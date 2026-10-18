from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class VoteRequest(_message.Message):
    __slots__ = ("task_id", "a", "b", "candidate")
    TASK_ID_FIELD_NUMBER: _ClassVar[int]
    A_FIELD_NUMBER: _ClassVar[int]
    B_FIELD_NUMBER: _ClassVar[int]
    CANDIDATE_FIELD_NUMBER: _ClassVar[int]
    task_id: str
    a: int
    b: int
    candidate: int
    def __init__(self, task_id: _Optional[str] = ..., a: _Optional[int] = ..., b: _Optional[int] = ..., candidate: _Optional[int] = ...) -> None: ...

class VoteResponse(_message.Message):
    __slots__ = ("accepted", "result", "votes")
    ACCEPTED_FIELD_NUMBER: _ClassVar[int]
    RESULT_FIELD_NUMBER: _ClassVar[int]
    VOTES_FIELD_NUMBER: _ClassVar[int]
    accepted: bool
    result: int
    votes: _containers.RepeatedCompositeFieldContainer[ReplicaVote]
    def __init__(self, accepted: _Optional[bool] = ..., result: _Optional[int] = ..., votes: _Optional[_Iterable[_Union[ReplicaVote, _Mapping]]] = ...) -> None: ...

class ReplicaVote(_message.Message):
    __slots__ = ("replica", "result")
    REPLICA_FIELD_NUMBER: _ClassVar[int]
    RESULT_FIELD_NUMBER: _ClassVar[int]
    replica: str
    result: int
    def __init__(self, replica: _Optional[str] = ..., result: _Optional[int] = ...) -> None: ...
