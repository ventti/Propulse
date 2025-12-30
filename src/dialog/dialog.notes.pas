// ==========================================================================
// Notes Dialog - View and edit song metadata
// ==========================================================================
unit Dialog.Notes;

interface

uses
	Types, Classes, SysUtils,
	CWE.Core,
	CWE.Dialogs;

	procedure Dialog_Notes;


implementation

uses
	StrUtils, Generics.Collections,
	CWE.Widgets.Text,
	ProTracker.Metadata, ProTracker.Player, ProTracker.Editor,
	Screen.Editor,
	MainWindow;

const
	ACTION_NEW = 1;
	ACTION_DELETE = 2;
	ACTION_GOTO = 3;
	ACTION_SETPOINTER = 4;
	ACTION_SAVE = 5;
	ACTION_CYCLESTATUS = 6;
	ACTION_FIXALL = 7;

type
	TNotesDialogHelper = class
	public
		procedure ListSelectionChanged(Sender: TCWEControl);
		procedure ButtonNewClick(Sender: TCWEControl);
		procedure ButtonDeleteClick(Sender: TCWEControl);
		procedure ButtonGotoClick(Sender: TCWEControl);
		procedure ButtonSetPtrClick(Sender: TCWEControl);
		procedure ButtonFixAllClick(Sender: TCWEControl);
		procedure DialogCallback(ID: Word; Button: TDialogButton;
			ModalResult: Integer; Data: Variant; Dlg: TCWEDialog);
	end;

var
	NotesList: TCWEList;
	TitleEdit: TCWEEdit;
	BodyEdit: TCWEEdit;
	StatusLabel: TCWELabel;
	PointerLabel: TCWELabel;
	CreatedLabel: TCWELabel;
	UpdatedLabel: TCWELabel;
	SummaryLabel: TCWELabel;
	CurrentEntryID: Integer = -1;
	CurrentStatus: TMetadataStatus = msOpen;
	DialogHelper: TNotesDialogHelper;

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
		msFixme:  Result := 'fixme';
		msWip:    Result := 'wip';
		msDone:   Result := 'done';
		msClosed: Result := 'closed';
	else
		Result := 'open';
	end;
end;

procedure UpdateEntryDisplay;
var
	Entry: TMetadataEntry;
	Summary: AnsiString;
begin
	if (CurrentEntryID < 0) or (not Assigned(Module)) or (not Assigned(Module.Metadata)) then
	begin
		SummaryLabel.SetCaption('');
		TitleEdit.SetCaption('');
		BodyEdit.SetCaption('');
		StatusLabel.SetCaption('');
		PointerLabel.SetCaption('');
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
	BodyEdit.SetCaption(Entry.Body);
	CurrentStatus := Entry.Status;
	StatusLabel.SetCaption('Status: ' + FormatStatus(Entry.Status));
	PointerLabel.SetCaption('Pointer: ' + FormatPointer(Entry.Pointer));
	CreatedLabel.SetCaption('Created: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Entry.CreatedAt));
	UpdatedLabel.SetCaption('Updated: ' + FormatDateTime('yyyy-mm-dd hh:nn:ss', Entry.UpdatedAt));
end;

procedure CheckListSelection;
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

procedure RefreshList;
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
		NotesList.ItemIndex := 0;
		if Entries.Count > 0 then
		begin
			CurrentEntryID := Entries[0].ID;
			UpdateEntryDisplay;
		end;
	end
	else
	begin
		CurrentEntryID := -1;
		UpdateEntryDisplay;
	end;
	
	// Check selection after refresh
	CheckListSelection;
end;

procedure HandleNotesAction(ActionID: Integer);
var
	Entry: TMetadataEntry;
	NewTitle, NewBody: AnsiString;
	Ptr: TMetadataPointer;
	i, FixedCount: Integer;
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
			RefreshList;
			// Select the new entry
			for i := 0 to NotesList.Items.Count - 1 do
			begin
				if Pos(IntToStr(CurrentEntryID), NotesList.Items[i].Captions[0]) > 0 then
				begin
					NotesList.ItemIndex := i;
					Break;
				end;
			end;
			UpdateEntryDisplay;
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
					// Get ID from first entry
					Entry := Module.Metadata.GetEntries[0];
					CurrentEntryID := Entry.ID;
					UpdateEntryDisplay;
				end;
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
				NewBody := Copy(BodyEdit.Caption, 1, MAX_BODY_LENGTH);
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

{ TNotesDialogHelper }

procedure TNotesDialogHelper.ListSelectionChanged(Sender: TCWEControl);
begin
	CheckListSelection;
end;

procedure TNotesDialogHelper.ButtonNewClick(Sender: TCWEControl);
begin
	HandleNotesAction(ACTION_NEW);
end;

procedure TNotesDialogHelper.ButtonDeleteClick(Sender: TCWEControl);
begin
	HandleNotesAction(ACTION_DELETE);
end;

procedure TNotesDialogHelper.ButtonGotoClick(Sender: TCWEControl);
begin
	HandleNotesAction(ACTION_GOTO);
end;

procedure TNotesDialogHelper.ButtonSetPtrClick(Sender: TCWEControl);
begin
	HandleNotesAction(ACTION_SETPOINTER);
end;

procedure TNotesDialogHelper.ButtonFixAllClick(Sender: TCWEControl);
begin
	HandleNotesAction(ACTION_FIXALL);
end;

procedure TNotesDialogHelper.DialogCallback(ID: Word; Button: TDialogButton;
	ModalResult: Integer; Data: Variant; Dlg: TCWEDialog);
begin
	if Dlg <> nil then Exit; // Ignore while dialog is open

	// Handle OK button - save and close
	if Button = btnOK then
	begin
		HandleNotesAction(ACTION_SAVE);
	end;
end;

procedure Dialog_Notes;
const
	W = 60;
	H = 25;
var
	Dlg: TCWEScreen;
	ListW, EditX, EditW: Integer;
	TitleLbl, BodyLbl, EmptyLabel: TCWELabel;
	BtnNew, BtnDelete, BtnGoto, BtnSetPtr, BtnFixAll: TCWEButton;
begin
	if not Assigned(Module) or not Assigned(Module.Metadata) then
	begin
		ModalDialog.ShowMessage('Notes', 'No module loaded.');
		Exit;
	end;

	Dlg := ModalDialog.CreateDialog(0, Bounds(
		(Console.Width div 2) - (W div 2),
		(Console.Height div 2) - (H div 2), W, H),
		'Notes', True);

	ListW := 25;
	EditX := ListW + 2;
	EditW := W - EditX - 1;

	// Create helper object for event handlers
	DialogHelper := TNotesDialogHelper.Create;

	// List of entries
	NotesList := TCWEList.Create(Dlg, '', 'NotesList',
		Types.Rect(1, 2, ListW, H - 6), True);
	NotesList.OnChange := DialogHelper.ListSelectionChanged;
	NotesList.CanCloseDialog := False;

	// Summary header (read-only)
	SummaryLabel := TCWELabel.Create(Dlg, '', 'Summary',
		Types.Rect(EditX, 2, EditX + EditW, 3), True);
	SummaryLabel.SetColors(3, 1);

	// Separator
//	SepLabel := TCWELabel.Create(Dlg, StringOfChar('-', EditW), 'Separator',
//		Types.Rect(EditX, 3, EditX + EditW, 4), True);

	// Title edit
	TitleLbl := TCWELabel.Create(Dlg, 'Title:', 'TitleLabel',
		Types.Rect(EditX, 4, EditX + 8, 5), True);
	TitleEdit := TCWEEdit.Create(Dlg, '', 'TitleEdit',
		Types.Rect(EditX + 8, 4, EditX + EditW, 5), True);
	TitleEdit.MaxLength := MAX_TITLE_LENGTH;
	TitleEdit.SetBorder(True, False, True, True);

	// Status (will be editable via keyboard shortcut)
	StatusLabel := TCWELabel.Create(Dlg, 'Status: open', 'StatusLabel',
		Types.Rect(EditX, 5, EditX + EditW, 6), True);

	// Pointer (will be editable via button)
	PointerLabel := TCWELabel.Create(Dlg, 'Pointer: None', 'PointerLabel',
		Types.Rect(EditX, 6, EditX + EditW, 7), True);

	// Body label
	BodyLbl := TCWELabel.Create(Dlg, 'Body:', 'BodyLabel',
		Types.Rect(EditX, 7, EditX + 8, 8), True);

	// Body edit (multiline support via large height)
	BodyEdit := TCWEEdit.Create(Dlg, '', 'BodyEdit',
		Types.Rect(EditX, 8, EditX + EditW, H - 8), True);
	BodyEdit.MaxLength := MAX_BODY_LENGTH;
	BodyEdit.SetBorder(True, False, True, True);
	BodyEdit.ReportAnyChange := True;

	// Timestamps
	CreatedLabel := TCWELabel.Create(Dlg, 'Created: ', 'CreatedLabel',
		Types.Rect(EditX, H - 8, EditX + EditW, H - 7), True);
	// Use -1 (transparent) to show dialog background (COLOR_PANEL)
	UpdatedLabel := TCWELabel.Create(Dlg, 'Updated: ', 'UpdatedLabel',
		Types.Rect(EditX, H - 7, EditX + EditW, H - 6), True);
	// Use -1 (transparent) to show dialog background (COLOR_PANEL)

	// Action buttons (custom, don't close dialog)
	BtnNew := TCWEButton.Create(Dlg, 'New', 'BtnNew',
		Types.Rect(EditX, H - 2, EditX + 6, H - 1));
	BtnNew.Tag := ACTION_NEW;
	BtnNew.ModalResult := -1;
	BtnNew.OnChange := DialogHelper.ButtonNewClick;

	BtnDelete := TCWEButton.Create(Dlg, 'Delete', 'BtnDelete',
		Types.Rect(EditX + 7, H - 2, EditX + 15, H - 1));
	BtnDelete.Tag := ACTION_DELETE;
	BtnDelete.ModalResult := -1;
	BtnDelete.OnChange := DialogHelper.ButtonDeleteClick;

	BtnGoto := TCWEButton.Create(Dlg, 'Go To', 'BtnGoto',
		Types.Rect(EditX + 16, H - 2, EditX + 23, H - 1));
	BtnGoto.Tag := ACTION_GOTO;
	BtnGoto.ModalResult := -1;
	BtnGoto.OnChange := DialogHelper.ButtonGotoClick;

	BtnSetPtr := TCWEButton.Create(Dlg, 'Set Ptr', 'BtnSetPtr',
		Types.Rect(EditX + 24, H - 2, EditX + 33, H - 1));
	BtnSetPtr.Tag := ACTION_SETPOINTER;
	BtnSetPtr.ModalResult := -1;
	BtnSetPtr.OnChange := DialogHelper.ButtonSetPtrClick;

	BtnFixAll := TCWEButton.Create(Dlg, 'Fix All', 'BtnFixAll',
		Types.Rect(EditX + 34, H - 2, EditX + 42, H - 1));
	BtnFixAll.Tag := ACTION_FIXALL;
	BtnFixAll.ModalResult := -1;
	BtnFixAll.OnChange := DialogHelper.ButtonFixAllClick;

	// OK button (closes dialog)
	with ModalDialog do
	begin
		AddResultButton(btnOK, 'OK', W - 9, H - 2, True);
		ButtonCallback := DialogHelper.DialogCallback;
	end;

	RefreshList;

	// Show empty state if no entries
	if NotesList.Items.Count = 0 then
	begin
		EmptyLabel := TCWELabel.Create(Dlg, 'No notes yet. Press ''New'' to create one.', 'EmptyState',
			Types.Rect(EditX, 10, EditX + EditW, 12), True);
		EmptyLabel.Alignment := ALIGN_CENTER;
		EmptyLabel.SetColors(7, 1);
	end;

	ModalDialog.Dialog.ActivateControl(NotesList);
	ModalDialog.Show;
end;

end.

