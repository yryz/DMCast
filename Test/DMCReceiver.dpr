program DMCReceiver;

{$APPTYPE CONSOLE}

uses
  FastMM4 in '..\Include\FastMM4.pas',
  FastMM4Messages in '..\Include\FastMM4Messages.pas',
  DMCReceiver_u in '..\Recv\DMCReceiver_u.pas',
  Negotiate_u in '..\Recv\Negotiate_u.pas',
  RecvData_u in '..\Recv\RecvData_u.pas',
  Config_u in '..\Public\Config_u.pas',
  Fifo_u in '..\Public\Fifo_u.pas',
  Func_u in '..\Public\Func_u.pas',
  Produconsum_u in '..\Public\Produconsum_u.pas',
  Protoc_u in '..\Public\Protoc_u.pas',
  SockLib_u in '..\Public\SockLib_u.pas',
  Console_u in '..\Public\Console_u.pas',
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

