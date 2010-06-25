unit UCastReceiver_u;

interface

uses
  Windows, Messages, SysUtils, WinSock, Stats_u,
  Config_u, Protoc_u, INegotiate_u, IStats_u;


function RunReceiver(const FileName: string): Boolean;
implementation

function RunReceiver(const FileName: string): Boolean;
var
  config            : TNetConfig;
  Nego              : INegotiate;
  Stats             : ITransStats;
begin
  FillChar(config, SizeOf(config), 0);

  config.ifName := 'eth0';              //eht0 or 192.168.0.1 or 00-24-1D-99-64-D5 or nil
  config.fileName := PAnsiChar(FileName);   

  config.mcastRdv := nil;               //传输地址
  config.blockSize := 1456;             //这个值在一些情况下（如家用无线），设置大点效果会好些如10K
  config.localPort := 8090;
  config.remotePort := 9080;

  config.flags := [];
  config.capabilities := 0;
  config.ttl := 1;
  config.requestedBufSize := 0;

  //Writeln(SizeOf(config));
  Stats := TReceiverStats.Create(@config, DEFLT_STAT_PERIOD);
  Nego := CreateNegotiateObject(@config, Stats);

  if Nego.StartNegotiate > 0 then
    Nego.DoTransfer;
end;


end.

