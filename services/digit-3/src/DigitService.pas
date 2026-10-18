// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-3
// Module:          src/DigitService.pas
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         The digit-3 service: configuration from the environment,
//                  database migrations, the HTTP server (fcl-web
//                  TFPHttpServer) on port 8080 and graceful shutdown.
// Related Docs:    services/digit-3/README.md, CLAUDE.md 4.4, 6.1,
//                  ADR-0022, ADR-0025

{ The digit-3 service: configuration, start-up, HTTP server and shutdown.

  Start-up reads the configuration (AAAS_BOOTSTRAP=env until P5.2), opens
  and migrates the database and checks that it holds the configured digit.
  The service then answers HTTP with one thread per connection until
  SIGTERM or SIGINT, waits for the running requests and closes the
  database, well within the 10 s of CLAUDE.md 6.1.

  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0. }
unit DigitService;

{$MODE objfpc}
{$H+}

interface

uses
  Classes,
  SysUtils,
  ctypes,
  ssockets,
  fphttpserver,
  DigitStore,
  DigitMetrics,
  DigitApi;

const
  { Version of the service (SemVer, docs/CHANGELOG.md). }
  ServiceVersion = '0.1.0';
  { Largest request body read, in bytes; the contract has no request body,
    larger bodies answer 413. }
  MaxBodyBytes = 65536;
  { Time allowed for each read from a connection, in milliseconds. }
  ReadTimeoutMs = 2000;
  { Poll interval of the accept loop, in milliseconds (stop latency). }
  AcceptIdleMs = 200;

type
  { Configuration of the process, from the environment. Thread Safety:
    plain value. }
  TConfig = record
    { AAAS_DB_PATH (default /data/digit-3.db). }
    DbPath: string;
    { AAAS_MIGRATIONS_DIR (default /app/migrations). }
    MigrationsDir: string;
    { AAAS_DIGIT, 0..9 (default 3). }
    Digit: integer;
    { AAAS_HTTP_PORT, 1..65535 (default 8080). }
    Port: integer;
  end;

  { A connection of the digit server: a read timeout on the socket and a
    cap on the request body.

    Business Justification: a silent or oversized request must not hold a
    thread or memory without bound.

    Thread Safety: one instance per connection thread.
    Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0. }
  TDigitConnection = class(TFPHTTPConnection)
  protected

    { Set a receive timeout of ReadTimeoutMs on the socket, then the
      library defaults.

      Errors: none (a failed setsockopt leaves the socket blocking).
      Side Effects: changes a socket option. Complexity: O(1).
      Thread Safety: connection thread. Owner: AEC. Since: digit-3 0.1.0.
      Example: called by the library. See Also: ReadTimeoutMs. }
    procedure SetupSocket; override;

    { Read the request body, unless it is larger than MaxBodyBytes.

      Description: a larger body is not read; the request is marked with the
      custom header X-Digit-Body-Too-Large and answered 413, and the
      connection closes.

      @param(ARequest the request being read)

      Errors: as the library (read failures). Side Effects: reads the
      socket. Complexity: O(n) in the body size. Thread Safety: connection
      thread. Owner: AEC. Since: digit-3 0.1.0.
      Example: called by the library. See Also: MaxBodyBytes. }
    procedure ReadRequestContent(ARequest: TFPHTTPConnectionRequest); override;

    { Keep every header the library does not know, so that traceparent is
      available to the handler.

      @param(ARequest the request being read)
      @param(AHeader the header line, Name: value)

      Errors: none. Side Effects: adds a custom header to the request.
      Complexity: O(n). Thread Safety: connection thread. Owner: AEC.
      Since: digit-3 0.1.0. Example: called by the library.
      See Also: TDigitService.HandleRequest. }
    procedure UnknownHeader(ARequest: TFPHTTPConnectionRequest; const AHeader: string); override;
  end;

  { The HTTP server of the digit: TFPHttpServer creating TDigitConnection.
    Thread Safety: as TFPHttpServer. Owner: AEC. Since: digit-3 0.1.0. }
  TDigitServer = class(TFPHttpServer)
  protected

    { Create a TDigitConnection for an accepted socket.

      @param(Data the accepted socket stream)
      @returns(the connection object)

      Errors: none. Side Effects: none. Complexity: O(1). Thread Safety:
      accept loop. Owner: AEC. Since: digit-3 0.1.0.
      Example: called by the library. See Also: TDigitConnection. }
    function CreateConnection(Data: TSocketStream): TFPHTTPConnection; override;
  end;

  { The running service: store, counters, contract and server.

    Thread Safety: HandleRequest runs on connection threads and is safe
    (TApi locks the database); the rest runs on the main thread.
    Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0. }
  TDigitService = class
  private
    { The database of the service. }
    FStore: TStore;
    { Request counters. }
    FMetrics: TMetrics;
    { The contract. }
    FApi: TApi;
    { The HTTP server. }
    FServer: TDigitServer;
    { The configured digit. }
    FDigit: integer;
    { True once the listening line was logged. }
    FAnnounced: boolean;
  public

    { Open and migrate the database, check the row, build the server.

      @param(Config the configuration)
      @raises(EStoreError when the database cannot be prepared or holds
        another digit)

      Side Effects: opens the database; applies migrations; logs.
      Complexity: O(s) in the migrations. Thread Safety: main thread.
      Owner: AEC. Since: digit-3 0.1.0.
      Example: Service := TDigitService.Create(Config). See Also: Run. }
    constructor Create(const Config: TConfig);

    { Close the server and the database. Errors: none. Side Effects:
      releases resources. Complexity: O(1). Thread Safety: main thread,
      after Run. Owner: AEC. Since: digit-3 0.1.0. Example: Service.Free.
      See Also: Create. }
    destructor Destroy; override;

    { Serve until SIGTERM or SIGINT, then wait for running requests.

      Description: the accept loop checks the stop flag every AcceptIdleMs;
      after it stops, Run waits up to 5 s for connection threads to finish.

      @raises(ESocketError when the port cannot be bound)

      Side Effects: network I/O; logs. Complexity: not applicable.
      Thread Safety: main thread. Owner: AEC. Since: digit-3 0.1.0.
      Example: Service.Run. See Also: HandleRequest. }
    procedure Run;

    { Answer one request through the contract (OnRequest of the server).

      Description: the path is the target without the query string; the
      body is sent byte for byte through a content stream; a debug line
      carries the caller's trace when traceparent is valid.

      @param(Sender the server)
      @param(ARequest the request)
      @param(AResponse the response to fill)

      Errors: none. Side Effects: database read, metrics, debug log.
      Complexity: O(1). Thread Safety: safe (connection threads).
      Owner: AEC. Since: digit-3 0.1.0. Example: called by the server.
      See Also: TApi.Handle. }
    procedure HandleRequest(
        Sender: TObject;
        var ARequest: TFPHTTPConnectionRequest;
        var AResponse: TFPHTTPConnectionResponse
    );

    { Log that the server listens (first call only) and stop the accept
      loop once a stop was requested (OnAcceptIdle).

      Description: the library calls it whenever no connection arrived for
      AcceptIdleMs, so the listening line appears at most 200 ms after the
      port is bound.

      @param(Sender the server)

      Errors: none. Side Effects: logs once; deactivates the server.
      Complexity: O(1).
      Thread Safety: accept loop. Owner: AEC. Since: digit-3 0.1.0.
      Example: called by the server. See Also: Run. }
    procedure AcceptIdle(Sender: TObject);
  end;

{ Signal handler for SIGTERM and SIGINT: request a graceful stop.

  Description: only records the signal and sets the stop flag, which the
  accept loop polls every AcceptIdleMs.

  Business Justification: docker stop sends SIGTERM; the service must stop
  within 10 s (CLAUDE.md 6.1).

  @param(Signal the received signal number)

  Errors: none. Side Effects: sets two unit variables. Complexity: O(1).
  Thread Safety: async-signal-safe (plain stores).
  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0.
  Example: fpSignal(SIGTERM, @OnStopSignal).
  See Also: TDigitService.AcceptIdle. }
procedure OnStopSignal(Signal: cint); cdecl;

{ The environment variable Name, or Fallback when unset or empty.

  Business Justification: configuration comes only from the environment
  (CLAUDE.md 6.1).

  @param(Name variable name)
  @param(Fallback value used when the variable is unset or empty)
  @returns(the value)

  Errors: none. Side Effects: reads the environment. Complexity: O(n).
  Thread Safety: safe while no thread changes the environment.
  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0.
  Example: EnvOr('AAAS_DB_PATH', '/data/digit-3.db').
  See Also: LoadConfig. }
function EnvOr(const Name, Fallback: string): string;

{ Parse a decimal integer in [Low, High].

  Description: the whole text must be the canonical decimal form of the
  value (no sign, blanks or leading zeros).

  Business Justification: rejects misconfiguration (a port of 0) at
  start-up.

  @param(Text text to parse)
  @param(Low smallest accepted value)
  @param(High largest accepted value)
  @param(Value receives the value)
  @returns(True on success)

  Errors: False for non-numeric text or a value out of range.
  Side Effects: none. Complexity: O(n). Thread Safety: safe.
  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0.
  Example: ParseInt('8080', 1, 65535, Port) = True.
  See Also: LoadConfig. }
function ParseInt(const Text: string; Low, High: integer; out Value: integer): boolean;

{ Read the configuration from the environment.

  Description: only AAAS_BOOTSTRAP=env is available until the config
  server and OpenBao exist (P5.2, P5.3); platform is refused.

  Business Justification: CLAUDE.md 3 and 6.1.

  @param(Config receives the configuration)
  @returns(True when valid; errors are logged)

  Errors: False for an unsupported AAAS_BOOTSTRAP or an invalid AAAS_DIGIT
  or AAAS_HTTP_PORT. Side Effects: reads the environment; logs.
  Complexity: O(1). Thread Safety: main thread.
  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0.
  Example: if not LoadConfig(Config) then Halt(1).
  See Also: RunService. }
function LoadConfig(out Config: TConfig): boolean;

{ Run the service: configuration, start-up checks, serving, shutdown.

  @returns(the exit status: 0 after a graceful stop, 1 when start-up fails)

  Errors: 1 for invalid configuration, an unopenable or unmigratable
  database, a database holding another digit, or a port that cannot be
  bound. Side Effects: database, network, signals, logs.
  Complexity: not applicable. Thread Safety: main thread.
  Owner: Arithmetic Excellence Center (AEC). Since: digit-3 0.1.0.
  Example: Halt(RunService).
  See Also: LoadConfig, TDigitService. }
function RunService: integer;

implementation

uses
  BaseUnix,
  Sockets,
  DigitLog,
  DigitTrace;

var
  { True once SIGTERM or SIGINT has been received. }
  StopRequested: boolean = False;
  { Number of the signal that requested the stop. }
  StopSignal: cint = 0;

procedure OnStopSignal(Signal: cint); cdecl;
begin
  StopSignal := Signal;
  StopRequested := True;
end;

function EnvOr(const Name, Fallback: string): string;
begin
  Result := GetEnvironmentVariable(Name);
  if Result = '' then
    Result := Fallback;
end;

function ParseInt(const Text: string; Low, High: integer; out Value: integer): boolean;
begin
  Result := TryStrToInt(Text, Value) and (Value >= Low) and (Value <= High) and (Text = IntToStr(Value));
end;

function LoadConfig(out Config: TConfig): boolean;
var
  Text: string;
begin
  Config := Default(TConfig);
  Text := EnvOr('AAAS_BOOTSTRAP', 'env');
  if Text <> 'env' then begin
    LogWrite(llError, 'unsupported AAAS_BOOTSTRAP; only env exists before P5.2', '', '', Text);
    Exit(False);
  end;
  Text := EnvOr('AAAS_DIGIT', '3');
  if not ParseInt(Text, 0, 9, Config.Digit) then begin
    LogWrite(llError, 'AAAS_DIGIT must be 0..9', '', '', Text);
    Exit(False);
  end;
  Text := EnvOr('AAAS_HTTP_PORT', '8080');
  if not ParseInt(Text, 1, 65535, Config.Port) then begin
    LogWrite(llError, 'AAAS_HTTP_PORT must be 1..65535', '', '', Text);
    Exit(False);
  end;
  Config.DbPath := EnvOr('AAAS_DB_PATH', '/data/digit-3.db');
  Config.MigrationsDir := EnvOr('AAAS_MIGRATIONS_DIR', '/app/migrations');
  Result := True;
end;

procedure TDigitConnection.SetupSocket;
var
  Timeout: TTimeVal;
begin
  inherited SetupSocket;
  Timeout.tv_sec := ReadTimeoutMs div 1000;
  Timeout.tv_usec := (ReadTimeoutMs mod 1000) * 1000;
  fpsetsockopt(Socket.Handle, SOL_SOCKET, SO_RCVTIMEO, @Timeout, SizeOf(Timeout));
end;

procedure TDigitConnection.ReadRequestContent(ARequest: TFPHTTPConnectionRequest);
begin
  if ARequest.ContentLength > MaxBodyBytes then
    ARequest.SetCustomHeader('X-Digit-Body-Too-Large', '1')
  else
    inherited ReadRequestContent(ARequest);
end;

procedure TDigitConnection.UnknownHeader(ARequest: TFPHTTPConnectionRequest; const AHeader: string);
var
  Colon: integer;
begin
  Colon := Pos(':', AHeader);
  if Colon > 1 then
    ARequest.SetCustomHeader(LowerCase(Trim(Copy(AHeader, 1, Colon - 1))), Trim(Copy(AHeader, Colon + 1, MaxInt)));
end;

function TDigitServer.CreateConnection(Data: TSocketStream): TFPHTTPConnection;
begin
  Result := TDigitConnection.Create(Self, Data);
end;

constructor TDigitService.Create(const Config: TConfig);
begin
  inherited Create;
  FStore := TStore.Create(Config.DbPath);
  FStore.Migrate(Config.MigrationsDir);
  if FStore.read.Digit <> Config.Digit then
    raise EStoreError.Create('the database does not hold the configured digit: ' + Config.DbPath);
  FMetrics := TMetrics.Create(Config.Digit, ServiceVersion);
  FApi := TApi.Create(FStore, Config.Digit, FMetrics);
  FDigit := Config.Digit;
  FServer := TDigitServer.Create(nil);
  FServer.Port := Config.Port;
  FServer.Threaded := True;
  FServer.AcceptIdleTimeout := AcceptIdleMs;
  FServer.OnAcceptIdle := @AcceptIdle;
  FServer.OnRequest := @HandleRequest;
end;

destructor TDigitService.Destroy;
begin
  FServer.Free;
  FApi.Free;
  FMetrics.Free;
  FStore.Free;
  inherited Destroy;
end;

{ The event signatures of TFPHttpServer require Sender, which both handlers
  ignore; hint 5024 (parameter not used) is off for them only. }
{$PUSH}
{$WARN 5024 OFF}
procedure TDigitService.AcceptIdle(Sender: TObject);
begin
  if not FAnnounced then begin
    FAnnounced := True;
    LogWrite(
        llInfo,
        'listening',
        '',
        '',
        Format('port %d, digit %d, version %s', [FServer.Port, FDigit, ServiceVersion])
    );
  end;
  if StopRequested then
    FServer.Active := False;
end;

procedure TDigitService.HandleRequest(
    Sender: TObject;
    var ARequest: TFPHTTPConnectionRequest;
    var AResponse: TFPHTTPConnectionResponse
);
var
  Reply: TReply;
  Path: string;
  Trace: TTraceContext;
  Cut: integer;
begin
  Path := ARequest.URL;
  Cut := Pos('?', Path);
  if Cut > 0 then
    Path := Copy(Path, 1, Cut - 1);
  if ARequest.GetCustomHeader('X-Digit-Body-Too-Large') <> '' then
    Reply := Problem(413, 'Payload Too Large', 'the request body exceeds 64 KiB')
  else
    Reply := FApi.Handle(ARequest.Method, Path);
  AResponse.Code := Reply.Status;
  AResponse.ContentType := Reply.ContentType;
  if Reply.Allow <> '' then
    AResponse.SetCustomHeader('Allow', Reply.Allow);
  AResponse.SetCustomHeader('Connection', 'close');
  // ContentStream, not Content: Content keeps the body in a TStrings and
  // appends a line ending, while the contract bodies end with the JSON.
  AResponse.ContentStream := TStringStream.Create(Reply.Body);
  AResponse.FreeContentStream := True;
  Trace := Default(TTraceContext);
  ParseTraceparent(ARequest.GetCustomHeader('traceparent'), Trace);
  LogWrite(
      llDebug,
      'request answered',
      Trace.TraceId,
      Trace.SpanId,
      Format('%s %s -> %d', [ARequest.Method, Path, Reply.Status])
  );
end;
{$POP}

procedure TDigitService.Run;
var
  Waited: integer;
begin
  FServer.Active := True;
  Waited := 0;
  while (FServer.ConnectionCount > 0) and (Waited < 5000) do begin
    Sleep(10);
    Inc(Waited, 10);
  end;
end;

function RunService: integer;
var
  Config: TConfig;
  Service: TDigitService;
begin
  LogInit(EnvOr('AAAS_SERVICE', 'digit-3'), ParseLevel(GetEnvironmentVariable('AAAS_LOG_LEVEL'), llInfo));
  if not LoadConfig(Config) then
    Exit(1);
  fpSignal(SIGTERM, @OnStopSignal);
  fpSignal(SIGINT, @OnStopSignal);
  try
    Service := TDigitService.Create(Config);
  except
    on E: EStoreError do begin
      LogWrite(llError, 'the database cannot be prepared', '', '', E.Message);
      Exit(1);
    end;
  end;
  try
    try
      Service.Run;
    except
      on E: Exception do begin
        LogWrite(llError, 'cannot start the HTTP server', '', '', E.Message);
        Exit(1);
      end;
    end;
    if StopSignal = SIGTERM then
      LogWrite(llInfo, 'shutting down', '', '', 'SIGTERM')
    else
      LogWrite(llInfo, 'shutting down', '', '', 'SIGINT');
  finally
    Service.Free;
  end;
  LogWrite(llInfo, 'stopped');
  Result := 0;
end;

end.
