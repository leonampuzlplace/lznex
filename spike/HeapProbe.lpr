program HeapProbe;

{ Sonda do heaptrc: isola se o relatorio sai e se o exit code reage a leak.
  Rodar com LEAK=1 para vazar de proposito. }

{$MODE DELPHI}{$H+}

uses
  SysUtils;

var
  P: Pointer;
begin
  // SetHeapTraceOutput — manda o dump do heaptrc para arquivo, nao para stderr.
  if GetEnvironmentVariable('HT_FILE') <> '' then
    SetHeapTraceOutput(GetEnvironmentVariable('HT_FILE'));

  if GetEnvironmentVariable('LEAK') = '1' then
  begin
    GetMem(P, 1234);   // vaza de proposito
    Writeln('vazei 1234 bytes de proposito');
  end
  else
    Writeln('sem vazamento proposital');

  Flush(Output);
end.
