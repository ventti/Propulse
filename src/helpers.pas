unit Helpers;

interface

uses
	SysUtils, DateUtils;

// Helper functions for ISO8601 date conversion
function DateToISO8601(const ADate: TDateTime): String;
function ISO8601ToDate(const AString: String): TDateTime;

implementation

function DateToISO8601(const ADate: TDateTime): String;
begin
	Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', ADate);
end;

function ISO8601ToDate(const AString: String): TDateTime;
var
	Year, Month, Day, Hour, Min, Sec: Word;
begin
	// Simple ISO8601 parser: yyyy-mm-ddThh:nn:ssZ
	if Length(AString) >= 19 then
	begin
		Year := StrToIntDef(Copy(AString, 1, 4), 0);
		Month := StrToIntDef(Copy(AString, 6, 2), 0);
		Day := StrToIntDef(Copy(AString, 9, 2), 0);
		Hour := StrToIntDef(Copy(AString, 12, 2), 0);
		Min := StrToIntDef(Copy(AString, 15, 2), 0);
		Sec := StrToIntDef(Copy(AString, 18, 2), 0);
		Result := EncodeDateTime(Year, Month, Day, Hour, Min, Sec, 0);
	end
	else
		Result := Now;
end;

end.


