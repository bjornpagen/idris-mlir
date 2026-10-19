<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0011: the array interpreter

**Status:** proposed 2026-10-12, decided 2026-10-14, audited against the
tree 2026-10-15. Nothing is built (*read*: no term arena, hash-consing,
wavefront machine or `repl` in `compiler/src`, `compiler/idris/src` or
`foreign/idr`). Every stage is **AFTER-SELF**: self-hosting (`make self`,
`tools/self.sh`) needs none of it, and A0 needs `make self` done, since its
bars are ratios to 0014's T0, recorded there. After A0: A1 needs A0, A2
A1, A3 A2 and §13's second question, A4 A3 and §13's third, A5 0010's
stage 7 (D45's plain-Idris layer, after its stage 5's ops), A6 0008's P4,
A7 A0. Nothing up to A3 needs sharding; its place after sharding is the
queue's order (proposals/README.md), not a dependency. All of it is Idris
in the fork and the frontend, so it builds and runs under the stock Idris
on Chez and under idris-mlir, always (AGENTS.md's two hosts, as 0002 R3
and 0010 D45 apply them): the arena and the machine are plain Idris over
base and, for array operations, over 0010 D45's plain-Idris layer, which
idris-mlir lowers through the registry's `Faster` hooks; they never reach
a `libs/` `%extern`. "The cutover" is the pipeline cutover, its last text
at 484d6403 (`proposals/0006-compile-time/README.md`).

It owns three earlier plans: static normalization (the owner's decisions
of 2026-10-10, D1 to D5), the frontend's interned names and term arena
(once 0012's O4), and the type checker's evaluator (once 0014's §2.2, T1,
T2 and T6). Claims are marked *read*, *measured*, *recalled*,
*conjecture* or *decision*.

**The idea.** A dependently typed compiler needs no "comptime" feature: its
type checker already normalizes total code, because deciding whether two
types are equal requires it. Compile-time evaluation, constant folding and
monomorphisation are one operation: **normalize the static part of the
program**, on the type checker's own evaluator. That evaluator is an array
program: terms are columns of one hash-consed arena, machine states are
rows, and each step runs one kernel per kind of term over all the rows at
that kind, so interpretive overhead is paid per kind and per step, not per
element. No JIT, no WebAssembly, no forked child, no bytecode, no second
compiler inside the first.

## 1. Where it starts from

*Read*, 2026-10-15:

- No pass runs program code; a closed call runs at run time (AGENTS.md).
  `tests/programs/eval/compile-time-evaluation/Main.idr` holds closed calls
  (`fib 15`, `fib 27`) beside the same functions on a digit read from
  input, against one expected file, and
  `tests/partial-divergent-call` holds that a closed call
  of a partial function stays a call. A constant table computed from
  constants is computed by the program, every run.
- The frontend normalizes only compile-time values (types and
  implementations), on the fork's normaliser behind `host`
  (`compiler/idris/src/Idris/Host.idr`, moved into the fork by 0002's lane
  I): `normaliseClosed` and `normalisedBy` in
  `compiler/src/IdrisMLIR/Frontend/Translate/Closed.idr`, read by
  `classify` in `Translate/Instances.idr`. A choice computed by a
  recursive closed call over values is not known when instances are
  decided, so monomorphisation cannot use it.
- The fork's evaluator is call by name with no update: a closure is
  evaluated again at each use (`evalClosure`,
  `compiler/idris/src/Core/Normalise/Eval.idr`); a `Glued` pair rebuilds
  its normal form at each `getNF` (`gnf` stores a function, not a result);
  `Convert Term` (`Core/Normalise/Convert.idr`) normalizes both sides
  before comparing heads; nothing is cached. Idris 2 was the slowest
  system on smalltt's elaboration benchmarks, stlc10k in 129.6 s against
  smalltt's 0.306 s (*measured* there in 2021,
  `sources/notes/type-checking/elaborators.md` §10). It applies a
  primitive through base's (`Core/Primitives.idr`) for conversion only:
  since upstream/18 no such result reaches a checked term.

The machine's speed is the native frontend's (stages 1 to 3 of `make
self`), where idris-mlir compiles its kernels; under the stock host it is
a slower tree walk, which must build and run and need not be fast
(AGENTS.md: nothing is shaped so that Chez can run it).

## 2. The operation: normalize the static part

| Rule | Decides | Already exists as |
| --- | --- | --- |
| **totality** | whether normalizing is *safe*: it ends, and covering code cannot fail a match | the totality checker |
| **closedness** (binding time) | *what* is normalized: calls whose arguments are all known | the instance set monomorphisation computes |
| **a cost rule** | whether it is *worth it*: total is not cheap (Ackermann is total) | a counted, deterministic budget, a named constant in `tools/policies.txt` (D13) |

What happens to a call, by how much of it is static (*decision*):

- **Closed, total, finished within the budget:** a value, written as a
  constant the C++ side holds. Data is an `#idr.con` in an `idr.constant`
  (`Idr_ConAttr`, `Idr_ConstantOp`, `foreign/idr/include/idr/IR/`),
  lowered to static cells at the persistent count 0
  (`foreign/idr/lib/Conversion/StaticData.cpp`; `runtime/idris_rt.h`). A
  closed array result follows D18. A function is an `#idr.closure`
  (`Idr_ClosureAttr`) naming an `idr.func` named from content, which
  defunctionalization treats as any closure constant.
- **Closed, total, past the budget:** a top-level constant, one static
  memo cell forced at its first demand and never again, at native speed:
  Emit's shared arity-0 cell for a lazy constant (`shared` in
  `compiler/src/IdrisMLIR/Emit/Declarations.idr`), released at exit
  (`idris_rt_caf_release`), under shards the memo sum's `Static i` (0008
  §6, D6). First demand, never startup: a failing primitive may be inside
  it, and it must fail where the program demands the value (D3). A3
  bounds what such cells retain (§10).
- **Partly static:** specialized only on the arguments that steer
  control, never on plain data (D9). The frontend keys an instance on
  what decides types and representations (types, implementations, a
  runtime argument's shape where the callee's type reduces on it, as
  `Translate/Instances.idr` does today), and static normalization extends
  that to such values computed by a closed call; monomorphisation is this
  rule when the static arguments are types. The ready set specializes on
  a known constructor of a sum, closures and `Extents` included (the
  cutover's §4.8; 0010 §4.3).
- **Under a binder** (an open term): never normalized; that is
  supercompilation, and code explodes.
- **Stuck:** a step that reaches a world (IO, `unsafePerformIO`, a linear
  array's operations), a primitive or a bodiless `%extern` the
  interpreter gives no meaning (§13, questions 2 and 3), or a failing
  primitive (a division by zero). The call runs at run time, where it
  fails as the program would. The totality checker keeps most failing
  primitives out already: one that can fail is not covering, so the fork
  refuses `prim__div_Double` in a definition not marked `partial`
  (`upstream/18-elaboration-primitive-folding/README.md`).

## 3. The representation: one arena, as columns

*Decision* (D7). The fork's terms, the frontend's TT and the interpreter's
code are one table, owned here and read by 0012's frontend and 0014's
checker; no pass copies it into a second form. It is plain Idris over
base (the fork's tables are base's `Data.IOArray` today,
`compiler/idris/src/Libraries/Data/Table.idr`), linear where that helps.

| Table | Columns | Notes |
| --- | --- | --- |
| names | `id → (offset, len)` into one byte buffer; namespaces are ids | interned once; equality is an id compare |
| terms | `kind : u8`, `a : u32`, `b : u32`, `extra : u32` (a slice of an extra column for variable arity, decoded by `kind`); cached `hash`, loose-bound-variable range, `has_metas` | hash-consed: one id per distinct subterm, de Bruijn indices, no source spans |
| values | `kind`, `head`, `env` (a slice of an environment column), `spine` (a slice of a spine column), `unfolded` (a value id or none) | levels, not indices; glued: head and spine the cheap form, `unfolded` the unfolded one; never hash-consed |
| caches | `closed term → whnf`, `closed term → normal form`, `(term, term) → convertible` as success and failure sets, and a transient set for terms with metas | indexed by id; a hit costs a gather |

- **Typed ids** (0012 D1): every id is a type indexed by its table, erased
  to a word, so a `TermId` cannot index the value table, and a read
  through one is an `index` with no guard (0010 D4, §3.2).
- **The hash-cons table** is open addressing over the stored `hash`
  column, so a resize never rehashes (Filliâtre and Conchon,
  `sources/code/ocaml-hashcons/hashcons.ml`, read through
  `sources/notes/flattened-data/columnar.md` §6); the cached hash, flags
  and range per node are Lean 4's kernel's
  (`sources/code/lean4/src/kernel/expr.h`), and nanoda interns every
  expression as a 32-bit index (`sources/code/nanoda_lib/src/util.rs`).
- **The `hash` column** (D16) is the frontend's one content hash,
  XXH3-128 in plain Idris over `Bits64` (0009 D16; today `xxh3_128` in
  `compiler/src/IdrisMLIR/Ids.idr`), a Merkle hash of a node's kind,
  payload and children's hashes, so a generated name carries its low 64
  bits (0009 §4.5). The table probes with the low 64 bits, and a hit
  compares the node's columns, never the hash alone (0009 §11). The fork
  never imports `IdrisMLIR.*` and `IdrisMLIR.Ids` may not import the fork
  (AGENTS.md), so A0 moves the one definition into a `libs/` package both
  import, plain Idris with bodies; a copy in the fork would be a second
  copy (*decision*, 2026-10-15). Its cost, 16 bytes a node, is a
  *conjecture* that T0 and A0's record show.
- **Values follow smalltt:** indices in terms, levels in values, closures
  for binders, no substitution (`sources/code/smalltt/src/CoreTypes.hs`,
  `Evaluation.hs`).
- **Only terms are hash-consed** (D10). It pays where terms are compared
  or memoized: a λ-calculus quicksort ran 91.5 s without it and 195 s
  with it, and 54 s against 5.06 s once memoized (*read*, `columnar.md`
  §6, Filliâtre §3.1). Closures in values share beta-reductions.
- **No spans in terms** (D10): a hash-consed node has no one position. A
  TTC already writes no `FC` and reads every term back at `emptyFC`
  (`compiler/idris/src/Core/TTC.idr`), so Translate's fallback to the
  definition's span (`bestFC`, `Frontend/Translate/Terms.idr`) already
  names the definition for every definition read from a TTC; that becomes
  the rule for every definition. A refusal after elaboration names the
  definition, the callee and the value that grows; the elaborator's own
  errors keep their columns (0012 §3's syntax nodes).
- **The loose-bound-variable range is a `Bits64`** beside 32-bit indices,
  so it holds every range and nothing checks it (*decision*, 2026-10-15,
  replacing a checked 32-bit word): Lean's kernel packed it into 20 bits,
  and an overflow check that returned 0 turned every skip on, a soundness
  bug (`sources/papers/carneiro-2024-lean4lean/main.tex`).
- **Ids never leave the arena** (D11): an id is the order a node was
  first interned, which a parallel elaborator's schedule decides
  (`sources/notes/sharded-compilation/whole-program-at-scale.md` §7).
  Whatever leaves (a TTC, a symbol, an instance key, MLIR) is written from
  content; a TTC keeps its tree format, and a format that writes each
  distinct subterm once is taken only if T0 shows TTC loading above 5% of
  elaboration (0012 D0's rule).
- **Two lifetimes, in the id's type** (D15): a persistent part (checked
  definitions, what TTCs hold) and a temporary part per check or
  normalization, dropped when it ends, as nanoda checks each declaration
  with a fresh DAG (`util.rs`). A temporary id cannot be written into a
  persistent row; a result that outlives its check is interned into the
  persistent part, one walk of what is new, its hash unchanged. Reason:
  the frontend peaked at 9.1 GB on Chez compiling itself (*measured*
  2026-10-10, 0012 §2).
- **Caches hold only what their key decides** (D12, from Lean's kernel
  and elaborator): a closed meta-free term by id; conversion as success
  and failure sets, never a transitive closure, since conversion with
  unfolding is not transitive (`sources/code/lean4/src/kernel/type_checker.h`);
  a term with metas in a transient set, dropped when the check postpones
  a constraint (`sources/code/lean4/src/Lean/Meta/ExprDefEq.lean`).

Syntactic equality is then an integer compare, conversion normalizes only
when ids differ, a normal form is computed once per id, and memory is a
few large arrays, each one counted cell (0013 D4).

## 4. The machine: wavefront evaluation

*Decision* (D6). Every live machine state is a row (the term id under
evaluation, its environment, its continuation as a slice of a frame
column), and one step advances all of them by four whole-table
operations:

1. **Group:** a stable counting sort of the rows by their term's kind.
2. **Run one kernel per kind** over its segment: a variable gathers from
   the environment column, a lambda builds closure rows, an application
   pushes a frame, a case selects its branch by a gather on the
   scrutinee's constructor, a constructor builds a value row, a primitive
   is §13's.
3. **Share:** a row on a closed meta-free term takes the cached value of
   its id, and rows that meet on one are merged; a row on an open term is
   cached under (term id, environment slice), the slice's identity, never
   its contents, since comparing would hash-cons values.
4. **Compact:** finished rows scatter their values to the rows waiting on
   them and leave; new rows are appended.

A per-element lambda over `n` indices is `n` rows in one wavefront, so
dispatch is paid once per kind per step: NESL's flattening done at run
time by Elsman's expansion (*read* through
`sources/notes/flattened-data/flattening.md` §2). NESL's own interpreter
lost on dense data to per-operation overhead (same notes, §4-5), and a
tail-recursive loop ran two orders of magnitude slower fully vectorised
(Keller et al. 2012, same notes, §4), which is why **one row is the plain
loop**: a deep sequential recursion keeps one row, grouping one row is one
compare, and the machine must be as fast there as a direct evaluator over
the same arena, A1's gate.

**Deterministic** (D8): rows are ordered by the stable sort and the order
they were appended; the budget counts steps and bytes, never time, so a
call is normalized or deferred identically on every machine, thread count
and shard count. **Parallel by construction:** each kernel is
data-parallel over its segment.

**Two drivers over one step** (D13). The checker's evaluation runs to its
end with no budget, behind the fork's `host`, since conversion decides
acceptance and no count may (AGENTS.md); static normalization runs under
the budget, which is also what makes its loop structurally total. The
problem has these two cases; the step and its kernels are shared.

## 5. Arrays in interpreted code

A program's arrays go through `libs/mlir-array`'s generating set, bodiless
`%extern`s (`tabulate`, `foldLast`, `scanLast` and the rest,
`libs/mlir-array/Array/Core.idr`), so interpreted code meets no body to
interpret, and a stock-hosted frontend can build no runtime array cell.
The interpreter stops at a generating op as at any bodiless `%extern`
(§2, stuck), and the call runs at run time. A wide `tabulate` as a wide
wavefront (A4) needs a body for each op the interpreter can run, which is
0010 D45's open question at its stage 7 (whether a layer definition's
body, with its hook, serves programs too, so that each operation is
declared once), and an array value held as the interpreter's own rows
(§13, question 3). An interpreter kernel per op would be its second
meaning (D3), and interpreted array chains are never fused, since that
would be a second compiler.

## 6. The kernels, over 0010's plain-Idris layer

The kernels are frontend code, so they are never written over
`mlir-array`'s `%extern` ops (0010 D45). Until A5 they are plain Idris
over base. Most of a step is not elementwise: the group by kind is a
counting sort (a histogram of the kind column, an exclusive `addi` scan
and a scatter), compaction is flags, an exclusive scan and a scatter, and
writing results back is a scatter (0010 §4.4, §11). At A5 they move onto
0010 D45's plain-Idris layer, adding to it the operations they use
(gather, histogram, exclusive scan, scatter, filter), each a definition
with a body that is its one meaning on both hosts and a `Faster` hook onto
0010's op (`idr.scan` and `idr.scatter` from its stage 4, `filter` from
5). idris-mlir then gives the native frontend 0010's lowering, fusion and
vectorization, elementwise steps checked by idr-expect's `fused`
(`foreign/idr/lib/Transforms/Expect/Fused.cpp`), and removing a hook
leaves every result. Their cost is measured at A5, not assumed.

## 7. Where it runs

In the frontend, where choices are decided: static normalization extends
Translate's normalization of compile-time values (§1) to the value level
at the same point, so a choice computed by recursion reaches the instance
decision that needs it. A closed call needs only its callees, which a
module's imports provide, so its results belong to the module's summary
once 0009 builds it (0009 §3.1, §5.3). **The C++ pipeline never runs
program code** (0009 D6): what leaves the frontend is ordinary IR
(constants, closure constants, memo cells), and no pass knows static
normalization exists. The type checker uses the same arena, machine and
caches for conversion, unification and proofs by reflection (0014).

**Stage 0** (D19, restated 2026-10-15 under AGENTS.md's two hosts).
From A3 the bootstrap's default stage 0 is the native frontend
built from the last commit before A3, a build choice; the stock Idris on
Chez still builds and runs the current frontend, interpreter included,
and that build is tested. A fold of Chez's meaning, should §13's second
question admit one, so stays out of the bootstrap chain.

## 8. The interactive loop

Moved here from 0010 (§3.9 there). `idris-mlir repl` runs a line as a
program, compiled through the same pipeline and linked as an executable,
in a child; no JIT in the driver (D4). It is running a program, not
normalizing one. It is A7, after A0, because a line's latency is mostly
the frontend loading what the line imports (*conjecture*), which A0's
arena changes (D17). A7 builds a child per line, then measures the
latency rule (1 s from line to output for an expression over arrays of up
to 10⁶ elements); a miss builds a resident frontend in the same stage,
one child process of ours that keeps the loaded context between lines,
never a library loaded at run time (AGENTS.md).

## 9. Rules changed when A3 lands

- AGENTS.md's paragraph on primitives: the compiler normalizes the static
  part of the program with the type checker's evaluator (closed total
  calls to values within a counted budget, first-demand constants beyond
  it, partly static calls specialized on the arguments that steer
  control, partial and covering code never), with §13's ruling on what
  the evaluator may fold.
- AGENTS.md's middle way: "which static normalization, specialization,
  closed sums and defunctionalization compile away".
- README.md: the frontend "normalizes the static part"; no JIT.
- `harness/README.md`: D5's twin tests.

## 10. Staged plan (every stage AFTER-SELF)

Each stage passes AGENTS.md's checks on both targets and records compile
times against the stage before, old binary against new binary from a
named saved input (the cutover's §10 rule). The bar is the native stages'
wall; stage 0's on the stock host is recorded beside it, never a bar
(*decision*, 2026-10-15: nothing is shaped so that Chez can run it, and
Chez must only build and run it). A stage that makes the native
self-compile slower is reworked, never kept beside the form it replaces.

| Stage | Needs | Content | Proof |
| --- | --- | --- | --- |
| A0 | `make self`, 0014's T0 | interned names and the hash-consed arena in the fork: typed ids, two lifetimes, the `hash` column with the one XXH3 moved to `libs/`; the fork's evaluator (`Eval.idr`, `Quote.idr`, `Convert.idr`) reads terms from it, its strategy unchanged; the frontend reads TT from it; TTCs keep their tree format | identical TTCs and corpus; elaboration of base and the frontend ≥ 1.5× faster than T0; peak resident memory no higher than T0's |
| A1 | A0 | the wavefront machine replaces A0's evaluator in one change (D14): weak head normal form and the read-back the checker needs | **the gate,** best of five, A1's binary against A0's on the checker's own normalizations (base, the frontend, smalltt's set): at most 2% slower where one row is live, more than 2% faster where many are (a `tabulate`-shaped corpus); 2% is the cutover's §10 runtime margin (0010 D35 on why not the run-to-run spread); a miss is reworked before it lands |
| A2 | A1 | glued values, §3's caches, approximate conversion | smalltt's set within 1.5× of smalltt; ≥ 2× over A0 on conversion-heavy files |
| A3 | A2, §13 Q2 | static normalization in the frontend: closed total calls to values, the frontend's share of control-steering specialization, the budget, first-demand constants beyond it; §9's rules; D19 | `tests/programs/eval` and the corpus unchanged in output; D5's twin tests; byte-identical across thread counts; `make self` green, and the current frontend built and run under the stock host; no bench program's runtime or peak resident memory worse by more than 2% |
| A4 | A3, §13 Q3 | arrays in interpreted code as wide wavefronts (§5) | a table of 10⁶ words built by array operations normalizes within the budget; reflection benchmarks ≥ 10× over A2 where they use arrays |
| A5 | 0010's stage 7 (D45) | the kernels onto D45's layer, adding the operations they use, each hooked onto 0010's op (§6) | `fused` on every elementwise kernel; wide-wavefront benchmarks faster than the stage before; every result unchanged with the hooks removed |
| A6 | 0008's P4 | segments across shards, through a `Faster` hook on a plain-Idris definition, never a `libs/` `%extern` the stock host would reach | identical results at every shard count; wall time on the A1 corpus recorded |
| A7 | A0 | the interactive loop (§8) | every line's output equal to the same expression compiled as a program; the latency of the 10⁶-element case recorded on both targets |

A3's 2% memory bar applies the cutover's runtime margin to what
over-budget cells retain until exit; A0's memory bar holds because the
arena exists to cut memory as well as time (§3) (*decision*).

## 11. Rejected alternatives

- A JIT or native compilation of reductions (the deleted `idr-eval`;
  Coq's `native_compute`, its compiler in the trusted base): a second
  compiler inside the first. WebAssembly: a second lowering and an
  embedded engine. A bytecode machine (Coq's `vm_compute`): a second
  representation of code beside the arena (`elaborators.md` §7).
- A tree-walking interpreter as the design: dispatch per element; it is
  only A0's evaluator, which A1 replaces.
- Eager evaluation of every closed call, partial included: a divergence
  budget and schedule-sensitive refusals. Over-budget constants computed
  at startup: a failing primitive inside would fail before the demand.
- A switch that turns static normalization off: a behaviour-selecting
  option (the cutover's D2); D5's twin tests check the property with one
  compiler.
- The frontend cloning a function for a constructor its body matches on:
  the ready set does it, in one place (D9). Specializing on every constant
  argument: one clone per value. Normalizing open terms: supercompilation.
- Hash-consing values or merging rows on equal environments; a span in
  every term node; an arena that only grows; a shared-subterm TTC format
  inside A0 (§3).
- A `comptime` keyword or staging annotations: the types say what is
  static, the totality checker what is safe.
- A stage 0 frozen before A3 as the only way the frontend builds: the two
  hosts (D19 keeps it as the bootstrap's default only). An interpreter
  kernel per generating op: its second meaning (§5). Kernels over
  `libs/mlir-array`'s `%extern`s, or segments over `libs/mlir-shard`'s:
  the stock host reaches none (0002 R3); 0010 D45's layer is the route.

## 12. Decisions

- D1 (owner, 2026-10-10). Only total code is normalized at compile time;
  partial and covering code never is.
- D2 (owner, 2026-10-10). No compile-time evaluation feature: the
  compiler normalizes the static part of the program, and
  monomorphisation is the case where the static arguments are types.
- D3 (owner, 2026-10-10; restated 2026-10-14). One evaluator, the type
  checker's interpreter, with array operations interpreted as their
  library definitions, a wide array a wide wavefront; no whole-array
  runtime primitive, no JIT, no WebAssembly, no compiled tier. Too
  expensive means a top-level constant computed once, at its first
  demand (the owner said "a startup constant"; first demand is the
  precise form, §2).
- D4 (owner, 2026-10-10). The interactive loop runs lines as linked
  executables, outside compilation. There is no JIT in the driver.
- D5 (owner, 2026-10-10; restated 2026-10-14). Static normalization never
  changes a program's output, and each of its tests holds its
  computations twice, once closed and once on a value read at run time,
  against one expected file, as `compile-time-evaluation` does with
  `fib 27` and `fib n` (the owner's form, every program test with and
  without it, needs the switch the cutover's D2 rules out).
- D6. The interpreter is the wavefront machine (§4); A1's gate is a
  condition it meets, not a fallback.
- D7. One arena, owned here, plain Idris over base; every reader reads it
  and none copies it (§3).
- D8. The budget counts steps and bytes; nothing the machine decides
  depends on time, threads or shards (§4).
- D9. One specializer per kind of argument: the frontend's on what
  decides types and representations, the ready set's on known
  constructors (§2).
- D10. Only terms are hash-consed, they hold no spans, and the
  loose-bound-variable range is a `Bits64` (§3).
- D11. Arena ids never reach output; a TTC keeps its tree format (§3).
- D12. Caches hold only what their key decides (§3).
- D13. The budget is static normalization's alone, a named constant in
  `tools/policies.txt`, and never rejects a program (the cutover's D17);
  the checker's evaluation has none and stays behind the fork's `host`
  (§4).
- D14. A0's evaluator is replaced at A1 in one change, measured binary
  against binary; no second evaluator is kept (the cutover's D2, §10).
- D15. Two lifetimes in each id's type; caches across checks key on
  persistent ids (§3).
- D16. The `hash` column is the one XXH3-128 (0009 D16), one definition
  the fork and the frontend both import, never trusted alone (§3).
- D17. The interactive loop is A7, after A0 (§8).
- D18. A closed array result of words or floats is a dense constant, an
  immortal `memref.global` (0010 §12, D23), whose lowering landed with
  0010's stage 1 (c7aa7b62; `LowerGetGlobal`,
  `foreign/idr/lib/Conversion/Arrays.cpp`); of any other element, it is
  built at startup from its elements' constants. It has a producer only
  once §13's third question gives the interpreter arrays to finish.
- D19 (restated 2026-10-15). From A3 the bootstrap's default stage 0 is
  the native frontend of the last commit before A3; the stock host still
  builds, runs and tests the current frontend (§7).

## 13. Open questions

1. **The restated owner decisions D3 and D5** (the owner's). Default: the
   restated forms, first-demand constants and twin tests, since startup
   evaluation can fail before a demand and the with-and-without matrix
   needs a switch the cutover's D2 forbids.
2. **What the normalizer may fold of a primitive** (the owner's; reopened
   2026-10-15, since the frontend runs under the stock host too). A
   primitive's one meaning is `runtime/`'s (AGENTS.md), and code the stock
   host runs reaches no `libs/` `%extern` (0002 R3). Default: the
   normalizer applies no primitive, on either host; a call that reaches
   one is stuck (§2), so A3 computes over constructors, matches and
   closures (the choices of §1), and arithmetic stays at run time. The
   checker's driver keeps applying primitives through base's, as the fork
   does, since its results never reach output; the driver, never a test
   per row, picks the primitive kernel. Alternative: the normalizer folds
   through base's primitives too, one kernel, `runtime/`'s meaning under
   idris-mlir and Chez's in a stock-hosted frontend's output, which D19
   keeps out of the bootstrap chain only; it needs AGENTS.md amended.
3. **A body the interpreter can run for each generating op** (0010 D45's
   question at its stage 7, with the owner). A4 needs it, an array value
   held as the interpreter's own rows, and question 2's alternative, since
   a body applies primitives. Default: 0010's (open until its stage 7);
   until then A4 is not taken, and D18 waits.
