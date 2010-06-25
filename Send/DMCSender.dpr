program DMCSender;

{$APPTYPE CONSOLE}
//{$DEFINE IS_MODULE}
uses
  Forms,
  frmCastFile_u in 'frmCastFile_u.pas' {frmUdpcast},
{$IFNDEF IS_MODULE}                     //核心为DLL模块
  Produconsum_u in '..\Public\Produconsum_u.pas',
  SendData_u in 'SendData_u.pas',
  Participants_u in 'Participants_u.pas',
  Func_u in '..\Public\Func_u.pas',
  Negotiate_u in 'Negotiate_u.pas',
  SockLib_u in '..\Public\SockLib_u.pas',
  Fifo_u in '..\Public\Fifo_u.pas',
{$ENDIF}
  Config_u in 'Config_u.pas',
  Protoc_u in '..\Public\Protoc_u.pas',
  Console_u in '..\Public\Console_u.pas',
  INegotiate_u in 'INegotiate_u.pas',
  IStats_u in '..\Public\IStats_u.pas';

{$R *.res}
begin
  Application.Initialize;
  Application.Title := '文件/数据多播';
  Application.CreateForm(TfrmCastFile, frmCastFile);
  Application.Run;
end.

