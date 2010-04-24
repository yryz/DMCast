unit UCastSender_u;

interface

uses
  Windows, Messages, SysUtils, WinSock,
  Config_u, Protoc_u, INegotiate_u, IStats_u;


function RunSender(const FileName: string): Boolean;
implementation

function RunSender(const FileName: string): Boolean;
var
  config            : TNetConfig;
  Nego              : INegotiate;
  Stats             : ISenderStats;
begin
  FillChar(config, SizeOf(config), 0);

  config.ifName := 'eth0';              //eht0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
  config.fileName := PChar(FileName);

{$IFDEF CONSOLE}
  config.flags := 0;
{$ELSE}
  config.flags := FLAG_NOKBD;           //没有控制台!
{$ENDIF}
  config.mcastRdv := nil;               //传输地址
  config.blockSize := 1456;             //这个值在一些情况下（如家用无线），设置大点效果会好些如10K
  config.sliceSize := 16;
  config.portBase := 9000;
  config.nrGovernors := 0;
  config.flags := 0;
  config.capabilities := 0;
  config.min_slice_size := 16;
  config.max_slice_size := MAX_SLICE_SIZE;
  config.default_slice_size := 0;
  config.ttl := 1;
  config.rexmit_hello_interval := 0;    //retransmit hello message
  config.autostart := 0;
  config.requestedBufSize := 0;

  config.min_receivers := 0;
  config.max_receivers_wait := 0;
  config.min_receivers_wait := 0;
  config.startTimeout := 0;

  config.retriesUntilDrop := 20;        //sendReqack片重试次数 （原 200）
  config.rehelloOffset := 50;

  //Writeln(SizeOf(config));
  Stats := CreateSenderStatsObject(@config, DEFLT_STAT_PERIOD);
  Nego := CreateNegotiateObject(@config, Stats);

  if Nego.StartNegotiate > 0 then
    Nego.DoTransfer;
end;


end.

