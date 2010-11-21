
{$IFDEF NO_DLL}
uses
  DMCSender_u;
{$ELSE}
const
  DMC_SENDER_DLL    = 'DMCSender.dll';

  //���Ĭ������

procedure DMCConfigFill(var config: TSendConfig); stdcall;
  external DMC_SENDER_DLL;

//�����Ự  OnTransStateChange,OnPartsChange ��ѡ

function DMCNegoCreate(config: PSendConfig;
  OnTransStateChange: TOnTransStateChange;
  OnPartsChange: TOnPartsChange;
  var lpFifo: Pointer): Pointer; stdcall;
  external DMC_SENDER_DLL;

//�����Ự(�ź�,�첽)

function DMCNegoDestroy(lpNego: Pointer): Boolean; stdcall;
  external DMC_SENDER_DLL;

//�ȴ���������д

function DMCDataWriteWait(lpFifo: Pointer; var dwBytes: DWORD): Pointer; stdcall;
  external DMC_SENDER_DLL;

//�����������

function DMCDataWrited(lpFifo: Pointer; dwBytes: DWORD): Boolean; stdcall;
  external DMC_SENDER_DLL;

//��ʼ/��ͣ����(�ź�)

function DMCTransferCtrl(lpNego: Pointer; isGo: Boolean): Boolean; stdcall;
  external DMC_SENDER_DLL;

//ͳ��Ƭ��С

function DMCStatsSliceSize(lpNego: Pointer): Integer; stdcall;
  external DMC_SENDER_DLL;

//ͳ���Ѿ�����Bytes

function DMCStatsTotalBytes(lpNego: Pointer): Int64; stdcall;
  external DMC_SENDER_DLL;

//ͳ���ش�Blocks(��)

function DMCStatsBlockRetrans(lpNego: Pointer): Int64; stdcall;
  external DMC_SENDER_DLL;

{$ENDIF}
