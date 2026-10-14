<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# foreign/

Code laid out as its upstream lays it out. Today that is one tree:

- `idr/` — the `idr` MLIR dialect, its passes and the `idris-mlir`
  driver, in upstream MLIR's in-tree layout and conventions
  (include/, lib/, tools/), so that upstream mechanisms, reviews
  and ports move between here and MLIR without translation.

A port from Mojo or MLIR lands where the code belongs in that
layout, keeps its upstream copyright and license header, gains an
SPDX line and a changes note, and is recorded in PINS.md with its
source and revision. A whole vendored unit that does not adapt
into the layout gets its own directory beside `idr/`, named for
its origin, with its upstream layout preserved inside it.
