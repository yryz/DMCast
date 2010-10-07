{
 20100427 %Fix 没有产生，先消耗会直接返回0(应该等待)
}

unit Produconsum_u;

interface
uses
  Windows, Sysutils;

type
  //工厂(生产、消耗数据/空间) ,消耗阻塞，生产不阻塞
  //用于操作数据缓冲区, 只是移动指针、计数和同步,并不添加删除数据
  TProduceConsum = class
  private
    FSize: UINT;
    FDoubSize: UINT;                    //双倍大小
    FProduced: UINT;
    FConsumed: UINT;
    FAtEnd: Boolean;
    FLock: TRTLCriticalSection;
    FConsumerIsWaiting: Boolean;
    FEvent: THandle;
    FName: PAnsiChar;
  protected
    procedure WakeConsumer();
    function _ConsumeAny(minAmount, waitTime: UINT): Integer; //阻塞
  public
    constructor Create(size: UINT; const name: PAnsiChar);
    destructor Destroy; override;

    procedure Produce(amount: UINT);    //产生
    procedure MarkEnd();                //标记结束
    function ConsumeAny(): Integer;     //获得至少1,阻塞
    function ConsumeAnyWithTimeout(waitTime: UINT): Integer; //获得至少1，直到超时
    function ConsumeAnyContiguous(): Integer; //获得连续的数据块,阻塞
    function ConsumeContiguousMinAmount(amount: UINT): Integer; //获得连续的缓冲区，至少x,阻塞
    function Consume(amount: UINT): Integer; //请求消耗x,阻塞
    function Consumed(amount: UINT): Integer; //已消耗
    function GetProducerPosition(): UINT; //获取生产者当前位置(由Produced移动)
    function GetConsumerPosition(): UINT; //获取消耗者当前位置(由Consumed移动)
    function GetSize(): UINT;
    function GetProducedAmount(): Integer; //获取目前可被消耗的数据总量，不阻塞
  end;

implementation

{ TProduceConsum }

constructor TProduceConsum.Create(size: UINT; const name: PAnsiChar);
begin
  Assert(size <= UINT(-1) div 2, '"size" Too Big!');
  FSize := size;
  FDoubSize := 2 * size;
  FProduced := 0;
  FConsumed := 0;
  FAtEnd := False;
  InitializeCriticalSection(FLock);
  FConsumerIsWaiting := True;           //True防止没有产生，就先消耗
  FEvent := CreateEvent(nil, True, False, nil); //[手动复位][无信号]
  FName := name;
end;

destructor TProduceConsum.Destroy;
begin
  DeleteCriticalSection(FLock);
  CloseHandle(FEvent);
  inherited;
end;

procedure TProduceConsum.MarkEnd;
begin
  FAtEnd := True;
  WakeConsumer();
end;

procedure TProduceConsum.Produce(amount: UINT);
var
  produced, consumed: UINT;
begin
  produced := FProduced;
  consumed := FConsumed;

  { * sanity checks:
    * 1. should not produce more than size
    * 2. do not pass consumed + size
    * }
  if (amount > FSize) then
  begin
    raise Exception.CreateFmt('Buffer overflow in produce %s: %d > %d '#10,
      [FName, amount, FSize]);
    Exit;
  end;

  Inc(produced, amount);
  if (produced >= FDoubSize) then
    Dec(produced, FDoubSize);

  if (produced > consumed + FSize) or
    ((produced < consumed) and (produced > consumed - FSize)) then
  begin
    raise Exception.CreateFmt('Buffer overflow in produce %s: %d > %d[%d]'#10,
      [FName, produced, consumed, FSize]);
    Exit;
  end;

  FProduced := produced;
  WakeConsumer();
end;

procedure TProduceConsum.WakeConsumer;
begin
  if FConsumerIsWaiting then
  begin
    EnterCriticalSection(FLock);
    SetEvent(FEvent);
    LeaveCriticalSection(FLock);
  end;
end;

function TProduceConsum._ConsumeAny(minAmount, waitTime: UINT): Integer;
var
  r                 : Integer;
  amount            : UINT;
begin
{$IFDEF DEBUG}
  WriteLn(Format('%s: Waiting for %d bytes(%d: %d)',
    [FName, minAmount, FConsumed, FProduced]);
{$ENDIF}
    FConsumerIsWaiting := True;
    amount := GetProducedAmount();
    if (amount >= minAmount) or FAtEnd then
    begin
      FConsumerIsWaiting := False;
{$IFDEF DEBUG}
      WriteLn(Format('%s: got %d bytes', [FName, amount]));
{$ENDIF}
      Result := amount;
    end
    else
    begin
      EnterCriticalSection(FLock);
      while (not FAtEnd) do
      begin
        amount := GetProducedAmount();
        if (amount < minAmount) then    //等待达到最底线
        begin
{$IFDEF DEBUG}
          WriteLn(Format('%s: ..Waiting for %d bytes(%d: %d)',
            [FName, minAmount, FConsumed, FProduced]);
{$ENDIF}
            ResetEvent(FEvent);
            LeaveCriticalSection(FLock);

            r := WaitForSingleObject(FEvent, waitTime);
            EnterCriticalSection(FLock);

            if (r = WAIT_TIMEOUT) then
            begin
              amount := GetProducedAmount();
              Break;
            end;
        end
        else
          Break;
      end;                              //end while
      LeaveCriticalSection(FLock);
{$IFDEF DEBUG}
      WriteLn(Format('%s: Got them %d(for %d) %s',
        [FName, amount, minAmount, BoolToStr(FAtEnd)]));
{$ENDIF}
      FConsumerIsWaiting := False;
      Result := amount;
    end;
end;

function TProduceConsum.Consume(amount: UINT): Integer;
begin
  Result := _ConsumeAny(amount, INFINITE);
end;

function TProduceConsum.ConsumeAny: Integer;
begin
  Result := _ConsumeAny(1, INFINITE);
end;

function TProduceConsum.ConsumeAnyContiguous: Integer;
begin
  Result := ConsumeContiguousMinAmount(1);
end;

function TProduceConsum.ConsumeAnyWithTimeout(waitTime: UINT): Integer;
begin
  Result := _ConsumeAny(1, waitTime);
end;

function TProduceConsum.ConsumeContiguousMinAmount(amount: UINT): Integer;
var
  l                 : Integer;
begin
  Result := _ConsumeAny(amount, INFINITE);
  l := FSize - (FConsumed mod FSize);
  if (Result > l) then
    Result := l;
end;

function TProduceConsum.Consumed(amount: UINT): Integer;
var
  consumed          : UINT;
begin
  consumed := FConsumed;
  if (consumed >= FDoubSize - amount) then
    Inc(consumed, amount - FDoubSize)
  else
    Inc(consumed, amount);

  FConsumed := consumed;
  Result := amount;
end;

function TProduceConsum.GetConsumerPosition: UINT;
begin
  Result := FConsumed mod FSize;
end;

function TProduceConsum.GetProducedAmount: Integer;
begin
  if (FProduced < FConsumed) then
    Result := FProduced + FDoubSize - FConsumed
  else
    Result := FProduced - FConsumed;
end;

function TProduceConsum.GetProducerPosition: UINT;
begin
  Result := FProduced mod FSize;
end;

function TProduceConsum.GetSize: UINT;
begin
  Result := FSize;
end;

end.

