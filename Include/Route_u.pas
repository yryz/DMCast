{
  操作路由表
}
unit Route_u;

interface

uses
  Windows, Winsock;

type
  PIP_MASK_STRING = ^IP_MASK_STRING;
{$EXTERNALSYM PIP_MASK_STRING}
  IP_ADDRESS_STRING = record
    S: array[0..15] of Char;
  end;
{$EXTERNALSYM IP_ADDRESS_STRING}
  PIP_ADDRESS_STRING = ^IP_ADDRESS_STRING;
{$EXTERNALSYM PIP_ADDRESS_STRING}
  IP_MASK_STRING = IP_ADDRESS_STRING;
{$EXTERNALSYM IP_MASK_STRING}
  TIpAddressString = IP_ADDRESS_STRING;
  PIpAddressString = PIP_MASK_STRING;

  //
  // IP_ADDR_STRING - store an IP address with its corresponding subnet mask,
  // both as dotted decimal strings
  //

  PIP_ADDR_STRING = ^IP_ADDR_STRING;
{$EXTERNALSYM PIP_ADDR_STRING}
  _IP_ADDR_STRING = record
    Next: PIP_ADDR_STRING;
    IpAddress: IP_ADDRESS_STRING;
    IpMask: IP_MASK_STRING;
    Context: DWORD;
  end;
{$EXTERNALSYM _IP_ADDR_STRING}
  IP_ADDR_STRING = _IP_ADDR_STRING;
{$EXTERNALSYM IP_ADDR_STRING}
  TIpAddrString = IP_ADDR_STRING;
  PIpAddrString = PIP_ADDR_STRING;

  //
  // ADAPTER_INFO - per-adapter information. All IP addresses are stored as
  // strings
  //

  PIP_ADAPTER_INFO = ^IP_ADAPTER_INFO;
{$EXTERNALSYM PIP_ADAPTER_INFO}
  _IP_ADAPTER_INFO = record
    Next: PIP_ADAPTER_INFO;             //链表指针域，我们通过这个来遍历静态键表
    ComboIndex: DWORD;                  //保留未用
    AdapterName: array[0..131] of Char; //网卡名
    Description: array[0..131] of Char; //对网卡的描述，实际上好象是//驱动程序的名字
    AddressLength: UINT;                //物理地址的长度，通过这个我们才能正确的显示下面数组中的物理地
    Address: array[0..7] of Byte;       //物理地址，每个字节存放一个十六进制的数值
    Index: DWORD;                       //网卡索引号
    Type_: UINT;                        //网卡类型
    DhcpEnabled: UINT;                  //是否启用了DHCP动态IP分配
    CurrentIpAddress: PIP_ADDR_STRING;  //当前使用的IP地址
    IpAddressList: IP_ADDR_STRING;      //绑定到此网卡的IP地址链表，重要项目
    GatewayList: IP_ADDR_STRING;        //网关地址链表，重要项目
    DhcpServer: IP_ADDR_STRING;         //DHCP服务器地址，只有在DhcpEnabled==TRUE的情况下才有
    HaveWins: BOOL;                     //是否启用了WINS
    PrimaryWinsServer: IP_ADDR_STRING;  //主WINS地址
    SecondaryWinsServer: IP_ADDR_STRING; //辅WINS地址
    LeaseObtained: Longint;             //当前DHCP租借获取的时间
    LeaseExpires: Longint;              //当前DHCP租借失效时间。这两个数据结构只有在启用了DHCP时才有用。
  end;
{$EXTERNALSYM _IP_ADAPTER_INFO}
  IP_ADAPTER_INFO = _IP_ADAPTER_INFO;
{$EXTERNALSYM IP_ADAPTER_INFO}
  TIpAdapterInfo = IP_ADAPTER_INFO;
  PIpAdapterInfo = PIP_ADAPTER_INFO;

  {IP 路由行表结构}
  PMIB_IPFORWARDROW = ^MIB_IPFORWARDROW;
  _MIB_IPFORWARDROW = record
    dwForwardDest: DWORD;               //路由到的目标网络地址
    dwForwardMask: DWORD;               //路由到的目标网络子网掩码
    dwForwardPolicy: DWORD;             //现在没用
    dwForwardNextHop: DWORD;            //下一跳的地址，即网关地址
    dwForwardIfIndex: DWORD;            //使用的网络设备接口索引值
    dwForwardType: DWORD;               //路由类型 3是最终目标，4是非最终目标
    dwForwardProto: DWORD;              //路由协议，这个在这个函数里要设成3
    dwForwardAge: DWORD;                //路由生命周期，路由存在的秒数
    dwForwardNextHopAS: DWORD;          //没用，设成0
    dwForwardMetric1: DWORD;            //路由优先级，正数，最小优先级越高
    dwForwardMetric2: DWORD;            //下面这几个暂时不用，设成0xFFFFFFFF
    dwForwardMetric3: DWORD;
    dwForwardMetric4: DWORD;
    dwForwardMetric5: DWORD;
  end;
  MIB_IPFORWARDROW = _MIB_IPFORWARDROW;
  TMibIpForwardRow = MIB_IPFORWARDROW;
  PMibIpForwardRow = PMIB_IPFORWARDROW;

  {IP 路由全表结构}
  PMIB_IPFORWARDTABLE = ^MIB_IPFORWARDTABLE;
  _MIB_IPFORWARDTABLE = record
    dwNumEntries: DWORD;                //路由条数
    table: array[0..0] of MIB_IPFORWARDROW;
  end;
  MIB_IPFORWARDTABLE = _MIB_IPFORWARDTABLE;

const
  iphlpapilib       = 'iphlpapi.dll';

function AddIpRoute(const dwDest, dwMask, dwGawy: DWORD): boolean;
function DeleteIpRoute(dwDest: DWORD): boolean;
function SetLocalRoute(dwDest, dwMask, dwGawy: DWORD): Integer;
implementation

//下面API返回ERROR_SUCCESS就是成功

function GetBestInterface(dwDestAddr: ULONG; var pdwBestIfIndex: DWORD): DWORD; stdcall; external iphlpapilib name 'GetBestInterface';
//function GetAdaptersInfo(pAdapterInfo: PIP_ADAPTER_INFO; var pOutBufLen: ULONG): DWORD; stdcall; external iphlpapilib name 'GetAdaptersInfo';

function GetIpForwardTable(pIpForwardTable: PMIB_IPFORWARDTABLE; var pdwSize: ULONG; bOrder: BOOL): DWORD; stdcall; external iphlpapilib name 'GetIpForwardTable';

function CreateIpForwardEntry(const pRoute: MIB_IPFORWARDROW): DWORD; stdcall; external iphlpapilib name 'CreateIpForwardEntry';

function SetIpForwardEntry(const pRoute: MIB_IPFORWARDROW): DWORD; stdcall; external iphlpapilib name 'SetIpForwardEntry';

function DeleteIpForwardEntry(const pRoute: MIB_IPFORWARDROW): DWORD; stdcall; external iphlpapilib name 'DeleteIpForwardEntry';

function SetRTable(const dwDest, dwMask, dwGawy, IfIndex: DWORD): MIB_IPFORWARDROW;
begin
  with Result do
  begin
    dwForwardDest := dwDest;
    dwForwardMask := dwMask;
    dwForwardNextHop := dwGawy;
    dwForwardIfIndex := IfIndex;        //使用的网络设备接口索引值
    dwForwardType := 4;                 //路由类型 3是最终目标，4是非最终目标
    dwForwardProto := 3;                //路由协议，这个在这个函数里要设成3
    dwForwardAge := 0;                  //路由生命周期，路由存在的秒数
    dwForwardNextHopAS := 0;            //没用，设成0
    dwForwardMetric1 := 1;              //路由优先级，正数，越小优先级越高
    dwForwardMetric2 := 0;              //下面这几个暂时不用，设成0xFFFFFFFF
    dwForwardMetric3 := 0;
    dwForwardMetric4 := 0;
    dwForwardMetric5 := 0;
  end;
end;

function AddIpRoute(const dwDest, dwMask, dwGawy: DWORD): boolean;
var
  IfIndex           : DWORD;
begin
  GetBestInterface(dwGawy, IfIndex);    //获得到达指定IP网络接口
  Result := CreateIpForwardEntry(SetRTable(dwDest, dwMask, dwGawy, IfIndex)) = NO_ERROR;
end;

function DeleteIpRoute;
var
  i, dwSize         : ULONG;
  lpRouteTable      : PMIB_IPFORWARDTABLE; //路由表
  lpRouteRow        : PMIB_IPFORWARDROW;
begin
  Result := false;
  dwSize := 0;
  if GetIpForwardTable(nil, dwSize, True) = ERROR_INSUFFICIENT_BUFFER then
  begin
    lpRouteTable := nil;
    GetMem(lpRouteTable, dwSize);
    try
      if GetIpForwardTable(lpRouteTable, dwSize, True) = NO_ERROR then
        for i := 0 to lpRouteTable.dwNumEntries - 1 do
        begin
          lpRouteRow := @lpRouteTable.table[i];
          if dwDest = lpRouteRow^.dwForwardDest then
            Result := DeleteIpForwardEntry(lpRouteRow^) = NO_ERROR;
        end;
    finally
      if lpRouteTable <> nil then
        FreeMem(lpRouteTable);
    end;
  end;
end;

function SetLocalRoute;
var
  pRTable           : PMIB_IPFORWARDTABLE;
  i, dwSize         : ULONG;
  ipRow             : TMibIpForwardRow;
begin
  Result := 0;
  dwSize := 0;
  pRTable := nil;
  try
    if GetIpForwardTable(nil, dwSize, TRUE) = ERROR_INSUFFICIENT_BUFFER then
    begin
      pRTable := GetMemory(dwSize);
      if GetIpForwardTable(pRTable, dwSize, TRUE) <> NO_ERROR then
        Exit;

      for i := 0 to pRTable^.dwNumEntries - 1 do
        if dwGawy = pRTable^.table[i].dwForwardNextHop then
        begin
          with ipRow do
          begin
            dwForwardDest := dwDest;    //网络
            dwForwardMask := dwMask;    //掩码
            dwForwardNextHop := dwGawy; //网关
            dwForwardIfIndex := pRTable^.table[i].dwForwardIfIndex; //使用的网络设备接口索引值
            dwForwardType := 3;         //路由类型 3是最终目标，4是非最终目标
            dwForwardProto := 3;        //路由协议，这个在这个函数里要设成3
            dwForwardAge := 0;          //路由生命周期，路由存在的秒数
            dwForwardNextHopAS := 0;    //没用，设成0
            dwForwardMetric1 := 1;      //路由优先级，正数，越小优先级越高
            dwForwardMetric2 := 0;      //下面这几个暂时不用，设成0xFFFFFFFF
            dwForwardMetric3 := 0;
            dwForwardMetric4 := 0;
            dwForwardMetric5 := 0;
          end;
          Result := CreateIpForwardEntry(ipRow);
          Break;
        end;
    end;
  finally
    FreeMemory(pRTable);
  end;
end;

end.

