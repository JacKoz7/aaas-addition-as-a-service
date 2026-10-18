defmodule Aaas.OperatorRegistry.V1.ResolveRequest do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.operator_registry.v1.ResolveRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :operator, 1, type: :string
end

defmodule Aaas.OperatorRegistry.V1.ResolveResponse do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.operator_registry.v1.ResolveResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :saga, 1, type: :string
  field :enabled, 2, type: :bool
end

defmodule Aaas.OperatorRegistry.V1.OperatorRegistryService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "aaas.operator_registry.v1.OperatorRegistryService",
    protoc_gen_elixir_version: "0.17.1"

  rpc :Resolve, Aaas.OperatorRegistry.V1.ResolveRequest, Aaas.OperatorRegistry.V1.ResolveResponse
end

defmodule Aaas.OperatorRegistry.V1.OperatorRegistryService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Aaas.OperatorRegistry.V1.OperatorRegistryService.Service
end
