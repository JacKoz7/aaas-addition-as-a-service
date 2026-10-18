{- This file was auto-generated from aaas/carry/v1/carry.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Aaas.Carry.V1.Carry (
        CarryService(..), PropagateRequest(), PropagateResponse()
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
     
         * 'Proto.Aaas.Carry.V1.Carry_Fields.digits' @:: Lens' PropagateRequest [Data.Word.Word32]@
         * 'Proto.Aaas.Carry.V1.Carry_Fields.vec'digits' @:: Lens' PropagateRequest (Data.Vector.Unboxed.Vector Data.Word.Word32)@
         * 'Proto.Aaas.Carry.V1.Carry_Fields.position' @:: Lens' PropagateRequest Data.Word.Word32@ -}
data PropagateRequest
  = PropagateRequest'_constructor {_PropagateRequest'digits :: !(Data.Vector.Unboxed.Vector Data.Word.Word32),
                                   _PropagateRequest'position :: !Data.Word.Word32,
                                   _PropagateRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show PropagateRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField PropagateRequest "digits" [Data.Word.Word32] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _PropagateRequest'digits
           (\ x__ y__ -> x__ {_PropagateRequest'digits = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField PropagateRequest "vec'digits" (Data.Vector.Unboxed.Vector Data.Word.Word32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _PropagateRequest'digits
           (\ x__ y__ -> x__ {_PropagateRequest'digits = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField PropagateRequest "position" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _PropagateRequest'position
           (\ x__ y__ -> x__ {_PropagateRequest'position = y__}))
        Prelude.id
instance Data.ProtoLens.Message PropagateRequest where
  messageName _ = Data.Text.pack "aaas.carry.v1.PropagateRequest"
  packedMessageDescriptor _
    = "\n\
      \\DLEPropagateRequest\DC2\SYN\n\
      \\ACKdigits\CAN\SOH \ETX(\rR\ACKdigits\DC2\SUB\n\
      \\bposition\CAN\STX \SOH(\rR\bposition"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        digits__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "digits"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Packed (Data.ProtoLens.Field.field @"digits")) ::
              Data.ProtoLens.FieldDescriptor PropagateRequest
        position__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "position"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"position")) ::
              Data.ProtoLens.FieldDescriptor PropagateRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, digits__field_descriptor),
           (Data.ProtoLens.Tag 2, position__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _PropagateRequest'_unknownFields
        (\ x__ y__ -> x__ {_PropagateRequest'_unknownFields = y__})
  defMessage
    = PropagateRequest'_constructor
        {_PropagateRequest'digits = Data.Vector.Generic.empty,
         _PropagateRequest'position = Data.ProtoLens.fieldDefault,
         _PropagateRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          PropagateRequest
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Unboxed.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Word.Word32
             -> Data.ProtoLens.Encoding.Bytes.Parser PropagateRequest
        loop x mutable'digits
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'digits <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                         (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                            mutable'digits)
                      (let missing = []
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
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'digits") frozen'digits x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        8 -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (Prelude.fmap
                                           Prelude.fromIntegral
                                           Data.ProtoLens.Encoding.Bytes.getVarInt)
                                        "digits"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'digits y)
                                loop x v
                        10
                          -> do y <- do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                        Data.ProtoLens.Encoding.Bytes.isolate
                                          (Prelude.fromIntegral len)
                                          ((let
                                              ploop qs
                                                = do packedEnd <- Data.ProtoLens.Encoding.Bytes.atEnd
                                                     if packedEnd then
                                                         Prelude.return qs
                                                     else
                                                         do !q <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                                                    (Prelude.fmap
                                                                       Prelude.fromIntegral
                                                                       Data.ProtoLens.Encoding.Bytes.getVarInt)
                                                                    "digits"
                                                            qs' <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                                     (Data.ProtoLens.Encoding.Growing.append
                                                                        qs q)
                                                            ploop qs'
                                            in ploop)
                                             mutable'digits)
                                loop x y
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "position"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"position") y x)
                                  mutable'digits
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'digits
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'digits <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                  Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'digits)
          "PropagateRequest"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                p = Lens.Family2.view (Data.ProtoLens.Field.field @"vec'digits") _x
              in
                if Data.Vector.Generic.null p then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((\ bs
                          -> (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt
                                  (Prelude.fromIntegral (Data.ByteString.length bs)))
                               (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         (Data.ProtoLens.Encoding.Bytes.runBuilder
                            (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral)
                               p))))
             ((Data.Monoid.<>)
                (let
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"position") _x
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
instance Control.DeepSeq.NFData PropagateRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_PropagateRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_PropagateRequest'digits x__)
                (Control.DeepSeq.deepseq (_PropagateRequest'position x__) ()))
{- | Fields :
     
         * 'Proto.Aaas.Carry.V1.Carry_Fields.digits' @:: Lens' PropagateResponse [Data.Word.Word32]@
         * 'Proto.Aaas.Carry.V1.Carry_Fields.vec'digits' @:: Lens' PropagateResponse (Data.Vector.Unboxed.Vector Data.Word.Word32)@ -}
data PropagateResponse
  = PropagateResponse'_constructor {_PropagateResponse'digits :: !(Data.Vector.Unboxed.Vector Data.Word.Word32),
                                    _PropagateResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show PropagateResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField PropagateResponse "digits" [Data.Word.Word32] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _PropagateResponse'digits
           (\ x__ y__ -> x__ {_PropagateResponse'digits = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField PropagateResponse "vec'digits" (Data.Vector.Unboxed.Vector Data.Word.Word32) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _PropagateResponse'digits
           (\ x__ y__ -> x__ {_PropagateResponse'digits = y__}))
        Prelude.id
instance Data.ProtoLens.Message PropagateResponse where
  messageName _ = Data.Text.pack "aaas.carry.v1.PropagateResponse"
  packedMessageDescriptor _
    = "\n\
      \\DC1PropagateResponse\DC2\SYN\n\
      \\ACKdigits\CAN\SOH \ETX(\rR\ACKdigits"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        digits__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "digits"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Packed (Data.ProtoLens.Field.field @"digits")) ::
              Data.ProtoLens.FieldDescriptor PropagateResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, digits__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _PropagateResponse'_unknownFields
        (\ x__ y__ -> x__ {_PropagateResponse'_unknownFields = y__})
  defMessage
    = PropagateResponse'_constructor
        {_PropagateResponse'digits = Data.Vector.Generic.empty,
         _PropagateResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          PropagateResponse
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Unboxed.Vector Data.ProtoLens.Encoding.Growing.RealWorld Data.Word.Word32
             -> Data.ProtoLens.Encoding.Bytes.Parser PropagateResponse
        loop x mutable'digits
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'digits <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                         (Data.ProtoLens.Encoding.Growing.unsafeFreeze
                                            mutable'digits)
                      (let missing = []
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
                           Data.ProtoLens.unknownFields (\ !t -> Prelude.reverse t)
                           (Lens.Family2.set
                              (Data.ProtoLens.Field.field @"vec'digits") frozen'digits x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        8 -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (Prelude.fmap
                                           Prelude.fromIntegral
                                           Data.ProtoLens.Encoding.Bytes.getVarInt)
                                        "digits"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'digits y)
                                loop x v
                        10
                          -> do y <- do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                        Data.ProtoLens.Encoding.Bytes.isolate
                                          (Prelude.fromIntegral len)
                                          ((let
                                              ploop qs
                                                = do packedEnd <- Data.ProtoLens.Encoding.Bytes.atEnd
                                                     if packedEnd then
                                                         Prelude.return qs
                                                     else
                                                         do !q <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                                                    (Prelude.fmap
                                                                       Prelude.fromIntegral
                                                                       Data.ProtoLens.Encoding.Bytes.getVarInt)
                                                                    "digits"
                                                            qs' <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                                                     (Data.ProtoLens.Encoding.Growing.append
                                                                        qs q)
                                                            ploop qs'
                                            in ploop)
                                             mutable'digits)
                                loop x y
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'digits
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'digits <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                  Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'digits)
          "PropagateResponse"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                p = Lens.Family2.view (Data.ProtoLens.Field.field @"vec'digits") _x
              in
                if Data.Vector.Generic.null p then
                    Data.Monoid.mempty
                else
                    (Data.Monoid.<>)
                      (Data.ProtoLens.Encoding.Bytes.putVarInt 10)
                      ((\ bs
                          -> (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt
                                  (Prelude.fromIntegral (Data.ByteString.length bs)))
                               (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                         (Data.ProtoLens.Encoding.Bytes.runBuilder
                            (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral)
                               p))))
             (Data.ProtoLens.Encoding.Wire.buildFieldSet
                (Lens.Family2.view Data.ProtoLens.unknownFields _x))
instance Control.DeepSeq.NFData PropagateResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_PropagateResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq (_PropagateResponse'digits x__) ())
data CarryService = CarryService {}
instance Data.ProtoLens.Service.Types.Service CarryService where
  type ServiceName CarryService = "CarryService"
  type ServicePackage CarryService = "aaas.carry.v1"
  type ServiceMethods CarryService = '["propagate"]
  packedServiceDescriptor _
    = "\n\
      \\fCarryService\DC2N\n\
      \\tPropagate\DC2\US.aaas.carry.v1.PropagateRequest\SUB .aaas.carry.v1.PropagateResponse"
instance Data.ProtoLens.Service.Types.HasMethodImpl CarryService "propagate" where
  type MethodName CarryService "propagate" = "Propagate"
  type MethodInput CarryService "propagate" = PropagateRequest
  type MethodOutput CarryService "propagate" = PropagateResponse
  type MethodStreamingType CarryService "propagate" = 'Data.ProtoLens.Service.Types.NonStreaming
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \\EMaaas/carry/v1/carry.proto\DC2\raaas.carry.v1\"F\n\
    \\DLEPropagateRequest\DC2\SYN\n\
    \\ACKdigits\CAN\SOH \ETX(\rR\ACKdigits\DC2\SUB\n\
    \\bposition\CAN\STX \SOH(\rR\bposition\"+\n\
    \\DC1PropagateResponse\DC2\SYN\n\
    \\ACKdigits\CAN\SOH \ETX(\rR\ACKdigits2^\n\
    \\fCarryService\DC2N\n\
    \\tPropagate\DC2\US.aaas.carry.v1.PropagateRequest\SUB .aaas.carry.v1.PropagateResponseB\205\SOH\n\
    \\DC1com.aaas.carry.v1B\n\
    \CarryProtoP\SOHZVgithub.com/JacKoz7/AaaS---Addition-as-a-Service/contracts/gen/go/aaas/carry/v1;carryv1\162\STX\ETXACX\170\STX\rAaas.Carry.V1\202\STX\rAaas\\Carry\\V1\226\STX\EMAaas\\Carry\\V1\\GPBMetadata\234\STX\SIAaas::Carry::V1J\134\DLE\n\
    \\ACK\DC2\EOT\f\NUL/\SOH\n\
    \\213\ETX\n\
    \\SOH\f\DC2\ETX\f\NUL\DC22\202\ETX SPDX-License-Identifier: MIT\n\
    \ Copyright (c) 2026 AaaS Contributors\n\
    \\n\
    \ Component:       contracts\n\
    \ Module:          aaas.carry.v1\n\
    \ Owning Team:     Arithmetic Excellence Center (AEC)\n\
    \ Classification:  INTERNAL\n\
    \ Purpose:         gRPC contract of the carry service: propagates a carry\n\
    \                  of one to the higher decimal positions of a number.\n\
    \ Related Docs:    CLAUDE.md (sections 3, 4.3, 4.4), contracts/proto/README.md,\n\
    \                  ADR-0020\n\
    \\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\SO\NUL\SYN\n\
    \\149\STX\n\
    \\STX\ACK\NUL\DC2\EOT\DC4\NUL\GS\SOH\SUB\136\STX CarryService is called by the successor service when a digit service\n\
    \ reports a carry (digit 9 wrapped to 0). It adds one at the given position,\n\
    \ asking the digit service of each visited digit for its successor, and\n\
    \ continues upwards while digits keep wrapping.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\ACK\NUL\SOH\DC2\ETX\DC4\b\DC4\n\
    \\163\ETX\n\
    \\EOT\ACK\NUL\STX\NUL\DC2\ETX\FS\STX>\SUB\149\ETX Propagate adds one at digits[position] and propagates further carries.\n\
    \\n\
    \ Example: for 999 + 1, the units digit wraps from 9 to 0 and the\n\
    \ successor service sends digits [0, 9, 9] with position 1; the response\n\
    \ is [0, 0, 0, 1], that is 1000. A position greater than the number of digits, or a digit outside\n\
    \ 0..9, yields the gRPC status INVALID_ARGUMENT. An unreachable digit\n\
    \ service yields UNAVAILABLE.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\SOH\DC2\ETX\FS\ACK\SI\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\STX\DC2\ETX\FS\DLE \n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\ETX\DC2\ETX\FS+<\n\
    \l\n\
    \\STX\EOT\NUL\DC2\EOT!\NUL(\SOH\SUB` PropagateRequest carries a number as decimal digits and the position that\n\
    \ receives the carry.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX!\b\CAN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\EOT\DC2\ETX$\STX\n\
    \\n\
    \\131\SOH\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX$\STX\GS\SUBv Decimal digits of the number, least significant first (index 0 is the\n\
    \ units digit); each in 0..9, at most 6 digits.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX$\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX$\DC2\CAN\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX$\ESC\FS\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ENQ\DC2\ETX'\STX\b\n\
    \\151\SOH\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX'\STX\SYN\SUB\137\SOH Index of the digit that receives the carry, in 0..len(digits). When it\n\
    \ equals len(digits), a new most significant digit 1 is appended.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX'\t\DC1\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX'\DC4\NAK\n\
    \O\n\
    \\STX\EOT\SOH\DC2\EOT+\NUL/\SOH\SUBC PropagateResponse carries the number after the carry was applied.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX+\b\EM\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\EOT\DC2\ETX.\STX\n\
    \\n\
    \\148\SOH\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX.\STX\GS\SUB\134\SOH Decimal digits of the result, least significant first; one element\n\
    \ longer than the request when the carry passed the highest digit.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX.\v\DC1\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX.\DC2\CAN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX.\ESC\FSb\ACKproto3"