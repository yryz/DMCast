unit INegotiate_u;

interface

uses
  Windows, Messages, SysUtils, WinSock, Config_u, Console_u, IStats_u;

type
  TOnPartsChange = function(isAdd: Boolean; index: Integer;
    addr: PSockAddrIn): Boolean of object;

  INegotiate = interface(IInterface)
    ['{20100422-1653-0000-0000-000000000001}']
    function StartNegotiate(): Integer;
    function SendHello(streaming: Boolean): Integer;
    procedure DoTransfer();
    function AbortTransfer(waitTime: DWORD): Boolean;
  end;

function CreateNegotiateObject(config: PNetConfig; Console: TConsole;
  Stats: ITransStats; OnPartsChange: TOnPartsChange): INegotiate;
implementation
uses
  Negotiate_u;

function CreateNegotiateObject(config: PNetConfig; Console: TConsole;
  Stats: ITransStats; OnPartsChange: TOnPartsChange): INegotiate;
begin
  Result := TNegotiate.Create(config, Console, Stats, OnPartsChange);
end;

end.

