defmodule Aaas.Successor.V1.NextRequest do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.successor.v1.NextRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :n, 1, type: :uint32
  field :task_id, 2, type: :string, json_name: "taskId"
end

defmodule Aaas.Successor.V1.NextResponse do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.successor.v1.NextResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :n, 1, type: :uint32
end

defmodule Aaas.Successor.V1.SuccessorService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "aaas.successor.v1.SuccessorService",
    protoc_gen_elixir_version: "0.17.1"

  rpc :Next, Aaas.Successor.V1.NextRequest, Aaas.Successor.V1.NextResponse
end

defmodule Aaas.Successor.V1.SuccessorService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Aaas.Successor.V1.SuccessorService.Service
end
