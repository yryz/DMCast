{$INCLUDE def.inc}

unit Negotiate_u;

interface
uses
  Windows, Sysutils, WinSock, Func_u,
  Config_u, Protoc_u, SockLib_u, Console_u,
  Fifo_u, HouLog_u;

type
  TNegotiate = class(TObject)
  private
    FConfig: TRecvConfig;
    FUSocket: TUDPReceiverSocket;

    FTransState: TTransState;
    FOnTransStateChange: TOnTransStateChange;
    procedure SetTransState(const Value: TTransState);
  protected
    FDmcMode: Word;                     //工作模式
    FClientID: Integer;                 //会话ID
    FCapabilities: Word;                //功能特征

    { 统计 }
    FStatsTotalBytes: Int64;
  private
    //请求会话
    function SendConnectReq(): Integer;

    //让服务端开始传输
    function SendGo(): Integer;
  public
    constructor Create(config: PRecvConfig; OnTransStateChange: TOnTransStateChange);
    destructor Destroy; override;

    //会话控制
    function StartNegotiate(): Boolean;
    function StopNegotiate(): Boolean;

    //断开会话
    function SendDisconnect(): Integer;

    //会话状态
    property TransState: TTransState read FTransState write SetTransState;

    //统计
    property StatsTotalBytes: Int64 read FStatsTotalBytes write FStatsTotalBytes;

    property DmcMode: Word read FDmcMode write FDmcMode;
    property ClientID: Integer read FClientID;
    property Config: TRecvConfig read FConfig;
    property USocket: TUDPReceiverSocket read FUSocket;
  end;

implementation

{ Negotiate }

constructor TNegotiate.Create;
begin
  Move(config^, FConfig, SizeOf(FConfig));

  FOnTransStateChange := OnTransStateChange;
  FClientID := -1;

  case config^.dmcMode of
    dmcFixedMode: FDmcMode := DMC_FIXED;
    dmcStreamMode: FDmcMode := DMC_STREAM;
    dmcAsyncMode: FDmcMode := DMC_ASYNC;
    dmcFecMode: FDmcMode := DMC_FEC;
  end;

  { make the socket and print banner }
  FUSocket := TUDPReceiverSocket.Create(@FConfig.net);

{$IFDEF EN_LOG}
  OutLog(Format('UDP receiver at %s:%d on %s',
    [inet_ntoa(FUSocket.NetIf.addr), FConfig.net.localPort, FUSocket.NetIf.name]));
  OutLog(Format('Connect to %s:%d',
    [inet_ntoa(FUSocket.CtrlAddr.sin_addr), FConfig.net.remotePort]));
{$ENDIF}
end;

destructor TNegotiate.Destroy;
begin
  if Assigned(FUSocket) then
    FreeAndNil(FUSocket);
  inherited;
end;

function TNegotiate.SendConnectReq(): Integer;
var
  conReq            : TConnectReq;
begin
  conReq.opCode := htons(Word(CMD_CONNECT_REQ));
  conReq.reserved := 0;
  conReq.dmcMode := htons(FDmcMode);
  conReq.capabilities := htons(RECEIVER_CAPABILITIES);
  conReq.rcvbuf := htonl(FUSocket.RecvBufSize);
  Result := FUSocket.SendCtrlMsg(conReq, SizeOf(conReq));
end;

function TNegotiate.SendGo(): Integer;
var
  go                : TGo;
begin
  go.opCode := htons(Word(CMD_GO));
  go.reserved := 0;
  Result := FUSocket.SendCtrlMsg(go, SizeOf(go));
end;

function TNegotiate.SendDisconnect: Integer;
var
  disCon            : TDisconnect;
begin
  disCon.opCode := htons(Word(CMD_DISCONNECT));
  disCon.reserved := 0;
  Result := FUSocket.SendCtrlMsg(disCon, SizeOf(disCon));
end;

function TNegotiate.StartNegotiate(): Boolean;
var
  msgLen            : Integer;
  pMsg              : PServerControlMsg;
  msgBuf            : array[0..SizeOf(TServerControlMsg) + MAX_BLOCK_SIZE - 1] of Byte; //Fix SOCKET WSAEMSGSIZE  EERR (10040);
  connectReqSent    : Boolean;
begin
  Result := False;
  FTransState := tsNego;
  connectReqSent := False;

  pMsg := @msgBuf;
  while not Result do
  begin
    if not LongBool(FDmcMode and (DMC_ASYNC or DMC_FEC))
      and not connectReqSent then
    begin
      if SendConnectReq() < 0 then
        Break;
      connectReqSent := True;
    end;

    if FUSocket.SelectSocks(@FUSocket.Socket, 1, 1.5, True) <= 0 then
      Continue;

    msgLen := FUSocket.RecvCtrlMsg(msgBuf, SizeOf(msgBuf),
      PSockAddrIn(@FUSocket.CtrlAddr)^);

    if (msgLen < 0) then
    begin
{$IFDEF DMC_MSG_ERROR}
      OutLog(Format('problem getting data from client.errorno:%d', [GetLastError]));
{$ENDIF}
      Break;                            { don't panic if we get weird messages }
    end
    else if (msgLen = 0) then
      Continue;

    case TOpCode(ntohs(pMsg^.opCode)) of
      CMD_CONNECT_REPLY:
        begin
          FClientID := ntohl(pMsg^.connectReply.clNr);
          FDmcMode := ntohs(pMsg^.hello.dmcMode);
          FCapabilities := ntohs(pMsg^.connectReply.capabilities);
          FConfig.blockSize := ntohl(pMsg^.connectReply.blockSize);
{$IFDEF EN_LOG}
          OutLog(Format('received message, cap=%-.8x', [FCapabilities]));
{$ENDIF}
          if LongBool(FCapabilities and CAP_NEW_GEN) then //支持组播
            FUSocket.SetDataAddrFromMsg(pMsg^.connectReply.mcastAddr);

          if FClientID >= 0 then
          begin
            Result := True;
          end
          else
          begin
{$IFDEF DMC_FATAL_ON}
            OutLog2(llFatal, 'Too many clients already connected');
{$ENDIF}
          end;
          Break;
        end;
      CMD_HELLO_STREAMING,
        CMD_HELLO_NEW,
        CMD_HELLO:
        begin
          connectReqSent := False;

          FDmcMode := ntohs(pMsg^.hello.dmcMode);
          FCapabilities := ntohs(pMsg^.hello.capabilities);

          if LongBool(FCapabilities and CAP_NEW_GEN) then
          begin
            FConfig.blockSize := ntohs(pMsg^.hello.blockSize);
            FUSocket.SetDataAddrFromMsg(pMsg^.hello.mcastAddr);
          end;

          if LongBool(FDmcMode and (DMC_ASYNC or DMC_FEC)) then
          begin
            Result := True;
            Break;
          end
          else
            Continue;
        end;
      CMD_CONNECT_REQ,
        CMD_DATA,
        CMD_FEC: Continue;
{$IFDEF DMC_WARN_ON}
    else
      OutLog2(llWarn, Format('Unexpected command %-.4x',
        [ntohs(pMsg^.opCode)]));
{$ENDIF}
    end;
  end;                                  //end while

end;

function TNegotiate.StopNegotiate: Boolean;
begin
  FUSocket.Close;
end;

procedure TNegotiate.SetTransState(const Value: TTransState);
begin
  FTransState := Value;
  if Assigned(FOnTransStateChange) then
    FOnTransStateChange(Value);
end;

end.

