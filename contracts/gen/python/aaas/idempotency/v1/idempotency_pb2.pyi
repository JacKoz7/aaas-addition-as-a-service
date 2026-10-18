from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class ClaimRequest(_message.Message):
    __slots__ = ("key", "task_id")
    KEY_FIELD_NUMBER: _ClassVar[int]
    TASK_ID_FIELD_NUMBER: _ClassVar[int]
    key: str
    task_id: str
    def __init__(self, key: _Optional[str] = ..., task_id: _Optional[str] = ...) -> None: ...

class ClaimResponse(_message.Message):
    __slots__ = ("task_id", "existing")
    TASK_ID_FIELD_NUMBER: _ClassVar[int]
    EXISTING_FIELD_NUMBER: _ClassVar[int]
    task_id: str
    existing: bool
    def __init__(self, task_id: _Optional[str] = ..., existing: _Optional[bool] = ...) -> None: ...

class MarkFailedRequest(_message.Message):
    __slots__ = ("key",)
    KEY_FIELD_NUMBER: _ClassVar[int]
    key: str
    def __init__(self, key: _Optional[str] = ...) -> None: ...

class MarkFailedResponse(_message.Message):
    __slots__ = ()
    def __init__(self) -> None: ...
