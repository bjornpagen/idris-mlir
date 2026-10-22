<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] The automatic search's acceptance is decided by a depth

At the pin, the automatic search (`Core.AutoSearch`) stops at
`%auto_implicit_depth` (default 50), and a goal it cannot solve within
that depth fails the program: acceptance is a count (proposals/0000 D53,
C66, C127).

## The fix

The fork (compiler/idris) carries it as its own code, landed in a386fe4d
(lane L17, 2026-10-21, unbuilt): before the search takes up a goal that
is a type constructor's application, it compares the goal with each
earlier goal of its path of the same type constructor by homeomorphic
embedding (unknowns, the search's locals and universes one symbol each,
an integer by its magnitude, a string as a subsequence, any other
constant by equality). A goal convertible with an earlier one fails that
step, as upstream's cycle check did; one that embeds an earlier goal
through unknowns waits for a later round, and at the last chance, as one
that embeds it with everything known, refuses the program, never caught
as a failed branch. Since e5b39cb2 (lane L17's second half) a growth is a
case of the search's result (`Searched`: `Found` or `Grows`, typed by
`Growth`) and its refusal `GrowingSearch` (PINS.md search-growth); this
diff is a386fe4d's, the first form, which a re-sync reads with that
commit.
Kruskal's tree theorem makes every endless path meet such a pair.
`%auto_implicit_depth` and every depth of the search go (`ISearch`,
`PSearch`, `BySearch` lose theirs), and the parser refuses the pragma.
The quote that follows stuck applications only so deep returns the term
or `TooDeep`, its callers choosing by matching; the depths that remain
(`%nf_metavar_threshold` among them) decide only a stored term's form,
never acceptance.

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
