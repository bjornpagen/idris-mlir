<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 design: one e-graph engine, written once, run by the elaborator and the optimizer

Status: written 2026-10-21 for D85, D86 and D87
(`proposals/0000-mlir-native.md:1218-1259`). D85 reversed D84's "one small
engine per side": the engine is written once. D86 chose its route: the
engine and its rules are written once in Idris, the specification
generator prints them as MLIR, the pinned toolchain's own MLIR and LLVM
passes compile that before idris-mlir is built, the result is linked
statically into the C++ tools, and the elaborator takes an Idris form
generated from the same source. D87 put a sparse tensor library first
(designed in `sparse-library.md`, beside this file) and left one question
here: does the C++ copy come from the generator (D86 as recorded) or from
idris-mlir compiling the engine in a bootstrap stage? This file is the
concrete design of D86's route (§1 to §6), the weighing of the two routes
D87 names (§7), what AGENTS.md still strains (§8), the options D86 did not
take, kept as a record (§9), and the one owner decision (§10).

Grounds: *read* (path:line), *measured* (a command named), *recalled*,
*conjecture*, *decision* (Dn, or a coordinator item). Ours at HEAD e96bb991
with the working tree's proposal and AGENTS.md; MLIR at the pin in
`.toolchain/llvm-project`. Nothing was built or run; the stage-2 toolchain
is not built on this machine (*measured*: no `.toolchain/llvm/bin/mlir-opt`).
Idris and MLIR below are sketches, never compiled.

## 0. In plain words

- **One engine** is one Idris source: the e-graph's tables, union-find,
  hash-cons, rebuild, rule matching, analyses' algebra, extraction,
  placement and the two schedules, written once as a *staged* program
  over D87's sparse library and a small machine of loops and tables, with
  the rules from the dialect's specification. `specgen` applies it twice:
  once printing MLIR (for the C++ optimizer), once printing Idris (for the
  elaborator). Both printings are committed under D67. Nothing of the
  engine is written twice; what each side keeps is its adapter to its own
  IR (C++ over MLIR's ops, Idris over Core's terms), which is the
  problem's, not a copy.
- **The build never waits on idris-mlir.** Stock Idris on Chez prints
  everything; the stage-2 `mlir-opt`, `mlir-translate` and `clang` that
  `make bootstrap` already installs compile the printed MLIR into an object
  before any C++ of ours is linked; idris-mlir links it like its runtime.
- **The boundary is tables the C++ owns.** The engine allocates nothing
  and has no global: the caller passes every buffer from its per-function
  arena, the node table's capacity is the budget, and the analyses whose
  meaning is C++ (D41's templates, upstream's interval transfer functions)
  are hooks the engine calls by link-time symbols the same header
  declares.
- **Two schedules, one engine, by type.** The elaborator can only run the
  *closing* schedule: its rules can merge but cannot make a node, so its
  closure is complete with no budget, and its result type has no "stopped"
  case. The optimizer runs the *exploring* schedule, which may stop when
  its table is full: less optimized, never refused.
- **D87's question.** The bootstrap stage (idris-mlir compiles the engine
  and links it into itself) is not an ordinary self-hosting stage: its
  first stage is a compiler without the engine (a second configuration of
  the compiler, or a stub), or its output is a seed only idris-mlir can
  regenerate; it also needs a C export of compiled Idris. Recommendation:
  the generator route, D86 as recorded. One owner decision (§10).

## 1. What "one engine" is under D86

| part | written | where it runs |
| --- | --- | --- |
| tables, union-find, hash-cons, rebuild, semi-naive matching, extraction, placement, the two schedules | once, the staged source (§2) | printed to MLIR (optimizer), printed to Idris (elaborator) |
| rules | once, the specification's rule language (`design/egraph.md` §3.1, kept) | specialized per rule into the printed MLIR; the elaborator's closing schedule has only congruence |
| an analysis's algebra (meet, its laws as erased proofs) | once, in the source | both printings |
| an analysis's `make` whose meaning is C++ (D41's domains; upstream's `InferIntRangeInterface`) | the C++ that already means it (D41, `proposals/0000-mlir-native.md:715-732`) | a hook the printed MLIR calls (§5.3); the elaborator has none (`egraph.md:901`, O7 needs no analysis) |
| which `sparse_tensor` op a library operation means | once, D87's library table (`sparse-library.md`) | read by the registry's `Faster` rows and by `specgen`'s MLIR printing: one table, two readers (coordinator item, §10) |
| the optimizer's adapter: numbering a function, classifying by the effect query, the skeleton, writing the extraction back as ops | C++, hand (`egraph.md` §2.1, §4.2 steps 1, 2, 7) | the open op set MLIR forces; essential |
| the elaborator's adapter: metas and Core terms to dense ids | Idris, in the fork | essential |

What is duplicated: nothing of the engine. Two printers exist (MLIR text,
Idris text) because there are two output languages; the Idris printer is
the one `specgen` already has for the frontend's builders (one-source
§6.3, `audits/p0/design/one-source.md:531-539`, *read*). They are held
together by printing one source, and checked by one set of committed
fixtures run through both printings (§6.3). This is what AGENTS.md asks
of a second copy: "Generate the second copy from the first, or delete it"
(`AGENTS.md`, "One thing, one representation", *read*).

## 2. The source: a staged Idris program

### 2.1 Why staged

`specgen` must print the engine, so the engine is a value `specgen` can
walk, not only a function it can call. The form (*decision*, coordinator,
open to review): the engine is written once as Idris functions polymorphic
over a *machine*, an interface whose operations are the loops, table reads
and writes, integer arithmetic, D87's sparse iteration, and hook calls.
`specgen` has two instances, each a printer: one builds MLIR, one builds
Idris. This is the tagless-final style of staging (*recalled*: Carette,
Kiselyov, Shan, JFP 2009): one source, several interpretations, no
interpreter and no deep AST with binders to maintain. Rules are static
data at print time, so the MLIR instance unfolds the matcher on each rule
into its own join loop: the first Futamura projection, which is how
Soufflé turns Datalog into C++ (*recalled*: Jordan, Scholz, Subotić, CAV
2016, stored at `sources/papers/jordan-2016-souffle/`, not re-read; its
union-find relation `eqrel`, Nappa et al., PACT 2019, *recalled*).

### 2.2 The shape

```idris
module Relational.EGraph.Source.Machine
%default total

||| The element types a table may hold. Fixed widths only, so both
||| printings mean the same arithmetic on all four targets.
public export
data Ty = I8 | I32 | I64

||| A table the caller passes: its element type, and whether the engine
||| may write it. No constructor allocates: the printed MLIR can hold no
||| `memref.alloc`, and the printed Idris sizes every array from its input.
public export
data Table : Ty -> Type where
  Input  : TableName -> Table t
  Output : TableName -> Table t

||| What both printings can say; `v` is a printed value (an SSA value, or
||| an Idris expression). No global and no allocation can be written.
public export
interface Machine (0 v : Ty -> Type) (0 step : Type -> Type) where
  lit     : Bits32 -> v I32
  load    : Table t -> v I32 -> v t
  store   : Table t -> v I32 -> v t -> step ()
  upTo    : v I32 -> (v I32 -> step ()) -> step ()          -- a counted loop
  rounds  : (m : Measure s) -> step (Progress s) -> step (Outcome s)
  hook    : (h : Hook) -> HookArgs h v -> v (HookResult h)  -- §5.3
  -- D87's sparse operations, each the library's own (no mirror of them)
```

Data-dependent control flow is written only through the machine's
combinators; a run-time `if` on a printed value would be a printed `if`,
never Idris's own. That is the discipline the route costs (§7.3).

### 2.3 The two schedules, by type

```idris
module Relational.EGraph.Source.Schedule
%default total

public export
data Schedule = Closing | Exploring

||| A rule's right side. `Make` has no `Closing` constructor: a closing run
||| cannot grow the universe it was given.
public export
data Action : Schedule -> Type where
  Union : Slot -> Slot -> Action s
  Make  : (k : Kind) -> Vect (arity k) Slot -> Action Exploring

||| How a run ended. Only a search can stop.
public export
data Outcome : Schedule -> Type where
  Closed    : Outcome Closing
  Saturated : Outcome Exploring
  Stopped   : Outcome Exploring          -- the node table is full

||| What strictly falls each round that changes anything.
public export
data Measure : Schedule -> Type where
  ClassesLeft : Measure Closing          -- every union that merges removes a class
  RoomLeft    : Measure Exploring        -- (room, classes), lexicographic: a made node
                                         -- uses room (the table is append-only), a merge
                                         -- removes a class
```

- **The elaborator** (O7, `proposals/0011-data-oriented-frontend.md:220-232,
  353`, *read*) receives the closing schedule only. Its universe is the
  terms it was handed; union-find and congruence never leave it, and each
  merge removes a class, so the closure ends complete, with no budget and
  no count. Its result type has one ending, so "a spent budget would fail a
  proof by a count" (`proposals/0015-relational-core.md:52-57`, *read*)
  cannot be written. Which facts it closes over stays the consumer's
  rule: metas' identity and syntactic hash-consing, never conversion,
  which is not transitive (`egraph.md:872-879`, *read*).
- **The optimizer** receives the exploring schedule. Its universe is the
  node table the caller sized, `c × ops(f)` (`egraph.md:728-736`, *read*);
  the run ends saturated or stopped, and a stopped graph is extracted as
  it is: less optimized, never refused (AGENTS.md's budget rule).
- **One engine, two instances, no shared state.** D84's soundness
  objection was to shared state (`proposals/0000-mlir-native.md:1215-1217`,
  *read*); there is none: each consumer runs its own instance over its own
  signature. The kernels both schedules use (find, union, rebuild, the
  hash-cons) are printed to both sides; each schedule's driver is printed
  only where it is consumed: closing to Idris, exploring to MLIR (*decision*,
  coordinator: print what a P0 path runs; R5's tactics, after P0, would
  take the exploring driver in Idris from the same source).
- **The printed termination.** In Idris, `rounds` prints structural
  recursion on the measure (the skill's "room left in a finite universe",
  never fuel). In MLIR it prints an `scf.while` whose condition reads the
  same measure (progress made, and room left); MLIR states no totality, so
  the Idris printing is where the argument is checked, on both hosts.

## 3. Placement in the tree (*conjecture*, a placement)

- The source: `libs/mlir-relational/src/Relational/EGraph/Source/`, in the
  library 0015 D4 names (`proposals/0015-relational-core.md:237-238`),
  over D87's library. Not under `IdrisMLIR.*`, since the fork consumes its
  printing and "the fork never imports `IdrisMLIR.*`" (`AGENTS.md:601-602`).
- The printed Idris: a package of its own, `libs/mlir-relational-egraph`,
  every file generated (no hand file beside a generated one: one-source's
  lesson 2, `one-source.md:195-196`).
- The printed MLIR: `foreign/idr/lib/EGraph/Engine.mlir`.
- The printed header: `foreign/idr/include/idr/EGraph/Engine.h.inc`.
- The adapter: hand C++ in `foreign/idr/lib/EGraph/`, the solver layer's
  e-graph pass (`egraph.md` §4.2-4.4, its data moved behind the boundary).

## 4. The build graph, step by step

Which tools exist at each step is the point: nothing needs idris-mlir
before idris-mlir is linked.

| step | runs | who built it, when | reads | writes |
| --- | --- | --- | --- | --- |
| 0. `make bootstrap` | host `cc`/`c++` | the host | pins, patches | CMake, Ninja, stage 1, runtimes, stage 2 with `clang`, `lld`, `opt`, `llc`, `mlir-opt`, `mlir-translate`, `mlir-tblgen` and MLIR's headers (`tools/bootstrap.sh:1012, 1354`, *read*), GMP, Chez with the host's C compiler (`:1087-1095`), Idris on Chez (`:1106-1112`) |
| 1. `tools/spec.sh generate` (one-source §7.1, `one-source.md:583-595`) | stock Idris on Chez | step 0 | D87's library, `mlir-relational` (with the engine source), `idris-mlir-spec`, `specgen`, D51's committed printers of upstream ops (`tools/dialects.sh:4-14`, *read*: they carry "the printer of each op's declarative syntax") | each changed output and the manifest (D67): `.td`, headers, `Engine.h.inc`, `Engine.mlir`, `libs/mlir-relational-egraph/` |
| 2a. CMake: `mlir-tblgen` | stage 2 | step 0 | the generated `.td` | `.h.inc` |
| 2b. CMake: the engine | stage-2 `mlir-opt`, `mlir-translate`, `clang` | step 0 | `Engine.mlir`; the target entry's triple (`foreign/idr/CMakeLists.txt:50-52`) | `idr_egraph.o`, a static library target |
| 2c. CMake: our C++ | stage-2 `clang`, `lld` | step 0 | units, `Engine.h.inc`, `idr_egraph.o`, the runtime archive | idris-mlir and the other tools, statically linked |
| 2d. `idris-mlir --prepare-runtime` | idris-mlir | step 2c | the runtime archive | the prepared runtime (`foreign/idr/CMakeLists.txt:195-203`, unchanged) |
| 3. `tools/dialects.sh generate` | `idris-mlir-tblgen` | step 2c | upstream's records | D51's Idris modules (`Makefile:159`) |
| 4. host packages, the fork, the frontend | stock Idris | step 0 | D87's library and `mlir-relational-egraph`, installed into `HOST_PREFIX` before the fork (the `fork` rule gains the host-libs stamp, `Makefile:192-198, 242-247`) | the fork with O7 on the printed engine, `idris-mlir-front` (`Makefile:204-207`) |
| 5. `prefix`, `libs` | the frontend | step 4 | the same packages | `CHECKOUT_PREFIX` (`Makefile:218-236`) |
| 6. `make self` | idris-mlir and its frontends | steps 2-5 | the fork with the printed engine | stage 2 equal to stage 3 (`tools/self.sh:37-40`); the elaborator's engine is now compiled by idris-mlir, D87's operations replaced by `sparse_tensor` ops through `Faster` |

Step 2b, concretely (*conjecture* on the exact pass list, *read* on each
option): `mlir-opt` runs upstream's `sparsifier` pipeline with
`enable-runtime-library=false` (the option exists and defaults to true,
`mlir/include/mlir/Dialect/SparseTensor/Pipelines/Passes.h:69-72`;
0015 §1 forbids the sparse runtime, `proposals/0015-relational-core.md:32-33`),
the `functional` emit strategy (the `sparse-iterator` one is marked
experimental, `Passes.h:58-64`), and C wrappers for the entry functions
(`emitCWrappers`, `mlir/include/mlir/Conversion/FuncToLLVM/ConvertFuncToLLVM.h:40-43`);
`mlir-translate` gives LLVM IR; the stage-2 `clang --target=<triple> -O3
-c` makes the object with the tools' flags. The printed MLIR names no
triple and no data layout: the target enters only here, from the target
entry, the one place AGENTS.md lets it be decided. The sparsifier in
`mlir-opt` and in idris-mlir is one code, the same patched stage-2 tree
(`tools/bootstrap.sh:48-56`, *read*), so the engine's C++ copy (step 2b)
and its self-hosted Idris copy (step 6) meet the same upstream passes.

`make typecheck` builds only TableGen and headers with the host's
compiler (`tools/bootstrap.sh:1119`, *read*: no `mlir-opt`), so it
compiles the adapter against the committed header and does not build the
object; an error in the printed MLIR shows at step 2b. `make check`
regenerates step 1's outputs with stock Idris alone, as it does every
generated file (`AGENTS.md:567-580`).

## 5. The calling boundary

### 5.1 The generated header

`specgen` prints `Engine.h.inc` from the same source and in the same run
as `Engine.mlir`, so the MLIR function's signature and the C++ prototype
are two printings of one declaration:

```cpp
// Printed by specgen from Relational.EGraph.Source; listed in the manifest.
#pragma once
#include "mlir/ExecutionEngine/CRunnerUtils.h" // upstream's memref descriptor

namespace idr::egraph::engine {
template <typename T> using Table = StridedMemRefType<T, 1>;

enum class Outcome : std::int32_t { Saturated, Stopped };

struct Tables {                 // every buffer is the caller's (§5.2)
  Table<std::int32_t> kind, type, props;      // per node: the spec's op identity, an
                                              // interned type, a properties id
  Table<std::int32_t> childStart, child;      // children as CSR over class ids
  Table<std::int32_t> region;                 // the node's available region
  Table<std::int32_t> parent;                 // union-find; representative = smaller id
  Table<std::int32_t> slot;                   // the hash-cons, open addressing
  Table<std::int32_t> usesStart, uses;        // class -> parent nodes, D87's CSR
  Table<std::int64_t> wordBits;               // the word constant per class
  Table<std::int8_t>  wordWidth;
  Table<std::int32_t> pooled;                 // a hook's datum: an id in a C++ pool
  Table<std::int32_t> best, place;            // extraction and placement, written
  Table<std::int32_t> used;                   // one cell: nodes in use
};

extern "C" std::int32_t _mlir_ciface_idr_egraph_explore(/* one pointer per table */);
inline Outcome explore(Tables &t);            // the typed call; the only one our C++ makes

// Hooks the engine calls; the adapter defines each (§5.3).
extern "C" std::int32_t idr_egraph_make_range(std::int32_t kind, std::int32_t node);
} // namespace idr::egraph::engine
```

- Upstream's descriptor, `StridedMemRefType` (`mlir/include/mlir/ExecutionEngine/CRunnerUtils.h:131-136, 169-172`,
  *read*), is included, never restated; that it is installed with
  stage 2's `mlir-headers` component is *recalled*.
- A hook defined by the adapter with another signature than the printed
  prototype is a compile error, since two `extern "C"` declarations of one
  name cannot differ; a missing one is a link error. Neither is a run-time
  check.

### 5.2 Data layout, and who owns memory

- **Ids** are dense `i32`, in walk order (`egraph.md:659-672`, *read*);
  sizes are `index`, 64 bits on all four targets (*conjecture* from their
  data layouts). No float crosses (the cost model is integers, `egraph.md`
  §5), so both sides mean the same bits on every target.
- **Relations** whose format D87 fixes (a class's uses as CSR, children as
  CSR) cross as their position and coordinate buffers, which the engine
  assembles into `sparse_tensor` values with `sparse_tensor.assemble`,
  made for "an external source" (`mlir/include/mlir/Dialect/SparseTensor/IR/SparseTensorOps.td:60-80`,
  *read*), and reads back with `disassemble` (`:105`). Whether one-shot
  bufferization keeps the caller's buffers in place, without a copy, is
  *conjecture*, a measurement of stage 1. The hash-cons and the union-find
  are plain tables: `sparse_tensor` has no hash level, which 0015 already
  names as its limit (`proposals/0015-relational-core.md:149-162, 238-242`,
  *read*).
- **The caller owns everything.** The C++ adapter carves every table out
  of its per-worker arena for one function and frees it after (`egraph.md`
  §4.1, perf-sources R5, R6). The engine allocates nothing: the machine
  has no allocating operation (§2.2), so the printed MLIR holds no
  `memref.alloc` and no `sparse_tensor.push_back` past capacity (which
  would reallocate, `SparseTensorOps.td:693-705`, *read*). No buffer is
  freed across the boundary in either direction.
- **The budget is the representation.** The node table's capacity is the
  budget: the exploring schedule stops when `used` reaches it. No counter
  exists to be set or forgotten.
- **Reentrant.** No global can be written (§2.2), so MLIR's parallel
  nested pass calls the engine on every worker with that worker's tables
  (`egraph.md:718-726`); output is byte-identical at any thread count.

### 5.3 Hooks: the analyses whose meaning is C++

D41 made an inline operation's meaning one C++ template, instantiated over
words as the folder and over intervals as upstream's
`InferIntRangeInterface` (`proposals/0000-mlir-native.md:715-732`, *read*).
The engine cannot instantiate a C++ template, so:
- the word constant analysis is in the engine where its datum is a word,
  and calls the runtime's fold of a runtime op through the runtime's own C
  symbols, which idris-mlir already links as native code for its folders
  (`runtime/CMakeLists.txt:5-9`, *read*);
- an analysis whose `make` is C++ (intervals; a constant that is not a
  word, a big integer or a string) is a hook: the engine calls
  `idr_egraph_make_<analysis>` with the node, and the adapter's definition
  is one call into the D41 template, monomorphized, writing its datum into
  a C++-owned pool and returning the pool id (`pooled`);
- the analysis's algebra (the meet, its laws) stays in the engine source.

The direction engine-to-C++ is a link-time call with one definition, not a
callback through a pointer; it is the strain named in §8 item 2.

### 5.4 What the C++ adapter does around the call

Number the function, classify each op by the one effect query, fill the
input tables with the floating and unique nodes (`egraph.md` §2.1, kept),
call `explore`, then write the extraction back: for each skeleton
operand, the best node of its class, placed by the engine's `place`
table (the scoped placement over the region tree, `egraph.md` §2.2 and
§4.2 step 7, now computed in the engine over the region table), each op
built by the adapter, the originals left unused erased. The linearity
verifier runs after the pass, as after every pass.

## 6. D67's committed outputs

### 6.1 Committed, in the manifest

- `foreign/idr/lib/EGraph/Engine.mlir`: upstream dialects only (`func`,
  `scf`, `arith`, `index`, `memref`, `sparse_tensor`), target-neutral,
  printed through D51's generated printers of each op's declarative syntax,
  so no upstream op's form is restated in `specgen`; the printers for the
  engine's ops come from a second admitted list the specification states
  beside `IdrAdmitted.td` (*decision*, coordinator), so the frontend does
  not gain builders it never calls.
- `foreign/idr/include/idr/EGraph/Engine.h.inc`.
- `libs/mlir-relational-egraph/` whole (its `.ipkg` included).
- Each with its content hash, and the specification's and the generator's
  hashes, in the one manifest (`proposals/0000-mlir-native.md:1073-1081`,
  *read*); a file is rewritten only when its bytes change, so an engine
  edit recompiles only the object and the adapter's units.

### 6.2 Not committed

The bitcode and the object: per target, made by step 2b from the
committed text, like any object of the build.

### 6.3 Checks

- `make check`: `tools/spec.sh check` regenerates with stock Idris into a
  temporary tree and fails on any difference of files or manifest.
- The second host: `specgen` built by idris-mlir reproduces the committed
  outputs byte for byte (D52, `proposals/0000-mlir-native.md:901-908`).
- The object: its undefined symbols are exactly the hooks and the
  runtime's fold symbols (a check beside `tests/static-linking`), so no
  sparse runtime and no allocator call slipped in.
- One set of committed fixtures (e-graphs, their closures, extractions;
  `egraph.md:904`) run through the object by a unit box (`make test-unit`)
  and through the printed Idris by the harness; the expected files are the
  specification, so neither printing is the other's oracle.

## 7. D87's question: through the generator, or a bootstrap stage

### 7.1 Route S, concretely

The engine is an ordinary Idris program over D87's library (plain bodies,
`Faster` hooks to `sparse_tensor` under idris-mlir), and idris-mlir
compiles it into the C++ tools:

| step | what | problem |
| --- | --- | --- |
| A | build idris-mlir without the engine | the e-graph pass is the one simplifier of `idr` functions (`egraph.md:765-796`); a compiler without it is either a pass compiled out by a build switch, or the pass linked against a stub engine |
| B | the frontend (stock Idris) and idris-mlir-A compile the engine to bitcode, with entry points C++ can call | idris-mlir must give compiled Idris functions a C-callable entry |
| C | relink idris-mlir with that bitcode | its engine was compiled by a compiler without one |
| D | it compiles the engine again; relink | the engine's results do not depend on how fast it runs, so the next compile equals this one: ship stage D |

Or, in place of A: a committed seed (the engine's MLIR at a stop point of
idris-mlir's pipeline, produced by the previous idris-mlir), as Zig's
committed WebAssembly compiler and OCaml's `boot/` are (*recalled*).

### 7.2 Is stage A an ordinary self-hosting stage?

No. `make self`'s stages compile one source, the frontend, by two hosts,
each a whole compiler; stage 1 is Chez, stages 2 and 3 idris-mlir, and
stage 2 equal to stage 3 is a check of determinism (`tools/self.sh:10-17,
37-40`, *read*). And `make self` is not on the build path: the shipped
frontend is the one stock Idris builds (`Makefile:154-162, 204-207`,
*read*). Route S puts idris-mlir on the build path of a shipped C++ tool
for the first time, and its stage A is not the same program on another
host but the compiler with a part removed, kept only to build the
compiler. AGENTS.md names that: "two implementations behind an option",
"a behavior-selecting pass option ... is fallback/configuration slop"
(the owner's call, 57bf8e1d, quoted in AGENTS.md). Reading stage A as the
e-graph "at a budget of zero" (`egraph.md:723-726`) makes its *meaning*
legal under AGENTS.md's budget rule, but not its *build*: the pass still
links the engine, so stage A needs the stub or the switch. The only other
host of the same engine, Chez, cannot be linked into C++ at all. The seed
avoids stage A and trades it for an output only one host can make: Chez
cannot regenerate it, against "A building stage may use either host, but
neither is dropped" (`AGENTS.md:554`) and D15's "stock Idris on Chez
builds it first, so the build always starts" (`AGENTS.md:560-566`); `make
check` runs "without a build" (`Makefile:8-10`) and cannot regenerate it;
and since the seed is idris-mlir's output, every change to the optimizer
that changes the engine's compiled code rewrites the seed in the same
commit, where D86's printed MLIR depends on the specification and
`specgen` alone. A seed in idris-mlir's lowered form also carries the
target's layouts, so likely four seeds (*conjecture*).

### 7.3 Side by side

| | G: the generator prints (D86) | S: idris-mlir compiles (a stage) |
| --- | --- | --- |
| the source | a staged program over the library's staged interface | an ordinary Idris program over the library |
| the C++ copy | `specgen` prints MLIR; stage-2 upstream tools compile it | idris-mlir compiles the engine; needs stage A or a seed |
| bootstrap | unchanged; no cycle (§4) | a cycle, broken by a stub, a switch or a seed |
| two hosts | Chez prints every output; idris-mlir reproduces them (D52) | the C++ copy has one host |
| D67 | target-neutral text, a function of the specification | a seed per target, or nothing committed and a C++ build that waits on Idris, against `AGENTS.md:578` |
| C ABI | entry points of generated MLIR, as the runtime's are | a C export of compiled Idris (`AGENTS.md:258-261`: "Do not implement ... `%extern` as a C export, a C calling convention") |
| memory | the caller owns every table; no allocation behind the boundary | Idris values made by the runtime cross into C++, which must count them, knowing D48's layouts |
| development | an engine edit reprints and recompiles one object | every optimizer edit recompiles the engine two or three times |
| what it costs | the staged discipline (§2.2) and an MLIR printing in `specgen`: a second code generator beside idris-mlir's lowering, the Greenspun risk one-source named (`one-source.md:712-717`) | the amendments in §7.4 |
| what it buys | the rules the tree already holds | the engine in plain Idris, idris-mlir's own optimizations of it |

Sizes, all *conjecture*: the engine's source near egglog's core, about
4,200 lines of Rust (`egraph.md:1029`, from wave 1, *read* there); each
printer for a machine of some forty operations, a few hundred lines.

### 7.4 What route S would need the owner to amend

1. `AGENTS.md:258-261`: "except the compiler's own e-graph engine, which
   idris-mlir compiles from `libs/` and its C++ calls through one
   generated entry no user code can name".
2. `AGENTS.md:554`: "except the stage that compiles the engine into the
   C++ tools, which only idris-mlir runs".
3. `AGENTS.md:578` ("a C++ build never waits on Idris") and D49
   (`proposals/0000-mlir-native.md:874-882`): an exception for the engine,
   or the seed with a `make` target outside `make check` that regenerates
   it.
4. AGENTS.md's ban on a behavior-selecting option: an exception for
   stage A, if no seed.
5. 0015's D6, §3 and §7 (`proposals/0015-relational-core.md:143-145,
   211-212, 243-245`), as route G also needs (§8).

### 7.5 Recommendation

Route G, D86 as recorded. It keeps every rule S would amend, and its one
cost, writing the engine staged, is paid once, in the source.

## 8. What AGENTS.md still strains under route G

1. **The C ABI line** (`AGENTS.md:258-265`). The boundary is `extern "C"`
   symbols between our C++ and our generated code, as the runtime's ABI
   already is, called by the folders on several threads
   (`runtime/Alloc/Cells.cpp:152-157`, `runtime/Start/Start.h:3-8`,
   *read*). No user code reaches it. A sentence beside the rule keeps it
   from reading as a precedent: "The compiler's own generated code (its
   runtime, its e-graph engine) is called from its C++ through symbols one
   generated header declares; no user code names one" (*decision* to
   record under D86).
2. **Callbacks** (`AGENTS.md:412-414`). The hooks are link-time symbols
   with one monomorphized definition each, not type-erased; but they are
   not template parameters either, so the analysis's `make` is a call the
   matcher cannot inline (unless our tools link with LTO, *conjecture*).
   D86's "entry points declared by a header generated from the same
   source" covers them; recorded with item 1.
3. **one-source and egraph.md, coordinator designs, reversed by D86**:
   "§5's rule engine is the sharpest temptation, and is refused"
   (`one-source.md:499-504, 712-717`) and "specgen ... prints constexpr
   tables, never matcher code" (`egraph.md:632-641`). `specgen` stays a
   printer (the semantics are the source's), but what it prints now
   computes. Both are amended in the change that lands this.
4. **0015**: "Every consumer is Idris" (D6), "the C++ optimizer" listed
   among non-consumers (§3), and "the library as the C++ side's engine"
   rejected (§7) (`proposals/0015-relational-core.md:143-145, 211-212,
   243-245`). Amended under D86: the C++ consumes layer 3's printing,
   never its Idris. 0015 §1's "no `sparse_tensor` runtime" holds, and the
   undefined-symbol check (§6.3) proves it.
5. **The sparsifier is upstream's, at main.** Its bugs are fixed upstream
   as `upstream/<bug>/` patches (AGENTS.md); its experimental strategy is
   not used (§4).
6. **The stage-1 elaborator** runs the printed Idris on Chez, with direct
   calls; its speed under Chez is unmeasured (*conjecture*), the price of
   O7 being in P0 (D69).

Kept, each by construction: static linking and nothing loaded at run
time (`AGENTS.md:97-106`: one more static object); four targets and the
one place the target is decided (§4); the two hosts (§6.3); "a C++ build
never waits on Idris" (the MLIR is committed); "anything above the C++ is
Idris" (the source and `specgen`); every generated file in the manifest.

## 9. The options D86 did not take, as a record

- **Generated C++** (Soufflé's form): the engine printed as
  concept-constrained templates, instantiated once behind `extern
  template`; it would compose with D41's templates at compile time, with
  no hooks. D86 chose MLIR for the sparsifier's dense code.
- **idris-mlir compiling the engine into the C++ tools**: route S, §7.
- **The engine in its own process** (the optimizer writes each function's
  problem out, an Idris-built engine process answers): no ABI, but every
  function's facts are written out and parsed back, the class AGENTS.md
  forbids when the compiler runs, and stage 1 would run the optimizer's
  engine on Chez.
- **Moving a consumer across the boundary** (the optimizer into Idris, the
  elaborator into C++): rejected in `egraph.md:853-868`, unchanged.

## 10. The owner's decision, and the coordinator's records

*For the owner, one question* (D87 left it open, and it is an engine's
architecture): **does the C++ copy come from `specgen`'s printing (route
G, D86 as recorded, recommended), or from idris-mlir compiling an ordinary
Idris engine (route S), with §7.4's amendments?** G costs the staged
discipline in the engine's source; S costs a C export of compiled Idris, a
bootstrap stage or a single-host seed, and four rule amendments.

*For the coordinator to record, if the owner takes G:*
- §2's staged form and §2.3's schedules as the engine's contract; the
  closing driver printed to Idris, the exploring driver to MLIR;
- one table in D87's library from each operation to its `sparse_tensor`
  op, read by the registry's `Faster` rows and by `specgen`
  (`sparse-library.md`), so the mapping is held once; and the library's
  staged interface is its own operation set, never a mirror;
- the engine's admitted upstream ops as a second list beside
  `IdrAdmitted.td`, printed by D51's backend for `specgen` alone;
- §8 item 1's sentence beside AGENTS.md's C ABI rule, with item 2 under it;
- amendments in the same change: one-source §5, §6.3, §10; egraph.md §3.4,
  §8, §10.5 item 1; 0015 D6, §3, §7 and R4's place; the `fork` rule's
  dependency on the host packages (`Makefile:192-198`).

## 11. Sources read

- Ours: `AGENTS.md` (working tree); `.claude/skills/representation-first/SKILL.md`;
  `proposals/0000-mlir-native.md` (D15, D16, D41, D49 to D52, D56, D57,
  D67, D69, D84 to D87); `proposals/0015-relational-core.md` (whole);
  `proposals/0011-data-oriented-frontend.md` (§0, §4.6 to §4.8, §7 to
  §10); `audits/p0/design/one-source.md` (whole); `audits/p0/design/egraph.md`
  (whole); `Makefile` (whole); `tools/bootstrap.sh` (1-120, 570-632,
  1076-1180, and the stage-2 components); `tools/self.sh:1-80`;
  `tools/dialects.sh:1-30`; `foreign/idr/CMakeLists.txt:25-100, 160-240`;
  `runtime/CMakeLists.txt:1-30, 120-145`; `foreign/idr/lib/Driver/LinkRuntime.cpp:1-60`;
  `foreign/idr/lib/Driver/Prepare.cpp:1-40`; `runtime/Start/Start.h`;
  `runtime/Alloc/Cells.cpp:140-170`.
- MLIR at the pin: `include/mlir/Dialect/SparseTensor/IR/SparseTensorOps.td`
  (assemble, disassemble, push_back, sort, foreach, iterate, coiterate),
  `include/mlir/Dialect/SparseTensor/Pipelines/Passes.h:26-90`,
  `include/mlir/Dialect/SparseTensor/Transforms/Passes.td` (the runtime
  library option), `include/mlir/Conversion/FuncToLLVM/ConvertFuncToLLVM.h:35-50`,
  `include/mlir/ExecutionEngine/CRunnerUtils.h:125-175`.
- Commands: `grep`, `sed`, `wc -l`, `git ls-files`, `ls`.
- *Recalled*, not re-read: Soufflé (Jordan et al., CAV 2016) and its
  `eqrel` (Nappa et al., PACT 2019); tagless-final staging (Carette,
  Kiselyov, Shan, JFP 2009); Zig's and OCaml's committed bootstrap seeds.
