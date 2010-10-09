{$INCLUDE def.inc}

unit RecvData_u;

interface
uses
  Windows, Sysutils, MyClasses, WinSock, Func_u,
  Config_u, Protoc_u, IStats_u, Negotiate_u,
  Produconsum_u, Fifo_u, SockLib_u, HouLog_u;

const
  NR_SLICES         = 4;

type
  TSlice = class;
  TDataPool = class;
  TReceiver = class;

  TSliceState = (SLICE_FREE,            { Free slice }
    SLICE_RECEIVING,                    { Data being received }
    SLICE_DONE                          { All data received }
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    ,
    SLICE_FEC,                          { Fec calculation in progress }
    SLICE_FEC_DONE                      { Fec calculation done }
{$ENDIF}
    );

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  PFecDesc = ^TFecDesc;
  TFecDesc = record
    adr: PAnsiChar;                     { address of FEC block }
    fecBlockNo: Integer;                { number of FEC block }
    erasedBlockNo: Integer;             { erased data block }
  end;
  PFecDescs = ^TFecDescs;
  TFecDescs = array[0..MAX_SLICE_SIZE - 1] of TFecDesc;
{$ENDIF}

  TSlice = class
  private
    FIndex: Integer;                    //In Dp.Slices Index
    FState: TSliceState;                { volatile }
    FBase: DWORD_PTR;                   { base offset of beginning of slice }
    FSliceNo: Integer;                  { current slice number }
    FNrBlocks: Integer;
    FBlocksTransferred: Integer;        { blocks transferred during this slice }
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    FDataBlocksTransferred: Integer;    { data blocks transferred during this slice }
{$ENDIF}
    FBytes: Integer;                    { number of bytes in this slice (or 0, if unknown) }
    FBytesKnown: Boolean;               { is number of bytes known yet? }
    FFreePos: Integer;                  { where the next data part will be stored to }
    FRetransmit: TRetransmit;
    { How many data blocks are there missing per stripe? }
    FMissing_data_blocks: array[0..MAX_FEC_INTERLEAVE - 1] of ShortInt;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    FFec_stripes: Integer;              { number of stripes for FEC }
    { How many FEC blocs do we have per stripe? }
    FFec_blocks: array[0..MAX_FEC_INTERLEAVE - 1] of ShortInt;
    FFec_descs: TFecDescs;
{$ENDIF}

    FFifo: TFifo;
    FDp: TDataPool;
    FConfig: PRecvConfig;
    FUSocket: TUDPReceiverSocket;
    FStats: IReceiverStats;
    FNego: TNegotiate;
  public
    constructor Create(Index: Integer;
      Nego: TNegotiate;
      Fifo: TFifo;
      Dp: TDataPool);
    destructor Destroy; override;
    procedure Init(sliceNo: Integer; base: DWORD_PTR);
    function CheckBytes(bytes: Integer): Integer;
    function GetBlockBase(blockNo: Integer): Pointer;

    function ProcessDataBlock(dataAdr: Pointer; blockNo,
      bytes: Integer): Integer;
    function CheckComplete(bytes: Integer): Integer; //error:-1 no:0 yes:1
    function DoFree(): Integer;

    class function SendOk(USocket: TUDPReceiverSocket; sliceNo: Integer): Integer;
    function SendRetransmit(rxmit: Integer): Integer;
    procedure FakeComplete();
  public
    property Index: Integer read FIndex;
    property State: TSliceState read FState write FState;
    property SliceNo: Integer read FSliceNo;
    property Base: DWORD_PTR read FBase;
    property Bytes: Integer read FBytes;
    property BytesKnown: Boolean read FBytesKnown;
    property FreePos: Integer read FFreePos;
  end;

  TDataPool = class(TObject)            //数据池(排序，组片)
  private
    FSlices: array[0..NR_SLICES - 1] of TSlice;
    FFreeSlicesPC: TProduceConsum;      //可用片
{$IFDEF BB_FEATURE_UDPCAST_FEC}
    FFecData: PAnsiChar;
    FFecThread: THandle;
    FFecDataPC: TProduceConsum;
{$ENDIF}
    //USE StreamMode Fisrt Slice  or  FEC
    FNextBlock: Pointer;
    //NOT FLAG_STREAMING
    FCurrentSlice: TSlice;
    //Completely received slices
    FReceivedSliceNo: Integer;

    //引用
    FFifo: TFifo;
    FConfig: PRecvConfig;
    FNego: TNegotiate;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Init(Nego: TNegotiate; Fifo: TFifo);
    procedure Close;

    function MakeSlice(sliceNo: Integer): TSlice; //准备数据片
    function FindSlice(sliceNo: Integer): TSlice;
  public
    property NextBlock: Pointer read FNextBlock;
    property CurrentSlice: TSlice read FCurrentSlice write FCurrentSlice;
    property ReceivedSliceNo: Integer read FReceivedSliceNo write FReceivedSliceNo;
    property FreeSlicesPC: TProduceConsum read FFreeSlicesPC;
  end;

  //  TFecDecode = class(TThread)           //数据FEC解码
  //  private
  //    FFec_slices: array[0..NR_SLICES - 1] of TSlice;
  //    // A reservoir of free blocks for FEC
  //    FFreeBlocksPC: TProduceConsum;
  //    FBlockAddresses: Pointer;           // adresses of blocks in local queue
  //
  //    FLocalBlockAddresses: Pointer;
  //    {* local blocks: freed FEC blocks after we
  //     * have received the corresponding data *}
  //    FLocalPos: Integer;
  //
  //    FBlockData: Pointer;
  //    FNextBlock: Pointer;
  //
  //    int endReached; {* end of transmission reached:
  //    0: transmission in progress
  //    2: network transmission _and_ FEC
  //       processing finished
  // *}
  //
  //    int netEndReached; {* In case of a FEC transmission; network
  //    * transmission finished. This is needed to avoid
  //    * a race condition, where the receiver thread would
  //    * already prepare to wait for more data, at the same
  //    * time that the FEC would set endReached. To avoid
  //    * this, we do a select without timeout before
  //    * receiving the last few packets, so that if the
  //    * race condition strikes, we have a way to protect
  //    * against
  //    *}
  //
  //    fec_code_t fec_code;
  //
  //    FConfig: PNetConfig;
  //    FStats: ITransStats;
  //  public
  //    constructor Create(Config: PNetConfig; Stats: ITransStats);
  //    destructor Destroy; override;
  //
  //  protected
  //    procedure Execute; override;        //循环等待读取数据到发送队列
  //  public
  //
  //  end;

  TReceiver = class                     //数据接收、处理、协调
  private
    FDp: TDataPool;
    FNego: TNegotiate;
    FConfig: PRecvConfig;
    FUSocket: TUDPReceiverSocket;
  protected
    function ProcessReqAck(readySet: PByteArray; sliceNo, bytes, rxmit: Integer): Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Init(Nego: TNegotiate; Dp: TDataPool);

    procedure Execute;                  //override;    //循环发送和处理客户端反馈消息
    procedure Terminate;
  end;

implementation

{ TSlice }

constructor TSlice.Create;
begin
  FIndex := Index;
  FState := SLICE_FREE;

  FDp := Dp;
  FFifo := Fifo;
  FNego := Nego;
  FStats := Nego.Stats;
  FConfig := @Nego.Config;
  FUSocket := Nego.USocket;
end;

destructor TSlice.Destroy;
begin
  inherited;
end;

procedure TSlice.Init(sliceNo: Integer; base: DWORD_PTR);
begin
  assert((FState = SLICE_FREE) or (FState = SLICE_RECEIVING));

  FState := SLICE_RECEIVING;
  FBytes := 0;
  FFreePos := 0;
  FBlocksTransferred := 0;
  FillChar(FRetransmit, SizeOf(FRetransmit), 0);

  if FDp.CurrentSlice <> nil then
  begin
    if not FDp.CurrentSlice.BytesKnown then
      raise Exception.Create('Previous slice size not known!');
    //IgnoreLostData
    if LongBool(FNego.DmcMode and (DMC_ASYNC or DMC_FEC)) then
      FBytes := FDp.CurrentSlice.Bytes;
  end;

  //只有流模式可能准备多片交错
  if (FNego.DmcMode <> DMC_STREAM)
    and (FDp.FCurrentSlice <> nil) then
    if FDp.CurrentSlice.SliceNo <> sliceNo - 1 then
      raise Exception.CreateFmt('Slice no mismatch %d <-> %d',
        [sliceNo, FDp.CurrentSlice.SliceNo]);

  FBase := base;
  FSliceNo := sliceNo;
  FBytesKnown := False;
  FillChar(FMissing_data_blocks, SizeOf(FMissing_data_blocks), 0);
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  FDataBlocksTransferred := 0;
  FillChar(fec_stripes);
  FillChar(fec_blocks);
  FillChar(fec_descs);
{$ENDIF}
  FDp.CurrentSlice := Self;
end;

function TSlice.CheckBytes(bytes: Integer): Integer;
begin
  Result := bytes;
  if FBytesKnown then
  begin
    if FBytes <> bytes then
    begin
{$IFDEF DMC_FATAL_ON}
      OutLog2(llFatal, Format('Byte number mismatch %d <-> %d',
        [bytes, FBytes]));
{$ENDIF}
      FNego.TransState := tsExcept;
      Result := -1;
    end;
  end
  else
  begin
    FBytes := bytes;
    FBytesKnown := True;
    FNrBlocks := (FBytes + FConfig^.blockSize - 1) div FConfig^.blockSize;

    if (FNego.DmcMode <> DMC_STREAM) then
    begin
      {* In streaming mode, do not reserve space as soon as first
       * block of slice received, but only when slice complete.
       * For detailed discussion why, see comment in checkSliceComplete
       *}
      FFifo.FreeMemPC.Consumed(bytes);
    end;
  end;
end;

function TSlice.GetBlockBase(blockNo: Integer): Pointer;
begin
  Result := FFifo.GetDataBuffer(FBase + blockNo * FConfig^.blockSize);
end;

function TSlice.ProcessDataBlock(dataAdr: Pointer; blockNo,
  bytes: Integer): Integer;
var
  shouldAdr         : Pointer;
begin
  Result := 0;
  if (FState = SLICE_FREE)
    or (FState = SLICE_DONE)
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  or (FState = SLICE_FEC)
    or (FState = SLICE_FEC_DONE)
{$ENDIF} then
  begin
    // an old slice. Ignore
    Exit;
  end;

  if (FSliceNo > FDp.CurrentSlice.SliceNo + 2) then
  begin
{$IFDEF DMC_FATAL_ON}
    OutLog2(llFatal, 'We have been dropped by sender');
{$ENDIF}
    FNego.TransState := tsExcept;
    Result := -1;                       //终止传输
    Exit;
  end;

  if BIT_ISSET(blockNo, @FRetransmit.map) then
  begin                                 //我们已经有了这个包,忽略(we already have this packet, ignore)
{$IFDEF 0}
    flprintf('Packet %d: %d not for us', sliceNo, blockNo);
{$ENDIF}
    Exit;
  end;

{$IFDEF DMC_FATAL_ON}
  if FBase mod FConfig^.blockSize > 0 then
  begin
    OutLog2(llFatal, Format('Bad base %d, not multiple of block size %d',
      [FBase, FConfig^.blockSize]));
  end;
{$ENDIF}

  //排序
  shouldAdr := GetBlockBase(blockNo);
  if (shouldAdr <> dataAdr) then
  begin                                 //复制信息到正确的地方 copy message to the correct place
    move(dataAdr^, shouldAdr^, FConfig^.blockSize);
  end;

  //检测片大小
  Result := CheckBytes(bytes);
  if Result < 0 then
    Exit;

  SET_BIT(blockNo, @FRetransmit.map);

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if (Slice.Fec_stripes <> 0) then
  begin
    stripe := blockNo mod Slice.Fec_stripes;
    Dec(Slice.Missing_data_blocks[stripe]);

    assert(Slice.Missing_data_blocks[stripe] >= 0);

    if (Slice.Missing_data_blocks[stripe] < Slice.Fec_blocks[stripe]) then
    begin
      // FIXME: FEC block should be enqueued in local queue here...
      Dec(Slice.Fec_blocks[stripe]);
      blockIdx := stripe + Slice.Fec_blocks[stripe] * Slice.Fec_stripes;

      assert(Slice.Fec_descs[blockIdx].adr <> 0);

      clst - > localBlockAddresses[clst - > localPos + +] =
        Slice.fec_descs[blockIdx].adr;
      Slice.fec_descs[blockIdx].adr = 0;
      Slice.BlocksTransferred := Slice.BlocksTransferred - 1;
    end;
  end;

  Inc(FDataBlocksTransferred);
{$ENDIF}
  Inc(FBlocksTransferred);

  //重新计算下块位置
  while (FFreePos < MAX_SLICE_SIZE) and BIT_ISSET(FFreePos, @FRetransmit.map) do
    Inc(FFreePos);
end;

function TSlice.CheckComplete(bytes: Integer): Integer;
begin
  if CheckBytes(bytes) < 0 then
  begin
    Result := -1;
    Exit;
  end;

  if (FNrBlocks <> FBlocksTransferred) then
    Result := 0
  else
  begin                                 //完成
    Result := 1;
    FDp.ReceivedSliceNo := FSliceNo;

    if FNego.DmcMode = DMC_STREAM then
    begin
      {* If we are in streaming mode, the storage space for the first
       * entire slice is only consumed once it is complete. This
       * is because it is only at comletion time that we know
       * for sure that it can be completed (before, we could
       * have missed the beginning).
       * After having completed one slice, revert back to normal
       * mode where we consumed the free space as soon as the
       * first block is received (not doing this would produce
       * errors if a new slice is started before a previous one
       * is complete, such as during retransmissions)
       *}
      FFifo.FreeMemPC.Consumed(FBytes);
      FNego.DmcMode := DMC_FIXED;       //进入固定模式
    end;

{$IFDEF BB_FEATURE_UDPCAST_FEC}
    if (FNrBlocks = FDataBlocksTransferred) then
      FState := SLICE_DONE
    else
    begin
      assert(FConfig^.use_fec);
      FState := SLICE_FEC;
    end;
    if (FConfig^.use_fec) then
    begin
      pos := FDp.FecDataPC.GetProducerPosition();
      assert((FState = SLICE_DONE) or (FState = SLICE_FEC));
      clst - > fec_slices[pos] = Slice;
      FDp.FecDataPC.Produce(1);
    end
    else
{$ENDIF}
      //FState := SLICE_DONE;
      Self.DoFree;
  end;
end;

function TSlice.DoFree: Integer;
begin
  Result := FBytes;
  if Assigned(FStats) then
    FStats.AddBytes(FBytes);

  // signal data received (END信号数据)
  if FBytes = 0 then
  begin
    FFifo.DataPC.MarkEnd();
    FNego.TransState := tsComplete;
  end
  else
    FFifo.DataPC.Produce(FBytes);

  // free up slice structure
{$IFDEF DEBUG}
  flprintf('Giving back slice %d = > %d %p',
    FSliceNo, FIndex, Self);
{$ENDIF}
  FState := SLICE_FREE;
  FDp.FreeSlicesPC.Produce(1);
end;

class function TSlice.SendOk(USocket: TUDPReceiverSocket; sliceNo: Integer): Integer;
var
  ok                : TOk;
begin
  ok.opCode := htons(Word(CMD_OK));
  ok.reserved := 0;
  ok.sliceNo := htonl(sliceNo);
  Result := USocket.SendCtrlMsg(ok, SizeOf(ok));
end;

function TSlice.SendRetransmit(rxmit: Integer): Integer;
begin
{$IFDEF DMC_DEBUG_ON}
  OutLog2(llDebug, Format('Ask for retransmission(%d : %d / %d - %d) Recved: %d',
    [FSliceNo, FBlocksTransferred, FNrBlocks, bytes, FDp.ReceivedSliceNo]));
{$ENDIF}
  FRetransmit.opCode := htons(Word(CMD_RETRANSMIT));
  FRetransmit.reserved := 0;
  FRetransmit.sliceNo := htonl(FSliceNo);
  FRetransmit.rxmit := htonl(rxmit);
  Result := FUSocket.SendCtrlMsg(FRetransmit, SizeOf(FRetransmit));
end;

procedure TSlice.FakeComplete();
begin
  FBlocksTransferred := FNrBlocks;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
  FDataBlocksTransferred := FNrBlocks;
{$ENDIF}
  CheckComplete(FBytes);
end;

//------------------------------------------------------------------------------
//   { TDataPool }
//------------------------------------------------------------------------------

constructor TDataPool.Create;
begin
  inherited Create;
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
  begin
    if Assigned(FSlices[i]) then
      FSlices[i].Free
  end;
  inherited;
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

procedure TDataPool.Init;
var
  i                 : Integer;
begin
  FFifo := Fifo;
  FNego := Nego;
  FConfig := @Nego.Config;

  FReceivedSliceNo := -1;
  FFreeSlicesPC := TProduceConsum.Create(NR_SLICES, 'free slices');
  FFreeSlicesPC.Produce(NR_SLICES);
  for i := 0 to NR_SLICES - 1 do
    FSlices[i] := TSlice.Create(i, FNego, Fifo, Self);

  if FNego.DmcMode <> DMC_STREAM then
    MakeSlice(0);                       //准备 CurrentSlice

  FNextBlock := Fifo.GetDataBuffer(0);

{$IFDEF BB_FEATURE_UDPCAST_FEC}
  if LongBool(FConfig^.flags and FLAG_FEC) then
  begin
    fec_init();
    / * fec new involves memory
      * allocation.Better do it here * /
      clst - > use_fec = 0;
    clst - > fec_data_pc = pc_makeProduconsum(NR_SLICES, "fec data");

    clst - > freeBlocks_pc = pc_makeProduconsum(NR_BLOCKS, "free blocks");
    pc_produce(clst - > freeBlocks_pc, NR_BLOCKS);
    clst - > blockAddresses = calloc(NR_BLOCKS, sizeof(char * ));
    clst - > localBlockAddresses = calloc(NR_BLOCKS, sizeof(char * ));
    clst - > blockData = xmalloc(NR_BLOCKS * net_config - > blockSize);
    for (i = 0; i < NR_BLOCKS; i + +)
      clst - > blockAddresses[i] = clst - > blockData + i * net_config - > blockSize;
    clst - > localPos = 0;

    FFecThread := BeginThread(nil, 0, @fecMainThread, FConfig, 0, dwThID);
  end;
{$ENDIF}
end;

function TDataPool.MakeSlice(sliceNo: Integer): TSlice;
var
  pos               : Integer;
begin
  pos := FFreeSlicesPC.GetConsumerPosition();
{$IFDEF DEBUG}
  flprintf('Getting new slice %d', pos);
{$ENDIF}
  if FFreeSlicesPC.Consume(1) = 0 then
  begin
    Result := nil;
    Exit;
  end;
  FFreeSlicesPC.Consumed(1);
{$IFDEF DEBUG}
  flprintf('Got new slice');
{$ENDIF}
  Result := FSlices[pos];
  assert(Result.State = SLICE_FREE);

  // wait for free data memory
{$IFDEF DEBUG}
  if (FFifo.FreeMemPC.Consume(0) < FConfig^.blockSize * MAX_SLICE_SIZE) then
    flprintf('Pipeline full');
{$ENDIF}
  FFifo.FreeMemPC.Consume(FConfig^.blockSize * MAX_SLICE_SIZE);
  Result.Init(sliceNo, FFifo.FreeMemPC.GetConsumerPosition());
end;

function TDataPool.FindSlice(sliceNo: Integer): TSlice;
var
  pos               : Integer;
  Slice             : TSlice;
begin
  Result := nil;
  if FCurrentSlice = nil then
  begin
    // Streaming mode?
    Result := MakeSlice(sliceNo);
    Exit;
  end;

  if sliceNo <= FReceivedSliceNo then
    Exit;                               //已经完成

  if (sliceNo <= FCurrentSlice.SliceNo) then
  begin                                 //片已经存在
    Result := FCurrentSlice;
    pos := Result.Index;
    while (Result.SliceNo <> sliceNo) do
    begin
      if (Result.State = SLICE_FREE) then
      begin
        Result := nil;
        Exit;
      end;

      Dec(pos);                         //得到之前的片
      if pos < 0 then
        Inc(pos, NR_SLICES);
      Result := FSlices[pos];
    end;
  end
  else                                  //新片？
  begin
    if (FNego.DmcMode = DMC_STREAM)
      and (sliceNo <> FCurrentSlice.SliceNo) then
    begin
      FCurrentSlice := FSlices[0];
      assert(FCurrentSlice <> nil);
      FCurrentSlice.Init(sliceNo, FCurrentSlice.Base);
      Result := FCurrentSlice;
      Exit;
    end;

    //片不连续？
    while (sliceNo > FReceivedSliceNo + 2)
      or (sliceNo <> FCurrentSlice.SliceNo + 1) do
    begin
      Slice := FindSlice(FReceivedSliceNo + 1);
      if LongBool(FNego.DmcMode and (DMC_ASYNC or DMC_FEC)) then //IgnoreLostData
      begin
        assert(Slice <> nil);
        assert(Slice.State <> SLICE_DONE);
        Slice.FakeComplete();
      end
      else
      begin
{$IFDEF DMC_FATAL_ON}
        OutLog2(llFatal, Format('Dropped by server now = %d last = %d',
          [sliceNo, FReceivedSliceNo]));
{$ENDIF}
        //{$IFDEF DMC_DEBUG_ON}
        //        if (Slice <> nil) then
        //          PrintMissedBlockMap(clst, slice);
        //{$ENDIF}
        //有数据丢失，终止传输
        FNego.TransState := tsExcept;
        Exit;
      end;
    end;
    //新片
    Result := MakeSlice(sliceNo);
  end;
end;

{ TFecDecode }

//constructor TFecDecode.Create(Config: PNetConfig; Stats: ITransStats);
//begin
//
//end;
//
//destructor TFecDecode.Destroy;
//begin
//
//  inherited;
//end;
//
//procedure TFecDecode.Execute;
//var
//  i, pos, stripe    : Integer;
//  Slice             : TSlice;
//  fecDescs          : PFecDescs;
//begin
//  assert(FConfig^.blockSize <> 0);
//  assert(FDp.DataBufSize mod FConfig^.blockSize = 0);
//
//  while (clst - > endReached < 2) do begin
//    FFecDataPC.Consume(1);
//    pos := FFecDataPC.GetConsumerPosition();
//    Slice := FFec_slices[pos];
//    FFecDataPC.Consumed(1);
//    if (Slice.State <> SLICE_FEC) and
//      (Slice.State <> SLICE_DONE) then
//      {* This can happen if a SLICE_DONE was enqueued after a SLICE_FEC:
//       * the cleanup after SLICE_FEC also cleaned away the SLICE_DONE (in
//       * main queue), and thus we will find it as SLICE_FREE in the
//       * fec queue. Or worse receiving, or whatever if it made full
//       * circle ... *}
//      Continue;
//
//    if (Slice.State = SLICE_FEC) then begin
//      // record the addresses of FEC blocks
//      for stripe := 0 to Slice.Fec_stripes - 1 do begin
//        fec_decode_one_stripe(clst, slice,
//          stripe,
//          Slice.Bytes,
//          Slice.Fec_stripes,
//          Slice.Fec_blocks[stripe],
//          Slice.Fec_descs);
//      end;
//
//      slice - > state = SLICE_FEC_DONE;
//      for stripe = 0 to Slice.Fec_stripes - 1 do begin
//        assert(Slice.missing_data_blocks[stripe] >= Slice.fec_blocks[stripe]);
//        for i = 0 to Slice.fec_blocks[stripe] - 1 do begin
//          freeBlockSpace(clst, Slice.Fec_descs[stripe + i * stripes].adr);
//          Slice.Fec_descs[stripe + i * stripes].adr = 0;
//        end;
//      end;
//    end else if Slice.State = SLICE_DONE then
//      Slice.State := SLICE_FEC_DONE;
//
//    assert(Slice.State = SLICE_FEC_DONE);
//    FDp.CleanupSlices(SLICE_FEC_DONE);
//  end;
//end;

//------------------------------------------------------------------------------
//    { TReceiver }
//------------------------------------------------------------------------------

constructor TReceiver.Create;
begin
  //inherited Create(True);
end;

destructor TReceiver.Destroy;
begin
  inherited;
end;

procedure TReceiver.Init;
begin
  FDp := Dp;
  FNego := Nego;
  FConfig := @Nego.Config;
  FUSocket := Nego.USocket;
end;

function TReceiver.ProcessReqAck(readySet: PByteArray;
  sliceNo, bytes, rxmit: Integer): Integer;
var
  Slice             : TSlice;
begin
  Result := 0;
{$IFDEF DEBUG}
  flprintf('Received REQACK (sn=%d, rxmit=%d sz=%d)',
    sliceNo, rxmit, bytes);
{$ENDIF}

  if (BIT_ISSET(FNego.ClientID, readySet)) then
  begin
    // not for us
{$IFDEF DEBUG}
    flprintf('Not for us');
{$ENDIF}
    Exit;
  end;

  Slice := FDp.FindSlice(sliceNo);
  if Slice = nil then
  begin
    // an old slice = > send ok
{$IFDEF DEBUG}
    flprintf('old slice => sending ok');
{$ENDIF}
    Result := TSlice.SendOk(FUSocket, sliceNo);
  end
  else
  begin
    Result := Slice.CheckComplete(bytes);
    if Result < 0 then
      Exit;                             //error
    if LongBool(Result) then            //完成
      Result := TSlice.SendOk(FUSocket, Slice.SliceNo)
    else
      Result := Slice.SendRetransmit(rxmit);
  end;
end;

procedure TReceiver.Execute;
var
  len               : Integer;

  dataMsg           : TServerDataMsg;
  msg               : TNetMsg;
  Slice             : TSlice;
begin
  //setup messages
  msg.head.base := @dataMsg;
  msg.head.len := sizeof(dataMsg);
  msg.data.len := FConfig^.blockSize;

  while FNego.TransState in [tsTransing, tsNego] do
  begin
    if (FDp.CurrentSlice <> nil)
      and (FDp.CurrentSlice.FreePos < MAX_SLICE_SIZE) then
    begin
      msg.data.base := FDp.CurrentSlice.GetBlockBase(
        FDp.CurrentSlice.FreePos);
    end
    else                                //StreamMode First Slice  or  FEC
      msg.data.base := FDp.NextBlock;

    len := FUSocket.RecvDataMsg(msg);

    if len < 0 then
    begin
{$IFDEF DMC_ERROR_ON}
      OutLog2(llError, Format('RecvDataMsg error! %d', [GetLastError]));
{$ENDIF}
      Break;
    end
    else if len = 0 then                //可疑数据?
      Continue;

    case TOpCode(ntohs(dataMsg.opCode)) of
      CMD_DATA:
        begin
          if FNego.TransState <> tsTransing then //接收到第一块数据
            FNego.TransState := tsTransing;

          Slice := FDp.FindSlice(ntohl(dataMsg.dataBlock.sliceNo));
          if Slice <> nil then
            if Slice.ProcessDataBlock(msg.data.base,
              ntohs(dataMsg.dataBlock.blockNo),
              ntohl(dataMsg.dataBlock.bytes)) < 0 then
              Break;
        end;
{$IFDEF BB_FEATURE_UDPCAST_FEC}
      CMD_FEC:
        begin
          if FNego.TransState = tsNego then //接收到第一块数据
            FNego.TransState := tsTransing;

          if ProcessFecBlock(ntohs(dataMsg.fecBlock.stripes),
            ntohl(dataMsg.fecBlock.sliceNo),
            ntohs(dataMsg.fecBlock.blockNo),
            ntohl(dataMsg.fecBlock.bytes)) < 0 then
            Break;
        end;
{$ENDIF}
      CMD_REQACK:
        begin
          if ProcessReqAck(msg.data.base,
            ntohl(dataMsg.reqack.sliceNo),
            ntohl(dataMsg.reqack.bytes),
            ntohl(dataMsg.reqack.rxmit)) < 0 then
            Break;
        end;
      CMD_HELLO_STREAMING,
        CMD_HELLO_NEW,
        CMD_HELLO: ;                    //retransmission of hello to find other participants ==> ignore
{$IFDEF DMC_WARN_ON}
    else
      OutLog2(llWarn, Format('Unexpected command %-.4x',
        [ntohs(dataMsg.opCode)]));
{$ENDIF}
    end;
  end;                                  // end while

  //传输完成信号 来自Slice.Bytes = 0
  FNego.SendDisconnect;
end;

procedure TReceiver.Terminate;
begin
  FNego.TransState := tsStop;
end;

end.

