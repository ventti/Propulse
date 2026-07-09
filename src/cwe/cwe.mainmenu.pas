unit CWE.MainMenu;

interface

uses
	Classes, SysUtils, Types,
	ShortcutManager,
	CWE.Core, CWE.Widgets.Text;

type
	TCWEMainMenuList = class(TCWETwoColumnList)
	public
		function	KeyDown(var Key: Integer; Shift: TShiftState): Boolean; override;
	end;

	// Command palette list: a filterable variant of the main menu list. Typing
	// narrows the command list (fuzzy subsequence match); Backspace edits the
	// query; Enter/Escape/arrows behave as in the main menu.
	TCWEPaletteList = class(TCWEMainMenuList)
	public
		function	KeyDown(var Key: Integer; Shift: TShiftState): Boolean; override;
		function	TextInput(var Key: Char): Boolean; override;
	end;

	// A single command captured from the menu population, kept unfiltered so the
	// palette can rebuild the visible list on each keystroke.
	TPaletteItem = record
		Cap0, Cap1:		String;		// command caption / shortcut columns
		Data:			Cardinal;	// binding ID (or $80000000+ID for keyless)
		ObjData:		Pointer;	// section (TKeyBindings)
		ColFg, ColBg:	ShortInt;
	end;

	TCWEMainMenu = class
	private
		Section: 	TKeyBindings;
		List:		TCWEMainMenuList;
	public
		Query:			AnsiString;				// command palette filter text
		SearchLabel:	TCWELabel;				// shows the current query
		Master:			array of TPaletteItem;	// unfiltered palette commands

		procedure	Show;
		procedure	ShowPalette;
		procedure	SnapshotItems;
		procedure	ApplyFilter;
		procedure	MainMenuCommand(Sender: TCWEControl);

		procedure 	SetSection(var ASection: TKeyBindings);
		procedure 	AddSection(const Caption: AnsiString);
		procedure 	AddCmd(Key: Cardinal; const Caption: AnsiString);
		procedure 	AddCmdEx(Key: Cardinal; const Caption: AnsiString);
	end;

var
	ContextMenu: TCWEMainMenu;

implementation

uses
	MainWindow,
	TextMode, SDL2,
	ProTracker.Util, CWE.Dialogs;

{ TCWEMainMenu }

procedure TCWEMainMenu.SetSection(var ASection: TKeyBindings);
begin
	Section := ASection;
end;

procedure TCWEMainMenu.AddSection(const Caption: AnsiString);
begin
	List.Items.Add(TCWEListItem.Create(Caption, LISTITEM_HEADER, nil, 3, 2));
end;

procedure TCWEMainMenu.AddCmd(Key: Cardinal; const Caption: AnsiString);
begin
	List.Items.Add(TCWEListItem.Create(
		Caption + COLUMNSEPARATOR + ShortCuts.GetShortcut(Section, Key),
		Ord(Key), Pointer(Section)));
end;

procedure TCWEMainMenu.AddCmdEx(Key: Cardinal; const Caption: AnsiString);
begin
	List.Items.Add(TCWEListItem.Create(Caption, $80000000 + Key, Pointer(Section)));
end;

procedure TCWEMainMenu.Show;
var
	Dlg: TCWEScreen;
	i, W, H: Integer;
begin
	W := 34+6;
	H := 32;

	if (ModalDialog.Dialog <> nil) or (CurrentScreen = nil) then
		Exit;

	Dlg := ModalDialog.CreateDialog(DIALOG_CONTEXTMENU, Bounds(
		(Console.Width  div 2) - (W div 2),
		(Console.Height div 2) - (H div 2), W, H),
		 'Menu');

	List := TCWEMainMenuList.Create(Dlg, '', 'Menu',
		Types.Rect(1, 2, W-1, H-1), True);

	with List do
	begin
		ColorBack := TConsole.COLOR_PANEL;
		ColorFore := TConsole.COLOR_TEXT;
		ColumnColor[0] := ColorFore;
		ColumnColor[1] := TConsole.COLOR_3DDARK;
		ColumnWidth[1] := 13;
		ColumnWidth[0] := Width - ColumnWidth[1];
		OnActivate  := MainMenuCommand;
		Selection3D := True;
		Data[0].Value := TConsole.COLOR_LIGHT; // bright white
		for i := 1 to 3 do
			Data[i].Value := 8; // hover bg + border
	end;

	// fill context menu items; only add global items if
	// CurrentScreen.OnContextMenu returns True
	Window.OnContextMenu(CurrentScreen.OnContextMenu);

	H := List.Items.Count + 3;
	ModalDialog.SetBounds(Bounds(
		(Console.Width  div 2) - (W div 2),
		(Console.Height div 2) - (H div 2), W, H));
	List.SetBounds(Types.Rect(1, 2, W-1, H-1));
	List.ItemIndex := 1;
	List.Scrollbar.Visible := False;

	ModalDialog.Show;
end;

procedure TCWEMainMenu.MainMenuCommand(Sender: TCWEControl);
var
	Item: TCWEListItem;
	Sect: TKeyBindings;
	Binding: TKeyBinding;
	i: Integer;
	Cmd: Cardinal;
	Key: Integer;
	Shift: TShiftState;
begin
	// get the Key and Shift codes for a keybinding const (e.g. keyScreenHelp -> F1, [])

	if not List.IsValidItemIndex(List.ItemIndex) then Exit;
	Item := List.Items[List.ItemIndex];
	if Item.ObjData = nil then Exit;
	Cmd := Item.Data;

	if (Cmd and $80000000) = 0 then
	begin
		i := Shortcuts.Sections.IndexOf(TKeyBindings(Item.ObjData));
		if i < 0 then
		begin
			Log(TEXT_WARNING+'Section not found!');
			Exit;
		end;

		Sect := Shortcuts.Sections[i];
		Binding := Sect.FindKey(Cmd);

		if Binding = nil then
		begin
			Log(TEXT_WARNING+'Binding not found!');
			Exit;
		end
		else
		begin
			Key := Binding.Shortcut.Key;
			Shift := Binding.Shortcut.Shift;
			if Key <> 0 then
			begin
				ModalDialog.Close;
				Window.OnKeyDown(Key, Shift);
			end
			else
				Log(TEXT_WARNING+'Unhandled command!');
		end;
	end
	else
	begin
		ModalDialog.Close;
		CurrentScreen.HandleCommand(Cmd and $7FFFFFFF);
	end;
end;

function TCWEMainMenuList.KeyDown(var Key: Integer; Shift: TShiftState): Boolean;
var
	Sc: ControlKeyNames;
begin
	Sc := ControlKeyNames(Shortcuts.Find(ControlKeys, Key, Shift));
	Result := True;
	case Sc of
		ctrlkeyRETURN:
			ContextMenu.MainMenuCommand(Self);
		ctrlkeyESCAPE:
			ModalDialog.Close;
		else
			Result := inherited;
	end;
end;

// ==========================================================================
{ Command palette }
// ==========================================================================

// Case-insensitive subsequence match: every char of Pattern appears in S in
// order (not necessarily contiguously). Both arguments must be lowercased.
function SubseqMatch(const S, Pattern: AnsiString): Boolean;
var
	i, j: Integer;
begin
	if Pattern = '' then Exit(True);
	j := 1;
	for i := 1 to Length(S) do
		if S[i] = Pattern[j] then
		begin
			Inc(j);
			if j > Length(Pattern) then Exit(True);
		end;
	Result := False;
end;

// Copy the freshly populated command list into Master so ApplyFilter can rebuild
// the visible list on each keystroke. Section headers are dropped: the palette
// is a flat, filterable list.
procedure TCWEMainMenu.SnapshotItems;
var
	i, n: Integer;
begin
	SetLength(Master, List.Items.Count);
	n := 0;
	for i := 0 to List.Items.Count-1 do
	begin
		if List.Items[i].Data = LISTITEM_HEADER then Continue;
		Master[n].Cap0    := List.Items[i].Captions[0];
		Master[n].Cap1    := List.Items[i].Captions[1];
		Master[n].Data    := List.Items[i].Data;
		Master[n].ObjData := List.Items[i].ObjData;
		Master[n].ColFg   := List.Items[i].ColorFore;
		Master[n].ColBg   := List.Items[i].ColorBack;
		Inc(n);
	end;
	SetLength(Master, n);
end;

// Rebuild the visible list from Master, keeping only commands whose caption
// fuzzy-matches Query, and select the first result.
procedure TCWEMainMenu.ApplyFilter;
var
	i: Integer;
	q, name, comb: AnsiString;
begin
	if List = nil then Exit;

	List.Clear;
	q := LowerCase(Query);

	for i := 0 to High(Master) do
	begin
		name := LowerCase(Master[i].Cap0);
		if (q = '') or SubseqMatch(name, q) then
		begin
			if Master[i].Cap1 <> '' then
				comb := Master[i].Cap0 + COLUMNSEPARATOR + Master[i].Cap1
			else
				comb := Master[i].Cap0;
			List.Items.Add(TCWEListItem.Create(comb,
				Master[i].Data, Master[i].ObjData, Master[i].ColFg, Master[i].ColBg));
		end;
	end;

	List.AdjustScrollbar;
	List.Offset := 0;
	if List.Items.Count > 0 then
		List.ItemIndex := 0
	else
		List.ItemIndex := -1;

	if SearchLabel <> nil then
	begin
		SearchLabel.Caption := 'Search: ' + Query + '_';
		SearchLabel.Paint;
	end;
	List.Paint;
end;

procedure TCWEMainMenu.ShowPalette;
var
	Dlg: TCWEScreen;
	i, W, H: Integer;
begin
	if (ModalDialog.Dialog <> nil) or (CurrentScreen = nil) then
		Exit;

	Query := '';
	W := 44;
	H := 30;

	Dlg := ModalDialog.CreateDialog(DIALOG_CONTEXTMENU, Bounds(
		(Console.Width  div 2) - (W div 2),
		(Console.Height div 2) - (H div 2), W, H),
		'Command palette');

	SearchLabel := TCWELabel.Create(Dlg, '', 'Search',
		Types.Rect(1, 2, W-1, 3));
	SearchLabel.SetColors(TConsole.COLOR_LIGHT, TConsole.COLOR_PANEL);

	List := TCWEPaletteList.Create(Dlg, '', 'Palette',
		Types.Rect(1, 4, W-1, H-1), True);

	with List do
	begin
		ColorBack := TConsole.COLOR_PANEL;
		ColorFore := TConsole.COLOR_TEXT;
		ColumnColor[0] := ColorFore;
		ColumnColor[1] := TConsole.COLOR_3DDARK;
		ColumnWidth[1] := 13;
		ColumnWidth[0] := Width - ColumnWidth[1];
		OnActivate  := MainMenuCommand;
		Selection3D := True;
		Data[0].Value := TConsole.COLOR_LIGHT; // bright white
		for i := 1 to 3 do
			Data[i].Value := 8; // hover bg + border
	end;

	// Populate using the same path as the main menu: current screen's commands
	// plus (optionally) the globals. This fills List via AddCmd/AddCmdEx.
	Window.OnContextMenu(CurrentScreen.OnContextMenu);
	SnapshotItems;
	ApplyFilter;

	Dlg.ActiveControl := List;
	ModalDialog.Show;
end;

function TCWEPaletteList.TextInput(var Key: Char): Boolean;
begin
	if Ord(Key) < 32 then Exit(False);
	ContextMenu.Query := ContextMenu.Query + Key;
	ContextMenu.ApplyFilter;
	Result := True;
end;

function TCWEPaletteList.KeyDown(var Key: Integer; Shift: TShiftState): Boolean;
var
	Sc: ControlKeyNames;
begin
	Sc := ControlKeyNames(Shortcuts.Find(ControlKeys, Key, Shift));
	if Sc = ctrlkeyBACKSPACE then
	begin
		if ssCtrl in Shift then
			ContextMenu.Query := ''
		else if Length(ContextMenu.Query) > 0 then
			SetLength(ContextMenu.Query, Length(ContextMenu.Query) - 1);
		ContextMenu.ApplyFilter;
		Key := 0;
		Result := True;
	end
	else
		Result := inherited KeyDown(Key, Shift);
end;


end.

