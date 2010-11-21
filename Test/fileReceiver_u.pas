unit fileReceiver_u;

interface

uses
  Windows, Messages, SysUtils, MyClasses, WinSock,
  FuncLib, Config_u, HouLog_u, fileWriter_u;

const
  MY_CRLF_LINE      = '┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈┈'#13#10;

var
  g_Nego            : Pointer;
  g_Fifo            : Pointer;
  g_TransState      : TTransState;

  { 速度统计 }
  g_StatsTimer      : THandle;
  g_TransStartTime  : DWORD;
  g_TransPeriodStart: DWORD;
  g_LastPosBytes    : Int64;

  g_WaitTimer       : THandle;

procedure Writeln(s: string);
function RunReceiver(const FileName: string): Boolean;

procedure OnTransStateChange(TransState: TTransState);
procedure DoDisplayStats;
implementation
{$INCLUDE DMCReceiver.inc}

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
        SetEvent(g_WaitTimer);
      end;
    tsExcept:
      begin
{$IFDEF CONSOLE}
        Writeln('Transfer Except!');
{$ENDIF}
        SetEvent(g_WaitTimer);
      end;

    tsStop:
      begin
{$IFDEF CONSOLE}
        Writeln('Stop.');
{$ENDIF}
        SetEvent(g_WaitTimer);
      end;
  end;
end;

procedure DoDisplayStats;
var
  hOut              : THandle;
  conBuf            : TConsoleScreenBufferInfo;

  totalBytes, bwBytes: Int64;
  tickNow, tdiff    : DWORD;

  bw                : Double;
begin
  tickNow := GetTickCount;
  totalBytes := DMCStatsTotalBytes(g_Nego);

  if g_TransState = tsTransing then
  begin
    tdiff := DiffTickCount(g_TransPeriodStart, tickNow);
    bwBytes := totalBytes - g_LastPosBytes;
  end
  else
  begin
    tdiff := DiffTickCount(g_TransStartTime, tickNow);
    bwBytes := totalBytes;
  end;
  if tdiff = 0 then
    tdiff := 1;
  //平均带宽统计
  bw := bwBytes * 1000 / tdiff;         // Byte/s

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

function ConsoleCtrlHandler(dwSignal: DWORD): BOOL; stdcall;
begin
  case dwSignal of
    CTRL_C_EVENT,                       //用户按下[Ctrl][C]。
    CTRL_BREAK_EVENT,                   //用户按下[Ctrl][Break]。
    CTRL_CLOSE_EVENT,                   //用户试图关闭控制台窗口。
    CTRL_LOGOFF_EVENT,                  //用户试图从系统注销。
    CTRL_SHUTDOWN_EVENT:                //用户试图关闭计算机。
      begin
        if g_Nego <> nil then
        begin
          DMCDataReaded(g_Fifo, 0);
          DMCNegoDestroy(g_Nego);
          g_Nego := nil;
        end;
      end;
  end;
end;

function RunReceiver(const FileName: string): Boolean;
var
  p                 : Pointer;
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

  if g_Nego = nil then
  begin
{$IFDEF EN_LOG}
    OutLog('DMCNegoCreate Fail!');
{$ENDIF}
    Exit;
  end;

  SetConsoleCtrlHandler(@ConsoleCtrlHandler, True);
  FileWriter := TFileWriter.Create(fileName, g_Fifo);

  while WaitForSingleObject(g_WaitTimer, 1000) = WAIT_TIMEOUT do
  begin
    if g_TransState = tsTransing then
      DoDisplayStats;
  end;

  FileWriter.WaitFor;                   //等待缓冲写入完成

  SetConsoleCtrlHandler(@ConsoleCtrlHandler, False);
  DMCNegoWaitEnded(g_Nego);
  DMCNegoDestroy(g_Nego);
  g_Nego := nil;
  FileWriter.Free;
end;

procedure Writeln(s: string);
begin
  System.Write(s + #13#10 + MY_CRLF_LINE);
end;

{$IFDEF CONSOLE}

procedure MyOutLog2(level: TLogLevel; s: string);
begin
  System.Writeln(LOG_MSG_TYPE[level], ': ', s);
end;
{$ENDIF}

initialization
{$IFDEF EN_LOG}
{$IFDEF CONSOLE}
  OutLog2 := MyOutLog2;
{$ENDIF}
{$ENDIF}
  g_WaitTimer := CreateEvent(nil, True, False, nil);

finalization
  CloseHandle(g_WaitTimer);

end.

