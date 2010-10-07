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

  { Sender says he's up. This is not in the enum with the others,
   * because of some endianness Snafu in early versions. However,since
   * 2005-12-23, new receivers now understand a CMD_HELLO_NEW which is
   * in sequence. Once enough of those are out in the field, we'll send
   * CMD_HELLO_NEW by default, and then phase out the old variant. }
  { Tried to remove this on 2009-08-30, but noticed that receiver was printing
   * "unexpected opcode" on retransmitted hello }

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
    capabilities: Integer;
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
    clNr: Integer;
    blockSize: Integer;
    capabilities: Integer;
    mcastAddr: array[0..15] of Byte;    { provide enough place for IPV6 }
  end;

  THello = packed record
    opCode: Word;
    reserved: SmallInt;
    capabilities: Integer;
    mcastAddr: array[0..15] of Byte;    { provide enough place for IPV6 }
    blockSize: SmallInt;
  end;

  TServerControlMsg = packed record
    case Integer of
      0: (opCode: Word);
      1: (reserved: SmallInt);
      2: (hello: THello);
      3: (connectReply: TConnectReply);
  end;

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

  TServerDataMsg = packed record        //16 byte
    case Integer of
      0: (opCode: Word);
      1: (reqack: TReqack);
      2: (dataBlock: TDataBlock);
      3: (fecBlock: TFecBlock);
  end;

  { ============================================
   * Capabilities
   }
const
  { Does the receiver support the new CMD_DATA command, which carries
   * capabilities mask?
   * "new generation" receiver:
   *   - capabilities word included in hello/connectReq commands
   *   - receiver multicast capable
   *   - receiver can receive ASYNC and SN
   }
   { 新一代(一般正常模式) }
  CAP_NEW_GEN       = $0001;

  { Use multicast instead of Broadcast for data }
  { CAP_MULTICAST 0x0002}

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  { Forward error correction }
  CAP_FEC           = $0004;
{$ENDIF}

  { This transmission is asynchronous (no receiver reply) }
  CAP_ASYNC         = $0020;

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

