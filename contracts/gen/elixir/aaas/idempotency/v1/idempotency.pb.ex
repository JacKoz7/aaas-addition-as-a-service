defmodule Aaas.Idempotency.V1.ClaimRequest do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.idempotency.v1.ClaimRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :key, 1, type: :string
  field :task_id, 2, type: :string, json_name: "taskId"
end

defmodule Aaas.Idempotency.V1.ClaimResponse do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.idempotency.v1.ClaimResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :task_id, 1, type: :string, json_name: "taskId"
  field :existing, 2, type: :bool
end

defmodule Aaas.Idempotency.V1.MarkFailedRequest do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.idempotency.v1.MarkFailedRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :key, 1, type: :string
end

defmodule Aaas.Idempotency.V1.MarkFailedResponse do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.idempotency.v1.MarkFailedResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3
end

defmodule Aaas.Idempotency.V1.IdempotencyService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "aaas.idempotency.v1.IdempotencyService",
    protoc_gen_elixir_version: "0.17.1"

  rpc :Claim, Aaas.Idempotency.V1.ClaimRequest, Aaas.Idempotency.V1.ClaimResponse

  rpc :MarkFailed, Aaas.Idempotency.V1.MarkFailedRequest, Aaas.Idempotency.V1.MarkFailedResponse
end

defmodule Aaas.Idempotency.V1.IdempotencyService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Aaas.Idempotency.V1.IdempotencyService.Service
end
