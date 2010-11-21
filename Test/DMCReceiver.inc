
{$IFDEF NO_DLL}
uses
  DMCReceiver_u;
{$ELSE}
const
  DMC_RECEIVER_DLL  = 'DMCReceiver.dll';

  //填充默认配置

procedure DMCConfigFill(var config: TRecvConfig); stdcall;
  external DMC_RECEIVER_DLL;

//开始会话  OnTransStateChange 可选

function DMCNegoCreate(config: PRecvConfig; OnTransStateChange: TOnTransStateChange;
  var lpFifo: Pointer): Pointer; stdcall;
  external DMC_RECEIVER_DLL;

//结束会话

function DMCNegoDestroy(lpNego: Pointer): Boolean; stdcall;
  external DMC_RECEIVER_DLL;

//等待数据缓冲区可读

function DMCDataReadWait(lpFifo: Pointer; var dwBytes: DWORD): Pointer; stdcall;
  external DMC_RECEIVER_DLL;

//数据已消耗(以从缓冲区取出)

function DMCDataReaded(lpFifo: Pointer; dwBytes: DWORD): Boolean; stdcall;
  external DMC_RECEIVER_DLL;

//等待会话结束(确保安全断开会话)

function DMCNegoWaitEnded(lpNego: Pointer): Boolean; stdcall;
  external DMC_RECEIVER_DLL;

//统计已经传输Bytes

function DMCStatsTotalBytes(lpNego: Pointer): Int64; stdcall;
  external DMC_RECEIVER_DLL;

{$ENDIF}

