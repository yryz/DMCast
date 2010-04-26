unit SockLib_u;

interface
uses
  Windows, Sysutils, WinSock, Config_u, Protoc_u;

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

  TIovec = packed record
    iov_base: Pointer;
    iov_len: Integer;
  end;
  TIovecArr = array[0..1023] of TIovec;
  PIovecArr = ^TIovecArr;

  PMsghdr = ^TMsghdr;
  TMsghdr = packed record
    msg_iov: PIovecArr;
    msg_iovlen: Integer;
  end;

  TUDPSocket = class
  private
    FSocket: TSocket;
    FPortBase: Integer;
    FAddrLen: Integer;
    FNetIf: TNetIf;
    FCtrlAddr: TSockAddrIn;             //默认广播[会话]
    FDataAddr: TSockAddrIn;             //默认组播[传输数据]
  private
    function GetSendBufSize(): Integer;
    function GetRecvBufSize(): Integer;
    procedure SetSendBufSize(size: Integer);
    procedure SetRecvBufSize(size: Integer);
    function GetTTL(): Integer;
    procedure SetTTL(Value: Integer);
  public
    constructor Create(config: PNetConfig; isSender: Boolean);
    destructor Destroy; override;

    procedure Close();
    function SendCtrlMsg(var msg; len: Integer; addrTo: PSockAddrIn): Integer;
    function SendCtrlMsgCast(var msg; len: Integer): Integer;
    function RecvCtrlMsg(var msg: TCtrlMsg; var addrFrom: TSockAddrIn): Integer;
    function SendDataMsg(const msg: TMsghdr): Integer;
    function RecvDataMsg(var msg: TMsghdr): Integer; //Use Receiver

    function IsFullDuplex(): Boolean;
    function BCastOption(Value: BOOL): Integer;
    function MCastOption(ifAddr, mAddr: TInAddr; isAdd: Boolean): Integer;
    function MCastIfOption(ifAddr: TInAddr): Integer;
    procedure SetDataAddr(inAddr: TInAddr);
    function GetDefaultMCastAddress(): TInAddr;
    function GetDefaultBCastAddress(): TInAddr;
  public
    class function GetNetIf(wanted: PChar; var net_if: TNetIf): Boolean;
    class procedure InitSockAddress(inAddr: TInAddr; port: Word;
      var addr: TSockAddrIn);
    class function IsMCastAddress(addr: PSockAddrIn): Boolean;
    class function IsBCastAddress(addr: PSockAddrIn): Boolean;

    class procedure CopyIpFrom(dst, src: PSockAddrIn);
    class procedure CopyAddrFrom(dst, src: PSockAddrIn);
    class procedure CopyIpToMessage(addr: PSockAddrIn; var dst);
    class procedure CopyIpFromMessage(addr: PSockAddrIn; var src);
    class function GetDataMsgLength(const msg: TMsghdr): Integer;
    class procedure DoCopyDataMsg(const msg: TMsghdr; buf: PAnsiChar;
      n: Integer; dir: Boolean);
  published
    property Socket: TSocket read FSocket;
    property CtrlAddr: TSockAddrIn read FCtrlAddr write FCtrlAddr;
    property DataAddr: TSockAddrIn read FDataAddr write FDataAddr;
    property SendBufSize: Integer read GetSendBufSize write SetSendBufSize;
    property RecvBufSize: Integer read GetRecvBufSize write SetRecvBufSize;
    property TTL: Integer read GetTTL write SetTTL;
    property NetIf: TNetIf read FNetIf;
  end;

function selectSock(socks: PIntegerArray; nr, startTimeout: Integer): Integer;
function prepareForSelect(socks: PIntegerArray; nr: Integer; read_set: PFDSet): Integer;
function getSelectedSock(socks: PIntegerArray; nr: Integer; read_set: PFDSet): Integer;
procedure closeSock(socks: PIntegerArray; nr: Integer; target: Integer);

implementation

function INET_ATON(const a: PChar; i: PInAddr): Boolean;
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

class function TUDPSocket.GetNetIf(wanted: PChar; var net_if: TNetIf): Boolean;
  function getIfRow(iftab: PMIB_IFTABLE; dwIndex: DWORD): PMIB_IFROW;
  var
    j               : Integer;
  begin

    { Find the corresponding interface row (for name and
      * MAC address) }
    for j := 0 to iftab^.dwNumEntries - 1 do begin
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
  else begin
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
    if TryStrToInt(PChar(@wanted[3]), i) then
      wantedEtherNo := i;

  for i := 0 to iptab^.dwNumEntries - 1 do begin
    goodness := -1;
    isEther := False;

    iprow := @iptab^.table[i];
    iaddr := iprow^.dwAddr;

    ifrow := getIfRow(iftab, iprow^.dwIndex);
    if (ifrow <> nil) and (ifrow^.dwPhysAddrLen = 6)
      and (iprow^.dwBCastAddr > 0) then begin
      isEther := True;
      Inc(etherNo);
    end;

    if (wanted <> nil) then begin
      if isAddress and (iaddr = wantedAddress.s_addr) then begin
        goodness := 8;
      end else if isEther and (wantedEtherNo = etherNo) then begin
        goodness := 9;
      end else if (ifrow^.dwPhysAddrLen > 0) then begin //MAC地址
        ptr := wanted;
        for j := 0 to ifrow^.dwPhysAddrLen - 1 do begin
          if ptr^ = #0 then Break;

          if not TryStrToInt('$' + ptr^ + PChar(ptr + 1)^, n)
            or (n <> ifrow^.bPhysAddr[j]) then Break;

          Inc(ptr, 2);
          if (ptr^ = '-') or (ptr^ = ':') then Inc(ptr);
        end;
        if (j = ifrow^.dwPhysAddrLen) then
          goodness := 9;
      end;
    end else begin
      if (iaddr = 0) then begin
        { disregard interfaces whose address is zero }
        goodness := 1;
      end else if (iaddr = htonl($7F000001)) then begin //127.0.0.1
        { disregard localhost type devices }
        goodness := 2;
      end else if (isEther) then begin
        { prefer ethernet }
        goodness := 6;
      end else if (ifrow^.dwPhysAddrLen > 0) then begin
        { then prefer interfaces which have a physical address }
        goodness := 4;
      end else begin
        goodness := 3;
      end;
    end;

    goodness := goodness * 2;
    { If all else is the same, prefer interfaces that
    * have broadcast }
    if (goodness >= lastGoodness) then begin
      { Privilege broadcast-enabled interfaces }
      if (iprow^.dwBCastAddr > 0) then
        Inc(goodness);
    end;

    if (goodness > lastGoodness) then begin
      chosen := iprow;
      chosenIf := ifrow;
      lastGoodness := goodness;
    end;
  end;

  if (chosen = nil) then begin
{$IFDEF CONSOLE}
    WriteLn('No suitable network interface found!');
    WriteLn('The following interfaces are available:');
    for i := 0 to iptab^.dwNumEntries - 1 do begin
      iprow := @iptab^.table[i];
      dwIp := ntohl(iprow^.dwAddr);
      WriteLn(dwIp shr 24, '.',
        dwIp and $00FF0000 shr 16, '.',
        dwIp and $0000FF00 shr 8, '.',
        dwIp and $000000FF, ' on ',
        PChar(@getIfRow(iftab, iprow^.dwIndex)^.bDescr)); //Unicode
{$ENDIF}
    end;
  end else
  begin
    net_if.addr.s_addr := chosen^.dwAddr;
    net_if.bcast.s_addr := chosen^.dwAddr;
    if (chosen^.dwBCastAddr > 0) then
      net_if.bcast.s_addr := net_if.bcast.s_addr or not chosen^.dwMask;
    if (chosenIf <> nil) then begin
      StrLCopy(net_if.name, @chosenIf^.bDescr, chosenIf^.dwDescrLen);
    end else begin
      net_if.name := '*';
    end;
    Result := True;
  end;
  FreeMemory(iftab);
  FreeMemory(iptab);
end;

class procedure TUDPSocket.CopyIpFrom(dst, src: PSockAddrIn);
begin
  dst.sin_addr := src.sin_addr;
  dst.sin_family := src.sin_family;
end;

class procedure TUDPSocket.CopyAddrFrom(dst, src: PSockAddrIn);
begin
  dst.sin_addr := src.sin_addr;
  dst.sin_port := src.sin_port;
  dst.sin_family := src.sin_family;
end;

class procedure TUDPSocket.CopyIpToMessage(addr: PSockAddrIn; var dst);
begin
  move(addr^.sin_addr, dst, SizeOf(TInAddr));
end;

class procedure TUDPSocket.CopyIpFromMessage(addr: PSockAddrIn; var src);
begin
  move(src, addr^.sin_addr, SizeOf(TInAddr));
end;

function selectSock(socks: PIntegerArray; nr, startTimeout: Integer): Integer;
var
  read_set          : TFDSet;
  maxFd             : Integer;
  tv                : TTimeVal;
  tvp               : PTimeVal;
begin
  if (startTimeout > 0) then
  begin
    tv.tv_sec := startTimeout;
    tv.tv_usec := 0;
    tvp := @tv;
  end else
    tvp := nil;

  maxFd := prepareForSelect(socks, nr, @read_set);
  Result := select(maxFd + 1, @read_set, nil, nil, tvp);
  if (Result >= 0) then
    Result := getSelectedSock(socks, nr, @read_set);
end;

function prepareForSelect(socks: PIntegerArray; nr: Integer; read_set: PFDSet): Integer;
var
  i, maxFd          : Integer;
begin
  FD_ZERO(read_set^);
  maxFd := -1;
  for i := 0 to nr - 1 do begin
    if (socks[i] = -1) then
      Continue;
    FD_SET(socks[i], read_set^);
    if (socks[i] > maxFd) then
      maxFd := socks[i];
  end;
  Result := maxFd;
end;

function getSelectedSock(socks: PIntegerArray; nr: Integer; read_set: PFDSet): Integer;
var
  i                 : Integer;
begin
  for i := 0 to nr - 1 do begin
    if (socks[i] = -1) then
      Continue;
    if (FD_ISSET(socks[i], read_set^)) then begin
      Result := socks[i];
      Exit;
    end;
  end;
  Result := -1;
end;

procedure closeSock(socks: PIntegerArray; nr: Integer; target: Integer);
var
  i                 : Integer;
  sock              : Integer;
begin
  sock := socks[target];

  socks[target] := -1;
  for i := 0 to nr - 1 do
    if (socks[i] = sock) then           //还有引用
      Exit;
  closesocket(sock);
end;


class function TUDPSocket.GetDataMsgLength(const msg: TMsghdr): Integer;
var
  i                 : Integer;
begin
  Result := 0;
  for i := 0 to msg.msg_iovlen - 1 do
    Inc(Result, msg.msg_iov[i].iov_len);
end;

class procedure TUDPSocket.DoCopyDataMsg(const msg: TMsghdr; buf: PAnsiChar;
  n: Integer; dir: Boolean);
var
  i, l              : Integer;
  ptr               : PAnsiChar;
begin
  i := 0;
  ptr := buf;
  while (n >= 0) and (i < msg.msg_iovlen) do
  begin
    l := msg.msg_iov[i].iov_len;
    if (l > n) then l := n;

    if dir then
      Move(ptr^, msg.msg_iov[i].iov_base^, l)
    else
      Move(msg.msg_iov[i].iov_base^, ptr^, l);

    Dec(n, l);
    Inc(ptr, l);
    Inc(i);
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

constructor TUDPSocket.Create(config: PNetConfig; isSender: Boolean);
var
  myaddr            : TSockAddrIn;
  lPort, rPort      : Word;
begin
  if not GetNetIf(config^.ifName, FNetIf) then
    raise Exception.Create('GetNetIf Error!');

  FPortBase := config^.portBase;

  //全双工判断
  if not Boolean(config^.flags and (FLAG_SN or FLAG_NOTSN)) then begin
    if IsFullDuplex then begin
{$IFDEF CONSOLE}
      WriteLn('Using full duplex mode');
{$ENDIF}
      config^.flags := config^.flags or FLAG_SN;
    end;
  end;

  FSocket := WinSock.Socket(AF_INET, SOCK_DGRAM, 0);
  if (FSocket < 0) then
    raise Exception.CreateFmt('Make Socket Error:%d', [GetLastError]);

  if isSender then begin
    lPort := FPortBase + S_PORT_OFFSET;
    rPort := FPortBase + R_PORT_OFFSET;
  end else begin
    lPort := FPortBase + R_PORT_OFFSET;
    rPort := FPortBase + S_PORT_OFFSET;
  end;

  InitSockAddress(FNetIf.addr, lPort, myaddr);

  if WinSock.bind(FSocket, myaddr, SizeOf(myaddr)) < 0 then
    raise Exception.CreateFmt('Bind Socket Error:%d', [GetLastError]);

  //发送缓冲区大小
  if (config^.requestedBufSize > 0) then
    SetSendBufSize(config^.requestedBufSize);

  FAddrLen := SizeOf(TSockAddrIn);
  //控制、数据地址
  if (config^.mcastRdv <> nil) then
    InitSockAddress(TInAddr(inet_addr(config^.mcastRdv)), rPort, FCtrlAddr)
  else
    InitSockAddress(GetDefaultBCastAddress(), rPort, FCtrlAddr);

  if IsBCastAddress(@FCtrlAddr) then begin
    if (config^.ttl > 1) then
      raise Exception.Create('BCast TTL not more than 1');
    BCastOption(True);
    InitSockAddress(GetDefaultMCastAddress(), rPort, FDataAddr);
  end else
    if IsMCastAddress(@FCtrlAddr) then begin
      MCastOption(FNetIf.addr, FCtrlAddr.sin_addr, True);
      SetTTL(config^.ttl);
      CopyAddrFrom(@FDataAddr, @FCtrlAddr);
    end;

{$IFDEF CONSOLE}
  if not Boolean(config^.flags and FLAG_POINTOPOINT) then
    WriteLn('Using mcast address ', inet_ntoa(FDataAddr.sin_addr));
{$ENDIF}

  if Boolean(config^.flags and FLAG_POINTOPOINT) then
    FDataAddr.sin_addr.S_addr := 0;
end;

destructor TUDPSocket.Destroy;
begin

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
  if isAdd then code := IP_ADD_MEMBERSHIP
  else code := IP_DROP_MEMBERSHIP;
  Result := setsockopt(FSocket, IPPROTO_IP, code, @mreq, SizeOf(mreq));
end;

function TUDPSocket.RecvCtrlMsg(var msg: TCtrlMsg; var addrFrom: TSockAddrIn): Integer;
var
  addrLen           : Integer;
  port              : Word;
begin
  addrLen := SizeOf(addrFrom);
{$IFDEF LOSSTEST}
  loseRecvPacket(FSocket);
{$ENDIF}
  Result := recvfrom(FSocket, msg, SizeOf(TCtrlMsg), 0, addrFrom, addrLen);
  if (Result < 0) then
    Exit;

  port := ntohs(addrFrom.sin_port);
  if (port - FPortBase <> R_PORT_OFFSET)
    and (port - FPortBase <> S_PORT_OFFSET) then
  begin
{$IFDEF CONSOLE}
    WriteLn(Format('Bad message from port %s.%d',
      [inet_ntoa(addrFrom.sin_addr), ntohs(addrFrom.sin_port)]));
{$ELSE}
    //...
{$ENDIF}
    Result := 0;
  end;
  { flprintf('recv: %08x %d\n', * (int * )message, r); }
end;

function TUDPSocket.RecvDataMsg(var msg: TMsghdr): Integer;
var
  size              : Integer;
  buf               : PAnsiChar;
begin
  size := GetDataMsgLength(msg);
  buf := GetMemory(size);

  if (buf = nil) then
  begin
    { Out of memory }
    Result := -1;
    Exit;
  end;

  Result := recvfrom(FSocket, buf^, size, 0, FDataAddr, FAddrLen);

  DoCopyDataMsg(msg, buf, Result, True);
  FreeMemory(buf);
end;

function TUDPSocket.SendCtrlMsg(var msg; len: Integer;
  addrTo: PSockAddrIn): Integer;
begin
{$IFDEF LOSSTEST}
  loseSendPacket();
{$ENDIF}
  Result := sendto(FSocket, msg, len, 0, addrTo^, SizeOf(TSockAddrIn));
end;

function TUDPSocket.SendCtrlMsgCast(var msg; len: Integer): Integer;
begin
{$IFDEF LOSSTEST}
  loseSendPacket();
{$ENDIF}
  Result := sendto(FSocket, msg, len, 0, FCtrlAddr, SizeOf(TSockAddrIn));
end;

function TUDPSocket.SendDataMsg(const msg: TMsghdr): Integer;
var
  size              : Integer;
  buf               : PAnsiChar;
begin
  size := GetDataMsgLength(msg);
  buf := GetMemory(size);

  if (buf = nil) then
  begin
    { Out of memory }
    Result := -1;
    Exit;
  end;

  DoCopyDataMsg(msg, buf, size, False);
  Result := sendto(FSocket, buf^, size, 0, FDataAddr, SizeOf(TSockAddrIn));
  FreeMemory(buf);
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
  Result := (addr^.sin_addr.S_addr > htonl($E0000000))
    and (addr^.sin_addr.S_addr < htonl($F0FFFFFF)); //224. ~ 239.
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

function TUDPSocket.GetTTL: Integer;
var
  len               : Integer;
begin
  len := SizeOf(Result);
  if getsockopt(FSocket, IPPROTO_IP, IP_MULTICAST_TTL, @Result, len) < 0 then
    Result := -1;
end;

procedure TUDPSocket.SetTTL(Value: Integer);
begin
  setsockopt(FSocket, IPPROTO_IP, IP_MULTICAST_TTL, @Value, SizeOf(Value));
end;

function TUDPSocket.MCastIfOption(ifAddr: TInAddr): Integer;
begin
  Result := setsockopt(FSocket, IPPROTO_IP, IP_MULTICAST_IF,
    @ifAddr, SizeOf(ifAddr));
end;

procedure TUDPSocket.SetDataAddr(inAddr: TInAddr);
begin
  FDataAddr.sin_addr := inAddr;
end;

procedure TUDPSocket.Close;
begin
  if FSocket > 0 then begin
    closesocket(FSocket);
    FSocket := -1;
  end;
end;

end.
