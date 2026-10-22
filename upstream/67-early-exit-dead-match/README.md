<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] An op whose regions only exit is found trivially dead

With llvm/llvm-project#166688 carried (`upstream/65-early-exits`),
`isOpTriviallyDead` is `use_empty() && wouldOpBeTriviallyDead`, and for an
op with `RecursiveMemoryEffects` the second walks the nested ops and
finds the op dead when none of them has an effect but a read or an
allocation (`mlir/lib/Interfaces/SideEffectInterfaces.cpp`,
`wouldOpBeTriviallyDeadImpl`, *read* at 416f328b). The pull request does
not touch it. An early exit transfers control out of the op, but an op
that only transfers control declares no memory effect, so a resultless op
whose regions all exit to an enclosing target is found dead: the greedy
driver, dead-code elimination or the e-graph's cleanup erases it, and the
code after it runs in place of the exit, a miscompile.

`scf.break` and `scf.continue` escape it only because they implement no
`MemoryEffectOpInterface`, which reads as an unknown effect. Our
`idr.jump` declares its effects, which are none, as an op that only moves
control should: an `idr.join` holding an `idr.data.match` of no result
whose every case ends in an `idr.jump` to the join's target, followed by
`ub.unreachable`, has its match erased and its body becomes
`ub.unreachable` (*read*, L09 §1.3.4 U1).

## Reproduce

No upstream exit declares its effects, so upstream's dialects do not
reach the bug; its reproducer is a test op that declares no effect, or
our `idr.jump`, which `tests/upstream-early-exit-dead-match` uses.

## Patch

`llvm.patch`, applying after 66: in the walk, an op implementing
`RegionExitTerminatorOpInterface` with a potential target outside the
root keeps the root (O(1) per visited op); `MLIRSideEffectInterfaces`
gains `MLIRRegionKindInterfaceIncGen` among its dependencies, since it
now includes `RegionKindInterface.h`. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not posted.

- Where: a review comment on llvm/llvm-project#166688 carrying this diff
  and a test op of the test dialect that exits with no declared effect.
- Upstream test: a resultless `test.propagate_control_flow_break` whose
  region ends in such an exit survives `-canonicalize`.
- The patch goes when the pin carries the pull request with this case
  covered; if upstream merges another form, D82 decides (65's README).
