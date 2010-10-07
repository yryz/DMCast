unit IStats_u;

interface
uses
  Windows, Sysutils, Messages, WinSock;

type
  { Sender/Receiver 传输状态统计 }

  TTransState = (tsStop, tsNego, tsTransing, tsComplete, tsExcept);

  ITransStats = interface
    //tCreate   tChange        nID
    ['{20100608-2010-1005-2212-001E68AD5693}']
    //传输状态更改
    procedure TransStateChange(TransState: TTransState);
    //当前传输状态
    function TransState: TTransState;
    //成功传输片大小
    procedure AddBytes(bytes: Integer);
  end;

  { Sender }
  ISenderStats = interface(ITransStats)
    //重传块数
    procedure AddRetrans(nrRetrans: Integer);
  end;

  { Reciever }
  IReceiverStats = interface(ITransStats)
  end;

  { Sender 成员变更 }
  IPartsStats = interface
    ['{20100930-1049-0000-0000-000000000001}']
    function Add(index: Integer; addr: PSockAddrIn; sockBuf: Integer): Boolean;
    function Remove(index: Integer; addr: PSockAddrIn): Boolean;
    function GetNrOnline(): Integer;
  end;

implementation

end.

