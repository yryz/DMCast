unit frmCastFile_u;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, XPMan, Buttons, ComCtrls, ExtCtrls, ImgList, WinSock,
  FuncLib, Config_u, Spin, ShellAPI;

type
  TFileReader = class(TThread)
  private
    FFile: TFileStream;
    FFifo: Pointer;
  protected
    procedure Execute; override;
  public
    constructor Create(fileName: string; lpFifo: Pointer);
    destructor Destroy; override;
    procedure Terminate; overload;
  end;

const
  WM_UPDATE_ONLINE  = WM_USER + 1;
  WM_AUTO_STOP      = WM_USER + 2;

type
  TfrmCastFile = class(TForm)
    dlgOpen1: TOpenDialog;
    XPManifest1: TXPManifest;
    stat1: TStatusBar;
    lvClient: TListView;
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

    procedure btnStartClick(Sender: TObject);
    procedure SpeedButton1Click(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure btnTransClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure lbl8Click(Sender: TObject);
    procedure tmrStatsTimer(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    FNego: Pointer;
    FFifo: Pointer;

    FConfig: TSendConfig;
    FFileReader: TFileReader;
    procedure UpdateOnline(var Msg: TMessage); message WM_UPDATE_ONLINE;
    procedure OnAutoStop(var Msg: TMessage); message WM_AUTO_STOP;

    procedure LoadSaveConfig(isLoad: Boolean);
  public

  end;

var
  frmCastFile       : TfrmCastFile;
  g_FileSize        : Int64;
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
{$DEFINE IS_IMPORT_MODULE}
{$IFNDEF IS_IMPORT_MODULE}
uses
  DMCSender_u;
{$ELSE}
//API接口
const
  DMC_SENDER_DLL    = 'DMCSender.dll';

  //填充默认配置

procedure DMCConfigFill(var config: TSendConfig); stdcall;
  external DMC_SENDER_DLL;

//创建会话  OnTransStateChange,OnPartsChange 可选

function DMCNegoCreate(config: PSendConfig;
  OnTransStateChange: TOnTransStateChange;
  OnPartsChange: TOnPartsChange;
  var lpFifo: Pointer): Pointer; stdcall;
  external DMC_SENDER_DLL;

//结束会话(信号,异步)

function DMCNegoDestroy(lpNego: Pointer): Boolean; stdcall;
  external DMC_SENDER_DLL;

//等待缓冲区可写

function DMCDataWriteWait(lpFifo: Pointer; var dwBytes: DWORD): Pointer; stdcall;
  external DMC_SENDER_DLL;

//数据生产完成

function DMCDataWrited(lpFifo: Pointer; dwBytes: DWORD): Boolean; stdcall;
  external DMC_SENDER_DLL;

//开始传输(信号)

function DMCDoTransfer(lpNego: Pointer): Boolean; stdcall;
  external DMC_SENDER_DLL;

//统计已经传输Bytes

function DMCStatsTotalBytes(lpNego: Pointer): Int64; stdcall;
  external DMC_SENDER_DLL;

//统计重传Blocks(块)

function DMCStatsBlockRetrans(lpNego: Pointer): Int64; stdcall;
  external DMC_SENDER_DLL;
{$ENDIF}

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
        g_TransStartTime := GetTickCount;
        g_TransPeriodStart := g_TransStartTime;
        frmCastFile.tmrStats.Enabled := True;
        frmCastFile.btnTrans.Enabled := False; //auto trans ?
{$IFDEF CONSOLE}
        Writeln('Start Trans..');
{$ENDIF}
      end;
    tsComplete:
      begin
        frmCastFile.tmrStatsTimer(nil);
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

{ TFileReader }

constructor TFileReader.Create(fileName: string; lpFifo: Pointer);
begin
  FFifo := lpFifo;
  FFile := TFileStream.Create(fileName, fmShareDenyNone or fmOpenRead);
  inherited Create(False);
end;

destructor TFileReader.Destroy;
begin
  if Assigned(FFile) then
    FFile.Free;
  inherited;
end;

procedure TFileReader.Execute;
var
  lpBuf             : PByte;
  dwBytes           : DWORD;
begin
  repeat
    dwBytes := 4096;
    lpBuf := DMCDataWriteWait(FFifo, dwBytes); //等待数据缓冲区可写
    if (dwBytes = 0) or Terminated then
      Break;

    dwBytes := FFile.Read(lpBuf^, dwBytes);
    DMCDataWrited(FFifo, dwBytes);

  until Terminated or (dwBytes = 0);
end;

procedure TFileReader.Terminate;
begin
  inherited Terminate;
  DMCDataWrited(FFifo, 0);
  WaitFor;
end;

{ End }

procedure TfrmCastFile.tmrStatsTimer(Sender: TObject);
var
  totalBytes        : Int64;
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

  tdiff := DiffTickCount(g_TransStartTime, tickNow);
  if tdiff = 0 then
    tdiff := 1;
  //平均带宽统计
  bw := totalBytes * 1000 / tdiff;      // Byte/s

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

  g_LastPosBytes := totalBytes;
  g_TransPeriodStart := GetTickCount;
end;

procedure TfrmCastFile.btnStartClick(Sender: TObject);
var
  fileName          : string;
begin
  fileName := edtFile.Text;
  if FileExists(fileName) then
  begin
    pb1.Position := 0;
    pb1.Max := 100;
    lvClient.Clear;
    btnStart.Enabled := False;

    g_FileSize := GetFileSize(PAnsiChar(fileName));
    lblFileSize.Caption := GetSizeKMG(g_FileSize);
    pb1.Hint := '总数据 ' + lblFileSize.Caption;

    //默认配置
    DMCConfigFill(FConfig);
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
      FFileReader := TFileReader.Create(fileName, FFifo);

    btnStop.Enabled := Assigned(FNego) and Assigned(FFifo);
    btnStart.Enabled := not btnStop.Enabled;
  end
  else
    MessageBox(Handle, '文件不存在!', '提示', MB_ICONWARNING);
end;

procedure TfrmCastFile.SpeedButton1Click(Sender: TObject);
begin
  if dlgOpen1.Execute then
    edtFile.Text := dlgOpen1.FileName;
end;

procedure TfrmCastFile.btnStopClick(Sender: TObject);
begin
  btnStop.Enabled := False;
  frmCastFile.tmrStats.Enabled := False;

  if FNego <> nil then
  begin
    // 等待FIFO　线程结束..
    FFileReader.Terminate;
    FFileReader.Free;

    DMCNegoDestroy(FNego);
    FNego := nil;
  end;

  btnStart.Enabled := g_TransState = tsStop;
  btnTrans.Enabled := not btnStart.Enabled;

  //循环模式
  if btnStart.Enabled and chkLoopStart.Checked then
    btnStartClick(nil);
end;

procedure TfrmCastFile.btnTransClick(Sender: TObject);
begin
  if Assigned(FNego) then
    DMCDoTransfer(FNego)
  else
    btnStopClick(nil);
  btnTrans.Enabled := False;
end;

procedure TfrmCastFile.FormCreate(Sender: TObject);
begin
  pb1.DoubleBuffered := True;
  LoadSaveConfig(True);
end;

procedure TfrmCastFile.UpdateOnline;
begin
  btnTrans.Enabled := (g_TransState = tsNego)
    and (g_NrOnline > 0);
  stat1.Panels[0].Text := '客户端: '
    + IntToStr(g_NrOnline) + '/' + IntToStr(lvClient.Items.Count);
end;

procedure TfrmCastFile.OnAutoStop(var Msg: TMessage);
begin
  btnStopClick(nil);
end;

procedure TfrmCastFile.lbl8Click(Sender: TObject);
begin
  ShellExecute(Handle, 'open', 'http://www.yryz.net/?from=DMCast',
    nil, nil, SW_SHOWNORMAL);
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

end.

