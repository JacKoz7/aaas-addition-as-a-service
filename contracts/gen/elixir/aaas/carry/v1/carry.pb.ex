defmodule Aaas.Carry.V1.PropagateRequest do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.carry.v1.PropagateRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :digits, 1, repeated: true, type: :uint32
  field :position, 2, type: :uint32
  field :task_id, 3, type: :string, json_name: "taskId"
end

defmodule Aaas.Carry.V1.PropagateResponse do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.carry.v1.PropagateResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :digits, 1, repeated: true, type: :uint32
end

defmodule Aaas.Carry.V1.CarryService.Service do
  @moduledoc false

  use GRPC.Service, name: "aaas.carry.v1.CarryService", protoc_gen_elixir_version: "0.17.1"

  rpc :Propagate, Aaas.Carry.V1.PropagateRequest, Aaas.Carry.V1.PropagateResponse
end

defmodule Aaas.Carry.V1.CarryService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Aaas.Carry.V1.CarryService.Service
end
