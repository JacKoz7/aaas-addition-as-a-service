-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Successor.Grpc
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         gRPC interface of the successor service on port 9090:
--                  aaas.successor.v1.SuccessorService/Next.
-- Related Docs:    contracts/proto/aaas/successor/v1/successor.proto,
--                  services/successor/docs/API.md, CLAUDE.md 4.3 and 6.1,
--                  ADR-0020, ADR-0033

-- | The gRPC server (grapesy, plain HTTP/2 without TLS).
--
-- __Description:__ @Next({n, task_id}) → {n}@ is served by
-- 'Successor.Api.serveCall', the handling shared with @POST \/v1\/next@,
-- so both interfaces log, count and answer alike. Statuses
-- (@successor.proto@): @INVALID_ARGUMENT@ when @task_id@ is not a
-- lowercase UUIDv7, @OUT_OF_RANGE@ when @n > 199997@, @UNAVAILABLE@ when
-- CouchDB, a digit service, the carry service or Kafka failed (the call
-- is safe to retry), and @UNAVAILABLE@ for a call that arrives while the
-- service stops. A @traceparent@ metadata entry is continued.
--
-- Exceptions that escape a handler (for example a client that
-- disconnects mid-call) are logged as JSON warn lines instead of
-- grapesy's plain-text default, and their text is never sent to the
-- client.
--
-- The 'Drain' counts calls in progress: on SIGTERM the process stops
-- accepting HTTP connections, refuses new gRPC calls with @UNAVAILABLE@
-- and waits for the calls in progress ('awaitIdle') before it exits.
--
-- __Business Justification:__ The interface of the successor in
-- CLAUDE.md 4.3, called by the saga from P3.3; graceful shutdown within
-- 10 s (CLAUDE.md 6.1).
--
-- __Thread Safety:__ safe; grapesy serves each call on its own thread and
-- the drain state is STM.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
module Successor.Grpc
  ( Drain,
    newDrain,
    startDraining,
    awaitIdle,
    nextHandler,
    withGrpcServer,
  )
where

import Control.Concurrent.STM
  ( TVar,
    atomically,
    check,
    modifyTVar',
    newTVarIO,
    readTVar,
    readTVarIO,
    writeTVar,
  )
import Control.Exception (SomeAsyncException, SomeException, bracket_, catch, fromException, throwIO)
import Data.Aeson qualified as Aeson
import Data.Text (Text)
import Data.Text qualified as Text
import Lens.Family2 ((&), (.~), (^.))
import Network.GRPC.Common (Default (..), GrpcError (..), GrpcException (..), NoMetadata (..))
import Network.GRPC.Common.Protobuf (defMessage)
import Network.GRPC.Server
  ( RpcHandler,
    ServerParams (..),
    getRequestMetadata,
    mkGrpcServer,
    mkRpcHandler,
    recvFinalInput,
    sendFinalOutput,
    sendGrpcException,
    someRpcHandler,
  )
import Network.GRPC.Server.Run (InsecureConfig (..), RunningServer, ServerConfig (..), forkServer)
import Proto.Aaas.Successor.V1.Successor_Fields qualified as Fields
import Successor.Api (Env (..), serveCall)
import Successor.Core (describeError)
import Successor.Identifiers (isUuidV7)
import Successor.Log (Level (..), logMsg)
import Successor.Metrics (countCall)
import Successor.Rpc (Next, TraceMetadata (..))
import Successor.Service (Failure (..), Outcome (..))

-- | The calls in progress and whether the service is stopping.
--
-- __Description:__ Created by 'newDrain', shared by the handler, the
-- signal handler ('startDraining') and the shutdown ('awaitIdle').
--
-- __Business Justification:__ Calls in progress finish instead of being
-- cut off when the container stops.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
data Drain = Drain
  { -- | Number of @Next@ calls in progress.
    inFlight :: TVar Int,
    -- | Whether new calls are refused.
    draining :: TVar Bool
  }

-- | Creates the drain state: no call in progress, accepting calls.
--
-- __Description:__ Two STM variables.
--
-- __Business Justification:__ One per process.
--
-- __Parameters:__ None.
--
-- __Returns:__ the drain state.
--
-- __Errors:__ None.
--
-- __Side Effects:__ allocates the variables.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__ @drain <- newDrain@.
--
-- __See Also:__ 'startDraining', 'awaitIdle'.
newDrain :: IO Drain
newDrain = Drain <$> newTVarIO 0 <*> newTVarIO False

-- | Refuses every new call from now on.
--
-- __Description:__ Calls already in progress continue.
--
-- __Business Justification:__ The first step of a graceful stop.
--
-- __Parameters:__
--
-- * @drain@: the drain state.
--
-- __Returns:__ when the flag is set.
--
-- __Errors:__ None.
--
-- __Side Effects:__ sets the flag.
--
-- __Complexity:__ O(1).
--
-- __Thread Safety:__ safe (STM).
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__ @startDraining drain@ in the SIGTERM handler.
--
-- __See Also:__ 'awaitIdle'.
startDraining :: Drain -> IO ()
startDraining drain = atomically (writeTVar (draining drain) True)

-- | Waits until no call is in progress.
--
-- __Description:__ Blocks (STM retry) while the counter is above zero;
-- the caller bounds the wait with a timeout.
--
-- __Business Justification:__ The last step of a graceful stop.
--
-- __Parameters:__
--
-- * @drain@: the drain state.
--
-- __Returns:__ when idle.
--
-- __Errors:__ None.
--
-- __Side Effects:__ None.
--
-- __Complexity:__ O(1) per change of the counter.
--
-- __Thread Safety:__ safe (STM).
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__ @timeout 8000000 (awaitIdle drain)@.
--
-- __See Also:__ 'startDraining'.
awaitIdle :: Drain -> IO ()
awaitIdle drain = atomically (readTVar (inFlight drain) >>= check . (== 0))

-- | The handler of @Next@.
--
-- __Description:__ Reads the @traceparent@ metadata and the request,
-- checks @task_id@ (counted as @rejected@ when malformed), serves the call
-- with 'Successor.Api.serveCall' and answers the result or the status of
-- the module documentation. While the drain flag is set, the call is
-- refused with @UNAVAILABLE@ before anything else happens.
--
-- __Business Justification:__ @Next@ of CLAUDE.md 4.3.
--
-- __Parameters:__
--
-- * @env@: the environment shared with the HTTP interface.
-- * @drain@: the drain state.
--
-- __Returns:__ the grapesy handler.
--
-- __Errors:__ statuses as described; exceptions of grapesy (a
-- disconnected client) reach the top-level hook of 'withGrpcServer'.
--
-- __Side Effects:__ those of 'Successor.Api.serveCall'.
--
-- __Complexity:__ that of the call.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__ @someRpcHandler (nextHandler env drain)@.
--
-- __See Also:__ 'withGrpcServer'.
nextHandler :: Env -> Drain -> RpcHandler IO Next
nextHandler env drain = mkRpcHandler $ \rpcCall -> do
  stopping <- readTVarIO (draining drain)
  if stopping
    then sendGrpcException rpcCall (status GrpcUnavailable "the successor is stopping; retry the call")
    else bracket_ (atomically (modifyTVar' (inFlight drain) (+ 1))) (atomically (modifyTVar' (inFlight drain) (subtract 1))) $ do
      TraceMetadata parent <- getRequestMetadata rpcCall
      request <- recvFinalInput rpcCall
      let n = toInteger (request ^. Fields.n)
          taskId = request ^. Fields.taskId
      if not (isUuidV7 taskId)
        then do
          countCall (metrics env) "rejected"
          sendGrpcException rpcCall (status GrpcInvalidArgument "task_id must be a lowercase UUIDv7")
        else
          serveCall env n taskId parent >>= \case
            Right outcome ->
              sendFinalOutput rpcCall (defMessage & Fields.n .~ fromInteger (resultOf outcome), NoMetadata)
            Left (InvalidArgument err) -> sendGrpcException rpcCall (status GrpcOutOfRange (describeError err))
            Left (DependencyFailed dependency _) ->
              sendGrpcException rpcCall (status GrpcUnavailable ("the " <> dependency <> " dependency is unavailable; retry the call"))
  where
    resultOf = \case
      Computed r -> r
      Replayed r -> r
    status code message = GrpcException code (Just message) Nothing []

-- | Runs the gRPC server around an action.
--
-- __Description:__ Listens on @0.0.0.0:port@ without TLS (the @services@
-- network is internal, CLAUDE.md 6.2) and serves 'nextHandler'; other
-- methods answer @UNIMPLEMENTED@. The server stops when the action
-- returns. See the module documentation for the exception hook.
--
-- __Business Justification:__ Port 9090 of CLAUDE.md 6.1.
--
-- __Parameters:__
--
-- * @port@: @AAAS_GRPC_PORT@.
-- * @env@: the environment.
-- * @drain@: the drain state.
-- * @action@: runs while the server listens.
--
-- __Returns:__ the result of the action.
--
-- __Errors:__ the exceptions of the action; a port in use fails the
-- listening thread, which the action does not see (the process exits
-- through 'Main' when the HTTP port fails the same way).
--
-- __Side Effects:__ a listening socket; log lines for escaped exceptions.
--
-- __Complexity:__ O(1) plus the action.
--
-- __Thread Safety:__ safe.
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.2.0
--
-- __Example:__ @withGrpcServer 9090 env drain (\\_ -> runSettings settings app)@.
--
-- __See Also:__ 'nextHandler'.
withGrpcServer :: Int -> Env -> Drain -> (RunningServer -> IO a) -> IO a
withGrpcServer port env drain action = do
  server <- mkGrpcServer params [someRpcHandler (nextHandler env drain)]
  forkServer def config server action
  where
    config = ServerConfig {serverInsecure = Just (InsecureConfig Nothing (fromIntegral port)), serverSecure = Nothing}
    params =
      def
        { serverTopLevel = \handler unmask req respond -> handler unmask req respond `catch` logEscaped,
          serverExceptionToClient = \_ -> pure (Just "internal error")
        }
    logEscaped :: SomeException -> IO ()
    logEscaped e = case fromException e of
      Just (_ :: SomeAsyncException) -> throwIO e
      Nothing ->
        logMsg (logger env) Warn Nothing Nothing "grpc call ended with an exception" [("error", Aeson.toJSON (firstLine e))]
    firstLine :: SomeException -> Text
    firstLine e = Text.pack (takeWhile (/= '\n') (show e))
