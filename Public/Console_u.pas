unit Console_u;

interface
uses
  Windows, Sysutils, WinSock2;

type
  TConsole = class                      //参与控制会话
  private
    FSocket: TSocket;
    FHandles: array[0..1] of THandle;   //0 Socket,1 Thread Wait KeyPress
    FNrHandles: DWORD;
    FKey: Char;                         //Key
    FKeyPressed: Boolean;
  private
    //function MakeConSocket(): Integer;
  public
    constructor Create();
    destructor Destroy; override;
    procedure Start(s: TSocket; enKeyPress: Boolean);
    procedure Stop;
    function SelectWithConsole(waitTime: DWORD): Integer;
    function PostPressed: Boolean;
  published
    property Key: Char read FKey;
    property KeyPressed: Boolean read FKeyPressed;
  end;

implementation

{ TConsole }

function WaitForKeyPress(Console: TConsole): Integer;
var
  key               : Char;
begin
{$IFDEF CONSOLE}
  read(key);
  Result := Ord(key);
{$ENDIF}
end;

constructor TConsole.Create();
begin
end;

destructor TConsole.Destroy;
begin
  Stop;
  inherited;
end;

//function TConsole.MakeConSocket(): Integer;
//var
//  r, len            : Integer;
//  addr              : TSockAddrIn;
//begin
//  addr.sin_family := AF_INET;
//  addr.sin_addr.s_addr := inet_addr('127.0.0.1');
//  addr.sin_port := htons(0);
//
//  Result := socket(PF_INET, SOCK_DGRAM, 0);
//  r := bind(Result, addr, SizeOf(addr));
//  if (r = SOCKET_ERROR) then begin
//    if (Result > 0) then begin
//      closesocket(Result);
//      Result := 0;
//    end;
//    raise Exception.Create('Could not start console listen socket');
//  end;
//  //收发对接
//  len := SizeOf(TSockAddrIn);
//  getsockname(Result, addr, len);
//  if connect(Result, addr, len) = SOCKET_ERROR then
//    raise Exception.Create('Could not connect console socket');
//end;

function TConsole.SelectWithConsole(waitTime: DWORD): Integer;
begin
  Result := WaitForMultipleObjects(FNrHandles, @FHandles, False, waitTime);
  case Result of
    WAIT_OBJECT_0 + 0:                  //Socket
      Result := FSocket;
    WAIT_OBJECT_0 + 1:
      begin
        GetExitCodeThread(FHandles[1], DWORD(Result));
        if Result > 0 then begin        //KeyPress
          FKeyPressed := True;
          FKey := Chr(Result);
          Result := 0;
        end else
          Result := -1;
      end;
    WAIT_TIMEOUT:
      Result := 0;
  else                                  //Error
    Result := -1;
  end;
end;

function TConsole.PostPressed: Boolean;
begin
  FKeyPressed := True;
  Result := SetEvent(FHandles[0]);
end;

procedure TConsole.Start(s: TSocket; enKeyPress: Boolean);
var
  dwThID            : DWORD;
begin
  FSocket := s;
  FHandles[0] := CreateEvent(nil, FALSE, FALSE, nil);
  if WSAEventSelect(s, FHandles[0], FD_READ or FD_CLOSE) = SOCKET_ERROR then
  begin
    FSocket := INVALID_SOCKET;
    raise Exception.CreateFmt('WSAAsyncSelect Socket(%d) Error(%d)', [s, GetLastError]);
  end;

  FNrHandles := 1;
  if enKeyPress then begin
    FHandles[1] := BeginThread(nil, 0, @WaitForKeyPress, Self, 0, DWORD(dwThID));
    if FHandles[1] > 0 then Inc(FNrHandles);
  end;
end;

procedure TConsole.Stop();
var
  nBlock            : DWORD;
begin
  if FHandles[1] > 0 then begin
    TerminateThread(FHandles[1], Cardinal(-1));
    WaitForSingleObject(FHandles[1], INFINITE);
    FHandles[1] := 0;
  end;
  if Integer(FSocket) > 0 then begin
    WSAEventSelect(FSocket, FHandles[0], 0);
    CloseHandle(FHandles[0]);
    nBlock := 0;
    ioctlsocket(FSocket, FIONBIO, nBlock);
    FSocket := INVALID_SOCKET;
  end;
end;

end.
