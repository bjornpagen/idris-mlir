<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0011: a data-oriented, array-first frontend

**Amended by P0 (2026-10-21, `0000-mlir-native.md`).** Absorbed whole
into the cutover with O6 and O7 (D44, D69), written by its lanes rather
than after self-hosting; each stage's bar is still a ratio measured once
`make self` holds (C136). The rule that skips a stage under 5% of the
frontend's wall goes (C142): "whole" means every stage. O7's
meta-to-meta unification keeps its own union-find in the checker,
`compiler/checker` (D107, C233), with no shared e-graph engine.

**Status (2026-10-22, read at e3b93a77):** open; nothing of its own is
built, as no step of the cutover is built until the whole is (D56), and
§0 lists what it stood on at 77eaa5b1. Every stage is P0's (D44, D69),
written by the cutover's lanes against P0 §5's contracts, none of it
after self-hosting. P0 §7 places each: 0011's baseline record with S0
(its F0), O2 as the Emit of the new dialect (F8, C136), O3 and O8 after
R1 and R2 (F9), O1 and O5 with the checker, O6 and O7 with what they
stand on (D69). The order is the cutover's, by what each stage stands on
(D56), not O0's costs. O0 itself is taken once `make self` holds, on the
commit 0013's T0 measures, and each bar is a ratio to it, measured
natively (C136). One contingency is **SELF-HOST** (§8): a frontend stage
of `make self` that does not fit the owner's machine.

The interned names and the stored terms' columns are 0010's (its A0, in
C183's form); this proposal builds the rest of the frontend's state as
tables on them. O3, Translate's instance fixpoint, is 0015's first
consumer (R1 and R2 come before it); O5's join, O7's constraint store
and O8's laws are 0015's too.

**Sources** (under `sources/`): `notes/flattened-data/columnar.md` §3,
§6, §8, §9 (Zig's `MultiArrayList`, AST, ZIR and InternPool;
hash-consing); `notes/flattened-data/flattening.md` §2 (Elsman);
`notes/type-checking/elaborators.md` §3 to §5, §11;
`notes/sharded-compilation/whole-program-at-scale.md` §7 (Zig, Carbon);
papers `hsu-2019-data-parallel-compiler`,
`elsman-2019-flattening-by-expansion`, `filliatre-2006-hash-consing`,
`jordan-2016-souffle`, `langdale-2019-parsing-json`,
`mytkowicz-2014-data-parallel-fsm`, `voetter-2021-gpu-frontend-thesis`;
code `co-dfns` (`cmp/TT.apl`), `zig`, `pareas`, `simdjson`, `smalltt`,
`lean4`. bumbledb at `../bumbledb` (c0e7708a): `exec/kernel/filter.rs`,
`compact.rs`, `src/allen.rs`, `src/schema/judge.rs`. Claims are marked
*read*, *measured*, *recalled*, *conjecture* or *decision*.

## 0. What it stands on (built elsewhere)

- **Instance symbols** (D7, D14): a key's print, plus `;` and the low 64
  bits of its identity hash exactly when the print loses part of the
  identity (`Frontend/Translate/Keys.idr`, `Term.keyText`). The identity
  is `Proof.Requests.Link`: the definition's `Address` (`Vect 8 (Fin
  256)`, the context index's bytes) and each static argument as a
  prefix-order token list (`Written`); `TS.symbols` makes two identities
  on one symbol an internal error.
- **The bytecode writer** (`MLIR/Bytecode.idr`): each data type written
  once, in the module's table of data types, and each type or attribute
  that can hold one an entry of its dialect's encoding
  (`Encoding/Idr.idr`, generated from ODS; 08647d2e); every other entry
  its text, numbered once; each function encoded as Emit finishes it, so
  no value of the whole module is held.
- **The phase record O0 reads:** `--timing`, one `phase<TAB>ms` line each
  for checks, reachable, translate and emit (`Frontend/Program.idr`,
  `reportTimes`), and Idris's `logTime` phases for the package commands
  (`Frontend/Driver.idr`).
- **No count in the fixpoint O3 inherits:** the growth check decides on
  the whole program, before translation, whether every static argument
  stays within a bound, and Translate's worklist descends within those
  bounds (`Frontend/Growth.idr`, `Proof/Growth.idr`, `Proof/Requests.idr`;
  3fc4d2e4).
- **Constructors by position:** `ConId = (dataId, index : Fin arity)`,
  Idris's tag (`Ids.idr`; `Translate/Types.idr`, `conIdOf`), which is the
  datatypes table's constructor row already.
- **What O2 replaces:** `FnId` and `DataId` stay symbols, checked by
  `TS.symbols` and `ES.keys`; Emit's `Numbering.names`
  (`Emit/Closures.idr`) and Bytecode's `Scope` key by SSA names. O2 makes
  an instance a row with its symbol a print column, and an operand a
  result position.
- `harness/Prims.idr` is the tests' table of Idris's primitives; emission
  does not read it. The ops table's opcodes come from the generated
  dialect modules (`IdrisMLIR.Dialect.*`, from ODS), their one source.

## 1. What it changes

Today the frontend (the checker in `compiler/checker`, Idris's checker
copied into our tree and ours from then on (P0's D118, C233), and
`compiler/src/IdrisMLIR`) keeps its state as trees of heap cells walked
by recursive functions (*read*). TT is the checker's `Term`, with an `FC`
in every constructor (`compiler/checker/src/Core/TT/Term.idr`). Full Core,
Translate's output, is another tree (`IdrisMLIR/Term.idr`, scoped by
`Fin n`, a `Loc` on its nodes). This proposal makes that state a few
**columnar tables keyed by typed ids**, and each pass **a function from
tables to tables**, built from scans, gathers, scatters, compaction,
segmented folds, joins and fixpoints. It is Brooks's "show me your
tables" (*recalled*) and bumbledb's data model, and Zig's self-hosted
compiler is the existence proof (*read* through `columnar.md` §3). It is
no rewrite (0013 §5): each stage changes one representation inside the
checker, proved by identical TTCs and the unchanged corpus.

**Two hosts** (AGENTS.md). The frontend and the checker compile and run under the stock
Idris on Chez and under idris-mlir, forever, so the tables run on Chez
too. A table is plain Idris over base (`Data.IOArray`, `Data.Buffer`,
linear data, definitions with bodies), as the checker's
`Libraries/Data/Table.idr` already is (0009 D38). idris-mlir may speed a
definition through the registry's `Faster` hook, its body staying the one
meaning. A table is never `libs/mlir-array`'s generating set, whose
bodiless `%extern`s serve programs and which no code the stock host runs
may reach. This replaces "its tables are 0009 arrays and its passes 0009
programs": a 0009 or 0015 mechanism serves the frontend through its
plain-Idris layer, and a kernel that exists only as ops waits for one
(D11, D12).

## 2. Where the time goes (the baseline)

Two records, both of stage 0 (the frontend on Chez):
- *Measured* (HANDOFF.md at 77eaa5b1; 2026-10-10, arm64 macOS,
  c50d176d): 137 s at 9.1 GB peak, a 405 MB MLIR text module (58,305 functions, 7,664 data
  types) and a 74 MB Core. Checks took 0.4 s, reachable 4.2 s, translate
  (TT to Core, monomorphisation on demand) 81 s, print 40 s, write 0.9 s.
- *Measured* (`bench/records/2026-10-14-f0-stage0.md`): 58,236
  functions in 294 MB of generic text, about 140 s to write.

Translate and print were 88% of the first run, both pointer chasing.
Both records predate bytecode emission. Elaboration (about 75 s when the
checker installs) is 0013's T0.

**Decision (D0):** O0 measures once, natively, on the self-compiled
frontend, on one commit with 0013's T0, on every target that runs
`make self`, with the
stage-0 run beside it as no target. Every threshold below is a ratio to
O0. Every stage is taken (C142). Reasons: emission has changed since both records, so they measure
a printer that is gone; and the stages change the self-hosted frontend,
since on Chez a representation buys memory and little else (§6).

## 3. The representation: the compiler's state as a schema

| Table | Columns (structure of arrays) | Precedent |
| --- | --- | --- |
| files | one byte buffer each | |
| tokens | `kind : u8`, `start : u32` | Zig's `tokens` (*read* through `columnar.md` §3: `Ast.zig:17-31`) |
| syntax nodes | the flat parse tree (P0's C216): per node its `kind`, its location in its payload and a size column, children before parents, one id where the grammar shares a subtree; variable arity in an `extra` column decoded by `kind` | Zig's nodes (`Ast.zig:3014-3086`); Co-dfns (`cmp/TT.apl:1-6`); Carbon (`whole-program-at-scale.md` §7) |
| names | interned (0010 §3) | |
| terms | while elaborated, an unshared, located tree; once stored, the definition's terms as columns in preorder, shared within the definition, their locations one more preorder column, frozen with it; no arena across definitions, which refer to one another by interned name (P0's C183) | |
| metas | `meta → solved term or unsolved` | |
| constraints | `(lhs, rhs, ctx, blocked_on)` | |
| defs | by `Address`: name, type, body, multiplicity, totality, location | the checker's growable `Table` on base's `IOArray` |
| instances | by `Link`: the instance and its requester | Translate's `Request` and its `chain` (`Translate/State.idr`) |
| core | per function instance, its body in preorder: `kind`, `subtree_size`, binder ids, operand slices; the function row holds the location | full Core, where each node carries a `Loc` |
| datatypes | per family, the declaration Idris checked (P0's D48): its erased indices; a constructor slice in tag order (a constructor's id is its position, as `ConId`), each with the index variables it binds, its equation and its fields with their quantities; no roles (C80); the in-place promise | the declarations data types carry (§4.10) |
| ops | per function: opcode (the generated dialect's), operands as result positions, result types, region slices | MLIR bytecode |

- **A size, not `parent`** (D8). Core is in preorder (D9), so a
  subtree is the interval `[pre, pre + size)` that lambda lifting
  (§4.10) reads. Depth is the inclusive prefix sum of +1 at each node
  and −1 one past its subtree, less one. A parent is the last earlier
  node one level up, as Hsu derives Co-dfns's parent vector (*read*:
  `hsu-dissertation.pdf.txt:719-760`). Syntax nodes are children before
  parents, with a size column and one id where the grammar shares a
  subtree (P0's C216), so every child precedes its parent and a shared
  subtree has more than one parent, which no `parent` column could
  hold. Storing both keeps one fact twice.
- **Core is a table** (D9), moved with Emit in O2. A tree beside it would
  be one concept held twice.

What falls out: equality of names is an integer compare, which also
makes 0014's "compared as values" regression an id compare (its proofs
stay 0014's feature 6), and so is equality of terms within one stored
definition, whose shared subterms are one row; across definitions no row
is shared, the cost C183 accepts. No location is lost: a syntax node
holds its location in its payload (C216), a term being elaborated stays
a located tree, as the elaborator's location reads need, and a stored
term's location is one more preorder column (C183), so Translate and
Emit keep naming the term each op comes from, as they have since
374e0e77. Memory becomes a few large arrays; the
9.1 GB peak is the first thing this should cut, on Chez too
(*conjecture*).

### 3.1 Typed indices

```idris
-- sketch: an id of a frozen table is bounded by its extent, erased to a word
NodeId : (t : Tree) -> Type                          -- Fin (size t)
parent : (i : NodeId t) -> (p : NodeId t ** LT p i)  -- Core, preorder: parents first
child  : (i : NodeId t) -> Fin (arity i) -> (c : NodeId t ** LT c i)
                                                     -- syntax (C216): children first, shared
```

**Decision (D1)**, restated for growth and the two hosts. No pass handles
a bare `Bits32`. Ids come in two kinds, because tables come in two kinds:
- **A frozen table** has an id that is a `Fin` of its extent: a file's
  tokens and nodes, a finished function's core, a data type's
  constructors (`ConId`'s `Fin arity` is the first in the tree). A read
  through it has no guard. Under two hosts that read is base's
  `prim__arrayGet`, which both hosts implement (idris-mlir:
  `Registry/Primitives.idr`), reached through the `Fin`. `readArray`
  returns a `Maybe` whose `Nothing` the type has already excluded, a check
  whose result is thrown away (*read*: `Table.lookupSlot`).
- **A table that grows while it is read** (the context's definitions, the
  instance fixpoint) has an opaque typed identity (`Address`, an instance
  row), and a read through it is a lookup until the table is frozen, as
  `Address` is for definitions.

In Core, `LT p i` makes every upward walk total; in the parse tree,
`LT c i` makes every downward walk total, through a shared subtree too
(C216). An `extra` slice is decoded by a type its `kind` decides.

## 4. Each phase as array operations

### 4.1 Lexing
Byte classes become bitmasks. String-literal parity is a prefix XOR over
the unescaped-quote bits, by shifts and XORs, six steps a `Bits64` in
plain Idris (D10; simdjson's carry-less form, *read*:
`simdjson.tex:595-598, 1488`). Nested-comment depth is a ±1 prefix sum,
and token starts come from compaction (bumbledb's `filter.rs` and
`compact.rs` shapes, *read*). A carry-less multiply (the pinned LLVM's
`llvm.clmul`) would add a primitive for one kernel. It, and a DFA run as a
scan over composed transitions (Mytkowicz, *recalled*), are taken only if
O0 leaves lexing above D0's 5%.

### 4.2 Layout
A token's column is its offset minus the last newline before it, one
max-scan. The block stack is an array, with no allocation per token.

### 4.3 Parsing
**D2:** sequential. The checker's parser is ours, written fresh as
parser combinators that use quantities (P0's D119): the token stream and
the parse state threaded linearly, so idris-mlir updates them in place
and counts nothing; termination proved by the types, a consuming
parser's evidence that it advances; and no type passing. It writes the
flat parse tree (§3, C216). Operator resolution stays sequential.
Parallel parsing (Pareas, Voetter) is research-grade, and Idris's grammar
is its hardest case (0013 §2.7).

### 4.4 Name resolution
O5 lands in two halves (P0's C216). The flat parse tree lands first,
whole: the parser emits its columns (§3), and a decoder gives `PTerm` to
Desugar, Resugar and the printer, so the parser is converted entirely
and nothing reads it half and half. Resolution as R1's interval join
waits on P0 §4's question to the owner, still open, which this
proposal does not settle: Idris resolves names during elaboration,
against the typed environment (`TTImp/Elab/App.idr:54`), and the only
scope over syntax is Desugar's set of bound names, which needs each
clause's pattern variables after operators are regrouped by the fixities
in force, so a join over the parse tree has no reader unless Desugar
reads the columns.

What O5 proposed for resolution, and what the question weighs: a
reference resolves to the deepest binder of its name whose interval
contains it, an Allen "during" join with a max-depth fold, on 0015's
layer 1 (bumbledb's `src/allen.rs` the reference). That it beats a scope
stack is *conjecture*, measured at O5, whose threshold a sequential
resolution over the same tables meets if the join does not. De Bruijn
indices follow from a binder-depth scan. Imports are a join of references
against export tables.

### 4.5 Desugaring
`do`, `where`, records and implicit insertion are masked maps over the
kind column. A node that expands into k nodes is count, exclusive scan,
scatter: Elsman's expansion, O(M) work for M outputs (*read* through
`flattening.md` §2).

### 4.6 Elaboration: representation, not SIMD
The gains here come from representation (*conjecture*, sized by 0010's A0
and A2):
- a stored definition's terms as frozen columns, shared within the
  definition, while a term being elaborated stays an unshared, located
  tree (P0's C183), and caches that hold only what their key decides
  (0010 D12);
- postponement as semi-naive evaluation: each round's newly solved metas
  join the blocked constraints on `blocked_on`, where the checker retries
  every postponed constraint until none progresses (`solveConstraints`,
  `Core/Unify.idr`, *read*);
- meta-to-meta unification as union-find, never the conversion cache,
  since conversion with unfolding is not transitive;
- one evaluator, 0010's machine;
- shape arithmetic as a group-by (0009 §3.7; 0013 §2.4);
- parallelism across definitions, not within one (0013 §2.7).

### 4.7 Multiplicities and termination are semiring folds
QTT usage checking groups occurrences by binder and folds each group in
0/1/ω (`Algebra/ZeroOneOmega.idr`, `Algebra/Semiring.idr`, *read*), a
segmented reduction. Composing size-change graphs (`composeChange`,
`Core/Termination/SizeChange.idr`) is a semiring matrix product over
`Algebra/SizeChange.idr`, with `Unknown` as the sum's zero
(`plusNeutral`). The checker's `SparseMatrix` is already DCSR in lists. The
closure is not a sum. The elaborator's `calcTerminating` still closes
`(f, g, graph)` triples (`SCSet`, `insertGraph`, `findLoops`), restricted
to components by PINS.md `termination-closure`. The frontend's verdict,
`loopsTerminate` (called from `Translate/Recursion.idr`), keeps only the
weakest graphs per function reached (`search`, `Kept`, `weaker`, on
`Dense n from to`). So the closure is a relational fixpoint with
subsumption (0015 D9), and the triple closure goes for `loopsTerminate`,
which carries the call path its message names (0013 D13). D11.

### 4.8 Translate is semi-naive Datalog over the instance table
Each round, the new instances gather their bodies. Type arguments are
substituted, memoised on `(term id, substitution id)`. Call sites are
found by a filter on node kind. A hash join on `Link` drops the
instances already known, and what remains is the next delta. Reachable
is the same query without substitution. **D3:** O3 changes no
acceptance. The growth check has refused what grows before translation
starts (§0), so the fixpoint refuses nothing and has no count.

### 4.9 Emission is bytecode serialization
The frontend writes bytecode and the driver reads it with
`readBytecodeFile` (the cutover's §4.1); the numbering is built (§0).
What O2 adds: each op is mapped to its encoded size, the sizes are
exclusive-scanned into offsets, and each op is scatter-written at its
offset, one function at a time, as the writer streams today. The
attribute and type section stays as §0 has it.

### 4.10 What emission asks of the tables
One form each (D7), in the Emit of the new dialect that O2 is, written
once over the Core table, so today's writer is no reference for its
bytes (P0's C136; D5):
- **Closures and suspensions.** A lambda is a core slice. Its captures
  are the occurrences in it whose binder lies outside, one interval query
  over binder depth (§4.4). Lifting it is a gather into a function row,
  and the ops table holds no region for it. A suspension of a held value
  stays `idr.delay %value`.
- **Content names.** A name is the owner's name and the hash of the
  slice's structural key. The subtree hash is one segmented fold in
  reverse preorder, with binders hashed by depth. Two lambdas of one
  owner with one key are one function: a join against the names written,
  which `ES.keys` checks today. Two keys on one hash are an internal
  error, never a merge (0008 §11).
- **Instances.** An instance's row is keyed by its `Link`, the identity
  the finiteness proof stands on. Its symbol is the built rule (§0). When
  0010's arena gives argument term ids, they replace `Written` only
  together with the proof, so there is one encoding of a static argument.
- **Data types.** One datatypes row per family, the inductive family
  Idris checked (P0's D48): its erased indices and, per constructor in
  tag order, the index variables it binds, the equation it satisfies and
  its fields with their quantities, recursion a back-reference carrying
  an index. Emit writes it as an attribute holding the declaration,
  applied to index terms (`!idr.data<#Vect[n]>`), whose identity is its
  content: no table, no name looked up. No constructor has a role: list
  and numeral are shapes derived from the declaration (C80). The in-place
  fact is the data member's promise (`Promise { None, InPlace }`, C80),
  from the registry's `InPlaceType` (`Registry/Recognized.idr`). It is a
  rule read off the program before counting, which counting honours, and
  a call the exclusivity analysis cannot prove exclusive is refused
  (D24); no pass derives it after the fact, as `idr-demand` did. The
  closure and memo sums are defunctionalization's, in C++. Each type is
  written once (§4.9).
- **Binders.** A binder is a row, and its facts are columns keyed by it.
  What is left of a name standing for a binder is the hole marker
  (`holeMarker`, `MN "idris-mlir-hole"`, `Translate/Closed.idr`), bound
  as environment variables while Idris normalises. In the tables it is a
  row id.
- **The root** is `idr.program`'s `root`, with visibility derived from it
  (the representation wave's D3). It is one function id beside the
  function table, as `Source.root` is, and no visibility is stored.

## 5. What appears once the state is tables

- **Laws** (O8, D13): what the types cannot state runs on every
  compilation as compiled law queries, as bumbledb's judge runs its laws
  (`judge.rs`; `../bumbledb/proposals/0003-idris-port.md` §4.3). Every
  reference resolves to exactly one binder (a key). Every instance is
  reachable from `main` (a containment). "Every parent precedes its
  child" is no law, because D1's `LT p i` makes its breach
  unrepresentable.
- **Incremental compilation** (*conjecture*, not planned): the tables as
  a persisted image and an edit as a delta (bumbledb's
  `judge_incremental`). 0008's S9 would hold it.
- **0015's first consumer:** the interval join and the laws are layer 1;
  the instance fixpoint, the constraint store and the size-change closure
  layer 2; meta-to-meta unification's union-find is the checker's own,
  not layer 3 (P0's D107).

## 6. Limits

- The elaborator will not vectorize: expect smalltt's gains, from
  representation and caching.
- Speed comes only once idris-mlir compiles base's arrays and buffers
  well (contiguous runs, which have no proposal). On Chez it buys memory
  and little else. P0 takes it in the cutover all the same, not after
  self-hosting (D44: "when we're rewriting the whole darn thing we're
  gonna redo everything right"), its bars measured once `make self`
  holds (C136).
- Sequential is fine. Zig runs semantic analysis on one thread and builds
  itself in 8.6 s (*measured* by its developers, read through
  `whole-program-at-scale.md` §7). Parallelism is taken only where a
  phase is regular and measured hot.

## 7. Rules it keeps

Idris 2 fully: checked TT and its context in, only their representation
changed. Two hosts (§1). One thing, one representation: a table replaces
its tree, and the relational mechanisms live once, in 0015's library. No
primitive implemented in Idris. Names from content: no arena id, row id
or arrival order reaches a symbol, a key or a file (the cutover's D18;
0008 D3). Facts in types. No refusal by budget: the fixpoint has no
count, and the frontend's reduction has had no fuel since the
representation wave's D4 and is total since the total wave (d06ed15c).
Deterministic,
byte-identical outputs on every target.

## 8. Staged plan

| Stage | Mark | Needs | Content | Proof |
| --- | --- | --- | --- | --- |
| O0 | P0 (D44); its baseline record is §7's F0, taken once `make self` holds (C136) | `make self` green; 0013's T0 on the same commit | the stage-3 frontend's phases by `--timing`, its peak memory, base's elaboration, and stage 0 beside it. `tools/self.sh` records only the driver's `-mlir-timing`, whose frontend is one scope, and peak memory, so `--timing` goes to `idris-mlir-front` directly | a committed record under `bench/records/` |
| O1 | P0 (D44), §7's F9, with the checker | 0010's A0 | token SoA over the interned names; names compared by id, replacing the name-equality traversal of 0014's ledger (the proofs stay 0014's feature 6) | identical TTCs and corpus |
| O2 | P0 (D44), §7's F8 | 0010's A0 | the Emit of the new dialect, written once over the Core table (C136): the core, datatypes and ops tables; lambdas lifted by interval queries; names from slice hashes; an instance as a row with its symbol as a print column (`TS.symbols` its check); operands as result positions; D48's families, each written once; the root as one id; each function's bytes by a size scan and a scatter | the cutover's checks (D56), with no earlier bytes to match, since today's writer emits the dialect O2 replaces (C136); emission ≥ 5× faster than O0; peak memory not above O0's |
| O3 | P0 (D44), §7's F9 | 0015's R1 and R2 in plain Idris (O3 is R3) | Translate as semi-naive over the instance table keyed by `Link`; reachable as its query, within the growth check's bounds | identical Core; translate ≥ 3× faster than O0 |
| O4 | | | moved: the stored terms' columns are 0010's A0, in C183's form | |
| O5 | P0 (D44), §7's F9, with the checker; two halves (C216) | the checker's parser (D119); for resolution, 0015's R1 and the answer to P0 §4's open question | first, whole, the flat parse tree and its decoder to `PTerm` (C216); then name resolution, its form open (§4.4) | identical TTCs; parse plus resolve no slower than 0010's A0, a bar the open question may change |
| O6 | P0 (D69) | 0009's plain-Idris layer, its stage 7, which comes into P0 with O6 (D69; D11) | multiplicity checking as a semiring fold; size-change composition as a semiring product (the closure stays `loopsTerminate` until 0015); `calcTerminating`'s triple closure deleted for `loopsTerminate` | identical totality and multiplicity verdicts, and identical totality messages, on base and the corpus |
| O7 | P0 (D69) | 0015's R2; the checker's own union-find, which is R4's part in P0 (D107) | the constraint store and postponement on 0015's layer 2; meta-to-meta unification on the checker's own union-find, in Idris | 0010 A2's targets; identical TTCs |
| O8 | P0 (D44), §7's F9 | 0015's R1 | the laws of §5 as queries on every compilation | a seeded violation of each law caught by name; under 5% of the frontend's wall at O0 |

The thresholds are *decisions*: each is the factor a representation
change must buy on a phase D0 has shown to be worth one. A stage that
misses is reworked, never kept beside the tree it replaces, and never
left out, since P0 takes this proposal whole (D44, D69; C142). The order
is the cutover's, by what each stage stands on (P0 §7, D56), not by the
size of its phase at O0.

**Contingency (SELF-HOST).** If 0006's record of the self-compile shows
a stage of `make self` whose frontend does not fit the owner's machine,
the frontend's memory is this proposal's ground. No stage above runs
before 0010's A0, so the fix is the one the record names, in the
structure that holds the memory today. The last figure: the self
compile's emit under a minute at a 3.74 GB peak (*measured*, 77a7192b,
2026-10-18).

## 9. Rejected alternatives

- A from-scratch frontend: it loses Idris 2 compatibility and the corpus
  proofs (0013 §5).
- Full flattening of everything (DPH): 0012 rejects it.
- The frontend's own Datalog: a second copy of 0015's. The elaborator's
  union-find is no such copy: it is the checker's own, in Idris, which is
  all unification and the constraint store need, since they merge and
  never search, and it is R4's part in P0 (P0's D107).
- `libs/mlir-array`'s ops in the frontend or the checker: Chez cannot run
  them (§1).
- Lambdas as regions in the ops table, outlined later: the round trip
  the cutover deleted (`idr-isolate`).
- Symbols numbered by order of appearance: creation order reaching
  output (the cutover's D18).
- A count of instances as the refusal (the cutover's D17; 0014 D4).
- Data types as symbols a lookup resolves.

Untyped ids, a parallel parser, storing `parent`, a carry-less multiply
and an O3 that changes acceptance are rejected by D1, D2, D8, D10 and
D3.

## 10. Decisions

- D0. Measure first (O0), as §2 says; every stage is taken, its bar a
  ratio to O0 (C142 struck the 5% skip).
- D1. No bare ids: a frozen table's id is a `Fin` of its extent, read
  with no guard through base's primitive array read; a growing table's id
  is an opaque typed identity read by lookup; an `extra` slice is decoded
  by a type its `kind` decides (§3.1).
- D2. Lexing is array-shaped; parsing stays sequential: parser
  combinators that use quantities, the token stream and the parse state
  threaded linearly, termination proved by the types, no type passing
  (P0's D119), writing the flat parse tree (C216).
- D3. Translate is a semi-naive fixpoint over the instance table, with no
  count and no refusal of its own (the growth check's comes first, §0);
  O3 changes no acceptance.
- D4. Emission writes each function's bytes from its ops rows by a size
  scan and a scatter; the attribute and type section is §0's.
- D5. Every stage is proved by identical TTCs and the unchanged corpus.
  O2 is the Emit of the new dialect, written once over the Core table, so
  no earlier bytecode is its reference and the cutover's checks prove it
  (P0's C136, D56). No stage keeps the tree it replaces.
- D6. A stored definition's terms are 0010's A0 in C183's form: columns
  in preorder, shared within the definition and frozen with it, no arena
  across definitions; a term being elaborated stays an unshared, located
  tree (P0's C183). This proposal keeps no second copy of a term.
- D7. Emission's forms have one form each in the tables: a lambda is a
  core slice lifted with its captures by an interval query; a generated
  name is the owner and the slice's hash; an instance is its `Link`, its
  symbol the built rule (the print, plus `;` and 16 hex digits of the
  identity hash when the print is lossy); a data type is a datatypes row;
  a binder is a row; the root is one function id.
- D8. Syntax nodes and Core store `subtree_size`, not `parent`.
- D9. Full Core is a table in preorder, moved in O2 with Emit; the
  function row holds the location.
- D10. The quote mask is a prefix XOR by shifts in plain Idris; a
  carry-less multiply waits on O0.
- D11. O6 is executed as 0009's stage 7, with this proposal's gate, and
  deletes the elaborator's triple closure for `loopsTerminate` (0013
  D13). Its kernels reach the checker only through 0009's plain-Idris
  layer (§1), which comes into P0 with O6 (P0's D69).
- D12. O3, O5's join, O7's constraint store and O8 are built on 0015's
  plain-Idris layer, which P0 builds as R1 and R2 (P0's D44); O3 is its
  first consumer. Whether O5's resolution is the join is P0 §4's open
  question (§4.4, C216). O7's meta-to-meta unification is the checker's
  own union-find (D107).
- D13. The law queries run on every compilation, never in test builds
  alone, under 5% of the frontend's wall at O0. Reason: a check off in
  the build that ships is behaviour that depends on the build (the
  cutover's D2).
- D14. Built (§0): an instance's symbol carries its identity hash exactly
  when its key's print dropped part of the identity.

Both layers D11 and D12 stand on are decided, and each comes into P0
with its consumers (D44, D69): 0009 D45 (its stage 7, for O6 first) and
0015 §1 (R1 and R2, for O3 first).

## The MLIR form owed

From the representation wave's audit of the proposals' MLIR forms (its
last text at 77eaa5b1), checked against the code there; none of it is
built unless it says so.

- One `DialectAttribute` bytecode record per idr attribute in
  `IdrBytecode.td`, which holds only `DataTable` today (the types have
  their records); §4.9's "an upstream patch" is wrong.
- Properties written in the properties section through the encoding ODS
  generates; today inherent attributes go in the dictionary and
  `setAttrs` splits them (`MLIR/Bytecode.idr`). §4.9 and O2 change with it.
