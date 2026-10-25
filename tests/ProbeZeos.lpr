program ProbeZeos;

{$MODE DELPHI}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  SysUtils,
  Classes,
  ZDbcIntfs,
  ZDbcMySql,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Intf,
  LzNex.Client,
  LzNex.Result,
  LzNex.Connection,
  LzNex.Pool,
  LzNex.Transaction,
  LzNex.Exceptions;

type

  TProbeClient = class(TLzNexClientBase)
  protected
    function QuoteChar: string; override;
  public
    function DialectName: string; override;
    function ZeosProtocol: string; override;
    function DdlIsTransactional: Boolean; override;
    function NewCompiler: ILzNexCompiler; override;
    function NewSchemaCompiler: ILzNexSchemaCompiler; override;
  end;

  TProbeDb = class(TInterfacedObject, ILzNex)
  private
    FClient: ILzNexClient;
    FPool: ILzNexPool;
    function NotHere(const AWhat: string): ELzNex;
  public
    constructor Create(const AClient: ILzNexClient; const APool: ILzNexPool);
    function Table(const AName: string): ILzNexQuery;
    function From(const AName: string): ILzNexQuery;
    function Query: ILzNexQuery;
    function Raw(const ASQL: string; const AArgs: array of const): ILzNexRaw;
    function Schema: ILzNexSchema;
    function Transaction: ILzNexTransaction; overload;
    function Transaction(const AIsolation: TLzNexIsolation): ILzNexTransaction; overload;
    function Migrator: ILzNexMigrator;
    function Seeder: ILzNexSeeder;
    function Execute(const ASQL: string; const AArgs: array of const): Int64;
    function Fetch(const ASQL: string; const AArgs: array of const): ILzNexResult;
    function Client: ILzNexClient;
    function Config: ILzNexConfig;
    function Pool: ILzNexPool;
    function Connection: ILzNexConnection;
    function ReadConnection: ILzNexConnection;
    function Transact(const AWork: ILzNexWork;
      const AAttempts: Integer = 1): Integer;
    function IsTransaction: Boolean;
    procedure Shutdown;
  end;

  TProbeWorker = class(TThread)
  private
    FPool: ILzNexPool;
    FIters: Integer;
    FSeed: Integer;
    FOkCount: Integer;
    FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create(const APool: ILzNexPool; const AIters, ASeed: Integer);
    property OkCount: Integer read FOkCount;
    property Error: string read FError;
  end;

var
  GFailures: Integer = 0;

procedure Check(const AWhat: string; ACond: Boolean);
begin
  if ACond then
    Writeln('  ok   ', AWhat)
  else
  begin
    Writeln('  FALHA ', AWhat);
    Inc(GFailures);
    ExitCode := 1;
  end;
  Flush(Output);
end;

procedure Step(const ATitle: string);
begin
  Writeln;
  Writeln('--- ', ATitle);
  Flush(Output);
end;

procedure Note(const AText: string);
begin
  Writeln('  .    ', AText);
  Flush(Output);
end;

function Env(const AName, ADefault: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    Result := ADefault;
end;

function FL(const ASQL: string): TLzNexFragment;
begin
  Result := TLzNexFragment.Lit(ASQL);
end;

function FB(const ASQL: string; const AValues: array of TLzNexValue): TLzNexFragment;
var
  B: TLzNexBindings;
  I: Integer;
begin
  B := TLzNexBindings.Empty;
  for I := 0 to High(AValues) do
    B.Add(AValues[I]);
  Result := TLzNexFragment.Make(ASQL, B);
end;

function Utf8Sample: string;
begin

  Result := 'Leonam ' + #$E2#$9C#$85 + ' acentua' + #$C3#$A7 + #$C3#$A3 +
            'o ' + #$F0#$9F#$9A#$80;
end;

function SameBytes(const A, B: TBytes): Boolean;
var
  I: Integer;
begin
  Result := Length(A) = Length(B);
  if not Result then
    Exit;
  for I := 0 to High(A) do
    if A[I] <> B[I] then
      Exit(False);
end;

function BytesOf(const AItems: array of Byte): TBytes;
var
  I: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AItems));
  for I := 0 to High(AItems) do
    Result[I] := AItems[I];
end;

function KindName(const AKind: TLzNexValueKind): string;
begin
  case AKind of
    vkUnset: Result := 'vkUnset';
    vkNull: Result := 'vkNull';
    vkBoolean: Result := 'vkBoolean';
    vkInteger: Result := 'vkInteger';
    vkInt64: Result := 'vkInt64';
    vkFloat: Result := 'vkFloat';
    vkCurrency: Result := 'vkCurrency';
    vkString: Result := 'vkString';
    vkBytes: Result := 'vkBytes';
    vkDate: Result := 'vkDate';
    vkTime: Result := 'vkTime';
    vkDateTime: Result := 'vkDateTime';
  else
    Result := 'outro';
  end;
end;

function CountRows(const AConn: ILzNexConnection; const ATable: string): Int64;
var
  R: ILzNexResult;
begin
  Result := -1;
  R := AConn.Query(FL('select count(*) as n from ' + ATable));
  if R.Next then
    Result := R.Field('n').AsInt64;
  R.Close;
end;

function TProbeClient.QuoteChar: string;
begin
  Result := '`';
end;

function TProbeClient.DialectName: string;
begin
  Result := 'mysql';
end;

function TProbeClient.ZeosProtocol: string;
begin
  Result := 'mysql';
end;

function TProbeClient.DdlIsTransactional: Boolean;
begin
  Result := False;
end;

function TProbeClient.NewCompiler: ILzNexCompiler;
begin
  Result := nil;
end;

function TProbeClient.NewSchemaCompiler: ILzNexSchemaCompiler;
begin
  Result := nil;
end;

constructor TProbeDb.Create(const AClient: ILzNexClient; const APool: ILzNexPool);
begin
  inherited Create;
  FClient := AClient;
  FPool := APool;
end;

function TProbeDb.NotHere(const AWhat: string): ELzNex;
begin
  Result := ELzNex.Create('A facade da sonda nao implementa ' + AWhat);
end;

function TProbeDb.Table(const AName: string): ILzNexQuery;
begin
  raise NotHere('Table');
end;

function TProbeDb.From(const AName: string): ILzNexQuery;
begin
  raise NotHere('From');
end;

function TProbeDb.Query: ILzNexQuery;
begin
  raise NotHere('Query');
end;

function TProbeDb.Raw(const ASQL: string; const AArgs: array of const): ILzNexRaw;
begin
  raise NotHere('Raw');
end;

function TProbeDb.Schema: ILzNexSchema;
begin
  raise NotHere('Schema');
end;

function TProbeDb.Transaction: ILzNexTransaction;
begin
  Result := NewTransaction(Self as ILzNex, FPool.Acquire, ilDefault);
end;

function TProbeDb.Transaction(const AIsolation: TLzNexIsolation): ILzNexTransaction;
begin
  Result := NewTransaction(Self as ILzNex, FPool.Acquire, AIsolation);
end;

function TProbeDb.Migrator: ILzNexMigrator;
begin
  raise NotHere('Migrator');
end;

function TProbeDb.Seeder: ILzNexSeeder;
begin
  raise NotHere('Seeder');
end;

function TProbeDb.Execute(const ASQL: string; const AArgs: array of const): Int64;
begin
  raise NotHere('Execute');
end;

function TProbeDb.Fetch(const ASQL: string; const AArgs: array of const): ILzNexResult;
begin
  raise NotHere('Fetch');
end;

function TProbeDb.Client: ILzNexClient;
begin
  Result := FClient;
end;

function TProbeDb.Config: ILzNexConfig;
begin
  Result := nil;
end;

function TProbeDb.Pool: ILzNexPool;
begin
  Result := FPool;
end;

function TProbeDb.Connection: ILzNexConnection;
begin
  Result := FPool.Acquire;
end;

function TProbeDb.ReadConnection: ILzNexConnection;
begin
  Result := FPool.Acquire;
end;

function TProbeDb.Transact(const AWork: ILzNexWork;
  const AAttempts: Integer): Integer;
begin
  Result := 0;
  raise NotHere('Transact');
end;

function TProbeDb.IsTransaction: Boolean;
begin
  Result := False;
end;

procedure TProbeDb.Shutdown;
begin
  if FPool <> nil then
    FPool.Shutdown;
end;

constructor TProbeWorker.Create(const APool: ILzNexPool; const AIters, ASeed: Integer);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FPool := APool;
  FIters := AIters;
  FSeed := ASeed;
  FOkCount := 0;
  FError := '';
end;

procedure TProbeWorker.Execute;
var
  I, Expected: Integer;
  Conn: ILzNexConnection;
  R: ILzNexResult;
  Got: Int64;
begin
  try
    for I := 1 to FIters do
    begin
      Expected := FSeed * 1000 + I;
      Conn := FPool.Acquire;
      try
        R := Conn.Query(FB('select ? as n, connection_id() as cid',
          [TLzNexValue.FromInteger(Expected)]));
        try
          if not R.Next then
            raise ELzNex.Create('query sem linha');
          Got := R.Field('n').AsInt64;
          if Got <> Expected then
            raise ELzNex.CreateFmt(
              'bind embaralhado entre threads: esperava %d, veio %d',
              [Expected, Got]);
        finally
          R := nil;
        end;
        Inc(FOkCount);
      finally
        Conn := nil;
      end;
    end;
  except
    on E: Exception do
      FError := E.ClassName + ': ' + E.Message;
  end;
end;

const
  DDL_TYPES =
    'create table probe_types (' +
    '  id int unsigned not null auto_increment primary key,' +
    '  c_null varchar(20) null,' +
    '  c_int int not null,' +
    '  c_big bigint not null,' +
    '  c_float double not null,' +
    '  c_money decimal(18,4) not null,' +
    '  c_bool tinyint(1) not null,' +
    '  c_bit bit(1) not null,' +
    '  c_text varchar(200) not null,' +
    '  c_date date not null,' +
    '  c_time time not null,' +
    '  c_dt datetime not null,' +
    '  c_bytes varbinary(64) not null' +
    ') engine=InnoDB default charset=utf8mb4';

  INS_TYPES =
    'insert into probe_types' +
    ' (c_null, c_int, c_big, c_float, c_money, c_bool, c_bit, c_text, c_date,' +
    '  c_time, c_dt, c_bytes)' +
    ' values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';

  SEL_TYPES =
    'select c_null, c_int, c_big, c_float, c_money, c_bool, c_bit, c_text,' +
    '       c_date, c_time, c_dt, c_bytes from probe_types where id = ?';

var
  GClient: ILzNexClient;
  GParams: TLzNexConnectionParams;

function OpenDirect(out AObj: TLzNexConnection): ILzNexConnection;
var
  Z: IZConnection;
begin
  Z := DriverManager.GetConnection(GParams.BuildURL);
  Z.Open;
  AObj := TLzNexConnection.Create(GClient, Z);
  Result := AObj as ILzNexConnection;
end;

procedure TestTypesRoundTrip(const AConn: ILzNexConnection);
var
  Vals_: TLzNexValues;
  Affected, NewId: Int64;
  R: ILzNexResult;
  Row: ILzNexRow;
  SrcBytes: TBytes;
  SrcDate, SrcTime, SrcDt: TDateTime;
  SrcText: string;
begin
  AConn.ExecuteScript('drop table if exists probe_types');
  AConn.ExecuteScript(DDL_TYPES);
  Check('DDL criou probe_types', True);

  SrcBytes := BytesOf([0, 1, 2, 250, 255, 65, 13, 10]);
  SrcDate := EncodeDate(2024, 2, 29);
  SrcTime := EncodeTime(23, 59, 58, 0);
  SrcDt := EncodeDate(2031, 12, 25) + EncodeTime(13, 45, 7, 0);
  SrcText := Utf8Sample;

  Vals_ := nil;
  SetLength(Vals_, 12);
  Vals_[0] := TLzNexValue.Null;
  Vals_[1] := TLzNexValue.FromInteger(42);
  Vals_[2] := TLzNexValue.FromInt64(9007199254740993);
  Vals_[3] := TLzNexValue.FromFloat(1234.5);
  Vals_[4] := TLzNexValue.FromCurrency(1234.5678);
  Vals_[5] := TLzNexValue.FromBoolean(True);
  Vals_[6] := TLzNexValue.FromBoolean(True);
  Vals_[7] := TLzNexValue.FromString(SrcText);
  Vals_[8] := TLzNexValue.FromDate(SrcDate);
  Vals_[9] := TLzNexValue.FromTime(SrcTime);
  Vals_[10] := TLzNexValue.FromDateTime(SrcDt);
  Vals_[11] := TLzNexValue.FromBytes(SrcBytes);

  Affected := AConn.Execute(FB(INS_TYPES, Vals_));
  Check('insert com 12 binds afetou 1 linha', Affected = 1);

  NewId := AConn.LastInsertId;
  Check('LastInsertId devolveu 1', NewId = 1);

  R := AConn.Query(FB(SEL_TYPES, [TLzNexValue.FromInt64(NewId)]));
  try
    Check('select devolveu linha', R.Next);
    Check('12 colunas no resultado', R.FieldCount = 12);

    Note('tags lidas do metadata: c_int=' + KindName(R.Field('c_int').Kind) +
         ' c_money=' + KindName(R.Field('c_money').Kind) +
         ' c_bool(tinyint(1))=' + KindName(R.Field('c_bool').Kind) +
         ' c_bit(bit(1))=' + KindName(R.Field('c_bit').Kind) +
         ' c_date=' + KindName(R.Field('c_date').Kind) +
         ' c_time=' + KindName(R.Field('c_time').Kind) +
         ' c_dt=' + KindName(R.Field('c_dt').Kind) +
         ' c_bytes=' + KindName(R.Field('c_bytes').Kind));

    Check('NULL voltou como vkNull', R.Field('c_null').Kind = vkNull);
    Check('NULL responde IsNull', R.Field('c_null').IsNull);

    Check('int: valor', R.Field('c_int').AsInt64 = 42);
    Check('int: tag vkInt64', R.Field('c_int').Kind = vkInt64);

    Check('int64 grande sobreviveu exato',
      R.Field('c_big').AsInt64 = 9007199254740993);

    Check('float: valor', Abs(R.Field('c_float').AsFloat - 1234.5) < 1E-9);
    Check('float: tag vkFloat', R.Field('c_float').Kind = vkFloat);

    Check('currency: valor exato', R.Field('c_money').AsCurrency = 1234.5678);
    Check('currency: tag vkCurrency', R.Field('c_money').Kind = vkCurrency);

    Check('boolean em tinyint(1): True de volta', R.Field('c_bool').AsBoolean);
    Check('boolean em bit(1): True de volta', R.Field('c_bit').AsBoolean);
    Check('bit(1) chega com tag vkBoolean', R.Field('c_bit').Kind = vkBoolean);

    Check('string com acento e emoji: round-trip exato',
      R.Field('c_text').AsString = SrcText);
    Check('string: tag vkString', R.Field('c_text').Kind = vkString);

    Check('date: tag vkDate', R.Field('c_date').Kind = vkDate);
    Check('date: valor',
      FormatDateTime('yyyy-mm-dd', R.Field('c_date').AsDateTime) = '2024-02-29');

    Check('time: tag vkTime', R.Field('c_time').Kind = vkTime);
    Check('time: valor',
      FormatDateTime('hh:nn:ss', R.Field('c_time').AsDateTime) = '23:59:58');

    Check('datetime: tag vkDateTime', R.Field('c_dt').Kind = vkDateTime);
    Check('datetime: valor',
      FormatDateTime('yyyy-mm-dd hh:nn:ss', R.Field('c_dt').AsDateTime) =
      '2031-12-25 13:45:07');

    Check('bytes: tag vkBytes', R.Field('c_bytes').Kind = vkBytes);
    Check('bytes: round-trip exato', SameBytes(R.Field('c_bytes').AsBytes, SrcBytes));

    Check('FieldAt(1) = Field(c_int)', R.FieldAt(1).AsInt64 = 42);
    Check('FieldName(1) = c_int', R.FieldName(1) = 'c_int');

    Row := R.CurrentRow;
    Check('CurrentRow tem 12 colunas', Row.FieldCount = 12);
    Check('CurrentRow.Field por nome', Row.Field('c_int').AsInt64 = 42);
    Check('CurrentRow.FieldAt por indice', Row.FieldAt(1).AsInt64 = 42);
    Check('CurrentRow.Has', Row.Has('c_text') and (not Row.Has('nao_existe')));
    Check('CurrentRow.ToJSON tem o inteiro',
      Pos('"c_int":42', Row.ToJSON) > 0);
    Check('CurrentRow.ToJSON tem null',
      Pos('"c_null":null', Row.ToJSON) > 0);
    Check('CurrentRow.ToJSON tem a data ISO',
      Pos('"c_date":"2024-02-29"', Row.ToJSON) > 0);
    Note('json da linha: ' + Copy(Row.ToJSON, 1, 220));
  finally
    R := nil;
  end;

  R := AConn.Query(FB(SEL_TYPES, [TLzNexValue.FromInt64(NewId)]));
  try
    R.Next;
    try
      R.Field('coluna_que_nao_existe');
      Check('coluna inexistente levanta', False);
    except
      on E: ELzNexQuery do
        Check('coluna inexistente levanta ELzNexQuery',
          Pos('coluna_que_nao_existe', E.Message) > 0);
    end;
  finally
    R := nil;
  end;
end;

procedure TestCursor(const AConn: ILzNexConnection);
var
  R: ILzNexResult;
  Row1, Row2: ILzNexRow;
  Rows: TLzNexRowArray;
  JSON: string;
begin
  AConn.ExecuteScript('drop table if exists probe_cursor');
  AConn.ExecuteScript(
    'create table probe_cursor (id int not null primary key, tag varchar(40) not null)' +
    ' engine=InnoDB default charset=utf8mb4');
  AConn.Execute(FB('insert into probe_cursor (id, tag) values (?, ?), (?, ?), (?, ?)',
    [TLzNexValue.FromInteger(1), TLzNexValue.FromString('um'),
     TLzNexValue.FromInteger(2), TLzNexValue.FromString('dois'),
     TLzNexValue.FromInteger(3), TLzNexValue.FromString('tres')]));

  R := AConn.Query(FL('select id, tag from probe_cursor order by id'));
  try
    Check('FieldCount antes do primeiro Next', R.FieldCount = 2);
    Check('FieldName(0)', R.FieldName(0) = 'id');
    Check('FieldName(1)', R.FieldName(1) = 'tag');

    try
      R.Field('id');
      Check('ler sem Next levanta', False);
    except
      on E: ELzNexQuery do Check('ler sem Next levanta ELzNexQuery', True);
    end;

    Check('Next #1', R.Next);
    Row1 := R.CurrentRow;
    Check('linha 1 por nome', R.Field('tag').AsString = 'um');
    Check('linha 1 por indice', R.FieldAt(0).AsInt64 = 1);

    Check('Next #2', R.Next);
    Row2 := R.CurrentRow;
    Check('linha 2 por nome', R.Field('tag').AsString = 'dois');

    Check('CurrentRow sobreviveu ao avanco do cursor',
      (Row1.Field('tag').AsString = 'um') and (Row1.FieldAt(0).AsInt64 = 1));
    Check('as duas linhas materializadas sao independentes',
      Row2.Field('tag').AsString = 'dois');

    Check('Next #3', R.Next);
    Check('linha 3', R.Field('tag').AsString = 'tres');
    Check('Next no fim devolve False', not R.Next);
  finally
    R := nil;
  end;

  R := AConn.Query(FL('select id, tag from probe_cursor order by id'));
  Rows := R.ToRows;
  Check('ToRows trouxe 3 linhas', Length(Rows) = 3);
  Check('ToRows preservou a ordem',
    (Rows[0].Field('id').AsInt64 = 1) and (Rows[2].Field('tag').AsString = 'tres'));
  Rows := nil;
  R := nil;

  R := AConn.Query(FL('select id, tag from probe_cursor order by id'));
  Check('Next antes de ToRows', R.Next);
  Rows := R.ToRows;
  Check('ToRows inclui a linha corrente', Length(Rows) = 3);
  Rows := nil;
  R := nil;

  R := AConn.Query(FL('select id, tag from probe_cursor order by id'));
  JSON := R.ToJSON;
  R := nil;
  Note('json do resultado: ' + JSON);
  Check('ToJSON e um array', (Copy(JSON, 1, 1) = '[') and (Copy(JSON, Length(JSON), 1) = ']'));
  Check('ToJSON tem as 3 linhas',
    (Pos('"tag":"um"', JSON) > 0) and (Pos('"tag":"dois"', JSON) > 0) and
    (Pos('"tag":"tres"', JSON) > 0));

  AConn.Execute(FB('insert into probe_cursor (id, tag) values (?, ?)',
    [TLzNexValue.FromInteger(9),
     TLzNexValue.FromString('a"b\c' + #10 + #9 + 'd')]));
  R := AConn.Query(FL('select tag from probe_cursor where id = 9'));
  JSON := R.ToJSON;
  R := nil;
  Check('ToJSON escapou aspas, barra e controle',
    Pos('a\"b\\c\n\td', JSON) > 0);
  Note('json com escape: ' + JSON);

  R := AConn.Query(FL('select 1 as n'));
  R.Close;
  Check('Next depois de Close devolve False', not R.Next);
  R := nil;
end;

procedure TestTransaction(const ADb: ILzNex; const AConn: ILzNexConnection);
var
  Trx, Sp: ILzNexTransaction;
  Before: Int64;
begin
  AConn.ExecuteScript('drop table if exists probe_trx');
  AConn.ExecuteScript(
    'create table probe_trx (tag varchar(40) not null) engine=InnoDB' +
    ' default charset=utf8mb4');

  Trx := NewTransaction(ADb, AConn, ilDefault);
  Check('transacao raiz no nivel 1', Trx.Level = 1);
  Check('nao completada ao abrir', not Trx.IsCompleted);
  Check('Connection e a conexao fixada', Trx.Connection = AConn);
  Check('IsTransaction', Trx.IsTransaction);
  Check('conexao sabe que esta em transacao', AConn.InTransaction);
  AConn.Execute(FB('insert into probe_trx (tag) values (?)',
    [TLzNexValue.FromString('commitado')]));
  Trx.Commit;
  Check('completada depois do commit', Trx.IsCompleted);
  Trx := nil;
  Check('commit persistiu', CountRows(AConn, 'probe_trx') = 1);
  Check('fora de transacao depois do commit', not AConn.InTransaction);

  Trx := NewTransaction(ADb, AConn, ilDefault);
  Trx.Commit;
  try
    Trx.Commit;
    Check('segundo commit levanta', False);
  except
    on E: ELzNexTransaction do Check('segundo commit levanta ELzNexTransaction', True);
  end;
  Trx := nil;

  Before := CountRows(AConn, 'probe_trx');
  Trx := NewTransaction(ADb, AConn, ilDefault);
  AConn.Execute(FB('insert into probe_trx (tag) values (?)',
    [TLzNexValue.FromString('descartado')]));
  Check('a linha existe dentro da transacao',
    CountRows(AConn, 'probe_trx') = Before + 1);
  Trx.Rollback;
  Trx := nil;
  Check('rollback desfez', CountRows(AConn, 'probe_trx') = Before);

  Trx := NewTransaction(ADb, AConn, ilDefault);
  AConn.Execute(FB('insert into probe_trx (tag) values (?)',
    [TLzNexValue.FromString('externo')]));
  Sp := Trx.Savepoint;
  Check('savepoint abriu no nivel 2', Sp.Level = 2);
  AConn.Execute(FB('insert into probe_trx (tag) values (?)',
    [TLzNexValue.FromString('interno')]));
  Check('as duas linhas existem antes do rollback do savepoint',
    CountRows(AConn, 'probe_trx') = Before + 2);
  Sp.Rollback;
  Sp := nil;
  Check('rollback do savepoint desfez SO o interno',
    CountRows(AConn, 'probe_trx') = Before + 1);
  Trx.Commit;
  Trx := nil;
  Check('o externo foi commitado',
    CountRows(AConn, 'probe_trx') = Before + 1);

  Before := CountRows(AConn, 'probe_trx');
  Trx := NewTransaction(ADb, AConn, ilDefault);
  Sp := Trx.Savepoint;
  AConn.Execute(FB('insert into probe_trx (tag) values (?)',
    [TLzNexValue.FromString('sp commitado')]));
  Sp.Commit;
  Sp := nil;
  Trx.Commit;
  Trx := nil;
  Check('commit do savepoint + commit da raiz persiste',
    CountRows(AConn, 'probe_trx') = Before + 1);

  Trx := NewTransaction(ADb, AConn, ilDefault);
  Trx.Rollback;
  try
    Sp := Trx.Savepoint;
    Check('Savepoint em transacao concluida levanta', False);
  except
    on E: ELzNexTransaction do
      Check('Savepoint em transacao concluida levanta ELzNexTransaction', True);
  end;
  Sp := nil;
  Trx := nil;
end;

procedure TrxWithoutCommit(const ADb: ILzNex; const AConn: ILzNexConnection);
var
  Trx: ILzNexTransaction;
begin
  Trx := NewTransaction(ADb, AConn, ilDefault);
  AConn.Execute(FB('insert into probe_trx (tag) values (?)',
    [TLzNexValue.FromString('fantasma')]));
end;

procedure NestedTrxWithoutCommit(const ADb: ILzNex; const AConn: ILzNexConnection);
var
  Trx, Sp: ILzNexTransaction;
begin
  Trx := NewTransaction(ADb, AConn, ilDefault);
  AConn.Execute(FB('insert into probe_trx (tag) values (?)',
    [TLzNexValue.FromString('fantasma externo')]));
  Sp := Trx.Savepoint;
  AConn.Execute(FB('insert into probe_trx (tag) values (?)',
    [TLzNexValue.FromString('fantasma interno')]));
end;

procedure TestTrxDestructorRollback(const ADb: ILzNex; const AConn: ILzNexConnection);
var
  Before: Int64;
begin
  Before := CountRows(AConn, 'probe_trx');

  TrxWithoutCommit(ADb, AConn);
  Check('destrutor sem commit fez rollback (dado NAO ficou)',
    CountRows(AConn, 'probe_trx') = Before);
  Check('conexao voltou a ficar fora de transacao', not AConn.InTransaction);

  NestedTrxWithoutCommit(ADb, AConn);
  Check('savepoint abandonado tambem foi desfeito',
    CountRows(AConn, 'probe_trx') = Before);
  Check('nivel de transacao zerado', AConn.TransactionLevel = 0);
end;

procedure TestStmtCache;
var
  Obj: TLzNexConnection;
  Conn: ILzNexConnection;
  I: Integer;
  R: ILzNexResult;
  Total: Int64;
begin
  Conn := OpenDirect(Obj);
  try
    Check('cache comeca vazio', Obj.CachedStatementCount = 0);

    try
      Conn.Execute(FL('isto nao e sql'));
      Check('SQL invalido levanta', False);
    except
      on E: ELzNexQuery do
        Check('SQL invalido levanta ELzNexQuery com o SQL anexado',
          Pos('isto nao e sql', E.SQL) > 0);
    end;
    Check('SQL invalido nao entrou no cache', Obj.CachedStatementCount = 0);

    Total := 0;
    for I := 1 to 300 do
    begin
      R := Conn.Query(FB('select ? as n', [TLzNexValue.FromInteger(I)]));
      if R.Next then
        Total := Total + R.Field('n').AsInt64;
      R := nil;
    end;
    Check('300 execucoes do mesmo SQL deram o resultado certo',
      Total = 300 * 301 div 2);
    Check('mesmo SQL ocupa UMA entrada no cache', Obj.CachedStatementCount = 1);

    for I := 1 to 200 do
    begin
      R := Conn.Query(FL('select ' + IntToStr(I) + ' as n'));
      R.Next;
      R := nil;
    end;
    Check('cache parou no teto de ' + IntToStr(LZNEX_STMT_CACHE_MAX),
      Obj.CachedStatementCount = LZNEX_STMT_CACHE_MAX);

    R := Conn.Query(FB('select ? as n', [TLzNexValue.FromInteger(7)]));
    Check('query funciona depois da rotacao do cache',
      R.Next and (R.Field('n').AsInt64 = 7));
    R := nil;
  finally
    Conn := nil;
  end;
end;

procedure TestPool;
var
  Pool: ILzNexPool;
  C1, C2: ILzNexConnection;
  I: Integer;
  R: ILzNexResult;
  Raised: Boolean;
  Msg: string;
begin
  Pool := NewPool(GClient, GParams, 1, 2, 200);
  try
    Check('pool aquecido com o min', Pool.Size = 1);
    Check('nada em uso no inicio', Pool.InUse = 0);

    C1 := Pool.Acquire;
    Check('Acquire marcou 1 em uso', Pool.InUse = 1);
    R := C1.Query(FL('select 1 as n'));
    Check('conexao do pool executa query', R.Next and (R.Field('n').AsInt64 = 1));
    R := nil;
    C1 := nil;
    Check('liberar a interface devolveu ao pool (RAII)', Pool.InUse = 0);
    Check('a conexao devolvida continua no pool', Pool.Size = 1);

    for I := 1 to 60 do
    begin
      C1 := Pool.Acquire;
      R := C1.Query(FL('select 1 as n'));
      R.Next;
      R := nil;
      C1 := nil;
    end;
    Check('60 ciclos de acquire/release: nada em uso no fim', Pool.InUse = 0);
    Check('60 ciclos de acquire/release: pool nao cresceu', Pool.Size = 1);

    C1 := Pool.Acquire;
    C2 := Pool.Acquire;
    Check('duas emprestadas = max', (Pool.InUse = 2) and (Pool.Size = 2));
    Raised := False;
    Msg := '';
    try
      Pool.Acquire;
    except
      on E: ELzNexPool do
      begin
        Raised := True;
        Msg := E.Message;
      end;
    end;
    Check('estourar o max com timeout levanta ELzNexPool', Raised);
    Check('a mensagem diz o tamanho e quantas estao em uso',
      (Pos('max 2', Msg) > 0) and (Pos('2 in use', Msg) > 0));
    Note('mensagem do pool: ' + Copy(Msg, 1, 160));

    C1 := nil;
    C2 := nil;
    Check('devolvidas as duas', Pool.InUse = 0);

    C1 := Pool.Acquire;
    C2 := C1;
    C1 := nil;

    Check('wrapper com duas referencias ainda nao devolveu', Pool.InUse = 1);
    C2 := nil;
    Check('devolveu quando a ultima referencia morreu', Pool.InUse = 0);

    C1 := Pool.Acquire;
    C1.ExecuteScript('drop table if exists probe_pool');
    C1.ExecuteScript(
      'create table probe_pool (tag varchar(20) not null) engine=InnoDB');
    C1.StartTransaction;
    C1.Execute(FB('insert into probe_pool (tag) values (?)',
      [TLzNexValue.FromString('vazado')]));
    C1 := nil;
    C1 := Pool.Acquire;
    Check('pool desfez a transacao abandonada na devolucao',
      (CountRows(C1, 'probe_pool') = 0) and (not C1.InTransaction));
    C1.ExecuteScript('drop table if exists probe_pool');
    C1 := nil;
  finally
    Pool.Shutdown;
    Pool := nil;
  end;

  Pool := NewPool(GClient, GParams, 1, 2, 50);
  Pool.Shutdown;
  Check('pool apos Shutdown tem tamanho zero', Pool.Size = 0);
  Raised := False;
  try
    Pool.Acquire;
  except
    on E: ELzNexPool do Raised := True;
  end;
  Check('Acquire depois de Shutdown levanta ELzNexPool', Raised);
  Pool := nil;
end;

procedure TestPoolThreads;
const
  THREADS = 6;
  ITERS = 40;
var
  Pool: ILzNexPool;
  Workers: array[0..THREADS - 1] of TProbeWorker;
  I, TotalOk: Integer;
  AllOk: Boolean;
  Errors: string;
begin

  for I := 0 to THREADS - 1 do
    Workers[I] := nil;

  Pool := NewPool(GClient, GParams, THREADS, THREADS, 5000);
  try
    Check('pool aquecido com ' + IntToStr(THREADS) + ' conexoes',
      Pool.Size = THREADS);

    for I := 0 to THREADS - 1 do
      Workers[I] := TProbeWorker.Create(Pool, ITERS, I + 1);
    for I := 0 to THREADS - 1 do
      Workers[I].Start;
    for I := 0 to THREADS - 1 do
      Workers[I].WaitFor;

    TotalOk := 0;
    AllOk := True;
    Errors := '';
    for I := 0 to THREADS - 1 do
    begin
      TotalOk := TotalOk + Workers[I].OkCount;
      if Workers[I].Error <> '' then
      begin
        AllOk := False;
        Errors := Errors + '[t' + IntToStr(I) + '] ' + Workers[I].Error + ' ';
      end;
    end;

    if not AllOk then
      Note('erros das threads: ' + Errors);
    Check('nenhuma thread falhou', AllOk);
    Check(IntToStr(THREADS) + ' threads x ' + IntToStr(ITERS) +
      ' queries completaram', TotalOk = THREADS * ITERS);
    Check('nada ficou emprestado no fim', Pool.InUse = 0);
    Check('pool nao passou do max', Pool.Size <= THREADS);
  finally

    for I := 0 to THREADS - 1 do
    begin
      Workers[I].Free;
      Workers[I] := nil;
    end;
    Pool.Shutdown;
    Pool := nil;
  end;
end;

procedure UseInExpression(const APool: ILzNexPool; out AInUseInside: Integer);
begin
  APool.Acquire.Query(FL('select 1 as n'));
  AInUseInside := APool.InUse;
end;

procedure QueryAndDropConnection(const APool: ILzNexPool; out AResult: ILzNexResult);
var
  C: ILzNexConnection;
begin
  C := APool.Acquire;
  AResult := C.Query(FL('select 7 as n'));
  C := nil;
end;

procedure TestTrxOverPool;
var
  Pool: ILzNexPool;
  Db: ILzNex;
  Trx: ILzNexTransaction;
  Conn, TConn: ILzNexConnection;
  Res: ILzNexResult;
  Before: Int64;
  Inside: Integer;
begin
  Pool := NewPool(GClient, GParams, 1, 2, 500);
  Db := TProbeDb.Create(GClient, Pool) as ILzNex;
  try
    Conn := Pool.Acquire;
    Conn.ExecuteScript('drop table if exists probe_trxpool');
    Conn.ExecuteScript(
      'create table probe_trxpool (tag varchar(20) not null) engine=InnoDB');
    Conn := nil;

    Check('pool livre antes da transacao', Pool.InUse = 0);
    Trx := Db.Transaction;
    Check('a transacao retem uma conexao do pool', Pool.InUse = 1);
    TConn := Trx.Connection;
    TConn.Execute(FB('insert into probe_trxpool (tag) values (?)',
      [TLzNexValue.FromString('a')]));
    TConn := nil;
    Trx.Commit;
    Trx := nil;
    Check('a transacao devolveu a conexao ao pool', Pool.InUse = 0);

    Conn := Pool.Acquire;
    Before := CountRows(Conn, 'probe_trxpool');
    Check('transacao sobre o pool commitou', Before = 1);
    Conn := nil;

    Trx := Db.Transaction;
    TConn := Trx.Connection;
    TConn.Execute(FB('insert into probe_trxpool (tag) values (?)',
      [TLzNexValue.FromString('b')]));
    TConn := nil;
    Trx := nil;
    Check('transacao abandonada sobre o pool: conexao devolvida',
      Pool.InUse = 0);
    Conn := Pool.Acquire;
    Check('transacao abandonada sobre o pool: dado NAO ficou',
      CountRows(Conn, 'probe_trxpool') = Before);
    Conn.ExecuteScript('drop table if exists probe_trxpool');
    Conn := nil;

    Inside := -1;
    UseInExpression(Pool, Inside);
    Check('Acquire solto em expressao ainda esta em uso dentro do escopo',
      Inside = 1);
    Check('Acquire solto em expressao e devolvido na saida do escopo',
      Pool.InUse = 0);

    QueryAndDropConnection(Pool, Res);
    Check('cursor segura o emprestimo depois de a conexao ser soltada',
      Pool.InUse = 1);
    Check('o cursor continua legivel', Res.Next and (Res.Field('n').AsInt64 = 7));
    Res := nil;
    Check('emprestimo volta ao pool quando o cursor morre', Pool.InUse = 0);
  finally
    Db := nil;
    Pool.Shutdown;
    Pool := nil;
  end;
end;

procedure TestErrorPaths;
var
  Conn: ILzNexConnection;
  Obj: TLzNexConnection;
  Pool: ILzNexPool;
  Trx: ILzNexTransaction;
  Bad: TLzNexConnectionParams;
  NotBindable: TLzNexValues;
  Raised: Boolean;
begin
  Conn := OpenDirect(Obj);
  try

    NotBindable := nil;
    SetLength(NotBindable, 1);
    NotBindable[0] := TLzNexValue.Identifier('id');
    try
      Conn.Execute(FB('select ? as n', NotBindable));
      Check('bind de identificador levanta', False);
    except
      on E: ELzNexQuery do
        Check('bind de identificador levanta ELzNexQuery',
          Pos('identifier', E.Message) > 0);
    end;

    Raised := False;
    try Conn.Execute(FL('')); except on E: ELzNexQuery do Raised := True; end;
    Check('Execute com SQL vazio levanta', Raised);
    Raised := False;
    try Conn.Query(FL('')); except on E: ELzNexQuery do Raised := True; end;
    Check('Query com SQL vazio levanta', Raised);
    Raised := False;
    try Conn.ExecuteScript('   '); except on E: ELzNexQuery do Raised := True; end;
    Check('ExecuteScript com SQL vazio levanta', Raised);

    Raised := False;
    try
      Conn.Query(FL('select * from tabela_que_nao_existe_mesmo'));
    except
      on E: ELzNexQuery do Raised := Pos('tabela_que_nao_existe_mesmo', E.SQL) > 0;
    end;
    Check('Query em tabela inexistente levanta ELzNexQuery com o SQL', Raised);
    Raised := False;
    try
      Conn.ExecuteScript('drop table tabela_que_nao_existe_mesmo');
    except
      on E: ELzNexQuery do Raised := True;
    end;
    Check('ExecuteScript invalido levanta ELzNexQuery', Raised);

    Raised := False;
    try Conn.Commit; except on E: ELzNexTransaction do Raised := True; end;
    Check('Commit fora de transacao levanta ELzNexTransaction', Raised);
    Raised := False;
    try Conn.Rollback; except on E: ELzNexTransaction do Raised := True; end;
    Check('Rollback fora de transacao levanta ELzNexTransaction', Raised);

    Conn.ExecuteScript('drop table if exists probe_err');
    Conn.ExecuteScript(
      'create table probe_err (tag varchar(10) not null) engine=InnoDB');
    Trx := NewTransaction(nil, Conn, ilDefault);
    Raised := False;
    try
      Conn.Execute(FB('insert into probe_err (tag) values (?)',
        [TLzNexValue.FromString('x')]));
      Conn.Execute(FL('insert into probe_err (nao_existe) values (1)'));
    except
      on E: ELzNexQuery do Raised := True;
    end;
    Trx := nil;
    Check('erro dentro da transacao levantou ELzNexQuery', Raised);
    Check('o destrutor desfez mesmo com erro no meio',
      CountRows(Conn, 'probe_err') = 0);
    Conn.ExecuteScript('drop table if exists probe_err');
  finally
    Conn := nil;
  end;

  Conn := OpenDirect(Obj);
  Conn.Close;
  Raised := False;
  try
    Trx := NewTransaction(nil, Conn, ilDefault);
  except
    on E: ELzNex do Raised := True;
  end;
  Trx := nil;
  Check('transacao sobre conexao fechada levanta', Raised);
  Conn := nil;

  Raised := False;
  try Pool := NewPool(GClient, GParams, 1, 0, 100);
  except on E: ELzNexConfig do Raised := True; end;
  Pool := nil;
  Check('pool com max 0 levanta ELzNexConfig', Raised);

  Raised := False;
  try Pool := NewPool(GClient, GParams, 5, 2, 100);
  except on E: ELzNexConfig do Raised := True; end;
  Pool := nil;
  Check('pool com min > max levanta ELzNexConfig', Raised);

  Bad := GParams;
  Bad.Password := 'senha-errada-de-proposito';
  Raised := False;
  try Pool := NewPool(GClient, Bad, 1, 2, 100);
  except on E: ELzNexConnection do Raised := True; end;
  Pool := nil;
  Check('pool com credencial invalida levanta ELzNexConnection no aquecimento',
    Raised);

  Pool := NewPool(GClient, Bad, 0, 1, 100);
  try
    Raised := False;
    try Pool.Acquire; except on E: ELzNexConnection do Raised := True; end;
    Check('Acquire com credencial invalida levanta ELzNexConnection', Raised);
    Check('a vaga reservada foi devolvida depois da falha',
      (Pool.InUse = 0) and (Pool.Size = 0));

    Raised := False;
    try Pool.Acquire; except on E: ELzNexConnection do Raised := True; end;
    Check('segunda tentativa falha pela conexao, nao por pool esgotado', Raised);
  finally
    Pool.Shutdown;
    Pool.Shutdown;
    Pool := nil;
  end;
  Check('Shutdown duas vezes nao levanta', True);
end;

procedure Cleanup(const AConn: ILzNexConnection);
begin
  AConn.ExecuteScript('drop table if exists probe_types');
  AConn.ExecuteScript('drop table if exists probe_cursor');
  AConn.ExecuteScript('drop table if exists probe_trx');
  AConn.ExecuteScript('drop table if exists probe_pool');
  AConn.ExecuteScript('drop table if exists probe_trxpool');
end;

var
  Conn: ILzNexConnection;
  ConnObj: TLzNexConnection;
  Db: ILzNex;
  Pool: ILzNexPool;
  R: ILzNexResult;
begin
  Writeln('=== sonda Zeos/DBC do LzNex ===');
  Writeln('FPC ', {$I %FPCVERSION%}, ' / ', {$I %FPCTARGETCPU%}, '-', {$I %FPCTARGETOS%});
  Flush(Output);

  GClient := TProbeClient.Create as ILzNexClient;

  GParams := TLzNexConnectionParams.Empty;
  GParams.Protocol := Env('DB_PROTOCOL', 'mysql');
  GParams.Host := Env('DB_HOST', 'mysql');
  GParams.Port := StrToIntDef(Env('DB_PORT', '3306'), 3306);
  GParams.Database := Env('DB_NAME', 'lznex');
  GParams.User := Env('DB_USER', 'root');
  GParams.Password := Env('DB_PASS', 'secret');

  GParams.LibLocation := Env('DB_LIB', '/usr/lib/x86_64-linux-gnu/libmariadb.so.3');
  GParams.Charset := Env('DB_CHARSET', 'utf8mb4');

  Step('1. conexao e metadados basicos');
  try
    Conn := OpenDirect(ConnObj);
  except
    on E: Exception do
    begin
      Writeln('  FALHA ao conectar: ', E.ClassName, ': ', E.Message);
      Flush(Output);
      Halt(1);
    end;
  end;
  Check('conexao aberta', not Conn.IsClosed);
  Check('Ping responde', Conn.Ping);
  Check('Native devolve o IZConnection', (Conn.Native as IZConnection) <> nil);
  Check('Client e o dialeto informado', Conn.Client.DialectName = 'mysql');
  Check('fora de transacao no inicio',
    (not Conn.InTransaction) and (Conn.TransactionLevel = 0));
  R := Conn.Query(FL('select version() as v, @@character_set_connection as cs'));
  if R.Next then
    Note('server ' + R.Field('v').AsString + ' / charset ' + R.Field('cs').AsString);
  R := nil;

  Step('2. DDL e round-trip de todos os tipos');
  TestTypesRoundTrip(Conn);

  Step('3. cursor, linha materializada e JSON');
  TestCursor(Conn);

  Step('4. cache de prepared statement');
  TestStmtCache;

  Step('5. transacao: commit, rollback e savepoint');
  Pool := NewPool(GClient, GParams, 1, 2, 500);
  Db := TProbeDb.Create(GClient, Pool) as ILzNex;
  TestTransaction(Db, Conn);

  Step('6. transacao sem commit: rollback no destrutor');
  TestTrxDestructorRollback(Db, Conn);
  Db := nil;
  Pool.Shutdown;
  Pool := nil;

  Step('7. pool: RAII, teto, timeout e shutdown');
  TestPool;

  Step('8. pool com varias threads');
  TestPoolThreads;

  Step('9. transacao em cima do pool');
  TestTrxOverPool;

  Step('10. caminhos de erro (onde orfao vazaria)');
  TestErrorPaths;

  Step('11. limpeza e fechamento');
  Cleanup(Conn);
  Conn.Close;
  Check('IsClosed depois de Close', Conn.IsClosed);
  Check('Ping em conexao fechada devolve False', not Conn.Ping);
  Conn := nil;
  ConnObj := nil;
  GClient := nil;

  Writeln;
  if GFailures = 0 then
    Writeln('=== sonda Zeos OK ===')
  else
    Writeln('=== sonda Zeos COM ', GFailures, ' FALHA(S) ===');
  Flush(Output);
end.
