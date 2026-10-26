-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Carry
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         gRPC client of the carry service
--                  (aaas.carry.v1.CarryService/Propagate) over one
--                  long-lived HTTP/2 connection.
-- Related Docs:    contracts/proto/aaas/carry/v1/carry.proto, CLAUDE.md 4.3
--                  and 6.1, services/successor/docs/DEPENDENCIES.md,
--                  ADR-0032, ADR-0033

-- | Client of @carry@.
--
-- __Description:__ 'withCarryClient' opens one HTTP/2 connection to
-- @AAAS_CARRY_ADDR@ (grapesy, @TCP_NODELAY@ on) that every call shares.
-- When the connection is lost or cannot be established, grapesy connects
-- again after 100 to 200 ms, without limit; a call made meanwhile waits
-- for the connection. 'propagate' bounds each call: the whole call,
-- including its retries, has a deadline of 2 s; an attempt that fails
-- with @UNAVAILABLE@ or a lost connection is repeated, up to three
-- attempts, after 50 ms and 100 ms with ±50% jitter. Other statuses are
-- final: @INVALID_ARGUMENT@ means the request was wrong, and the carry
-- service already retried its digit services within its own budget.
--
-- __Business Justification:__ A successor whose units digit is 9 needs
-- the carry service for the higher digits (CLAUDE.md 3, step 7); every
-- network call has a timeout and retries (CLAUDE.md 6.1).
--
-- __Thread Safety:__ safe; HTTP/2 multiplexes concurrent calls on the
-- connection.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
module Successor.Carry
  ( CarryClient,
    withCarryClient,
    checkDigits,
    propagate,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, fromException)
import Data.Foldable (toList)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Word (Word32)
import Lens.Family2 ((&), (.~), (^.))
import Network.GRPC.Client
  ( Address (..),
    CallParams,
    ConnParams (..),
    Connection,
    Reconnect (..),
    ReconnectDecision (..),
    ReconnectPolicy (..),
    ReconnectTo (..),
    Server (..),
    ServerDisconnected,
    callRequestMetadata,
    rpcWith,
    withConnection,
  )
import Network.GRPC.Client.StreamType.IO (nonStreaming)
import Network.GRPC.Common (Default (..), GrpcError (..), GrpcException (..))
import Network.GRPC.Common.Protobuf (Proto, defMessage)
import Proto.Aaas.Carry.V1.Carry (PropagateRequest)
import Proto.Aaas.Carry.V1.Carry_Fields qualified as Fields
import Successor.Exceptions (trySync)
import Successor.Rpc (Propagate, TraceMetadata (..))
import Successor.Trace (TraceContext)
import System.Random (randomRIO)
import System.Timeout (timeout)

-- | The connection to the carry service.
--
-- __Description:__ Valid inside 'withCarryClient' only.
--
-- __Business Justification:__ One connection per process; no handshake
-- per successor call.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
newtype CarryClient = CarryClient Connection

-- | Runs an action with a connection to the carry service.
--
-- __Description:__ See the module documentation for the reconnection
-- policy. The connection is closed when the action returns or throws.
-- Nothing is sent before the first call, so the service starts while the
-- carry service is still down.
--
-- __Business Justification:__ The process lifetime of the connection.
--
-- __Parameters:__
--
-- * @host@, @port@: the address of the carry service
--   ('Successor.Config.carryAddress').
-- * @action@: the rest of the program.
--
-- __Returns:__ the result of the action.
--
-- __Errors:__ the exceptions of the action.
--
-- __Side Effects:__ TCP connections to the carry service, from the first
-- call on.
--
-- __Complexity:__ O(1) plus the action.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__ @withCarryClient "carry" 9090 (\\client -> serve client)@.
--
-- __See Also:__ 'propagate'.
withCarryClient :: String -> Int -> (CarryClient -> IO a) -> IO a
withCarryClient host port action =
  withConnection params server (action . CarryClient)
  where
    server = ServerInsecure (Address host (fromIntegral port) Nothing)
    params = def {connReconnectPolicy = reconnectForever}
    reconnectForever = ReconnectPolicy $ do
      randomRIO (100000, 200000) >>= threadDelay
      pure (DoReconnect (Reconnect ReconnectToOriginal Nothing reconnectForever))

-- | Checks the digits answered by the carry service.
--
-- __Description:__ The answer must have one to seven digits, each in
-- @0..9@ (the request has at most six; one more when the carry passed the
-- highest digit).
--
-- __Business Justification:__ A wrong answer must not become a wrong sum.
--
-- __Parameters:__
--
-- * @digits@: the answer, least significant first.
--
-- __Returns:__ the digits, or a description of the defect.
--
-- __Errors:__ @Left@ for an empty, too long or out-of-range answer.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(d).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__
--
-- >>> checkDigits [0, 0, 0, 1]
-- Right [0,0,0,1]
-- >>> checkDigits [0, 12]
-- Left "the carry service answered a digit outside 0..9"
--
-- __See Also:__ 'propagate'.
checkDigits :: [Word32] -> Either Text [Int]
checkDigits digits
  | null digits || length digits > 7 = Left "the carry service answered an invalid number of digits"
  | any (> 9) digits = Left "the carry service answered a digit outside 0..9"
  | otherwise = Right (map fromIntegral digits)

-- | Asks the carry service to add a carry.
--
-- __Description:__ Sends @Propagate(digits, position, taskId)@ with the
-- @traceparent@ of the serving span; see the module documentation for the
-- deadline and the retries. The answer is checked by 'checkDigits'.
--
-- __Business Justification:__ The higher digits of a successor step.
--
-- __Parameters:__
--
-- * @client@: the connection.
-- * @span'@: the serving span, continued in the metadata.
-- * @task@: the task identifier (UUIDv7).
-- * @digits@: the digits, least significant first, each in @0..9@.
-- * @position@: the index that receives the carry.
--
-- __Returns:__ the new digits, or @("carry", cause)@.
--
-- __Errors:__ @Left@ after the deadline, after the last attempt, for a
-- final gRPC status, or for an invalid answer; no exception escapes.
--
-- __Side Effects:__ one to three gRPC calls; the carry service records
-- the propagation and publishes @aaas.carry.propagated.v1@.
--
-- __Complexity:__ O(d) plus up to three round trips (at most 2 s).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__ @propagate client span' task [0, 9, 9] 1@ returns
-- @Right [0, 0, 0, 1]@ (999 + 1).
--
-- __See Also:__ 'Successor.Core.successorVia', CLAUDE.md 4.3 (@Propagate@).
propagate :: CarryClient -> TraceContext -> Text -> [Int] -> Int -> IO (Either (Text, Text) [Int])
propagate (CarryClient conn) span' task digits position = do
  outcome <- timeout 2000000 (go (1 :: Int))
  pure $ case outcome of
    Nothing -> Left ("carry", "no answer within 2 s")
    Just (Left cause) -> Left ("carry", cause)
    Just (Right answer) -> Right answer
  where
    request :: Proto PropagateRequest
    request =
      defMessage
        & Fields.digits .~ map fromIntegral digits
        & Fields.position .~ fromIntegral position
        & Fields.taskId .~ task
    params :: CallParams Propagate
    params = def {callRequestMetadata = TraceMetadata (Just span')}
    go attemptNo = do
      result <- trySync (nonStreaming conn (rpcWith @Propagate params) request)
      case result of
        Right reply -> pure (checkDigits (toList (reply ^. Fields.digits)))
        Left (e :: SomeException)
          | transient e && attemptNo < 3 -> do
              let base = 50000 * 2 ^ (attemptNo - 1) :: Int
              randomRIO (base `div` 2, base + base `div` 2) >>= threadDelay
              go (attemptNo + 1)
          | otherwise -> pure (Left (describe e))
    transient e = case fromException e of
      Just GrpcException {grpcError = GrpcUnavailable} -> True
      Just GrpcException {} -> False
      Nothing -> case fromException e of
        Just (_ :: ServerDisconnected) -> True
        Nothing -> False
    describe e = case fromException e of
      Just GrpcException {grpcError, grpcErrorMessage} ->
        Text.pack (show grpcError) <> maybe "" (": " <>) grpcErrorMessage
      Nothing -> Text.pack (takeWhile (/= '\n') (show e))
