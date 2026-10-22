<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L16: the Idris frontend: TTC facts, typed tables, the absorbed plans, the growth proof

*Lane L16 of the P0 verification swarm. HEAD `e96bb991` at the start
(2026-10-21T21:31Z) and at the finish (§6's foot). Nothing was built or
run: every count is a `grep`/`wc` over the tree at HEAD, with its
command; every cost not counted is marked. Ground marks: *read*
(path:line at HEAD), *measured* (the command), *recalled*, *conjecture*,
*decision* (a ruling Dn or Cn). Paths under `compiler/src/IdrisMLIR/`
unless they start otherwise; the fork is `compiler/idris/src/`. "NN X"
cites `audits/p0/NN-*.md` row X; "D §n" synthesis D.*

Rulings in scope: D8, D12, D13, D44, D46, D48 (the frontend's side), D50,
and AGENTS.md's two hosts. Read in full first: the representation-first
skill, AGENTS.md, `proposals/0000-mlir-native.md`; then 15 and 16 whole,
17's TTC parts (§1 on 0003, §2.3–§2.5, §3, §4.1–§4.3, §5 C1–C5, §6–§8),
synthesis D whole, proposals 0003 whole, 0010 (A0, §1–§3, §10, §12),
0011 whole, 0015 whole; then the code named in §1 and §2.

## 1. Verification

### 1.1 The rulings

**D8 (the Idris side is in scope, type-driven, in the subset): holds.**
- The frontend is the shape the ruling asks for in its checks and proofs:
  no fuel, no budget, no `covering`, `assert_total` or `believe_me` in
  `Frontend/` or `Proof/` code (*measured*: `grep -n
  "covering\|assert_total\|believe_me"` over `Frontend/Translate`,
  `Frontend/Growth`, `Proof`: comments and strings only, e.g.
  `Translate/Terms.idr:1164-1176`).
- It is not yet that shape in the translation: 72 `internal` sites in
  `Frontend/Translate/*.idr`, 61 `SortedMap` mentions over `Translate/`,
  `Frontend/`, `Term`, `Types`, `Ids`, `Loc`, 40 per-site quantity reads
  (`use rig`/`use q`), 113 `EmptyFC` in `Frontend/` (*measured*: `grep -c`
  over those files at HEAD). *Structural incompleteness*: the typed
  tables D44 names do not exist; §2.3 states them.

**D12 (a strict subset, never a contradiction): holds with a correction.**
- The frontend refuses only by rule (75 `reject ` sites across
  `Frontend/`, *measured*) and passes upstream's pragmas through the
  elaborator (`Frontend/Profile.idr:136-141`: `default`, `hide`,
  `unhide`, `logging`, every other pragma refused, which a subset
  allows). *Defect confirmed in source*: one refusal is a representation
  limit, not a construct: `applyOver` refuses a compile-time argument to a
  `let` whose type the TTC dropped (`ValueType`; the encoder writes the
  type as a comment, `Core/TTC.idr:612`, reads `Erased`, `:482`; 17 FB-01).
  AGENTS.md forbids it; it goes with the TTC fact (§2.2 row T1).
- *Integration mismatch*: the fact Emit writes as `idr.func`'s `total`
  (`Emit/Declarations.idr:56`) is `Facts.terminating`
  (`Facts.idr:11-18`), "every loop through it terminates": termination
  only, not upstream's `total` (terminating and covering). The name says
  upstream's concept and means a narrower one. Under D22 and D27 the fact
  is the source of the `divergence` atom and is named for that (§4 I1).
- The frontend proves termination of `partial` and `covering` definitions
  itself, by upstream's own size-change algorithm per component
  (`Translate/Recursion.idr:112-135`, the fork's `loopsTerminate`). That
  is more precise than upstream and changes no meaning (D12 refined:
  "we may even be MORE CORRECT"), *provided* the composition is sound,
  which it is not (D13 below).

**D13 (eager evaluation; only totality licenses deletion): holds with two
corrections on the frontend's side.**
- *Defect (conjecture as to reachability; read as to the facts)*: the
  per-definition termination fact composes unsoundly once
  specialization and defunctionalization make call cycles Idris's graph
  never had. The fact is "a loop never leaves its component; what it
  calls outside carries its own fact" (`Facts.idr:13-17`). A lifted
  lambda is written `total` because "a recursion goes through a function
  of the program, which carries its own proof or its absence"
  (`Emit/Closures.idr:89-93`). C++ sums each member's own fact over an
  SCC (`foreign/idr/lib/IR/Func/Func.cpp:189-201`: `getTotal() ?
  Effect::none : Effect::diverge`). Two kinds of cycle break the
  premise: recursion through a stored function of a non-strictly-positive
  type, which needs no call of any definition to itself, and mutual
  recursion through two implementations that call each other through a
  method projection, which Idris's graph records as a call to the
  projection (§4 I1 gives the program). Both members read "terminates",
  the SCC reads no divergence, and an unused call can be deleted, which
  gives a looping eager program a lazy meaning (D13). Idris computes
  every type constructor's positivity even outside a total context
  (`TTImp/ProcessDecls/Totality.idr:25-28`, "#524"), but the frontend
  reads none of it (`grep -rn -i positiv compiler/src`: none in code).
- *Unverified behaviour*: `delayedLets` (`Translate/Closed.idr:184-197`,
  used at `Translate/Terms.idr:434-441`) moves every `let` chain around a
  `Delay` into it. For `do { a; let x = v; b }` this keeps the language
  over the elaborator (the tutorial's desugaring, `let x = v; e` to `let x
  = v in e`, at the second argument of `>>`, which is `Lazy`,
  `third_party/Idris2/docs/source/tutorial/interfaces.rst:285-291`), and
  D12 says to keep the language. For a user's explicit `let x = loop in
  Delay 3` it changes the meaning: eager evaluation runs `loop`. The fact
  that tells the two apart (the elaborator inserted this `Delay` for a
  `Lazy` expected type) exists in the elaborator and is not kept (§4 I6).

**D44 (P0 absorbs 0003 and 0011 whole, 0010's A0, 0015's R1 and R2):
holds with five corrections.**
1. *"Its 21 standing items" miscounts 0003.* The 21 is lane 20's probe of
   24 items (20 §4.3), and the probe is wrong at HEAD: it reports `covers`
   gone from `Forced.idr` and `outermost`/`rootOf` gone, but
   `Translate/Forced.idr:255` (`covers`), `Translate/Closed.idr:419`
   (`outermost`), `:437` (`rootOf`) and `Translate/Keys.idr:258`
   (`keyOrigin`) all stand (*read*). So 23 of the 24 probed stand (only
   the TTC's term locations, 374e0e77, are built, and its `bestFC`
   fallback stands). And 0003 holds 62 item bullets in six sections, not
   24 (*measured*: `awk '/^- \*\*/'` per section of
   `proposals/0003-facts-once.md`: 20, 5, 9, 5, 10, 13). "0003 whole" is
   the 62; §2.9 places each.
2. *The absorbed bars cannot be measured where P0 puts them.* 0011's
   bars are ratios to O0, "measured once, natively, on the
   self-compiled frontend" (0011 §2 D0, §8); 0010's A0 bar is a ratio to
   0013's T0, taken "once `make self` is green" (0010 §10); 0015's R3 needs
   0011's O0 "at `make self`" (0015 §6). P0 comes before self-hosting
   (`proposals/README.md`, "After P0, the goal is self-hosting"; D1). No
   native frontend exists: S3's frontend half ran on Chez (450–528 s, 6.5
   GB, `proposals/README.md`), and the pipeline half has never finished.
   Owner question 2.
3. *"0011 whole" holds stages whose needs are not absorbed.* O6 needs
   0009's stages 4 and 6 through a plain-Idris layer (0011 §8, D11); O7
   needs 0015's R4 (0011 §8). D44 absorbs R1 and R2, not R4, and 0009's
   array cutover (D43), not its stage 7 layer. Owner question 3.
4. *0011 D0 contradicts "whole".* D0 drops a stage whose phase is under
   5% of the frontend's wall at O0; D44 takes the whole. Folded into owner
   question 2.
5. *R1's and R2's bars stand outside the tree.* R1's proof is bumbledb's
   2,879 cases and its 32 read families at ≥ 80% of bumbledb's Rust
   engine; R2's is within 1.5× of Soufflé (0015 §6). Neither engine is in
   the toolchain, and the Rust figures are bumbledb 2.0.0's own
   measurement on its machine (0015 §5). The frontend's consumer (O3) needs
   only layer 2's semi-naive fixpoint. Folded into owner question 2.

**D46 (the growth proof covers the code): holds with a correction, and
one link needs the owner.** §2.10 designs it; the findings:
- *Read*: Theorem 1 is over a three-constructor model
  (`Proof/Bound.idr:80-83`: `Var`, `Head`, `Leaf`); the code's `Template`
  has eleven (`Frontend/Growth/Template.idr:75-98`); nothing imports
  `Proof.Bound` (16 FC-95). The bridge is a run-time check:
  `Finite.heightWithin` (`Frontend/Finite.idr:187-192`), `sizedWithin`
  (`:197-202`) and `boundsHold` (`Translate/Types.idr:847-853`).
- *Structural incompleteness*: Theorem 1 concludes only a height bound
  (`bounded`, `Proof/Bound.idr:304-306`). The worklist's termination needs
  more: `sizedWithin` returns `Inside b l` (`InUniverse`: the link's
  length within the breadth, each argument's written size within
  `sizeWithin arity height heaviest`, and the erased membership,
  `Proof/Requests.idr:758-765`), and the worklist recurses on that
  membership (`Finite.idr:122-170`, `Extends`, `extensionsEnd`, `Under`). Deleting
  the check deletes the evidence the recursion stands on, unless the
  derivation also concludes sizes and breadth. The size claim is today a
  comment (`sizeWithin`'s, `Proof/Requests.idr:650-666`).
- *Structural incompleteness*: eight of the eleven constructors have no
  rule in the model. `Field` and `Held` have height 0 and are "weighed by
  their arcs", `Choice` by its leaves, `Opaque` and `Computing` give
  `Stuck` weights (`Template.idr:445-456, 1178-1191`); each needs its own
  case in `Reduces` and in `Covers`.
- *Defect confirmed in source (D10, at the compiler's run time)*: the
  check builds proofs at run time and throws them away. `fitsWithin`
  answers `Holds (lteThrough (lteSo fits) ...)` (`Proof/Requests.idr:
  692-694, 704-709`), and `Decision`'s evidence is at quantity many
  (`Proof/Growth.idr:42-45`), so each argument of each request builds a
  unary `LTE` of its written size (`lteSo` recurses on it, `Proof/Growth.
  idr:53-56`; `lteThrough` "costs the first's size", `Proof/Requests.idr:
  677-681`), puts it in a `Pointwise` list, and `MkIn` erases it
  (`:775-777`). A literal weighs its magnitude plus one
  (`Proof/Requests.idr:198-201`), so the cost is linear in a static
  literal's value (*conjecture* on the size reached in practice). D46
  deletes it.
- *The link no Idris type states (owner question 1)*: the derivation is
  about the values the templates reduce to; a request's static argument
  is what the fork's normaliser returns for the call with the caller's
  values substituted (`closeNormalise`, then `Keys.write` and
  `closedHeight`, `Translate/Instances.idr:55-73`). That the reading of
  the second is a reduction of the reading of the first (normalization
  commutes with substitution for the probes the reading uses) is
  Idris's metatheory, about a normaliser outside every proof of ours
  (`Idris/Host.idr:103-113`, one `assert_total` over nine operations).
  The run-time witness is exactly this link's check.

**D48 (a data type is the family Idris checked, carried whole): holds on
the frontend's side, with corrections.** §2.11 says where each fact comes
from; the findings:
- *Read*: the frontend erases every index today. A data instance's key
  keeps only `Keyed` and `Formed` arguments; `Held` and `Index` arguments
  become `Erased EmptyFC Placeholder` (`Translate/Types.idr:711-712,
  960-965`), and no constructor's index equation is read into Core
  (`Term.idr:86-124`: `Con` holds fields only). D48 turns the erased
  argument into an index term and adds the equations.
- *Correction*: "whole" holds for indices and runtime fields, not for
  parameters and compile-time fields. The family the frontend can carry
  is the instance's: keyed parameters substituted (D48's own example has
  `x : i64`), dictionary fields fixed per program (`ArgKind.DictArg`, 17
  FB-19). Idris's family itself has neither.
- *Integration mismatch*: the frontend collapses a one-constructor,
  one-runtime-field type to its field (`Registered.Newtype`,
  `Translate/State.idr:350-352`; `Translate/Types.idr:998-1004`). That is
  a layout decision, and it drops the family (an indexed one-field type
  loses its equation). D48 puts layout in the dialect ("inline or in a
  cell is layout"); the collapse goes (§4 I8).
- *Correction*: function index parameters (`idr.func @map<n : nat>`) and
  call index arguments (`idr.call @map<k>`) have their source in TT's
  quantity-0 Pi binders and quantity-0 application arguments, which the
  frontend drops today ("A lambda's binder of quantity 0 is no parameter
  at runtime", `Translate/Terms.idr:443-452`). The one runtime signature
  needs a third kind of position (§2.3).
- *Fork bug on the path*: `paramPos` misses parameters hidden behind a
  definition (`a -@ LList a -@ LList a`), and the frontend patches it
  (`Translate/Types.idr:109-152`, `dataParams`; 17 FB-18). Which positions
  are indices is `arity` minus parameters, so D48 rests on the fix.

**D50 (the frontend imports the specification's closed sets): holds with
two corrections.**
- *Read*: the frontend raises the generated `Rule` (`Syntax/Idr.idr:
  172-175`) and nothing reads the generated `ruleCategory` (16 FC-78);
  `Profile.outsideLanguage` restates a scope by hand
  (`Frontend/Profile.idr:52-70`). One-source §6.2 names `Spec.Rules`,
  `Spec.Endings`, `Spec.Clocks`, grades and stages imported. *Correction*:
  the scope (forbidden wherever reached, or only where user code names
  it) must be a field of the spec's rule (16 G5), or `Profile` keeps its
  hand list; and the category must be true of every site (0003, "A
  refusal rule's category false of some of its sites"), which a rule
  indexed by its category makes checkable (§4 I7).
- *Integration mismatch*: P0 §6 deletes "the Idris printers of our types",
  while one-source §6.2 keeps `compiler/src/IdrisMLIR/{Dialect,Syntax,
  Encoding}/Idr.idr` generated, and `Syntax/Idr.idr` is the printers
  (`Syntax/Idr.idr:1-7`, 595 lines). The printers have no reader only once
  every `idr` type and attribute crosses as a native bytecode record (P0
  §5.6 "every `idr` type and attribute native in bytecode"; 14 TD2). The
  deletion lands with that encoding, in the spec's cutover B (L03 seam).

**AGENTS.md's two hosts: holds, with one standing violation in the area.**
- Everything designed here stays in plain Idris over base, indexed by
  parameters no field stores (`Template : Stage -> Nat -> Type`,
  `Signature arity`, `Vect arity`); `(n ** Vector n Int)` already compiles
  (`tests/arrays-key-dependent-pair/Main.idr:10-11`).
- *Defect confirmed in source*: a double crosses the handoff as host-printed
  decimal text (`MLIR/Text.idr:129-142`), so the two hosts agree by the
  coincidence of two printers (AGENTS.md's "never", 14 X01). It goes when
  doubles cross as their 64 bits.
- *Unverified behaviour*: base's `Data.IOArray` under idris-mlir is
  unmeasured (15 §8; 0011 §6: on Chez a table buys memory, not time).

### 1.2 The deletions the dispatch names

| deletion | verdict | evidence and condition |
| --- | --- | --- |
| `Translate/Forced.idr` | holds with a correction | Its re-patterning per instance (`clauses`, `split`, `afterCon`, `afterDelay`, `afterLit`, `covers`, `aliases`, `heldAt`; `Forced.idr:160-301`) exists because the TTC writes no clause index (`Core/TTC.idr:777`, `STerm 0`). The index alone does not delete the file: a leaf still reads an erased variable as the runtime variable its clause unified it with (`Forced.idr:3-18`), which needs the clause's patterns. 0003 keeps both ("Keep the index (and the builder's `List Pat` per clause in `PMDef`)"). With both, the alias map is a per-clause column of the definition table, computed once per definition, and `host.argToPat` (`Forced.idr:180`) leaves `Host`. Under AGENTS.md no run-time case tree is translated (D §3.7), so Q-FB1's option (a) is closed. |
| the five erasure readers | holds with a correction | `Closed.erasedArgs` (`Closed.idr:291`), `Forced.quantities` (`Forced.idr:153`), `Sites.quantitiesOf` (`Growth/Sites.idr:481`), `Terms.lastRuntime` (`Terms.idr:75`), `Types.conBinders` (`Types.idr:170`) all stand; `eraseArgs` has no reader (`grep -rn eraseArgs compiler/src`: none). *Correction*: `eraseArgs` is `findErased` on the type's normal form with no argument (`TTImp/Elab/Utils.idr:57-62`), so it covers the binders that form shows. A definition whose type computes further binders from a static argument (`(fmt : String) -> Format fmt`) has positions only an instance can read; today `Forced.quantities` takes a binder past the type as erased (`Forced.idr:155-160`). The one reader is per definition for the prefix and per instance for the rest (§2.3), an essential case. |
| the string-keyed maps | holds | `TS` holds 12 `SortedMap`s and 6 `SortedSet`s keyed by `DataId`/`FnId` strings, `ConId`, token lists, byte-vector addresses and module names (`Translate/State.idr:355-449`). Dense ids replace them (§2.3); a symbol stays a printed column written once, from the key alone (determinism, 15 §8). |
| the copied format parser | holds | It is `idris-mlir-tblgen`'s hand subset of upstream's declarative-format parser (14 T35, `tblgen:1822-2002`); D51 deletes every backend of `idris-mlir-tblgen` but the one reading upstream's records. |
| the Idris printers of our types | holds with a correction | Above (D50): only with native bytecode records for every `idr` type and attribute. |
| `idr.refusals` as a discardable attribute | holds | Written at `Emit.idr:104`, declared `IdrBase.td:68-70`, checked `foreign/idr/lib/IR/Verify/Attributes.cpp:21-28`, re-emitted `foreign/idr/lib/Driver/Run.cpp:231-237`. Its replacement is a refusal op (§4 I7). |
| Emit's `mostUses` | holds with a correction | `Emit/Bodies.idr:56` counts each linear binder's uses at every binder; `heldAs` (`:139-141`) demotes a quantity-1 binder used twice, parameters included (`Emit/Declarations.idr:45`). Deleting the count needs the translation to hand Emit a `Term` whose binders' quantities are proved of that `Term` (17 C5): where it renames, Idris's; where it aliases or substitutes, computed at that site. A parameter's quantity is its Pi binder's and is never demoted (§4 I4). |

### 1.3 P0 §5.6's claims

- *"The TTC keeps every fact a reader rebuilds (a `let`'s type, a match's
  scrutinee type, a leaf's clause index, why a term is erased, a block's
  typed parent, imports, a module's package)"*: holds with a correction.
  Add the builder's per-clause patterns (above) and each pragma use (17
  FB-12); a module's package and the main source path are session and
  driver facts, not TTC facts (17 FB-13, FB-14). §2.2 is the exact list.
- *"One runtime signature per definition from Idris's own `eraseArgs`"*:
  corrected above (prefix per definition, rest per instance) and by D48
  (index positions).
- *"The checks stay where they are (no budget, no `covering`), with their
  answers returned as values, `Template` indexed by its stage, one
  numbering"*: holds (16 §5, G1–G14; *read* §2.6 of 16 against HEAD).
- *"Lands with the `.td` change, in the same commit"*: holds for what the
  dialect changes (Core's grain, Emit, families, the grade, the world,
  refusals, the divergence fact). *Correction*: the TTC facts, the tables,
  the instance identity, the memo, D46, A0's reader side and R1/R2 touch
  no `.td` and land earlier, each in its own change (§2.9).

### 1.4 Coordinator decisions in the area

- **C6** (an op's spec names the base primitive it implements; the
  registry's rows generated): holds; it makes the registry table of §2.3
  partly generated, with the frontend still resolving every row once
  against the context (RS-1).
- **C7** (the spec in `compiler/spec/`, package `idris-mlir-spec`, base
  alone): holds; the frontend's package depends on it, and the spec never
  imports the fork, so the import rule holds.
- **C8** (a suspected bug inside what P0 replaces goes with its cause): the
  termination hole of §1.1 D13 is inside (D13, D22). Its cause goes with
  the divergence derivation; its reproducing test is written first (§5
  U9).

## 2. Boundaries

### 2.1 The end state, by piece

The frontend reads checked TT through the fork's TTC, once, into typed
tables; checks reachability and growth over them and returns the
admission as a value carrying its erased derivation; translates instances
keyed by a dense identity into Core; and Emit writes Core as an `idr`
module of the redesigned dialect, in bytecode, with no `idr` text. In
order of the pipeline:

| piece | end-state shape | replaces |
| --- | --- | --- |
| the TTC (fork, L17's encoder) | §2.2's facts in Idris's own types, `ttcVersion` bumped per fact, decode total and round-tripping | the dropped binder types, `scTy`, clause index, `WhyErased`, text parents |
| module table | `ModuleId` → (ident, origin, package, source file, printed name), built when the session adds each package | `TS.places`, `homeOf`, `elaboratedFile`, per-node `show ident` |
| definition, type-constructor, constructor tables | §2.3 | the five erasure readers, `conIdOf`'s normalisation, `siblings`, `projectionOf`, `rolesIn`, `hooksOf` by printed name |
| registry table | resolved once by `validate`, a `Hook` sum per definition, indexed by its arity (14 R15, R16; 15 RS-1) | `validate : … -> Maybe Refusal`, the 12-field `<|>` chain, seven arity `decEq`s |
| profile and reach | one walk over resolved reaches; rules from `Spec.Rules` with category and scope | `outsideLanguage`, the string-keyed `spelled`, the `words` import scan |
| growth admission | `Admitted` (§2.10): numbered positions, bounds, `Bounds`, erased `Describes` and `Feasible` | `checkGrowth : … -> Core Bool`, `TS.bounds`, `TS.sizes` |
| instance table | `InstanceId` minted once per `Link`; columns: definition, request, key, symbol, Core body, erased evidence | `fns`, `fnOrder`, `seen`, `named`, `symbols` |
| translation | over the tables; `Classified`, `Read`, `Keying`, `Coverage`, `Termination` sums; environment indexed by `IsVar` | 72 `internal`s mostly, every `fromMaybe`/`getAt` default |
| Core | `Let` with its `Binder`; `Case` with its family and index; `Effect`/`Call` indexed by arity; families (§2.11) | untyped `Let`/`Case`, `DataShape`'s three constructors, `Newtype` |
| Emit | writes the spec's builders; families; index parameters and arguments; the grade from the spec's frontend view; no world; refusal ops; counts nothing | `mostUses`, `heldAs`, `linear One WorldT`, `idr.refusals` |

Ops, attributes and types the frontend writes, as the design fixes them
(the shapes are L01, L03, L04, L05, L13's; the frontend's side is what
it puts in them): `idr.func` with its index and lifetime parameters,
its effect row's frontend-sourced part (the termination fact, §4 I1)
and `#idr.instance` as a typed identity; `idr.call` with index
arguments; `idr.match` a region per case (D19), with the family and
index of its scrutinee; `#idr.family`/`#idr.families`;
`!idr.data<#F[…]>`; `!idr.lin<T>` (quantity 1) and the bare type
(quantity many); a refusal op. No world, `world.new`, world operand
(D20), `!idr.box` (D48), `idr.refusals`, or `idr` text.

### 2.2 The exact list of facts the TTC keeps, each with its one reader

A fact is kept by the fork's encoder in Idris's own type (README "What a
TTC keeps", `compiler/idris/README.md:531-568`) and read by exactly one
frontend function, at the boundary, into one table column. "Kept" rows
are written today (`Core/TTC.idr:1314-1337` writes the full record only
for user names, which include case and with blocks, `Core/Name.idr:118-
123`); "to keep" rows are L17's encoder changes, each landing with the
reader's deletion.

| # | fact (Idris type) | in the TTC | its one reader → column | deletes in the same change |
| --- | --- | --- | --- | --- |
| K1 | a term node's location (`FC`) | kept (374e0e77) | `Errors.toLoc` → `(ModuleId, Span)` | `bestFC`, `isEmptyFC`, `siteAt`'s copy, 113 `EmptyFC` |
| K2 | binder quantities on `Pi`/`Lam`/`Let`/`PVar`/`PLet`/`PVTy` (`RigCount`) | kept (`TTC.idr:609-620`) | Pi: `signatureOf`; `Lam`/`Let`: the translation's binder step → `Binder.quantity` | `Resolve.use` at 40 sites; `coreBinder`'s quantity-0 error |
| K3 | `GlobalDef.type` | kept | `signatureOf`, `tyConFacts` (once each) | per-site normalisation of a signature (17 FB-32) |
| K4 | `definition` (`PMDef args treeCT pats`, `DCon tag arity`, `TCon arity parampos datacons`, `ExternDef`, `ForeignDef`, `Builtin`) | kept (`treeRT` not) | definition table's kind sum | `TS-10`'s `_ => internal` |
| K5 | `eraseArgs` (`NatSet`) | kept, unread (`TTC.idr:1326`) | `signatureOf` (prefix) | the five readers |
| K6 | `multiplicity` | kept | definition table | `Profile.proofOnly`'s own lookup |
| K7 | `totality` (coverage; termination of checked code; a type's positivity) | kept (`TTC.idr:1332`) | coverage → `Coverage`; the rest → `Termination` (§4 I1) | `complete : Bool`; `tot = fromMaybe False` (`Programs.idr:78`) |
| K8 | `sizeChange` (`List SCCall`) | kept | `Recursion`'s component search (one Tarjan: the fork's exported `insideComponents`, 17 C6) | the frontend's second Tarjan |
| K9 | `refersToRuntime` | kept, unread | definition table's reach column | `Profile.refsOf`'s and `Keys.treeRefs`' walks (17 FB-16) |
| K10 | `location`, `visibility`, `isEscapeHatch`, `flags` (`ConType` `ZERO`/`SUCC`) | kept | definition table; natness in `tyConFacts` | `Crash` re-deriving trust (0003 "smaller") |
| K11 | `TCon parampos` | kept, wrong behind `-@` | `tyConFacts` (parameters, hence indices) | `dataParams`' second reading, after the fork's fix (17 FB-18) |
| T1 | a `Let`'s/`PLet`'s/`PVTy`'s type (`Term`) | to keep (`TTC.idr:612, 618, 620`) | the translation's let step → `Term.Let`'s `Binder` | `valueType` (`Terms.idr:261`), the `ValueType` refusal, Emit's synthesis |
| T2 | a `Case`'s `scTy` (`Term`) | to keep (`TTC.idr:775, 831`) | `Cases.tree` → `Term.Case`'s family and index | `instanceOf` (`Cases.idr:247`), `siblings` (`:155`), `coversAll`'s re-derivation, `VarInfo.Runtime`'s `Maybe`s |
| T3 | a leaf's clause index (`STerm Int`) | to keep (`TTC.idr:777, 832`) | `Cases.tree` → the leaf's clause | `covers`, `split`, `afterCon/Delay/Lit` |
| T4 | each clause's builder patterns (`List Pat`, 0003) | to keep | definition table → per-clause alias map | `Forced.clauses`, `aliases`, `heldAt`; `host.argToPat` |
| T5 | why a term is erased (`WhyErased`) | to keep, after the frontend's run-time probe moves off `Erased _ Impossible` (`TTC.idr:583, 694`) | `Closed.runtimeDependent` (no longer colliding) | the overloaded marker |
| T6 | a block's parent (`Name`, kind, ordinal) | to keep (`Core/Name.idr:45-46` holds text) | definition table's parent column | `outermost`, `rootOf`'s climb, `keyOrigin`'s context search |
| T7 | each import's `FC` and `ModuleIdent` | to keep | `Profile` imports check | `Profile.imports`' `words` scan, `Program.idr:210-215`'s split |
| T8 | each pragma use (kind, `FC`) | to keep (17 FB-12) | `Profile` pragma check | the re-lex of every module; spelled escape hatches stay lexical |
| T9 | the `Delay` the elaborator inserted for a `Lazy` expected type | to keep (§4 I6) | the translation's let step | `delayedLets`' blanket move |
| — | `treeRT` | not kept; `mkRunTime` deleted (17 FB-38, L17) | none: AGENTS.md forbids translating run-time case trees | `compileRunTime`'s per-definition work |
| — | a non-user name's type and `eraseArgs` (`MN`, `PV`) | measure first (17 FB-08) | a solved metavariable's reader, if any meets it | `Erased` read back for its type |
| — | `safeErase`, `specArgs`, `inferrable`, `localVars`, `invertible`, `noCycles`, `linearChecked`, `newtypeArg`, `detpos` | kept, no reader | none; `newtypeArg` is not the fact the frontend needs (17 FB-19) | — |

Session and driver facts, not TTC facts: a loaded module's package
(recorded at `addPkgDir`, 17 FB-13) → module table; the main source path
(the driver's `source`, 17 FB-14) → module table.

### 2.3 The typed tables, read once

Two kinds of id (0011 D1): a frozen table's id is a `Fin` of its extent,
read with no guard; a growing table's is an opaque typed identity read by
lookup until frozen. All plain Idris over base (`Data.IOArray`,
`Data.SortedMap`), both hosts.

```idris
-- Per definition, by context index (`DefId`, growing while reading).
data DefKind = Constructor ConId | TypeConstructor TyConId | Primitive PrimId
             | Pattern | Foreign | Extern | Hole
data Position = Absent                     -- erased, and no index of the IR
              | Index Sort                 -- erased, kept as a compile-time parameter (D48)
              | Runtime Quantity ClosedTerm -- at Idris's quantity, its type normalised once
record Signature (arity : Nat) where       -- arity a parameter, not a field
  constructor MkSignature
  positions : Vect arity Position          -- from eraseArgs and the Pi quantities (K2, K5)
  rest : Telescope                         -- Closed, or ComputedBy the static positions it waits on
data Termination = Terminates ComponentId | MayDiverge (List1 Name)
data Coverage = Covering | Partial
record DefFacts where
  kind : DefKind; signature : (n ** Signature n); coverage : Coverage
  termination : Termination; origin : Origin; hook : Hooked; parent : BlockParent
  reaches : Reaches; clauses : List ClauseAliases
-- Per type constructor (`TyConId`): parameters after the fork's fix,
-- roles : Vect arity Role, kind : TyConKind (NatLike | Word | Ordered o _ |
-- ValueArray | Data), natness, constructors in tag order, the family's
-- index sorts, interface membership.
-- Per constructor (`ConId = (TyConId, Fin k)`): fields : Vect f (Quantity,
-- ClosedTerm), index variables : Vect v Sort, equations : one per family
-- index, in D48's index language.
```

- `Position`'s three cases are essential: an erased proof is `Absent`; an
  erased `n` in `Vect n a` is an `Index`; a value is `Runtime`. A caller
  cannot pass a `RigCount` where a runtime quantity is due (17 FB-27).
- `Telescope.ComputedBy` is the essential case of §1.2: an instance whose
  static arguments are known reads its remaining positions once, from its
  normalised type, into its own `Signature`, the instance table's column.
- The instance table (`InstanceId`, growing during translation, frozen
  before Emit) keys by `Link` once; its columns are the definition, the
  request, the key, the symbol (printed once from the key alone), the
  `TFn`, and the erased evidence of §2.10.
- The family table (`FamilyId`) keys by (type constructor, keyed
  parameters); it replaces the data instance table and `Registered`.

### 2.4 Constructor provenance

| fact | constructed by | who alone may |
| --- | --- | --- |
| a binder's quantity, erasure, totality, positivity, size-change graphs | Idris's elaborator (the fork) | the fork; the frontend reads, never decides |
| a TTC fact (§2.2) | the fork's encoder, round-tripping | L17's encoder; one frontend reader each |
| `Signature` (prefix) | `signatureOf`, from K2, K3, K5 | `signatureOf` once per definition |
| `Signature` (an instance's rest) | the instance's reading of its normalised type | the instance table, once per instance |
| `Position.Index` | `signatureOf`: an erased binder whose variable occurs in an index position of a runtime binder's or the result's type | `signatureOf` |
| a family (index sorts, equations, fields) | the constructor table, from `TCon parampos` (fixed) and each `DCon`'s type | `tyConFacts` / the constructor table |
| `Termination` | `Recursion`, per Idris component, when the instance is requested | `Recursion` alone |
| `Coverage` | K7 | the definition table |
| `Admitted` and its erased `Describes`, `Feasible` | `Graph.build` and `Check.check` | the growth phase alone |
| a request's erased `InV` and `InUniverse` | the translation at each call, from the caller's evidence and the site's (§2.10) | the request step alone |
| `InstanceId` | the instance table, on a new `Link` | the instance table alone |
| `!idr.lin<T>` on a binder | Emit, from `Binder.quantity = One` | Emit, through the spec's frontend view of the grade, which admits nothing else |
| a refusal | `reject` with a `Spec.Rules` rule, at its site | the frontend's checks and translation |
| the symbol | the key's print (`Term.keyText`, `Term.idr:581-586`) | the key alone, never an id (stage 2 = stage 3) |

### 2.5 Consumers, error and cleanup paths

- **Readers of the tables**: Profile, Growth, Translate, Emit; nothing on
  the C++ side reads a frontend table: the handoff is the module (17 §6
  Q-O3).
- **Refusals**: `reject` raises a rule at a site; `noting` records it and
  restores the state from before the instance (`keepFound after before`,
  `Frontend/Finite.idr:360-370`; 2a66fbcb), so every independent
  rejection is reported in one run (essential, 16 FC-76). The refusal
  rides beside Idris's `Error` today (`TS.inFlight`, `Translate/State.
  idr:376-381`) and is deduplicated by printed text (`Errors.idr:70-92`);
  the translation's own error type carries it instead (15 ST-7; the fork
  may not import `IdrisMLIR.*`, D §5 D7 note). The refused module holds
  refusal ops (§4 I7); the driver reports them.
- **Internal errors that stay, each essential at the fork's boundary**: a
  case alternative binding another number of arguments than its
  constructor (16 FC-16), a constructor name the context lacks (FC-42), a
  negative metavariable index (FC-57), a `Meta` index resolved by name (17
  FB-09). Every other `internal` of today guards a state §2.3's types make
  unrepresentable.
- **Cleanup**: `TState` dies with the run; the module is streamed per
  function (`Program.idr:62-81`). The Core dump (79 MB on the self compile,
  15 TM-9) is streamed per function or deleted with its readers moved
  (15 NQ-4, L19 seam).

### 2.6 What it deletes

By file, each in the change that makes it dead (15 §7, 16 §7, 17 §7 for
the full symbol lists; the additions are this lane's):
- `Frontend/Translate/Forced.idr` whole (T3, T4).
- `Closed.erasedArgs`, `Forced.quantities`, `Sites.quantitiesOf`,
  `Terms.lastRuntime`, `Types.conBinders`' quantity reading (K5).
- `Terms.valueType`, `applyOver`'s `ValueType` refusal (T1); `Cases.
  instanceOf`, `siblings` (T2); `outermost`, `rootOf`'s climb,
  `keyOrigin`'s search (T6); `Profile.imports` (T7); `Resolve.homeOf`,
  `elaboratedFile`.
- `TS.fns`, `seen`, `symbols`, `named`'s value, `instances`, `Registered`,
  `bounds`, `sizes`, `loops`, `inFlight`, `spelled`'s `String` key, `places`.
- `Finite.heightWithin`, `sizedWithin`, `unsound`; `Types.boundsHold`;
  `Proof/Requests.within`, `fitsWithin`, `climb`, `lteThrough`; the model
  `Proof/Bound.Term` (restated over the code's `Template`, §2.10).
- `Emit/Bodies.mostUses` and helpers, `heldAs`, `holdFor`;
  `Emit/Monad.linear`'s world branch; `Emit.refused`'s discardable
  attribute; `Emit/Closures.functionOp`'s blanket `total' = True`.
- `Facts.terminating : Bool`; `Types.quantityText`; `Types.signed`.
- `Translate/Types.idr:998-1004`'s newtype collapse.
- `Closed.delayedLets`' blanket move (T9).
- `MLIR/Text.floatLiteral`'s decimal path.
- With the dialect's cutover: `Syntax/Idr.idr`'s printers and enum copies
  (D50, native records), `Term.DataShape`, `Emit/Index.body`'s table.

### 2.7 Distinctions that must remain

- The four roles of a type constructor's argument (`Keyed`, `Formed`,
  `Held`, `Index`: what keys the instance, what the growth check watches;
  `Translate/State.idr:284-301`), now as `Vect arity Role`.
- Trust by where a definition comes from against who reaches it (16
  FC-86).
- `Absent` against `Index` against `Runtime` (§2.3).
- A crash (a partial definition's missing case) against unreachable
  (Idris proved it) against exit (D14): `Crash`, `Unreachable`, the exit
  terminator.
- Termination proved per Idris component against may-diverge (§4 I1).
- `idr.lin.enter` and `idr.lin.use`: QTT's subsumption and a linear
  value's one use, two cases the problem has (17 C4).
- A static argument's written form (the identity) against its print (for
  readers); the symbol is the print, the identity the `Link`.

### 2.8 Seams

| with | the declaration both write against | state |
| --- | --- | --- |
| L17 (fork) | §2.2's encoder rows; `eraseArgs` complete on the normal form; `paramPos` on normal forms; `ZeroOneOmega` `public export`; the block parent typed; `mkRunTime` deleted; A0's arena; O1 and O5 | fixed by this table; each row lands with its reader's deletion |
| L03 (one source) | `Spec.Rules` (with category and scope), `Spec.Endings`, `Spec.Clocks`, grades, stages imported; builders printed as `Op n` over `Vect n Value`; native records for every `idr` type and attribute | fixed for the closed sets; the printers' deletion unfixed (§1.1 D50) |
| L04 (families) | `#idr.family` as D48 states it; the frontend supplies index sorts, per-constructor index variables, equations, fields and the in-place kind | unfixed: whether a field's quantity is its type (`!idr.lin<T>`) or a field of the family (recommended: the type, one fact, §4 I8); how an opaque index term is identified; whether a runtime field may occur in an index term |
| L05 (grades, lifetimes) | the spec's frontend view of the grade: quantity 1 or the bare type, no permission or lifetime | fixed by D40 and 17 C4; the view's shape is L03's and L05's |
| L02 (rows) | the divergence atom's source: the frontend's `Termination` with its component, read by the derivation over the C++ SCCs | unfixed: proposed in §4 I1 |
| L08 (in-place promise) | D24's rule reads a parameter's `!idr.lin<T>` as the frontend wrote it; the frontend never demotes a parameter | fixed by D24 and §4 I4 |
| L14 (program graph) | the frontend's Idris components are a different graph from the C++ call graph; only their ids cross, on `idr.func` | proposed in §4 I1 |
| L18 (specialization) | `#idr.instance` a typed identity, not argument texts (0003 B7) | fixed in substance; the attribute's shape is L18's |
| L19 (tests) | the refusal tests and their `near/`; `tests/growth-check` (542,896 graphs) as the oracle of the check; `quantities-kept` keyed by binder; the Core dump's readers | fixed by 16 §8, 17 FB-31 |
| L20 (QTT end to end) | §3 | — |

### 2.9 The absorbed plans in P0's sequence

P0's stages are §7's (S0 to S7). The frontend's work is a track beside
them, F0 to F9, of which only F8 and F9 change with the dialect. Each
item's gate is P0's (it builds, the suites and the invariant set pass,
it deletes what it replaces), plus its own measured bar where the plan
it comes from has one (owner question 2 decides the baseline).

| step | P0 stage | content | needs |
| --- | --- | --- | --- |
| F0 | S0 | the baseline record (owner question 2); the fork's low-risk facts T7, T8, the package and main path (session and driver); the failing test of §4 I1 | — |
| F1 | S3–S4 | the TTC's term facts, one per change: T1 (ends the refusal of valid programs), T2, T3 with T4, T5 after the probe moves, T6, T9 | L17's encoder rows |
| F2 | S3–S4 | the tables of §2.3 with `Signature`; the registry resolved once; the module table and interned locations (15 D-5); Profile over resolved reaches (16 G14); the growth check's representation changes that need no proof (16 G2–G8, G11–G13) | F1's T2, T3 for the constructor table's readers |
| F3 | S4 | one instance identity (15 D-1), the admission as a value and one numbering (16 G1, G4) in one change, since data registration reads the bounds (16 §8) | F2 |
| F4 | S4 | the classification memo (15 D-3), its key the full static input, gated by a run comparing memoised and recomputed answers | F3 |
| F5 | S4 | linearity by construction; Emit counts nothing (§4 I4) | F2 |
| F6 | S4 | 0010's A0 reader side: the frontend reads TT from the fork's arena; XXH3 moved from `Ids.idr` to a `libs/` package both import | L17's arena |
| F7 | S4–S6 | D46's derivation (§2.10); the witness and `within` deleted | F3; owner question 1 |
| F8 | S5 | with the dialect: D50's imports; D48's families (§2.11); 0011's O2 as the Emit of the new dialect (Core, datatypes and ops tables; one Emit rewrite, not two); D20's world dropped at Emit; the grade view; refusal ops; the divergence fact (§4 I1) with L02's rows | F2, F6; L03's cutover A |
| F9 | S6–S7 | 0015's R1 and R2 in `libs/mlir-relational` (plain Idris, both hosts); 0011's O3 (Translate as semi-naive over the instance table, its termination in R2's type, carrying F7's evidence per tuple); O8 (laws on every compile); O1 and O5 (L17); O6 and O7 per owner question 3 | F7, F8 |

0011's stages: O0 is F0 (re-based); O1 and O5 are L17's, after F6; O2 is
F8; O3 and O8 are F9; O4 is A0 (F6, moved there by 0011 itself); O6 and
O7 wait on owner question 3. 0010's A0 is F6 with L17. 0015's R1 and R2
are F9's first half.

0003's 62 items, each placed. The frontend's section (20 items) and the
Idris-side leftovers are this lane's; the rest name the ruling that
absorbs them and the lane that owns them.

| 0003 item | lands in | owner |
| --- | --- | --- |
| rebuilt terms' locations; locations defaulted though known; A5 a library module at `UnknownLoc` | F2 (module table, located rebuilds; A5 at F8's location writer) | L16 |
| C1 a `let`'s type; C2 `scTy`; a leaf's clause number; B1 a block's parent; B3 imports; the `Impossible` marker | F1 (T1–T7) | L16 reader, L17 encoder |
| the main source path; B6 package names | F0 | L16 (+L17 for `addPkgDir`) |
| erased arguments, five readers; C3 a constructor's type constructor three ways | F2 (`Signature`, the constructor table) | L16 |
| C4 a request classified twice | F3 (the request carries the classification) | L16 |
| C5 what an implementation closes over, twice | F2 (one `holed`) | L16 |
| B5 the registry resolved and thrown away; B4 spelled pragmas by root string | F2 | L16 |
| B7 an instance's identity printed for C++ | F3 (typed identity), F8 (the attribute) | L16, L18 |
| smaller: `tot = fromMaybe False`; `Recursion` re-resolves; `Crash` re-derives trust; errors merged by text; non-user names' default facts | F2–F3 (`Termination`, origin column, the translation's error type); FB-08 measured | L16 (+L17) |
| D1 Emit's use counts | F5 | L16 |
| a token without its cell | S5: the token names its constructor; `!idr.box` goes (D48) | L07, L04 |
| static searched along the chain | D39, D40 | L05 |
| a `dup` of atoms-only data exempted | D39 (static graded from what a value holds) | L05, L07 |
| exclusivity solved twice | §6 counting | L08 |
| `quantities-kept` by location | keyed by binder | L19 |
| a pattern variable's location; output rewrites' location; what an enclosing match says, three ways; two upward walks; `knownNonEmpty` | S6 canonicalization (§5.3 "one view of a match per visit") | L13 |
| a raise node's consumer at `UnknownLoc`; deduplicate fuses one location; a consumer cloned per request; the optimizer rescans | S6 | L18 |
| tail loops' and frames' locations; `closureLabels` | S6 | L10 |
| data types carry no location | F8: the family carries its declaration's location from K10 | L16, L04 |
| analyses dropped and rebuilt; `givesBack` solved twice; ranges discarded | S4 (program graph, analysis manager) | L14 (L18 for ranges' seed) |
| one target machine recipe; the user address width; the small word decoded by hand | the target's entry; runtime | L11 (L15) |
| function facts not lowered | D22's row to LLVM | L02 |
| no line tables | the lowering | unassigned in the swarm's table: named here as an open seam |
| `idr.crash_str` drops its site; the ending lost | D38, D37 | L11, L19 |
| no stack probes | D32, C5 | L10, L11 |
| `make compile OUT=`; the upstream runner; held twice or re-parsed in the harness | S2 | L19 |
| a data body's kind beside roles | D48 deletes the table | L04 |
| the owned stage reads `memref` by name | counting's redesign | L07 |
| `feeds()` a ladder | S6 | L13 |
| MoveOut's second classifier; resources read as bits by hand; the crash-site count against the crash effect | D9, §5.1 | L01, L02 (L19) |
| `idris-mlir-tblgen` matches by name | D16, D51 | L03 |
| types that could carry the fact | split: `Exclusivity::targets` L08; `Reuses::sites`, PassThroughMemory L07; Identities, statistics by name L18; `narrow::Copy` L14; `holdsLabels`, Placement's `casesOf` L13 | as named |
| exclusivity is no analysis | S4 | L08, L14 |
| a refusal rule's category false of some sites | F8 (D50, §4 I7) | L16, L03 |
| Idris side leftovers: an Emit statement with no results; the environment by position; `TS.loops` and `Template.Computing`; `proofOnly`'s second lookup | F8 (statements `NonEmpty`), F2 (`IsVar`, G2, G13, G14) | L16 |
| `SpecKeyAttr`'s `origin` | S6 | L18 |

### 2.10 D46: Theorem 1 over the code's `Template`, built as the frontend works

Selected design (the one link of owner question 1 aside):

1. **Placement under the import rule.** `data Template` and its measures
   move to `Proof/` (they use `Address` and naturals, nothing of the
   fork); the readers of TT into templates stay in `Frontend/Growth/`.
   Theorem 1 is then stated over the type the readers produce, and no
   `Proof.*` module imports the fork (AGENTS.md: only
   `IdrisMLIR.Frontend.*` may).
2. **The template indexed by stage and scope.** `Template : Stage -> Nat
   -> Type`, `Stage = Read | AtNode | Admitted` (16 G2 plus the admitted
   view), and `Var : Fin m -> Template s m` with the site's binder table
   `Vect m (Binder size)` (the model's `Site`, `Proof/Bound.idr:155-160`).
   Today's `Var Nat Nat` names a parameter by number and a depth, so a
   variable no writer binds is representable (16 FC-45's internal error);
   `Fin m` makes it not. `Computing` exists only below `Admitted`: every
   admitted graph has no `Stuck` arc (both causes refuse,
   `Check.idr:47-56`), so an admitted site holds no computing family and
   no `Opaque` with a variable. `Head (Maybe Address)` splits into
   `Named` and `Former` (16 FC-13).
3. **A rule per constructor.** `Reduces` gains `AtToken` (height 1, its
   weight for `heaviest`); `Chosen : Elem leaf leaves -> Reduces … leaf w
   -> Reduces … (Choice t leaves) w` (`height (Choice _ ts) = tallest ts`,
   so `reducesBelow` holds by `heightsBelow`); `AtField` and `AtHeld`,
   whose value is in `V` at the implementation's field position (the
   arcs `Graph`'s `fieldValue` draws make `Covers` carry them); `Applied`
   is the model's `Landed`/`Raised`; `Formal` only in a family's body
   (the model's `Nowhere`); a closed `Opaque` a constant leaf. `Covers`
   gains the field and choice arcs.
4. **Sizes and breadth, not only heights.** A second lemma: the key is
   written from the value (one representation of a static argument, §4
   I2), and `writtenWithin : height w ≤ h -> arityOf w ≤ a -> heaviestOf w
   ≤ k -> (write w).size ≤ sizeWithin a h k` turns `sizeWithin`'s comment
   into a proof; the link's length is the definition's arity from its
   `Signature`, below the breadth because the definition is a node of the
   graph. Together they build `InUniverse` at quantity 0, which is what
   `Under` and `extensionsEnd` consume today.
5. **Built as the frontend works, all at quantity 0.**
   - `Graph.build` returns `(g ** ss ** (0 _ : Describes g ss))`, each
     site's `Covers` made where its arcs are drawn (`raw`, from
     `weightsAt`, whose occurrences are the proof's `Occurs`).
   - `Check.check` returns `Bounded pot (0 _ : Feasible g pot)` (16 G9,
     G10). `Admitted` holds both.
   - Every request carries `0 inV` for each static position and `0 inside
     : InUniverse b link`; the root's are trivial (`main` has no static
     argument). At a call, the translation finds its site by coordinate
     (the one reading of the definition numbers its call sites, so `Elem
     s ss` is the site table's index), builds `Matches` from the caller's
     `inV` and the depths its case tree matched (the environment holds
     each pattern variable's `Sub d v u`), and `Reduced s el ms r` gives
     the callee's `inV`; `bounded` and `writtenWithin` give `inside`.
   - Nothing of it runs: every proof is erased; the run-time cost is the
     site lookup the translation already makes.
6. **Deleted**: `heightWithin`, `sizedWithin`, `unsound`, `boundsHold`,
   `within`, `fitsWithin`, `climb`, `lteThrough`, `TS.bounds`, the model
   `Term`; the worklist's `Under` takes its evidence from the request.
7. **What remains unproved**: that the request's value (what the host's
   normaliser returns) is the `w` the derivation names. Owner question 1.

### 2.11 Emitting D48's families: where each fact comes from

| D48 fact | source in TT (and the TTC row) | the frontend's reader |
| --- | --- | --- |
| the family's identity | the type constructor and its keyed arguments (`Keyed`, `Formed` roles) | the family table |
| its erased indices and their sorts | the type constructor's positions that are not parameters (K4 `TCon arity`, K11 `parampos` fixed), each position's type | `tyConFacts` |
| a constructor's index variables | the constructor's quantity-0 Pi binders whose variables occur in the result type's index arguments (K3 the `DCon`'s type, read under markers as `conBinders` reads it today) | the constructor table |
| its index equation, one per family index | the result type's argument at each index position, in D48's index language (constants, variables, successor, constructor applications, `Nat` as a number; anything else an opaque term) | the constructor table |
| its fields and their quantities | the runtime Pi binders (quantity 1 or many, K2); quantity 0 is no field | the constructor table; quantity 1 is `!idr.lin<T>` in the field's type (§4 I8) |
| recursion as `self[...]`; a mutual group by position | a field whose type is the family itself, or a member of the group | the family table (the reentry fact `TS.reentered` today) |
| the in-place kind | the registry's `InPlaceType`, `ListType` (K9 of the registry table) | the family table |
| a function's index parameters | the function's `Position.Index` binders | `signatureOf` |
| a call's index arguments | the application's quantity-0 arguments at the callee's `Index` positions, as index terms | the call step |
| a match's refined index | `scTy` (T2) and the alternative's constructor equation | `Cases.tree` |
| the declaration's location | the type constructor's `location` (K10) | the family table |

## 3. QTT

**Where each quantity enters, is kept, read or lost, from TT to the
module.**

| | enters | kept as | read by | lost or paid today |
| --- | --- | --- | --- | --- |
| 0 on a binder | `RigCount` on `Pi`/`Lam`/`Let`/`PVar` (K2); `eraseArgs` (K5) | absence: no Core parameter, field or argument (`Types.idr:123-130`) | five readers, each its own default | erasure re-derived five ways; positions behind a computed type defaulted to erased (`Forced.idr:155-160`) |
| 0 on an index | `Vect n a`'s `n`, `TCon`'s non-parameter positions | nothing: keys erase it (`Types.idr:711-712, 960-965`) | — | every index and equation lost; D48 restores them as compile-time parameters, never values |
| 0 on a proof | `(0 prf : LTE n m)` | absence | — | correct |
| 1 | `Rig1` on a binder or field | `Binder.quantity = One` → `!idr.lin<T>` (`Emit/Index.idr:58-59`) | Emit's `coerce` (`lin.enter`, `lin.use`); D24's rule; D26's ownership read off a caller's linear binder | demoted by Emit's count where the translated body uses it twice (`Emit/Bodies.idr:139-141`, parameters at `Emit/Declarations.idr:45`): the module's quantity is then not Idris's |
| ω | `RigW` | the bare type | — | — |
| the world's 1 | `(1 _ : %World)` | a branch (`Emit/Monad.idr:81`) | — | goes with the world (D20) |
| a definition's 0 | `multiplicity` (K6) | never translated | `Profile.proofOnly` | looked up twice |

**Facts a quantity proves that the design still pays for (D10).**
- *At the compiler's run time*: Emit's quadratic use count re-derives
  linearity Idris proved (`Emit/Bodies.idr:56`; 0003 D1); 40 sites
  re-read a binder's quantity from a type they normalised again; the
  growth check builds a unary `LTE` per request argument and throws it
  away (§1.1 D46); `Feasible`'s `All` list is built at quantity many and
  discarded (16 FC-68); the frontend's own proofs are erased everywhere
  else (`Proof/Generations.idr`, `Finite.idr:80-176`).
- *At a program's run time*: none originates here. Whether a word's
  quantity 1 (`!idr.lin<i64>`, 128 uses in 13 test files, 17 §3.3) stays
  is DD-Q1's, settled in substance by AGENTS.md ("Quantity 1 is a type"):
  the frontend writes it.

**Using quantities harder in this area.**
- *Index variables at quantity 0 become the IR's compile-time parameters*
  (D48): `Position.Index` makes "erased" and "an index the verifier
  refines by" two cases, so an erased index is never a value and never
  lost.
- *Quantity 1 on a parameter is never demoted*: a parameter's quantity is
  its Pi binder's; D24 reads it to decide the in-place promise, and D26
  reads a caller's linear binder to pass an argument owned. A demotion
  Emit makes changes what D24 binds and so what is refused (§4 I4); after
  F5 none can be made.
- *The frontend's own code at quantity 0*: certificates erased (16 G9),
  `Decision`'s evidence split by who reads it (§4 I10), the growth
  derivation erased (§2.10), membership evidence of the instance table at
  quantity 0.
- *Linear tables in the frontend*: 0011 asks for tables "linear where that
  helps"; an `IOArray` updated in place means the same under both hosts,
  and a linear table makes a stale read of an updated table unwritable.
  *Conjecture* on the gain; measured at F2.

**Representations that make a misuse unwritable.**
- `Position = Absent | Index Sort | Runtime Quantity ClosedTerm`: no
  quantity 0 where a runtime quantity is due (17 FB-27).
- The spec's frontend view of the grade: Emit can build `!idr.lin<T>` or
  the bare type and nothing else (17 C4, FB-30).
- `Template s m` with `Var : Fin m`: no variable outside its site.
- `Request` carrying `0 inside : InUniverse b link`: no request outside
  the universe can be queued.
- A Core `Term` binder carrying its quantity as constructed: a binder of
  quantity 1 used twice cannot reach Emit (§4 I4).

## 4. Improvements

**I1. Divergence follows Idris's components, not each function's own
loops.** *Coordinator.*
- *Evidence*: §1.1 D13; `Facts.idr:13-17`, `Emit/Closures.idr:89-93`,
  `foreign/idr/lib/IR/Func/Func.cpp:189-201`, `Translate/Recursion.idr:
  112-135`.
- *Counterexample* (*conjecture* until run):
  ```idris
  data D = MkD (D -> Nat)          -- not strictly positive; accepted
  selfapp : D -> Nat               -- under the default `covering`
  selfapp (MkD f) = f (MkD f)      -- no call of itself: "terminates"
  main : IO ()
  main = do let x = selfapp (MkD selfapp)
            putStrLn "unreachable"
  ```
  Eager evaluation loops. After defunctionalization `selfapp` calls
  itself through the dispatch; every member reads `total`, the SCC reads
  no divergence, and deleting the unused call prints the line. The same
  holds for `Show T` and `Show (Wrap T)` whose methods call each other
  through `show` (Idris's graph records a call to the projection).
- *Root cause*: a fact about Idris's call graph is read as a fact about
  the C++ call graph, which specialization and defunctionalization make
  different.
- *Correction*: `Termination = Terminates ComponentId | MayDiverge (List1
  Name)`, decided per Idris component when the instance is requested; Emit
  writes the component's identity on `idr.func` (a lifted lambda takes its
  owner's); the divergence derivation (L02) marks a C++ SCC non-diverging
  only when every member `Terminates` in one and the same Idris component,
  since a cycle inside one component's instances maps onto a cycle of
  that component's calls, which size-change proved decreasing.
- *Deletes*: `Facts.terminating : Bool`, `TS.loops`, `fromMaybe False`,
  the blanket `total' = True` on lifted functions, `total` as a name for
  termination.
- *Discriminated by*: the program above as a test (expected: it does not
  print), and its `near/` with a strictly positive type that prints.
  Precision cost to measure: functions losing `Terminates` on the
  self-compile.

**I2. One representation of a static argument.** *Coordinator* (needed
by D46 whichever answer owner question 1 gets).
- *Evidence*: a static argument is written for the key (`Keys.write`),
  printed for the symbol (`render`, a second traversal that must agree,
  15 KY-6), read again for its height (`closedHeight`, cached by
  `(Static, Written Form)` in `TS.readings`, `State.idr:435-439`), and
  taken apart a third way for dictionaries (16 FC-15). `Template`'s
  `Leaf h` and `Token n` keep only a height and a weight.
- *Counterexample*: a key and a height read by two traversals that
  disagree on a literal (KY-4 writes a string one token per character)
  give a link whose size the check bounds differently from the key the
  worklist keeps: today an internal error, after D46 an unchecked one.
- *Root cause*: one fact (the closed static value) held as three trees.
- *Correction*: a static value is a `Template Admitted 0` whose leaves
  keep their closed content (the literal, the primitive type); the key's
  `Written`, the print, the height, the arity and the heaviest token are
  each a function of it, and its TT is generated from it where the
  translation substitutes it.
- *Deletes*: `render` as a traversal, `TS.readings`, `closedHeight` on
  requests, the second dictionary take-apart.
- *Discriminated by*: `writtenWithin` (§2.10) type-checks only when the
  key is a function of the value.

**I3. Erasure decided once, with three kinds of position.**
*Coordinator.*
- *Evidence*: §1.2's second row; D48's index parameters.
- *Counterexample*: `printf : (fmt : String) -> Format fmt` at `fmt =
  "%d"` has a runtime `Int` the definition's normal form does not show;
  `Forced.quantities` takes a binder past the type as erased, so a reader
  that met the instance's binder first would disagree with one that met
  the definition's (17 FB-15's "erased to one, runtime to another").
- *Root cause*: a per-definition fact used for positions only an instance
  can see; and erased indices folded into "absent".
- *Correction*: §2.3's `Signature` with `Position` and `Telescope`, the
  prefix from `eraseArgs` once per definition, the rest once per instance;
  if a measurement shows `findErased`'s `nf` misses a binder
  `normaliseTypes` finds, the fork's `findErased` is fixed (17 FB-15).
- *Deletes*: the five readers, the past-the-type default, 40 `use` sites
  where only the position's kind was wanted.
- *Discriminated by*: a test whose static argument opens a runtime binder
  (`printf`'s shape), and the M7 measurement (D §7) of `eraseArgs`
  against today's readers on the corpus.

**I4. Linearity carried by construction; Emit counts nothing.**
*Coordinator* (the dispatch's QTT focus fixes the direction; this is the
representation).
- *Evidence*: `Emit/Bodies.idr:56, 139-146`; `Emit/Declarations.idr:45`;
  D24 reads "a quantity-1 parameter of such a type"; FB-31: nothing checks
  that emitted quantities are Idris's.
- *Counterexample* (*conjecture* until run): an `LList` parameter of
  quantity 1 that the translation aliases (`aliased`,
  `Translate/Terms.idr:553-555`) to a variable used elsewhere reaches Emit
  used twice; `heldAs` makes it plain; D24's rule no longer binds it, so a
  call the exclusivity analysis cannot prove is accepted silently, without
  the promise, where Idris's program says linear.
- *Root cause*: the translation copies Idris's quantity onto binders of a
  term it rewrote, and Emit repairs by counting.
- *Correction*: a parameter's quantity is its Pi binder's and the
  translation keeps it; a binder the translation itself makes (a `let`
  for an argument, an alias, a held dictionary) takes its quantity at the
  site that makes it, from that site's own uses (one structural fact: an
  alias of a quantity-1 variable joins the variable's uses, so the
  translation writes `Many` there and says why in the constructor);
  a parameter of quantity 1 used twice is an internal error naming it.
- *Deletes*: `mostUses`, `heldAs`, `holdFor`, Emit's `Lazy Nat` counts.
- *Discriminated by*: `tests/func-linear-twice`'s verifier rule stays
  green with no count in Emit; a test whose `LList` parameter is aliased
  keeps its refusal.

**I5. `Forced.idr` becomes a column.** *Coordinator.* Evidence and
correction in §1.2's first row and §2.2 T3, T4. *Counterexample*: a
definition with 200 clauses and 50 alternatives re-patterns 10,000
clause-alternative pairs per instance (`afterCon` filters every clause at
every alternative, 15 FO-2). *Deletes*: the file and `host.argToPat`.
*Discriminated by*: the alias-reading tests (`upTo (Step t p) Here`'s
shape, `Forced.idr:5-8`) unchanged.

**I6. A `let` around a `Delay` keeps the language in both cases.**
*Coordinator.*
- *Evidence*: §1.1 D13; `Translate/Closed.idr:184-197`.
- *Counterexample* (*conjecture* until run): `f : Lazy Nat -> Nat; f _ =
  0; main = printLn (f (let x = loop 0 in Delay 3))` with a partial
  `loop`: eager evaluation loops; the frontend prints 0.
- *Root cause*: the elaborator's fact "this `Delay` was inserted for a
  `Lazy` expected type" is dropped, so the frontend cannot tell
  `do`-notation's `let` from a user's.
- *Correction*: the fork keeps it (T9; the elaborator's `Delay` insertion
  marks its node); the move applies only to an inserted `Delay`.
- *Deletes*: the blanket move.
- *Discriminated by*: the two programs as one test with a `near/`.

**I7. Refusals as ops, rules from the spec, categories true by type.**
*Coordinator.*
- *Evidence*: §1.2's `idr.refusals` row; 16 FC-78; 0003's "category false
  of some of its sites" (`tests/static-argument-stuck-implementation`
  refuses a choice the program bounds under `StaticArgument`, a
  megamorphic rule).
- *Correction*: a refused module holds one refusal op per refusal, its
  site the op's location (MLIR's own carrier), its rule an inherent enum
  property from `Spec.Rules`, its message a string property; `Spec.Rules`
  is indexed by category and carries its scope, and `reject : Rule c ->
  …` at a site whose category the rule's index states.
- *Deletes*: `idr.refusals`, `Verify/Attributes.cpp`'s check of it,
  `Profile.outsideLanguage`, `reason`, the hand scope.
- *Discriminated by*: `tests/rules-covered` unchanged; a rule raised at a
  site of another category does not type-check.

**I8. The family carried is the instance's, laid out by the dialect.**
*Coordinator* (follows D48).
- *Evidence*: §1.1 D48.
- *Counterexample*: `data Tagged : Nat -> Type where MkTagged : Int ->
  Tagged n` collapses to `i64` today (one runtime field), so `Tagged 3`
  and `Tagged 4` are one type and no index refines a match.
- *Correction*: the frontend emits every family and stops collapsing;
  a field's quantity 1 is `!idr.lin<T>` in the field's type (one fact,
  AGENTS.md's "Quantity 1 is a type"), not a second enum in the family.
- *Deletes*: `Registered.Newtype`, `Types.idr:998-1004`, the frontend's
  half of NQ-1's layout choices.
- *Discriminated by*: a module test that a one-field indexed family keeps
  its equation, and the run-time output unchanged.

**I9. 0011's O2 is the Emit of the new dialect.** *Coordinator.*
- *Evidence*: O2 replaces Core and Emit by tables (0011 §8); P0's S5
  rewrites Emit for the redesigned dialect; D19 changes the match.
- *Root cause*: two plans rewriting one module in sequence.
- *Correction*: F8 writes Emit once, over the Core table, for the new
  dialect; A0 (F6) lands before it.
- *Deletes*: one full rewrite of Emit.
- *Discriminated by*: no change between F8's start and end rewrites
  `Emit/` twice (the history of the files).

**I10. A decision whose evidence only proofs read carries it at quantity
0.** *Coordinator.*
- *Evidence*: `Decision`'s `Holds : p -> Decision p`
  (`Proof/Growth.idr:42-45`), used where only erased readers take the
  evidence (`fitsWithin`, `within`, `capsHold`).
- *Correction*: `Decided p = Yes (0 _ : p) | No (0 _ : Not p)` beside
  `Decision`, `Decision` kept where the evidence is read at run time
  (`Check` reads `fitted.pot`).
- *Deletes*: every unary proof built at run time and dropped.
- *Discriminated by*: a request whose static argument holds a large
  literal costs no more than one with a small one (a timing test with a
  bound in program units, never seconds).

## 5. Work units

Drafts for the implementation swarm; none dispatched. Each unit reads
the representation-first and testing-by-search skills first. Write sets
are exclusive; a seam unit of another lane is named.

| unit | write set | outcome | deletes | must not | acceptance |
| --- | --- | --- | --- | --- | --- |
| U0 baseline | `bench/records/<date>-frontend-p0-baseline.md` | the record owner question 2 names, on one commit, per phase with peak memory | — | measure in seconds of a debug build or mix measures in one table | the record exists and names build, input, command |
| U1 TTC readers (with L17's encoder units) | `Frontend/Translate/{Terms,Cases,Closed,Keys}.idr`, `Term.idr`, `Emit/Bodies.idr` (let type), `Frontend/Profile.idr` (T7, T8) | each fact read once into its column, one change per fact | §2.6's T-rows | keep a reconstruction beside the fact; read a fact in two places | the program refused today as `ValueType` for a dropped let type compiles; every suite unchanged |
| U2 tables and signature | `Frontend/Translate/{State,Types,Closed,Forced,Instances,Terms}.idr`, `Frontend/Growth/Sites.idr`, `Frontend/Resolve.idr`, `Registry/*.idr` | §2.3's tables, `Signature` with three positions, registry resolved once | the five readers, `hooksOf`, `conIdOf`'s normalisation, `siblings`, `projectionOf`, `Forced.idr` (with U1's T3, T4) | default a missing fact; key by printed name | refusals and outputs unchanged; a `printf`-shaped test passes |
| U3 locations | `Loc.idr`, `Frontend/Translate/Errors.idr`, `Frontend/Driver.idr`, `Frontend/Program.idr` | `(ModuleId, Span)`; rebuilt terms located | `bestFC`, `isEmptyFC`, `homeOf`, `elaboratedFile`, `noLoc` at the root | print a module name per node | every refusal test's line unchanged or moved to the reference (0003) |
| U4 instance identity and admission | `Frontend/Translate/{State,Keys,Instances,Programs}.idr`, `Frontend/{Finite,Growth}.idr`, `Frontend/Growth/Graph.idr`, `Ids.idr`, `Term.idr`, `Proof/Requests.idr` (`Address` one word, if measured) | one `InstanceId` per `Link`; `Admitted` passed to translation | `fns`, `seen`, `named`, `symbols`, `bounds`, `sizes`, the `Bool` | let an id reach a symbol | stage-2-equal-to-stage-3 bytes on the self compile's module at both hosts |
| U5 memo | `Frontend/Translate/{Instances,Types}.idr` | classification and `coreType` memoised by the full static input | repeated normalisations (15 IN-1, IN-2, TT-6) | key on less than the full input | the comparing run (memo against recomputation) agrees on the corpus |
| U6 linearity | `Frontend/Translate/Terms.idr`, `Term.idr`, `Emit/{Bodies,Declarations,Operations}.idr` | §4 I4 | `mostUses`, `heldAs`, `holdFor` | demote a parameter | an aliased `LList` parameter keeps its refusal; no count in Emit |
| U7 D46 | `Proof/{Bound,Growth,Requests}.idr`, a `Proof/` module for `Template`, `Frontend/Growth/{Template,Graph,Check,Potential,Sites}.idr`, `Frontend/Finite.idr`, `Frontend/Translate/Types.idr` | §2.10 | §2.10 item 6 | add `believe_me`, `assert_total`, fuel; keep the witness beside the proof | `tests/growth-check` identical; no run-time bound check in `Frontend/`; both hosts type-check the proofs |
| U8 termination (with L02's rows unit) | `Facts.idr`, `Frontend/Translate/{Recursion,Programs}.idr`, `Emit/{Declarations,Closures}.idr` | §4 I1 | `TS.loops`, `fromMaybe False`, `total' = True` on lifted functions | read Idris's positivity as a substitute for components | §4 I1's test and its `near/` |
| U9 A0 reader side (with L17's arena unit) | `Frontend/{Walk,Resolve}.idr`, `Frontend/Translate/{Closed,Keys}.idr`, `Frontend/Growth/Sites.idr`, `Ids.idr`, a new `libs/<hash package>/` | TT read from the arena; one XXH3 both import | `Ids.xxh3_128` in the frontend | let an arena id leave the arena | identical TTCs and corpus (0010 A0's proof) |
| U10 families and the dialect (S5, with L03's, L04's, L01's units) | `Term.idr`, `Types.idr`, `Frontend/Translate/{Types,Cases,State}.idr`, `Emit/*`, `Emit.idr`, `MLIR/Bytecode.idr`, `MLIR/Text.idr`, `Frontend/Profile.idr`, `Frontend/Translate/Errors.idr` | D48's families; D50's imports; O2's tables as Emit; no world; refusal ops; the grade view; doubles as bits | `DataShape`, `Newtype`, `idr.refusals`, `linear One WorldT`, `Syntax/Idr.idr`'s printers, decimal floats | keep a shim or alias of a generated name | the suites and the invariant set pass on the new dialect at both hosts |
| U11 relational core | `libs/mlir-relational/**` | 0015 R1, R2 in plain Idris, `%default total`, both hosts | — | reach a `libs/` `%extern` from code the stock host runs | committed expected files of the cases owner question 2 keeps |
| U12 O3 and O8 | `Frontend/Finite.idr` (deleted), `Proof/Generations.idr` (deleted), `Frontend/Translate/{Programs,Instances}.idr`, `Frontend/Laws.idr` (new) | Translate as semi-naive over the instance table, each tuple carrying U7's evidence; laws on every compile | the worklist, the generations argument | change acceptance (0011 D3) | identical Core; laws catch a seeded violation by name |
| U13 `delayedLets` reader (with L17's T9 unit) | `Frontend/Translate/{Closed,Terms}.idr` | §4 I6 | the blanket move | — | §4 I6's test |

## 6. Owner questions

**Q1. D46's one unprovable link: what stands between the normaliser and
the derivation?** The derivation of §2.10 proves every part the frontend
computes. It cannot prove that the static argument the fork's normaliser
returns at a call is the value the site's template reduces to: that is
Idris's metatheory (normalization commutes with substituting closed
values for the probes the reading uses), about a normaliser no type of
ours describes. Today's witness checks exactly that.
- *A. One stated trust, in the fork.* `Idris.Host` gains, at quantity 0,
  that substitution property, over a reduction relation the fork declares
  for the static fragment (heads, beta of families, choice of a stuck
  definition's leaf, projection); the frontend's readers are proved
  sound against the relation; the witness goes. *Costs*: one postulate,
  in the place AGENTS.md puts the frontend's trusts in Idris's compiler,
  beside the termination trust `host` already states; the largest proof
  in the tree (the readers' soundness over eleven constructors); until it
  lands, the witness stays (deleted in the change that lands the proof).
  *Buys*: no check at run time; everything ours proved; the trust is the
  one Idris's own type checker rests on.
- *B. A second evaluator of the static fragment.* The frontend computes
  each request's static value by reducing the site's template itself,
  and generates the TT it substitutes from that value; the derivation
  then holds by construction. *Costs*: two evaluators of static values
  (the fork's for types in bodies, ours for keys), against AGENTS.md's
  "one thing, one representation" and 0010 D3 ("One evaluator", the
  owner's, 2026-10-10); a disagreement becomes a silent miscompile (a
  wrong dictionary) where today it is an internal error. *Buys*: no
  postulate.
- *C. Keep the witness for this link only.* *Costs*: D10 and D46 as
  ruled. *Buys*: nothing new.
- *Recommendation*: A.

**Q2. The absorbed plans' bars, before `make self`.** 0011's, 0010 A0's
and 0015's bars are ratios to O0 and T0, taken natively at `make self`;
P0 precedes self-hosting, so no native frontend exists to measure.
0011's D0 skips a stage under 5%, against D44's "whole"; R1 and R2 are
measured against bumbledb's Rust engine and Soufflé, outside the tree.
- *A.* Baseline = one committed record at P0's starting commit of the
  frontend as it runs today (stage 0 on Chez compiling the frontend, with
  base's elaboration), every stage taken; each stage's gate = identical
  outputs (TTCs, Core, bytecode as 0011 D5 says) and no regression in
  wall or peak against the record; the ratio bars re-measured natively
  once `make self` holds, a miss reworked then; R1/R2's database bars
  stay with 0015's database consumer. *Costs*: the speed bars bind late;
  on Chez a table buys memory more than time (0011 §6). *Buys*: every
  stage lands in P0, gated now.
- *B.* The stages wait for `make self` inside P0, measured as written.
  *Costs*: P0 then follows self-hosting, reversing the queue (D1).
- *C.* The stages that need native bars leave P0 again. *Costs*: D44's
  reversal of the deferral.
- *Recommendation*: A.

**Q3. Do 0011's O6 and O7 pull their needs into P0?** O6 needs 0009's
plain-Idris layer (its stage 7); O7 needs 0015's R4 (e-graphs). D44
absorbs neither.
- *A.* Both come in with their needs (R4 and 0009's layer join P0).
  *Costs*: two more libraries in P0, R4's bar against egglog. *Buys*:
  "0011 whole" literally.
- *B.* O6 and O7 stay in 0011, after P0; "whole" reads as O0 to O5 and O8.
  *Costs*: the elaborator's constraint store and the semiring folds wait.
  *Buys*: P0's scope stays what D44 enumerated.
- *Recommendation*: B.

*HEAD at the finish: `e96bb991` (checked with `git rev-parse --short
HEAD` before the last write); every anchor above is at it.*
