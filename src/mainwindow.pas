unit MainWindow;

{$I propulse.inc}

interface

uses
	Classes, Types, SysUtils, Generics.Collections,
	SDL2,
	ConfigurationManager, ShortcutManager, TextMode,
	CWE.Core, CWE.MouseCursor, CWE.Dialogs, CWE.Widgets.Text,
	{$IFDEF MIDI}ProTracker.MIDI,{$ENDIF}
	ProTracker.Util, ProTracker.Player, ProTracker.Editor;

type
	GlobalKeyNames = (
		keyNONE,				keyMainMenu,
		keyProgramQuit,			keyProgramFullscreen,
		keyScreenHelp,			keyScreenPatternEditor,
		keyScreenSamples,		keyScreenAbout,
		keyScreenLoad,			keyScreenSave,
		keyScreenOrderList,		keyScreenLog,
		keyScreenLayout,		keyScreenConfig,
		keyPlaybackSong,		keyPlaybackPattern,
		keyPlaybackPlayFrom,	keyPlaybackStop,
		keyPlaybackPrevPattern, keyPlaybackNextPattern,
		keyControlsPrevious,	keyControlsNext,
		keySongLength,			keyJumpToTime,
		keySongNew,
		keyMouseCursor,			keySaveCurrent,
		keyRenderToSample,		keyCleanup,
		keyToggleChannel1,		keyToggleChannel2,
		keyToggleChannel3,		keyToggleChannel4,
		keyMetadataNotes,		keyMetadataNext,
		keyMetadataPrev
	);

	TVideoInfo = record
		Renderer:		PSDL_Renderer;
		Window:			PSDL_Window;
		Texture:		PSDL_Texture;

		IsFullScreen: 	Boolean;
		HaveVSync:		Boolean;
		SyncRate:		Word;
		NextFrameTime:	UInt64;

		NewSDL: 		Boolean;
		RendererName,
		LibraryVersion:	AnsiString;
	end;

	TWindow = class
	const
		TimerInterval = 10;
	private
		{$IFDEF LIMIT_KEYBOARD_EVENTS}
		PrevKeyTimeStamp: Uint32;
		{$ENDIF}
		Screens:	TObjectList<TCWEScreen>;
		AutoSaveCounter: Integer;

		procedure 	ModuleSpeedChanged(Speed, Tempo: Byte);
		procedure	ModuleOrderChanged;
		procedure 	TimerTick;

		function 	GetMaxScaling(MaxScale: Byte = 0): Byte;
		function 	SetupVideo: Boolean;
		procedure	SetFullScreen(WantFullScreen: Boolean; Force: Boolean = False);
		procedure 	InitConfiguration;

		procedure 	HandleInput;
		procedure 	ProcessMouseMovement;
		procedure	SyncTo60Hz;
		procedure	FlipFrame;
		procedure	UpdateVUMeter(Len: DWord);
		procedure 	UpdatePatternView;
		procedure 	AutoSaveRecovery;
		function 	GetRecoveryFilename: String;
		function 	CheckRecoveryFile: Boolean; // Returns True if dialog was shown
	public
		Video:				TVideoInfo;
		MessageTextTimer,
		PlayTimeCounter:	Integer;
		Visible: 			Boolean;

		constructor Create;
		destructor 	Destroy; override;
		procedure	Close;

		procedure	ProcessFrame;
		procedure	SetTitle(const Title: AnsiString);

		procedure 	DoLoadModule(const Filename: String);
		procedure 	FinishModuleLoad(AltMethod: Boolean = False);

		procedure 	PlayModeChanged;
		procedure 	DialogCallback(ID: Word; Button: TDialogButton;
					ModalResult: Integer; Data: Variant; Dlg: TCWEDialog);
		procedure	OnKeyDown(var Key: Integer; Shift: TShiftState);
		function	OnContextMenu(AddGlobal: Boolean): Boolean;
		procedure	CleanupRecoveryFile;
	end;


	function	GetModifierKey(keymod: TSDL_Keymod; var Shift: TShiftState;
				keymodconst: Integer; shiftconst: TShiftStateEnum): Boolean; inline;
	function 	GetShiftState: TShiftState;
	function 	TimerTickCallback(interval: Uint32; param: Pointer): UInt32; cdecl;

var
	SDLLogFuncData: Integer;

	Window: 		TWindow;
	GlobalKeys: 	TKeyBindings;
	QuitFlag:		Boolean;
	Initialized:	Boolean;


implementation

uses
	{$IFDEF WINDOWS}Windows,{$ENDIF}
	{$IFDEF LAZARUS}FileUtil,{$ENDIF}
	BuildInfo, Math,
	{$IFDEF BASS}BASS,{$ENDIF}
	{$IFDEF SOXR}soxr,{$ENDIF}
	ProTracker.Messaging, ProTracker.Import,
	Screen.Editor, Screen.Samples, Screen.FileReq, Screen.FileReqSample,
	Screen.Log, Screen.Help, Screen.Config, Screen.Splash,
	Screen.Notes,
	Dialog.Cleanup, Dialog.ModuleInfo, Dialog.NewModule, Dialog.RenderAudio, Dialog.JumpToTime,
	CWE.MainMenu;


procedure SDLLogFunc(userdata: Pointer; category: Integer;
	priority: TSDL_LogPriority; const msg: PAnsiChar);
begin
	Log(msg);
end;

procedure ClearMessageQueue;
var
	InputEvent: TSDL_Event;
begin
	SDL_Delay(50);
	while SDL_PollEvent(@InputEvent) <> 0 do;
end;

procedure TWindow.DialogCallback(ID: Word; Button: TDialogButton;
	ModalResult: Integer; Data: Variant; Dlg: TCWEDialog);
begin
	// bail out if the originating modal dialog is still displaying
	// as some of these actions might want to display other dialogs
	if Dlg <> nil then Exit;

	if Button in [btnYes, btnOK] then
	case ID of

		ACTION_QUIT:
			QuitFlag := True;

		ACTION_LOADMODULE:
			DoLoadModule(Data);

		ACTION_MODULEIMPORTED:
			FinishModuleLoad;

		ACTION_NEWMODULE:
			with Editor do
			begin
				NewModule(False);
				SetSample(1);
				lblSongTitle.SetCaption(Module.Info.Title);
				lblFilename.SetCaption('');
				UpdatePatternView;
				Module.SetModified(False, True);
				if CurrentScreen = Editor then
					Paint;
			end;

		ACTION_SAVEFILE:
			FileScreen.SaveFile(False);

		ACTION_DELETEFILE:
			FileScreen.DeleteFile(False);

		ACTION_DELETEDIR:
			FileScreen.DeleteDir(False);

		ACTION_RESTORERECOVERY:
			begin
				if Button = btnYes then
				begin
					try
						DoLoadModule(Data);
						CleanupRecoveryFile;
					except
						on E: ERangeError do
						begin
							// Handle range errors from corrupted files
							Log(TEXT_FAILURE + 'Failed to restore recovery file (range error). File is corrupted.');
							try
								if FileExists(Data) then
									SysUtils.DeleteFile(Data);
							except
								// Ignore cleanup errors
							end;
							try
								DoLoadModule('');
							except
								// If even loading empty module fails, just continue
							end;
						end;
						on E: Exception do
						begin
							// Handle other exceptions
							Log(TEXT_FAILURE + 'Failed to restore recovery file: ' + E.Message);
							Log('File may be corrupted. Loading empty module instead.');
							try
								if FileExists(Data) then
									SysUtils.DeleteFile(Data);
							except
								// Ignore cleanup errors
							end;
							try
								DoLoadModule('');
							except
								// If even loading empty module fails, just continue
							end;
						end;
					end;
				end
				else
				begin
					// User chose not to restore, delete recovery file and load empty module
					try
						CleanupRecoveryFile;
					except
						// Ignore cleanup errors
					end;
					try
						DoLoadModule('');
					except
						// If loading empty module fails, just continue
					end;
				end;
			end;

	end;
end;

// ==========================================================================
// Module events
// ==========================================================================

procedure ApplyAudioSettings;
begin
	if Assigned(Module) then
		Module.ApplyAudioSettings;
end;

{$IFDEF MIDI}
procedure ApplyMIDISettings;
begin
	if MIDI <> nil then
		MIDI.SettingsChanged;
end;
{$ENDIF}

procedure PixelScalingChanged;
begin
	ClearMessageQueue;
	MouseCursor.Erase;
	Window.SetFullScreen(Window.Video.IsFullScreen);
end;

procedure ChangeMousePointer;
begin
	MouseCursor.Show := False;

	case Options.Display.MousePointer of

		CURSOR_SYSTEM:
			SDL_ShowCursor(SDL_ENABLE);

		CURSOR_CUSTOM:
			begin
				SDL_ShowCursor(SDL_DISABLE);
				MouseCursor.Show := True;
			end;

		else
			SDL_ShowCursor(SDL_DISABLE);
	end;
end;

procedure ApplyPointer;
var
	Fn: String;
begin
	if (Console.Font.Width >= 14) or (Console.Font.Height >= 14) then
		Fn := 'mouse2'
	else
		Fn := 'mouse';

	if MouseCursor <> nil then
	begin
		MouseCursor.Erase;
		MouseCursor.SetImage(Fn);
	end
	else
		MouseCursor := TMouseCursor.Create(Fn);

	ChangeMousePointer;
end;

procedure ApplyFont;
begin
	ClearMessageQueue;
	Window.SetupVideo;
	Window.SetFullScreen(Window.Video.IsFullScreen);
end;

procedure TWindow.UpdateVUMeter(Len: DWord);
var
	InModal: Boolean;
	{$IFDEF MIDI_DISPLAY}
	i: Integer;
	Vol: Single;
	{$ENDIF}
begin
	// this hack will update the background screen (vumeters etc.) if a module
	// is currently playing underneath a modal dialog
	if not Assigned(Module) then Exit;
	InModal := (ModalDialog.Dialog <> nil) and (Module.PlayMode <> PLAY_STOPPED);
	if InModal then
		CurrentScreen := ModalDialog.PreviousScreen;

	if CurrentScreen = Editor then
		Editor.UpdateVUMeter(Len)
	else
	if CurrentScreen = SampleScreen then
		SampleScreen.UpdateVUMeter
	else
	if CurrentScreen = SampleRequester then
		SampleRequester.Waveform.Paint;
	{else
	if (InModal) and (CurrentScreen = SplashScreen) then
		SplashScreen.Update;}

	if InModal then
	begin
		CurrentScreen := ModalDialog.Dialog;
		Console.Bitmap.FillRect(Console.GetPixelRect(CurrentScreen.Rect),
			Console.Palette[TConsole.COLOR_PANEL]);
		CurrentScreen.Paint;
	end;

	{$IFDEF MIDI_DISPLAY}
	if (MIDI <> nil) and (Options.Midi.UseDisplay) then
		for i := 0 to AMOUNT_CHANNELS-1 do
		with Module.Channel[i].Paula do
		begin
			if Enabled then
				Vol := Volume
			else
				Vol := 0;
			if (CurrentScreen <> Editor) and (Volume >= 0.025) then
				Volume := Volume - 0.025;
			MIDI.UpdateVUMeter(i, Vol);
		end;
	{$ENDIF}
end;

procedure TWindow.UpdatePatternView;
begin
	if not Assigned(Module) then Exit;
	if CurrentScreen = Editor then
	with Editor do
	begin
		if FollowPlayback then
		begin
			PatternEditor.ScrollPos := Max(Module.PlayPos.Row - 16, 0);
			CurrentPattern := Module.PlayPos.Pattern;
		end;
		UpdateInfoLabels;
		PatternEditor.Paint;
	end;
end;

procedure TWindow.ModuleSpeedChanged(Speed, Tempo: Byte);
begin
	Editor.UpdateInfoLabels(False, Speed, Tempo);
end;

procedure TWindow.ModuleOrderChanged;
begin
	if CurrentScreen = Editor then
	begin
		OrderList.Paint;
		UpdatePatternView;
	end;
end;

procedure TWindow.PlayModeChanged;
var
	S: AnsiString;
begin
	if CurrentScreen <> Editor then Exit;
	if not Assigned(Module) then Exit;

	case Module.PlayMode of
		PLAY_PATTERN:	S := #16 + ' Pattern';
		PLAY_SONG:		S := #16 + ' Song';
		else
			S := ''; // #219 + ' Stopped';
			FollowPlayback := False;
	end;

	Editor.lblPlayMode.ColorFore := 3;
	Editor.lblPlayMode.SetCaption(S);
	Editor.Paint;
	UpdatePatternView;
end;

procedure TWindow.DoLoadModule(const Filename: String);

	function ResetModule: TPTModule;
	begin
		Result := TPTModule.Create(True, False);

		Result.OnSpeedChange := ModuleSpeedChanged;
		Result.OnPlayModeChange := PlayModeChanged;
		Result.OnModified := PatternEditor.SetModified;
	end;

var
	OK{, AltMethod}: Boolean;
	TempModule: TPTModule;
	RecoveryFilename: String;
	FileTime: TDateTime;
begin
	TempModule := ResetModule;
	//AltMethod := False;

	if Filename <> '' then
	begin
		try
			OK := TempModule.LoadFromFile(Filename);
			if not OK then // try again in case file is broken
			begin
				TempModule.Warnings := False;
				if Assigned(Module) then
					Module.Warnings := False;
				{AltMethod := True;
				OK := TempModule.LoadFromFile(Filename, True);}
			end;
		except
			on E: ERangeError do
			begin
				// Handle range errors from corrupted files
				OK := False;
				TempModule.Warnings := False;
				if Assigned(Module) then
					Module.Warnings := False;
				Log(TEXT_FAILURE + 'Failed to load file (range error): ' + Filename);
				Log('File may be corrupted or invalid.');
			end;
			on E: Exception do
			begin
				// Handle other exceptions from corrupted or invalid files
				OK := False;
				TempModule.Warnings := False;
				if Assigned(Module) then
					Module.Warnings := False;
				Log(TEXT_FAILURE + 'Failed to load file: ' + Filename);
				Log('Error: ' + E.Message);
				Log('File may be corrupted or invalid.');
			end;
		end;
	end
	else
		OK := True;

	if not OK then
	begin
		TempModule.Free;
		Log('');
		ChangeScreen(TCWEScreen(LogScreen));
		Exit;
	end
	else
	begin
		if Assigned(Module) then
		begin
			if not TempModule.Warnings then
				TempModule.Warnings := Module.Warnings;
			Module.Free;
		end;
		Module := TempModule;

		{$IFDEF BASS}
		if Stream <> 0 then
			BASS_ChannelPlay(Stream, True);
		{$ENDIF}

		Module.PlayPos.Order := 0;
		CurrentPattern := Module.OrderList[0];
		CurrentSample := 1;
		Editor.Reset;
		Module.SetModified(False, True);

		ChangeScreen(TCWEScreen(Editor));

		Editor.SetSample(1);
		Editor.lblSongTitle.SetCaption(Module.Info.Title, True);
		Editor.lblFilename.SetCaption(ExtractFilename(Filename), True);

		Editor.Paint;

		// Check for autosave file for this module
		if (Filename <> '') and (ModalDialog.Dialog = nil) then
		begin
			RecoveryFilename := GetRecoveryFilename;
			if (RecoveryFilename <> '') and FileExists(RecoveryFilename) then
			begin
				try
					FileTime := FileDateToDateTime(FileAge(RecoveryFilename));
					// Check if autosave is newer than the loaded file
					if (FileTime > FileDateToDateTime(FileAge(Filename))) then
					begin
						ModalDialog.MessageDialog(ACTION_RESTORERECOVERY,
							'Autosave Found',
							Format('An autosave file was found from %s, which is newer than the loaded file.'#13 +
								'Would you like to restore the autosave?',
								[FormatDateTime('YYYY-mm-dd hh:nn:ss', FileTime)]),
							[btnYes, btnNo], btnYes, DialogCallback, RecoveryFilename);
					end;
				except
					// Ignore errors
				end;
			end;
		end;

		if (ImportedModule <> nil) and (ImportedModule.Conversion.TotalChannels > AMOUNT_CHANNELS) then
			ImportedModule.ShowImportDialog
		else
		if Filename <> '' then
			FinishModuleLoad(False{AltMethod});
	end;
end;

procedure TWindow.FinishModuleLoad(AltMethod: Boolean = False);
var
	S: AnsiString;
begin
	S := '';

	if ImportedModule <> nil then
	begin
		FreeAndNil(ImportedModule);
		Editor.Reset;
		Editor.Paint;
	end;

	if (Module.Warnings) {or (AltMethod)} then
	begin
		//if Module.Warnings then
			S := 'Module loaded with errors/warnings.' + CHAR_NEWLINE;
		{if AltMethod then
			S := S + 'The module was loaded from a nonstandard offset,' + CHAR_NEWLINE +
				'indicating a broken or non-module file.' + CHAR_NEWLINE;}
	end;

	if not Module.Warnings then
		Log(TEXT_SUCCESS + 'Load success.')
	else
		Log(TEXT_FAILURE + 'Loaded with errors/warnings.');
	Log('-');

	Module.Warnings := False;

	if S <> '' then
		ModalDialog.MultiLineMessage('Module loaded',
			S + 'See the Message Log for more info.');
	//ChangeScreen(TCWEScreen(LogScreen))
end;

function TWindow.SetupVideo: Boolean;

	function SetHint(const Hint: AnsiString; Val: Boolean): Boolean;
	var
		bs: AnsiString;
	begin
		if Val then bs := '1' else bs := '0';
		Result := SDL_SetHint(PAnsiChar(Hint), PAnsiChar(bs));
		if not Result then
			LogIfDebug('Failed to set SDL hint "' + Hint + '"!');
	end;

	function GetFontFile(const Fn: String): String;
	begin
		Result := 'font/' + Fn + '.pcx';
	end;

var
	dm: TSDL_DisplayMode;
	windowFlags: TSDL_WindowFlags;
	rendererFlags: TSDL_RendererFlags;
	screenW, screenH, sx, sy: Word;
	Icon: PSDL_Surface;
	Fn: String;
	rinfo: TSDL_RendererInfo;
	sdlVersion: TSDL_Version;
	OK: Boolean;
begin
    Result := False;
	Locked := True;
	Visible := True;

	Fn := GetDataFile(GetFontFile(Options.Display.Font));
	if Fn = '' then
	begin
		Options.Display.Font := FILENAME_DEFAULTFONT;
		Fn := GetDataFile(GetFontFile(FILENAME_DEFAULTFONT));
	end;

	if not Initialized then
	begin
		OK := (Fn <> '');
		if OK then
			Console := TConsole.Create(80, 45, GetFontFile(Options.Display.Font),
				GetDataFile('palette/Propulse.ini'), OK);
		if not OK then
		begin
			LogFatal('Error initializing console emulation!');
			LogFatal('Probably the file "' + Options.Display.Font + '" couldn''t be found.');
			Exit;
		end;
	end
	else
	begin
		sx := Console.Font.Width;
		sy := Console.Font.Height;
		Console.LoadFont('font/' + Options.Display.Font);
		if (sx <> Console.Font.Width) or (sy <> Console.Font.Height) then
		begin
			ApplyPointer;
			SplashScreen.Init;
		end;
	end;

	screenW := Console.Bitmap.Width;
	screenH := Console.Bitmap.Height;
	sx := screenW * Options.Display.Scaling;
	sy := screenH * Options.Display.Scaling;

	if not Initialized then
	begin
		SDL_GetVersion(@sdlVersion);
		Video.NewSDL := sdlVersion.patch >= 5; // we want SDL 2.0.5 or newer
		Video.LibraryVersion := Format('%d.%d.%d',
			[sdlVersion.major, sdlVersion.minor, sdlVersion.patch]);
		LogIfDebug('Loaded SDL ' + Video.LibraryVersion);
	end;

	windowFlags := 0;
	rendererFlags := UInt32(SDL_RENDERER_ACCELERATED or SDL_RENDERER_TARGETTEXTURE);

	if Video.NewSDL then
		SetHint(SDL_HINT_WINDOWS_DISABLE_THREAD_NAMING, True);
	SetHint(SDL_HINT_TIMER_RESOLUTION, True);
	SetHint(SDL_HINT_VIDEO_HIGHDPI_DISABLED, True);
	SetHint(SDL_HINT_WINDOWS_NO_CLOSE_ON_ALT_F4, True);

	{$IFDEF UNIX}
		{$IFDEF DISABLE_FULLSCREEN}
		SetHint('SDL_VIDEO_X11_XRANDR',   False);
		SetHint('SDL_VIDEO_X11_XVIDMODE', True);
		{$ENDIF}
	{$ENDIF}

	if not Initialized then
	begin
		if SDL_Init(SDL_INIT_VIDEO or SDL_INIT_TIMER) <> 0 then
		begin
			LogFatal('Error initializing SDL: ' + SDL_GetError);
			Exit;
		end;

		SDL_SetThreadPriority(SDL_THREAD_PRIORITY_HIGH);
		SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, 'nearest');
	end
	else
	begin
		SDL_DestroyRenderer(Video.Renderer);
		SDL_DestroyTexture(Video.Texture);
		SDL_DestroyWindow(Video.Window);
	end;

	Video.HaveVSync := False;
	Video.SyncRate := 0;

	if Options.Display.VSyncMode <> VSYNC_OFF then
	begin
		if SDL_GetDesktopDisplayMode(0, @dm) = 0 then
			Video.SyncRate := dm.refresh_rate
		else
			Log('GetDesktopDisplayMode failed: ' + SDL_GetError);
		if (Options.Display.VSyncMode = VSYNC_FORCE) or
			(Video.SyncRate in [50..61]) then
		begin
			rendererFlags := rendererFlags or UInt32(SDL_RENDERER_PRESENTVSYNC);
			Video.HaveVSync := True;
		end;
	end;

	windowFlags := UInt32(SDL_WINDOW_SHOWN);

	Video.Window := SDL_CreateWindow('Propulse Tracker',
		SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, sx, sy, windowFlags);
	if Video.Window = nil then
	begin
		LogFatal('Error setting up window: ' + SDL_GetError);
		Exit;
	end;

	// make sure not to exceed display bounds
	sx := GetMaxScaling;
	if sx <> Options.Display.Scaling then
	begin
		sy := screenH * sx;
		sx := screenW * sx;
		SDL_SetWindowSize(Video.Window, sx, sy);
		SDL_SetWindowPosition(Video.Window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
	end;

	Video.Renderer := SDL_CreateRenderer(Video.Window, -1, rendererFlags);
	if (Video.Renderer = nil) and (Video.HaveVSync) then
	begin
		// try again without vsync flag
		Video.HaveVSync := False;
		rendererFlags := rendererFlags and not UInt32(SDL_RENDERER_PRESENTVSYNC);
		Video.Renderer := SDL_CreateRenderer(Video.Window, -1, rendererFlags);
		if Video.Renderer = nil then
		begin
			LogFatal('Error creating renderer: ' + SDL_GetError);
			Exit;
		end;
	end;
	SDL_SetRenderDrawBlendMode(Video.Renderer, SDL_BLENDMODE_NONE);

	SDL_GetRendererInfo(Video.Renderer, @rinfo);
	Video.RendererName := rinfo.name;

	if SDL_RenderSetLogicalSize(Video.Renderer, screenW, screenH) <> 0 then
	begin
		LogFatal('Error setting renderer size: ' + SDL_GetError);
		Exit;
	end;

	{$IFNDEF DISABLE_SDL2_2_0_5}
	if Video.NewSDL then
		SDL_RenderSetIntegerScale(Video.Renderer, SDL_TRUE);
	{$ENDIF}

	Video.Texture := SDL_CreateTexture(Video.Renderer,
		UInt32(SDL_PIXELFORMAT_ARGB8888),
		SInt32(SDL_TEXTUREACCESS_STREAMING), screenW, screenH);
	if Video.Texture = nil then
	begin
		LogFatal('Error initializing streaming texture: ' + SDL_GetError);
		Exit;
	end;
	SDL_SetTextureBlendMode(Video.Texture, SDL_BLENDMODE_NONE);

	Fn := GetDataFile('icon.bmp');
	if (Fn <> '') and FileExists(Fn) then
	begin
		Icon := SDL_LoadBMP(PAnsiChar(Fn));
		SDL_SetWindowIcon(Video.Window, Icon);
		SDL_FreeSurface(Icon);
	end;

	if Initialized then
	begin
		Console.Refresh;
		if CurrentScreen <> nil then
		begin
			CurrentScreen.Show;
			CurrentScreen.Paint;
		end;
	end;

	Video.NextFrameTime := Trunc(SDL_GetPerformanceCounter +
		((SDL_GetPerformanceFrequency / 60.0) + 0.5));

	Result := True;
	Locked := False;
end;

procedure TWindow.FlipFrame;
begin
	if Locked then Exit;

	if CurrentScreen = SplashScreen then
		SplashScreen.Update;

	MouseCursor.Draw;

	SDL_UpdateTexture(Video.Texture, nil, @Console.Bitmap.Bits[0], Console.Bitmap.Width*4);
	SDL_RenderCopy(Video.Renderer, Video.Texture, nil, nil);
	SDL_RenderPresent(Video.Renderer);

	MouseCursor.Erase;
end;

function TWindow.GetMaxScaling(MaxScale: Byte = 0): Byte;
var
	w, h: Integer;
	R: TSDL_Rect;
begin
	if MaxScale = 0 then MaxScale := Max(Options.Display.Scaling, 1);

	{$IFNDEF DISABLE_SDL2_2_0_5}
	if Video.NewSDL then
		SDL_GetDisplayUsableBounds(SDL_GetWindowDisplayIndex(Video.Window), @R)
	else
	{$ENDIF}
		SDL_GetDisplayBounds(SDL_GetWindowDisplayIndex(Video.Window), @R);

	repeat
		w := Console.Bitmap.Width  * MaxScale;
		h := Console.Bitmap.Height * MaxScale;
		if (w <= R.w) and (h <= R.h) then Break;
		Dec(MaxScale);
	until MaxScale <= 1;
	Result := Max(MaxScale, 1);
end;

procedure TWindow.SetFullScreen(WantFullScreen: Boolean; Force: Boolean = False);
var
	w, h: Integer;
	X, Y: Single;
	{$IFDEF DISABLE_FULLSCREEN}
	R: SDL_Rect;
	{$ENDIF}
const
	SDL_WINDOW_WINDOWED = 0;
label
	GetMouseScale;
begin
	if (Locked) or ((not Force) and (Video.IsFullScreen = WantFullScreen)) then goto GetMouseScale;

	Locked := True;
	Visible := True;
	Video.IsFullScreen := WantFullScreen;

	if WantFullScreen then
	begin
    	{$IFNDEF DISABLE_FULLSCREEN}
		//SDL_SetWindowFullscreen(Video.Window, SDL_WINDOW_FULLSCREEN);
		SDL_SetWindowFullscreen(Video.Window, SDL_WINDOW_FULLSCREEN_DESKTOP);
		//SDL_SetWindowGrab(Video.Window, SDL_TRUE);
    	{$ELSE}
		{$IFNDEF DISABLE_SDL2_2_0_5}
		if Video.NewSDL then
	        SDL_GetDisplayUsableBounds(SDL_GetWindowDisplayIndex(Video.Window), R)
		else
		{$ENDIF}
			SDL_GetDisplayBounds(SDL_GetWindowDisplayIndex(Video.Window), R);
        SDL_SetWindowSize(Video.Window, R.w, R.h);
		SDL_SetWindowPosition(Video.Window, R.x, R.y);
        {$ENDIF}
	end
	else
	begin
		h := GetMaxScaling;
		w := Console.Bitmap.Width  * h;
		h := Console.Bitmap.Height * h;

		SDL_SetWindowFullscreen(Video.Window, SDL_WINDOW_WINDOWED);
		SDL_SetWindowBordered(Video.Window, SDL_TRUE);
		SDL_SetWindowSize(Video.Window, w, h);
		SDL_SetWindowPosition(Video.Window,
			SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);
		SDL_SetWindowGrab(Video.Window, SDL_FALSE);
	end;

	{$IFNDEF DISABLE_SDL2_2_0_5}
	if Video.NewSDL then
		SDL_SetWindowInputFocus(Video.Window);
	{$ENDIF}

    ClearMessageQueue;
    Locked := False;

GetMouseScale:
	SDL_RenderGetScale(Video.Renderer, @X, @Y);
	w := Max(Trunc(X), 1); h := Max(Trunc(Y), 1);
	w := Min(w, h);
	MouseCursor.Scaling := Types.Point(w, w);
	if WantFullScreen then MouseCursor.InWindow := True;
end;

procedure TWindow.SetTitle(const Title: AnsiString);
begin
	if Initialized then
		SDL_SetWindowTitle(Video.Window, PAnsiChar(Title));
end;

procedure TWindow.OnKeyDown(var Key: Integer; Shift: TShiftState);
var
	InModal: Boolean;
	KeyID: Word;
begin
	if (CurrentScreen = nil) then Exit;

	if (CurrentScreen.KeyDown(Key, Shift)) then
	begin
		Key := 0;
		Exit;
	end;

	InModal := InModalDialog;

	// Direct check for Shift-F8 to ensure it's handled correctly
	if (Key = SDLK_F8) and (ssShift in Shift) and (not InModal) then
	begin
		if (Module.PlayMode <> PLAY_STOPPED) then
		begin
			// Shift-F8: keep current playback position
			CurrentPattern := Module.PlayPos.Pattern;
			PatternEditor.Cursor.Row := Module.PlayPos.Row;
			OrderList.Cursor.Y := Module.PlayPos.Order;
			Module.Stop;
			PlayTimeCounter := 0;
			PatternEditor.ValidateCursor;
			Editor.UpdateInfoLabels;
			if CurrentScreen = Editor then
			begin
				PatternEditor.Paint;
				OrderList.Paint;
			end;
			Key := 0;
			Exit;
		end;
	end;

	KeyID := Shortcuts.Find(GlobalKeys, Key, Shift);
	case GlobalKeyNames(KeyID)	of

		keyNONE:
			Exit;

		keyMainMenu:
			ContextMenu.Show;

		// exit program
		keyProgramQuit:
			Close;

		keyScreenConfig:
			ChangeScreen(TCWEScreen(ConfigScreen));

		keyScreenAbout:
			ChangeScreen(TCWEScreen(SplashScreen));

		keyScreenHelp:
			if not InModal then
				if not Editor.ShowCommandHelp then
					Help.Show(CurrentScreen.ID);

		keyScreenPatternEditor:
			if not InModal then
			begin
				FollowPlayback := False;
				Editor.ActiveControl := PatternEditor;
				ChangeScreen(TCWEScreen(Editor));
			end;

		keyScreenOrderList:
			if not InModal then
			begin
				Editor.ActiveControl := OrderList;
				ChangeScreen(TCWEScreen(Editor));
			end;

		keyScreenSamples:
			if not InModal then
			begin
				SampleScreen.Waveform.Sample := Module.Samples[CurrentSample-1];
				ChangeScreen(TCWEScreen(SampleScreen));
				SampleScreen.UpdateSampleInfo;
			end;

		keyPlaybackSong:
			if not InModal then
			begin
				if Module.PlayMode = PLAY_STOPPED then
				begin
					PlaybackStartPos.Pattern := CurrentPattern;
					PlaybackStartPos.Row := PatternEditor.Cursor.Row;
					PlaybackStartPos.Channel := PatternEditor.Cursor.Channel;
					PlaybackStartPos.Order := OrderList.Cursor.Y;
					Module.Play;
				end;
				ChangeScreen(TCWEScreen(Editor));
				FollowPlayback := True;
				PlayTimeCounter := 0;
			end;

		keyPlaybackPattern:
			if not InModal then
			begin
				PlaybackStartPos.Pattern := CurrentPattern;
				PlaybackStartPos.Row := PatternEditor.Cursor.Row;
				PlaybackStartPos.Channel := PatternEditor.Cursor.Channel;
				PlaybackStartPos.Order := OrderList.Cursor.Y;
				FollowPlayback := False;
				Module.PlayPattern(CurrentPattern);
				PlayTimeCounter := 0;
			end;

		keyPlaybackPlayFrom:
			if not InModal then
			begin
				Key := Integer(SDLK_F7); // dumb hack
				CurrentScreen.KeyDown(Key, Shift);
				PlayTimeCounter := 0;
			end;

		keyPlaybackStop:
			if not InModal then
			begin
				if ssShift in Shift then
				begin
					// Shift-F8: keep current playback position
					if (Module.PlayMode <> PLAY_STOPPED) then
					begin
						// Save current position before stopping
						CurrentPattern := Module.PlayPos.Pattern;
						PatternEditor.Cursor.Row := Module.PlayPos.Row;
						OrderList.Cursor.Y := Module.PlayPos.Order;
						// Remember last played order position for F7 resume
						if Module.PlayMode = PLAY_SONG then
						begin
							PlaybackStartPos.Order := Module.PlayPos.Order;
							PlaybackStartPos.Pattern := Module.PlayPos.Pattern;
							PlaybackStartPos.Row := Module.PlayPos.Row;
						end;
						Module.Stop;
						PlayTimeCounter := 0;
						PatternEditor.ValidateCursor;
						Editor.UpdateInfoLabels;
						if CurrentScreen = Editor then
						begin
							PatternEditor.Paint;
							OrderList.Paint;
						end;
					end
					else
					begin
						Module.Stop;
						PlayTimeCounter := 0;
					end;
				end
				else
				begin
					// F8: restore start position
					if (Module.PlayMode <> PLAY_STOPPED) then
					begin
						Module.Stop;
						PlayTimeCounter := 0;
						CurrentPattern := PlaybackStartPos.Pattern;
						PatternEditor.Cursor.Row := PlaybackStartPos.Row;
						PatternEditor.Cursor.Channel := PlaybackStartPos.Channel;
						OrderList.Cursor.Y := PlaybackStartPos.Order;
						PatternEditor.ValidateCursor;
						Editor.UpdateInfoLabels;
						if CurrentScreen = Editor then
						begin
							PatternEditor.Paint;
							OrderList.Paint;
						end;
					end
					else
					begin
						Module.Stop;
						PlayTimeCounter := 0;
					end;
				end;
			end;

		keyScreenLoad:
			if not InModal then
				FileRequester.Show(False, Options.Dirs.Modules);

		keyScreenSave:
			FileRequester.Show(True, Options.Dirs.Modules);

		keySaveCurrent:
			if not InModal then
				PatternEditor.SaveModule;

		// toggle fullscreen with alt-enter
		keyProgramFullscreen:
			SetFullScreen(not Video.IsFullScreen);

		keyScreenLog:
			ChangeScreen(TCWEScreen(LogScreen));

		keyMetadataNotes:
			if Assigned(Module) and Assigned(Module.Metadata) then
				ChangeScreen(TCWEScreen(NotesScreen))
			else
				ModalDialog.ShowMessage('Notes', 'No module loaded.');

		keyMetadataNext:
			if Assigned(Module) and Assigned(Module.Metadata) then
				Module.Metadata.NavigateNext;

		keyMetadataPrev:
			if Assigned(Module) and Assigned(Module.Metadata) then
				Module.Metadata.NavigatePrevious;

		keyPlaybackPrevPattern:
			if not InModal then
				Editor.SelectPattern(SELECT_PREV);

		keyPlaybackNextPattern:
			if not InModal then
				Editor.SelectPattern(SELECT_NEXT);

		keySongNew:
			if not InModal then
				NewModule(True);

		keyCleanup:
			if not InModal then
				Dialog_Cleanup;

		keySongLength:
			if not InModal then
				Dialog_ModuleInfo;

		keyJumpToTime:
			if not InModal then
				Dialog_JumpToTime;

		keyRenderToSample:
			if not InModal then
				Dialog_Render(True);

		keyToggleChannel1:	Editor.ToggleChannel(0);
		keyToggleChannel2:	Editor.ToggleChannel(1);
		keyToggleChannel3:	Editor.ToggleChannel(2);
		keyToggleChannel4:	Editor.ToggleChannel(3);

		keyMouseCursor:
			begin
				Inc(Options.Display.MousePointer);
				if Options.Display.MousePointer > CURSOR_NONE then
					Options.Display.MousePointer := 0;
				case Options.Display.MousePointer of
					CURSOR_SYSTEM:
						Editor.MessageText('Hardware mouse cursor enabled');
					CURSOR_CUSTOM:
						Editor.MessageText('Software mouse cursor enabled');
					CURSOR_NONE:
						Editor.MessageText('Mouse disabled');
				end;
				ChangeMousePointer;
			end;

	end;

	Key := 0; // fix F10
end;

procedure TWindow.ProcessMouseMovement;
var
	P: TPoint;
	X, Y: Integer;
begin
	if Locked then Exit;

	SDL_PumpEvents;
	SDL_GetMouseState(@X, @Y);

	X := X div MouseCursor.Scaling.X;
	Y := Y div MouseCursor.Scaling.Y;
	MouseCursor.Pos := Types.Point(X, Y);
	P := Types.Point(X div Console.Font.Width, Y div Console.Font.Height);

	if (CurrentScreen <> nil) and
		((X <> MouseCursor.OldPos.X) or (Y <> MouseCursor.OldPos.Y)) then
	begin
		MouseCursor.OldPos := MouseCursor.Pos;
		CurrentScreen.MouseMove(X, Y, P);
	end;
end;

function GetModifierKey(keymod: TSDL_Keymod; var Shift: TShiftState;
	keymodconst: Integer; shiftconst: TShiftStateEnum): Boolean;
begin
	if (keymod and keymodconst) <> 0 then
	begin
		Include(Shift, shiftconst);
		Result := True;
	end
	else
		Result := False;
end;

function GetShiftState: TShiftState;
var
	M: TSDL_Keymod;
begin
	Result := [];
	M := SDL_GetModState;
	GetModifierKey(M, Result, KMOD_SHIFT,	ssShift);	// Shift
	GetModifierKey(M, Result, KMOD_CTRL,	ssCtrl);	// Ctrl
	GetModifierKey(M, Result, KMOD_ALT,		ssAlt);		// Alt
	GetModifierKey(M, Result, KMOD_MODE,	ssAltGr);	// AltGr
	GetModifierKey(M, Result, KMOD_GUI,		ssMeta);	// Windows
	//GetModifierKey(M, Result, KMOD_NUM,	ssNum);		// Num Lock
	GetModifierKey(M, Result, KMOD_CAPS,	ssCaps);	// Caps Lock
end;

function RemoveDiacritics(const S: String): String;
var
	F: Boolean;
	I: SizeInt;
	PS, PD: PChar;
begin
	SetLength(Result, Length(S));
	PS := PChar(S);
	PD := PChar(Result);
	I := 0;
	while PS^ <> #0 do
	begin
		F := PS^ = #195;
		if F then
		case PS[1] of
			#128..#134:			PD^ := 'A';
			#135:				PD^ := 'C';
			#136..#139:			PD^ := 'E';
			#140..#143:			PD^ := 'I';
			#144:				PD^ := 'D';
			#145:				PD^ := 'N';
			#146..#150, #152:	PD^ := 'O';
			#151:				PD^ := 'x';
			#153..#156:			PD^ := 'U';
			#157:				PD^ := 'Y';
			#158:				PD^ := 'P';
			#159:				PD^ := 's';
			#160..#166:			PD^ := 'a';
			#167:				PD^ := 'c';
			#168..#171:			PD^ := 'e';
			#172..#175:			PD^ := 'i';
			#176:				PD^ := 'd';
			#177:				PD^ := 'n';
			#178..#182, #184:	PD^ := 'o';
			#183:				PD^ := '-';
			#185..#188:			PD^ := 'u';
			#190:				PD^ := 'p';
			#189, #191:			PD^ := 'y';
		else
			F := False;
		end;
		if F then
			Inc(PS)
		else
			PD^ := PS^;
		Inc(I); Inc(PD); Inc(PS);
	end;
	SetLength(Result, I);
end;

procedure TWindow.HandleInput;
var
	InputEvent: TSDL_Event;
	X, Y: Integer;
	B: Boolean;
	Btn: TMouseButton;
	Key: TSDL_KeyCode;
	km: TSDL_KeyMod;
	Shift: TShiftState;
	AnsiInput: AnsiString;
	{$IFDEF MIDI}
	KeyBind: TKeyBinding;
	i: Integer;
	{$ENDIF}

	function GetXY: TPoint;
	begin
		Result := Types.Point(
			MouseCursor.Pos.X div Console.Font.Width,
			MouseCursor.Pos.Y div Console.Font.Height);
	end;

begin
	if Locked then Exit;

	X := MouseCursor.Pos.X;
	Y := MouseCursor.Pos.Y;

	while SDL_PollEvent(@InputEvent) <> 0 do
	case {%H-}InputEvent.type_ of

		SDL_USEREVENT:			// messages from playroutine/midi handler
		case InputEvent.user.code of
			MSG_VUMETER:			UpdateVUMeter(GetMessageValue(InputEvent));
			MSG_ROWCHANGE:			UpdatePatternView;
			MSG_ORDERCHANGE:		ModuleOrderChanged;
			MSG_TIMERTICK:			TimerTick;

			{$IFDEF MIDI}
			MSG_MIDI_SELPATTERN:	Editor.SelectPattern(GetMessageValue(InputEvent));
			MSG_MIDI_SELSAMPLE:		Editor.SetSample(GetMessageValue(InputEvent));
			MSG_SHORTCUT:
			begin
				KeyBind := TKeyBinding(InputEvent.user.data1^);
				if Assigned(KeyBind) then
				begin
					i := KeyBind.Shortcut.Key;
					OnKeyDown(i, KeyBind.Shortcut.Shift);
				end;
			end;
			{$ENDIF}
		end;

		SDL_KEYDOWN:
		begin
			{$IFDEF LIMIT_KEYBOARD_EVENTS}
			if (InputEvent.key.timestamp - PrevKeyTimeStamp) > 4 then
			{$ENDIF}
			begin
				Key := InputEvent.key.keysym.sym;
				case Key of
					SDLK_UNKNOWN:
					{SDLK_LSHIFT, SDLK_RSHIFT,
					SDLK_LCTRL,  SDLK_RCTRL,
					SDLK_LALT,   SDLK_RALT,
					SDLK_LGUI,   SDLK_RGUI:}
					;
				else
					Shift := [];
					if InputEvent.key.keysym._mod <> KMOD_NONE then
					begin
						km := {SDL_GetModState;} InputEvent.key.keysym._mod;
						GetModifierKey(km, Shift, KMOD_SHIFT,	ssShift);		// Shift
						GetModifierKey(km, Shift, KMOD_CTRL,	ssCtrl);		// Ctrl
						GetModifierKey(km, Shift, KMOD_ALT,		ssAlt);			// Alt
						GetModifierKey(km, Shift, KMOD_GUI,		ssMeta);		// Windows
						GetModifierKey(km, Shift, Integer(KMOD_CAPS), ssCaps);	// Caps Lock
						GetModifierKey(km, Shift, Integer(KMOD_MODE), ssAltGr);	// AltGr
					end;
(*
					{$IFDEF DEBUG}
					sk := '';
					if ssShift in Shift then sk := sk + 'Shift ';
					if ssCtrl in Shift then sk := sk + 'Ctrl ';
					if ssAlt in Shift then sk := sk + 'Alt ';
					if ssAltGr in Shift then sk := sk + 'AltGr ';
					if ssMeta in Shift then sk := sk + 'Meta ';
					if ssCaps in Shift then sk := sk + 'Caps ';
					writeln('Key=', Key, '   Shift=', sk);
					{$ENDIF}
*)
					OnKeyDown(Integer(Key), Shift);
				end;
			end;
			{$IFDEF LIMIT_KEYBOARD_EVENTS}
			PrevKeyTimeStamp := InputEvent.key.timestamp;
			{$ENDIF}
		end;

        SDL_TEXTINPUT:
			if InputEvent.text.text[0] <> #0 then
			begin
				AnsiInput := RemoveDiacritics(InputEvent.text.text);
				if Length(AnsiInput) > 0 then
					CurrentScreen.TextInput(AnsiInput[1]);
			end;

		SDL_MOUSEBUTTONDOWN,
		SDL_MOUSEBUTTONUP:
			if CurrentScreen <> nil then
			begin
				case InputEvent.button.button of
					SDL_BUTTON_LEFT:	Btn := mbLeft;
					SDL_BUTTON_MIDDLE:	Btn := mbMiddle;
					SDL_BUTTON_RIGHT:	Btn := mbRight;
				else
					Btn := mbLeft;
				end;

				if InputEvent.type_ = SDL_MOUSEBUTTONDOWN then
				begin
					if PtInRect(CurrentScreen.Rect, GetXY) then
					begin
						SDL_SetWindowGrab(Video.Window, SDL_TRUE);
						B := CurrentScreen.MouseDown(Btn, X, Y, GetXY);
						// right button for context menu if the button wasn't otherwise handled
						if (Btn = mbRight) and (not B) and (ModalDialog.Dialog = nil) then
							ContextMenu.Show;
					end
					else
					// close context menu by clicking outside it
					if (ModalDialog.Dialog <> nil) and (ModalDialog.ID = DIALOG_CONTEXTMENU) and
						(CurrentScreen = ModalDialog.Dialog) then
							ModalDialog.Close;
				end
				else
				if InputEvent.type_ = SDL_MOUSEBUTTONUP then
				begin
					SDL_SetWindowGrab(Video.Window, SDL_FALSE);
					CurrentScreen.MouseUp(Btn, X, Y, GetXY);
				end;
			end;

		{SDL_MOUSEMOTION:
			//if (not DisableInput) then
			if (CurrentScreen <> nil) and (Initialized) then
				CurrentScreen.MouseMove(X, Y, GetXY);}

		SDL_MOUSEWHEEL:
			if CurrentScreen <> nil then
				CurrentScreen.MouseWheel([], InputEvent.wheel.y, GetXY);

		SDL_WINDOWEVENT:
			case InputEvent.window.event of
		        SDL_WINDOWEVENT_ENTER:		MouseCursor.InWindow := True;
		        SDL_WINDOWEVENT_LEAVE:		MouseCursor.InWindow := False;
				SDL_WINDOWEVENT_SHOWN,
				SDL_WINDOWEVENT_RESTORED:	Window.Visible := True;
				SDL_WINDOWEVENT_HIDDEN,
				SDL_WINDOWEVENT_MINIMIZED:	Window.Visible := False;
			end;

		SDL_DROPFILE:
			DoLoadModule(InputEvent.drop._file);

		SDL_QUITEV:
			Close;

	end;
end;

procedure TWindow.SyncTo60Hz; 				// from PT clone
var
	delayMs, perfFreq, timeNow_64bit: UInt64;
begin
	if (Window.Visible) and (Video.HaveVSync or Locked) then Exit;

	perfFreq := SDL_GetPerformanceFrequency; // should be safe for double
	if perfFreq = 0 then Exit; // panic!

	timeNow_64bit := SDL_GetPerformanceCounter;
	if Video.NextFrameTime > timeNow_64bit then
	begin
		delayMs := Trunc((Video.NextFrameTime - timeNow_64bit) * (1000.0 / perfFreq) + 0.5);
		SDL_Delay(delayMs);
	end;
	Inc(Video.NextFrameTime, Trunc(perfFreq / 60 + 0.5));
end;

function TimerTickCallback(interval: Uint32; param: Pointer): UInt32; cdecl;
var
	event: TSDL_Event;
begin
	if (Initialized) and (not Locked) then
	begin
		event.type_ := SDL_USEREVENT;
		event.user.code := MSG_TIMERTICK;
	    SDL_PushEvent(@event);
	end;
	Result := interval;
end;

procedure TWindow.TimerTick;
begin
	if Locked then Exit;

	if MessageTextTimer >= 0 then
	begin
		Dec(MessageTextTimer);
		if MessageTextTimer < 0 then
			Editor.MessageText('');
	end;

	Dec(PlayTimeCounter);
	if PlayTimeCounter <= 0 then
	begin
		PlayTimeCounter := 25;
		if CurrentScreen = Editor then
			Editor.UpdateTimeDisplay;
	end;

	if TimerCallback.Enabled then
	begin
		Inc(TimerCallback.Counter);
		if TimerCallback.Counter >= TimerCallback.Interval then
		begin
			TimerCallback.Counter := 0;
			if Assigned(TimerCallback.Callback) then
				TimerCallback.Callback(TimerCallback.Control, TimerCallback.ID);
		end;
	end;
end;

procedure TWindow.InitConfiguration;
var
	Cfg: TConfigurationManager;
	Sect: AnsiString;
	i: Integer;
	AudioDeviceList: TStringList;
	{$IFDEF BASS}device: BASS_DEVICEINFO;{$ENDIF}
begin
	AudioDeviceList := TStringList.Create;

	// Init list of audio devices
	//
	{$IFDEF BASS}
	BASS_SetConfig(BASS_CONFIG_DEV_DEFAULT, 1);

	for i := 1 to 99 do
		if BASS_GetDeviceInfo(i, device) then
			AudioDeviceList.Add(device.name)
		else
			Break;
	{$ELSE}
	SDL_Init(SDL_INIT_AUDIO);

	AudioDeviceList.Add('Default');
	for i := 0 to SDL_GetNumAudioDevices(0)-1 do
		AudioDeviceList.Add(SDL_GetAudioDeviceName(i, 0));
	{$ENDIF}

	// Init configuration
	//
	ConfigManager := TConfigurationManager.Create;
	Cfg := ConfigManager;
	Cfg.Filename := ConfigPath + FILENAME_CONFIG;

	with Options do
	begin
		Sect := 'Editor';
		Cfg.AddBoolean(Sect, 'AltHomeEndBehavior', @Tracker.AltHomeEndBehavior, False)
		.SetInfo('Home and End keys behavior', 0, 1, ['Impulse Tracker', 'Propulse']);
		Cfg.AddBoolean(Sect, 'ShowEmptyParamZeroes', @Tracker.ShowEmptyParamZeroes, True)
		.SetInfo('Show empty command parameters as', 0, 1, ['...', '.00']);
		Cfg.AddBoolean(Sect, 'CenterPlayback', @Tracker.CenterPlayback, True)
		.SetInfo('Center currently playing row', 0, 1, ['No', 'Yes']);
		Cfg.AddBoolean(Sect, 'NoteB3AsInvalid', @Tracker.NoteB3Warning, False)
		.SetInfo('Consider note B-3 as invalid', 0, 1, ['No', 'Yes']);
		Cfg.AddBoolean(Sect, 'RestoreSamples', @Tracker.RestoreSamples, False)
		.SetInfo('Restore samples when playback stopped', 0, 1, ['No', 'Yes']);
		Cfg.AddBoolean(Sect, 'ResetTempo', @Tracker.ResetTempo, True)
		.SetInfo('Reset tempo when playback stopped', 0, 1, ['No', 'Yes']);
		Cfg.AddBoolean(Sect, 'HexRows', @Tracker.HexRows, True)
		.SetInfo('Show row numbers in hex', 0, 1, ['No', 'Yes']);

		Sect := 'Program';
		Cfg.AddBoolean(Sect, 'HighPriority', @HighPriority, True)
		{$IFDEF WINDOWS}
		.SetInfo('Task priority', 0, 1, ['Normal', 'High'])
		{$ENDIF};
		Cfg.AddByte(Sect, 'AutosaveInterval', @Program_.AutosaveInterval, 2)
		.SetInfo('Autosave interval', 0, Ord(High(TAutosaveInterval)), GetAutosaveIntervalLabels);

		Sect := 'Display';
		Cfg.AddByte(Sect, 'Scaling', @Display.Scaling, 2)
		.SetInfo('Maximum scale factor', 1, 9, [], PixelScalingChanged);
		Cfg.AddByte(Sect, 'Vsync', @Display.VSyncMode, VSYNC_AUTO)
		.SetInfo('Vertical sync', VSYNC_AUTO, VSYNC_OFF, ['Auto', 'Force on', 'Off']);
		Cfg.AddString(Sect, 'Font', @Display.Font, FILENAME_DEFAULTFONT)
		.SetInfoFromDir('Font', DataPath + 'font/', '*.pcx', ApplyFont);
		{Cfg.AddString(Sect, 'Palette', @Display.Palette, 'Propulse').
		SetInfoFromDir('Palette', ConfigPath + 'palette/', '*.ini', ApplyPalette);}
		Cfg.AddByte(Sect, 'Mouse', @Display.MousePointer, CURSOR_CUSTOM)
		.SetInfo('Mouse pointer', CURSOR_SYSTEM, CURSOR_NONE,
		['System', 'Software', 'Hidden'], ChangeMousePointer);
		Cfg.AddBoolean(Sect, 'ScopePerChannel', @Display.ScopePerChannel, True)
		.SetInfo('Scope displays', 0, 1, ['Master output', 'Channels']);
		Cfg.AddBoolean(Sect, 'SampleAsBytes', @Display.SampleAsBytes, True)
		.SetInfo('Show sample sizes/offsets in', 0, 1, ['Words', 'Bytes']);
		Cfg.AddBoolean(Sect, 'SampleAsDecimal', @Display.SizesAsDecimal, True)
		.SetInfo('Show sizes/offsets as', 0, 1, ['Hexadecimal', 'Decimal']);
		Cfg.AddBoolean(Sect, 'RawFileSizes', @Dirs.RawFileSizes, False)
		.SetInfo('Show filesizes as', 0, 1, ['Kilobytes', 'Bytes']);
		{ Cfg.AddBoolean(Sect, 'ShowVolumeColumn',
		  @Display.ShowVolumeColumn, True);
		  Cfg.SetInfo('Show volume column', 0, 1, ['Yes' ,'No']); }
		Cfg.AddBoolean(Sect, 'ShowSplashScreen', @Display.ShowSplashScreen, True)
		.SetInfo('Splash screen', 0, 1, ['Disabled', 'Enabled']);

		Sect := 'Audio';
		{$IFDEF BASS}
		Cfg.AddString(Sect, 'Device', @Audio.Device, 'Default')
		{$ELSE}
		Cfg.AddString(Sect, 'Device.SDL2', @Audio.Device, 'Default')
		{$ENDIF}
		.SetInfo('Audio device', 0, AudioDeviceList.Count-1, AudioDeviceList);

		Cfg.AddByte(Sect, 'Frequency', @Audio.Frequency, 1)
		.SetInfo('Sampling rate (Hz)', 0, 2, ['32000', '44100', '48000'], nil);

		{$IFDEF BASS}
		Cfg.AddInteger(Sect, 'Buffer', @Audio.Buffer, 0)
		.SetInfo('Audio buffer (ms)', 0, 500, ['Automatic']);
		{$ELSE}
		Cfg.Addbyte(Sect, 'Buffer.SDL2', @Audio.BufferSamples, 2)
		.SetInfo('Audio buffer (samples)', 0, 5,
		['256', '512', '1024', '2048', '4096', '8192']);
		{$ENDIF}

		Cfg.AddFloat(Sect, 'Amplification', @Audio.Amplification, 4.00)
		.SetInfo('Amplification', 0, 10, [], ApplyAudioSettings, '', -1);
		Cfg.AddByte(Sect, 'StereoSeparation', @Audio.StereoSeparation, 15)
		.SetInfo('Stereo separation', 0, 100, ['Mono', 'Full stereo'], ApplyAudioSettings, '', 5);
		Cfg.AddBoolean(Sect, 'FilterLowPass',  @Audio.FilterLowPass, False)
		.SetInfo('Lowpass filter',  0, 1, ['Disabled', 'Enabled'], ApplyAudioSettings);
		Cfg.AddBoolean(Sect, 'FilterHighPass', @Audio.FilterHighPass, False)
		.SetInfo('Highpass filter', 0, 1, ['Disabled', 'Enabled'], ApplyAudioSettings);
		Cfg.AddBoolean(Sect, 'FilterLed',      @Audio.FilterLed, True)
		.SetInfo('LED filter',      0, 1, ['Disabled', 'Enabled'], ApplyAudioSettings);
		Cfg.AddBoolean(Sect, 'CIAMode', @Audio.CIAmode, False)
		.SetInfo('Timing mode', 0, 1, ['CIA', 'VBlank'], ApplyAudioSettings);
		Cfg.AddBoolean(Sect, 'EditorInvertLoop', @Audio.EditorInvertLoop, True)
		.SetInfo('Play EFx (Invert Loop) like', 0, 1, ['PT playroutine', 'PT editor']);
		Cfg.AddBoolean(Sect, 'EnableKarplusStrong', @Audio.EnableKarplusStrong, False)
		.SetInfo('Enable E8x (Karplus-Strong) effect', 0, 1, ['No', 'Yes']);

		{$IFDEF MIDI}
		Sect := 'MIDI';
		Cfg.AddBoolean(Sect, 'Enabled', @Midi.Enabled, False)
		.SetInfo('Enable MIDI input', 0, 1, ['No', 'Yes'], ApplyMIDISettings);
			{$IFDEF MIDI_DISPLAY}
			Cfg.AddBoolean(Sect, 'Display.Enabled', @Midi.UseDisplay, False)
			.SetInfo('Enable LED matrix display', 0, 1, ['No', 'Yes'], ApplyMIDISettings);
			Cfg.AddByte(Sect, 'Display.Effect', @Midi.DisplayEffect, 0)
			.SetInfo('Display effect', MIDI_FX_SCROLLTEXT, MIDI_FX_VU_HORIZONTAL,
			['Scrolltext', 'VU (vertical)', 'VU (horizontal)'], ApplyMIDISettings);
			{$ENDIF}
		{$ENDIF}

		Sect := 'Directory';
		Cfg.AddString	(Sect, 'Modules', 		@Dirs.Modules, 			AppPath);
		Cfg.AddString	(Sect, 'Samples', 		@Dirs.Samples, 			AppPath);
		Cfg.AddString	(Sect, 'Autosave', 		@Dirs.Autosave, 			AppPath);
		Cfg.AddByte		(Sect, 'SortMode',		@Dirs.FileSortMode,   	FILESORT_NAME).Max := FILESORT_EXT;
		Cfg.AddByte		(Sect, 'SortModeS',		@Dirs.SampleSortMode, 	FILESORT_NAME).Max := FILESORT_EXT;

		Sect := 'Resampling';
		Cfg.AddBoolean(Sect, 'Resample.Automatic', @Import.Resampling.Enable, True)
		.SetInfo('Automatic resampling on import', 0, 1, ['Disabled', 'Enabled']);
		Cfg.AddCardinal(Sect, 'Resample.From', @Import.Resampling.ResampleFrom, 29556)
		.SetInfo('Resample if sample rate exceeds', 0, 44100, []);
		Cfg.AddByte(Sect, 'Resample.To', @Import.Resampling.ResampleTo, 24)
		.SetInfo('Resample to note', 0, 35, NoteNames);
		Cfg.AddByte(Sect, 'Resample.Quality', @Import.Resampling.Quality, 4)
		.SetInfo('Resampling quality', 0, 4,
		['Quick cubic', 'Low', 'Medium', 'High', 'Very high']);
		Cfg.AddBoolean(Sect, 'Resample.Normalize', @Import.Resampling.Normalize, True)
		.SetInfo('Normalize audio levels', 0, 1, ['No', 'Yes']);
		Cfg.AddBoolean(Sect, 'Resample.HighBoost', @Import.Resampling.HighBoost, True)
		.SetInfo('Boost highs', 0, 1, ['No', 'Yes']);
	end;

	AudioDeviceList.Free;

	LogIfDebug('Loading configuration...');

	Cfg.Load;
end;

constructor TWindow.Create;
var
	Dir: String;
	i: Integer;
	Warnings: Boolean = False;
begin
	Initialized := False;
	QuitFlag := False;
	Locked := True;

	// Init application directories
	// Do this first before any other initialization that might access files
	try
		{$IFDEF LAZARUS}
		AppPath := IncludeTrailingPathDelimiter(ProgramDirectory);
		{$ELSE}
		// Expand to absolute path to handle relative paths like ./Propulse-macos-arm64
		// This ensures we get the correct path regardless of current working directory
		AppPath := ExtractFilePath(ExpandFileName(ParamStr(0)));
		if AppPath = '' then
		begin
			WriteLn(StdErr, '');
			WriteLn(StdErr, 'ERROR: Could not determine executable path.');
			WriteLn(StdErr, '');
			Halt(1);
		end;
		AppPath := IncludeTrailingPathDelimiter(AppPath);
		{$ENDIF}
		
		// Require data and docs directories (or symlinks) under AppPath
		DataPath := AppPath + 'data/';
		if not DirectoryExists(DataPath) then
	begin
		WriteLn(StdErr, '');
		WriteLn(StdErr, 'ERROR: Required directory not found: ', DataPath);
		WriteLn(StdErr, '');
		WriteLn(StdErr, 'The "data" directory (or symbolic link) must exist in the same');
		WriteLn(StdErr, 'directory as the executable.');
		WriteLn(StdErr, '');
		WriteLn(StdErr, 'Executable location: ', AppPath);
		WriteLn(StdErr, 'Expected data path:   ', DataPath);
		WriteLn(StdErr, '');
		Halt(1);
	end;
	
	if not DirectoryExists(AppPath + 'docs/') then
	begin
		WriteLn(StdErr, '');
		WriteLn(StdErr, 'ERROR: Required directory not found: ', AppPath + 'docs/');
		WriteLn(StdErr, '');
		WriteLn(StdErr, 'The "docs" directory (or symbolic link) must exist in the same');
		WriteLn(StdErr, 'directory as the executable.');
		WriteLn(StdErr, '');
		WriteLn(StdErr, 'Executable location: ', AppPath);
		WriteLn(StdErr, 'Expected docs path:  ', AppPath + 'docs/');
		WriteLn(StdErr, '');
		Halt(1);
	end;
	
	DataPath := IncludeTrailingPathDelimiter(DataPath);
	except
		on E: Exception do
		begin
			WriteLn(StdErr, '');
			WriteLn(StdErr, 'ERROR: Failed to initialize application directories.');
			WriteLn(StdErr, 'Exception: ', E.ClassName);
			WriteLn(StdErr, 'Message: ', E.Message);
			WriteLn(StdErr, '');
			Halt(1);
		end;
	end;
	
	ConfigPath := GetAppConfigDir(False);
	if ConfigPath = '' then ConfigPath := DataPath;
	ConfigPath := IncludeTrailingPathDelimiter(ConfigPath);
	ForceDirectories(ConfigPath);
	DefaultFormatSettings.DecimalSeparator := '.';

	// Setup logging
	//
	LogIfDebug('============================================================');
	LogIfDebug('Propulse Tracker ' + ProTracker.Util.VERSION + ' starting...');

	// Init config
	//
	InitConfiguration;

	if Options.Dirs.Modules = '' then
		Options.Dirs.Modules := AppPath;
	if Options.Dirs.Samples = '' then
		Options.Dirs.Samples := Options.Dirs.Modules;
	if Options.Dirs.Autosave = '' then
		Options.Dirs.Autosave := Options.Dirs.Modules;


	// Init keyboard commands now so we can log any possible errors with
	// the initialization of subsequent screens
	//
	with Shortcuts do
	begin
		GlobalKeys := SetContext('Global');

		Bind(keyMainMenu,				'Program.Menu',				'Escape');
		Bind(keyProgramQuit, 			'Program.Quit', 			'Ctrl+Q');
		Bind(keyProgramFullscreen, 		'Program.Fullscreen', 		'Alt+Return');
		Bind(keyScreenHelp, 			'Screen.Help', 				'F1');
		Bind(keyScreenPatternEditor, 	'Screen.PatternEditor', 	'F2');
		Bind(keyScreenSamples, 			'Screen.Samples', 			'F3');
		Bind(keyScreenLoad, 			'Screen.Load', 				['F9', 'Ctrl+L', 'Ctrl+O']);
		Bind(keyScreenSave, 			'Screen.Save', 				['F10', 'Ctrl+W']);
		Bind(keyCleanup, 				'Song.Cleanup',				'Ctrl+Shift+C');
		Bind(keyScreenOrderList, 		'Screen.OrderList', 		'F11');
		Bind(keyScreenLog, 				'Screen.Log', 				['F4', 'Ctrl+F11']);
		Bind(keyMetadataNotes,			'Metadata.Notes',			['Shift+F4']);
		Bind(keyMetadataNext,			'Metadata.Next',			['Ctrl+Shift+N']);
		Bind(keyMetadataPrev,			'Metadata.Previous',		['Ctrl+Shift+P']);
		Bind(keyScreenAbout, 			'Screen.About', 			'Ctrl+F1');
		Bind(keyScreenConfig, 			'Screen.Config', 			'F12');
		Bind(keyPlaybackSong, 			'Playback.Song', 			'F5');
		Bind(keyPlaybackPattern, 		'Playback.Pattern', 		'F6');
		Bind(keyPlaybackPlayFrom, 		'Playback.PlayFrom', 		'F7');
		Bind(keyPlaybackStop, 			'Playback.Stop', 			['F8', 'Shift+F8']);
		Bind(keyPlaybackPrevPattern, 	'Playback.PrevPattern', 	'Ctrl+Left');
		Bind(keyPlaybackNextPattern, 	'Playback.NextPattern', 	'Ctrl+Right');
		Bind(keySongLength, 			'Song.Length', 				'Ctrl+P');
		Bind(keyJumpToTime, 			'Song.JumpToTime', 			'Ctrl+Shift+P');
		Bind(keySongNew, 				'Song.New', 				'Ctrl+N');
		Bind(keyRenderToSample, 		'Song.RenderToSample',		'Shift+F10');
		Bind(keySaveCurrent, 			'Song.SaveCurrent', 		'Ctrl+S');
		Bind(keyMouseCursor, 			'Program.MouseCursor', 		'Ctrl+M');
		Bind(keyToggleChannel1, 		'Playback.ToggleChannel.1',	'Ctrl+1');
		Bind(keyToggleChannel2, 		'Playback.ToggleChannel.2',	'Ctrl+2');
		Bind(keyToggleChannel3, 		'Playback.ToggleChannel.3',	'Ctrl+3');
		Bind(keyToggleChannel4, 		'Playback.ToggleChannel.4',	'Ctrl+4');

		FileOpKeys := SetContext('FileOperations');

		Bind(filekeyRename,				'File.Rename',				'Shift+F2');
		Bind(filekeyCopy,				'File.Copy',				'Shift+F5');
		Bind(filekeyMove,				'File.Move',				'Shift+F6');
		Bind(filekeyDelete,				'File.Delete',				['Shift+F8', 'Delete']);
		Bind(filekeyCreate,				'File.CreateDir',			'Shift+F7');
		Bind(filekeyModMerge,			'File.MergeModule',			'Shift+Return');
	end;

	// Load any user-defined shortcuts
	Shortcuts.Load(GetDataFile(FILENAME_KEYBOARD));


	// Create fake text mode console and init SDL
	//
	LogIfDebug('Setting up video...');

//	LogIfDebug('SDL loaded from ' + SDL.FileName);

{	if not SDL.Valid then
	begin
		LogFatal('Could not initialize SDL2!');
		QuitFlag := True;
		Exit;
	end;}

	if not SetupVideo then
	begin
		LogFatal('Could not initialize video!');
		QuitFlag := True;
		Exit;
	end;

	SDL_LogSetOutputFunction(SDLLogFunc, nil);

	// Create screens
	//
	Screens := TObjectList<TCWEScreen>.Create(True);

	// Init config screen first to load user palettes
	//
	ConfigScreen := TConfigScreen.Create(Console, 'Propulse Configuration', 'Config');
	Screens.Add(ConfigScreen);

	// Set up logging
	//
	LogScreen := TLogScreen.Create(Console, 'Messages', 'Log');
	Screens.Add(LogScreen);

//	Progress := TProgress.Create;

	// Log startup messages
	//
	Log('');
	Log(TEXT_HEAD + 'Propulse Tracker v' + ProTracker.Util.VERSION + ' (built on ' +
		Build.CompileDate + ' ' + Build.CompileTime + ')');
	Log('');
	Log(TEXT_LIGHT + '(C) 2016-2019 hukka (Joel Toivonen)');
	Log(TEXT_LIGHT + 'fork and knife by vent + tempest (2025)');
	Log(TEXT_LIGHT + URL);
	Log(TEXT_LIGHT + 'Contains code based on work by 8bitbubsy (Olav Sorensen)');
	Log('');

	if not Video.NewSDL then
	begin
		Log(TEXT_WARNING + 'Using an older version of SDL. (< 2.0.5)');
		Warnings := True;
		Log('');
	end;

	if Video.SyncRate = 0 then
		Dir := 'unknown'
	else
		Dir := IntToStr(Video.SyncRate);
	Dir := Format('Video: SDL %s, %s renderer at %s Hz',
		[Video.LibraryVersion, {ExtractFilename(SDL.FileName),} Video.RendererName, Dir]);
	if Video.HaveVSync then	Dir := Dir + ' VSync';
	Log(TEXT_INIT + Dir);

	case Options.Audio.Frequency of
		0: i := 32000;
		1: i := 44100;
		2: i := 48000;
	else
		i := 44100;
	end;

	LogIfDebug('Initializing audio...');

	if not AudioInit(i) then
	begin
	    LogFatal('Could not initialize audio; quitting!');
		QuitFlag := True;
		Exit;
	end;

	Options.Features.SOXR := {$IFDEF SOXR} (soxr_version <> ''); {$ELSE} False; {$ENDIF}

	if not Options.Features.SOXR then
	begin
	    Log(TEXT_WARNING +
		{$IFNDEF SOXR}
		'SOXR support not compiled in! ' +
		{$ELSE}
	    'SOXR library not found - ' +
		{$ENDIF}
		'Resampling features disabled.');
		Warnings := True;
	end
	else
		{$IFDEF SOXR}
		Log(TEXT_INIT + 'Other: Using ' + soxr_version + ' for resampling')
		{$ENDIF};

	Log('');

	{$IFDEF MIDI}
	if Options.Midi.Enabled then
	begin
		LogIfDebug('Initializing MIDI...');
		MIDI := TMIDIHandler.Create;
		Log('MIDI:  %d controllers enabled.', [MIDI.Controllers.Count]);
	end
	else
		MIDI := nil;
	{$ENDIF}

	LogIfDebug('Initializing GUI...');
	InitCWE;

	// Create the rest of the screens
	//
	Editor := TEditorScreen.Create(Console,	'Pattern Editor', 'Editor');
	Screens.Add(Editor);

	FileRequester := TModFileScreen.Create(Console,
		'File Requester', 'File Requester');
	Screens.Add(FileRequester);
	FileScreen := FileRequester;

	SampleRequester := TSampleFileScreen.Create(Console,
		'File Requester', 'Sample File Requester');
	Screens.Add(SampleRequester);

	SampleScreen := TSampleScreen.Create(Console, 'Sample List', 'Samples');
	Screens.Add(SampleScreen);

	Help := THelpScreen.Create(Console, 'Help Viewer', 'Help');
	Screens.Add(Help);

	SplashScreen := TSplashScreen.Create(Console, '', 'Splash');
	Screens.Add(SplashScreen);

	NotesScreen := TNotesScreen.Create(Console, 'Notes', 'Notes');
	Screens.Add(NotesScreen);

	// Init context menu
	ContextMenu := TCWEMainMenu.Create;

	Log('');

	ApplyPointer;

	ConfigScreen.Init(ConfigManager);

	// Initialize recovery system
	AutoSaveCounter := 0;

	// Check for recovery file before loading new module
	// If recovery file exists and user chooses to restore, DoLoadModule will be called from dialog callback
	// Otherwise, load empty module
	try
		if not CheckRecoveryFile then
			DoLoadModule('');
	except
		on E: Exception do
		begin
			// If checking recovery file fails (e.g., corrupted file), just load empty module
			LogIfDebug('Error checking recovery file: ' + E.Message);
			try
				DoLoadModule('');
			except
				// If even loading empty module fails, just continue
			end;
		end;
	end;

	{$IFDEF LIMIT_KEYBOARD_EVENTS}
	PrevKeyTimeStamp := 0;
	{$ENDIF}
	MessageTextTimer := -1;
	Initialized := True;
	if Assigned(Module) then
		Module.SetModified(False);

	{$IFDEF WINDOWS}
{!!!
	if Options.HighPriority then
		SetPriorityClass(GetCurrentProcess, ABOVE_NORMAL_PRIORITY_CLASS);
}
	{$ENDIF}

	SetFullScreen(Video.IsFullScreen, True);

	{$IFDEF MIDI}
	if MIDI <> nil then MIDI.InitShortcuts;
	{$ENDIF}

	SDL_AddTimer(TimerInterval, TimerTickCallback, nil);

	LogIfDebug('OK.');
	Log(TEXT_SUCCESS + 'Program started at ' + FormatDateTime('YYYY-mm-dd hh:nn.', Now));
	Log('-');

    if Warnings then
		ChangeScreen(TCWEScreen(LogScreen))
	else
	if Options.Display.ShowSplashScreen then
		ChangeScreen(TCWEScreen(SplashScreen))
	else
	begin
		// Ensure Module is initialized before changing to Editor screen
		if not Assigned(Module) then
			DoLoadModule('');
		ChangeScreen(TCWEScreen(Editor));
	end;

	Console.Paint;

	MouseCursor.InWindow := True;
end;

destructor TWindow.Destroy;
begin
	LogIfDebug('Closing down...');

	if Initialized then
	begin
		Initialized := False;

		// Save configuration
		if Shortcuts <> nil then
			Shortcuts.Save(ConfigPath + FILENAME_KEYBOARD);
		if ConfigScreen <> nil then
			ConfigScreen.SavePalette;

		if ConfigManager <> nil then
		begin
			ConfigManager.Save;
			ConfigManager.Free;
		end;

		// Clean up recovery file on exit
		CleanupRecoveryFile;

		ContextMenu.Free;
		Console.Free;
		Screens.Free;
		MouseCursor.Free;

		Module.Free;
		AudioClose;

		{$IFDEF MIDI}if MIDI <> nil then MIDI.Free;{$ENDIF}

		if Video.Renderer <> nil then
			SDL_DestroyRenderer(Video.Renderer);
		if Video.Texture <> nil then
			SDL_DestroyTexture(Video.Texture);
		if Video.Window <> nil then
			SDL_DestroyWindow(Video.Window);
		SDL_Quit;
	end;
end;

procedure TWindow.Close;
begin
	if Module.Modified then
	begin
		if ModalDialog.Dialog <> nil then Exit;
		ModalDialog.MessageDialog(ACTION_QUIT,
			'Quit Propulse Tracker',
			'There are unsaved changes. Discard and quit?',
			[btnOK, btnCancel], btnCancel, DialogCallback, 0)
	end
	else
		QuitFlag := True;
end;

procedure TWindow.ProcessFrame;
begin
	HandleInput;
	SyncTo60Hz;
	ProcessMouseMovement;
	
	// Auto-save recovery file periodically
	// Only proceed if autosave is enabled (interval > 0)
	if (Options.Program_.AutosaveInterval > 0) and Module.ShouldAutoSave and Module.Modified then
	begin
		Inc(AutoSaveCounter);
		// Check if autosave interval has been reached
		if IsValidAutosaveInterval(Options.Program_.AutosaveInterval) and
		   (AutoSaveCounter >= GetAutosaveIntervalFrames(Options.Program_.AutosaveInterval)) then
		begin
			AutoSaveRecovery;
			AutoSaveCounter := 0;
		end;
	end
	else
		AutoSaveCounter := 0;
	
	FlipFrame;
end;

// ==========================================================================
// Crash Recovery System
// ==========================================================================

function TWindow.GetRecoveryFilename: String;
var
	BaseFilename, Dir: String;
begin
	Result := '';
	if Module = nil then Exit;
	
	// If module has a filename, use its directory; otherwise use configured autosave directory
	if Module.Info.Filename <> '' then
	begin
		BaseFilename := ExtractFileName(Module.Info.Filename);
		if BaseFilename = '' then
			BaseFilename := 'untitled.mod';
		Dir := ExtractFilePath(Module.Info.Filename);
		if Dir = '' then
		begin
			// If no path in filename, use configured autosave directory
			Dir := Options.Dirs.Autosave;
			if Dir = '' then
				Dir := Options.Dirs.Modules;
			if Dir = '' then
				Dir := AppPath;
		end;
	end
	else
	begin
		// Module has no filename, use configured autosave directory
		BaseFilename := 'untitled.mod';
		Dir := Options.Dirs.Autosave;
		if Dir = '' then
			Dir := Options.Dirs.Modules;
		if Dir = '' then
			Dir := AppPath;
	end;
	
	Dir := IncludeTrailingPathDelimiter(Dir);
	Result := Dir + BaseFilename + '.autosave';
end;

procedure TWindow.AutoSaveRecovery;
var
	RecoveryFilename, OriginalFilename: String;
begin
	if Module = nil then Exit;
	
	// Only autosave if module has been saved at least once (has a filename)
	if Module.Info.Filename = '' then Exit;
	
	RecoveryFilename := GetRecoveryFilename;
	if RecoveryFilename = '' then Exit;
	
	// Only autosave if both ShouldAutoSave and Modified are true
	if not (Module.ShouldAutoSave and Module.Modified) then Exit;
	
	try
		// Save original filename before autosave (SaveToFile modifies Module.Info.Filename)
		OriginalFilename := Module.Info.Filename;
		
		ForceDirectories(ExtractFilePath(RecoveryFilename));
		Module.SaveToFile(RecoveryFilename);
		
		// Restore original filename so it doesn't get changed to the autosave filename
		Module.Info.Filename := OriginalFilename;
		
		// Set ShouldAutoSave to false after autosave
		Module.ShouldAutoSave := False;
		
		// Don't log autosave operations to keep the info log clean
	except
		// Silently fail - don't interrupt user's work
		// Try to restore filename even if save failed
		if Module <> nil then
			Module.Info.Filename := OriginalFilename;
	end;
end;

function TWindow.CheckRecoveryFile: Boolean;
var
	Dir, Mask, RecoveryFilename: String;
	SearchRec: TSearchRec;
	MostRecentFile: String;
	MostRecentTime: TDateTime;
	FileTime: TDateTime;
	FileValid: Boolean;
begin
	Result := False;
	
	// Get autosave directory
	Dir := Options.Dirs.Autosave;
	if Dir = '' then
		Dir := Options.Dirs.Modules;
	if Dir = '' then
		Dir := AppPath;
	Dir := IncludeTrailingPathDelimiter(Dir);
	
	// Search for .autosave files
	Mask := Dir + '*.autosave';
	MostRecentFile := '';
	MostRecentTime := 0;
	
	if SysUtils.FindFirst(Mask, faAnyFile, SearchRec) = 0 then
	begin
		try
			repeat
				if (SearchRec.Attr and faDirectory) = 0 then
				begin
					RecoveryFilename := Dir + SearchRec.Name;
					try
						FileTime := FileDateToDateTime(FileAge(RecoveryFilename));
						
						// Basic validation: file size check only
						// Full validation will happen when user tries to load it
						// This prevents crashes during startup validation
						FileValid := (SearchRec.Size >= 1084) and (SearchRec.Size < 100 * 1024 * 1024);
						
						// Only consider valid files
						if FileValid and ((MostRecentFile = '') or (FileTime > MostRecentTime)) then
						begin
							MostRecentFile := RecoveryFilename;
							MostRecentTime := FileTime;
						end
						else
						if not FileValid then
						begin
							// Delete corrupted autosave file silently
							try
								SysUtils.DeleteFile(RecoveryFilename);
								LogIfDebug('Removed corrupted autosave file: ' + RecoveryFilename);
							except
								// Ignore deletion errors
							end;
						end;
					except
						// Skip files we can't read or validate
					end;
				end;
			until SysUtils.FindNext(SearchRec) <> 0;
		finally
			SysUtils.FindClose(SearchRec);
		end;
	end;
	
	// If we found a valid recovery file, offer to restore it
	if MostRecentFile <> '' then
	begin
		ModalDialog.MessageDialog(ACTION_RESTORERECOVERY,
			'Crash Recovery',
			Format('An autosave file was found from %s.'#13 +
				'Would you like to restore your unsaved work?',
				[FormatDateTime('YYYY-mm-dd hh:nn:ss', MostRecentTime)]),
			[btnYes, btnNo], btnYes, DialogCallback, MostRecentFile);
		Result := True; // Dialog was shown
	end;
end;

procedure TWindow.CleanupRecoveryFile;
var
	RecoveryFilename: String;
begin
	RecoveryFilename := GetRecoveryFilename;
	if (RecoveryFilename <> '') and FileExists(RecoveryFilename) then
	begin
		try
			SysUtils.DeleteFile(RecoveryFilename);
			LogIfDebug('Cleaned up recovery file: ' + RecoveryFilename);
		except
			// Ignore errors
		end;
	end;
end;

function TWindow.OnContextMenu(AddGlobal: Boolean): Boolean;
begin
	with ContextMenu do
	begin
		SetSection(GlobalKeys);

		if AddGlobal then
		begin
			AddSection('Module');
			AddCmd(Ord(keySongNew),					'New module');
			AddCmd(Ord(keyScreenLoad), 				'Load module');
			AddCmd(Ord(keyScreenSave), 				'Save module');
			AddCmd(Ord(keySongLength), 				'Show length/size');
			AddCmd(Ord(keyJumpToTime), 				'Jump to time...');
			AddCmd(Ord(keyCleanup), 				'Cleanup');
			AddCmd(Ord(keyRenderToSample),			'Selection to sample');

			AddSection('Screens');
			if CurrentScreen <> Help then
				AddCmd(Ord(keyScreenHelp), 			'Help');
			if CurrentScreen <> Editor then
				AddCmd(Ord(keyScreenPatternEditor),	'Pattern editor');
			if CurrentScreen <> SampleScreen then
				AddCmd(Ord(keyScreenSamples), 		'Samples');
			if CurrentScreen <> LogScreen then
				AddCmd(Ord(keyScreenLog), 			'Message log');
			if CurrentScreen <> ConfigScreen then
				AddCmd(Ord(keyScreenConfig), 		'Configuration');
		end;

		AddSection('Program');
		AddCmd(Ord(keyProgramFullscreen), 		'Toggle fullscreen');
		AddCmd(Ord(keyScreenAbout), 			'About...');
		AddCmd(Ord(keyProgramQuit), 			'Quit');
	end;
	Result := True;
end;

end.

