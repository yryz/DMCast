{$INCLUDE def.inc}

unit Fifo_u;

interface
uses
  Windows, Sysutils, Produconsum_u;

const
  DISK_BLOCK_SIZE   = 4096;             //磁盘请求最小单位，最大为 blockSize * DISK_BLOCK_SIZE

type
  //默认 挂起
  TFifo = class(TObject)
  private
    FOrigFDataBuffer: Pointer;          //原始缓冲区指针
    FDataBuffer: Pointer;
    FDataBufSize: DWORD;
    FDataPC: TProduceConsum;            //可用数据
    FFreeMemPC: TProduceConsum;         //可用空间
  public
    constructor Create(blockSize: Integer);
    destructor Destroy; override;
    procedure Terminate;

    function GetDataBuffer(offset: Integer): Pointer;
  published
    property DataPC: TProduceConsum read FDataPC;
    property FreeMemPC: TProduceConsum read FFreeMemPC;
  end;

implementation

{ TFifo }

constructor TFifo.Create;
begin
  FDataBufSize := blockSize * DISK_BLOCK_SIZE; //保证生产/消耗都是整块
  FOrigFDataBuffer := GetMemory(FDataBufSize + DISK_BLOCK_SIZE);
  FDataBuffer := Pointer(Integer(FOrigFDataBuffer) + DISK_BLOCK_SIZE -
    Integer(FOrigFDataBuffer) mod DISK_BLOCK_SIZE);

  FFreeMemPC := TProduceConsum.Create(FDataBufSize, 'free mem');
  FFreeMemPC.Produce(FDataBufSize);
  FDataPC := TProduceConsum.Create(FDataBufSize, 'data');
end;

destructor TFifo.Destroy;
begin
  if Assigned(FDataPC) then
    FreeAndNil(FDataPC);
  if Assigned(FFreeMemPC) then
    FreeAndNil(FFreeMemPC);
  FreeMemory(FOrigFDataBuffer);
  inherited;
end;

procedure TFifo.Terminate;
begin
  if Assigned(FreeMemPC) then
    FreeMemPC.MarkEnd;
  if Assigned(FDataPC) then
    FDataPC.MarkEnd;
end;

function TFifo.GetDataBuffer(offset: Integer): Pointer;
begin
  Result := Pointer(Integer(FDataBuffer) + offset mod FDataBufSize);
end;

end.

