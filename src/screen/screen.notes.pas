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
	LENGTH_NOTETEXT = 22; // same as the F3 sample list (LENGTH_SAMPLETEXT)

type
	TNoteSortKey = (nskStatus, nskCreated, nskUpdated);

	TNotesList = class(TCWEList)
	private
		CursorInStatus: Boolean;
		LastEntryID: Integer;
		LastEntryTitle: AnsiString;
		// Push one undo snapshot per title-editing session (like the F3 sample name).
		procedure EnsureTitleUndo(const Entry: TMetadataEntry);
	public
		Cursor: TPoint;
		procedure Paint; override;
		function KeyDown(var Key: Integer; Shift: TShiftState): Boolean; override;
		function TextInput(var Key: Char): Boolean; override;
		function MouseDown(Button: TMouseButton; X, Y: Integer; P: TPoint): Boolean; override;
		constructor Create(Owner: TCWEControl; const sCaption, sID: AnsiString; const Bounds: TRect; IsProtected: Boolean = False); override;
	end;

	// Free 2D text canvas: the caret can be placed anywhere (arrow keys or mouse),
	// including past a line's end or below the last line. Typing there materializes
	// the position — padding the line with spaces and inserting blank lines as
	// needed. No soft-wrapping; long lines scroll horizontally.
	TMultiLineEdit = class(TCWEEdit)
	private
		FLines: TStringList;
		FCursorY: Integer;
		FLineOffset: Integer; // Vertical scroll offset
		function GetText: AnsiString;
		procedure SetText(const Value: AnsiString);
		function CurrentLine: AnsiString;
		procedure MaterializeCursor; // pad blank lines / spaces up to the caret
		procedure ScrollToCursor;    // keep the caret within the visible box
	public
		constructor Create(Owner: TCWEControl; const sCaption, sID: AnsiString; const Bounds: TRect; IsProtected: Boolean = False); override;
		destructor Destroy; override;
		function KeyDown(var Key: Integer; Shift: TShiftState): Boolean; override;
		function TextInput(var Key: Char): Boolean; override;
		function MouseDown(Button: TMouseButton; X, Y: Integer; P: TPoint): Boolean; override;
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
		BtnNew, BtnDelete, BtnGoto, BtnSetPtr, BtnFixAll: TCWEButton;
		BtnFilter, BtnSort: TCWEButton;
		CurrentEntryID: Integer;
		CurrentStatus: TMetadataStatus;
		UpdatingDisplay: Boolean; // Flag to prevent recursive calls

		// Filtered + sorted view of the entries the list renders/navigates.
		FView: array of Integer; // indices into Module.Metadata.GetEntries
		FFilterStatus: array[TMetadataStatus] of Boolean; // which statuses are shown
		FFilterBackup: array[TMetadataStatus] of Boolean; // snapshot for dialog cancel
		FSortKey: TNoteSortKey;
		FSortReverse: Boolean;
		FSortKeyBackup: TNoteSortKey;
		FSortReverseBackup: Boolean;
		FSortBtns: array[TNoteSortKey] of TCWEButton; // sort dialog option buttons
		FSortReverseBtn: TCWEButton;

		// Coalesce Title/Body field edits into one undo step per (note, field) session.
		FEditUndoEntryID: Integer;
		FEditUndoField: Integer; // 0 none, 1 title field, 2 body field

		procedure BeginTextUndo(FieldKind: Integer);
		procedure UpdateEntryDisplay;
		procedure RebuildView;
		function  ViewCount: Integer;
		function  ViewEntry(Index: Integer): TMetadataEntry;
		procedure SelectViewIndex(Index: Integer);
		procedure RefreshList;
		procedure RefreshCurrentEntry;
		procedure SaveCurrentEntryQuietly;
		procedure DeleteWithConfirm;
		procedure DeleteConfirmCallback(ID: Word; ModalResult: TDialogButton; Tag: Integer; Data: Variant; Dlg: TCWEDialog);
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
		procedure ButtonFilterClick(Sender: TCWEControl);
		procedure ButtonSortClick(Sender: TCWEControl);
		procedure FilterToggleClick(Sender: TCWEControl);
		procedure FilterDialogCallback(ID: Word; ModalResult: TDialogButton; Tag: Integer; Data: Variant; Dlg: TCWEDialog);
		procedure SortOptionClick(Sender: TCWEControl);
		procedure SortReverseClick(Sender: TCWEControl);
		procedure SortDialogCallback(ID: Word; ModalResult: TDialogButton; Tag: Integer; Data: Variant; Dlg: TCWEDialog);
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
	ACTION_FILTER = 9;
	ACTION_SORT = 10;

	SortKeyNames: array[TNoteSortKey] of AnsiString = ('Status', 'Created', 'Updated');

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

// Single source for the 4-character status labels shown in the list, the
// summary header and the status selector.
function FormatStatus(const Status: TMetadataStatus): AnsiString;
begin
	case Status of
		msOpen:   Result := 'open';
		msTodo:   Result := 'todo';
		msFixme:  Result := 'fix ';
		msWip:    Result := 'wip ';
		msDone:   Result := 'done';
		msClosed: Result := 'old ';
		msInfo:   Result := 'info';
	else
		Result := 'open';
	end;
end;

// Single source for the status display color.
function StatusColor(const Status: TMetadataStatus): Byte;
begin
	case Status of
		msOpen:   Result := 6;
		msTodo:   Result := 11;
		msFixme:  Result := 9;
		msWip:    Result := 14;
		msDone:   Result := 10;
		msClosed: Result := 7;
		msInfo:   Result := 3;
	else
		Result := 6;
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
	Scr: TNotesScreen;
	StatusStartX, MaxSlots: Integer;
begin
	Result := False;
	if Button <> mbLeft then Exit;
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	if not (Screen is TNotesScreen) then Exit;
	Scr := TNotesScreen(Screen);

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
		if (P.Y >= 0) and (P.Y < Scr.ViewCount) then
		begin
			Scr.CurrentEntryID := Scr.ViewEntry(P.Y).ID;
			Scr.StatusLabelMouseDown(nil, Button, X, Y, P);
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

	if (P.Y >= 0) and (P.Y < Scr.ViewCount) then
		Scr.CurrentEntryID := Scr.ViewEntry(P.Y).ID
	else
		Scr.CurrentEntryID := -1;
	Scr.UpdateEntryDisplay;

	Paint;
	Result := True;
end;

procedure TNotesList.EnsureTitleUndo(const Entry: TMetadataEntry);
begin
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	// A new session = a different note, or the title changed since our last edit.
	if (LastEntryID <> Entry.ID) or (LastEntryTitle <> Entry.Title) then
	begin
		Module.Metadata.PushUndo;
		LastEntryID := Entry.ID;
		LastEntryTitle := Entry.Title;
	end;
end;

function TNotesList.TextInput(var Key: Char): Boolean;
var
	Entry: TMetadataEntry;
	NewTitle: AnsiString;
	Scr: TNotesScreen;
begin
	Result := False;
	if not Focused then Exit;
	if CursorInStatus then Exit; // Don't edit when cursor is in status area
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	if not (Screen is TNotesScreen) then Exit;
	Scr := TNotesScreen(Screen);

	if (Cursor.Y < 0) or (Cursor.Y >= Scr.ViewCount) then Exit;

	Entry := Scr.ViewEntry(Cursor.Y);

	// One undo snapshot per editing session (before the first change).
	EnsureTitleUndo(Entry);

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
	Scr: TNotesScreen;
	MaxSlots: Integer;
begin
	Result := False;
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	if not (Screen is TNotesScreen) then Exit;
	Scr := TNotesScreen(Screen);

	MaxSlots := Rect.Bottom - Rect.Top;
	if MaxSlots > MAX_METADATA_ENTRIES then
		MaxSlots := MAX_METADATA_ENTRIES;

	// Allow navigation even if no entries exist (to show empty slots)
	if (Scr.ViewCount = 0) and (Cursor.Y >= MaxSlots) then Exit;

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
				if (Cursor.Y >= 0) and (Cursor.Y < Scr.ViewCount) then
				begin
					Entry := Scr.ViewEntry(Cursor.Y);
					Cursor.X := Min(Cursor.X, Min(Length(Entry.Title), LENGTH_NOTETEXT));
					Scr.CurrentEntryID := Entry.ID;
				end
				else
				begin
					Cursor.X := Min(Cursor.X, LENGTH_NOTETEXT);
					Scr.CurrentEntryID := -1;
				end;
				Scr.UpdateEntryDisplay;
				Result := True;
			end;

		ctrlkeyDOWN:
			if Cursor.Y < MaxSlots - 1 then
			begin
				Inc(Cursor.Y);
				ItemIndex := Cursor.Y;
				CursorInStatus := False;
				if (Cursor.Y >= 0) and (Cursor.Y < Scr.ViewCount) then
				begin
					Entry := Scr.ViewEntry(Cursor.Y);
					Cursor.X := Min(Cursor.X, Min(Length(Entry.Title), LENGTH_NOTETEXT));
					Scr.CurrentEntryID := Entry.ID;
				end
				else
				begin
					Cursor.X := Min(Cursor.X, LENGTH_NOTETEXT);
					Scr.CurrentEntryID := -1;
				end;
				Scr.UpdateEntryDisplay;
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
			if (Cursor.Y >= 0) and (Cursor.Y < Scr.ViewCount) then
			begin
				Entry := Scr.ViewEntry(Cursor.Y);
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
			if not CursorInStatus and (Cursor.Y >= 0) and (Cursor.Y < Scr.ViewCount) then
			begin
				Entry := Scr.ViewEntry(Cursor.Y);
				NewTitle := Entry.Title;
				if Cursor.X > 0 then
				begin
					EnsureTitleUndo(Entry);
					Delete(NewTitle, Cursor.X, 1);
					Dec(Cursor.X);
					Module.Metadata.UpdateEntry(Entry.ID, NewTitle, Entry.Body, Entry.Status);
					Module.Metadata.SaveToFile;
					LastEntryTitle := NewTitle;
					Scr.UpdateEntryDisplay;
					Result := True;
				end;
			end;

		ctrlkeyDELETE:
			if not CursorInStatus and (Cursor.Y >= 0) and (Cursor.Y < Scr.ViewCount) then
			begin
				Entry := Scr.ViewEntry(Cursor.Y);
				NewTitle := Entry.Title;
				if Cursor.X < Length(NewTitle) then
				begin
					EnsureTitleUndo(Entry);
					Delete(NewTitle, Cursor.X+1, 1);
					Module.Metadata.UpdateEntry(Entry.ID, NewTitle, Entry.Body, Entry.Status);
					Module.Metadata.SaveToFile;
					LastEntryTitle := NewTitle;
					Scr.UpdateEntryDisplay;
					Result := True;
				end;
			end;

		ctrlkeyRETURN:
			if CursorInStatus and (Cursor.Y >= 0) and (Cursor.Y < Scr.ViewCount) then
			begin
				// Open status dropdown when Enter is pressed on status
				Entry := Scr.ViewEntry(Cursor.Y);
				Scr.CurrentEntryID := Entry.ID;
				Scr.StatusLabelMouseDown(nil, mbLeft, 0, 0, Point(0, 0));
				Result := True;
			end;

	else
	begin
		// Swallow printable keys while editing an existing note's title so they
		// insert via TextInput instead of triggering global shortcuts (matches the
		// F3 sample list behaviour).
		if Focused and (not CursorInStatus)
			and (Cursor.Y >= 0) and (Cursor.Y < Scr.ViewCount)
			and (Key >= Ord(' ')) and (Key <= Ord('~'))
			and ((Shift = []) or (Shift = [ssShift])) then
			Result := True
		else
			Exit(False);
	end;
	end;

	if Result then
		Paint;
end;

procedure TNotesList.Paint;
var
	i, x, MaxSlots, SlotIndex: Integer;
	col: Byte;
	Entry: TMetadataEntry;
	Scr: TNotesScreen;
	TitleMaxLen: Integer;
	EntryMap: array of Integer; // Maps slot index to view index, or -1 if empty
begin
	if not Screen.Active then Exit;
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	if not (Screen is TNotesScreen) then Exit;
	Scr := TNotesScreen(Screen);

	Console.BeginUpdate;

	Console.FrameRect(Types.Rect(
		Rect.Left+3, Rect.Top, Rect.Right, Rect.Bottom), True, True, TConsole.COLOR_BLANK);

	MaxSlots := Rect.Bottom - Rect.Top;
	if MaxSlots > MAX_METADATA_ENTRIES then
		MaxSlots := MAX_METADATA_ENTRIES;

	// Build a map of slot index to view index
	SetLength(EntryMap, MaxSlots);
	for i := 0 to MaxSlots - 1 do
		EntryMap[i] := -1; // -1 means empty slot

	// Map visible (filtered+sorted) entries to slots
	for i := 0 to Min(Scr.ViewCount - 1, MaxSlots - 1) do
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
			Entry := Scr.ViewEntry(i);

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
				col := Data[2].Value; // same color as the F3 sample list "Play" status
		end
		else
		begin
			// Empty slot - show subtle dots instead of a number
			Console.Write('..', Rect.Left, Rect.Top+SlotIndex, 7);
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
			Console.Write(FormatStatus(Entry.Status), Rect.Left+3+LENGTH_NOTETEXT+1, Rect.Top+SlotIndex, col)
		else
			Console.Write('....', Rect.Left+3+LENGTH_NOTETEXT+1, Rect.Top+SlotIndex, col); // Empty status dots
	end;

	Console.EndUpdate;
end;

{ TMultiLineEdit }

constructor TMultiLineEdit.Create(Owner: TCWEControl; const sCaption, sID: AnsiString; const Bounds: TRect; IsProtected: Boolean);
begin
	inherited;
	FLines := TStringList.Create;
	FCursorY := 0;
	FLineOffset := 0;
	Cursor.X := 0; // base TCWEEdit sets -1; the canvas needs a valid caret from the start
	Cursor.Y := 0;
	WantMouse := True;
	if sCaption <> '' then
		SetText(sCaption)
	else
		FLines.Add('');
end;

destructor TMultiLineEdit.Destroy;
begin
	FLines.Free;
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
	if FLines.Count = 0 then
		FLines.Add('');
	FCursorY := 0;
	FLineOffset := 0;
	Cursor.X := 0;
	Offset := 0;
end;

function TMultiLineEdit.CurrentLine: AnsiString;
begin
	if (FCursorY >= 0) and (FCursorY < FLines.Count) then
		Result := FLines[FCursorY]
	else
		Result := '';
end;

// Ensure the backing store actually holds the caret position: append blank lines
// until row FCursorY exists, then right-pad that line with spaces up to Cursor.X.
// This is what lets the user click/arrow into empty space and just start typing.
procedure TMultiLineEdit.MaterializeCursor;
var
	Line: AnsiString;
begin
	if FCursorY < 0 then FCursorY := 0;
	if Cursor.X < 0 then Cursor.X := 0;
	while FLines.Count <= FCursorY do
		FLines.Add('');
	Line := FLines[FCursorY];
	while Length(Line) < Cursor.X do
		Line := Line + ' ';
	FLines[FCursorY] := Line;
end;

// Keep the caret inside the visible box, scrolling vertically and horizontally.
procedure TMultiLineEdit.ScrollToCursor;
var
	VisW: Integer;
begin
	if FCursorY < FLineOffset then
		FLineOffset := FCursorY
	else if FCursorY > FLineOffset + Height - 1 then
		FLineOffset := FCursorY - Height + 1;
	if FLineOffset < 0 then FLineOffset := 0;

	VisW := Rect.Right - Rect.Left;
	if VisW < 1 then VisW := 1;
	if Cursor.X < Offset then
		Offset := Cursor.X
	else if Cursor.X > Offset + VisW - 1 then
		Offset := Cursor.X - VisW + 1;
end;

function TMultiLineEdit.KeyDown(var Key: Integer; Shift: TShiftState): Boolean;
var
	Sc: ControlKeyNames;
	Line, Tail: AnsiString;
	MaxRow: Integer;
begin
	Result := True;
	Sc := ControlKeyNames(Shortcuts.Find(ControlKeys, Key, Shift));

	case Sc of
		ctrlkeyUP:
			if FCursorY > 0 then
				Dec(FCursorY)          // free vertical move: keep the column
			else
				Screen.BrowseControls(True);

		ctrlkeyDOWN:
		begin
			// Move down freely, including into the empty space below the text,
			// but don't scroll past the content and the visible box into nothing.
			MaxRow := FLines.Count - 1;
			if FLineOffset + Height - 1 > MaxRow then
				MaxRow := FLineOffset + Height - 1;
			if FCursorY < MaxRow then
				Inc(FCursorY)
			else
				Screen.BrowseControls(False);
		end;

		ctrlkeyLEFT:
			if Cursor.X > 0 then
				Dec(Cursor.X)
			else if FCursorY > 0 then
			begin
				Dec(FCursorY);
				Cursor.X := Length(CurrentLine);
			end;

		ctrlkeyRIGHT:
			if Cursor.X < MaxLength then
				Inc(Cursor.X);         // free horizontal move, past line end allowed

		ctrlkeyHOME:
			Cursor.X := 0;

		ctrlkeyEND:
			Cursor.X := Length(CurrentLine);

		ctrlkeyBACKSPACE:
		begin
			if Cursor.X > Length(CurrentLine) then
				Dec(Cursor.X)          // in virtual padding past the end: just step left
			else if Cursor.X > 0 then
			begin
				Line := CurrentLine;
				Delete(Line, Cursor.X, 1);
				FLines[FCursorY] := Line;
				Dec(Cursor.X);
			end
			else if (FCursorY > 0) and (FCursorY < FLines.Count) then
			begin
				// Join with the previous line
				Line := FLines[FCursorY];
				FLines.Delete(FCursorY);
				Dec(FCursorY);
				Cursor.X := Length(FLines[FCursorY]);
				FLines[FCursorY] := FLines[FCursorY] + Line;
			end
			else if FCursorY > 0 then
				Dec(FCursorY);         // virtual empty row: step up
			Change(ReportAnyChange);
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
					// Join the next line at the visible caret column
					while Length(Line) < Cursor.X do
						Line := Line + ' ';
					FLines[FCursorY] := Line + FLines[FCursorY+1];
					FLines.Delete(FCursorY+1);
				end;
				Change(ReportAnyChange);
			end;
		end;

		ctrlkeyRETURN:
		begin
			MaterializeCursor;
			Line := FLines[FCursorY];
			Tail := Copy(Line, Cursor.X+1, MaxInt);
			FLines[FCursorY] := Copy(Line, 1, Cursor.X);
			FLines.Insert(FCursorY+1, Tail);
			Inc(FCursorY);
			Cursor.X := 0;
			Change(ReportAnyChange);
		end;

	else
		Exit(False);
	end;

	ScrollToCursor;
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

	// Materialize the (possibly virtual) caret position, then insert the char.
	MaterializeCursor;
	Line := FLines[FCursorY];
	Insert(Key, Line, Cursor.X+1);
	FLines[FCursorY] := Line;
	Inc(Cursor.X);

	Result := True;
	ScrollToCursor;
	Change(ReportAnyChange);
	Paint;
end;

function TMultiLineEdit.MouseDown(Button: TMouseButton; X, Y: Integer; P: TPoint): Boolean;
begin
	Result := False;
	if Button <> mbLeft then Exit;
	if not Assigned(FLines) then Exit;

	// P is relative to the control; place the caret freely at that cell.
	FCursorY := FLineOffset + P.Y;
	if FCursorY < 0 then FCursorY := 0;
	Cursor.X := Offset + P.X;
	if Cursor.X < 0 then Cursor.X := 0;

	ScrollToCursor;
	Result := True;
	Paint;
end;

procedure TMultiLineEdit.Paint;
var
	C, B, y, row, cx, VisW: Integer;
	Line: AnsiString;
begin
	if not Screen.Active then Exit;
	if not Assigned(FLines) then Exit;

	DrawBorder;

	// Consistent green-on-background look regardless of focus (focus is shown by
	// the caret highlight), so the timestamp labels can share the background.
	C := ColorFore;
	B := ColorBack;

	VisW := Rect.Right - Rect.Left;
	if VisW < 1 then VisW := 1;

	for y := 0 to Height - 1 do
	begin
		row := y + FLineOffset;
		// Clear the whole interior row (text starts at the leftmost column).
		Console.FillRect(Types.Rect(Rect.Left, Rect.Top + y, Rect.Right, Rect.Top + y + 1), ' ', C, B);
		if (row >= 0) and (row < FLines.Count) then
		begin
			Line := Copy(FLines[row], Offset + 1, VisW);
			Console.Write(Line, Rect.Left, Rect.Top + y);
		end;

		// Caret (may sit past the line's end, on virtual padding space)
		if Focused and (row = FCursorY) then
		begin
			cx := Rect.Left + Cursor.X - Offset;
			if (cx >= Rect.Left) and (cx < Rect.Right) then
				Console.SetColor(cx, Rect.Top + y, TConsole.COLOR_TEXT, TConsole.COLOR_LIGHT);
		end;
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
		FCursorY := FLines.Count - 1;
		if FCursorY < 0 then FCursorY := 0;
		Cursor.X := Length(CurrentLine);
	end;
	ScrollToCursor;
	Paint;
end;

{ TNotesScreen }

// Push one undo snapshot when a text-edit session begins (a new note or a switch
// between the title and body fields). Coalesces continuous typing into one step.
procedure TNotesScreen.BeginTextUndo(FieldKind: Integer);
begin
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	if (FEditUndoEntryID <> CurrentEntryID) or (FEditUndoField <> FieldKind) then
	begin
		Module.Metadata.PushUndo;
		FEditUndoEntryID := CurrentEntryID;
		FEditUndoField := FieldKind;
	end;
end;

procedure TNotesScreen.UpdateEntryDisplay;
var
	Entry: TMetadataEntry;
begin
	// (Re)loading a note into the fields ends any text-edit undo session.
	FEditUndoEntryID := -1;
	FEditUndoField := 0;
	UpdatingDisplay := True;
	try
		if (CurrentEntryID < 0) or (not Assigned(Module)) or (not Assigned(Module.Metadata)) then
		begin
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
begin
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	if not Assigned(NotesList) or (NotesList.ItemIndex < 0) then Exit;
	if NotesList.ItemIndex >= ViewCount then Exit;

	Entry := ViewEntry(NotesList.ItemIndex);
	if Entry.ID <> CurrentEntryID then
	begin
		CurrentEntryID := Entry.ID;
		UpdateEntryDisplay;
	end;
end;

// Repaint the list from the model without rebinding the title/body edit
// controls, so the caret is not reset mid-typing.
procedure TNotesScreen.RefreshCurrentEntry;
begin
	if Assigned(NotesList) then
		NotesList.Paint;
end;

// Auto-save the current entry on every keystroke without rebinding the active
// edit control (TNotesList.Paint reads straight from the model, so a repaint
// suffices). Replaces the old RefreshList-based autosave that reset the caret
// and made typed text appear reversed.
procedure TNotesScreen.SaveCurrentEntryQuietly;
var
	NewTitle, NewBody: AnsiString;
begin
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	if CurrentEntryID < 0 then Exit;
	NewTitle := Copy(TitleEdit.Caption, 1, MAX_TITLE_LENGTH);
	NewBody  := Copy(BodyEdit.Text, 1, MAX_BODY_LENGTH);
	Module.Metadata.UpdateEntry(CurrentEntryID, NewTitle, NewBody, CurrentStatus);
	Module.Metadata.SaveToFile;
	RefreshCurrentEntry;
end;

// Build FView: the indices (into GetEntries) that pass the status filter, in the
// chosen sort order. This is what the list renders and navigates.
procedure TNotesScreen.RebuildView;
var
	Entries: TList<TMetadataEntry>;
	i, j, n: Integer;
	tmp: Integer;
	function Less(a, b: Integer): Boolean;
	var
		ea, eb: TMetadataEntry;
	begin
		ea := Entries[a];
		eb := Entries[b];
		case FSortKey of
			nskStatus:
				if Ord(ea.Status) <> Ord(eb.Status) then
					Exit(Ord(ea.Status) < Ord(eb.Status));
			nskUpdated:
				if ea.UpdatedAt <> eb.UpdatedAt then
					Exit(ea.UpdatedAt < eb.UpdatedAt);
		else // nskCreated
			if ea.CreatedAt <> eb.CreatedAt then
				Exit(ea.CreatedAt < eb.CreatedAt);
		end;
		Result := ea.ID < eb.ID; // stable tie-break
	end;
begin
	SetLength(FView, 0);
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	Entries := Module.Metadata.GetEntries;

	// filter
	n := 0;
	for i := 0 to Entries.Count - 1 do
		if FFilterStatus[Entries[i].Status] then
		begin
			SetLength(FView, n + 1);
			FView[n] := i;
			Inc(n);
		end;

	// simple insertion sort (list is small, <= 100 entries)
	for i := 1 to High(FView) do
	begin
		tmp := FView[i];
		j := i - 1;
		while (j >= 0) and Less(tmp, FView[j]) do
		begin
			FView[j + 1] := FView[j];
			Dec(j);
		end;
		FView[j + 1] := tmp;
	end;

	if FSortReverse then
		for i := 0 to (Length(FView) div 2) - 1 do
		begin
			tmp := FView[i];
			FView[i] := FView[High(FView) - i];
			FView[High(FView) - i] := tmp;
		end;
end;

function TNotesScreen.ViewCount: Integer;
begin
	Result := Length(FView);
end;

function TNotesScreen.ViewEntry(Index: Integer): TMetadataEntry;
var
	Entries: TList<TMetadataEntry>;
begin
	FillChar(Result, SizeOf(Result), 0);
	if (Index < 0) or (Index >= Length(FView)) then Exit;
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	Entries := Module.Metadata.GetEntries;
	if FView[Index] < Entries.Count then
		Result := Entries[FView[Index]];
end;

// Point the list cursor and CurrentEntryID at the given view row.
procedure TNotesScreen.SelectViewIndex(Index: Integer);
begin
	if ViewCount = 0 then
	begin
		CurrentEntryID := -1;
		NotesList.Cursor.Y := -1;
		NotesList.Cursor.X := 0;
		NotesList.ItemIndex := -1;
		Exit;
	end;
	if Index < 0 then Index := 0;
	if Index >= ViewCount then Index := ViewCount - 1;
	NotesList.Cursor.Y := Index;
	NotesList.Cursor.X := 0;
	NotesList.ItemIndex := Index;
	NotesList.CursorInStatus := False;
	CurrentEntryID := ViewEntry(Index).ID;
end;

procedure TNotesScreen.RefreshList;
var
	i, sel: Integer;
begin
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;

	RebuildView;

	// keep enough list items for the visible slots (display reads the model)
	NotesList.Clear;
	for i := 0 to ViewCount - 1 do
		NotesList.AddItem('');

	// Try to keep the previously selected entry selected; else keep the row.
	sel := -1;
	if CurrentEntryID >= 0 then
		for i := 0 to ViewCount - 1 do
			if ViewEntry(i).ID = CurrentEntryID then
			begin
				sel := i;
				Break;
			end;
	if sel < 0 then
		sel := NotesList.Cursor.Y;
	SelectViewIndex(sel);
	UpdateEntryDisplay;
	CheckListSelection;
	// Repaint so the rebuilt view is shown immediately (e.g. when the screen is
	// first shown after import, before any navigation).
	if Assigned(NotesList) then
		NotesList.Paint;
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
			Module.Metadata.PushUndo;
			CurrentEntryID := Module.Metadata.AddEntry('New note', '', Ptr, msOpen);
			Module.Metadata.SaveToFile;

			// RefreshList rebuilds the view and re-selects CurrentEntryID (the new
			// note) at its filtered+sorted position.
			RefreshList;
			NotesList.Paint;
		end;

		ACTION_DELETE:
		begin
			if CurrentEntryID >= 0 then
			begin
				Module.Metadata.PushUndo;
				Module.Metadata.DeleteEntry(CurrentEntryID);
				Module.Metadata.SaveToFile;
				CurrentEntryID := -1;
				RefreshList; // selects a nearby row in the rebuilt view
				NotesList.Paint;
			end;
		end;

		ACTION_GOTO:
		begin
			if CurrentEntryID >= 0 then
			begin
				Entry := Module.Metadata.GetEntry(CurrentEntryID);
				// Switch to the editor (F2) screen first, otherwise NavigateToPointer
				// paints the pattern editor on top of the Notes screen and corrupts it.
				ChangeScreen(TCWEScreen(Editor));
				Module.Metadata.NavigateToPointer(Entry.Pointer);
			end;
		end;

		ACTION_SETPOINTER:
		begin
			if CurrentEntryID >= 0 then
			begin
				// Update the pointer in place — keep the note's ID and position
				// (the old delete+re-add reassigned the ID, making numbers jump).
				Ptr := Module.Metadata.GetCurrentPointer;
				Module.Metadata.PushUndo;
				Module.Metadata.UpdatePointer(CurrentEntryID, Ptr);
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
					msTodo:   CurrentStatus := msFixme;
					msFixme:  CurrentStatus := msWip;
					msWip:    CurrentStatus := msDone;
					msDone:   CurrentStatus := msClosed;
					msClosed: CurrentStatus := msInfo;
					msInfo:   CurrentStatus := msOpen;
				end;
				StatusLabel.SetCaption('Status: ' + FormatStatus(CurrentStatus));
				// Auto-save status change
				Entry := Module.Metadata.GetEntry(CurrentEntryID);
				Module.Metadata.PushUndo;
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
	
	// Undo / Redo (Ctrl+Z / Ctrl+Y), like the other editors.
	if (ssCtrl in Shift) and (Key = Ord('Z')) then
	begin
		if Assigned(Module) and Assigned(Module.Metadata) and Module.Metadata.Undo then
		begin
			Module.Metadata.SaveToFile;
			CurrentEntryID := -1; // let RefreshList reselect a valid row
			RefreshList;
			NotesList.Paint;
		end;
		Result := True;
		Exit;
	end;
	if (ssCtrl in Shift) and (Key = Ord('Y')) then
	begin
		if Assigned(Module) and Assigned(Module.Metadata) and Module.Metadata.Redo then
		begin
			Module.Metadata.SaveToFile;
			CurrentEntryID := -1;
			RefreshList;
			NotesList.Paint;
		end;
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
			DeleteWithConfirm;
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
	st: TMetadataStatus;
begin
	inherited;

	CurrentEntryID := -1;
	CurrentStatus := msOpen;
	UpdatingDisplay := False;
	FEditUndoEntryID := -1;
	FEditUndoField := 0;

	// Filter/sort defaults: show everything except 'old' and 'done';
	// sort by creation time, oldest first.
	for st := Low(TMetadataStatus) to High(TMetadataStatus) do
		FFilterStatus[st] := not (st in [msClosed, msDone]);
	FSortKey := nskCreated;
	FSortReverse := False;

	RegisterScreenLayout(Self, 'Notes');
	
	// Add header title (similar to Sample List F3)
	AddHeader('Metadata.Notes');
	
	// Size the list to its content: number(3) + title(22) + separator(1) +
	// status(4) ~= 30 cols, so titles get the full F3 width while the status
	// stays a tight 4-char column (no wasted empty area after it).
	ListW := 31;
	EditX := ListW + 2;
	EditW := Console.Width - EditX - 1;
	EditH := Console.Height - 10;
	
	// List of entries (custom paint)
	NotesList := TNotesList.Create(Self, '', 'NotesList',
		Types.Rect(1, 3, ListW, Console.Height - 3), True);
	RegisterLayoutControl(NotesList, CTRLKIND_BOX, False, True, True);
	NotesList.OnChange := ListSelectionChanged;
	
	// Summary header (read-only)
	// Title edit
	TitleEdit := TCWEEdit.Create(Self, '', 'TitleEdit',
		Types.Rect(EditX, 4, EditX + EditW, 5), True);
	TitleEdit.MaxLength := MAX_TITLE_LENGTH;
	TitleEdit.SetBorder(True, False, True, True);
	TitleEdit.ReportAnyChange := True;
	TitleEdit.OnChange := TitleEditChanged;
	RegisterLayoutControl(TitleEdit, CTRLKIND_BOX, False, True, True);

	// Status label (clickable dropdown)
	StatusLabel := TCWELabel.Create(Self, 'Status: open', 'StatusLabel',
		Types.Rect(EditX, 5, EditX + EditW, 6), True);
	StatusLabel.WantMouse := True;
	StatusLabel.WantHover := True;
	StatusLabel.OnMouseDown := StatusLabelMouseDown;
	RegisterLayoutControl(StatusLabel, CTRLKIND_LABEL, False, False, False);

	// Pointer label
	PointerLabel := TCWELabel.Create(Self, 'Pointer: None', 'PointerLabel',
		Types.Rect(EditX, 6, EditX + EditW, 7), True);
	RegisterLayoutControl(PointerLabel, CTRLKIND_LABEL, False, False, False);

	// Body edit (multiline text canvas) — starts two rows higher now that the
	// summary and separator rows are gone.
	BodyEdit := TMultiLineEdit.Create(Self, '', 'BodyEdit',
		Types.Rect(EditX, 8, EditX + EditW, EditH), True);
	BodyEdit.MaxLength := MAX_BODY_LENGTH;
	BodyEdit.SetBorder(True, False, True, True);
	BodyEdit.ReportAnyChange := True;
	BodyEdit.ColorFore := 6; // green, matching the note title list
	BodyEdit.OnChange := BodyEditChanged;
	RegisterLayoutControl(BodyEdit, CTRLKIND_BOX, False, True, True);

	// Timestamps — default label colors (text on the beige panel), matching the
	// Status/Pointer labels.
	CreatedLabel := TCWELabel.Create(Self, 'Created: ', 'CreatedLabel',
		Types.Rect(EditX, EditH + 1, EditX + EditW, EditH + 2), True);
	RegisterLayoutControl(CreatedLabel, CTRLKIND_LABEL, False, False, False);

	UpdatedLabel := TCWELabel.Create(Self, 'Updated: ', 'UpdatedLabel',
		Types.Rect(EditX, EditH + 2, EditX + EditW, EditH + 3), True);
	RegisterLayoutControl(UpdatedLabel, CTRLKIND_LABEL, False, False, False);

	// Filter / Sort (open popups) — below the timestamps
	BtnFilter := TCWEButton.Create(Self, 'Filter', 'BtnFilter',
		Types.Rect(EditX, EditH + 3, EditX + 10, EditH + 4));
	BtnFilter.OnChange := ButtonFilterClick;
	RegisterLayoutControl(BtnFilter, CTRLKIND_BUTTON, False, True, True);

	BtnSort := TCWEButton.Create(Self, 'Sort', 'BtnSort',
		Types.Rect(EditX + 11, EditH + 3, EditX + 21, EditH + 4));
	BtnSort.OnChange := ButtonSortClick;
	RegisterLayoutControl(BtnSort, CTRLKIND_BUTTON, False, True, True);

	// Action buttons — along the bottom, under the (now wide) list.
	BtnNew := TCWEButton.Create(Self, 'New', 'BtnNew',
		Types.Rect(1, Console.Height - 2, 9, Console.Height - 1));
	BtnNew.OnChange := ButtonNewClick;
	RegisterLayoutControl(BtnNew, CTRLKIND_BUTTON, False, True, True);

	BtnDelete := TCWEButton.Create(Self, 'Delete', 'BtnDelete',
		Types.Rect(10, Console.Height - 2, 19, Console.Height - 1));
	BtnDelete.OnChange := ButtonDeleteClick;
	RegisterLayoutControl(BtnDelete, CTRLKIND_BUTTON, False, True, True);

	BtnGoto := TCWEButton.Create(Self, 'Go To', 'BtnGoto',
		Types.Rect(20, Console.Height - 2, 28, Console.Height - 1));
	BtnGoto.OnChange := ButtonGotoClick;
	RegisterLayoutControl(BtnGoto, CTRLKIND_BUTTON, False, True, True);

	BtnSetPtr := TCWEButton.Create(Self, 'Set Ptr', 'BtnSetPtr',
		Types.Rect(29, Console.Height - 2, 38, Console.Height - 1));
	BtnSetPtr.OnChange := ButtonSetPtrClick;
	RegisterLayoutControl(BtnSetPtr, CTRLKIND_BUTTON, False, True, True);

	BtnFixAll := TCWEButton.Create(Self, 'Fix All', 'BtnFixAll',
		Types.Rect(39, Console.Height - 2, 48, Console.Height - 1));
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
	DeleteWithConfirm;
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

// ---- Filter popup -------------------------------------------------------

procedure TNotesScreen.ButtonFilterClick(Sender: TCWEControl);
var
	W, H, y: Integer;
	st: TMetadataStatus;
	Btn: TCWEButton;
begin
	// Snapshot for Cancel.
	for st := Low(TMetadataStatus) to High(TMetadataStatus) do
		FFilterBackup[st] := FFilterStatus[st];

	W := 22;
	H := (Ord(High(TMetadataStatus)) + 1) + 5; // one row per status + margins/buttons
	ModalDialog.CreateDialog(ACTION_FILTER, Bounds(
		(Console.Width div 2) - (W div 2),
		(Console.Height div 2) - (H div 2), W, H), 'Show statuses');

	y := 2;
	for st := Low(TMetadataStatus) to High(TMetadataStatus) do
	begin
		// 1x1 toggle button (shows a checkmark when down), like F3 "Repeat".
		Btn := TCWEButton.Create(ModalDialog.Dialog, ' ', 'flt' + IntToStr(Ord(st)),
			Bounds(2, y, 1, 1));
		Btn.Toggle := True;
		Btn.Tag := Ord(st);
		Btn.Down := FFilterStatus[st];
		Btn.OnChange := FilterToggleClick;
		TCWELabel.Create(ModalDialog.Dialog, Trim(FormatStatus(st)),
			'fltl' + IntToStr(Ord(st)), Bounds(4, y, W - 6, 1), True);
		Inc(y);
	end;

	with ModalDialog do
	begin
		AddResultButton(btnOK,     'OK',     2,      H - 2, True);
		AddResultButton(btnCancel, 'Cancel', W - 10, H - 2, False);
		ButtonCallback := FilterDialogCallback;
		Show;
	end;
end;

procedure TNotesScreen.FilterToggleClick(Sender: TCWEControl);
begin
	if not (Sender is TCWEButton) then Exit;
	FFilterStatus[TMetadataStatus(TCWEButton(Sender).Tag)] := TCWEButton(Sender).Down;
end;

procedure TNotesScreen.FilterDialogCallback(ID: Word; ModalResult: TDialogButton;
	Tag: Integer; Data: Variant; Dlg: TCWEDialog);
var
	st: TMetadataStatus;
begin
	if ModalResult = btnCancel then
		for st := Low(TMetadataStatus) to High(TMetadataStatus) do
			FFilterStatus[st] := FFilterBackup[st];
	RefreshList;
	if Assigned(NotesList) then NotesList.Paint;
end;

// ---- Sort popup ---------------------------------------------------------

procedure TNotesScreen.ButtonSortClick(Sender: TCWEControl);
var
	W, H, y: Integer;
	k: TNoteSortKey;
begin
	FSortKeyBackup := FSortKey;
	FSortReverseBackup := FSortReverse;

	W := 22;
	H := (Ord(High(TNoteSortKey)) + 1) + 1 + 5; // options + reverse + margins/buttons
	ModalDialog.CreateDialog(ACTION_SORT, Bounds(
		(Console.Width div 2) - (W div 2),
		(Console.Height div 2) - (H div 2), W, H), 'Sort by');

	y := 2;
	for k := Low(TNoteSortKey) to High(TNoteSortKey) do
	begin
		// Toggle buttons used as radio options (see SortOptionClick).
		FSortBtns[k] := TCWEButton.Create(ModalDialog.Dialog, ' ',
			'srt' + IntToStr(Ord(k)), Bounds(2, y, 1, 1));
		FSortBtns[k].Toggle := True;
		FSortBtns[k].Tag := Ord(k);
		FSortBtns[k].Down := (FSortKey = k);
		FSortBtns[k].OnChange := SortOptionClick;
		TCWELabel.Create(ModalDialog.Dialog, SortKeyNames[k],
			'srtl' + IntToStr(Ord(k)), Bounds(4, y, W - 6, 1), True);
		Inc(y);
	end;

	FSortReverseBtn := TCWEButton.Create(ModalDialog.Dialog, ' ', 'srtRev',
		Bounds(2, y, 1, 1));
	FSortReverseBtn.Toggle := True;
	FSortReverseBtn.Down := FSortReverse;
	FSortReverseBtn.OnChange := SortReverseClick;
	TCWELabel.Create(ModalDialog.Dialog, 'Reverse', 'srtRevL', Bounds(4, y, W - 6, 1), True);

	with ModalDialog do
	begin
		AddResultButton(btnOK,     'OK',     2,      H - 2, True);
		AddResultButton(btnCancel, 'Cancel', W - 10, H - 2, False);
		ButtonCallback := SortDialogCallback;
		Show;
	end;
end;

procedure TNotesScreen.SortOptionClick(Sender: TCWEControl);
var
	k: TNoteSortKey;
begin
	if not (Sender is TCWEButton) then Exit;
	FSortKey := TNoteSortKey(TCWEButton(Sender).Tag);
	// Radio behaviour: only the chosen key stays down (re-checks it even if the
	// click toggled it off).
	for k := Low(TNoteSortKey) to High(TNoteSortKey) do
		if Assigned(FSortBtns[k]) then
			FSortBtns[k].Down := (FSortKey = k);
end;

procedure TNotesScreen.SortReverseClick(Sender: TCWEControl);
begin
	if Sender is TCWEButton then
		FSortReverse := TCWEButton(Sender).Down;
end;

procedure TNotesScreen.SortDialogCallback(ID: Word; ModalResult: TDialogButton;
	Tag: Integer; Data: Variant; Dlg: TCWEDialog);
var
	k: TNoteSortKey;
begin
	if ModalResult = btnCancel then
	begin
		FSortKey := FSortKeyBackup;
		FSortReverse := FSortReverseBackup;
	end;
	// Dialog controls are freed on close; drop the stale references.
	for k := Low(TNoteSortKey) to High(TNoteSortKey) do
		FSortBtns[k] := nil;
	FSortReverseBtn := nil;
	RefreshList;
	if Assigned(NotesList) then NotesList.Paint;
end;

// Ask before destroying a note; offer to mark it 'old' instead (notes are
// ticket-like, and keeping them as 'old' preserves the running ID history).
procedure TNotesScreen.DeleteWithConfirm;
var
	W, H: Integer;
begin
	if CurrentEntryID < 0 then Exit;
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;

	W := 44;
	H := 8;
	ModalDialog.CreateDialog(ACTION_DELETE, Bounds(
		(Console.Width div 2) - (W div 2),
		(Console.Height div 2) - (H div 2), W, H), 'Delete note');

	TCWELabel.Create(ModalDialog.Dialog, 'Delete this note permanently?',
		'DelMsg1', Types.Rect(2, 2, W-1, 3), True);
	TCWELabel.Create(ModalDialog.Dialog, 'Set it to ''old'' instead to keep it.',
		'DelMsg2', Types.Rect(2, 3, W-1, 4), True);

	with ModalDialog do
	begin
		AddResultButton(btnYes,    'Set old', 2,    H-2, True);
		AddResultButton(btnNo,     'Delete',  13,   H-2, False);
		AddResultButton(btnCancel, 'Cancel',  W-10, H-2, False);
		ButtonCallback := DeleteConfirmCallback;
		Show;
	end;
end;

procedure TNotesScreen.DeleteConfirmCallback(ID: Word; ModalResult: TDialogButton;
	Tag: Integer; Data: Variant; Dlg: TCWEDialog);
var
	Entry: TMetadataEntry;
begin
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;
	if CurrentEntryID < 0 then Exit;

	case ModalResult of
		btnYes: // Set as 'old' (msClosed) instead of deleting
		begin
			Entry := Module.Metadata.GetEntry(CurrentEntryID);
			Module.Metadata.PushUndo;
			Module.Metadata.UpdateEntry(CurrentEntryID, Entry.Title, Entry.Body, msClosed);
			Module.Metadata.SaveToFile;
			CurrentStatus := msClosed;
			RefreshList;
		end;
		btnNo: // Confirm permanent deletion
			HandleNotesAction(ACTION_DELETE);
		btnCancel: ; // do nothing
	end;
end;

function TNotesScreen.EnsureNoteExists: Boolean;
var
	Ptr: TMetadataPointer;
	SavedTitle, SavedBody: AnsiString;
begin
	Result := False;
	if not Assigned(Module) or not Assigned(Module.Metadata) then Exit;

	// Need a note to edit?
	if (CurrentEntryID < 0) or (Module.Metadata.GetEntryCount = 0) then
	begin
		// Don't create if we're at max capacity
		if Module.Metadata.GetEntryCount >= MAX_METADATA_ENTRIES then
			Exit;

		// Save any text that was already typed before creating the note
		SavedTitle := TitleEdit.Caption;
		SavedBody := BodyEdit.Text;

		Ptr := Module.Metadata.GetCurrentPointer;
		Module.Metadata.PushUndo;
		CurrentEntryID := Module.Metadata.AddEntry(SavedTitle, SavedBody, Ptr, msOpen);
		Module.Metadata.SaveToFile;

		// RefreshList rebuilds the view and re-selects the new note by ID.
		RefreshList;

		// Restore the text that was typed, keeping the caret at the end so
		// continued typing appends (don't call UpdateEntryDisplay here — it would
		// re-set the body with the caret at 0 and reverse the text).
		TitleEdit.SetCaption(SavedTitle);
		TitleEdit.Cursor.X := Length(SavedTitle);
		BodyEdit.SetCaption(SavedBody); // SetCaption leaves caret at end
		NotesList.Paint;
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
		// Auto-save title changes without rebinding the edit control
		if CurrentEntryID >= 0 then
		begin
			BeginTextUndo(1);
			SaveCurrentEntryQuietly;
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
		// Auto-save body changes without rebinding the edit control (otherwise
		// the caret resets to 0 and typed text comes out reversed)
		if CurrentEntryID >= 0 then
		begin
			BeginTextUndo(2);
			SaveCurrentEntryQuietly;
		end;
	end;
end;

function TNotesScreen.StatusLabelMouseDown(Sender: TCWEControl; Button: TMouseButton; X, Y: Integer; P: TPoint): Boolean;
var
	sl: TStringList;
	Idx, i, W, H: Integer;
	B: Boolean;
	StatusList: TCWEList;
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
			sl.Add(Trim(FormatStatus(Status)));
		
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
		Module.Metadata.PushUndo;
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

