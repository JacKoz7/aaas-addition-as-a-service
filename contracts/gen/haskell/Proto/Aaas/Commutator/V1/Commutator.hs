{- This file was auto-generated from aaas/commutator/v1/commutator.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Aaas.Commutator.V1.Commutator (
        CommutatorService(..), NormalizeRequest(), NormalizeResponse()
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
     
         * 'Proto.Aaas.Commutator.V1.Commutator_Fields.a' @:: Lens' NormalizeRequest Data.Word.Word32@
         * 'Proto.Aaas.Commutator.V1.Commutator_Fields.b' @:: Lens' NormalizeRequest Data.Word.Word32@ -}
data NormalizeRequest
  = NormalizeRequest'_constructor {_NormalizeRequest'a :: !Data.Word.Word32,
                                   _NormalizeRequest'b :: !Data.Word.Word32,
                                   _NormalizeRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show NormalizeRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField NormalizeRequest "a" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _NormalizeRequest'a (\ x__ y__ -> x__ {_NormalizeRequest'a = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField NormalizeRequest "b" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _NormalizeRequest'b (\ x__ y__ -> x__ {_NormalizeRequest'b = y__}))
        Prelude.id
instance Data.ProtoLens.Message NormalizeRequest where
  messageName _
    = Data.Text.pack "aaas.commutator.v1.NormalizeRequest"
  packedMessageDescriptor _
    = "\n\
      \\DLENormalizeRequest\DC2\f\n\
      \\SOHa\CAN\SOH \SOH(\rR\SOHa\DC2\f\n\
      \\SOHb\CAN\STX \SOH(\rR\SOHb"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        a__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "a"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"a")) ::
              Data.ProtoLens.FieldDescriptor NormalizeRequest
        b__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "b"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"b")) ::
              Data.ProtoLens.FieldDescriptor NormalizeRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, a__field_descriptor),
           (Data.ProtoLens.Tag 2, b__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _NormalizeRequest'_unknownFields
        (\ x__ y__ -> x__ {_NormalizeRequest'_unknownFields = y__})
  defMessage
    = NormalizeRequest'_constructor
        {_NormalizeRequest'a = Data.ProtoLens.fieldDefault,
         _NormalizeRequest'b = Data.ProtoLens.fieldDefault,
         _NormalizeRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          NormalizeRequest
          -> Data.ProtoLens.Encoding.Bytes.Parser NormalizeRequest
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
                                       "a"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"a") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "b"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"b") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "NormalizeRequest"
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
                      ((Prelude..)
                         Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
             ((Data.Monoid.<>)
                (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"b") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                (Data.ProtoLens.Encoding.Wire.buildFieldSet
                   (Lens.Family2.view Data.ProtoLens.unknownFields _x)))
instance Control.DeepSeq.NFData NormalizeRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_NormalizeRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_NormalizeRequest'a x__)
                (Control.DeepSeq.deepseq (_NormalizeRequest'b x__) ()))
{- | Fields :
     
         * 'Proto.Aaas.Commutator.V1.Commutator_Fields.a' @:: Lens' NormalizeResponse Data.Word.Word32@
         * 'Proto.Aaas.Commutator.V1.Commutator_Fields.b' @:: Lens' NormalizeResponse Data.Word.Word32@
         * 'Proto.Aaas.Commutator.V1.Commutator_Fields.swapped' @:: Lens' NormalizeResponse Prelude.Bool@ -}
data NormalizeResponse
  = NormalizeResponse'_constructor {_NormalizeResponse'a :: !Data.Word.Word32,
                                    _NormalizeResponse'b :: !Data.Word.Word32,
                                    _NormalizeResponse'swapped :: !Prelude.Bool,
                                    _NormalizeResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show NormalizeResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField NormalizeResponse "a" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _NormalizeResponse'a
           (\ x__ y__ -> x__ {_NormalizeResponse'a = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField NormalizeResponse "b" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _NormalizeResponse'b
           (\ x__ y__ -> x__ {_NormalizeResponse'b = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField NormalizeResponse "swapped" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _NormalizeResponse'swapped
           (\ x__ y__ -> x__ {_NormalizeResponse'swapped = y__}))
        Prelude.id
instance Data.ProtoLens.Message NormalizeResponse where
  messageName _
    = Data.Text.pack "aaas.commutator.v1.NormalizeResponse"
  packedMessageDescriptor _
    = "\n\
      \\DC1NormalizeResponse\DC2\f\n\
      \\SOHa\CAN\SOH \SOH(\rR\SOHa\DC2\f\n\
      \\SOHb\CAN\STX \SOH(\rR\SOHb\DC2\CAN\n\
      \\aswapped\CAN\ETX \SOH(\bR\aswapped"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        a__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "a"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"a")) ::
              Data.ProtoLens.FieldDescriptor NormalizeResponse
        b__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "b"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"b")) ::
              Data.ProtoLens.FieldDescriptor NormalizeResponse
        swapped__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "swapped"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"swapped")) ::
              Data.ProtoLens.FieldDescriptor NormalizeResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, a__field_descriptor),
           (Data.ProtoLens.Tag 2, b__field_descriptor),
           (Data.ProtoLens.Tag 3, swapped__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _NormalizeResponse'_unknownFields
        (\ x__ y__ -> x__ {_NormalizeResponse'_unknownFields = y__})
  defMessage
    = NormalizeResponse'_constructor
        {_NormalizeResponse'a = Data.ProtoLens.fieldDefault,
         _NormalizeResponse'b = Data.ProtoLens.fieldDefault,
         _NormalizeResponse'swapped = Data.ProtoLens.fieldDefault,
         _NormalizeResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          NormalizeResponse
          -> Data.ProtoLens.Encoding.Bytes.Parser NormalizeResponse
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
                                       "a"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"a") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "b"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"b") y x)
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "swapped"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"swapped") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "NormalizeResponse"
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
                      ((Prelude..)
                         Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
             ((Data.Monoid.<>)
                (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"b") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (let
                      _v = Lens.Family2.view (Data.ProtoLens.Field.field @"swapped") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
                            ((Prelude..)
                               Data.ProtoLens.Encoding.Bytes.putVarInt (\ b -> if b then 1 else 0)
                               _v))
                   (Data.ProtoLens.Encoding.Wire.buildFieldSet
                      (Lens.Family2.view Data.ProtoLens.unknownFields _x))))
instance Control.DeepSeq.NFData NormalizeResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_NormalizeResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_NormalizeResponse'a x__)
                (Control.DeepSeq.deepseq
                   (_NormalizeResponse'b x__)
                   (Control.DeepSeq.deepseq (_NormalizeResponse'swapped x__) ())))
data CommutatorService = CommutatorService {}
instance Data.ProtoLens.Service.Types.Service CommutatorService where
  type ServiceName CommutatorService = "CommutatorService"
  type ServicePackage CommutatorService = "aaas.commutator.v1"
  type ServiceMethods CommutatorService = '["normalize"]
  packedServiceDescriptor _
    = "\n\
      \\DC1CommutatorService\DC2X\n\
      \\tNormalize\DC2$.aaas.commutator.v1.NormalizeRequest\SUB%.aaas.commutator.v1.NormalizeResponse"
instance Data.ProtoLens.Service.Types.HasMethodImpl CommutatorService "normalize" where
  type MethodName CommutatorService "normalize" = "Normalize"
  type MethodInput CommutatorService "normalize" = NormalizeRequest
  type MethodOutput CommutatorService "normalize" = NormalizeResponse
  type MethodStreamingType CommutatorService "normalize" = 'Data.ProtoLens.Service.Types.NonStreaming
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \#aaas/commutator/v1/commutator.proto\DC2\DC2aaas.commutator.v1\".\n\
    \\DLENormalizeRequest\DC2\f\n\
    \\SOHa\CAN\SOH \SOH(\rR\SOHa\DC2\f\n\
    \\SOHb\CAN\STX \SOH(\rR\SOHb\"I\n\
    \\DC1NormalizeResponse\DC2\f\n\
    \\SOHa\CAN\SOH \SOH(\rR\SOHa\DC2\f\n\
    \\SOHb\CAN\STX \SOH(\rR\SOHb\DC2\CAN\n\
    \\aswapped\CAN\ETX \SOH(\bR\aswapped2m\n\
    \\DC1CommutatorService\DC2X\n\
    \\tNormalize\DC2$.aaas.commutator.v1.NormalizeRequest\SUB%.aaas.commutator.v1.NormalizeResponseB\245\SOH\n\
    \\SYNcom.aaas.commutator.v1B\SICommutatorProtoP\SOHZ`github.com/JacKoz7/AaaS---Addition-as-a-Service/contracts/gen/go/aaas/commutator/v1;commutatorv1\162\STX\ETXACX\170\STX\DC2Aaas.Commutator.V1\202\STX\DC2Aaas\\Commutator\\V1\226\STX\RSAaas\\Commutator\\V1\\GPBMetadata\234\STX\DC4Aaas::Commutator::V1J\134\SO\n\
    \\ACK\DC2\EOT\SO\NUL-\SOH\n\
    \\186\EOT\n\
    \\SOH\f\DC2\ETX\SO\NUL\DC22\175\EOT SPDX-License-Identifier: MIT\n\
    \ Copyright (c) 2026 AaaS Contributors\n\
    \\n\
    \ Component:       contracts\n\
    \ Module:          aaas.commutator.v1\n\
    \ Owning Team:     Arithmetic Excellence Center (AEC)\n\
    \ Classification:  INTERNAL\n\
    \ Purpose:         gRPC contract of the commutator service: orders the\n\
    \                  operands so that the second one is the smaller, which\n\
    \                  minimises the number of successor calls (a + b takes b\n\
    \                  calls).\n\
    \ Related Docs:    CLAUDE.md (sections 1, 3, 4.3), contracts/proto/README.md,\n\
    \                  ADR-0020\n\
    \\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\DLE\NUL\ESC\n\
    \\212\SOH\n\
    \\STX\ACK\NUL\DC2\EOT\NAK\NUL\ESC\SOH\SUB\199\SOH CommutatorService applies the commutative law of addition so that the\n\
    \ Peano loop runs min(a, b) times instead of b times. It is called by the\n\
    \ parser after the validator has accepted the operands.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\ACK\NUL\SOH\DC2\ETX\NAK\b\EM\n\
    \\193\SOH\n\
    \\EOT\ACK\NUL\STX\NUL\DC2\ETX\SUB\STX>\SUB\179\SOH Normalize returns the operands ordered so that a >= b.\n\
    \\n\
    \ When the request already satisfies a >= b (including a == b), the\n\
    \ operands are returned unchanged and swapped is false.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\SOH\DC2\ETX\SUB\ACK\SI\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\STX\DC2\ETX\SUB\DLE \n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\ETX\DC2\ETX\SUB+<\n\
    \>\n\
    \\STX\EOT\NUL\DC2\EOT\RS\NUL#\SOH\SUB2 NormalizeRequest carries two validated operands.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX\RS\b\CAN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX \STX\b\n\
    \?\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX \STX\SI\SUB2 First operand, in 0..99 999 (already validated).\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX \t\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX \r\SO\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ENQ\DC2\ETX\"\STX\b\n\
    \@\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX\"\STX\SI\SUB3 Second operand, in 0..99 999 (already validated).\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX\"\t\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX\"\r\SO\n\
    \I\n\
    \\STX\EOT\SOH\DC2\EOT&\NUL-\SOH\SUB= NormalizeResponse carries the operands in the order a >= b.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX&\b\EM\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX(\STX\b\n\
    \T\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX(\STX\SI\SUBG The larger operand (or either one when they are equal), in 0..99 999.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX(\t\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX(\r\SO\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ENQ\DC2\ETX*\STX\b\n\
    \P\n\
    \\EOT\EOT\SOH\STX\SOH\DC2\ETX*\STX\SI\SUBC The smaller operand, in 0..99 999; the number of successor calls.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\SOH\DC2\ETX*\t\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ETX\DC2\ETX*\r\SO\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ENQ\DC2\ETX,\STX\ACK\n\
    \D\n\
    \\EOT\EOT\SOH\STX\STX\DC2\ETX,\STX\DC3\SUB7 True when the operands of the request were exchanged.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\SOH\DC2\ETX,\a\SO\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ETX\DC2\ETX,\DC1\DC2b\ACKproto3"