<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] A constructor's implicit a clause leaves out keeps no mark

At the pin (third_party/Idris2 at 1c630e67, the toolchain's
`idris2` 0.8.0-1c630e67c), a function that matches a constructor whose
implicit argument the clause leaves out, and that the pattern of a later
field fixes, is reported not covering. Upstream/50's change, which the
checker has, does not reach it.

## Reproduce

`idris2 --check C.idr` on:

```idris
module C
import Data.List.Quantifiers
%default total

data W = A | F Integer | B

data IsF : W -> Type where
  ItIsF : IsF (F w)

data T1 : Type where
  C1 : {x : W} -> All IsF [x] -> T1

v1 : T1 -> ()
v1 (C1 (ItIsF :: [])) = ()

data T2 : Type where
  C2 : {0 x : W} -> All IsF [x] -> T2

v2 : T2 -> ()
v2 (C2 (ItIsF :: [])) = ()

0 v3 : T2 -> ()
v3 (C2 (ItIsF :: [])) = ()
```

It exits 1, reporting `v1 is not covering` and `v3 is not covering`,
each with missing cases `v1 (C1 _)` and `v1 (C1 _)` (`v3 (C2 _)` twice).
`v2` is accepted. The checker as the working tree had it (with 50's and
51's changes), built into a private prefix, gives the same two errors from
`idris-mlir-front --check C.idr`, exit 3. Measured on arm64 macOS,
2026-10-16.

## Expected

All three are covering: `ItIsF` is the only constructor of `IsF w`, so the
field `ItIsF :: []` fixes `x = F w`, and `C1 {x = A} _` has no value. A
clause that does not write an argument does not match on it before the
patterns that fix it.

## Found by

The agent that made upstream/50's change, which recorded it in that
report's "What the fix leaves".

## Cause

`makeImplicit` (`src/TTImp/Elab/App.idr`) elaborates an implicit argument
a pattern leaves out as a hole, bound as a pattern variable only if it
stays unsolved (`addBindIfUnsolved`). When unification solves it, the
solution takes its place, and the checked clause is the one a clause
writing `C1 {x = F w} (ItIsF {w} :: [])` would give: nothing says the
clause did not write `x`. Upstream/50 marks the arguments a clause leaves
to unification by the `n@_` the elaborator writes for them on the raw
left-hand side; a constructor's implicit never appears there, since the
elaborator inserts it while checking the application.

So the compile-time tree, which takes the columns left to right, splits
`x` before the field: `case x of F _ => ...`. The branches `x = A` and
`x = B` have no clause, and their candidates, `v1 (C1 {x = A} _)`, are not
impossible to the coverage check, which finds `All IsF [A]` inhabited by
`(::)` without looking at its field `IsF A` (upstream/50, Cause). In `v2`
the implicit is erased and the definition above quantity 0, where
upstream's 252e07833 takes an erased constructor pattern whose names are
bound elsewhere as a variable; that rule is off at quantity 0 (`v3`) and
never looks at a relevant argument (`v1`).

## The fix

Our type checker (compiler/checker) has the change as its own code,
after upstream/50's and upstream/52's, in that order. It also fixes
upstream/54-erased-constant-pattern, which needs the mark it adds; that
report points here.

- The elaborator binds an implicit argument a pattern leaves out as it
  binds the definition's own (`implicitsAs`): an as-pattern on its own
  side over the hole unification fills, named by the hole (`unifiedArg`,
  from `makeImplicit` and `makeDefImplicit`). It records the name
  (`EState`'s `marks`), which `elabTermSubMarked` returns, and `checkLHS`
  adds the names to the `VarSet` of arguments the clause leaves to
  unification, upstream/50's one mark (`unifiedArgs`). Above quantity 0 an
  erased argument is not marked: 252e07833's rule takes it as a variable
  where the names it binds are bound elsewhere, as before.
- A mark over a variable gives way to it (`markDrops`, and
  `findPLetRenames` skips it): the variable keeps its name and its as-name
  goes, so an implicit unification leaves unsolved, or solves to another
  pattern variable, is the variable it was. Where the definition's own
  `p@_` and a constructor's implicit meet on one unsolved variable
  (contrib's `Data.Nat.Factor`, `cofactor`), the definition's name stays.
- The case builder needs nothing new: upstream/52's order reads the mark
  at every step of the match, so once `C1` is split, its column `x` (bound
  to what unification found) is split after the field `ItIsF :: []`, whose
  pattern fixes it, and `x = A` is impossible by unification. The tree a
  definition above quantity 0 keeps has no mark (`saved`, upstream/52) and
  splits as at the pin, so no rule above quantity 0 is needed.
- `checkAs`'s binding of the as-name is `bindAs`, which `unifiedArg` uses
  too; `elabTermSub` is `elabTermSubMarked` without the marks.
- upstream/54's part: `getClauseType` reads where a pattern comes from
  (upstream/52's `Source`, `matchesErased`); at quantity 0 a pattern the
  clause writes on an erased argument is split whatever its kind, and one
  unification fixed keeps the old rule.

The checks below name `coverage034`, a test laid out for upstream's suite
beside the change, `ConImplicit.idr`: `v1`, `v3` (computed in a type), and `w3` and `w4`,
whose implicits the clauses write and still match, `w3 (C3 {x = B})` and
`w4 (C4 {x = B})` taking the second clause; and `coverage035`, for
upstream/54.

## What the fix leaves

- A `_` the clause writes, which unification solves: `f _ (ItIsF :: [])`
  with `f : (x : W) -> All IsF [x] -> ()`, and `v3 (C2 {x = _} (ItIsF ::
  []))`, are reported not covering, at the pin and with the fix. The mark
  is the elaborator's, for what it inserts; a wildcard the clause writes
  is solved in place.
- The tree a definition above quantity 0 keeps splits `x` first, as at the
  pin: `v1`'s Core tests `x`, and its branches `A` and `B` are
  `unreachable`, since `v1` is covering. `getW (C1 (ItIsF {w} :: [])) = w`,
  whose right-hand side reads `w` from `x`, is covering, and its program
  reads `w` from that split.

## Why there is no patch

There is no `idris.patch`: nothing the stock Idris builds meets the bug.
The Idris that elaborates what this compiler consumes is our type checker
in compiler/checker, Idris's checker copied into our tree, which has the
change as its own code. The stock Idris only builds stage 0 (the checker,
the frontend and the test runner) and the benchmarks' Chez baseline, and
nothing it builds is refused by the bug: all of it checks at the pin.

## Testing

At the pin, the stock Idris reports `coverage034`'s `v1` and `v3` not covering, two missing cases each, and
nothing else. The checker has 50, 52, 53 and 54 as one change, checked as
upstream/52's README says: among those checks, `coverage032` to
`coverage035` print exactly their `expected`, the reproducer checks,
`v1`'s and `v3`'s forms at the other quantity (`0 v1z`, and `v2` above
quantity 0) check, `getW` is covering, and the 385 programs give the same
status, output, Core and bytecode as before.
`tests/upstream-constructor-implicit-mark` compiles through the frontend,
which the unchanged checker's refuses. Its `expected` waits for a build of the
whole toolchain.

An earlier version of this change took a marked binding as a variable
(50's `asVariables`, extended to nested ones), with a rule above quantity 0
for the trees that run; upstream/52's order replaced both.

A first version let a mark take an unsolved variable's name, as a `ws@_`
does. It built base and could not build contrib: in `cofactor`, the
definition's erased `p@_` and `CofactorExists`'s relevant `{p}` met on one
variable, the mark took it, and the definition's `p` became an erased alias
the right-hand side could not use. That is why a mark gives way.

## Upstreaming plan

Status: recorded, not carried; nothing goes to idris-lang/Idris2 from
here. Idris accepts no contribution that arises from generative AI or a
coding agent, issues, pull requests, commits and comments alike
(upstream/README.md, **Idris**), and this report was written with one.
Whether to report the bug upstream is Bjorn's call alone, in their own
words and from their own understanding; nothing here is drafted for it. The
report goes when the Idris pin carries upstream's own fix; the checker
keeps its own, which `tests/upstream-constructor-implicit-mark` checks.
