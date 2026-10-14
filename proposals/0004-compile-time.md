# 0004: whole-program facts, a fixed optimizer, parallel code generation

## 0. Status

**Proposed 2026-10-14; design only.** Nothing here is coded until the
owner approves it. It is then executed as one hard cutover, with no
compatibility owed to any mechanism it replaces, on the owner's machine,
where `make build` and the suites run at each lane's integration
(§10). This file supersedes every earlier text of 0004: the compile-time
record those drafts held is kept in §3, condensed only where nothing is
lost, and git history holds the drafts themselves.

The opt-in `scc-pipeline` that landed at 552d682a is deleted by this
cutover (§3.3, §6). Nothing builds on it in the meantime.

**Sources.** Five research reports of 2026-10-14, kept verbatim in
`sources/notes/compile-pipeline/`: `mlton.md` (MLton's pipeline, closure
conversion, inliner and chunks, read from `sources/code/mlton`, 43 files at
`aa2fd1ad`), `codegen-partitioning.md` (LLVM, GCC WHOPR, ThinLTO, rustc,
Swift, Zig, GHC, Lean), `mojo.md` (the Mojo compiler, snapshot in
`sources/code/modular` at `9211931`), `upstream-mlir-llvm.md` (the pinned
MLIR and LLVM machinery against our C++) and `casework-audit.md` (our
casework, why acceptance depends on optimization, what blocks sharding).
Their section numbers are cited as, for example, *mlton §2*. The stage-0
measurement is `bench/profiles/2026-10-14-f0-stage0.md` (*F0*). `M/` and
`L/` are the pinned MLIR and LLVM trees under `.toolchain/build/llvm-project/`.
Line numbers in our tree are those the reports read on 2026-10-14.

**Claims** are marked *read* (the path), *measured* (the record),
*recalled*, *conjecture* or *decision*.

## 1. The philosophy

**The owner's rule, in his words:** full-program optimization for
invariants, types, quantities, lowering and memory management; for code
generation, a far more parallelizable baseline. The research gives it a
precise shape.

**The whole program is the unit of meaning.** Every fact a guarantee rests
on quantifies over every caller or every value, so it is decided once, on
the whole program, and read frozen afterwards:
- the instance set and monomorphization (the frontend);
- each closure's label set and the sum it becomes (defunctionalization, §2);
- quantities and linearity, which live in types and are checked by the
  verifier after every pass;
- exclusivity and borrow grades (`idr-rc`'s signatures);
- layouts (`idr-lower`'s type converter);
- effects, the tail-call cycle plan, escape summaries for the stack, and
  reachability.

**The whole program is not the unit of work.** Rewrites run per function or
per call-graph component; LLVM's optimizer and code generator run per
partition. After whole-program optimization, LLVM's code generation is
local to each function apart from minor passes (IPRA, the machine outliner,
global merging) (*read*, codegen-partitioning §1), and MLton shows that
partitioning after optimization is independent of the optimization itself
(mlton §4). Today the driver translates one module, runs one O3 and emits
one object, serially (`foreign/idr/lib/Driver/Run.cpp:164-201`,
`lib/Target/Optimize.cpp:44-59`, *read*). That is the part this design
splits (§5).

**Acceptance is a property of the program, never of the optimizer.** Today
a program compiles only if `idr-simplify` reaches its fixpoint before a
round counter runs out (*measured*, F0: "the fixpoint is load-bearing, not
ceremonial"). §2 removes that dependency by making defunctionalization
total by analysis alone, as MLton's closure conversion is. Inlining then
becomes pure optimization: a budget stops it and never rejects a program.

**Representation first, everywhere.** When a new case shows up, the data,
types and invariants change until the case is no longer special or no
longer expressible; a branch, a flag, a guard, an option or a fallback is
the wrong answer. In this design that means:
- facts live in types and inherent properties, never in discardable
  attributes that a pass can drop silently;
- change is a returned fact from the pass that made it, never a hash of the
  module taken to find out (a check that throws away what it learned);
- names are derived from content, never from counters, so creation order
  cannot reach output;
- one flow table, one canonicalization configuration, one effects analysis;
- no pass option selects behaviour; experiments compare binaries (§10).

**The shape of the work that results.** Decide the facts once, exactly.
Transform with a fixed sequence of bounded passes. Partition. Generate code
in parallel. Each step is a function of its input alone, so the output is
byte-identical at every thread count.

## 2. The question answered first: inlining as pure optimization

**The answer is yes.** Defunctionalization can be made total by analysis
alone, so that no optimization is needed for a closed, monomorphic program
to be accepted. This section shows what it needs today, every reason it can
fail today, the four representation changes that remove those reasons, the
argument that it then cannot fail, where it sits in the pipeline, what that
costs, and how each risk is checked.

### 2.1 What defunctionalize needs today

A closure-carrying slot is a *key*. A key becomes a sum only if its labels
are known, they fit its type, and, for a lazy key, they all return into one
key (`lib/Transforms/Defunctionalize/Decide.cpp:38-47`, *read*). It also
must never meet a key that did not convert: one such key marks every label
it may hold as a closure, and their parameters, results and applies,
transitively (`Decide.cpp:97-184`). The keys left unconverted are collected
by `unknownKeys` (`Decide.cpp:204-219`) and reported as
`unsupported (runtime closure)` or `unsupported (laziness)`
(`Defunctionalize/Pass.cpp:43-50, 96-101`, *read*; casework-audit §2).

### 2.2 Every source of the unknown label set, and what removes it

The label analysis has a top element, `LabelSet::top()`
(`include/idr/Analysis/Labels.h:55`, *read*), and a second, narrower list of
ops that the slots follow (`Defunctionalize/Moves.cpp:75-79`). Each row is a
place where a value becomes unknown today (casework-audit §2):

| Where a label set becomes unknown | Code | The representation change that makes it unexpressible |
| --- | --- | --- |
| An op with a closure result that Labels does not handle | `lib/Analysis/Labels.cpp:119-121` | One flow interface (below): an op that carries a closure or lazy value declares its edges, and the verifier refuses a closure- or lazy-typed operand on an op without it |
| Any op not in `isFollowed`: its operands flow into unknown, its results come from it | `Moves.cpp:75-79, 226-238` | The same interface; `isFollowed` is deleted |
| Every non-entry block argument of an `idr.func`, which is what the inliner makes of a multi-block callee (`handleTerminator` writes `cf.br`, `lib/IR/Func/Inliner.cpp:32-39`) | `Moves.cpp:240-245` | Branch edges come from upstream's `BranchOpInterface`, which the interface reads; Labels already follows `cf.br` through the dataflow framework, so the two agree |
| The yield of an evaluated `idr.delay` | `Moves.cpp:37-38`; Isolate's branch that steers around it, `lib/Transforms/Isolate/Isolate.cpp:80-86` | A forced-state anchor keyed by the lazy value's type (below) |
| Public or escaping functions | `Labels.cpp:165-166`; `lib/Analysis/LabelSites.cpp:116-122` | Closed world as a verified invariant (below) |
| External functions | `Labels.cpp:145-148`; `Defunctionalize/Keys.cpp:226-235` | Closed world |
| An apply whose callee is unknown: its results go to top and its arguments join every label of the type, so unknown spreads | `Labels.cpp:134-141` | Nothing: with no source of unknown, no callee is unknown (the argument of §2.4) |
| Region arguments of fold, generate and match that are not fields | `Labels.cpp:199-221` | The interface declares region-argument edges, through upstream's `RegionBranchOpInterface` for matches and per op for fold's accumulator and generate's element (the existing `ElementsAnchor`, `Labels.h:175`) |
| A lazy component whose labels return different types is refused | `Moves.cpp:185-198` | The forced-state anchor: every label of a lazy key returns into the one anchor of its value type |
| A label that does not fit its key: `fits` demands exact type equality | `Keys.cpp:84-95` | Labels are compared on the unrestricted function type, the grade being the slot's (*conjecture*, checked in §2.9) |

**The four changes** (casework-audit §2):

1. **Closed world as a verified invariant** (*decision*). No external
   `idr.func`, and no public function except the root, which takes a world.
   The module verifier checks it once, before defunctionalization. This
   deletes `escapes`, the external tops and `Decide.cpp:158-164`.
2. **One flow interface** (*decision*). An idr op interface, beside
   upstream's Call, Region and Branch interfaces, through which an op that
   carries a closure or lazy value declares how each such operand reaches
   its results, region arguments and anchors. Labels and Slots both read
   it; nothing else decides how a closure moves. The verifier refuses a
   closure- or lazy-typed operand on an op that lacks it. This deletes
   `isFollowed`, `Labels.cpp:119-121` and `Moves.cpp:240-245`, and it is the
   one representation of closure flow that today is held twice
   (`Labels.cpp:68-123` against `Moves.cpp:27-79, 209-247`, which disagree
   on `cf.br`).
3. **A forced-state anchor keyed by the lazy value's type** (*decision*),
   the way `ElementsAnchor` is keyed by element type (`Labels.h:170-180`).
   Evaluated delays write it, and every label of a lazy slot returns into
   it. This deletes `unifySuspensions` (`Moves.cpp:147-206`), Isolate's
   evaluated-delay branch and `Moves.cpp:37-38`.
4. **No unknown element in `LabelSet`** (*decision*). This deletes
   `labelsFor` (`LabelSites.cpp:92-114`), the sealing cascade
   (`Decide.cpp:97-184`) and both `unsupported` reasons; reaching one is an
   internal error.

### 2.3 What MLton does, for comparison

MLton's closure conversion has no top value at all (mlton §2): every
abstract value is built from its type (`code/mlton/mlton/closure-convert/
abstract-value.fun:273`), each constructor argument gets one value
(`closure-convert.fun:249-256`), an application adds a handler on the
callee's lambda set (`:311-326`), shared mutable cells are unified rather
than joined (`abstract-value.fun:316-329`), and every distinct lambda set
becomes its own datatype, one constructor per lambda carrying its free
variables (`closure-convert.fun:499-546`), with a coercion `case` wherever a
value flows between two sets (`:596-644`) and an `apply` that cases over the
set and calls each lambda's function (`:676-708`). It cannot fail. Its
minimal pipeline, `-ssa-passes minimal`, is only `polyEqual` and `polyHash`
(`code/mlton/mlton/ssa/simplify.fun:124-129`), so a correct program needs no
inlining, contification or flattening: closure conversion is exact from the
analysis alone (*read*, mlton §2). A large set compiles to a `case` with one
arm per lambda; there is no cap, no refusal and no boxed fallback.

### 2.4 The totality argument

After the four changes, defunctionalization accepts every module that
passes the verifier. The argument (*conjecture*, each step checked by §2.9's
tests):

1. **Closed.** By the verified invariant, every function is defined in the
   module and every caller of a non-root function is in the module.
2. **Every closure value has a label.** A value of a closure or lazy type is
   created only by an op that names a label (`idr.closure`, `idr.suspend`,
   a closure constant) or arrives through an edge some op declares. There
   is no other way to make one: no external function returns one, and no
   op without the interface may produce one.
3. **Flow is only along declared edges.** Every op that holds such a value
   implements the flow interface, so the analysis's transfer functions only
   copy or union label sets along declared edges. No transfer introduces a
   label that no op named, and none introduces an unknown, because the
   lattice has no unknown element.
4. **Each set is finite.** The labels are the module's functions, a finite
   set, and the lattice is the powerset of it ordered by inclusion, so the
   least fixpoint exists and is reached in finitely many steps.
5. **Every set becomes a sum.** Each key's set is a finite set of functions,
   possibly empty. A nonempty set is a sum with one constructor per label
   carrying its captures. An empty set means no value ever reaches the key;
   its applies are unreachable and lower to `ub.unreachable`.
6. **Values move between sets by coercion.** Where a value flows from a key
   with one set to a key with a larger one, the existing converter coerces
   it (`SlotTypeConverter::coerce`,
   `include/idr/Transforms/Defunctionalize.h:218`, *read*), as MLton's
   coercion `case` does.
7. **An apply is a dispatch.** An apply on a key becomes a case over the
   key's constructors, each arm a direct call. So every apply in the module
   has a translation, and none is refused.

Hence no closed, monomorphic module is refused by defunctionalization, and
whether a program compiles no longer depends on inlining, specialization,
SCCP, the force preparation or any budget (casework-audit §2).

### 2.5 What is still refused, and where

- **The frontend's megamorphic refusals**, as AGENTS.md defines them: an
  implementation chosen by a runtime value, a recursion that builds its
  type deeper at each call, `%foreign`. They are decided before any MLIR
  exists and name the site and the unbounded value. A closure set in a
  closed monomorphic module is never unbounded, so no refusal of that kind
  is left to the C++ side (casework-audit §2).
- **A broken invariant is an internal error**, never `unsupported`: a
  verifier failure after a pass, a lattice that reached a state the
  argument rules out, a termination argument that does not hold.
- **A spent optimization budget stops optimizing.** Inline caps, the
  unroll limit (`kUnrollLimit`, `Specialize/Keys.cpp:38`) and the clones per
  owner (`kClonesPerOwner = 1024`, `Clones.cpp:30-33`) bound work and code
  size; reaching one leaves the program less optimized and never rejects it.
  `unsupported (compile-time budget)` is deleted (§6).

### 2.6 The directive.lam4 refusal

F0 records that after 16 rounds defunctionalize still refused a closure in
`Idris.Parser.directive.lam4` (*measured*). The refusal names the op kind
(`Pass.cpp:48-49`) but only the function was kept, so which gap it hit is
not known (casework-audit §2). Lane L0 (§10) reruns the old binary's
defunctionalize on the saved round-16 module and records the op and the key.
That record is a regression fixture for the new analysis, not a design
input: under §2.4 every gap of §2.2 is closed, and the fixture shows the
closure accepted. *Conjecture:* the likeliest gaps are a non-entry block
argument left by multi-block inlining, or an apply on a value that crossed a
match region argument, since those are the two that grow with inlining.

### 2.7 Where defunctionalization sits: right after emission

*Decision:* in MLton's order, defunctionalization runs before the optimizer,
right after the closed-world check and deduplication (§4). MLton
closure-converts SXML into SSA and only then simplifies (`main/compile.fun:
489-507`, mlton §1); its earlier `polyvariance` pass is optional precision
(`xml/polyvariance.fun:91-106`), duplicating small higher-order functions
before 0CFA so that sets are smaller. Every consequence:

- **The apply canonicalization becomes case of known constructor.** Today
  `ApplyOp::canonicalize` turns an apply of a known closure into a call
  (`lib/IR/OpsClosures.cpp:316-346`). After defunctionalization the closure
  is a constructor and the apply a case over it, so the fold that matches a
  case on a known constructor, which already exists (455d3c0f), does the
  same work for every first-order program, with no closure-specific rule.
- **Closure references become direct calls.** Each arm of a dispatch is a
  direct `idr.call`, so upstream's `CallGraph` sees every edge. The custom
  reference graph exists because an `idr.apply` is invisible to the call
  graph and a closure naming `@f` contributes no edge (upstream-mlir-llvm
  §2); after this order it is no longer needed for the optimizer.
- **Passes lose their closure cases:** LoopBreakers, Effects, SCCP's
  closure constants (`Round.cpp:64-66`), Raise
  (`lib/Transforms/Specialize/Raise.cpp`), ForceAtCapture and the two force
  rewrites of `Inline/Prepare.cpp:68-211` all have closure-specific code that
  goes (casework-audit §2).
- **Specialization becomes specialization on known constructors.** What
  substitutes a static closure into a clone today (`Specialize/Keys.cpp:
  13-15`) becomes the specialization of a callee on an argument that is a
  known constructor of a dispatch sum. That is one first-order rule for
  every sum, closures included.
- **Isolate's round trip goes.** Emit writes `idr.lambda` and `idr.delay`
  regions that `idr-isolate` immediately outlines (casework-audit §1.E). Emit
  knows the captures and writes the symbol form directly (§4, stage 1).
- **Defunctionalization's conversion runs per function.** Once the keys are
  decided, each function's types are a pure function of the decision, so
  the module-wide `applyFullConversion` (`Pass.cpp:117-136`) becomes a
  nested conversion per function, in parallel (casework-audit §3).

### 2.8 What it costs, and how it is kept fast

- **Larger sums before inlining.** Before the optimizer, every apply is a
  dispatch over its full set. The optimizer then folds the known
  constructors, so the dispatches that remain are the ones whose sets are
  really plural, which MLton reports as "almost no calls" (slide 14,
  mlton §2). Lane L2 records, per key, the number of constructors and the
  dispatches left after the optimizer.
- **The solve over the stage-0 module** (about 100,000 functions after
  emission, F0). MLton's 0CFA runs in under 2 seconds on MLton itself
  (slide 14). Its representation choices, each adopted here
  (*decision*):
  - first-order values carry no flow: every first-order type shares one
    abstract value (`abstract-value.fun:242-246`), and first-order tuples
    are not tracked (`closure-convert.fun:364-367`);
  - sets are hash-consed with cached operations (`UniqueSet`, cache size 5,
    13 bits, `abstract-value.fun:42-44`);
  - mutable containers unify instead of coerce (`closure-convert.fun:341-345`),
    so union-find handles every equality constraint;
  - only differences are propagated (`abstract-value.fun:87-95`).
  Our label walk took 54 seconds before it was made one walk (6a7841dc);
  *decision:* the solve must take under 10 seconds of wall on the stage-0
  module, or the representation is wrong.

### 2.9 Risks, and how each is checked

| Risk | Check |
| --- | --- |
| The frontend emits something the closed-world verifier refuses (an external function, a second public symbol) | The verifier runs on every corpus module and the stage-0 module in lane L2; every refusal is fixed at emission |
| An op carries a closure without the flow interface | The verifier names it; every corpus module passes before L2 integrates |
| `fits` on unrestricted types admits a label whose grade differs from the slot's | A fixture per grade (linear, owned, plain) with the linearity verifier after defunctionalization; the verifier already checks quantities after every pass |
| Sums too large for code quality | Per-key constructor counts and post-optimizer dispatch counts recorded on stage 0; bench runtime within 2% (§10) |
| The forced anchor changes a memo's semantics | Every laziness test in `tests/programs`, and `memo-shared-stream` and `stream-share` with their live-cell marks |
| A program accepted today only because simplify deleted its closures now runs a dispatch it did not before | Same bench threshold; the dispatch is the program's meaning, and the optimizer removes it where the constructor is known |
| The solve is slow | §2.8's 10-second threshold on stage 0 |

## 3. Where the time goes, and the record

### 3.1 F0, the stage-0 measurement (2026-10-14)

The full record is `bench/profiles/2026-10-14-f0-stage0.md`; the numbers that
bear on this design (*measured*):

- **The frontend is not the wall:** 58,236 functions, about 300 MB of text,
  about 140 s. Nor is the prefix: parse 11.7 s, isolate 3.0, deduplicate 3.8,
  contify 3.5 (27.0 s in all, 1.09 GB).
- **Round 1 of Simplify: 447 s wall.** IdrInline 330 s, with one
  InlineCleanup instance at 211 s, effectively serial. SCCP 43 s, serial.
  Analyses rebuilt inside the round about 25 user-seconds (CallGraph 11.9,
  References twice, InlineDecisions, BindingTimes, RoundFacts). The
  per-function step is healthy: 77 user-seconds in 10 s of wall. IntRange
  nested 48 user-seconds in 6. SymbolDCE 9.4. The loop's own fingerprints
  and bookkeeping about 4 s. Peak RSS 5.27 GB.
- **Sixteen rounds, no fixpoint.** Round walls 340, 119, 99, 117, 97, 142,
  100, 120, 127, 143, 133, 119, 121, 113, 118, 117 s. Module text 158 MB to
  244 MB, still changing at round 16. Operations about 471k to about 1.25M by
  round 14, while functions fall from 100,198 to 28,276 (round 6) as inlining
  absorbs bodies. The largest functions after round 6:
  `IdrisMLIR.MLIR.statementText.spec1` about 152k ops (14% of the module in
  one function), `Idris.ProcessIdr.processMod.lam4` about 76k,
  `Libraries.Utils.Path.parse` about 45k. A steady round is flat: IdrInline
  dominates, SCCP 21 to 27 s serial, canonicalize and CSE about 20 s, IntRange
  about 28 user-seconds, SymbolDCE about 5 s. Peak RSS about 5.8 GB.
  Extrapolated, Simplify alone is over 2,000 s and unfinished.
- **The SCC structure exists.** The direct `idr.call` graph (closure applies
  are not edges in it) at emission: 58,235 functions, the largest SCC 174
  (TTImp.Elab), 93% singletons; after isolate, deduplicate and contify the
  largest is 14; after six rounds the largest is 24 of 28,276, with 99
  functions in any SCC over 10. Namespace locality: 17% of distinct
  origin-to-origin direct-call pairs share an Idris module, 49% a top-level
  segment.
- **The tail.** RemoveDeadValues (without its canonicalization) plus
  SymbolDCE on the round-16 module: 65 s wall (liveness 51 s), 7.65 GB peak,
  11 MB removed. Defunctionalize onward cannot be timed: after 16 rounds it
  still refuses a runtime closure in `Idris.Parser.directive.lam4` (§2.6).
  LLVM's share is measured only at test scale: 3.8% of the
  every-interfaces-export profile (bench/profiles, 2026-10-13).
- **The fixes that landed** 2026-10-13 and 2026-10-14, each output-identical
  where it claims: the match-field symbol scan deleted (one canonicalizer
  sweep 65.1 to 19.1 user-seconds); `idr-deduplicate` (7,505 of 107,732
  functions in about 1 s); scoped post-inline canonicalization (70,252
  whole-body runs deleted); IntRange nested (30 s to 3 s of wall per round);
  defunctionalize labels in one walk; RemoveDeadValues once at the fixpoint.
  One explicit round fell from 1,321 s to 385 s (dev build); the suite record
  from 248.8 s to 167.9 s over 429 compilations. Stage 1 still never
  finished: the round count is what remains.

### 3.2 Why the rounds never decay

The research explains the flat rounds (*read*, mlton §3, upstream-mlir-llvm
§1, casework-audit §3):

- **Our inline rule is MLton's, applied every round instead of once.**
  `InlineDecisions` inlines a leaf of at most 40 ops, and any other function
  when `(calls - 1) * (size - 60) <= 320` (`lib/Analysis/Inline.cpp:23-25,
  42-53`). MLton's non-recursive inliner has exactly `small = 60`,
  `product = 320` (`code/mlton/mlton/control/control-flags.sml:1034-1041`) and
  its leaf inliner runs at 20 and then 40 (`:1011-1032`). MLton applies each
  once, in a fixed list where every entry runs once
  (`control/control.sml:497-508`; `ssa/simplify.fun:46-122`), deciding per
  function, inlining every call and deleting the original
  (`ssa/inline.fun:465-476`). We recompute the decisions every round on
  bodies that grew, so the rule fires again and again.
- **A function with one call site always inlines, whatever its size**, and
  nothing caps the caller. That is MLton's rule too ("the minus one is the
  deleted original", mlton §3), at zero growth per decision; MLton has a
  `maxFunctionSize` control that no code reads (`control-flags.sml:1224-1226`).
  Repeated over rounds it builds the 152k-op function.
- **Specialization feeds inlining.** Clones are made for one call site, so
  they always inline, and inlining exposes static closures that ask for new
  clones.
- **Unlimited inliner iterations.** Our inliner runs with no iteration bound
  (`Inline/Inline.cpp:238`) because a `do` block of n statements needs n
  iterations; each iteration walks the whole caller, O(n x size) on a large
  root (upstream-mlir-llvm §1), and runs InlineCleanup's greedy patterns plus
  a whole-body `simplifyRegions` on what it touched (§3.4).
- **MLton's trajectory is the contrast.** In its self-compile the SSA goes
  from 719k statements to 365k and never exceeds its start; the non-recursive
  inline pass takes 341k to 491k (+44%) while functions go from 7.7k to 1.8k
  (slide 26, mlton §3, §5). Ours grows 2.6 times and does not stop.

### 3.3 The opt-in SCC pipeline, and the pinned problem

**What was built** (552d682a). `idr-simplify` gained an `scc-pipeline`
option, default off, the rounds staying the default. Under it,
`idr::runSimplifySCCPipeline` (`lib/Transforms/Simplify/Scc.cpp`) ran a pre
part once (effects, SCCP, loop breakers, RoundFacts, the per-function step
of identity, canonicalize, CSE and redirect), then a delta (inline,
specialize, RoundFacts, the per-function step) until one delta changed
nothing by the module's structural fingerprint (clone-count termination had
left `@done` uninlined on do-block, *measured*), then a post part (SCCP,
RoundFacts, the per-function step, IntRange, SymbolDCE), then the
RemoveDeadValues removal, resuming when a removal changed the module.
`max-rounds` bounded deltas, and the instrumentation counted deltas as
rounds. It had no ready set, no size-budgeted decisions, no bottom-up SCCP
summaries and no parallelism; despite its name it computed no SCCs
(casework-audit §1.A). On `tests/idr/pipeline/do-block.mlir` it reached its
fixpoint in 3 deltas, byte-identical to the rounds. The gates at 552d682a
(arm64 macOS, `NCPU=6`): `make build` clean, `make check` 27/27,
`make test-idr` 286/286, `make test` 415/415; the SCC path itself ran one lit
test. The file-size split (Scc.cpp, `Simplify/Trace.cpp`; `Simplify.cpp` 463
to 383 lines) was pure movement, byte-identical.

**The verdict run, killed.** Started 2026-10-14 17:03 CDT on the post-contify
stage-0 module (`/tmp/f0/post-contify.mlir`, 158 MB; the raw emission is
`/tmp/idris-mlir-stage0.mlir`, and `/tmp/f0/round1` to `round16.mlir` are the
manual round trajectory), at background priority on efficiency cores, with
output written only at exit:

```
/usr/bin/time -l nice -n 10 taskpolicy -b \
  build/dev/foreign/idr/idris-mlir-opt /tmp/f0/post-contify.mlir \
  '--pass-pipeline=builtin.module(idr-simplify{scc-pipeline=true})' \
  -mlir-timing --mlir-pass-statistics \
  -o /tmp/f0/scc-out.mlir --remarks-filter-passed=idr-simplify
```

Sampled inside the pipeline at 36 and 86 CPU-minutes, about 1 GB RSS; killed
by the owner at 18:10 after about 66 wall-minutes and at least 90 CPU-minutes,
with no output and no verdict. An earlier throttled attempt was cancelled at
21 CPU-minutes still inside its first delta's inlining. Its wall time is not
comparable with §3.1's unthrottled rounds.

**The pinned problem** (owner, 2026-10-14). It landed as an opt-in: a
behaviour-selecting pass option with the old rounds as the fallback. Two code
paths for one pass means every change pays twice, every test proves half, and
the unexercised path rots while looking supported. It got there because the
landing rule (measure or revert) was read as needing both pipelines in one
binary; the A/B scaffolding was then checkpoint-committed to `main` instead of
staying a local probe, and froze into the tree with a maintained test for the
flag and proposal prose calling it a steady state. The same day's §3.4
experiments were compared old binary against new binary, which needs no
option. The casework it created: the option, the branch, three extra pass
managers built whether or not they run; one counter with two meanings (deltas
counted as rounds, `max-rounds` bounding deltas); traces keyed on the
composite's pipelines, so the deltas were untraced and the killed run could
not report its progress; RUN lines whose only purpose was diffing the two
paths; and the round machinery it kept despite this file's earlier promise to
delete it (a fingerprint around every delta and removal, RoundFacts per delta,
SCCP twice, the resume loop). This design resolves it by deletion (§6):
neither the option nor the rounds survive, and measurement is by binary
(§10).

### 3.4 Two refactors measured and reverted (2026-10-14)

`InlineCleanup` (`Inline/Inline.cpp:76-157`) is the pipeline upstream's
inliner runs on a function an iteration inlined into: seeded canonicalization
patterns, then `simplifyRegions(..., mergeBlocks=false)`, a whole-body
liveness fixpoint (`M/lib/Transforms/Utils/RegionUtils.cpp`, `runRegionDCE`),
and an unconditional whole-body `eraseUnreachableBlocks` before the patterns.
Upstream's inliner optimizes an SCC before every inline attempt until one
inlines nothing (`M/lib/Transforms/Utils/Inliner.cpp:471-490`); its only
parallelism is across one SCC's nodes (`:527-567`), and our SCCs are 93%
singletons: the wall-equals-user signature of the 211 s.

- **Strict worklist confinement** (`GreedyRewriteStrictness::ExistingAndNewOps`):
  a do block took 19 rounds against 3, and the corpus produced a
  linearity-invalid intermediate state. The apply a returned closure feeds
  sits more than one hop from any seed, through continuation block arguments.
- **Deferring the structural half** (no `simplifyRegions` in the hot cleanup;
  once per touched function after inlining, in parallel): 7% slower, old
  binary against new under identical conditions on the round-6 module (462 s
  against 494 s; IdrInline user time 108 to 139 s; outputs the same size, 18
  lines of op order apart).

Both leave one finding: the dominant cost is the greedy pattern work itself,
spread from the seeds over enormous bodies and repeated per inlining
iteration. The design of §4 runs that work once per function, after its
callees are final.

## 4. The pipeline after the cutover

Each stage says what is whole-program (decided once, read frozen) and what
runs per unit. *Decision* for every stage unless marked.

1. **Frontend** (Idris; whole-program by nature: monomorphization, the
   instance set, representations).
   - Closures and suspensions are written in symbol form: each lambda and
     delay is an `idr.func`, and `idr.closure`/`idr.suspend` name it with its
     captures. Emit knows the captures; `idr-isolate` and the
     `idr.lambda`/`idr.delay` region forms go.
   - Generated names are derived from content: the owner's name and a hash
     of the structural key, never a counter (`.lam<n>`, `.delay<n>`,
     `Isolate.cpp:124-125`, and every other counter-named symbol, §6).
   - Binders are keyed by identity, so the synthetic world binder needs no
     `$world` rename (`Frontend/Translate/Programs.idr:182-193`) and holes
     need no sentinel name renamed around Idris's normaliser
     (`Translate/Closed.idr:173, 287-295, 471-476`): the open term is
     normalised under an environment that binds the holes.
   - The in-place promise is a fact of `mlir-linear`'s types, emitted with
     them, replacing `--demand-in-place` (§6).
   - The handoff is MLIR bytecode: the frontend writes it and the driver
     reads it (`readBytecodeFile`); text remains a dump. This kills the
     11.7 s parse and every text round trip in the corpus tooling (the
     earlier F4). Lands on identical bytes everywhere.
2. **Closed-world verification** (whole-program, one walk): no external
   `idr.func`, one public root, every closure- or lazy-typed operand on an op
   with the flow interface (§2.2).
3. **Deduplication** (whole-program by content; hashing per function in
   parallel): Mojo's EliminateDuplicateFunctions design, bottom-up over a
   ready set so that merging is transitive in one pass, with the
   lexicographically smallest member of each class kept (mojo §4, §7;
   `code/modular/Mojo/lib/Transforms/EliminateDuplicateFunctions.cpp:31-80,
   188-254`). It runs before defunctionalization so the label sets are
   smaller.
4. **Defunctionalization, total** (§2): the label solve is whole-program; the
   conversion is per function, in parallel.
5. **Contification** (whole-program analysis, per-function rewrite): MLton's
   dominator-based contification on first-order code (Fluet and Weeks, ICFP
   2001; `code/mlton/mlton/ssa/contify.fun`, mlton §3). A function that always
   returns to the same place becomes a block of its caller, which gives loops
   without growth. It runs early, before inlining, as MLton interleaves it with
   loop formation (`ssa/simplify.fun:48-54, 82-97`). Today's Contify
   (`lib/Transforms/Simplify/Contify.cpp`) exists because upstream's inliner
   refuses A to B to A (`M/lib/Transforms/Utils/Inliner.cpp:729-734`); it is
   replaced, not kept beside.
6. **The first-order optimizer: one bottom-up ready set over the call graph.**
   - The graph is upstream's `CallGraph`, complete now that every closure is a
     direct call (§2.7), and its SCCs come from our deterministic Tarjan
     (`include/idr/Support/Scc.h`). A node is ready when every callee outside
     its SCC is final.
   - A ready function gets its inline decisions (below), its calls inlined
     with upstream `mlir::inlineCall`, and then **one inner per-function
     pipeline, run once**: identity, canonicalize with the one configuration
     (`include/idr/Transforms/Canonicalize.h:34-38`), CSE, redirect,
     int-range, case of known constructor. The pipeline runs through
     `Pass::runPipeline` from per-thread copies of one `OpPassManager`, the
     pattern upstream's inliner uses (`M/lib/Transforms/Utils/Inliner.cpp:
     526-567`), so the verifier and the instrumentation stay on.
   - **A bounded local loop** follows: a call the cleanup exposed (a dispatch
     whose constructor became known) into a callee that is already final is
     inlined under the same decisions, then the pipeline runs on the caller
     again, at most until the caller's cap. Mojo has no such loop because it
     lowers closures later (mojo §2); ours needs it because case of known
     constructor exposes direct calls.
   - This is Mojo's AutomaticInline design (`code/modular/Mojo/lib/Transforms/
     AutomaticInline.cpp:380-501`, mojo §2), rebuilt on our `Scc.h` and MLIR's
     thread pool (`llvm::ThreadPoolTaskGroup`, whose `wait` lends the waiting
     worker, pinned `ThreadPool.h:68-72`), not ported with AsyncRT (§8).
   - Deterministic by dataflow order: a body is a function of its own body and
     its callees' final bodies; a callee is read only after it is final; calls
     are inlined in call-site order; dead functions are erased afterwards,
     serially, in module order (mojo §2, §5).
7. **Inline decisions.** MLton's per-function formula, evaluated on the
   callee's final size, the way Mojo measures it lazily after the callee's
   own pipeline (`AutomaticInline.cpp:161-166`): a leaf at most 40 ops inlines;
   any other function inlines when `(calls - 1) * (size - 60) <= 320`; a member
   of a recursive SCC is never inlined into another member; when every call is
   inlined, the original is deleted. Plus what MLton lacks: **a per-caller
   size cap** above which nothing more is inlined into that caller, so the
   152k-op function is refused at decision time, not discovered in a trace.
   Reaching the cap stops inlining into that caller; it never rejects.
8. **Specialization as demand-driven nodes in the same ready set.** A call
   whose argument is a known constructor of a sum, closures included, is a
   request keyed by (callee, the static pattern). The key's node is created
   once, named from the key (never `<owner>.spec<n>`, `Clones.cpp:20, 40-41`),
   and enters the ready set below the requesting caller, the way Mojo's
   elaborator creates instantiation nodes keyed by content and resumes waiters
   (`code/modular/Mojo/lib/Elaborator/Elaborator.cpp:1675-1693, 1746-1756,
   2944-2989`, mojo §4). `kClonesPerOwner` stays as a budget that stops
   specializing. Specialization of static structure, raising and binding times
   have no upstream analogue and stay ours (upstream-mlir-llvm §8).
9. **Interprocedural constants and effects as bottom-up SCC summaries.** Each
   function's solve runs with interprocedural mode off, in parallel, and
   upstream's `visitExternalCall` hook applies the callee's summary, computed
   callee first over the SCC order (upstream-mlir-llvm §4;
   `M/lib/Analysis/DataFlow/SparseAnalysis.cpp:229-251, 277-302, 523-538`).
   This replaces module SCCP every round (21 to 43 s serial) and the effects
   computed three ways (§6). The solver and the analyses stay upstream; the
   driver and the summary lattice are ours. Call-site `effects`
   (`IdrOps.td:59-75`), a verified cache of the callee's, is written once here.
10. **Dead values once:** upstream RemoveDeadValues and SymbolDCE at the end of
    the optimizer, once (65 s and 7.65 GB on the round-16 module, *measured*;
    a per-SCC liveness is left to 0006).
11. **Memory and loops:** `idr-stack`, `idr-accumulate`, `idr-rc`,
    `idr-demand`, `idr-trmc`, `idr-tail-loops`, `idr-narrow`, `idr-in-bounds`,
    as today: module plans, nested rewrites. Changes: `idr.stack` becomes an
    inherent property of `idr.con`; `idr-rc`'s exclusivity loop
    (`Ownership/Rc.cpp:84-96`) computes each function's grade contexts as a key
    set first and clones once; `idr-demand` always checks the type facts
    (§6).
12. **Lowering:** layouts are whole-program and decided first; the runtime's
    declarations are created up front from the decided set instead of inserted
    into one symbol table as the conversion goes; the conversion runs per
    function (today one serial `applyPartialConversion`, `Lower.cpp:166`).
13. **Partitioning** into codegen units (§5): a pure function of content.
14. **Per partition:** each unit is a nested `builtin.module`; the lowering
    tail (`convert-to-llvm`, `convert-vector-to-llvm`,
    `reconcile-unrealized-casts`) runs under `pm.nest<ModuleOp>()`;
    `translateModuleToLLVMIR` takes the sub-module with its own
    `llvm::LLVMContext` (`M/include/mlir/Target/LLVMIR/Export.h:32-36`;
    upstream-mlir-llvm §5).
15. **LLVM optimization and code generation per partition** (§5's two steps).
16. **Link** the N objects in unit-name order with the runtime.

**Determinism rules** (*decision*): the partition count is a function of the
module's size, never of `--num-threads`; every parallel join merges in a
canonical sorted order; every name is derived from content; erasure is
deferred and serial in module order; node maps are ordered (MapVector);
output is byte-identical at 1, 2 and 8 threads, checked by
`tests/determinism` (mojo §5, codegen-partitioning §9).

## 5. The code generation unit

### 5.1 The evidence

- **MLton splits for size, not for parallelism** (mlton §4). A Machine
  program is a list of chunks, each a C or LLVM function holding blocks from
  possibly many SML functions (`backend/machine.fun:898-935`). The modes are
  One, Func, `Coalesce{limit}` (blocks linked by goto, switch or C-call return
  never split; call and return edges coarsened up to the limit,
  `backend/chunkify.fun:54-178`) and Simple (by call-graph SCC, `:190-431`).
  The default is `Coalesce 4096` for C and LLVM (`main/main.fun:1213-1222`).
  Chunks are batched into files of about 2^15 statements
  (`control-flags.sml:125-127`) and compiled **serially**, a `List.fold` of
  `System.system` (`main/main.fun:1475-1494, 1546-1574`). Calls between chunks
  go through a trampoline (`include/c-main.h:33-37`) because C cannot promise
  tail calls and MLton keeps its own stack; with LLVM's `musttail` our units
  are plain functions, so a unit is a module split, not a function-merging
  device.
- **LLVM** (codegen-partitioning §1, upstream-mlir-llvm §6). `SplitModule`
  externalizes locals (`L/lib/Transforms/Utils/SplitModule.cpp:230-239`),
  clusters comdats, aliases, block-address users and locals with their users,
  places clusters on the least-loaded of N bins by symbol count, hashes the rest
  by MD5 of the name (`:114-224`), clones the module once per part, keeps inline
  asm in part 0 (`:293-294`), and admits internal-name collisions with outside
  symbols (`SplitModule.h:32-38`). `ParallelCG.h` is gone from the pinned tree;
  the live pattern is `L/lib/LTO/LTOBackend.cpp:517-570`: bitcode written per
  part on the main thread, parsed in a fresh context with its own
  `TargetMachine` on a pool thread. LTO uses N = threads, so its objects change
  with the thread count.
- **lld on Mach-O builds `lto::LTO` with no parallelism level**
  (`lld/MachO/LTO.cpp:124`), so on our macOS target there is no split codegen
  through the linker: we split ourselves.
- **GCC WHOPR** cuts size-balanced intervals at the best boundary of internal
  against external edges (`lto-partition.cc:1198-1520`), and keeps source
  files together in its `cache` mode to limit divergence; GCC 6m31s to 48 s,
  Firefox 19m29s to 5m30s on 24 cores, the serial whole-program analysis
  bounding further gains (codegen-partitioning §2).
- **rustc** gives each module a stable and a volatile codegen unit, merges to
  16 or 256, copies only `#[inline]` items, names merged units by a hash of
  sorted names (*recalled*, codegen-partitioning §4). **Swift** WMO optimizes
  SIL whole and splits IRGen and LLVM per source file (§5 there). **Zig** codegens
  per function into one linker thread (§6 there). **GHC** and **Lean** are
  per module (§7 there).

### 5.2 The candidates

- **One SCC per unit.** Closed under mutual recursion, so tail loops and
  per-SCC attribute inference stay inside; 93% singletons make it maximally
  edit-stable. As a codegen unit it is far too fine: about 54,000 LLVM modules,
  each with its own context, target machine, pass setup and object, and a link
  with tens of thousands of inputs.
- **One Idris module per unit.** Matches how people edit and gives names for
  free, but only 17% of direct calls stay inside a module, monomorphized
  instances have no single home (rustc's volatile-unit problem), and instance
  counts are skewed toward Prelude and base.
- **Size-balanced bins of SCCs.** Controls load balance and per-unit overhead,
  never splits an SCC, and can be deterministic and edit-stable. GCC's
  partitioners and rustc's merging both land here.

### 5.3 The decision

*Decision:* **size-balanced bins of SCCs, grouped by top-level namespace,**
which agrees with 0006 D4:

1. **The bin count does not depend on threads.** The target is a fixed
   estimated size, so the objects and the executable are the same for every
   worker count. Several bins per core, largest started first.
2. **Edit-stable cuts.** Group by top-level namespace first (49% of calls stay
   inside one). Within a group, order SCCs by content hash and cut where the
   hash meets a boundary condition, between a minimum and a maximum size.
   GCC's balanced cut at a running total would shift every later cut on one
   edit. A single function too large for a bin is a unit of its own.
3. **Linkage between units.** Each definition lives in exactly one unit. A
   symbol another unit references gets external linkage, hidden visibility,
   `dso_local`, and its content-derived name under a reserved prefix, which
   avoids the static-link collision `SplitModule`'s FIXME warns of. Symbols
   used only inside their unit become internal. The runtime enters every unit
   as `available_externally`, as it enters the one module today
   (`Run.cpp:186-190`). Objects link in unit-name order. `--icf=all`, already
   on with function sections (`CMakeLists.txt:174, 213`;
   `Target/Optimize.cpp:30`), recovers the cross-unit folding MergeFunctions
   would miss.
4. **To verify on both targets:** `musttail` and the `idr-tail-calls` plan
   across object boundaries on Mach-O and ELF; the runtime's inline asm
   (`Run.cpp:209`) against the part-0 rule.

### 5.4 Two steps

- **S2, first:** keep the whole-module O3, then split only code generation,
  with the fixed bin count and our own size-based predicate (`SplitModule`'s
  clone loop is fine to reuse, about 40 lines of partition logic of our own);
  one context and target machine per unit, objects written in index order.
  Almost nothing is lost, because code generation is per function after O3.
- **Then, split before O3**, one context per unit, ThinLTO's shape without its
  summaries (*decision*: LLVM's summary-based importer would be a second
  inlining analysis beside ours, which the one-representation rule forbids).
  The interprocedural facts LLVM would lose across units are emitted from our
  whole-program analyses as attributes on cross-unit declarations: memory
  effects, `nounwind` and `willreturn` from the effects summaries; `noalias`
  and `readonly` from exclusivity and borrows; `nonnull` and `dereferenceable`
  from layouts (codegen-partitioning §9).

What Mojo does here, for reference (mojo §1): it splits the LLVM module per
exported root with transitive callees (`LLVMIRUtils.cpp:301-420`), optimizes
each split in its own context, splits again per function for codegen, and
links the machine functions back with an `MCLinker` that needs a non-upstream
LLVM patch and reaches into LLVM's private members (`LLVMAccessorHelper.cpp:
41-69, 150`). We take the shape, upstream's `SplitModule` and the LTO backend
pattern, and never the linker (§8).

## 6. What is deleted

Every row is casework that guards against a state the right representation
makes impossible (casework-audit §1, §4). Paths are under `foreign/idr/`
unless named. Nothing in this table survives the cutover, and nothing
replaces it with a better branch.

| Deleted | Code | Why it exists today | The representation change that deletes it |
| --- | --- | --- | --- |
| `idr-simplify{scc-pipeline}`, its branch, three extra pass managers, `Scc.cpp`, the do-block RUN line that diffs the paths | `include/idr/Transforms/Passes.td:613-616`; `lib/Transforms/Simplify/Simplify.cpp:119-120, 131-136, 149-153, 165-176, 217`; `Simplify/Scc.cpp:83-110`; `tests/idr/pipeline/do-block.mlir:5-6` | An A/B harness committed as a mode (§3.3) | One pipeline (§4); comparison by binary (§10) |
| `max-rounds`, the composite fixed point, `Round.cpp`, `Trace.cpp`, `SimplifyInstrumentation` and the pass's failure without it | `Passes.td:611`; `Simplify.cpp:123-128, 160-164, 189-209, 242, 244-377`; `Simplify/Round.cpp`; `Simplify/Trace.cpp` | Rounds repeat until nothing changes; the loop's counter lives in an observer found by the string `"composite-fixed-point-pass"` | The ready set: each function is processed when its callees are final; an empty worklist is the end (§4.6) |
| The composite's `OperationFingerPrint` fixpoint | `Simplify.cpp:126-128` | Change detected by hashing the module after every round | Change is the returned fact of the pass that made it (`applyPatternsGreedily`'s `changed`, the inliner's clone callback) |
| The RemoveDeadValues resume loop | `Simplify.cpp:193-204`; `Scc.cpp:106-110` | Two whole-module SHA1s per resumption, so that a removal can restart the rounds | Dead values removed once, at the end of the optimizer (§4.10) |
| The inliner's preparation and inline repeat, and its cycle guard | `Inline/Inline.cpp:174-181, 175-312` (24eff40c) | Preparation and inlining can oscillate, so a list of module fingerprints stops them silently when the module returns to an earlier shape | Bottom-up order on first-order code: a callee is final before its caller reads it, and no closure needs preparing (§2.7) |
| The `idr.inlined` seed marks | `Inline.cpp:74, 98-121, 257-260, 299-301` (5088d7a8) | A discardable attribute marks what an iteration inlined, a pre-walk finds it, a module sweep removes leftovers | A function is cleaned once, when it is final: what changed is the function itself |
| `InlineCleanup` per iteration with `simplifyRegions` and `eraseUnreachableBlocks` | `Inline.cpp:76-157, 143-153` | Upstream's inliner re-optimizes every SCC node on every iteration | The inner per-function pipeline, once per function (§4.6) |
| `LoopBreakers` | `Simplify/LoopBreakers.cpp:15-20` | Inlining repeats across rounds and must not unroll a cycle | Recursive SCC members are never inlined into each other; the bottom-up order needs no marks |
| `RoundFacts` | `Simplify/RoundFacts.cpp:6-15` | A nested pass manager drops module analyses, so facts are recomputed before every nest | Facts are computed once per stage and read frozen by the units (§4) |
| The `CloneAttr` self-reference and its special cases | `include/idr/IR/IdrAttrs.td:231-242`; `Analysis/LabelSites.cpp:118-122`; `Ownership/Rc.cpp:70-73`; `Deduplicate/Deduplicate.cpp:306-320` | A clone names itself so that SCCP, dead-code analysis and RDV treat it as having unknown callers that later rounds fill | No rounds: a clone is an ordinary private function made once, named from its key |
| `unsupported (compile-time budget)` from the rounds and from specialization | `Simplify.cpp:207-209`; `Specialize/Clones.cpp:30-33`; `include/idr/Analysis/Specialize.h:59` | Assertions about the optimizer's termination reported as rejections of the user's program | Budgets stop optimizing; a broken termination argument is an internal error (§2.5) |
| The closure analysis's unknown element, `labelsFor`, the sealing cascade, `escapes`, `unsupported (runtime closure)` and `unsupported (laziness)` | `include/idr/Analysis/Labels.h:55`; `LabelSites.cpp:92-114`; `Defunctionalize/Decide.cpp:97-184, 158-164, 204-219`; `Defunctionalize/Pass.cpp:43-50, 96-101` | A gap in what the analysis follows becomes unknown, and unknown spreads | Closed world, one flow interface, the forced anchor, no unknown (§2.2) |
| `isFollowed` and the second flow table | `Defunctionalize/Moves.cpp:27-79, 209-247` against `Analysis/Labels.cpp:68-123` | Closure flow decided twice, and the two disagree on `cf.br` | One flow interface read by both |
| `unifySuspensions` and Isolate's evaluated-delay branch | `Moves.cpp:147-206, 37-38`; `Isolate/Isolate.cpp:80-86` (43a9e235) | An evaluated delay's yield becomes unknown | The forced-state anchor keyed by the lazy value's type |
| `idr-isolate`'s region round trip | Emit's `idr.lambda`/`idr.delay`; `Isolate/Isolate.cpp` | Emit writes regions that the first pass outlines | Emit writes the symbol form (§4.1) |
| `idr-rc{reuse,sink}` | `Passes.td:668-671`; `lib/Transforms/Pipeline.cpp:119-120` | Measurement toggles | None; a comparison is two binaries |
| `--without`, the Sink/Build/Names classes, `pipelinePassNames`, the demand-against-without usage error | `lib/Driver/Options.cpp:46-50`; `lib/Driver/Run.cpp:80-104`; `Pipeline.cpp:29-89, 182-187` (44495199) | Turning passes off from the command line, then reconciling two toggles | `idris-mlir-opt --pass-pipeline` for experiments; the compiler has one pipeline |
| The strings `"reuse"`, `"sink"`, `"in-place"` | `Run.cpp:83-85`; `Pipeline.cpp:119-124` | Toggles matched by name | Gone with the toggles |
| `--demand-in-place`, `idr-demand{in-place}` | `Passes.td:696`; `Options.cpp:53-57`; `Pipeline.cpp:123-124`; `tests/lib/e2e.sh:64` | The command line decides whether a program is rejected, which makes two languages | The promise is a fact of `mlir-linear`'s types ("rebuilt in place, exclusive"), emitted by the frontend; `idr-demand` checks it every time |
| `--dump-dir` | `Options.cpp:66-69`; `lib/Driver/Dump.cpp` | Per-pass dumps | Upstream `-mlir-print-ir-tree-dir` (`M/lib/Pass/PassManagerOptions.cpp:61`), which `Run.cpp:118` already enables |
| `idr.stack` as a discardable attribute | `include/idr/IR/IdrBase.td:58`; `Stack/Stack.cpp:62-96`; read in `Ownership/Reuses.cpp`, `Exclusivity.cpp`, `lib/IR/OpsCon.cpp:38`, `Conversion/Cells.cpp:52` | A memory fact kept where a pass can drop it, after which idr-rc and idr-lower disagree about a cell | An inherent property of `idr.con` |
| `idr.program` as a discardable attribute | `IdrBase.td:58`; `Conversion/Lower.cpp:217-219` | Its presence alone turns on the verifier's stage and linearity rules; dropping it disables them silently | The stage is what the IR's own types say: owned grades exist only after idr-rc, so the verifier reads the stage from them (*decision*; §11 open question 4) |
| Closure flow, canonicalization and effects each held several times | Canonicalization: `include/idr/Transforms/Canonicalize.h:34-38` against `Specialize/Clones.cpp:74` (default config, bottom-up, regions on), `Inline.cpp:86-94, 143-153`, `Specialize.cpp:82-90`; effects: idr-effects, `Defunctionalize/ByName.cpp:25-46`, `Clones.cpp:54-66` | Each pass built its own copy | One canonicalization configuration, one pattern set collected once; one effects summary (§4.9) |
| The lookup-dodging branches and the module-scanning declaration lookups | `IR/Canon/MatchPatterns.cpp:101-121`; `Canon/Eta.cpp:43-87`; `IR/OpsClosures.cpp:325-326`; 20 lookups through `IR/Symbols.cpp:51-62` (0768bc9f, 4d207761) | `!idr.data<@T>` keeps its constructors in a symbol, so a pattern scans the module to read a type | Types that carry their declaration: identified types with bodies, as LLVM's identified structs carry theirs; a pattern reads the type (§11 open question 5) |
| `listElement`'s "any two-field constructor is the cons" | `IR/Symbols.cpp:65-72` | The list's role guessed from its shape | The declaration carries the role as a type fact |
| Deduplicate's refusal of functions with an `instance` fact | `Deduplicate.cpp:183-195, 322-331` | `idr-expect` looks functions up by provenance name, so a test API constrains an optimization | `idr-expect` finds functions by structure and facts, not names |
| Names from counters and module order | `.lam<n>`/`.delay<n>` (`Isolate.cpp:124-125`); `.capture<n>` (`Inline/Prepare.cpp:126`); `.spec<n>`/`.raise<n>` (`Clones.cpp:40-41`); `fn$<n>`/`lazy$<n>` by first appearance (`Defunctionalize/Decide.cpp:188-198`); `.acc`, `.trmc`, `.excl` | Creation order reaches output | Names from keys: the owner and a hash of the structural key |
| The driver's decision by message prefix `"unsupported ("` | `Run.cpp:252` | A refusal recognized by its text | A refusal carries its rule as structured data on the diagnostic, which the driver reads |
| `idr-rc`'s exclusivity loop | `Ownership/Rc.cpp:84-96` | Bounded by the number of calls, with an internal error if it "did not settle" | Each function's grade contexts computed as a key set first, then each copy made once |
| `InBounds/Empty.cpp` | `Transforms/InBounds/Empty.cpp` | Integer emptiness reimplemented because upstream's exact search was slow (qsort, 180 s) | An upstream Presburger patch with its reproducer (§7); the in-bounds stack itself goes in 0003's purge |
| `Frontend/Translate/Prof.idr` | `compiler/src/IdrisMLIR/Frontend/Translate/Prof.idr:58-66, 224, 240-313`; `compiler/idris-mlir.ipkg:42` | A profiling module "never committed", committed with e569ea3f: eight environment variables, five behaviour toggles, global IORef memo tables; nothing imports it | Deleted |
| The `$world` rename and the hole sentinel | `Translate/Programs.idr:182-193`; `Translate/Closed.idr:173, 287-295, 471-476` | Binder facts keyed by (name, span); a marker name captured by Idris's normaliser | Binder identity; open-term normalisation under an environment that binds the holes (§4.1) |

**Upstream patches that lose their only site.** 02 (`sccp` re-makes
constants), 16 (RDV rebuilds unchanged calls) and 22 (RDV re-poisons
operands) are carried only because the composite's fingerprint loop reads
"the module prints the same, but OperationFingerPrint changes" as a change
(`PINS.md:108-152, 335ff`, casework-audit §1.B). With the loop gone, their
`llvm.patch` files, `tests/upstream` checks and PINS entries go; each report
stays in `upstream/` as an LLVM submission marked "not carried", since the
bugs are real upstream (*decision*).

**Kept:** `--num-threads` (a resource; output does not depend on it);
`idr-expect{holds}` (a test API); IntRange per function (5d3318fb); labels in
one walk (6a7841dc), whose `labelsFor` goes with unknown; the upstream/23 CSE
statistics patch; the call-site `effects` cache, written once (§4.9);
code-quality thresholds (inline 40/60/320, `kUnrollLimit` 32, stack
256/1024/64, the in-bounds branch budget 512), which are fine once they can
no longer change acceptance (casework-audit §1.C).

## 7. Upstream first

The four upstream changes the research named (upstream-mlir-llvm §8),
re-evaluated against this design (*decision* for each verdict):

- **The adaptor's preserved-set intersection** (an adaptor preserves nothing,
  `M/lib/Pass/Pass.cpp:619, 1183-1186`, and every nested pipeline clears its
  analyses, `:673-679`). Remains useful: the units read stage facts computed
  by a module step, and the inner pipeline runs through `runPipeline`. Taken
  only if the post-cutover record names analysis rebuilds.
- **A dirty-node option for the inliner.** Unnecessary: the ready-set driver
  calls `mlir::inlineCall` directly and runs its own pipeline once per function.
- **Inlining in place through A to B to A** (`Inliner.cpp:729-734` against
  `:661-668`). Unnecessary: contification on first-order code replaces today's
  Contify.
- **Reference edges in `CallGraph`.** Unnecessary: after defunctionalization
  no closure reference remains to be an edge.

What remains for upstream, each a patch under `upstream/` with its report,
reproducer, `tests/upstream` check and PINS entry, sent under LLVM's AI tool
policy as `upstream/README.md` already requires (a human reviews every line
and answers for it, an `Assisted-by: Claude Code` trailer, the owner's
explicit approval of each post, one submission at a time):

1. **`duplicate-function-elimination` generalized** from `func::FuncOp` to
   `FunctionOpInterface`, with transitive merging in one pass and a hook for
   facts that must match
   (`M/lib/Dialect/Func/Transforms/DuplicateFunctionElimination.cpp:23-48`).
   Until it lands upstream, our deduplication is the ported Mojo design (§8),
   and the port is deleted when the pin carries upstream's.
2. **The region simplifier's exponential case:** reduce Mojo's
   `FIXME(#25742)` (`KGENToLLVMPipeline.cpp:43-47`) to an upstream reproducer.
   Our cleanup no longer calls `simplifyRegions` per iteration, but upstream's
   canonicalizer on the LLVM dialect still can.
3. **Integer emptiness:** `Empty.cpp`'s branch on the simplex's fractional
   coordinates under a budget, as a Presburger patch with the qsort reproducer.
4. **Statistics of dynamic pipelines:** passes run through `runPipeline` are
   never printed (`M/lib/Pass/PassStatistics.cpp:62-136`); the inner
   per-function pipeline is one.
5. **One-Shot module bufferization over `FunctionOpInterface`,** which 0003
   needs (its U1); recorded here so the two proposals share one upstream queue.
6. Later, a DAG-parallel CGSCC traversal for upstream's inliner (mojo §7), if
   our driver's shape proves out.

## 8. What we take from Modular

Ranked (mojo §7). Port means the file comes over under proposal 0001's
protocol; rebuild means the design comes over and the code is ours.

| Rank | What | Port or rebuild | Size | Replaces in our tree | Dependencies |
| --- | --- | --- | --- | --- | --- |
| 1 | The SCC ready-set scheduler (`Mojo/include/Mojo/TransformUtils/SCCUtils.h:60-170`: atomic counters per SCC, a worklist inside each SCC, bottom-up rewrites) | Rebuild on our `Scc.h` and MLIR's thread pool | 150 to 250 lines | `Simplify.cpp` (383), `Round.cpp` (79), `Scc.cpp` (112), `RoundFacts.cpp` (48), `Trace.cpp` (49), every module fingerprint | none beyond MLIR; not `CallGraphUtils.h`, whose parallel build makes caller order nondeterministic (`CallGraphUtils.h:160-198`) |
| 2 | Inline then pipeline once, per function (`AutomaticInline.cpp:380-501`, about 350 of its 715 lines carry over) | Rebuild | about 350 lines | `Inline/Inline.cpp` (324): InlineCleanup, the seed marks, the cycle guard, the use of upstream's inliner driver | upstream `mlir::inlineCall`; per-thread `OpPassManager` copies run by `runPipeline` (`M/lib/Transforms/Utils/Inliner.cpp:526-567`), keeping the verifier and instrumentation that Mojo's `PerThreadPassManagers` turns off (`InliningUtils.cpp:285-322`); our decision rule with the caller cap and the bounded local loop of §4.6 |
| 3 | Specialization as demand-driven nodes (`Elaborator.cpp:1675-1693, 1746-1756, 2944-2989`) | Rebuild | part of the ready set | `idr-specialize`'s generation loop and `RedirectPass` | names from the key (not `Clones.cpp:20`) |
| 4 | EliminateDuplicateFunctions (`Mojo/lib/Transforms/EliminateDuplicateFunctions.cpp`, 301 lines) | Port nearly whole | about 300 lines | `idr-deduplicate`'s "left for a later run" (`Deduplicate.cpp:20`) | our rules for which uses may be renamed and our fact comparison; deleted when upstream's generalization lands (§7) |
| 5 | The parallel code generation baseline (`ObjectCompiler.cpp:540-606, 858-897, 1178-1243`) | Rebuild on upstream `SplitModule` and the LTO backend pattern | about 150 lines in `lib/Driver/Artifacts.cpp` and `lib/Target/Optimize.cpp` | the one-module codegen (`Run.cpp:164-201`) | `splitPerExported` (about 300 lines) only if per-partition optimization is wanted, at §5.4's second step |
| 6 | Bottom-up SCC summaries (the SCCGraph pattern of IPDF, InferFunctionAttrs, ArgPromotion; `DeadArgumentElimination.cpp`, 695 lines, as a reference) | Rebuild | with §4.9 | module SCCP per round; three effects computations | upstream's dataflow solver |

**Never comes:** AsyncRT (16,114 lines; its includes reach
`Support/max_license/Tracy/Tracy.h`, which the open export lacks, so it does
not compile from the tree; MLIR's thread pool suffices); MCLinker and
`LLVMAccessorHelper` (a non-upstream LLVM patch and private members, against
AGENTS.md's upstream rule); `PerThreadPassManagers` (upstream has the pattern,
and Mojo's turns off the verifier); the Canonicalizer (our configuration
already matches: region simplification off, `Canonicalize.h:34-38`; the lesson
is where it runs); `Cache/` for now (about 1,000 lines; content-addressed
blobs for 0006's memoisation later, rebuilt on LLVM's xxhash in about 200
lines).

**Licensing steps** (0001 §1, §3, §4; mojo §6). Every Modular file is
Apache-2.0 WITH LLVM-exception, and every file read carries the header
(Mojo/lib 370 of 370, Mojo/include 177 of 177, Support 359 of 359, AsyncRT 64
of 64, Cache 11 of 11); the repository has no NOTICE; `Licenses/` is the MAX
Community License for shipped products and does not travel with the source. A
ported file keeps Modular's header verbatim, gains an SPDX line and a changes
line naming `9211931`, and gets a PINS.md entry; the licence text is already in
`LICENSES/`. Modular builds against LLVM `8d4fc8f1` with its own patches; both
trees use the `Op::create(b, ...)` builders, and the API distance is measured
per file at port time. `Support/HashUtils`' external xxhash (BSD-2) is
replaced with `llvm/Support/xxhash.h`. Proposals 0001 and earlier drafts of
this file cite Modular at `4b0d20f`; their line numbers are re-read against
`9211931` before any port.

## 9. Ready for sharding

Every unit of this design is 0006's unit, so 0006 consumes it unchanged
(casework-audit §3):

- **Inherent, whole-program, decided once and read frozen:** defunctionalization's
  label sets and sums (the conversion is per function); `idr-rc`'s borrow and
  exclusivity grades (placement and commit already nested, `Rc.cpp:66, 101`);
  layouts; the tail-call cycle plan; escape summaries; ranges; reachability.
  These are 0006's phase 2.
- **Accidental, and deleted here:** the rounds; RoundFacts; LoopBreakers;
  RemoveDeadValues per round; InlineCleanup's serial work on singleton SCCs;
  symbol creation serialized and named by order; the mutable shared
  `CloneTable`; the `CloneAttr` self-reference; the instrumentation's mutex and
  records keyed by pass pointer (`Simplify.cpp:372-376`); nominal types that make
  every canonicalization read the module's top level; one module-wide
  conversion each in defunctionalization and lowering; the single LLVM module.
- **Module passes for one symbol or one use count** (Isolate, Contify,
  Deduplicate, Accumulate, Trmc) either go (Isolate, today's Contify) or become
  per-unit work over decided facts.
- **The ready set is 0006's phase 3 with a serial scheduler.** Serial drains the
  ready set in canonical order; parallel drains it with the pool and merges in
  the same order. Sharding swaps the scheduler and moves units into
  per-worker contexts as bytecode (0006 D7); nothing here is redone there.
- **The codegen bins are 0006's codegen units** (0006 §3.4, D4), with the same
  rule: a pure, edit-stable function of content, independent of the shard count.

## 10. The cutover plan

**Where it runs.** On the owner's machine, which builds the toolchain and runs
every suite; each lane integrates only with `make build`, `make check`,
`make test`, `make test-idr` and `make test-mlir-tools` green there, and with
`tests/determinism` at 1, 2 and 8 threads. This machine checks only
`make typecheck` and `make check`.

**Lanes,** each with disjoint ownership:

| Lane | Owns | Work | Proof |
| --- | --- | --- | --- |
| L0, the baseline | `bench/profiles/`, `/tmp/f0/` | Run the old binary's defunctionalize on the round-16 module and record directive.lam4's op and key (§2.6); time-boxed timings of the old pipeline from the saved post-contify module; keep the module and the command that regenerates it | a committed record |
| L1, emission | `compiler/src/IdrisMLIR/Emit`, `Frontend/Translate` | Symbol-form closures and suspensions; names from content; binder identity (no `$world`, no hole sentinel); the in-place type fact; bytecode handoff; delete `Prof.idr` | corpus emits; every program's expected output unchanged |
| L2, total defunctionalization | `lib/Analysis/Labels*`, `lib/Transforms/Defunctionalize`, the flow interface in `include/idr/IR`, the closed-world verifier | §2's four changes, MLton's representation choices, per-function conversion, placement after deduplication; delete everything in §6 that §2 deletes | every former source of unknown has a fixture that now converts; the corpus and stage 0 pass the verifier; the solve under 10 s on stage 0; suites green |
| L3, the first-order optimizer | `lib/Transforms/{Simplify,Inline,Specialize}`, `lib/Analysis/Inline.cpp`, the summaries | The ready set, decisions with the caller cap, the inner pipeline once, the bounded local loop, specialization nodes, contification, summaries, dead values once; delete the rounds and everything in §6 that §4 deletes | suites green; stage 0's optimizer under the threshold below; determinism 1/2/8 |
| L4, the driver and options | `lib/Driver`, `Pipeline.cpp`, `Passes.td` options | Delete `--without`, `--dump-dir`, the toggles and `--demand-in-place`; structured refusals; budgets that stop optimizing | suites green; no pass option selects behaviour (a spec check) |
| L5, IR facts | `include/idr/IR`, `lib/IR` | `idr.stack` inherent; the stage read from types; identified types with bodies and the lookups they delete; `listElement`'s role; one canonicalization configuration | suites green; no discardable attribute carries a fact (a spec check) |
| L6, ports and upstream | `upstream/`, PINS.md, the ported Mojo files | EliminateDuplicateFunctions ported; 02, 16 and 22 no longer carried; the `Empty.cpp` and region-simplifier reports | `tests/upstream` green; `tests/spec/licenses` green |
| L7, code generation | `lib/Driver/Artifacts.cpp`, `lib/Target/Optimize.cpp`, `lib/Transforms/Pipeline.cpp`'s tail | §5's partitioning and S2 split codegen; tail calls and inline asm checked on both targets | executables byte-identical at 1, 2 and 8 threads; bench compile times recorded |
| L8, tests | `tests/` | Delete tests of deleted mechanisms (`tests/idr/obs/budget.mlir`, the do-block A/B lines); restate brittle fixtures as properties; add the totality fixtures and the determinism checks | the suites themselves |

**Order:** L0, then L5's identified types and L1 together (they meet at
emission), then L2, then L3, then L4 and L6, then L7, with L8 alongside each.
After the cutover: §5.4's split before O3, then whatever the new record names
next (the giant-function tail if the caller cap leaves one; the frontend's
140 s and 9.1 GB, 0008's ground; the LLVM tail once measurable, 0006 S2).

**Measurement** (*decision*): old binary against new binary, two commits, two
builds, under identical conditions on performance cores, from a named saved
module (the post-contify stage-0 module and the round-16 module), time-boxed,
with a progress remark per finished SCC batch so that a run reports progress
instead of silence. A behaviour-selecting pass option is never a measurement
instrument.

**Thresholds** (*decision*):
- the optimizer segment (deduplication through dead values) on the stage-0
  module under 600 s of wall, against the old rounds' more than 2,000 s
  unfinished;
- the label solve under 10 s on stage 0 (§2.8);
- no bench program's compile time regressing by more than 5%, nor its runtime
  by more than 2%;
- the corpus byte-identical where a lane claims it, the suite green,
  determinism at 1, 2 and 8 threads.

A stage that misses its threshold is reworked or reverted whole; it is never
kept beside the old form.

## 11. Decisions and open questions

**Decided by the owner** (2026-10-14):
- D1. Inlining becomes pure optimization; defunctionalization is total by
  analysis alone (§2).
- D2. No options, toggles, fallbacks or dual paths, anywhere, ever.
- D3. A hard cutover with no compatibility owed, planned completely here
  before any code.
- D4. Whole-program for invariants, types, quantities, lowering and memory
  management; a parallel baseline for code generation.
- D5. Churn is fine.
- D6. Code may be ported from Modular under proposal 0001's protocol.

**Design decisions taken here:**
- D7. Closed world is a verified invariant (no external `idr.func`, one public
  root), checked before defunctionalization. Reason: it removes the
  external and escaping sources of unknown (§2.2).
- D8. One flow interface, read by the label analysis and the slots alike, and
  enforced by the verifier. Reason: closure flow had two tables that disagreed.
- D9. A forced-state anchor keyed by the lazy value's type. Reason: it removes
  the evaluated-delay gap and the lazy-return refusal.
- D10. `LabelSet` has no unknown element; reaching one is an internal error.
- D11. Defunctionalization runs right after the closed-world check and
  deduplication, before the optimizer, MLton's order. Reason: every later pass
  is first-order, the call graph is complete, closure cases disappear (§2.7).
- D12. The label solve uses MLton's representation: first-order values carry
  no flow, hash-consed sets, union-find for mutable cells, difference
  propagation; under 10 s on stage 0.
- D13. The optimizer is one bottom-up ready set over call-graph SCCs, each
  function processed once after its callees are final, with a bounded local
  loop for calls its cleanup exposes. Reason: it deletes the round multiplier
  and the per-iteration cleanup together (§3.2, §3.4).
- D14. Inline decisions use MLton's per-function formula on the callee's final
  size, never inline within a recursive SCC, delete originals, and add a
  per-caller size cap. Reason: the rule is right, applied once; the cap bounds
  what single-call absorption builds.
- D15. Specialization requests are demand-driven nodes in the same ready set,
  named from their key. Reason: one scheduler, order-free names.
- D16. Interprocedural constants and effects are bottom-up SCC summaries
  through upstream's `visitExternalCall`; effects are computed once.
- D17. Budgets stop optimizing and never reject; `unsupported (compile-time
  budget)` is deleted.
- D18. Names are derived from content everywhere.
- D19. Facts live in types and inherent properties: `idr.stack` inherent, the
  stage read from types, the in-place promise a type fact.
- D20. Codegen units are size-balanced bins of SCCs grouped by top-level
  namespace, cut by content hash, their count from size, never from threads.
- D21. S2 first (whole-module O3, then split codegen), then the split before O3
  with whole-program facts as attributes on cross-unit declarations; no
  LLVM summary-based importer.
- D22. Measurement is by binary from a saved module, time-boxed and
  observable, on performance cores.
- D23. Upstream patches 02, 16 and 22 are no longer carried; their reports stay
  as submissions.
- D24. From Modular: rebuild the ready set, the inline driver, specialization
  nodes, the codegen baseline and the summaries on its design; port
  EliminateDuplicateFunctions; never AsyncRT, MCLinker or
  `PerThreadPassManagers`.

**Open questions, each with the default taken:**
1. **The per-caller size cap.** Default: the largest caller size on the corpus
   after the cutover's first run, times two, recorded in L3; the stage-0 run
   then confirms that no function exceeds it.
2. **The codegen bin size.** Default: the size at which per-unit overhead
   (context, target machine, pass setup) is under 5% of the unit's codegen time,
   measured at S2; until measured, *conjecture*, about 10,000 LLVM instructions
   per bin.
3. **`fits` across grades.** Default: labels are compared on the unrestricted
   function type and the slot's grade applies (§2.9 checks it per grade).
4. **The stage marker.** Default: the verifier reads the stage from the IR's
   types (owned grades only after idr-rc); if a stage cannot be read from types,
   it becomes an inherent property of an op the module must contain, never a
   discardable attribute.
5. **Identified types with bodies.** Default: `!idr.data` carries its
   constructors as an identified, mutable type (LLVM's identified-struct
   mechanism), landing with L1; the twenty module-scanning lookups and the
   dodging branches go in the same change.
6. **Concurrent `translateModuleToLLVMIR` on one `MLIRContext`.** Default:
   S2 translates units serially and parallelizes only LLVM codegen; parallel
   translation comes after a ThreadSanitizer run is clean (upstream-mlir-llvm §5).
7. **Polyvariance before defunctionalization** (MLton's optional precision pass,
   `xml/polyvariance.fun:433-466`, 2 rounds, `small = 30`, `product = 300`).
   Default: not built; taken only if L2's per-key counts show sets that the
   optimizer cannot shrink and that cost runtime.

## 12. Sources

- `sources/notes/compile-pipeline/mlton.md`, `codegen-partitioning.md`,
  `mojo.md`, `upstream-mlir-llvm.md`, `casework-audit.md` (2026-10-14,
  verbatim).
- `sources/code/mlton/` at `aa2fd1ad` (43 files; the 2026-10-14 addendum holds
  the driver, controls, pass lists, chunkify and code generators).
- `sources/code/modular/` at `9211931` (17 files and `LICENSE`).
- `sources/notes/sharded-compilation/whole-program-at-scale.md` and
  `deterministic-fixpoints.md`.
- `sources/papers/weeks-2006-mlton-whole-program`, `glek-2010-gcc-lto`,
  `johnson-2017-thinlto`, `hovgaard-2018-defunctionalisation` (Futhark's
  exact defunctionalization by typing rules, the alternative where branching
  is unacceptable: conditionals and loops may not return functions, arrays may
  not hold them).
- `bench/profiles/2026-10-14-f0-stage0.md`.
- The pinned LLVM and MLIR trees, `.toolchain/build/llvm-project/`.
