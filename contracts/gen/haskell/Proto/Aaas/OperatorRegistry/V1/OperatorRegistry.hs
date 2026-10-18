{- This file was auto-generated from aaas/operator_registry/v1/operator_registry.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Aaas.OperatorRegistry.V1.OperatorRegistry (
        OperatorRegistryService(..), ResolveRequest(), ResolveResponse()
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
     
         * 'Proto.Aaas.OperatorRegistry.V1.OperatorRegistry_Fields.operator' @:: Lens' ResolveRequest Data.Text.Text@ -}
data ResolveRequest
  = ResolveRequest'_constructor {_ResolveRequest'operator :: !Data.Text.Text,
                                 _ResolveRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ResolveRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ResolveRequest "operator" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ResolveRequest'operator
           (\ x__ y__ -> x__ {_ResolveRequest'operator = y__}))
        Prelude.id
instance Data.ProtoLens.Message ResolveRequest where
  messageName _
    = Data.Text.pack "aaas.operator_registry.v1.ResolveRequest"
  packedMessageDescriptor _
    = "\n\
      \\SOResolveRequest\DC2\SUB\n\
      \\boperator\CAN\SOH \SOH(\tR\boperator"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        operator__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "operator"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"operator")) ::
              Data.ProtoLens.FieldDescriptor ResolveRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, operator__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ResolveRequest'_unknownFields
        (\ x__ y__ -> x__ {_ResolveRequest'_unknownFields = y__})
  defMessage
    = ResolveRequest'_constructor
        {_ResolveRequest'operator = Data.ProtoLens.fieldDefault,
         _ResolveRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ResolveRequest
          -> Data.ProtoLens.Encoding.Bytes.Parser ResolveRequest
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
                                       "operator"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"operator") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ResolveRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"operator") _x
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
instance Control.DeepSeq.NFData ResolveRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ResolveRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq (_ResolveRequest'operator x__) ())
{- | Fields :
     
         * 'Proto.Aaas.OperatorRegistry.V1.OperatorRegistry_Fields.saga' @:: Lens' ResolveResponse Data.Text.Text@
         * 'Proto.Aaas.OperatorRegistry.V1.OperatorRegistry_Fields.enabled' @:: Lens' ResolveResponse Prelude.Bool@ -}
data ResolveResponse
  = ResolveResponse'_constructor {_ResolveResponse'saga :: !Data.Text.Text,
                                  _ResolveResponse'enabled :: !Prelude.Bool,
                                  _ResolveResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ResolveResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ResolveResponse "saga" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ResolveResponse'saga
           (\ x__ y__ -> x__ {_ResolveResponse'saga = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ResolveResponse "enabled" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ResolveResponse'enabled
           (\ x__ y__ -> x__ {_ResolveResponse'enabled = y__}))
        Prelude.id
instance Data.ProtoLens.Message ResolveResponse where
  messageName _
    = Data.Text.pack "aaas.operator_registry.v1.ResolveResponse"
  packedMessageDescriptor _
    = "\n\
      \\SIResolveResponse\DC2\DC2\n\
      \\EOTsaga\CAN\SOH \SOH(\tR\EOTsaga\DC2\CAN\n\
      \\aenabled\CAN\STX \SOH(\bR\aenabled"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        saga__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "saga"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"saga")) ::
              Data.ProtoLens.FieldDescriptor ResolveResponse
        enabled__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "enabled"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"enabled")) ::
              Data.ProtoLens.FieldDescriptor ResolveResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, saga__field_descriptor),
           (Data.ProtoLens.Tag 2, enabled__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ResolveResponse'_unknownFields
        (\ x__ y__ -> x__ {_ResolveResponse'_unknownFields = y__})
  defMessage
    = ResolveResponse'_constructor
        {_ResolveResponse'saga = Data.ProtoLens.fieldDefault,
         _ResolveResponse'enabled = Data.ProtoLens.fieldDefault,
         _ResolveResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ResolveResponse
          -> Data.ProtoLens.Encoding.Bytes.Parser ResolveResponse
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
                                       "saga"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"saga") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "enabled"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"enabled") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ResolveResponse"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"saga") _x
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"enabled") _x
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
instance Control.DeepSeq.NFData ResolveResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ResolveResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ResolveResponse'saga x__)
                (Control.DeepSeq.deepseq (_ResolveResponse'enabled x__) ()))
data OperatorRegistryService = OperatorRegistryService {}
instance Data.ProtoLens.Service.Types.Service OperatorRegistryService where
  type ServiceName OperatorRegistryService = "OperatorRegistryService"
  type ServicePackage OperatorRegistryService = "aaas.operator_registry.v1"
  type ServiceMethods OperatorRegistryService = '["resolve"]
  packedServiceDescriptor _
    = "\n\
      \\ETBOperatorRegistryService\DC2`\n\
      \\aResolve\DC2).aaas.operator_registry.v1.ResolveRequest\SUB*.aaas.operator_registry.v1.ResolveResponse"
instance Data.ProtoLens.Service.Types.HasMethodImpl OperatorRegistryService "resolve" where
  type MethodName OperatorRegistryService "resolve" = "Resolve"
  type MethodInput OperatorRegistryService "resolve" = ResolveRequest
  type MethodOutput OperatorRegistryService "resolve" = ResolveResponse
  type MethodStreamingType OperatorRegistryService "resolve" = 'Data.ProtoLens.Service.Types.NonStreaming
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \1aaas/operator_registry/v1/operator_registry.proto\DC2\EMaaas.operator_registry.v1\",\n\
    \\SOResolveRequest\DC2\SUB\n\
    \\boperator\CAN\SOH \SOH(\tR\boperator\"?\n\
    \\SIResolveResponse\DC2\DC2\n\
    \\EOTsaga\CAN\SOH \SOH(\tR\EOTsaga\DC2\CAN\n\
    \\aenabled\CAN\STX \SOH(\bR\aenabled2{\n\
    \\ETBOperatorRegistryService\DC2`\n\
    \\aResolve\DC2).aaas.operator_registry.v1.ResolveRequest\SUB*.aaas.operator_registry.v1.ResolveResponseB\168\STX\n\
    \\GScom.aaas.operator_registry.v1B\NAKOperatorRegistryProtoP\SOHZngithub.com/JacKoz7/AaaS---Addition-as-a-Service/contracts/gen/go/aaas/operator_registry/v1;operator_registryv1\162\STX\ETXAOX\170\STX\CANAaas.OperatorRegistry.V1\202\STX\CANAaas\\OperatorRegistry\\V1\226\STX$Aaas\\OperatorRegistry\\V1\\GPBMetadata\234\STX\SUBAaas::OperatorRegistry::V1J\206\SO\n\
    \\ACK\DC2\EOT\DC1\NUL/\SOH\n\
    \\214\ENQ\n\
    \\SOH\f\DC2\ETX\DC1\NUL\DC22\203\ENQ SPDX-License-Identifier: MIT\n\
    \ Copyright (c) 2026 AaaS Contributors\n\
    \\n\
    \ Component:       contracts\n\
    \ Module:          aaas.operator_registry.v1\n\
    \ Owning Team:     Arithmetic Excellence Center (AEC)\n\
    \ Classification:  INTERNAL\n\
    \ Purpose:         gRPC contract of the operator-registry service: maps an\n\
    \                  operator symbol to the saga that executes it and reports\n\
    \                  whether the operation is currently enabled.\n\
    \ Related Docs:    CLAUDE.md (sections 3, 4.3), contracts/proto/README.md,\n\
    \                  ADR-0020\n\
    \\n\
    \ The proto package and directory use `operator_registry` (underscore)\n\
    \ because protobuf package names cannot contain the hyphen of the service\n\
    \ name `operator-registry` (ADR-0020).\n\
    \\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\DC3\NUL\"\n\
    \\229\SOH\n\
    \\STX\ACK\NUL\DC2\EOT\CAN\NUL\US\SOH\SUB\216\SOH OperatorRegistryService is the catalogue of arithmetic operations. AaaS\n\
    \ supports exactly one entry, `+`, executed by the saga `addition`; the\n\
    \ enabled flag reflects the feature flag `addition_enabled` (step P6.4).\n\
    \\n\
    \\n\
    \\n\
    \\ETX\ACK\NUL\SOH\DC2\ETX\CAN\b\US\n\
    \\249\SOH\n\
    \\EOT\ACK\NUL\STX\NUL\DC2\ETX\RS\STX8\SUB\235\SOH Resolve looks up an operator symbol.\n\
    \\n\
    \ An operator that is not in the catalogue yields the gRPC status\n\
    \ NOT_FOUND. A known but disabled operator is a successful response with\n\
    \ enabled set to false; the caller must not start the saga.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\SOH\DC2\ETX\RS\ACK\r\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\STX\DC2\ETX\RS\SO\FS\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\ETX\DC2\ETX\RS'6\n\
    \;\n\
    \\STX\EOT\NUL\DC2\EOT\"\NUL&\SOH\SUB/ ResolveRequest names the operator to look up.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX\"\b\SYN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX%\STX\b\n\
    \\DEL\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX%\STX\SYN\SUBr Operator symbol exactly as it appears in the expression, for example\n\
    \ \"+\". Matching is exact and case-sensitive.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX%\t\DC1\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX%\DC4\NAK\n\
    \E\n\
    \\STX\EOT\SOH\DC2\EOT)\NUL/\SOH\SUB9 ResolveResponse describes how the operator is executed.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX)\b\ETB\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX,\STX\b\n\
    \o\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX,\STX\DC2\SUBb Name of the saga (Temporal workflow family) that executes the\n\
    \ operator, for example \"addition\".\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX,\t\r\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX,\DLE\DC1\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ENQ\DC2\ETX.\STX\ACK\n\
    \;\n\
    \\EOT\EOT\SOH\STX\SOH\DC2\ETX.\STX\DC3\SUB. True when the operation may be executed now.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\SOH\DC2\ETX.\a\SO\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ETX\DC2\ETX.\DC1\DC2b\ACKproto3"