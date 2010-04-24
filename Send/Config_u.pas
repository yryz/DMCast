{    注意结构大小要和udpcast.h中的一样!!!
}
unit Config_u;

interface
uses
  Windows, Sysutils, WinSock;

const
  //端口Offset
  S_PORT_OFFSET     = 1;                //Sender
  R_PORT_OFFSET     = 0;                //Receiver

  //性能参数
  DOUBLING_SETP     = 4;                //sliceSize 增加 sliceSize div DOUBLING_SETP
  REDOUBLING_SETP   = 2;                //如果lastGoodBlocks小于sliceSize div REDOUBLING_SETP，那么sliceSize以后者为准
  MIN_CONT_SLICE    = 5;                //最小连续片数，达到则转为增加状态

  MIN_SLICE_SIZE    = 32;               //自动调整片大小时，最小限度
  MAX_SLICE_SIZE    = 1024;             //最大片大小,最大10K左右，因MAX_SLICE_SIZE div BITS_PER_CHAR +Header(8)<1472
  MAX_BLOCK_SIZE    = 1456;             //传输时1472，包含16字节头

  DISK_BLOCK_SIZE   = 4096;             //磁盘请求最小单位，最大为 blockSize * DISK_BLOCK_SIZE
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  MAX_FEC_INTERLEAVE = 256;
{$ENDIF}

  //一般常量
  MAX_CLIENTS       = 512;              //允许最大客户端（并非越大越好）
  RC_MSG_QUEUE_SIZE = MAX_CLIENTS;      //反馈消息队列大小
  DEFLT_STAT_PERIOD = 1000;             //状态输出周期 1s

  //固定常量
  BITS_PER_CHAR     = 8;
  BITS_PER_INT      = SizeOf(Integer) * 8;
const
  { "switched network" 交换网络(全双工): 服务器准备开始发送下一数据片之前，先确认上一片。
    不要用于旧的同轴电缆网络 }
  FLAG_SN           = $0001;

  { "not switched network" mode: 网络是已知的不可交换(无法确认)! }
  FLAG_NOTSN        = $0002;

  { 异步模式：不而要客户的确认。用于没有回传信道可用的情况下! }
  FLAG_ASYNC        = $0004;

  { 点至点传送模式：使用单播（时常发生）的特殊情况下只有一个接收器。}
  FLAG_POINTOPOINT  = $0008;

  { Do automatic rate limitation by monitoring socket's send buffer
    size. Not very useful, as this still doesn't protect against the
    switch dropping packets because its queue (which might be slightly slower)
    overruns }
  //{$ifndef WINDOWS}
  // FLAG_AUTORATE =$0008;
  //{$ENDIF}

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  { Forward Error Correction }
  FLAG_FEC          = $0010;
{$ENDIF}

  { 使用广播而不是多播，在网卡不支持多播时 }
  FLAG_BCAST        = $0020;

  { 不使用点对点，就算只有一个接收器 }
  FLAG_NOPOINTOPOINT = $0040;

  { 在发送端不要询问按键开始传输 }
  FLAG_NOKBD        = $0080;

  { 流模式：允许接收器加入一个正在进行的传输 }
  FLAG_STREAMING    = $0100;

const
  MAX_GOVERNORS     = 10;

type
  TDiscovery = (
    DSC_DOUBLING,                       //增加块
    DSC_REDUCING                        //减少块
    );

  TNetConfig = packed record            //sizeof=216
    ifName: PChar;                      //eht0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
    fileName: PChar;
    portBase: Integer;                  //Port base

    blockSize: Integer;
    sliceSize: Integer;

    mcastRdv: PChar;
    ttl: Integer;
    nrGovernors: Integer;
    rateGovernor: array[0..MAX_GOVERNORS - 1] of Pointer; //struct rateGovernor_t *rateGovernor[MAX_GOVERNORS];
    rateGovernorData: array[0..MAX_GOVERNORS - 1] of Pointer;
    {int async;}
    {int pointopoint;}
    ref_tv: timeval;
    discovery: TDiscovery;              //enum sizeof=4
    { int autoRate; do queue watching using TIOCOUTQ, to avoid overruns }
    flags: Integer;                     { non-capability command line flags }
    capabilities: Integer;
    min_slice_size: Integer;
    default_slice_size: Integer;
    max_slice_size: Integer;
    rcvbuf: DWORD;                      //根据不同客户端缓冲区大小，取最小的
    rexmit_hello_interval: Integer; { retransmission interval between hello's.
    * If 0, hello message won't be retransmitted
    }
    autostart: Integer;                 { autostart after that many retransmits }
    requestedBufSize: Integer;          { requested receiver buffer }
    { sender-specific parameters }
    min_receivers: Integer;
    max_receivers_wait: Integer;
    min_receivers_wait: Integer;
    retriesUntilDrop: Integer;
    { receiver-specif parameters }
    exitWait: Integer;                  { How many milliseconds to wait on program exit }
    startTimeout: Integer;              { Timeout at start }
    { FEC config }
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    fec_redundancy: Integer;            { how much fec blocks are added per group }
    fec_stripesize: Integer;            { size of FEC group }
    fec_stripes: Integer;               { number of FEC stripes per slice }
{$ENDIF}
    rehelloOffset: Integer;             { 隔多少个块，发送一次hello }
  end;
  PNetConfig = ^TNetConfig;

implementation

end.

