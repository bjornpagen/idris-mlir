<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: slow elaboration of linear Idris on the stock host

Written 2026-10-21 at e96bb991. **Resolved 2026-10-23** (L06h,
`idris-linear-check-addendum.md`): the case here is two bugs of the stock
Idris, both carried as patches. This module's own slow failure (a type
error in `recanonRow`) is what `upstream/109-delayed-retry-doubling`
fixes; the rest is not linearity but the size-change graph's comparison
doubling with each case block, `upstream/115-size-change-as-pattern-doubling`.
What follows is the record as it stood; §5's advice is struck.

Grounds: *measured* (command and input given), *read* (path:line),
*recalled*, *conjecture*. Tool: the stock `idris2 0.8.0-1c630e67c` on the
pinned Chez under `.toolchain/`, run as `idris2 --check`. Times are user
seconds from `/usr/bin/time -p`. The machine is an Apple M2 Max (virtual)
with 8 cores, and its load average was 8 to 10 from other agents. A run
that hit its timeout shows `user 0.00`, because the killed child was
never counted.

## 1. Nesting alone is cheap

- *measured* (`gen/gen.py` and `gen/run.sh`, which generate module `M`;
  inputs are in `runs/<variant>-<depth>/M.idr`): a lambda over a linear
  state, nested `d` deep. Each lambda is the continuation of
  `step : {0 s : Type} -> (1 st : s) -> ((1 _ : s) -> s) -> s` and
  matches the state with a constructor pattern.

  | variant | pattern | d=1 | d=4 | d=8 | d=16 |
  | --- | --- | --- | --- | --- | --- |
  | `pat` | `\(MkSt a b) =>` (linear fields) | 0.35 | 0.34 | 0.33 | 0.39 |
  | `nested` | `\(MkO x (MkSt a b)) =>` | | | 0.34 | 0.45 |

  An empty module takes about 0.3 s. So nesting constructor patterns in
  linear lambdas, even 16 deep, costs nothing measurable. The slowdown is
  not "nested patterns in lambdas" as such.
- *measured* (`red/R1.idr`, `red/R2.idr`): `recanonLeaves` from the
  prototype, cut down to a small `Machine` interface (`bind1`, `forUp`,
  `cond`, `load`, `store`), with the same linear `MkUL uf (MkLv ...)`
  patterns in nested lambdas under `L.do`. It checks in 0.49 s with
  three fields and 0.50 s with six. So `recanonLeaves` is not what failed
  to finish.

## 2. Bisecting the prototype's module

- *measured* (`proto/cutN/EG/Kernel.idr`: the first N lines of
  `/tmp/eg-machine-proto/idris/EG/Kernel.idr`, each cut at a top-level
  boundary):

  | cut | adds | user s |
  | --- | --- | --- |
  | 776 | everything up to `var` (the node section, flattened) | 5.59 |
  | 822 | `fromRS`, `mergeRow`, `dupRow`, `keepRow` | 5.72 |
  | 853 | `recanonRow` (lines 823 to 853) | over 120 (timeout) |
  | 872 | `finishT`, `recanonT` | over 300 (timeout) |

- So one 31-line definition, `recanonRow`, takes the module from 5.7 s to
  more than 120 s. A copy is in `red/recanonRow.idr`. It differs from the
  cheap cases in four ways (*read*, `Kernel.idr:823-853`):
  1. Its type has a linear `LPair (LPair src dst) st` inside `Got`.
  2. It matches on `Vals` list literals: `[out, unions]` in its own
     clause.
  3. It binds `(st :& res) <- cond {ts = [Cnt r, Bit]} ...` with two
     lambdas whose bodies call `dupRow` and `keepRow`, each taking 6 to 9
     arguments.
  4. It returns `pure1 (fromRS st :& res)`.
- The smallest reproducer has **not** been reached. The next steps would
  be to delete those four features one at a time from `recanonRow` and
  time each. The growth law (exponential or polynomial, and in what) has
  **not** been measured.

## 3. What Idris's source shows so far

Each of these is *read* at the pin, `third_party/Idris2/src`:

- `checkCase` checks a case's scrutinee at the unrestricted multiplicity.
  On `LinearMisuse` it checks it again at linear
  (`TTImp/Elab/Case.idr:390-401`). Only the scrutinee is checked twice,
  and the scrutinee of a pattern lambda is a variable, so this alone
  cannot explain the cost.
- Every case block is delayed (`delayElab`, `Case.idr:376`;
  `TTImp/Elab/Delayed.idr:115-133`), and is elaborated as a top-level
  function over the whole environment (`Case.idr:196-252`).
- The linearity checker re-checks a binder at linear after a
  `LinearMisuse` (`Core/LinearCheck.idr:227-233`). It caches each case
  function's argument usage behind `linearChecked`, so it is computed
  once (`LinearCheck.idr:575-584`). Neither re-checks a scope, so neither
  has an exponential path on its own.
- A bug, unrelated to the time: for an as-pattern, `updateHoleUsage`
  visits the as-name twice and the pattern never
  (`LinearCheck.idr:132-135`, `a` where `p` was meant).
- *conjecture*, unverified: the cost comes from ambiguity resolution
  nested under delayed case blocks. `[]` and `(::)` name both the
  Prelude's `List` and the prototype's `Vals`, and `#` names both
  `LPair`'s and `Res`'s constructor. `recanonRow` has both in a clause
  pattern, in a `{ts = ...}` argument and in the results of `cond`'s
  lambdas. If each alternative re-elaborates a delayed case body that
  holds further ambiguous names, the cost doubles at each level. The
  prototype's own note says ambiguity accounted for part of the earlier
  184 s. The next step would be to rename `Vals`'s constructors in a copy
  and time `cut853` again.
- The fork's copies (*read*, `diff` against the pin):
  `Core/LinearCheck.idr` differs in 2 lines, `TTImp/Elab/Case.idr` in
  108 and `TTImp/Elab/Delayed.idr` in 135. Whether those differences
  touch this path was not read.

## 4. Not done

- Upstream's issue tracker and commits were not searched, so it is not
  known whether the pin already carries a fix.
- No fix, no patch, no `upstream/<bug>/` contents, no `PINS.md` line.

## 5. Struck (2026-10-23)

The advice that stood here, shapes our libraries should avoid, is
withdrawn: measured, none of them is a cause (the addendum), and both
bugs are patched upstream of our code (D121).
