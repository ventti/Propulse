unit CommandLine;

interface

uses
	SysUtils, ConfigurationManager;

procedure ParseCommandLine;
procedure ApplySettingsOverrides(const Cfg: TConfigurationManager);
procedure RestoreSettingsOverrides(const Cfg: TConfigurationManager);
function GetRequestedModuleFilename: String;

implementation

uses
	Classes,
	IniFiles,
	StrUtils,
	BuildInfo,
	ProTracker.Util;

type
	TOverrideKind = (okNone, okBool, okByte, okInt, okCard, okFloat, okString);

	TSettingOverride = record
		Section: String;
		Name: String;
		Value: String;
		Item: TConfigItem;
		Applied: Boolean;
		Kind: TOverrideKind;
		OrigBool: Boolean;
		OrigByte: Byte;
		OrigInt: Integer;
		OrigCard: Cardinal;
		OrigFloat: Single;
		OrigString: String;
	end;

var
	Overrides: array of TSettingOverride;
	RequestedModuleFilename: String;

function GetRequestedModuleFilename: String;
begin
	Result := RequestedModuleFilename;
end;

function GetVersionText: String;
begin
	if Build.GitDescribe <> 'unknown' then
		Result := 'Propulse Tracker v' + ProTracker.Util.VERSION +
			' (' + Build.GitDescribe + ') (built on ' +
			Build.CompileDate + ' ' + Build.CompileTime + ')'
	else
		Result := 'Propulse Tracker v' + ProTracker.Util.VERSION +
			' (built on ' + Build.CompileDate + ' ' + Build.CompileTime + ')';
end;

procedure PrintHelpAndExit(ExitCode: Integer);
var
	ExeName: String;
begin
	ExeName := ExtractFileName(ParamStr(0));
	if ExeName = '' then ExeName := 'propulse';

	WriteLn('Usage: ', ExeName, ' [options] [modulefile]');
	WriteLn('');
	WriteLn('Options:');
	WriteLn('  -h, --help                    Show this help and exit');
	WriteLn('  -v, --version                 Show version/build info and exit');
	WriteLn('  --print-config                Print config keys/values (from propulse.ini) and exit');
	WriteLn('  --set section.name=value      Override a settings value for this run (may be repeated)');
	WriteLn('');
	WriteLn('Notes:');
	WriteLn('  - Setting names reuse the same Section/Name identifiers as the Settings UI.');
	WriteLn('  - Overrides are temporary and are not written back to the configuration file.');
	Halt(ExitCode);
end;

procedure PrintVersionAndExit;
begin
	WriteLn(GetVersionText);
	Halt(0);
end;

procedure PrintConfigAndExit;
var
	ExeDir: String;
	DataPath: String;
	ConfigPath: String;
	ConfigFilename: String;
	Ini: TIniFile;
	Sections: TStringList;
	Keys: TStringList;
	Sect: String;
	i: Integer;
	Key: String;
	Val: String;
begin
	// Mirror MainWindow's config path behavior (but keep it independent of full GUI startup).
	ExeDir := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ParamStr(0))));
	DataPath := ExeDir + 'data/';

	ConfigPath := GetAppConfigDir(False);
	if ConfigPath = '' then
		ConfigPath := DataPath;
	ConfigPath := IncludeTrailingPathDelimiter(ConfigPath);

	ConfigFilename := ConfigPath + FILENAME_CONFIG;
	if not FileExists(ConfigFilename) then
	begin
		WriteLn(StdErr, 'warning: config file not found: ', ConfigFilename);
		Halt(0);
	end;

	Ini := TIniFile.Create(ConfigFilename);
	Sections := TStringList.Create;
	Keys := TStringList.Create;
	try
		Sections.Sorted := True;
		Sections.Duplicates := dupIgnore;
		Ini.ReadSections(Sections);

		for Sect in Sections do
		begin
			Keys.Clear;
			Keys.Sorted := True;
			Keys.Duplicates := dupIgnore;
			Ini.ReadSection(Sect, Keys);

			for i := 0 to Keys.Count - 1 do
			begin
				Key := Keys[i];
				Val := Ini.ReadString(Sect, Key, '');
				WriteLn(Sect, '.', Key, '=', Val);
			end;
		end;
	finally
		Keys.Free;
		Sections.Free;
		Ini.Free;
	end;

	Halt(0);
end;

procedure AddOverrideFromSpec(const Spec: String);
var
	EqPos: SizeInt;
	DotPos: SizeInt;
	Sect, Name, Val: String;
	i: Integer;
begin
	EqPos := Pos('=', Spec);
	if EqPos <= 0 then
	begin
		WriteLn(StdErr, 'warning: invalid --set argument (missing "="): ', Spec);
		Exit;
	end;

	Val := Copy(Spec, EqPos + 1, MaxInt);
	Sect := Copy(Spec, 1, EqPos - 1);

	DotPos := Pos('.', Sect);
	if DotPos <= 0 then
	begin
		WriteLn(StdErr, 'warning: invalid --set name (expected section.name): ', Copy(Spec, 1, EqPos - 1));
		Exit;
	end;

	Name := Copy(Sect, DotPos + 1, MaxInt);
	Sect := Copy(Sect, 1, DotPos - 1);

	if (Sect = '') or (Name = '') then
	begin
		WriteLn(StdErr, 'warning: invalid --set name (expected section.name): ', Copy(Spec, 1, EqPos - 1));
		Exit;
	end;

	i := Length(Overrides);
	SetLength(Overrides, i + 1);
	Overrides[i].Section := Sect;
	Overrides[i].Name := Name;
	Overrides[i].Value := Val;
	Overrides[i].Item := nil;
	Overrides[i].Applied := False;
	Overrides[i].Kind := okNone;
end;

procedure ParseCommandLine;
var
	i: Integer;
	Arg: String;
	AbsFn: String;
begin
	i := 1;
	while i <= ParamCount do
	begin
		Arg := ParamStr(i);

		if (Arg = '-h') or (Arg = '--help') then
			PrintHelpAndExit(0)
		else
		if (Arg = '-v') or (Arg = '--version') then
			PrintVersionAndExit
		else
		if Arg = '--print-config' then
			PrintConfigAndExit
		else
		if Arg = '--set' then
		begin
			Inc(i);
			if i > ParamCount then
			begin
				WriteLn(StdErr, 'warning: missing argument after --set');
				Exit;
			end;
			AddOverrideFromSpec(ParamStr(i));
		end
		else
		begin
			// Optional positional argument: module filename.
			// Only treat non-option arguments as a module filename.
			if (Arg <> '') and (Arg[1] <> '-') then
			begin
				if RequestedModuleFilename = '' then
					RequestedModuleFilename := Arg
				else
					WriteLn(StdErr, 'warning: ignoring extra positional argument: ', Arg);
			end
			else
			begin
				// Be permissive: ignore unknown options/args to avoid breaking platform launchers
				// (e.g. macOS may pass process serial number flags to GUI apps).
			end;
		end;

		Inc(i);
	end;

	// Validate module file if provided. Resolve relative paths from the current working directory.
	if RequestedModuleFilename <> '' then
	begin
		AbsFn := ExpandFileName(RequestedModuleFilename);
		if not FileExists(AbsFn) then
		begin
			WriteLn(StdErr, 'error: module file not found: ', RequestedModuleFilename);
			WriteLn(StdErr, '       resolved path: ', AbsFn);
			Halt(1);
		end;
		RequestedModuleFilename := AbsFn;
	end;
end;

function FindConfigItem(const Cfg: TConfigurationManager; const Sect, Name: String): TConfigItem;
var
	CI: TConfigItem;
begin
	Result := nil;
	if Cfg = nil then Exit;
	for CI in Cfg.Items do
		if (CI.Section = Sect) and (CI.Name = Name) then
			Exit(CI);
end;

function ParseBool(const S: String; out V: Boolean): Boolean;
var
	T: String;
begin
	T := LowerCase(Trim(S));
	if (T = '1') or (T = 'true') or (T = 'yes') or (T = 'on') then
	begin
		V := True;
		Exit(True);
	end;
	if (T = '0') or (T = 'false') or (T = 'no') or (T = 'off') then
	begin
		V := False;
		Exit(True);
	end;
	Result := False;
end;

procedure ApplySettingsOverrides(const Cfg: TConfigurationManager);
var
	i, j: Integer;
	CI: TConfigItem;
	B: Boolean;
	N: Integer;
	C: Cardinal;
	F: Double;
	S: String;
begin
	if (Cfg = nil) or (Length(Overrides) <= 0) then Exit;

	for i := 0 to High(Overrides) do
	begin
		CI := FindConfigItem(Cfg, Overrides[i].Section, Overrides[i].Name);
		if CI = nil then
		begin
			WriteLn(StdErr, 'warning: unknown setting: ', Overrides[i].Section, '.', Overrides[i].Name);
			Continue;
		end;

		Overrides[i].Item := CI;

		if CI is TConfigItemBoolean then
		begin
			if not ParseBool(Overrides[i].Value, B) then
			begin
				WriteLn(StdErr, 'warning: invalid boolean value for ', CI.Section, '.', CI.Name, ': ', Overrides[i].Value);
				Continue;
			end;
			Overrides[i].Kind := okBool;
			Overrides[i].OrigBool := TConfigItemBoolean(CI).Value^;
			TConfigItemBoolean(CI).Value^ := B;
			Overrides[i].Applied := True;
		end
		else
		if CI is TConfigItemByte then
		begin
			N := StrToIntDef(Trim(Overrides[i].Value), -1);
			if (N < CI.Min) or (N > CI.Max) then
			begin
				WriteLn(StdErr, 'warning: out-of-range value for ', CI.Section, '.', CI.Name, ': ', Overrides[i].Value);
				Continue;
			end;
			Overrides[i].Kind := okByte;
			Overrides[i].OrigByte := TConfigItemByte(CI).Value^;
			TConfigItemByte(CI).SetValue(N);
			Overrides[i].Applied := True;
		end
		else
		if CI is TConfigItemInteger then
		begin
			N := StrToIntDef(Trim(Overrides[i].Value), Low(Integer));
			if (N = Low(Integer)) and (Trim(Overrides[i].Value) <> IntToStr(Low(Integer))) then
			begin
				WriteLn(StdErr, 'warning: invalid integer value for ', CI.Section, '.', CI.Name, ': ', Overrides[i].Value);
				Continue;
			end;
			if (N < CI.Min) or (N > CI.Max) then
			begin
				WriteLn(StdErr, 'warning: out-of-range value for ', CI.Section, '.', CI.Name, ': ', Overrides[i].Value);
				Continue;
			end;
			Overrides[i].Kind := okInt;
			Overrides[i].OrigInt := TConfigItemInteger(CI).Value^;
			TConfigItemInteger(CI).SetValue(N);
			Overrides[i].Applied := True;
		end
		else
		if CI is TConfigItemCardinal then
		begin
			S := Trim(Overrides[i].Value);
			try
				C := Cardinal(StrToInt(S));
			except
				on E: Exception do
				begin
					WriteLn(StdErr, 'warning: invalid cardinal value for ', CI.Section, '.', CI.Name, ': ', Overrides[i].Value);
					Continue;
				end;
			end;
			if (C < Cardinal(CI.Min)) or (C > Cardinal(CI.Max)) then
			begin
				WriteLn(StdErr, 'warning: out-of-range value for ', CI.Section, '.', CI.Name, ': ', Overrides[i].Value);
				Continue;
			end;
			Overrides[i].Kind := okCard;
			Overrides[i].OrigCard := TConfigItemCardinal(CI).Value^;
			TConfigItemCardinal(CI).Value^ := C;
			Overrides[i].Applied := True;
		end
		else
		if CI is TConfigItemFloat then
		begin
			try
				F := StrToFloat(Trim(Overrides[i].Value), DefaultFormatSettings);
			except
				on E: Exception do
				begin
					WriteLn(StdErr, 'warning: invalid float value for ', CI.Section, '.', CI.Name, ': ', Overrides[i].Value);
					Continue;
				end;
			end;
			if (F < CI.Min) or (F > CI.Max) then
			begin
				WriteLn(StdErr, 'warning: out-of-range value for ', CI.Section, '.', CI.Name, ': ', Overrides[i].Value);
				Continue;
			end;
			Overrides[i].Kind := okFloat;
			Overrides[i].OrigFloat := TConfigItemFloat(CI).Value^;
			TConfigItemFloat(CI).Value^ := F;
			Overrides[i].Applied := True;
		end
		else
		if CI is TConfigItemString then
		begin
			S := Overrides[i].Value;
			if (S = '') and (not TConfigItemString(CI).AllowEmpty) then
			begin
				WriteLn(StdErr, 'warning: empty value not allowed for ', CI.Section, '.', CI.Name);
				Continue;
			end;
			Overrides[i].Kind := okString;
			Overrides[i].OrigString := TConfigItemString(CI).Value^;
			TConfigItemString(CI).Value^ := S;

			// Keep CurrentIndex in sync when ValueNames is used.
			for j := 0 to High(CI.ValueNames) do
				if CI.ValueNames[j] = S then
				begin
					TConfigItemString(CI).CurrentIndex := j;
					Break;
				end;

			Overrides[i].Applied := True;
		end
		else
		begin
			WriteLn(StdErr, 'warning: unsupported setting type for ', CI.Section, '.', CI.Name);
			Continue;
		end;
	end;
end;

procedure RestoreSettingsOverrides(const Cfg: TConfigurationManager);
var
	i: Integer;
	CI: TConfigItem;
begin
	if (Cfg = nil) or (Length(Overrides) <= 0) then Exit;

	for i := 0 to High(Overrides) do
	begin
		if not Overrides[i].Applied then Continue;

		CI := Overrides[i].Item;
		if CI = nil then
			CI := FindConfigItem(Cfg, Overrides[i].Section, Overrides[i].Name);
		if CI = nil then Continue;

		case Overrides[i].Kind of
			okBool:   if CI is TConfigItemBoolean  then TConfigItemBoolean(CI).Value^ := Overrides[i].OrigBool;
			okByte:   if CI is TConfigItemByte     then TConfigItemByte(CI).Value^    := Overrides[i].OrigByte;
			okInt:    if CI is TConfigItemInteger  then TConfigItemInteger(CI).Value^ := Overrides[i].OrigInt;
			okCard:   if CI is TConfigItemCardinal then TConfigItemCardinal(CI).Value^:= Overrides[i].OrigCard;
			okFloat:  if CI is TConfigItemFloat    then TConfigItemFloat(CI).Value^   := Overrides[i].OrigFloat;
			okString: if CI is TConfigItemString   then TConfigItemString(CI).Value^  := Overrides[i].OrigString;
		else
		end;
	end;
end;

end.


