unit ProTracker.Editor;

interface

uses
//	Windows,
	Classes, Types, SysUtils, Math, DateUtils,
	TextMode, CWE.Core, CWE.Widgets.Text, ShortcutManager,
	ProTracker.Player;

{.$DEFINE TIMING}

const
	CmdChars:    AnsiString = '0123456789AB DEF';

	KeyboardNotes      = 'ZSXDCVGBHNJMQ2W3ER5T6Y7UI9O0P';
	KeyboardNumbers    = '0123456789';
	KeyboardHexNumbers = KeyboardNumbers + 'ABCDEF';
	//KeyboardEffects    = KeyboardHexNumbers;

	EM_SAMPLE = 0;
	EM_VOLUME = 1;
	EM_EFFECT = 2;


type
	PasteMode = (pstInsert, pstOverwrite, pstMix);

	EditColumn = (
		COL_NOTE, COL_OCTAVE,
		COL_SAMPLE_1, COL_SAMPLE_2,
		COL_VOLUME_1, COL_VOLUME_2,
		COL_COMMAND,
		COL_PARAMETER_1, COL_PARAMETER_2,
		COL_NEXTCHANNEL
	);

	EditorKeyNames = (
		keyNONE,
		keyNoteC_lo,	keyNoteCClo,	keyNoteD_lo,	keyNoteDDlo,
		keyNoteE_lo,	keyNoteF_lo,	keyNoteFFlo,	keyNoteG_lo,
		keyNoteGGlo,	keyNoteA_lo,	keyNoteAAlo,	keyNoteB_lo,
		keyNoteC_hi,	keyNoteCChi,	keyNoteD_hi,	keyNoteDDhi,
		keyNoteE_hi,	keyNoteF_hi,	keyNoteFFhi,	keyNoteG_hi,
		keyNoteGGhi,	keyNoteA_hi,	keyNoteAAhi,	keyNoteB_hi,
		keyNoteModifierPreview,		keyNoteClear,		keyNoteFullClear,
		keyNoteDelete,				keyNoteInsert,
		keyNoteDeleteRow,			keyNoteInsertRow,
		keyNoteUseLast,				keyNoteGetLast,
		keyNotePlay,				keyNotePlayRow,
		keyMoveUp,					keyMoveDown,
		keyMoveLeft,				keyMoveRight,
		keyMoveUpAlt,				keyMoveDownAlt,
		keyMoveLeftAlt,				keyMoveRightAlt,
		keyMoveForwards,			keyMoveBackwards,
		keyMovePgUp,				keyMovePgDn,
		keyMoveTop,					keyMoveBottom,
		keyMoveHome,				keyMoveEnd,
		keyPlaybackPlayFrom,		keySelectModifierSkipValue,
		keySelectPatternNext,		keySelectPatternPrev,
		keySelectOctaveLo,			keySelectOctaveHi,
		keySelectSampleNext,		keySelectSamplePrev,
		keyBlockMarkStart,			keyBlockMarkEnd,
		keyBlockMarkWhole,			keyBlockUnmark,
		keyBlockModifier,
		keyBlockCut,				keyBlockCutMasked,			keyBlockCopy,
		keyBlockPaste,				keyBlockOverwrite,			keyBlockMix,
		keyBlockPasteMasked,		keyBlockOverwriteMasked,	keyBlockMixMasked,
		keyBlockDouble,				keyBlockHalve,
		keyBlockSetSample,			//keyBlockSlideWipeEffect,
		keyBlockSlideEffect,		keyBlockWipeEffects,
		keyBlockSwap,				keyToggleEditMask,
		keyTransposeSemitoneUp,		keyTransposeSemitoneDown,
		keyTransposeOctaveUp,		keyTransposeOctaveDown,
		keyChannelToggle,			keyChannelSolo,
		keyPatternInsert,			keyPatternDelete,
		keyUndo,					keyRedo
	);

	TEditCursor = record
		X,
		Row,
		Channel:	Byte;
		Column:		EditColumn;
		Note:		PNote;
	end;

	TClipPattern = record
		Notes: 		array [0..AMOUNT_CHANNELS-1, 0..63] of TNote;
		Size:       TPoint;
		//procedure	FromClipboard;
		//procedure	ToClipboard;
	end;

	// Undo system types
	TUndoActionType = (
		uaSetNote,		// Single note change
		uaInsertNote,	// Row inserted
		uaDeleteNote,	// Row deleted
		uaBlockClear,	// Block cleared
		uaBlockPaste,	// Block pasted
		uaTranspose,	// Transpose operation
		uaBlockSetSample, // Block sample set
		uaBlockWipeEffects, // Block effects wiped
		uaBlockSlideEffect, // Block slide effect
		uaReplaceSample, // Sample replaced in pattern
		uaInsertPattern, // Pattern inserted
		uaDeletePattern, // Pattern deleted
		uaSetOrder,		// Orderlist entry changed
		uaInsertOrder,	// Orderlist entry inserted
		uaDeleteOrder,	// Orderlist entry deleted
		uaSetOrderCount  // Orderlist count changed
	);

	TUndoChange = record
		Pattern, Channel, Row: Byte;
		OldNote, NewNote: TNote;
		// Orderlist fields (used when ActionType is orderlist-related)
		Order: Byte;
		OldOrderValue, NewOrderValue: Byte;
		OldOrderCount, NewOrderCount: Byte;
	end;

	TUndoEntry = record
		ActionType: TUndoActionType;
		Pattern: Byte;
		Changes: array of TUndoChange;
		Description: AnsiString;
		// Cursor positions for restoring after undo/redo
		CursorPattern, CursorChannel, CursorRow: Byte;
		CursorOrder: Byte;
	end;

	TPatternEditor = class(TCWEControl)
	class var
		COL_INVALID,

		COL_HL_ROW,			COL_HL_BEAT,

		COL_SEL_BG,			COL_SEL_FG,
		COL_HL_SEL_ROW,		COL_HL_SEL_BEAT,

		COL_CUR_FG,			COL_CUR_BG,

		COL_ROW,
		COL_ROW_CURRENT,	COL_ROW_CURRENTOTHER:		Byte;

	private
		Locked:		Boolean;
		Drawing:	Boolean;
		Marking: 	Boolean;
		MarkPos: 	TPoint;
		MouseDragging: Boolean;
		MouseDragStart: TPoint;
		MouseDragStartChan: Integer;
		MouseDragStartRow: Integer;
		PrevClickTime: TDateTime;
		PrevClickPos: TPoint;
		PrevClickChan: Integer;
		PrevClickRow: Integer;
		PrevSelectionState: TRect; // Store selection state before first click for toggle detection
		UndoBuffer: array[0..99] of TUndoEntry;
		UndoIndex:	Integer;
		UndoCount:	Integer;
		RedoCount:	Integer;
		UndoInProgress: Boolean;
		
		procedure	ClearRedo;
		function	GetChannelFromX(X: Integer): Integer;
		function	GetRowFromY(Y: Integer): Integer;
	public
		Cursor:		TEditCursor;
		Selection: 	TRect;
		NoteStep,
		ScrollPos:	Byte;
		ClipBuf: 	TClipPattern;
		HighOctave:	Boolean;
		LastNote:	TNote;
		EditMask:	array[EM_SAMPLE..EM_EFFECT] of Boolean;

		procedure	AddUndoEntry(const Entry: TUndoEntry);
		function	CreateUndoEntry(ActionType: TUndoActionType; Pattern: Byte; const Description: AnsiString): TUndoEntry;
		property	IsUndoInProgress: Boolean read UndoInProgress;

		procedure 	SetModified(B: Boolean = True; Force: Boolean = False);
		procedure 	SelectChannel(Ch: Integer);
		procedure	ValidateCursor;
		procedure 	Advance;

		function 	GetNote(Pattern, Channel, Row: Byte): PNote;
		function 	IsValidPosition(Pattern, Channel, Row: Byte): Boolean;
		function 	SetNote(Pattern, Channel, Row: Byte; Note: TNote;
					Masked: Boolean = False): Boolean;
		function 	PrepareSelectionForRender: Byte;

		procedure 	InsertNote(Pattern, Channel, Row: Byte; WholePattern: Boolean = False);
		procedure 	DeleteNote(Pattern, Channel, Row: Byte; WholePattern: Boolean = False);

		procedure 	NoteTranspose(Pattern, Channel, Row: Byte; Semitones: ShortInt);
		procedure 	Transpose(Semitones: ShortInt);

		procedure 	InsertPattern;
		procedure 	DeletePattern(i: Byte);
		procedure 	ExchangePatterns(A, B: Byte);

		procedure 	BufferClear(R: TRect; Masked: Boolean = False);
		procedure 	BufferCopy(R: TRect);
		procedure 	BufferPaste(Mix: PasteMode; Masked: Boolean = False);
		procedure 	BlockSwap;
		procedure 	BlockDoubleOrHalve(DoubleIt: Boolean);
		procedure	BlockWipeEffects;
		procedure	BlockSlideEffect;
		procedure 	BlockSetSample;

		procedure 	ReplaceSample(iFrom, iTo: Byte);

		procedure 	Undo;
		procedure 	Redo;
		function	CanUndo: Boolean;
		function	CanRedo: Boolean;

		procedure 	MessageText(const S: String); inline;
		procedure 	SaveModule(const Filename: String = '');

		procedure 	Paint; override;

		function	MouseWheel(Shift: TShiftState; WheelDelta: Integer; P: TPoint): Boolean; override;
		function	MouseDown(Button: TMouseButton; X, Y: Integer; P: TPoint): Boolean; override;
		procedure	MouseMove(X, Y: Integer; P: TPoint); override;
		function	MouseUp(Button: TMouseButton; X, Y: Integer; P: TPoint): Boolean; override;
		function 	KeyDown(var Key: Integer; Shift: TShiftState): Boolean; override;

		constructor	Create(Owner: TCWEControl;
					const sCaption, sID: AnsiString; const Bounds: TRect;
					IsProtected: Boolean = False); override;
	end;

var
	CurrentSample,
	CurrentPattern: Byte;
	EditorKeys: TKeyBindings;

const
	EditColumnX: array [EditColumn] of Byte = ( 0, 2, 4,5, 7,8,  10,11,12, 0 );

	procedure	SwitchToEditor;

implementation

uses
	MainWindow,
	{$IFDEF TIMING}
	TimeMeasurer,
	{$ENDIF}
	//ClipBrd,
	SDL2,
	ProTracker.Util,
	{$IFDEF DEBUG}
	ProTracker.Sample,
	{$ENDIF}
	Screen.Log,
	Screen.FileReq,
	Screen.Editor,
	CWE.Dialogs,
	Dialog.RenderAudio;

{$IFDEF TIMING}
var
	Time: TTimeMeasurer;
{$ENDIF}


procedure SwitchToEditor;
begin
	Editor.SwitchTo;
end;

// ==========================================================================
// TPatternEditor
// ==========================================================================

constructor TPatternEditor.Create;
begin
	inherited;

	Locked := False;
	NoteStep := 1;
	Selection := Types.Rect(-1, -1, -1, -1);
	UndoIndex := -1;
	UndoCount := 0;
	RedoCount := 0;
	UndoInProgress := False;
	MouseDragging := False;
		PrevClickTime := 0;
		PrevClickPos := Point(-1, -1);
		PrevClickChan := -1;
		PrevClickRow := -1;
		PrevSelectionState := Types.Rect(-1, -1, -1, -1);

	SetBorder(True, True, True, False);

	WantKeyboard := True;
	WantMouse := True;
	WantHover := False;

	EditMask[EM_SAMPLE] := True;
	EditMask[EM_VOLUME] := True;
	EditMask[EM_EFFECT] := False;

	{$IFDEF TIMING}
	Time.Init;
	{$ENDIF}

	with Shortcuts do
	begin
		EditorKeys := SetContext('Editor');

		Bind(keyNoteC_lo, 'Note.C-lo', 'Z');	Bind(keyNoteCClo, 'Note.C#lo', 'S');
		Bind(keyNoteD_lo, 'Note.D-lo', 'X');	Bind(keyNoteDDlo, 'Note.D#lo', 'D');
		Bind(keyNoteE_lo, 'Note.E-lo', 'C');	Bind(keyNoteF_lo, 'Note.F-lo', 'V');
		Bind(keyNoteFFlo, 'Note.F#lo', 'G');	Bind(keyNoteG_lo, 'Note.G-lo', 'B');
		Bind(keyNoteGGlo, 'Note.G#lo', 'H');	Bind(keyNoteA_lo, 'Note.A-lo', 'N');
		Bind(keyNoteAAlo, 'Note.A#lo', 'J');	Bind(keyNoteB_lo, 'Note.B-lo', 'M');
		Bind(keyNoteC_hi, 'Note.C-hi', 'Q');	Bind(keyNoteCChi, 'Note.C#hi', '2');
		Bind(keyNoteD_hi, 'Note.D-hi', 'W');	Bind(keyNoteDDhi, 'Note.D#hi', '3');
		Bind(keyNoteE_hi, 'Note.E-hi', 'E');	Bind(keyNoteF_hi, 'Note.F-hi', 'R');
		Bind(keyNoteFFhi, 'Note.F#hi', '5');	Bind(keyNoteG_hi, 'Note.G-hi', 'T');
		Bind(keyNoteGGhi, 'Note.G#hi', '6');	Bind(keyNoteA_hi, 'Note.A-hi', 'Y');
		Bind(keyNoteAAhi, 'Note.A#hi', '7');	Bind(keyNoteB_hi, 'Note.B-hi', 'U');

		//Bind(keyNoteModifierPreview,	'Note.Modifier.Preview',	'Shift', True);
		Bind(keyToggleEditMask,			'Toggle.EditMask',			',');
		Bind(keyNoteClear,				'Note.Clear', 				'.');
		Bind(keyNoteFullClear,			'Note.FullClear',			'Shift+.');
		Bind(keyNoteDelete,				'Note.Delete', 				'Delete');
		Bind(keyNoteInsert,				'Note.Insert', 				'Insert');
		Bind(keyNoteDeleteRow,			'Note.DeleteRow', 			'Alt+Delete');
		Bind(keyNoteInsertRow,			'Note.InsertRow', 			'Alt+Insert');
		Bind(keyNoteUseLast,			'Note.UseLast', 			'Space');
		Bind(keyNoteGetLast,			'Note.GetLast', 			'Return');
		Bind(keyNotePlay,				'Note.Play', 				'4');
		Bind(keyNotePlayRow,			'Note.PlayRow',				'8');
		Bind(keyMoveUp,					'Move.Up',  				'Up');
		Bind(keyMoveDown,				'Move.Down',				'Down');
		Bind(keyMoveLeft,				'Move.Left', 				'Left');
		Bind(keyMoveRight,				'Move.Right',				'Right');
		Bind(keyMoveUpAlt,				'Move.Up.Alt',				'Alt+Up');
		Bind(keyMoveDownAlt,			'Move.Down.Alt',			'Alt+Down');
		Bind(keyMoveLeftAlt,			'Move.Left.Alt',			'Alt+Left');
		Bind(keyMoveRightAlt,			'Move.Right.Alt',			'Alt+Right');
		Bind(keyMovePgUp,				'Move.PgUp', 				'PageUp');
		Bind(keyMovePgDn,				'Move.PgDn', 				'PageDown');
		Bind(keyMoveTop,				'Move.Top', 				'Ctrl+PageUp');
		Bind(keyMoveBottom,				'Move.Bottom', 				'Ctrl+PageDown');
		Bind(keyMoveHome,				'Move.Home', 				'Home');
		Bind(keyMoveEnd,				'Move.End', 				'End');
		Bind(keyMoveForwards,			'Move.Forwards',			'Tab');
		Bind(keyMoveBackwards,			'Move.Backwards',			'Shift+Tab');
		//Bind(keySelectModifierSkipValue,'Select.Modifier.SkipValue','Alt', True);
		Bind(keySelectPatternNext,		'Select.Pattern.Next', 		'KeyPad +');
		Bind(keySelectPatternPrev,		'Select.Pattern.Prev', 		'KeyPad -');
		Bind(keySelectOctaveLo,			'Select.Octave.Lo', 		'Keypad /');
		Bind(keySelectOctaveHi,			'Select.Octave.Hi', 		'Keypad *');
		Bind(keySelectSampleNext,		'Select.Sample.Next', 		['Ctrl+Down', '>']);
		Bind(keySelectSamplePrev,		'Select.Sample.Prev', 		['Ctrl+Up',   '<']);
		Bind(keyBlockMarkStart,			'Block.MarkStart',	 		'Alt+B');
		Bind(keyBlockMarkEnd,			'Block.MarkEnd', 			'Alt+E');
		Bind(keyBlockMarkWhole,			'Block.MarkWhole', 			'Alt+L');
		Bind(keyBlockUnmark,			'Block.Unmark', 			'Alt+U');
		//Bind(keyBlockModifier,		'Block.Modifier', 			'Shift', True);
		Bind(keyBlockCut,				'Block.Cut', 				'Alt+Z');
		Bind(keyBlockCutMasked,			'Block.CutMasked', 			'Alt+Shift+Z');
		Bind(keyBlockCopy,				'Block.Copy', 				'Alt+C');
		Bind(keyBlockPaste,				'Block.Paste', 				'Alt+P');
		Bind(keyBlockOverwrite,			'Block.Overwrite', 			'Alt+O');
		Bind(keyBlockMix,				'Block.Mix', 				'Alt+M');
		Bind(keyBlockPasteMasked,		'Block.PasteMasked',		'Alt+Shift+P');
		Bind(keyBlockOverwriteMasked,	'Block.OverwriteMasked',	'Alt+Shift+O');
		Bind(keyBlockMixMasked,		 	'Block.MixMasked', 			'Alt+Shift+M');
		Bind(keyBlockDouble,			'Block.Double', 			'Alt+F');
		Bind(keyBlockHalve,				'Block.Halve', 				'Alt+G');
		Bind(keyBlockSetSample,			'Block.SetSample',			'Alt+S');
		Bind(keyBlockSwap,				'Block.Swap',				'Alt+Y');
		//Bind(keyBlockSlideWipeEffect,	'Block.SlideOrWipeEffects',	'Alt+X');
		Bind(keyBlockSlideEffect,		'Block.SlideEffect',		'Alt+X');
		Bind(keyBlockWipeEffects,		'Block.WipeEffects',		'Alt+Shift+X');
		Bind(keyTransposeSemitoneUp,	'Transpose.Semitone.Up',	'Alt+Q');
		Bind(keyTransposeSemitoneDown,	'Transpose.Semitone.Down',	'Alt+A');
		Bind(keyTransposeOctaveUp,		'Transpose.Octave.Up', 	 	'Shift+Alt+Q');
		Bind(keyTransposeOctaveDown,	'Transpose.Octave.Down', 	'Shift+Alt+A');
		Bind(keyChannelToggle,			'Channel.Toggle', 			'Alt+F9');
		Bind(keyChannelSolo,			'Channel.Solo', 			'Alt+F10');
		Bind(keyPatternInsert,			'Pattern.Insert',			'Ctrl+Insert');
		Bind(keyPatternDelete,			'Pattern.Delete',			'Ctrl+Delete');
		Bind(keyUndo,					'Edit.Undo',				'Ctrl+Z');
		Bind(keyRedo,					'Edit.Redo',				'Ctrl+Y');
	end;

	ColorBack := 0;
	ColorFore := 6;

	// Setup palette
	//
	SetLength(Data, 16);
{	SetLength(Data, IDX_COL_ROW_CURRENTOTHER+1);
	SetData(IDX_COL_HL_ROW, 14, 'Highlight row');
	SetData(IDX_COL_HL_BEAT, 15, 'Highlight beat');
	SetData(IDX_COL_SEL_BG, 8, 'Selected background');
	SetData(IDX_COL_SEL_FG, 3, 'Selected foreground');
	SetData(IDX_COL_HL_SEL_ROW, 9, 'Selected highlight row');
	SetData(IDX_COL_HL_SEL_BEAT, 9, 'Selected highlight beat');
	SetData(IDX_COL_INVALID, 13, 'Invalid notes');
	SetData(IDX_COL_CUR_FG, 0, 'Cursor foreground');
	SetData(IDX_COL_CUR_BG, 3, 'Cursor background');
	SetData(IDX_COL_ROW, 0, 'Row number');
	SetData(IDX_COL_ROW_CURRENT, 3, 'Current row number, playing');
	SetData(IDX_COL_ROW_CURRENTOTHER, 6, 'Current row number');}
end;

procedure TPatternEditor.SetModified(B: Boolean = True; Force: Boolean = False);
var
	S: String;
begin
	if B then
	begin
		if (Module.Info.PatternCount <= CurrentPattern) and
			(not Module.IsPatternEmpty(CurrentPattern)) then
		begin
			Module.Info.PatternCount := CurrentPattern;
			Editor.UpdateInfoLabels(True);
		end
		else
		if Force then
			Editor.UpdateInfoLabels(True);
	end;

	if (not Force) and (B = Module.Modified) then Exit;

	S := Module.Info.Title;
	if S = '' then
		S := '(Untitled)';
	S := 'Propulse' + ' - ' + S;
	if B then S := S + ' (*)';

	if Window <> nil then
		Window.SetTitle(S);
end;

procedure TPatternEditor.SaveModule(const Filename: String = '');
var
	Dir, Fn: String;
	{$IFDEF DEBUG}
	S: String;
	sl: TStringList;
	patt, row, ch: Integer;
	Sam: TSample;
const
	DC_B = #9'dc.b'#9;
	{$ENDIF}
begin
	if Filename <> '' then
		Fn := Filename
	else
	begin
		Fn := Editor.lblFilename.Caption;
		Dir := ExtractFilePath(Module.Info.Filename);

		if (Fn = '') or (Dir = '') then
		begin
			FileRequester.Show(True, Options.Dirs.Modules);
			Exit;
		end
		else
			Fn := IncludeTrailingPathDelimiter(Dir) + Fn;
	end;

	if LowerCase(ExtractFileExt(Fn)) = '.wav' then
	begin
		if ModalDialog.Dialog = nil then
			Dialog_Render(False, Fn);
	end
	else
	{$IFDEF DEBUG}
	if LowerCase(ExtractFileExt(Fn)) = '.asm' then
	begin
		sl := TStringList.Create;

		sl.Add(Format('; %s (%s)', [Module.Info.Title, Module.Info.Filename]));

		sl.Add('; ');
		sl.Add('; Patterns');
		sl.Add('; --------');

		for patt := 0 to Module.Info.PatternCount do
		begin
			sl.Add(Format('; Pattern %.2d', [patt]));

			for ch := 0 to 3 do
			begin
				S := Format('P%.2d_%.1d:', [patt, ch]) + DC_B;
				for row := 0 to 63 do
				begin
					S := S + Format('%.3d,', [Module.Notes[patt, ch, row].Pitch]);
					if (row+1) mod 16 = 0 then
					begin
						sl.Add(Copy(S, 1, Length(S)-1));
						S := DC_B;
					end;
				end;

			end;
		end;

		sl.Add('; ');
		sl.Add('; Samples');
		sl.Add('; -------');

		for row := 0 to Module.Samples.Count-1 do
		begin
			Sam := Module.Samples[row];
			if not (Sam.IsEmpty) and (Sam.ByteLength <= 256) then
			begin
				sl.Add(Format('; Sample %.2d (%d words, %d bytes): "%s"', [Sam.Index, Sam.Length, Sam.ByteLength, Sam.GetName]));
				S := Format('S%.2d:', [Sam.Index]) + DC_B;

				for ch := 0 to Sam.ByteLength-1 do
				begin
					S := S + Format('%.3d,', [Sam.Data[ch]]);
					if (ch+1) mod 16 = 0 then
					begin
						sl.Add(Copy(S, 1, Length(S)-1));
						S := DC_B;
					end;
				end;
				if S <> DC_B then
					sl.Add(Copy(S, 1, Length(S)-1));
			end;
		end;

		sl.SaveToFile(Fn);
		sl.Free;
	end
	else
	{$ENDIF}
	begin
		Module.SaveToFile(Fn);
		Module.SetModified(False, True);
		Editor.lblFilename.SetCaption(ExtractFilename(Fn));
		FileRequester.SetDirectory(ExtractFilePath(Fn));
		// Clean up recovery file after successful save
		if Window <> nil then
			Window.CleanupRecoveryFile;
	end;

	ChangeScreen(TCWEScreen(LogScreen));
end;

// ==========================================================================
// Undo/Redo System
// ==========================================================================

procedure TPatternEditor.ClearRedo;
begin
	RedoCount := 0;
end;

function TPatternEditor.CreateUndoEntry(ActionType: TUndoActionType; Pattern: Byte; const Description: AnsiString): TUndoEntry;
begin
	Result.ActionType := ActionType;
	Result.Pattern := Pattern;
	Result.Description := Description;
	SetLength(Result.Changes, 0);
	// Store current cursor position
	Result.CursorPattern := CurrentPattern;
	Result.CursorChannel := Cursor.Channel;
	Result.CursorRow := Cursor.Row;
	Result.CursorOrder := 0; // Will be set by orderlist undo if needed
end;

procedure TPatternEditor.AddUndoEntry(const Entry: TUndoEntry);
var
	i: Integer;
begin
	if UndoInProgress then Exit;
	
	// Clear redo stack when new action is performed
	ClearRedo;
	
	// Move forward in circular buffer
	Inc(UndoIndex);
	if UndoIndex >= 100 then
		UndoIndex := 0;
	
	// If buffer is full, we're overwriting oldest entry
	if UndoCount < 100 then
		Inc(UndoCount);
	
	// Store the entry
	UndoBuffer[UndoIndex] := Entry;
end;

function TPatternEditor.CanUndo: Boolean;
begin
	Result := (UndoCount > 0) and (UndoIndex >= 0);
end;

function TPatternEditor.CanRedo: Boolean;
begin
	// Can redo if there are entries after the current undo position
	Result := (RedoCount > 0) and (UndoCount + RedoCount <= 100);
end;

procedure TPatternEditor.Undo;
var
	Entry: TUndoEntry;
	i: Integer;
	Change: TUndoChange;
begin
	if not CanUndo then
	begin
		MessageText('Nothing to undo.');
		Exit;
	end;
	
	Entry := UndoBuffer[UndoIndex];
	UndoInProgress := True;
	Locked := True;
	
	try
		// Apply undo: restore old values
		for i := 0 to High(Entry.Changes) do
		begin
			Change := Entry.Changes[i];
			case Entry.ActionType of
				uaSetOrder:
					Module.OrderList[Change.Order] := Change.OldOrderValue;
				uaInsertOrder:
				begin
					// Undo insert: delete the inserted entry
					Module.OrderList.Delete(Change.Order);
					if Module.Info.OrderCount > 0 then
						Dec(Module.Info.OrderCount);
				end;
				uaDeleteOrder:
				begin
					// Undo delete: insert the deleted value back
					Module.OrderList.Insert(Change.Order, Change.OldOrderValue);
					if Module.Info.OrderCount < 127 then
						Inc(Module.Info.OrderCount);
				end;
				uaSetOrderCount:
					Module.Info.OrderCount := Change.OldOrderCount;
			else
				Module.Notes[Entry.Pattern, Change.Channel, Change.Row] := Change.OldNote;
			end;
		end;
		
		// Move backwards in undo stack, add to redo
		Dec(UndoIndex);
		if UndoIndex < 0 then
			UndoIndex := 99;
		Dec(UndoCount);
		Inc(RedoCount);
		
		MessageText('Undo: ' + Entry.Description);
		
		// Restore cursor position
		if Entry.ActionType in [uaSetOrder, uaInsertOrder, uaDeleteOrder, uaSetOrderCount] then
		begin
			// Orderlist change: restore orderlist cursor
			if Assigned(OrderList) then
			begin
				OrderList.Cursor.Y := Entry.CursorOrder;
				OrderList.Cursor.X := 0;
				if Assigned(Editor) then
				begin
					Editor.ActiveControl := OrderList;
					OrderList.Paint;
					Editor.UpdateInfoLabels;
				end;
			end;
		end
		else
		begin
			// Pattern change: restore pattern editor cursor
			if Entry.CursorPattern <= MAX_PATTERNS then
			begin
				CurrentPattern := Entry.CursorPattern;
				SelectChannel(Entry.CursorChannel);
				Cursor.Row := Entry.CursorRow;
				ValidateCursor;
				Paint;
			end;
		end;
	finally
		Locked := False;
		UndoInProgress := False;
		Module.SetModified;
	end;
end;

procedure TPatternEditor.Redo;
var
	Entry: TUndoEntry;
	i: Integer;
	Change: TUndoChange;
begin
	if not CanRedo then
	begin
		MessageText('Nothing to redo.');
		Exit;
	end;
	
	// Move forward to get the redo entry
	Inc(UndoIndex);
	if UndoIndex >= 100 then
		UndoIndex := 0;
	
	Entry := UndoBuffer[UndoIndex];
	UndoInProgress := True;
	Locked := True;
	
	try
		// Apply redo: restore new values
		for i := 0 to High(Entry.Changes) do
		begin
			Change := Entry.Changes[i];
			case Entry.ActionType of
				uaSetOrder:
					Module.OrderList[Change.Order] := Change.NewOrderValue;
				uaInsertOrder:
				begin
					// Redo insert: insert the value back
					Module.OrderList.Insert(Change.Order, Change.NewOrderValue);
					if Module.Info.OrderCount < 127 then
						Inc(Module.Info.OrderCount);
				end;
				uaDeleteOrder:
				begin
					// Redo delete: delete the entry again
					Module.OrderList.Delete(Change.Order);
					if Module.Info.OrderCount > 0 then
						Dec(Module.Info.OrderCount);
				end;
				uaSetOrderCount:
					Module.Info.OrderCount := Change.NewOrderCount;
			else
				Module.Notes[Entry.Pattern, Change.Channel, Change.Row] := Change.NewNote;
			end;
		end;
		
		// Move forward in undo stack, remove from redo
		Inc(UndoCount);
		Dec(RedoCount);
		
		MessageText('Redo: ' + Entry.Description);
		
		// Restore cursor position
		if Entry.ActionType in [uaSetOrder, uaInsertOrder, uaDeleteOrder, uaSetOrderCount] then
		begin
			// Orderlist change: restore orderlist cursor
			if Assigned(OrderList) then
			begin
				OrderList.Cursor.Y := Entry.CursorOrder;
				OrderList.Cursor.X := 0;
				if Assigned(Editor) then
				begin
					Editor.ActiveControl := OrderList;
					OrderList.Paint;
					Editor.UpdateInfoLabels;
				end;
			end;
		end
		else
		begin
			// Pattern change: restore pattern editor cursor
			if Entry.CursorPattern <= MAX_PATTERNS then
			begin
				CurrentPattern := Entry.CursorPattern;
				SelectChannel(Entry.CursorChannel);
				Cursor.Row := Entry.CursorRow;
				ValidateCursor;
				Paint;
			end;
		end;
	finally
		Locked := False;
		UndoInProgress := False;
		Module.SetModified;
	end;
end;

function TPatternEditor.IsValidPosition(Pattern, Channel, Row: Byte): Boolean;
begin
	Result :=
		InRange(Pattern, 0, MAX_PATTERNS{-1}) and
		InRange(Channel, 0, AMOUNT_CHANNELS-1) and
		InRange(Row,     0, 63);
end;

function TPatternEditor.GetNote(Pattern, Channel, Row: Byte): PNote;
begin
	if IsValidPosition(Pattern, Channel, Row) then
		Result := @Module.Notes[Pattern, Channel, Row]
	else
		Result := nil;
end;

function TPatternEditor.SetNote(Pattern, Channel, Row: Byte; Note: TNote;
	Masked: Boolean = False): Boolean;
var
	DestNote: PNote;
	OldNote: TNote;
	UndoEntry: TUndoEntry;
	Change: TUndoChange;
begin
	Result := IsValidPosition(Pattern, Channel, Row);
	if Result then
	begin
		// Capture old note for undo (only if not already in undo operation)
		if not UndoInProgress and not Locked then
		begin
			OldNote := Module.Notes[Pattern, Channel, Row];
			
			// Check if note actually changed
			if not Masked then
			begin
				if (OldNote.Pitch <> Note.Pitch) or (OldNote.Sample <> Note.Sample) or
				   (OldNote.Command <> Note.Command) or (OldNote.Parameter <> Note.Parameter) then
				begin
					UndoEntry := CreateUndoEntry(uaSetNote, Pattern, 'Set note');
					SetLength(UndoEntry.Changes, 1);
					Change.Pattern := Pattern;
					Change.Channel := Channel;
					Change.Row := Row;
					Change.OldNote := OldNote;
					Change.NewNote := Note;
					UndoEntry.Changes[0] := Change;
					AddUndoEntry(UndoEntry);
				end;
			end
			else
			begin
				// For masked operations, we need to check what actually changed
				DestNote := @Module.Notes[Pattern, Channel, Row];
				case Cursor.Column of
					COL_NOTE, COL_OCTAVE:
						if DestNote.Pitch <> Note.Pitch then
						begin
							UndoEntry := CreateUndoEntry(uaSetNote, Pattern, 'Set note');
							SetLength(UndoEntry.Changes, 1);
							Change.Pattern := Pattern;
							Change.Channel := Channel;
							Change.Row := Row;
							Change.OldNote := OldNote;
							Change.NewNote := OldNote;
							Change.NewNote.Pitch := Note.Pitch;
							UndoEntry.Changes[0] := Change;
							AddUndoEntry(UndoEntry);
						end;
					COL_SAMPLE_1, COL_SAMPLE_2:
						if DestNote.Sample <> Note.Sample then
						begin
							UndoEntry := CreateUndoEntry(uaSetNote, Pattern, 'Set note');
							SetLength(UndoEntry.Changes, 1);
							Change.Pattern := Pattern;
							Change.Channel := Channel;
							Change.Row := Row;
							Change.OldNote := OldNote;
							Change.NewNote := OldNote;
							Change.NewNote.Sample := Note.Sample;
							UndoEntry.Changes[0] := Change;
							AddUndoEntry(UndoEntry);
						end;
					COL_VOLUME_1, COL_VOLUME_2,
					COL_COMMAND,
					COL_PARAMETER_1, COL_PARAMETER_2:
						if (DestNote.Command <> Note.Command) or (DestNote.Parameter <> Note.Parameter) then
						begin
							UndoEntry := CreateUndoEntry(uaSetNote, Pattern, 'Set note');
							SetLength(UndoEntry.Changes, 1);
							Change.Pattern := Pattern;
							Change.Channel := Channel;
							Change.Row := Row;
							Change.OldNote := OldNote;
							Change.NewNote := OldNote;
							Change.NewNote.Command := Note.Command;
							Change.NewNote.Parameter := Note.Parameter;
							UndoEntry.Changes[0] := Change;
							AddUndoEntry(UndoEntry);
						end;
				end;
			end;
		end;
		
		if not Masked then
			Module.Notes[Pattern, Channel, Row] := Note
		else
		begin
			DestNote := @Module.Notes[Pattern, Channel, Row];

			case Cursor.Column of

				COL_NOTE, COL_OCTAVE:
					DestNote.Pitch   := Note.Pitch;

				COL_SAMPLE_1, COL_SAMPLE_2:
					DestNote.Sample := Note.Sample;

				COL_VOLUME_1, COL_VOLUME_2,
				COL_COMMAND,
				COL_PARAMETER_1, COL_PARAMETER_2:
				begin
					DestNote.Command   := Note.Command;
					DestNote.Parameter := Note.Parameter;
				end;

			end;
		end;

		if not Locked then
			Module.SetModified;
	end;
end;

procedure TPatternEditor.InsertNote(Pattern, Channel, Row: Byte; WholePattern: Boolean = False);
var
	Y, ch1, ch2, ch: Integer;
	UndoEntry: TUndoEntry;
	Change: TUndoChange;
	i: Integer;
begin
	// Guard against out-of-bounds insert requests (e.g. block-paste near end of pattern).
	// Without this, (64 - Row) can go negative and trigger a range check error.
	if (Row > 63) then Exit;
	if (not WholePattern) and (Channel >= AMOUNT_CHANNELS) then Exit;

	if WholePattern then
	begin
		ch1 := 0;
		ch2 := AMOUNT_CHANNELS-1;
	end
	else
	begin
		ch1 := Channel;
		ch2 := Channel;
	end;

	// Capture state for undo (only if not already in undo operation)
	if not UndoInProgress and not Locked then
	begin
		UndoEntry := CreateUndoEntry(uaInsertNote, Pattern, 'Insert row');
		SetLength(UndoEntry.Changes, (ch2 - ch1 + 1) * (64 - Row));
		i := 0;
		for ch := ch1 to ch2 do
		begin
			for Y := Row to 63 do
			begin
				Change.Pattern := Pattern;
				Change.Channel := ch;
				Change.Row := Y;
				Change.OldNote := Module.Notes[Pattern, ch, Y];
				if Y = Row then
					Change.NewNote := EmptyNote
				else
					Change.NewNote := Module.Notes[Pattern, ch, Y-1];
				UndoEntry.Changes[i] := Change;
				Inc(i);
			end;
		end;
		AddUndoEntry(UndoEntry);
		Locked := True; // Prevent SetNote from creating duplicate undo entries
	end;

	for Channel := ch1 to ch2 do
	begin
		for Y := 63 downto Max(Row, 1) do
			Module.Notes[Pattern, Channel, Y] :=
				Module.Notes[Pattern, Channel, Y-1];
		SetNote(Pattern, Channel, Row, EmptyNote);
	end;
	
	if not UndoInProgress then
	begin
		Locked := False;
		Module.SetModified;
	end;
end;

procedure TPatternEditor.DeleteNote(Pattern, Channel, Row: Byte; WholePattern: Boolean = False);
var
	Y, ch1, ch2, ch: Integer;
	UndoEntry: TUndoEntry;
	Change: TUndoChange;
	i: Integer;
begin
	if WholePattern then
	begin
		ch1 := 0;
		ch2 := AMOUNT_CHANNELS-1;
	end
	else
	begin
		ch1 := Channel;
		ch2 := Channel;
	end;

	// Capture state for undo (only if not already in undo operation)
	if not UndoInProgress and not Locked then
	begin
		UndoEntry := CreateUndoEntry(uaDeleteNote, Pattern, 'Delete row');
		SetLength(UndoEntry.Changes, (ch2 - ch1 + 1) * (64 - Row));
		i := 0;
		for ch := ch1 to ch2 do
		begin
			for Y := Row to 63 do
			begin
				Change.Pattern := Pattern;
				Change.Channel := ch;
				Change.Row := Y;
				Change.OldNote := Module.Notes[Pattern, ch, Y];
				if Y < 63 then
					Change.NewNote := Module.Notes[Pattern, ch, Y+1]
				else
					Change.NewNote := EmptyNote;
				UndoEntry.Changes[i] := Change;
				Inc(i);
			end;
		end;
		AddUndoEntry(UndoEntry);
		Locked := True; // Prevent SetNote from creating duplicate undo entries
	end;

	for Channel := ch1 to ch2 do
	begin
		for Y := Row to 62 do
			Module.Notes[Pattern, Channel, Y] :=
				Module.Notes[Pattern, Channel, Y+1];
		Module.Notes[Pattern, Channel, 63] := EmptyNote;
	end;
	
	if not UndoInProgress then
	begin
		Locked := False;
		Module.SetModified;
	end;
end;

procedure TPatternEditor.NoteTranspose(Pattern, Channel, Row: Byte; Semitones: ShortInt);
var
	Note: PNote;
	np: Integer;
begin
	Note := @Module.Notes[Pattern, Channel, Row];
	if Semitones > 0 then
		np := 1
	else
		np := -1;

	case Cursor.Column of

		COL_NOTE, COL_OCTAVE:
		begin
			np := Note.Pitch;
			if np > 0 then
			begin
				np := np + Semitones;
				if InRange(np, 1, 36) then
					Note.Pitch := np;
			end;
		end;

		COL_SAMPLE_1, COL_SAMPLE_2:
		begin
			if Note.Sample > 0 then
				Note.Sample := Min(Max(Note.Sample + np, 1), 31);
		end;

		COL_VOLUME_1, COL_VOLUME_2:
		begin
			if Note.Command = $C then
			begin
				if np > 0 then
					Note.Parameter := Min(Note.Parameter + 1, 64)
				else
				if Note.Parameter > 0 then
					Note.Parameter := Note.Parameter - 1;
			end;
		end;

		COL_COMMAND,
		COL_PARAMETER_1, COL_PARAMETER_2:
		begin
			if ((Note.Parameter <> 0) or (Note.Command <> 0)) and
				(Note.Command <> $C) then
					Note.Parameter := Note.Parameter + np;
		end;

	end;
end;

procedure TPatternEditor.Transpose(Semitones: ShortInt);
var
	x, y: Integer;
begin
	if (Selection.Right >= 0) and (Selection.Bottom >= 0) then
	begin
		for x := Max(Selection.Left, 0) to Selection.Right do
		for y := Max(Selection.Top, 0)  to Selection.Bottom do
			NoteTranspose(CurrentPattern, x, y, Semitones);
	end
	else
		NoteTranspose(CurrentPattern, Cursor.Channel, Cursor.Row, Semitones);
	Module.SetModified;
end;

procedure TPatternEditor.BufferClear(R: TRect; Masked: Boolean = False);
var
	x, y: Integer;
begin
	Locked := True;
	for x := R.Left to R.Right do
		for y := R.Top to R.Bottom do
			SetNote(CurrentPattern, x, y, EmptyNote, Masked);
	Locked := False;
	Module.SetModified;
end;

procedure TPatternEditor.BufferCopy(R: TRect);
var
	x, y: Integer;
begin
	MessageText('Selection copied to memory.');
	for x := R.Left to R.Right do
		for y := R.Top to R.Bottom do
			ClipBuf.Notes[x-R.Left, y-R.Top] := Module.Notes[CurrentPattern, x, y];
	ClipBuf.Size.X := R.Right  - R.Left;
	ClipBuf.Size.Y := R.Bottom - R.Top;
	//Clipbuf.ToClipboard;
end;

procedure TPatternEditor.BufferPaste(Mix: PasteMode; Masked: Boolean = False);
var
	x, y: Integer;
	Note: PNote;
begin
	Locked := True;

	case Mix of

		pstInsert:
			for x := 0 to ClipBuf.Size.X do
			for y := 0 to ClipBuf.Size.Y do
			begin
				InsertNote(CurrentPattern, Cursor.Channel + x, Cursor.Row + y);
				SetNote(CurrentPattern, Cursor.Channel + x, Cursor.Row + y,
					ClipBuf.Notes[x, y], Masked);
			end;

		pstOverwrite:
			for x := 0 to ClipBuf.Size.X do
			for y := 0 to ClipBuf.Size.Y do
				SetNote(CurrentPattern, Cursor.Channel + x, Cursor.Row + y,
					ClipBuf.Notes[x, y], Masked);

		pstMix:
			for x := 0 to ClipBuf.Size.X do
			for y := 0 to ClipBuf.Size.Y do
			begin
				Note := GetNote(CurrentPattern, Cursor.Channel + x, Cursor.Row + y);
				if (Note <> nil) and (Note.Pitch = EmptyNote.Pitch) then
					SetNote(CurrentPattern, Cursor.Channel + x, Cursor.Row + y,
						ClipBuf.Notes[x, y], Masked);
			end;

	else
		Locked := False;
		Exit;
	end;

	Locked := False;
	Module.SetModified;
end;

// Copies current selection to the last pattern in module
// Returns number of rows in prepared pattern
//
function TPatternEditor.PrepareSelectionForRender: Byte;
const
	DestPattern = MAX_PATTERNS;
var
	x, y: Integer;
	R: TRect;
begin
	if (Selection.Left < 0) or (Selection.Top < 0) then
		Selection := Types.Rect(0, 0, AMOUNT_CHANNELS-1, 63);

	for x := 0 to AMOUNT_CHANNELS-1 do
		for y := 0 to 63 do
			SetNote(DestPattern, x, y, EmptyNote);

	R := Selection;
	Result := Min(R.Bottom - R.Top + 1, 63);

	for x := R.Left to R.Right do
	for y := R.Top to R.Bottom do
		SetNote(DestPattern, x, y - R.Top, Module.Notes[CurrentPattern, x, y]);
end;

procedure TPatternEditor.BlockSwap;
var
	p, sx, sy, dx, dy: Integer;
	TempNote: TNote;
	dummyRect, Src, Dest: TRect;
begin
	if (Selection.Left < 0) or (Selection.Top < 0) then
	begin
		Editor.MessageText('No selection!');
		Exit;
	end;

	Src := Selection;
	Inc(Src.Right);
	Inc(Src.Bottom);
	Dest := Types.Bounds(Cursor.Channel, Cursor.Row,
		RectWidth(Src), RectHeight(Src));

	// does Dest overlap with Selection?
	if IntersectRect(dummyRect, Dest, Src) then
	begin
		Editor.MessageText('Swap blocks overlap!');
		Exit;
	end;

	// is Dest out of pattern bounds?
	Dec(Dest.Right);
	Dec(Dest.Bottom);
	if (Dest.Bottom >= 64) or (Dest.Right >= AMOUNT_CHANNELS) then
	begin
		Editor.MessageText('Destination out of pattern bounds!');
		Exit;
	end;

	p := CurrentPattern;
	dy := Dest.Top;

	for sy := Selection.Top to Selection.Bottom do
	begin
		dx := Dest.Left;
		for sx := Selection.Left to Selection.Right do
		begin
			TempNote := Module.Notes[p, sx, sy];
			Module.Notes[p, sx, sy] := Module.Notes[p, dx, dy];
			Module.Notes[p, dx, dy] := TempNote;
			Inc(dx);
		end;
		Inc(dy);
	end;

	{Editor.MessageText(format('sel=%d,%d-%d,%d  dest=%d,%d-%d,%d', [
		Src.Left, Src.Top, Src.Right, Src.Bottom,
		Dest.Left, Dest.Top, Dest.Right, Dest.Bottom]));}
	Module.SetModified;
end;

procedure TPatternEditor.BlockDoubleOrHalve(DoubleIt: Boolean);
var
	p, x, y, yy, t: Integer;
begin
	p := CurrentPattern;
	t := Selection.Top;

	for x := Selection.Left to Selection.Right do
	begin
		if DoubleIt then
			for y := Selection.Bottom-t downto 0 do // double
			begin
				yy := y * 2 + t;
				if (yy < 64) and (y+t < 64) then
					Module.Notes[p, x, yy] := Module.Notes[p, x, y+t];
				if yy < 63 then
					Module.Notes[p, x, yy+1] := EmptyNote;
			end
		else
			for y := 0 to Selection.Bottom-t do // halve
				if y mod 2 = 0 then
					Module.Notes[p, x, (y div 2) + t] := Module.Notes[p, x, y+t];
	end;

	Module.SetModified;
end;

procedure TPatternEditor.BlockSlideEffect;
var
	p, x, y, h, t, FX1, FX2: Integer;
	step: Single;
begin
	p := CurrentPattern;
	t := Selection.Top;
	h := Selection.Bottom - t;
	if h <= 0 then Exit;

	for x := Selection.Left to Selection.Right do
	begin
		FX1 := Module.Notes[p, x, t].Parameter;
		FX2 := Module.Notes[p, x, Selection.Bottom].Parameter - FX1;
		if FX2 = 0 then
			step := 0
		else
			step := FX2 / h;
		for y := 0 to h do
			Module.Notes[p, x, y+t].Parameter := Round(FX1 + (step * y));
	end;

	Module.SetModified;
end;

procedure TPatternEditor.BlockWipeEffects;
var
	x, y: Integer;
begin
	for x := Selection.Left to Selection.Right do
		for y := Selection.Top to Selection.Bottom do
		begin
			Module.Notes[CurrentPattern, x, y].Command   := 0;
			Module.Notes[CurrentPattern, x, y].Parameter := 0;
		end;
	Module.SetModified;
end;

procedure TPatternEditor.BlockSetSample;
var
	x, y: Integer;
begin
	for x := Selection.Left to Selection.Right do
		for y := Selection.Top to Selection.Bottom do
		begin
			if Module.Notes[CurrentPattern, x, y].Sample <> 0 then
				Module.Notes[CurrentPattern, x, y].Sample := CurrentSample;
		end;
	Module.SetModified;
end;

procedure TPatternEditor.ReplaceSample(iFrom, iTo: Byte);
var
	p, x, y: Integer;
begin
	if (iFrom = iTo) then Exit;
	for p := 0 to Module.Info.PatternCount do
	for x := 0 to AMOUNT_CHANNELS-1 do
		for y := 0 to 63 do
		begin
			if Module.Notes[p, x, y].Sample = iFrom then
				Module.Notes[p, x, y].Sample := iTo;
		end;
	Module.SetModified;
end;

procedure TPatternEditor.ExchangePatterns(A, B: Byte);
var
	c, y: Integer;
	Temp: TNote;
begin
	for c := 0 to AMOUNT_CHANNELS-1 do
	for y := 0 to 63 do
	begin
		Temp := Module.Notes[B, c, y];
		Module.Notes[B, c, y] := Module.Notes[A, c, y];
		Module.Notes[A, c, y] := Temp;
	end;
	Module.SetModified;
end;

procedure TPatternEditor.InsertPattern;
var
	p, c, y: Integer;
begin
	if Module.Info.PatternCount < MAX_PATTERNS-1 then
	begin
		for p := Module.Info.PatternCount downto CurrentPattern do
			for c := 0 to AMOUNT_CHANNELS-1 do
			for y := 0 to 63 do
				Module.Notes[p+1, c, y] := Module.Notes[p, c, y];

		for c := 0 to AMOUNT_CHANNELS-1 do
		for y := 0 to 63 do
			Module.Notes[CurrentPattern, c, y] := EmptyNote;

		for c := 0 to Module.Info.OrderCount-1 do
			if Module.OrderList[c] >= CurrentPattern then
				Module.OrderList[c] := Module.OrderList[c] + 1;

		Inc(Module.Info.PatternCount);
		Module.SetModified(True, True);
	end
	else
		ModalDialog.ShowMessage('Insert pattern', 'No room to insert a new pattern!');
end;

procedure TPatternEditor.DeletePattern(i: Byte);
var
	p, c, y: Integer;
begin
	if (Module.Info.PatternCount < 1) or (i >= MAX_PATTERNS) then Exit;

	for p := i to Module.Info.PatternCount-1 do
		for c := 0 to AMOUNT_CHANNELS-1 do
		for y := 0 to 63 do
			Module.Notes[p, c, y] := Module.Notes[p+1, c, y];

	for c := 0 to AMOUNT_CHANNELS-1 do
	for y := 0 to 63 do
		Module.Notes[Module.Info.PatternCount, c, y] := EmptyNote;

	for y := Module.Info.OrderCount-1 downto 0 do
	begin
		if Module.OrderList[y] = i then
		begin
			Module.OrderList.Delete(y);
			Dec(Module.Info.OrderCount);
		end
		else
		if Module.OrderList[y] > i then
			Module.OrderList[y] := Module.OrderList[y] - 1;
	end;

	Dec(Module.Info.PatternCount);
	Module.SetModified(True, True);
end;

procedure TPatternEditor.Advance;
begin
	if (Cursor.Row + NoteStep) > 63 then Exit;
	Inc(Cursor.Row, NoteStep);
end;

// validate cursor coords
procedure TPatternEditor.ValidateCursor;
begin
	if Cursor.Row > 63 then
		Cursor.Row := 63;

	if Cursor.Row < ScrollPos then
		ScrollPos := Cursor.Row
	else
	if Cursor.Row >= (ScrollPos + 31) then
		ScrollPos := Cursor.Row - 31;

	Cursor.X := EditColumnX[Cursor.Column] + (Cursor.Channel * PATTERN_CHAN_WIDTH);
	Cursor.Note := @Module.Notes[CurrentPattern, Cursor.Channel, Cursor.Row];

	// Remember last edit cursor position separately from playback position.
	// This is used e.g. when returning to the pattern editor during playback.
	if Assigned(OrderList) then
		RememberLastEditPosition(
			CurrentPattern,
			OrderList.Cursor.Y,
			Cursor.Row,
			Cursor.Channel,
			Ord(Cursor.Column),
			ScrollPos
		)
	else
		RememberLastEditPosition(
			CurrentPattern,
			0,
			Cursor.Row,
			Cursor.Channel,
			Ord(Cursor.Column),
			ScrollPos
		);
end;

procedure TPatternEditor.MessageText(const S: String);
begin
	Editor.MessageText(S);
end;

procedure TPatternEditor.SelectChannel(Ch: Integer);
begin
	if Ch < 0 then
		Ch := 0
	else
		Ch := Min(Ch, AMOUNT_CHANNELS-1);
	Cursor.Channel := Ch;
	Editor.UpdateInfoLabels(True);
end;

{procedure TPatternEditor.DrawEditMaskIndicators;
begin
end;}

// todo make this less unwieldy
//
function TPatternEditor.KeyDown;
var
	i, n, o: Integer;
	prevColumn: EditColumn;
	r: TRect;
	Sht: TShiftState;
	Sc, Scs: EditorKeyNames;
	AllowEditing: Boolean;
	chrKey: AnsiString;
	NewNote: TNote;
label
	Done;
begin
	if Key = 0 then Exit(False);

	if (Key < 256) then
	begin
		chrKey := UpperCase(Chr(Key));
		//writeln('Key=', Key, '  Chr=', chrKey);
	end
	else
		chrKey := '';

	AllowEditing := not FollowPlayback; //(Module.PlayMode <> PLAY_SONG);
	Result := False;
	prevColumn := Cursor.Column;

	// Continue playback from current position
	//
	if Key = SDLK_F7 then //keyPlaybackPlayFrom
	begin
		PlaybackStartPos.Pattern := CurrentPattern;
		PlaybackStartPos.Channel := Cursor.Channel;
		
		// Shift-F7: start from beginning of pattern at current order
		if ssShift in Shift then
		begin
			if Assigned(OrderList) and
			   (OrderList.Cursor.Y < Module.Info.OrderCount) and
			   (Module.OrderList[OrderList.Cursor.Y] = CurrentPattern) then
			begin
				PlaybackStartPos.Order := OrderList.Cursor.Y;
				PlaybackStartPos.Row := 0;
				Module.Play(OrderList.Cursor.Y, 0);
			end
			else
				Module.PlayPattern(CurrentPattern, 0);
		end
		else
		begin
			// F7: always use current cursor position
			if Assigned(OrderList) and
			   (OrderList.Cursor.Y < Module.Info.OrderCount) and
			   (Module.OrderList[OrderList.Cursor.Y] = CurrentPattern) then
			begin
				PlaybackStartPos.Order := OrderList.Cursor.Y;
				PlaybackStartPos.Row := Cursor.Row;
				Module.Play(OrderList.Cursor.Y, Cursor.Row);
			end
			else
				Module.PlayPattern(CurrentPattern, Cursor.Row);
		end;
		Exit(True);
	end;

	// Set cursor step
	//
	//keySelectModifierSkipValue
	if ssAlt in Shift then
	begin
		o := Pos(chrKey, KeyboardNumbers) - 1;
		if o in [0..9] then
		begin
			if o = 9 then o := 16;
			NoteStep := o;
			MessageText('Cursor step set to ' + IntToStr(o) + '.');
			Result := True;
			goto Done;
		end;
	end;

	Sc := EditorKeyNames(Shortcuts.Find(EditorKeys, Key, Shift));
	//window.Caption := format('Key=%d  Sc=%d', [Key, Integer(sc)]);

	// Some keys are handled differently when playing song
	//
	if FollowPlayback {Module.PlayMode = PLAY_SONG} then
	begin
		// 's' key: solo/unsolo current channel during playback
		if Key = SDLK_s then
		begin
			Editor.ToggleChannelSolo(Cursor.Channel);
			Exit(True);
		end;

		case Sc of

			keyNoteUseLast: // space
				Sc := keyChannelToggle;

			keyMoveBackwards,
			keyMoveLeft,
			keyMoveUp:
			begin
				SelectChannel(Cursor.Channel - 1);
				Exit(True);
			end;

			keyMoveForwards,
			keyMoveRight,
			keyMoveDown:
			begin
				SelectChannel(Cursor.Channel + 1);
				Exit(True);
			end;

		end;
	end;

	// Setup block marking
	//
	if (not AllowEditing) or (Sc <> keyNONE) or (Shift <> [ssShift]) then
		Marking := False
	else
	begin
		if not Marking then
		begin
			MarkPos := Point(Cursor.Channel, Cursor.Row);
			Marking := True;
		end;

		if Marking then
		begin
			Sht := Shift;
			Exclude(Sht, ssShift);
			Scs := EditorKeyNames(Shortcuts.Find(EditorKeys, Key, Sht));

			if Scs in [keyMoveUp..keyMoveEnd] then
			begin
				Sc := Scs;
				Shift := Sht;
			end;
		end;
	end;

	// Insert/play notes into pattern
	//
	if Cursor.Column = COL_NOTE then
	case Sc of

		keyNotePlay:	// 4
		begin
			Module.PlayNote(Cursor.Note, Cursor.Channel);
			Result := True;
		end;

		keyNotePlayRow:	// 8
		begin
			for n := 0 to AMOUNT_CHANNELS-1 do
			begin
				Module.Channel[n].Paula.Kill;
				Module.PlayNote(@Module.Notes[CurrentPattern, n, Cursor.Row], n);
				{with Module.Notes[CurrentPattern, n, Cursor.Row] do
					if Period > 0 then
						Module.PlaySample(GetPeriodTableOffset(Period), Sample, n);}
			end;
			Result := True;
		end;

		else
		begin
			Sht := Shift;
			Exclude(Sht, ssShift);
			Scs := EditorKeyNames(Shortcuts.Find(EditorKeys, Key, Sht));

			if Scs in [keyNoteC_lo..keyNoteB_hi] then
			begin
				Marking := False;
				n := Integer(Scs) - Integer(keyNoteC_lo) + (Integer(HighOctave) * 12);
				if n < 36 then // go no higher than B-3
				begin
					// only insert note data into pattern if shift not pressed
					if AllowEditing then
					begin
						if ModKeys(ssShift) then
						begin
							// just play the sample instead
							Module.PlaySample(n+1, CurrentSample, Cursor.Channel);
						end
						else
						begin
							// Create new note with changes
							LastNote := Cursor.Note^;
							LastNote.Pitch := n + 1;
							if EditMask[EM_SAMPLE] then
								LastNote.Sample := CurrentSample;

							if EditMask[EM_VOLUME] then
							begin
								if LastNote.Command = $C then
								begin
									LastNote.Command   := LastNote.Command;
									LastNote.Parameter := LastNote.Parameter;
								end
								else
								begin
									LastNote.Command   := $0;
									LastNote.Parameter := $0;
								end;
							end;
							if EditMask[EM_EFFECT] then
							begin
								LastNote.Command   := LastNote.Command;
								LastNote.Parameter := LastNote.Parameter;
							end;

							// Use SetNote to track undo
							SetNote(CurrentPattern, Cursor.Channel, Cursor.Row, LastNote);
							Module.PlayNote(@LastNote, Cursor.Channel);
							Advance;
						end; // not Shift

						Result := True;

					end; // AllowEditing
				end;
			end;
		end;
	end;

	if Result then
		goto Done;

	// Handle cursor movement, editing etc.
	//
	case Sc of

		keyMoveUp:
		begin
			Result := True;
			Cursor.Row := Max(0, Cursor.Row - NoteStep);
		end;

		keyMoveDown:
		begin
			Result := True;
			Advance;
		end;

		keyMoveLeft:
		begin
			Result := True;
			if Marking then
				SelectChannel(Cursor.Channel - 1)
			else
			if (Cursor.Column > COL_NOTE) or (Cursor.Channel > 0) then
			begin
				if (Cursor.Column = COL_NOTE) then
				begin
					SelectChannel(Cursor.Channel - 1);
					Cursor.Column := COL_PARAMETER_2;
				end
				else
					Dec(Cursor.Column);
			end;
		end;

		keyMoveRight:
		begin
			Result := True;
			if Marking then
				SelectChannel(Cursor.Channel + 1)
			else
			begin
				Inc(Cursor.Column);

				if (Cursor.Column >= COL_NEXTCHANNEL) then
				begin
					if Cursor.Channel < AMOUNT_CHANNELS-1 then
					begin
						SelectChannel(Cursor.Channel + 1);
						Cursor.Column := COL_NOTE;
					end
					else
						Cursor.Column := COL_PARAMETER_2;
				end;
			end;
		end;

		keyMovePgUp:
		begin
			Result := True;
			if AllowEditing then
			begin
				if Cursor.Row >= 63 then
					Cursor.Row := 48
				else
					Cursor.Row := Max(Cursor.Row - 16, 0);
			end;
		end;

		keyMovePgDn:
		begin
			Result := True;
			if AllowEditing then
				Cursor.Row := Min(Cursor.Row + 16, 63);
		end;

		keyMoveUpAlt:
		if AllowEditing then
		begin
			ScrollPos := Max(ScrollPos-1, 0);
			Cursor.Row := Min(ScrollPos+31, Cursor.Row);
			Result := True;
		end;

		keyMoveDownAlt:
		if AllowEditing then
		begin
			Inc(ScrollPos);
			Cursor.Row := Max(ScrollPos, Cursor.Row);
			Result := True;
		end;

		keyMoveLeftAlt:
		if AllowEditing then
		begin
			SelectChannel(Cursor.Channel - 1);
			Result := True;
		end;

		keyMoveRightAlt:
		if AllowEditing then
		begin
			SelectChannel(Cursor.Channel + 1);
			Result := True;
		end;

		keyMoveTop:
		begin
			if AllowEditing then
				Cursor.Row := 0;
			Result := True;
		end;

		keyMoveBottom:
		begin
			if AllowEditing then
				Cursor.Row := 63;
			Result := True;
		end;

		keyMoveHome:
		begin
			Result := True;
			if AllowEditing then
			begin
				if Options.Tracker.AltHomeEndBehavior then
				begin
					// Propulse behavior
					if Cursor.Row > ScrollPos then
						Cursor.Row := ScrollPos
					else
					begin
						if Cursor.Row > 0 then
							Cursor.Row := 0
						else
						begin
							SelectChannel(0);
							Cursor.Column := COL_NOTE;
						end;
					end;
				end
				else
				begin
					// Impulse Tracker behavior
					if Cursor.Column = COL_NOTE then
					begin
						if Cursor.Channel > 0 then
							SelectChannel(0)
						else
							Cursor.Row := 0;
					end
					else
						Cursor.Column := COL_NOTE;
				end;
			end;
		end;

		keyMoveEnd:
		if AllowEditing then
		begin
			Result := True;
			if Options.Tracker.AltHomeEndBehavior then
			begin
				// PoroTracker behavior
				if Cursor.Row < (ScrollPos + 31) then
					Cursor.Row := (ScrollPos + 31)
				else
					Cursor.Row := 63;
			end
			else
			begin
				// Impulse Tracker behavior
				if Cursor.Column < COL_PARAMETER_2 then
					Cursor.Column := COL_PARAMETER_2
				else
				begin
					if Cursor.Channel >= AMOUNT_CHANNELS-1 then
						Cursor.Row := 63
					else
						SelectChannel(AMOUNT_CHANNELS-1);
				end;
			end;
		end;

		keyMoveBackwards:
		begin
			// jump backwards
			if (Cursor.Column > COL_NOTE) then
				Cursor.Column := COL_NOTE
			else
			SelectChannel(Cursor.Channel - 1);
			Result := True;
		end;

		keyMoveForwards:
		begin
			// jump to next channel
			SelectChannel(Cursor.Channel + 1);
			Cursor.Column := COL_NOTE;
			Result := True;
		end;

		// Insert/Delete

		keyNoteInsert:
		begin
			Result := True;
			if AllowEditing then
				InsertNote(CurrentPattern, Cursor.Channel, Cursor.Row, False);
		end;

		keyNoteDelete:
		begin
			Result := True;
			if AllowEditing then
				DeleteNote(CurrentPattern, Cursor.Channel, Cursor.Row, False);
		end;

		keyNoteInsertRow:
		if AllowEditing then
		begin
			InsertNote(CurrentPattern, Cursor.Channel, Cursor.Row, True);
			Result := True;
		end;

		keyNoteDeleteRow:
		if AllowEditing then
		begin
			DeleteNote(CurrentPattern, Cursor.Channel, Cursor.Row, True);
			Result := True;
		end;

		keyNoteClear:		//190: // period; clear note
		if AllowEditing then
		begin
			case Cursor.Column of

				COL_NOTE, COL_OCTAVE:
				begin
					Cursor.Note.Pitch := 0;
					Cursor.Note.Sample := 0; // ???
				end;

				COL_SAMPLE_1, COL_SAMPLE_2:
				begin
					Cursor.Note.Sample := 0;
					if EditMask[EM_SAMPLE] then
						LastNote.Sample := 0;
				end;

				COL_VOLUME_1, COL_VOLUME_2:
				begin
					Cursor.Note.Command := 0;
					Cursor.Note.Parameter := 0;
					if EditMask[EM_VOLUME] then // should we do this?
					begin
						LastNote.Command   := 0;
						LastNote.Parameter := 0;
					end;
				end;

				COL_COMMAND:
				if Cursor.Note.Command <> $C then
				begin
					Cursor.Note.Command := 0;
					Cursor.Note.Parameter := 0;
					if EditMask[EM_EFFECT] then
						LastNote.Command := 0;
				end;

				COL_PARAMETER_1, COL_PARAMETER_2:
				if Cursor.Note.Command <> $C then
				begin
					Cursor.Note.Parameter := 0;
					if EditMask[EM_EFFECT] then
						LastNote.Parameter := 0;
				end;
			end;

			Module.SetModified;
			Advance;
			Result := True;
		end;

		keyNoteFullClear:
		if AllowEditing then
		begin
			if Cursor.Column <= COL_OCTAVE then
				Cursor.Note.Pitch := 0;

			if Cursor.Column <= COL_SAMPLE_2 then
				Cursor.Note.Sample := 0;

			Cursor.Note.Command := 0;
			Cursor.Note.Parameter := 0;

			Module.SetModified;
			Advance;
			Result := True;
		end;

		keyNoteGetLast:	// enter
		begin
			Result := True;
			with GetNote(CurrentPattern, Cursor.Channel, Cursor.Row)^ do
			begin
				LastNote.Sample := Sample;
				LastNote.Command   := Command;
				LastNote.Parameter := Parameter;
				LastNote.Pitch := Pitch;
				Editor.SetSample(Sample);
			end;
		end;

		keyNoteUseLast:		// Space
		begin
			case Cursor.Column of

				COL_NOTE:
				begin
					NewNote := Cursor.Note^;
					if EditMask[EM_SAMPLE] then
						NewNote.Sample := LastNote.Sample;
					if EditMask[EM_VOLUME] then
					begin
						if LastNote.Command = $C then
						begin
							NewNote.Command   := LastNote.Command;
							NewNote.Parameter := LastNote.Parameter;
						end
						else
						begin
							NewNote.Command   := $0;
							NewNote.Parameter := $0;
						end;
					end;
					if EditMask[EM_EFFECT] then
					begin
						NewNote.Command   := LastNote.Command;
						NewNote.Parameter := LastNote.Parameter;
					end;
					NewNote.Pitch := LastNote.Pitch;
					SetNote(CurrentPattern, Cursor.Channel, Cursor.Row, NewNote);
					Module.PlayNote(Cursor.Note, Cursor.Channel);
				end;

				COL_SAMPLE_1, COL_SAMPLE_2:
				begin
					NewNote := Cursor.Note^;
					NewNote.Sample := LastNote.Sample;
					SetNote(CurrentPattern, Cursor.Channel, Cursor.Row, NewNote);
				end;

				COL_VOLUME_1, COL_VOLUME_2:
				begin
					NewNote := Cursor.Note^;
					NewNote.Command   := $C; // ???
					NewNote.Parameter := Min(64, LastNote.Parameter);
					SetNote(CurrentPattern, Cursor.Channel, Cursor.Row, NewNote);
				end;

				COL_COMMAND:
				begin
					NewNote := Cursor.Note^;
					if NewNote.Command = $C then
						NewNote.Parameter := Min(64, NewNote.Parameter)
					else
						NewNote.Command := LastNote.Command;
					SetNote(CurrentPattern, Cursor.Channel, Cursor.Row, NewNote);
				end;

				COL_PARAMETER_1, COL_PARAMETER_2:
				begin
					NewNote := Cursor.Note^;
					NewNote.Parameter := LastNote.Parameter;
					SetNote(CurrentPattern, Cursor.Channel, Cursor.Row, NewNote);
				end;
			end;

			Advance;
			Result := True;
		end;

		// Block

		keyBlockMarkWhole: // Mark entire column/pattern
		begin
			Result := True;
			r := Bounds(Cursor.Channel, 0, 0, 63);
			if (r.Left = Selection.Left) and (r.Right  = Selection.Right) and
				(r.Top = Selection.Top)  and (r.Bottom = Selection.Bottom) then
					Selection := Types.Rect(0, 0, AMOUNT_CHANNELS-1, r.Bottom)
			else
				Selection := r;
		end;

		keyBlockMarkStart:
		begin
			Result := True;
			Selection.Left   := Cursor.Channel;
			Selection.Top    := Cursor.Row;
			Selection.Right  := Max(Cursor.Channel, Selection.Right);
			Selection.Bottom := Max(Cursor.Row, Selection.Bottom);
		end;

		keyBlockMarkEnd:	// Mark end of block (fixme maybe)
		begin
			Result := True;
			i := Selection.Right;
			n := Cursor.Channel;
			Selection.Left   := Min(i, n);
			Selection.Right  := Max(i, n);
			i := Cursor.Row;
			n := Selection.Bottom;
			Selection.Bottom := Max(i, n);
			Selection.Top    := Min(i, n);
		end;

		keyBlockUnmark:		// Unmark block/Release clipboard memory
		begin
			Result := True;
			Selection := Types.Rect(-1, -1, -1, -1);
		end;

		keyBlockCopy:		// Copy block into clipboard
		begin
			Result := True;
			BufferCopy(Selection);
		end;

		keyBlockCut,		// Cut block
		keyBlockCutMasked:
		begin
			Result := True;
			if AllowEditing then
			begin
				BufferCopy(Selection);
				BufferClear(Selection, (Sc = keyBlockCutMasked));
			end;
		end;

		keyBlockPaste,		// Alt-P, Alt-V
		keyBlockPasteMasked:
		begin
			Result := True;
			if AllowEditing then
				BufferPaste(pstInsert, (Sc = keyBlockPasteMasked));
		end;

		keyBlockOverwrite,
		keyBlockOverwriteMasked:
		begin
			Result := True;
			if AllowEditing then
				BufferPaste(pstOverwrite, (Sc = keyBlockOverwriteMasked));
		end;

		keyBlockMix,		// Mix each row from clipboard with pattern data
		keyBlockMixMasked:
		begin
			Result := True;
			if AllowEditing then
				BufferPaste(pstMix, (Sc = keyBlockMixMasked));
		end;

		keyBlockDouble:
		begin
			Result := True;
			if AllowEditing then
				BlockDoubleOrHalve(True);
		end;

		keyBlockHalve:
		begin
			Result := True;
			if AllowEditing then
				BlockDoubleOrHalve(False);
		end;

		keyBlockSetSample:
		begin
			Result := True;
			if AllowEditing then
				BlockSetSample;
		end;

		keyBlockSwap:
		begin
			Result := True;
			if AllowEditing then
				BlockSwap;
		end;

		keyBlockSlideEffect:
		begin
			Result := True;
			if AllowEditing then
				BlockSlideEffect;
		end;

		keyBlockWipeEffects:
		begin
			Result := True;
			if AllowEditing then
				BlockWipeEffects;
		end;

		// Transpose

		keyTransposeSemitoneUp:
		begin
			Result := True;
			Transpose(+1);
		end;

		keyTransposeSemitoneDown:
		begin
			Result := True;
			Transpose(-1);
		end;

		keyTransposeOctaveUp:
		begin
			Result := True;
			Transpose(+12);
		end;

		keyTransposeOctaveDown:
		begin
			Result := True;
			Transpose(-12);
		end;

		// Channel muting

		keyChannelToggle:
		begin
			Result := True;
			Editor.ToggleChannel(Cursor.Channel);
		end;

		keyChannelSolo:
		begin
			Result := True;
			Editor.ToggleChannelSolo(Cursor.Channel);
		end;

		// Pattern insertion/deletion

		keyPatternInsert:
		begin
			Result := True;
			InsertPattern;
		end;

		keyPatternDelete:
		begin
			Result := True;
			DeletePattern(CurrentPattern);
		end;

		// Undo/Redo

		keyUndo:
		begin
			Result := True;
			if AllowEditing then
				Undo;
		end;

		keyRedo:
		begin
			Result := True;
			if AllowEditing then
				Redo;
		end;

		// Misc

		keySelectSamplePrev:
		begin
			Editor.SetSample(CurrentSample - 1);
			Result := True;
		end;

		keySelectSampleNext:
		begin
			Editor.SetSample(CurrentSample + 1);
			Result := True;
		end;

		keyToggleEditMask:
		begin
			Result := True;
			if AllowEditing then
			begin
				o := -1;
				case Cursor.Column of

					COL_SAMPLE_1, COL_SAMPLE_2:
						o := EM_SAMPLE;

					COL_VOLUME_1, COL_VOLUME_2:
						o := EM_VOLUME;

					COL_COMMAND,
					COL_PARAMETER_1, COL_PARAMETER_2:
						o := EM_EFFECT;

				end;
				if o >= EM_SAMPLE then
				begin
					EditMask[o] := not EditMask[o];
					Editor.UpdateInfoLabels(True);
					//DrawEditMaskIndicators;
				end;
			end;
		end;

	else

		Marking := False;

		// insert data into pattern
		if AllowEditing then
		case Cursor.Column of

			COL_OCTAVE:
			begin
				o := Pos(chrKey, KeyboardNumbers) - 1;
				if o in [1..3] then
				begin
					Result := True;
					if Cursor.Note^.Pitch > 0 then
					begin
						n := (Cursor.Note^.Pitch - 1) mod 12;
						if n >= 0 then
						begin
							LastNote := Cursor.Note^;
							LastNote.Pitch := n + 1 + ((o - 1) * 12);
							SetNote(CurrentPattern, Cursor.Channel, Cursor.Row, LastNote);
							Advance;
						end;
					end;
				end;
			end;

			COL_SAMPLE_1:  // sample number 1st digit
			begin
				o := Pos(chrKey, KeyboardNumbers) - 1;
				if o in [0..3] then
				begin
					Result := True;
					LastNote := Cursor.Note^;
					LastNote.Sample := Min((o * 10) + (LastNote.Sample mod 10), 31);
					SetNote(CurrentPattern, Cursor.Channel, Cursor.Row, LastNote);
					Editor.SetSample(LastNote.Sample);
					Inc(Cursor.Column);
				end;
			end;

			COL_SAMPLE_2:  // sample number 2nd digit
			begin
				o := Pos(chrKey, KeyboardNumbers) - 1;
				if o >= 0 then
				begin
					LastNote := Cursor.Note^;
					LastNote.Sample := Min((LastNote.Sample div 10 * 10) + o, 31);
					SetNote(CurrentPattern, Cursor.Channel, Cursor.Row, LastNote);
					Editor.SetSample(LastNote.Sample);
					Dec(Cursor.Column);
					Advance;
					Result := True;
				end;
			end;

			COL_VOLUME_1:	// volume 1st digit
			begin
				o := Pos(chrKey, KeyboardNumbers) - 1;
				if o >= 0 then
				begin
					LastNote := Cursor.Note^;
					if LastNote.Command <> $C then
						LastNote.Parameter := 0;
					LastNote.Command := $C;
					LastNote.Parameter := Min( (o * 10) + (LastNote.Parameter mod 10), 64);
					SetNote(CurrentPattern, Cursor.Channel, Cursor.Row, LastNote);
					Inc(Cursor.Column);
					Result := True;
				end;
			end;

			COL_VOLUME_2:	// volume 2nd digit
			begin
				o := Pos(chrKey, KeyboardNumbers) - 1;
				if o >= 0 then
				begin
					LastNote := Cursor.Note^;
					if LastNote.Command <> $C then
						LastNote.Parameter := 0;
					LastNote.Command := $C;
					LastNote.Parameter := Min( (LastNote.Parameter div 10 * 10) + o, 64);
					SetNote(CurrentPattern, Cursor.Channel, Cursor.Row, LastNote);
					Dec(Cursor.Column);
					Advance;
					Result := True;
				end;
			end;

			COL_COMMAND:	// effect type
			begin
				o := Pos(chrKey, CmdChars) - 1;
				if o >= 0 then
				begin
					LastNote := Cursor.Note^;
					if LastNote.Command = $C then
						LastNote.Parameter := 0;
					LastNote.Command := o;
					SetNote(CurrentPattern, Cursor.Channel, Cursor.Row, LastNote);
					Advance;
					Result := True;
				end;
			end;

			COL_PARAMETER_1,	// effect 1st digit
			COL_PARAMETER_2:	// effect 2nd digit
			if Cursor.Note.Command <> $C then
			begin
				o := Pos(chrKey, KeyboardHexNumbers) - 1;
				if o >= 0 then
				begin
					LastNote := Cursor.Note^;
					if Cursor.Column = COL_PARAMETER_1 then
					begin
						LastNote.Parameter := (o * $10) + (LastNote.Parameter mod $10);
						SetNote(CurrentPattern, Cursor.Channel, Cursor.Row, LastNote);
						Inc(Cursor.Column);
					end
					else
					begin
						LastNote.Parameter := (LastNote.Parameter div $10 * $10) + o;
						SetNote(CurrentPattern, Cursor.Channel, Cursor.Row, LastNote);
						Cursor.Column := COL_PARAMETER_1;
						Advance;
					end;
					Result := True;
				end;
			end;

		end; // case Column

	end;

	if not Result then Exit;

Done:

	if Marking then
	begin
		Selection.Left  := Min(Cursor.Channel, MarkPos.X);
		Selection.Right := Max(Cursor.Channel, MarkPos.X);
		Selection.Top   := Min(Cursor.Row, MarkPos.Y);
		Selection.Bottom:= Max(Cursor.Row, MarkPos.Y);
	end;

	if AllowEditing then
		ValidateCursor;

	if prevColumn <> Cursor.Column then
		Editor.UpdateInfoLabels(True);

	Paint;
end;

function TPatternEditor.MouseWheel(Shift: TShiftState; WheelDelta: Integer; P: TPoint): Boolean;
const
	ScrollStep = 2;
begin
	if FollowPlayback then
		SelectChannel(Cursor.Channel - WheelDelta)
	else
	begin
		if WheelDelta > 0 then
			ScrollPos := Max(ScrollPos - Abs(WheelDelta*ScrollStep), 0)
		else
		if WheelDelta < 0 then
			ScrollPos := Min(ScrollPos + Abs(WheelDelta*ScrollStep), 63 - Height);

		// Remember view offset changes even when the cursor doesn't move (e.g. mouse wheel scrolling).
		if Assigned(OrderList) then
			RememberLastEditPosition(
				CurrentPattern,
				OrderList.Cursor.Y,
				Cursor.Row,
				Cursor.Channel,
				Ord(Cursor.Column),
				ScrollPos
			)
		else
			RememberLastEditPosition(
				CurrentPattern,
				0,
				Cursor.Row,
				Cursor.Channel,
				Ord(Cursor.Column),
				ScrollPos
			);
	end;
	Paint;
	Result := True;
end;

function TPatternEditor.MouseDown(Button: TMouseButton; X, Y: Integer; P: TPoint): Boolean;
var
	Chan, Row: Integer;
	IsDoubleClick: Boolean;
	NowTime: TDateTime;
	ColOffset: Integer;
begin
	Result := True;
	NowTime := Now;

	if P.X < 2 then // row number clicked
	begin
		Cursor.Row := P.Y + ScrollPos;
		if Button = mbRight then // center row using right button
			ScrollPos := Cursor.Row - 16;
		ValidateCursor;
		Exit;
	end;

	Chan := GetChannelFromX(P.X);
	Row := GetRowFromY(P.Y);
	
	if (Chan < 0) or (Row < 0) then
	begin
		if Button = mbLeft then
			MouseDragging := False;
		Exit(False);
	end;

	case Button of

		mbLeft:
		begin
			// Store selection state BEFORE any modifications (needed for double-click toggle)
			// This allows us to check what the selection was before the first click cleared it
			// We'll use this for the toggle check on double-click
			// Note: We need to check BEFORE clearing selection on single click
			// Store selection state if this might be the first click of a double-click
			if (PrevClickTime = 0) or 
			   ((PrevClickTime > 0) and 
			    (MilliSecondsBetween(NowTime, PrevClickTime) >= 500) and
			    (PrevClickChan = Chan)) then
			begin
				// First click or new click on same channel (after timeout) - store current selection state
				PrevSelectionState := Selection;
			end;
			
			// Double-click detection:
			// - Time window: 25ms to 500ms between clicks
			// - Minimum time: 25ms (prevents glitches from accidental rapid clicks)
			// - Maximum time: 500ms (0.5 seconds) between the two clicks
			// - Position: Must be on the same channel AND row (logical position, not pixel)
			// Calculation: (MilliSecondsBetween >= 25) AND (MilliSecondsBetween < 500)
			IsDoubleClick := False;
			if PrevClickTime > 0 then
			begin
				if (MilliSecondsBetween(NowTime, PrevClickTime) >= 25) and
				   (MilliSecondsBetween(NowTime, PrevClickTime) < 500) and
				   (PrevClickChan = Chan) and (PrevClickRow = Row) then
				begin
					IsDoubleClick := True;
					{$IFDEF DEBUG}
					MessageText(Format('Double-click detected: %dms, Chan=%d Row=%d', 
						[MilliSecondsBetween(NowTime, PrevClickTime), Chan, Row]));
					{$ENDIF}
				end;
			end;
			
			// Handle double-click FIRST - before any other logic
			// Priority 1: Double-click anywhere in channel - same as Alt-L (keyBlockMarkWhole)
			// Alt-L works regardless of row, so double-click should too
			if IsDoubleClick then
			begin
				// Match Alt-L behavior: Mark entire column/pattern
				// Toggle sequence: current channel -> all channels -> no channels
				// Check what the selection state was BEFORE the first click
				if (PrevSelectionState.Left = Chan) and (PrevSelectionState.Right = Chan) and
				   (PrevSelectionState.Top = 0) and (PrevSelectionState.Bottom = 63) then
				begin
					// Channel was already selected, expand to all channels (same as Alt-L toggle)
					Selection := Types.Rect(0, 0, AMOUNT_CHANNELS-1, 63);
				end
				else
				if (PrevSelectionState.Left = 0) and (PrevSelectionState.Right = AMOUNT_CHANNELS-1) and
				   (PrevSelectionState.Top = 0) and (PrevSelectionState.Bottom = 63) then
				begin
					// All channels were selected, clear selection (third state)
					Selection := Types.Rect(-1, -1, -1, -1);
				end
				else
				begin
					// Channel was not selected, select this channel (rows 0-63)
					Selection := Types.Rect(Chan, 0, Chan, 63);
				end;
				// Reset selection state tracking for next potential double-click
				PrevSelectionState := Types.Rect(-1, -1, -1, -1);
				// Update double-click tracking and exit immediately - don't enable capture
				PrevClickTime := NowTime;
				PrevClickPos := P;
				PrevClickChan := Chan;
				PrevClickRow := Row;
				Paint;
				Exit;
			end;
			
			// Priority 2: Double-click on marked area - unmark channel
			if IsDoubleClick and (Selection.Left >= 0) then
			begin
				if (Chan >= Selection.Left) and (Chan <= Selection.Right) and
				   (Row >= Selection.Top) and (Row <= Selection.Bottom) then
				begin
					// Clicked in selection, unmark this channel
					if (Selection.Left = Selection.Right) then
					begin
						// Only one channel selected, clear selection
						Selection := Types.Rect(-1, -1, -1, -1);
					end
					else
					begin
						// Multiple channels, remove this one
						if Chan = Selection.Left then
							Selection.Left := Selection.Left + 1
						else
						if Chan = Selection.Right then
							Selection.Right := Selection.Right - 1;
					end;
					// Update double-click tracking and exit immediately - don't enable capture
					PrevClickTime := NowTime;
					PrevClickPos := P;
					PrevClickChan := Chan;
					PrevClickRow := Row;
					Paint;
					Exit;
				end;
			end;
			
			// Set cursor position
			ColOffset := P.X - 3 - (Chan * (Width div 4));
			case ColOffset of
				$0,$1:	Cursor.Column := COL_NOTE;
				$2: 	Cursor.Column := COL_OCTAVE;
				$4:		Cursor.Column := COL_SAMPLE_1;
				$5:		Cursor.Column := COL_SAMPLE_2;
				$7: 	Cursor.Column := COL_VOLUME_1;
				$8:		Cursor.Column := COL_VOLUME_2;
				$A: 	Cursor.Column := COL_COMMAND;
				$B: 	Cursor.Column := COL_PARAMETER_1;
				$C: 	Cursor.Column := COL_PARAMETER_2;
				$D:     Exit;
			end;
			Cursor.Row := Row;
			Cursor.Channel := Chan;
			ValidateCursor;
			
			// Handle shift-click: start selection from current position
			if (SDL_GetModState and KMOD_SHIFT) <> 0 then
			begin
				// Start selection from mark position or current cursor
				if not Marking then
				begin
					MarkPos := Point(Cursor.Channel, Cursor.Row);
					Marking := True;
				end;
				Selection.Left  := Min(Cursor.Channel, MarkPos.X);
				Selection.Right := Max(Cursor.Channel, MarkPos.X);
				Selection.Top   := Min(Cursor.Row, MarkPos.Y);
				Selection.Bottom := Max(Cursor.Row, MarkPos.Y);
				Paint;
			end
			else
			begin
				// Prepare for potential drag selection, but don't start dragging yet
				// Only start dragging if mouse actually moves in MouseMove
				MouseDragging := False;
				MouseDragStart := Point(Cursor.Channel, Cursor.Row);
				MouseDragStartChan := Cursor.Channel;
				MouseDragStartRow := Cursor.Row;
				Marking := False;
				// Clear any existing selection on single click (not shift-click, not double-click)
				// BUT: Don't clear if this might become a double-click (same channel, within 500ms)
				// We need to preserve the selection state for toggle detection
				// Only check channel (not row) because Alt-L works on any row
				if not ((PrevClickTime > 0) and 
				        (MilliSecondsBetween(NowTime, PrevClickTime) < 500) and
				        (PrevClickChan = Chan)) then
				begin
					// Not a potential double-click, clear selection
					Selection := Types.Rect(-1, -1, -1, -1);
				end;
				// If it IS a potential double-click, preserve the selection for now
				// It will be handled in the double-click handler or cleared in MouseUp if timeout
				// Enable mouse capture so we receive MouseMove events to detect actual drag
				if Screen <> nil then
					Screen.MouseInfo.Capturing := True;
				Paint;
			end;
			
			// Update double-click tracking
			PrevClickTime := NowTime;
			PrevClickPos := P;
			PrevClickChan := Chan;
			PrevClickRow := Row;
			
			Editor.UpdateInfoLabels(False);
		end;

		mbMiddle:
		begin
			if Chan in [0..AMOUNT_CHANNELS-1] then
			begin
				Module.Channel[Chan].Enabled := not
					Module.Channel[Chan].Enabled;
				Editor.UpdateInfoLabels(False);
			end;
		end;

		mbRight:
			Result := False; // unhandled -> show menu

	end;
end;

function TPatternEditor.GetChannelFromX(X: Integer): Integer;
begin
	if X < 3 then
		Result := -1
	else
	begin
		X := X - 3;
		Result := X div (Width div 4);
		if not (Result in [0..AMOUNT_CHANNELS-1]) then
			Result := -1;
	end;
end;

function TPatternEditor.GetRowFromY(Y: Integer): Integer;
begin
	Result := Y + ScrollPos;
	if (Result < 0) or (Result > 63) then
		Result := -1;
end;

procedure TPatternEditor.MouseMove(X, Y: Integer; P: TPoint);
var
	Chan, Row: Integer;
begin
	inherited MouseMove(X, Y, P);
	
	// Check if we should start dragging (mouse moved away from initial click)
	if Screen <> nil then
	begin
		if Screen.MouseInfo.Capturing and (not MouseDragging) then
		begin
			Chan := GetChannelFromX(P.X);
			Row := GetRowFromY(P.Y);
			
			// Only start dragging if mouse moved to a different channel or row
			if (Chan >= 0) and (Row >= 0) and 
			   ((Chan <> MouseDragStartChan) or (Row <> MouseDragStartRow)) then
			begin
				MouseDragging := True;
			end;
		end;
		
		// Update selection during drag
		if MouseDragging then
		begin
			Chan := GetChannelFromX(P.X);
			Row := GetRowFromY(P.Y);
			
			if (Chan >= 0) and (Row >= 0) then
			begin
				Cursor.Channel := Chan;
				Cursor.Row := Row;
				ValidateCursor;
				
				// Create/update selection during drag
				Selection.Left  := Min(Cursor.Channel, MouseDragStart.X);
				Selection.Right := Max(Cursor.Channel, MouseDragStart.X);
				Selection.Top   := Min(Cursor.Row, MouseDragStart.Y);
				Selection.Bottom := Max(Cursor.Row, MouseDragStart.Y);
				
				Paint;
			end;
		end;
	end;
end;

function TPatternEditor.MouseUp(Button: TMouseButton; X, Y: Integer; P: TPoint): Boolean;
var
	NowTime: TDateTime;
begin
	Result := inherited MouseUp(Button, X, Y, P);
	
	if (Button = mbLeft) then
	begin
		NowTime := Now;
		
		// If we were capturing but didn't actually drag, it was just a single click
		if (Screen <> nil) and Screen.MouseInfo.Capturing and (not MouseDragging) then
		begin
			// Single click without drag - check if we preserved selection for potential double-click
			// If enough time has passed (>= 500ms) since MouseDown, it's definitely not a double-click
			// Clear the preserved selection if it matches what we preserved
			if (PrevClickTime > 0) and 
			   (MilliSecondsBetween(NowTime, PrevClickTime) >= 500) then
			begin
				// Too much time has passed, definitely not a double-click
				// Clear selection if it was preserved for potential double-click
				// Check if current selection matches what we would have preserved
				if (Selection.Left = PrevClickChan) and (Selection.Right = PrevClickChan) and
				   (Selection.Top = 0) and (Selection.Bottom = 63) then
				begin
					// This was a preserved selection, clear it now
					Selection := Types.Rect(-1, -1, -1, -1);
					Paint;
				end;
			end;
		end;
		
		MouseDragging := False;
		// Disable mouse capture
		if Screen <> nil then
			Screen.MouseInfo.Capturing := False;
		Result := True;
	end;
end;

procedure sPut(var S: AnsiString; Index: Byte; const D: AnsiString); inline;
var
	i: Integer;
begin
	for i := 1 to Min(Length(S), Length(D)) do
		S[Index+i-1] := D[i];
end;

// not fixed for height <> 32!
procedure TPatternEditor.Paint;
const
	WIDTH_ROWNUM = 3;
	SEMP1 = CHR_PERIOD + '00';
	SEMP2 = CHR_PERIOD + CHR_2PERIODS;
var
	i, c, CX, CY, row, fg, bg: Integer;
	s: AnsiString;
	Note: PNote;
	FirstInvalidNote: Byte;
	ScrPos: Integer;
//	UseVolumeColumn: Boolean;
	Text_Vals: PTextVals;
begin
	if (Drawing) or (not Assigned(Module)) then Exit;

//	UseVolumeColumn := Options.Display.ShowVolumeColumn;

	if Options.Tracker.NoteB3Warning then
		FirstInvalidNote := 36
	else
		FirstInvalidNote := 37;

	Drawing := True;
	Console.BeginUpdate;

	{$IFDEF TIMING}
	Time.Start;
	{$ENDIF}

	if (FollowPlayback) and {(Module.PlayMode = PLAY_SONG) and }(Options.Tracker.CenterPlayback) then
		ScrPos := Module.PlayPos.Row - 16
	else
	begin
		if ScrollPos > 32 then
			ScrollPos := 32;
		ScrPos := ScrollPos;
	end;

	if Options.Tracker.HexRows then
		Text_Vals := @HexVals
	else
		Text_Vals := @TextVals;

	for i := 0 to Height do
	begin
		row := ScrPos + i;
		if row = Module.PlayPos.Row then
		begin
			if Module.PlayPos.Pattern = CurrentPattern then
				c := COL_ROW_CURRENT
			else
				c := COL_ROW_CURRENTOTHER;
		end
		else
			c := COL_ROW;
		if (row < 0) or (row > 63) then
			Console.Write('  ', Rect.Left, Rect.Top + i, c)
		else
			Console.Write(Text_Vals[row], Rect.Left, Rect.Top + i, c);
	end;

	for c := 0 to AMOUNT_CHANNELS - 1 do
	for i := 0 to Height do
	begin
		row := ScrPos + i;
		CX := Rect.Left + WIDTH_ROWNUM + (c * PATTERN_CHAN_WIDTH);
		CY := Rect.Top + i;

		if (row < 0) or (row > 63) then
		begin
			Console.Write('... .. .. ...', CX, CY, ColorBack, ColorBack);
		end
		else
		begin
			s := '    '; // 4 spaces
			Note := @Module.Notes[CurrentPattern, c, row];
			if Note.Pitch = 0 then
				sPut(s, 1, CHR_3PERIODS)
			else
				sPut(s, 1, NoteText[Min(Note.Pitch, High(NoteText))]);

			if 	InRange(c,   Selection.Left, Selection.Right)  and
				InRange(row, Selection.Top,  Selection.Bottom) then
			begin
				if row mod 16 = 0 then
					bg := COL_HL_SEL_ROW	// highlight sel. rows bg
				else
				if row mod 4 = 0 then
					bg := COL_HL_SEL_BEAT	// highlight sel. beats bg
				else
					bg := COL_SEL_BG;		// normal sel. bg
				fg := COL_SEL_FG;			// selected text
			end
			else
			begin
				if row mod 16 = 0 then
					bg := COL_HL_ROW		// highlight rows bg 9
				else
				if row mod 4 = 0 then
					bg := COL_HL_BEAT		// highlight beats bg 9
				else
					bg := ColorBack;		// normal bg 8
				fg := ColorFore;			// normal text
			end;

			if Note.Pitch >= FirstInvalidNote then
				bg := COL_INVALID;

			Console.Write(s, CX, CY, fg, bg);

			if (Note.Sample = 0) then
				Console.Write(CHR_2PERIODS, CX + 4, CY, fg, bg)
			else
				Console.Write(TextVals[Note.Sample], CX + 4, CY, fg, bg);

			s[1] := ' ';
			s[4] := ' ';

			if {(UseVolumeColumn) and} (Note.Command = $C) then
			begin
				// volume column + empty effect column
				sPut(s, 2, TextVals[Note.Parameter]);
				Console.Write(s, CX + 6, CY, fg, bg);
				Console.Write(CHR_3PERIODS, CX + 10, CY, 15, bg);
			end
			else
			begin
				// empty volume column
				//if UseVolumeColumn then
				sPut(s, 2, CHR_2PERIODS);
				Console.Write(s, CX + 6, CY, fg, bg);

				if (Note.Command = 0) and (Note.Parameter = 0) then
				begin
					if Options.Tracker.ShowEmptyParamZeroes then
						Console.Write(SEMP1, CX + 10, CY, fg, bg)
					else
						Console.Write(SEMP2, CX + 10, CY, fg, bg);
				end
				else
					Console.Write(CmdChars[Note.Command+1] // strings start at [1]
						+ HexVals[Note.Parameter], CX + 10, CY, fg, bg);
			end;

		end;

	end;

	// paint edit cursor if editor is active
	if (Focused) and {(Module.PlayMode <> PLAY_SONG)} (not FollowPlayback) then
	begin
		row := Rect.Top + Cursor.Row - ScrPos;
		if (row >= Rect.Top) and (row < Rect.Bottom) then
			Console.SetColor(
				Cursor.X + Rect.Left + WIDTH_ROWNUM, row,
				COL_CUR_FG, COL_CUR_BG);
	end;

	Console.EndUpdate;
	Drawing := False;

	{$IFDEF TIMING}
	Time.Stop;
	Window.Caption := FloatToStr(Time.MillisecondsFloat);
	{$ENDIF}
end;

{ TClipPattern }

// Notes: array [0..AMOUNT_CHANNELS-1, 0..63] of TNote;
// Size:  TPoint;

// Schism clipboard format:
//
// Pasted Pattern - IT
// |G-521...... <- 1 channel
// |F-526...A05|B-517...D02|........T77|C#516...F02| <-- multiple channels
// |NNNss...Exx <- format for 1 channel

(*
procedure TClipPattern.FromClipboard;
begin

end;

procedure TClipPattern.ToClipboard;
var
	WasPZ: Boolean;
	patt, ch, row: Integer;
	Note: PNote;
	S: String;
begin
	WasPZ := Options.Tracker.ShowEmptyParamZeroes;

	Options.Tracker.ShowEmptyParamZeroes := False;

	S := '';

	for ch := 0 to Size.X do
	for row := 0 to Size.Y do
	begin
		Note := @Notes[ch, row];
		if (Note.Command <> 0) or (Note.Parameter <> 0) then
			Note.GetText;
		S := S + Note.CmdText + sLineBreak;
	end;

	ClipBoard.AsText := S;
	Options.Tracker.ShowEmptyParamZeroes := WasPZ;
end;
*)

end.
