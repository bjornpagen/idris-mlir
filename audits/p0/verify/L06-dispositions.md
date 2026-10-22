<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L06: every question, decision point and coordinator draft, against the rulings

Lane L06 of the P0 verification swarm. Started at HEAD `e96bb991`
(2026-10-21T21:30Z, branch `main`, the tree dirty with the coordinator's
uncommitted P0 work, read as it is). The rulings are D1 to D55 of
`proposals/0000-mlir-native.md` §2: D53 to D55 arrived while this lane ran
(the coordinator's messages; D45 amended by D53 to D55), and the tables
below use them. The coordinator's decisions are C1 to C8 of §3, C3 and C8
in their revised texts. Proposal line numbers are those of the working
tree when this file was finished; the coordinator edits the proposal
concurrently, so they may drift.

**Marks.** *read* (path:line), *measured* (how), *recalled* (not in
`sources/` or the tree), *conjecture*, *decision* (a ruling Dn, a
coordinator decision Cn, or a draft of synthesis G cited `G:nn`).

**How the tables cite.** Table 1 gives each of the 158 question IDs of
`audits/p0/wave1/questions.md` exactly one row and cites synthesis G's
drafts as `G:nn`; Table 2 gives each of G's 63 drafts, DP-22 to DP-84,
exactly one row and names no question ID. Status codes in Table 2:
**S** superseded by a named ruling (cite it, do not restate it);
**C** consistent and still needed (fold as drafted); **C\*** still
needed, corrected by a named ruling or rule (fold corrected); **X** in
conflict with a ruling, AGENTS.md or a design document (fold only as the
correction says).

**One unrecorded ruling.** The owner struck the stage-1 record decision
(DP-07: who runs stage 1, on which build, what a run leaves) as meta-work
on 2026-10-21: "this is meta-work, above the compiler ... i refuse to
distract you from the more important architectural work", and then
"purge meta work from your mind" (*recalled*: the coordinator's record
`no-invented-process`, outside the tree). The proposal records it only by
omission: §4 jumps from item 6 to item 8 (*read*:
`proposals/0000-mlir-native.md:1063-1065`). Five question IDs rest on it
(Table 1), and so do two of G's drafts (Table 2). This file cites it as
"the strike" and proposes its record (§4 I1).

## 1. Verification

### 1.1 The rulings and coordinator decisions

Every ruling binds; this checks each one's load-bearing claims and its
consistency with the others and with the tree's text. Class: **D** a
defect confirmed in the source; **S** structural incompleteness; **I** an
integration mismatch; **U** unverified behaviour; **O** an optional
simplification.

| id | verdict | evidence, and the correction where there is one | class |
| --- | --- | --- | --- |
| D1 | holds | AGENTS.md:47-50 states it (*read*) | |
| D2 | holds | AGENTS.md:482-486 (*read*); bears on G:52 (§1.4) | |
| D3 | holds | waves 1 and 2 exist (`audits/p0/wave1/`, `audits/p0/01-*.md` to `21-*.md`, *read*) | |
| D4 | holds | AGENTS.md:47-50: "no code of it" (P0's); C8's fixes outside P0 are not bound by it (*read*) | |
| D5 | holds | AGENTS.md:12-18; the skill (*read*) | |
| D6 | holds | AGENTS.md:42-46 (*read*) | |
| D7 | holds with a correction | its closing "Pending: the owner's approval of the skill's new wording" (proposal:186-188) is stale: D47 approved it and the skill reads "never an `isa<A, B>` ladder, and never a concept that lists ops" (`.claude/skills/representation-first/SKILL.md:104-105`, *read*) | S |
| D8 | holds | AGENTS.md:565-568 (*read*) | |
| D9 | holds | AGENTS.md:433-442, 355-360 (*read*) | |
| D10 | holds | AGENTS.md:278-319 (*read*); the lens behind most corrections of Table 2 | |
| D11 | holds | AGENTS.md:37-41 (*read*); §6 asks one question | |
| D12 | holds | AGENTS.md:119-131 (*read*) | |
| D13 | holds | `third_party/Idris2/docs/source/tutorial/typesfuns.rst:704-705` (*read*); upstream's inliner deletes an unused source `let`: a source let becomes `CLet fc x YesInline` (`third_party/Idris2/src/Compiler/CompileExpr.idr:166-169`) and `Inline.idr:200-206` evaluates and drops one used fewer than once (*read*) | |
| D14 | holds | `third_party/Idris2/libs/base/System.idr:307-310`, "Exit the program normally" (*read*) | |
| D15 | holds | AGENTS.md:545-551 (*read*) | |
| D16 | holds | AGENTS.md:552-564 (*read*). Two texts still name the old source: AGENTS.md:579-584 ("generated to both from ODS, and a `.td` change the Idris side names lands with ...") and AGENTS.md:184-185 ("its category in ODS"); proposal §5.6 (proposal:1280, 1284: "the generator reading the records once through the `mlir::tblgen` wrappers", "Lands with the `.td` change") | I |
| D17 | holds | the strike that removed DP-07 the same day is unrecorded (§4 skips item 7, proposal:1063-1065) | S |
| D18 | holds | AGENTS.md:361-368 (*read*) | |
| D19 | holds | AGENTS.md:369-383 (*read*); `design/match-and-counting.md` §12 | |
| D20 | holds | AGENTS.md:449-454 (*read*) | |
| D21 | holds | `runtime/Io/Ending.cpp:63-71` flushes output before the crash's message (*read*) | |
| D22 | holds | AGENTS.md:443-445 (*read*) | |
| D23 | holds | AGENTS.md:458-462 (*read*) | |
| D24 | holds | `foreign/idr/lib/Transforms/Demand/Demand.cpp:62` (`rebuilt`, the derivation it deletes, *read*); AGENTS.md:179-184 states the rule | |
| D25 | holds | AGENTS.md:598-603 (*read*); it supersedes G:30 and corrects G:52 (§1.4) | |
| D26 | holds | AGENTS.md:196-213 (*read*) | |
| D27 | holds | AGENTS.md:462-469 (*read*) | |
| D28 | holds | names land "in the change that brings the new names" (proposal §2): corrects G:27 | |
| D29 | holds | §5.1 still prints the deleted atoms: "`io runtime exit crash diverge read write count memo`" and "not with `diverge`" (proposal:1125, 1146) | I |
| D30 | holds with a correction | the fallback it deletes is `foreign/idr/lib/Conversion/TailCallPlan.cpp:108-112` (`frameBound`, *read*), not a `Transforms` path | S |
| D31 | holds | supersedes G:46 | |
| D32 | holds | §5.5's "stack probes from the target's entry" (proposal:1263) and G:80 conflict with it; §8's driver row (proposal:1365) is moot under D33 | I |
| D33 | holds | corrects G:62 | |
| D34 | holds | `!idr.dest` is linear by its type and parameterized by a `BoxType` (`foreign/idr/include/idr/IR/IdrTypes.td:344-351`, *read*), which D48 deletes: the destination needs restating over families (§4 I12) | I |
| D35 | holds | AGENTS.md:230-232 (*read*) | |
| D36 | holds with a correction | `StatsRange` is snmalloc's (`third_party/snmalloc/src/snmalloc/backend/standard_range.h:41`), chained by the `StandardLocalState` the runtime's configuration selects (`runtime/Alloc/Cells.cpp:69`), not "a type the runtime owns" (*read*) | S |
| D37 | holds | AGENTS.md:232-236 (*read*); corrects G:75 | |
| D38 | holds | supersedes G:42's crash-cause clause | |
| D39 | holds with a correction | "A scope parameter is a handle at run time, so it is part of the function's type" (proposal:657-658) contradicts D48's lifetime variables "passed at calls at compile time only" (proposal:820-822) and AGENTS.md:337-339; the owner's question in §6. Its citation `Ownership.h:22-23` is `foreign/idr/include/idr/Analysis/Ownership.h:23-24` (*read*) | I |
| D40 | holds | §5.3 still writes "a `static` lifetime, ordered static < heap < frame" (proposal:1199-1200) | I |
| D41 | holds | AGENTS.md:244-252 amended (*read*) | |
| D42 | holds | AGENTS.md:531-534 amended (*read*); corrects G:45 | |
| D43 | holds | §5.3's "`lin.enter` and `lin.use` one cast" (proposal:1206) and G:44's link and head meet as one cast family with two members | I |
| D44 | holds | makes G:76 unconditional | |
| D45 | holds as amended | its size rule and "bounded by what it has already tried" are withdrawn by D53 and D55 (`design/elaborator-counts.md` §1.6, §2.5); its citations hold: `compiler/idris/src/TTImp/Elab/App.idr:272-274`, `Ambiguity.idr:326-334` (*read*) | |
| D46 | holds | `compiler/src/IdrisMLIR/Frontend/Translate/Types.idr:853` (`heightWithin`, *read*); corrects G:33's list and G:77 | |
| D47 | holds | SKILL.md:104-105 (*read*) | |
| D48 | holds | §5.3 still writes "`!idr.token<!idr.box<T>, @C>`" and "a data body one alternative per kind" (proposal:1199, 1201); G:40's box half conflicts with it | I |
| D49 | holds | supersedes G:71 | |
| D50 | holds | moves G:47 and G:72 into the specification | |
| D51 | holds | supersedes G:69's tool half | |
| D52 | holds | consistent with G:34 | |
| D53 | holds | `design/elaborator-counts.md` §2.6 (*read*, its summary and §7) | |
| D54 | holds | `design/elaborator-counts.md` §2.6 case 2 | |
| D55 | holds | `design/elaborator-counts.md` §1 (*read* §0, §1.7); the tuple's resolution by the expected type's sort is owed as a fork design (conjecture there) | U |
| C1 | holds | `foreign/idr/lib/Analysis/Ownership/Reuses.cpp:193-195` (the guess) and `Borrows.cpp:179-181` (owned from reuse sites) (*read*) | |
| C2 | holds | not verified in depth here (L01, L20) | |
| C3 | holds (revised) | its path is `foreign/idr/lib/Transforms/Expect/Allocation.cpp:27-30` (*read*); §5.1's last bullet "**A closure acquires its cell** (C3)" (proposal:1163) states the withdrawn first version | D |
| C4 | holds | QTT could widen it by a proof (§3 item 14) | O |
| C5 | holds | the page map's size is `ENTRIES = one_at_bit(address_bits - GRANULARITY_BITS)` times the entry size (`third_party/snmalloc/src/snmalloc/ds/pagemap.h:102-108`, *read*); the 256 GiB stays conjecture | |
| C6 | holds | supersedes G:42's registry clause | |
| C7 | holds | | |
| C8 | holds with a correction | four of its five "outside" items live in code P0 replaces: `maxNumRewrites` in `Pipeline.cpp`, whose pass list specgen prints (one-source §6.2); `OsOp::fold`, in the dialect redesigned whole (D9); snmalloc's failure path, which §5.5 routes through the one out-of-memory path (D23); OPT-48 and OPT-14, in the optimizer G:64 and G:65 rebuild. Only 17 FB-48 (the fork's Windows branches) is outside. The owner's "fix bugs aggressively" (*recalled*) still allows a fix on main now, since main runs until P0 lands; the record should not call them outside | S |

### 1.2 The proposal's text against its own rulings

Integration mismatches found while reconciling, each an edit for the
coordinator (none changes a ruling):
- **M1** §4 has no item 7 (proposal:1063-1065): DP-07's strike is
  unrecorded, so five question IDs resolve nowhere in the proposal. (S)
- **M2** §5.1's row prints `runtime`, `diverge`, `memo`, which D29
  deleted with no alias (proposal:1125, 1146). (I)
- **M3** §5.1's last bullet states C3's withdrawn first version
  (proposal:1163). (D)
- **M4** §5.3: "static < heap < frame" against D40 (static, counted,
  frame and lifetime variables); `!idr.token<!idr.box<T>, @C>` and "a data
  body one alternative per kind" against D48 (no `!idr.box`, the family
  attribute, constructors by position) (proposal:1199-1201). (I)
- **M5** §5.5's "stack probes from the target's entry" (proposal:1263)
  against D32 and C5 (compiled frames static, the guard at least the
  largest frame, checked when built). (I)
- **M6** §5.6's generator "reading the records once through the
  `mlir::tblgen` wrappers" and "Lands with the `.td` change"
  (proposal:1280, 1284) against D16, D50, D51. (I)
- **M7** §6's "patches that reach nothing (06, 28, 63) once QA3 is
  decided" (proposal:1311) against AGENTS.md:620-625, which names carrying
  them a never. (I)
- **M8** §7's gate (proposal:1341-1344, "pending §3"): "the invariant set
  unchanged" and a measurement per adoption as a step gate are the run
  gates the strike removed; AGENTS.md:62-68 (done when built, run and
  passing on all four targets) and AGENTS.md:482-493 (upstream's order)
  already hold what is not meta-work. (I)
- **M9** §8's driver row, "the deep-recursion stack covers the main
  thread only" (proposal:1365), is moot under D33. (I)
- **M10** D7's "Pending" (proposal:186-188), settled by D47. (S)
- **M11** D39 against D48 on the lifetime parameter at run time (§6).
  (I)
- **M12** AGENTS.md:184-185 and :579-584 name ODS and `.td` as the source
  (D16). (I)
- **M13** §0 lists three design documents (proposal:57-59); nine exist
  (`audits/p0/design/`, *read*). (S)
- **M14** §5.2 cites "§5.5" (proposal:1181, 1190) for wave 1's C++ lane,
  but inside the proposal "§5.5" is its own memory section (§0 defines
  "§5.N" as wave 1's only "in every other document"). (I)

### 1.3 Table 1: every question, and what settles it

| ID | disposition | ground |
| --- | --- | --- |
| ods-Q1 | Kept: an unused crash or endless loop in partial code happens; only `total` licenses deletion and `mustprogress` | D13 |
| DD-Q2 | The same answer from the dialect: an unused call to a non-total function is kept | D13 |
| ods-Q3 | A crash is ordered with IO only; the heap is its sibling; a guard's hazard is held by data dependence on its refined result | D21 |
| ods-Q2 | Neither a hand trait nor a split: the rules by which effects follow from types are declared once in the specification (the typed-rule form of declaration) | D9, D16, D27 |
| DD-Q3 | Effects only after the frontend; the world ends at Emit; the derived row's `io` atom is IO's typed carrier | D20 |
| ods-Q5 | Declared in the one source like every other effect fact; nothing reads them yet | D9, D16 |
| Q2 | The parallel agent has stopped committing and no fence is needed; P0 comes first; a run that only measures is not code | D1, D4, D17 |
| Q3 | Yes, in one change; the source is the specification, which regenerates the `.td`, the C++ and the Idris modules, and the frontend imports its closed sets | D16, D50; AGENTS.md (the Idris side) |
| Q4 | Struck as meta-work; AGENTS.md's claim rule (a number states its measure, build and input) is all that stands | the strike (*recalled*); AGENTS.md:69-74 |
| DD-Q8 | Every name is open, the namespace included; a name lands with the change that makes its concept | D28, D29, D40; G:27 corrected |
| QL5 | Equality saturation is outside P0's scope; nothing waits on it | G:25 |
| QL6 | Approved, items 1 to 15 and 17; item 16 dropped with equality saturation | G:29 |
| Q-M4 | No more ports: fresh code from Modular's shapes, to D7's line; the deduplicator port retired | G:26 |
| Q-E4 | Nothing of CIRCT or IREE is ported; their shapes inform fresh code | G:26 |
| QL2 | A rule: every ownership change defines a value, and each case region binds its refined scrutinee, the index refinement included | D19, D48; G:37 |
| Q-O1 | Kept to the lowering: regions as the base, join points, blocks only through `convert-scf-to-cf` | D19, D25 |
| Q-O3 | Yes: a fact a later pass reads lives in a type or a verified property; the data type is the family Idris checked | D48, D39; G:36 |
| Q-E2 | In the IR: a computation's row on its op, verified per function; grades, lifetimes and indices in types | D20, D22; G:36 |
| DD-Q1 | No normalization: `!idr.lin<i64>` stays, quantity 1 being a type every transformation keeps | AGENTS.md:320-329; G:32 |
| DD-Q4 | arith's school: signless types, the sign on the op where the computation differs; one `shl` | G:41 |
| DD-Q5 | One op, its variant an enum of the specification, the ABI row keyed by op and case, runtime entries instantiated per case; a crash site is one entry with its cause as data | G:42 corrected; D38, D16 |
| DD-Q6 | Lifetimes named in types, lexical, on D19's regions | D39, D40 |
| DD-Q7 | Our `idr.func` and `idr.call` stay; a computation's row lives on them | D20; G:38 |
| QA1 | Yes: the storage patch P1 first, carried; no P2 | G:51; AGENTS.md:482-493; D25 |
| Q-E5 | The maintained call graph becomes a carried upstream patch, the RFC its upstream plan; the dataflow-scope RFC is not wanted | D25; G:30 superseded |
| QA2 | Per-function solves with summaries by default; whole-program only where measured to fit after P1 | G:51 |
| QA3 | Patches 06, 28 and 63 are retired now; the pass stays out unless §7 S3's measured per-function trial shows it removes what the optimizer's demand bit leaves | AGENTS.md:73-74, 620-625; G:54 corrected |
| QA4 | Yes: one shared vocabulary of concept-constrained types, not one engine | G:53; D2, D7 |
| Q-O2 | No single model: shared types and three generic algorithms; upstream's framework per function where its state fits | G:53 |
| Q-E1 | Yes: one maintained graph and three solve shapes | G:52 |
| QL3 | Each where it fits: the frontend's translation is relational and semi-naive (0011 O3, 0015 R1 and R2); the C++ solvers share types, the label solve keeps its rules as data; no rule engine in the specification | D44; G:53; one-source §10 |
| Q-M1 | Fresh, informed by Modular's `SCCGraph`, which lacks insertion and merge | G:52 |
| QL1 | A read-only view per solve; no map keyed by `Value` or `Operation *` | G:53; AGENTS.md:416-419 |
| Q-llvm-3 | A function's numbering is one cached analysis, invalidated by change, never maintained across rewrites | G:53; D17 |
| Q-llvm-2 | Confirmed: no budget in an analysis a refusal rests on; an optimizing analysis may stop at a budget in program units, pessimistic, never an error | AGENTS.md:172-195; G:33 |
| Q-E3 | The same line | AGENTS.md:172-195; G:33 |
| Q-llvm-7 | Solved serially first, measured; no double-buffered rounds | G:52 |
| rc-Q1 | Restricted to the frame-limited cases: borrowed only when every caller uses the argument afterwards or its type bounds what it reaches, and the callee neither consumes nor stores it | C1; D26 |
| rc-Q2 | One marking, and grade copies made inside counting; the run-time test only where exclusivity is unknown until run time | G:55; AGENTS.md:528-531 |
| rc-Q3 | Frame-limited, stated for this compiler | D26 |
| rc-Q5 | Confirmed, with the problem's exceptions narrowed by the space promise | G:56 corrected; D26 |
| ods-Q6 | Nesting is a rule of the pipeline (decide, apply, restructure); verification per function, in parallel | G:60 |
| Q-M2 | Full verification after every pass in every build; no split by build | G:60; §9 of the proposal |
| Q-O5 | Kept as the contract, its cost lowered by nesting and by a pass that changed nothing preserving analyses | G:60; AGENTS.md:324-325 |
| QL4 | Required: byte-identical output at any thread count | G:34 |
| Q-llvm-6 | Yes, per solver at one thread and at many, in the unit boxes | G:34 |
| rc-Q4 | Confirmed: no counted cell crosses threads; shards pass cells by detach; the tree holds per shard | G:59; C2 |
| Q-O4 | MLton's order after defunctionalization; polyvariance before the label solve only if the closure sums shrink, as a C++ pass under a budget | G:64 |
| Q-M5 | The bottom-up schedule stays (it is already a demand-driven hybrid) | G:64 |
| Q1 | MLIR's interfaces over ops; templates and concepts below the one dispatch; the skill's wording approved | D7, D47 |
| Q-M3 | A concept-constrained problem type, not Modular's CRTP | D7 |
| Q-llvm-1 | Monomorphized; each solver one explicit instantiation; the cost measured | D7 |
| cxx-Q1 | Adopted as the skill's line: "never a concept that lists ops" | D7, D47 |
| Q-llvm-4 | Banned: every chain gives way to one exhaustive fold | G:73 |
| cxx-Q2 | `std::visit` banned outright for the one fold `match` | G:73 |
| cxx-Q3 | A precompiled header now, with compile-time-cpp §7.2's contents, after the `-ftime-trace` baseline; no C++ modules in P0 | G:74 corrected |
| cxx-Q4 | Extensive hardening everywhere; a failure is D37's internal-error ending; release's cost measured | G:75 corrected; D37 |
| cxx-Q5 | P0 does not wait for reflection, and takes it when a weekly fast-forward brings a usable form | G:25 corrected; D25, D7 |
| ods-Q4 | DRR allowed, its patterns declared in the specification and printed; PDLL refused | G:66 corrected; D16 |
| Q-llvm-5 | Superseded: specgen, in Idris, prints every `.td`, header and Idris module; one slim C++ backend reads upstream's records | D16, D51 |
| oom-1 | Outside the language, a named crash of the machine; an "acquires memory" effect marks where memory enters the arena | D23 |
| oom-2 | The compiler running out is a crash with a named line, distinct from a refusal; every compiler budget is in program units | G:33 |
| oom-3 | Struck with the stage-1 record; profiling and memory measurement stay existing tooling | the strike (*recalled*) |
| oom-4 | Compiled code takes no probes: its frames are static and the guard covers the largest, checked when built; the runtime's units and the tools take `-fstack-clash-protection` | D32, C5; G:80 corrected |
| oom-5 | The cgroup's `memory.max`, read behind the platform layer, kept to; no setting | D36 |
| oom-6 | One status per ending: 111 out of memory; no stack-overflow status, since compiled code cannot exhaust the stack and reaching the guard is an internal error | D37, D32 |
| oom-7 | Settled by representation: frame stacks give chunks back as they shrink, and the native stack is small | D31, D32; G:84 |
| oom-8 | Deferred until a program needs it | G:84 |
| oom-9 | Deferred until 0007's shards; the tree holds per shard | G:84; C2 |
| Q-fc-1 | The code's `Template` is the model; the frontend builds the derivation at quantity 0; the run-time witness goes | D46 |
| Q-fc-2 | Yes, if stage 1 shows the node split's products large; the derivation covers the split flow | G:77 corrected; D46 |
| canon-Q1 | A canonicalization runs before defunctionalization | G:68 |
| canon-Q2 | k times the function's op count, k a constant of the specification; the tests keep `test-convergence=true` | G:33 |
| canon-Q3 | Composed: a pure `show_*` and one `put_str`; the lowering emits the allocation-free entry | G:43 |
| canon-Q4 | Named per point with `filter-dialects` (`idr`, `arith`, `ub`, and what the point needs) | G:67 |
| canon-Q5 | Upstream's pass on the greedy driver, configured once; a carried patch so a canonicalize that changed nothing preserves analyses | G:67 |
| tail-Q1 | One fact on the call, decided once, verified, lowered to `llvm.call`'s tail kind | D30 |
| tail-Q2 | Meaning: a call in tail position never grows the stack; binds and call cycles never grow the native stack; a failure is an internal error | D30, D31, D32 |
| tail-Q3 | One stack per result type | D31 |
| tail-Q4 | Yes, once the TTC keeps a block's parent (0003's B1, absorbed) | G:76; D44, D19 |
| ids-Q1 | Committed, each stamped with the specification's and its own fingerprint; `make check` regenerates and fails on a difference | D49 |
| ids-Q2 | Generated: specgen prints each op's encoder for the Idris writer | D16, D50; G:70 superseded |
| ids-Q3 | Every `idr` type and attribute native in bytecode, its encoders printed from the specification | G:69 corrected; D16 |
| ids-Q4 | Every binder specgen prints is primed; operands are a `Vect n Value` | G:72 corrected; D50 |
| ids-Q5 | Yes: an op's specification names the base primitive it implements; the registry's rows are generated | C6 |
| ids-Q6 | A test: a test-only build without the `Faster` rows, compared on exit, output and refusals | G:35 |
| defunc-Q1 | Adopted: partition refinement merges duplicates inside cycles | G:26 |
| defunc-Q2 | Folded in: the one derivation of rows first runs in defunctionalization's decision and decides `by_name` | G:50; D22 |
| defunc-Q3 | One walk writes the decision into the types; each closure sum is a family the pass declares | G:48 corrected; D48 |
| defunc-Q4 | Kept: a use moving into two sinks unifies them | G:49 |
| count-Q1 | The program's: a rule read off the program before counting, which counting honours | D24 |
| count-Q2 | After: drops first, then reuse guided by them; a parameter the promise rebuilds is owned | C1 |
| count-Q3 | Counting first; tail recursion modulo context is read off the program before counting and written on the call | D34; G:57 |
| count-Q4 | No convention attribute: the call's operand and result types, with its compile-time index and lifetime arguments, are its callee's conventions after substitution | G:38 corrected; D39, D48 |
| own-Q1 | Koka's: drop-guided reuse after placement | C1 |
| own-Q2 | A declarative rule the analysis decides exactly, with a test of its boundary | D24 |
| own-Q3 | Grade copies stay inside counting, made by the optimizer's clone-and-key template | G:55 |
| conv-Q1 | One C++ template over a numeric domain: the folder, the integer ranges, the `arith` expansion; the runtime includes it | D41 |
| conv-Q2 | Two program passes, then the lowering as a function pass | G:61 |
| conv-Q3 | Counting's last step at the `idr` level | G:58 corrected |
| conv-Q4 | Yes: `idris_rt_crash_at(cause, file, line, column)` | D38 |
| conv-Q5 | Yes: one prefix on every program symbol | G:83 |
| ops-Q1 | Yes, as D48 refines it: the case binds the scrutinee at its constructor of the family application, the constructor's index variables at quantity 0 | G:37 corrected; D48 |
| ops-Q2 | Neither alone: one template is the meaning, expanded into `arith` at the stage that needs it | D41 |
| ops-Q3 | Yes: `divu` and `modu` become a guard and `arith.divui`/`arith.remui` on the guard's refined operand | D41, D21; §5.3 |
| ops-Q4 | Yes: each family declares its legal stages in the specification; one generated trait checks them | G:47 corrected; D16, D50 |
| ft-Q1 | Split: Idris's facts (Nat-likes as numbers, pointer-like words as `u64`, the enumerated crash alternatives) are the frontend's; inline or in a cell, a one-field collapse included, is the family's layout | G:40 corrected; D48 |
| ft-Q2 | Both forms in P0: 0011 whole, with 0010's A0 and 0015's R1 and R2 | D44 |
| ft-Q3 | No: polyvariance, if taken, is a C++ pass, never the frontend's | G:64 |
| ft-Q4 | The module is the one output; the Core dump goes | G:78 |
| ft-Q5 | Neither the fork's `Error` nor a side channel: the translation returns its own typed refusal | G:79; D50 |
| rt-Q1 | Koka's signed count without atomics, confirmed by instructions per `inc` and `dec` | G:59 |
| rt-Q2 | Moved: the live-cell count lives in the checked runtime | G:81 |
| rt-Q3 | Programs start on strict hosts | D35; C5 |
| rt-Q4 | The test writes past the shipped buffer; no compiled-in seam | G:81 |
| rt-Q5 | A seed-range hook as a carried snmalloc patch; our copy of the config goes | G:82; D25 |
| arr-Q1 | Taken in P0, with its two carried patches | D43 |
| arr-Q2 | Two members of one cast family, link and head, chosen by the translation | G:44 corrected; D43 |
| arr-Q3 | The specification's op, with upstream's tensor and linalg semantics; AGENTS.md amended | D42 |
| arr-Q4 | `idr.transpose` goes; `transpose` means upstream's `linalg.transpose`, its permutation written once | G:45 corrected; D42 |
| arr-Q5 | In P0's cutover | D43 |
| Q-AN1 | Tail position: one fact on the call. "Gives back argument i": a verified property of the function | D30; G:38 corrected |
| Q-AN2 | The optimizer is the one dynamic client of a static spine | G:52 |
| Q-AN3 | Per function with callers-first argument summaries, after P1's measurement | G:51 |
| types-Q1 | The owned rule's whole-function walk goes: a view's lifetime is its type and its region, checked locally | D39; G:60 corrected |
| types-Q2 | Superseded: no boxes and no table; inline or in a cell is computed from the family | D48 |
| types-Q3 | Two cases: undecided (legal only before counting) and holds no reference | G:39 |
| types-Q4 | One closed grade attribute with methods, no interface | G:39 corrected; D40 |
| Q-FB1 | The fork stops building the run-time tree; the TTC keeps `scTy` and the clause index | AGENTS.md:569-578; G:76; D44 |
| Q-FB2 | An internal error: the translation keeps Idris's proof, and Emit reads quantities, never counts uses | AGENTS.md:320-329; G:32 |
| Q-FB3 | Removed: the automatic search ends by the path rule, a growth holding an unknown is postponed to the last chance, and the ambiguity count is deleted with the tuple settled by representation | D45, D53, D54, D55 |
| Q-opt-1 | MLton's order: specialize to completion, inline once on the final graph with true counts, normalize | G:64 |
| Q-opt-2 | Moot in that order: counts are true counts on the final graph | G:64 |
| Q-opt-3 | The run's own interned data, freed with the pass, taking no context lock | G:65 |
| Q-opt-4 | Yes: the signature half is the optimizer's demand bit | G:54 |
| drv-Q1 | Struck as meta-work; a number states its build | the strike (*recalled*); AGENTS.md:69-74 |
| drv-Q2 | Yes, in the specification: one list printed into `Passes.td` and the pipeline's body, imported by the frontend | G:47 corrected; D16, D50 |
| drv-Q3 | Yes, a rule | G:60; §5.4 |
| drv-Q4 | Every thread on one small stack, D33's measured bound, through a carried `StdThreadPool` patch | G:62 corrected; D33 |
| drv-Q5 | One home beside the object on every target | G:63; AGENTS.md:83-91 |
| drv-Q6 | Struck as meta-work; profiling stays existing tooling | the strike (*recalled*) |
| T-Q1 | AGENTS.md's done rule, and a test's committed expected files as its specification; the frozen-set gate is struck | AGENTS.md:62-68, 142-146; the strike (*recalled*); G:22 superseded |
| T-Q2 | Behaviour to program tests, a pass's guarantee to an idr-expect property, every other fixture deleted, none renamed by script | G:28 corrected; the owner's test rule (*recalled*) |
| T-Q3 | Open to renames; the properties generated from the specification | G:27; D16 |
| T-Q4 | Test-only per-function records under nesting | G:60 |
| T-Q5 | From `--mlir-timing`; the every-pass rule kept whole | G:60 |
| eff-Q1 | Every state a caller must order with, derived from ops, checked per function | D22 |
| eff-Q2 | Its own effect under IO; a function that may exit is never `willreturn`; the call is `noreturn` | D14 |
| eff-Q3 | An unrestricted construction is pure and may merge; a linear or owned result takes a fresh identity; memory is acquired at `cell.new` | C3 |
| eff-Q4 | A read-only child of IO | D27 |
| perf-Q1 | No fence; the agent has stopped; P0 may undo its work | D17 |
| perf-Q2 | Off the owner's list; counting's redesign decides it; the numbering is a cached analysis, never maintained | D17; G:53 |
| perf-Q3 | Struck as meta-work | the strike (*recalled*) |
| hist-Q1 | Upstream, then upstream patched, then ours; never dropped with the middle step skipped; never a removal on an unmeasured claim | AGENTS.md:73-74, 482-493; G:24 superseded |
| hist-Q2 | Done means built, run and passing on all four targets | AGENTS.md:62-68; G:22 superseded |
| hist-Q3 | Retired now: nothing in the tree reaches them | AGENTS.md:609-611, 620-625; D25; G:54 |
| hist-Q4 | P0 absorbs 0003 whole | D44 |
| hist-Q5 | Only by a dated ruling of the owner, named in the commit | D17; AGENTS.md:27-36 |

### 1.4 Table 2: every decision of synthesis G

| DP | G's decision, in short | status | against which ruling, with the evidence | would the owner overrule? |
| --- | --- | --- | --- | --- |
| DP-22 | a step lands built on four targets, failing no test, passing a frozen invariant set, leaving a stage-1 record; a receding frontier fails it; WIP allowed with the new path unreachable | S, and X | The build half is AGENTS.md's done rule (AGENTS.md:62-68). The stage-1 record, the frontier gate and the frozen set are run gates and records the strike removed (*recalled*). A new path landed unreachable beside the old is a dual path (AGENTS.md:51-61). D37 changes every crash's committed stderr, so "unchanged" cannot hold at that step | yes, the additions |
| DP-23 | each `.td` change lands with the Idris side it regenerates | S | D16 (no hand `.td`; the specification regenerates both sides), D50 (the frontend imports closed sets); AGENTS.md:579-584 | no |
| DP-24 | adopt, keep or remove upstream only on a stage-1-scale measurement; its AGENTS.md wording returned | S | AGENTS.md now holds the rule: upstream's order with "not dropped ... with the middle step skipped" and the never-line on a 0.84 s adoption (AGENTS.md:482-493), and "a removal resting on an unmeasured claim" (AGENTS.md:73-74). As a §7 step gate it is meta-work | yes, the gate; the rule stands |
| DP-25 | equality saturation and static reflection are out | C\* | Equality saturation out stands (no wall from phase ordering, 04 §6). Reflection: dependencies fast-forward weekly (D25, AGENTS.md:112-115) and D7 asks for every static fact at compile time, so it is taken when the pin has a usable form; "out" reads as never | likely, for reflection only |
| DP-26 | no more ports; deduplication by partition refinement, merging inside cycles | C | D7 (concepts, not Modular's CRTP); D25 carries the symbol-hook patch | no |
| DP-27 | every name open; renames land last, in their own step | X | The open names stand (D28, D29, D40: "maximally churn the names"). The last step conflicts with D28: the old resource names go "in the change that brings the new names, with no alias, shim or dual spelling"; a later rename step would print old names inside the new design | yes, the step order |
| DP-28 | behaviour to program tests, properties to idr-expect, brittle deleted, the rest renamed once by a script | X | "The rest renamed" conflicts with the owner's standing rule: "i would rather kill all the useless tests and have NO tests than have tests that are ceremony" (2026-10-15, *recalled*), and with D16's cutover A, which deletes every fixture of a state the specification cannot construct (one-source §8.3) | yes, "the rest" is deleted |
| DP-29 | snapshots approved, item 16 dropped | C | housekeeping; no ruling bears | no |
| DP-30 | the call-graph RFC recorded to send later; the dataflow-scope RFC not | S | D25 and AGENTS.md:598-603: "a change upstream we need ... is carried as a patch, always ... ESPECIALLY if it's meant to be upstreamed"; the RFC becomes the carried patch's upstream plan, folded into the spine's entry | yes |
| DP-31 | closures, suspensions and `delay` declare their allocation; CSE merges none | S | C3, revised under the owner's word | already overruled |
| DP-32 | `!idr.lin<i64>` stays; Emit reads quantities; a quantity-1 binder used twice at Emit is an internal error | C | AGENTS.md:320-329 (FB-28 a never); D48 (a field's quantity has no erased case) | no |
| DP-33 | no budget in the named refusal analyses; others stop at a budget in program units; `maxNumRewrites` k times the ops; the compiler's out of memory named | C\* | The named list changes: D24 makes the uniqueness refusal the rule decided by exclusivity (idr-demand's derived promise goes); D45 to D55 end the elaborator's searches by construction; D46 deletes `Finite`'s run-time re-check. k becomes a constant of the specification (D16) | no |
| DP-34 | byte-identical output at any thread count; frozen per-solver answers | C | an existing promise of the tool (13 §6); D52 holds specgen to the same purity | no |
| DP-35 | the `Faster` rule tested by a test-only build; hooks indexed by kind | C | C6 generates the registry's rows; the test-only build omits the `Faster` rows | no |
| DP-36 | facts into types or verified properties; summaries in the IR | C | D20, D22 (rows on ops, verified), D39, D48 (signatures and families in types); its returned part (the data type's form) is D48 | no |
| DP-37 | each case binds `!idr.ctor<T, @C>`; `tag` attributes go | C\* | D19 confirms the regions. D48 refines: the refined type names the family application and the constructor by its position (labels are printed, never looked up), binds the constructor's index variables at quantity 0 under its equation, and its fields at their quantities | no |
| DP-38 | `idr.func`/`idr.call` carry the row, tail position, the callee's conventions, "gives back argument i" | C\* | Tail position is D30's. The row is D20's. Conventions: the call's types, with D48's compile-time arguments (`idr.call @map<k, frame>`), already are its callee's conventions; an attribute beside them is "a copy kept in step by a verifier" (AGENTS.md:265-277). "Gives back": a verified property of the function, copied to the call only where a nested pass must read it, as the row is | no |
| DP-39 | one `#idr.grade` with constexpr methods; lifetime static < heap < frame, join `max`; `Plain` two cases | C\* | D39, D40: the constants are `static`, `counted`, `frame`, with lifetime variables beside them; the lifetimes in scope at a point form a chain by lexical nesting, so `fitsIn` is outlives and join the innermost; printed `!idr.q<1, own, T, ρ>`; D50: the frontend imports the grade's parts. The quantity already has no zero (`foreign/idr/include/idr/IR/IdrBase.td:80-87`, *read*) | no |
| DP-40 | the frontend decides one-field collapse, `!idr.nat`, pointer-like `u64`, crash enumeration and the boxes that break cycles | X | D48: the family is carried whole, `!idr.box` is no type, the `#idr.types` table is deleted, and inline or in a cell is "a function of the type and its lifetime computed once"; the box and collapse half is superseded. The Nat, pointer-word and crash-enumeration facts stay the frontend's | yes, the box half (D48 already did) |
| DP-41 | signless types; `shls`/`shlu` one `shl` | C | consistent with D41 | no |
| DP-42 | one op per operation with an enum; ABI rows per op and case; the registry the one place naming a base primitive | C\* | The registry clause is superseded by C6; the crash cause by D38 (one entry, the cause a shared global); enums are declared in the specification (D16) | no |
| DP-43 | output composes a pure `show_*` and one `put_str` | C | D10 (a known `show` folds); D23 (an unused allocation goes) | no |
| DP-44 | a link and a head are two ops, chosen by the translation | C\* | D43 makes `lin.enter` and `lin.use` one cast (§5.3): link and head are that family's two members, chosen where the translation threads a quantity-1 `LArray` | no |
| DP-45 | `idr.transpose` goes; a tabulate carries the permutation as its indexing map | C\* | D42: `transpose` means "the op the Idris specification declares ... with upstream's tensor and linalg semantics", and upstream has `linalg.transpose`, whose permutation is written once; AGENTS.md:360: the `idr` dialect holds only what upstream's do not mean | no |
| DP-46 | one frames stack per member result type | S | D31: "one stack per result type ... a frame of the wrong type is unrepresentable" | no |
| DP-47 | each family declares its legal stages; the pipeline one TableGen list | C\* | The substance stands; the form is D16 and D50: stages and the pipeline are the specification's, printed into `Passes.td` and the pipeline's body, imported by the frontend; `IdrPassStages.txt` and `IdrPassRoles.txt` go | no |
| DP-48 | one walk writes the label solve's decision into the types | C\* | D48: each closure sum is a family the pass declares ("every type comes from a declaration (Idris's, or one a pass declares)") | no |
| DP-49 | a use into two sinks unifies them | C | no ruling bears; plan size against set precision (06 §8 item 7) | no |
| DP-50 | no idr-effects pass; the derivation runs in defunctionalization's decision | C | D22's one derivation; D20 deletes the world-typed reading it replaced; `design/effects.md` §6.7 is indifferent | no |
| DP-51 | P1 first; Ranges, Borrows, Returned measured; per-function solves stay; Borrows becomes a marking; no P2 | C\* | AGENTS.md:482-493: Borrows leaves the framework only on the patched framework's measurement; stated as settled beforehand it repeats ffa91113. C1 and D26 shrink its problem first | no |
| DP-52 | our `ProgramGraph`, three solve shapes, the optimizer its one dynamic client | X | AGENTS.md:482-493 (upstream, patched, then ours) and D25: G chose its own graph because `mlir::CallGraph` lacks callers and dense ids, which is a patch, and records an RFC to send later, the step D25 forbids skipping | likely: a carried patch to `mlir::CallGraph` first |
| DP-53 | shared concept-constrained types, three algorithms, the numbering a cached analysis | C | D2, D7, D17; AGENTS.md:416-421 | no |
| DP-54 | `remove-dead-values` stays out; a demand bit; patches 06, 28, 63 retired now | C\* | Retiring the patches now is AGENTS.md's (AGENTS.md:620-625 names carrying them a never). "Stays out" pre-decides §7 S3's measured per-function trial, against AGENTS.md:73-74 | no |
| DP-55 | one marking and grade copies inside counting; the run-time test only for run-time facts | C | AGENTS.md:528-531; D24 (no promise rests on a copy) | no |
| DP-56 | drops at last use, with four exceptions | C\* | D26 narrows the borrowed-argument exception to C1's borrows | no |
| DP-57 | counting before TRMC; tail modulo cons decided once and written on the call | C\* | D34 makes it a promise read off the program before counting; `!idr.dest` is parameterized by a `BoxType` (IdrTypes.td:344-351), which D48 deletes | no |
| DP-58 | the take's expansion at the `idr` level; `idr.is_unique` folds on exclusive and frame values | C\* | D39, D40: a cell of `static`, `frame` or a lexical lifetime has no count word, so `is_unique` takes only `counted` values; D19: the path with no reuse token jumps to a join region's specialized copy, so a token is never null (today "or null", `foreign/idr/include/idr/IR/IdrOwnershipOps.td:33-35`, *read*) | no |
| DP-59 | no counted cell shared between threads; Koka's encoding | C | AGENTS.md:253; C2; D40 (`static` typed) | no |
| DP-60 | full verification after every pass, cheapened by nesting; the owned rule in `idr.func`'s region verifier | C\* | D39 deletes the owned verifier's whole-function walk; what remains of the owned rule is local, in each op's verifier | no |
| DP-61 | two program passes, then the lowering as a function pass | C | §5.4's decide, apply, restructure | no |
| DP-62 | workers on reserved stacks like the main thread, by a `StdThreadPool` patch | C\* | D33: the 64 GiB main-thread reservation goes; every thread gets one small size from the measured bound | no |
| DP-63 | the prepared runtime's bitcode in one home | C | AGENTS.md:83-91 | no |
| DP-64 | bottom-up; MLton's order; polyvariance a C++ pass under a budget | C\* | D48: keys gain known index terms and lifetimes, so a call at a known index gets the copy whose shape the index fixes | no |
| DP-65 | keys as the run's interned data | C | §5.2 (arenas, per-run interning) | no |
| DP-66 | DRR allowed, PDLL refused | C\* | D16: a DRR pattern is a `.td` record, so it is declared in the specification and printed | no |
| DP-67 | upstream's canonicalizer configured once, with a carried patch | C | AGENTS.md:482-493; D25 | no |
| DP-68 | a canonicalization before defunctionalization | C | C3 lets equal unrestricted closures merge there | no |
| DP-69 | native bytecode; one TableGen tool on `MlirTblgenMain` for the C++ and the Idris writer | C\* | The tool half is superseded by D16 and D51 (specgen prints; one slim C++ backend for upstream's records); native bytecode stands, now covering D48's family attributes | no |
| DP-70 | each op's property encoder generated for the Idris writer | S | D16, D50; one-source §6.2 (specgen prints the encoders) | no |
| DP-71 | the generated Idris modules checked in and fingerprinted | S | D49 (every generated file committed, stamped with the specification's and its own fingerprint) | no |
| DP-72 | every generated binder primed | C\* | moves into specgen's printer; operands are a `Vect n Value` (D50) | no |
| DP-73 | one fold `match`; `std::visit` banned | C | D7; compile-time-cpp §3.5 | no |
| DP-74 | a PCH of LLVM's, MLIR's and the standard library's headers, none of ours | X | compile-time-cpp §7.2 puts `IdrDialect.h` with its generated declarations and the vocabulary headers in the PCH; both name the `-ftime-trace` baseline first. Selected: §7.2's contents (an op change rebuilds the ~260 includers either way, one-source §7.4) | no |
| DP-75 | extensive hardening; a failure routed to a named crash | C\* | D37: a hardening failure is a bug of the runtime or the compiler, an internal error (the message, then `SIGABRT`), not a crash's status 1 | no |
| DP-76 | the fork stops building the run-time tree; `scTy` and the clause index; case blocks in place | C | AGENTS.md:569-578; D44 removes its "waits on 0003" condition; D19 | no |
| DP-77 | the growth check's flow splits by node if stage 1 shows it large | C\* | D46: the derivation built at quantity 0 must cover the split flow | no |
| DP-78 | the Core dump goes | C | AGENTS.md:265-270; D44 | no |
| DP-79 | a refusal is the translation's own typed value | C | D50 (refusal categories imported); AGENTS.md:585-586 | no |
| DP-80 | inline probes in every function; `-fstack-clash-protection`; a guard below the signal stack | X | D32 and C5: compiled frames are static and the guard is at least the largest, checked when built, so a probe in compiled code tests at run time what the build proved (D10). The clash protection and the guard's place stand | yes, the compiled-code probes |
| DP-81 | no live-cell count or `IDRIS_RT_LIVE` in shipped programs | C | AGENTS.md:316-319; D37 | no |
| DP-82 | snmalloc's seed-range hook as a carried patch | C | D25 | no |
| DP-83 | one prefix on every program symbol | C | no ruling bears | no |
| DP-84 | stack pages returned, a pressure signal, shards' limits deferred | C\* | the stack-pages part is settled by D31 and D32 | no |

**Counts** (*measured*: counted from the table above): 8 S, 25 C, 24 C\*,
6 X; 63 in all. The owner would overrule 6 (DP-22's additions, DP-24's
gate, DP-27's step order, DP-28's rename, DP-30, DP-80's probes), likely
2 more (DP-25 on reflection, DP-52), and has already overruled 2 (DP-31
by C3, DP-40's box half by D48).

### 1.5 Questions no ruling or decision covers

**From the register.** None is open on its own terms after D53 to D55.
Five rest on the strike, which the proposal does not record:
- **Q4, perf-Q3, drv-Q1, oom-3, drv-Q6** (DP-07). Options: (a) §4 item 7
  records the strike, so each resolves to a dated text; (b) §4 stays
  silent, so the five resolve nowhere and the struck question returns
  with the next reader of the register. Selected: (a), text in §4 I1.

**From the rulings' interplay** (new; each also an improvement in §4):
- **N1. Is a lifetime parameter a value at run time?** D39 against D48.
  Options and recommendation in §6 (the owner's).
- **N2. Where D24's rule meets linear arrays.** D24 states the in-place
  promise for types of kind `in_place`, by a take-apart and a rebuild;
  `mlir-array`'s linear arrays are updated in place by a link "in place,
  always" (11 N2) with no take-apart. Options: (a) the link is the
  promise's array form, read off the program before counting and refused
  when exclusivity fails, as D24's constructor form is; (b) a head (a
  copy) is the link's lawful fallback, so arrays promise nothing.
  Selected: (a) as today's meaning restated (coordinator, L08 and L12);
  if the owner reads it as a new promise, it is the owner's.

## 2. Boundaries

### 2.1 The end state of the record

- **§2** holds D1 to D55, each dated, in the owner's words where quoted;
  only the owner adds or amends one.
- **§3** holds C1 to C8 and, once folded, the 55 entries of the appendix
  (proposed numbers C9 to C63), each naming its decision point, the
  questions it closes, the rulings it was corrected under, and what it
  deletes. G's eight superseded drafts are cited in one closing line, not
  restated.
- **§4** holds only what is open for the owner: the execution's shape
  (§7), the lifetime question if the owner takes it (§6), and a recorded
  item 7 for the strike.
- **Every question ID** of the register resolves to exactly one of: a
  ruling, a coordinator decision, the strike, or an open §4 item (Table 1).

### 2.2 Constructor provenance

| fact | constructed by | who alone may | consumers |
| --- | --- | --- | --- |
| a ruling Dn | the owner's dated words, recorded in §2 by the coordinator | the owner | every lane; AGENTS.md's rule text |
| an AGENTS.md rule | the coordinator, from the rulings, the owner's words quoted | the owner's rules; the coordinator writes them | every agent |
| a coordinator decision Cn | the coordinator under D6, with its reason | the coordinator; reversed only by the owner | lanes; the implementation packet |
| a question's disposition | this file's Table 1, folded by the coordinator | the coordinator, from rulings and decisions | the register; lanes |
| a G draft's status | this file's Table 2 | the coordinator | §3's fold |
| an open owner item | §4 | listed by the coordinator; settled by the owner, one at a time (D11) | the owner |
| a design document's "decided here" | its design agent | binding only once a ruling or a Cn records it | lanes |

Failure paths: two rulings that disagree (D39, D48) go to the owner, never
resolved by editing a ruling's text; a draft in conflict with a ruling is
folded only as corrected; a superseded draft is cited, never restated
beside its ruling.

### 2.3 Seams with the other lanes

Each corrected or conflicting draft has its design in another lane's
file; this file fixes only its disposition:
- L03 (one source): G:47, G:66, G:69, G:70, G:71, G:72.
- L04 (families): G:37, G:40, G:48 and the destination of G:57.
- L05 (lifetimes): G:39 and §6's question.
- L07 and L08 (counting, exclusivity): G:51, G:55, G:56, G:58, and N2.
- L09 (control flow): G:37's regions; the token's join-region copy.
- L10 (tail, frames, stack): G:57, G:62, G:80, G:84.
- L11 (runtime): G:75, G:80's runtime half, G:81, G:82, C8's snmalloc item.
- L12 (arrays): G:44, G:45, N2.
- L13 (ops, canonicalization): G:41, G:42, G:43, G:66, G:67, G:68.
- L14 (analyses): G:51, G:52 with G:30, G:53, G:54, G:60.
- L15 (C++): G:25's reflection, G:73, G:74.
- L16 (frontend): G:76, G:77, G:79, G:40's frontend half.
- L18 (defunctionalization, optimizer): G:48, G:49, G:50, G:64, G:65.
- L19 (tests): G:22, G:28, G:34, G:35.

### 2.4 What this deletes, and what must stay distinct

This lane deletes nothing. Once folded, G's draft and F's coordinator half
are history, read through §3. Distinctions that must remain: the owner's
ruling against the coordinator's decision; a ruling's text against a
design document's; superseded (cite), corrected (restate) and conflicting
(propose the overrule); a question settled by a ruling, by a decision, or
by the strike.

## 3. QTT

**Where quantities enter the record.** Idris's checked TT carries 0, 1 and
many on binders and fields, with erased indices and proofs. The rulings
keep them: AGENTS.md:320-329 (quantity 0 is no value; quantity 1 a type,
checked after every pass); D48 (a field's quantity is one or many; index
and lifetime variables are quantity-0 parameters passed at calls at
compile time); D24 (quantity 1 makes a parameter subject to the in-place
rule; exclusivity is the caller's separate obligation); D26 ("an argument
whose binder in the caller is linear is passed owned, read off its
type"); D31 (frames linear, uncounted); C3 (unrestricted constructions
pure, linear results a fresh identity). Lost today: Emit's demotion of a
quantity-1 binder (17 FB-28; G:32 makes it an internal error); erasure
read five ways (D44's 0003 reads Idris's own `eraseArgs`).

**Where quantities settle a question differently than G drafted:**

| draft or question | G drafted | what the quantities settle | paid today, or made unwritable |
| --- | --- | --- | --- |
| G:31 | every construction allocates; CSE merges none | many: pure, mergeable; one: a fresh identity (C3) | equal unrestricted values merge and hoist; merging two linear values, which would use one twice, cannot be written |
| G:32 | `!idr.lin` stays on words | the same, for a stronger reason: a handle is a word used once | normalizing would make "close twice" writable |
| G:37 | `!idr.ctor<T, @C>` | the case binds the constructor's index variables at 0 under its equation and its fields at their quantities; an erased field does not exist | `head`'s `@Nil` at `n + 1` cannot be written (D48); no tag read |
| G:38 | conventions copied onto the call | the call passes its index and lifetime arguments at 0, at compile time; its types are the conventions | no convention attribute and no verifier keeping one in step |
| G:39 | quantity an ordered enum | it has no zero case already (IdrBase.td:80-87); lifetime variables are 0 (D48), so a run-time handle, where needed, is a separate value (§6) | an erased value in the IR cannot be written; a view-only lifetime costs no register |
| G:40 | the frontend collapses one-field types | "one field" counts only fields of quantity one or many; the layout reads the family's quantities | an erased field can never make a cell |
| G:44 | link chosen by the translation | the link is where a quantity-1 `LArray` binder is threaded | the per-query re-proof goes |
| G:51, C1 | borrow inference over every parameter | one call passing a quantity-1 binder of a type that does not bound what it reaches makes the parameter owned, with no solve (D26, C1) | inference runs over the rest only: a solve for a fact the type proves is no longer paid |
| G:54 | dead parameters by a demand bit | quantity 0 is no parameter; a quantity-1 parameter is used once in the program as written; only many-quantity parameters can be dead | the demand bit's domain shrinks |
| G:56 | drops at last use | a quantity-1 value is used at most once on every path (IdrTypes.td:272-273, *read*): its last use is that use, or the entry of a path that does not use it | placement computes no liveness for linear values |
| G:57, D34 | a destination written on the call | `!idr.dest` is linear by its type (IdrTypes.td:344-351) | a second write cannot be written; restated over families since `!idr.box` goes |
| G:58 | the take's token, "or null" | a token is used exactly once (recycled or freed) and present by its type | a double recycle, a leaked token and a run-time null test cannot be written |
| G:64 | keys from grades and labels | quantity-0 index terms join the key (D48) | a call at `#Vect[3]` gets an inline, tagless copy |
| C4 | never a user's `Semigroup` | an erased proof of associativity in the program costs nothing at run time and could license a user's operation (*conjecture*; L10's to weigh) | widens the accumulator by a proof instead of a list |
| D24 | the refusal | reads quantity 1 on the parameter, exclusivity at the call | consistent; nothing to add |

**Used harder.** Three facts quantities prove that the design still pays
for: borrow inference over parameters a quantity-1 caller already makes
owned; placement's liveness for linear values; the reuse token's null
test. Three representations that make a misuse unwritable: the token
linear and present by type; `idr.is_unique` taking only `counted` values;
a quantity-1 allocation handle whose type names its lifetime (§6).

## 4. Improvements

**I1. Record the strike** (*coordinator*). Evidence: §4 skips item 7
(proposal:1063-1065); the strike is *recalled* only. Counterexample: a
lane reading the register finds oom-3 with no disposition and puts "who
measures stage 1, and how is it recorded" back on the owner's list, the
question the owner called "an egregious example of meta work". Root
cause: a ruling held only in a record outside the tree. Correction: §4
item 7 reads "**DP-07.** Struck by the owner as meta-work (2026-10-21):
P0 adds no record rule, measurement regime, run gate or runner; AGENTS.md's
claim rule stands (a number states its measure, build and input)."
Deletes: G:22's stage-1 record and frontier gate, G:24's gate framing,
§7's "invariant set unchanged" gate (M8). Discriminated: every register ID
resolves (Table 1).

**I2. A lifetime is erased; an allocation handle is a value**
(*owner*: §6). Evidence: proposal:657-658 against 820-822 and
AGENTS.md:337-339. Counterexample: `idr.func @build<ρ : lifetime>(%n :
i64) -> !idr.q<1, own, !idr.data<#List>, ρ>` builds its list in its
caller's lifetime; read by D48, `ρ` is gone at run time and the callee has
no allocator to bump; read by D39, `@lookup<ρ>`, which only returns a view
into its argument, takes a handle register on every call it never uses.
Root cause: one parameter asked to be a compile-time index and a run-time
capability. Correction: the lifetime variable stays quantity 0; a function
that allocates into a lifetime it did not bind takes a linear handle whose
type names that lifetime (`!idr.arena<ρ>`), made by `idr.lifetime`,
passed down, its end freeing the cells. Deletes: nothing yet built.
Discriminated: a verifier rule that an allocation into `ρ` needs a handle
of type `!idr.arena<ρ>` in scope, and a test that a view-only function's
lowered signature has no extra parameter.

**I3. Compiled code takes no stack probes** (*coordinator*: D32, C5 and
D10 settle it). Evidence: G:80 against D32 ("No frame is larger than the
guard, checked when built") and C5 ("The guard: one page, or the largest
frame rounded up if larger"). Counterexample: on arm64 Linux with 16 KiB
pages, a function with a 40 KiB frame and inline probing touches each page
of its frame on every call (about three probes, *conjecture* on LLVM's
exact sequence), though the build already proved the guard covers 48 KiB. Root cause: a fact known when the program is built, paid on
every call. Correction: no probe attribute on compiled functions; the
runtime's units and the tools keep `-fstack-clash-protection` (GMP's
`alloca`); the guard sits below the signal stack. Deletes: the planned
probe-size plumbing from the target's entry into the lowering, §5.5's line
(M5). Discriminated: the build-time check that every frame fits the guard,
and a test whose function has a frame larger than a page and smaller than
the guard runs with no probe and overflows into the guard, ending as D37's
internal error.

**I4. The call graph as a carried upstream patch** (*coordinator*:
AGENTS.md's order and D25 settle it; L14 designs it). Evidence: G:52's
reason is "`mlir::CallGraph` has no callers or dense ids"; G:30 records an
RFC to send later; AGENTS.md:486-487 ("not dropped for ours with the middle
step skipped") and D25 ("ESPECIALLY if it's meant to be upstreamed"); the
history's record of sending is nothing in about 25 patches (20 H4).
Counterexample: P0 lands `ProgramGraph` in `foreign/idr`, and the RFC,
"to be sent separately", joins the 25 unsent; the next upstream pass we
adopt (the inliner) builds `mlir::CallGraph` beside it, two call graphs
with two SCC orders. Root cause: the upstream-first order applied at
adoption and skipped at writing. Correction: dense node ids, callers and
maintained SCCs written as a patch to `mlir::CallGraph`, carried under
`upstream/<id>/llvm-project.patch` with its plan and test; ours in the
solver layer only where the patch's plan states what upstream cannot hold
(D2). Deletes: the separate `ProgramGraph` type and the RFC as a record.
Discriminated: one call-graph analysis in the manager, read by our passes
and upstream's.

**I5. A name lands with its concept** (*coordinator*: D28). Evidence:
G:27's "renames land last, in their own step" against D28's "in the change
that brings the new names". Counterexample: the effect system lands with
`idr.io` and `idr.crash` (D28) while op mnemonics wait for a final rename
step; in between, every generated fixture prints new resource names beside
old mnemonics, and a reject's rule phrase changes twice. Correction: each
name lands in the change that makes or remakes its concept; a rule's
phrase changes in the step that changes the rule. Deletes: the final
rename step. Discriminated: no step prints a name the specification no
longer declares (the generator's committed output, D49).

**I6. Fixtures: what is not behaviour or a guarantee is deleted**
(*coordinator*: the owner's standing test rule). Evidence: G:28's "the
rest is renamed once by a script"; the rule (*recalled*, 2026-10-15).
Counterexample: a canonicalization fixture matching `CHECK: arith.constant
3 : i64` survives a scripted rename and keeps asserting one op sequence;
the next dialect change breaks it for no behaviour change. Correction:
behaviour becomes a program test, a pass's guarantee an idr-expect
property over one, everything else is deleted. Deletes: the rename script
and every fixture it would have kept. Discriminated: no surviving test
names an `idr` op it does not assert a contract about.

**I7. Layout is the family's** (*coordinator*: D48). Evidence: G:40's
frontend-emitted boxes against D48 ("Inline or in a cell is layout, a
function of the type and its lifetime computed once"). Counterexample: for
`#Vect[3]` the frontend, deciding boxes from the declaration, emits a cell
for the recursive field where D48's layout makes three inline words with
no tag, cell or count. Root cause: a layout decision made before the index
that fixes it is known. Correction: the frontend emits the family whole
and states only Idris's facts (Nat-likes, pointer words, crash
alternatives); one layout function of the type and its lifetime decides
inline or in a cell, a one-field collapse included. Deletes:
`Layout/Fit.cpp`, the frontend's box emission, `DataTableAttr::verify`'s
cycle check (D48 deletes the table). Discriminated: a test that a value at
a known index of a recursive family lowers with no allocation.

**I8. The reuse token is linear and present by type; `is_unique` reads
only counted values** (*coordinator*: D10, D19, D39, D40; L07 and L08
design it). Evidence: "the memory of a cell whose fields idr.take moved
out, or null" (`IdrOwnershipOps.td:33-35`, *read*); `design/match-and-counting.md`
§7 already sends the no-token path to a specialized copy. Today the token
is an owned, counted value and not linear by its type
(`foreign/idr/lib/IR/ValueFacts.cpp:198`, `isLinearByType` false, *read*),
so only the owned rule's whole-function walk keeps it used once, and D39
deletes that walk. Counterexample: `%t = idr.take %x` on a shared cell
yields a null token; `idr.cell.recycle %t` must test it at run time, and
once the walk goes, nothing local refuses a path that both frees and
recycles `%t`. Root cause: presence of a token held as a value's null, and
its single use held by a walk instead of its type.
Correction: `!idr.token` linear by its type (exactly one recycle or free);
the take's two outcomes as two regions or join targets, one with a token
and one without; `idr.is_unique`'s operand constrained to the `counted`
lifetime. Deletes: the token's null, the null test, every re-test of
sharing on a token. Discriminated: the generated verifier refuses a second
use of a token and an `is_unique` on a `frame` or lexical value.

**I9. `transpose` is `linalg.transpose`** (*coordinator*: D42 and
AGENTS.md:360). Evidence: G:45 writes a tabulate whose indexing map holds
the permutation. Counterexample: `transpose m` as a tabulate of a permuted
read reaches linalg as a `linalg.generic`, and linalg's specialization
recognizes the transpose again, re-deriving what the frontend wrote (D10).
Correction: the specification declares `transpose` as upstream's
`linalg.transpose` with its permutation and destination. Deletes:
`TransposeOp`, its arms in `Forms`, `Linalg`, `Nests`, `TransposeColumns`.
Discriminated: a test that the lowered module of a transposing program
holds no specialization step for it.

**I10. Restate the stale text** (*coordinator*). Evidence: M2 to M7, M9,
M10, M12 to M14. Counterexample: an implementer reading §5.1 declares the
atoms `runtime`, `memo` and `diverge`, which D29 deleted with no alias, and
reading §5.3 orders lifetimes `static < heap < frame`, which D40 renamed and
extended. Correction: each line rewritten to its ruling (the appendix uses
the new names throughout). Deletes: the stale lines. Discriminated: no
deleted name of D28, D29 or D40 appears in the proposal or AGENTS.md
(*measured* by `grep`, to take when folding).

**I11. `remove-dead-values` on its measurement** (*coordinator*:
AGENTS.md). Evidence: G:54 against AGENTS.md:73-74 and §7 S3.
Counterexample: dead values inside a match's case regions that the
optimizer's interprocedural demand bit never sees stay in the program,
because the per-function pass was never measured. Correction: patches 06,
28 and 63 retired now; the per-function pass returns only if S3's trial
shows it removes what the demand bit leaves, its patches carried again in
that change. Deletes: the patches now. Discriminated: S3's measurement on
the scale fixtures.

**I12. The destination over families** (*coordinator*: D34 and D48; L04
and L10). Evidence: `Idr_DestType`'s one parameter is a `BoxType`
(IdrTypes.td:347-351, *read*). Counterexample: `map f (x :: xs)` needs a
destination at the tail field of `#List`'s cons cell; with `!idr.box` gone,
`!idr.dest<!idr.box<...>>` cannot be written. Correction: a destination is
typed by its family application, constructor position and field position,
still linear by type. Deletes: `BoxType` as the destination's parameter.
Discriminated: a TRMC program over a family with two recursive fields
writes each destination exactly once.

## 5. Work units

This lane writes no code; its corrections run inside other lanes' units.
Drafted pointers for the implementation packet:

| unit | owning lane | write set (real paths, before D16's cutover moves them into `compiler/spec/`) | outcome | must not | acceptance |
| --- | --- | --- | --- | --- | --- |
| token and uniqueness | L07, L08 | `foreign/idr/include/idr/IR/IdrOwnershipOps.td`, `foreign/idr/lib/IR/OpsOwnership.cpp`, `foreign/idr/lib/Transforms/` counting passes | I8 | keep a null token or a run-time re-test | a program whose take is shared on one path recycles on the other and frees nothing twice (exit status and output) |
| no probes in compiled code | L10, L11 | `foreign/idr/lib/Conversion/`, `runtime/Runner.cpp` | I3 | add a probe attribute to compiled functions | a program with a frame between a page and the guard runs; an overflow ends as the internal error |
| the call graph patch | L14 | `upstream/<id>/llvm-project.patch`, `foreign/idr/lib/Analysis/` | I4 | write a second graph type beside upstream's | one call-graph analysis serves every reader; the build carries the patch on all four targets |
| layout from the family | L04, L16 | `compiler/src/IdrisMLIR/Frontend/Translate/`, `foreign/idr/lib/IR/Layout/` | I7 | emit boxes from the frontend | a known-index value of a recursive family lowers with no allocation |
| destinations over families | L04, L10 | `foreign/idr/include/idr/IR/IdrTypes.td`, `foreign/idr/lib/Transforms/Tail/` | I12 | keep `BoxType` in the destination | TRMC programs keep their outputs |
| `linalg.transpose` | L12 | `foreign/idr/include/idr/IR/IdrArrayOps.td`, `compiler/src/IdrisMLIR/Frontend/Emit/Tensors.idr` | I9 | recover a transpose by specialization | transposing programs keep their outputs |

## 6. Owner questions

**OQ1. Is a lifetime parameter a value at run time?** D39 records "A scope
parameter is a handle at run time, so it is part of the function's type"
(proposal:657-658); D48 records lifetime variables as quantity-0
parameters "passed at calls at compile time only" (proposal:820-822), and
AGENTS.md:337-339 states D48's reading. They part for a callee that builds
its result in its caller's lifetime, which needs that lifetime's allocator
at run time.
- *(a) Two things* (recommended). The lifetime variable stays quantity 0
  (D48). A function that allocates into a lifetime it did not bind takes a
  separate linear handle whose type names the lifetime (`!idr.arena<ρ>`),
  made by `idr.lifetime` and passed down. Buys: a view's lifetime costs
  nothing at run time (D10); a handle exists only where allocation does; a
  handle of the wrong lifetime is a type error. Costs: one more type; one
  register on each allocating call. Who pays: L05's design and the
  function type.
- *(b) Every lifetime parameter a run-time handle* (D39 as written).
  Costs: a register on every call that passes a lifetime, views included,
  a static fact paid at run time; it contradicts D48 and AGENTS.md.
- *(c) No allocation into a caller's lifetime*: only views cross calls.
  Costs: loses D39's "a callee can build its result in the caller's
  scope"; such results go to `counted`.

No other question here is the owner's: the rest of this file's
corrections follow from rulings, AGENTS.md or a design document, and the
strike's record (I1) is the coordinator's text.

## Appendix: proposed text for §3

For the coordinator to fold after C8. Numbers are provisional. Each entry
is one of G's drafts that survives, corrected for D13 to D55.

*Process and scope*
- **C9** (DP-25: QL5, cxx-Q5). Equality saturation is outside P0's scope;
  nothing waits on it (no wall came from phase ordering, 04 §6). P0 does
  not wait for static reflection and takes it when a weekly fast-forward
  (D25) brings a usable form to the pin, for D7's compile-time constants.
- **C10** (DP-26: Q-M4, Q-E4, defunc-Q1). No more ports: fresh code from
  Modular's, CIRCT's and IREE's shapes, to D7's line. The deduplicator
  port is retired by partition refinement over upstream's
  `OperationEquivalence`, its symbol hook a carried patch (D25), merging
  duplicates inside call-graph cycles, each class keeping its first in
  symbol order. Deletes heights, waves, the cycle exclusion, `Reading`,
  `BodyHash`, `BodyEqual`, per-op dictionaries, the port's PINS.md entry.
- **C11** (DP-27: DD-Q8, T-Q3). Every name is open (D28, D29, D40):
  mnemonics (the 46 unprefixed join families), `con`, `dup`, `drop`, the
  namespace, pass names, idr-expect's property names. A name lands in the
  change that makes or remakes its concept, never in a later rename step;
  a rule's phrase changes in the step that changes the rule.
- **C12** (DP-28: T-Q2). A fixture stating behaviour becomes a program
  test; one stating a pass's guarantee, an idr-expect property over a
  program test; every other fixture is deleted, none renamed by script:
  op sequences, SSA names, orders, the 260 prose `expected-error`s,
  reference IR copied from output, and fixtures of states the
  specification cannot construct.
- **C13** (DP-29: QL6). 5.7's items 1 to 15 and 17 are fetched, verified
  and recorded with licences in `sources/INDEX.md`; item 16 goes with C9.

*Effects, quantities and budgets*
- **C14** (DP-32: DD-Q1, Q-FB2). `!idr.lin<i64>` stays a type on words.
  The translation keeps Idris's proof; Emit reads quantities, never counts
  uses; a quantity-1 binder used twice reaching Emit is an internal error.
  Deletes `mostUses`, `heldAs`, `holdFor` (`Emit/Bodies.idr:48-138`,
  `Emit/Declarations.idr:45`).
- **C15** (DP-33: Q-llvm-2, Q-E3, oom-2, canon-Q2). No budget in an
  analysis a refusal rests on: the frontend's profile, growth check and
  reachability walk (its derivation built at quantity 0, D46); the label
  solve and defunctionalization; idr-knots; the exclusivity analysis that
  decides D24's rule. The fork's elaborator searches end by construction
  (D45, D53 to D55). Every other analysis may stop at a budget in program
  units, keeping the pessimistic answer, never an error;
  canonicalization's `maxNumRewrites` is k times the function's op count,
  k a constant of the specification, the tests keeping
  `test-convergence=true`. The compiler running out of memory ends
  through one handler with a named line, never a refusal. Deletes
  `kNoLimit` (`Pipeline.cpp:28-32`, `Optimize.cpp:64-66`) and LLVM's
  default abort.
- **C16** (DP-34: QL4, Q-llvm-6). Output is byte-identical at any thread
  count, tested whole as today and per solver (frozen answers at one
  thread and many, in the unit boxes). Deletes OPT-48's lock-ordered
  request chain.
- **C17** (DP-35: ids-Q6). Each program is compiled by the shipped
  frontend and by a test-only build whose registry omits the `Faster`
  rows (generated from the specification, C6); exit, output and refusals
  are compared. Hooks are indexed by kind (`Contract | Faster |
  Stricter`), so a `Faster` hook on a bodiless definition cannot be
  written. Deletes `Faster` on bodiless primitives.

*The dialect's representation*
- **C18** (DP-36: Q-O3, Q-E2). Every fact a later pass reads is written
  by the pass that proves it into a type or a verified property; no side
  table crosses passes. Rows live on `idr.func` and `idr.call` (D20,
  D22); grades, lifetimes and families in types (D39, D40, D48); a cached
  analysis holds only what one pass reads. Deletes the optimizer's facts
  that die with its run (gives-back, binding times, inline facts).
- **C19** (DP-37: QL2, ops-Q1). Each case region binds its scrutinee
  refined to its constructor: the type names the family application and
  the constructor by its position in the family (its label printed, never
  looked up, D48), binds the constructor's index variables at quantity 0
  under its equation, and its fields at their quantities; an erased field
  does not exist. `field`, `take` and `unpack` take that type and lose
  `tag`, so a read of the wrong constructor cannot be written. Deletes the
  `tag` attributes, the enclosing-match walks, `readField`'s scan,
  counting's undo of the default's rebinding.
- **C20** (DP-38: DD-Q7, tail-Q1, count-Q4, Q-AN1). `idr.func` and
  `idr.call` stay. A function carries its row (D20, D22), its signature
  (grades, lifetimes and index parameters in its type) and "gives back
  argument i" as a verified property. A call carries its callee's row
  (D20), its tail kind (D30: decided once, verified, lowered onto
  `llvm.call`'s tail kind), its tail-modulo-context destination (D34) and
  its quantity-0 index and lifetime arguments (D48); its types are its
  callee's conventions after substitution, so no convention attribute
  exists. "Gives back" is copied onto a call only where a nested pass must
  read it, as the row is. Deletes `IR/Tail.cpp`'s climb,
  `TailPosition.cpp`, the whole-module Returned solve.
- **C21** (DP-39: types-Q4, types-Q3). One closed `#idr.grade` attribute
  with constexpr methods and no interface: a quantity (one, many), a
  permission (`Plain` two cases: undecided, legal only before counting,
  and holds no reference), and a lifetime (D39, D40): `static`,
  `counted`, `frame` and the lifetime variables in scope, which form a
  chain by lexical nesting, so `fitsIn` is outlives and join the
  innermost. Printed `!idr.q<1, own, T, ρ>`, `counted` unwritten. The
  frontend imports the grade's parts from the specification (D50).
  Deletes the grade's free functions, the stage reads
  (`Grades.cpp:80-91`, `Program.cpp:222-228`), the `heap` constant's name.
- **C22** (DP-40: ft-Q1, types-Q2). The frontend states Idris's
  representation facts: Nat-like types as numbers, pointer-like word
  types as `u64`, the enumerated crash alternatives. Layout is not the
  frontend's: each family is carried whole (D48), and inline or in a
  cell, a one-field collapse included, is one function of the type and
  its lifetime, computed once; byte layout is the lowering's, from the
  module's data layout. Deletes `Layout/Fit.cpp` and its whole-program
  remap, the second `TypeGraph` walks, the frontend's box emission.
- **C23** (DP-41: DD-Q4). arith's school: signless types, the sign on the
  op where the computation differs; `shls` and `shlu` become one `shl`.
  Deletes the shift pair and `signed : IntTy -> Bool`.
- **C24** (DP-42: DD-Q5, ids-Q5). One op per operation, its variant an
  enum of the specification (`io.clock <kind>`, the file times); the
  generated ABI row is keyed by op and case, and the runtime's entries are
  explicit instantiations of one template over the case, so nothing picks
  the case at run time. Crash sites follow D38; base primitives, C6.
  Deletes the per-clock and per-time ops, the generator's refusal of an
  enum, hand arities.
- **C25** (DP-43: canon-Q3). Canonical output composes a pure `show_*`
  and one `put_str`; the lowering emits the allocation-free entry for
  `put_str(show_* x)`. Deletes the four `put_*` ops and canon's fusion
  (`Output.cpp:107-133`).
- **C26** (DP-44: arr-Q2). Entering a linear array is one of two members
  of D43's one cast: a link (in place, always) or a head (may copy),
  chosen by the translation where it threads a quantity-1 `LArray`;
  bufferization confirms the op and never re-proves it. Deletes `isLink`'s
  per-query state (`Linear.cpp:32-50`).
- **C27** (DP-45: arr-Q4). `idr.transpose` goes: `transpose` means
  upstream's `linalg.transpose` (D42), its permutation written once by the
  frontend; a transposing read inside a tabulate stays that tabulate's
  indexing map. Nothing recovers a permutation. Deletes `TransposeOp` and
  its arms in `Forms`, `Linalg`, `Nests`, `TransposeColumns`.
- **C28** (DP-47: ops-Q4, drv-Q2). Each op family declares in the
  specification the stages it is legal at, checked by one generated
  trait; the pipeline is one list in the specification (order, reasons,
  options, each pass's kind: decide, apply or restructure), its stage
  chain proved there, printed into `Passes.td` and the pipeline's body
  and imported by the frontend (D16, D50); nesting follows from the
  kinds. Deletes the verifier's stage rule, the hand order and its copy,
  the harness's awk, the dead `remove-dead-values` registration.

*Defunctionalization*
- **C29** (DP-48: defunc-Q3). One walk writes the label solve's decision
  into the types: each closure sum is a family the pass declares (D48),
  values retyped to its applications, legality checked by the stage
  verifier; no per-function conversion. Deletes `Plan`,
  `SlotTypeConverter`, `RetypePattern`, the rollback,
  `PatternsCalls.cpp`.
- **C30** (DP-49: defunc-Q4). A use moving into two sinks unifies them;
  the plan holds one key per use.
- **C31** (DP-50: defunc-Q2). No idr-effects pass: the one derivation of
  rows (D22; callees first over the call graph, its transfer generated
  from the specification) first runs in defunctionalization's decision
  over calls and label runs and decides `by_name`; idr-optimize keeps it
  current. Deletes `Analysis/Effects.cpp` and the body rule
  (`Func.cpp:189-202`).

*The solver layer*
- **C32** (DP-51: QA1, QA2, Q-AN3). Upstream's dataflow framework's
  storage is patched first (P1, carried), and Ranges, Borrows and
  Returned are measured on it at the scale fixtures and at stage 1; it
  then keeps the per-value solves inside one function (idr-constants,
  narrowing's Copy, Ranges per function with callers-first argument
  summaries). Returned goes with C20's "gives back". Borrows leaves the
  framework for the marking template only if that measurement shows its
  state is the problem's, after C1 and D26 have shrunk it (one call
  passing a quantity-1 binder of a type that does not bound what it
  reaches makes the parameter owned). No P2.
- **C33** (DP-52, with DP-30: Q-E1, Q-M1, Q-AN2, Q-llvm-7, Q-E5). One
  maintained call graph, written first as a carried patch to
  `mlir::CallGraph` (D25; AGENTS.md's order), its upstream plan the RFC:
  dense node ids minted by the graph, callers and callees as compressed
  rows, SCCs bottom-up, built through `CallOpInterface`, kept current by
  the passes that edit calls and preserved by the rest; ours in the solver
  layer only where the patch's plan states what upstream cannot hold (D2).
  Three solve shapes on one static schedule; the optimizer its one dynamic
  client, editing through the graph's API; the giant SCC serial first.
  The dataflow-scope RFC is not wanted. Deletes `CallCycles`, `Recursion`,
  caller-only `SymbolUserMap`s, nine name-keyed maps, `Scc.cpp`'s copies,
  the optimizer's second walk.
- **C34** (DP-53: QA4, Q-O2, QL1, Q-llvm-3, QL3). Shared
  concept-constrained types (`Id<Tag>`, `IndexVector` with raw index
  deleted, `Graph` modelled by `Csr<Tag>` with `GraphTraits`, `Lattice`,
  `Summary`, direction a type) and three generic algorithms
  (`mark<Dir, Gate>`, `solve<CalleesFirst | CallersFirst>`,
  extract-solve-link), each solver one explicit instantiation in its own
  unit over a read-only view. A function's numbering is one cached
  analysis, invalidated by change, never maintained across rewrites. The
  label solve keeps its rules as data; the frontend's translation is
  relational (D44). Deletes six numberings, pointer-keyed solver maps,
  dead worklists, `bool backward`, the solvers' callbacks.
- **C35** (DP-54: QA3, Q-opt-4, hist-Q3). Patches 06, 28 and 63 are
  retired now (nothing reaches them; AGENTS.md). Dead parameters are a
  demand bit in the optimizer's summary, the callee narrowed before its
  callers run; dead results, one callers-first pass; a function a closure
  label names has an unknown caller; only many-quantity parameters can be
  dead. `remove-dead-values` returns per function only if §7 S3's
  measured trial shows it removes what these leave, its patches carried
  again in that change.

*Counting*
- **C36** (DP-55: rc-Q2, own-Q3). One marking proves what it can, and
  grade copies (one per function, keyed "every followed parameter
  exclusive") make more static, made inside counting by the optimizer's
  clone-and-key template; join regions take the same keys. The run-time
  test stays only where exclusivity is unknown until run time, and its
  code says so. No promise rests on a copy (D24). Deletes counting's own
  cloning code.
- **C37** (DP-56: rc-Q5). Drops go at last use, with the problem's
  exceptions: a loop holding an outside value, a crash region (D21), a
  tail call on a cycle (its parameter owned, D30), and a borrowed
  argument only where C1 and D26 allow one. No lexical lifetimes for
  drops: Idris has no destructors. A quantity-1 value's last use is its
  one use, or the entry of a path that does not use it.
- **C38** (DP-57: count-Q3). Tail recursion modulo context is read off
  the program before counting (D34) and written on the call; counting
  runs first and honours it; idr-trmc executes it on counting's
  `cell.init`, keeping the recycled cell. `!idr.dest` stays linear by its
  type, typed by its family application, constructor position and field
  position (D48). Deletes Borrows' prediction of idr-trmc.
- **C39** (DP-58: conv-Q3). The take's expansion is counting's last step
  at the `idr` level: `idr.is_unique` takes only a `counted` value and
  folds to true on `!idr.excl`; a reuse token is linear by its type and
  never null, the take's two outcomes being two targets (D19); moves and
  counts are IR; the lowering lowers primitive ops only. Deletes the
  lowering's uniqueness branches, the exclusive drop's count read, the
  `Fields` table, the runtime's stack-bit test, the token's null.
- **C40** (DP-59: rc-Q4, rt-Q1). No counted cell is ever shared between
  threads (no atomic count, no mark-shared pass); shards pass cells by
  detach (C2). The count takes Koka's signed encoding without atomics (0
  unique, negative sticky), "count 0 is persistent" moving to the sticky
  constant; with `static` in the type (D40), the sticky test serves only
  run-time facts. Deletes `count == 1 && !stack`.

*Verification and the pipeline*
- **C41** (DP-60: ods-Q6, Q-M2, Q-O5, types-Q1, drv-Q3, T-Q4, T-Q5). Full
  verification after every pass in every build, cheapened by nesting as a
  rule: decide passes compute a fact and change nothing, apply passes
  rewrite functions in parallel, only restructure passes change the
  program's shape. The owned rule's whole-function walk goes (D39); its
  remainder is local, in each op's verifier. A pass that changed nothing
  preserves all analyses (patches U-a, U-b, carried). Contracts are
  per-function test records; the verifier is read from `--mlir-timing`.
  Deletes the program verifier's serial walks, the contracts' module
  clone, hand nests.
- **C42** (DP-61: conv-Q2). Two program passes (declare every runtime
  function, make every static datum, once), then the lowering as a
  function pass. Deletes the worker-and-merge scheduler.
- **C43** (DP-62: drv-Q4). Every thread of the compiler runs on one stack
  size, D33's measured bound with a margin, set through a carried patch
  giving `StdThreadPool` a stack size and sized in one platform place.
  Deletes OS-default worker stacks and `PINS.md:595`'s stale 2^40.
- **C44** (DP-63: drv-Q5). The prepared runtime's bitcode lives beside
  the object on every target. Deletes `BitcodeHome`, its switch, both
  CMake branches, the section path.

*Specialization*
- **C45** (DP-64: Q-O4, Q-M5, Q-opt-1, ft-Q3, Q-opt-2). The bottom-up
  schedule stays, what a call reaches one sum decided at the grant, in
  MLton's order: specialize to completion, inline once on the final graph
  with true call counts, normalize. Keys include known index terms and
  lifetimes (D48), so a call at a known index gets the copy whose shape
  the index fixes. Polyvariance, if the closure sums shrink with it, is a
  C++ pass between deduplication and defunctionalization under a budget,
  never the frontend's. Deletes OPT-84's five rules, `no_inline`, the
  per-round interleaving.
- **C46** (DP-65: Q-opt-3). Keys are the run's own interned data (a
  closed sum in an arena), freed with the pass, taking no context lock; a
  debug print on demand. Deletes `Idr_SpecKeyAttr`, `Idr_KeyRaiseAttr`,
  the global node-table mutex.

*Rewrites and tools*
- **C47** (DP-66: ods-Q4). DRR for rooted local patterns, each declared
  in the specification and printed into the generated `.td` (D16); PDLL
  refused; region-reading patterns stay C++. Deletes five C++ pattern
  classes and `StrBuilderOpInterface`'s partial methods.
- **C48** (DP-67: canon-Q5, canon-Q4). Upstream's canonicalizer on the
  greedy driver, configured once, `filter-dialects` naming `idr`, `arith`,
  `ub` and each point's needs, C15's budget, one match view per visit,
  and a carried patch so a canonicalize that changed nothing preserves
  analyses. Deletes the second configuration, the per-visit rescans and
  string roots.
- **C49** (DP-68: canon-Q1). A canonicalization runs before
  defunctionalization, where the force, suspension and closure forms, and
  C3's merging of equal unrestricted values, shrink the label solve's
  sets.
- **C50** (DP-69: Q-llvm-5, ids-Q3). Every `idr` type and attribute, D48's
  family attributes included, is native in bytecode, its encoding printed
  from the specification for the C++ and for the Idris writer (D16); no
  `idr` text crosses the handoff; the one C++ TableGen backend of ours is
  D51's. Deletes the copied format parser, the Idris printers, the hand
  record switch, raw record reads and string compares, decimal doubles.
- **C51** (DP-72: ids-Q4). Every binder specgen prints in an Idris builder
  is primed, so no keyword list is copied; operands are a `Vect n Value`
  (D50).

*C++*
- **C52** (DP-73: Q-llvm-4, cxx-Q2). One exhaustive fold, `match`, over
  every closed sum of ours, coverage checked at compile time;
  `get_if`, `holds_alternative` chains and `std::visit` banned;
  `PointerUnion` for pointer-sized handles, read by the same fold.
- **C53** (DP-74: cxx-Q3). One precompiled header on `IdrIR`, reused by
  every target of ours, with compile-time-cpp §7.2's contents, after the
  `-ftime-trace` baseline; `-fno-pch-timestamp` and ccache sloppiness; no
  C++ modules in P0.
- **C54** (DP-75: cxx-Q4). Extensive libc++ hardening in every
  configuration; a failure is a bug of the runtime or the compiler, so a
  handler routes it to D37's internal-error ending; release's cost is
  measured and reported. Deletes the bare trap.

*Frontend and fork*
- **C55** (DP-76: Q-FB1, tail-Q4). The fork stops building the run-time
  case tree; the TTC keeps 0003's `scTy` and clause index (D44), read
  where `Forced.idr` guesses; once it keeps a block's parent, a case block
  is emitted in place as a region of its parent (D19). Deletes
  `compileRunTime`'s tree, `Forced.idr`, `Cases`' guesses.
- **C56** (DP-77: Q-fc-2). If stage 1 shows the node split's products
  large, the growth check's flow splits by node, acceptance unchanged, and
  the derivation D46 builds covers the split form.
- **C57** (DP-78: ft-Q4). The module is the one output; the Core dump
  goes, its two readers read the module.
- **C58** (DP-79: ft-Q5). A refusal is a value of the translation's own
  typed refusal (its rule one of the specification's categories, D50; its
  site a location), never the fork's `Error` or a side channel. Deletes
  `TS.inFlight` and the dedupe by printed text.

*The runtime*
- **C59** (DP-80: oom-4). Compiled code takes no stack probes: its frames
  are static and the guard is at least the largest, checked when the
  program is built (D32, C5). The runtime's units and the tools take
  `-fstack-clash-protection` on every target; the guard sits below the
  signal stack. Deletes `Runner.cpp:35-37`'s unchecked claim.
- **C60** (DP-81: rt-Q2, rt-Q4). Shipped programs neither count cells nor
  read `IDRIS_RT_LIVE`; the count lives in the checked runtime, which the
  harness links for leak runs of the same module; the IO test writes past
  the shipped buffer. Deletes the `thread_local` count, `IDRIS_RT_LIVE`,
  `IDRIS_RT_IO_BUFFER_SIZE`.
- **C61** (DP-82: rt-Q5). A seed-range hook as
  `upstream/<bug>/snmalloc.patch`, carried, with its report, test and
  plan (a submission: snmalloc wants a CLA); our config copy goes.
- **C62** (DP-83: conv-Q5). One prefix on every program symbol, so none
  is a runtime symbol or `main`. Deletes three collision checks.
- **C63** (DP-84: oom-7, oom-8, oom-9). Returning stack memory is D31's
  (frame stacks give chunks back) and D32's (the native stack is small); a
  pressure signal and shards' limits wait until a program or a shard
  needs them (C2, D36).

*Settled by rulings, not restated:* DP-22 and DP-24 (AGENTS.md; their
gates struck as meta-work), DP-23 (D16, D50), DP-30 (D25, inside C33),
DP-31 (C3), DP-46 (D31), DP-70 (D16, D50), DP-71 (D49).

## Sources read

- In full: `audits/p0/verify/dispatch/L06-dispositions.md`; the
  representation-first skill; `AGENTS.md` (the working tree, 643 lines);
  `proposals/0000-mlir-native.md` (the working tree, through D55);
  `audits/p0/wave1/questions.md`; `audits/p0/wave1/00-brief.md`;
  `audits/p0/synthesis/F-decisions.md`; `audits/p0/synthesis/G-coordinator-decisions.md`;
  `audits/p0/20-history.md`.
- In part: synthesis E §5; `design/one-source.md` §6 to §12;
  `design/effect-vocabulary.md` §8; `design/match-and-counting.md` §5.4,
  §6, §7, §12; `design/compile-time-cpp.md` §2.1, §3.5, §7.2;
  `design/effects.md` §6.5 to §6.8; `design/typed-effects.md` §4, §5;
  `design/elaborator-counts.md` §0, §1.7, §7; `design/AGENTS.changelog.md`;
  `audits/p0/verify/README.md`, `validate.sh`, `ownership.json`; the
  coordinator's records `no-invented-process`, `delete-brittle-tests`,
  `bjorn-engineering-preferences` (*recalled*, outside the tree).
- Code, at the lines cited: `third_party/Idris2` (`typesfuns.rst`,
  `System.idr`, `CompileExpr.idr`, `Inline.idr`); `runtime/Io/Ending.cpp`;
  `runtime/Alloc/Cells.cpp`; `third_party/snmalloc` (`standard_range.h`,
  `ds/pagemap.h`); `foreign/idr/include/idr/IR/{IdrTypes.td,IdrBase.td,IdrOwnershipOps.td}`;
  `foreign/idr/include/idr/Analysis/Ownership.h`;
  `foreign/idr/lib/IR/OpsOwnership.cpp`;
  `foreign/idr/lib/Transforms/{Expect/Allocation.cpp,Demand/Demand.cpp}`;
  `foreign/idr/lib/Conversion/TailCallPlan.cpp`;
  `foreign/idr/lib/Analysis/Ownership/{Reuses.cpp,Borrows.cpp}`;
  `compiler/src/IdrisMLIR/Frontend/Translate/Types.idr`;
  `compiler/idris/src/TTImp/Elab/{App.idr,Ambiguity.idr}`.
- Checks run: `grep`, `sed`, `wc`, `awk` over the files above, and the
  register's 158 IDs compared against F's placement (*measured*: equal
  sets). No build, typecheck or test.

HEAD at start: `e96bb991`. HEAD at finish: `e96bb991`.
