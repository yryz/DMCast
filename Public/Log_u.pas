unit Log_u;

interface
uses
  Windows, Sysutils, WinSock, Config_u;

var
  g_udpc_log        : THandle;

function logprintf(logfile: THandle; fmt: PChar; const Args: array of const): Integer;
implementation
{**
 * Print message to the log, if not null
 *}

function logprintf(logfile: THandle; fmt: PChar; const Args: array of const): Integer;
var
  s                 : string;
begin
  if logfile > 0 then
  begin
    s := FormatDateTime('hh:mm:ss.nnn ', Now) + Format(fmt, Args);
    Result := FileWrite(logfile, s[1], Length(s));
  end else
    Result := -1;
end;
end.
