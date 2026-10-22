<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [mlir] Successor-input patterns edit the inputs of an exit's target

With llvm/llvm-project#166688 carried (`upstream/65-early-exits`), the
successor mapping of a region branch op includes the exits nested in it,
whose successor inputs belong to their target, an enclosing op. The pull
request guards `MakeRegionBranchOpSuccessorInputsDead` with
`isSuccessorInputOwnedBy`, and leaves unguarded the two other patterns
that build their maps from the same mapping
(`mlir/lib/Interfaces/ControlFlowInterfaces.cpp`, *read* at 416f328b):

- `RemoveDeadRegionBranchOpSuccessorInputs` erases a dead input of the
  target with the operands of the exits this op holds; the target's
  other exits keep theirs, which the verifier refuses.
- `RemoveDuplicateSuccessorInputUses` compares two inputs of the target
  by the operands of the exits this op holds, a part of their
  predecessors, and may merge two inputs that differ on the rest.

A dead join-point parameter, seen from a match that holds only some of
the jumps to it, meets the first (L09 §1.3.4 U3).

## Reproduce

`successor-inputs.mlir`, under `-canonicalize` (*conjecture* from the
reading: not run, since no tool of the pin parses `scf.loop`).

## Patch

`llvm.patch`, applying after 68: both patterns skip an input the op does
not own, as the pull request's guarded pattern does; the dead-input
pattern skips a tied set holding one. Not built.

## Upstreaming plan

Status: carried (2026-10-21); not posted.

- Where: a review comment on llvm/llvm-project#166688 with the diff and
  the reproducer as a test.
- Upstream test: `successor-inputs.mlir`'s function in
  `mlir/test/Dialect/SCF/loop_canonicalize.mlir`, checking the loop keeps
  both breaks' operands, or loses its dead result through the loop's own
  canonicalization, with every break rewritten.
- The patch goes when the pin carries the pull request with these cases
  covered; if upstream merges another form, D82 decides (65's README).
