<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] Overloaded names are resolved under a depth that only refuses programs

At the pin, nested resolution of overloaded names stops at
`%ambiguity_depth` (default 3): `printLn (1, 2, 3, 4, 5, 6)` is refused,
and a candidate can win because another ran out (proposals/0000 D55).

## The fix

The fork (compiler/idris) carries it as its own code, landed in a386fe4d
(lane L17, 2026-10-21, unbuilt): the count and everything that serves it
go (`%ambiguity_depth`, `AmbigDepth`, the elaborator's `ambigTries`):
every candidate elaborates smaller parts of the source, so resolution
ends without one; the parser refuses the pragma. The tuple's two
meanings are left to their own design (D55).

`pull-request.diff` is that commit's change for this entry, its paths
those of the Idris tree (`src/...`), against the fork as it stood before
the commit (the pin with the earlier fork entries), which is what a re-sync
 of the fork reads. Hunks the commit shares between entries sit in
one of them, as each entry's text says.

Since e5b39cb2 (lane L17's second half), the syntax that writes a type
and its value alike (`(l, r)`, `()`, `(x ** p)`) is one node read by its
expected type's sort, not an alternative of two readings nested at each
level of a tuple (PINS.md tuple-node); that commit is its record.

## Why there is no patch

The fork is ours: a fix to its upstream code is fork code, recorded in
PINS.md, never a patch the bootstrap applies. The stock Idris, which
builds only stage 0 and the benchmarks' Chez baseline, is not patched.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). The entry goes when a
re-sync of the fork brings upstream's own fix, or never, where the
change is this compiler's subset.
