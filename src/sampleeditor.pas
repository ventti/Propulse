unit SampleEditor;

interface

uses
	{Types, }Classes, Math, SysUtils,
	CWE.Core,
	Screen.Samples, SampleView;

const
	actSelectNone		= 1;
	actSelectAll		= 2;
	actSelectPreLoop	= 3;
	actSelectPostLoop	= 4;
	actSelectLoop		= 5;

	actShowAll			= 10;
	actShowRange		= 11;
	actZoomIn			= 20;
	actZoomOut			= 21;

	actCopy				= 30;
	actCut				= 31;
	actPaste			= 32;
	actMixPaste			= 33;
	actCrop				= 34;

	actAmplify			= 40;
	actFadeIn			= 41;
	actFadeOut			= 42;
	actCrossfade		= 45;
	actEqualizer		= 50;
	actFilterLo			= 52;
	actFilterHi			= 53;
	actFilterFlt		= 54;
	actFilterBst		= 55;
	actReverse			= 60;
	actInvert			= 61;
	actResample			= 70;
	actUpsample			= 71;
	actDownsample		= 72;
	actGenerate			= 80;

type
	TWavetype = (
		WAVE_SILENCE,
		WAVE_SINE,
		WAVE_SQUARE,
		WAVE_SAW,
		WAVE_TRIANGLE,
		WAVE_NOISE);

	// Undo system types
	TSampleUndoActionType = (
		uaDelete,		// Delete operation
		uaPaste,		// Paste operation
		uaMixPaste,		// Mix paste operation
		uaCrop,			// Crop operation
		uaAmplify,		// Amplify operation
		uaFadeIn,		// Fade in operation
		uaFadeOut,		// Fade out operation
		uaCrossfade,	// Crossfade operation
		uaFilter,		// Filter operation
		uaReverse,		// Reverse operation
		uaInvert,		// Invert operation
		uaResample,		// Resample operation
		uaUpsample,		// Upsample operation
		uaDownsample,	// Downsample operation
		uaGenerate,		// Generate operation
		uaPreLoopCut,	// Pre-loop cut operation
		uaPostLoopCut,	// Post-loop cut operation
		uaClear,		// Clear sample operation
		uaCopy,			// Copy from another sample
		uaSwap,			// Swap samples operation
		uaReplace,		// Replace sample operation
		uaInsertSlot,	// Insert sample slot
		uaDeleteSlot,	// Delete sample slot
		uaSetLoop,		// Set loop points
		uaSetVolume,	// Set volume
		uaSetFinetune,	// Set finetune
		uaSetName,		// Set sample name
		uaDraw			// Draw operation
	);

	TSampleUndoEntry = record
		ActionType: TSampleUndoActionType;
		SampleIndex: Byte;
		BackupFilename: AnsiString;
		Description: AnsiString;
		// Cursor positions for restoring after undo/redo
		SelectionL, SelectionR: Integer;
		ViewportL, ViewportR: Integer;
		// For metadata changes, store old values
		OldName: AnsiString;
		OldFinetune: ShortInt;
		OldVolume: Byte;
		OldLoopStart, OldLoopLength: Cardinal;
		OldTempLoopStart, OldTempLoopLength: Cardinal;
		OldLoopEnabled: Boolean; // For loop toggle
	end;

	TSampleEditor = class
	private
		UndoBuffer: array[0..99] of TSampleUndoEntry;
		UndoIndex: Integer;
		UndoCount: Integer;
		RedoCount: Integer;
		UndoInProgress: Boolean;
		TempDir: AnsiString;
		TempFiles: TStringList;
		PendingDrawUndo: TSampleUndoEntry;
		IsDrawing: Boolean;
		FDrawOccurred: Boolean;

		procedure	ClearRedo;
		function	SaveSampleBackup(SampleIndex: Byte): AnsiString;
		function	RestoreSampleBackup(const Filename: AnsiString; SampleIndex: Byte): Boolean;
		procedure	CleanupTempFiles;
		procedure	InitializeUndoSystem;
	public
		Waveform: 	TSampleView;

		constructor Create;
		destructor  Destroy; override;

		function	CreateUndoEntry(ActionType: TSampleUndoActionType; SampleIndex: Byte; const Description: AnsiString): TSampleUndoEntry;
		procedure	AddUndoEntry(const Entry: TSampleUndoEntry);
		procedure	Undo;
		procedure	Redo;
		function	CanUndo: Boolean;
		function	CanRedo: Boolean;
		property	IsUndoInProgress: Boolean read UndoInProgress;
		property	DrawOccurred: Boolean write FDrawOccurred;

		procedure	StartDrawUndo;
		procedure	EndDrawUndo;

		function	GetSelection(var X1, X2: Integer): Boolean;
		function	HasSelection: Boolean; inline;
		function	HasLoop: Boolean; inline;
		function	HasSample: Boolean;

		procedure 	ProcessCommand(Cmd: Integer);
		procedure 	OnCommand(Sender: TCWEControl);

		function 	MakeRoom(Pos, Len: Integer): Boolean;
		procedure 	Delete;
		procedure 	Cut;
		procedure 	Copy;
		procedure 	Paste;
		procedure 	MixPaste;

		procedure	Crop;

		procedure 	Amplify;
		procedure 	FadeIn;
		procedure 	FadeOut;
		procedure	CrossFade;
		procedure 	Equalizer;
		procedure 	DoFilter(Hz: Word; LP: Boolean; X1, X2: Integer);
		procedure	FilterLo(Hz: Word = 0);
		procedure	FilterHi(Hz: Word = 0);
		procedure	FilterDecreaseTreble;
		procedure	FilterIncreaseTreble;
		procedure 	Reverse;
		procedure 	Invert;
		procedure 	Resample;
		procedure	Upsample;
		procedure	Downsample;
		procedure	Generate;

		procedure 	GenerateAudio(Wavetype: TWavetype;
					numsamples, samplerate: Integer; frequency: Single);
	end;

var
	SampleEdit: TSampleEditor;


implementation

uses
	ShortcutManager,
	CWE.Dialogs,
	CWE.Widgets.Text,
	Dialog.ValueQuery,
	Dialog.GenerateWaveform,
	ProTracker.Util,
	ProTracker.Player,
	ProTracker.Sample,
	FloatSampleEffects,
	FileStreamEx;

// Get OS-specific temp directory
function GetOSTempDir: AnsiString;
{$IFDEF WINDOWS}
var
	TempPath: AnsiString;
begin
	TempPath := GetEnvironmentVariable('TEMP');
	if TempPath = '' then
		TempPath := GetEnvironmentVariable('TMP');
	if TempPath = '' then
		TempPath := 'C:\Windows\Temp';
	Result := IncludeTrailingPathDelimiter(TempPath);
end;
{$ELSE}
var
	TempPath: AnsiString;
begin
	TempPath := GetEnvironmentVariable('TMPDIR');
	if TempPath = '' then
		TempPath := GetEnvironmentVariable('TMP');
	if TempPath = '' then
		TempPath := '/tmp';
	Result := IncludeTrailingPathDelimiter(TempPath);
end;
{$ENDIF}

var
	Clipbrd: array of Byte;

// --------------------------------------------------------------------------
// Utility
// --------------------------------------------------------------------------

function TSampleEditor.HasSample: Boolean;
begin
	Result := (Waveform.Sample <> nil);
	if not Result then
		ModalDialog.ShowMessage('No sample', 'No sample to operate on!')
end;

function TSampleEditor.HasLoop: Boolean;
begin
	Result := (Waveform.Sample <> nil) and (Waveform.Sample.LoopLength > 2);
	if not Result then
	begin
		if HasSample then
			ModalDialog.ShowMessage('Loop required', 'This function requires a loop.');
	end;
end;

function TSampleEditor.HasSelection: Boolean;
begin
	Result := (Waveform.Selection.R > Waveform.Selection.L) and (Waveform.Sample <> nil);
	if not Result then
	begin
		if HasSample then
			ModalDialog.ShowMessage('Selection required', 'Current selection is empty.');
	end;
end;

function TSampleEditor.GetSelection(var X1, X2: Integer): Boolean;
begin
	with Waveform do
	if (Selection.L >= 0) and (Selection.R > Selection.L) then
	begin
		X1 := Selection.L;
		X2 := Min(Selection.R, Sample.ByteLength);
		Result := not Sample.IsEmpty;
	end
	else
	if Sample <> nil then
	begin
		X1 := 0;
		X2 := Sample.ByteLength;
		Result := not Sample.IsEmpty;
	end
	else
	begin
		X1 := -1;
		X2 := -1;
		Result := False;
	end;
end;

// --------------------------------------------------------------------------
// Events
// --------------------------------------------------------------------------

procedure TSampleEditor.OnCommand(Sender: TCWEControl);
var
	Item: TCWEListItem;
begin
	CurrentScreen.MouseInfo.Control := nil;
	with Sender as TCWEList do
		Item := Items[ItemIndex];
	if Item <> nil then
		ProcessCommand(Item.Data);
end;

procedure TSampleEditor.ProcessCommand(Cmd: Integer);
var
	Sam: TSample;
begin
	if (Waveform = nil) or (Cmd = LISTITEM_HEADER) then Exit;

	Sam := Waveform.Sample;
	if Sam = nil then Exit;

	with Waveform do
	case Cmd of


		// -----------------------------------------------
		// Cut

		actCrop:	Crop;

		// -----------------------------------------------
		// Select

		actSelectNone:
			Selection.SetRange(0, 0);

		actSelectAll:
			Selection.SetRange(0, Sam.ByteLength);

		actSelectLoop:
			if HasLoop then
				Selection.SetRange(Sam.LoopStart*2, (Sam.LoopStart + Sam.LoopLength) * 2);

		actSelectPreLoop:
			if HasLoop then
				Selection.SetRange(0, Sam.LoopStart*2);

		actSelectPostLoop:
			if HasLoop then
				Selection.SetRange((Sam.LoopStart + Sam.LoopLength) * 2, Sam.ByteLength);

		// -----------------------------------------------
		// Show

		actShowAll:		SetViewport(0, Sam.ByteLength);
		actShowRange:	if HasSelection then
							SetViewport(Selection.L, Selection.R);
		actZoomIn:		Zoom(True);
		actZoomOut:		Zoom(False);

		// -----------------------------------------------
		// Clipboard

		actCopy:		Copy;
		actCut:			Cut;
		actPaste:		Paste;
		actMixPaste:	MixPaste;

		// -----------------------------------------------
		// Effects

		actAmplify:		Amplify;
		actFadeIn:		FadeIn;
		actFadeOut:		FadeOut;
		actCrossfade:	CrossFade;
		actEqualizer:	Equalizer;
		actFilterLo:	FilterLo(0);
		actFilterHi:	FilterHi(0);
		actFilterFlt:	FilterDecreaseTreble;
		actFilterBst:	FilterIncreaseTreble;
		actReverse:		Reverse;
		actInvert:		Invert;
		actResample:	Resample;
		actUpsample:	Upsample;
		actDownsample:	Downsample;
		actGenerate:	Generate;
	end;

	// Done!
	//
	Waveform.DrawWaveform;
	if CurrentScreen = SampleScreen then
		SampleScreen.UpdateSampleInfo;
	if ModalDialog.Dialog <> nil then
		ModalDialog.Dialog.Paint;
end;

// --------------------------------------------------------------------------
// Clipboard
// --------------------------------------------------------------------------

procedure TSampleEditor.Delete;
var
	X1, X2, L: Integer;
	UndoEntry: TSampleUndoEntry;
begin
	if HasSelection then
	with Waveform do
	begin
		if not UndoInProgress and (Sample <> nil) then
		begin
			UndoEntry := CreateUndoEntry(uaDelete, Sample.Index, 'Delete selection');
			AddUndoEntry(UndoEntry);
		end;
		
		GetSelection(X1, X2);

		L := Sample.ByteLength - X2;
		if L > 0 then
			Move(Sample.Data[X2], Sample.Data[X1], L);

		Sample.Resize(Sample.ByteLength - (X2 - X1));

		// Fix loop points if loop enabled (from PT clone)
		if Sample.LoopLength > 1 then
		begin
			X1 := X1 div 2;
			X2 := X2 div 2;
			if X2 > Sample.LoopStart then
			begin
				if X1 < (Sample.LoopStart + Sample.LoopLength) then
				begin
					// we cut data inside the loop, increase loop length
					L := Sample.LoopLength - ((X2 - X1) and $FFFFFFFE);
					if L < 2 then L := 2;
					Sample.LoopLength := L;
				end;
			end
			else
			begin
				// We cut data before the loop, adjust loop start point
				L := (Sample.LoopStart - (X2 - X1)) and $FFFFFFFE;
				if L < 0 then
				begin
					Sample.LoopStart  := 0;
					Sample.LoopLength := 1;
				end
				else
					Sample.LoopStart := L;
			end;
		end;

		Selection.SetRange(Selection.L, Selection.L, Sample);

		Module.SetModified;
		Sample.Validate;
	end;
end;

procedure TSampleEditor.Cut;
var
	UndoEntry: TSampleUndoEntry;
begin
	if HasSelection then
	begin
		if not UndoInProgress and (Waveform.Sample <> nil) then
		begin
			UndoEntry := CreateUndoEntry(uaDelete, Waveform.Sample.Index, 'Cut selection');
			AddUndoEntry(UndoEntry);
		end;
		Module.Stop;
		Copy;
		Delete;
	end;
end;

procedure TSampleEditor.Copy;
var
	X1, X2: Integer;
begin
	if HasSelection then
	with Waveform do
	begin
		GetSelection(X1, X2);
		SetLength(Clipbrd, X2-X1+1);
		Move(Sample.Data[X1], Clipbrd[0], X2-X1);
	end;
end;

function TSampleEditor.MakeRoom(Pos, Len: Integer): Boolean;
var
	X1, oldLen: Integer;
begin
	if not HasSample then Exit(False);

	if Len mod 2 = 0 then Inc(Len);

	with Waveform do
	begin
		if IsEmptySample(Sample) then
			oldLen := 0
		else
			oldLen := Sample.ByteLength;

		Sample.Resize(oldLen + Len);
		if (oldLen > 0) and (Pos < oldLen) then
			Move(Sample.Data[Pos], Sample.Data[Pos + Len],
				Sample.ByteLength - Pos - Len );

		if Sample.LoopLength > 1 then // loop enabled?
		begin
			X1 := Selection.L div 2;
			Len := Len div 2;
			if X1 > Sample.LoopStart then
			begin
				if X1 < (Sample.LoopStart + Sample.LoopLength) then
				begin
					// we added data inside the loop, increase loop length
					Sample.LoopLength := Sample.LoopLength + Len;
					if (Sample.LoopStart + Sample.LoopLength) > Sample.Length then
					begin
						Sample.LoopStart  := 0;
						Sample.LoopLength := 1;
					end;
				end;
				// we added data after the loop, don't modify loop points
			end
			else
			begin
				// we added data before the loop, adjust loop start point
				Sample.LoopStart := Sample.LoopStart + Len;
				if (Sample.LoopStart + Sample.LoopLength) > Sample.Length then
				begin
					Sample.LoopStart  := 0;
					Sample.LoopLength := 1;
				end;
			end;
		end;
	end;

	Result := ((Pos + Len) < Waveform.Sample.ByteLength);
end;

procedure TSampleEditor.Paste;
var
	L: Integer;
	B: Boolean;
	UndoEntry: TSampleUndoEntry;
begin
	with Waveform do
	begin
		if not HasSample then Exit;

		if not UndoInProgress and (Sample <> nil) then
		begin
			UndoEntry := CreateUndoEntry(uaPaste, Sample.Index, 'Paste');
			AddUndoEntry(UndoEntry);
		end;

		Module.Stop;

		L := Length(Clipbrd);
		B := IsEmptySample(Sample);

		// pasting into an empty sample slot?
		if (B) and (L > 1) then
		begin
			Sample.Resize(L);
			Selection.L := 0;
			Selection.R := Sample.ByteLength;
		end;

		if (Selection.L >= 0) then
		begin
			if L < 1 then
				ModalDialog.ShowMessage('Clipboard empty', 'Nothing to paste.')
			else
			begin
				// was whole sample visible in view?
				if not B then
					B := (Viewport.L = 0) and (Viewport.R >= Sample.ByteLength-1);

				// replace current selection with clipboard contents?
				if Selection.Length > 1 then Delete;

				if MakeRoom(Selection.L, L) then
					Move(Clipbrd[0], Sample.Data[Selection.L], L-1);

				if B then
					Viewport.SetRange(0, Sample.ByteLength, Sample);

				Sample.Validate;
				Module.SetModified;
			end;
		end;
	end;
end;

procedure TSampleEditor.MixPaste;
var
	X, X1, X2, S: Integer;
	UndoEntry: TSampleUndoEntry;
begin
	with Waveform do
	begin
		if not HasSample then Exit;

		if not UndoInProgress and (Sample <> nil) then
		begin
			UndoEntry := CreateUndoEntry(uaMixPaste, Sample.Index, 'Mix paste');
			AddUndoEntry(UndoEntry);
		end;

		if Length(Clipbrd) < 1 then
		begin
			ModalDialog.ShowMessage('Clipboard empty', 'Nothing to paste.');
			Exit;
		end;

		if IsEmptySample(Sample) then
		begin
			Paste;
			Exit;
		end;

		X1 := Max(0, Selection.L);
		X2 := Min(X1 + Length(Clipbrd), Sample.ByteLength) - 1;

		if IsShiftPressed then
		begin
			for X := X1 to X2 do
			begin
				S := Trunc(ShortInt(Sample.Data[X]) + ShortInt(Clipbrd[X-X1]));
				if S < -128 then
					S := -128
				else
				if S > 127 then
					S := 127;
				ShortInt(Sample.Data[X]) := ShortInt(S);
			end;
		end
		else
		begin
			for X := X1 to X2 do
				ShortInt(Sample.Data[X]) := ShortInt(Trunc(
					(ShortInt(Sample.Data[X]) / 2) +
					(ShortInt(Clipbrd[X-X1]) / 2) ));
		end;

		Sample.Validate;
		Module.SetModified;
	end;
end;

procedure TSampleEditor.Crop;
var
	X1, X2: Integer;
	UndoEntry: TSampleUndoEntry;
begin
	if HasSelection then
	with Waveform do
	begin
		if not UndoInProgress and (Sample <> nil) then
		begin
			UndoEntry := CreateUndoEntry(uaCrop, Sample.Index, 'Crop');
			AddUndoEntry(UndoEntry);
		end;
		
		GetSelection(X1, X2);
		Module.Stop;

		if X1 > 0 then
		begin
			Selection.SetRange(0, X1, Sample);
			Delete;
		end;

		if X2 < Sample.ByteLength then
		begin
			Selection.SetRange(X2, Sample.ByteLength, Sample);
			Delete;
		end;

		Sample.Validate;
		Module.SetModified;
	end;
end;

// --------------------------------------------------------------------------
// Effects
// --------------------------------------------------------------------------

procedure TSampleEditor.Amplify;
var
	X1, X2: Integer;
begin
	if GetSelection(X1, X2) then
	begin
		AskValue(ACTION_AMPLIFY_SAMPLE, 'Sample amplification %:', 0, 300,
			Trunc(Waveform.Sample.GetNormalizationValue(X1, X2) * 100),
			SampleScreen.DialogCallback);
	end;
end;

procedure TSampleEditor.FadeIn;
var
	X1, X2, x, L: Integer;
	UndoEntry: TSampleUndoEntry;
begin
	if GetSelection(X1, X2) then
	begin
		if not UndoInProgress and (Waveform.Sample <> nil) then
		begin
			UndoEntry := CreateUndoEntry(uaFadeIn, Waveform.Sample.Index, 'Fade in');
			AddUndoEntry(UndoEntry);
		end;
		
		L := X2 - X1;
		for x := 0 to L-1 do
			ShortInt(Waveform.Sample.Data[x+X1]) :=
				Trunc(ShortInt(Waveform.Sample.Data[x+X1]) * (x / L));
		Module.SetModified;
	end;
end;

procedure TSampleEditor.FadeOut;
var
	X1, X2, x, L: Integer;
	UndoEntry: TSampleUndoEntry;
begin
	if GetSelection(X1, X2) then
	begin
		if not UndoInProgress and (Waveform.Sample <> nil) then
		begin
			UndoEntry := CreateUndoEntry(uaFadeOut, Waveform.Sample.Index, 'Fade out');
			AddUndoEntry(UndoEntry);
		end;
		
		L := X2 - X1;
		for x := 0 to L-1 do
			ShortInt(Waveform.Sample.Data[x+X1]) :=
				Trunc(ShortInt(Waveform.Sample.Data[x+X1]) * (1.0 - (x / L)));
		Module.SetModified;
	end;
end;

procedure TSampleEditor.CrossFade;
var
	h, i, e, X1, X2: Integer;
	V: Byte;
	UndoEntry: TSampleUndoEntry;
begin
	with Waveform do
	begin
		if (not HasSample) or (IsEmptySample(Sample)) then Exit;
		if not GetSelection(X1, X2) then Exit;

		if not UndoInProgress and (Sample <> nil) then
		begin
			UndoEntry := CreateUndoEntry(uaCrossfade, Sample.Index, 'Crossfade');
			AddUndoEntry(UndoEntry);
		end;

		e := X2-1;
		h := X1 + ((X2 - X1) div 2);
		h := Min(h, Sample.ByteLength) - 1;

		with Sample do
		for i := X1 to h do
		begin
			V := Data[e];
			Data[e] := Byte(
				Trunc((ShortInt(Data[e]) / 2) + (ShortInt(Data[i]) / 2)));
			Data[i] := Byte(
				Trunc((ShortInt(V) / 2) + (ShortInt(Data[i]) / 2)));
			Dec(e);
		end;

		Sample.ZeroFirstWord;
		Module.SetModified;
	end;
end;

procedure TSampleEditor.Equalizer;
begin
end;

procedure TSampleEditor.DoFilter(Hz: Word; LP: Boolean; X1, X2: Integer);
var
	buf: TFloatArray;
	Sam: TSample;
	i: Integer;
	UndoEntry: TSampleUndoEntry;
begin
	Sam := GetCurrentSample;
	if Sam = nil then Exit;

	if not UndoInProgress then
	begin
		UndoEntry := CreateUndoEntry(uaFilter, Sam.Index, 'Filter');
		AddUndoEntry(UndoEntry);
	end;

	Sam.ValidateCoords(X1{%H-}, X2{%H-});
	Sam.GetFloatData(X1, X2, buf{%H-});
	Filter(buf, Hz, LP);

	for i := X1 to X2 do
		ShortInt(Sam.Data[i]) := ShortInt(Trunc(buf[i-X1] * 127));

	Sam.ZeroFirstWord;
	Module.SetModified;
end;

procedure TSampleEditor.FilterLo(Hz: Word = 0);
var
	X1, X2: Integer;
begin
	if GetSelection(X1, X2) then
	begin
		if Hz = 0 then
			AskValue(ACTION_FILTER_LOWPASS, 'Lowpass Filter Frequency (Hz):',
				1, FILTERS_BASE_FREQ div 2, 1000,
				SampleScreen.DialogCallback)
		else
			DoFilter(Hz, True, X1, X2);
	end;
end;

procedure TSampleEditor.FilterHi(Hz: Word = 0);
var
	X1, X2: Integer;
begin
	if GetSelection(X1, X2) then
	begin
		if Hz = 0 then
			AskValue(ACTION_FILTER_HIGHPASS, 'Highpass Filter Frequency (Hz):',
				1, FILTERS_BASE_FREQ div 2, 1000,
				SampleScreen.DialogCallback)
		else
			DoFilter(Hz, False, X1, X2);
	end;
end;

function ROUND_SMP_D(x: Single): Integer; inline;
begin
	if x >= 0.0 then
		Result := Floor(x + 0.5)
	else
		Result := Ceil(x - 0.5);
end;

procedure TSampleEditor.FilterDecreaseTreble;
var
	i, X1, X2: Integer;
	Sam: TSample;
	D: Single;
	UndoEntry: TSampleUndoEntry;
begin
	if GetSelection(X1, X2) then
	begin
		Sam := GetCurrentSample;
		if Sam = nil then Exit;

		if not UndoInProgress then
		begin
			UndoEntry := CreateUndoEntry(uaFilter, Sam.Index, 'Decrease treble');
			AddUndoEntry(UndoEntry);
		end;
		Sam.ValidateCoords(X1, X2);

		for i := X1 to X2-1 do
		begin
			D := (ShortInt(Sam.Data[i]) + ShortInt(Sam.Data[i+1])) / 2;
			ShortInt(Sam.Data[i]) := ShortInt(Clamp(ROUND_SMP_D(D), -128, +127));
		end;

		Sam.ZeroFirstWord;
		Module.SetModified;
	end;
end;

procedure TSampleEditor.FilterIncreaseTreble;
var
	i, X1, X2: Integer;
	Sam: TSample;
	tmp16_1, tmp16_2, tmp16_3: SmallInt;
	UndoEntry: TSampleUndoEntry;
begin
	if GetSelection(X1, X2) then
	begin
		Sam := GetCurrentSample;
		if Sam = nil then Exit;

		if not UndoInProgress then
		begin
			UndoEntry := CreateUndoEntry(uaFilter, Sam.Index, 'Increase treble');
			AddUndoEntry(UndoEntry);
		end;
		Sam.ValidateCoords(X1, X2);

		tmp16_3 := 0;
		for i := X1 to X2 do
		begin
			tmp16_1 := ShortInt(Sam.Data[i]);
			tmp16_2 := tmp16_1;
			Dec(tmp16_1, tmp16_3);
			tmp16_3 := tmp16_2;
			Inc(tmp16_2, CLAMP(ROUND_SMP_D(tmp16_1 / 4), -128, 127));
			ShortInt(Sam.Data[i]) := ShortInt(Clamp(tmp16_2, -128, +127));
		end;

		Sam.ZeroFirstWord;
		Module.SetModified;
	end;
end;

procedure TSampleEditor.Reverse;
var
	X1, X2: Integer;
	UndoEntry: TSampleUndoEntry;
begin
	if GetSelection(X1, X2) then
	begin
		if not UndoInProgress and (Waveform.Sample <> nil) then
		begin
			UndoEntry := CreateUndoEntry(uaReverse, Waveform.Sample.Index, 'Reverse');
			AddUndoEntry(UndoEntry);
		end;
		
		Waveform.Sample.Reverse(X1, X2);
		Module.SetModified;
	end;
end;

procedure TSampleEditor.Invert;
var
	X1, X2: Integer;
	UndoEntry: TSampleUndoEntry;
begin
	if GetSelection(X1, X2) then
	begin
		if not UndoInProgress and (Waveform.Sample <> nil) then
		begin
			UndoEntry := CreateUndoEntry(uaInvert, Waveform.Sample.Index, 'Invert');
			AddUndoEntry(UndoEntry);
		end;
		
		Waveform.Sample.Invert(X1, X2);
		Module.SetModified;
	end;
end;

procedure TSampleEditor.Resample;
begin
	Module.Stop;
	SampleScreen.ResampleDialog(True);
end;

procedure TSampleEditor.Upsample;
var
	UndoEntry: TSampleUndoEntry;
begin
	if not UndoInProgress and (Waveform.Sample <> nil) then
	begin
		UndoEntry := CreateUndoEntry(uaUpsample, Waveform.Sample.Index, 'Upsample');
		AddUndoEntry(UndoEntry);
	end;
	
	Module.Stop;
	Waveform.Sample.Upsample;
	Module.SetModified;
end;

procedure TSampleEditor.Downsample;
var
	UndoEntry: TSampleUndoEntry;
begin
	if not UndoInProgress and (Waveform.Sample <> nil) then
	begin
		UndoEntry := CreateUndoEntry(uaDownsample, Waveform.Sample.Index, 'Downsample');
		AddUndoEntry(UndoEntry);
	end;
	
	Module.Stop;
	Waveform.Sample.Downsample;
	Module.SetModified;
end;

procedure TSampleEditor.Generate;
begin
	Module.Stop;
	Dialog_GenerateWaveform;
end;

// adapted from http://www.joelstrait.com/nanosynth_create_sound_with_ruby/
//
procedure TSampleEditor.GenerateAudio(Wavetype: TWavetype;
	numsamples, samplerate: Integer; frequency: Single);
var
	position_in_period,
	position_in_period_delta: Single;
	Data: Single;
	X, i: Integer;
	UndoEntry: TSampleUndoEntry;
begin
	if not HasSample then Exit;

	if not UndoInProgress and (Waveform.Sample <> nil) then
	begin
		UndoEntry := CreateUndoEntry(uaGenerate, Waveform.Sample.Index, 'Generate audio');
		AddUndoEntry(UndoEntry);
	end;

	X := Max(Waveform.Selection.L, 0);
	if not MakeRoom(X, numsamples) then
	begin
		ModalDialog.ShowMessage('Internal Error', 'Could not make room for sample data.');
		Exit;
	end;

	position_in_period := 0.0;
	position_in_period_delta := frequency / samplerate;
	Data := 0;

	for i := 0 to numsamples-1 do
	begin
		case Wavetype of
			WAVE_SINE:		Data := Sin(position_in_period * (Pi * 2));
			WAVE_SQUARE:	if position_in_period >= 0.5 then Data := 1.0 else Data := -1.0;
			WAVE_SAW:		Data := ((position_in_period * 2.0) - 1.0);
			WAVE_TRIANGLE:	Data := 1.0 - Abs(((position_in_period * 2.0) - 1.0) * 2.0);
			WAVE_NOISE:		begin Waveform.Sample.Data[X+i] := Random(255); Continue; end;
		end;

		ShortInt(Waveform.Sample.Data[X+i]) := ShortInt(Trunc(Data * 127));

		position_in_period := position_in_period + position_in_period_delta;
		if position_in_period >= 1.0 then
			position_in_period := position_in_period - 1.0;
	end;

	with Waveform do
	begin
		Sample.Validate;
		Viewport.SetRange(0, Sample.ByteLength, Sample);
		Selection.SetRange(X, X+numsamples);
		DrawWaveform;
	end;

	if CurrentScreen = SampleScreen then
		SampleScreen.UpdateSampleInfo;

	Module.SetModified;
end;

// ==========================================================================
// Undo/Redo System
// ==========================================================================

procedure TSampleEditor.ClearRedo;
begin
	RedoCount := 0;
end;

function TSampleEditor.CreateUndoEntry(ActionType: TSampleUndoActionType; SampleIndex: Byte; const Description: AnsiString): TSampleUndoEntry;
var
	Sample: TSample;
begin
	Result.ActionType := ActionType;
	Result.SampleIndex := SampleIndex;
	Result.Description := Description;
	Result.BackupFilename := '';
	Result.OldName := '';
	Result.OldFinetune := 0;
	Result.OldVolume := 0;
	Result.OldLoopStart := 0;
	Result.OldLoopLength := 0;
	Result.OldTempLoopStart := 0;
	Result.OldTempLoopLength := 0;
	Result.OldLoopEnabled := False;
	
	// Store current cursor/viewport positions
	if Waveform <> nil then
	begin
		Result.SelectionL := Waveform.Selection.L;
		Result.SelectionR := Waveform.Selection.R;
		Result.ViewportL := Waveform.Viewport.L;
		Result.ViewportR := Waveform.Viewport.R;
	end
	else
	begin
		Result.SelectionL := 0;
		Result.SelectionR := 0;
		Result.ViewportL := 0;
		Result.ViewportR := 0;
	end;
	
	// Store current metadata values before modification
	if (SampleIndex >= 1) and (SampleIndex <= 31) then
	begin
		Sample := Module.Samples[SampleIndex - 1];
		if Sample <> nil then
		begin
			case ActionType of
				uaSetName:
					// OldName should already be set by caller, but ensure it's set
					if Result.OldName = '' then
						Result.OldName := Sample.GetName;
				uaSetFinetune:
					Result.OldFinetune := Sample.Finetune;
				uaSetVolume:
					Result.OldVolume := Sample.Volume;
				uaSetLoop:
				begin
					Result.OldLoopStart := Sample.LoopStart;
					Result.OldLoopLength := Sample.LoopLength;
					Result.OldTempLoopStart := Sample.TempLoopStart;
					Result.OldTempLoopLength := Sample.TempLoopLength;
					Result.OldLoopEnabled := Sample.IsLooped;
				end;
			end;
		end;
	end;
end;

procedure TSampleEditor.AddUndoEntry(const Entry: TSampleUndoEntry);
var
	BackupFile: AnsiString;
begin
	if UndoInProgress then Exit;
	
	// Clear redo stack when new action is performed
	ClearRedo;
	
	// For name changes, we don't need file backups (name is stored in OldName)
	// For other operations, save sample backup to temp file
	if Entry.ActionType <> uaSetName then
	begin
		BackupFile := SaveSampleBackup(Entry.SampleIndex);
		if BackupFile = '' then Exit; // Failed to save backup
	end
	else
		BackupFile := '';
	
	// Move forward in circular buffer
	Inc(UndoIndex);
	if UndoIndex >= 100 then
		UndoIndex := 0;
	
	// If buffer is full, we're overwriting oldest entry
	if UndoCount < 100 then
		Inc(UndoCount);
	
	// Store the entry with backup filename
	UndoBuffer[UndoIndex] := Entry;
	UndoBuffer[UndoIndex].BackupFilename := BackupFile;
end;

function TSampleEditor.SaveSampleBackup(SampleIndex: Byte): AnsiString;
var
	Sample: TSample;
	Filename: AnsiString;
	Counter: Integer;
begin
	Result := '';
	if (SampleIndex < 1) or (SampleIndex > 31) then
		Exit;
	
	Sample := Module.Samples[SampleIndex - 1];
	if (Sample = nil) or Sample.IsEmpty then
		Exit;
	
	// Ensure temp directory exists
	if (TempDir <> '') and (not DirectoryExists(TempDir)) then
		ForceDirectories(TempDir);
	
	// Generate unique filename
	Counter := 0;
	repeat
		Filename := TempDir + Format('propulse_sample_%d_%d_%d.raw', [SampleIndex, Trunc(Now * 86400 * 1000) mod 1000000, Counter]);
		Inc(Counter);
	until not FileExists(Filename) or (Counter > 1000);
	
	if Counter > 1000 then
		Exit; // Failed to generate unique filename
	
	// Save sample data as raw file
	try
		with TFileStreamEx.Create(Filename, fmCreate) do
		try
			Write(Sample.Data[0], Sample.ByteLength);
		finally
			Free;
		end;
		
		// Store filename for cleanup
		if TempFiles <> nil then
			TempFiles.Add(Filename);
		Result := Filename;
	except
		on E: Exception do
		begin
			Log('Error saving sample backup: ' + E.Message);
			Result := '';
		end;
	end;
end;

function TSampleEditor.RestoreSampleBackup(const Filename: AnsiString; SampleIndex: Byte): Boolean;
var
	Sample: TSample;
	FileSize: Int64;
begin
	Result := False;
	if (SampleIndex < 1) or (SampleIndex > 31) then
		Exit;
	if not FileExists(Filename) then
		Exit;
	
	Sample := Module.Samples[SampleIndex - 1];
	if Sample = nil then
		Exit;
	
	try
		with TFileStreamEx.Create(Filename, fmOpenRead) do
		try
			FileSize := Size;
			if FileSize > 0 then
			begin
				Sample.Resize(FileSize);
				Read(Sample.Data[0], FileSize);
				Sample.Validate;
				Result := True;
			end;
		finally
			Free;
		end;
	except
		on E: Exception do
		begin
			Log('Error restoring sample backup: ' + E.Message);
			Result := False;
		end;
	end;
end;

function TSampleEditor.CanUndo: Boolean;
begin
	Result := (UndoCount > 0) and (UndoIndex >= 0);
end;

function TSampleEditor.CanRedo: Boolean;
begin
	// Can redo if there are entries after the current undo position
	Result := (RedoCount > 0) and (UndoCount + RedoCount <= 100);
end;

procedure TSampleEditor.Undo;
var
	Entry: TSampleUndoEntry;
	CurrentName: AnsiString;
	CurrentFinetune: ShortInt;
	CurrentVolume: Byte;
	CurrentLoopStart, CurrentLoopLength: Cardinal;
	CurrentTempLoopStart, CurrentTempLoopLength: Cardinal;
	CurrentLoopEnabled: Boolean;
	CurrentBackupFile, OldBackupFile: AnsiString;
	Sample: TSample;
begin
	if not CanUndo then
	begin
		Log('Nothing to undo.');
		Exit;
	end;
	
	Entry := UndoBuffer[UndoIndex];
	// Save the old backup filename before we potentially overwrite it
	OldBackupFile := Entry.BackupFilename;
	UndoInProgress := True;
	
	try
		// Handle metadata-only changes separately (they don't need file backups)
		if Entry.ActionType in [uaSetName, uaSetFinetune, uaSetVolume, uaSetLoop] then
		begin
			if (Entry.SampleIndex >= 1) and (Entry.SampleIndex <= 31) then
			begin
				Sample := Module.Samples[Entry.SampleIndex - 1];
				if Sample <> nil then
				begin
					case Entry.ActionType of
						uaSetName:
						begin
							// Swap current name with old name
							CurrentName := Sample.GetName;
							Sample.SetName(Entry.OldName);
							// Update entry with current name for redo
							UndoBuffer[UndoIndex].OldName := CurrentName;
						end;
						uaSetFinetune:
						begin
							// Swap current finetune with old finetune
							CurrentFinetune := Sample.Finetune;
							Sample.Finetune := Entry.OldFinetune;
							// Update entry with current finetune for redo
							UndoBuffer[UndoIndex].OldFinetune := CurrentFinetune;
						end;
						uaSetVolume:
						begin
							// Swap current volume with old volume
							CurrentVolume := Sample.Volume;
							Sample.Volume := Entry.OldVolume;
							// Update entry with current volume for redo
							UndoBuffer[UndoIndex].OldVolume := CurrentVolume;
						end;
						uaSetLoop:
						begin
							// Swap current loop points with old loop points
							CurrentLoopStart := Sample.LoopStart;
							CurrentLoopLength := Sample.LoopLength;
							CurrentTempLoopStart := Sample.TempLoopStart;
							CurrentTempLoopLength := Sample.TempLoopLength;
							CurrentLoopEnabled := Sample.IsLooped;
							
							// Restore old values
							Sample.LoopStart := Entry.OldLoopStart;
							Sample.LoopLength := Entry.OldLoopLength;
							Sample.TempLoopStart := Entry.OldTempLoopStart;
							Sample.TempLoopLength := Entry.OldTempLoopLength;
							Sample.UpdateVoice;
							
							// Update entry with current values for redo
							UndoBuffer[UndoIndex].OldLoopStart := CurrentLoopStart;
							UndoBuffer[UndoIndex].OldLoopLength := CurrentLoopLength;
							UndoBuffer[UndoIndex].OldTempLoopStart := CurrentTempLoopStart;
							UndoBuffer[UndoIndex].OldTempLoopLength := CurrentTempLoopLength;
							UndoBuffer[UndoIndex].OldLoopEnabled := CurrentLoopEnabled;
						end;
					end;
				end;
			end;
		end
		else
		begin
			// Restore sample from backup (for data changes)
			// IMPORTANT: For redo to work, we need to save the CURRENT state before restoring
			// This creates a backup that redo can use to restore back to the state we're leaving
			CurrentBackupFile := SaveSampleBackup(Entry.SampleIndex);
			if CurrentBackupFile <> '' then
			begin
				// Store the current state backup in the entry for redo
				// We swap: old backup becomes the restore point, current state becomes the redo point
				UndoBuffer[UndoIndex].BackupFilename := CurrentBackupFile;
			end;
			
			if not RestoreSampleBackup(OldBackupFile, Entry.SampleIndex) then
			begin
				Log('Failed to restore sample backup.');
				Exit;
			end;
		end;
		
		// Restore cursor/viewport positions
		if Waveform <> nil then
		begin
			Waveform.Selection.SetRange(Entry.SelectionL, Entry.SelectionR, Module.Samples[Entry.SampleIndex - 1]);
			Waveform.Viewport.SetRange(Entry.ViewportL, Entry.ViewportR, Module.Samples[Entry.SampleIndex - 1]);
			Waveform.DrawWaveform;
		end;
		
		// Move backwards in undo stack, add to redo
		Dec(UndoIndex);
		if UndoIndex < 0 then
			UndoIndex := 99;
		Dec(UndoCount);
		Inc(RedoCount);
		
		Log('Undo: ' + Entry.Description);
		Module.SetModified;
		
		if CurrentScreen = SampleScreen then
		begin
			// Update waveform if it's showing the affected sample
			if (SampleScreen.Waveform.Sample <> nil) and 
			   (SampleScreen.Waveform.Sample.Index = Entry.SampleIndex) then
			begin
				SampleScreen.Waveform.DrawWaveform;
			end;
			// UpdateSampleInfo already sets Updating flag, so it won't create undo entries
			SampleScreen.UpdateSampleInfo;
			// Refresh sample list to show name changes - Paint the whole screen
			if Entry.ActionType = uaSetName then
				SampleScreen.Paint;
		end;
	finally
		UndoInProgress := False;
	end;
end;

procedure TSampleEditor.Redo;
var
	Entry: TSampleUndoEntry;
	CurrentName: AnsiString;
	CurrentFinetune: ShortInt;
	CurrentVolume: Byte;
	CurrentLoopStart, CurrentLoopLength: Cardinal;
	CurrentTempLoopStart, CurrentTempLoopLength: Cardinal;
	CurrentLoopEnabled: Boolean;
	CurrentBackupFile, OldBackupFile: AnsiString;
	Sample: TSample;
begin
	if not CanRedo then
	begin
		Log('Nothing to redo.');
		Exit;
	end;
	
	// Move forward to get the redo entry
	Inc(UndoIndex);
	if UndoIndex >= 100 then
		UndoIndex := 0;
	
	Entry := UndoBuffer[UndoIndex];
	// Save the old backup filename before we potentially overwrite it
	OldBackupFile := Entry.BackupFilename;
	UndoInProgress := True;
	
	try
		// Handle metadata-only changes separately (they don't need file backups)
		if Entry.ActionType in [uaSetName, uaSetFinetune, uaSetVolume, uaSetLoop] then
		begin
			if (Entry.SampleIndex >= 1) and (Entry.SampleIndex <= 31) then
			begin
				Sample := Module.Samples[Entry.SampleIndex - 1];
				if Sample <> nil then
				begin
					case Entry.ActionType of
						uaSetName:
						begin
							// Swap current name with old name (which contains the redo name)
							CurrentName := Sample.GetName;
							Sample.SetName(Entry.OldName);
							// Update entry with current name for next undo
							UndoBuffer[UndoIndex].OldName := CurrentName;
						end;
						uaSetFinetune:
						begin
							// Swap current finetune with old finetune (which contains the redo value)
							CurrentFinetune := Sample.Finetune;
							Sample.Finetune := Entry.OldFinetune;
							// Update entry with current finetune for next undo
							UndoBuffer[UndoIndex].OldFinetune := CurrentFinetune;
						end;
						uaSetVolume:
						begin
							// Swap current volume with old volume (which contains the redo value)
							CurrentVolume := Sample.Volume;
							Sample.Volume := Entry.OldVolume;
							// Update entry with current volume for next undo
							UndoBuffer[UndoIndex].OldVolume := CurrentVolume;
						end;
						uaSetLoop:
						begin
							// Swap current loop points with old loop points (which contain the redo values)
							CurrentLoopStart := Sample.LoopStart;
							CurrentLoopLength := Sample.LoopLength;
							CurrentTempLoopStart := Sample.TempLoopStart;
							CurrentTempLoopLength := Sample.TempLoopLength;
							CurrentLoopEnabled := Sample.IsLooped;
							
							// Restore redo values
							Sample.LoopStart := Entry.OldLoopStart;
							Sample.LoopLength := Entry.OldLoopLength;
							Sample.TempLoopStart := Entry.OldTempLoopStart;
							Sample.TempLoopLength := Entry.OldTempLoopLength;
							Sample.UpdateVoice;
							
							// Update entry with current values for next undo
							UndoBuffer[UndoIndex].OldLoopStart := CurrentLoopStart;
							UndoBuffer[UndoIndex].OldLoopLength := CurrentLoopLength;
							UndoBuffer[UndoIndex].OldTempLoopStart := CurrentTempLoopStart;
							UndoBuffer[UndoIndex].OldTempLoopLength := CurrentTempLoopLength;
							UndoBuffer[UndoIndex].OldLoopEnabled := CurrentLoopEnabled;
						end;
					end;
				end;
			end;
		end
		else
		begin
			// Restore sample from backup (for data changes)
			// IMPORTANT: For undo to work after redo, we need to save the CURRENT state before restoring
			// This creates a backup that undo can use to restore back to the state we're leaving
			CurrentBackupFile := SaveSampleBackup(Entry.SampleIndex);
			if CurrentBackupFile <> '' then
			begin
				// Store the current state backup in the entry for undo
				// We swap: old backup becomes the restore point, current state becomes the undo point
				UndoBuffer[UndoIndex].BackupFilename := CurrentBackupFile;
			end;
			
			if not RestoreSampleBackup(OldBackupFile, Entry.SampleIndex) then
			begin
				Log('Failed to restore sample backup.');
				Exit;
			end;
		end;
		
		// Restore cursor/viewport positions
		if Waveform <> nil then
		begin
			Waveform.Selection.SetRange(Entry.SelectionL, Entry.SelectionR, Module.Samples[Entry.SampleIndex - 1]);
			Waveform.Viewport.SetRange(Entry.ViewportL, Entry.ViewportR, Module.Samples[Entry.SampleIndex - 1]);
			Waveform.DrawWaveform;
		end;
		
		// Move forward in undo stack, remove from redo
		Inc(UndoCount);
		Dec(RedoCount);
		
		Log('Redo: ' + Entry.Description);
		Module.SetModified;
		
		if CurrentScreen = SampleScreen then
		begin
			// Update waveform if it's showing the affected sample
			if (SampleScreen.Waveform.Sample <> nil) and 
			   (SampleScreen.Waveform.Sample.Index = Entry.SampleIndex) then
			begin
				SampleScreen.Waveform.DrawWaveform;
			end;
			// UpdateSampleInfo already sets Updating flag, so it won't create undo entries
			SampleScreen.UpdateSampleInfo;
			// Refresh sample list to show name changes - Paint the whole screen
			if Entry.ActionType = uaSetName then
				SampleScreen.Paint;
		end;
	finally
		UndoInProgress := False;
	end;
end;

procedure TSampleEditor.StartDrawUndo;
var
	PrevPendingDrawUndo: TSampleUndoEntry;
	PrevDrawOccurred: Boolean;
begin
	if UndoInProgress then
		Exit;
	if IsDrawing then
	begin
		// Previous draw operation didn't complete properly - end it first
		// Save the previous pending entry before starting a new one
		PrevPendingDrawUndo := PendingDrawUndo;
		PrevDrawOccurred := FDrawOccurred;
		
		// Reset drawing state first
		IsDrawing := False;
		FDrawOccurred := False;
		
		// Now finalize the previous draw if it had valid data
		if PrevDrawOccurred and (PrevPendingDrawUndo.BackupFilename <> '') and 
		   (PrevPendingDrawUndo.SampleIndex >= 1) and 
		   (PrevPendingDrawUndo.SampleIndex <= 31) then
		begin
			// Manually add the previous entry to buffer (same logic as EndDrawUndo)
			ClearRedo;
			Inc(UndoIndex);
			if UndoIndex >= 100 then
				UndoIndex := 0;
			if UndoCount < 100 then
				Inc(UndoCount);
			UndoBuffer[UndoIndex] := PrevPendingDrawUndo;
		end;
	end;
	
	if (Waveform <> nil) and (Waveform.Sample <> nil) and 
	   (Waveform.Sample.Index >= 1) and (Waveform.Sample.Index <= 31) then
	begin
		IsDrawing := True;
		FDrawOccurred := False;
		PendingDrawUndo := CreateUndoEntry(uaDraw, Waveform.Sample.Index, 'Draw sample');
		// Save backup BEFORE drawing starts
		// SaveSampleBackup will check if sample is empty and return empty string if so
		PendingDrawUndo.BackupFilename := SaveSampleBackup(PendingDrawUndo.SampleIndex);
		if PendingDrawUndo.BackupFilename = '' then
		begin
			// Failed to save backup (sample might be empty or file system error)
			// Cancel draw undo - user can still draw but won't be able to undo
			IsDrawing := False;
		end;
	end;
end;

procedure TSampleEditor.EndDrawUndo;
var
	Index: Integer;
begin
	if not IsDrawing then
		Exit;
	if UndoInProgress then
		Exit;
	
	// Add the undo entry to the buffer (backup already saved in StartDrawUndo)
	// Only add if drawing actually occurred AND we have a valid backup filename and sample index
	// The backup file should exist if SaveSampleBackup returned a filename
	if FDrawOccurred and (PendingDrawUndo.BackupFilename <> '') and 
	   (PendingDrawUndo.SampleIndex >= 1) and 
	   (PendingDrawUndo.SampleIndex <= 31) then
	begin
		// Use the same logic as AddUndoEntry but skip backup save since we already did it
		// Clear redo stack when new action is performed
		ClearRedo;
		
		// Move forward in circular buffer
		Inc(UndoIndex);
		if UndoIndex >= 100 then
			UndoIndex := 0;
		
		// If buffer is full, we're overwriting oldest entry
		if UndoCount < 100 then
			Inc(UndoCount);
		
		// Store the entry with backup filename (already set in StartDrawUndo)
		UndoBuffer[UndoIndex] := PendingDrawUndo;
	end
	else
	begin
		// Backup failed or invalid - clean up if backup file was created
		if (PendingDrawUndo.BackupFilename <> '') then
		begin
			try
				if FileExists(PendingDrawUndo.BackupFilename) then
					DeleteFile(PendingDrawUndo.BackupFilename);
				if TempFiles <> nil then
				begin
					// Remove from TempFiles list if it exists
					Index := TempFiles.IndexOf(PendingDrawUndo.BackupFilename);
					if Index >= 0 then
						TempFiles.Delete(Index);
				end;
			except
				// Ignore cleanup errors
			end;
		end;
	end;
	
	IsDrawing := False;
	FDrawOccurred := False;
end;

procedure TSampleEditor.CleanupTempFiles;
var
	i: Integer;
begin
	if TempFiles <> nil then
	begin
		for i := 0 to TempFiles.Count - 1 do
		begin
			if FileExists(TempFiles[i]) then
			begin
				try
					DeleteFile(TempFiles[i]);
				except
					// Ignore errors during cleanup
				end;
			end;
		end;
		TempFiles.Clear;
	end;
end;


// ==========================================================================
// Constructor/Destructor
// ==========================================================================

constructor TSampleEditor.Create;
begin
	inherited;
	InitializeUndoSystem;
end;

destructor TSampleEditor.Destroy;
begin
	CleanupTempFiles;
	if TempFiles <> nil then
		TempFiles.Free;
	inherited;
end;

procedure TSampleEditor.InitializeUndoSystem;
begin
	UndoIndex := -1;
	UndoCount := 0;
	RedoCount := 0;
	UndoInProgress := False;
	IsDrawing := False;
	FDrawOccurred := False;
	// Get OS-specific temp directory (always writable)
	TempDir := GetOSTempDir + 'propulse_sample_undo' + PathDelim;
	ForceDirectories(TempDir);
	TempFiles := TStringList.Create;
end;

// ==========================================================================
// Utility
// ==========================================================================

initialization

	SampleEdit := TSampleEditor.Create;

finalization

	if SampleEdit <> nil then
		SampleEdit.Free;


end.
