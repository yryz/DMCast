{$INCLUDE def.inc}

unit Negotiate_u;

interface
uses
  Windows, Sysutils, WinSock, Func_u,
  Config_u, Protoc_u, SockLib_u, Console_u,
  Participants_u, Route_u, HouLog_u;

const
  USecPerMSec       = 1000;

type
  TNegotiate = class(TObject)
  private
    FAbort: Boolean;
    FConfig: TSendConfig;
    FParts: TParticipants;
    FUSocket: TUDPSenderSocket;

    FConsole: TConsole;                 //控制会话Select

    FTransState: TTransState;
    FOnTransStateChange: TOnTransStateChange;
    procedure SetTransState(const Value: TTransState);
  protected
    FDmcMode: Word;
    FCapabilities: Word;

    { 统计 }
    FStatsTotalBytes: Int64;
    FStatsBlockRetrans: Int64;

    { 速率 }
    FXmitRate: Double;                  //限制多少 byte/us
    FXmitWaitTime: Integer;             //传输等待时间(us)
    FXmitLastTick: DWORD;               //最后传输片的时间(us)(用于计算程序自身开销)
    FXmitRateTimer: THandle;

    { 传输控制 }
    FCtrlWaitHandle: THandle;

    procedure XmitRateSet(kb: Integer); //限速设置(kb/s)
  private
    //单点模式?
    function IsPointToPoint(): Boolean;

    //检测条件是否复合(达到指定客户端)
    function CheckClientWait(firstConnected: PDWORD): Integer;

    //会话调度
    function MainDispatcher(var tries: Integer; firstConnected: PDWORD): Integer;
  public
    constructor Create(config: PSendConfig; OnTransStateChange: TOnTransStateChange;
      OnPartsChange: TOnPartsChange);
    destructor Destroy; override;

    //会话控制
    function StartNegotiate(): Integer;
    function StopNegotiate(): Boolean;
    //控制(暂停/继续)
    procedure WaitForCtrl();
    procedure TransferCtrl(transCtrl: TTransmitCtrl);

    //Hello
    function SendHello(streaming: Boolean): Integer;
    //响应连接请求
    function SendConnectionReply(client: PSockAddrIn;
      cap: Word; rcvbuf: DWORD_PTR): Integer;

    //传输开始/结束
    procedure BeginTrans();
    procedure EndTrans();

    //会话状态
    property TransState: TTransState read FTransState write SetTransState;

    //统计
    property StatsTotalBytes: Int64 read FStatsTotalBytes write FStatsTotalBytes;
    property StatsBlockRetrans: Int64 read FStatsBlockRetrans write FStatsBlockRetrans;

    //速率
    procedure XmitRateWait(us: DWORD);
    property XmitRate: Double read FXmitRate;
    property XmitLastTick: DWORD read FXmitLastTick write FXmitLastTick;
    property XmitWaitTime: Integer read FXmitWaitTime write FXmitWaitTime;

    property DmcMode: Word read FDmcMode;
    property Config: TSendConfig read FConfig;
    property USocket: TUDPSenderSocket read FUSocket;
    property Parts: TParticipants read FParts;
  end;

implementation

{ Negotiate }

constructor TNegotiate.Create;
var
  tryFullDuplex     : Boolean;
begin
  { Copy Config }
  Move(config^, FConfig, SizeOf(FConfig));

  FConsole := TConsole.Create;
  FOnTransStateChange := OnTransStateChange;
  FParts := TParticipants.Create;
  FParts.OnPartsChange := OnPartsChange;

  case config^.dmcMode of
    dmcFixedMode: FDmcMode := DMC_FIXED;
    dmcStreamMode: FDmcMode := DMC_STREAM;
    dmcAsyncMode: FDmcMode := DMC_ASYNC;
    dmcFecMode: FDmcMode := DMC_FEC;
  end;
  FCapabilities := SENDER_CAPABILITIES;

  XmitRateSet(config^.xmitRate);

  FCtrlWaitHandle := CreateEvent(nil, True, True, nil);

  { make the socket and print banner }
  tryFullDuplex := not (dmcFullDuplex in FConfig.flags)
    and not (dmcNotFullDuplex in FConfig.flags);

  FUSocket := TUDPSenderSocket.Create(@FConfig.net,
    dmcPointToPoint in FConfig.flags, tryFullDuplex);

  if tryFullDuplex then
    FConfig.flags := FConfig.flags + [dmcFullDuplex];

{$IFDEF DMC_MSG_ON}
  if dmcFullDuplex in FConfig.flags then
    OutLog2(llMsg, 'Using full duplex mode');

  OutLog2(llMsg, Format('Broadcasting control to %s:%d',
    [inet_ntoa(FUSocket.CtrlAddr.sin_addr), FConfig.net.remotePort]));

  OutLog2(llMsg, Format('DMC Sender at %s:%d on %s',
    [inet_ntoa(FUSocket.NetIf.addr),
    FConfig.net.localPort, FUSocket.NetIf.name]));
{$ENDIF}
end;

destructor TNegotiate.Destroy;
begin
  if Assigned(FParts) then
    FParts.Free;
  if Assigned(FUSocket) then
    FUSocket.Free;
  if Assigned(FConsole) then
    FConsole.Free;
  if FXmitRateTimer > 0 then
    CloseHandle(FXmitRateTimer);
  if FCtrlWaitHandle > 0 then
    CloseHandle(FCtrlWaitHandle);
  inherited;
end;

function TNegotiate.IsPointToPoint(): Boolean;
begin
  if dmcPointToPoint in FConfig.flags then
  begin
    if FParts.Count > 1 then
      raise Exception.CreateFmt('pointopoint mode set, and %d participants instead of 1',
        [FParts.Count]);
    Result := True;
  end
  else if (dmcNoPointToPoint in FConfig.flags)
    or (FConfig.dmcMode in [dmcAsyncMode, dmcStreamMode])
    or (dmcBoardcast in FConfig.flags) then
    Result := False
  else
    Result := FParts.Count = 1;
end;

function TNegotiate.SendConnectionReply(client: PSockAddrIn;
  cap: Word; rcvbuf: DWORD_PTR): Integer;
var
  reply             : TConnectReply;
begin
  reply.opCode := htons(Word(CMD_CONNECT_REPLY));
  reply.dmcMode := htons(FDmcMode);
  reply.capabilities := htons(FCapabilities);

  reply.clNr := htonl(FParts.Add(client, cap, rcvbuf,
    dmcPointToPoint in FConfig.flags));
  reply.blockSize := htonl(FConfig.blockSize);
  reply.reserved := 0;
  FUSocket.CopyDataAddrToMsg(reply.mcastAddr);

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
  if streaming then                     // Data Transing
    hello.opCode := htons(Word(CMD_HELLO_STREAMING))
  else
    hello.opCode := htons(Word(CMD_HELLO));
  hello.reserved := 0;
  hello.dmcMode := htons(FDmcMode);
  hello.capabilities := htons(FCapabilities);
  hello.blockSize := htons(FConfig.blockSize);
  FUSocket.CopyDataAddrToMsg(hello.mcastAddr);

  //rgWaitAll(net_config, sock, FConfig.controlMcastAddr.sin_addr.s_addr, SizeOf(hello));
  Result := FUSocket.SendCtrlMsg(hello, SizeOf(hello));
end;

function TNegotiate.CheckClientWait(firstConnected: PDWORD): Integer;
begin
  Result := 0;
  if (FParts.Count < 1) or (firstConnected = nil) then
    Exit;                               { do not start: no receivers }

  if (FConfig.max_receivers_wait > 0)
    and (DiffTickCount(firstConnected^, GetTickCount) >= FConfig.max_receivers_wait * 1000) then
  begin                                 // 时间
{$IFDEF DMC_MSG_ON}
    OutLog2(llMsg, Format('max wait[%d] passed: starting',
      [FConfig.max_receivers_wait]));
{$ENDIF}
    Result := 1;                        { send-wait passed: start }
    Exit;
  end
  else if (FConfig.min_receivers > 0)
    and (FParts.Count >= FConfig.min_receivers) then
  begin                                 // 数量
{$IFDEF DMC_MSG_ON}
    OutLog2(llMsg, Format('min receivers[%d] reached: starting',
      [FConfig.min_receivers]));
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
    if (FConfig.rexmit_hello_interval > 0) then
      waitTime := FConfig.rexmit_hello_interval
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

    if (FConfig.rexmit_hello_interval > 0) then
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

  if LongBool(FDmcMode and (DMC_ASYNC or DMC_FEC)) then
    Exit;

  case TOpCode(ntohs(ctrlMsg.opCode)) of
    CMD_CONNECT_REQ:
      begin
        sendConnectionReply(@client,
          ntohs(ctrlMsg.connectReq.capabilities),
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
begin
  FAbort := False;
  TransState := tsNego;

  tries := 0;
  Result := 0;
  firstConnected := 0;

  SendHello(False);

  if (FConfig.min_receivers > 0) or (FConfig.max_receivers_wait > 0) then
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
    if not LongBool(FDmcMode and (DMC_ASYNC or DMC_FEC)) and (FParts.Count <= 0) then
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
  TransferCtrl(tcStart);
  if FXmitRateTimer > 0 then
  begin
    CloseHandle(FXmitRateTimer);
    FXmitRateTimer := 0;
  end;
end;

procedure TNegotiate.BeginTrans();
var
  i                 : Integer;
  isPtP             : Boolean;
begin
  FStatsTotalBytes := 0;
  FStatsBlockRetrans := 0;

  isPtP := IsPointToPoint();

  for i := 0 to MAX_CLIENTS - 1 do
    if FParts.IsValid(i) then
    begin
      if isPtP then
        FUSocket.SetDataAddr(FParts.GetAddr(i)^.sin_addr);

      //取共同特性
      FCapabilities := FCapabilities and FParts.GetCapabilities(i);
    end;

{$IFDEF DMC_MSG_ON}
  OutLog2(llMsg, Format('Starting transfer.[Capabilities: %-.4X]',
    [FCapabilities]));

  OutLog2(llMsg, 'Data address ' + inet_ntoa(FUSocket.DataAddr.sin_addr));
{$ENDIF}

  if (dmcBoardcast in FConfig.flags)
    or not LongBool(FCapabilities and CAP_NEW_GEN) then
  begin                                 //不支持组播
    if not isPtP then
      FUSocket.SetDataAddr(FUSocket.CtrlAddr.sin_addr);
    FConfig.flags := FConfig.flags - [dmcFullDuplex, dmcNotFullDuplex];
  end
  else
  begin
    if FDmcMode = DMC_FIXED then        //接收者固定
    begin
      if FUSocket.CtrlAddr.sin_addr.S_addr <> FUSocket.DataAddr.sin_addr.S_addr then
      begin                             //重设控制地址
        FUSocket.CopyIpFrom(@FUSocket.CtrlAddr, @FUSocket.DataAddr);
{$IFDEF DMC_MSG_ON}
        OutLog2(llMsg, 'Reset control to ' + inet_ntoa(FUSocket.CtrlAddr.sin_addr));
{$ENDIF}
      end;
    end
    else
    begin
      if FUSocket.IsMCastAddress(@FUSocket.DataAddr) then
      begin                             //设置组播路由，解决ADSL组播问题
        DeleteIpRoute(FUSocket.DataAddr.sin_addr.S_addr);
        SetLocalRoute(FUSocket.DataAddr.sin_addr.S_addr, $FFFFFFFF,
          FUSocket.NetIf.addr.S_addr);
      end;
    end;
  end;
end;

procedure TNegotiate.EndTrans();
begin
  FParts.Clear();
end;

procedure TNegotiate.SetTransState(const Value: TTransState);
begin
  FTransState := Value;
  if Assigned(FOnTransStateChange) then
    FOnTransStateChange(Value);
end;

procedure TNegotiate.XmitRateSet(kb: Integer);
var
  xmitRateBytes     : Integer;
  xmitRateBlocks    : Integer;
begin
  if kb > 0 then
  begin
    xmitRateBytes := kb * 1024;         //byte/s
    FXmitRate := xmitRateBytes / 1000000; //byte/us

    xmitRateBlocks := xmitRateBytes div FConfig.blockSize;
    if xmitRateBlocks < 1 then
      xmitRateBlocks := 1;

    if FConfig.min_slice_size > xmitRateBlocks then
      FConfig.min_slice_size := xmitRateBlocks;

    if FConfig.default_slice_size > xmitRateBlocks then
      FConfig.default_slice_size := xmitRateBlocks;

    if FConfig.max_slice_size > xmitRateBlocks then
      FConfig.max_slice_size := xmitRateBlocks;

    //Timer
    if FXmitRateTimer = 0 then
      FXmitRateTimer := CreateWaitableTimer(nil, True, nil);
  end
  else
    FXmitRate := 0;
end;

procedure TNegotiate.XmitRateWait(us: DWORD);
var
  lpDueTime         : TLargeInteger;
begin
  lpDueTime := us * (-10);              //负它代表以 100 纳秒为单位的相对时间
  SetWaitableTimer(FXmitRateTimer, lpDueTime, 0, nil, nil, True);

  WaitForSingleObject(FXmitRateTimer, INFINITE);
end;

procedure TNegotiate.WaitForCtrl;
begin
  WaitForSingleObject(FCtrlWaitHandle, INFINITE);
end;

procedure TNegotiate.TransferCtrl(transCtrl: TTransmitCtrl);
begin
  case transCtrl of
    tcStart:
      begin
        SetEvent(FCtrlWaitHandle);
        if Assigned(FConsole) then
          FConsole.PostPressed;
      end;
    tcPause:
      ResetEvent(FCtrlWaitHandle);
  end;
end;

end.

