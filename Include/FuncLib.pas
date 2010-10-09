unit FuncLib;
{$DEFINE SMALL}                         //减小体积
interface

uses
  windows, MySysutils, Messages, ShellAPI{$IFNDEF SMALL}, ActiveX, ComObj{$ENDIF} {, shlobj};

type
  TStrArr = array of string;

procedure OutDebug(s: string);          //调试输出
procedure AbortProcess;                 //结束进程(一般在DLL中使用)

function StrDec(const Str: string): string; //字符解密函數
function GetFileVersion(FileName: string): Word;
function GetFileSize(const Path: PAnsiChar): Int64;
function GetSizeKMG(byteSize: Int64): string; //自动计算KB MB GB
function GetModulePath(hinst: Cardinal; DllName: PAnsiChar): PAnsiChar; //获得DLL所在目录
procedure MousePosClick(x, y: Integer); //鼠标点击指定坐标

function RandStr(minLen, maxLen: WORD): string; //随机字符
function GetSubStr(const _Str, _Start, _End: string): string;
function GetSubStrEx(const _Str, _Start, _End: string; var _LastStr: string {余下部分}): string;
function SplitStrArr(const Separators, sContent: string; var StrArr: TStrArr): Integer;

function MyPos(c: Char; const Str: string): Integer; //自定义的 Pos 函数 速度提升5倍
function SetPrivilege(const Privilege: PAnsiChar): boolean; //SeShutdownPrivilege 关机权限  SeDebugPrivilege 调试权限
function RegDelValue(const Key, Vname: PAnsiChar): boolean; //删除注册表值
function RegReadStr(const Key, Vname: PAnsiChar): string; //读注册表 str
function RegReadInt(const Key, Vname: PAnsiChar): DWORD; //读注册表Integer
function RegWriteStr(const Key, Vname, Value: PAnsiChar): boolean; //写STR
function RegWriteInt(const Key, Vname: PAnsiChar; const Value: Integer): boolean; //写DWORD

function CopyFileAndDir(const source, dest: string): boolean; //复制文件和目录
function DelFileAndDir(const source: string): boolean; //删除文件和目录

function WaitForExec(const CommLine: string; const Time, cmdShow: Cardinal): Cardinal; //创建进程并等待返回PID
function SelectDesktop(pName: PAnsiChar): boolean; stdcall; //选择桌面
function InputDesktopSelected: boolean; stdcall; //是否为当前桌面

function JavaScriptEscape(const s: string): string; //JAVASCRIPT转义字符
{$IFNDEF SMALL}
function RunJavaScript(const JsCode, JsVar: string): string; //  参数 JsCode 是要执行的 Js 代码; 参数 JsVar 是要返回的变量
{$ENDIF}

function GetTickCountUSec(): DWORD;     //微秒计时器，1/1000 000秒
function DiffTickCount(tOld, tNew: DWORD): DWORD; //计算活动时间差
function MSecondToTimeStr(ms: Cardinal): string;

implementation

procedure OutDebug(s: string);
begin
  OutputDebugString(PAnsiChar(s));
end;

procedure AbortProcess;
begin
  TerminateProcess(GetCurrentProcess, 0);
end;

function StrDec(const Str: string): string; //字符解密函數
const
  XorKey            : array[0..7] of Byte = ($B2, $09, $AA, $55, $93, $6D, $84, $47); //字符串加密用
var
  i, j              : Integer;
begin
  Result := '';
  j := 0;
  try
    for i := 1 to Length(Str) div 2 do
    begin
      Result := Result + Char(StrToInt('$' + Copy(Str, i * 2 - 1, 2)) xor XorKey[j]);
      j := (j + 1) mod 8;
    end;
  except
  end;
end;

function GetFileVersion(FileName: string): Word;
type
  PVerInfo = ^TVS_FIXEDFILEINFO;
  TVS_FIXEDFILEINFO = record
    dwSignature: longint;
    dwStrucVersion: longint;
    dwFileVersionMS: longint;
    dwFileVersionLS: longint;
    dwFileFlagsMask: longint;
    dwFileFlags: longint;
    dwFileOS: longint;
    dwFileType: longint;
    dwFileSubtype: longint;
    dwFileDateMS: longint;
    dwFileDateLS: longint;
  end;
var
  ExeNames          : array[0..255] of char;
  VerInfo           : PVerInfo;
  Buf               : pointer;
  Sz                : word;
  L, Len            : Cardinal;
begin
  Result := 0;
  StrPCopy(ExeNames, FileName);
  Sz := GetFileVersionInfoSize(ExeNames, L);
  if Sz = 0 then
    Exit;

  try
    GetMem(Buf, Sz);
    try
      GetFileVersionInfo(ExeNames, 0, Sz, Buf);
      if VerQueryValue(Buf, '\', Pointer(VerInfo), Len) then
      begin
        {Result := IntToStr(HIWORD(VerInfo.dwFileVersionMS)) + '.' +
          IntToStr(LOWORD(VerInfo.dwFileVersionMS)) + '.' +
          IntToStr(HIWORD(VerInfo.dwFileVersionLS)) + '.' +
          IntToStr(LOWORD(VerInfo.dwFileVersionLS));   }
        Result := HIWORD(VerInfo.dwFileVersionMS);
      end;
    finally
      FreeMem(Buf);
    end;
  except
    Result := 0;
  end;
end;

function GetFileSize(const Path: PAnsiChar): Int64;
var
  FindHandle        : THandle;
  FindData          : TWin32FindData;
begin
  FindHandle := FindFirstFile(Path, FindData);
  if FindHandle <> INVALID_HANDLE_VALUE then
    Result := FindData.nFileSizeHigh * $100000000 + FindData.nFileSizeLow
  else
    Result := 0;
end;

function GetSizeKMG(byteSize: Int64): string; //自动计算KB MB GB
begin
  if byteSize < 1024 then
    Result := IntToStr(byteSize) + ' B'
  else if byteSize < 1024 * 1024 then
    Result := FloatToStr2(byteSize / 1024, 2) + ' KB' //format2('%.2f KB', [byteSize / 1024])
  else if byteSize < 1024 * 1024 * 1024 then
    Result := FloatToStr2(byteSize / (1024 * 1024), 2) + ' MB' //format('%.2f MB', [byteSize / (1024 * 1024)])
  else
    Result := FloatToStr2(byteSize / (1024 * 1024 * 1024), 2) + ' GB'; //format('%.2f GB', [byteSize / (1024 * 1024 * 1024)]);
end;

{-------------------------------------------------------------------------------
  过程名:    GetModulePath
  作者:      HouSoft
  日期:      2009.12.01
  参数:      模块实例  模块名 (模块实例为0时模块名才有效)
  返回值:    PAnsiChar
-------------------------------------------------------------------------------}

function GetModulePath(hinst: Cardinal; DllName: PAnsiChar): PAnsiChar;
var
  i, n              : Integer;
  szFilePath        : array[0..MAX_PATH] of Char;
  lpPath            : PAnsiChar;
begin
  if hInst > 0 then
    GetModuleFileName(hInst, szFilePath, MAX_PATH)
  else
    GetModuleFileName(GetModuleHandle(DllName), szFilePath, MAX_PATH);
  n := 0;
  for i := Low(szFilePath) to High(szFilePath) do
    case szFilePath[I] of
      '\': n := i;
      #0: Break;
    end;
  szFilePath[n + 1] := #0;
  Result := szFilePath;                 //此处理,可让DLL调用中不会出错
end;

procedure MousePosClick(x, y: Integer);
var
  lpPoint           : TPoint;
begin
  GetCursorPos(lpPoint);
  SetCursorPos(x, y);
  mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0);
  mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0);
  SetCursorPos(lpPoint.X, lpPoint.Y);
end;

function RandStr(minLen, maxLen: WORD): string;
const
  USER_CHARS        = 'abcdefghijklmnopurstuvwxyz1234567890';
var
  i                 : Integer;
  sRet              : string;
  randLen           : integer;
  randChar          : Char;
begin
  sRet := '';
  randLen := minLen + (GetTickCount() + 1) mod (maxLen - minLen); //随机长度
  SetLength(sRet, randLen);
  for i := 1 to randLen do
  begin
    randChar := USER_CHARS[(Random(GetTickCount) + 1) mod (Length(USER_CHARS) - 1)]; //随机字符
    if ((i = 1) and (randChar in ['0'..'9'])) or
      (i = randLen) then                //开头不能为数字
      randChar := Char(Ord('a') + (GetTickCount() + 1) mod 25);
    sRet[i] := randChar;
  end;
  Result := sRet;
end;

function GetSubStr(const _Str, _Start, _End: string): string;
//20100306
var
  Index             : Integer;
begin
  if _Start <> '' then
  begin
    Index := Pos(_Start, _Str);
    if Index = 0 then
    begin
      Result := '';
      Exit;
    end;
  end
  else
    Index := 1;

  Result := Copy(_Str, Index + Length(_Start), MaxInt);
  if _End = '' then
    Index := Length(Result) + 1
  else
    Index := Pos(_End, Result);

  Result := Copy(Result, 1, Index - 1);
end;

function GetSubStrEx(const _Str, _Start, _End: string; var _LastStr: string {余下部分}): string;
//20100306 Pos 比 StrPos 快 1.5倍
var
  Index             : Integer;
begin
  if _Start <> '' then
  begin
    Index := Pos(_Start, _Str);
    if Index = 0 then
    begin
      Result := '';
      _LastStr := _Str;
      Exit;
    end;
  end
  else
    Index := 1;

  _LastStr := Copy(_Str, Index + Length(_Start), MaxInt);
  if _End = '' then
    Index := Length(_Str) + 1
  else
    Index := Pos(_End, _LastStr);

  Result := Copy(_LastStr, 1, Index - 1);
  _LastStr := Copy(_LastStr, Index + Length(_End), MaxInt);
end;

function SplitStrArr(const Separators, sContent: string; var StrArr: TStrArr): Integer;
var
  sStr, sTmp        : string;
begin
  Result := 0;
  SetLength(StrArr, Result);
  sStr := sContent + Separators;
  repeat
    sTmp := GetSubStrEx(sStr, '', Separators, sStr);
    if sTmp <> '' then
    begin
      Inc(Result);
      SetLength(StrArr, Result);
      StrArr[High(StrArr)] := sTmp;
    end;
  until sTmp = '';
end;

//自定义的 Pos 函数 单个字符查找比Pos快10倍多

function MyPos(c: Char; const Str: string): Integer;
var
  i                 : Integer;
begin
  Result := 0;
  for i := 1 to Length(Str) do
    if c = Str[i] then
    begin
      Result := i;
      exit
    end;
end;

function SetPrivilege(const Privilege: PAnsiChar): boolean; //权限
var
  OldTokenPrivileges, TokenPrivileges: TTokenPrivileges;
  ReturnLength      : DWORD;
  hToken            : THandle;
  luid              : Int64;
begin
  OpenProcessToken(GetCurrentProcess, TOKEN_ADJUST_PRIVILEGES, hToken);
  LookupPrivilegeValue(nil, Privilege, luid);
  TokenPrivileges.Privileges[0].luid := luid;
  TokenPrivileges.PrivilegeCount := 1;
  TokenPrivileges.Privileges[0].Attributes := 0;
  AdjustTokenPrivileges(hToken, false, TokenPrivileges, SizeOf(TTokenPrivileges), OldTokenPrivileges, ReturnLength);
  OldTokenPrivileges.Privileges[0].luid := luid;
  OldTokenPrivileges.PrivilegeCount := 1;
  OldTokenPrivileges.Privileges[0].Attributes := TokenPrivileges.Privileges[0].Attributes or SE_PRIVILEGE_ENABLED;
  Result := AdjustTokenPrivileges(hToken, false, OldTokenPrivileges, ReturnLength, PTokenPrivileges(nil)^, ReturnLength);
end;
{----------end-------------}

function RegDelValue(const Key, Vname: PAnsiChar): boolean; //删除注册表值
var
  hk                : HKEY;
begin
  Result := false;
  if RegOpenKey(HKEY_LOCAL_MACHINE, Key, hk) = ERROR_SUCCESS then
    if RegDeleteValue(hk, Vname) = ERROR_SUCCESS then
      Result := True;
  RegCloseKey(hk);
end;

function RegReadStr(const Key, Vname: PAnsiChar): string; //读注册表 str
var
  hk                : HKEY;
  dwSize            : DWORD;
  S                 : array[0..255] of Char;
begin
  Result := '';
  dwSize := 256;
  if RegOpenKey(HKEY_LOCAL_MACHINE, Key, hk) = 0 then
    if RegQueryValueEx(hk, Vname, nil, nil, @S, @dwSize) = 0 then
      Result := S;
  RegCloseKey(hk);
end;

function RegReadInt(const Key, Vname: PAnsiChar): DWORD; //读注册表Integer
var
  hk                : HKEY;
  dwSize, S         : DWORD;
begin
  Result := 3;
  dwSize := 256;
  if RegOpenKey(HKEY_LOCAL_MACHINE, Key, hk) = 0 then
    if RegQueryValueEx(hk, Vname, nil, nil, @S, @dwSize) = 0 then
      Result := S;
  RegCloseKey(hk);
end;

function RegWriteStr(const Key, Vname, Value: PAnsiChar): boolean; //写STR
var
  hk                : HKEY;
  D                 : DWORD;
begin
  Result := false;
  D := REG_CREATED_NEW_KEY;
  if RegCreateKeyEx(HKEY_LOCAL_MACHINE, Key, 0, nil, 0, KEY_ALL_ACCESS, nil, hk, @D) = 0 then
    if RegSetValueEx(hk, Vname, 0, REG_SZ, Value, Length(Value)) = 0 then
      Result := True;
  RegCloseKey(hk);
end;

function RegWriteInt(const Key, Vname: PAnsiChar; const Value: Integer): boolean; //写DWORD
var
  hk                : HKEY;
  D                 : DWORD;
begin
  Result := false;
  D := REG_CREATED_NEW_KEY;
  if RegCreateKeyEx(HKEY_LOCAL_MACHINE, Key, 0, nil, 0, KEY_ALL_ACCESS, nil, hk, @D) = 0 then
    if RegSetValueEx(hk, Vname, 0, REG_DWORD, @Value, SizeOf(Value)) = 0 then
      Result := True;
  RegCloseKey(hk);
end;

function CopyFileAndDir(const source, dest: string): boolean;
var
  fo                : TSHFILEOPSTRUCT;
begin
  FillChar(fo, SizeOf(fo), 0);
  with fo do
  begin
    Wnd := 0;
    wFunc := FO_Copy;
    pFrom := PAnsiChar(source + #0);
    pTo := PAnsiChar(dest + #0);
    fFlags := FOF_NOCONFIRMATION or FOF_NOERRORUI or FOF_SILENT;
  end;
  Result := (SHFileOperation(fo) = 0);
end;

function DelFileAndDir(const source: string): boolean;
var
  fo                : TSHFILEOPSTRUCT;
begin
  FillChar(fo, SizeOf(fo), 0);
  with fo do
  begin
    Wnd := 0;
    wFunc := FO_DELETE;
    pFrom := PAnsiChar(source + #0);
    pTo := #0#0;
    fFlags := FOF_NOCONFIRMATION + FOF_SILENT;
  end;
  Result := (SHFileOperation(fo) = 0);
end;

function WaitForExec(const CommLine: string; const Time, cmdShow: Cardinal): Cardinal; //创建进程并等待返回PID
var
  si                : STARTUPINFO;
  pi                : PROCESS_INFORMATION;
begin
  ZeroMemory(@si, SizeOf(si));
  si.cb := SizeOf(si);
  si.dwFlags := STARTF_USESHOWWINDOW;
  si.wShowWindow := cmdShow;
  CreateProcess(nil, PAnsiChar(CommLine), nil, nil, false, CREATE_DEFAULT_ERROR_MODE, nil, nil, si, pi);
  WaitForSingleObject(pi.hProcess, Time);
  Result := pi.dwProcessID;
end;

{桌面切换}

function SelectHDESK(HNewDesk: HDESK): boolean; stdcall;
var
  HOldDesk          : HDESK;
  dwDummy           : DWORD;
  sName             : array[0..255] of Char;
begin
  Result := false;
  HOldDesk := GetThreadDesktop(GetCurrentThreadId);
  if (not GetUserObjectInformation(HNewDesk, UOI_NAME, @sName[0], 256, dwDummy)) then
  begin
    //OutputDebugString('GetUserObjectInformation Failed.');
    exit;
  end;
  if (not SetThreadDesktop(HNewDesk)) then
  begin
    //OutputDebugString('SetThreadDesktop Failed.');
    exit;
  end;
  if (not CloseDesktop(HOldDesk)) then
  begin
    //OutputDebugString('CloseDesktop Failed.');
    exit;
  end;
  Result := True;
end;

function SelectDesktop(pName: PAnsiChar): boolean; stdcall;
var
  HDesktop          : HDESK;
begin
  Result := false;
  if Assigned(pName) then
    HDesktop := OpenDesktop(pName, 0, false,
      DESKTOP_CREATEMENU or DESKTOP_CREATEWINDOW or
      DESKTOP_ENUMERATE or DESKTOP_HOOKCONTROL or
      DESKTOP_WRITEOBJECTS or DESKTOP_READOBJECTS or
      DESKTOP_SWITCHDESKTOP or GENERIC_WRITE)
  else
    HDesktop := OpenInputDesktop(0, false,
      DESKTOP_CREATEMENU or DESKTOP_CREATEWINDOW or
      DESKTOP_ENUMERATE or DESKTOP_HOOKCONTROL or
      DESKTOP_WRITEOBJECTS or DESKTOP_READOBJECTS or
      DESKTOP_SWITCHDESKTOP or GENERIC_WRITE);
  if (HDesktop = 0) then
  begin
    //OutputDebugString(PAnsiChar('Get Desktop Failed: ' + IntToStr(GetLastError)));
    exit;
  end;
  Result := SelectHDESK(HDesktop);
end;

function InputDesktopSelected: boolean; stdcall;
var
  HThdDesk          : HDESK;
  HInpDesk          : HDESK;
  //dwError: DWORD;
  dwDummy           : DWORD;
  sThdName          : array[0..255] of Char;
  sInpName          : array[0..255] of Char;
begin
  Result := false;
  HThdDesk := GetThreadDesktop(GetCurrentThreadId);
  HInpDesk := OpenInputDesktop(0, false,
    DESKTOP_CREATEMENU or DESKTOP_CREATEWINDOW or
    DESKTOP_ENUMERATE or DESKTOP_HOOKCONTROL or
    DESKTOP_WRITEOBJECTS or DESKTOP_READOBJECTS or
    DESKTOP_SWITCHDESKTOP);
  if (HInpDesk = 0) then
  begin
    //OutputDebugString('OpenInputDesktop Failed.');
    //dwError := GetLastError;
    //Result := (dwError = 170);
    exit;
  end;
  if (not GetUserObjectInformation(HThdDesk, UOI_NAME, @sThdName[0], 256, dwDummy)) then
  begin
    //OutputDebugString('GetUserObjectInformation HThdDesk Failed.');
    CloseDesktop(HInpDesk);
    exit;
  end;
  if (not GetUserObjectInformation(HInpDesk, UOI_NAME, @sInpName[0], 256, dwDummy)) then
  begin
    //OutputDebugString('GetUserObjectInformation HInpDesk Failed.');
    CloseDesktop(HInpDesk);
    exit;
  end;
  CloseDesktop(HInpDesk);
  Result := (lstrcmp(sThdName, sInpName) = 0);
end;

{
转义序列 字符
  \b 退格
  \f 走纸换页
  \n 换行
  \r 回车
  \t 横向跳格 (Ctrl-I)
  \' 单引号
  \" 双引号
  \\ 反斜杠
 }

function JavaScriptEscape(const s: string): string;
var
  i                 : Integer;
  sTmp              : string;
begin
  sTmp := '';
  if Length(s) > 0 then
    for i := 1 to Length(s) do
      case s[i] of
        '\': sTmp := sTmp + '\\';
        '"': sTmp := sTmp + '\"';
        '''': sTmp := sTmp + '\''';
        #13: sTmp := sTmp + '\r';
        #12: sTmp := sTmp + '\f';
        #10: sTmp := sTmp + '\n';
        #9: sTmp := sTmp + '\t';
        #8: sTmp := sTmp + '\b';
      else
        sTmp := sTmp + s[i];
      end;
  Result := sTmp;
end;

{$IFNDEF SMALL}
{此函数需要 ComObj 单元的支持}
{参数 JsCode 是要执行的 Js 代码; 参数 JsVar 是要返回的变量}

function RunJavaScript(const JsCode, JsVar: string): string;
var
  script            : OleVariant;
begin
  try
    CoInitialize(nil);
    script := CreateOleObject('ScriptControl');
    script.Language := 'JavaScript';
    script.ExecuteStatement(JsCode);
    Result := script.Eval(JsVar);
    CoUninitialize;
  except
    Result := '';
  end;
end;
{$ENDIF}

var
  Frequency         : Int64;

function GetTickCountUSec;              //比 GetTickCount精度高25~30毫秒
var
  lpPerformanceCount: Int64;
begin
  if Frequency = 0 then
  begin
    QueryPerformanceFrequency(Frequency); //WINDOWS API 返回计数频率(Intel86:1193180)(获得系统的高性能频率计数器在一秒内的震动次数)
    Frequency := Frequency div 1000000; //一微秒内振动次数
  end;
  QueryPerformanceCounter(lpPerformanceCount);
  Result := lpPerformanceCount div Frequency;
end;

function DiffTickCount;                 //计算活动时间差
begin
  if tNew >= tOld then
    Result := tNew - tOld
  else
    Result := DWORD($FFFFFFFF) - tOld + tNew;
end;

function MSecondToTimeStr;
var
  Day, Hour, Min, Sec: Word;
begin
  Sec := ms div 1000;
  Min := ms div (1000 * 60);
  Hour := ms div (1000 * 60 * 60);
  Day := ms div (1000 * 60 * 60 * 24);
  Result := '';
  if Day > 0 then
    Result := Result + IntToStr(Day) + '天';
  if Hour > 0 then
    Result := Result + IntToStr(Hour) + '时';
  if Min > 0 then
    Result := Result + IntToStr(Min) + '分';
  if Sec > 0 then
    Result := Result + IntToStr(Sec) + '秒';
end;

end.

