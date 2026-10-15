# 0004: whole-program facts, a fixed optimizer, parallel code generation

## 0. Status

**Decided 2026-10-14; every question decided.** The owner approved the
cutover the same day ("hard cutover, shoot for the moon", and the
swarm), and ruled that a count never decides acceptance (D40). It is
executed as one hard cutover, in one swarm wave, with no compatibility owed to any
mechanism it replaces, on the owner's machine, where `make build` and
the suites run at each lane's integration (§10). This file supersedes
every earlier text of 0004: the compile-time record those drafts held is
kept in §3, condensed only where nothing is lost, and git history holds
the drafts themselves.

**What is true now.** The cutover of 0002 is committed and builds on
arm64 macOS. Its gate was green there at 552d682a and its file-size
split df5d8742: `make build` clean, `make check` 27/27, `make test-idr`
286/286, `make test` 415/415 (*measured* 2026-10-14 at `NCPU=6`, §3.3).
Those runs took the rounds, the default; the opt-in `scc-pipeline` that
552d682a added ran in one lit test only, and this cutover deletes it
(§3.3, §6). Nothing builds on it in the meantime. x86_64 Linux has not
run this tree: 0002's G1 is NotRun there. Stage 1 of `make self` has
never finished, and this cutover is what it waits on.

**Sources.** Five research reports of 2026-10-14, kept verbatim in
`sources/notes/compile-pipeline/`: `mlton.md` (MLton's pipeline, closure
conversion, inliner and chunks, read from `sources/code/mlton`, 43 files at
`aa2fd1ad`), `codegen-partitioning.md` (LLVM, GCC WHOPR, ThinLTO, rustc,
Swift, Zig, GHC, Lean), `mojo.md` (the Mojo compiler, snapshot in
`sources/code/modular` at `9211931`), `upstream-mlir-llvm.md` (the pinned
MLIR and LLVM machinery against our C++) and `casework-audit.md` (our
casework, why acceptance depends on optimization, what blocks sharding).
Their section numbers are cited as, for example, *mlton §2*. The stage-0
measurement is `bench/profiles/2026-10-14-f0-stage0.md` (*F0*). `M/`,
`L/` and `lld/` are the pinned MLIR, LLVM and lld trees under
`.toolchain/build/llvm-project/`, the copy the bootstrap patches and
builds. Every line number in our tree was re-read against ccaba89c on
2026-10-14 (no file under `foreign/`, `compiler/` or `runtime/` changed
since 3de67510); where a report's number had drifted, or a report's
count did not reproduce, this file gives the tree's and says so.

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
- no option selects behaviour, of a pass or of the driver; experiments
  compare binaries (§10).

**The shape of the work that results.** Decide the facts once, exactly.
Transform with a fixed sequence of bounded passes. Partition. Generate code
in parallel. Each step is a function of its input alone, so the output is
byte-identical at every thread count.

**Rules of AGENTS.md it keeps.**
- *Idris does types; MLIR does programs*: the frontend decides instances
  and representations; every pass of §4 is C++ in `foreign/idr`.
- *One thing, one representation*: one flow interface, one effects
  summary, one canonicalization configuration, a data type's
  declaration held once in its type (D8, D16, D29); §6 deletes every
  copy the audit found.
- *Reject with a named rule, never miscompile*: a refusal carries its
  rule as data (D42); a broken invariant is an internal error (§2.5).
- *No pass drops what Idris proved*: quantities stay in types,
  `!idr.lin<T>` checked by the verifier after every pass, and no fact
  moves into a discardable attribute (D19, D28, D31).
- *Two first-class targets*: every lane integrates on both, and nothing
  here reads the target outside its entry (§10).
- *Static linking*: no runtime library is added; code generation runs
  on LLVM's own thread pool and writes objects that link as today.
- *An upstream bug is fixed upstream, and a patch goes when the pin
  moves past upstream's fix*: §7's patches each carry a report, a
  reproducer and a `tests/upstream` check, and 02, 16 and 22 stay
  carried after their site in our code goes (D23).
- *Tests check behaviour*: brittle fixtures become properties (L8), and
  every claim of output identity is checked binary against binary (§10).

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
| Region arguments of fold, generate and match that are not fields | `Labels.cpp:199-221` | The interface declares region-argument edges, through upstream's `RegionBranchOpInterface` for matches and per op for fold's accumulator and generate's element (the existing `ElementsAnchor`, `Labels.h:175`); fold and generate on unordered arrays go at 0003's stage 1, which writes them as `scf` loops whose edges upstream already declares (0003 §15, D41) |
| A lazy component whose labels return different types is refused | `Moves.cpp:185-198` | The forced-state anchor: every label of a lazy key returns into the one anchor of its value type |
| A label that does not fit its key: `fits` demands exact type equality | `Keys.cpp:84-95` | Nothing new: a label enters a key only along a declared edge from the op that named it, and that op's verifier already demands the same equality (`ClosureOp::verifySymbolUses`, `lib/IR/OpsClosures.cpp:155-171`; `SuspendOp`'s on the carrier, `:201-217`). The flow interface's verifier demands that every edge join two values of one carrier, so `fits` becomes an assertion: a label that does not fit is an internal error (*decision*, D27) |

**The four changes** (casework-audit §2):

1. **Closed world as a verified invariant** (*decision*). No external
   `idr.func`, and no public function except the root, which takes a world
   or returns an `i64` (the two root types `Verify/Program.cpp:32-40`
   already demands). The root is the module's one public function, as the
   module rules and the entry conversion already find it
   (`Verify/Program.cpp:24-31`, `Conversion/Entry.cpp:35-45`, *read*). An
   external `idr.func` becomes unexpressible: the function verifier, which
   today returns early for one (`lib/IR/Func/Func.cpp:85-86`), demands a
   body, and demands a root type of a public function. The rest is the
   module rule the root's verifier runs, once per verification, on the
   module that holds it (D28, §4 stage 2). This deletes `escapes`
   (`Labels.h:279-281`), the external tops, `Decide.cpp:158-164`, and the
   `isExternal()` tests through the analyses and passes before lowering
   (56 lines in `foreign/idr/lib` and `include`, *read* by a search at
   ccaba89c, the definition in `IdrOps.td:46, 52` and the few on lowered
   `func.func` and `llvm.func` among them, which stay: the runtime's
   declarations are external).
2. **One flow interface** (*decision*). An idr op interface, beside
   upstream's Call, Region and Branch interfaces, through which an op that
   carries a closure or lazy value declares how each such operand reaches
   its results, region arguments and anchors. Labels and Slots both read
   it; nothing else decides how a closure moves. The verifier refuses a
   closure- or lazy-typed operand on an op that lacks it, with two
   cases that are declarations already and need no model of ours
   (*decision*): an op that declares its edges through upstream's
   `RegionBranchOpInterface` or `BranchOpInterface` (`scf.for`,
   `scf.yield`, `cf.br`), whose edges the flow rule reads as it reads a
   match's; and a value of a shaped type whose element is a closure, a
   tensor or memref, which is not itself closure-typed: its element moves
   through the element anchor of its type, and only the ops that move
   one element in or out (`tensor.insert`'s scalar, `tensor.extract`'s
   result) declare an edge into that anchor (0003 §4.5, D28, D41). This
   deletes
   `isFollowed`, `Labels.cpp:119-121` and `Moves.cpp:240-245`, and it is the
   one representation of closure flow that today is held twice
   (`Labels.cpp:68-123` against `Moves.cpp:27-79, 209-247`, which disagree
   on `cf.br`).
3. **A forced-state anchor keyed by the lazy value's type** (*decision*),
   the way `ElementsAnchor` is keyed by element type (`Labels.h:170-180`).
   Evaluated delays write it, and every label of a lazy slot returns into
   it. This deletes `unifySuspensions` (`Moves.cpp:147-206`), Isolate's
   evaluated-delay branch and `Moves.cpp:37-38`.
4. **No unknown element in `LabelSet`** (*decision*). This deletes the
   `unknown` flag (`Labels.h:43-59`), `labelsFor` (`Labels.h:276`, filed by
   type at `LabelSites.cpp:92-114`), the sealing cascade
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
2. **Every closure value has a label of its carrier.** A value of a
   closure or lazy type is created only by an op that names a label
   (`idr.closure`, `idr.suspend`, a closure constant) or arrives through an
   edge some op declares. There is no other way to make one: no external
   function returns one, and no op without the interface may produce one.
   The naming op's verifier makes the label fit the value's carrier
   (`OpsClosures.cpp:155-171, 201-217`), and every edge joins two values of
   one carrier, so a label in a key always fits it.
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
   carrying its captures; a key on a cycle of captures is a box of that
   sum, as today (`Decide.cpp:90-95, 197`), which ends the cycle. A box
   holds its tag in the runtime's cell header, which has room for 2^16
   constructors (`IDRIS_RT_TAG_LIMIT`, `runtime/idris_rt.h:106`; a
   closure sum is boxable only under it, `IR/Layout/Fit.cpp:30`, and a
   boxed type past it is refused, `IR/OpsData.cpp:93-98`, *read*), so a
   key on a capture cycle with more labels than that is refused as
   `unsupported (layout)`: a representation limit, not a count, and the
   one limit this argument leaves (§2.5). An empty
   set means no value ever reaches the key; its applies are unreachable and
   lower to `ub.unreachable`. Today an empty closure key is refused
   (`convertible`, `Decide.cpp:42-43`); that line goes with the rest.
6. **Values move between sets by coercion.** Where a value flows from a key
   with one set to a key with a larger one, the existing converter coerces
   it (`SlotTypeConverter::coerce`,
   `include/idr/Transforms/Defunctionalize.h:218`, *read*), as MLton's
   coercion `case` does. The target's set contains the source's, because
   the labels flowed along that edge, so `Slots::canCoerce`
   (`Decide.cpp:29-32`) always holds and the coercion always exists.
7. **An apply is a dispatch.** An apply on a key becomes a case over the
   key's constructors, each arm a direct call. So every apply in the module
   has a translation, and none is refused.

Hence no closed, monomorphic module is refused by defunctionalization
but for step 5's header limit, and whether a program compiles no longer
depends on inlining, specialization, SCCP, the force preparation or any
budget (casework-audit §2).

### 2.5 What is still refused, and where

- **The frontend's refusals**, whose whole account is 0011's "What
  stays refused" (0011 D16): the megamorphic constructs AGENTS.md
  defines, an implementation chosen by a runtime value and a recursion
  that builds its type deeper at each call, each named with its site and
  the unbounded value; what is outside the language, `%foreign`,
  threads, collector finalizers and raw pointers among them; and, until
  0011's six features land, the bounded constructs the frontend does not
  compile yet (an erased match forced by a runtime value, bounded
  polymorphic recursion, a type computed from a runtime value, an
  existential, a type at runtime, an equality a primitive decides), each
  removed by its feature. All are decided before any MLIR exists. A
  closure set in a closed monomorphic module is never unbounded, so no
  refusal of a megamorphic construct is left to the C++ side
  (casework-audit §2).
- **The one representation limit:** a boxed sum past the header's 2^16
  tags (§2.4 step 5), `unsupported (layout)`, as 0011 D3 records for
  every boxed sum. No program is known to reach it; lane L2 records the
  largest boxed closure sum on the corpus and stage 0, and lifting the
  limit belongs to 0009, which records it, if a record ever names it.
- **A broken invariant is an internal error**, never `unsupported`: a
  verifier failure after a pass, a lattice that reached a state the
  argument rules out, a termination argument that does not hold.
- **A spent optimization budget stops optimizing.** The per-caller size
  cap (§4 stage 7), the unroll limit (`kUnrollLimit`,
  `Specialize/Keys.cpp:38`) and the clone budget
  (`kClonesPerOwner = 1024`, `include/idr/Analysis/Specialize.h:59`, spent
  at `Clones.cpp:30-33`, counted per requesting node after the cutover,
  §4 stage 8) bound work and code size; reaching one leaves the
  program less optimized and never rejects it. `unsupported (compile-time
  budget)` is deleted from its three C++ sites (`Simplify.cpp:207-209`,
  `Simplify/Scc.cpp:96-98`, `Clones.cpp:30-33`; §6). `kClonesPerOwner`'s
  own comment calls it the check of a finiteness argument
  (`Specialize.h:56-58`); it is a budget, not that check (*decision*,
  D39): a finite set of static patterns can pass 1,024 in a large program,
  and a check that refuses it would make acceptance depend on program
  size. Specialization's termination rests on the binding-time rule
  (`Specialize/Keys.cpp:7-15`) and the key's node being made once (§4
  stage 8).
- **The frontend's instance bound goes in this cutover.**
  `instanceBudget = 4096` refuses the 4,097th instance of one definition
  as `unsupported (compile-time budget)`
  (`Frontend/Translate/Instances.idr:38-39, 110-112`, *read*), a backstop
  for calls Idris's size-change graphs do not record. The cutover deletes
  it (D40, the owner's ruling of 2026-10-14 that a count never decides
  acceptance). Lane L1 lands 0011's feature 2, the request-chain rule
  (0011 D4), which refuses an instance only where its chain of requests
  grows, naming the site and the growing value, and which replaces
  `checkComponent`'s blanket refusal. That changes which programs the
  frontend accepts, so the cutover's proof carries a named acceptance
  change beside "every expected output unchanged": a program the budget
  refused and the rule accepts compiles, with an accepted program's
  expected files; a program the rule refuses keeps its refusal, now
  naming the growth. The corpus and the stage-0 module stay under the old
  bound (stage 0 emits, F0), so their outputs do not move. After the
  cutover no count refuses any program, in the frontend or the C++
  pipeline.

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
489-507`, mlton §1); its earlier `polyvariance` pass is precision that can
be turned off, though it is on by default (2 rounds, `small = 30`,
`product = 300`, `control/control-flags.sml:1343-1348`; with it off the
pass returns its input, `xml/polyvariance.fun:433-436`, *read*),
duplicating small higher-order functions before 0CFA so that sets are
smaller (`:91-106`). This design does not build it (D35). Every
consequence:

- **The apply canonicalization becomes case of known constructor.** Today
  `ApplyOp::canonicalize` turns an apply of a known closure into a call
  (`lib/IR/OpsClosures.cpp:316-346`). After defunctionalization the closure
  is a constructor and the apply a case over it, so the pattern that
  replaces a match on a known constructor by its taken region, which
  already exists (upstream's region-branch inlining pattern with
  `canon::readField`, `lib/IR/OpsMatch.cpp:175-187`, *read*), does the same
  work for every first-order program, with no closure-specific rule.
- **Closure references become direct calls.** Each arm of a dispatch is a
  direct `idr.call`, so upstream's `CallGraph` sees every edge. The custom
  reference graph exists because an `idr.apply` is invisible to the call
  graph and a closure naming `@f` contributes no edge (upstream-mlir-llvm
  §2); after this order it is no longer needed for the optimizer.
- **Passes lose their closure cases:** LoopBreakers, Effects, SCCP's
  closure constants (`Round.cpp:64-66`), Raise
  (`lib/Transforms/Specialize/Raise.cpp`) and the two force rewrites of
  `Inline/Prepare.cpp:64-211` (ForceAtCapture and ForceOfOneConstant) all
  have closure-specific code that goes (casework-audit §2).
- **Specialization becomes specialization on known constructors.** What
  substitutes a static closure into a clone today (`Specialize/Keys.cpp:
  13-15`) becomes the specialization of a callee on an argument that is a
  known constructor of a dispatch sum. That is one first-order rule for
  every sum, closures included.
- **Isolate's round trip goes.** Emit writes `idr.lambda` and `idr.delay`
  regions that `idr-isolate` immediately outlines (casework-audit §1.E). Emit
  knows the captures and writes the symbol form directly (§4, stage 1).
  Isolate keeps one region form today: an `idr.delay` whose body only
  yields a value that is no closure or suspension stays a region
  (`Isolate.cpp:82-86`), the evaluated suspension. *Decision* (D37): that
  form loses its region too and becomes `idr.delay %value`, an op whose
  operand is the value it holds; it declares one edge, its operand into the
  forced-state anchor of its lazy type, and the fold of a force of it
  (`ForceOp::fold`, `OpsClosures.cpp:283-293`) reads the operand. A region
  that holds only a yield is the value said twice, and the `EvaluateDelay`
  pattern that hoists ops out of it (`OpsClosures.cpp:95-118`) goes with
  the region.
- **Defunctionalization's conversion runs per function.** Once the keys are
  decided, each function's types are a pure function of the decision, so
  the module-wide `applyFullConversion` (`Pass.cpp:117-136`) becomes a
  nested conversion per function, in parallel (casework-audit §3).
- **Effects are first known inside it.** Defunctionalization marks the
  memo labels that reach observable output (`markByName`, `Pass.cpp:105`,
  after the conversion) with a walk of its own through direct calls
  (`ByName.cpp:30-53`), one of the three effects computations (§6).
  *Decision* (D34): the one effects summary (§4 stage 9) is first computed
  right after the label solve, bottom-up over the SCCs of the call graph in
  which an apply calls every label of its key, which are exactly the
  direct calls its dispatch becomes. Its lattice is today's effects (`io`,
  `crash`, `diverge`, the `Idr_Effect` enum, `IdrAttrs.td:165-169`) and
  the one bit `by_name` needs,
  whether an op with the `ObservableIO` trait is reached
  (`IdrInterfaces.td:75-84`), which is narrower than `io` (an array, a
  buffer and a forged world are `io` and not observable). So each memo sum
  is made with its `by_name` labels already in its body, which is set once
  (D29), and the walk goes. A label's observable bit cannot change after:
  inlining, specialization and cleanup remove effects and never an output.
  After the conversion every one of those edges is a direct call, so the
  ready set's recomputation (stage 9) reads the same graph through
  upstream's `CallGraph`.

### 2.8 What it costs, and how it is kept fast

- **Larger sums before inlining.** Before the optimizer, every apply is a
  dispatch over its full set. The optimizer then folds the known
  constructors, so the dispatches that remain are the ones whose sets are
  really plural, which MLton reports as "almost no calls" (slide 14,
  mlton §2). Lane L2 records, per key, the number of constructors and the
  dispatches left after the optimizer.
- **The solve over the stage-0 module** (about 100,000 functions once
  closures are outlined: 100,198 in F0's run, 107,732 in the run of
  234b81a0, of which deduplication then merges 7,505, *measured*). MLton's
  0CFA runs in under 2 seconds on MLton itself (slide 14). Its
  representation choices, each adopted here (*decision*):
  - first-order values carry no flow: every first-order type shares one
    abstract value (`abstract-value.fun:242-246`), and first-order tuples
    are not tracked (`closure-convert.fun:364-367`);
  - sets are hash-consed with cached operations (`UniqueSet`, cache size 5,
    13 bits, `abstract-value.fun:42-44`);
  - mutable containers unify instead of coerce
    (`abstract-value.fun:341-345`), so union-find handles every equality
    constraint; ours already share one anchor per element type
    (`Labels.h:170-180`);
  - only differences are propagated (`abstract-value.fun:87-95`).
  Today's whole step is the bar: gathering the label sites took 46 of
  `idr-defunctionalize`'s 57 seconds on the stage-0 module, and one walk
  instead of one per site family took the step from 66.6 s to 54.0 s
  (6a7841dc, *measured*). *Decision:* the solve must take under 10 seconds
  of wall on the stage-0 module, or the representation is wrong.

### 2.9 Risks, and how each is checked

| Risk | Check |
| --- | --- |
| The frontend emits something the closed-world verifier refuses (an external function, a second public symbol) | The verifier runs on every corpus module and the stage-0 module in lane L2; every refusal is fixed at emission |
| Dialect tests are fragments that break the closed world: 82 of `tests/`' `.mlir` files declare more than one public `idr.func`, and 23 declarations in 15 files have no body (`tests/idr/stack/calls.mlir:97`, `tests/idr/effects/idr-effects.mlir:191`, `tests/idr/func/call-effects.mlir:62`, among them) (*measured* by a search, ccaba89c) | L8 rewrites each before L5's verifier lands: one root or none, every other function private, every function with a body; a fragment with no root gets the per-function rules only, as a module without `idr.program` does today (D28) |
| The in-place promise, checked on every program (§4 stage 1), rejects a program accepted today: 33 test directories load `mlir-linear` and 11 of them make the promise (*measured*, a search of `tests/*/packages` and `demand-in-place` files), and five bench programs load it and make none (`bench/fannkuch-linear`, `k-nucleotide`, `qsort`, `spectral-norm-linear`, `unionfind`, each with a `packages` file; `bench/run.sh` passes no `--demand-in-place`, *read*) | Before L1 lands, the old binary compiles the other 22 test programs and the five bench programs with `--demand-in-place`, which it still has, 27 programs in all (L0); each rejection decides whether the program or the type fact is wrong, and is fixed there, never by keeping the option |
| An op carries a closure without the flow interface | The verifier names it; every corpus module passes before L2 integrates |
| A flow edge joins two carriers, so a label reaches a key it does not fit (an internal error under D27) | The flow interface's verifier refuses such an edge; a fixture per grade (a closure taking a linear argument, one returning a linear result, a plain one, each through `lin.enter`/`lin.use` and a field) converts, with the linearity verifier after defunctionalization |
| `by_name` comes from the summary, before the conversion, instead of a walk after it (D34) | Every test whose suspension writes output (`tests/programs`' laziness and output fixtures) prints the same bytes; old binary against new, the corpus gets the same `by_name` marks both ways: the old walk ran on the converted module, whose direct calls are the summary's edges, so a difference is a bug in one of the two |
| Sums too large for code quality | Per-key constructor counts and post-optimizer dispatch counts recorded on stage 0; bench runtime within 2% (§10) |
| A key on a capture cycle with more labels than the header's 2^16 tags, refused as `unsupported (layout)` (§2.4 step 5) | L2 records the largest boxed closure sum on the corpus and stage 0 beside the per-key counts |
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
  where it claims, each figure *measured* as its commit message records
  it (F0 holds none of them): the match-field symbol scan deleted (one
  canonicalizer sweep 65.1 to 19.1 user-seconds, 0768bc9f);
  `idr-deduplicate` (7,505 of 107,732 functions in about 1 s, 234b81a0);
  scoped post-inline canonicalization (70,252 whole-body runs deleted,
  5088d7a8); IntRange nested (30 s to 3 s of wall per round, 5d3318fb);
  defunctionalize labels in one walk (the step 66.6 to 54.0 s, 6a7841dc);
  RemoveDeadValues once at the fixpoint (3b166aa3, whose message gives no
  figure; the 40 s of serial analysis it saved per round is
  `Simplify/Round.cpp:68-71`'s comment). One explicit round fell from 1,321 s to
  692 s to 385 s (dev build, 5088d7a8). The suite record is *recalled*:
  248.8 s to 167.9 s over 429 compilations, a figure in no commit message
  and no file (a search of every commit), while HANDOFF's 2026-10-13
  entry counts 490 compilations in a record kept under `/tmp` and since
  lost; G1's run before the cutover re-records it and commits the record
  (0002 §3). Stage 1 still never finished: a 4 h 23 min stage-1 attempt
  on the pre-round compiler and a restarted one after it were both
  stopped inside the rounds (*measured* then, recorded in the
  compile-time proposal at dcb087d2, "What stands"; the runs' own logs
  were not kept). The round count is what remains.

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
  deleted original", mlton §3), at zero growth per decision. MLton has a
  `maxFunctionSize` control, default 10,000 blocks
  (`control-flags.sml:1224-1226`), settable as `-max-function-size`
  (`main/main.fun:637-638`), that none of the 43 stored files reads
  (*read*, a search of `sources/code/mlton`). Repeated over rounds the rule
  builds the 152k-op function.
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

This subsection is a record of what the cutover deletes (§6), kept
because its lessons shape §4 and §10; nothing in it is a plan.

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
`make test-idr` 286/286, `make test` 415/415, all on the rounds, the
default; the SCC path itself ran one lit test. The file-size split
(df5d8742: Scc.cpp, `Simplify/Trace.cpp`; `Simplify.cpp` 463 to 383 lines)
was pure movement, byte-identical.

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
     `idr.lambda`/`idr.delay` region forms go. A suspension of a value Emit
     already holds is `idr.delay %value`, the region-free evaluated
     suspension (§2.7, D37).
   - Generated names are derived from content: the owner's name and a hash
     of the structural key, never a counter (`.lam<n>`, `.delay<n>`,
     `Isolate.cpp:124-125`, and every other counter-named symbol, §6).
     *Decision* (as 0006 D16 decided, taken here because the cutover
     writes the names): the hash is XXH3's 128-bit variant, LLVM's on
     the C++ side (`L/include/llvm/Support/xxhash.h:58-70`) and a copy in
     plain Idris over `Bits64` in the frontend, checked against the
     algorithm's published test values as committed expected values; a
     generated name carries the low 64 bits as 16 hex digits, and two
     keys whose names collide are caught where the name is interned, by
     full equality of the keys, as an internal error, never a merge and
     never a widened name (0006 §4.5).
   - An instance's symbol is its key printed, and the frontend's repeats
     `p'n` on keys that print alike (`compiler/src/IdrisMLIR/Emit/
     Index.idr:21-60`), a counter in program order, go: the symbol is the
     printed key, followed by the low 64 bits of the instance's identity
     hash where the key's print drops part of its identity, a rule of
     the key alone (0008 §4.10, D7).
   - A hook applied below its arity is eta-expanded in symbol form, so
     that the partial application is a closure whose body is the
     saturated call, and the profile's assumption that the hook answers
     for the definition holds everywhere (today they disagree:
     `Frontend/Profile.idr:65-70` against `Translate/Terms.idr:364-370`;
     0002 D18).
   - Binders are keyed by identity, so the synthetic world binder needs no
     `$world` rename (`Frontend/Translate/Programs.idr:182-194`) and holes
     need no sentinel name renamed around Idris's normaliser
     (`Translate/Closed.idr:173, 287-295, 471-476`): the open term is
     normalised under an environment that binds the holes.
   - Data types are written as identified types that carry their
     constructors (D29), and the root as the one public `idr.func`, as
     today (D28); the `idr.program` mark is no longer written
     (`Dialect/Idr.idr:30-33`, generated from `IdrBase.td:58` by
     `idris-mlir-tblgen`, so it goes when the ODS does).
   - *Decision* (D29): a data type is an identified type, the mechanism of
     LLVM's identified structs (`MutableType`, identified by name, its body
     set once: `M/include/mlir/Dialect/LLVMIR/LLVMTypes.td:153-175`,
     `M/lib/Dialect/LLVMIR/IR/LLVMTypes.cpp:519-524`, *read*). Today
     `!idr.data<@T>` is only a symbol name (`IdrTypes.td:25-29`) and its
     constructors are ops in an `idr.data` body. After D29 the type's body
     is the declaration: the constructors in tag order, each with its field
     types and, for a memo label, `by_name`; the sum's kind (plain,
     closures, memo); the frontend's `instance`; the role the registry
     names (the list's cons, §6); and the in-place promise. The `idr.data`
     and `idr.ctor` ops go, since the declaration is then held once. Each
     consequence is decided:
     - an op names a constructor by its name within its value's type, and
       the tag stays the position (`IdrOps.td:158-160`), so a pattern or a
       verifier reads the type and never the symbol table; this deletes
       §6's module scans and the one inside `ForceOp::getEffects`
       (`OpsClosures.cpp:272-277`);
     - a constructor of a sum defunctionalization makes is named by its
       label, a symbol reference to the label's `idr.func`, so every site
       that builds one is a symbol use of the label and keeps its body for
       the interprocedural analyses, which is the work of the `labels`
       attribute today (`IdrOps.td:129-135`), and only while a value of it
       can still be built;
     - boxing is the value's type alone (`!idr.box` around the identified
       type), not a flag of the declaration: today the flag and the value
       types say it twice and the module rule checks that they agree
       (`Verify/Program.cpp:59-63`), and `layout::fit` sets both
       (`IR/Layout/Fit.cpp:117-153`); after D29 it retypes values only;
     - the body is set once, when the type is made, so every fact in it is
       decided before then: a memo sum's `by_name` labels by the effects
       summary before the conversion (D34); a pass that would change a
       declaration makes a new type instead;
     - a recursive type names itself inside its body by its identifier,
       printed and written as its assembly (the handoff below, D36);
     - the module rule that every sum or box type names a declaration of its
       kind (`Verify/Program.cpp:46-90`) becomes a property of the type: an
       identified data type without a body is refused wherever a value of
       it is verified.
     *Checked:* the corpus emits and every program's expected output is
     unchanged (L1); no call of `declarationOf`, `constructorOf` or
     `lookupNearestSymbolFrom` on a data type is left in `lib/` (a spec
     check, L5).
   - The in-place promise is a fact of `mlir-linear`'s types, emitted with
     them, replacing `--demand-in-place` (§6). *Decision:* the registry,
     where the frontend already learns the facts of library definitions
     (`Registry/Libraries.idr`), names the `mlir-linear` types that are
     rebuilt in place and exclusive, and the frontend writes that fact into
     the type's body (D29); `idr-demand` checks it on every program.
   - The handoff is MLIR bytecode: the frontend writes it and the driver
     reads it; text remains a dump. The driver already reads either:
     `parseSourceFile` detects bytecode by its magic and calls
     `readBytecodeFile` (`M/lib/Parser/Parser.cpp:47-48, 62-63`), and the
     driver's input takes `.mlirbc` (`lib/Driver/Options.cpp:22-23`,
     `Artifacts.cpp:34-37`). The work is the frontend's writer. *Decision*
     (D36): it writes attributes and types as their assembly, the bytecode's own
     fallback encoding, as upstream does for LLVM's identified structs,
     whose dialect gives them no bytecode form; a recursive identified type
     then names itself in text and is no cycle of section entries, which the
     reader refuses (`upstream/03-bytecode-deferred-quadratic`). This
     replaces the 11.7 s text parse with a bytecode read (*conjecture*,
     several times faster; L1 records it) and every text round trip in the
     corpus tooling (the earlier F4). Lands on identical bytes everywhere.
2. **Closed-world verification** (whole-program, one walk): no external
   `idr.func`, one public root, every closure- or lazy-typed operand on an op
   with the flow interface (§2.2). It is no separate step: an external
   `idr.func` is unexpressible (the function verifier demands a body), the
   flow rule is each op's own verifier's, and the root's verifier runs the
   module rule (D28). So it holds after every pass the verifier runs after,
   and a pass that broke it is an internal error.
3. **Deduplication** (whole-program by content; hashing per function in
   parallel): Mojo's EliminateDuplicateFunctions design, bottom-up over a
   ready set so that merging is transitive in one pass, with the
   lexicographically smallest member of each class kept (mojo §4, §7;
   `code/modular/Mojo/lib/Transforms/EliminateDuplicateFunctions.cpp:31-80,
   188-254`). It runs before defunctionalization so the label sets are
   smaller.
4. **Defunctionalization, total** (§2): the label solve is whole-program;
   then the effects summary is computed for the first time, bottom-up over
   the SCCs of the call graph the solve resolves (an apply calls every
   label of its key), and the sums are made, each memo sum with its
   `by_name` labels in its body (D34, D29); then the conversion runs per
   function, in parallel.
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
     with upstream `mlir::inlineCall`, each inlined body taking away the
     caller's proof of termination where the callee had none
     (`FuncOp::absorb`, `IdrOps.td:55`, as `Inline.cpp:246` does today), and
     then **one inner per-function pipeline, run once**: identity,
     canonicalize with the one configuration
     (`include/idr/Transforms/Canonicalize.h:33-37`), whose match patterns
     are case of known constructor (`lib/IR/OpsMatch.cpp:175-187`), CSE,
     redirect (each call whose key has a node calls the node's function:
     stage 8's per-function half, today `idr-redirect`,
     `Specialize/RedirectPass.cpp`), int-range, and the function's
     constants solve with its callees' summaries (stage 9). The pipeline
     runs through `Pass::runPipeline` from per-thread copies of one `OpPassManager`, the
     pattern upstream's inliner uses (`M/lib/Transforms/Utils/Inliner.cpp:
     526-567`), so the verifier and the instrumentation stay on.
   - **What the inner pipeline reads, and where each fact comes from**
     (*decision*, as 0006 D20 decided; RoundFacts computes all of them
     today, `Simplify/RoundFacts.cpp:39-43`, because a nested pass manager
     drops module analyses, upstream-mlir-llvm §3). `Holds`, two bits per
     declaration over the type graph (`include/idr/Analysis/Holds.h:3-6`),
     is a type fact computed once before the optimizer and read frozen.
     `Identities`, a greatest fixpoint over the module today
     (`include/idr/Analysis/Identities.h:3-12`), becomes a stage-9
     summary: each SCC takes its greatest fixpoint inside its node when
     the SCC is ready, its callees' identities read frozen. `BindingTimes`,
     a property of each parameter over the references from its cycles
     (`include/idr/Analysis/Specialize.h:106-120`), is computed per SCC
     from that SCC's own bodies when it is ready. `CloneTable` goes with
     the key-named nodes (stage 8). The symbol table is the ready-set
     driver's, a module pass. Reason: each fact then has exactly the scope
     it quantifies over, and none is recomputed per nest.
   - The driver is a module pass, as upstream's inliner is. Inlining reads a
     sibling of the function it rewrites, which the pass manager forbids a
     nested pass (`sources/docs/mlir/docs/PassManagement.md:29-34`); the
     ready set is what makes the read safe (a callee is final, so nothing
     writes it). Every other rewrite runs inside the per-function pipeline,
     which is 0002's D3 in the form this design keeps.
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
     serially, in module order (mojo §2, §5). A function the ready set
     creates (stage 8) is built detached by a worker and inserted into the
     module by the scheduler, serially, after its owner and in key order
     among that owner's, so the module's order is a function of content.
7. **Inline decisions.** MLton's per-function formula, evaluated on the
   callee's final size, the way Mojo measures it lazily after the callee's
   own pipeline (`AutomaticInline.cpp:161-166`): a leaf at most 40 ops inlines;
   any other function inlines when `(calls - 1) * (size - 60) <= 320`; a
   function on a cycle of calls (a member of an SCC of two or more, or one
   that calls itself) is never inlined, MLton's rule (`ssa/inline.fun:
   271-295, 319-327`) and ours today (`lib/Analysis/Inline.cpp:100-107`),
   which the per-function decision needs, since such a function's original
   could never be deleted; when every call is inlined, the original is
   deleted. Size is the op count the formula reads today
   (`References::ops`, `Inline.cpp:108`). `calls(f)` is the number of
   `f`'s call sites when the optimizer starts, frozen (*decision*, as
   0006 D11 decided): no count inside an SCC is ever read, since a
   function on a cycle, the only kind with a call site inside its own
   SCC, is never inlined; no caller of `f` runs before `f` is final, so
   the frozen count is the count at `f`'s finality (*conjecture*,
   checked by L3's determinism at 1, 2 and 8 threads); and a
   specialization node counts one call per request, since its
   requesters wait on it and any count read when it is final would be
   an arrival count. A clone therefore inlines into each requester until
   that requester's cap is reached, unless it is on a cycle, which is
   today's rule for a clone made for one call site (§3.2), bounded by the
   cap. Plus what MLton lacks: **a
   per-caller size cap** (*decision*, D25): calls are inlined in call-site
   order while the caller, with the callee's final body in, stays at or
   under **10,000 ops**; a call past that stays a call, and its callee's
   original stays with it. So the 152k-op function is refused at decision
   time, not discovered in a trace. Reaching the cap stops inlining into
   that caller; it never rejects. Reasons for the constant: the formula
   bounds every callee with two or more calls to 380 ops
   (`(2 - 1) * (size - 60) <= 320`), so only single-call absorption builds
   a giant, and the cap is what bounds it; the cost the cap protects is
   the greedy pattern work over one body, which §3.4 found dominant and
   which a single worker does serially (`statementText.spec1` was 14% of
   the module in one function, F0); 10,000 ops is about 2,000 times the
   emitted average (471k ops over about 100,000 functions, F0) and about
   2% of the emitted module, so no one function holds the ready set's
   critical path; and it is the order MLton's authors chose for the
   `maxFunctionSize` control they never wired (10,000 blocks,
   `control-flags.sml:1224-1226`). The previous default, twice the largest
   caller on the corpus after a first run, needed a run before the
   constant existed. *Checked* in L3 on the corpus and stage 0: the size
   distribution of final functions, the largest, and the calls the cap
   kept, recorded beside the bench's runtime threshold (§10). A miss
   changes the constant in one commit; it never becomes an option.
8. **Specialization as demand-driven nodes in the same ready set.** A call
   whose argument is a known constructor of a sum, closures included, is a
   request keyed by (callee, the static pattern). The key's node is created
   once, named from the key (never `<owner>.spec<n>`, `Clones.cpp:20, 40-41`),
   and enters the ready set below the requesting caller, the way Mojo's
   elaborator creates instantiation nodes keyed by content and resumes waiters
   (`code/modular/Mojo/lib/Elaborator/Elaborator.cpp:1675-1693, 1746-1756,
   2944-2989`, mojo §4). `kClonesPerOwner` stays as a budget that stops
   specializing, never as a check that refuses (D39, §2.5), counted per
   requesting node (*decision*, as 0006 D5 decided): the distinct keys
   one node requests of one owner, in its call-site order, an
   already-made key counted like a new one; a request past the 1,024th is
   not made, and its argument stays a runtime leaf, as the binding-time
   rule makes every argument it does not allow. A node's requests are a
   function of its own final body, so the budget is spent the same way
   on every schedule; counted owner-wide as requests arrive, which
   request is the 1,025th would depend on which caller a worker ran
   first, against the determinism rules below. L3 renames the constant
   and restates its comment after what it counts.
   Specialization of static structure, raising and binding times have no
   upstream analogue and stay ours (upstream-mlir-llvm §8).
9. **Interprocedural constants and effects as bottom-up SCC summaries,**
   in the ready set's own order. Each function's solve runs with
   interprocedural mode off, in parallel, when the function is final, and
   upstream's `visitExternalCall` hook applies the callee's summary, computed
   callee first over the SCC order (upstream-mlir-llvm §4;
   `M/lib/Analysis/DataFlow/SparseAnalysis.cpp:229-251, 277-302, 523-538`).
   This replaces module SCCP every round (21 to 43 s serial) and the effects
   computed three ways (§6). The solver and the analyses stay upstream; the
   driver and the summary lattice are ours. A bottom-up summary carries what
   a callee returns and does; what every caller passes is not propagated
   down, and specialization (stage 8) is how a static argument reaches a
   callee. That drop is a measured risk: today SCCP stays on the module
   because, nested per function, it "retains 582 extra calls on the same
   round" (5d3318fb's message; `Simplify/Round.cpp:57-66`). *Conjecture:*
   those calls are the closure constants module SCCP carries down into
   callers, which after defunctionalization are known constructors of a
   dispatch sum that stage 8 specializes on, so the summaries and the
   specialization nodes recover them together. L3 proves it: the calls
   left after the optimizer, old binary against new, on the corpus and
   stage 0, recorded beside the bench's runtime threshold (§10), which
   is the bar. Identities are a summary of this stage too (stage 6).
   Effects are summarized once before the optimizer (stage 4); the
   ready set recomputes a function's entry when the function is final,
   which can only shrink it, since inlining, specialization and cleanup
   remove effects and never add one. Call-site `effects` (`IdrOps.td:59-75`)
   is written once per call (*decision*, D38): for a callee outside the
   caller's SCC, when the caller becomes ready, since every such callee
   is final then and so is its entry, before the inline decisions and
   the inner pipeline, whose canonicalize and CSE read it (a call with no
   `effects` may do anything, `IdrOps.td:59-61`, so a call left without
   it until the caller was final could never be deleted or merged); for
   a callee in the caller's own SCC, when the SCC is final, from the
   SCC's recomputed entries. A call inlining brings in carries the
   effects written in the callee's body. After defunctionalization no
   closure is passed to a call, so a call's effects are its callee's
   (the comment at `IdrOps.td:59-61` joins in "the closures it is
   given"): the copy is kept only because `getEffects` has no symbol
   table, and its verifier checks equality with the callee's, not
   containment (D38).
10. **Dead values once:** upstream RemoveDeadValues and SymbolDCE at the end of
    the optimizer, once (65 s and 7.65 GB on the round-16 module, *measured*).
    Liveness is a least fixpoint, which 0006 shards by its S3 rule and
    never per SCC, since argument liveness flows from callees and result
    liveness from callers (0006 D19).
    From 0003's stage 1, the arrays stage runs here, between dead values
    and memory: structuring, fusion and the schedules per function, then
    One-Shot on the whole program, then a per-function clean (0003 §7,
    D26).
11. **Memory and loops:** `idr-stack`, `idr-accumulate`, `idr-rc`,
    `idr-demand`, `idr-trmc`, `idr-tail-loops`, `idr-narrow`, and
    `idr-in-bounds` until 0003's stage 1 deletes it (0003 §15),
    as today: module plans, nested rewrites. Changes: `idr.stack` becomes an
    inherent property of `idr.con`; `idr-rc`'s exclusivity loop
    (`Ownership/Rc.cpp:79-99`) computes each function's grade contexts as a key
    set first and clones once; `idr-demand` always checks the type facts
    (§6); the copies `idr-accumulate`, `idr-trmc` and `idr-rc` make are named
    from their keys (§6).
12. **Lowering:** layouts are whole-program and decided first; the runtime's
    declarations are created up front from the decided set instead of inserted
    into one symbol table as the conversion goes; the conversion runs per
    function (today one serial `applyPartialConversion`, `Lower.cpp:166`).
    The lowering tail and `idr-tail-calls` run as today
    (`lib/Transforms/Pipeline.cpp:134-172`), on the whole module: the
    tail-call plan stays one module plan (`Conversion/TailCallPlan.h`).
    The tail's vectorization group (`Pipeline.cpp:142-147`) becomes
    0003's vectorization schedule at 0003's stage 1 (0003 §7.1).
13. **LLVM, whole:** the module is translated once, the runtime linked in,
    everything but `main` internalized and O3 run once, as today
    (`lib/Driver/Run.cpp:164-198`, `lib/Target/Optimize.cpp:44-59`). This is
    §5.4's S2, the step the cutover builds.
14. **Partitioning** of the optimized LLVM module into bins (§5.3): SCCs of
    its call graph, grouped by top-level namespace, cut by content hash at a
    fixed size; a pure function of the module.
15. **Code generation per bin** (§5.4): the optimized module written once as
    bitcode, each bin materialized from it in its own `LLVMContext` with its
    own `TargetMachine` on a pool thread, one object per bin.
16. **Link** the bin objects in bin-name order with the runtime. With `-c`,
    the driver writes them as one archive at the path `-o` names (D32).

After the cutover, §5.4's second step moves the partition before O3 and
before translation: each unit becomes a nested `builtin.module`, the
lowering tail runs under `pm.nest<ModuleOp>()`, and each unit is
translated in a context of its own (D30; `M/include/mlir/Target/LLVMIR/
Export.h:32-36`; upstream-mlir-llvm §5).

**Determinism rules** (*decision*): the bin count is a function of the
module's size, never of `--num-threads`; every parallel join merges in a
canonical sorted order; every name is derived from content; insertion of a
new function is serial and placed by key (stage 6); erasure is deferred
and serial in module order; node maps are ordered (MapVector); output is
byte-identical at 1, 2 and 8 threads, checked by `tests/determinism`
(mojo §5, codegen-partitioning §9).

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
   size, so the objects and the executable are the same for every worker
   count. Several bins per core, largest started first. *Decision* (D26):
   the target is **2^15 = 32,768 LLVM instructions per bin**, counted on
   the optimized module (`Function::getInstructionCount`), the units S2
   partitions. Reasons: a bin's fixed cost (its context, target machine,
   pass setup and bitcode read) is per bin and its code generation is
   linear in its instructions, so bins should be as large as balance
   allows; the stage-0 module, at 471k idr ops when emitted (F0) and
   larger once lowered, is then more than thirty bins (*conjecture*),
   several per core at `NCPU=6`; every test program is likely one bin
   (*conjecture*: the bin is counted on the optimized module, which holds
   the runtime bodies linked before O3, `Run.cpp:182-193`, whose size is
   unmeasured; L7 records each corpus program's bin count, and D32's
   archive gives `-c` one shape whatever it finds); and MLton batches its output into files of the
   same 2^15 (statements, `control-flags.sml:125-127`). GCC's balanced
   partitioner also fixes a count with a minimum size rather than following
   threads (128 partitions of at least 10,000 instructions, *recalled*
   defaults). Checked at S2 on the stage-0 module and the bench: a bin's
   fixed cost stays under 5% of its code generation time. A miss changes
   the constant in one commit; it never becomes an option.
2. **Edit-stable cuts.** Group by top-level namespace first (49% of calls
   stay inside one), read from the symbol's name, whose dots the mangling
   keeps (`Conversion/Mangle.h:15-20`). Every name with no dot falls
   into one namespace group by the same rule: the runtime's definitions,
   whose names are C identifiers, and later 0013's v0-mangled Rust
   names, so neither needs a rule of its own (as 0006 §3.4 says).
   Within a group, order SCCs by
   content hash and cut by content, between a minimum and a maximum size.
   *Decision* (D41): an SCC of size s closes its bin when the bin holds at least
   B/4 and the SCC's hash, read as a fraction of 2^64, is below s/B, or
   when the next SCC would take the bin past 2B (B the target above). A cut
   so depends only on the SCCs beside it, and a bin averages about B. GCC's
   balanced cut at a running total would shift every later cut on one edit.
   A single function too large for a bin is a unit of its own.
3. **Linkage between units.** Each definition lives in exactly one unit. A
   function or a mutable global another unit references gets external
   linkage, hidden visibility, `dso_local`, and its content-derived name
   under the reserved prefix `__idr.` (*decision*, D41): C never names a symbol
   with a dot, and the runtime's names are C identifiers, its own mangling
   (`Conversion/Mangle.h:15-20`), so no static link can collide with one,
   the collision `SplitModule`'s FIXME warns of (`SplitModule.h:32-38`). A
   private constant without address identity (`unnamed_addr`) used from
   several units is copied into each and stays private. Symbols used only
   inside their unit become internal. The runtime's bodies were linked and
   optimized with the module before the split (stage 13), as today
   (`Run.cpp:184-192`). Objects link in unit-name order. `--icf=all`,
   already on with function sections (`CMakeLists.txt:174, 213`;
   `Target/Optimize.cpp:30`), folds identical code across objects, which
   matters at the second step, when MergeFunctions runs per unit.
4. **Tail calls stay inside a unit** (*decision*, D33). `idr-tail-calls`
   plans and rewrites on the whole module before translation, as today; a
   planned tail call joins two functions of one cycle (`Passes.td:95-117`,
   `Conversion/TailCallPlan.h`). O3 may break that cycle by inlining, so
   the partitioner joins every `musttail` caller to its callee as it joins
   an SCC, and no `musttail` crosses an object; a callee of `tailcc` that
   another unit calls keeps its convention on the declaration that unit
   reads, since a declaration keeps its function's calling convention.
   Checked on both targets by the `tests/idr/tail-calls` fixtures and by a
   generated program larger than two bins whose tail-call cycles are
   called from another bin and run deep enough that a lost tail call would
   overflow the stack; the partitioner treats a `musttail` across bins as
   an internal error.
5. **Module-level inline assembly stays in the first bin**, SplitModule's
   rule (`SplitModule.cpp:293-294`), so it is defined once. `runtime/`'s
   sources hold no assembly (*read*, a search of `runtime/`), yet the
   driver initializes the assembly parser because the runtime's bitcode
   carries some (`Run.cpp:209-210`), so it comes from what the runtime
   includes (*conjecture*). L7 records which kind it is on both targets in
   a test that asserts what it finds.
6. **`-c` writes an archive** (*decision*, D32). With several bins a
   compilation makes several objects. ld64.lld cannot merge objects into
   one: it builds a bundle, a dylib or an executable
   (`lld/MachO/Driver.cpp:74-85`), and its `-r` is declared hidden
   (`lld/MachO/Options.td:247-250`) and falls to "not yet implemented". So
   `-c` writes the bin objects, in bin-name order, as one archive at the
   path `-o` names, through LLVM's archive writer in-process and in its
   deterministic mode; it is an archive for one bin too, so the output has
   one shape. A link without `-c` passes the objects themselves. A link of
   the archive takes a member only for a symbol something wants, and that
   takes every bin: after O3 every definition is reached from `main`, the
   one symbol left external (`Run.cpp:187-192`), and the module has no
   constructor or appending global that a member could hold unreferenced,
   since the runtime's reader refuses them (`ReadRuntime.cpp:143-164`) and
   the lowering writes none (*read*, a search of `foreign/idr/lib`). The
   relink kit 0001 describes is then that archive. The tests that read the
   `-c` output with `llvm-nm` (`tests/idr/e2e/hello.mlir:2-3`,
   `tests/lib/heap.sh:57-68`) read an archive and subtract what its other
   members define (L8).

### 5.4 Two steps

- **S2, first, and the step the cutover builds:** keep the whole-module O3,
  then split only code generation, with the fixed bin size and our own
  partition. Almost nothing is lost, because code generation is per
  function after O3. *Decision* (D21): the split does not use
  `SplitModule`'s clone loop. That loop clones the module once per part
  (`SplitModule.cpp:281-296`), and each clone declares every global of the
  module (`CloneModule.cpp:66-84`), so its serial work grows with bins times
  module size: a cost set by the bin count, which this design keeps out.
  Instead the optimized module is written once as bitcode on the main
  thread; each bin's task reads it lazily in a fresh `LLVMContext`
  (`getLazyBitcodeModule`, `L/include/llvm/Bitcode/BitcodeReader.h:203`),
  materializes its own definitions, keeps every other symbol it references
  as a declaration and drops the rest, applies §5.3's linkage, and runs
  code generation with its own `TargetMachine`, the shape of the LTO
  backend's tasks (`L/lib/LTO/LTOBackend.cpp:528-548`). Objects are written
  in bin order. The serial part is one bitcode write.
- **Then, split before O3** (after the cutover), one context per unit,
  ThinLTO's shape without its summaries (*decision*: LLVM's summary-based
  importer would be a second inlining analysis beside ours, which the
  one-representation rule forbids). The units are cut on the lowered MLIR
  module by the same rule, with the same constant counted in its ops, and
  each is written as bytecode on the main thread and translated and
  optimized in an `MLIRContext` and `LLVMContext` of its own (D30). No two
  translations ever share an `MLIRContext`: upstream neither documents
  nor tests concurrent translation of sibling modules on one context
  (upstream-mlir-llvm §5), each translation needs its own `LLVMContext`
  anyway (`L/include/llvm/IR/LLVMContext.h:62-67`), and 0006 takes the
  same contexts for its codegen units (0006 D7), so no ThreadSanitizer run
  is needed to permit anything; S2 translates once, on the whole module,
  and the question does not arise there. The
  interprocedural facts LLVM would lose across units are emitted from our
  whole-program analyses as attributes on cross-unit declarations: memory
  effects, `nounwind` and `willreturn` from the effects summaries; `noalias`
  and `readonly` from exclusivity and borrows; `nonnull` and
  `dereferenceable` from layouts (codegen-partitioning §9). The tail-call
  plan is then decided on the parent module over every unit's functions and
  applied per unit, with §5.3 item 4's rule.

What Mojo does here, for reference (mojo §1): it splits the LLVM module per
exported root with transitive callees (`LLVMIRUtils.cpp:301-420`), optimizes
each split in its own context, splits again per function for codegen, and
links the machine functions back with an `MCLinker` that needs a non-upstream
LLVM patch and reaches into LLVM's private members (`LLVMAccessorHelper.cpp:
41-69, 150`, *read* in the full clone at `~/Documents/modular` at
`9211931`, not in the snapshot's 17 files). We take the shape and the LTO backend's pattern (a module as
bitcode, read in a fresh context per task), and never the linker (§8).

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
| `LoopBreakers`, and every fact and test that exists only for it: the inherent `break_last` on `idr.func` (`include/idr/IR/IdrOps.td:20, 36`; the pass descriptions that name it, `Passes.td:136, 256, 289`); the frontend's `BreakLast` purpose and its table column (`compiler/src/IdrisMLIR/Registry/Libraries.idr:5, 50-52, 60-78`) and Emit's writer (`Emit/Declarations.idr:51, 73`; the generated `Dialect/Idr.idr:354`); the copies made at `Isolate/Isolate.cpp:136` and `Inline/Prepare.cpp:129`; Deduplicate's comparison of it (`Deduplicate.cpp:192, 263`); the `no_inline` marks the pass writes; `idr-expect`'s `breaks-last` and `every-cycle-has-breaker` (`Passes.td:783-788`; `Expect/BreaksLast.cpp`, `Expect/EveryCycleHasBreaker.cpp`) and their tests (`tests/idr/expect/breaks-last.mlir`, `breaks-last/run`, `breakers.mlir`, `tests/idr/loops/breakers.mlir`, and the properties in six `tests/programs` `mlir.expect` files) | `Simplify/LoopBreakers.cpp:15-20` | Inlining repeats across rounds and must not unroll a cycle | Recursive SCC members are never inlined into each other; the bottom-up order needs no marks, so nothing reads `break_last` after the cutover. Owners: L1 the frontend's purpose, column and writer; L5 `IdrOps.td` and the generated module; L3 the pass and its readers in `Inline/`; L2 Isolate's copy; L6 Deduplicate's comparison; L8 the two properties and their tests |
| `RoundFacts` | `Simplify/RoundFacts.cpp:6-15, 39-43` | A nested pass manager drops module analyses, so facts are recomputed before every nest | Each fact gets one home, as 0006 D20 decided (§4 stage 6): `Holds` a type fact frozen before the optimizer; `Identities` a stage-9 summary whose greatest fixpoint is taken inside each SCC; `BindingTimes` per SCC from its own bodies when it is ready; `CloneTable` gone with the key-named nodes; the symbol table the ready-set driver's |
| The `CloneAttr` self-reference and its special cases | `include/idr/IR/IdrAttrs.td:232-243`; `Analysis/LabelSites.cpp:118-122`; `Transforms/Ownership/Rc.cpp:70-73`; `Deduplicate/Deduplicate.cpp:316-320` | A clone names itself so that SCCP, dead-code analysis and RDV treat it as having unknown callers that later rounds fill | No rounds: a clone is an ordinary private function made once, named from its key |
| `unsupported (compile-time budget)` from the rounds and from specialization | `Simplify.cpp:207-209`; `Simplify/Scc.cpp:96-98`; `Specialize/Clones.cpp:30-33`, with `kClonesPerOwner`'s comment (`include/idr/Analysis/Specialize.h:56-59`) and the pass descriptions (`Passes.td:178, 599-602`) | Assertions about the optimizer's termination reported as rejections of the user's program | Budgets stop optimizing; a broken termination argument is an internal error (§2.5) |
| The closure analysis's unknown element, `labelsFor`, the sealing cascade, `escapes`, `unsupported (runtime closure)` and `unsupported (laziness)` | `include/idr/Analysis/Labels.h:55`; `LabelSites.cpp:92-114`; `Defunctionalize/Decide.cpp:97-184, 158-164, 204-219`; `Defunctionalize/Pass.cpp:43-50, 96-101` | A gap in what the analysis follows becomes unknown, and unknown spreads | Closed world, one flow interface, the forced anchor, no unknown (§2.2) |
| `isFollowed` and the second flow table | `Defunctionalize/Moves.cpp:27-79, 209-247` against `Analysis/Labels.cpp:68-123` | Closure flow decided twice, and the two disagree on `cf.br` | One flow interface read by both |
| `unifySuspensions` and Isolate's evaluated-delay branch | `Moves.cpp:147-206, 37-38`; `Isolate/Isolate.cpp:80-86` (43a9e235) | An evaluated delay's yield becomes unknown | The forced-state anchor keyed by the lazy value's type |
| `idr-isolate`'s region round trip | Emit's `idr.lambda`/`idr.delay`; `Isolate/Isolate.cpp` | Emit writes regions that the first pass outlines | Emit writes the symbol form (§4.1) |
| `idr-rc{reuse,sink}` | `Passes.td:668-671`; `lib/Transforms/Pipeline.cpp:119-120` | Measurement toggles | None; a comparison is two binaries |
| `--without`, the Sink/Build/Names classes, `pipelinePassNames`, the demand-against-without usage error | `lib/Driver/Options.cpp:46-50`; `lib/Driver/Run.cpp:80-104`; `Pipeline.cpp:29-89, 182-187` (44495199) | Turning passes off from the command line, then reconciling two toggles | `idris-mlir-opt --pass-pipeline` for experiments; the compiler has one pipeline |
| The strings `"reuse"`, `"sink"`, `"in-place"` | `Run.cpp:83-85`; `Pipeline.cpp:119-124` | Toggles matched by name | Gone with the toggles |
| `--demand-in-place`, `idr-demand{in-place}` | `Passes.td:696`; `Options.cpp:53-57`; `Pipeline.cpp:123-124`; `tests/lib/e2e.sh:38, 64`, `tests/lib/profile.sh:38, 47`, `tests/lib/compile.sh:5`; documented at `tools/compile.sh:12` | The command line decides whether a program is rejected, which makes two languages | The promise is a fact of `mlir-linear`'s types ("rebuilt in place, exclusive"), emitted by the frontend; `idr-demand` checks it every time |
| `--dump-dir` | `Options.cpp:66-69`; `lib/Driver/Dump.cpp`; its readers in `tests/`: `tests/lib/determinism.sh:19, 80`, `tests/lib/e2e.sh:71`, `tests/lib/timing.sh:33`, `tests/lib/mlir.sh:36`, `tests/lib/compile.sh:6`, `tests/idr/pipeline/steps.mlir:2, 11`, `tests/idr/pipeline/timing/run:31`, `tests/idr/e2e/eval.mlir:2`, `tests/idr/obs/debug-counter.mlir:2, 5`, `tests/idr/tail-calls/mutual.mlir:2, 7`; documented at `tools/compile.sh:13` | Per-pass dumps | Upstream `-mlir-print-ir-tree-dir` (`M/lib/Pass/PassManagerOptions.cpp:61`), which `Run.cpp:118` already enables; L8 moves every test reader to it, L4 the documentation |
| `-mlir-debug-counter` in the compiler | `lib/Driver/Main.cpp:99`; the action handler at `Run.cpp:277-287`; `include/idr/Support/Actions.h:3-7`; `tests/idr/obs/debug-counter.mlir`, `debug-counter/run` | A counter that skips actions changes the output (the test skips every `idr-specialize-clone` action), so the compiler has a behaviour-selecting option beside its one pipeline | *Decision:* `idris-mlir` registers no debug counter; `idris-mlir-opt` keeps upstream's, where experiments already live (`--pass-pipeline`), and the test moves there (L4 the registration, L8 the test). The actions stay, observed by `--log-actions-tags` |
| `idr.stack` as a discardable attribute | `include/idr/IR/IdrBase.td:58`; written at `Transforms/Stack/Stack.cpp:62-96`; read at `Analysis/Ownership/Reuses.cpp:163, 194` and `Analysis/Ownership/Exclusivity.cpp:116` (through a `StackAttrHelper` each holds, `Reuses.cpp:67, 253, 275`, `Exclusivity.cpp:169`), `IR/OpsCon.cpp:38`, `IR/OpsClosures.cpp:107`, `IR/Verify/Owned.cpp:208` (through `include/idr/IR/Verify.h:139`'s member), `Conversion/Cells.cpp:52`; checked at `IR/Verify/Attributes.cpp:30-35` | A memory fact kept where a pass can drop it, after which idr-rc and idr-lower disagree about a cell | An inherent property of `idr.con` |
| `idr.program` as a discardable attribute | `IdrBase.td:58`; checked at `IR/Verify/Attributes.cpp:22-29`; removed at `Conversion/Lower.cpp:214-219`; written by the frontend (`Dialect/Idr.idr:30-33`) | Its presence alone turns on the module rules: one root of the two root types, every sum or box type naming a declaration of its kind, containment through unboxed sums acyclic, no knot (`Verify/Program.cpp:23-101`); dropping it disables them silently. (The research said it gates the stage and linearity rules too; it does not: those are each function's, run by `idr.func`'s region verifier with or without it, `Func/Func.cpp:81-93`, *read*) | The module rules run from the root's verifier, the root being the one public function (D28); the stage needs no marker, since each function's stage is already read from its own grades (`Verify.h:44-47`; D31) |
| Closure flow, canonicalization and effects each held several times | Canonicalization: `include/idr/Transforms/Canonicalize.h:33-37` against `Specialize/Clones.cpp:74` (default config, bottom-up, regions on), `Inline.cpp:143-153`; the pattern set collected at `Inline.cpp:86-94` and `Specialize/Specialize.cpp:89-101` besides upstream's canonicalizer; effects: idr-effects (`Analysis/Effects.cpp`, `Transforms/Effects/Effects.cpp`), `Defunctionalize/ByName.cpp:30-53`, `Clones.cpp:54-65` | Each pass built its own copy | One canonicalization configuration, one pattern set collected once; one effects summary (§4.9) |
| The lookup-dodging branches and the module-scanning declaration lookups | `IR/Canon/MatchPatterns.cpp:101-121`; `Canon/Eta.cpp:43-87`; `IR/OpsClosures.cpp:325-326`; the uncached scans through `IR/Symbols.cpp:51-62` (0768bc9f, 4d207761): `IR/OpsClosures.cpp:274, 326`, `IR/OpsCon.cpp:233, 250`, `Canon/MatchPatterns.cpp:114`, `Canon/MoveOut.cpp:66`, `Canon/Eta.cpp:83`, `Verify/Owned.cpp:56`, `Transforms/Tail/WhileDo.cpp:201` (*read*: nine, plus seven cached lookups through a `SymbolTableCollection` in `verifySymbolUses`; the research counted 20) | `!idr.data<@T>` keeps its constructors in a symbol, so a pattern scans the module to read a type | Types that carry their declaration: identified types with bodies, as LLVM's identified structs carry theirs; a pattern reads the type (D29, §4 stage 1) |
| `listElement`'s "any two-field constructor is the cons" | `IR/Symbols.cpp:65-72` | The list's role guessed from its shape | The declaration carries the role as a type fact |
| Deduplicate's refusal of functions with an `instance` fact | `Deduplicate.cpp:183-195, 322-331` | `idr-expect` looks functions up by provenance name, so a test API constrains an optimization | `idr-expect` finds functions by structure and facts, not names |
| Names from counters and module order | `.lam<n>`/`.delay<n>` (`Isolate.cpp:124-125`); `.capture<n>` (`Inline/Prepare.cpp:126`); `.spec<n>`/`.raise<n>` (`Clones.cpp:40-41`); `fn$<n>`/`lazy$<n>` by first appearance (`Defunctionalize/Decide.cpp:188-198`); `.acc` (`Tail/Accumulate.cpp:119`), `.trmc` (`Tail/Trmc.cpp:167`) and `.excl` (`Ownership/Specialize.cpp:51`), whose collisions the symbol table renames in insertion order; the frontend's `'n` repeats on keys that print alike (`compiler/src/IdrisMLIR/Emit/Index.idr:21-60`); the lowering's static-data globals `__idr_msg_`, `__idr_caf_`, `__idr_box_`, `__idr_str_` and `__idr_big_` numbered by one counter in creation order (`Conversion/StaticData.cpp:42, 189, 246, 276, 315`), which at §5.4's second step reach other units | Creation order reaches output | Names from keys: the owner and a hash of the structural key, at D18's width; instance symbols by 0008 §4.10's rule, the printed key followed by the low 64 bits of the identity hash where the print drops part of the identity (§4 stage 1); static data under the reserved prefix `__idr.` (§5.3 item 3), named by the hash of its content. Owners: L1 the frontend's, L2 `fn$`/`lazy$`, L3 `.capture`/`.spec`/`.raise`, L9 `.acc`/`.trmc`/`.excl` and static data |
| The driver's decision by message prefix `"unsupported ("` | `Run.cpp:248-254`; `tests/upstream-idris/common.sh:115-127`'s `rejection_skip`, which matches the same text | A refusal recognized by its text | A refusal carries its rule as structured data on the diagnostic, which the driver reads (D42), and `rejection_skip` reads the rule (L8). The four parts of a precise rejection the owner asked for (what was found, where, why, what form compiles) are fields 0002 adds to this data after the cutover, since they change the reject tests' expected text, which D42's proof holds fixed (0002 D17) |
| The test hook `--break-shape` | `lib/Driver/Options.cpp:41-45`; `Compile.cpp:41-42`; `Main.cpp:160`; the frontend's own option, `compiler/src/IdrisMLIR/Frontend/Driver.idr:17, 87, 110, 118, 140-142, 178-179, 188, 273-275`; `Frontend/Resolve.idr:216-230`; `Frontend/Program.idr:93-99, 142-144`; its tests, `tests/registry/broken-entry/run:3, 14`, `string-iterator/run:4, 13`, `base-surface/run:9-18` and `tests/compiler/frontend-command-line/run:70`; documented at `tests/lib/compile.sh:6` and `tools/compile.sh:13` | A hidden option makes the frontend break a registry entry so that the registry tests can see the validation refuse it: a behaviour the compiler has only for a test | The tests give the validation an input it refuses (D43); the research's inventory missed this option |
| `idr-rc`'s exclusivity loop | `Transforms/Ownership/Rc.cpp:79-99` | Bounded by the number of calls, with an internal error if it "did not settle" | Each function's grade contexts computed as a key set first, then each copy made once |
| `InBounds/Empty.cpp` | `Transforms/InBounds/Empty.cpp` | Integer emptiness reimplemented because upstream's exact search was slow (qsort, 180 s) | An upstream Presburger patch with its reproducer (§7); the in-bounds stack itself goes in 0003's purge, and the patch stays carried until the pin carries upstream's fix (AGENTS.md) |
| `Frontend/Translate/Prof.idr` | `compiler/src/IdrisMLIR/Frontend/Translate/Prof.idr:58-66, 224, 240-313`; `compiler/idris-mlir.ipkg:42` | A profiling module "never committed", committed with e569ea3f: eight environment variables, five behaviour toggles, global IORef memo tables; nothing imports it | Deleted |
| The `$world` rename and the hole sentinel | `Translate/Programs.idr:182-194`; `Translate/Closed.idr:173, 287-295, 471-476` | Binder facts keyed by (name, span); a marker name captured by Idris's normaliser | Binder identity; open-term normalisation under an environment that binds the holes (§4.1) |

**The pass registry after the cutover** (*decision*, one shared
declaration the packet fixes; `include/idr/Transforms/Passes.td`, L4's).
A registered pass is an entry for `idris-mlir-opt` and the tests, never
a second path: an entry survives only where it is one stage or one step
of the one pipeline. Test files that name each pass today (*measured*, a
search of `tests/` at ccaba89c) are given so L8 can size its work.

| Pass today | After the cutover | Tests naming it |
| --- | --- | --- |
| `idr-simplify` | deleted; stages 6 to 9 are one module pass, `idr-optimize` (the ready set, its decisions, the inner pipeline, the specialization nodes and the summaries), and its tests run that | 50 |
| `idr-inline`, `idr-specialize` | deleted as passes of their own: their work is the ready set's, and a standalone pass of either would need a second driver to order its decisions; their tests run `idr-optimize` | 7, 30 |
| `idr-loop-breakers`, `idr-round-facts`, `idr-isolate` | deleted (§6) | 3, 3, 8 |
| `idr-redirect`, `idr-identity` | kept: steps of the inner pipeline, function passes `runPipeline` runs (§4 stage 6) | 2, 1 |
| `idr-contify` | kept as the argument of stage 5's contification, the pass replaced whole | 7 |
| `idr-effects` | kept: computes the one effects summary and writes the entries and call-site effects, the code stage 4 and the ready set call (D34, D38) | 18 |
| `idr-binding-times` | kept: its remark, computed per SCC as the ready set computes it (§4 stage 6) | 1 |
| `idr-deduplicate`, `idr-defunctionalize` | kept: stages 3 and 4 | 2, and the defunctionalization suite |
| `idr-in-bounds`, `idr-vectorize`, `idr-narrow-lanes` | kept until 0003's stage 1 replaces them (0003 §15) | |
| every other pass | kept as today | |

**Upstream patches that lose their only site.** 02 (`sccp` re-makes
constants), 16 (RDV rebuilds unchanged calls) and 22 (RDV re-poisons
operands) were found because the composite's fingerprint loop reads
"the module prints the same, but OperationFingerPrint changes" as a change
(`PINS.md:108-152, 335ff`, casework-audit §1.B). With the loop gone our
code no longer meets them, but the bugs are still in the pinned LLVM.
*Decision* (D23): each stays carried, its `llvm.patch`, `tests/upstream`
check and PINS entry unchanged, until the pin moves past upstream's fix,
as AGENTS.md binds ("a patch goes when the pin moves past upstream's
fix") and `upstream/README.md`'s retirement rule says ("The patch stays
until the pin moves past the merged commit"). The earlier text dropped
them at the cutover, citing 08 and 17 as precedent; those two were never
carried at all (`upstream/README.md:36-37, 82`), so they are none. PINS.md's
entries for the three are restated by L6 to say that nothing in the tree
reaches the bug after the cutover, which is a fact of the entry, not a
reason to drop it.

**Kept:** `--num-threads` (a resource; output does not depend on it);
`--time-trace` and `--log-actions-tags` (observation, which changes no
output byte: profiling is LLVM's time trace, 0002 D8,
`include/idr/Support/Profile.h:3-10`); the driver's inputs and outputs
(`-o`, `-c`, `-p`, `--package-path`, `--prefix`, `--no-prelude`, and the
build-recorded `--runtime` and `--runtime-bitcode-section`) and its other
actions (`--prepare-runtime` and the `--print-*` queries,
`lib/Driver/Options.cpp:70-118`), none of which selects how a program is
compiled; `idr-expect{holds}` (a test API); IntRange per function
(5d3318fb); labels in one walk (6a7841dc), whose `labelsFor` goes with
unknown; the upstream/23 CSE statistics patch; the call-site `effects`
cache, written once (§4.9); code-quality thresholds (inline 40/60/320,
`lib/Analysis/Inline.cpp:23-25`; `kUnrollLimit` 32; stack 256/1024/64,
`Passes.td:543-544`; the in-bounds branch budget 512,
`InBounds/Empty.cpp:86`, which becomes the bound idr-in-bounds passes to
the Presburger patch of §7 until 0003's stage 1 deletes the pass and its
bound, the patch staying carried until the pin carries upstream's fix),
which are fine once they can no longer change acceptance (casework-audit
§1.C).

## 7. Upstream first

The four upstream changes the research named (upstream-mlir-llvm §8),
re-evaluated against this design (*decision* for each verdict):

- **The adaptor's preserved-set intersection** (an adaptor preserves nothing,
  `M/lib/Pass/Pass.cpp:619, 1183-1186`, and every nested pipeline clears its
  analyses, `:673-679`). Remains useful: the units read stage facts computed
  by a module step, and the inner pipeline runs through `runPipeline`. Taken
  when the post-cutover record shows analysis rebuilds above 5% of the
  optimizer segment's wall, 0006 §10's part-of-wall rule.
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
6. Later, a DAG-parallel CGSCC traversal for upstream's inliner (mojo §7),
   sent once the cutover meets §10's optimizer threshold on stage 0,
   which is when our driver's shape has proved out.

## 8. What we take from Modular

Ranked (mojo §7). Port means the file comes over under proposal 0001's
protocol; rebuild means the design comes over and the code is ours.

| Rank | What | Port or rebuild | Size | Replaces in our tree | Dependencies |
| --- | --- | --- | --- | --- | --- |
| 1 | The SCC ready-set scheduler (`Mojo/include/Mojo/TransformUtils/SCCUtils.h:60-170`: atomic counters per SCC, a worklist inside each SCC, bottom-up rewrites) | Rebuild on our `Scc.h` and MLIR's thread pool | 150 to 250 lines | `Simplify.cpp` (383), `Round.cpp` (79), `Scc.cpp` (112), `RoundFacts.cpp` (48), `Trace.cpp` (49), every module fingerprint | none beyond MLIR; not `CallGraphUtils.h`, whose parallel build makes caller order nondeterministic (`CallGraphUtils.h:160-198`) |
| 2 | Inline then pipeline once, per function (`AutomaticInline.cpp:380-501`) | Rebuild | about 350 lines of ours, on the design of `AutomaticInline.cpp:380-501` (no line of its 715 is copied, 0001 §1) | `Inline/Inline.cpp` (324): InlineCleanup, the seed marks, the cycle guard, the use of upstream's inliner driver | upstream `mlir::inlineCall`; per-thread `OpPassManager` copies run by `runPipeline` (`M/lib/Transforms/Utils/Inliner.cpp:526-567`), keeping the verifier and instrumentation that Mojo's `PerThreadPassManagers` turns off (`InliningUtils.cpp:285-322`); our decision rule with the caller cap and the bounded local loop of §4.6 |
| 3 | Specialization as demand-driven nodes (`Elaborator.cpp:1675-1693, 1746-1756, 2944-2989`) | Rebuild | part of the ready set | `idr-specialize`'s generation loop and the mutable `CloneTable`; `RedirectPass`'s per-function rewrite stays as the inner pipeline's redirect step, reading the node table (§4 stage 6) | names from the key (not `Clones.cpp:20`) |
| 4 | EliminateDuplicateFunctions (`Mojo/lib/Transforms/EliminateDuplicateFunctions.cpp`, 301 lines) | Port nearly whole | about 300 lines | `idr-deduplicate`'s "left for a later run" (`Deduplicate.cpp:20`) | our rules for which uses may be renamed and our fact comparison; deleted when upstream's generalization lands (§7) |
| 5 | The parallel code generation baseline (`ObjectCompiler.cpp:540-606, 858-897, 1178-1243`) | Rebuild on the LTO backend's pattern (the module written once as bitcode, each bin read lazily in a context of its own), not `SplitModule`'s clone loop (D21) | about 150 lines in `lib/Driver/Artifacts.cpp` and `lib/Target/` | the one-module codegen (`Run.cpp:164-201`) | `splitPerExported` (about 300 lines) only if per-partition optimization is wanted, at §5.4's second step |
| 6 | Bottom-up SCC summaries (the SCCGraph pattern of IPDF, InferFunctionAttrs, ArgPromotion; `DeadArgumentElimination.cpp`, 695 lines, as a reference) | Rebuild | with §4.9 | module SCCP per round; three effects computations | upstream's dataflow solver |

**Never comes:** AsyncRT (16,114 lines; its includes reach
`Support/max_license/Tracy/Tracy.h`, which the open export lacks, so it does
not compile from the tree; *read* in the full clone at
`~/Documents/modular` at `9211931`, not in the snapshot; MLIR's thread
pool suffices); MCLinker and
`LLVMAccessorHelper` (a non-upstream LLVM patch and private members, against
AGENTS.md's upstream rule); `PerThreadPassManagers` (upstream has the pattern,
and Mojo's turns off the verifier); the Canonicalizer (our configuration
already matches: region simplification off, `Canonicalize.h:33-37`; the lesson
is where it runs); `Cache/` (about 1,000 lines): 0006's S9 rebuilds its
design, content-addressed blobs, on `llvm/Support/xxhash.h` in about 200
lines (0006 D15, D16), so no line of it is ported.

**Licensing steps** (0001 §1, §3, §4; mojo §6). Every Modular file is
Apache-2.0 WITH LLVM-exception, and every C++ and TableGen file under
`Mojo/lib`, `Mojo/include`, `Support/`, `AsyncRT/` and `Cache/` carries
Modular's header: 968 `.cpp`, `.h` and `.td` files, 984 with the `.inc`
and `.def` files beside them, none without it (*measured* by 0001 §2 at
`9211931`; mojo §6's 981 counts by a rule the report does not state).
The repository has no NOTICE; `Licenses/` is the MAX Community License
for shipped products and does not travel with the source. A ported file
keeps Modular's header verbatim, gains an SPDX line and a changes line,
and gets a PINS.md entry naming its source path and `9211931` (0001 §4;
whether the changes line also names them is 0001's open question, whose
default keeps them in PINS.md alone); the licence text is already in
`LICENSES/`. Modular builds against LLVM `8d4fc8f1` with its own patches; both
trees use the `Op::create(b, ...)` builders, and the API distance is measured
per file at port time. `Support/HashUtils`' external xxhash (BSD-2) is
replaced with `llvm/Support/xxhash.h`. Earlier drafts of this file cited
Modular at `4b0d20f`; 0001 has since been re-read at `9211931` (0001 §2),
and every Modular line number in both files is `9211931`'s.

## 9. Ready for sharding

Every unit of this design is 0006's unit, so 0006 consumes it unchanged
(casework-audit §3). Four rules 0006 decided are rules the cutover itself
runs, so they are taken here and 0006 points at them: the clone budget
per requesting node (0006 D5; §4 stage 8, D39), `calls(f)` frozen with
one call per specialization request (0006 D11; §4 stage 7, D14), the
name hash and its width (0006 D16; §4 stage 1, D18) and the homes of
RoundFacts' facts (0006 D20; §4 stage 6, §6).

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
- **The ready set is 0006's phase 3.** The cutover drains it with MLIR's
  thread pool in one process and merges in canonical order, so one
  thread and many write the same bytes (stage 6; 0006 S7, taken by L3).
  Sharding swaps the scheduler and keeps the one `MLIRContext` for every
  stage up to lowering, codegen units taking contexts of their own (0006
  D7, this file's D30); per-worker contexts for the stages before
  lowering come only by 0006's S6 rule. Nothing here is redone there.
- **The codegen bins are 0006's codegen units** (0006 §3.4, D4), with the same
  rule: a pure, edit-stable function of content, independent of the shard count.

## 10. The cutover plan

**Where it runs.** On the owner's machine, which builds the toolchain and runs
every suite; each lane integrates only with `make build`, `make check`,
`make test`, `make test-idr` and `make test-mlir-tools` green there, and with
`tests/determinism` at 1, 2 and 8 threads. This machine checks only
`make typecheck` and `make check`.

**Lanes,** each owning its files outright. Paths are under `foreign/idr/`
unless named. Every file a stage of §4 or a row of §6 changes has exactly
one owner below (*decision*): a lane that needs a line in another lane's
file lists it in its work, and the owner writes it in the same
integration. The two files every pipeline change touches,
`lib/Transforms/Pipeline.cpp` and `include/idr/Transforms/Passes.td`, are
L4's on that rule, and so are the build lists every lane's sources sit
in, `lib/Transforms/CMakeLists.txt`, `lib/Analysis/CMakeLists.txt` and
`include/idr/Transforms/CMakeLists.txt` (a lane lists its lines, as for
`Pipeline.cpp`). A lane owns the `include/idr/` headers that mirror its
`lib/` paths (`include/idr/Transforms/Simplify.h`, `Inline.h`,
`Specialize.h`, `Effects.h` and `Identity.h` are L3's; `Isolate.h` and
`Defunctionalize.h` L2's; `Deduplicate.h` L6's; `Demand.h`, `Pipeline.h`
and `include/idr/Driver/` L4's; `Expect.h` L8's; `Ownership.h`,
`Stack.h`, `Tail.h`, `InBounds.h`, `Narrow.h`, `Vectorize.h` and
`include/idr/Conversion/` L9's; `include/idr/Target/` L7's), with two
named exceptions: `include/idr/Transforms/Canonicalize.h`, the one
configuration, is L3's, and `include/idr/Support/` is L3's (`Scc.h`,
which the ready set reads; `Profile.h` and `Actions.h` change only where
L4 lists a line). The swarm packet turns this table into its
disjoint-write table and its validator.

| Lane | Owns | Work | Proof |
| --- | --- | --- | --- |
| L0, the baseline | `bench/profiles/`, `/tmp/f0/` | Run the old binary's defunctionalize on the round-16 module and record directive.lam4's op and key (§2.6); time-boxed timings of the old pipeline from the saved post-contify module; the old binary's `--demand-in-place` run over the 27 programs that load `mlir-linear` and make no promise, 22 tests and five bench programs (§2.9); G1's run before the cutover on the same commit (0002 §3, D14): the bench and `tests/compile-times.sh` on both targets, the baselines §10's 5% and 2% compare against, each record committed under `bench/profiles/`; keep the modules and the commands that regenerate them | committed records, one old binary named by all of them |
| L1, emission | `compiler/src/IdrisMLIR/`: `Emit.idr`, `Emit/`, `Frontend/`, `MLIR.idr`, `MLIR/`, `Registry/`; `compiler/idris-mlir.ipkg` | Symbol-form closures and suspensions, an evaluated one as `idr.delay %value` (D37); names from content at D18's width, with the plain-Idris XXH3-128 checked against its published test values; instance symbols injective by 0008 §4.10's rule, the `'n` repeats deleted (`Emit/Index.idr:21-60`; 0006 S1); every hook applied below its arity eta-expanded in symbol form, so the partial application is a closure whose body is the saturated call (0002 D18; §4 stage 1); binder identity (no `$world`, no hole sentinel); data types written as identified types with bodies (D29) and the in-place fact from the registry (D19); the bytecode writer (D36); no `idr.program` written (D28); no `break_last` written and the `BreakLast` purpose and column deleted (§6); delete `Prof.idr` and the frontend's half of `--break-shape` (D43); 0011 feature 2's request-chain rule (0011 D4), deleting `instanceBudget`, its `compile-time budget` rule and `checkComponent`'s blanket refusal (D40) | corpus emits; the programs whose acceptance changes listed, each accepted with its expected output or refused naming its growth; every program's expected output unchanged; the bytecode read time recorded against the 11.7 s text parse |
| L2, total defunctionalization | `include/idr/Analysis/Labels.h`; `lib/Analysis/Labels.cpp`, `LabelSites.cpp`; `include/idr/Transforms/Defunctionalize.h`; `lib/Transforms/Defunctionalize/` but `ByName.cpp`; `lib/Transforms/Isolate/`; the flow interface's own files (new: `include/idr/IR/IdrFlow.td`, `lib/IR/Flow.cpp`) | The flow interface (D8), the forced-state anchor (D9), no unknown (D10), the external and escaping cases of the label analysis deleted (D7), MLton's representation choices (D12), `fits` as an assertion (D27), the sums made after the effects summary with D29's bodies (D34), the per-function conversion, placement after deduplication (D11); `idr-isolate` deleted once L1 writes the symbol form; the list of ops that declare the interface, for L5 | every former source of unknown has a fixture that now converts; the grade fixtures (§2.9); the corpus and stage 0 pass the verifier; the solve under 10 s on stage 0; per-key constructor counts, post-optimizer dispatch counts and the largest boxed closure sum recorded on stage 0 (§2.5, §2.8); suites green |
| L3, the first-order optimizer | `lib/Transforms/Simplify/`, `Inline/`, `Specialize/`, `Effects/`, `Identity/`; `lib/Transforms/Defunctionalize/ByName.cpp`; `lib/Analysis/Inline.cpp`, `References.cpp`, `BindingTimes.cpp`, `Specialize.cpp`, `Effects.cpp`, `Holds.cpp`, `Identities*.cpp` with their headers; `include/idr/Transforms/Canonicalize.h`; `include/idr/Support/`; the constants summary (new) | The ready set as `idr-optimize` (D13; §6's registry table); decisions with the caller cap (D14, D25), `calls(f)` frozen with one call per specialization request (§4 stage 7); the inner pipeline once and the bounded local loop; one canonicalization configuration and one pattern set collected once (§6); specialization nodes (D15), the clone budget per requesting node (D39); the homes of RoundFacts' facts: `Holds` frozen, `Identities` a stage-9 summary per SCC, `BindingTimes` per SCC when ready (§4 stage 6); contification (§4 stage 5); the effects summary with its observable bit, first called by L2's pass (D34), and the constants summary (D16); call-site effects written once, at the caller's readiness for callees outside its SCC (D38); dead values once; delete the rounds and every row of §6 that §4 deletes, LoopBreakers and its readers in `Inline/` among them, and `SimplifyInstrumentation`'s registration in `Run.cpp:120` and `tools/idris-mlir-opt.cpp` (L4 writes those lines) | suites green; stage 0's optimizer under the threshold below; D25's record; the calls left after the optimizer, old binary against new, on the corpus and stage 0 (§4 stage 9); determinism 1/2/8 |
| L4, the driver and options | `lib/Driver/` but `Artifacts.cpp`; `lib/Transforms/Pipeline.cpp`; `include/idr/Transforms/Passes.td`, `Demand.h`, `Pipeline.h`, `CMakeLists.txt`; `include/idr/Driver/`; `lib/Transforms/CMakeLists.txt`, `lib/Analysis/CMakeLists.txt`; `lib/Transforms/Demand/`; `tools/idris-mlir.cpp`, `idris-mlir-opt.cpp`, `idris-mlir-reduce.cpp`; `tools/compile.sh`; `bench/README.md` | Delete `--without`, `--dump-dir`, the toggles, `--demand-in-place` (idr-demand then reads the type fact) and `--break-shape` (D43), and the debug counter's registration in `idris-mlir` (`Main.cpp:99`, kept in `idris-mlir-opt`); structured refusals (D42); the pass registry of §6's table; the pipeline's order as §4 gives it, written as each lane lands its stage; `tools/compile.sh:12-13` and `bench/README.md`'s ablation section (`:156` on) restated without the deleted options | suites green; no option selects behaviour (a spec check over `Passes.td` and `Options.cpp`) |
| L5, IR facts | `include/idr/IR/` and `lib/IR/` but L2's flow files; `tools/idris-mlir-tblgen.cpp`; `compiler/src/IdrisMLIR/Rule.idr`, `Dialect/` and `Syntax/` (generated from L5's ODS, checked by `tests/spec/dialects-current`) | `idr.stack` inherent; the root as the one public function, the module rules from its verifier, no external `idr.func`, no `idr.program` (D28, D31); identified types with bodies and every lookup they delete, the `idr.data` and `idr.ctor` ops deleted, the generator taught the types for the Idris side (D29); `break_last` deleted from `idr.func` (§6); `listElement`'s role; `idr.delay %value` (D37); the call-site effects verifier checking equality (D38); the rule enum, its Idris `Rule` generated and `Rule.idr` deleted (D42); the interface declarations L2 lists; the generated modules regenerated | suites green; no discardable attribute declared (`IdrBase.td:58` empty) and no declaration lookup on a data type left in `lib/` (spec checks) |
| L6, ports and upstream | `upstream/`, `PINS.md`, `lib/Transforms/Deduplicate/` with `include/idr/Transforms/Deduplicate.h` | EliminateDuplicateFunctions ported (§8 rank 4), with the `instance` refusal and the `break_last` comparison deleted once L8's `idr-expect` finds functions by structure; 02, 16 and 22 kept carried, their PINS entries restated to say nothing in the tree reaches the bug after the cutover (D23); the Presburger patch that replaces `Empty.cpp` (L9 deletes the file and calls the patched API) and the region-simplifier report (§7) | `tests/upstream` green; `tests/spec/licenses` green |
| L7, code generation | `lib/Target/`, `include/idr/Target/`; `lib/Driver/Artifacts.cpp` | §5's partitioning (D20, D26, D41), dotless names in one namespace group (§5.3 item 2), and S2's split code generation (D21); the archive for `-c` (D32); tail calls (D33) and inline assembly checked on both targets; the call from `Run.cpp`'s LLVM half into it (L4 writes that line) | executables byte-identical at 1, 2 and 8 threads; bench compile times and each corpus program's bin count recorded; the edit fixture of D41 |
| L8, tests | `tests/`; `lib/Transforms/Expect/` with `include/idr/Transforms/Expect.h` | Delete the tests of deleted mechanisms: `tests/idr/obs/budget.mlir`, `round-failure.mlir`, `round-trace.mlir`, `tests/idr/specialize/budget.mlir` (it becomes a test that specialization stops and the program runs), `tests/idr/pipeline/steps.mlir`'s usage errors, the do-block A/B lines, the `--demand-in-place` fixture files with `tests/lib/e2e.sh:38, 64` and `tests/lib/profile.sh:38, 47`, the `breaks-last` and `every-cycle-has-breaker` properties and their tests (§6); move every `--dump-dir` reader to `-mlir-print-ir-tree-dir` (§6's row) and `tests/idr/obs/debug-counter.mlir` to `idris-mlir-opt`; restate every test that runs `idr-simplify`, `idr-inline` or `idr-specialize` on `idr-optimize` (§6's registry table), and brittle fixtures as properties; the 82 fragments with several public functions and the 15 files with bodiless functions rewritten for D28 before L5's verifier lands; the registry tests (`broken-entry`, `string-iterator`, `base-surface`) and `tests/compiler/frontend-command-line` on D43's fixtures; a fixture for a partially applied `castPtr` (0002 D18); `tests/upstream-idris/common.sh`'s `rejection_skip` reading the refusal's rule instead of its text (D42, 0002 §3); the `-c` readers of D32; `idr-expect` finding functions by structure and facts, not names; the name-stability edit fixture of 0006 S1 (one definition edited, every other symbol unchanged); the totality fixtures and the determinism checks at 1, 2 and 8 threads | the suites themselves |
| L9, memory and lowering | `lib/Transforms/Ownership/`, `Stack/`, `Tail/`, `InBounds/`, `Narrow/`, `Vectorize/` with their headers; `lib/Analysis/Ownership/`, `Escapes*.cpp`, `Ranges.cpp`, `Tail.cpp`; `lib/Conversion/`, `include/idr/Conversion/` | Stages 11 and 12: `idr-rc`'s grade contexts as a key set, each copy made once (§6); `.acc`, `.trmc` and `.excl` named from their keys, and the static-data globals named by content under `__idr.` (D18, §6); the readers of `idr.stack` on L5's property; the lowering per function, the runtime's declarations created up front from the decided set; `InBounds/Empty.cpp` replaced by L6's Presburger patch; the `isExternal()` tests of these passes deleted (D7) | suites green; determinism 1/2/8; the tail's timings on stage 0 recorded |

**Order:** L0; then L5's identified types and L1 together (they meet at
emission), with L8's fragment rewrite before L5's verifier; then L2; then
L3; then L4 and L6; then L7; L9 alongside L2 and L3 once L5's `idr.stack`
property has landed, since it shares no file with them; L8 alongside each.
After the cutover: §5.4's split before O3, then whatever the new record names
next (the giant-function tail if the caller cap leaves one; the frontend's
140 s and 9.1 GB, 0008's ground; the LLVM tail once measurable, 0006 S2).

**Measurement** (*decision*): old binary against new binary, two commits, two
builds, under identical conditions on performance cores, from a named saved
module (the post-contify stage-0 module and the round-16 module), time-boxed,
with a progress remark per finished SCC batch so that a run reports progress
instead of silence (the time trace is written only at exit,
`Support/Profile.h:29-33`, so it cannot report a killed run), and LLVM's
time trace for where the time went (0002 D8), one zone per ready-set node
and per codegen bin. A behaviour-selecting pass option is never a
measurement instrument.

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
- D7. Closed world is a verified invariant (no external `idr.func`, one
  public root), held by the verifier after every pass (§4 stage 2, D28).
  Reason: it removes the external and escaping sources of unknown (§2.2),
  and with them the `isExternal()` tests through the analyses.
- D8. One flow interface, read by the label analysis and the slots alike, and
  enforced by the verifier. Reason: closure flow had two tables that disagreed.
- D9. A forced-state anchor keyed by the lazy value's type. Reason: it removes
  the evaluated-delay gap and the lazy-return refusal.
- D10. `LabelSet` has no unknown element; reaching one is an internal error.
- D11. Defunctionalization runs right after deduplication, before the
  optimizer, MLton's order; the closed world it needs is the verifier's, not
  a step. Reason: every later pass is first-order, the call graph is
  complete, closure cases disappear (§2.7).
- D12. The label solve uses MLton's representation: first-order values carry
  no flow, hash-consed sets, union-find for mutable cells, difference
  propagation; under 10 s on stage 0.
- D13. The optimizer is one bottom-up ready set over call-graph SCCs, each
  function processed once after its callees are final, with a bounded local
  loop for calls its cleanup exposes. Reason: it deletes the round multiplier
  and the per-iteration cleanup together (§3.2, §3.4).
- D14. Inline decisions use MLton's per-function formula on the callee's final
  size, never inline a function on a cycle of calls (a member of an SCC of
  two or more, or one that calls itself), delete originals, and add a
  per-caller size cap. `calls(f)` is `f`'s call sites when the optimizer
  starts, frozen, and a specialization node counts one call per request
  (as 0006 D11 decided). Reason: the rule is right, applied once; a cycle's
  member could never lose its original; the cap bounds what single-call
  absorption builds; a count read when a node is final would be an
  arrival count under the pool (§4 stage 7).
- D15. Specialization requests are demand-driven nodes in the same ready set,
  named from their key. Reason: one scheduler, order-free names.
- D16. Interprocedural constants and effects are bottom-up SCC summaries
  through upstream's `visitExternalCall`; effects are computed once.
- D17. Budgets stop optimizing and never reject; `unsupported (compile-time
  budget)` is deleted from the C++ pipeline, and the frontend's instance
  bound with it (D40): after the cutover no count refuses a program.
- D18. Names are derived from content everywhere: the owner and the
  XXH3-128 hash of the structural key, LLVM's in C++ and a plain-Idris
  copy in the frontend checked against the published test values, a name
  carrying the low 64 bits as 16 hex digits and a collision an internal
  error (as 0006 D16 decided); instance symbols by 0008 §4.10's rule,
  which deletes the frontend's `'n` repeats; static data named by
  content under `__idr.` (§4 stage 1, §6). Reason: creation order must
  not reach output, and one width is what 0006's sharding needs.
- D19. Facts live in types and inherent properties: `idr.stack` inherent, the
  stage read from types, the in-place promise a type fact.
- D20. Codegen units are size-balanced bins of SCCs grouped by top-level
  namespace, cut by content hash, their count from size, never from threads.
- D21. S2 first (whole-module O3, then split codegen), built on the LTO
  backend's pattern, the module written once as bitcode and each bin read
  lazily in a context of its own, not on `SplitModule`'s clone loop, whose
  serial work grows with bins times module size (§5.4); then the split
  before O3 with whole-program facts as attributes on cross-unit
  declarations; no LLVM summary-based importer.
- D22. Measurement is by binary from a saved module, time-boxed and
  observable, on performance cores.
- D23. Upstream patches 02, 16 and 22 stay carried after the cutover,
  until the pin moves past upstream's fix; their PINS entries say that
  nothing in the tree reaches the bug any more (§6). Reason: AGENTS.md
  binds ("a patch goes when the pin moves past upstream's fix"), the bugs
  are still in the pinned LLVM, and 08 and 17, the earlier text's
  precedent, were never carried. This supersedes the earlier "no longer
  carried", which would have needed the owner to amend AGENTS.md.
- D24. From Modular: rebuild the ready set, the inline driver, specialization
  nodes, the codegen baseline and the summaries on its design; port
  EliminateDuplicateFunctions; never AsyncRT, MCLinker or
  `PerThreadPassManagers`.

The seven open questions of the earlier text are decided below: the
per-caller cap (D25), the bin size (D26), labels across grades (D27), the
stage marker (D31, with D28), types that carry their constructors (D29),
concurrent translation (D30) and polyvariance (D35). Each says how it is
checked. D45 to D48 close what the cross-proposal check of 2026-10-14
found the plan had left open: the pass registry, the debug counter, the
homes of RoundFacts' facts and the header's tag limit.

- D25. The per-caller size cap is 10,000 ops, counted as the inline
  formula counts (`References::ops`): calls are inlined in call-site order
  while the caller with the callee's final body stays at or under it.
  Reason: only single-call absorption builds a giant, the cost it protects
  is the greedy pattern work over one body, which one worker does
  serially, and 10,000 ops is about 2,000 times the emitted average and 2%
  of the emitted module (§4 stage 7). Checked in L3: the final size
  distribution and the calls the cap kept, on the corpus and stage 0,
  beside the bench's runtime threshold; a miss changes the constant in one
  commit.
- D26. The codegen bin target is 2^15 = 32,768 LLVM instructions, counted on
  the optimized module. Reason: a bin's fixed cost is per bin and its code
  generation linear, so bins are as large as balance allows; stage 0 is
  then more than thirty bins, every test program one, and MLton batches at
  the same 2^15 (§5.3 item 1). Checked at S2 on stage 0 and the bench: each
  bin's fixed cost under 5% of its code generation, read from the time
  trace's zone per bin; a miss changes the constant in one commit.
- D27. A label enters a key only along a declared edge, and the flow
  interface's verifier demands that every edge join two values of one
  carrier (the type without its outermost grade, as
  `SuspendOp::verifySymbolUses` reads it, `OpsClosures.cpp:212-213`), so a
  label always fits its key by the naming op's own verifier, and
  `Slots::fits` (`Keys.cpp:84-95`) becomes an assertion. Reason: the fit is
  then a fact of the IR, checked where the label is named, not a second
  comparison that can disagree with it. Checked by the grade fixtures of
  §2.9, with the linearity verifier after defunctionalization.
- D28. The root is the module's one public `idr.func`, as the module rules
  and the entry conversion already find it (`Verify/Program.cpp:24-31`,
  `Conversion/Entry.cpp:35-45`); no `root` property is added, since it would
  hold publicity twice. The function verifier demands a body of every
  `idr.func` and a root type of a public one; the module rules (one public
  function, the type rules, containment, knots,
  `Verify/Program.cpp:23-101`) run from the public function's verifier, so
  they hold on every module with a root and need no mark; `idr.program`
  goes. A module with no public function is a fragment and gets each
  function's rules only, as a module without the mark does today. Reason:
  the mark's only work is to turn the module rules on, and dropping it
  turns them off silently. Checked: L8 rewrites the fragments first (§2.9);
  a fixture with two public functions and no mark is refused; the corpus
  and stage 0 verify.
- D29. A data type is an identified type with a body set once, LLVM's
  identified-struct mechanism; the body is the declaration (constructors in
  tag order with field types and facts, the sum's kind, `instance`, the
  registry's role, the in-place promise), and the `idr.data` and `idr.ctor`
  ops go. An op names a constructor by name within its value's type; a sum
  defunctionalization makes names each constructor by its label, a symbol
  use of the label's function, which replaces the `labels` attribute;
  boxing is the value's type alone; a fact in a body is decided before the
  body is set (§4 stage 1). Reason: a pattern reads a type, never the
  module; the declaration is held once; the box flag stops being said twice.
  Checked: corpus output unchanged (L1); no declaration lookup on a data
  type left in `lib/` (L5's spec check).
- D30. No two translations share an `MLIRContext`. S2 translates once, on
  the whole module; at the second step each unit is written as bytecode on
  the main thread and translated and optimized in an `MLIRContext` and an
  `LLVMContext` of its own. Reason: upstream neither documents nor tests
  concurrent translation on one context (upstream-mlir-llvm §5), and a
  context per unit needs no such promise, which is the shape 0006 D7 takes
  for its codegen units. Checked at the second step by determinism at 1, 2
  and 8 threads and the time trace's share of the bytecode write.
- D31. There is no stage marker: each function's stage is already read from
  its own grades by `idr.func`'s region verifier (`Verify.h:44-47`,
  `Func/Func.cpp:81-93`), and the only thing `idr.program` gated was the
  module rules (D28). Reason: the earlier default's fallback, an inherent
  property of an op every module must hold, answered a case the code does
  not have. Checked by L5's spec check that the dialect declares no
  discardable attribute.
- D32. With `-c` the driver writes the bin objects, in bin-name order, as one
  archive at the path `-o` names, in LLVM's deterministic archive mode, for
  one bin too. Reason: ld64.lld merges no objects (`-r` is not
  implemented), and an archive link takes every bin, since all of them are
  reached from `main` and the module has no constructor or appending global
  (§5.3 item 6). Checked by the `-c` readers of `tests/` (L8) on both
  targets.
- D33. Tail calls stay inside a unit: the partitioner joins every `musttail`
  caller to its callee as it joins an SCC, and a `musttail` across bins is
  an internal error (§5.3 item 4). Checked on both targets by the
  `tests/idr/tail-calls` fixtures and a generated program over two bins
  whose cycles would overflow the stack without their tail calls.
- D34. The effects summary is first computed right after the label solve,
  over the call graph in which an apply calls every label of its key, with
  one bit beyond today's effects: whether an `ObservableIO` op is reached.
  Each memo sum is made with its `by_name` labels in its body, and
  `markByName`'s walk goes (§2.7). Reason: D29 sets a body once, and the
  graph is the one the conversion makes direct. Checked by the same
  `by_name` marks, old binary against new, both ways, and the laziness and
  output tests' bytes.
- D35. Polyvariance is not built. Reason: defunctionalization's
  acceptance never depends on it (§2.4; MLton's closure conversion is
  exact with it off, `xml/polyvariance.fun:433-436`), and from 0005's P4
  the send check reads the same 0CFA sets, frozen, so a change of
  precision would change which forks are accepted, a language change
  for a proposal of its own and never a bench decision (0005 §7.3);
  what it buys, smaller sets at
  higher-order call sites, specialization on a known constructor (§4 stage
  8) recovers after the solve, on demand, where MLton duplicates before it
  by an occurrence count; and it would grow the solve's input. MLton runs
  it by default (`control-flags.sml:1343-1348`), so this is a departure,
  checked by L2's per-key constructor counts and post-optimizer dispatch
  counts on stage 0 and the bench's runtime threshold (§2.8, §10). If the
  bench misses that threshold on dispatches over plural sets, polyvariance
  becomes a proposal of its own, a stage before the solve, never an option.
- D36. The frontend hands the driver MLIR bytecode, writing attributes and
  types as their assembly, so a recursive identified type names itself in
  text and is no cycle of section entries (§4 stage 1). Checked by the
  corpus's identical outputs and L1's record of the read time against the
  11.7 s text parse.
- D37. An evaluated suspension is `idr.delay %value`, with no region; it
  declares one edge, into the forced-state anchor of its lazy type, and
  `EvaluateDelay` goes with the region (§2.7). Checked by the laziness tests
  and `memo-shared-stream` and `stream-share`.
- D38. Call-site `effects` is written once per call: when the caller
  becomes ready, for a callee outside its SCC, which is final then; when
  the SCC is final, for a callee inside it; a call inlining brings in
  keeps the effects written in the callee's body. It is verified equal
  to the callee's, not contained in it, since after defunctionalization
  no closure is passed to a call (§4 stage 9). Reason: the inner
  pipeline's canonicalize and CSE read it, and a call without it may do
  anything (`IdrOps.td:59-61`), so writing it when the caller is final,
  as the earlier text had it, came after the one pipeline that could
  use it. Checked by the verifier on the corpus, and by a fixture in
  which a call to a pure callee whose result is unused is gone after
  `idr-optimize`.
- D39. `kClonesPerOwner` is a budget that stops specializing, not a check of
  the finiteness argument its comment names (`Specialize.h:56-58`),
  counted per requesting node: the distinct keys one node requests of one
  owner, in call-site order, an already-made key counted like a new one
  (as 0006 D5 decided; §4 stage 8). Reason: a finite set of static
  patterns can pass 1,024 in a large program, and termination rests on
  the binding-time rule and each key's node being made once (§2.5); and
  counted owner-wide as requests arrive, which call stays unspecialized
  would depend on the schedule. Checked by
  `tests/idr/specialize/budget.mlir` restated: the program past the
  budget compiles and runs (L8); and by determinism at 1, 2 and 8
  threads.
- D40. The cutover deletes the frontend's instance bound
  (`Instances.idr:38-39, 110-112`) and `checkComponent`'s blanket refusal:
  lane L1 lands 0011 D4's request-chain rule, which refuses only a chain
  of requests that grows and names the site and the growing value. Decided
  by the owner (2026-10-14): acceptance is a property of the program,
  never of a count, and the project holds it as a rule (AGENTS.md).
  Reason: a bound on instances refuses bounded programs by count, which
  is the defect this cutover removes everywhere else. The proof gains the
  named acceptance change of §2.5; the corpus and stage 0, already under
  the bound, are unchanged.
- D41. Codegen cuts and cross-unit linkage: within a namespace group, SCCs
  are taken in content-hash order, and an SCC of size s closes its bin when
  the bin holds at least B/4 and the SCC's hash, read as a fraction of
  2^64, is below s/B, or when the next SCC would take the bin past 2B (B
  being D26's target); a function or mutable global another unit
  references gets external linkage, hidden visibility, `dso_local` and a
  content-derived name under `__idr.`; an `unnamed_addr` constant used from
  several units is copied into each (§5.3 items 2 and 3). Reason: a cut depends only on its
  neighbours, so one edit moves few cuts, and no C symbol has a dot.
  Checked by determinism at 1, 2 and 8 threads and an edit fixture whose
  unrelated bins keep their members at S2, and their bytes from §5.4's
  second step, since a whole-module O3 may change any bin before it
  (0006 S2's proof).
- D42. A refusal names its rule as data: one rule enum declared in the
  dialect's ODS, its C++ from ODS and its Idris `Rule` generated by
  `idris-mlir-tblgen` beside `Dialect/Idr.idr`, which deletes the
  hand-written `compiler/src/IdrisMLIR/Rule.idr`; a C++ refusal is a
  diagnostic whose first argument is the rule's attribute, which the
  driver's handler reads instead of matching `"unsupported ("`
  (`Run.cpp:248-254`); the phrase is rendered from the enum in one place.
  After the cutover the C++ rules are `layout`, `uniqueness`, `cycle` and
  `runtime` (*read*, a search of `foreign/idr/lib`). Reason: the reasons for
  a rejection are one concept held in two places today. Checked by every
  reject test's expected text, unchanged, and a spec check that no
  `"unsupported ("` literal is left in `foreign/idr` outside that one place.
  The four parts of a precise rejection (what was found, where, why,
  what form compiles; the owner's request of 2026-10-10) are fields 0002
  adds to this data after the cutover, since they change the expected
  text this proof holds fixed (0002 D17).
- D43. `--break-shape` is deleted. The registry tests give the validation a
  module it refuses: a `--no-prelude` fixture whose own module defines a
  keyed name at another shape, for a definition entry and for a spec entry
  (`Builtin.replace`, `C:idris2_putStr`, as the tests break today). The
  validation reads only the loaded context and runs before translation
  (`Frontend/Program.idr:96`), so the shadowing module meets it first
  (*conjecture*: that Idris loads a fixture module of a base module's name
  under `--no-prelude` is checked by L8 before L4 deletes the option).
  Reason: D2; a test of a refusal is a refused input, not a compiler mode.
- D44. Every file the cutover changes has one lane that owns it, and a lane
  that needs a line in another's file lists it for the owner (§10): the
  build lists are L4's, a lane owns the `include/idr/` headers that
  mirror its `lib/` paths, `Canonicalize.h` and `include/idr/Support/`
  are L3's, and the generated Idris modules with `Rule.idr` are L5's.
  Reason: the swarm packet's disjoint writes are then a property of this
  plan, not a negotiation; the earlier text left the build lists, the
  headers and the generated modules without an owner.
- D45. The pass registry after the cutover is §6's table: `idr-optimize`
  is the ready set's one module pass; `idr-simplify`, `idr-inline`,
  `idr-specialize`, `idr-loop-breakers`, `idr-round-facts` and
  `idr-isolate` are deleted; `idr-redirect`, `idr-identity`,
  `idr-contify`, `idr-effects`, `idr-binding-times`, `idr-deduplicate`
  and `idr-defunctionalize` stay as entries of one stage or step each.
  Reason: a registered pass that runs part of the ready set alone would
  need its own driver, a second path; one that is a step of the one
  pipeline is a test entry and nothing more.
- D46. `idris-mlir` registers no debug counter; `idris-mlir-opt` keeps
  upstream's, and `tests/idr/obs/debug-counter.mlir` moves there. Reason:
  a counter that skips actions changes the output, so in the compiler it
  is a behaviour-selecting option (D2); experiments live in
  `idris-mlir-opt` (§6).
- D47. RoundFacts' facts get one home each: `Holds` a type fact frozen
  before the optimizer, `Identities` a stage-9 summary with its greatest
  fixpoint inside each SCC, `BindingTimes` per SCC when the SCC is
  ready, `CloneTable` gone, the symbol table the driver's (as 0006 D20
  decided; §4 stage 6). Reason: each fact then has the scope it
  quantifies over, and nothing is recomputed per nest.
- D48. The one representation limit the totality argument leaves is the
  runtime header's 2^16 tags for a boxed sum, refused as `unsupported
  (layout)`; L2 records the largest boxed closure sum on stage 0 (§2.4
  step 5, §2.5). Reason: it is a limit of the cell's representation,
  which 0009 records for every boxed sum (0011 D3), not a count of
  anything the optimizer does; lifting it is 0009's if a record names
  it.

**No question is left for the owner.** The one this section held,
whether the cutover takes 0011 D4 and deletes the instance bound, the
owner settled on 2026-10-14 (D40).

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
