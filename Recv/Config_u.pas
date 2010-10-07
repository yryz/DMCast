unit Config_u;

interface
uses
  Windows, Sysutils, WinSock;

const
  //一般常量
  DEFLT_STAT_PERIOD = 1000;             //状态输出周期 1s

const
  {
   * Receiver will passively listen to sender. Works best if sender runs
   * in async mode}
  FLAG_PASSIVE      = $0010;

  // Do not write file synchronously
  FLAG_NOSYNC       = $0040;

  // Don't ask for keyboard input on receiver end.
  FLAG_NOKBD        = $0080;

  // Do write file synchronously
  FLAG_SYNC         = $0100;

  // Streaming mode

  FLAG_STREAMING    = $0200;

  // Ignore lost data

  FLAG_IGNORE_LOST_DATA = $0400;

type
  TDmcFlag = (
    // 接收端被动Listen。如果发送端在异步模式下运行
    dmcPassiveMode,
    // Streaming mode
    dmcStreamMode,
    // Ignore lost data
    dmcIgnoreLostData);
  TDmcFlags = set of TDmcFlag;

  TNetConfig = packed record
    ifName: PAnsiChar;                  //eht0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
    localPort: Word;                    //9001
    remotePort: Word;                   //9000

    mcastRdv: PAnsiChar;
    ttl: Integer;

    //SOCKET OPTION
    sockSendBufSize: Integer;
    sockRecvBufSize: Integer;
  end;
  PNetConfig = ^TNetConfig;

  TRecvConfig = packed record
    net: TNetConfig;
    flags: TDmcFlags;                   { non-capability command line flags }
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

