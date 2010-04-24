program UCastSender;

{$APPTYPE CONSOLE}

uses
  Forms,
  frmCastFile in 'frmCastFile.pas' {frmUdpcast},
  Config_u in '..\Public\Config_u.pas',
  DiskIO_u in '..\Public\DiskIO_u.pas',
  Protoc_u in '..\Public\Protoc_u.pas',
  FIFO_u in '..\Public\FIFO_u.pas',
  Produconsum_u in '..\Public\Produconsum_u.pas',
  SendData_u in 'SendData_u.pas',
  Participants_u in 'Participants_u.pas',
  Func_u in '..\Public\Func_u.pas',
  SockLib_u in '..\Public\SockLib_u.pas',
  Negotiate_u in 'Negotiate_u.pas',
  SenderStats_u in 'SenderStats_u.pas',
  Log_u in '..\Public\Log_u.pas',
  Console_u in '..\Public\Console_u.pas',
  UCastSender_u in 'UCastSender_u.pas';

begin
  Application.Initialize;
  Application.CreateForm(TfrmUdpcast, frmUdpcast);
  Application.Run;
end.

