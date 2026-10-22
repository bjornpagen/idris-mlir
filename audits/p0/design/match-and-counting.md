<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: the match, join points, and counting

Status: written 2026-10-21 for DP-15, after D18 and D19
(`proposals/0000-mlir-native.md:280-325`, `AGENTS.md:285-297`). D19
settled the shape: regions are the base, join points carry linear tail
continuations and local tail calls, blocks only at the lowering. This
document makes D19 buildable. It says what each counting proof needs from
control flow, how a join point is encoded in MLIR, what upstream does and
what we write, and walks the two stress tests through it.

Grounds: *read* (a path:line I read), *measured* (a command I ran),
*recalled* (from memory, not re-read), *conjecture*. Ours at e96bb991;
MLIR at the pin 7208ba24 (`.toolchain/llvm-project`, shallow); Lean at
541dbdcd (`/tmp/rc-lane-lean/lean4`, 2026-10-21); Koka at
`/tmp/rc-lane-koka/koka`; Modular at `third_party/modular`. Nothing was
built or run. IR is illustrative: op names that do not exist yet
(`idr.join`, `idr.jump`, `!idr.cont`, `idr.is_unique`, `!idr.ctor`) are
proposals. Per D20 no world value appears.

## 0. In plain words

- **The foundation.** MLton chose a flat CFG under a garbage collector:
  no ownership, scope or uniqueness fact matters at its run time. Koka
  keeps an expression tree but tests uniqueness at run time. Lean tests
  `isShared` at run time and re-tests it after a join. We prove counting
  decisions from Idris's quantities and our exclusivity marking. So our
  representation is judged by what it lets the compiler prove.
- **What counting reads.** Scopes (which case a value lives in), rejoin
  points (where facts meet), the refined constructor in a case, and the
  edges along which values flow. Regions hold all four structurally.
  Blocks hold them only through dominance, recomputed. Join points hold
  them too, and add one thing regions cannot: a continuation shared by
  sites that are not siblings, with no copy and no run-time selector.
- **Join points do not replace regions; they live beside them** (§3).
  GHC keeps `case` beside `join`. Lean keeps `cases` beside `jp`, but its
  `cases` is a terminator, so Lean is a lexically scoped CFG, not regions.
- **The MLIR gap** (§5). `RegionBranchOpInterface` can say "jump to a
  sibling region" (as `scf.while` does) but not "jump from inside a
  nested match to an enclosing join". Upstream is adding exactly this
  (the early-exit work, PR #166688, unmerged at the pin). The design:
  `idr.join` and `idr.jump` with an SSA token, our ops implementing
  upstream's interfaces, nested jumps through upstream's early exit,
  backported. Vendoring `scf` and imitating Mojo's HLCF both lose.
- **bindGrammar** (§8): the 43 GB blowup was a per-pair clone in
  frames, not the match form; regions serve its counting fully.
- **The CPS parser** (§9): a linear continuation inlining brings next to
  its applications is a join point, never allocated; one crossing a
  recursive call is a heap cell taken apart once and reused in place.

## 1. The foundation: a collector, a run-time test, a proof

| compiler | memory | control flow after closure conversion | where uniqueness is decided |
| --- | --- | --- | --- |
| MLton | tracing GC | flat CFG: `Case` arms are labels, blocks take fields as arguments (`wave1/5.9-mlton.md:199-213`, read there) | nowhere: nothing at run time depends on ownership |
| Koka | Perceus RC | expression tree: `Case` with branches, no join points (`Backend/C/Parc.hs:239-283`, read) | at run time: drop-specialization and reuse emit `is_unique` tests (5.10 A3, A4); FBIP checks a definition but "decides uniqueness at each call at run time" (5.10 A8) |
| Lean 4 | RC | tree with `cases` as a terminator beside `jp`/`jmp` (`LCNF/Basic.lean:380-387`, read) | at run time: `reset` tests `isShared`; the expansion passes `isShared` to a join point and tests it again at the `reuse` (`LCNF/ExpandResetReuse.lean:17-36`, read) |
| idris-mlir | RC with proofs | regions; join points (D19) | statically: grades in types, one exclusivity marking, grade-keyed copies, `idr.is_unique` folding on `!idr.excl` (synthesis C §2 items 1, 6, 9; 08 §6 rc-Q2) |

Lean's reset shows a fact lost at a join: the unique path's fact becomes
a boolean argument of `resetjp`, tested again at the reuse
(`ExpandResetReuse.lean:20-35`, read): D10's ban in miniature. The fix is
a join point specialized by the fact (§7), not no join points.

## 2. What each counting proof reads, under each shape

"Regions" is today's `idr.match` (a region per case, rejoining at the
op's results). "Blocks" is MLton's form (03 §5.2b). "Join points" is
regions plus D19's join points.

| optimization | what it reads | regions | blocks | join points |
| --- | --- | --- | --- | --- |
| dup/drop placement (08 T3) | a reverse walk with the live set; each decision's arms and their live-ins; each rejoin's live-in | the tree: one walk, O(ops + regions) | a post-order walk over an acyclic CFG; a rejoin is any block with two predecessors, found by liveness | as regions; a join region's live-in is computed once and used at every jump (Lean's `jpLiveVarMap`, `ExplicitRC.lean:587-597, 627-636`, read) |
| drop at a case head for values only a sibling uses (Perceus) | the arms of one decision | the case region's entry | the arm block, if every arm block has the case as its only predecessor (an invariant to verify) | as regions |
| drop specialization (5.10 A3) | the constructor of the dropped value | the refined case argument `!idr.ctor<T,@C>` (03 §5.2a) | a produced operand of the case terminator | as regions; a join parameter is refined only if every jump agrees on the constructor |
| drop-guided reuse (08 T4) | tokens available on each path; their meet at a rejoin | a token reaches the code after a match only as a match result (all cases give one) | a block argument, same rule | a jump argument: tokens reach shared continuations too |
| the take's expansion (synthesis C §3.1) | the unique and shared paths, and what follows both | `scf.if` on `is_unique`; the rest after it sees a nullable token (a re-test), or is copied into both arms | the same, as blocks | the rest as a join region, specialized by the token's presence: no re-test, at most two copies (§7) |
| borrow inference (07 D3) | per parameter: read only, or consumed; tail calls | per function | per function | jump parameters are nodes too: Lean infers them (`InferBorrow.lean:20-33, 430-434`, read) |
| exclusivity (07 D2) | flow edges; a meet at each rejoin | edges from yields to results; e96bb991's quadratic was a client's query per pair (03 §3, M3) | edges per terminator operand, O(1) (MLton C3) | edges per jump operand, O(1); a crash arm jumps nowhere, so 07 D1's precision loss cannot arise |
| the in-place promise (DP-C1, DP-12) | a quantity-1 parameter of an `in_place` type rebuilt on every path | each case region that rebuilds | arm blocks by dominance | as regions; the rebuild may sit in a join region, the token passed to it |
| stack cells (08 T9) | a cell that cannot outlive a scope | the region is the scope (`memref.alloca_scope` is a region op) | lifetime markers, LLVM's stack colouring | a join region is a scope; a recursive one (a loop) frees per iteration |
| frames (10 D2) | the rest of a block after a run of a closure, and the values it holds | the rest of the block and the enclosing tail matches; `held` found by an O(rest²) walk (10 Q-W6) | the call's continuation blocks | the rest is a join region: a frame is that join point escaped, its fields the region's live-in |
| TRMC (10 §2.3) | the path from a self call's result to the return | arrivals per region, recounted per arrival (10 IT-7) | arrivals per predecessor of the join block | arrivals per jump and per yield, read once |
| tail loops | a self tail call | `scf.while` built from a decision, or the flag payload loop (10 §2.3) | a back edge | a recursive join point is the loop (D19) |
| contification (10 D4) | functions that always return to one continuation | one call site only: "a second call site would need a branch out of a match region into a block they share" (`Contify.cpp:10-13`, read) | Fluet and Weeks in full (MLton E1) | Fluet and Weeks in full: the function becomes a join region |

**Proofs we cannot make today because of the representation** (read
chains in the cited lanes, effects conjecture):
1. A continuation tail-called from two sites stays a heap closure:
   allocated, counted, at best reused (`Contify.cpp:10-13`).
2. Exclusivity is met at every match's rejoin; nothing carries it on
   through a shared continuation except copying it (case-of-case, under a
   duplication limit; c179ab2d shows it fighting `yield-fields`).
3. A reuse token never crosses a match: Reuses searches each region
   (`Reuses.cpp:219-225`, per 08 Q-W4).
4. A live crash arm shares every result of its match (07 D1, bug C #2).
5. After the take's expansion the unique path's fact is lost; the
   lowering re-tests the token for null (`Cells.cpp:128-140`, per 08 §6).
6. Frames knows by construction that its stack is threaded once and
   built fresh, and writes no grade for it; counting must rediscover it
   or test (`Frames.cpp:1-48`, read; no `excl` write in its plan, 10 §2.3).

Regions alone fix 3 (a token as a match result), 4 (07 D1) and 6 (frames
writes the grade). Join points are needed for 1 and, within a bound, 2
and 5. Blocks fix 1 and 4 but drop the scopes that placement, stack
cells and the promise read structurally.

**Reuse across a rejoin.** D19's "reuse across a rejoin through a token
argument" needs a correction: across a match's own rejoin, regions do it
with a token result; join points add shared continuations.

```mlir
// regions: every case gives a token of one layout, so the match yields it
%t, %v = idr.match %xs : !idr.excl<!idr.box<!T>> -> (!idr.token<2>, i64) {
case @Node(%c: !idr.ctor<!T,@Node>, %a: i64, %b: i64) {
  %k, %_a, %_b = idr.take %c ...   // excl: fields move, %k is the cell
  %s = arith.addi %a, %b : i64
  idr.yield %k, %s : !idr.token<2>, i64
}
case @Pair(%c: !idr.ctor<!T,@Pair>, %a: i64, %b: i64) { ... idr.yield %k, %a ... }
}
%cell = idr.cell.recycle %t : !idr.token<2> -> !idr.cell<!T>
%n = idr.cell.init %cell @Leaf(%v : i64)  // tag written, no allocation
```

`!idr.token<2>` is keyed by layout (two words, no pointers), not by
constructor, so a `Node` cell becomes a `Leaf` (Koka matches by size,
5.10 A4). Synthesis A's `!idr.token<!idr.box<T>, @C>` would forbid it;
§12 keeps the source constructor for reuse specialization and checks
layout equality at the recycle.

**Exclusivity through a shared continuation.**

```mlir
%v = idr.match_lit %c : i1 -> (!idr.own<!A>) {
case true  { %f = ... fresh cell ...; %s = idr.share %f ...; idr.yield %s }
case false { idr.yield %old : !idr.own<!A> }
}
... update %v in place ...   // the meet is shared: an is_unique test runs
```

Copying the update into both arms keeps `excl` in the first. A join
region specialized by its parameter's grade does the same with at most
one extra copy, the rule grade specialization already uses for functions
("one copy per function, key every followed parameter exclusive", 08 §6
rc-Q2): a finite key, so no budget is needed for it to end.

## 3. Join points elsewhere, and whether they replace regions

**GHC** (Maurer, Downen, Ariola, Peyton Jones, PLDI 2017, *recalled*):
`join j x = e in body` and `jump j a`; a join point is never captured
and only jumped to in tail position; a let-bound function whose every
call is a saturated tail call becomes one (contification); case-of-case
shares the outer continuation through a join point instead of copying it
into each inner arm; a recursive join point (`joinrec`) is a loop. Core
keeps `case` as an expression with its own continuation beside `join`.

**Lean 4** (read): `Code` has `cases` with no continuation (a terminator),
`jp decl k` whose scope is `k`, and `jmp` from any depth of `k`
(`Basic.lean:380-387`). Counting: ExplicitRC computes a join point's live
set once and, at each `jmp`, sets the live set to it and adds `inc`s for
arguments passed to owned parameters (`ExplicitRC.lean:587-597,
627-636`). At `cases`, the union of the arms' live sets, then a drop
prologue per arm (`:598-626`). Borrow inference treats join parameters as
parameters, with two forced reasons: propagation from a jump's argument,
and tail-call preservation (no `dec` can follow a `jmp`)
(`InferBorrow.lean:20-33, 212-215, 430-434`). Reset/reuse does not cross
a `jmp`: `S` stops at it (`ResetReuse.lean:122`); `D` searches a join
point's body only for values free in it (`:213-221`). Only the expansion
passes a token to a join point, with `isShared` (`ExpandResetReuse.lean:20-35`).

**Koka** (read): Perceus on the expression tree, drops per branch
(`Parc.hs:239-283`), tokens intersected at branches (`ParcReuse.hs:200,
296-303`); no join points.

**Can join points replace regions?** No, and D19 does not ask it. A
region match already has one implicit join point: the code after the op,
receiving its results. An explicit one is needed only where a rejoin is
shared by sites that are not siblings, for a tail jump from depth, or for
a loop. Join points everywhere is Lean's form: every match a terminator,
every rejoin named. It is a CFG with lexical scope (CPS and SSA are one
thing, Kelsey 1995, *recalled*); it loses the single entry and single
canonical rejoin per match, and upstream's structured tools. GHC's shape,
`case` with a continuation beside `join`, is D19's. The coordinator's
framing holds with one correction: Lean is not GHC's shape, since its
`cases` has no implicit continuation.

## 4. Idris's static guarantees, through control flow

| guarantee | how regions carry it | how join points carry it | lost under blocks / HLCF-style exits | the counting proof it enables |
| --- | --- | --- | --- | --- |
| quantity 0 (erased) | no field, parameter or argument (AGENTS.md) | no join parameter | nothing | an erased index costs nothing: no value, no count, no instance split if instances are keyed by representation |
| quantity 1 (`!idr.lin<T>`) | in the type, verified after every pass | join parameters typed `!idr.lin` | nothing (types) | a linear value is used once per path, so it is never dup'd; its last use is syntactic; the apply of a linear closure consumes it (a take, a token). It does **not** prove the cell unique: QTT lets an unrestricted value fill a linear parameter (AGENTS.md: "a linear binder does not imply unique heap ownership"); exclusivity must still prove it |
| linear continuation `(1 k : Res a -> r)` | the closure's sum is `!idr.lin` | applied once per path: jumped to once per path, so the join body is never copied for it | blocks: the same; HLCF: no continuation concept | never allocated when it is a join point (§9); a heap cell taken apart once otherwise |
| coverage | an exhaustive match has an empty default region, "the one spelling of no other constructor arrives" (03 O-44); impossible cases have no region | the same | blocks: a missing arm is a missing successor; same | no crash arm, so no unknown predecessor at the rejoin (07 D1): exclusivity holds through the match |
| partiality | a crash arm ends in `ub.unreachable`; placement places nothing there (`Placement.cpp:3-35`, read) | a crash jumps nowhere | the same | a crash arm leaks nothing that matters and costs no drops |
| totality (D13) | `total` on the function; no divergence effect | a recursive join point in total code is a terminating loop: `mustprogress` | the same | unused total code is deleted with its counts |
| refined constructor in a case | `!idr.ctor<T,@C>` bound by the case region (03 §5.2a); field reads total and speculatable | a join parameter of type `!idr.ctor` if every jump passes that constructor | blocks: a produced operand, scoped by dominance; `scf.index_switch`: no binding, a positional cast | drop specialization without a tag test; reuse specialization without a tag write |
| Idris's case blocks and `with` blocks | the elaborator lifts each into a function with one call site (`Contify.cpp:15-21`, read); emitted in place they are region matches (10 D4) | a case block called from several tail sites after inlining is a join region | nothing | a cell the parent takes apart is reused by the constructor the case block builds (`Contify.cpp:17-21`) |
| `Lazy` / `Inf` | a suspension: a closure in a memo cell, forced by a call | a forced suspension of a known label folds like a continuation | nothing | forced at most once: the memo cell's captures move out (`Captures`, 07 §3.1 row 21) |

Two notes. First, quantity 0 decides representation even when erased:
`{0 r : Type}` gives `r` no value, yet a value of type `r` has a layout,
so instances are keyed on that layout. Second, the fork's parser lost a
guarantee when its grammar became closures (360db182): Idris saw
recursion through `SeqEat` as guarded; through a function it does not,
so five calls are `assert_total` (`Libraries/Text/Parser.idr:82, 96,
120, 142`, `Parser/Rule/Source.idr:611`, measured by grep). Under D13
those functions count as total on trust (§9, item 4).

## 5. Encoding the match and join points in MLIR

### 5.1 What upstream's interfaces can say (read, at the pin)

- A region successor is "a region of this op" or "after this op"
  (`ControlFlowInterfaces.td:144-146`; `RegionSuccessor`,
  `ControlFlowInterfaces.h:199-227`). A terminator may name a *sibling*
  region of its parent: `scf.while`'s condition enters its body. It
  cannot name a region of an ancestor.
- A terminator that branches to a block of its own region is not a region
  branch terminator, and that is allowed ("in the presence of
  unstructured control flow", `ControlFlowInterfaces.td:156-163`).
  `scf.execute_region` holds several blocks for exactly this
  (`SCFOps.td:82-99`).
- `BranchOpInterface`'s successor operands may be *produced* by the
  terminator (`ControlFlowInterfaces.h:28-58`): a case terminator whose
  arms receive the fields.
- The dataflow framework marks the point after a successor op, or a
  region's entry, live (`DeadCodeAnalysis.cpp:520-536`).
- `lift-cf-to-scf` rebuilds structure from a CFG by adding a
  *multiplexer* block that dispatches on a block argument naming the
  predecessor (`CFGToSCF.cpp:1-100`, read): structure for a shared join
  costs a run-time selector. This is the proof, in upstream's own code,
  that pure regions cannot hold a shared continuation losslessly.
- Upstream's answer to jumps from depth is in progress (read 2026-10-21,
  web): the RFC "Region-based control-flow with early exits"
  (discourse 76998); Mehdi Amini's PR #166688 adds `scf.loop`,
  `scf.break`, `scf.continue`, a `HasBreakingControlFlowOpInterface` for
  the op that receives an exit and `PropagateControlFlowBreak` for the
  ops it crosses, and an SCCP test showing the precision gain; unmerged
  at the EuroLLVM 2026 round table, the target's encoding still argued
  (a count of regions, labels as Mojo uses, or an SSA token entering as a
  block argument, "least resistance" per Matthias Springer)
  (discourse 90555). The pin has none of it (measured: grep for
  `BreakingControl`, `PropagateControlFlowBreak`, `scf.break` finds
  nothing in `mlir/include` or `mlir/lib`).

### 5.2 One example in each form

```idris
f : List Int -> Int -> Int
f xs n = case xs of
  []          => k 0
  (x :: rest) => if x < 0 then n            -- an exit from depth
                 else case rest of
                        []       => k x
                        (y :: _) => k (x + y)
  where k : Int -> Int                       -- shared, tail-called
        k v = v * n + 1
```

**(a) Upstream as it is, blocks** (`scf.execute_region` or the function
body, `cf` branches; `cf.switch` produces no operands):

```mlir
%r = scf.execute_region -> i64 {
  %t = idr.tag %xs : !idr.box<!L> -> i32
  cf.switch %t : i32, [default: ^nil, 1: ^cons]
^nil:  cf.br ^k(%c0 : i64)
^cons: %x = idr.field %xs @Cons[0] ...     // the constructor is positional
       %neg = arith.cmpi slt, %x, %c0 : i64
       cf.cond_br %neg, ^out, ^more
^out:  scf.yield %n : i64
^more: ... cf.switch on rest's tag ... cf.br ^k(%x) / cf.br ^k(%s)
^k(%v: i64): ... scf.yield %w : i64
}
```

Keeps: sharing, the exit, every upstream CFG tool. Loses: the case tree
as scopes (dominance instead), the refined binding, the canonical rejoin
per match, and D19's letter (blocks before the lowering).

**(b) Upstream structured only**: `k` copied into three arms, or each arm
yields `(selector, value)` for a dispatch after: a fact known at each
yield paid at run time (D10), `lift-cf-to-scf`'s multiplexer.

**(c) Modular's HLCF** (`HLCFOps.td`, read):

```mlir
%v = hlcf.loop -> i64 {                       // a loop that never continues:
  hlcf.switch %tag default {                  //   its exit is the join point
    hlcf.break %c0 : i64
  } case 1 {
    hlcf.if %neg { hlcf.return %n : i64 }     // non-local: leaves the function
    else { hlcf.switch %tag2 ... hlcf.break %x ... hlcf.break %s ... }
    hlcf.yield
  }
  hlcf.yield
}
... k's body on %v ...
```

HLCF has no join point with a body. Its targets are fixed places (after
a loop, the next case, after the match, the function's end:
`HLCFOps.td:391-437, 648-713, 1074-1105`). A shared continuation is the
code after a break; two shared continuations of different types need two
nested loops or a selector.

**(d) D19: regions and a join op** (proposed):

```mlir
idr.func @f(%xs: !idr.box<!L>, %n: i64) -> i64 {
  %r = idr.join -> (i64) {
  ^body(%k: !idr.cont<(i64)>):                 // the join point's token
    idr.match %xs : !idr.box<!L> -> () {
    case @Nil(%c: !idr.ctor<!L,@Nil>) { idr.jump %k(%c0 : i64) }
    case @Cons(%c: !idr.ctor<!L,@Cons>, %x: i64, %rest: !idr.box<!L>) {
      %neg = arith.cmpi slt, %x, %c0 : i64
      idr.match_lit %neg : i1 -> () {
      case true  { idr.exit %n : i64 }          // ends the join op: see below
      case false {
        idr.match %rest : !idr.box<!L> -> () {
        case @Nil(%d: !idr.ctor<!L,@Nil>) { idr.jump %k(%x : i64) }
        case @Cons(%d: !idr.ctor<!L,@Cons>, %y: i64, %t: !idr.box<!L>) {
          %s = arith.addi %x, %y : i64
          idr.jump %k(%s : i64)
        }
        }
        ub.unreachable
      }
      }
      ub.unreachable
    }
    }
    ub.unreachable
  } join {
  ^k(%v: i64):
    %m = arith.muli %v, %n : i64
    %w = arith.addi %m, %c1 : i64
    idr.yield %w : i64
  }
  idr.return %r : i64
}
```

The exit from depth is itself a jump to the join op's result, so a
second terminator (`idr.exit`, written above for clarity) is the same op
as `idr.jump` with the op's own token: one op, the body's entry carrying
a token for "after this op" beside one per join region. A match whose
every case jumps has no yielding case and is followed by
`ub.unreachable`, as an HLCF case region needs `hlcf.unreachable`
(`HLCFOps.td:715-760`).

### 5.3 The options, ranked by how much upstream does

| # | option | upstream does | we write | keeps D19's facts? | verdict |
| --- | --- | --- | --- | --- | --- |
| 1 | `scf.index_switch` on a tag for the match, our ops only for fields and grades | folds on a constant index, `convert-scf-to-cf`, SCCP over regions | `idr.tag`, a refining cast at each case's head | loses the refined binding (a positional cast that must not be hoisted) and the match's consumption of a linear scrutinee as one op | no: today's `idr.match` is cheap under D16 and keeps both |
| 1b | `scf.while` for a recursive join point | loop canonicalizations, `upliftWhileToForLoop` (10 §2.3) | the payload `(i1 continue, A, R)` with poison halves (`Loop.cpp:7-14`, per 10 §2.3) | a recursive jump becomes a flag: the "flag-heavy `scf.while`" the round table calls mostly unoptimizable | interim only; upstream's `scf.loop` is the target |
| 1c | `scf.execute_region` with blocks and `cf.br` as the join carrier | region simplification (`mergeIdenticalBlocks`, `dropRedundantArguments`, `RegionUtils.cpp:1033, 1114`), dominance, SCCP over `cf`, `convert-scf-to-cf` | a case terminator with produced operands | loses single entry per match and the canonical rejoin; two forms of a match (region op and terminator) | no: against D19 and "one thing, one representation" |
| 2 | our own ops implementing upstream's interfaces (today's `idr.match`; the proposed `idr.join` for sibling jumps) | every client of `RegionBranchOpInterface`: SCCP, dead code, the canonicalizer's region tools, the inliner, CSE | the ops (generated from the Idris specification, D16) | yes, for jumps from the join op's own regions | yes, as the base |
| 3 | upstream's early exit, backported (PR #166688): our ops implement `PropagateControlFlowBreak` (`idr.match`, `idr.match_lit`) and `HasBreakingControlFlowOpInterface` (`idr.join`) | sees nested jumps as edges: SCCP, dead code, the lowering of `scf` ops that propagate exits | the backport as `upstream/<id>/llvm-project.patch` with its test and PINS.md entry | yes, all of them | yes, if the owner accepts carrying an unmerged PR (§5.4) |
| 4 | vendor `scf` into `foreign/idr` and extend it | nothing new: the interfaces' clients still cannot see an exit to an ancestor | a copy of `SCF.cpp`, its transforms, conversions, bufferization models and tests, re-synced on every bump of a pin that tracks main | no more than option 2 | no: drift on every bump; a vendored `.td` is hand-written text, against D16 (or regenerated from Idris, which is option 2); it adds nothing the interfaces' clients read |
| 5 | Modular's HLCF, imitated or vendored | nothing: HLCF uses its own `ControlFlowNode`/`ControlFlowTerminator` (`HLCFInterfaces.td:19-96`) and no HLCF op implements `RegionBranchOpInterface` (5.4 F7) | its canonicalizer, SCCP, mem2reg and SROA (`KGENPasses.td:32, 763, 959, 1160`), its CFG analysis, its lowering (`:444`) | non-local exits yes; join bodies no | no: the cost Mojo paid, for a weaker construct |
| 6 | a join point as a separate function, tail-called, contified into blocks only after lowering | `func.call`, the inliner, `musttail` | a property and a CFG-level contification | keeps counting (calls carry conventions) but not "local to its function" | no: D19 says local |

### 5.4 The encoding (recommended)

- **`idr.join`**: results; region 0 the body, whose entry block takes one
  token per target: `!idr.cont<(T...)>` per join region and one for the
  op's results; regions 1..N the join bodies, whose entry arguments are
  the join parameters with their grades (`!idr.lin`, `!idr.excl`,
  `!idr.token<n>`, views). `RegionBranchOpInterface`: parent to body;
  a jump immediately in the body or a join region to a join region
  (sibling, as `scf.while`) or to the parent; `idr.yield` in a join region
  to the parent. A join region that jumps to itself is a loop.
  `RecursiveMemoryEffects`, as the match has.
- **`idr.jump %tok(args)`**: a terminator. Its target is its token, one
  fact; the token's type fixes the arguments' types, checked by the
  generated verifier. Immediately nested, it is a
  `RegionBranchTerminatorOpInterface`. Nested in a match, it is an exit
  crossing the matches between (option 3).
- **`!idr.cont<...>`**: no op but `idr.jump` takes it (an operand type
  constraint every other op lacks), and it is never a result, a field, a
  call argument or a join parameter: "non-escaping" is unrepresentable,
  not checked by walking uses. Dominance puts every jump inside its join
  op. This is upstream's token option, so no count of regions has to be
  renumbered when the canonicalizer inlines a region (the question left
  open at the round table, discourse 90555).
- **The match** stays `idr.match` with the refined case argument (03
  §5.2a), `match_lit` split by key as 03 §5.2 says; lowered to
  `scf.index_switch` by idr-lower, then `convert-scf-to-cf`.
- **At the pin, until option 3**: upstream sees a nested jump as a case
  region that never returns to its match (true) and the join region's
  inputs as produced by the parent edge (unknown): sound, imprecise for
  SCCP. Our own passes (placement, exclusivity, borrows, TRMC) read the
  jump edges off one generated interface method of `idr.join`. That is a
  second tier, the smallest one; it is deleted when the backport or
  upstream's form lands. The lowering of nested jumps is ours until then:
  `scf.index_switch` requires `scf.yield` in its cases, so a match whose
  cases jump lowers straight to `cf` in idr-lower.
- **The upstream plan** (AGENTS.md): prefer upstream's own form,
  backported; the patch lives as `upstream/<id>/llvm-project.patch` with
  the PR's tests as `tests/upstream-<id>`, a PINS.md entry, and goes when
  the pin passes the merge. If the merged encoding differs (counts), the
  token stays ours and the verifier derives the count from it: one
  source, checked, as `idr.call`'s `effects` is (08 T6).

**Modular's lesson.** HLCF chose source-level scoping with labelled
non-local exits and paid with its own interfaces and four reimplemented
passes. Its labels are the encoding Mojo "never looked back" from
(discourse 90555), but its targets are fixed places, not join bodies,
and `match.next` (fall through to the next case, `HLCFOps.td:648-683`)
serves guards that Idris's case trees have already compiled away. Take
from it only the idea of a named target; take the mechanism from
upstream.

## 6. Contification and join-point formation, as passes

**Contification** (Fluet and Weeks; MLton E1, `5.9-mlton.md:283-296`):
- *Reads*: the program graph (synthesis B 2.1: dense ids, callers and
  callees as compressed rows), each call's tail kind (one fact per call,
  10 D1).
- *Algorithm*: one graph over functions and a root (edges: root to the
  root function and to every function with an unknown caller; f to g for
  a tail call; a non-tail call's continuation to g); one dominator tree
  (`llvm::DominatorTreeBase` over the graph's `GraphTraits`, 10 D4);
  `A(g) = Uncalled | Unknown | Cont | Func f` read from g's ancestor below
  the root. A function whose `A` is `Func f` becomes a join region of an
  `idr.join` in f, placed at the nearest region containing every call
  site, so jumps are as shallow as they can be. Each call becomes
  `idr.jump`.
- *Cost*: one graph build (maintained), one dominator computation, one
  rewrite. No budget, no iteration.
- *Where*: before idr-optimize (today's slot, `Pipeline.cpp:81-84`), and
  again in the optimizer's bottom-up step once inlining exposes direct
  tail calls (MLton runs it three times, E1). Better, the frontend emits
  Idris's case blocks in place as region matches once the TTC keeps a
  block's parent (10 D4, 0003 B1).

**Join-point formation** for a linear continuation:
- *Reads*: a closure constructor in f whose label is known; its uses (all
  applications, all in f); each application's tail position; the label's
  linearity (`!idr.lin`) so that each path jumps once.
- *Rewrite*: each application of the known constructor becomes
  `idr.jump` to one join region holding the lambda's body, its captures
  the join parameters (or free values of the region where they dominate
  it). A constructor stored, returned or passed to a call escapes and is
  left alone: it is not a join point.
- *Cost*: per function, linear in the constructor's uses.
- *Case-of-case* becomes GHC's: the outer match moves into a join region
  the inner arms jump to, never copied per arm.

## 7. Counting over join points

- **Placement** (08 T3 extended): visit each join region before the body
  (join regions that jump to each other in reverse order of their
  jumps; a recursive one by the loop rule placement already has). Record
  its live-in, parameters excluded. At a jump the live set is the
  target's live-in plus the arguments; an argument still live after the
  jump is impossible (a jump is a terminator in tail position), so every
  owned value in scope that is neither is dropped before the jump, as
  before a return. Still one walk, O(ops + regions).
- **Reuse tokens** (08 T4 extended): at a jump, tokens available on that
  path pass as arguments when the target takes a token of that layout;
  a path with none jumps to the copy specialized for "no token" (below)
  rather than passing a null.
- **Specialization by key**: a join region gets at most one copy per key
  bit (exclusive arguments, token present), chosen per jump by its
  arguments' state, as grade specialization chooses function copies (08
  T5, rc-Q2). The key is finite, so it ends by construction; a size
  budget may stop it and leave a run-time test, which only makes the
  program slower (AGENTS.md). This replaces Lean's re-test of `isShared`
  with a static choice.
- **Borrowed join parameters**: as Lean's rules: owned if any jump passes
  an owned value whose last use is the jump (no drop can follow a jump);
  borrowed if the body only reads it and every jump passes a view whose
  owner outlives the join op (a borrowed parameter of the function, or a
  value the join op's scope owns and drops after the op). The borrows
  marking (07 D3) gains these parameters as nodes.
- **Exclusivity** (07 D2): an edge per jump operand to its parameter, read
  once from the jump. A parameter is exclusive if every jump that reaches
  it passes an exclusive value; its specialized copy takes the rest.
- **The in-place promise** must be stated before the optimizer
  (DP-C1 (b)). Join-point formation is an optimization that can only
  raise exclusivity, so if the refusal read exclusivity after it, whether
  a program is accepted would depend on whether a join point was formed:
  08 NQ1 made worse. D19 makes DP-C1 (b) a requirement.
- **Stack cells**: a cell made in a join region and not escaping the join
  op is a frame cell; in a recursive join region it is freed per
  iteration (the region is the scope).

## 8. Stress test 1: bindGrammar

**The code** (`compiler/idris/src/Libraries/Text/Parser/Core.idr`, read).
A grammar is a box of a function (`:62-69`; 360db182 made it a shallow
embedding where upstream's was a data type, `third_party/Idris2/src/
Libraries/Text/Parser/Core.idr:23-53`). `bindGrammar` (`:87-93`) runs
`act`, matches the result, runs `next v.val` and passes that to
`mergeWith v`. Both runs are non-tail: the first is matched, the second
feeds `mergeWith`. `<|>` (`:184-204`) runs `x` and, on an uncommitted
failure, `y` on the same input.

**After defunctionalization** (conjecture on names). Each `MkGrammar`
lambda is a label of the closure sum of its type,
`Input -> ParseResult ty`; `runGrammar g inp` is `apply_ty(g, inp)`, a
dispatch over every label of that type. One `bindLam` per instance:

```mlir
idr.func @bindLam_ab(%env: !idr.ctor<!G_b,@Bind_ab>, %inp: !Input) -> !PR_b {
  %act  = idr.field %env [0] ...                  // a view: grammars are persistent
  %next = idr.field %env [1] ...
  %r1 = idr.call @apply_a(%act, %inp) ...          // non-tail
  %r = idr.match %r1 : !PR_a -> (!PR_b) {
  case @Failure(%c: !idr.ctor<!PR_a,@Failure>, %com: i1, %fat: i1, %errs: !E) {
    // after counting: a take (r1 is fresh, so exclusive) and a recycle
    // of its cell as a Failure of PR_b: same layout, tag only
    idr.yield %f : !PR_b
  }
  case @Res(%c: !idr.ctor<!PR_a,@Res>, %inp2: !Input, %v: !WB_a) {
    %val = idr.field %v [0] ...                    // v is used again: a view
    %g  = idr.call @apply_next_ab(%next, %val) ...
    %r2 = idr.call @apply_b(%g, %inp2) ...         // non-tail
    %m  = idr.call @mergeWith_b(%v, %r2) ...       // takes r2 apart, rebuilds Res in its cell
    idr.yield %m : !PR_b
  }
  }
  idr.return %r : !PR_b
}
```

The component is every `apply_ty` and every label reachable from them: M
members over R result types (every syntax type Idris's grammar returns).

**Counting, under each shape.**
- Grammars are built once (`noNewtype`, `Core.idr:59-61`): their cells
  are persistent. Borrows marks `act`, `next`, `g` borrowed in every run:
  no count per run; a grammar at top level is static (08 T1): no count at
  all.
- The input is threaded once except at `<|>`, which keeps `inp0` for the
  second alternative: one dup per alternative tried.
- `r1` is fresh: exclusive. The Failure arm recycles its cell for the
  `PR_b` failure (needs by-layout tokens, §2). The Res arm's token is
  dropped (holding it across two calls is frame-limited but buys
  nothing here). `mergeWith` takes `r2` apart and rebuilds `Res` in its
  cell, writing only the bounds (reuse specialization, 5.10 A7).
- Every match's rejoin is the function's return: nothing follows any
  match. Regions express every decision above; join points add nothing in
  direct style; blocks lose the case scopes and gain nothing.

**Under frames** (`Frames.cpp:4-48`, read). Each non-tail run in the cycle
becomes a push of a frame and a tail call of `apply.run`; each rest is a
case of a resume. Counting then sees a push (a fresh cell) and a pop (a
take in the resume's case, exclusive if the stack is proven threaded
once). The rest after a pop pushes the next frame in the same case
region, so drop-guided reuse recycles the popped cell: the frame frees
itself, under regions. Frames knows the stack is threaded once; it
should write `!idr.lin` and `!idr.excl` on it (§2 item 6) so that no test
and no proof is needed.

**What blew up, and why** (16005000, read; perf-sources M2, C9). Frames
cloned every member's body once per member-and-result-type pair and
restamped every frame's rest into every resume: M × R bodies, 336 s and a
43 GB kill. 16005000 made the answer one sum: M runs, R resumes, each
rest once. What is left is regions, R·(F+1) + M·R (10 §2.3), which
per-type stacks make F + R + 2M (10 D2). The same shape walled exclusivity
(per pair of terminator and successor, e96bb991) and the marking
(ffa91113): a fact per pair of program quantities. None of the three is
a property of regions; each was a client of them.

**What representation decides here.** (1) Instances keyed by
representation, not type (the owner's item 5): `ParseResult ty` differs
across ty only in `WithBounds ty`'s value field, a pointer for every
boxed ty, so R collapses to the few layouts the grammar returns (pointer,
i64, i32, i1, unit), and M with it (conjecture: measure M, R, F at stage
1, 10 §8). (2) With join points, frames reads the rest of a block as a
join region: its fields are the region's live-in, not a walk of the rest
(the O(rest²) `madeInRest`, 10 Q-W6). A frame is a join point that
escaped, defunctionalized as a closure is.

## 9. Stress test 2: the owner's CPS parser

```idris
record Parser a where
  constructor MkP
  run : {0 r : Type} -> String -> Int -> (1 k : Res a -> r) -> r
data Res a = Ok a Int | Err Int
MkP p >>= f = MkP $ \s, i, k => p s i $ \res => case res of
                Ok x j => run (f x) s j k
                Err e  => k (Err e)
```

**After defunctionalization.** Every call is a tail call; there is no
frame and no answer sum (every parser of a component returns the same
`r`). Continuations of type `Res a -> r` form one sum `K_a` per answer
type `a`: `KBind_ab(f, s, k')` with `k' : K_b`, `KAlt(...)`, `KTop`.
`apply_K_a(k, res)` dispatches on `k`. Recursive grammars (`many`, a
nonterminal that names itself) chain `KBind` cells: the parse stack, on
the heap, as the program built it.

**The path, step by step.**
1. *Frontend*: `r` is quantity 0, so no value; `k` is quantity 1, so its
   type is `!idr.lin<K_a>`; `Res`, `Parser` are data types. The
   consumption index of a Grammar-style parser (item 4) is quantity 0:
   no field.
2. *Monomorphization* keyed by layout: one `>>=` per layout of `a`, `b`
   and `r`, never one per closure argument and never one per value of the
   erased index. `f` is a closure-sum value, not an instance key.
3. *Defunctionalization*: labels per flow set (MLton M4), applications as
   dispatches. Linearity survives: `K_a` values stay `!idr.lin`.
4. *Optimizer*: inline known labels. When `run (f x)` meets a known
   parser, its dispatch folds and its body is inlined; the continuation
   it builds meets its applications in one function. Each application of
   a known `KBind(...)` is a dispatch on a known constructor.
   - one application: the constructor folds; nothing is allocated.
   - several tail applications (both arms of a character test; both
     alternatives of `<|>`; a `k` reached from the leaves of an inlined
     `<|>` nest): join-point formation (§6) makes one join region; each
     application a jump with the captures as arguments. Never allocated,
     never copied.
   - an application across a recursive call (the continuation passed to
     `many`'s recursive run): it escapes into that call; it stays a heap
     cell.
5. *Counting*:
   - a join point's captures are join parameters: `s` a borrowed
     parameter (its owner is the parse's caller), `i` a word, `k'` owned
     and linear, moved. No count anywhere on the path.
   - a heap continuation is applied once: `apply_K` takes it apart. If
     the marking proves the cell exclusive (built fresh by `>>=`, passed
     through tail calls, never dup'd; linearity alone does not prove it,
     §4), the take moves the fields with no count and yields the cell as
     a token. After inlining, the next `>>=`'s push sits in the same
     case region, so the token is recycled: a frame that frees itself.
     Where a caller passes a shared continuation, grade specialization
     sends that call to the counting copy.
   - `s` captured in a heap cell is an owned field: a dup per push and a
     drop per pop. Keeping it borrowed there needs a field whose
     referent outlives the cell: a scoped lifetime in the grade, DP-16's
     question (synthesis A's "locality" parameter). Regions and join
     points give that scope (the parse's extent); blocks would need it
     rebuilt from dominance. A static string (a literal) is static (08
     T1) and never counted.
   - `<|>`'s backtracking saves `i`, a word: nothing to count.
   - `Res` values built at a leaf and matched by the continuation fold
     when both are inlined; otherwise a fresh cell, exclusive, taken
     apart, its token reused by the next `Res`.
6. *Tail passes*: a self tail call of a nonterminal is a loop (a recursive
   join point); TRMC is not needed (no constructor waits on a result).
7. *Lowering*: `idr.match` to `scf.index_switch`, `idr.join` and jumps to
   blocks, `convert-scf-to-cf`; tail calls on cycles `musttail`
   (idr-tail-calls).
8. *LLVM*: SimplifyCFG, jump threading, GVN and the register allocator
   across join blocks. The grammar becomes jumps between blocks within a
   nonterminal and calls (tail calls on cycles) between nonterminals:
   what a hand-written recursive-descent parser compiles to.

**Item 4, termination.** `many` needs a consuming parser; Idris's index
says so, at quantity 0, and costs nothing. Whether `total` is honest is
the Idris side's: the fork's shallow `Grammar` trusts five
`assert_total` (§4). An honest form indexes the input by its length and
has a consuming parser return a shorter one, so the checker sees the
descent (the skill's `SizeAccessible`), with no fuel and no trust.

**The coordinator's working view, tested.** "A linear, non-escaping
continuation called in tail position is exactly a join point": holds,
with two conditions the code must check. Linearity gives "once per path",
not "non-escaping": a linear `k` captured in another closure or passed to
a call escapes. And the producer and every application must be in one
function, which only inlining makes true. "Reuse tokens could cross a
rejoin as typed join arguments": holds, with the token keyed by layout
and the no-token path sent to a specialized copy rather than a null.

## 10. Performance reasons for a lossy step

| reason | the fact a CFG step would lose | verdict |
| --- | --- | --- |
| contification | the function's body as a scope | needs a shared continuation, which join points give (§6) |
| merging identical arms (`mergeIdenticalBlocks`) | which case each arm is | a match canonicalization merges identical case regions into the default or a multi-tag case; no CFG needed |
| tail position | the chain of tail matches | one fact per call (10 D1); the same under regions |
| a 30,000-case match | its regions | regions need no dominator tree (each case one block); a terminator with 30,000 successors needs one over 30,001 blocks (03 Q-W3, unmeasured); lowering makes LLVM's switch either way |
| loops | the loop's body as a scope | a recursive join point is the loop; upstream's `scf.loop` when it lands |
| LLVM's CFG | nothing: the lowering hands LLVM blocks | after counting and the tail passes, no proof reads scopes |

No reason survives for blocks before the lowering: their one gain,
sharing, is what join points add.

## 11. Unknowns, and the cheapest experiment for each

1. *Whether upstream's early exit lands, and in which encoding.* Read PR
   #166688 and its tests against the token design; build it on a scratch
   copy of the pin (the owner's machine: this lane builds no LLVM).
2. *How many continuations at stage 1 are join-point candidates.* Count,
   in the optimized stage-1 module, the closure constructors whose every
   use is a tail application in the same function, against those that
   escape.
3. *The code growth of key specialization of join regions.* Count join
   regions with an exclusive-or-not split and their sizes on the suites.
4. *The cost of a nested jump at the pin's conservative modelling.* SCCP
   precision lost on join parameters: compare constants found with the
   jump edges hidden and shown, on the suites.
5. *M, R and F of bindGrammar's component*, under type keys and layout
   keys (10 §8, measurement 13 of synthesis C).
6. *Whether placement with jumps from depth keeps every self tail call*
   (08 §8's open question, now for jumps too). The reverse walk on a
   fixture of nested jumps and the live-cell differential.
7. *Whether acceptance moves.* Run the refusal fixtures with join-point
   formation skipped by a debug counter: no verdict may change once
   DP-C1 (b) holds.
8. *By-layout tokens and reuse specialization.* A fixture recycling a
   `Node` cell as a `Leaf` and a `KBind_ab` as a `KBind_bc`.
9. *The run-time gain of a join point over a tail call between functions*
   (option 6 of §5.3): a hand-written CPS parser in both forms through
   LLVM, instructions per token.
10. *Shapes not seen here* (deep `with` nests, `Lazy` chains) whose join
    points might nest beyond the token design: the `with` depth in the
    stage-1 TT bounds it.

## 12. Recommendation

**Per segment** (D19, made concrete):

| segment | representation | what it does here |
| --- | --- | --- |
| frontend | regions: `idr.match` with the refined case argument; case blocks emitted in place once the TTC keeps a block's parent | quantities as types; erased values absent; coverage as the empty default |
| defunctionalization | regions; continuation sums per answer layout; `!idr.lin` kept | applications as dispatches |
| optimizer | regions and join points | inlining of known labels; contification (Fluet and Weeks) and join-point formation; case-of-case through join regions |
| counting | regions and join points | the reverse walk with join live-ins; tokens as match results and jump arguments; key specialization of join regions; exclusivity and borrows with jump edges |
| tail passes | regions and join points | TRMC on yields and jumps; recursive join points as loops; frames as escaped join points with per-type stacks |
| lowering | `scf.index_switch`, then blocks through `convert-scf-to-cf`; join ops to blocks | LLVM does the block-level work |

**What it changes in synthesis C.** T3 visits join regions first and
drops before jumps. T4 passes tokens as match results and jump
arguments, keyed by layout. The take's expansion puts the rest in a join
region specialized by the token's presence, not a null re-test (DP-C6).
D2's marking and D3's borrows gain jump edges and join parameters. R2's
key applies to join regions. DP-C1 (b) becomes required. DP-C4: TRMC's
arrivals come from jumps and yields. Frames writes its stack linear and
exclusive, and reads rests as join regions (DP-C8).

**What it changes in synthesis A.** §5.8 is settled: regions with
`!idr.ctor<T,@C>`. New, in the Idris specification (D16): `idr.join`,
`idr.jump`, `!idr.cont<...>` with its operand-only constraint; the token
type keyed by layout, carrying its source constructor for reuse
specialization. `idr.match` and `idr.match_lit` implement
`PropagateControlFlowBreak` and `idr.join`
`HasBreakingControlFlowOpInterface` once the backport is carried.

**What the cutover deletes** (each with its replacement in the same
change):
- `Contify.cpp`'s one-call-site rule and its rebuilt `CallCycles` (10
  C-1, C-4): Fluet and Weeks on the program graph.
- The general tail loop's flag payload with poison halves (`Loop.cpp`,
  10 §2.3): recursive join points.
- TRMC's `runningRegions` recount and per-join arrival maps (10 IT-7):
  arrivals off jumps and yields.
- Frames' `held` walk and `madeInRest` (10 FP-2), the resume's impossible
  cases (10 D2).
- Case-of-case's copying of continuations into arms, and the
  `yield-fields` counter-move it fought (c179ab2d).
- Reuses' per-region search and tokens held across calls (07 D4, 08 T4).
- Exclusivity's `unknownFrom` and its share (07 D1).
- The three enclosing-match walks and the `tag` attributes of `field`,
  `take`, `unpack` (03 O-52, §5.2a); the default-binding merges (08
  C-08).
- After the backport: the second tier of §5.4 and idr-lower's own
  lowering of nested jumps.

**For the owner** (D11): carry upstream's unmerged early-exit PR as a
backport now, or model nested jumps conservatively until it merges.
Settled by D25 (2026-10-21): carried as a patch now, with every
dependency fast-forwarded to latest; the conservative modelling is never
built.

## 13. Sources

- Ours: `proposals/0000-mlir-native.md:146-325`; `AGENTS.md:270-297`;
  synthesis A, B, C; lanes 03, 07, 08, 10; wave 1 §5.4, §5.8, §5.9,
  §5.10; `design/{perf-sources,typed-effects}.md`; `IdrMatchOps.td`,
  `IdrOwnershipOps.td`, `Pipeline.cpp`, `Tail/Frames.cpp`,
  `Optimize/Contify.cpp`, `Ownership/Placement.cpp`; the fork's
  `Libraries/Text/{Parser.idr,Parser/Core.idr}`, `Parser/Rule/Source.idr`
  and upstream's `Core.idr`; commits 16005000, b0b9fbe2, c179ab2d,
  1b2e31da, 360db182, a4f2174d, e96bb991, ffa91113.
- MLIR at the pin: `Interfaces/ControlFlowInterfaces.{td,h}`,
  `Dialect/SCF/IR/SCFOps.td`, `Transforms/Utils/{CFGToSCF,RegionUtils}.cpp`,
  `Analysis/DataFlow/DeadCodeAnalysis.cpp`. Lean 4 (541dbdcd):
  `LCNF/{Basic,ExplicitRC,ResetReuse,ExpandResetReuse,InferBorrow}.lean`.
  Koka: `Backend/C/{Parc,ParcReuse}.hs`. Modular: `HLCFDialect/
  {HLCFDialect,HLCFInterfaces,HLCFOps}.td`, `KGENPasses.td`.
- Upstream discussion (web, read 2026-10-21):
  <https://discourse.llvm.org/t/rfc-region-based-control-flow-with-early-exits-in-mlir/76998>;
  <https://discourse.llvm.org/t/eurollvm-2026-round-table-summary-early-exit-from-mlir-regions/90555>
  (PR #166688).
- Papers: Maurer, Downen, Ariola, Peyton Jones, "Compiling without
  continuations", PLDI 2017, doi:10.1145/3062341.3062380 (recalled);
  Fluet and Weeks, "Contification using dominators", ICFP 2001 (via
  5.9 E1); Reinking et al., Perceus, PLDI 2021, and Lorenzen and Leijen,
  frame-limited reuse, ICFP 2022 (via 5.10); Ullrich and de Moura,
  "Counting immutable beans", IFL 2019 (via Lean's sources); Bahmann et
  al., TACO 2015 (via `CFGToSCF.cpp`); Kelsey, "A correspondence between
  continuation passing style and static single assignment form", 1995
  (recalled).
