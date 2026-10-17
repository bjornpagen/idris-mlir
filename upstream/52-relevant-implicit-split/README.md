<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] A relevant implicit the clauses leave out is reported not covering

At the pin (third_party/Idris2 at 1c630e67, the toolchain's
`idris2` 0.8.0-1c630e67c), the coverage checker rejects a definition above
quantity 0 whose clauses leave a relevant implicit to unification, when the
patterns that fix it rule a branch out only one level down. A case block
or a with block whose environment holds such an argument is rejected the
same way. It is the first case upstream/50-erased-coverage-nested-match
leaves: 50's `fp` with `ws` bound at quantity ω in a definition that runs.

## Reproduce

`idris2 --check X.idr` on:

```idris
module X
import Data.List.Quantifiers
%default total

data W = A | F Integer | B

data IsF : W -> Type where
  ItIsF : IsF (F w)

data Pr : W -> Type where
  M1 : Pr (F w)
  M2 : Pr B

fp4 : {ws : List W} -> All IsF ws -> All Pr ws
fp4 [] = []
fp4 (ItIsF :: fs) = M1 :: fp4 fs
```

It reports `fp4 is not covering`, with missing cases `fp4 _` and `fp4 _`.
With `cb xs = case xs of [] => 0; (ItIsF :: _) => 1` at the same type
(result `Nat`) it reports `cb` as calling the non-covering `case block in
cb`, and a `with (b)` block over the same arguments reports `with block in
wb _ True (A :: _) _` and `... (B :: _) _` missing. The fork with 50's
change reports the same. Measured on arm64 macOS, 2026-10-16.

## Expected

All are covering: `ItIsF` is the only constructor of `IsF w`, so `[]` and
`(ItIsF :: fs)` cover `All IsF ws` whatever `ws` is, and the quantity of
`ws` does not change which values the patterns cover.

## Found by

The record of upstream/50-erased-coverage-nested-match, whose "What the fix
leaves" lists it first.

## Cause

As in 50: an implicit a clause leaves out is bound by the elaborator as an
as-pattern over `_`, which unification solves from the clause's other
patterns (`ws = F w :: xs` in `fp4 (ItIsF :: fs)`); the compile-time tree
takes the arguments left to right, so it splits `ws` before the explicit
argument, and its branches `ws = A :: _` and `ws = B :: _` have no clause
and are not impossible to the coverage check, which does not see that
`All IsF (A :: xs)` is empty one level down. A case block's environment and
a with block's arguments are bound the same way. 50 made the tree of a
definition elaborated at quantity 0 take such an argument as a variable;
above quantity 0 the coverage check's tree still splits it first.

Taking it as a variable is wrong at every quantity, which two first
versions of this fix showed:

- A later argument's type may compute on it. In `liftedBad : {0 r : Rel a}
  -> Bad r xs -> New r xs y -> Lifted r xs y z -> r y z`, the type of the
  third argument reduces only once `xs` is split, and without that split the
  case builder cannot type the column: "Patterns for liftedBad require
  matching on different types". The pin accepts it. With 50's change the
  fork already refuses its copy at quantity 0, `0 liftedBad0`, and taken as
  a variable above quantity 0 it refused the frontend's own
  `IdrisMLIR.Proof.AlmostFull.liftedBad` (at efe0ad36; 3b1909e7 deletes
  the module).
- In this repository the tree a definition above quantity 0 keeps is the
  program that runs (the frontend translates it), and the split binds what
  the pattern names, which the right-hand side may read at run time where
  the clause's own patterns hold it only at quantity 0: `sumF (ItIsF {w} ::
  fs) = w + sumF fs` reads `w`, which `ItIsF` holds erased, and `fp4`'s
  recursive call passes the tail of `ws`. With the argument a variable in
  that tree the frontend fails on `sumF`: "a compile-time variable in a
  runtime position".

The root is the order, not the split: the tree splits a pattern the clause
does not write before the patterns that fix it.

## The fix

`pull-request.diff` is the change, against the pin with 50's
`pull-request.diff` applied, whose `VarSet` mark (the arguments a checked
clause leaves to unification, `unifiedArgs`) it reads. upstream/53's
`pull-request.diff` applies after it.

- Each row of the case builder's match carries the clause it comes from
  (`Origin`): its place, which its leaf names, and the names of the
  arguments it leaves to unification, which every copy of the row keeps
  through the splits. At every step `match` arranges the columns
  (`arrange`): one the clauses only bind, and some bind to what
  unification found from the patterns they write (`Use`: `Binds`,
  `Fixed`, `Tests`), goes after the others. It is still split: a leaf
  binds what its pattern names, and a column whose type computes on it
  waits for it (`pickNextViable` passes over a column it cannot type yet).
  Split after the patterns that fix it, the branches it leaves are
  impossible by unification, which the coverage check sees. This replaces
  50's `asVariables`, which took such an argument as a variable. Where a
  column's type is not known, the columns keep their order (`typed`): such
  a type is found as the columns before it are split.
- `getPMDef` reads the mark of every clause it is given, at every phase.
  The coverage check gives it the checked clauses, so its tree splits such
  an argument last at every quantity, and so does the tree a definition
  elaborated at quantity 0 keeps. The tree a definition above quantity 0
  keeps is built from the clauses without the mark (`saved`): it is the
  program that runs, and it takes an erased argument as a variable where
  later patterns bind the names in it; moved last, that argument is split
  instead, and a type the definition computes stops reducing while it is
  unsolved. With every compile-time tree arranged, base no longer builds:
  `Data.Nat.Order.lte` leaves the length in `Data.Fun`'s `Fun` and `chain`
  unsolved. The runtime tree (`mkRunTime`) has no mark.
- A column some clause tests keeps its place, so a clause's own test is
  never moved.

upstream/53 adds marks for a constructor's implicits, which the same order
splits after the field that fixes them, at whatever step their constructor
is split; upstream/54 is a rule of the same `Use` at quantity 0.

Upstream test: `tests/idris2/coverage/coverage033` (in the diff),
`RelevantImplicit.idr`: `fp4`, `sumF` with a reduction in a type, the case
block `cb`, the with block `wb`, and `liftedBad` and `0 liftedBad0`.

## What the fix leaves

- A column some clause tests and another leaves to unification keeps its
  place: with `mixed {ws = []} [] = 0` and `mixed (ItIsF :: fs) = S (mixed
  fs)`, `mixed` is reported not covering at the pin and with the fix.
  Moving the column would move the first clause's own test.
- The tree a definition above quantity 0 keeps still splits such an
  argument first: the frontend's program for `fp4` tests `ws` before its
  explicit argument, and the branches the coverage check now proves no input
  reaches (`ws = A :: _`) are `unreachable` in its Core, since the
  definition is covering.

## Why there is no patch

There is no `idris.patch`. The Idris that elaborates what this compiler
consumes is the fork in compiler/idris, which carries the change as its own
code. The stock Idris only builds stage 0 (the fork, the frontend and the
test runner) and the benchmarks' Chez baseline, and nothing it builds is
refused by the bug: all of it checks at the pin.

## Testing at the pin

The series 50, 52, 53 applies to the pin in that order (`git apply`, each
in turn, on an archive of the pin), and gives the fork's change line for
line, but for two lines of the pin's own that 53 moves (`elabTermSub`'s
`DelayedElabs` argument, and `checkAs`'s log). The pinned Idris typechecks
the compiler with 50 and 52, and with all three (`idris2 --typecheck
idris2api.ipkg`). No stock Idris has been built with them and upstream's
suite has not run with them; at the pin, the stock Idris reports
`coverage033`'s `fp4`, `sumF`, `cb` and `wb` not covering and accepts
`liftedBad` and `liftedBad0`.

The fork carries 50, 52, 53 and 54 together, one change. It was built by
the pinned Idris into a private prefix, with the frontend against it, and
compared with the working tree's fork (efe0ad36 with 50's and 51's changes;
3b1909e7 deletes `IdrisMLIR.Proof.AlmostFull`, which its frontend still
imports, so efe0ad36's compiler and tests are the base) built the same way
(arm64 macOS, 2026-10-16):

- `coverage032` to `coverage035` print exactly their `expected`; the
  reproducer, 50's `fp`, `fp2`, `fp3`, `g` and `Pick`, this report's `fp4`,
  `sumF`, `cb`, `wb`, `liftedBad` and `liftedBad0`, 53's `v1` and `v3` and
  their quantity-0 forms, and 54's `h` (`h 5` is 2, `h _` reachable) check.
  `mixed`, and 53's solved wildcards, are reported as at the pin;
- the fixtures of upstream/21, 50, 51, 52, 53 and 54 compile through the
  frontend as they should (51's is refused, as its test expects), 21's and
  50's to the same Core as the baseline's. This report's fixture compiles
  to the Core checked when it was first made: `sumF` splits `ws`, reads `w`
  from `F`'s field and recurses on the tail of `ws`; `fp4`, `count`, `cb`
  and `wb` likewise. Its `expected` waits for a build of the whole
  toolchain;
- prelude, base, linear, network, contrib, test, mlir-linear, mlir-array and
  the fork's own package build with it. Of the 484 TTCs, 161 are
  byte-identical to the baseline's and 284 hold the same definitions, their
  headers' hashes and machine-generated names aside. The definitions of the
  other 39 that differ: those of the 8 fork modules the change edits; 27 at
  quantity 0, whose kept tree splits an argument left to unification last;
  and 56 above quantity 0 whose clauses hold a new mark of 53's: 49 with
  the same splits and a `let` in a leaf binding the marked name to the term
  it stood for, and 7 case blocks and local definitions that take the
  enclosing clause's new binder as an argument, or rebuild 53's `EState`.
  No run-time tree, and no definition's quantity or totality, changed;
- on the 385 programs of `tests/programs`, `tests/accept` and
  `tests/reject`, the frontend's exit status, stdout, stderr, Core dump and
  bytecode are identical to the baseline's, against the baseline's prefix
  and against the one the changed frontend built;
- the frontend's own sources (efe0ad36's `compiler/src`, with
  `AlmostFull`) check with it as with the baseline.

52 alone was first checked the same way, against the same base; with it
50's `asVariables` was taken out, and a version that took the argument as a
variable above quantity 0 refused `AlmostFull.liftedBad`.

## Upstreaming plan

Status: carried as the fork's code; nothing goes to idris-lang/Idris2
from here. Idris accepts no contribution that arises from generative AI
or a coding agent (upstream/README.md, **Idris**), and this report, the diff
and the fork's change were written with one.

- `pull-request.diff` is the record of what the fork changed against the
  pin, after 50's change and before 53's, laid out as a stock checkout with
  the upstream test (`coverage033`) it would carry. At a re-sync of compiler/idris
  (compiler/idris/README.md) it says what to look for upstream: if upstream
  has fixed the bug its own way, the fork takes upstream's code and drops
  this change, with 50's; if not, the change is carried forward onto the
  new base. Whatever upstream does with the tree a definition above
  quantity 0 keeps, the fork keeps that tree's order (`saved`): its frontend
  translates it, and its erased arguments are taken as variables.
- When upstream's fix arrives: this directory,
  `tests/upstream/relevant-implicit-split` and the PINS.md entry go.
- Whether to report the bug upstream is Bjorn's call alone, in his own
  words and from his own understanding; nothing here is drafted for it.
