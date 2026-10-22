<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] A definition's erased positions are fixed before its type is known

At the pin, a definition's erased argument positions are computed where
its type is declared; a type that reaches its binders through a
definition declared before and defined after is stuck there, so they are
too few (proposals/0000 C122: the frontend reads the fork's own erasure,
once).

## The fix

The fork (compiler/idris) carries it as its own code, landed in a386fe4d
(lane L17, 2026-10-21, unbuilt): once a definition's clauses are checked
against its whole spine, its erased positions are found again
(`updateErasable`); `ZeroOneOmega` is public, so a reader matches on a
quantity.

`pull-request.diff` is that commit's change for this entry, laid out
against third_party/Idris2 at its gitlink (89ba32eb): each hunk is the
change written against upstream's file, without the fork's other
deviations, so that it applies to the pin alone and states exactly what
a re-sync of the fork carries. It was made by merging the change three
ways onto upstream's files and writing each conflict against upstream's
text; a part of the change in a file of the fork's own, with no upstream
counterpart, is left out and said below. Hunks the commit shares between
entries sit in one of them, as each entry's text says.

## Why there is no patch

The fork is ours: a fix to its upstream code is fork code, recorded in
PINS.md, never a patch the bootstrap applies. The stock Idris, which
builds only stage 0 and the benchmarks' Chez baseline, is not patched.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). The entry goes when a
re-sync of the fork brings upstream's own fix, or never, where the
change is this compiler's subset.
