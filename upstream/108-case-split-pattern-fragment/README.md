<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris] A case that splits a bound variable takes the constraints on it out of the pattern fragment

At Idris 2 main 89ba32eb (third_party/Idris2's gitlink), the stock Idris
refuses two well-typed definitions (*measured*, scratch build of 89ba32eb
on Chez 10.4.1):

- `Update.idr`: a record update in a lambda whose type is inferred,
  `let keep = \pool => { runs $= map S } pool in map keep pools`: "Can't
  solve constraint between: Pool and ?caseTy".
- `Hint.idr`: `map (\k => { threads := k } o) (parsePositive n)`, where
  `threads : Nat`: "Mismatch between: Integer and Nat".

The same definitions check with the lambda annotated, with no `case` (a
constructor applied instead of an update), or with the case on `id o`
instead of `o`: only a case that splits a bound variable fails. Upstream's
issue #62, opened by its author, reports the family ("case in a lambda is
broken"); its example, `(\dx => case dx of () => ()) ()`, fails the same
way ("Can't solve constraint between: ?delayTy and ()"). The harness was
bent around both before (552cf2ec: `keep` given a signature,
`parsePositive {a = Nat}`).

## Cause

*read* at 89ba32eb, `src/TTImp/Elab/Case.idr`. A record update is a
`case` on the record. `caseBlock` elaborates the case as a function over
the environment and splits the scrutinee where it is a bound variable,
so in each clause the variable is replaced by the constructor pattern,
in the spine of every still-unsolved meta applied to it: the lambda's
result type in `Update.idr`, `parsePositive`'s `a` in `Hint.idr` (the
type of `k`, an argument of the case function). A constraint between such
a meta and a type is then outside the pattern fragment, so it is
postponed and never solved; in `Hint.idr` the `%defaulthint` for `Num`
fires meanwhile, fixing `a` as `Integer` against the field's `Nat`.

## Patch

`idris.patch`, against 89ba32eb with 104 to 107, changes `caseBlock`
alone. Where the case splits a bound variable, every clause's pattern
there is not a variable, and an unsolved meta in the case function's
type, after that variable's binder, is applied to it, the function takes
the variable twice: split, and again, at quantity 0, just inside it and
unsplit; those metas are applied to the unsplit copy, which each clause
binds as a pattern variable, as it binds the environment's, and the call
passes the variable in both places. The copy is the same value at every
call, so the function's type, applied, is the one it had; inside a clause
the metas stand applied to variables, so the clause's constraint on them
is in the pattern fragment and is solved there, as a function of the
variable that holds outside the case too. Nothing changes for a case on
an expression, or on a variable no unsolved meta is applied to; and a
meta solved before the case block runs (it is a delayed elaborator, run
after the rest of its term) is not touched.

Nothing changes either for a case with a clause whose pattern at the
variable is a variable (`_`, a name, or an as-pattern of one). That clause
leaves the variable as it is, so the metas stand applied to its own
variable and it solves them, as the unpatched Idris does; the copy would
take that away. A clause's own metas (the type of a `Left` it builds, say)
depend on every variable it binds, the split variable's among them, so a
meta applied to the copy instead cannot be solved to a term that mentions
them ("Can't shrink"), and the case's type is then never found:
`Default.idr`, a pattern bind on a case with a catch-all clause, the shape
of Idris's own `src/Idris/REPL.idr:522` (`processEdit`), failed with
"Can't infer type for case scrutinee" when the copy was taken in every
case, and `make install-api` with it (INT-13's bisection).

What it gives up: such a meta, solved from a clause, cannot depend on
which constructor the clause matched. A case whose type depends on its
scrutinee and is learnt only after the case block runs would need that,
and the unpatched Idris refuses the shapes tried as well: in `foo b = let
f = \x => case x of True => the Nat 1; False => "a" in f b`, at
`(b : Bool) -> if b then Nat else String`, and in the same written as an
applied lambda, the unpatched build cannot solve the case's type and the
patched build fixes it from the first clause, so both refuse
(*measured*); with the lambda's type given the case checks in both.

## Testing

On full bootstraps of 89ba32eb (scratch, Chez 10.4.1, 2026-10-22, an
8-core Apple M2 Max virtual machine at load average about 4), each of
which built itself and all its libraries (prelude, base, contrib,
network, test, linear, papers): one with 104 to 107 and this patch, and
one with every Idris patch, 96 and 104 to 109. The second, with the patch
as it now stands, ran the bootstrap's own targets, `make bootstrap
install install-api`, to the end: 449 s wall, 3.0 GiB peak RSS (rusage),
beside one other Idris process (*measured*).

- `Update.idr`, `Hint.idr` and #62's example check; run, the update
  maps `[[1, 2], []]` to `[[2, 3], []]` and `setThreads (MkOpts 1) "8"`
  gives `Just 8`. `Default.idr` and INT-13's reproducer of `processEdit`
  check, as on the unpatched build; with the copy taken in every case
  both failed, "Can't infer type for case scrutinee".
- Upstream's own tests, run as upstream's runner runs them. With 104 to
  107 and this patch in its first form (the copy taken in every case): in
  the groups basic, casetree, coverage, error,
  evaluator, failing, interface, linear, perf, reg, termination, total
  and with, 391 of 392 pass, as without it (`casetree/heuristics001` is
  105's); in chez, allschemes, base, prelude, codegen and typedd-book, 147
  of 153, the six failing alike without it (96's README says why). With
  every patch, the patch as it now stands, those groups and data, misc,
  operators, reflection, builtin, warning, literate, false, debug,
  schemeeval, ttimp and linear as well: 724 of 734 pass, as with its
  first form, and against the builds without 96, 108 and
  109 the one difference is `literate/literate006`. It prints the context
  of a hole in a case block that takes its split variable twice (every
  clause splits it) with two variables in the other order (`x : Integer`
  before `1 d : Door Open`; the same variables, the same types, the copy
  not shown): the clause binds one more pattern variable, and
  `getToBind` binds a clause's pattern variables in dependency order
  (`depSort`), which with the copy among them puts `x` first. The other
  two failures in those groups, `literate/literate017` and
  `reflection/reflection024`, fail alike with 104 to 107 alone.

`tests/upstream-case-split-pattern-fragment` checks that the pinned Idris
checks the three reproducers.

## When it goes

When the Idris pin carries upstream's fix for #62 (the check then passes
without the patch). Until then the bootstrap applies the patch.

## Upstreaming plan

Nothing is sent: Idris takes no contribution written with generative AI
or a coding agent (upstream/README.md, **Idris**). Whether Bjorn comments
on #62, in his own words, is his call. The patch goes when the pin moves
past upstream's fix, which `tests/upstream-case-split-pattern-fragment`
shows by passing on an unpatched pin.
