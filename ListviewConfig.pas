unit ListviewConfig;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, Buttons, CheckLst, myf_consts, FlatButton, XPMenu;

type
  TfrmListViewConfig = class(TForm)
    gb1: TGroupBox;
    clbCols: TCheckListBox;
    btnOk: TFlatButton;
    btnAbort: TFlatButton;
    gbOptions: TGroupBox;
    Label1: TLabel;
    cbSizeFmt: TComboBox;
    procedure FormCreate(Sender: TObject);
  private
    { Private-Deklarationen }
  public
    { Public-Deklarationen }
  end;

var
  frmListViewConfig: TfrmListViewConfig;

implementation

uses Unit1;

{$R *.DFM}
(*
procedure TfrmListViewConfig.btnResetClick(Sender: TObject);
var
  i: integer;
begin
  with MainForm do
  begin
    with ini do
    begin
      for i := 1 to 3 do
        DeleteKey('GUI.ListView.Columns' + IntToStr(i));
      EraseSection('GUI.lvPZip');
      EraseSection('GUI.lvDriveState');
    end;
    CustListView(lvstyle + 64);
  end;
end;*)

procedure TfrmListViewConfig.FormCreate(Sender: TObject);
begin
  MyFiles3Form.GimmeXP(Self);
end;

end.
