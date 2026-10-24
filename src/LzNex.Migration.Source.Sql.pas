unit LzNex.Migration.Source.Sql;

{ Fonte de migrations em arquivo .sql.

  Convencao de nome, igual a do CLI do knex com a extensao desdobrada:
    <id>_<descricao>.up.sql     -- obrigatorio
    <id>_<descricao>.down.sql   -- opcional

  Sem o .down.sql a migration e irreversivel: ela aplica normalmente e o Down
  levanta dizendo que nao existe volta. Isso e melhor que um down vazio, que
  daria rollback "com sucesso" sem desfazer nada.

  SPLITTER: um arquivo pode ter varios comandos separados por ';'. O scanner
  ignora ';' dentro de literal ('...', "...", `...`) e de comentario (--, #,
  /* */), o que cobre o caso normal de DDL/DML. O que ele NAO cobre e corpo de
  procedure/trigger/function, onde o ';' interno e parte do codigo: para esses,
  ponha um comentario `-- lznex:nosplit` no arquivo e ele vai inteiro, como um
  unico comando. }

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  Classes,
  LzNex.Types,
  LzNex.Value,
  LzNex.Exceptions,
  LzNex.Intf,
  LzNex.Migration;

const
  LZNEX_SOURCE_SQL = 'sql';
  LZNEX_SQL_UP_SUFFIX   = '.up.sql';
  LZNEX_SQL_DOWN_SUFFIX = '.down.sql';
  // Marca que desliga o split no arquivo (procedure, trigger, function).
  LZNEX_SQL_NOSPLIT = 'lznex:nosplit';

type
  TLzNexSqlMigration = class(TInterfacedObject, ILzNexMigration)
  private
    FId: string;
    FName: string;
    FUpPath: string;
    FDownPath: string;
    procedure RunFile(const ADb: ILzNex; const APath: string);
  public
    constructor Create(const AId, AName, AUpPath, ADownPath: string);

    function Id: string;
    function Name: string;
    function UseTransaction: Boolean;
    procedure Up(const ADb: ILzNex);
    procedure Down(const ADb: ILzNex);

    // Caminhos resolvidos. DownPath vazio = migration irreversivel.
    function UpPath: string;
    function DownPath: string;
    function IsReversible: Boolean;
  end;

  TLzNexSqlMigrationSource = class(TInterfacedObject, ILzNexMigrationSource)
  private
    FDir: string;
    FItems: TLzNexMigrationArray;
    FLoaded: Boolean;
    FOptional: Boolean;
    procedure Load;
  public
    constructor Create(const ADir: string; const AOptional: Boolean = False);
    // Diretorio ausente e erro: a fonte foi pedida de proposito.
    class function New(const ADir: string): ILzNexMigrationSource;
    // Diretorio ausente devolve lista vazia. E o que a facade usa ao registrar
    // a fonte .sql automaticamente: projeto que so tem migration em Pascal nao
    // pode quebrar por nao ter o diretorio.
    class function NewOptional(const ADir: string): ILzNexMigrationSource;

    function All: TLzNexMigrationArray;
    function SourceName: string;

    // O diretorio varrido.
    function Directory: string;
    // Descarta o cache; a proxima chamada a All le o diretorio de novo.
    procedure Refresh;
  end;

// Quebra um script em comandos. Ignora ';' dentro de literal e de comentario.
// Comando so com espaco/comentario e descartado.
function SplitSqlStatements(const ASQL: string): TLzNexStringArray;

// Le o arquivo como texto, descartando BOM UTF-8.
function ReadSqlFile(const APath: string): string;

implementation

{ ------------------------------------------------------------------
  Splitter
  ------------------------------------------------------------------ }

function SplitSqlStatements(const ASQL: string): TLzNexStringArray;
var
  I, Len, Start, N: Integer;
  C, Q: Char;
  InLiteral, InLine, InBlock, HasContent: Boolean;
  Piece: string;

  procedure Push(const AText: string);
  begin
    Piece := Trim(AText);
    if Piece = '' then
      Exit;
    if N >= Length(Result) then
      SetLength(Result, Length(Result) * 2);
    Result[N] := Piece;
    Inc(N);
  end;

begin
  Result := nil;
  N := 0;
  Len := Length(ASQL);
  if Trim(ASQL) = '' then
    Exit;

  SetLength(Result, 8);

  { Arquivo marcado: vai inteiro, o ';' interno e do codigo do usuario. }
  if Pos(LZNEX_SQL_NOSPLIT, LowerCase(ASQL)) > 0 then
  begin
    Push(ASQL);
    SetLength(Result, N);
    Exit;
  end;

  Start := 1;
  Q := #0;
  InLiteral := False;
  InLine := False;
  InBlock := False;
  HasContent := False;

  I := 1;
  while I <= Len do
  begin
    C := ASQL[I];

    if InLine then
    begin
      if C = #10 then
        InLine := False;
      Inc(I);
      Continue;
    end;

    if InBlock then
    begin
      if (C = '*') and (I < Len) and (ASQL[I + 1] = '/') then
      begin
        InBlock := False;
        Inc(I, 2);
        Continue;
      end;
      Inc(I);
      Continue;
    end;

    if InLiteral then
    begin
      { Barra invertida escapa o proximo char (default do MySQL). }
      if (C = '\') and (I < Len) then
      begin
        Inc(I, 2);
        Continue;
      end;
      if C = Q then
      begin
        { Delimitador dobrado e o delimitador literal, nao o fim. }
        if (I < Len) and (ASQL[I + 1] = Q) then
        begin
          Inc(I, 2);
          Continue;
        end;
        InLiteral := False;
        Inc(I);
        Continue;
      end;
      Inc(I);
      Continue;
    end;

    if (C = '-') and (I < Len) and (ASQL[I + 1] = '-') then
    begin
      InLine := True;
      Inc(I, 2);
      Continue;
    end;

    if C = '#' then
    begin
      InLine := True;
      Inc(I);
      Continue;
    end;

    if (C = '/') and (I < Len) and (ASQL[I + 1] = '*') then
    begin
      InBlock := True;
      Inc(I, 2);
      Continue;
    end;

    if (C = '''') or (C = '"') or (C = '`') then
    begin
      InLiteral := True;
      Q := C;
      HasContent := True;
      Inc(I);
      Continue;
    end;

    if C = ';' then
    begin
      if HasContent then
        Push(Copy(ASQL, Start, I - Start));
      Start := I + 1;
      HasContent := False;
      Inc(I);
      Continue;
    end;

    if not ((C = ' ') or (C = #9) or (C = #10) or (C = #13)) then
      HasContent := True;
    Inc(I);
  end;

  if InLiteral then
    raise ELzNexMigration.Create(
      'SQL script ends with an unclosed literal (delimiter ' + Q +
      ' without a pair). There is no way to tell where a statement ends, ' +
      'so nothing was executed.');
  if InBlock then
    raise ELzNexMigration.Create(
      'SQL script ends with an unclosed /* ... */ comment.');

  if HasContent then
    Push(Copy(ASQL, Start, Len - Start + 1));

  SetLength(Result, N);
end;

function ReadSqlFile(const APath: string): string;
var
  Stream: TFileStream;
  Buf: TBytes;
  Size: Integer;
begin
  Result := '';
  Stream := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    Size := Stream.Size;
    if Size <= 0 then
      Exit;
    Buf := nil;
    SetLength(Buf, Size);
    Stream.ReadBuffer(Buf[0], Size);
  finally
    Stream.Free;
  end;
  SetLength(Result, Size);
  Move(Buf[0], Result[1], Size);
  { BOM UTF-8 na frente faria o primeiro comando comecar com lixo. }
  if (Length(Result) >= 3) and (Result[1] = #$EF) and (Result[2] = #$BB)
    and (Result[3] = #$BF) then
    Delete(Result, 1, 3);
end;

{ TLzNexSqlMigration }

constructor TLzNexSqlMigration.Create(const AId, AName, AUpPath,
  ADownPath: string);
begin
  inherited Create;
  FId := AId;
  FName := AName;
  FUpPath := AUpPath;
  FDownPath := ADownPath;
end;

function TLzNexSqlMigration.Id: string;
begin
  Result := FId;
end;

function TLzNexSqlMigration.Name: string;
begin
  Result := FName;
end;

function TLzNexSqlMigration.UseTransaction: Boolean;
begin
  Result := True;
end;

function TLzNexSqlMigration.UpPath: string;
begin
  Result := FUpPath;
end;

function TLzNexSqlMigration.DownPath: string;
begin
  Result := FDownPath;
end;

function TLzNexSqlMigration.IsReversible: Boolean;
begin
  Result := FDownPath <> '';
end;

procedure TLzNexSqlMigration.RunFile(const ADb: ILzNex; const APath: string);
var
  Statements: TLzNexStringArray;
  Conn: ILzNexConnection;
  I: Integer;
begin
  if not FileExists(APath) then
    raise ELzNexMigration.Create(
      'Migration file disappeared: ' + APath + '.');

  Statements := SplitSqlStatements(ReadSqlFile(APath));
  if Length(Statements) = 0 then
    raise ELzNexMigration.Create(
      'Migration file has no statement at all: ' + APath + '.');

  { Uma conexao para todos os comandos do arquivo: fora de transacao, cada
    chamada a ADb.Connection pode devolver uma conexao diferente do pool. }
  Conn := ADb.Connection;
  for I := 0 to High(Statements) do
    try
      Conn.ExecuteScript(Statements[I]);
    except
      on E: Exception do
        raise ELzNexMigration.CreateFmt(
          'Migration %s failed on statement %d of %d (%s):' + sLineBreak +
          '%s' + sLineBreak + 'SQL: %s',
          [FName, I + 1, Length(Statements), ExtractFileName(APath),
           E.Message, Statements[I]]);
    end;
end;

procedure TLzNexSqlMigration.Up(const ADb: ILzNex);
begin
  RunFile(ADb, FUpPath);
end;

procedure TLzNexSqlMigration.Down(const ADb: ILzNex);
begin
  if FDownPath = '' then
    raise ELzNexMigration.Create(
      'Migration ' + FName + ' is irreversible: there is no ' +
      ExtractFileName(ChangeFileExt(FUpPath, '')) + LZNEX_SQL_DOWN_SUFFIX +
      ' in the directory. Create the down file or undo it by hand.');
  RunFile(ADb, FDownPath);
end;

{ TLzNexSqlMigrationSource }

constructor TLzNexSqlMigrationSource.Create(const ADir: string;
  const AOptional: Boolean);
begin
  inherited Create;
  FDir := ExcludeTrailingPathDelimiter(ADir);
  FOptional := AOptional;
  FLoaded := False;
end;

class function TLzNexSqlMigrationSource.New(const ADir: string): ILzNexMigrationSource;
begin
  Result := TLzNexSqlMigrationSource.Create(ADir, False);
end;

class function TLzNexSqlMigrationSource.NewOptional(
  const ADir: string): ILzNexMigrationSource;
begin
  Result := TLzNexSqlMigrationSource.Create(ADir, True);
end;

function TLzNexSqlMigrationSource.Directory: string;
begin
  Result := FDir;
end;

procedure TLzNexSqlMigrationSource.Refresh;
begin
  FItems := nil;
  FLoaded := False;
end;

// True se ANome termina em ASuffix, sem distinguir caixa.
function HasSuffix(const AName, ASuffix: string): Boolean;
begin
  Result := (Length(AName) > Length(ASuffix)) and
    SameText(Copy(AName, Length(AName) - Length(ASuffix) + 1,
      Length(ASuffix)), ASuffix);
end;

procedure TLzNexSqlMigrationSource.Load;
var
  SR: TSearchRec;
  Base, Id, DownPath, Dir: string;
  Found: TLzNexStringArray;
  FoundCount, I, J, Slot: Integer;
  Item: ILzNexMigration;
begin
  if FLoaded then
    Exit;

  if not DirectoryExists(FDir) then
  begin
    if FOptional then
    begin
      FItems := nil;
      FLoaded := True;
      Exit;
    end;
    raise ELzNexMigration.Create(
      '.sql migrations directory does not exist: ' + FDir + '.');
  end;

  Dir := IncludeTrailingPathDelimiter(FDir);
  Found := nil;
  FoundCount := 0;
  SetLength(Found, 16);

  if FindFirst(Dir + '*', faAnyFile, SR) = 0 then
  try
    repeat
      if (SR.Attr and faDirectory) <> 0 then
        Continue;
      if not HasSuffix(SR.Name, LZNEX_SQL_UP_SUFFIX) then
        Continue;
      if FoundCount >= Length(Found) then
        SetLength(Found, Length(Found) * 2);
      Found[FoundCount] := SR.Name;
      Inc(FoundCount);
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
  SetLength(Found, FoundCount);

  FItems := nil;
  SetLength(FItems, FoundCount);

  for I := 0 to FoundCount - 1 do
  begin
    Base := Copy(Found[I], 1, Length(Found[I]) - Length(LZNEX_SQL_UP_SUFFIX));
    Id := MigrationIdOf(Base);
    if Trim(Id) = '' then
      raise ELzNexMigration.Create(
        'Migration name without id: ' + Found[I] + '. ' +
        'Expected "<id>_<description>' + LZNEX_SQL_UP_SUFFIX + '".');

    DownPath := Dir + Base + LZNEX_SQL_DOWN_SUFFIX;
    if not FileExists(DownPath) then
      DownPath := '';

    { Acha o lugar e barra duplicata ANTES de alocar: objeto criado e depois
      abandonado por uma excecao fica orfao, porque quem ia ser dono e a lista. }
    Slot := I;
    for J := 0 to I - 1 do
    begin
      if FItems[J].Id = Id then
        raise ELzNexMigration.Create(
          'Duplicate migration id in directory ' + FDir + ': "' + Id +
          '" appears in ' + FItems[J].Name + ' and in ' + Base + '.');
      if FItems[J].Id > Id then
      begin
        Slot := J;
        Break;
      end;
    end;

    Item := TLzNexSqlMigration.Create(Id, Base, Dir + Found[I], DownPath);
    for J := I downto Slot + 1 do
      FItems[J] := FItems[J - 1];
    FItems[Slot] := Item;
  end;

  FLoaded := True;
end;

function TLzNexSqlMigrationSource.All: TLzNexMigrationArray;
var
  I: Integer;
begin
  Load;
  Result := nil;
  SetLength(Result, Length(FItems));
  for I := 0 to High(FItems) do
    Result[I] := FItems[I];
end;

function TLzNexSqlMigrationSource.SourceName: string;
begin
  Result := LZNEX_SOURCE_SQL;
end;

end.
