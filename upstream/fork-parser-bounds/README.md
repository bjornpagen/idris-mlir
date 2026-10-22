<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] A parser's result keeps junk bounds beside a flag

At the pin, `WithBounds` keeps `isIrrelevant : Bool` beside bounds that
are junk when it is set, so mapping a result or sequencing it after
`pure` changes its bounds and the functor and monad identities fail
(proposals/0000 D101; payoffs.md §1.5, measured).

## The fix

The fork (compiler/idris) carries it as its own code, landed in a386fe4d
(lane L17, 2026-10-21, unbuilt): a parser's result is a sum,
`Irrelevant` (parsed from no input) or `Relevant` with its bounds, and a
lexer's token is `Located`, always with its bounds; the lexers, the
literate reader, the parser core and their users follow.

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
