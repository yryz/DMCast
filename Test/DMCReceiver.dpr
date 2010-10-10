program DMCReceiver;

{$APPTYPE CONSOLE}

uses
  Windows,
  SysUtils,
  fileReceiver_u in 'fileReceiver_u.pas';

{$R *.res}
begin
  if ParamCount < 1 then
    MessageBox(0,
      '请加上参数 "文件保存位置"!'#13#13'DMCReceiver.exe d:\test.rar', '提示', 0)
  else
    RunReceiver(ParamStr(1));
end.

