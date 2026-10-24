<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# foreign/

Code laid out as its upstream lays it out. Today that is one tree:

- `idr/` — the `idr` MLIR dialect, its passes and the `idris-mlir`
  driver, in upstream MLIR's in-tree layout and conventions
  (include/, lib/, tools/), so that upstream mechanisms and reviews
  move between here and MLIR without translation.
