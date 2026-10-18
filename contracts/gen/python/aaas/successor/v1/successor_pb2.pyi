from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class NextRequest(_message.Message):
    __slots__ = ("n", "task_id")
    N_FIELD_NUMBER: _ClassVar[int]
    TASK_ID_FIELD_NUMBER: _ClassVar[int]
    n: int
    task_id: str
    def __init__(self, n: _Optional[int] = ..., task_id: _Optional[str] = ...) -> None: ...

class NextResponse(_message.Message):
    __slots__ = ("n",)
    N_FIELD_NUMBER: _ClassVar[int]
    n: int
    def __init__(self, n: _Optional[int] = ...) -> None: ...
