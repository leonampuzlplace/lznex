program ExitProbe;

{$MODE DELPHI}{$H+}

uses
  SysUtils;

var
  Mode: string;
begin
  Mode := GetEnvironmentVariable('MODE');
  Writeln('modo=', Mode);

  if Mode = 'exitcode' then
    ExitCode := 7
  else if Mode = 'halt' then
  begin
    Flush(Output);
    Halt(7);
  end
  else if Mode = 'exitcode-proc' then
    ExitCode := 7;

  Writeln('ExitCode no fim = ', ExitCode);
  Flush(Output);
end.
