{$INCLUDE def.inc}

unit Negotiate_u;

interface
uses
  Windows, Sysutils, WinSock, Func_u,
  Config_u, Protoc_u, SockLib_u, Console_u,
  Participants_u, IStats_u, HouLog_u;

type
  TNegotiate = class(TObject)
  private
    FAbort: Boolean;
    FConfig: PSendConfig;
    FParts: TParticipants;
    FStats: ISenderStats;
    FUSocket: TUDPSenderSocket;

    FConsole: TConsole;                 //控制会话Select

    FTransState: TTransState;
    procedure SetTransState(const Value: TTransState);
  protected
    FCapabilities: Integer;
  private
    //单点模式?
    function IsPointToPoint(): Boolean;

    //响应连接
    function SendConnectionReply(client: PSockAddrIn;
      capabilities: Integer; rcvbuf: DWORD_PTR): Integer;

    //检测条件是否复合(达到指定客户端)
    function CheckClientWait(firstConnected: PDWORD): Integer;

    //会话调度
    function MainDispatcher(var tries: Integer; firstConnected: PDWORD): Integer;
  public
    constructor Create(config: PSendConfig; TransStats: ISenderStats;
      PartsStats: IPartsStats);
    destructor Destroy; override;

    //会话控制
    function StartNegotiate(): Integer;
    function StopNegotiate(): Boolean;
    function PostDoTransfer(): Boolean;

    function SendHello(streaming: Boolean): Integer;

    //传输开始/结束
    procedure BeginTrans();
    procedure EndTrans();

    //会话状态
    property TransState: TTransState read FTransState write SetTransState;

    property Config: PSendConfig read FConfig;
    property USocket: TUDPSenderSocket read FUSocket;
    property Parts: TParticipants read FParts;
    property Stats: ISenderStats read FStats;
  end;

implementation

{ Negotiate }

constructor TNegotiate.Create;
begin
  FConfig := config;
  FConsole := TConsole.Create;
  FStats := TransStats;
  FParts := TParticipants.Create;
  FParts.PartsStats := PartsStats;
end;

destructor TNegotiate.Destroy;
begin
  if Assigned(FParts) then
    FParts.Free;
  if Assigned(FUSocket) then
    FUSocket.Free;
  if Assigned(FConsole) then
    FConsole.Free;
  inherited;
end;

function TNegotiate.IsPointToPoint(): Boolean;
begin
  if dmcPointToPoint in FConfig^.flags then
  begin
    if FParts.Count > 1 then
      raise Exception.CreateFmt('pointopoint mode set, and %d participants instead of 1',
        [FParts.Count]);
    Result := True;
  end
  else if (dmcNoPointToPoint in FConfig^.flags)
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

  reply.opCode := htons(Word(CMD_CONNECT_REPLY));
  reply.clNr := htonl(FParts.Add(client, capabilities, rcvbuf,
    dmcPointToPoint in FConfig^.flags));
  reply.blockSize := htonl(FConfig^.blockSize);
  reply.reserved := 0;
  reply.capabilities := ntohl(FCapabilities);

  FUSocket.CopyDataAddrToMsg(reply.mcastAddr);
  { reply.mcastAddress = mcastAddress; }
  //rgWaitAll(config, sock, client^.sin_addr.s_addr, SizeOf(reply));

  Result := FUSocket.SendCtrlMsgTo(reply, SizeOf(reply), client);
{$IFDEF DMC_ERROR_ON}
  if (Result < 0) then
    OutLog2(llError, 'reply add new client. error:' + IntToStr(GetLastError));
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
  hello.capabilities := htonl(FCapabilities);
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
    (DiffTickCount(firstConnected^, GetTickCount) > FConfig^.max_receivers_wait) then
  begin
{$IFDEF DMC_MSG_ON}
    OutLog2(llMsg, Format('max wait[%d] passed: starting',
      [FConfig^.max_receivers_wait]));
{$ENDIF}
    Result := 1;                        { send-wait passed: start }
    Exit;
  end
  else if (FParts.Count >= FConfig^.min_receivers) then
  begin
{$IFDEF DMC_MSG_ON}
    OutLog2(llMsg, Format('min receivers[%d] reached: starting',
      [FConfig^.min_receivers]));
{$ENDIF}
    Result := 1;
    Exit;
  end;
end;

//接收，处理消息

function TNegotiate.MainDispatcher(var tries: Integer; firstConnected: PDWORD): Integer;
var
  socket            : Integer;
  client            : TSockAddrIn;
  ctrlMsg           : TCtrlMsg;
  msgLength         : Integer;

  waitTime          : DWORD;
begin
  Result := 0;
  socket := 0;

  if (firstConnected <> nil) and (FParts.Count > 0) then
  begin
    firstConnected^ := GetTickCount;
  end;

  while (Result = 0) do
  begin
    if (FConfig^.rexmit_hello_interval > 0) then
      waitTime := FConfig^.rexmit_hello_interval
    else
      waitTime := INFINITE;

    socket := FConsole.SelectWithConsole(waitTime);
    if (socket < 0) then
    begin
      OutputDebugString('SelectWithConsole error');
      Result := -1;
      Exit;
    end;

    if FConsole.keyPressed then
    begin                               //key pressed
      Result := 1;
      Exit;
    end;

    if (socket > 0) then
      Break;                            // receiver activity

    if (FConfig^.rexmit_hello_interval > 0) then
    begin
      { retransmit hello message }
      sendHello(False);
    end;

    if (firstConnected <> nil) then
      Result := Result or checkClientWait(firstConnected);
  end;                                  //end while

  if socket <= 0 then
    Exit;

  //有客户连接
  Result := 0;
  FillChar(ctrlMsg, SizeOf(ctrlMsg), 0);

  msgLength := FUSocket.RecvCtrlMsg(ctrlMsg, SizeOf(ctrlMsg), client);
  if (msgLength < 0) then
  begin
{$IFDEF DMC_ERROR_ON}
    OutLog2(llError, Format('RecvCtrlMsg Error! %d', [GetLastError]));
{$ENDIF}
    Exit;                               { don't panic if we get weird messages }
  end;

  if dmcAsyncMode in FConfig^.flags then
    Exit;

  case TOpCode(ntohs(ctrlMsg.opCode)) of
    CMD_CONNECT_REQ:
      begin
        sendConnectionReply(@client,
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
{$IFDEF DMC_WARN_ON}
  else
    OutLog2(llWarn, Format('Unexpected command %-.4x',
      [ntohs(ctrlMsg.opCode)]));
{$ENDIF}
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
  TransState := tsNego;

  tries := 0;
  Result := 0;
  firstConnected := 0;

  { make the socket and print banner }
  tryFullDuplex := not (dmcFullDuplex in FConfig^.flags)
    and not (dmcNotFullDuplex in FConfig^.flags);

  FUSocket := TUDPSenderSocket.Create(@FConfig^.net,
    dmcPointToPoint in FConfig^.flags, tryFullDuplex);

  if tryFullDuplex then
    FConfig^.flags := FConfig^.flags + [dmcFullDuplex];

{$IFDEF DMC_MSG_ON}
  if dmcFullDuplex in FConfig^.flags then
    OutLog2(llMsg, 'Using full duplex mode');

  OutLog2(llMsg, PAnsiChar(Format('Broadcasting control to %s:%d',
    [inet_ntoa(FUSocket.CtrlAddr.sin_addr), FConfig^.net.remotePort])));

  OutLog2(llMsg, PAnsiChar(Format('DMC Sender at %s:%d on %s',
    [inet_ntoa(FUSocket.NetIf.addr),
    FConfig^.net.localPort, FUSocket.NetIf.name])));
{$ENDIF}

  FCapabilities := SENDER_CAPABILITIES;
  if dmcAsyncMode in FConfig^.flags then
    FCapabilities := FCapabilities or CAP_ASYNC;

  SendHello(False);

  if (FConfig^.min_receivers > 0) or (FConfig^.max_receivers_wait > 0) then
    firstConnectedP := @firstConnected
  else
    firstConnectedP := nil;

  //开始分派
  FConsole.Start(FUSocket.Socket, False);
  while True do
  begin
    Result := MainDispatcher(tries, firstConnectedP);
    if Result <> 0 then
      Break;
  end;
  if FConsole.keyPressed and (FConsole.Key = 'q') then
    Halt;                               //手动退出
  FConsole.Stop;

  if (Result = 1) then
  begin
    if not (dmcAsyncMode in FConfig^.flags) and (FParts.Count <= 0) then
    begin
      Result := 0;
{$IFDEF DMC_MSG_ON}
      OutLog2(llMsg, 'No participants... exiting.');
{$ENDIF}
    end;
  end;

  if FAbort then
  begin
    Result := -1;
    EndTrans;
  end;
end;

function TNegotiate.StopNegotiate: Boolean;
begin
  Result := not FAbort;
  FAbort := True;
  if Assigned(FConsole) then
    Result := FConsole.PostPressed;
end;

procedure TNegotiate.BeginTrans();
var
  i                 : Integer;
  isPtP             : Boolean;
  // pRcvBuf           : DWORD_PTR;
begin
  isPtP := IsPointToPoint();

  //FConfig^.rcvbuf := 0;

  for i := 0 to MAX_CLIENTS - 1 do
    if FParts.IsValid(i) then
    begin
      // pRcvBuf := FParts.GetRcvBuf(i);
      if isPtP then
        FUSocket.SetDataAddr(FParts.GetAddr(i)^.sin_addr);

      //取共同特性
      FCapabilities := FCapabilities and FParts.GetCapabilities(i);

      //      if (pRcvBuf <> 0) and ((FConfig^.rcvbuf = 0)
      //        or (FConfig^.rcvbuf > pRcvBuf)) then
      //        FConfig^.rcvbuf := pRcvBuf;
    end;

{$IFDEF DMC_MSG_ON}
  OutLog2(llMsg, PAnsiChar(Format('Starting transfer.[Capabilities: %-.8x]',
    [FCapabilities])));

  OutLog2(llMsg, PAnsiChar('Data address ' + inet_ntoa(FUSocket.DataAddr.sin_addr)));
{$ENDIF}

  if not LongBool(FCapabilities and CAP_NEW_GEN) then
  begin                                 //不支持组播，双工...
    FUSocket.SetDataAddr(FUSocket.CtrlAddr.sin_addr);
    FConfig^.flags := FConfig^.flags - [dmcFullDuplex, dmcNotFullDuplex];
  end
  else
  begin
    if not (dmcAsyncMode in FConfig^.flags) and
      not (dmcStreamMode in FConfig^.flags) then
    begin                               //不是异步或流模式(接收者固定)
      if FUSocket.CtrlAddr.sin_addr.S_addr <> FUSocket.DataAddr.sin_addr.S_addr then
      begin                             //重设控制地址
        FUSocket.CopyIpFrom(@FUSocket.CtrlAddr, @FUSocket.DataAddr);
{$IFDEF DMC_MSG_ON}
        OutLog2(llMsg, PAnsiChar('Reset control to ' + inet_ntoa(FUSocket.CtrlAddr.sin_addr)));
{$ENDIF}
      end;
    end;
  end;
end;

procedure TNegotiate.EndTrans();
var
  i                 : Integer;
begin
  { remove all participants }
  for i := 0 to MAX_CLIENTS - 1 do
    FParts.Remove(i);
end;

function TNegotiate.PostDoTransfer: Boolean;
begin
  Result := FConsole.PostPressed;
end;

procedure TNegotiate.SetTransState(const Value: TTransState);
begin
  FTransState := Value;
  FStats.TransStateChange(Value);
end;

end.

