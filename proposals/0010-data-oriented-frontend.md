<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# 0010: a data-oriented, array-first frontend

**Status:** proposed 2026-10-10, decided 2026-10-14, audited 2026-10-15
against `main` at b843d8b5 while proposal 0001's lanes edit the frontend.
Nothing of it is built. Every stage is **AFTER-SELF**: `make self` (0005
§2 step 5) needs none of it. O0 is a record taken from the self-hosted
frontend once `make self` holds; O1 onward start after 0009's A0, in the
order O0's costs give (D0). One contingency is **SELF-HOST** (§8): a
frontend stage that does not fit the owner's machine in 0005 §2 step 4's
record.

The interned names and the term arena are 0009's (its A0); this proposal
builds the rest of the frontend's state as tables on them. O3,
Translate's instance fixpoint, is 0014's first consumer (R1 and R2 come
before it); O5's join, O7's constraint store and O8's laws are 0014's too.

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

## 0. Done, and what it stands on now

Built by other waves; each line is the record kept.
- **Instance symbols** (D7, D14): a key's print, followed by `;` and the
  low 64 bits of its identity hash exactly when the print loses part of
  the identity, a rule of the key alone: `Ids.KeyPrint` (`Whole | Lossy`),
  `Term.keyText` (the cutover, c7aa7b62). The identity is
  `Proof.Requests.Link`, the definition's `Address` and each static
  argument as a prefix-order token list (`Written`); `TS.symbols` makes
  two identities on one symbol an internal error.
- **The attribute and type section** (§4.9): one entry per distinct text,
  its assembly, every use its number (`MLIR/Bytecode.idr`, `Numbered`);
  each function is encoded as Emit finishes it, so no value of the whole
  module is held.
- **The phase record O0 reads:** `--timing`, one `phase<TAB>ms` line each
  for checks, reachable, translate and emit (`Frontend/Program.idr`,
  `reportTimes`), and Idris's `logTime` phases for the package commands
  (`Frontend/Driver.idr`).
- **No count in the fixpoint O3 inherits:** the request-chain rule, proved
  to end (`Proof/Requests.idr` `afRequested`, `Frontend/Finite.idr`
  `chainsEnd`; 0002).
- **The emission the tables re-express**, coded, not built (the cutover,
  c7aa7b62; the representation wave, bfdcac70; their last texts at
  484d6403): closures and suspensions in symbol form
  (`Emit/Closures.idr`), names from content, data types that carry their
  constructors, constructors by tag, the in-place promise in the type, the
  root as `idr.program`'s property.

**What 0001 changes under it** (lanes I and N, in progress; *read* in the
live tree):
- A definition's identity is `Proof.Requests.Address`, the context
  index's bytes; `loops`, `refused`, `tyCons`, `blockNames` and
  Recursion's Tarjan tables key by it. Not `Fin n`, since the context
  grows while it is read: D1 takes that in (§3.1).
- A constructor is `ConId = (dataId, index : Fin arity)`, Idris's tag;
  `Con.tag` is derived from `index`, `Con.name` is a print, and
  `Types.conIdOf` is the one maker. That is the datatypes table's
  constructor row already: a position in its type's slice, with no tag
  column and no name as identity.
- `FnId` and `DataId` stay symbols, faithful because `TS.symbols` and
  `ES.keys` check them. Emit's `Numbering.names` and Bytecode's `Scope`
  key by SSA names, which 0001 §4.6 leaves as later work. O2 is that work:
  an instance becomes a row and its symbol a print column, and an operand
  becomes a result position.
- `tests/Prims.idr` (`Op`, `Prim`) is the tests' table of Idris's
  primitives. Emission does not read it. The ops table's opcodes come
  from the generated dialect modules (`IdrisMLIR.Dialect.*`, from ODS),
  their one source.

## 1. What it changes

Today the frontend (the fork in `compiler/idris`, and
`compiler/src/IdrisMLIR`) keeps its state as trees of heap cells walked
by recursive functions (*read*). TT is upstream's `Term`, with an `FC` in
every constructor (`compiler/idris/src/Core/TT/Term.idr`). Full Core,
Translate's output, is another tree (`IdrisMLIR/Term.idr`, scoped by
`Fin n`, a `Loc` on its nodes). This proposal makes that state a few
**columnar tables keyed by typed ids**, and each pass **a function from
tables to tables**, built from scans, gathers, scatters, compaction,
segmented folds, joins and fixpoints. It is Brooks's "show me your
tables" (*recalled*) and bumbledb's data model, and Zig's self-hosted
compiler is the existence proof (*read* through `columnar.md` §3). It is
no rewrite (0012 §5): each stage changes one representation inside the
fork, proved by identical TTCs and the unchanged corpus.

**Two hosts** (AGENTS.md; 0001 R3; the coordinator's ruling of
2026-10-15). The frontend and the fork compile and run under the stock
Idris on Chez and under idris-mlir, forever, so the tables run on Chez
too. A table is plain Idris over base (`Data.IOArray`, `Data.Buffer`,
linear data, definitions with bodies), as the fork's
`Libraries/Data/Table.idr` already is (0008 D38). idris-mlir may speed a
definition through the registry's `Faster` hook, its body staying the one
meaning. A table is never `libs/mlir-array`'s generating set, whose
bodiless `%extern`s serve programs and which no code the stock host runs
may reach. This replaces "its tables are 0008 arrays and its passes 0008
programs": a 0008 or 0014 mechanism serves the frontend through its
plain-Idris layer, and a kernel that exists only as ops waits for one
(D11, D12).

## 2. Where the time goes (the baseline)

Two records, both of stage 0 (the frontend on Chez):
- *Measured* (HANDOFF.md, 2026-10-10, arm64 macOS, c50d176d): 137 s at
  9.1 GB peak, a 405 MB MLIR text module (58,305 functions, 7,664 data
  types) and a 74 MB Core. Checks took 0.4 s, reachable 4.2 s, translate
  (TT to Core, monomorphisation on demand) 81 s, print 40 s, write 0.9 s.
- *Measured* (`bench/profiles/2026-10-14-f0-stage0.md`): 58,236
  functions in 294 MB of generic text, about 140 s to write.

Translate and print were 88% of the first run, both pointer chasing.
Both records predate bytecode emission. Elaboration (about 75 s when the
fork installs) is 0012's T0.

**Decision (D0):** O0 measures once, natively, on the self-compiled
frontend, on one commit with 0012's T0, on both targets, with the
stage-0 run beside it as no target. Every threshold below is a ratio to
O0. A stage whose phase is under 5% of the frontend's wall at O0 is not
taken. Reasons: emission has changed since both records, so they measure
a printer that is gone; and the stages change the self-hosted frontend,
since on Chez a representation buys memory and little else (§6).

## 3. The representation: the compiler's state as a schema

| Table | Columns (structure of arrays) | Precedent |
| --- | --- | --- |
| files | one byte buffer each | |
| tokens | `kind : u8`, `start : u32` | Zig's `tokens` (*read* through `columnar.md` §3: `Ast.zig:17-31`) |
| syntax nodes | `kind`, `main_token`, `subtree_size` in preorder, so a subtree is `[pre, pre + size)`; variable arity in an `extra` column decoded by `kind` | Zig's nodes (`Ast.zig:3014-3086`); Co-dfns (`cmp/TT.apl:1-6`); Carbon (`whole-program-at-scale.md` §7) |
| names | interned (0009 §3) | |
| terms | the hash-consed arena (0009 §3) | |
| metas | `meta → solved term or unsolved` | |
| constraints | `(lhs, rhs, ctx, blocked_on)` | |
| defs | by `Address`: name, type, body, multiplicity, totality, location | the fork's growable `Table` on base's `IOArray` |
| instances | by `Link`: the instance and its requester | Translate's `Request` and its `chain` (`Translate/State.idr`) |
| core | per function instance, its body in preorder: `kind`, `subtree_size`, binder ids, operand slices; the function row holds the location | full Core, where each node carries a `Loc` |
| datatypes | key; constructor slice in tag order (a constructor's id is its position, as `ConId`), field types, quantities, roles; the in-place fact | the declarations data types carry (§4.10) |
| ops | per function: opcode (the generated dialect's), operands as result positions, result types, region slices | MLIR bytecode |

- **`subtree_size`, not `parent`** (D8). The interval is what name
  resolution (§4.4) and lambda lifting (§4.10) read. Depth is the
  inclusive prefix sum of +1 at each node and −1 one past its subtree,
  less one. A parent is the last earlier node one level up, as Hsu
  derives Co-dfns's parent vector (*read*:
  `hsu-dissertation.pdf.txt:719-760`). Storing both keeps one fact twice.
- **Core is a table** (D9), moved with Emit in O2. A tree beside it would
  be one concept held twice.

What falls out: equality of names, terms and types is an integer
compare, which also makes 0013's "compared as values" regression an id
compare (its proofs stay 0013's feature 6). Spans are free: a syntax node
names its token, terms carry none, and Translate and Emit report at the
definition (0009 §3 and its D10). Memory becomes a few large arrays; the
9.1 GB peak is the first thing this should cut, on Chez too
(*conjecture*).

### 3.1 Typed indices

```idris
-- sketch: an id of a frozen table is bounded by its extent, erased to a word
NodeId : (t : Tree) -> Type                          -- Fin (size t)
parent : (i : NodeId t) -> (p : NodeId t ** LT p i)  -- preorder: parents first
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
  row), and a read through it is a lookup until the table is frozen.
  0001 took this for definitions.

`LT p i` makes every upward walk total. An `extra` slice is decoded by a
type its `kind` decides.

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
**D2:** sequential, with an explicit stack, writing the preorder arrays
with no recursion and no closures, as Carbon does. 0013's ledger already
made the combinators direct code; operator resolution stays sequential.
Parallel parsing (Pareas, Voetter) is research-grade, and Idris's grammar
is its hardest case (0012 §2.7).

### 4.4 Name resolution is an interval join
A reference resolves to the deepest binder of its name whose interval
contains it, an Allen "during" join with a max-depth fold, on 0014's
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
The gains here come from representation (*conjecture*, sized by 0009's A0
and A2):
- hash-consing and id-keyed caches (0009 D12);
- postponement as semi-naive evaluation: each round's newly solved metas
  join the blocked constraints on `blocked_on`, where the fork retries
  every postponed constraint until none progresses (`solveConstraints`,
  `Core/Unify.idr`, *read*);
- meta-to-meta unification as union-find, never the conversion cache,
  since conversion with unfolding is not transitive;
- one evaluator, 0009's machine;
- shape arithmetic as a group-by (0008 §3.7; 0012 §2.4);
- parallelism across definitions, not within one (0012 §2.7).

### 4.7 Multiplicities and termination are semiring folds
QTT usage checking groups occurrences by binder and folds each group in
0/1/ω (`Algebra/ZeroOneOmega.idr`, `Algebra/Semiring.idr`, *read*), a
segmented reduction. Composing size-change graphs (`composeChange`,
`Core/Termination/SizeChange.idr`) is a semiring matrix product over
`Algebra/SizeChange.idr`, with `Unknown` as the sum's zero
(`plusNeutral`). The fork's `SparseMatrix` is already DCSR in lists. The
closure is not a sum. The elaborator's `calcTerminating` still closes
`(f, g, graph)` triples (`SCSet`, `insertGraph`, `findLoops`), restricted
to components by PINS.md `termination-closure`. The frontend's verdict,
`loopsTerminate` (called from `Translate/Recursion.idr`), keeps only the
weakest graphs per function reached (`search`, `Kept`, `weaker`, on
`Dense n from to`). So the closure is a relational fixpoint with
subsumption (0014 D9), and the triple closure goes for `loopsTerminate`,
which carries the call path its message names (0012 D13). D11.

### 4.8 Translate is semi-naive Datalog over the instance table
Each round, the new instances gather their bodies. Type arguments are
substituted, memoised on `(term id, substitution id)`. Call sites are
found by a filter on node kind. A hash join on `Link` drops the
instances already known, and what remains is the next delta. Reachable
is the same query without substitution. **D3:** O3 changes no
acceptance. The refusals, as they stand when O3 lands, are filters on
the delta against each row's request chain, so a refusal still names the
site and the growing value. Since the cutover that is the request-chain
rule alone, with no count (§0).

### 4.9 Emission is bytecode serialization
The frontend writes bytecode and the driver reads it with
`readBytecodeFile` (the cutover's §4.1); the numbering is built (§0).
What O2 adds: each op is mapped to its encoded size, the sizes are
exclusive-scanned into offsets, and each op is scatter-written at its
offset, one function at a time, as the writer streams today. Every
attribute and type stays its assembly, the bytecode's fallback
(`emitAttrOrTypeRawImpl`). The pinned writer takes that form for every
mutable type, and a recursive data type names itself, so no cycle of
entries reaches the reader (`upstream/03-bytecode-deferred-quadratic`). A
custom encoding becomes an upstream patch only if O0 names the section
as a cost (*conjecture*: it is small next to the ops).

### 4.10 What emission asks of the tables
One form each (D7), changing no byte of what is emitted (D5):
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
  error, never a merge (0007 §11).
- **Instances.** An instance's row is keyed by its `Link`, the identity
  the finiteness proof stands on. Its symbol is the built rule (§0). When
  0009's arena gives argument term ids, they replace `Written` only
  together with the proof, so there is one encoding of a static argument.
- **Data types.** One datatypes row per data instance, with the
  constructor slice in tag order, its field types, quantities and roles.
  A role a pass needs (the list's cons) is filled from the Idris
  declaration, never guessed from shape. The in-place fact comes from the
  registry (`Registry/Recognized.idr`: `mlir-linear`'s types rebuilt in
  place and held exclusive), which `idr-demand` checks. The closure and
  memo sums are defunctionalization's, in C++. Each type is written once
  (§4.9).
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
  `judge_incremental`). 0007's S9 would hold it.
- **0014's first consumer:** the interval join and the laws are layer 1;
  the instance fixpoint, the constraint store and the size-change closure
  layer 2; union-find layer 3.

## 6. Limits

- The elaborator will not vectorize: expect smalltt's gains, from
  representation and caching.
- Speed comes only once idris-mlir compiles base's arrays and buffers
  well (contiguous runs, which have no proposal). On Chez it buys memory
  and little else, which is why it follows self-hosting.
- Sequential is fine. Zig runs semantic analysis on one thread and builds
  itself in 8.6 s (*measured* by its developers, read through
  `whole-program-at-scale.md` §7). Parallelism is taken only where a
  phase is regular and measured hot.

## 7. Rules it keeps

Idris 2 fully: checked TT and its context in, only their representation
changed. Two hosts (§1). One thing, one representation: a table replaces
its tree, and the relational mechanisms live once, in 0014's library. No
primitive implemented in Idris. Names from content: no arena id, row id
or arrival order reaches a symbol, a key or a file (the cutover's D18;
0007 D3). Facts in types. No refusal by budget: the fixpoint has no
count, and the frontend's reduction has had no fuel since the
representation wave's D4 and is total since 0002. Deterministic,
byte-identical outputs on both targets.

## 8. Staged plan, ordered by measured cost

| Stage | Mark | Needs | Content | Proof |
| --- | --- | --- | --- | --- |
| O0 | AFTER-SELF | `make self` green on both targets; 0012's T0 on the same commit | the stage-3 frontend's phases by `--timing`, its peak memory, base's elaboration, and stage 0 beside it. `tools/self.sh` records only the driver's `-mlir-timing`, whose frontend is one scope, and peak memory, so `--timing` goes to `idris-mlir-front` directly | a committed record under `bench/profiles/` |
| O1 | AFTER-SELF | 0009's A0 | token SoA over the interned names; names compared by id, replacing the name-equality traversal of 0013's ledger (the proofs stay 0013's feature 6) | identical TTCs and corpus |
| O2 | AFTER-SELF | the cutover's emission and 0001's lane I, built by the owner | the core, datatypes and ops tables; lambdas lifted by interval queries; names from slice hashes; an instance as a row with its symbol as a print column (`TS.symbols` its check); operands as result positions; data types written once; the root as one id; each function's bytes by a size scan and a scatter | the bytecode bytes of today's writer on the corpus and the stage-0 self-compile; emission ≥ 5× faster than O0; peak memory not above O0's |
| O3 | AFTER-SELF | 0014's R1 and R2 in plain Idris (O3 is R3) | Translate as semi-naive over the instance table keyed by `Link`; reachable as its query; the request-chain rule as a filter on the delta | identical Core; translate ≥ 3× faster than O0 |
| O4 | | | moved: the term arena is 0009's A0 | |
| O5 | AFTER-SELF | 0014's R1 | flat parse tree; name resolution as the interval join | identical TTCs; parse plus resolve no slower than 0009's A0 |
| O6 | AFTER-SELF | 0008's stages 4 and 6 through a plain-Idris layer (D11) | multiplicity checking as a semiring fold; size-change composition as a semiring product (the closure stays `loopsTerminate` until 0014); `calcTerminating`'s triple closure deleted for `loopsTerminate` | identical totality and multiplicity verdicts, and identical totality messages, on base and the corpus |
| O7 | AFTER-SELF | 0014's R2 and R4 | the constraint store and postponement on 0014; meta-to-meta unification on its union-find | 0009 A2's targets; identical TTCs |
| O8 | AFTER-SELF | 0014's R1 | the laws of §5 as queries on every compilation | a seeded violation of each law caught by name; under 5% of the frontend's wall at O0 |

The thresholds are *decisions*: each is the factor a representation
change must buy on a phase D0 has shown to be worth one. A stage that
misses is reworked or not taken, never kept beside the tree it replaces.
Among the stages whose needs are met, the largest phase at O0 goes first;
on the 2026-10-10 record that is translate (O3), then emission (O2)
(*conjecture* until O0).

**Contingency (SELF-HOST).** If 0005 §2 step 4's record shows a stage of
`make self` whose frontend does not fit the owner's machine, the
frontend's memory is this proposal's ground (0005 D10). No stage above
runs before 0009's A0, so the fix is the one the record names, in the
structure that holds the memory today. Emission has since streamed
bytecode per function (§0), the bytecode rule HANDOFF.md's 2026-10-12
item on the 9.1 GB print-write names; its effect on the peak is
unmeasured.

## 9. Rejected alternatives

- A from-scratch frontend: it loses Idris 2 compatibility and the corpus
  proofs (0012 §5).
- Full flattening of everything (DPH): 0011 rejects it.
- The frontend's own Datalog or union-find: a second copy of 0014's.
- `libs/mlir-array`'s ops in the frontend or the fork: Chez cannot run
  them (§1).
- Lambdas as regions in the ops table, outlined later: the round trip
  the cutover deleted (`idr-isolate`).
- Symbols numbered by order of appearance: creation order reaching
  output (the cutover's D18).
- A count of instances as the refusal (the cutover's D17; 0013 D4).
- Data types as symbols a lookup resolves.

Untyped ids, a parallel parser, storing `parent`, a carry-less multiply
and an O3 that changes acceptance are rejected by D1, D2, D8, D10 and
D3.

## 10. Decisions

- D0. Measure first (O0), as §2 says; a phase under 5% of the frontend's
  wall at O0 gets no stage.
- D1. No bare ids: a frozen table's id is a `Fin` of its extent, read
  with no guard through base's primitive array read; a growing table's id
  is an opaque typed identity read by lookup; an `extra` slice is decoded
  by a type its `kind` decides (§3.1).
- D2. Lexing is array-shaped; parsing stays sequential, writing tables.
- D3. Translate is a semi-naive fixpoint over the instance table, with no
  count; its refusals are filters on the delta that name the site and
  the growing value; O3 changes no acceptance.
- D4. Emission writes each function's bytes from its ops rows by a size
  scan and a scatter; each attribute and type is one textual entry,
  numbered once (built, §0).
- D5. Every stage is proved by identical TTCs, the unchanged corpus and,
  from O2, identical bytecode; no stage keeps the tree it replaces.
- D6. The arena is 0009's; this proposal keeps no second copy of a term.
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
- D11. O6 is executed as 0008's stage 7, with this proposal's gate, and
  deletes the elaborator's triple closure for `loopsTerminate` (0012
  D13). Its kernels reach the fork only through a plain-Idris layer
  (§1). Until 0008 has one, O6 waits.
- D12. O3, O5's join, O7 and O8 are built on 0014's plain-Idris layer;
  O3 is its first consumer and takes it out of parking.
- D13. The law queries run on every compilation, never in test builds
  alone, under 5% of the frontend's wall at O0. Reason: a check off in
  the build that ships is behaviour that depends on the build (the
  cutover's D2).
- D14. Built (§0): an instance's symbol carries its identity hash exactly
  when its key's print dropped part of the identity.

Open, for the coordinator to place: whether 0008 and 0014 give their
kernels a plain-Idris layer the frontend and the fork can use, which D11
and D12 now wait on.
