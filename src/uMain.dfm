object frmMain: TfrmMain
  Left = 0
  Top = 0
  BorderIcons = [biSystemMenu]
  BorderStyle = bsSingle
  Caption = 'MultiThreaded Directory and File Count'
  ClientHeight = 137
  ClientWidth = 337
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OnCloseQuery = FormCloseQuery
  OnCreate = FormCreate
  TextHeight = 13
  object GroupBox1: TGroupBox
    Left = 8
    Top = 8
    Width = 323
    Height = 121
    TabOrder = 0
    object lblDCount: TLabel
      Left = 16
      Top = 13
      Width = 304
      Height = 13
      AutoSize = False
      Caption = 'Directory Count: 0'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Tahoma'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lblFCount: TLabel
      Left = 16
      Top = 32
      Width = 297
      Height = 13
      AutoSize = False
      Caption = 'File Count: 0'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Tahoma'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object lblTCount: TLabel
      Left = 16
      Top = 51
      Width = 304
      Height = 13
      AutoSize = False
      Caption = 'Total Count: 0'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -11
      Font.Name = 'Tahoma'
      Font.Style = [fsBold]
      ParentFont = False
    end
    object Label1: TLabel
      Left = 11
      Top = 91
      Width = 22
      Height = 13
      Caption = 'Path'
    end
    object cmdThread: TButton
      Left = 238
      Top = 88
      Width = 75
      Height = 25
      Caption = 'Enable'
      TabOrder = 0
      OnClick = cmdThreadClick
    end
    object txtPath: TEdit
      Left = 39
      Top = 88
      Width = 194
      Height = 21
      ReadOnly = True
      TabOrder = 1
    end
    object cmdSelect: TButton
      Left = 215
      Top = 90
      Width = 17
      Height = 18
      TabOrder = 2
      OnClick = cmdSelectClick
    end
  end
end
