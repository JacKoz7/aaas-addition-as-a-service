# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          infra/buf/protoc_gen_grpc_python.py
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         protoc plugin `protoc-gen-grpc_python` of the aaas/buf:dev
#                  image: adapts the grpc_python generator, which grpcio-tools
#                  ships only built into its own protoc, to the plugin
#                  protocol that buf speaks.
# Related Docs:    ADR-0020, infra/buf/Dockerfile, contracts/proto/buf.gen.yaml
"""protoc plugin that runs the grpc_python generator of grpcio-tools.

buf runs every plugin that is not a built-in generator of a stock protoc as
``protoc-gen-<name>``, but grpcio-tools has no such executable: grpc_python
exists only inside ``grpc_tools.protoc``. This adapter reads the
``CodeGeneratorRequest`` from stdin, hands the request's descriptors to
``grpc_tools.protoc`` with ``--descriptor_set_in``, and returns the files it
wrote as a ``CodeGeneratorResponse`` on stdout.
"""

import pathlib
import sys
import tempfile

from google.protobuf import descriptor_pb2
from google.protobuf.compiler import plugin_pb2
from grpc_tools import protoc


def generate(request: plugin_pb2.CodeGeneratorRequest) -> plugin_pb2.CodeGeneratorResponse:
    """Run grpc_python on the files of a plugin request.

    Summary:
        Turns one plugin request into one plugin response.

    Description:
        Writes ``request.proto_file`` (every file to generate plus its
        dependencies, in dependency order) to a temporary FileDescriptorSet,
        runs ``grpc_tools.protoc`` on ``request.file_to_generate`` with the
        request's parameter, and collects every written file with its path
        relative to the output directory. A non-zero protoc status becomes
        the ``error`` field of the response, as the plugin protocol requires.

    Business Justification:
        Lets buf generate the gRPC stubs of the Python consensus replica
        (P4.2) without a remote plugin registry (ADR-0020).

    Parameters:
        request (plugin_pb2.CodeGeneratorRequest): request read from buf.

    Returns:
        plugin_pb2.CodeGeneratorResponse: generated files, or an error.

    Errors:
        None raised; generator failures are reported in the response.

    Side Effects:
        Creates and removes a temporary directory.

    Complexity: O(s) time and memory in the size of the descriptors and the
        generated code.
    Thread Safety: safe (no shared state).
    Owner: Platform Enablement Guild (PEG)
    Since: buf image 0.1.0

    Example:
        >>> generate(plugin_pb2.CodeGeneratorRequest()).file
        []

    See Also: main, contracts/proto/buf.gen.yaml.
    """
    response = plugin_pb2.CodeGeneratorResponse()
    if not request.file_to_generate:
        return response
    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        out = work / "out"
        out.mkdir()
        descriptors = work / "descriptors.binpb"
        descriptors.write_bytes(descriptor_pb2.FileDescriptorSet(file=request.proto_file).SerializeToString())
        target = f"{request.parameter}:{out}" if request.parameter else str(out)
        status = protoc.main(
            [
                "grpc_tools.protoc",
                f"--descriptor_set_in={descriptors}",
                f"--grpc_python_out={target}",
                *request.file_to_generate,
            ]
        )
        if status != 0:
            response.error = f"grpc_tools.protoc exited with status {status}"
            return response
        for path in sorted(p for p in out.rglob("*") if p.is_file()):
            response.file.add(name=path.relative_to(out).as_posix(), content=path.read_text(encoding="utf-8"))
    return response


def main() -> int:
    """Read a request from stdin and write the response to stdout.

    Summary:
        Entry point of the plugin executable.

    Description:
        Implements the protoc plugin protocol: one serialized
        ``CodeGeneratorRequest`` in, one ``CodeGeneratorResponse`` out.

    Business Justification:
        See :func:`generate`.

    Parameters:
        None.

    Returns:
        int: 0; errors travel in the response.

    Errors:
        google.protobuf.message.DecodeError: stdin is not a valid request.

    Side Effects:
        Reads stdin, writes stdout.

    Complexity: as :func:`generate`.
    Thread Safety: not applicable (process entry point).
    Owner: Platform Enablement Guild (PEG)
    Since: buf image 0.1.0

    Example:
        Run by buf as ``protoc-gen-grpc_python``; not called directly.

    See Also: generate.
    """
    request = plugin_pb2.CodeGeneratorRequest.FromString(sys.stdin.buffer.read())
    sys.stdout.buffer.write(generate(request).SerializeToString())
    return 0


if __name__ == "__main__":
    sys.exit(main())
