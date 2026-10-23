<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] The size-change closure builds every call path, exponential in a mutual block

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), the stock
Idris's totality check of a mutual block takes time and memory
exponential in the block's size, though every function terminates. The
checker's decoder (`compiler/checker/src/Idris/Syntax/Tree.idr`, a
`mutual` block of `child*`/`decode*` functions recursing on an
accessibility proof) passed 8 GiB within about 115 s in its totality check
(INT-9, 2026-10-22). `Paths.idr`, a hub and twenty-two spokes recursing on
a shrinking `Nat`, has the same growth.

*measured*, scratch build of 89ba32eb on Chez 10.4.1, an 8-core Apple M2
Max virtual machine at load average 20 to 50:

- `Paths.idr`'s shape with K spokes: 0.59 s at K = 12, 1.23 s at 14,
  5.94 s and 470 MB at 16, about 2.2 times per two spokes added.
- the decoder's shape (K form pairs, stub types): 0.024 s at K = 8, 0.57 s
  at 12, 24.9 s and 1.68 GB at 16, over 300 s at 32. Recursion on a plain
  `Nat` instead of the accessibility proof, or without the `case`, is as
  slow (24.2 s at 16).
- on an instrumented build, the closure's graphs for K = 8, 10, 12, 14
  number 587, 803, 1051, 1331, while its longest stored call path has
  5888, 27648, 126976 and 573440 calls.

## Cause

*read* at 89ba32eb, `src/Core/Termination/SizeChange.idr`. A graph of the
closure carries `seq`, the call path it stands for, which only an error
message reads (`Ord` and `Eq` compare the change alone). `composeGraph`
builds the composed graph's path as `a1.seq ++ a2.seq`, eagerly, so a
path's length is the sum of its parts' and can double with every
composition the closure makes, whether the composed graph is kept or
dropped as known, and whether a loop is ever reported.

## Patch

`idris.patch`, against 89ba32eb: `seq` is `Lazy CallSeq`; `composeGraph`
delays the append, and the path is forced only where it is read, in
`show` and in the `RecPath` of a reported loop. Verified on a full
bootstrap of 89ba32eb with this patch alone, which built itself and all its
libraries: the decoder's shape checks in 0.057 s at 226 MB at K = 16,
0.38 s at 32 and 3.1 s at 64, its memory flat; terminating and
non-terminating mutual blocks get the same verdicts and byte-identical
messages, the recursive path's text included; and the checker's
`Tree.idr` completes its totality check at 353 MB, elaborating in 2.1 s.
See `## Testing` for `Paths.idr` on the build carrying every Idris patch.

## Testing

On a full bootstrap of 89ba32eb carrying 104 to 107, in order (scratch,
Chez 10.4.1, 2026-10-22), which built itself and all its libraries with
them; times are wall seconds on an 8-core Apple M2 Max virtual machine at
load average 5 to 15, the unpatched build's runs stopped at 120 s.

- `Paths.idr` (twenty-two spokes) checks total in 1 s (unpatched: past
  120 s; 5.94 s and 470 MB at sixteen).

Upstream's own tests in the groups basic, casetree, coverage, error,
evaluator, failing, interface, linear, perf, reg, termination, total and
with, run as upstream's runner runs them: 391 of 392 pass, as all 392 do on the unpatched build. The one
difference is `casetree/heuristics001`, which prints a compile-time tree:
105 leaves out an alternative `S` under a default that `S` has already
missed (dead: the variable is neither `Z` nor `S` there), and the
generated names after it shift.

## When it goes

When the Idris pin carries upstream's own fix (the check then passes
without the patch). Until then our code writes its mutual blocks as Idris
allows them, and the bootstrap applies the patch.

Our type checker (compiler/checker) never had the cost: its size-change
search joins two walks' paths as one node (`CallPath`'s `Then`) and lists
the calls of a reported loop alone.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). No matching upstream
issue was found (2026-10-22). Whether Bjorn reports the bug, in their own
words, is their call. The patch goes when the pin moves past upstream's fix,
which `tests/upstream-size-change-call-paths` shows by passing on an
unpatched pin.
