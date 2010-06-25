{$INCLUDE def.inc}

unit Fifo_u;

interface
uses
  Windows, Sysutils, Classes, Produconsum_u;

const
  DISK_BLOCK_SIZE   = 4096;             //磁盘请求最小单位，最大为 blockSize * DISK_BLOCK_SIZE

type
  TFifo = class(TThread)
  private
    FOrigFDataBuffer: DWORD_PTR;        //原始缓冲区指针
    FDataBuffer: DWORD_PTR;
    FDataBufSize: DWORD;
    FDataPC: TProduceConsum;            //可用数据
    FFreeMemPC: TProduceConsum;         //可用空间
  public
    constructor Create(blockSize: Integer);
    destructor Destroy; override;
    procedure Terminate; overload;
  published
    property DataPC: TProduceConsum read FDataPC;
    property FreeMemPC: TProduceConsum read FFreeMemPC;
    property DataBuffer: DWORD_PTR read FDataBuffer;
    property DataBufSize: DWORD read FDataBufSize;
  end;

  TDiskIO = class(TFifo)
  private
    FFile: Integer;
    FIsRead: Boolean;
  protected
    procedure Execute; override;
    function RunReader(): Integer;
    function RunWriter(): Integer;
  public
    constructor Create(fileName: string; blockSize: Integer; isRead: Boolean);
    destructor Destroy; override;
  end;

implementation

{ TFifo }

constructor TFifo.Create;
begin
  FDataBufSize := blockSize * DISK_BLOCK_SIZE; //保证生产/消耗都是整块
  FOrigFDataBuffer := DWORD_PTR(GetMemory(FDataBufSize + DISK_BLOCK_SIZE));
  FDataBuffer := FOrigFDataBuffer + DISK_BLOCK_SIZE -
    DWORD_PTR(FOrigFDataBuffer) mod DISK_BLOCK_SIZE;

  FFreeMemPC := TProduceConsum.Create(FDataBufSize, 'free mem');
  FFreeMemPC.Produce(FDataBufSize);
  FDataPC := TProduceConsum.Create(FDataBufSize, 'data');

  inherited Create(True);
end;

destructor TFifo.Destroy;
begin
  if Assigned(FDataPC) then FreeAndNil(FDataPC);
  if Assigned(FFreeMemPC) then FreeAndNil(FFreeMemPC);
  FreeMemory(Pointer(FOrigFDataBuffer));
  inherited;
end;

procedure TFifo.Terminate;
begin
  inherited Terminate;
  if Assigned(FreeMemPC) then FreeMemPC.MarkEnd;
  if Assigned(FDataPC) then FDataPC.MarkEnd;
  WaitFor;
end;

{ TDiskIO }

constructor TDiskIO.Create(fileName: string; blockSize: Integer;
  isRead: Boolean);
begin
  FIsRead := isRead;
  if isRead then begin
    FFile := FileOpen(fileName, fmOpenRead or fmShareDenyNone);
    if Integer(FFile) <= 0 then
      raise Exception.Create(fileName + ' 文件无法打开');
  end else
  begin
    FFile := FileCreate(fileName);
    if Integer(FFile) <= 0 then
      raise Exception.Create(fileName + ' 文件无法创建');
  end;
  inherited Create(blockSize);
end;

destructor TDiskIO.Destroy;
begin
  if Integer(FFile) > 0 then FileClose(FFile);
  inherited;
end;

procedure TDiskIO.Execute;
begin
  if FIsRead then
    ReturnValue := RunReader
  else
    ReturnValue := RunWriter;
end;

function TDiskIO.RunReader: Integer;
var
  Pos, bytes        : Integer;
begin
  bytes := 0;
  while True do
  begin
    pos := FFreeMemPC.GetConsumerPosition;
    bytes := FFreeMemPC.ConsumeContiguousMinAmount(DISK_BLOCK_SIZE);

    if Terminated then Break;

    if (bytes > (pos + bytes) mod DISK_BLOCK_SIZE) then
      Dec(bytes, (pos + bytes) mod DISK_BLOCK_SIZE);

    if (bytes = 0) then Break;          //net writer exited?

    bytes := FileRead(FFile, PAnsiChar(FDataBuffer + pos)^, bytes);

    if (bytes < 0) then
      raise Exception.CreateFmt('read error!', [GetLastError])
    else if (bytes = 0) then
    begin
      FDataPC.MarkEnd;
      Break;
    end else
    begin
      FFreeMemPC.Consumed(bytes);
      FDataPC.Produce(bytes);
    end;
  end;
  Result := bytes;
end;

function TDiskIO.RunWriter: Integer;
var
  Pos, bytes        : Integer;
begin
  bytes := 0;
  while True do
  begin
    pos := FDataPC.GetConsumerPosition;
    bytes := FDataPC.ConsumeContiguousMinAmount(DISK_BLOCK_SIZE);

    if bytes = 0 then Break; //END

    if (bytes > (pos + bytes) mod DISK_BLOCK_SIZE) then
      Dec(bytes, (pos + bytes) mod DISK_BLOCK_SIZE);

{$IFDEF 0}
    writeln(Format('writing at pos = %p', [Pointer(FDataBuffer + pos)]));
{$ENDIF}

    if bytes > 128 * 1024 then
      bytes := 64 * 1024;
    bytes := FileWrite(FFile, PAnsiChar(FDataBuffer + pos)^, bytes);

    if (bytes < 0) then
      raise Exception.CreateFmt('file write error!', [GetLastError])
    else begin
      FDataPC.Consumed(bytes);
      FFreeMemPC.Produce(bytes);
    end;
  end;
  Result := bytes;
end;

end.

