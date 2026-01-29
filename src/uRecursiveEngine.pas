(************************************************************
     Project: MultiThreaded Recursive FileSearch
     Module : uRecursiveEngine.pas
     Author : Robert Milan (https://caporin.com)
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
(* Module Name : uRecursiveEngine.pas
(* Author      : Robert Milan
(* Purpose     : Multithreaded recursive directory + file scanner engine
(*
(* Notes       :
(*     - Uses shared queue + event to wake workers (no busy spin)
(*     - Uses Interlocked* for shared counters
(*     -    Progress + Finished callbacks are queued onto the main thread
(*          via TThread.Queue (so UI can safely update)
(* Threading   :
(*     - Worker threads call into engine for queue/counters
(*     - Callbacks are always fired on the main thread
(************************************************************)

(************************************************************)
(* Revision History
(* ----------------------------------------------------------
(* Date       Time     TZ   Author        Change
(* ----------------------------------------------------------
(* 2026-01-29 11:30    ET   Robert Milan  Scan-safe lifecycle update:
(*                                 - Added atomic running guard (m_iRunning)
(*                                 - Recreated worker threads per scan
(*                                 - Added ClearQueue between scans
(*                                 - Prevented TThread.Start reuse crash
(*                                 - Marked engine idle before OnFinished
(*                                 - Converted early-exit blocks to single-line exits
(* ----------------------------------------------------------
(* 2026-01-28 18:00    ET   Robert Milan  Initial uRecursiveEngine implementation:
(*                                 - Added multithreading support
(*                                 - Added classes:
(*                                       TRecursiveEngine
(*                                       TRecursiveProgressEvent
(*                                       TRecursiveFinishedEvent
(*                                       TRecursiveWorker
(*                                 - Implemented recursive file scanning via TDirectory
(*                                 - Implemented worker thread pool + shared queue
(* ----------------------------------------------------------
(************************************************************)


unit uRecursiveEngine;

interface

uses
     { Win32 atomic operations + core types }
     Winapi.Windows,

     { RTL helpers, exceptions }
     System.SysUtils,

     { TThread base class }
     System.Classes,

     { TCriticalSection, TEvent }
     System.SyncObjs,

     { TQueue<T> }
     System.Generics.Collections,

     { EnsureRange }
     System.Math,

     { TDirectory }
     System.IOUtils;

type
     { Forward declaration so engine can store worker objects }
     TRecursiveWorker = class;



     (************************************************************)
     (* Event: TRecursiveProgressEvent
     (* Purpose:
     (*     Fired periodically with current counters.
     (* Threading:
     (*     Always fired on main thread (queued by engine).
     (************************************************************)
     TRecursiveProgressEvent = procedure(const p_iPendingFolders : Int64;
                                         const p_iDirCount : Int64;
                                         const p_iFileCount : Int64) of object;



     (************************************************************)
     (* Event: TRecursiveFinishedEvent
     (* Purpose:
     (*     Fired once when scan completes or is canceled.
     (* Threading:
     (*     Always fired on main thread (queued by engine).
     (************************************************************)
     TRecursiveFinishedEvent = procedure(const p_bCanceled : Boolean;
                                         const p_szLastError : string;
                                         const p_iDirCount : Int64;
                                         const p_iFileCount : Int64) of object;



     (************************************************************)
     (* Class: TRecursiveEngine
     (* Purpose:
     (*     Standalone engine that performs multithreaded directory traversal.
     (* Scan-Safe Rule:
     (*     - TThread instances are one-shot objects.
     (*     - Therefore, workers are created per scan and never re-started.
     (************************************************************)
     TRecursiveEngine = class
     private
          { Root folder where scanning begins }
          m_szRootPath : string;

          { Shared folder queue (work list) }
          m_oQueue : TQueue<string>;

          { Protects queue access }
          m_oQueueCS : TCriticalSection;

          { Event to wake workers when new work arrives }
          m_oQueueEvent : TEvent;

          { Protects cancel flag }
          m_oCancelCS : TCriticalSection;

          { True when cancel requested }
          m_bCancel : Boolean;

          { # folders queued OR currently being scanned }
          m_iPendingFolders : Int64;

          { Total discovered directories }
          m_iDirCount : Int64;

          { Total discovered files }
          m_iFileCount : Int64;

          { Best-effort last error string }
          m_szLastError : string;

          { Worker array (created per scan) }
          m_aWorkers : TArray<TRecursiveWorker>;

          { Worker count }
          m_iWorkerCount : Integer;

          { Ensure Finished fires only once per Start }
          m_iFinishedFired : Integer;

          { Progress throttling (every N folders finished) }
          m_iNotifyEvery : Integer;
          m_iNotifyTick : Integer;

          { Running guard (0 = idle, 1 = running) }
          m_iRunning : Integer;

          { UI-safe callbacks (queued onto main thread) }
          m_OnProgress : TRecursiveProgressEvent;
          m_OnFinished : TRecursiveFinishedEvent;

          function  IsCanceled : Boolean;

          procedure SetLastError(const p_szMsg : string);

          procedure WakeWorkers;

          procedure ClearQueue;

          procedure CreateWorkersForScan;

          procedure StopAndJoinWorkers;

          procedure EnqueueFolder(const p_szFolder : string;
                                 const p_bCountAsDirectory : Boolean);

          function  TryDequeueFolder(out p_szFolder : string) : Boolean;

          function  WaitPopFolder(out p_szFolder : string) : Boolean;

          procedure FolderFinished;

          procedure FireProgress_Queued;

          procedure FireFinished_Queued(const p_bCanceled : Boolean);

     public
          constructor Create(const p_iWorkerCount : Integer = 0);

          destructor Destroy; override;

          procedure Start(const p_szRootPath : string);

          procedure RequestCancel;

          procedure IncrementFileCount;
          procedure IncrementDirCount;

          property WorkerCount : Integer read m_iWorkerCount;
          property NotifyEvery : Integer read m_iNotifyEvery write m_iNotifyEvery;

          property PendingFolders : Int64 read m_iPendingFolders;
          property DirCount : Int64 read m_iDirCount;
          property FileCount : Int64 read m_iFileCount;
          property LastError : string read m_szLastError;

          property OnProgress : TRecursiveProgressEvent read m_OnProgress write m_OnProgress;
          property OnFinished : TRecursiveFinishedEvent read m_OnFinished write m_OnFinished;
     end;



     (************************************************************)
     (* Class: TRecursiveWorker
     (* Purpose:
     (*     Worker thread that pops folder jobs and scans them.
     (************************************************************)
     TRecursiveWorker = class(TThread)
     private
          { Back-reference to engine (owned externally) }
          m_oEngine : TRecursiveEngine;

          procedure ScanFolder(const p_szFolder : string);

     protected
          procedure Execute; override;

     public
          constructor Create(const p_oEngine : TRecursiveEngine);
     end;

implementation



(************************************************************)
(* TRecursiveWorker.Create
(************************************************************)
constructor TRecursiveWorker.Create(const p_oEngine : TRecursiveEngine);
begin
     { Create suspended so engine can Start all workers at once }
     inherited Create(True);

     { Engine owns this thread object lifetime; do not auto free }
     FreeOnTerminate := False;

     { Store engine reference used for queue/cancel/counters }
     m_oEngine := p_oEngine;
end;



(************************************************************)
(* TRecursiveWorker.Execute
(************************************************************)
procedure TRecursiveWorker.Execute;
var
     { Folder path pulled from shared queue }
     l_szFolder : string;
begin
     { Worker main loop }
     while (not Terminated) do
     begin
          { Wait for a folder job (or cancel/done) }
          if m_oEngine.WaitPopFolder(l_szFolder) then
          begin
               { Scan the folder }
               ScanFolder(l_szFolder);

               { Notify engine this folder job is complete }
               m_oEngine.FolderFinished;
          end else
          begin
               { No work because done or canceled }
               exit;
          end;
     end;
end;



(************************************************************)
(* TRecursiveWorker.ScanFolder
(************************************************************)
procedure TRecursiveWorker.ScanFolder(const p_szFolder : string);
var
     { Enumerator variable for file paths }
     l_szFile : string;

     { Enumerator variable for directory paths }
     l_szDir : string;
begin
     { Reject empty folder names }
     if (p_szFolder = '') then
     begin
          exit;
     end;

     { Fast cancel check for responsiveness }
     if (m_oEngine.IsCanceled) then exit;


     try
          { Do not attempt enumeration if folder is gone / invalid }
          if (not TDirectory.Exists(p_szFolder)) then
          begin
               exit;
          end;

          { Enumerate files }
          for l_szFile in TDirectory.GetFiles(p_szFolder) do
          begin
               { Count file }
               m_oEngine.IncrementFileCount;

               { Cancel check inside loop }
               if m_oEngine.IsCanceled then
               begin
                    exit;
               end;
          end;

          { Enumerate subdirectories }
          for l_szDir in TDirectory.GetDirectories(p_szFolder) do
          begin
               { Cancel check before enqueueing more work }
               if m_oEngine.IsCanceled then
               begin
                    exit;
               end;

               { Enqueue subfolder; count it as discovered directory }
               m_oEngine.EnqueueFolder(l_szDir, True);
          end;

     except
          on E : Exception do
          begin
               { Best-effort store error (access denied is common) }
               m_oEngine.SetLastError(E.Message);
          end;
     end;
end;



(************************************************************)
(* TRecursiveEngine.Create
(************************************************************)
constructor TRecursiveEngine.Create(const p_iWorkerCount : Integer = 0);
begin
     { Base init }
     inherited Create;


     { No root until Start() }
     m_szRootPath := '';

     { Allocate work queue }
     m_oQueue := TQueue<string>.Create;

     { Allocate queue critical section }
     m_oQueueCS := TCriticalSection.Create;

     { Auto-reset event: wakes a waiter when work arrives }
     m_oQueueEvent := TEvent.Create(nil, False, False, '');

     { Allocate cancel critical section }
     m_oCancelCS := TCriticalSection.Create;

     { Default cancel flag }
     m_bCancel := False;

     { Default counters }
     m_iPendingFolders := 0;
     m_iDirCount := 0;
     m_iFileCount := 0;

     { Default last error }
     m_szLastError := '';

     { Finished callback guard }
     m_iFinishedFired := 0;

     { Progress throttle defaults }
     m_iNotifyEvery := 100;
     m_iNotifyTick := 0;

     { Engine starts idle }
     m_iRunning := 0;

     { Determine worker count }
     m_iWorkerCount := p_iWorkerCount;
     if (m_iWorkerCount <= 0) then
     begin
          { Heuristic: half the cores, clamped }
          m_iWorkerCount := EnsureRange(TThread.ProcessorCount div 2, 2, 6);
     end;

     { No workers allocated until Start() (scan-safe) }
     SetLength(m_aWorkers, 0);
end;



(************************************************************)
(* TRecursiveEngine.Destroy
(************************************************************)
destructor TRecursiveEngine.Destroy;
begin
     { Request cancel (safe even if idle) }
     RequestCancel;

     { Stop any threads if present }
     StopAndJoinWorkers;

     { Free queue/event/locks }
     FreeAndNil(m_oQueue);
     FreeAndNil(m_oQueueCS);
     FreeAndNil(m_oQueueEvent);
     FreeAndNil(m_oCancelCS);

     { Base destroy }
     inherited;
end;



(************************************************************)
(* TRecursiveEngine.ClearQueue
(* Purpose:
(*     Clear any leftover queued folder items between scans.
(************************************************************)
procedure TRecursiveEngine.ClearQueue;
begin
     { Lock queue for safe manipulation }
     m_oQueueCS.Enter;
     try
          { Drain all pending items }
          while (m_oQueue.Count > 0) do
          begin
               m_oQueue.Dequeue;
          end;
     finally
          m_oQueueCS.Leave;
     end;
end;



(************************************************************)
(* TRecursiveEngine.CreateWorkersForScan
(* Purpose:
(*     Create new one-shot worker threads for a single scan run.
(************************************************************)
procedure TRecursiveEngine.CreateWorkersForScan;
var
     { Worker creation index }
     l_iIndex : Integer;
begin
     { Allocate worker array }
     SetLength(m_aWorkers, m_iWorkerCount);

     { Create each worker suspended }
     for l_iIndex := 0 to m_iWorkerCount - 1 do
     begin
          m_aWorkers[l_iIndex] := TRecursiveWorker.Create(Self);
     end;
end;



(************************************************************)
(* TRecursiveEngine.StopAndJoinWorkers
(* Purpose:
(*     Terminate + join + free workers (if any exist).
(************************************************************)
procedure TRecursiveEngine.StopAndJoinWorkers;
var
     { Worker cleanup index }
     l_iIndex : Integer;
begin
     { If there are no workers, nothing to do }
     if (Length(m_aWorkers) <= 0) then
     begin
          exit;
     end;

     { Wake anyone waiting so they can see cancel/done }
     WakeWorkers;

     { Terminate and join each worker }
     for l_iIndex := 0 to High(m_aWorkers) do
     begin
          if Assigned(m_aWorkers[l_iIndex]) then
          begin
               { Ask thread to stop }
               m_aWorkers[l_iIndex].Terminate;

               { Wake again to break WaitFor loops in worker wait }
               WakeWorkers;

               { Join thread }
               m_aWorkers[l_iIndex].WaitFor;

               { Free worker object }
               FreeAndNil(m_aWorkers[l_iIndex]);
          end;
     end;

     { Clear array }
     SetLength(m_aWorkers, 0);
end;



(************************************************************)
(* TRecursiveEngine.Start
(* Scan-Safe:
(*     - Prevents start while already running (m_iRunning guard)
(*     - Recreates worker threads per scan (no TThread reuse)
(*     - Clears queue between scans
(************************************************************)
procedure TRecursiveEngine.Start(const p_szRootPath : string);
var
     { Worker start index }
     l_iIndex : Integer;

     { Local sanitized root }
     l_szRoot : string;
begin
     { Trim incoming root }
     l_szRoot := Trim(p_szRootPath);

     { Reject empty root }
     if (l_szRoot = '') then
     begin
          exit;
     end;

     { Guard: do not start if scan already running }
     if (InterlockedCompareExchange(m_iRunning, 1, 0) <> 0) then
     begin
          exit;
     end;

     { Save root }
     m_szRootPath := l_szRoot;

     { Reset cancel flag }
     m_oCancelCS.Enter;
     try
          m_bCancel := False;
     finally
          m_oCancelCS.Leave;
     end;

     { Ensure no old workers exist }
     StopAndJoinWorkers;

     { Clear any queued work from a prior scan }
     ClearQueue;

     { Reset counters }
     m_iPendingFolders := 0;
     m_iDirCount := 0;
     m_iFileCount := 0;

     { Reset last error }
     m_szLastError := '';

     { Reset finished guard }
     m_iFinishedFired := 0;

     { Reset progress throttle counter }
     m_iNotifyTick := 0;

     { Create fresh workers for this scan }
     CreateWorkersForScan;

     { Enqueue root folder (counts as directory) }
     EnqueueFolder(m_szRootPath, True);

     { Start each worker exactly once }
     for l_iIndex := 0 to High(m_aWorkers) do
     begin
          if Assigned(m_aWorkers[l_iIndex]) then
          begin
               m_aWorkers[l_iIndex].Start;
          end;
     end;
end;



(************************************************************)
(* TRecursiveEngine.RequestCancel
(************************************************************)
procedure TRecursiveEngine.RequestCancel;
begin
     { Set cancel flag thread-safely }
     m_oCancelCS.Enter;
     try
          m_bCancel := True;
     finally
          m_oCancelCS.Leave;
     end;

     { Wake workers so they re-check cancel quickly }
     WakeWorkers;
end;



(************************************************************)
(* TRecursiveEngine.IsCanceled
(************************************************************)
function TRecursiveEngine.IsCanceled : Boolean;
begin
     { Read cancel flag under lock }
     m_oCancelCS.Enter;
     try
          Result := m_bCancel;
     finally
          m_oCancelCS.Leave;
     end;
end;



(************************************************************)
(* TRecursiveEngine.SetLastError
(************************************************************)
procedure TRecursiveEngine.SetLastError(const p_szMsg : string);
begin
     { Store only non-empty errors (best-effort) }
     if (p_szMsg <> '') then
     begin
          m_szLastError := p_szMsg;
     end;
end;



(************************************************************)
(* TRecursiveEngine.WakeWorkers
(************************************************************)
procedure TRecursiveEngine.WakeWorkers;
begin
     { Signal event if allocated }
     if Assigned(m_oQueueEvent) then
     begin
          m_oQueueEvent.SetEvent;
     end;
end;



(************************************************************)
(* TRecursiveEngine.IncrementFileCount
(************************************************************)
procedure TRecursiveEngine.IncrementFileCount;
begin
     { Atomic increment for file count }
     InterlockedIncrement64(m_iFileCount);
end;



(************************************************************)
(* TRecursiveEngine.IncrementDirCount
(************************************************************)
procedure TRecursiveEngine.IncrementDirCount;
begin
     { Atomic increment for directory count }
     InterlockedIncrement64(m_iDirCount);
end;



(************************************************************)
(* TRecursiveEngine.EnqueueFolder
(************************************************************)
procedure TRecursiveEngine.EnqueueFolder(const p_szFolder : string;
                                         const p_bCountAsDirectory : Boolean);
begin
     { Validate folder }
     if (p_szFolder = '') then
     begin
          exit;
     end;

     { Do not accept new work when canceled }
     if IsCanceled then
     begin
          exit;
     end;

     { Optionally count as a discovered directory }
     if p_bCountAsDirectory then
     begin
          IncrementDirCount;
     end;

     { Increment pending work before enqueue }
     InterlockedIncrement64(m_iPendingFolders);

     { Queue push under lock }
     m_oQueueCS.Enter;
     try
          m_oQueue.Enqueue(p_szFolder);
     finally
          m_oQueueCS.Leave;
     end;

     { Wake worker }
     WakeWorkers;
end;



(************************************************************)
(* TRecursiveEngine.TryDequeueFolder
(************************************************************)
function TRecursiveEngine.TryDequeueFolder(out p_szFolder : string) : Boolean;
begin
     { Default outputs }
     Result := False;
     p_szFolder := '';

     { Dequeue under lock }
     m_oQueueCS.Enter;
     try
          if (m_oQueue.Count > 0) then
          begin
               p_szFolder := m_oQueue.Dequeue;
               Result := True;
          end;
     finally
          m_oQueueCS.Leave;
     end;
end;



(************************************************************)
(* TRecursiveEngine.WaitPopFolder
(* Behavior:
(*     - TryDequeue first
(*     - If nothing available but pending > 0, wait on event
(*     - If pending <= 0, done
(************************************************************)
function TRecursiveEngine.WaitPopFolder(out p_szFolder : string) : Boolean;
begin
     { Default outputs }
     Result := False;
     p_szFolder := '';

     while True do
     begin
          { Cancel check }
          if IsCanceled then
          begin
               exit;
          end;

          { Try pull work }
          if TryDequeueFolder(p_szFolder) then
          begin
               Result := True;
               exit;
          end else
          begin
               { Done if no pending }
               if (m_iPendingFolders <= 0) then
               begin
                    exit;
               end else
               begin
                    { Soft wait for new work or completion/cancel }
                    m_oQueueEvent.WaitFor(100);
               end;
          end;
     end;
end;



(************************************************************)
(* TRecursiveEngine.FireProgress_Queued
(************************************************************)
procedure TRecursiveEngine.FireProgress_Queued;
begin
     { Fire only if assigned }
     if Assigned(m_OnProgress) then
     begin
          m_OnProgress(m_iPendingFolders, m_iDirCount, m_iFileCount);
     end;
end;



(************************************************************)
(* TRecursiveEngine.FireFinished_Queued
(************************************************************)
procedure TRecursiveEngine.FireFinished_Queued(const p_bCanceled : Boolean);
begin
     { Fire only if assigned }
     if Assigned(m_OnFinished) then
     begin
          m_OnFinished(p_bCanceled, m_szLastError, m_iDirCount, m_iFileCount);
     end;
end;



(************************************************************)
(* TRecursiveEngine.FolderFinished
(************************************************************)
procedure TRecursiveEngine.FolderFinished;
var
     { Pending count after decrement }
     l_iPending : Int64;
begin
     { Decrement pending work }
     l_iPending := InterlockedDecrement64(m_iPendingFolders);

     { Progress throttle tick }
     Inc(m_iNotifyTick);

     { Fire progress periodically }
     if (m_iNotifyTick >= m_iNotifyEvery) then
     begin
          m_iNotifyTick := 0;

          TThread.Queue(nil,
               procedure
               begin
                    FireProgress_Queued;
               end);
     end;

     { If done, fire finished once }
     if (l_iPending <= 0) then
     begin
          { Wake any workers so they can exit }
          WakeWorkers;

          { Only one worker should trigger finished }
          if (InterlockedExchange(m_iFinishedFired, 1) = 0) then
          begin
               { Mark engine idle now (scan-safe for next Start call) }
               InterlockedExchange(m_iRunning, 0);

               TThread.Queue(nil,
                    procedure
                    begin
                         FireFinished_Queued(IsCanceled);
                    end);
          end;
     end;
end;

end.

