program UDP_Send;

{$APPTYPE CONSOLE}

uses
  //FastMM4 in '..\..\Include\FastMM4\FastMM4.pas',
  //FastMM4Messages in '..\..\Include\FastMM4\FastMM4Messages.pas',
  Config_u in 'Config_u.pas',
  Protoc_u in '..\Public\Protoc_u.pas',
  Produconsum_u in '..\Public\Produconsum_u.pas',
  SendData_u in 'SendData_u.pas',
  Participants_u in 'Participants_u.pas',
  Func_u in '..\Public\Func_u.pas',
  Negotiate_u in 'Negotiate_u.pas',
  Stats_u in 'Stats_u.pas',
  Log_u in '..\Public\Log_u.pas',
  Console_u in '..\Public\Console_u.pas',
  SockLib_u in '..\Public\SockLib_u.pas',
  UCastSender_u in 'UCastSender_u.pas',
  INegotiate_u in 'INegotiate_u.pas';

begin
  RunSender(ParamStr(1));
end.

