<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] A case tree copies its fallthrough whole into every alternative

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), the stock Idris
does not finish checking `Fallthrough.idr`, one function of thirty clauses
whose first argument alternates between constructors and a wildcard, in
120 s (*measured*, scratch build of 89ba32eb on Chez 10.4.1, an 8-core
Apple M2 Max virtual machine at load average 25 to 50). The
specification's `Spec.Effects.Atom.kept`, the same shape with a richer
result, ran 986 s to 18.7 GiB before it was rewritten to avoid it (INT-5,
70258ae5). With the first two arguments swapped, so every clause has a
constructor first, the six-state module below checks in 0.1 s.

The growth, *measured* on modules of n states of the same shape (each
state admitting one to three kinds, one clause per admitted kind and one
`absurd` clause per state): the compile-time tree has 35, 1170, 10531 and
148772 alternatives for n = 1 to 4, and checking takes 0.3 s at n = 2,
6 s at n = 4, and more than 900 s at n = 5 (stopped there).

## Cause

*read* at 89ba32eb, `src/Core/Case/CaseBuilder.idr`. At compile time the
builder splits the first column (`nextIdxByScore` takes the first for
`CompileTime`, so the tree that defines reduction splits left to right).
`partition` cuts the clauses into runs of constructor and wildcard
patterns in that column, and `mixture` compiles each run with the tree of
the runs after it as its fallthrough. `caseGroups` copies that fallthrough
into every alternative it builds and into its default. A copy keeps every
alternative of its own cases, including those the alternative it sits in
has ruled out, so the tree of one run holds several copies of the tree of
the next: the tree, and every pass over it (coverage, the run-time tree,
the checks that follow), is exponential in the number of runs.

## Patch

`idris.patch`, against 89ba32eb: `caseGroups` prunes each copy of the
fallthrough. In the alternative for constructor `c` of variable `x`, every
case on `x` in the copy keeps only `c`'s alternative, or its default when
it has none; in the default, every case on `x` in the copy drops the
alternatives of the constructors this case matched. A case left with
nothing is left alone. This changes no result: in `c`'s alternative `x` is
`c`, so evaluation would take `c`'s alternative; a default is taken only
for a concrete value (`Core/Normalise/Eval.idr`, `tryAlt` on
`DefaultCase`) that none of the matched constructors is. Constructors are
told apart by name, which is how the evaluator matches a type constructor
(all of them have tag 0 in the builder). The coverage walk already ignores
the pruned alternatives (it filters by the same knowledge), and a clause
now absent from the tree was reachable only through a pruned, dead path,
so the unreachable-clause warning it may now get is correct.

## Testing

On a full bootstrap of 89ba32eb carrying 104 to 107, in order (scratch,
Chez 10.4.1, 2026-10-22), which built itself and all its libraries with
them; times are wall seconds on an 8-core Apple M2 Max virtual machine at
load average 5 to 15, the unpatched build's runs stopped at 120 s.

- `Fallthrough.idr` checks in 1 s (unpatched: past 120 s).
- the specification's old `kept`, standalone, checks in 3 s (unpatched:
  past 120 s).

Upstream's own tests in the groups basic, casetree, coverage, error,
evaluator, failing, interface, linear, perf, reg, termination, total and
with, run as upstream's runner runs them: 391 of 392 pass, as all 392 do on the unpatched build. The one
difference is `casetree/heuristics001`, which prints a compile-time tree:
105 leaves out an alternative `S` under a default that `S` has already
missed (dead: the variable is neither `Z` nor `S` there), and the
generated names after it shift.

## When it goes

When the Idris pin carries an upstream fix that keeps such a tree small
(the check then passes without the patch). Until then our code writes such
a definition as Idris allows it, and the bootstrap applies the patch.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn reports
the bug, in his own words, is his call. The patch goes when the pin moves
past upstream's fix, which `tests/upstream-case-tree-fallthrough-copies`
shows by passing on an unpatched pin.
