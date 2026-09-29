# Architecture: is the optimizer the right frame?

Stream "architecture". The question: is idris-mlir's optimizer architecture
the right frame for whole-program, rich-data optimization, far more
aggressive than MLton's, and what should change? The experiments behind the
IR excerpts are in `findings/architecture-experiments.md` (commands,
programs, timings). The MLIR mechanisms named here (DataFlow API,
interfaces, the LLVM dialect's attributes, canonicalization rules) are
treated in depth by the mlir-idioms stream (`findings/mlir-idioms.md`); this
file says *which* mechanism fits *which* fact and stops there.

Status of claims: **measured** (I ran it), **read** (file:line or paper
section), **conjecture** (my judgment, not tested).

## Verdict in one paragraph

The outer frame is right and some of it is ahead of MLton: a whole program,
quantities kept as types and re-verified after every pass, compile-time
evaluation that runs the program's own lowered code, closure analysis
already on MLIR's DataFlow framework, and a verifier for the owned stage.
Three things are wrong with the inner frame.

1. **Facts are produced ad hoc, several times, and weaker than Idris knew
   them.** There are six hand-written fixpoints, a weak duplicate of the
   closure-label analysis, and range interfaces that nothing in the
   pipeline runs. Size-change graphs, `Nat`'s arithmetic, case blocks being
   continuations, and erased proofs are all known on the Idris side and
   dropped before MLIR.
2. **The simplify loop ends because the IR hash stops changing.** Every
   blow-up in the history was patched with a budget. It should end by
   construction, over a finite set of monotone decisions.
3. **The whole-program transformations that matter most are missing.**
   From MLton: contification, useless fields, type simplification. Beyond
   MLton, and possible only with Idris's facts: uniqueness from linearity,
   tail recursion modulo cons, and eager `Lazy` in total code.

Equality saturation is **not** the fix for (2). The expensive fights were
between expanding, interprocedural transformations, which is where
e-graphs scale worst.

---

## The questions

1. Which hand-written analyses should become MLIR dataflow lattices?
2. Should the simplify group be equality saturation?
3. Whole-program optimization beyond MLton: what MLton does, and what Idris
   facts add.
4. What LLVM should receive from Idris facts, compared with what it gets
   today (actual IR).
5. Is translation validation or verified rewriting feasible as a safety net?
6. A proposed architecture, as data.

---

## 1. Hand-written fixpoints, and which should be lattices

The inventory, found by grepping `lib/` for worklists (**read**):

| Fixpoint | Where | What it computes | Lattice | Fits MLIR DataFlow? |
|---|---|---|---|---|
| Escape, interprocedural | `Stack/Escape.cc:70-93` (parameter summaries, worklist over callers) | parameters whose references escape | per value: {none < contents escape < reference escapes} (the code's Shallow/Deep node pair, `Escape.h:63-64`) | **Yes**: a `SparseBackwardDataFlowAnalysis`, shaped like upstream `LivenessAnalysis` (`LivenessAnalysis.h:78`), which is backward, sparse and interprocedural. |
| Escape, within a function | `Stack/Escape.cc:112-147` (reversed graph, backward reachability), `forwardsOf` `:56` | which nodes reach an escaping use | same | **Yes.** `forwardsOf` rebuilds by hand the region-branch forwarding the framework already does. The part that asks "does this con run again in its frame" (`repeating`, `Escape.cc:131-147` in the header comment, `Frame`) depends on the program point and stays a local check. |
| Binding times | `Specialize/BindingTimes.cc:66-85` (abstract interpretation per (function, abstract arguments)), `:190-215` (per SCC) | fixed, decreasing, bounded or other, per parameter | `{Same(i), Smaller(i), Top}` per argument, context-sensitive | **No**, not as a derivation: MLIR's sparse framework is context-insensitive. Idris has already proved the fact: seed it from the size-change graphs (§3.2). |
| Effects (`idr-effects`) | `Facts/Infer/Infer.cc:64-106` (worklist over reverse reach edges, `:78-88`) | io and crash per function | per function {none, crash, io, io+crash} | Better as one bottom-up pass over `CallGraph` SCCs than on the solver. The real defect is imprecision, not the algorithm: a closure's crash counts where it is *made* (`Infer.cc:41-58`) rather than where it is applied. With the label lattice it can count at the applies. |
| What closures a value passes | `Facts/Closures/Passed.cc:34-70` | the effects of the labels a value may hold | a local backward walk; any block argument is ⊤ (`:67`) | **Delete.** It is a weak second producer of the fact `LabelAnalysis` already computes (`Passes/Defunctionalize.cc:234-392`). Consume that lattice instead. |
| Recursion (idr-stack's budgets) | `Stack/Recursion.cc:24-46` | which functions may have several frames live | an apply calls *every* address-taken function (`:43-46`) | Consume the label lattice: an apply calls the labels its callee may hold. |
| Borrowed parameters | `Ownership/Borrow.cc:57-61` (`do … while (changed)` over the module) | owned or borrowed, per parameter | a two-point lattice per parameter | Could be interprocedural backward dataflow. Lean's algorithm is fine, the verifier checks its output, and it runs once. **Keep.** |
| Defunctionalization, keep or convert | `Passes/Defunctionalize.cc:822-845` | which slot keys stay closures | a two-point lattice per key (MLton's `TwoPointLattice` in `flatten.fun`) | Local to the pass. **Keep.** |
| Closure labels | `Passes/Defunctionalize.cc:234-392` | the labels a `!idr.fn` may hold | sets of labels, ⊤ | **Already done right**: `SparseForwardDataFlowAnalysis`, interprocedural, with a `FieldAnchor` per (data, ctor, field) (`:123-131`). This is the template. |
| Integer ranges | none | none | none | `TagOp`, `ToCharOp`, `DoubleHeadOp`, `IntHeadOp` and `StrLengthOp` implement `InferIntRangeInterface` (`Dialect/Ops.cc:442,861,883,889,903`), but **no pipeline step runs a range analysis** (`Registration.cc:15-31`, `Simplify.cc:207-222`). Only `tests/idr/fold/range.mlir` runs `--int-range-optimizations`. By the dialect's own standard these interfaces are not load-bearing. `knownNonZero` (`Ops.cc:20-29`), which decides whether `idr.div` may crash, looks only at constants. |

**What to do (Q1).**

- **Escape** becomes a sparse backward lattice, modeled on `LivenessAnalysis`,
  with field anchors like `Defunctionalize`'s. The loop-iteration condition
  stays a local check on top. This is the same machinery the new
  *uniqueness* fact needs (§6), so the two share it.
- **Binding times** are not re-derived. Emit passes Idris's size-change
  relation for each recursive call (§3.2), and the MLIR side only
  *maintains* it through clones and inlining, by composing the relations.
  Two hacks become unnecessary: `BindingTimes.cc:121-126`, which treats a
  subtraction by a positive constant as decreasing, and commits
  `3d02a0c`/`f748122`, which unroll an Int counter as a Nat.
- **Effects** stay a function summary, computed over CallGraph SCCs, but
  count closure effects at applies through the label lattice. Delete
  `Passed.cc`.
- **Ranges** get three changes:
  - run MLIR's `IntegerRangeAnalysis`, whose widening already exists at the
    pin (`IntegerRangeAnalysis.h`, the merge-count budget of
    `IntegerValueRangeLattice::join`);
  - add the idr knowledge it lacks: bind the scrutinee of `idr.match_lit` as
    a case-region argument, so the default region of a `0` case knows
    `x ≠ 0`. This is SSI live-range splitting (SSA book ch. 11, §11.1;
    `idr.match` already does it for constructor fields). Then refine that
    argument in a subclass's `visitNonControlFlowArguments`;
  - give `Nat` a non-negative type (§3.2).

  Consumers: `knownNonZero` and the crash causes, so a division the range
  proves safe is rewritten into a plain `arith` division with no crash
  path. That makes the function crash-free (`Facts/Moves`), which makes it
  movable, droppable and raisable. The consumers must turn the fact into a
  more precise op, not store it; see §6's rule.

Why bother at the MLIR level, when LLVM re-derives ranges? **Measured**: in
`crash/`, the default region of `match_lit n {0 …}` tests `n == 0` three
more times and guards the division with `select i1 %9, i64 1, i64 %4`
(`crash.pre.ll`). LLVM removes all of it at O3. What LLVM cannot do is feed
the fact back into *Idris-level* decisions: effects, raising, case-of-case
legality, specialization keys and evaluation. Those happen before LLVM
exists.

---

## 2. Equality saturation for the simplify group? Cost and benefit

### The phase-ordering fights in the history (read: `git show`)

| Commit | What happened | Kind of interaction |
|---|---|---|
| `5fbc601` → `f5730a2` | A positive supercompiler with a whistle (homeomorphic embedding) and generalization; deleted in the cutover | expanding: unfolding and generalization |
| `cc3aebe` → `fc1d6f2` | "embedding for growth, stops that remember their key", then "the stopped, counted and historied specialization is gone", replaced by binding times | expanding: cloning |
| `81b0fa5` | specializing on machine Ints: "one clone per value … until the machine ran out of memory" | expanding: cloning |
| `9b58aaf` | case-of-case through nested matches: "grew the module past 15,000 lines within 2,000 rewrites without converging"; backed out | expanding: duplication inside canonicalize |
| `8cee6a8` | sink into regions unbounded: "2,000 to 12,000 lines in 40 s", hence `kSinkBudget = 64` (`Sink.cc:26,80`) | expanding: duplication inside canonicalize |
| `908df5f` | inliner bounded at 4 iterations: 279 s in idr-simplify, down to 39 s; sink's candidate walk down to 14 s | expanding (inline) against the round structure |
| `2685edd`, `558250e` | clones close call cycles; the MLIR inliner unrolls them "round after round and the simplify loop never ended"; loop breakers every round; a structural hash because sccp reorders constants | expanding (clone, inline) and a fixpoint test on IR |
| `7884dd8` | sccp, prune and remove-dead-values baked the one caller's constant into a raised clone; specialize re-specialized it: "call-pattern looped" | interprocedural constant propagation against cloning |
| `77d9b14` | write raising removed along with the heap rejections | raise against canonicalize |
| `3d02a0c`, `f748122` | Int counters unrolled as Nats, a binding-time special case | a fact re-derived by syntax |

**Read the table's last column.** Not one of these fights is between
*local, shrinking* rewrites (fold, known constructor, field of con, output
fusion), and those are the problem equality saturation solves ("when to
apply which rewrite … is called the phase ordering problem", egg §2,
`02-background.tex:344-352`). Every fight is between **expanding** or
**interprocedural** transformations: unfolding, cloning, inlining,
case-of-case duplication, and constant propagation across clones.

### Benefits of an e-graph here (real, but narrow)

- Order independence among the local rewrites. Known-constructor against
  output fusion against arithmetic folds would stop mattering.
- Rules as data. They can be checked (Ruler/Enumo, `pal-2023-ruler`
  abstract; Alive-style, §5) and enumerated.
- egglog's design (`zhang-2023-egglog`, abstract and `background.tex:139-208`)
  puts Datalog-style analyses with lattice merges beside the rewrites:
  "facts as relations". This half of egglog is the valuable part for us,
  and §1 and §6 take it with MLIR's DataFlow instead. Plain egg allows only
  one upward-propagating e-class analysis (`background.tex:360-365`),
  which is too weak for ranges plus labels plus uniqueness.

### Costs (why not for the simplify group)

1. **Scaling on functional terms.** Koehler et al.: "even with efficient
   lambda calculus encoding, unguided equality saturation can locate only
   the two simplest of these optimizations, the remaining five are
   undiscovered even with an hour of compilation time and 60GB of RAM"
   (`koehler-2021-sketch-eqsat/main.tex:173`). Our expanding transformations
   (inline, clone, case-of-case) are exactly the rewrites that make e-graphs
   explode. Herbie had to cap the e-graph's size and time (egg §6,
   `06-case-studies.tex:30-50`). We would be back to budgets.
2. **Regions are binders.** `idr.match` case regions bind fields, and a
   function body binds parameters. E-graphs over binders need de Bruijn
   encodings, which cost orders of magnitude (Koehler, abstract), or slotted
   e-graphs. The slotted-e-graph work in `sources/`
   (`wu-2026-slotted-egraphs`) proves a trace theorem that "does not
   establish concrete transition semantics … or refinement of the Java
   code" (`intro_compressed.tex`). That is research-grade.
3. **Linearity.** An e-graph is hash-consed, and congruence merges terms
   without regard to how many times they occur. Extraction can pick a term
   that uses an `!idr.lin` value twice, or drops it. Keeping quantities
   through extraction needs occurrence-aware (ILP) extraction. I know of no
   solution (**conjecture**, but the obstacle is structural). AGENTS.md
   forbids any pass that drops what Idris proved. The verifier would catch
   a violation after extraction, but that is a failure, not an
   optimization.
4. **Effects and worlds.** World-threaded IO must stay a fixed skeleton,
   with pure ops floating around it. That is Cranelift's "aegraph" design
   (not in `sources/`; **conjecture** that it transfers), and it only
   covers straight-line pure code.
5. **Extraction.** DAG extraction with sharing is NP-hard; greedy per-class
   extraction is exact only for tree costs (egg §2,
   `02-background.tex:395-400`).
6. **Integration.** egglog is Rust; binding it into MLIR is research work.

### Answer (Q2)

**No** for the simplify group. The cure for the history above is
structural (§6):

- move expanding transformations out of the greedy driver. `CaseOfCase.cc`
  and `Sink.cc` already break MLIR's own contract for canonicalization:
  "Repeated applications of patterns should converge", and "complicated
  cost models don't belong to canonicalization"
  (`mlir/docs/Canonicalization.md:44-60`);
- replace case-of-case duplication with join points;
- make the outer loop a fixpoint over monotone decisions.

**Maybe later**, a bounded e-graph for the *region-free, effect-free
peephole layer* (arith, bits, string and big ops, known-constructor on
straight-line code), with rules checked à la Alive. That is an experiment,
not an architecture.

---

## 3. Whole-program optimization beyond MLton

### 3.1 What MLton does, and where idris-mlir stands

MLton's SSA pipeline is a **fixed sequence** of passes, each run a fixed
number of times, with the order justified in comments. There is no global
fixpoint (`mlton/ssa/simplify.fun:44-120` at the snapshot's revision
`aa2fd1ad`; `simplify.fun` is not in `sources/code/mlton`, so I fetched it
to scratch). Lean's LCNF does the same, in three phases
(base/mono/impure) with an `occurrence` count per pass
(`Lean/Compiler/LCNF/Passes.lean:92-160`, fetched). Neither iterates the
whole pipeline to a fixpoint.

| MLton pass (from `simplify.fun`) | What it does | idris-mlir today |
|---|---|---|
| closure conversion with 0CFA (`closure-convert/`) | flow-directed defunctionalization | **parity**: `idr-defunctionalize`, keyed by (type, label set) |
| `inlineLeaf` ×2, `inlineNonRecursive` | size rule | **ported**: `Inline.cc:36-38` (kLeafSize 40, kSmall 60, kProduct 320) |
| `constantPropagation` (whole program, data too) | abstract values of constructors and globals | **stronger in one way**: `idr-eval` runs closed calls; `sccp` covers scalars; static shapes are recomputed syntactically by `Pattern.cc` |
| `contify` ×3 (Fluet & Weeks, dominators; `contify.fun:9-12`) | a function with one continuation becomes a block | **missing**, see the measurement below |
| `useless` (`useless.fun:10-25`) | fields and arguments whose values are never used | **missing for fields**; `remove-dead-values` covers arguments and results only |
| `removeUnused` ×4 | unused functions, constructors, arguments | `symbol-dce` and `remove-dead-values` (with `idr-prune` working around two pinned bugs); no unused-constructor removal |
| `simplifyTypes`, `splitTypes` ×2 | single-constructor types become tuples; types are split | **missing**: Emit decides box or sum by recursion alone (`Term.idr:309-310`) |
| `flatten`, `localFlatten` ×3, `deepFlatten` | pass tuple components instead of the tuple | partial: unboxed sums are taken apart 1:n by the lowering |
| `knownCase`, `redundantTests` (relational facts `x < y`, `redundant-tests.fun:9-60`) | case on a known constructor; tests implied by others | known constructor locally, and case-of-case; relational tests **missing** at idr (LLVM does some) |
| `introduceLoops` ×3, `loopInvariant` ×3 | tail self calls become loops; LICM | self tail calls only (`idr-tail-loops`); LICM left to LLVM |
| `commonArg`, `commonBlock`, `commonSubexp` | argument, block and value CSE | `cse`, and `Merge.cc` for identical regions |
| packed representation (`backend/packed-representation.fun`) | tags in pointer bits, nullary constructors as immediates | a header word with the tag; nullary constructors are **static cells**, so testing for `Nil` loads memory (`load i32 … and 65535` in `total'`, `lists.pre.ll`) |

**Measured: why contification matters.** In `tree/`, `insert x (Node l y r)
= if x < y then Node (insert x l) y r else Node l y (insert x r)`
elaborates to `insert` plus `case block 841 in insert`. After idr-simplify,
`insert` is `no_inline` (the loop breaker) and still *calls* the case block,
from both arms of a `match_lit` on `x < y`, passing constant `True`/`False`
(`tree/dump/01-idr-simplify.mlir`). The case block is never inlined. The
pinned MLIR inliner refuses any call whose callee calls the caller back,
"A->B->A" (`mlir/lib/Transforms/Utils/Inliner.cpp:709-715`). The loop
breaker does not help, because the refusal is the inliner's own and does
not depend on `no_inline`. Commit `2685edd` cites the same lines. Three
consequences:

- the Bool is materialized and matched again in the callee: case-of-case
  paid for itself only on paper (`Meet.cc:13-25` predicted a fold that never
  came);
- **reuse is lost across the call**: `insert` resets the node's cell and
  frees it (`call void @idris_rt_free_cell(ptr %35)`), and the case block
  allocates a fresh one (`tree.pre.ll`);
- mutual tail recursion (`ev`/`od`, `mutual/`) stays two functions at the
  MLIR level (`06-idr-tail-loops.mlir`). Constant stack depends on LLVM's
  sibling-call optimization, which happens to hold here because all
  arguments fit in registers (**measured**: 10^8 iterations ran).

An Idris case block is, by construction of the elaborator, a continuation of
its parent. Contifying it, or emitting it as a region in the first place,
makes the A→B→A cycle unrepresentable. MLton runs contify three times.

### 3.2 What Idris facts add beyond MLton

For each fact: what it enables, and whether we exploit it today.

| Idris fact | Analysis or transformation it enables | Status and evidence |
|---|---|---|
| **Quantity 1, plus the whole program** | *Uniqueness inference*. Linearity proves the callee uses a value once; whole-program flow proves every caller passes an unshared one. Then reset/reuse with no runtime test, and `noalias` for LLVM. MLton has neither half; Koka's FIP checks the callee statically but tests the caller at runtime (README). | Planned in `Ownership/ResetReuse.cc:19-25` ("belongs on the parameter's type, computed over the call graph"). Today every reuse tests at runtime: `icmp eq i32 %7, 1` plus a check of the static mark in `bump` (`lists.pre.ll`). |
| **Quantity 1 and fresh cells** | *Tail recursion modulo cons* (destination passing): `bump (x :: xs) = f x :: bump xs` builds the cell first and passes the hole down, which gives a loop. Legal because the fresh cell is unshared until returned. MLton does not do this. | **Measured**: `bump` over 400,000 elements **segfaults** (stack overflow at the default 8 MiB), and 10^6 fails too; Chez gives the answer (`lists/`). With `ulimit -s unlimited` it succeeds. A silent crash is worse than a named `unsupported`. |
| **Quantity 0** | erasure | Done (`!idr.erased`). **Beyond**: erased *proofs* are the richest facts and vanish entirely. `LTE i n`, `NonZero d`, `So (x < y)`, `Elem`, and `x = y` could survive as zero-width SSA facts that range analysis consumes and the lowering turns into nothing or `llvm.assume` (conjecture: design needed; see open questions). |
| **Totality** (Idris-proved termination and coverage) | Speculation and hoisting of pure total calls (`Facts/Moves` already uses it); dropping dead calls; `willreturn`/`mustprogress` for LLVM; **eager evaluation of `Lazy`/`Delay` whose body is total, crash-free and cheap**. Strictness analysis becomes a cost question, not a divergence question, which GHC cannot say. Coverage gives exhaustive matches, so the last case is the default (done). | Eval budget by totality: done (`Eval.cc:52-68`). Eager `Lazy`: missing (conjecture that it pays on `Stream`/`Inf` and on the `if`/`&&` thunks that survive inlining). |
| **Size-change graphs** (`GlobalDef.sizeChange`) | Binding times without re-derivation; which match region is the base case (branch weights); bounds on recursion depth when the decreasing argument is statically small (stack budgets for recursive functions, now a flat 64 bytes, `Stack/Pass.cc:38`) | Read by the frontend only for polymorphic recursion (`Frontend/Translate/Recursion.idr:1-7`, commit `6883563`), then **dropped**. `BindingTimes.cc` re-derives a weaker version from syntax. |
| **Nat is a non-negative Integer**, with `plus`/`mult`/`minus`/`equalNat`/`compareNat` as Integer ops | Integer arithmetic instead of unary recursion; a range ≥ 0; small Nats unboxed | Upstream Idris does this for every backend with its "natHack" (`third_party/Idris2/src/Compiler/Opts/Constructor.idr:81-95`), at the CExp level, which this compiler does not consume. **Measured**: `count (S k) acc = count k (acc + 2)` calls the Prelude's recursive `plus` once per iteration. It takes 1.9 s, 8.0 s and 39.2 s for n = 10k, 20k and 40k (quadratic); Chez takes 0.11 s for 40k and 0.13 s for 10^7. `!idr.big` conflates Integer and Nat ("an Integer, or a Nat-like value (non-negative)", `IdrOps.td:79-81`). |
| **Indices** (`Fin n`, `Vect n`) | ranges [0, n); no bounds checks; exact sizes; unrolling | When `n` is static, done: `index (toFin4 n) v` became a 4-way switch with no check (`vect.pre.ll`). When `n` is only known at runtime, `Fin n`'s bound is erased with `n`. |
| **Linearity and totality together** | *Fusion/deforestation* of intermediate structures: a producer consumed once by a total consumer can be fused without duplicating work or changing termination | Missing: `upto`, `bump` and `total'` each materialize the list (`lists.pre.ll`). |
| **Pure, total code is referentially transparent** | CSE of *calls* across the whole program, and memoization of closed calls (the eval cache, `Eval.cc`, is one) | Partial: `cse` works per region; no CSE of calls. |

**Answer (Q3).** Close the MLton gap first: contify (as an Emit-level
representation or an MLIR pass), useless fields (a backward lattice with the
same `FieldAnchor`), type simplification, and the Nat mapping. Then build the
fact-driven transformations MLton cannot have: uniqueness, TRMC, eager
`Lazy`, and fusion. Two of them are measured failures today (Nat is
quadratic, deep non-tail recursion segfaults).

---

## 4. What LLVM receives, and what it should

**Measured**: the IR the translation produces before O3 (`*.pre.ll`), and
after O3 (`*.O3.ll`, runtime linked, `Lower/Target.cc:28`).

| LLVM fact | Today (cited IR) | What Idris fact justifies more | Honest value |
|---|---|---|---|
| function attributes | none on generated functions (`define ptr @Main.bump(ptr %0)`); after O3 only `nounwind` (`attributes #0 = { nounwind }`, `lists.O3.ll`) | `idr.total` → `mustprogress willreturn`; `#idr.effects<none>` → `memory(...)` (reads of cells only) | LLVM cannot infer `willreturn` for recursive functions. Dead-call removal already happens in idr (`canDrop`), so the gain is small. |
| `nonnull`, `dereferenceable(n)`, `align 8` on box pointers | none on parameters or results; LLVM inferred `nonnull` only on `idris_rt_cell` (`noundef nonnull ptr @idris_rt_cell()`) | representation: a box is never null (static cells for nullary constructors); the constructor's size from `Layouts` | Moderate: enables speculating loads. Note that the lowering uses `null` as a placeholder in phis (`phi ptr [ %15, %11 ], [ null, %10 ]`), so the attribute belongs on values, not on every phi. |
| alignment of field loads | `load i64, ptr %12, align 4` for 8-byte-aligned cells (`lists.pre.ll`, `total'`) | Layout knows | Small but free. |
| `noalias` | none | *not* `!idr.lin` (linear ≠ unique, AGENTS.md); **yes** for a proved-unique cell (§3.2) and the reuse token; `allockind("alloc")` on `idris_rt_cell` | Depends on uniqueness inference. |
| TBAA | the generated code has none; the runtime, compiled from C++, has its own (`store i32 %sub…, ptr %0, … !tbaa !9816` next to untagged field loads in `bump`, `lists.O3.ll`) | the representation: header count (mutable), info word (immutable while a cell lives), fields by type | Moderate in loops that count (conjecture). Also, a cell's fields are immutable between construction and reset: `!invariant.group` on field loads, with `llvm.launder.invariant.group` at reuse, is exactly the C++ vptr pattern (conjecture: needs care). |
| `range` metadata, `nsw`/`nuw` | none; the tag is masked (`and i32 %3, 65535`) | tag ∈ [0, #ctors); Char ≤ 0x10FFFF; Nat ≥ 0; `Fin n` < n. **Not** `nsw` on `Int`: Idris `Int` wraps, and the lowering is right to emit a plain `add` | Small for tags (LLVM sees the switch); real for Nat and Fin once they have types. |
| crash paths | `declare void @idris_rt_crash(ptr, i64) #0` with `#0 = { noreturn }`; the call is followed by `br label %14` and a guard `select i1 %9, i64 1, i64 %4` before `sdiv` (`crash.pre.ll`; `Lower/Runtime.cc:94-99` lowers a crash as `scf.if` + call, `Lower/Patterns.cc:215-240`) | a crash does not return | Add `cold`. O3 already rewrites everything after a `noreturn` call to `unreachable`, and the O3 loop is clean (`crash.O3.ll`), so explicit branch weights on crash paths add little. |
| branch weights | none | size-change: the region that recurses on a decreasing argument is the likely one; a reuse test on a value whose binder was linear is likely to succeed (a heuristic, not a proof) | Conjecture; measure before adding. |
| `llvm.sideeffect` / `mustprogress` | partial loops carry `llvm.sideeffect` (`ack`, `readInt`'s `go`); total ones carry nothing; `main` makes no progress claim (commit `d26ffc5`) | totality | This one is right as is. |

**Answer (Q4).** The genuinely Idris-sourced facts worth sending are:

- `willreturn`/`mustprogress` from totality;
- `range` from Nat, Fin and tags, once they are types;
- `noalias` from *proved uniqueness* (not from linearity);
- `nonnull`/`dereferenceable`/`align` from the representation;
- TBAA (or `invariant.group`) from cell immutability.

Most of what LLVM "misses" today it re-infers at O3, because the runtime is
linked into the module. The larger gain is facts consumed *before* LLVM,
§1 and §3.

---

## 5. Translation validation and verified rewrites as a safety net

What is feasible, cheapest first:

1. **Checkers for facts: infer globally, check locally.** The owned-stage
   verifier (`Ownership/Verify.cc`, run after every pass once
   `idr.stage = "owned"`, `Dialect.cc:436-441`) already follows CompCert's
   pattern: a validator smaller than the transformation
   (`leroy-2009-compcert`, §2.2: `Comp'(S) = … if Validate(S, C) …`). Make
   it the rule for every fact that a transformation relies on. The fact
   lives in a type (or an inherent op property) whose *local* verifier rule
   is sound. The global lattice inference only produces it. This works for:
   - quantity (done);
   - uniqueness: every call passes a fresh cell or a unique value moved;
   - frame-local cells: a frame-typed value never reaches a return, a
     capture, a heap field or an unknown call, as OCaml's local mode does
     (`lorenzen-2024-oxidizing-ocaml`, link only);
   - a size-change edge: the argument is a field or a predecessor of the
     parameter;
   - effects: a local check, given the labels.

   It does **not** work for termination (trusted from Idris; losing it only
   costs speed) or ranges (consume them immediately into precise ops).
2. **Differential execution with the existing JIT.** `idr-eval` already
   lowers, JITs, meters and reifies calls in a child process
   (`Eval/*.cc`). A `--validate` mode can run a changed function before and
   after a pass on inputs enumerated from its types (small data, random
   machine numbers) and compare the reified results. Totality makes the
   comparison meaningful within the meter. This is bounded validation in
   Alive2's sense: it "misses bugs" but raises no false alarms
   (`lopes-2021-alive2`, abstract). `tools/bisect.sh` and the MLIR action
   framework (`Support/Actions.h`, `idr-eval-call`) already bisect to one
   action. Extend both to every rewrite.
3. **Verified local rules.** The DRR patterns (`Canonicalize.td`), the
   folders and known-constructor are small enough for Alive-style SMT
   checks. Arithmetic uses bitvectors; constructors and matches use the SMT
   theory of algebraic datatypes; strings and bigs use Z3's theories, with
   the runtime's C as the reference semantics. Alive translated 300 LLVM
   rules and found eight wrong (`lopes-2015-alive`, abstract). Regions are
   covered by LeanMLIR's peephole framework (`bhat-2024-verifying-peephole`,
   abstract and §4.1), which proves rewriting sound over an SSA calculus
   with regions. Cost: a formal semantics of the `idr` ops. The runtime is
   their meaning, so the model must be checked against it (differential
   testing again).
4. **Not feasible**: whole-program SMT translation validation of
   inline + clone + eval + defunctionalization. Alive2 is intraprocedural,
   bounded and unrolls loops. Our transformations change call graphs.

**Answer (Q5).** Feasible and cheap: (1) and (2), with (2) almost free
because the JIT exists. Moderate: (3) for the rule layer. Not feasible: (4).
The architecture below makes (1) structural.

---

## 6. A proposed architecture, as data

### The rules

- **R1. A fact has one producer**, which is a lattice inference or Idris
  itself. It lives in a **type or inherent property** when losing it would
  be unsound, and there **a local verifier rule checks it** after every pass
  (§5.1). A fact whose loss only costs speed (totality, `idr.stack`) may be
  a discardable attribute. A fact that cannot be checked locally (ranges,
  shapes) is **never stored**: its consumer rewrites the IR into an op that
  cannot express the bad state ("parse, don't validate": a division proved
  non-zero becomes `arith.divsi`, a case proved impossible is deleted).
- **R2. A transformation declares the facts it needs**, whether it
  *shrinks* (a measure strictly decreases) or *expands* (it consumes a
  decision), and which facts it invalidates. A phase recomputes the
  invalidated facts, as MLIR's analysis manager already does per pass.
- **R3. Termination by construction.** Shrinking transformations run to a
  greedy fixpoint (a measure decreases: MLton's shrinker, Lean's `simp`).
  Expanding ones never run "until the IR stops changing". Each takes
  decisions from a monotone, finite decision set, and the outer loop is
  Kleene iteration on that set. `structural()` (`Simplify.cc:137-176`) and
  the reason for it (sccp's constant churn, `Simplify.cc:10-18`) become
  irrelevant; `max-rounds` stays as an assertion.

### Facts

| Fact | Lattice | Carrier | Producer (one) | Local checker | Consumers |
|---|---|---|---|---|---|
| Quantity | {0, 1, ω} | types `!idr.erased`, `!idr.lin<T>` | Idris (Emit) | verifier (exists) | rc, specialize, raise, defunctionalize |
| Totality | {total, partial} | `idr.total` (loss-safe) | Idris | none (trusted) | eval budget, moves, LLVM `willreturn` |
| Size-change | per call edge: {<, ≤, ?} per argument pair | inherent property of the recursive call, composed on clone and inline | Idris (`sizeChange`, which Emit emits) | the argument is a field or a predecessor of the parameter | binding times, branch weights, stack budget |
| Labels | sets of functions, ⊤ | analysis state | `LabelAnalysis` (exists) | none (consumed by defunctionalize into sums) | defunctionalize, effects, escape, recursion |
| Effects | {io, crash} per function | `#idr.effects` (recomputed; loss-safe) | CallGraph SCC fold over labels | a local recomputation | moves, raise, eval, case-of-case |
| Shape (partially static value) | ⊥ / ctor C [v…] / closure f [v…] / constant / ⊤, with depth widening (Lean `ElimDeadBranches.lean:21-43,141-175`: `maxValueDepth = 8`) | analysis state | one sparse forward, interprocedural analysis with field anchors | none (consumed) | known-case, prune (dead regions), specialize keys (replacing `Pattern.cc`'s syntactic walk), eval closedness |
| Range | intervals (`IntegerValueRange`) | analysis state; types for Nat (`≥ 0`) and Fin | `IntegerRangeAnalysis` + idr transfer functions + `match_lit` region arguments | none (consumed into precise ops) | division/index/crash rewriting, folds, LLVM `range` |
| Escape | {none < contents < reference} | a frame-local mark in the **type** of the con's result (new), or `idr.stack` (today; loss-safe) | sparse backward analysis, shaped like LivenessAnalysis | a frame-typed value reaches no return, capture, heap field or unknown call | idr-stack, uniqueness |
| Uniqueness | {unique, shared} per value and parameter | **type** (new) on parameters and results | forward/interprocedural: fresh con or call result, moved linearly; a parameter is unique when every caller passes a unique value | each call site passes a unique value | reset without test, TRMC, fusion, `noalias` |
| Borrowed | {owned, borrowed} per parameter | `idr.borrowed` (verified by the owned stage) | Borrow.cc (exists) | owned-stage verifier (exists) | rc |
| Useful field | {useless, useful} per (data, ctor, field) | analysis state | sparse backward with field anchors | none (consumed: the field is deleted) | useless-field removal |
| Continuation | per function: the unique return continuation, or none (Fluet & Weeks) | none: consumed by contify | dominator analysis on the call graph | none | contify |

### Transformations

| Transformation | Needs | Kind | Termination measure / decision set |
|---|---|---|---|
| fold, known-case, field/tag of con, output fusion, DCE of calls, prune | shape, effects, ranges | shrink | op count, redexes |
| contify (case blocks: best at Emit, as regions) | continuation | shrink | function count |
| join points in place of case-of-case copying: the consumer becomes a join, each yield a jump; a jump whose shape is known gets its own copy of the join | shape | expand (decision) | set of (join, ctor) copies: finite |
| inline (MLton's rule) | size, loop breakers | expand (decision) | set of (caller origin, callee) edges: finite |
| specialize | shape, binding times from size-change | expand (decision) | set of keys: finite by binding times, `kUnrollLimit` (`Specializer.h:18`) and `kClonesPerOwner` (`Clones.h:22`) |
| eval | effects, totality (budget), shape (closed) | shrink (call → constant) | cache of evaluated keys (exists) |
| defunctionalize | labels | representation | once |
| useless fields, simplify types, Nat mapping | useful field; Idris | representation | once |
| TRMC, fusion | uniqueness, totality | representation | once per recursive function |
| stack, reset/reuse, borrow, rc | escape, uniqueness, borrowed | ownership stage | once |
| lower | ranges, totality, uniqueness, layout | lowering | once |

### Phases (Lean's shape, with legality by phase)

1. **Pure idr, Idris facts seeded.** Quantities, totality, size-change,
   case blocks as regions, Nat as its own type.
2. **Decision loop.** Compute labels, shape, ranges and effects. Grow the
   decision sets {inline edges, spec keys, eval keys, join copies}.
   Materialize them. Shrink to a fixpoint. Repeat while the decision sets
   grow.
3. **Representation, once.** Defunctionalize, useless fields, type
   simplification, contify leftovers, TRMC and fusion.
4. **Ownership, a separate stage, once.** Escape, then uniqueness, borrow,
   rc, reset/reuse and tail loops. (review-external's point that the two
   semantics should come from what is loaded, not from a module attribute,
   applies here; see mlir-idioms.)
5. **Lowering** with the LLVM facts of §4.

### Delete

- `Dialect/Canonicalize/Sink.cc` (and `kSinkBudget`), and the duplication in
  `CaseOfCase.cc`: replaced by join points. The profitability oracle
  `Meet.cc` goes with them. Its prediction was wrong in `tree/`.
- `Facts/Closures/Passed.cc`: a weak duplicate of the label lattice.
- `Stack/Recursion.cc`'s "an apply calls every address-taken function":
  replaced by labels.
- `BindingTimes.cc`'s re-derivation, including the subtraction hack
  `:121-126`: seeded from size-change.
- `Simplify.cc`'s `structural()` fixpoint test: replaced by decision-set
  growth (keep it as a debug assertion if wanted).
- The `InferIntRangeInterface` implementations stay only if a range
  analysis runs in the pipeline. Otherwise they are decorative by the
  dialect's own standard.

### Keep

- Quantities in types, and the verifier after every pass.
- `LabelAnalysis` on MLIR DataFlow, as the template for every new lattice.
- `idr-eval` (the JIT): both an optimizer and the validation oracle of §5.
- MLton's inline rule and the loop breakers.
- The owned-stage verifier (the model for R1's checkers) and Borrow.cc.
- `idr-expect`'s property API, whose properties turn into verifier rules
  where they are facts (`reuses-in-place` → uniqueness).

---

## What it means for idris-mlir, concretely (ordered by evidence)

1. **Map Nat's Prelude arithmetic to big ops** (the natHack's five
   functions). Measured quadratic; a registry-sized change
   (`Registry/Recognized.idr`). Give `Nat` its own type so the range ≥ 0
   is carried.
2. **Case blocks are continuations**: emit them as regions, or contify.
   Measured lost reuse and an unexploited case-of-case in `tree/`; and the
   A→B→A refusal in MLIR's inliner deserves an entry in `upstream/` if we
   keep relying on the inliner for this.
3. **TRMC for constructor-guarded recursion**. `bump` over 400k elements
   segfaults; Chez does not.
4. **Uniqueness as a type**, inferred over the call graph, checked locally
   (`ResetReuse.cc:19-25` already says so): the README's promise.
5. **Run range analysis**, with `match_lit` region arguments, feeding crash
   causes and `knownNonZero`.
6. **The decision-set loop, and join points** in place of `Sink.cc` and
   case-of-case copying.
7. **Size-change edges from Emit**, in place of re-deriving binding times.
8. **LLVM facts**: `nonnull`/`dereferenceable`/`align` from the layout,
   `range` for tags, Nat and Fin, `cold` on crash, `willreturn`/`mustprogress`
   from totality, and `noalias` only after 4.
9. **`--validate`**: differential execution of changed functions through
   the JIT.

## Open questions

- **Join points in MLIR.** A jump from inside nested `idr.match` regions to
  a named continuation is non-local control flow that structured regions
  forbid. Options: `rgn.val`/`rgn.run`-style region values
  (`bhat-2022-lambda-ultimate-ssa`, §"The rgn Dialect", `paper.tex:1693-1714`),
  unstructured blocks inside the function, or a yield that names its join.
  Which one keeps `RegionBranchOpInterface` and the dataflow framework
  working? (mlir-idioms.)
- **Erased proofs as facts.** Which Idris propositions (LTE, NonZero, So,
  Elem, `=`) are worth keeping as zero-width values after erasure, and how
  does Emit recognize them robustly? `Registry/Recognized.idr` already
  recognizes `Builtin.Equal`.
- **Size-change across erasure.** Idris's `SCCall` matrices index *source*
  arguments, implicit ones included. Emit needs the map to MLIR parameters
  after erasure and monomorphization. Composition under inlining and
  cloning is standard (Lee, Jones and Ben-Amram), but untested here.
- **Does eager `Lazy` pay?** It needs a cost bound on the thunk body. A
  total, crash-free body can still be expensive.
- **The decision-set loop.** Does every interaction the current rounds find
  (evaluation exposing specialization exposing evaluation) show up as
  decision-set growth? The do-block case (`908df5f`) is internal to the
  inliner and does. Unknown: `7884dd8`-style interactions through `sccp`.
- **ackdyn** (MLton 2.3x faster, README): the O3 IR of `ack` is a tight
  loop plus one recursive call (`ackdyn.O3.ll`). The difference is probably
  frame and calling-convention cost, not the optimizer. Not investigated.
