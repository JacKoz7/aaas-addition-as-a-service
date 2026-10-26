# Threat Model — `successor`

| Field | Value |
| --- | --- |
| Document | Threat Model (STRIDE) |
| Component | `successor` |
| Owning Team | Arithmetic Excellence Center (AEC) |
| Classification | INTERNAL |
| Document Version | 1.1 |
| Last Reviewed | 2026-10-26 |
| Security Reviewer | Trust & Identity Board (TIB) |

## 1. System Context

- Networks: `services` (callers, the digit services, `carry`, Redpanda)
  and `data` (its own CouchDB only). No port is published on the host (CLAUDE.md 6.2) and the gateway
  has no route to the service.
- Data store: CouchDB (`successor-db`), reachable only on `data` with the
  service's credentials.
- Trust boundaries: `POST /v1/next` (port 8080) and gRPC `Next` (port
  9090, plain HTTP/2 without TLS) from any container on `services` (no
  authentication between services yet); outbound `GET /next` to the digit
  services and gRPC `Propagate` to `carry`, whose answers decide the
  result; messages produced to `aaas.successor.called.v1`; CouchDB on
  `data`.

## 2. STRIDE Analysis

| Category | Threat | Mitigation | Residual Risk |
| --- | --- | --- | --- |
| Spoofing | A container on `services` calls `POST /v1/next` or `Next` for a task it does not own and pollutes the call log | Network segmentation; strict validation of `taskId` (lowercase UUIDv7) and `n` on both interfaces; a forged call cannot change the result of another call (the natural key returns the stored document) | Medium until service authentication; Low impact |
| Spoofing | A container on `services` answers as a digit service or as `carry` (DNS of the Compose network) | Network segmentation; replies are checked against the contracts (the digit named in the reply, a successor in 0..9, one to seven carry digits in 0..9) before use; the consensus vote (P4.5) recomputes every sum | Medium until service authentication; a wrong sum is caught by consensus |
| Tampering | The call log is altered to change a stored result | CouchDB only on `data` with credentials; every call, retries included, is computed again by the digit services and `carry`, and a stored result that differs is refused with 503 instead of being replayed; the consensus vote (P4.5) checks the sum | Low |
| Tampering | A large or crafted body exhausts the parser | HTTP bodies above 4 KiB are refused (413); JSON parsed with aeson; gRPC messages decoded by the generated proto-lens code (fixed fields, unknown fields kept aside and ignored); integers checked before any side effect | Low |
| Repudiation | A call cannot be traced to a task | Every call is a document with `taskId`, `traceId` and `calledAt`, and an event with the trace continued | Low |
| Information Disclosure | CouchDB credentials leak | Password only in the environment (OpenBao from P5.3), never logged; problems and gRPC statuses carry no internal details (an exception escaping a gRPC handler is answered as `internal error`, its text only logged) | Low |
| Denial of Service | A flood of calls exhausts CouchDB or the disk | `mem_limit` and `cpus`; rate limits at the gateway (P6.2) protect the user side; storage growth tracked as R-014 | Medium |
| Denial of Service | Many gRPC streams or HTTP/2 control frames exhaust the process | grapesy's HTTP/2 limits: at most 128 concurrent streams per connection, a 256 KiB stream and 2 MiB connection window, at most 100 pings per second, and the frame rate limits of the http2 library; `mem_limit` and `cpus` | Medium |
| Denial of Service | A slow or failed digit service or `carry` holds calls | Every outbound call is bounded (250 ms per digit attempt, 2 s for a carry call); the call fails with 503 / `UNAVAILABLE` and the caller retries | Low |
| Elevation of Privilege | A compromised process gains host access | Non-root user (UID 10001), Debian slim runtime with four packages | Low |
