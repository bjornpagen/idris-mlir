# What the other compilers do that we should take

Research note, 2026-10-02, at 57b22ac. The question: which mechanisms of
GHC, Lean 4, Koka, MLton, Idris 2's own backends (Chez, RefC), Futhark and
Dex matter for the programs `bench/` measures, which of them this compiler
already has, where the gap is, and what to adopt under the rules of
AGENTS.md: the representation first, upstream MLIR for as much of the work
as possible, our own code light, Idris's facts kept in types, no language
change, the stock Chez backend as the oracle and not the specification.

Status of every claim: **read** (with the path, and the section or line),
**measured** (`bench/README.md`, the run of 2026-10-02 at 903d127, or
`foreign/idr/bench/alloc/README.md`), **recalled** (from memory of a
source not in `sources/`; treat as approximate), **conjecture**. The
sources library has papers for Lean (Counting Immutable Beans, TeX), Koka
(Perceus TR, FP², PDF), Futhark (the PLDI 2017 paper and Hovgaard's
defunctionalisation, PDF) and the GHC commentary and MLton guide snapshots
(`sources/docs/{ghc,mlton}`), plus MLton's pass sources
(`sources/code/mlton`) and Idris 2's (`sources/code/idris2`,
`third_party/Idris2`). It has nothing of Lean 4's compiler source, Koka's
source, GHC's source or Dex (`sources/README.md`, "Planned sources not
collected": `code-lean4-lcnf-specinfo`, `code-koka`, `code-dex`,
`code-futhark`, all "not collected"). What is said of those is recalled
and marked.

## The rows this note is about

From the table in `bench/README.md` (measured; the run-to-run spread is up
to 15%, so a ratio within that of 1 is parity):

- lose to C: **reverse-complement 0.08x**, **fasta 0.50x** (both over
  `List Char`, input read a character at a time), **fannkuch-redux 0.72x**
  (`IOArray`), **spectral-norm 0.77x** (lists; the `Linear.Array` version is
  at 0.99x), **unionfind 0.77x** in this run (the per-program note says
  parity after two changes; the table's C moved 2x between runs);
- trail a competitor: **rbtree-ck** is 1.60x of C but Koka takes 2.157 s
  to our 2.837 s; **regex-redux** is the one row the stock Chez backend
  wins (3.023 s to our 3.573 s), which the README does not explain;
- at parity with a known cost left: **pidigits** 1.05x with a fresh `mpz`
  per operation; **binary-trees** 4.87x of C (which frees through musl's
  `malloc`), faster than Lean (7.221 s) and Koka (12.557 s);
- do not compile: **k-nucleotide**, rejected because `Data.SortedMap`
  keeps its `Ord` dictionary in a constructor field.

## 1. Per competitor: mechanism, what it buys, our equivalent, the gap

### GHC

| mechanism | what it buys | ours | gap | evidence |
| --- | --- | --- | --- | --- |
| Demand analysis and worker/wrapper: strictness, absence, CPR; the wrapper inlines so callers pass unboxed components | unboxed arguments and results across calls, absent arguments dropped | Strictness is free (Idris is strict). Scalars are unboxed by type (`Emit/Types.idr`); a non-recursive data type is an unboxed sum, only a recursive one a box (`compiler/src/IdrisMLIR/Term.idr`, `Repr`), so "unboxing a pair across a call" is the representation, not a pass. Absence: `remove-dead-values` and `idr-prune` in every round (`foreign/idr/lib/Passes/Simplify.cc`). CPR: a function returns its sum's components, and `idr-returned-arguments` drops a result that is an argument | none that the rows need; a *recursive* box is never split across a call, as GHC would not either | read: `sources/docs/ghc/commentary-compiler-demand.md`; `Passes/ReturnedArguments.cc` |
| SpecConstr (call-pattern specialisation): a recursive function cloned for the constructor shapes of its arguments at its recursive calls | no repeated match in the loop; unboxing of the matched argument | `idr-specialize`: a call whose argument is built from constants, `idr.con` and `idr.closure` calls a clone with the static part substituted and the runtime leaves as parameters, when the parameter's binding time allows (fixed, decreasing, bounded) | none; ours is wider (closures too, binding times decide termination instead of a count) | read: `foreign/idr/lib/Specialize/Specialize.cc` head, `BindingTimes.cc`; `sources/docs/ghc/users_guide/using-optimisation.html` `-fspec-constr`; fixture `tests/programs/eval/call-pattern` |
| Call arity and eta-expansion; eval/apply with arity in the closure (Marlow and Peyton Jones) | a function returning a function called with both arguments at once; unknown calls checked by arity | Arity raising: the single consumer of a call's result (an apply) moves into a clone of the callee (`Specialize/Raise.cc`). A closure has one parameter per lambda (`Term.idr`, `Lam`); a partial application after `idr-defunctionalize` is an unboxed sum unless its captures are recursive, so a PAP is registers, not a heap object | a closure applied to several arguments through an unknown `k` costs one apply (a match over labels) per argument; GHC's PAP is a heap object, so this is not a loss | read: `Passes/Defunctionalize.cc` head ("unboxed unless the key is on a cycle"); `scratchpad` text of `sources/papers/marlow-2006-fast-curry` §8.3 (2–3% between the models) |
| Join points (STG `let-no-escape`), case-of-case, case-of-known-constructor | no closure for a continuation; matches that meet their consumer fold | Regions: an `idr.match` yield is the join point by construction; `idr-contify` inlines the case blocks Idris lifted (`Passes/Contify.cc`); case-of-case and sinking (`Dialect/Canonicalize/CaseOfCase.cc`, `Sink.cc`); known constructor (`Matches.cc`, `Con.cc` record eta) | none | read: `sources/docs/ghc/commentary-compiler-stg-syn-type.md`; the files named |
| foldr/build and stream fusion (RULES on list producers and consumers) | no intermediate list in `map f (take n (drop k xs))` and friends | **None for lists.** Only strings: a string built to be written is written piece by piece (`output-fused`, `tests/idr/canon/output-fusion.mlir`), and `pack`/`concat` of a list build the string once (`idr.str.pack`, commit 29ad802) | **the gap behind fasta, reverse-complement, spectral-norm (lists)**: every intermediate `List` is allocated, counted and freed | read: `sources/papers/kovacs-2022-staged/paper.tex:593-618` (fusion as binding-time improvement; "it is possible to get pessimized code via failed fusion" in GHC); `bench/fasta/Main.idr`, `bench/spectral-norm/Main.idr` |
| Pointer tagging: the constructor's tag in the low bits of the reference | a match on a two- or three-constructor type reads no memory | None: a box's tag is in its header word (`runtime/idris_rt.h`, `idris_rt_header.info`); a nullary constructor is an atom (a static cell, `Ownership.h` `isAtom`); an unboxed sum's tag is a slot in registers | a match on a box loads one word. **Deliberately not adopted**: AGENTS.md keeps heap references raw, untagged addresses (Apple's data-memory-dependent prefetcher), and `decision-nat.md` keeps the only tag in bit 0 of small integers | read: `sources/docs/ghc/commentary-compiler-generated-code.md:820-830`; AGENTS.md; `findings/decision-nat.md` |
| Unboxed sums and unboxed tuples (`(# a \| b #)`), `-funbox-strict-fields` | no cell for a small sum | every non-recursive data type is an unboxed sum whose counted components share slots (`Lower/Layout.h`, `SumLayout`); scalar fields live inside cells after the object slots (`idris_rt.h`) | none; GHC needs the programmer to ask (recalled), we do it from the declaration | read: the files named; `commentary-compiler-data-types.md` ("Unboxing strict fields") |
| Exitification: exit paths pulled out of a recursive function so the simplifier inlines there | smaller loop bodies | `idr-tail-loops` in while-do form puts the exiting region after the `scf.while` and runs loop-invariant code once, before it | partial: nothing hoists an exit path out of a recursion that is not a self tail call | read: `Passes/TailLoops.cc` head; `using-optimisation.html` `-fexitification` |
| Late lambda lifting (free variables as parameters, closures gone at STG) | fewer closure allocations | every lambda is closure-converted at Emit (`Term.idr`, "Futhark's defunctionalisation"), then raising removes the apply where the closure is consumed at once, and `idr-defunctionalize` turns the rest into sums | none | read: `Term.idr` head; `Specialize/Raise.cc` head |
| The inliner (Secrets of the GHC inliner), CSE, full laziness | | MLton's size rule in `Inline/Inline.cc`; upstream `cse` and `sccp` in the round; no float-out (strict language) | none | read: `Inline.cc` head; `Passes/Simplify.cc` round |
| Specialisation of overloading (dictionaries passed at runtime unless specialised) | | interfaces resolved at compile time on the Idris side: an implementation is a compile-time value (`Frontend/Translate/Closed.idr`, `VarInfo.Static`), so no dictionary exists at runtime | the price is k-nucleotide (below, Futhark row on Hovgaard): a dictionary in a field is rejected where GHC would pass it at runtime | read: `Closed.idr`; `bench/README.md` ("k-nucleotide is rejected"); `tests/reject/runtime-closure-implementation` |

### Lean 4

| mechanism | what it buys | ours | gap | evidence |
| --- | --- | --- | --- | --- |
| Reset/reuse insertion (Counting Immutable Beans §R, D, S: in each case arm, where the scrutinee dies, the first constructor of the same arity is built in its cell) | a persistent update that is in place when the value is unshared | `Ownership/ResetReuse.cc` implements R, D and S on match regions, with the take moved to where the box dies and inner matches done first; `resets-unshared` is a stated property of rbtree and cfold | none in insertion | read: `sources/papers/ullrich-2019-counting-immutable-beans/update.tex`; `ResetReuse.cc` head; `tests/programs/data/rbtree/mlir.expect`, `tests/programs/data/cfold/mlir.expect` |
| Expanding reset/reuse: when the reused constructor is the taken one, store only the fields that changed and keep the header (Lean's `ExpandResetReuse`; Perceus calls it reuse specialization) | on red-black insertion, one store instead of five; no header rewrite | **None.** `Lower/Counting.cc` `LowerReuse` writes the header and every field on both paths; `LowerTake` loads every field. The `Node Red (ins l) ky vy r` branch rewrites `ky vy r` it just loaded | **the first candidate for rbtree-ck** (Koka 1.4x faster than us) and rbtree, cfold, deriv, nqueens | read: Perceus TR §2.5 (text extracted from `sources/papers/reinking-2021-perceus/perceus-tr-v4.pdf`); `Lower/Counting.cc:60-150`. Lean's pass name recalled |
| Borrow inference (Beans §4.2): a parameter never consumed stays borrowed; the tail-call refinement marks a parameter owned when an owned value is passed to it in a tail call | no dup/drop per call on read-only parameters | `Ownership/Borrow.cc` is Beans §4.2 with the tail-call refinement, plus one rule Lean cannot have: a quantity-1 parameter is owned without being counted, because Idris proved it is used once | none; ours is stronger by the quantity rule | read: `borrowinf.tex`; `refcount.tex:413-450` ("Preserving tail calls"); `Borrow.cc` head |
| Explicit RC insertion (Beans §4.3: `inc` before an owned use unless last, `dec` after last use, per branch) | | `Ownership/Counts.cc` (Perceus's placement: dups before consuming uses, drops after the last read, drops at region entry); the owned stage is in types (`!idr.own<T>`) and `Ownership/Verify.cc` checks it after every pass | none | read: `refcount.tex:307-412`; `Counts.cc` head; `Ownership.h` |
| Scalars unboxed inside constructors; boxing only where a value meets polymorphic code; `Nat` a tagged scalar with a bignum fallback | | cells place non-counted components after the object slots (`idris_rt.h`, commit 39bf5fb); nothing is ever boxed since everything is monomorphic; `Nat` is a tagged big and `idr-narrow` makes proved ranges plain `i64` (`decision-nat.md`, `Passes/Narrow.cc`) | none; Lean tests the tag at runtime where we remove it where proved | read: `refcount.tex:67-72` (Lean's IR has unboxed data and boxing instructions); Lean's layout recalled |
| `@[specialize]` and `@[inline]` annotations drive specialisation of higher-order and instance arguments | | binding times decide, with no annotation (`Specialize/BindingTimes.cc`); the Lean benchmarks need annotations (`bench/lean/qsort.lean:27,47`, `unionfind.lean:9-43`) | none | read: `bench/lean/*.lean`; Lean's LCNF `specialize` pass recalled |
| In-place `Array.set!` decided by `isExclusive` at runtime; `IO.Ref` | | linear arrays are proved exclusive (`!idr.q<1 excl, ...>`), so `Linear.Array` loops change no count and allocate nothing (`tests/programs/arrays/linarray-fannkuch/mlir.expect`); `IOArray` goes through the world as one `memref` cell | **fannkuch-redux 0.72x** is the `IOArray` version: base's `readArray` returns `Maybe` and tests the bound before ours; Lean's `mkArray n v` fills, as our `Linear.Array` does | read: `README.md` "Why not Lean 4"; `bench/README.md` fannkuch note; Lean's array semantics recalled |
| The allocator: a small-object allocator in the mimalloc family, 8-byte granularity | fast local allocation and free | snmalloc, chosen by `foreign/idr/bench/alloc/` for cross-core frees; on local work mimalloc was 12–22% faster there (`trees` 4.76 s to 5.82 s; `churn`, a million live objects randomly replaced, 3.58 s to 4.25 s) | **a measured candidate for rbtree-ck** (a live set of trees, Koka 1.4x faster) and rbtree; programs are single-threaded today | measured: `foreign/idr/bench/alloc/README.md`; read: `alloc.tex` (Lean's allocator uses Koka's free-list sharding, i.e. mimalloc's) |
| Join points and `jmp` in the IR; dead-branch elimination; `reduceArity`; `floatLetIn` | | regions; `idr-prune`; `remove-dead-values`; sinking into regions (`Sink.cc`) | none | read: `refcount.tex:67-72`; Lean's pass names recalled |

### Koka (Perceus, FP²)

| mechanism | what it buys | ours | gap | evidence |
| --- | --- | --- | --- | --- |
| Precise ownership-based counting with dup/drop placed at last use | no counts on the fast path | `Counts.cc` | none | read: Perceus TR §2.2, §3.4 |
| Drop specialization and dup/drop fusion: `drop xs` at a known constructor becomes `if unique(xs) then free(xs) else dup children; decref(xs)`, then the children's dups fuse with their drops | on `map`, no count operation at all on a unique list | the take has it: `LowerTake` yields the fields and the cell when exclusive, else incs the fields and decs the cell (Perceus Fig. 1g's shape); with the `excl` grade not even the test (`tests-nothing`) | a box that dies without a same-size constructor after it is not taken apart: its fields are dup'd and the box dropped, which walks the children again | read: Perceus TR §2.3 and Fig. 1; `Lower/Counting.cc` `LowerTake`; `ResetReuse.cc` ("If no matching constructor instruction can be found, D does not modify") |
| Reuse analysis (drop-reuse pairs the dying scrutinee with a constructor of the same size in the branch) | | `ResetReuse.cc` | none | read: Perceus TR §2.4 |
| Reuse specialization | | none (the Lean row above) | rbtree-ck, rbtree, cfold, deriv, nqueens | read: Perceus TR §2.5 |
| Frame-limited reuse (Lorenzen and Leijen 2022): a reuse token never outlives the frame, so reuse is garbage free | no memory held for later reuse | a take happens where the box dies; a last use that consumes the box (a call) takes nothing, so no token spans a call; the token is dropped on paths that do not reuse it | none known | read: `ResetReuse.cc` head; the 2022 paper is link-only in `sources/INDEX.md` and its rule recalled |
| TRMC, tail recursion modulo cons and modulo context (Leijen and Lorenzen 2023); FP²'s zipper-based "modulo reusable defunctionalized CPS contexts" for traversals | constant stack for `map`-shaped recursions; in-place traversals | `idr-trmc`: a self call whose result is a field of the boxed constructor a tail returns becomes a tail call with a destination, then a loop (`Passes/Trmc.cc`) | ours covers constructor contexts only; not associative operators (`1 + check l + check r` in binary-trees stays a recursion, as it should: FP² measured its zipper `tmap` slower than recursion) | read: `sources/papers/lorenzen-2023-fp2` §3.1 and §6 (text extracted); `Trmc.cc` head; the 2023 TRMC paper recalled |
| FIP/FBIP: a syntactic check that a function allocates nothing (or at most n cells), with borrowed (`^`) parameters; call sites decided at runtime by the count | a promise about the body, not the call | the promise is in the types: `!idr.excl<T>` is inferred by provenance on MLIR's dataflow solver and verified after every pass (`Ownership/Exclusive.cc`); `tests-nothing`, `counts-nothing`, `no-heap-allocation` are checkable properties (`Expect`) | ours proves both halves (callee and every caller) where FP² proves the body only; what is missing is the user-facing promise the README names ("the static promise is not") | read: FP² §1.3, §1.4.2; `Exclusive.cc` head; `README.md` |
| Value types (tuples) unboxed and passed in registers | | unboxed sums | none | read: FP² footnote 3 |
| mimalloc allocator | | see the Lean row | rbtree-ck | measured: alloc README; read: Perceus TR §4 |

### MLton

| mechanism | what it buys | ours | gap | evidence |
| --- | --- | --- | --- | --- |
| Whole-program monomorphisation and defunctorisation | no polymorphism at runtime | the Idris side monomorphises (`Frontend/Translate/*`); polymorphic recursion is rejected with a named rule (`Translate/Recursion.idr`) | none | read: `sources/docs/mlton/doc/guide/src/WholeProgramOptimization.adoc`; `Recursion.idr` head |
| Closure conversion by control-flow analysis into sum types (Cejtin, Jagannathan, Weeks): a function value is a variant naming the function and carrying its free variables | no indirect calls; closures are data | `idr-defunctionalize`: a sparse dataflow analysis of the labels each `!idr.fn` may hold, sums keyed by (type, label set), unboxed unless recursive | none; keying by label set is finer than MLton's per-type sum (which it also refines by its abstract values) | read: `Closure.adoc`, `ClosureConvert.adoc`; `code/mlton/mlton/closure-convert/`; `Defunctionalize.cc` head |
| Contification by dominators (Fluet and Weeks): a function that always returns to the same continuation becomes a local block | loops and continuations exposed to loop optimisations | `idr-contify` for a function called exactly once from another; `idr-tail-loops` for self tail calls; MLIR regions for Idris's case blocks | a function called from several sites of one caller with one return point stays a call; inlining usually covers it (MLton's inline rule is ours) | read: `Contify.adoc`; `code/mlton/mlton/ssa/contify.fun` head; `Contify.cc` head |
| Inline by size: a leaf under 40 ops; otherwise (calls − 1)(size − 60) ≤ 320 | | copied as written (`Inline/Inline.cc`) | none | read: `Inline.cc` head ("Inline calls by MLton's size rule") |
| Flatten: tuple arguments passed as components; DeepFlatten: tuples flat inside refs and arrays | no cell for a pair passed or stored | a non-recursive sum is its components after lowering (`Layouts::components`); array elements are laid out as a cell's fields, so a sum element is stored flat (`idris_rt.h`, `idris_rt_array`) | the structure-of-arrays split (`findings/simd.md` §4) is beyond MLton | read: `Flatten.adoc`, `DeepFlatten.adoc`; `Lower/Layout.h`; `idris_rt.h` |
| Useless and RemoveUnused: values no primitive or case needs, unused arguments, results, constructor arguments | | `remove-dead-values`, `idr-prune` (poison for unread parameters), `symbol-dce`, `idr-returned-arguments`; Idris's erasure removes quantity-0 fields before any of this | a constructor field no match ever reads is still stored (conjecture: not checked on the rows) | read: `Useless.adoc`, `RemoveUnused.adoc`, `code/mlton/mlton/ssa/useless.fun` head; `Simplify.cc` round |
| KnownCase, Redundant (parameters always passed the same value), CommonArg, RedundantTests, LocalRef, IntroduceLoops, LoopUnroll/Unswitch, Shrink | | known case is `match-known` canonicalization; loops are `idr-tail-loops`; unroll/unswitch are LLVM's; `IORef` has not landed (`decision-acyclic-heap.md`) | no interprocedural "two parameters always equal" merge (small) | read: `SSASimplify.adoc` (the pass list); the descriptions beyond the names recalled |
| Representation selection (PackedRepresentation: bit-level packing, `bool` as 0/1, padding to word widths) | | `Lower/Layout.cc` with `SumLayout` slot sharing; `i1` for `Bool`; a sum's tag slot as wide as its count needs | none that matters | read: `code/mlton/mlton/backend/packed-representation.fun` head; `RSSA.adoc` |
| Generational copying collection with bump allocation | cheap short-lived allocation | counting on an acyclic heap, by decision | N/A: regex-redux is where this shows (below) | read: `GarbageCollection.adoc`; `findings/decision-acyclic-heap.md` |

### Idris 2's own backends (Chez, RefC)

| mechanism | what it buys | ours | gap | evidence |
| --- | --- | --- | --- | --- |
| The Nat hack: `plus`, `mult`, `minus`, `equalNat`, `compareNat`, `natToInteger`, `integerToNat` rewritten to `Integer` primitives; an `S` branch as a subtraction | `Nat` as a number, not unary | `NatT` is a tagged big by type, `CaseNat` a match on zero/successor, and `idr-narrow` proves ranges and makes the web `i64` with loop versioning (`decision-nat.md`) | none; ours removes the tag test where proved | read: `third_party/Idris2/src/Compiler/Opts/Constructor.idr:40-100`; `Passes/Narrow.cc` head; fixtures `tests/programs/nat/*` |
| `ConInfo` representations: `NIL`/`NOTHING` as `'()`, `CONS` as a Scheme pair, `JUST` as a box, `RECORD` without a tag, `ENUM`, `UNIT`, `ZERO`/`SUCC` | a `List` as native pairs; `Maybe` as a nullable | nullary constructors are atoms; `Maybe a` is an unboxed sum in registers; a cons cell is a header and two words (24 bytes; a Chez pair is two words, recalled) | our cons cell is 8 bytes larger than Chez's and the same as Lean's (header `rc:32 info:32`, recalled); the only way to shrink it is a tag in the pointer, which is excluded by design | read: `third_party/Idris2/src/Compiler/Scheme/Chez.idr:556-600`, `Core/CompileExpr.idr:19-30`; `idris_rt.h` |
| CSE of closed subterms into zero-argument top-level definitions | shared dictionaries and constants | `idr-eval` runs every closed call of pure code at compile time and replaces it by static data (count 0, never freed); `cse` in the round | none | read: `third_party/Idris2/src/Compiler/Opts/CSE.idr` head; `Passes.td` `IdrEval`; `idris_rt.h` ("persistent") |
| Identity: a function that returns its argument (including through `S`/pred patterns) is replaced by the argument | | `idr-returned-arguments` after lowering, through joins and recursive calls; record eta in `Con.cc` | none | read: `Compiler/Opts/Identity.idr` head; `ReturnedArguments.cc` head |
| ToplevelConstants: constant expressions lifted to top-level, evaluated once | | `idr-eval` | none | read: `Compiler/Opts/ToplevelConstants.idr` head |
| InlineHeuristics (`simple` bodies) and `%inline`; `Inline.idr` with case-of-case | | MLton's rule; `%inline` is rejected (`tests/reject/pragma-inline`) since the compiler decides | none | read: `Compiler/Opts/InlineHeuristics.idr`; `Compiler/Inline.idr` head |
| RefC: counting with `idris2_isUnique`-tested constructor reuse per constructor, owned-variable tracking per scope | dynamic reuse | the Beans/Perceus pipeline with borrow inference, exclusivity grades and the verifier | none; RefC reuses only where it sees the same constructor name in scope | read: `third_party/Idris2/src/Compiler/RefC/RefC.idr:405-450` |
| `Lazy` (`LLazy`) delays memoised through Scheme promises on Chez; `Inf` as plain thunks | a lazy value forced twice is computed once | `TDelay` is a `Suspend` (a closure of no arguments), `TForce` a `Resume`; nothing memoises (`Translate/Terms.idr:128-130`; no memoisation in `Lower/Closures.cc`) | a `Lazy` value forced twice is computed twice; the result is the same (pure), the cost is not. No row forces one twice (conjecture) | read: `Terms.idr`; Chez's `blodwen-delay` memoisation recalled |
| Chez's runtime: pointer-tagged fixnums, generational collection, bump allocation | cheap closures and short-lived cells | counting | regex-redux (below) | recalled |

### Futhark

| mechanism | what it buys | ours | gap | evidence |
| --- | --- | --- | --- | --- |
| Producer–consumer and horizontal fusion of SOACs (`map`, `reduce`, `scan`, streams) by graph reduction, from the universal properties of fold | no intermediate arrays | none for lists; the plan in `findings/simd.md` raises index spaces to `linalg` so upstream fuses and vectorises | spectral-norm (lists), fasta, reverse-complement | read: `sources/papers/henriksen-2017-futhark` §2.1 and §4 (text extracted); `simd.md` |
| Uniqueness types: a unique parameter is consumed; alias analysis; in-place update is an error when unsafe | referentially transparent in-place writes | quantity 1 on the handle plus the inferred `excl` grade (`decision-inhouse-linear.md`); a shared array is still the one object, as on Chez | none; Futhark asks the programmer for `*` where we prove exclusivity | read: Futhark §3; `decision-inhouse-linear.md` |
| Arrays-of-tuples to tuples-of-arrays, early | vectorisable storage | array elements are laid out as cell fields (array of structures) | the SoA split is `simd.md` §4's plan, not done | read: Futhark §2.2 footnote 2; `idris_rt.h` |
| Size types (`Πn`) and shape parameters | bounds known statically | `Vect`'s index is erased at the Idris side; an array carries its length in its descriptor (`memref` dimension), which made unionfind's bounds check two registers | `Fin n` as a ranged word is planned (`decision-nat.md`), not done | read: Futhark §2.1; `bench/README.md` unionfind note |
| Allocations hoisted out of loops and kernels | | `idr-stack` puts frame-local cells on the stack; nothing hoists a heap cell out of a loop | small | read: Futhark §2.3; `Stack/Pass.cc` head |
| Defunctionalisation by static values with a type restriction: a conditional, loop or array may not produce a function of order above zero (Hovgaard, Henriksen, Elsman) | first-order code with no closures at all | no restriction: `idr-defunctionalize` makes a sum for a closure that several labels may reach, with coercions between keys; what is rejected is a *dictionary* stored in a field, because implementations are compile-time values on the Idris side | **k-nucleotide**: `Data.SortedMap`'s `Ord` in a constructor field is exactly a function value stored in data; the MLIR side could already defunctionalise it if the Idris side emitted it as a record of closures | read: `sources/papers/hovgaard-2018-defunctionalisation` §2.2 and §3 (text extracted; `τ orderZero` premise); `Defunctionalize.cc` head; `Closed.idr`; `bench/README.md` |

### Dex

Nothing of Dex is in `sources/` (`INDEX.md`: "Dex papers and index sets:
unresolved"). Recalled: arrays are indexed by finite types (`n => a`),
built by `for i. ...`, with effects (`Accum`, `State`) for in-place
accumulation. Our equivalent is the plan to make `Fin n` a ranged `index`
(`decision-nat.md`, `simd.md` R5) and `Vect` a tensor (`simd.md`); nothing
is implemented, and no measured row needs it today.

## 2. What to adopt, ranked

Each item names the mechanism, the rows it would move, how it fits the
rules (the representation first, upstream MLIR first, our code light),
its risks, and where it goes.

1. **Reuse without rewriting unchanged fields** (Lean's `ExpandResetReuse`,
   Perceus §2.5 "reuse specialization"). Today `idr.take` loads every field
   of the dying cell and `idr.reuse` stores every field and the header
   (`Lower/Counting.cc`); on the rbtree branch `Node Red (ins l) ky vy r`
   four of five stores and the header write are of what was just loaded,
   and LLVM cannot remove them because the recursive call sits between the
   load and the store. Rows: rbtree-ck (the row Koka wins by 1.4x), rbtree,
   cfold, deriv, nqueens (every reset/reuse program). Fit: the fact is
   already in the IR as operand identity: a field of the `idr.reuse` that is
   the result of the `idr.take` whose token it reuses, at the same index,
   need not be stored on the path where the token is the cell; the same
   constructor needs no header write. No attribute, no new op; a condition
   in `LowerReuse` on the exclusive and token paths, with the fresh-cell
   path storing everything. Risk: the slow path (null token) must still
   write every field, so the elision is per path, and the verifier's rule
   (every reference consumed once) is unchanged since nothing moves. Where:
   `foreign/idr/lib/Lower/Counting.cc`, `LowerReuse`; a property for
   `idr-expect` ("a reuse of the taken constructor stores only changed
   fields") instead of matching stores.

2. **Measure mimalloc against snmalloc on the single-threaded rows.**
   Koka and Lean both allocate through mimalloc's free-list sharding
   (Perceus TR §4; `alloc.tex`), and our own allocator benchmark found
   mimalloc 12–22% faster on local work, with snmalloc chosen for cross-core
   frees a scheduler does not yet produce (`foreign/idr/bench/alloc/README.md`).
   Rows: rbtree-ck ("measures the allocator under a live set",
   `bench/README.md`), rbtree, binary-trees, cfold, deriv. Fit: the runtime's
   platform layer, no compiler change; the allocator is configured in
   `runtime/CMakeLists.txt` and `runtime/alloc.cc` (size classes per
   `IDRIS_RT_SIZE_CLASSES`). Risk: the measured result was a model
   (`shapes.cc`), not these programs, and the arm64 macOS port needs the
   same allocator to build there; the finding stands only after a run of
   `bench/run.sh` on both. Where: a build option in `runtime/`, one bench
   run; conjecture until measured that this is the rbtree-ck gap and not the
   stores of item 1.

3. **Make a dictionary in a field a runtime record of closures** (Hovgaard's
   static values with the restriction lifted by our label-set sums).
   `Data.SortedMap` stores its `Ord k` in `M`'s constructor, so k-nucleotide
   is `unsupported`. The Idris side treats an implementation as a
   compile-time value (`Closed.idr`, `Static`); where one flows into a
   constructor field, it could instead be emitted as a `ConApp` of its
   methods' closures, and `idr-defunctionalize` already turns every closure
   slot whose labels are known into a sum with one constructor per label,
   so the comparisons in `insert`/`lookup` become a match over the
   implementations the whole program stores there. Rows: k-nucleotide
   compiles; `tests/reject/runtime-closure-implementation` becomes an
   accept. Fit: a representation decision on the Idris side (AGENTS.md:
   Idris decides representations), with the MLIR work already written.
   Risk: specialization budgets (`unsupported (compile-time budget)`) when
   each method clones; the heap-cycle check must see the closure captures
   (`decision-acyclic-heap.md` already runs after defunctionalization).
   Where: `compiler/src/IdrisMLIR/Frontend/Translate/{Closed,Terms}.idr`
   and the registry's rule for `SortedMap`; no C++.

4. **Fusion of list producers into their consumers** (GHC's foldr/build and
   stream fusion, Futhark's SOAC fusion; Kovács's view that fusion is a
   binding-time improvement). Rows: spectral-norm over lists (0.77x; the
   array version is at parity), fasta (0.50x: `pack (take m (drop k alu2))`,
   `gen` builds a list, reverses it and packs it), reverse-complement
   (0.08x: `readAll` conses every character, `reverse`, `splitAt 60`,
   `pack`). Fit: the representation first means raising the index-space
   schemes (`replicate`, `[a .. b]`, `map`, `zipWith`, `foldl` over them) to
   `linalg.generic` on tensors, where upstream's fusion, bufferization and
   vectorizer do the work (`findings/simd.md` §5, item 1 of its path); the
   stream schemes (`take`, `drop`, `pack` of a list the program builds once)
   are a canonicalization of the `idr.str.pack` consumer in the style of
   output fusion, which already exists for strings. Risk: GHC's own
   experience that failed fusion pessimises (Kovács §"Fusion"); a crash
   inside a fused body must stay in program order (the Chez diff is the
   check); `List` is the programmer's representation, so a fused program
   must still be the same program when the list escapes. Where:
   `Dialect/Canonicalize` for the consumer patterns; the classifier of
   `simd.md` for the index spaces; both are our code, the loops they
   produce are upstream's.

5. **Take apart a dying box with no constructor to reuse** (Perceus's drop
   specialization and dup/drop fusion, §2.3). Where a match's scrutinee dies
   in a branch and no same-size constructor follows, `ResetReuse.cc` inserts
   no take, so the fields the branch keeps are dup'd and the box is dropped
   (a runtime walk that decs the same children). A take there yields the
   fields and frees the cell when exclusive, one test instead of k incs and
   a dec that walks k children. Rows: conjecture; the borrowed traversals
   (`check`, `fold`) are not affected since their parameter is borrowed, so
   the candidates are consumers that keep a field and drop the rest
   (`myLen`, `countFirst`, list consumers in regex-redux). Fit: the IR has
   the ops (`idr.take` with a token dropped at once, which `LowerDrop` frees
   with `idris_rt_free_cell`); the change is in insertion. Risk: a take
   where the box is shared costs the incs anyway, which is Perceus's slow
   path and no worse than today. Where: `Ownership/ResetReuse.cc`, the `D`
   step when `S` finds nothing.

6. **In-place big-integer arithmetic on exclusive bigs.** No competitor does
   this (GHC's `integer-gmp`, Lean's `Nat` and Koka's bigints allocate a
   fresh result; recalled), so it is an extension of our own reuse to
   bignum cells rather than a theft: a `idr.big.*` whose operand is
   `!idr.excl` and whose result fits the operand's limb count writes into
   the operand's cell (`mpz_roinit_n` views already make reads
   allocation-free, `decision-nat.md`). Rows: pidigits (1.05x of C with a
   fresh `mpz` per operation; C updates in place). Fit: the exclusivity
   grade is in the types already; the runtime's function stays the one
   meaning (its in-place form is the same function on a result cell). Risk:
   GMP's `mpn_` layer and limb-count growth; the digit layout change of
   `decision-nat.md` ("one hop to the digits") comes first. Where:
   `Lower/Bigs.cc` and `runtime/big.cc`, behind the grade.

7. **A promise the programmer can read** (FP²'s `fip`/`fbip` as a checked
   claim, without annotations). FP² checks a body and decides call sites at
   runtime; we infer `excl` for both halves and have the properties as test
   assertions (`tests-nothing`, `counts-nothing`, `no-heap-allocation`,
   `reuses-in-place`). What the README promises ("will be updated in place
   with no runtime test, or the program will not compile, with a named
   reason") is the demand form `simd.md` §6 describes for vectorization:
   `--demand in-place=Main.f` turning a shared take into `unsupported
   (in-place)`. Rows: none move; this is what the compiler exists for. Fit:
   the facts are in types; the demand is a remark turned into an error. Where:
   `Expect`'s properties behind an `idris-mlir-cc` option; no pass changes.

8. **Contification by dominators** (MLton) for a private function called from
   several sites in one caller that all return to the same point: today it
   stays a call unless inlined by size. Rows: none measured; conjecture that
   the backtracking `match` of regex-redux has such continuations. Fit:
   MLIR regions and `inlineCall`, as `idr-contify` already does for one
   site; the dominator analysis is MLIR's. Risk: code copying where sites
   differ in arguments. Where: `Passes/Contify.cc`.

9. **Remove constructor fields no match reads** (MLton's Useless and
   RemoveUnused on constructor arguments). Erasure already removes quantity-0
   fields, so what remains is a runtime field the whole program never
   projects. Rows: none known (conjecture). Fit: a module-wide analysis on
   `idr.data`, its result written into the declaration (no attribute). Risk:
   layouts change under compile-time evaluation's cached results. Where: a
   step of the simplify round before `remove-dead-values`.

10. **Memoising `Lazy`.** Chez's `Delay` is a Scheme promise, forced once;
    ours is a closure resumed on every force. No measured row forces a lazy
    value twice (conjecture), and a memo needs a mutable cell, which the
    acyclic-heap decision allows only through the world. Rows: none today.
    Fit: representation first means `Lazy a` as a one-slot cell with a
    state, which is a library-visible cost model, not a semantics; it is
    listed last because it would be the first mutable cell outside IO.
    Where: `Emit`'s `Suspend`/`Resume` and `Lower/Closures.cc`, if ever.

Not adopted, and why: **pointer tagging** (GHC, Chez) because references
stay raw addresses for the prefetcher (AGENTS.md); **a tracing or
generational collector** (GHC, MLton, Chez) because counting on an acyclic
heap is the design (`decision-acyclic-heap.md`); **annotations**
(`@[specialize]`, `@[inline]`, `fip`, `SPEC`, `%inline`) because the
language does not change and binding times decide; **Hovgaard's
restriction** on functions in conditionals and arrays, because our sums
handle them and the one restriction we have (dictionaries in fields) is
item 3's to lift.

## 3. What we do that they do not

- **Compile-time evaluation by running the program's own code.** `idr-eval`
  lowers each round's closed calls with the real lowering, JIT-compiles
  them, runs them in a child process under a tick, arena and stack budget,
  and replaces each call by its results as static data (`Passes.td`,
  `IdrEval`; `Eval/*`). GHC folds through rules and the inliner, Lean
  through `simp`/`csimp` lemmas (recalled), MLton by constant propagation;
  none runs the lowered program.
- **Ownership in types, verified after every pass.** `!idr.own<T>`,
  `!idr.excl<T>`, `!idr.lin<T>`, `!idr.erased` (`IdrOps.td`), checked by
  `Ownership/Verify.cc` after every later pass. Lean's IR carries borrow
  flags on parameters and Koka's FIP check is syntactic (FP² §1.4);
  neither re-verifies after transformations.
- **Exclusivity proved for both halves.** The `excl` grade is provenance on
  MLIR's dataflow solver: a constructor of exclusive fields, a field taken
  from an exclusive value, a parameter every caller passes exclusive
  (`Exclusive.cc`). Lean and Koka test the count at runtime; FP² proves the
  body only.
- **Quantity 1 means no count.** A quantity-1 parameter is owned without a
  dup or drop because Idris proved it is used once (`Borrow.cc`); no
  competitor has QTT to read.
- **Binding times instead of annotations or counts.** Specialization ends
  because every parameter on a cycle is fixed, decreasing or bounded
  (`BindingTimes.cc`); GHC's SpecConstr has a count limit and `SPEC`, Lean
  has `@[specialize]`.
- **Ranges proved, not tested.** `idr-narrow` makes a `Nat`/`Integer` web
  plain `i64` where range analysis proves it fits, with loop versioning on
  descending naturals; Chez, Lean and GHC test the small/big tag at every
  operation.
- **Frame cells.** `idr-stack` puts a box that never leaves its frame or
  loop iteration on the stack by escape analysis; GHC, Lean, Koka and MLton
  allocate every constructor on the heap (GHC's nursery is cheap but still a
  heap, recalled).
- **Returned arguments dropped after lowering**, through joins and recursive
  calls (`ReturnedArguments.cc`); Idris 2's `Identity` is the per-function
  special case, GHC and Lean have no equivalent (recalled).
- **Output fusion**: a string built only to be written is written piece by
  piece through the world (`output-fused`).
- **An acyclic heap by decision**, so counting is exact and the release walk
  needs no marking (`decision-acyclic-heap.md`); Koka and Lean leak cycles
  made through mutable references (Perceus TR §2.7.4 for Koka).
- **The oracle in the tests.** Every program is diffed against the stock
  Chez backend and, with an `Oracle.idr`, Idris's evaluator
  (`tests/README.md`); the competitors' benchmark suites compare numbers,
  not two backends of one language on every fixture.

## Open: the row Chez wins

regex-redux (`bench/regex-redux/Main.idr`) is a backtracking matcher in
continuation style: `match (Seq (r :: rs)) xs k = match r xs (\rest =>
match (Seq rs) rest k)` builds a closure per step that captures `k`, and
`k` is unknown at every call. After `idr-defunctionalize` the continuations
are a recursive sum (boxed: "a recursive set of lambdas is a recursive
datatype", `Defunctionalize.cc`), so every step allocates a counted cell
and dups the captured `k`; Chez bump-allocates the same closure and never
counts it. Conjecture: this is where a nursery beats counting, and it is
the only such row. The mechanisms above that touch it are items 5 and 8;
an ablation with `--without=idr-defunctionalize` and `IDRIS_RT_LIVE=1`
would say how much is the sum and how much the counts before anything is
built.
