unit frmCastFile;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, XPMan, Buttons, ComCtrls, ExtCtrls, ImgList, WinSock,
  FuncLib, Participants_u, Config_u, UCastSender_u;

type
  TfrmUdpcast = class(TForm)
    dlgOpen1: TOpenDialog;
    XPManifest1: TXPManifest;
    stat1: TStatusBar;
    lvClient: TListView;
    pb1: TProgressBar;
    Panel1: TPanel;
    Label1: TLabel;
    edtFile: TEdit;
    SpeedButton1: TSpeedButton;
    btnTrans: TButton;
    ImageList1: TImageList;
    procedure btnTransClick(Sender: TObject);
    procedure SpeedButton1Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  frmUdpcast        : TfrmUdpcast;
  dwThID            : DWORD;

implementation

{$R *.dfm}

procedure ParticipantsChange(db: PParticipantsDb;
  index: Integer;
  addr: PSockAddrIn;
  isAdd: integer); stdcall;
var
  Item              : TListItem;
begin
  with frmUdpcast do
  begin
    if Boolean(isAdd) then
    begin
      Item := lvClient.Items.Add;
      Item.Caption := IntToStr(index);
      Item.SubItems.Add(inet_ntoa(addr^.sin_addr));
    end else
    begin
      Item := lvClient.FindCaption(-1, IntToStr(index), False, False, False);
      if Assigned(Item) then
        Item.ImageIndex := 1;
    end;
  end;
end;

procedure DisplaySenderStatus(totalBytes: Int64; retransmissions: Int64;
  blockSize: Integer;
  sliceSize: Integer;
  isFinal: Integer); stdcall;
begin
  with frmUdpcast do
  begin
    pb1.Position := totalBytes;
    stat1.Panels[0].Text := Format('[传输] %0.2fKB  [重传] %0.2fKB  [片大小] %d', [totalBytes / 1024, retransmissions / 1024, sliceSize])
  end;
end;

function TransThread(p: Pointer): Integer;
begin
  with frmUdpcast do
  begin
    btnTrans.Enabled := False;
    RunSender(edtFile.Text);
    btnTrans.Enabled := True;
  end;
end;

procedure TfrmUdpcast.btnTransClick(Sender: TObject);
begin
  if FileExists(edtFile.Text) then
  begin
    pb1.Position := 0;
    pb1.Max := GetFileSize(PChar(edtFile.Text));
    lvClient.Clear;
    //udpc_setDisplaySenderCallback(@DisplaySenderStatus);
    //udpc_setParticipantsStatusCallback(@ParticipantsChange);
    CloseHandle(BeginThread(nil, 0, @TransThread, nil, 0, dwThID));
  end;
end;

procedure TfrmUdpcast.SpeedButton1Click(Sender: TObject);
begin
  if dlgOpen1.Execute then
    edtFile.Text := dlgOpen1.FileName;
end;

end.

