program Api;

{$MODE DELPHI}{$H+}

uses
  {$IFDEF UNIX}{$IFDEF UseCThreads}
  cthreads,
  {$ENDIF}{$ENDIF}
  SysUtils,
  Horse,
  LzNex,
  LzNex.Client.MySQL;

var

  Db: ILzNex;

function EnvOr(const AName, ADefault: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    Result := ADefault;
end;

procedure Log(const AMessage: string);
begin
  Writeln('[api] ', AMessage);

  Flush(Output);
end;

function JsonQuote(const AText: string): string;
var
  I: Integer;
  Ch: Char;
begin
  Result := '"';
  for I := 1 to Length(AText) do
  begin
    Ch := AText[I];
    case Ch of
      '"':  Result := Result + '\"';
      '\':  Result := Result + '\\';
      #8:   Result := Result + '\b';
      #9:   Result := Result + '\t';
      #10:  Result := Result + '\n';
      #12:  Result := Result + '\f';
      #13:  Result := Result + '\r';
    else
      if Ch < ' ' then
        Result := Result + '\u' + LowerCase(IntToHex(Ord(Ch), 4))
      else
        Result := Result + Ch;
    end;
  end;
  Result := Result + '"';
end;

procedure OpenDatabase;
var
  Cfg: ILzNexConfig;
begin
  Cfg := NewConfig
    .Client('mysql')
    .Host(EnvOr('DB_HOST', 'mysql'))
    .Port(StrToIntDef(EnvOr('DB_PORT', '3306'), 3306))
    .Database(EnvOr('DB_NAME', 'lznex'))
    .User(EnvOr('DB_USER', 'root'))
    .Password(EnvOr('DB_PASS', 'secret'))

    .LibraryLocation(EnvOr('DB_LIB', '/usr/lib/x86_64-linux-gnu/libmariadb.so.3'))
    .Charset('utf8mb4')
    .Pool(2, 8);
  Db := Connect(Cfg);
end;

procedure GetHealth(Req: THorseRequest; Res: THorseResponse);
begin
  try
    if Db.Connection.Ping then
      Res.Status(200).ContentType('application/json')
         .Send('{"status":"ok","dialect":' + JsonQuote(Db.Client.DialectName) + '}')
    else
      Res.Status(503).ContentType('application/json')
         .Send('{"status":"down"}');
  except
    on E: Exception do
    begin
      Log('health falhou: ' + E.Message);
      Res.Status(503).ContentType('application/json')
         .Send('{"status":"down","error":' + JsonQuote(E.Message) + '}');
    end;
  end;
end;

procedure GetUsers(Req: THorseRequest; Res: THorseResponse);
var
  Rows: ILzNexResult;
begin
  try
    Rows := Db.Table('users')
      .Select(['id', 'name', 'email'])
      .OrderBy('id')
      .Limit(20)
      .Get;
    Res.Status(200).ContentType('application/json').Send(Rows.ToJSON);
  except
    on E: Exception do
    begin
      Log('users falhou: ' + E.Message);
      Res.Status(500).ContentType('application/json')
         .Send('{"error":' + JsonQuote(E.Message) + '}');
    end;
  end;
end;

begin
  OpenDatabase;
  Log('banco: ' + EnvOr('DB_USER', 'root') + '@' + EnvOr('DB_HOST', 'mysql') +
      '/' + EnvOr('DB_NAME', 'lznex') + ' via ' + Db.Client.DialectName);

  THorse.Get('/health', GetHealth);
  THorse.Get('/users', GetUsers);

  Log('ouvindo em 0.0.0.0:9000');
  try
    THorse.Listen(9000);
  finally
    Db.Shutdown;
    Db := nil;
  end;
end.
