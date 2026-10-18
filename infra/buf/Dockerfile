# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       repo
# Module:          infra/buf/Dockerfile
# Owning Team:     Platform Enablement Guild (PEG)
# Classification:  INTERNAL
# Purpose:         Tool image of the gRPC contracts: buf (lint, breaking,
#                  generate) and the protoc plugins of the nine languages
#                  that consume contracts/proto (Go, Rust, Haskell, OCaml,
#                  Elixir, C#, Crystal, Zig, Python).
# Related Docs:    ADR-0020, contracts/proto/README.md,
#                  contracts/proto/buf.gen.yaml, Makefile (targets
#                  proto-image, proto, proto-check)
#
# The image is a developer tool, not a runtime service: it is built and run by
# `make proto` and `make proto-check`, never by Compose. The repository is
# mounted at /work and the container runs with the caller's UID.
#
# Every plugin is built from source at a pinned version in a stage of its own
# language and only the resulting binary is copied into the final image, so
# the large toolchain images are needed only while building. Binaries from
# Go, Rust, OCaml, Crystal and Zig are static; proto-lens-protoc (Haskell)
# needs libgmp, protoc-gen-elixir needs an Erlang runtime and the Python
# generators run on the Debian Python. All base images are multi-arch
# (linux/amd64, linux/arm64).

# ---------------------------------------------------------------------------
# Go: buf itself, protoc-gen-go and protoc-gen-go-grpc (static, CGO off).
# ---------------------------------------------------------------------------
FROM golang:1.27.2-alpine3.24 AS go-plugins
ARG BUF_VERSION=v1.74.0
ARG PROTOC_GEN_GO_VERSION=v1.36.12
ARG PROTOC_GEN_GO_GRPC_VERSION=v1.6.2
ENV CGO_ENABLED=0 GOBIN=/out
RUN go install "github.com/bufbuild/buf/cmd/buf@${BUF_VERSION}" \
    && go install "google.golang.org/protobuf/cmd/protoc-gen-go@${PROTOC_GEN_GO_VERSION}" \
    && go install "google.golang.org/grpc/cmd/protoc-gen-go-grpc@${PROTOC_GEN_GO_GRPC_VERSION}" \
    && rm -rf /root/go /root/.cache

# ---------------------------------------------------------------------------
# Rust: protoc-gen-prost (messages) and protoc-gen-tonic (services), for
# prost/tonic 0.14. The musl target of rust:alpine links statically.
# ---------------------------------------------------------------------------
FROM rust:1.99.1-alpine3.24 AS rust-plugins
ARG PROTOC_GEN_PROST_VERSION=0.5.0
ARG PROTOC_GEN_TONIC_VERSION=0.5.0
RUN cargo install --locked --root /out "protoc-gen-prost@${PROTOC_GEN_PROST_VERSION}" \
    && cargo install --locked --root /out "protoc-gen-tonic@${PROTOC_GEN_TONIC_VERSION}" \
    && rm -rf /usr/local/cargo/registry

# ---------------------------------------------------------------------------
# Haskell: proto-lens-protoc, on the GHC image of the successor service and
# at the same Hackage index state (services/successor/Dockerfile).
# ---------------------------------------------------------------------------
FROM haskell:9.10.3-slim-bookworm AS haskell-plugins
ARG PROTO_LENS_PROTOC_VERSION=0.9.0.1
ARG HACKAGE_INDEX_STATE=2026-10-15T00:00:00Z
RUN cabal update "hackage.haskell.org,${HACKAGE_INDEX_STATE}" \
    && cabal install --index-state="${HACKAGE_INDEX_STATE}" --installdir=/out \
       --install-method=copy "proto-lens-protoc-${PROTO_LENS_PROTOC_VERSION}" \
    && rm -rf /root/.cabal/packages /root/.cache/cabal /root/.local/state/cabal

# ---------------------------------------------------------------------------
# OCaml: protoc-gen-ocaml of ocaml-protoc-plugin, on the opam image of the
# parser service, from the opam repository snapshot of that image (no
# `opam update`, as in services/parser/Dockerfile; 6.2.0 is the newest
# version it has). OCAMLPARAM links the executable statically against musl.
# ---------------------------------------------------------------------------
FROM ocaml/opam:alpine-3.22-ocaml-4.14 AS ocaml-plugins
ARG OCAML_PROTOC_PLUGIN_VERSION=6.2.0
# conf-protoc, a build dependency, requires protoc and the protobuf headers;
# they are used only while building. Root only installs the Alpine
# packages; numeric IDs, as hadolint DL3066 asks.
USER 0:0
RUN apk add --no-cache protobuf=29.4-r0 protobuf-dev=29.4-r0
USER 1000:1000
RUN OCAMLPARAM='_,ccopt=-static' opam install -y "ocaml-protoc-plugin.${OCAML_PROTOC_PLUGIN_VERSION}" \
    && mkdir -p /home/opam/out \
    && cp "$(opam var bin)/protoc-gen-ocaml" /home/opam/out/ \
    && opam clean -a -c -s --logs

# ---------------------------------------------------------------------------
# Elixir: protoc-gen-elixir of the hex package protobuf, as an escript. It is
# built on OTP 25, the Erlang release of Debian bookworm that runs it in the
# final image.
# ---------------------------------------------------------------------------
FROM elixir:1.18.4-otp-25-slim AS elixir-plugins
ARG ELIXIR_PROTOBUF_VERSION=0.17.1
# The slim image has no CA certificates, which mix needs to reach hex.pm.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates=20250419~deb12u1 \
    && rm -rf /var/lib/apt/lists/*
RUN mix local.hex --force \
    && mix escript.install --force hex protobuf "${ELIXIR_PROTOBUF_VERSION}" \
    && mkdir -p /out \
    && cp /root/.mix/escripts/protoc-gen-elixir /out/

# ---------------------------------------------------------------------------
# Crystal: protoc-gen-crystal of protobuf.cr, linked statically.
# ---------------------------------------------------------------------------
FROM crystallang/crystal:1.22.0-alpine AS crystal-plugins
ARG PROTOBUF_CR_VERSION=2.3.1
ARG PROTOBUF_CR_SHA256=47428109040c5924d63a61b89d85252ba685fb7c6c4a38b3d03d02368a38927f
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
WORKDIR /src
ADD --checksum=sha256:${PROTOBUF_CR_SHA256} \
    https://github.com/jeromegn/protobuf.cr/archive/refs/tags/v${PROTOBUF_CR_VERSION}.tar.gz /tmp/protobuf.tar.gz
RUN tar -xzf /tmp/protobuf.tar.gz --strip-components=1 \
    && mkdir -p /out \
    && crystal build --release --static --no-debug -o /out/protoc-gen-crystal bin/protoc-gen-crystal.cr

# ---------------------------------------------------------------------------
# Zig: protoc-gen-zig of zig-protobuf 6.0.0, which requires Zig 0.16.0.
# ---------------------------------------------------------------------------
FROM alpine:3.22.2 AS zig-plugins
ARG TARGETARCH
ARG ZIG_VERSION=0.16.0
ARG ZIG_SHA256_AMD64=70e49664a74374b48b51e6f3fdfbf437f6395d42509050588bd49abe52ba3d00
ARG ZIG_SHA256_ARM64=ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17
ARG ZIG_PROTOBUF_VERSION=6.0.0
ARG ZIG_PROTOBUF_SHA256=def36850331a455884deca3d145a6df096fbcfc40945ccd83686baef57eb72af
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN apk add --no-cache xz=5.8.4-r0 curl=8.14.1-r3
WORKDIR /src
ADD --checksum=sha256:${ZIG_PROTOBUF_SHA256} \
    https://github.com/Arwalk/zig-protobuf/archive/refs/tags/v${ZIG_PROTOBUF_VERSION}.tar.gz /tmp/zig-protobuf.tar.gz
RUN case "${TARGETARCH}" in \
        amd64) arch=x86_64; sum="${ZIG_SHA256_AMD64}" ;; \
        arm64) arch=aarch64; sum="${ZIG_SHA256_ARM64}" ;; \
        *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL --retry 5 --retry-all-errors -o zig.tar.xz \
       "https://ziglang.org/download/${ZIG_VERSION}/zig-${arch}-linux-${ZIG_VERSION}.tar.xz" \
    && echo "${sum}  zig.tar.xz" | sha256sum -c - \
    && mkdir /opt/zig && tar -xJf zig.tar.xz -C /opt/zig --strip-components=1 && rm zig.tar.xz \
    && tar -xzf /tmp/zig-protobuf.tar.gz --strip-components=1 \
    && /opt/zig/zig build install -Doptimize=ReleaseSafe -Dtarget="${arch}-linux-musl" --prefix /out \
    && rm -rf /root/.cache/zig

# ---------------------------------------------------------------------------
# C#: protoc and grpc_csharp_plugin from the Grpc.Tools NuGet package (the
# package that .NET services use through MSBuild).
# ---------------------------------------------------------------------------
FROM alpine:3.22.2 AS csharp-plugins
ARG TARGETARCH
ARG GRPC_TOOLS_VERSION=2.84.0
ARG GRPC_TOOLS_SHA256=1bfc81e6a218d71a9d9b0569ec50b8e27697c5fa89a7bef926424434b0802d96
SHELL ["/bin/ash", "-eo", "pipefail", "-c"]
RUN apk add --no-cache curl=8.14.1-r3
WORKDIR /src
RUN case "${TARGETARCH}" in \
        amd64) arch=linux_x64 ;; \
        arm64) arch=linux_arm64 ;; \
        *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL --retry 5 --retry-all-errors -o grpc.tools.nupkg \
       "https://api.nuget.org/v3-flatcontainer/grpc.tools/${GRPC_TOOLS_VERSION}/grpc.tools.${GRPC_TOOLS_VERSION}.nupkg" \
    && echo "${GRPC_TOOLS_SHA256}  grpc.tools.nupkg" | sha256sum -c - \
    && unzip -q grpc.tools.nupkg "tools/${arch}/*" \
    && mkdir -p /out \
    && install -m 0755 "tools/${arch}/protoc" /out/protoc \
    && install -m 0755 "tools/${arch}/grpc_csharp_plugin" /out/grpc_csharp_plugin

# ---------------------------------------------------------------------------
# Final image: Debian bookworm (glibc for the Grpc.Tools and GHC binaries),
# Erlang for the Elixir escript, Python with grpcio-tools for the Python
# generators, git for `buf breaking` against a git reference.
# ---------------------------------------------------------------------------
FROM debian:bookworm-20251020-slim AS runtime

LABEL org.opencontainers.image.title="buf" \
      org.opencontainers.image.description="AaaS gRPC contract toolchain: buf and the protoc plugins of Go, Rust, Haskell, OCaml, Elixir, C#, Crystal, Zig and Python" \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/JacKoz7/AaaS---Addition-as-a-Service" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="AaaS Contributors" \
      com.aaas.owning-team="Platform Enablement Guild (PEG)"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates=20250419~deb12u1 git=1:2.39.5-0+deb12u3 libgmp10=2:6.2.1+dfsg1-1.1 \
       erlang-base=1:25.2.3+dfsg-1+deb12u4 python3=3.11.2-1+b1 python3-venv=3.11.2-1+b1 \
    && rm -rf /var/lib/apt/lists/*

# Python generators: grpc_tools.protoc is a protoc with the python, pyi and
# grpc_python generators built in; buf runs it through the wrapper below as
# the protoc of its protoc_builtin plugins (python, pyi), and grpc_python
# through the plugin adapter copied below. Every package is pinned.
RUN python3 -m venv /opt/venv \
    && /opt/venv/bin/pip install --no-cache-dir \
       "grpcio-tools==1.84.0" "grpcio==1.84.0" "protobuf==7.36.2" \
       "setuptools==84.0.0" "typing-extensions==4.15.0"
COPY --chmod=0755 <<'EOF' /usr/local/bin/protoc-python
#!/bin/sh
# protoc-python: protoc of grpcio-tools (python, pyi and grpc_python
# generators built in), used by buf.gen.yaml as protoc_path of the Python
# plugins.
exec /opt/venv/bin/python -m grpc_tools.protoc "$@"
EOF

# protoc-gen-grpc_python: adapter that exposes the grpc_python generator of
# grpcio-tools through the plugin protocol (buf does not treat it as a
# built-in generator).
COPY protoc_gen_grpc_python.py /usr/local/lib/aaas/protoc_gen_grpc_python.py
COPY --chmod=0755 <<'EOF' /usr/local/bin/protoc-gen-grpc_python
#!/bin/sh
# protoc-gen-grpc_python: runs infra/buf/protoc_gen_grpc_python.py on the
# Python of grpcio-tools.
exec /opt/venv/bin/python /usr/local/lib/aaas/protoc_gen_grpc_python.py "$@"
EOF

COPY --from=go-plugins /out/ /usr/local/bin/
COPY --from=rust-plugins /out/bin/ /usr/local/bin/
COPY --from=haskell-plugins /out/proto-lens-protoc /usr/local/bin/
# proto-lens-protoc pretty-prints with the GHC library, which reads the
# compiler settings from the GHC libdir at run time. Only those small files
# are copied, not the 1.8 GB of libraries next to them.
COPY --from=haskell-plugins /opt/ghc/9.10.3/lib/ghc-9.10.3/lib/settings \
     /opt/ghc/9.10.3/lib/ghc-9.10.3/lib/llvm-targets \
     /opt/ghc/9.10.3/lib/ghc-9.10.3/lib/llvm-passes \
     /opt/ghc/9.10.3/lib/ghc-9.10.3/lib/
COPY --from=ocaml-plugins /home/opam/out/protoc-gen-ocaml /usr/local/bin/
COPY --from=elixir-plugins /out/protoc-gen-elixir /usr/local/bin/
COPY --from=crystal-plugins /out/protoc-gen-crystal /usr/local/bin/
COPY --from=zig-plugins /out/bin/protoc-gen-zig /usr/local/bin/
COPY --from=csharp-plugins /out/ /usr/local/bin/

# buf keeps its cache under $HOME; the container runs with an arbitrary UID,
# so the cache goes to a world-writable directory.
# UTF-8 locale: the Erlang VM of protoc-gen-elixir warns under latin1.
ENV BUF_CACHE_DIR=/tmp/buf-cache LANG=C.UTF-8
WORKDIR /work
ENTRYPOINT ["buf"]
