## Generated from aaas/successor/v1/successor.proto for aaas.successor.v1
require "protobuf"

module Aaas
  module Successor
    module V1
      
      struct NextRequest
        include ::Protobuf::Message
        
        contract_of "proto3" do
          optional :n, :uint32, 1
        end
      end
      
      struct NextResponse
        include ::Protobuf::Message
        
        contract_of "proto3" do
          optional :n, :uint32, 1
        end
      end
      end
    end
  end
