<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# P0 synthesis D: the Idris side

*Written 2026-10-21 by synthesis reader D. Sources: lanes 14, 15, 16, 17
and 21 and `audits/p0/README.md`, every line; §5 and §6 of lanes 01, 03,
10, 19 and 20 where they touch the Idris side; the proposal's §0–§4, §6,
§8, §9, §5.7–§5.9 and the TableGen parts of §5.2 and §5.3; proposals 0003
and 0011; `bench/records/2026-10-17-self-growth.md`. Nothing was built or
run. A citation "15 TS-5" is row TS-5 of `audits/p0/15-frontend-translate.md`;
"15 §6" its section 6; "P0 §5.8 DS1" the proposal. Decisions are the
owner's: this document lays them out and decides none.*

**Owner ruling folded in (2026-10-21, through the coordinator).** "Heavy
use of templates and concepts" for our own C++, `idris-mlir-tblgen`
included: §8 Q1, Q-M3 and Q-llvm-1 are settled toward concept-constrained
templates. On the Idris side the matching rule is the representation-first
skill's type-driven development (indices, views, erased proofs), within
the subset both hosts compile. Every change is a hard cutover that culls
the old code, with maximal churn toward the most elegant representation.
Where this settles or bears on a point below, the point says so (§2.6,
§5 D1, D8, §6 step 1).

## 1. In plain words

**What the cluster is.** The Idris half of the compiler, in four parts:
- *The fork* of Idris's compiler (`compiler/idris`, 65,876 lines, 17 §2.1)
  elaborates the program, proves quantities, erasure and totality, writes
  every module to a TTC file and reads it back.
- *The checks* (`Profile`, `Growth`, `Finite`, `Proof`; 9,964 lines, 16
  §2.1) refuse what the compiler cannot compile and prove that
  monomorphization reaches finitely many instances.
- *The translation* (`Translate`, `Term`, `Types`; 11,583 lines, 15 §2.1)
  turns checked TT into Core, one function per instance.
- *The mirror and the handoff* (`idris-mlir-tblgen`, 3,255 lines of C++;
  the generated `Dialect/`, `Syntax/`, `Encoding/` modules, 4,591 lines;
  `Emit`, `MLIR/Bytecode`, `Registry`, about 5,000 lines; 14 §2.1) write
  Core as an `idr` module in MLIR bytecode, through builders generated
  from the dialect's ODS records.

**What is wrong today.**
- The fork computes facts, then drops them on the way through the TTC,
  and the frontend guesses them back: seven dropped, three kept and never
  read (17 §3.1, row §5.9 M1). One guess refuses valid programs (17 FB-01).
- One fact is derived in many places with different defaults: erasure
  five ways (17 FB-15), an instance's identity in five structures (15
  ST-2), a quantity in six spellings (17 §2.5), the registry resolved and
  thrown away, then searched again by printed name at about twenty sites
  (14 R06, 15 RS-1).
- Everything is keyed by strings or byte lists in sorted maps: 46
  `SortedMap`s and 27 `SortedSet`s in the translation, no dense numbering
  anywhere (15 §2.4); in Emit a value *is* its SSA name string (14 M06).
- The handoff writes many of our own types and attributes as text, which
  the reader parses again, and the generator keeps a hand copy of
  upstream's declarative-format parser to print them (14 T35, B05).
- The checks are already the shape P0 wants (extract, solve, certify; no
  budget, no `covering`, every recursion on a measure), but their answers
  cross as mutable state behind a `Bool`, and the code carries 18 hand
  folds over one type and three numberings (16 §2.6, §5 intro).

**What it should become.** The TTC keeps every fact a reader rebuilds.
The frontend reads each fact once at the boundary into a typed table: one
runtime signature per definition, one identity per instance, one resolved
registry entry per name. Core carries exactly what the redesigned dialect
needs, so Emit derives nothing; Emit writes through typed builders (values
as numbers, ops indexed by their result count, primitives by arity). No
`idr` text crosses the handoff. All of it stays in the subset both hosts
compile, and lands in the same commit as the `.td` change it follows,
because the frontend will not build otherwise (14 §6 Q3; 17 §6 Q3).

## 2. Where the lanes agree

**2.1 The fork keeps the facts; the frontend stops rebuilding them** (17
C1; 15 D-4; 16 G12, G14; 0003 §2 order item 2).

| fact | lost at | rebuilt by | lanes |
| --- | --- | --- | --- |
| a `let`'s, `PLet`'s, `PVTy`'s type | `TTC.idr:611-620`, read as `Erased` | `Terms.valueType`, `applyOver`'s refusal, Emit's second synthesis | 17 FB-01–03, 15 TM-1, TS-5 |
| a match's scrutinee type `scTy` | `TTC.idr:829-831` | `Cases.instanceOf`, `siblings`, `coversAll` | 17 FB-05, 15 TM-2, CS-1, CS-2 |
| a leaf's clause index | `TTC.idr:832`, read `STerm 0` | all of `Translate/Forced.idr` (301 lines) | 17 FB-06, 15 FO-1, FO-2 |
| why a term is erased (`WhyErased`) | `TTC.idr:583, 694` | the frontend reuses `Erased _ Impossible` as its own marker | 17 FB-04, 15 CL-3 |
| a case or with block's parent | stored as printed text (`Name.idr:45-46`) | `Closed.outermost`, `rootOf`, `Keys.keyOrigin`'s context search | 17 FB-10, 15 CL-4, KY-1 |
| imports with locations; pragma uses | not kept | `Profile.imports` (`words`), a re-lex of every module | 17 FB-11, FB-12, 16 FC-79 |
| a module's package; the main source path | not recorded | `Resolve.homeOf`, `Resolve.elaboratedFile` | 17 FB-13, FB-14, 15 RS-3, RS-4 |

Each fact is one change: `ttcVersion` bumped, round-trip checked, the
reader deleted in the same change (17 C1, "One line"). Agreed order:
low-risk facts and locations first, then the term facts, then `WhyErased`
after the frontend's marker moves to a probe of its own, then the block
parent, which touches `Core.Name` across the elaborator (17 C1 "Order";
0003 §2).

**2.2 One runtime signature per definition** (17 C2; 15 D-2; 16 G12). It
comes from `eraseArgs`, which the fork keeps and nothing reads (17 FB-15),
plus the quantities of the remaining `Pi` binders, normalised once and
cached by address. It deletes the five erasure readers (`Closed.erasedArgs`,
`Forced.quantities`, `Sites.quantitiesOf`, `Terms.lastRuntime`,
`Types.conBinders`), `coreBinder`'s quantity-0 internal error (17 FB-27,
15 TT-11) and, once the fork computes `paramPos` on normal forms,
`Types.dataParams`' second reading (17 FB-18). `ZeroOneOmega` becomes
`public export` so readers can match it (17 FB-22). The registry's
`Multiplicity` mirror stays: the registry may not import the fork (17
FB-24).

**2.3 One table per thing the translation asks about** (15 D-2; 16 G4,
G14; 14 TD7). Per definition: its kind as the translation's sum, erasure,
projection, termination verdict, origin, resolved hook. Per type
constructor: `roles : Vect arity Role` and one `TyConKind` sum (15 TT-4).
Per constructor: type constructor, tag, quantities (0003 C3). The registry
is resolved once by `validate` and returned keyed by resolved name; hooks
are indexed by their kind, `Contract | Faster | Stricter`, so a `Faster`
hook on a bodiless definition cannot be written (14 R15, R16).

**2.4 One identity per instance** (15 D-1; 14 E25, G05; 16 G4; 0003 B7).
The `Link` stays the identity, because the finiteness proof is about it.
It is looked up once and mints a dense `InstanceId`; definition, request,
translated body, key and symbol become columns. The symbol is printed once,
from the key alone, so stage 2 equals stage 3 whatever order instances
are minted in (15 §8). `#idr.instance` carries a typed identity instead of
argument texts, so C++ stops keying specialization by a string (lane 09).

**2.5 Classification memoised by its key** (15 D-3): a callee's parameter
kinds and result type depend only on the callee and its static arguments.
This is MLton's per-binding instance cache (P0 §5.9 D1) and §5.7 L5's
"keys first". Its gate is a debug run comparing memoised and recomputed
answers (15 §8).

**2.6 The generated mirror, typed** (14 TD1, TD3–TD6, TD9; 15 TM-3,
TY-3, TY-4; 01 C6, C12; 03 §5.4):
- the generator reads the records once into a typed model through the
  `mlir::tblgen` wrappers; it is already a set of `GenRegistration`s on
  `MlirTblgenMain`, but bypasses the wrappers in about twenty places (14
  §3.1 rows 1 and 3, T05–T19);
- a value is a dense number per function; builders return `Op n`; a
  statement binds `Vect n` values; captures come from the term's free
  variables, not from a walk of the built region (14 TD3);
- guards name operands by `Fin n`; `ioOp` takes `Vect (ioArity p)` as
  `pureOp` already does (14 TD4);
- facts restated on both sides move into ODS and are generated to both:
  `CmpPredicate` against arith's predicates (held in Idris and again in
  `Layouts.cpp`, 14 E14), "linear by its type" (deleting
  `linear One WorldT = False`, 14 E01, 01 C6), the lifetime default, the
  dynamic-extent constant, the library-location marker (14 TD5);
- the frontend gets builders only for the ops its stage admits: 125 of
  191 `idr` builders are named by no Idris code (14 §2.6, TD6);
- primitives become one generated family with typed operand slots, not 17
  hand constructors beside a generated catch-all (15 TY-3).
- the generator's own C++ loses its string ladders and type-erased
  plumbing: `formatv` templates with `{0}` holes become a typed
  Idris-expression tree printed once; arity a closed enum, not a `char`
  sentinel; four parallel vectors one struct; `get_if`/`get` pairs over
  `Written<T>` one exhaustive visit or `std::expected`; no
  `std::function` (14 TD9, T04, T07, T11, T21, T31, T49). Under the
  owner's ruling this is written as concept-constrained templates: each
  Idris view a generator template over the one typed model, record kinds
  classified by templates over their TableGen class, never by comparing a
  C++ spelling (this reader's sketch of the ruling applied to 14 TD1 and
  TD9; P0 §5.5 D1's line holds, since every type in the generator is ours
  or a TableGen record). Still open: cxx-Q2 (ban `std::visit`, or allow
  it under 12 alternatives), which picks between the visit and a fold
  `match` for T31.

**2.7 The handoff's encoding** (14 TD2; 01 C8; 0011 "The MLIR form
owed"). Every `idr` type and attribute gets a bytecode record; the
pairing of record and constructor is generated, replacing the hand switch
(14 B04). The copied format parser (about 180 lines) and the Idris
printers go. A lifted function is keyed by a structural hash of its op,
not by its printed text (14 E05). A double is written as its 64 bits (14
X01). Text stays only for arith's and ub's attributes and the builtin
records that need a custom reader. Lanes 01 and 14 both ask to measure the
text payload first (01 §5.10; 14 §8).

**2.8 Quantity at the boundary.** Lanes 14, 15 and 17 measured the same
thing: the frontend writes one grade, `(one, plain)` with no lifetime, for
every quantity-1 binder except the world; quantity 0 is absent; ω is the
bare type (14 §3.2; 15 §3.2; 17 §3.3). No proved fact crosses in a
discardable attribute (17 §3.3 W-E4), though `idr.refusals` is one (14
T38). Quantity 1 means "used once from here", never "unique" (17 §1 on P0
§5.10 G2). Results are never graded; Idris has no linear result (17 §3.1
R1.1).

**2.9 The checks stay where they are and keep no budget** (16 §5 intro).
The growth check's facts exist only before monomorphization, so nothing
moves to C++. The changes are representation only: the admission returned
as a value, not written into `TS` behind a `Bool` (G1); `Template` indexed
by its stage, with one traversal instead of 18 hand folds (G2); a stuck
arc carries its cause (G3); one numbering and resolved identities (G4);
the dictionary flow semi-naive (G7); one walk and one Tarjan (G8, and 17
C6: call the fork's own component search instead of a second Tarjan);
certificates at quantity 0 (G9); one trie and a check right by
construction (G10, G11); termination a sum (G13).

**2.10 Locations and types.** Locations become an interned
`(ModuleId, Span)`, and a rebuilt term takes the location of what it
rebuilds (15 D-5; 16 G12, FC-99). Every lookup's `Maybe` becomes an index,
every `Bool` pair a sum, the environment an `IsVar`-indexed vector,
layouts `Vect arity` (15 D-8; 16 G2–G7; 14 E07–E21): the type-driven lens
the owner's ruling names. Most of the 77 internal-error sites in the
translation and 21 in Emit go (15 §4; 14 §2.6).

## 3. Where they disagree

**3.1 Who makes a representation choice: the frontend or the dialect.**
- Today the frontend collapses a one-field type to its field, maps
  Nat-likes to `!idr.nat` and pointer-like words to `u64`, and enumerates
  crash alternatives, though `Term.idr:110-112` says layout is "the
  dialect's decision" (15 NQ-1, ft-Q1).
- Lane 01 asks for the opposite move: the frontend should emit the boxes
  that break cycles, so a table is never cyclic in place and `layout::fit`
  with its whole-program remap goes (01 NQ2, types-Q2).
- Lane 17 says the dialect laying out each monomorphic instance is right,
  so Idris's unread `ConType` flags lose nothing (17 FB-20), and that the
  newtype decision must stay the frontend's, because the frontend's fields
  differ from Idris's (17 FB-19).
- Other lanes want the frontend to write more facts as IR: a guard around
  an arith op (03 NQ3, ops-Q3), a transpose as a tabulate (11 N4,
  arr-Q4), tail position on the call (10 §5 D1b, tail-Q1), a static
  suspension (06 D-11), a link as its own op (11 N2, arr-Q2).

What it turns on: the lanes imply, without stating, one test. A fact is
the frontend's if only Idris knows it (quantity, erasure, totality,
coverage, which fields a newtype has once compile-time arguments go); it
is the dialect's if it depends on the whole monomorphic type graph
(boxes, packing). Boxes are the hard case: the frontend holds the whole
table, but defunctionalization adds closure sums after it (15 §3.1 M10),
and those can close new cycles.

**3.2 The grade the Idris side can build.** P0 §5.8 DS1.1 wants one enum
of legal grades with an attribute interface. Lane 01 keeps quantity and
permission as two enums, since six pairs occur, and no interface, since
the skill forbids one where the type fixes the implementation (01 C1,
NQ4). Lane 17 wants the generated Idris view to offer the frontend only
the grade it writes (17 C4, FB-30). Under lane 01's form the generated
`QType` stays a product the frontend could misuse; unrepresentability on
the Idris side then needs either a per-stage grade view (lane 14's TD6
applied to grades) or a generated frontend-only `lin` constructor.

**3.3 DD-Q1, normalizing `!idr.lin<i64>` to `i64`.** The lanes agree on
the facts (128 uses in 13 test files, 17 §3.3; 127 of 434 `lin`s, 01 §6;
the world is already normalized this way, 15 §6) and lean differently.
Lane 15: normalizing at the builder "loses nothing the frontend holds".
Lane 17: normalizing at construction "is the boundary dropping it, not a
pass". Lane 01: it is no pass, but afterwards no verifier sees a word's
quantity, and today that quantity catches passes that duplicate a use.

**3.4 QL2, a case region binding its refined scrutinee.** Lane 17 marks
§5.7 L1 "holds" because Idris's `ConCase` binds the constructor's
arguments (17 §3.1). Lanes 15 (TM-6, "refuted today"), 01 (§6 QL2: the
default rebinds the scrutinee unrefined; no type says "this value is
C") and 03 (§6 QL2, NQ1) say it does not. L1 asks for the refined
scrutinee, not the fields, so lane 17's verdict answers a different
question. If QL2 is adopted, the frontend already knows the refined value
(`VarInfo.Shaped`) and `Alt` gains it in one constructor (15 §6).

**3.5 The checks.** DS4 merges the five check ops into `arith.cmpi` plus
one `idr.check <reason>` (P0 §5.8 DS4). Lane 03 keeps five ops of one
class, each returning its operand refined, because the merge loses the
data dependence (03 §5.3, checks row). Lane 14's guard design survives
either (14 TD4). Lane 03's form costs the Idris side a generated
`CrashCause` enum in place of strings (03 §5.4).

**3.6 One op for several primitives (DD-Q5).** Lane 03 makes
`io.clock <kind>` one op and one runtime function taking the kind, and
the six file times one `io.file.times` with six results (03 §5.3, §6
DD-Q5). Lane 14 finds that the generator refuses an attribute on a
primitive (T28), the ABI generator refuses an op with more than one
result, and base calls the six file times one by one, each its own
`%foreign`; so a six-result op is a merge the frontend or a
canonicalization must perform, not a translation of one base call (14
§6 DD-Q5). It turns on whether a registry entry may map several base
primitives onto one op and pick a result.

**3.7 The run-time case tree (Q-FB1), against AGENTS.md.** Lane 17 offers
(a) keep an erasure-only run-time tree in the TTC and translate it,
deleting `Forced.idr`, or (b) stop building it, since it is computed and
dropped today (17 C3, FB-07, FB-38). AGENTS.md says: "The compiler
consumes checked Idris TT and its definition context. Do not replace that
input with CExp or runtime case trees". Option (a) is that replacement,
and lane 17 does not cite the rule. Lane 15's plan assumes (b) (15 D-4).
Option (a) needs the rule changed first; (b) fits it.

**3.8 How Emit gets linearity right (Q-FB2).** Lane 14 keeps Emit's use
count and makes it linear with summaries from the paramorphism (14 E03,
0003 D1). Lane 17 deletes the count: the translation hands Emit
quantities proved of the term it returns and states each demotion at the
binder (17 C5). The first fixes the cost; the second moves the check to
the boundary. AGENTS.md pulls both ways: "No pass may drop what Idris
proved", and "Linearity is a performance property, never a correctness
one".

**3.9 P0 against 0011 and 0003.** 0011 marks every stage AFTER-SELF,
needs its O0 measurement first, takes no stage under 5% of the frontend's
wall (0011 D0), and accepts a stage only on identical bytecode (D5). 0003
is queued after self-hosting (0003 status). P0 comes first (P0 §9 D1) and
its goal is "no rederivation chains". Lanes 14 and 15 propose the small
forms of 0011's O2 and O3 now (14 TD3; 15 D-1, D-3, D-5; ft-Q2). Lane 20
says 0003 must be folded in or deferred item by item (20 §5.2 item 4).

**3.10 Where polyvariance would go (Q-O4, ft-Q3).** P0 §5.9 Design 7 puts
it in C++ before the label solve, and lane 06 between deduplication and
defunctionalization (06 §6). Lane 15 says the frontend already holds the
source lambdas, a keyed instance cache and the growth bound (15 D-9, §6
Q-O4). In the frontend it grows the Idris side and the growth check's
scope; in C++ it never sees a source lambda.

**3.11 Wave 1 corrected by the lanes.**
- P0 §5.3 E3 says `MlirTblgenMain` gives a custom tool every upstream
  generator. Refuted at the pin: `MLIRTblgenLib` is the driver alone, so
  "one tool" (Q-llvm-5) needs upstream's generators made a library (14
  §3.1).
- P0 §5.2 row 13 (op configuration as properties) collides with the Idris
  writer, which writes no native property (14 T23, B11).
- P0 §5.6 item 5 and §5.11 (A) list the analyses a refusal rests on and
  omit the growth check and the reach walk (16 §3.1).
- P0 §5.7 H3 (binding times stated as types) is a language change, out of
  P0's reach (16 §3.1).

## 4. Suspected bugs and rule violations

Ground: *read* unless marked. "AGENTS.md" names the rule broken.

| # | what | where | ground | lanes |
| --- | --- | --- | --- | --- |
| 1 | **Valid programs refused**: a compile-time argument to a `let` value whose type the TTC dropped is refused as `ValueType`. AGENTS.md: no representation limit refuses a program. | `Terms.idr:399-404`; `TTC.idr:611-612` | read | 17 FB-01, 15 TS-5, 0003 C1 |
| 2 | `siblings` answers `[]` on a miss, so a default that stands for no value is translated | `Cases.idr:155-176` | read | 15 CS-2, 17 FB-05, 0003 C2 |
| 3 | Erasure decided by five readers with different defaults; an argument behind `-@` can be erased to one and runtime to another | `Closed`, `Forced`, `Sites`, `Terms`, `Types` | read; a disagreeing program: conjecture | 17 FB-15, 15 TS-3, 16 FC-52 |
| 4 | Fork bug: `paramPos` misses parameters hidden behind a definition; the frontend patches it. AGENTS.md: fix it in the fork, with a `PINS.md` entry | `Core/Context/Data.idr:71-92` | read | 17 FB-18 |
| 5 | A block's parent kept as printed text: a wrong root can hang the normaliser and change trusted admission | `Name.idr:45-46`; `Closed.idr:415-450` | read (0003 B1) | 17 FB-10, 15 CL-4 |
| 6 | Spelled escape hatches keyed by root-name string: an unrelated definition with the same root is silenced | `Profile.idr:163-164, 458-459` | read | 16 FC-81, 0003 B4 |
| 7 | Imports found by `words`: an import in a block comment is imported (and can be refused); one split over lines is missed | `Profile.idr:113-130` | read | 16 FC-79, 17 FB-11 |
| 8 | Emit demotes a quantity-1 binder to plain when the translated body uses it twice: the emitted quantities are not Idris's, and the `quantities-kept` contract cannot see it | `Emit/Bodies.idr:131-138` | read; frequency unmeasured | 17 FB-28, FB-31 |
| 9 | The growth check may under-approximate: a dispatched argument past `own` dropped with no arc; an unresolved method field taken as hand-written; three lists truncated silently on a length mismatch. Only `Finite`'s run-time witness would catch it, as an internal error | `Heads.idr:246-250`; `Implementations.idr:160-166`; `Sites.idr:492-508` | conjecture | 16 FC-35, FC-40, FC-53 |
| 10 | Theorem 1 is proved over a three-constructor model, not the code's 11-constructor `Template`; a run-time check bridges them | `Proof/Bound.idr:55-58`; `Finite.idr:176-202` | read | 16 FC-73, FC-95 |
| 11 | "Never checked" collapsed into "may not terminate" by `fromMaybe False` | `Translate/Programs.idr:78` | read | 16 FC-96, 15 PG-4 |
| 12 | `Faster` labels hooks that are a bodiless extern's only meaning; a `Faster` entry validates on a bodiless definition; nothing checks AGENTS.md's "removing the hook leaves the same result" | `Registry/Entry.idr:322-356, 445-454` | read | 14 R15, R16 |
| 13 | A refusal rule's category false at some sites (`StaticArgument` refuses a choice the program bounds) | `tests/static-argument-stuck-implementation` | read via 0003; other rules recalled | 15 §1, 0003 |
| 14 | Acceptance decided by a count in elaboration: `%ambiguity_depth` (3), `%auto_implicit_depth` (50) | `TTImp/Elab/Ambiguity.idr:326-334`; `App.idr:272-274` | read | 17 FB-40, FB-41 |
| 15 | A per-target case outside the target's entry: Windows branches in the fork's path module, which the frontend calls. AGENTS.md: a bug | `Libraries/Utils/Path.idr` | read | 17 FB-48 |
| 16 | Refusals kept in the discardable `idr.refusals` on the module (no pass reads it today). AGENTS.md: no fact in a discardable attribute | `Emit.idr:100-108` | read | 14 T38, E23 |
| 17 | Float text agrees across the two hosts by coincidence of two printers (Chez's and the runtime's Ryu); one branch is dead on the idris-mlir host | `MLIR/Text.idr:124-142` | read | 14 X01 |
| 18 | Dead work: a search timer checked at every unfolding, never started; a run-time case tree built for every definition and dropped | `Core/Context.idr:2553-2584`; `ProcessDef.idr:722-843` | read | 17 FB-39, FB-38 |
| 19 | One fact held twice across the generated boundary: `CmpPredicate` in Idris and C++; `Profile.outsideLanguage` restating `IdrBase.td` while the generated `ruleCategory` is read by nothing; the harness's hand copy of Idris's primitives and the lowering's guards | `Emit/Operations.idr:176-194`; `Profile.idr:52-70`; `harness/Prims.idr:3-10, 535-610` | read | 14 E14, 16 FC-78, 19 G6 |
| 20 | Fuel in the Idris test machinery (`bitLength`), against the skill's "never fuel"; lane 19 calls it essential under the subset | `harness/Prims.idr:239-251` | read | 19 G7 |
| 21 | The frontend got slower and larger between two runs with no record of why: 345 s, 5.64 GB on 2026-10-18 against 450–528 s, 6.5 GB on 2026-10-20 | the record; 0001 §0 | measured (two runs, different trees) | this reader, from 15 §2.6 and the record |

Cross-cluster, noted only: `Array.Core`'s 21 externs mean the dialect's
ops, not a runtime function, against AGENTS.md's "a primitive of `libs/`
means only what `runtime/` says" (11 N3, arr-Q3; cluster C).

## 5. The decisions this cluster hinges on

The §8 IDs, grouped into ten decision points. For each: the options, the
evidence, and what depends on it.

**D1. Cut over with the dialect, and how the mirror is built.** [Q3,
Q-llvm-5, ids-Q1, ids-Q4; T-Q2 is cluster E's]
- *Q3*: one commit with the `.td` change, or staged. All three lanes say
  a change that renames or removes anything the frontend names breaks the
  Idris build on both hosts, and a shim is a second copy (14 §6; 15 §6;
  17 §6). The owner's hard-cutover ruling excludes the staged form with a
  shim. So Q3 is settled in substance; what is left is one commit for the
  whole redesign or one per op family, each culling the old form. Cost measured: 73 `Idr.*Op` call
  sites in Emit, 70 upstream builders, at most 220 primitive-constructor
  uses (14 §5.2). Ops the frontend does not write change nothing but the
  regeneration.
- *Q-llvm-5*: one tool needs an upstream patch (the generators as a
  library) or upstream sources compiled into ours; two tools over one
  record set are not two copies (14 §3.1, TD1). How the generator's C++
  is written is settled (concept-constrained templates, the owner's
  ruling); how many tools there are is not.
- *ids-Q1*: keep the 15 generated modules checked in (fingerprint only
  the records and the output: 16 of 29 commits to `Syntax/Idr.idr`
  restamped only the fingerprint, 14 T50), or make them build outputs.
  *Conjecture* of this reader: as build outputs, the frontend's stage-0
  build on Chez would need the C++ generator, hence MLIR, built first.
- *ids-Q4*: prime every generated binder, or keep a keyword list copied
  from the fork's lexer (14 T01).
- *Depends on it*: every Idris-side change in cluster A's cutover.

**D2. The handoff's encoding.** [ids-Q3, ids-Q2, ft-Q4]
- *ids-Q3*: every `idr` type and attribute native in bytecode (14 TD2, 01
  C8, 0011 "owed"), or text kept and upstream patched to make the format
  parser a library. Unmeasured: how much of the 71 MB is text payload (14
  §8). A native `!idr.data` makes the reader resolve a name while reading,
  as the text parser does now (14 §8).
- *ids-Q2*: accept "every property the frontend writes is an attribute"
  as a constraint on ODS, or generate each op's property encoder for the
  Idris writer (14 T23).
- *ft-Q4*: keep the Core dump (79 MB, built as one string, 15 TM-9),
  streamed, or delete it and move its two readers (the harness's prelude
  coverage, one test) onto the module (15 D-7).
- *Depends on it*: lane 01's data type and body (DS3, C4), lane 03's
  attributes, carried upstream patch 03.

**D3. Frontend or dialect: who decides a representation, and which known
facts become IR.** [ft-Q1, types-Q2, Q-O3, Q-E2, ops-Q3, arr-Q2, arr-Q4,
tail-Q1, DD-Q7]
- *Options*: (a) the frontend states only what Idris knows and the
  dialect decides layout once from the type graph, so the newtype
  collapse, `!idr.nat`, the `u64` mapping and the crash enumeration move
  or are justified as Idris facts; (b) the frontend also decides layout,
  boxes included (types-Q2).
- *Facts the frontend knows and does not write* (15 §6 Q-O3): let types,
  a match's data instance, a value's known constructor, coverage beyond
  `Crash`/`Unreachable`; also tail position (10 D1b), a static
  suspension (06 D-11), a link (11 N2).
- *Evidence*: §3.1 above. Tail position and call effects both need
  `idr.call`, since `func.call` can carry neither (10 §5 D1b; 03 §6 DD-Q7).
  `DataTableAttr::verify` could refuse a cycle once per table if the
  frontend emits boxes (01 NQ2).
- *Depends on it*: cluster A (DS3, DD-Q7), B (what analyses then read
  instead of solving), C (tail, arrays).

**D4. The grade and the refined scrutinee the frontend writes.** [DD-Q1,
types-Q4 with DS1, QL2 with ops-Q1]
- *DD-Q1*: keep `lin` on words, or normalize at construction (§3.3).
- *DS1*: two enums (01 C1), one enum of legal grades with an interface
  (P0 §5.8), and whether the Idris view is narrowed to `lin` (17 C4)
  (§3.2).
- *QL2*: whether `Alt` binds the refined value as well as the fields (15
  TM-6; 03 §5.2(a)); see §3.4 for the lanes' split.
- *Depends on it*: cluster A's types, cluster C's linearity verifier and
  counting, Emit's `heldType` and `coerce` (14 §6 DD-Q1).

**D5. The world.** [DD-Q3, ods-Q2]
- *Options*: no world after the frontend, IO ordered by effects (DS2.1),
  or the world kept with every effect derived from it (DS2.2).
- *Evidence on this side*: the world is a Core value end to end: the last
  operand of `Effect`, a binder of `TabulateIO`, the root's parameter,
  forged by `NewWorld`; `IORes` is a data type the frontend registers (15
  §6 DD-Q3, TM-12). The generated IO primitives, `IOResult` and the C
  ABI's `World` kind all carry it (14 §3.1). It sits on 44 op definitions
  (03 §6). The world and `IOResource` have coexisted since the first commit
  with no recorded decision (20 §6). Under DS2.1 the frontend may keep the
  world inside Core and drop it at Emit, or Core loses it too (15 TM-12).
- *Depends on it*: cluster A's resource tree, cluster B's effects, the
  registry's 124 IO rows.

**D6. Op families, the registry and names.** [DD-Q5, ids-Q5, DD-Q4,
DD-Q8, ops-Q2 with conv-Q1, canon-Q3]
- *DD-Q5*: §3.6. *ids-Q5*: should an op's record name the base primitive
  it implements, so the 124 IO rows are generated, or does the registry
  stay the one place that names a library definition (14 TD10, not
  recommended without the owner)?
- *DD-Q4*: the frontend is arith's school at the dialect already (it picks
  the op by sign at ten sites) and CIR's school inside Core (15 §6); an
  `IntTy` sum replaces `signed : IntTy -> Bool` either way (15 TY-2).
- *DD-Q8*: the Idris side spells no op name; a rename is a regeneration
  plus call sites; no Idris code writes `dup` or `drop` (14 §6).
- *canon-Q3*: no Idris cost; the frontend writes no `put_*` (14 §3.2).
- *Depends on it*: cluster A, cluster C (runtime functions, crash causes).

**D7. What the frontend reads from the fork.** [Q-FB1, Q-FB2, Q-FB3,
ft-Q5, tail-Q4]
- *Q-FB1*: §3.7, including the AGENTS.md conflict of option (a). Measure
  the elaboration time `compileRunTime` costs before choosing (b) (17 §8).
- *Q-FB2*: a demotion the boundary may make and state, an internal error,
  or a refusal (§3.8).
- *Q-FB3*: remove the two elaboration counts the way `%totality_depth`
  was removed (a memo; the exponential ambiguity search then needs one,
  its cost to be measured), or accept them as Idris's type checking (17
  C7, §8).
- *ft-Q5*: give the fork's `Error` a constructor for the frontend's
  refusal, deleting the side channel `TS.inFlight` and the dedupe by
  printed text (15 ST-7, ER-1). *This reader's note*: the fork may never
  import `IdrisMLIR.*` (AGENTS.md), so that constructor cannot name the
  frontend's `Rule`; it needs a payload the fork defines, or the
  translation's own error type (15 ST-7's alternative).
- *tail-Q4*: once the TTC keeps a block's parent, emit a clause's case
  block in place as a match region; whether each case block keeps one
  call site through the frontend's specialization is unsettled (10 §5 D4).
- *Depends on it*: cluster B (contify), cluster C (what counting reads).

**D8. How much of the frontend's own refactoring P0 takes.** [ft-Q2,
hist-Q4, Q-fc-1, Q-fc-2, Q-O4, ft-Q3, Q-M5]
- *ft-Q2, hist-Q4*: the small forms now (15 D-1, D-3, D-5; 14 TD3), 0011's
  O2 and O3 folded into the cutover, or both left to 0011 and 0003. 0011
  says measure first, and its O0 record does not exist (§3.9). The
  owner's ruling ("maximal churn toward the most elegant representation")
  leans toward the larger form and away from deferral, and the
  type-driven lens it names is what 15 D-8 and 16 G2–G7 already apply;
  but it does not say whether 0011's measure-first gate (D0) still binds
  inside P0, nor whether 0003's 21 items are absorbed, so ft-Q2 and
  hist-Q4 still need an explicit answer.
- *Q-fc-1*: make the code's `Template` the proof's model (the frontend
  builds the derivation and the run-time witness goes), or record the
  witness as a trust point the way `covering` is (16 §6).
- *Q-fc-2*: if stage 1 shows the node split's products large, split the
  flow by node; no budget may cut an acceptance analysis (16 §6).
- *Q-O4, ft-Q3, Q-M5*: polyvariance in the frontend or in C++ (§3.10); the
  frontend is already demand-driven from `main` with instances keyed
  before translation (15 §6; 16 §6).
- *Depends on it*: cluster B (what the label solve sees), cluster E
  (measurement).

**D9. Rules the cluster asks to be stated.** [Q-llvm-2 with Q-E3 and
oom-2, ids-Q6, T-Q1, QL4]
- Name the growth check and the reach walk among the analyses a refusal
  rests on, which take no budget; both already meet the rule (16 §6).
- *ids-Q6*: a mode that drops the `Faster` hooks and a test comparing both
  ways (no Chez, so no oracle in AGENTS.md's sense), or a review rule (14
  R15).
- *T-Q1*: the invariant set every step passes unchanged, which is also
  the gate for the frontend's byte-identical acceptance (14 §8; 15 §8).
- *QL4*: the frontend is single-threaded with fixed orders (16 §6); the
  one determinism risk here is an id reaching a symbol (15 §8).
- *Depends on it*: cluster E.

**D10. Process.** [Q2, Q4, perf-Q1, perf-Q3, hist-Q2] Who measures the
frontend half, in the per-run record perf-Q3 asks for (21 NQ-21-3); and
whether each step must build under both hosts before the next (hist-Q2).

## 6. Order of work, and dependencies

Within the cluster, in five steps. Each change deletes what it makes
dead in the same commit.

1. **Measure** (§7) and **no-dependency work**: in the fork, the dead
   timer, the module list, the exported component search, the Windows
   branches, `public export` on `ZeroOneOmega`, and the low-risk TTC facts
   (package, main path, imports, pragma uses) (17 C1, C6, C8); in the
   generator, the typed model and its C++, written as concept-constrained
   templates per the owner's ruling (14 TD1, TD9); in the checks,
   `Template` and the arc labels (16 G2, G3) and the proofs (G9–G11); in
   the translation, locations (15 D-5) and the type-driven rows file by
   file (D-8).
2. **One signature, one table per thing, the registry resolved once**: 17
   C2 with the fork's `paramPos` fix (a `PINS.md` entry and
   `upstream/<bug>/pull-request.diff`, AGENTS.md); 15 D-2 with RS-1; 14
   TD7; the checks' readers (16 G12, G14). Then one identity per instance
   (15 D-1, which needs lane 16's `Address`), with the admission as a value
   and one numbering (16 G1, G4) in the same change, since data
   registration reads the bounds (16 §8); then the memo (15 D-3) behind
   its gate.
3. **The TTC's term facts**, one per change, each deleting its reader:
   the let type (which ends bug 1), `scTy`, the clause index, `WhyErased`
   after the probe, the block parent (17 C1). Q-FB1 then decides
   `Forced.idr`'s end (17 C3). Q-FB3 and ft-Q5 when the owner rules.
4. **Emit**: the facts generated to both sides that need no other lane (14
   TD5), arity-indexed guards and primitives (TD4), then values as numbers
   and ops indexed by result count (TD3, the largest change, gated on a
   byte-identical module), then linearity at the boundary after Q-FB2 (17
   C5).
5. **With cluster A, one hard cutover in the commit that changes the
   `.td` files**: Core on the new grain (15 D-6), the native handoff (14
   TD2) once lane 01's data type and body and lane 03's attributes settle,
   the data table's body (14 TD8), the stage-scoped vocabulary (14 TD6)
   once ops declare their stages, the grade (17 C4), the world, the check
   and clock families, and renames last (03 §5.5 item 6).

**Dependencies on other clusters.**
- *A (the dialect's surface)*: the grade (01 C1, DS1), the data table and
  body (DS3, 01 C4), bytecode records (01 C8), properties (P0 §5.2 row
  13), stages per op (ops-Q4), op families (03 R1), the world (DD-Q3),
  our own function op (DD-Q7). Step 5 cannot start before these settle.
- *B (analyses and solvers)*: contify and case blocks (tail-Q4); the label
  solve and polyvariance (Q-O4); a static suspension the frontend could
  state (06 D-11); the effects decision (defunc-Q2). C++ reads the
  frontend's `total` as divergence in four passes (16 §2.2).
- *C (counting, tail, lowering, arrays, runtime)*: counting reads the
  quantities the frontend writes (Q-FB2, DD-Q1); arrays want a link op and
  a transpose as a tabulate (arr-Q2, arr-Q4); the runtime gains a clock
  function taking a kind (03 §6 DD-Q5); tail position on the call
  (tail-Q1).
- *E (pipeline, tests, history, the parallel agent)*: the invariant set
  and fixture rewrites (T-Q1, T-Q2); the Core dump's readers in the
  harness; the harness's primitive list generated from the guard records
  (19 G6); per-run records (perf-Q3). The parallel agent has not touched
  the Idris side (21 §2.3), but main has been at 403/480 since 101edbc5
  (21 P-16), so a byte-identical gate needs a green base such as
  e96bb991 (21 §5.5).

**What the two-hosts rule constrains.**
- Every new index stays a parameter no field stores: `Op n`,
  `Template Stage`, `Signature arity`, `Vect arity`. A record holding `n`
  and a `Vect n` is refused as a dependent field (14 §8; 16 §8; the
  skill's subset).
- No deriving: an enum is written four times by hand (16 FC-93); a
  generated `Eq` should be one clause, for both hosts' compile time (14
  T08).
- Tables on `Data.IOArray` and `Data.Buffer` have an unmeasured cost
  under idris-mlir; on Chez a representation buys memory more than time
  (15 §8; 0011 §6).
- A `Nat` index such as `power 2 64` might unfold in unary in the type
  checker; try it on both hosts first (16 §8). A `Fix`-style base functor
  may fall outside the subset; `children`/`withChildren` is the safer
  traversal (16 §8).
- Every `ttcVersion` bump rebuilds prelude, base and `libs/` under both
  hosts, and the fork must keep building at stage 0 on Chez (17 §8).
- Write floats as bits, never as host-printed decimals (14 X01). No
  `%extern` in the frontend, no `covering` added (15 §5).
- The generated modules compile under both hosts: about 2,800 lines of
  builders, most unused, until TD6 (14 §8).

## 7. Risks, and the measurements that must exist

**The frontend half today.** On 2026-10-20 the frontend compiled itself
in 450–528 s at 6.5 GB peak and wrote a 71 MB module (0001 §0, measured
under `build/self/stage1`, in no committed record). The last committed
record, 2026-10-18 on Chez, took 345 s at 5.64 GB: checks 0.8 s,
reachable 9.4 s, growth 64.7 s, translate 171.8 s, emit 50.8 s (297.5 s;
about 48 s falls outside these phases), an 82 MB module and a 79 MB Core
dump, 69,697 instance translations, about 69,773 Core functions and 6,743
data types (`bench/records/2026-10-17-self-growth.md`; 15 §2.6). Between
the two runs the module shrank by 11 MB (b9d4d592 writes a data type as
its name) while time grew 30–53% and peak by 0.9 GB, with no breakdown.
Nothing tells where translate's 172 s goes (15 §8).

**Risks.**
- A memo key that misses a dependency (what the call offers, dictionary
  fields read from runtime records, implementations closing over runtime
  values) is a silent miscompile, as 3934cc0c fixed once (15 §8).
- An id that reaches a symbol breaks stage 2 = stage 3 (15 §8; 0011 §7).
- TD3 rewrites about 2,000 lines of Emit; the module must stay
  byte-identical and emit's time and peak must hold (14 §8).
- TTC growth: keeping term locations grew the installed prelude from 2.2
  to 3.6 MB and base from 17 to 30 MB; more facts grow it again (17 §8).
- Moving the check's proofs onto the trie costs type-checking time;
  `tests/growth-check` (542,896 graphs) must stay identical (16 §8).
- Three products in the growth graph (`combinations`, `familyHeads`,
  `choices`) could be the next wall, and no budget may cut them (16 §2.4,
  §6 oom-2).
- The 79 MB Core dump is one string; its share of the 6.5 GB is unknown
  (15 TM-9).

**Measurements, deduplicated** (none can run in this checkout; all on
stage 1 at one recorded commit, before the work and after each step).

| # | what | asked by |
| --- | --- | --- |
| M1 | the frontend's phases at stage 1, elaboration included, with peak memory per phase, in a committed record | 15 §8; 16 §8; 0011 O0; 21 NQ-21-3 |
| M2 | the heap by kind: Core trees, locations, key token lists, the Core dump string | 15 M-4, M-7 |
| M3 | repeated work: `normaliseClosed`, `classifyCall`, `instanceKey` against new instances, `coreType` against distinct types, `Forced.split`, `partialIn`, `toLoc`; translations per distinct instance | 15 M-5, M-6 |
| M4 | the module's census: ops, values, blocks, regions per op; the widest matches and where they come from, crash enumerations included | 15 M-1, M-2; P0 §5.1 W1, §5.9 Q-W1 |
| M5 | the text payload's share and the reader's parse time; the writer's intern maps | 14 §8; 01 §5.10 |
| M6 | linear against bare binders; how often Emit demotes a linear binder | 15 M-3; 17 §8 |
| M7 | `eraseArgs` against the five readers on the corpus and the self-compile, before C2 | 17 §8 |
| M8 | TTC sizes and frontend time around each fork fact; `compileRunTime`'s elaboration time before Q-FB1 (b) | 17 §8 |
| M9 | growth sub-phases; sizes of the three products; flow rounds; components with a losing arc; chain lengths at `elemLink` | 16 §8 |
| M10 | Idris compile time of the generated modules under both hosts before and after TD6; `Data.IOArray`'s cost under idris-mlir | 14 §8; 15 §8 |
| M11 | the cost of memoised ambiguity resolution on base and the frontend, if Q-FB3 removes the count | 17 §8 |

## 8. What is stale or unverified

- Nothing was built or run by lanes 14–17; every count is over the source
  (14 §9; 15 §8; 16 status line; 17 §8).
- All four lanes read e96bb991. origin/main has moved to 101edbc5 and
  51a4771b, which touch no file of this cluster (21 §2.3) but shift the
  `IdrBase.td` lines past 292 that lanes 16 and 17 cite (21 §3.5, "line
  drift only").
- The S3 frontend number has no committed record (0001 §0; 21 P-17), and
  the 2026-10-18 and 2026-10-20 runs do not reconcile (§7).
- Lane 17's verdict on §5.7 L1 contradicts lanes 15, 01 and 03 (§3.4).
- Lane 14 asks whether the term exposes its free variables cheaply for
  TD3's captures (14 §8); lane 15 does not answer.
- No lane cites AGENTS.md's rule against translating run-time case trees
  when weighing Q-FB1 (§3.7).
- Conjectures that remain: the growth check's silent drops (16 FC-35,
  FC-40); which readers meet a non-user name's defaulted type (17 FB-08);
  an unused import (17 FB-46); whether every case block keeps one call
  site through specialization (10 §5 D4); `Address` as one word (16 G4).
- 0003's status says the binary format is "no longer read by hand"; it
  holds for the data table, while most `idr` types and attributes still
  cross as text (14 §3.1).
