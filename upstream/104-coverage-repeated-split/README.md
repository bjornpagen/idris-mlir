<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] The coverage checker loses a refinement when a tree splits a variable twice

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), `Covering.idr`,
checked by the stock Idris, fails with `f is not covering` and names
`f Read (There _)` as missing (*measured*, scratch build of 89ba32eb on
Chez 10.4.1). `f` is covering: a proof that `Read` is the second element of
`[Read, Write]` is `There Here`, which needs `Read = Write`, and every
`There (There _)` is the third clause's. Adding the clause
`f Read (There Here) impossible` changes nothing: the same case is reported.

```idris
f : (k : Kind) -> Elem k [Read, Write] -> ()
f Read Here = ()
f Write (There Here) = ()
f _ (There (There later)) = absurd later
```

It is the shape of a proof that indexes a table by a kind with a wildcard
for the cases the index rules out, which the specification's effect rows
had (the old `Spec.Effects.Atom.kept`). Upstream's open issues #550 and
#3710 report the same symptom on lists.

## Cause

*read* at 89ba32eb, `src/Core/Coverage.idr`. The compile-time tree for `f`
splits `k`, then the proof; under `k = Read` its first case on the proof
has `Here` and a default, and the default holds the tree for the third
clause, which splits the proof again (`case {arg:1} of There e0 .. e4 =>
case e4 of There ...`). `buildArgs` walks the tree with the patterns built
so far (`ps`), substituting each split variable by name. It replaces the
default by the constructors it stands for, so `ps` become `f Read (There
m0 .. m4)`; then the second split of the same variable binds its arguments
again, as `e0 .. e4`, and `buildArgs` substitutes the variable in `ps`,
where it no longer occurs, so `e4` is tied to nothing. The split of `e4`
that finds `Here` missing returns `ps` unrefined: `f Read (There _)`,
which is neither impossible nor matched by a clause, so it is reported.
The same happens one level down for every argument of a variable split
twice whose own argument was split in between (the specification's old
`kept`: `kept Write Count (There (There _)) _`), and the alternatives that
stand for a default all name their arguments `m0`, `m1`, ..., so two of
them on one path share names.

## Patch

`idris.patch`, against 89ba32eb: `buildArgs` keeps what each variable of
the tree stands for in `ps` once a split has refined it. A split of a
variable that stands for a constructor binds its arguments to that
constructor's parts in `ps` (and is impossible for any other constructor,
so it proposes nothing); a split of one that stands for a pattern variable
substitutes it, naming its arguments afresh for each split (printed `m`,
as the default's are, so messages read as before). Delays and constants
are refined the same way. Only the walk that
proposes missing patterns changes, and each proposal is still checked
(impossible, or matched by a clause) as before, so a refined proposal is
reported only where the unrefined one would have been. See `## Testing`.

## Testing

On a full bootstrap of 89ba32eb carrying 104 to 107, in order (scratch,
Chez 10.4.1, 2026-10-22), which built itself and all its libraries with
them; times are wall seconds on an 8-core Apple M2 Max virtual machine at
load average 5 to 15, the unpatched build's runs stopped at 120 s.

- `Covering.idr` checks (unpatched: `f is not covering`, naming
  `f Read (There _)`).
- the examples of upstream #550 and #3710 check (unpatched: not covering).
- the specification's old `kept`, standalone with its types, checks in 3 s
  (unpatched: past 120 s, the case tree, 105; INT-5 measured 986 s and
  18.7 GiB on the specification).
- definitions that do miss a case are still refused, each naming exactly
  the case it misses where the unpatched build named a spurious one
  beside it: #550's example without its fourth clause reports
  `test ((_ :: _) :: _) ([] :: _)`; the reduced `kept` without the `Write`
  clause reports `f Write (There Here)`.

Upstream's own tests in the groups basic, casetree, coverage, error,
evaluator, failing, interface, linear, perf, reg, termination, total and
with, run as upstream's runner runs them: 391 of 392 pass, as all 392 do on the unpatched build. The one
difference is `casetree/heuristics001`, which prints a compile-time tree:
105 leaves out an alternative `S` under a default that `S` has already
missed (dead: the variable is neither `Z` nor `S` there), and the
generated names after it shift.

## When it goes

When the Idris pin carries upstream's own fix (the check then passes
without the patch), or when nothing of ours meets the shape. Until then
our code writes the covering proof as Idris allows it, and the bootstrap
applies the patch.

Our type checker (compiler/checker) carries the change as its own code, in
`Core.Coverage.buildArgs`, which `tests/checker-coverage-repeated-split`
checks; it stays when the patch goes.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, or comments on #550 or #3710, in their own words, is their call. The
patch goes when the pin moves past upstream's fix, which
`tests/upstream-coverage-repeated-split` shows by passing on an unpatched
pin.
