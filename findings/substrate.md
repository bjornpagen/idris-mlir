# The substrate: one representation per idea, MLIR first

How the compiler should hold what it knows, written against `main` at
cb65104. It is research: nothing here was built, run or timed unless a line
says **measured**. Its partner, `concurrency.md`, applies the same moves to
thunks, tasks, shards and futures; `README.md` orders the work of both.

Claims are marked:

- **read**: the file named, at cb65104.
- **measured**: a count or a run on this tree, with how.
- **decision**: what this note decides, for the user to accept or change.
- **conjecture**: an estimate, to be checked by the step that needs it.

## 0. The method

### Representation before control flow

The biggest lever in this compiler is how it represents what it knows, not
how its passes branch. When a new case shows up, there are two ways to absorb
it:

- **Patch the trace.** Add another branch, flag or guard, and the complexity
  gathers in control flow.
- **Change the representation.** Change the data, the types and their
  invariants until the case is no longer special, or no longer expressible.

The practitioners say it in nearly the same words across thirty years.
Brooks (*The Mythical Man-Month* ch. 9): "Show me your tables, and I won't
usually need your flowcharts". Pike's rule 5: "data dominates", with a
citation to Brooks. Raymond: "smart data structures and dumb code". Torvalds:
"good programmers worry about data structures and their relationships".
The type-theoretic account of why it works:

- **Make illegal states unrepresentable** (Minsky). A precise sum type leaves
  nothing for the guards to guard.
- **Parse, don't validate** (King). A check that returns the refined value
  happens once. A check that returns nothing happens again at every use.
- **Choose the coordinates** (Dijkstra's half-open interval, homogeneous
  coordinates). Some special cases are artifacts of the representation and
  vanish with a better one.
- **Make control flow data and give it a small evaluator** (SICP ch. 4).

The limit is Brooks's own ("No Silver Bullet"). A better representation
removes accidental complexity only. Two genuinely different cases forced
into one representation just hide their branch.

AGENTS.md already states the rule for this tree: one thing, one
representation; when a new case shows up, change the data and its invariants
until it is not special, before adding a branch, a flag or a guard. This
note applies that rule everywhere at once.

### Five steps, in order

Every requirement below went through these, in this order:

1. **Question the requirement.**
   - A requirement must name who needs it and what breaks without it.
   - A requirement inherited from a note is a hypothesis, including ones
     from this note's earlier drafts.
2. **Delete the part or the process.** If nothing has to be put back
   afterwards, not enough was deleted.
3. **Simplify what remains.**
4. **Accelerate it**: compile time, run time.
5. **Automate it**: passes, verifiers, properties.

Section 5 lists the requirements this pass deletes, each with where it came
from and why it was not real.

### MLIR first, in a fixed order of preference

**decision** For each concept, take the first of these that holds it whole:

1. an upstream MLIR mechanism (op, interface, pass, utility);
2. an upstream interface we implement on our ops;
3. an op or type of ours that carries a fact Idris proved, or a meaning only
   our runtime gives;
4. a pass of ours;
5. a hand-written C++ walk.

An `idr` op that does neither of the things in item 3 should not exist.
This is the order the MLIR paper argues for: semantics in declarative op
definitions and interfaces, so that generic passes (inlining, CSE, DCE, the
dataflow framework) work on every dialect without knowing it (read:
`sources/papers/lattner-2020-mlir/implications.tex`, "Optimization
interfaces"; `infra.tex`, ODS and DRR).

## 1. Where the special cases live today

The inventory the moves below delete. Counts are **measured** with `grep`
over `foreign/idr/lib` and `compiler/src` at cb65104. Rows marked "audit"
were first listed in the one-representation audit, `findings/one-representation.md`
at 4cfce76, which cb65104 deleted; the open ones are carried here.

| # | Special case | Where | Count | Move |
|---|---|---|---:|---|
| 1 | The evaluation mode threaded through the lowering (`jit`) | Lower/Lowering, Runtime, Pass, Counting, StackCell; Eval/* | 47 mentions in 10 files (audit row 18 counted 31 in 8) | S3 |
| 2 | Closures lowered for `idr-eval` only, while programs hold none | Lower/Closures.cppm (`populateClosurePatterns`: "Only idr-eval's lowering meets a closure"), Layout, Reify's code table, the runtime's closure release | — (audit row 6) | S3 |
| 3 | The thunk written by hand: enter/done, the code-pointer swap, `distinguish`, `idris_rt_lazy_kept`, mutable static suspensions | Lower/Runtime.cppm `emitSuspension`, Lower/StaticData, runtime/Rc/Counting | — | S1, `concurrency.md` §2 |
| 4 | Closure conversion done in Idris, with labels as symbols, and four canonicalization patterns that undo a suspension built only to be forced | Term.idr `Lam`/`Suspend`; Emit/Bodies; Dialect/Ops/Lazy.cc | 4 patterns | S1 |
| 5 | Consumption as an `isa` table | Ownership/UseOf.cppm | about 20 op kinds | S2 |
| 6 | A module attribute that changes what a plain type means | `idr.stage` | 6 mentions (audit row 17) | S2 |
| 7 | A partial op's precondition stated three times: the crash cause, the lowering's check and the folder's guard | 17 `Idr_MayCrash` ops | 45 `getCrashCause` mentions (audit row 14) | S2 |
| 8 | A claim that removes a check (`in_bounds`), sound only by pipeline order | InBounds/*, Passes.td `idr-in-bounds` | — | S2 |
| 9 | `ub.poison` as "no value" | Lower/Cells, Narrow, InBounds, Ownership, Tail, Verify | 33 sites (audit counted 14) | S2 |
| 10 | The two array loops as special constructors on both sides | Idris `ArrayGen`/`ArrayFold`; C++ `ArrayGenerateOp`, `ArrayFoldOp`, `isArrayLoop` | 16 Idris, 45 in 14 C++ files (audit §3 #3) | S1 |
| 11 | The primitive set mirrored in Idris | `Prim`, `IOOp` in Types.idr | 2 types (audit row 2: stage 4a) | S5 |
| 12 | Constants nested as deep as a list is long, with two pins on the depth | Eval/Reify, `#idr.con` | pins `mlir-recursion`, `bytecode-deferred-quadratic` (audit row 20) | S4 |
| 13 | Strings with a cell kind of their own beside arrays and buffers | runtime/Strings, Lower/Strings, Lower/Arrays | — (audit row 7) | S3 |
| 14 | Lists as cells where the program wants a buffer | the lists note at 4cfce76 | 4 slow benchmarks | S3 |
| 15 | Base's foreign surface rejected as `%foreign` | System.File, Directory, Clock, Errno, getArgs, getEnv, Term | 62 foreign definitions in File, Clock, Directory and System; at least 10 upstream tests (read: `findings/upstream-idris/results`) | S5 |
| 16 | The acyclic-heap decision, not enforced | `decision-acyclic-heap.md`; no `cycle` rule in Rule.idr | 0 checks | §3 |
| 17 | The in-place promise of README's "Why not Lean 4", not enforced | "the static promise is not" (read: README.md) | 0 checks | §3 |
| 18 | A clang-module workaround in our code instead of a patch, contrary to AGENTS' patch rule | PINS `clang-module-layout-forward-declaration`; `clang-module-predeclared-new`'s went with the LLVM pin (20fcfadb) | 1 (2 at cb65104) | §6 |
| 19 | The grade as a wrapper type, unwrapped by hand | `unrestricted(` | 98 sites | kept (§7) |

## 2. The six moves

### S1. Deferred computation is a region whose captures are explicit only when it leaves

**The concept.** A computation that is not run where it is written. The
dialect spells it six ways today:

- `idr.closure` and `!idr.fn`: run later, here, any number of times;
- `idr.suspend` and `!idr.lazy`: run later, here, at most once, with the
  result shared;
- `idr.array.generate` and `idr.array.fold`: run now, here, once per index;
- Idris's `Term.Lam`, `Term.Suspend`, `ArrayGen` and `ArrayFold`, which
  closure-convert in Idris;
- the hop and the fork of `concurrency.md`: run elsewhere, once.

MLIR's vocabulary for this is the **region**. A region op says when its body
runs through upstream interfaces:

- `RegionBranchOpInterface`: regions entered now, as by `scf.for` and our
  matches;
- `CallableOpInterface`: bodies run when called;
- `IsolatedFromAbove`: regions whose only inputs are explicit operands.

The MLIR paper names that last property as both a semantic barrier and what
lets passes run in parallel: "no use-def chains may cross the isolation
barriers" (read: `sources/papers/lattner-2020-mlir/ir_design.tex`, "isolated
from above").

**decision** Every deferred computation is a region op. Its type says how
the result is consumed, and its captures are implicit (SSA uses of
enclosing values) until something needs them explicit:

| Op | Result | Consumed by | Region runs | Isolated |
|---|---|---|---|---|
| `idr.lambda` | `!idr.fn<(A) -> (B)>` | `idr.apply` | later, here, any number of times | when it becomes data (S1.2) |
| `idr.delay` | `!idr.lazy<T>` | `idr.force` | later, here, at most once; shared result | when lowered |
| `idr.array.generate`, `idr.array.fold` | array, accumulator | — (`RegionBranchOpInterface`) | now, here | never |
| `idr.fork` (`concurrency.md` §4) | `!idr.join<T>` | `idr.join` | later, on another shard, once | always (`IsolatedFromAbove`) |

#### S1.1 What implicit captures buy

**Constant propagation instead of specialization.** A lambda that captures a
constant is a closure pattern idr-specialize must clone for today (read:
Passes.td, `idr-specialize`; Specialize/Pattern). As a region,
`sccp`/`canonicalize` see the constant in the body directly, because the use
is an ordinary SSA use. Specialization keeps the case it exists for: a
static argument of a *call*.

**Inlining an apply is region inlining.** `idr.apply` of an `idr.lambda`
with the same body in scope is `inlineRegion`, which needs neither a symbol
lookup nor a callee clone. The same holds for `idr.force` of an `idr.delay`
with one use.

**Four patterns become two rules.** `ForceOfOneUse`, `ForceOfOneConstant`,
`ForceInOneCase` and `ForceAtCapture` (read: Dialect/Ops/Lazy.cc) become:

1. a delay whose one use is a force, in any nested region, a lambda's
   included, is inlined at that force;
2. forces in disjoint arms of one match each inline the delay.

`ForceAtCapture` exists only because closure conversion happened in Idris,
so that a forced capture had become a parameter. With implicit captures it
is rule 1.

**Two Idris constructors go.** `ArrayGen`/`ArrayFold` are already region
ops in the dialect. The Idris side keeps one generic region-op node with
generated ops (S5), instead of a constructor per library loop.

#### S1.2 Closure conversion moves into MLIR

Lambda lifting and closure conversion in Idris (Term.idr `Lam` with a label
and a capture vector; Emit/Bodies lifting the body to a function) become one
MLIR step:

- `mlir::makeRegionIsolatedFromAbove` computes and threads the captures;
- `outlineSingleBlockRegion` makes the function where one is wanted.

(read: `.toolchain/llvm-project/mlir/include/mlir/Transforms/RegionUtils.h:69`;
`mlir/include/mlir/Dialect/SCF/Utils/Utils.h:69`.)

A label stops being a name Idris invents and becomes the op. Its name, when
one is needed, is the outlined symbol.

When does a lambda need a name? When its label must outlive the function it
is written in:

1. idr-defunctionalize turns it into a sum constructor;
2. a compile-time result holds it (idr-eval reifies a closure);
3. a constant names it.

Isolation and outlining happen once, by one pass (`idr-isolate`). In phase
1 (proposal 0002) the pass runs first in the pipeline, so the simplify loop
keeps the symbol form: closure conversion leaves Idris without every pass
of the loop becoming region-aware in the same change. Phase 2 moves the
pass to the first of the three needs above, and lets regions live through
the loop, which is what the two region rules of S1.1 need.

The audit placed this move last (its stage 5) because it touches every
Idris lane. It is placed early here (W6) because S1 is the substrate the
concurrency work builds on: `idr.fork` is an isolated region of the same
family, and a thunk is `idr.delay`.

#### S1.3 What stays essential

The three result types stay distinct, because they are three protocols
(`concurrency.md` §6):

- a closure is applied many times and keeps no state;
- a thunk keeps one memo;
- a join is consumed once, on another shard.

Collapsing them into one op with a mode would put the branch back into
every reader. What is shared is captured once, as an interface,
`CapturingOpInterface`, implemented by all three:

- the capture set;
- isolation;
- the layout of captures;
- the ownership of captures (each is consumed into the cell);
- the send check (`concurrency.md` §4.6);
- outlining.

### S2. Ownership, effects and partiality are declared on operands and types

#### S2.1 Consumption is an effect on a reference resource

Today `useOf` is a table over about 20 op kinds (read: Ownership/UseOf.cppm),
and every new op must remember to join it. MLIR already has a vocabulary
for "this op does X to operand Y": memory effects on a resource, declared
per operand in ODS (`Arg<Type, "", [MemFree<Resource>]>`).

**decision** One resource, `Idr_ReferenceResource`:

- a use that consumes an owned reference is `MemFree` of that resource on
  that operand, declared in ODS where the op is defined;
- a call's consumption comes from the callee's parameter grades, through the
  existing external model (read: Facts/CallEffects.cc).

The effect is conditional on the grade in the operand's type: an operand of
type `!idr.own<T>` or `!idr.excl<T>` is consumed; a plain `T` is a view.
Before idr-rc every value is plain, so every op keeps the purity it has now.
After idr-rc the same declaration states consumption, and three readers see
it:

- **counting** (`useOf` becomes a query);
- **the ownership verifier**;
- **every upstream pass.** A consuming call is no longer dead to
  `remove-dead-values` just because its result is unused, which closes the
  census hole the MLIR survey found (read: `findings/mlir-survey.md` at
  4cfce76, §C).

#### S2.2 The grade replaces the stage

`idr.stage` makes a plain type mean "any quantity" before idr-rc and "a
view" after it (6 mentions). **decision**: a view is the grade
`(u, borrow)`, written by idr-rc as it writes `own` and `excl`. A plain type
then means one thing in every stage. The verifier's trigger becomes "an op
whose operand has an owned or borrowed grade", which no pass can drop
without dropping the grade itself.

#### S2.3 A partial op is a guard and a total op

King's rule applied to the IR. Today a partial op says its precondition
three times:

1. `getCrashCause`, which makes it `MayCrash`;
2. the lowering's check;
3. the folder's guard.

Seventeen ops declare `Idr_MayCrash`, and `getCrashCause` appears 45 times
(**measured**).

**decision** One guard op per kind of precondition:

- `idr.check.nonzero`
- `idr.check.in_bounds`
- `idr.check.byte`
- `idr.check.finite` (a Double cast to an integer)
- `idr.check.nonempty`
- `idr.check.range` (a range of a buffer)

Each takes the value and returns it checked. It is the one `MayCrash` op of
its kind, it carries the crash message, and it folds away when the value is
proved: constant, `IntegerRangeAnalysis`, `ValueBoundsOpInterface`, or a
dominating test. The op that consumes the checked value is total. It is
speculatable only while its operand is the guard's result or a constant
that passes the check: once a path condition has proved a guard away, a
freely speculatable `str.index` would be hoisted above that condition and
read out of bounds (proposal 0002, F-guard-6). There is no `char` guard:
`to_char` is total, and `finite` is the kind that was missing.

This also deletes the `in_bounds` claim (inventory row 8). It is an
inherent property, not a discardable attribute, but one pass sets it and
the lowering trusts it on facts no verifier re-checks:

- a proved guard is gone;
- an unproved guard is still there;
- no attribute can be copied onto an access it does not describe;
- `idr-in-bounds` stops having to run "right before lowering" for
  soundness (read: Passes.td, `idr-in-bounds`, last paragraph). It becomes
  one more folder of the guard.

#### S2.4 Counted types know they are counted

"Holds references" was defined five times (audit row 13). On main it
survives as per-site `counted(Type)` helpers in Ownership/Counting,
Lower/Cells and Layout.

**decision** One function, `idr::holdsReferences(type, symbols, scope)`. A
type interface cannot do it: an unboxed sum answers only through its
declaration, which a type cannot look up (`DataType` holds only a name).
`Layouts::counted`, which says which lowered components are counted
pointers, is a different question and stays.

#### S2.5 No sentinel values in the IR

There are 33 `ub.poison` sites (**measured**). Part of them come from the
`remove-dead-values` patch, which gives an address-taken operand
`ub.poison` (read: PINS.md `remove-dead-values-address-taken`). Part are
C++ code using a poison value to mean "no value".

**decision**:

- C++ that means "no value" says `std::optional`.
- A clone that names itself to keep "callers to come" stays as it is.
  Symbol visibility `nested` was proposed here and does not hold:
  `remove-dead-values` keeps the parameters of a function only when it is
  public or external, or has users outside the pass root (read:
  `mlir/lib/Transforms/RemoveDeadValues.cpp:280-281`, at 7208ba24), and a
  `nested` function of the program's module, the pass root, is none of
  these. The verifier allows one public function, the program's root.

### S3. One object model and one evaluation mode

#### S3.1 The runtime's kinds

Every heap object has the header (count, info) and a kind (read:
`runtime/idris_rt.h`). **decision** The kinds are what the runtime must
tell apart to free an object, and nothing else:

| Kind | Holds | Freed by | Today |
|---|---|---|---|
| box | a constructor's fields, object slots first | the walk over `objs` | as now |
| run | a contiguous run of elements: an array, a buffer, a string's bytes, a contiguous list (`!idr.seq`) | the walk over per-element slots, or none | three kinds today: array, string, plus lists as boxes |
| bignum | GMP limbs | free | as now |
| thunk | a suspended computation: label, then captures or the value | the walk over `objs`; the info word says which | the closure kind, shared with closures |
| task | an LLVM coroutine frame, linear, owned by its shard (`concurrency.md` §3) | its destroy function | new |
| foreign | a Rust value and its drop entry (proposal 0001) | the drop entry, from the walk | new |

**Closures have no kind.** idr-defunctionalize turns every closure of a
program into a sum (read: Lower/Closures.cppm, "the program's own lowering
meets none"). The one consumer of the runtime closure is idr-eval, whose
scratch module is not defunctionalized. **decision**: idr-eval runs
idr-defunctionalize on its closed scratch module before lowering it, and
reify reads a sum constructor's label back as the closure it stands for.
The closure lowering, `Runtime::code`, `emitCode`'s closure half, the
labels in `Layouts` that only closures use, and the runtime's closure
release all go.

**Strings, arrays and lists share one cell.**

- A string keeps its type (`!idr.str` proves immutability, well-formed
  UTF-8 and a scalar count), but its bytes become the run cell, read
  through a memref view. `str.index`, `str.length` on ASCII, `pack` and
  output then become loads and stores upstream passes see (audit §1.1 (a)).
- A list that idr-rc proves exclusive along its spine lives in the same
  cell as `!idr.seq<@T>`, a run viewed from a dynamic offset. That is step
  3 of the lists note, which **measured** at 4cfce76:

  | program | C | before | contiguous |
  |---|---:|---:|---:|
  | fasta | 27.7 ms | 59.1 ms | 29.7 ms |
  | reverse-complement | 7.1 ms | 100.8 ms | 35.8 ms |
  | spectral-norm | 1433 ms | 1775 ms | 1478 ms |
  | k-nucleotide | 336 ms | 5955 ms | 4911 ms |

  The decision is per value, on the MLIR side, recorded in the type as
  `idr.stack` is today. The verifier's rule that every cons onto a seq takes
  an exclusive tail turns a wrong decision into a compile error.

#### S3.2 One evaluation mode

Compile-time evaluation "is runtime evaluation run early" (read:
README.md). It should share the program's lowering, not a mode of it.

The `jit` flag (47 mentions in 10 files) selects five things. **decision**
on where each goes:

| What `jit` selects | Where it goes |
|---|---|
| Cells from the arena, persistent | the runtime's arena mode, which already makes every cell persistent and counting a no-op (read: `idris_rt.h`, `idris_rt_eval_begin`) |
| A crash reported to the evaluator | the runtime's crash entry, which the eval child's runtime state already redirects |
| A tick at function entry and at `idr.may_loop` | a separate pass, `idr-meter`, run on the eval pipeline only, after lowering |
| No `@main` | a separate pass, `idr-entry`, run on the program pipeline only |
| Closures | gone (S3.1) |

`lowerModule(module, jit)` becomes `lowerModule(module)`.

### S4. Constants are flat and static data is immutable

#### S4.1 List spines are flat

A computed list of 10,000 elements is a constant nested 10,000 deep, and
two upstream bugs show only at that depth (read: PINS.md `mlir-recursion`,
`bytecode-deferred-quadratic`).

**decision** A constant of a run of one cons constructor is one attribute:
its elements and its tail, read through one accessor. Eval's transport
table is that flat form already (read: Eval/Reify). The list case of both
pins retires. The reserved compile stack stays for other deep data.

#### S4.2 Nothing static is ever written

A constant suspension is a mutable global that a force writes (read:
Lower/StaticData.cppm, `frozen = !isa<LazyType>`). It is the only static
data that is ever written.

**decision** Its template becomes immutable: the label and its persistent
captures. The first force on a shard writes a per-shard slot. That is
STG's CAF list (`concurrency.md` §2.4). Proposal 0002 corrects this for
its first cut: constant static data can point at the cell, so the cell
stays one per process, written once and marked by its kind, until the
shards work gives it a per-shard home. After it:

- **The persistent invariant is unconditional.** Count 0 means immutable,
  never freed, and pointing only to persistent data (read: `idris_rt.h`, the
  header comment).
- **Any shard may share any persistent cell by pointer** (`concurrency.md`
  §4.3).

### S5. One world, one primitive set, generated mirrors

#### S5.1 The primitive set has one home

ODS is the set; the runtime is the meaning (AGENTS.md). The Idris mirror of
the ops is generated already (read: `compiler/src/IdrisMLIR/Dialect/Idr.idr`,
"Generated by idris-mlir-tblgen"). `Prim` and `IOOp` in Types.idr are its
last hand copy (audit stage 4a). **decision**: Types.idr's `Prim` and `IOOp`
become the generated constructors. What stays in Idris is what only Idris
knows: the registry's map from Idris names to ops.

#### S5.2 Base's foreign surface becomes runtime primitives

Base is a commitment (AGENTS.md). Its file, directory, clock, environment,
argument, errno and terminal functions are `%foreign` definitions with C and
Scheme specs: 62 of them in `System.File.*`, `System.Clock`,
`System.Directory` and `System` (**measured**: grep of `prim__` with a
foreign spec). Today a program that reaches one is rejected as
`%foreign`. At least ten upstream tests fail on it, among them `ReadDir`,
`Time`, `NumProcessors`, `TermSize` and the file tests (read:
`findings/upstream-idris/results`).

The decision on `%foreign` excludes a C calling convention in *user* code
and names the precedent: "a `Data.Buffer` operation is a runtime primitive,
with its one meaning in `runtime/`" (read: `decision-threads-pointers.md`).

**decision** Base's foreign definitions are recognized by name and origin
in the registry, as `Data.Buffer`'s are, and each gets one meaning in
`runtime/` behind `rt.platform`:

- **A `File` is the runtime's small integer.** This is what `AnyPtr`
  already is for the three standard streams (the same decision note), so
  `FilePtr` stays an integer and never becomes an address.
- **The environment goes through base's own code.** Proposal 0002 (owner
  decision O1) made every pointer of base's a runtime handle, so `getEnv`
  reads its string through `prim__getString` of a string handle, as base
  writes it, and no wrapper is recognized by name but `exitWith`.
- **Signal handlers stay out.** A handler runs an effect at a time the
  world does not name, the finalizer's reason. They get their own named
  rule, `unsupported (signal)`, instead of the generic `%foreign` one.
- **Process creation (`system`, `popen`) stays out.** Proposal 0002 (owner
  decision O4) refuses it by name with its own rule, `unsupported
  (process)`, as signals and threads are refused.

#### S5.3 The world is per shard; waiting is an effect

`concurrency.md` §3 and §4 give each shard its own world token and add a
fourth effect bit, `wait`, beside `io`, `crash` and `diverge` (read:
Passes.td, `idr-effects`). Here that means two things:

- the world stays the quantity-1 token with no runtime components;
- the bit is computed like the other three, and only functions that have it
  are lowered as coroutines.

### S6. One parallel substrate, upstream from the loop to the core

Today's array path is upstream from the raising on: `linalg.generic`, the
transform-driven tiling, the upstream vectorizer and int-range narrowing
(read: Passes.td, `idr-vectorize`, `idr-narrow-lanes`).

**decision** Multicore extends it at the same layer:

- **Tiling.** A parallel dimension is tiled to `scf.forall` with the
  transform dialect's `tile_using_forall`, and vectorized inside each tile
  as today.
- **The core grid is upstream's own op.** The grid of cores is
  `shard.grid @cores(shape = ?)`. Its size is a runtime value, as upstream
  allows ("dynamic device assignment... where the exact number of devices
  might not be determined during compile time"; read:
  `mlir/include/mlir/Dialect/Shard/IR/ShardOps.td`, `Shard_GridOp`), and
  `shard.process_linear_index` is the running shard.
- **The lowering is ours.** `scf.forall` becomes a fork per shard and a join,
  through the runtime of `concurrency.md` §4, for a body that holds no
  counted reference: the `counts-nothing` property, already an `idr-expect`
  check. The arrays reach every shard by pointer for the duration of the
  join, since such a body only loads and stores words in its own slice
  (`concurrency.md` §4.12). It does not go through `async-parallel-for`, which builds the async
  runtime's tasks, or through `convert-scf-to-openmp`, which is a second
  runtime.
- **SPMD stays later.** Upstream's SPMD partitioning (`shard-partition`,
  with collectives that `ShardToMPI` lowers) needs tensor programs, and our
  arrays are memrefs from birth, mutated in world order. Pure array
  programs become tensors (`decision-tensors.md`, the user's, 2026-10-09);
  SPMD follows that work.

## 3. The promises, checked

README.md's promise is guaranteed costs: the compiler delivers what the
types promise or rejects the program with a named rule. Four promises are
stated today; two are enforced.

| Promise | Today | **decision** |
|---|---|---|
| Constant stack for every valid program | enforced: `idr-tail-calls`, `constant-stack=@f` | keep |
| No bounds check where the index space proves it | `in-bounds=@f`, through a discardable attribute | the guard of S2.3: a proved check is not there |
| In place: "a quantity-1 value that is matched and rebuilt at the same size will be updated in place with no runtime test, or the program will not compile" (read: README.md, "Why not Lean 4") | not enforced ("the static promise is not") | the check below |
| The heap is acyclic, so counting never leaks (`decision-acyclic-heap.md`) | not enforced: no `cycle` rule exists in `Rule.idr` | the check below |

**The in-place check.**

- **Where:** a module check after idr-rc, which has the `excl` grade and the
  `tests-nothing` and `reuses-in-place` properties. Lorenzen et al.'s FIP
  calculus is the static half (read:
  `sources/papers/lorenzen-2023-fp2`, abstract: "provided their arguments
  are not shared elsewhere"). Marshall et al. are why both halves are
  needed: linearity speaks of the future and uniqueness of the past (read:
  `sources/papers/marshall-2022-linearity-uniqueness`, the comparison of
  the two logics: "'future' refers to outgoing substitutions, while 'past'
  refers to incoming substitutions").
- **What it checks:** for every parameter of quantity 1 that a function
  matches and rebuilds at the same size, every call site must pass an
  `excl` value.
- **The rejection:** a site that passes a shared one is
  `unsupported (uniqueness)`, naming the call and the reference that made
  the value shared.
- **The switch:** behind `--demand-in-place` until the benchmarks pass it.
  Then it is the default, which is what the README promises.

**The cycle check.**

- **What it is:** the decided rule, as the decision states it: the type
  reachability graph after idr-defunctionalize, and a cycle through a
  mutable cell (an array: `IOArray`, `Buffer`, and `IORef`, the array of
  rank 0) is `unsupported (cycle)`, naming the types.
- **Who runs it:** the `idr.program` verifier, so every pass after
  defunctionalization is checked. The frontend cannot run it, because the
  closure sums do not exist before idr-defunctionalize.

## 4. Upstream: newly used, and rejected with the real reason

### Newly used

| Mechanism | For | Replaces |
|---|---|---|
| `makeRegionIsolatedFromAbove`, `outlineSingleBlockRegion` | S1.2 | Idris closure conversion; Emit's lifting of lambda and suspension bodies |
| `inlineRegion` (upstream inliner utilities) | S1.1 | four Lazy.cc patterns; closure specialization for captured constants |
| Memory effects per operand on a resource | S2.1 | `useOf` |
| `IntegerRangeAnalysis`, `ValueBoundsOpInterface` folding guards | S2.3 | the folders' guards; the `in_bounds` attribute |
| `scf.forall`, `transform.structured.tile_using_forall` | S6 | — (new) |
| `shard.grid`, `shard.process_linear_index` | S6, `concurrency.md` §4 | a core count and shard id of our own |
| `llvm.intr.coro.*` and `llvm.call_intrinsic` for `coro.done`/`destroy`/`alloc` | waiting frames (`concurrency.md` §3) | — (new) |
| `createCanonicalizerPass(GreedyRewriteConfig)` with a listener | idr-canonicalize | the copy of canonicalize's options (audit §4.2 #3) |
| `missed` remarks wherever a pass declines | every pass of ours | silence (MLIR survey §1) |
| `composite-fixed-point-pass`, silent at its budget | the simplify loop (since 20fcfadb) | `idr-simplify`'s own loop |

`composite-fixed-point-pass` was rejected here for the simplify loop, for
the measured `sccp` reason in `upstream/02-composite-fixed-point-sccp`.
That patch removes the reason: `sccp` keeps the constants the module
already holds. Since the LLVM pin moved to 7208ba24 (20fcfadb),
`idr-simplify` runs the upstream pass over the round, silent at its
budget, between two passes of ours that open and close a round, and its
fixpoint test is the pass's `OperationFingerPrint`
(`llvm-trunk-mechanisms.md`, "Adopted in the cutover"). A round at the
fixpoint keeps the fingerprint: `remove-dead-values` now keeps a call it
erases no result of as well (§6).

### Rejected, with the reason that holds

**The async dialect.** The earlier notes rejected it because "it is a
pool". That is not the reason. The pool is one library, `AsyncRuntime.cpp`,
reached only through `convert-async-to-llvm`. `async.execute` itself says
"fully sequential execution is a completely legal execution", and its
lowering to `async.runtime.*` and `async.coro.*` is ours to retarget (read:
AsyncOps.td; AsyncToAsyncRuntime.cpp). The reasons that hold:

- **A second reference count.** `!async.token` and `!async.value` are
  multi-await objects with their own counting passes
  (`async-runtime-ref-counting`), beside ours.
- **An error channel the language does not have.** `set_error`, `is_error`,
  and `cf.assert` rewritten into error blocks inside every coroutine.
- **No placement.** `async.execute` has no operand that says where it runs,
  and correctness of `Local` state depends on where.
- **A blocking await outside coroutines.** `async.runtime.await` would
  block a reactor.
- **Little to save.** What remains useful, the coroutine CFG skeleton, is a
  few hundred lines. LLVM's CoroSplit does the hard part either way.

**Ownership-based buffer deallocation.** It frees memrefs by runtime
ownership indicators over static aliasing. Our arrays are shared through
heap cells and counted.

**MPI for collectives.** `ShardToMPI` targets processes and MPI. Our shards
are threads with queues.

## 5. Requirements deleted

Each row is a requirement found in the tree or in the notes, why it is not
real, and what replaces it.

| Requirement | From | Why it is not real | Instead |
|---|---|---|---|
| Lazy needs an LLVM coroutine | `frame.md`, `future.md`, `copies.md` (cb65104) and this note's first draft | A thunk is never suspended mid-body: it has no world, so it cannot wait. A coroutine with no inner suspend is a closure plus a memo. It would add the null test STG's self-updating model exists to avoid (STG §3.1.2), and hide the frame from MLIR until CoroSplit. | An updatable closure with its own kind (`concurrency.md` §2) |
| A coroutine frame cannot carry our header | `frame.md`, `copies.md` | The frontend allocates the frame and passes it to `coro.begin`; the header sits before it. | Header, then frame (`concurrency.md` §3.2) |
| The async dialect is a thread pool | `async-dialect.md`, `future.md`, `scheduler.md` | The pool is one library behind one conversion. | Rejected for the reasons in §4 |
| The memo is what `Lazy` means | every note | Stock Chez runs `Delay` call-by-name: `defaultLaziness` is `(lambda () e)`, and only 0-ary top-level lazy definitions use Scheme `delay` (read: `third_party/Idris2/src/Compiler/Scheme/Common.idr` `defaultLaziness`, `schDef`). | The memo is a complexity guarantee, decided per thunk (`concurrency.md` §2.5) |
| Closure conversion belongs to the frontend | Term.idr, Emit | It is a property of the program's regions, which MLIR computes. | S1.2 |
| The lowering needs an evaluation mode | Lower/* | Every difference but two is the runtime's mode already; the two are passes. | S3.2 |
| A closure needs a runtime form | Lower/Closures, runtime | Only eval holds one, because only eval skips defunctionalization. | S3.1 |
| A proved access is marked, not changed | `idr-in-bounds` | A mark can be dropped or copied; a guard that folds cannot. | S2.3 |
| A plain type means different things by stage | `idr.stage` | The grade can say it. | S2.2 |
| Base's foreign functions are `%foreign` | the profile | The decision excludes user C calls and names the buffer precedent. | S5.2 |
| The reactor waits on io_uring | `cross-shard.md` | io_uring is commonly disabled under container seccomp profiles (recalled); epoll and eventfd are universal. | epoll first (`concurrency.md` §4.8) |
| Standard streams must be asynchronous under a reactor | IX and Seastar rules, applied wholesale | The batch programs this compiler is measured on read standard input in a loop, and making that a wait would colour every one of them. | The standard streams stay blocking on shard 0 (`concurrency.md` §4.7) |
| A Rust future is our coroutine handle | `rust-executor.md` | rustc compiles a future into its own state machine. | A foreign cell polled from our task frame (`concurrency.md` §5.3) |
| Sync Rust enters through `%foreign "rust:"` | proposal 0001 | `%foreign` and `onCollect` were excluded on 2026-10-07. | Generated primitives (`concurrency.md` §5.5) |
| `System.Future` gets a meaning | `future.md` | It is contrib (no commitment), `%foreign`, and a sequential `Lazy` under a parallel name. | Refused by name |
| Workarounds for the two clang module crashes | PINS.md | AGENTS.md now says a pinned upstream's bug is patched, not worked around. | §6, item W1 |

## 6. Cleanup that is not a representation move

These are known issues of the tree that need no design, listed so that the
ordered work in `README.md` carries them:

- **The clang module crash** (PINS
  `clang-module-layout-forward-declaration`): reduce it, then move the pin
  past a fix on main or patch clang in its `upstream/` directory, and
  delete the workaround in `Stack/Escape.cppm`. At 23.1.2 it crashed the
  x86_64 Linux build; the clang of 7208ba24 compiles the report's unit on
  arm64 macOS. Its check now runs on every target and expects the unit to
  compile, so the next build of each target says whether it is gone or
  must be reduced; its README records the plan. The second,
  `clang-module-predeclared-new`, went with the LLVM pin (20fcfadb):
  main's clang compiles its unit, so `Driver/Retarget.cppm` builds its
  feature string as `std::string` again, and the report, its check and
  the workaround are gone.
- **`idr-dead-values`** ran `remove-dead-values` on a copy and kept the
  module when the copy hashed the same: a workaround for upstream
  behaviour, a call rebuilt when nothing is erased. Proposal 0002 deleted
  it. The fix is a report of its own,
  `upstream/16-remove-dead-values-unchanged-call`, not a hunk of
  `remove-dead-values-unreachable`'s patch: its `llvm.patch` makes
  `RewriterBase::eraseOpResults` keep an op it erases no result of, as
  `eraseOperands` returns early on an empty set. The simplify round runs
  upstream's `remove-dead-values{canonicalize=false}` directly.
- **`findings/upstream-idris/`** is the output location of
  `tests/upstream-idris/run` (read: that script, `results=$root/findings/upstream-idris/results`).
  cb65104 deleted its results. This restructure restores the directory from
  cb65104's parent.
- **README.md** still points at `findings/one-representation.md`, which
  cb65104 deleted. It now points at `findings/README.md`.

## 7. What stays, and why

- **The grade as a wrapper type** (98 `unrestricted(` sites). It keeps the
  grade orthogonal to the carrier and the verifier simple (audit §8). A
  helper that names the common pattern is a cleanup, not a move.
- **Box-ness cached in the type**, checked against the declaration. MLIR
  types cannot look up symbols.
- **Facts on `builtin.module` and `func.func` as discardable attributes.**
  Neither op has an inherent slot for them, and every such fact is
  conservative when absent (audit §1.1 (c)). The verifier trigger for
  ownership moves into the grades (S2.2).
- **TT and the dialect as two languages.** Idris's types make distinctions
  the dialect's do not (signedness, `Char`, `Lazy`, Nat-likeness).
- **The semantics.** Nat as a big, the world, Euclidean division and
  well-formed strings are essential complexity. A representation removes
  only its copies.
