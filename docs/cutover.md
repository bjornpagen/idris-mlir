# The cutover: census and requirements (stop point 1)

*Temporary.* This is the review document for stop point 1 of the cutover
("idris does types, mlir does programs, and the program runs at compile
time"). It exists only on the `cutover` branch. At the merge, its content
moves into [architecture/](architecture/00-index.md) and
[the plan](plan.md), and this file is deleted, so `plan.md` stays the only
plan (AGENTS.md).

Base: `main` at `5a58550`. LLVM is pinned at `llvmorg-23.1.2`, and Idris at
the `third_party/Idris2` gitlink. Nothing below was built or run for the
new design yet. Every claim about upstream code cites the file and line at
the pin.

## 0. Summary

- **Section 1 of the prompt holds on current main**, with four corrections:
  - main moved three commits, and none of them touches a claim;
  - the number-casts item is plan 12.5 item 29, not 26;
  - the code to delete is about 5,200 lines, not 4,500;
  - upstream's `mlir::ExecutionEngine` cannot run inside a static-musl
    `idris-mlir-cc`, because it aborts while creating its process-symbol
    generator. The JIT is therefore ORC's `LLJIT`, which `ExecutionEngine`
    wraps.
- **Every default verdict of section 2 stands**, except the JIT's API
  (above). Section 2.2 adds 30 rows.
- **Rules.** I read all 228 rules of the eight families. 115 are
  implemented, wholly or in part, by code being deleted, and each has a
  verdict in section 3. The rest are listed as unchanged, so the census is
  complete.
- **Four programs that compile today would be rejected** by "partial code
  is never evaluated". That contradicts the second acceptance bullet of the
  prompt's section 11, so they need your decision (section 4.3).
- **Three reject fixtures become accepts.** Arity raising and its rule
  `PROF-HEAP-5` go away, and output fusion then reaches strings that
  `Simplify` could not see through (section 4.2).
- **This container cannot build the C++ side yet.** The stage-2 musl
  toolchain that `idris-mlir-cc` is built with is unfinished here (the
  bootstrap stopped at about 1,500 of 6,850 steps). Stop point 2 needs it
  (section 8.0).

Section 7 lists the decisions for you, each with a recommendation. These
change what gets built first:
- 7.1: what "total" means;
- 7.2: the four programs;
- 7.3: what "constant-like" means;
- 7.5: when an unused call may be removed;
- 7.9: `Term` as a nested datatype.

## 1. The prompt's claims, checked on main

| # | Claim | Holds | Evidence |
| --- | --- | --- | --- |
| 1 | written against `2946d76` | moved | main is at `5a58550`, three commits later: `017d0d2` (Makefile environment), `3e5f057` (four e2e fixtures after the Prelude move) and `5a58550` (the gate's LTO mode). None touches a claim below. |
| 2 | `Simplify.idr` and `Simplify/{Value,Gen,Fold,Safety}.idr` are about 2,100 lines | yes | 917 + 565 + 411 + 162 + 66 = 2,121 |
| 3 | `Simplify` is at once an evaluator, an inliner, a call-pattern specializer with a whistle, a known-constructor folder, a string optimizer, a defunctionalizer (`Choice`), the heap-free profile's enforcer, and a CFG builder through `Code` | yes | `Simplify.idr` (`drive`, the whistle, generalization, the budget of 20,000, literal depth 4), `Value.idr` (`Choice`), `Gen.idr`, `Safety.idr` (`PROF-HEAP-5`), `Code.idr` |
| 4 | `Fold.idr` re-implements every primitive, with Chez standing in for Ryu and for GMP | yes | `Fold.idr:101` `foldBig BigShow [LBig n] = Just (LStr (show n))` is Idris's `Integer` on Chez. `Double` and string primitives fold with the compiler's own Idris primitives. |
| 5 | `printLn 'x'` takes 5.7 s | yes | 5.4 to 5.6 s on this container, against 0.75 s for `hello` |
| 6 | plan 12.3 says the driver may not scale | yes | plan 12.3, item 14 |
| 7 | plan 6 describes a server process, a wire protocol, `popen`, and a symbolic evaluator kept until M2 | yes | plan 6 starts the server with Idris's `popen2`; under M1, `Fold.idr` keeps only `Integer`, and M2 deletes it |
| 8 | `Emit` hand-writes `cf.switch` segment attributes, `cmpi` predicate integers, `ub.poison` and `inhabitant` | yes | `Emit.idr:382` (`case_operand_segments`), `:189` (`predicate`), `:159` (`ub.poison`), `:457` (`inhabitant`) |
| 9 | MLIR receives flattened `cf` and runs five generic passes; the dialect is value-level | yes | `Registration.cc` runs `inline`, `sccp`, `canonicalize`, `cse` and `symbol-dce`, plus `idr-check-input`, `idr-entry` and `idr-lower` |
| 10 | the runtime is LLVM-dialect text: `Lower/Runtime.mlir.inc` (930 lines) and `tools/GenRyuTables.idr` | yes | 930 lines. `GenRyuTables.idr` has 147 lines plus `gen-ryu-tables.ipkg`, and `make check` depends on it (`Makefile:110`). |
| 11 | `runtime/` exists and joins programs by full LTO | yes, but nothing calls it | `idris-mlir-cc.cc` links the runtime's bitcode with `LinkOnlyNeeded`. `runtime/idris_rt.h` says "Nothing in the compiler calls it yet". |
| 12 | checkers that check each other | yes | `Code/Check.idr` (286 lines), `Term/Check.idr` (72), `Simplify/Safety.idr` (66), `CheckInput.cc` (206) |
| 13 | version machinery | yes | `idr.version` (`Emit.idr:510`, `CheckInput.cc:73`, `Lower.cc:123`), `Idr_Since` (`IdrOps.td:61`), `sinceVersion` (`IdrDialect.cc:113`), `Code.level` and `typeLevel` (`Code.idr:446-590`) |
| 14 | Idris's typechecker gates reduction on visibility, with a timer and optional fuel | yes | `Core/Normalise/Eval.idr`: `reducibleInAny` in `evalRef` (:302), `checkTimer` (:308), `fuel` in `evalDef` (:531) |
| 15 | base's `Deriving.*` at the pin has `Functor`, `Foldable` and `Traversable`, but not `Eq` or `Ord` | yes | `libs/base/Deriving/{Common,Foldable,Functor,Show,Traversable}.idr` |
| 16 | `ub.unreachable` exists at the pin | yes | `UBOps.td:73`. It has only the `Terminator` trait and no effects interface. |
| 17 | `func.call_indirect` of a `func.constant` canonicalizes to a direct call | yes | `FuncOps.cpp:107`, `CallIndirectOp::canonicalize`: a callee matching `m_Constant` becomes a `func.call` |
| 18 | `idris-mlir-cc` can run upstream's `ExecutionEngine` (ORC) | **no** | `ExecutionEngine.cpp:393-395` calls `cantFail(DynamicLibrarySearchGenerator::GetForCurrentProcess(...))`. That needs `dlopen(NULL)`, which a static musl process lacks. `LLJITBuilder` also links process symbols by default. `LLJIT` works in a static process with `setLinkProcessSymbolsByDefault(false)` (`LLJIT.h:415`) and an `absoluteSymbols` table. |
| 19 | the inliner has `default-pipeline`, `max-iterations` and `inlining-threshold` | yes | `Transforms/Passes.td:319-329`. The defaults are `canonicalize`, 4 and `-1U`, which means no limit (`InlinerPass.cpp:104`). |
| 20 | `SparseForwardDataFlowAnalysis` and `DataFlowConfig::setInterprocedural` | yes | `SparseAnalysis.h:300`, `DataFlowFramework.h:290` |
| 21 | `RegionBranchOpInterface` has `getRegionInvocationBounds` | yes | `ControlFlowInterfaces.td:221,243,336`; the `RecursivelySpeculatable` trait is at `SideEffectInterfaces.td:142` |
| 22 | `sccp`, `remove-dead-values`, `symbol-dce`, `int-range-optimizations` | yes | `Transforms/Passes.td:127,439,496`, `Arith/Transforms/Passes.td:46` |
| 23 | `runPipeline` from within a pass, `PassManager::enableTiming`, `allowPatternRollback` | yes | `Pass.h:208`, `PassManager.h:437-456`, `DialectConversion.h:1463` |
| 24 | a remark engine with `Passed` and `Missed` remarks | yes | `IR/Remarks.h:70` (`RemarkKind`) and `MLIRContext::setRemarkEngine` |
| 25 | the action framework, `--mlir-debug-counter` and `mlir-reduce` | yes, with a gap | `Debug/Counter.h` exists, and so does `mlir/tools/mlir-reduce`. But `tools/bootstrap.sh:581` leaves `mlir-reduce` out of the stage-2 components. |
| 26 | `idris-mlir-cc` is stream T's static musl build | yes in the repository, not in this container | The bootstrap builds it. Here, `.toolchain/llvm` is the older glibc build and `build/dev/foreign/idr/idris-mlir-cc` does not exist. |
| 27 | "plan 12.5 item 26" (number casts in types) | item 29 | plan 12.5 |
| 28 | "expect roughly 4,500 lines to go" | about 5,200 | section 5 |
| 29 | every row of `bench/` reads its size at runtime | yes | every `bench/*/Main.idr` reads `n` with `readInt` from stdin |

**Also checked.** These upstream facts are needed below:
- `wouldOpBeTriviallyDead` ignores `Allocate` effects on an op's own
  results (`SideEffectInterfaces.cpp:77-87`), so an unused box allocation is
  dead code.
- A dialect can add canonicalization patterns for other dialects' ops
  (`Dialect::getCanonicalizationPatterns`, `Dialect.h:74`).
- A dialect can verify any op that carries one of its attributes
  (`Dialect::verifyOperationAttribute`, `Dialect.h:148`).
- `OperationFingerPrint` is public (`OperationSupport.h:1432`), which the
  simplify loop needs to detect a round that changed nothing.

## 2. Requirements (step 1)

### 2.1 The prompt's rows

| requirement | default | census | why |
| --- | --- | --- | --- |
| supercompilation (`ELIM-G-19`) | delete | **delete** | Unfolding becomes `inline`, residual calls `idr-specialize`, and evaluation `idr-eval`. The driver's "literal in a matched position" (`ack 0 n`) becomes specialization on a constant, without the four-unfolding bound. |
| choices (`ELIM-G-20`) | delete | **delete** | A value picked at runtime is an ordinary value. Data built from constants is static data; a closure is defunctionalized. Choices also served consumers (`putStr (maybe "none" show m)`), and that needs one added canonicalization, case-of-case (row A3). |
| `Fold.idr` | delete | **delete** | Folders work on attributes. The folders of string, `Double`-printing and big ops call the runtime's own C functions, which are linked into `idris-mlir-cc`. So a folder is the runtime's entry point, not a copy of it. |
| `idr-jit` as a server | keep the idea, delete the shape, use `ExecutionEngine` | **keep the idea and delete the shape; overturn the API** | `ExecutionEngine::create` aborts in a static musl process (row 18 of section 1). Using ORC's `LLJIT` directly is the same ORC, with the runtime bound through an absolute-symbol table, as plan 6 already required. This goes into `PINS.md`. |
| `SEM-BIG-1` | delete | **delete** | See section 4.3: the evaluation of `Integer` code that Idris does not prove terminating goes with it. |
| heap-free profile before M1 | keep, narrowed | **keep, narrowed** | Only dynamic allocation is rejected. So operations that allocate nothing (length, index and comparison of an existing string, or a match on a string picked among literals) are allowed at runtime and lower to runtime calls (row A10). |
| first-order Core with join points | delete | **delete** | Control flow is regions, and loops come from `idr-tail-loops`. |
| `Ty` vs `VTy` | delete | **delete** | One `Ty`. `StaticT` goes: data holding functions is ordinary data with closure fields. |
| contract versions | delete | **delete** | The *profile* version (`docs/architecture/VERSION`, `PROF-GEN-4`, `TEST-SPEC-1`) is a different thing and stays (7.13). |
| `idr-check-input` | delete the pass; its checks become verifiers | **delete** | The checks that outlive the version machinery become three things:<br>- op and type verifiers;<br>- the dialect's attribute verifier, which MLIR runs on any op carrying an `idr.*` attribute, for rules about a whole function or module (world linearity, one root);<br>- for `IDR-IN-1`, a parse-time registry of exactly the contract's dialects (row A19). |
| `idr-entry` | delete; `Emit` marks the root public and `idr-lower` privatizes it | **delete** | `idr.entry` and `idr.entry_kind` go too. The root is the only public function, and its kind is its type. `PINS.md: idr-entry-public` retires. |
| `Code/Check.idr`, `Term/Check.idr` | delete | **delete** | `mlir::verify` runs when `idris-mlir-cc` parses the module and after every pass (the pass manager's default). |
| `Simplify/Safety.idr` | delete; traits enforce `OPT-SAFE-1` | **delete** | Traits need two additions: crash and IO effects share an ordering resource (row A21), and an unused call may be removed only if it cannot crash (row A20). |
| `Facts.idr`'s `block` and `inline` | delete | **delete** | `terminating` stays and becomes `idr.total` (7.1). |
| the hand-written runtime and Ryu port | move to C in `runtime/`, vendor Ryu | **delete** | Ryu becomes a pinned submodule (`ulfjack/ryu`), with the tie wrapper that `SEM-DBL-5` needs. |
| the 1 s compile budget (decision 13) | delete | **delete** | |
| limits on evaluation | delete | **delete** | The only bound left is the machine's (`EVAL-1`). |
| two evaluators that may disagree | unify | **unify, with two named exceptions** | Besides `cast` from `String` (plan item 29), there is `libm`. The typechecker runs `sin` with Chez's host libm; compiled code runs musl's. Where such a term reaches a type, the compiler rejects it with a named rule (7.14). |
| limits on executable size | delete | **delete** | |
| the registry | keep | **keep** | Its *Inline hints* column goes (A7). *Break last* and *Report at caller* stay. |
| generic MLIR text over `system` | keep | **keep** | Text over `system` stays. But `Emit` writes each op's custom syntax instead of the generic form (7.10), and that is what removes the hand-written internals. |
| every existing test | keep the program, question the expectation | **keep, with four exceptions for you** | section 4 |

### 2.2 Added rows

| # | requirement | serves | verdict |
| --- | --- | --- | --- |
| A1 | arity raising (`ELIM-G-5`) and `PROF-HEAP-5` | IO without closures | **Delete.** `inline`, apply-of-closure and defunctionalization remove IO's closures without moving any code. No prefix is left whose crash could move past an effect. Three reject fixtures become accepts (4.2). |
| A2 | output fusion (`ELIM-G-7`) | output without runtime strings | **Keep, as DRR patterns** on `idr.io.put_str`: `append` becomes two writes; `cons` becomes `put_char` then `put_str`; the one-character cast becomes `put_char`; `show` of an integer becomes `put_int`, and of a `Double`, `put_double`. |
| A3 | case-of-case: move a match's single consumer into each of its regions | what choices did for consumers: `putStr (maybe "none" show m)`, `strLength (word c)`, showing a value picked at runtime | **Add**, as a C++ canonicalization, because it touches regions. It applies when, in at least one region, the yielded value is something the consumer folds or canonicalizes against. It moves nothing past an effect, and every path still runs the consumer exactly once (`OPT-SAFE-1`). |
| A4 | what is known about a string built at runtime (`ELIM-G-15`) | `show` putting negative numbers in parentheses | **Keep, as canonicalizations**: `str.head (str.show x)` becomes `idr.int_head x` or `idr.double_head x`; `str.head (str.cons c s)` becomes `c`; a match of such a string against `""` takes its default. |
| A5 | loop breakers (`OPT-PIPE-3`) | stopping the inliner from unrolling mutual recursion | **Keep, in `Emit`**, computed on full Core's call graph with the registry's *Break last* column. Clones inherit `no_inline`. |
| A6 | `CORE-INV-*` | catching frontend bugs | **Withdraw** them with first-order Core. Each property that still means something becomes a verifier (3.2). |
| A7 | the *Inline hints* column, and `%inline` as a hint (`PROF-LIB-2`) | the driver's unfolding | **Delete.** The inliner inlines every legal non-recursive call, because `inlining-threshold` has no limit by default. |
| A8 | a closure never captures `%World` | IO linearity | **Keep**, as a verifier: worlds pass only as arguments and results. |
| A9 | `idr.entry` and `idr.entry_kind` | naming the root and its kind | **Delete** (the `idr-entry` row). |
| A10 | string operations that allocate nothing, at runtime | the narrowed profile | **Add.** `length`, `index`, `head`, comparisons, and literal matches on strings that already exist (literals, or one picked among them) lower to runtime calls. |
| A11 | profile errors from `idris-mlir-cc` are user errors | `DIAG-*`, `TEST-REJ-1` | **Add** a new exit status. The frontend also runs `idris-mlir-cc`'s check for `main : Int` programs, so `--check` still fails with the rule and writes no artifact (7.11). |
| A12 | `.core` | debugging, `FE-ART-1`, `TEST-DET-1` | **Keep**, as full Core after `Translate`. `02-simplify.core` goes; `--directive dump-mlir` shows everything after. |
| A13 | `TEST-ELIM-1` (`core.check` on first-order Core) | elimination tests | **Move** to `mlir.check` on the module after the simplify loop (`--dump-after`). |
| A14 | `idr.may_loop` | `SEM-EVAL-5` | **Reinstate**, in loops of functions not known to terminate: an `scf.while` whose body has no effects and whose results are unused is trivially dead upstream. This is the prompt's `LOW-TAIL-4` note. |
| A15 | a `Passed` remark with a step count | seeing where compile time went | **Change** to wall-clock time. JIT mode adds no counters, so no step count exists (7.12). |
| A16 | `ELIM-G-17` (specialization per literal) | `printLn 'x'` | **Withdraw.** Its cause, an `Integer` made from a `Char` that could not exist at runtime, is gone. |
| A17 | `SEM-REC-*`: recursive data exists at compile time only | recursive data before a heap | **Change.** Recursive data is a box, and constants are static data. A box built at runtime from non-constant parts is a `PROF-DATA-3` error. |
| A18 | `Nat`-like types are `Big` | `printLn 'x'`, `power` | **Add**, from Idris's `ZERO`/`SUCC` flags. That includes `Fin` (Idris's `calcNaty` skips erased arguments) and any user type of the same shape. |
| A19 | `IDR-IN-1`, the op allowlist | a checked contract | **Keep, by construction.** `idris-mlir-cc` parses with a registry of exactly `builtin`, `idr`, `func`, `arith`, `math` and `ub`, so any other op fails to parse; passes load the dialects they need afterwards. `IDR-IN-2` (no flags) holds by `Emit`'s construction, and the new `Emit` test checks it. |
| A20 | removing unused calls | dead-code elimination of calls | **Change the prompt's rule.** A call may be removed when its callee is pure, total, **and cannot crash**. `SEM-EVAL-4` says a crash still happens when its result is unused, and "total" here means terminating (7.1). A third fact, "may crash", is computed alongside `idr.effect`. |
| A21 | crash and IO effects are ordered | `OPT-SAFE-1` through traits | **Add.** Crashes write `CrashResource`, and IO ops read and write `IOResource`. MLIR orders effects only on the same resource, so the effect model does not stop a pass from swapping a crash with output; today no upstream pass does. Ops that may crash will also write the IO resource, so the order is enforced by the traits themselves. |
| A22 | "constant-like" includes partially static values | specialization on data and closures that have runtime parts | **Decide** (7.3). An `idr.con` or `idr.closure` with some runtime operands is constant-like in its static part, and the runtime operands become the clone's parameters, as `ELIM-G-3`'s shapes do today. Without this, `prelude-lists`, `vect`, `choice` and `show-values` are rejected. |
| A23 | a closed call to a partial function is neither evaluated nor specialized | "partial code is never evaluated" | **Add** (7.4). Specializing such a call would unroll it one clone at a time, which is evaluation under another name, bounded only by the clone limit. |
| A24 | libm results in types | the two levels agreeing | **Add** a named rejection (7.14). |
| A25 | `cast` from `String` at runtime | one semantics per primitive | **Pull forward** plan section 3's fast_float grammar, since the folder must be the runtime's parser. Plan item 29's rejection applies where such a term reaches a type. |
| A26 | the stage-2 toolchain with `mlir-reduce` | building `idris-mlir-cc`, and section 9's debugging | **Add** `mlir-reduce` to `stage2_components`, and finish the bootstrap here before stop point 2. |
| A27 | the profile version | `PROF-GEN-4`, `TEST-SPEC-1` | **Keep v3** (7.13). |
| A28 | the inliner threshold | acceptance as a rule (`GOAL-P4`) | **Keep upstream's default of no limit.** With a finite threshold, whether a string reaches output fusion, and so whether a program compiles, would depend on a heuristic. `K` (`max-iterations`) is tuned on `bench/`. |
| A29 | `Term.Check`'s arity checks | internal errors | **Delete.** MLIR verifies what `Emit` writes. |
| A30 | `inhabitant` and `ub.poison` in `Emit` | well-typed blocks around join points | **Delete.** Regions need neither. |

## 3. Rule census (step 2)

Verdicts:
- **op, folder, canon, verifier, pass `name`**: where the behaviour lives
  after the cutover. A canon is a canonicalization, written in DRR or, when
  it touches regions, in C++.
- **Emit**: the new emitter produces it by construction.
- **frontend**: unchanged Idris code under `Frontend.*`.
- **runtime**: a C function in `runtime/`.
- **withdrawn**: the rule goes, for the reason given.
- **text**: the behaviour is unchanged, but the text names deleted code.
- **unchanged**: no deleted code implements it, and its text stays.

Test paths are relative to `tests/`, and "all e2e" means every e2e
fixture. Every `bench/` program reads `n` with `readInt` (an IO loop over
`getChar`) and prints with `printLn`. So every benchmark exercises
`ELIM-G-5`, `ELIM-G-7`, `CORE-LOOP-1`, `LOW-IO-4` and `PROF-IO-4`, and the
tables below name only the other rules a benchmark depends on. The rule
names marked *new* are proposals, fixed at stop point 4.

### 3.1 ELIM (06)

| rule | deleted code | verdict | owner after | tests; benchmarks |
| --- | --- | --- | --- | --- |
| ELIM-ERASE-1 | `Simplify`, `Emit` | **text**: values stay `!idr.erased`, and no pass reads one or treats it as a constant. `remove-dead-values` may drop an unused erased parameter. | Emit; `idr-lower` (1:0) | e2e/v0/erased-witness, profile/v0/accept |
| ELIM-ERASE-2, -3 | — | unchanged | frontend | profile/v0/reject/PROF-ESC-1-* |
| ELIM-MONO-1..4 | — | unchanged | frontend (`Translate.request`) | profile/v1/reject/PROF-POLY-1-nested, e2e/v2/interface-* |
| ELIM-G-1 beta | `Simplify` | **canon (C++)**: `idr.apply (idr.closure @f(caps)) args` becomes `func.call @f(caps…, args…)`, then `inline` | `idr.apply` | e2e/v1/ELIM-G-1-beta |
| ELIM-G-2 known constructor | `Simplify` | **folder and canon**: `idr.field` and `idr.tag` fold on an `idr.con` or a constant; an `idr.match` on either inlines its region, and so does a match with one region left | `idr.match`, `idr.field`, `idr.tag` | e2e/v1/ELIM-G-2-known-constructor, interface-superclass, e2e/v2/interface-option-monad, interface-state-monad, e2e/v3/static-evaluation, prelude-traverse; bench/nbody |
| ELIM-G-3 specialization | `Simplify`, `Gen` | **pass `idr-specialize`** (*new* `ELIM-SPEC-1`) | `idr-specialize` | e2e/v1/ELIM-G-3-specialization, interface-superclass, e2e/v2/interface-*, profile/v1/accept/PROF-FN-7-*; bench/ack |
| ELIM-G-4 static let | `Simplify` | **Emit and upstream**: a `let` is an SSA value, and constants propagate by `sccp` | Emit, `sccp` | e2e/v1/ELIM-G-4-static-let |
| ELIM-G-5 arity raising | `Simplify`, `Value`, `Gen`, `Safety` | **withdrawn** (A1) | — | e2e/v1/ELIM-G-5-arity-raising, e2e/v3/call-pattern, prelude-traverse, profile/v1/{accept,reject}/PROF-HEAP-5-*; all bench |
| ELIM-G-6 primitives on literals | `Fold`, `Simplify` | **folders and `idr-eval`**: upstream folds `arith` and `math`; ours fold `idr.div`, `idr.mod`, `idr.to_char`, `idr.to_int`, `idr.str.*` and `idr.big.*`, through the runtime's C where the op is ours | folders, `idr-eval` | e2e/v1/ELIM-G-6-compile-time, strings-at-compile-time, numbers, e2e/v3/prelude-user-types |
| ELIM-G-7 output fusion | `Simplify`, `Value` | **canon (DRR)** on `idr.io.put_str` (A2); its case 5 is A3 | `idr.io.put_str` | e2e/v1/ELIM-G-7-output-fusion, hello, e2e/v2/string-functions, every IO e2e; all bench |
| ELIM-G-8 force of delay | `Simplify` | **canon**: ELIM-G-1's pattern with no arguments, since a `Lazy` value is a closure of no arguments | `idr.apply` | e2e/v1/ELIM-G-8-force-delay, laziness |
| ELIM-G-9 dead static values | `Simplify` | **upstream DCE**: `idr.closure` and an `idr.con` of data are `Pure`, and a box's `idr.con` only allocates its own result, which `wouldOpBeTriviallyDead` ignores | upstream | e2e/v1/ELIM-G-9-dead-static |
| ELIM-G-15 strings built at runtime | `Simplify`, `Types` | **canon** (A4), with `idr.int_head` (*new*) and `idr.double_head` | `idr.str.head`, `idr.match_lit` | e2e/v3/show-values, prelude-show, static-evaluation |
| ELIM-G-17 specialization per literal | `Gen` | **withdrawn** (A16) | — | e2e/v3/prelude-user-types |
| ELIM-G-19 the driver | `Simplify`, `Value`, `Gen` | **withdrawn**; replaced by `inline`, `idr-specialize` and `idr-eval` (*new* `ELIM-SPEC-1`, `ELIM-SPEC-2`, `ELIM-EVAL-1`) | the simplify loop (*new* `OPT-PIPE-5`) | e2e/v3/static-evaluation, compile-time-evaluation, call-pattern, prelude, prelude-lists, prelude-math, e2e/v2/string-functions, math-showcase, nbody, e2e/v0/shapes, absurd-body, erased-witness, profile/v1/reject/PROF-HEAP-4-growing-function, profile/v2/reject, profile/v3/accept; bench/ack, nbody |
| ELIM-G-20 choices | `Simplify`, `Value`, `Code` | **withdrawn**; replaced by ordinary data, `idr-defunctionalize` (*new* `ELIM-CLOS-1`) and A3 | `idr-defunctionalize`, case-of-case | e2e/v3/choice, prelude, prelude-io, prelude-show, show-values, profile/v1/reject/PROF-HEAP-{1,2}-growing-choice |
| ELIM-G-ORDER | `Simplify` | **withdrawn**: the simplify loop has its own termination argument (`OPT-PIPE-5`) | — | review |
| ELIM-G-SCOPE | `Simplify` | **withdrawn**: no optimizer is left in Idris | — | review |
| ELIM-G-10..14, 16, 18 | — | stay withdrawn; their text points at the new owners | — | — |
| ELIM-DEFUNC-1..3 | — | stay withdrawn; the IDs are not reused | — | — |
| ELIM-FORCE-1 | — | unchanged (reserved) | — | — |
| ELIM-FORCE-2 | — | **text**: `Nat`-like types are now `Big` (A18); `newtypeArg` is still unused | frontend (representation) | review |

### 3.2 CORE (05)

| rule | deleted code | verdict | where its content goes | tests |
| --- | --- | --- | --- | --- |
| CORE-INV-1 closed, unique names | `Code/Check` | withdrawn | SSA dominance, checked by the MLIR verifier | compiler/core-check (deleted) |
| CORE-INV-2 first order, arities | `Code/Check` | withdrawn | the symbol verifier of `func.call`; the verifiers of `idr.con` (one operand per field), `idr.closure` and `idr.apply` | compiler/core-check |
| CORE-INV-3 monomorphic, typed, erased positions | `Code/Check` | withdrawn | MLIR types. `idr.ctor` quantities match `!idr.erased` fields (`IDR-DATA-2`), and the dialect's attribute verifier checks that an argument's `idr.quantity` matches its type. | compiler/core-check |
| CORE-INV-4 quantities recorded | `Simplify`, `Translate` | withdrawn | `Emit` writes them (`IDR-FN-1`, `IDR-DATA-2`) | e2e/v0/shapes mlir.check |
| CORE-INV-5 quantity-0 values only in quantity-0 positions | `Code/Check` | withdrawn | by types: an `!idr.erased` value can flow only to erased positions | e2e/v0/erased-witness |
| CORE-INV-6 matches | `Code/Check` | withdrawn | the verifiers of `idr.match` (distinct constructors of the scrutinee's type; a region's arguments are its constructor's fields) and `idr.match_lit` (distinct literals of the scrutinee's type) | e2e/v0/absurd-body |
| CORE-INV-7 tags, acyclic data | `Code/Check` | withdrawn | `IDR-DATA-2`, and `IDR-DATA-4` as revised | idr/verify |
| CORE-INV-8 everything reachable from the root | `Code/Check` | withdrawn | `symbol-dce` makes it true, and nothing depends on it | — |
| CORE-INV-9 world linearity | `Code/Check` | withdrawn | `IDR-WORLD-1`, a region-aware verifier | idr/world, e2e/v1/ELIM-G-5-arity-raising |
| CORE-INV-10 strings are literals | by construction | withdrawn | `PROF-HEAP-3` in `idr-check-profile` | — |
| CORE-INV-11 join points | `Code/Check` | withdrawn | there are no join points | compiler/core-check |
| CORE-CHECK-1 | `Term/Check`, `Code/Check` | withdrawn | `mlir::verify` when the module is parsed and after every pass; a failure is `DIAG-ICE-1` | compiler/core-check |
| CORE-PASS-1 | — | text: the passes are `Translate` (with `Mono`), then `Emit`; `Rewrite` stays reserved | — | review |
| CORE-LOOP-1 | `Code/Loops` | withdrawn from 05 | `idr-tail-loops` (*new* `LOW-TAIL-5`) | e2e/v0/tail-loop-deep, e2e/v2/math-showcase, profile/v0/accept/PROF-FN-6-tail-loop; every bench loop |
| CORE-OPT-1 | — | withdrawn: the middle end has no optimizer at all | — | review |
| CORE-ERASE-1 | — | unchanged | — | e2e/v0/shapes |
| CORE-DUMP-1 | the `Code` printer | text: one printer, for full Core; `.core` is Core after `Translate` | — | every e2e (artifact), registry/FE-TR-7-identity-hook translate.check |

### 3.3 PROF (02)

| rule | deleted code | verdict | owner after | tests |
| --- | --- | --- | --- | --- |
| PROF-GEN-3 | `Simplify` | text: `PROF-HEAP-*` is checked on the optimized MLIR module | `idr-check-profile` | profile/v0/accept |
| PROF-GEN-4 | — | text: if you choose so, the programs of 4.3 are a deliberate exception, as `PROF-IO-1` was (7.2) | — | TEST-VER-1 |
| PROF-GEN-5 | `Simplify` | text: the documented pipeline decides acceptance, with its parameters fixed (A28) | `idr-check-profile` | profile/v1/accept |
| PROF-LIB-1 | `Simplify` (the Prelude row) | text: lists, `Nat` and `Integer` literals have runtime representations | frontend | profile/v3/accept |
| PROF-LIB-2 | `Simplify` (`%inline`) | text: `%inline` is ignored (A7) | — | profile/v1/accept/PROF-LIB-2-io-library |
| PROF-TYPE-4 | `Translate.coreType`, `Simplify` | **revised**: `Integer` is a runtime type. A big that is not a constant in the optimized module is rejected with this rule, since bigs may allocate. `Type` and types that depend on runtime values stay frontend rejections. | `idr-check-profile`, frontend | profile/v1/reject/PROF-TYPE-4-{integer,dependent}, profile/v3/reject/PROF-TYPE-4-prelude-integer |
| PROF-DATA-3 | `Translate`, `Simplify`, `CheckInput` | **revised**: recursive data is a box. A box's `idr.con` with an operand that is not constant, if it survives, is rejected. | `idr-check-profile` | profile/v3/reject/PROF-DATA-3-* |
| PROF-PRIM-2 | `Translate` | text: `Integer` primitives are ops | frontend | profile/v0/reject/PROF-PRIM-2-* |
| PROF-PRIM-4 | `Simplify` | **revised**: a string built at runtime that reaches anything other than output is rejected at that use. Operations that allocate nothing, on strings that exist, are allowed (A10). | `idr-check-profile` | profile/v1/reject/PROF-PRIM-4-runtime-match, e2e/v3/choice, static-evaluation |
| PROF-HEAP-1 | `Simplify`, `Code` | **revised**: rejects a closure of at least one argument that survives `idr-defunctionalize`: its set of labels is unknown, or its captures would make the sum recursive. An implementation chosen at runtime stays a frontend rejection (FE-TR-6). | `idr-check-profile`, frontend | profile/v1/reject/PROF-HEAP-1-growing-choice, profile/v2/reject/PROF-HEAP-1-runtime-implementation |
| PROF-HEAP-2 | `Simplify` | **revised**: the same, for closures of no arguments (`Lazy`, `Inf`) | `idr-check-profile` | profile/v1/reject/PROF-HEAP-2-growing-choice |
| PROF-HEAP-3 | `Simplify`, `Types` | **revised**: rejects a string-building op whose result output fusion did not consume | `idr-check-profile` | profile/v1/reject/PROF-HEAP-3-* (both become accepts), profile/v2/reject/PROF-HEAP-3-recursive-string |
| PROF-HEAP-4 | `Simplify` (the whistle) | **revised**: rejects a closure that survives because the clone limit stopped its callee's specialization | `idr-specialize`, `idr-check-profile` | profile/v1/reject/PROF-HEAP-4-growing-function |
| PROF-HEAP-5 | `Safety` | **withdrawn** (A1) | — | profile/v1/accept/PROF-HEAP-5-division-run-at-once (stays an accept), profile/v1/reject/PROF-HEAP-5-division-before-action (becomes one) |
| PROF-FN-5 | `Gen` (missing cases) | text: a missing case is `idr.crash` | frontend, Emit | e2e/v3/missing-case |
| PROF-FN-7, PROF-IFACE-1 | — | text: their references to `PROF-HEAP-*` | frontend | profile/v1/accept, e2e/v2/interface-* |

These are unchanged, because the frontend's `Frontend.Profile` and
`Translate` check them and no deleted code does: PROF-GEN-1; PROF-GEN-2 (a
location may now come from the C++ side, 3.9); PROF-PROG-1..4; PROF-LIB-3;
PROF-IO-1..4; PROF-TYPE-1..3; PROF-DATA-1, -2, -4 and -5; PROF-FN-1..4;
PROF-FN-6; PROF-POLY-1; PROF-TERM-1 and -2; PROF-PRIM-1, -3 and -5;
PROF-ESC-1; PROF-PRAG-1.

### 3.4 SEM (03)

| rule | deleted code | verdict | owner after | tests |
| --- | --- | --- | --- | --- |
| SEM-REF-1 | `Fold` (values) | text: Idris's evaluator stays the reference for values, and the two-level test checks it (prompt section 10) | the two-level test | every `Oracle.idr` (TEST-ORACLE-1) |
| SEM-EVAL-2 | `Simplify` (left to right) | text: `Emit` evaluates arguments left to right | Emit | bench/fib, e2e/v3/compile-time-evaluation |
| SEM-EVAL-4 | `Safety` | text: a call that may crash is never removed (A20) | `IDR-EFF-1`, A20 | e2e/v0/crash-*, idr/effects |
| SEM-EVAL-5 | `Code.Loops` (loops as blocks) | text: `idr.may_loop` (A14) | `idr-tail-loops` | idr/pipeline/emit-llvm |
| SEM-INT-2, -3, -7 | `Fold` | text: the folders are upstream `arith` (APInt) and ours (`idr.div`, `idr.mod`); `Fold`'s copy goes | folders, `idr-lower` | e2e/v0/SEM-INT-* (63), idr/fold |
| SEM-LIT-1 | `Emit` | text: `Emit` writes each literal as Idris stores it | Emit | e2e/v0/SEM-INT-* |
| SEM-DBL-1 | `Emit` (the literal's text) | text: a `Double` constant is a `FloatAttr` holding the literal's bits | Emit | e2e/v2/double-basics |
| SEM-IO-2..5, SEM-IO-7, SEM-CRASH-1, SEM-PROG-1, -2 | `Runtime.mlir.inc`, `Entry.cc` | text: the runtime's C and `idr-lower`'s entry point implement them | runtime, `idr-lower` | e2e/v1/echo, hello, e2e/v0/crash-*, e2e/v3/prelude-input, idr/lower/io |
| SEM-CHAR-3 | `Fold`, `Emit` | text: `idr.to_char`'s folder and lowering | op | e2e/v1/chars, idr/fold/to-char |
| SEM-STR-2 | `Fold` | **revised**: a string primitive means what the runtime computes, which the two-level test holds to Idris's evaluator | runtime, folders | e2e/v1/ELIM-G-6-compile-time, numbers |
| SEM-DBL-3 | `Fold` | text: our compiler runs musl's libm at both levels (one libc); Idris's typechecker runs the host's (A24) | runtime | e2e/v2/double-basics |
| SEM-DBL-4 | `Fold` | text: `idr.to_int`'s folder agrees with its lowering | op | e2e/v2/double-cast-nan |
| SEM-DBL-5 | `Fold` (Chez's `number->string`), `Runtime.mlir.inc` | **revised**: vendored Ryu with the tie wrapper; `cast` from `String` uses fast_float's grammar at runtime (A25) | runtime | e2e/v2/double-basics, double-print-fuzz, spec/ryu-tables (deleted) |
| SEM-BIG-1 | `Simplify`, `Fold`, `Translate` | **withdrawn**: bigs are runtime values, and the profile rejects runtime ones for now | — | profile/v3/accept/SEM-BIG-1-static-integers (4.3), e2e/v3/compile-time-evaluation, prelude-math, static-evaluation, profile/v1/reject/PROF-TYPE-4-integer |
| SEM-REC-1 | `Translate` (`StaticT`), `Simplify` | **revised**: boxes, and constants are static data (A17) | frontend (representation), `idr-check-profile` | profile/v3/accept/SEM-REC-1-static-list, profile/v3/reject/PROF-DATA-3-*, e2e/v3/choice, prelude-lists |
| SEM-REC-2 | `Simplify.drive` | **revised**: a value is still built strictly, where it is written. `Inf` is a closure of no arguments, forced by name. The whistle and the budget go. | Emit, `idr-eval` | profile/v3/accept/SEM-REC-2-streams (4.3), e2e/v3/prelude-lists, prelude-show, prelude-traverse, prelude-user-types, vect |
| SEM-IDX-1 | — | text: a value of a recursive family is a box, not compile-time data | frontend | profile/v3/accept/SEM-IDX-1-indexed-tags, e2e/v3/vect |
| SEM-LAZY-1 | `Simplify` (G8) | unchanged in meaning; the closure ops own it | ops | e2e/v1/laziness |
| SEM-CRASH-2 | `Gen`, `Emit` | text: `idr.crash` | Emit | e2e/v3/missing-case |
| SEM-RES-2 | `Code.Loops` | text: `idr-tail-loops` | `idr-tail-loops` | e2e/v0/tail-loop-deep |
| SEM-DEV-2 | `Fold` | **revised**: `Simplify` no longer folds libm. LLVM folds it inside `idris-mlir-cc`, on musl, which is the executable's libm too. | — | review |
| SEM-EXCL-2 | — | **revised**: `Integer` has a representation, and at runtime only the heap-free profile excludes it | — | profile/v1/reject/PROF-TYPE-4-integer |

New rules in 03 (proposed names):
- `SEM-EVAL-6`: compile-time evaluation is runtime evaluation, run early.
  Total code is always evaluated and partial code never is. Totality is the
  `Terminating` result of `Core.Termination.checkTotal` (7.1). The rule says
  why it is stricter than the typechecker's visibility-and-timer rule.
- `SEM-EVAL-7`: memory management is not observable, so the JIT's arena
  cannot change a result.
- `EVAL-1`: a total evaluation the machine cannot finish is a compile error
  that names the call.

Unchanged: SEM-REF-2, SEM-EVAL-1, SEM-EVAL-3, SEM-INT-1, SEM-INT-4..6,
SEM-CHAR-1 and -2, SEM-STR-1, SEM-DBL-2, SEM-DATA-1 and -2, SEM-Q-1 and
-2, SEM-IO-1, SEM-IO-6, SEM-RES-1, SEM-DEV-1, SEM-EXCL-1.

### 3.5 LOW (10)

| rule | deleted code | verdict | owner after | tests |
| --- | --- | --- | --- | --- |
| LOW-TAIL-1, -2 | — | stay withdrawn | — | — |
| LOW-TAIL-3 | — | unchanged | LLVM | e2e/v1/echo |
| LOW-TAIL-4 | `Code.Loops` (cycles of blocks) | **revised**: loops are `scf.while` from `idr-tail-loops`; loops in functions not known to terminate carry `idr.may_loop` (A14); still no `mustprogress` | `idr-tail-loops`, `idr-lower` | e2e/v0/tail-loop-deep, idr/pipeline/emit-llvm |
| LOW-SWITCH-1 | `LowerSwitch` | **withdrawn**: `idr.match` lowers to `idr.tag` and `scf.index_switch`, and `convert-scf-to-cf` builds the CFG (*new* `LOW-MATCH-1`) | `idr-lower` | idr/lower/data-layout, e2e/v3/prelude-lists |
| LOW-BLOCK-1 | `Lower.cc` | withdrawn: functions from `Emit` have one block | — | idr/lower/select |
| LOW-DATA-1..3 | — | unchanged for sums. Boxes, closures, bigs and strings get their own layouts, from plan section 3, as new rules. | `idr-lower` | idr/lower/data-layout |
| LOW-ERASE-1 | — | unchanged | `idr-lower` | — |
| LOW-SEL-1 | — | text: it may become dead code, since `scf.if` now becomes `select` after types are converted | `idr-lower` | idr/lower/select |
| LOW-STR-1 | `Runtime.{h,cc}` (the string half stays) | **revised** into *new* `LOW-CONST-1`: every `idr.constant` (string, sum, box, closure or big) is static data, a private constant global with count 0, shared when equal | `idr-lower` | e2e/v1/hello |
| LOW-CHAR-1 | — | unchanged | `idr-lower` | idr/fold/to-char |
| LOW-IO-1..4 | `Runtime.mlir.inc` | **revised**: buffering, `put_int`, `get_char`, `get_byte` and `exit` are C in `runtime/`, and "There is no runtime library" goes | runtime | e2e/v1/echo, hello, e2e/v3/prelude-input, idr/lower/io, get-byte |
| LOW-DBL-1 | `Runtime.mlir.inc` (`__idr_f64_to_i64`) | **revised**: the helper is C | runtime | e2e/v2/double-*, idr/lower/double |
| LOW-DBL-2 | `Runtime.mlir.inc`, `GenRyuTables` | **revised**: vendored Ryu, with its own tables, plus the tie wrapper | runtime | e2e/v2/double-print-fuzz, spec/ryu-tables (deleted) |
| LOW-DBL-3 | — | unchanged | upstream | e2e/v2/double-basics |
| LOW-DBL-4 | `Runtime.mlir.inc` | **revised**: C, and `idr.int_head` joins it | runtime | e2e/v3/show-values, idr/lower/double-head |
| LOW-DIV-1 | — | unchanged | `idr-lower` | e2e/v0/SEM-INT-*, crash-* |
| LOW-CRASH-1 | `Runtime.mlir.inc` | **revised**: `idris_rt_crash` is C. In JIT mode it reports to the parent process instead of exiting. | runtime | e2e/v0/crash-*, idr/lower/crash |
| LOW-CRASH-2 | `Lower/Patterns.cc` | **revised**: `idr.crash` is followed by `ub.unreachable`, so it needs no stand-in results | `idr-lower` | idr/lower/crash-op, e2e/v3/missing-case |
| LOW-EXT-1 | — | text: the runtime's C now joins programs, and still calls only `write`, `read`, `_exit` and libm | driver, runtime | every e2e (TEST-HEAP-1) |
| LOW-ENTRY-1 | `Entry.cc`, `CheckInput.cc`, `Lower.cc` | **revised**: the root is the only public function, and its type gives its kind | `idr-lower` | idr/e2e, idr/lower |
| LOW-UP-1 | — | text: the match lowering adds `scf` | — | — |
| LOW-TARGET-1 | — | text: the JIT compiles for the host CPU, which no result depends on | driver | idr/pipeline |
| LOW-ATTR-1, LOW-CC-1 | — | unchanged | — | — |

New rules in 10 (proposed names):
- `LOW-MATCH-1`: how `idr.match` lowers.
- `LOW-CONST-1`: constants are static data.
- `LOW-BOX-1`, `LOW-CLOS-1`, `LOW-BIG-1`: the layouts of boxes, closures and
  bigs.
- `LOW-STR-2`: strings at runtime.
- `LOW-JIT-1`: JIT mode, which differs only in its arena allocator and in
  reporting a crash.
- `LOW-RT-1`: every helper is a C function in `runtime/`, joined as bitcode
  into executables and linked natively into the JIT.
- `LOW-TAIL-5`: `idr-tail-loops`.

### 3.6 OPT (09)

| rule | deleted code | verdict | owner after | tests; benchmarks |
| --- | --- | --- | --- | --- |
| OPT-SAFE-1 | `Safety`, `Gen` | text: traits enforce it, now with A20 and A21; an evaluation that crashes leaves its call in place | traits, `idr-eval` | e2e/v0/crash-div-zero, idr/effects |
| OPT-PIPE-1 | `Registration.cc` | **revised**: the pipeline of section 6.3 | `Registration.cc` | idr/pipeline/cc-steps |
| OPT-PIPE-2 | — | stays withdrawn | — | — |
| OPT-PIPE-3 | `Code.loopBreakers` | kept (A5), and moves to `Emit` | Emit | e2e/v2/loop-breakers |
| OPT-PIPE-4 | — | unchanged | `idris-mlir-cc` | idr/pipeline/layout; bench/tak, fib |
| OPT-IDEM-1 | — | **revised**: the simplify loop runs to a fixpoint, so running it again changes nothing | — | idr/pipeline/fixpoint |

New (proposed names): `OPT-PIPE-5`, the simplify loop and why it
terminates; `OPT-CALL-1`, when an unused call may be removed (A20).

### 3.7 IDR (08)

| rule | deleted code | verdict | owner after | tests |
| --- | --- | --- | --- | --- |
| IDR-MOD-1 | `CheckInput`, `Emit`, `Lower.cc`, `Idr_Since` | **withdrawn** | — | idr/check-input/reject-module, reject-v2, reject-v3 (deleted) |
| IDR-MOD-2 | `Emit` | **revised**: `Emit` writes custom syntax (7.10) | Emit | e2e/v0/shapes |
| IDR-TY-1, -2, -5 | — | unchanged | types | — |
| IDR-TY-3 | `CheckInput` | text: the allowed builtin types | verifiers | — |
| IDR-TY-4 | — | **revised**: `!idr.str` is any string, not only a literal | types | — |
| IDR-DATA-1..3 | — | text: field types may also be boxes, closures and bigs | verifier | idr/verify/data-* |
| IDR-DATA-4 | `CheckInput` | **revised**: containment through unboxed sums is acyclic, and every cycle passes through a box; the module's attribute verifier checks it | verifier | idr/check-input/reject-data-cycle (moves to idr/verify) |
| IDR-DATA-5 | `Emit` | unchanged (`NameLoc`), plus the library origin (7.11) | Emit | e2e/v0/shapes |
| IDR-CON-1, IDR-TAG-1, IDR-FIELD-1 | — | extended to boxes; a box's `idr.con` allocates (`MemAlloc`) | ops | idr/fold/data |
| IDR-DIV-1, -2, IDR-EFF-1 | — | unchanged, plus A21 | ops | idr/effects/div, idr/fold/division |
| IDR-CHAR-1 | — | unchanged | op | idr/fold/to-char |
| IDR-DBL-1..3 | `Runtime.mlir.inc` (their helpers) | unchanged ops; the helpers become C | ops, runtime | idr/lower/double, double-head, e2e/v2/double-* |
| IDR-CRASH-1 | `CheckInput` (version), `Lower` | **revised**: `idr.crash "msg"`, then `ub.unreachable` | op | idr/lower/crash-op |
| IDR-STR-1 | — | **revised**: `idr.str.lit` becomes an `idr.constant` of a `StringAttr`, so there is one constant op | op | — |
| IDR-IO-1, -2, IDR-EFF-2 | `Runtime.mlir.inc` | the ops are unchanged, plus A21 | ops, runtime | idr/effects/io, idr/lower/io |
| IDR-WORLD-1 | `CheckInput` | **moved** to the attribute verifier of each function; region-aware, a region being one path | verifier | idr/world/* |
| IDR-IN-1 | `CheckInput` | **moved** to the parse-time registry (A19) | driver | idr/check-input/reject-ops (moves to compiler/cc-contract) |
| IDR-IN-2 | `CheckInput` | **moved**: `Emit` by construction, checked by the `Emit` test | Emit | — |
| IDR-IN-3 | `Emit` | **revised** mapping: `Integer` to `idr.big.*`, strings to `idr.str.*`, `Nat` to big arithmetic | Emit | e2e/v0/literal-match |
| IDR-FN-1 | `CheckInput`, `Emit` | **revised**: every function is private except the root. Arguments carry `idr.quantity`; functions carry `idr.total` (from Idris), `idr.effect` (computed) and, on loop breakers, `no_inline`. | Emit | e2e/v0/shapes |
| IDR-FN-2, -3 | `Emit` | unchanged | Emit | e2e/v0/shapes |
| IDR-MATCH-1 | `Emit` | **replaced** by `idr.match` with regions (*new* rule) | op | e2e/v0/shapes |
| IDR-MATCH-2 | `Emit` | **revised**: impossible alternatives are left out; no default is invented, and none gets `ub.unreachable` | Emit | e2e/v0/absurd-body, enum-stepping, impossible-branch |
| IDR-MATCH-3 | `Emit` | **replaced** by `idr.match_lit` | op | e2e/v0/literal-match |
| IDR-MATCH-4 | `Emit` | unchanged | Emit | e2e/v0/erased-witness |
| IDR-LOC-1 | `Emit` | unchanged, plus the origin | Emit | — |
| IDR-IF-1 | — | extended to regions | dialect | idr/pipeline |
| IDR-IF-2 | — | unchanged | — | — |

New rules in 08 (proposed names):
- `IDR-TY-6`, `IDR-TY-7`, `IDR-TY-8`: the box, closure and big types.
- `IDR-CONST-1`: the attribute forms of values.
- `IDR-CONST-2`: `idr.constant`.
- `IDR-MATCH-5`: `idr.match` and its interfaces.
- `IDR-MATCH-6`: `idr.match_lit`.
- `IDR-CLOS-1`: `idr.closure` and `idr.apply`.
- `IDR-STR-2`: the string ops.
- `IDR-BIG-1`: the big ops.
- `IDR-FACT-1`: `idr.total`, `idr.effect` and "may crash".
- `IDR-RANGE-1`: `InferIntRangeInterface`.

### 3.8 FE-DET (04)

| rule | deleted code | verdict | owner after | tests |
| --- | --- | --- | --- | --- |
| FE-DET-1 | the `Code` printer, `Emit` | **text**: `.core` (full Core) and `.mlir` stay byte-identical. Clone names and JIT results are deterministic: MLIR runs single-threaded, clones are numbered by first request, and results do not depend on the JIT's optimization level. | frontend, Emit, `idr-specialize` | determinism/v0-shapes, v1-hello |

### 3.9 Other rules the deleted code implements

These are outside the eight families but change with them:
- **DIAG-HEAP-1**: an `idr-check-profile` rejection names the op, its
  location chain and the reason; `Missed` remarks add the specialization or
  evaluation that stopped.
- **DIAG-ONE-1**: "first" means frontend errors, then `idr-check-profile`
  in op order. Its test, `PROF-HEAP-3-reported-before-heap-5`, becomes an
  accept, so it needs a new test.
- **DIAG-LOC-1**: errors report the location chain, with the library origin
  read from locations (7.11).
- **DIAG-ICE-1**: MLIR verifier failures are internal errors.
- **DRV-CC-2**: gains an exit status for a profile rejection and one for
  `EVAL-1`.
- **DRV-DUMP-1**, **DRV-OPT-1**, **TEST-ELIM-1**, **TEST-EMIT-1**: revised
  (A12, A13, 6.3).
- **FE-TR-1**: `Emit` synthesizes the types of `let`s (6.1).
- **FE-TOT-1**: totality now also decides evaluation.
- **GOAL-P2**, **GOAL-P4**, **GOAL-P6** and settled decision **D14** (01)
  are principles the cutover reverses: abstraction is removed *in* MLIR, and
  C++ now handles closures. These are contract-level changes that need your
  approval.
- **HOOK-NAME-1**: unchanged. No Idris name reaches C++ as data.

## 4. Tests and benchmarks

### 4.1 By suite

| suite | fate |
| --- | --- |
| `tests/spec` (25) | `ryu-tables` is deleted, the rest stay. New: no primitive semantics in Idris, and `Emit` names only `idr`, `func`, `arith`, `math` and `ub`. |
| `tests/compiler` (4) | `core-check` and `CoreCheck.idr` are deleted. `cc-contract` is revised: a foreign op fails to parse, and a profile rejection gets its new exit status. `artifacts` and `exec` are unchanged. |
| `tests/idr` (35 files) | `check-input` (6) is deleted, and the checks that survive move to `verify/` and `world/`. `e2e` (3), `lower` (8), `pipeline` (5) and `world` (4) are rewritten for the new contract. `effects`, `fold` and `verify` stay and grow. Every new op, folder, canonicalization, verifier and pass gets tests (TEST-IDR-1). |
| `tests/e2e` (123) | The programs are unchanged except in 4.3, and so are their stdout and exit expectations. The 14 `core.check` files become `mlir.check` files after the simplify loop, and the 7 existing `mlir.check` files are rewritten. |
| `tests/profile` | see 4.2 |
| `tests/determinism`, `registry`, `toolchain`, `mlir` | unchanged; `registry/FE-TR-7-identity-hook` reads `01-translate.core`, which stays |

### 4.2 Expected changes (predictions, confirmed at stop point 2)

| fixture | today | after | reason |
| --- | --- | --- | --- |
| profile/v1/reject/PROF-HEAP-3-reported-before-heap-5 | reject `PROF-HEAP-3` | **accept** | `idr.field` of a known `idr.con` folds, and fusion turns `putStrLn (strCons c "!")` into `put_char` and `put_str`. `report`'s action becomes a direct call, and `PROF-HEAP-5` is withdrawn. `DIAG-ONE-1` needs a new test. |
| profile/v1/reject/PROF-HEAP-3-stored-string | reject `PROF-HEAP-3` | **accept** | the same folding and fusion |
| profile/v1/reject/PROF-HEAP-5-division-before-action | reject `PROF-HEAP-5` | **accept** | The rule is withdrawn. The division runs where Idris runs it, before `ready`, as Chez does. |
| profile/v1/reject/PROF-HEAP-1-growing-choice | `PROF-HEAP-1` | `PROF-HEAP-1` | the lambda captures a closure of its own type, so no finite sum over labels represents it |
| profile/v1/reject/PROF-HEAP-2-growing-choice | `PROF-HEAP-2` | `PROF-HEAP-2` | the same, for a closure of no arguments |
| profile/v1/reject/PROF-HEAP-4-growing-function | `PROF-HEAP-4` | `PROF-HEAP-4` | The clone limit stops `iter`, whose closure then survives. Compiling this takes a limit's worth of clones. |
| profile/v1/reject/PROF-PRIM-4-runtime-match | `PROF-PRIM-4` | `PROF-PRIM-4` | a string built at runtime reaches a match |
| profile/v1/reject/PROF-TYPE-4-integer, v3/reject/PROF-TYPE-4-prelude-integer | `PROF-TYPE-4` | `PROF-TYPE-4` | A big exists at runtime. The second is reported at the user's code through the location chain; the reported line is checked at stop point 2. |
| profile/v3/reject/PROF-DATA-3-* | `PROF-DATA-3` | `PROF-DATA-3` | a box is built from runtime values |
| profile/v2/reject/PROF-HEAP-3-recursive-string | `PROF-HEAP-3` | `PROF-HEAP-3` | a recursive function returns a string built at runtime |
| every other reject fixture | its rule | the same rule | frontend rules |
| profile/v3/accept/SEM-BIG-1-static-integers, SEM-REC-2-streams | accept | **decision 7.2** | 4.3 |
| e2e/v3/compile-time-evaluation, prelude-math | accept | **decision 7.2** | 4.3 |
| all other accept fixtures and e2e | accept | accept, same output | The same program. The mechanism is inline, specialize (with partially static shapes, 7.3), evaluate, case-of-case, and defunctionalize. |

### 4.3 The four programs

"Partial code is never evaluated" rejects four programs that compile today.
In each, a closed call to a function Idris does not prove terminating
builds a value that the profile forbids at runtime:

| program | the call | Idris's verdict | then |
| --- | --- | --- | --- |
| e2e/v3/compile-time-evaluation | `euclid (the Integer 1071) 462` | `Main.euclid` is possibly not terminating (recursive path) | the call stays; its result is a runtime big, so `PROF-TYPE-4` |
| e2e/v3/prelude-math | `euclid (the Integer 48) 18` | the same | `PROF-TYPE-4` |
| profile/v3/accept/SEM-BIG-1-static-integers | `fact 30`, with `fact : Integer -> Integer` | not terminating (`Integer` is not structural) | `PROF-TYPE-4` |
| profile/v3/accept/SEM-REC-2-streams | `takeBefore (> 40) (countFrom 1 (* 2))` | `takeBefore` is declared `covering` in the Prelude and is possibly not terminating | the list is built at runtime, so `PROF-DATA-3` |

User modules cannot assert totality (`assert_total` and `assert_smaller`
are `%unsafe`, which `PROF-ESC-1` rejects), so these programs cannot be
made total by annotation. `fib 15` and `countdown 7` stop being evaluated
too, but their results are `Int`s, so nothing is rejected.

Options (7.2):
1. keep each program and change its expectation to the rejection;
2. rewrite the programs so that Idris proves them terminating;
3. **(recommended)** split each program. The total part stays an accept
   fixture, whose results `idr-eval` computes, which is the intent of
   acceptance bullet 2. The partial calls become named reject fixtures
   (`PROF-TYPE-4-partial-integer`, `PROF-DATA-3-partial-stream`) that
   document the rule. Record these as `PROF-GEN-4` exceptions.

### 4.4 Benchmarks

The recorded table is `bench/README.md` (best of 5). Every row reads its
size from stdin.

| row | what changes | risk |
| --- | --- | --- |
| nbody | `energy (offset initial)` is closed and total, so it becomes a constant; the loop is unchanged | low |
| mandelbrot, harmonic | loops come from `idr-tail-loops` instead of join points | low; the MLIR the loops produce differs in shape |
| fib, ackdyn | `fib` and `ack` are partial and run as they do today | low |
| ack (0.001 s) | `ack 3 n` is specialized for `m` = 3, 2, 1 and 0. The closed base calls `ack 2 1`, `ack 1 1` and `ack 0 1` stay generic calls, because `ack` is partial. | low: those calls take tens of steps |
| tak, collatz | division by a constant needs no crash branch (IDR-DIV-2) | low |
| all | printing goes through the C runtime by LTO, instead of MLIR helpers | measured at stop point 3 |

### 4.5 New tests the prompt requires

- **Equivalence:** `--no-eval`, run over every e2e program that compiles
  both ways.
- **The fuzzer:** closed pure expressions over every primitive, compared
  across compile time, runtime and Chez.
- **Folders:** each folder against its lowering through the JIT.
- **The two levels:** closed terms normalized by Idris's evaluator,
  compared with `idr-eval`.
- **Enforcement:** no primitive semantics in Idris; `Emit`'s dialects; a lit
  test for every canonicalization.
- **Termination:** a closed partial call that diverges on a path never
  taken, and an accumulator that would specialize forever.
- **Rules without a test after the moves:** a new `DIAG-ONE-1` test, and one
  test per new rule.

## 5. Deletions, and what comes back

Measured on main today. Exact numbers from `git diff --stat` come with
stop point 2.

| deleted | lines |
| --- | ---: |
| `Simplify.idr`, `Simplify/{Value,Gen,Fold,Safety}.idr` | 2,121 |
| `Code.idr`, `Code/Check.idr`, `Code/Loops.idr` | 1,068 |
| `Term/Check.idr` | 72 |
| `Emit.idr` (rewritten from scratch) | 513 |
| `tools/GenRyuTables.idr`, `tools/gen-ryu-tables.ipkg` | 154 |
| `Facts.idr`'s `block` and `inline` | about 12 |
| **Idris** | **about 3,940** |
| `Lower/Runtime.mlir.inc` | 930 |
| `CheckInput.cc`, `Entry.cc` | 236 |
| the module-copying half of `Lower/Runtime.{h,cc}` | about 45 |
| `LowerSwitch` (the `cf.switch` 1:N conversion) | about 50 |
| `Idr_Since`, `sinceVersion`, `idr.version` handling | about 25 |
| **C++ and MLIR text** | **about 1,290** |
| **code, total** | **about 5,230** |
| tests: `CoreCheck.idr` and `core-check`, `idr/check-input` (199 lines of MLIR), `spec/ryu-tables`, 14 `core.check` files (98 lines) | about 500 |
| docs: plan section 6's server design, `SEM-BIG-1`, first-order Core in 05, `ELIM-G-19`/`20` | rewritten at stop point 4 |

What comes back is nowhere near the 10% floor, because the MLIR side is new
machinery rather than a port. The estimates below are reported exactly at
stop point 2:

| added | estimate |
| --- | ---: |
| the dialect: types, attributes, ops, interfaces, folders, verifiers, canonicalizations | 1,500 |
| `idr-specialize`, `idr-eval` with the JIT, `idr-defunctionalize`, `idr-tail-loops`, `idr-check-profile`, the simplify driver, the effects pass | 2,300 |
| `idr-lower` for matches, constants, boxes, closures, bigs, strings and JIT mode | 800 |
| the runtime in C: IO, printing, the Ryu wrapper, strings, bigs, the arena, crashes | 1,200, plus vendored Ryu |
| the Idris side: the new `Emit` with type synthesis, `TermF`, one `Ty` | 700 |

## 6. The target, file by file

### 6.1 Idris

- **`Types.idr`**: one `Ty`. Its cases are the scalars, `StrT`, `BigT`,
  `WorldT`, `ErasedT`, `DataT DataId` (the data declaration records the
  representation), `FunT` and `LazyT`, and `StaticT` goes. The
  representation is decided once per monomorphic data instance:
  - `Sop` for non-recursive data, including data holding closures;
  - `Box` for recursive data;
  - `Big` for types Idris flags `ZERO`/`SUCC`.

  `PrimOp` loses its compile-time-only string split.
- **`Term.idr`**: `Term a`, a nested datatype (Bird and Paterson), with
  binders over `Term (Var a)`. Derived `Functor` renames, derived
  `Foldable` gives free variables, and derived `Traversable` strengthens.
  The derivations come from `Deriving.*` in base. A base functor `TermF`
  with `cata` and `para` replaces `lift`, `liftN`, `weaken`, `unbind`,
  `matchedParams` and `captures` (7.9).
- **`Translate.idr`**: unchanged except for the representation decision
  above, the single `Ty`, and `Facts` reduced to `terminating`, read with
  `checkTotal` as today (`Translate.idr:1281`).
- **`Emit.idr`**: new, one fold over `Term`. Types are synthesized, because
  TTC drops `let` types (FE-TR-1). A lambda or `Suspend` becomes a lifted
  `func.func` whose leading parameters are its captures. `Case` becomes
  `idr.match` and `CaseLit` becomes `idr.match_lit`; impossible
  alternatives are left out. `Crash` becomes `idr.crash` and
  `ub.unreachable`. `Nat`-like matches and constructors become big
  arithmetic. Loop breakers get `no_inline` (A5), and functions get
  `idr.total` and `idr.quantity`. Library code gets its origin in its
  location (7.11). Ops are written in custom syntax (7.10).
- **`Frontend/Main.idr`**: `Translate`, then `Emit`, then `idris-mlir-cc`,
  for IO programs as today. For `main : Int`, `idris-mlir-cc --check` runs
  before artifacts are written, and its exit status maps to an Idris error
  (7.11).
- **Registry**: the *Inline hints* column is deleted. *Break last* is read
  by `Emit`, and *Report at caller* becomes location metadata.

### 6.2 The dialect

- **Types**:
  - `!idr.data<@T>`, an unboxed sum;
  - `!idr.box<@T>`;
  - `!idr.fn<(A…) -> (R…)>`, with `Lazy` and `Inf` as `!idr.fn<() -> (R)>`;
  - `!idr.str`, `!idr.big`, `!idr.world`, `!idr.erased`;
  - the builtin scalar types.
- **Attributes**: `#idr.con<@T::@C, [...]>`, `#idr.closure<@f, [...]>` and
  `#idr.big<"decimal">`. Strings are `StringAttr`, and scalars are
  `IntegerAttr` and `FloatAttr`. `#idr.hole` is internal to specialization
  keys and never appears in the contract.
- **Ops**. The contract ops are:
  - `idr.constant` (`ConstantLike`, `materializeConstant`);
  - `idr.con`, `idr.field`, `idr.tag`;
  - `idr.match` and `idr.match_lit`, with `idr.yield`;
  - `idr.closure` and `idr.apply`;
  - `idr.crash`;
  - the scalar ops `idr.div`, `idr.mod`, `idr.to_char`, `idr.to_int`,
    `idr.double_head` and `idr.int_head`;
  - `idr.str.*` (`append`, `cons`, `from_char`, `show`, `length`, `index`,
    `head`, `tail`, `substr`, `reverse`, comparisons, `to_int`,
    `to_double`);
  - `idr.big.*` (arithmetic, bitwise, comparisons, casts, and to and from
    strings);
  - `idr.io.*` as today.

  `idr.may_loop` exists only after `idr-tail-loops`.
- **Traits and interfaces**:
  - `idr.match` implements `RegionBranchOpInterface` and has
    `RecursiveMemoryEffects` and `RecursivelySpeculatable`; `idr.yield`
    implements `RegionBranchTerminatorOpInterface`.
  - `idr.apply` implements `CallOpInterface`, with a value callee.
  - The ops that name symbols implement `SymbolUserOpInterface`.
  - `idr.tag`, `idr.to_char`, `idr.int_head`, `idr.double_head` and
    `idr.str.length` implement `InferIntRangeInterface`.
  - `idr.div`, `idr.mod`, `idr.to_int`, `idr.str.head` and `idr.str.index`
    have conditional effects, as `IDR-EFF-1` defines them.
  - A box's `idr.con`, the string builders and the big ops allocate their
    results (`MemAlloc`).
  - The IO ops keep `IDR-EFF-2`, and A21 applies.
- **Folders** fold on constants. Those of string, `Double`-printing and big
  ops call the runtime's C.
- **Canonicalizations**:
  - DRR: A2 and A4.
  - C++: apply-of-closure (DRR cannot concatenate variadic operand lists),
    and the region patterns. A match on a constant inlines its region, so
    does a match with one region left, unused results drop, identical
    regions merge, and case-of-case applies (A3).
  - A20, as a dialect-level pattern on `func.call`.
- **Verifiers**: op verifiers, the attribute verifier of each function and
  of the module (world linearity, one public root, acyclic containment
  through sums), and the parse-time registry (A19).

### 6.3 Passes and the pipeline

```
idr-simplify (repeated until OperationFingerPrint says a round changed nothing):
  idr-effects
  inline{default-pipeline=canonicalize max-iterations=K}
  idr-specialize
  sccp, canonicalize, cse
  idr-eval
  remove-dead-values, symbol-dce
idr-defunctionalize
canonicalize
idr-tail-loops
idr-check-profile
idr-lower
canonicalize, cse
convert-scf-to-cf, convert-to-llvm, reconcile-unrealized-casts
```

- **`idr-effects`** computes, per function, `idr.effect` (whether it
  reaches an `idr.io` op, `unsafePerformIO` included) and "may crash". It
  runs every round, because clones and evaluation change the call graph.
- **`idr-specialize`** specializes calls with constant-like arguments
  (7.3). The key is the callee plus the constant pattern, with runtime
  leaves as `#idr.hole`. A closed call is never specialized (7.4).
  - The clone limit is `--idr-clone-limit`, default 4096, counted per
    original callee. Every call it stops gets a `Missed` remark.
  - A clone's `idr.total` is its origin's, together with that of every label
    in its constant arguments.
- **`idr-eval`**: section 6.4.
- **`idr-defunctionalize`** runs on MLIR's dataflow framework. The lattice
  holds sets of labels. Values reach fields through a lattice anchor per
  (type, constructor, field), and the entry arguments of each possible
  callee are updated at an `idr.apply`. That handling is needed because the
  framework's interprocedural mode follows only symbol callees. A finite set
  becomes a sum over labels, and `idr.apply` on it becomes an `idr.match`.
- **`idr-tail-loops`** turns self tail calls into `scf.while`, with
  `idr.may_loop` in functions that are not total.
- **`idr-check-profile`** checks section 3.3's revised rules, reporting the
  op's location chain.
- **`idr-lower`** lowers matches to `idr.tag` and `scf.index_switch`,
  constants to static data, and boxes, closures, bigs and strings to their
  layouts. JIT mode swaps in the arena and the crash report. It uses
  `allowPatternRollback = false` if every pattern permits it.
- **Termination** (`OPT-PIPE-5`). Inlining never goes around a cycle,
  because loop breakers cut every cycle. Clones are bounded by the limit.
  Every evaluation terminates (7.1) and removes a call. So the loop reaches
  a fixpoint.

### 6.4 `idr-eval`

- **What is evaluated**: a `func.call`, or an `idr.apply` of a constant
  closure, whose operands are all constants. The callee must be pure and
  total, and so must every label in the operands, recursively through
  captures and fields (7.1, 7.4).
- **One compile per round.** The pass collects every closed call and clones
  the callees' transitive closure into one scratch module. For each call it
  adds a wrapper that materializes the arguments as static data, calls the
  callee, and stores the flattened results through a pointer. The module is
  lowered with the executable's own `idr-lower` (in JIT mode) and LLVM
  pipeline, and JITed once with ORC `LLJIT`. The runtime's symbols are
  bound to `idris-mlir-cc`'s own copies through `absoluteSymbols`. Results
  are cached per (callee, arguments) for the compilation.
- **The child.** `idris-mlir-cc` runs MLIR single-threaded, then forks. The
  child runs the round's calls on a stack reserved as large as the address
  space allows (`MAP_NORESERVE`, committed lazily). It turns each result
  into its attribute text, using the same layout code as `idr-lower`, and
  writes it to a pipe; the parent parses it.
- **Crashes and exhaustion**:
  - a crash reported by the runtime leaves that call in place, and the
    parent forks again for the remaining calls;
  - a fault on the stack guard, a failed arena `mmap`, or a `SIGKILL` from
    the OOM killer is `EVAL-1`;
  - any other signal is an internal error.
- **Remarks**: `--remarks=idr-eval`. `Passed` carries wall-clock time
  (7.12). `Missed` fires only for a crash, with the call-site chain.
- **`--no-eval`**: the knob of section 10.

### 6.5 The runtime

- **Additions to `runtime/`**:
  - output buffering: `put_str`, `put_char`, `put_int` and `put_double`;
  - input: `get_char` and `get_byte`;
  - `exit` and `crash`;
  - `f64_to_i64`, `double_head` and `int_head`;
  - Ryu, as a submodule, with the tie wrapper;
  - strings, over simdutf, and `cast` from `String` over fast_float;
  - bigs: a small-integer fast path, and GMP otherwise;
  - the JIT's arena.
- **Linking**:
  - executables join the runtime's bitcode by LTO, as today;
  - `idris-mlir-cc` links it natively, so folders and the JIT call the same
    code.
- **The Ryu wrapper** (`SEM-DBL-5`): it calls `d2s`, then checks with exact
  digits whether the shortest candidate is a tie, and if so takes the
  larger. `double-print-fuzz` keeps it honest.

### 6.6 Driver and diagnostics

- **Exit statuses of `idris-mlir-cc`**: `0` success; `1` contract violation
  or pass failure (internal); `2` usage; `3` a profile rejection (a user
  error); `4` `EVAL-1`.
- **Rejection message**: `unsupported (<RULE>)`, with the op's location
  chain. The frontend turns it into an Idris error, with an `FC` from the
  innermost location of user code (7.11).

### 6.7 Toolchain

- Add `mlir-reduce` to `stage2_components`.
- Build the stage-2 musl toolchain in this container.
- `idris-mlir-cc` links `LLVMOrcJIT`, which is part of `llvm-libraries`
  (already built), and GMP.

## 7. Decisions for you

Each item has a recommendation. Unless you overrule it, stop point 2
proceeds on the recommendation.

1. **What "total" means.** Idris's totality has two parts, and `checkTotal`
   returns only the termination part (`Core/Termination.idr:101`). The
   division primitives are "not covering" in Idris. So with the full
   notion, every function that divides would be partial, and the prompt's
   own example ("a total function can still crash: division by zero") would
   be impossible. **Recommendation:** evaluate exactly when `checkTotal` is
   `IsTerminating`, which is what the frontend reads today. A coverage
   failure is a crash, and a crash leaves its call in place.
2. **The four programs** (4.3). **Recommendation:** option 3, split them,
   and record the `PROF-GEN-4` exceptions.
3. **Constant-like.** Read literally, "`idr.con`/`idr.closure` with
   constant-like operands" excludes a list with one runtime element. Then
   `sum [1, 2, n]`, `show (Just n)` and `len (list n)` have nothing to
   specialize on, and `prelude-lists`, `vect`, `choice` and `show-values`
   would be rejected. **Recommendation:** partially static values. The
   static part is the key, and the runtime leaves become the clone's
   parameters, which is `ELIM-G-3` today.
4. **Closed calls to partial functions** are neither evaluated nor
   specialized (A23). **Recommendation:** yes.
5. **Removing unused calls** needs pure, total and **cannot crash** (A20).
   **Recommendation:** yes; the prompt's rule, without the third condition,
   would drop crashes that `SEM-EVAL-4` requires.
6. **Case-of-case** (A3) and **crash/IO ordering** (A21) are added.
   **Recommendation:** yes.
7. **The JIT on `LLJIT`**, not `ExecutionEngine` (section 1, row 18).
   **Recommendation:** yes, recorded in `PINS.md`.
8. **Results as attribute text** from a forked child, and `EVAL-1` for
   exhausted resources (6.4). **Recommendation:** yes.
9. **`Term` as a nested datatype.** `Deriving` needs a type parameter, and
   today's `Term : Nat -> Type` has none. **Recommendation:** `Term a`,
   which keeps scoping by type (a closed term is `Term Void`), with `TermF`
   for folds. The alternative is a hand-written `TermF` with no derived
   instances, which leaves the prompt's `Deriving.*` unused.
10. **Custom syntax in `Emit`** instead of the generic form (`IDR-MOD-2`).
    With it, `cmpi` predicates and segment sizes are written by the ops'
    own printers and parsers. **Recommendation:** yes, for `idr` and for
    the upstream ops.
11. **User errors from C++**, in three parts:
    - exit status 3;
    - the frontend runs the check for `main : Int` too, so `--check` fails
      and writes no artifact;
    - library locations carry their origin as `FusedLoc` metadata, so
      errors are reported at the user's caller (DIAG-LOC-1).

    **Recommendation:** all three.
12. **Remarks report wall-clock time**, not step counts (A15). The prompt
    asks for both "step count" and "no counters".
    **Recommendation:** time.
13. **The profile stays v3.** Rules the cutover changes are marked "revised
    at the cutover", as earlier revisions were. **Recommendation:** yes. M1
    remains v4.
14. **Host-dependent primitives in types.** Where a type depends on `cast`
    from `String` or on a libm function, the two levels can disagree by
    design. **Recommendation:** a named rejection (a new `SEM` rule) where
    the frontend finds such a term in a type, and the fast_float grammar in
    03 now (A25).
15. **The branch.** The prompt says `cutover`, in a worktree, and this
    session was given `claude/lucid-pasteur-4dwdxs`. **Done so far:** the
    worktree `.worktrees/cutover` is on a local branch named `cutover`,
    which is pushed to `claude/lucid-pasteur-4dwdxs`. **Question:** should
    it also be pushed as `cutover`?
16. **Principles.** `GOAL-P2`, `GOAL-P4`, `GOAL-P6` and `D14` are
    contract-level, and the cutover reverses them (3.9).
    **Recommendation:** rewrite them at stop point 4.

## 8. Work plan

### 8.0 Before stop point 2

- Add `mlir-reduce` to `tools/bootstrap.sh`, as its own commit.
- Finish the stage-2 bootstrap (hours on 4 cores).
- Check that `make build` produces a static `idris-mlir-cc`.

### 8.1 To stop point 2

1. **Deletions first**, in their own commits (section 5). The branch may be
   red until step 6.
2. **Idris**: one `Ty` and the representations; `Term a` and `TermF`;
   `Facts`; the new `Emit`; `Main`'s pipeline.
3. **The dialect**: types, attributes, ops, interfaces, folders,
   canonicalizations and verifiers, each with lit tests.
4. **The passes**: `idr-effects`, `idr-specialize`, `idr-eval`,
   `idr-defunctionalize`, `idr-tail-loops`, `idr-check-profile`, the new
   parts of `idr-lower`, and the simplify driver.
5. **The runtime**: C, and Ryu as a submodule.
6. **The first green subset**: v0, then v1, v2 and v3, with a list of what
   fails and why.

Stop point 2 reports the deleted and added line counts.

### 8.2 To stop point 3

- Equivalence (`--no-eval`), the fuzzer, folders against lowerings, the two
  levels, and the enforcement tests.
- `bench/` against `bench/README.md`, and every fixture's compile time,
  with the slowest ten broken down by pass, JIT compilation and evaluation.
- The suites' wall time before and after.
- In 14-testing: bisecting a rewrite with the action framework and
  `--mlir-debug-counter`, and shrinking a module with `mlir-reduce`.

### 8.3 To stop point 4

- The spec: 01, 02, 03, 04, 05, 06, 08, 09, 10, 12, 13, 14 and 17, as
  section 3 says.
- `plan.md`:
  - sections 1, 6 and 8 rewritten;
  - M1 to M3 restated as "lower instead of reject", op by op;
  - decision 6 becomes `idr-eval`;
  - decision 13 is withdrawn.
- The "who owns what" note.
- This file is deleted.
- The merge, with the line counts in its message.

## 9. Acceptance (section 11), and how each is checked

| criterion | check |
| --- | --- |
| every suite green; every changed expectation listed with its reason; no program rejected both before and after under a different rule | `make check`, `build`, `test`, `test-idr`, `test-mlir-tools`; section 4.2 kept current; the reject fixtures keep their `expect:` lines |
| the v3 programs that needed compile-time evaluation compile, with `idr-eval` computing their results | an `mlir.check` per fixture on the module after the simplify loop (no call left); 4.3 as you decide |
| equivalence and the fuzzer are green | new suites (4.5) |
| `bench/` within noise on every row, each reading its size at runtime | `make bench` against `bench/README.md` |
| compile times per fixture, with the JIT's share | the harness's timing report (8.2) |
| no closed call to a pure total function survives in the e2e suite, except those that crash | a test over the final MLIR of every e2e fixture, run with `--remarks=idr-eval` |
| the deletions are done; the line counts are in the merge message | section 5, from `git diff --stat` |
| the spec matches the code | stop point 4; `make check` (TEST-SPEC-1) |
| the "who owns what" note | stop point 4 |

## 10. The contract (normative for the implementation)

This section is what the Idris side (`Emit`) and the C++ side implement
independently. It becomes [08](architecture/08-idr-dialect.md) at stop
point 4. The decisions of section 7 are adopted as recommended.

### 10.1 Module and functions

```mlir
module attributes {idr.program} {
  idr.data @Main.Shape { ... }                 // declarations first
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"})
      -> !idr.data<@PrimIO.IORes$91$Builtin.Unit$93$> attributes {idr.total} { ... }
  func.func private @Main.area(...) -> f64 attributes {idr.total} { ... }
}
```

- The module carries the unit attribute `idr.program`; the dialect's
  attribute verifier checks module-level rules there: exactly one public
  `func.func` (the root), acyclic containment through unboxed sums
  (`IDR-DATA-4`), and that every `idr.data` and `func.func` symbol resolves.
- The root is the only public function. Its type is `() -> i64` (a
  `main : Int` program) or `(!idr.world) -> (...)` (an IO program). There is
  no `idr.version`, `idr.entry` or `idr.entry_kind`.
- Every other `func.func` is private. Every argument carries
  `idr.quantity = "0" | "1" | "w"` (`"0"` exactly on `!idr.erased`).
  A function Idris reports terminating carries the unit attribute
  `idr.total`. A loop breaker (`OPT-PIPE-3`) carries `no_inline`.
  `idr-effects` adds `idr.effect = "pure" | "effectful"` and the unit
  attribute `idr.may_crash`; `Emit` never writes them.
- A function's body is one block; control flow is regions. A lambda or a
  `Delay` becomes a private `func.func` whose leading parameters are its
  captures, then its own parameters (none for a `Delay`).
- Emit writes every op in its custom (pretty) syntax, and upstream ops in
  theirs: `arith.cmpi slt, %a, %b : i64`, never generic-form predicates.
- Every op has a location. Definitions are `NameLoc`s around the
  `FileLineColLoc` (`IDR-DATA-5`). Code from a library module (the
  registry's *Report at caller* column) is wrapped in
  `loc(fused<"library">[...])`, so diagnostics can report at the user's
  caller.

### 10.2 Types

| type | meaning |
| --- | --- |
| `i8`, `i16`, `i32`, `i64` | the fixed-width integers (`Char` is `i32`) |
| `f64` | `Double` |
| `i1` | only results of comparisons and conditions of `idr.match_lit` on them |
| `!idr.data<@T>` | a value of the unboxed sum `@T` |
| `!idr.box<@T>` | a value of the boxed (recursive) type `@T` |
| `!idr.fn<(A...) -> (R...)>` | a closure; `Lazy a` and `Inf a` are `!idr.fn<() -> (a)>` |
| `!idr.str` | a string (UTF-8) |
| `!idr.big` | an `Integer`, or a `Nat`-like type (non-negative) |
| `!idr.world` | the IO world token |
| `!idr.erased` | a quantity-0 value |

### 10.3 Data declarations

```mlir
idr.data @Main.Shape {
  idr.ctor @Circle tag 0 (f64) {quantities = ["w"]}
  idr.ctor @Rect tag 1 (f64, f64) {quantities = ["w", "w"]}
}
idr.data @Prelude.Basics.List$91$Int$93$ box {
  idr.ctor @Nil tag 0 () {quantities = []}
  idr.ctor @$58$$58$ tag 1 (i64, !idr.box<@Prelude.Basics.List$91$Int$93$>) {quantities = ["w", "w"]}
}
```

- `box` marks a boxed declaration; values of it have type `!idr.box<@T>`,
  values of the others `!idr.data<@T>`. The verifier rejects the wrong one.
- A recursive type is boxed. A `Nat`-like type (Idris's `ZERO`/`SUCC`
  flags) has no declaration: it is `!idr.big`.

### 10.4 Constant attributes

| attribute | value |
| --- | --- |
| `#idr.con<@T::@C, [f1, f2]>` | a constructor of a sum or box, fields as attributes, nested |
| `#idr.closure<@f, [c1, c2]>` | a closure of `@f` with its captures |
| `#idr.big<"-123">` | an integer of any size, in decimal |
| `#idr.erased` | the erased value |
| `"bytes"` (`StringAttr`) | a string, UTF-8 |
| `IntegerAttr`, `FloatAttr` | scalars |

### 10.5 Ops

Values and constants:
- `%v = idr.constant #idr.con<...> : !idr.data<@T>` materializes any
  attribute above (`ConstantLike`); `Emit` uses it for strings, bigs and
  erased values, and `arith.constant` for integers and doubles.
- `%v = idr.con @T::@C(%a, %b) : (i64, f64) -> !idr.data<@T>` (or
  `-> !idr.box<@T>`, which allocates).
- `%x = idr.field %v[@C, 1] : !idr.data<@T> -> f64`
- `%t = idr.tag %v : !idr.data<@T>` (result `i64`)

Matches:

```mlir
%r:2 = idr.match %v : !idr.data<@Main.Shape> -> (f64, !idr.world) {
case @Circle(%r: f64) {
  ...
  idr.yield %a, %w1 : f64, !idr.world
}
case @Rect(%w: f64, %h: f64) {
  ...
}
default {
  ...
}
}
%s = idr.match_lit %n : i64 -> (i64) {
case 0 { idr.yield %c1 : i64 }
case 1 { ... }
default { ... }
}
```

- `idr.match` has one region per reachable constructor, whose block
  arguments are that constructor's fields, and an optional default with
  no arguments. Constructors Idris proved impossible are left out, and no
  default is invented for them.
- `idr.match_lit` keys are integers, characters (`i32`), strings or bigs,
  all distinct, and a default is required.
- A region ends in `idr.yield` or in `ub.unreachable` (after `idr.crash`).

Closures:
- `%c = idr.closure @f(%x, %y) : (i64, i64) -> !idr.fn<(i64) -> (i64)>`
- `%r = idr.apply %c(%a) : !idr.fn<(i64) -> (i64)>`

Crashes: `idr.crash "unhandled input for Main.f"` then `ub.unreachable`.

Scalars (unchanged): `idr.div`, `idr.mod`, `idr.to_char`, `idr.to_int`,
`idr.double_head`; new `%c = idr.int_head signed %x : i64` (the first
character of the decimal text).

Strings (`!idr.str`):
- `idr.str.append %a, %b`
- `idr.str.cons %c, %s`
- `idr.str.from_char %c`
- `idr.str.show signed %x : i64`, `idr.str.show unsigned %x : i8`,
  `idr.str.show %x : f64`
- `%n = idr.str.length %s` (i64)
- `%c = idr.str.index %s, %i` (i32, crashes out of range)
- `idr.str.head %s`, `idr.str.tail %s` (crash on `""`)
- `idr.str.substr %s, %start, %len`
- `idr.str.reverse %s`
- `%b = idr.str.cmp lt %a, %b` (`eq`, `lt`, `lte`, `gt`, `gte`; result `i1`)
- `%n = idr.str.to_int signed %s : i64`, `%d = idr.str.to_double %s`

Bigs (`!idr.big`):
- `idr.big.add`, `sub`, `mul`, `div`, `mod`, `and`, `or`, `xor` (`div` and
  `mod` crash on zero)
- `idr.big.neg %a`
- `%b = idr.big.cmp lt %a, %b` (result `i1`)
- `idr.big.from_int signed %x : i64`, `%x = idr.big.to_int %b : i32` (wraps)
- `idr.big.from_double %d` (crashes on a non-finite value),
  `idr.big.to_double %b`
- `idr.big.show %b`, `idr.big.from_str %s`

`Nat`-like values: `Z` is `idr.constant #idr.big<"0">`, `S x` is
`idr.big.add %x, %one`, and a match on one is an `idr.match_lit` with
`case #idr.big<"0">` and a default that computes the predecessor with
`idr.big.sub`.

IO, unchanged: `idr.io.put_str`, `put_char`, `put_int`, `put_double`,
`get_char`, `get_byte`, `exit`.

Internal to the pipeline, never written by `Emit`: `idr.may_loop`.

### 10.6 Primitive mapping (`IDR-IN-3`)

As today for integers, characters and doubles: `arith` and `math` ops with
no flags, `idr.div`/`idr.mod`/`idr.to_char`/`idr.to_int`; comparisons as
`arith.cmpi`/`arith.cmpf` then `arith.extui` to `i64`. `String` primitives
map to `idr.str.*`, `Integer` primitives to `idr.big.*`, and casts between
`Integer` and the other types to `idr.big.from_*`/`to_*`. A string
comparison primitive is `idr.str.cmp` then `arith.extui`.

### 10.7 Division of labour

| component | owner | paths |
| --- | --- | --- |
| `Types`, `Term`, `Translate`, `Emit`, `Main` | Idris | `compiler/` |
| types, attributes, ops, interfaces, folders, verifiers, canonicalizations, `idr-effects` | dialect | `foreign/idr/include`, `foreign/idr/lib/Dialect`, `tests/idr/{verify,fold,canon,effects,world}` |
| `idr-specialize`, `idr-defunctionalize`, `idr-tail-loops`, `idr-check-profile`, the simplify driver | passes | `foreign/idr/lib/Passes`, `tests/idr/{specialize,defunc,loops,profile,pipeline}` |
| `idr-lower`, `idr-eval` and the JIT, `idris-mlir-cc`, the C runtime and Ryu | lowering | `foreign/idr/lib/Lower`, `foreign/idr/lib/Eval`, `foreign/idr/tools`, `runtime/`, `tests/idr/{lower,eval,e2e}` |
