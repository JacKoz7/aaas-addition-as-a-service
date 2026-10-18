from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class NormalizeRequest(_message.Message):
    __slots__ = ("a", "b")
    A_FIELD_NUMBER: _ClassVar[int]
    B_FIELD_NUMBER: _ClassVar[int]
    a: int
    b: int
    def __init__(self, a: _Optional[int] = ..., b: _Optional[int] = ...) -> None: ...

class NormalizeResponse(_message.Message):
    __slots__ = ("a", "b", "swapped")
    A_FIELD_NUMBER: _ClassVar[int]
    B_FIELD_NUMBER: _ClassVar[int]
    SWAPPED_FIELD_NUMBER: _ClassVar[int]
    a: int
    b: int
    swapped: bool
    def __init__(self, a: _Optional[int] = ..., b: _Optional[int] = ..., swapped: _Optional[bool] = ...) -> None: ...
