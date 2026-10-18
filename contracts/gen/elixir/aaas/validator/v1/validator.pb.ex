defmodule Aaas.Validator.V1.ValidateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.validator.v1.ValidateRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :a, 1, type: :uint64
  field :b, 2, type: :uint64
end

defmodule Aaas.Validator.V1.ValidateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.validator.v1.ValidateResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :ok, 1, type: :bool
  field :reason, 2, type: :string
end

defmodule Aaas.Validator.V1.ValidatorService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "aaas.validator.v1.ValidatorService",
    protoc_gen_elixir_version: "0.17.1"

  rpc :Validate, Aaas.Validator.V1.ValidateRequest, Aaas.Validator.V1.ValidateResponse
end

defmodule Aaas.Validator.V1.ValidatorService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Aaas.Validator.V1.ValidatorService.Service
end
