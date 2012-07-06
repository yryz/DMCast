program DMCSender;

uses
  FastMM4 in '..\Include\FastMM4.pas',
  FastMM4Messages in '..\Include\FastMM4Messages.pas',
  {$IFDEF NO_DLL}
  DMCSender_u in '..\Send\DMCSender_u.pas',
  Negotiate_u in '..\Send\Negotiate_u.pas',
  Participants_u in '..\Send\Participants_u.pas',
  SendData_u in '..\Send\SendData_u.pas',
  Config_u in '..\Public\Config_u.pas',
  Fifo_u in '..\Public\Fifo_u.pas',
  Protoc_u in '..\Public\Protoc_u.pas',
  Produconsum_u in '..\Public\Produconsum_u.pas',
  Func_u in '..\Public\Func_u.pas',
  SockLib_u in '..\Public\SockLib_u.pas',
  Console_u in '..\Public\Console_u.pas',
  Route_u in '..\Include\Route_u.pas',
  {$ENDIF}
  Forms,
  frmCastFile_u in 'frmCastFile_u.pas' {frmCastFile};

{$R *.res}
begin
  Application.Initialize;
  Application.Title := 'HOUÎÄ¼þ¶à²¥';
  Application.CreateForm(TfrmCastFile, frmCastFile);
  Application.Run;
end.

