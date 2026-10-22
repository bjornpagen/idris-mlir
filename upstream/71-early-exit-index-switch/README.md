<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir][scf] scf.index_switch cannot carry an early exit

With llvm/llvm-project#166688 carried (`upstream/65-early-exits`), only
`scf.if` propagates exits. `scf.index_switch` is
`SingleBlockImplicitTerminator<"scf::YieldOp">`, its verifier requires
each region to end in `scf.yield`, its `getSuccessorRegions` answers
"the op" for every terminator, and its lowering casts each region's
terminator to `scf.yield` (*read* at 416f328b: `SCFOps.td`,
`IndexSwitchOp::verify`, `IndexSwitchOp::getSuccessorRegions`,
`IndexSwitchLowering`). `idr.match` lowers to `scf.index_switch`, so a
jump nested in a match has no upstream lowering, and a case that only
crashes cannot end in `ub.unreachable` without a yield of poison values
after it (L09 §1.3.4 U5). The same holds for `scf.if`, whose regions the
pull request opens to exits alone, not to a terminator that never
returns.

Its structural type conversion moves its regions whole and converts
`scf.yield` by its own pattern, so it needs no change, and its
canonicalizations are the generic region-branch ones that 68 and 69
guard (*read*; L09's U5 named the structural conversion too).

## Reproduce

`index-switch.mlir`, under `-convert-scf-to-cf` (*read*: not run).

## Patch

`llvm.patch`, applying after 70:

- `scf.index_switch` takes `PropagateControlFlowBreak` and accepts the
  terminators `scf.if` accepts (`IndexSwitchOpImplicitTerminatorType`,
  an alias of the pull request's `IfOpImplicitTerminatorType`); its
  verifier checks result types only for `scf.yield`.
- `getSuccessorRegions` reports a propagated exit with its target's
  successors, through 66's helpers.
- `IndexSwitchLowering` turns `scf.yield` into a branch and leaves an
  exit in place for its target's lowering, as `lowerIfOpToCFG` does.
- A region of `scf.if` or `scf.index_switch` may end in any terminator
  that never returns (`isNoReturnTerminator` in `SCF.h`: a terminator
  with no successor that is neither `ReturnLike` nor a region branch
  terminator), `ub.unreachable`, `llvm.unreachable` or a dialect's own
  crash among them, with no dialect of theirs changed; `scf.if`'s type
  inference reads `scf.yield` alone.
- A test in `convert-early-exit-to-cfg.mlir`.

Not built.

## Upstreaming plan

Status: carried (2026-10-21); not posted.

- Where: a review comment on llvm/llvm-project#166688 carrying this diff,
  in the pull request's own form for `scf.if`.
- Upstream test: `index_switch_break` in
  `convert-early-exit-to-cfg.mlir`, and a verifier test of a switch whose
  case ends in `ub.unreachable`.
- The patch goes when the pin carries the pull request with
  `scf.index_switch` covered; if upstream merges another form, D82
  decides (65's README).
