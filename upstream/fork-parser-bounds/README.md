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

`pull-request.diff` is that commit's change for this entry, laid out
against third_party/Idris2 at its gitlink (89ba32eb): each hunk is the
change written against upstream's file, without the fork's other
deviations, so that it applies to the pin alone and states exactly what
a re-sync of the fork carries. It was made by merging the change three
ways onto upstream's files and writing each conflict against upstream's
text; a part of the change in a file of the fork's own, with no upstream
counterpart, is left out and said below. Hunks the commit shares between
entries sit in one of them, as each entry's text says.

The fork's parser is upstream's, a grammar data type that `doParse`
runs, so the change is written as the fork has it: on `doParse` and
`ParseResult` (`Located` tokens, `Irrelevant` and `Relevant` results),
with `terminalAt` as `Position` then `Terminal`, a token read with its
bounds.

## Why there is no patch

The fork is ours: a fix to its upstream code is fork code, recorded in
PINS.md, never a patch the bootstrap applies. The stock Idris, which
builds only stage 0 and the benchmarks' Chez baseline, is not patched.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). The entry goes when a
re-sync of the fork brings upstream's own fix, or never, where the
change is this compiler's subset.
