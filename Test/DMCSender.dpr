program DMCSender;

uses
  Forms,
  frmCastFile_u in 'frmCastFile_u.pas' {frmCastFile};

{$R *.res}
begin
  Application.Initialize;
  Application.Title := 'HOUÎÄ¼þ¶à²¥';
  Application.CreateForm(TfrmCastFile, frmCastFile);
  Application.Run;
end.

