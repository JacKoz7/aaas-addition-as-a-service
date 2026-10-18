{- This file was auto-generated from aaas/consensus/v1/consensus.proto by the proto-lens-protoc program. -}
{-# LANGUAGE ScopedTypeVariables, DataKinds, TypeFamilies, UndecidableInstances, GeneralizedNewtypeDeriving, MultiParamTypeClasses, FlexibleContexts, FlexibleInstances, PatternSynonyms, MagicHash, NoImplicitPrelude, DataKinds, BangPatterns, TypeApplications, OverloadedStrings, DerivingStrategies#-}
{-# OPTIONS_GHC -Wno-unused-imports#-}
{-# OPTIONS_GHC -Wno-duplicate-exports#-}
{-# OPTIONS_GHC -Wno-dodgy-exports#-}
module Proto.Aaas.Consensus.V1.Consensus (
        ConsensusService(..), ReplicaVote(), VoteRequest(), VoteResponse()
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
     
         * 'Proto.Aaas.Consensus.V1.Consensus_Fields.replica' @:: Lens' ReplicaVote Data.Text.Text@
         * 'Proto.Aaas.Consensus.V1.Consensus_Fields.result' @:: Lens' ReplicaVote Data.Word.Word32@ -}
data ReplicaVote
  = ReplicaVote'_constructor {_ReplicaVote'replica :: !Data.Text.Text,
                              _ReplicaVote'result :: !Data.Word.Word32,
                              _ReplicaVote'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show ReplicaVote where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField ReplicaVote "replica" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ReplicaVote'replica
           (\ x__ y__ -> x__ {_ReplicaVote'replica = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField ReplicaVote "result" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _ReplicaVote'result (\ x__ y__ -> x__ {_ReplicaVote'result = y__}))
        Prelude.id
instance Data.ProtoLens.Message ReplicaVote where
  messageName _ = Data.Text.pack "aaas.consensus.v1.ReplicaVote"
  packedMessageDescriptor _
    = "\n\
      \\vReplicaVote\DC2\CAN\n\
      \\areplica\CAN\SOH \SOH(\tR\areplica\DC2\SYN\n\
      \\ACKresult\CAN\STX \SOH(\rR\ACKresult"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        replica__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "replica"
              (Data.ProtoLens.ScalarField Data.ProtoLens.StringField ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Text.Text)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"replica")) ::
              Data.ProtoLens.FieldDescriptor ReplicaVote
        result__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "result"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"result")) ::
              Data.ProtoLens.FieldDescriptor ReplicaVote
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, replica__field_descriptor),
           (Data.ProtoLens.Tag 2, result__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _ReplicaVote'_unknownFields
        (\ x__ y__ -> x__ {_ReplicaVote'_unknownFields = y__})
  defMessage
    = ReplicaVote'_constructor
        {_ReplicaVote'replica = Data.ProtoLens.fieldDefault,
         _ReplicaVote'result = Data.ProtoLens.fieldDefault,
         _ReplicaVote'_unknownFields = []}
  parseMessage
    = let
        loop ::
          ReplicaVote -> Data.ProtoLens.Encoding.Bytes.Parser ReplicaVote
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
                                       "replica"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"replica") y x)
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "result"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"result") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "ReplicaVote"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"replica") _x
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"result") _x
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
instance Control.DeepSeq.NFData ReplicaVote where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_ReplicaVote'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_ReplicaVote'replica x__)
                (Control.DeepSeq.deepseq (_ReplicaVote'result x__) ()))
{- | Fields :
     
         * 'Proto.Aaas.Consensus.V1.Consensus_Fields.taskId' @:: Lens' VoteRequest Data.Text.Text@
         * 'Proto.Aaas.Consensus.V1.Consensus_Fields.a' @:: Lens' VoteRequest Data.Word.Word32@
         * 'Proto.Aaas.Consensus.V1.Consensus_Fields.b' @:: Lens' VoteRequest Data.Word.Word32@
         * 'Proto.Aaas.Consensus.V1.Consensus_Fields.candidate' @:: Lens' VoteRequest Data.Word.Word32@ -}
data VoteRequest
  = VoteRequest'_constructor {_VoteRequest'taskId :: !Data.Text.Text,
                              _VoteRequest'a :: !Data.Word.Word32,
                              _VoteRequest'b :: !Data.Word.Word32,
                              _VoteRequest'candidate :: !Data.Word.Word32,
                              _VoteRequest'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show VoteRequest where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField VoteRequest "taskId" Data.Text.Text where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _VoteRequest'taskId (\ x__ y__ -> x__ {_VoteRequest'taskId = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField VoteRequest "a" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _VoteRequest'a (\ x__ y__ -> x__ {_VoteRequest'a = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField VoteRequest "b" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _VoteRequest'b (\ x__ y__ -> x__ {_VoteRequest'b = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField VoteRequest "candidate" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _VoteRequest'candidate
           (\ x__ y__ -> x__ {_VoteRequest'candidate = y__}))
        Prelude.id
instance Data.ProtoLens.Message VoteRequest where
  messageName _ = Data.Text.pack "aaas.consensus.v1.VoteRequest"
  packedMessageDescriptor _
    = "\n\
      \\vVoteRequest\DC2\ETB\n\
      \\atask_id\CAN\SOH \SOH(\tR\ACKtaskId\DC2\f\n\
      \\SOHa\CAN\STX \SOH(\rR\SOHa\DC2\f\n\
      \\SOHb\CAN\ETX \SOH(\rR\SOHb\DC2\FS\n\
      \\tcandidate\CAN\EOT \SOH(\rR\tcandidate"
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
              Data.ProtoLens.FieldDescriptor VoteRequest
        a__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "a"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"a")) ::
              Data.ProtoLens.FieldDescriptor VoteRequest
        b__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "b"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"b")) ::
              Data.ProtoLens.FieldDescriptor VoteRequest
        candidate__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "candidate"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"candidate")) ::
              Data.ProtoLens.FieldDescriptor VoteRequest
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, taskId__field_descriptor),
           (Data.ProtoLens.Tag 2, a__field_descriptor),
           (Data.ProtoLens.Tag 3, b__field_descriptor),
           (Data.ProtoLens.Tag 4, candidate__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _VoteRequest'_unknownFields
        (\ x__ y__ -> x__ {_VoteRequest'_unknownFields = y__})
  defMessage
    = VoteRequest'_constructor
        {_VoteRequest'taskId = Data.ProtoLens.fieldDefault,
         _VoteRequest'a = Data.ProtoLens.fieldDefault,
         _VoteRequest'b = Data.ProtoLens.fieldDefault,
         _VoteRequest'candidate = Data.ProtoLens.fieldDefault,
         _VoteRequest'_unknownFields = []}
  parseMessage
    = let
        loop ::
          VoteRequest -> Data.ProtoLens.Encoding.Bytes.Parser VoteRequest
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
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "a"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"a") y x)
                        24
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "b"
                                loop (Lens.Family2.set (Data.ProtoLens.Field.field @"b") y x)
                        32
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "candidate"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"candidate") y x)
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do loop Data.ProtoLens.defMessage) "VoteRequest"
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
                (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"a") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (let _v = Lens.Family2.view (Data.ProtoLens.Field.field @"b") _x
                    in
                      if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                          Data.Monoid.mempty
                      else
                          (Data.Monoid.<>)
                            (Data.ProtoLens.Encoding.Bytes.putVarInt 24)
                            ((Prelude..)
                               Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                   ((Data.Monoid.<>)
                      (let
                         _v = Lens.Family2.view (Data.ProtoLens.Field.field @"candidate") _x
                       in
                         if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                             Data.Monoid.mempty
                         else
                             (Data.Monoid.<>)
                               (Data.ProtoLens.Encoding.Bytes.putVarInt 32)
                               ((Prelude..)
                                  Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                      (Data.ProtoLens.Encoding.Wire.buildFieldSet
                         (Lens.Family2.view Data.ProtoLens.unknownFields _x)))))
instance Control.DeepSeq.NFData VoteRequest where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_VoteRequest'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_VoteRequest'taskId x__)
                (Control.DeepSeq.deepseq
                   (_VoteRequest'a x__)
                   (Control.DeepSeq.deepseq
                      (_VoteRequest'b x__)
                      (Control.DeepSeq.deepseq (_VoteRequest'candidate x__) ()))))
{- | Fields :
     
         * 'Proto.Aaas.Consensus.V1.Consensus_Fields.accepted' @:: Lens' VoteResponse Prelude.Bool@
         * 'Proto.Aaas.Consensus.V1.Consensus_Fields.result' @:: Lens' VoteResponse Data.Word.Word32@
         * 'Proto.Aaas.Consensus.V1.Consensus_Fields.votes' @:: Lens' VoteResponse [ReplicaVote]@
         * 'Proto.Aaas.Consensus.V1.Consensus_Fields.vec'votes' @:: Lens' VoteResponse (Data.Vector.Vector ReplicaVote)@ -}
data VoteResponse
  = VoteResponse'_constructor {_VoteResponse'accepted :: !Prelude.Bool,
                               _VoteResponse'result :: !Data.Word.Word32,
                               _VoteResponse'votes :: !(Data.Vector.Vector ReplicaVote),
                               _VoteResponse'_unknownFields :: !Data.ProtoLens.FieldSet}
  deriving stock (Prelude.Eq, Prelude.Ord)
instance Prelude.Show VoteResponse where
  showsPrec _ __x __s
    = Prelude.showChar
        '{'
        (Prelude.showString
           (Data.ProtoLens.showMessageShort __x) (Prelude.showChar '}' __s))
instance Data.ProtoLens.Field.HasField VoteResponse "accepted" Prelude.Bool where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _VoteResponse'accepted
           (\ x__ y__ -> x__ {_VoteResponse'accepted = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField VoteResponse "result" Data.Word.Word32 where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _VoteResponse'result
           (\ x__ y__ -> x__ {_VoteResponse'result = y__}))
        Prelude.id
instance Data.ProtoLens.Field.HasField VoteResponse "votes" [ReplicaVote] where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _VoteResponse'votes (\ x__ y__ -> x__ {_VoteResponse'votes = y__}))
        (Lens.Family2.Unchecked.lens
           Data.Vector.Generic.toList
           (\ _ y__ -> Data.Vector.Generic.fromList y__))
instance Data.ProtoLens.Field.HasField VoteResponse "vec'votes" (Data.Vector.Vector ReplicaVote) where
  fieldOf _
    = (Prelude..)
        (Lens.Family2.Unchecked.lens
           _VoteResponse'votes (\ x__ y__ -> x__ {_VoteResponse'votes = y__}))
        Prelude.id
instance Data.ProtoLens.Message VoteResponse where
  messageName _ = Data.Text.pack "aaas.consensus.v1.VoteResponse"
  packedMessageDescriptor _
    = "\n\
      \\fVoteResponse\DC2\SUB\n\
      \\baccepted\CAN\SOH \SOH(\bR\baccepted\DC2\SYN\n\
      \\ACKresult\CAN\STX \SOH(\rR\ACKresult\DC24\n\
      \\ENQvotes\CAN\ETX \ETX(\v2\RS.aaas.consensus.v1.ReplicaVoteR\ENQvotes"
  packedFileDescriptor _ = packedFileDescriptor
  fieldsByTag
    = let
        accepted__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "accepted"
              (Data.ProtoLens.ScalarField Data.ProtoLens.BoolField ::
                 Data.ProtoLens.FieldTypeDescriptor Prelude.Bool)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional
                 (Data.ProtoLens.Field.field @"accepted")) ::
              Data.ProtoLens.FieldDescriptor VoteResponse
        result__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "result"
              (Data.ProtoLens.ScalarField Data.ProtoLens.UInt32Field ::
                 Data.ProtoLens.FieldTypeDescriptor Data.Word.Word32)
              (Data.ProtoLens.PlainField
                 Data.ProtoLens.Optional (Data.ProtoLens.Field.field @"result")) ::
              Data.ProtoLens.FieldDescriptor VoteResponse
        votes__field_descriptor
          = Data.ProtoLens.FieldDescriptor
              "votes"
              (Data.ProtoLens.MessageField Data.ProtoLens.MessageType ::
                 Data.ProtoLens.FieldTypeDescriptor ReplicaVote)
              (Data.ProtoLens.RepeatedField
                 Data.ProtoLens.Unpacked (Data.ProtoLens.Field.field @"votes")) ::
              Data.ProtoLens.FieldDescriptor VoteResponse
      in
        Data.Map.fromList
          [(Data.ProtoLens.Tag 1, accepted__field_descriptor),
           (Data.ProtoLens.Tag 2, result__field_descriptor),
           (Data.ProtoLens.Tag 3, votes__field_descriptor)]
  unknownFields
    = Lens.Family2.Unchecked.lens
        _VoteResponse'_unknownFields
        (\ x__ y__ -> x__ {_VoteResponse'_unknownFields = y__})
  defMessage
    = VoteResponse'_constructor
        {_VoteResponse'accepted = Data.ProtoLens.fieldDefault,
         _VoteResponse'result = Data.ProtoLens.fieldDefault,
         _VoteResponse'votes = Data.Vector.Generic.empty,
         _VoteResponse'_unknownFields = []}
  parseMessage
    = let
        loop ::
          VoteResponse
          -> Data.ProtoLens.Encoding.Growing.Growing Data.Vector.Vector Data.ProtoLens.Encoding.Growing.RealWorld ReplicaVote
             -> Data.ProtoLens.Encoding.Bytes.Parser VoteResponse
        loop x mutable'votes
          = do end <- Data.ProtoLens.Encoding.Bytes.atEnd
               if end then
                   do frozen'votes <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                        (Data.ProtoLens.Encoding.Growing.unsafeFreeze mutable'votes)
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
                              (Data.ProtoLens.Field.field @"vec'votes") frozen'votes x))
               else
                   do tag <- Data.ProtoLens.Encoding.Bytes.getVarInt
                      case tag of
                        8 -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          ((Prelude./=) 0) Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "accepted"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"accepted") y x)
                                  mutable'votes
                        16
                          -> do y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                       (Prelude.fmap
                                          Prelude.fromIntegral
                                          Data.ProtoLens.Encoding.Bytes.getVarInt)
                                       "result"
                                loop
                                  (Lens.Family2.set (Data.ProtoLens.Field.field @"result") y x)
                                  mutable'votes
                        26
                          -> do !y <- (Data.ProtoLens.Encoding.Bytes.<?>)
                                        (do len <- Data.ProtoLens.Encoding.Bytes.getVarInt
                                            Data.ProtoLens.Encoding.Bytes.isolate
                                              (Prelude.fromIntegral len)
                                              Data.ProtoLens.parseMessage)
                                        "votes"
                                v <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                       (Data.ProtoLens.Encoding.Growing.append mutable'votes y)
                                loop x v
                        wire
                          -> do !y <- Data.ProtoLens.Encoding.Wire.parseTaggedValueFromWire
                                        wire
                                loop
                                  (Lens.Family2.over
                                     Data.ProtoLens.unknownFields (\ !t -> (:) y t) x)
                                  mutable'votes
      in
        (Data.ProtoLens.Encoding.Bytes.<?>)
          (do mutable'votes <- Data.ProtoLens.Encoding.Parser.Unsafe.unsafeLiftIO
                                 Data.ProtoLens.Encoding.Growing.new
              loop Data.ProtoLens.defMessage mutable'votes)
          "VoteResponse"
  buildMessage
    = \ _x
        -> (Data.Monoid.<>)
             (let
                _v = Lens.Family2.view (Data.ProtoLens.Field.field @"accepted") _x
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
                   _v = Lens.Family2.view (Data.ProtoLens.Field.field @"result") _x
                 in
                   if (Prelude.==) _v Data.ProtoLens.fieldDefault then
                       Data.Monoid.mempty
                   else
                       (Data.Monoid.<>)
                         (Data.ProtoLens.Encoding.Bytes.putVarInt 16)
                         ((Prelude..)
                            Data.ProtoLens.Encoding.Bytes.putVarInt Prelude.fromIntegral _v))
                ((Data.Monoid.<>)
                   (Data.ProtoLens.Encoding.Bytes.foldMapBuilder
                      (\ _v
                         -> (Data.Monoid.<>)
                              (Data.ProtoLens.Encoding.Bytes.putVarInt 26)
                              ((Prelude..)
                                 (\ bs
                                    -> (Data.Monoid.<>)
                                         (Data.ProtoLens.Encoding.Bytes.putVarInt
                                            (Prelude.fromIntegral (Data.ByteString.length bs)))
                                         (Data.ProtoLens.Encoding.Bytes.putBytes bs))
                                 Data.ProtoLens.encodeMessage _v))
                      (Lens.Family2.view (Data.ProtoLens.Field.field @"vec'votes") _x))
                   (Data.ProtoLens.Encoding.Wire.buildFieldSet
                      (Lens.Family2.view Data.ProtoLens.unknownFields _x))))
instance Control.DeepSeq.NFData VoteResponse where
  rnf
    = \ x__
        -> Control.DeepSeq.deepseq
             (_VoteResponse'_unknownFields x__)
             (Control.DeepSeq.deepseq
                (_VoteResponse'accepted x__)
                (Control.DeepSeq.deepseq
                   (_VoteResponse'result x__)
                   (Control.DeepSeq.deepseq (_VoteResponse'votes x__) ())))
data ConsensusService = ConsensusService {}
instance Data.ProtoLens.Service.Types.Service ConsensusService where
  type ServiceName ConsensusService = "ConsensusService"
  type ServicePackage ConsensusService = "aaas.consensus.v1"
  type ServiceMethods ConsensusService = '["vote"]
  packedServiceDescriptor _
    = "\n\
      \\DLEConsensusService\DC2G\n\
      \\EOTVote\DC2\RS.aaas.consensus.v1.VoteRequest\SUB\US.aaas.consensus.v1.VoteResponse"
instance Data.ProtoLens.Service.Types.HasMethodImpl ConsensusService "vote" where
  type MethodName ConsensusService "vote" = "Vote"
  type MethodInput ConsensusService "vote" = VoteRequest
  type MethodOutput ConsensusService "vote" = VoteResponse
  type MethodStreamingType ConsensusService "vote" = 'Data.ProtoLens.Service.Types.NonStreaming
packedFileDescriptor :: Data.ByteString.ByteString
packedFileDescriptor
  = "\n\
    \!aaas/consensus/v1/consensus.proto\DC2\DC1aaas.consensus.v1\"`\n\
    \\vVoteRequest\DC2\ETB\n\
    \\atask_id\CAN\SOH \SOH(\tR\ACKtaskId\DC2\f\n\
    \\SOHa\CAN\STX \SOH(\rR\SOHa\DC2\f\n\
    \\SOHb\CAN\ETX \SOH(\rR\SOHb\DC2\FS\n\
    \\tcandidate\CAN\EOT \SOH(\rR\tcandidate\"x\n\
    \\fVoteResponse\DC2\SUB\n\
    \\baccepted\CAN\SOH \SOH(\bR\baccepted\DC2\SYN\n\
    \\ACKresult\CAN\STX \SOH(\rR\ACKresult\DC24\n\
    \\ENQvotes\CAN\ETX \ETX(\v2\RS.aaas.consensus.v1.ReplicaVoteR\ENQvotes\"?\n\
    \\vReplicaVote\DC2\CAN\n\
    \\areplica\CAN\SOH \SOH(\tR\areplica\DC2\SYN\n\
    \\ACKresult\CAN\STX \SOH(\rR\ACKresult2[\n\
    \\DLEConsensusService\DC2G\n\
    \\EOTVote\DC2\RS.aaas.consensus.v1.VoteRequest\SUB\US.aaas.consensus.v1.VoteResponseB\237\SOH\n\
    \\NAKcom.aaas.consensus.v1B\SOConsensusProtoP\SOHZ^github.com/JacKoz7/AaaS---Addition-as-a-Service/contracts/gen/go/aaas/consensus/v1;consensusv1\162\STX\ETXACX\170\STX\DC1Aaas.Consensus.V1\202\STX\DC1Aaas\\Consensus\\V1\226\STX\GSAaas\\Consensus\\V1\\GPBMetadata\234\STX\DC3Aaas::Consensus::V1J\166\DC3\n\
    \\ACK\DC2\EOT\r\NUL;\SOH\n\
    \\166\EOT\n\
    \\SOH\f\DC2\ETX\r\NUL\DC22\155\EOT SPDX-License-Identifier: MIT\n\
    \ Copyright (c) 2026 AaaS Contributors\n\
    \\n\
    \ Component:       contracts\n\
    \ Module:          aaas.consensus.v1\n\
    \ Owning Team:     Transaction Integrity Office (TIO)\n\
    \ Classification:  INTERNAL\n\
    \ Purpose:         gRPC contract of the consensus service: three replicas\n\
    \                  compute a + b independently and the Raft cluster commits\n\
    \                  the majority result, which must match the Peano result.\n\
    \ Related Docs:    CLAUDE.md (sections 1, 3, 4.3), contracts/proto/README.md,\n\
    \                  ADR-0020\n\
    \\n\
    \\b\n\
    \\SOH\STX\DC2\ETX\SI\NUL\SUB\n\
    \\146\SOH\n\
    \\STX\ACK\NUL\DC2\EOT\DC3\NUL\FS\SOH\SUB\133\SOH ConsensusService verifies a Peano result by majority vote. The saga calls\n\
    \ it once per task, after the successor loop has finished.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\ACK\NUL\SOH\DC2\ETX\DC3\b\CAN\n\
    \\144\ETX\n\
    \\EOT\ACK\NUL\STX\NUL\DC2\ETX\ESC\STX/\SUB\130\ETX Vote asks every replica to compute a + b, commits the majority result\n\
    \ through Raft and compares it with the candidate.\n\
    \\n\
    \ A disagreement with the candidate is a successful response with\n\
    \ accepted set to false; the saga then fails the task. When no majority\n\
    \ can be formed (fewer than two replicas agree, or fewer than two answer\n\
    \ in time), the call yields the gRPC status UNAVAILABLE.\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\SOH\DC2\ETX\ESC\ACK\n\
    \\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\STX\DC2\ETX\ESC\v\SYN\n\
    \\f\n\
    \\ENQ\ACK\NUL\STX\NUL\ETX\DC2\ETX\ESC!-\n\
    \H\n\
    \\STX\EOT\NUL\DC2\EOT\US\NUL)\SOH\SUB< VoteRequest carries the addition and the result to verify.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\NUL\SOH\DC2\ETX\US\b\DC3\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ENQ\DC2\ETX\"\STX\b\n\
    \\139\SOH\n\
    \\EOT\EOT\NUL\STX\NUL\DC2\ETX\"\STX\NAK\SUB~ Task identifier (UUIDv7, canonical text form); repeated votes for the\n\
    \ same task return the result committed the first time.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\SOH\DC2\ETX\"\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\NUL\ETX\DC2\ETX\"\DC3\DC4\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ENQ\DC2\ETX$\STX\b\n\
    \+\n\
    \\EOT\EOT\NUL\STX\SOH\DC2\ETX$\STX\SI\SUB\RS First operand, in 0..99 999.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\SOH\DC2\ETX$\t\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\SOH\ETX\DC2\ETX$\r\SO\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ENQ\DC2\ETX&\STX\b\n\
    \,\n\
    \\EOT\EOT\NUL\STX\STX\DC2\ETX&\STX\SI\SUB\US Second operand, in 0..99 999.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\SOH\DC2\ETX&\t\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\STX\ETX\DC2\ETX&\r\SO\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ENQ\DC2\ETX(\STX\b\n\
    \@\n\
    \\EOT\EOT\NUL\STX\ETX\DC2\ETX(\STX\ETB\SUB3 Result computed by the Peano loop, in 0..199 998.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\SOH\DC2\ETX(\t\DC2\n\
    \\f\n\
    \\ENQ\EOT\NUL\STX\ETX\ETX\DC2\ETX(\NAK\SYN\n\
    \Q\n\
    \\STX\EOT\SOH\DC2\EOT,\NUL3\SOH\SUBE VoteResponse carries the committed majority result and the ballots.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\SOH\SOH\DC2\ETX,\b\DC4\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ENQ\DC2\ETX.\STX\ACK\n\
    \B\n\
    \\EOT\EOT\SOH\STX\NUL\DC2\ETX.\STX\DC4\SUB5 True when the majority result equals the candidate.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\SOH\DC2\ETX.\a\SI\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\NUL\ETX\DC2\ETX.\DC2\DC3\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ENQ\DC2\ETX0\STX\b\n\
    \E\n\
    \\EOT\EOT\SOH\STX\SOH\DC2\ETX0\STX\DC4\SUB8 Majority result committed through Raft, in 0..199 998.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\SOH\DC2\ETX0\t\SI\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\SOH\ETX\DC2\ETX0\DC2\DC3\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\EOT\DC2\ETX2\STX\n\
    \\n\
    \L\n\
    \\EOT\EOT\SOH\STX\STX\DC2\ETX2\STX!\SUB? One ballot per replica that answered, in no particular order.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ACK\DC2\ETX2\v\SYN\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\SOH\DC2\ETX2\ETB\FS\n\
    \\f\n\
    \\ENQ\EOT\SOH\STX\STX\ETX\DC2\ETX2\US \n\
    \7\n\
    \\STX\EOT\STX\DC2\EOT6\NUL;\SOH\SUB+ ReplicaVote is the ballot of one replica.\n\
    \\n\
    \\n\
    \\n\
    \\ETX\EOT\STX\SOH\DC2\ETX6\b\DC3\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ENQ\DC2\ETX8\STX\b\n\
    \C\n\
    \\EOT\EOT\STX\STX\NUL\DC2\ETX8\STX\NAK\SUB6 Replica name, for example \"consensus-replica-cobol\".\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\SOH\DC2\ETX8\t\DLE\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\NUL\ETX\DC2\ETX8\DC3\DC4\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ENQ\DC2\ETX:\STX\b\n\
    \@\n\
    \\EOT\EOT\STX\STX\SOH\DC2\ETX:\STX\DC4\SUB3 a + b as computed by that replica, in 0..199 998.\n\
    \\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\SOH\DC2\ETX:\t\SI\n\
    \\f\n\
    \\ENQ\EOT\STX\STX\SOH\ETX\DC2\ETX:\DC2\DC3b\ACKproto3"