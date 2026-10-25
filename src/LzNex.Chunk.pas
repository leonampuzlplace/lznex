unit LzNex.Chunk;

{$MODE DELPHI}{$H+}

interface

uses
  SysUtils,
  LzNex.Types,
  LzNex.Value,
  LzNex.Intf,
  LzNex.Ast,
  LzNex.Cursor,
  LzNex.Exceptions;

type
  TLzNexChunks = class(TInterfacedObject, ILzNexChunks)
  private
    FSource: ILzNexQuery;
    FSize: Int64;

    // Vazio: lotes por Limit/Offset. Preenchido: lotes por chave.
    FKeyColumn: string;
    FKeys: TLzNexOrderKeys;

    FIndex: Int64;
    FSeen: Int64;
    FRows: TLzNexRowArray;
    FDone: Boolean;
    FLastKey: TLzNexValue;

    function RunChunk(const AQuery: ILzNexQuery): TLzNexRowArray;
    function LoadOffsetChunk: TLzNexRowArray;
    function LoadKeyChunk: TLzNexRowArray;
  public
    constructor Create(const ASource: ILzNexQuery; const ASize: Int64;
      const AKeyColumn: string);
    destructor Destroy; override;

    function Next: Boolean;
    function Rows: TLzNexRowArray;
    function ChunkIndex: Int64;
    function RowsSeen: Int64;
  end;

function NewOffsetChunks(const ASource: ILzNexQuery;
  const ASize: Int64): ILzNexChunks;

function NewKeyChunks(const ASource: ILzNexQuery; const ASize: Int64;
  const AKeyColumn: string): ILzNexChunks;

implementation

constructor TLzNexChunks.Create(const ASource: ILzNexQuery; const ASize: Int64;
  const AKeyColumn: string);
begin
  inherited Create;
  if ASource = nil then
    raise ELzNexBuilder.Create('Chunk without a query');
  if ASize < 1 then
    raise ELzNexBuilder.CreateFmt('Chunk: size must be >= 1, got %d', [ASize]);

  FSource := ASource;
  FSize := ASize;
  FKeyColumn := Trim(AKeyColumn);
  FIndex := 0;
  FSeen := 0;
  FDone := False;
  FLastKey := TLzNexValue.Unset;

  if FKeyColumn = '' then
  begin
    if not ASource.Ast.Has(sgOrder) then
      raise ELzNexBuilder.Create(
        'Chunk requires an OrderBy: without a stable order the database is ' +
        'free to return the rows in a different sequence on each chunk, and ' +
        'the same row would show up twice while another is never read. Add an ' +
        'OrderBy, or use ChunkById.');
    Exit;
  end;

  SetLength(FKeys, 1);
  FKeys[0].Column := FKeyColumn;
  FKeys[0].Descending := False;
end;

destructor TLzNexChunks.Destroy;
begin
  FRows := nil;
  FSource := nil;
  inherited Destroy;
end;

function TLzNexChunks.RunChunk(const AQuery: ILzNexQuery): TLzNexRowArray;
var
  Res: ILzNexResult;
begin
  Res := AQuery.Get;
  try
    Result := Res.ToRows;
  finally
    // Fecha antes de devolver: o lease do pool nao fica preso entre lotes.
    Res.Close;
  end;
end;

function TLzNexChunks.LoadOffsetChunk: TLzNexRowArray;
begin
  Result := RunChunk(FSource.Clone.ClearPaging.Page(FIndex + 1, FSize));
end;

function TLzNexChunks.LoadKeyChunk: TLzNexRowArray;
var
  Q: ILzNexQuery;
  Values: TLzNexValues;
begin
  { A ordem passa a ser a da chave: avancar por "chave > ultima lida" so faz
    sentido lendo nessa ordem. }
  Q := FSource.Clone.ClearPaging.Clear(sgOrder);
  if not FLastKey.IsUnset then
    Q.Where(FKeyColumn, '>', FLastKey);
  Q.OrderBy(FKeyColumn).Limit(FSize);

  Result := RunChunk(Q);
  if Length(Result) > 0 then
  begin
    Values := KeyValuesOf(Result[High(Result)], FKeys);
    FLastKey := Values[0];
    if FLastKey.IsNull then
      raise ELzNexBuilder.CreateFmt(
        'ChunkById found NULL in the key column "%s". The walk advances with ' +
        '"%s > last value", and a comparison against NULL is never true, so ' +
        'it would stop early. Use a NOT NULL key.',
        [FKeyColumn, FKeyColumn]);
  end;
end;

function TLzNexChunks.Next: Boolean;
begin
  FRows := nil;
  if FDone then
    Exit(False);

  if FKeyColumn = '' then
    FRows := LoadOffsetChunk
  else
    FRows := LoadKeyChunk;

  // Lote menor que o pedido significa que o conjunto acabou.
  if Int64(Length(FRows)) < FSize then
    FDone := True;

  Result := Length(FRows) > 0;
  if Result then
  begin
    Inc(FIndex);
    Inc(FSeen, Length(FRows));
  end;
end;

function TLzNexChunks.Rows: TLzNexRowArray;
begin
  Result := FRows;
end;

function TLzNexChunks.ChunkIndex: Int64;
begin
  Result := FIndex;
end;

function TLzNexChunks.RowsSeen: Int64;
begin
  Result := FSeen;
end;

function NewOffsetChunks(const ASource: ILzNexQuery;
  const ASize: Int64): ILzNexChunks;
begin
  Result := TLzNexChunks.Create(ASource, ASize, '') as ILzNexChunks;
end;

function NewKeyChunks(const ASource: ILzNexQuery; const ASize: Int64;
  const AKeyColumn: string): ILzNexChunks;
begin
  if Trim(AKeyColumn) = '' then
    raise ELzNexBuilder.Create('ChunkById: the key column is required');
  Result := TLzNexChunks.Create(ASource, ASize, AKeyColumn) as ILzNexChunks;
end;

end.
