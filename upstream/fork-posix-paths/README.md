<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] Every path is read with Windows's grammar on every platform

At the pin, `Libraries.Utils.Path` reads every path with Windows's
grammar and asks the host's operating system at run time where it
differs (`isWindows`): a backslash separates, a leading `x:` is a
volume, and names end at the first `:` or `?` (`"/tmp/a:b" </>
"Main.idr"` is `/tmp/a/Main.idr`; proposals/0000 C125, C8, P0 §8's per-target
 row).

## The fix

The fork (compiler/idris) carries it as its own code, landed in a386fe4d
(lane L17, 2026-10-21, unbuilt): a path is an optional root and the
names after it, split at `/` alone, on every target the compiler has
(all POSIX); `Volume`, `dirSeparator`, `pathSeparator`, `pathLookup` and
the run-time test of the host go.

`pull-request.diff` is that commit's change for this entry, laid out
against third_party/Idris2 at its gitlink (89ba32eb): each hunk is the
change written against upstream's file, without the fork's other
deviations, so that it applies to the pin alone and states exactly what
a re-sync of the fork carries. It was made by merging the change three
ways onto upstream's files and writing each conflict against upstream's
text; a part of the change in a file of the fork's own, with no upstream
counterpart, is left out and said below. Hunks the commit shares between
entries sit in one of them, as each entry's text says.

Upstream parses a path with combinators, where the fork had written a
lexer of its own under an earlier change: the change is written on
upstream's combinators, `/` the one separator and no volume.

The change's hunk in `mkdirAll` (`Core.Directory`) is to the fork's own
form of it (upstream/fork-total-frontend-paths), which builds a `Path`;
upstream's builds none, so the hunk has no counterpart and is left out.

## Why there is no patch

The fork is ours: a fix to its upstream code is fork code, recorded in
PINS.md, never a patch the bootstrap applies. The stock Idris, which
builds only stage 0 and the benchmarks' Chez baseline, is not patched.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). The entry goes when a
re-sync of the fork brings upstream's own fix, or never, where the
change is this compiler's subset.
