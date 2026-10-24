program HeapProbe;

{$MODE DELPHI}{$H+}

uses
  SysUtils;

var
  P: Pointer;
begin

  if GetEnvironmentVariable('HT_FILE') <> '' then
    SetHeapTraceOutput(GetEnvironmentVariable('HT_FILE'));

  if GetEnvironmentVariable('LEAK') = '1' then
  begin
    GetMem(P, 1234);
    Writeln('vazei 1234 bytes de proposito');
  end
  else
    Writeln('sem vazamento proposital');

  Flush(Output);
end.
