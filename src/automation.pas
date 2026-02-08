unit Automation;

{$I propulse.inc}

interface

uses
	SysUtils, Classes,
	SDL2,
	ShortcutManager, TextMode;

type
	TAutomationActionKind = (
		aaWait,
		aaKey,
		aaText,
		aaMouseMove,
		aaMouseDown,
		aaMouseUp,
		aaMouseClick,
		aaMouseWheel,
		aaDumpRow,
		aaQuit
	);

	TAutomationAction = record
		Kind: TAutomationActionKind;
		WaitMs: Cardinal;
		Shortcut: TShortCut;
		Text: AnsiString;
		MouseX: Integer;
		MouseY: Integer;
		MouseIsCell: Boolean;
		MouseButton: UInt8;
		WheelY: Integer;
		HasMousePos: Boolean;
		PatternIndex: Integer;
		RowIndex: Integer;
		ChannelIndex: Integer;
		DumpAllChannels: Boolean;
	end;

	TAutomationRunner = class
	private
		FActions: array of TAutomationAction;
		FIndex: Integer;
		FNextTime: UInt32;
		FActive: Boolean;
		FExitOnComplete: Boolean;
		FShouldQuit: Boolean;

		procedure AddAction(const Action: TAutomationAction);
		procedure PushKey(const Shortcut: TShortCut);
		procedure PushText(const Text: AnsiString);
		procedure PushMouseButton(Button: UInt8; Down: Boolean; X, Y: Integer);
		procedure PushMouseWheel(Dy: Integer);
		procedure WarpMouse(Window: PSDL_Window; X, Y: Integer);
		function ResolveMousePoint(const Action: TAutomationAction; out X, Y: Integer): Boolean;
	public
		procedure LoadScript(const Filename: String);
		procedure Start(ExitOnComplete: Boolean);
		procedure ProcessFrame(Window: PSDL_Window);
		function IsActive: Boolean;
		function ShouldQuit: Boolean;
	end;

var
	Automation: TAutomationRunner;

procedure InitAutomation(const ScriptFilename: String; ExitOnComplete: Boolean);
procedure ProcessAutomationFrame(Window: PSDL_Window);
function AutomationShouldQuit: Boolean;
function AutomationIsActive: Boolean;

implementation

uses
	StrUtils,
	CWE.Core,
	ProTracker.Player;

const
	AUTOMATION_TEXT_MAX = 31; // SDL_TEXTINPUTEVENT_TEXT_SIZE - 1
{$if not declared(SDL_MOUSEWHEEL_NORMAL)}
	SDL_MOUSEWHEEL_NORMAL = 0;
{$endif}

function StripComment(const Line: String): String;
var
	P: SizeInt;
begin
	P := Pos('#', Line);
	if P > 0 then
		Result := Trim(Copy(Line, 1, P - 1))
	else
		Result := Trim(Line);
end;

function ParseMouseButton(const S: String; out Button: UInt8): Boolean;
var
	L: String;
begin
	L := LowerCase(Trim(S));
	if L = 'left' then
		Button := SDL_BUTTON_LEFT
	else
	if L = 'right' then
		Button := SDL_BUTTON_RIGHT
	else
	if L = 'middle' then
		Button := SDL_BUTTON_MIDDLE
	else
	begin
		Button := SDL_BUTTON_LEFT;
		Exit(False);
	end;
	Result := True;
end;

function ParseMousePosition(const Tokens: TStringList; StartIndex: Integer;
	out X, Y: Integer; out IsCell: Boolean): Boolean;
var
	Idx: Integer;
begin
	Result := False;
	IsCell := False;
	Idx := StartIndex;
	if (Idx < Tokens.Count) and (LowerCase(Tokens[Idx]) = 'cell') then
	begin
		IsCell := True;
		Inc(Idx);
	end;
	if Tokens.Count <= Idx + 1 then Exit(False);
	if (not TryStrToInt(Tokens[Idx], X)) or (not TryStrToInt(Tokens[Idx + 1], Y)) then
		Exit(False);
	Result := True;
end;

function ContainsHexLetter(const S: String): Boolean;
var
	C: Char;
begin
	Result := False;
	for C in S do
		if (C in ['A'..'F']) or (C in ['a'..'f']) then
			Exit(True);
end;

function ParseIntMaybeHex(const S: String; out Value: Integer): Boolean;
var
	T: String;
begin
	T := Trim(S);
	if T = '' then Exit(False);
	if (Length(T) > 1) and (LowerCase(Copy(T, 1, 2)) = '0x') then
		T := '$' + Copy(T, 3, MaxInt);
	if (Pos('$', T) <> 1) and ContainsHexLetter(T) then
		T := '$' + T;
	Result := TryStrToInt(T, Value);
end;

procedure TAutomationRunner.AddAction(const Action: TAutomationAction);
var
	I: Integer;
begin
	I := Length(FActions);
	SetLength(FActions, I + 1);
	FActions[I] := Action;
end;

procedure TAutomationRunner.PushKey(const Shortcut: TShortCut);
var
	Ev: TSDL_Event;
	ModState: TSDL_Keymod;
begin
	if Shortcut.Key = 0 then Exit;

	ModState := KMOD_NONE;
	if ssShift in Shortcut.Shift then ModState := ModState or KMOD_SHIFT;
	if ssCtrl  in Shortcut.Shift then ModState := ModState or KMOD_CTRL;
	if ssAlt   in Shortcut.Shift then ModState := ModState or KMOD_ALT;
	if ssAltGr in Shortcut.Shift then ModState := ModState or KMOD_MODE;
	if ssMeta  in Shortcut.Shift then ModState := ModState or KMOD_GUI;
	if ssCaps  in Shortcut.Shift then ModState := ModState or KMOD_CAPS;

	FillChar(Ev, SizeOf(Ev), 0);
	Ev.type_ := SDL_KEYDOWN;
	Ev.key.state := SDL_PRESSED;
	Ev.key.keysym.sym := Shortcut.Key;
	Ev.key.keysym.scancode := SDL_GetScancodeFromKey(Shortcut.Key);
	Ev.key.keysym._mod := ModState;
	SDL_PushEvent(@Ev);

	FillChar(Ev, SizeOf(Ev), 0);
	Ev.type_ := SDL_KEYUP;
	Ev.key.state := SDL_RELEASED;
	Ev.key.keysym.sym := Shortcut.Key;
	Ev.key.keysym.scancode := SDL_GetScancodeFromKey(Shortcut.Key);
	Ev.key.keysym._mod := ModState;
	SDL_PushEvent(@Ev);
end;

procedure TAutomationRunner.PushText(const Text: AnsiString);
var
	Ev: TSDL_Event;
	I: Integer;
	C: AnsiChar;
begin
	if Text = '' then Exit;
	for I := 1 to Length(Text) do
	begin
		C := Text[I];
		FillChar(Ev, SizeOf(Ev), 0);
		Ev.type_ := SDL_TEXTINPUT;
		Ev.text.text[0] := C;
		Ev.text.text[1] := #0;
		SDL_PushEvent(@Ev);
	end;
end;

procedure TAutomationRunner.PushMouseButton(Button: UInt8; Down: Boolean; X, Y: Integer);
var
	Ev: TSDL_Event;
begin
	FillChar(Ev, SizeOf(Ev), 0);
	if Down then
		Ev.type_ := SDL_MOUSEBUTTONDOWN
	else
		Ev.type_ := SDL_MOUSEBUTTONUP;
	Ev.button.button := Button;
	Ev.button.state := SDL_PRESSED;
	if not Down then
		Ev.button.state := SDL_RELEASED;
	Ev.button.x := X;
	Ev.button.y := Y;
	SDL_PushEvent(@Ev);
end;

procedure TAutomationRunner.PushMouseWheel(Dy: Integer);
var
	Ev: TSDL_Event;
begin
	FillChar(Ev, SizeOf(Ev), 0);
	Ev.type_ := SDL_MOUSEWHEEL;
	Ev.wheel.y := Dy;
	Ev.wheel.x := 0;
	Ev.wheel.direction := SDL_MOUSEWHEEL_NORMAL;
	SDL_PushEvent(@Ev);
end;

procedure TAutomationRunner.WarpMouse(Window: PSDL_Window; X, Y: Integer);
begin
	if Window = nil then Exit;
	SDL_WarpMouseInWindow(Window, X, Y);
end;

function TAutomationRunner.ResolveMousePoint(const Action: TAutomationAction; out X, Y: Integer): Boolean;
var
	CellW, CellH: Integer;
begin
	if Action.HasMousePos then
	begin
		X := Action.MouseX;
		Y := Action.MouseY;
		if Action.MouseIsCell then
		begin
			if Console <> nil then
			begin
				CellW := Console.Font.Width;
				CellH := Console.Font.Height;
				X := X * CellW;
				Y := Y * CellH;
			end;
		end;
		Result := True;
	end
	else
	begin
		SDL_GetMouseState(@X, @Y);
		Result := True;
	end;
end;

procedure TAutomationRunner.LoadScript(const Filename: String);
var
	Lines: TStringList;
	Tokens: TStringList;
	Line, Clean, Cmd, Rest: String;
	P: SizeInt;
	Action: TAutomationAction;
	WaitMs: Integer;
	Button: UInt8;
	PosOk: Boolean;
	X, Y: Integer;
	IsCell: Boolean;
begin
	FIndex := 0;
	FNextTime := 0;
	FActive := False;
	FShouldQuit := False;
	SetLength(FActions, 0);

	if Filename = '' then Exit;
	if not FileExists(Filename) then
	begin
		WriteLn(StdErr, 'automation: script not found: ', Filename);
		Exit;
	end;

	Lines := TStringList.Create;
	Tokens := TStringList.Create;
	try
		Lines.LoadFromFile(Filename);
		for Line in Lines do
		begin
			Clean := StripComment(Line);
			if Clean = '' then Continue;
			P := Pos(' ', Clean);
			if P <= 0 then
			begin
				Cmd := LowerCase(Clean);
				Rest := '';
			end
			else
			begin
				Cmd := LowerCase(Copy(Clean, 1, P - 1));
				Rest := Trim(Copy(Clean, P + 1, MaxInt));
			end;

			if Cmd = 'wait' then
			begin
				if not TryStrToInt(Rest, WaitMs) then
				begin
					WriteLn(StdErr, 'automation: invalid wait: ', Clean);
					Continue;
				end;
				if WaitMs < 0 then
					WaitMs := 0;
				FillChar(Action, SizeOf(Action), 0);
				Action.Kind := aaWait;
				Action.WaitMs := Cardinal(WaitMs);
				AddAction(Action);
			end
			else
			if Cmd = 'key' then
			begin
				FillChar(Action, SizeOf(Action), 0);
				Action.Kind := aaKey;
				Action.Shortcut := TextToShortCut(Rest);
				if Action.Shortcut.Key = 0 then
				begin
					WriteLn(StdErr, 'automation: invalid key: ', Clean);
					Continue;
				end;
				AddAction(Action);
			end
			else
			if Cmd = 'text' then
			begin
				if (Length(Rest) >= 2) and (Rest[1] = '"') and (Rest[Length(Rest)] = '"') then
					Rest := Copy(Rest, 2, Length(Rest) - 2);
				FillChar(Action, SizeOf(Action), 0);
				Action.Kind := aaText;
				Action.Text := Copy(Rest, 1, AUTOMATION_TEXT_MAX);
				AddAction(Action);
			end
			else
			if Cmd = 'mouse' then
			begin
				Tokens.Clear;
				ExtractStrings([' ', #9], [], PChar(Rest), Tokens);
				if Tokens.Count = 0 then
				begin
					WriteLn(StdErr, 'automation: invalid mouse command: ', Clean);
					Continue;
				end;

				if LowerCase(Tokens[0]) = 'move' then
				begin
					PosOk := ParseMousePosition(Tokens, 1, X, Y, IsCell);
					if not PosOk then
					begin
						WriteLn(StdErr, 'automation: invalid mouse move: ', Clean);
						Continue;
					end;
					FillChar(Action, SizeOf(Action), 0);
					Action.Kind := aaMouseMove;
					Action.MouseX := X;
					Action.MouseY := Y;
					Action.MouseIsCell := IsCell;
					Action.HasMousePos := True;
					AddAction(Action);
				end
				else
				if LowerCase(Tokens[0]) = 'click' then
				begin
					if (Tokens.Count < 2) or (not ParseMouseButton(Tokens[1], Button)) then
					begin
						WriteLn(StdErr, 'automation: invalid mouse click: ', Clean);
						Continue;
					end;
					FillChar(Action, SizeOf(Action), 0);
					Action.Kind := aaMouseClick;
					Action.MouseButton := Button;
					Action.HasMousePos := False;
					if Tokens.Count > 2 then
					begin
						PosOk := ParseMousePosition(Tokens, 2, X, Y, IsCell);
						if not PosOk then
						begin
							WriteLn(StdErr, 'automation: invalid mouse click position: ', Clean);
							Continue;
						end;
						Action.MouseX := X;
						Action.MouseY := Y;
						Action.MouseIsCell := IsCell;
						Action.HasMousePos := True;
					end;
					AddAction(Action);
				end
				else
				if (LowerCase(Tokens[0]) = 'down') or (LowerCase(Tokens[0]) = 'up') then
				begin
					if (Tokens.Count < 2) or (not ParseMouseButton(Tokens[1], Button)) then
					begin
						WriteLn(StdErr, 'automation: invalid mouse button: ', Clean);
						Continue;
					end;
					FillChar(Action, SizeOf(Action), 0);
					if LowerCase(Tokens[0]) = 'down' then
						Action.Kind := aaMouseDown
					else
						Action.Kind := aaMouseUp;
					Action.MouseButton := Button;
					Action.HasMousePos := False;
					if Tokens.Count > 2 then
					begin
						PosOk := ParseMousePosition(Tokens, 2, X, Y, IsCell);
						if not PosOk then
						begin
							WriteLn(StdErr, 'automation: invalid mouse position: ', Clean);
							Continue;
						end;
						Action.MouseX := X;
						Action.MouseY := Y;
						Action.MouseIsCell := IsCell;
						Action.HasMousePos := True;
					end;
					AddAction(Action);
				end
				else
				begin
					WriteLn(StdErr, 'automation: unsupported mouse command: ', Clean);
					Continue;
				end;
			end
			else
			if Cmd = 'wheel' then
			begin
				if not TryStrToInt(Rest, WaitMs) then
				begin
					WriteLn(StdErr, 'automation: invalid wheel: ', Clean);
					Continue;
				end;
				FillChar(Action, SizeOf(Action), 0);
				Action.Kind := aaMouseWheel;
				Action.WheelY := WaitMs;
				AddAction(Action);
			end
			else
			if Cmd = 'dump-row' then
			begin
				Tokens.Clear;
				ExtractStrings([' ', #9], [], PChar(Rest), Tokens);
				if Tokens.Count < 2 then
				begin
					WriteLn(StdErr, 'automation: invalid dump-row: ', Clean);
					Continue;
				end;
				if (not ParseIntMaybeHex(Tokens[0], X)) or (not ParseIntMaybeHex(Tokens[1], Y)) then
				begin
					WriteLn(StdErr, 'automation: invalid dump-row values: ', Clean);
					Continue;
				end;
				FillChar(Action, SizeOf(Action), 0);
				Action.Kind := aaDumpRow;
				Action.PatternIndex := X;
				Action.RowIndex := Y;
				Action.DumpAllChannels := True;
				AddAction(Action);
			end
			else
			if Cmd = 'dump' then
			begin
				Tokens.Clear;
				ExtractStrings([' ', #9], [], PChar(Rest), Tokens);
				if Tokens.Count < 3 then
				begin
					WriteLn(StdErr, 'automation: invalid dump: ', Clean);
					Continue;
				end;
				if (not ParseIntMaybeHex(Tokens[0], X)) or
					(not ParseIntMaybeHex(Tokens[1], Y)) or
					(not ParseIntMaybeHex(Tokens[2], WaitMs)) then
				begin
					WriteLn(StdErr, 'automation: invalid dump values: ', Clean);
					Continue;
				end;
				FillChar(Action, SizeOf(Action), 0);
				Action.Kind := aaDumpRow;
				Action.PatternIndex := X;
				Action.RowIndex := Y;
				Action.ChannelIndex := WaitMs;
				Action.DumpAllChannels := False;
				AddAction(Action);
			end
			else
			if (Cmd = 'quit') or (Cmd = 'exit') then
			begin
				FillChar(Action, SizeOf(Action), 0);
				Action.Kind := aaQuit;
				AddAction(Action);
			end
			else
			begin
				WriteLn(StdErr, 'automation: unknown command: ', Clean);
				Continue;
			end;
		end;
	finally
		Tokens.Free;
		Lines.Free;
	end;
end;

procedure TAutomationRunner.Start(ExitOnComplete: Boolean);
begin
	FExitOnComplete := ExitOnComplete;
	FIndex := 0;
	FNextTime := 0;
	FActive := Length(FActions) > 0;
	FShouldQuit := False;
end;

procedure TAutomationRunner.ProcessFrame(Window: PSDL_Window);
var
	NowMs: UInt32;
	Action: TAutomationAction;
	X, Y: Integer;
begin
	if not FActive then Exit;

	NowMs := SDL_GetTicks;
	if (FNextTime <> 0) and (NowMs < FNextTime) then Exit;

	FNextTime := 0;
	if FIndex > High(FActions) then
	begin
		FActive := False;
		if FExitOnComplete then
			FShouldQuit := True;
		Exit;
	end;

	Action := FActions[FIndex];
	Inc(FIndex);

	case Action.Kind of
		aaWait:
			FNextTime := NowMs + Action.WaitMs;
		aaKey:
			PushKey(Action.Shortcut);
		aaText:
			PushText(Action.Text);
		aaMouseMove:
			if ResolveMousePoint(Action, X, Y) then
				WarpMouse(Window, X, Y);
		aaMouseDown:
			if ResolveMousePoint(Action, X, Y) then
				PushMouseButton(Action.MouseButton, True, X, Y);
		aaMouseUp:
			if ResolveMousePoint(Action, X, Y) then
				PushMouseButton(Action.MouseButton, False, X, Y);
		aaMouseClick:
			if ResolveMousePoint(Action, X, Y) then
			begin
				WarpMouse(Window, X, Y);
				PushMouseButton(Action.MouseButton, True, X, Y);
				PushMouseButton(Action.MouseButton, False, X, Y);
			end;
		aaMouseWheel:
			PushMouseWheel(Action.WheelY);
		aaDumpRow:
			begin
				if Module = nil then
				begin
					WriteLn(StdErr, 'automation: dump-row failed (no module loaded)');
					Exit;
				end;
				if (Action.PatternIndex < 0) or (Action.PatternIndex > Module.Info.PatternCount) then
				begin
					WriteLn(StdErr, 'automation: dump-row invalid pattern ', Action.PatternIndex);
					Exit;
				end;
				if (Action.RowIndex < 0) or (Action.RowIndex > 63) then
				begin
					WriteLn(StdErr, 'automation: dump-row invalid row ', Action.RowIndex);
					Exit;
				end;

				if Action.DumpAllChannels then
				begin
					for X := 0 to AMOUNT_CHANNELS-1 do
						WriteLn(StdErr, Format(
							'dump pattern=%d row=%s ch=%d cmd=%s param=%s',
							[
								Action.PatternIndex,
								IntToHex(Action.RowIndex, 2),
								X,
								IntToHex(Module.Notes[Action.PatternIndex, X, Action.RowIndex].Command, 2),
								IntToHex(Module.Notes[Action.PatternIndex, X, Action.RowIndex].Parameter, 2)
							]
						));
				end
				else
				begin
					if (Action.ChannelIndex < 0) or (Action.ChannelIndex >= AMOUNT_CHANNELS) then
					begin
						WriteLn(StdErr, 'automation: dump invalid channel ', Action.ChannelIndex);
						Exit;
					end;
					WriteLn(StdErr, Format(
						'dump pattern=%d row=%s ch=%d cmd=%s param=%s',
						[
							Action.PatternIndex,
							IntToHex(Action.RowIndex, 2),
							Action.ChannelIndex,
							IntToHex(Module.Notes[Action.PatternIndex, Action.ChannelIndex, Action.RowIndex].Command, 2),
							IntToHex(Module.Notes[Action.PatternIndex, Action.ChannelIndex, Action.RowIndex].Parameter, 2)
						]
					));
				end;
			end;
		aaQuit:
			begin
				FShouldQuit := True;
				FActive := False;
			end;
	end;
end;

function TAutomationRunner.IsActive: Boolean;
begin
	Result := FActive;
end;

function TAutomationRunner.ShouldQuit: Boolean;
begin
	Result := FShouldQuit;
end;

procedure InitAutomation(const ScriptFilename: String; ExitOnComplete: Boolean);
begin
	if Automation = nil then
		Automation := TAutomationRunner.Create;
	Automation.LoadScript(ScriptFilename);
	Automation.Start(ExitOnComplete);
end;

procedure ProcessAutomationFrame(Window: PSDL_Window);
begin
	if Automation <> nil then
		Automation.ProcessFrame(Window);
end;

function AutomationShouldQuit: Boolean;
begin
	Result := (Automation <> nil) and Automation.ShouldQuit;
end;

function AutomationIsActive: Boolean;
begin
	Result := (Automation <> nil) and Automation.IsActive;
end;

initialization
	Automation := nil;

finalization
	if Automation <> nil then
		Automation.Free;

end.
