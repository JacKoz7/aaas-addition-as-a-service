## Generated from aaas/carry/v1/carry.proto for aaas.carry.v1
require "protobuf"

module Aaas
  module Carry
    module V1
      
      struct PropagateRequest
        include ::Protobuf::Message
        
        contract_of "proto3" do
          repeated :digits, :uint32, 1
          optional :position, :uint32, 2
        end
      end
      
      struct PropagateResponse
        include ::Protobuf::Message
        
        contract_of "proto3" do
          repeated :digits, :uint32, 1
        end
      end
      end
    end
  end
