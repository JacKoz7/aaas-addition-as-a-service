// SPDX-License-Identifier: MIT
// Copyright (c) 2026 AaaS Contributors
//
// Component:       digit-8
// Module:          src/digit8/app.d
// Owning Team:     Arithmetic Excellence Center (AEC)
// Classification:  INTERNAL
// Purpose:         Entry point of the digit-8 executable.
// Related Docs:    services/digit-8/README.md, ADR-0030

/**
 * Entry point of the digit-8 executable.
 *
 * The process itself is `digit8.service.run`; this module only holds
 * `main`, because `dub test` leaves the main source file out of the
 * unit-test build.
 *
 * Owner: Arithmetic Excellence Center (AEC)
 * Since: digit-8 0.1.0
 */
module digit8.app;

import digit8.service : run;

/**
 * The process entry point.
 *
 * Returns: the exit status of `digit8.service.run`: 0 after a graceful
 * stop, 1 when a start-up check fails.
 *
 * Errors: none. Side Effects: those of `run`. Complexity: runs until
 * stopped. Thread Safety: the main thread. Owner: AEC.
 * Since: digit-8 0.1.0.
 */
int main()
{
    return run();
}
