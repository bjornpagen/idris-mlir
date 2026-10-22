<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] The fork builds a run-time case tree the frontend never reads

At the pin, Idris builds for every definition a second, run-time case
tree for its back ends (`mkRunTime`, `compileRunTime`, `Core.Transform`
in elaboration, `TTImp.PartialEval`, the case builder's `RunTime` phase
and its `-Xcase-tree-opt` heuristics), and the TTC drops it; the
frontend translates the compile-time tree (proposals/0000 C55;
AGENTS.md: checked TT, never run-time case trees).

## The fix

The fork (compiler/idris) carries it as its own code, landed in a386fe4d
(lane L17, 2026-10-21, unbuilt): none is built: a `PMDef` holds the
compile-time tree and, per clause, the patterns the case builder read
(`clausePats`), and references are what that tree refers to
(`refersTo`). `TTImp.PartialEval`, `Core.Transform`'s use, the scored-column
 heuristics and the renaming of one tree into the other's scope
go; `%transform` and `%spec` are read as hints this compiler need not
apply. The hunk of `processDef` that stores `clausePats` in place of the
placeholder tree is in fork-erase-args' diff, which shares it.

`pull-request.diff` is that commit's change for this entry, its paths
those of the Idris tree (`src/...`), against the fork as it stood before
the commit (the pin with the earlier fork entries), which is what a re-sync
 of the fork reads. Hunks the commit shares between entries sit in
one of them, as each entry's text says.

## Why there is no patch

The fork is ours: a fix to its upstream code is fork code, recorded in
PINS.md, never a patch the bootstrap applies. The stock Idris, which
builds only stage 0 and the benchmarks' Chez baseline, is not patched.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). The entry goes when a
re-sync of the fork brings upstream's own fix, or never, where the
change is this compiler's subset.
