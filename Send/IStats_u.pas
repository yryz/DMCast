unit IStats_u;

interface
uses
  Windows, Sysutils, Messages, WinSock,
  Config_u, Func_u;

type
  ISenderStats = interface
    ['{20100423-0503-0000-0000-000000000001}']
    procedure BeginTrans();
    procedure EndTrans();
    procedure AddBytes(bytes: Integer);
    procedure AddRetrans(nrRetrans: Integer);
  end;

function CreateSenderStatsObject(config: PNetConfig; statPeriod: Integer): ISenderStats;
implementation
uses
  Stats_u;

function CreateSenderStatsObject;
begin
  Result := TSenderStats.Create(config, statPeriod);
end;

end.

