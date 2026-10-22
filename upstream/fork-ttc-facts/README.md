<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] The TTC drops facts its readers rebuild

At the pin, the TTC drops a `let`'s, a `PLet`'s and a `PVTy`'s binder
type, why a term is erased, a case tree's scrutinee type and each leaf's
clause index, and a block's typed parent; the frontend guessed them
back, and one guess refused valid programs (17 FB-01; proposals/0000
D44's F1, C129).

## The fix

The fork (compiler/idris) carries it as its own code, landed in a386fe4d
(lane L17, 2026-10-21, unbuilt): the TTC keeps them: the binder types,
`WhyErased` (a placeholder, impossible, or the term a dotted position
equals), the scrutinee type and clause index, per definition each
clause's patterns as the case builder read them, and a block's typed
parent; `ttcVersion` moves.

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
