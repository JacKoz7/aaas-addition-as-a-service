## Generated from aaas/validator/v1/validator.proto for aaas.validator.v1
require "protobuf"

module Aaas
  module Validator
    module V1
      
      struct ValidateRequest
        include ::Protobuf::Message
        
        contract_of "proto3" do
          optional :a, :uint64, 1
          optional :b, :uint64, 2
        end
      end
      
      struct ValidateResponse
        include ::Protobuf::Message
        
        contract_of "proto3" do
          optional :ok, :bool, 1
          optional :reason, :string, 2
        end
      end
      end
    end
  end
