unit M20261024120000_create_users;

{ Migration de exemplo em Pascal: usa o schema builder tipado. }

{$MODE DELPHI}{$H+}

interface

uses
  LzNex.Intf,
  LzNex.Migration;

type
  TCreateUsers = class(TLzNexMigration)
  public
    class function Id: string; override;
    class function MigrationName: string; override;
    procedure Up(const ADb: ILzNex); override;
    procedure Down(const ADb: ILzNex); override;
  end;

implementation

class function TCreateUsers.Id: string;
begin
  Result := '20261024120000';
end;

class function TCreateUsers.MigrationName: string;
begin
  Result := '20261024120000_create_users';
end;

procedure TCreateUsers.Up(const ADb: ILzNex);
begin
  ADb.Schema.CreateTable('users')
    .Increments('id')
    .Str('email', 191).NotNull.Unique
    .Str('name', 120).NotNull
    .Bool('active').Default_(True)
    .Json('meta').Nullable
    .Timestamps
    .Engine('InnoDB')
    .Charset('utf8mb4')
    .Execute;

  ADb.Schema.CreateTable('posts')
    .Increments('id')
    .Int('user_id').Unsigned.NotNull
      .References('id').InTable('users').OnDelete('CASCADE')
    .Str('title', 200).NotNull
    .Text('body').Nullable
    .Timestamps
    .Engine('InnoDB')
    .Charset('utf8mb4')
    .Execute;
end;

procedure TCreateUsers.Down(const ADb: ILzNex);
begin
  // Ordem inversa: posts referencia users.
  ADb.Schema.DropTableIfExists('posts');
  ADb.Schema.DropTableIfExists('users');
end;

initialization
  RegisterMigration(TCreateUsers);

end.
