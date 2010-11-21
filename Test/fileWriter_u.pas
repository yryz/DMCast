unit fileWriter_u;

interface
uses
  Windows, SysUtils, Classes, Config_u, fileProtoc_u;

type
  TFileWriter = class(TThread)
  private
    FPath: string;
    FFifo: Pointer;
  protected
    procedure Execute; override;
  public
    constructor Create(Path: string; lpFifo: Pointer);
    destructor Destroy; override;
  end;

implementation
{$INCLUDE DMCReceiver.inc}

{ TFileWriter }

constructor TFileWriter.Create(Path: string; lpFifo: Pointer);
begin
  FPath := Path;
  if not (FPath[Length(FPath)] in ['\', '/']) then
    FPath := FPath + '\';

  FFifo := lpFifo;
  inherited Create(False);
end;

destructor TFileWriter.Destroy;
begin
  inherited;
end;

procedure TFileWriter.Execute;
var
  lpBuf             : PByte;
  dwBytes           : DWORD;

  sFile, sDir       : string;
  fileSize, lastSize: Int64;
  FileStrm          : TFileStream;

  bInvalidSize      : Boolean;
label
  __readhead;
begin
  while True do                         //确保缓冲区数据完全写入
  begin
    { 文件信息 }
    dwBytes := SizeOf(TFInfoHead);
    __readhead:
    lpBuf := DMCDataReadWait(FFifo, dwBytes); //等待数据
    if (lpBuf = nil) then               //data end?
      Exit;

    if dwBytes < PFileInfo(lpBuf)^.head.size then
    begin
      dwBytes := PFileInfo(lpBuf)^.head.size;
      goto __readhead;
    end
    else
    begin                               //得到信息头
      sFile := FPath + PChar(@PFileInfo(lpBuf)^.fileName);
      fileSize := PFileInfo(lpBuf)^.head.fileSize;
      DMCDataReaded(FFifo, PFileInfo(lpBuf)^.head.size);
    end;

    //目录
    Writeln(#13#10'Current: ', sFile);
    sDir := ExtractFileDir(sFile);
    if not DirectoryExists(sDir) then
      ForceDirectories(sDir);

    { 文件数据 }
    FileStrm := TFileStream.Create(sFile, fmShareDenyWrite or fmCreate);
    try
      lastSize := fileSize;
      while lastSize > 0 do
      begin
        dwBytes := 4096;
        lpBuf := DMCDataReadWait(FFifo, dwBytes); //等待数据
        if (lpBuf = nil) then           //data end?
          Exit;

        if dwBytes > lastSize then
          dwBytes := lastSize;

        dwBytes := FileStrm.Write(lpBuf^, dwBytes);
        if Integer(dwBytes) <= 0 then
        begin
          Writeln(#13#10'File Write Error: ' + SysErrorMessage(GetLastError));
          Halt(0);
          Exit;
        end;

        Dec(lastSize, dwBytes);
        DMCDataReaded(FFifo, dwBytes);
      end;

    finally
      if Assigned(FileStrm) then
      begin
        if FileStrm.Position <> fileSize then
        begin
          Writeln(#13#10'文件大小不符！', FileStrm.Position, '/', fileSize);
          Halt(0);
        end;
        FileStrm.Free;
      end;
    end

  end;                                  // end while
end;

{ End }
end.

