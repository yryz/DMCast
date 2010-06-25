unit INegotiate_u;

interface

uses
  Windows, Messages, SysUtils, Config_u, IStats_u;

type
  INegotiate = interface(IInterface)
    ['{20100422-1653-0000-0000-000000000001}']
    function StartNegotiate(): Integer;
    procedure DoTransfer();
    function AbortTransfer(waitTime: DWORD): Boolean;
  end;

function CreateNegotiateObject(config: PNetConfig; Stats: ITransStats): INegotiate;
implementation
uses
  Negotiate_u;

function CreateNegotiateObject(config: PNetConfig; Stats: ITransStats): INegotiate;
begin
  Result := TNegotiate.Create(config, Stats);
end;

end.
