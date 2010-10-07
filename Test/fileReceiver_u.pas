unit fileReceiver_u;

interface

uses
  Windows, Messages, SysUtils, Classes, WinSock,
  FuncLib, Config_u, IStats_u;

type
  TReceiverStats = class(TInterfacedObject, IReceiverStats)
  private
    FConfig: PRecvConfig;
    FStartTime: DWORD;                  //传输开始时间
    FStatPeriod: DWORD;                 //状态显示周期
    FPeriodStart: DWORD;                //周期开始节拍
    FLastPosBytes: Int64;               //最后统计进度
    FTotalBytes: Int64;                 //传输总数

    FTransState: TTransState;           //传输状态(进度)
  protected
    procedure DoDisplay();
  public
    constructor Create(config: PRecvConfig; statPeriod: Integer);
    destructor Destroy; override;

    procedure TransStateChange(TransState: TTransState);
    function TransState: TTransState;

    procedure AddBytes(bytes: Integer);
  end;

  TFileWriter = class(TThread)
  private
    FFile: TFileStream;
    FFifo: Pointer;
  protected
    procedure Execute; override;
  public
    constructor Create(fileName: string; lpFifo: Pointer);
    destructor Destroy; override;
    procedure Terminate; overload;
  end;

function RunReceiver(const FileName: string): Boolean;
implementation
//{$DEFINE IS_IMPORT_MODULE}
{$IFNDEF IS_IMPORT_MODULE}
uses
  DMCReceiver_u;
{$ELSE}
//API接口
const
  DMC_RECEIVER_DLL  = 'DMCReceiver.dll';

function DMCConfigFill(var config: TNetConfig): Boolean;
  external DMC_RECEIVER_DLL;

function DMCNegoCreate(config: PNetConfig; TransStats: IReceiverStats;
  var lpFifo: Pointer): Pointer; stdcall;
  external DMC_RECEIVER_DLL;

function DMCDataReadWait(lpFifo: Pointer; var dwBytes: DWORD): Pointer; stdcall;
  external DMC_RECEIVER_DLL;

function DMCDataReaded(lpFifo: Pointer; dwBytes: DWORD): Boolean; stdcall;
  external DMC_RECEIVER_DLL;

function DMCNegoWaitEnded(lpNego: Pointer): Boolean; stdcall;
  external DMC_RECEIVER_DLL;

function DMCNegoDestroy(lpNego: Pointer): Boolean; stdcall;
  external DMC_RECEIVER_DLL;
{$ENDIF}

{ TReceiverStats }

constructor TReceiverStats.Create(config: PRecvConfig; statPeriod: Integer);
begin
  FConfig := config;
  FStatPeriod := statPeriod;
end;

destructor TReceiverStats.Destroy;
begin
  inherited;
end;

procedure TReceiverStats.TransStateChange;
begin
  FTransState := TransState;
  case TransState of
    tsNego:
      begin
{$IFDEF CONSOLE}
        Writeln('Start Negotiations...');
{$ENDIF}
      end;
    tsTransing:
      begin
        FStartTime := GetTickCount;
        FPeriodStart := FStartTime;
{$IFDEF CONSOLE}
        Writeln('Start Trans..');
{$ENDIF}
      end;
    tsComplete:
      begin
        DoDisplay;
{$IFDEF CONSOLE}
        Writeln('Transfer Completed.');
{$ENDIF}
      end;
    tsExcept:
      begin
{$IFDEF CONSOLE}
        Writeln('Transfer Except!');
{$ENDIF}
      end;
    tsStop:
      begin
{$IFDEF CONSOLE}
        Writeln('Stop.');
{$ENDIF}
      end;
  end;
end;

procedure TReceiverStats.AddBytes(bytes: Integer);
begin
  Inc(FTotalBytes, bytes);
  DoDisplay;
end;

procedure TReceiverStats.DoDisplay();
var
  tickNow, tdiff    : DWORD;
  bw                : double;
  hOut              : THandle;
  conBuf            : TConsoleScreenBufferInfo;
begin
  tickNow := GetTickCount;

  if FTransState = tsTransing then
  begin
    tdiff := DiffTickCount(FPeriodStart, tickNow);
    if (tdiff < FStatPeriod) then
      Exit;
    //带宽统计
    bw := (FTotalBytes - FLastPosBytes) / tdiff * 1000; // Byte/s
  end
  else
  begin
    tdiff := DiffTickCount(FStartTime, tickNow);
    if tdiff = 0 then
      tdiff := 1;
    //平均带宽统计
    bw := FTotalBytes / tdiff * 1000;   // Byte/s
  end;

  //显示状态
{$IFDEF CONSOLE}
  hOut := GetStdHandle(STD_OUTPUT_HANDLE);
  GetConsoleScreenBufferInfo(hOut, conBuf);
  conBuf.dwCursorPosition.X := 0;
  SetConsoleCursorPosition(hOut, conBuf.dwCursorPosition);

  Write(Format('bytes=%d(%s)'#9'speed=%s/s'#9#9,
    [FTotalBytes, GetSizeKMG(FTotalBytes), GetSizeKMG(Trunc(bw))]));
{$ENDIF}
  FPeriodStart := GetTickCount;
  FLastPosBytes := FTotalBytes;
end;

function TReceiverStats.TransState: TTransState;
begin
  Result := FTransState;
end;

{ TFileWriter }

constructor TFileWriter.Create(fileName: string; lpFifo: Pointer);
begin
  FFifo := lpFifo;
  FFile := TFileStream.Create(fileName, fmShareDenyNone or fmCreate);
  inherited Create(False);
end;

destructor TFileWriter.Destroy;
begin
  if Assigned(FFile) then
    FFile.Free;
  inherited;
end;

procedure TFileWriter.Execute;
var
  lpBuf             : PByte;
  dwBytes           : DWORD;
begin
  while not Terminated do
  begin
    dwBytes := 4096;
    lpBuf := DMCDataReadWait(FFifo, dwBytes); //等待数据
    if (lpBuf = nil) or Terminated then
      Break;

    dwBytes := FFile.Write(lpBuf^, dwBytes);
    DMCDataReaded(FFifo, dwBytes);
  end;
end;

procedure TFileWriter.Terminate;
begin
  inherited Terminate;
  DMCDataReaded(FFifo, 0);
  WaitFor;
end;

function RunReceiver(const FileName: string): Boolean;
var
  config            : TRecvConfig;
  Nego              : Pointer;
  Fifo              : Pointer;
  ReceiverStats     : IReceiverStats;

  FileWriter        : TFileWriter;
begin
  //默认配置
  DMCConfigFill(config);

{$IFDEF CONSOLE}
  WriteLn('File Save to ', fileName);
  //Writeln(SizeOf(config));
{$ENDIF}

  ReceiverStats := TReceiverStats.Create(@config, DEFLT_STAT_PERIOD);
  Nego := DMCNegoCreate(@config, ReceiverStats, Fifo);

  if Assigned(Fifo) then
    FileWriter := TFileWriter.Create(fileName, Fifo);

  DMCNegoWaitEnded(Nego);
  DMCNegoDestroy(Nego);

  FileWriter.WaitFor;
  FileWriter.Free;
end;

end.

