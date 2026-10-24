program DiagPool;

{ Isola qual operacao nao devolve a conexao ao pool.

  Mede Pool.InUse depois de cada tipo de chamada, numa thread so, para separar
  o problema de concorrencia do problema de ciclo de vida. }

{$MODE DELPHI}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  SysUtils,
  LzNex,
  LzNex.Types,
  LzNex.Value,
  LzNex.Intf,
  LzNex.Client.MySQL;

const
  TBL = 'diag_pool';

var
  Db: ILzNex;

procedure Show(const AStep: string);
begin
  Writeln(Format('  %-52s InUse=%d Size=%d', [AStep, Db.Pool.InUse, Db.Pool.Size]));
  Flush(Output);
end;

procedure StepExecute;
begin
  Db.Execute('select 1', []);
  Show('depois de Execute (SQL cru)');
end;

procedure StepCount;
var
  N: Int64;
begin
  N := Db.Table(TBL).Count;
  Show('depois de Count = ' + IntToStr(N));
end;

procedure StepInsertGetId;
var
  Id: Int64;
begin
  Id := Db.Table(TBL).InsertGetId(Vals(['tag', 'x']));
  Show('depois de InsertGetId = ' + IntToStr(Id));
end;

procedure StepValue;
var
  V: TLzNexValue;
begin
  V := Db.Table(TBL).Where('id', 1).Value('tag');
  Show('depois de Value');
end;

procedure StepUpdate;
begin
  Db.Table(TBL).Where('id', 1).Update(Vals(['tag', 'y']));
  Show('depois de Update');
end;

procedure StepGetConsumido;
var
  R: ILzNexResult;
begin
  R := Db.Table(TBL).Get;
  while R.Next do ;
  R := nil;
  Show('depois de Get consumido e anulado');
end;

procedure StepTransacao;
var
  Trx: ILzNexTransaction;
begin
  Trx := Db.Transaction;
  Trx.Table(TBL).Insert(Vals(['tag', 'trx']));
  Trx.Rollback;
  Trx := nil;
  Show('depois de transacao com rollback');
end;

procedure StepLacoMisto(const AVoltas: Integer);
var
  I: Integer;
  Id: Int64;
begin
  for I := 1 to AVoltas do
  begin
    Id := Db.Table(TBL).InsertGetId(Vals(['tag', 'loop' + IntToStr(I)]));
    Db.Table(TBL).Where('id', Id).Value('tag');
    Db.Table(TBL).Where('id', Id).Update(Vals(['tag', 'z']));
    Db.Table(TBL).Count;
  end;
  Show('depois de laco misto x' + IntToStr(AVoltas) + ' DENTRO da rotina');
end;

// Reproduz o padrao do worker: transacao a cada volta, dentro de UMA rotina.
procedure StepLacoComTransacao(const AVoltas: Integer);
var
  I: Integer;
  Trx: ILzNexTransaction;
begin
  for I := 1 to AVoltas do
  begin
    Trx := Db.Transaction;
    try
      Trx.Table(TBL).Insert(Vals(['tag', 'trx' + IntToStr(I)]));
      Trx.Rollback;
    finally
      Trx := nil;
    end;
    Show('  volta ' + IntToStr(I) + ' (apos Trx := nil)');
  end;
end;

begin
  Db := Connect(NewConfig
    .Client('mysql')
    .Host('mysql').Port(3306).Database('lznex')
    .User('root').Password('secret')
    .LibraryLocation('/usr/lib/x86_64-linux-gnu/libmariadb.so.3')
    .Pool(1, 10));
  try
    Db.Execute('drop table if exists `' + TBL + '`', []);
    Db.Execute('create table `' + TBL + '` (id int unsigned not null ' +
      'auto_increment primary key, tag varchar(40) not null) engine=InnoDB', []);

    Writeln('=== uma operacao por rotina (cada rotina fecha o escopo) ===');
    Show('inicio');
    StepExecute;
    StepCount;
    StepInsertGetId;
    StepValue;
    StepUpdate;
    StepGetConsumido;
    StepTransacao;

    Writeln;
    Writeln('=== varias operacoes DENTRO de uma rotina so ===');
    Writeln('(no FPC 3.2.2 o temporario de interface so morre no fim da rotina)');
    StepLacoMisto(5);
    Show('depois que a rotina do laco retornou');

    Writeln;
    Writeln('=== laco de 30 voltas: o pool aguenta? ===');
    StepLacoMisto(30);
    Show('depois do laco de 30');

    Writeln;
    Writeln('=== laco COM TRANSACAO numa rotina so (padrao do worker) ===');
    StepLacoComTransacao(4);
    Show('depois que a rotina das transacoes retornou');

    Db.Execute('drop table if exists `' + TBL + '`', []);
  finally
    Db.Shutdown;
  end;
  Writeln;
  Writeln('fim');
  Flush(Output);
end.
