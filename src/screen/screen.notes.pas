// ==========================================================================
// Notes Screen - View and edit song metadata (full screen)
// ==========================================================================
unit Screen.Notes;

interface

uses
	Classes, Types, SysUtils,
	TextMode, CWE.Core, CWE.Widgets.Text, CWE.Dialogs, ShortcutManager,
	ProTracker.Metadata;

const
	LENGTH_NOTETEXT = 22; // Same as LENGTH_SAMPLETEXT

type
	TNotesList = class(TCWEList)
	private
		CursorInStatus: Boolean;
		LastEntryID: Integer;
		LastEntryTitle: AnsiString;
	public
		Cursor: TPoint;
		procedure Paint; override;
		function KeyDown(var Key: Integer; Shift: TShiftState): Boolean; override;
		function TextInput(var Key: Char): Boolean; override;
		function MouseDown(Button: TMouseButton; X, Y: Integer; P: TPoint): Boolean; override;
		constructor Create(Owner: TCWEControl; const sCaption, sID: AnsiString; const Bounds: TRect; IsProtected: Boolean = False); override;
	end;

	TMultiLineEdit = class(TCWEEdit)
	private
		FLines: TStringList;
		FCursorY: Integer;
		FLineOffset: Integer; // Vertical scroll offset
		FWrappedLines: TStringList; // Display lines (with wrapping)
		FSourceToWrapped: array of Integer; // Maps source line index to first wrapped line index
		FWrappedLinesDirty: Boolean; // Flag to track if wrapped lines need updating
		function GetText: AnsiString;
		procedure SetText(const Value: AnsiString);
		procedure UpdateWrappedLines;
	public
		constructor Create(Owner: TCWEControl; const sCaption, sID: AnsiString; const Bounds: TRect; IsProtected: Boolean = False); override;
		destructor Destroy; override;
		function KeyDown(var Key: Integer; Shift: TShiftState): Boolean; override;
		function TextInput(var Key: Char): Boolean; override;
		procedure Paint; override;
		procedure SetCaption(const NewCaption: AnsiString; CursorAtStart: Boolean = False);
		property Text: AnsiString read GetText write SetText;
	end;

	TNotesScreen = class(TCWEScreen)
	private
		NotesList: TNotesList;
		TitleEdit: TCWEEdit;
		BodyEdit: TMultiLineEdit;
		StatusLabel: TCWELabel;
		PointerLabel: TCWELabel;
		CreatedLabel: TCWELabel;
		UpdatedLabel: TCWELabel;
		SummaryLabel: TCWELabel;
		BtnNew, BtnDelete, BtnGoto, BtnSetPtr, BtnFixAll: TCWEButton;
		CurrentEntryID: Integer;
		CurrentStatus: TMetadataStatus;
		UpdatingDisplay: Boolean; // Flag to prevent recursive calls
		
		procedure UpdateEntryDisplay;
		procedure RefreshList;
		procedure HandleNotesAction(ActionID: Integer);
		procedure BodyEditChanged(Sender: TCWEControl);
		procedure TitleEditChanged(Sender: TCWEControl);
		procedure CheckListSelection;
		procedure ListSelectionChanged(Sender: TCWEControl);
		procedure ButtonNewClick(Sender: TCWEControl);
		procedure ButtonDeleteClick(Sender: TCWEControl);
		procedure ButtonGotoClick(Sender: TCWEControl);
		procedure ButtonSetPtrClick(Sender: TCWEControl);
		procedure ButtonFixAllClick(Sender: TCWEControl);
		function StatusLabelMouseDown(Sender: TCWEControl; Button: TMouseButton; X, Y: Integer; P: TPoint): Boolean;
		procedure StatusSelectionCallback(ID: Word; ModalResult: TDialogButton; Tag: Integer; Data: Variant; Dlg: TCWEDialog);
		function EnsureNoteExists: Boolean;
		
	public
		constructor Create(var Con: TConsole; const sCaption, sID: AnsiString); override;
		function KeyDown(var Key: Integer; Shift: TShiftState): Boolean; override;
		procedure Show; override;
	end;

var
	NotesScreen: TNotesScreen;

implementation

uses
	StrUtils, DateUtils, Generics.Collections, Math,
	Layout,
	ProTracker.Player, ProTracker.Editor, ProTracker.Util,
	Screen.Editor, MainWindow;

const
	ACTION_NEW = 1;
	ACTION_DELETE = 2;
	ACTION_GOTO = 3;
	ACTION_SETPOINTER = 4;
	ACTION_SAVE = 5;
	ACTION_CYCLESTATUS = 6;
	ACTION_FIXALL = 7;
	ACTION_SELECTSTATUS = 8;

function FormatPointer(const Ptr: TMetadataPointer): AnsiString;
begin
	case Ptr.PointerType of
		ptPattern:
			Result := Format('Pattern %d', [Ptr.Pattern]);
		ptOrderList:
			Result := Format('Order %d', [Ptr.Order]);
		ptSample:
			Result := Format('Sample %d', [Ptr.Sample]);
		ptPatternRange:
			Result := Format('Pattern %d Ch%d R%d-%d', [Ptr.Pattern, Ptr.Channel, Ptr.RowStart, Ptr.RowEnd]);
	else
		Result := 'None';
	end;
end;

function FormatStatus(const Status: TMetadataStatus): AnsiString;
begin
	case Status of
		msOpen:   Result := 'open';
		msTodo:   Result := 'todo';
		msFixme:  Result := 'fixm';
		msWip:    Result := 'wip ';
		msDone:   Result := 'done';
		msClosed: Result := 'clsd';
	else
		Result := 'open';
	end;
end;

{ TNotesList }

constructor TNotesList.Create(Owner: TCWEControl; const sCaption, sID: AnsiString; const Bounds: TRect; IsProtected: Boolean);
begin
	inherited;
	SetData(0, 0,  'Cursor foreground');
	SetData(1, 11, 'Cursor background');
	SetData(2, 6,  'Status text enabled');
	SetData(3, 7,  'Status text disabled');
	SetData(4, 4,  'Last character color');
	SetData(5, 14, 'Selection background');
	ColorFore := 6;
	ColorBack := 3;
	Cursor.X := 0;
	Cursor.Y := 0;
	CursorInStatus := False;
	LastEntryID := -1;
	LastEntryTitle := '';
	WantMouse := True;
	WantKeyboard := True;
	WantHover := False;
	// Hide scrollbar
	if Assigned(Scrollbar) then
		Scrollbar.Visible := False;
end;

function TNotesList.MouseDown(Button: TMouseButton; X, Y: Integer; P: TPoint): Boolean;
var
	Entries: TList<TMetadataEntry>;
	StatusStartX, MaxSlots: Integer;
begin
	Result := False;
	if Button <> mbLeft then Exit;
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	
	Entries := Module.Metadata.GetEntries;
	MaxSlots := Rect.Bottom - Rect.Top;
	if MaxSlots > MAX_METADATA_ENTRIES then
		MaxSlots := MAX_METADATA_ENTRIES;
	if (P.Y < 0) or (P.Y >= MaxSlots) then Exit;
	
	// Check if click is on status field (after separator, 4 chars wide)
	StatusStartX := 3 + LENGTH_NOTETEXT + 1; // After separator
	if P.X >= StatusStartX then
	begin
		// Clicked on status - open dropdown (only if slot has an entry)
		ItemIndex := P.Y;
		if (P.Y >= 0) and (P.Y < Entries.Count) then
		begin
			// Set current entry and open status dialog
			if Assigned(Screen) and (Screen is TNotesScreen) then
			begin
				TNotesScreen(Screen).CurrentEntryID := Entries[P.Y].ID;
				TNotesScreen(Screen).StatusLabelMouseDown(nil, Button, X, Y, P);
			end;
		end;
		Result := True;
		Exit;
	end;
	
	// Click on title area - set cursor position
	Dec(P.X, 3); // Adjust for number column
	if P.X < 0 then P.X := 0;
	
	ItemIndex := P.Y;
	Cursor.X := P.X;
	Cursor.Y := P.Y;
	CursorInStatus := False;
	
	if Assigned(Screen) and (Screen is TNotesScreen) then
	begin
		if (P.Y >= 0) and (P.Y < Entries.Count) then
			TNotesScreen(Screen).CurrentEntryID := Entries[P.Y].ID
		else
			TNotesScreen(Screen).CurrentEntryID := -1;
		TNotesScreen(Screen).UpdateEntryDisplay;
	end;
	
	Paint;
	Result := True;
end;

function TNotesList.TextInput(var Key: Char): Boolean;
var
	Entry: TMetadataEntry;
	NewTitle: AnsiString;
	Entries: TList<TMetadataEntry>;
begin
	Result := False;
	if not Focused then Exit;
	if CursorInStatus then Exit; // Don't edit when cursor is in status area
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	
	Entries := Module.Metadata.GetEntries;
	if (Cursor.Y < 0) or (Cursor.Y >= Entries.Count) or (Entries.Count = 0) then Exit;
	
	Entry := Entries[Cursor.Y];
	
	// Track title changes for undo/redo if needed
	if (LastEntryID <> Entry.ID) or (LastEntryTitle <> Entry.Title) then
	begin
		LastEntryID := Entry.ID;
		LastEntryTitle := Entry.Title;
	end;
	
		// Edit title (limit to LENGTH_NOTETEXT for display, but can store up to MAX_TITLE_LENGTH)
		NewTitle := Entry.Title;
		while Length(NewTitle) < Cursor.X do
			NewTitle := NewTitle + ' ';
		Insert(Key, NewTitle, Cursor.X+1);
		NewTitle := Copy(NewTitle, 1, MAX_TITLE_LENGTH); // MAX_TITLE_LENGTH = 50
		
		// Update entry
		Module.Metadata.UpdateEntry(Entry.ID, NewTitle, Entry.Body, Entry.Status);
		Module.Metadata.SaveToFile;
		
		if Cursor.X < LENGTH_NOTETEXT then
			Inc(Cursor.X)
		else
		begin
			// Moved beyond title area, go to status
			CursorInStatus := True;
			Cursor.X := 0;
		end;
		
		LastEntryTitle := NewTitle;
	
	// Update display
	if Assigned(Screen) and (Screen is TNotesScreen) then
		TNotesScreen(Screen).UpdateEntryDisplay;
	
	Result := True;
	Paint;
end;

function TNotesList.KeyDown(var Key: Integer; Shift: TShiftState): Boolean;
var
	Sc: ControlKeyNames;
	Entry: TMetadataEntry;
	NewTitle: AnsiString;
	Entries: TList<TMetadataEntry>;
	MaxSlots: Integer;
begin
	Result := False;
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	
	Entries := Module.Metadata.GetEntries;
	MaxSlots := Rect.Bottom - Rect.Top;
	if MaxSlots > MAX_METADATA_ENTRIES then
		MaxSlots := MAX_METADATA_ENTRIES;
	
	// Allow navigation even if no entries exist (to show empty slots)
	if (Entries.Count = 0) and (Cursor.Y >= MaxSlots) then Exit;
	
	Sc := ControlKeyNames(Shortcuts.Find(ControlKeys, Key, Shift));
	
	case Sc of
		ctrlkeyLEFT:
			if Cursor.X > 0 then
			begin
				Dec(Cursor.X);
				CursorInStatus := False;
				Result := True;
			end;
		
		ctrlkeyRIGHT:
		begin
			if CursorInStatus then
			begin
				CursorInStatus := False;
				Cursor.X := 0;
			end
			else
			begin
				if Cursor.X < LENGTH_NOTETEXT then
					Inc(Cursor.X)
				else
				begin
					// Move to status area
					CursorInStatus := True;
					Cursor.X := 0;
				end;
			end;
			Result := True;
		end;
		
		ctrlkeyUP:
			if Cursor.Y > 0 then
			begin
				Dec(Cursor.Y);
				ItemIndex := Cursor.Y;
				CursorInStatus := False;
				if (Cursor.Y < Entries.Count) and (Entries.Count > 0) then
				begin
					Entry := Entries[Cursor.Y];
					Cursor.X := Min(Cursor.X, Min(Length(Entry.Title), LENGTH_NOTETEXT));
					if Assigned(Screen) and (Screen is TNotesScreen) then
					begin
						TNotesScreen(Screen).CurrentEntryID := Entry.ID;
						TNotesScreen(Screen).UpdateEntryDisplay;
					end;
				end
				else
				begin
					Cursor.X := Min(Cursor.X, LENGTH_NOTETEXT);
					if Assigned(Screen) and (Screen is TNotesScreen) then
					begin
						TNotesScreen(Screen).CurrentEntryID := -1;
						TNotesScreen(Screen).UpdateEntryDisplay;
					end;
				end;
				Result := True;
			end;
		
		ctrlkeyDOWN:
			if Cursor.Y < MaxSlots - 1 then
			begin
				Inc(Cursor.Y);
				ItemIndex := Cursor.Y;
				CursorInStatus := False;
				if (Cursor.Y < Entries.Count) and (Entries.Count > 0) then
				begin
					Entry := Entries[Cursor.Y];
					Cursor.X := Min(Cursor.X, Min(Length(Entry.Title), LENGTH_NOTETEXT));
					if Assigned(Screen) and (Screen is TNotesScreen) then
					begin
						TNotesScreen(Screen).CurrentEntryID := Entry.ID;
						TNotesScreen(Screen).UpdateEntryDisplay;
					end;
				end
				else
				begin
					Cursor.X := Min(Cursor.X, LENGTH_NOTETEXT);
					if Assigned(Screen) and (Screen is TNotesScreen) then
					begin
						TNotesScreen(Screen).CurrentEntryID := -1;
						TNotesScreen(Screen).UpdateEntryDisplay;
					end;
				end;
				Result := True;
			end;
		
		ctrlkeyHOME:
		begin
			Cursor.X := 0;
			CursorInStatus := False;
			Result := True;
		end;
		
		ctrlkeyEND:
		begin
			if (Cursor.Y >= 0) and (Cursor.Y < Entries.Count) and (Entries.Count > 0) then
			begin
				Entry := Entries[Cursor.Y];
				Cursor.X := Min(Length(Entry.Title), LENGTH_NOTETEXT);
				CursorInStatus := False;
			end
			else
			begin
				Cursor.X := LENGTH_NOTETEXT;
				CursorInStatus := False;
			end;
			Result := True;
		end;
		
		ctrlkeyBACKSPACE:
			if not CursorInStatus and (Cursor.Y >= 0) and (Cursor.Y < Entries.Count) and (Entries.Count > 0) then
			begin
				Entry := Entries[Cursor.Y];
				NewTitle := Entry.Title;
				if Cursor.X > 0 then
				begin
					Delete(NewTitle, Cursor.X, 1);
					Dec(Cursor.X);
					Module.Metadata.UpdateEntry(Entry.ID, NewTitle, Entry.Body, Entry.Status);
					Module.Metadata.SaveToFile;
					if Assigned(Screen) and (Screen is TNotesScreen) then
						TNotesScreen(Screen).UpdateEntryDisplay;
					Result := True;
				end;
			end;
		
		ctrlkeyDELETE:
			if not CursorInStatus and (Cursor.Y >= 0) and (Cursor.Y < Entries.Count) and (Entries.Count > 0) then
			begin
				Entry := Entries[Cursor.Y];
				NewTitle := Entry.Title;
				if Cursor.X < Length(NewTitle) then
				begin
					Delete(NewTitle, Cursor.X+1, 1);
					Module.Metadata.UpdateEntry(Entry.ID, NewTitle, Entry.Body, Entry.Status);
					Module.Metadata.SaveToFile;
					if Assigned(Screen) and (Screen is TNotesScreen) then
						TNotesScreen(Screen).UpdateEntryDisplay;
					Result := True;
				end;
			end;
		
		ctrlkeyRETURN:
			if CursorInStatus and (Cursor.Y >= 0) and (Cursor.Y < Entries.Count) and (Entries.Count > 0) then
			begin
				// Open status dropdown when Enter is pressed on status
				Entry := Entries[Cursor.Y];
				if Assigned(Screen) and (Screen is TNotesScreen) then
				begin
					TNotesScreen(Screen).CurrentEntryID := Entry.ID;
					TNotesScreen(Screen).StatusLabelMouseDown(nil, mbLeft, 0, 0, Point(0, 0));
				end;
				Result := True;
			end;
		
	else
		Exit(False);
	end;
	
	if Result then
		Paint;
end;

procedure TNotesList.Paint;
var
	i, x, MaxSlots, SlotIndex: Integer;
	col: Byte;
	Entry: TMetadataEntry;
	Entries: TList<TMetadataEntry>;
	StatusNames: array[TMetadataStatus] of AnsiString = ('open', 'todo', 'fixm', 'wip ', 'done', 'clsd');
	StatusColors: array[TMetadataStatus] of Byte = (6, 11, 9, 14, 10, 7); // Colors for each status
	TitleMaxLen: Integer;
	EntryMap: array of Integer; // Maps slot index to entry index, or -1 if empty
begin
	if not Screen.Active then Exit;
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;

	Console.BeginUpdate;

	Console.FrameRect(Types.Rect(
		Rect.Left+3, Rect.Top, Rect.Right, Rect.Bottom), True, True, TConsole.COLOR_BLANK);

	Entries := Module.Metadata.GetEntries;
	MaxSlots := Rect.Bottom - Rect.Top;
	if MaxSlots > MAX_METADATA_ENTRIES then
		MaxSlots := MAX_METADATA_ENTRIES;

	// Build a map of slot index to entry index
	SetLength(EntryMap, MaxSlots);
	for i := 0 to MaxSlots - 1 do
		EntryMap[i] := -1; // -1 means empty slot

	// Map existing entries to slots
	for i := 0 to Min(Entries.Count - 1, MaxSlots - 1) do
		EntryMap[i] := i;

	// Ensure Items list has enough items for display
	while Items.Count < MaxSlots do
		Items.Add(TCWEListItem.Create(''));

	// Update cursor status
	CursorInStatus := (Cursor.X >= LENGTH_NOTETEXT);

	// Draw all slots (like samples list shows all 31 slots)
	for SlotIndex := 0 to MaxSlots - 1 do
	begin
		i := EntryMap[SlotIndex];
		
		if i >= 0 then
		begin
			// Slot has an entry
			Entry := Entries[i];

			// Number (like samples: %.2d)
			Console.Write(Format('%.2d', [Entry.ID]), Rect.Left, Rect.Top+SlotIndex, 0);
			
			// Title (editable area) - same width as sample list (22 chars)
			Console.Write(Copy(Entry.Title, 1, LENGTH_NOTETEXT), Rect.Left+3, Rect.Top+SlotIndex, ColorFore);

			if (SlotIndex = ItemIndex) then
			begin
				// Highlight title area
				for x := 0 to LENGTH_NOTETEXT - 1 do
					Console.SetColor(Rect.Left+3+x, Rect.Top+SlotIndex, -1, Data[5].Value);

				if Focused then
				begin
					if not CursorInStatus and (SlotIndex = Cursor.Y) then
					begin
						// Show cursor in title area
						if Cursor.X < LENGTH_NOTETEXT then
							Console.SetColor(Rect.Left+3+Cursor.X, Rect.Top+SlotIndex,
								Data[0].Value, Data[1].Value);
					end;
					
					// Status area always has black background, even when focused
					for x := 0 to 3 do
						Console.SetColor(Rect.Left+3+LENGTH_NOTETEXT+1+x, Rect.Top+SlotIndex,
							Data[0].Value, TConsole.COLOR_BLANK);
				end;
			end;

			// Status (like "Play" in samples) - separate clickable field, 4 chars
			if (SlotIndex = ItemIndex) and Focused and CursorInStatus and (SlotIndex = Cursor.Y) then
				col := Data[0].Value
			else
			if (SlotIndex = ItemIndex) and Focused then
				col := Data[2].Value
			else
				col := StatusColors[Entry.Status];
		end
		else
		begin
			// Empty slot - show placeholder
			Console.Write('--', Rect.Left, Rect.Top+SlotIndex, 7); // Gray number
			// Empty title area (already blank)
			
			if (SlotIndex = ItemIndex) and Focused then
			begin
				// Highlight empty slot
				for x := 0 to LENGTH_NOTETEXT - 1 do
					Console.SetColor(Rect.Left+3+x, Rect.Top+SlotIndex, -1, Data[5].Value);
				
				// Status area always has black background, even when focused
				for x := 0 to 3 do
					Console.SetColor(Rect.Left+3+LENGTH_NOTETEXT+1+x, Rect.Top+SlotIndex,
						Data[0].Value, TConsole.COLOR_BLANK);
			end;
			
			col := Data[3].Value; // Disabled color for empty status
		end;

		// Separator (always shown, like in samples list) - at position after title (22 chars)
		Console.PutChar(Rect.Left + 3 + LENGTH_NOTETEXT, Rect.Top+SlotIndex, 168,
			TConsole.COLOR_PANEL, TConsole.COLOR_BLANK);

		// Status text (4 chars, like "Play" in samples) - always on black background
		// Set background to black for all status column cells
		for x := 0 to 3 do
			Console.SetColor(Rect.Left+3+LENGTH_NOTETEXT+1+x, Rect.Top+SlotIndex, col, TConsole.COLOR_BLANK);
		
		if i >= 0 then
			Console.Write(StatusNames[Entry.Status], Rect.Left+3+LENGTH_NOTETEXT+1, Rect.Top+SlotIndex, col)
		else
			Console.Write('----', Rect.Left+3+LENGTH_NOTETEXT+1, Rect.Top+SlotIndex, col); // Empty status
	end;

	Console.EndUpdate;
end;

{ TMultiLineEdit }

constructor TMultiLineEdit.Create(Owner: TCWEControl; const sCaption, sID: AnsiString; const Bounds: TRect; IsProtected: Boolean);
begin
	inherited;
	FLines := TStringList.Create;
	FWrappedLines := TStringList.Create;
	FCursorY := 0;
	FLineOffset := 0;
	FWrappedLinesDirty := True;
	SetLength(FSourceToWrapped, 0);
	if sCaption <> '' then
		SetText(sCaption);
end;

destructor TMultiLineEdit.Destroy;
begin
	FLines.Free;
	FWrappedLines.Free;
	inherited;
end;

function TMultiLineEdit.GetText: AnsiString;
begin
	Result := FLines.Text;
	// Remove trailing line break
	if (Length(Result) > 0) and (Result[Length(Result)] = #10) then
		SetLength(Result, Length(Result) - 1);
	if (Length(Result) > 0) and (Result[Length(Result)] = #13) then
		SetLength(Result, Length(Result) - 1);
end;

procedure TMultiLineEdit.SetText(const Value: AnsiString);
begin
	if not Assigned(FLines) then Exit;
	FLines.Text := Value;
	FCursorY := 0;
	FLineOffset := 0;
	if FLines.Count = 0 then
		FLines.Add('');
	Cursor.X := 0;
	Offset := 0;
	FWrappedLinesDirty := True;
	UpdateWrappedLines;
end;

procedure TMultiLineEdit.UpdateWrappedLines;
var
	i, j, MaxWidth: Integer;
	Line, Remaining: AnsiString;
	WrapPos: Integer;
begin
	if not Assigned(FWrappedLines) then Exit;
	if not Assigned(FLines) then Exit;
	
	// Check if Rect is valid
	if (Rect.Right <= Rect.Left) or (Rect.Right - Rect.Left < 3) then
	begin
		// Rect not initialized or too small, use a default width
		FWrappedLines.Clear;
		if FLines.Count > 0 then
		begin
			SetLength(FSourceToWrapped, FLines.Count);
			for i := 0 to FLines.Count - 1 do
			begin
				FSourceToWrapped[i] := i;
				FWrappedLines.Add(FLines[i]);
			end;
		end
		else
			SetLength(FSourceToWrapped, 0);
		FWrappedLinesDirty := False;
		Exit;
	end;
	
	FWrappedLines.Clear;
	
	if FLines.Count = 0 then
	begin
		SetLength(FSourceToWrapped, 0);
		FWrappedLinesDirty := False;
		Exit;
	end;
	
	SetLength(FSourceToWrapped, FLines.Count);
	
	MaxWidth := Rect.Right - Rect.Left - 2; // Account for border
	if MaxWidth < 1 then MaxWidth := 1; // Safety check
	
	for i := 0 to FLines.Count - 1 do
	begin
		FSourceToWrapped[i] := FWrappedLines.Count;
		Line := FLines[i];
		Remaining := Line;
		
		// Always add at least one wrapped line per source line
		if Remaining = '' then
		begin
			FWrappedLines.Add('');
		end
		else
		begin
			while Remaining <> '' do
			begin
				if Length(Remaining) <= MaxWidth then
				begin
					FWrappedLines.Add(Remaining);
					Remaining := '';
				end
				else
				begin
					// Try to break at a space
					WrapPos := MaxWidth;
					for j := MaxWidth downto 1 do
					begin
						if (j <= Length(Remaining)) and (j > 0) and (Remaining[j] = ' ') then
						begin
							WrapPos := j;
							Break;
						end;
					end;
					// Ensure WrapPos doesn't exceed remaining length
					if WrapPos > Length(Remaining) then
						WrapPos := Length(Remaining);
					if WrapPos < 1 then
						WrapPos := 1;
					FWrappedLines.Add(Copy(Remaining, 1, WrapPos));
					if WrapPos < Length(Remaining) then
						Remaining := TrimLeft(Copy(Remaining, WrapPos + 1, MaxInt))
					else
						Remaining := '';
				end;
			end;
		end;
	end;
	
	FWrappedLinesDirty := False;
end;

function TMultiLineEdit.KeyDown(var Key: Integer; Shift: TShiftState): Boolean;
var
	Sc: ControlKeyNames;
	Line: AnsiString;
begin
	Result := True;
	Sc := ControlKeyNames(Shortcuts.Find(ControlKeys, Key, Shift));

	case Sc of
		ctrlkeyUP:
			if FCursorY > 0 then
			begin
				Dec(FCursorY);
				Cursor.X := Min(Cursor.X, Length(FLines[FCursorY]));
				// Adjust vertical scroll based on wrapped lines
				// Find the wrapped line index for this source line
				if FCursorY < Length(FSourceToWrapped) then
				begin
					if FSourceToWrapped[FCursorY] < FLineOffset then
						FLineOffset := FSourceToWrapped[FCursorY];
				end;
			end
			else
				Screen.BrowseControls(True);

		ctrlkeyDOWN:
			if FCursorY < FLines.Count - 1 then
			begin
				Inc(FCursorY);
				Cursor.X := Min(Cursor.X, Length(FLines[FCursorY]));
				// Adjust vertical scroll based on wrapped lines
				if FCursorY < Length(FSourceToWrapped) then
				begin
					if FSourceToWrapped[FCursorY] >= FLineOffset + Height then
						FLineOffset := FSourceToWrapped[FCursorY] - Height + 1;
				end;
			end
			else
				Screen.BrowseControls(False);

		ctrlkeyLEFT:
			if Cursor.X > 0 then
				Dec(Cursor.X)
			else if (FCursorY > 0) and (FCursorY < FLines.Count) then
			begin
				Dec(FCursorY);
				if FCursorY < FLines.Count then
					Cursor.X := Length(FLines[FCursorY]);
			end;

		ctrlkeyRIGHT:
		begin
			if (FCursorY >= 0) and (FCursorY < FLines.Count) then
			begin
				if Cursor.X < Length(FLines[FCursorY]) then
					Inc(Cursor.X)
				else if FCursorY < FLines.Count - 1 then
				begin
					Inc(FCursorY);
					Cursor.X := 0;
				end;
			end;
		end;

		ctrlkeyHOME:
			Cursor.X := 0;

		ctrlkeyEND:
		begin
			if (FCursorY >= 0) and (FCursorY < FLines.Count) then
				Cursor.X := Length(FLines[FCursorY])
			else
				Cursor.X := 0;
		end;

		ctrlkeyBACKSPACE:
		begin
			if (FCursorY >= 0) and (FCursorY < FLines.Count) then
			begin
				if Cursor.X > 0 then
				begin
					Line := FLines[FCursorY];
					Delete(Line, Cursor.X, 1);
					FLines[FCursorY] := Line;
					Dec(Cursor.X);
				end
				else if FCursorY > 0 then
				begin
					Line := FLines[FCursorY];
					FLines.Delete(FCursorY);
					Dec(FCursorY);
					if FCursorY < FLines.Count then
					begin
						Cursor.X := Length(FLines[FCursorY]);
						FLines[FCursorY] := FLines[FCursorY] + Line;
					end;
				end;
				UpdateWrappedLines;
				Change(ReportAnyChange);
			end;
		end;

		ctrlkeyDELETE:
		begin
			if (FCursorY >= 0) and (FCursorY < FLines.Count) then
			begin
				Line := FLines[FCursorY];
				if Cursor.X < Length(Line) then
				begin
					Delete(Line, Cursor.X+1, 1);
					FLines[FCursorY] := Line;
				end
				else if FCursorY < FLines.Count - 1 then
				begin
					FLines[FCursorY] := FLines[FCursorY] + FLines[FCursorY+1];
					FLines.Delete(FCursorY+1);
				end;
				UpdateWrappedLines;
				Change(ReportAnyChange);
			end;
		end;

		ctrlkeyRETURN:
		begin
			Line := FLines[FCursorY];
			FLines[FCursorY] := Copy(Line, 1, Cursor.X);
			FLines.Insert(FCursorY+1, Copy(Line, Cursor.X+1, MaxInt));
			Inc(FCursorY);
			Cursor.X := 0;
			UpdateWrappedLines;
			// Adjust vertical scroll
			if FCursorY >= FLineOffset + Height then
				FLineOffset := FCursorY - Height + 1;
			Change(ReportAnyChange);
		end;

	else
		Exit(False);
	end;

	Paint;
end;

function TMultiLineEdit.TextInput(var Key: Char): Boolean;
var
	Line: AnsiString;
begin
	Result := False;
	if not Assigned(FLines) then Exit;
	if Ord(Key) < 32 then Exit; // Control characters handled in KeyDown
	if (AllowedChars <> '') and (Pos(Key, AllowedChars) < 1) then Exit;
	if Length(GetText) >= MaxLength then Exit;
	if (FCursorY < 0) or (FCursorY >= FLines.Count) or (FLines.Count = 0) then Exit;

	Line := FLines[FCursorY];
	Insert(Key, Line, Cursor.X+1);
	FLines[FCursorY] := Copy(Line, 1, MaxLength);
	Inc(Cursor.X);
	
	FWrappedLinesDirty := True;
	UpdateWrappedLines;

	Result := True;
	Change(ReportAnyChange);
	Paint;
end;

procedure TMultiLineEdit.Paint;
var
	C, B, y, i: Integer;
	Line: AnsiString;
	DisplayY: Integer;
begin
	if not Screen.Active then Exit;
	if not Assigned(FWrappedLines) then Exit;
	if not Assigned(FLines) then Exit;

	DrawBorder;

	if (Focused) or (Hovered) then
	begin
		C := Data[0].Value;
		B := Data[1].Value;
	end
	else
	begin
		C := ColorFore;
		B := ColorBack;
	end;

	// Ensure wrapped lines are up to date (only if dirty)
	if FWrappedLinesDirty then
		UpdateWrappedLines;

	// Display visible wrapped lines
	for y := 0 to Height - 1 do
	begin
		i := y + FLineOffset;
		if (i >= 0) and (i < FWrappedLines.Count) then
		begin
			Line := Copy(FWrappedLines[i], Offset + 1, Rect.Right - Rect.Left - 2);
			Console.FillRect(Types.Rect(Rect.Left + 1, Rect.Top + y, Rect.Right - 1, Rect.Top + y + 1), ' ', C, B);
			Console.Write(Line, Rect.Left + 1, Rect.Top + y);
			
			// Find which source line this wrapped line belongs to and show cursor if needed
			if Focused and Assigned(FLines) and (FCursorY >= 0) and (FCursorY < FLines.Count) and 
			   (FCursorY < Length(FSourceToWrapped)) then
			begin
				// Check if this wrapped line belongs to the current source line
				if (i >= FSourceToWrapped[FCursorY]) and 
				   ((FCursorY = FLines.Count - 1) or (i < FSourceToWrapped[FCursorY+1])) then
				begin
					// Calculate cursor position in wrapped line
					DisplayY := Rect.Left + 1 + Cursor.X - Offset;
					if (DisplayY >= Rect.Left + 1) and (DisplayY < Rect.Right - 1) then
						Console.SetColor(DisplayY, Rect.Top + y, TConsole.COLOR_TEXT, TConsole.COLOR_LIGHT);
				end;
			end;
		end
		else
			Console.FillRect(Types.Rect(Rect.Left + 1, Rect.Top + y, Rect.Right - 1, Rect.Top + y + 1), ' ', C, B);
	end;
end;

procedure TMultiLineEdit.SetCaption(const NewCaption: AnsiString; CursorAtStart: Boolean);
begin
	if not Assigned(FLines) then Exit;
	SetText(NewCaption);
	if CursorAtStart then
	begin
		FCursorY := 0;
		Cursor.X := 0;
	end
	else
	begin
		if FLines.Count > 0 then
		begin
			FCursorY := FLines.Count - 1;
			Cursor.X := Length(FLines[FCursorY]);
		end
		else
		begin
			FCursorY := 0;
			Cursor.X := 0;
		end;
	end;
	Paint;
end;

{ TNotesScreen }

procedure TNotesScreen.UpdateEntryDisplay;
var
	Entry: TMetadataEntry;
	Summary: AnsiString;
begin
	UpdatingDisplay := True;
	try
		if (CurrentEntryID < 0) or (not Assigned(Module)) or (not Assigned(Module.Metadata)) then
		begin
			SummaryLabel.SetCaption('');
			TitleEdit.SetCaption('');
			BodyEdit.SetText('');
			StatusLabel.SetCaption('Status: open');
			PointerLabel.SetCaption('Pointer: None');
			CreatedLabel.SetCaption('');
			UpdatedLabel.SetCaption('');
			CurrentStatus := msOpen;
			Exit;
		end;

		Entry := Module.Metadata.GetEntry(CurrentEntryID);
		if Entry.ID = 0 then Exit;

		Summary := FormatPointer(Entry.Pointer) + ': ' + Entry.Title + ' [' + FormatStatus(Entry.Status) + ']';
		SummaryLabel.SetCaption(Summary);
		TitleEdit.SetCaption(Entry.Title);
		BodyEdit.SetText(Entry.Body);
		CurrentStatus := Entry.Status;
		StatusLabel.SetCaption('Status: ' + FormatStatus(Entry.Status));
		PointerLabel.SetCaption('Pointer: ' + FormatPointer(Entry.Pointer));
		CreatedLabel.SetCaption('Created: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Entry.CreatedAt));
		UpdatedLabel.SetCaption('Updated: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Entry.UpdatedAt));
	finally
		UpdatingDisplay := False;
	end;
end;

procedure TNotesScreen.CheckListSelection;
var
	Entry: TMetadataEntry;
	Entries: TList<TMetadataEntry>;
begin
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	if not Assigned(NotesList) or (NotesList.ItemIndex < 0) then Exit;

	Entries := Module.Metadata.GetEntries;
	if NotesList.ItemIndex >= Entries.Count then Exit;

	Entry := Entries[NotesList.ItemIndex];
	if Entry.ID <> CurrentEntryID then
	begin
		CurrentEntryID := Entry.ID;
		UpdateEntryDisplay;
	end;
end;

procedure TNotesScreen.RefreshList;
var
	i: Integer;
	Entry: TMetadataEntry;
	ItemText: AnsiString;
	Entries: TList<TMetadataEntry>;
begin
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;

	NotesList.Clear;
	Entries := Module.Metadata.GetEntries;

	for i := 0 to Entries.Count - 1 do
	begin
		Entry := Entries[i];
		ItemText := Format('%d: %s [%s]', [Entry.ID, Entry.Title, FormatStatus(Entry.Status)]);
		NotesList.AddItem(ItemText);
	end;

	if NotesList.Items.Count > 0 then
	begin
		// Maintain cursor position if possible, otherwise select first item
		if (NotesList.Cursor.Y >= 0) and (NotesList.Cursor.Y < Entries.Count) then
		begin
			NotesList.ItemIndex := NotesList.Cursor.Y;
			CurrentEntryID := Entries[NotesList.Cursor.Y].ID;
		end
		else
		begin
			NotesList.ItemIndex := 0;
			NotesList.Cursor.Y := 0;
			NotesList.Cursor.X := 0;
			if Entries.Count > 0 then
				CurrentEntryID := Entries[0].ID;
		end;
		UpdateEntryDisplay;
	end
	else
	begin
		CurrentEntryID := -1;
		NotesList.Cursor.Y := -1;
		NotesList.Cursor.X := 0;
		UpdateEntryDisplay;
	end;
	
	CheckListSelection;
end;

procedure TNotesScreen.HandleNotesAction(ActionID: Integer);
var
	Entry: TMetadataEntry;
	NewTitle, NewBody: AnsiString;
	Ptr: TMetadataPointer;
	i, FixedCount: Integer;
	Entries: TList<TMetadataEntry>;
begin
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;

	case ActionID of
		ACTION_NEW:
		begin
			if Module.Metadata.GetEntryCount >= MAX_METADATA_ENTRIES then
			begin
				ModalDialog.ShowMessage('Notes', Format('Maximum %d notes reached. Delete some notes to add more.', [MAX_METADATA_ENTRIES]));
				Exit;
			end;

			Ptr := Module.Metadata.GetCurrentPointer;
			CurrentEntryID := Module.Metadata.AddEntry('New note', '', Ptr, msOpen);
			Module.Metadata.SaveToFile;
			
			// Refresh the list to include the new entry
			RefreshList;
			
			// Find and select the newly created entry
			Entries := Module.Metadata.GetEntries;
			for i := 0 to Entries.Count - 1 do
			begin
				if Entries[i].ID = CurrentEntryID then
				begin
					NotesList.ItemIndex := i;
					NotesList.Cursor.Y := i;
					NotesList.Cursor.X := 0;
					NotesList.CursorInStatus := False;
					CurrentEntryID := Entries[i].ID;
					UpdateEntryDisplay;
					NotesList.Paint; // Force repaint to show the new entry
					Break;
				end;
			end;
		end;

		ACTION_DELETE:
		begin
			if CurrentEntryID >= 0 then
			begin
				Module.Metadata.DeleteEntry(CurrentEntryID);
				Module.Metadata.SaveToFile;
				CurrentEntryID := -1;
				RefreshList;
				if NotesList.Items.Count > 0 then
				begin
					NotesList.ItemIndex := 0;
					Entry := Module.Metadata.GetEntries[0];
					CurrentEntryID := Entry.ID;
					UpdateEntryDisplay;
				end;
				NotesList.Paint; // Force repaint to show updated list immediately
			end;
		end;

		ACTION_GOTO:
		begin
			if CurrentEntryID >= 0 then
			begin
				Entry := Module.Metadata.GetEntry(CurrentEntryID);
				Module.Metadata.NavigateToPointer(Entry.Pointer);
			end;
		end;

		ACTION_SETPOINTER:
		begin
			if CurrentEntryID >= 0 then
			begin
				Entry := Module.Metadata.GetEntry(CurrentEntryID);
				Ptr := Module.Metadata.GetCurrentPointer;
				Module.Metadata.UpdateEntry(CurrentEntryID, Entry.Title, Entry.Body, Entry.Status);
				// Recreate entry with new pointer
				Module.Metadata.DeleteEntry(CurrentEntryID);
				CurrentEntryID := Module.Metadata.AddEntry(Entry.Title, Entry.Body, Ptr, Entry.Status);
				Module.Metadata.SaveToFile;
				RefreshList;
			end;
		end;

		ACTION_SAVE:
		begin
			if CurrentEntryID >= 0 then
		begin
			NewTitle := Copy(TitleEdit.Caption, 1, MAX_TITLE_LENGTH);
			NewBody := Copy(BodyEdit.Text, 1, MAX_BODY_LENGTH);
				Module.Metadata.UpdateEntry(CurrentEntryID, NewTitle, NewBody, CurrentStatus);
				Module.Metadata.SaveToFile;
				RefreshList;
			end;
		end;

		ACTION_CYCLESTATUS:
		begin
			if CurrentEntryID >= 0 then
			begin
				// Cycle through status values
				case CurrentStatus of
					msOpen:   CurrentStatus := msTodo;
					msTodo:  CurrentStatus := msFixme;
					msFixme: CurrentStatus := msWip;
					msWip:   CurrentStatus := msDone;
					msDone:  CurrentStatus := msOpen;
					msClosed: CurrentStatus := msOpen;
				end;
				StatusLabel.SetCaption('Status: ' + FormatStatus(CurrentStatus));
				// Auto-save status change
				Entry := Module.Metadata.GetEntry(CurrentEntryID);
				Module.Metadata.UpdateEntry(CurrentEntryID, Entry.Title, Entry.Body, CurrentStatus);
				Module.Metadata.SaveToFile;
				RefreshList;
			end;
		end;

		ACTION_FIXALL:
		begin
			if Assigned(Module.Metadata) then
			begin
				FixedCount := Module.Metadata.FixInvalidPointers;
				if FixedCount > 0 then
					ModalDialog.ShowMessage('Notes', Format('Fixed %d invalid pointer(s).', [FixedCount]))
				else
					ModalDialog.ShowMessage('Notes', 'No invalid pointers found.');
				Module.Metadata.SaveToFile;
				RefreshList;
			end;
		end;
	end;
end;

function TNotesScreen.KeyDown(var Key: Integer; Shift: TShiftState): Boolean;
begin
	Result := False;
	
	// Handle Esc to go back to previous screen
	if Key = 27 then // Esc
	begin
		HandleNotesAction(ACTION_SAVE); // Auto-save before leaving
		ChangeScreen(TCWEScreen(Editor));
		Result := True;
		Exit;
	end;
	
	// Handle Ctrl+S or Ctrl+Tab to cycle status
	if ((Key = Ord('S')) or (Key = 9)) and (ssCtrl in Shift) then // Ctrl+S or Ctrl+Tab
	begin
		HandleNotesAction(ACTION_CYCLESTATUS);
		Result := True;
		Exit;
	end;
	
	// Handle Enter to save
	if Key = 13 then // Enter
	begin
			if ActiveControl = TitleEdit then
		begin
			HandleNotesAction(ACTION_SAVE);
			ActiveControl := BodyEdit;
			Result := True;
			Exit;
		end;
	end;
	
	// Handle Delete key to delete entry
	if (Key = 127) and (not (ssCtrl in Shift)) then // Delete (not Ctrl+Delete)
	begin
		if ActiveControl = NotesList then
		begin
			HandleNotesAction(ACTION_DELETE);
			Result := True;
			Exit;
		end;
	end;
	
	// Let parent handle other keys
	if not Result then
		Result := inherited KeyDown(Key, Shift);
end;

constructor TNotesScreen.Create(var Con: TConsole; const sCaption, sID: AnsiString);
var
	ListW, EditX, EditW, EditH: Integer;
	SepLabel, TitleLbl, BodyLbl: TCWELabel;
begin
	inherited;
	
	CurrentEntryID := -1;
	CurrentStatus := msOpen;
	UpdatingDisplay := False;
	
	RegisterScreenLayout(Self, 'Notes');
	
	// Add header title (similar to Sample List F3)
	AddHeader('Metadata.Notes');
	
	ListW := Console.Width div 3;
	EditX := ListW + 6; // Moved 4 chars to the right (was +2, now +6)
	EditW := Console.Width - EditX - 4; // Made 3 chars narrower (was -1, now -4)
	EditH := Console.Height - 10;
	
	// List of entries (custom paint)
	NotesList := TNotesList.Create(Self, '', 'NotesList',
		Types.Rect(1, 3, ListW, Console.Height - 3), True);
	RegisterLayoutControl(NotesList, CTRLKIND_BOX, False, True, True);
	NotesList.OnChange := ListSelectionChanged;
	
	// Summary header (read-only)
	SummaryLabel := TCWELabel.Create(Self, '', 'Summary',
		Types.Rect(EditX, 3, EditX + EditW, 4), True);
	SummaryLabel.SetColors(3, 1);
	RegisterLayoutControl(SummaryLabel, CTRLKIND_LABEL, False, False, False);
	
	// Separator
	SepLabel := TCWELabel.Create(Self, StringOfChar('-', EditW), 'Separator',
		Types.Rect(EditX, 4, EditX + EditW, 5), True);
	RegisterLayoutControl(SepLabel, CTRLKIND_LABEL, False, False, False);
	
	// Title edit
	TitleEdit := TCWEEdit.Create(Self, '', 'TitleEdit',
		Types.Rect(EditX, 6, EditX + EditW, 7), True);
	TitleEdit.MaxLength := MAX_TITLE_LENGTH;
	TitleEdit.SetBorder(True, False, True, True);
	TitleEdit.ReportAnyChange := True;
	TitleEdit.OnChange := TitleEditChanged;
	RegisterLayoutControl(TitleEdit, CTRLKIND_BOX, False, True, True);
	
	// Status label (clickable dropdown)
	StatusLabel := TCWELabel.Create(Self, 'Status: open', 'StatusLabel',
		Types.Rect(EditX, 7, EditX + EditW, 8), True);
	StatusLabel.WantMouse := True;
	StatusLabel.WantHover := True;
	StatusLabel.OnMouseDown := StatusLabelMouseDown;
	RegisterLayoutControl(StatusLabel, CTRLKIND_LABEL, False, False, False);
	
	// Pointer label
	PointerLabel := TCWELabel.Create(Self, 'Pointer: None', 'PointerLabel',
		Types.Rect(EditX, 8, EditX + EditW, 9), True);
	RegisterLayoutControl(PointerLabel, CTRLKIND_LABEL, False, False, False);
	
	// Body edit (multiline support)
	BodyEdit := TMultiLineEdit.Create(Self, '', 'BodyEdit',
		Types.Rect(EditX, 10, EditX + EditW, EditH), True);
	BodyEdit.MaxLength := MAX_BODY_LENGTH;
	BodyEdit.SetBorder(True, False, True, True);
	BodyEdit.ReportAnyChange := True;
	BodyEdit.OnChange := BodyEditChanged;
	RegisterLayoutControl(BodyEdit, CTRLKIND_BOX, False, True, True);
	
	// Timestamps
	CreatedLabel := TCWELabel.Create(Self, 'Created: ', 'CreatedLabel',
		Types.Rect(EditX, EditH + 1, EditX + EditW, EditH + 2), True);
	CreatedLabel.SetColors(7, 1);
	RegisterLayoutControl(CreatedLabel, CTRLKIND_LABEL, False, False, False);
	
	UpdatedLabel := TCWELabel.Create(Self, 'Updated: ', 'UpdatedLabel',
		Types.Rect(EditX, EditH + 2, EditX + EditW, EditH + 3), True);
	UpdatedLabel.SetColors(7, 1);
	RegisterLayoutControl(UpdatedLabel, CTRLKIND_LABEL, False, False, False);
	
	// Action buttons
	BtnNew := TCWEButton.Create(Self, 'New', 'BtnNew',
		Types.Rect(EditX, Console.Height - 2, EditX + 8, Console.Height - 1));
	BtnNew.OnChange := ButtonNewClick;
	RegisterLayoutControl(BtnNew, CTRLKIND_BUTTON, False, True, True);
	
	BtnDelete := TCWEButton.Create(Self, 'Delete', 'BtnDelete',
		Types.Rect(EditX + 9, Console.Height - 2, EditX + 18, Console.Height - 1));
	BtnDelete.OnChange := ButtonDeleteClick;
	RegisterLayoutControl(BtnDelete, CTRLKIND_BUTTON, False, True, True);
	
	BtnGoto := TCWEButton.Create(Self, 'Go To', 'BtnGoto',
		Types.Rect(EditX + 19, Console.Height - 2, EditX + 27, Console.Height - 1));
	BtnGoto.OnChange := ButtonGotoClick;
	RegisterLayoutControl(BtnGoto, CTRLKIND_BUTTON, False, True, True);
	
	BtnSetPtr := TCWEButton.Create(Self, 'Set Ptr', 'BtnSetPtr',
		Types.Rect(EditX + 28, Console.Height - 2, EditX + 37, Console.Height - 1));
	BtnSetPtr.OnChange := ButtonSetPtrClick;
	RegisterLayoutControl(BtnSetPtr, CTRLKIND_BUTTON, False, True, True);
	
	BtnFixAll := TCWEButton.Create(Self, 'Fix All', 'BtnFixAll',
		Types.Rect(EditX + 38, Console.Height - 2, EditX + 47, Console.Height - 1));
	BtnFixAll.OnChange := ButtonFixAllClick;
	RegisterLayoutControl(BtnFixAll, CTRLKIND_BUTTON, False, True, True);
	
	ActiveControl := NotesList;
	
	LoadLayout(Self);
end;

procedure TNotesScreen.ListSelectionChanged(Sender: TCWEControl);
begin
	CheckListSelection;
end;

procedure TNotesScreen.ButtonNewClick(Sender: TCWEControl);
begin
	HandleNotesAction(ACTION_NEW);
end;

procedure TNotesScreen.ButtonDeleteClick(Sender: TCWEControl);
begin
	HandleNotesAction(ACTION_DELETE);
end;

procedure TNotesScreen.ButtonGotoClick(Sender: TCWEControl);
begin
	HandleNotesAction(ACTION_GOTO);
end;

procedure TNotesScreen.ButtonSetPtrClick(Sender: TCWEControl);
begin
	HandleNotesAction(ACTION_SETPOINTER);
end;

procedure TNotesScreen.ButtonFixAllClick(Sender: TCWEControl);
begin
	HandleNotesAction(ACTION_FIXALL);
end;

function TNotesScreen.EnsureNoteExists: Boolean;
var
	Ptr: TMetadataPointer;
	Entries: TList<TMetadataEntry>;
	SavedTitle, SavedBody: AnsiString;
begin
	Result := False;
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	
	// Check if we need to create a new note
	Entries := Module.Metadata.GetEntries;
	if (CurrentEntryID < 0) or (Entries.Count = 0) then
	begin
		// Create a new note if we're at max capacity, don't create
		if Module.Metadata.GetEntryCount >= MAX_METADATA_ENTRIES then
			Exit;
		
		// Save any text that was already typed before creating the note
		SavedTitle := TitleEdit.Caption;
		SavedBody := BodyEdit.Text;
		
		Ptr := Module.Metadata.GetCurrentPointer;
		CurrentEntryID := Module.Metadata.AddEntry(SavedTitle, SavedBody, Ptr, msOpen);
		Module.Metadata.SaveToFile;
		
		// Refresh list and select the new entry
		RefreshList;
		Entries := Module.Metadata.GetEntries;
		if Entries.Count > 0 then
		begin
			NotesList.ItemIndex := 0;
			NotesList.Cursor.Y := 0;
			NotesList.Cursor.X := 0;
			NotesList.CursorInStatus := False;
			CurrentEntryID := Entries[0].ID;
			// Restore the text that was typed
			TitleEdit.SetCaption(SavedTitle);
			BodyEdit.SetText(SavedBody);
			UpdateEntryDisplay;
			NotesList.Paint;
		end;
		Result := True;
	end
	else
		Result := True;
end;

procedure TNotesScreen.TitleEditChanged(Sender: TCWEControl);
begin
	// Prevent recursive calls when UpdateEntryDisplay sets the caption
	if UpdatingDisplay then Exit;
	
	// Ensure a note exists before saving title changes
	if EnsureNoteExists then
	begin
		// Auto-save title changes
		if CurrentEntryID >= 0 then
		begin
			HandleNotesAction(ACTION_SAVE);
		end;
	end;
end;

procedure TNotesScreen.BodyEditChanged(Sender: TCWEControl);
begin
	// Prevent recursive calls when UpdateEntryDisplay sets the text
	if UpdatingDisplay then Exit;
	
	// Ensure a note exists before saving body changes
	if EnsureNoteExists then
	begin
		// Auto-save body changes
		if CurrentEntryID >= 0 then
		begin
			HandleNotesAction(ACTION_SAVE);
		end;
	end;
end;

function TNotesScreen.StatusLabelMouseDown(Sender: TCWEControl; Button: TMouseButton; X, Y: Integer; P: TPoint): Boolean;
var
	sl: TStringList;
	Idx, i, W, H: Integer;
	B: Boolean;
	StatusList: TCWEList;
	StatusNames: array[TMetadataStatus] of AnsiString = ('open', 'todo', 'fixm', 'wip ', 'done', 'clsd');
	Status: TMetadataStatus;
begin
	Result := False;
	if Button <> mbLeft then Exit;
	if CurrentEntryID < 0 then Exit;
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	
	Result := True;
	
	sl := TStringList.Create;
	try
		// Add all status options
		for Status := Low(TMetadataStatus) to High(TMetadataStatus) do
			sl.Add(StatusNames[Status]);
		
		// Find current status index
		Idx := Ord(CurrentStatus);
		
		if sl.Count > 0 then
		begin
			W := 0;
			for i := 0 to sl.Count-1 do
			begin
				H := Length(sl[i]);
				if H > W then W := H;
			end;
			
			W := Math.Min(W + 3, Console.Width - 4);
			if W mod 2 <> 0 then Inc(W);
			W := Math.Max(W, 20);
			H := Math.Min(sl.Count + 5, Console.Height - 8);
			
			ModalDialog.CreateDialog(ACTION_SELECTSTATUS, Bounds(
				(Console.Width div 2) - (W div 2),
				(Console.Height div 2) - (H div 2), W, H), 'Select Status');
			
			// Figure out if a scrollbar is needed
			B := (sl.Count > H-5);
			i := W - 1;
			if B then Dec(i);
			
			StatusList := TCWEList.Create(ModalDialog.Dialog, '', 'StatusList', Types.Rect(1, 2, i, H-3), True);
			StatusList.CanCloseDialog := True;
			StatusList.Scrollbar.Visible := B;
			StatusList.Border.Pixel := True;
			
			for i := 0 to sl.Count-1 do
				StatusList.AddItem(sl[i]);
			StatusList.Select(Idx);
			
			with ModalDialog do
			begin
				AddResultButton(btnOK,     'OK',     1,   H-2, True);
				AddResultButton(btnCancel, 'Cancel', W-9, H-2, True);
				
				ButtonCallback := StatusSelectionCallback;
				Dialog.ActivateControl(StatusList);
				Show;
			end;
		end;
	finally
		sl.Free;
	end;
end;

procedure TNotesScreen.StatusSelectionCallback(ID: Word; ModalResult: TDialogButton; Tag: Integer; Data: Variant; Dlg: TCWEDialog);
var
	StatusList: TCWEList;
	Entry: TMetadataEntry;
	NewStatus: TMetadataStatus;
begin
	if (ModalResult <> btnOK) or (Dlg = nil) then Exit;
	if CurrentEntryID < 0 then Exit;
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	
	StatusList := Dlg.Dialog.FindControl('StatusList') as TCWEList;
	if StatusList = nil then Exit;
	if StatusList.ItemIndex < 0 then Exit;
	
	// Convert index to status
	NewStatus := TMetadataStatus(StatusList.ItemIndex);
	
	// Update entry
	Entry := Module.Metadata.GetEntry(CurrentEntryID);
	if Entry.ID > 0 then
	begin
		CurrentStatus := NewStatus;
		Module.Metadata.UpdateEntry(CurrentEntryID, Entry.Title, Entry.Body, CurrentStatus);
		Module.Metadata.SaveToFile;
		UpdateEntryDisplay;
		RefreshList;
	end;
end;

procedure TNotesScreen.Show;
begin
	inherited Show;
	// Refresh list when screen is shown
	if Assigned(Module) and Assigned(Module.Metadata) then
	begin
		RefreshList;
	end
	else
	begin
		if Assigned(NotesList) then
			NotesList.Clear;
		CurrentEntryID := -1;
		UpdateEntryDisplay;
	end;
end;

end.

