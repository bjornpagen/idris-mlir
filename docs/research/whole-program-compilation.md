# Whole-program compilation: prior art and what we need

> Research note, September 2026. Pinned sources: Idris `1c630e67`, LLVM
> `llvmorg-23.1.2`. MLton and Lean 4 facts come from their source trees
> (shallow clones of `MLton/mlton` and `leanprover/lean4` main). Paper summaries marked
> *(abstract)* come from abstracts and search results only: arxiv, mlton.org,
> and most university hosts were blocked from this environment.

## The question

We now compile a tiny first-order subset: checked TT → our IR → erasure →
MLIR text → native. Everything real is missing: IO, data, closures, the
Prelude, memory management. This note looks at compilers that solved those
problems for similar languages, checks what MLIR actually provides, and turns
that into an ordered plan.

## MLton: whole-program, typed all the way down

MLton's pipeline (`doc/guide/src/CompilerOverview.adoc`):

| IL | Character | Produced by |
| --- | --- | --- |
| CoreML | elaborated SML | Elaborate |
| XML | polymorphic, higher-order, flat patterns, every expression typed | Defunctorize |
| SXML | same, simply typed | Monomorphise |
| SSA | first-order, simply typed; datatypes + functions of basic blocks | ClosureConvert |
| SSA2 | SSA plus mutable object fields, n-ary vectors | ToSSA2 |
| RSSA | representation decisions explicit; subtyping on bit-level layouts | ToRSSA |
| Machine | untyped, infinite temporaries | ToMachine |

What carries over to us:

- **Whole program is the design, not an option.** "Whole-program compilation
  is an integral part of the design of MLton and is not likely to change."
  It enables defunctorization, monomorphisation, higher-order control-flow
  analysis, inlining, unboxing, argument flattening, redundant-argument
  removal, and representation selection (`WholeProgramOptimization.adoc`).
- **Monomorphisation relies on SML's restrictions.** MLton duplicates each
  polymorphic function per type instance. That terminates only "due to the
  absence of polymorphic recursion in SML" (`Monomorphise.adoc`). Idris has
  polymorphic recursion and types that depend on values, so we cannot
  monomorphise everything. We need specialization where it is finite and a
  uniform representation elsewhere.
- **No closures at runtime.** "Based on whole-program higher-order
  control-flow analysis, MLton represents a function as an element of a sum
  type, where the variant indicates which function it is and carries the free
  variables as arguments" (`Closure.adoc`). This is flow-directed
  defunctionalization (Cejtin, Jagannathan, Weeks, ESOP 2000). The result is
  a first-order program that standard SSA optimizations understand.
- **Most of the wins are cheap, generic SSA passes** once the program is first
  order and typed: `Contify` turns functions that always return to one place
  into continuations (loops), plus `KnownCase`, `Useless`, `RemoveUnused`
  (unused constructors, arguments, returns), `Flatten` (unboxed tuple
  arguments), and size-metric `Inline` (`SSASimplify.adoc`).
- **Representation is its own IL.** RSSA makes packing and layout explicit.
  Deep flattening "does not have a significant impact" on MLton's benchmarks
  (`DeepFlatten.adoc`), a useful caution against over-investing in layout
  before measuring.
- **Memory**: a tracing GC that switches between copying, mark-compact, and
  generational collection (`GarbageCollection.adoc`).

## Lean 4: the closest analogue

Lean is dependently typed, strict, and compiles its own core language through
its own IRs to C or LLVM. `src/Lean/Compiler/LCNF/Passes.lean` has three phases:

1. **base**: A-normal form with join points ("Compiling without
   continuations"). CSE, simp, float-let-in, eager lambda lifting, and
   **specialization**.
2. **mono**: types lose dependencies; irrelevant types become `lcErased` or
   `lcAny`. Arity reduction, struct projection cases, and lambda lifting.
3. **impure**: `insertResetReuse`, `inferBorrow`, `explicitBoxing`,
   `explicitRc`, `expandResetReuse`, `coalesceRC`.

Lean does not monomorphise. It specializes parameters classified in
`SpecInfo.lean`: `fixedInst` (type class instances fixed across recursion,
always specialized), `fixedHO` (fixed higher-order arguments), `fixedNeutral`
(irrelevant parameters that others depend on), and `user`. Everything else stays
uniform (boxed `lcAny`). That is the model Idris needs: interface
dictionaries play the role of instances.

Memory is precise reference counting with in-place reuse of uniquely owned
constructors (Ullrich and de Moura, "Counting Immutable Beans", IFL 2019
*(abstract)*), which also enables destructive updates in pure code.

## Koka / Perceus

Perceus (Reinking, Xie, de Moura, Leijen, PLDI 2021 *(abstract)*) inserts
precise reference counts so programs are garbage free, then does reuse
analysis for guaranteed in-place updates ("functional but in-place").
Koka specializes higher-order functions like `map`/`fold` to their arguments
*before* inserting reference counts, and compiles to C with no GC.

Idris's RefC backend already does a dynamic form of this: it checks
uniqueness at run time before reusing a constructor. A linear quantity does
*not* prove uniqueness (see our semantic rules), so a static reuse analysis
must still be justified by reference counts or ownership analysis.

## Other relevant work

- **Erasure.** Tejiščák's thesis, "Erasure in Dependently Typed Programming"
  (St Andrews, 2020) *(abstract)*: proof terms can dominate runtime
  asymptotically, and irrelevance or universe-based erasure is not enough. It
  proposes flow-based useless-variable elimination (what Idris 1 used)
  and typed erasure inference. Idris 2 instead relies on explicit quantity-0
  annotations (QTT). Our erasure pass does that today. A later usage analysis
  (MLton's `Useless`/`RemoveUnused`, or MLIR's `remove-dead-values`) can erase
  more.
- **Defunctionalization.** Futhark (Hovgaard, Henriksen, Elsman, TFP 2018)
  *(abstract)* restricts higher-order types so defunctionalization always
  succeeds with no branching. Huang and Yallop (PLDI 2023) *(abstract)* give
  the first formal defunctionalization for a dependently typed language. We
  defunctionalize after erasure, on simple types, so we need MLton's version,
  not theirs.
- **CertiCoq** (Anand, Appel et al.) *(abstract)*: verified Coq → C, whole
  program. Its pipeline works on untyped ANF/CPS (λANF), with closure
  conversion, uncurrying, shrink reductions, and inlining. It is evidence that
  a dependently typed source can be compiled after erasure through an
  ordinary functional middle end.
- **GRIN** (Boquist; Podlovics, Hruska, Pénzes 2021) *(abstract)*:
  whole-program backend for lazy and strict functional languages with
  interprocedural heap-points-to analysis. It is relevant if laziness (`Lazy`, `Inf`) becomes
  performance-critical.
- **Functional programs in MLIR.** Bhat and Grosser, "Lambda the Ultimate SSA"
  (CGO 2022) *(abstract)*: a Lean 4 backend in MLIR that models functional
  constructs with regions, reaching performance parity with Lean's backend.
  They needed **custom dialects**. Under our no-C++ rule we cannot do that,
  so the functional optimizations must happen in our own IRs, as MLton and
  Lean do.

## What MLIR actually gives us (checked in the pinned source)

- **Lowering to LLVM**: `convert-to-llvm` covers `arith`, `cf`, `func`,
  `index`, `math`, `memref`, `ptr`, `ub`, `vector`, and `complex`. `scf` needs
  `convert-scf-to-cf` first, which our tests already run.
- **Generic passes** (`mlir/include/mlir/Transforms/Passes.td`): `canonicalize`, `cse`,
  `inline`, `sccp`, `symbol-dce`, `remove-dead-values` (drops non-live
  function arguments and results across callers), `mem2reg`, `sroa`,
  `loop-invariant-code-motion`, `control-flow-sink`.
- **Tail calls**: `func.call` has no tail-call control. `llvm.call` has
  `tail_call_kind` (`tail`, `musttail`, `notail`). Idris programs loop
  through tail recursion, so we must either turn tail calls into loops
  ourselves (MLton's contification) or emit `llvm.call ... musttail` for
  calls that must not grow the stack.
- **GC hooks**: `llvm.func` has a `garbageCollector` attribute (LLVM GC
  strategies and statepoints). A precise tracing GC through that route means
  stack maps and a runtime; reference counting needs only calls.
- **No functional constructs**: no ADTs, closures, thunks, or reference
  counting in any upstream dialect. Heap objects are `llvm.call @malloc` plus
  `llvm.getelementptr`/`load`/`store`, or `memref` for arrays.
- **Where MLIR earns its place**: loops and arrays (`scf`, `affine`, `memref`,
  `vector`) for kernels over contiguous data. For ordinary functional code,
  emitting MLIR buys little over emitting LLVM IR directly. The project's
  performance thesis rests on the kernel path, which should be demonstrated
  early rather than assumed.

## What Idris hands us

- `compileExpr` receives `unsafePerformIO main` and the whole context: a
  whole-program entry point, like MLton's.
- IO is world passing: `PrimIO a = (1 w : %World) -> IORes a`, with
  `MkIO` wrapping it. Erasing the world token and inlining `io_bind`
  yields ordered first-order code.
- Checked definitions keep their types, quantities, and compile-time case
  trees. TTC drops runtime trees and the types of machine-generated names.
  A per-module sidecar of our IR, written by the incremental callback, keeps
  what TTC drops. The Prelude and base must be built through our backend to
  get sidecars, since an import without our incremental data disables the
  callback.
- Idris already performs `%spec` partial evaluation, inlining, newtype
  erasure, Nat-as-Integer, and enum tags. Our output must at least match
  these, or we are measuring regressions.

## The plan

The IR ladder, in MLton/Lean terms:

1. **Typed IR** (ours; exists as v0): higher-order, with quantities, constructor
   and index facts, explicit laziness and effects. Interface specialization
   (Lean's `fixedInst`/`fixedHO`) and inlining happen here, while types are
   known.
2. **Erasure** (exists): quantity 0, later usage-based.
3. **First-order IR**: defunctionalized whole program (MLton), constructors
   with runtime layouts, explicit `dup`/`drop` (Perceus/Lean) and reuse.
   Contification turns tail calls into loops.
4. **MLIR text**: `func`/`cf`/`scf`/`arith`/`llvm`, with `memref`/`vector` for
   array kernels. Upstream `inline`, `sccp`, `remove-dead-values`, and
   `canonicalize` run before `convert-to-llvm`.

Milestones, each with an executable test, compared against the stock Idris
Chez backend on the same program (differential testing, with exit status and
output checked):

1. **Whole-program entry and IO.** Implement `compileExpr`: link per-module
   sidecars, lower `unsafePerformIO main`, erase `%World`, and support
   `%foreign "C:..."` calls. Then the compiler runs the MLIR tools itself and
   produces an executable, so the test harness stops doing it.
2. **Data.** Constructors, constructor case trees, heap layout, and a small C
   runtime. Start with reference counting plus Idris's existing dynamic
   uniqueness check (as in RefC). That takes no stack maps.
3. **Closures.** A uniform closure representation first, for correctness.
   Then flow-directed defunctionalization over the whole program, keeping
   closures only where flow is unknown (FFI callbacks).
4. **Prelude.** Build prelude/base with sidecars. Interface dictionaries are
   specialized when fixed, as in Lean, and left uniform otherwise. Add a
   GMP-backed `Integer`, strings, `Nat` as `Integer`, and laziness (`TDelay`
   and `TForce` as memoizing thunks).
5. **Representation.** Newtype, enum, and unit cases (match Idris), argument
   flattening and unboxing (MLton `Flatten`), and removal of unused
   constructors and arguments.
6. **Tail calls and kernels.** Contification and loop introduction, then a
   contiguous indexed array library lowered to `scf`/`memref`/`vector`, with
   benchmarks against Chez, RefC, and hand-written C.

## Decisions needed

1. **Memory management.** Precise reference counting with reuse
   (Lean/Koka/RefC; no stack maps; fits Idris's existing RefC semantics) or a
   tracing GC (MLton; better for cyclic or shared data; needs LLVM statepoints
   or a conservative collector). Recommendation: reference counting.
2. **Closures.** Uniform closures first and defunctionalize later
   (recommended), or defunctionalize from the start and accept that
   separately compiled code cannot be linked.
3. **Specialization policy.** Lean-style (fixed instances and fixed
   higher-order arguments, uniform fallback; recommended), or attempt
   MLton-style monomorphisation with a fallback when it does not terminate.
4. **Sidecars.** Serialize our typed IR per module (recommended: keeps what
   TTC drops), or rebuild everything from TTC-loaded context at link time.

## Sources

- MLton guide pages in the MLton source tree: `CompilerOverview`,
  `WholeProgramOptimization`, `Monomorphise`, `ClosureConvert`, `Closure`,
  `SSA`, `SSASimplify`, `Contify`, `Useless`, `RemoveUnused`, `Flatten`,
  `DeepFlatten`, `RSSA`, `GarbageCollection`
  (https://github.com/MLton/mlton/tree/master/doc/guide/src)
- Lean 4 compiler sources: `src/Lean/Compiler/LCNF/Passes.lean`, `SpecInfo.lean`,
  `Types.lean` (https://github.com/leanprover/lean4)
- MLIR at `llvmorg-23.1.2`: `mlir/include/mlir/Transforms/Passes.td`,
  `mlir/include/mlir/Dialect/LLVMIR/LLVMOps.td`, `mlir/lib/Conversion/*ToLLVM`
- S. Weeks, "Whole-program compilation in MLton", ML Workshop 2006,
  https://dl.acm.org/doi/10.1145/1159876.1159877
- H. Cejtin, S. Jagannathan, S. Weeks, "Flow-Directed Closure Conversion for
  Typed Languages", ESOP 2000, https://doi.org/10.1007/3-540-46425-5_4
- S. Ullrich, L. de Moura, "Counting Immutable Beans", IFL 2019,
  https://arxiv.org/abs/1908.05647
- A. Reinking, N. Xie, L. de Moura, D. Leijen, "Perceus: Garbage Free
  Reference Counting with Reuse", PLDI 2021, https://xnning.github.io/papers/perceus.pdf
- M. Tejiščák, "Erasure in Dependently Typed Programming", PhD thesis, St
  Andrews 2020, https://research-repository.st-andrews.ac.uk/handle/10023/28867
- A. K. Hovgaard, T. Henriksen, M. Elsman, "High-Performance
  Defunctionalisation in Futhark", TFP 2018,
  https://link.springer.com/chapter/10.1007/978-3-030-18506-0_7
- Y. Huang, J. Yallop, "Defunctionalization with Dependent Types", PLDI 2023,
  https://dl.acm.org/doi/10.1145/3591241
- CertiCoq, https://certicoq.org/
- P. Podlovics, C. Hruska, A. Pénzes, "A Modern Look at GRIN", Acta
  Cybernetica 2021, https://cyber.bibl.u-szeged.hu/index.php/actcybern/article/view/4101
- S. Bhat, T. Grosser, "Lambda the Ultimate SSA", CGO 2022,
  https://arxiv.org/abs/2201.07272
- E. Brady, "Idris 2: Quantitative Type Theory in Practice", ECOOP 2021,
  https://arxiv.org/abs/2104.00480
