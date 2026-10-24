program LzNexTests;

{ Suite FPCUnit do LzNex.

  Usa simpletestrunner, nao consoletestrunner: ele roda TUDO sempre e devolve
  exit code 0/1 puro. O consoletestrunner exige --all e usa bitmask (1=falha,
  2=erro), o que ja fez teste vermelho sair verde em CI alheio.

  Compilado no build mode Debug (-gh) e rodado com HEAPTRC=haltonnotreleased,
  este binario tambem e o gate de vazamento: qualquer bloco nao liberado
  derruba o processo. }

{$MODE DELPHI}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  SysUtils,
  simpletestrunner,
  Test.Helper,
  Test.Core,
  Test.Query,
  Test.Postgres,
  Test.Integration,    // pulados sem LZNEX_IT setado
  Test.Concurrency;    // idem

var
  App: TTestRunner;
begin
  App := TTestRunner.Create(nil);
  try
    App.Initialize;
    App.Title := 'LzNex';
    App.Run;
  finally
    App.Free;
  end;
  Flush(Output);   // stdout nao-tty e bufferizado
end.
