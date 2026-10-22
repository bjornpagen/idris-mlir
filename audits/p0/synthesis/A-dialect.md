<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 synthesis A: the dialect's surface

The dialect cluster: types (lane 01), effects, traits and interfaces
(02), ops (03), canonicalization and folds (04), with what lanes 07, 08,
10, 12, 14 and 21 say of them, against the proposal's §5.2 and §5.8, at
e96bb991 (later commits: section 8). "01 §3.1" is a lane's section;
"02 E31", "03 O-12" are issue IDs; "§5.8 DS4" is the proposal. Nothing
here decides; section 5 lists what the owner decides.

**Owner's ruling in force (2026-10-21):** "heavy use of templates and
concepts pls". Our own C++ is concept-constrained templates by default:
callbacks become templates, ladders over our own types become
concept-constrained overloads or one fold over a closed sum; MLIR op
interfaces stay where the op set is open; a concept may read ODS facts
(trait or interface membership, a generated constant), never list ops.
Every change is a hard cutover with hard culling, churning toward the
most elegant representation. It settles §8 Q1, Q-M3, Q-llvm-1 (5.0).

## 1. In plain words

**What the cluster is.** The `idr` dialect's surface: what a value's
type says (grades, data types, tokens), what an op may do to state
(effects on resources), how ops are grouped (traits, interfaces,
families), which ops exist and what each means, and the rewrites that
simplify them (folds, canonicalization).

**What is wrong today.** Most of the dialect is declared in ODS, some
of it well (02 §3.1: `GuardedOp`, `ConsumesOnly`; 03 §3: every
ownership op already defines a new value). But one fact is often held
two to six times, and the copies disagree:
- "Does IO" is held four ways that do not match: a trait (80 ops), a
  world operand (the same 80), the `IOResource` effect (written by 80,
  read by 70, another set), and the function summary's own reading
  (02 §3.1; 03 O-36).
- "The result is the operand" is held six ways (02 E57); the six
  resources are siblings, so "a crash comes after output" is said by
  writing two at once (02 §2.3).
- A function's summary ignores its ops' effects and drops some (02
  §3.7): a handle-table read, a memo write, `exit`'s "never returns".
- The grade is three free enums with its rules in C++ free functions
  (01 §2.2); the verifier walks the whole program serially after every
  pass and adaptor (01 §2.3); canonicalization re-reads a match's
  regions six times per visit, unbounded, so a cycle hangs (04 §3.2,
  C60).

**What it should become.** One declaration per fact, read by everyone:
a resource tree in one header, effects in ODS where static and from one
typed trait where they follow from types, a function's effects derived
from its ops by one generated table (02 §5); a grade as one attribute in
the type, recursive type facts computed at construction, a token that
names its cell (01 §5); op families from lists, one op per semantics,
each op's legal stages as ODS data (03 §5.1); one runtime fold read off
the generated ABI table, one bounded canonicalizer, one view of a match
per visit (04 §5); a verifier local and parallel per function (01 C7).
Below the dispatch, concept-constrained templates whose concepts read
ODS constants, and our own sums folded once (2.7). The open choices:
does a dead crash stay; does the world value stay; what form the match
takes after defunctionalization; what the function and call carry.

## 2. Where the lanes agree

### 2.1 Types (01, with 03, 07, 08, 12, 14)

- **Grades stay in types**; the bare type is the unrestricted grade
  (true today, 01 §3.1 T3 row); the algebra lives in one place: one
  `#idr.grade` attribute with three enum parameters and methods, the
  type-level functions thin wrappers (01 C1).
- **Recursive facts at construction**: `Held` covers labels and "holds
  no component", so a query is a bit test (01 C5; §5.8 T7); the 55 hand
  `ValueFacts` answers come from ODS fields (01 C6); `followed` and
  `isMemoCell` join them (07 D6).
- **The token names its cell**: `!idr.token<!idr.box<T>, @C>`, inferred
  by `idr.take` (01 C3, 03 §3, 07 D4, 12 T3; 0003); four walks back to
  the take and a refusal of a token through a block argument go.
- **A `static` lifetime, ordered** static < heap < frame, written where a
  value is made (01 C2, 08 T1, 07 D6; 0003).
- **A body is one alternative per kind** (plain, list, closures, memo)
  with typed views; the kind/role table goes (01 C4, 14 TD8, 04 C33,
  03 O-60).
- **Type graph and layouts from the table only**, through the
  `AnalysisManager`, never in a verifier (01 C10).
- **Every non-mutable type and attribute in bytecode**, so the 75 MB
  handoff carries no `idr` text (01 C8, 14 TD2, 03 O-99); measure first.

### 2.2 Effects (02, with 03, 08, 12, §5.2, §5.8)

- **One resource tree in one header** replaces the double writes (02 T1;
  §5.2 M3; §5.8 EF2); its shape is the owner's (5.1-5.3).
- **"Does IO" is an effect query**: `PerformsIO`, `ObservableIO` and
  `MayCrashOpInterface` go (02 T7; 03 O-36; §5.2 M1).
- **Static effects in ODS**: `memo.run` and the two updates are written
  by hand though static (02 E49-E50, 03 O-20, O-76).
- **Type-dependent effects from one trait**, the `ConsumesOperands`
  precedent: consumption, fresh linear results, memo reads, a box's
  allocation (02 T3; 03 R3). `call` keeps one hand method, essential
  while its effects are a property (03 O-5).
- **Ops that run a label say "anything"**: `apply` and `force` share
  one bundle (02 T4, 03 O-19).
- **A function's effects are derived from its ops** through one
  generated two-way table, checked per function in parallel (02 T2,
  03 O-65, O-66): the fix for 02 §3.7.
- **The call already carries its callee's effects**, checked in
  `verifySymbolUses`: §5.8 DS2.1's mechanism is today's code (02 §3.5,
  03 O-4).
- **Counts get their own resource** under the heap (02 E5, 03 O-22,
  08 T7; §5.10 R1.5).

### 2.3 Traits and interfaces

- **Marker traits with no reader go or become record fields**:
  `PerformsIO`, `CallsRuntime`, `Primitive`, `TakesReference` (after the
  count resource), `MayCrashOpInterface` (02 T7; 03 O-30).
- **`Primitive` is not implied by `Idr_Runtime`**: 114 against 119 ops,
  different sets (02 F13, 03 O-30), refuting §5.8 DS4's last row.
- **Forwarding is declared once**: `SameValue`, `CarriesOperand`,
  `ResultCarriesOperand` and nine hand flow bodies become one kind per
  op (02 T6: `HandsOn`, `Views`, `Forgets`, `Adopts`, `Gives`); four
  identical range methods go the same way (03 O-73).
- **Ladders over ops become traits or interfaces**: `isa<ReturnOp,
  YieldOp>` (five copies, 02 §3.1, 03 O-92), `feeds` (04 C11),
  `eliminationAt` (03 O-82), `retryBetween` (04 C02).

### 2.4 Ops (03, with 02, 04, 10, 12)

- **Families from lists** (03 R1): one TableGen class per family with
  its effects, symbol, guard and format; members by `foreach`. Today
  the classes exist but every member is a hand `def` (03 M8).
- **One op per semantics, by §5.8 O1's line**, checked against §5.8 DS4
  row by row (03 §3 table). What holds: `cell.new`/`cell.stack` as one
  class parameterized by the resource (O-25); `lin.enter`/`lin.use` as
  one `lin.cast` (O-29); `crash`, `crash_str`, `io.exit` as terminators
  with no successors (R4, O-37, O-39); one `io.clock <kind>` calling one
  runtime function that takes the kind (O-40; the runtime already holds
  the enum, 03 §6); `str.pack`/`str.concat` as `str.from_list` (O-34);
  `closure`/`suspend` as one family (O-18); `divu`/`modu` to `arith`
  behind their guard (03 §3: their lowering is exactly `arith`'s).
  About 189 ops become 168 (03 §5.3).
- **Each op's legal stages are ODS data**, checked by one generated
  trait (03 O-1, O-61; 14 TD6; 04 T7); the frontend then sees only
  `Higher` ops (14 TD6).
- **Match interface methods answer in O(1)**: override `getPredecessors`
  and `getPredecessorValues` (03 O-13; §5.1 C4). The op already answers
  each terminator in O(1); e96bb991's quadratic was a client's (03 §3;
  21 §3.1).
- **No verifier follows def-use chains**: `own.adopt`/`own.give` become
  0003's `own.alloc/load/store` (03 O-28, O-70; 01 T75). A
  frontend-named op changes with its Idris in one commit (14 §6 Q3).

### 2.5 Canonicalization and folds (04, with 02, 03, 12)

- **No `MatchAnyOpTypeTag` remains** (04 §3.1, measured); the two
  patterns rooted at every registered op by name are lanes 06 and 13's
  (04 C65, 21 P-6).
- **One runtime fold read off `Abi<Op>`**: 37 of 47 folders restate the
  ABI row by hand (04 C40, T1); 12 T1 puts that row on the op, so a
  folder and the lowering cannot disagree.
- **One canonicalizer configuration** (04 C59, T3), and an `upstream/`
  patch so a canonicalize that changed nothing preserves analyses
  (04 C62).
- **One answer to "what constructor is this value here"** (04 T6,
  03 O-52; 0003). Greedy for canonicalization only; one-shot rewrites
  on the walk driver, as ours already are (§5.2 Design 2; 04 §3.1).

### 2.6 Verification (01, with 02, 03, 04, 13)

The program verifier's serial walks leave it: a name with no body is
refused at the parser and the bytecode reader, effects coverage moves
into each function's verifier, the root comes from the shared symbol
table (01 C7a; 02 E29; 03 O-62, O-64). The function verifier's walks
fuse into one that numbers ops once (01 C7b), shared with counting's
numbering (21 P-2, 07 D5). The owned rule stays OSSA's checker, reading
consumption from declared effects (01 C7c, T74; §5.10 M3).

### 2.7 The cluster's C++, under the owner's ruling

The lanes' proposals, stated as the ruling's target. Over ops the
dispatch stays MLIR's; below it, templates.
- **One generic runtime fold**: a template over the C function's
  signature, constrained by a concept that reads the generated
  `Abi<OpT>` row and `GuardedOp` membership, supplied by a `foldTrait`
  (04 T1). The lowering reads the same row (12 T1: `concept RuntimeOp =
  requires { OpT::runtimeEntry; }`, filtered over `GET_OP_LIST` at
  compile time, as today, 02 §3.3 B4).
- **Family code as templates over op classes**, constrained by concepts
  reading the family's ODS constants (`isSigned`, `quotient`, `left`):
  today's `DivisionOp`/`ShiftOp` (03 O-48), the bits generated from the
  family record (03 O-31), shared op methods in a trait or a template
  the family instantiates (03 §5.4).
- **One classifier**, `template <Question Q> Does classify(Operation *,
  const Q &)`, MoveOut's question one instance; its `function_ref` and
  the second classifier go (02 T5, E37; 04 C26).
- **Callbacks become templates**: `eachTaken` (02 E55), `edgesOf`
  (01 T47), `forTails` (10 D1a), `DataRemap::Leaf` and
  `Positions::assign`'s `std::function` (03 O-85, 21 P-19). The lanes'
  "keep a cold `function_ref`" (01 T84-T85) becomes the exception the
  owner must accept case by case.
- **Our own sums folded once, exhaustively**: `Source` (02 E39, 01 T41),
  `FlowPoint` (01 T46), `Where` (03 O-94), `DescriptorField` (01 T57),
  `forEachNamed`'s three callbacks as one `Named` sum (01 T82), the body
  sum replacing `Role` and its 18 `get_if` sites (01 C4, T09). `Carriers`
  becomes a bitmask enum (02 E61). Whether a fold is `std::visit` or a
  fold `match` is cxx-Q2/Q-llvm-4, still open.
- **The grade's algebra as constexpr members**, `Lifetime` and
  `Quantity` ordered so `fitsIn` is `<=` and `joined`/`times` are `max`
  (01 C1, C2, T35-T36).
- **Interfaces stay where the set is open**: effects, the forwarding
  kind (02 T6), `ValueFacts`, `RegionBranchOpInterface`, `meets` (04 T2).
- **Sharpened, not settled**: 12 T12's `ArithDomain` concept (one
  template folding over `APInt` and lowering into `arith`) is the
  ruling's idiom; whether it may be a primitive's one meaning is
  AGENTS.md's (5.10).

## 3. Where they disagree

1. **The grade's shape** (§5.8 DS1.1, T4 against 01 C1). Wave 1 wanted
   one enum of legal grades behind an attribute interface. 01 refutes
   both: six (quantity, permission) pairs occur and a seventh is
   constructible, so the halves are two facts (01 §3.1 T4 row, §2.2);
   the set is closed, so an interface is "an interface where the type
   fixes the implementation" (01 NQ4). Turns on Brooks' limit: quantity
   is Idris's fact, permission counting's.
2. **The fourth grade parameter** (§5.8 T5, DS1, DD-Q6 against 01 §3.1).
   Wave 1 read it as a borrow lifetime; it is locality (heap or frame).
   A borrow is a permission with no scope in its type. DD-Q6 asks about
   a parameter that does not exist; the real question is whether a
   borrow gets a scope at all (01 §6, 08 §6).
3. **Consumption: static ODS decorator or typed trait.** §5.2 row 2, M2
   and §5.8 EF3 declare `Arg<..., [MemRead, MemFree]>`; 08 T7 sketches
   `Idr_Consumed<T>`. 02 §3.5 refutes a static form: consumption depends
   on the stage (owned grades appear at idr-rc) and on which uses the
   flow takes over, so a decorator would declare it everywhere always;
   and `Lin` is a fresh value's identity, not consumption (02 §3.3 M2).
   03 M2: the trait exists already. Ours omits the transform dialect's
   `Read` beside `Free` (02 §3.3 A9).
4. **The guards** (§5.8 DS4, 12 T11 against 03). DS4 and 12 want
   `arith.cmpi` plus one `idr.check %cond, <kind>`. 03 refutes it: a
   guard returns its operand refined so the total op "stays below its
   check by data dependence", and checks the very value indexed (03 §3;
   `IdrCheckOps.td:56-73, 105-107`); it keeps five ops of one class with
   a generated cause enum (O-38). Turns on whether def-use ordering is
   load-bearing once the total op is `ConditionallySpeculatable`.
5. **Word ops and shifts** (§5.8 DS4 against 03). DS4 sends six ops to
   `arith` and merges `shls`/`shlu`; 03 holds it only for `divu`/`modu`:
   `divs`/`mods` are Euclidean and wrap `MIN / -1`, shifts are total and
   a signed negative amount reverses (03 O-33, §3).
6. **Regrades and destructuring** (§5.8 DS4, O3 against 03, 02). DS4
   merges six ownership ops into one cast and `take`/`unpack` into one
   destructure; 03 refutes both by effects (`borrow` pure, `share`
   consumes; `take` touches memory, `unpack` does not: O-24, O-27); 02 T6
   keeps them apart with a shared forwarding kind.
7. **The runtime symbol's carrier** (§5.2 M7 against 02, 12, 04). §5.2
   proposed an interface and one interface-rooted lowering pattern; 02
   §3.3 and 12 T1 reject it for the generated `Abi<Op>` table, folded
   over `GET_OP_LIST`. Then 02 T7 deletes the empty C++ trait
   `CallsRuntime` and keeps a record field; 12 T1 (and 03 M7) make that
   trait the carrier (`static constexpr runtimeEntry`); 04 T1 adds a
   folding trait over the row. The ruling admits either generated
   constant and rules out the interface pattern; what is left is one
   carrier, not two.
8. **`RecursiveMemoryEffects` on a match** (§5.1 item 6, 02 T5, 03 O-12
   against 04 C50). Three lanes want a summary or explicit effects; 04
   shows the trait is load-bearing (upstream's `InlineRegionBranchOp`
   refuses an op without it), and DCE pays its walk only for a match with
   no used result.
9. **The parallel agent's trait work** (21 §3.3, §5.3). 101edbc5's
   `Idr_Decides` restates `RegionBranchOpInterface` and re-asks it per
   region on every verification; `getRegionInvocationBounds`, which the
   matches override, is the interface's own statement (21 P-5). The owned
   verifier's `alternatives` is a second classifier and admits `scf.if`,
   which `decides` no longer does (P-3). The agent's `verifyTrait` on
   `SameValue` is work P0 deletes (02 T6; §5.8 DS4).
10. **The world** (§5.3 S0, §5.7 C6 against §5.8 DS2.1). Wave 1
    disagrees with itself: MemorySSA's chain and a VSDG state edge, or
    effects only (5.4).
11. **Output's canonical form** (§5.8 O5 against 04 C32). Canon fuses
    `put_str(show_sint x)` into `put_sint x`; §5.8 composes and fuses at
    lowering; 03 accepts composition if the runtime's put equals its
    show (lane 18).
12. **Smaller splits.** `exit`: a `Halt` write (02 T1) or `MemWrite<IO>`
    (03 R4). `lin.cast`'s fake `MemAlloc<Lin>`: essential (03's table),
    replaceable by consumption (03 O-29), or a `Fresh` node derived from
    the type (02 E4). `con` and memo reads: one trait (02 T3) or split
    ops, `data.box`/`data.con` and `lazy.state` (03 O-8, O-9; 12 T5).
13. **Wave 1 against our code.** §5.2 H2 ("a type verifies once") holds
    only for release `get` (01 §3.1). §5.2 M9 and Design 3 ("uses in
    traits") fail: the use rules follow def-use chains, as §5.8 B10
    forbids and our verifiers do (01 §3.1). §5.8 DS3.1 strands 147
    type-level body reads (01 §2.5). §5.7 M6 is refuted in part: since
    98c6315c no reader meets a type that may change (01 §3.1).
14. **Against AGENTS.md.** Scalar primitives (`divs`, `mods`, shifts,
    `to_char`) have no runtime function; their meaning is written twice
    in C++ and division again in the runtime (03 O-47, NQ2; 12 T12,
    NQ1), against "a primitive's one meaning is the runtime's, which
    folders call". DD-Q1 meets "quantity 1 is a type every transformation
    must keep" (01 §6).

## 4. Suspected bugs and rule violations

| # | what | where | ground | lane |
| --- | --- | --- | --- | --- |
| B1 | A function's summary ignores its ops: `handle.string`'s read of the handle table is lost at the boundary, so a call may move past `io.handle_free` | `Func.cpp:189-202`, `IdrPlatformOps.td:363-366`, `Primitives.idr:373-375` | read; miscompile conjecture, no test | 02 §3.7, E22 |
| B2 | `exit` is neither crash nor diverge: a function that always exits says it returns; unsound once `willreturn` is lowered | `IdrPlatformOps.td:282-287`, `IdentitiesRecord.cpp:160` | read; latent | 02 §3.7, E19 |
| B3 | Memo state is a sibling of IO and no summary bit carries it: CSE may merge a `tag`/`field` read across a memo-dispatch call | `Call.cpp:65-72` | read; conjecture no pipeline reaches it | 02 §3.7 |
| B4 | `force` declares no `Read` of IO: `performsIO(force)` is false, MoveOut special-cases it | `IdrClosureOps.td:101-104` | read | 02 E31, 04 C27 |
| B5 | `closure`, `suspend`, `delay` build a cell and declare no allocation: CSE may merge two; the allocation test misses `delay` | `IdrClosureOps.td:37, 54, 72`, `Expect/Allocation.cpp:28-33` | read; last part conjecture | 02 E43-E44 |
| B6 | `describe` drops a field's lifetime: two shapes get one content key | `DataRemap.cpp:43-48` | read; latent | 01 T27 |
| B7 | `maxNumRewrites` unset: a cycle of patterns hangs inside one iteration (c179ab2d) | `Pipeline.cpp:28-32`, `Optimize.cpp:64-66` | read | 04 C60, C08 |
| B8 | Ten `PerformsIO` ops declare no `IOResource`; `handle.string` reads it with no world; `io.strerror` writes IO against its own comment | `IdrIOOps.td:138-147`, `IdrPlatformOps.td:311-322, 363-374` | measured (records) | 02 §3.1, 03 O-36, O-41 |
| B9 | `NeverRuns`, our model on upstream `ub.unreachable`: an upstream gap worked around in our code (AGENTS.md: patch upstream) | `FlowOps.cpp:344-346` | read | 02 E67, T8 |
| B10 | `OsOp::fold` falls back to the build machine's triple and reads the discardable `llvm.target` (per-target rule) | `OpsPlatform.cpp:22-44` | read | 03 O-81, O-103; 04 C57 |
| B11 | Scalar primitives have no runtime function; meaning written twice in C++ | `Ops.cpp:205-294`, `Conversion/Scalars.cpp:58-160` | read | 03 O-47, 12 T12 |
| B12 | A token through a block argument is refused: a representation limit acting as a refusal | `Program.cpp:106-108` | read | 01 T12 |
| B13 | `own.adopt`/`own.give` verifiers read a producer and a user | `OpsOwnership.cpp:211-230` | read | 03 O-70 |
| B14 | `setVisibility` on `program` and `func` is a silent no-op | `IdrOps.td:97-101, 190-194` | read | 03 O-2 |
| B15 | `BigToIntOp::fold` walks up with no cycle guard | `Fold/Bigs.cpp:176-179` | read | 04 C14 |
| B16 | `foldsWith` clones the consumer per query, linking its uses (the 1b2e31da class) | `Feeds.cpp:75-93` | read | 04 C12 |
| B17 | Context grows on read paths: a `StringAttr` per big fold operand, a `#idr.con` per run read, a `FlatSymbolRefAttr` per return flow query, a dictionary per op per program verify | `Scope.cpp:38-42`, `ConAttr.cpp:188-206`, `FlowOps.cpp:97`, `Func.cpp:74` | read | 04 C41, 01 T32, 02 E64, 01 §3.2 |
| B18 | `DenseMapInfo<FlowAnchor>` has no empty or tombstone key | `FlowEdges.h:363-369` | read | 02 E62 |
| B19 | `idr.array.yield` is `Pure`, `idr.yield` consumes, though both move operands on | `IdrArrayOps.td:215-224`, `IdrMatchOps.td:163-170` | read | 03 O-17 |
| B20 | `Idr_Decides` restates the interface, re-asked per region per verification; `decides` and `alternatives` disagree on `scf.if` | `IdrBase.td:295-303`, `Traits.h:133-147` (101edbc5) | read | 21 P-3, P-5 |
| B21 | Dead: `lookupRoot`, `idr::world()`, three type constraints, pre-defunctionalization canon reached only by fixtures, stale comments, `Does` declared twice | `Func.cpp:92-95`, `Grades.h:65`, `IdrTypes.td:253, 311`, `OpsClosures.cpp:40-91`, `Canon.h:42-44`, `Flow.h:83` | measured, read | 03 O-63, 01 T83, T04, 04 C15, C51-C53, C01, 02 E35 |

Cross-cluster, noted only: 101edbc5's `Positions` is wrong on 67
programs (403/480 against 470/480), lane C's code (21 P-1, P-16).

## 5. The decisions this cluster hinges on

Each groups §8 IDs that are one choice. Options and evidence only.

**5.0 Settled by the owner's ruling (2026-10-21).** For §9:
- **Q1** with its input **cxx-Q1**: MLIR interfaces, traits and rooted
  patterns over ops, types and attributes; concept-constrained templates
  for our own C++; a concept may read ODS, never list ops (the skill to
  read "never an `isa<A, B>` ladder or a C++ concept that lists ops").
- **Q-M3**: concepts, not Modular's concept-free CRTP.
- **Q-llvm-1**: monomorphized templates, one explicit instantiation per
  client where compile time calls for it.
- *For this cluster:* 2.7 is the target. Interim forms fall under the
  hard-cutover half: 02 E56's "until then a `verifyTrait`" on
  `SameValue`, the agent's wave 1 (21 §5.3), any "keep beside" step.
  cxx-Q2/Q-llvm-4 (how a sum is folded) stay open.

**5.1 What keeps a dead op alive** (ods-Q1, DD-Q2, eff-Q2).
- *Kept (today):* every crash, guard, `may_loop` and `force` writes a
  resource (02 §6); `may_loop` exists only for this (10 §6); three
  idr-expect properties and a contract assume it (02 §6); canon moves
  nothing past a crash (04 §6).
- *Deletable (upstream's model):* the 11 guarded total ops already are
  `NoMemoryEffect` plus speculatable, so a guard dies only with its
  total op (02 §6); `may_loop` and `Divergence` go; `checkedBefore`'s
  fold goes to CSE (04 C55). After lowering neither is deletable today;
  `mustprogress` on total functions would let LLVM delete only loops
  Idris proved finite (12 §6).
- *`exit`:* a `Halt` write (02 T1) or an IO write (03 R4).
- *Depends:* 5.2; lane 10's `may_loop`; lane 19; canon's guards.

**5.2 What a crash is ordered with; the tree's shape** (ods-Q3, eff-Q4).
- *With IO:* the runtime flushes output before the message
  (`runtime/Io/Ending.cpp:64-71`), kept today by a second write (02 §6).
- *With heap writes:* nothing reads program memory after a crash; today
  ordered only because the heap is the root. "No" lets CSE move heap
  reads across output and crashes (02 §6, T1).
- *Runtime state* (`handle.string`, `io.strerror`): IO, or a child
  ordered only with what changes it (02 T1, E11-E12).
- *Depends:* 5.3 (T1 and T2 land together); 08's count resource; 12 T2.

**5.3 What a function's summary covers** (eff-Q1, with Q-E2).
- *Today:* {io, crash, diverge}; memory crosses a call by the root's
  accident, memo state not at all (02 §3.7).
- *Proposed:* `memory` and `memo` bits, derived from ops (02 T2).
- *Depends:* T1 cannot land without it (02 §8); 12 T2 lowers the bits
  to `memory`, `willreturn`, `nounwind`.

**5.4 The world** (DD-Q3; §5.8 DS2).
- *Keep, effects derived by one rule:* Idris's own form of IO, 391
  frontend lines (02 §2.5); MoveOut walks its chain; it orders the ten
  buffer and array ops; keys and identities read it as a value (02 §6).
- *Effects only:* `PerformsIO` equals "has a world" (80 = 80); IO ops
  already conflict through effects; it lowers to nothing; the summary's
  world rule is a special case (02 §6). Deletes `world.new`,
  `tabulate_io`, `element.update`, world operands on 44 definitions, the
  clock queries' fake IO (03 O-40, O-43, O-78).
- *Builtin `token`:* ruled out by every lane (B11; 02 §3.5).
- *Depends:* MoveOut's next-IO search (quadratic risk, 02 §8); the
  Idris side's `IOPrim`/`IOResult` (14 §6); the ABI's `World` kind
  (12 §6); lane 11's array pairs.

**5.5 Effects that follow from types** (ods-Q2).
- *One typed trait:* the form works (`Idr_ConsumesOnly`); every
  distinction is already a type (02 §6); 8 hand bodies go (02 T3).
- *Split until static:* `con` in two, memo variants or `lazy.state`
  (03 O-8, O-9); consumption would double 11 ops across idr-rc (02 §6).
- *Depends:* the `con` and memo rows of 03's table; 12 T5.

**5.6 The grade** (types-Q4, DD-Q1, types-Q3; §5.8 DS1, DD-Q6).
- *Attribute with methods, two halves* (01 C1), or *enum of legal grades
  with an interface* (§5.8 DS1.1): section 3 item 1.
- *DD-Q1:* 127 of 434 `lin`s wrap `i64`; counting never reads a word's
  quantity; the linearity verifier and the quantities contract do;
  constants are exempt already. Normalizing loses that coverage; keeping
  it costs `lin.enter`/`lin.use` pairs CSE never merges (01 §6, R6).
- *types-Q3:* `Plain` is "undecided" before idr-rc, "no reference"
  after (01 T38).
- *DD-Q6:* no borrow has a scope; views of written memory die at its
  next write, a scope no region states (01 §6).
- *Depends:* lane 14's `QType`, lane 08's grade writers, 03's constraints.

**5.7 The data type** (Q-O3's table half, types-Q2, ft-Q1; §5.8 DS3).
- *DS3.2, sealed once (today):* no read under a lock since 98c6315c;
  costs left are content-named remakes, storage never freed, a
  name-alone state (01 §6).
- *DS3.1, an index into an ancestor's table:* readable by any nested
  pass; 147 type-level readers lose the body (01 §2.5, R3).
- *DS3.3, structural with back-references:* unmeasured, no precedent.
- *types-Q2:* the frontend emits the boxes, and `fit` goes (01 NQ2)?
- *Depends:* 14 TD2, TD8; lane 06's remaps.

**5.8 The match after defunctionalization** (Q-O1, QL2, ops-Q1).
- *Regions, refined case argument* (03 5.2a): a case binds
  `!idr.ctor<T, @C>`; `field`, `take`, `unpack` lose their tag; three
  enclosing-match walks go (03 O-52, 04 T6). Lanes 08, 10 and the
  lowering already work on single-block regions; tail loops want
  structured output (03 §6, 08 §6, 10 §6).
- *CFG core* (§5.9 Design 2, 03 5.2b): produced successor operands;
  `mergeIdenticalBlocks` merges cases (04 C25); contify gains MLton's
  full form (10 D4); 27 files rewritten (03 §3 Q-W4); an N-block
  region's dominator tree unmeasured.
- *QL2:* every ownership op defines a value already; only the case's
  refined scrutinee is missing; counting undoes the default's rebinding
  (03 §3, 07 §6, 08 §6).
- *Depends:* 04 T4, 08 T3, 10 D1/D4, 12's phase 1, lane 01's new type.

**5.9 What the function and call carry** (DD-Q7, Q-E2, count-Q4,
tail-Q1, Q-AN1).
- *Keep `idr.func`/`idr.call`:* the effects property lets upstream CSE
  and DCE read a call alone, which `func.call` cannot (03 §6). Add
  conventions (08 T6: grading nests per function; a second copy checked
  like `effects`) and a tail kind lowering to `llvm.call`'s
  `tail_call_kind` (10 D1b, 10 §6).
- *Or `func.func`:* facts in analyses; every call unknown upstream.
- *Depends:* lanes 08, 10, 12 (phase 0 rebuilds `func.func` and drops
  facts, 12 §6); 01 C7a.

**5.10 Op granularity at the dialect's edges** (DD-Q4, DD-Q5, ops-Q2,
conv-Q1, arr-Q3, ops-Q3, canon-Q3).
- *DD-Q4:* dialect, frontend and lowering are arith's school already;
  nine pairs split by sign, four by computation (03 §6, 12 §6, 14 §6).
- *DD-Q5:* the clocks need one function taking the kind (03 §6); file
  times need a multi-result ABI (12 §6, 14 §6).
- *ops-Q2/conv-Q1/arr-Q3:* runtime functions for the scalar primitives,
  one C++ template (12 T12), or the `arith` expansion (03 O-47); the
  AGENTS.md text decides which is lawful.
- *ops-Q3:* `divu`/`modu` to `arith` through a generated guard pairing.
- *The guard form:* section 3 item 4. *canon-Q3:* fuse or compose.
- *Depends:* lanes 15/16 (registry), 18 (runtime), 12, 14.

**5.11 How facts are declared** (ods-Q4, ods-Q5, Q-llvm-5, ops-Q4,
ids-Q2, ids-Q3).
- *DRR:* about 16 `Pat`s replace five C++ patterns and
  `StrBuilderOpInterface`'s partial methods; every costly pattern reads
  regions and cannot be DRR (04 §6); nor the lowering's 1:N (12 §6).
- *ods-Q5:* four declarations carry a stage or full-region bit; nothing
  reads them (02 §6).
- *Q-llvm-5:* the generator is already on `MlirTblgenMain`; one tool
  needs upstream's generators as a library (14 §6).
- *ops-Q4:* legal stages on each family (03 O-1).
- *ids-Q2:* properties only for ops the frontend never writes, or
  generated Idris encoders (14 NQ-14-2). *ids-Q3:* native bytecode, or
  text with a format-parser library upstream (14 TD2).
- *Also:* the runtime symbol's carrier (3.7); one "decides" (3.9).

**5.12 Canonicalization's budget and place** (canon-Q1, canon-Q2,
canon-Q4, canon-Q5, with Q-llvm-2, Q-E3, oom-2; eff-Q3).
- *canon-Q2:* a rewrite bound in program units, never a failure, tests
  keeping `test-convergence=true` (04 T3).
- *canon-Q5:* the greedy pass with one match view (04 T4), or MLton's
  per-function normalizer on the walk driver (§5.9 Design 5).
- *canon-Q1:* canonicalize before defunctionalization, or delete the
  closure, suspension and force forms with their fixtures (04 T8).
- *canon-Q4:* `filter-dialects` (04 C61). *eff-Q3:* may CSE merge two
  equal closures before counting?

**5.13 Verification at 70,000 functions** (ods-Q6, Q-M2, Q-O5,
types-Q1, T-Q5). Every build verifies after every pass; the program
verifier runs serially after every program pass and adaptor (01 §6);
on the suites the verifier is 1.6-1.7 % self, never measured at stage 1
(21 §3.4). *types-Q1:* the owned rule in `idr.func`'s region verifier,
or an instrumented check pass (01 NQ1).

**5.14 Renames** (DD-Q8, with T-Q2, T-Q3, Q3). 46 of 189 mnemonics lack
a family (03 §2); 26,104 op names in 334 fixtures (03 §6); the Idris
side is generated, with 73 builder call sites (14 §5.2).

## 6. The order of work, and dependencies on other clusters

From 01 §5.13, 02 §5, 03 §5.5 and 04 §5:
1. **No owner decision needed.** 01 C9, C11, C5, C6; 02 T5, T4, T8
   (the `ub.unreachable` patch); 03 R3, R6 (static effects in ODS,
   shared verifier traits, one defaulted-type directive, result names),
   O-13, the dead code; 04 T3's configuration and patch, then T1, T2, T6.
2. **After 5.1-5.3:** 02 T1 and T2 together, never apart; then 12 T2.
3. **After 5.5:** 02 T3 and the `con`/memo rows of 03's table.
4. **The verifier:** 01 C10, then C7 (needs C5 and the call's symbol
   check).
5. **With counting:** 01 C3 and C2 with lanes 07, 08, 12; 02 T6 once
   the grade ops settle.
6. **Body and grade:** 01 C4 (with 06, 14, 15); C1 after 5.6; C12 and C8
   with lane 14 after 5.7.
7. **Ops:** families from lists after lane 14's typed model (14 TD1);
   merges after 5.10; the match after 5.8; the world after 5.4.
8. **Canonicalization's shape:** 04 T4, T5 after 5.8 and 5.12; T7-T9
   after canon-Q1, canon-Q3, ods-Q4.
9. **Renames last** (03 §5.5).

Each step replaces the old form in the same change; the C++ of 2.7
lands with what it deletes. "Keep, else measure" dispositions (01 T24,
03 O-49) become questions of essence. Dependencies on other clusters:
- **B (analyses, solvers):** `scc_iterator` for the SCC utility (01 T30,
  T50; 03 O-85); one per-function numbering shared with the verifier
  (01 C7b, 07 D5, 21 P-2; Q-llvm-3); lane 06's effects solve reads T2;
  `ValueFacts` as the solvers' type filter (07 D6; §5.6 Design 2); one
  "decides" (07 D5).
- **C (counting, tail, lowering, arrays, runtime):** the static
  lifetime's writer (08 T1); consumption's readers (08 T7); conventions
  on the call (08 T6); `is_unique` as a folding op (08 T8, 12 T4); tail
  kind and the `ReturnLike` ladders (10 D1, D5); array pairs and
  `Forms.cpp` (lane 11); effects to LLVM, the runtime carrier, crash
  sites as data, the guard form (12 T1, T2, T9, T11); the runtime's
  meanings for `put_*`, the clock, the scalar primitives, and an audit
  of the 119 runtime ops' declared effects (lane 18; 02 §8).
- **D (Idris side):** the generator's typed model first (14 TD1);
  bytecode after 5.7 (TD2); stages per op (TD6); the body (TD8);
  registry rows for every merge (lanes 15, 16); same-commit frontend
  changes (14 §6).
- **E (pipeline, tests, history, agent):** function nesting for
  verification (lane 13; drv-Q3); idr-expect properties reading deleted
  facts: crash sites, computes-nothing, builds-value, allocation (02 §8;
  lane 19); T-Q2, T-Q3; hist-Q1; the agent's trait waves as this
  cluster's work, not landed ahead (21 §5.3, perf-Q1).

## 7. Risks, and the measurements that must exist

**Risks.** The tree without the summary hides a callee's buffer and
memo writes across calls; CSE gains are sound only if every heap write
is declared, the 119 runtime ops are unaudited, and a sharper summary
turns any gap into a miscompile (02 §8). Replacing
`RecursiveMemoryEffects` switches off known-case inlining (04 C50). The
generic fold must match every folder bit for bit, and T4's fixed order
makes order-dependent fixtures confluent pairs, not copies (04 §8). The
static lifetime was reverted once (c4d38e9b): grade by what a value
holds (01 R1, 08 T1). C7a assumes the bytecode reader seals the table
first (01 R2). `lin.cast` must keep two entries apart; the refined case
type changes 27 readers; the scalar primitives' meaning in the runtime
makes every fold a C call, in `arith` it needs ranges and narrowing to
run first (03 §8). The agent keeps changing the trait layer on main
(21 §8).

**Measurements** (none taken; no lane built a compiler; stage 1,
release build, one recorded commit):
- The pipeline with and without verification, program and function
  verifier apart (01 M1, 03 §8, 04 §6; lane 13; T-Q5).
- `QType::get` calls and uniquer misses per pass; values per carrier
  and grade (01 M2, M3).
- The handoff's text share and parse time (01 M4, 03 §8, 14).
- Largest matches' case counts against `isRepetitiveRegion` and
  `alternatives` calls (01 M5); a 30,000-case match's bytes as regions
  and as a CFG terminator (03 Q-W3).
- `getEffects` on consuming ops, `getEffectsRecursively` and
  `effectsCovered` time (02 §8); functions whose derived summary differs;
  CSE merges with and without the tree.
- Canonicalize visits and time per match, rewrites per function (the
  budget), `foldsWith` clones, no-op runs (04 §8); table remakes (01 U1).

## 8. What is stale, and what wave 2 left unverified

**Stale** (21 §3.5).
- *101edbc5* (origin/main) added `Idr_Decides` (`IdrBase.td:295-303`,
  `Traits.h:126-149`) on `match`, `match_lit`, `memo.run`,
  `array.update`, `element.update`. 02 §3.1's "Refuted: no `Decides`
  exists ... the one native trait with a `verifyTrait` is
  `ResultCarriesOperand`" is false on main; 02 §2's counts are one
  trait, one `verifyTrait` and three `hasTrait` readers short; the
  proposal's §2 correction is stale likewise. 01 and 03 cite drifted
  lines (+10 in `IdrBase.td` after 292, +26 in `Traits.h` after 123);
  03's per-op trait counts miss it. 04 is untouched.
- *51a4771b* adds no code; main is 403/480, so P0's gates start from
  e96bb991 (21 §5.5); its suite profile names defunctionalization's
  per-function pattern freeze (04 C65, 21 P-6) and a context-lock share
  of about a fifth (B17). §2 counts 191 ops; the lanes measure 189.

**Unverified.** Every cost here is read or counted, nothing ran (01 §8,
02 §8, 03 §8, 04 §8). Open: whether B1 and B3 are reachable (a test
each, 02 §8); whether the 119 runtime ops' effects match their
functions (02 §8); whether `put_*` composition preserves output (03 §8);
the bytecode reader's order and frame grades in body fields (01 R2, U3);
whether `MoveOut<ArrayGetOp>` is redundant (04 C30); whether PDLL
matches region contents (04 §6, recalled); whether any `scf.if` reaches
counting after 101edbc5 (21 P-3); whether `no_inline` stays the type's
fact after specialization (03 §8).
