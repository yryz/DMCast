unit DMCSender_u;

interface
uses
  Windows, Messages, SysUtils, MyClasses,
  FuncLib, Config_u, Protoc_u, Fifo_u,
  Negotiate_u, SendData_u, HouLog_u;

type
  TSenderThread = class(TThread)
  private
    FRc: TRChannel;
    FSender: TSender;
  protected
    FIo: TFifo;
    FDp: TDataPool;
    FNego: TNegotiate;
  protected
    procedure Execute; override;
  public
    constructor Create(config: PSendConfig;
      OnTransStateChange: TOnTransStateChange;
      OnPartsChange: TOnPartsChange);
    destructor Destroy; override;
    procedure Terminate; overload;
  end;

  //API接口

  //填充默认配置
procedure DMCConfigFill(var config: TSendConfig); stdcall;

//创建会话  OnTransStateChange,OnPartsChange 可选
function DMCNegoCreate(config: PSendConfig;
  OnTransStateChange: TOnTransStateChange;
  OnPartsChange: TOnPartsChange;
  var lpFifo: Pointer): Pointer; stdcall;

//结束会话(信号,异步)
function DMCNegoDestroy(lpNego: Pointer): Boolean; stdcall;

//等待缓冲区可写
function DMCDataWriteWait(lpFifo: Pointer; var dwBytes: DWORD): Pointer; stdcall;
//数据生产完成
function DMCDataWrited(lpFifo: Pointer; dwBytes: DWORD): Boolean; stdcall;

//开始/暂停/停止传输(信号)
function DMCTransferCtrl(lpNego: Pointer; transCtrl: TTransmitCtrl): Boolean; stdcall;

//统计片大小
function DMCStatsSliceSize(lpNego: Pointer): Integer; stdcall;
//统计已经传输Bytes
function DMCStatsTotalBytes(lpNego: Pointer): Int64; stdcall;
//统计重传Blocks(块)
function DMCStatsBlockRetrans(lpNego: Pointer): Int64; stdcall;

implementation

procedure DMCConfigFill(var config: TSendConfig);
begin
  FillChar(config, SizeOf(config), 0);
  with config do
  begin
    with net do
    begin
      ifName := nil;                    //eth0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil(INADDR_ANY)
      localPort := 9080;                //9001
      remotePort := 8090;               //9000

      mcastRdv := nil;
      ttl := 1;

      sockRecvBufSize := 64 * 1024;
    end;

    flags := [];
    dmcMode := dmcFixedMode;
    blockSize := 1456;                  // 这个值在一些情况下（如家用无线），设置大点效果会好些如10K

    min_slice_size := Protoc_u.MIN_SLICE_SIZE;
    max_slice_size := Protoc_u.MAX_SLICE_SIZE;

    rexmit_hello_interval := 1000;      //retransmit hello message
    retriesUntilDrop := 30;
    rehelloOffset := 50;
  end;
end;

function DMCNegoCreate(config: PSendConfig;
  OnTransStateChange: TOnTransStateChange;
  OnPartsChange: TOnPartsChange;
  var lpFifo: Pointer): Pointer;
var
  Sender            : TSenderThread;
begin
  Sender := TSenderThread.Create(config, OnTransStateChange, OnPartsChange);
  lpFifo := Sender.FIo;
  Result := Sender;
  Sender.Resume;
end;

function DMCNegoDestroy(lpNego: Pointer): Boolean;
begin
  Result := True;
  try
    with TSenderThread(lpNego) do
    begin
      Terminate;
      Sleep(0);
      FreeOnTerminate := True;
      if Suspended then
        Resume;
    end;

  except on e: Exception do
    begin
      Result := False;
{$IFDEF EN_LOG}
      OutLog2(llError, e.Message);
{$ENDIF}
    end;
  end;
end;

function DMCDataWriteWait(lpFifo: Pointer; var dwBytes: DWORD): Pointer;
var
  pos, bytes        : Integer;
begin
  pos := TFifo(lpFifo).FreeMemPC.GetConsumerPosition;
  bytes := TFifo(lpFifo).FreeMemPC.ConsumeContiguousMinAmount(dwBytes);
  if (bytes > (pos + bytes) mod DISK_BLOCK_SIZE) then
    Dec(bytes, (pos + bytes) mod DISK_BLOCK_SIZE);

  dwBytes := bytes;
  if bytes > 0 then
    Result := TFifo(lpFifo).GetDataBuffer(pos)
  else
    Result := nil;
end;

function DMCDataWrited(lpFifo: Pointer; dwBytes: DWORD): Boolean;
begin
  Result := True;
  try
    if (dwBytes > 0) then
    begin
      TFifo(lpFifo).FreeMemPC.Consumed(dwBytes);
      TFifo(lpFifo).DataPC.Produce(dwBytes);
    end
    else                                //no data(data end?)
    begin
      TFifo(lpFifo).FreeMemPC.MarkEnd;
      TFifo(lpFifo).DataPC.MarkEnd;
    end;
  except on e: Exception do
    begin
      Result := False;
{$IFDEF EN_LOG}
      OutLog2(llError, e.Message);
{$ENDIF}
    end;
  end;
end;

function DMCTransferCtrl(lpNego: Pointer; transCtrl: TTransmitCtrl): Boolean;
begin
  Result := True;
  try
    TSenderThread(lpNego).FNego.TransferCtrl(transCtrl);
  except on e: Exception do
    begin
      Result := False;
{$IFDEF EN_LOG}
      OutLog2(llError, e.Message);
{$ENDIF}
    end;
  end;
end;

function DMCStatsSliceSize(lpNego: Pointer): Integer;
begin
  try
    if Assigned(TSenderThread(lpNego).FDp) then
      Result := TSenderThread(lpNego).FDp.SliceSize
    else
      Result := 0;
  except on e: Exception do
    begin
      Result := -1;
{$IFDEF EN_LOG}
      OutLog2(llError, e.Message);
{$ENDIF}
    end;
  end;
end;

function DMCStatsTotalBytes(lpNego: Pointer): Int64;
begin
  try
    Result := TSenderThread(lpNego).FNego.StatsTotalBytes;
  except on e: Exception do
    begin
      Result := -1;
{$IFDEF EN_LOG}
      OutLog2(llError, e.Message);
{$ENDIF}
    end;
  end;
end;

function DMCStatsBlockRetrans(lpNego: Pointer): Int64;
begin
  try
    Result := TSenderThread(lpNego).FNego.StatsBlockRetrans;
  except on e: Exception do
    begin
      Result := -1;
{$IFDEF EN_LOG}
      OutLog2(llError, e.Message);
{$ENDIF}
    end;
  end;
end;

{ TSenderThread }

constructor TSenderThread.Create;
begin
  FIo := TFifo.Create(config^.blockSize);
  FNego := TNegotiate.Create(config, OnTransStateChange, OnPartsChange);
  inherited Create(True);
end;

destructor TSenderThread.Destroy;
begin
  Terminate;

  if Assigned(FIo) then
    FIo.Free;
  if Assigned(FNego) then
    FNego.Free;
  inherited;
end;

procedure TSenderThread.Execute;
begin
  try
    if FNego.StartNegotiate > 0 then
    begin                               //已连接数 >0
      FNego.BeginTrans();

      FDp := TDataPool.Create(FNego);
      FRc := TRChannel.Create(FNego, FDp);
      FSender := TSender.Create(FNego, FDp, FRc);
      FDp.InitSlice(FIo, FRc);

      FRc.Resume;                       //唤醒反馈隧道
      FSender.Execute;                  //执行发送

      Self.Terminate;

      FreeAndNil(FSender);
      FreeAndNil(FRc);
      FreeAndNil(FDp);

      FNego.EndTrans();
    end;
  finally
    FNego.TransState := tsStop;
  end;

  //挂起(确保数据能安全释放)
  if not FreeOnTerminate then
    Suspend;
end;

procedure TSenderThread.Terminate;
begin
  inherited Terminate;

  try
    FNego.StopNegotiate;
    if Assigned(FSender) then
    begin
      FSender.Terminated := True;
      FDp.Close;
      FNego.USocket.Close;
      FRc.Terminate;
      FIo.Close;
    end;
  except
  end;
end;

end.
 
