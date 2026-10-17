<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# [Idris2] At quantity 0, a constant pattern on an erased argument is dropped

At the pin (third_party/Idris2 at 1c630e67, the toolchain's
`idris2` 0.8.0-1c630e67c), the case tree of a definition elaborated at
quantity 0 takes a constant or a type that a clause writes on an erased
argument as a variable. The clause then matches every value, the
definition reduces by it, and the type checker proves what the clauses
deny.

## Reproduce

`idris2 --check H.idr` on:

```idris
module H
%default total

0 h : (0 n : Integer) -> Integer
h 0 = 1
h _ = 2

hFive : h 5 = 2
hFive = Refl
```

It exits 1: `Warning: Unreachable clause: h _`, then `Error: While
processing right hand side of hFive. ... Mismatch between: 2 and 1.` With
`hFive : h 5 = 1` instead, the file checks: the second clause is
unreachable and `h 5` is 1. The same holds of a type (`0 tp : (0 t : Type)
-> Integer; tp Integer = 1; tp _ = 2` reduces `tp String` to 1) and of a
constant under a constructor (`pv (MkP 0) = 1; pv (MkP _) = 2` with
`MkP : (0 n : Integer) -> P` reduces `pv (MkP 5)` to 1). The fork as the
working tree has it (upstream/50 and 51 applied) gives the same from
`idris-mlir-front --check`, exit 3, and accepts `h 5 = 1`. Measured on arm64
macOS, 2026-10-16.

## Expected

`h 5` is 2, and every clause is reachable: a pattern a clause writes is a
match, whatever the quantity of its argument. A definition at quantity 0
does not run, so nothing stops its tree from matching an erased argument;
it is how such a definition computes in types.

## Found by

The agent that made upstream/50's change, which recorded it in that
report's "What the fix leaves".

## Cause

`getClauseType` (`src/Core/Case/CaseBuilder.idr`) decides, per clause and
column, whether the tree splits there. For a pattern on an erased argument
it answers "variable", in every phase, unless the pattern is a constructor:
upstream's 252e07833, "Fix case trees at multiplicity zero", made a
constructor pattern split at quantity 0 and left constants, types, function
types and delays to the general rule, which is right only for a tree that
runs. At quantity 0 nothing is made must-unify (`dotErased` acts only above
it), so the `0` of `h 0` is the clause's match, and the tree, `h n = 1`,
drops it.

Upstream cannot just split those patterns at quantity 0: a constant or a
type that unification put there is in the same place. A clause over
`List Integer` has `(::) {a = Integer} x xs`, and splitting `Integer`
leaves every other type unmatched. Telling the two apart needs the mark of
an argument a clause leaves to unification, which a constructor's implicit
lacks: upstream/53-constructor-implicit-mark.

## The fix

The change is upstream/53-constructor-implicit-mark's `pull-request.diff`
(after 50's and 52's), one diff for both: there is no fix of this bug
without the mark that one adds. Its part here is `getClauseType`'s rule
for a pattern on an erased argument at quantity 0, which reads what the
clause does with it (upstream/52's `Use`, from the pattern's `Source`): a
pattern the clause writes is split whatever its kind, as a constructor
already was. One unification fixed, the definitions' implicits and now
their constructors' (upstream/50, 53), and every part of one once the tree
splits it, keeps the old rule: split after what the clause writes
(upstream/52), and a variable unless it is a constructor. A type unification solved there
is the only one the argument's type allows, and splitting it leaves a
default branch the coverage check cannot match: splitting every pattern on
an erased argument at quantity 0 left base's `Control.App.Has`, whose `[]`
carries such a type, with no case covered; and reading the source off the
top of a column alone left the types inside a pair unification fixed to
read as written (`heads`, whose `All`'s implicit `x` is found to be the
clause's `(i, a)`, was reported not covering, as were six definitions of
the frontend that call its like). Above quantity 0, and in the run-time
tree, nothing changes.

Upstream test: `tests/idris2/coverage/coverage035`, in that diff,
`ErasedConstant.idr`: `h`, whose `h 5` must be 2 and `h 0` 1, `tp`, `pv`,
`len` over `List Integer`, which must stay covering and reduce `len [1, 2]`
to 2, and `heads`, which must stay covering and reduce in a type.

## Why there is no patch

There is no `idris.patch`. The Idris that elaborates what this compiler
consumes is the fork in compiler/idris, which carries the change as its own
code. The stock Idris only builds stage 0 (the fork, the frontend and the
test runner) and the benchmarks' Chez baseline, and nothing it builds
writes such a pattern: all of it checks at the pin.

## Testing at the pin

As upstream/53's, with the series: at the pin, the stock Idris reports
`coverage035`'s `h _`, `tp _` and `pv (MkP _)` unreachable and refuses
`hFive`, `tpString` and `pvFive`, and nothing else; the changed fork checks
it, printing exactly its `expected`, and checks `h 5 = 2` with `h _`
reachable (no warning). `heads` checks at the pin and with the series.
`tests/upstream/erased-constant-pattern` compiles through the changed
frontend, which the unchanged fork's refuses at `hFive`; its core prints
`Two`'s string, and its `expected` waits for a build of the whole
toolchain.

## Upstreaming plan

Status: carried as the fork's code; nothing goes to idris-lang/Idris2
from here. Idris accepts no contribution that arises from generative AI
or a coding agent, issues, pull requests, commits and comments alike
(upstream/README.md, **Idris**), and this report and the change were
written with one.

- upstream/53-constructor-implicit-mark's `pull-request.diff` records this
  change with that one, and with `coverage035`. At a re-sync of
  compiler/idris (compiler/idris/README.md), if upstream has fixed this bug
  its own way, the fork takes upstream's code and drops `getClauseType`'s
  rule at quantity 0; the mark stays with upstream/53 until that one is
  fixed too.
- When upstream's fix arrives: this directory,
  `tests/upstream/erased-constant-pattern` and the PINS.md entry go.
- Whether to report the bug upstream is Bjorn's call alone, in his own
  words and from his own understanding; nothing here is drafted for it.
