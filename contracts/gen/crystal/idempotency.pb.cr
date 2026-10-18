## Generated from aaas/idempotency/v1/idempotency.proto for aaas.idempotency.v1
require "protobuf"

module Aaas
  module Idempotency
    module V1
      
      struct ClaimRequest
        include ::Protobuf::Message
        
        contract_of "proto3" do
          optional :key, :string, 1
          optional :task_id, :string, 2
        end
      end
      
      struct ClaimResponse
        include ::Protobuf::Message
        
        contract_of "proto3" do
          optional :task_id, :string, 1
          optional :existing, :bool, 2
        end
      end
      
      struct MarkFailedRequest
        include ::Protobuf::Message
        
        contract_of "proto3" do
          optional :key, :string, 1
        end
      end
      
      struct MarkFailedResponse
        include ::Protobuf::Message
        
        contract_of "proto3" do
        end
      end
      end
    end
  end
