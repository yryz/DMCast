//引用此单元，创建Windows消息队列

unit Window_u;

interface
uses
  Windows;

var
  WinHandle         : THandle;

implementation
const
  WIN_CLASSNAME     = 'HouMessageQueue';

  //注册窗体类

function RegWindowClass: Boolean;
var
  WindowClass       : TWndClass;
begin
  WindowClass.Style := CS_HREDRAW or CS_VREDRAW;
  WindowClass.lpfnWndProc := @DefWindowProc;
  WindowClass.cbClsExtra := 0;
  WindowClass.cbWndExtra := 0;
  WindowClass.hInstance := hInstance;
  WindowClass.hIcon := 0;
  WindowClass.hCursor := LoadCursor(0, IDC_ARROW);
  WindowClass.hbrBackground := COLOR_WINDOW;
  WindowClass.lpszMenuName := nil;
  WindowClass.lpszClassName := WIN_CLASSNAME;
  result := Windows.RegisterClass(WindowClass) <> 0; //API来自Windows单元
end;

//建立窗体

function CreateWindow: DWORD;
begin
  if not RegWindowClass then
  begin
    messagebox(0, 'RegisterClass error !!', nil, 0);
    Halt;
  end;
  result := CreateWindowEx(0,
    WIN_CLASSNAME,
    '',
    WS_DISABLED,
    0,                                  //X
    0,                                  //Y
    0,                                  //Width
    0,                                  //Height
    0,
    0,
    hInstance,
    nil);
  if (result = 0) then
  begin
    messagebox(0, 'Create Window error !!', nil, 0);
    Halt;
  end;
end;

initialization
  WinHandle := CreateWindow;

end.

