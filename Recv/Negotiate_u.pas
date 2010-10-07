{$INCLUDE def.inc}

unit Negotiate_u;

interface
uses
  Windows, Sysutils, WinSock, Func_u,
  Config_u, Protoc_u, SockLib_u, Console_u,
  IStats_u, Fifo_u, HouLog_u;

type
  TNegotiate = class(TObject)
  private
    FConfig: PRecvConfig;
    FStats: IReceiverStats;
    FUSocket: TUDPReceiverSocket;

    FTransState: TTransState;
    procedure SetTransState(const Value: TTransState);
  protected
    FClientID: Integer;                 //会话ID
    FCapabilities: Integer;             //功能特征
  private
    //请求会话
    function SendConnectReq(): Integer;

    //让服务端开始传输
    function SendGo(): Integer;
  public
    constructor Create(config: PRecvConfig; Stats: IReceiverStats);
    destructor Destroy; override;

    //会话控制
    function StartNegotiate(): Boolean;
    function StopNegotiate(): Boolean;

    //断开会话
    function SendDisconnect(): Integer;

    //会话状态
    property TransState: TTransState read FTransState write SetTransState;

    property ClientID: Integer read FClientID;
    property Config: PRecvConfig read FConfig;
    property USocket: TUDPReceiverSocket read FUSocket;
    property Stats: IReceiverStats read FStats;
  end;

implementation

{ Negotiate }

constructor TNegotiate.Create(config: PRecvConfig; Stats: IReceiverStats);
begin
  FConfig := config;
  FStats := Stats;
  FClientID := -1;
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
  if (dmcPassiveMode in FConfig^.flags) then
    Result := 0
  else
  begin
    conReq.opCode := htons(Word(CMD_CONNECT_REQ));
    conReq.reserved := 0;
    conReq.capabilities := htonl(RECEIVER_CAPABILITIES);
    conReq.rcvbuf := htonl(FUSocket.RecvBufSize);
    Result := FUSocket.SendCtrlMsg(conReq, SizeOf(conReq));
  end;
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
  ctrlMsg           : TServerControlMsg;
begin
  Result := False;
  FTransState := tsNego;

  { make the socket and print banner }
  FUSocket := TUDPReceiverSocket.Create(@FConfig^.net);

{$IFDEF CONSOLE}
  //if disk_config^.pipeName = nil then Write('Compressed ');
  Write('UDP receiver at ');
  Write(inet_ntoa(FUSocket.NetIf.addr), ':', FConfig.net.localPort);
  WriteLn(' on ', FUSocket.NetIf.name);
  WriteLn('Connect to ', inet_ntoa(FUSocket.CtrlAddr.sin_addr),
    ':', FConfig.net.remotePort);
{$ENDIF}

  while True do
  begin
    if not Result then
      if SendConnectReq() < 0 then
        Break;

    if FUSocket.SelectSocks(@FUSocket.Socket, 1, 1.5, True) <= 0 then
      Continue;

    msgLen := FUSocket.RecvCtrlMsg(ctrlMsg, SizeOf(ctrlMsg),
      PSockAddrIn(@FUSocket.CtrlAddr)^);

    if (msgLen < 0) then
    begin
{$IFDEF CONSOLE}
      WriteLn('problem getting data from client.errorno:', GetLastError);
{$ENDIF}
      Break;                            { don't panic if we get weird messages }
    end
    else if (msgLen = 0) then
      Continue;

    case TOpCode(ntohs(ctrlMsg.opCode)) of
      CMD_CONNECT_REPLY:
        begin
          FClientID := ntohl(ctrlMsg.connectReply.clNr);
          FConfig^.blockSize := ntohl(ctrlMsg.connectReply.blockSize);
          FCapabilities := ntohl(ctrlMsg.connectReply.capabilities);
{$IFDEF CONSOLE}
          WriteLn(Format('received message, cap=%-.8x', [FCapabilities]));
{$ENDIF}
          if LongBool(FCapabilities and CAP_NEW_GEN) then //支持组播
            FUSocket.SetDataAddrFromMsg(ctrlMsg.connectReply.mcastAddr);

          if FClientID >= 0 then
            Result := True
          else
          begin
{$IFDEF DMC_FATAL_ON}
            OutLog2(llFatal, 'Too many clients already connected');
{$ENDIF}
          end;
          Break;
        end;
      CMD_HELLO_STREAMING: ;
      CMD_HELLO_NEW: ;
      CMD_HELLO:
        begin
          FCapabilities := ntohl(ctrlMsg.hello.capabilities);
          if TOpCode(ntohs(ctrlMsg.opCode)) = CMD_HELLO_STREAMING then
            FConfig^.flags := FConfig^.flags + [dmcStreamMode];

          if LongBool(FCapabilities and CAP_NEW_GEN) then
          begin
            FConfig^.blockSize := ntohs(ctrlMsg.hello.blockSize);
            FUSocket.SetDataAddrFromMsg(ctrlMsg.hello.mcastAddr);

            if LongBool(FCapabilities and CAP_ASYNC) then
              FConfig^.flags := FConfig^.flags + [dmcPassiveMode];
            if dmcPassiveMode in FConfig^.flags then
              Break;
          end;
          continue;
        end;
      CMD_CONNECT_REQ: ;
      CMD_DATA: ;
      CMD_FEC: continue;
{$IFDEF DMC_WARN_ON}
    else
      OutLog2(llWarn, Format('Unexpected command %-.4x',
        [ntohs(ctrlMsg.opCode)]));
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
  if Assigned(FStats) then
    FStats.TransStateChange(Value);
end;

end.

