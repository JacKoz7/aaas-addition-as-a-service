-- SPDX-License-Identifier: MIT
-- Copyright (c) 2026 AaaS Contributors
--
-- Component:       successor
-- Module:          Main (tests/Spec.hs)
-- Owning Team:     Arithmetic Excellence Center (AEC)
-- Classification:  INTERNAL
-- Purpose:         hspec suite of the successor service: the digit-based
--                  successor, identifiers, events, the call service with
--                  fake dependencies, the digit client against an
--                  in-process digit service, the gRPC interface and the
--                  carry client against an in-process carry service, the
--                  HTTP interface, configuration and, with COUCHDB_URL
--                  set, the CouchDB call log.
-- Related Docs:    services/successor/README.md (Running and testing),
--                  ADR-0016, ADR-0033

-- | Unit and integration tests of the successor.
--
-- __Description:__ The pure modules and the HTTP application are tested
-- with fake dependencies; the digit client, the carry client and the gRPC
-- server are tested over real sockets against in-process fakes of the
-- digit and carry services (warp and grapesy on ephemeral ports). When
-- @COUCHDB_URL@ is set (the Makefile starts a
-- throw-away CouchDB container for that), the call log is tested against
-- a real database. When @PRODUCED_DIR@ is set, every event the fake
-- publisher receives is written there; the Dockerfile test stage then
-- validates the files against their JSON Schema.
--
-- __Business Justification:__ @make test-successor@ (CLAUDE.md 6.3).
--
-- __Owner:__ Arithmetic Excellence Center (AEC).
--
-- __Since:__ successor 0.1.0
module Main (main) where

import Control.Exception (try)
import Control.Monad (forM_, (>=>))
import Data.Aeson (Value (..), decode, encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Bifunctor (first)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as BL
import Data.CaseInsensitive qualified as CI
import Data.IORef (IORef, atomicModifyIORef', modifyIORef', newIORef, readIORef, writeIORef)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TE
import Lens.Family2 ((&), (.~), (^.))
import Network.GRPC.Client qualified as Client
import Network.GRPC.Client.StreamType.IO qualified as Client
import Network.GRPC.Common (CustomMetadata (..), Default (..), GrpcError (..), GrpcException (..), HeaderName (..), NoMetadata (..), ParseMetadata (..))
import Network.GRPC.Common.Protobuf (defMessage)
import Network.GRPC.Server qualified as Server
import Network.GRPC.Server.Run (InsecureConfig (..), ServerConfig (..), forkServer, getServerPort)
import Network.HTTP.Types (hContentType, methodGet, methodPost, status200, status404)
import Network.Wai (Request (..), responseLBS)
import Network.Wai qualified as Wai
import Network.Wai.Handler.Warp qualified as Warp
import Network.Wai.Test
  ( SRequest (..),
    SResponse (..),
    defaultRequest,
    request,
    runSession,
    setPath,
    srequest,
  )
import Proto.Aaas.Carry.V1.Carry_Fields qualified as CarryFields
import Proto.Aaas.Successor.V1.Successor_Fields qualified as NextFields
import Successor.Api (Env (..), application)
import Successor.CallLog
  ( CallRecord (..),
    RecordResult (..),
    documentId,
    migrate,
    newCallLog,
    ping,
    record,
  )
import Successor.Carry (checkDigits, propagate, withCarryClient)
import Successor.Config (Config (..), loadConfig, parseAddress)
import Successor.Core (DigitStep (..), NextError (..), checkArgument, fromDigits, maxArgument, successorVia, toDigits)
import Successor.Digits (askNext, newDigitClient, parseNextReply)
import Successor.Event (successorCalled)
import Successor.Grpc (awaitIdle, newDrain, startDraining, withGrpcServer)
import Successor.Identifiers (formatTimestamp, isUuid, isUuidV7, newUuidV7, uuidV7FromParts)
import Successor.Log (Level (..), newLogger, renderLine)
import Successor.Metrics (Metrics, newMetrics, render)
import Successor.Rpc (Next, Propagate, TraceMetadata (..))
import Successor.Service (CallRequest (..), Deps (..), Failure (..), Outcome (..), call)
import Successor.Trace (TraceContext (..), childSpan, parseTraceparent, renderTraceparent)
import System.Directory (createDirectoryIfMissing)
import System.Environment (lookupEnv)
import System.FilePath ((</>))
import System.Timeout (timeout)
import Test.Hspec

-- | A valid sampleTask identifier used throughout the tests.
sampleTask :: Text
sampleTask = "018f3c2e-7b1a-7c3d-9f00-0000000000aa"

-- | The parent trace of the CLAUDE.md example.
parentTrace :: TraceContext
parentTrace = TraceContext "4bf92f3577b34da6a3ce929d0e0e4736" "00f067aa0ba902b7" "01"

-- | The answers of the ten digit services (CLAUDE.md 4.4).
digitTable :: Int -> DigitStep
digitTable d = DigitStep (if d == 9 then 0 else d + 1) (d == 9)

-- | The carry service, as the test oracle: adds one at a position.
carryOracle :: [Int] -> Int -> [Int]
carryOracle digits position = case splitAt position digits of
  (low, []) -> low ++ [1]
  (low, d : high)
    | d == 9 -> carryOracle (low ++ 0 : high) (position + 1)
    | otherwise -> low ++ (d + 1) : high

-- | Fake dependencies: an in-memory call log, the digit table, the carry
-- oracle and a recording publisher.
--
-- __Description:__ Returns the 'Deps', the published @(key, value)@
-- pairs (newest first), a switch that makes the next publications fail
-- and the number of digit and carry calls made.
fakeDeps :: IO (Deps, IORef [(BS.ByteString, BS.ByteString)], IORef Bool, IORef (Int, Int))
fakeDeps = do
  store <- newIORef (Map.empty :: Map.Map Text CallRecord)
  sent <- newIORef []
  failing <- newIORef False
  asked <- newIORef (0, 0)
  produced <- lookupEnv "PRODUCED_DIR"
  let recordFake rec = atomicModifyIORef' store $ \m ->
        let key = documentId (recTaskId rec) (recN rec)
         in case Map.lookup key m of
              Just stored -> (m, AlreadyRecorded stored)
              Nothing -> (Map.insert key rec m, Recorded)
      digitFake _ d = do
        modifyIORef' asked (first (+ 1))
        pure (Right (digitTable d))
      carryFake _ _ digits position = do
        modifyIORef' asked (fmap (+ 1))
        pure (Right (carryOracle digits position))
      publishFake key value = do
        broken <- readIORef failing
        if broken
          then pure (Left "broker down")
          else do
            modifyIORef' sent ((key, value) :)
            forM_ produced $ \dir -> do
              createDirectoryIfMissing True dir
              name <- newUuidV7
              BS.writeFile (dir </> Text.unpack name <> ".json") value
            pure (Right ())
  pure (Deps recordFake digitFake carryFake publishFake (pure 1792152000000) newUuidV7, sent, failing, asked)

-- | The application with fake dependencies and the shared metrics.
testEnv :: Metrics -> Deps -> [(Text, IO Bool)] -> IO Env
testEnv metrics deps checks = do
  logger <- newLogger "successor" Fatal
  pure (Env deps logger metrics checks render)

-- | POSTs a JSON body to @/v1/next@.
postNext :: Env -> [(BS.ByteString, BS.ByteString)] -> BL.ByteString -> IO SResponse
postNext env headers body =
  runSession
    (srequest (SRequest (setPath defaultRequest {requestMethod = methodPost, requestHeaders = (hContentType, "application/json") : map (first CI.mk) headers} "/v1/next") body))
    (application env)

-- | GETs a path.
getPath :: Env -> BS.ByteString -> IO SResponse
getPath env path = runSession (request (setPath defaultRequest {requestMethod = methodGet} path)) (application env)

-- | Reads a JSON field of a response body.
field :: Text -> SResponse -> Maybe Value
field name resp = case decode (simpleBody resp) of
  Just (Object o) -> KeyMap.lookup (Key.fromText name) o
  _ -> Nothing

-- | Runs a WAI application on an ephemeral port of 127.0.0.1.
withWarp :: Wai.Application -> (Int -> IO a) -> IO a
withWarp app = Warp.withApplicationSettings (Warp.setHost "127.0.0.1" Warp.defaultSettings) (pure app)

-- | The ten digit services on one port: @GET /d\<digit\>/next@ answers the
-- digit table, or the body given for a digit; requests are counted and
-- their @traceparent@ headers kept.
fakeDigitServices :: IORef [Maybe BS.ByteString] -> Map.Map Int BL.ByteString -> Wai.Application
fakeDigitServices seen overrides req respond = do
  modifyIORef' seen (lookup "traceparent" (Wai.requestHeaders req) :)
  case Wai.pathInfo req of
    [name, "next"]
      | Just digitText <- Text.stripPrefix "d" name,
        [(digit, "")] <- reads (Text.unpack digitText) ->
          respond (responseLBS status200 [(hContentType, "application/json")] (fromMaybe (reply digit) (Map.lookup digit overrides)))
    _ -> respond (responseLBS status404 [] "")
  where
    reply d = let DigitStep n c = digitTable d in encode (object ["digit" .= d, "next" .= n, "carry" .= c])

-- | A carry service on 127.0.0.1 (grapesy) that answers the oracle and
-- records the traceparent it received.
withFakeCarry :: IORef (Maybe TraceContext) -> (Int -> IO a) -> IO a
withFakeCarry seen action = do
  server <- Server.mkGrpcServer def [Server.someRpcHandler handler]
  forkServer def (ServerConfig (Just (InsecureConfig (Just "127.0.0.1") 0)) Nothing) server $
    getServerPort >=> (action . fromIntegral)
  where
    handler :: Server.RpcHandler IO Propagate
    handler = Server.mkRpcHandler $ \rpcCall -> do
      TraceMetadata parent <- Server.getRequestMetadata rpcCall
      writeIORef seen parent
      req <- Server.recvFinalInput rpcCall
      let digits = map fromIntegral (req ^. CarryFields.digits)
          answer = carryOracle digits (fromIntegral (req ^. CarryFields.position))
      Server.sendFinalOutput rpcCall (defMessage & CarryFields.digits .~ map fromIntegral answer, NoMetadata)

-- | Runs every spec.
main :: IO ()
main = do
  metrics <- newMetrics "test"
  couch <- lookupEnv "COUCHDB_URL"
  migrations <- fromMaybe "migrations" <$> lookupEnv "MIGRATIONS_DIR"
  hspec $ do
    describe "Core" $ do
      it "checks the domain" $ do
        checkArgument 0 `shouldBe` Right 0
        checkArgument maxArgument `shouldBe` Right maxArgument
        checkArgument (-1) `shouldBe` Left (Negative (-1))
        checkArgument 199998 `shouldBe` Left (AboveRange 199998)
      it "converts every possible number to digits and back" $
        forM_ [0 .. 199998] $
          \n -> fromDigits (toDigits n) `shouldBe` n
      it "computes n + 1 for the whole domain from the digit table and the carry" $
        forM_ [0 .. maxArgument] $ \n ->
          successorVia (Just . Right . digitTable) (\ds p -> Just (Right (carryOracle ds p))) n
            `shouldBe` (Just (Right (n + 1)) :: Maybe (Either () Integer))
      it "calls the carry only when the units digit is 9" $ do
        let run n = successorVia (\d -> ([d], Right (digitTable d))) (\ds p -> ([-1], Right (carryOracle ds p))) n :: ([Int], Either () Integer)
        run 1208 `shouldBe` ([8], Right 1209)
        run 1209 `shouldBe` ([9, -1], Right 1210)
        run 99999 `shouldBe` ([9, -1], Right 100000)
      it "returns the failure of a digit or of the carry" $ do
        successorVia (\_ -> Just (Left "digit-7")) (\_ _ -> Just (Right [])) 7 `shouldBe` Just (Left "digit-7" :: Either String Integer)
        successorVia (Just . Right . digitTable) (\_ _ -> Just (Left "carry")) 19 `shouldBe` Just (Left "carry" :: Either String Integer)

    describe "Digits" $ do
      it "parses the replies of the contract" $ do
        parseNextReply 7 "{\"digit\":7,\"next\":8,\"carry\":false}" `shouldBe` Right (DigitStep 8 False)
        parseNextReply 9 "{\"digit\":9,\"next\":0,\"carry\":true,\"extra\":1}" `shouldBe` Right (DigitStep 0 True)
        forM_ ["", "[]", "{\"digit\":7,\"next\":8}", "{\"digit\":7,\"next\":10,\"carry\":false}", "{\"digit\":6,\"next\":7,\"carry\":false}"] $ \body ->
          either (const True) (const False) (parseNextReply 7 body) `shouldBe` True
      it "asks the service of each digit over HTTP with the trace" $ do
        seen <- newIORef []
        withWarp (fakeDigitServices seen Map.empty) $ \port -> do
          client <- newDigitClient ("http://127.0.0.1:" <> Text.pack (show port) <> "/d{digit}/")
          forM_ [0 .. 9] $ \d -> askNext client parentTrace d `shouldReturn` Right (digitTable d)
          traces <- readIORef seen
          traces `shouldBe` replicate 10 (Just (TE.encodeUtf8 (renderTraceparent parentTrace)))
      it "retries a reply that breaks the contract three times" $ do
        seen <- newIORef []
        withWarp (fakeDigitServices seen (Map.fromList [(3, "{\"digit\":4,\"next\":5,\"carry\":false}")])) $ \port -> do
          client <- newDigitClient ("http://127.0.0.1:" <> Text.pack (show port) <> "/d{digit}")
          askNext client parentTrace 3 `shouldReturn` Left ("digit-3", "the reply is for digit 4")
          (length <$> readIORef seen) `shouldReturn` 3
      it "retries three times and names the failed digit service" $ do
        client <- newDigitClient "http://127.0.0.1:1/digit-{digit}"
        span' <- childSpan Nothing
        result <- askNext client span' 3
        fmap fst (either Just (const Nothing) result) `shouldBe` Just "digit-3"

    describe "Carry" $ do
      it "checks the answer" $ do
        checkDigits [0, 0, 1] `shouldBe` Right [0, 0, 1]
        forM_ [[], [10], replicate 8 0] $ \ds -> either (const True) (const False) (checkDigits ds) `shouldBe` True
      it "propagates through a gRPC carry service and passes the trace" $ do
        seen <- newIORef Nothing
        withFakeCarry seen $ \port ->
          withCarryClient "127.0.0.1" port $ \client -> do
            propagate client parentTrace sampleTask [0, 9, 9] 1 `shouldReturn` Right [0, 0, 0, 1]
            propagate client parentTrace sampleTask [0, 1] 1 `shouldReturn` Right [0, 2]
            readIORef seen `shouldReturn` Just parentTrace
      it "gives up after its deadline when the carry service is down" $
        withCarryClient "127.0.0.1" 1 $ \client -> do
          result <- timeout 3000000 (propagate client parentTrace sampleTask [0] 1)
          result `shouldBe` Just (Left ("carry", "no answer within 2 s"))

    describe "Identifiers" $ do
      it "lays out a UUIDv7" $ do
        uuidV7FromParts 0x018f3c2e7b1a (BS.replicate 10 0) `shouldBe` Just "018f3c2e-7b1a-7000-8000-000000000000"
        uuidV7FromParts 0x018f3c2e7b1a (BS.replicate 10 255) `shouldBe` Just "018f3c2e-7b1a-7fff-bfff-ffffffffffff"
        uuidV7FromParts 0 "short" `shouldBe` Nothing
      it "generates unique version 7 identifiers" $ do
        a <- newUuidV7
        b <- newUuidV7
        a `shouldNotBe` b
        isUuid a `shouldBe` True
        isUuidV7 a `shouldBe` True
      it "recognizes only version 7 with the RFC 9562 variant" $ do
        isUuidV7 "018f3c2e-7b1a-4c3d-9f00-0000000000aa" `shouldBe` False
        isUuidV7 "018f3c2e-7b1a-7c3d-cf00-0000000000aa" `shouldBe` False
        isUuidV7 "018F3C2E-7B1A-7C3D-9F00-0000000000AA" `shouldBe` False
      it "formats timestamps" $ do
        formatTimestamp 1792152000000 `shouldBe` "2026-10-16T12:00:00.000Z"
        formatTimestamp 1835481599999 `shouldBe` "2028-02-29T23:59:59.999Z"

    describe "Trace" $ do
      it "parses and renders traceparent" $ do
        let value = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
        (renderTraceparent <$> parseTraceparent value) `shouldBe` Just value
        forM_ ["", "01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01", "00-4BF92F3577B34DA6A3CE929D0E0E4736-00f067aa0ba902b7-01", "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01"] $ \v ->
          parseTraceparent v `shouldBe` Nothing
      it "continues the parent trace with a new span" $ do
        child <- childSpan (Just parentTrace)
        traceId child `shouldBe` traceId parentTrace
        spanId child `shouldNotBe` spanId parentTrace
        root <- childSpan Nothing
        parseTraceparent (renderTraceparent root) `shouldBe` Just root
      it "reads traceparent from gRPC metadata and ignores everything else" $ do
        let entry = CustomMetadata (AsciiHeader "traceparent") (TE.encodeUtf8 (renderTraceparent parentTrace))
            other = CustomMetadata (AsciiHeader "x-other") "1"
        parseMetadata [other, entry] `shouldReturn` TraceMetadata (Just parentTrace)
        parseMetadata [CustomMetadata (AsciiHeader "traceparent") "garbage"] `shouldReturn` TraceMetadata Nothing
        parseMetadata [] `shouldReturn` TraceMetadata Nothing

    describe "Event" $
      it "serializes the envelope in specification order" $ do
        let bytes = successorCalled "018f3c2e-7b1a-7c3d-9f00-000000000020" 1792152001250 sampleTask parentTrace 3 4
        bytes
          `shouldBe` TE.encodeUtf8
            "{\"eventId\":\"018f3c2e-7b1a-7c3d-9f00-000000000020\",\"type\":\"aaas.successor.called\",\"version\":1,\"occurredAt\":\"2026-10-16T12:00:01.250Z\",\"producer\":\"successor\",\"taskId\":\"018f3c2e-7b1a-7c3d-9f00-0000000000aa\",\"traceparent\":\"00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01\",\"payload\":{\"n\":3,\"result\":4}}"

    describe "Service.call" $ do
      it "computes through the digits and the carry, logs and publishes" $ do
        (deps, sent, _, asked) <- fakeDeps
        call deps (CallRequest 199 sampleTask parentTrace) `shouldReturn` Right (Computed 200)
        readIORef asked `shouldReturn` (1, 1)
        call deps (CallRequest 200 sampleTask parentTrace) `shouldReturn` Right (Computed 201)
        readIORef asked `shouldReturn` (2, 1)
        published <- readIORef sent
        map fst published `shouldBe` replicate 2 (TE.encodeUtf8 sampleTask)
      it "recomputes a retried call and publishes the identical stored event" $ do
        (deps, sent, _, asked) <- fakeDeps
        _ <- call deps (CallRequest 41 sampleTask parentTrace)
        call deps (CallRequest 41 sampleTask parentTrace) `shouldReturn` Right (Replayed 42)
        readIORef asked `shouldReturn` (2, 0)
        published <- readIORef sent
        case published of
          [(_, retried), (_, original)] -> retried `shouldBe` original
          _ -> expectationFailure "two messages expected"
      it "refuses to replay a stored call whose result differs" $ do
        (deps, sent, _, _) <- fakeDeps
        let tampered = deps {recordCall = \rec -> pure (AlreadyRecorded rec {recResult = 43})}
        call tampered (CallRequest 41 sampleTask parentTrace) `shouldReturn` Left (DependencyFailed "couchdb" "stored call has a different result")
        readIORef sent `shouldReturn` []
      it "does not ask, log or publish an invalid argument" $ do
        (deps, sent, _, asked) <- fakeDeps
        call deps (CallRequest 199998 sampleTask parentTrace) `shouldReturn` Left (InvalidArgument (AboveRange 199998))
        readIORef sent `shouldReturn` []
        readIORef asked `shouldReturn` (0, 0)
      it "reports a digit service or carry failure by name, and logs nothing" $ do
        (deps, sent, _, _) <- fakeDeps
        let noDigit = deps {askDigit = \_ d -> pure (Left ("digit-" <> Text.pack (show d), "down"))}
            noCarry = deps {propagateCarry = \_ _ _ _ -> pure (Left ("carry", "down"))}
        call noDigit (CallRequest 9 sampleTask parentTrace) `shouldReturn` Left (DependencyFailed "digit-9" "down")
        call noCarry (CallRequest 9 sampleTask parentTrace) `shouldReturn` Left (DependencyFailed "carry" "down")
        call deps (CallRequest 9 sampleTask parentTrace) `shouldReturn` Right (Computed 10)
        (length <$> readIORef sent) `shouldReturn` 1
      it "reports a publication failure, and a retry publishes the stored event" $ do
        (deps, sent, failing, _) <- fakeDeps
        modifyIORef' failing (const True)
        call deps (CallRequest 7 sampleTask parentTrace) `shouldReturn` Left (DependencyFailed "kafka" "broker down")
        modifyIORef' failing (const False)
        call deps (CallRequest 7 sampleTask parentTrace) `shouldReturn` Right (Replayed 8)
        (length <$> readIORef sent) `shouldReturn` 1
      it "reports a call log failure" $ do
        (deps, _, _, _) <- fakeDeps
        let broken = deps {recordCall = \_ -> ioError (userError "couchdb down")}
        result <- call broken (CallRequest 1 sampleTask parentTrace)
        case result of
          Left (DependencyFailed "couchdb" _) -> pure ()
          other -> expectationFailure (show other)

    describe "Grpc" $ do
      let withNext deps body = do
            env <- testEnv metrics deps []
            drain <- newDrain
            withGrpcServer 0 env drain $ \running -> do
              port <- getServerPort running
              Client.withConnection def (Client.ServerInsecure (Client.Address "127.0.0.1" port Nothing)) (body drain)
          next conn n task =
            Client.nonStreaming conn (Client.rpcWith @Next def {Client.callRequestMetadata = TraceMetadata (Just parentTrace)}) $
              defMessage & NextFields.n .~ n & NextFields.taskId .~ task
          statusOf action = either (Just . grpcError) (const Nothing) <$> tryGrpc action
          tryGrpc :: IO a -> IO (Either GrpcException a)
          tryGrpc = try
      it "serves Next and continues the trace" $ do
        (deps, sent, _, _) <- fakeDeps
        withNext deps $ \_ conn -> do
          reply <- next conn 99999 sampleTask
          reply ^. NextFields.n `shouldBe` 100000
        published <- readIORef sent
        case published of
          [(_, value)] -> BS.isInfixOf (TE.encodeUtf8 (traceId parentTrace)) value `shouldBe` True
          _ -> expectationFailure "one message expected"
      it "answers the statuses of the contract" $ do
        (deps, _, failing, _) <- fakeDeps
        withNext deps $ \drain conn -> do
          statusOf (next conn 199998 sampleTask) `shouldReturn` Just GrpcOutOfRange
          statusOf (next conn 1 "018f3c2e-7b1a-4c3d-9f00-0000000000aa") `shouldReturn` Just GrpcInvalidArgument
          statusOf (next conn 1 "") `shouldReturn` Just GrpcInvalidArgument
          writeIORef failing True
          statusOf (next conn 1 sampleTask) `shouldReturn` Just GrpcUnavailable
          writeIORef failing False
          startDraining drain
          statusOf (next conn 2 sampleTask) `shouldReturn` Just GrpcUnavailable
          awaitIdle drain

    describe "Api" $ do
      it "answers POST /v1/next with n + 1 and continues the trace" $ do
        (deps, sent, _, _) <- fakeDeps
        env <- testEnv metrics deps []
        resp <- postNext env [("traceparent", TE.encodeUtf8 (renderTraceparent parentTrace))] (encode (object ["n" .= (2 :: Int), "taskId" .= sampleTask]))
        simpleStatus resp `shouldBe` status200
        field "n" resp `shouldBe` Just (Number 3)
        published <- readIORef sent
        case published of
          [(_, value)] -> BS.isInfixOf (TE.encodeUtf8 (traceId parentTrace)) value `shouldBe` True
          _ -> expectationFailure "one message expected"
      it "refuses malformed requests with problems" $ do
        (deps, _, _, _) <- fakeDeps
        env <- testEnv metrics deps []
        let cases =
              [ ("not json", 400),
                ("{\"n\":2.5,\"taskId\":\"018f3c2e-7b1a-7c3d-9f00-0000000000aa\"}", 400),
                ("{\"n\":2,\"taskId\":\"X\"}", 422),
                ("{\"n\":2,\"taskId\":\"018f3c2e-7b1a-4c3d-9f00-0000000000aa\"}", 422),
                ("{\"n\":199998,\"taskId\":\"018f3c2e-7b1a-7c3d-9f00-0000000000aa\"}", 422),
                ("{\"n\":-1,\"taskId\":\"018f3c2e-7b1a-7c3d-9f00-0000000000aa\"}", 422)
              ]
        forM_ cases $ \(body, code) -> do
          resp <- postNext env [] body
          lookup hContentType (simpleHeaders resp) `shouldBe` Just "application/problem+json"
          field "status" resp `shouldBe` Just (Number code)
      it "maps a dependency failure to 503" $ do
        (deps, _, failing, _) <- fakeDeps
        modifyIORef' failing (const True)
        env <- testEnv metrics deps []
        resp <- postNext env [] (encode (object ["n" .= (2 :: Int), "taskId" .= sampleTask]))
        field "status" resp `shouldBe` Just (Number 503)
      it "reports health and metrics" $ do
        (deps, _, _, _) <- fakeDeps
        ok <- testEnv metrics deps [("database", pure True), ("broker", pure True)]
        bad <- testEnv metrics deps [("database", pure True), ("broker", pure False)]
        healthy <- getPath ok "/health"
        simpleBody healthy `shouldBe` "{\"checks\":{\"broker\":\"ok\",\"database\":\"ok\"},\"status\":\"ok\"}"
        unhealthy <- getPath bad "/health"
        field "status" unhealthy `shouldBe` Just (String "error")
        m <- getPath ok "/metrics"
        BS.isInfixOf "successor_calls_total" (BL.toStrict (simpleBody m)) `shouldBe` True
        missing <- getPath ok "/nope"
        field "status" missing `shouldBe` Just (Number 404)
        wrong <- runSession (request (setPath defaultRequest {requestMethod = methodPost} "/health")) (application ok)
        field "status" wrong `shouldBe` Just (Number 405)

    describe "Config" $ do
      let env pairs name = lookup name pairs
      it "reads defaults and requires the password" $ do
        let defaults = loadConfig (env [("SUCCESSOR_DB_PASSWORD", "x")])
        (brokers <$> defaults) `shouldBe` Right "redpanda:9092"
        (httpPort <$> defaults) `shouldBe` Right 8080
        (grpcPort <$> defaults) `shouldBe` Right 9090
        (digitUrlTemplate <$> defaults) `shouldBe` Right "http://digit-{digit}:8080"
        (carryAddress <$> defaults) `shouldBe` Right ("carry", 9090)
        either (const True) (const False) (loadConfig (env [])) `shouldBe` True
      it "rejects invalid values"
        $ forM_
          [ [("AAAS_BOOTSTRAP", "platform")],
            [("AAAS_HTTP_PORT", "http")],
            [("AAAS_GRPC_PORT", "8080")],
            [("AAAS_DIGIT_URL_TEMPLATE", "http://digit:8080")],
            [("AAAS_CARRY_ADDR", "carry")],
            [("AAAS_CARRY_ADDR", "carry:0")],
            [("AAAS_LOG_LEVEL", "loud")],
            [("AAAS_KAFKA_LOG_LEVEL", "9")]
          ]
        $ \pairs -> either (const True) (const False) (loadConfig (env (("SUCCESSOR_DB_PASSWORD", "x") : pairs))) `shouldBe` True
      it "splits host and port" $
        parseAddress "10.0.0.1:9090" `shouldBe` Right ("10.0.0.1", 9090)

    describe "Log" $
      it "renders the fields of CLAUDE.md 6.1 in order" $ do
        let line = renderLine "t" "successor" Warn (Just sampleTask) (Just parentTrace) "m" [("n", Number 1)]
        line `shouldBe` "{\"ts\":\"t\",\"level\":\"warn\",\"service\":\"successor\",\"msg\":\"m\",\"taskId\":\"018f3c2e-7b1a-7c3d-9f00-0000000000aa\",\"traceId\":\"4bf92f3577b34da6a3ce929d0e0e4736\",\"spanId\":\"00f067aa0ba902b7\",\"n\":1}"

    describe "CallLog (CouchDB, needs COUCHDB_URL)" $
      case couch of
        Nothing -> it "is skipped without COUCHDB_URL" pending
        Just url -> do
          it "migrates once and logs a call once" $ do
            db <- newCallLog (Text.pack url) "successor" "change-me"
            applied <- migrate db migrations
            applied `shouldSatisfy` (>= 0)
            migrate db migrations `shouldReturn` 0
            ping db `shouldReturn` True
            taskId <- newUuidV7
            let rec = CallRecord taskId 3 4 "018f3c2e-7b1a-7c3d-9f00-000000000020" "{}" "2026-10-16T12:00:00.000Z" (traceId parentTrace)
            record db rec `shouldReturn` Recorded
            record db rec {recEventId = "other"} `shouldReturn` AlreadyRecorded rec
          it "serves calls end to end against CouchDB" $ do
            db <- newCallLog (Text.pack url) "successor" "change-me"
            (deps, sent, _, asked) <- fakeDeps
            let real = deps {recordCall = record db}
            taskId <- newUuidV7
            call real (CallRequest 99999 taskId parentTrace) `shouldReturn` Right (Computed 100000)
            call real (CallRequest 99999 taskId parentTrace) `shouldReturn` Right (Replayed 100000)
            readIORef asked `shouldReturn` (2, 2)
            published <- readIORef sent
            case published of
              [(_, a), (_, b)] -> a `shouldBe` b
              _ -> expectationFailure "two messages expected"
