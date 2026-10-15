<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0007: the array interpreter

**Status:** proposed 2026-10-12; reconciled 2026-10-14 with the pipeline
cutover (c7aa7b62, 5d5f3312; its proposal at 484d6403) and decided the
same day: every question is decided but the one in §13, which restates
two of the owner's rulings, and what A3's folds mean on the Chez host,
asked once in 0006 §12 (default: a native stage 0 from A3, D19). Nothing
here is built. The tree today (*measured*, 0002 and the cutover's §0):
the cutover 0002 designed is committed and builds on arm64 macOS, where
`make test` was 415/415 at 7a27fd34, before the opt-in SCC pipeline, and
again at 552d682a with it off by default; both runs took the Simplify
rounds, and the cutover deleted the rounds and that pipeline together.
x86_64 Linux is NotRun. `make self` has never finished; it waits on the
qualification of the cutover and the representation wave (bfdcac70; its
proposal at 484d6403), coded and integrated but not yet built, which the
owner's machine runs after 0004, integrated typecheck-only
(proposals/README.md). Compile-time evaluation is already gone:
`idr-eval`, its JIT and its forked child left the C++ side, the
runtime's evaluation entries left `runtime/`, and MLIR threading is on
(*read*: AGENTS.md, "A closed call runs at run time";
`tests/programs/eval/compile-time-evaluation`;
`foreign/idr/lib/Driver/Run.cpp:218-240`, the context on a pool sized by
`--num-threads`).

It takes over three earlier plans: static normalization (the former
static-normalization proposal, decided by the owner on 2026-10-10: D1,
D2 and D4 stand here word for word, and D3 and D5 are restated in §12,
each with its reason), the frontend's interned names and term arena
(0008's O1 and O4), and the type checker's evaluator (0010's former
§2.2, T1, T2 and T6). In the queue it follows sharding's first stages
(`proposals/README.md`). A0 to A3 need only `make self` (0002 §2, step
5), which follows the cutover, the representation wave and 0004; A4
needs 0003's stage 1, which landed with the cutover; A5 waits on 0003's
stage 5, the last its kernels' vocabulary needs (fusion at stage 3,
`idr.scan` and `idr.scatter` at 4, `filter` at 5); A6 on 0005's P4; A7,
the interactive loop, on A0. Claims are marked: *read*, *measured*,
*recalled*, *conjecture*, *decision*.

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

*Read* (the tree today): no pass runs program code. A closed call runs
at run time (AGENTS.md). `tests/programs/eval/compile-time-evaluation`
shows it: `fib 15` and `fib 27` are closed and stay calls, beside
`fib n` on a digit read from input, as `euclid` runs once closed and
once on the input, and one expected file holds every result
(`Main.idr:1-32`). So today:

- a constant table computed from constants is computed by the program,
  every run;
- a choice computed by a recursive closed call (a dictionary, an
  implementation, a shape) is not known when the frontend decides
  instances, so monomorphisation cannot use it. The frontend normalises
  only types and implementations, with Idris's normaliser
  (`compiler/src/IdrisMLIR/Frontend/Translate/Closed.idr:1-5, 273`;
  `Translate/Instances.idr:119-130, 212-218`);
- conversion checking in the fork compares trees of cells on upstream's
  evaluator, which is call by name with no update: a closure is
  evaluated again at each use (`compiler/idris/src/Core/Normalise/
  Eval.idr:139-141, 225-226, 634-637`); its "glued" pair builds its
  normal form afresh at each `getNF` (`Eval.idr:20-37`; `gnf` at
  `:661-667` stores a function, not a result); its conversion
  normalizes both sides before it compares heads
  (`Core/Normalise/Convert.idr:432-439`); and it caches nothing (*read*
  at ccaba89c, 2026-10-14; first read through
  `sources/notes/type-checking/elaborators.md` §11, whose line numbers
  have drifted). Idris 2 was the slowest system on smalltt's
  elaboration benchmarks, stlc10k in 129.6 s against smalltt's 0.306 s,
  424 times (same notes, §10; *measured* there in 2021, not here).

This proposal fixes all three with one machine. It is written for the
self-hosted frontend: the interpreter is Idris, compiled by this
compiler, so its kernels get the compiler's loops, vectorization and,
later, fusion and shards. On Chez it would be a slow tree walk, which is
why it waits for `make self`.

## 2. The operation: normalize the static part

Three rules decide it. Each already exists in the compiler.

| Rule | Decides | Already exists as |
| --- | --- | --- |
| **totality** | whether normalizing is *safe*: it ends, and covering code cannot fail a match | the totality checker |
| **closedness** (binding time) | *what* is normalized: calls whose arguments are all known | the instance set monomorphisation computes |
| **a cost rule** | whether it is *worth it*: total is not cheap (Ackermann is total) | a counted, deterministic budget, which stops normalizing and never rejects a program (the cutover's D17) |

What happens to a call, by how much of it is static:

- **A closed call of total code** normalizes to a value: a scalar, data,
  an array, or a function. The value is written as a constant the C++
  side already holds. Data is an `#idr.con` in an `idr.constant`
  (`foreign/idr/include/idr/IR/IdrAttrs.td:49`; `IdrOps.td:184`), which
  idr-lower writes as static cells at the runtime's persistent count 0,
  never counted and never freed (`lib/Conversion/StaticData.cpp`;
  `runtime/idris_rt.h:30-33`). An array of words or floats is a dense
  constant, an immortal `memref.global` (0003 §12, D23): the static
  shape it needs and its lowering came with 0003's stage 1, in the
  cutover (0003 D40; `LowerGetGlobal`,
  `foreign/idr/lib/Conversion/Arrays.cpp`). For an array of any other
  element, a closed array result is built at startup from its elements'
  constants (same section), which cannot fail, since every element is
  already a value. This proposal remains the producer of closed array
  results (0003 §12). A function is an `#idr.closure`
  (`IdrAttrs.td:120`) naming an `idr.func` that the frontend writes in
  symbol form, with a name derived from content (the cutover's §4.1);
  defunctionalization treats it as any closure constant.
- **A closed call the cost rule refuses** becomes a top-level constant:
  one static memo cell, forced at its first demand and never again, at
  native speed, once per shard that demands it (0005 D6). It is the
  shared arity-0 cell Emit already writes for a lazy constant
  (`compiler/src/IdrisMLIR/Emit/Declarations.idr:67-70`) and the
  runtime's static memo cell, released at exit
  (`runtime/idris_rt.h:30-33, 226-230`); under shards it is the memo
  sum's `Static i` state, naming the demanding shard's slot (0005 §6).
  The program's first demand *is* the compiled tier. *Decision:* first
  demand, never startup. The budget stopped before the call ended, so a
  failing primitive may be inside it, and it must fail where the program
  demands the value, as an effect of a trusted library happens where its
  value is demanded (AGENTS.md). The cell holds its value until exit, so
  A3 bounds what such cells retain (§10).
- **A partly static call** specializes only on the arguments that
  **steer control**, never on plain data, which would clone a function
  per distinct integer. The two sides of the compiler split them by what
  they decide (*decision*):
  - **the frontend** keys an instance on what decides types and
    representations: types, implementations (dictionaries), and a
    runtime argument's shape where the callee's type reduces on it, as
    the instance key does today (`Translate/Instances.idr:1-6`). Static
    normalization extends this to such values computed by a closed call.
    **Monomorphisation is this rule when the static arguments are
    types.**
  - **The cutover's ready set** specializes a callee on a runtime
    argument that is a known constructor of a sum, closures included
    once defunctionalization has made them sums, and an `Extents` value
    among them (the cutover's §4.8; 0003 §4.3). This supersedes the
    earlier "constructors the callee matches on" in the frontend: a
    constructor the body matches on decides no type, and two
    specializers would be one analysis held twice.
- **A call under a binder** (an open term) is never normalized: that is
  supercompilation, and code explodes.
- **Code reaching a world** (IO, or a forged world: `unsafePerformIO`,
  `Linear.Array`'s operations) is stuck and runs at run time.
- **A failing primitive** (a division by zero) makes the call stuck, and
  it runs at run time, where it fails as the program would. With only
  total code and no compiled tier there is nothing to isolate. The
  totality checker already keeps most such calls out, since a primitive
  that can fail is not covering and makes its caller partial (the fork
  refuses `prim__div_Double` in a definition not marked `partial`,
  *read*: `upstream/18-elaboration-primitive-folding/README.md`); the
  stuck rule covers what is left, a failure inside code asserted total.

## 3. The representation: one arena, as columns

*Decision.* The fork's terms, the frontend's TT and the interpreter's code
are one table, owned here and used by 0008's frontend and 0010's checker.
No pass copies it into a second form.

| Table | Columns | Notes |
| --- | --- | --- |
| names | `id → (offset, len)` into one byte buffer; namespaces are ids | interned once; equality is an id compare |
| terms | `kind : u8`, `a : u32`, `b : u32`, `extra : u32` (a slice of an extra column for variable arity, decoded by `kind`); cached `hash`, loose-bound-variable bound, `has_metas` | hash-consed: one id per distinct subterm, de Bruijn indices, no source spans |
| values | `kind`, `head`, `env` (a slice of an environment column), `spine` (a slice of a spine column), `unfolded` (a value id or none) | levels, not indices; glued: the head and spine are the cheap form, `unfolded` the unfolded one; never hash-consed |
| caches | `closed term → whnf`, `closed term → normal form`, `(term, term) → convertible` as success and failure sets, and a transient set for terms with metas | indexed by id; a hit costs a gather |

Every id is a type indexed by its table, erased to a word (0008 D1):
`TermId a` cannot index a value table. A read through such an id has no
guard, because its type bounds it by the table's extent, so it is an
`index` at its access (0003 D4, §3.2); no pass proves a check away, and
the earlier route through `idr-in-bounds` went with 0003's stage 1.

The hash-cons table is open addressing over the `hash` column, which
stores each node's hash so a resize never rehashes (*read* through
`sources/notes/flattened-data/columnar.md` §6: Filliâtre and Conchon
§2.3, `sources/code/ocaml-hashcons/hashcons.ml:20-90`). The cached word
per node is Lean 4's kernel's, whose expressions carry the hash, flags
and the loose-bound-variable range (`code/lean4/src/kernel/expr.h:124-155`),
and nanoda interns every expression as a 32-bit index so every cache key
is an integer (`code/nanoda_lib/src/util.rs:34-69, 394-400`) (*read*
through `elaborators.md` §3).

*Decision:* the `hash` column holds the frontend's one content hash,
XXH3's 128-bit variant written in plain Idris over `Bits64` (0006 D16,
which closed the question 0006 §12 once held, and checks the Idris copy
against the algorithm's published test values). It is a Merkle hash of
a node's kind, payload and children's hashes, so equal subterms hash
equally wherever they are interned, and a generated name carries its
low 64 bits (0006 §4.5). The table probes with its low 64
bits, and a hit compares the node's columns, never the hash alone (0006
§11 rejects trusting hash equality). Reason: 0006 keys owner shards,
summaries and symbol names by exactly this hash over these terms (0006
§4.1, §4.5), so one column serves the table and the names, and a name
taken without it would walk the term again. Its cost is 16 bytes a
node, about what the node's other columns take (*conjecture*); 0010's
T0 and A0's record show it.

Values follow smalltt: de Bruijn indices in terms, levels in values,
closures for binders, no substitution (`code/smalltt/src/CoreTypes.hs:23-67`,
`Evaluation.hs:26-32, 162-181`; *read* through `elaborators.md` §3).

Five rules about the arena, each a *decision*:

- **Only terms are hash-consed.** Hash-consing pays where terms are
  compared or memoized and costs where they are not: a λ-calculus
  quicksort ran 91.5 s without it and 195 s with it, and 54 s against
  5.06 s once memoized (*read*, `columnar.md` §6, Filliâtre §3.1). It
  does not share beta-reductions, which closures in values do
  (`elaborators.md` §3, §12).
- **Spans are not in terms.** A hash-consed node is shared by every
  occurrence, so it has no one position. The elaborator reports at the
  syntax node it is elaborating, which names its token (0008 §3).
  Today every TT constructor carries an `FC`
  (`compiler/idris/src/Core/TT/Term.idr:100-124`), which would make two
  equal terms at two places two nodes. The fork already drops them
  where terms persist: a TTC writes no `FC`, and every term node read
  back from one is `emptyFC` (*read*: `Core/TTC.idr:392-477`). So
  Translate, which falls back to the definition's span when a node has
  none (`Frontend/Translate/Terms.idr:67-68`), already names the
  definition, not a column inside it, for every definition it reads
  from a TTC. *Decision:* that is the rule for every definition once
  terms come from the arena. A refusal after elaboration names the
  definition, the callee and the value that grows, which identify the
  site without a span (AGENTS.md asks for the site and the value), and
  each op's MLIR location is its function's (the frontend emits no
  debug information, so nothing else reads a finer span). The user's
  own modules, checked in the same run, lose the column inside a
  definition in those messages; the elaborator's own errors keep it.
  This supersedes the earlier "spans are free: a node names its token",
  which is true of 0008's syntax nodes, not of terms.
- **The loose-bound-variable column is a full word, and checked.** Lean's
  kernel packed the range into 20 bits, and an overflow check that
  returned 0 turned every skip on, a soundness bug found by a failing
  proof (*read* through `elaborators.md` §3:
  `papers/carneiro-2024-lean4lean/main.tex:630-642`). An overflow here is
  an internal error.
- **Ids never leave the arena.** An id is the order a node was first
  interned, which a parallel elaborator's schedule decides; Zig's
  InternPool even packs the creating thread into its indices (*read*
  through `sources/notes/sharded-compilation/whole-program-at-scale.md`
  §7). Whatever leaves the arena (a TTC, a symbol, an instance key,
  MLIR) is written from content: a TTC keeps its tree format, writing
  each term by its structure (`Core/TTC.idr:392-477`), so no id and no
  interning order reaches it, and a name uses the `hash` column (the
  cutover's D18; 0006 D3). Filliâtre's tags do not survive serialization
  either (`columnar.md` §6). *Decision:* A0 does not change the TTC
  format. A format that writes each distinct subterm once would make
  TTCs smaller and loading them a gather, but it is a second change with
  its own cost; it is taken only if 0010's T0 shows TTC loading above 5%
  of elaboration, 0008 D0's rule for a representation change.
- **Two lifetimes, in the id's type.** The arena has a persistent part,
  which holds checked definitions and what TTCs hold, and a temporary
  part for one definition's check or one normalization, dropped when it
  ends. nanoda does the same: each declaration is checked with a fresh
  temporary DAG, dropped once the declaration is verified, and its
  32-bit pointers carry the DAG in bit 31 (*read*:
  `code/nanoda_lib/src/util.rs:34-69, 221-246, 257-265`). Here the
  lifetime is the id's type index, not a bit: a temporary id cannot be
  written into a persistent row, so a dangling id is a type error. A
  result that outlives its check (the checked term, a normal form a
  cache keeps) is interned into the persistent part, one walk of what is
  new, with its hash unchanged; caches that outlive a check key on
  persistent ids only (*decision*). Reason: an arena that only grows
  would keep every intermediate term of every check until exit, and
  the frontend already peaks at 9.1 GB on Chez (0008 §2).

The caches hold only what their key decides (*decision*, from Lean's
kernel and elaborator, *read* through `elaborators.md` §4): a closed,
meta-free term by its id; conversion as sets of successful and failed
pairs, never a union-find or a transitive closure, because conversion
with unfolding is not transitive and a closure would make answers depend
on evaluation order (`code/lean4/src/kernel/type_checker.h:33-41`); a
term with metas only in a transient set, dropped when the check
postponed a constraint (`code/lean4/src/Lean/Meta/ExprDefEq.lean:2438-2480`).

What falls out: syntactic equality is an integer compare; conversion
normalizes only when ids differ; a normal form is computed once per id;
memory is a few large arrays, each one counted cell (0009 D4), not
millions of cells.

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
3. **Share.** A row whose term is closed and meta-free takes the cached
   value of that term id, and rows that meet on such a term are merged,
   so the work is done once. A row on an open term is cached under the
   pair (term id, environment slice), the slice's identity and not its
   contents: two equal environments built apart are not merged, since
   comparing them would hash-cons values (§3). Hash-consing is what
   makes the meeting an id compare.
4. **Compact.** Finished rows scatter their values to the rows waiting on
   them and leave the table; new rows from the step are appended.

Why this shape. A per-element lambda, `tabulate n (\i => ...)`, is `n`
rows in one wavefront: each step runs the lambda's next kind once over
`n` rows, so the interpreter's dispatch is paid once per kind per step,
not once per element. It is NESL's flattening done on the interpreter's
rows at run time, where the compiler cannot do it ahead of time, and a
step appends its rows by Elsman's expansion, built from scan, scatter,
map and gather (*read* through `sources/notes/flattened-data/flattening.md`
§2: `papers/elsman-2019-flattening-by-expansion` §1-3). NESL's own
interpreter paid one library call per vector operation and could not
fuse; it won on very sparse data (10 times Cray Fortran) and lost on
dense data to that overhead (*read* through `flattening.md` §4-5:
`papers/blelloch-1994-portable-nesl` §3.4, §5, Fig. 13), which is why the
dense one-row case is the gate below. Co-dfns writes a whole compiler
as passes over node columns: its tree-transforming pass takes the tree
as the columns `p d t k n lx vb pos end` (parent, depth, type, kind,
name and the rest) and rewrites them whole, by masks and
compaction (*read*: `code/co-dfns/cmp/TT.apl:1-6`; the method is
`papers/hsu-2019-data-parallel-compiler`). HVM2 reduces a global bag of
active redexes from many threads at once, lock-free with atomic
substitutions, and strong confluence makes the number of reductions
independent of their order (*read*:
`papers/taelin-2024-hvm2/HVM2.typst:13, 378, 409-411, 750`). The
wavefront takes the many-redexes-at-once idea and not the atomics: its
rows advance in lockstep in a deterministic order, and 0005 has no
shared heap. smalltt shows what a careful glued evaluator buys over Agda,
Coq, Lean and Idris (*read* through `elaborators.md` §10, which read
smalltt's README at `ea99b0f4`; `code/smalltt/SNAPSHOT.md` lists the
README, but the file is not in the tree).

**One row is the plain loop.** A deep sequential recursion keeps one live
row; its step is one kernel over a segment of one, and grouping one row is
one compare. The machine must be as fast there as a direct recursive
evaluator over the same arena; that is the gate of stage A1, and it is a
condition the machine meets, not a choice between two designs. Keller et
al. measured the failure it guards against: a tail-recursive loop ran two
orders of magnitude slower fully vectorised, because vectorisation
prevented a simple loop (*read* through `flattening.md` §4:
`papers/keller-2012-vectorisation-avoidance` §5.4-5.5).

**Deterministic.** The order of rows is the order of the stable sort and
the order rows were appended; the budget counts steps and bytes per
normalization, never time. A call is normalized or deferred identically
on every machine, thread count and shard count.

**Parallel by construction.** Each kernel is data-parallel over its
segment. Once 0003's arrays exist, the kernels are written in its
vocabulary, so the compiler fuses and vectorizes them (§6); once 0005's
shards exist, a segment splits across shards with the same result.

## 5. Arrays in interpreted code

An array value is one value row whose payload is a runtime array cell.
An array operation in interpreted code is its library definition (0003
§3.5), interpreted like any other code: a `tabulate` of `n` elements
appends `n` rows, one per index, to its body's kind segment, so a wide
array is a wide wavefront, which is the case the machine is built for. No
array operation has a second implementation in the runtime for the
interpreter: the library's definition is the one meaning, and its
primitives' meaning is the runtime's (AGENTS.md), so the interpreter and
the compiled program call the same `runtime/` functions for those
primitives and nothing else. The interpreter can, because it is an
idris-mlir program linked with `runtime/` (§1). The fork already keeps
the other fold out: a primitive applied to constants stays a call in the
checked definition instead of becoming the constant Idris's own
implementation computes (*read*:
`upstream/18-elaboration-primitive-folding/README.md`, which lists
Chez's `"+inf.0"` against the runtime's `inf`; the second meaning the
evaluator gives a Char's text is `upstream/20-evaluator-char-text`). So
the interpreter's call into `runtime/` is the one fold of a primitive
anywhere. A chain of array operations in interpreted
code is not fused: fusing interpreted code would be a second compiler. A
closed array expression whose cost is past the budget is a top-level
constant, computed once by the compiled program at its first demand
(§2) (*conjecture* until A4 measures that a wide `tabulate` interprets
fast enough).

## 6. The interpreter is 0003's second consumer

The interpreter is written in the typed array style it interprets. Its
tables are 0003 arrays, its kernels are 0003 programs over them, and its
columns take 0009's layouts (one tensor per field, 0003 §4.5). When
0003's stage 3 lands, a kernel such as "gather the environment slot of
every variable row, then build the value rows" is a `map` over a gather,
which `linalg-fuse-elementwise-ops` fuses into one loop with no
intermediate array, checked by `idr-expect`'s `fused`. The compiler that
fuses user programs fuses its own evaluator.

Most of a step is not that kind of kernel, and this is said plainly:
the stable group by term kind is a counting scatter, finishing rows is a
compaction, and writing results back is a scatter (0003 §4.4, §11).
Those are where `linalg` is weakest and where fusion stops, as it must at
a size-changing operation. They are ordinary 0003 programs over
`select`, `idr.scatter`, `idr.scan` and `filter` (the two ops are
0003's, kept until upstream has a combining scatter and a region-combiner
scan, 0003 D16), compiled by the same lowering, and their cost is
measured at A5, not assumed. Every combiner they need is one integer
op, the only case 0003's structuring turns into those ops (0003 §4.4,
D16): the group by kind is a counting sort, a histogram of the kind
column, an exclusive scan of it and a scatter, all `addi`; compaction
is `filter`, flags, an exclusive `addi` scan and a scatter without a
combiner. They arrive at 0003's stages 4 and 5, which is why A5 waits
on stage 5 (*decision*).

## 7. Where it runs

In the frontend, where choices are decided. Translate already
monomorphises on demand, with Idris's normaliser doing the type-level
computation (*read*: `Translate/Closed.idr:273`, `normaliseClosed`, and
its uses in `Translate/Instances.idr:178, 212-218, 300`); static
normalization extends that to the value level at the same point, so a
choice computed by recursion reaches the instance decision that needs
it. A closed call needs only its callees, which a module's imports
provide, so normalization runs per module and is cached under the
module's content hash with the rest of its summary (0006 §3.1, §5.3).
**The C++ pipeline never runs program code** (0006 D6: phases 2 to 4 run
none, on any schedule). What leaves the frontend is ordinary IR
(constants, closure constants, memo cells), which the pipeline the
cutover built compiles like any other; no pass of it knows static
normalization exists.

**Stage 0 from A3** (*decision* with the owner's question in 0006 §12,
default taken). `make self`'s stage 0 runs the frontend on Chez
(`tools/self.sh:13-14`). From A3 the normalizer folds a primitive by
calling `runtime/` (§5), which has no meaning there, and a fold computed
with base's primitives on Chez would carry Chez's meaning into stage 1
(upstream/18 lists `"+inf.0"` against the runtime's `inf`), against
AGENTS.md's rule that a primitive's one meaning is the runtime's.
Default: from A3 on, stage 0 is the native frontend built from the last
commit before A3. Stock Idris on Chez builds only that commit's
frontend, which compiles the current source natively into stage 1, so
no fold ever runs on Chez and the interpreter has no host case. Reason:
any test of the host inside the interpreter would be a second path, and
a fold on Chez would put a Chez meaning into output. The same fact, no
meaning of ours on the Chez host, is what 0006 §12 asks about shards,
so the owner answers both together. A3 changes `tools/self.sh`'s stage
0 in the same change; AGENTS.md's Chez exception (the host side of the
frontend) is unchanged, since stock Idris on Chez still builds a
frontend, the seed commit's.

The type checker uses the same arena, machine and caches for conversion,
unification's evaluation and proofs by reflection (0010 builds tabled
search, shape arithmetic, the rewrite ladder and the kernel on top of
it).

## 8. The interactive loop

The interactive loop moved here from 0003 (§3.9 there). `idris-mlir
repl` runs a line as a program, compiled through the same pipeline and
linked as an executable, in a child. There is no JIT in the driver.
The latency rule (1 s from line to output for an expression over arrays
of up to 10⁶ elements) decides whether a resident frontend is built, not
how the line is run (D4). That is running a program, not normalizing
one, and it stays out of compilation. Nothing of it exists today
(*read*: no `repl` in `foreign/idr/lib/Driver`).

*Decision:* it is stage A7, after A0. A line's latency is mostly the
frontend loading what the line imports (*conjecture*: the fork installs
in about 75 s on Chez, HANDOFF.md, and a line compiles almost nothing
of its own), which A0's arena changes, so a
loop measured before A0 would measure a representation about to go
(0008 D0's reason for measuring after the change that replaces what is
measured). A7 builds the loop as a child per line, then measures the
latency rule; a miss builds the resident frontend in the same stage: one
child process that keeps the loaded context between lines and compiles
each line it is sent, a process of ours and never a library loaded at
run time (AGENTS.md). Every line's output is the output of the same
expression compiled as a program by `idris-mlir`, which is its test.

## 9. Rules changed

When A3 lands, in the same change:

- AGENTS.md's paragraph on primitives becomes: "No primitive has an
  implementation in Idris: its one meaning is the runtime's (`runtime/`),
  which folders and the evaluator call too. The compiler has no
  compile-time evaluation feature: it normalizes the static part of the
  program with the type checker's evaluator. Closed calls of total code
  become values within a counted budget, or top-level constants computed
  once, at their first demand, beyond it; partly static calls specialize
  on the arguments that steer control; partial and covering code is
  never normalized."
- AGENTS.md's middle way: "which static normalization, specialization,
  closed sums and defunctionalization compile away".
- README.md: the frontend "normalizes the static part"; no JIT.
- `tests/README.md`: every test of static normalization holds each
  computation twice, once closed and once on a value the program reads
  at run time, against one expected file (D5).

## 10. Staged plan

Each stage passes AGENTS.md's checks on both targets and records compile
times against the stage before, old binary against new binary from a
named saved input, by the measurement rule of the cutover's §10. A stage
that makes the self-compile slower is reworked until it is not, and is
never kept beside the form it replaces.

| Stage | Content | Proof |
| --- | --- | --- |
| A0 | interned names and the hash-consed term arena in the fork, typed ids, its two lifetimes and its 128-bit `hash` column; the fork's evaluator (`Core/Normalise/Eval.idr`, `Quote.idr`, `Convert.idr`) reads terms from the arena, its strategy unchanged; the frontend reads TT from it; TTCs keep their tree format (§3) | identical TTCs and corpus; elaboration of base and the frontend ≥ 1.5× faster than 0010's T0 record; peak resident memory of elaborating them no higher than T0's |
| A1 | the wavefront machine replaces A0's evaluator in one change: weak head normal form and the read-back the checker needs | **the gate,** A1's binary against A0's on the checker's own normalizations (base, the frontend, smalltt's benchmark set), best of five: at most 2% slower where one row is live, and more than 2% faster where many are (a `tabulate` corpus); 2% is the runtime margin of the cutover's §10 applied to the checker as a program (0003 D35 on why not the run-to-run spread). A machine that misses either is reworked before it lands, and until then A0's evaluator is the only one |
| A2 | glued values, the caches of §3, approximate conversion, on the machine | smalltt's benchmark set within 1.5× of smalltt; ≥ 2× over A0 on conversion-heavy files |
| A3 | static normalization in the frontend: closed total calls to values, the frontend's share of control-steering specialization (§2), the counted budget, first-demand constants beyond it; closed array results of words or floats as dense constants, through the lowering 0003's stage 1 brought, and of other elements built at startup (§2); §9's rules; stage 0 from the last commit before A3 (§7, default of 0006 §12) | `tests/programs/eval` and the corpus unchanged in output; every test of static normalization holds its computations closed and on input (D5); byte-identical across thread counts; `make self` green from the native stage 0; no bench program's runtime or peak resident memory worse than the stage before by more than 2% |
| A4 | arrays in interpreted code as wide wavefronts (§5), after 0003's stage 1 | a table of 10⁶ words built by array operations normalizes within the budget; reflection benchmarks ≥ 10× over A2 where they use arrays |
| A5 | the kernels as 0003 programs, after its stage 5 (§6) | `fused` holds on every kernel whose steps are elementwise; wide-wavefront benchmarks faster than A4 |
| A6 | segments across shards, after 0005's P4 | identical results at every shard count; wall time on the A1 corpus recorded |
| A7 | the interactive loop (§8), after A0: a child per line, then the latency rule measured, and the resident frontend built in the same stage if it misses | every line's output equal to the same expression compiled as a program; the latency of the 10⁶-element case recorded on both targets |

A3's memory bound is a *decision*: 2% is the bar the cutover's §10 set for
runtime, applied to what over-budget cells retain until exit. A0's
memory bar is one too: the arena exists to cut memory as well as time
(§3), so a stage that raises the peak has not delivered it.

## 11. Rejected alternatives

- **A JIT or native compilation of reductions** (the deleted `idr-eval`;
  Coq's `native_compute`, 2 to 5 times its bytecode machine, with the
  compiler joining the trusted base, *read* through `elaborators.md` §7):
  a second compiler inside the first, and a fork to contain it.
- **WebAssembly**: a second lowering pipeline plus an embedded engine.
- **A bytecode virtual machine** (Coq's `vm_compute`, same notes, §7): a
  second representation of code beside the arena, which drifts from it.
  The arena is the code.
- **A tree-walking interpreter as the design**: it pays dispatch per
  element and cannot use the vocabulary's primitives across rows. It
  exists only as A0's evaluator, the fork's own on the arena, which A1
  replaces in one change.
- **Fusing interpreted array chains**: a compiler inside the interpreter.
  Expensive chains are first-demand constants.
- **Eager evaluation of every closed call, partial included**: needs a
  divergence budget and gives schedule-sensitive refusals.
- **Over-budget constants computed at startup**: a call the budget
  stopped may hold a failing primitive, which would then fail before the
  program demanded the value (§2).
- **A switch that turns static normalization off**, to run every test
  with and without it: a behaviour-selecting option, which the cutover's
  D2 rules out. D5's twin tests check the same property with one
  compiler.
- **The frontend cloning a function for a constructor its body matches
  on**: the ready set does that (the cutover's §4.8), in one place, on
  first-order code.
- **Hash-consing values, or merging rows on equal environments**: the
  cost Filliâtre measured without the memoization that pays for it (§3).
- **A span in every term node:** two equal terms at two places would be
  two nodes, and the TTCs the fork reads already hold none (§3).
- **One arena that only grows:** every intermediate term of every check
  would live until exit; temporary ids, dropped per check, are nanoda's
  answer and ours (§3).
- **A TTC format with shared subterms inside A0:** a second change in
  the stage whose proof is identical TTCs (§3).
- **A `comptime` keyword or staging annotations**: the types already say
  what is static; the totality checker already says what is safe.
- **Specializing on every constant argument**: one clone per distinct
  value; only control-steering arguments specialize.
- **Normalizing open terms**: supercompilation's code explosion.

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
  demand. The owner's words were "a startup constant"; first demand is
  the precise form, because a call the budget stopped may hold a failing
  primitive (§2).
- D4 (owner, 2026-10-10). The interactive loop runs lines as linked
  executables, outside compilation. There is no JIT in the driver.
- D5 (owner, 2026-10-10; restated 2026-10-14). Static normalization never
  changes a program's output, and the tests show it: each test of static
  normalization holds its computations twice, once closed and once on a
  value read at run time, against one expected file, as
  `compile-time-evaluation` does with `fib 27` and `fib n`. The owner's
  form ran every program test with and without static normalization,
  which needs the switch the cutover's D2 (owner, 2026-10-14) rules out.
- D6. The interpreter is an array program: the wavefront machine over the
  hash-consed arena, one kernel per kind per step. A1's gate is a
  condition it meets, not a fallback.
- D7. One arena, owned here: the fork's elaborator, the checker, the
  frontend and the normalizer read it and never copy it.
- D8. The budget counts steps and bytes; nothing the machine decides
  depends on time, threads or shards.
- D9. The frontend specializes on what decides types and
  representations (types, implementations, shapes a type reduces on);
  the cutover's ready set specializes on known constructors. Reason: one
  specializer per kind of argument.
- D10. Only terms are hash-consed; spans live on syntax nodes, and a
  message after elaboration names the definition, the callee and the
  value, as every definition read from a TTC is named today; the
  loose-bound-variable column is a checked word. Reason: §3.
- D11. Arena ids never reach output; a TTC keeps its tree format, and a
  symbol or a key is written from content. Reason: ids follow the
  elaboration schedule.
- D12. Caches hold only what their key decides: closed meta-free terms by
  id, open terms by (id, environment slice), conversion as success and
  failure sets with no transitive closure, terms with metas in a
  transient set. Reason: Lean's kernel and elaborator (§3).
- D13. The budget stops normalizing and never rejects a program
  (the cutover's D17).
- D14. A0's evaluator is replaced at A1 in one change, measured binary
  against binary; no second evaluator is ever kept for measurement.
  Reason: the cutover's D2 and the measurement rule of its §10.
- D15. The arena has a persistent and a temporary part, the lifetime
  in each id's type; a result that outlives its check is interned into
  the persistent part, and caches across checks key on persistent ids.
  Reason: memory, by nanoda's design (§3).
- D16. The `hash` column is the frontend's content hash, XXH3-128
  (0006 D16), a Merkle hash per node, probed by its low word and never
  trusted alone. Reason: names and summaries are keyed by it (§3).
- D17. The interactive loop is stage A7, after A0, with the latency
  rule deciding the resident frontend in that stage. Reason: the
  latency is mostly loading, which A0 changes (§8).
- D18. A3's closed array results of words or floats are dense
  constants; a closed array result of any other element is built at
  startup. Reason: a dense constant needs a static shape and 0003 §12's
  lowering, which 0003 D40 moved to its stage 1, so both landed with
  the cutover (`LowerGetGlobal`, `Conversion/Arrays.cpp`); this
  proposal remains the producer of closed array results (0003 §12).
- D19. From A3, `make self`'s stage 0 is the native frontend of the
  last commit before A3, by the default of 0006 §12's owner question.
  Reason: a fold calls `runtime/`, which has no meaning on Chez, and a
  host case in the interpreter would be a second path (§7).

## 13. Open question

1. **The restated owner decisions D3 and D5.** Default: the restated
   forms, first-demand constants and twin tests, since startup
   evaluation can fail before a demand and the with-and-without matrix
   needs a switch the cutover's D2 forbids.

What A3's folds mean on the Chez host that runs stage 0 is the owner's
too, asked once in 0006 §12 with the shards question that rests on the
same fact; its default here is D19.
