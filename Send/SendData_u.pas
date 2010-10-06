{$INCLUDE def.inc}

unit SendData_u;

interface
uses
  Windows, Sysutils, Classes, WinSock, Func_u,
  Config_u, Protoc_u, IStats_u, Negotiate_u,
  Participants_u, Produconsum_u, Fifo_u, SockLib_u,
  HouLog_u;

const
  NR_SLICES         = 2;

type
  TSlice = class;
  TDataPool = class;
  TRChannel = class;
  TSender = class;

  TSliceState = (SLICE_FREE,            { free slice, and in the queue of free slices }
    SLICE_NEW,                          { newly allocated. FEC calculation and first transmission }
    SLICE_XMITTED,                      { transmitted }
    SLICE_PRE_FREE                      { no longer used, but not returned to queue }
    );

  TClientsMap = array[0..MAX_CLIENTS div BITS_PER_CHAR - 1] of Byte;
  TReqackBm = packed record             //请求确认,已经准备Map
    ra: TReqack;
    readySet: TClientsMap;              { who is already ok? }
  end;

  TSlice = class
  private
    FIndex: Integer;                    //In Dp.Slices Index
    FBase: DWORD_PTR;                   { base address of slice in buffer }
    FSliceNo: Integer;
    FBytes: Integer;                    { bytes in slice }
    FNextBlock: Integer;                { index of next buffer to be transmitted }
    FState: TSliceState;                {volatile}
    FRxmitMap: TBlocksMap;
    { blocks to be retransmitted }

    FXmittedMap: TBlocksMap;
    FAnsweredMap: TClientsMap;          { who answered at all? }
    { blocks which have already been retransmitted during this round}

    FRxmitId: Integer;                  //用来区分几个重发请求，使我们能够轻易放弃的“旧”的请求的答复

    { 这个结构是用来跟踪客户answered ,并制造reqack消息 }
    FReqackBm: TReqackBm;

    FNrReady: Integer;                  { number of participants who are ready }
    FNrAnswered: Integer;               { number of participants who answered; }
    FNeedRxmit: Boolean;                { does this need retransmission? }
    FLastGoodBlocks: Integer; { last good block of slice (i.e. last block having not
    * needed retransmission }

    FLastReqack: Integer;               { last req ack sent (debug) }
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    FFecData: PAnsiChar;
{$ENDIF}

    { 引用 }
    FFifo: TFifo;
    FRc: TRChannel;
    FDp: TDataPool;
    FConfig: PSendConfig;
    FUSocket: TUDPSenderSocket;
    FNego: TNegotiate;
    FStats: ISenderStats;
  private
    function SendRawData(header: PAnsiChar; headerSize: Integer;
      data: PAnsiChar; dataSize: Integer): Integer;
    function TransmitDataBlock(i: Integer): Integer;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    function TransmitFecBlock(i: Integer): Integer;
{$ENDIF}
  public
    constructor Create(Index: Integer;
      Fifo: TFifo;
      Rc: TRChannel;
      Dp: TDataPool;
      Nego: TNegotiate);
    destructor Destroy; override;
    procedure Init(sliceNo: Integer; base: DWORD_PTR;
{$IFDEF BB_FEATURE_UDPCAST_FEC}fecData: PAnsiChar; {$ENDIF}bytes: Integer);
    function GetBlocks(): Integer;

    function Send(isRetrans: Boolean): Integer;
    function Reqack(): Integer;

    procedure MarkOk(clNo: Integer);
    procedure MarkDisconnect(clNo: Integer);
    procedure MarkParticipantAnswered(clNo: Integer);
    procedure MarkRetransmit(clNo: Integer; map: PByteArray; rxmit: Integer);
    function IsReady(clNo: Integer): Boolean;
  public
    property Index: Integer read FIndex;
    property State: TSliceState read FState write FState;
    property SliceNo: Integer read FSliceNo;
    property Bytes: Integer read FBytes;
    property NextBlock: Integer read FNextBlock; { index of next buffer to be transmitted }
    property NrReady: Integer read FNrReady;
    property NeedRxmit: Boolean read FNeedRxmit;
    property NrAnswered: Integer read FNrAnswered;
    property RxmitId: Integer read FRxmitId write FRxmitId;
  end;

  TDataPool = class(TObject)            //数据分片传输池
  private
    { 用于半双工模式动态调整SliceSize }
    FNrContSlice: Integer;              //连续成功片数，用于判断是否要增加片大小
    FDiscovery: TDiscovery;

    FSliceSize: Integer;
    FSliceIndex: Integer;
    FSlices: array[0..NR_SLICES - 1] of TSlice;
    FFreeSlicesPC: TProduceConsum;      //可用片
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    FFecData: PAnsiChar;
    FFecThread: THandle;
    FFecDataPC: TProduceConsum;
{$ENDIF}

    { 引用 }
    FFifo: TFifo;
    FConfig: PSendConfig;
    FStats: ISenderStats;
    FNego: TNegotiate;
  public
    constructor Create(Nego: TNegotiate);
    destructor Destroy; override;
    procedure InitSlice(Fifo: TFifo; Rc: TRChannel); //初始化！
    procedure Close;

    function MakeSlice(): TSlice;       //准备数据片
    function AckSlice(Slice: TSlice): Integer; //确认片，成功返回>=0
    function FreeSlice(Slice: TSlice): Integer;
    function FindSlice(Slice1, Slice2: TSlice; sliceNo: Integer): TSlice;
  public
    property NrContSlice: Integer read FNrContSlice write FNrContSlice;
    property Discovery: TDiscovery read FDiscovery write FDiscovery;
    property SliceSize: Integer read FSliceSize write FSliceSize;
  end;

  TCtrlMsgQueue = packed record
    clNo: Integer;                      //客户编号（索引）
    msg: TCtrlMsg;                      //反馈消息
  end;

  TRChannel = class(TThread)            //客户端消息反馈隧道Thread
  private
    FUSocket: TUDPSenderSocket;         { socket on which we receive the messages }

    FIncomingPC: TProduceConsum;        { where to enqueue incoming messages }
    FFreeSpacePC: TProduceConsum;       { free space }
    FMsgQueue: array[0..RC_MSG_QUEUE_SIZE - 1] of TCtrlMsgQueue; //消息队列

    { 引用 }
    FDp: TDataPool;
    FNego: TNegotiate;
    FConfig: PSendConfig;
    FParts: TParticipants;
  public
    constructor Create(Nego: TNegotiate; Dp: TDataPool);
    destructor Destroy; override;
    procedure Terminate; overload;
    procedure HandleNextMessage(xmitSlice, rexmitSlice: TSlice); //处理反馈消息队列中的消息
  protected
    procedure Execute; override;        //循环接收客户端反馈消息（但不处理）
  public
    property IncomingPC: TProduceConsum read FIncomingPC;
  end;

  TSender = class                       //(TThread)   //数据发送、处理、协调
  private
    FTerminated: Boolean;               //终止发送

    { 引用 }
    FDp: TDataPool;
    FRc: TRChannel;
    FNego: TNegotiate;
    FConfig: PSendConfig;
    FParts: TParticipants;
  public
    constructor Create(Nego: TNegotiate;
      Dp: TDataPool;
      Rc: TRChannel);
    destructor Destroy; override;

    procedure Execute;                  //override;    //循环发送和处理客户端反馈消息
  public
    property Terminated: Boolean read FTerminated write FTerminated;
  end;

implementation

{ TSlice }

constructor TSlice.Create;
begin
  FIndex := Index;
  FState := SLICE_FREE;

  FFifo := Fifo;
  FRc := Rc;
  FDp := Dp;
  FNego := Nego;
  FUSocket := Nego.USocket;
  FConfig := Nego.Config;
  FStats := Nego.Stats;
end;

destructor TSlice.Destroy;
begin
  inherited;
end;

function TSlice.GetBlocks: Integer;
begin
  Result := (FBytes + FConfig^.blockSize - 1) div FConfig^.blockSize;
end;

procedure TSlice.Init(sliceNo: Integer; base: DWORD_PTR;
{$IFDEF BB_FEATURE_UDPCAST_FEC}fecData: PAnsiChar; {$ENDIF}bytes: Integer);
begin
  FState := SLICE_NEW;

  FBase := base;
  FBytes := bytes;
  FSliceNo := sliceNo;

  FNextBlock := 0;
  FRxmitId := 0;

  FillChar(FReqackBm, SizeOf(FReqackBm), 0);
  FillChar(FRxmitMap, SizeOf(FRxmitMap), 0);
  FillChar(FXmittedMap, SizeOf(FXmittedMap), 0);
  FillChar(FAnsweredMap, SizeOf(FAnsweredMap), 0);

  FNrReady := 0;
  FNrAnswered := 0;
  FNeedRxmit := False;
  FLastGoodBlocks := 0;

  FLastReqack := 0;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  FFecData := fecData;
{$ENDIF}
end;

function TSlice.Reqack(): Integer;
var
  nrBlocks          : Integer;
begin
  Inc(FRxmitId);

  //不是全双工模式且不是第一次重传请求确认
  if not (dmcFullDuplex in FConfig^.flags) and (FRxmitId <> 0) then
  begin
    nrBlocks := GetBlocks();
{$IFDEF DEBUG}
    Writeln(Format('nrBlocks=%d lastGoodBlocks=%d', [nrBlocks, FLastGoodBlocks]));
{$ENDIF}
    //如果当前块数大于上次成功的块数，减小片大小
    if (FLastGoodBlocks <> 0) and (FLastGoodBlocks < nrBlocks) then
    begin
      FDp.Discovery := DSC_REDUCING;
      if (FLastGoodBlocks < FDp.SliceSize div REDOUBLING_SETP) then
        FDp.SliceSize := FDp.SliceSize div REDOUBLING_SETP
      else
        FDp.SliceSize := FLastGoodBlocks;

      if (FDp.SliceSize < MIN_SLICE_SIZE) then
        FDp.SliceSize := MIN_SLICE_SIZE;
{$IFDEF DMC_DEBUG_ON}
      OutLog2(llDebug, Format('Slice size^.%d', [FDp.SliceSize]));
{$ENDIF}
    end;
  end;

  FLastGoodBlocks := 0;
{$IFDEF DEBUG}
  writeln(Format('Send reqack %d.%d', [FSliceNo, slice^.rxmitId]));
{$ENDIF}
  FReqackBm.ra.opCode := htons(Word(CMD_REQACK));
  FReqackBm.ra.sliceNo := htonl(FSliceNo);
  FReqackBm.ra.bytes := htonl(FBytes);

  FReqackBm.ra.reserved := 0;
  move(FReqackBm.readySet, FAnsweredMap, SizeOf(FAnsweredMap));
  FNrAnswered := FNrReady;

  { not everybody is ready yet }
  FNeedRxmit := False;
  FillChar(FRxmitMap, SizeOf(FRxmitMap), 0);
  FillChar(FXmittedMap, SizeOf(FXmittedMap), 0);
  FReqackBm.ra.rxmit := htonl(FRxmitId);

  //  rgWaitAll(net_config, sock,
  //    FUSocket.CastAddr.sin_addr.s_addr,
  //    SizeOf(FReqackBm));
{$IFDEF DEBUG}
  writeln('sending reqack for slice ', FSliceNo);
{$ENDIF}
  //BCAST_DATA(sock, FReqackBm);
  {发送数据}
  Result := FUSocket.SendCtrlMsg(FReqackBm, SizeOf(FReqackBm));
end;

function TSlice.Send(isRetrans: Boolean): Integer;
var
  nrBlocks, i, rehello: integer;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  fecBlocks         : Integer;
{$ENDIF}
  nrRetrans         : Integer;
begin
  Result := 0;
  nrRetrans := 0;

  if isRetrans then
  begin
    FNextBlock := 0;
    if (FState <> SLICE_XMITTED) then
      Exit;
  end
  else if (FState <> SLICE_NEW) then
    Exit;

  nrBlocks := GetBlocks();
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if LongBool(FConfig^.flags and FLAG_FEC) and not isRetrans then
    fecBlocks := FConfig^.fec_redundancy * FConfig^.fec_stripes
  else
    fecBlocks := 0;
{$ENDIF}

{$IFDEF DEBUG}
  if isRetrans then
  begin
    writeln(Format('Retransmitting:%s slice %d from %d to %d (%d bytes) %d',
      [BoolToStr(isRetrans), FSliceNo, slice^.nextBlock, nrBlocks, FBytes,
      FConfig^.blockSize]));
  end;
{$ENDIF}

  if dmcStreamMode in FConfig^.flags then
  begin
    rehello := nrBlocks - FConfig^.rehelloOffset;
    if rehello < 0 then
      rehello := 0
  end
  else
    rehello := -1;

  { transmit the data }

  for i := FNextBlock to nrBlocks
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  + fecBlocks
{$ENDIF} - 1 do
  begin
    if isRetrans then
    begin
      if not BIT_ISSET(i, @FRxmitMap) or
        BIT_ISSET(i, @FXmittedMap) then
      begin                             //如果不在重传列表或已经完成那么跳过
        if (i > FLastGoodBlocks) then
          FLastGoodBlocks := i;
        Continue;
      end;

      SET_BIT(i, @FXmittedMap);
      Inc(nrRetrans);
{$IFDEF DEBUG}
      writeln(Format('Retransmitting %d.%d', [FSliceNo, i]));
{$ENDIF}
    end;

    if (i = rehello) then
      FNego.SendHello(True);            //流模式

    if i < nrBlocks then
      TransmitDataBlock(i)
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    else
      TransmitFecBlock(i - nrBlocks)
{$ENDIF};
    if not isRetrans and (FRc.FIncomingPC.GetProducedAmount > 0) then
      Break;                            //传输包时若有反馈消息(一般为需要重传)，先中止传输，处理
  end;                                  //end while

  if nrRetrans > 0 then
    FStats.AddRetrans(nrRetrans);       //更新状态

  if i <> nrBlocks
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  + fecBlocks
{$ENDIF} then
  begin
    FNextBlock := i                     //数据片没有传输完，记住下次要传输的位置
  end
  else
  begin
    FNeedRxmit := False;
    if not LongBool(isRetrans) then
      FState := SLICE_XMITTED;

{$IFDEF DEBUG}
    writeln(Format('Done: at block %d %d %d',
      [i, isRetrans, FState]));
{$ENDIF}
    Result := 2;
    Exit;
  end;
{$IFDEF DEBUG}
  writeln(Format('Done: at block %d %d %d',
    [i, isRetrans, FState]));
{$ENDIF}
  Result := 1;
end;

function TSlice.SendRawData(header: PAnsiChar; headerSize: Integer;
  data: PAnsiChar; dataSize: Integer): Integer;
var
  msg               : TNetMsg;
begin
  msg.head.base := header;
  msg.head.len := headerSize;
  msg.data.base := data;
  msg.data.len := dataSize;

  ////rgWaitAll(config, sock, FUSocket.CastAddr.sin_addr.s_addr, dataSize + headerSize);
  Result := FUSocket.SendDataMsg(msg);
{$IFDEF DMC_ERROR_ON}
  if Result < 0 then
  begin
    OutLog2(llError, Format('(%d) Could not broadcast data packet to %s:%d',
      [GetLastError, inet_ntoa(FUSocket.DataAddr.sin_addr),
      ntohs(FUSocket.DataAddr.sin_port)]));
  end;
{$ENDIF}
end;

function TSlice.TransmitDataBlock(i: Integer): Integer;
var
  msg               : TDataBlock;
  size              : Integer;
begin
  assert(i < MAX_SLICE_SIZE);

  msg.opCode := htons(Word(CMD_DATA));
  msg.sliceNo := htonl(FSliceNo);
  msg.blockNo := htons(i);

  msg.reserved := 0;
  msg.reserved2 := 0;
  msg.bytes := htonl(FBytes);

  size := FBytes - i * FConfig^.blockSize;
  if size < 0 then
    size := 0;
  if size > FConfig^.blockSize then
    size := FConfig^.blockSize;

  Result := SendRawData(@msg, SizeOf(msg),
    FFifo.GetDataBuffer(FBase + i * FConfig^.blockSize), size);
end;

{$IFDEF BB_FEATURE_UDPCAST_FEC}

function TSlice.TransmitFecBlock(int i): Integer;
var
  config            : PSendConfig;
  msg               : fecBlock;
begin
  Result := 0;
  config := sendst^.config;

  { Do not transmit zero byte FEC blocks if we are not in async mode }
  if (FBytes = 0) and not (dmcAsyncMode in FConfig^.flags)) then
Exit;

assert(i < FConfig^.fec_redundancy * FConfig^.fec_stripes);

msg.opCode := htons(CMD_FEC);
msg.stripes := htons(FConfig^.fec_stripes);
msg.sliceNo := htonl(slice^.sliceNo);
msg.blockNo := htons(i);
msg.reserved2 := 0;
msg.bytes := htonl(FBytes);
SendRawData(sendst^.socket, sendst^.config,
  @msg, SizeOf(msg),
  (slice^.fec_data + i * FConfig^.blockSize), FConfig^.blockSize);
end;
{$ENDIF}

procedure TSlice.MarkOk(clNo: Integer);
begin
  if (BIT_ISSET(clNo, @FReqackBm.readySet)) then
  begin
    { client is already marked ready }
{$IFDEF DEBUG}
    writeln(Format('client %d is already ready', [clNo]));
{$ENDIF}
  end
  else
  begin
    SET_BIT(clNo, @FReqackBm.readySet);
    Inc(FNrReady);
{$IFDEF DEBUG}
    writeln(Format('client %d replied ok for %p %d ready = %d',
      [clNo, @Self, FSliceNo, FNrReady]));
{$ENDIF}
    MarkParticipantAnswered(clNo);
  end;
end;

procedure TSlice.MarkDisconnect(clNo: Integer);
begin
  if (BIT_ISSET(clNo, @FReqackBm.readySet)) then
  begin
    //avoid counting client both as left and ready
    CLR_BIT(clNo, @FReqackBm.readySet);
    Dec(FNrReady);
  end;
  if (BIT_ISSET(clNo, @FAnsweredMap)) then
  begin
    Dec(FNrAnswered);
    CLR_BIT(clNo, @FAnsweredMap);
  end;
end;

procedure TSlice.MarkParticipantAnswered(clNo: Integer);
begin
  if BIT_ISSET(clNo, @FAnsweredMap) then //client already has answered
    Exit;

  Inc(FNrAnswered);
  SET_BIT(clNo, @FAnsweredMap);
end;

procedure TSlice.MarkRetransmit(clNo: Integer; map: PByteArray; rxmit: Integer);
var
  i                 : Integer;
begin
{$IFDEF DEBUG}
  writeln(Format('Mark retransmit Map %d@%d', [FSliceNo, clNo]));
{$ENDIF}
  if (rxmit < FRxmitId) then
  begin                                 //较早的 Reqack 回答
{$IF False}
    writeln('Late answer');
{$IFEND}
    Exit;
  end;

{$IFDEF DEBUG}
  writeln(Format('Received retransmit request for slice %d from client %d',
    [Slice^.sliceNo, clNo]);
{$ENDIF}
    //or 操作，填充需重传BlocksMap
    for i := 0 to SizeOf(FRxmitMap) - 1 do
      FRxmitMap[i] := FRxmitMap[i] or not map[i];

    FNeedRxmit := True;
    MarkParticipantAnswered(clNo);
end;

function TSlice.IsReady(clNo: Integer): Boolean;
begin
  Result := BIT_ISSET(clNo, @FReqackBm.readySet)
end;

//------------------------------------------------------------------------------
//   { TDataPool }
//------------------------------------------------------------------------------

{$IFDEF BB_FEATURE_UDPCAST_FEC}

procedure fec_encode_all_stripes(sendst: PSenderState;
  slice: PSlice);
var
  i, j              : Integer;
  stripe            : Integer;
  config            : PSendConfig;
  fifo              : PFifo;
  bytes, stripes, redundancy, nrBlocks, leftOver: Integer;
  fec_data          : PAnsiChar;
  fec_blocks        : array of PAnsiChar;
  data_blocks       : array[0..127] of PAnsiChar;
  lastBlock         : PAnsiChar;
begin
  config := sendst^.config;
  fifo := sendst^.fifo;
  bytes := FBytes;
  stripes := FConfig^.fec_stripes;
  redundancy := FConfig^.fec_redundancy;
  nrBlocks := (bytes + FConfig^.blockSize - 1) div FConfig^.blockSize;
  leftOver := bytes mod FConfig^.blockSize;
  fec_data := slice^.fec_data;

  SetLength(fec_blocks, redundancy);
  if (leftOver) then
  begin
    lastBlock := fifo^.dataBuffer + (slice^.base + (nrBlocks - 1)
      * FConfig^.blockSize) mod fifo^.dataBufSize;
    FillChar(lastBlock + leftOver, FConfig^.blockSize - leftOver, 0);
  end;

  for stripe := 0 to stripes - 1 do
  begin
    for i = : 0 to redundancy - 1 do
      fec_blocks[i] := fec_data + FConfig^.blockSize * (stripe + i * stripes);
    j := 0;
    i := stripe;
    while i < nrBlocks do
    begin
      data_blocks[j] = ADR(i, FConfig^.blockSize);
      Inc(i, stripes);
      Inc(j);
    end;
    fec_encode(FConfig^.blockSize, data_blocks, j, fec_blocks, redundancy);
  end;
end;

function fecMainThread(sendst: PSenderState): Integer;
var
  slice             : PSlice;
  sliceNo           : Integer;
begin
  sliceNo := 0;

  while True do
  begin
    { consume free slice }
    slice := makeSlice(sendst, sliceNo);
    Inc(sliceNo);
    { do the fec calculation here }
    fec_encode_all_stripes(sendst, slice);
    pc_produce(sendst^.fec_data_pc, 1);
  end;
  Result := 0;
end;
{$ENDIF}

constructor TDataPool.Create;
begin
  FNego := Nego;
  FConfig := Nego.Config;
  FStats := Nego.Stats;
end;

destructor TDataPool.Destroy;
var
  i                 : Integer;
begin
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  FFecThread.Destroy;
{$ENDIF}
  if Assigned(FFreeSlicesPC) then
    FreeAndNil(FFreeSlicesPC);
  for i := 0 to NR_SLICES - 1 do
    FreeAndNil(FSlices[i]);
  inherited;
end;

procedure TDataPool.InitSlice;
var
  i                 : Integer;
begin
  FFifo := Fifo;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if LongBool(FConfig^.flags and FLAG_FEC) then
    FFecData := GetMemory(NR_SLICES *
      FConfig^.fec_stripes *
      FConfig^.fec_redundancy *
      FConfig^.blockSize);
{$ENDIF}

  FFreeSlicesPC := TProduceConsum.Create(NR_SLICES, 'free slices');
  FFreeSlicesPC.Produce(NR_SLICES);
  for i := 0 to NR_SLICES - 1 do        //准备片
    FSlices[i] := TSlice.Create(i, Fifo, Rc, Self, FNego);

  if (FConfig^.default_slice_size = 0) then
  begin                                 //根据情况设置合适的片大小
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    if LongBool(FConfig^.flags and FLAG_FEC) then
      FSliceSize := FConfig^.fec_stripesize * FConfig^.fec_stripes
    else
{$ENDIF}if dmcAsyncMode in FConfig^.flags then
        FSliceSize := MAX_SLICE_SIZE
      else if dmcFullDuplex in FConfig^.flags then
        FSliceSize := 112
      else
        FSliceSize := 130;

    FDiscovery := DSC_DOUBLING;
  end
  else
  begin
    FSliceSize := FConfig^.default_slice_size;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    if LongBool(FConfig^.flags and FLAG_FEC) and
      (FDp.SliceSize > 128 * FConfig^.fec_stripes) then
      FDp.SliceSize := 128 * FConfig^.fec_stripes;
{$ENDIF}
  end;

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if ((FConfig^.flags & FLAG_FEC) and
    FConfig^.max_slice_size > FConfig^.fec_stripes * 128)
    FConfig^.max_slice_size = FConfig^.fec_stripes * 128;
{$ENDIF}

  if (FSliceSize > FConfig^.max_slice_size) then
    FSliceSize := FConfig^.max_slice_size;

  assert(FSliceSize <= MAX_SLICE_SIZE);

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if LongBool(FConfig^.flags and FLAG_FEC) then
  begin
    { Free memory queue is initially full }
    fec_init();
    FFecDataPC := TProduceConsum.Create(NR_SLICES, 'fec data');

    FFecThread := BeginThread(nil, 0, @fecMainThread, FConfig, 0, dwThID);
  end;
{$ENDIF}
end;

procedure TDataPool.Close;
begin
  if Assigned(FFreeSlicesPC) then
    FFreeSlicesPC.MarkEnd;

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if LongBool(FConfig^.flags and FLAG_FEC) then
  begin
    pthread_cancel(FFec_thread);
    pthread_join(FFec_thread, nil);
    pc_destoryProduconsum(FFec_data_pc);
    FreeMemory(FFec_data);
  end;
{$ENDIF}
end;

function TDataPool.MakeSlice(): TSlice;
var
  I, bytes          : Integer;
begin
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if LongBool(FConfig^.flags and FLAG_FEC) then
  begin
    FFecDataPC.Consume(1);
    i := FFecDataPC.GetConsumerPosition();
    Result := FSlices[i];
    FFecDataPC.Consumed(1);
  end
  else
{$ENDIF}
  begin
    FFreeSlicesPC.Consume(1);
    i := FFreeSlicesPC.GetConsumerPosition();
    Result := FSlices[i];
    FFreeSlicesPC.Consumed(1);
  end;

  assert(Result.State = SLICE_FREE);

  bytes := FFifo.DataPC.Consume(MIN_SLICE_SIZE * FConfig^.blockSize);
  { fixme: use current slice size here }
  if bytes > FConfig^.blockSize * FSliceSize then
    bytes := FConfig^.blockSize * FSliceSize;

  if bytes > FConfig^.blockSize then
    Dec(bytes, bytes mod FConfig^.blockSize);

  Result.Init(FSliceIndex, FFifo.DataPC.GetConsumerPosition(),
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    sendst^.fec_data + (i * FConfig^.fec_stripes *
    FConfig^.fec_redundancy *
    FConfig^.blockSize),
{$ENDIF}bytes);

  FFifo.DataPC.Consumed(bytes);
  Inc(FSliceIndex);

{$IFDEF 0}
  writeln(Format('Made slice %p %d', [@Result, sliceNo]));
{$ENDIF}
end;

function TDataPool.AckSlice(Slice: TSlice): Integer;
begin
  if not (dmcFullDuplex in FConfig^.flags) //非全双工模式，有必要动态调整片大小
  and (FSliceSize < FConfig^.max_slice_size) then //可增加
    if (FDiscovery = DSC_DOUBLING) then
    begin                               //增加片大小
      Inc(FSliceSize, FSliceSize div DOUBLING_SETP);

      if (FSliceSize >= FConfig^.max_slice_size) then
      begin
        FSliceSize := FConfig^.max_slice_size;
        FDiscovery := DSC_REDUCING;
      end;

{$IFDEF DMC_DEBUG_ON}
      OutLog2(llDebug, Format('Doubling slice size to %d', [FSliceSize]));
{$ENDIF}
    end
    else
    begin                               //成功片计数
      if FNrContSlice >= MIN_CONT_SLICE then
      begin
        FDiscovery := DSC_DOUBLING;
        FNrContSlice := 0;
      end
      else
        Inc(FNrContSlice);
    end;

  Result := Slice.Bytes;
  FFifo.FreeMemPC.Produce(Result);
  FreeSlice(Slice);                     //释放片

  FStats.AddBytes(Result);              //更新状态
end;

function TDataPool.FindSlice(Slice1, Slice2: TSlice; sliceNo: Integer): TSlice;
begin
  if (Slice1 <> nil) and (Slice1.SliceNo = sliceNo) then
    Result := Slice1
  else if (Slice2 <> nil) and (Slice2.SliceNo = sliceNo) then
    Result := Slice2
  else
    Result := nil;
end;

function TDataPool.FreeSlice(Slice: TSlice): Integer;
var
  pos               : Integer;
begin
  Result := 0;
{$IFDEF DEBUG}
  Writeln(format('Freeing slice %p %d %d',
    [@Slice, Slice.SliceNo, Slice.Index]));
{$ENDIF}
  Slice.State := SLICE_PRE_FREE;
  while True do
  begin
    pos := FFreeSlicesPC.GetProducerPosition();
    if FSlices[pos].State = SLICE_PRE_FREE then //防止Free正在使用的Slice
      FSlices[pos].State := SLICE_FREE
    else
      Break;
    FFreeSlicesPC.Produce(1);
  end;
end;

//------------------------------------------------------------------------------
//    { TRChannel }
//------------------------------------------------------------------------------

constructor TRChannel.Create;
begin
  FDp := Dp;
  FNego := Nego;
  FConfig := Nego.Config;
  FUSocket := Nego.USocket;
  FParts := Nego.Parts;

  FFreeSpacePC := TProduceConsum.Create(RC_MSG_QUEUE_SIZE, 'msg:free-queue');
  FFreeSpacePC.Produce(RC_MSG_QUEUE_SIZE);
  FIncomingPC := TProduceConsum.Create(RC_MSG_QUEUE_SIZE, 'msg:incoming');

  inherited Create(True);
end;

destructor TRChannel.Destroy;
begin
  FreeAndNil(FFreeSpacePC);
  FreeAndNil(FIncomingPC);
  inherited;
end;

procedure TRChannel.Terminate;
begin
  inherited;
  if Assigned(FFreeSpacePC) then
    FFreeSpacePC.MarkEnd;
  if Assigned(FIncomingPC) then
    FIncomingPC.MarkEnd;
  WaitFor;
end;

procedure TRChannel.HandleNextMessage(xmitSlice, rexmitSlice: TSlice);
var
  pos, clNo         : Integer;
  msg               : PCtrlMsg;
  Slice             : TSlice;
begin
  pos := FIncomingPC.GetConsumerPosition();
  msg := @FMsgQueue[pos].msg;
  clNo := FMsgQueue[pos].clNo;

{$IFDEF DEBUG}
  Writeln('handle next message');
{$ENDIF}

  FIncomingPC.ConsumeAny();
  case TOpCode(ntohs(msg^.opCode)) of
    CMD_OK:
      begin
        Slice := FDp.FindSlice(xmitSlice, rexmitSlice, ntohl(msg^.ok.sliceNo));
        if Slice <> nil then
          Slice.MarkOk(clNo);
      end;

    CMD_DISCONNECT:
      begin
        if Assigned(xmitSlice) then
          xmitSlice.MarkDisconnect(clNo);
        if Assigned(rexmitSlice) then
          rexmitSlice.MarkDisconnect(clNo);
        FParts.Remove(clNo);
      end;

    CMD_RETRANSMIT:
      begin
{$IFDEF DEBUG}
        WriteLn(Format('Received retransmittal request for %d from %d: ',
          [ntohl(msg^.retransmit.sliceNo), clNo]));
{$ENDIF}
        Slice := FDp.FindSlice(xmitSlice, rexmitSlice, ntohl(msg^.retransmit.sliceNo));
        if Slice <> nil then
          Slice.MarkRetransmit(clNo,
            @msg^.retransmit.map,
            msg^.retransmit.rxmit);
      end;
  else
    begin
{$IFDEF DMC_WARN_ON}
      OutLog2(llWarn, Format('Bad command %-.4x', [ntohs(msg^.opCode)]));
{$ENDIF}
    end;
  end;
  FIncomingPC.Consumed(1);
  FFreeSpacePC.Produce(1);
end;

procedure TRChannel.Execute;
var
  pos, clNo         : Integer;
  addrFrom          : TSockAddrIn;
begin
  while True do
  begin
    pos := FFreeSpacePC.GetConsumerPosition();
    FFreeSpacePC.ConsumeAny();

    if Terminated then
      Break;

    ReturnValue := FUSocket.RecvCtrlMsg(FMsgQueue[pos].msg,
      SizeOf(FMsgQueue[pos].msg), addrFrom);

    if ReturnValue > 0 then
    begin
      clNo := FParts.Lookup(@addrFrom);
      if (clNo < 0) then                { packet from unknown provenance }
        Continue;

      FMsgQueue[pos].clNo := clNo;
      FFreeSpacePC.Consumed(1);
      FIncomingPC.Produce(1);
    end;
  end;
end;

//------------------------------------------------------------------------------
//    { TSender }
//------------------------------------------------------------------------------

constructor TSender.Create;
begin
  FNego := Nego;
  FConfig := Nego.Config;
  FDp := Dp;
  FRc := Rc;
  FParts := Nego.Parts;
  //inherited Create(True);
end;

destructor TSender.Destroy;
begin
  FTerminated := True;
  inherited;
end;

procedure TSender.Execute;
var
  i                 : Integer;
  atEnd             : Boolean;
  nrWaited          : Integer;
  tickStart, tickDiff: DWORD;           //等待反馈计时
  waitAvg, waitTime : DWORD;

  xmitSlice, rexmitSlice: TSlice;
begin
  atEnd := False;
  nrWaited := 0;
  waitAvg := 10 * 1000;                 // 上次等待的平均数(初始0.01s，之后计算)

  xmitSlice := nil;                     // Slice第一次被传输
  rexmitSlice := nil;                   // Slice等待确认或重传

  { transmit the data }
  FNego.TransState := tsTransing;
  while not FTerminated do
  begin
    if dmcAsyncMode in FConfig^.flags then //ASYNC
    begin
      if (xmitSlice <> nil) then
      begin                             // 直接确认，释放
        FDp.AckSlice(xmitSlice);
        xmitSlice := nil;
      end;
    end
    else
    begin
      if FParts.Count < 1 then          // 没有成员
        Break;

      if (rexmitSlice <> nil)
        and (rexmitSlice.NrReady >= FParts.Count) then
      begin                             // rexmitSlice片确认完毕，释放
        FDp.AckSlice(rexmitSlice);
        rexmitSlice := nil;
      end;

      if (xmitSlice <> nil) and (rexmitSlice = nil)
        and (xmitSlice.State = SLICE_XMITTED) then
      begin                             // xmitSlice已传输，移动到rexmitSlice并(首次)请求确认
        rexmitSlice := xmitSlice;
        xmitSlice := nil;
        rexmitSlice.Reqack();
      end;

      if FRc.FIncomingPC.GetProducedAmount > 0 then
      begin                             // 处理客户反馈消息
        FRc.HandleNextMessage(xmitSlice, rexmitSlice);
        Continue;
      end;

      if (rexmitSlice <> nil) then
      begin
        if (rexmitSlice.NeedRxmit) then
        begin                           // 重传
          FDp.NrContSlice := 0;         // 连续片数清0
          rexmitSlice.Send(True);
        end
        else if (rexmitSlice.NrAnswered >= FParts.Count) then
          rexmitSlice.Reqack();         // 成员都回答了,请求重传片是否到达
      end;
    end;                                // end NO_ASYNC

    if (xmitSlice = nil) and (not atEnd) then
    begin                               // 准备xmitSlice
{$IFDEF DEBUG}
      Writeln(Format('SN = %d', [dmcFullDuplex in FConfig^.flags]));
{$ENDIF}
      if (dmcFullDuplex in FConfig^.flags) or (rexmitSlice = nil) then
      begin                             //全双工 或 上一片已经确认
        xmitSlice := FDp.MakeSlice();
        if (xmitSlice.Bytes = 0) then
          atEnd := True;                // 结束
      end;
    end;

    if (xmitSlice <> nil) and (xmitSlice.State = SLICE_NEW) then
    begin                               // 发送xmitSlice (有可能是传输过，但没传输完)
      xmitSlice.Send(False);
{$IFDEF DEBUG}
      Writeln(Format('%d Interrupted at %d / %d', xmitSlice^.sliceNo,
        [xmitSlice^.nextBlock, getSliceBlocks(xmitSlice, config)]));
{$ENDIF}
      Continue;
    end;

    if atEnd and (rexmitSlice = nil) and (xmitSlice = nil) then
      Break;                            // 结束且Slice都已成功传输

    // 等待反馈消息,直到超时
{$IFDEF DEBUG}
    WiteLn('Waiting for timeout...');
{$ENDIF}
    tickStart := GetTickCountUSec();
    if (rexmitSlice.RxmitId > 10) then
      waitTime := waitAvg div 1000 + 1000 // 最少1秒
    else
      waitTime := waitAvg div 1000;

    //Writeln(#13, waitTime);
    if FRc.IncomingPC.ConsumeAnyWithTimeout(waitTime) > 0 then
    begin                               // 有反馈消息
{$IFDEF DEBUG}
      Writeln('Have data');
{$ENDIF}
      // 根据性能更新等待时间
      tickDiff := DiffTickCount(tickStart, GetTickCountUSec());
      if (nrWaited > 0) then
        Inc(tickDiff, waitAvg);

      Inc(waitAvg, 9);
      waitAvg := Trunc(0.9 * waitAvg + 0.1 * tickDiff);

      nrWaited := 0;
      Continue;
    end
    else
    begin                               // 检测是否超时，否则再请求确认
      if (rexmitSlice <> nil) then
      begin
{$IFDEF DEBUG}
        if (nrWaited > 5) then
        begin
          Write('Timeout notAnswered map = ');
          printNotSet(rc^.participantsDb,
            @rexmitSlice^.answeredSet);
          Write(' notReady = ');
          printNotSet(rc^.participantsDb, @rexmitSlice^.sl_reqack.readySet);
          WriteLn(format(' nrAns = %d nrRead = %d nrPart = %d avg = %d',
            [rexmitSlice^.nrAnswered, rexmitSlice^.nrReady,
            nrParticipants(rc^.participantsDb), waitAvg]));
          nrWaited := 0;
        end;
{$ENDIF}
        Inc(nrWaited);
        if (rexmitSlice.RxmitId >= FConfig^.retriesUntilDrop) then
        begin                           //数据片超时
          for i := 0 to MAX_CLIENTS - 1 do
          begin
            if (not rexmitSlice.IsReady(i)) then
              if FParts.Remove(i) then
              begin                     //移除接收器
{$IFDEF DMC_MSG_ON}
                OutLog2(llMsg, 'Dropping client #' + IntToStr(i) + ' because of timeout');
{$ENDIF}
              end;
          end;
        end
        else
          rexmitSlice.Reqack();         // 重发 Reqack
      end
      else
      begin                             //rexmitSlice = nil ？奇怪！^_^!
{$IFDEF DMC_FATAL_ON}
        OutLog2(llFatal, 'Weird. Timeout and no rxmit slice');
{$ENDIF}
        Break;
      end;
    end;                                // end wait
  end;                                  // end while

{$IFDEF DMC_MSG_ON}
  OutLog2(llMsg, 'Transfer complete.');
{$ENDIF}
  FNego.TransState := tsComplete;       // 结束传输
end;

end.

