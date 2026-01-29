(************************************************************
     Project: MultiThreaded Recursive FileSearch
     File: uMain.pas
     Author: Robert Milan (https://caporin.com)
     License: GNU General Public License v3.0

     Copyright (c) 2026 Robert Milan (https://caporin.com)

     This program is free software: you can redistribute it and/or modify
     it under the terms of the GNU General Public License as published by
     the Free Software Foundation, either version 3 of the License, or
     (at your option) any later version.

     This program is distributed in the hope that it will be useful,
     but WITHOUT ANY WARRANTY; without even the implied warranty of
     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
     GNU General Public License for more details.

     You should have received a copy of the GNU General Public License
     along with this program.  If not, see <https://www.gnu.org/licenses/>.
************************************************************)





(************************************************************)
(* Module Name : uMain.pas
(* Purpose     : UI-only unit (VCL form)
(*               Calls the multithreaded recursive scan engine
(*               implemented in uRecursiveEngine.
(* Notes       :
(*     - All threading / worker logic removed from this unit
(*     - UI updates occur via engine callbacks (queued to main thread)
(************************************************************)

unit uMain;

interface

uses
     Winapi.Windows,
     Winapi.Messages,

     System.SysUtils,
     System.Classes,
     System.Math,
     System.IOUtils,

     Vcl.Graphics,
     Vcl.Controls,
     Vcl.Forms,
     Vcl.Dialogs,
     Vcl.StdCtrls,
     Vcl.FileCtrl,

     { Engine unit (threading code lives there, not here) }
     uRecursiveEngine;

type
     TfrmMain = class(TForm)
          GroupBox1 : TGroupBox;
          lblDCount : TLabel;
          lblFCount : TLabel;
          lblTCount : TLabel;
          cmdThread : TButton;
          txtPath : TEdit;
          Label1 : TLabel;
          cmdSelect : TButton;

          procedure FormCreate(Sender : TObject);
          procedure FormDestroy(Sender : TObject);
          procedure FormCloseQuery(Sender : TObject; var CanClose : Boolean);
          procedure cmdSelectClick(Sender : TObject);
          procedure cmdThreadClick(Sender : TObject);

     private
          { Engine instance used to perform the scan }
          m_oEngine : TRecursiveEngine;

          { True while a scan is running (UI state flag) }
          m_bScanRunning : Boolean;

          procedure BrowseForFolder;

          procedure HandleProgress(const p_iPendingFolders : Int64;
                                   const p_iDirCount : Int64;
                                   const p_iFileCount : Int64);

          procedure HandleFinished(const p_bCanceled : Boolean;
                                   const p_szLastError : string;
                                   const p_iDirCount : Int64;
                                   const p_iFileCount : Int64);

          procedure ResetCountersUI;

          procedure SetUIRunningState(const p_bRunning : Boolean);
     public
     end;

var
     frmMain : TfrmMain;

implementation

{$R *.dfm}

(************************************************************
     Function Name: FmtI64
     Purpose      : Formats an Int64 value into a decimal string for UI display.
     Notes        : Centralized so formatting can be changed later (commas, etc).
************************************************************)
function FmtI64(const p_iValue : Int64) : string;
begin
     { Format Int64 as decimal string }
     Result := IntToStr(p_iValue);
end;




(************************************************************
     Procedure    : TfrmMain.SetUIRunningState
     Purpose      : Centralizes UI enable/disable state changes when scan starts/stops.
     Parameters   :
          p_bRunning - True to indicate a scan is active.
     Notes        :
          - Keeps UI consistent and avoids duplicated enable/disable logic.
************************************************************)
procedure TfrmMain.SetUIRunningState(const p_bRunning : Boolean);
begin
     { Store running state }
     m_bScanRunning := p_bRunning;

     { Toggle button caption based on state }
     if m_bScanRunning then
     begin
          cmdThread.Caption := 'Disable';
     end else
     begin
          cmdThread.Caption := 'Enable';
     end;

     { Disable path controls while scanning to avoid confusion }
     txtPath.Enabled := (not m_bScanRunning);

     { Disable browse button while scanning }
     cmdSelect.Enabled := (not m_bScanRunning);
end;




(************************************************************
     Procedure    : TfrmMain.ResetCountersUI
     Purpose      : Resets UI labels to zero counts.
************************************************************)
procedure TfrmMain.ResetCountersUI;
begin
     { Reset directory label }
     lblDCount.Caption := 'Directory Count: 0';

     { Reset file label }
     lblFCount.Caption := 'File Count: 0';

     { Reset total label }
     lblTCount.Caption := 'Total Count: 0';
end;




(************************************************************
     Procedure    : TfrmMain.FormCreate
     Purpose      : Initializes engine instance and UI state.
************************************************************)
procedure TfrmMain.FormCreate(Sender : TObject);
begin
     { No scan running on startup }
     m_bScanRunning := False;

     { Create engine instance (threading code lives in uRecursiveEngine) }
     m_oEngine := TRecursiveEngine.Create(0);

     { Throttle progress updates to avoid UI spam }
     m_oEngine.NotifyEvery := 100;

     { Hook progress callback (engine queues this on main thread) }
     m_oEngine.OnProgress := HandleProgress;

     { Hook finished callback (engine queues this on main thread) }
     m_oEngine.OnFinished := HandleFinished;

     { Default demo path (Program Files) }
     txtPath.Text := TPath.Combine(TPath.GetPathRoot(GetCurrentDir), 'Program Files');

     { Reset counters display }
     ResetCountersUI;

     { Apply initial UI state }
     SetUIRunningState(False);
end;




(************************************************************
     Procedure    : TfrmMain.FormDestroy
     Purpose      : Ensures engine cancels and frees cleanly.
************************************************************)
procedure TfrmMain.FormDestroy(Sender : TObject);
begin
     { If engine exists, request cancel before freeing }
     if Assigned(m_oEngine) then
     begin
          { Ask engine to cancel any active scan }
          m_oEngine.RequestCancel;

          { Free engine (joins worker threads internally) }
          FreeAndNil(m_oEngine);
     end;
end;




(************************************************************
     Procedure    : TfrmMain.FormCloseQuery
     Purpose      : Requests cancellation if user closes window during a scan.
************************************************************)
procedure TfrmMain.FormCloseQuery(Sender : TObject; var CanClose : Boolean);
begin
     { If a scan is running, request cancel so threads can exit }
     if m_bScanRunning then
     begin
          if Assigned(m_oEngine) then
          begin
               m_oEngine.RequestCancel;
          end;
     end;
end;




(************************************************************
     Procedure    : TfrmMain.BrowseForFolder
     Purpose      : Opens folder selection dialog and applies selected path.
************************************************************)
procedure TfrmMain.BrowseForFolder;
var
     { Folder selected by the user }
     l_szFolder : string;
begin
     { Seed dialog with current path }
     l_szFolder := txtPath.Text;

     { Show folder picker }
     if SelectDirectory('Select a Directory', '', l_szFolder) then
     begin
          { Apply chosen folder to edit box }
          txtPath.Text := l_szFolder;
     end;
end;




(************************************************************
     Procedure    : TfrmMain.cmdSelectClick
     Purpose      : Browse button event handler.
************************************************************)
procedure TfrmMain.cmdSelectClick(Sender : TObject);
begin
     { Browse for a folder }
     BrowseForFolder;
end;




(************************************************************
     Procedure    : TfrmMain.HandleProgress
     Purpose      : Receives progress from engine and updates UI counters.
     Threading    : Called on MAIN THREAD (queued by engine).
************************************************************)
procedure TfrmMain.HandleProgress(const p_iPendingFolders : Int64;
                                  const p_iDirCount : Int64;
                                  const p_iFileCount : Int64);
var
     { Total items (dirs + files) }
     l_iTotal : Int64;
begin
     { Update directory label }
     lblDCount.Caption := 'Directory Count: ' + FmtI64(p_iDirCount);

     { Update file label }
     lblFCount.Caption := 'File Count: ' + FmtI64(p_iFileCount);

     { Compute total }
     l_iTotal := p_iDirCount + p_iFileCount;

     { Update total label }
     lblTCount.Caption := 'Total Count: ' + FmtI64(l_iTotal);

     { p_iPendingFolders is available if you want to display it later }
     { (Kept as parameter for future UI expansion) }
     if (p_iPendingFolders < 0) then
     begin
          { Should never happen; placeholder for debug hooks }
     end;
end;




(************************************************************
     Procedure    : TfrmMain.HandleFinished
     Purpose      : Receives finished signal from engine and finalizes UI state.
     Threading    : Called on MAIN THREAD (queued by engine).
************************************************************)
procedure TfrmMain.HandleFinished(const p_bCanceled : Boolean;
                                  const p_szLastError : string;
                                  const p_iDirCount : Int64;
                                  const p_iFileCount : Int64);
var
     { Total items (dirs + files) }
     l_iTotal : Int64;

     { Optional message text (not shown by default) }
     l_szMsg : string;
begin
     { Mark scan as no longer running and re-enable controls }
     SetUIRunningState(False);

     { Compute total }
     l_iTotal := p_iDirCount + p_iFileCount;

     { Ensure final counts are displayed }
     lblDCount.Caption := 'Directory Count: ' + FmtI64(p_iDirCount);
     lblFCount.Caption := 'File Count: ' + FmtI64(p_iFileCount);
     lblTCount.Caption := 'Total Count: ' + FmtI64(l_iTotal);

     { Build optional status message (kept for debugging / future UI) }
     if p_bCanceled then
     begin
          l_szMsg := 'Canceled.' + sLineBreak;
     end else
     begin
          l_szMsg := 'Finished.' + sLineBreak;
     end;

     { Append counts }
     l_szMsg := l_szMsg + 'Dirs: ' + FmtI64(p_iDirCount) + sLineBreak;
     l_szMsg := l_szMsg + 'Files: ' + FmtI64(p_iFileCount) + sLineBreak;

     { Append last error if present }
     if (p_szLastError <> '') then
     begin
          l_szMsg := l_szMsg + sLineBreak + 'Last Error: ' + p_szLastError;
     end;

     { If you want a dialog later, uncomment in UI design phase }
     { ShowMessage(l_szMsg); }
end;




(************************************************************
     Procedure    : TfrmMain.cmdThreadClick
     Purpose      : Starts or cancels the scan depending on current state.
************************************************************)
procedure TfrmMain.cmdThreadClick(Sender : TObject);
var
     { Path to scan }
     l_szPath : string;
begin
     { If not currently running, start scan }
     if (not m_bScanRunning) then
     begin
          { Read path from UI }
          l_szPath := Trim(txtPath.Text);

          { If path is blank, do nothing }
          if (l_szPath = '') then exit;

          { Reset counters display before starting }
          ResetCountersUI;

          { Set UI state to running }
          SetUIRunningState(True);

          { Start engine scan }
          if Assigned(m_oEngine) then
          begin
               m_oEngine.Start(l_szPath);
          end else
          begin
               { If engine is missing for some reason, revert UI state }
               SetUIRunningState(False);
          end;

     end else
     begin
          { Cancel scan }
          if Assigned(m_oEngine) then
          begin
               m_oEngine.RequestCancel;
          end;

          { UI will flip back to enabled when HandleFinished fires }
     end;
end;

end.

