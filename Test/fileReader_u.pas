unit fileReader_u;

interface
uses
  Windows, SysUtils, Classes, Forms, Config_u, fileProtoc_u, FuncLib, HouLog_u;

type
  TFileReader = class;
  TOnFilePosition = procedure(Sender: TFileReader) of object;

  TFileReader = class(TThread)
  private
    FPath: string;
    FFifo: Pointer;

    FPosition: Int64;
    FFilePosition: Int64;
    FCurrentFile: string;

    FOnFilePosition: TOnFilePosition;
  protected
    function ReadFile(fileName: string): Boolean; // a\b\c.rar
    function ReadDirs(subDir: string = ''): Boolean; // a\b\
    procedure Execute; override;
  public
    constructor Create(Path: string; lpFifo: Pointer);
    destructor Destroy; override;
    procedure Terminate; overload;

    property Position: Int64 read FPosition;
    property FilePosition: Int64 read FFilePosition;
    property CurrentFile: string read FCurrentFile;

    property OnFilePosition: TOnFilePosition read FOnFilePosition write FOnFilePosition;
  end;

function GetDirectorySize(const Dir: string;
  var dwDirs, dwFiles: DWORD): Int64;
implementation
{$INCLUDE DMCSender.inc}

function GetDirectorySize(const Dir: string;
  var dwDirs, dwFiles: DWORD): Int64;
var
  Sr                : TSearchRec;
begin
  Result := 0;
  if FindFirst(Dir + '\*.*', faAnyFile, Sr) <> NO_ERROR then
    Exit;

  if (Sr.Name <> '.') and (Sr.Name <> '..') then
    if ((Sr.Attr and faDirectory) > 0) then
    begin
      Inc(dwDirs);
      Inc(Result, GetDirectorySize(Dir + '\' + Sr.Name, dwDirs, dwFiles));
    end
    else
    begin
      Inc(dwFiles);
      Inc(Result, Sr.FindData.nFileSizeHigh * $100000000 + Sr.FindData.nFileSizeLow);
    end;

  while FindNext(Sr) = NO_ERROR do
    if (Sr.Name <> '.') and (Sr.Name <> '..') then
      if ((Sr.Attr and faDirectory) > 0) then
      begin
        Inc(dwDirs);
        Inc(Result, GetDirectorySize(Dir + '\' + Sr.Name, dwDirs, dwFiles));
      end
      else
      begin
        Inc(dwFiles);
        Inc(Result, Sr.FindData.nFileSizeHigh * $100000000 + Sr.FindData.nFileSizeLow);
      end;

  FindClose(Sr);
end;

{ TFileReader }

constructor TFileReader.Create(Path: string; lpFifo: Pointer);
begin
  FPath := Path;
  if not (FPath[Length(FPath)] in ['\', '/']) and not FileExists(Path) then
    FPath := FPath + '\';

  FFifo := lpFifo;
  inherited Create(True);
end;

destructor TFileReader.Destroy;
begin
  inherited;
end;

function TFileReader.ReadFile(fileName: string): Boolean;
var
  lpBuf             : PByte;
  dwBytes           : DWORD;
  fileInfo          : TFileInfo;
  FileStrm          : TFileStream;

  lastSize          : Int64;
begin
  Result := False;
  FileStrm := nil;
  try
    try
      FCurrentFile := FPath + fileName;
      if Assigned(FOnFilePosition) then
        FOnFilePosition(Self);

      FileStrm := TFileStream.Create(FCurrentFile, fmShareDenyWrite or fmOpenRead);

      { 文件信息 }
      dwBytes := SizeOf(TFInfoHead) + Length(fileName) + 1;
      fileInfo.head.size := dwBytes;
      fileInfo.head.fileSize := FileStrm.Size;

      lpBuf := DMCDataWriteWait(FFifo, dwBytes); //等待数据缓冲区可写
      if (dwBytes = 0) or Terminated then
        Exit;

      //写入缓冲区
      Move(fileInfo.head, lpBuf^, SizeOf(TFInfoHead));
      Inc(lpBuf, SizeOf(TFInfoHead));
      StrPCopy(PChar(lpBuf), fileName);
      DMCDataWrited(FFifo, fileInfo.head.size);

      { 文件数据 }
      lastSize := fileInfo.head.fileSize; //剩余大小
      while not Terminated and (lastSize > 0) do
      begin
        dwBytes := 4096;
        lpBuf := DMCDataWriteWait(FFifo, dwBytes); //等待数据缓冲区可写
        if (dwBytes = 0) or Terminated then
          Break;

        dwBytes := FileStrm.Read(lpBuf^, dwBytes);
        Assert(Integer(dwBytes) > 0, 'file read < 0!!!');

        Dec(lastSize, dwBytes);
        DMCDataWrited(FFifo, dwBytes);
      end;

      Result := lastSize = 0;           // data end ?
    finally
      if Assigned(FileStrm) then
        FileStrm.Free;
    end;
  except
{$IFDEF EN_LOG}
    on e: Exception do
    begin
      //Result := GetLastError = $0002;   //系统找不到指定的文件
      _OutLog2(llError, e.Message);
      case Application.MessageBox(PChar(e.Message), '发生异常！',
        MB_ICONERROR or MB_ABORTRETRYIGNORE) of
        ID_ABORT: Result := False;
        ID_RETRY: Result := ReadFile(fileName);
        ID_IGNORE: Result := True;
      end;
    end;
{$ENDIF}
  end;
end;

function TFileReader.ReadDirs(subDir: string = ''): Boolean;
var
  Sr                : TSearchRec;
begin
  Result := True;
  if FindFirst(FPath + subDir + '*.*', faAnyFile, Sr) <> NO_ERROR then
    Exit;

  if (Sr.Name <> '.') and (Sr.Name <> '..') then
    if ((Sr.Attr and faDirectory) > 0) then
      Result := ReadDirs(subDir + Sr.Name + '\')
    else
      Result := ReadFile(subDir + Sr.Name);

  while Result and (FindNext(Sr) = NO_ERROR) do
    if (Sr.Name <> '.') and (Sr.Name <> '..') then
      if ((Sr.Attr and faDirectory) > 0) then
        Result := ReadDirs(subDir + Sr.Name + '\')
      else
        Result := ReadFile(subDir + Sr.Name);

  FindClose(Sr);
end;

procedure TFileReader.Execute;
var
  s                 : string;
begin
  if Terminated then
    Exit;

  if FileExists(FPath) then             //单文件
  begin
    s := FPath;
    FPath := ExtractFilePath(s);
    ReadFile(Copy(s, Length(FPath) + 1, MaxInt));
  end
  else
    ReadDirs();

  //End
  DMCDataWrited(FFifo, 0);
end;

procedure TFileReader.Terminate;
begin
  inherited Terminate;
  DMCDataWrited(FFifo, 0);
  Resume;
  WaitFor;
end;

{ End }

end.

