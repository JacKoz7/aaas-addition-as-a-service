# SPDX-License-Identifier: MIT
# Copyright (c) 2026 AaaS Contributors
#
# Component:       digit-3
# Module:          tools/implementation-doc-check.awk
# Owning Team:     Arithmetic Excellence Center (AEC)
# Classification:  INTERNAL
# Purpose:         Documentation check of the implementation sections of
#                  the Pascal units, which PasDoc does not read: every
#                  constant and variable declared at unit level after
#                  `implementation` must follow a `{ ... }` comment.
# Related Docs:    services/digit-3/Dockerfile (stage doc-coverage),
#                  ADR-0025
#
# A unit-level block starts with `const` or `var` at column 0 outside a
# routine; declarations are the lines indented by exactly two spaces that
# start with an identifier. Local blocks (between a routine header and its
# `begin`) are skipped. Prints each undocumented declaration and exits 1
# when there is one.

# Reset the state at the start of every file.
FNR == 1 { impl = 0; block = 0; routine = 0; prev = "" }

# The implementation section starts.
/^implementation/ { impl = 1 }

# A routine header at column 0: its `var` and `const` blocks are local.
impl && /^(procedure|function|constructor|destructor) / { routine = 1; block = 0 }

# The body of a routine starts: later blocks are unit-level again.
impl && /^begin/ { routine = 0 }

# A unit-level block starts.
impl && !routine && /^(const|var)$/ { block = 1; prev = $0; next }

# Any other line at column 0 ends the block.
block && /^[^ ]/ { block = 0 }

# A declaration in a unit-level block must follow a comment.
block && /^  [A-Za-z_][A-Za-z0-9_]*[ :=]/ && prev !~ /}[[:space:]]*$/ {
  print FILENAME ":" FNR ": undocumented declaration: " $0
  bad = 1
}

# Remember the last non-blank line.
$0 !~ /^[[:space:]]*$/ { prev = $0 }

# Exit status: 1 when a declaration is undocumented.
END { exit bad }
