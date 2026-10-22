<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] Counts, state and options nothing needs

At the pin, the elaborator carries state and options no reader needs:
the search timer, never started and checked at every unfolding, with
`%search_timeout`; `%foreign_impl`, stored and read by nothing;
`--debug-elab-check`, a second conversion check behind a flag;
`delayDepth`, counted and read by nothing; `processTTImpFile` with the
raw TTImp parser, which nothing calls (proposals/0000 C128).

## The fix

The fork (compiler/idris) carries it as its own code, landed in a386fe4d
(lane L17, 2026-10-21, unbuilt): they go; the parser no longer knows a
removed pragma, so a module that writes one is refused where it writes
it. The clauses of one definition are collected in the desugarer
(`collectDefs`), which the raw parser held.

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
