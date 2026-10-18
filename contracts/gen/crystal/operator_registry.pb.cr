## Generated from aaas/operator_registry/v1/operator_registry.proto for aaas.operator_registry.v1
require "protobuf"

module Aaas
  module OperatorRegistry
    module V1
      
      struct ResolveRequest
        include ::Protobuf::Message
        
        contract_of "proto3" do
          optional :operator, :string, 1
        end
      end
      
      struct ResolveResponse
        include ::Protobuf::Message
        
        contract_of "proto3" do
          optional :saga, :string, 1
          optional :enabled, :bool, 2
        end
      end
      end
    end
  end
