
{$IFDEF NO_DLL}
uses
  DMCSender_u;
{$ELSE}
const
  DMC_SENDER_DLL    = 'DMCSender.dll';

  //填充默认配置

procedure DMCConfigFill(var config: TSendConfig); stdcall;
  external DMC_SENDER_DLL;

//创建会话  OnTransStateChange,OnPartsChange 可选

function DMCNegoCreate(config: PSendConfig;
  OnTransStateChange: TOnTransStateChange;
  OnPartsChange: TOnPartsChange;
  var lpFifo: Pointer): Pointer; stdcall;
  external DMC_SENDER_DLL;

//结束会话(信号,异步)

function DMCNegoDestroy(lpNego: Pointer): Boolean; stdcall;
  external DMC_SENDER_DLL;

//等待缓冲区可写

function DMCDataWriteWait(lpFifo: Pointer; var dwBytes: DWORD): Pointer; stdcall;
  external DMC_SENDER_DLL;

//数据生产完成

function DMCDataWrited(lpFifo: Pointer; dwBytes: DWORD): Boolean; stdcall;
  external DMC_SENDER_DLL;

//开始/暂停传输(信号)

function DMCTransferCtrl(lpNego: Pointer; isGo: Boolean): Boolean; stdcall;
  external DMC_SENDER_DLL;

//统计片大小

function DMCStatsSliceSize(lpNego: Pointer): Integer; stdcall;
  external DMC_SENDER_DLL;

//统计已经传输Bytes

function DMCStatsTotalBytes(lpNego: Pointer): Int64; stdcall;
  external DMC_SENDER_DLL;

//统计重传Blocks(块)

function DMCStatsBlockRetrans(lpNego: Pointer): Int64; stdcall;
  external DMC_SENDER_DLL;

{$ENDIF}

