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

const
  MAX_GOVERNORS     = 10;

type
  TTransState = (tsRunning, tsComplete, tsExcept, tsStop);
  TDmcFlag = (
    // 接收端被动Listen。如果发送端在异步模式下运行
    dmcPassiveMode,
    // Streaming mode
    dmcStreamMode,
    // Ignore lost data
    dmcIgnoreLostData);
  TDmcFlags = set of TDmcFlag;

  TNetConfig = packed record            //sizeof=216
    ifName: PAnsiChar;                  //eht0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
    fileName: PAnsiChar;
    localPort: Word;                    //9001
    remotePort: Word;                   //9000

    blockSize: Integer;
    mcastRdv: PAnsiChar;
    ttl: Integer;
    requestedBufSize: Integer;          { requested receiver buffer }

    flags: TDmcFlags;                   { non-capability command line flags }
    capabilities: Integer;

    { FEC config }
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    fec_redundancy: Integer;            { how much fec blocks are added per group }
    fec_stripesize: Integer;            { size of FEC group }
    fec_stripes: Integer;               { number of FEC stripes per slice }
{$ENDIF}

    //全局变量
    transState: TTransState;
    clientNumber: Integer;
  end;
  PNetConfig = ^TNetConfig;

implementation

end.

