unit Screen.Help;

interface

uses
	Classes, Types,
	TextMode, CWE.Core, CWE.Widgets.Text;

type
	THelpScreen = class(TCWEScreen)
	private
		Timestamp:	LongInt;
		lblSearchHint,
		lblSearch:	TCWELabel;
		SearchTerm:	AnsiString;
		MatchLines:	array of Integer;
		MatchIndex:	Integer;

		procedure	ClearSearch;
		procedure	SearchTermChanged;
		procedure	JumpToMatch(NewIndex: Integer);
		procedure	NextMatch;
		procedure	PrevMatch;
	public
		Memo:		TCWEMemo;

		function 	HelpFileName: String;
		function 	LoadHelp: Boolean;
		procedure	Show(Context: AnsiString); reintroduce;

		function	KeyDown(var Key: Integer; Shift: TShiftState): Boolean; override;
		function	TextInput(var Key: Char): Boolean; override;

		constructor	Create(var Con: TConsole; const sCaption, sID: AnsiString); override;
	end;

var
	Help: THelpScreen;


implementation

uses
	SDL2,
	SysUtils,
	ProTracker.Util,
	Layout;


constructor THelpScreen.Create;
begin
	inherited;

	RegisterScreenLayout(Self, 'HelpViewer');

	Memo := TCWEMemo.Create(Self, '', 'Text View',
		Types.Rect(1, 1, Console.Width-2, Console.Height-4), True);

	Memo.ColorFore := 6;
	ActiveControl := Memo;

	lblSearchHint := TCWELabel.Create(Self, 'Type to search:', 'SearchHint',
		Types.Rect(2, Console.Height-3, Console.Width-1, Console.Height-2));
	lblSearch := TCWELabel.Create(Self, '', 'Search',
		Types.Rect(2, Console.Height-2, Console.Width-1, Console.Height-1));
	RegisterLayoutControl(TCWEControl(lblSearchHint), CTRLKIND_LABEL, False, True, False);
	RegisterLayoutControl(TCWEControl(lblSearch),     CTRLKIND_LABEL, False, True, False);

	LoadLayout(Self);

	ClearSearch;
	LoadHelp;
end;

function THelpScreen.HelpFileName: String;
begin
	Result := GetDataFile('help.txt');
end;

procedure THelpScreen.ClearSearch;
begin
	SearchTerm := '';
	MatchIndex := -1;
	SetLength(MatchLines, 0);
	if lblSearch <> nil then
		lblSearch.SetCaption('');
end;

procedure THelpScreen.JumpToMatch(NewIndex: Integer);
begin
	if (NewIndex < 0) or (NewIndex >= Length(MatchLines)) then Exit;
	MatchIndex := NewIndex;
	Memo.ScrollTo(Cardinal(MatchLines[MatchIndex]));
end;

procedure THelpScreen.NextMatch;
begin
	if Length(MatchLines) < 1 then Exit;
	if MatchIndex < 0 then
		JumpToMatch(0)
	else
		JumpToMatch((MatchIndex + 1) mod Length(MatchLines));
end;

procedure THelpScreen.PrevMatch;
begin
	if Length(MatchLines) < 1 then Exit;
	if MatchIndex < 0 then
		JumpToMatch(0)
	else
		JumpToMatch((MatchIndex + Length(MatchLines) - 1) mod Length(MatchLines));
end;

procedure THelpScreen.SearchTermChanged;
var
	i, c: Integer;
	LineText: AnsiString;
	Term: AnsiString;
	Best: Integer;
begin
	if lblSearch <> nil then
		lblSearch.SetCaption(SearchTerm);

	SetLength(MatchLines, 0);
	MatchIndex := -1;
	if SearchTerm = '' then Exit;

	Term := LowerCase(SearchTerm);
	c := 0;
	for i := 0 to Memo.Lines.Count-1 do
	begin
		LineText := LowerCase(Memo.Lines[i].GetText);
		if Pos(Term, LineText) > 0 then
		begin
			SetLength(MatchLines, c+1);
			MatchLines[c] := i;
			Inc(c);
		end;
	end;

	if c < 1 then Exit;

	// Prefer the first match at/after current scroll offset, else wrap to first match.
	Best := 0;
	for i := 0 to c-1 do
		if MatchLines[i] >= Integer(Memo.Offset) then
		begin
			Best := i;
			Break;
		end;
	JumpToMatch(Best);
end;

function THelpScreen.LoadHelp: Boolean;
var
	sl: TStringList;
	S: AnsiString;
	Fn: String;
begin
	Memo.Lines.Clear;

	Fn := HelpFileName;
	Result := FileExists(Fn);

	if Result then
	begin
		Timestamp := FileAge(Fn);
		sl := TStringList.Create;
		sl.LoadFromFile(Fn);
		for S in sl do
			if Copy(S, 1, 1) <> ';' then
				Memo.Add(S);
		sl.Free;
	end
	else
	begin
		Timestamp := 0;
		Memo.Add('<h1>Help file not found!');
	end;

	SearchTermChanged;
end;

procedure THelpScreen.Show(Context: AnsiString);
var
	Fn: String;
begin
	Fn := HelpFileName;
	if (FileExists(Fn)) and (FileAge(Fn) <> Timestamp) then
		LoadHelp; // reload help file if it's been modified

	ClearSearch;
	if Memo.JumpToSection(Context) < 0 then
		Memo.ScrollTo(0);
	ChangeScreen(TCWEScreen(Self));
end;

function THelpScreen.KeyDown(var Key: Integer; Shift: TShiftState): Boolean;
begin
	// Handle incremental search editing + match navigation.
	if (Key = SDLK_BACKSPACE) then
	begin
		if ssCtrl in Shift then
			SearchTerm := ''
		else
		if SearchTerm <> '' then
			SearchTerm := Copy(SearchTerm, 1, Length(SearchTerm)-1);
		SearchTermChanged;
		Exit(True);
	end;

	if (Key = SDLK_RIGHT) and (SearchTerm <> '') and (Length(MatchLines) > 0) then
	begin
		NextMatch;
		Exit(True);
	end;

	if (Key = SDLK_LEFT) and (SearchTerm <> '') and (Length(MatchLines) > 0) then
	begin
		PrevMatch;
		Exit(True);
	end;

	Result := inherited KeyDown(Key, Shift);
end;

function THelpScreen.TextInput(var Key: Char): Boolean;
begin
	// Type-to-search for help content (case-insensitive).
	SearchTerm := SearchTerm + LowerCase(Key);
	SearchTermChanged;
	Result := True;
end;

end.

