## Generated from aaas/commutator/v1/commutator.proto for aaas.commutator.v1
require "protobuf"

module Aaas
  module Commutator
    module V1
      
      struct NormalizeRequest
        include ::Protobuf::Message
        
        contract_of "proto3" do
          optional :a, :uint32, 1
          optional :b, :uint32, 2
        end
      end
      
      struct NormalizeResponse
        include ::Protobuf::Message
        
        contract_of "proto3" do
          optional :a, :uint32, 1
          optional :b, :uint32, 2
          optional :swapped, :bool, 3
        end
      end
      end
    end
  end
