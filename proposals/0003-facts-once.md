<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Each fact once

**Amended by P0 (2026-10-21, `0000-mlir-native.md`).** Absorbed whole
into the cutover (D44), which reverses the owner's 2026-10-19 deferral
of this proposal to after self-hosting: its 62 items are placed on the
cutover's lanes (C136, `audits/p0/verify/L16-frontend.md` §2.9), written
by them beside P0's stages, and built only with the whole cutover, never
one by one (D56). Where P0 decided an item, the item below states P0's
form and names the ruling.

**Status (2026-10-22):** written in P0, nothing of it built on its own.
Built before P0: the term locations a TTC keeps (374e0e77); the force
dispatch's and an apply's cases placed at their labels (8e2fbec7); and
the dialect's binary format no longer read by hand, one ODS record read
and written by both sides' generated code, which self-hosting's S3
forced (the owner, 2026-10-19: "we cannot have the binary format be read
by hand"). The program's table of data type bodies that record held
goes with P0's families: a data type is a family attribute holding its
declaration (D48), native in bytecode (C50).

The compiler knew a fact at some point, threw it away, and derives it
again later, or guesses it. Where it comes from: five read-only sweeps
over 374e0e77's parent (the checker, the frontend and Emit, the dialect,
the passes and the driver, the runtime and the harness), the leftovers
of the representation wave (its packet's last text is at 77eaa5b1, with
the MLIR audits that went with it), and the ownership lane's static
lifetime. Each item gives where the fact is known, where it is lost,
where it is derived again, and the fix. The sweeps read code and ran
nothing, so the lane that takes an item confirms it first, and deletes
it here (or says why it is not one) when it lands.

## 1. Keep, or derive from a tighter representation

Not every rederivation is wrong (the owner, 2026-10-19: "for those that
are low risk (line numbers in the source is a perfect example) ... other
stuff, there may be merit to rederiving from a tighter representation").
Each item is decided by these rules when it starts, and the decision is
written beside it:
- **Keep** a fact when deriving it again is a guess (it can fail, or two
  derivations can disagree), when the derivation can refuse a valid
  program or hang, or when it costs more than linear. Source locations
  are the plain case: nothing can derive them again, and keeping them is
  low risk, so every location item goes first.
- **Derive** a fact when it is a total, cheap function of a smaller
  representation that is the one source, and keeping it would make a
  second copy that can drift (a cache held beside its source is the
  second copy). The fix then makes the derivation the one function every
  reader calls, and deletes the stored copy and the other derivations.
- Either way, one fact has one source, and every reader reads that.

## 2. The order

1. **Locations, every lane's** (low risk, §1): the frontend's rebuilt
   terms, the program root, library modules, data type declarations,
   folded matches' arguments, output rewrites, raise consumers, tail
   loops, frames, deduplicated bodies, driver errors, `idr.crash_str`,
   the report's column, and line tables. Each is below in its lane's
   section.
2. **The checker's TTC**, by the rules of `compiler/checker/README.md`,
   "What a TTC keeps": a let's type (C1, which refuses valid programs
   today), a match's scrutinee type (C2), a leaf's clause number, a
   block's parent (B1), imports' locations (B3).
3. **The rest**, by lane, in the order of each section.

## The checker's TTC and the frontend (arrays lane)

The root cause of most of the frontend's guessing: the checker's TTC is
lossy, and every definition the frontend reads, main's included
(`ModTree.idr` `buildDeps`: `clearCtxt`, then `readAsMain`), comes back
through it. The checker is ours (P0's D118, C233); each loss is fixed in
its encoder, with `ttcVersion` bumped, and the frontend's reconstruction
deleted.

How far the checker's TTC stops matching upstream's, and the care each
kept fact takes, is `compiler/checker/README.md`, "What a TTC keeps".

- **The frontend's rebuilt terms.** The TTC keeps every node's location
  (374e0e77), but the terms the frontend rebuilds take `EmptyFC` instead
  of the location of what they rebuild (`Translate/Closed.idr` betaAll,
  applyAll, pack/unpack; `Terms.idr` `settle`; `Shapes.idr`;
  `Growth/Sites.idr`; `Growth/Template.idr`). Give each the FC of what it
  rebuilds; then `bestFC` and `Sites.siteAt`'s copy of the same fallback
  go, and reach refusals (`Profile.userFC`) are placed at the reference,
  not the referring definition.
- **C1, a `let`'s type (correctness: refuses valid programs).** Written as
  a comment (`Core/TTC.idr` `-- ; toBuf ty`), read as `Erased`.
  `Terms.valueType` guesses it for a lambda, a variable or a `Ref`
  application only; anything else is "not known here", and `applyOver`
  refuses a compile-time argument to it as ValueType. Keep the type,
  give `Term.Let` its binder, delete `valueType` and Emit's second
  synthesis of the Core type.
- **C2, a match's scrutinee type `scTy`.** Not written, read as `Erased`.
  `Cases.instanceOf` infers the data instance per match (an internal error
  when it cannot); `siblings` derives the type constructor again and
  answers `[]` on a miss, so a default that stands for no value is
  translated. Keep it; delete the inference and `VarInfo.Runtime`'s
  `Maybe`s.
- **A leaf's clause number.** `STerm` is written without its index and
  read as `STerm 0`, so all of `Translate/Forced.idr` rebuilds the
  clause-to-leaf map, per function instance, by re-running `argToPat` and
  guessing coverage, first clause winning. Keep the index (and the
  builder's `List Pat` per clause in `PMDef`); delete `covers` and the
  alias merge.
- **B1, a block's parent (correctness: a wrong root can hang the
  normaliser and change trusted admission).** Case and with blocks store
  `prettyName` text, which drops the namespace and prints a `DN` as its
  display name; `Nested` stores a session-local index. `Closed.outermost`
  parses the text back, `rootOf` rebuilds `NS ns (UN …)`, and
  `Keys.keyOrigin` searches the whole context for the parent and counts
  the block's number. Keep the parent as a resolved `Name` with the
  block's kind and ordinal; delete `outermost`, `rootOf`'s climb and the
  search.
- **B3, imports.** The TTC's `imported` has no FC, so `Profile.imports`
  scans the source with `words`: an `import` inside a block comment is
  imported (and can be refused), one split across lines is missed. Carry
  each import's FC and `ModuleIdent`; delete the scanner and the string
  matching in `Program.idr`.
- **The main source path.** `Resolve.elaboratedFile` works back from the
  TTC path and tries extensions until a file exists, though the driver
  had `source`. Thread it through; delete `elaboratedFile`.
- **Erased arguments, five readers.** Idris's `eraseArgs` is on the
  definition; `Closed.erasedArgs` (unnormalised), `Forced.quantities`
  (normalised, default erased), `Sites.quantitiesOf` (normalised
  sometimes), `Terms.lastRuntime`/`binder` and `Types.conBinders` each
  read it again with different defaults, so an argument behind `a -@ b`
  is erased to one and run time to another. One reader per definition,
  cached by address.
- **The `Impossible` marker.** The frontend uses `Erased _ Impossible` as
  "a run-time value"; it is unambiguous only because the TTC loses
  Idris's own `Impossible`. Move it to a probe name before the TTC keeps
  erasure reasons.
- **C3, a constructor's type constructor, three ways.** `conIdOf`
  normalises, `siblings` does not (wrong for `-@`), `Sites.conStands` has
  its own; `Types.idr` normalises one constructor twice. One table,
  constructor address to (type constructor, tag), built once in
  `tyConFacts`.
- **C4, a request classified twice.** The call site classifies the callee
  and stores `kinds`; `Programs.idr` runs `classify` on the definition
  again. `Request` carries the result; the second run goes. Its
  definition is also looked up again by name (`lookupDef EmptyFC`, a
  `Maybe`) though `p.link.definition` is its address.
- **C5, what an implementation closes over, twice.** `Growth/Sites.holed`
  and `Terms.holed` disagree (one reduces, one does not), and a
  disagreement surfaces as an internal unsoundness. One function.
- **B5, the registry resolved and thrown away.** `validate` resolves every
  entry and returns only `Maybe Refusal`; about twenty call sites then
  re-derive hooks through `show n` and a string map, and `foreignHook`
  re-parses spec strings per entry. `validate` returns the resolved
  table keyed by address.
- **B4, spelled pragmas keyed by root-name string.** An unrelated
  definition with the same root name is silenced. Key by resolved `Name`.
- **B6, package names parsed out of TTC paths.** Record them when the
  session adds each package.
- **B7, an instance's identity printed for C++.** The frontend holds
  `link.definition : Address` and emits only `show`; C++ keys
  specialization nodes by the string. Emit a typed identity.
- **Locations defaulted though known.** The program root is `noLoc`
  though main's FC is in hand, and Emit's comment says it is main's
  (`Programs.idr`); generated world lambdas (`Terms.idr` exit action,
  `ATabulateIO`) and `closedOver` drop `loc`; `lookupDef EmptyFC` while
  `p.site` is known (`Programs.idr`, `Types.idr`, `Growth/Caps.idr`);
  `Dictionaries.chooser` reports at the user definition, not
  `Request.site`; two "no location" defaults (`Driver.mainSite`,
  `moduleFC`) and the file start computed twice.
- **A5, a library module without installed source becomes `UnknownLoc`**
  (`MLIR/Bytecode.idr`, `MLIR/Text.idr`) though its module and span are
  known. Write a `FileLineColRange` on the module's canonical path.
- **Smaller:** `tot = fromMaybe False` where the component was always
  checked (an internal error, not a default); `Recursion.idr` re-resolves
  addresses each `Member` holds; `Crash` re-derives trust from the
  location though `Profile.level` classified it; errors are merged by
  printed text; non-user names decode with default facts that
  `Profile.refsOf` reads.
- **D1, Emit's use counts, quadratic.** `mostUses` traverses the body at
  every let, field, lambda and parameter. Return use summaries from the
  paramorphism.

## The dialect: ownership (ownership lane)

- **A token without its cell.** `!idr.token` has no parameters, so the
  program verifier, `Conversion/Fields.cpp`, `Demand.cpp` and
  `ReusesEveryCell.cpp` each walk back to the `idr.take`. A token reaching
  its recycle through a block argument is refused by the verifier (a
  representation limit acting as a refusal), and `Fields` silently stores
  every field again. P0's token names the family applications and
  constructors whose cell it may be, `!idr.token<{#F[i] @C, ...}>`, a
  non-empty set of one layout, linear, either `counted unique deep` and
  never null or `counted` with no claim (C39), `!idr.box` being no longer
  a type (D48); the four walks go, and C39 deletes the `Fields` table
  (the reuse pairing `reuseAt` decided is then in the type).
- **Static, searched for along the definition chain:** below, "Static in
  the grade".
- **A `dup` of atoms-only data exempted by its producer**
  (`Verify/OwnedOps.cpp`): the `dup` gives `excl` when its operand
  reaches only atoms.
- **Exclusivity solved twice** (`Ownership/Exclusive.cpp` re-solves the
  whole program when grade copies exist), and `ownsParameter` answers
  from the signature or the grade depending on whether a table was
  passed.
- **`quantities-kept` identifies binders by location**
  (`Expect/Quantities.cpp`) and drops colliding keys silently, so every
  pass that stamps one location on many binders weakens the contract.
  Key by the binder.

### Static in the grade

**The bug it removes.** Whether a value is static is searched for, not
known: `ownership::isStatic` (`IR/Verify/Uses.cpp`) walks the value's
definition chain for an op that `madeStatic` accepts (no regions, pure, no
operand that holds references: a constant, poison, a small big, a
global's buffer), and anything read from such a value is static too. Its
readers are counting's classes (`Transforms/Ownership/Classes.cpp`:
`Class::Phantom`, `Class::Constant`, `Class::StaticRead`, and Placement's
plan for each), `Analysis/Ownership/Values.cpp` (`tracked`),
`Analysis/Ownership/Reuses.cpp`, `Transforms/Narrow/Facts.cpp` and the
program verifier (`IR/Verify/Program.cpp`); the owned verifier asks
`madeStatic` alone (static data is a view there). Two consequences: the
answer changes when a pass rewires a chain (6f774119: a capture became
non-static once idr-tail-loops moved its match into a loop), and every
reader re-walks a chain per use (under the cutover IdrRcGrades on
every-interfaces-export went from about 3.5 s to about 21 s, unbisected).

**Why the first cutover was taken out.** 467fa2f5, fc1a5daa, 4365c540 and
ccc9f4e7 made `Lifetime::Static` a grade idr-rc wrote, but graded a value
static from where it came, not from what it holds: a constructor of
runtime words became static data, and a constant printed a lifetime its
uses' syntax did not parse. c4d38e9b restored 902076f4's `isStatic`,
keeping `rebindDefaults` (a match's default binding is its scrutinee to
counting) and `Captures::keepMadeIn`.

**Owed, as P0 decides it** (D39: "0003's owed static lifetime is
this"). `static` is a hold of the grade, not a lifetime: a value's grade
is `!idr.graded<uses, hold, T>`, its hold `static` (never freed, shared
by definition, so with no sharing level) or `counted` or `scoped` with
what is known of its sharing (D88, D90, C21). A lifetime is no part of
the grade: it is an SSA value of type `!idr.lifetime<…>` (D63, D93).
The hand enum `Idr_Lifetime` (`IR/IdrBase.td`) with its `heap < frame`
order goes (C21); `heap` names the resource, and the hold freed by its
count is `counted` (D90).
- static is graded from what a value holds, never from where it came
  (D39): `static` comes from a constant's type, the frontend's literal
  types and the field-read rule, never from purity (C86). A constructor
  or closure built at run time is not static, whatever its fields hold;
- no hold is ever undecided: before counting, a value that holds
  references is `counted` with no sharing claim, or `static` for a
  constant, and later passes only strengthen it, each a verified
  refinement (C144);
- a `dup` or `drop` of a static value cannot be written (C40). Static
  data reaching code that counts meets a copy specialized by hold, which
  counts nothing; only a function that receives both, past the
  specialization budget, keeps the runtime's count-0 marker test (D89);
- the Idris side imports the grade's parts from the specification
  (D50), so every grade a constant carries prints and parses on both
  sides.

Deleted in the same change (C86): `madeStatic` and `isStatic` with
their nine callers, counting's `Class::Phantom`, `Class::Constant` and
`Class::StaticRead` with Placement's plans for them, `persistHeld` and
`idris_rt_persist_held`. A buffer an upstream op makes enters the
grades through `own.adopt` (C185). (`StaticData::isStatic` in
`Conversion/` is the lowering's question of a global's component, not
this one.)

**Acceptance**, in the cutover's qualification: it is built with the
whole cutover, never on its own (P0's D56). `git grep` finds neither
`ownership::isStatic` nor `madeStatic`; IdrRcGrades on
every-interfaces-export stays near 3.5 s (Debug); nat-parity,
escape-hatch-hole-at-runtime, lower-static-thunk, lower-value-buffers,
verify-sources and effects-memo-state pass.

## The dialect: matches and locations (control lane)

- **A pattern variable's location replaced by the match's** when a match
  folds: `canon::readField`, `Canon/Force.cpp` `capturesOf`, and
  `Canon/Merge.cpp`'s default argument build at the match's location
  though `arg.getLoc()` is in hand. Use the argument's (fused with the
  match's).
- **Output rewrites keep the builder's location** (`Canon/Output.cpp`):
  `writePieces` and `firstChar` take the replaced op's location.
- **What an enclosing match says about a value, three ways**
  (`OpsMatch.cpp` `takenFromEnclosing`, `Canon/Eta.cpp` `knownFromMatch`,
  `OpsConReads.cpp` `FieldOp::canonicalize`), with different identity
  rules; `TagOp::fold` never asks. P0 puts the fact in the IR instead of
  a query: each case of a match binds the scrutinee refined to that
  case's constructor, its family at the refined index, and the fields
  are reads of that refined value, total since its type fixes the
  constructor (D105, D48). No walk asks what the match said, and
  `FieldOp::canonicalize` goes with every canonicalization pattern on
  our ops (D98).
- **Two upward walks without `definitionChain`'s cycle guard**
  (`Fold/Bigs.cpp` `BigToIntOp::fold`, `Conversion/Fields.cpp` `moved`):
  a named step in `Grades.h` on `definitionChain`.
- **`knownNonEmpty` re-walks the append tree per question**
  (`Crashes.cpp`): quadratic on long chains. Put non-emptiness in the
  type, as `!idr.nat` holds non-negativity.
- **A raise node's consumer** (`Specialize/Consumer.cpp`, `Raise.cpp`) is
  built at `UnknownLoc`, then every pushed op is overwritten with the
  callee's return: a crash in the dispatch prints the wrong place. Wrap
  as `CallSiteLoc(opLoc, term)`, as inlining does.
- **Tail loops** (`Tail/Loop.cpp`, `WhileDo.cpp`) put the loop, its block
  arguments and yields at the function's location though the self call's
  and the match's are known. **Frames' resume cases** (`Frames.cpp`) at
  the member's, though the frame site's is known; `closureLabels` walks
  every value's type on every run though the sums are
  `TypeGraph::declarations()`.
- **Deduplicate** fuses only the function's location; fuse op by op along
  the lockstep equivalence.
- **Data types carry no location.** `Declarations::define` errors at
  `UnknownLoc`, and the knot refusal guesses one (first array, first
  located con, else the program). Under P0 there is no body, table or
  `DataRemap`, and `Declarations` goes (D48): the family attribute
  carries its declaration's location, written by the frontend from the
  location the TTC keeps for the type constructor (placed by C136 at
  `audits/p0/verify/L16-frontend.md` §2.9, F8).

## Defunctionalization and the optimizer (defunc lane)

- **Analyses dropped and rebuilt.** `Effects.cpp` preserves only
  `SymbolTable` though it writes only effects, so Contify rebuilds
  `CallCycles`; `Defunctionalize/Pass.cpp` builds a `TypeGraph` outside
  the manager for a statistic and Knots builds it again; `TypeGraph(op)`
  is also built directly by `Layouts`, `layout::fit` and the program
  verifier after every pass, and `verify::recycles` builds a whole
  `Layouts` to compare two sizes. `Layouts` takes the `AnalysisManager`.
- **`givesBack` solved twice:** idr-optimize's summaries go at the pass's
  end and `Tail/Returned.cpp` solves it again on the lowered module.
  Carry it as LLVM's `returned`, and seed the lowered solve with it.
- **The optimizer rescans each wave** (`Waves.cpp` `enable`) and restamps
  every call's effects each round (`Component.cpp` `writeCallEffects`);
  the comment about one symbol-use map is stale.
- **A consumer form cloned per request** though interned, and named by
  printing after hashing already decided it (`Consumer.cpp`).
- **Ranges discarded** (`Narrow.cpp`) and re-solved over the whole
  program after versioning a few loops; `Lanes.cpp` finds a size bound by
  search behind a run-time guard, maybe one `Ranges` proved. Emit ranges
  as `range` facts and seed the re-solve.

## Target, lowering, driver, runtime, harness (target lane)

- **One target machine recipe.** MLIR-side builds use
  `getTargetMachine(TargetAttr)` with default options, codegen uses
  `idr::target::machine`: the vector width, the required CPU bits and the
  return-register answer come from a differently configured machine.
  idr-target writes every target fact once into the DLTI spec; `Run.cpp`
  stops resetting the triple and layout from constants; `OsOp::fold`'s
  fallback to the build machine's triple goes (the program verifier
  requires the target). A first attempt (2026-10-19, reverted unpushed)
  refused every module: the layout that goes machine, DLTI spec, MLIR's
  translation compares unequal to the machine's own under LLVM's
  structural `DataLayout::operator==`. idr-target checks that the
  lowered module's DLTI spec is the one it writes from the machine,
  rather than comparing LLVM layouts after translation.
- **Function facts not lowered.** `effects` and `total` reach no LLVM
  attribute; LLVM re-infers weaker ones. Map them in `LowerFunc`
  (`willreturn`, `mustprogress`, `nounwind`, `memory`).
- **No line tables.** Every op has a source range through lowering and
  nothing emits debug info; run `ensure-debug-info-scope-on-llvm-func`
  before translation.
- **`idr.crash_str` drops its site;** lower it through `Runtime::crash`.
  The report drops the column and later locations of a `FusedLoc`;
  `harness/lib/profile.sh` drops the file; driver errors sit at
  `UnknownLoc` though the path is known.
- **No stack probes against the 1 MiB guard.** Compiled code takes
  none (P0's D77): every compiled function's frame size is known, so
  the build proves that none exceeds the guard, and the native stack's
  size is computed from the call graph when the program is built (D32).
  Only the runtime's own C++ and what it links, whose frames may be
  sized at run time, take stack-clash protection.
- **The user address width** is a recorded minimum used as a maximum in
  `static_assert`s: record the maximum or check at startup.
- **The ending lost:** the harness infers return, exit and crash from the
  status and stderr (`exitWith ExitSuccess` fails spuriously; three
  copies of the protocol). One report channel from the runtime.
- **`make compile OUT=`** keeps only the basename. Pass `-o` through.
- **The upstream runner:** `rejection_skip` calls the deleted
  `refusal_rule`, so outside-the-language refusals count as failures;
  `skip_reason` greps identifiers the compiler supports (pointer
  handles, getenv). Classify by the report's rule category.
- **Held twice or re-parsed:** `uname` for target names (read a CMake
  fact); prelude coverage from printed Core and REPL text (the report
  lists reached definitions); `%differential` rebuilds the pipeline from
  text; the handoff dialect list twice, already disagreeing on `scf`;
  libm symbols split; artifact layout and the checked runtime's path
  spelled in the harness; the lock and stamps parsed four or five ways;
  the test-unit box list from a glob; compile_commands re-read;
  `page-size-mismatch` hand-spells flags `baseline-cpu-flags` holds;
  `idris_rt_memref_copy` re-reads the element layout the compiler had;
  simdutf re-tests the CPU word `idris_rt_start` already has; bench
  duplicates (`labels=`, CPU count, `bounded`, two timing parsers).

## The representation wave's leftovers

What the wave's packet left unbuilt, checked against the code at
77eaa5b1; everything else in it is built.
- **A data type's body holds a kind beside its constructors' roles**
  (control lane). `DataType::Body` is `{kind, ctors, instance}`
  (`IdrTypes.td`), and `KindRule`, `RoleOnce`, `ruleOf` and verifyBody's
  table of legal role and kind pairs (`lib/IR/DataBody.cpp`) check the
  pairs; there is no `DataType::memo()`, so the force dispatch keeps a
  catch-all internal error (`Defunctionalize/Forces.cpp`) and
  `Fold/Values.cpp` walks a list of roles. P0 replaces the body: a data
  type is a family attribute holding its declaration, with no table of
  bodies (D48), and a group's member kinds are a closed sum (data,
  closure, memo), list and numeral derived shapes and `in_place` a
  `Promise { None, InPlace }` on the data member (C80). Deleted:
  `Idr_SumKind`, `Idr_CtorRole`, `KindRule`, `RoleOnce`, `ruleOf`,
  `roleTags` (C80) and the `#idr.types` table with `DataBody.cpp` (D48).
  Acceptance: a role that does not fit its kind cannot be written; the
  catch-all arm is gone.
- **The owned stage reads upstream's buffer ops by name** (ownership
  lane). The verifier special-cases `memref::AllocOp`
  (`Verify/Program.cpp`) and `memref::LoadOp` (`Verify/Uses.cpp`), and
  `Role::Carried`, `takesCarried`, `storedBy` and `idr.own.adopt` and
  `give` carry values across the boundary. Owed, once one design is
  chosen: the crossings as their own ops (`idr.own.load`, `store`,
  `alloc`), made once by idr-rc and lowered to the upstream op and its
  count, or `own.give`'s result as a flow edge that makes `Carried` dead.
  Acceptance: the owned verifier holds no `memref::` case.
- **`feeds()` is a ladder of op kinds** (`lib/IR/Canon/Feeds.cpp`, control
  lane): its call, force, put-list, con, match, field and tag arms are
  `isa` tests. Owed: an interface on the consumer (`meets(OpOperand &,
  Value)`, the fold probe its default), `feeds()` the query and the call
  test. Acceptance: no per-op arm in `Feeds.cpp`; case-of-case and sink
  fixtures unchanged.
- **MoveOut classifies effects a second way** (`lib/IR/Canon/MoveOut.cpp`,
  control lane): its own `Does`, `doesOf` and `isa<ForceOp>` beside
  `idr::classify` (`lib/IR/Effects.cpp`); the two already disagree on
  `ub.unreachable`, and `idr.force` declares no valueless `MemRead`.
  Owed: one classifier with MoveOut's predicate, the force's read declared
  in ODS. Acceptance: one `Does` and one walk.
- **Resources read as effect bits by hand** (`Expect/Placement.cpp`
  `Order`, `StructureLoops/Forms.cpp` `atMostCrashes`): the reverse reading
  beside `idr::effectInstances` (`lib/IR/Func/Func.cpp`), used by both.
- **The crash-site count and the crash effect disagree** (target lane).
  `Expect/CrashSites.cpp` counts every `NoReturn` op, `idr.exit` among
  them, while `bodyEffect` counts `MayCrash`: a kept function holding
  `idr.exit` breaks `crash-sites-not-added` (*conjecture*: the cause of
  harness-cases' contify failure, `audits/bugs.md`). Owed: "may crash"
  one ODS fact both read.
- **Emitted code decodes the small word by hand** (target lane):
  `Conversion/Bigs.cpp` (`lowBit`, the shift in `LowerNatToExtent`) and
  `Conversion/Words.cpp` (`groupBase`), though `idris_rt_small_word` shows
  the runtime's own encoding can be called. Owed: `idris_rt_word_is_small`
  and `idris_rt_small_value` callable the same way, the hand decodes and
  their comments deleted.
- **`idris-mlir-tblgen` matches a record by name**
  (`getName() == "Idr_TagParameter"`; `byteCountOf` maps `Idr_AbiCount`
  defs by name): a class or a field of the record.
- **Types that could carry the fact** (owning lanes as the files say):
  `Exclusivity::targets` keyed by `Operation *` where only calls are
  stored (`Ownership.h`); `Reuses::sites` dereferencing a `find` without a
  check; Identities' parallel `arguments`, `slots` and `types` and the
  `Drop` pair; `narrow::Copy`'s hand resync (`copy.bound`, `Narrow/Lanes.cpp`);
  PassThroughMemory taking the call's next node to be its return; the
  optimizer matching inner statistics by name strings
  (`Optimize/Component.cpp`); `holdsLabels(Value)` (`lib/IR/Flow.cpp`)
  repeating `carriesLabels(Type)` (`Analysis/Labels.h`); Placement's
  `casesOf` variant beside the match interface.
- **Exclusivity is no analysis** (ownership lane): the final solve is
  handed to `createRcCommit` by constructor (`Ownership/Exclusive.cpp`),
  so nothing reads it cached and it has no timing row. Owed: the solve as
  a cached program analysis and idr-rc-commit a pass of its own reading it
  with `getCachedParentAnalysis`. 0006, 0008 and 0012 need it.
- **A refusal rule's category false of some of its sites** (arrays lane):
  `StaticArgument` is megamorphic, yet
  `tests/static-argument-stuck-implementation` refuses a choice the
  program bounds, behind a `covering` chooser; the wave's notes named
  `ValueType`, `DependentField`, `DictionaryField`, `RuntimeClosure`,
  `Match`, `Primitive` and `StringPrimitive` too (*recalled*). Owed: each
  rule split until its category is true of every site.
- **Idris side, the wave's leftovers** (arrays lane):
  - a named Emit statement with no results can still be built
    (`MkStatement` in `Emit/Operations.idr` and `SyntaxSamples.idr`), and
    four "gives no result" internal errors remain (`Operations.idr` in
    `effect`, `Emit/Tensors.idr`): a constructor that needs
    `NonEmpty o.results` makes them unwritable;
  - the translation's environment is a `List` read by position (`getAt`,
    about 11 sites in `Terms.idr`, `Cases.idr`, `Forced.idr`): a `Vect`
    indexed by Idris's `IsVar`; about 35 more position or membership
    lookups in `Translate/Types.idr` and `Growth/Sites.idr`, each its
    index or its map;
  - `TS.loops` is a `SortedMap Address Bool`, and `Template.Computing` is
    matched outside where it is built (Caps, Graph, Heads, Sites);
  - `Profile.proofOnly` asks `isErased` after its own lookup.
- **`SpecKeyAttr`'s `origin` means the owner** while `Node::origin` means
  the program's function (defunc lane): rename the key's parameter
  `owner` and its callers.
