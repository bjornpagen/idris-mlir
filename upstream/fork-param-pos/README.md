<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] A type's parameters are missed when a constructor's binders come through a definition

At the pin, a type's parameter positions are read off its constructors'
types as written, so a constructor whose binders come through a
definition (`a -@ LList a -@ LList a`) has none (17 FB-18; the review's
U8).

## The fix

The fork (compiler/idris) carries it as its own code, landed in a386fe4d
(lane L17, 2026-10-21, unbuilt): parameters are read off the
constructors' types in normal form (`Core/Context/Data.idr`).

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
