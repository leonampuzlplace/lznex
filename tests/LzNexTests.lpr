program LzNexTests;

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
  Test.Integration,
  Test.Concurrency;

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
  Flush(Output);
end.
