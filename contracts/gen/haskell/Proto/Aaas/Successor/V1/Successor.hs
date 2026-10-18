{- This file was auto-generated from aaas/successor/v1/successor.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Aaas.Successor.V1.Successor (
        SuccessorService(..), NextRequest(), NextResponse()
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
     
         * 'Proto.Aaas.Successor.V1.Successor_Fields.n' @:: Lens' NextRequest Data.Word.Word32@
         * 'Proto.Aaas.Successor.V1.Successor_Fields.taskId' @:: Lens' NextRequest Data.Text.Text@ -}
data NextRequest
  = NextRequest'_constructor {_NextRequest'n :: !Data.Word.Word32,
                              _NextRequest'taskId :: !Data.Text.Text,
                              _NextRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show NextRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField NextRequest "n" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _NextRequest'n (\ x__ y__ -> x__ {_NextRequest'n = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField NextRequest "taskId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _NextRequest'taskId (\ x__ y__ -> x__ {_NextRequest'taskId = y__}))
        Prelude.id
instance Data.ProtoLens.Message NextRequest where
  messageName _ = Data.Text.pack "aaas.successor.v1.NextRequest"
  packedMessageDescriptor _
    = "\n\
      \\vNextRequest\DC2\f\n\
      \\SOHn\CAN\SOH \SOH(\rR\SOHn\DC2\ETB\n\
      \\atask_id\CAN\STX \SOH(\tR\ACKtaskId"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        n__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "n"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"n")) ::
              Data.ProtoLens.FieldDescriptor NextRequest
        taskId__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "task_id"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"taskId")) ::
              Data.ProtoLens.FieldDescriptor NextRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, n__field_descriptor),
           (Data.ProtoLens.Tag 2, taskId__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _NextRequest'_unknownFields
        (\ x__ y__ -> x__ {_NextRequest'_unknownFields = y__})
  defMessage
    = NextRequest'_constructor
        {_NextRequest'n = Data.ProtoLens.fieldDefault,
         _NextRequest'taskId = Data.ProtoLens.fieldDefault,
         _NextRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          NextRequest -> Data.ProtoLens.Encoding.Bytes.Parser NextRequest
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
                        8 -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "n"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"n") y x)
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
          (do loop Data.ProtoLens.defMessage) "NextRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"n") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                      ((Prelude..)
                         Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
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
instance Control.DeepSeq.NFData NextRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_NextRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_NextRequest'n x__)
                (Control.DeepSeq.deepseq (_NextRequest'taskId x__) ()))
{- | Fields :
     
         * 'Proto.Aaas.Successor.V1.Successor_Fields.n' @:: Lens' NextResponse Data.Word.Word32@ -}
data NextResponse
  = NextResponse'_constructor {_NextResponse'n :: !Data.Word.Word32,
                               _NextResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show NextResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField NextResponse "n" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _NextResponse'n (\ x__ y__ -> x__ {_NextResponse'n = y__}))
        Prelude.id
instance Data.ProtoLens.Message NextResponse where
  messageName _ = Data.Text.pack "aaas.successor.v1.NextResponse"
  packedMessageDescriptor _
    = "\n\
      \\fNextResponse\DC2\f\n\
      \\SOHn\CAN\SOH \SOH(\rR\SOHn"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        n__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "n"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"n")) ::
              Data.ProtoLens.FieldDescriptor NextResponse
      in Data.Map.fromList [(Data.ProtoLens.Tag 1, n__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _NextResponse'_unknownFields
        (\ x__ y__ -> x__ {_NextResponse'_unknownFields = y__})
  defMessage
    = NextResponse'_constructor
        {_NextResponse'n = Data.ProtoLens.fieldDefault,
         _NextResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          NextResponse -> Data.ProtoLens.Encoding.Bytes.Parser NextResponse
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
                        8 -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "n"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"n") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "NextResponse"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"n") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                      ((Prelude..)
                         Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData NextResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_NextResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq (_NextResponse'n x__) ())
data SuccessorService = SuccessorService {}
instance Data.ProtoLens.Service.Types.Service SuccessorService where
  type ServiceName SuccessorService = "SuccessorService"
  type ServicePackage SuccessorService = "aaas.successor.v1"
  type ServiceMethods SuccessorService = '["next"]
  packedServiceDescriptor _
    = "\n\
      \\DLESuccessorService\DC2G\n\
      \\EOTNext\DC2\RS.aaas.successor.v1.NextRequest\SUB\US.aaas.successor.v1.NextResponse"
instance Data.ProtoLens.Service.Types.HasMethodImpl SuccessorService "next" where
  type MethodName SuccessorService "next" = "Next"
  type MethodInput SuccessorService "next" = NextRequest
  type MethodOutput SuccessorService "next" = NextResponse
  type MethodStreamingType SuccessorService "next" = 'Data.ProtoLens.Service.Types.NonStreaming
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \!aaas/successor/v1/successor.proto\DC2\DC1aaas.successor.v1\"4\n\
    \\vNextRequest\DC2\f\n\
    \\SOHn\CAN\SOH \SOH(\rR\SOHn\DC2\ETB\n\
    \\atask_id\CAN\STX \SOH(\tR\ACKtaskId\"\FS\n\
    \\fNextResponse\DC2\f\n\
    \\SOHn\CAN\SOH \SOH(\rR\SOHn2[\n\
    \\DLESuccessorService\DC2G\n\
    \\EOTNext\DC2\RS.aaas.successor.v1.NextRequest\SUB\US.aaas.successor.v1.NextResponseB\237\SOH\n\
    \\NAKcom.aaas.successor.v1B\SOSuccessorProtoP\SOHZ^github.com/JacKoz7/AaaS---Addition-as-a-Service/contracts/gen/go/aaas/successor/v1;successorv1\162\STX\ETXASX\170\STX\DC1Aaas.Successor.V1\202\STX\DC1Aaas\\Successor\\V1\226\STX\GSAaas\\Successor\\V1\\GPBMetadata\234\STX\DC3Aaas::Successor::V1J\172\r\n\
    \\ACK\DC2\EOT\f\NUL-\SOH\n\
    \\223\ETX\n\
    \\SOH\f\DC2\ETX\f\NUL\DC22\212\ETX SPDX-License-Identifier: MIT\n\
    \ Copyright (c) 2026 AaaS Contributors\n\
    \\n\
    \ Component:       contracts\n\
    \ Module:          aaas.successor.v1\n\
    \ Owning Team:     Arithmetic Excellence Center (AEC)\n\
    \ Classification:  INTERNAL\n\
    \ Purpose:         gRPC contract of the successor service: computes n + 1,\n\
    \                  the only arithmetic primitive of Peano addition.\n\
    \ Related Docs:    CLAUDE.md (sections 1, 3, 4.3), contracts/proto/README.md,\n\
    \                  ADR-0016, ADR-0020\n\
    \\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\SO\NUL\SUB\n\
    \\187\SOH\n\
    \\STX\ACK\NUL\DC2\EOT\DC3\NUL\SUB\SOH\SUB\174\SOH SuccessorService computes the successor of a natural number by querying\n\
    \ the digit services and, on a carry, the carry service. The saga calls it\n\
    \ b times to compute a + b.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\ACK\NUL\SOH\DC2\ETX\DC3\b\CAN\n\
    \\214\SOH\n\
    \\EOT\ACK\NUL\STX\NUL\DC2\ETX\EM\STX/\SUB\200\SOH Next returns n + 1.\n\
    \\n\
    \ An n outside 0..199 997 yields the gRPC status OUT_OF_RANGE (the largest\n\
    \ possible sum is 99 999 + 99 999 = 199 998). An unreachable digit or carry\n\
    \ service yields UNAVAILABLE.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\SOH\DC2\ETX\EM\ACK\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\STX\DC2\ETX\EM\v\SYN\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\ETX\DC2\ETX\EM!-\n\
    \l\n\
    \\STX\EOT\NUL\DC2\EOT\RS\NUL'\SOH\SUB` NextRequest carries the number whose successor is requested and the task\n\
    \ the call belongs to.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX\RS\b\DC3\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX \STX\b\n\
    \,\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX \STX\SI\SUB\US Natural number in 0..199 997.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX \t\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX \r\SO\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ENQ\DC2\ETX&\STX\b\n\
    \\221\STX\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX&\STX\NAK\SUB\207\STX Task identifier (UUIDv7, canonical text form). An addition asks for the\n\
    \ successor of each value from a to a + b - 1 exactly once, so\n\
    \ (task_id, n) identifies a call: a retried call is answered from the\n\
    \ call log without a second log entry or event (ADR-0016). A missing or\n\
    \ malformed task_id yields the gRPC status INVALID_ARGUMENT.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX&\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX&\DC3\DC4\n\
    \1\n\
    \\STX\EOT\SOH\DC2\EOT*\NUL-\SOH\SUB% NextResponse carries the successor.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX*\b\DC4\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX,\STX\b\n\
    \$\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX,\STX\SI\SUB\ETB n + 1, in 1..199 998.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX,\t\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX,\r\SOb\ACKproto3"