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
  Test.Paginate,
  Test.Sugar,
  Test.Postgres,
  Test.Firebird,
  Test.SQLite,
  Test.Features.MySQL,
  Test.Features.Postgres,
  Test.Features.SQLite,
  Test.Features.Firebird,
  Test.Schema.Inspect,
  Test.Literal,
  Test.Safety,
  Test.Integration,
  Test.It.Features,
  Test.It.Paginate,
  Test.It.Sugar,
  Test.It.Infra,
  Test.It.Lease,
  Test.It.Cursor,
  Test.It.Dialect,
  Test.It.Schema,
  Test.It.Migrator,
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
