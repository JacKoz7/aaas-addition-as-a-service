-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Config
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Configuration of the successor service read from
--                  environment variables (bootstrap mode `env`).
-- Related Docs:    services/successor/README.md (Configuration), CLAUDE.md 3
--                  (platform at startup) and 6.1, ADR-0016

-- | Service configuration.
--
-- __Description:__ Until step P5.2 every service reads its configuration
-- from environment variables (@AAAS_BOOTSTRAP=env@); @platform@ is refused
-- until config-server and OpenBao exist. The variables and defaults are
-- listed in the README.
--
-- __Business Justification:__ No hard-coded hosts or passwords (CLAUDE.md
-- 6.1).
--
-- __Thread Safety:__ pure; safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
module Successor.Config
  ( Config (..),
    loadConfig,
    parseAddress,
  )
where

import Data.Text (Text)
import Data.Text qualified as Text
import Successor.Log (Level, parseLevel)
import Text.Read (readMaybe)

-- | The configuration of one successor process.
--
-- __Description:__ One field per environment variable, see the README.
--
-- __Business Justification:__ Everything the process needs to start.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data Config = Config
  { -- | @AAAS_SERVICE@, default @successor@.
    service :: Text,
    -- | @AAAS_ENV@, default @local@.
    environment :: Text,
    -- | @AAAS_HTTP_PORT@, default @8080@.
    httpPort :: Int,
    -- | @AAAS_GRPC_PORT@, default @9090@.
    grpcPort :: Int,
    -- | @AAAS_DIGIT_URL_TEMPLATE@, default @http://digit-{digit}:8080@: the
    -- base URL of each digit service, @{digit}@ replaced by the digit.
    digitUrlTemplate :: Text,
    -- | @AAAS_CARRY_ADDR@, default @carry:9090@, split into host and port.
    carryAddress :: (String, Int),
    -- | @AAAS_KAFKA_BROKERS@, default @redpanda:9092@.
    brokers :: Text,
    -- | @AAAS_DB_URL@, default @http://successor-db:5984@.
    dbUrl :: Text,
    -- | @AAAS_DB_USER@, default @successor@.
    dbUser :: Text,
    -- | @SUCCESSOR_DB_PASSWORD@, required (moves to OpenBao in P5.3).
    dbPassword :: Text,
    -- | @AAAS_MIGRATIONS_DIR@, default @/app/migrations@.
    migrationsDir :: FilePath,
    -- | @AAAS_LOG_LEVEL@, default @info@.
    logLevel :: Level,
    -- | @AAAS_KAFKA_LOG_LEVEL@: librdkafka log level 0..7 (syslog), default
    -- 4 (warning); its lines are written as JSON log lines.
    kafkaLogLevel :: Int
  }
  deriving stock (Eq, Show)

-- | Reads the configuration from a variable lookup.
--
-- __Description:__ Empty values count as unset. @AAAS_BOOTSTRAP@ must be
-- @env@ (the default).
--
-- __Business Justification:__ One validated configuration at startup; a
-- mistake stops the process with a message.
--
-- __Parameters:__
--
-- * @lookupVar@: returns the value of a variable, usually
--   'System.Environment.lookupEnv'.
--
-- __Returns:__ the configuration, or the first error.
--
-- __Errors:__ @Left@ for @AAAS_BOOTSTRAP=platform@ or another mode, a
-- missing @SUCCESSOR_DB_PASSWORD@, a port outside @1..65535@ (or the same
-- port for HTTP and gRPC), a digit URL template without @{digit}@, a
-- carry address that is not @host:port@, an unknown log level or a Kafka
-- log level outside @0..7@.
--
-- __Side Effects:__ None of its own (the lookup is the caller's).
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__
--
-- >>> fmap brokers (loadConfig (\v -> if v == "SUCCESSOR_DB_PASSWORD" then Just "x" else Nothing))
-- Right "redpanda:9092"
--
-- __See Also:__ README, section Configuration.
loadConfig :: (String -> Maybe String) -> Either Text Config
loadConfig lookupVar = do
  case get "AAAS_BOOTSTRAP" "env" of
    "env" -> Right ()
    "platform" ->
      Left
        "AAAS_BOOTSTRAP=platform is not available yet: config-server and OpenBao arrive in steps P5.2 and P5.3; use AAAS_BOOTSTRAP=env"
    other -> Left ("AAAS_BOOTSTRAP: expected env or platform, got " <> Text.pack other)
  port <- case readMaybe (get "AAAS_HTTP_PORT" "8080") of
    Just p | p >= 1 && p <= 65535 -> Right p
    _ -> Left "AAAS_HTTP_PORT: expected a port number"
  rpcPort <- case readMaybe (get "AAAS_GRPC_PORT" "9090") of
    Just p | p >= 1 && p <= 65535 && p /= port -> Right p
    _ -> Left "AAAS_GRPC_PORT: expected a port number other than AAAS_HTTP_PORT"
  template <- case Text.pack (get "AAAS_DIGIT_URL_TEMPLATE" "http://digit-{digit}:8080") of
    t | "{digit}" `Text.isInfixOf` t -> Right t
    _ -> Left "AAAS_DIGIT_URL_TEMPLATE: expected a URL containing {digit}"
  carry <- parseAddress (Text.pack (get "AAAS_CARRY_ADDR" "carry:9090"))
  level <- maybe (Left "AAAS_LOG_LEVEL: expected debug, info, warn, error or fatal") Right (parseLevel (Text.pack (get "AAAS_LOG_LEVEL" "info")))
  kafkaLevel <- case readMaybe (get "AAAS_KAFKA_LOG_LEVEL" "4") of
    Just l | l >= 0 && l <= 7 -> Right l
    _ -> Left "AAAS_KAFKA_LOG_LEVEL: expected 0..7"
  password <- case get "SUCCESSOR_DB_PASSWORD" "" of
    "" -> Left "SUCCESSOR_DB_PASSWORD is required"
    p -> Right (Text.pack p)
  pure
    Config
      { service = Text.pack (get "AAAS_SERVICE" "successor"),
        environment = Text.pack (get "AAAS_ENV" "local"),
        httpPort = port,
        grpcPort = rpcPort,
        digitUrlTemplate = template,
        carryAddress = carry,
        brokers = Text.pack (get "AAAS_KAFKA_BROKERS" "redpanda:9092"),
        dbUrl = Text.pack (get "AAAS_DB_URL" "http://successor-db:5984"),
        dbUser = Text.pack (get "AAAS_DB_USER" "successor"),
        dbPassword = password,
        migrationsDir = get "AAAS_MIGRATIONS_DIR" "/app/migrations",
        logLevel = level,
        kafkaLogLevel = kafkaLevel
      }
  where
    get name def = case lookupVar name of
      Just v | not (null v) -> v
      _ -> def

-- | Splits @host:port@.
--
-- __Description:__ The host is everything before the last colon; the port
-- must be in @1..65535@.
--
-- __Business Justification:__ @AAAS_CARRY_ADDR@ is checked at startup, so
-- a typo stops the service instead of failing every carry.
--
-- __Parameters:__
--
-- * @address@: for example @carry:9090@.
--
-- __Returns:__ @(host, port)@, or an error message.
--
-- __Errors:__ @Left@ without a host or with an invalid port.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(length of the address).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__
--
-- >>> parseAddress "carry:9090"
-- Right ("carry",9090)
-- >>> parseAddress "carry"
-- Left "AAAS_CARRY_ADDR: expected host:port"
--
-- __See Also:__ 'loadConfig', 'Successor.Carry.withCarryClient'.
parseAddress :: Text -> Either Text (String, Int)
parseAddress address = case Text.breakOnEnd ":" address of
  (hostColon, port)
    | Text.length hostColon > 1,
      Just p <- readMaybe (Text.unpack port),
      p >= 1 && p <= 65535 ->
        Right (Text.unpack (Text.dropEnd 1 hostColon), p)
  _ -> Left "AAAS_CARRY_ADDR: expected host:port"
