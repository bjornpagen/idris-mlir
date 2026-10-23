<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] Building a size-change graph takes time doubling with each case block around a call

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), the stock Idris,
with 96 and 104 to 114 (the toolchain's series) and without them, checks
a definition in time doubling with each case block around a call in it,
all of it spent building the definition's size-change graph, which it
does for every definition whatever its totality (`processDef`,
`src/TTImp/ProcessDef.idr:953-956`; the time `--timing` reports as
"Building size change graphs"). `Binds.idr`, a do block of thirty pattern
binds in `IO` and nothing else, takes 117.6 s of user time to check
(382.8 s wall at load average 55), and 0.97 s with the patch;
`Machine.idr`, a loop over a linear state whose continuations nest nine
deep, takes 308.1 s (791.8 s wall at load 47), and 2.85 s with the patch
(*measured*; the builds and the command are under **Testing**).

This is the slow elaboration of nested linear patterns the e-graph
prototype met on the stock host (`audits/p0/design/idris-linear-check.md`,
whose cause was not found there). The definition that note bisected to,
`recanonRow`, has a type error, and its slow failure is 109's: with 109 it
is reported in 5.2 s; with the error removed it checks in 8 to 12 s on
every build, the unpatched pin's included. What is left of the slowness
is this bug, in correct code: `Machine.idr` is the prototype's shape
(`Got`, `LPair`, `Vals` with list literals, `L.do`), and at seven levels
it takes 5.6 s of user time with the series, 5.5 to 6.7 s with any one of
`#`'s ambiguity, the list literals, the pattern-matching lambdas or the
linearity taken away (an unrestricted machine), so none of them is the
cost; the case blocks are.

## Cause

*read* at 89ba32eb, `src/Core/Termination/CallGraph.idr`, and *measured*
on a scratch build of the series to 109 instrumented around each
comparison (below).

- A call in a case block is taken into the size-change graph of the
  definition the case block is part of: `findSCcall` looks into the case
  block (375-378), and `getCasePats` rewrites the definition's argument
  patterns into the case block's scope, each argument the case block is
  passed replaced by the case block's pattern for it (`matchArgs`, 357-361;
  `lookupTm`, 336-349).
- A case block binds each variable of its environment as an as pattern
  (`addEnv`, `src/TTImp/Elab/Case.idr:290-296`), and the rewrite keeps the
  as pattern it finds and rewrites inside its as part (`lookupTm`, 339-342;
  `urhs`, 323, where the inner part is not one of the arguments). So an
  argument passed on through k case blocks has, in the k-th, a pattern of k
  as patterns nested in their as parts, the variable at the bottom: the
  innermost calls of `Machine.idr`'s nest meet patterns 26 deep at eight
  levels and 29 at nine (*measured*).
- `mkChange` compares each argument of each call with each such pattern
  (275-277). `sizeCompare` takes an as pattern, on either side, by
  `knownOr` of the comparison with its as part and the one with its
  pattern part (169-172), and `knownOr x y = case !x of Unknown => y; _ =>
  x` (148-149) returns `x`, the comparison, when its result is known, so
  the caller runs it a second time. An argument passed on unchanged is
  `Same` as the variable at the bottom of its own pattern, known at every
  level, so the comparison runs twice at each of the k levels: 2^k times.
  The instrumented build timed each comparison of `mkChange`: in the nest
  eight deep, one argument against its pattern 26 deep took 3.8 s, and the
  definition 42 s of user time.

## Patch

`idris.patch`, against 89ba32eb (no other patch of the series touches
the file), changes `knownOr` to return the known result instead of the
comparison that gave it. The comparison reads the context and computes a
`SizeChange`, the same on its second run, so every graph, and every
totality result, is as before; only the second run goes, and a
comparison with a pattern k as patterns deep costs k steps, not 2^k.

Our type checker (compiler/checker) does not need it: its comparison has
no `knownOr`, and computes each pair of positions once, the parts of an as
pattern included, memoized by the positions (`compareRoot`, `sizeCompare`
and `compareNew`, its `src/Core/Termination/CallGraph.idr`, 252-265 and
346-351) (*read*; not measured, since no frontend is built here).

## Testing

On full bootstraps of 89ba32eb (scratch, Chez 10.4.1, 2026-10-23, this
repository's 8-core arm64 macOS machine, an Apple M2 Max virtual machine
at load average 20 to 60 from other agents), one with every Idris patch,
96 and 104 to 114, and one with this patch as well, each of which built
itself and all its libraries (prelude, base, contrib, network, test,
linear, papers) with `make bootstrap install`: 1217 s and 1218 s wall,
502 s of user time each, 2.8 GiB peak RSS each (rusage), with no error
(*measured*): the libraries are checked by the built compiler. Its `make
install-api`, which checks Idris's own source with it, gives the same
three warnings and no error with the patch and without it (216 s and
228 s of user time, 594 s and 750 s wall, 413 and 389 MiB).

Times are user seconds of `idris2 --check FILE`, its Chez process run as
the installed launcher runs it, from `wait4`'s rusage, with the wall time
and the peak RSS beside them; at that load the wall times are two to
four times the user times.

| input | series | with the patch |
| --- | --- | --- |
| `Binds.idr`, 30 binds | 117.6 (382.8 wall, 217 MiB) | 0.97 (2.0 wall, 217 MiB) |
| 20, 24, 28 binds | 0.78, 2.45, 28.4 | 0.62, 0.73, 0.88 |
| `Machine.idr`, nine deep | 308.1 (791.8 wall, 217 MiB) | 2.85 (9.7 wall, 217 MiB) |
| six, seven, eight deep | 1.86, 6.32, 40.8 (64.9 wall) | 1.28, 1.66, 2.08 |
| the prototype's module, error removed | 11.0 (519 MiB; the toolchain's) | 9.0 (480 MiB) |

- On the unpatched pin the times are the series': `Machine.idr`'s nest
  seven deep spends 4.57 s building its size-change graph there, 4.65 s
  with the series and 0.015 s with the patch (`--timing 5`), and 22, 24
  and 26 binds take 1.17, 2.59 and 7.92 s there.
- The prototype's `recanonRow` reports its type error alike with and
  without the patch (6.5 and 5.3 s); the prototype's whole module, its
  error removed, checks on both.
- upstream's own tests, in the 31 groups 108's README lists, run by
  upstream's runner as tests/Makefile runs it in each built tree: 729 of
  733 pass with the patch and without it, and every test's result is the
  same. The four failing are `casetree/heuristics001` (105's),
  `literate/literate006` (108's), and `chez/chez017` and
  `reflection/reflection024`, which print a directory under `/tmp` as
  `/private/tmp`, the scratch trees' place on macOS.

`tests/upstream-size-change-as-pattern-doubling` checks that the pinned
Idris checks `Binds.idr` and `Machine.idr`, each within thirty seconds.
Its run script, run directly against each scratch build
(`IDRIS_MLIR_TOOLCHAIN` naming a directory whose `idris2` is that build's
prefix), prints its expected output with the patch (18.6 s wall for both,
at load 62), and without it, for each, that the bug still reproduces.

## When it goes

When the Idris pin carries an upstream fix (the check then passes without
the patch; upstream main has the same `knownOr` on 2026-10-23), or when
nothing of ours meets the shape. Until then the bootstrap applies the
patch.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in their own words, is their call. The patch goes when the pin
moves past upstream's fix, which
`tests/upstream-size-change-as-pattern-doubling` shows by passing on an
unpatched pin.
