program DMCReceiver;

{$APPTYPE CONSOLE}

uses
  Windows,
  SysUtils,
  Config_u in 'Config_u.pas',
  Protoc_u in '..\Public\Protoc_u.pas',
  Produconsum_u in '..\Public\Produconsum_u.pas',
  RecvData_u in 'RecvData_u.pas',
  Func_u in '..\Public\Func_u.pas',
  Negotiate_u in 'Negotiate_u.pas',
  Stats_u in 'Stats_u.pas',
  Console_u in '..\Public\Console_u.pas',
  SockLib_u in '..\Public\SockLib_u.pas',
  UCastReceiver_u in 'UCastReceiver_u.pas',
  INegotiate_u in 'INegotiate_u.pas',
  Fifo_u in '..\Public\Fifo_u.pas',
  IStats_u in '..\Public\IStats_u.pas';

begin
  RunReceiver(ParamStr(1));
end.

