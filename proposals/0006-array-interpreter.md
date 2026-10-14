# 0006: the array interpreter

**Status:** proposed (2026-10-12). Nothing here is built. It takes over
three earlier plans: static normalization (the former static-normalization proposal, decided by the
owner on 2026-10-10, whose decisions D1 to D5 stand here word for word),
the frontend's interned names and term arena (0007's O1 and O4), and the
type checker's evaluator (0009's §2.2, T2 and T6). Compile-time
evaluation is already gone: `idr-eval`, its JIT and its forked child left
the C++ side, the runtime's evaluation entries left `runtime/`, and MLIR
threading is on. Work starts once the compiler hosts itself (0001, stage
S); its first stages need nothing else. Claims are marked: *read*,
*measured*, *recalled*, *conjecture*, *decision*.

**The idea.** A dependently typed compiler needs no "comptime" feature: its
type checker already normalizes total code, because deciding whether two
types are equal requires it. Compile-time evaluation, constant folding
and monomorphisation are one operation: **normalize the static part of
the program.** It runs on the type checker's own evaluator. That
evaluator is an array program: the terms are columns of one hash-consed
arena, the machine's states are rows, and each step runs one kernel per
kind of term over all the rows at that kind. Interpretive overhead is
paid per kind and per step, not per element. There is no JIT, no
WebAssembly, no forked child, no bytecode, and no second compiler inside
the first.

## 1. Where it starts from

*Read* (the tree after the cutover): no pass runs program code. A closed
call runs at run time (AGENTS.md), so today:

- a constant table computed from constants is built at startup, every run;
- a choice computed by a recursive closed call (a dictionary, an
  implementation, a shape) is not known when the frontend decides
  instances, so specialization cannot use it;
- conversion checking in the fork compares trees of cells, and its
  evaluator is upstream's, which walks a term per element and caches
  nothing by identity.

This proposal fixes all three with one machine. It is written for the
self-hosted frontend: the interpreter is Idris, compiled by this
compiler, so its kernels get the compiler's loops, vectorization and,
later, fusion and shards. On Chez it would be a slow tree walk, which is
why it waits for stage S.

## 2. The operation: normalize the static part

Three rules decide it. Each already exists in the compiler.

| Rule | Decides | Already exists as |
| --- | --- | --- |
| **totality** | whether normalizing is *safe*: it ends, and covering code cannot fail a match | the totality checker |
| **closedness** (binding time) | *what* is normalized: calls whose arguments are all known | the instance set monomorphisation computes |
| **a cost rule** | whether it is *worth it*: total is not cheap (Ackermann is total) | a counted, deterministic budget |

What happens to a call, by how much of it is static:

- **A closed call of total code** normalizes to a value: a scalar, data,
  an array, or a function. Data becomes a static constant (cells at count
  0; arrays of words as dense constants, 0002 §12); a function becomes a
  specialized function. If the cost rule refuses it, it stays a
  **top-level constant computed once at startup**, at native speed, once
  per shard that demands it (0004 D6). The program's startup *is* the
  compiled tier.
- **A partly static call** specializes only on the arguments that **steer
  control**: types, dictionaries, shapes, and constructors the callee
  matches on. Never on plain data, which would clone a function per
  distinct integer. **Monomorphisation is this rule when the static
  arguments are types.**
- **A call under a binder** (an open term) is never normalized: that is
  supercompilation, and code explodes.
- **Code reaching a world** (IO, or a forged world: `unsafePerformIO`,
  `Linear.Array`'s operations) is stuck and runs at run time.
- **A failing primitive** (a division by zero) makes the call stuck, and
  it runs at run time, where it fails as the program would. With only
  total code and no compiled tier there is nothing to isolate.

## 3. The representation: one arena, as columns

*Decision.* The fork's terms, the frontend's TT and the interpreter's code
are one table, owned here and used by 0007's frontend and 0009's checker.
No pass copies it into a second form.

| Table | Columns | Notes |
| --- | --- | --- |
| names | `id → (offset, len)` into one byte buffer; namespaces are ids | interned once; equality is an id compare |
| terms | `kind : u8`, `a : u32`, `b : u32`, `extra : u32` (a slice of an extra column for variable arity); cached `hash`, loose-bound-variable bound, `has_metas` | hash-consed: one id per distinct subterm, de Bruijn indices |
| values | `kind`, `head`, `env` (a slice of an environment column), `spine` (a slice of a spine column), `unfolded` (a value id or none) | levels, not indices; glued: the head and spine are the cheap form, `unfolded` the unfolded one |
| caches | `term → whnf`, `term → normal form`, `(term, term) → convertible` | indexed by id; a hit costs a gather |

Every id is a type indexed by its table, erased to a word (0007 D1):
`TermId a` cannot index a value table, and `idr-in-bounds` erases the
bounds check it proves. The hash-cons table is open addressing over the
`hash` column (*recalled*: Filliâtre and Conchon's hash-consing, Lean 4's
cached `Expr` data, both under `sources/`).

What falls out: syntactic equality is an integer compare; conversion
normalizes only when ids differ; a normal form is computed once per id;
memory is a few large arrays, one count per region (0008 D4), not
millions of cells. Spans are free: a node names its token.

## 4. The machine: wavefront evaluation

*Decision.* The interpreter evaluates every live machine state at once, as
rows of one table, and advances them one step together.

A state is a row: the term id under evaluation, its environment, and its
continuation (a slice of a frame column). One step is four whole-table
operations:

1. **Group.** A stable counting sort of the rows by the kind of their
   current term: one pass over a `u8` column, one segment per kind.
2. **Run one kernel per kind** over its segment. A variable is a gather
   from the environment column. A lambda builds closure rows. An
   application pushes a frame. A case reads the scrutinee's constructor
   and selects the branch by a gather. A constructor builds a value row.
   A primitive calls the runtime's primitive once over the whole segment
   (§5).
3. **Share.** Rows whose (term, environment) pair is already in the
   cache take the cached value; rows that meet on a closed subterm are
   merged, so the work is done once. Hash-consing is what makes the
   meeting an id compare.
4. **Compact.** Finished rows scatter their values to the rows waiting on
   them and leave the table; new rows from the step are appended.

Why this shape. A per-element lambda, `tabulate n (\i => ...)`, is `n`
rows in one wavefront: each step runs the lambda's next kind once over
`n` rows, so the interpreter's dispatch is paid once per kind per step,
not once per element. It is NESL's flattening done on the interpreter's
rows at run time, where the compiler cannot do it ahead of time
(*recalled*: Blelloch's NESL; Elsman's flattening by expansion is under
`sources/`). Co-dfns showed a whole compiler written as such passes over
node columns (*recalled*: `code/co-dfns`,
`papers/hsu-2019-data-parallel-compiler`). HVM2 advances every redex of an
interaction net in one parallel step (*recalled*). smalltt shows what a
careful glued evaluator buys over Agda, Coq, Lean and Idris (*read*:
`code/smalltt`'s README).

**One row is the plain loop.** A deep sequential recursion keeps one live
row; its step is one kernel over a segment of one, and grouping one row is
one compare. The machine must be as fast there as a direct recursive
evaluator over the same arena; that is the gate of stage A1, and it is a
condition the machine meets, not a choice between two designs.

**Deterministic.** The order of rows is the order of the stable sort and
the order rows were appended; the budget counts steps and bytes per
normalization, never time. A call is normalized or deferred identically
on every machine, thread count and shard count.

**Parallel by construction.** Each kernel is data-parallel over its
segment. Once 0002's arrays exist, the kernels are written in its
vocabulary, so the compiler fuses and vectorizes them (§6); once 0004's
shards exist, a segment splits across shards with the same result.

## 5. Arrays in interpreted code

An array value is one value row whose payload is a runtime array cell.
An array operation in interpreted code is its library definition (0002
§3.5), interpreted like any other code: a `tabulate` of `n` elements
appends `n` rows, one per index, to its body's kind segment, so a wide
array is a wide wavefront, which is the case the machine is built for. No
array operation has a second implementation in the runtime for the
interpreter: the library's definition is the one meaning, and its
primitives' meaning is the runtime's (AGENTS.md), so the interpreter and
the compiled program call the same `runtime/` functions for those
primitives and nothing else. A chain of array operations in interpreted
code is not fused: fusing interpreted code would be a second compiler. A
closed array expression whose cost is past the budget is a startup
constant, computed once by the compiled program (*conjecture* until A4
measures that a wide `tabulate` interprets fast enough).

## 6. The interpreter is 0002's second consumer

The interpreter is written in the typed array style it interprets. Its
tables are 0002 arrays, its kernels are 0002 programs over them, and its
columns take 0008's layouts. When 0002's stage 3 lands, a kernel such as
"gather the environment slot of every variable row, then build the value
rows" is a `map` over a gather, which `linalg-fuse-elementwise-ops` fuses
into one loop with no intermediate array, checked by `idr-expect`'s
`fused`. The compiler that fuses user programs fuses its own evaluator.

Most of a step is not that kind of kernel, and this is said plainly:
the stable group by term kind is a counting scatter, finishing rows is a
compaction, and writing results back is a scatter (0002 §4.4, §11).
Those are where `linalg` is weakest and where fusion stops, as it must at
a size-changing operation. They are ordinary 0002 programs over
`select`, `idr.scatter`, `idr.scan` and `filter`, compiled by the same
lowering, and their cost is measured at A5, not assumed.

## 7. Where it runs

In the frontend, where choices are decided. Translate already
monomorphises on demand with Idris's normalizer doing the type-level
computation (*read*: `compiler/src/IdrisMLIR/Frontend/Translate/`);
static normalization extends that to the value level at the same point,
so a choice computed by recursion reaches the instance decision that
needs it. A closed call needs only its callees, which a module's imports
provide, so normalization runs per module and is cached under the
module's content hash (0005 S1). **The C++ pipeline never runs program
code.**

The type checker uses the same arena, machine and caches for conversion,
unification's evaluation and proofs by reflection (0009 builds tabled
search, shape arithmetic, the rewrite ladder and the kernel on top of
it).

## 8. The interactive loop

The interactive loop moved here from 0002 (§3.9 there). `idris-mlir
repl` runs a line as a program, compiled through the same pipeline and
linked as an executable, in a child. There is no JIT in the driver.
The latency rule (1 s from line to output for an expression over arrays
of up to 10⁶ elements) decides whether a
resident frontend is built, not how the line is run (D4). That is running
a program, not normalizing one, and it stays out of compilation.

## 9. Rules changed

When A3 lands, in the same change:

- AGENTS.md's paragraph on primitives becomes: "No primitive has an
  implementation in Idris: its one meaning is the runtime's (`runtime/`),
  which folders and the evaluator call too. The compiler has no
  compile-time evaluation feature: it normalizes the static part of the
  program with the type checker's evaluator. Closed calls of total code
  become values within a counted budget, or startup constants beyond it;
  partly static calls specialize on the arguments that steer control;
  partial and covering code is never normalized."
- AGENTS.md's middle way: "which static normalization, specialization,
  closed sums and defunctionalization compile away".
- README.md: the frontend "normalizes the static part"; no JIT.
- `tests/README.md`: every program test runs with and without static
  normalization (D5), the matrix the deleted pass once had.

## 10. Staged plan

Each stage passes AGENTS.md's checks on both targets and records compile
times against the stage before. A stage that makes the self-compile slower
is not taken until it is not.

| Stage | Content | Proof |
| --- | --- | --- |
| A0 | interned names and the hash-consed term arena in the fork, typed ids; the frontend reads TT from it | identical TTCs and corpus; elaboration of base and the frontend ≥ 1.5× faster than 0009's T0 record |
| A1 | the wavefront machine on the arena, weak head normal form only; a direct recursive evaluator on the same arena as the measuring stick, deleted after | **the gate:** on the checker's own normalizations (base, the frontend, smalltt's benchmark set) the machine is within the run-to-run spread of the direct evaluator where one row is live, and faster where many are (a `tabulate` corpus); the machine is fixed until both hold |
| A2 | glued values, the caches, approximate conversion; the fork's checker on the machine | smalltt's benchmark set within 1.5× of smalltt; ≥ 2× over A0 on conversion-heavy files |
| A3 | static normalization in the frontend: closed total calls to values, control-steering specialization, the counted budget, startup constants beyond it; §9's rules | `tests/programs/eval` and the corpus unchanged; D5's matrix green; byte-identical across thread counts |
| A4 | arrays in interpreted code as wide wavefronts (§5), after 0002's stage 1 | a table of 10⁶ words built by array operations normalizes within the budget; reflection benchmarks ≥ 10× over A2 where they use arrays |
| A5 | the kernels as 0002 programs, after its stage 3 | `fused` holds on every kernel; wide-wavefront benchmarks faster than A4 |
| A6 | segments across shards, after 0004's P4 | identical results at every shard count; wall time on the A1 corpus recorded |

## 11. Rejected alternatives

- **A JIT or native compilation of reductions** (the deleted `idr-eval`;
  Coq's `native_compute`): a second compiler inside the first, and a fork
  to contain it.
- **WebAssembly**: a second lowering pipeline plus an embedded engine.
- **A bytecode virtual machine**: a second representation of code beside
  the arena, which drifts from it. The arena is the code.
- **A tree-walking interpreter as the design**: it pays dispatch per
  element and cannot use the vocabulary's primitives across rows. It
  exists only as A1's measuring stick.
- **Fusing interpreted array chains**: a compiler inside the interpreter.
  Expensive chains are startup constants.
- **Eager evaluation of every closed call, partial included**: needs a
  divergence budget and gives schedule-sensitive refusals.
- **A `comptime` keyword or staging annotations**: the types already say
  what is static; the totality checker already says what is safe.
- **Specializing on every constant argument**: one clone per distinct
  value; only control-steering arguments specialize.
- **Normalizing open terms**: supercompilation's code explosion.

## 12. Decisions

- D1 (owner). Only total code is normalized at compile time; partial and
  covering code never is.
- D2. No compile-time evaluation feature: the compiler normalizes the
  static part of the program, and monomorphisation is the case where the
  static arguments are types.
- D3. One evaluator, the type checker's interpreter, with array
  operations interpreted as their library definitions, a wide array a
  wide wavefront; no whole-array runtime primitive, no JIT, no
  WebAssembly, no compiled tier. Too expensive means a startup
  constant.
- D4. The interactive loop runs lines as linked executables, outside
  compilation. There is no JIT in the driver.
- D5. Every program test runs with and without static normalization.
- D6. The interpreter is an array program: the wavefront machine over the
  hash-consed arena, one kernel per kind per step. A1's gate is a
  condition it meets, not a fallback.
- D7. One arena, owned here: the fork's elaborator, the checker, the
  frontend and the normalizer read it and never copy it.
- D8. The budget counts steps and bytes; nothing the machine decides
  depends on time, threads or shards.
