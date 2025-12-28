unit Screen.Log;

interface

uses
	Classes, Types,
	TextMode, CWE.Core, CWE.Widgets.Text;

type
	TLogScreen = class(TCWEScreen)
	private
		LastLoggedEmpty: Boolean;
	public
		Memo:		TCWEMemo;

		procedure	Log(const Msg: AnsiString);

		constructor	Create(var Con: TConsole; const sCaption, sID: AnsiString); override;
	end;

var
	LogScreen: TLogScreen;


implementation

uses
	Layout, ProTracker.Util, SysUtils, MainWindow;

procedure TLogScreen.Log(const Msg: AnsiString);

	function WrapText(const Text: AnsiString; MaxWidth: Integer): TStringList;
	var
		Remaining, Line: AnsiString;
		WrapPos, i: Integer;
	begin
		Result := TStringList.Create;
		Remaining := Text;
		
		while Remaining <> '' do
		begin
			if Length(Remaining) <= MaxWidth then
			begin
				Result.Add(Remaining);
				Remaining := '';
			end
			else
			begin
				// Try to break at a space
				WrapPos := MaxWidth;
				for i := MaxWidth downto 1 do
				begin
					if (i <= Length(Remaining)) and (Remaining[i] = ' ') then
					begin
						WrapPos := i;
						Break;
					end;
				end;
				// If no space found, break at MaxWidth
				if WrapPos > Length(Remaining) then
					WrapPos := MaxWidth;
				if WrapPos < 1 then
					WrapPos := 1;
				
				Line := Copy(Remaining, 1, WrapPos);
				Result.Add(TrimRight(Line));
				Remaining := TrimLeft(Copy(Remaining, WrapPos + 1, MaxInt));
			end;
		end;
		
		if Result.Count = 0 then
			Result.Add('');
	end;

var
	S, Timestamp, TimestampPrefix, Indent: AnsiString;
	ColorCode: Integer;
	WrappedLines, ContinuationLines: TStringList;
	TimestampWidth, FirstLineWidth, ContinuationWidth, i, j: Integer;
begin
	if Msg = '-' then
	begin
		if not LastLoggedEmpty then
			Memo.Add(StringOfChar(#205, Memo.Width+1), 15);
		LastLoggedEmpty := True;
	end
	else
	begin
		// Calculate timestamp width (format: "hh:nn:ss " = 9 characters)
		Timestamp := FormatDateTime('hh:nn:ss', Now) + ' ';
		TimestampWidth := Length(Timestamp);
		TimestampPrefix := ' ' + Timestamp;
		
		// Available width for first line: Memo.Width - timestamp width - 1 (for leading space)
		FirstLineWidth := Memo.Width - Length(TimestampPrefix);
		// Available width for continuation lines: Memo.Width - timestamp width (for indentation)
		ContinuationWidth := Memo.Width - TimestampWidth;
		// Indentation string for continuation lines
		Indent := StringOfChar(' ', TimestampWidth + 1);
		
		if FirstLineWidth < 1 then FirstLineWidth := 1;
		if ContinuationWidth < 1 then ContinuationWidth := 1;
		
		if Copy(Msg, 1, 1) = '$' then
		begin
			S := Copy(Msg, 3, Length(Msg));
			if not ((LastLoggedEmpty) and (S = '')) then
			begin
				ColorCode := StrToInt(Copy(Msg, 1, 2));
				
				// Replace line breaks with spaces for wrapping
				S := StringReplace(S, #13#10, ' ', [rfReplaceAll]);
				S := StringReplace(S, #10, ' ', [rfReplaceAll]);
				S := StringReplace(S, #13, ' ', [rfReplaceAll]);
				
				// Wrap the text
				WrappedLines := WrapText(S, FirstLineWidth);
				try
					// Add first line with timestamp
					if WrappedLines.Count > 0 then
						Memo.Add(TimestampPrefix + WrappedLines[0], ColorCode);
					
					// Add continuation lines with indentation
					for i := 1 to WrappedLines.Count - 1 do
					begin
						// Wrap continuation lines if needed
						if Length(WrappedLines[i]) > ContinuationWidth then
						begin
							// Further wrap continuation line using WrapText
							ContinuationLines := WrapText(WrappedLines[i], ContinuationWidth);
							try
								for j := 0 to ContinuationLines.Count - 1 do
									Memo.Add(Indent + ContinuationLines[j], ColorCode);
							finally
								ContinuationLines.Free;
							end;
						end
						else
							Memo.Add(Indent + WrappedLines[i], ColorCode);
					end;
				finally
					WrappedLines.Free;
				end;
			end;
		end
		else
		begin
			S := Msg;
			if not ((LastLoggedEmpty) and (S = '')) then
			begin
				// Replace line breaks with spaces for wrapping
				S := StringReplace(S, #13#10, ' ', [rfReplaceAll]);
				S := StringReplace(S, #10, ' ', [rfReplaceAll]);
				S := StringReplace(S, #13, ' ', [rfReplaceAll]);
				
				// Wrap the text
				WrappedLines := WrapText(S, FirstLineWidth);
				try
					// Add first line with timestamp
					if WrappedLines.Count > 0 then
						Memo.Add(TimestampPrefix + WrappedLines[0]);
					
					// Add continuation lines with indentation
					for i := 1 to WrappedLines.Count - 1 do
					begin
						// Wrap continuation lines if needed
						if Length(WrappedLines[i]) > ContinuationWidth then
						begin
							// Further wrap continuation line using WrapText
							ContinuationLines := WrapText(WrappedLines[i], ContinuationWidth);
							try
								for j := 0 to ContinuationLines.Count - 1 do
									Memo.Add(Indent + ContinuationLines[j]);
							finally
								ContinuationLines.Free;
							end;
						end
						else
							Memo.Add(Indent + WrappedLines[i]);
					end;
				finally
					WrappedLines.Free;
				end;
			end;
		end;
		
		LastLoggedEmpty := (S = '');
	end;

	if Active then
	begin
		Paint;
		Window.ProcessFrame;
	end;
end;

constructor TLogScreen.Create(var Con: TConsole; const sCaption, sID: AnsiString);
begin
	inherited;

	RegisterScreenLayout(Self, 'MessageLog');

	Memo := TCWEMemo.Create(Self, '', 'Message Log',
		Types.Rect(1, 1, Console.Width-2, Console.Height-1), True);
	RegisterLayoutControl(Memo, CTRLKIND_BOX, False, True, True);
	Memo.ColorFore := 12;

	ActiveControl := Memo;

	LoadLayout(Self);
	OnLog := Self.Log;
end;


end.
