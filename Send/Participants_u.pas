{$INCLUDE def.inc}

unit Participants_u;

interface
uses
  Windows, Sysutils, WinSock, Func_u, IStats_u;

const
  MAX_CLIENTS       = 512;              //允许最大客户端，极限1456 * 8

type
  PClientDesc = ^TClientDesc;
  TClientDesc = packed record
    addr: TSockAddrIn;
    used: Boolean;
    capabilities: Integer;
    rcvbuf: DWORD_PTR;
  end;

  PClientTable = ^TClientTable;
  TClientTable = array[0..MAX_CLIENTS - 1] of TClientDesc;

  TParticipants = class
  private
    FCount: Integer;
    FClientTable: TClientTable;
    FPartsStats: IPartsStats;
  public
    constructor Create;
    destructor Destroy; override;

    function IsValid(i: Integer): Boolean;
    function Remove(i: Integer): Boolean; //is safe remove
    function Clear(): Integer;
    function Lookup(addr: PSockAddrIn): Integer;
    function Add(addr: PSockAddrIn; capabilities: Integer; rcvbuf: DWORD_PTR;
      pointopoint: Boolean): Integer;
    function GetClientDesc(i: Integer): PClientDesc;
    function GetCapabilities(i: Integer): Integer;
    function GetRcvBuf(i: Integer): DWORD_PTR;
    function GetAddr(i: Integer): PSockAddrIn;
    procedure PrintNotSet(d: PByteArray);
    procedure PrintSet(d: PByteArray);
  published
    property Count: Integer read FCount;
    property PartsStats: IPartsStats read FPartsStats write FPartsStats;
  end;

implementation

{ TParticipants }

constructor TParticipants.Create;
begin
end;

destructor TParticipants.Destroy;
begin
  inherited;
end;

function TParticipants.Add(addr: PSockAddrIn; capabilities: Integer;
  rcvbuf: DWORD_PTR; pointopoint: Boolean): Integer;
var
  i                 : Integer;
begin
  i := Lookup(addr);
  Result := i;
  if i >= 0 then
    Exit;

  for i := 0 to High(FClientTable) do
  begin
    if not FClientTable[i].used then
    begin
      if Assigned(FPartsStats) then
        if not FPartsStats.Add(i, addr, rcvbuf) then
          Exit;

      FClientTable[i].addr := addr^;
      FClientTable[i].used := True;
      FClientTable[i].capabilities := capabilities;
      FClientTable[i].rcvbuf := rcvbuf;
      Inc(FCount);
{$IFDEF CONSOLE}
      WriteLn(Format('New connection from %s  (#%d) [Capabilities %-.8x]',
        [inet_ntoa(addr^.sin_addr), i, capabilities]));
{$ENDIF}

      Result := i;
      Exit;
    end
    else if (pointopoint) then
      Break;
  end;
end;

function TParticipants.GetClientDesc(i: Integer): PClientDesc;
begin
  Result := @FClientTable[i];
end;

function TParticipants.GetCapabilities(i: Integer): Integer;
begin
  Result := FClientTable[i].capabilities;
end;

function TParticipants.GetAddr(i: Integer): PSockAddrIn;
begin
  Result := @FClientTable[i].addr;
end;

function TParticipants.GetRcvBuf(i: Integer): DWORD_PTR;
begin
  Result := FClientTable[i].rcvbuf;
end;

function TParticipants.IsValid(i: Integer): Boolean;
begin
  Result := (i >= Low(FClientTable)) and (i <= High(FClientTable))
    and FClientTable[i].used;
end;

function TParticipants.Lookup(addr: PSockAddrIn): Integer;
var
  i                 : Integer;
begin
  Result := -1;
  for i := 0 to High(FClientTable) do
  begin
    if FClientTable[i].used and
      (FClientTable[i].addr.sin_addr.S_addr = addr.sin_addr.S_addr) then
    begin
      Result := i;
      Break;
    end;
  end;
end;

procedure TParticipants.PrintNotSet(d: PByteArray);
var
  i                 : Integer;
  first             : Boolean;
begin
{$IFDEF CONSOLE}
  first := True;
  Write('[');
  for i := 0 to MAX_CLIENTS - 1 do
  begin
    if (FClientTable[i].used) then
    begin
      if not BIT_ISSET(i, d) then
      begin
        if (not first) then
          Write(',');
        first := False;
        Write(i);
      end;
    end;
  end;
  Write(']');
{$ENDIF}
end;

procedure TParticipants.PrintSet(d: PByteArray);
var
  i                 : Integer;
  first             : Boolean;
begin
{$IFDEF CONSOLE}
  first := True;
  Write('[');
  for i := 0 to MAX_CLIENTS - 1 do
  begin
    if (FClientTable[i].used) then
    begin
      if BIT_ISSET(i, d) then
      begin
        if (not first) then
          Write(',');
        first := False;
        Write(i);
      end;
    end;
  end;
  Write(']');
{$ENDIF}
end;

function TParticipants.Remove(i: Integer): Boolean;
begin
  Result := IsValid(i);
  if Result then
  begin
    if Assigned(FPartsStats) then
      Result := FPartsStats.Remove(i, @FClientTable[i].addr);

    if Result then
    begin
      FClientTable[i].used := False;
      Dec(FCount);
{$IFDEF CONSOLE}
      WriteLn(Format('Disconnecting #%d (%s)',
        [i, inet_ntoa(FClientTable[i].addr.sin_addr)]));
{$ENDIF}
    end;
  end;
end;

function TParticipants.Clear: Integer;
var
  i                 : Integer;
begin
  { remove all participants }
  Result := 0;
  for i := 0 to High(FClientTable) do
    if Remove(i) then
      Inc(Result);
end;

end.

