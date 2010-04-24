unit Console_u;

interface
uses
  Windows, Sysutils, WinSock;

type
  TConsole = class                      //参与控制会话
  private
    FSocket: TSocket;
    FThread: THandle;                   //Wait KeyPress
    FKey: Char;                         //Key
    FKeyPressed: Boolean;
  private
    function MakeConSocket(): Integer;
  public
    constructor Create();
    destructor Destroy; override;
    procedure Start(enKeyPress: Boolean);
    procedure Stop;
    function SelectWithConsole(var maxFd: Integer; var read_set: TFDSet;
      tv: PTimeVal): Integer;
    function PostPress(Key: Char): Boolean;
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
  if key <> #0 then
    Console.PostPress(key);
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

function TConsole.MakeConSocket(): Integer;
var
  r, len            : Integer;
  addr              : TSockAddrIn;
begin
  addr.sin_family := AF_INET;
  addr.sin_addr.s_addr := inet_addr('127.0.0.1');
  addr.sin_port := htons(0);

  Result := socket(PF_INET, SOCK_DGRAM, 0);
  r := bind(Result, addr, SizeOf(addr));
  if (r = SOCKET_ERROR) then begin
    if (Result > 0) then begin
      closesocket(Result);
      Result := 0;
    end;
    raise Exception.Create('Could not start console listen socket');
  end;
  //收发对接
  len := SizeOf(TSockAddrIn);
  getsockname(Result, addr, len);
  if connect(Result, addr, len) = SOCKET_ERROR then
    raise Exception.Create('Could not connect console socket');
end;

function TConsole.SelectWithConsole(var maxFd: Integer; var read_set: TFDSet;
  tv: PTimeVal): Integer;
begin
  FD_SET(FSocket, read_set);
  if (FSocket >= maxFd) then
    maxFd := FSocket + 1;

  Result := select(maxFd, @read_set, nil, nil, tv);
  if (Result > 0) then
    if FD_ISSET(FSocket, read_set) then
      FKeyPressed := True;
end;

function TConsole.PostPress(Key: Char): Boolean;
begin
  FKey := Key;
  Result := send(FSocket, Key, 1, 0) > 0;
  if Result then Sleep(0);              //Thread时保证数据能传出
end;

procedure TConsole.Start(enKeyPress: Boolean);
var
  dwThID            : DWORD;
begin
  FSocket := MakeConSocket();
  if enKeyPress then begin
    FThread := BeginThread(nil, 0, @WaitForKeyPress, Self, 0, DWORD(dwThID));
  end;
end;

procedure TConsole.Stop;
begin
  if FSocket > 0 then begin
    TerminateThread(FThread, 0);
    WaitForSingleObject(FThread, INFINITE);
    closesocket(FSocket);
    FSocket := -1;
  end;
end;

end.

