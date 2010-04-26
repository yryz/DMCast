unit Participants_u;

interface
uses
  Windows, Sysutils, WinSock, Config_u, Func_u;

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
  public
    constructor Create();
    destructor Destroy; override;

    function IsValid(i: Integer): Boolean;
    function Remove(i: Integer): Boolean; //is safe remove
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
  if (i >= 0) then begin
    Result := i;
    Exit;
  end;

  for i := 0 to MAX_CLIENTS - 1 do
  begin
    if (not FClientTable[i].used) then
    begin
      FClientTable[i].addr := addr^;
      FClientTable[i].used := True;
      FClientTable[i].capabilities := capabilities;
      FClientTable[i].rcvbuf := rcvbuf;
      Inc(FCount);
{$IFDEF CONSOLE}
      WriteLn(Format('New connection from %s  (#%d) [Capabilities %-.8x]',
        [inet_ntoa(addr^.sin_addr), i, capabilities]));
{$ELSE}

{$ENDIF}
{$IFDEF USE_SYSLOG }
      syslog(LOG_INFO, 'New connection from %s  (#%d)',
        getIpString(addr, ipBuffer), i);
{$ENDIF}
      Result := i;
      Exit;
    end else if (pointopoint) then
      Break;
  end;
  Result := -1;                         {no space left in participant's table}
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
  for i := 0 to MAX_CLIENTS - 1 do
  begin
    if FClientTable[i].used and
      (FClientTable[i].addr.sin_addr.S_addr = addr.sin_addr.S_addr) then begin
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
    FClientTable[i].used := False;
    Dec(FCount);
{$IFDEF CONSOLE}
    WriteLn(Format('Disconnecting #%d (%s)',
      [i, inet_ntoa(FClientTable[i].addr.sin_addr)]));
{$ELSE}
{$ENDIF}
  end;
end;

end.
