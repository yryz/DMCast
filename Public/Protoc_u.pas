unit Protoc_u;

interface
uses
  Windows, WinSock, Config_u;

type
  { Receiver to sender }

  TOpCode = (
    CMD_OK,                             { all is ok, no need to retransmit anything }
    CMD_RETRANSMIT,                     { receiver asks for some data to be retransmitted }
    CMD_GO,                             { receiver tells server to start }
    CMD_CONNECT_REQ,                    { receiver tries to find out server's address }
    CMD_DISCONNECT,                     { receiver wants to disconnect itself }

    CMD_UNUSED, { obsolete version of CMD_HELLO, dating back to the
    * time when we had little endianness (PC). This
    * opcode contained a long unnoticed bug with parsing of
    * blocksize }

{ Sender to receiver }
    CMD_REQACK,                         { server request acknowledgments from receiver }
    CMD_CONNECT_REPLY,                  { receiver tries to find out server's address }

    CMD_DATA,                           { a block of data }
    CMD_FEC,                            { a forward-error-correction block }

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
const
  CMD_HELLO         = $0500;

type
  TOk = packed record
    opCode: Word;
    reserved: SmallInt;
    sliceNo: Integer;
  end;

  TRetransmit = packed record
    opCode: Word;
    reserved: SmallInt;
    sliceNo: Integer;
    rxmit: Integer;
    map: array[0..MAX_SLICE_SIZE div BITS_PER_CHAR - 1] of char;
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
    mcastAddr: array[0..15] of char;    { provide enough place for IPV6 }
  end;

  THello = packed record
    opCode: Word;
    reserved: SmallInt;
    capabilities: Integer;
    mcastAddr: array[0..15] of char;    { provide enough place for IPV6 }
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

  TServerDataMsg = packed record
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

  CAP_NEW_GEN       = $0001;

  { Use multicast instead of Broadcast for data }
  { CAP_MULTICAST 0x0002}

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  { Forward error correction }
  CAP_FEC           = $0004;
{$ENDIF}

  { Supports big endians (a.k.a. network) }
  CAP_BIG_ENDIAN    = $0008;

  { Support little endians (a.k.a. PC) ==> obsolete! }
  CAP_LITTLE_ENDIAN = $0010;

  { This transmission is asynchronous (no receiver reply) }
  CAP_ASYNC         = $0020;

  { Sender currently supports CAPABILITIES and MULTICAST }
  SENDER_CAPABILITIES = CAP_NEW_GEN or CAP_BIG_ENDIAN;
  RECEIVER_CAPABILITIES = CAP_NEW_GEN or CAP_BIG_ENDIAN;


implementation

initialization
  Assert(SizeOf(TRetransmit) < 1472);
  Assert(MAX_SLICE_SIZE <= DISK_BLOCK_SIZE);
end.

