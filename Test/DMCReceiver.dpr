program DMCReceiver;

{$APPTYPE CONSOLE}

uses
  Windows,
  SysUtils,
  fileReceiver_u in 'fileReceiver_u.pas';

begin
  if ParamCount < 1 then
    MessageBox(0,
      '���ڼ��ϲ��� "�ļ�����λ��!"'#13#13'DMCReceiver.exe d:\test.rar', '��ʾ', 0)
  else
    RunReceiver(ParamStr(1));
end.
