unit Stats_u;

interface
uses
  Windows, Sysutils, Messages, WinSock,
  Config_u, Func_u, IStats_u;

type
  TSenderStats = class(TInterfacedObject, ISenderStats)
  private
    FConfig: PNetConfig;
    FStatPeriod: DWORD;                 //状态显示周期
    FPeriodStart: DWORD;                //周期开始节拍
    FLastPosBytes: Int64;               //最后统计进度
    FTotalBytes: Int64;                 //传输总数
    FNrRetrans: Int64;                  //重传数
    FIsFinal: Boolean;                  //End Trans
  protected
    procedure DoDisplay();
  public
    constructor Create(config: PNetConfig; statPeriod: Integer);
    destructor Destroy; override;

    procedure BeginTrans();
    procedure EndTrans();
    procedure AddBytes(bytes: Integer);
    procedure AddRetrans(nrRetrans: Integer);
  end;

implementation

{ TSenderStats }

constructor TSenderStats.Create(config: PNetConfig; statPeriod: Integer);
begin
  FConfig := config;
  FStatPeriod := statPeriod;
end;

destructor TSenderStats.Destroy;
begin
  inherited;
end;

procedure TSenderStats.BeginTrans;
begin
  FIsFinal := False;
  FPeriodStart := GetTickCount;
end;

procedure TSenderStats.EndTrans;
begin
  FIsFinal := True;
  DoDisplay;
end;

procedure TSenderStats.AddBytes(bytes: Integer);
begin
  Inc(FTotalBytes, bytes);
  DoDisplay;
end;

procedure TSenderStats.AddRetrans(nrRetrans: Integer);
begin
  Inc(FNrRetrans, nrRetrans);
  DoDisplay;
end;

procedure TSenderStats.DoDisplay();
var
  tickNow, tdiff    : DWORD;
  blocks            : dword;
  bw, percent       : double;
  hOut              : THandle;
  conBuf            : TConsoleScreenBufferInfo;
begin
  tickNow := GetTickCount;
  tdiff := DiffTickCount(FPeriodStart, tickNow);

  if not FIsFinal and (tdiff < FStatPeriod) then Exit;

  //带宽统计
  bw := (FTotalBytes - FLastPosBytes) / tdiff * 1000; // Byte/s
  //重传块统计
  blocks := (FTotalBytes + FConfig^.blockSize - 1) div FConfig^.blockSize;
  if (blocks = 0) then percent := 0
  else percent := FNrRetrans / blocks;
  //显示状态
{$IFDEF CONSOLE}
  hOut := GetStdHandle(STD_OUTPUT_HANDLE);
  GetConsoleScreenBufferInfo(hOut, conBuf);
  conBuf.dwCursorPosition.X := 0;
  SetConsoleCursorPosition(hOut, conBuf.dwCursorPosition);

  Write(Format('bytes=%d speed=%s re-xmits=%d(%.2f%%) slice size=%d',
    [FTotalBytes, GetSizeKMG(Trunc(bw)), FNrRetrans, percent, FConfig^.sliceSize]));
{$ENDIF}
  FPeriodStart := GetTickCount;
  FLastPosBytes := FTotalBytes;
end;

end.

