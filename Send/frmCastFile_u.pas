unit frmCastFile_u;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, XPMan, Buttons, ComCtrls, ExtCtrls, ImgList, WinSock,
  FuncLib, Config_u, Protoc_u, INegotiate_u, Console_u, IStats_u, Spin;

type
  TfrmCastFile = class(TForm)
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
    btnStart: TButton;
    pnl1: TPanel;
    btnStop: TButton;
    grp1: TGroupBox;
    lbl1: TLabel;
    lbl2: TLabel;
    lbl3: TLabel;
    lbl4: TLabel;
    lblSliceSize: TLabel;
    lblRexmit: TLabel;
    lblSpeed: TLabel;
    lblTransBytes: TLabel;
    grp2: TGroupBox;
    grp3: TGroupBox;
    mmoLog: TMemo;
    chkAutoSliceSize: TCheckBox;
    lbl5: TLabel;
    seSliceSize: TSpinEdit;
    lbl6: TLabel;
    seWaitReceivers: TSpinEdit;
    procedure btnStartClick(Sender: TObject);
    procedure SpeedButton1Click(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure btnTransClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    FThread: THandle;
    FConsole: TConsole;
    FStats: ITransStats;
    FNrOnline: Integer;
  public
    function OnPartsChange(isAdd: Boolean; index: Integer;
      addr: PSockAddrIn): Boolean;
  end;

  TSenderStats = class(TInterfacedObject, ITransStats)
  private
    FConfig: PNetConfig;
    FStartTime: DWORD; //传输开始时间
    FStatPeriod: DWORD; //状态显示周期
    FPeriodStart: DWORD; //周期开始节拍
    FLastPosBytes: Int64; //最后统计进度
    FTotalBytes: Int64; //传输总数
    FNrRetrans: Int64; //重传数
    FTransmitting: Boolean;
  protected
    procedure DoDisplay();
  public
    constructor Create(config: PNetConfig; statPeriod: Integer);
    destructor Destroy; override;

    procedure BeginTrans();
    procedure EndTrans();
    procedure AddBytes(bytes: Integer);
    procedure AddRetrans(nrRetrans: Integer);
    procedure Msg(msgType: TUMsgType; msg: string);
    function Transmitting(): Boolean;
  end;

var
  frmCastFile: TfrmCastFile;
  dwThID: DWORD;
  g_Nego: INegotiate;
  g_Config: TNetConfig;
  g_FileName: string;

implementation

{$R *.dfm}

{ TSenderStats }

constructor TSenderStats.Create(config: PNetConfig; statPeriod: Integer);
begin
  FConfig := config;
  FStatPeriod := statPeriod;
end;

destructor TSenderStats.Destroy;
begin
  inherited;
end;

procedure TSenderStats.BeginTrans;
begin
  FTransmitting := True;
  FStartTime := GetTickCount;
  FPeriodStart := FStartTime;
end;

procedure TSenderStats.EndTrans;
begin
  FTransmitting := False;
  DoDisplay;
end;

procedure TSenderStats.AddBytes(bytes: Integer);
begin
  Inc(FTotalBytes, bytes);
  DoDisplay;
end;

procedure TSenderStats.AddRetrans(nrRetrans: Integer);
begin
  Inc(FNrRetrans, nrRetrans);
  DoDisplay;
end;

procedure TSenderStats.DoDisplay();
var
  tickNow, tdiff: DWORD;
  blocks: dword;
  bw, percent: double;
begin
  tickNow := GetTickCount;

  if FTransmitting then
  begin
    tdiff := DiffTickCount(FPeriodStart, tickNow);
    if (tdiff < FStatPeriod) then Exit;
    //带宽统计
    bw := (FTotalBytes - FLastPosBytes) / tdiff * 1000; // Byte/s
  end else
  begin
    tdiff := DiffTickCount(FStartTime, tickNow);
    if tdiff = 0 then tdiff := 1;
   //平均带宽统计
    bw := FTotalBytes / tdiff * 1000; // Byte/s
  end;

  //重传块统计
  blocks := (FTotalBytes + FConfig^.blockSize - 1) div FConfig^.blockSize;
  if blocks = 0 then percent := 0
  else percent := FNrRetrans / blocks;
  //显示状态

  frmCastFile.pb1.Position := FTotalBytes;
  frmCastFile.lblTransBytes.Caption := GetSizeKMG(FTotalBytes);
  frmCastFile.lblSpeed.Caption := GetSizeKMG(Trunc(bw));
  frmCastFile.lblRexmit.Caption := Format('%d(%.2f%%)', [FNrRetrans, percent]);
  frmCastFile.lblSliceSize.Caption := IntToStr(FConfig^.sliceSize);

  FPeriodStart := GetTickCount;
  FLastPosBytes := FTotalBytes;
end;

procedure TSenderStats.Msg(msgType: TUMsgType; msg: string);
var
  s: string;
begin
  s := '[' + DMC_MSG_TYPE[msgType] + '] ' + msg;
  frmCastFile.mmoLog.Lines.Insert(0, s);
end;

function TSenderStats.Transmitting: Boolean;
begin
  Result := FTransmitting;
end;

{!--END--}

function TransThread(p: Pointer): Integer;
begin
  try
    if g_Nego.StartNegotiate > 0 then
      g_Nego.DoTransfer;
  finally
    PostMessage(frmCastFile.btnStop.Handle, WM_LBUTTONDOWN, 0, 0);
    PostMessage(frmCastFile.btnStop.Handle, WM_LBUTTONUP, 0, 0);
  end;
end;

function TfrmCastFile.OnPartsChange(isAdd: Boolean; index: Integer;
  addr: PSockAddrIn): Boolean;
var
  Item: TListItem;
begin
  Result := True;
  if isAdd then
  begin
    Inc(FNrOnline);
    Item := frmCastFile.lvClient.Items.Add;
    Item.Caption := IntToStr(index);
    Item.SubItems.Add(inet_ntoa(addr^.sin_addr));
  end
  else begin
    Item := frmCastFile.lvClient.FindCaption(-1, IntToStr(index), False, False, False);
    if Assigned(Item) then begin
      Item.ImageIndex := 1;
      Dec(FNrOnline);
    end;
  end;
  btnTrans.Enabled := FNrOnline > 0;
  stat1.Panels[0].Text := '客户端: '
    + IntToStr(FNrOnline) + '/' + IntToStr(lvClient.Items.Count);
end;

procedure TfrmCastFile.btnStartClick(Sender: TObject);
begin
  g_FileName := edtFile.Text; //防止“引用”出错
  if FileExists(g_FileName) then
  begin
    pb1.Position := 0;
    pb1.Max := GetFileSize(PAnsiChar(g_FileName));
    FNrOnline := 0;
    lvClient.Clear;
    btnStart.Enabled := False;

    //配置
    FillChar(g_Config, SizeOf(g_Config), 0);

    g_Config.ifName := 'eth0'; //eht0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
    g_Config.fileName := PAnsiChar(g_FileName);

{$IFDEF CONSOLE}
    g_Config.flags := [];
{$ELSE}
    g_Config.flags := [dmcNoKeyBoard]; //没有控制台!
{$ENDIF}
    g_Config.mcastRdv := nil; //传输地址
    g_Config.blockSize := 1456; //这个值在一些情况下（如家用无线），设置大点效果会好些如10K
    g_Config.sliceSize := MIN_SLICE_SIZE;
    g_Config.localPort := 9080;
    g_Config.remotePort := 8090;
    g_Config.nrGovernors := 0;

    if chkAutoSliceSize.Checked then
      g_Config.flags := g_Config.flags + [dmcNotFullDuplex];

    g_Config.capabilities := 0;
    g_Config.min_slice_size := MIN_SLICE_SIZE;
    g_Config.max_slice_size := MAX_SLICE_SIZE;
    g_Config.default_slice_size := seSliceSize.Value; //=0 则根据情况自动选择
    g_Config.ttl := 1;
    g_Config.rexmit_hello_interval := 0; //retransmit hello message
    g_Config.autostart := 0;
    g_Config.requestedBufSize := 0;

    g_Config.min_receivers := seWaitReceivers.Value;
    g_Config.max_receivers_wait := 0;
    g_Config.min_receivers_wait := 0;
    g_Config.startTimeout := 0;

    g_Config.retriesUntilDrop := 30; //sendReqack片重试次数 （原 200）
    g_Config.rehelloOffset := 50;

    FConsole := TConsole.Create;
    FStats := TSenderStats.Create(@g_Config, DEFLT_STAT_PERIOD);
    g_Nego := CreateNegotiateObject(@g_Config, FConsole, FStats,
      OnPartsChange);

    FThread := BeginThread(nil, 0, @TransThread, nil, 0, dwThID);
    btnStop.Enabled := True;
  end else
    MessageBox(Handle, '文件不存在!', '提示', MB_ICONWARNING);
end;

procedure TfrmCastFile.SpeedButton1Click(Sender: TObject);
begin
  if dlgOpen1.Execute then
    edtFile.Text := dlgOpen1.FileName;
end;

procedure TfrmCastFile.btnStopClick(Sender: TObject);
begin
  if not btnStop.Enabled then Exit; //已经手动停止中？
  btnStop.Enabled := False;

  if Assigned(g_Nego) then begin
    g_Nego.AbortTransfer(0);
    if WaitForSingleObject(FThread, 2) = WAIT_TIMEOUT then
      Application.ProcessMessages;
    g_Nego := nil;
    FStats := nil;
  end;
  if FThread > 0 then begin
    CloseHandle(FThread);
    FThread := 0;
  end;

  if Assigned(FConsole) then FConsole.Free;

  btnStart.Enabled := True;
  btnTrans.Enabled := False;
end;

procedure TfrmCastFile.btnTransClick(Sender: TObject);
begin
  if Assigned(FConsole) then
    FConsole.PostPressed
  else
    btnStopClick(nil);
  btnTrans.Enabled := False;
end;

procedure TfrmCastFile.FormCreate(Sender: TObject);
begin
  mmoLog.DoubleBuffered := True;
  seSliceSize.MaxValue := MAX_SLICE_SIZE;
  seWaitReceivers.MaxValue := MAX_CLIENTS;
end;

end.

