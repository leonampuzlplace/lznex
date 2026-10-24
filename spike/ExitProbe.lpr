program ExitProbe;

{ Descobre como o FPC 3.2.2 propaga o codigo de saida: ExitCode funciona?
  Halt funciona? Rodar com MODE=exitcode ou MODE=halt. }

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
