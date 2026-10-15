# 0009: a data-oriented, array-first frontend

**Status:** proposed 2026-10-10 against `main` at c50d176d; trimmed
2026-10-12; reconciled 2026-10-14 with 0004's pipeline cutover and
decided the same day. Nothing here is built. The tree today
(*measured*, 0002 and 0004 §0): the cutover 0002 designed is committed
and builds on arm64 macOS, where `make test` was 415/415 at 7a27fd34,
before the opt-in SCC pipeline, and again at 552d682a with it off by
default; both runs took the Simplify rounds, and 0004's cutover deletes
the rounds and that pipeline together. x86_64 Linux is NotRun. `make
self` has never finished; 0004's cutover is what it waits on.

The interned names (once part of O1) and the hash-consed term arena
(once O4) moved to 0008, which owns them; this proposal builds the rest
of the frontend's tables on that arena. It is one of the three consumers
of 0003's array style (with 0010's layouts and 0008's interpreter): its
tables are 0003 arrays and its passes 0003 programs. In the queue it
follows 0008. O0 is taken at `make self` with 0011's T0, before 0008's
A0, whose proof is a ratio to that record; O1 onward start after A0,
each with the further needs §8 names.

0004's cutover changes emission first, in its lane L1: closures and
suspensions in symbol form, names derived from content, binder identity,
data types that carry their constructors, the root as the module's one
public function with no mark, the in-place promise as a type fact and
the bytecode handoff (0004 §4.1, D28, D29, D36). L1 makes them on today's trees. This proposal consumes
those changes and decides how its tables hold each one (§4.10); its O2
writes 0004's bytecode from an ops table. O3 is the relational core's
first consumer (0013's R3), so 0013, parked until a consumer starts
(0013 §0), is taken up for it: R1 and R2 are built before O3. O5's
interval join, O7's constraint store and O8's laws are 0013's too
(its layers 1 to 3).

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
- code: `code/co-dfns` (read: `cmp/TT.apl`), `code/zig`, `code/pareas`,
  `code/simdjson`, `code/smalltt`, `code/lean4`;
- read directly for this text: `papers/hsu-2019-data-parallel-compiler`
  (the repository's text extraction, `hsu-dissertation.pdf.txt`) and
  `papers/langdale-2019-parsing-json/simdjson.tex`.

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
relational parts run on the shared relational core of proposal 0013; the
array parts run on the typed APL of proposal 0003; the layouts are
proposal 0010's. Zig's self-hosted compiler is the existence proof of the
shape: tokens and nodes as `MultiArrayList`s, an untyped IR written to
its cache as its arrays, and an intern pool that is hash-consing over
flat storage (*read* through `columnar.md` §3).

It is not a from-scratch rewrite (0011 §5 rejects that): each stage
changes one representation inside the fork, proved by identical TTCs and
the unchanged corpus.

## 2. Where the time goes (the baseline)

Two records exist, both of stage 0 (the frontend on Chez):

- *Measured* (HANDOFF.md, 2026-10-10, arm64 macOS, at c50d176d): stage 0
  compiling its own sources took 137 s at 9.1 GB peak and emitted a
  405 MB MLIR text module (58,305 functions, 7,664 data types) and a
  74 MB Core. Phases:

  | Phase | Time |
  | --- | --- |
  | checks | 0.4 s |
  | reachable | 4.2 s |
  | translate (TT → Core, monomorphisation on demand) | 81 s |
  | print (Core → MLIR text) | 40 s |
  | write | 0.9 s |

- *Measured* (`bench/profiles/2026-10-14-f0-stage0.md`): the dump 0004's
  F0 starts from, 58,236 functions in 294 MB of generic-form text, about
  140 s to write; 100,198 functions once `idr-isolate` outlines the
  closures.

A third figure, "87 s and 1.8 GB on stage 0", was once given in 0012;
0012 now records that it was written at 4c87ad0f, half an hour before
stage 0 first compiled the whole frontend at c50d176d, and is superseded
by the first record (0012, "Measures"). It is not a record.

Translate and print are 88% of the 2026-10-10 run. Both are pointer
chasing: a worklist over trees of cells, and a tree serialized to text.
Elaboration is not in these profiles (it runs when the fork installs,
about 75 s); 0011's T0 records it. The frontend writes its phases with
`--timing`, one `phase<TAB>ms` line each: today checks, reachable,
translate and emit, with print and write folded into emit (*read*:
`compiler/src/IdrisMLIR/Frontend/Program.idr:84-90, 185-200`;
`Frontend/Driver.idr:17`). It is a record the run writes, not a switch
of behaviour, so 0004's deletion of options does not touch it.

**Decision (D0):** stage O0 measures once, natively, at `make self`, on
the self-compiled frontend and on one commit with 0011's T0, on both
targets; the same run on stage 0 is recorded beside it and is no
target. Reasons: after 0004's cutover emission writes bytecode,
symbol-form closures and content names, so a record taken before it
measures a printer that no longer exists; the stages below change the
self-hosted frontend, and on Chez its representation buys memory and
little else (§6); and 0012's "Measures" already says the Chez figures
measure Chez. Every threshold below is a ratio to O0, and a stage whose
phase is under 5% of the frontend's wall at O0 is not taken: the plan is
ordered by measured cost, and a representation change that cannot move
the total by 5% does not pay for its churn.

## 3. The representation: the compiler's state as a schema

| Table | Columns (structure of arrays) | Precedent |
| --- | --- | --- |
| files | one contiguous byte buffer each | |
| tokens | `kind : u8`, `start : u32` (end from the next start or a length) | Zig's `tokens`, a `MultiArrayList` (*read* through `columnar.md` §3: `code/zig/lib/std/zig/Ast.zig:17-31`) |
| syntax nodes | `kind`, `main_token`, `subtree_size`, in preorder, so every subtree is a contiguous slice `[pre, pre + size)`; variable arity in an `extra` column decoded by `kind` | Zig's node `{tag, main_token, data}` (*read*, same: `Ast.zig:3014-3086`); Co-dfns's node columns (*read*: `code/co-dfns/cmp/TT.apl:1-6`); Carbon's toolchain (*read* through `whole-program-at-scale.md` §7); 0010's packed layout |
| names | interned (0008 §3) | |
| terms | the hash-consed arena (0008 §3) | |
| metas | `meta → solved term | unsolved` | |
| constraints | `(lhs, rhs, ctx, blocked_on)` | |
| defs | `def → name, type, body, multiplicity, totality, location` | already a growable `Linear.Array` in the fork (*read*: `compiler/idris/src/Libraries/Data/Table.idr:3-12`, the only module of the fork that imports `Linear.Array`; 0012's ledger, its improvements table); 0003's stage 1 moves it onto base's `Data.IOArray`, keeping its doubling growth, and drops the fork's `mlir-linear` dependency, since a table held in a `Ref` cannot hold an `LArray` (0003 §3.8, D38) |
| instances | `(def, compile-time arguments…) → instance`, with its requester | Translate's monomorphisation and its requester chain (`Translate/Instances.idr:99-117`) |
| core | per function instance, its body in preorder: `kind`, `subtree_size`, binder ids, operand slices; the function row holds its location, and nodes hold none (0008 §3) | full Core, Translate's output and Emit's input (`IdrisMLIR/Term.idr:330-362`), where today every node carries a `Loc` (`:82-112`) |
| datatypes | `datatype → key, constructor slice, in-place fact`; a constructor row holds its field types, their quantities and its role | the declarations 0004 makes types carry (§4.10) |
| ops | `(opcode, operands, result types, region slices)` | MLIR bytecode |

Two layout choices, each a *decision*:
- **`subtree_size`, not `parent`.** The interval `[pre, pre + size)` is
  what name resolution (§4.4) and lambda lifting (§4.10) read; a parent
  column is derived from it where a pass needs one, and storing both
  would keep one fact twice. The derivation is two passes: with +1 at
  each node and −1 one past its subtree, a node's depth is the inclusive
  prefix sum at it, less one; and a node's parent is the last earlier
  node one level up, which is how Hsu derives Co-dfns's parent vector
  from its depth vector (*read*: `papers/hsu-2019-data-parallel-compiler/
  hsu-dissertation.pdf.txt:719-760`). Co-dfns itself keeps both `p` and
  `d` columns (`TT.apl:2`); its passes walk up the tree, and ours read
  intervals.
- **Core is a table.** It is the state Translate hands to Emit; a tree of
  it beside the tables would be one concept held twice, so it moves to
  the table in the stage that moves Emit (O2).

What falls out at once:
- **Equality is an integer compare** for names, terms and types. This also
  makes the comparison in a 0012 regression ("names, constants and
  scopes compared as values") an id compare; the proofs that regression
  lost stay 0012's feature 6 (O1).
- **Spans are free.** A syntax node names its token, a token its offset;
  no location side-table threads through every function. Terms carry no
  spans, since a hash-consed term is shared by every occurrence (0008
  §3); the elaborator reports at the syntax node it elaborates, and
  Translate and Emit at the definition, as they already do for every
  definition read from a TTC (0008 §3, D10).
- **Memory is a few large arrays,** each one counted cell (0010 D4), not
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
  prefix XOR over the unescaped-quote bits, which simdjson computes with
  one carry-less multiply by a word of ones, or with shifts and XORs
  (*read*: `papers/langdale-2019-parsing-json/simdjson.tex:595-598,
  1488`); nested-comment depth is a prefix sum of ±1; token starts come
  from compaction. *Decision:* the shift-and-XOR form, six steps for a
  64-bit word in plain Idris over `Bits64`. The pinned LLVM has a
  target-independent `llvm.clmul` (*read*:
  `L/include/llvm/IR/Intrinsics.td:1642`), but reaching it would add a
  primitive, with its meaning in `runtime/`, for one kernel; it is taken
  only if O0 leaves lexing above D0's 5%.
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
semantic context; its speed targets unverified). 0012's ledger already
turned the combinator library into direct code (*read*: 0012, "The
ledger", the row for `Libraries.Text.Parser.Core`: each combinator is
its clause, with no interpretation step); this goes one step further,
so its output is tables, not cells. Operator resolution (fixities are
declared in source) stays sequential, over a flat token slice.

**Decision (D2):** parsing stays sequential. Parallel parsing (Pareas,
`code/pareas`, `papers/voetter-2021-gpu-frontend-thesis`) is
research-grade, and Idris's grammar (user fixities, indentation,
interpolation, pragmas) is its hardest case; 0011 §2.7 already defers GPU
front ends.

### 4.4 Name resolution is an interval join
- Each binder covers a preorder interval `[pre, pre + size)`. A reference
  resolves to the deepest binder of the same name whose interval contains
  it: an Allen "during" join with a max-depth fold. The join is 0013's
  layer 1, whose kernels include Allen masks (0013 §3), with bumbledb's
  interval machinery (`src/allen.rs`) as the reference implementation;
  the frontend keeps no join of its own (§9). *Conjecture* that it beats
  a scope stack; measured at stage O5, whose threshold a sequential
  resolution over the same tables meets if the join does not.
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
representation (*conjecture*, sized by 0008's A0 and A2 targets):
- **Hash-consing and id-keyed caches** for weak-head normal forms and
  conversion results (0008 A0, A2; 0008 D12 says which keys may be
  cached).
- **Postponement as semi-naive evaluation.** Each round's newly solved
  metas (the delta) join the blocked constraints on `blocked_on`; only
  the matches wake. The fork retries every postponed constraint by
  scanning all guesses until none progresses
  (`compiler/idris/src/Core/Unify.idr:1515-1522`, `solveConstraints`;
  *read* at ccaba89c, first through `elaborators.md` §11), which is
  quadratic or worse when many wait.
- **Meta-to-meta unification as union-find,** since a solution is an
  equality; conversion's cache is never one, since conversion with
  unfolding is not transitive (0008 §3). Batched conversion dedups
  `(id, id)` pairs before any normalisation.
- **One evaluator.** Normalization runs on 0008's wavefront machine over
  the arena, which also serves the program's static normalization.
- **Shape arithmetic as a group-by.** A polynomial is a sparse column of
  `(monomial, coefficient)`; normalising it is a sort and a segmented
  sum (the library tactic's canonical form, 0003 §3.7; 0011 §2.4).
- **Parallelism across definitions and modules,** not within one (0011
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
  which 0003 §6 lets a reduction reassociate, written by the frontend as
  an `scf.parallel` with an `scf.reduce` (*read*: 0003 §6, §9, §11,
  D32).
- **Size-change termination** is half an array program. Composing two
  size-change graphs (`composeChange`,
  `compiler/idris/src/Core/Termination/SizeChange.idr:143`) is a semiring
  matrix product over `Algebra/SizeChange.idr`'s semiring (*read*:
  `Smaller | Same | Unknown` at `:10`, `plusNeutral = Unknown` at `:58`),
  encoded with the sum's zero at 0 (`Unknown = 0`), not by constructor
  order; the fork's `Libraries/Data/SparseMatrix.idr` is already DCSR in
  lists (`Matrix a = Vector (Vector1 a)`, `:111-112`). The closure is not
  a sum, and the fork holds it twice (*read*; 0011 §2.6). The
  elaborator's `calcTerminating` closes `(f, g, graph)` triples
  transitively within each component (`Core/Termination/SizeChange.idr:
  77-85, 183-208`, used at `:565`); `upstream/21-termination-closure`
  restricted that closure to components and did not remove it (PINS.md,
  `termination-closure`: "the elaborator's checks of `total` code still
  do"). The frontend's loop verdict (`loopsTerminate`, `:455-459`,
  called from `Translate/Recursion.idr:137`) extends walks from each
  function `f` breadth first and keeps, per function reached, only the
  weakest graphs of the walks to it, an antichain under `weaker`
  (`loopsFrom`, `:413-452`; `weaker`, `:383-384`). Summing graphs would
  merge walks whose verdicts differ, so the closure is a relational
  fixpoint with subsumption (0013 D9), with the composition as its
  kernel; the triple closure goes for it (0011 D13). This supersedes the
  earlier text, which said the fork no longer keeps the triples.

*Decision:* both folds are executed as 0003's stage 7, "the multiplicity
check as a sparse reduction and size-change composition as a semiring
product", whose gate is this proposal's (identical verdicts on base and
the corpus), and O6 below names that stage rather than doing the work
twice. The same stage deletes the triple closure: `loopsFrom` carries
the call path the checker's message names (`SizeChange.idr:565-574`),
and the proof is identical totality verdicts and messages (0011 §2.6,
D13). Reason: the kernels are 0003 programs over its sparse arrays
(stage 6) and finite semirings (stage 4), so 0003's plan owns when they
land; one piece of work has one place in the queue, and one analysis
held twice is one representation too many.

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

The refusal of an unbounded instance set is decided per request, before
the request joins (*read*). Before 0004's cutover three checks made it
(*read* at ccaba89c). `checkRecursion` refuses a recursive
component that passes a type or an implementation other than its own,
unchanged, judged on Idris's size-change graphs (`checkComponent`,
`Translate/Recursion.idr:130-165`). `growing` refuses an instance whose
argument at a runtime parameter is deeper than at an instance of the same
definition in its requester chain, and names the parameter
(`Translate/Instances.idr:62-93`). A third check counts:
`instanceBudget` refuses the 4,097th instance of one definition as
`unsupported (compile-time budget)` (`Translate/Instances.idr:33-39,
110-112`; the rule `CompileBudget`, `IdrisMLIR/Rule.idr:37, 69`), a
backstop for calls Idris's size-change graphs do not record (under
`assert_total`, or through a local function).

0004's cutover replaced them with 0012's feature 2 (0004 D40): one
rule on request chains, which `growing` became
(`chainGrows`, called from `request`, `Translate/Instances.idr`): a new
instance is refused when, against an ancestor instance of the same
definition on its chain, its static arguments are smaller in no
position and larger in one; the rule names the definition, the
argument and both keys, and it deleted `checkComponent`'s blanket
refusal, `growing` as a check of its own, and the count with its rule
(0012 D4). Its argument for ending without a count is Dickson's lemma
on each chain and König's on the finitely branching request tree
(*conjecture* there, checked by its stage's tests).

*Decision:* O3 changes no acceptance. In the semi-naive form the
frontend's refusals, as they stand when O3 lands, are filters on the
delta, applied to each new row against its requester chain, so a refusal
still names the site and the value that grows, as AGENTS.md requires of
a megamorphic construct. Since 0004's cutover took 0012's feature 2,
that is the request-chain rule alone, and the fixpoint has no count,
since the rule's argument is what ends it. Reason: what is refused is a
rule of the language the frontend accepts, which 0012 owns, and a
representation change proved by identical Core (D5) cannot also change
what is accepted. The earlier "O3's fixpoint has no count" rests on
feature 2, whose argument is what lets the fixpoint end without one.

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
`M/lib/Bytecode/Writer/BytecodeWriter.cpp:885-940`). How an entry is
written is 0004's decision (§4.1 there, D36): every attribute and type as its
assembly, the bytecode's own fallback encoding (`emitAttrOrTypeRawImpl`,
`BytecodeWriter.cpp:889-892`). The pinned writer takes that form itself
for every mutable type, which 0004's data types that carry their
constructors are ("We don't currently support custom encoded mutable
types", `:894-899`), and the LLVM dialect, whose identified structs are
the precedent, registers no type encodings at all
(`M/include/mlir/Dialect/LLVMIR/LLVMDialectBytecode.td:371`, empty
`elems`). A recursive data type then names itself in its text, so no
cycle of section entries reaches the reader, which hangs on one
(`upstream/03-bytecode-deferred-quadratic/README.md`). *Decision:* the
table's part is the numbering: each distinct attribute and type is one
entry, printed once, a data type's body with it, and every use is its
number. *Conjecture:* with 7,664 data types (HANDOFF, 2026-10-10) those
entries are small next to the ops; O0 measures them, and a custom
encoding becomes an upstream patch only if O0 names the section as a
cost.

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
  body in the scope it is written in (`IdrisMLIR/Term.idr:20-22, 108-110`).
  In the core table a lambda is a slice `[pre, pre + size)`; its
  captures are the variable occurrences in the slice whose binder lies
  outside it, one interval query over the binder-depth column (§4.4's
  machinery); lifting it is a gather of the slice into a function row.
  The ops table holds no region for a lambda.
- **Names derived from content.** A generated function's name is its
  owner's name and a hash of its structural key (0004 §4.1). The core
  table's subtree hash is one segmented fold in reverse preorder, so every
  lambda's key hash is one pass; binders are hashed by depth, never by
  name, as instance keys already print them (`Translate/Keys.idr:308-313`).
  Two lambdas of one owner with one key are one function: emission writes
  a name once, a hash join against the names written. A collision of two
  different keys on one hash is caught where the name is interned, by
  comparing the keys, and is an internal error, never a merge (0007 §11
  rejects trusting hash equality).
- **Instance symbols.** An instance's symbol is its key printed
  (`IdrisMLIR/Term.idr:364-372`), and the print is not injective by
  design: an instance is its definition and its compile-time arguments
  up to the names of binders, "its identity, which nothing prints", and
  the key is how it reads (*read*: `Translate/Keys.idr:3-10`; `render`
  prints an erased argument as `_` and drops an as-pattern's name,
  `:282, 287`). So today a key that prints like an earlier one takes
  `'n`, its repeat number in program order (`Emit/Index.idr:21-60`), a
  counter. 0007 §4.5 needs the symbol made injective, so that the
  repeats go. In the tables an instance's identity is its definition's
  id and its argument term ids, which are de Bruijn terms of the arena,
  so the binder names are already out and its hash is the combination of
  their `hash` columns (0008 §3). *Decision:* whether a key's symbol
  carries its identity hash is decided by the key alone. The printer
  reports whether its print dropped part of the identity, as it prints:
  a dotted erased argument printed `_`, an as-pattern's name, a binder
  it skips, a meta's arguments, an annotation a lambda or a let leaves
  unprinted, an implicit kind it prints as another, an inner name it
  prints for a `DN`, or an integer constant whose type its `show` leaves
  out (*read*: `render`, `Translate/Keys.idr:270-305`; `Show Constant`,
  `compiler/idris/src/Core/TT/Primitive.idr:133-148`, prints `5` for an
  `Int` and a `Bits8` alike). A key whose print dropped nothing is its
  symbol; a key whose print dropped something is its print, a `;`, and
  the low 64 bits of its identity hash as 16 hex digits (0007 §4.5,
  D16). No print ends in `;` and 16 hex digits, since a print shows `;`
  only inside a string or character literal, which ends in its quote,
  and names never contain it (*recalled*: Idris's identifier and
  operator characters exclude `;`; L1 checks it), so a suffixed symbol
  never equals a bare one. Two identities whose symbols still meet are caught where the
  name is interned, by full equality, and that is an internal error,
  never a merge (0007 §4.4, §4.5), which also exposes a loss the printer
  failed to report. Reasons: one key's symbol is a function of that key,
  never of the program's other keys, which 0007 §4.5 needs for names
  stable under an unrelated edit and its S1 fixture checks; the common
  symbol stays readable; and the print keeps what it is for, how an
  instance reads. The cost: a lossy key carries its hash even when no
  other key prints like it. This supersedes two earlier forms: "the
  printed key must be injective" as a property of the print itself,
  which the key's own design rules out; and a hash on every key of a
  group that prints alike, which renamed an existing key when the
  program gained one printing like it, making one key's name depend on
  another (0007 §11 rejects that for widened names, and for the same
  reason).
- **Data types that carry their constructors.** `!idr.data<@T>` names a
  symbol today (`include/idr/IR/IdrTypes.td:25-29`) whose constructors
  are `idr.ctor` ops in an `idr.data` body (`IdrOps.td:117, 163`), which
  patterns find by scanning the module (0004 §6). 0004 makes the type
  carry its declaration, an identified type whose body is set once
  (0004 §4.1, D29), built by its lane L5 and emitted by L1 together
  (0004 §10); the `idr.data` and `idr.ctor` ops go, and an op names a
  constructor by its name within its value's type. The body holds the
  constructors in tag order with their field types, the sum's kind, the
  frontend's `instance`, the registry's role and the in-place promise
  (D29). The datatypes table is that body for what the frontend makes:
  one row per data instance, its key, its constructor slice in tag order
  with field types, quantities and roles, and its in-place fact; the
  closure and memo sums are defunctionalization's, made in C++.
  Emission writes each type once (§4.9). The role a pass needs (the
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
  The frontend fills it from the registry, which already holds what the
  frontend knows of library definitions and which 0004 makes name the
  types rebuilt in place and exclusive (`Registry/Libraries.idr`;
  0004 §4.1); `idr-demand` checks it on every program.
- **The root.** The root is the module's one public `idr.func`, as the
  module rules already find it; 0004 adds no `root` property, which
  would hold publicity twice, and stops writing the discardable
  `idr.program` mark (0004 §4.1, D28; written today at
  `Dialect/Idr.idr:30-33`). Full Core already holds the root as one
  function id (`Source.root`, `IdrisMLIR/Term.idr:354-362`), named
  `$idris-mlir.root`, a fixed name and no counter
  (`Translate/Programs.idr:188`). In the tables it is that id, a single
  value beside the function table rather than a column, and the ops
  table writes that function's op public and every other private, as
  Emit does today (`Emit/Declarations.idr:71`).

## 5. What appears once the state is tables

- **The compiler's invariants become laws.** "Every reference resolves to
  exactly one binder" is a key. "Every parent precedes its child" is an
  order law. "Every instance is reachable from `main`" is a containment.
  They run on every compilation, as the dialect's verifier runs after
  every pass (0004 §4 stage 6), as compiled law queries over the
  compiler's own state (*decision*: a check that runs in one build and
  not in the build that ships is a behaviour that depends on the build,
  which 0004 D2 rules out, and it would be off where the backstop
  matters; O8's proof bounds its cost), as bumbledb's judge runs its laws (`../bumbledb/proposals/0003-idris-port.md`
  §4.3, "Laws compile too": a key is a group count above one, a
  containment an anti-join; `crates/bumbledb/src/schema/judge.rs`), a
  mechanical backstop for "reject with a named rule, never miscompile".
- **Incremental compilation has an obvious shape** (*conjecture*, not
  planned here): the tables as a persisted image, an edit as a delta, and
  only the groups a delta touches re-judged, as bumbledb's
  `judge_incremental` does (`src/schema/judge.rs:217`). It is rustc's
  query system with a database underneath instead of a memo table.
  0007's cache (its S9) is where it would land.
- **The relational core gets its first consumer.** The interval join
  and the law queries are layer 1 of proposal 0013, the instance
  fixpoint, the constraint store and the size-change closure layer 2,
  and union-find layer 3 (0013 §3).

## 6. Limits, honestly

- **The elaborator will not vectorize.** Expect smalltt-style gains from
  representation and caching, not array-language ones. Lexing,
  desugaring, multiplicity checking, emission and the fixpoint phases are
  the array-shaped ones.
- **Bootstrap order.** The data-oriented frontend pays off in speed only
  once idris-mlir compiles arrays well: 0003's array core and contiguous
  runs, both unbuilt (contiguous runs have no proposal). That is why it
  follows self-hosting: on Chez it would cut memory and little else.
- **Sequential is fine.** Zig runs its semantic analysis on one thread
  and fans out only code generation, and builds itself in 8.6 s with a
  separate code generation thread (*measured* by its developers, read
  through `whole-program-at-scale.md` §7); Carbon keeps its data in
  vectors and parses without semantic context, though its speed targets
  are talk figures, unverified (same note). Parallelism is taken only
  where a phase is regular and measured hot.

## 7. Rules it keeps

- **Idris 2, fully.** The frontend still consumes checked TT and its
  definition context; only the representation of that TT changes.
- **One thing, one representation.** A table replaces its tree; no pass
  keeps the old form beside the new one. The relational mechanisms live
  once, in 0013's library.
- **No primitive implemented in Idris;** array and relational operations
  lower through the array core and the dialect.
- **Names from content.** No arena id, row id or arrival order reaches a
  symbol, a key or a file (0004 D18; 0007 D3).
- **Facts in types.** A data type carries its constructors and their
  roles; quantities stay in the types.
- **No refusal by budget** (0004 D17): a megamorphic construct is refused
  by a rule that names the site and the growing value. The frontend's
  instance count went with 0012's feature 2, in 0004's cutover (0004
  D40), and its fuel (`whnf 64`, `implementationOf 64`) goes in 0005
  (its D4), not with a stage here (§4.8).
- **Deterministic, byte-identical outputs;** both targets.

## 8. Staged plan, ordered by measured cost

| Stage | Needs | Content | Proof |
| --- | --- | --- | --- |
| O0 | `make self` | one baseline, natively at `make self` on one commit with 0011's T0, on both targets, the stage-0 run beside it: self-compile phases by `--timing`, peak memory, elaboration of base | committed record under `bench/profiles/` |
| O1 | 0008's A0 | token SoA over 0008's interned names; names compared by id. This replaces the name-equality traversal in 0012's ledger. The equality proofs stay 0012's feature 6 | identical TTCs and corpus |
| O2 | 0003's stage 1; 0004's L1 | the core, datatypes and ops tables; lambdas lifted by interval queries, names from slice hashes, instance symbols by §4.10's rule, data types written once, the root as one id; 0004's bytecode written from the ops table by a size scan and a scatter | the same bytecode bytes as 0004's L1 writer on the corpus and the stage-0 self-compile; emission ≥ 5× faster than O0 |
| O3 | 0013's R1 and R2 (O3 is R3) | Translate as semi-naive over the instance table; reachable as its query; the refusals as they stand as filters on the delta (after 0012's feature 2, its request-chain rule and no count) | identical Core; translate ≥ 3× faster than O0 |
| O4 | | (moved: the term arena is 0008's A0) | |
| O5 | 0013's R1 for the join | flat parse tree; name resolution as the interval join | identical TTCs; parse plus resolve no slower than 0008's A0 |
| O6 | 0003's stages 4 and 6 | executed as 0003's stage 7 (§4.7): multiplicity checking as a semiring fold; size-change composition as a semiring product (the closure stays the fork's `loopsFrom` until 0013); the elaborator's `calcTerminating` triple closure deleted for `loopsFrom`, which carries the call path its message names (0011 D13) | identical totality and multiplicity verdicts, and identical totality messages, on base and the corpus |
| O7 | 0013's R2 and R4 | elaborator constraint store and postponement on 0013's core; meta-to-meta unification on its union-find | 0008 A2's targets; identical TTCs |
| O8 | 0013's R1 | the compiler's invariants as law queries on every compilation (§5) | a seeded violation of each law is caught by name; the queries under 5% of the frontend's wall at O0 |

The thresholds of O2 and O3 are *decisions*, ratios to O0's phase: the
factor a representation change must buy on a phase D0 has shown to be
worth one. A stage that misses its threshold is reworked or not taken,
and never kept beside the tree it replaces (0004 §10). The order among
the stages whose needs are met is O0's measured cost, largest phase
first (D0); on the 2026-10-10 record that is translate (O3), then
emission (O2), then the rest (*conjecture* until O0).

## 9. Rejected alternatives

- **A from-scratch frontend:** loses Idris 2 compatibility and the corpus
  proofs (0011 §5).
- **Full flattening of everything** (DPH): 0010 rejects it; layouts are
  chosen where the access pattern pays.
- **Untyped `u32` ids, Zig style:** the type checker can carry the
  invariant for free (D1).
- **A parallel parser now:** D2.
- **The frontend's own Datalog or union-find:** that would be a second
  copy of 0013's mechanism.
- **Lambdas as regions in the ops table, outlined later:** the round trip
  0004 deletes (`idr-isolate`).
- **Symbols numbered by order of appearance** (`'n` repeats, `.lam<n>`):
  creation order reaching output (0004 D18).
- **A count of instances as the refusal:** a budget deciding acceptance
  (0004 D17); 0012's request-chain rule replaces it (0012 D4).
- **O3 changing which programs are accepted:** a representation change
  is proved by identical Core; the rule that decides acceptance is
  0012's (§4.8).
- **An injective printed key:** the key's print is how an instance
  reads, and making it carry every distinction would make every symbol
  carry what only lossy ones need (§4.10).
- **A hash on every key of a group that prints alike:** one key's
  symbol would depend on another key, so an unrelated edit could rename
  it (§4.10; 0007 §4.5).
- **Data types as symbols a lookup resolves:** the nominal form 0004
  replaces with types that carry their declaration.
- **Both `subtree_size` and `parent` stored:** one is derived from the
  other in two passes (§3).
- **A carry-less multiply for the quote mask:** a new primitive for one
  kernel, before O0 shows lexing matters (§4.1).
- **The 0012 figure of 87 s and 1.8 GB as a baseline:** 0012 itself
  records that it predates stage 0 compiling the whole frontend (§2).

## 10. Decisions

- D0. Measure first (O0), natively at `make self` on one commit with
  0011's T0, on both targets, the stage-0 run beside it as no target; a
  stage whose phase is under 5% of the frontend's wall at O0 is not
  taken.
- D1. Every table id is a type indexed by its table, erased to a word; a
  read through it is unguarded (0003 D4); an `extra` slice is decoded by
  a type its `kind` decides.
- D2. Lexing is array-shaped; parsing stays sequential, writing tables.
- D3. Translate is a semi-naive fixpoint over the instance table; its
  refusals, as they stand when O3 lands, are filters on the delta that
  name the site and the growing value; O3 changes no acceptance, and
  the fixpoint has no count, since 0012's feature 2 landed with 0004's
  cutover.
- D4. Emission writes 0004's bytecode from an ops table by a size scan
  and a scatter; every attribute and type is one textual entry of its
  section (0004 §4.1), printed once, a data type's body with it.
- D5. Every stage is proved by identical TTCs, the unchanged corpus and,
  from O2, identical bytecode; no stage keeps the tree it replaces.
- D6. The arena is 0008's; this proposal never keeps a second copy of a
  term.
- D7. 0004's emission changes have one form each in the tables: a lambda
  is a core slice lifted with its captures by an interval query; a
  generated name is the owner and the slice's hash; an instance's symbol
  is its printed key, followed by `;` and the low 64 bits of its
  identity hash when the printer reports that its print dropped part of
  the identity, a rule of the key alone (§4.10; 0007 §4.5); a data type is a datatypes row with its
  constructors, quantities, roles and in-place fact; a binder is a row;
  the root is one function id.
- D8. Syntax nodes and Core store `subtree_size`, not `parent`.
- D9. Full Core is a table in preorder, moved in O2 with Emit; the
  function row holds the location, and nodes hold none.
- D10. The quote mask is a prefix XOR by shifts in plain Idris; a
  carry-less multiply waits on O0.
- D11. O6 is executed as 0003's stage 7, with this proposal's gate,
  and deletes the elaborator's triple closure for `loopsFrom` (0011
  D13).
- D12. O3, O5's join, O7 and O8 are built on 0013; O3 is its first
  consumer and takes it out of parking.
- D13. The law queries run on every compilation, never in test builds
  alone, under 5% of the frontend's wall at O0 (§5). Reason: 0004 D2,
  and a backstop for "never miscompile silently" is needed in the build
  that ships.
- D14. An instance's symbol carries its identity hash exactly when its
  key's print dropped part of the identity, a rule of the key alone
  (§4.10). Reason: no symbol may depend on another key (0007 §4.5).

There is no open question for the owner.
