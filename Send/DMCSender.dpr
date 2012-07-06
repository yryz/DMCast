library DMCSender;

uses
  FastMM4 in '..\Include\FastMM4.pas',
  FastMM4Messages in '..\Include\FastMM4Messages.pas',
  DMCSender_u in 'DMCSender_u.pas',
  Negotiate_u in 'Negotiate_u.pas',
  Participants_u in 'Participants_u.pas',
  SendData_u in 'SendData_u.pas',
  Config_u in '..\Public\Config_u.pas',
  Fifo_u in '..\Public\Fifo_u.pas',
  Protoc_u in '..\Public\Protoc_u.pas',
  Produconsum_u in '..\Public\Produconsum_u.pas',
  Func_u in '..\Public\Func_u.pas',
  SockLib_u in '..\Public\SockLib_u.pas',
  Console_u in '..\Public\Console_u.pas',
  Route_u in '..\Include\Route_u.pas';

{$R *.res}

exports
  DMCConfigFill,
  DMCNegoCreate,
  DMCNegoDestroy,
  DMCDataWriteWait,
  DMCDataWrited,
  DMCTransferCtrl,
  DMCStatsSliceSize,
  DMCStatsTotalBytes,
  DMCStatsBlockRetrans;

begin

end.

