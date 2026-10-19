<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0002: sound passes, typed identities, good tests or none

A swarm wave of cleanup and refactoring through the whole pipeline, aimed
first at the soundness of the C++ optimizations. Every pass's contract is
checked at the pass; every optional transform is skippable, so "skipping it
changes nothing" can be checked; a function's facts are related to its body.
The Idris side drops the strings that stand for things and finishes its
totality. Every brittle test is deleted; the tests that remain or are written
stand on one small shared machinery, built from libraries the toolchain
already pins.

This file is the architecture. The work units are `parts/lanes/*.md`, the
dispatches `dispatch/*.md` (assembled from `parts/` by `assemble.py`, never
edited by hand), the ownership `ownership.json`, the orchestrator's prompt
`orchestrator.md`, the check `validate.py`.

## 0. Engagement contract

- **Checkout:** `/Users/bjorn/Documents/idris-mlir`, branch `main`, HEAD
  `47f9705915c834e4a1531caac3464549a8824bfc` (2026-10-15T19:29Z), clean but
  for this folder. 0001-total is integrated there, typecheck only; the owner's
  first build since c7aa7b62 has not run.
- **Dispatch is authorized** (the owner, 2026-10-15: "ultracode. rip it. i
  trust your judgement"), with the owner's rulings of §8 taken by the
  coordinator on the owner's delegation, and the owner's representation-first
  guideline (`parts/representation.md`) carried verbatim, first, in every
  dispatch.
- **The owner's choices, binding:** breaking changes to tests are allowed and
  wanted (brittle tests are deleted, §2); no compatibility for test formats;
  the two targets of AGENTS.md; on this machine anything may be built and run
  but the LLVM project itself (so `make typecheck`, `make check`,
  `tools/check-units.py`, the fork and the frontend on the stock host, Idris
  run on Chez, the runtime and C property programs by the host's clang; never
  `make build`, `make test*` or `make self`, which need the built LLVM), and
  the owner builds and runs the suites after integration; one integration commit per wave, by the coordinator, pushed
  when green; lanes never commit.
- **Concurrent design documents:** `proposals/0001-total/README.md` §5 (what
  remains; this wave takes items 6, 8, 9 and part of 4) and
  `proposals/0006-toolchain-bump.md` (not touched; the bump follows
  this wave or precedes it, the owner's order).

## 1. Intent and invariants

Intent: every optimization is shown sound by a check that runs where the
optimization runs, and every test in the tree earns its place.

- **I1. A pass's contract holds at the pass.** After every pass: quantities
  and linear types kept, effects never widened, no crash site added, folding
  facts balanced, and the structural verifier, which already runs. A failure
  names the pass.
- **I2. Optimization is optional.** Every transform a pass of role
  `optimization` performs is one MLIR action; skipping any one of them leaves
  a valid module whose behaviour is unchanged.
- **I3. A fact is related to what it states.** A function's declared
  `effects` cover its body's effects; `total` and `no_inline` come only from
  the places this packet names.
- **I4. One verdict rule.** Internal wins over refused wins over accepted, in
  the driver and the frontend alike.
- **I5. A string is a printed form.** Inside the compiler a thing has a typed
  identity; it becomes text where it is printed or handed to MLIR as a symbol.
- **I6. A test asserts its contract and nothing more**, on the shared
  machinery; a test that cannot is deleted.

## 2. Rules (in addition to AGENTS.md)

- **Brittle tests are deleted, not restated** (the owner's hard constraint).
  A test whose assertion is stronger than its contract (an op sequence, an
  SSA name, a copy's hashed name, an order the contract leaves open, a
  snapshot nobody reviewed) is deleted; a brittle RUN line or check in an
  otherwise good test is deleted from it. Nothing is transliterated into a
  property to keep a test alive.
- **Proof before contract before generated test.** Make a wrong state
  unrepresentable where the types can; prove (Idris) or check exhaustively in
  a small box (every input up to a size or width) where the property allows;
  state a relation between a pass's input and output as a checked contract;
  generate tests for what is left.
- **Two hosts, forever** (the owner's rule). The frontend (`compiler/src`), the
  fork, `libs/` and the Idris test machinery stay buildable by the stock Idris
  on Chez and by idris-mlir itself (`make self`), always. Every Idris change in
  this wave stays inside the subset idris-mlir compiles: no construct it
  refuses (escape hatches, `%foreign`, megamorphic recursion), no feature only
  one host has. Linear (quantity 1) features are used where they help: they
  mean the same on both hosts, and idris-mlir optimizes them better (in-place
  update, no counting). Facts a lane must respect: idris-mlir compiles with
  `--no-prelude`, so every module imports `Prelude` explicitly; `libs/`
  compiles under both hosts, but a `libs/` `%extern` is a runtime primitive
  whose one meaning is `runtime/`'s, so a program that reaches one runs under
  idris-mlir only, and no code the stock host runs (the runner, Gen, the
  frontend) reaches one. **No escape hatch in a user module**: idris-mlir
  refuses `assert_total` in the frontend's own modules (`IdrisMLIR.*` is the
  project's, `Registry/Libraries.idr` `moduleOrigin Project = User`), so the
  frontend's two trust points move out of them (owner ruling R4, §8): the
  `Host` record and its one `assert_total` move into the fork, which is
  Idris's compiler and a trusted library (`Library Compiler`), as
  `compiler/idris/src/Idris/Host.idr` (lane I); the dictionary passes are
  proved finite (lane Q, outcome A) or `covering`, never asserted (outcome
  B, the coverage-checked admission both hosts accept, with the `covering`
  chain to `main` named in `tools/policies.txt`).
- **Library first.** §5's table names the library that owns each mechanism.
  A lane that would write a mechanism the table assigns to a library uses the
  library.
- **Idris first** for the test machinery that is not a library's (§5); shell
  stays `run` glue; C++ tests only where the thing under test is C++ or C.
- **No outside oracle** (AGENTS.md). Oracles are self-consistency relations,
  the verifier and the contracts, and the runtime's documented meaning stated
  as a property or a small model in the harness (Sem's precedent, owner
  decision O4). A test never reimplements the runtime.
- **Encode the harness's invariants, not the system's expected behaviour**: a
  generator's types make its inputs valid; what the compiler should do with
  them is an oracle, never a type of the generator. Named invalid cases (each
  construct outside the subset, each documented crash) are first-class cases.

## 3. Findings

Each finding has one owning lane (`ownership.json`); supporting producers and
consumers are named in the lane's dispatch. Evidence is source observation at
HEAD above unless marked otherwise; nothing here was executed.

| ID | Finding (evidence) | Counterexample | Selected correction | Lane |
|---|---|---|---|---|
| F01 | Between passes only the structural verifier runs; quantities-kept is checked only on e2e compilations, after each dumped step (`harness/lib/properties.sh:13-56`), never on a fixture and never naming the pass at the moment it runs | a pass that drops a `!idr.lin` grade on one value passes `make test-idr` unless a fixture names it | `PassInstrumentation` contracts (§4.1) in `idris-mlir-opt --idr-contracts` | K1 |
| F02 | A function's `effects`, `total`, `no_inline` are never related to its body (`lib/IR/Func/Func.cpp:105-114`) | `idr.func @f() attributes {effects = none}` whose body has `idr.io.put_str` verifies, and idr-pure-calls may erase a call to it | the program verifier checks declared effects cover the body's; `total`/`no_inline` provenance fixed (§4.3) | F |
| F03 | Three transforms are MLIR actions (`include/idr/Support/Actions.h`); the rest of the optional transforms cannot be skipped, so I2 is unchecked | a wrong inlining cannot be bisected to the one inline that caused it | every optional transform of an `optimization` pass performs through an action (§4.2) | K3 |
| F04 | idr-optimize's own transforms (node turns, its inner steps) are partly actions; its inner canonicalizer's `not-converged` and CSE counts are lost (`include/idr/Transforms/Optimize.h:233-239`) | a spent canonicalization budget inside idr-optimize is invisible | `InnerCounts` gains them; idr-optimize's transforms are actions | K2 |
| F05 | Pass roles are not data; the tests cannot derive "drop or skip an optimization" relations | — | `IdrPass<arg, anchor, role>` in `Passes.td`, `-gen-pass-roles` (§4.2) | K2 |
| F06 | `ConOp::verify` accepts an owned field value only when `view(value) == expected` (`lib/IR/OpsCon.cpp:146-150`), but `view` now returns the borrow grade (`lib/IR/Grades.cpp:86-90`) while bodies declare fields plain | an owned `!idr.str` stored into a plain `!idr.str` field is refused (`tests/idr/ownership/consumed-effects.mlir:20-30`, source observation) | compare against the field type at the value's own grade, the one rule held in `Grades.h` | F |
| F07 | The reducer has no idr reduction patterns and does not run on the reserved stack (`tools/idris-mlir-reduce.cpp`, PINS `mlir-recursion`) | reducing a failing module ends with every op inside regions kept (`tests/idr/verify/reduce-regions.mlir`) | `DialectReductionPatternInterface` for idr; the reducer on the reserved stack | F |
| F08 | The driver ranks a refusal above an internal error (`lib/Driver/Run.cpp:73,111,238`); the frontend the reverse (`compiler/src/IdrisMLIR/Frontend/Driver.idr:216-223`) | a program refused by one site and hitting an internal error at another exits 3 from the driver | I4 in both, and `--report` (§4.4); I writes the frontend's half against §4.4 | G |
| F09 | `idris-mlir` takes only handoff-stage modules (`lib/Driver/Run.cpp:203-215`), so an `idris-mlir-opt` experiment cannot reach the real backend | a skipped-action module cannot be linked and run | `idris-mlir` accepts an LLVM-dialect module and runs only its LLVM half | G |
| F10 | Arithmetic a rewrite rests on is checked by no exhaustive box (narrowing transfer rules, word-narrowing ranges, the tagged small-big identities) | — | googletest programs exhausting each rule at a reduced width (§4.5) | B |
| F11 | Strings stand for things (0001-total §5 item 8): `Request`'s `base`, `owner`, `chooser`; `TS.symbols`, the loops table; Recursion's Tarjan tables; `ConId.name` (`compiler/src/IdrisMLIR/Ids.idr:30-34`); Emit's `keys`, `names`; Bytecode's numbering | two definitions whose printed names collide would share a table row (`TS.symbols` is today the guard that detects exactly that, `Keys.idr:806-810`: it stays, as a check of the printed symbol) | typed identities (§4.6) | I |
| F12 | The translation of applications is `covering` (`Translate/Terms.idr`, `Programs.idr`, `Cases.idr`; `tools/policies.txt`) | — | the spine and the head evaluation by 0001-total's ruling | T |
| F13 | The dictionary passes rest on one `assert_total` (`Frontend/Finite.idr`, `translateFrom`) | — | proved over F11's typed field identity, or the trust kept exactly as now and the gap stated | Q |
| F14 | The `scalar_end` chain is dead (`prim__scalarEnd` has no caller): `IdrStringOps.td`, `OpsStrings.cpp`, `Fold/Strings.cpp`, `runtime/Strings/Scalars.cpp`, `Emit/Operations.idr`; `libs/mlir-linear`'s iterator computes a UTF-8 width in Idris. Other lanes' files name it too: `runtime/idris_rt.h:460` and `tests/runtime-api/api.c:406` (R3), `tests/fold-string-offsets/fold-string-offsets.mlir` and `tests/lower-llvm-facts/lower-llvm-facts.mlir:36,67` (X1): each of those lanes deletes its mention, and P keeps the definition in `Scalars.cpp` until the coordinator's integration check shows none remains | — | the registry, ODS and runtime audited as one list; dead and duplicated primitives deleted across all three | P |
| F15 | Three copies of the integer bounds table (`harness/Fuzz.idr:83`, `Sem.idr:66`, `TwoLevels.idr:59`); Fuzz's `Expr` is untyped (`Fuzz.idr:95`), its weights accidental (`TInt` listed twice), no swarm, no shrinking, one LCG threaded through all cases; Sem's 72 directories are unchecked against `Sem.tests`; nothing checks the `d` lines are folded | a seventy-third chunk would silently go unrun | one primitive table and `Gen` (§4.7) | N |
| F16 | `runtime-api/expected-operations` (3,136 lines) and `double-print/expected-doubles` (176,000 lines) are unreviewed snapshots of the runtime's own output | a wrong rounding recorded once is accepted forever | both deleted (R2 deletes `expected-doubles`, R3 `expected-operations`, in their own files); property programs per family (§4.8): R1 bigs and integer text, R2 doubles, UTF-8 and strings | R1 |
| F17 | No runtime test builds a wide cell, frees an even-group cell or calls `idris_rt_caf_release`; `runtime-start` freezes a message that names no feature because it requires bit 63, which no feature owns (`start.c:44`, `expected:20`; `runtime/Start/Entry.cpp:67-80` already prints each missing feature's name); the IO buffer size is a fixed `constexpr 4096` (`runtime/Io/Io.h:23`) | the even-group free crashed past every test (0001-total §4.3) | model-based counting and array tests; the message names the bit; the buffer size overridable in a test build | R3 |
| F18 | 123 dialect fixtures match a transformed module with FileCheck (op order, SSA names, copy names embedding a hash); the dialect harness never round-trips its inputs | `#idr.con` syntax drift broke 100 fixtures that checked nothing else | deleted (§2); `--verify-roundtrip` in the harness | X1 |
| F19 | 24 program `mlir.check` files match op sequences; reject `message:` headers pin how instance keys render; `bench/report` counts `<rect>`; `io/system-info` writes into its fixture; 12 of 29 rules have no reject fixture; `profile_accept` skips the universal checks | — | deleted or fixed (§2); a reject fixture per rule, generated from the registry for the out-of-language entries | X2 |
| F20 | Specs transcribe their findings (`no-fuel`, `dialects-current`, `runtime-prepared`, `prelude-coverage`, `licenses`); grep specs have no non-vacuity witness; 318 transcripts repeat the same universal lines; the thread count is a hidden input (`tools/compile.sh:42`) | adding one universal check rewrites 318 files | specs state properties; one universal line; determinism over {1,3,5,13} threads and two processes | X3 |
| F22 | The small integer range is defined twice: `runtime/Big/Big.h:22-23` and `foreign/idr/include/idr/IR/Ranges.h:23-24` | the two drift and the compiler narrows a value the runtime holds large | the runtime's header exports the bounds (R3 adds `IDRIS_RT_SMALL_MIN`/`IDRIS_RT_SMALL_MAX` to `runtime/idris_rt.h`); `Ranges.h` uses them and its copy goes | F |
| F21 | 69 of 82 idr-expect properties have no fixture where they fail; `tests/expect-structured-loops/expect-structured-loops.mlir` is stale against `StructureLoops/Forms.cpp:127-129` | a property that holds of every module | each gets a failing fixture or is deleted (the five K1 calls and `folds-balanced` stay); `folded=@f` added for N's fold check | E |

## 4. Selected representations

### 4.1 Contracts (K1)

MLIR's `PassInstrumentation` (`mlir/include/mlir/Pass/PassInstrumentation.h`)
is the mechanism; `idris-mlir-opt` already installs its pass manager through
`MlirOptMainConfig::setPassPipelineSetupFn` (`tools/idris-mlir-opt.cpp:67`).
`--idr-contracts` (a `cl::opt` of `idris-mlir-opt` only, never `idris-mlir`'s)
adds `idr::ContractInstrumentation` (`include/idr/Transforms/Contracts.h`),
installed before the profile instrumentation:

- **When.** Before and after every pass whose operation is the module or an
  `idr.program` (almost every pass runs on the program, `Passes.td:7-14`);
  function-level runs on worker threads are not checked.
- **Snapshot.** The module printed with locations to a temporary file (the
  form idr-expect's `quantitiesKept` reads), and per function by symbol its
  effects and its parameters' and results' quantities.
- **Relations, after the pass,** each defined once in idr-expect and called,
  never copied (`Expect.h` keeps exporting `quantitiesKept`, `crashSites`,
  `foldsBalanced`, `functionsOf`, `names`; E's dispatch binds it):
  - `quantities-kept`: idr-expect's, against the snapshot's file;
  - `linear-kept`: for every function present before and after under the same
    symbol and arity, each parameter's and result's quantity is unchanged
    (inlining and erasure may legitimately add or remove linear values inside
    a body, so the multiset of a body's values is not the relation);
  - `effects-not-widened`: such a function's declared effects after the pass
    are contained in its declared effects before it;
  - `crash-sites-not-added`: `crashSites("@f:0")` for each such function whose
    effects lack crash, whose name no copy shares and whose symbol has no `:`;
  - `folds-balanced`: idr-expect's absolute check, after every pass.
- **Failure.** An error at the module, `contract <relation> broken by <pass>`
  (the pass's `getArgument()`, or its textual pipeline for an adaptor), and the
  pass fails.
- **Discriminator.** A test pass `test-idr-break-contract{relation=...}`,
  registered only in `idris-mlir-opt`, breaks one relation on valid IR; the
  contract must catch each, since no real pass breaks one on valid input.
- Functions a pass creates or deletes are not compared (a raise node or a trmc
  copy has no predecessor with the same contract).

### 4.2 Pass roles and actions (K2, K3)

- `Passes.td` defines the role as a record, `class IdrPassRole<string
  roleName> { string name = roleName; }` with the four defs
  `IdrRoleOptimization`, `IdrRoleLowering`, `IdrRoleAnalysis`,
  `IdrRoleCheck`, and `class IdrPass<string arg, string anchor, IdrPassRole
  passRole> : Pass<arg, anchor> { IdrPassRole role = passRole; }`, so an
  unknown role is no TableGen value and TableGen refuses it; every pass in
  `Passes.td` derives from it. The inner steps of `InnerPasses.td` keep `Pass` (including
  `Passes.td` there would pull every pass into `InnerPasses.h.inc`); they are
  steps of idr-optimize, whose role they share.
- Roles, fixed: `lowering` for idr-target, idr-defunctionalize, idr-rc,
  idr-structure-loops, idr-bufferize, idr-tail-calls (a tail call on a cycle
  using no stack is a guarantee programs rely on), idr-lower, idr-entry;
  `analysis` for idr-effects, idr-binding-times; `check` for idr-demand,
  idr-expect; `optimization` for every other pass.
- `idris-mlir-tblgen -gen-pass-roles` writes `<role> <argument>` per line,
  sorted by argument, to `IdrPassRoles.txt` beside `IdrRules.txt`; it fails on
  a pass not declared as `IdrPass` (TableGen itself refuses an unknown role).
- Every optional transform of an `optimization` pass performs through an
  action (`include/idr/Support/Actions.h`), tagged `idr-<pass>-<transform>`;
  the existing `idr-raise`, `idr-specialize-clone` and `idr-optimize-node` keep
  their names (`tools/bisect.sh`, `tests/obs-debug-counter/obs-debug-counter.mlir` use them).
  A skipped action leaves the IR as it was and valid. The split is by file:
  K2 the actions in `lib/Transforms/Optimize/**` (pure-calls, contify), K3
  every other file's (inline, identity, constants, canonicalize, deduplicate,
  columns, stack, accumulate, trmc, tail loops, narrow, narrow lanes, returned
  arguments). An action that correctness requires (idr-stack returning a cell
  to the heap) is no action. Upstream's `apply-pattern` and
  `apply-conversion` are outside the promise.
- idr-optimize gains `idr-canonicalize.not-converged`, `cse.num-cse'd` and
  `cse.num-dce'd`, read off each inner pipeline copy.

### 4.3 Facts (F)

- **What the facts mean** (source, not intent): `total` means the function's own
  loops end (`Analysis/Effects.cpp:47`); a total function may call partial
  ones (every lambda and delay function the frontend emits is total,
  `Emit/Closures.idr:89-93`, as are defunctionalization's force functions,
  `Defunctionalize/Forces.cpp:39-46`). `total` is set by the frontend and by
  defunctionalization; `no_inline` only by the frontend. F writes this
  provenance into the attributes' ODS descriptions; no verifier rule relates
  `total` to callees.
- **Effects covered by the body, held once.** `idr::bodyEffect(FuncOp)` in
  `lib/IR` is the solver's own-part rule (the effects a body's ops have by
  themselves); `lib/Analysis/Effects.cpp` calls it instead of its own copy,
  and the program verifier (`lib/IR/Verify/Program.cpp`) checks, for every
  function with a declared `effects`, that `bodyEffect` joined with its
  callees' declared effects (a callee with none counts as every effect;
  `idr.apply` and `idr.force` count as every effect) and with diverge unless
  `total` is contained in the declaration. A violation is an internal error
  naming the function and the uncovered effect, never a refusal. Op memory
  resources are not the rule (a crash also writes the IO resource,
  `idr.handle.string` reads IO with no world).
- **Grades at a field (F06, wider than first seen).** Since bfdcac70 `view`
  returns the borrow grade, which broke four sites: `ConOp::verify`,
  `verifyElement`, `verifyEnd`, `DupOp::verify`. One rule in `Grades.h`,
  `atPermission(Type, Permission)`, keeping the quantity, replaces the `view`
  comparison at all four; a borrow never fills a constructor field.
- **Reduction (F07)** lives in `tools/idris-mlir-reduce.cpp`: the
  `DialectReductionPatternInterface` registered by a registry extension, with
  a `PoisonResults` pattern, the tool on the reserved stack (`mlirReduceMain`
  constructs its own `InitLLVM`; the tool adds none). PINS `mlir-recursion`
  text updated by the coordinator.

### 4.4 The verdict (G, I)

- One rule, held in each language once: `Verdict = Accepted < Refused <
  Internal`, the worst seen wins (owner ruling R1, §8, settling review D1).
  It is sound because a refusal fails the step that makes it, so no later
  step runs on a refused program and no error after a refusal can be its
  cascade: the verifier refuses a knot (`Verify/Knots.cpp`), idr-demand
  signals failure on the refusal it reports (`Demand.cpp:145`), and the
  frontend's refusals end its build. An internal error beside a refusal is
  then from the same step, the compiler's, which must be fixed before the
  refusal can be believed. G states the invariant in `Verdict.h`'s comment and
  keeps every refusing site failing its step. C++: a header-only
  `include/idr/Driver/Verdict.h` (`Verdict`, `statusOf`, `nameOf`, and a
  thread-safe `Outcome` the diagnostic handler updates, which also fixes the
  unsynchronized write at `Run.cpp:238`). Idris: the frontend's
  `statusOfAll` (`Frontend/Driver.idr:212-226`) already holds the rule; lane I
  keeps it and G re-reads it at handoff.
- `idris-mlir --report=<file>` (an output; X3 adds `report` to the allowed
  options of `tests/no-behaviour-options`): written whatever the verdict,
  checked by `Plan::of` against the input and outputs, a usage error with any
  action but compiling, a failed write failing the compilation. Lines:
  `verdict: accepted|refused|internal`; then `diagnostic: <severity> <rule,
  spaces as -, or -> <file:line of the first file location, or ->`; no field
  names a rule's category, which `IdrRules.txt` gives and a reader joins on
  the rule, nor the pass, which MLIR does not tell a diagnostic handler; then `statistic:
  <pass>.<name>=<summed value>` for every statistic, zeros included, sorted
  bytewise.
- **F09.** The input's content decides, with no flag: the parse registry is the
  handoff dialects plus LLVM and DLTI; a module with an `idr.program` is a
  handoff module; one without must be all LLVM dialect and runs only the LLVM
  half, after checking its triple against the build's; anything else is an
  internal error naming the offending op.

### 4.5 Exhaustive boxes (B)

googletest and googlemock from the pinned tree
(`.toolchain/llvm-project/third-party/unittest`), built by our CMake as a
static library for a new `foreign/idr/unittests/` (owner decision O2); one
program per rule family, each calling the real rule (never a copy: the range
functions, the range hooks on ops built in a scratch block, the generated
big-to-word table folded by MLIR's arith folders, the runtime's C entries
through `idr::runtime::Abi<Op>::function`) and exhausting a box: every
interval over a small domain for the range and narrowing rules, and for the
tagged arithmetic every small value within 2 of 0 or of ±2^k, which puts
inputs on both sides of every overflow boundary, against exact `__int128`
arithmetic. The rules are 64-bit `extern "C"` functions, so a reduced width
would need a copy, which §2 forbids. A new `make test-unit` target runs them (coordinator).

### 4.6 Typed identities (I, consumed by T and Q)

Canonical text: `parts/lanes/I.md`, Fixed decisions (T and Q quote it). In short:

- **A definition's identity is `Proof.Requests.Address`**, the value
  `Link.definition` already holds (not a `Fin n`: the context size is a run-time
  value). `State.idr` exports `addressOf : Int -> Address` (moved from
  `Keys.idr`, whose copy Q deletes) and `definitionAddress : Context -> Name ->
  Maybe Address`; a name with no address is skipped by every table, as
  `Walk.enter` skips it.
- **`Request`** becomes `MkRequest inst name kinds key site (owner : Shown)
  link`: `base` is deleted (the link holds the definition; Finite prints
  `nameKey !(toFullNames r.name)`, the same text); `owner` and
  `Dictionary.chooser` are `Shown`, since they are only printed and an `FnId`
  prints the instance, not the definition. `request`'s signature is unchanged.
- **`ConId`** becomes `MkConId (dataId : DataId) {0 arity : Nat} (index : Fin
  arity)` (the arity erased: only `index`'s type needs it): `index` is Idris's tag (0, 1, … in declaration order,
  `Core/Context/Data.idr:116-121`); equality and order by `(dataId, finToNat
  index)`; `Show ConId` prints `<dataId>#<index>` for internal messages only;
  `Term.Con` gains `name : String` for every user-visible print and holds no
  tag of its own: `c.tag` is the derived projection `finToNat c.id.index`, and
  the unread `idrisName` is deleted; `Types.conIdOf` is the only
  constructor of a `ConId`.
- **Tables:** `loops`, `refused`, `tyCons`, `blockNames` keyed by `Address`;
  `places`, `spelled` by `ModuleIdent`; `TS.symbols` and Emit's `keys` stay
  (they guard printed symbols, which reach MLIR); Recursion's `Node` gains
  `address`, its Tarjan tables keyed by it; Emit's `ES.owner` becomes `FnId`
  and the lifted kind `data Lifted = LiftedLambda | LiftedDelay`. Emit's
  `names` and Bytecode's numbering key by SSA names, the only value identity
  the MLIR model has: typed SSA names are later work.
- **The verdict's frontend half:** `statusOf err = statusOfAll [err]`.
- **Closed's exports** are unchanged; T's list is in `T.md` and I keeps each.
- **T's head evaluation** uses `normalisedBy host.normaliseHoles` (beta only, the
  same totality guard), not `normaliseAll`, which would run every total
  definition a term reaches and fold closed calls at compile time.
- **Printed text stays byte-identical.**

### 4.7 Gen and the primitive table (N)

Decided by the owner (O1): our own suite, written clean room. idris2-hedgehog,
Mojo's stdlib `testing/prop` and Hypothesis are references read, never code
copied, so no port and no second licence enter the tree.

- **The choice stream.** `harness/Gen.idr`: a generator reads every decision as a
  `Nat` below a bound from one tape; the tape is a linear (quantity 1) buffer
  threaded through the draws, so a draw is O(1), a run allocates its tape once
  and reuses it (matklad's static allocation), and generation is linear in the
  tape's length.
- **Three sources, one generator.** A seeded PRNG fills the tape; a replayed
  tape reproduces a case exactly; an odometer enumerates every tape up to a
  bound (exhaustive small-scope mode, matklad's "generate all the things").
- **Distribution as a value.** `weighted : Weights n -> Gen (Fin n)` where
  `Weights` cannot be all zero (its type carries the nonzero floor);
  `swarm : Weights n -> Gen (Weights n)` zeroes each weight with probability ½
  and keeps the floor.
- **Shrinking on the tape.** Each pass (delete a span, zero a span, lower a
  draw) is one linear sweep; a change is kept only when the case still fails
  and the tape is strictly smaller in shortlex order, so shrinking terminates
  by construction with no pass budget, and every shrunk case is valid because
  it is regenerated.
- **In the subset.** Gen is written in the language idris-mlir compiles, so the
  compiler can compile its own test machinery, and linearity becomes in-place
  update there; the runner stays on the stock Idris so a broken compiler cannot
  break its own tests.

`harness/Prims.idr` is the one table of primitives (type, bounds, domain, host
dependence) that Fuzz, Sem and TwoLevels import.

The exact exports of `Gen` and `Prims` are the code blocks of
`parts/lanes/N.md`, Fixed decisions, which are canonical: the tape is pure Idris
linear data (`Slot : Nat -> Nat -> (1 rest : Slots) -> Slots` inside an abstract
`Tape`), never `LArray` or a `%extern` primitive, so the stock host runs it and
idris-mlir reuses its cells in place; `caseSeed s i` is output `i` of
splitmix64 started at `s`, the same definition prop.h uses (§4.8). The fold
check is a new idr-expect property, `folded=@f`, which E supplies with the
definition N.md gives.

### 4.8 Runtime properties (R1, R2, R3)

`harness/prop/prop.h` (R1 owns): draws through compiler-rt's
`FuzzedDataProvider` (`.toolchain/llvm-project/compiler-rt/include/fuzzer/FuzzedDataProvider.h`,
header-only) over bytes from splitmix64 seeded per case (`--seed S --case I`
replays one); an exhausted provider yields each family's simplest value;
swarm masks with a floor; shrinking by halving the byte buffer; per-class
counts with f1/n written to a report beside the transcript, never into it. A
program's transcript is its property lines only.

prop.h's exact declarations are the code block of `parts/lanes/R1.md`, Fixed
decisions, which is canonical; R2 and R3 quote it verbatim. Properties link no
C++ library (`link_program` links none), so they use only `FuzzedDataProvider`'s
header-only members that do not allocate, and build their operands from the
documented layout (persistent constants, as idr-lower writes static data), so
no runtime parser sits under an oracle. An exhausted provider yields minimums,
so every family list puts the simplest family first.

## 5. Library first

| Responsibility | Owner | Invention that disappears |
|---|---|---|
| Per-pass contract checks | MLIR `PassInstrumentation` | a hand-rolled snapshot-and-compare pass pipeline |
| Skippable optimizations, bisection | MLIR actions and `-mlir-debug-counter` (`mlir/IR/Action.h`, `Support/DebugCounter`) | per-pass "disable" flags |
| Round trips | `MlirOptMainConfig::verifyRoundtrip` (`--verify-roundtrip`) | a print-parse-compare script |
| Reduction | `mlir-reduce` with `DialectReductionPatternInterface`; `llvm-reduce` for the LLVM half | a source-level shrinker of modules |
| C++ unit tests, expressive matchers | googletest and googlemock (`UnorderedElementsAre`, `Each`), pinned in llvm-project | assertion macros of our own |
| C choice stream | compiler-rt `FuzzedDataProvider` (header-only) | a byte-tape decoder of our own |
| Coverage-guided search | libFuzzer (compiler-rt) — not this wave (O3) | — |
| Idris generators and shrinking | `harness/Gen.idr`, ours, clean room (O1, decided) | Fuzz's, Sem's and TwoLevels' separate machinery |
| Text contracts | FileCheck, only where the text is the contract | — |
| Test runner | the existing Idris runner (`harness/Main.idr`) | llvm-lit as a second harness |

## 6. Lanes

All lanes start at dispatch; none waits on another, because §4 fixes every
shared declaration by name and shape. The coordinator owns the hubs
(`compiler/idris-mlir.ipkg`, `harness/harness.ipkg`, every `CMakeLists.txt`,
`Makefile`, `PINS.md`, `upstream/README.md`, `tools/policies.txt`, which
T, Q and I edit by handoff: `tests/no-fuel` wants each line still in its
file) and the generated Idris dialect
modules (`compiler/src/IdrisMLIR/{Dialect,Syntax}/*`, regenerated by
`make typecheck-dialects` after an ODS change, never edited by hand), and
applies the lanes' requests to them; the lanes name what they need in their
handoff.

| Lane | Exclusive writes (`ownership.json`) | Consumes | Findings |
|---|---|---|---|
| K1 contracts | `lib/Transforms/Contracts/**`, `include/idr/Transforms/Contracts.h`, `tools/idris-mlir-opt.cpp` | §4.1, idr-expect's definitions | F01 |
| K2 roles | `include/idr/Transforms/{Passes,InnerPasses}.td`, `tools/idris-mlir-tblgen.cpp`, `lib/Transforms/Optimize/**`, `include/idr/Transforms/Optimize.h` | §4.2 | F04, F05 |
| K3 actions | `lib/Transforms/**` except `Optimize/`, `Expect/`, `Contracts/`; `include/idr/Support/Actions.h` | §4.2 | F03 |
| E expect | `lib/Transforms/Expect/**`, `include/idr/Transforms/Expect.h`, `tests/idr/expect/**` | — | F21 |
| F facts and IR | `include/idr/IR/**` except `IdrStringOps.td`; `lib/IR/**` except `OpsStrings.cpp`, `Fold/Strings.cpp`; `tools/idris-mlir-reduce.cpp`; `include/idr/Analysis/Effects.h`, `lib/Analysis/Effects.cpp` (the body-effects rule moves to `lib/IR`) | §4.3 | F02, F06, F07 |
| G driver | `include/idr/Driver/**`, `lib/Driver/**` | §4.4 | F08, F09 |
| B boxes | `foreign/idr/unittests/**` | §4.5 | F10 |
| P primitives | `include/idr/IR/IdrStringOps.td`, `lib/IR/OpsStrings.cpp`, `lib/IR/Fold/Strings.cpp`, `compiler/src/IdrisMLIR/Registry/**`, `compiler/src/IdrisMLIR/Emit/Operations.idr`, `runtime/Strings/**`, `libs/**`, `tests/registry/**` | — | F14 |
| I identities | `compiler/src/IdrisMLIR/**` except `Registry/**`, `Emit/Operations.idr`, `Proof/**`, `Frontend/Finite.idr`, `Frontend/Translate/{Keys,Terms,Programs,Cases}.idr`; `compiler/idris/src/Idris/Host.idr` (new), `compiler/idris/README.md` | §4.4, §4.6, §2 (R4: `Host` into the fork) | F11 |
| T applications | `compiler/src/IdrisMLIR/Frontend/Translate/{Terms,Programs,Cases}.idr` | §4.6 | F12 |
| Q proofs | `compiler/src/IdrisMLIR/Proof/**`, `Frontend/Finite.idr`, `Frontend/Translate/Keys.idr` | §4.6 | F13 |
| N generators | `tests/{Gen,Prims,Fuzz,Sem,TwoLevels}.idr`, `tests/fuzz/**`, `tests/two-levels/**`, `tests/programs/semantics/**`, `harness/lib/fuzz.sh` | §4.7 | F15 |
| R1 bigs and text | `harness/prop/**`, `tests/runtime-bigs/**`, `tests/runtime-text/**` | §4.8 | F16 |
| R2 doubles and strings | `tests/runtime-doubles/**`, `tests/runtime-utf8/**`, `tests/runtime-strings/**`, `tests/toolchain/double-print/**` | §4.8 | F16 |
| R3 counting, arrays, IO | `runtime/**` except `runtime/Strings/**`; `tests/toolchain/**` except R1's and R2's | §4.8 | F17 |
| X1 dialect cull | `tests/idr/**` except `expect/`; `harness/lib/lit.sh` | §2, §4.1 | F18 |
| X2 program cull | `tests/{programs,accept,reject,bench}/**` except `programs/semantics/`; `harness/lib/{profile,e2e,expect,run,heap}.sh` | §2 | F19 |
| X3 specs and harness | `tests/{spec,determinism,compiler}/**`, `harness/lib/**` except X1's, X2's and N's; `tests/{Main,Runner,Lock}.idr`, `harness/testutils.sh`, `harness/README.md`, `tests/ACCEPTANCE.md` | §2, `idr-contracts` and `report` added to `spec/no-behaviour-options`' kept flags | F20 |

Eighteen concurrent lanes; the record (`proposals/**`, `HANDOFF.md`) is the
coordinator's at integration. F08 is G's: I writes the frontend's half against
§4.4, and G's acceptance includes it.

## 7. Acceptance (the conjunction)

`producer ∧ adapted consumers ∧ deleted predecessor ∧ discriminating evidence
∧ bounded scope ∧ integrated qualification`. Evidence kinds stay apart:
source review (the coordinator, against each lane's contract), typecheck
(`make typecheck`, `tools/check-units.py`), `make check` here, and the owner's
build and suites, which alone are behavioural evidence; every new or changed
test carries NEEDS-ACCEPTANCE until then. Code that runs without the built
LLVM (Idris on the stock host, the runtime and C property programs by the
host's clang) is run here, and that run is behavioural evidence for it. Each
lane's dispatch names its tempting partial solution and why its acceptance
rejects it, and states, per obligation, the representation that removed the
branch (the owner's guideline, first in every dispatch).

## 8. Owner decisions

| ID | Decision | Default taken in the packet | Trade-off |
|---|---|---|---|
| O1 | Idris generator library | **decided by the owner:** our own suite, clean room (§4.7) | idris2-hedgehog's rose-tree shrinking and three dependencies are the opposite of the choice-stream design; it, Mojo's `testing/prop` and Hypothesis stay references |
| O2 | Build googletest and googlemock from the pinned llvm-project in our CMake | **decided (R5):** yes | no LLVM rebuild and no new dependency; adds `foreign/idr/unittests/` and a `make test-unit` target |
| O3 | libFuzzer (compiler-rt) in the bootstrap for coverage-guided runtime fuzzing | not this wave | needs a stage-2 change and an LLVM rebuild; `FuzzedDataProvider` alone needs neither |
| O4 | A primitive's documented meaning as a small model in the harness (Sem's precedent) | allowed, never a reimplementation of the runtime | the alternative is properties only, which leave integer arithmetic's values unpinned |
| O5 | Collapse the universal harness lines (318 transcripts rewritten once) | yes | one rewrite now against one per future universal check |
| O6 | Research-library snapshots | none taken; candidates in §9 | the library records provenance for each |

The review's open decisions, ruled by the coordinator on the owner's
delegation (2026-10-15, "i trust your judgement"), each by the
representation-first guideline:

| ID | Ruling | Why |
|---|---|---|
| R1 (review D1) | `Accepted < Refused < Internal`, the worst seen wins, in C++ and in the frontend; a refusal fails its step (§4.4) | the reviewer's cascade cannot occur: no step runs after a refusing one, so the order needs no exception for it; one total order, held once per language, replaces a rule with a carve-out |
| R2 (review D8) | Kept, as the text that is the contract: `tests/lower-llvm-facts/lower-llvm-facts.mlir` RUN 3-4 (the attributes LLVM reads are the interface, so they are checked as LLVM is given them; E's `memory` property covers alignment, not `nonnull`, `dereferenceable` or `range`); `tests/partial-divergent-call/mlir.check` (soundness: a closed call of a partial function is never evaluated at compile time; two lines naming source definitions); `tests/programs/partial/lambda-terminates/mlir.check` (the frontend's `total` fact: a lambda's function whose body has no loop is total, `main` is not; no idr-expect property can name a lambda's hashed function). Deleted like the rest: `data/shapes` (pins the printer's text and holds an unresolved mark about its syntax), `eval/dead-static`, `eval/static-evaluation`, `interfaces/interface-superclass` (they pin what the optimizer happened to remove, so a budget or an order change stales them; their values are the run's) | the hard rule deletes a check stronger than its contract; these three are exactly as strong as theirs. `dialect-text` (X3) exempts exactly `lower/llvm-facts.mlir` |
| R3 | `libs/` compiles under both hosts; its `%extern` primitives mean only what `runtime/` says, so a program that reaches one runs under idris-mlir only, and nothing the stock host runs reaches one (§2; AGENTS.md says it) | one meaning per primitive (AGENTS.md) and "Chez must compile and run the Idris side" agree once the line is drawn at what the stock host runs |
| R4 | No escape hatch stays in a user module: `Host` moves into the fork (I); Finite's passes are proved finite or `covering` (Q, with T's `translateIOProgram` following) | `make self` refuses `assert_total` in `IdrisMLIR.*`; the trust in Idris's compiler belongs to the fork, a trusted library whose own assertions are its; a `covering` definition states exactly what is not proved, where an assertion states the opposite |
| R5 (O2, review prerequisite 4) | Accepted: B's googletest-from-source unit programs (unbuilt here: they link MLIR) and R1's C++ property programs over the runtime (built and run here by the host's clang) | the library owns the mechanism; the property programs link no LLVM library, so they are verified on this machine |

## 9. Deferred

- The typed program generator over the subset (`Tm sig ctx ty`, `Prog` over
  live resources), swarm feature weights, EMI-style rewrites that keep
  meaning, campaigns with a Good–Turing stopping rule: the next testing step,
  standing on `Gen`, the contracts, the verdict report and the skippable
  actions this wave builds.
- Two refusal rules nothing raises (`io primitive`, `identity hook`: only
  registry entries' `rules` lists name them); a rule with no raise site is a
  second copy of nothing, for the next wave to delete or give a site.
- An `LLVM_ENABLE_REVERSE_ITERATION` build compared with the normal one; a
  simulated platform layer for the runtime's IO; libFuzzer (O3).
- Found during the wave, each with its evidence, for the next wave:
  - crash-sites counts `idr.exit` and every noreturn runtime call as a crash,
    while `idr::bodyEffect` counts only `MayCrash`. It is latent, since no
    dialect fixture reaches `idr.io.exit`. The single-fact fix: generate a
    `crashes` flag from `MayCrash` into the runtime table and read it on both
    sides of lowering.
  - C++ identities still held as strings: `CalleePattern::kLabel`
    (`IR/Canon.h`), the `StringMap`s in `Conversion/Runtime.cpp`, and
    `getName() == "main"` in `Driver/Run.cpp`. Also owed: a pass that trims
    the C++.
  - The `static argument` refusal reached through a library projection is
    reported at the projection (`Prelude/Show.idr:49`), not at the user's
    code, so its reject fixture is owed. Lane T's program:
    `chosen = if loopy 0 == 3 then showA else showB` with `loopy` covering.
  - ODS gives some rules the category Megamorphic or OutsideLanguage while
    the rule also refuses bounded cases (`ValueType`, `DependentField`,
    `DictionaryField`, `StaticArgument`, `RuntimeClosure`, `Match`,
    `Primitive`, `StringPrimitive`). The category is per rule where it is a
    fact of each site.
  - `harness/Prims.idr`'s `Op` is a test-side copy of Idris's `PrimFn`,
    kept apart from the compiler's on purpose so the model stays
    independent, but it can drift. Its `opIndex` is a hand numbering.
- Snapshot candidates (O6): the Hypothesis reducer paper (CC-BY), matklad's
  three posts, TigerBeetle's VOPR sources (Apache-2.0); link-only for the
  Google, Turso and TigerBeetle posts and the ACM papers (swarm, Csmith, EMI,
  YARPGen, STADS).

## 10. Validation

`python3 proposals/0002-sound/validate.py` (numbers recorded at the end of
packet authoring): see §11.

## 11. Validation record

2026-10-15, after `assemble.py`: `validate.py` reports 22 findings, each with one
owner equal to `ownership.json`; 4,536 pairs of write paths compared with no
overlap; 18 dispatches, each with the template's fifteen sections, the common
obligations verbatim, six binding rules, its findings and every owned path; no
waiting language; no retired mechanism prescribed; 0 problems. The adversarial
review (`review.md`, a different model) read K1, F, I and R1 in full and the
rest's decisions: verdict "executable after named concrete prerequisites".

2026-10-15, after the rulings R1-R5 (§8) and the owner's guideline was made
the first part of every dispatch: `validate.py` reports 22 findings; 4,815
pairs of write paths compared with no overlap (lane I gained the fork's
`Idris/Host.idr` and `README.md`, the coordinator the fork's `.ipkg`); 18
dispatches, each beginning with `parts/representation.md` verbatim, then the
lane, the common obligations and six binding rules; 0 problems. The review's
prerequisites: (1) D1 and D8 ruled (R1, R2); (2) integration sequenced in
`orchestrator.md`; (3) X1's A10 repairs land with F's verifier (orchestrator
step 6); (4) accepted (R5). Document checks only.

2026-10-15, integration on the typecheck machine. Eighteen lanes and one
delegated lane (Z: `lib/Conversion`, three duplicate and dead-code
removals) delivered. Every hub text was applied (CMake: `IdrContracts`,
`IdrPassRoles.txt`, `foreign/idr/unittests`, `IdrSupport` links,
`Expect/Folded.cpp`, `Driver/Outcome.cpp`; the Makefile's `test-unit`; both
`.ipkg`s; `tools/policies.txt`; `PINS.md`; `.gitignore`), the dialect modules
were regenerated once, and the coordinator fixed what integration found:
`conIdOf` reads a constructor's type in normal form (`-@` hid the binders of
`Linear.List.(::)`, refusing twelve linear programs), the user pragma
`%prefix_record_projections` left `Translate/Closed.idr` (the frontend
refuses it), the hole marker's spelling is `markerName`/`markerOf` alone, and
lane G's report reads statistics through a minimal instrumentation with no
`thread_local` and names no pass (`tests/mlir-layout`). `make typecheck`
passes every part (C++ 0 errors) and `make check` is 35/35; `tests/ACCEPTANCE.md`
lists 285 files. Evidence that ran here: the runtime property programs and
`rc`, two googletest boxes, Gen and Sem and TwoLevels on Chez, and the
frontend on Chez beside HEAD's (same exit status on all 312 test programs).
Everything idris-mlir does is the owner's build.

