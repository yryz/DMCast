unit Config_u;

interface
uses
  Windows, Sysutils, WinSock;

const
  //性能参数
  DOUBLING_SETP     = 4;                //sliceSize 增加 sliceSize div DOUBLING_SETP
  REDOUBLING_SETP   = 2;                //如果lastGoodBlocks小于sliceSize div REDOUBLING_SETP，那么sliceSize以后者为准
  MIN_CONT_SLICE    = 5;                //最小连续片数，达到则转为增加状态

  //一般常量
  MAX_CLIENTS       = 512;              //允许最大客户端（并非越大越好）
  RC_MSG_QUEUE_SIZE = MAX_CLIENTS;      //反馈消息队列大小
  DEFLT_STAT_PERIOD = 1000;             //状态输出周期 1s

const
  MAX_GOVERNORS     = 10;

type
  TDmcFlag = (
    { "switched network" 交换网络(全双工): 可连续发送两片（开始发送下一片前，上一片已经确认）
    不要用于旧的同轴电缆网络 }
    dmcFullDuplex,

    { "not switched network" mode: 网络是已知的不可交换(无法边发边确认)! }
    dmcNotFullDuplex,

    { 异步模式：不需要客户的确认。用于没有回传信道可用的情况下! }
    dmcAsyncMode,

    { 点至点传送模式：使用单播（时常发生）的特殊情况下只有一个接收器。}
    dmcPointToPoint,

    { Do automatic rate limitation by monitoring socket's send buffer
      size. Not very useful, as this still doesn't protect against the
      switch dropping packets because its queue (which might be slightly slower)
      overruns }
    //{$ifndef WINDOWS}
    // FLAG_AUTORATE =$0008;
    //{$ENDIF}

{$IFDEF BB_FEATURE_UDPCAST_FEC}
    { Forward Error Correction }
    dmcUseFec,                          // FLAG_FEC          = $0010;
{$ENDIF}

    { 使用广播而不是多播，在网卡不支持多播时 }
    dmcBCastMode,

    { 不使用点对点，就算只有一个接收器 }
    dmcNoPointToPoint,

    { 流模式：允许接收器加入一个正在进行的传输 }
    dmcStreamMode
    );
  TDmcFlags = set of TDmcFlag;

  TDiscovery = (
    DSC_DOUBLING,                       //增加块
    DSC_REDUCING                        //减少块
    );

  TNetConfig = packed record            //sizeof=216
    ifName: PAnsiChar;                  //eht0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
    localPort: Word;                    //9001
    remotePort: Word;                   //9000

    //采用组播会话/传输
    mcastRdv: PAnsiChar;                //234.1.2.3  default nil
    ttl: Integer;

    //SOCKET OPTION
    sockSendBufSize: Integer;
    sockRecvBufSize: Integer;
  end;
  PNetConfig = ^TNetConfig;

  TSendConfig = packed record
    net: TNetConfig;
    flags: TDmcFlags;                   { non-capability command line flags }
    blockSize: Integer;

    //传输速度管理(暂未实现)
//    nrGovernors: Integer;
//    rateGovernor: array[0..MAX_GOVERNORS - 1] of Pointer; //struct rateGovernor_t *rateGovernor[MAX_GOVERNORS];
//    rateGovernorData: array[0..MAX_GOVERNORS - 1] of Pointer;

    min_slice_size: Integer;
    default_slice_size: Integer;
    max_slice_size: Integer;

    //rcvbuf: DWORD;                      //根据不同客户端缓冲区大小，取最小的
    rexmit_hello_interval: Integer;     { sendHello 间隔  }

    { sender-specific parameters }
    min_receivers: Integer;             //接收端数量满足min_receivers后,自动开始
    max_receivers_wait: Integer;        //最大等待时间

    retriesUntilDrop: Integer;          //sendReqack片重试次数 （原 200）

    { FEC config }
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    fec_redundancy: Integer;            { how much fec blocks are added per group }
    fec_stripesize: Integer;            { size of FEC group }
    fec_stripes: Integer;               { number of FEC stripes per slice }
{$ENDIF}
    rehelloOffset: Integer;             { 隔多少个块，发送一次hello }
  end;
  PSendConfig = ^TSendConfig;

  //const
  //  DEFAULT_CONFIG    : TNetConfig = (
  //    ifName: 'eth0';                     //eht0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
  //    localPort: 9080;
  //    remotePort: 8090;
  //
  //    blockSize: 1456;                    //这个值在一些情况下（如家用无线），设置大点效果会好些如10K
  //    sliceSize: 32;
  //
  //    mcastRdv: nil;                      //传输地址
  //    ttl: 1;
  //
  //    nrGovernors: 0;
  //
  //    flags: [dmcNoKeyBoard];             //没有控制台!
  //    capabilities: 0;
  //    min_slice_size: 32;
  //    max_slice_size: 1456;
  //    default_slice_size: 0;              //=0 则根据情况自动选择
  //
  //    rexmit_hello_interval: 0;           //retransmit hello message
  //    autostart: 0;
  //    requestedBufSize: 0;
  //
  //    min_receivers: seWaitReceivers.Value;
  //    max_receivers_wait: 0;
  //    min_receivers_wait: 0;
  //    startTimeout: 0;
  //
  //    retriesUntilDrop: 30;
  //    rehelloOffset: 50;
  //    );

implementation

end.

