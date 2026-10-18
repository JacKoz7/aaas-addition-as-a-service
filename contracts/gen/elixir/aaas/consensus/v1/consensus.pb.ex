defmodule Aaas.Consensus.V1.VoteRequest do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.consensus.v1.VoteRequest",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :task_id, 1, type: :string, json_name: "taskId"
  field :a, 2, type: :uint32
  field :b, 3, type: :uint32
  field :candidate, 4, type: :uint32
end

defmodule Aaas.Consensus.V1.VoteResponse do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.consensus.v1.VoteResponse",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :accepted, 1, type: :bool
  field :result, 2, type: :uint32
  field :votes, 3, repeated: true, type: Aaas.Consensus.V1.ReplicaVote
end

defmodule Aaas.Consensus.V1.ReplicaVote do
  @moduledoc false

  use Protobuf,
    full_name: "aaas.consensus.v1.ReplicaVote",
    protoc_gen_elixir_version: "0.17.1",
    syntax: :proto3

  field :replica, 1, type: :string
  field :result, 2, type: :uint32
end

defmodule Aaas.Consensus.V1.ConsensusService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "aaas.consensus.v1.ConsensusService",
    protoc_gen_elixir_version: "0.17.1"

  rpc :Vote, Aaas.Consensus.V1.VoteRequest, Aaas.Consensus.V1.VoteResponse
end

defmodule Aaas.Consensus.V1.ConsensusService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Aaas.Consensus.V1.ConsensusService.Service
end
