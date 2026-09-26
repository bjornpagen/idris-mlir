# 01. Goals, non-goals, principles

## Goals

- **GOAL-1.** Compile programs in a strict, versioned subset of Idris 2 to
  native code, with the meaning stock Idris gives them
  ([03-semantics](03-semantics.md)).
- **GOAL-2.** Turn the facts Idris establishes (quantities, types, coverage,
  totality, and later proofs) into less runtime work, without losing any fact
  before the stage that can use it.
- **GOAL-3.** Stand on existing infrastructure. Idris 2 does parsing,
  elaboration, type checking and totality. MLIR and LLVM do generic
  optimization and code generation. We write only what neither provides.
- **GOAL-4.** Every guarantee comes from a profile rule the compiler enforces,
  never from optimizer luck. A program the compiler cannot compile within the
  guarantees is rejected, with an error at its Idris source location.
- **GOAL-5.** Start small and grow. Each profile version is a strict superset
  of the previous one and changes no program's meaning.

## Non-goals

- **Language design.** The profile selects from Idris 2. It adds no syntax, no
  pragmas, and no new meaning. The only thing we design is the compiler's IR
  (`Core` and the `idr` dialect).
- **Superoptimization, search, and equality saturation.** None of Souper- or
  STOKE-style synthesis, e-graphs, autotuning, or cost-model search. Scalar
  peepholes are left to upstream MLIR canonicalization and LLVM.
  *Rationale:* the research corpus shows that the big wins for functional
  code come from whole-program elimination (MLton, Futhark, Lean LCNF), while
  automatic superoptimization pays off little in general code (Souper made
  Clang 4.4% smaller but about 2% slower;
  [sasnauskas-2017-souper](../research/papers/sasnauskas-2017-souper)).
- **Heap, GC, reference counting, runtime system (until reopened).** Until the
  memory design exists, compiled programs allocate no heap memory. Memory management is
  a later design discussion that starts from scratch
  ([15-roadmap](15-roadmap.md)).
- **Separate compilation.** The compiler is whole-program.
- **Compatibility with other Idris backends' foreign interfaces, runtime
  representations, or `%foreign` conventions.**
- **Modifying Idris 2.** `third_party/Idris2` stays unmodified at its pinned
  gitlink.

## Principles

- **GOAL-P1. Each optimization runs at the lowest level where its facts still
  exist.** In order of preference:
  1. Upstream MLIR passes, when our dialect exposes the facts through traits,
     folders and interfaces.
  2. Our own C++ passes, when the facts are visible in the dialect but no
     upstream pass uses them.
  3. The Idris middle end, when the facts need dependent types, evaluation, or
     the TT context.

  [09-optimization](09-optimization.md) assigns every optimization to a
  level.
- **GOAL-P2. Remove abstraction before the core, then optimize first-order
  code.** Following MLton and Futhark, the Idris middle end removes
  polymorphism, lambdas, laziness, monadic structure and string building
  with a fixed list of whole-program eliminations
  ([06-elimination](06-elimination.md)). So the `idr` dialect is first-order
  and monomorphic. Lowering is a change of representation (dialect
  conversion), not a place where decisions are made.
- **GOAL-P3. Reject rather than guess.** Any construct, type, or missing fact
  that the current version cannot handle fails with an explicit `unsupported`
  error ([13-diagnostics](13-diagnostics.md)). Silent miscompilation is the
  worst possible outcome.
- **GOAL-P4. Heap-free by guaranteed elimination.** Until the memory design
  exists:
  - A program is accepted only if no heap operation survives the guaranteed
    eliminations (`PROF-HEAP-1`). The source may use lambdas, `Lazy`, monads
    and string operations, as long as each is eliminated.
  - The list of eliminations is fixed and deterministic, so acceptance is a
    rule and does not depend on optimizer heuristics.
  - The `idr` dialect has no allocating operation, so any program that passes
    its verifier lowers to code with no heap allocation.
- **GOAL-P5. Facts are not semantics.**
  - Erased does not mean constant.
  - Quantity 1 does not mean unique ownership: Idris's linearity promises
    only that an argument is not shared in the future, not that it was
    unshared in the past
    ([brady-2021-idris2-qtt](../research/papers/brady-2021-idris2-qtt),
    [marshall-2022-linearity-uniqueness](../research/papers/marshall-2022-linearity-uniqueness)).
  - An indexed vector does not imply contiguous storage.
  - A fact MUST NOT be used beyond what it proves.
- **GOAL-P6. Two languages, one contract.**
  - Idris code handles everything that needs dependent types.
  - C++ code handles simply typed, first-order rewriting inside MLIR.
  - They meet only at the `idr` dialect text ([08-idr-dialect](08-idr-dialect.md)).
  - Neither side mirrors the other's data structures.

## Settled decisions

These are decided. Reopening one is a contract-level change that needs the
user's approval.

| # | Decision | Why |
| --- | --- | --- |
| D1 | The compiler front and middle end are Idris, registered as an Idris 2 backend. | Only Idris can normalize types, read quantities, and evaluate TT without re-implementing Idris. |
| D2 | C++ MLIR dialect `idr`, with ODS traits, folders and interfaces. | The IRDL experiment showed that dialects defined only in text are opaque to CSE and dead-code elimination, while `arith` next to them was optimized. MLIR's generic passes only help ops with real traits. |
| D3 | Heap-free profile first; no RC, GC or heap until a later memory design. | Every elimination must then really happen at compile time, or the program is rejected. The subset cannot overpromise. |
| D4 | The profile is a strict subset of Idris 2, versioned, and grows only by relaxing rules. | "Start with a subset and grow up; the reverse is inappropriate." This mirrors cpp-starter's C++ profile. |
| D5 | `Int` is in the profile and is 64-bit signed, wrapping. | Matches the Chez and RefC backends (`intKind IntType = Signed (P 64)` in the pinned Idris). |
| D6 | C++ follows bjornpagen/cpp-starter, adopted fully, with the deviations listed in [11-toolchain](11-toolchain.md). | One C++ discipline across projects. |
| D7 | No superoptimization. | See the non-goals above. |
| D8 | Proved rewrites (user-proved equalities used by the compiler) are a future feature. The design keeps them possible from day one, but no version has them yet and they will use no pragma. | [07-proved-rewrites](07-proved-rewrites.md) |
| D9 | No pragmas in profile programs. | "Strict subset for now, no pragmas yet." |
| D10 | LLVM/MLIR is rebuilt with the pinned GCC, so all C++ is built by one compiler. | cpp-starter treats the toolchain as part of the language. |
| D11 | v0's entry point is a pure `main : Int`, and the process exit status is its low 8 bits. From v1, `main : IO ()` is also an entry point, compiled through `-o`. | v0 brings up the pipeline without IO. v1 adds IO. |
| D12 | The compiler reads checked TT (`treeCT`, signatures, quantities), never `CExp` or runtime case trees. | `CExp` and `treeRT` have already erased facts we need. |
| D13 | v1 targets "hello world": an IO monad, static strings, and `Char`, heap-free. | Static strings live in read-only data. IO is world-passing code once its lambdas are eliminated. Neither needs a heap. |
| D14 | Heap-freedom is decided after a fixed list of MLton-style eliminations in the Idris middle end: specialization on known functions, inlining of known higher-order and monadic code, arity raising, compile-time string evaluation, and output fusion. | Most apparent heap use in Idris code, such as closures, monadic binds, and `putStrLn`'s append, is statically eliminable in a whole program. |
| D15 | The Prelude is deferred like GC. Its dependency modules are compiled first, one layer at a time and fully tested, before the stock Prelude is ever imported implicitly. | Grow from a verified base. |
| D16 | IO comes from the stock `Builtin` and `PrimIO` modules plus our own small `IdrisMLIR.IO`. That module is the only place `%foreign` appears; user code stays pragma-free. | One small, audited escape point. |
