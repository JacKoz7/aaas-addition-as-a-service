from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from typing import ClassVar as _ClassVar, Optional as _Optional

DESCRIPTOR: _descriptor.FileDescriptor

class ResolveRequest(_message.Message):
    __slots__ = ("operator",)
    OPERATOR_FIELD_NUMBER: _ClassVar[int]
    operator: str
    def __init__(self, operator: _Optional[str] = ...) -> None: ...

class ResolveResponse(_message.Message):
    __slots__ = ("saga", "enabled")
    SAGA_FIELD_NUMBER: _ClassVar[int]
    ENABLED_FIELD_NUMBER: _ClassVar[int]
    saga: str
    enabled: bool
    def __init__(self, saga: _Optional[str] = ..., enabled: _Optional[bool] = ...) -> None: ...
