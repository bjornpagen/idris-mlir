# 0002: the cutover swarm

**Status:** launched and integrated, 2026-10-12. Every lane's work is in
the tree and committed, and it builds on arm64 macOS (4d5e7e8f). Its
first suites' failures are fixed and the gate has not run again since.
It is deleted when 0001's G1 qualifies it on the owner's machine.

The packet makes the compiler hold each thing it knows once, where MLIR
already has a name for it, and deletes the copy that held it before:

- **The pass layer is an MLIR project.** Headers and `.cpp` in upstream's
  layout, built with upstream's CMake, cached by ccache. The C++20
  module wrapper of MLIR, the quarantine profile and the two pins it
  caused go.
- **Facts have one home.** A function's facts are inherent to
  `idr.func` and a call's effects to `idr.call`; every other fact is an
  analysis under the pass manager. The thread-local scope chains, the
  atomics on the dialect, the pass instances that cache results and the
  string-read attributes go.
- **The function is the unit of work.** A rewrite of one body is a
  function pass under a nested pass manager, which MLIR runs in
  parallel. A module pass computes analyses, inserts, erases or retypes
  symbols, and rewrites one function at a time or nests that rewrite.
  The whole-module verify after every pass goes; each pass is verified
  at the level it ran.
- **The round takes MLton's shape** on upstream's composite pass: facts,
  then the analyses the function step reads, then local rewrites in
  parallel, then symbol changes, once per round.
- **The frontend emits what it decided.** No erased value, no newtype,
  no shim, functions at arity, keys as text attributes, readable quoted
  names, real locations, streamed to a file.
- **The dialect reads well.** Suggested value names, aliases for every
  data type, the `idr.` prefix elided under `idr.func`, binder names as
  SSA names, the handoff in declarative syntax where the generator can
  print the op's format.
- **Profiling is one layer**, through the pass manager's instrumentation,
  on a Tracy preset, with the compiler's allocations tracked behind
  their own option.

The evidence is `findings.md`, read at 25890d32. The declarations are
`contracts.md`. The work is `work-units.md`, `ownership.json` and
`dispatch/`. The launch is `orchestrator.md`. The review is `review.md`.

## Engagement contract

- **Mode: proposal.** Nothing here authorizes implementation. The owner
  says "launch".
- **Tree at authoring:** `main` at 25890d32, with
  `proposals/0001-get-back-on-track.md` untracked and
  `proposals/README.md` modified (the 0001 index entry). No toolchain is
  built on the authoring machine; nothing was run. Every anchor in
  `findings.md` was read at 25890d32. If HEAD has moved at launch, the
  coordinator diffs every cited file first (`orchestrator.md` step 1).
- **Compatibility: none owed** (owner, 2026-10-12). The handoff text,
  the dumps, every fixture, pass names, options and the module layout
  change at once. No user data exists. The runtime ABI does not change
  because nothing in `runtime/` changes.
- **Shared declarations:** the hubs in `contracts.md` C1, which the
  coordinator applies at dispatch and alone may edit: the ODS, the
  passes' TableGen, every `CMakeLists.txt`, the presets, the submodules
  and the lock file, `CS/Ids.idr`, `CS/Rule.idr`, the generated
  `CS/Dialect` and `CS/Syntax`, the `compiler/*.ipkg` files,
  `tests/spec`, PINS, README, AGENTS, HANDOFF, `proposals/`. At
  qualification the coordinator alone also writes `bench/README.md` and
  `bench/runs`.
- **Verification timing:** no lane builds or runs a test (common
  obligations). The tree is red mid-swarm by design: every `.cppm` is
  deleted and every `.cpp` is new while lanes write. The coordinator
  runs AGENTS.md's checks at integration, with repairs and reruns as a
  phase: `make check`, `make build`, `make test`, `make test-idr`,
  `make test-mlir-tools`, on arm64 macOS, then on x86_64 Linux.
- **Commit policy:** lanes do not commit. The coordinator commits to
  `main` at integration, in a few commits that each stage only this
  packet's paths, once the suites are green on arm64 macOS. x86_64
  Linux is recorded NotRun at that commit and run next (owner decision
  5).
- **Toolchain:** unchanged. The one pinned LLVM stays; no patch is
  added or removed, and no lane patches upstream (R44). The Tracy
  submodule is added at dispatch.
- **Deletions allowed:** everything under "The Elon pass" and C11. A
  test is deleted only when it tested a retired mechanism and nothing
  else.
- **Targets:** x86_64 Linux and arm64 macOS. Nothing here assumes x86,
  Linux, ELF or musl.

## The move

1. **Declare once, derive the rest.** The facts the passes keep in
   attributes read by string, in pass instances and in thread-local
   chains move to `idr.func`'s inherent attributes, to `idr.call`'s
   effects and to analyses the pass manager caches and invalidates
   (C1.2, C2). Each old copy is deleted in the lane that writes the new
   one.
2. **Make the function the unit of work.** A rewrite of one body is a
   function pass; every whole-program question is an analysis; a module
   pass inserts, erases, retypes or redirects symbols and runs its
   rewrite one function at a time or nested (C1.3, C2.0, C3). A nest
   reads only the module analyses the step before it computed (C2.0).
   The verifier follows: a function pass is checked on its function
   (C4).
3. **Emit what was decided.** Erasure, newtypes, saturated method calls,
   arity, keys and locations are the frontend's knowledge; it writes
   them, streamed to a file, and the C++ side stops recovering them
   (C6).
4. **Say it in MLIR's words.** Upstream's layout, build, inliner,
   composite pass, canonicalizer, conversion framework and assembly
   hooks replace ours where they fit (C1.1, C1.5, C2.4, C3, C7).
5. **Measure with one instrument.** Tracy through the pass manager, a
   preset away (C8).

**What becomes unrepresentable:**

- a function fact that a pass can drop without changing the op
  (F-fact-1, F-fact-2);
- a call whose effects must be found by looking its callee up
  (F-state-5);
- a value of quantity zero (F-hand-1);
- a symbol whose structure must be parsed from its name (F-hand-2,
  F-hand-3);
- a pass that holds IR-derived state across runs or publishes it
  through the dialect (F-state-1, F-state-2, F-state-3);
- a pipeline step whose analyses do not survive to the next (F-pass-5),
  and a function step that reads a module analysis nobody computed for
  its nest (F-pass-8);
- a handoff held whole in memory before it is written (F-hand-8);
- a C++ unit that imports MLIR through a module wrapper (F-build-1).

## The Elon pass

Deleted, not implemented:

| Requirement as practiced | Why it existed | Verdict |
|---|---|---|
| Every pass is a module pass | the first passes were, and nothing nested one | **Deleted.** A rewrite of one body is a function pass; a pass that inserts clones, writes signatures or plans over the module stays a module pass and rewrites per function (C1.3, R17 to R20). |
| The whole program is verified after every pass | the program's rules hung on the module's attribute | **Deleted.** Function rules on `idr.func`, in parallel; declaration rules in `verifySymbolUses`; module rules on the module (C4, R05, R13). |
| A pass hashes the module to learn whether it changed it | no change flag was kept | **Deleted.** `markAllAnalysesPreserved` from the pass's own knowledge; one fingerprint per round, upstream's (C2.0, C3.1). |
| Symbol tables and memos are published to worker threads through the dialect | module passes could not share an analysis | **Deleted.** Analyses; a nest reads what the step before it computed (C2.0, C2.1, R15). |
| Facts are discardable attributes, policed by a trait on every op | `func.func` has no place for them | **Deleted.** `idr.func`'s inherent attributes and `idr.call`'s effects; the dialect's discardable attributes are `program` and `stack` alone (C1.2, R04, R07). |
| A call's effects recomputed at every query, by lookup | no attribute carried them | **Deleted.** `idr.call` carries them; `idr-effects` writes them (C1.2, C2.2, R07). |
| A clone's key is two discardable attributes | the same | **Deleted.** `clone` inherent; a hole is its parameter's position (C1.2, R04, R29). |
| Twenty-five pass managers from text | the steps were strings for `--without` | **Deleted.** One typed manager, `idr-target` then the pipeline; `--without` by top-level step (C1.4, R21). |
| The upstream lowering passes on the whole module | they were top-level steps | **Deleted.** Nested per function (C1.4, R21). |
| The inliner's optimization of every component | upstream's default once a pipeline is installed | **Deleted.** Only a callable an iteration inlined into (C3.3, R22). |
| `idr-canonicalize` wraps canonicalize to count rewrites | the counts were statistics | **Deleted.** Upstream's pass; the loop's instrumentation reports the round's statistics, and `idr-expect` states properties (C3.2, R23). |
| A strongly-connected-components walk per graph, and a second DFS in the verifier | each graph grew its own | **Deleted.** One utility in `IdrSupport`; `TypeGraph::containsItself` (C2.1, R11). |
| C++20 modules wrapping every MLIR header | the C++ profile forbade MLIR's API | **Deleted.** An in-tree MLIR dialect (C1.1). |
| Hardening flags on the Release compiler | one profile for every build | **Deleted** from Release; a `hardened` preset (C1.5). |
| Tracy from a sibling checkout, always on, uninstrumented | a sampler was wanted once | **Deleted.** A pinned submodule, a preset, one instrumentation that adds nothing outside the profile build (C8, R39). |
| Erased parameters, fields and arguments as values | erasure was kept as a type | **Deleted.** No quantity zero in the dialect; an erased value Translate cannot drop is refused (C6.1, C10, R28). |
| `$<n>$` mangling in the handoff | symbols were assumed to be bare identifiers | **Deleted.** Quoted readable names; mangling once, in `idr-lower`'s phase 0 (C2.3, C6.3, R31). |
| The instance key printed into the symbol | no attribute carried it | **Deleted.** `#idr.instance`, text with no symbol use (C1.2, C6.3, R02). |
| Generic form in the handoff | the printer was generic by design | **Deleted** where the generator can print the op's format; the dumps are the readability target (C7.3, R33). |
| The handoff built as one string, then written | Emit returned the module's text | **Deleted.** Emit streams to a file, top-level op by top-level op (C6.7, R34). |
| A default region after a complete split, dropped by a pattern that scans | Idris's case trees carry one | **Deleted.** Translate drops it (C6.4, R42). |
| A second compilation of every program test for `--no-eval` | `idr-eval` existed | **Deleted.** One compilation (C9.2). |
| Case blocks named by Idris's global counter | the name came from `nameKey` | **Deleted.** `<parent>.case<k>`, by position in the parent (C6.3, R31). |
| Parametric data types (`bugs/idris-mlir-handoff-investigation.md` §3.12) | proposed from a dump | **Refuted.** Declarations stay monomorphic (owner decision 3); the structure is `instance`; readability is aliases (C10). |
| Bytecode for the handoff | 0001 C5 | **Deferred.** The driver reads `.mlirbc` already; nothing writes it; measured after the diet (C5). |
| Location aliases in the handoff | ranges and name locations lengthen the text | **Deferred.** A text format change follows the diet's measurement (C5). |
| Instrumenting the runtime | "the entire C++ codebase" | **Deferred.** The compiler alone; the runtime is linked into every program and is a later decision (C8.2). |
| A merged dataflow solve for the round | 0001 §5.3 | **Deferred.** Upstream's `sccp`, `remove-dead-values` and `int-range-optimizations` stay as module steps; `Returned` and `Identities` stay two analyses; a merge is measured after C4 lands (F-round-2, R43). |
| Upstream patches for the round's serial residue | the verifies after unchanged upstream passes, the inliner's first optimization | **Deferred.** No patch in this packet; the records of "Qualification" name each (R47). |
| Deleting `idr-accumulate` for LLVM's tail-recursion elimination | a conjecture | **Deferred.** Measured at integration (C10, O4). |

**What stays, and why:**

- **Every decision MLIR cannot take**: what to specialize and raise, how
  to defunctionalize, what to borrow, reuse and put on the stack, which
  self call becomes a loop or a destination write, which natural becomes
  a word, which guard is proved. Each is re-housed as an analysis and a
  rewrite, not rewritten.
- **The ODS**, its traits and interfaces, the DRR patterns, the
  generated Idris syntax: unchanged in meaning, extended by C1.2.
- **`!idr.q` as it is** (R03): every grade whose permission is plain
  prints by a spelling.
- **Two discardable attributes**, `idr.program` on the module and
  `idr.stack` on a cell (R04). `idr-stack` recomputes the mark on each
  run; lost before `idr-rc` it only sends a cell to the heap, and lost
  after it the owned-stage verifier refuses the function.
- **What is inlined**: the carried patch `inline-unreachable` keeps
  deciding a callee that ends in `ub.unreachable` (R22).
- **`Holds` stops at an array**, as today; a seam for another packet
  (R43).
- **`-mlir-timing`** as the always-on report beside Tracy.
- **The 400-line unit rule** and the ratchet.
- **The round's remarks** (`round N …`, `fixpoint: round N changed
  nothing`), which tests read by name.

## Rulings

The rulings of `contracts.md` C10 are decisions, not questions. In
addition:

- **The layout flip is each lane's, for its area.** A serial flip before
  dispatch would be a foundation wave; a flip after the lanes would
  touch every file twice. Every lane writes its area as `.cpp` and `.h`
  from the first minute and deletes its `.cppm`.
- **Every `CMakeLists.txt` under `FI` is the coordinator's** and is one
  of the lists of C1.1; an old area's list is deleted by the lane that
  deletes the area (C1.1 names each), but `IDR/Dialect` and
  `IDR/Ownership`, which the coordinator deletes.
- **Each header under `INC` is the lane's that `ownership.json` names
  for it**, the lane that writes its `.cpp`; the `.td` files and the
  `CMakeLists.txt` files under `INC` are the coordinator's.
- **`T/idr` is one lane**: 254 fixtures change in the same way, and two
  writers in one directory would conflict on every file.

The owner ruled on the lanes' escalations and the critics' review on
2026-10-12, with performance, concurrency and representation first.
Each ruling is folded into the contract sections it names and into the
dispatches of the lanes it revises. Nineteen proposals were rejected,
each with its reason.

| Ruling | Decision | Contract | Lanes revised |
|---|---|---|---|
| R01 | `idr.func`, `idr.call`, `idr.return` in the ODS: plain interfaces, the call's own effects, consumption by grade, `absorb` the one home of the totality loss | C1.2 | U01 to U05, U18, U20, U21 |
| R02 | The instance key is text: no symbol use, shared by clones | C1.2, C1.6, C6.3, C10 | U01, U04, U06, U08, U09, U15, U18 to U22 |
| R03 | `!idr.q` unchanged; type names through the grade; field names from the binders' `NameLoc`s | C1.2, C6.5, C7.1 | U01, U18, U20, U21 |
| R04 | The discardable attributes are `program` and `stack` | C1.2, C2.2, C4, C11 | U01, U02, U06, U08, U10, U13, U15, U20, U21 |
| R05 | Code MLIR calls without a table: no sibling function, bounded declaration scans, declaration rules in `verifySymbolUses` | C1.2, C2.0, C3.2 | U01, U02, U06, U17, U21 |
| R06 | `ForceAtCapture` and `ForceOfOneConstant` become `idr-inline`'s preparation | C1.1, C3.3 | U01, U05, U17, U21 |
| R07 | `idr.call` carries its effects; `idr-effects` writes them; `verifySymbolUses` checks them | C1.3, C2.2, C9.1 | U02, U03, U05 to U07, U15, U18, U20, U21 |
| R08 | One `consumes`, by the callee's parameter grade | C2.2 | U01, U02, U08 |
| R09 | The symbol helpers by name; users from `SymbolUserMap` | C1.1, C2.0 | U01, U03 to U13, U15 to U17 |
| R10 | Layout, include, header, link and build rules; who deletes an old list | C1.1, C1.5, C2.0, C9.3 | U01, U04 to U07, U09, U11, U12, U14 to U17, U20 |
| R11 | `TypeGraph` in `IdrIR`; one strongly-connected-components utility | C1.1, C2.1, C4 | U02 to U08, U13, U15 |
| R12 | Homes of `IDR/Graph`'s helpers that are not analyses | C1.1 | U03, U04, U08 to U13, U15 |
| R13 | The owned stage's vocabulary in `IdrIR`; the owned verify's cost | C1.1, C4 | U02, U08, U11, U15 |
| R14 | The analyses: one table, preservation obligations, parallel construction | C2.1 | U03 to U13, U15 |
| R15 | Nests preserve no module analysis; `idr-round-facts`; `idr-redirect` reads no sibling | C1.3, C2.0, C3.2, C3.3 | U04 to U06, U08 to U14, U21 |
| R16 | Never mutate while walking: patterns, the greedy driver, or a collected plan | C1.3, C2.0 | U06, U08, U09, U11 to U13, U16 |
| R17 | A pass run only inside a module pass is an unregistered wrapper | C1.3 | U08 to U12, U14, U21 |
| R18 | `idr-rc` in five steps with two nested function passes | C1.3, C1.4 | U08, U14, U21 |
| R19 | The tail passes' anchors | C1.3, C1.4 | U09, U14, U21, U22 |
| R20 | `idr-tail-calls`: a module plan, a rewrite nested over `llvm.func` | C1.3, C1.4 | U10, U14, U21 |
| R21 | The pipeline, the driver's manager, `--without` and the dumps | C1.4, C3, C5 | U14, U21, U22 |
| R22 | The inliner interface mirrors func's; the component pipeline only where something was inlined | C1.2, C3.3 | U02, U04, U05, U21 |
| R23 | The loop's instrumentation, added by the manager's owner, with the round's frame and plots | C3.1, C5, C8.1, C10 | U04, U14, U21, U23 |
| R24 | `Ranges` in `IdrAnalysis`; `Lengths` private to `IdrInBounds` | C1.1, C1.3, C2.1 | U11, U12, U15 |
| R25 | `Escapes` on the sparse backward base | C2.1 | U13 |
| R26 | Defunctionalization through dialect conversion, as it can be done | C2.4 | U07, U21 |
| R27 | The evaluated suspension | C1.2, C1.3, C2.4, C6.4 | U01, U07, U13, U19, U21 |
| R28 | The erased grade deleted; an undroppable erased position refused; the corpus records any loss | C0, C6.1 | U01, U06, U10, U13, U15, U17 to U19, U21, U22 |
| R29 | The clone fact's rules; a new function's first facts | C1.3, C2.2 | U02 to U06, U08, U09, U13, U15, U23 |
| R30 | The Idris side's shapes: one quantity enum, the registry's own multiplicity, `Term` records | C1.6, C6.1 | U18 to U20 |
| R31 | Names: the readable symbol, derived functions, mangling at the boundary, how tests name a function | C2.3, C6.3, C9.2 | U05, U06, U08 to U10, U13 to U15, U18, U19, U21, U22 |
| R32 | Locations: ranges and name locations, and every reader of a position | C6.5 | U02, U10, U15, U18 |
| R33 | The handoff's text: a generated head printer per dialect | C1.7, C7.3 | U18, U20 to U22 |
| R34 | Emit streams the handoff to a file | C6, C6.7 | U18, U19, U22 |
| R35 | Printer names, aliases as shortening, hook owners, registration | C1.1, C2.3, C5, C7.1, C7.2 | U01, U02, U14, U21 |
| R36 | `INC/Support/Actions.h`; U06 declares the two actions | C1.1 | U06, U14 |
| R37 | `Layouts`: `valid()`, the tag limit in `idr.data`'s verifier, the names it publishes | C1.2, C2.1 | U01, U02, U07, U08, U10, U13, U15, U16, U21 |
| R38 | Function passes' remarks through the diagnostic engine, in the determinism proof | C2.0, C9.2 | U11, U16, U22 |
| R39 | One profile instrumentation in every build; allocation tracking behind its own option | C1.4, C1.5, C5, C8.1, C8.2 | U04, U14, U23 |
| R40 | The text of `INC/Transforms/Passes.td` | C1.3 | U03 to U06, U08 to U11, U13 to U15 |
| R41 | Arity: a missing parameter is a closure | C6.4 | U18, U19 |
| R42 | The frontend emits no covered default; `DropCoveredDefault` goes | C6.4 | U17, U19, U21, U22 |
| R43 | Overstated claims and small corrections | C1.3, C2.5, C5 | U10 to U13 |
| R44 | What lanes confirm at the pin, and how a difference is handled | C0 | U01, U02, U05, U06, U08 to U11, U13, U14, U20 |
| R45 | Split files granted now, so no lane meets the 400-line rule without a unit | `ownership.json` | U01, U06, U07, U13 |
| R46 | The declarative printer checked against the generic form | C9.2 | U20, U22 |
| R47 | Qualification, stated so it can pass | "Qualification" | U22 |
| R48 | The documents: findings, ownership, README, work units, orchestrator, PINS, validator | this packet | U01 to U05, U09 to U11, U14, U18, U19, U22 |

## Owner decisions

Approved by the owner on 2026-10-12, with R01 to R48. The rulings cite
them as owner decisions 1 to 6.

1. **Call-site effects.** `idr.call` carries its effects, written by
   `idr-effects` and checked against its callee (R07).
2. **The erased grade is deleted**, and the corpus measures the loss:
   the programs newly refused for an erased value in a runtime position
   are listed by name and count (R28).
3. **Declarations stay monomorphic.** The instance's structure is
   `instance`; readability is names and aliases (C10).
4. **The dumps are the readability target**, and the handoff is
   declarative where the ODS gives a format the generator can print
   (R33).
5. **Commit when arm64 macOS is green.** x86_64 Linux is recorded
   NotRun at the commit and is the next thing run (R47).
6. **23 lanes at once when the environment allows.** Under a lower cap,
   the orchestrator says so with the number and starts the next lane as
   each returns (`orchestrator.md` step 2).

O1 to O4 have defaults so that lanes can start. One word vetoes one;
until then the defaults stay:

- **O1. Release without sanitizer traps** (C1.5). Default: yes. On a
  veto: `release` keeps UBSan with traps and `hardened` adds the rest;
  U14 and the coordinator change nothing else.
- **O2. The Tracy pin** (C1.5). Default: the current release tag at
  launch, recorded in `toolchain.lock.json`. On a veto naming a tag,
  that tag.
- **O3. Capture directory** `bench/profiles/` gitignored (C8.2).
  Default: yes. On a veto: profiles are written beside the compiled
  program and nothing is added under `bench/`.
- **O4. `idr-accumulate` measured, not deleted** (C10). Default: yes. On
  a veto ("delete"): U09 deletes it and U22 adapts the fixtures that
  name it; the measurement is skipped.

## The frontier: 23 lanes, disjoint writes, all start at dispatch

Every lane writes against `contracts.md` from the first minute. Where
the environment caps concurrency below 23, the orchestrator says so
with the number and starts the next lane, in the order U01 to U23, as
each returns.

| Lane | Outcome | Exclusive writes (roots as `ownership.json`) | Consumes |
|---|---|---|---|
| U01 | The dialect's core as `IdrIR`: ops, types, attrs, grades, folders' hooks, the symbol helpers by name over a `SymbolTable&`, table-less code bounded, result names, aliases, the evaluated delay's canonicalization and fold, the tag limit in `idr.data`'s verifier | the root `IDR/IR/*.cpp` files `ownership.json` lists (`OpsCon.cpp` and `OpsMatchSyntax.cpp` if a split needs them; not `TypeGraph.cpp`), `INC/IR/{IdrDialect,Grades,Ranges,Symbols}.h`; deletes `IDR/Dialect/*` but `Verify` and the pipeline registration, `IDR/Ops`, `IDR/Ranges`, `IDR/Sharing`, `IDR/Mlir.cppm`, `INC/Idr.h` | C1.1, C1.2, C2.0, C2.3, C7 |
| U02 | `idr.func`, `idr.call`, `idr.return`; the inliner interface mirroring func's; a call's effects checked against its callee; the function verifier (linearity, the owned stage, the clone fact); the module verifier reduced | `IDR/IR/Func`, `IDR/IR/Verify`, `INC/IR/{Func,Verify,Ownership}.h`; deletes `IDR/Verify`, `IDR/Dialect/Verify`, `IDR/Ownership/Verify.cppm` | C1.2, C3.3, C4 |
| U03 | `References`, `Effects`, `Holds` in `IdrAnalysis`; `TypeGraph` in `IdrIR`; one strongly-connected-components utility; `idr-effects` writes facts on functions and calls | `IDR/Analysis/{References,Effects,Holds}.cpp`, their headers, `IDR/IR/TypeGraph.cpp`, `INC/IR/TypeGraph.h`, `IDR/Support/Scc.cpp`, `INC/Support/Scc.h`, `IDR/Transforms/Effects`, `INC/Transforms/Effects.h`; deletes `IDR/Graph`, `IDR/Facts` | C1.1, C2.1, C2.2 |
| U04 | `idr-simplify` on the composite pass; the round with `idr-round-facts` before its function step; the loop's instrumentation (remarks, statistics, frame, plots); breakers and contify re-housed | `IDR/Transforms/Simplify`, `INC/Transforms/Simplify.h`; deletes `IDR/Simplify`, `IDR/Canonicalize`, two `Support` units | C2.0, C3, C5 |
| U05 | The force preparation; `idr-inline` through `mlir::Inliner`, its component pipeline only where an iteration inlined; `InlineDecisions` | `IDR/Transforms/Inline`, `INC/Transforms/Inline.h`, `IDR/Analysis/Inline.cpp`, `INC/Analysis/Inline.h`; deletes `IDR/Inline` | C2.1, C3.3 |
| U06 | `BindingTimes` and `CloneTable` analyses; `idr-specialize`; `idr-redirect` reading no sibling; the two actions | `IDR/Transforms/Specialize`, `IDR/Analysis/Specialize.cpp` (and `BindingTimes.cpp` if a split needs it), headers; deletes `IDR/Specialize`, two `Support` units | C1.3, C2.1, C2.2 |
| U07 | `Labels` analysis; defunctionalization as dialect conversion as R26 states it; the evaluated delay becomes the forced state | `IDR/Transforms/Defunctionalize`, `INC/Transforms/Defunctionalize.h`, `IDR/Analysis/Labels.cpp` (and `LabelSites.cpp` if a split needs it), `INC/Analysis/Labels.h`; deletes `IDR/Defunctionalize` | C2.4 |
| U08 | `Borrows`, `Reuses`, `Exclusivity`; `idr-rc` in five steps; `idr-rc-place` and `idr-rc-commit` per function | `IDR/Transforms/Ownership`, `IDR/Analysis/Ownership`, headers; deletes `IDR/Ownership`'s units but `Verify.cppm` | C1.3, C2.1, C4 |
| U09 | `idr-tail-loops` per function; `idr-accumulate`, `idr-trmc` and `idr-returned-arguments` at the module; the tail helpers in `IdrAnalysis` | `IDR/Transforms/Tail`, `INC/Transforms/Tail.h`, `IDR/Analysis/Tail.cpp`, `INC/Analysis/Tail.h`; deletes `IDR/Tail` | C1.3, C1.4, C2.1 |
| U10 | `idr-lower` with phase 0 and its mangling, `idr-entry`; `idr-tail-calls` on the module with its rewrite nested over `llvm.func`; `Layouts` analysis; the target | `IDR/Conversion`, `INC/Conversion`, `IDR/IR/Layout`, `INC/IR/Layout.h`, `IDR/Target/*.cpp`, `INC/Target/Target.h`; deletes `IDR/Lower`, `IDR/Layout`, `IDR/Target/*.cppm`, `IDR/Target/Pass.cc` | C1.3, C2.3, C2.5 |
| U11 | Narrowing as `IdrNarrow`: the seeded `Ranges` analysis, module versioning, per-function word rewrite, per-function lanes | `IDR/Transforms/Narrow`, `INC/Transforms/Narrow.h`, `IDR/Analysis/Ranges.cpp`, `INC/Analysis/Ranges.h`; deletes `IDR/Narrow` | C1.3, C2.1 |
| U12 | `Lengths` private to `IdrInBounds` over `Ranges`; `idr-in-bounds` proving per function | `IDR/Transforms/InBounds`, `INC/Transforms/InBounds.h`; deletes `IDR/InBounds` | C1.3, C2.1 |
| U13 | `Escapes`, `Identities`; `idr-stack`, `idr-identity`, `idr-isolate`, `idr-demand` | `IDR/Transforms/{Stack,Identity,Isolate,Demand}`, `IDR/Analysis/{Escapes,Identities}.cpp` (and the three split units if needed), their headers, the four area headers; deletes the four old dirs | C1.3, C2.1 |
| U14 | One typed `PassManager`: `idr-target`, then the pipeline, the upstream lowering passes nested per function; `--without` by top-level step, `--dump-dir` as instrumentation; the driver and tools as `.cpp`; `idris-mlir-opt` on `MlirOptMain` | `IDR/Driver`, `INC/Driver`, `IDR/Transforms/Pipeline.cpp`, `INC/Transforms/Pipeline.h`, `IDR/Support/Actions.cpp`, `INC/Support/Actions.h`, `FI/tools/{idris-mlir,idris-mlir-opt,idris-mlir-reduce}.cc`; deletes the registration units and three `Support` units | C1.4, C5, C8.1 |
| U15 | `idr-expect` on the layout and `idr.func` | `IDR/Transforms/Expect`, `INC/Transforms/Expect.h`; deletes `IDR/Expect` | C1.1, C2.2 |
| U16 | Folders in `IdrIR`; `idr-vectorize` | `IDR/IR/Fold`, `INC/IR/Fold.h`, `IDR/Transforms/Vectorize`, `INC/Transforms/Vectorize.h`; deletes `IDR/Fold`, `IDR/Vectorize` | C1.1 |
| U17 | The canonicalization patterns in `IdrIR`, audited against upstream's; `DropCoveredDefault` deleted | `IDR/IR/Canon`, `INC/IR/Canon.h`; deletes `IDR/Canon` | C1.1, C2.0, C3.2 |
| U18 | Emit: no erased values, `idr.func`, readable quoted names, locations with names, declarative syntax through the generated head printers, streamed to a file | `CS/Emit`, `CS/Emit.idr`, `CS/MLIR.idr`, `CS/MLIR`, `CS/Types.idr`, `CS/Term.idr`, `CS/Loc.idr`, `CS/Facts.idr`, `CS/Graph.idr` | C1.6, C1.7, C6, C7.3 |
| U19 | Translate: saturated method calls, arity with a closure per missing parameter, newtypes, alpha-normalized text keys, case blocks by position, covered defaults dropped, the erased-position refusal | `CS/Frontend/*`, `CS/Registry*` | C1.6, C6.1 to C6.4 |
| U20 | The generator emits a head printer per dialect and the new ops' builders; the syntax samples in both forms | `FI/tools/idris-mlir-tblgen.cc`, `tools/dialects.sh`, `CS/SyntaxSamples.idr` | C1.7, C7.3 |
| U21 | Every dialect fixture on `idr.func`; `T/idr/func`, `T/idr/asm` | `T/idr` | C9.1 |
| U22 | One compilation per program; `handoff-readable`, `handoff-round-trip`, `dialect-syntax` in both forms; the timing record as JSON; remarks in the determinism proof; `expected` files | `T/*` but `T/idr`, `T/spec`, `T/README.md` | C9.2 |
| U23 | Tracy as a pinned preset; one instrumentation in every build; allocation tracking behind its own option; `tools/profile.sh` | `INC/Support/Profile*.h`, `IDR/Support/Profile*.cpp`, `tools/profile.sh`, `bench/profiles`; deletes `IDR/TracySampling.h` | C8 |
| coordinator | The hubs (C1), the spec rules (C9.3), PINS, README, AGENTS, HANDOFF, `bench/README.md`, integration, qualification | `ownership.json` "coordinator" | all |

No two rows intersect by prefix, and `validate.sh` proves it. The one
long serialization is the first `make build` of the new layout at
integration, where the coordinator fills every `CMakeLists.txt`.

## Finding map

Every finding has exactly one accountable lane. Supporting producers and
consumers are named in the lane's dispatch.

| Finding | Disposition | Owner |
|---|---|---|
| F-pass-1 | nested `idr.func` and `func.func` managers in one typed pipeline; module passes only where clones or plans need the module | U14 |
| F-pass-2 | function rules on `idr.func`'s verifier; module rules on the module | U02 |
| F-pass-3 | one numbering per body | U02 |
| F-pass-4 | change flags; one fingerprint per round | U04 |
| F-pass-5 | one `PassManager`, constructors, nested managers | U14 |
| F-pass-6 | the inliner's component pipeline runs `canonicalize,cse` where an iteration inlined | U05 |
| F-pass-7 | `References` once per round, shared | U03 |
| F-pass-8 | `idr-round-facts` before the round's function step; no analysis held across `runPipeline` | U04 |
| F-pass-9 | the component pipeline only on a callable an iteration inlined into | U05 |
| F-pass-10 | the five upstream lowering passes under `func.func` nests | U14 |
| F-pass-11 | two module passes that rewrite per function; `Returned` with a nested rewrite | U09 |
| F-pass-12 | `TailCallPlan` and a rewrite nested over `llvm.func` | U10 |
| F-pass-13 | the inliner interface mirrors func's, both terminator forms | U02 |
| F-state-1 | `SymbolScope` deleted; `getAnalysis<SymbolTable>()` | U01 |
| F-state-2 | `HoldMemo` deleted; `Holds` analysis | U01 |
| F-state-3 | `Effects` analysis; `idr-effects` writes facts | U03 |
| F-state-4 | the analyses of C2.1 | U03 |
| F-state-5 | `idr.call`'s effects, written by `idr-effects`, read without a lookup | U03 |
| F-state-6 | declaration rules in `verifySymbolUses`, bounded scans, consumption by grade | U01 |
| F-fact-1 | `idr.func` with inherent facts | U02 |
| F-fact-2 | `Idr_KnownAttributes` and `verifyDiscardableAttrs` deleted; `program` and `stack` the only discardable attributes | U02 |
| F-fact-3 | `clone` inherent; `CloneTable` analysis | U06 |
| F-build-1 | the layout and build of C1.1 | U14 |
| F-build-2 | ccache on `make build` | U14 |
| F-build-3 | the `hardened` preset | U14 |
| F-build-4 | Tracy pinned, a preset, one instrumentation in every build | U23 |
| F-hand-1 | no quantity zero; an undroppable erased position refused | U18 |
| F-hand-2 | quoted names; mangling in `idr-lower`'s phase 0 | U10 |
| F-hand-3 | `#idr.instance`, text only | U19 |
| F-hand-4 | declarative syntax where the generator prints the op's format | U18 |
| F-hand-5 | `FileLineColRange` and `NameLoc` | U18 |
| F-hand-6 | saturated method calls, arity, newtypes; the evaluated suspension of the dialect (C2.4) | U19 |
| F-hand-7 | Translate drops a covered default; `DropCoveredDefault` goes | U19 |
| F-hand-8 | Emit streams to a handle | U18 |
| F-asm-1 | result names, type names, aliases | U01 |
| F-asm-2 | `instance` on `idr.data`; aliases | U01 |
| F-round-1 | the round of C3.2 on the composite pass | U04 |
| F-round-2 | `Identities` an analysis; the merge deferred and measured | U13 |
| F-round-3 | upstream `canonicalize` | U04 |
| F-test-1 | every fixture on `idr.func` | U21 |
| F-test-2 | the two programs within their limits at integration | U22 |
| F-test-3 | one compilation per program | U22 |
| F-test-4 | the timing report read as JSON, with the round count | U22 |
| F-test-5 | `threads-*` compare the function passes' remarks | U22 |

## Retired mechanisms

The validator refuses these names outside a Delete section. The names
R04 keeps (the dialect's `discardableAttrs`, now `program` and `stack`)
are not retired.

- retired: SymbolScope
- retired: HoldMemo
- retired: SymbolsHeld
- retired: holdsSymbols
- retired: publishedScopes
- retired: publishedMemos
- retired: PipelineStatistics
- retired: OpenRound
- retired: CloseRound
- retired: pipelineSteps
- retired: Idr_KnownAttributes
- retired: verifyDiscardableAttrs
- retired: Idr_ErasedAttr
- retired: !idr.erased
- retired: #idr.erased
- retired: ErasedT
- retired: erasedValue
- retired: Mlir.cppm
- retired: export module
- retired: import idr.
- retired: IDRIS_MLIR_TRACY_DIR
- retired: TracySampling.h
- retired: idr-canonicalize
- retired: $40$
- retired: stackMark

## Qualification

The coordinator does this after integration.

1. **The suites.** `make check`, `make build` (the `dev` preset, then
   `release`, `hardened` and `profile` configure and build), `make
   test`, `make test-idr`, `make test-mlir-tools`, all green on arm64
   macOS. Then the same on x86_64 Linux. x86_64 Linux is recorded
   NotRun at commit and run next (owner decision 5). A target that has
   not run them is NotRun, never green.
2. **Sensitivity.** Each new discriminator (C9) fails at 25890d32 with
   the same test files, run once: `T/idr/func/*`, `T/idr/asm/*`,
   `T/compiler/handoff-readable`, `T/compiler/handoff-round-trip`,
   `T/compiler/dialect-syntax`. The two set-aside programs fail at
   25890d32 by their time limit and pass after.
3. **Measurements the packet owes**, each recorded as a number against
   its record:
   - **the compile-time record.** `T/compile-times.sh` reads the timing
     report as JSON (`-mlir-output-format=json`) and records, per
     compilation, parse, `idr-simplify` with its round count, the
     `VerifierPass` sum, the analyses' sum, LLVM and the rest.
     `--against` compares each column with a record the same script
     takes of 25890d32's build on the same machine, and lists the
     programs whose round count grew; the total and the ten slowest are
     recorded. A program over twice its earlier time is a bug of ours,
     fixed before qualification;
   - **the rounds**: the round count per program from the fixpoint
     remark, its distribution and the ten highest;
   - **the analyses** (`-mlir-timing` in tree mode on
     `every-interfaces-export`): no `(A)` row of an analysis appears
     twice between two consecutive steps that both preserve it. Per
     round, `(A) References` appears under `idr-effects`, `idr-inline`
     and `idr-specialize` and nowhere else, `(A) Effects` under
     `idr-effects` only, `(A) Identities` under `idr-round-facts` only,
     `(A) CloneTable` and `(A) BindingTimes` under `idr-round-facts` and
     `idr-specialize` only, and no `(A)` row appears under a function
     pass. Recorded with User against Wall time under the pool;
   - **the verifier**: the `VerifierPass` rows' share per round and
     after `idr-rc`, under the pool and with one thread. If the rows
     after `idr-rc` dominate, the owner's next step is the
     declaration-dependent half of the owned walk as `idr.func`'s
     `verifySymbolUses` (R13);
   - **the serial residue per round**: `idr-simplify`'s own time minus
     its children, the `VerifierPass` rows' Wall against User, and
     `(A) CallGraph`. Each above a tenth of the round is named as a seam
     with its upstream plan;
   - the `Canonicalizer` and `CSE` rows under `idr-inline`;
   - `int-range-optimizations` nested under `idr.func` against its
     module placement, by round counts and the suite's expected files;
     the module placement stays the default unless nothing changes;
   - `T/determinism/threads-*` byte-identical, the remarks of
     `idr-vectorize` and `idr-narrow-lanes` included, and the wall time
     of `idr-pipeline` under the pool against one thread on
     `programs/data/rbtree` and `programs/data/shapes`;
   - **memory**: the peak RSS of stage 0 (the frontend) and of
     `idris-mlir` on `every-interfaces-export`;
   - **the stage-0 dump** at 25890d32 (`build/self/keep/front.mlir`,
     kept from the last self-host attempt) against the dump the new
     frontend writes: functions (58,305 before), operations and bytes;
   - **the corpus**: the programs newly refused for an erased value in a
     runtime position, by name and count (R28);
   - `bench/run.sh` on arm64 against
     `bench/runs/2026-10-07-f5a4dff9-darwin-arm64` by ratio to C: no
     program worse beyond the spread, or bisected; the `idr-accumulate`
     measurement of O4 recorded in `bench/README.md`;
   - one Tracy capture of `every-interfaces-export` saved under
     `bench/profiles/` and its path recorded in HANDOFF.md;
   - the size of `foreign/idr/lib` in lines before and after.

   Upstream patches that would remove the whole-module verifies after
   unchanged upstream passes, or the inliner's first optimization, are
   later work, named from these records.
4. **Docs.** PINS.md loses `mlir-cxx-api`, `zones-on-demand` and
   `clang-module-layout-forward-declaration` and gains the Tracy pin;
   `simplify-structural-fixpoint` names its site
   `foreign/idr/lib/Transforms/Simplify/Simplify.cpp` and says a pass
   instrumentation counts the rounds and emits the remarks and the
   round's statistics (R23); `inline-unreachable` stays. AGENTS.md's C++
   sentence changes as 0001 §10 says; README.md's Setup says `make
   build` is cached; HANDOFF.md records the state. Then this packet's
   status becomes "accepted" or "accepted in part", and 0001's stages
   C1 to C4 and H1 to H2 are marked done or named as what remains.

## Documents

- [contracts.md](contracts.md): every shared declaration, with the
  rulings folded in.
- [findings.md](findings.md): every finding, with its evidence.
- [work-units.md](work-units.md): U01 to U23, and the coordinator's own
  work.
- [ownership.json](ownership.json): exclusive write sets and mandatory
  findings.
- `dispatch/U??-*.md`: assembled from [dispatch/parts](dispatch/parts)
  by [dispatch/assemble.sh](dispatch/assemble.sh), with
  [the common obligations](dispatch/parts/common-obligations.md) and
  [the binding rules](dispatch/parts/binding-rules.md);
  [dispatch/parts/TEMPLATE.md](dispatch/parts/TEMPLATE.md) says how a
  part is written.
- [orchestrator.md](orchestrator.md): the launch instruction.
- [review.md](review.md): the adversarial review and the table of
  disagreements.
- [validate.sh](validate.sh): the document checks. Its numbers are
  below.

## Validation

`sh proposals/0002-cutover-swarm/validate.sh`:

```json
(filled in by the coordinator after the last edit)
```
