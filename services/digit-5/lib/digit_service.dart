// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-5
// Module:          lib/digit_service.dart
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Public library of the digit-5 service: exports the
//                  contract, storage, metrics, logging, trace context and
//                  HTTP server used by bin/digit5.dart and the tests.
// Related Docs:    services/digit-5/README.md, ADR-0022, ADR-0027

/// The digit-5 service: authoritative source for the value and successor
/// of digit 5 (contracts/http/digit.yaml).
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-5 0.1.0.
library;

export 'src/api.dart';
export 'src/log.dart';
export 'src/metrics.dart';
export 'src/server.dart';
export 'src/store.dart';
export 'src/trace.dart';
