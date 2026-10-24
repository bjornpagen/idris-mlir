<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] A region branch op cannot be asked whether one of its regions may run after another

On llvm main at 416f328b (the pin), with the carried patches applied, and
on main on 2026-10-24 (*read*), `isRegionReachable`
(`mlir/lib/Interfaces/ControlFlowInterfaces.cpp`), the walk of a region
branch op's region graph from one region until it meets another, is
`static` to that file. It answers `isRepetitiveRegion` (a region reached
from itself) and `insideMutuallyExclusiveRegions` (two regions neither
reached from the other), and nothing exported answers the order of two
regions: `insideMutuallyExclusiveRegions` is symmetric, false for the two
regions of an op that runs them one after the other whichever is asked
first. No pull request or issue exports it (searched 2026-10-24): the
open llvm/llvm-project#234162 (NFC) folds `traverseRegionGraph` into
`isRegionReachable` and keeps it `static`.

The ownership facts (`ownership::runsAfter`,
foreign/idr/include/idr/Analysis/Ownership/Facts.h) need that order: a
use in a join region of an `idr.join` may run after a call in the body
that jumps to it, a use in the body never runs after a call in one of its
join regions, and a use in one match case never after a call in another.
The in-place rule (`ownership::entryOf`) and the borrow inference
(`usedAfter`) read it. With the walk private, `Facts.h` kept a second
walk of the same graph (`entersAfter`, backwards over `getPredecessors`).

## Reproduce

`reachable.cpp`: an op of its own with two regions run one after the
other asks `isRegionReachable` both ways and of each region with itself.
At the pin it does not compile (no such member); with the patch it
prints `ok` (*conjecture*: not built or run, no toolchain is built with
the carried patches).

## Patch

`llvm.patch`, applying after 70, whose edges the walk keeps
(`upstream/70-early-exit-region-graph`: a nested exit that lands on the
op is an edge of its graph), and to the pin alone: the static function
becomes `RegionBranchOpInterface::isRegionReachable(unsigned from,
unsigned to)`, declared in the interface's `extraClassDeclaration` beside
`isRepetitiveRegion` and taking region numbers as that one does, so two
regions of different ops cannot be asked and the assertion that they
belong to one op goes. `isRepetitiveRegion(index)` is
`isRegionReachable(index, index)`, and `insideMutuallyExclusiveRegions`
asks it both ways, as before; no answer changes. A unit test in
`mlir/unittests/Interfaces/ControlFlowInterfacesTest.cpp` asks it of the
test's sequential op both ways and of its double loop op. Checked with
`git apply` after the 48 carried llvm patches, on the pin's files outside
`.toolchain`; the patched `ControlFlowInterfaces.cpp`, the unit test and
`reachable.cpp` compile (`-fsyntax-only`) against the pin's headers with
the carried patches' headers and the interface's declarations generated
from the patched `.td`. Not built.

The next LLVM bump re-places it, with 70: upstream main changed
`traverseRegionGraph` on 2026-10-23 (llvm/llvm-project#233784, relanded
as #234591), whose stop condition now takes the region alone, and moved
the region-graph unit tests into a `RegionGraphTest` fixture
(`createRegionGraphOp(entries, successors)`), where the unit test goes as
one more case; and onto #234162's single search if that lands first.
The patch does not apply to main as it stands (*read*, main's files on
2026-10-24).

## Check

`tests/upstream-region-branch-reachability`: `mlir_check` of
`reachable.cpp`, which prints `ok`.

## Upstreaming plan

Status: carried (2026-10-24); not posted.

- Where: one pull request to llvm/llvm-project, `[mlir][Interfaces]`, on
  its own, against main after #234591 (it does not need #166688).
- Upstream test: the unit test above, as a `RegionGraphTest` case on
  main: a two-region op whose region 0 branches to region 1 answers
  `isRegionReachable(0, 1)` true and `isRegionReachable(1, 0)` false.
- The patch goes when the pin exports the directional query; if upstream
  takes another form (a free function over two `Region *`), ours moves to
  it.
