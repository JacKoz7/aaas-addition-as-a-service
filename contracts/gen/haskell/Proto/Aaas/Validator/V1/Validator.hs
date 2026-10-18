{- This file was auto-generated from aaas/validator/v1/validator.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Aaas.Validator.V1.Validator (
        ValidatorService(..), ValidateRequest(), ValidateResponse()
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
     
         * 'Proto.Aaas.Validator.V1.Validator_Fields.a' @:: Lens' ValidateRequest Data.Word.Word64@
         * 'Proto.Aaas.Validator.V1.Validator_Fields.b' @:: Lens' ValidateRequest Data.Word.Word64@ -}
data ValidateRequest
  = ValidateRequest'_constructor {_ValidateRequest'a :: !Data.Word.Word64,
                                  _ValidateRequest'b :: !Data.Word.Word64,
                                  _ValidateRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ValidateRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ValidateRequest "a" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ValidateRequest'a (\ x__ y__ -> x__ {_ValidateRequest'a = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ValidateRequest "b" Data.Word.Word64 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ValidateRequest'b (\ x__ y__ -> x__ {_ValidateRequest'b = y__}))
        Prelude.id
instance Data.ProtoLens.Message ValidateRequest where
  messageName _ = Data.Text.pack "aaas.validator.v1.ValidateRequest"
  packedMessageDescriptor _
    = "\n\
      \\SIValidateRequest\DC2\f\n\
      \\SOHa\CAN\SOH \SOH(\EOTR\SOHa\DC2\f\n\
      \\SOHb\CAN\STX \SOH(\EOTR\SOHb"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        a__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "a"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"a")) ::
              Data.ProtoLens.FieldDescriptor ValidateRequest
        b__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "b"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt64Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word64)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"b")) ::
              Data.ProtoLens.FieldDescriptor ValidateRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, a__field_descriptor),
           (Data.ProtoLens.Tag 2, b__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ValidateRequest'_unknownFields
        (\ x__ y__ -> x__ {_ValidateRequest'_unknownFields = y__})
  defMessage
    = ValidateRequest'_constructor
        {_ValidateRequest'a = Data.ProtoLens.fieldDefault,
         _ValidateRequest'b = Data.ProtoLens.fieldDefault,
         _ValidateRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ValidateRequest
          -> Data.ProtoLens.Encoding.Bytes.Parser ValidateRequest
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
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "a"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"a") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       Data.ProtoLens.Encoding.Bytes.getVarInt "b"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"b") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ValidateRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"a") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
             ((Data.Monoid.<>)
                (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"b") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt _v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData ValidateRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ValidateRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ValidateRequest'a x__)
                (Control.DeepSeq.deepseq (_ValidateRequest'b x__) ()))
{- | Fields :
     
         * 'Proto.Aaas.Validator.V1.Validator_Fields.ok' @:: Lens' ValidateResponse Prelude.Bool@
         * 'Proto.Aaas.Validator.V1.Validator_Fields.reason' @:: Lens' ValidateResponse Data.Text.Text@ -}
data ValidateResponse
  = ValidateResponse'_constructor {_ValidateResponse'ok :: !Prelude.Bool,
                                   _ValidateResponse'reason :: !Data.Text.Text,
                                   _ValidateResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ValidateResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ValidateResponse "ok" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ValidateResponse'ok
           (\ x__ y__ -> x__ {_ValidateResponse'ok = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ValidateResponse "reason" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ValidateResponse'reason
           (\ x__ y__ -> x__ {_ValidateResponse'reason = y__}))
        Prelude.id
instance Data.ProtoLens.Message ValidateResponse where
  messageName _ = Data.Text.pack "aaas.validator.v1.ValidateResponse"
  packedMessageDescriptor _
    = "\n\
      \\DLEValidateResponse\DC2\SO\n\
      \\STXok\CAN\SOH \SOH(\bR\STXok\DC2\SYN\n\
      \\ACKreason\CAN\STX \SOH(\tR\ACKreason"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        ok__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "ok"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"ok")) ::
              Data.ProtoLens.FieldDescriptor ValidateResponse
        reason__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "reason"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"reason")) ::
              Data.ProtoLens.FieldDescriptor ValidateResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, ok__field_descriptor),
           (Data.ProtoLens.Tag 2, reason__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ValidateResponse'_unknownFields
        (\ x__ y__ -> x__ {_ValidateResponse'_unknownFields = y__})
  defMessage
    = ValidateResponse'_constructor
        {_ValidateResponse'ok = Data.ProtoLens.fieldDefault,
         _ValidateResponse'reason = Data.ProtoLens.fieldDefault,
         _ValidateResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ValidateResponse
          -> Data.ProtoLens.Encoding.Bytes.Parser ValidateResponse
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
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "ok"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"ok") y x)
                        18
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                           Data.ProtoLens.Encoding.Bytes.getText
                                             (Prelude.fromIntegral len))
                                       "reason"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"reason") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ValidateResponse"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"ok") _x
              in
                if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 8)
                      ((Prelude..)
                         Data.ProtoLens.Encoding.Bytes.putVarInt (\ b -> if b then 1 else 0)
                         _v))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"reason") _x
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
instance Control.DeepSeq.NFData ValidateResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ValidateResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ValidateResponse'ok x__)
                (Control.DeepSeq.deepseq (_ValidateResponse'reason x__) ()))
data ValidatorService = ValidatorService {}
instance Data.ProtoLens.Service.Types.Service ValidatorService where
  type ServiceName ValidatorService = "ValidatorService"
  type ServicePackage ValidatorService = "aaas.validator.v1"
  type ServiceMethods ValidatorService = '["validate"]
  packedServiceDescriptor _
    = "\n\
      \\DLEValidatorService\DC2S\n\
      \\bValidate\DC2\".aaas.validator.v1.ValidateRequest\SUB#.aaas.validator.v1.ValidateResponse"
instance Data.ProtoLens.Service.Types.HasMethodImpl ValidatorService "validate" where
  type MethodName ValidatorService "validate" = "Validate"
  type MethodInput ValidatorService "validate" = ValidateRequest
  type MethodOutput ValidatorService "validate" = ValidateResponse
  type MethodStreamingType ValidatorService "validate" = 'Data.ProtoLens.Service.Types.NonStreaming
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \!aaas/validator/v1/validator.proto\DC2\DC1aaas.validator.v1\"-\n\
    \\SIValidateRequest\DC2\f\n\
    \\SOHa\CAN\SOH \SOH(\EOTR\SOHa\DC2\f\n\
    \\SOHb\CAN\STX \SOH(\EOTR\SOHb\":\n\
    \\DLEValidateResponse\DC2\SO\n\
    \\STXok\CAN\SOH \SOH(\bR\STXok\DC2\SYN\n\
    \\ACKreason\CAN\STX \SOH(\tR\ACKreason2g\n\
    \\DLEValidatorService\DC2S\n\
    \\bValidate\DC2\".aaas.validator.v1.ValidateRequest\SUB#.aaas.validator.v1.ValidateResponseB\237\SOH\n\
    \\NAKcom.aaas.validator.v1B\SOValidatorProtoP\SOHZ^github.com/JacKoz7/AaaS---Addition-as-a-Service/contracts/gen/go/aaas/validator/v1;validatorv1\162\STX\ETXAVX\170\STX\DC1Aaas.Validator.V1\202\STX\DC1Aaas\\Validator\\V1\226\STX\GSAaas\\Validator\\V1\\GPBMetadata\234\STX\DC3Aaas::Validator::V1J\200\DC1\n\
    \\ACK\DC2\EOT\r\NUL4\SOH\n\
    \\158\EOT\n\
    \\SOH\f\DC2\ETX\r\NUL\DC22\147\EOT SPDX-License-Identifier: MIT\n\
    \ Copyright (c) 2026 AaaS Contributors\n\
    \\n\
    \ Component:       contracts\n\
    \ Module:          aaas.validator.v1\n\
    \ Owning Team:     Arithmetic Excellence Center (AEC)\n\
    \ Classification:  INTERNAL\n\
    \ Purpose:         gRPC contract of the validator service: checks that both\n\
    \                  operands of an addition lie in the supported range\n\
    \                  0..99 999 before any arithmetic resource is committed.\n\
    \ Related Docs:    CLAUDE.md (sections 1, 4.3), contracts/proto/README.md,\n\
    \                  ADR-0020\n\
    \\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\SI\NUL\SUB\n\
    \\220\STX\n\
    \\STX\ACK\NUL\DC2\EOT\SYN\NUL\GS\SOH\SUB\207\STX ValidatorService guards the arithmetic pipeline against operands outside\n\
    \ the supported range 0..99 999 (CLAUDE.md section 1). It is called by the\n\
    \ parser after the expression has been turned into an AST and before the\n\
    \ addition is requested. The service holds no per-request state: the same\n\
    \ request always yields the same response.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\ACK\NUL\SOH\DC2\ETX\SYN\b\CAN\n\
    \\156\STX\n\
    \\EOT\ACK\NUL\STX\NUL\DC2\ETX\FS\STX;\SUB\142\STX Validate checks both operands against the supported range.\n\
    \\n\
    \ An out-of-range operand is a regular, successful response with ok set\n\
    \ to false, not a gRPC error. gRPC errors are reserved for the service\n\
    \ being unable to answer (UNAVAILABLE, DEADLINE_EXCEEDED, INTERNAL).\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\SOH\DC2\ETX\FS\ACK\SO\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\STX\DC2\ETX\FS\SI\RS\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\ETX\DC2\ETX\FS)9\n\
    \\224\STX\n\
    \\STX\EOT\NUL\DC2\EOT%\NUL*\SOH\SUB\211\STX ValidateRequest carries the two operands exactly as the parser read them.\n\
    \\n\
    \ The fields are 64-bit so that operands above the supported range (for\n\
    \ example 123 456) reach the validator and are rejected with a reason\n\
    \ instead of being truncated by the caller. An operand that does not even\n\
    \ fit in 64 bits is rejected by the parser itself.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX%\b\ETB\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX'\STX\b\n\
    \C\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX'\STX\SI\SUB6 First operand (left of `+`), any value in 0..2^64-1.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX'\t\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX'\r\SO\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ENQ\DC2\ETX)\STX\b\n\
    \E\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX)\STX\SI\SUB8 Second operand (right of `+`), any value in 0..2^64-1.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX)\t\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX)\r\SO\n\
    \?\n\
    \\STX\EOT\SOH\DC2\EOT-\NUL4\SOH\SUB3 ValidateResponse is the verdict of the validator.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX-\b\CAN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX/\STX\ACK\n\
    \8\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX/\STX\SO\SUB+ True when both operands lie in 0..99 999.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX/\a\t\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX/\f\r\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ENQ\DC2\ETX3\STX\b\n\
    \\180\SOH\n\
    \\EOT\EOT\SOH\STX\SOH\DC2\ETX3\STX\DC4\SUB\166\SOH Human-readable English explanation of a rejection, naming the offending\n\
    \ operand(s), for example \"a = 123456 is outside the range 0..99999\".\n\
    \ Empty when ok is true.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\SOH\DC2\ETX3\t\SI\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ETX\DC2\ETX3\DC2\DC3b\ACKproto3"