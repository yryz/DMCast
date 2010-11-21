program DMCReceiver;

{$APPTYPE CONSOLE}

uses
  Windows,
  SysUtils,
  fileReceiver_u in 'fileReceiver_u.pas';

{$R *.res}
var
  s                 : string;
begin
  Write(MY_CRLF_LINE);
  Writeln('HOU文件多播(接收端) v1.0b');

  if ParamCount < 1 then
  begin
    write('输入文件保存目录(如d:\):');
    readln(s);
    if s = '' then
      Exit;
    Write(MY_CRLF_LINE);
  end
  else
    s := ParamStr(1);

  //Start
  RunReceiver(s);
end.

