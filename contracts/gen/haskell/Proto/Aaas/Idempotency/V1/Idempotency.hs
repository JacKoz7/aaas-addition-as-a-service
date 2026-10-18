{- This file was auto-generated from aaas/idempotency/v1/idempotency.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Aaas.Idempotency.V1.Idempotency (
        IdempotencyService(..), ClaimRequest(), ClaimResponse(),
        MarkFailedRequest(), MarkFailedResponse()
    ) where
import qualified Data.ProtoLens.Runtime.Control.DeepSeq as Control.DeepSeq
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Prism as Data.ProtoLens.Prism
import qualified Data.ProtoLens.Runtime.Prelude as Prelude
import qualified Data.ProtoLens.Runtime.Data.Int as Data.Int
import qualified Data.ProtoLens.Runtime.Data.Monoid as Data.Monoid
import qualified Data.ProtoLens.Runtime.Data.Word as Data.Word
import qualified Data.ProtoLens.Runtime.Data.ProtoLens as Data.ProtoLens
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Bytes as Data.ProtoLens.Encoding.Bytes
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Growing as Data.ProtoLens.Encoding.Growing
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Parser.Unsafe as Data.ProtoLens.Encoding.Parser.Unsafe
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Encoding.Wire as Data.ProtoLens.Encoding.Wire
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Field as Data.ProtoLens.Field
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Message.Enum as Data.ProtoLens.Message.Enum
import qualified Data.ProtoLens.Runtime.Data.ProtoLens.Service.Types as Data.ProtoLens.Service.Types
import qualified Data.ProtoLens.Runtime.Lens.Family2 as Lens.Family2
import qualified Data.ProtoLens.Runtime.Lens.Family2.Unchecked as Lens.Family2.Unchecked
import qualified Data.ProtoLens.Runtime.Data.Text as Data.Text
import qualified Data.ProtoLens.Runtime.Data.Map as Data.Map
import qualified Data.ProtoLens.Runtime.Data.ByteString as Data.ByteString
import qualified Data.ProtoLens.Runtime.Data.ByteString.Char8 as Data.ByteString.Char8
import qualified Data.ProtoLens.Runtime.Data.Text.Encoding as Data.Text.Encoding
import qualified Data.ProtoLens.Runtime.Data.Vector as Data.Vector
import qualified Data.ProtoLens.Runtime.Data.Vector.Generic as Data.Vector.Generic
import qualified Data.ProtoLens.Runtime.Data.Vector.Unboxed as Data.Vector.Unboxed
import qualified Data.ProtoLens.Runtime.Text.Read as Text.Read
{- | Fields :
     
         * 'Proto.Aaas.Idempotency.V1.Idempotency_Fields.key' @:: Lens' ClaimRequest Data.Text.Text@
         * 'Proto.Aaas.Idempotency.V1.Idempotency_Fields.taskId' @:: Lens' ClaimRequest Data.Text.Text@ -}
data ClaimRequest
  = ClaimRequest'_constructor {_ClaimRequest'key :: !Data.Text.Text,
                               _ClaimRequest'taskId :: !Data.Text.Text,
                               _ClaimRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ClaimRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ClaimRequest "key" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ClaimRequest'key (\ x__ y__ -> x__ {_ClaimRequest'key = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ClaimRequest "taskId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ClaimRequest'taskId
           (\ x__ y__ -> x__ {_ClaimRequest'taskId = y__}))
        Prelude.id
instance Data.ProtoLens.Message ClaimRequest where
  messageName _ = Data.Text.pack "aaas.idempotency.v1.ClaimRequest"
  packedMessageDescriptor _
    = "\n\
      \\fClaimRequest\DC2\DLE\n\
      \\ETXkey\CAN\SOH \SOH(\tR\ETXkey\DC2\ETB\n\
      \\atask_id\CAN\STX \SOH(\tR\ACKtaskId"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        key__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "key"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"key")) ::
              Data.ProtoLens.FieldDescriptor ClaimRequest
        taskId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "task_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"taskId")) ::
              Data.ProtoLens.FieldDescriptor ClaimRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, key__field_descriptor),
           (Data.ProtoLens.Tag 2, taskId__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ClaimRequest'_unknownFields
        (\ x__ y__ -> x__ {_ClaimRequest'_unknownFields = y__})
  defMessage
    = ClaimRequest'_constructor
        {_ClaimRequest'key = Data.ProtoLens.fieldDefault,
         _ClaimRequest'taskId = Data.ProtoLens.fieldDefault,
         _ClaimRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ClaimRequest -> Data.ProtoLens.Encoding.Bytes.Parser ClaimRequest
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "key"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"key") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "task_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"taskId") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ClaimRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"key") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"taskId") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 18)
                         ((Prelude..)
                            (\ bs
                               -> (Data.Monoid.<>)
                                    (Data.ProtoLens.Encoding.Bytes.putVarInt
                                       (Prelude.fromIntegral (Data.ByteString.length bs)))
                                    (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                            Data.Text.Encoding.encodeUtf8 _v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData ClaimRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ClaimRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ClaimRequest'key x__)
                (Control.DeepSeq.deepseq (_ClaimRequest'taskId x__) ()))
{- | Fields :
     
         * 'Proto.Aaas.Idempotency.V1.Idempotency_Fields.taskId' @:: Lens' ClaimResponse Data.Text.Text@
         * 'Proto.Aaas.Idempotency.V1.Idempotency_Fields.existing' @:: Lens' ClaimResponse Prelude.Bool@ -}
data ClaimResponse
  = ClaimResponse'_constructor {_ClaimResponse'taskId :: !Data.Text.Text,
                                _ClaimResponse'existing :: !Prelude.Bool,
                                _ClaimResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ClaimResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ClaimResponse "taskId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ClaimResponse'taskId
           (\ x__ y__ -> x__ {_ClaimResponse'taskId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ClaimResponse "existing" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ClaimResponse'existing
           (\ x__ y__ -> x__ {_ClaimResponse'existing = y__}))
        Prelude.id
instance Data.ProtoLens.Message ClaimResponse where
  messageName _ = Data.Text.pack "aaas.idempotency.v1.ClaimResponse"
  packedMessageDescriptor _
    = "\n\
      \\rClaimResponse\DC2\ETB\n\
      \\atask_id\CAN\SOH \SOH(\tR\ACKtaskId\DC2\SUB\n\
      \\bexisting\CAN\STX \SOH(\bR\bexisting"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        taskId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "task_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"taskId")) ::
              Data.ProtoLens.FieldDescriptor ClaimResponse
        existing__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "existing"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"existing")) ::
              Data.ProtoLens.FieldDescriptor ClaimResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, taskId__field_descriptor),
           (Data.ProtoLens.Tag 2, existing__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ClaimResponse'_unknownFields
        (\ x__ y__ -> x__ {_ClaimResponse'_unknownFields = y__})
  defMessage
    = ClaimResponse'_constructor
        {_ClaimResponse'taskId = Data.ProtoLens.fieldDefault,
         _ClaimResponse'existing = Data.ProtoLens.fieldDefault,
         _ClaimResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ClaimResponse -> Data.ProtoLens.Encoding.Bytes.Parser ClaimResponse
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "task_id"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"taskId") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "existing"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"existing") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ClaimResponse"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"taskId") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"existing") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt (\ b -> if b then 1 else 0)
                            _v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData ClaimResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ClaimResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ClaimResponse'taskId x__)
                (Control.DeepSeq.deepseq (_ClaimResponse'existing x__) ()))
{- | Fields :
     
         * 'Proto.Aaas.Idempotency.V1.Idempotency_Fields.key' @:: Lens' MarkFailedRequest Data.Text.Text@ -}
data MarkFailedRequest
  = MarkFailedRequest'_constructor {_MarkFailedRequest'key :: !Data.Text.Text,
                                    _MarkFailedRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show MarkFailedRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField MarkFailedRequest "key" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _MarkFailedRequest'key
           (\ x__ y__ -> x__ {_MarkFailedRequest'key = y__}))
        Prelude.id
instance Data.ProtoLens.Message MarkFailedRequest where
  messageName _
    = Data.Text.pack "aaas.idempotency.v1.MarkFailedRequest"
  packedMessageDescriptor _
    = "\n\
      \\DC1MarkFailedRequest\DC2\DLE\n\
      \\ETXkey\CAN\SOH \SOH(\tR\ETXkey"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        key__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "key"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"key")) ::
              Data.ProtoLens.FieldDescriptor MarkFailedRequest
      in
        Data.Map.fromList [(Data.ProtoLens.Tag 1, key__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _MarkFailedRequest'_unknownFields
        (\ x__ y__ -> x__ {_MarkFailedRequest'_unknownFields = y__})
  defMessage
    = MarkFailedRequest'_constructor
        {_MarkFailedRequest'key = Data.ProtoLens.fieldDefault,
         _MarkFailedRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          MarkFailedRequest
          -> Data.ProtoLens.Encoding.Bytes.Parser MarkFailedRequest
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        10
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "key"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"key") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "MarkFailedRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"key") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((Prelude..)
                         (\ bs
                            -> (Data.Monoid.<>)
                                 (Data.ProtoLens.Encoding.Bytes.putVarInt
                                    (Prelude.fromIntegral (Data.ByteString.length bs)))
                                 (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         Data.Text.Encoding.encodeUtf8 _v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData MarkFailedRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_MarkFailedRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq (_MarkFailedRequest'key x__) ())
{- | Fields :
      -}
data MarkFailedResponse
  = MarkFailedResponse'_constructor {_MarkFailedResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show MarkFailedResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Message MarkFailedResponse where
  messageName _
    = Data.Text.pack "aaas.idempotency.v1.MarkFailedResponse"
  packedMessageDescriptor _
    = "\n\
      \\DC2MarkFailedResponse"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag = let in Data.Map.fromList []
  unknownFields
    = Lens.Family2.Unchecked.lens
        _MarkFailedResponse'_unknownFields
        (\ x__ y__ -> x__ {_MarkFailedResponse'_unknownFields = y__})
  defMessage
    = MarkFailedResponse'_constructor
        {_MarkFailedResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          MarkFailedResponse
          -> Data.ProtoLens.Encoding.Bytes.Parser MarkFailedResponse
        loop x
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do (let missing = []
                       in
                         if Prelude.null missing then
                             Prelude.return ()
                         else
                             Prelude.fail
                               ((Prelude.++)
                                  "Missing required fields: "
                                  (Prelude.show (missing :: [Prelude.String]))))
                      Prelude.return
                        (Lens.Family2.over
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t) x)
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "MarkFailedResponse"
  buildMessage
    = \ _x
        -> Data.ProtoLens.Encoding.Wire.buildFieldSet
             (Lens.Family2.view Data.ProtoLens.unknownFields _x)
instance Control.DeepSeq.NFData MarkFailedResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_MarkFailedResponse'_unknownFields x__) ()
data IdempotencyService = IdempotencyService {}
instance Data.ProtoLens.Service.Types.Service IdempotencyService where
  type ServiceName IdempotencyService = "IdempotencyService"
  type ServicePackage IdempotencyService = "aaas.idempotency.v1"
  type ServiceMethods IdempotencyService = '["claim", "markFailed"]
  packedServiceDescriptor _
    = "\n\
      \\DC2IdempotencyService\DC2N\n\
      \\ENQClaim\DC2!.aaas.idempotency.v1.ClaimRequest\SUB\".aaas.idempotency.v1.ClaimResponse\DC2]\n\
      \\n\
      \MarkFailed\DC2&.aaas.idempotency.v1.MarkFailedRequest\SUB'.aaas.idempotency.v1.MarkFailedResponse"
instance Data.ProtoLens.Service.Types.HasMethodImpl IdempotencyService "claim" where
  type MethodName IdempotencyService "claim" = "Claim"
  type MethodInput IdempotencyService "claim" = ClaimRequest
  type MethodOutput IdempotencyService "claim" = ClaimResponse
  type MethodStreamingType IdempotencyService "claim" = 'Data.ProtoLens.Service.Types.NonStreaming
instance Data.ProtoLens.Service.Types.HasMethodImpl IdempotencyService "markFailed" where
  type MethodName IdempotencyService "markFailed" = "MarkFailed"
  type MethodInput IdempotencyService "markFailed" = MarkFailedRequest
  type MethodOutput IdempotencyService "markFailed" = MarkFailedResponse
  type MethodStreamingType IdempotencyService "markFailed" = 'Data.ProtoLens.Service.Types.NonStreaming
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \%aaas/idempotency/v1/idempotency.proto\DC2\DC3aaas.idempotency.v1\"9\n\
    \\fClaimRequest\DC2\DLE\n\
    \\ETXkey\CAN\SOH \SOH(\tR\ETXkey\DC2\ETB\n\
    \\atask_id\CAN\STX \SOH(\tR\ACKtaskId\"D\n\
    \\rClaimResponse\DC2\ETB\n\
    \\atask_id\CAN\SOH \SOH(\tR\ACKtaskId\DC2\SUB\n\
    \\bexisting\CAN\STX \SOH(\bR\bexisting\"%\n\
    \\DC1MarkFailedRequest\DC2\DLE\n\
    \\ETXkey\CAN\SOH \SOH(\tR\ETXkey\"\DC4\n\
    \\DC2MarkFailedResponse2\195\SOH\n\
    \\DC2IdempotencyService\DC2N\n\
    \\ENQClaim\DC2!.aaas.idempotency.v1.ClaimRequest\SUB\".aaas.idempotency.v1.ClaimResponse\DC2]\n\
    \\n\
    \MarkFailed\DC2&.aaas.idempotency.v1.MarkFailedRequest\SUB'.aaas.idempotency.v1.MarkFailedResponseB\253\SOH\n\
    \\ETBcom.aaas.idempotency.v1B\DLEIdempotencyProtoP\SOHZbgithub.com/JacKoz7/AaaS---Addition-as-a-Service/contracts/gen/go/aaas/idempotency/v1;idempotencyv1\162\STX\ETXAIX\170\STX\DC3Aaas.Idempotency.V1\202\STX\DC3Aaas\\Idempotency\\V1\226\STX\USAaas\\Idempotency\\V1\\GPBMetadata\234\STX\NAKAaas::Idempotency::V1J\171\DC3\n\
    \\ACK\DC2\EOT\r\NUL>\GS\n\
    \\252\ETX\n\
    \\SOH\f\DC2\ETX\r\NUL\DC22\241\ETX SPDX-License-Identifier: MIT\n\
    \ Copyright (c) 2026 AaaS Contributors\n\
    \\n\
    \ Component:       contracts\n\
    \ Module:          aaas.idempotency.v1\n\
    \ Owning Team:     Trust & Identity Board (TIB)\n\
    \ Classification:  INTERNAL\n\
    \ Purpose:         gRPC contract of the idempotency service: guarantees that\n\
    \                  one Idempotency-Key of the `=` key maps to exactly one\n\
    \                  addition task.\n\
    \ Related Docs:    CLAUDE.md (sections 3, 4.1, 4.3), contracts/proto/README.md,\n\
    \                  ADR-0020\n\
    \\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\SI\NUL\FS\n\
    \\228\SOH\n\
    \\STX\ACK\NUL\DC2\EOT\DC4\NUL!\SOH\SUB\215\SOH IdempotencyService records which task was created for an Idempotency-Key,\n\
    \ so that repeating the same `=` request returns the same task instead of\n\
    \ starting a second addition. It is called by expression-assembler.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\ACK\NUL\SOH\DC2\ETX\DC4\b\SUB\n\
    \\252\STX\n\
    \\EOT\ACK\NUL\STX\NUL\DC2\ETX\FS\STX2\SUB\238\STX Claim atomically binds a key to a task identifier.\n\
    \\n\
    \ When the key is unknown (or was marked failed), it is bound to the\n\
    \ proposed task_id and existing is false. When the key is already bound,\n\
    \ the stored task identifier is returned with existing set to true, and\n\
    \ the proposed task_id is discarded. An empty key or task_id yields the\n\
    \ gRPC status INVALID_ARGUMENT.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\SOH\DC2\ETX\FS\ACK\v\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\STX\DC2\ETX\FS\f\CAN\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\ETX\DC2\ETX\FS#0\n\
    \\214\SOH\n\
    \\EOT\ACK\NUL\STX\SOH\DC2\ETX \STXA\SUB\200\SOH MarkFailed releases a key whose task failed, so that the next Claim\n\
    \ with the same key starts a new task. It is sent by the saga during\n\
    \ compensation. Marking an unknown key is a no-op and succeeds.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\SOH\SOH\DC2\ETX \ACK\DLE\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\SOH\STX\DC2\ETX \DC1\"\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\SOH\ETX\DC2\ETX -?\n\
    \E\n\
    \\STX\EOT\NUL\DC2\EOT$\NUL+\SOH\SUB9 ClaimRequest proposes a binding of a key to a new task.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX$\b\DC4\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX'\STX\b\n\
    \j\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX'\STX\DC1\SUB] Value of the Idempotency-Key header of the `=` request; non-empty, at\n\
    \ most 255 characters.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX'\t\f\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX'\SI\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ENQ\DC2\ETX*\STX\b\n\
    \i\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX*\STX\NAK\SUB\\ Task identifier (UUIDv7, canonical text form) that the caller will use\n\
    \ if the key is new.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX*\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX*\DC3\DC4\n\
    \=\n\
    \\STX\EOT\SOH\DC2\EOT.\NUL4\SOH\SUB1 ClaimResponse names the task that owns the key.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX.\b\NAK\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX1\STX\b\n\
    \u\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX1\STX\NAK\SUBh Task identifier bound to the key: the proposed one when existing is\n\
    \ false, the earlier one otherwise.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX1\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX1\DC3\DC4\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ENQ\DC2\ETX3\STX\ACK\n\
    \D\n\
    \\EOT\EOT\SOH\STX\SOH\DC2\ETX3\STX\DC4\SUB7 True when the key was already bound before this call.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\SOH\DC2\ETX3\a\SI\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ETX\DC2\ETX3\DC2\DC3\n\
    \9\n\
    \\STX\EOT\STX\DC2\EOT7\NUL:\SOH\SUB- MarkFailedRequest names the key to release.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\STX\SOH\DC2\ETX7\b\EM\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ENQ\DC2\ETX9\STX\b\n\
    \=\n\
    \\EOT\EOT\STX\STX\NUL\DC2\ETX9\STX\DC1\SUB0 Idempotency-Key of the failed task; non-empty.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\SOH\DC2\ETX9\t\f\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ETX\DC2\ETX9\SI\DLE\n\
    \c\n\
    \\STX\EOT\ETX\DC2\ETX>\NUL\GS\SUBX MarkFailedResponse is intentionally empty: success is conveyed by the\n\
    \ gRPC status OK.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\ETX\SOH\DC2\ETX>\b\SUBb\ACKproto3"