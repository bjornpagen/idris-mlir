<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 synthesis C: memory and the back end

Cluster C covers counting (lanes 07, 08), tail calls and frames (10), the
arrays stage (11), the lowering (12) and the runtime (18), with what lanes
02, 03, 13, 19 and 21 say about them. Sources: the proposal's §0–§4, §5.5,
§5.8 (effects, consumption), §5.10, §5.11, §6, §8, §9; wave 2's documents
read in full where listed in the brief. Citations: "08 §5 T3" is lane 08's
document, section 5, item T3; "§5.10 A4" is the proposal. Every claim
below is the lanes'; nothing was built or run for this synthesis. Where a
lane says *conjecture*, so does this document.

**Settled by the owner, 2026-10-21 (relayed by the coordinator), and
applied throughout:** "heavy use of templates and concepts pls". Our own
C++ (counting's internals, the lowering's helpers, the runtime's typed
entry points included) is concept-constrained templates by default:
callbacks become templates; a ladder over our own types becomes
concept-constrained overloads or one fold over a closed sum; MLIR op
interfaces stay where the op set is open; a concept may read ODS facts,
never list ops. §8 Q1, Q-M3 and Q-llvm-1 are settled in that direction.
Every change is a hard cutover that culls the old code, churning toward
the most elegant representation. §2's last part writes the target in
those terms.

## 1. In plain words

**What this cluster is.** Everything between "the program is first-order
and optimized" and "a binary runs". Frames and accumulation turn deep
recursion into data or loops. Counting decides where every reference is
copied (`dup`) and released (`drop`), which cells are reused, which live
on the stack, which values are exclusive, and whether a promised in-place
update is honoured. TRMC and tail loops turn tail calls into loops. The
arrays stage turns array ops into linalg, bufferizes, splits records into
columns and narrows words. The lowering turns all of it into func, memref
and LLVM, with one call per runtime primitive. The runtime is the meaning
of every primitive, the cell header, the count, freeing, allocation,
crashes and the stack.

**What is wrong today.** Five things, each a representation problem.
- *Counting derives the same fact several times.* Where a value dies is
  computed three times under three rules (08 §3.1, the M2 row). Whether an
  operand is consumed is read five ways (08 §2.6). Reuse is decided on a
  simulated body before any drop exists (08 C-45, 07 R-01); that
  simulation caused 1088 verifier errors on stage 1 (21 §2.3, 9db9813d).
  Exclusivity is solved twice (08 C-57). Each value's class is rebuilt per
  step (08 C-04, C-05).
- *Static facts become run-time tests or C++ branches.* "Is it unique" is
  a C++ branch in two lowering patterns, not an op that folds (08 C-76,
  12 CV-30). An exclusive drop still reads the count (12 CV-32, 18 R-RC-2).
  Every `inc`/`dec` tests for NULL and the odd bit, though the type says
  what the word is (18 R-RC-1). Tail position is recomputed per query,
  redefined on the LLVM dialect, and "a tail call on a cycle" is decided
  four times (10 §3.1, on §5.9 C3).
- *Whole-program state is still the shape of the next walls.* Borrows runs
  on `DataFlowSolver` over the whole program; `idr-narrow`'s range solve
  and `Returned`'s solve are whole-program too, and stage 1 has never
  reached the last two (21 §3.4; 10 R-1; 11 R1).
- *Facts are dropped at the lowering.* No function fact and no op effect
  reaches LLVM (12 CV-05, CV-14). No stack probes are set, and the 1 MiB
  guard sits directly above the writable signal stack (18 R-STK-1, R-STK-2).
- *Acceptance depends on the optimizer.* The in-place promise binds only
  where reuse happened to recycle the parameter's cell, so skipping an
  optimization can remove a refusal, or add one (08 §6.1 NQ1). AGENTS.md
  forbids this.

**What it should become.** Perceus as MLIR passes (§5.10 R1), on the
grades already in types. Function types are counting's per-function ABI.
One reverse walk per function places dups and drops; drop specialization
and reuse are written into the IR where they are decided. Uniqueness is
one op that folds to true on an exclusive type. The interprocedural parts
(exclusivity, stack frames, borrows) are two-point markings in one honest
solver layer. Consumption is declared once as `Read` + `Free`. The
lowering lowers ops and decides nothing. The runtime gets one entry per
kind of word, counts runs of slots, one ending sum, one out-of-memory
path, and probes from the target's entry. Tail position becomes one fact.
Frames get a stack type per value type. The arrays stage, already the
part closest to upstream, decides each fact once.

In C++ terms (the owner's ruling): one marking template over a graph
concept, instantiated once per marking; one reverse walk templated on its
live set; dense typed ids the graph mints; every closed set of ours a
sum read by one fold; every callback a template parameter; the runtime's
typed core a set of concept-constrained templates whose C entry points
are thin instantiations generated from `IdrRuntime.td`. Each piece lands
as a hard cutover: the old form is deleted in the same change.

## 2. Where the lanes agree

Each piece: what it is, who holds it, what it deletes.

1. **Grades in types are counting's ABI.** Parameter and result grades
   (owned, view, excl, frame) already sit in function types (08 §3.1, the
   R1.1 row; 07 §6 Q-E2). Placement reads only a callee's signature (08
   §3.1, the §5.1 G3 row). Keep it; it is MLIR's ownership-based
   deallocation ABI, written in types (§5.10 G5).
2. **The static lifetime in the grade.** `Lifetime ∈ {Static, Heap,
   Frame}`, written once by the op that makes a persistent value (08 T1,
   07 D6, 11 I-NA5, 12 CV-20; 0003). Deletes `isStatic`'s chain walks, the
   classes `Phantom`, `Constant`, `StaticRead`, and the lowering's
   re-derivation of static data from the defining LLVM op.
3. **The class is the grade.** Once (2) holds, `enum class Class`, the
   `Classes` map and its three switches go; readers read the type (08 T2).
4. **Placement as one reverse walk per function** with the live set as its
   state: dup late, drop early, drop at the head of a region for values
   live only in a sibling (08 T3; §5.10 A1–A3; §5.9 Design 4). Deletes
   `Placement`, the per-region use scans, Reshape's three take-apart
   predictors and the default-binding merges (08 T3). Cost: O(ops +
   regions) per function. 07 D5 and 101edbc5 propose other shapes for the
   query vocabulary; see §3.3.
5. **Consumption declared once.** Every operand that takes over its
   reference declares `MemRead` + `MemFree` on one resource; `dup`,
   `drop`, `take` move off the default resource (08 T7; 02 T3, T6; §5.8
   EF3; §5.2 M2). The five readings become one `hasEffect<Free>` query.
   Which resource is §3.10.
6. **Uniqueness as an op that folds.** `idr.is_unique %x` reads the count
   and folds to true on `!idr.excl`; drop specialization and reuse emit
   `scf.if` on it; canonicalization deletes the shared arm (08 T8, 12 T4,
   18 T-RC4; §5.10 R1.4). A frame value's test folds to false, so the
   runtime stops testing the stack bit (18 R-RC-3).
7. **A token names its cell.** `!idr.token<!idr.box<T>, @C>` (0003),
   inferred by `take`. Deletes four walks back to the take (08 C-72), the
   lowering's `Fields` side table (12 T3, CV-28, CV-29), and the
   exclusive free's re-tests (18 T-RC4).
8. **Reuse specialization in the IR.** Which fields a reuse keeps is
   decided where the take and the init are both in hand, and written as
   IR (08 T4; 12 T3: `idr.cell.update` of the changed fields; §5.10 A7).
9. **Exclusivity a cached analysis, solved once; the commit a nested
   pass.** One solve over a graph with a potential copy per copyable
   function; `shareTainted` becomes an edge kind; the commit reads
   `getCachedParentAnalysis` (08 T5; 07 D2; 13 DP-11; 0003). Deletes the
   second solve and the hand `OpPassManager`.
10. **Three markings, one solver layer.** Exclusivity (gated edges),
    idr-rc-stack and borrows are one monotone two-point marking over a
    CSR graph, instantiated three times (07 D7; 08 T9; §5.10 M6; §5.3 S1;
    §5.5 D3). idr-rc-stack's b8301ebe engine is the nearest start (07 D7).
    The stack graph is extracted per function in parallel, then linked
    (08 T9). Each solve becomes an action, so traces name it (21 §5.1).
11. **Nesting.** Grading, placement and commit run nested on `idr.func`
    under the pass manager, not in `parallelForEach` inside program passes
    (08 T6; 13 T1's decide / apply / restructure). It needs either the
    call to carry its callee's conventions or a frozen analysis (§5,
    DP-C5).
12. **The runtime is single-threaded and should say so in its fast path.**
    No atomics in counting, no mark-shared walk (18 §3.1; 08 §6 rc-Q4);
    sticky overflow and count-0-persistent already exist (18 §3.1).
    Freeing is already stackless and allocation-free, Lean's way (18
    §3.1, the A10 row).
13. **Runtime entries by word kind, and counts by runs.** `layout::Component`
    carries its kind and LLVM facts once (12 T8); the ABI gets
    `inc_cell`/`dec_cell` (no test), `_maybe` (NULL test), `_big` (odd
    test) (18 T-RC2). A take's moving or dying fields are counted by one
    `idris_rt_inc_slots`/`dec_slots` call per contiguous run (12 T4,
    CV-19; 18 T-RC5). The wide take-apart's 4,472 + 4,472 calls in one
    function go, and with them the reason for the 4,096-instruction inline
    budget (18 R-RC-4; 13 DP-38).
14. **One ending.** One closed sum (`Returned | Exited | Crashed |
    OutOfMemory | StackExhausted | …`), its statuses and texts in one
    checked table, one async-signal-safe `end` (18 T-END1); the harness
    reads it instead of parsing stderr (19 C4); a crash site reaches the
    runtime as data, not one string per site (12 T9). Ten alternatives
    stay on libc++'s switch path (§5.5 finding 12).
15. **Out of memory is outside the language, and already treated so.** No
    entry returns a failed allocation; the crash path flushes and
    allocates nothing (18 §6 oom-1); no allocating op carries `Crash`
    (18 §6; 02 §6). The target: snmalloc's failure continuation as the one
    `[[noreturn]]` path, its PAL's `error` routed to the same ending, the
    size checked once in `newCell` (18 T-AL1; §5.11 B1).
16. **Stack probes from the target's entry.** `"probe-stack"="inline-asm"`
    and `stack-probe-size` = the entry's page, set by the lowering; the
    runtime and the tools compiled with `-fstack-clash-protection` on every
    target; a guard below the signal stack too (18 T-STK1; 12 §6 oom-4;
    §5.11 B2; 0003).
17. **Effects reach LLVM.** One rule maps an op's declared effects onto
    the runtime call (`memory_effects`, `will_return`, `no_unwind`) and a
    function's facts onto `func.func` (12 T2; 02 T2). It needs an upstream
    patch: `llvm.call` implements no `MemoryEffectOpInterface` at the pin
    (12 §3.1).
18. **Tail position is one fact per function.** At least a cached
    per-function `TailPositions` analysis read in O(1) by every reader (10
    D1a). The five `isa<ReturnOp, YieldOp>` become one `TailEnd` view over
    `ReturnLike` (10 D5).
19. **Frames are the defunctionalized continuation.** Frames is a
    transformation, not a solver; §5.1 item 3's "per point, set-valued,
    stays ours" is refuted (10 §3.1). Its plan becomes one decision; its
    inputs read once (10 D2).
20. **No whole-module `Returned` solve.** Seed it from idr-optimize's
    `givesBack`, solve the rest per function on upstream's framework (10
    D3; 0003).
21. **The arrays stage decides each fact once.** No decision is needed
    for: forms read from interfaces and upstream utilities (11 C1);
    bufferization's alias classes, links and match yields computed once
    per analysis (11 C6); columns reading the program's table (11 C7).
    Element counting moves from the lowering to idr-rc, as 0009 owes
    (11 C9; 11 I-CV1). Upstream's ownership-based deallocation stays
    rejected: one ownership system (11 §3.1; 0009 §17; 18 §3.2 W9).
22. **Measure first.** Every lane's §8 asks for the same stage-1 record:
    the frontier pass, per-pass time, per-pass footprint in the measure
    jetsam kills on, and counts at each solve point (13 T5; 21 §5.1;
    §5.11 A2).

### The target's C++, under the owner's ruling

The line (§5.5 D1, now settled): dispatch over ops stays MLIR's (an
interface, a trait, an op-rooted pattern), because the op set is open to
C++; below that dispatch, and over every type of our own, the code is
concept-constrained templates, monomorphized, each solver instantiated
once in its own unit with `extern template` (§5.5 D3; Q-llvm-1). A
concept may read ODS (`OpT::template hasTrait<…>()` is a constant), never
list ops. A closed sum of ours is a `std::variant` read by one fold
(§5.5 D2's `match`: a jump table at any size; whether `std::visit`
survives on small variants is cxx-Q2, outside the ruling). The cluster's
code, piece by piece:

| subsystem | today | under the ruling | lanes |
| --- | --- | --- | --- |
| markings (exclusivity, stack, borrows) | three hand-built graphs keyed by pointer through hash maps; `mark(seeds, bool backward)` | `template <FlowGraph G, TwoPoint L, class Gate> Solution<G> mark(const G &, Seeds<G>)`; direction a type (`Forward`, `Backward`); `Id<Tag>` minted by the graph, `IndexVector<Id, T>` refusing a raw integer by `= delete("…")`; gates a template parameter (exclusivity's) or `NoGate` (stack, borrows); one explicit instantiation per marking | 07 D7; 08 T9, C-50, C-51; 21 P-14; §5.5 D3 |
| placement | `Placement`, `Classes`, three switches over `Class` | `template <LiveSet S> void place(FuncOp, S &)`: one reverse walk, `S` a bit vector or a sparse set chosen at instantiation; values numbered densely per function | 08 T2, T3 |
| consumption | five readings; `consumes` rebuilding `FlowEdges` per operand | `template <class OpT> concept Consuming = OpT::template hasTrait<…>();` reading the one ODS declaration; one `hasEffect<Free>` query where the op is not typed | 08 T7; 02 T3; §5.5 D1 sketch |
| reuse, demand | `Reuses::Site::box` variant visited ad hoc; `Borrows::Param` switch; `get_if` validator over `Source` | one fold per question; `Borrows` answers a `Permission` (no second enum); the token type carries the cell | 08 C-45, C-68, C-70 |
| callbacks in counting | `whereDies`, `edgesOf` take `function_ref` | template parameters constrained by `std::invocable` | 08 §3.2 (§5.3 bullets) |
| tail | `forTails` callback; `Site{CallOp, optional<Addition>}`; `FramesPlan::answer` nullable; `Where`, `Known` probed by `get_if`; a local `Visit` set; `std::function` recursion in `Positions` | `TailEnd`, `Site`, `Answer`, `Frame::site` as sums, each read by one fold; `forTails` returns its blocks; recursion by a lambda over deducing `this` | 10 D2, D5, D7, H-1, H-6, H-11, A-4; 21 P-19; §5.5 D5 |
| arrays | `Bind`/`Yield`/`cellDim` `function_ref`s; fold or scan re-asked inside shared code; two switches over `Form`; `element.boxed` tested in four functions | template parameters; `lowerInterchange<OpT>` with `if constexpr` on an ODS constant; one `constexpr` table indexed by `Form` checked by `consteval`; `Element = InPlace \| Boxed` read by one fold | 11 I-SL1, I-SL14, I-SL17, I-SL24, I-CV5 |
| lowering | ABI kinds switched in four places; an unnamed `requires` over `GET_OP_LIST`; the scalar families listed by hand; `isBoxed` asked in three patterns; five cold `function_ref` builders | `concept RuntimeOp = requires { OpT::runtimeEntry; }`; generated rows carry each kind's LLVM type and passing rule; families from `GET_OP_LIST` filtered by concepts on `isSigned`, `quotient`, `left`; `Representation = Boxed \| Unboxed` matched once; builders as templates; typed content keys | 12 T1, T5, CV-13, CV-23, CV-37, CV-42, CV-44 |
| runtime counting | `idris_rt_inc`/`dec` testing NULL and the odd bit; `eachSlot`, `binary<Op>` unconstrained | `template <Component K> void inc(Word<K>)` and `dec`, `K ∈ {Cell, MaybeCell, Big}`, each test present only in the kind that needs it; `inc_slots`/`dec_slots` over a run of one kind; the C names explicit instantiations generated from `IdrRuntime.td`; `std::invocable` on every template | 18 T-RC2, T-RC5, T-CPP1, R-RC-6, R-BG-2 |
| runtime allocation | null tests after `snmalloc::alloc` | snmalloc's failure policy and PAL are already template parameters: one `Conts` type and one PAL type route every failure to the ending; the type has no failing return | 18 T-AL1; §5.11 M1 |
| runtime endings, IO, numerals | ten text causes, status 1; `Slot` a tag and a union; `StreamOps` rows; `ByteRead`; `Numeral` with default-valued fields; `bool` + errno | `Ending`, `Slot`, `Read`, `Numeral` as sums, each question one fold; statuses and texts in one `constexpr` table checked by `consteval`; `std::expected<T, Errno>` from the platform layer | 18 T-END1, T-IO1, T-NU1, T-PL1 |
| one meaning of a primitive | Euclidean division three times | if DP-C9 chooses it, one template over a value domain concept (`APInt` for the folder, `arith` building for the lowering); if the runtime is the meaning, the runtime's typed template is that one source and the folder calls its instantiation | 12 T12; 18 T-BG1 |

Templates do not decide where a fact lives: the ruling fixes the C++
shape, not DP-C5's or DP-C9's answers. It does make every "keep the old
form beside the new" option of the lanes unavailable (hard cutover).

## 3. Where they disagree

Each: the sides, and what the choice turns on.

**3.1 Who owns the take's expansion (conv-Q3).** 12 T4 and 08 T8 both put
it in counting, at the idr level: the uniqueness test, the field moves and
the counts as IR (Lean's expand-reset-reuse, §5.10 B5). No lane argues for
keeping it in the lowering. It turns on two things. First, the owned
verifier must state the unique arm, where fields move without a count;
"every reference consumed once" has to hold there (12 §8). Second, Q-O1:
under a CFG core the expansion is blocks, not `scf.if`.

**3.2 Reuse before or after borrow inference (count-Q2 = own-Q1; rc-Q1,
rc-Q3).** Wave 1 favours drop-guided reuse after placement: proved
frame-limited, needs only a forward walk (§5.10 A4, A5, M7). 08 T4 takes
that as the target. 07 D4 offers both: (a) Lean's order, the decision
made as IR at once; (b) Koka's order. Today is neither: reuse runs first,
matches by size, at a *predicted* death point, then makes it true (08
§3.1 M7 row). It turns on:
- *precision*: today a take wins over a borrow; under (b) a parameter
  taken apart only for its cell stays borrowed unless a forced rule owns
  it (07 D4);
- *space*: tokens are held across calls today (`Reuses.cpp:208-227`), so
  reuse is not frame-limited (07 R-09; 08 §6 rc-Q3);
- *the guess*: under (a), "every call takes its arguments over" stays,
  essential to deciding before borrows (07 R-07);
- *the stage*: (a) needs a take admitted before grading (07 §8).

**3.3 Counting's query vocabulary: three designs for one code path
(perf-Q2).** 101edbc5 put a per-function pre-order numbering
(`Positions`) on main; it is wrong on 67 programs (21 P-1). 07 D5 wants a
per-function scope analysis shared with the verifier's `Numbering`, with
a sentinel per block start. 08 T3 wants a reverse walk that needs no
position queries at all. 21 §5.4: "not both". It turns on whether any
reader besides placement needs positions: Reuses' `fits` under Lean's
order does; the verifier's `Numbering` exists anyway; 10 FP-2's proposed
fix uses the very pair 101edbc5 measured hot (21 §3.4).

**3.4 Counting before or after TRMC (count-Q3).** 08 T16: Borrows
predicts TRMC's decisions, a rederivation (08 C-81); Koka runs TRMC first
(§5.10 M10). 10 §3.1: our order is representational, not chosen; TRMC
finds its context on the `idr.cell.init` counting creates, and keeps the
recycled cell. It turns on whether TRMC can work on `con` before cells
exist, and whether counting can place around `dest.write` and holes.

**3.5 Borrow inference itself (rc-Q1).** Wave 1: Koka turned inference
off (not frame-limited), Lean infers per SCC (§5.10 A5, A6, B2). Ours is
Lean's rule set, whole-program, with no frame-limited restriction (08 §6
rc-Q1). 07 D3 keeps every reason and makes it a two-point marking. It
turns on the space guarantee (rc-Q3), on dup counts, and on a coupling:
`shareTainted`'s one-level taint relies on a borrowed parameter never
being dup'd in its own function (07 §6, *conjecture*). Change borrows and
Share must change too.

**3.6 One meaning for the scalar primitives (conv-Q1 = ops-Q2).**
Euclidean division, the total shifts and the scalar test are written in
the folder and in the lowering, and division a third time in the runtime
(12 CV-39; 18 R-BG-1; 03 O-47). Three proposals:
- one C++ template over a value domain, instantiated for folding and for
  lowering (12 T12), which AGENTS.md does not allow without a ruling;
- runtime functions the folder calls, AGENTS.md as written (18 T-BG1;
  03 NQ2);
- `arith` where it agrees, Idris's edges as guards or selects (§5.8 DS4).
  12 §3.1 refutes "agrees" for everything but `divu`/`modu`.
It turns on vectorization: would a runtime call in a linalg body block it
(12 §8, *conjecture*; lane 11 knows)? The owner's C++ ruling favours the
template's *shape* but does not move the meaning out of `runtime/`;
AGENTS.md's text still decides that. The same question for arrays:
`Array.Core`'s 21 externs mean what the dialect's ops mean, not a runtime
function (11 I-LI2, arr-Q3).

**3.7 One guard op or five.** 12 T11 and §5.8 DS4: `arith.cmpi` plus one
`idr.check %cond, <kind>`. 03 §5.3 keeps five guard ops returning their
operand refined: DS4's form "loses the data dependence". 02 §6 ods-Q1
shows why it matters: a guard is dead only when its total op is dead,
because the total op reads the guard's result. It turns on whether that
dependence is wanted.

**3.8 One yield or one per parent.** 03 R5: one `idr.yield`, the parent's
`YieldTargetsOpInterface` deciding the targets. 11 I-BU14, C4: one
terminator per parent kind, so each bufferization model and conversion
pattern attaches to the op it is for (today a model is right only by
pipeline position, 11 I-BU14). It turns on whether upstream bufferization
can attach a model through a parent interface.

**3.9 Smaller op-shape disagreements touching this cluster.**
- `lin.enter`/`lin.use`: 03 merges them into one `lin.cast`; 11 N2
  (arr-Q2) asks for the opposite split, link against head, because a link
  is re-proved by an analysis on every query.
- `transpose`: 11 C2 deletes it into a tabulate; 03 keeps it, deferring to
  lane 11; 0009 §3.1's wording is the obstacle (arr-Q4).
- `put_sint` and kin: canon fuses (`put_str(show x)` to `put_sint x`);
  §5.8 O5 composes and fuses at lowering; 03 deletes the fused ops; 12
  §3.1: the lowering fuses nothing today; 18 R-IO-8: the fused entries
  allocate nothing, composition allocates a string, so keep them only if
  the lowering fuses (canon-Q3).

**3.10 Which resource consumption frees.** §5.8 EF3: `MemFree<Idr_Linear>`
on the value. 02 T1: `Count` under `Heap`, or today's `Reference` kept as
a sibling, "lanes 07 and 08 decide". 03 §5.3: `drop` frees `Heap` and
writes `Count`. 08 T7: one reference resource for consumption, `dup`,
`drop` and `take`. It turns on Swift's ordering hazard (§5.10 C4): once
runtime calls carry effects (12 T2), `is_unique` must read what `dup`
writes, or an upstream pass may move a `dup` above the test. Today that
order holds only because every lowered call has unknown effects (12 §3.1).

**3.11 Wave 1 against the code.** Wave-1 claims the lanes refuted:
- §5.1 item 3, frames' plan is a per-point solve: refuted (10 §3.1).
- §5.10 R1.3, counting nested per function: refuted (08 §3.1); R1.4, an
  `is_unique` op: none exists (08, 12); R4, an exclusive drop reads no
  count: it does (12 CV-32; 18 §3.1).
- §5.10 M7, reuse is algorithm K or D: neither (08 §3.1).
- §5.8 DS4, word ops to `arith`: only `divu`/`modu` (12 §3.1); `take` and
  `unpack` as one destructure: refuted, essential (08 C-43); six stat ops
  as five runtime calls: the OS call is already one (18 §3.1).
- §5.11.2, below the guard lies the heap: below it lies the writable
  signal stack (18 §3.1 O2).
- §5.11 C1, snmalloc as the tools' malloc: it is not (18 §3.1).
- §5.10 W9 and G5, upstream deallocation for arrays: refuted as a target
  by the owner's earlier ruling (11 §3.1; 0009 §17); 18 §3.2 adds that it
  would be correct only for arrays whose elements hold no object.

**3.12 Tensions with AGENTS.md.** Listed here; each is a row of §4.
- "Acceptance is a property of the program, never of the optimizer": the
  in-place promise (08 NQ1).
- "No primitive has an implementation in Idris: its one meaning is the
  runtime's, which folders call too": the scalar primitives and the array
  externs (§3.6).
- "Never miscompile silently": a frame that skips the guard (18 R-STK-1);
  a constant-stack promise broken silently (10 TC-5, FP-11).
- "Nothing may assume … a page size outside the one place the target is
  decided": the address width recorded as a minimum and read as a maximum
  (18 R-RC-5); the host's `sizeof(idris_rt_array)` in the lowering (11
  I-CV10); preprocessor branches inside the platform layer (18 R-PL-2);
  the bitcode home branched four times (13 DP-35).
- "A fact kept in a discardable attribute can be dropped silently":
  TRMC, accumulation and returned arguments copy a call's discardable
  attributes (10 Tr-1, A-1, RA-1); nothing writes one today.

## 4. Suspected bugs and rule violations

"R" read, "M" measured, "C" conjecture.

| # | what | where | ground | lanes |
| --- | --- | --- | --- | --- |
| 1 | **The in-place promise depends on the optimizer.** idr-demand binds it only where a recycle took its token from a take of the parameter. Skipping one `ReuseAction` (a debug counter can), or idr-rc-stack framing the parameter, removes the promise and the refusal. `sinkConsumers`, an unwrapped optimization, decides whether a dup appears, hence exclusivity, hence the verdict. Skipping idr-rc-stack could add a refusal. | `Demand.cpp:59-77`; `Reuse.cpp:25-28, 61-64`; `Stack.cpp:344-353`; `Reuses.cpp:158`; `Reshape.cpp:149-210` | R chain; no program run | 08 NQ1, C-37, C-74 |
| 2 | **Exclusivity's crash-case precision loss.** A case ending in `ub.unreachable` counts as an unknown way out; when live, every input of every successor of its match is shared. Every memo force and every non-covering function has one. It sits on the refusal's path. | `ExclusivityGraph.cpp:208-216, 222`; `ExclusivityAnalyses.cpp:236-243` | R path, C effect | 07 G-09, D1 |
| 3 | **`Positions` miscompile path, on main.** `make test` 403/480 against 470/480 since 101edbc5; `tests/chars` asserts in `placeOwned` on overlapping spans; 65 outputs assert "Malformed attribute storage object". Mechanism (C): a block has no coordinate. A second path (C): a missed `forget` leaves a span under a freed pointer. Landed without a program-suite run. | `Positions.cpp` (`assign`, `forget`) at 101edbc5 | M (51a4771b) | 21 P-1, P-16 |
| 4 | **`decides` changed meaning silently.** 101edbc5 made it "the five idr ops with `Idr_Decides`"; an `scf.if` reaching counting is now held across, not moved into its regions, while the owned verifier still calls its regions alternatives. | `Positions.cpp:211`; `Verify/Linearity.cpp:27-33` | R; reach C | 21 P-3 |
| 5 | **The function summary loses op effects.** `handle.string` in a pure helper gets `effects<none>`; `exit` never returns but the summary says it does, unsound once `willreturn` is lowered (12 T2); a memo state write is lost at its function's boundary, so CSE may merge memo reads across a call. | `Func.cpp:189-202`; `Call.cpp:65-72` | R; reach C | 02 §3.7 |
| 6 | **No stack probes; a guard-skipping frame lands in the signal stack.** 1 MiB guard; the alternate stack lies right below it; the comment "none is" larger is checked by nothing; tools lack stack-clash protection on macOS; the runtime on every target. | `Runner.cpp:35-37, 71-72`; `CMakeLists.txt:207, 226, 242, 277`; `runtime/CMakeLists.txt:134-141` | R; no probe M (grep) | 18 R-STK-1, R-STK-2, R-BD-1; 12 §3.1; 19 §6 |
| 7 | **snmalloc's own fatal errors** print another format, a stack trace, and `abort()` without flushing the program's output. | `Cells.cpp:51`; `pal_posix.h:189-201` | R | 18 R-AL-3 |
| 8 | **Every crash is status 1**, its kind only its text; the harness parses stderr in three copies. | `idris_rt.h:292-297`; `harness/lib/{run,e2e,differential}.sh` | R | 18 R-ABI-4; 19 C4 |
| 9 | **libc++ hardening in programs traps** rather than naming a crash. | `CMakeLists.txt:324-326` | R; trap behaviour recalled | 18 R-BD-2, §6 cxx-Q4 |
| 10 | **A string's size is unchecked** (`sizeof(idris_rt_str) + bytes`), trusting the lowering; arrays check theirs. | `Strings/Making.cpp:20-28, 58-60` | R | 18 R-ST-1 |
| 11 | **Writable reservations** (64 GiB stack, 4 GiB heap region, snmalloc's pagemap): a program cannot start under overcommit mode 2 or a smaller `ulimit -v`. 1445d894 chose one constant knowingly. | `Posix/Memory.cpp:65-85`; `Runner.cpp:76-80`; `Cells.cpp:93-123` | R; host behaviour C | 18 R-AL-4, R-STK-3 |
| 12 | **The address width is a recorded minimum used as a maximum** in the dying list's 48-bit packing asserts (39 on arm64 Linux 4K). | `Freeing.cpp:44-51`; `CMakeLists.txt:222` | R | 18 R-RC-5; 0003 |
| 13 | **The host's layout of the runtime header** (`sizeof(idris_rt_array)`) in the lowering, not the target's. | `Descriptors.cpp:222-226` | C (equal on four LP64 targets) | 11 I-CV10 |
| 14 | **A latent race:** `Layouts::sizeOf` from parallel lowering workers may fill the `DataLayout` caches no worker may fill. | `StaticData.cpp:187`; `Lower.cpp:251-255` | C | 12 CV-55 |
| 15 | **The constant-stack promise is kept by comments.** idr-rc-stack and idr-tail-calls each decide "a tail call on a cycle"; a frame-bound one stays a call, counted, otherwise silent. A frames component whose result no field may hold keeps its stack growth with nothing said. | `Stack.cpp:36-40`; `TailCalls.cpp:47-52`; `FramesPlan.cpp:166-171` | R | 10 TC-5, R-2, R-3, FP-11; 21 P-10 |
| 16 | **Copies of discardable attributes** onto new calls (carry nothing today, or a forbidden fact). | `Trmc.cpp:74-77`; `Accumulate.cpp:73`; `ReturnedArguments.cpp:73` | R; none written M | 10 Tr-1, A-1, RA-1 |
| 17 | **Checks thrown away:** `Returned`'s solve result dropped in release (`[[maybe_unused]]` + `assert`); `zip_first` truncating silently in frames; `setType` outside the rewriter; `(void)reifyResultShapes` then a `zip_equal` assert. | `Returned.cpp:156-159`; `Frames.cpp:96-104, 243`; `Nests.cpp:175` | R | 10 R-2, Fr-1, Fr-9; 11 I-SL25 |
| 18 | **Quadratic shapes awaiting stage 1:** TRMC's join recounts a match's regions per arrival; `madeInRest` O(rest²); `in()` O(ops × carried); `YieldModel` O(N²) per match; per-block `Classes` in `sinkConsumers` (still after 101edbc5); `Positions` inserts linear in the block; bufferization's region cache never filled upstream. | `IR/Tail.cpp:93-96, 213`; `FramesPlan.cpp:31-35`; `WhileDo.cpp:80-96`; `Data.cpp:186-191`; `Reshape.cpp:162`; pin `BufferizableOpInterface.cpp:84-104` | R; cost C | 10 IT-7, FP-2, W-1; 11 I-BU10-12; 08 C-37; 21 P-4 |
| 19 | **The next whole-program walls:** Borrows (ran on stage 1, never measured), idr-narrow's `Ranges` (re-solved whole after versioning), `Returned` on the lowered module (never reached). | `Borrows.cpp:29-41`; `Ranges.cpp:67-76`; `Narrow.cpp:158-165`; `Returned.cpp:152-159` | R; C | 07 B-01; 11 R1; 10 R-1; 21 §3.4 |
| 20 | **Workers create attributes under the context lock** (one crash message per site, range dictionaries per call). The suites show lock slow paths at about a fifth of the reduced corpus. | `Runtime.cpp:42-50, 189-196`; `RuntimeCalls.cpp:112-116` | R; suite share M | 12 CV-16; 21 §3.4 |
| 21 | **A test fact on every program's hot path:** a `thread_local` live-cell count on every allocation and free, and `IDRIS_RT_LIVE` read at exit. | `Cells.cpp:153-157, 187-205`; `Ending.cpp:17-31` | R | 18 R-AL-5, N2 |
| 22 | **Pass-thread stacks differ by OS:** the reserved stack covers the main thread only; pool workers get OS defaults. `PINS.md:595` says 2^40 where the runner reserves 2^36. | `Runner.cpp:44`; `Threading.cpp:81-93` | R | 13 DP-39 |
| 23 | **Dead code:** `GEN_PASS_DECL_IDRRCPLACE`; `site.cells.empty()`; `asIndex`; the empty `CallsRuntime` trait; `idris_rt_io_term_setup`; `str_release`/`big_release` aliases; frames' `!fn \|\| empty`. | 08 C-01, C-46; 11 I-CV12; 12 CV-52; 18 R-IO-9, R-ABI-8; 10 FP-8 | R/M | as cited |

## 5. The decisions this cluster hinges on

The §8 IDs, deduplicated. For each: the options, the evidence, what
depends on it. No recommendation. Q1, Q-M3 and Q-llvm-1 are settled
(templates and concepts, monomorphized, one instantiation per solver) and
no longer appear below; every option listed is a hard cutover, so none
keeps an old form beside a new one.

**DP-C1. What specifies the in-place promise and the uniqueness refusal.**
(count-Q1 = own-Q2; bears on rc-Q2.)
- *Options.* (a) The refusal is whatever the analysis answers; a more
  precise analysis admits more programs. (b) A declarative rule stated
  where the promise is made (the `in_place` type plus the function's own
  rebuild of a quantity-1 parameter, before counting), with idr-rc-stack
  and reuse bound to honour it, and a test of the rule's boundary (08
  T13).
- *Evidence.* Bug 1 above. 07 D1 (bug 2) can only accept more and count
  less, yet it changes which programs pass (07 §8). AGENTS.md's
  "acceptance is a property of the program". The Idris-side hook exists
  (`Registry/Entry.idr:258-260`, `Recognized.idr:183-186`; 08 §4.10).
- *Depends.* T13; the reuse order (DP-C2: under (b) the promised cell is
  always recycled); the exclusivity redesign (cluster B); the registry's
  `InPlaceType` (cluster D, lanes 14, 16); `tests/uniqueness-shared-rebuild`.

**DP-C2. Reuse order, borrow inference, and a space guarantee.**
(count-Q2 = own-Q1; rc-Q1; rc-Q3; rc-Q5 asks only for a confirmation.)
- *Options.* Reuse: (a) Lean's order, decided as IR at once (07 D4a);
  (b) Koka's drop-guided reuse after placement (08 T4, 07 D4b). Borrows:
  keep inferring (07 D3's marking); restrict to frame-limited cases;
  declare only on runtime primitives (§5.10 Q1). Space: none stated;
  garbage-free; frame-limited; each with a test (19 C6: a high-water mark
  of the live-cell count, compared with reuse skipped and made).
- *Evidence.* 9db9813d's 1088 errors came from the simulation (21 P-15).
  Tokens cross calls today (07 R-09). Lean's forced reasons are ours too:
  the tail call within a cycle, the reuse target (07 §6). rc-Q5: drops are
  at last use today, with four exceptions written in the code (08 §6).
- *Depends.* DP-C1; DP-C3 (Reuses' `fits` needs positions under (a));
  Share's taint (§3.5); T3; the solver layer's marking (cluster B).

**DP-C3. Counting's vocabulary: `Positions` and numbering.** (perf-Q2;
with Q-llvm-3 and QL1 from cluster B.)
- *Options.* Repair `Positions` into 07 D5's scope (a block sentinel, an
  analysis, one numbering with the verifier, invalidated by a listener);
  revert to e96bb991's queries until P0; keep it as the interim that 08
  T3 deletes. Under the hard-cutover ruling, whichever survives P0 is the
  one form: a repaired `Positions` beside T3's walk would be two.
- *Evidence.* 21 P-1 to P-4; main has been red since 101edbc5; the
  sampler put half of idr-rc-grades in `findAncestorOpInBlock` and a
  quarter in block renumbering (21 §2.3).
- *Depends.* perf-Q1's fence on the parallel agent (cluster E); DP-C2;
  cluster B's numbering decision. A green starting commit for every gate
  (21 §5.5).

**DP-C4. Counting before or after TRMC.** (count-Q3.)
- *Options.* Keep today's order, with Borrows' prediction moved into the
  walk; or Koka's, TRMC first, counting placing around `dest.write`.
- *Evidence.* 10 §3.1 (the context lives on `cell.init`; reuse is kept);
  08 C-81, T16.
- *Depends.* T3's handling of self tail calls (08 §8 unknowns); Q-O1.

**DP-C5. Where counting's and the tail's facts live: on the call, or in
analyses.** (count-Q4; tail-Q1 = Q-AN1; bears on DD-Q7, drv-Q3, ods-Q6,
types-Q3.)
- *Options.* (a) `idr.call` carries its callee's parameter conventions,
  and tail position as an inherent property (MLton's `Return.t`), each
  verified against the callee in `verifySymbolUses` and lowered into
  `llvm.call`'s `tail_call_kind` (08 T6, 10 D1b). (b) Cached analyses
  read with `getCachedParentAnalysis` (08 T6's alternative, 10 D1a).
- *Evidence.* `idr.call` already carries `effects` this way
  (`Call.cpp:29-59`). 4c87dcc5: a program verified half-graded failed
  every program. Under (b), no upstream pass reading effects sees a
  call's consumption (08 T6). `func.call` has no property for either, so
  (a) needs our call op through the lowering (03 §6 DD-Q7; 10 §6).
- *Depends.* Cluster A (DD-Q7, the call op, the function op); cluster E
  (decide / apply / restructure, verification cost); tail-Q2 (DP-C8);
  lowering phase 0 (`FuncToFunc`).

**DP-C6. The take's expansion and uniqueness as an op.** (conv-Q3; the
fallback half of rc-Q2.)
- *Options.* Counting's last step at the idr level, with `idr.is_unique`
  folding on `excl` (12 T4, 08 T8); or the lowering keeps it.
- *Evidence.* Today both arms give the same fields and only the token
  differs, so the test changes speed, never meaning (12 §6 rc-Q2). The
  run-time fallback exists already (08 §6). The owned verifier must state
  the unique arm (12 §8).
- *Depends.* The count resource in the effects tree (§3.10, cluster A);
  the typed token (lane 01, cluster A); `inc_slots`/`dec_slots` (runtime);
  deleting the inline budget (lanes 12, 13).

**DP-C7. How much exclusivity is static, and where grade copies live.**
(rc-Q2; own-Q3.)
- *Options.* R1 alone (one marking, the run-time test elsewhere); R2 as
  built (one copy per function, key "every followed parameter
  exclusive"); a finer mask key (still finite, no budget); or the grade
  as a key of idr-optimize's one specializer.
- *Evidence.* R2 already runs inside counting, after placement, so the
  pipeline-order cost §5.10 R2 feared does not arise (12 §6; 08 §6).
  Arrays decide in-place writes statically, a copy at a link being an
  internal error (11 §6 rc-Q2).
- *Depends.* Cluster B (Q-opt, the one specializer); DP-C1.

**DP-C8. The constant-stack promise and frames' stack type.** (tail-Q2,
tail-Q3.)
- *Options.* Q2: part of a program's meaning (a frame-bound tail call on a
  cycle is an internal error; an unframed component must be impossible or
  said), or a performance property (a statistic, as today). Q3: a stack
  type per member result type (R·(F+1) regions become F + R), or one per
  component with the impossible cases in a default region.
- *Evidence.* 10 TC-5, FP-11; 10 R-6: a group of R mutually recursive
  stack types has never been tried, and idr-knots must accept it.
- *Depends.* DP-C5 (tail position in the call makes the two readers
  agree by construction); lane 01 (data-type groups); oom-6 (a stack
  overflow named).

**DP-C9. One meaning for primitives the runtime does not define.**
(conv-Q1 = ops-Q2; ops-Q3; arr-Q3.)
- *Options.* Runtime functions the folders call (AGENTS.md as written);
  one C++ template as the one meaning (AGENTS.md amended); `arith` where
  it agrees plus Idris's edges, with `divu`/`modu` leaving the dialect
  behind a generated guard pairing (ops-Q3). For the array externs: name
  the dialect as their meaning in AGENTS.md or 0009, or give them runtime
  functions.
- *Evidence.* §3.6; 18 §3.2 (the runtime defines none of the word ops);
  11 I-LI2.
- *Depends.* Cluster A (the scalar ops); vectorization (lane 11);
  AGENTS.md (the owner's text).

**DP-C10. The runtime's ABI.** (rt-Q1, rt-Q2, rt-Q4, rt-Q5, conv-Q4,
conv-Q5, oom-6, DD-Q5, cxx-Q4, rc-Q4.)
- *Count encoding (rt-Q1).* Koka's signed count without atomics (0 unique,
  negative sticky) makes the non-last decrement one branch and overflow
  free. Cost: every reader of "count 0 is persistent" moves (static data,
  `persistHeld`, 0007's detach table). Gated on instructions per `dec`
  (18 T-RC1). Safe only with rc-Q4 confirmed (no cell crosses a thread;
  the folders release theirs in scope, 18 §6).
- *Live cells (rt-Q2).* Keep the counter in shipped programs, or only in
  the checked runtime and the folders (18 T-AL4). A leak only the shipped
  build shows would go unseen (18 §8).
- *Endings (conv-Q4, oom-6).* Crash sites as (cause, file, line, column)
  (12 T9); a status per ending kind is then one table row (18 T-END1).
- *Mangling (conv-Q5).* A prefix on every program symbol deletes three
  collision checks (12 T7).
- *One op, several functions (DD-Q5).* The runtime already serves the six
  clocks with one `readClock(Clock)` and the file times with one `fstat`;
  one op, one function with an enum argument suffices (18 §3.1; 03 §6;
  12 §6). The generator refuses it today (12 CV-53).
- *Test seams and snmalloc (rt-Q4, rt-Q5).* `IDRIS_RT_IO_BUFFER_SIZE`; a
  seed-range hook upstream in snmalloc, or our copy of its config with a
  diff test (18 T-AL2).
- *Hardening (cxx-Q4).* Extensive mode on every unit in every
  configuration today; in programs it traps (18 §6).
- *Depends.* Cluster E (the harness's ending, lane 19); 0007 (unbuilt).

**DP-C11. Running out of memory and strict hosts.** (oom-1 to oom-9,
rt-Q3, drv-Q4.)
- *Options.* oom-1 confirmed by the code already (18 §6). oom-4: probes
  everywhere (no lane objects). oom-5: no limit (1445d894's ruling), a
  limit as one more snmalloc range, or the reservation's size (07aeb299,
  reverted the same day). rt-Q3: reserve `PROT_NONE` and commit on use
  (heap through snmalloc's `notify_using`; the stack through the runner's
  fault handler), or say strict hosts are outside a program's promise.
  drv-Q4: worker stacks reserved like the main thread's.
- *Evidence.* 18 §6; §5.11 K2; 13 DP-39.
- *Depends.* 0017 D9; cluster E (the pool).

**DP-C12. The arrays stage's scope in P0.** (arr-Q1, arr-Q2, arr-Q4,
arr-Q5; QA2 for `Ranges`.)
- *Options.* Take 0009's stage-2 "buffers in data-type bodies" (two
  upstream patches) and its destination-style generating ops inside P0, or
  leave them to 0009. A link as its own op, or one op with the fact
  computed once. Transpose as a tabulate. `Ranges` per function with
  summaries, or whole-program on a patched framework.
- *Evidence.* 11 §5 C2, C3, C5, C8; 11 §6 QA2 (the consumer is per
  function already; `int-range-optimizations` 3 s nested against 30 s
  module-wide).
- *Depends.* Cluster A (array ops, the grade type's tensor-like
  interface); cluster B (summaries); counting meeting ordered ops on
  buffers (11 R3).

**DP-C13. `idr-lower` under the pass manager.** (conv-Q2; drv-Q5.)
- *Options.* Two program passes first (declare every runtime function,
  materialize every static datum), then a nested function pass (12 T6);
  or the worker-and-merge scheduler, kept and named as ours. drv-Q5: the
  prepared runtime's bitcode in one home on every target.
- *Evidence.* Runs are cut by function count, not cost (12 CV-02); the
  pre-pass must see every datum, which needs T5 and T9 (12 §8).
- *Depends.* Cluster E (the pipeline as records, nesting).

## 6. Order of work, and dependencies on other clusters

**Step 0. A baseline, and a green tree.** One stage-1 record at a fixed
commit (21 §5.1; 13 T5): frontier, per-pass time, per-pass footprint,
counts at each solve point. The tree must be green: e96bb991 (470/480) or
main after 101edbc5 is fixed or reverted (21 §5.5; DP-C3). Fence the
parallel agent's work on counting, exclusivity and the stack (perf-Q1,
cluster E).

Every step below is a hard cutover: the lane's §7 deletion list for the
step is part of the step, and the old form, its tests of the old state
and its call sites go in the same change. The C++ of each step is written
to the ruled shape (§2's last part) from the start, never ported first
and templated later.

**Step 1. Local, no ABI change, no ruling needed.**
- Runtime: T-AL1 (one OOM continuation, one PAL), T-PL1, T-PL2, T-PL4,
  T-NU1, T-IO1, T-CPP1, T-STK2, T-PL3 (18 §5.8 item 1).
- Lowering: T1 (the runtime entry on the op), T10 (encodings called) (12
  §5).
- Tail: D5, then D1a, then D9, D8, D7 (10 §5).
- Arrays: C1, C6, C7, C8's local items, C9's dead code and `Elements`
  sum, C10 (11 §5).
- Counting: T11, T14, T15 (08 §5.3).

**Step 2. With cluster A (the dialect's surface).** In this order:
1. The effects tree and function bits together (02 T1 with T2), never
   apart, after ods-Q1, ods-Q3, DD-Q2, DD-Q3 and eff-Q1 (02 §5 order).
   `exit` must be settled (eff-Q2, bug 5) before 12 T2 lowers
   `willreturn`.
2. The static lifetime in the grade (08 T1), the typed token, the
   `idr.is_unique` op, a `token.free` split from `drop` (12 CV-31), the
   cell allocation class, consumption as `Read` + `Free` (08 T7), the
   call's conventions property if DP-C5 says so (08 T6).
3. Counting T2 + T3 together, then T4 (after DP-C2), then T8 (after
   DP-C6).
4. Lowering T3, T4, T5, T8, T11; runtime T-RC2, T-RC4, T-RC5, T-ABI1,
   T-ABI2 (18 §5.8 items 2–3).
5. T-END1 with the harness's one ending (19 C4, cluster E), before the
   cutover, so later steps are checked by it.

**Step 3. With cluster B (the solver layer).** The marking template,
then idr-rc-stack (08 T9) as its first client, exclusivity (07 D2 with
08 T5, T12), borrows (07 D3, after rc-Q1). D1 of lane 07 may go first,
alone, with its test (07 §5 order), once DP-C1 says acceptance may move.
`Returned` (10 D3) and `Ranges` (11 C8) on the summary schedule (Q-M1).

**Step 4. With cluster E (pipeline, tests).** Nesting by decide / apply /
restructure (13 T1), lane 08 first since the commit already is an apply
step (13 §5 order). `idr-lower` under the pass manager last (12 T6, after
T5 and T9). Stack probes from the target's entry (18 T-STK1; 13). The
invariant oracle (T-Q1) must exist before any step that rewrites
fixtures.

**Step 5. With cluster D (the Idris side).** The in-place promise at the
source if DP-C1 says (b); case blocks emitted in place (tail-Q4, lanes 15
and 17); transpose emitted as a tabulate (11 C2); array fields as buffers
(11 C5); guards built by a function indexed by kind and operand type (12
T11); the generated enums (clock kind, crash cause; 03 §5.4).

**Behind a ruling or a measurement.** T13 (DP-C1), T16 (DP-C4), T-RC1
(rt-Q1), T-AL3 and T-STK3 (rt-Q3), T-AL4 (rt-Q2), 11 C3 and C5
(arr-Q1, arr-Q5), 10 D1b (tail-Q1), 10 D2 (tail-Q3).

**Dependencies, by cluster.**

| on | what this cluster needs from it |
| --- | --- |
| A, dialect surface | the effects tree and `Count`; consumption's declaration; the typed token; `!idr.ctor` if Q-O1 keeps regions; the call's properties (conventions, tail position); `is_unique`; op splits and merges (guards, yields, `lin.*`, `cell.*`, clocks, file times); `Idr_Lifetime` with `Static` |
| B, analyses and solvers | the marking template and CSR graph; one per-function numbering (or none, per DP-C3); the summary schedule over SCCs; the one specializer if grade keys move there |
| D, the Idris side | the `InPlaceType` hook's form; case blocks; emitted tabulates and buffer fields; typed guards; the generated mirror of every changed op |
| E, pipeline and tests | the baseline record; the fence; nesting; the pass table; the ending the harness reads; the invariant oracle; worker stacks; the pool |

## 7. Risks, and the measurements they need

**Risks.**
- *Placement's rewrite.* T3 replaces rules fixed by many bug hunts, some
  of which Perceus does not state: an update holds its array, static
  data, memo cells never taken apart, buffer crossings, a force's
  captures (08 §8). A mismatch is a leak or a double release found only
  by running. Gate: the suites' statistics and the live-cell
  differential, per test, before and after.
- *Acceptance moves.* 07 D1, 07 D2, 08 T13 each change which programs
  pass, and there is no oracle; the committed expectations are the spec
  (07 §8; 08 §8).
- *Static facts replacing run-time tests.* T-RC2 and T-RC4 dereference
  NULL or free a stack cell if a kind or a token type is wrong once; the
  checked runtime and the verifier are the net (18 §8). T-RC1's missed
  writer of the sticky constant would let a take reuse read-only memory.
- *Effects on runtime calls* (12 T2) make reordering possible where today
  every call is unknown; the count resource must be right first (§3.10).
- *The collision with the parallel agent*: three designs for counting's
  vocabulary and two for exclusivity and the stack, on a tree that moves
  (21 §8).
- *Compile time of template-heavy C++.* Measured on the host, a template
  callback costs two to three times a `function_ref` to compile, and
  `std::visit` past eleven alternatives costs 11.3 s and 3 MB for 300
  sites against 2.0 s and 68 KB for the fold (§5.5 findings 12, 13). The
  answers are already in §5.5 D6: one instantiation per solver behind
  `extern template`, sums through the fold, a precompiled header (cxx-Q3;
  13 DP-55: about 294 units parse MLIR's core).
- *Untried shapes*: R mutually recursive stack types (10 R-6); ordered
  generating ops after bufferization, which counting has never met (11
  R3); the static-data pre-pass (12 §8).
- *Upstream patches this cluster needs*, each with its report and plan:
  `llvm.call` reporting `memory_effects` (12 T2); `getSuccessorForOperands`
  on LLVM branches (10 D6); bufferization's region cache (§5.1 U3, 11
  I-BU12); a `ub.poison` bufferization model (11 I-BU21); 1:N function
  attribute arrays (11 I-CO6); patch 27 and a per-instance `extraClassOf`
  (11 C5); snmalloc's seed range (18 T-AL2); a thread pool stack size
  (13 U-d).

**Measurements** (none exists; no lane could run one).
1. The stage-1 record of step 0, with `phys_footprint` on macOS (18 §3.2
   W3: `peak_memory` reads `ru_maxrss`, which misses compressed pages) and
   assertions stated (drv-Q1).
2. Per idr-rc pass: time and footprint; idr-rc-grades after the
   `Positions` fix; idr-rc-exclusive on the module, not a fixture (21 §8).
3. The match case-count distribution, values used in more than one case,
   crash cases per match (08 §8; 07 §8).
4. Stack inference's nodes and edges; the followed fraction (08 §8; 07 §8).
5. The suites' `numDups`, `numDrops`, `numTakes`, `numReuses`,
   `numExclusive`, `numStackCells`, `numBorrowed` as baselines for T3, T4,
   T5 (08 §8).
6. Refusals under `-mlir-debug-counter` skipping `idr-reuse-site` and
   `idr-stack-cell`: the test of bug 1's chain (08 §8).
7. `idris_rt_is_unique` calls in the lowered module before and after 07 D1
   and T8 (07 §8; 12 §6).
8. Instructions per inlined `dec` and `inc`, today against T-RC1 (18 §8);
   the `thread_local` cost per allocation per target (rt-Q2).
9. records-past-the-cell with run counts, with and without the inline
   budget (18 §8).
10. Program start under `ulimit -v` and overcommit mode 2 on the Linux
    targets; `mprotect` per committed chunk (18 §8).
11. The largest frame in the stage-1 frontend and the benches against the
    1 MiB guard (18 §8).
12. `Ranges` and `Returned` on stage 1 in isolation, before the pipeline
    reaches them (21 §8; 10 R-1; 11 R1).
13. Frames' M, R, F per component at stage 1 (10 §8).
14. Context-lock wait in idr-lower; the largest function's share of its
    time (12 §8).
15. The arrays' bench counters before and after C1, C2, C6, C8 (11 §8).
16. A `-ftime-trace` build of today's tree as the compile-time baseline,
    then per step, so the ruled template shape is measured, not assumed
    (§5.5 D6.2; 13 DP-59).

## 8. What is stale, and what wave 2 left unverified

**Stale since 101edbc5** (on origin/main after the tree the lanes read;
21 §3.5). `decides`, `usedIn`, `usedAfter`, `usersIn`, `whereDies`,
`heldIn`, `onlyReads` moved into `Positions`; `Idr_Decides` exists.
- 08: the §3.1 rows citing those queries' costs, §4 C-06, C-22, C-27,
  C-29, C-37 (`readBetween`), C-79, and §8's "quadratic shapes": the
  per-query terms are gone; the `Class` switches and the per-block
  `Classes` in `sinkConsumers` stand. T3 now deletes `Positions`, not the
  free functions.
- 07: §2's `Uses.cpp` rows and costs, §3 rows 6 and 7, §4 O- and U- rows;
  D5 is half built, differently.
- 02 §3.1: "no `Decides` exists" is false. 03, 11, 12, 18: line drift in
  `IdrBase.td` past 292 and `Traits.h` past 123.

**Stale since 51a4771b.** Main is 403/480, not 470/480; a new counting bug
is registered ("op numbering corrupts under counting's own rewrites").
The first written measurement is of the suites, not stage 1: defunc's
per-function pattern set, the context lock about a fifth, the verifier
1.6–1.7 % self, counting a few percent, the 20,000-case probe 0.31 s on
the profile build against 3.83 s on dev (21 §2.3).

**Unverified by any lane** (no compiler was built in wave 2):
- every quadratic shape in §4 row 18, and Borrows' cost;
- whether any `scf.if` reaches idr-rc (bug 4), and G-09's effect on the
  committed expectations (07 §8);
- whether the reverse walk keeps the self tail calls placement keeps by
  construction, and whether a match's default binding can be a forwarded
  successor input, which C-08's deletion needs (08 §8);
- whether vectorization meets `divs` or shifts in linalg bodies (12 §8);
- libc++'s trap behaviour at the pin; snmalloc's pagemap size; each
  kernel's real address width; host behaviour under strict overcommit
  (18 §8);
- whether `persistHeld`'s callers could know the cell is static (18
  R-RC-8); the `Layouts::sizeOf` race (bug 14);
- the generated ABI tables read are stale (2026-10-18): the 119 `Abi<>`
  and 133 prototype counts are approximate (12 §8; 18 §2.1);
- what the 52 GB and 627 GB figures measure (a manual stop, a jetsam
  footprint; 21 P-18);
- this synthesis read the local `origin/main` ref (51a4771b) and did not
  fetch; a later push may have moved it.
