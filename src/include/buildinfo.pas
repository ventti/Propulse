unit BuildInfo;

interface

const
	CompileDate = {$I %DATE%};
	CompileTime = {$I %TIME%};
	GitDescribe = {$I gitdescribe.inc};

var
	Build: record
		CompileDate: String;
		CompileTime: String;
		GitDescribe: String;
	end;

implementation

uses
	SysUtils, StrUtils;

initialization

	Build.CompileDate := Trim(ReplaceStr(CompileDate, '/', '-'));
	Build.CompileTime := Trim(CompileTime);
	Build.GitDescribe := GitDescribe;

end.

