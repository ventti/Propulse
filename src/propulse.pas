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
	{$IFDEF UNIX} cthreads, {$ENDIF}
	Classes, SysUtils,
	MainWindow, Screen.Log,
	CommandLine;

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

// Custom exception handler - based on SysUtils.CatchUnhandledException
// but with custom output formatting and rock-solid error handling
procedure CustomExceptionHandler(ExceptObject: TObject; ExceptAddr: Pointer);
begin
	// Write to stderr only - rock-solid error handling
	try
		WriteLn(StdErr, '========================================');
		WriteLn(StdErr, 'FATAL EXCEPTION');
		WriteLn(StdErr, '========================================');
		if ExceptObject is Exception then
		begin
			WriteLn(StdErr, 'Exception: ', Exception(ExceptObject).ClassName);
			WriteLn(StdErr, 'Message: ', Exception(ExceptObject).Message);
		end
		else
		begin
			WriteLn(StdErr, 'Exception: ', ExceptObject.ClassName);
			WriteLn(StdErr, 'Address: ', HexStr(ExceptAddr));
		end;
		
		{$IFDEF UNIX}
		WriteLn(StdErr, '');
		WriteLn(StdErr, 'Stack trace:');
		WriteLn(StdErr, '----------------------------------------');
		try
			DumpExceptionBackTrace(StdErr);
		except
			// If DumpExceptionBackTrace fails, at least we tried
			WriteLn(StdErr, '(Failed to generate stack trace)');
		end;
		WriteLn(StdErr, '----------------------------------------');
		{$ENDIF}
	except
		// If writing to stderr fails, we're in deep trouble
		// but at least we tried
	end;
	
	// Always halt - this is a fatal exception
	Halt(1);
end;

var
	ExePath, ExeDir, DataDir, DocsDir: String;
begin
	// Install custom exception handler before anything else
	// This will catch all unhandled exceptions
	ExceptProc := @CustomExceptionHandler;

	// Handle command-line arguments that should exit immediately (-h/--help, -v/--version)
	// and collect any temporary settings overrides (--set) for later application.
	ParseCommandLine;
	
	// Check for required directories BEFORE any initialization that might access files
	// This prevents crashes when running from different directories
	ExePath := ExpandFileName(ParamStr(0));
	ExeDir := IncludeTrailingPathDelimiter(ExtractFilePath(ExePath));
	
	DataDir := ExeDir + 'data';
	DocsDir := ExeDir + 'docs';
	
	if not DirectoryExists(DataDir) then
	begin
		WriteLn(StdErr, '');
		WriteLn(StdErr, 'ERROR: Required directory not found: ', DataDir);
		WriteLn(StdErr, '');
		WriteLn(StdErr, 'The "data" directory (or symbolic link) must exist in the same');
		WriteLn(StdErr, 'directory as the executable.');
		WriteLn(StdErr, '');
		WriteLn(StdErr, 'Executable location: ', ExeDir);
		WriteLn(StdErr, 'Expected data path:   ', DataDir);
		WriteLn(StdErr, '');
		Halt(1);
	end;
	
	if not DirectoryExists(DocsDir) then
	begin
		WriteLn(StdErr, '');
		WriteLn(StdErr, 'ERROR: Required directory not found: ', DocsDir);
		WriteLn(StdErr, '');
		WriteLn(StdErr, 'The "docs" directory (or symbolic link) must exist in the same');
		WriteLn(StdErr, 'directory as the executable.');
		WriteLn(StdErr, '');
		WriteLn(StdErr, 'Executable location: ', ExeDir);
		WriteLn(StdErr, 'Expected docs path:  ', DocsDir);
		WriteLn(StdErr, '');
		Halt(1);
	end;
	
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

	Window := TWindow.Create;

	try
		while not QuitFlag do
		begin
			try
				Window.ProcessFrame;
			except
				on E: Exception do
				begin
					// Try to log to screen if possible (non-fatal)
					try
						if Assigned(LogScreen) then
							LogScreen.Log('[FATAL] Exception in ProcessFrame: ' + E.ClassName + ': ' + E.Message);
					except
						// Ignore logging errors
					end;
					raise; // Re-raise - will be caught by ExceptProc
				end;
			end;
		end;
	finally
		if Assigned(Window) then
			Window.Free;
	end;
end.

