unit Config_u;

interface
uses
  Windows, Sysutils, WinSock;

const
  DEFLT_STAT_PERIOD = 1000;             //状态输出周期 1s

type
  TDmcFlag = (
    { "switched network" 交换网络(全双工): 可连续发送两片（开始发送下一片前，上一片已经确认）
    不要用于旧的同轴电缆网络 }
    dmcFullDuplex,

    { "not switched network" mode: 网络是已知的不可交换(无法边发边确认)! }
    dmcNotFullDuplex,

    { 点至点传送模式：使用单播（时常发生）的特殊情况下只有一个接收器。}
    dmcPointToPoint,

    { 强制使用广播而不是多播，在网卡不支持多播时才建议使用 }
    dmcBoardcast,

    { 不使用点对点，就算只有一个接收器 }
    dmcNoPointToPoint
    );
  TDmcFlags = set of TDmcFlag;

  { 数据多播模式 }
  TDmcMode = (
    { 固定模式: 接收器数据固定 }
    dmcFixedMode,
    { 流模式：允许接收器加入一个正在进行的传输 }
    dmcStreamMode,

    // Ignore lost data
    { 异步模式：不需要客户的确认。用于没有回传信道可用的情况下! }
    dmcAsyncMode,

    { FEC模式: 前向纠错，提供数据冗余备份 }
    dmcFecMode);

  TNetConfig = packed record
    ifName: PAnsiChar;                  //eht0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
    localPort: Word;                    //9001
    remotePort: Word;                   //9000

    //采用组播会话/传输
    mcastRdv: PAnsiChar;                //239.1.2.3  default nil
    ttl: Integer;

    //SOCKET OPTION
    sockSendBufSize: Integer;
    sockRecvBufSize: Integer;
  end;
  PNetConfig = ^TNetConfig;

  TSendConfig = packed record
    net: TNetConfig;
    flags: TDmcFlags;
    dmcMode: TDmcMode;

    {
      数据块(包)大小(不含16字节头)。 默认（也是最大）是1456。
      MTU(1500) - 28(UDP_HEAD + IP_HEAD) - 16(DMC_HEAD) = 1456
    }
    blockSize: Integer;

    {
      最小片尺寸（以块为单位）。 默认为32。
      当动态调整片的大小（仅适用于非双工模式）。
      双工模式忽略此设置（默认）。
    }
    min_slice_size: Integer;

    {
      默认片尺寸（以块为单位）。
      半双工模式:130
      全双工模式:112
    }
    default_slice_size: Integer;

    {
      最大片尺寸（以块为单位）。 默认值是1024。
      当动态调整片的大小（仅适用于非双工模式），从不使用比这个更大的片。
      双工模式忽略此设置（默认）。
    }
    max_slice_size: Integer;

    {
      会话期间,间隔多长时间发送一次Hello数据包。
      这个选项在[异步模式]下很有用，因为异步模式接收器不会发送一个连接请求(因此不会得到连接答复)
      因而要依赖此包得到参数信息，进入数据接收状态。
      (以毫秒为单位,默认1000)
    }
    rexmit_hello_interval: Integer;

    {
     [自动启动]连接的接收器数量达到此数。(默认0,忽略)
    }
    min_receivers: Integer;
    {
     [自动启动]当有一个接收器连接后,最多等待多长时间（以秒为单位）。(默认0,忽略)
    }
    max_receivers_wait: Integer;

    {
      [超时机制]隔一些时间发送REQACK到接收端，重复多少次后终止无响应的接收端.
      头10次间隔时间约10ms(waitAvg)左右,之后在500ms左右
      注意:等待接收端确认过程中断断续续收到些反馈消息，等待时间会增加(0.9 * waitAvg + 0.1 * tickDiff(前一次等待耗时))
    }
    retriesUntilDrop: Integer;          //sendReqack片重试次数(默认30)

    { FEC config }
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    fec_redundancy: Integer;            { how much fec blocks are added per group }
    fec_stripesize: Integer;            { size of FEC group }
    fec_stripes: Integer;               { number of FEC stripes per slice }
{$ENDIF}
    {
      用于[流模式]下，在片传输完成前隔多少包发送一次Hello数据包（默认50）。
      使新开启的接收器收到参数信息，进入数据接收状态。
    }
    rehelloOffset: Integer;             { 隔多少个块，发送一次hello }
  end;
  PSendConfig = ^TSendConfig;

  { Receiver }
type
  TRecvConfig = packed record
    net: TNetConfig;
    dmcMode: TDmcMode;                  { non-capability command line flags }
    blockSize: Integer;

    { FEC config }
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    fec_redundancy: Integer;            { how much fec blocks are added per group }
    fec_stripesize: Integer;            { size of FEC group }
    fec_stripes: Integer;               { number of FEC stripes per slice }
{$ENDIF}
  end;
  PRecvConfig = ^TRecvConfig;

implementation

end.

