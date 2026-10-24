<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Rederivation audit: data types, indices and layouts

Family: the inductive families Idris checked (constructors, index
equations, fields), the indices a match refines, the shapes a known index
fixes, layout marks (D130), inline-or-cell, field types at binders; from the
TTC through the frontend's types, Emit, the families' C++ (classify, layout
queries, repacks, refinement), the specializer, bufferization and the
lowering's layouts.

HEAD at start: eedaf5d4. HEAD at finish: b2aab6e9 (8b2cd180, L18aa, and its
queue entry b2aab6e9 landed during the audit; the queue entry, three
reindex builders that pick their own result type, is a narrower cousin of
finding 1 and is folded into it).

Method: read only. Nothing built or run: every C++ path needs MLIR, so no
cost below is measured; each is read off the code, and the frequency of a
per-query cost is the count of its call sites (grep), not a profile. The
lane each fix waits on is from `audits/p0/verify/ownership.json`; "M" marks
a file modified in the checkout at finish (`git status`), whose lane holds
it now. Line numbers are the working copy's at b2aab6e9.

Ranked by how much rederivation the fix deletes.

---

## 1. Whether a reindex or a field read is free, works, or builds: one op, three meanings, re-decided from its types at every reader

**The fact.** What `idr.data.reindex` does at run time (nothing: the same
words; work that builds nothing: a cell taken apart, a numeral widened; or
building a fresh cell or array), and whether `idr.data.field` re-packs its
slot into a fresh value.

**First known.** When the op is built: `DataReindexOp::givenType`
(`foreign/idr/lib/IR/Families/Refinement.cpp:57-66`) calls
`families::builds` to pick the result's hold, and `DataFieldOp::build` takes
its result from `fieldReadType`, which calls `families::fieldReadBuilds`
(`foreign/idr/lib/IR/OpsConReads.cpp:22-46`).

**Dropped.** At the op class: one op for all three meanings
(`foreign/idr/include/idr/IR/Generated/IdrOps.td:221`, from
`compiler/spec/IdrisMLIR/Spec/Families/Ops.idr:211-260`, which says so:
"Whether it does work is a fact of its two types (`isFree`)", with
`speculation = Conditionally`, `effects = Executes [] [Repacks 0 0]` and a
member `isFree`). The answer the builder computed is stored nowhere; it is a
function of the operand's and result's types, evaluated again by each
reader. For a field read the re-pack is hidden inside the projection.

**Re-derived** (each a walk of `layoutMatch`, and for `builds` /
`fieldReadBuilds` the re-pack walk of `Repacks.cpp:200-246`, which unifies
each constructor's equation, re-runs the class rule for fields and
re-computes possible constructors; see finding 2):
- the verifier: `Refinement.cpp:80-111` (`builds` again at :93);
- every flow-edge query: `foreign/idr/lib/IR/FlowOps.cpp:152` (field read)
  and `:167` (reindex); flow edges are recomputed per op by about twenty
  consumers (`IR/Flow.cpp`, `Verify/Uses.cpp:242`, `Verify/Local.cpp:127`,
  `Counting/Flow.cpp`, `ExclusivityGraph.cpp`, `Borrows.cpp`, `LabelSites.cpp`,
  `InPlace/*`, `Lifetimes/*`, `Tail/Context.cpp`, `Specialize/Open.cpp:296`,
  `Defunctionalize/Decide.cpp` ...), so per op, per consumer, per pass, and
  per verification;
- every field read's type inference (`OpsConReads.cpp:45`): at build, at
  each verification, and in `followOperands` after a substitution;
- every effect query, through a pair-rule mechanism that exists for this one
  op: `relates<PairCondition::LaidOutApart>`
  (`foreign/idr/lib/IR/Effects/Conditions.cpp:91-98`), expanded by
  `ExpandPair` (`foreign/idr/include/idr/IR/Effects/Rules.h:193-250`),
  declared as `PairCondition`, `PairRuleName`, `PairConsequence`, `ByPair`
  and `Repacks` (`compiler/spec/IdrisMLIR/Spec/Effects/Declaration.idr:318-417,
  430-433, 485-495`);
- speculation and carry: `isFree`, `getCarry`, `getSpeculatability`
  (`Refinement.cpp:125-140`); the carry decides tail position
  (`foreign/idr/lib/IR/Tail.cpp:44-80`, so the "one fact on the call" rests
  on a per-query re-derivation), the tail expectation
  (`Transforms/Expect/Tails.cpp:54-57`) and the specializer
  (`Specialize/Open.cpp:395`);
- bufferization: `byCarry` (`Transforms/Bufferize/Reindex.cpp:123-136`)
  dispatches each of five interface methods (`:138-167`) on `getCarry`, so
  One-Shot's analysis re-decides it at every query: a switch on a tag
  computed per call, the two cases `SameWords` and `Repacked` being two ops
  not yet named;
- the lowering: `LowerReindex` on `isFree` and `repack` on `builds`
  (`foreign/idr/lib/Conversion/Lower/Repack.cpp:249, 280`);
- static data: `ConAttr::getStaticForm` (`foreign/idr/lib/IR/Constants.cpp:220`).

Fixtures hold 31 `idr.data.reindex` and 43 `idr.data.field` in 17 and more
files; the specializer, contify, tail splitting and bufferization make more.

**Carrier.** One op per meaning, from the specification's op list:
`idr.data.reindex` (same words: pure, speculatable, `Carry::Free`, no
effect, a cast as `tensor.cast` is), and a re-pack op (works, consumes its
operand) split by whether it allocates (`Acquisition` on its result, a
fresh value at `builtHold`), each with static ODS effects, speculation and
carry. A field read is a projection at its slot's layout; where the binder's
type lays out otherwise the builder appends the re-pack op. The meaning is
decided once where the op is made, and again only where its types are
rewritten (the substitution already re-infers every op, `followOperands`,
and folds reindexes it made equal, `foldEqualCasts`), which is where the new
fact (a closed index) is first known. It fits the dialect: "an operand,
attribute or enum that changes what an op means or may do is a flag, and
the op is two" (AGENTS.md); the types are that flag here.

**Deletes.**
- spec: `PairCondition`, `pairConditionClosed`, `PairRuleName`,
  `pairRuleClosed`, `PairConsequence` and its readers, `pairConsequence`,
  `ByPair`, `Repacks` (about 110 lines of `Effects/Declaration.idr`); the
  op's `isFree` member and `speculation = Conditionally`
  (`Families/Ops.idr:248, 257`), and the generated pair tables
  (`EffectTree.h.inc`);
- C++ effects: `ExpandPair` and `PairSide` (`Rules.h:193-250`, about 58
  lines), `relates<LaidOutApart>` (`Conditions.cpp:91-98`), its declaration
  in `Vocabulary.h:329` and its use in `Declared.h`;
- `fieldReadBuilds` (`Repacks.cpp:270-290`) and its doc
  (`Families.h:292-299`), its three readers (`OpsConReads.cpp:41-46`,
  `FlowOps.cpp:148-153`);
- the per-query `builds` readers (`Refinement.cpp:61, 93-98`,
  `FlowOps.cpp:160-168`, `Repack.cpp:278-283`); `isFree`, `getCarry`'s
  test and `getSpeculatability` (`Refinement.cpp:125-140`);
- `byCarry` and `AskedOfEither` (`Reindex.cpp:123-136`), the model becoming
  one model per op; `LowerReindex`'s branch (`Repack.cpp:249-252`);
- the queued builders of b2aab6e9 (`Tail/Accumulate.cpp:81`,
  `Defunctionalize/Walk.cpp:109`, `Bufferize/Reindex.cpp:114`) ask the
  classifier once instead of `givenType`.
About 300 lines deleted, about 80 added (the ops from the specification,
one classifier where an op is made or its types rewritten).

**Owner and waits.** L04 (`Refinement.cpp` M, `Repacks.cpp` M,
`OpsConReads.cpp` M, `Families.h` M, `Spec/Families/Ops.idr`), L01 (the
pair machinery, clean), L09 (`FlowOps.cpp` M), L12 (`Bufferize/Reindex.cpp`
M, and b2aab6e9's queued item), L21 (`Lower/Repack.cpp`), L10 (`Tail.cpp`),
INT and L03 (generated `IdrOps.td` M, `EffectTree.h.inc`). Waits on L04's
and L09's in-flight C286 hunks and L18aa's queue item, and on a ruling:
which op holds a fact is the owner's (AGENTS.md, "architectural choices").

**Confidence.** Read (every reader listed was read; the per-query cost is
read, its magnitude unmeasured).

---

## 2. The class rule's unfolding (solved binders, each field's placement, possible constructors) dropped to bare words at the storage, then unified again by every reader

**The fact.** For a data type at its indices: which constructors the indices
leave possible; for each, the terms its binders take (the substitution the
equation solves); and each field's application and placement (class,
layout) under it.

**First known.** In the type's storage construction:
`DataTypeStorage::construct` (`foreign/idr/lib/IR/Types.cpp:139-152`)
computes `possibleAt`, then `classify` (`foreign/idr/lib/IR/Layout/Classes.cpp:330-335`)
whose `Unfolder::unfold` (`:213-247`) unifies each possible constructor's
equation against the indices (`:224-227`) and places every field
(`Unfolder::field`, `:256-303`).

**Dropped.** `LayoutFacts` keeps the class, layout, refs, reach, bound and
the flat slot words only (`foreign/idr/include/idr/IR/Families/Families.h:132-149`,
`SlotPlan::keep`); the per-constructor substitution and each field's
placement are thrown away when `classify` returns.

**Re-derived.**
- in the same construction: `unfold` calls `possibleAt` again on the same
  indices (`Classes.cpp:219`) after `construct` did (`Types.cpp:145`): every
  constructor unified twice for every closed type made;
- `Layouts::fieldsAt` (`foreign/idr/lib/IR/Layout/Layouts.cpp:77-85`) calls
  `solvedBinders` (`foreign/idr/lib/IR/Families/DataNormal.cpp:195-206` over
  `solveBinders`, `:37-57`): one unification per laid-out type and tag, each
  time a `Layouts` is built (the analysis, and the program verifier's own,
  finding 7);
- every re-pack walk (`Repacks.cpp`): `layoutSubst` unifies again
  (`:136-151`), `writtenApplied` rewrites the field's terms (`:154-160`),
  `placementOf` re-runs the class rule for a written field (`classAt`,
  `Classes.cpp:342-349`, `laidAt` and a fresh `Unfolder` wherever the
  `Unfolding::ByHolder` shortcut does not apply), `possibleOf` re-unifies
  every constructor (`possibleAt`, `Repacks.cpp:95-107`); per query, under
  finding 1's readers;
- `DataType::bindersOf` / `determined` (`DataNormal.cpp:61-67, 186-190`)
  unify again for each `fieldReadType` and `determinedFields` call
  (`OpsConReads.cpp:22-30`, `Constants.cpp:182` per cell of a constant per
  verification).

**Carrier.** The unfolding kept in the storage as plain arrays (allowed in
construction, which may make no type): `possible` computed once and handed
to `classify`; per possible tag the binder terms the indices solve (and
whether they determine every binder) as `TermNode` runs; per field its
placement (`Placed`: group, member, written terms, mark, class, layout).
`Layouts`, the re-pack walk and `bindersOf` read it. This is the type's own
fact, so it belongs where the type's other computed facts are ("computed
once, when the type is made", `Families.h:132-137`).

**Deletes.** `classAt` and the `Unfolding` enum with their docs
(`Classes.cpp:336-349`, `Families.h:168-185`); `Repacks.cpp`'s `Written`
origin, the `possibleOf` and `placementOf` arms that recompute,
`layoutSubst`'s unification, `writtenApplied`, `FieldsAt`/`unfoldingOf`
(about 80 lines); `solvedBinders` (`DataNormal.cpp:191-206`) and
`Layouts::fieldsAt`'s unifying branch; the second `possibleAt` in
`unfold`. About 140 lines, and every unification after a type is made.

**Owner and waits.** L04 (`Classes.cpp`, `Layouts.cpp`, `DataNormal.cpp`,
`Types.cpp`, `Repacks.cpp` M, `Families.h` M). Waits on L04's in-flight
`Repacks.cpp` and `Families.h` hunks. With finding 1 the re-pack walk runs
once per op made instead of per query, so the two compound.

**Confidence.** Read.

---

## 3. Emit restates the class rule as "holds references" per family group, and disagrees with the C++'s per-application fact

**The fact.** Whether a value of a type holds a reference a count accounts
for (so whether its grade has a hold), whether a group is recursive, and how
far a claim reaches into a field.

**First known.** In the C++, per application, by the class rule:
`Unfolder::unfold` sets `refs` from the fields actually laid out
(`Classes.cpp:236-251`), `fixedLayout` gives a closed numeral a word with
`Refs::Words` (`:169-199`), stored as `LayoutFacts::refs` and read by
`DataType::holdsReferences` (`Types.cpp:276`); the group's recursion is
`FamilyAttrStorage::containment` (`Families/Family.cpp:221-226`); a field's
reach is `FieldTypeInterface::getFieldReach` (`Types.cpp:244-250`,
`Grades.cpp:249`).

**Dropped / restated.** Emit computes its own, per family group, from the
frontend's `Ty`: `Reaches`, `reachesIn`, `reaches`, `groupReaches`
(`compiler/src/IdrisMLIR/Emit/Index.idr:32, 69-86, 380-397`): a recursive
group always `HoldsReferences`. It decides the grade Emit writes (`grade`,
`:125-132`; `fieldsIn`, `:357-361`, `claimless`, `:348-350`), the field reach
(`reachIn`, `promisedReach`, `fieldReaches`, `:317-345`) and the array op
Emit picks (`Emit/Tensors.idr:379, 438, 571`: `tensor.insert_slice` or
`from_elements` for words, a tabulation otherwise).

**Re-derived and disagreeing.** For a closed application of a recursive
family held in place (`#Vect[3]` of words is three words, `Classes.cpp:12-13`)
or a closed numeral (`#Fin[5]` is a `Word8`), the C++ says `Refs::Words`
and Emit says `HoldsReferences`. A value of such a type graded `once` (a
quantity-1 parameter, `Emit/Types.idr:25-29`; a quantity-1 field,
`Index.idr:360`; and since C286, 45599c62, a fresh result built into a
quantity-1 position) is written `!idr.graded<once, counted, ...>`, which
`GradedType::verify` refuses ("expects no hold of ..., which holds no
reference", `Grades.cpp:121-123`), at the module's read, before any pass.
No fixture holds a quantity-1 closed `Vect` or `Fin` (grep of `tests/` and
`libs/`), so the refusal is latent. Emit's array choice is only
conservative (a tabulation where words would do).

**Carrier.** The C++'s per-application fact, alone. Emit writes the grade it
means (uses and claim); the boundary builder makes it canonical, dropping a
hold the carrier cannot have, as `DataType::getNormalized` already
normalizes a refinement (`DataNormal.cpp:170-182`): the bytecode reader's
`GradedType` builder becomes a normalizing one. The array op is chosen by
the C++ from the element's `holdsReferences` (C284's split, words to
upstream's op, counted elements to the tabulation), not by Emit. The field
reach Emit needs for a field read's hold is the C++'s `getFieldReach` of the
declared field, which the read's inferred type already applies.

**Deletes.** In Emit: `Reaches`, `reachesIn`, `reaches`, `groupReaches`,
`claimless`, `reachIn`, `promisedReach`, `fieldReaches`, the `reaches` field
of `FamilyEntry` and the `Reaches` parameter of `grade` (about 100 lines of
`Emit/Index.idr`), the three `case reaches ix` decisions in
`Emit/Tensors.idr` (about 40 lines move to one C++ choice), the reach
argument of `caseFields` (`Emit/Bodies.idr:396-397, 678`). And the latent
refusal.

**Owner and waits.** L16 (`Emit/Index.idr`, `Emit/Tensors.idr`,
`Emit/Bodies.idr` M), L05 (`Grades.cpp`, the normalizing builder), L12 (the
array choice). Waits on L16's in-flight Emit hunks (C286).

**Confidence.** Read (the disagreement is read off both rules; that a
module with such a value is refused is read, not run: no C++ tool on this
machine).

---

## 4. The possible constructors of a refined type, held by its base, unified again on every get (assertions on)

**The fact.** The constructors a data type's indices leave possible.

**First known.** The unrefined type's storage (`Types.cpp:145-148`, kept as
`DataTypeStorage::possible`); a refined type is made from that base
(`DataType::refined`, `DataNormal.cpp:80-90`, intersects with
`base.possibleTags()`).

**Dropped.** `get` passes the group, member, indices, refinement and binders
as parameters, not the base, so the verifier sees no stored answer.

**Re-derived.** MLIR's `StorageUserBase::get` asserts `verifyInvariants`
on every call (`.toolchain/llvm-project/mlir/include/mlir/IR/StorageUniquerSupport.h:176-181`),
and this toolchain and our C++ keep assertions on (AGENTS.md;
`foreign/idr/CMakeLists.txt:21-44`). `DataType::verify`
(`DataNormal.cpp:143-162`) re-runs `possibleAt` (one unification per
constructor, `:153`) and `determined` (`:160`) for every refined type
requested, uniqued or not. `refinedTo` adds a `determined` of its own
(`:92-99`) and may `get` twice. Callers: every substitution of a refined type
(`Families/Substitute.cpp:172-175`, so every specialization), every match
built (`OpsMatch.cpp:186`), every constant verified, once per cell of its
run (`Constants.cpp:195`), the lowering (`Conversion/Cells.cpp:203`,
`Lower/Statics.cpp:76`, `Lower/Repack.cpp:214`), defunctionalization and
tail jumps (22 call sites). Also `DataType::matchInstance`
(`Families/Matching.cpp:142`) re-unifies the instance's terms per call
operand checked.

**Carrier.** The base as the refined type's parameter (its storage already
keeps it, `Types.cpp:134-145`), so `verify` checks the refinement against
`base.possibleTags()` with no unification; the full check stays at the
text and bytecode boundary (`getNormalized`), the one place parts arrive
from outside. With finding 2 the determined binders are read from the base.

**Deletes.** `verify`'s `possibleAt` and `determined` on the build path,
`refinedTo`'s own `determined`; about 20 lines, and a unification per
constructor at every refined get.

**Owner and waits.** L04 (`DataNormal.cpp`, `Types.cpp`, the type's
parameters in `Spec/Families/Types.idr`), INT (generated `IdrTypes.td`).
Clean in the checkout.

**Confidence.** Read.

---

## 5. Nat-likeness and list shape: decided by the checker, read by the frontend, dropped at the family declaration, re-derived structurally in C++

**The fact.** That a type is Nat-like (a zero and a successor whose one
runtime field is the type itself), with the index its successor descends
along; that a type is list-shaped.

**First known.** The checker: `calcNaty` and `calcListy`
(`compiler/checker/src/TTImp/ProcessData.idr:295-368`) flag constructors
`ZERO`/`SUCC` and `NIL`/`CONS`. The frontend reads `ZERO`/`SUCC`
(`natRole`, `Frontend/Translate/Closed.idr:198-205`) into `Natness`
(`TypeConstructors.idr:380-391`: `Chain` becomes `NatT`, `Numeral` a family
the dialect lays out as a number, `Types.idr:884-889`); `NIL`/`CONS` is read
by nothing.

**Dropped.** The family declaration carries no shape: "A list and a numeral
are shapes the C++ derives from a data member, not kinds of their own"
(`compiler/spec/IdrisMLIR/Spec/Families/Group.idr:17-18`); Emit's
`memberDecl` writes none (`Emit/Index.idr`).

**Re-derived.** `shapeOf`, `descentOf`, `depthAlong`
(`foreign/idr/lib/IR/Families/Family.cpp:133-202`), once per family made,
from the declaration's structure. And the frontend's own copy downstream:
the array language's snoc field is taken for a numeral whenever it is any
data type (`Frontend/Translate/Terms.idr:2332`), though the type
constructor's natness says, so a wrong one is caught by
`NumeralOfNatOp::verify` (`Refinement.cpp:262-266`) as a verifier error
rather than the frontend's `unshaped` refusal; the string ops re-test the
list shape (`IR/Ops/Constraints.cpp:40`, `Conversion/Strings.cpp:124-129`).

**Carrier.** The member's shape in the family declaration (numeral with its
descent position and zero depth, list with its element position), written
by the frontend from the checker's flags and its natness, generated to both
sides from the specification's `Group`; the C++ reads it as it reads
`Promise`.

**Deletes.** `shapeOf`, `descentOf`, `depthAlong` (about 70 lines of
`Family.cpp`); the snoc field's guess (`Terms.idr:2332`) becomes a read of
natness; the list re-tests read the declared shape. The spec gains one
field.

**Owner and waits.** L04 (`Spec/Families/Group.idr`, `Family.cpp`), L16
(`TypeConstructors.idr` M, `Terms.idr` M, `Emit/Index.idr`), L13
(`Ops/Constraints.cpp`, `Conversion/Strings.cpp`), L17 (none: the flags
exist). Reverses a recorded design (Group.idr's sentence), so it waits on a
ruling.

**Confidence.** Read.

---

## 6. A family's declaration looked up by a bare id at every type, term and sort Emit writes, with silent fallbacks

**The fact.** That family `f` is declared, as member `m` of group `g`.

**First known.** At registration: the frontend groups families into
`Source.groups`, and Emit numbers them once (`declare`,
`Emit/Index.idr:399-410`).

**Dropped.** `Ty`, `ITerm` and `Sort` hold a bare `FamilyId`, a `Nat`
(`compiler/src/IdrisMLIR/Ids.idr:37-39`, `Types.idr:126, 133, 155`).

**Re-derived.** Thirteen `SortedMap` lookups in `Emit/Index.idr` (`:74-76,
150-156, 213-217, 261, 286-290, 330-332, 344, 389`), one per data type,
constructor index term, sort and field written, each with a `Nothing` arm
for a state the representation allows: a family no group declares becomes
`NoneType` (`:156`), an opaque index term (`:217`, weakening what a match
learns, silently), an opaque sort (`:290`), "holds references" (`:76`) or
"reaches nothing" (`:332`).

**Carrier.** A family reference resolved at registration into its group and
member (dense numbers into a `Vect` of declared groups, or the entry
itself), so a lookup cannot miss.

**Deletes.** The thirteen lookups' `Maybe` arms and the three silent
fallbacks (about 30 lines).

**Owner and waits.** L16 (`Ids.idr`, `Types.idr`, `Emit/Index.idr`; the
frontend's other files M). Waits on L16's in-flight frontend hunks.

**Confidence.** Read.

---

## 7. Cell sizes counting decided, rebuilt whole by the program verifier at every verification

**The fact.** The byte size of a constructor's cell, which decides which
tokens a recycle may take.

**First known.** By counting, from the `Layouts` analysis
(`Transforms/Counting/Reuse.cpp:147`, `getAnalysis<Layouts>()`), when it
assigns tokens to cells of one size.

**Dropped.** The token type keeps its source types, not the size
(`verifyRecycle`, `IR/Counting/Ops.cpp:64-77`).

**Re-derived.** The program verifier builds a whole new `Layouts`
(`IR/Verify/Program.cpp:89-99`): every data type the module holds, their
field types (`instantiateFields`, making types, and finding 2's
`solvedBinders`), every cell, the reach of each, and the target's measures,
on every verification of a program holding a recycle, so after every pass
from counting to the lowering, beside the analysis manager's copy.

**Carrier.** The size on the token, written by counting from the analysis
it has; the verifier compares sizes in O(1), and the one place that lays
cells out (the lowering's `Layouts`) checks a token's size against its cell
once.

**Deletes.** The verifier's per-verification `Layouts` (`Program.cpp:86-99`)
and `verifyRecycle`'s two table lookups per source.

**Owner and waits.** L04 (`Verify/Program.cpp` M), L07 (`IR/Counting/Ops.cpp`,
`Reuse.cpp`, the token type in `Spec/Counting`). Waits on L04's hunk in
`Program.cpp`.

**Confidence.** Read.

---

## 8. Emit re-compares each value's type with its slot's, because the core term does not carry its type

**The fact.** That a value and the slot it fills are one Idris type, up to a
refinement of indices or the static extents of an array.

**First known.** Idris's checker, which typed the term.

**Dropped.** The frontend's core `Term` is not indexed by its type (Emit's
own note: "Kept: the core term holds the type each slot takes ... but no
proof that the two agree", `Emit/Tensors.idr:202-208`).

**Re-derived.** `fitting` (`Emit/Tensors.idr:160-177`) compares the two `Ty`
structurally at every slot filled (call arguments, fields, region results)
and chooses `AsIs`, a cast, a reindex, or `Mismatch`, an internal error for a
state the representation allows (`:207`); the C++ scope walk then checks
each reindex against the refinements again (`Families/Scope.h:84-120`,
which is a verifier and stays).

**Carrier.** The translation emits the reindex where it reads a variable at
a refined type (where the case's refinement is known), so Emit compares
nothing; or a core term indexed by its type.

**Deletes.** `Fitting`, `fitting`, the `Mismatch` arm and `unfit`'s use
here (about 50 lines).

**Owner and waits.** L16 (`Emit/Tensors.idr`, the frontend's terms M). A
core shape the owner decides (Emit's note records it as kept).

**Confidence.** Read.

---

## 9. A numeral constant kept as a run of successor cells, its number walked out again

**The fact.** The value of a constant numeral (`Fin`, `Elem`), whose layout
is a number.

**First known.** Where the constant is formed (the frontend's constructor
terms, folded by the e-graph into a `ConAttr` run).

**Dropped.** Held as constructor cells, though no layout of a numeral is a
cell.

**Re-derived.** `numeralValue` (`Families/Refinement.cpp:268-280`) walks the
run per fold of `idr.numeral.to_nat` (`:283-288`) and per static form
(`Constants.cpp:223-225`).

**Carrier.** A numeral constant as its number at its data type.

**Deletes.** `numeralValue` and its two walks (about 15 lines).

**Owner and waits.** L04 (`Refinement.cpp` M), L13 (`Constants.cpp`, the
e-graph's `Fold/Values.cpp`). Waits on L04's hunk.

**Confidence.** Read.

---

## Considered, not findings

- Erasure: the frontend reads Idris's `eraseArgs` once (`Closed.idr:414-424`),
  P0's 17 FB-15 is closed.
- `LayoutFacts::slots` and `Layouts::SumLayout` (`Layout/Components.cpp:224-240`):
  the second is the first with its word types made, for workers that may
  make no type; a copy for a stated reason, not a rederivation.
- The checker's `detagBy` (`ProcessData.idr:151-200`) is coarser than the
  C++'s `possibleAt`, which decides per application; not the same fact.
- `resolveBinders`, `pruneUninhabited`, `followOperands`
  (`Families/Substitute.cpp:322-533`) re-derive after a substitution, where a
  closed index is new information: essential.
- The tail-layout checks (`Tail.cpp:378-394`, `Expect/Tails.cpp:115-130`)
  are verifiers of D129's rule over stored type facts.

---

## Table

| # | Fact | Drop site | Rederive sites | Carrier | Lines deleted | Owner | Waits on |
|---|------|-----------|----------------|---------|---------------|-------|----------|
| 1 | reindex / field read free, works or builds | one op for three meanings (`Spec/Families/Ops.idr:211-260`, `IdrOps.td:221`); field read hides its re-pack | verify (`Refinement.cpp:93`), flow edges (`FlowOps.cpp:152,167`, ~20 consumers), inference (`OpsConReads.cpp:45`), effects pair rule (`Conditions.cpp:97`, `Rules.h:193-250`, spec `Declaration.idr:318-495`), carry/speculation (`Refinement.cpp:125-140`, `Tail.cpp:44-80`), bufferization (`Reindex.cpp:123-167`), lowering (`Repack.cpp:249,280`), static form (`Constants.cpp:220`) | one ODS op per meaning (cast / re-pack / allocating re-pack); field read = projection + explicit re-pack | ~300 (+~80) | L04, L01, L09, L12, L21, L10, INT | L04/L09 C286 hunks, b2aab6e9 queue item; owner ruling (which op holds the fact) |
| 2 | unfolding: possible ctors, solved binders, field placements | `classify` keeps flat words only (`Families.h:132-149`) | double `possibleAt` in one construction (`Types.cpp:145`, `Classes.cpp:219`), `Layouts::fieldsAt`/`solvedBinders` (`Layouts.cpp:77-85`, `DataNormal.cpp:195`), re-pack walk (`Repacks.cpp:95-160`, `classAt` `Classes.cpp:342`), `bindersOf`/`determined` per field-read inference | unfolding stored as plain arrays in `LayoutFacts` | ~140 | L04 | L04's `Repacks.cpp`/`Families.h` hunks |
| 3 | holds references / recursive group / field reach | Emit's own per-group rule (`Emit/Index.idr:32-86,317-397`) | C++ per-application refs (`Classes.cpp:236-251`), containment, `getFieldReach`; disagreement refuses a once-graded `#Vect[3]` / `#Fin[5]` (`Grades.cpp:121`) | the C++ fact alone; normalizing `GradedType` builder at the boundary; array op chosen in C++ | ~100 Emit + ~40 moved | L16, L05, L12 | L16's C286 Emit hunks |
| 4 | possible ctors of a refined type | base not a parameter of `get` | `DataType::verify` on every refined get under assertions (`DataNormal.cpp:153,160`), `refinedTo` (`:92-99`), `matchInstance` (`Matching.cpp:142`); 22 callers incl. every substitution | base as parameter; full check only at `getNormalized` | ~20 | L04, INT | none in checkout |
| 5 | Nat-like / list shape | family declaration has no shape (`Spec/Families/Group.idr:17-18`) | `shapeOf`/`descentOf`/`depthAlong` (`Family.cpp:133-202`); snoc numeral guess (`Terms.idr:2332`) caught by `NumeralOfNatOp::verify`; list re-tests (`Ops/Constraints.cpp:40`, `Strings.cpp:124`) | shape in the declaration, from the checker's `ZERO/SUCC`/`NIL/CONS` | ~70 | L04, L16, L13 | L16 hunks; ruling (reverses Group.idr's design) |
| 6 | family declared as group/member | bare `FamilyId` in `Ty`/`ITerm`/`Sort` (`Ids.idr:37`) | 13 lookups in `Emit/Index.idr`, fallbacks to `NoneType` (`:156`), opaque term (`:217`), opaque sort (`:290`) | resolved group/member reference | ~30 | L16 | L16 hunks |
| 7 | cell byte sizes | token keeps sources, not size (`Counting/Ops.cpp:64`) | program verifier rebuilds whole `Layouts` per verification (`Verify/Program.cpp:89-99`) | size on the token; lowering checks once | ~25 | L04, L07 | L04's `Program.cpp` hunk |
| 8 | value and slot are one Idris type | core `Term` untyped (`Emit/Tensors.idr:202-208`) | `fitting` per slot (`Tensors.idr:160-177`), `Mismatch` internal error (`:207`) | reindex emitted where a refined variable is read; or typed core term | ~50 | L16 | owner (core shape) |
| 9 | constant numeral's value | kept as successor cells | `numeralValue` per fold and static form (`Refinement.cpp:268-288`, `Constants.cpp:225`) | numeral constant as its number | ~15 | L04, L13 | L04's `Refinement.cpp` hunk |
