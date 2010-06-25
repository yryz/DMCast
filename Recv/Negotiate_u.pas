{$INCLUDE def.inc}

unit Negotiate_u;

interface
uses
  Windows, Sysutils, WinSock, Func_u,
  Config_u, Protoc_u, SockLib_u, Console_u,
  RecvData_u, IStats_u, INegotiate_u, Fifo_u;

type                                    //不要直接使用对象,容易出错
  TNegotiate = class(TInterfacedObject, INegotiate)
  private
    FUSocket: TUDPReceiverSocket;
    FConfig: PNetConfig;
    FIo: TDiskIO;
    FDp: TDataPool;
    FReceiver: TReceiver;
    FStats: ITransStats;
    FOverEvent: THandle;
    FConsole: TConsole;
  private
    function SendConnectReq(): Integer;
    function SendGo(): Integer;
    function SendDisconnect(): Integer;
  public
    constructor Create(config: PNetConfig; Stats: ITransStats);
    destructor Destroy; override;
    function StartNegotiate(): Integer;
    function StopNegotiate(): Boolean;
    procedure DoTransfer();
    function AbortTransfer(waitTime: DWORD): Boolean;
  end;

implementation

{ Negotiate }

constructor TNegotiate.Create(config: PNetConfig; Stats: ITransStats);
begin
  FConfig := config;
  FStats := Stats;
  FOverEvent := CreateEvent(nil, True, False, nil);
  //FConsole := TConsole.Create;
end;

destructor TNegotiate.Destroy;
begin
  //FreeAndNil(FConsole);
  SetEvent(FOverEvent);
  CloseHandle(FOverEvent);
  if Assigned(FUSocket) then FreeAndNil(FUSocket);
  inherited;
end;

function TNegotiate.SendConnectReq(): Integer;
var
  conReq            : TConnectReq;
begin
  if (dmcPassiveMode in FConfig^.flags) then
    Result := 0
  else begin
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

function TNegotiate.StartNegotiate(): Integer; // If Result=1. start transfer
var
  msgLen            : Integer;
  isConnected       : Boolean;
  ctrlMsg           : TServerControlMsg;
begin
  Result := 0;
  { make the socket and print banner }
  FUSocket := TUDPReceiverSocket.Create(FConfig);

{$IFDEF CONSOLE}
  //if disk_config^.pipeName = nil then Write('Compressed ');
  Write('UDP receiver for ');
  //if disk_config^.fileName = nil then Write('(stdin)')
  //else
  Write(FConfig^.fileName);
  Write(' at ');
  Write(inet_ntoa(FUSocket.NetIf.addr), ':', FConfig^.localPort);
  WriteLn(' on ', FUSocket.NetIf.name);
  WriteLn('Connect to ', inet_ntoa(FUSocket.CtrlAddr.sin_addr),
    ':', FConfig^.remotePort);
{$ENDIF}

  isConnected := False;
  while True do
  begin
    if not isConnected then
      if SendConnectReq() < 0 then Break;

    if FUSocket.SelectSocks(@FUSocket.Socket, 1, 1.5, True) <= 0 then
      Continue;
    msgLen := FUSocket.RecvCtrlMsg(ctrlMsg, SizeOf(ctrlMsg),
      PSockAddrIn(@FUSocket.CtrlAddr)^);
    if (msgLen = 0) then Continue;
    if (msgLen < 0) then begin
{$IFDEF CONSOLE}
      WriteLn('problem getting data from client.errorno:', GetLastError);
{$ENDIF}
      Break;                            { don't panic if we get weird messages }
    end;

    case TOpCode(ntohs(ctrlMsg.opCode)) of
      CMD_CONNECT_REPLY: begin
          FConfig^.clientNumber := ntohl(ctrlMsg.connectReply.clNr);
          FConfig^.blockSize := ntohl(ctrlMsg.connectReply.blockSize);
          FConfig^.capabilities := ntohl(ctrlMsg.connectReply.capabilities);
{$IFDEF CONSOLE}
          WriteLn(Format('received message, cap=%-.8x', [FConfig^.capabilities]));
{$ENDIF}
          if LongBool(FConfig^.capabilities and CAP_NEW_GEN) then
            FUSocket.SetDataAddrFromMsg(ctrlMsg.connectReply.mcastAddr);

          if FConfig^.clientNumber >= 0 then
            isConnected := True
          else begin
{$IFDEF DMC_FATAL_ON}
            FStats.Msg(umtFatal, 'Too many clients already connected');
{$ENDIF}
          end;
          Break;
        end;
      CMD_HELLO_STREAMING: ;
      CMD_HELLO_NEW: ;
      CMD_HELLO: begin
          FConfig^.capabilities := ntohl(ctrlMsg.hello.capabilities);
          if TOpCode(ntohs(ctrlMsg.opCode)) = CMD_HELLO_STREAMING then
            FConfig^.flags := FConfig^.flags + [dmcStreamMode];

          if LongBool(FConfig^.capabilities and CAP_NEW_GEN) then
          begin
            FConfig^.blockSize := ntohs(ctrlMsg.hello.blockSize);
            FUSocket.SetDataAddrFromMsg(ctrlMsg.hello.mcastAddr);

            if LongBool(FConfig^.capabilities and CAP_ASYNC) then
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
      FStats.Msg(umtWarn, Format('Unexpected command %-.4x',
        [ntohs(ctrlMsg.opCode)]));
{$ENDIF}
    end;
  end;                                  //end while

  if isConnected then Result := 1;
end;

function TNegotiate.StopNegotiate: Boolean;
begin
  Result := False;
  if Assigned(FConsole) then
    Result := FConsole.PostPressed;
end;

procedure TNegotiate.DoTransfer();
begin
  FIo := TDiskIO.Create(FConfig^.fileName, FConfig^.blockSize, False);
  FDp := TDataPool.Create(FConfig, FStats);
  FReceiver := TReceiver.Create(FConfig, FDp, FUSocket, FStats);
  FDp.Open(FIo, FUSocket, Self);

  FIo.Resume;                           //唤醒数据IO

  FReceiver.Execute;                    //执行发送
  SetEvent(FOverEvent);
  SendDisconnect();

  FUSocket.Close;
  FDp.Close;
  FIo.Terminate;
  FreeAndNil(FReceiver);
  FreeAndNil(FDp);
  FreeAndNil(FIo);
{$IFDEF CONSOLE}
  WriteLn(#13#10'Transfer complete.');
{$ENDIF}
end;

function TNegotiate.AbortTransfer(waitTime: DWORD): Boolean;
begin
  if Assigned(FReceiver) then begin
    FReceiver.Terminate;
    FUSocket.Close;
    FDp.Close;
    FIo.Terminate;
    Result := WaitForSingleObject(FOverEvent, waitTime) = WAIT_OBJECT_0;
  end else
    Result := True;
end;

end.

