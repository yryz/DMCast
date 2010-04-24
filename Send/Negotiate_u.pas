unit Negotiate_u;

interface
uses
  Windows, Sysutils, WinSock, Func_u,
  Config_u, Protoc_u, SockLib_u, Console_u,
  Participants_u, SendData_u,
  IStats_u, INegotiate_u;

type                                    //不要直接使用对象,容易出错
  TNegotiate = class(TInterfacedObject, INegotiate)
  private
    FUSocket: TUDPSocket;
    FConfig: PNetConfig;
    FDp: TDataPool;
    FRc: TRChannel;
    FSender: TSender;
    FParts: TParticipants;
    FStats: ISenderStats;
    FOverEvent: THandle;
    FConsole: TConsole;                 //控制会话Select
  private
    function IsPointToPoint(): Boolean;
    function SendConnectionReply(client: PSockAddrIn;
      capabilities: Integer; rcvbuf: DWORD_PTR): Integer;
    function CheckClientWait(firstConnected: PDWORD): Integer;
    function MainDispatcher(fd: PIntegerArray; nr: Integer;
      var tries: Integer; firstConnected: PDWORD): Integer;
  public
    constructor Create(config: PNetConfig; Stats: ISenderStats);
    destructor Destroy; override;
    function StartNegotiate(): Integer;
    function StopNegotiate(): Boolean;
    function SendHello(streaming: Boolean): Integer;
    procedure DoTransfer();
    function AbortTransfer(waitTime: DWORD): Boolean;
  end;

implementation

{ Negotiate }

constructor TNegotiate.Create(config: PNetConfig; Stats: ISenderStats);
begin
  FConfig := config;
  FStats := Stats;
  FParts := TParticipants.Create;
  FOverEvent := CreateEvent(nil, True, False, nil);
  FConsole := TConsole.Create;
end;

destructor TNegotiate.Destroy;
begin
  FreeAndNil(FConsole);
  SetEvent(FOverEvent);
  CloseHandle(FOverEvent);
  if Assigned(FParts) then FreeAndNil(FParts);
  if Assigned(FUSocket) then FreeAndNil(FUSocket);
  inherited;
end;

function TNegotiate.IsPointToPoint(): Boolean;
begin
  if Boolean(FConfig^.flags and FLAG_POINTOPOINT) then begin
    if FParts.Count > 1 then
      raise Exception.CreateFmt('pointopoint mode set, and %d participants instead of 1',
        [FParts.Count]);
    Result := True;
  end else
    if Boolean(FConfig^.flags and (FLAG_NOPOINTOPOINT or FLAG_ASYNC or FLAG_BCAST)) then
      Result := False
    else
      Result := FParts.Count = 1;
end;

function TNegotiate.SendConnectionReply(client: PSockAddrIn; capabilities: Integer;
  rcvbuf: DWORD_PTR): Integer;
var
  reply             : TConnectReply;
begin
  if (rcvbuf = 0) then
    rcvbuf := 65536;

  if Boolean(capabilities and CAP_BIG_ENDIAN) then begin
    reply.opCode := htons(Word(CMD_CONNECT_REPLY));
    reply.clNr := htonl(FParts.Add(client,
      capabilities,
      rcvbuf,
      Boolean(FConfig^.flags and FLAG_POINTOPOINT)));
    reply.blockSize := htonl(FConfig^.blockSize);
  end else begin
    raise Exception.Create('Little endian protocol no longer supported');
  end;
  reply.reserved := 0;

  { new parameters: always big endian }
  reply.capabilities := ntohl(FConfig^.capabilities);
  TUDPSocket.CopyIpToMessage(@FUSocket.DataAddr, reply.mcastAddr);
  { reply.mcastAddress = mcastAddress; }
  //rgWaitAll(config, sock, client^.sin_addr.s_addr, SizeOf(reply));

  Result := FUSocket.SendCtrlMsg(reply, SizeOf(reply), client);
  if (Result < 0) then begin
{$IFDEF CONSOLE}
    WriteLn('reply add new client. error:', GetLastError);
{$ENDIF}
  end;
end;

function TNegotiate.SendHello(streaming: Boolean): Integer;
var
  hello             : THello;
begin
  { send hello message }
  if (streaming) then
    hello.opCode := htons(Word(CMD_HELLO_STREAMING))
  else
    hello.opCode := htons(Word(CMD_HELLO));
  hello.reserved := 0;
  hello.capabilities := htonl(FConfig^.capabilities);
  FUSocket.CopyIpToMessage(@FUSocket.DataAddr, hello.mcastAddr);
  hello.blockSize := htons(FConfig^.blockSize);
  //rgWaitAll(net_config, sock, FConfig^.controlMcastAddr.sin_addr.s_addr, SizeOf(hello));
  //发送控制
  Result := FUSocket.SendCtrlMsgCast(hello, SizeOf(hello));
end;

function TNegotiate.CheckClientWait(firstConnected: PDWORD): Integer;
begin
  Result := 0;
  if (FParts.Count < 1) or (firstConnected = nil) then
    Exit;                               { do not start: no receivers }
  {
   * If we have a max_client_wait, start the transfer after first client
   * connected + maxSendWait
   }
  if (FConfig^.max_receivers_wait > 0) and
    (DiffTickCount(firstConnected^, GetTickCount) > FConfig^.max_receivers_wait) then begin
{$IFDEF USE_SYSLOG}
    syslog(LOG_INFO, 'max wait[%d] passed: starting',
      FConfig^.max_receivers_wait);
{$ENDIF}
    Result := 1;                        { send-wait passed: start }
    Exit;
  end

    {
     * Otherwise check to see if the minimum of clients
     *  have checked in.
     }
  else if (FParts.Count >= FConfig^.min_receivers) and
    {
*  If there are enough clients and there's a min wait time, we'll
*  wait around anyway until then.
*  Otherwise, we always transfer
}
  ((FConfig^.min_receivers_wait = 0) or
    (DiffTickCount(firstConnected^, GetTickCount) >= FConfig^.min_receivers_wait)) then begin
{$IFDEF USE_SYSLOG}
    syslog(LOG_INFO, 'min receivers[%d] reached: starting',
      FConfig^.min_receivers);
{$ENDIF}
    Result := 1;
    Exit;
  end;
end;

{ *****************************************************
 * Receive and process a localization enquiry by a client
 * Params:
 * fd		- file descriptor for network socket on which to receiver
 *		client requests
 * db		- participant database
 * disk_config	- disk configuration
 * net_config	- network configuration
 * keyboardFd	- keyboard filedescriptor (-1 if keyboard inaccessible,
 *		or configured away)
 * tries	- how many hello messages have been sent?
 * firstConnected - when did the first client connect?
 }

function TNegotiate.MainDispatcher(fd: PIntegerArray; nr: Integer;
  var tries: Integer; firstConnected: PDWORD): Integer;
var
  ret               : Integer;

  client            : TSockAddrIn;
  fromClient        : TCtrlMsg;
  read_set          : TFDSet;
  msgLength         : Integer;
  loopStart         : DWORD;

  maxFd, selected   : Integer;

  tv                : TTimeVal;
  tvp               : PTimeVal;
begin
  Result := 0;
  loopStart := GetTickCount;

  if (FParts.Count > 0) or Boolean(FConfig^.flags and FLAG_ASYNC)
    and not Boolean(FConfig^.flags and FLAG_NOKBD) then
  begin
{$IFDEF CONSOLE}
    WriteLn('Ready. Press return to start sending data.');
{$ENDIF}
  end;

  if (firstConnected <> nil) and (FParts.Count > 0) then begin
    firstConnected^ := GetTickCount;
{$IFDEF USE_SYSLOG }
    syslog(LOG_INFO,
      'first connection: min wait[%d] secs - max wait[%d] - min clients[%d]',
      FConfig^.min_receivers_wait, FConfig^.max_receivers_wait,
      FConfig^.min_receivers);
{$ENDIF}
  end;

  while (Result = 0) do begin
    maxFd := prepareForSelect(fd, nr, @read_set);

    if (FConfig^.rexmit_hello_interval > 0) then begin
      tv.tv_usec := (FConfig^.rexmit_hello_interval mod 1000) * 1000;
      tv.tv_sec := FConfig^.rexmit_hello_interval div 1000;
      tvp := @tv;
    end else if (firstConnected <> nil) and (FParts.Count > 0)
      or (FConfig^.startTimeout > 0) then begin
      tv.tv_usec := 0;
      tv.tv_sec := 2;
      tvp := @tv;
    end else
      tvp := nil;

    Inc(maxFd);
    selected := FConsole.SelectWithConsole(maxFd, read_set, tvp);
    if (selected < 0) then begin
      Result := -1;
      OutputDebugString('select error');
      Exit;
    end;

    if FConsole.keyPressed then begin   //key pressed
      Result := 1;
      Exit;
    end;

    if (selected > 0) then              // receiver activity
      Break;

    if (FConfig^.rexmit_hello_interval > 0) then begin
      { retransmit hello message }
      sendHello(False);
      Inc(tries);
      if (FConfig^.autostart <> 0) and (tries > FConfig^.autostart) then
        Result := 1;
    end;

    if (firstConnected <> nil) then
      Result := Result or checkClientWait(firstConnected);

    if (Result <> 0) and (FConfig^.startTimeout > 0) and
      (GetTickCount - loopStart >= FConfig^.startTimeout) then begin
      Result := -1;
      Break;
    end;
  end;                                  //end while

  //有客户连接
  FillChar(fromClient, SizeOf(fromClient), 0); { Zero it out in order to cope with short messages
  * from older versions }

  msgLength := FUSocket.RecvCtrlMsg(fromClient, client);
  if (msgLength < 0) then begin
{$IFDEF CONSOLE}
    WriteLn('problem getting data from client.errorno:', GetLastError);
{$ENDIF}
    Result := 0;
    Exit;                               { don't panic if we get weird messages }
  end;

  if Boolean(FConfig^.flags and FLAG_ASYNC) then
  begin
    Result := 0;
    Exit;
  end;

  case TOpCode(ntohs(fromClient.opCode)) of
    CMD_CONNECT_REQ:
      begin
        sendConnectionReply(@client,
          CAP_BIG_ENDIAN or
          ntohl(fromClient.connectReq.capabilities),
          ntohl(fromClient.connectReq.rcvbuf));
      end;

    CMD_GO:
      begin
        Result := 1;
      end;

    CMD_DISCONNECT:
      begin
        ret := FParts.Lookup(@client);
        if (ret >= 0) then
          FParts.Remove(ret);
      end;
  else begin
{$IFDEF CONSOLE}
      WriteLn(Format('Unexpected command %-.4x',
        [fromClient.opCode]));
{$ENDIF}
    end;
  end;
end;

function TNegotiate.StartNegotiate(): Integer;
var
  tries             : Integer;
  r                 : Integer;          { return value for maindispatch. If 1, start transfer }
  firstConnected    : DWORD;
  firstConnectedP   : PDWORD;
begin
  r := 0;
  tries := 0;
  Result := 0;
  firstConnected := 0;

  { make the socket and print banner }
  FUSocket := TUDPSocket.Create(FConfig, True);

{$IFDEF CONSOLE}
  //if disk_config^.pipeName = nil then Write('Compressed ');
  Write('UDP sender for ');
  //if disk_config^.fileName = nil then Write('(stdin)')
  //else
  Write(FConfig^.fileName);
  Write(' at ');
  Write(inet_ntoa(FUSocket.NetIf.addr));
  WriteLn(' on ', FUSocket.NetIf.name);
  WriteLn('Broadcasting control to ', inet_ntoa(FUSocket.CtrlAddr.sin_addr));
{$ENDIF}

  FConfig^.capabilities := SENDER_CAPABILITIES;
  if Boolean(FConfig^.flags and FLAG_ASYNC) then
    FConfig^.capabilities := FConfig^.capabilities or CAP_ASYNC;

  SendHello(False);

  if (FConfig^.min_receivers > 0) or (FConfig^.min_receivers_wait > 0) or
    (FConfig^.max_receivers_wait > 0) then
    firstConnectedP := @firstConnected
  else
    firstConnectedP := nil;

  //开始分派
  FConsole.Start(not Boolean(FConfig^.flags and FLAG_NOKBD)); //
  while True do begin
    r := MainDispatcher(@FUSocket.Socket, 1, tries, firstConnectedP);
    if r <> 0 then Break;
  end;
  if FConsole.keyPressed and (FConsole.Key = 'q') then Halt; //手动退出
  FConsole.Stop;

  if (r = 1) then begin
    if Boolean(FConfig^.flags and FLAG_ASYNC) or (FParts.Count > 0) then
      Result := 1
    else begin
{$IFDEF CONSOLE}
      WriteLn('No participants... exiting.');
{$ENDIF}
    end;
  end;
end;

function TNegotiate.StopNegotiate: Boolean;
begin
  Result := False;
  if Assigned(FConsole) then
    Result := FConsole.PostPress(#0);
end;

procedure TNegotiate.DoTransfer();
var
  i                 : Integer;
  isPtP             : Boolean;
  pRcvBuf           : DWORD_PTR;
begin
  isPtP := IsPointToPoint();

  FConfig^.rcvbuf := 0;

  for i := 0 to MAX_CLIENTS - 1 do
    if FParts.IsValid(i) then begin
      pRcvBuf := FParts.GetRcvBuf(i);
      if isPtP then
        FUSocket.SetDataAddr(FParts.GetAddr(i)^.sin_addr);

      FConfig^.capabilities := FConfig^.capabilities
        and FParts.GetCapabilities(i);

      if (pRcvBuf <> 0) and ((FConfig^.rcvbuf = 0)
        or (FConfig^.rcvbuf > pRcvBuf)) then
        FConfig^.rcvbuf := pRcvBuf;
    end;

{$IFDEF CONSOLE}
  WriteLn(Format('Starting transfer.[Capabilities: %-.8x]', [FConfig^.capabilities]));
{$ENDIF}

  if not Boolean(FConfig^.capabilities and CAP_BIG_ENDIAN) then
    raise Exception.Create('Peer with incompatible endianness');

  if not Boolean(FConfig^.capabilities and CAP_NEW_GEN) then
  begin                                 //不支持组播，又工...
    FUSocket.SetDataAddr(FUSocket.CtrlAddr.sin_addr);
    FConfig^.flags := FConfig^.flags and not (FLAG_SN or FLAG_ASYNC);
  end else
  begin
    if not Boolean(FConfig^.flags and (FLAG_STREAMING or FLAG_ASYNC)) then
    begin                               //不是异步或流模式
      if FUSocket.CtrlAddr.sin_addr.S_addr <> FUSocket.DataAddr.sin_addr.S_addr then
      begin                             //重设控制地址
        FUSocket.CopyIpFrom(@FUSocket.CtrlAddr, @FUSocket.DataAddr);
{$IFDEF CONSOLE}
        WriteLn('Reset control to ', inet_ntoa(FUSocket.CtrlAddr.sin_addr));
{$ENDIF}
      end;
    end;
  end;

  FDp := TDataPool.Create(FConfig, FStats);
  FRc := TRChannel.Create(FConfig, FUSocket, FDp, FParts);
  FSender := TSender.Create(FConfig, FDp, FRc, FParts, FStats);
  FDp.InitData(FRc, FUSocket, Self);

  FDp.Resume;                           //唤醒数据池
  FRc.Resume;                           //唤醒反馈隧道
  Sleep(0);                             //保证工作线程先启动
  //Sender.Resume;

  FSender.Execute;                      //执行发送
  SetEvent(FOverEvent);

  FUSocket.Close;
  FRc.Terminate;
  FDp.Terminate;
  FreeAndNil(FSender);
  FreeAndNil(FRc);
  FreeAndNil(FDp);

{$IFDEF CONSOLE}
  WriteLn(#13#10'Transfer complete.');
{$ENDIF}
{$IFDEF USE_SYSLOG}
  syslog(LOG_INFO, 'Transfer complete.');
{$ENDIF}

  { remove all participants }
  for i := 0 to MAX_CLIENTS - 1 do
    FParts.Remove(i);
end;

function TNegotiate.AbortTransfer(waitTime: DWORD): Boolean;
begin
  if Assigned(FSender) then begin
    FSender.Terminated := True;
    FUSocket.Close;
    FRc.Terminate;
    FDp.Terminate;
    Result := WaitForSingleObject(FOverEvent, waitTime) = WAIT_OBJECT_0;
  end else
    Result := True;
end;

end.

