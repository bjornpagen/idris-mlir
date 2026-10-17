<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] An erased function with a nested constructor match is reported not covering

At the pin (third_party/Idris2 at 1c630e67, the toolchain's
`idris2` 0.8.0-1c630e67c), the coverage checker rejects an erased (`0`)
function whose clauses match a constructor nested inside another. The same
function without the `0` is accepted.

## Reproduce

`idris2 --check X.idr` on:

```idris
module X
import Data.List.Quantifiers
import Data.List.Elem
%default total

data W = A | F Integer | B

data IsF : W -> Type where
  ItIsF : IsF (F w)

data Pr : W -> Type where
  M1 : Pr (F w)
  M2 : Pr B

0 fp : All IsF ws -> All Pr ws
fp [] = []
fp (ItIsF :: fs) = M1 :: fp fs

fp2 : All IsF ws -> All Pr ws
fp2 [] = []
fp2 (ItIsF :: fs) = M1 :: fp2 fs

0 fp3 : {ws : List W} -> All IsF ws -> All Pr ws
fp3 [] = []
fp3 (ItIsF :: fs) = M1 :: fp3 fs
```

It reports `fp is not covering` and `fp3 is not covering`, each with
missing cases `fp _` and `fp _` (`fp3 _` and `fp3 _`). `fp2`, which
differs from `fp` only in its quantity, is accepted. Measured on arm64
macOS, 2026-10-16.

## Expected

All three are covering: `ItIsF` is the only constructor of `IsF w`, so
`(ItIsF :: fs)` and `[]` cover `All IsF ws` whatever `ws` is, and the
quantity of the function does not change which values its patterns cover.

## Found by

The drafter of the checker packet's lanes P1 and P4
(`proposals/0003-self-host/checker`), writing erased proofs over
`All` and the graph's certificates. Their sketches are now written without
any function that meets it, so nothing in the tree reaches it.

## Cause

`clauseType` (`src/Core/Case/CaseBuilder.idr`) decides, for each clause
and column, whether the case tree splits on the clause's pattern there. At
compile time it takes a constructor pattern on an erased argument as a
variable when every name in it is bound elsewhere, but only in a
definition elaborated above quantity 0 (`not (isErased cr)`, from
upstream's 252e07833, "Fix case trees at multiplicity zero", test
`reg022`). Above quantity 0 every pattern a clause writes on an erased
argument was elaborated must-unify (`dotErased`, `src/TTImp/Elab/App.idr`),
so the rule only ever skips patterns the clause does not match on. At
quantity 0 nothing is made must-unify: a clause's own pattern on an erased
argument is a match (`g Z = ...; g (S k) = ...` on `(0 n : Nat)`), the
rule cannot tell it from one the clause does not match on, and it is off.

An implicit a clause leaves out is bound by the elaborator as an
as-pattern on its own side over `_`, `IAs _ _ UseLeft ws (Implicit _ True)`
(`implicitsAs`, `src/TTImp/TTImp.idr`; a case block's environment and a
with block's arguments are bound the same way), and unification solves it
from the clause's other patterns: in `fp (ItIsF :: fs)`, `ws = F w :: xs`.
A compile-time tree takes the columns left to right, so `fp`'s tree splits
`ws` first:

```
case ws of
  []       => case arg of [] => ...
  (x :: _) => case x of
                F _ => case arg of (_ :: _) => ...
```

The branches `ws = A :: _` and `ws = B :: _` have no clause, and their
candidates, `fp {ws = A :: _} _`, are not impossible to the coverage
check: it looks for a pattern variable whose type no constructor fits
(`hasEmptyPat`, `isEmpty` in `src/Core/Coverage.idr`), and `All IsF (A ::
xs)` has one, `(::)`, whose field `IsF A` is the empty type, one level
down. In `fp2` the same `ws` is an erased argument of a definition above
quantity 0, so its tree takes it as a variable and splits the explicit
argument, where `IsF x` has one constructor. `fp3` has `ws` at quantity ω,
which the rule at quantity 0 does not look at either.

The checked clause cannot tell the case builder which as-patterns are such
bindings. Their side is no mark: a case block on a variable of its
environment (`if b then p else Not p` in a type is one) puts the
alternative's own pattern into the as-pattern that binds the variable,
also `UseLeft` (`replace`, `src/TTImp/Elab/Case.idr`). Only the raw
left-hand side shows the difference, the `_` under the as-pattern, and
`checkLHS` returns it beside the checked one, which `checkClause` drops.

## The fix

`pull-request.diff`, against the pin, is the change as first made.
upstream/52-relevant-implicit-split's `pull-request.diff`, which applies
after it, replaced its case-builder half; the fork carries both:

- A checked clause carries the variables of its scope that name an
  argument it leaves to unification (`MkClause`'s new `VarSet`).
  `checkClause` reads them off the raw left-hand side (`unifiedArgs`: the
  names of `IAs _ _ UseLeft n (Implicit _ _)`, the form upstream's
  `isImplicitAs` already recognises), for pattern clauses and with
  clauses; every other clause has none.
- In a definition elaborated at quantity 0, the case builder took each
  such argument as the variable it is (`asVariables`): its as-pattern
  became its name alone, unless a name in its pattern was bound by no
  pattern the clause writes. That refused what the pin accepts: when a
  later argument's type computes on such an argument, the case builder
  cannot type that column without the split, and with this change alone
  the fork refuses `0 liftedBad0 : {0 r : Rel a} -> Bad r xs -> New r xs y
  -> Lifted r xs y z -> r y z` ("Patterns for liftedBad0 require matching
  on different types"). upstream/52 replaced `asVariables` with an order:
  the tree splits such an argument after the patterns the clause writes,
  at every step, so the candidates its other splits leave are impossible by
  unification, and a column whose type needs it waits for it. `fp`'s tree
  splits the explicit argument first and `ws` last.
- Nothing else changes: a clause's own patterns stay matches (`g Z = 1; g
  _ = 2` still splits `Z`, as `reg022` needs, and so does a case
  alternative on a variable), the clauses a definition saves are the
  checked ones, so its termination graphs are unchanged, and the trees of
  a definition above quantity 0 are unchanged. The REPL's clause
  generation (`TTImp.Interactive.GenerateDef`, which the fork deleted)
  takes the new field apart in the diff.

Upstream test: `tests/idris2/coverage/coverage032` (in the diff),
`ErasedNested.idr`: `fp`, `fp2` and `fp3`, `fp` computed in a type, `g`,
whose `g 5` must take its second clause, and `Pick`, an `if` on a
variable in a type, whose `Pick False` must take the `else`.

## What the fix leaves

The same split, of a pattern the clause does not match on, before the
patterns that fix it, had three more cases besides `fp`'s, which this
change did not reach. Each now has its own record and change, which the
fork carries: upstream/52 (the first), 53 (the second) and 54 (the third).

- A definition above quantity 0 with a relevant implicit the clauses leave
  out: `fp4 : {ws : List W} -> All IsF ws -> All Pr ws`, with `fp`'s
  clauses, is reported not covering at the pin and with the fix. Taking the
  binding as a variable there changes the compile-time tree of a
  definition that runs, which this repository's frontend translates: a
  case block over `xs : Vect n Int` with `n` relevant in scope splits `n`
  before `xs` today, so that change needs its own check of the frontend's
  output.
- A constructor's implicit a clause leaves out, solved by unification,
  keeps no mark in the checked term. With `C1 : {x : W} -> All IsF [x] ->
  T1`, `v1 : T1 -> (); v1 (C1 (ItIsF :: [])) = ()` is reported not
  covering at the pin and with the fix, and so is the same in an erased
  definition with `{0 x : W}`.
- At quantity 0, a constant or type pattern a clause writes on an erased
  argument is taken as a variable (upstream's 252e07833 changed only
  constructor patterns): `0 h : (0 n : Integer) -> Integer; h 0 = 1; h _ =
  2` reports `h _` unreachable, and `h 5` reduces to `1`, at the pin and
  with the fix. Telling those from a constructor's type implicit, which is
  a type pattern on an erased argument that unification solved, needs the
  mark the previous case lacks.

With all four, one form keeps the pin's split: a `_` the clause writes
that unification solves (upstream/53). A column one clause writes and
another leaves to unification (`mixed {ws = []} [] = 0; mixed (ItIsF ::
fs) = S (mixed fs)`) is covering too: the column keeps its place, and the
parts of the pattern unification found are split after the others
(upstream/52).

## Why there is no patch

There is no `idris.patch`. The Idris that elaborates what this compiler
consumes is the fork in compiler/idris, which carries the change as its own
code. The stock Idris only builds stage 0 (the fork, the frontend and the
test runner) and the benchmarks' Chez baseline, and nothing it builds is
refused by the bug: all of it checks at the pin.

## Testing at the pin

`pull-request.diff` applies to the pin (`git -C third_party/Idris2 apply
--check`). No stock Idris has been built with it and upstream's suite has
not run with it; at the pin, the stock Idris reports `coverage032`'s `fp`
and `fp3` not covering, two missing cases each, and nothing else. The same
edits applied to HEAD's fork give the fork's change byte for byte. The
fork with the change was built by the pinned Idris into a private prefix,
with the frontend against it, and compared with HEAD's built the same way
(arm64 macOS, 2026-10-16):

- the reproducer and `coverage032`'s file check (`idris-mlir-front
  --check`), the latter printing exactly the test's `expected`; HEAD's
  frontend reports the stock Idris's errors on both. `fp4`, `v1`, `v3` and
  `h` (above) are reported as before;
- the frontend builds its prefix with it (prelude, base, linear, network,
  contrib, test, mlir-linear, mlir-array). 279 of the 280 TTCs are
  byte-identical to HEAD's; the other is `Syntax.PreorderReasoning.Generic`,
  whose erased `Prerequisite` leaves `der` to unification and matches only
  the view, which its tree now splits first;
- on the 385 programs of `tests/programs`, `tests/accept` and
  `tests/reject`, the frontend's exit status, stdout, stderr, core dump and
  bytecode are identical to HEAD's, against the tree's prefix and against
  the one the changed frontend built;
- `tests/upstream/erased-coverage-nested-match` compiles through the
  frontend, which HEAD's refuses; its `expected` waits for a build of the
  whole toolchain.

Those checks are of the change as first made. The fork now carries it with
upstream/52's order in place of `asVariables`, and with 53's and 54's
changes; upstream/52's README has the checks of that whole change, among
them `coverage032`, which prints exactly its `expected`, and this report's
fixture, which compiles to the same Core as before.

A first version read the as-pattern's side alone as the mark. It passed
the corpus against HEAD's prefix and could not build base:
`Data.Bool.Decidable.invert`'s type, `if b then p else Not p`, is a case
block on a variable, whose alternatives sit in `UseLeft` as-patterns. That
is why the clause carries what the raw left-hand side says, and why
`coverage032` and the fixture check `Pick`.

## Upstreaming plan

Status: carried as the fork's code; nothing goes to idris-lang/Idris2
from here. Idris accepts no contribution that arises from generative AI
or a coding agent, issues, pull requests, commits and comments alike
(upstream/README.md, **Idris**), and this report, the diff and the fork's
change were written with one.

- `pull-request.diff` is the record of what the fork changed against the
  pin, laid out as a stock checkout with the upstream test (`coverage032`)
  it would carry. At a re-sync of compiler/idris
  (compiler/idris/README.md) it says what to look for upstream: if
  upstream has fixed the bug its own way, the fork takes upstream's code
  and drops this change; if not, the change is carried forward onto the
  new base.
- When upstream's fix arrives: this directory,
  `tests/upstream/erased-coverage-nested-match` and the PINS.md entry go.
- Whether to report the bug upstream is Bjorn's call alone, in his own
  words and from his own understanding; nothing here is drafted for it.
