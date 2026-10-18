defmodule Aaas.Commutator.V1.NormalizeRequest do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.commutator.v1.NormalizeRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :a, 1, type: :uint32
  field :b, 2, type: :uint32
end

defmodule Aaas.Commutator.V1.NormalizeResponse do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.commutator.v1.NormalizeResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :a, 1, type: :uint32
  field :b, 2, type: :uint32
  field :swapped, 3, type: :bool
end

defmodule Aaas.Commutator.V1.CommutatorService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "aaas.commutator.v1.CommutatorService",
    protoc_gen_elixir_version: "0.17.1"

  rpc :Normalize, Aaas.Commutator.V1.NormalizeRequest, Aaas.Commutator.V1.NormalizeResponse
end

defmodule Aaas.Commutator.V1.CommutatorService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Aaas.Commutator.V1.CommutatorService.Service
end
