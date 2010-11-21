unit frmCastFile_u;

interface

uses
  Windows, Messages, SysUtils, Classes, Variants, Graphics, Controls, Forms,
  Dialogs, StdCtrls, XPMan, Buttons, ComCtrls, ExtCtrls, ImgList, WinSock,
  FuncLib, Config_u, Spin, ShellAPI, fileReader_u, ShlObj;

const
  WM_UPDATE_ONLINE  = WM_USER + 1;
  WM_AUTO_STOP      = WM_USER + 2;
  WM_FILE_POSITION  = WM_USER + 3;

type
  TfrmCastFile = class(TForm)
    dlgOpen1: TOpenDialog;
    XPManifest1: TXPManifest;
    stat1: TStatusBar;
    lvClient: TListView;
    Panel1: TPanel;
    edtFile: TEdit;
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
    chkAutoSliceSize: TCheckBox;
    lbl5: TLabel;
    seSliceSize: TSpinEdit;
    grp4: TGroupBox;
    lbl6: TLabel;
    seWaitReceivers: TSpinEdit;
    chkLoopStart: TCheckBox;
    chkStreamMode: TCheckBox;
    seRetriesUntilDrop: TSpinEdit;
    lbl7: TLabel;
    lbl8: TLabel;
    lbl9: TLabel;
    seMaxWait: TSpinEdit;
    lblFile: TLabel;
    lblFileSize: TLabel;
    pb1: TProgressBar;
    tmrStats: TTimer;
    lbl10: TLabel;
    seXmitRate: TSpinEdit;
    cbbInterface: TComboBox;
    lbl11: TLabel;
    lbl12: TLabel;
    lblTotalTime: TLabel;
    cbb1: TComboBox;

    procedure btnStartClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure btnTransClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure lbl8Click(Sender: TObject);
    procedure tmrStatsTimer(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure SpinEditChange(Sender: TObject);
    procedure cbb1Change(Sender: TObject);
  private
    FNego: Pointer;
    FFifo: Pointer;

    FConfig: TSendConfig;
    procedure UpdateOnline(var Msg: TMessage); message WM_UPDATE_ONLINE;
    procedure OnAutoStop(var Msg: TMessage); message WM_AUTO_STOP;

    procedure OnFilePosition(Sender: TFileReader);

    procedure LoadSaveConfig(isLoad: Boolean);
    procedure GetAllInterface;
  public

  end;

var
  frmCastFile       : TfrmCastFile;
  g_FileSize        : Int64;
  g_FileReader      : TFileReader;
  g_TransState      : TTransState;

  g_NrOnline        : Integer;
  { 速度统计 }
  g_TransStartTime  : DWORD;
  g_TransPeriodStart: DWORD;
  g_LastPosBytes    : Int64;

procedure OnTransStateChange(TransState: TTransState);
function OnPartsChange(index: Integer; addr: PSockAddrIn;
  lpParam: PClientParam): Boolean;

implementation
{$INCLUDE DMCSender.inc}

{$R *.dfm}

{ TSenderStats }

procedure OnTransStateChange(TransState: TTransState);
begin
  g_TransState := TransState;
  case TransState of
    tsNego:
      begin
        g_NrOnline := 0;
        frmCastFile.tmrStatsTimer(nil); //Stats Clear 0
{$IFDEF CONSOLE}
        Writeln('Start Negotiations...');
{$ENDIF}
      end;
    tsTransing:
      begin
        g_FileReader.Resume;

        g_TransStartTime := GetTickCount;
        g_TransPeriodStart := g_TransStartTime;
        frmCastFile.tmrStats.Enabled := True;
        //auto trans ?
        frmCastFile.btnTransClick(nil);
{$IFDEF CONSOLE}
        Writeln('Start Trans..');
{$ENDIF}
      end;
    tsComplete:
      begin
        frmCastFile.tmrStatsTimer(nil);
        frmCastFile.stat1.Panels[1].Text := '传输完成.';
{$IFDEF CONSOLE}
        Writeln('Transfer Complete.');
{$ENDIF}
      end;
    tsExcept:
      begin
{$IFDEF CONSOLE}
        Writeln('Transfer Except!');
{$ENDIF}
      end;

    tsStop:
      begin
        PostMessage(frmCastFile.Handle, WM_AUTO_STOP, 0, 0);
{$IFDEF CONSOLE}
        Writeln('Stop.');
{$ENDIF}
      end;
  end;
end;

function OnPartsChange(index: Integer; addr: PSockAddrIn;
  lpParam: PClientParam): Boolean;
var
  Item              : TListItem;
begin
  Result := True;

  if lpParam <> nil then
  begin                                 //Add
    Inc(g_NrOnline);
    Item := frmCastFile.lvClient.Items.Add;
    Item.Caption := IntToStr(index);
    Item.SubItems.Add(inet_ntoa(addr^.sin_addr));
    Item.SubItems.Add(GetSizeKMG(lpParam^.sockBuf));
  end
  else                                  //Remove
  begin
    Item := frmCastFile.lvClient.FindCaption(-1, IntToStr(index), False, False, False);
    if Assigned(Item) then
    begin
      Item.ImageIndex := 1;
      Dec(g_NrOnline);
    end;
  end;

  PostMessage(frmCastFile.Handle, WM_UPDATE_ONLINE, 0, 0);
end;

procedure TfrmCastFile.tmrStatsTimer(Sender: TObject);
var
  totalBytes, bwBytes: Int64;
  tickNow, tdiff    : DWORD;
  rexmitBlocks      : dword;
  bw, percent       : double;
begin
  if g_TransState in [tsComplete, tsStop, tsExcept] then //停止?
    tmrStats.Enabled := False;

  if FNego = nil then
  begin
    tmrStats.Enabled := False;
    Exit;
  end;

  tickNow := GetTickCount;
  totalBytes := DMCStatsTotalBytes(FNego);

  if g_TransState = tsTransing then
  begin
    tdiff := DiffTickCount(g_TransPeriodStart, tickNow);
    bwBytes := totalBytes - g_LastPosBytes;
  end
  else
  begin
    tdiff := DiffTickCount(g_TransStartTime, tickNow);
    bwBytes := totalBytes;
  end;
  if tdiff = 0 then
    tdiff := 1;

  //平均带宽统计
  bw := bwBytes * 1000 / tdiff;         // Byte/s

  //重传块统计
  rexmitBlocks := DMCStatsBlockRetrans(FNego);
  if rexmitBlocks < 1 then
    percent := 0
  else
    percent := rexmitBlocks / (totalBytes div FConfig.blockSize);

  //显示状态
  if g_FileSize > 0 then
    pb1.Position := totalBytes * 100 div g_FileSize;
  lblTransBytes.Caption := GetSizeKMG(totalBytes);
  lblSpeed.Caption := GetSizeKMG(Trunc(bw)) + '/s';
  lblRexmit.Caption := Format('%d(%.2f%%)', [rexmitBlocks, percent]);
  lblSliceSize.Caption := IntToStr(DMCStatsSliceSize(FNego));
  if g_TransState = tsTransing then
    lblTotalTime.Caption := MSecondToTimeStr(DiffTickCount(g_TransStartTime, tickNow));

  g_LastPosBytes := totalBytes;
  g_TransPeriodStart := GetTickCount;
end;

procedure TfrmCastFile.btnStartClick(Sender: TObject);
var
  filePath          : string;
  dwDirs, dwFiles   : DWORD;
begin
  filePath := edtFile.Text;
  if FileExists(filePath) or DirectoryExists(filePath) then
  begin
    pb1.Position := 0;
    pb1.Max := 100;
    lvClient.Clear;
    btnStart.Enabled := False;

    stat1.Panels[1].Text := '大小统计中...';
    Application.ProcessMessages;

    dwDirs := 0;
    if FileExists(filePath) then
    begin
      dwFiles := 1;
      g_FileSize := GetFileSize(PAnsiChar(filePath))
    end
    else
    begin
      dwFiles := 0;
      g_FileSize := GetDirectorySize(filePath, dwDirs, dwFiles);
    end;

    stat1.Panels[1].Text := Format('%d 个文件，%d 个文件夹 , 大小 %s (%d 字节)',
      [dwFiles, dwDirs, GetSizeKMG(g_FileSize), g_FileSize]);

    lblFileSize.Caption := GetSizeKMG(g_FileSize);
    pb1.Hint := '总数据 ' + lblFileSize.Caption;

    //默认配置
    DMCConfigFill(FConfig);
    if cbbInterface.ItemIndex > 0 then
      FConfig.net.ifName := PAnsiChar(cbbInterface.Text);
    //FConfig.dmcMode:=dmcAsyncMode;
    if chkStreamMode.Checked then
      FConfig.dmcMode := dmcStreamMode;
    //config.net.mcastRdv:='239.0.0.1';

    FConfig.retriesUntilDrop := seRetriesUntilDrop.Value;
    FConfig.xmitRate := seXmitRate.Value;

    if chkAutoSliceSize.Checked then
      FConfig.flags := FConfig.flags + [dmcNotFullDuplex];

    FConfig.default_slice_size := seSliceSize.Value;
    FConfig.min_receivers := seWaitReceivers.Value;
    FConfig.max_receivers_wait := seMaxWait.Value;

    //创建
    FNego := DMCNegoCreate(@FConfig, OnTransStateChange, OnPartsChange, FFifo);

    if Assigned(FFifo) then
    begin
      g_FileReader := TFileReader.Create(filePath, FFifo);
      g_FileReader.OnFilePosition := OnFilePosition;
    end;

    btnStop.Enabled := Assigned(FNego) and Assigned(FFifo);
    btnStart.Enabled := not btnStop.Enabled;
  end
  else
    MessageBox(Handle, '文件不存在!', '提示', MB_ICONWARNING);
end;

procedure TfrmCastFile.OnAutoStop(var Msg: TMessage);
begin
  btnStopClick(nil);
end;

procedure TfrmCastFile.btnStopClick(Sender: TObject);
begin
  btnStop.Enabled := False;
  frmCastFile.tmrStats.Enabled := False;

  if FNego <> nil then
  begin
    // 等待FIFO　线程结束..
    g_FileReader.Terminate;
    g_FileReader.Free;

    DMCNegoDestroy(FNego);
    FNego := nil;
  end;

  btnStart.Enabled := g_TransState = tsStop;
  btnTrans.Enabled := not btnStart.Enabled;
  btnTrans.Caption := '传输';
  btnTrans.Tag := 0;

  //循环模式
  if btnStart.Enabled and chkLoopStart.Checked then
    btnStartClick(nil);
end;

procedure TfrmCastFile.btnTransClick(Sender: TObject);
begin
  if FNego = nil then
  begin
    btnStopClick(nil);
    Exit;
  end;

  if not Assigned(Sender) then          //auto start?
  begin
    btnTrans.Caption := '暂停';
    btnTrans.Tag := 1;
    Exit;
  end;

  with TButton(Sender) do
    case Tag of
      0:
        begin
          DMCTransferCtrl(FNego, tcStart);
          Caption := '暂停';
          Tag := 1;
        end;
      1:
        begin
          DMCTransferCtrl(FNego, tcPause);
          Caption := '继续';
          Tag := 2;
        end;
      2:
        begin
          DMCTransferCtrl(FNego, tcStart);
          Caption := '暂停';
          Tag := 1;
        end;
    end;
end;

procedure TfrmCastFile.FormCreate(Sender: TObject);
begin
  pb1.DoubleBuffered := True;
  GetAllInterface;
  LoadSaveConfig(True);
end;

procedure TfrmCastFile.UpdateOnline;
begin
  btnTrans.Enabled := (g_TransState = tsNego)
    and (g_NrOnline > 0);
  stat1.Panels[0].Text := '接收端: '
    + IntToStr(g_NrOnline) + '/' + IntToStr(lvClient.Items.Count);
end;

procedure TfrmCastFile.lbl8Click(Sender: TObject);
begin
  ShellExecute(Handle, 'open', PChar('http://www.yryz.net/?from=DMCast_' + Caption),
    nil, nil, SW_SHOWNORMAL);
end;

procedure TfrmCastFile.GetAllInterface;
var
  phe               : PHostEnt;
  lpHost            : array[0..15] of Char;
  lpInAddr          : ^PInAddr;
begin
  with cbbInterface.Items do
  begin
    Clear;
    getHostName(lpHost, SizeOf(lpHost));
    phe := GetHostByName(lpHost);
    if Assigned(phe) then
    begin
      lpInAddr := Pointer(phe^.h_addr_list);
      repeat
        Add(inet_ntoa(lpInAddr^^));
        Inc(lpInAddr);
      until lpInAddr^ = nil;
    end;
    if Count > 0 then
      Insert(0, '::所有网络接口::');
  end;
end;

procedure TfrmCastFile.LoadSaveConfig(isLoad: Boolean);
var
  cfgFile           : PChar;
  szBuf             : array[0..MAX_PATH - 1] of char;
begin
  cfgFile := PChar(ParamStr(0));
  StrCopy(PChar(StrRScan(cfgFile, '.') + 1), 'ini');
  try
    if isLoad then
    begin
      GetPrivateProfileString('opt', 'file', '', szBuf, MAX_PATH, cfgFile);
      edtFile.Text := szBuf;
      chkLoopStart.Checked := LongBool(GetPrivateProfileInt('opt', 'loopStart', 0, cfgFile));
      chkStreamMode.Checked := LongBool(GetPrivateProfileInt('opt', 'streamMode', 0, cfgFile));
      cbbInterface.ItemIndex := GetPrivateProfileInt('opt', 'ifIndex', 0, cfgFile);
      seSliceSize.Value := GetPrivateProfileInt('opt', 'sliceSize', 0, cfgFile);
      seXmitRate.Value := GetPrivateProfileInt('opt', 'xmitRate', 0, cfgFile);
      seMaxWait.Value := GetPrivateProfileInt('opt', 'maxWaitSec', 0, cfgFile);
      seWaitReceivers.Value := GetPrivateProfileInt('opt', 'waitReceivers', 0, cfgFile);
      seRetriesUntilDrop.Value := GetPrivateProfileInt('opt', 'retriesUntilDrop', 30, cfgFile);
    end
    else
    begin
      WritePrivateProfileString('opt', 'file', PChar(edtFile.Text), cfgFile);
      WritePrivateProfileString('opt', 'loopStart', PChar(IntToStr(Integer(chkLoopStart.Checked))), cfgFile);
      WritePrivateProfileString('opt', 'streamMode', PChar(IntToStr(Integer(chkStreamMode.Checked))), cfgFile);
      WritePrivateProfileString('opt', 'ifIndex', PChar(IntToStr(cbbInterface.ItemIndex)), cfgFile);
      WritePrivateProfileString('opt', 'sliceSize', PChar(IntToStr(seSliceSize.Value)), cfgFile);
      WritePrivateProfileString('opt', 'xmitRate', PChar(IntToStr(seXmitRate.Value)), cfgFile);
      WritePrivateProfileString('opt', 'maxWaitSec', PChar(IntToStr(seMaxWait.Value)), cfgFile);
      WritePrivateProfileString('opt', 'waitReceivers', PChar(IntToStr(seWaitReceivers.Value)), cfgFile);
      WritePrivateProfileString('opt', 'retriesUntilDrop', PChar(IntToStr(seRetriesUntilDrop.Value)), cfgFile);
    end;
  except
    on E: Exception do
      OutDebug('处理配置文件异常!' + E.Message);
  end;
end;

procedure TfrmCastFile.FormClose(Sender: TObject;
  var Action: TCloseAction);
begin
  LoadSaveConfig(False);
end;

procedure TfrmCastFile.SpinEditChange(Sender: TObject);
begin
  if (TSpinEdit(Sender).Text <> '') and (TSpinEdit(Sender).Value < 0) then
    TSpinEdit(Sender).Value := 0;
end;

procedure TfrmCastFile.OnFilePosition(Sender: TFileReader);
begin
  stat1.Panels[1].Text := Sender.CurrentFile;
end;

procedure TfrmCastFile.cbb1Change(Sender: TObject);
var
  info              : TBrowseinfo;
  Dir               : array[0..266] of char;
  Itemid            : PitemIDList;
begin
  case cbb1.ItemIndex of
    1:
      begin
        if dlgOpen1.Execute then
          edtFile.Text := dlgOpen1.FileName;
        Exit;
      end;

    2:
      begin
        with info do
        begin
          hwndOwner := self.Handle;
          pidlRoot := nil;
          pszDisplayName := nil;
          lpszTitle := '请选择需要传输的目录';
          ulFlags := 0;                 {“0”表示返回控制面板、回收站等目录，“1”则反之}
          lpfn := nil;
          lParam := 0;
          iImage := 0;
        end;

        ItemId := SHBrowseForFolder(info);
        if ItemId <> nil then
        begin
          SHGetPathFromIDList(ItemId, @Dir);
          edtFile.Text := string(Dir);
        end;
      end;
  end;
end;

end.

