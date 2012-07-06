library DMCReceiver;

uses
  FastMM4 in '..\Include\FastMM4.pas',
  FastMM4Messages in '..\Include\FastMM4Messages.pas',
  DMCReceiver_u in 'DMCReceiver_u.pas',
  Negotiate_u in 'Negotiate_u.pas',
  RecvData_u in 'RecvData_u.pas',
  Config_u in '..\Public\Config_u.pas',
  Fifo_u in '..\Public\Fifo_u.pas',
  Func_u in '..\Public\Func_u.pas',
  Produconsum_u in '..\Public\Produconsum_u.pas',
  Protoc_u in '..\Public\Protoc_u.pas',
  SockLib_u in '..\Public\SockLib_u.pas',
  Console_u in '..\Public\Console_u.pas';

{$R *.res}

exports
  DMCConfigFill,
  DMCNegoCreate,
  DMCNegoDestroy,
  DMCDataReadWait,
  DMCDataReaded,
  DMCNegoWaitEnded,
  DMCStatsTotalBytes;

begin

end.

