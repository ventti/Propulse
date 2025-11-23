program Propulse;

(*	Propulse - a ProTracker clone with an Impulse Tracker-style interface

	Copyright 2016-2019 Joel Toivonen (hukka)
	Portions of code adapted from pt2play.c Copyright Olav Sørensen (8bitbubsy)

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
*)

{$R propulse.res}
{$I propulse.inc}

uses
	{$IFDEF UNIX} cthreads, Classes, SysUtils, {$ENDIF}
	MainWindow, Screen.Log;

	{$IFDEF UNIX}
	// on Unix we need to initialize the threading system before
	// using custom callbacks with BASS or we crash!
	type
		TDummyThread = class(TThread)
			procedure Execute; override;
		end;

		procedure TDummyThread.Execute;
		begin
		end;
	{$ENDIF}

var
	CrashLog: TextFile;
	LogFile: String;

begin
	{$IFNDEF WINDOWS}
	with TDummyThread.Create(False) do
	begin
		WaitFor;
		Free;
	end;
	{$ENDIF}

	{$IF declared(UseHeapTrace)}
	GlobalSkipIfNoLeaks := True;
	SetHeapTraceOutput('trace.log');
	{$ENDIF}

	try
		Window := TWindow.Create;

		try
			while not QuitFlag do
			begin
				try
					Window.ProcessFrame;
				except
					on E: Exception do
					begin
						WriteLn(StdErr, '========================================');
						WriteLn(StdErr, 'Exception in ProcessFrame');
						WriteLn(StdErr, '========================================');
						WriteLn(StdErr, 'Exception: ', E.ClassName);
						WriteLn(StdErr, 'Message: ', E.Message);
						{$IFDEF UNIX}
						WriteLn(StdErr, 'Stack trace:');
						DumpExceptionBackTrace(StdErr);
						{$ENDIF}
						// Try to log to file if possible
						try
							if Assigned(LogScreen) then
								LogScreen.Log('[FATAL] Exception in ProcessFrame: ' + E.ClassName + ': ' + E.Message);
						except
							// Ignore logging errors
						end;
						raise; // Re-raise to show crash dialog
					end;
				end;
			end;
		finally
			if Assigned(Window) then
				Window.Free;
		end;
	except
		on E: Exception do
		begin
			WriteLn(StdErr, '========================================');
			WriteLn(StdErr, 'FATAL EXCEPTION');
			WriteLn(StdErr, '========================================');
			WriteLn(StdErr, 'Exception: ', E.ClassName);
			WriteLn(StdErr, 'Message: ', E.Message);
			{$IFDEF UNIX}
			WriteLn(StdErr, '');
			WriteLn(StdErr, 'Stack trace:');
			WriteLn(StdErr, '----------------------------------------');
			DumpExceptionBackTrace(StdErr);
			WriteLn(StdErr, '----------------------------------------');
			{$ENDIF}
			// Write crash log to file
			try
				LogFile := ExtractFilePath(ParamStr(0)) + 'crash.log';
				AssignFile(CrashLog, LogFile);
				Rewrite(CrashLog);
				WriteLn(CrashLog, 'Propulse Crash Report');
				WriteLn(CrashLog, '====================');
				WriteLn(CrashLog, 'Time: ', FormatDateTime('YYYY-mm-dd hh:nn:ss', Now));
				WriteLn(CrashLog, 'Exception: ', E.ClassName);
				WriteLn(CrashLog, 'Message: ', E.Message);
				{$IFDEF UNIX}
				WriteLn(CrashLog, '');
				WriteLn(CrashLog, 'Stack trace:');
				WriteLn(CrashLog, '----------------------------------------');
				DumpExceptionBackTrace(CrashLog);
				WriteLn(CrashLog, '----------------------------------------');
				{$ENDIF}
				CloseFile(CrashLog);
				WriteLn(StdErr, '');
				WriteLn(StdErr, 'Crash log written to: ', LogFile);
			except
				on F: Exception do
					WriteLn(StdErr, 'Failed to write crash log: ', F.Message);
			end;
			Halt(1);
		end;
	end;
end.

