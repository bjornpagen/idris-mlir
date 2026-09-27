# Refactor and memory: where shape specialization stops, and what comes next

Research note. Nothing here was built or run; it reads the code at
`c3eb8a2` and the papers cited. Sources marked *local* are stored under
`docs/research/papers/`; the others are cited from the literature and were
not re-read for this note.

## 1. Where we are, and where it stops

The compiler has one representation strategy. `Simplify` is a two-level
evaluator (Kovács, *local*: `kovacs-2022-staged`): every value is either a
runtime scalar atom (`Dyn`) or a static value (`SVal`) whose *shape* is known
at compile time. A function is specialized per shape
(`Key = fn + shapes + elims`), and data with a known shape is flattened
into scalars. That is why the benchmarks beat MLton: there is no boxing, no
closure, no tag test and no allocation left to pay for.

It is also exactly where it stops. Monomorphising *types* is not the
problem: MLton does that and still runs anything. We specialize on
*shapes*, and we have **no runtime representation for a value whose shape
is decided at runtime**. Every failure we hit is that one case:

| Program | Why the shape is dynamic | Today |
| --- | --- | --- |
| `line <- getLine` | the bytes come from input | no primitive at all |
| `words line`, `unpack s`, `filter p xs` | a list's length depends on runtime data | `PROF-DATA-3` |
| `if b then (+ 1) else (* 2)` kept in data | which closure it is depends on runtime data | `PROF-HEAP-1` |
| a string built in a loop | its length depends on runtime data | `PROF-HEAP-3` |
| n-body over `Vect 3 Double` | the shape is fixed but crosses a runtime join (the loop's result) | `PROF-DATA-3` |

The last row is different from the others. There the shape *is* static; we
only lack a way to return a static value from runtime control flow. The
first four genuinely need a runtime representation.

So the next step is not more specialization. We need a **second
representation**, chosen per value by binding time:

- **static** (what we have): the shape is known, so the value is flattened
  into scalars and code is specialized on it;
- **dynamic** (new): the shape is known only at runtime, so the value is
  boxed, meaning a tagged cell in memory. Closures become tagged cells too,
  by defunctionalization (Reynolds; Danvy and Nielsen, *local*).

MLton uses the dynamic representation everywhere and a heap to hold it. We
keep the static representation wherever it applies, and replace the heap
with memory whose lifetime we can prove (section 4).

The refactor below should come first. Two representations on top of
today's `Simplify` would double its special cases.

## 2. What the code is today

`Simplify` (953 lines), `Simplify/Gen` (306 lines) and `Simplify/Value`
(357 lines) make one decision at every call: **unfold, specialize, defer,
or evaluate to a constant**. Today that decision is made by a stack of
local rules, each added to fix one program:

- **Three recursion bounds** in `unfoldOnce`:
  - 1 by default;
  - 64 when an argument holds a string join point or the result is a
    static `IORes`;
  - 10000 for `Integer` results, recursive-data results, and calls with a
    known constructor of recursive data among their arguments.
- **A separate fuel of 20000**, for compile-time evaluation (`ELIM-G-16`).
- **Four ways to force a deferred call to its value**, each with its own
  cap:
  - `known` and `knownData`: evaluate if every argument is constant;
  - `force`: unfold until a constructor appears, at most 1000 times;
  - `once`: unfold an action's run, at most 64 times.
- **Two ways to specialize on literals**:
  - `ELIM-G-17`: retry with literal keys after a failure;
  - `ELIM-G-18`: call-pattern specialization, at most 4 per function.
- **Growth backstops**: homeomorphic embedding (`PROF-HEAP-4`), plus at
  most 256 specializations per function and a key size of at most 4096.
- **Predicates on the result type**: `chooses`, `staticRun`, `value`, and
  `== BigT`. `recursiveArg`, `interesting` and `joinIn` then pick among
  the options above.
- **Special cases in the matchers**:
  - `matchCon` on a deferred call: a separate path for single-constructor
    data, and another when the constructor carries a world;
  - `matchCon` on a runtime value: a path for "one constructor whose
    alternative returns a static value";
  - string join points (`SCase`), a special form that only strings get.
- **`Value`**: about 150 lines of hand-written `rank`/`cmp`/`couple`/
  `pairs`/`children`/`size`, and a separate `SStr` type with its own
  traversals and comparisons.

Every one of these answers one of three questions, each case by case:

1. **Must this call run now?** Yes when its result or an argument is
   static, because such a value cannot exist at runtime.
2. **Will running it terminate?** Answered today by the bounds, the fuel
   and the caps.
3. **What does a static value become when it meets a runtime choice?**
   Answered by string join points, the single-constructor `IORes` case,
   and rejections.

The refactor answers each question once.

## 3. The refactor: one driver, one whistle, one join

### R1. Values as a functor, with generic zipping

- Make the base functor of `SVal` explicit, `SValF r a`: `r` is the
  recursive positions, `a` the atoms.
- Give it `zipMatch : SValF r a -> SValF r b -> Maybe (SValF (r, r) (a, b))`,
  the "generic unification via two-level types" of Sheard (ICFP 2001), as in
  the `unification-fd` library.
- Derive everything else from `Traversable`, `cata` and `zipMatch`:
  - equality and order;
  - `atoms`, `refill` and `shape` (all are already traversals);
  - `size` and `children` (both are folds);
  - homeomorphic embedding: coupling is `zipMatch` with embedding on the
    children, and diving is `any` over `children`;
  - **most specific generalization** (anti-unification, needed by R3):
    `zipMatch` where it succeeds, and a fresh variable where it fails.
- This replaces the hand-written comparison and coupling code in
  `Value.idr`, and gives R3 its two operations for free.

### R2. Strings are static data

- `SStr` is a free structure over pieces: literal, runtime string,
  character, shown number, append.
- Make it a built-in static data type whose constructors are those pieces.
  A string value is then an ordinary `SCon` tree, and:
  - output fusion (`ELIM-G-7`) becomes one fold over that tree;
  - `nonEmpty` and `headOf` (`ELIM-G-15`) become two small algebras;
  - `traverseS`, `cmpS`, `rankS`, `showS` and `SString` go away.
- `SCase` then disappears in favour of R4.

### R3. Driving with one termination rule: a whistle plus generalization

This is positive supercompilation (Sørensen, Glück and Jones, JFP 1996,
*local*), with termination by homeomorphic embedding (Leuschel, SAS 1998)
and generalization by most specific generalization. The staging boundary
comes from 2LTT (Kovács, *local*): a computation-type value must be
eliminated at compile time. Three rules.

**Drive.** A call is unfolded when it carries static information. That
means some argument is not a plain runtime atom, or its result after the
applied eliminations is a static type. It is also unfolded when it is an
Idris case or with block, or a library `%inline`. A call with only runtime
atoms and a value-type result is residualized. There is nothing to
specialize on, so it becomes an ordinary call of the function's generic
instance, and MLIR's inliner decides the rest.

**Whistle.** The *configuration* of a call is its function plus its
arguments' shapes, *including literal atoms*. The unfolding path keeps the
configurations of the calls being unfolded. If an ancestor's configuration
with the same function embeds in the current one, driving stops.
- Literals are compared by a well-quasi-order: equal characters and
  strings, `|a| ≤ |b|` for integers, and subsequence (Higman) for literal
  strings.
- Kruskal's theorem guarantees that every unfolding path is finite.

**Generalize.** When the whistle blows, take the most specific
generalization of the two configurations. Equal literals stay; unequal
ones become runtime atoms. Then specialize on it, memoized by the
generalized configuration: that is folding, today's `memo`. If the
generalization would have to turn a static value into a runtime one that
cannot exist at runtime (a growing closure, a join point, an `Integer`),
that is today's `PROF-HEAP-4` or `PROF-TYPE-4` error, now reported from
one place.

**Budget.** One global budget of unfoldings per top-level residual function
bounds compile time. It is not a termination argument. When it runs out,
the whistle is treated as having blown.

What it subsumes:

| Today | Under R3 |
| --- | --- |
| bounds 1, 64 and 10000, `recursiveArg`, `staticRun`, `chooses`, `unfolding` counts | the whistle |
| `ELIM-G-16` (evaluate constant calls), `known`, `knownData`, `evaluate`, `abandon`, `attempt` | constant calls just drive to a literal. A path that does not finish generalizes instead of rolling back. |
| `force`, `once`, the `SCall` special cases in `matchCon` | driving a deferred call is driving |
| `ELIM-G-17` and `ELIM-G-18` (literal specialization, the budget of 4) | the generalization keeps equal literals. `ack 3 n` gives `ack[3]`, `ack[2]`, `ack[1]` because each recursive call repeats its own `m`; `go 0 n → go 1 n` generalizes to `go(_, _)`. |
| `PROF-HEAP-4` growth check, 256 per function, key size 4096 | a generalization that cannot be residualized |
| `interesting`, `constants`, `callPattern`, `matchedParams` | the drive rule |

**Known trade-offs, to measure rather than assume.**
- *Downward generalization.* Generalizing the current call, not the
  ancestor, peels one iteration of a loop that starts from a literal.
  Upward generalization re-drives from the ancestor and avoids the peel,
  at the cost of a rollback, which `Gen` supports cheaply.
- *Compile time.* A constant program with deep recursion (`fib 38`) is
  capped by the budget.
- *Coverage.* Every benchmark and every fixture must produce the same
  output and the same or better code, so R3 needs a before/after
  comparison of code size and benchmark times.

### R4. Join points for static values

A residual match whose alternatives yield static values produces a single
new static value: `SJoin` holds the scrutinee, and for each alternative its
binders, its code prefix and its static value. These are join points
(Maurer, Downen, Ariola and Peyton Jones, "Compiling without
continuations", PLDI 2017). Consuming an `SJoin` does one of two things:

- **Case-of-case.** The consumer is pushed into each alternative. This is
  what string join points do for `putStr` today, now for any static value.
  It is bounded by the whistle.
- **Constructed product result.** If the alternatives' shapes have a
  common generalization in which only atoms differ, the match returns
  those atoms and the value is rebuilt after it. This is CPR (Baker-Finch,
  Glynn and Peyton Jones, JFP 2004), with the shapes computed by R1's
  generalization.

A specialization whose result is static uses the same rule. Its result
shape is the generalization of its alternatives' shapes, computed as a
fixpoint over the recursion (start from the non-recursive alternatives and
iterate). This is the part missing from the overnight attempt, which
looped because it guessed the shape instead of computing the fixpoint.

What it subsumes:
- `SCase` and string join points (`ELIM-G-14`);
- `joinIn`, `needsJoin`, `reifiable`;
- the single-constructor `IORes` special case;
- the n-body-over-`Vect` rejection, the last row of the table in section 1.

### R5. The frontend

`Translate.idr` (1381 lines) should split along what it does:

| Module | Contents |
| --- | --- |
| `Frontend/Data` | `dataInstance`, `typeParams`, `eraseIndices`, `paramLayout` |
| `Frontend/Instances` | `request`, `classify` |
| `Frontend/Terms` | `term`, `application` |
| `Frontend/Trees` | case trees |

One clean-up is conceptual. Whether an argument is a compile-time value is
decided today by three overlapping predicates: `isAuto`, a `dictionary`
flag set when the argument is a static local, and `interfaceType`. It should
be decided once, from the parameter's type: a type-like type or an
interface type makes a compile-time parameter. `ArgValue` then shrinks, and
`isImplementation` and the `dictionary` flag go away.

`VarInfo`'s `TypeValue` and `Static` both hold closed terms, and differ only
in whether they are normalised or kept as written. They should become one
constructor carrying that choice.

### R6. Smaller consolidations

- `needsV1`, `needsV2` and `needsV3` in `Code.idr` become one algebra that
  returns the set of features a program uses; the contract version is the
  maximum over that set.
- The rule identifiers `ELIM-G-10` to `ELIM-G-18` collapse into three:
  - **drive**: `ELIM-G-10`, `ELIM-G-11`, `ELIM-G-12`, `ELIM-G-13`,
    `ELIM-G-16`;
  - **whistle and generalization**: `ELIM-G-17`, `ELIM-G-18`, and
    `PROF-HEAP-4`'s check;
  - **join**: `ELIM-G-14`.
- `ELIM-G-15` becomes two string algebras.
- The spec (06) is rewritten to match. Changing 02, 03 or 08 needs the
  user's approval (`AG-NEVER-1`).

### Expected size

This is an estimate, to be checked against the diff:

- `Simplify.idr`: from about 950 to about 600 lines;
- `Value.idr`: about 150 fewer lines;
- `Gen.idr`: `St` goes from 16 fields to about 10.

Nothing changes in C++.

### Order, each step behaviour-preserving and green

Each step is a separate commit, with the same fixtures passing and the
benchmark table unchanged or better:

1. R1, since R3 and R4 need `zipMatch` and generalization.
2. R2.
3. R3: the largest step, measured before and after.
4. R4: this is where the `Vect` n-body starts to compile.
5. R5 and R6.

## 4. Memory: making dynamic values possible without a GC

### What MLIR and LLVM already give us

This was checked in the pinned tree (`.toolchain/llvm-project/mlir`).

- **Calls make frames.** A `func.call` lowers to an LLVM call, and LLVM lays
  out the frame, allocating registers and spilling. Stack allocation is a
  separate mechanism *inside* a frame:
  - `memref.alloca` or `llvm.alloca` reserve frame memory, of static or
    dynamic size, freed when the function returns;
  - `memref.alloca_scope` frees the allocas made inside its region when the
    region ends. It lowers to `llvm.intr.stacksave` and
    `llvm.intr.stackrestore`, which is how a loop iteration can free what
    it allocated;
  - `promote-buffers-to-stack` turns small `memref.alloc`s that do not
    escape into allocas.
- **What none of these do** is let a callee return memory of runtime size
  to its caller. A callee's allocas die when it returns. That, and knowing
  when data is dead, is the whole problem. Allocation itself is easy.

### What we build

**A region stack**, called the secondary stack in Ada/GNAT.
- It is a static `.bss` arena with a bump pointer: a few globals and a
  handful of MLIR helpers in `Runtime.mlir.inc`, next to the I/O buffers.
- A callee may allocate on it and return the result to its caller.
- Memory is freed only by *releasing to a mark*, which is LIFO.
- It needs no new symbol, so `TEST-HEAP-1` stays as it is: `write`,
  `read`, `_exit` and libm. Overflow is a crash with a message, like a
  stack overflow.
- It is OCaml's local-allocation design with `exclave_` (Lorenzen et al.,
  "Oxidizing OCaml with modal memory management", ICFP 2024) and GNAT's
  secondary stack. The general theory is Tofte and Talpin's regions (1997),
  restricted to regions that nest with the program's loops.

**Regions are loop iterations.**
- After `Simplify`, a loop is a self tail call, and `idr-tail-loops` turns
  it into an `scf.while`. The region of an iteration is everything
  allocated from the loop head to the back edge.
- At the back edge, the loop releases to the iteration's mark, **if** no
  loop-carried argument holds a dynamic value.
- Functions never release: their allocations belong to the enclosing
  iteration, so returning a dynamic value is free.
- The proof is a liveness check on first-order `Code`: at each back edge,
  no dynamic value is live except in the loop-carried atoms. It is simple
  because `Simplify` already removed every closure and every unknown call,
  so there are no aliases hidden behind higher-order code.

**What happens when a loop does carry dynamic data:**
- In a *total* loop (Idris's `terminating` flag, which each `CFn` already
  carries), the loop does not release. Its allocations accumulate until the
  enclosing loop releases, and the loop's termination bounds them. This is
  how `reverse`, `foldl` with a list accumulator, and Prelude's `words`
  work.
- In a partial loop (a REPL's `main`), this is rejected with a new
  `PROF-REG` rule, because memory could grow without bound. Section 4.3
  lifts this later.

**Representation.**
- `!idr.str` is already a (pointer, length) pair; a runtime string's bytes
  live in the region.
- Dynamic recursive data (`List Char`, `List String`, a tree) gets a boxed
  type `!idr.box<@T>`, a pointer to a region cell holding the tag and
  fields in today's flattened layout (`LOW-DATA-1`).
- A runtime-chosen closure is defunctionalized into a boxed sum with one
  constructor per label, holding the captured atoms. `Label` already names
  each lambda.

### 4.1 Where multiplicity comes in

The first subset needs no multiplicity. Liveness at back edges is enough
to prove that a loop iteration's memory can be dropped. Quantities become
essential for the next step: a loop that **carries** dynamic state without
growing, such as a REPL keeping a history, or a buffer reused every
iteration.

- **Quantity 0**: erased already, so none of it is allocated (`SEM-IDX-1`
  extends this to indices).
- **Quantity 1** does not mean the value is unique. `AGENTS.md` says so,
  and Marshall, Vollmer and Orchard (ESOP 2022, *local*) explain why: a
  linear binder constrains the callee, not the aliases the caller may hold.
  Two things give uniqueness:
  - *by construction*: a scoped, linear API in the style of Linear Haskell
    (Bernardy et al., POPL 2018, *local*):
    `withBuffer : (n : Nat) -> ((1 b : Buffer) -> IO (Res a (const Buffer))) -> IO a`.
    The only way to get a `Buffer` is linearly from `withBuffer`, so it is
    never shared;
  - *by analysis*, on first-order `Code`: a value is unique if it was just
    allocated and every path uses it at most once. `Code.uses` already
    computes exactly this for the world (`CORE-INV-9`).
- A unique loop-carried value can be **updated in place**, or **moved down
  to the loop's mark** at the back edge (a copy of the live data only, and
  none at all when it is already at the top). Loops can then carry dynamic
  state in bounded memory. This is the reuse of Perceus (Reinking et al.,
  PLDI 2021), of Lean's "Counting Immutable Beans" (*local*) and of FP²
  (Lorenzen, Leijen and Swierstra, ICFP 2023), without reference counts,
  because uniqueness is proved statically.

### 4.2 The CLI program as the target

```idris
main : IO ()
main = do
  line <- getLine
  case words line of
    ["fib", n]   => printLn (fib (cast n)) >> main
    ["nbody", n] => printLn (energy (run (cast n) (offset initial))) >> main
    ["quit"]     => pure ()
    []           => pure ()                      -- end of input
    _            => putStrLn "usage: fib N | nbody N | quit" >> main
```

What it needs:
- **I/O**: `getLine`, a new `idr.io.get_line` that reads into the region.
- **Runtime string primitives**: comparison (for the literal matches), the
  `cast`s from `String` to `Int` and `Double`, `length`, `strHead`,
  `strTail`, `strIndex`, `substr`, `++` and `strCons`. They allocate in the
  region, so `PROF-PRIM-4` and `PROF-HEAP-3` narrow.
- **Boxed runtime lists**, for Prelude's `unpack`, `pack` and `words`.
- **The region rule**: `main` loops forever and carries nothing dynamic, so
  it releases every iteration and runs in constant memory.
- **Unchanged work**: `fib` and `nbody` themselves are still specialized
  and flattened, so the benchmarks keep their current speed. Only the
  input handling becomes dynamic.

### 4.3 Milestones, each a profile version

- **M1**: runtime strings from input.
  - `getLine`, the region stack, and runtime string primitives;
  - regions per loop iteration, and `PROF-REG-1` (no dynamic value carried
    by a partial loop);
  - no boxed data yet.
  - It already allows line-oriented input: read a number per line, or
    compare a command word against literals.
- **M2**: boxed dynamic data.
  - `!idr.box`, and constructors of recursive data allocated in the region
    when their choice is dynamic;
  - defunctionalized closures when a closure's choice is dynamic;
  - Prelude's `words`, `lines`, `unpack` and `pack`;
  - the CLI above compiles.
- **M3**: uniqueness.
  - uniqueness analysis on `Code`, in-place update, and moving live data
    down at the back edge;
  - a linear `Buffer`/`Array` API;
  - loops that carry dynamic state in bounded memory.
- **M4**: the native stack as an optimization.
  - When a region's allocations and uses stay inside one function, use
    `memref.alloca_scope` instead of the region stack. This is escape
    analysis in the style of `promote-buffers-to-stack`.

## 5. Proposed sequence

1. The refactor, R1 to R6, which changes no behaviour. It makes M1 and M2
   additions to one driver instead of new special cases.
2. Write M1 in the spec: 02 (a new `PROF-REG` group), 03 (region
   semantics), 08 (`idr.io.get_line`, region mark and release), 10
   (lowering). This needs the user's approval, because 02, 03 and 08 are
   contract documents.
3. M1, then M2 with the CLI program as its end-to-end test, then M3.

## 6. Questions for the user

- **Generalization direction** (R3): peel one loop iteration (downward), or
  re-drive from the ancestor (upward, no peel, a little more compile time)?
  I lean upward, since `Gen` already rolls back cheaply.
- **Region stack size**: fixed at link time (for example 64 MiB of
  `.bss`), or set by a flag?
- **Rejection in M1**: is rejecting a partial loop that carries dynamic
  data acceptable until M3?
- **Linear API**: for M3, should the linear `Buffer`/`Array` API live in
  `IdrisMLIR.IO` (our library), or should we aim at Idris's own
  `Data.Linear` modules from `base` and `contrib`?
