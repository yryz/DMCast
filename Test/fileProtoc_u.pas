unit fileProtoc_u;

interface
uses
  Windows;

type
  TFInfoHead = packed record
    size: Integer;                      //FileInfo大小
    fileSize: Int64;                    // 文件大小
  end;

  TFileInfo = packed record
    head: TFInfoHead;
    fileName: array[0..0] of AnsiChar;  // soft/t.rar
  end;
  PFileInfo = ^TFileInfo;

implementation

end.

