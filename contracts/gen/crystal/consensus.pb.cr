## Generated from aaas/consensus/v1/consensus.proto for aaas.consensus.v1
require "protobuf"

module Aaas
  module Consensus
    module V1
      
      struct VoteRequest
        include ::Protobuf::Message
        
        contract_of "proto3" do
          optional :task_id, :string, 1
          optional :a, :uint32, 2
          optional :b, :uint32, 3
          optional :candidate, :uint32, 4
        end
      end
      
      struct VoteResponse
        include ::Protobuf::Message
        
        contract_of "proto3" do
          optional :accepted, :bool, 1
          optional :result, :uint32, 2
          repeated :votes, ReplicaVote, 3
        end
      end
      
      struct ReplicaVote
        include ::Protobuf::Message
        
        contract_of "proto3" do
          optional :replica, :string, 1
          optional :result, :uint32, 2
        end
      end
      end
    end
  end
