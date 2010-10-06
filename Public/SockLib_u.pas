unit SockLib_u;

interface
uses
  Windows, Sysutils, WinSock, Config_u, Protoc_u, HouLog_u;

type
  TNetIf = packed record
    addr: in_addr;
    bcast: in_addr;
    name: array[0..255] of Char;
{$IFDEF SIOCGIFINDEX}
    index: Integer;
{$ENDIF}
  end;
  PNetIf = ^TNetIf;

  //加入组播数据结构
  TIp_mreq = record
    imr_multiaddr: in_addr;             //要加入的组播组的地址
    imr_interface: in_addr;             //本地接口地址
  end;
  PIp_mreq = ^TIp_mreq;
  //IO Vector
  PIOVec = ^TIOVec;
  TIOVec = packed record
    base: Pointer;
    len: Integer;
  end;
  TIOVecArr = array[0..1023] of TIOVec;
  PIOVecArr = ^TIOVecArr;

  PNetMsg = ^TNetMsg;
  TNetMsg = packed record
    head: TIOVec;
    data: TIOVec;
  end;

  TUDPSocket = class(TObject)
  private
    FSocket: TSocket;
    FLocalPort: Word;
    FRemotePort: Word;
    FAddrLen: Integer;
    FNetIf: TNetIf;
    FCtrlAddr: TSockAddrIn;             //默认广播[会话]
  private
    function GetSendBufSize(): Integer;
    function GetRecvBufSize(): Integer;
    procedure SetSendBufSize(size: Integer);
    procedure SetRecvBufSize(size: Integer);
    function GetMCastTTL(): Integer;
    procedure SetMCastTTL(Value: Integer);
  public
    constructor Create(config: PNetConfig);
    destructor Destroy; override;

    procedure Close();
    function SendCtrlMsgTo(var msg; len: Integer; addrTo: PSockAddrIn): Integer;
    function SendCtrlMsg(var msg; len: Integer): Integer;
    function RecvCtrlMsg(var msg; len: Integer;
      var addrFrom: TSockAddrIn): Integer;

    function IsFullDuplex(): Boolean;   //未实现
    function BCastOption(Value: BOOL): Integer;
    function MCastOption(ifAddr, mAddr: TInAddr; isAdd: Boolean): Integer;
    function MCastIfOption(ifAddr: TInAddr): Integer;
    function GetDefaultMCastAddress(): TInAddr;
    function GetDefaultBCastAddress(): TInAddr;
  public
    class function GetNetIf(wanted: PAnsiChar; var net_if: TNetIf): Boolean;
    class procedure InitSockAddress(inAddr: TInAddr; port: Word;
      var addr: TSockAddrIn);
    class function IsMCastAddress(addr: PSockAddrIn): Boolean;
    class function IsBCastAddress(addr: PSockAddrIn): Boolean;

    class procedure CopyIpFrom(dst, src: PSockAddrIn);
    class procedure CopyAddrFrom(dst, src: PSockAddrIn);
    //合并/分离 头和数据
    class procedure DoCopyDataMsg(msg: TNetMsg; buf: PAnsiChar;
      size: Integer; fromBuf: Boolean);
    //Select
    class function PrepareForSelect(socks: PIntegerArray; nr: Integer;
      fdSet: PFDSet): Integer;
    class function SelectSocks(socks: PIntegerArray; nr: Integer;
      timeout: Single; isRead: Boolean): Integer;
    class function GetSelectedSock(socks: PIntegerArray; nr: Integer;
      fdSet: PFDSet): Integer;
    class procedure CloseSocks(socks: PIntegerArray; nr: Integer);
  public
    property Socket: TSocket read FSocket;
    property CtrlAddr: TSockAddrIn read FCtrlAddr write FCtrlAddr;
    property SendBufSize: Integer read GetSendBufSize write SetSendBufSize;
    property RecvBufSize: Integer read GetRecvBufSize write SetRecvBufSize;
    property MCastTTL: Integer read GetMCastTTL write SetMCastTTL;
    property NetIf: TNetIf read FNetIf;
  end;

  TUDPSenderSocket = class(TUDPSocket)
  private
    FDataAddr: TSockAddrIn;             //默认组播[传输数据]
  public
    constructor Create(config: PNetConfig; isPointToPoint: Boolean;
      var tryFullDuplex: Boolean);
    function SendDataMsg(const msg: TNetMsg): Integer;
    procedure SetDataAddr(inAddr: TInAddr);
    procedure CopyDataAddrToMsg(var dst);
  public
    property DataAddr: TSockAddrIn read FDataAddr write FDataAddr;
  end;

  TUDPReceiverSocket = class(TUDPSocket)
  public
    constructor Create(config: PNetConfig);
    function RecvDataMsg(var msg: TNetMsg): Integer;
    procedure SetDataAddrFromMsg(const src);
  end;

function inet_ntoa(inaddr: TInAddr): string;
implementation

function inet_ntoa(inaddr: TInAddr): string;
var
  dwIp              : Cardinal;
begin
  dwIp := ntohl(inaddr.S_addr);
  Result := IntToStr(dwIp shr 24) + '.'
    + IntToStr(dwIp and $00FF0000 shr 16) + '.'
    + IntToStr(dwIp and $0000FF00 shr 8) + '.'
    + IntToStr(dwIp and $000000FF);
end;

function INET_ATON(const a: PAnsiChar; i: PInAddr): Boolean;
begin
  i^.s_addr := inet_addr(a);
  Result := (i^.s_addr <> INADDR_NONE) or (StrComp(a, '255.255.255.255') = 0);
end;

{**
 * Canonize interface name. If attempt is not nil, pick the interface
 * which has that address.
 * If attempt is nil, pick interfaces in the following order of preference
 * 1. eth0
 * 2. Anything starting with eth0:
 * 3. Anything starting with eth
 * 4. Anything else
 * 5. localhost
 * 6. zero address
 *}

const
  MAXLEN_PHYSADDR   = 8;
  MAXLEN_IFDESCR    = 256;
  MAX_INTERFACE_NAME_LEN = 256;
type
  PMIB_IPADDRROW = ^MIB_IPADDRROW;
  MIB_IPADDRROW = record
    dwAddr: DWORD;
    dwIndex: DWORD;
    dwMask: DWORD;
    dwBCastAddr: DWORD;
    dwReasmSize: DWORD;
    unused1: Word;
    wType: Word;
  end;

  PMIB_IPADDRTABLE = ^MIB_IPADDRTABLE;
  MIB_IPADDRTABLE = record
    dwNumEntries: DWORD;
    table: array[0..0] of MIB_IPADDRROW;
  end;

  PMIB_IFROW = ^MIB_IFROW;
  MIB_IFROW = record
    wszName: array[0..MAX_INTERFACE_NAME_LEN - 1] of WCHAR;
    dwIndex: DWORD;
    dwType: DWORD;
    dwMtu: DWORD;
    dwSpeed: DWORD;
    dwPhysAddrLen: DWORD;
    bPhysAddr: array[0..MAXLEN_PHYSADDR - 1] of BYTE;
    dwAdminStatus: DWORD;
    dwOperStatus: DWORD;
    dwLastChange: DWORD;
    dwInOctets: DWORD;
    dwInUcastPkts: DWORD;
    dwInNUcastPkts: DWORD;
    dwInDiscards: DWORD;
    dwInErrors: DWORD;
    dwInUnknownProtos: DWORD;
    dwOutOctets: DWORD;
    dwOutUcastPkts: DWORD;
    dwOutNUcastPkts: DWORD;
    dwOutDiscards: DWORD;
    dwOutErrors: DWORD;
    dwOutQLen: DWORD;
    dwDescrLen: DWORD;
    bDescr: array[0..MAXLEN_IFDESCR - 1] of BYTE;
  end;

  PMIB_IFTABLE = ^MIB_IFTABLE;
  MIB_IFTABLE = record
    dwNumEntries: DWORD;
    table: array[0..0] of MIB_IFROW;
  end;

const
  iphlpapilib       = 'iphlpapi.dll';

function GetIfTable(pIfTable: PMIB_IFTABLE; var pdwSize: ULONG; bOrder: BOOL): DWORD; stdcall;
  external iphlpapilib name 'GetIfTable';

function GetIpAddrTable(pIpAddrTable: PMIB_IPADDRTABLE; var pdwSize: ULONG; bOrder: BOOL): DWORD; stdcall;
  external iphlpapilib name 'GetIpAddrTable';

class function TUDPSocket.GetNetIf(wanted: PAnsiChar; var net_if: TNetIf): Boolean;
  function getIfRow(iftab: PMIB_IFTABLE; dwIndex: DWORD): PMIB_IFROW;
  var
    j               : Integer;
  begin

    { Find the corresponding interface row (for name and
      * MAC address) }
    for j := 0 to iftab^.dwNumEntries - 1 do
    begin
      Result := @iftab^.table[j];
      { eth0, eth1, ...}
      if Result^.dwIndex = dwIndex then
        exit;
    end;
    Result := nil;
  end;
var
  i, j              : Integer;
  m                 : ULONG;
  n                 : Integer;
  ptr               : PAnsiChar;
  etherNo, wantedEtherNo: Integer;

  iptab             : PMIB_IPADDRTABLE;
  iftab             : PMIB_IFTABLE;

  iprow, chosen     : PMIB_IPADDRROW;
  chosenIf          : PMIB_IFROW;
  wsaData           : TWSAData;         { Winsock implementation details }

  dwIp              : ULONG;
  goodness, lastGoodness: Integer;
  wantedAddress     : in_addr;
  isAddress         : Boolean;

  ifrow             : PMIB_IFROW;
  iaddr             : DWORD;
  isEther           : Boolean;
begin
  Result := False;
  etherNo := -1;
  wantedEtherNo := -2;                  { Wanted ethernet interface }
  chosen := nil;
  lastGoodness := 0;

  if (wanted <> nil) and INET_ATON(wanted, @wantedAddress) then
    isAddress := True
  else
  begin
    isAddress := False;
    wantedAddress.s_addr := 0;
  end;

  { WINSOCK initialization }
  if (WSAStartup(MAKEWORD(2, 0), wsaData) <> 0) then { Load Winsock DLL }
    raise Exception.Create('WSAStartup() failed!');

  m := 0;
  GetIpAddrTable(nil, m, TRUE);
  iptab := AllocMem(m);
  GetIpAddrTable(iptab, m, TRUE);

  m := 0;
  GetIfTable(nil, m, TRUE);
  iftab := AllocMem(m);
  GetIfTable(iftab, m, TRUE);

  if (wanted <> nil) and (StrLComp(wanted, 'eth', 3) = 0) then
    if TryStrToInt(PAnsiChar(@wanted[3]), i) then
      wantedEtherNo := i;

  for i := 0 to iptab^.dwNumEntries - 1 do
  begin
    goodness := -1;
    isEther := False;

    iprow := @iptab^.table[i];
    iaddr := iprow^.dwAddr;

    ifrow := getIfRow(iftab, iprow^.dwIndex);
    if (ifrow <> nil) and (ifrow^.dwPhysAddrLen = 6)
      and (iprow^.dwBCastAddr > 0) then
    begin
      isEther := True;
      Inc(etherNo);
    end;

    if (wanted <> nil) then
    begin
      if isAddress and (iaddr = wantedAddress.s_addr) then
      begin                             //192.168.1.1
        goodness := 8;
      end
      else if isEther and (wantedEtherNo = etherNo) then
      begin                             //eth0
        goodness := 9;
      end
      else if (ifrow^.dwPhysAddrLen > 0) then
      begin                             //MAC地址
        ptr := wanted;
        for j := 0 to ifrow^.dwPhysAddrLen - 1 do
        begin
          if ptr^ = #0 then
            Break;

          if not TryStrToInt('$' + ptr^ + PAnsiChar(ptr + 1)^, n)
            or (n <> ifrow^.bPhysAddr[j]) then
            Break;

          Inc(ptr, 2);
          if (ptr^ = '-') or (ptr^ = ':') then
            Inc(ptr);
        end;
        if (j = ifrow^.dwPhysAddrLen) then
          goodness := 9;
      end;
    end
    else
    begin
      if (iaddr = 0) then
      begin
        { disregard interfaces whose address is zero }
        goodness := 1;
      end
      else if (iaddr = htonl($7F000001)) then
      begin                             //127.0.0.1
        { disregard localhost type devices }
        goodness := 2;
      end
      else if (isEther) then
      begin
        { prefer ethernet }
        goodness := 6;
      end
      else if (ifrow^.dwPhysAddrLen > 0) then
      begin
        { then prefer interfaces which have a physical address }
        goodness := 4;
      end
      else
      begin
        goodness := 3;
      end;
    end;

    goodness := goodness * 2;
    { If all else is the same, prefer interfaces that
    * have broadcast }
    if (goodness >= lastGoodness) then
    begin
      { Privilege broadcast-enabled interfaces }
      if (iprow^.dwBCastAddr > 0) then
        Inc(goodness);
    end;

    if (goodness > lastGoodness) then
    begin
      chosen := iprow;
      chosenIf := ifrow;
      lastGoodness := goodness;
    end;
  end;

  if (chosen = nil) then
  begin
{$IFDEF EN_FATAL}
    OutLog2(llFatal, 'No suitable network interface found!'#13#10
      + 'The following interfaces are available:');
    for i := 0 to iptab^.dwNumEntries - 1 do
    begin
      iprow := @iptab^.table[i];
      dwIp := ntohl(iprow^.dwAddr);
      OutLog2(llFatal, inet_ntoa(TInAddr(dwIp)) + ' on '
        + PAnsiChar(@getIfRow(iftab, iprow^.dwIndex)^.bDescr)); //Unicode
    end;
{$ENDIF}
  end
  else
  begin
    net_if.addr.s_addr := chosen^.dwAddr;
    net_if.bcast.s_addr := chosen^.dwAddr;
    if (chosen^.dwBCastAddr > 0) then
      net_if.bcast.s_addr := net_if.bcast.s_addr or not chosen^.dwMask;
    if (chosenIf <> nil) then
    begin
      StrLCopy(net_if.name, @chosenIf^.bDescr, chosenIf^.dwDescrLen);
    end
    else
    begin
      net_if.name := '*';
    end;
    Result := True;
  end;
  FreeMemory(iftab);
  FreeMemory(iptab);
end;

{ TUDPSocket }

class procedure TUDPSocket.CopyIpFrom(dst, src: PSockAddrIn);
begin
  dst^.sin_addr := src^.sin_addr;
  dst^.sin_family := src^.sin_family;
end;

class procedure TUDPSocket.CopyAddrFrom(dst, src: PSockAddrIn);
begin
  dst.sin_addr := src.sin_addr;
  dst.sin_port := src.sin_port;
  dst.sin_family := src.sin_family;
end;

class function TUDPSocket.PrepareForSelect(socks: PIntegerArray; nr: Integer;
  fdSet: PFDSet): Integer;
var
  i, maxFd          : Integer;
begin
  FD_ZERO(fdSet^);
  maxFd := -1;
  for i := 0 to nr - 1 do
  begin
    if (socks[i] = -1) then
      Continue;
    FD_SET(socks[i], fdSet^);
    if (socks[i] > maxFd) then
      maxFd := socks[i];
  end;
  Result := maxFd;
end;

class function TUDPSocket.SelectSocks(socks: PIntegerArray; nr: Integer;
  timeout: Single; isRead: Boolean): Integer;
var
  fdSet             : TFDSet;
  maxFd             : Integer;
  tv                : TTimeVal;
  tvp               : PTimeVal;
begin
  if (timeout > 0.0) then
  begin
    tv.tv_sec := Trunc(timeout);
    tv.tv_usec := Trunc(timeout * 1000000) mod 1000000;
    tvp := @tv;
  end
  else
    tvp := nil;

  maxFd := PrepareForSelect(socks, nr, @fdSet);
  if isRead then
    Result := select(maxFd + 1, @fdSet, nil, nil, tvp)
  else
    Result := select(maxFd + 1, nil, @fdSet, nil, tvp);

  if Result > 0 then
    Result := GetSelectedSock(socks, nr, @fdSet);
end;

class function TUDPSocket.GetSelectedSock(socks: PIntegerArray; nr: Integer;
  fdSet: PFDSet): Integer;
var
  i                 : Integer;
begin
  for i := 0 to nr - 1 do
  begin
    if (socks[i] = -1) then
      Continue;
    if (FD_ISSET(socks[i], fdSet^)) then
    begin
      Result := socks[i];
      Exit;
    end;
  end;
  Result := -1;
end;

class procedure TUDPSocket.CloseSocks(socks: PIntegerArray; nr: Integer);
var
  i                 : Integer;
begin
  for i := 0 to nr - 1 do
    if socks[i] > 0 then
    begin
      closesocket(socks[i]);
      socks[i] := -1;
    end;
end;

class procedure TUDPSocket.DoCopyDataMsg(msg: TNetMsg; buf: PAnsiChar;
  size: Integer; fromBuf: Boolean);
var
  l                 : Integer;
  pBuf              : PAnsiChar;
  pIov              : PIOVec;
begin
  pBuf := buf;
  pIov := @msg.head;
  //head - data
  while True do
  begin
    l := pIov.len;
    if l > size then
      l := size;

    if fromBuf then
      Move(pBuf^, pIov.base^, l)
    else
      Move(pIov.base^, pBuf^, l);

    Dec(size, l);
    if (size < 0) or (pIov = @msg.data) then
      break;
    Inc(pBuf, l);
    pIov := @msg.data;
  end;
end;

{ TUDPSocket }

function TUDPSocket.IsFullDuplex(): Boolean;
begin
  Result := True;
end;

function TUDPSocket.BCastOption(Value: BOOL): Integer;
begin
  Result := setsockopt(FSocket, SOL_SOCKET, SO_BROADCAST, @Value, SizeOf(Value));
end;

constructor TUDPSocket.Create(config: PNetConfig);
var
  myaddr            : TSockAddrIn;
begin
  if not GetNetIf(config^.ifName, FNetIf) then
    raise Exception.Create('GetNetIf Error!');

  FLocalPort := config^.localPort;
  FRemotePort := config^.remotePort;

  FSocket := WinSock.Socket(AF_INET, SOCK_DGRAM, 0);
  if (FSocket < 0) then
    raise Exception.CreateFmt('Make Socket Error:%d', [GetLastError]);

  InitSockAddress(FNetIf.addr, FLocalPort, myaddr);

  if WinSock.bind(FSocket, myaddr, SizeOf(myaddr)) < 0 then
    raise Exception.CreateFmt('Bind Socket Error:%d', [GetLastError]);

  FAddrLen := SizeOf(TSockAddrIn);
  //控制、数据地址
  if (config^.mcastRdv <> nil) then
    InitSockAddress(TInAddr(inet_addr(config^.mcastRdv)), FRemotePort, FCtrlAddr)
  else
    InitSockAddress(GetDefaultBCastAddress(), FRemotePort, FCtrlAddr);

  //传输缓冲区大小
  if (config^.sockSendBufSize > 0) then
    SetSendBufSize(config^.sockSendBufSize);
  if (config^.sockRecvBufSize > 0) then
    SetRecvBufSize(config^.sockRecvBufSize);
end;

destructor TUDPSocket.Destroy;
begin
  Close;
  inherited;
end;

function TUDPSocket.GetRecvBufSize: Integer;
var
  len               : Integer;
begin
  len := SizeOf(Result);
  if getsockopt(FSocket, SOL_SOCKET, SO_RCVBUF, @Result, len) < 0 then
    Result := -1;
end;

function TUDPSocket.GetSendBufSize: Integer;
var
  len               : Integer;
begin
  len := SizeOf(Result);
  if getsockopt(FSocket, SOL_SOCKET, SO_SNDBUF, @Result, len) < 0 then
    Result := -1;
end;

class procedure TUDPSocket.InitSockAddress(inAddr: TInAddr; port: Word;
  var addr: TSockAddrIn);
begin
  FillChar(addr, SizeOf(addr), 0);
  addr.sin_family := AF_INET;
  addr.sin_port := htons(port);
  addr.sin_addr := inAddr;
end;

function TUDPSocket.McastOption(ifAddr, mAddr: TInAddr; isAdd: Boolean): Integer;
var
  code              : Integer;
  mreq              : TIp_mreq;
begin
  mreq.imr_interface := ifAddr;
  mreq.imr_multiaddr := mAddr;
  if isAdd then
    code := IP_ADD_MEMBERSHIP
  else
    code := IP_DROP_MEMBERSHIP;
  Result := setsockopt(FSocket, IPPROTO_IP, code, @mreq, SizeOf(mreq));
end;

function TUDPSocket.RecvCtrlMsg(var msg; len: Integer;
  var addrFrom: TSockAddrIn): Integer;
var
  addrLen           : Integer;
  port              : Word;
begin
  addrLen := SizeOf(addrFrom);
{$IFDEF LOSSTEST}
  loseRecvPacket(FSocket);
{$ENDIF}
  Result := recvfrom(FSocket, msg, len, 0, addrFrom, addrLen);
  if (Result < 0) then
    Exit;

  port := ntohs(addrFrom.sin_port);
  if (port <> FRemotePort) then
  begin
{$IFDEF DMC_WARN_ON}
    OutLog2(llWarn, Format('Bad message from port %s.%d',
      [inet_ntoa(addrFrom.sin_addr), ntohs(addrFrom.sin_port)]));
{$ELSE}
    //...
{$ENDIF}
    Result := 0;
  end;
  { flprintf('recv: %08x %d\n', * (int * )message, r); }
end;

function TUDPSocket.SendCtrlMsgTo(var msg; len: Integer;
  addrTo: PSockAddrIn): Integer;
begin
{$IFDEF LOSSTEST}
  loseSendPacket();
{$ENDIF}
  Result := sendto(FSocket, msg, len, 0, addrTo^, SizeOf(TSockAddrIn));
end;

function TUDPSocket.SendCtrlMsg(var msg; len: Integer): Integer;
begin
{$IFDEF LOSSTEST}
  loseSendPacket();
{$ENDIF}
  Result := sendto(FSocket, msg, len, 0, FCtrlAddr, SizeOf(TSockAddrIn));
end;

procedure TUDPSocket.SetRecvBufSize(size: Integer);
begin
  setsockopt(FSocket, SOL_SOCKET, SO_RCVBUF, @size, SizeOf(size));
end;

procedure TUDPSocket.SetSendBufSize(size: Integer);
begin
  setsockopt(FSocket, SOL_SOCKET, SO_SNDBUF, @size, SizeOf(size));
end;

class function TUDPSocket.IsMCastAddress(addr: PSockAddrIn): Boolean;
begin
  Result := Byte(ntohl(addr^.sin_addr.S_addr) shr 24) in [$E0..$EF]; //224. ~ 239.
end;

class function TUDPSocket.IsBCastAddress(addr: PSockAddrIn): Boolean;
begin
  Result := ntohl(addr^.sin_addr.S_addr) and $000000FF = $FF //.255
end;

function TUDPSocket.GetDefaultMCastAddress(): TInAddr;
begin
  Result.S_addr := FNetIf.addr.S_addr and htonl($07FFFFFF) or htonl($E8000000);
end;

function TUDPSocket.GetDefaultBCastAddress(): TInAddr;
begin
  Result := FNetIf.bcast;
  if (Result.S_addr = 0) and (FNetIf.addr.S_addr <> 0) then
    Result.S_addr := FNetIf.addr.S_addr and htonl($FFFFFF00) or htonl($000000FF);
end;

function TUDPSocket.GetMCastTTL: Integer;
var
  len               : Integer;
begin
  len := SizeOf(Result);
  if getsockopt(FSocket, IPPROTO_IP, IP_MULTICAST_TTL, @Result, len) < 0 then
    Result := -1;
end;

procedure TUDPSocket.SetMCastTTL(Value: Integer);
begin
  setsockopt(FSocket, IPPROTO_IP, IP_MULTICAST_TTL, @Value, SizeOf(Value));
end;

function TUDPSocket.MCastIfOption(ifAddr: TInAddr): Integer;
begin
  Result := setsockopt(FSocket, IPPROTO_IP, IP_MULTICAST_IF,
    @ifAddr, SizeOf(ifAddr));
end;

procedure TUDPSocket.Close;
begin
  if FSocket > 0 then
  begin
    closesocket(FSocket);
    FSocket := -1;
  end;
end;

{ TUDPServerSocket }

constructor TUDPSenderSocket.Create(config: PNetConfig; isPointToPoint: Boolean;
  var tryFullDuplex: Boolean);
begin
  inherited Create(config);

  //全双工判断
  if tryFullDuplex then
    tryFullDuplex := IsFullDuplex;

  if isPointToPoint then
    InitSockAddress(TInAddr(inet_addr('0.0.0.0')), FRemotePort, FDataAddr)
  else
  begin
    if IsBCastAddress(@FCtrlAddr) then
    begin
      if (config^.ttl > 1) then
        raise Exception.Create('BCast TTL not more than 1');
      BCastOption(True);
      InitSockAddress(GetDefaultMCastAddress(), FRemotePort, FDataAddr);
    end
    else if IsMCastAddress(@FCtrlAddr) then
    begin
      MCastOption(FNetIf.addr, FCtrlAddr.sin_addr, True);
      SetMCastTTL(config^.ttl);
      CopyAddrFrom(@FDataAddr, @FCtrlAddr);
    end;
  end;
end;

procedure TUDPSenderSocket.SetDataAddr(inAddr: TInAddr);
begin
  FDataAddr.sin_addr := inAddr;
end;

function TUDPSenderSocket.SendDataMsg(const msg: TNetMsg): Integer;
var
  size              : Integer;
  buf               : PAnsiChar;
begin
  size := msg.head.len + msg.data.len;
  buf := GetMemory(size);

  if buf = nil then
  begin                                 // Out of memory
    Result := -1;
    Exit;
  end;

  DoCopyDataMsg(msg, buf, size, False);
  Result := sendto(FSocket, buf^, size, 0, FDataAddr, SizeOf(TSockAddrIn));
  FreeMemory(buf);
end;

procedure TUDPSenderSocket.CopyDataAddrToMsg(var dst);
begin
  move(FDataAddr.sin_addr, dst, SizeOf(TInAddr));
end;

{ TUDPClientSocket }

constructor TUDPReceiverSocket.Create(config: PNetConfig);
begin
  inherited Create(config);
end;

function TUDPReceiverSocket.RecvDataMsg(var msg: TNetMsg): Integer;
var
  size              : Integer;
  buf               : PAnsiChar;
  fromAddr          : TSockAddrIn;
begin
  size := msg.head.len + msg.data.len;
  buf := GetMemory(size);

  if buf = nil then
  begin                                 // Out of memory
    Result := -1;
    Exit;
  end;

  Result := recvfrom(FSocket, buf^, size, 0, fromAddr, FAddrLen);
  if (Result <> -1) and (FCtrlAddr.sin_addr.S_addr = fromAddr.sin_addr.S_addr) then
    DoCopyDataMsg(msg, buf, Result, True)
  else
  begin
    Result := 0;
    OutputDebugString(PAnsiChar('TUDPSocket.RecvDataMsg unknown address! '
      + inet_ntoa(fromAddr.sin_addr)))
  end;
  FreeMemory(buf);
end;

procedure TUDPReceiverSocket.SetDataAddrFromMsg(const src);
begin
  if IsMCastAddress(@TSockAddrIn(src)) then //加入组播
    MCastOption(FNetIf.addr, TSockAddrIn(src).sin_addr, True);
end;

end.

