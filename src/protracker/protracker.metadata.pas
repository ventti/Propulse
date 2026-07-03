// ==========================================================================
// Song Metadata System - Core Metadata Management
// ==========================================================================
unit ProTracker.Metadata;

{$I propulse.inc}

interface

uses
	Types, Classes, SysUtils, Generics.Collections, SyncObjs,
	fpjson, jsonparser,
	ProTracker.Util;

type
	TIntegerArray = array of Integer;

const
	MAX_METADATA_ENTRIES = 100;
	MAX_TITLE_LENGTH = 50;
	MAX_BODY_LENGTH = 1000;
	METADATA_VERSION = 1;

type
	TMetadataStatus = (msOpen, msTodo, msFixme, msWip, msDone, msClosed, msInfo);

	TMetadataPointerType = (ptPattern, ptOrderList, ptSample, ptPatternRange);

	TMetadataPointer = record
		PointerType: TMetadataPointerType;
		Pattern: Byte;        // For pattern/range
		Order: Byte;          // For orderlist
		Sample: Byte;         // For sample
		Channel: Byte;        // For pattern (cursor) / range
		RowStart: Byte;       // For pattern (cursor row) / range
		RowEnd: Byte;         // For pattern range
		Column: Byte;         // For pattern (cursor column)
	end;

	TMetadataEntry = record
		ID: Integer;
		CreatedAt: TDateTime;
		UpdatedAt: TDateTime;
		Title: AnsiString;
		Body: AnsiString;
		Pointer: TMetadataPointer;
		Status: TMetadataStatus;
	end;

	// A whole-list snapshot used for undo/redo (the entry set is small).
	TMetaSnapshot = record
		Entries: array of TMetadataEntry;
		NextID: Integer;
	end;

	TSongMetadata = class
	private
		FEntries: TList<TMetadataEntry>;
		FNextID: Integer;
		FModuleFilename: String;
		FCurrentIndex: Integer;
		FLock: TCriticalSection;
		FActiveEntriesCache: array of Integer;
		FCacheValid: Boolean;
		FUndoStack: array of TMetaSnapshot;
		FRedoStack: array of TMetaSnapshot;

		function  TakeSnapshot: TMetaSnapshot;
		procedure RestoreSnapshot(const Snap: TMetaSnapshot);

		function GetMetadataFilename: String;
		function PointerToJSON(const Ptr: TMetadataPointer): TJSONObject;
		function JSONToPointer(Obj: TJSONObject): TMetadataPointer;
		function StatusToString(Status: TMetadataStatus): String;
		function StringToStatus(const S: String): TMetadataStatus;
		function GetActiveEntries: TIntegerArray;
		procedure InvalidateCache;
		function ValidateEntry(const Entry: TMetadataEntry): Boolean;
		function ValidatePointer(const Ptr: TMetadataPointer): Boolean;
		procedure ValidateAndFixIDs;

	public
		constructor Create(const ModuleFilename: String);
		destructor Destroy; override;

		procedure LoadFromFile;
		procedure SaveToFile;
		function LoadFromFileSafe: Boolean;

		function AddEntry(const Title, Body: AnsiString;
			const Pointer: TMetadataPointer; Status: TMetadataStatus = msOpen): Integer;
		procedure UpdateEntry(ID: Integer; const Title, Body: AnsiString;
			Status: TMetadataStatus);
		procedure UpdatePointer(ID: Integer; const Ptr: TMetadataPointer);
		procedure DeleteEntry(ID: Integer);

		// Undo/redo (whole-list snapshots). Call PushUndo before a mutation.
		procedure PushUndo;
		function  Undo: Boolean;
		function  Redo: Boolean;
		function  CanUndo: Boolean;
		function  CanRedo: Boolean;

		function GetEntry(ID: Integer): TMetadataEntry;
		function GetEntryCount: Integer;
		function GetEntries: TList<TMetadataEntry>;

		function GetCurrentPointer: TMetadataPointer;
		procedure NavigateToPointer(const Ptr: TMetadataPointer);
		procedure SetModuleFilename(const Filename: String);

		function NavigateNext: Boolean;
		function NavigatePrevious: Boolean;
		function GetCurrentEntry: TMetadataEntry;
		function GetCurrentEntryID: Integer;
		function FormatStatusDisplay: AnsiString;
		function GetNavigationInfo: AnsiString;

		function FixInvalidPointers: Integer;
		function ValidateAllPointers: Integer;
	end;

implementation

uses
	DateUtils, StrUtils,
	Helpers,
	ProTracker.Player, ProTracker.Editor,
	Screen.Editor,
	MainWindow, FileStreamEx,
	CWE.Dialogs;

// ==========================================================================
// TSongMetadata
// ==========================================================================

constructor TSongMetadata.Create(const ModuleFilename: String);
begin
	inherited Create;
	FModuleFilename := ModuleFilename;
	FEntries := TList<TMetadataEntry>.Create;
	FNextID := 1;
	FCurrentIndex := -1;
	FLock := TCriticalSection.Create;
	FCacheValid := False;
end;

destructor TSongMetadata.Destroy;
begin
	FLock.Enter;
	try
		FEntries.Free;
	finally
		FLock.Leave;
	end;
	FLock.Free;
	inherited Destroy;
end;

function TSongMetadata.GetMetadataFilename: String;
begin
	if FModuleFilename = '' then
		Result := ''
	else
		Result := FModuleFilename + '.json';
end;

function TSongMetadata.StatusToString(Status: TMetadataStatus): String;
begin
	case Status of
		msOpen:   Result := 'open';
		msTodo:   Result := 'todo';
		msFixme:  Result := 'fixme';
		msWip:    Result := 'wip';
		msDone:   Result := 'done';
		msClosed: Result := 'closed';
		msInfo:   Result := 'info';
	else
		Result := 'open';
	end;
end;

function TSongMetadata.StringToStatus(const S: String): TMetadataStatus;
var
	Lower: String;
begin
	Lower := LowerCase(Trim(S));
	if Lower = 'todo' then
		Result := msTodo
	else
	if Lower = 'fixme' then
		Result := msFixme
	else
	if Lower = 'wip' then
		Result := msWip
	else
	if Lower = 'done' then
		Result := msDone
	else
	if Lower = 'closed' then
		Result := msClosed
	else
	if Lower = 'info' then
		Result := msInfo
	else
		Result := msOpen;
end;

function TSongMetadata.PointerToJSON(const Ptr: TMetadataPointer): TJSONObject;
begin
	Result := TJSONObject.Create;
	case Ptr.PointerType of
		ptPattern:
		begin
			Result.Add('type', 'pattern');
			Result.Add('pattern', Ptr.Pattern);
			Result.Add('channel', Ptr.Channel);
			Result.Add('row', Ptr.RowStart);
			Result.Add('column', Ptr.Column);
		end;
		ptOrderList:
		begin
			Result.Add('type', 'orderlist');
			Result.Add('order', Ptr.Order);
		end;
		ptSample:
		begin
			Result.Add('type', 'sample');
			Result.Add('sample', Ptr.Sample);
		end;
		ptPatternRange:
		begin
			Result.Add('type', 'pattern_range');
			Result.Add('pattern', Ptr.Pattern);
			Result.Add('channel', Ptr.Channel);
			Result.Add('row_start', Ptr.RowStart);
			Result.Add('row_end', Ptr.RowEnd);
		end;
	end;
end;

function TSongMetadata.JSONToPointer(Obj: TJSONObject): TMetadataPointer;
var
	TypeStr: String;
begin
	FillChar(Result, SizeOf(Result), 0);
	if not Assigned(Obj) then Exit;

	TypeStr := LowerCase(Obj.Get('type', 'pattern'));
	if TypeStr = 'orderlist' then
	begin
		Result.PointerType := ptOrderList;
		Result.Order := Obj.Get('order', 0);
	end
	else
	if TypeStr = 'sample' then
	begin
		Result.PointerType := ptSample;
		Result.Sample := Obj.Get('sample', 1);
	end
	else
	if TypeStr = 'pattern_range' then
	begin
		Result.PointerType := ptPatternRange;
		Result.Pattern := Obj.Get('pattern', 0);
		Result.Channel := Obj.Get('channel', 0);
		Result.RowStart := Obj.Get('row_start', 0);
		Result.RowEnd := Obj.Get('row_end', 0);
	end
	else
	begin
		Result.PointerType := ptPattern;
		Result.Pattern := Obj.Get('pattern', 0);
		Result.Channel := Obj.Get('channel', 0);
		Result.RowStart := Obj.Get('row', 0);
		Result.Column := Obj.Get('column', 0);
	end;
end;

procedure TSongMetadata.InvalidateCache;
begin
	FCacheValid := False;
	SetLength(FActiveEntriesCache, 0);
end;

function TSongMetadata.GetActiveEntries: TIntegerArray;
var
	i: Integer;
	Entry: TMetadataEntry;
begin
	if FCacheValid then
	begin
		SetLength(Result, Length(FActiveEntriesCache));
		for i := 0 to High(FActiveEntriesCache) do
			Result[i] := FActiveEntriesCache[i];
		Exit;
	end;

	SetLength(Result, 0);
	for i := 0 to FEntries.Count - 1 do
	begin
		Entry := FEntries[i];
		if not (Entry.Status in [msClosed, msDone]) then
		begin
			SetLength(Result, Length(Result) + 1);
			Result[High(Result)] := i;
		end;
	end;

	SetLength(FActiveEntriesCache, Length(Result));
	for i := 0 to High(Result) do
		FActiveEntriesCache[i] := Result[i];
	FCacheValid := True;
end;

function TSongMetadata.ValidateEntry(const Entry: TMetadataEntry): Boolean;
begin
	Result := (Length(Entry.Title) <= MAX_TITLE_LENGTH) and
	          (Length(Entry.Body) <= MAX_BODY_LENGTH) and
	          (Entry.ID > 0);
end;

function TSongMetadata.ValidatePointer(const Ptr: TMetadataPointer): Boolean;
begin
	Result := True;
	case Ptr.PointerType of
		ptPattern:
			Result := (Ptr.Pattern <= MAX_PATTERNS);
		ptOrderList:
			Result := (Ptr.Order <= 127);
		ptSample:
			Result := (Ptr.Sample >= 1) and (Ptr.Sample <= 31);
		ptPatternRange:
			Result := (Ptr.Pattern <= MAX_PATTERNS) and
			          (Ptr.Channel < AMOUNT_CHANNELS) and
			          (Ptr.RowStart <= 63) and
			          (Ptr.RowEnd <= 63) and
			          (Ptr.RowStart <= Ptr.RowEnd);
	end;
end;

procedure TSongMetadata.ValidateAndFixIDs;
var
	i, j, MaxID: Integer;
	Entry: TMetadataEntry;
	IDs: array of Integer;
begin
	MaxID := 0;
	SetLength(IDs, FEntries.Count);

	// Collect all IDs and find duplicates
	for i := 0 to FEntries.Count - 1 do
	begin
		Entry := FEntries[i];
		IDs[i] := Entry.ID;
		if Entry.ID > MaxID then
			MaxID := Entry.ID;

		// Check for duplicates
		for j := 0 to i - 1 do
		begin
			if IDs[j] = Entry.ID then
			begin
				// Duplicate found, reassign
				Entry.ID := MaxID + 1;
				Inc(MaxID);
				FEntries[i] := Entry;
				IDs[i] := Entry.ID;
				Log(TEXT_WARNING + Format('Fixed duplicate metadata ID %d, reassigned to %d', [IDs[j], Entry.ID]));
			end;
		end;
	end;

	FNextID := MaxID + 1;
end;

function TSongMetadata.LoadFromFileSafe: Boolean;
begin
	Result := False;
	FLock.Enter;
	try
		try
			LoadFromFile;
			Result := True;
		except
			on E: Exception do
			begin
				Log(TEXT_FAILURE + 'Failed to load metadata: ' + E.Message);
				Result := False;
			end;
		end;
	finally
		FLock.Leave;
	end;
end;

procedure TSongMetadata.LoadFromFile;
var
	Filename, S: String;
	JSONData: TJSONData;
	RootObj: TJSONObject;
	EntriesArray: TJSONArray;
	EntryObj: TJSONObject;
	Entry: TMetadataEntry;
	i: Integer;
	CreatedStr, UpdatedStr: String;
	Stream: TFileStream;
	RetryCount: Integer;
	LastError: Exception;
begin
	Filename := GetMetadataFilename;
	if (Filename = '') or (not FileExists(Filename)) then
	begin
		FEntries.Clear;
		FNextID := 1;
		InvalidateCache;
		Exit;
	end;

	FLock.Enter;
	try
		FEntries.Clear;
		
		// Retry logic for transient file system errors (EAGAIN on macOS)
		RetryCount := 0;
		LastError := nil;
		Stream := nil;
		while RetryCount < 5 do
		begin
			try
				Stream := TFileStream.Create(Filename, fmOpenRead or fmShareDenyNone);
				Break; // Success, exit retry loop
			except
				on E: Exception do
				begin
					LastError := E;
					// Check if it's a transient error (EAGAIN / Resource temporarily unavailable)
					if (Pos('Resource temporarily unavailable', E.Message) > 0) or
					   (Pos('temporarily unavailable', E.Message) > 0) or
					   (E is EFCreateError) then
					begin
						Inc(RetryCount);
						if RetryCount < 5 then
						begin
							// Brief delay before retrying (allows file system to settle)
							// Use a simple loop for cross-platform compatibility
							// This gives the file system a moment to become available
							for i := 1 to 1000 * RetryCount do
								; // Busy wait
							Continue;
						end;
					end;
					// Not a retryable error, re-raise
					raise;
				end;
			end;
		end;
		
		if Stream = nil then
		begin
			if LastError <> nil then
				raise LastError
			else
				raise Exception.Create('Failed to open metadata file after retries');
		end;
		
		// Use GetJSON with string read from stream (non-deprecated API)
		Stream.Position := 0;
		SetLength(S, Stream.Size);
		Stream.ReadBuffer(S[1], Stream.Size);
		Stream.Free;
		Stream := nil;
		
		JSONData := GetJSON(S);
		try
			// Handle version 1 format with wrapper object
			if JSONData is TJSONObject then
			begin
				RootObj := TJSONObject(JSONData);
				// Version is read but not currently used (for future version checking)
				RootObj.Get('version', 0);
				EntriesArray := RootObj.Get('entries', TJSONArray(nil)) as TJSONArray;
			end
			else
			// Backward compatibility: direct array (old format)
			if JSONData is TJSONArray then
			begin
				EntriesArray := TJSONArray(JSONData);
			end
			else
			begin
				raise Exception.Create('Invalid JSON format');
			end;

			if not Assigned(EntriesArray) then
				Exit;

			for i := 0 to EntriesArray.Count - 1 do
			begin
				EntryObj := EntriesArray.Objects[i];
				if not Assigned(EntryObj) then Continue;

				Entry.ID := EntryObj.Get('id', 0);
				Entry.Title := EntryObj.Get('title', '');
				Entry.Body := EntryObj.Get('body', '');
				Entry.Status := StringToStatus(EntryObj.Get('status', 'open'));

				// Parse timestamps
				CreatedStr := EntryObj.Get('created_at', '');
				UpdatedStr := EntryObj.Get('updated_at', '');
				if CreatedStr <> '' then
					Entry.CreatedAt := ISO8601ToDate(CreatedStr)
				else
					Entry.CreatedAt := Now;
				if UpdatedStr <> '' then
					Entry.UpdatedAt := ISO8601ToDate(UpdatedStr)
				else
					Entry.UpdatedAt := Entry.CreatedAt;

				// Parse pointer
				Entry.Pointer := JSONToPointer(EntryObj.Get('pointer', TJSONObject(nil)));

				// Validate entry
				if ValidateEntry(Entry) then
					FEntries.Add(Entry)
				else
					Log(TEXT_WARNING + Format('Skipped invalid metadata entry ID %d', [Entry.ID]));
			end;

			// Validate and fix IDs
			ValidateAndFixIDs;
			// Honor a persisted running counter so ticket numbers are never reused,
			// even if the highest-numbered note was deleted (ValidateAndFixIDs only
			// guarantees MaxID+1).
			if (JSONData is TJSONObject) and
			   (TJSONObject(JSONData).Get('next_id', 0) > FNextID) then
				FNextID := TJSONObject(JSONData).Get('next_id', 0);
			InvalidateCache;
		finally
			JSONData.Free;
		end;
	finally
		FLock.Leave;
	end;
end;

procedure TSongMetadata.SaveToFile;
var
	Filename, TempFilename: String;
	RootObj: TJSONObject;
	EntriesArray: TJSONArray;
	EntryObj: TJSONObject;
	Entry: TMetadataEntry;
	i: Integer;
	Stream: TFileStream;
	JSONStr: String;
	Dir: String;
	RetryCount: Integer;
	LastError: Exception;
begin
	Filename := GetMetadataFilename;
	if Filename = '' then Exit;

	FLock.Enter;
	try
		// Don't create file if no entries
		if FEntries.Count = 0 then
		begin
			if FileExists(Filename) then
				DeleteFile(Filename);
			Exit;
		end;

		// Ensure directory exists before creating file
		Dir := ExtractFilePath(Filename);
		if (Dir <> '') and (not DirectoryExists(Dir)) then
			ForceDirectories(Dir);

		RootObj := TJSONObject.Create;
		try
			RootObj.Add('version', METADATA_VERSION);
			RootObj.Add('module_hash', ''); // Optional, can be filled later
			RootObj.Add('next_id', FNextID); // Persist running counter so IDs are never reused

			EntriesArray := TJSONArray.Create;
			for i := 0 to FEntries.Count - 1 do
			begin
				Entry := FEntries[i];
				EntryObj := TJSONObject.Create;
				EntryObj.Add('id', Entry.ID);
				EntryObj.Add('created_at', DateToISO8601(Entry.CreatedAt));
				EntryObj.Add('updated_at', DateToISO8601(Entry.UpdatedAt));
				EntryObj.Add('title', Entry.Title);
				EntryObj.Add('body', Entry.Body);
				EntryObj.Add('status', StatusToString(Entry.Status));
				EntryObj.Add('pointer', PointerToJSON(Entry.Pointer));
				EntriesArray.Add(EntryObj);
			end;

			RootObj.Add('entries', EntriesArray);

			// Use atomic write: write to temp file, then rename
			// This prevents readers from seeing partially written files
			TempFilename := Filename + '.tmp';
			
			// Retry logic for transient file system errors
			RetryCount := 0;
			LastError := nil;
			while RetryCount < 5 do
			begin
				try
					// Write to temp file
					Stream := TFileStream.Create(TempFilename, fmCreate);
					try
						JSONStr := RootObj.AsJSON;
						if Length(JSONStr) > 0 then
							Stream.WriteBuffer(JSONStr[1], Length(JSONStr));
					finally
						Stream.Free;
					end;
					
					// Atomic rename: replace target file atomically
					// On most file systems, this is an atomic operation
					if FileExists(Filename) then
						DeleteFile(Filename);
					RenameFile(TempFilename, Filename);
					
					Break; // Success, exit retry loop
				except
					on E: Exception do
					begin
						LastError := E;
						// Clean up temp file if it exists
						if FileExists(TempFilename) then
							DeleteFile(TempFilename);
						
						// Check if it's a transient error (EAGAIN / Resource temporarily unavailable)
						if (Pos('Resource temporarily unavailable', E.Message) > 0) or
						   (Pos('temporarily unavailable', E.Message) > 0) or
						   (E is EFCreateError) or (E is EFOpenError) then
						begin
							Inc(RetryCount);
							if RetryCount < 5 then
							begin
								// Brief delay before retrying
								for i := 1 to 1000 * RetryCount do
									; // Busy wait
								Continue;
							end;
						end;
						// Not a retryable error, re-raise
						raise;
					end;
				end;
			end;
			
			if RetryCount >= 5 then
			begin
				if LastError <> nil then
				begin
					Log(TEXT_FAILURE + Format('Failed to save metadata file "%s" after retries: %s', [Filename, LastError.Message]));
					raise LastError;
				end
				else
					raise Exception.Create('Failed to save metadata file after retries');
			end;
		finally
			RootObj.Free;
		end;
	finally
		FLock.Leave;
	end;
end;

function TSongMetadata.AddEntry(const Title, Body: AnsiString;
	const Pointer: TMetadataPointer; Status: TMetadataStatus = msOpen): Integer;
var
	Entry: TMetadataEntry;
	TitleTrimmed, BodyTrimmed: AnsiString;
begin
	Result := -1;

	FLock.Enter;
	try
		// Check entry limit
		if FEntries.Count >= MAX_METADATA_ENTRIES then
		begin
			Log(TEXT_FAILURE + Format('Maximum %d metadata entries reached', [MAX_METADATA_ENTRIES]));
			Exit;
		end;

		// Warn at 90 entries
		if FEntries.Count = 90 then
			Log(TEXT_WARNING + Format('Approaching metadata limit: %d of %d entries', [FEntries.Count, MAX_METADATA_ENTRIES]));

		// Trim the title; keep the body verbatim (free 2D text canvas — leading/
		// trailing blank lines and space padding are meaningful).
		TitleTrimmed := Copy(Trim(Title), 1, MAX_TITLE_LENGTH);
		BodyTrimmed := Copy(Body, 1, MAX_BODY_LENGTH);

		if not ValidatePointer(Pointer) then
		begin
			Log(TEXT_WARNING + 'Invalid pointer, entry not added');
			Exit;
		end;

		Entry.ID := FNextID;
		Inc(FNextID);
		Entry.CreatedAt := Now;
		Entry.UpdatedAt := Entry.CreatedAt;
		Entry.Title := TitleTrimmed;
		Entry.Body := BodyTrimmed;
		Entry.Pointer := Pointer;
		Entry.Status := Status;

		FEntries.Add(Entry);
		InvalidateCache;
		Result := Entry.ID;
	finally
		FLock.Leave;
	end;
end;

procedure TSongMetadata.UpdateEntry(ID: Integer; const Title, Body: AnsiString;
	Status: TMetadataStatus);
var
	i: Integer;
	Entry: TMetadataEntry;
	TitleTrimmed, BodyTrimmed: AnsiString;
begin
	FLock.Enter;
	try
		for i := 0 to FEntries.Count - 1 do
		begin
			if FEntries[i].ID = ID then
			begin
				Entry := FEntries[i];
				TitleTrimmed := Copy(Trim(Title), 1, MAX_TITLE_LENGTH);
				// Do NOT trim the body: the notes body is a free 2D text canvas, so
				// leading/trailing blank lines and space padding are meaningful layout.
				BodyTrimmed := Copy(Body, 1, MAX_BODY_LENGTH);

				Entry.Title := TitleTrimmed;
				Entry.Body := BodyTrimmed;
				Entry.Status := Status;
				Entry.UpdatedAt := Now;

				FEntries[i] := Entry;
				InvalidateCache;
				Exit;
			end;
		end;
	finally
		FLock.Leave;
	end;
end;

procedure TSongMetadata.UpdatePointer(ID: Integer; const Ptr: TMetadataPointer);
var
	i: Integer;
	Entry: TMetadataEntry;
begin
	if not ValidatePointer(Ptr) then Exit;
	FLock.Enter;
	try
		for i := 0 to FEntries.Count - 1 do
		begin
			if FEntries[i].ID = ID then
			begin
				Entry := FEntries[i];
				Entry.Pointer := Ptr;
				Entry.UpdatedAt := Now;
				FEntries[i] := Entry;
				InvalidateCache;
				Exit;
			end;
		end;
	finally
		FLock.Leave;
	end;
end;

procedure TSongMetadata.DeleteEntry(ID: Integer);
var
	i: Integer;
begin
	FLock.Enter;
	try
		for i := FEntries.Count - 1 downto 0 do
		begin
			if FEntries[i].ID = ID then
			begin
				FEntries.Delete(i);
				InvalidateCache;
				Exit;
			end;
		end;
	finally
		FLock.Leave;
	end;
end;

function TSongMetadata.GetEntry(ID: Integer): TMetadataEntry;
var
	i: Integer;
begin
	FillChar(Result, SizeOf(Result), 0);
	FLock.Enter;
	try
		for i := 0 to FEntries.Count - 1 do
		begin
			if FEntries[i].ID = ID then
			begin
				Result := FEntries[i];
				Exit;
			end;
		end;
	finally
		FLock.Leave;
	end;
end;

function TSongMetadata.GetEntryCount: Integer;
begin
	FLock.Enter;
	try
		Result := FEntries.Count;
	finally
		FLock.Leave;
	end;
end;

function TSongMetadata.GetEntries: TList<TMetadataEntry>;
begin
	Result := FEntries;
end;

// ==========================================================================
// Undo / redo (whole-list snapshots; the entry set is small)
// ==========================================================================

function TSongMetadata.TakeSnapshot: TMetaSnapshot;
var
	i: Integer;
begin
	SetLength(Result.Entries, FEntries.Count);
	for i := 0 to FEntries.Count - 1 do
		Result.Entries[i] := FEntries[i];
	Result.NextID := FNextID;
end;

procedure TSongMetadata.RestoreSnapshot(const Snap: TMetaSnapshot);
var
	i: Integer;
begin
	FEntries.Clear;
	for i := 0 to High(Snap.Entries) do
		FEntries.Add(Snap.Entries[i]);
	FNextID := Snap.NextID;
	InvalidateCache;
end;

procedure TSongMetadata.PushUndo;
const
	MAX_UNDO = 100;
var
	n, i: Integer;
begin
	FLock.Enter;
	try
		n := Length(FUndoStack);
		if n >= MAX_UNDO then
		begin
			// Drop the oldest snapshot.
			for i := 1 to n - 1 do
				FUndoStack[i - 1] := FUndoStack[i];
			Dec(n);
			SetLength(FUndoStack, n);
		end;
		SetLength(FUndoStack, n + 1);
		FUndoStack[n] := TakeSnapshot;
		SetLength(FRedoStack, 0); // a new action invalidates redo
	finally
		FLock.Leave;
	end;
end;

function TSongMetadata.Undo: Boolean;
var
	n: Integer;
begin
	Result := False;
	FLock.Enter;
	try
		n := Length(FUndoStack);
		if n = 0 then Exit;
		// Current state -> redo, then restore the top undo snapshot.
		SetLength(FRedoStack, Length(FRedoStack) + 1);
		FRedoStack[High(FRedoStack)] := TakeSnapshot;
		RestoreSnapshot(FUndoStack[n - 1]);
		SetLength(FUndoStack, n - 1);
		Result := True;
	finally
		FLock.Leave;
	end;
end;

function TSongMetadata.Redo: Boolean;
var
	n: Integer;
begin
	Result := False;
	FLock.Enter;
	try
		n := Length(FRedoStack);
		if n = 0 then Exit;
		SetLength(FUndoStack, Length(FUndoStack) + 1);
		FUndoStack[High(FUndoStack)] := TakeSnapshot;
		RestoreSnapshot(FRedoStack[n - 1]);
		SetLength(FRedoStack, n - 1);
		Result := True;
	finally
		FLock.Leave;
	end;
end;

function TSongMetadata.CanUndo: Boolean;
begin
	Result := Length(FUndoStack) > 0;
end;

function TSongMetadata.CanRedo: Boolean;
begin
	Result := Length(FRedoStack) > 0;
end;

function TSongMetadata.GetCurrentPointer: TMetadataPointer;
var
	Sel: TRect;
begin
	FillChar(Result, SizeOf(Result), 0);
	if not Assigned(Module) then Exit;

	// Don't access editor state if a modal dialog is open (could cause access violations)
	if Assigned(ModalDialog) and (ModalDialog.Dialog <> nil) then
	begin
		// Return a safe default pointer when dialog is open
		Result.PointerType := ptPattern;
		Result.Pattern := 0;
		Exit;
	end;

	// Check if there's a selection in pattern editor (range)
	if Assigned(PatternEditor) then
	begin
		try
			Sel := PatternEditor.Selection;
			if (Sel.Left >= 0) and (Sel.Top >= 0) and (Sel.Bottom >= 0) then
			begin
				Result.PointerType := ptPatternRange;
				Result.Pattern := CurrentPattern;
				Result.Channel := Sel.Left;
				Result.RowStart := Sel.Top;
				Result.RowEnd := Sel.Bottom;
				Exit;
			end;
		except
			// If selection access fails, fall through to pattern pointer
		end;
		
		// Check current editor state
		try
			Result.PointerType := ptPattern;
			Result.Pattern := CurrentPattern;
			Result.Channel := PatternEditor.Cursor.Channel;
			Result.RowStart := PatternEditor.Cursor.Row;
			Result.Column := Ord(PatternEditor.Cursor.Column);
			Exit;
		except
			// If CurrentPattern access fails, continue to next check
		end;
	end;
	
	if Assigned(OrderList) then
	begin
		try
			Result.PointerType := ptOrderList;
			Result.Order := OrderList.Cursor.Y;
			Exit;
		except
			// If OrderList access fails, continue to next check
		end;
	end;
	
	if Assigned(Module) then
	begin
		try
			Result.PointerType := ptSample;
			Result.Sample := CurrentSample;
		except
			// If CurrentSample access fails, return default (already zeroed)
		end;
	end;
end;

procedure TSongMetadata.NavigateToPointer(const Ptr: TMetadataPointer);
var
	ch, rw, re: Integer;
begin
	if not Assigned(Module) then Exit;

	// Clamp positions: pointers can come from imported modules that had more
	// channels / rows than a ProTracker pattern, so guard against range errors.
	ch := Ptr.Channel;
	if ch < 0 then ch := 0;
	if ch > AMOUNT_CHANNELS - 1 then ch := AMOUNT_CHANNELS - 1;
	rw := Ptr.RowStart;
	if rw < 0 then rw := 0;
	if rw > 63 then rw := 63;
	re := Ptr.RowEnd;
	if re < rw then re := rw;
	if re > 63 then re := 63;

	case Ptr.PointerType of
		ptPattern:
		begin
			if Assigned(Editor) and (Ptr.Pattern <= MAX_PATTERNS) then
			begin
				Editor.SelectPattern(Ptr.Pattern);
				if Assigned(PatternEditor) then
				begin
					PatternEditor.Cursor.Row := rw;
					PatternEditor.Cursor.Channel := ch;
					if Ptr.Column <= Ord(High(EditColumn)) then
						PatternEditor.Cursor.Column := EditColumn(Ptr.Column);
					PatternEditor.ValidateCursor;
					PatternEditor.Paint;
				end;
			end;
		end;
		ptOrderList:
		begin
			if Assigned(OrderList) and (Ptr.Order <= 127) then
			begin
				OrderList.Cursor.Y := Ptr.Order;
				OrderList.Cursor.X := 0;
				if Assigned(Editor) then
				begin
					Editor.ActiveControl := OrderList;
					OrderList.Paint;
				end;
			end;
		end;
		ptSample:
		begin
			if Assigned(Editor) and (Ptr.Sample >= 1) and (Ptr.Sample <= 31) then
			begin
				Editor.SetSample(Ptr.Sample);
			end;
		end;
		ptPatternRange:
		begin
			if Assigned(Editor) and (Ptr.Pattern <= MAX_PATTERNS) then
			begin
				Editor.SelectPattern(Ptr.Pattern);
				if Assigned(PatternEditor) then
				begin
					PatternEditor.Cursor.Row := rw;
					PatternEditor.Cursor.Channel := ch;
					PatternEditor.Selection := Types.Rect(ch, rw, ch, re);
					PatternEditor.ValidateCursor;
					PatternEditor.Paint;
				end;
			end;
		end;
	end;
end;

function TSongMetadata.NavigateNext: Boolean;
var
	ActiveEntries: array of Integer;
	i: Integer;
begin
	Result := False;
	FLock.Enter;
	try
		ActiveEntries := GetActiveEntries;
		if Length(ActiveEntries) = 0 then Exit;

		// Find current position in active entries if not set
		if FCurrentIndex < 0 then
		begin
			// Try to find entry matching current editor position
			FCurrentIndex := 0;
			for i := 0 to Length(ActiveEntries) - 1 do
			begin
				// Simple heuristic: start from first entry
				// Could be improved to find closest match
			end;
		end
		else
		begin
			// Find current index in active entries array
			for i := 0 to Length(ActiveEntries) - 1 do
			begin
				if ActiveEntries[i] = FCurrentIndex then
				begin
					FCurrentIndex := i;
					Break;
				end;
			end;
			// Move to next
			Inc(FCurrentIndex);
			if FCurrentIndex >= Length(ActiveEntries) then
				FCurrentIndex := 0; // Wrap around
		end;

		if (FCurrentIndex >= 0) and (FCurrentIndex < Length(ActiveEntries)) then
		begin
			FCurrentIndex := ActiveEntries[FCurrentIndex]; // Store actual entry index
			NavigateToPointer(FEntries[FCurrentIndex].Pointer);
			Result := True;
		end;
	finally
		FLock.Leave;
	end;
end;

function TSongMetadata.NavigatePrevious: Boolean;
var
	ActiveEntries: array of Integer;
	i: Integer;
begin
	Result := False;
	FLock.Enter;
	try
		ActiveEntries := GetActiveEntries;
		if Length(ActiveEntries) = 0 then Exit;

		// Find current position in active entries if not set
		if FCurrentIndex < 0 then
		begin
			FCurrentIndex := Length(ActiveEntries) - 1;
		end
		else
		begin
			// Find current index in active entries array
			for i := 0 to Length(ActiveEntries) - 1 do
			begin
				if ActiveEntries[i] = FCurrentIndex then
				begin
					FCurrentIndex := i;
					Break;
				end;
			end;
			// Move to previous
			Dec(FCurrentIndex);
			if FCurrentIndex < 0 then
				FCurrentIndex := Length(ActiveEntries) - 1; // Wrap around
		end;

		if (FCurrentIndex >= 0) and (FCurrentIndex < Length(ActiveEntries)) then
		begin
			FCurrentIndex := ActiveEntries[FCurrentIndex]; // Store actual entry index
			NavigateToPointer(FEntries[FCurrentIndex].Pointer);
			Result := True;
		end;
	finally
		FLock.Leave;
	end;
end;

function TSongMetadata.GetCurrentEntry: TMetadataEntry;
var
	ActiveEntries: array of Integer;
begin
	FillChar(Result, SizeOf(Result), 0);
	FLock.Enter;
	try
		ActiveEntries := GetActiveEntries;
		if (FCurrentIndex >= 0) and (FCurrentIndex < Length(ActiveEntries)) then
			Result := FEntries[ActiveEntries[FCurrentIndex]];
	finally
		FLock.Leave;
	end;
end;

function TSongMetadata.GetCurrentEntryID: Integer;
var
	Entry: TMetadataEntry;
begin
	Entry := GetCurrentEntry;
	Result := Entry.ID;
end;

function TSongMetadata.FormatStatusDisplay: AnsiString;
var
	Entry: TMetadataEntry;
begin
	Entry := GetCurrentEntry;
	if Entry.ID = 0 then
		Result := ''
	else
		Result := Format('%d %s: %s', [Entry.ID, StatusToString(Entry.Status), Entry.Title]);
end;

function TSongMetadata.GetNavigationInfo: AnsiString;
var
	ActiveEntries: array of Integer;
	CurrentPos: Integer;
begin
	Result := '';
	FLock.Enter;
	try
		ActiveEntries := GetActiveEntries;
		if Length(ActiveEntries) = 0 then Exit;

		CurrentPos := FCurrentIndex + 1;
		if CurrentPos < 1 then CurrentPos := 1;
		Result := Format('Note %d of %d', [CurrentPos, Length(ActiveEntries)]);
	finally
		FLock.Leave;
	end;
end;

function TSongMetadata.FixInvalidPointers: Integer;
var
	i: Integer;
	Entry: TMetadataEntry;
	Fixed: Boolean;
begin
	Result := 0;
	FLock.Enter;
	try
		for i := 0 to FEntries.Count - 1 do
		begin
			Entry := FEntries[i];
			Fixed := False;

			if not ValidatePointer(Entry.Pointer) then
			begin
				case Entry.Pointer.PointerType of
					ptPattern:
					begin
						if Entry.Pointer.Pattern > MAX_PATTERNS then
						begin
							Entry.Pointer.Pattern := 0;
							Fixed := True;
						end;
					end;
					ptSample:
					begin
						if (Entry.Pointer.Sample < 1) or (Entry.Pointer.Sample > 31) then
						begin
							Entry.Pointer.Sample := 1;
							Fixed := True;
						end;
					end;
					ptPatternRange:
					begin
						if Entry.Pointer.RowStart > Entry.Pointer.RowEnd then
						begin
							Entry.Pointer.RowEnd := Entry.Pointer.RowStart;
							Fixed := True;
						end;
						if Entry.Pointer.Channel >= AMOUNT_CHANNELS then
						begin
							Entry.Pointer.Channel := 0;
							Fixed := True;
						end;
					end;
				end;

				if Fixed then
				begin
					FEntries[i] := Entry;
					Inc(Result);
				end;
			end;
		end;

		if Result > 0 then
			InvalidateCache;
	finally
		FLock.Leave;
	end;
end;

function TSongMetadata.ValidateAllPointers: Integer;
var
	i: Integer;
begin
	Result := 0;
	FLock.Enter;
	try
		for i := 0 to FEntries.Count - 1 do
		begin
			if not ValidatePointer(FEntries[i].Pointer) then
				Inc(Result);
		end;
	finally
		FLock.Leave;
	end;
end;

procedure TSongMetadata.SetModuleFilename(const Filename: String);
begin
	FLock.Enter;
	try
		FModuleFilename := Filename;
	finally
		FLock.Leave;
	end;
end;

end.

