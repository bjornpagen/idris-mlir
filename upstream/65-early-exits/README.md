<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [MLIR] Early exits: a terminator that leaves several regions at once

On llvm main at 416f328b (the pin, 2026-10-21) a region terminator can
only hand control to its immediate parent op. A jump out of a match case
to a join point two levels up, a loop's `break` inside an `if`, has no
form: a dialect writes it as a flag every enclosing op tests and yields
outward, or as blocks, which lose the scopes counting reads.

llvm/llvm-project#166688, "[MLIR] Introduce support for early exits"
(Mehdi Amini; open; head 968e49b1, last pushed 2026-07-22; 3,963 lines
added over 44 files), gives the form: a terminator whose target is a
builtin `token` that an ancestor op defines
(`RegionExitTerminatorOpInterface`), ops it may cross
(`PropagateControlFlowBreak`, a trait), and ops it may land on
(`HasBreakingControlFlowOpInterface`, `HasNestedTerminators`), with
`scf.loop`, `scf.break` and `scf.continue` as its first users and
`scf.if` carrying exits. Upstream's dead-code analysis, SCCP and the
sparse and dense analyses read a nested exit as an edge, post-dominance
follows it, and the inliner refuses a region an exit escapes.

The compiler's join points are this form: `idr.join` and `idr.loop`
define a builtin `token` per target, `idr.jump` exits to it across
`idr.match` and `idr.match_lit`, and upstream's analyses read the edge;
no control-flow reading of ours stands beside them (proposals/0000 D25,
D76, D82, C93).

## Reproduce

`early-exit.mlir` holds two of the pull request's own inputs, on upstream
dialects. At the pin neither parses: `scf.loop` does not exist. With the
patch, SCCP folds `@early_exit_dead_code`'s comparison to `false` (the
value -5 leaves both loops at once and never reaches it), and
`-convert-scf-to-cf` lowers `@loop_with_iter_args` to a back edge carrying
`%arg` and an exit block taking the break's value.

## Patch

`llvm.patch` is the pull request at 968e49b1 with its tests, rebased by
hand onto the pin: applied to 416f328b after every patch before it, five
of its hunks fail `git apply` (which takes no fuzz, as the bootstrap's
step does) because the pin's text moved under them, each placed by hand
with the pull request's meaning (*measured*: `git apply --check` and
`--reject` on a copy of the pin with the patches before it applied):

- `SCFToControlFlow.cpp`: the pin added `copyLLVMDialectAttrs` between
  `} // namespace` and `propagateLoopAttrs`; `LoopOpLowering`'s
  declaration goes inside the anonymous namespace and `lowerIfOpToCFG`
  after it. The pin's `IfLowering` is the pull request's base text, so
  its hunk applies as written.
- `SCF.cpp`, `WhileMoveIfDown`: the pin rewrote the loop to assign into
  each condition operand and still calls `thenYield()`/`elseYield()`,
  which the pull request deletes; the pin's calls become
  `thenTerminator()`/`elseTerminator()`. No other caller of the deleted
  accessors is left in `mlir/` (*measured*, grep).
- `ControlFlowInterfaces.cpp`, `MakeRegionBranchOpSuccessorInputsDead`:
  the `isSuccessorInputOwnedBy` skip goes after the pin's `isIsolated`.
- `Transforms/Utils/CMakeLists.txt`: the pin already has a `DEPENDS`
  list; `MLIRRegionKindInterfaceIncGen` joins it.
- `mlir-opt.cpp`: the declaration of
  `registerRegionBranchOpInterfaceTestPasses` goes in name order, the pin
  having dropped `registerPrintTosaAvailabilityPass`.

The other hunks apply with offsets. Of the files the pull request
touches, upstream changed at most these since 7208ba24 (*read*, the
commits by path): `SCF.cpp` (#222144, #230717), `OpDefinition.h`
(#233051, which changes how trait verifiers are instantiated, not the
traits the pull request adds), the test dialect's ops (#232733 and its
revert, #233681) and `TestOpDefs.cpp` (#233149, #233454), and SCF's
bufferization (#231187); none conflicts with its text. Not built.

The pull request's own gaps that our ops reach are fixed beside it, each
its own patch applying after this one: 66 (the propagation helpers
exported), 67 (an op whose nested ops only exit is not dead), 68 (the
region inliner), 69 (the successor-input patterns), 70 (the region-graph
traversal), 71 (`scf.index_switch` carries exits).

## Upstreaming plan

Status: carried (2026-10-21); the pull request is open, every review
`COMMENTED`, none approving; the last round (Matthias Springer,
2026-06-12 to 06-15) asked about API shapes, so names may still move.

- Where: llvm/llvm-project#166688 itself; nothing of ours is sent but the
  review comments of 66 to 71.
- Upstream test: the pull request's (`early-exit*.mlir`,
  `sccp-early-exit.mlir`, `convert-early-exit-to-cfg.mlir`,
  `test-dead-code-analysis-early-exit.mlir`, `test-dominance.mlir`,
  `loop_canonicalize.mlir`, the breakable-loop tests).
- The patch goes when the pin passes the merge. If upstream merges
  another form, ours moves to it only when it keeps every fact this one
  keeps; otherwise this patch stays and the difference goes to the owner
  with its evidence (proposals/0000 D82). If upstream rejects the pull
  request, which encoding stands is a new ruling, on evidence. Each
  weekly fast-forward rebases it; its five hand placements are re-measured
  then.
