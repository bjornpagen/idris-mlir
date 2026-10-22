<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] A case or with block names its parent as printed text

At the pin, a case or with block's name holds its parent's printed text
and the session's machine-name counter (`Name.idr`,
`Core/UnifyState.idr`), a fact kept as a string and a session-wide `Int`
(17 FB-10; proposals/0000 C129).

## The fix

The fork (compiler/idris) carries it as its own code, landed in a386fe4d
(lane L17, 2026-10-21, unbuilt): a block's name holds its parent's full
name and its ordinal among the parent's blocks (`CaseBlock`,
`WithBlock`, counted per definition in `blockOrdinals`); messages print
the parent as upstream's did, and reflection gives base's form.

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
