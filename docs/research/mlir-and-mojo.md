# MLIR, Mojo, and the Idris performance goal

> Research snapshot from before the scaffold. See [the current architecture](../architecture.md) and [repository README](../../README.md) for implemented scope.

This is design research, not a speedup claim. Idris source baseline:
`1c630e67c386629a0fbbc6b78a59176fde7f0a76`. The interface recommendation is in
[compiler-interfaces.md](compiler-interfaces.md).

## What Idris already does

The backend cookbook describes Idris as not being an optimizing compiler. That
describes its emphasis, not an absence of optimization in this checkout:

- [Runtime preparation](../../third_party/Idris2/src/TTImp/ProcessDef.idr) performs relevance-based
  erasure and selected partial evaluation; `%spec` is implemented in
  [TTImp.PartialEval](../../third_party/Idris2/src/TTImp/PartialEval.idr).
- [compileAndInlineAll](../../third_party/Idris2/src/Compiler/Inline.idr) performs three rounds of
  inlining, lambda merging, case/lambda transformations, arity fixes, inline
  heuristics, constant folding, and identity analysis.
- [Constructor optimizations](../../third_party/Idris2/src/Compiler/Opts/Constructor.idr) include
  nat-like values represented with `Integer`, compact enum tags, unit-case
  elimination, and shared intrinsic list/option constructors. Newtype removal
  is also handled in [CompileExpr](../../third_party/Idris2/src/Compiler/CompileExpr.idr).
- [Common](../../third_party/Idris2/src/Compiler/Common.idr) performs runtime reachability and CSE
  before the later backend representations.
- [RefC](../../third_party/Idris2/src/Compiler/RefC/RefC.idr) already tracks owned/borrowed uses and
  reuses constructors after a dynamic `idris2_isUnique` check. Its older docs'
  statement that reference counting has no optimization is not an adequate
  description of this implementation.

The opportunity is to preserve and exploit more information, specialize more
effectively, improve representations, and reduce allocation/call overhead.
Measure against existing Chez and RefC behavior rather than crediting MLIR for
work Idris already performs.

## What MLIR supplies

The [MLIR rationale](https://mlir.llvm.org/docs/Rationale/Rationale/) describes
progressive lowering across abstraction levels. Custom operations and types can
retain domain semantics while ordinary arithmetic/control-flow operations coexist
with them. MLIR supplies compiler infrastructure; we supply Idris semantics,
legal transformations, representation choices, and the runtime contract.

The [Toy tutorial](https://mlir.llvm.org/docs/Tutorials/Toy/) demonstrates the
relevant progression: custom dialect, language-specific rewrites, interfaces
for generic transformations, partial lowering, then LLVM code generation.
It is an implementation learning path, not evidence that arbitrary functional
programs become efficient automatically.

For Idris, an initial dialect could retain algebraic constructors/cases,
closures/applications, typed scalar values, delay/force, and explicit facts
about indexed operations. Ordinary function/arithmetic/control-flow dialects
can handle the pieces whose semantics already match. Representation and closure
decisions should precede final conversion to LLVM.

Array kernels may later benefit from `memref`, `scf`, `vector`, and perhaps
`linalg` or `affine`, when their contracts fit. A general functional compiler
does not have to force its whole program through those dialects.

## What Mojo actually does

Research used Modular's public repository at commit
`01030725d36b72b85d826e5381cc76f804ba471e` and the official language documentation.
Old `docs.modular.com/mojo/...` links now redirect to `mojolang.org` for the
pages successfully followed.

The public [compiler walkthrough](https://github.com/modular/modular/blob/01030725d36b72b85d826e5381cc76f804ba471e/Mojo/docs/compiler/MojoCompilerWalkthrough.md)
describes this pipeline:

```text
source -> LIT (parametric source-level MLIR)
       -> semantic/lifetime checking -> KGEN (parametric IR)
       -> optimizations before instantiation
       -> elaboration / monomorphization / compile-time evaluation
       -> concrete lowering and optimization
       -> LLVM dialect -> LLVM IR -> machine code
```

Here “elaboration” includes instantiating generators and evaluating compile-time
code; that is not synonymous with Idris's dependent-type elaboration phase.

The [Mojo vision document](https://github.com/modular/modular/blob/01030725d36b72b85d826e5381cc76f804ba471e/Mojo/docs/site/vision.mdx)
explicitly says Mojo builds on **MLIR Core**, rather than the stock `linalg`,
`affine`, or `scf` dialects. Its own dialects and KGEN infrastructure preserve
parametric programs before instantiation. We should not describe Mojo as simply
sending programs through a standard MLIR tensor-optimization pipeline.

The [parameter manual](https://mojolang.org/docs/manual/parameters/) explains
that parameters are compile-time inputs, and concrete versions are created for
parameter values. This is stronger than “an argument is erased”: an Idris index
can be erased while remaining symbolically unknown during compilation.

The [ownership documentation](https://github.com/modular/modular/blob/01030725d36b72b85d826e5381cc76f804ba471e/Mojo/docs/site/manual/values/ownership.mdx)
describes owner lifetimes, argument conventions, and mutable-reference
exclusivity. These provide information Idris multiplicity alone does not imply.

There is a concrete library-level connection to MLIR too:
[`SIMD`](https://github.com/modular/modular/blob/01030725d36b72b85d826e5381cc76f804ba471e/Mojo/stdlib/std/simd.mojo)
has a computed MLIR representation and methods using operations such as
`pop.add`, `pop.mul`, and `pop.simd.extractelement`. Parameterized library types
and low-level operations are designed together.

The repository's older `DesignOverview.md` explicitly labels itself historical,
written before Mojo, and says it is not the current design. Do not use it as an
authoritative current pipeline specification. The walkthrough and code above
are evidence of architecture; no Mojo build or comparative benchmark was run.

## What follows for this project

The useful lesson from Mojo is to preserve parametric structure and make
representations intentional. We can reuse Idris's frontend and import checked
Core into our own typed representation without first throwing its information
away. We do not need to reproduce Mojo's parser or its complete dialect stack.

Three distinct opportunities should be measured separately:

| Opportunity | Information required | Observable result |
| --- | --- | --- |
| Remove proof/wrapper/dictionary overhead | Erasure, specialized call sites, known implementations | No proof objects; direct calls; fewer allocations |
| Choose efficient scalar and aggregate representations | Concrete types, valid ranges, layout contract | Unboxed arithmetic and fields; less tagging/boxing |
| Optimize indexed collection operations | Shape/index relationships plus actual storage and effect semantics | Fewer redundant checks; fused loops; SIMD where legal |

[`Vect`](../../third_party/Idris2/libs/base/Data/Vect.idr) illustrates why these differ. Its
constructors are `Nil` and a head/tail cons, and `index` recursively traverses
the vector. Its type supplies a length relationship; it does not specify a
contiguous array. Converting it to one changes the costs of cons, slicing,
sharing, and indexing, and can require copies. A dedicated contiguous indexed
collection is a reasonable early experiment, provided we report the library
change separately from compiler-only gains on existing programs.

Do not identify `Nat`/`Integer` with machine `index` or fixed-width integers
without range and overflow justification. Do not infer heap uniqueness from
one-use binders. Do not infer a numeric bound from an arbitrary proposition
without a supported interpretation and a clear treatment of unsafe escapes.
These are correctness requirements for particular transformations, not reasons
to discard useful type information.

## Proposed order of work

1. Validate the typed-Core export boundary, including fresh/cached dependencies.
2. Establish small benchmark programs and hand-written low-level references:
   erased wrapper/proof, scalar loop, specialized higher-order fold, indexed
   access, and constructor-producing traversal. Include dynamic inputs so the
   entire workload cannot disappear through constant folding.
3. Bring up a small typed MLIR subset and native execution. Preserve behavior,
   effects, numeric semantics, and tail-call requirements explicitly.
4. Add one justified optimization at a time; record runtime, allocation, code
   size, and compile-time changes, along with generated IR/assembly evidence.
5. Add an indexed contiguous collection or stronger ownership contract only
   where the experiment demonstrates why existing information is insufficient.

CPU execution is enough to establish the thesis. The central question is whether
checked Idris information can eliminate concrete runtime work while preserving
the program's meaning.
