-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Digits
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         HTTP/JSON client of the ten digit services: the successor
--                  of one decimal digit from GET /next.
-- Related Docs:    contracts/http/digit.yaml, CLAUDE.md 4.4 and 6.1,
--                  services/successor/docs/DEPENDENCIES.md, ADR-0033

-- | Client of the digit services (@digit-0@ … @digit-9@).
--
-- __Description:__ 'askNext' sends @GET /next@ to the service of one
-- digit, whose base URL is the template @AAAS_DIGIT_URL_TEMPLATE@ with
-- @{digit}@ replaced by the digit. Every attempt has a 250 ms response
-- timeout; a failed attempt (connection error, timeout, a status other
-- than 200, or a reply that does not match the contract) is repeated up
-- to three attempts in total, after 50 ms and 100 ms with ±50% jitter.
-- One HTTP connection manager is shared by all calls, so connections are
-- kept alive and reused.
--
-- __Business Justification:__ The digit services own the successor of
-- each digit (CLAUDE.md 1, rule 5, and 4.4); the successor asks them
-- instead of adding natively.
--
-- __Thread Safety:__ safe; the connection manager is thread-safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
module Successor.Digits
  ( DigitClient,
    newDigitClient,
    digitUrl,
    dependencyName,
    parseNextReply,
    askNext,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, fromException)
import Data.Aeson (Value (..), (.:))
import Data.Aeson qualified as Aeson
import Data.Aeson.Types (parseEither, withObject)
import Data.ByteString.Lazy qualified as BL
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import Network.HTTP.Client
  ( HttpException (..),
    Manager,
    ManagerSettings (..),
    Request (..),
    defaultManagerSettings,
    httpLbs,
    newManager,
    parseRequest,
    responseBody,
    responseStatus,
    responseTimeoutMicro,
  )
import Network.HTTP.Types (statusCode)
import Successor.Core (DigitStep (..))
import Successor.Exceptions (trySync)
import Successor.Trace (TraceContext, renderTraceparent)
import System.Random (randomRIO)

-- | A connection manager and the URL template of the digit services.
--
-- __Description:__ Built once at startup by 'newDigitClient'.
--
-- __Business Justification:__ Kept-alive connections keep a successor
-- step at a fraction of a millisecond per digit call.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
data DigitClient = DigitClient
  { -- | Shared HTTP connection manager (250 ms response timeout).
    manager :: Manager,
    -- | Base URL with the placeholder @{digit}@.
    urlTemplate :: Text
  }

-- | Creates the client.
--
-- __Description:__ A connection manager with a 250 ms response timeout
-- per attempt; the template is stored without a trailing slash.
--
-- __Business Justification:__ One client per process (CLAUDE.md 6.1:
-- timeouts on every network call).
--
-- __Parameters:__
--
-- * @template@: @AAAS_DIGIT_URL_TEMPLATE@, for example
--   @http://digit-{digit}:8080@.
--
-- __Returns:__ the client.
--
-- __Errors:__ None (no connection is opened here).
--
-- __Side Effects:__ allocates the connection manager.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__ @client <- newDigitClient "http:\/\/digit-{digit}:8080"@.
--
-- __See Also:__ 'askNext'.
newDigitClient :: Text -> IO DigitClient
newDigitClient template = do
  m <- newManager defaultManagerSettings {managerResponseTimeout = responseTimeoutMicro 250000}
  pure (DigitClient m (Text.dropWhileEnd (== '/') template))

-- | The base URL of the service of one digit.
--
-- __Description:__ Every @{digit}@ of the template is replaced by the
-- decimal text of the digit.
--
-- __Business Justification:__ One setting addresses all ten services.
--
-- __Parameters:__
--
-- * @template@: the URL template.
-- * @digit@: the digit, @0..9@.
--
-- __Returns:__ the base URL.
--
-- __Errors:__ None.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(length of the template).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__
--
-- >>> digitUrl "http://digit-{digit}:8080" 7
-- "http://digit-7:8080"
--
-- __See Also:__ 'newDigitClient'.
digitUrl :: Text -> Int -> Text
digitUrl template digit = Text.replace "{digit}" (Text.pack (show digit)) template

-- | The dependency name of the service of one digit.
--
-- __Description:__ @digit-<d>@: the Compose service name, used in errors,
-- logs and the label of @successor_dependency_failures_total@.
--
-- __Business Justification:__ An operator sees which digit service failed.
--
-- __Parameters:__
--
-- * @digit@: the digit.
--
-- __Returns:__ the name.
--
-- __Errors:__ None.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__
--
-- >>> dependencyName 9
-- "digit-9"
--
-- __See Also:__ 'askNext'.
dependencyName :: Int -> Text
dependencyName digit = "digit-" <> Text.pack (show digit)

-- | Parses and checks the body of @GET /next@.
--
-- __Description:__ The body must be a JSON object with @digit@ equal to
-- the digit asked, @next@ in @0..9@ and the boolean @carry@
-- (@contracts/http/digit.yaml@). Other members are ignored.
--
-- __Business Justification:__ A digit service that answers for another
-- digit, or out of range, must not corrupt an addition.
--
-- __Parameters:__
--
-- * @digit@: the digit that was asked.
-- * @body@: the response body.
--
-- __Returns:__ the 'DigitStep', or a description of the mismatch.
--
-- __Errors:__ @Left@ for invalid JSON, a missing or mistyped member, a
-- different @digit@ or a @next@ outside @0..9@.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(size of the body).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__
--
-- >>> parseNextReply 9 "{\"digit\":9,\"next\":0,\"carry\":true}"
-- Right (DigitStep {stepNext = 0, stepCarry = True})
-- >>> parseNextReply 3 "{\"digit\":4,\"next\":5,\"carry\":false}"
-- Left "the reply is for digit 4"
--
-- __See Also:__ 'askNext'.
parseNextReply :: Int -> BL.ByteString -> Either Text DigitStep
parseNextReply digit body = do
  value <- either (const (Left "the reply is not JSON")) Right (Aeson.eitherDecode body :: Either String Value)
  (replied, successor, carry) <-
    either (const (Left "the reply does not match the digit contract")) Right $
      parseEither (withObject "next" (\o -> (,,) <$> o .: "digit" <*> o .: "next" <*> o .: "carry")) value
  check replied successor carry
  where
    check replied successor carry
      | replied /= digit = Left ("the reply is for digit " <> Text.pack (show replied))
      | successor < 0 || successor > 9 = Left ("the successor digit " <> Text.pack (show successor) <> " is not a digit")
      | otherwise = Right (DigitStep successor carry)

-- | Asks the service of one digit for its successor.
--
-- __Description:__ @GET {base}/next@ with the @traceparent@ of the
-- serving span; see the module documentation for the timeout and the
-- retries.
--
-- __Business Justification:__ One digit of one Peano step.
--
-- __Parameters:__
--
-- * @client@: the client.
-- * @span'@: the serving span, continued in @traceparent@.
-- * @digit@: the digit, @0..9@.
--
-- __Returns:__ the 'DigitStep', or @(dependency, cause)@ after the last
-- attempt, for example @("digit-9", "ConnectionFailure ...")@.
--
-- __Errors:__ @Left@ as described; no exception escapes.
--
-- __Side Effects:__ one to three HTTP requests.
--
-- __Complexity:__ O(1) plus up to three round trips (at most about 0.9 s).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__ @askNext client span' 7@ returns
-- @Right (DigitStep 8 False)@ when @digit-7@ is up.
--
-- __See Also:__ 'Successor.Core.successorVia', 'parseNextReply'.
askNext :: DigitClient -> TraceContext -> Int -> IO (Either (Text, Text) DigitStep)
askNext client span' digit = go (1 :: Int)
  where
    go attemptNo = do
      outcome <- once
      case outcome of
        Right step -> pure (Right step)
        Left cause
          | attemptNo >= 3 -> pure (Left (dependencyName digit, cause))
          | otherwise -> do
              let base = 50000 * 2 ^ (attemptNo - 1) :: Int
              jitter <- randomRIO (base `div` 2, base + base `div` 2)
              threadDelay jitter
              go (attemptNo + 1)
    once = do
      result <- trySync $ do
        base <- parseRequest (Text.unpack (digitUrl (urlTemplate client) digit <> "/next"))
        let req =
              base
                { requestHeaders =
                    [ ("Accept", "application/json"),
                      ("traceparent", TE.encodeUtf8 (renderTraceparent span'))
                    ]
                }
        httpLbs req (manager client)
      pure $ case result of
        Left (e :: SomeException) -> Left (describe e)
        Right resp
          | statusCode (responseStatus resp) /= 200 ->
              Left ("HTTP " <> Text.pack (show (statusCode (responseStatus resp))))
          | otherwise -> parseNextReply digit (responseBody resp)
    describe e = case fromException e of
      Just (HttpExceptionRequest _ content) -> Text.pack (takeWhile (/= '\n') (show content))
      _ -> Text.pack (takeWhile (/= '\n') (show e))
