<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0010: the array interpreter

**Amended by P0 (2026-10-21, `0000-mlir-native.md`).** A0 (interned
names, the term arena as columns) is absorbed into the cutover (D44):
the arena in the checker, in the form C183 gives it (§3), and its reader
side in the frontend (P0 §7's F6). A1 onward stay as written,
AFTER-SELF; static normalization (the closed call folded) is still not
built, and which side it runs on is open (below, "Under P0").

**Status (2026-10-23):** A0's arena is in the checker
(`compiler/checker/src/Core/TT/Stored.idr`), P0's work; nothing later is
built: no hash-consing, wavefront machine or `repl` in `compiler/src`,
`compiler/checker/src` or `foreign/idr`. **A0 is P0's** (D44), written
by its lanes and built only with the whole cutover (D56); its bars stay
ratios to 0013's T0, measured natively once `make self` holds (C136).
Every later stage is **AFTER-SELF**. After A0: A1 needs A0, A2 A1, A3
A2, A4 A3 and 0009's stage 7 (§13, question 3), A5 0009's stage 7, A6
0007's P4, A7 A0. Nothing up to A3 needs sharding; its place after
sharding is the queue's order, not a dependency. As planned here, all
of it is Idris in the checker and the frontend (A3's side is open:
"Under P0"), so it builds and runs under the stock Idris on Chez and
under idris-mlir,
always (AGENTS.md's two hosts, as 0009 D45 applies them): the arena and
the machine are plain Idris over base and, for array operations, over
0009 D45's plain-Idris layer, which idris-mlir lowers through the
registry's `Faster` hooks; they never reach a `libs/` `%extern`. "The
cutover" is the pipeline cutover, its last text at 484d6403
(`proposals/0005-compile-time/README.md` there).

It owns three earlier plans: static normalization (the owner's decisions
of 2026-10-10, D1 to D5), the frontend's interned names and term arena
(once 0011's O4), and the type checker's evaluator (once 0013's §2.2, T1,
T2 and T6). Claims are marked *read*, *measured*, *recalled*,
*conjecture* or *decision*.

**The idea.** A dependently typed compiler needs no "comptime" feature: its
type checker already normalizes total code, because deciding whether two
types are equal requires it. Compile-time evaluation, constant folding and
monomorphisation are one operation: **normalize the static part of the
program**, on the type checker's own evaluator. That evaluator is an array
program: terms are columns, hash-consed within each stored definition
(P0's C183, §3), machine states are rows, and each step runs one kernel
per kind of term over all the rows at that kind, so interpretive
overhead is paid per kind and per step, not per element. No JIT, no
WebAssembly, no forked child, no bytecode, no second compiler inside
the first.

**Under P0** (read, 2026-10-22). AGENTS.md: "Idris does types; MLIR
does programs": every optimization runs in C++ over MLIR, and the Idris
side checks what the compiler accepts, monomorphises and decides
representations; "a closed call runs at run time. Static normalization
(proposal 0010) is what would fold one, and it is not built." P0's D109
puts "the e-graph and every pass that makes code faster or smaller" in
C++ over MLIR, "within reason. don't take that too literally", and
keeps on the Idris side the frontend's checking, elaboration and
representation decisions; its D68 keeps one evaluator, the checker's
("No second evaluator (0010 D3: one evaluator)"). The checker's own
evaluation (A0 to A2) is checking, the Idris side's. A3 does two things
those texts place differently: it folds a closed total call to a
constant, which makes code faster, and it hands the value to the
frontend's instance decisions, which are representation. Whether A3
runs in Idris on the checker's evaluator, as this proposal has it,
neither D109 nor AGENTS.md settles: it is open.

## 1. Where it starts from

*Read*, 2026-10-15:

- No pass runs program code; a closed call runs at run time (AGENTS.md).
  `tests/closed-calls/Main.idr` holds closed calls
  (`fib 15`, `fib 27`) beside the same functions on a digit read from
  input, against one expected file, and
  `tests/partial-divergent-call` holds that a closed call
  of a partial function stays a call. A constant table computed from
  constants is computed by the program, every run.
- The frontend normalizes only compile-time values (types and
  implementations), on the checker's normaliser behind `host`
  (`compiler/checker/src/Idris/Host.idr`): `normaliseClosed` and
  `normalisedBy` in
  `compiler/src/IdrisMLIR/Frontend/Translate/Closed.idr`, read by
  `classify` in `Translate/Instances.idr`. A choice computed by a
  recursive closed call over values is not known when instances are
  decided, so monomorphisation cannot use it.
- The checker's evaluator is call by name with no update: a closure is
  evaluated again at each use (`evalClosure`,
  `compiler/checker/src/Core/Normalise/Eval.idr`); a `Glued` pair
  rebuilds its normal form at each `getNF` (`gnf` stores a function,
  not a result); `Convert Term` (`Core/Normalise/Convert.idr`)
  normalizes both sides before comparing heads; nothing is cached.
  Idris 2 was the slowest system on smalltt's elaboration benchmarks,
  stlc10k in 129.6 s against smalltt's 0.306 s (*measured* there in 2021,
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
  (`idris_rt_caf_release`), under shards the memo sum's `Static i` (0007
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
  cutover's §4.8; 0009 §4.3).
- **Under a binder** (an open term): never normalized; that is
  supercompilation, and code explodes.
- **Stuck:** a step that reaches a world (IO, `unsafePerformIO`, a linear
  array's operations), a primitive or a bodiless `%extern` the
  interpreter gives no meaning (§13, questions 2 and 3), or a failing
  primitive (a division by zero). The call runs at run time, where it
  fails as the program would. The totality checker keeps most failing
  primitives out already: one that can fail is not covering, so the
  checker refuses `prim__div_Double` in a definition not marked `partial`
  (`upstream/18-elaboration-primitive-folding/README.md`).

## 3. The representation: the arena, as columns per definition

*Decision* (D7, as P0's C183 shapes it). The checker's terms, the
frontend's TT and the interpreter's code are one representation, read
by 0011's frontend and 0013's checker; no pass copies it into a second
form. It is not one global arena (C183): a term being elaborated stays
an unshared, located tree, as the elaborator's 59 location reads need;
when a definition is stored, its terms become columns in preorder,
shared within the definition, with their locations as one more preorder
column. The stored columns are frozen with the definition (an immutable
array of `mlir-array`, both hosts), so every read is a pure read of an
immutable value and the checker states no new trust; definitions refer
to one another by interned name, never by arena position, so no table
grows under a read. Its cost is no sharing across definitions, which a
global append-only arena would give at the price of that trust. It is
plain Idris over base (the checker's tables are base's `Data.IOArray`
today, `compiler/checker/src/Libraries/Data/Table.idr`), linear where
that helps.

| Table | Columns | Notes |
| --- | --- | --- |
| names | `id → (offset, len)` into one byte buffer; namespaces are ids | interned once; equality is an id compare |
| terms | `kind : u8`, `a : u32`, `b : u32`, `extra : u32` (a slice of an extra column for variable arity, decoded by `kind`); cached `hash`, loose-bound-variable range, `has_metas` | a stored definition's, in preorder: one id per distinct subterm within the definition, none shared across definitions (C183); de Bruijn indices; no source spans, the locations a preorder column beside them |
| values | `kind`, `head`, `env` (a slice of an environment column), `spine` (a slice of a spine column), `unfolded` (a value id or none) | levels, not indices; glued: head and spine the cheap form, `unfolded` the unfolded one; never hash-consed |
| caches | `closed term → whnf`, `closed term → normal form`, `(term, term) → convertible` as success and failure sets, and a transient set for terms with metas | indexed by id; a hit costs a gather |

- **Typed ids** (0011 D1): every id is a type indexed by its table, erased
  to a word, so a `TermId` cannot index the value table, and a read
  through one is an `index` with no guard (0009 D4, §3.2).
- **The hash-cons table**, which shares a definition's terms as it is
  stored (C183), is open addressing over the stored `hash` column, so a
  resize never rehashes (Filliâtre and Conchon,
  `sources/code/ocaml-hashcons/hashcons.ml`, read through
  `sources/notes/flattened-data/columnar.md` §6); the cached hash, flags
  and range per node are Lean 4's kernel's
  (`sources/code/lean4/src/kernel/expr.h`), and nanoda interns every
  expression as a 32-bit index (`sources/code/nanoda_lib/src/util.rs`).
- **The `hash` column** (D16) is the frontend's one content hash,
  XXH3-128 in plain Idris over `Bits64` (0008 D16; today `xxh3_128` in
  `compiler/src/IdrisMLIR/Ids.idr`), a Merkle hash of a node's kind,
  payload and children's hashes, so a generated name carries its low 64
  bits (0008 §4.5). The table probes with the low 64 bits, and a hit
  compares the node's columns, never the hash alone (0008 §11). The
  checker and the frontend both import the one definition, plain Idris
  with bodies, and a copy in the checker would be a second copy
  (*decision*, 2026-10-15). The reason A0 was to move it into a `libs/`
  package, an import rule fencing the checker from `IdrisMLIR.*`, is
  gone: no import rule fences the checker (P0's D118, C233). Where the
  one definition lives, P0 does not say. Its cost, 16 bytes a node, is a
  *conjecture* that T0 and A0's record show.
- **Values follow smalltt:** indices in terms, levels in values, closures
  for binders, no substitution (`sources/code/smalltt/src/CoreTypes.hs`,
  `Evaluation.hs`).
- **Only terms are hash-consed** (D10), each within its definition
  (C183). It pays where terms are compared or memoized: a λ-calculus
  quicksort ran 91.5 s without it and 195 s with it, and 54 s against
  5.06 s once memoized (*read*, `columnar.md` §6, Filliâtre §3.1).
  Closures in values share beta-reductions.
- **No spans in terms; locations beside them** (D10): a hash-consed node
  has no one position. Since 374e0e77 the checker's TTC keeps each node's
  location and reads it back (`compiler/checker/src/Core/TTC.idr`;
  `compiler/checker/README.md`, "What a TTC keeps"), and every op the
  frontend emits names the term it comes from (`bestFC`,
  `Frontend/Translate/Terms.idr`), which the reject tests' lines hold.
  A0 keeps that fact: a location is a column of the occurrence (a TT
  node as Translate reads it; C183's preorder location column), never of
  the hash-consed term, and never enters the `hash` column (as 0008 D17
  keeps locations out of keys). *Decision*: dropping it would erase a
  fact before the pass that uses it (AGENTS.md).
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
  elaboration (0011 D0's rule).
- **A tree while elaborated, columns once stored** (P0's C183, replacing
  D15's two lifetimes in the id's type): a term being elaborated is an
  unshared, located tree, and a stored definition's terms are its frozen
  columns. No global arena holds both parts, so no id carries a
  lifetime and no temporary id can reach a stored row. What a
  normalization's own temporary terms are, from A1 on, P0 does not say.
- **Caches hold only what their key decides** (D12, from Lean's kernel
  and elaborator): a closed meta-free term by id; conversion as success
  and failure sets, never a transitive closure, since conversion with
  unfolding is not transitive (`sources/code/lean4/src/kernel/type_checker.h`);
  a term with metas in a transient set, dropped when the check postpones
  a constraint (`sources/code/lean4/src/Lean/Meta/ExprDefEq.lean`).

Syntactic equality within a definition is then an integer compare,
conversion normalizes only when ids differ, a normal form is computed
once per id, and a stored definition's terms are a few frozen arrays,
each one counted cell (0012 D4).

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
end with no budget, behind the checker's `host`, since conversion
decides acceptance and no count may (AGENTS.md); static normalization
runs under the budget, which is also what makes its loop structurally
total. The
problem has these two cases; the step and its kernels are shared.

## 5. Arrays in interpreted code

A program's arrays go through `libs/mlir-array`'s generating set, bodiless
`%extern`s (`tabulate`, `foldLast`, `scanLast` and the rest,
`libs/mlir-array/Array/Core.idr`), so interpreted code meets no body to
interpret, and a stock-hosted frontend can build no runtime array cell.
The interpreter stops at a generating op as at any bodiless `%extern`
(§2, stuck), and the call runs at run time. A wide `tabulate` as a wide
wavefront (A4) needs a body for each op the interpreter can run, which is
0009 D45's open question at its stage 7 (whether a layer definition's
body, with its hook, serves programs too, so that each operation is
declared once), and an array value held as the interpreter's own rows
(§13, question 3). An interpreter kernel per op would be its second
meaning (D3), and interpreted array chains are never fused, since that
would be a second compiler.

## 6. The kernels, over 0009's plain-Idris layer

The kernels are frontend code, so they are never written over
`mlir-array`'s `%extern` ops (0009 D45). Until A5 they are plain Idris
over base. Most of a step is not elementwise: the group by kind is a
counting sort (a histogram of the kind column, an exclusive `addi` scan
and a scatter), compaction is flags, an exclusive scan and a scatter, and
writing results back is a scatter (0009 §4.4, §11). At A5 they move onto
0009 D45's plain-Idris layer, adding to it the operations they use
(gather, histogram, exclusive scan, scatter, filter), each a definition
with a body that is its one meaning on both hosts and a `Faster` hook onto
0009's op (`idr.scan` and `idr.scatter` from its stage 4, `filter` from
5). idris-mlir then gives the native frontend 0009's lowering, fusion and
vectorization, elementwise steps checked by idr-expect's `fused`
(`foreign/idr/lib/Transforms/Expect/Fused.cpp`), and removing a hook
leaves every result. Their cost is measured at A5, not assumed.

## 7. Where it runs

In the frontend, where choices are decided: static normalization extends
Translate's normalization of compile-time values (§1) to the value level
at the same point, so a choice computed by recursion reaches the instance
decision that needs it. A closed call needs only its callees, which a
module's imports provide, so its results belong to the module's summary
once 0008 builds it (0008 §3.1, §5.3). **The C++ pipeline never runs
program code** (0008 D6): what leaves the frontend is ordinary IR
(constants, closure constants, memo cells), and no pass knows static
normalization exists. The type checker uses the same arena, machine and
caches for conversion, unification and proofs by reflection (0013).

**Stage 0** (D19, restated 2026-10-15 under AGENTS.md's two hosts).
From A3 the bootstrap's default stage 0 is the native frontend
built from the last commit before A3, a build choice; the stock Idris on
Chez still builds and runs the current frontend, interpreter included,
and that build is tested. No fold of a primitive enters either build
(§13, question 2).

## 8. The interactive loop

Moved here from 0009 (§3.9 there). `idris-mlir repl` runs a line as a
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

## 10. Staged plan (A0 in P0, every later stage AFTER-SELF)

Each stage passes AGENTS.md's checks on every target and records compile
times against the stage before, old binary against new binary from a
named saved input (the cutover's §10 rule). The bar is the native stages'
wall; stage 0's on the stock host is recorded beside it, never a bar
(*decision*, 2026-10-15: nothing is shaped so that Chez can run it, and
Chez must only build and run it). A stage that makes the native
self-compile slower is reworked, never kept beside the form it replaces.

| Stage | Needs | Content | Proof |
| --- | --- | --- | --- |
| A0 | nothing outside P0, which writes it (P0's D44) and builds it only with the whole cutover (P0's D56); its bars, ratios to 0013's T0, are measured once `make self` holds (P0's C136) | interned names and the term arena in the checker as C183 shapes it: typed ids, terms an unshared located tree while elaborated and frozen per-definition columns once stored, shared within the definition, the `hash` column with the one XXH3; the checker's evaluator (`Eval.idr`, `Quote.idr`, `Convert.idr`) reads terms from it, its strategy unchanged; the frontend reads TT from it (P0 §7's F6); TTCs keep their tree format | identical TTCs and corpus; elaboration of base and the frontend ≥ 1.5× faster than T0; peak resident memory no higher than T0's |
| A1 | A0 | the wavefront machine replaces A0's evaluator in one change (D14): weak head normal form and the read-back the checker needs | **the gate,** best of five, A1's binary against A0's on the checker's own normalizations (base, the frontend, smalltt's set): at most 2% slower where one row is live, more than 2% faster where many are (a `tabulate`-shaped corpus); 2% is the cutover's §10 runtime margin (0009 D35 on why not the run-to-run spread); a miss is reworked before it lands |
| A2 | A1 | glued values, §3's caches, approximate conversion | smalltt's set within 1.5× of smalltt; ≥ 2× over A0 on conversion-heavy files |
| A3 | A2 | static normalization in the frontend: closed total calls to values, the frontend's share of control-steering specialization, the budget, first-demand constants beyond it; §9's rules; D19 | `tests/closed-calls`, `tests/e2e-eval` and the corpus unchanged in output; D5's twin tests; byte-identical across thread counts; `make self` green, and the current frontend built and run under the stock host; no bench program's runtime or peak resident memory worse by more than 2% |
| A4 | A3; 0009's stage 7 (§13 Q3) | arrays in interpreted code as wide wavefronts (§5) | a table of 10⁶ words built by array operations normalizes within the budget; reflection benchmarks ≥ 10× over A2 where they use arrays |
| A5 | 0009's stage 7 (D45) | the kernels onto D45's layer, adding the operations they use, each hooked onto 0009's op (§6) | `fused` on every elementwise kernel; wide-wavefront benchmarks faster than the stage before; every result unchanged with the hooks removed |
| A6 | 0007's P4 | segments across shards, through a `Faster` hook on a plain-Idris definition, never a `libs/` `%extern` the stock host would reach | identical results at every shard count; wall time on the A1 corpus recorded |
| A7 | A0 | the interactive loop (§8) | every line's output equal to the same expression compiled as a program; the latency of the 10⁶-element case recorded on every target |

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
  the stock host reaches none (AGENTS.md's two hosts); 0009 D45's layer
  is the route.

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
  against one expected file, as `tests/closed-calls` does with
  `fib 27` and `fib n` (the owner's form, every program test with and
  without it, needs the switch the cutover's D2 rules out).
- D6. The interpreter is the wavefront machine (§4); A1's gate is a
  condition it meets, not a fallback.
- D7. One representation of terms, plain Idris over base, in the form
  P0's C183 gives it: no global arena, a stored definition's terms its
  frozen columns; every reader reads it and none copies it (§3).
- D8. The budget counts steps and bytes; nothing the machine decides
  depends on time, threads or shards (§4).
- D9. One specializer per kind of argument: the frontend's on what
  decides types and representations, the ready set's on known
  constructors (§2).
- D10. Only terms are hash-consed, they hold no spans, an occurrence's
  location is a column beside them, and the loose-bound-variable range
  is a `Bits64` (§3).
- D11. Arena ids never reach output; a TTC keeps its tree format (§3).
- D12. Caches hold only what their key decides (§3).
- D13. The budget is static normalization's alone, a named constant in
  `tools/policies.txt`, and never rejects a program (the cutover's D17);
  the checker's evaluation has none and stays behind the checker's
  `host` (§4).
- D14. A0's evaluator is replaced at A1 in one change, measured binary
  against binary; no second evaluator is kept (the cutover's D2, §10).
- D15. Replaced by P0's C183: a term is an unshared tree while
  elaborated and its definition's frozen columns once stored, so no id
  carries a lifetime; caches across checks key on stored definitions'
  terms (§3).
- D16. The `hash` column is the one XXH3-128 (0008 D16), one definition
  the checker and the frontend both import, never trusted alone (§3).
- D17. The interactive loop is A7, after A0 (§8).
- D18. A closed array result of words or floats is a dense constant, an
  immortal `memref.global` (0009 §12, D23), whose lowering landed with
  0009's stage 1 (c7aa7b62; `LowerGetGlobal`,
  `foreign/idr/lib/Conversion/Arrays.cpp`); of any other element, it is
  built at startup from its elements' constants. It has a producer only
  once §13's third question gives the interpreter arrays to finish.
- D19 (restated 2026-10-15). From A3 the bootstrap's default stage 0 is
  the native frontend of the last commit before A3; the stock host still
  builds, runs and tests the current frontend (§7).

## 13. Questions decided

Each was left to the owner; each is decided here by the rule given
(*decision*, 2026-10-19).

1. **D3 and D5 as restated:** first-demand constants and twin tests.
   Reason: startup evaluation can fail before a demand, and the
   with-and-without matrix needs a switch the cutover's D2 forbids.
2. **What the normalizer may fold of a primitive: nothing**, on either
   host. A primitive's one meaning is `runtime/`'s (AGENTS.md), and code
   the stock host runs reaches no `libs/` `%extern`, so a call that
   reaches a primitive is stuck (§2): A3 computes over constructors,
   matches and closures (the choices of §1), and arithmetic stays at run
   time. The checker's driver keeps applying primitives through base's,
   as the checker's evaluator does today, since its results never reach
   output; the driver, never a test per row, picks the primitive
   kernel. Rejected: folding
   through base's primitives, which would put Chez's meaning in a
   stock-hosted frontend's output and needs AGENTS.md amended.
3. **A body the interpreter can run for each generating op** is 0009
   D45's question at its stage 7, decided there. A4 and D18 wait on it.

## The MLIR form owed

From the representation wave's audit of the proposals' MLIR forms (its
last text at 77eaa5b1), checked against the code there; none of it is
built unless it says so.

- §13's second question closes on its default for this reason: the folders
  call the runtime, and constants cross blocks by idr-optimize's
  `createConstants` over `SummarizedConstantPropagation`
  (`lib/Analysis/Constants.cpp`; upstream's `sccp` is not in the
  pipeline). A3 emits `idr.constant` and `arith.constant` arguments.
- A5's hooks follow 0009's tileable generating ops.
