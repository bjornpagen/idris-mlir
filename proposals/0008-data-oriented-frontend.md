# 0008: a data-oriented, array-first frontend

**Status:** proposed 2026-10-10 against `main` at c50d176d; trimmed
2026-10-12; reconciled 2026-10-14 with 0004's pipeline cutover. Nothing
here is built. The tree today: the cutover 0002 designed is committed
and builds on arm64 macOS, where the last gate (`make test` 415/415;
0004 §3.3) ran the default Simplify rounds, not the opt-in SCC pipeline
that landed beside them and that 0004 deletes; x86_64 Linux has not run
(NotRun).

The interned names (once part of O1) and the hash-consed term arena
(once O4) moved to 0007, which owns them; this proposal builds the rest
of the frontend's tables on that arena. It is one of the three consumers
of 0003's array style (with 0009's layouts and 0007's interpreter): its
tables are 0003 arrays and its passes 0003 programs. In the queue it
follows 0007; its stages start after `make self` and 0007's A0.

0004's cutover changes emission first, in its lane L1: closures and
suspensions in symbol form, names derived from content, binder identity,
data types that carry their constructors, the in-place promise as a type
fact and the bytecode handoff (0004 §4.1). This proposal consumes those
changes and decides how its tables hold each one (§4.10); its O2 writes
0004's bytecode from an ops table. O3 and O7 wait on the relational core
(0012), which is parked, so they are parked with it.

**Sources.** Under `sources/`:
- notes: `notes/flattened-data/columnar.md` §3 (Zig's `MultiArrayList`,
  AST, ZIR and InternPool, read from `code/zig`), §6 (hash-consing), §8
  and §9; `notes/flattened-data/flattening.md` §2 (Elsman's expansion);
  `notes/type-checking/elaborators.md` §3 to §5 and §11 (the fork's
  elaborator, read in `compiler/idris/src`);
  `notes/sharded-compilation/whole-program-at-scale.md` §7 (Zig, Carbon,
  Unison);
- papers: `hsu-2019-data-parallel-compiler`,
  `elsman-2019-flattening-by-expansion`, `filliatre-2006-hash-consing`,
  `jordan-2016-souffle`, `langdale-2019-parsing-json`,
  `mytkowicz-2014-data-parallel-fsm`, `voetter-2021-gpu-frontend-thesis`;
- code: `code/co-dfns`, `code/zig`, `code/pareas`, `code/simdjson`,
  `code/smalltt`, `code/lean4`.

bumbledb is read at `../bumbledb` (c0e7708a): its kernels
`crates/bumbledb/src/exec/kernel/filter.rs` and `compact.rs`, its interval
machinery `src/allen.rs`, its judge `src/schema/judge.rs`, and the port
`proposals/0003-idris-port.md` (once numbered 0002). A claim that rests
on a source not re-read is marked *recalled*; one read through a note
names the note.

**Claims** are marked: *read*, *measured*, *recalled*, *conjecture*,
*decision*.

## 1. What it changes

Today the frontend (the fork in `compiler/idris` and
`compiler/src/IdrisMLIR`) keeps its state as trees of heap cells and
walks them with recursive functions (*read*: `Frontend/Translate.idr`,
`Term.idr`, `Emit/`). TT is upstream's `Term`, a recursive family with an
`FC` in every constructor (`compiler/idris/src/Core/TT/Term.idr:100-124`);
full Core, Translate's output, is another tree (`IdrisMLIR/Term.idr:1-25,
82-110`). This proposal makes the compiler's state a small set of
**columnar tables keyed by integer ids**, and each pass **a function
from tables to tables**, built from whole-table operations: scans,
gathers, scatters, compaction, segmented folds, joins and fixpoints.

It is Brooks's "show me your tables" applied to the compiler itself
(*recalled*), and it is the same data model as bumbledb (relations as
columnar images, SIMD kernels, Free Join, semi-naive fixpoints). The
relational parts run on the shared relational core of proposal 0012; the
array parts run on the typed APL of proposal 0003; the layouts are
proposal 0009's. Zig's self-hosted compiler is the existence proof of the
shape: tokens and nodes as `MultiArrayList`s, an untyped IR written to
its cache as its arrays, and an intern pool that is hash-consing over
flat storage (*read* through `columnar.md` §3).

It is not a from-scratch rewrite (0010 §5 rejects that): each stage
changes one representation inside the fork, proved by identical TTCs and
the unchanged corpus.

## 2. Where the time goes (the baseline)

Three records exist, and they disagree:

- *Measured* (HANDOFF.md, 2026-10-10, arm64 macOS): stage 0 compiling its
  own sources took 137 s at 9.1 GB peak and emitted a 405 MB MLIR text
  module (58,305 functions, 7,664 data types). Phases:

  | Phase | Time |
  | --- | --- |
  | checks | 0.4 s |
  | reachable | 4.2 s |
  | translate (TT → Core, monomorphisation on demand) | 81 s |
  | print (Core → MLIR text) | 40 s |
  | write | 0.9 s |

- *Measured* (0011, "Measures"): 87 s and 1.8 GB on stage 0, with no
  phases recorded.
- *Measured* (`bench/profiles/2026-10-14-f0-stage0.md`): the dump 0004's
  F0 starts from, 58,236 functions in 294 MB of generic-form text, about
  140 s to write; 100,198 functions once `idr-isolate` outlines the
  closures.

Translate and print are 88% of the 2026-10-10 run. Both are pointer
chasing: a worklist over trees of cells, and a tree serialized to text.
Elaboration is not in these profiles (it runs when the fork installs,
about 75 s); 0010's T0 records it.

**Decision (D0):** stage O0 measures once, on one commit after 0004's
cutover, and reconciles the three records. After the cutover emission
writes bytecode, symbol-form closures and content names, so a record
taken before it measures a printer that no longer exists. Every
threshold below is a ratio to O0, and a stage whose phase is under 5% of
the frontend's wall at O0 is not taken: the plan is ordered by measured
cost, and a representation change that cannot move the total by 5% does
not pay for its churn.

## 3. The representation: the compiler's state as a schema

| Table | Columns (structure of arrays) | Precedent |
| --- | --- | --- |
| files | one contiguous byte buffer each | |
| tokens | `kind : u8`, `start : u32` (end from the next start or a length) | Zig's `tokens`, a `MultiArrayList` (*read* through `columnar.md` §3: `code/zig/lib/std/zig/Ast.zig:17-31`) |
| syntax nodes | `kind`, `main_token`, `subtree_size`, in preorder, so every subtree is a contiguous slice `[pre, pre + size)`; variable arity in an `extra` column decoded by `kind` | Zig's node `{tag, main_token, data}` (*read*, same: `Ast.zig:3014-3086`); Co-dfns, Carbon's toolchain (*recalled*); 0009's packed layout |
| names | interned (0007 §3) | |
| terms | the hash-consed arena (0007 §3) | |
| metas | `meta → solved term | unsolved` | |
| constraints | `(lhs, rhs, ctx, blocked_on)` | |
| defs | `def → name, type, body, multiplicity, totality` | already a growable `Linear.Array` in the fork (*read*: 0011's ledger, `proposals/0011-self-host-features.md:51`; `compiler/idris/src/Libraries/Data/Table.idr`) |
| instances | `(def, compile-time arguments…) → instance`, with its requester | Translate's monomorphisation and its requester chain (`Translate/Instances.idr:99-117`) |
| core | per function instance, its body in preorder: `kind`, `subtree_size`, binder ids, operand slices | full Core, Translate's output and Emit's input (`IdrisMLIR/Term.idr:330-362`) |
| datatypes | `datatype → key, constructor slice`; a constructor row holds its field types, their quantities and its role | the declarations 0004 makes types carry (§4.10) |
| ops | `(opcode, operands, result types, region slices)` | MLIR bytecode |

Two layout choices, each a *decision*:
- **`subtree_size`, not `parent`.** The interval `[pre, pre + size)` is
  what name resolution (§4.4) and lambda lifting (§4.10) read; a parent
  column is one segmented scan of it, and storing both would keep one
  fact twice.
- **Core is a table.** It is the state Translate hands to Emit; a tree of
  it beside the tables would be one concept held twice, so it moves to
  the table in the stage that moves Emit (O2).

What falls out at once:
- **Equality is an integer compare** for names, terms and types. This also
  replaces a 0011 regression ("names, constants and scopes compared as
  values") without waiting for 0011's feature 6.
- **Spans are free.** A syntax node names its token, a token its offset;
  no location side-table threads through every function. Terms carry no
  spans, since a hash-consed term is shared by every occurrence (0007
  §3); the elaborator reports at the syntax node it elaborates.
- **Memory is a few large arrays,** each one counted cell (0009 D4), not
  millions of cells. The 9.1 GB peak is the first thing this should cut,
  on Chez as well as natively (*conjecture*).

### 3.1 Typed indices: what Idris adds to data-oriented design

The known weakness of data-oriented code is that every id is a `u32`:
stale indices, a token id used as a node id, a parent pointer that points
forward. In Zig or C++ that is discipline: Zig's `extra_data` is decoded
by the reader's choice of type, and a wrong one reads garbage (*read*
through `columnar.md` §9: `Ast.zig:283-305`). Here it is a type, erased:

```idris
-- sketch: an id is indexed by the table it indexes, erased to a word
NodeId : (t : Tree) -> Type                          -- an Index [<size t] (0003 §3.2)
parent : (i : NodeId t) -> (p : NodeId t ** LT p i)  -- preorder: parents first
```

A read through an id has no guard: its type bounds it by the table's
extent, so it is an `index` at its access, unguarded (0003 D4); nothing
proves a check away, and `idr-in-bounds` goes in 0003's purge before this
work starts. `LT p i` makes every upward walk total. **Decision (D1):**
every table id is a type indexed by its table; no pass handles a bare
`Bits32` id, and an `extra` slice is decoded by a type its `kind` decides.

## 4. Each phase as array operations

### 4.1 Lexing: classify, scan, compact
- A byte-class kernel produces bitmasks; string-literal parity is a
  prefix XOR (simdjson, *recalled*: `code/simdjson`,
  `papers/langdale-2019-parsing-json`); nested-comment depth is a prefix
  sum of ±1; token starts come from compaction.
- A DFA can also run as a scan over composed transition functions,
  because composition is associative (Hillis and Steele 1986, *recalled*;
  Mytkowicz et al., `papers/mytkowicz-2014-data-parallel-fsm`, stored and
  *recalled*). *Decision:* taken only if O0 shows the classify-and-scan
  form leaves lexing above D0's 5%.
- These are bumbledb's kernel shapes (*read*): `filter.rs` compares
  fixed-width lanes into a bitmask, then a branchless cursor writes every
  position and advances past survivors; `compact.rs` keeps the items
  whose keep byte is 1.

### 4.2 Layout
A token's column is its offset minus the last newline before it: one
max-scan. Block structure from columns needs a stack; the stack is an
array, with no allocation per token.

### 4.3 Parsing
A sequential parser with an explicit stack writes the preorder node
arrays: no recursion, no closures, as Carbon does (*read* through
`whole-program-at-scale.md` §7: "data in vectors", parsing without
semantic context; its speed targets unverified). 0011's ledger already
turned the combinator library into direct code (*read*:
`proposals/0011-self-host-features.md:50`); this goes one step further,
so its output is tables, not cells. Operator resolution (fixities are
declared in source) stays sequential, over a flat token slice.

**Decision (D2):** parsing stays sequential. Parallel parsing (Pareas,
`code/pareas`, `papers/voetter-2021-gpu-frontend-thesis`) is
research-grade, and Idris's grammar (user fixities, indentation,
interpolation, pragmas) is its hardest case; 0010 §2.7 already defers GPU
front ends.

### 4.4 Name resolution is an interval join
- Each binder covers a preorder interval `[pre, pre + size)`. A reference
  resolves to the deepest binder of the same name whose interval contains
  it: an Allen "during" join with a max-depth fold, which is bumbledb's
  interval machinery (`src/allen.rs`) used directly (*conjecture* that it
  beats a scope stack; measured at stage O5).
- De Bruijn conversion follows from a binder-depth scan: index = depth at
  the reference − depth at the binder − 1.
- Imports and namespaces are a join of references against module export
  tables.

### 4.5 Desugaring
`do`, `where`, records and implicit-argument insertion are masked maps
over the kind column. A node that expands into k nodes is count, then
exclusive scan for offsets, then scatter: Elsman's flattening by
expansion, `expand` built from scan, scatter, map and gather with O(M)
work for M outputs (*read* through `flattening.md` §2).

### 4.6 Elaboration: representation, not SIMD
A bidirectional elaborator with metavariables is irregular and
order-dependent within one definition. The gains here are from the
representation (*conjecture*, sized by 0007's A0 and A2 targets):
- **Hash-consing and id-keyed caches** for weak-head normal forms and
  conversion results (0007 A0, A2; 0007 D12 says which keys may be
  cached).
- **Postponement as semi-naive evaluation.** Each round's newly solved
  metas (the delta) join the blocked constraints on `blocked_on`; only
  the matches wake. The fork retries every postponed constraint by
  scanning all guesses until none progresses
  (`compiler/idris/src/Core/Unify.idr:1516-1523`, `solveConstraints`;
  *read* through `elaborators.md` §11), which is quadratic or worse when
  many wait.
- **Meta-to-meta unification as union-find,** since a solution is an
  equality; conversion's cache is never one, since conversion with
  unfolding is not transitive (0007 §3). Batched conversion dedups
  `(id, id)` pairs before any normalisation.
- **One evaluator.** Normalization runs on 0007's wavefront machine over
  the arena, which also serves the program's static normalization.
- **Shape arithmetic as a group-by.** A polynomial is a sparse column of
  `(monomial, coefficient)`; normalising it is a sort and a segmented
  sum (the library tactic's canonical form, 0003 §3.7; 0010 §2.4).
- **Parallelism across definitions and modules,** not within one (0010
  §2.7).

### 4.7 Multiplicities and termination are semiring folds
- **QTT usage checking** groups variable occurrences by binder, folds
  each group in the 0/1/ω semiring, and compares with the declared
  multiplicity: a segmented reduction. The fork already has the semiring
  (*read*: `compiler/idris/src/Algebra/ZeroOneOmega.idr:11`,
  `Algebra/Semiring.idr`). Occurrences grouped by binder are a
  compressed level, so the fold is a `sparse_tensor.reduce` over a CSR
  array of `i8`, `Rig0 = 0`, `Rig1 = 1`, `RigW = 2`, plus
  `minui(addi(a, b), 2)`: a finite semiring whose laws the fork proves,
  which 0003 §6 lets a reduction reassociate (*read*: 0003 §6, §9, §11).
- **Size-change termination** is half an array program. Composing two
  size-change graphs (`composeChange`,
  `compiler/idris/src/Core/Termination/SizeChange.idr:143`) is a semiring
  matrix product over `Algebra/SizeChange.idr`'s semiring (*read*:
  `Smaller | Same | Unknown` at `:10`, `plusNeutral = Unknown` at `:58`),
  encoded with the sum's zero at 0 (`Unknown = 0`), not by constructor
  order; the fork's `Libraries/Data/SparseMatrix.idr` is already DCSR in
  lists (`Matrix a = Vector (Vector1 a)`, `:111-112`). The closure is not
  a sum. For each function `f` of a component, the checker extends walks
  from `f` breadth first and keeps, per function reached, only the
  weakest graphs of the walks to it, an antichain under `weaker`
  (*read*: `loopsFrom`, `Core/Termination/SizeChange.idr:413-447`;
  `weaker`, `:383-384`; per component, `loopsTerminate`, `:449-459`).
  Summing graphs would merge walks whose verdicts differ, so the closure
  is a relational fixpoint with subsumption (0012), with the composition
  as its kernel. 0010 §2.7 already names it. This supersedes the earlier
  reading of a set of `(f, h, matrix)` triples, which the fork no longer
  keeps.

### 4.8 Translate is semi-naive Datalog over the instance table
Each round:
1. the new instances (the delta) gather their bodies;
2. type arguments are substituted, memoised on `(term id, substitution
   id)`;
3. call sites are found by a filter on node kind;
4. a hash join against the instance table drops the instances already
   known;
5. what remains is the next delta.

"Reachable" (4.2 s) is the same query without substitution.

The refusal of an unbounded instance set is decided per request today,
before the request joins (*read*). `checkRecursion` refuses a recursive
component that passes a type or an implementation other than its own,
unchanged, judged on Idris's size-change graphs
(`Translate/Recursion.idr:120-165`). `growing` refuses an instance whose
argument at a runtime parameter is deeper than at an instance of the same
definition in its requester chain, and names the parameter
(`Translate/Instances.idr:62-93`). In the semi-naive form both are filters
on the delta, applied to each new row against its requester chain, so the
refusal still names the site and the value that grows, as AGENTS.md
requires of a megamorphic construct.

A third check counts: `instanceBudget` refuses the 4,097th instance of
one definition as `unsupported (compile-time budget)`
(`Translate/Instances.idr:33-39, 111-112`), a backstop for calls Idris's
size-change graphs do not record (under `assert_total`, or through a
local function). 0004 D17 deletes refusals by budget. *Decision:* O3's
fixpoint has no count. A delta that would need one means the filters
missed a growing chain, which is an internal error naming the definition,
and the filter is what gets fixed. *Conjecture:* applying `growing`'s
depth test to the compile-time positions of the key as well (types and
implementations, not only runtime shapes) closes the calls Idris does not
record; O3 checks it on base and the corpus before the count goes.

### 4.9 Emission is bytecode serialization
0004 decides the handoff: the frontend writes MLIR bytecode, the driver
reads it with `readBytecodeFile`
(`M/include/mlir/Bytecode/BytecodeReader.h:85-91`), and text stays a dump
(0004 §4.1). That removes the 11.7 s parse (F0) and every text round
trip. How the frontend writes bytecode is this proposal's part: map each
op to its encoded size, exclusive-scan the sizes into offsets,
scatter-write each op at its offset (O2).

The attribute and type section is a table too: the writer numbers each
distinct attribute and type once and writes an offset per entry (*read*:
`M/lib/Bytecode/Writer/BytecodeWriter.cpp:885-940`). A mutable type, which
0004's data types that carry their constructors are, is written as its
textual form inside the bytecode, since the pinned writer has no custom
encoding for one (*read*: `BytecodeWriter.cpp:894-899`, "We don't
currently support custom encoded mutable types"). The LLVM dialect, whose
identified structs are the precedent, registers no type encodings at all
(*read*: `M/include/mlir/Dialect/LLVMIR/LLVMDialectBytecode.td`,
`LLVMDialectTypes` with empty `elems`). *Decision:* each data type's body
is one entry of the types section, printed once; every use is its number.
*Conjecture:* with 7,664 data types (HANDOFF, 2026-10-10) those entries
are small next to the ops; O0 measures them, and a custom encoding for
mutable types becomes an upstream patch only if O0 names them as a cost.

### 4.10 What 0004's emission asks of the tables
Each change 0004 makes to emission (0004 §4.1, §6) has one form in the
tables (*decision* for each). 0004's L1 makes them on today's trees
first; the tables re-express them without changing a byte of what is
emitted (D5).

- **Closures and suspensions in symbol form.** Emit writes each lambda
  and delay as an `idr.func` and names it in `idr.closure` or
  `idr.suspend` with its captures, instead of the `idr.lambda` and
  `idr.delay` regions (`foreign/idr/include/idr/IR/IdrClosureOps.td:46-77`;
  written today at `Emit/Bodies.idr:337-341`) that `idr-isolate` outlines
  (0004 §2.7); a suspension of a value Emit already holds stays the
  region-free `idr.delay %value` (0004 §4.1). Full Core keeps a lambda's
  body in the scope it is written in (`IdrisMLIR/Term.idr:20, 110`). In the core table a lambda is a slice
  `[pre, pre + size)`; its captures are the variable occurrences in the
  slice whose binder lies outside it, one interval query over the
  binder-depth column (§4.4's machinery); lifting it is a gather of the
  slice into a function row. The ops table holds no region for a lambda.
- **Names derived from content.** A generated function's name is its
  owner's name and a hash of its structural key (0004 §4.1). The core
  table's subtree hash is one segmented fold in reverse preorder, so every
  lambda's key hash is one pass; binders are hashed by depth, never by
  name, as instance keys already print them (`Translate/Keys.idr:308-313`).
  Two lambdas of one owner with one key are one function: emission writes
  a name once, a hash join against the names written. A collision of two
  different keys on one hash is caught where the name is interned, by
  comparing the keys, and is an internal error, never a merge (0006 §11
  rejects trusting hash equality). An instance's symbol is its key
  printed (`IdrisMLIR/Term.idr:364-372`). Today a key that prints like an
  earlier one takes `'n`, its repeat number in program order
  (`Emit/Index.idr:21-60`): a counter, which 0004's names from content
  remove. The names table holds the printed key, which must therefore be
  injective.
- **Data types that carry their constructors.** `!idr.data<@T>` names a
  symbol today (`include/idr/IR/IdrTypes.td:25-29`) whose constructors
  are `idr.ctor` ops in an `idr.data` body (`IdrOps.td:117, 163`), which
  patterns find by scanning the module (0004 §6). 0004 makes the type
  carry its declaration, an identified type with a body (0004 §11, open
  question 5). The datatypes table is that declaration: one row per data
  instance, its constructor slice with field types, quantities and roles;
  emission writes each type once (§4.9). The role a pass needs (the
  list's cons, 0004 §6's `listElement` row) is a column the frontend
  fills from the Idris declaration it translated, never a guess from
  shape.
- **Binder identity.** Binder facts are keyed today by (name, span), so
  the synthetic world binder is renamed `$world`
  (`Translate/Programs.idr:182-194`) and holes are a sentinel name
  renamed around Idris's normaliser (`Translate/Closed.idr:173, 287-295,
  471-476`). In the tables a binder is a row and its facts are columns
  keyed by the row id, so neither rename has anything to do; the hole
  case normalises the open term under an environment that binds the holes
  (0004 §4.1).
- **The in-place promise** is a column of the datatypes table for
  `mlir-linear`'s types, written into the type (0004 §4.1), never a flag.

## 5. What appears once the state is tables

- **The compiler's invariants become laws.** "Every reference resolves to
  exactly one binder" is a key. "Every parent precedes its child" is an
  order law. "Every instance is reachable from `main`" is a containment.
  In test builds they run as compiled law queries over the compiler's own
  state, as bumbledb's judge runs its laws (`../bumbledb/proposals/0003-idris-port.md`
  §4.3, "Laws compile too": a key is a group count above one, a
  containment an anti-join; `crates/bumbledb/src/schema/judge.rs`), a
  mechanical backstop for "reject with a named rule, never miscompile".
- **Incremental compilation has an obvious shape** (*conjecture*, not
  planned here): the tables as a persisted image, an edit as a delta, and
  only the groups a delta touches re-judged, as bumbledb's
  `judge_incremental` does (`src/schema/judge.rs:217`). It is rustc's
  query system with a database underneath instead of a memo table.
  0006's cache (its S9) is where it would land.
- **The relational core gets its first consumer.** The constraint store,
  union-find, the interval join, the instance fixpoint and the
  size-change closure are layers 1 and 2 of proposal 0012.

## 6. Limits, honestly

- **The elaborator will not vectorize.** Expect smalltt-style gains from
  representation and caching, not array-language ones. Lexing,
  desugaring, multiplicity checking, emission and the fixpoint phases are
  the array-shaped ones.
- **Bootstrap order.** The data-oriented frontend pays off in speed only
  once idris-mlir compiles arrays well: 0003's array core and contiguous
  runs, both unbuilt (contiguous runs have no proposal). That is why it
  follows self-hosting: on Chez it would cut memory and little else.
- **Sequential is fine.** Zig and Carbon are fast with sequential
  data-oriented front ends (*recalled*). Parallelism is taken only where a
  phase is regular and measured hot.

## 7. Rules it keeps

- **Idris 2, fully.** The frontend still consumes checked TT and its
  definition context; only the representation of that TT changes.
- **One thing, one representation.** A table replaces its tree; no pass
  keeps the old form beside the new one. The relational mechanisms live
  once, in 0012's library.
- **No primitive implemented in Idris;** array and relational operations
  lower through the array core and the dialect.
- **Names from content.** No arena id, row id or arrival order reaches a
  symbol, a key or a file (0004 D18; 0006 D3).
- **Facts in types.** A data type carries its constructors and their
  roles; quantities stay in the types.
- **No refusal by budget** (0004 D17): a megamorphic construct is refused
  by a rule that names the site and the growing value.
- **Deterministic, byte-identical outputs;** both targets.

## 8. Staged plan, ordered by measured cost

| Stage | Content | Proof |
| --- | --- | --- |
| O0 | one baseline after 0004's cutover: self-compile phases, peak memory, elaboration of base (with 0010 T0); the three records reconciled | committed record |
| O1 | token SoA over 0007's interned names (A0); names compared by id. This replaces the name-equality traversal in 0011's ledger. The equality proofs stay 0011's feature 6 | identical TTCs and corpus |
| O2 | the core, datatypes and ops tables; lambdas lifted by interval queries, names from slice hashes, data types written once; 0004's bytecode written from the ops table by a size scan and a scatter | the same bytecode bytes as 0004's L1 writer on the corpus and the stage-0 self-compile; emission ≥ 5× faster than O0 |
| O3 | Translate as semi-naive over the instance table; reachable as its query; the refusals as filters on the delta; no count | identical Core; translate ≥ 3× faster than O0 |
| O4 | (moved: the term arena is 0007's A0) | |
| O5 | flat parse tree; name resolution as the interval join | identical TTCs; parse plus resolve no slower than 0007's A0 |
| O6 | multiplicity checking as a semiring fold; size-change composition as a semiring product (the closure stays the fork's `loopsFrom` until 0012) | identical totality and multiplicity verdicts on base and the corpus |
| O7 | elaborator constraint store and postponement on 0012's core | 0007 A2's targets; identical TTCs |
| O8 | the compiler's invariants as law queries in test builds | a seeded violation of each law is caught by name |

The thresholds of O2 and O3 are *decisions*, ratios to O0's phase: the
factor a representation change must buy on a phase D0 has shown to be
worth one. A stage that misses its threshold is reworked or not taken,
and never kept beside the tree it replaces (0004 §10).

## 9. Rejected alternatives

- **A from-scratch frontend:** loses Idris 2 compatibility and the corpus
  proofs (0010 §5).
- **Full flattening of everything** (DPH): 0009 rejects it; layouts are
  chosen where the access pattern pays.
- **Untyped `u32` ids, Zig style:** the type checker can carry the
  invariant for free (D1).
- **A parallel parser now:** D2.
- **The frontend's own Datalog or union-find:** that would be a second
  copy of 0012's mechanism.
- **Lambdas as regions in the ops table, outlined later:** the round trip
  0004 deletes (`idr-isolate`).
- **Symbols numbered by order of appearance** (`'n` repeats, `.lam<n>`):
  creation order reaching output (0004 D18).
- **A count of instances as the refusal:** a budget deciding acceptance
  (0004 D17).
- **Data types as symbols a lookup resolves:** the nominal form 0004
  replaces with types that carry their declaration.
- **Both `subtree_size` and `parent` stored:** one is a scan of the
  other.

## 10. Decisions

- D0. Measure first (O0), after 0004's cutover; the three recorded
  self-compile figures are reconciled on one commit; a stage whose phase
  is under 5% of the frontend's wall at O0 is not taken.
- D1. Every table id is a type indexed by its table, erased to a word; a
  read through it is unguarded (0003 D4); an `extra` slice is decoded by
  a type its `kind` decides.
- D2. Lexing is array-shaped; parsing stays sequential, writing tables.
- D3. Translate is a semi-naive fixpoint over the instance table; its
  refusals are filters on the delta that name the site and the growing
  value; it has no count.
- D4. Emission writes 0004's bytecode from an ops table by a size scan
  and a scatter; a data type is one textual entry of the types section.
- D5. Every stage is proved by identical TTCs, the unchanged corpus and,
  from O2, identical bytecode; no stage keeps the tree it replaces.
- D6. The arena is 0007's; this proposal never keeps a second copy of a
  term.
- D7. 0004's emission changes have one form each in the tables: a lambda
  is a core slice lifted with its captures by an interval query; a
  generated name is the owner and the slice's hash; an instance's symbol
  is its injective printed key; a data type is a datatypes row with its
  constructors, quantities and roles; a binder is a row.
- D8. Syntax nodes and Core store `subtree_size`, not `parent`.
- D9. Full Core is a table in preorder, moved in O2 with Emit.

There is no open question for the owner.
