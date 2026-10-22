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

`pull-request.diff` is that commit's change for this entry, laid out
against third_party/Idris2 at its gitlink (89ba32eb): each hunk is the
change written against upstream's file, without the fork's other
deviations, so that it applies to the pin alone and states exactly what
a re-sync of the fork carries. It was made by merging the change three
ways onto upstream's files and writing each conflict against upstream's
text; a part of the change in a file of the fork's own, with no upstream
counterpart, is left out and said below. Hunks the commit shares between
entries sit in one of them, as each entry's text says.

Upstream writes terms and case trees in its `TTC` instances, where the
fork has its own encoders and decoders (upstream/fork-total-frontend-paths):
the facts are written there, `Let`, `PLet` and `PVTy` with their binder
type, `Erased` with why, a `Case` with its scrutinee type and an `STerm`
with its clause index. The fork's total decoders of patterns, which this
commit added and which write upstream's bytes, are the fork's own and
are left out, as are `saveMetas`' change and a block's parent, which
upstream's `fromBuf` reads as written once `Core.Name` makes it a name
(fork-block-parent).

Since e5b39cb2 (lane L17's second half), the TTC also keeps whether a
`Delay` was written or inserted by the elaborator (PINS.md ttc-delays),
and a module's imports and pragma uses with their locations (PINS.md
ttc-imports-pragmas); that commit is their record.

## Why there is no patch

The fork is ours: a fix to its upstream code is fork code, recorded in
PINS.md, never a patch the bootstrap applies. The stock Idris, which
builds only stage 0 and the benchmarks' Chez baseline, is not patched.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). The entry goes when a
re-sync of the fork brings upstream's own fix, or never, where the
change is this compiler's subset.
