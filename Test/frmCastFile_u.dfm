object frmCastFile: TfrmCastFile
  Left = 216
  Top = 137
  Width = 645
  Height = 398
  Caption = #25991#20214#22810#25773' v1.0a'
  Color = clBtnFace
  Font.Charset = ANSI_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = #23435#20307
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnClose = FormClose
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 12
  object stat1: TStatusBar
    Left = 0
    Top = 345
    Width = 637
    Height = 19
    Panels = <
      item
        Width = 50
      end>
  end
  object lvClient: TListView
    Left = 0
    Top = 74
    Width = 312
    Height = 271
    Align = alClient
    Columns = <
      item
        Caption = 'ID'
      end
      item
        Caption = #23458#25143#31471
        Width = 110
      end
      item
        Caption = 'SOCKET'#32531#20914
        Width = 80
      end>
    LargeImages = ImageList1
    ReadOnly = True
    RowSelect = True
    SmallImages = ImageList1
    TabOrder = 1
    ViewStyle = vsReport
  end
  object Panel1: TPanel
    Left = 0
    Top = 0
    Width = 637
    Height = 56
    Align = alTop
    BevelOuter = bvNone
    ParentBackground = False
    TabOrder = 0
    object Label1: TLabel
      Left = 11
      Top = 19
      Width = 32
      Height = 13
      Alignment = taRightJustify
      AutoSize = False
      Caption = #25991#20214
    end
    object SpeedButton1: TSpeedButton
      Left = 240
      Top = 16
      Width = 23
      Height = 22
      Caption = '...'
      OnClick = SpeedButton1Click
    end
    object lbl8: TLabel
      Left = 552
      Top = 21
      Width = 42
      Height = 12
      Cursor = crHandPoint
      Caption = 'HouSoft'
      Font.Charset = ANSI_CHARSET
      Font.Color = clBlue
      Font.Height = -12
      Font.Name = #23435#20307
      Font.Style = [fsUnderline]
      ParentFont = False
      OnClick = lbl8Click
    end
    object edtFile: TEdit
      Left = 48
      Top = 16
      Width = 180
      Height = 20
      ImeName = #20013#25991' ('#31616#20307') - '#32654#24335#38190#30424
      TabOrder = 0
    end
    object btnTrans: TButton
      Left = 336
      Top = 16
      Width = 51
      Height = 22
      Caption = #20256#36755
      Enabled = False
      TabOrder = 2
      OnClick = btnTransClick
    end
    object btnStart: TButton
      Left = 272
      Top = 16
      Width = 51
      Height = 22
      Caption = #24320#22987
      TabOrder = 1
      OnClick = btnStartClick
    end
    object btnStop: TButton
      Left = 400
      Top = 16
      Width = 51
      Height = 22
      Caption = #20572#27490
      Enabled = False
      TabOrder = 3
      OnClick = btnStopClick
    end
    object chkLoopStart: TCheckBox
      Left = 464
      Top = 18
      Width = 82
      Height = 17
      Caption = #24490#29615#21551#21160
      TabOrder = 4
    end
  end
  object pnl1: TPanel
    Left = 312
    Top = 74
    Width = 325
    Height = 271
    Align = alRight
    BevelOuter = bvNone
    ParentBackground = False
    TabOrder = 2
    object grp1: TGroupBox
      Left = 0
      Top = 0
      Width = 325
      Height = 108
      Align = alTop
      Caption = #29366#24577
      TabOrder = 0
      object lbl1: TLabel
        Left = 160
        Top = 24
        Width = 64
        Height = 13
        Alignment = taRightJustify
        AutoSize = False
        Caption = #24050#32463#20256#36755':'
        Transparent = True
      end
      object lbl2: TLabel
        Left = 8
        Top = 49
        Width = 64
        Height = 13
        Alignment = taRightJustify
        AutoSize = False
        Caption = #20256#36755#36895#24230':'
        Transparent = True
      end
      object lbl3: TLabel
        Left = 160
        Top = 75
        Width = 64
        Height = 13
        Alignment = taRightJustify
        AutoSize = False
        Caption = #37325#20256#22359#25968':'
        Transparent = True
      end
      object lbl4: TLabel
        Left = 8
        Top = 75
        Width = 64
        Height = 13
        Alignment = taRightJustify
        AutoSize = False
        Caption = #29255#22823#23567':'
        Transparent = True
      end
      object lblSliceSize: TLabel
        Left = 79
        Top = 75
        Width = 80
        Height = 13
        AutoSize = False
        Caption = '0'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGreen
        Font.Height = -11
        Font.Name = 'MS Sans Serif'
        Font.Style = []
        ParentFont = False
        Transparent = True
      end
      object lblRexmit: TLabel
        Left = 231
        Top = 75
        Width = 80
        Height = 13
        AutoSize = False
        Caption = '0'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clRed
        Font.Height = -11
        Font.Name = 'MS Sans Serif'
        Font.Style = []
        ParentFont = False
        Transparent = True
      end
      object lblSpeed: TLabel
        Left = 79
        Top = 49
        Width = 80
        Height = 13
        AutoSize = False
        Caption = '0'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGreen
        Font.Height = -11
        Font.Name = 'MS Sans Serif'
        Font.Style = []
        ParentFont = False
        Transparent = True
      end
      object lblTransBytes: TLabel
        Left = 231
        Top = 24
        Width = 80
        Height = 13
        AutoSize = False
        Caption = '0'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGreen
        Font.Height = -11
        Font.Name = 'MS Sans Serif'
        Font.Style = []
        ParentFont = False
        Transparent = True
      end
      object lblFile: TLabel
        Left = 8
        Top = 24
        Width = 64
        Height = 13
        Alignment = taRightJustify
        AutoSize = False
        Caption = #25991#20214#22823#23567':'
        Transparent = True
      end
      object lblFileSize: TLabel
        Left = 79
        Top = 24
        Width = 80
        Height = 13
        AutoSize = False
        Caption = '0'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGreen
        Font.Height = -11
        Font.Name = 'MS Sans Serif'
        Font.Style = []
        ParentFont = False
        Transparent = True
      end
      object lbl12: TLabel
        Left = 160
        Top = 49
        Width = 64
        Height = 13
        Alignment = taRightJustify
        AutoSize = False
        Caption = #24050#29992#26102#38388':'
        Transparent = True
      end
      object lblTotalTime: TLabel
        Left = 231
        Top = 49
        Width = 80
        Height = 13
        AutoSize = False
        Caption = '0'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clGreen
        Font.Height = -11
        Font.Name = 'MS Sans Serif'
        Font.Style = []
        ParentFont = False
        Transparent = True
      end
    end
    object grp2: TGroupBox
      Left = 0
      Top = 108
      Width = 325
      Height = 163
      Align = alClient
      Caption = #35774#32622
      TabOrder = 1
      object lbl5: TLabel
        Left = 6
        Top = 59
        Width = 75
        Height = 13
        Alignment = taRightJustify
        AutoSize = False
        Caption = #21021#22987#29255#22823#23567':'
        Transparent = True
      end
      object lbl7: TLabel
        Left = 6
        Top = 90
        Width = 75
        Height = 13
        Alignment = taRightJustify
        AutoSize = False
        Caption = #36229#26102#37325#35797#27425':'
        Transparent = True
      end
      object lbl10: TLabel
        Left = 144
        Top = 90
        Width = 98
        Height = 13
        Alignment = taRightJustify
        AutoSize = False
        Caption = #20256#36755#36895#29575'(KB/s):'
        Transparent = True
      end
      object lbl11: TLabel
        Left = 6
        Top = 27
        Width = 75
        Height = 13
        Alignment = taRightJustify
        AutoSize = False
        Caption = #20256#36755#30340#25509#21475':'
        Transparent = True
      end
      object chkAutoSliceSize: TCheckBox
        Left = 153
        Top = 57
        Width = 121
        Height = 17
        Caption = #21160#24577#35843#25972#29255#22823#23567
        TabOrder = 0
      end
      object seSliceSize: TSpinEdit
        Left = 88
        Top = 55
        Width = 49
        Height = 21
        Hint = '0 '#20351#29992#40664#35748
        MaxLength = 4
        MaxValue = 1024
        MinValue = 0
        ParentShowHint = False
        ShowHint = True
        TabOrder = 1
        Value = 0
      end
      object grp4: TGroupBox
        Left = 2
        Top = 117
        Width = 321
        Height = 44
        Align = alBottom
        Caption = #33258#21160#24320#22987
        TabOrder = 2
        object lbl6: TLabel
          Left = 4
          Top = 20
          Width = 75
          Height = 13
          Alignment = taRightJustify
          AutoSize = False
          Caption = #31561#24453#23458#25143#25968':'
          Transparent = True
        end
        object lbl9: TLabel
          Left = 150
          Top = 20
          Width = 90
          Height = 13
          Alignment = taRightJustify
          AutoSize = False
          Caption = #26368#22823#31561#24453'('#31186'):'
          Transparent = True
        end
        object seWaitReceivers: TSpinEdit
          Left = 86
          Top = 16
          Width = 49
          Height = 21
          Hint = #31561#24453#23458#25143#25968#65292'0 '#24573#30053
          MaxLength = 4
          MaxValue = 1024
          MinValue = 0
          ParentShowHint = False
          ShowHint = True
          TabOrder = 0
          Value = 0
        end
        object seMaxWait: TSpinEdit
          Left = 246
          Top = 16
          Width = 60
          Height = 21
          Hint = #26377#19968#20010#23458#25143#31471#21518','#20877#31561#24453#22810#38271#26102#38388#12290'0 '#24573#30053
          MaxValue = 0
          MinValue = 0
          ParentShowHint = False
          ShowHint = True
          TabOrder = 1
          Value = 0
        end
      end
      object chkStreamMode: TCheckBox
        Left = 228
        Top = 25
        Width = 89
        Height = 17
        Hint = #20801#35768#25509#25910#22120#21152#20837#19968#20010#27491#22312#36827#34892#30340#20256#36755
        Caption = #24320#21551#27969#27169#24335
        ParentShowHint = False
        ShowHint = True
        TabOrder = 3
      end
      object seRetriesUntilDrop: TSpinEdit
        Left = 88
        Top = 86
        Width = 49
        Height = 21
        MaxLength = 4
        MaxValue = 9999
        MinValue = 10
        ParentShowHint = False
        ShowHint = True
        TabOrder = 4
        Value = 30
        OnChange = SpinEditChange
      end
      object seXmitRate: TSpinEdit
        Left = 248
        Top = 86
        Width = 60
        Height = 21
        Hint = '0 '#19981#38480#36895
        MaxValue = 0
        MinValue = 0
        ParentShowHint = False
        ShowHint = True
        TabOrder = 5
        Value = 0
        OnChange = SpinEditChange
      end
      object cbbInterface: TComboBox
        Left = 88
        Top = 23
        Width = 124
        Height = 20
        Style = csDropDownList
        ImeName = #20013#25991' ('#31616#20307') - '#32654#24335#38190#30424
        ItemHeight = 12
        ParentShowHint = False
        ShowHint = False
        TabOrder = 6
      end
    end
  end
  object pb1: TProgressBar
    Left = 0
    Top = 56
    Width = 637
    Height = 18
    Align = alTop
    ParentShowHint = False
    ShowHint = True
    TabOrder = 4
  end
  object dlgOpen1: TOpenDialog
    Left = 136
    Top = 128
  end
  object XPManifest1: TXPManifest
    Left = 104
    Top = 128
  end
  object ImageList1: TImageList
    Left = 56
    Top = 136
    Bitmap = {
      494C010102000300040010001000FFFFFFFFFF10FFFFFFFFFFFFFFFF424D3600
      0000000000003600000028000000400000001000000001002000000000000010
      000000000000000000000000000000000000FFFFFFFFFCFCFCFFF2F2F2FFE8E8
      E8FFE4E4E4FFE4E4E4FFE4E4E4FFE4E4E4FFE4E4E4FFE4E4E4FFE4E4E4FFE4E4
      E4FFE8E8E8FFF2F2F2FFFCFCFCFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000FFFFFFFFFAFAFAFFE8E8E8FFD4D4
      D4FFBAC1BAFF7FA07EFF559054FF3B813AFF3B813AFF559054FF7FA07EFFBAC1
      BAFFD2D2D2FFE6E6E6FFFAFAFAFFFFFFFFFFFFFFFFFFF0F0F0FFEAEAEAFFE6E6
      E6FFE4E4E4FFE8E8E8FFECECECFFF0F0F0FFF0F0F0FFEEEEEEFFEAEAEAFFE6E6
      E6FFE6E6E6FFEAEAEAFFF0F0F0FFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFB3CB
      B2FF459641FF2CA723FF25C617FF22D512FF22D512FF25C617FF2CA723FF4596
      41FFB3CBB2FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE2E2E2FFD8D8D8FF9A9A
      AEFF32327EFF9E9EB1FFDADADAFFE2E2E2FFE4E4E4FFDEDEDEFFA0A0B3FF3232
      7EFF9A9AAEFFD8D8D8FFE2E2E2FFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000FFFFFFFFFFFFFFFFB5D8B2FF3D9F
      35FF27C518FF23D112FF22B611FF22D111FF22D111FF22D111FF22D111FF25C4
      16FF3C9F34FFB5D8B2FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFB6B6CEFF3232
      8DFF1111D8FF32328DFFB6B6CEFFFFFFFFFFFFFFFFFFB6B6CEFF32328DFF1111
      D8FF32328DFFB6B6CEFFFFFFFFFFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000FFFFFFFFE5F2E4FF4BA742FF2DC1
      1EFF23C812FF22B211FFE6E6E6FF22B211FF22C811FF22C811FF22C811FF22C8
      11FF26BE16FF4AA641FFE5F2E4FFFFFFFFFFFFFFFFFFFFFFFFFF32329AFF1111
      D0FF1111D0FF1111D0FF32329AFFB6B6DBFFB6B6DBFF32329AFF1111D0FF1111
      D0FF1111D0FF32329AFFFFFFFFFFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000FFFFFFFF97CC92FF3AB12CFF26C0
      15FF22AD11FFDEDEDEFFE2E2E2FFE6E6E6FF22B311FF22BE11FF22BE11FF22BE
      11FF22BE11FF30AC24FF97CC92FFFFFFFFFFFFFFFFFFFFFFFFFFB6B6DCFF3232
      9EFF1111C4FF1111C4FF1111C4FF32329EFF32329EFF1111C4FF1111C4FF1111
      C4FF32329EFFB6B6DCFFFFFFFFFFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000FFFFFFFF61B458FF42BF33FF23AE
      12FFD5D5D5FFDADADAFFDEDEDEFFE2E2E2FFC0D8BDFF22AE11FF22B411FF22B4
      11FF22B411FF29B21AFF61B458FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFB6B6
      DEFF3232A3FF1111B8FF1111B8FF1111B8FF1111B8FF1111B8FF1111B8FF3232
      A3FFB6B6DEFFFFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000FFFFFFFF45AA3AFF51C840FF9EDC
      96FFD2D2D2FFD5D5D5FF51B644FFDDDEDDFFE2E2E2FFA6CEA0FF24A813FF22AA
      11FF22AA11FF29AE18FF45AA3AFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFB6B6DFFF3232A7FF1515AFFF1111ACFF1111ACFF1111ACFF3232A7FFB6B6
      DFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000FFFFFFFF46AD3AFF55CB44FF44BB
      33FFFFFFFFFF2EAB1DFF23A212FF51B044FFDEDEDEFFE2E2E2FF87C27FFF22A1
      11FF22A111FF2DAA1CFF46AD3AFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFB6B6E1FF3232ABFF2525B4FF1111A2FF1111A2FF1414A5FF3232ABFFB6B6
      E1FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000FFFFFFFF63BC58FF57CD47FF47BE
      36FF47BE36FF47BE36FF42B931FF36AF25FFAACDA5FFDEDEDEFFE2E2E2FF68B5
      5DFF279F16FF3BB32BFF63BC58FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFB6B6
      E2FF3232AEFF5353DBFF2E2EB7FF3D3DC6FF3131BAFF15159FFF1E1EA7FF3232
      AEFFB6B6E2FFFFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000FFFFFFFF99D592FF52C643FF54CB
      43FF4EC53DFF4EC53DFF4EC53DFF4EC53DFF4EC53DFFD3F1CEFFFFFFFFFFFFFF
      FFFF52C941FF4CBF3CFF99D592FFFFFFFFFFFFFFFFFFFFFFFFFFB6B6E4FF3232
      B2FF6767EFFF3636BEFF5E5EE6FF3232B2FF3232B2FF4F4FD7FF3636BEFF4545
      CDFF3232B2FFB6B6E4FFFFFFFFFFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000FFFFFFFFE6F5E4FF53BD45FF61D8
      50FF59D048FF57CE46FF57CE46FF57CE46FF57CE46FF57CE46FFFFFFFFFF58CF
      47FF5BD34AFF52BC44FFE6F5E4FFFFFFFFFFFFFFFFFFFFFFFFFF3232B5FF7676
      FEFF4C4CD4FF7272FAFF3232B5FFB6B6E4FFB6B6E4FF3232B5FF6262EAFF4C4C
      D4FF5C5CE4FF3232B5FFFFFFFFFFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000FFFFFFFFFFFFFFFFB8E3B2FF4CBE
      3DFF64DB53FF63DA52FF5FD64EFF5FD64EFF5FD64EFF5FD64EFF63DA52FF62D9
      50FF4BBD3CFFB8E3B2FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFB6B6E5FF3232
      B8FF7777FFFF3232B8FFB6B6E5FFFFFFFFFFFFFFFFFFB6B6E5FF3232B8FF7070
      F8FF3232B8FFB6B6E5FFFFFFFFFFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFB8E4
      B2FF54C145FF56CE45FF65DD54FF6CE35BFF6CE35AFF65DD54FF54CD44FF54C1
      45FFB8E4B2FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFB6B6
      E6FF3232BAFFB6B6E6FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFB6B6E6FF3232
      BAFFB6B6E6FFFFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFE6F5E4FF9ADA92FF65C758FF4ABD3AFF4ABD3AFF65C758FF9ADA92FFE6F5
      E4FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000FFFFFF00FFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
      FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000000000000000000000000000424D3E000000000000003E000000
      2800000040000000100000000100010000000000800000000000000000000000
      000000000000000000000000FFFFFF0000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      0000000000000000000000000000000000000000000000000000000000000000
      000000000000}
  end
  object tmrStats: TTimer
    Enabled = False
    OnTimer = tmrStatsTimer
    Left = 80
    Top = 192
  end
end
