program DMCSender;

uses
  Forms,
  frmCastFile_u in 'frmCastFile_u.pas' {frmUdpcast};

{$R *.res}
begin
  Application.Initialize;
  Application.Title := '文件/数据多播';
  Application.CreateForm(TfrmCastFile, frmCastFile);
  Application.Run;
end.

