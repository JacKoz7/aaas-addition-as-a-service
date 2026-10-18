from google.protobuf.internal import containers as _containers
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class PropagateRequest(_message.Message):
    __slots__ = ("digits", "position")
    DIGITS_FIELD_NUMBER: _ClassVar[int]
    POSITION_FIELD_NUMBER: _ClassVar[int]
    digits: _containers.RepeatedScalarFieldContainer[int]
    position: int
    def __init__(self, digits: _Optional[_Iterable[int]] = ..., position: _Optional[int] = ...) -> None: ...

class PropagateResponse(_message.Message):
    __slots__ = ("digits",)
    DIGITS_FIELD_NUMBER: _ClassVar[int]
    digits: _containers.RepeatedScalarFieldContainer[int]
    def __init__(self, digits: _Optional[_Iterable[int]] = ...) -> None: ...
