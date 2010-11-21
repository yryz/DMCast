unit Protoc_u;

interface
uses
  Windows, WinSock;

const
  MAX_FEC_INTERLEAVE = 256;
  MIN_SLICE_SIZE    = 32;               //自动调整片大小时，最小限度
  MAX_SLICE_SIZE    = 1024;             //最大片大小,最大10K左右，因MAX_SLICE_SIZE div BITS_PER_CHAR +Header(8)<1472
  MAX_BLOCK_SIZE    = 1456;             //传输时1472，包含16字节头

  BITS_PER_CHAR     = 8;
  BITS_PER_INT      = SizeOf(Integer) * 8;

type
  TOpCode = (
    { Receiver to sender }
    CMD_OK,                             { all is ok, no need to retransmit anything }
    CMD_RETRANSMIT,                     { receiver asks for some data to be retransmitted }
    CMD_GO,                             { receiver tells server to start }
    CMD_CONNECT_REQ,                    { receiver tries to find out server's address }
    CMD_DISCONNECT,                     { receiver wants to disconnect itself }

    { Sender to receiver }
    CMD_REQACK,                         { server request acknowledgments from receiver }
    CMD_CONNECT_REPLY,                  { receiver tries to find out server's address }

    CMD_DATA,                           { a block of data }
    CMD_FEC,                            { a forward-error-correction block }

    CMD_HELLO,
    CMD_HELLO_NEW,                      { sender says he's up }
    CMD_HELLO_STREAMING                 { retransmitted hello during streaming mode }
    );

type
  TOk = packed record
    opCode: Word;
    reserved: SmallInt;
    sliceNo: Integer;
  end;

  TBlocksMap = array[0..MAX_SLICE_SIZE div BITS_PER_CHAR - 1] of Byte;
  TRetransmit = packed record
    opCode: Word;
    reserved: SmallInt;
    sliceNo: Integer;
    rxmit: Integer;
    map: TBlocksMap;
  end;

  TConnectReq = packed record
    opCode: Word;
    reserved: SmallInt;
    dmcMode: Word;
    capabilities: Word;
    rcvbuf: DWORD_PTR;
  end;

  TGo = packed record
    opCode: Word;
    reserved: SmallInt;
  end;

  TDisconnect = packed record
    opCode: Word;
    reserved: SmallInt;
  end;

  PCtrlMsg = ^TCtrlMsg;
  TCtrlMsg = packed record
    case Integer of
      0: (opCode: Word);
      1: (ok: TOk);
      2: (retransmit: TRetransmit);
      3: (connectReq: TConnectReq);
      4: (go: TGo);
      5: (disconnect: TDisconnect);
  end;

  /////////////////////////////////////////////////////////

  TConnectReply = packed record
    opCode: Word;
    reserved: SmallInt;
    dmcMode: Word;
    capabilities: Word;
    clNr: Integer;
    blockSize: Integer;
    mcastAddr: array[0..15] of Byte;    { provide enough place for IPV6 }
  end;

  THello = packed record
    opCode: Word;
    reserved: SmallInt;
    dmcMode: Word;
    capabilities: Word;
    blockSize: SmallInt;
    mcastAddr: array[0..15] of Byte;    { provide enough place for IPV6 }
  end;

  TServerControlMsg = packed record
    case Integer of
      0: (opCode: Word);
      1: (reserved: SmallInt);
      2: (hello: THello);
      3: (connectReply: TConnectReply);
  end;
  PServerControlMsg = ^TServerControlMsg;

  TDataBlock = packed record
    opCode: Word;
    reserved: SmallInt;
    sliceNo: Integer;
    blockNo: Word;
    reserved2: Word;
    bytes: Integer;
  end;

  TFecBlock = packed record
    opCode: Word;
    stripes: SmallInt;
    sliceNo: Integer;
    blockNo: Word;
    reserved2: Word;
    bytes: Integer;
  end;

  TReqack = packed record
    opCode: Word;
    reserved: SmallInt;
    sliceNo: Integer;
    bytes: Integer;
    rxmit: Integer;
  end;

  TServerDataMsg = packed record
    case Integer of
      0: (opCode: Word);
      1: (reqack: TReqack);
      2: (dataBlock: TDataBlock);
      3: (fecBlock: TFecBlock);
  end;

  { dmc mode }
const
  { reliable mode }
  DMC_FIXED         = $0000;            //fixed receivers (固定接收者)
  DMC_STREAM        = $0001;            //stream mode
  { unreliable mode(no receiver reply) }
  DMC_ASYNC         = $0010;            //no reply
  DMC_FEC           = $0020;            //forward-error-correction

  { capabilities }
const

  { Does the receiver support the new CMD_DATA command, which carries
   * capabilities mask?
   * receiver:
   *   - capabilities word included in hello/connectReq commands
   *   - receiver multicast capable
   *   - receiver can receive ASYNC and SN
   }
   { "new generation" 新一代 }
  CAP_NEW_GEN       = $0001;

  { Sender currently supports CAPABILITIES and MULTICAST }
  SENDER_CAPABILITIES = CAP_NEW_GEN;
  RECEIVER_CAPABILITIES = CAP_NEW_GEN;

implementation
uses
  Fifo_u;

initialization
  Assert(SizeOf(TRetransmit) < 1472);
  Assert(MAX_SLICE_SIZE <= DISK_BLOCK_SIZE);
  
end.

