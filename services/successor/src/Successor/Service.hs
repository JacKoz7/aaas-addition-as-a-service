-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Service
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         Serves one successor call: computes n + 1 through the
--                  digit services and carry, logs the call in CouchDB and
--                  publishes aaas.successor.called.v1.
-- Related Docs:    services/successor/README.md, CLAUDE.md 3 (step 7) and
--                  4.3, ADR-0016, ADR-0033

-- | One successor call, end to end.
--
-- __Description:__ 'call' runs, in order:
--
-- 1. 'Successor.Core.checkArgument' (an argument outside @0..199997@ is
--    rejected, nothing is asked or logged);
-- 2. 'Successor.Core.successorVia' with the digit services and the carry
--    service;
-- 3. the call log ('Successor.CallLog.record'): a new document with the
--    serialized event, or, for a retried call, the stored document, whose
--    result must equal the one just computed;
-- 4. the publication of the event (the new one, or the stored one again,
--    so its @eventId@ never changes).
--
-- A retried call asks the digit services and the carry service again
-- (the carry service answers it from its own log), so a stored result is
-- never replayed without being recomputed (ADR-0033).
--
-- The answer is sent only after the side effects succeeded. Dependencies
-- are passed as functions ('Deps') so that tests run without CouchDB,
-- Kafka, the digit services and the carry service.
--
-- __Business Justification:__ Step 7 of the request flow (CLAUDE.md 3):
-- every successor call is computed by the digit services, logged and
-- announced.
--
-- __Thread Safety:__ safe; concurrent calls share no state here.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
module Successor.Service
  ( Deps (..),
    CallRequest (..),
    Outcome (..),
    Failure (..),
    call,
  )
where

import Control.Exception (SomeException)
import Data.ByteString (ByteString)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import Successor.CallLog (CallRecord (..), RecordResult (..))
import Successor.Core (DigitStep, NextError, checkArgument, successorVia)
import Successor.Event (successorCalled)
import Successor.Exceptions (trySync)
import Successor.Identifiers (formatTimestamp)
import Successor.Trace (TraceContext (..))

-- | The side effects 'call' needs.
--
-- __Description:__ In production: the CouchDB call log, the digit
-- services, the carry service, the Kafka publisher (key, value), the wall
-- clock and the UUIDv7 generator. A failed digit or carry call is
-- @Left (dependency, cause)@.
--
-- __Business Justification:__ Testability without infrastructure.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0 (digits and carry since 0.2.0)
data Deps = Deps
  { -- | Logs a call ('Successor.CallLog.record').
    recordCall :: CallRecord -> IO RecordResult,
    -- | The successor of one digit ('Successor.Digits.askNext').
    askDigit :: TraceContext -> Int -> IO (Either (Text, Text) DigitStep),
    -- | The carry service ('Successor.Carry.propagate'): span, task,
    -- digits, position.
    propagateCarry :: TraceContext -> Text -> [Int] -> Int -> IO (Either (Text, Text) [Int]),
    -- | Publishes an event and waits for the acknowledgement.
    publishEvent :: ByteString -> ByteString -> IO (Either Text ()),
    -- | Current time, Unix milliseconds.
    clock :: IO Integer,
    -- | A new UUIDv7.
    freshId :: IO Text
  }

-- | A validated request.
--
-- __Description:__ The argument, its task and the serving span.
--
-- __Business Justification:__ Input of 'call', built by the HTTP and gRPC
-- layers.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data CallRequest = CallRequest
  { -- | The argument @n@.
    argument :: Integer,
    -- | The task (lowercase UUIDv7).
    task :: Text,
    -- | The context of the serving span.
    servingSpan :: TraceContext
  }
  deriving stock (Eq, Show)

-- | A successful call.
--
-- __Description:__ 'Computed' for a first call, 'Replayed' for a retried
-- call answered from the call log; both carry @n + 1@.
--
-- __Business Justification:__ Metrics distinguish retries.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data Outcome
  = -- | First call: computed, logged and published now.
    Computed Integer
  | -- | Retried call: stored result, stored event published again.
    Replayed Integer
  deriving stock (Eq, Show)

-- | A failed call.
--
-- __Description:__ 'InvalidArgument' for an argument outside the domain;
-- 'DependencyFailed' with the dependency (@couchdb@, @kafka@, @carry@ or
-- @digit-0@ … @digit-9@) and the cause.
--
-- __Business Justification:__ Mapped to 422 and 503 problems (HTTP) and to
-- @OUT_OF_RANGE@ and @UNAVAILABLE@ (gRPC).
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
data Failure
  = -- | The argument is outside @0..199997@.
    InvalidArgument NextError
  | -- | A dependency failed after its retries.
    DependencyFailed Text Text
  deriving stock (Eq, Show)

-- | Serves one call.
--
-- __Description:__ See the module documentation.
--
-- __Business Justification:__ The core use case of the service.
--
-- __Parameters:__
--
-- * @deps@: the side effects.
-- * @req@: the validated request.
--
-- __Returns:__ the 'Outcome', or the 'Failure'.
--
-- __Errors:__ 'InvalidArgument' outside the domain; 'DependencyFailed' if
-- a digit service, the carry service, the call log or the publication
-- fails, or if a stored call has a different result (a corrupted log).
--
-- __Side Effects:__ one digit call and at most one carry call, at most one
-- new document, one Kafka message.
--
-- __Complexity:__ O(d) plus at most five round trips.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
--
-- __Example:__ @call deps (CallRequest 199 task span)@ returns
-- @Right (Computed 200)@, and @Right (Replayed 200)@ when repeated.
--
-- __See Also:__ 'Successor.Api.serveCall', 'Successor.Core.successorVia'.
call :: Deps -> CallRequest -> IO (Either Failure Outcome)
call deps req = case checkArgument (argument req) of
  Left err -> pure (Left (InvalidArgument err))
  Right n -> do
    computed <- successorVia (askDigit deps span') (propagateCarry deps span' (task req)) n
    case computed of
      Left (dependency, cause) -> pure (Left (DependencyFailed dependency cause))
      Right result -> logAndAnnounce n result
  where
    span' = servingSpan req
    logAndAnnounce n result = do
      millis <- clock deps
      eventId <- freshId deps
      let event = successorCalled eventId millis (task req) span' n result
          rec =
            CallRecord
              { recTaskId = task req,
                recN = n,
                recResult = result,
                recEventId = eventId,
                recEvent = TE.decodeUtf8 event,
                recCalledAt = formatTimestamp millis,
                recTraceId = traceId span'
              }
      logged <- trySync (recordCall deps rec)
      case logged of
        Left (e :: SomeException) -> pure (Left (DependencyFailed "couchdb" (firstLine e)))
        Right Recorded -> announce event (Computed result)
        Right (AlreadyRecorded stored)
          | recResult stored /= result ->
              pure (Left (DependencyFailed "couchdb" "stored call has a different result"))
          | otherwise -> announce (TE.encodeUtf8 (recEvent stored)) (Replayed result)
    announce event outcome = do
      sent <- publishEvent deps (TE.encodeUtf8 (task req)) event
      pure $ case sent of
        Left err -> Left (DependencyFailed "kafka" err)
        Right () -> Right outcome
    firstLine e = Text.pack (takeWhile (/= '\n') (show e))
