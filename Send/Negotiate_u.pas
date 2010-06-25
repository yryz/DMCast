{$INCLUDE def.inc}

unit Negotiate_u;

interface
uses
  Windows, Sysutils, WinSock, Func_u,
  Config_u, Protoc_u, SockLib_u, Console_u,
  Participants_u, SendData_u, Fifo_u,
  IStats_u, INegotiate_u;

type                                    //不要直接使用对象,容易出错
  TNegotiate = class(TInterfacedObject, INegotiate)
  private
    FAbort: Boolean;
    FUSocket: TUDPSenderSocket;
    FConfig: PNetConfig;
    FIo: TDiskIO;
    FDp: TDataPool;
    FRc: TRChannel;
    FSender: TSender;
    FParts: TParticipants;
    FStats: ITransStats;
    FOverEvent: THandle;
    FConsole: TConsole;                 //控制会话Select
  private
    function IsPointToPoint(): Boolean;
    function SendConnectionReply(client: PSockAddrIn;
      capabilities: Integer; rcvbuf: DWORD_PTR): Integer;
    function CheckClientWait(firstConnected: PDWORD): Integer;
    function MainDispatcher(var tries: Integer; firstConnected: PDWORD): Integer;
  public
    constructor Create(config: PNetConfig; Console: TConsole; Stats: ITransStats;
      OnPartsChange: TOnPartsChange);
    destructor Destroy; override;
    function StartNegotiate(): Integer;
    function StopNegotiate(): Boolean;
    function SendHello(streaming: Boolean): Integer;
    procedure DoTransfer();
    function AbortTransfer(waitTime: DWORD): Boolean;
  end;

implementation

{ Negotiate }

constructor TNegotiate.Create;
begin
  FConfig := config;
  FConsole := Console;
  FStats := Stats;
  FParts := TParticipants.Create;
  FParts.OnPartsChange := OnPartsChange;
  FOverEvent := CreateEvent(nil, True, False, nil);
end;

destructor TNegotiate.Destroy;
begin
  SetEvent(FOverEvent);
  CloseHandle(FOverEvent);
  if Assigned(FParts) then FParts.Free;
  if Assigned(FUSocket) then FreeAndNil(FUSocket);
  inherited;
end;

function TNegotiate.IsPointToPoint(): Boolean;
begin
  if dmcPointToPoint in FConfig^.flags then begin
    if FParts.Count > 1 then
      raise Exception.CreateFmt('pointopoint mode set, and %d participants instead of 1',
        [FParts.Count]);
    Result := True;
  end else
    if (dmcNoPointToPoint in FConfig^.flags)
      and (dmcAsyncMode in FConfig^.flags)
      and (dmcBCastMode in FConfig^.flags) then
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

  if LongBool(capabilities and CAP_BIG_ENDIAN) then begin
    reply.opCode := htons(Word(CMD_CONNECT_REPLY));
    reply.clNr := htonl(FParts.Add(client, capabilities, rcvbuf,
      dmcPointToPoint in FConfig^.flags));
    reply.blockSize := htonl(FConfig^.blockSize);
  end else begin
    raise Exception.Create('Little endian protocol no longer supported');
  end;
  reply.reserved := 0;

  { new parameters: always big endian }
  reply.capabilities := ntohl(FConfig^.capabilities);
  FUSocket.CopyDataAddrToMsg(reply.mcastAddr);
  { reply.mcastAddress = mcastAddress; }
  //rgWaitAll(config, sock, client^.sin_addr.s_addr, SizeOf(reply));

  Result := FUSocket.SendCtrlMsgTo(reply, SizeOf(reply), client);
{$IFDEF DMC_ERROR_ON}
  if (Result < 0) then
    FStats.Msg(umtError, 'reply add new client. error:' + IntToStr(GetLastError));
{$ENDIF}
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
  FUSocket.CopyDataAddrToMsg(hello.mcastAddr);
  hello.blockSize := htons(FConfig^.blockSize);
  //rgWaitAll(net_config, sock, FConfig^.controlMcastAddr.sin_addr.s_addr, SizeOf(hello));
  //发送控制
  Result := FUSocket.SendCtrlMsg(hello, SizeOf(hello));
end;

function TNegotiate.CheckClientWait(firstConnected: PDWORD): Integer;
begin
  Result := 0;
  if (FParts.Count < 1) or (firstConnected = nil) then
    Exit;                               { do not start: no receivers }
  if (FConfig^.max_receivers_wait > 0) and
    (DiffTickCount(firstConnected^, GetTickCount) > FConfig^.max_receivers_wait) then begin
{$IFDEF USE_SYSLOG}
    syslog(LOG_INFO, 'max wait[%d] passed: starting',
      FConfig^.max_receivers_wait);
{$ENDIF}
    Result := 1;                        { send-wait passed: start }
    Exit;
  end
  else if (FParts.Count >= FConfig^.min_receivers)
    and ((FConfig^.min_receivers_wait = 0)
    or (DiffTickCount(firstConnected^, GetTickCount) >= FConfig^.min_receivers_wait)) then begin
{$IFDEF USE_SYSLOG}
    syslog(LOG_INFO, 'min receivers[%d] reached: starting',
      FConfig^.min_receivers);
{$ENDIF}
    Result := 1;
    Exit;
  end;
end;

//接收，处理消息

function TNegotiate.MainDispatcher(var tries: Integer; firstConnected: PDWORD): Integer;
var
  selected          : Integer;
  client            : TSockAddrIn;
  ctrlMsg           : TCtrlMsg;
  msgLength         : Integer;
  loopStart         : DWORD;

  waitTime          : DWORD;
begin
  Result := 0;
  loopStart := GetTickCount;

  if (FParts.Count > 0) or (dmcAsyncMode in FConfig^.flags)
    and not (dmcNoKeyBoard in FConfig^.flags) then
  begin
{$IFDEF DMC_MSG_ON}
    FStats.Msg(umtMsg, 'Ready. Press return to start sending data.');
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

  while (Result = 0) do
  begin
    if (FConfig^.rexmit_hello_interval > 0) then begin
      waitTime := FConfig^.rexmit_hello_interval;
    end else if (firstConnected <> nil) and (FParts.Count > 0)
      or (FConfig^.startTimeout > 0) then begin
      waitTime := 2000;
    end else
      waitTime := INFINITE;

    selected := FConsole.SelectWithConsole(waitTime);
    if (selected < 0) then begin
      OutputDebugString('SelectWithConsole error');
      Result := -1;
      Exit;
    end;

    if FConsole.keyPressed then begin   //key pressed
      Result := 1;
      Exit;
    end;

    if (selected > 0) then Break;       // receiver activity

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
      (DiffTickCount(loopStart, GetTickCount) >= FConfig^.startTimeout) then begin
      Result := -1;
    end;
  end;                                  //end while

  if selected < 1 then Exit;
  //有客户连接
  Result := 0;
  FillChar(ctrlMsg, SizeOf(ctrlMsg), 0); { Zero it out in order to cope with short messages
  * from older versions }

  msgLength := FUSocket.RecvCtrlMsg(ctrlMsg, SizeOf(ctrlMsg), client);
  if (msgLength < 0) then begin
{$IFDEF DMC_ERROR_ON}
    FStats.Msg(umtError, Format('RecvCtrlMsg Error! %d', [GetLastError]));
{$ENDIF}
    Exit;                               { don't panic if we get weird messages }
  end;

  if dmcAsyncMode in FConfig^.flags then
    Exit;

  case TOpCode(ntohs(ctrlMsg.opCode)) of
    CMD_CONNECT_REQ:
      begin
        sendConnectionReply(@client,
          CAP_BIG_ENDIAN or
          ntohl(ctrlMsg.connectReq.capabilities),
          ntohl(ctrlMsg.connectReq.rcvbuf));
      end;

    CMD_GO:
      begin
        Result := 1;
      end;

    CMD_DISCONNECT:
      begin
        FParts.Remove(FParts.Lookup(@client));
      end;
  else begin
{$IFDEF DMC_WARN_ON}
      FStats.Msg(umtWarn, Format('Unexpected command %-.4x',
        [ntohs(ctrlMsg.opCode)]));
{$ENDIF}
    end;
  end;
end;

function TNegotiate.StartNegotiate(): Integer; // If Result=1. start transfer
var
  tries             : Integer;
  firstConnected    : DWORD;
  firstConnectedP   : PDWORD;
  tryFullDuplex     : Boolean;
begin
  FAbort := False;

  tries := 0;
  Result := 0;
  firstConnected := 0;

  { make the socket and print banner }
  tryFullDuplex := not (dmcFullDuplex in FConfig^.flags)
    and not (dmcNotFullDuplex in FConfig^.flags);

  FUSocket := TUDPSenderSocket.Create(FConfig,
    dmcPointToPoint in FConfig^.flags, tryFullDuplex);

  if tryFullDuplex then
    FConfig^.flags := FConfig^.flags + [dmcFullDuplex];

{$IFDEF DMC_MSG_ON}
  if dmcFullDuplex in FConfig^.flags then
    FStats.Msg(umtMsg, 'Using full duplex mode');

  FStats.Msg(umtMsg, Format('Broadcasting control to %s:%d',
    [inet_ntoa(FUSocket.CtrlAddr.sin_addr), FConfig^.remotePort]));

  FStats.Msg(umtMsg, Format('DMC Sender for %s at %s:%d on %s',
    [FConfig^.fileName, inet_ntoa(FUSocket.NetIf.addr),
    FConfig^.localPort, FUSocket.NetIf.name]));
{$ENDIF}

  FConfig^.capabilities := SENDER_CAPABILITIES;
  if dmcAsyncMode in FConfig^.flags then
    FConfig^.capabilities := FConfig^.capabilities or CAP_ASYNC;

  SendHello(False);

  if (FConfig^.min_receivers > 0) or (FConfig^.min_receivers_wait > 0) or
    (FConfig^.max_receivers_wait > 0) then
    firstConnectedP := @firstConnected
  else
    firstConnectedP := nil;

  //开始分派
  FConsole.Start(FUSocket.Socket, not (dmcNoKeyBoard in FConfig^.flags));
  while True do begin
    Result := MainDispatcher(tries, firstConnectedP);
    if Result <> 0 then Break;
  end;
  if FConsole.keyPressed and (FConsole.Key = 'q') then Halt; //手动退出
  FConsole.Stop;

  if (Result = 1) then begin
    if not (dmcAsyncMode in FConfig^.flags) and (FParts.Count <= 0) then
    begin
      Result := 0;
{$IFDEF DMC_MSG_ON}
      FStats.Msg(umtMsg, 'No participants... exiting.');
{$ENDIF}
    end;
  end;

  if FAbort then Result := -1;
end;

function TNegotiate.StopNegotiate: Boolean;
begin
  Result := not FAbort;
  FAbort := True;
  if Assigned(FConsole) then
    Result := FConsole.PostPressed;
end;

procedure TNegotiate.DoTransfer();
var
  i                 : Integer;
  isPtP             : Boolean;
  pRcvBuf           : DWORD_PTR;
  hFile             : THandle;
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

{$IFDEF DMC_MSG_ON}
  FStats.Msg(umtMsg, Format('Starting transfer.[Capabilities: %-.8x]',
    [FConfig^.capabilities]));

  FStats.Msg(umtMsg, 'Data address ' + inet_ntoa(FUSocket.DataAddr.sin_addr));
{$ENDIF}

  if not LongBool(FConfig^.capabilities and CAP_BIG_ENDIAN) then
    raise Exception.Create('Peer with incompatible endianness');

  if not LongBool(FConfig^.capabilities and CAP_NEW_GEN) then
  begin                                 //不支持组播，双工...
    FUSocket.SetDataAddr(FUSocket.CtrlAddr.sin_addr);
    FConfig^.flags := FConfig^.flags - [dmcFullDuplex, dmcNotFullDuplex];
  end else
  begin
    if not (dmcAsyncMode in FConfig^.flags) and
      not (dmcStreamMode in FConfig^.flags) then
    begin                               //不是异步或流模式(接收者固定)
      if FUSocket.CtrlAddr.sin_addr.S_addr <> FUSocket.DataAddr.sin_addr.S_addr then
      begin                             //重设控制地址
        FUSocket.CopyIpFrom(@FUSocket.CtrlAddr, @FUSocket.DataAddr);
{$IFDEF DMC_MSG_ON}
        FStats.Msg(umtMsg, 'Reset control to ' + inet_ntoa(FUSocket.CtrlAddr.sin_addr));
{$ENDIF}
      end;
    end;
  end;

  FIo := TDiskIO.Create(FConfig^.fileName, FConfig^.blockSize, True);
  FDp := TDataPool.Create(FConfig, FStats);
  FRc := TRChannel.Create(FConfig, FUSocket, FDp, FParts, FStats);
  FSender := TSender.Create(FConfig, FDp, FRc, FParts, FStats);
  FDp.Open(FIo, FRc, FUSocket, Self);

  FIo.Resume;                           //唤醒数据IO
  FRc.Resume;                           //唤醒反馈隧道

  FSender.Execute;                      //执行发送
  SetEvent(FOverEvent);

  FDp.Close;
  FUSocket.Close;
  FRc.Terminate;
  FIo.Terminate;
  FreeAndNil(FSender);
  FreeAndNil(FRc);
  FreeAndNil(FDp);
  FreeAndNil(FIo);
{$IFDEF DMC_MSG_ON}
  FStats.Msg(umtMsg, 'Transfer complete.');
{$ENDIF}

  { remove all participants }
  for i := 0 to MAX_CLIENTS - 1 do
    FParts.Remove(i);
end;

function TNegotiate.AbortTransfer(waitTime: DWORD): Boolean;
begin
  if Assigned(FSender) then begin
    FSender.Terminated := True;
    FDp.Close;
    FUSocket.Close;
    FRc.Terminate;
    FIo.Terminate;
    Result := WaitForSingleObject(FOverEvent, waitTime) = WAIT_OBJECT_0;
  end else
    Result := StopNegotiate;
end;

end.

