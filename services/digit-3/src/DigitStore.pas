// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-3
// Module:          src/DigitStore.pas
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         SQLite storage of the digit: opening the database,
//                  applying the versioned migrations and reading the row
//                  that holds the value and successor of the digit.
// Related Docs:    services/digit-3/README.md, migrations/0001_digit.sql,
//                  CLAUDE.md 4.4, ADR-0022

{ SQLite storage of the digit (open, migrate, read).

  The digit service keeps its only fact, the value and successor of its
  digit, in its own SQLite database (CLAUDE.md 4.4). Migrations are the
  files NNNN_*.sql of the migrations directory, applied once each in
  lexical order and recorded in the table schema_migrations.

  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0. }
unit DigitStore;

{$MODE objfpc}
{$H+}

interface

uses
  SysUtils,
  sqlite3;

type
  { The digit row of the database (table digit of 0001_digit.sql).
    Thread Safety: plain value. }
  TDigitRow = record
    { The digit the service represents, 0..9. }
    Digit: integer;
    { Numeric value of the digit, 0..9. }
    Value: integer;
    { Successor of the digit in base 10, 0..9. }
    Next: integer;
    { True when the successor wraps to 0 (digit 9 only). }
    Carry: boolean;
  end;

  { A storage failure: the database cannot be opened, migrated or read;
    Message carries the SQLite text or the reason. }
  EStoreError = class(Exception);

  { The SQLite database of the service (one connection), closed when the
    object is freed.

    Business Justification: each service owns its database (CLAUDE.md 1,
    rule 4).

    Thread Safety: not safe; one thread at a time (TApi serialises access
    with a lock). Owner: Arithmetic Excellence Center (AEC).
    Since: digit-3 0.1.0. }
  TStore = class
  private
    { The open connection. }
    FDb: psqlite3;

    { Raise EStoreError with Context and the last SQLite message.

      @param(Context what failed)
      @raises(EStoreError always)

      Side Effects: none. Complexity: O(1). Thread Safety: as the
      connection. Owner: AEC. Since: digit-3 0.1.0.
      Example: RaiseError('cannot read the digit'). See Also: Execute. }
    procedure RaiseError(const Context: string);

    { Whether a migration is recorded in schema_migrations.

      Description: a failing query counts as "not applied", so that the
      following apply fails loudly instead of skipping silently.

      Business Justification: each migration runs exactly once.

      @param(Version migration file name)
      @returns(True when recorded)

      Errors: none. Side Effects: one SELECT. Complexity: O(log m).
      Thread Safety: as the connection. Owner: AEC. Since: digit-3 0.1.0.
      Example: IsApplied('0001_digit.sql'). See Also: Migrate. }
    function IsApplied(const Version: string): boolean;

    { Apply one migration file and record it, in one transaction.

      Description: on any failure the transaction is rolled back.

      Business Justification: a half-applied migration must never be
      recorded as applied.

      @param(Dir migrations directory)
      @param(Version migration file name inside Dir)
      @raises(EStoreError when the file cannot be read or its SQL or the
        record fails)

      Side Effects: writes the database; logs the applied file.
      Complexity: O(s) in the file size. Thread Safety: as the connection.
      Owner: AEC. Since: digit-3 0.1.0.
      Example: Apply('/app/migrations', '0001_digit.sql'). See Also: Migrate. }
    procedure Apply(const Dir, Version: string);
  public

    { Open (or create) the SQLite database file.

      Description: opens Path read-write, creating it when missing, sets a
      busy timeout of 2 s and enables foreign keys.

      Business Justification: each service owns its database.

      @param(Path database file path; :memory: for an in-memory database)
      @raises(EStoreError when SQLite cannot open the file)

      Side Effects: creates the file when missing. Complexity: O(1).
      Thread Safety: safe. Owner: Arithmetic Excellence Center (AEC).
      Since: digit-3 0.1.0. Example: Store := TStore.Create('/data/digit-3.db').
      See Also: Migrate, Destroy. }
    constructor Create(const Path: string);

    { Close the connection.

      Errors: none. Side Effects: releases the connection. Complexity: O(1).
      Thread Safety: not safe while another thread uses the store.
      Owner: AEC. Since: digit-3 0.1.0. Example: Store.Free.
      See Also: Create. }
    destructor Destroy; override;

    { Execute one or more SQL statements without results.

      Description: used by the migration runner and by the unit tests.

      Business Justification: one place where SQL errors become EStoreError.

      @param(Sql SQL text)
      @raises(EStoreError with the SQLite message when a statement fails)

      Side Effects: whatever the SQL does. Complexity: that of the
      statements. Thread Safety: as the connection. Owner: AEC.
      Since: digit-3 0.1.0. Example: Store.Execute('UPDATE digit SET next = 7;').
      See Also: Migrate. }
    procedure Execute(const Sql: string);

    { Apply the migrations of a directory that are not applied yet.

      Description: creates schema_migrations when missing, lists the files
      *.sql of Dir that do not start with a dot, sorts them lexically and
      applies each file not recorded yet, in one transaction per file with
      its record. Running it again applies nothing.

      Business Justification: migrations run at start-up and are versioned
      (CLAUDE.md 6.1); the seed of the digit is a migration, so the digit
      lives in the database, not the code.

      @param(Dir directory with the migration files)
      @returns(number of files applied by this call)
      @raises(EStoreError when the directory or a file cannot be read or its
        SQL fails)

      Side Effects: reads files; writes the database; logs each applied
      file. Complexity: O(f log f + s). Thread Safety: not safe; call before
      serving. Owner: AEC. Since: digit-3 0.1.0.
      Example: Applied := Store.Migrate('/app/migrations'). See Also: Read. }
    function Migrate(const Dir: string): integer;

    { Read the digit row.

      Description: requires the table digit to hold exactly one row; zero
      rows or more than one are an error, as is any SQLite failure.

      Business Justification: GET /value, GET /next and GET /health answer
      from this read on every request (CLAUDE.md 4.4).

      @returns(the row)
      @raises(EStoreError when the query fails or the table does not hold
        exactly one row)

      Side Effects: one SELECT. Complexity: O(1). Thread Safety: as the
      connection. Owner: AEC. Since: digit-3 0.1.0.
      Example: Row := Store.Read. See Also: TDigitRow. }
    function Read: TDigitRow;
  end;

implementation

uses
  Classes,
  DigitLog;

const
  { Busy timeout of the connection, in milliseconds (CLAUDE.md 6.1). }
  BusyTimeoutMs = 2000;

  { Bookkeeping table of the migration runner: one row per applied file,
    version is the file name, applied_at the UTC time (ISO 8601). }
  MigrationsTable =
      'CREATE TABLE IF NOT EXISTS schema_migrations ('
          + ' version TEXT PRIMARY KEY NOT NULL, applied_at TEXT NOT NULL) STRICT;';

constructor TStore.Create(const Path: string);
begin
  inherited Create;
  if sqlite3_open_v2(pansichar(Path), @FDb, SQLITE_OPEN_READWRITE or SQLITE_OPEN_CREATE, nil) <> SQLITE_OK then
    RaiseError('cannot open the database');
  sqlite3_busy_timeout(FDb, BusyTimeoutMs);
  Execute('PRAGMA foreign_keys = ON;');
end;

destructor TStore.Destroy;
begin
  sqlite3_close(FDb);
  inherited Destroy;
end;

procedure TStore.RaiseError(const Context: string);
begin
  raise EStoreError.Create(Context + ': ' + string(sqlite3_errmsg(FDb)));
end;

procedure TStore.Execute(const Sql: string);
var
  Error: pansichar;
  Message: string;
begin
  Error := nil;
  if sqlite3_exec(FDb, pansichar(Sql), nil, nil, @Error) <> SQLITE_OK then begin
    if Error <> nil then
      Message := string(Error)
    else
      Message := string(sqlite3_errmsg(FDb));
    sqlite3_free(Error);
    raise EStoreError.Create(Message);
  end;
end;

function TStore.IsApplied(const Version: string): boolean;
var
  Stmt: psqlite3_stmt;
begin
  Result := False;
  Stmt := nil;
  if sqlite3_prepare_v2(FDb, 'SELECT 1 FROM schema_migrations WHERE version = ?1;', -1, @Stmt, nil) = SQLITE_OK then
  begin
    sqlite3_bind_text(Stmt, 1, pansichar(Version), -1, sqlite3_destructor_type(SQLITE_TRANSIENT));
    Result := sqlite3_step(Stmt) = SQLITE_ROW;
  end;
  sqlite3_finalize(Stmt);
end;

procedure TStore.Apply(const Dir, Version: string);
var
  Lines: TStringList;
  Stmt: psqlite3_stmt;
begin
  Lines := TStringList.Create;
  try
    try
      Lines.LoadFromFile(IncludeTrailingPathDelimiter(Dir) + Version);
    except
      on E: Exception do
        raise EStoreError.Create('cannot read migration ' + Version + ': ' + E.Message);
    end;
    Execute('BEGIN IMMEDIATE;');
    try
      Execute(Lines.Text);
      Stmt := nil;
      if sqlite3_prepare_v2(
              FDb,
              'INSERT INTO schema_migrations (version, applied_at) '
                  + 'VALUES (?1, strftime(''%Y-%m-%dT%H:%M:%fZ'', ''now''));',
              -1,
              @Stmt,
              nil)
          <> SQLITE_OK then
        RaiseError('cannot record migration');
      try
        sqlite3_bind_text(Stmt, 1, pansichar(Version), -1, sqlite3_destructor_type(SQLITE_TRANSIENT));
        if sqlite3_step(Stmt) <> SQLITE_DONE then
          RaiseError('cannot record migration');
      finally
        sqlite3_finalize(Stmt);
      end;
      Execute('COMMIT;');
    except
      on E: Exception do begin
        sqlite3_exec(FDb, 'ROLLBACK;', nil, nil, nil);
        raise EStoreError.Create('migration ' + Version + ' failed: ' + E.Message);
      end;
    end;
  finally
    Lines.Free;
  end;
  LogWrite(llInfo, 'migration applied', '', '', Version);
end;

function TStore.Migrate(const Dir: string): integer;
var
  Names: TStringList;
  Search: TSearchRec;
  Name: string;
begin
  Execute(MigrationsTable);
  if not DirectoryExists(Dir) then
    raise EStoreError.Create('cannot read the migrations directory ' + Dir);
  Names := TStringList.Create;
  try
    Names.Sorted := True;
    if FindFirst(IncludeTrailingPathDelimiter(Dir) + '*.sql', faAnyFile, Search) = 0 then begin
      repeat
        if (Search.Name[1] <> '.') and (Length(Search.Name) > 4) and ((Search.Attr and faDirectory) = 0) then
          Names.Add(Search.Name);
      until FindNext(Search) <> 0;
    end;
    FindClose(Search);
    Result := 0;
    for Name in Names do
      if not IsApplied(Name) then begin
        Apply(Dir, Name);
        Inc(Result);
      end;
  finally
    Names.Free;
  end;
end;

function TStore.Read: TDigitRow;
var
  Stmt: psqlite3_stmt;
begin
  Stmt := nil;
  if sqlite3_prepare_v2(FDb, 'SELECT digit, value, next, carry FROM digit LIMIT 2;', -1, @Stmt, nil) <> SQLITE_OK then
    RaiseError('cannot read the digit');
  try
    if sqlite3_step(Stmt) <> SQLITE_ROW then
      raise EStoreError.Create('the table digit holds no row');
    Result.Digit := sqlite3_column_int(Stmt, 0);
    Result.Value := sqlite3_column_int(Stmt, 1);
    Result.Next := sqlite3_column_int(Stmt, 2);
    Result.Carry := sqlite3_column_int(Stmt, 3) <> 0;
    if sqlite3_step(Stmt) <> SQLITE_DONE then
      raise EStoreError.Create('the table digit holds more than one row');
  finally
    sqlite3_finalize(Stmt);
  end;
end;

end.
