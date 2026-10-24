unit LzNex.Client;

{ TLzNexClientBase: dialeto base com defaults ANSI, e o registry de dialetos.

  Incluir um banco novo (PostgreSQL, Firebird) = descender desta classe e
  sobrescrever o que muda. O registry e populado no `initialization` de cada
  unit de dialeto, entao o core nao conhece nenhum banco especifico. }

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  Classes,
  Generics.Collections,
  LzNex.Types,
  LzNex.Value,
  LzNex.Bindings,
  LzNex.Fragment,
  LzNex.Ast,
  LzNex.Intf,
  LzNex.Exceptions;

type
  TLzNexClientBase = class;
  TLzNexClientClass = class of TLzNexClientBase;

  // Dialeto base. Defaults ANSI: identificador entre aspas
  // duplas, placeholder '?', sem RETURNING.
  TLzNexClientBase = class(TInterfacedObject, ILzNexClient)
  protected
    // Caractere de quoting de identificador. MySQL troca por backtick.
    function QuoteChar: string; virtual;
  public
    function DialectName: string; virtual; abstract;
    function ZeosProtocol: string; virtual; abstract;

    function WrapIdentifier(const AName: string): string; virtual;
    function WrapQualified(const AName: string): string; virtual;
    function Alias(const AExpr, AAlias: string): string; virtual;
    function Placeholder(const AIndex: Integer): string; virtual;
    function EscapeForLog(const AValue: TLzNexValue): string; virtual;

    function SupportsReturning: Boolean; virtual;
    function SupportsOnConflictWhere: Boolean; virtual;
    function SupportsNullsOrdering: Boolean; virtual;
    function SupportsDistinctOn: Boolean; virtual;
    function SupportsSavepoints: Boolean; virtual;
    function DdlIsTransactional: Boolean; virtual;

    function Components(const AMethod: TLzNexQueryMethod): TLzNexComponents; virtual;
    function InvalidComponents(const AMethod: TLzNexQueryMethod): TLzNexComponents; virtual;

    // Fabricas: abstratas de proposito. As units de compiler usam esta unit,
    // entao esta unit NAO pode usa-las de volta (seria ciclo). Cada unit de
    // dialeto, que conhece as duas, implementa.
    function NewCompiler: ILzNexCompiler; virtual; abstract;
    function NewSchemaCompiler: ILzNexSchemaCompiler; virtual; abstract;
  end;

// Registra um dialeto pelo nome ('mysql', 'postgresql').
// Chamado no initialization da unit do dialeto.
procedure RegisterClient(const AName: string; const AClass: TLzNexClientClass);

// Instancia o dialeto pelo nome. Levanta se nao registrado,
// listando os disponiveis (o erro diz o que fazer: dar `uses` na unit).
function CreateClient(const AName: string): ILzNexClient;

// Se o dialeto esta disponivel.
function IsClientRegistered(const AName: string): Boolean;

// Nomes dos dialetos registrados, separados por vírgula.
function RegisteredClients: string;

// Valida o operador contra a whitelist e normaliza o caso.
// Operador fora da lista levanta: fecha a porta para injecao via operador.
function NormalizeOperator(const AOp: string): string;

// Quebra 'schema.tabela.coluna' nos segmentos.
function SplitQualified(const AName: string): TLzNexStringArray;

// Posicao do ' as ' (case-insensitive) ou 0 se nao houver.
function FindAliasSeparator(const AName: string): Integer;

implementation

var
  GClients: TDictionary<string, TLzNexClientClass>;

{ TLzNexClientBase }

function TLzNexClientBase.QuoteChar: string;
begin
  Result := '"';
end;

function TLzNexClientBase.WrapIdentifier(const AName: string): string;
var
  Q, N: string;
begin
  N := Trim(AName);
  if (N = '') or (N = '*') then
    Exit(N);

  Q := QuoteChar;
  // Dobra o caractere de quoting dentro do nome -- e o escape padrao em SQL.
  Result := Q + StringReplace(N, Q, Q + Q, [rfReplaceAll]) + Q;
end;

function TLzNexClientBase.WrapQualified(const AName: string): string;
var
  AsPos: Integer;
  Parts: TLzNexStringArray;
  I: Integer;
  SB: TStringBuilder;
begin
  AsPos := FindAliasSeparator(AName);
  if AsPos > 0 then
  begin
    Result := Alias(
      WrapQualified(Trim(Copy(AName, 1, AsPos - 1))),
      WrapIdentifier(Trim(Copy(AName, AsPos + 4, Length(AName)))));
    Exit;
  end;

  Parts := SplitQualified(AName);
  if Length(Parts) <= 1 then
    Exit(WrapIdentifier(AName));

  SB := TStringBuilder.Create;
  try
    for I := 0 to High(Parts) do
    begin
      if I > 0 then
        SB.Append('.');
      SB.Append(WrapIdentifier(Parts[I]));
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TLzNexClientBase.Alias(const AExpr, AAlias: string): string;
begin
  if AAlias = '' then
    Result := AExpr
  else
    Result := AExpr + ' as ' + AAlias;
end;

function TLzNexClientBase.Placeholder(const AIndex: Integer): string;
begin
  // O Zeos aceita '?' posicional em MySQL, PostgreSQL e Firebird, entao o indice
  // e ignorado aqui. O hook existe para dialeto que precise de $1/:1.
  Result := LZNEX_PLACEHOLDER;
end;

function TLzNexClientBase.EscapeForLog(const AValue: TLzNexValue): string;
begin
  case AValue.Kind of
    vkUnset:
      Result := '<unset>';
    vkNull:
      Result := 'null';
    vkBoolean:
      if AValue.AsBoolean then Result := '1' else Result := '0';
    vkInteger, vkInt64:
      Result := IntToStr(AValue.AsInt64);
    vkFloat, vkCurrency:
      Result := StringReplace(FloatToStr(AValue.AsFloat), ',', '.', [rfReplaceAll]);
    vkDate:
      Result := QuotedStr(FormatDateTime('yyyy-mm-dd', AValue.AsDateTime));
    vkTime:
      Result := QuotedStr(FormatDateTime('hh:nn:ss', AValue.AsDateTime));
    vkDateTime:
      Result := QuotedStr(FormatDateTime('yyyy-mm-dd hh:nn:ss', AValue.AsDateTime));
    vkBytes:
      Result := '<' + IntToStr(Length(AValue.AsBytes)) + ' bytes>';
    vkIdentifier:
      Result := WrapQualified(AValue.Text);
  else
    // String e o resto: dobra a aspa simples. SO para log -- execucao usa bind.
    Result := QuotedStr(AValue.AsString);
  end;
end;

function TLzNexClientBase.SupportsReturning: Boolean;
begin
  Result := False;
end;

function TLzNexClientBase.SupportsOnConflictWhere: Boolean;
begin
  Result := False;
end;

function TLzNexClientBase.SupportsNullsOrdering: Boolean;
begin
  Result := False;
end;

function TLzNexClientBase.SupportsDistinctOn: Boolean;
begin
  Result := False;
end;

function TLzNexClientBase.SupportsSavepoints: Boolean;
begin
  Result := True;
end;

function TLzNexClientBase.DdlIsTransactional: Boolean;
begin
  Result := True;
end;

function TLzNexClientBase.Components(const AMethod: TLzNexQueryMethod): TLzNexComponents;
begin
  case AMethod of
    qmSelect, qmFirst:
      Result := TLzNexComponents.Create(
        cpHints, cpColumns, cpFrom, cpJoin, cpWhere, cpGroup, cpHaving,
        cpUnion, cpOrder, cpLimit, cpOffset, cpLock);
    qmUpdate:
      Result := TLzNexComponents.Create(cpFrom, cpJoin, cpWhere, cpOrder, cpLimit);
    qmDelete:
      Result := TLzNexComponents.Create(cpFrom, cpJoin, cpWhere, cpOrder, cpLimit);
    qmInsert:
      Result := TLzNexComponents.Create(cpFrom);
    qmTruncate:
      Result := TLzNexComponents.Create(cpFrom);
  else
    Result := nil;
  end;
end;

function TLzNexClientBase.InvalidComponents(
  const AMethod: TLzNexQueryMethod): TLzNexComponents;
begin
  case AMethod of
    qmDelete:
      // ANSI nao aceita HAVING nem LIMIT em DELETE. MySQL aceita LIMIT e
      // sobrescreve isto.
      Result := TLzNexComponents.Create(cpHaving, cpGroup, cpLimit);
    qmUpdate:
      Result := TLzNexComponents.Create(cpHaving, cpGroup);
    qmTruncate:
      Result := TLzNexComponents.Create(cpWhere, cpHaving, cpGroup, cpOrder, cpLimit);
  else
    Result := nil;
  end;
end;

{ registry }

procedure RegisterClient(const AName: string; const AClass: TLzNexClientClass);
begin
  GClients.AddOrSetValue(LowerCase(Trim(AName)), AClass);
end;

function IsClientRegistered(const AName: string): Boolean;
begin
  Result := GClients.ContainsKey(LowerCase(Trim(AName)));
end;

function RegisteredClients: string;
var
  Key: string;
begin
  Result := '';
  for Key in GClients.Keys do
  begin
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + Key;
  end;
  if Result = '' then
    Result := '<none>';
end;

function CreateClient(const AName: string): ILzNexClient;
var
  Cls: TLzNexClientClass;
begin
  if not GClients.TryGetValue(LowerCase(Trim(AName)), Cls) then
    raise ELzNexConfig.CreateFmt(
      'Dialect "%s" is not registered. Available: %s. ' +
      'The dialect unit is missing from `uses` (e.g. LzNex.Client.MySQL).',
      [AName, RegisteredClients]);
  Result := Cls.Create as ILzNexClient;
end;

function NormalizeOperator(const AOp: string): string;
var
  Norm: string;
  I: Integer;
begin
  Norm := LowerCase(Trim(AOp));
  // Normaliza espaco interno: 'not  like' -> 'not like'.
  while Pos('  ', Norm) > 0 do
    Norm := StringReplace(Norm, '  ', ' ', [rfReplaceAll]);

  for I := Low(LZNEX_OPERATORS) to High(LZNEX_OPERATORS) do
    if Norm = LZNEX_OPERATORS[I] then
      Exit(Norm);

  raise ELzNexBuilder.CreateFmt(
    'Operator "%s" is not allowed. The list is closed on purpose, so that an ' +
    'operator coming from user input cannot turn into SQL injection.', [AOp]);
end;

function SplitQualified(const AName: string): TLzNexStringArray;
var
  Parts: TStringArray;
  I: Integer;
begin
  Result := nil;
  Parts := AName.Split(['.']);
  SetLength(Result, Length(Parts));
  for I := 0 to High(Parts) do
    Result[I] := Trim(Parts[I]);
end;

function FindAliasSeparator(const AName: string): Integer;
var
  I, L: Integer;
begin
  // Busca ' as ' sem alocar lower-case da string inteira.
  // Devolve a posicao do ESPACO que abre o separador, entao a expressao e
  // Copy(1, pos-1) e o alias comeca em pos+4 (o separador tem 4 caracteres).
  Result := 0;
  L := Length(AName);
  for I := 1 to L - 3 do
    if (AName[I] = ' ') and
       ((AName[I + 1] = 'a') or (AName[I + 1] = 'A')) and
       ((AName[I + 2] = 's') or (AName[I + 2] = 'S')) and
       (AName[I + 3] = ' ') then
      Exit(I);
end;

initialization
  GClients := TDictionary<string, TLzNexClientClass>.Create;

finalization
  GClients.Free;

end.
