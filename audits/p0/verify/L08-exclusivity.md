<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Lane L08: exclusivity, the in-place promise, borrows

**Scope:** D24, C1 (borrows), D26, D10, D19, D39 (views), as they bear on
exclusivity, the in-place promise and borrow inference. **HEAD:**
`e96bb991` at start (2026-10-21T21:30Z) and at finish (re-checked; no
anchor moved). Nothing built or run; every cost is *read*, *conjecture* or
a measurement written out to be taken. Ground markers as in
`proposals/README.md`.

**Read for this file:** the representation-first skill; AGENTS.md; the
proposal whole (§0 to §9); 07 whole; 08 §6; synthesis B (the markings, §1
to §8) and C (whole); §5.10 (borrowing: A4 to A6, B2 to B5, G1 to G5, M1
to M7, Q1 to Q3); `design/match-and-counting.md` §2, §4, §7;
`tests/uniqueness-shared-rebuild` (and `near/`); `tests/leet-relink-in-place`;
`foreign/idr/lib/Analysis/Ownership/{Exclusivity,ExclusivityAnalyses,ExclusivityGraph,Borrows}.cpp`;
`foreign/idr/lib/Transforms/Demand/Demand.cpp`;
`foreign/idr/lib/Transforms/Ownership/{Specialize,Exclusive,Signatures,Share,Commit}.cpp`
and the parts of `Grades.cpp`, `Reuses.cpp`, `Stack.cpp` cited;
`foreign/idr/lib/Transforms/Pipeline.cpp`; `lib/IR/{OpsCon,Constants,Grades,Types,OpsMatch}.cpp`;
`include/idr/IR/{IdrOps,IdrOwnershipOps,IdrBase}.td`; `Passes.td:530-640`;
`lib/Transforms/Optimize/Contify.cpp:1-45`;
`compiler/src/IdrisMLIR/Registry/{Entry,Recognized}.idr` (`InPlaceType`),
`Term.idr:90-130`, `Frontend/Translate/Types.idr:800-820`,
`Emit/{Operations,Bodies}.idr` (the parts cited); `libs/mlir-linear/` whole;
pinned `UBOps.td:73`, `ControlFlowInterfaces.td:638-640`.

---

## 1. Verification

Each item: verdict, evidence, and the class of each observation
(*defect*: confirmed in the source; *incomplete*: structural
incompleteness; *mismatch*: integration mismatch; *unverified*:
behaviour not checked by running; *simplification*: optional).

### 1.1 D24, the in-place promise

**D24.1** "A type of kind `in_place` (today `Linear.List.LList`,
`Linear.Nat.LNat`, by the registry's `InPlaceType`) promises its values
are rebuilt in place with no run-time test." **Holds.** The registry
names exactly two families (`Registry/Recognized.idr:183-186`), as a
hook of kind *stricter*, one that may only add refusals
(`Entry.idr:258-260, 343`); the frontend turns it into the sum's shape
(`Frontend/Translate/Types.idr:814`, `Term.idr:106`) and Emit into the
body's kind (`Emit/Index.idr:72`; `SumKind::InPlace`,
`Syntax/Idr.idr:362`), which `Demand.cpp:54-57` reads. *Read.*

**D24.2** "A function that takes apart a quantity-1 parameter of such a
type and builds a value of that type from it rebuilds it; that is decided
from the program as the frontend wrote it." **Holds with a correction**
(*incomplete*, four ways):
1. *The frontend writes the take and the build in two functions.* Idris
   lifts every `case` and `if` on a clause's right-hand side into a case
   block, a function of its own (`Contify.cpp:15-25`; the frontend keys
   them by parent, `Frontend/Translate/Keys.idr:66`,
   `State.idr:123`). In `tests/leet-relink-in-place/Main.idr:43`
   (`splitRev k (x :: xs) acc = if k <= 0 then ... else splitRev (k - 1) xs (x :: acc)`)
   and `:77` (`drop'`) the parent takes the parameter apart and the case
   block builds the new cell. Read literally on the program as written,
   neither function "takes apart and builds", so neither is promised.
   Today the promise appears only because idr-contify, which calls itself
   an optimization ("a move this run does not make ... only leaves the
   program less optimized", `Contify.cpp:38-42`), merged the two before
   idr-demand looked. A case block on no cycle with its parent is left to
   the inliner's cap (`Contify.cpp:22-25`), so for a non-recursive
   rebuild under an `if` the promise exists only when the case block is
   small enough to inline. *Read.*
2. *A forwarding function is under no promise.* `Linear.List.reverse xs =
   reverseOnto [] xs` (`libs/mlir-linear/Linear/List.idr:36-37`) takes
   nothing apart, so its callers owe nothing by the literal rule; a user
   who passes a shared list to `reverse` is refused at the library's own
   call (`List.idr:37`), or at wherever inlining leaves that call
   (`Demand.cpp:127-135` reports a call with no dup when no call has
   one). *Read* the mechanism; which site the user sees depends on the
   inliner (*conjecture* on its decision).
3. *"Of that type" and "builds" are not exact.* An instance (`LList a`)
   against its family (`LList`), erased indices, a constructor with no
   cell (`Nil`, `Zero` are atoms), and a construction after the match
   rejoins (where the cell's token cannot follow, since the empty
   constructor gives none) are all undecided by the sentence. §2.1 fixes
   each.
4. *"Quantity 1" must be Idris's.* Emit demotes a linear binder its body
   uses twice to a plain one (`Emit/Bodies.idr:131-138`, 17 FB-28), so
   reading the quantity off the IR's type (`Demand.cpp:70`,
   `isLinear(param.getType())`) can miss a parameter Idris checked at 1.
   *Read.*

**D24.3** "*The three quantities*: ... exclusivity (`!idr.excl<T>`,
proved) is the obligation at every call." **Holds with a correction**
(*defect* of strength, for the owner, Q1). `!idr.excl<T>` means the value
holds the only reference to *every* cell of its cell graph
(`Exclusivity.cpp:3-9`); a construction is exclusive only if every
followed field is (`ExclusivityAnalyses.cpp:133-142, 186`). A rebuild
takes apart only the family's own cells, down its recursive fields; the
elements move as fields, with no count touched. So a list whose spine is
fresh but whose boxed elements are shared (`reverse (rep n (Just k))`,
where `rep n x = x :: rep (n - 1) x` shares `x` into every cell) is
refused, though its spine can be rebuilt in place with no test. *Read*
path; the program was not run.

**D24.4** "*Counting honours it*: reuse must recycle the rebuilt cell,
the stack inference may not take that parameter, and no placement may
add a dup of it." **Holds as the obligation; the mechanism is
incomplete** (*incomplete*). Today nothing holds any of the three:
idr-rc-stack frames parameters (`Stack.cpp:344-353`), reuse pairs by size
on a predicted death point (`Reuses.cpp:186-200`), placement's
`sinkConsumers` decides a dup (08 §6.1 NQ1). Under the design two of the
three become unwritable by the grade alone: an exclusive value of the
frame is no grade (`Types.cpp:344-345`), and a second use of a quantity-1
value, which a dup implies, is a verifier error (`Verify/Linearity.cpp:1-6`).
The third has no representation: §5.5 holds only "which
parameters a function rebuilds ... in the function's type", so the reuse
walk must find the construction again, and it cannot when the
construction is in another function (a case block, item D24.2.1; under
D32, a frame's continuation, since idr-frames runs before counting,
`Pipeline.cpp:125-128`) or when an earlier construction of the same
layout takes the token first. I-2 makes the pairing data.

**D24.5** "*The refusal*: a call the exclusivity analysis cannot prove
exclusive is `unsupported (uniqueness)` at the call, the analysis exact
against the rule." **Refuted as placed** (*mismatch* and *defect*). The
exclusivity analysis runs on the owned stage (`Pipeline.cpp:44-47`), after
idr-contify, idr-optimize, canonicalization and CSE twice, idr-accumulate,
idr-frames and placement (`Pipeline.cpp:77-128`). Every one of these may
change whether an obligation's argument is shared, so the caller half of
the promise is decided on the optimizer's output:
- the inliner's cap decides whether a case-block rebuild is promised at
  all (D24.2.1);
- deleting an unused total call (`let _ = lenT xs in bump xs`, which D13
  licenses) removes the second use and turns a refusal into an
  acceptance (*conjecture* that the canonicalizer deletes it today; the
  licence is D13's);
- borrow inference decides whether an earlier read dups: under C1 a
  parameter is borrowed "only when at every call the caller uses the
  argument afterwards", so `let n = countW xs in bump xs` is accepted or
  refused according to whether some *other* call of `countW` elsewhere in
  the program passes a value at its last use (*read* C1's text;
  `Borrows.cpp:7-27` has no such condition today);
- forming a join point "can only raise exclusivity" (match-and-counting
  §7, the in-place bullet);
- skipping a `ReuseAction`, framing the parameter, or `sinkConsumers`'
  dup (08 §6.1 NQ1).
And the analysis is not exact on its own terms: a crash case shares its
match's results and every case's arguments (G-09, 1.6 below), which
refuses a partial rebuilder applied twice. I-1 moves the decision ahead
of every optimization; I-4 fixes G-09.

**D24.6** "a test pins the rule's boundary
(`tests/uniqueness-shared-rebuild` and its `near/`)." **Holds in part**
(*incomplete*). The test pins one point: an unrestricted `let` used twice
(refused at the rebuilder's call, `Main.idr:30`) against one used once
(`near/Main.idr`). It is the only test that expects `uniqueness`
(*measured*: `grep -rl uniqueness tests --include=expected`). The
boundary has about twenty more points (§2.1's table); the ones that
discriminate the corrections are B5, B6, B7, B10, B11 and B13.

**D24.7** "*Deleted*: `idr-demand` deriving the promise from
`idr.cell.recycle` and the take's token (`Demand.cpp`'s `rebuilt`)."
**Holds, and more goes.** `rebuilt` (`Demand.cpp:59-77`) reads reuse's
output; once the rule is read before the optimizer (I-1) the whole pass
goes: its name-keyed map of promised callees (`:104-107`, a
`DenseMap<StringAttr, ...>`, a string standing for a function), its walk
of every call (`:112-126`), and the reporting heuristic that shows only
the calls with a dup when one exists (`:127-135`), which exists because
the late analysis joins a parameter over all callers and so marks every
call inside a rebuilder broken too. *Read.*

**The refusal today** (site and message): `idr::refuse(call,
Rule::Uniqueness)` with "@caller passes a shared T to @callee, which
rebuilds it in place" and a note "shared here" at the dup
(`Demand.cpp:89-97`). The rule's category is *outside the language*
(`IdrBase.td:224-226`), which AGENTS.md's list of acceptance analyses
names ("a library's in-place promise exclusivity cannot meet"). Holds as
a category; the site is the optimized IR's and the names are MLIR
symbols (`@Main.main`), I-3.

### 1.2 C1, borrows (the coordinator's; open to challenge)

**C1.a** "a parameter is borrowed only when at every call the caller uses
the argument afterwards or its type bounds everything it reaches, and the
callee neither consumes nor stores it." **Holds with a correction**
(*incomplete*). It misses the derived view: a value read from a borrowed
parameter, whose owner an active caller keeps alive (Lean's derived
borrows, §5.10 B3; OSSA's guaranteed projection, §5.10 C1). Read
literally, every recursive read-only traversal passes its own field at
that field's last use (`depth (Node l r) = 1 + max (depth l) (depth r)`:
`l` is last used by its call), so `depth`'s parameter can never be
borrowed, and a caller that keeps the tree pays an increment and a
decrement per node at run time for a fact (the caller keeps it) known
statically: D10. (A self call idr-accumulate turns into a loop meets the
join-parameter rule instead; two calls under `max` are not accumulated.) match-and-counting §7 already states the
rule for join parameters ("every jump passes a view whose owner outlives
the join op"); functions need the same. I-6.

**C1.b** "a parameter D24 rebuilds is owned." **Holds; redundant**
(*simplification*). A rebuilt parameter has quantity 1, and every
quantity-1 parameter is owned by its type (`Borrows.cpp:22-25, 83-84`,
"Idris proved the function uses it once"); under I-1 its grade in the
signature says so. One fact, one place: state it as a consequence.

**C1.c** "Users declare nothing: Idris has no borrow annotation"; "A
runtime function's conventions come from the Idris specification."
**Holds** (design; no code to read).

**C1.d** "*Drops first, then reuse guided by them* ... The in-place
promise (D24) is read before placement and makes its rebuild an
obligation of this walk." **Holds with a correction** (*incomplete*):
the walk pairs a token with the first construction of the same layout on
the path (§5.10 A4); it cannot honour a rebuild in another function, and
a different construction of equal layout may take the promised token
first. The pairing must exist before the walk (I-2), so the walk never
sees a promised token.

**C1.e** "*Deleted*: ... Borrows' forced-owned reason taken from reuse
sites (`Borrows.cpp:179-181`)." **Holds with a correction.** Under
drop-guided reuse after placement there are no reuse sites when borrows
are inferred. Deleting the reason loses nothing where C1 borrows because
the caller uses the argument afterwards (the cell is then shared, and a
take in the callee could not reuse it anyway). It loses a reuse where
C1's bounded-type clause borrows a parameter the callee takes apart and
rebuilds at equal layout (a two-word cell passed at its last use). The
replacement is a fact of the program, not of reuse: a parameter the
callee takes apart and rebuilds (the rebuild site of §2.1, any family)
is owned. *Read* `Borrows.cpp:179-181`, `Reuses.cpp:193-195`.

**C1.f** "*Reason*: ... ours is Lean's, with reuse sites predicted before
placement by guessing that any call takes its arguments over
(`Reuses.cpp:193-195`) and simulated." **Holds.** *Read*
`Reuses.cpp:186-200` (`takesOver` is "any call, or a consuming use").

### 1.3 D26, frame-limited (as it bears on borrows and tokens)

**D26.a** "*A call may hold*: reuse tokens of statically sized cells
awaiting their construction." **Holds**, and it is what lets the rebuild
token of I-2 cross a call, a frame (D31: "reuse tokens carried in it") or
a join point.

**D26.b** "*Never*: ... a borrowed argument whose last use is the call,
unless its type bounds everything it reaches (so an argument whose binder
in the caller is linear is passed owned, read off its type)." **Holds
with a correction** (*defect* of wording, owner Q2). Read literally it
forbids every derived borrow (C1.a), which the promise itself allows:
"each call holds at most a fixed number of bytes it no longer needs", and
the bytes a derived view reaches are needed by the active caller that
owns them. The parenthetical holds: a linear binder's one use is its last,
and `Borrows.cpp:83-84` already owns every quantity-1 parameter.

**D26.c** "*Not carried over*: ... the run-time uniqueness test as part
of space." **Holds**: the promise in my area is about count tests, not
space.

### 1.4 D10, no static fact paid at run time (in my area)

**Holds as the ban; violated today** (*defect*, each):
- *At run time*: a call exclusive at some but not all followed parameters
  goes to the original and pays the count test for the exclusive ones,
  because a copy's key is "every followed parameter exclusive"
  (`Specialize.cpp:3-11, 51-57`), I-5; G-09's shared crash case puts a
  test in every memo force and partial function (I-4); read-only
  recursion pays a count pair per element (C1.a, I-6).
- *When the compiler runs*: idr-demand recomputes, after counting, a fact
  the frontend held (the kind and the quantity, `Demand.cpp:54-77`) and
  keys it by name (`:104-115`); exclusivity is solved twice per pass
  (`Exclusive.cpp:39-46`) and its graph rebuilt per memo stratum
  (07 A-01, E-01); Borrows redoes a symbol lookup, a parent walk, a cycle
  query and two tail-position walks on every revisit of a call
  (`Borrows.cpp:232-237`, 07 B-07), which D30's tail fact on the call
  deletes.

### 1.5 D19, regions, join points, blocks only at the lowering (in my area)

**D19.a** "Regions keep the scopes ... the in-place promise ... read."
**Holds**: a rebuild's scope is the case region of the match that takes
the cell (§2.1 R1).

**D19.b** join points "jumped to with typed arguments (grades and reuse
tokens among them)". **Holds as design**; a rebuild in a join region
needs its token as a jump argument, which I-2 makes an SSA value from
the start, so contification moving the construction into a join region
cannot lose it.

**D19.c** (match-and-counting §2's table) "a crash arm jumps nowhere, so
07 D1's precision loss cannot arise." **Holds with a correction**: only
if the extractor classifies a terminator as a dead end by interface, and
counts D25's breaking control flow (`idr.jump`) as an edge. Under
regions alone G-09 stands today, and a dead-end rule written as "neither
a region-branch terminator nor a branch" (07 D1) becomes unsound the day
`idr.jump` exists, since a jump's operands would flow nowhere and its
join parameters could be marked exclusive. I-4 states the classification.

### 1.6 Exclusivity, against the rule (the late solve)

**G-09 holds** (*defect*; path *read*, effect *conjecture*): a case region
whose terminator is not a region-branch terminator (`ub.unreachable`,
which ends every crash case: `OpsMatch.cpp:25-36`, `Emit/Bodies.idr:571-585`;
`UBOps.td:73`, `Terminator` only) is put in `unknownFrom` of *every*
successor of its match (`ExclusivityGraph.cpp:208-216, 222`); when its
block is live, every input of every successor is shared
(`ExclusivityAnalyses.cpp:234-243`). Counterexample: `partial bump1 :
LList (!* Int) -@ LList (!* Int); bump1 (MkBang x :: xs) = MkBang (x + 1)
:: xs`, then `sumL 0 (bump1 (bump1 (build n [])))`. The inner match's
missing `Nil` case is a crash; its result is shared; `bump1`'s result is
not exclusive; the outer call is refused `unsupported (uniqueness)`
though every cell is fresh. The rule (§2.1 R3.P5: a crash case gives
nothing) accepts it.

**Every other precision loss of the late solve**, each with its fix (the
late solve decides no refusal after I-1, so each costs a run-time test,
a D10 debt):

| # | loss | where (*read*) | essential? | fix |
| --- | --- | --- | --- | --- |
| X1 | crash case shares its match (G-09) | `ExclusivityGraph.cpp:208-222` | no | I-4 |
| X2 | a parameter joins all callers; a copy only for "every followed parameter exclusive" | `Specialize.cpp:51-57` | no | I-5: context by mask |
| X3 | values marked shared through a copy a call later left keep their mark ("may be less precise than one solved afresh") | `Exclusivity.cpp:37-43` | no | I-5: re-mark with targets fixed until they stop moving; masks only shrink, so it ends |
| X4 | entry arguments of a region op with no region-branch interface are shared | `ExclusivityAnalyses.cpp:301-308` | no | the op declares its region inputs (its flow edges, lanes L01/L13) |
| X5 | block arguments reached from a terminator with no branch interface are shared | `ExclusivityAnalyses.cpp:281-286` | no | the same classification as X1 (I-4) |
| X6 | the result of an op that declares no flow is shared | `ExclusivityAnalyses.cpp:153-154, 186` | no | every op declares flow in its specification (L01) |
| X7 | an element's dup taints its container | `Share.cpp:27-47` | yes under whole-graph `excl`; no under Q1's spine reading | Q1 |
| X8 | a memo capture is shared when any init of its label stores a shared value | `ExclusivityAnalyses.cpp:195-210, 259-268` | yes (one fact per constructor field, as MLton's) | none |
| X9 | the root's parameters, constants with cells, frame cells, `idr.share` results are shared | `ExclusivityAnalyses.cpp:91-103, 180-183`; `Exclusivity.cpp:22-30` | yes | none |
| X10 | a result is exclusive only if every reached return is, whatever the call's arguments | `Signatures.cpp:55-66` | no | I-5: per context |

### 1.7 The three markings as one template (§5.5; synthesis B §2.9, C §2 item 10)

**Holds with a correction.** The template is right for the shape (a
monotone two-point mark per node, a node that rises walks its row once,
O(V + E)), and b8301ebe's engine is the nearest start (`Stack.cpp:197-208,
262-268`). Corrections: there are four clients, not three (I-1's
obligation closure is a plain backward marking); exclusivity is two-point
only once `Unknown` becomes a reach gate (07 O-21); its gates are
function run bits, memo-label made bits and a per-call target that, under
masks, moves monotonically down a finite lattice of masks (at most one
move per followed parameter), not a single switch; its made-label stratum
is two calls of the template, the second seeded from the first's frozen
answer (07 D2); and its final run set is one more call, over the call
graph under the final targets (07 E-03). §2.4 states the shape.

### 1.8 D39, views (in my area)

**D39.a** "*Views first*: borrowed parameters and results." **Holds with
a correction** (*incomplete*, seam with L05). Borrow inference (C1) and
lifetime inference (D39) decide one fact: a parameter is owned, or a view
at a lifetime parameter of its function. Two inferences writing one
signature field would be two copies; they must be one marking that writes
the view's lifetime. Under D39 a derived view is a view at the caller's
lifetime variable, so C1.a's correction becomes checkable by types: an
argument whose lifetime outlives the call holds nothing past its last use
(I-6).

**D39.b** "a result can live in its argument's scope (a recursive
`lookup` returns a view of the tree, counted nothing)". **Holds as
design.** For the in-place rule a view taken of a value is a use of it,
so `let v = lookup t k in rebuildT t` is refused (§2.1 B10's reasoning),
consistent with I-1's "every evaluated use counts".

### 1.9 C3, as it bears on the promise

"`con` ... of an unrestricted value are pure (two equal ones merge ...),
a linear or owned result takes a fresh identity." **Holds for today's
in-place families, by their declaration, not by construction.** Both
declare every field linear (`(::) : a -@ LList a -@ LList a`,
`List.idr:15`; `Succ : LNat -@ LNat`, `Nat.idr:14`), so Emit enters every
field operand linearly (`Emit/Operations.idr:309-312, 143-155`); an
`idr.lin.enter` result carries `MemAlloc<Idr_LinResource>`
(`IdrOwnershipOps.td:403-413`), so no two merge, and a constructor whose
fields are not constants never folds (`OpsCon.cpp:108-120`; a constant
must be unrestricted, `Constants.cpp:122-124`). So `bump [MkBang 1,
MkBang 2]` stays a fresh construction today (*read*). An in-place family
with an unrestricted field would lose its cells' identity to the
constant fold before the late solve, a refusal an optimization adds.
Under I-1 no extra check is needed: the check runs before any fold, and
every construction on an obligation chain is graded exclusive, which no
constant can hold (`Constants.cpp:122-124`: owned grades are refused)
and which C3's own clause gives a fresh identity (an owned result is
never merged). A registry precondition on field quantities would be a
second copy of that guarantee; none is proposed.

### 1.10 The three "Delete (verify)" items

- `Demand.cpp`'s `rebuilt` from `cell.recycle`: **holds** (D24.7).
- exclusivity's `unknownFrom` and its share: **holds**, with D19.c's
  condition (I-4).
- Borrows' forced-owned reason from reuse sites: **holds with the
  replacement of C1.e** (I-6).

---

## 2. Boundaries

### 2.1 The rule, exact

**R0. Where it is read.** On the first-order program right after
defunctionalization and the knot check, both acceptance steps, before any
optimization (`Pipeline.cpp:71-77`: before idr-effects, idr-contify,
idr-optimize). Deduplication before it merges only functions whose bodies
are equal, so it changes no use and no rebuild. Idris's case and with
blocks are written in place in their parent by the frontend (seam L16;
synthesis C step 5, tail-Q4), so "a function" is the function the user
wrote. Every closure is a constructor and every application a direct
call of its dispatch.

**R1. Terms.**
- *In-place family*: a family the registry marks `InPlaceType`. Its
  cells are one family's whatever its type parameters and erased indices
  (quantity 0: no value, so never read).
- *Cell constructor*: a constructor with a field, whose layout is a cell
  (D48's layout). `Nil` and `Zero` are atoms and are never rebuilt.
- *Taken cell*: in the case region of a cell constructor of a match whose
  scrutinee is a value of an in-place family, that value's cell; and,
  inside it, the cell of a field of the same family taken apart by a
  nested match.
- *Rebuild site*: a taken cell and a construction of a cell constructor of
  the same family, of equal layout, inside the taken cell's case region
  at any depth (through jumps to join points local to the function),
  with no rejoin of that match in between. Each taken cell pairs with at
  most one construction and each construction with one cell: in the case
  region's pre-order, outer cells first. A construction of the cell's own
  fields in order is the cell itself (record eta: no write).
- *Rebuilt parameter* (D24): a parameter of quantity 1 in Idris's checked
  signature (not the IR's held form, D24.2.4), of an in-place family,
  whose cell (seen through the ops that hand a value on as itself:
  `idr.lin.enter`, `idr.lin.use`, the default region's rebinding) is the
  taken cell of a rebuild site.

**R2. Obligation positions.** The least set of parameters holding every
rebuilt parameter, and every parameter `q` (of any quantity) of a
function that, on some path, passes `q` or a field taken out of `q` to an
obligation position (an argument at a parameter of the set). A refusal
never lands inside a forwarder: the requirement moves to its callers.

**R3. Exclusive at an obligation position.** The argument `v` is
exclusive when
- **U** (used once) on every path through the call, the call is `v`'s
  only use: Idris's quantity 1 gives it for a linear binder; for an
  unrestricted one it is the per-path count Emit already makes on Core
  (`mostUses`, `Emit/Bodies.idr:51-75`), on SSA no second use outside a
  region that excludes the call's; every use the program evaluates
  counts, a read by a callee that would borrow included (I-1); and
- one of, recursively:
  - **P1** `v` is an obligation parameter of its own function (its callers
    discharge it);
  - **P2** `v` is a construction, made anew each time it is evaluated
    (eager evaluation), each field of which is exclusive by R3 or holds
    no cell (D24 as worded; under Q1's reading, each field *of the same
    family*);
  - **P3** `v` is a call's result, every reachable return of the callee
    gives a value exclusive by R3 read in the callee with its parameters
    in a set `S` taken as exclusive, and this call's arguments at `S` are
    exclusive by R3; a path ending in a crash, `exit` or `ub.unreachable`
    gives nothing;
  - **P4** `v` is a field bound by a case of a match whose scrutinee is
    exclusive by R3 and whose only use on the path is the match;
  - **P5** `v` is a match's result, and each case that yields gives an
    exclusive value; a case that ends in a crash gives nothing.
- *Never*: an element read from an array, a memo cell's value, a forced
  suspension's value (the suspension keeps it), a value made by an op
  that declares no flow. A closure's capture is P4 on the closure's
  constructor.

**R4. The refusal.** At each obligation position whose argument fails R3
and is not in R2 (the requirement cannot move into the enclosing
function), the program is refused, once per cause: `unsupported
(uniqueness)`, at that call's Idris source location, naming the caller,
the callee and the in-place family as the user wrote them, with one note
at the cause: the other use on the path (its location), the callee whose
return is not exclusive (that return's location), or the read (array,
memo, suspension).

**Boundary cases** (each a test; "today" is *read*, never run):

| # | program (sketch) | rule | today | discriminates |
| --- | --- | --- | --- | --- |
| B1 | `let xs = build ...; bump xs; sumL 0 xs` | refused at `bump xs`, note at `sumL 0 xs` | refused | existing test |
| B2 | the same, `xs` used once | accepted | accepted | existing `near/` |
| B3 | `let 1 xs = MkBang n :: [] in bump xs`, `n` read at run time | accepted by types alone (P2, U by quantity) | accepted | QTT path |
| B4 | `bump [MkBang 1, MkBang 2]` | accepted (P2) | accepted (linear fields keep it out of static data, 1.9) | I-1 (a graded construction never folds) |
| B5 | `reverse xs` then `xs` again | refused at the user's `reverse xs` | refused inside `List.idr:37` or where inlining leaves it | I-3 |
| B6 | `bump1 (bump1 (build n []))`, `bump1` partial | accepted (P5: the crash gives nothing) | refused (G-09) | I-4 |
| B7 | a rebuild under an `if` on the right-hand side, a shared caller | refused | refused only if contify or the inliner merged the case block | I-1, L16 |
| B8 | a top-level definition of an `LList` referenced twice, each passed to `bump` | accepted if each reference is a call that builds anew (P3) | accepted | *conjecture* on the frontend's translation of a definition of no argument |
| B9 | two equal literal lists, one to `bump`, one to `sumL` | accepted | accepted (fresh identities, 1.9) | I-1 |
| B10 | `let n = countW xs in bump xs`, `countW` an unrestricted read-only function | refused (every evaluated use counts) | accepted (Borrows has no frame limit); under C1, depends on `countW`'s other callers | I-1 |
| B11 | `let _ = lenT xs in bump xs`, `lenT` total, result unused | refused | accepted when the dead call is deleted (*conjecture*) | I-1 |
| B12 | `wrapW : LList a -> LList a; wrapW xs = bump xs`, a shared caller | refused at the caller's `wrapW xs` | refused inside `wrapW` | I-3 |
| B13 | a fresh spine with shared boxed elements, to `reverse` | refused (D24 as worded) / accepted (Q1's reading) | refused | Q1 |
| B14 | a rebuild after a non-tail recursive call on a cycle (`g (x :: xs) = x :: rev (g xs) []`) | promised; the token crosses the frame | reused (idr-frames takes no plain recursion yet); under D32 the build moves into the frame's continuation, away from the take | I-2, L10 |
| B15 | `f (x :: y :: zs) = y :: x :: f zs` | two rebuild sites, both cells reused | first-fit by size | I-2 |
| B16 | `mapL : (a -@ b) -> LList a -@ LList b` with equal layouts | rebuilt (same family, equal layout) | rebuilt if reuse paired it | reading of "that type" |
| B17 | `f (x :: xs) = x :: xs` | the cell itself (eta), no write | folded by `ConOp::fold`'s eta | — |
| B18 | a construction after the match rejoins | not a rebuild (no token crosses a rejoin the empty case reaches) | not promised | — |
| B19 | a linear `Box` parameter holding an `LList`, both rebuilt | the inner cell under no promise (D24 as worded) | not promised | Q3 |
| B20 | a trusted library uses a rebuilt parameter twice | refused inside the library (the library's error) | not promised (Emit demoted it) | L16 (FB-28) |

### 2.2 The end state (names and shapes)

- **Registry.** `InPlaceType` (`Entry.idr:258-260`), kind *stricter*,
  unchanged. Its one reader turns it into the family's kind, a field of
  the family attribute (`#idr.family<... in_place ...>`, seam L04).
- **Grade.** The obligation is the grade on the parameter in its
  function's type: `!idr.q<1, excl, T>` (linear and exclusive), or the
  permission Q1 recommends for the family's own cells. Admitted from the
  in-place check on (today `excl` exists only from the owned stage; seam
  L05, L03's stage table). Values on a proven chain carry it too.
- **Ops.** `idr.take` admitted from the in-place check on, on an
  exclusive refined scrutinee (03 §5.2a's `!idr.ctor<T, @C>`), giving the
  cell's token and the fields; `idr.rebuild %token @C(fields)` (new, a
  value op): consumes a token of equal layout and builds the constructor
  value, a fresh identity, never merged, never folded. Counting lowers
  them to `idr.take` and `idr.cell.recycle` + `idr.cell.init`. The token
  type is keyed by layout (match-and-counting §2: `!idr.token<n>`), with
  the source constructor kept for reuse specialization (seam L04).
- **Pass `idr-in-place`** (role *check*), after idr-knots, before
  idr-effects: computes rebuild sites, R2's closure, R3 with P3's
  summaries, refuses per R4, and writes the grades, the takes and the
  rebuilds. It replaces idr-demand.
- **Late exclusivity.** A cached program analysis (`Exclusivity`, 07 D2)
  with contexts by mask (I-5); `idr-rc-commit` nested, reading it with
  `getCachedParentAnalysis`. It decides no refusal and gives no node to a
  value already graded exclusive.
- **Borrows.** One marking writing each parameter's grade: owned, or a
  view at a lifetime parameter (D39), with I-6's rules.
- **Rule::Uniqueness** (`IdrBase.td:226`, category *outside the
  language*), generated from the specification (D50), emitted by
  idr-in-place alone.

### 2.3 Invariants

1. A value graded exclusive is used at most once on every path, is never
   dup'd, never of the frame (`Types.cpp:344-345`), never a constant
   (`Constants.cpp:122-124`); forgetting exclusivity is `idr.share`, the
   one way down.
2. A token is linear: consumed exactly once, by an `idr.rebuild` of equal
   layout, or freed; a rebuild that loses its cell is a verifier error.
3. Every call passes each obligation parameter a value graded exclusive
   (the call's operand types equal the callee's parameter types).
4. A function's rebuilt parameters are its function type's; no table,
   no name-keyed map, holds them.
5. A pass that would break 1 to 3 is a compiler bug (an internal error at
   the verifier after it), never a refusal (D24).
6. Every terminator the late solve's extractor meets is a region-branch
   terminator, a branch, a breaking jump (D25), a return, or a dead end
   with no successor; any other is an internal error naming the op.

### 2.4 The markings' template

```
template <Graph G, GatePolicy<G> Gates = NoGate>
BitVector mark(const G &graph, Seeds<G> seeds, Gates gates = {});
```
Direction is the graph view's type (`Forward<G>`, `Backward<G>`), never a
`bool` (08 C-51). Clients: the obligation closure (backward, no gate),
Borrows (backward, no gate), idr-rc-stack (no gate), exclusivity
(forward; gates: run bit per function, made bit per memo label, target
per call by mask). One explicit instantiation each (§5.2). Owned by
L14; consumed here.

### 2.5 Constructor provenance

| fact | constructed by | who alone may | consumers |
| --- | --- | --- | --- |
| a family is in place | the registry entry (`Recognized.idr:183-186`), read once by the frontend (`Types.idr:814`) into the family's kind | the registry | idr-in-place |
| a parameter has quantity 1 | Idris's checked signature, emitted faithfully as `!idr.lin` | Emit (FB-28 fixed, L16) | idr-in-place, Borrows, the linearity verifier |
| a rebuild site (which construction rebuilds which cell) | idr-in-place, as `idr.take` + `idr.rebuild` | idr-in-place | counting (lowers), frames and join points (carry the token), the verifier |
| a parameter is an obligation | idr-in-place, as the grade in the function type | idr-in-place | every pass (keeps it), counting (no test, no frame, no dup), Borrows and the late solve (no node) |
| a value is exclusive | idr-in-place (proved, on obligation chains); the late solve (inferred, monotone, elsewhere) | those two; any other pass only keeps it or shares it | counting's take and recycle, the lowering |
| a grade copy | idr-in-place (for P3) and the late solve, in one key space (function, mask), named from the key | those two | symbol-dce |
| a refusal of uniqueness | idr-in-place | idr-in-place | the harness (status, the rule's phrase) |
| a parameter is borrowed (a view at a lifetime) | the Borrows marking | Borrows | placement (L07), the verifier |
| a terminator is a dead end | its interfaces (upstream's, D25's) | upstream and the specification | the late solve's extractor |

### 2.6 Consumers, error and cleanup paths

- idr-in-place refuses and stops (status per D37's table for a refusal;
  the harness reads the rule, not text). It makes no partial rewrite:
  rewrites happen only once every check passed.
- Counting meets a token: lowers it; an `idr.rebuild` whose token it
  cannot reach is an internal error (I-2's verifier makes it
  unrepresentable before that).
- The commit meets an owned value where the solve proved exclusive on an
  unreached path: ends the path (`Commit.cpp:47-55, 58-72`), unchanged.
- A mask copy no call keeps is symbol-dce's (`Pipeline.cpp:49`).

### 2.7 What it deletes

- `foreign/idr/lib/Transforms/Demand/Demand.cpp` whole; `include/idr/Transforms/Demand.h`;
  `IdrDemand` (`Passes.td:612-626`, generated from the specification);
  `createIdrDemand` (`Pipeline.cpp:130`).
- `SuccessorSources::unknownFrom` (`ExclusivityDetail.h:139-144`),
  `ExclusivityGraph.cpp:208-216, 222`, `ExclusivityAnalyses.cpp:234-243`.
- `givesExclusive`, `copyable` and the key closure (`Specialize.cpp:51-69,
  92-117`); the second solve and the hand pass manager
  (`Exclusive.cpp:39-54`).
- In Borrows: the reading of `Reuses` (`Borrows.cpp:179-181`), the
  `DataFlowSolver`, `HoldingState`, `Inference`, the `Holding`-to-`Param`
  switch (07 D3's list); C1's clause on rebuilt parameters.
- The rest of 07 §7's list for exclusivity (`Sharing::Unknown`, the five
  maps, the outer loop) under I-5.

### 2.8 Essential distinctions kept

- *Linearity* (the callee uses it once: the future) and *exclusivity*
  (the caller held it alone: the past) are two facts, one grade each
  half (§5.10 G1, G2; AGENTS.md).
- The *promise* (decided by a rule, refuses) and *inferred exclusivity*
  (optimization, never refuses) are two facts with two producers.
- A taken cell's *family* and a construction's *layout* are both read: a
  rebuild needs the same family and equal layout.
- Borrowed and owned parameters; fixed cases (the root, quantity 1, memo
  cells) carry no inference.

### 2.9 Seams

| with | the declaration both sides write against | status |
| --- | --- | --- |
| L16 frontend | case and with blocks written in place; quantities emitted as Idris checked them (FB-28) | unfixed; required by R0 and R1 |
| L04 families | the family's kind `in_place`; layout per constructor; the token's key (layout and source constructor) | unfixed |
| L05 lifetimes, grades | `excl` (or Q1's permission) admitted before counting; a view's lifetime parameter as Borrows' answer | unfixed |
| L07 counting | lowers `idr.take`/`idr.rebuild`; drop-guided reuse never sees a promised token; placement adds no dup to an exclusive value | fixed by invariants 1, 2 |
| L09 control flow | a token as a jump argument; dead-end classification with `HasBreakingControlFlowOpInterface` (D25) | fixed by D19, D25 |
| L10 frames, tail | a frame field may be a token (D31); TRMC keeps the recycled cell (10 §3.1); tail kind on the call read by Borrows (D30) | fixed by D30, D31, D34 |
| L14 analyses | the marking template; the program graph | consumed |
| L18 optimizer | every pass keeps exclusive grades and tokens (linear); a rebuild never folds | fixed by invariant 1 |
| L03 specification | `idr.rebuild`; the stage table; Rule::Uniqueness; the pass record | unfixed |
| L19 tests | B1 to B20 as tests of behaviour | drafted here |

---

## 3. QTT

### 3.1 Where each quantity enters, is kept, read, lost

| quantity | enters | kept | read | lost |
| --- | --- | --- | --- | --- |
| 0 | Idris's erased arguments and indices | no value (AGENTS.md; D48 index terms) | never by the rule; layout does not depend on it | nothing to lose. `Linear.Nat.toNat` is `0` (`Nat.idr:16-20`), the iterator's string index too (`Iterator.idr:62-64`) |
| 1, parameter | the checked signature | `!idr.lin<T>` (`Emit/Operations.idr:145-155`); `idr.lin.enter` where an unrestricted value fills it, a fresh identity (`IdrOwnershipOps.td:403-413`) | the linearity verifier (`Verify/Linearity.cpp:1-6`); Borrows owns it (`Borrows.cpp:83-84`); idr-demand (`Demand.cpp:70`) | Emit's demotion of a binder used twice (`Bodies.idr:131-138`); `idr.lin.use` at its one use; the grade becomes `own`/`excl` at counting; nothing past the lowering |
| 1, constructor field | the declaration (`List.idr:15`, `Nat.idr:14`) | each operand entered linearly (`Operations.idr:309-312`) | implicitly: no constant fold, no merge (1.9) | nowhere; under I-1 the exclusive grade holds it by construction |
| 1, case-bound field | a match on a linear scrutinee binds fields at their declared quantity (`Bodies.idr:412-424`, `takenApart`) | linear block arguments | the verifier | as above |
| ω | `let` and unannotated binders | plain types (`heldAs Many`, `Bodies.idr:136`) | exclusivity only by analysis | — |

### 3.2 Where linearity alone proves exclusivity

An argument is exclusive by Idris's check alone when its chain from a
construction to the call passes only through quantity-1 binders and
linear fields: a construction (fresh), entered linearly (a fresh
identity), held by linear binders (each used once by QTT), taken apart by
linear matches. In the IR that chain is `idr.con`, `idr.lin.enter`,
linear block arguments of matches on such values, and obligation
parameters, all typed `!idr.lin`: idr-in-place reads it off the types
with no solve (P1, P2, P4, with U given by the type). B3 is the case,
and B2 with `let 1` would be too but for `build`'s result (P3). The
analysis is needed only for an unrestricted binder (U by the per-path
count), a call's result (P3: QTT says nothing of a result's past), and a
case that crashes (P5).

The closed world gives fresh results without analysis: a library that
builds a value and hands it to a linear continuation
(`newArray : (size : Int) -> (1 k : (1 arr : Array t) -> a) -> a`,
`sources/papers/brady-2021-idris2-qtt/protocols.tex:15-27`) becomes,
after defunctionalization, a direct call with a fresh construction as
its argument: P2 plus U by type.

### 3.3 Facts a quantity proves that the design still pays for

- A count test on a take where a context exists that proves exclusivity
  (subset masks, X2 and X10): I-5.
- A count pair per element on read-only recursion over a part of a
  borrowed value: I-6.
- A test in every memo force and partial function (G-09): I-4.
- The late solve proving again what idr-in-place proved: the domain
  filter (a value graded exclusive has no node).
- When the compiler runs: idr-demand's re-derivation and name map
  (D10, 1.4).

### 3.4 Representations that make a misuse unwritable

- `!idr.q<1, excl, T>` on a rebuilt parameter: the future (QTT) and the
  past (uniqueness) in one grade, as Marshall, Vollmer and Orchard pair
  them (§5.10 G1). A dup, a frame lifetime, a constant and a merge are
  each refused by a rule that exists today (invariant 1).
- The token: the rebuild's cell as a linear SSA value from the check on,
  so a pass cannot drop the pairing without the verifier seeing a token
  unused.
- Faithful quantities from Emit (L16): the rule reads what Idris checked.

---

## 4. Improvements

### I-1. The in-place promise decided whole before the optimizer (*coordinator*)

- **Evidence.** D24.5: the refusal reads exclusivity on the owned stage,
  after contify, the optimizer, canonicalization, CSE, frames and
  placement (`Pipeline.cpp:77-128`); match-and-counting §7 already warns
  that join-point formation would move acceptance.
- **Counterexample.** B7: `inc1 (MkBang x :: xs) = if x > 0 then MkBang
  (x + 1) :: xs else MkBang 0 :: xs` called with a list used again. With
  a small case block the inliner merges it, idr-demand sees a recycle of
  a take of the parameter, and the program is refused; grow the `else`
  arm past the inliner's cap and the case block stays a function, no
  recycle of the parameter's take exists in `inc1`, and the same call is
  accepted with a run-time test. B10 and B11 move the same way with
  borrow inference and dead-code deletion.
- **Root cause.** The caller half of the promise is read off the
  optimized, counted program, where the program's own uses are gone.
- **Correction.** A check pass, `idr-in-place`, after idr-knots and
  before idr-effects, decides §2.1's R1 to R4 on the program as written,
  refuses there, and writes its verdict as grades (the obligation in the
  function type; exclusive values along each proven chain; P3's
  conditional summaries served by grade copies in the key space of I-5).
  Every use the program evaluates counts (U): a borrowed read is a use,
  because borrow inference is a performance inference whose answer
  depends on unrelated calls (C1's "at every call"), and acceptance may
  not (AGENTS.md); this choice is the coordinator's, open to the owner.
- **Deletes.** `Demand.cpp` whole and its pass record; exclusivity's part
  in acceptance (the late solve no longer carries `Rule::Uniqueness`);
  the dependence 08 NQ1 lists.
- **Discriminated by** B7, B10, B11 (a fixed verdict, whatever runs
  after), and by the verifier: an exclusive value used twice after any
  pass is an error.

### I-2. The rebuild's pairing as data: a token from the check on (*coordinator*)

- **Evidence.** D24.4, C1.d: the bit in the function type leaves the walk
  to find the construction again; idr-frames runs before counting
  (`Pipeline.cpp:125`), and under D32 it takes every non-tail call on a
  cycle, so a rebuild after one sits in another function from the take;
  first-fit by size gives the
  token to whichever construction of equal layout comes first
  (`Reuses.cpp:186-200`; §5.10 A4).
- **Counterexample.** B14: `g : LList Int -@ LList Int; g (x :: xs) = x
  :: rev (g xs) []`. Under D32, idr-frames moves `x :: rev _ []` into the
  frame's continuation; counting in `g` sees the parameter's cell die with no
  construction after it and drops it; the continuation allocates. The
  promise is broken with nothing said, which D24 calls a compiler bug.
  B15: in `f ((a, b) :: xs) = (b, a) :: f xs` the pair's cell and the
  list's cell are both two words; whichever the walk pairs first, the
  list's construction may get the pair's token, a token not promised and
  so tested.
- **Root cause.** A relation between a cell and a construction is held as
  nothing (a per-parameter bit), so every pass that moves code can lose
  it.
- **Correction.** idr-in-place writes each rebuild site as an `idr.take`
  of the exclusive refined scrutinee at the case's entry (the token and
  the fields) and an `idr.rebuild %token @C(fields)` in place of the
  paired construction. The token is linear, so a join point takes it as a
  jump argument, a frame as a field (D31), a case block cannot exist
  (R0); counting lowers both to its own take and recycle; drop-guided
  reuse never sees a promised token.
- **Deletes.** C1's "an obligation of this walk"; every special case for
  frames, join points and case blocks in reuse; first-fit for promised
  cells.
- **Discriminated by** a verifier rule (a token used other than by one
  rebuild of equal layout or a free is an error) and by B14 and B15: the
  lowered module of each has no allocation for the rebuilt cells
  (*unverified* until built).

### I-3. Obligations close over forwarding; the refusal names the user's call (*coordinator*)

- **Evidence.** D24.2.2; `Demand.cpp:127-135`.
- **Counterexample.** B5 and B12: a shared list passed to
  `Linear.List.reverse` is refused at `List.idr:37`, a line of the
  library, with "@Linear.List.reverse passes a shared LList to
  @Linear.List.reverseOnto"; whether the user's line appears instead
  depends on whether the optimizer inlined `reverse`.
- **Root cause.** The obligation is per rebuilt parameter only, so a
  forwarder's parameter is joined over its callers and the failure shows
  where the join is, not where the sharing is.
- **Correction.** R2's closure and R4's site: the requirement moves back
  through every parameter that hands the value on, and the refusal is at
  the first call whose argument is not such a parameter, with the user's
  names and one note at the cause.
- **Deletes.** The reporting heuristic (`Demand.cpp:127-135`) and its
  reason; the name-keyed map (`:104-107`).
- **Discriminated by** B5, B12: the error's location is the user's call
  (the harness reads the line, as `tests/uniqueness-shared-rebuild/expected`
  does).

### I-4. A dead end gives nothing (G-09), classified by interfaces (*coordinator*)

- **Evidence.** 1.6 G-09; D19.c.
- **Counterexample.** B6.
- **Root cause.** A terminator that never returns is read as a way out
  whose operands are unknown.
- **Correction.** In the late solve's extractor a block whose terminator
  has no successor and implements neither
  `RegionBranchTerminatorOpInterface` (which `ReturnLike` brings,
  `ControlFlowInterfaces.td:638-640`) nor D25's breaking control flow
  contributes no predecessor; any other terminator is an internal error
  naming the op (invariant 6). In idr-in-place it is P3 and P5's "gives
  nothing".
- **Deletes.** `unknownFrom`, its copy into every successor, its share.
- **Discriminated by** B6 compiling, and the lowered module of a partial
  rebuilder having no count test on its take (an artifact check).

### I-5. Exclusivity by context, one solve, exact copies (*coordinator*)

- **Evidence.** X2, X3, X10; D10. Today: up to one copy per function
  (key "every followed parameter exclusive", `Specialize.cpp:3-11`), keys
  guessed on a context-blind solve and closed over callees and fed calls
  (`:92-117`), then a second whole-program solve (`Exclusive.cpp:39-46`)
  that rebuilds `Calls`, `Captures` and the graph (07 Z-01). Cost of the
  copies: at most twice the functions that take a followed parameter
  shared (08 §6 rc-Q2, *read*); the solve's cost twice.
- **Counterexample.** `merge : List Int -> List Int -> List Int`, which
  takes both lists apart and builds from their cells, called at one site
  with a fresh first list and a shared second, and at another with both
  shared. No call gives every followed parameter an exclusive value, so
  no copy is made (`Specialize.cpp:62-69, 97-102`); the first call goes
  to the original, whose first parameter is shared by the join over both
  callers, and every take of the fresh list tests its count, a fact the
  call site knows.
- **Root cause.** A function's context is one bit (all exclusive or the
  original), and copies are decided before the solve that needs them.
- **Correction.** The solve's nodes are (value, mask) for each mask a
  call reaches, created as calls reach them (summaries per context, the
  IFDS form 07 §3.1 row 5 names); a call's mask only loses bits as its
  arguments become shared, so its target moves at most once per followed
  parameter; after the marking, re-mark with targets fixed until none
  moves (X3), which ends since masks only shrink; then one copy is
  materialized per reached (function, mask) whose answer differs from
  the original's, named from its key. No budget: the key space is finite.
- **Deletes.** `givesExclusive`, `copyable`, the key closure, the second
  solve, `Calls::target`'s callback (07 X-03).
- **Discriminated by** the counterexample: its lowered module has no
  count test on the fresh list's takes. **Measurement to take:** on stage 1,
  reached (function, mask) pairs, copies materialized, code size before
  and after, and the solve's time and peak footprint
  (`--mlir-timing`, `phys_footprint`), against today's copy count and
  two solves.

### I-6. Borrows: derived views, a program fact for rebuilds, one inference with lifetimes (*coordinator*; D26's wording is Q2)

- **Evidence.** C1.a, C1.e, D26.b, D39.a; match-and-counting §7's join
  parameter rule; Lean's derived borrows (§5.10 B3).
- **Counterexample.** `depth : Tree -> Nat; depth Leaf = 0; depth (Node
  l r) = 1 + max (depth l) (depth r)` and `main` doing `let d = depth t
  in size t`. C1 as written owns `depth`'s parameter (`depth l` passes
  `l` at its last use), so `main` dups the tree and `depth` pays a
  decrement and an increment per node; with derived views the parameter
  is a view at `main`'s lifetime and no count moves.
- **Root cause.** "Uses the argument afterwards" asks only the immediate
  caller; the fact that an outer active call needs the bytes is lost.
- **Correction.** A parameter is borrowed when the callee neither
  consumes nor stores it, does not take it apart into a rebuild site of
  equal layout (the program fact replacing the reuse sites), and at
  every call the argument is used afterwards, or its type bounds what it
  reaches, or it is a view whose lifetime outlives the call (a borrowed
  parameter of the caller or a part read from one). The answer is the
  parameter's grade in the signature, a view at a lifetime parameter
  (D39), written by one marking (§2.4, backward, no gate); the tail and
  TRMC facts are read off the call (D30, D34).
- **Deletes.** `Borrows.cpp`'s framework state and the reading of
  `Reuses`; C1's clause on rebuilt parameters; a second inference of
  lifetimes for parameters.
- **Discriminated by** the counterexample's lowered `depth` having no
  count operation (an artifact check), and B10 unchanged
  (refused: borrows never move acceptance).

### I-7. The obligation is the family's own cells (*owner*, Q1)

- **Evidence.** D24.3; `ExclusivityAnalyses.cpp:133-142, 186`.
- **Counterexample.** B13.
- **Root cause.** The obligation borrows the grade `excl`, whose meaning
  (every cell of the graph) is wider than what a rebuild takes apart.
- **Correction.** The obligation is that the argument holds the only
  reference to each cell of its family it reaches through the family's
  recursive fields; a permission between `own` and `excl` carries it
  (`excl` implies it); P2 reads "each field of the same family".
- **Deletes.** The element's taint of its container in the promise (X7).
- **Discriminated by** B13 accepted, B1 still refused.

---

## 5. Work units (draft; none dispatched)

**U1. Dead ends give nothing.** *Writes:*
`foreign/idr/lib/Analysis/Ownership/ExclusivityGraph.cpp`,
`foreign/idr/lib/Analysis/Ownership/ExclusivityAnalyses.cpp`,
`foreign/idr/include/idr/Analysis/Ownership/ExclusivityDetail.h`, a new
`tests/uniqueness-partial-rebuild/` (B6). *Outcome:* I-4. *Deletes:*
`unknownFrom` and its share. *Must not:* change what a branch or a
region-branch terminator contributes; touch placement (L07). *Acceptance:*
B6 compiles and runs to its expected output; the five suites unchanged.
Lands first, alone.

**U2. The in-place check.** *Writes:* the pass record and Rule::Uniqueness
row in the Idris specification (L03's layout, C7), a new
`foreign/idr/lib/Transforms/InPlace/InPlace.cpp`,
`foreign/idr/lib/Transforms/Pipeline.cpp` (one line each: add after
idr-knots, remove idr-demand), `tests/uniqueness-*` (B1 to B13, B19, B20).
*Outcome:* I-1 and I-3: R1 to R4 decided before the optimizer, grades
written. *Deletes:* `foreign/idr/lib/Transforms/Demand/Demand.cpp`,
`foreign/idr/include/idr/Transforms/Demand.h`. *Must not:* read reuse,
placement, borrows or the late solve; budget anything (an acceptance
analysis). *Needs:* L16 (case blocks in place, faithful quantities), L05
(the grade admitted before counting). *Acceptance:* each boundary test's
verdict and error line as §2.1 states; `tests/leet-relink-in-place`
unchanged.

**U3. The rebuild token.** *Writes:* `idr.rebuild` and `idr.take`'s stage
in the specification, the token verifier rule,
`foreign/idr/lib/Transforms/Ownership/Take.cpp`,
`foreign/idr/lib/Transforms/Ownership/Reuse.cpp` (lowering only),
`foreign/idr/lib/Transforms/InPlace/InPlace.cpp` (after U2). *Outcome:*
I-2. *Deletes:* reuse's handling of promised cells. *Must not:* change
drop-guided reuse for unpromised cells (L07); change frames (L10 carries
the token as a field). *Acceptance:* B14, B15 and the relink test show no
allocation for a rebuilt cell in the lowered module.

**U4. Exclusivity by context.** *Writes:*
`foreign/idr/lib/Analysis/Ownership/{Exclusivity,ExclusivityAnalyses,ExclusivityGraph,Captures}.cpp`,
`foreign/idr/include/idr/Analysis/Ownership/ExclusivityDetail.h`, the
`Exclusivity` part of `foreign/idr/include/idr/Analysis/Ownership.h`,
`foreign/idr/lib/Transforms/Ownership/{Exclusive,Commit,Specialize}.cpp`,
`writeExclusiveGrades` in `Signatures.cpp`. *Outcome:* I-5 on L14's
template; a cached analysis, the commit nested. *Deletes:* 2.7's
exclusivity rows. *Must not:* refuse anything; give a node to a value
already graded exclusive. *Acceptance:* the I-5 counterexample's lowered
module has no count test on the fresh list's takes; the measurement of I-5 recorded.
After U1.

**U5. Borrows as a marking.** *Writes:*
`foreign/idr/lib/Analysis/Ownership/Borrows.cpp`, the `Borrows` part of
`Ownership.h` and `writeOwnedGrades` in `Signatures.cpp` (after U4),
`foreign/idr/lib/Transforms/Ownership/Grades.cpp` (the order: no reuse
read). *Outcome:* I-6. *Deletes:* 2.7's Borrows rows. *Must not:* decide
placement (L07) or lifetime allocation (L05); move any refusal.
*Acceptance:* the `depth` program's lowered `depth` has no count
operation; B10 still refused.

---

## 6. Owner questions

**Q1. How strong is the obligation?** D24 names `!idr.excl<T>`, which
means every cell the value reaches is unshared; a rebuild takes apart
only its own family's cells.
- *(a) As worded.* Costs: refuses rebuilding a fresh spine whose boxed
  elements are shared (B13, `reverse (rep n (Just k))`); buys: one
  permission, no new grade.
- *(b) The family's own cells.* Costs: one more permission between `own`
  and `excl`; buys: every program whose rebuilds can be kept is accepted,
  and an element's sharing never reaches the promise.
- *Recommend (b).*

**Q2. D26's "never" line and derived borrows.** Read literally, "a
borrowed argument whose last use is the call" forbids a read-only
recursion from borrowing its own fields, though the promise ("bytes it no
longer needs") allows it, and D10 forbids paying a count pair per element
for a fact the outer caller already proves.
- *(a) Keep the wording.* Costs: every read-only recursion that is not
  a loop (two calls under `max`, a tree's depth) counts per node; buys:
  nothing D26's promise needs.
- *(b) "A borrowed argument no active call needs after the call".* Costs:
  a lifetime per view (D39 has it); buys: Lean's derived borrows, D10.
- *Recommend (b).*

**Q3. Does the promise reach an in-place value held at quantity 1 inside
another linear value?** D24 says "a quantity-1 parameter of such a type";
its first sentence says the type's "values".
- *(a) Parameters only* (B19's inner cell tested at run time when shared).
  Costs: a linear record holding a list loses the promise; buys: the
  rule's text as it stands.
- *(b) Every value bound at quantity 1*, a parameter or a field a linear
  match binds. Costs: the obligation reaches the enclosing parameter
  through R2 (callers of such functions owe exclusivity); buys: the
  promise means what the type says, with QTT treating both binders alike.
- *Recommend (b).*
