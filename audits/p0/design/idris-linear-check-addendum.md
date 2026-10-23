<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Addendum to idris-linear-check.md: reproduced, and the cause found

Written 2026-10-23 at 410113a7 (L06h). Grounds as in the note. Every
time is user seconds of `idris2 --check`, from `wait4`'s rusage of its
Chez process, on this repository's 8-core arm64 macOS machine at load
average 20 to 60; the builds are scratch bootstraps of 89ba32eb (the
gitlink) on the toolchain's Chez: unpatched, with 96 and 104 to 108, with
96 and 104 to 109, with the whole series (96 and 104 to 114, which the
toolchain's installed Idris carries, its stamp's hashes those of the
tree), and with the series and 115. The note's inputs are its own
(`/tmp/idris-linear-check/proto/cutN`).

## 1. The bisected definition is 109's

- *measured*: `cut853`, which ends at `recanonRow`, is killed at 1200 s
  wall unpatched (241 s user) and with 96 and 104 to 108 (671 s, 555
  MiB). With 109 it reports, in 5.2 s, a type error: `recanonRow` binds
  `b`, the machine's buffer type, as a value (`(uf :& b) <- findU ...`)
  and then uses it as a type (`the (RS b g n r h) ...`). That is the slow
  failure `upstream/109-delayed-retry-doubling` fixes.
- *measured*: with that `b` renamed, `cut853`, `cut872` and the whole
  module check in 8 to 12 s on every build, the unpatched one included.

## 2. What is left is upstream/115, and it is not linearity

- *measured*: correct code over the same machine, continuations over a
  linear state nested `d` deep, takes 1.9, 6.3 and 40.8 s at `d` = 6, 7,
  8 with the series, 1.3, 1.7 and 2.1 s with 115. The time is in building
  the size-change graph, which grows twofold with each case block around
  a call; the cause and the patch are in
  `upstream/115-size-change-as-pattern-doubling/README.md`.
- *measured*, at `d` = 7 with the series: the time stays (5.5 to 6.7 s
  against 5.6) with `Builtin.DPair.(#)` hidden, with `Vals`'s
  constructors renamed and written out, with the lambdas binding
  variables instead of patterns, and with the machine unrestricted. A do
  block of pattern binds in plain `IO` has the same growth
  (`Binds.idr`). So §5's three hazards are not causes: no library needs
  to avoid `Nil`, `(::)` or `(#)`, list-literal patterns, or nested
  `LPair`s for this.
- *conjecture*: the first prototype's `nodeNS` (186 s, machine-prototype
  §3), which is not kept, was this shape.
- *measured*: our libraries meet neither bug on the series: each module
  of `libs/mlir-linear` and `libs/mlir-array` spends under a millisecond
  building its size-change graphs (`--timing 3`). The frontend and the
  checker were not measured.

## 3. Still open from §3

The as-pattern slip in `updateHoleUsage` (`Core/LinearCheck.idr:132-135`,
`a` visited twice and `p` never) is still at the pin; it costs no time
and nothing here acts on it.
