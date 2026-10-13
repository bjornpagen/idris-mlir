# 0007: a data-oriented, array-first frontend

**Status:** proposed (2026-10-10), against `main` at c50d176d; trimmed
2026-10-12. Nothing here is built. The interned names (once part of O1)
and the hash-consed term arena (once O4) moved to 0006, which owns them; this proposal
builds the rest of the frontend's tables on that arena. It is one of the
three consumers of 0003's array style (with 0008's layouts and 0006's
interpreter): its tables are 0003 arrays and its passes 0003 programs.
It starts after self-hosting and after 0006's A0. O2 is decided by 0001's
parse measurement. O3 and O7 wait on the relational core (0011), which is
parked, so they are parked with it.

**Sources.** Under `sources/`: `code/co-dfns` and
`papers/hsu-2019-data-parallel-compiler` (a compiler as array programs),
`code/zig` (tokens and AST as structure-of-arrays), `code/pareas`
(Voetter's GPU front end), `code/simdjson` (bitmask classification and
prefix-XOR string parity), `papers/elsman-2019-flattening-by-expansion`,
`papers/filliatre-2006-hash-consing`, `code/smalltt`, `code/lean4`,
`papers/jordan-2016-souffle`. None of them was re-read for this draft:
claims that rest on them are marked *recalled*.

**Claims** are marked: *read*, *measured*, *recalled*, *conjecture*,
*decision*.

## 1. What it changes

Today the frontend (the fork in `compiler/idris` and
`compiler/src/IdrisMLIR`) keeps its state as trees of heap cells and
walks them with recursive functions (*read*: `Frontend/Translate.idr`,
`Term.idr`, `Emit/`). This proposal makes the compiler's state a small set
of **columnar tables keyed by integer ids**, and each pass **a function
from tables to tables**, built from whole-table operations: scans,
gathers, scatters, compaction, segmented folds, joins and fixpoints.

It is Brooks's "show me your tables" applied to the compiler itself, and
it is the same data model as bumbledb (relations as columnar images,
SIMD kernels, Free Join, semi-naive fixpoints). The relational parts run
on the shared relational core of proposal 0011; the array parts run on
the typed APL of proposal 0003; the layouts are proposal 0008's.

It is not a from-scratch rewrite (0009 §5 rejects that): each stage
changes one representation inside the fork, proved by identical TTCs and
the unchanged corpus.

## 2. Where the time goes (the baseline)

*Measured* (HANDOFF.md, 2026-10-10, arm64 macOS): stage 0 compiling its
own sources takes 137 s at 9.1 GB peak and emits a 405 MB MLIR text
module (58,305 functions, 7,664 data types). Phases:

| Phase | Time |
| --- | --- |
| checks | 0.4 s |
| reachable | 4.2 s |
| translate (TT → Core, monomorphisation on demand) | 81 s |
| print (Core → MLIR text) | 40 s |
| write | 0.9 s |

Translate and print are 88% of the run. Both are pointer chasing: a
worklist over trees of cells, and a tree serialized to text. Elaboration
is not in this profile (it runs when the fork installs, about 75 s); 0009
T0 records it.

0010 records a different self-compile figure (87 s, 1.8 GB on stage 0).
**Decision (D0):** stage O0 re-measures both on one commit before any
change, and every target below is a ratio to that record.

## 3. The representation: the compiler's state as a schema

| Table | Columns (structure of arrays) | Precedent |
| --- | --- | --- |
| files | one contiguous byte buffer each | |
| tokens | `kind : u8`, `start : u32` (end from the next start or a length) | Zig's tokenizer (*recalled*) |
| syntax nodes | `kind`, `main_token`, `subtree_size` (or `parent`), in preorder, so every subtree is a contiguous slice; variable arity in an `extra` column | Co-dfns, Carbon's toolchain (*recalled*); 0008's packed layout |
| names | interned (0006 §3) | |
| terms | the hash-consed arena (0006 §3) | |
| metas | `meta → solved term | unsolved` | |
| constraints | `(lhs, rhs, ctx, blocked_on)` | |
| defs | `def → name, type, body, multiplicity, totality` | already a growable `Linear.Array` in the fork (*read*: 0010's ledger) |
| instances | `(def, type arguments…) → instance` | Translate's monomorphisation |
| ops | `(opcode, operands, result types, region slices)` | MLIR bytecode |

What falls out at once:
- **Equality is an integer compare** for names, terms and types. This also
  replaces a 0010 regression ("names, constants and scopes compared as
  values") without waiting for 0010's feature 6.
- **Spans are free.** A node names its token, a token its offset; no
  location side-table threads through every function.
- **Memory is a few large arrays,** one count per region (0008 D4), not
  millions of cells. The 9.1 GB peak is the first thing this should cut,
  on Chez as well as natively (*conjecture*).

### 3.1 Typed indices: what Idris adds to data-oriented design

The known weakness of data-oriented code is that every id is a `u32`:
stale indices, a token id used as a node id, a parent pointer that points
forward. In Zig or C++ that is discipline. Here it is a type, erased:

```idris
-- sketch: an id is indexed by the table it indexes, erased to a word
NodeId : (t : Tree) -> Type                      -- a Fin (size t)
parent : (i : NodeId t) -> (p : NodeId t ** LT p i)  -- preorder: parents first
```

`idr-in-bounds` erases each bounds check it proves, and `LT p i` makes
every upward walk total. **Decision (D1):** every table id is a type
indexed by its table; no pass handles a bare `Bits32` id.

## 4. Each phase as array operations

### 4.1 Lexing: classify, scan, compact
- A byte-class kernel produces bitmasks; string-literal parity is a
  prefix XOR (simdjson, *recalled*); nested-comment depth is a prefix sum
  of ±1; token starts come from compaction.
- A DFA can also run as a scan over composed transition functions,
  because composition is associative (Hillis and Steele 1986, *recalled*).
  Taken only if the classify-and-scan form leaves the lexer measurably
  slow.
- These are bumbledb's kernel shapes: its `exec/kernel/filter.rs` and
  `compact.rs` (*read*).

### 4.2 Layout
A token's column is its offset minus the last newline before it: one
max-scan. Block structure from columns needs a stack; the stack is an
array, with no allocation per token.

### 4.3 Parsing
A sequential parser with an explicit stack writes the preorder node
arrays: no recursion, no closures, as Carbon does (*recalled*). 0010's
ledger already turned the combinator library into direct code (*read*);
this goes one step further, so its output is tables, not cells. Operator
resolution (fixities are declared in source) stays sequential, over a
flat token slice.

**Decision (D2):** parsing stays sequential. Parallel parsing (Pareas,
*recalled*) is research-grade, and Idris's grammar (user fixities,
indentation, interpolation, pragmas) is its hardest case; 0009 §2.7
already defers GPU front ends.

### 4.4 Name resolution is an interval join
- Each binder covers a preorder interval `[pre, pre + size)`. A reference
  resolves to the deepest binder of the same name whose interval contains
  it: an Allen "during" join with a max-depth fold, which is bumbledb's
  interval machinery (`Allen` masks, interval keys) used directly
  (*conjecture* that it beats a scope stack; measured at stage O5).
- De Bruijn conversion follows from a binder-depth scan: index = depth at
  the reference − depth at the binder − 1.
- Imports and namespaces are a join of references against module export
  tables.

### 4.5 Desugaring
`do`, `where`, records and implicit-argument insertion are masked maps
over the kind column. A node that expands into k nodes is count, then
exclusive scan for offsets, then scatter: flattening by expansion
(Elsman 2019, *recalled*).

### 4.6 Elaboration: representation, not SIMD
A bidirectional elaborator with metavariables is irregular and
order-dependent within one definition. The gains here are from the
representation (*conjecture*, sized by 0006's A0 and A2 targets):
- **Hash-consing and id-keyed caches** for weak-head normal forms and
  conversion results (0006 A0, A2).
- **Postponement as semi-naive evaluation.** Each round's newly solved
  metas (the delta) join the blocked constraints on `blocked_on`; only
  the matches wake. No rescans of a worklist.
- **Meta-to-meta unification as union-find;** batched conversion dedups
  `(id, id)` pairs before any normalisation.
- **One evaluator.** Normalization runs on 0006's wavefront machine over
  the arena, which also serves the program's static normalization.
- **Shape arithmetic as a group-by.** A polynomial is a sparse column of
  `(monomial, coefficient)`; normalising it is a sort and a segmented
  sum (the library tactic's canonical form, 0003 §3.7; 0009 §2.4).
- **Parallelism across definitions and modules,** not within one (0009
  §2.7).

### 4.7 Multiplicities and termination are semiring folds
- **QTT usage checking** groups variable occurrences by binder, folds
  each group in the 0/1/ω semiring, and compares with the declared
  multiplicity: a segmented reduction. The fork already has the semiring
  (*read*: `compiler/idris/src/Algebra/ZeroOneOmega.idr`,
  `Algebra/Semiring.idr`). Occurrences grouped by binder are a
  compressed level, so the fold is a `sparse_tensor.reduce` over a CSR
  array of `i8`, `Rig0 = 0`, `Rig1 = 1`, `RigW = 2`, plus
  `minui(addi(a, b), 2)`: a finite semiring whose laws the fork proves,
  which 0003 §6 lets a reduction reassociate (*read*: 0003 §6, §9, §11).
- **Size-change termination** is half an array program. Composing two
  size-change matrices is a semiring matrix product over
  `Algebra/SizeChange.idr`'s semiring (*read*: `Smaller | Same | Unknown`,
  `Same` the product's neutral, `Unknown` the sum's), encoded with the
  sum's zero at 0 (`Unknown = 0`), not by constructor order; the fork's
  `Libraries/Data/SparseMatrix.idr` is already DCSR in lists. The closure
  is not a sum: the checker keeps a set of `(f, h, matrix)` triples
  (*read*: `Core/Termination/SizeChange.idr:415-417`), and summing them
  would merge call paths that must stay apart, so the closure is a
  relational fixpoint (0011), with the composition as its kernel. 0009
  §2.7 already names this.

### 4.8 Translate is semi-naive Datalog over the instance table
Each round:
1. the new instances (the delta) gather their bodies;
2. type arguments are substituted, memoised on `(term id, substitution
   id)`;
3. call sites are found by a filter on node kind;
4. a hash join against the instance table drops the instances already
   known;
5. what remains is the next delta.

"Reachable" (4.2 s) is the same query without substitution. 0010's rule
(refuse when an instance set grows without bound) is exactly the case in
which Datalog with function symbols stops terminating, so the refusal has
a precise meaning in this representation: the delta never empties.

### 4.9 Print is bytecode serialization
Map each op to its encoded size, exclusive-scan the sizes into offsets,
scatter-write each op at its offset. With MLIR bytecode instead of a
405 MB text module, both the printer and the C++ side's parse shrink
(*conjecture*; HANDOFF names a bytecode rule, R7, as the measure).

## 5. What appears once the state is tables

- **The compiler's invariants become laws.** "Every reference resolves to
  exactly one binder" is a key. "Every parent precedes its child" is an
  order law. "Every instance is reachable from `main`" is a containment.
  In test builds they run as compiled law queries over the compiler's own
  state (bumbledb's judge, `../bumbledb/proposals/0001-idris-port.md`
  §4.3), a mechanical backstop for "reject with a named rule, never
  miscompile".
- **Incremental compilation has an obvious shape** (*conjecture*, not
  planned here): the tables as a persisted image, an edit as a delta, and
  only the groups a delta touches re-judged, as bumbledb's
  `judge_incremental` does. It is rustc's query system with a database
  underneath instead of a memo table.
- **The relational core gets its first consumer.** The constraint store,
  union-find, the interval join, the instance fixpoint and the
  size-change closure are layers 1 and 2 of proposal 0011.

## 6. Limits, honestly

- **The elaborator will not vectorize.** Expect smalltt-style gains from
  representation and caching, not array-language ones. Lexing,
  desugaring, multiplicity checking, emission and the fixpoint phases are
  the array-shaped ones.
- **Bootstrap order.** The data-oriented frontend pays off in speed only
  once idris-mlir compiles arrays well: 0003's array core and contiguous
  runs, both unbuilt. That is why it follows self-hosting: on Chez it
  would cut memory and little else.
- **Sequential is fine.** Zig and Carbon are fast with sequential
  data-oriented front ends (*recalled*). Parallelism is taken only where a
  phase is regular and measured hot.

## 7. Rules it keeps

- **Idris 2, fully.** The frontend still consumes checked TT and its
  definition context; only the representation of that TT changes.
- **One thing, one representation.** A table replaces its tree; no pass
  keeps the old form beside the new one. The relational mechanisms live
  once, in 0011's library.
- **No primitive implemented in Idris;** array and relational operations
  lower through the array core and the dialect.
- **Deterministic, byte-identical outputs;** both targets.

## 8. Staged plan, ordered by measured cost

| Stage | Content | Proof |
| --- | --- | --- |
| O0 | one baseline: self-compile phases, peak memory, elaboration of base (with 0009 T0) | committed record |
| O1 | token SoA over 0006's interned names (A0); names compared by id. This replaces the name-equality traversal in 0010's ledger. The equality proofs stay 0010's feature 6 | identical TTCs and corpus |
| O2 | ops table and MLIR bytecode emission, if 0001's parse measurement takes bytecode | identical module after a bytecode round trip; print ≥ 5× faster than O0 (*conjecture*) |
| O3 | Translate as semi-naive over the instance table; reachable as its query | identical Core; translate ≥ 3× faster than O0 (*conjecture*) |
| O4 | (moved: the term arena is 0006's A0) | |
| O5 | flat parse tree; name resolution as the interval join | identical TTCs; parse plus resolve no slower than 0006's A0 |
| O6 | multiplicity and size-change checking as semiring folds | identical totality and multiplicity verdicts on base and the corpus |
| O7 | elaborator constraint store and postponement on 0011's core | 0006 A2's targets; identical TTCs |
| O8 | the compiler's invariants as law queries in test builds | a seeded violation of each law is caught by name |

The thresholds marked *conjecture* become decisions once O0 records the
baseline.

## 9. Rejected alternatives

- **A from-scratch frontend:** loses Idris 2 compatibility and the corpus
  proofs (0009 §5).
- **Full flattening of everything** (DPH): 0008 rejects it; layouts are
  chosen where the access pattern pays.
- **Untyped `u32` ids, Zig style:** the type checker can carry the
  invariant for free (D1).
- **A parallel parser now:** D2.
- **The frontend's own Datalog or union-find:** that would be a second
  copy of 0011's mechanism.

## 10. Decisions

- D0. Measure first (O0); the two recorded self-compile figures are
  reconciled on one commit.
- D1. Every table id is a type indexed by its table, erased to a word.
- D2. Lexing is array-shaped; parsing stays sequential, writing tables.
- D3. Translate is a semi-naive fixpoint over the instance table, and an
  unbounded instance set is the refusal 0010 already names.
- D4. Emission is bytecode from an ops table.
- D5. Every stage is proved by identical TTCs and the unchanged corpus;
  no stage keeps the tree it replaces.
- D6. The arena is 0006's; this proposal never keeps a second copy of a
  term.
