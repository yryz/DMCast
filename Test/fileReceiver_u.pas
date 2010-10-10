unit fileReceiver_u;

interface

uses
  Windows, Messages, SysUtils, MyClasses, WinSock,
  FuncLib, Config_u, Window_u, HouLog_u;

type
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

var
  g_Nego            : Pointer;
  g_Fifo            : Pointer;
  g_TransState      : TTransState;

  { 速度统计 }
  g_StatsTimer      : THandle;
  g_TransStartTime  : DWORD;
  g_TransPeriodStart: DWORD;
  g_LastPosBytes    : Int64;

function RunReceiver(const FileName: string): Boolean;

procedure OnTransStateChange(TransState: TTransState);
procedure DoDisplayStats;
implementation
{$DEFINE IS_IMPORT_MODULE}
{$IFNDEF IS_IMPORT_MODULE}
uses
  DMCReceiver_u;
{$ELSE}
//API接口
const
  DMC_RECEIVER_DLL  = 'DMCReceiver.dll';

  //填充默认配置

procedure DMCConfigFill(var config: TRecvConfig); stdcall;
  external DMC_RECEIVER_DLL;

//开始会话  TransStats 可以为nil

function DMCNegoCreate(config: PRecvConfig; OnTransStateChange: TOnTransStateChange;
  var lpFifo: Pointer): Pointer; stdcall;
  external DMC_RECEIVER_DLL;

//结束会话

function DMCNegoDestroy(lpNego: Pointer): Boolean; stdcall;
  external DMC_RECEIVER_DLL;

//等待数据缓冲区可读

function DMCDataReadWait(lpFifo: Pointer; var dwBytes: DWORD): Pointer; stdcall;
  external DMC_RECEIVER_DLL;

//数据已消耗(以从缓冲区取出)

function DMCDataReaded(lpFifo: Pointer; dwBytes: DWORD): Boolean; stdcall;
  external DMC_RECEIVER_DLL;

//等待会话结束(确保安全断开会话)

function DMCNegoWaitEnded(lpNego: Pointer): Boolean; stdcall;
  external DMC_RECEIVER_DLL;

//统计已经传输Bytes

function DMCStatsTotalBytes(lpNego: Pointer): Int64; stdcall;
  external DMC_RECEIVER_DLL;
{$ENDIF}

{ TReceiverStats }

procedure OnTransStateChange(TransState: TTransState);
begin
  g_TransState := TransState;
  case TransState of
    tsNego:
      begin
{$IFDEF CONSOLE}
        Writeln('Start Negotiations...');
{$ENDIF}
      end;
    tsTransing:
      begin
        g_TransStartTime := GetTickCount;
        g_TransPeriodStart := g_TransStartTime;
        g_StatsTimer := SetTimer(WinHandle, 0, 1000, nil);
{$IFDEF CONSOLE}
        Writeln('Start Trans..');
{$ENDIF}
      end;
    tsComplete:
      begin
        DoDisplayStats;
{$IFDEF CONSOLE}
        Writeln('Transfer Complete.');
{$ENDIF}
        PostMessage(WinHandle, WM_QUIT, 0, 0);
      end;
    tsExcept:
      begin
{$IFDEF CONSOLE}
        Writeln('Transfer Except!');
{$ENDIF}
        PostMessage(WinHandle, WM_QUIT, 0, 0);
      end;

    tsStop:
      begin
{$IFDEF CONSOLE}
        Writeln('Stop.');
{$ENDIF}
        PostMessage(WinHandle, WM_QUIT, 0, 0);
      end;
  end;
end;

procedure DoDisplayStats;
var
  hOut              : THandle;
  conBuf            : TConsoleScreenBufferInfo;

  totalBytes        : Int64;
  tickNow, tdiff    : DWORD;

  bw                : Double;
begin
  if g_Nego = nil then
  begin
    KillTimer(WinHandle, g_StatsTimer);
    Exit;
  end;

  tickNow := GetTickCount;
  totalBytes := DMCStatsTotalBytes(g_Nego);

  tdiff := DiffTickCount(g_TransStartTime, tickNow);
  if tdiff = 0 then
    tdiff := 1;
  //平均带宽统计
  bw := totalBytes * 1000 / tdiff;      // Byte/s

  //显示状态
{$IFDEF CONSOLE}
  hOut := GetStdHandle(STD_OUTPUT_HANDLE);
  GetConsoleScreenBufferInfo(hOut, conBuf);
  conBuf.dwCursorPosition.X := 0;
  SetConsoleCursorPosition(hOut, conBuf.dwCursorPosition);

  Write(Format('bytes=%d(%s)'#9'speed=%s/s'#9#9,
    [totalBytes, GetSizeKMG(totalBytes), GetSizeKMG(Trunc(bw))]));
  if g_TransState <> tsTransing then
    WriteLn('');
{$ENDIF}

  g_LastPosBytes := totalBytes;
  g_TransPeriodStart := GetTickCount;
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

{ End }

function RunReceiver(const FileName: string): Boolean;
var
  msg               : TMsg;
  config            : TRecvConfig;
  FileWriter        : TFileWriter;
begin
  //默认配置
  DMCConfigFill(config);

{$IFDEF EN_LOG}
  OutLog('File Save to ' + fileName);
{$ELSE}
{$IFDEF CONSOLE}
  WriteLn('File Save to ' + fileName);
{$ENDIF}
{$ENDIF}

  g_Nego := DMCNegoCreate(@config, OnTransStateChange, g_Fifo);

  if Assigned(g_Fifo) then
    FileWriter := TFileWriter.Create(fileName, g_Fifo);

  while GetMessage(msg, 0, 0, 0) do
  begin
    case msg.message of
      WM_TIMER: DoDisplayStats;
      WM_QUIT: Break;
    else
      TranslateMessage(msg);
      DispatchMessage(msg);
    end;
  end;

  DMCNegoWaitEnded(g_Nego);
  DMCNegoDestroy(g_Nego);

  FileWriter.WaitFor;
  FileWriter.Free;
end;

{$IFDEF EN_LOG}
{$IFDEF CONSOLE}

procedure MyOutLog2(level: TLogLevel; s: string);
begin
  Writeln(DMC_MSG_TYPE[level], ': ', s);
end;

initialization
  OutLog2 := MyOutLog2;
{$ENDIF}
{$ENDIF}

end.

