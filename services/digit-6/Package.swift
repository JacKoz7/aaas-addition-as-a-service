// swift-tools-version:6.0

// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-6
// Module:          Package.swift
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Swift package manifest of the digit-6 service: targets
//                  and compiler settings; the package has no dependencies.
// Related Docs:    services/digit-6/docs/SERVICE_CHARTER.md

import PackageDescription

/// Compiler settings of every target: warnings are errors (the lint stage
/// and every build fail on a warning).
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
let strict: [SwiftSetting] = [.unsafeFlags(["-warnings-as-errors"])]

/// The digit-6 package: the CSQLite system library, the DigitService
/// library, the digit6 executable and the unit tests. Sources live in src/
/// and tests/ like every AaaS service, instead of Sources/ and Tests/. The
/// package has no dependencies: the build fetches nothing (ADR-0028).
///
/// Owner: Arithmetic Excellence Center (AEC). Since: digit-6 0.1.0.
let package = Package(
  name: "digit-6",
  targets: [
    .systemLibrary(name: "CSQLite", path: "src/CSQLite"),
    .target(
      name: "DigitService",
      dependencies: ["CSQLite"],
      path: "src/DigitService",
      swiftSettings: strict
    ),
    .executableTarget(
      name: "digit6",
      dependencies: ["DigitService"],
      path: "src/digit6",
      swiftSettings: strict
    ),
    .testTarget(
      name: "DigitServiceTests",
      dependencies: ["DigitService"],
      path: "tests/DigitServiceTests",
      swiftSettings: strict
    ),
  ]
)
