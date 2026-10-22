<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 synthesis G: the coordinator's decisions (draft)

The coordinator's decisions on DP-22 to DP-84 of `F-decisions.md`, in its
order and grouping; once reviewed, the proposal's "coordinator decisions"
section, each entry open to the owner's review. Bound by the owner's
rulings of 2026-10-21 (R1 templates and concepts; R2 compile-time facts
from the one TableGen source; R3 one effect system; R4 hard cutover,
upstream first, representation first; R5 P0 first, honest solvers, no
code before the plan) and AGENTS.md's bullet of that day, cited as **the
static-fact rule**: no fact known statically, or that an earlier stage
knew or could have kept, is paid for when the compiler or a program runs.
Citations as in F; "D-M6" is synthesis D §7's M6. "Confirmed by M": the
decision stands unless M, taken at its step, contradicts it. Newer than
F: 0be4e660 and 1e1907ab repaired `Positions`, main is at 470/480, and
DP-06 is no longer urgent; it remains the owner's.

## Process and records

**DP-22. How each step lands.**
*Decision:* A step lands on the commit that builds on the four targets
(one not yet buildable named as not run), fails no test that passed at
the start (470/480), passes the invariant set unchanged (907 program-test
cases, 47 rejects with `near/` neighbours, 144 `semantics@` runs, 30
benchmarks' outputs, the fuzz seeds) and leaves a stage-1 record; a
receding frontier fails it. WIP commits stay as the lanes README allows
(they build, the new path unreachable) and land nothing.
*Reason:* AGENTS.md: done when it builds and passes on all four; 101edbc5
landed unrun and measured 403/480 (21 P-16); 20 L2.
*Closes:* hist-Q2, T-Q1. *Deletes:* type-checked, unbuilt landings.
*Depends:* DP-05 (whom it binds); DP-07 (with no per-step stage-1 runner,
the record and the frontier gate move to milestones).

**DP-23. The frontend's mirror moves with the `.td`.**
*Decision:* Each `.td` change lands in one commit with the Idris side it
regenerates (modules, Emit's call sites, registry rows); no shim.
*Reason:* AGENTS.md: two hosts, always; a `.td` change the frontend names
breaks its build otherwise, and a shim is a second copy (14, 15, 17 §6).
*Closes:* Q3. *Deletes:* the compatibility-layer option.
*Depends:* DP-22; the step size is returned (below).

**DP-24. Measure before adopting, patch before dropping.**
*Decision:* P0's §4 and §7.3's gates: an upstream mechanism is adopted,
kept or removed only on a measurement at stage-1 scale (or the scale
fixtures: a 20,000-case match, 65,536 labels), and removed only after its
upstream patch was tried or the state is shown essential.
*Reason:* Lanes 20 (L1), 21: 595ed341's adoption and the ffa91113 and
16005000 drops would each have failed it.
*Closes:* hist-Q1. *Deletes:* adoption on a fixture, a drop on a kill.
*Depends:* DP-07. Its AGENTS.md wording is returned.

**DP-25. What P0 leaves out.**
*Decision:* Equality saturation and static reflection are out; nothing
waits on them; static facts come from TableGen (R2).
*Reason:* No wall came from phase ordering (04 §6); reflection at the pin
is `^^` behind a cc1 flag (§5.5 D9) and arrives with the pin.
*Closes:* QL5, cxx-Q5. *Deletes:* the egg snapshot. *Depends:* none.

**DP-26. Ports from Modular, CIRCT and IREE.**
*Decision:* No more ports: fresh code from their shapes, to R1's line.
The deduplicator port is retired by partition refinement over upstream's
`OperationEquivalence` (06 T4, with a patched symbol hook), merging
duplicates inside cycles, each class keeping its first in symbol order.
*Reason:* Little of the port remains; `SCCGraph` lacks insertion and
merge (05, 06 §6); Modular's CRTP has no concepts; the cycle exclusion is
a coordinate error.
*Closes:* Q-M4, Q-E4, defunc-Q1. *Deletes:* heights, waves, the cycle
exclusion, `Reading`, `BodyHash`, `BodyEqual`, per-op dictionaries (06 T4;
U-1 to U-13); the port's `PINS.md` entry.
*Depends:* DP-24, DP-34; refinement rounds measured at stage 1 (06 §8).

**DP-27. Renames.**
*Decision:* Every name is open: mnemonics (the 46 unprefixed get
families), `con`, `dup`, `drop`, the namespace, pass names, idr-expect's
82 property names. Renames land last, in their own step (03 §5.5); a
property is restated over declared facts in the step that changes them.
*Reason:* §1's "every rename it needs" and R4; the Idris side spells no op
name (14 §6); a frozen test API keeps names of deleted facts (02 §8).
*Closes:* DD-Q8, T-Q3. *Deletes:* unprefixed mnemonics; properties over
deleted facts.
*Depends:* DP-28. A rule's phrase is a reject's expected output, so its
rename is that step's only change to the invariant set.

**DP-28. Rewriting the fixtures.**
*Decision:* A fixture stating behaviour becomes a program test whose
module no dialect change touches; one stating a pass's property, an
idr-expect property over a program test; one matching op sequences, SSA
names or order is deleted, not restated. The rest is renamed once by a
script that is not kept.
*Reason:* AGENTS.md: tests check behaviour, and a brittle test is deleted;
339 fixtures hold 26,025 names (19 §6).
*Closes:* T-Q2. *Deletes:* brittle fixtures, the 260 prose
`expected-error`s (19 T4), reference IR copied from output.
*Depends:* DP-27.

**DP-29. Snapshots for `sources/`.**
*Decision:* Approved, amended: 5.7's items 1 to 15 and 17 are fetched,
verified and recorded with licences in `sources/INDEX.md`; item 16 (egg,
egglog) is dropped. *Reason:* DP-25; the rest bear on chosen designs.
*Closes:* QL6. *Deletes:* the planned egg collection. *Depends:* none.

**DP-30. Two upstream RFCs.**
*Decision:* Recorded, to be sent separately: a call graph maintained in
place with callers, dense ids and SCCs. The dataflow-scope RFC is not.
*Reason:* AGENTS.md: a written plan, sending separate; `CallGraph` has no
callers or dense ids, `eraseNode` is O(nodes) (05 T5.1); no solve of ours
wants a per-SCC framework scope (05 §6).
*Closes:* Q-E5. *Deletes:* nothing. *Depends:* DP-52.

## Effects and rules

**DP-31. A closure's allocation.**
*Decision:* `closure`, `suspend` and `delay` declare their allocation as
`con` does: one row of the effect source says every op that makes a cell
allocates, so CSE merges none.
*Reason:* R3: one rule, no exception among cell makers (02 T3); it fixes
B5 (the allocation test misses `delay`).
*Closes:* eff-Q3. *Deletes:* `Expect/Allocation.cpp:28-33`'s hand list.
*Depends:* DP-03, DP-04 (the tree's heap node).

**DP-32. Quantity 1 at the boundary.**
*Decision:* `!idr.lin<i64>` stays a type on words. The translation keeps
Idris's proof (a rewrite that would use a quantity-1 binder twice binds it
instead); Emit reads quantities, never counts uses; a quantity-1 binder
used twice reaching Emit is an internal error.
*Reason:* AGENTS.md as written ("No pass may drop what Idris proved");
the static-fact rule forbids Emit re-counting Idris's proof (FB-28's
quadratic `mostUses`); the other options need AGENTS.md amended.
*Closes:* DD-Q1, Q-FB2. *Deletes:* `mostUses`, `heldAs`, `holdFor`
(`Emit/Bodies.idr:48-138`, `Emit/Declarations.idr:45`).
*Depends:* confirmed by D-M6 (where and how often Emit demotes today).

**DP-33. Budgets, and the compiler running out.**
*Decision:* No budget in an analysis a refusal rests on, named exactly:
the frontend's profile, growth check, reachability walk and `Finite`; the
label solve and defunctionalization; idr-knots; exclusivity with
idr-demand. Others may stop at a budget in program units, pessimistic,
never an error; `maxNumRewrites` is k times the function's ops, k a
`Passes.td` constant (canon tests keep `test-convergence=true`). Out of
memory, the compiler ends through one handler with a named line.
*Reason:* AGENTS.md's budget paragraph; every lane finds the code on the
line; `kNoLimit` let c179ab2d hang (04 C60); time or byte budgets break
stage 2 = stage 3 (09 §6).
*Closes:* Q-llvm-2, Q-E3, oom-2, canon-Q2. *Deletes:* `kNoLimit`
(`Pipeline.cpp:28-32`, `Optimize.cpp:64-66`); LLVM's default abort.
*Depends:* DP-11.

**DP-34. Determinism across thread counts.**
*Decision:* Byte-identical output at any thread count is required, tested
whole as today and per solver (frozen answers at one thread and many, in
the unit-test boxes, on `LabelsLeast`'s shape).
*Reason:* The tool promises it (13 §6); nothing the agent added is tested
at two counts (21 §6.1).
*Closes:* QL4, Q-llvm-6. *Deletes:* OPT-48's lock-ordered request chain.
*Depends:* none.

**DP-35. The `Faster` rule as a test.**
*Decision:* Each program is compiled by the shipped frontend and by a
test-only build whose registry omits the `Faster` hooks; exit, output and
refusals are compared. Hooks are indexed by kind (`Contract | Faster |
Stricter`), so a `Faster` hook on a bodiless definition cannot be written.
*Reason:* A rule nothing checks drifts (D §4 row 12); the registry is a
value, so the seam is a build, never an option of the shipped tool.
*Closes:* ids-Q6. *Deletes:* `Faster` on bodiless primitives (14 R15,
R16). *Depends:* none.

## The dialect's representation

**DP-36. Facts into types and the IR.**
*Decision:* Every fact a later pass reads is written by the pass that
proves it into a type or a verified inherent property; no side table
crosses passes. Summaries (effects, parameter grades, DP-38's facts) live
in the IR, checked after every pass against their derivation (R3); a
cached analysis holds only what one pass reads.
*Reason:* Lanes 01, 06, 07, 08, 11, 15, 17; the static-fact rule names a
summary solved, dropped and solved again (Returned), and a cache dies at
every invalidation.
*Closes:* Q-O3, Q-E2. *Deletes:* the optimizer's facts that die with its
run (gives-back, binding times, inline facts: 09 §6).
*Depends:* DP-09. The data type's form (DS3) is returned.

**DP-37. Case regions bind the refined scrutinee.**
*Decision:* Each case binds its scrutinee at `!idr.ctor<T, @C>`; `field`,
`take`, `unpack` take that type and lose `tag`, so a read of the wrong
constructor cannot be written.
*Reason:* Lanes 01, 03, 04, 07, 08, 15; the frontend knows the value (15
§6); the static-fact rule: enclosing-match walks re-derive it.
*Closes:* QL2, ops-Q1. *Deletes:* the `tag` attributes, two of three
enclosing-match walks, `readField`'s scan (04 T6, C10), counting's undo of
the default's rebinding.
*Depends:* DP-15 (a region's or a successor block's argument; same type).

**DP-38. What `idr.func` and `idr.call` carry.**
*Decision:* Our function and call ops stay, carrying the generated effect
summary (R3) and three facts written by the passes that prove them and
checked against the callee in `verifySymbolUses`: tail position, the
callee's conventions, "gives back argument i"; lowered onto `llvm.call`.
*Reason:* Lanes 03, 05, 08, 10: `func.call` has no effects interface or
property (03 §6); the static-fact rule names the Returned re-solve.
*Closes:* DD-Q7, tail-Q1, count-Q4, Q-AN1. *Deletes:* `IR/Tail.cpp`'s
climb, `TailPosition.cpp` (seven tail readers), the whole-module Returned
solve (10 D3), four deciders of "a tail call on a cycle".
*Depends:* DP-02 to DP-04; DP-14 (an unhonoured tail fact: internal error
under "meaning", statistic under "performance"); DP-15.

**DP-39. The grade's form.**
*Decision:* One closed `#idr.grade` attribute with constexpr methods:
quantity and permission two ordered enums, lifetime static < heap <
frame, so `fitsIn` is `<=` and join `max`; no interface. `Plain` is two
cases, undecided (legal only before counting) and no-reference. The
frontend's generated view offers only the grades it writes.
*Reason:* Six (quantity, permission) pairs occur (01 C1, NQ3, NQ4); the
skill forbids an interface the type fixes; R2; the static-fact rule
forbids reading the stage to learn what `Plain` means.
*Closes:* types-Q4, types-Q3. *Deletes:* the grade's free functions,
`Idr_LifetimeParam`, the stage reads (`Grades.cpp:80-91`,
`Program.cpp:222-228`), DS1.1's interface.
*Depends:* DP-10 (upstream's tensor-like interface sits on this type);
DP-16 (symbolic lifetimes add a parameter); DP-32.

**DP-40. Who decides layout.**
*Decision:* The frontend decides representations: one-field collapse,
`!idr.nat`, pointer-like `u64`, crash enumeration, and the boxes that
break cycles, so `DataTableAttr::verify` refuses an in-place cycle once;
defunctionalization boxes its closure sums by the same rule. Byte layout
stays the lowering's, from the module's data layout.
*Reason:* AGENTS.md: the Idris side "decides representations" and holds
the whole table (01 NQ2); the static-fact rule: `layout::fit`'s
whole-program remap re-derives what the frontend could keep.
*Closes:* ft-Q1, types-Q2. *Deletes:* `Layout/Fit.cpp`, the second remap
and `TypeGraph` walks (06 T5), `Term.idr:110-112`'s comment.
*Depends:* DP-09, DP-48.

**DP-41. Signedness.**
*Decision:* arith's school: signless types, sign on the op where the
computation differs; `shls`/`shlu` become one `shl`.
*Reason:* Dialect, folds, lowering, emitter, runtime are there already.
*Closes:* DD-Q4. *Deletes:* the shift pair; `signed : IntTy -> Bool` (15
TY-2). *Depends:* DP-17 (`divu`/`modu`).

**DP-42. Ops, runtime functions and base primitives.**
*Decision:* One op per operation, its variant an ODS enum (`io.clock
<kind>`, the file times, the crash cause); the generated ABI row is keyed
by (op, case) at the compiler's build, and the runtime's entries are
explicit instantiations of one template over the case, so nothing picks
the case at run time. The registry stays the one place naming a base
primitive; its rows' other facts are generated from ODS.
*Reason:* R2 and the static-fact rule: a function switching on a kind
each call site fixes pays at run time for a static fact; separate ops
restate one operation; the dialect names no Idris library.
*Closes:* DD-Q5, ids-Q5. *Deletes:* the per-clock and per-time ops, the
generator's refusal of an enum (14 T28; 12 CV-53), hand arities.
*Depends:* DP-02, DP-17, DP-18 (statuses per cause), DP-69.

**DP-43. Output: fuse or compose.**
*Decision:* Canonical output composes a pure `show_*` and one `put_str`;
the lowering emits the allocation-free entry for `put_str(show_* x)`.
*Reason:* Values and memory at different levels; four effectful ops
leave the effect source; by the static-fact rule a `show` of a known
value folds at compile time, where `put_sint 42` formats at run time.
*Closes:* canon-Q3. *Deletes:* the four `put_*` ops, canon's fusion
(`Output.cpp:107-133`).
*Depends:* DP-42; a test that each `put_*` writes `put_str` of `show_*`.

**DP-44. Is a link an op?**
*Decision:* One op per kind: entering a linear array is a link (in place,
always) or a head (may copy), chosen by the translation, which knows;
bufferization confirms the op, never re-proves it.
*Reason:* One op per semantics; the static-fact rule: `isLink` re-proves
per query (`Linear.cpp:32-50`) what the frontend had.
*Closes:* arr-Q2. *Deletes:* `isLink`'s per-query state (11 I-BU15).
*Depends:* DP-10 (under 0009's stage 2 the check stays as the promise).

**DP-45. Transposition as a tabulate.**
*Decision:* `idr.transpose` goes: the frontend writes a tabulate whose
read is the permutation, carried as its indexing map, written once by the
frontend and handed to linalg, never recovered.
*Reason:* One form for one thing (11 C2), 0009 §3.1's map kept; the
static-fact rule forbids recognizing again what `Emit/Tensors.idr`
computed.
*Closes:* arr-Q4. *Deletes:* `TransposeOp` and its arms in `Forms`,
`Linalg`, `Nests`, `TransposeColumns` (11 I-SL9, 10, 16, 26; I-TD3).
*Depends:* DP-10: a tabulate carrying maps is 0009's MLIR form; left to
0009, the deletion moves with it (`readsOf` would re-derive the map).

**DP-46. Frames' stack per result type.**
*Decision:* One stack type per member result type of a recursive group,
so a frame of another type on top cannot be built.
*Reason:* 10 D2; the static-fact rule: default regions for states the
types exclude.
*Closes:* tail-Q3. *Deletes:* the R·(F+1) impossible regions.
*Depends:* DP-14, DP-15; a test that idr-knots accepts R mutually
recursive stack types, never tried (10 R-6).

**DP-47. Stages declared in TableGen.**
*Decision:* Each op family declares its legal stages, checked by one
generated trait; the pipeline is one TableGen list (order, reasons,
options, each pass's kind), its stage chain asserted when TableGen runs,
nesting computed from the kinds, generating the textual pipeline, the
registrations and the tests' table.
*Reason:* Declare, don't write; R2; the order is held twice and the copies
disagree (13 DP-01).
*Closes:* ops-Q4, drv-Q2. *Deletes:* the verifier's stage rule, the hand
order and its copy, the harness's awk, the dead `remove-dead-values`
registration (13 DP-16). *Depends:* DP-39, DP-60.

## Defunctionalization

**DP-48. Types first.**
*Decision:* One walk writes the label solve's decision into the types,
legality checked by the stage verifier; no per-function conversion.
*Reason:* The static-fact rule's first example: a pattern per registered
op built per function (70 % of the corpus's samples); `TypeConverter` maps
types, and these follow a flow set (06 NQ-defunc-3).
*Closes:* defunc-Q3. *Deletes:* 06 T1's list (`Plan`,
`SlotTypeConverter`, `RetypePattern`, the rollback, `PatternsCalls.cpp`).
*Depends:* DP-36, DP-40; no casting accessor reads a retyped value.

**DP-49. One sink per operand.**
*Decision:* Kept: a use moving into two points unifies them. *Reason:*
Lane 06 keeps the trade (06 §8 item 7). *Closes:* defunc-Q4.
*Deletes:* nothing. *Depends:* none.

**DP-50. Effects before the conversion.**
*Decision:* No idr-effects pass: the effect system's one summary solve
(callees first over `ProgramGraph`, its transfer generated from the
effect source) runs in defunctionalization's decision over calls and
label runs and decides `by_name`; idr-optimize keeps it current.
*Reason:* R3's single place, computed once and kept (06 T3); IO is found
today by world-typed parameters, a second reading.
*Closes:* defunc-Q2. *Deletes:* `Analysis/Effects.cpp`, the body rule
`Func.cpp:189-202`.
*Depends:* DP-01 to DP-04, DP-52; today's bits on the 16 `effects-*`
fixtures, `by_name` unmoved (06 §8).

## The solver layer

**DP-51. Upstream's dataflow framework.**
*Decision:* Its storage is patched upstream first (P1) and Ranges, Borrows
and Returned measured on it; then it keeps only per-value solves inside
one function: idr-constants, narrowing's Copy, Ranges per function with
callers-first argument summaries. Returned goes with DP-38's fact, its
residue per function; Borrows becomes a marking (DP-53). No P2.
*Reason:* R4 and DP-24; P2 has no client (05 §6); Ranges per function 3 s
against 30 s (11 §6); Borrows is a marking (07 §3.1).
*Closes:* QA1, QA2, Q-AN3. *Deletes:* whole-program Ranges
(`Ranges.cpp:67-76`, `Narrow.cpp:158-165`), Returned, Borrows on the
framework.
*Depends:* DP-07; confirmed by 05 §8 and 21 §8 item 5.

**DP-52. The spine.**
*Decision:* One `ProgramGraph` (on `idr.program`, and on the lowered
module): `FunctionId` minted by it alone, callees and callers in
compressed rows, SCCs bottom-up, built through `CallOpInterface`, kept
current by the passes that edit calls, preserved by name by the rest.
Three solve shapes on one static schedule (`scc_iterator`); the optimizer
its one dynamic client, editing through the graph's API; the giant SCC
serial first.
*Reason:* Lanes 05, 06, 09; the static-fact rule names the call graph
built seven times; `mlir::CallGraph` has no callers or dense ids.
*Closes:* Q-E1, Q-M1, Q-AN2, Q-llvm-7. *Deletes:* `CallCycles`,
`Recursion`, caller-only `SymbolUserMap`s, nine name-keyed maps (05 R9),
`Scc.cpp`'s copies, the optimizer's second walk (OPT-29).
*Depends:* confirmed by stage-1 SCC sizes and idle per wave (05, 09 §8);
rebuilt and compared in test builds.

**DP-53. The solver layer's state and model.**
*Decision:* Shared concept-constrained types (`Id<Tag>`, `IndexVector`
with raw index deleted, `Graph` modelled by `Csr<Tag>` with `GraphTraits`,
`Lattice`, `Summary`, direction a type) and three generic algorithms
(`mark<Dir, Gate>`, `solve<CalleesFirst | CallersFirst>`,
extract-solve-link), each solver one explicit instantiation in its own
unit, reading a read-only view. A function's numbering is one cached
analysis (blocks by MLIR's own), invalidated by change, never maintained
across rewrites. The label solve keeps its rules as data.
*Reason:* No one engine fits (gates, a growing graph, a greatest fixpoint,
relations: B §3.2); R1, R2; the static-fact rule rules out order
recomputed per query or solve, and `Positions` broke by maintenance.
*Closes:* QA4, Q-O2, QL1, Q-llvm-3, QL3. *Deletes:* six numberings and
pointer-keyed solver maps (05 §2.6; 21 P-14), dead worklists (05 WL1,
WL2), `bool backward`, the solvers' callbacks (21 P-19), OPT-22's virtual.
*Depends:* DP-06 (a kept `Positions` becomes this analysis's code), DP-05
(the agent's markings move here), DP-15.

**DP-54. `remove-dead-values`.**
*Decision:* It stays out. Dead parameters are a demand bit in the
optimizer's summary, the callee narrowed before its callers run (09 T5);
dead results, one callers-first pass; a function a closure label names
has an unknown caller. Patches 06, 28 and 63 are retired now.
*Reason:* AGENTS.md: a patch goes when nothing reaches its bug; eight
patches, two silent miscompiles (20 §6); a bit computed once.
*Closes:* QA3, Q-opt-4, hist-Q3. *Deletes:* the three patches, their
`PINS.md` entries and `upstream/` directories.
*Depends:* DP-38, DP-52, DP-64; confirmed by unread parameters left at
stage 1 (21 P-9).

## Counting

**DP-55. How much exclusivity is static.**
*Decision:* One marking proves what it can (R1), and grade copies (R2: one
per function, key "every followed parameter exclusive") make more static,
made inside counting, where grades exist, by the optimizer's own
clone-and-key template. The run-time test stays only where exclusivity is
unknown until run time, and its code says so.
*Reason:* AGENTS.md: linearity is performance, a lawful fallback; the
static-fact rule wants all a copy can make static; idr-optimize runs
before grades exist (09 §6).
*Closes:* rc-Q2, own-Q3. *Deletes:* counting's own cloning code.
*Depends:* DP-12 (no promise rests on a copy), DP-13 (what "followed"
means); measured by copies and counts saved at stage 1.

**DP-56. Drops at last use.**
*Decision:* Confirmed, with the problem's four exceptions (a loop holding
an outside value, a crash region, a borrowed argument, a tail call in a
cycle); no lexical lifetimes. *Reason:* No destructors (08 §6).
*Closes:* rc-Q5. *Deletes:* nothing. *Depends:* DP-13.

**DP-57. Counting before or after TRMC.**
*Decision:* Counting first; "tail modulo cons" is decided once and written
on the call (DP-38) before counting, read by Borrows, executed by
idr-trmc.
*Reason:* TRMC works on counting's `cell.init` and keeps the recycled
cell (10 §3.1); a carried fact replaces a prediction (static-fact rule).
*Closes:* count-Q3. *Deletes:* Borrows' prediction (08 C-81, T16).
*Depends:* DP-13, DP-14, DP-38.

**DP-58. The take's expansion.**
*Decision:* Counting's last step at the `idr` level: `idr.is_unique`
folds to true on `!idr.excl` and false on a frame value, moves and counts
as IR; the lowering lowers primitive ops only.
*Reason:* The static-fact rule's named case (08 C-76; 12 CV-30, CV-32);
no lane argues for the lowering (C §3.1).
*Closes:* conv-Q3. *Deletes:* the lowering's uniqueness branches, the
exclusive drop's count read, the `Fields` table (12 T3), the runtime's
stack-bit test (18 R-RC-3).
*Depends:* DP-12, DP-55, DP-15; the owned verifier states the unique arm.

**DP-59. The count: threads, shards and encoding.**
*Decision:* No counted cell is ever shared between threads (no atomic
count, no mark-shared pass); shards pass cells by detach, as 0007 has it.
The count takes Koka's signed encoding without atomics (0 unique,
negative sticky), "count 0 is persistent" moving to the sticky constant.
*Reason:* AGENTS.md puts threads outside the language; with `Static` in
the grade (08 T1) the sticky test is only for facts unknown until run
time.
*Closes:* rc-Q4, rt-Q1. *Deletes:* `count == 1 && !stack`.
*Depends:* DP-55; the encoding confirmed by 18 §8 (instructions per
`inc`, `dec`).

## Verification and the pipeline

**DP-60. Verification after every pass, at 70,000 functions.**
*Decision:* Full verification after every pass in every build, cheapened
by nesting as a rule: decide passes compute a fact and change nothing,
apply passes rewrite functions in parallel, only restructure passes
change the program's shape. The owned rule stays in `idr.func`'s region
verifier; a pass that changed nothing preserves all analyses, so nothing
re-verifies (patches U-a, U-b). Contracts are per-function test records;
the verifier is read from `--mlir-timing`.
*Reason:* AGENTS.md: quantity 1 checked after every pass; a split by build
is a behaviour the build chooses (13 §6); the static-fact rule:
re-verifying what nothing changed.
*Closes:* ods-Q6, Q-M2, Q-O5, types-Q1, drv-Q3, T-Q4, T-Q5. *Deletes:* the
program verifier's serial walks (01 C7a), the contracts' module clone
(19 C7), hand nests (13 §3.2).
*Depends:* DP-07, DP-16 (lifetimes in types move the owned rule), DP-38.

**DP-61. `idr-lower` under the pass manager.**
*Decision:* Two program passes (declare every runtime function, make every
static datum, once), then the lowering as a function pass.
*Reason:* §4: the pass manager does the parallelism; runs cut by count are
unbalanced (12 CV-02). *Closes:* conv-Q2.
*Deletes:* the worker-and-merge scheduler (12 T6).
*Depends:* DP-38, DP-60; 12 T5, T9 first.

**DP-62. Worker stacks.**
*Decision:* Workers run on reserved stacks like the main thread, by an
upstream patch giving `StdThreadPool` a stack size (U-d), sized in the
runtime's platform layer.
*Reason:* R4: patched upstream before a pool of ours; one place per OS;
today depth depends on thread and OS (13 DP-39).
*Closes:* drv-Q4. *Deletes:* OS-default worker stacks, `PINS.md:595`'s
stale 2^40. *Depends:* none.

**DP-63. The prepared runtime's bitcode in one home.**
*Decision:* Beside the object, on every target.
*Reason:* AGENTS.md: per-target cases elsewhere are bugs; the static-fact
rule: a run-time switch on the target entry's fact.
*Closes:* drv-Q5. *Deletes:* `BitcodeHome`, its switch, both CMake
branches, the section path (13 DP-35). *Depends:* none.

## Specialization

**DP-64. Specialization: order and shape.**
*Decision:* The bottom-up schedule stays, what a call reaches one sum
decided at the grant (09 T4), in MLton's order: specialize to completion,
inline once on the final graph with true call counts, normalize.
Polyvariance, if taken, is a C++ pass between deduplication and
defunctionalization under a budget, never the frontend's.
*Reason:* AGENTS.md: a fixed sequence; interleaving took five rules after
five unrollings (OPT-84) and leaves a made node's count unknown (OPT-12);
in the frontend polyvariance widens the growth check, which has no budget.
*Closes:* Q-O4, Q-M5, Q-opt-1, ft-Q3, Q-opt-2. *Deletes:* OPT-84's five
rules, `no_inline`, the per-round interleaving.
*Depends:* DP-52, DP-55; confirmed by code size, compile and bench time
against today, polyvariance only if closure sums shrink (09 §8 item 5).

**DP-65. Keys outside the context.**
*Decision:* Keys are the run's own interned data (a closed sum in an
arena), freed with the pass, no context lock; a debug print on demand.
*Reason:* No op holds a key (09 T3); attributes are never freed and
serialize on the lock (98c6315c; a fifth of samples, 51a4771b).
*Closes:* Q-opt-3. *Deletes:* `Idr_SpecKeyAttr`, `Idr_KeyRaiseAttr`, the
global node-table mutex (OPT-49, 64). *Depends:* DP-36, DP-64.

## Rewrites and tools

**DP-66. DRR allowed, PDLL refused.**
*Decision:* DRR for rooted patterns; PDLL refused; region-reading
patterns stay C++.
*Reason:* R2, the static-fact rule: an interpreted pattern pays at run
time for what the build knew; PDLL has no user at the pin (04 §6).
*Closes:* ods-Q4. *Deletes:* five C++ pattern classes,
`StrBuilderOpInterface`'s partial methods. *Depends:* none.

**DP-67. Canonicalization's place.**
*Decision:* Upstream's pass on the greedy driver, configured once,
`filter-dialects` naming idr, arith, ub and each point's needs, DP-33's
budget, one match view per visit (04 T4), and an upstream patch so a
canonicalize that changed nothing preserves analyses.
*Reason:* R4: upstream, then patched, before a normalizer of ours; the
static-fact rule: patterns tried where ODS says they cannot match
(3a96c407), re-verification after a no-op run.
*Closes:* canon-Q5, canon-Q4. *Deletes:* the second configuration, the
per-visit rescans and string roots (04 C06 to C38, C19).
*Depends:* DP-01, DP-15, DP-33, DP-60.

**DP-68. Canonical forms before defunctionalization.**
*Decision:* A canonicalization runs before defunctionalization, so the
force, suspension and closure forms shrink the label solve's sets.
*Reason:* Hard culling or a live stage (04 T8): a known closure or
suspension is folded at compile time instead of dispatched at run time.
*Closes:* canon-Q1. *Deletes:* the forms' fixture-only status.
*Depends:* DP-64; confirmed by the label solve's P, E, D, distinct sets
with and without (06 §8); a null result deletes the forms.

**DP-69. One TableGen tool, and the handoff.**
*Decision:* Every `idr` type and attribute is native in bytecode, its
encoding generated from ODS (upstream's generator for C++, ours for the
Idris writer); no `idr` text crosses the handoff. Our generator reads
records only through `mlir::tblgen`'s wrappers, a binary of its own on
`MlirTblgenMain` beside `mlir-tblgen`.
*Reason:* The static-fact rule: a known fact as text parsed back; the
owner: "we cannot have the binary format be read by hand" (20 §5.3); two
binaries over one record set are not two copies (14 §3.1).
*Closes:* Q-llvm-5, ids-Q3. *Deletes:* the copied format parser, the
Idris printers, the hand record switch (14 B04), raw record reads and
string compares (14 T05 to T19), decimal doubles (X01).
*Depends:* DP-23; DS3 (returned); the text share measured first (14 §8).

**DP-70. Properties the frontend writes.**
*Decision:* Each op's property encoder for the Idris writer is generated.
*Reason:* Otherwise ODS bends around a generator's gap; follows DP-69.
*Closes:* ids-Q2. *Deletes:* properties as attributes (14 B11, T23).
*Depends:* DP-69.

**DP-71. Generated Idris modules in git.**
*Decision:* Checked in, fingerprinted over records and output only;
`make check` regenerates them and fails on a difference.
*Reason:* Their recorded purpose (`tools/dialects.sh:26-27`): both hosts
build the Idris side with no other step, and an ODS change shows as the
Idris it means; the churn was the fingerprint's scope (14 T50).
*Closes:* ids-Q1. *Deletes:* the generator-source fingerprint.
*Depends:* DP-69.

**DP-72. Generated binder names.**
*Decision:* Every generated parameter is primed. *Reason:* No copied
keyword list. *Closes:* ids-Q4. *Deletes:* the list (14 T01). *Depends:*
DP-69.

## C++

**DP-73. Variants.**
*Decision:* One exhaustive fold, `match`, over every closed sum of ours,
coverage checked at compile time; `get_if`, `holds_alternative` chains
and `std::visit` banned; `PointerUnion` for pointer-sized handles, read
by the same fold.
*Reason:* R1; past eleven alternatives `std::visit` goes through a table
(11.3 s and 3 MB against 2.0 s and 68 KB, §5.5 finding 12); a size
threshold is a special case.
*Closes:* Q-llvm-4, cxx-Q2. *Deletes:* every chain and `std::visit`.
*Depends:* DP-08.

**DP-74. Precompiled headers.**
*Decision:* A PCH for `foreign/idr` now, of LLVM's, MLIR's and the
standard library's headers and none of ours (`-fno-pch-timestamp`,
ccache sloppiness); no C++ modules in P0.
*Reason:* About 7.5 CPU-minutes of headers against 2.1 (13 DP-55; §5.5
D6); modules were tried and removed; our headers outside it keep a
missing include an error.
*Closes:* cxx-Q3. *Deletes:* nothing. *Depends:* a `-ftime-trace`
baseline first (13 DP-59).

**DP-75. libc++ hardening.**
*Decision:* Extensive hardening stays in every configuration; in
programs a handler routes a failure to the runtime's one ending as a
named crash; release's cost is measured and reported.
*Reason:* It checks facts unknown until run time, which the static-fact
rule allows; dropping it changes what a release promises.
*Closes:* cxx-Q4. *Deletes:* the bare trap (18 R-BD-2).
*Depends:* DP-18; 13 M6 goes to the owner if it shows a cost.

## Frontend and fork

**DP-76. What the fork's TTC gives the frontend for case trees.**
*Decision:* The fork stops building the run-time case tree; the TTC keeps
0003's `scTy` and clause index, read where `Forced.idr` guesses. Once it
keeps a block's parent, a case block is emitted in place in its parent.
*Reason:* AGENTS.md: "Do not replace that input with ... runtime case
trees"; the static-fact rule: a tree built and dropped (FB-38), facts
dropped and guessed back (FB-05, FB-06).
*Closes:* Q-FB1, tail-Q4. *Deletes:* `compileRunTime`'s tree, `Forced.idr`,
`Cases`' guesses (`instanceOf`, `siblings`, `coversAll`).
*Depends:* DP-09 (without 0003 this waits), DP-15; D-M8 recorded first.

**DP-77. Context-sensitive flow as a representation fix.**
*Decision:* If stage 1 shows the node split's products large, the
growth check's flow splits by node, acceptance unchanged.
*Reason:* An acceptance analysis takes no budget, only a representation;
four such fixes took growth from 1,093 s to 67 s (16 §6).
*Closes:* Q-fc-2. *Deletes:* nothing. *Depends:* DP-07, DP-33; D-M9.

**DP-78. The Core dump.**
*Decision:* The module is the one output; the dump goes, its two readers
read the module. *Reason:* A second 79 MB copy (15 TM-9).
*Closes:* ft-Q4. *Deletes:* the dump (15 D-7). *Depends:* none.

**DP-79. A refusal in the fork's `Error`.**
*Decision:* A refusal is a value of the translation's own typed refusal
(rule an enum, site a location), never the fork's `Error` or a side
channel (15 ST-7's alternative).
*Reason:* The fork never imports `IdrisMLIR.*`, so its `Error` could carry
the rule only as text, which the static-fact rule forbids.
*Closes:* ft-Q5. *Deletes:* `TS.inFlight`, the dedupe by printed text.
*Depends:* none.

## The runtime

**DP-80. Stack probes on all four targets.**
*Decision:* Inline probes in every function, the probe size the target's
page from its entry, set by the lowering; runtime and tools built with
`-fstack-clash-protection` everywhere; a guard below the signal stack.
*Reason:* AGENTS.md: never miscompile silently, page size only in the
entry; a large frame lands in the signal stack today (18 R-STK-1, 2).
*Closes:* oom-4. *Deletes:* `Runner.cpp:35-37`'s unchecked claim.
*Depends:* none.

**DP-81. Test hooks in the shipped runtime.**
*Decision:* Shipped programs neither count cells nor read `IDRIS_RT_LIVE`;
the count lives in the checked runtime (a compile-time variant of the
same sources), which the harness links for leak runs of the same module;
the IO test writes past the shipped buffer instead of sizing it.
*Reason:* The static-fact rule names it (18 R-AL-5).
*Closes:* rt-Q2, rt-Q4. *Deletes:* the `thread_local` count,
`IDRIS_RT_LIVE`, `IDRIS_RT_IO_BUFFER_SIZE`. *Depends:* none.

**DP-82. snmalloc's config.**
*Decision:* A seed-range hook as `upstream/<bug>/snmalloc.patch`, applied
by the bootstrap, with report, test and plan (a submission: a CLA); our
config copy goes. *Reason:* R4; a copy drifts.
*Closes:* rt-Q5. *Deletes:* the copy (18 T-AL2). *Depends:* none.

**DP-83. Mangling.**
*Decision:* One prefix on every program symbol, so none is a runtime
symbol or `main`. *Reason:* A collision unrepresentable, not checked.
*Closes:* conv-Q5. *Deletes:* three collision checks (12 T7). *Depends:*
none.

**DP-84. Runtime memory work that can wait.**
*Decision:* Deferred until a program or shard needs them: stack pages
returned, a pressure signal, shards' limits. *Reason:* "Can wait"
(§5.11); one thread, no shards yet (18 §6).
*Closes:* oom-7, oom-8, oom-9. *Deletes:* nothing. *Depends:* DP-11.

## Returned to the owner

No decision point is returned whole. Four sub-questions inside decided
points are the owner's; each decision holds under either answer.
- **DS3, the data type's form** (in DP-36's Q-O3): a contested core shape,
  sealed once (today) against an index into the program's table, which
  strands 147 type-level body reads (01 R3).
- **The cutover's step size** (in DP-23): one commit per op family or one
  for the dialect is the owner's reading of "one total cutover" (E §6).
- **DP-24's rule in AGENTS.md**: the owner's text.
- **Amendments these decisions avoid**: a stated demotion of quantity 1
  (DP-32) if D-M6 shows the translation cannot keep every proof; release
  hardening (DP-75) if 13 M6 shows a cost.

Count: decided 63, returned 0, total 63.
