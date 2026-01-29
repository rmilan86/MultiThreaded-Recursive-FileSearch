program MultiThreaded_Recursive_FileSearch;

uses
  Forms,
  uMain in 'uMain.pas' {frmMain},
  uRecursiveEngine in 'uRecursiveEngine.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
