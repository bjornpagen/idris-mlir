<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Representation, unified: a hard cutover of the C++ and the Idris

**Status:** packet, compiled 2026-10-17; the owner approved its decisions and ordered dispatch (2026-10-17, "rip it"). The owner's
directive (2026-10-17): "deeply follow this document, and heavily refactor
the codebase, both the C++ and the Idris part, and look for any bad branches
or invalid states or unnecessary casework that are caused by bad
representation", then "these should all be hard refactored in a backwards
incompatible hard cutover to unify representations". The document is the
source text of `.claude/skills/representation-first/SKILL.md`, quoted in
every dispatch.

Ten read-only surveys (2026-10-17, at 73d6dcf3 plus the uncommitted
checker) found 169 defects, each written with its evidence, counterexample,
root cause, one correction, deletion, discriminator, write set and risk:
[findings/](findings/). This packet selects one representation per root
cause, merges the 21 findings that share one, fixes every seam two lanes
share (§4), and gives each finding one owning lane (§3, `ownership.json`).
Twenty-four lanes started together on disjoint files (§6); three more,
added on 2026-10-18 (L25, legacy tests and benchmarks; L26, the fork's
`SyntaxInfo` knot; L27, `tools/self.sh`), start with L23 at their own
dispatch.

## 0. Engagement

- **Kind:** proposal (this packet). Dispatching it is the owner's word
  ("dispatch"); the coordinator then integrates and qualifies.
- **Base:** e5b05658 on `main`: the polymorphism checker (proposals/0003-self-host
  S2.2, 3fc4d2e4), its hard cleanup, and the fixes and speedups that
  landed after this packet was compiled: method markers (3e8ea8f2), one
  instance identity per type with emit's slot check (3934cc0c), the emit
  speedup that is idris-emit-19 and more (77a7192b), translate rounds
  (1d25638c), and the renumbering (e5b05658). Lanes L20, L21 and L22 open
  with what moved under them. Every anchor here names a symbol first and a
  line second, and a lane re-finds the symbol at the base.
- **Compatibility:** none (the owner's hard cutover). The textual IR, the
  bytecode, the generated Idris dialect modules, pass options, `idr-expect`
  property spellings and every internal API change wherever a finding's
  correction says so; no reader keeps an old form readable, no alias keeps
  an old name. There is no user data: fixtures are rewritten to the new
  forms by the lane that owns them, except the printed forms that change
  wave-wide (S2's default, S6's effects, S18's constants, the cell ops,
  S4's take split), which the coordinator rewrites with one script at
  integration (§8, §9 B7): lanes do not hand-edit those lines in other
  lanes' fixtures, and do edit them in their own.
- **Targets:** every first-class target (AGENTS.md). Nothing here may add
  a per-target case outside the target's entry.
- **Verification cadence** (§8): Idris lanes build and run on Chez in
  private copies, byte for byte against the base. The runtime lane (L19) is
  not compile-only (ruling A3): it builds the runtime privately with host
  clang, its compile commands taken from `build/typecheck/compile_commands.json`
  and the base's `idris_rt_ops.h` regenerated privately, and runs every
  property program and the `rc` mode; on the base this ran with 52 units and
  every program exiting 0. A definition that must match a regenerated
  declaration (S15's buffer entries, any finding that changes the ABI) is
  checked at integration against the regenerated header. C++ lanes do not
  build during the swarm (generated headers are shared state), and the
  coordinator's staged `make typecheck` after integration (ODS targets
  first, then C++; §8.2) is the C++ gate, with repairs dispatched to the
  owning lane. MLIR passes and compiled programs run only on the owner's
  build.
- **Commits:** lanes never commit. The coordinator commits once after
  qualification and pushes; the owner's build runs the fixtures marked
  `NEEDS-ACCEPTANCE`.

## 1. Invariants (what every lane keeps)

1. **One thing, one representation.** After this wave no fact in §3 is held
   twice: where a finding names two copies, one is generated from the other
   or deleted (AGENTS.md).
2. **No pass drops what Idris proved.** Quantity 1 stays a type
   (`!idr.lin<T>`, and after §4 S10, S3 and S41 the world, destinations,
   cells and closures with a linear capture by their types); erasure stays
   absence; nothing moves into a discardable attribute.
3. **Acceptance is a property of the program.** No change here refuses a
   program the base accepts, except a refusal that was a miscompile; every
   refusal keeps its category in ODS.
4. **Never miscompile silently.** A state a type cannot yet rule out is an
   `internal` error naming the site, never `Unreachable`, a sentinel or a
   default.
5. **Upstream MLIR first.** A correction that names an upstream mechanism
   (an interface, `InferTypeOpInterface`, ODS constraints and memory
   effects, properties, `RegionBranchOpInterface`, the analysis manager,
   `DataFlowSolver`, `llvm::Error`, `eraseUnreachableBlocks`) uses it rather
   than C++ of ours.

## 2. Rules (in addition to AGENTS.md)

- **The six binding rules** are quoted verbatim in every dispatch
  (`parts/rules.md`).
- **Hard cutover:** the new form replaces the old in the same change,
  everywhere in a lane's writes. A consumer outside the writes is the
  owner's lane (§3 names it; the dispatch's "Consumer adaptations" lists
  what each lane adapts) and is never bridged.
- **Brooks's limit:** each survey lists what it judged essential and kept
  (the "Judged essential" section of each [findings/](findings/) file). A
  lane does not flatten those; a case split it keeps is named as essential
  in its handoff.
- **Generated code is the coordinator's:** `compiler/src/IdrisMLIR/{Dialect,
  Syntax,Encoding}/**` are regenerated from ODS by `tools/dialects.sh
  generate typecheck` at integration. A lane that changes ODS writes no
  generated file; a lane that consumes a generated builder writes against
  the name the generator gives (§4 S0).

## 3. Findings

Each finding's full text is in [findings/](findings/), under its ID; the
dispatch of its owner quotes it verbatim. A merged finding shares its
primary's correction and owner. The owner column equals `ownership.json`.

<!-- findings-table -->
| ID | Finding | Owner | Merged into |
|---|---|---|---|
| analysis-1 | binding times hold three elements no decision reads, and `Free` is just `Fixed` for a function on no cycle | L09 |  |
| analysis-2 | the call graph's components and "same cycle" are computed five times | L09 |  |
| analysis-3 | the effects of a body are written twice, and only the verifier knows an indirect run | L03 |  |
| analysis-4 | what a value is made of is re-derived by six ladders that disagree | L04 |  |
| analysis-5 | a flow point has three key spaces and two five-arm visitors | L10 |  |
| analysis-6 | Identities reads a callee's effects three ways, and the accessor D13 named was never exported | L10 |  |
| analysis-7 | "callee final or not" travels as a null pointer through every callee hook | L11 |  |
| analysis-8 | "a natural is ≥ 0" is applied at four sites, with and without the grade | L04 |  |
| analysis-9 | the default effects have two storage forms | L03 |  |
| analysis-10 | Exclusivity's tables lose the type of a caller and say "none" twice | L10 |  |
| analysis-11 | a take's field has two coordinates in Reuses | L10 |  |
| analysis-12 | Escapes passes a one-valued `Mode` and reads a missing state as "escapes" | L09 |  |
| analysis-13 | `tail::Built = variant<ConOp, ReuseOp>` is an op interface not yet named | L02 | transforms-b-2 |
| analysis-14 | Borrows is a hand-built dependency solver where MLIR's solver is the mechanism | L10 |  |
| analysis-15 | Borrows' `Holding::Fixed` lumps three reasons | L10 |  |
| analysis-16 | the inline summary carries the decision's inputs, re-decided at every call | L09 |  |
| analysis-17 | a constant's field walk is defined in `Analysis/Labels.h`, not on `ConAttr` | L17 | ir-ops-4 |
| analysis-18 | "this block ends a tail position" is written twice | L10 |  |
| cleanup-1 | the checker's remaining duplicate readings, Bools and parallel data | L22 |  |
| conversion-1 | one runtime ABI kind for two positions, and the variant found by a search | L06 |  |
| conversion-2 | every other runtime function is typed by hand at each call, and checked after the fact | L06 |  |
| conversion-3 | a memref descriptor's free fields decided by four walks with two different tests | L07 |  |
| conversion-4 | a cell's own words are restated by two writers, and its kind and object count decoded from a packed word | L07 |  |
| conversion-5 | poison of a cell pointer is null, so Facts runs an analysis to withhold the pointer facts | L07 |  |
| conversion-6 | the components of a value and whether each is counted, as two parallel lists | L07 | ir-ops-3 |
| conversion-7 | the tail-call plan copies per-callee facts into per-caller lists, beside flags that admit invalid combinations | L08 |  |
| conversion-8 | idr-entry re-checks the lowered stage, and the root's kind is decided twice by two rules | L08 |  |
| conversion-9 | a static datum is walked twice, once to name it and once to write it | L07 |  |
| conversion-10 | a string or big literal match with no case is special-cased because the chain has no first link | L08 |  |
| conversion-11 | the crash message finds its source location by a hand walk that the report does with MLIR's | L08 |  |
| conversion-12 | the small Integer word, 2v+1, is restated at seven sites | L07 |  |
| conversion-13 | ops with no runtime form are listed by hand in four populate functions | L08 |  |
| conversion-14 | a buffer's alignment and layout are checked in two lowering patterns instead of once at the stage | L07 |  |
| conversion-15 | the lowering's own symbols share the program's namespace, and collisions are checked rather than excluded | L08 |  |
| driver-runtime-D1 | A driver failure is a print plus a sentinel, not a value that carries its class | L18 |  |
| driver-runtime-P1 | Partition keeps a symbol's role three times: `kind`, `nodeOf` and `Symbol::home` | L18 |  |
| driver-runtime-R1 | The standard streams live outside the handle table, so every file operation compares integers to find them | L19 |  |
| driver-runtime-S1 | Each tool re-implements the reserved-stack trampoline and the tool registry | L18 |  |
| driver-runtime-T1 | The generated runtime ABI has one `Kind` for operands and results, so each consumer's switch has impossible cases | L06 | conversion-1 |
| driver-runtime-U1 | The six exhaustive boxes each copy the same fixture and helpers | L18 |  |
| driver-runtime-D2 | The command line is flat globals, checked piecemeal in `Main.cpp` and read deep in the steps | L18 |  |
| driver-runtime-R2 | The crash message format is assembled at eleven sites, and two contradict it | L19 |  |
| driver-runtime-T2 | A buffer is passed to the runtime as three C values, of which the runtime reads one | L06 |  |
| driver-runtime-D3 | "Prepared or archive" is decided three times, and the CPU marks are stripped and written back | L18 |  |
| driver-runtime-R3 | The runtime's meaning of a function is documented in two or three places | L19 |  |
| driver-runtime-T3 | The generator decides an ODS type's C word, and whether it counts bytes, by matching record names in C++ tables | L06 |  |
| driver-runtime-D4 | The prepared runtime's bitcode container is a run-time option, validated by object format outside the target entry and re-read by the reader | L18 |  |
| driver-runtime-R4 | Target address-space facts sit in rt::rc and rt::start, not in the platform layer | L19 |  |
| driver-runtime-T4 | The generator returns `optional` plus an out-parameter `why`, and `enumKind` encodes three states with an empty string | L06 |  |
| driver-runtime-D5 | `ModuleKind` does not carry the module's target, so `toObjects` re-validates it and misclassifies a user's module | L18 |  |
| driver-runtime-R5 | The baseline mark is spelled ten times | L19 |  |
| driver-runtime-D6 | The process entry's name is spelled four times in C++ | L18 |  |
| driver-runtime-R6 | The one empty string is chosen at each constructor, not by the allocator | L19 |  |
| driver-runtime-R7 | The runtime's kept-string slots are made on first use, so their handles may be null everywhere | L19 |  |
| idris-emit-1 | a constructor is referenced by id, so Emit resolves it and counts its fields again | L20 |  |
| idris-emit-2 | a primitive application forgets the signature Idris gave it (arity and result type) | L20 |  |
| idris-emit-3 | whether a primitive performs IO, and which results it gives, are re-derived by hand from Idris's types | L20 |  |
| idris-emit-4 | the array language's operands are positional lists | L20 |  |
| idris-emit-5 | `Entry.rules` is a field nothing reads, a second copy of the hook's rule | L20 |  |
| idris-emit-6 | guards are found by the built op's name string and its operand positions, so the word type rides alongside | L20 |  |
| idris-emit-7 | arms Idris proved impossible travel as `Unreachable` subterms, which Emit rediscovers | L20 |  |
| idris-emit-8 | an empty file name stands for "no source" | L20 | idris-frontend-13 |
| idris-emit-9 | a data body's kind and its constructors' roles are independent fields (crosses into the C++ dialect) | L17 | ir-ods-7 |
| idris-emit-10 | multi-result naming is written three times, and callers take results by list position | L20 |  |
| idris-emit-11 | a value in scope and a value an op uses are one type | L20 |  |
| idris-emit-12 | `Scalar` admits conversions and comparisons that the frontend never makes | L20 |  |
| idris-emit-13 | Emit re-reads what it built, and searches for the root | L20 |  |
| idris-emit-14 | tensor dimensions are addressed by a `Nat` into a `List` | L20 |  |
| idris-emit-15 | the data table's layout is written by hand on both sides of the bytecode | L06 |  |
| idris-emit-16 | `MemRefT`'s dimension list admits shapes that are never made | L20 |  |
| idris-emit-17 | a let-bound value's location is patched after the fact by searching for its name | L20 |  |
| idris-emit-18 | a key's non-keying position is the sentinel string `-` | L20 |  |
| idris-emit-19 | XXH3's eight accumulators are a `List` | L20 |  |
| idris-frontend-1 | a refusal is prose from the moment it is made | L21 |  |
| idris-frontend-2 | Shapes names positions with bare Nats in three coordinate systems, and writes the witness analysis twice | L21 |  |
| idris-frontend-3 | `PrimType` is classified by three partial functions, and `primOp` is a priority cascade | L21 |  |
| idris-frontend-4 | `Prims.Ty` is flat, so integerness and width are recovered by `Maybe`s and a parallel proof family | L23 |  |
| idris-frontend-5 | `RigCount` has five classifiers and ~40 Boolean tests, and `quantityOf 0 = Many` | L22 |  |
| idris-frontend-6 | a definition's place is resolved two or three times per site, and `enter`'s `Nothing` means two things | L22 |  |
| idris-frontend-7 | `TwoLevels` spells `Prims` again as strings, so "every primitive" is a comment | L23 |  |
| idris-frontend-8 | a test case's identity is its position | L23 |  |
| idris-frontend-9 | the semantics tests are held twice, as `Sem.tests` and as 72 identical directories | L23 |  |
| idris-frontend-10 | generator facts pass to shell through labels and comments that shell re-parses | L23 |  |
| idris-frontend-11 | probe sentinels are spelled as string literals in six files, and one spelling is shared by two families | L22 |  |
| idris-frontend-12 | a dictionary field has two keys, converted by a lookup by printed symbol | L22 |  |
| idris-frontend-13 | `Loc` uses `""` for "no file" and "no module" | L20 |  |
| idris-frontend-14 | shape terms are recognised by hand three times, and `arrayShape`'s pair is never read | L21 |  |
| idris-frontend-15 | Gen and Prims have dead arms that a measure or evidence would rule out | L23 |  |
| idris-frontend-16 | Lock validates, and silently skips entries that are not objects | L23 |  |
| idris-frontend-17 | Fuzz literal pools hold source text and parse it back | L23 |  |
| idris-frontend-18 | `IndexInto Nat` points at another argument by position | L20 |  |
| ir-ods-1 | no interface for the two match ops | L01 |  |
| ir-ods-2 | the guard marks are restated by hand in C++ | L05 |  |
| ir-ods-3 | the world is a grade of a carrier, so every grade function excludes it | L04 |  |
| ir-ods-4 | MayCrash admits a crash that cannot happen and an allocation no op makes | L05 |  |
| ir-ods-5 | about twenty verifier checks are type constraints ODS can declare | L05 |  |
| ir-ods-6 | a value's components and their counted bits are two parallel walks | L07 | ir-ops-3 |
| ir-ods-7 | every constructor carries a label's fields | L17 |  |
| ir-ods-8 | every constant attribute carries a type that is always NoneType when stored | L17 |  |
| ir-ods-9 | a match's default region is known by counting | L01 |  |
| ir-ods-10 | ConsumesOnly's operand groups are a copy nothing reads | L05 |  |
| ir-ods-11 | the runtime ABI word of a type constraint is held by its name in the generator | L06 | driver-runtime-T3 |
| ir-ods-12 | the specializer's in-memory keys are dialect attributes exported to Idris | L11 |  |
| ir-ops-1 | Facts ODS declares are written as C++ hooks | L05 |  |
| ir-ops-2 | `idr.array.yield` switches on its parent's kind | L24 |  |
| ir-ops-3 | Components and their countedness are two parallel walks; a sum's words carry the tag as a coordinate offset | L07 |  |
| ir-ops-4 | A constant constructor has two storage forms, and every reader writes both | L17 |  |
| ir-ops-5 | `idr.con` and `idr.reuse` are one shape with no interface | L02 | transforms-b-2 |
| ir-ops-6 | The atom is ten `fields.empty()` tests and four token rules | L02 |  |
| ir-ops-7 | DataRemap decides what a field becomes three times, and the key's copy disagrees | L17 |  |
| ir-ops-8 | A destination of any type is expressible, and a hole at a non-box field is checked only under assertions | L02 |  |
| ir-ops-9 | Six custom directives differ only in a plain type | L03 |  |
| ir-ops-10 | "A literal of this type" is three ladders | L04 |  |
| ir-ops-11 | Every constant attribute carries a type parameter that must be `none` once stored | L17 | ir-ods-8 |
| ir-ops-12 | Facts of a boxed sum are kept per constructor cell and read through constructor 0 | L07 |  |
| ir-ops-13 | A guard's condition reads its constants by position and checks their count | L05 |  |
| ir-ops-14 | A match's default region binds nothing or the scrutinee | L01 | ir-ods-9 |
| ir-ops-15 | A signedness flag on operands that have no sign | L16 |  |
| ir-ops-16 | "Used exactly once by its nature" has two encodings | L04 |  |
| ir-verify-1 | an `idr.func` body may have several blocks, a state only inlining makes | L03 |  |
| ir-verify-2 | the two matches share one shape that no interface names | L01 | ir-ods-1 |
| ir-verify-3 | the world's quantity is said three ways, and one of them is quantity many | L04 | ir-ods-3 |
| ir-verify-4 | each guard's operand and kind are written again by hand in C++ | L05 | ir-ods-2 |
| ir-verify-5 | what each stage implies is written in five places, two of them as a two-bool struct | L03 |  |
| ir-verify-6 | the translation between `Effect` bits and MLIR's resources, and the rule for what a call may do, are written several times | L03 |  |
| ir-verify-7 | a closure or suspension that captures a linear value has a plain type, so a side rule enforces its one use | L04 |  |
| ir-verify-8 | `holdsClosure` is computed for every type and never read, while the verifier finds labels by its own type walk | L04 |  |
| ir-verify-9 | two classifiers of "what an op does", with one walk written twice and a force rule in only one | L03 |  |
| ir-verify-10 | `idr.str.show` is two ops in one, and its consumers split it back | L16 |  |
| ir-verify-11 | `ownership::readFrom` re-derives from an isa ladder what the flow edges already declare | L15 |  |
| ir-verify-12 | the owned stage's crossings into upstream's buffer ops are protocols of position and use count | L15 |  |
| ir-verify-13 | `rebuildMatch` takes the kept cases and their regions as parallel lists, with the default as one extra entry | L01 |  |
| ir-verify-14 | flow anchors hold an `mlir::Type` where they always mean a particular type, and the slot rule is written twice | L17 |  |
| ir-verify-15 | a function's effects have two spellings of "everything", which a verifier rule and a writer keep apart | L03 | analysis-9 |
| ir-verify-16 | the string patterns' left-hand sides are copied into three hand lists | L01 |  |
| ir-verify-17 | case-of-case's profit rule is a ladder over consumer kinds that restates each consumer's canonicalization | L01 |  |
| ir-verify-18 | the owned walk's view of a value is three overlapping predicates over three maps | L15 |  |
| ir-verify-19 | knot reporting keeps three parallel lists matched by position | L15 |  |
| legacy-1 | `bench/ackdyn` is an ablation twin of `bench/ack` that no suite needs | L25 |  |
| legacy-2 | nine benchmark programs are held twice, as `bench/<name>/Main.idr` and as a fixture's copy, three of them drifted apart | L25 |  |
| legacy-3 | `io/system-info` keeps a per-target table for seven systems on a tree with two targets | L25 |  |
| legacy-4 | bench/'s script and documents describe what is gone | L25 |  |
| legacy-5 | two tools live in tests/ and look like tests | L25 |  |
| legacy-6 | harness/README.md's layout omits what the tree holds | L25 |  |
| legacy-7 | tests/fuzz-two-hosts takes its expected output from the stock host at run time | L23 |  |
| legacy-8 | the 72 semantics chunk directories, as the survey measured them | L23 | idris-frontend-9 |
| legacy-9 | test helpers kept for features that are gone | L23 |  |
| legacy-10 | the libm symbol list is held five times | L23 |  |
| lists-1 | lists used for position, key, appends or membership in Core and Emit | L20 |  |
| lists-2 | lists used for position, key, appends or membership in frontend translation | L21 |  |
| lists-3 | lists used for position, key, appends or membership in frontend state and the checker | L22 |  |
| lists-4 | lists used for position, key, appends or membership in libraries and test machinery | L23 |  |
| mlir-1 | `is_signed` is a unit attribute that switches the meaning, folder, lowering and runtime function of ten ops | L16 |  |
| mlir-2 | the matches' syntax is hand C++ that copies ODS's generated property check and finds the default by position | L01 |  |
| mlir-3 | an op's flow model is verified only while the program is at stage `higher` | L17 |  |
| mlir-4 | the program's rules hang on a symbol-use hook, so no program pass is held to them | L03 |  |
| mlir-5 | `idr.take` is three operations chosen by its operand's type, declared with the cell's effects for all three | L02 |  |
| mlir-6 | the compiler registers every upstream dialect, extension and pass, so the set it needs is written nowhere | L18 |  |
| mlir-7 | every location and dictionary key reaches the C++ reader as MLIR text, which it parses again | L20 |  |
| mlir-8 | returned-arguments solves an optimistic forward dataflow by hand | L13 |  |
| mlir-9 | a match does not tell `RegionBranchOpInterface` that its default region's argument is the scrutinee | L01 |  |
| mlir-10 | lowering's phase 0 renames functions by recomputing `mangle` at each use it knows, outside a rewriter | L08 |  |
| mlir-11 | lowering patterns compute converted types through `Layouts`, around their `TypeConverter` | L07 |  |
| mlir-12 | a call cannot tell MLIR what it does, so the tree keeps a second effects API, a canonicalizer bound to a table, and its own CSE | L03 |  |
| mlir-13 | nested and inner passes get their parent's analyses as C++ constructor arguments, so they are unregistered pass wrappers | L13 |  |
| mlir-14 | pipeline steps are composed inside passes: idr-rc's five steps, idr-effects inside idr-defunctionalize, symbol-dce inside idr-optimize | L13 |  |
| mlir-15 | an element's address is computed by two formulas, ours and upstream's `getStridedElementPtr` | L07 |  |
| mlir-16 | the facts at function boundaries are written by a second walk that recounts the signature conversion | L07 |  |
| mlir-17 | narrowing runs upstream's patterns and our folders under two hand-written drivers | L12 |  |
| mlir-18 | while-do's dead sweep is upstream's `eliminateTriviallyDeadOps` | L13 |  |
| mlir-19 | rewrites to an existing value are written as patterns instead of folds | L01 |  |
| mlir-20 | Escapes keeps calls away from upstream's backward base by hand; the solver's configuration and external-call hook state its call rule | L09 |  |
| mlir-21 | Exclusivity's `Entry` analysis repeats upstream's rule for public callables | L10 |  |
| mlir-22 | failing properties and the one remark-emitting pass are checked by FileCheck on stderr, where `-verify-diagnostics` checks place and count | L14 |  |
| mlir-23 | `facts-as-marked` is `expected-remark` written as a discardable attribute on the op under test | L14 |  |
| selfhost-1 | `SyntaxInfo` reaches its own cell through a pragma's closure | L26 |  |
| selfhost-2 | `tools/self.sh` reuses stage 1's TTCs, runs the frontend and the pipeline as one, and bounds neither | L27 |  |
| transforms-a-1 | idr-expect's properties take their argument as text, and each property parses it itself | L14 |  |
| transforms-a-2 | The two match ops share no interface, so 25 sites ask `isa<MatchOp, MatchLitOp>` (crosses into IR) | L01 | ir-ods-1 |
| transforms-a-3 | A binding time has five cases, and specialization reads one bit (crosses into analysis) | L09 | analysis-1 |
| transforms-a-4 | A key hole stores its index, which is always its pre-order position, and a C++ `Pattern` mirrors the key to renumber it | L11 |  |
| transforms-a-5 | A raise key holds its consumer as printed text, which the build parses back | L11 |  |
| transforms-a-6 | A request holds its kind twice and its owner three times | L11 |  |
| transforms-a-7 | A requester's earlier keys are one flat list across owners and kinds, so every comparison re-tests both | L11 |  |
| transforms-a-8 | What a program stage implies is decided in five places, in three forms (crosses into IR, analysis and Effects) | L03 | ir-verify-5 |
| transforms-a-9 | idr-columns states which ops it converts twice | L12 |  |
| transforms-a-10 | A made function's lifecycle is spread over a null field, a claimed set, a symbol lookup and a second node (crosses into Optimize) | L11 |  |
| transforms-a-11 | A constructor's role and its payload are independent fields (crosses into IR) | L17 | ir-ods-7 |
| transforms-a-12 | The defunctionalization decision is half-built between phases, and a nested sum's failure is a flag the recursion cannot see | L12 |  |
| transforms-a-13 | The inline legality rule lives outside the inliner interface (crosses into IR) | L03 |  |
| transforms-a-14 | "Computes on wide lanes" is defined twice | L12 |  |
| transforms-a-15 | Three copies of "make the op again with new operands and types, moving its regions" | L12 |  |
| transforms-b-1 | a take's results are a function of (value type, tag), spelled five ways | L02 |  |
| transforms-b-2 | `idr.reuse` is `idr.con` with a cell, held as a second op | L02 |  |
| transforms-b-3 | an `idr.func` body admits several blocks that only an inliner transient makes | L03 | ir-verify-1 |
| transforms-b-4 | returned-arguments walks `scf` ops by kind where `RegionBranchOpInterface` names the predecessors | L13 |  |
| transforms-b-5 | idr-rc lowers linalg loops over counted elements that no pass makes | L13 |  |
| transforms-b-6 | the stage a pass runs at is prose, checked by hand in 2 passes | L13 |  |
| transforms-b-7 | grade specialization erases dead copies with its own reachability walk | L13 |  |
| transforms-b-8 | the ordered tabulation threads an optional world through seven flag tests | L13 |  |
| transforms-b-9 | the ordered tabulation tests every iteration for the first and special-cases rank 0 | L13 |  |
| transforms-b-10 | the callee-effects table is bound when the pipeline is built, so function passes go without it or rebuild it | L13 |  |
| transforms-b-11 | while-do's three scopes are a tag switched twice | L13 |  |
| transforms-b-12 | placement's `Class` conflates outcomes its consumers re-split with predicates | L13 |  |
| transforms-b-13 | fold and scan share accessors that lowering recovers with casts | L24 |  |
| transforms-b-14 | an optimizer node's lifecycle is three fields and a step kind | L11 | transforms-a-10 |
| transforms-b-15 | addition's identity lives in idr-accumulate, not in `idr.big.add` | L16 |  |
| transforms-b-16 | a terminator is rebuilt by kind to change its operands | L13 |  |
| transforms-b-17 | placement asserts a flow rule and then handles its violation | L13 |  |
<!-- /findings-table -->

## 4. Shared contracts

Each seam two lanes meet at is fixed here by name, fields and semantics;
the owner writes it, the consumers write against this text at the same
time, and nobody waits. "ODS text by L05" means the declaration lives in a
file L05 owns and L05 writes it exactly as stated; the implementation is the
named lane's. Exact ODS spelling, builder overloads and private helpers are
the owner's, within these names.

**S0. Generated names.** The Idris dialect modules name a builder after its
op's mnemonic with `.` and `_` removed and the next letter capitalised
and `Op` appended (`idr.str.show_sint` → `strShowSintOp`, as `idr.io.put_int`
is `ioPutIntOp` in `Dialect/Idr.idr` today; `idris-mlir-tblgen`'s
`camel(mnemonic) + "Op"`), as `-gen-idris-dialect` does at the base. An
operand group of arity `?` is a `Maybe Value` parameter with no default; an
attribute is a parameter like today; a property that is no attribute and has
a default (S6's `effects`) is **not** a parameter: the generator writes the
op at its default. L20 and L21 write against that rule; the coordinator
regenerates.

**S1. `idr::MatchOpInterface`** (ODS text by L05 in `IdrInterfaces.td`;
implementation and the base class by L01). Attached to `idr.match` and
`idr.match_lit` through `Idr_MatchOpBase`. Methods: `::mlir::Value
getScrutinee()`; `unsigned getNumCases()`; `::mlir::Region
&getCaseRegion(unsigned)`; `::mlir::Region &getDefaultRegion()`; `unsigned
caseOf(::mlir::Region &)` (a case region's index, asserted to be one of the
op's case regions); `std::optional<::idr::Tag> knownTag(::mlir::Region &)`
(the constructor a case region is entered at; none for the default and for
`idr.match_lit`); `::mlir::Operation *rebuild(::mlir::RewriterBase &,
::mlir::TypeRange results, ::llvm::ArrayRef<unsigned> keptCases,
::mlir::Region *defaultRegion)`. Builders (`skipDefaultBuilders = 1`):
`MatchOp(TypeRange results, Value scrutinee, ArrayRef<Tag> tags)` and
`MatchLitOp(TypeRange results, Value scrutinee, ArrayAttr cases)`, each
making an empty default and one empty region per key; a builder of a default
adds its block with `createBlock(&op.getDefaultRegion(), {},
{scrutinee.getType()}, {loc})`. Every reader of `getRegionNumber()` as a case
index goes through `caseOf` (`IdentitiesRecord.cpp:155,277,283`,
`OpsCon.cpp:284`, `Expect/Placement.cpp:63`, `Tail/WhileDo.cpp:170`), and
every reader of the default by number takes `getDefaultRegion()`
(`Asm.cpp:226`, `FlowOps.cpp:137`). The four `RegionBranchOpInterface`
members are written once in the base class. "Which region does a constant
scrutinee take" is not a second "taken region" method: it is upstream's
`RegionBranchOpInterface::getEntrySuccessorRegions` asked with the constant
operand (`ControlFlowInterfaces.td`), which the base class answers through
`getTakenRegion` (`Regions.cpp:56-82`); that helper stays private to the
base class, and its one outside caller (`Canon/MatchPatterns.cpp:104`) asks
`getEntrySuccessorRegions`. Deleted: the `MatchLike` concept,
`rebuildMatch(Operation*)` and its internal-error default, `scrutineeOf`,
every `isa<MatchOp, MatchLitOp>` pair (each becomes `isa<MatchOpInterface>`),
the explicit template instantiations. Consumers: L02, L04, L08, L10, L11,
L12, L13, L14, L15, L17, L24.

**S2. A match's regions** (L01). As `scf.index_switch`
(`SCFOps.td:IndexSwitchOp`), the default first: `(region
<default>:$defaultRegion, VariadicRegion<SizedRegion<1>>:$caseRegions)`,
because ODS refuses a variadic region that is not the last
(`mlir/lib/TableGen/Operator.cpp`: "only the last region can be
variadic"). `<default>` is `MaxSizedRegion<1>` for `idr.match` (empty when
the cases are exhaustive, as `scf.if`'s `$elseRegion` is when there is no
else; not `AnyRegion`, which admits several blocks), and `SizedRegion<1>`
for `idr.match_lit`, which has no exhaustive form. A non-empty default
region's block has exactly one argument, the scrutinee at its type: never
zero (P2), printed `default(%d: T) { ... }`. That argument is a fresh
binding whose predecessor the match does not declare: `getEntrySuccessorOperands`
of the default region and `getSuccessorInputs` say nothing, as at the base
(`Regions.cpp:66-68,85-87`), and S11 reads the argument as `Same` by our own
rule. mlir-9's edge is withdrawn (§9 B12): the matches register upstream's
region-branch canonicalizations (`OpsMatch.cpp:192,200`), which, given the
edge, replace the argument by the scrutinee
(`ControlFlowInterfaces.cpp:718-760`), a second use of a linear value the
match consumed, or erase it together with the scrutinee operand (`:859-990`).
Case `i` is `caseRegions[i]` (region `i + 1`), the default region 0; nothing
counts regions to find the default, and a case index is S1's `caseOf`. Every
builder of a match (L12, L13, L08) and the Idris emitter (L20) write the
default in its own place; a walk that reads a region's block skips an empty
one.

**S3. Cells are explicit after counting: allocation is split from
construction** (ruling A4, the owner's MLIR-native pick: MLIR separates
values from memory; ODS text by L02 in `IdrOwnershipOps.td` for the cell
type and ops, by L03 in `IdrOps.td` for `idr.con`'s change; semantics by
L02; the rewrites by L13; the lowering by L07).

1. *Value stage* (before idr-rc): `idr.con` builds a constructor value, as at
   the base, less `UnitAttr:$stack`, `$holes` and `$dests`, which are
   deleted: `(ins Idr_TagAttr:$tag, Variadic<AnyType>:$fields)`, builder
   `(type, tag, fields)`. It has no token and no cell; it stays foldable. A
   hole is a field of a cell written later, memory, which only idr-trmc
   makes (`Tail/Trmc.cpp:87`), after idr-rc (`Pipeline.cpp:99,102`), when
   every con that builds a cell is one; the frontend writes none. So holes
   and their destinations live on `idr.cell.init` alone (item 5), and
   `idr.con`'s builders, accessors (`getField`/`getDest`) and syntax lose
   them. Its effects are otherwise as at the base.
2. *idr-rc's cells step* (L13, `idr.func(idr-rc-cells)`, the first of S27's
   idr-rc steps, at stage `first`) rewrites every `idr.con` for which S36's
   `buildsCell` holds into one `idr.cell.new` and one `idr.cell.init`. The
   cell ops are legal from this step on, at stage `first`. After idr-rc the
   owned verifier (L15) refuses such an `idr.con`; an unboxed sum's con and
   an atom's con stay `idr.con`.
3. *The cell type* (L02, a `TypeDef` in `IdrOwnershipOps.td`):
   `!idr.cell<box type, tag>`, printed `!idr.cell<!idr.box<!L>, @Cons>`, the
   uninitialised memory of one cell for that constructor. The parameters are
   `(::idr::BoxType box, ::idr::Tag tag)`, as everywhere else in the dialect
   a data type is a named type (`IdrTypes.td:Idr_DataType`, a `MutableType`)
   and a constructor is its tag in it, printed by name (`custom<CtorRef>`,
   as `idr.con` prints its tag). It has no grade; it is linear by type
   (`isLinearByType()` true, S10), so a cell is used exactly once, by
   `idr.cell.init`; it is not counted (`holdsReferences` and `isCounted`
   false); its verifier refuses a tag for which `buildsCell` fails, so an
   atom has no cell.
4. *Cell producers*, one op per source, each with its effect declared in ODS
   on the op (no flag decides an effect); the producer writes the cell's
   header:
   - `idr.cell.new`: a fresh heap cell
     (`Res<..., [MemAlloc<DefaultResource, 0, FullEffect>]>`), as
     `memref.alloc` (`MemRefOps.td:AllocLikeOp`);
   - `idr.cell.stack`: a cell in the frame
     (`MemAlloc<AutomaticAllocationScopeResource, 0, FullEffect>`), as
     `memref.alloca`, whose verifier requires an ancestor with
     `AutomaticAllocationScope`, which `idr.func` is. idr-rc's stack step
     (`idr-rc-stack`, L13, S27) replaces an `idr.cell.new` by it where L09's
     escape analysis proves the cell stays in its frame, before reuse and
     exclusivity are decided, so Reuses and Exclusivity see stack cells and
     the base's "stack beats reuse" priority holds. That is upstream's
     order: `promote-buffers-to-stack` turns `memref.alloc` into
     `memref.alloca` after bufferization
     (`Bufferization/Transforms/Passes.td:PromoteBuffersToStackPass`). The
     separate idr-stack pass that ran before idr-rc (`Pipeline.cpp:94`), on
     the value stage where no cell exists, is deleted. The escape analysis
     (`Analysis/Escapes.cpp`, already upstream's
     `SparseBackwardDataFlowAnalysis`) reads uses by their flow edges, which
     model references, not addresses: `idr.share` releases its operand and
     its result is "a value no flow explains" (`FlowOps.cpp:213-215`), though
     it is the same cell, and `idr.cell.init`'s result is its cell. Escapes
     follows the address itself, through `idr.share` and from a cell to its
     init's result (S11's `sourceOf` never looks through a share), or a cell
     that escapes through a share would go on the stack: a use after return.
     That is L09's obligation, with a stack fixture whose cell escapes
     through an `idr.share`;
   - `idr.cell.recycle %token`: the token's cell, or a fresh one when the
     token is null (the take of a shared box), with exactly
     `memref.realloc`'s effects (`MemRefOps.td:MemRef_ReallocOp`):
     `MemFreeAt<0, FullEffect>` on the token, whose cell is given up, and
     `MemAlloc<DefaultResource, 1, FullEffect>` on the result, which may be
     the same memory. Reuse (L13, in idr-rc's place step, reading the cached `Reuses`) replaces an
     `idr.cell.new` by it. Which cell may be recycled for which constructor
     is the Reuses analysis's decision (L10), as at the base; the op does
     not re-check it. Reuses' candidates are `idr.cell.new` ops, so a stack
     cell is never recycled and Reuses' stack tests (`Reuses.cpp:174,209`)
     go.

   Reuse and stack placement each replace one producer op by another, so the
   `idr.cell.init` that names the cell never changes: Reuse.cpp's site maps
   and Trmc's second rebuild have nothing left to track.
5. `idr.cell.init %cell (fields..., holes)`, with `$dests` as `idr.con` has
   them at the base: writes the fields of the cell's constructor into the
   cell (`MemWrite` on the cell) and consumes it; holes and destinations
   live here alone, `holes` an `Idr_HolePositions` (S17). Its fields are
   checked against the constructor by one declared constraint
   (`detail::fillsCell`, L02's S28 hunk), not a hand verifier. Its results
   are a function of the cell's type and `holes`, so it implements
   `InferTypeOpInterface`: the box at the plain grade, then
   `!idr.dest<field>` per hole. The result is not owned at creation: the
   cells step runs at stage `first`, where an owned value is refused
   (`Verify/Program.cpp:230`), and idr-rc's grades step grades it later;
   `isCompatibleReturnTypes` admits the box at the grades the later steps
   write (owned, and excl from the commit). The format prints the result
   type only when it is not the inferred one, so an owned or excl box
   round-trips; the destinations come from a directive over
   `CellInitOp::destTypes` (L03's `custom<CellDests>`): one source. The
   base's hand inference of the same types in `parseDests` (`Ops.cpp`), in
   `ConOp::build` and `ReuseOp::build`, and `verifyHoles` are deleted.
6. *Lowering* (L07): `idr.cell.new` is the runtime's allocation,
   `idr.cell.stack` an alloca, `idr.cell.recycle` the token-or-allocate branch
   (read from the base's `LowerReuse`,
   `git show HEAD:foreign/idr/lib/Conversion/Counting.cpp`), each storing
   the header; `idr.cell.init` stores the fields; `LowerCon` keeps unboxed
   sums and atoms. L08 deletes `LowerReuse`. `!idr.cell<...>` is one pointer component in S20's
   walk, so the lowering's `TypeConverter` (fed by `Layouts::components`,
   `Lower.cpp:91-97`) converts it and each cell op is a plain
   `OpConversionPattern`; `idr.cell.stack`'s slot is placed at its
   `AutomaticAllocationScope`'s entry, as a stack cell is today
   (`Cells.cpp:42-47`).
7. *Flow* (L17, `lib/IR/FlowOps.cpp`): edges for the four new ops (a recycle
   consumes its token; an init moves its fields into the cell and consumes
   the cell); `ReuseOp`'s edges are deleted.
8. *Deleted:* `ReuseOp`, `idr.con`'s `stack` attribute and every test of it,
   `idr.con`'s `holes`, `$dests`, `custom<Dests>` and `getDest`, the
   holes tests of `Specialize/Patterns.cpp:37,43`,
   `tail::Built` and its visits, `isa<ConOp, ReuseOp>` pairs, Reuse.cpp's two
   maps (`now`, `boxOf`, `pointOf`), Trmc's second `rebuilt`, `LowerReuse`,
   the idr-stack pass. ir-ops-5's two-op interface is not built: one op
   builds a cell's contents and each source of a cell is its own op.

Consumers: L03 (`Verify/Program.cpp`; `Ops.cpp`'s `Fields`, `CellResult`
and `CellDests` directives), L07, L08, L09 (Escapes over the owned ops,
through `idr.share`), L10 (Reuses' candidates are `idr.cell.new` ops; its
stack tests go), L11 (`Specialize/Patterns.cpp`), L12 (`Demand.cpp`), L13
(idr-rc's steps and their place in `Pipeline.cpp`, Trmc), L14 (properties
that count reuse and stack placement), L15 (the owned verifier), L17
(`FlowOps.cpp`), L20 (`conOp` loses `stack` and `holes`; `SyntaxSamples.idr`
samples the cell type and ops).

**S4. Taking a value apart: `idr.take` and `idr.unpack`, and atoms** (L02,
ruling A6 (mlir-5); `DataType::isAtom` by L04). The three operand kinds of
the base's one `idr.take` (a cell, an unboxed sum, an atom) are two
meanings, each its own op with its own declared effects, chosen by S36's
`buildsCell(type, tag)`, the one place they meet (essential: a cell or
none). `idr.take %box @C -> (token, fields...)` is the take of a cell (a box
whose constructor is not an atom): `(outs Idr_OwnedToken:$token,
Variadic<AnyType>:$fields)`, the token always there and no segment sizes,
`MemRead, MemWrite, MemFree` on the box as at the base. `idr.unpack %v @C ->
(fields...)` is the take of a value with no cell of its own (an unboxed
sum's slots; an atom, no results): `Idr_ConsumesOnly`, so its consumption
is declared and an atom's unpack, which has no result, is never erased as
dead; no effect on a cell. Each implements `InferTypeOpInterface`, each
field at `fieldType(value, field)`, owned where it holds references, and
`isCompatibleReturnTypes` admits the excl grade the commit writes later;
each builder is `(value, tag)`, and each refuses the other's operand
(`idr.take` of an unboxed sum or an atom does not verify).
`::idr::DataType::isAtom(::idr::Tag) const` (L04, `IdrTypes.td`/`Types.cpp`):
no fields and not a memo sum's state. A nullary boxed `idr.con` lowers to the
static atom cell (L07), so no heap cell is made that a take would not free.
Lowering: `LowerTake` keeps the cell's body (L08), `LowerUnpack` the
projection (L07). Deleted: the hand `getToken`/`getFields` and their
`drop_front`, `taken`, `movedField`, the three hand result lists, the
`Optional` token and `AttrSizedResultSegments`, every other spelling of
token presence (ten sites: each is the op it is), `LowerTake`'s two type
branches, the divergent box tests in Stack, Reshape and Reuses. Consumers:
L03, L07, L08, L10, L12, L13, L14, L15, L17 (`FlowOps.cpp`: unpack's
edges), L20 (`SyntaxSamples.idr`: `takeOp`, `unpackOp`).

**S5. One block per function** (L03). `idr.func`'s body is
`SizedRegion<1>`. The one producer of a second block is `mlir::inlineCall`
taking in a callee that ends in `ub.unreachable` (upstream/07 makes the
inliner keep that terminator and split the caller's block, leaving the rest
of the caller as an unreachable block); the two sites that call it are
`inlining::inlineCalls` and `Optimize/Contify.cpp`, both L11's. Each calls
upstream's `eraseUnreachableBlocks(rewriter, fn.getBody())` (as
`Conversion/TailCalls.cpp:106` does) **once, after its whole loop**, not
after each inline and not inside the inliner interface: `inlineCalls` holds
the `CallOp`s it listed before the loop and `Contify` holds `SymbolUserMap`
users from before its sweep, and some of those calls sit in the block that
dies, so an erase between two inlines leaves them dangling; and inside
`processInlinedBlocks`/`handleTerminator` the new blocks are not yet joined
to the caller's entry (`inlineRegionImpl` joins them after those hooks), so
`eraseUnreachableBlocks` there would erase all of them. L03 deletes the
interface's multi-block `handleTerminator(Operation *, Block *)` (a callee of
one block ending in `idr.return` takes the fast path; one ending in
`ub.unreachable` never reaches our hook), `isExternal`'s body test and the
`FuncOp::verify` body check (ruling A2). Every multi-block path in a function
body is deleted by its owner: L11 (Inline, Contify, Specialize; PureCalls
goes whole under S6), L13 (Reshape, idr-accumulate's refusals), L09
(EscapesCycles), L10 (the multi-block loops of `Borrows.cpp`, `Reuses.cpp`,
`ExclusivityAnalyses.cpp`, `LabelSites.cpp`), L12, L01
(`Canon/MatchPatterns.cpp`'s function-parent case).

**S6. Effects are one property, on a function and on a call** (L03;
rulings A5 and, open, D2). `idr.func` and `idr.call` each hold
`DefaultValuedProp<NamedEnumProp<Idr_Effect, "effects">,
"::idr::anyEffect">:$effects`; there is no absent form. `EnumProp` prints
and parses itself: `NamedEnumProp` writes `effects<io, crash>` through the
`FieldParser<::idr::Effect>` and `operator<<` generated for the bit enum
(`EnumAttr.td:NamedEnumProp`), so `Idr_EffectAttr` (`IdrAttrs.td`) is not
kept as the property's text form: it has no reader and L17 deletes it;
`Idr_Effect` stays. Printed forms, elided at `anyEffect`: `idr.func
effects<io> @f(...)` (L03's hand parser reads it before the symbol and its
printer writes it before `printFunctionOp`, since a property is not in
`op->getAttrs()`), and `idr.call`'s format `($effects^)?` after its
arguments. A call holds its own effects as `llvm.call` holds
`memory_effects` (mlir-12): `CallOp::getEffects` is S7's table over the
property, then `consumedEffects`, then an allocation on each linear result
(so CSE never merges two calls that each give a fresh linear value, while
`wouldOpBeTriviallyDead` still erases an unused one); `CallOp::build(FuncOp,
...)` copies the callee's effects; `verifySymbolUses` checks that a call's
effects contain its callee's, naming the call, as it checks the types.
The one writer is `void idr::writeEffects(FuncOp fn, Effect effects, const
mlir::SymbolUserMap &users)` (`Func.h`): it sets `fn`'s property and every
call's, and L09's solve and L11's Waves call it where no worker holds the
callers. What survives of the effects API takes no table (`Flow.h`, L17,
from L03's text): `bool onlyAllocates(mlir::Operation *op)` and `bool
performsIO(mlir::Operation *op)`, both reading MLIR's effects (a call's from
its property); `ownEffects` is deleted with the table, since MLIR's
`MemoryEffectOpInterface` answers what it answered; `consumes` keeps its
signature mode (judged essential) over a `const mlir::SymbolTable *` (L03's
S28 hunk). Then upstream does the work: CSE, the greedy driver's dead-op
erase, and canonicalization as upstream's `createCanonicalizerPass` with
region simplification disabled. Deleted, every reference (ruling A5, a hard
cutover): the second effects API, `CalleeEffects` (`Flow.h`) and every
table parameter and lookup, `effectsOf(CallOp, ...)`, `calleeEffect` and the
`erase_if` (`Effects.cpp`), `CalleePattern`, `withCallees`, `bindCallees`
(`Canon.h`, `Canon/Callees.cpp`), the canonicalizer wrapper bound to a table
(`Transforms/Canonicalize`), our hand CSE `Optimize/PureCalls.cpp` with its
`InnerPasses.td` entry and statistics, StructureLoops' table and
transforms-b-10's helper; and for the function, the verifier rule refusing
an explicit default, `removeEffectsAttr`, the presence tests, `setEntry`'s
default branch. This reverses 0002's D13 (§9). Consumers: L01 (`Canon/**`,
`Canonicalize/**`), L09 (the Effects solve), L10 (Identities reads a call's
property), L11 (Raise, Specialization, Waves, Optimize, PureCalls), L13 (Rc,
Place, Placement, Reshape, StructureLoops, `Pipeline.cpp`, `InnerPasses.td`),
L14 (Contracts, Expect), L17 (`IdrAttrs.td`, `Flow.h`), L20
(`SyntaxSamples.idr` loses its two `EffectAttr` samples; its
`dialect-syntax/expected`); the coordinator (`IdrDialect.h`; the fixture
script rewrites `effects = #idr.effects<X>` as `effects<X>`, before an
`idr.func`'s symbol and after an `idr.call`'s arguments). The generated
builders leave the property out (S0), so the frontend writes no effect.
Risk and escalation: §9, D2.

**S7. Effects of a body, once** (L03, `Func.h`/`lib/IR/Func`).
`::idr::Effect bodyEffect(FuncOp)` (it reads `total` and the signature)
counts an indirect run (apply, force: any op with S8) as `anyEffect`;
`::idr::Effect componentEffects(::llvm::ArrayRef<FuncOp>, const
::mlir::SymbolTable &)` moves beside it from `lib/Analysis/Effects.cpp`. One
table maps `Effect` bits to MLIR resources and back (ir-verify-6), and a
call's effects come from it over the call's own property (S6), so a call to
a function whose only effect is crash keeps the IO write an inline
`idr.crash` keeps. The calls' effects follow ruling A5: the effects pass
writes each call's (S6's `writeEffects`), and the export of
`effectsOf(CallOp, const CalleeEffects &)` is withdrawn. The verifier's own
walk is deleted; it checks that each function's effects contain
`bodyEffect(fn)` and its calls' effects, which S6's containment rule ties to
the callees, with no symbol lookup. Consumers: L09, L10 (Identities), L11
(Component, Transforms/Effects).

**S8. `idr::RunsLabelsOpInterface`** (ODS text by L05; attached to
`idr.apply` and `idr.force` by L24). One method, `::mlir::Value
getLabelCarrier()`. Read by `Labels::runs` (L10), by `observableRuns` (L09,
`Effects.cpp:158`) and by S7 (L03); the three hand lists of "runs labels"
are deleted. Consumers: L12 (`Defunctionalize/Pass.cpp` calls
`observableRuns`).

**S9. What a stage implies, once** (L03, `Func.h`). `struct StageFacts {
bool defunctionalized; bool owned; ... }` is replaced by one function
`::idr::StageFacts stageFacts(::idr::Stage)` over the stage enum, the only
place a stage's implications are written; its fields are those the five
current copies read (the lane enumerates them from ir-verify-5's evidence).
Consumers: L09, L10, L11, L12 (`Narrow/Facts.cpp`), L13, L15, L17
(`Flow.cpp:288`).

**S10. The world's own type, linear by type** (L04). `!idr.world` is a type
of its own (`Idr_WorldType` as a `TypeDef`, no grade), not a grade of a
carrier. `ValueFactsTypeInterface` (ODS text by L05) gains `bool
isLinearByType()`, with no default (every implementation states it): true
for `!idr.world`, `!idr.dest<T>` and S3's `!idr.cell<...>`, false otherwise;
every "used exactly once by its nature" test reads it, and the linearity
verifier counts a world used twice as an error. `holdsClosure` is deleted
(never read; ir-verify-8): L05 deletes it from the interface in
`IdrInterfaces.td` in the same change that adds `isLinearByType`, and L04
deletes its implementations (`ValueFacts.cpp`), `Grades.h`'s declaration
and, through its S28 hunk, `IdrDialect.h`'s `Held::Closure`.
`!idr.world_carrier` is deleted. The TableGen def keeps its name
`Idr_WorldType` (as a `TypeDef` now, mnemonic `world`), so every operand
written `Idr_WorldType` in L16's and L24's `.td` files stays as it is, and
`idr::isWorld(Type)` and `idr::world(MLIRContext *)` stay as names, now
`isa<WorldType>` and `WorldType::get`: a consumer's `isWorld` arm needs no
edit unless it names `QType` around a world, and the generated getter of a
world operand is `TypedValue<WorldType>`. Consumers: L24 (IO and platform
ops' world operands, `idr.tabulate_io`), L08 (Entry's root), L13 (the
ordered tabulation's world, transforms-b-8), L15, L20 (Emit's world builder,
`Emit/Index.idr`), and the files that read `isWorld`/`holdsWorld` today to
check they do not match the old wrapper: L01 (`Canon/MoveOut.cpp`), L03
(`Func/Func.cpp`, `Verify/Program.cpp:58`), L07 (`Layout/Components.cpp`,
`StaticNames.cpp`, `StaticData.cpp`), L10 (`Identities.cpp`), L11
(`Specialize/Keys.cpp`, `Consumer.cpp`), L14 (`Contracts.cpp`), L17
(`Constants.cpp`), L20 (`SyntaxSamples.idr:53`,
`tests/dialect-syntax/expected`), L03 (`plainReference` admits
`!idr.cell`). The world's bytecode record is S28's.

**S11. A value's structural source** (L04, `Grades.h`; the trait's ODS text
by L05 in `IdrBase.td`). `::idr::Source sourceOf(::mlir::Value)` returns
`std::variant<Made, Same, Field>`: `Same{Value}` for the result of an op
with the trait `Idr_SameValue` (operand 0) and for a default region's
argument (S2, by our own rule: the match declares no predecessor for it);
`Field{Value scrutinee, Tag, unsigned index}` for `idr.field`, a memo part
included, and a case region's argument; `Made` otherwise. With S1's
`knownTag`. `Idr_SameValue` (`def Idr_SameValue : NativeOpTrait<"SameValue">
{ let cppNamespace = "::idr"; }`, its C++ class an empty `TraitBase` in
L04's S28 hunk) marks a grade op whose result is its operand's value, its
identity and exclusivity kept; L02 attaches it to `idr.borrow`,
`idr.lin.enter` and `idr.lin.use`. `idr.share` lacks it: a share carries its
operand (`ResultCarriesOperand`) but forgets exclusivity, so following it
would prove a shared cell exclusive (§7); the trait states this, so
`sourceOf` tests no op. Every ladder that re-derives the source keeps only
its own extras; Exclusivity keeps its own edge search. Consumers: L02, L09
(BindingTimes, which now looks through grade ops), L10 (IdentitiesRecord,
Tail), L15 (Uses: `readFrom` no longer calls the scrutinee a field of
itself).

**S12. The range a type proves** (L04, `IR/Ranges.h`).
`::mlir::IntegerValueRange idr::ranges::ofType(::mlir::Type)`, ignoring the
grade. Consumers: L10 (`Analysis/Ranges.cpp` seeds with it), L16
(`OpsBigs`, `OpsScalars` intersect with it), L12 (`Narrow/Facts.cpp`).

**S13. `idr::CallCycles`** (L09, `Analysis/CallCycles.h`). An analysis the
analysis manager caches, built from upstream's call graph as upstream's
inliner walks it: its constructor `(Operation *, AnalysisManager &am)` takes
the cached `am.getAnalysis<mlir::CallGraph>()` and iterates
`llvm::scc_begin(&graph)` (`mlir/lib/Transforms/Utils/Inliner.cpp`;
`GraphTraits<const mlir::CallGraph *>` in
`mlir/include/mlir/Analysis/CallGraph.h`), skipping external nodes, rather
than re-indexing the graph for `idr::components`; the pinned graph sees
`idr.func` (`FunctionOpInterface` brings `CallableOpInterface`) and
`idr.call` (`CallOpInterface`). A one-function component calls itself when
`scc_iterator::hasCycle()`. `isInvalidated` keeps it while both it and
`CallGraph` are preserved. Keyed by the callable `Operation *`, with
`using Component = llvm::SmallVector<Operation *, 1>`:
`ArrayRef<Component> components() const` (callees first), `unsigned
componentOf(Operation *) const`, `bool together(Operation *, Operation *)
const`, `bool callsItself(Operation *) const`. Deleted: the five other walks
(Effects' `callGraphComponents`, EscapesCycles' map, Borrows' `cycleOf`,
Contify's `componentsOf`, the direct `scc_begin` loops in Returned,
TailCallPlan, ReadySet and Report). Consumers: L10, L11, L13, L08.

**S14. Binding time is two** (L09, renamed `Analysis/BindingTimes.h`).
`enum class BindingTime { Fixed, Varies }`, join is max;
`bindingTimesOf(FuncOp, ArrayRef<FuncOp> component)`. L09 also deletes the
`BindingTimes` class and Constants' dead `direct` arm. A `SpecKeyAttr` the
specializer writes is unchanged except where S11 makes binding times look
through grade ops: there keys may change, and the lane names the change.
Consumers: L11.

**S15. The runtime ABI, typed once** (L06). The generated table stays in
`idr::runtime`: two enums, `idr::runtime::OperandKind` and
`idr::runtime::ResultKind`; "does not return" is a `ResultKind` case, not a
flag. No selector picks a runtime variant by operand kinds: mlir-1 gives
each op its own runtime function. Every runtime function the lowering calls
(the 19 named by string today) is declared in TableGen and typed by the
generated table: an op's through its `Idr_Runtime` mark, and the 14 non-op
functions (the cell, array, count, string-building, crash and start entries)
as records in L06's new `IdrRuntime.td`, each the base `idris_rt.h`
prototype exactly, from which `idris_rt_ops.h` declares them, so L19 deletes
their hand prototypes from `idris_rt.h`. Each call is an `LLVM::CallOp`
built through L06's helpers (`Runtime::call(mlir::OpBuilder &,
mlir::Location, const idr::runtime::Function &, mlir::ValueRange)`, the
generated `helper::<name>` constants and `runtimeDeclaration`) with
`llvm.call`'s typed builder, so `LLVM::CallOp::verifySymbolUses` checks each
call against the one merged declaration; the `mistyped` flag, the string
`call` and their internal errors are deleted. `idr.nat.to_extent` keeps its
lowering pattern and its located crash: it needs two runtime functions, so
it carries no single-function `Idr_Runtime` mark. `Runtime.h` drops the
`Tag` parameter of `allocate`, `storeHeader` and `storeCellWords`. A buffer crosses the
ABI as the one value the runtime reads (driver-runtime-T2), and the runtime's
signatures (L19) change with it. Exactly: every `Buffer` operand is one
`idris_rt_array *` parameter at the operand's position, and the function's
other parameters are as the base's `idris_rt_ops.h` declares them (the
pointer-to-first-byte and size parameters it adds for a buffer go); L19
defines the runtime buffer entries to match and adds the inline `char
*idris_rt_array_bytes(idris_rt_array *cell)` to `runtime/idris_rt.h`, which is
L19's alone (R1, R2, R3, R5 and R6 edit it too; L06 and L07 write nothing
there and take their names from this text). conversion-12's functions, also
L19's, are `idris_rt_big idris_rt_small_word(int64_t value)`, `bool
idris_rt_word_is_small(idris_rt_big word)` and `int64_t
idris_rt_small_value(idris_rt_big word)`, the types of `runtime/Big/Big.h`'s
`small`, `isSmall` and its value read. Consumers: L05 (`Fold.h`), L07, L08,
L16 (`BigSmallOp`'s mark), L18 (the boxes), L19.

**S16. Guards declared once** (marks by L05 in `IdrBase.td`, the trait in
`IdrInterfaces.td` and the C++ shapes in L05's S28 hunk; the generator
backend by L06). Each guard's operand and check kind are read from its
`Idr_Guarded` mark (S29(a)), and the check kind is an enum case, not a
string. The shape is a generated per-op specialization (ir-ods-2's form):
`template <typename GuardOp, unsigned... Operands> struct Guard {};` (a guard
op and the op's operand indices it reads, the guarded one first) and
`template <typename Op> struct Guarded;`; L06's `-gen-guards` writes
`IdrGuards.inc`, included from `IdrDialect.h` right after the op classes,
with one `template <> struct Guarded<XOp> { using Guards =
std::tuple<Guard<CheckYOp, i, j>...>; };` per op that lists `Idr_GuardedOp`,
one `Guard` per mark in ODS order (on such an op a mark that names a byte
count or a variadic group is a TableGen error; the IO buffer ops and array
accesses do not list the trait and stay Idris-only). The trait, `def
Idr_GuardedOp : NativeOpTrait<"GuardedOp"> { let cppNamespace = "::idr"; }`,
supplies as `AlwaysSpeculatableImplTrait` supplies `getSpeculatability`:
`template <typename Adaptor> static bool guardHolds(Adaptor adaptor)` (every
guard's `holds` on the adaptor's constants at its indices) and
`mlir::Speculation::Speculatability getSpeculatability()` (speculatable when
every guard is passed), both expanding `Guarded<ConcreteType>::Guards` at
compile time: no `switch` and no table keyed by `Operation *`, which would
redo by hand the per-op dispatch MLIR gives a trait. A folder writes `if
(!guardHolds(adaptor)) return {};`; an op that speculates lists
`ConditionallySpeculatable` beside the trait and writes no body. The
`GuardOp` concept and the run-time `guardedSpeculatability` go. The five
`getSpeculatability` bodies and the folder preconditions that restate the
marks (seven, and `Ops.cpp:264`'s) are deleted by their owners (L16, L24,
L05, L03). The Idris side's guards by op name string (idris-emit-6) read the
generated table (L20).

**S17. Facts ODS can declare** (shared constraint definitions by L05 in
`IdrBase.td`, except where their base def lives later in the include order:
`Idr_Rank1ArrayValue` and `Idr_ArrayValue` are defined in `IdrBigOps.td`,
which includes `IdrBase.td`, so `Idr_ByteBuffer` (a `Idr_Rank1ArrayValue` of
`i8`) is defined by L16 in `IdrBigOps.td` right after them, and L24's
`IdrIOOps.td` uses it from there; TableGen cannot read `.predicate` of a def
that comes later). L05 defines the constraints the hand checks become
(strictly sorted and non-negative dense arrays through upstream's
`DenseArrayStrictlySorted`/`DenseArrayNonNegative`, and the others ir-ods-5
lists: `Idr_BaseListOf<list<Type> elements>` and `Idr_Capture`, whose names
are these, and `Idr_HolePositions` for `idr.cell.init`'s `holes`, L02's)
and the declarative memory effects the eleven
hand `getEffects` bodies become (ir-ops-1). Each op family's owner converts
its own ops and deletes its hand `verify`/`getEffects` bodies: L01, L02,
L03, L16, L17, L24. ir-ods-5's evidence lists each op.

**S18. One constant constructor form** (L17). `#idr.con` has one form: a
plain constructor is a run of one cell, and the `tail` parameter is
deleted; `ConAttr::walkFields(llvm::function_ref<void(Attribute,
unsigned)>)` walks a constant's fields. A constant attribute carries no type
parameter that must be `none` once stored (ir-ods-8). Consumers: L10
(Labels, LabelSites, IdentitiesRecord), L12 (Defunctionalize/Declare), L07
(StaticData), L08, L11, L16, L20.

**S19. A data body is one variant per kind** (L17; the body by L04). A
constructor's role carries its payload: L17's S28 hunk replaces
`IdrDialect.h`'s `struct Ctor` by `{ mlir::StringAttr name;
llvm::ArrayRef<mlir::Type> fields; Role role; }`, `Role` a `std::variant` of
one struct per `CtorRole` case in its order (`role::Label` holding `fn`, a
`FlatSymbolRefAttr`, and `byName`), with `kindOf(const Role &)` giving the
case; a reader asks `std::get_if<role::Label>` for the payload. So a body's
kind and its constructors' roles are one value, and `verifyBody`'s table of
legal pairs (`KindRule`) is deleted. Deleting it needs the body as a
variant: L04 writes `Body` as one alternative per kind in `IdrTypes.td`
(`Types.cpp`), and `DataType::define`'s callback returns `FailureOr<Body>`
(L04's). The Idris side's names for the roles are L20's. Consumers: L01,
L04, L06, L07, L11, L12 (Defunctionalize), L13, L14, L16, L20 (the data
table writer), L22.

**S20. One component walk** (L07, `Layout.h`). `struct Component {
::mlir::Type type; bool counted; }` and one walk producing
`llvm::SmallVector<Component>`; a sum's tag is an ordinary word of the
list, not a coordinate offset. `componentsOf`/`countedOf` are deleted.
Consumers: L03 (`Program.cpp:130`), L06 (`RuntimeCalls.cpp:130`), L08, L10
(`Reuses.cpp:188,210`), L13.

**S21. `idr.str.show` is one op per meaning** (L16): `idr.str.show_sint`,
`idr.str.show_uint` (mlir-1 splits the integer one by signedness) and
`idr.str.show_double`. Consumers: L01 (`Canonicalize.td`, `Feeds.cpp`), L05
(`Crashes.cpp:43`), L06 (runtime table), L20 (the registry's primitive to
op mapping, S0), and each fixture's owning lane for its spelling.

**S22. Keys off the Idris side, uniqued by MLIR** (L11). The specializer's
keys and raise keys stay attributes, `KeyHoleAttr`, `KeyConAttr`,
`SpecKeyAttr` and `KeyRaiseAttr` in `IdrAttrs.td` (L17), because their
uniquing is what the specializer's memo tables rely on: `Order::Embeddings`
is `DenseMap<pair<Attribute, Attribute>, bool>` and `Order::sizes`
`DenseMap<Attribute, APInt>` (`Transforms/Specialize.h:291,296`), keyed by
attribute identity, so a key made of C++ values would need its own
hashing, equality and interning, a second `StorageUniquer`
(`mlir/include/mlir/Support/StorageUniquer.h`), and its renumbering
`AttrTypeReplacer` already does
(`mlir/include/mlir/IR/AttrTypeSubElements.h:AttrTypeReplacer`). No op holds
one, so none is exported: `Idr_KeyAttr` carries `bit idris = 0`, which the
generator reads (ir-ods-12's correction), and no Idris syntax is written for
them. A hole has no index (it is its pre-order position: `#idr.key_hole`
has no parameter). A raise key holds its consumer by reference to the
uniqued form, never as printed text parsed back: `#idr.key_raise`'s form
parameter is a uniqued `StringAttr` digest of the consumer, which names its
entry in the run's table of forms (`DenseMap<StringAttr,
OwningOpRef<idr::FuncOp>>`). transforms-a-6's rename of the keys' `origin`
parameter to `owner` is in L17's `IdrAttrs.td`. Consumers: L17 (`bit idris
= 0`, the hole's parameter, the raise key's form, `owner`), L06 (the
generator skips a def with `idris = 0`), L20 (`SyntaxSamples.idr` loses the
four).

**S23. Core keeps what the frontend knew** (L20, `Term.idr`). `Con` is
indexed by its field count and every reference holds it; a primitive
application is `Prim k` with a generated `primArity` (L06), and its result
type comes from the signature, not a hand table; whether a primitive does IO
and which results it gives are generated from ODS; an array op holds its own
operands. The declarations are L20's forms: `NewWorld` stays its own
constructor, a run-time crash message is `CrashWith`, and case arms are
`CaseArms`/`LitArms` (no `Maybe` default). Consumers: L21 (Terms, Cases,
Primitives, Shapes, Programs), L22, L06.

**S24. A location is a sum** (L20, `Loc.idr`). No `""` stands for "no file"
or "no module": a source is present or absent by constructor. Names:
`Located`, `Span`, `locFile`, `locModule`, `locSpan`. Consumers: L21, L22
(`Growth.idr`, `Profile.idr`, `TS.places`).

**S25. A refusal is a record, carried in the module** (L21 builds it in
`Resolve.idr`; L20 writes it into the module; L17 declares the attribute;
L18 re-emits it; rulings A1 and A7, completed by §9 B8). `Resolve.idr` holds
`record Refusal { rule : Rule; site : NonEmptyFC; owner : String; what :
String }`, deduplicated by value, never by printed text: no field holds a
category (the category is the rule's ODS record's), and it lives in
`Resolve.idr` because `Errors` imports `State`; `TS.rejected` holds the
rejections in the order found, and `program : Core (List Rejection)`, a
`Rejection` being a refusal or one of Idris's own errors. One channel: L20
owns `record ModuleRefusal { rule : Rule; site : Loc; message : String }`
and the writer `Emit.refused : File -> List1 ModuleRefusal -> IO (Either
String ())`, which writes a module with no `idr.program` whose module
attribute `idr.refusals` holds an array of `#idr.refusal<rule, loc,
message>` (declared by L17 in `IdrAttrs.td`), one per refusal, in order
(`List1`: a refused module has a refusal; no pass runs on a module with no
program, so nothing drops the attribute). L21 and L22 build the
`ModuleRefusal`s; Idris's own errors (a program that does not elaborate) are
refusals of the rule `Elaboration` (S29(c)) carrying Idris's message (L22),
so every frontend failure is a typed `#idr.refusal`. The driver (L18) reads
`idr.refusals`, re-emits each through `idr::refuse(loc, rule)`, and is the
only printer of refusals: the existing `foldDiagnostics` alone decides every
verdict and writes the report; no text line is parsed, and the frontend's
exit status 3 (`Frontend/Driver.idr:statusOfAll`) is no longer read as a
verdict. The frontend prints no refusal, so its stdout and stderr for a
refused program change, and the reject fixtures' expected files change with
them (§8.4). `Location` and its printer move into `MLIR/Text.idr` (L20), so
the generated syntax module can name a location, and L06's generator gains a
`LocationAttr` parameter kind for `#idr.refusal`'s `loc`
(`idris-mlir-tblgen.cpp:1211-1240`). `harness/lib/profile.sh` reads the
report, not the prose (L23). Consumers: L05, L06, L17, L18, L20, L22,
L23.

**S26. One typed property table for `idr-expect`** (L14). Internal to L14
and its fixtures (`tests/expect-allocation/**`, `tests/contracts-break-linear/**`): each
property is one table row with typed arguments parsed once; Contracts calls
the typed checks directly and prints no module to a temporary file.

**S27. A pass's stage is data** (L13, `Passes.td`; the stage table by L06).
Each pass declares in its TableGen record the stage it requires and the
stage it leaves, the fields `requires` and `sets` of `IdrPass` (records
`IdrStageHigher`, `IdrStageFirst`, `IdrStageOwned`, `IdrStageLowered`,
`IdrStageAny`, with no defaults, so TableGen refuses a pass without them); a
pass that runs at several stages declares `any`. The check comes only from
upstream's mechanism for what every pass of a family shares, the generated
base's base class: `PassBase`'s `baseClass`
(`mlir/include/mlir/Pass/PassBase.td:PassBase`, as `InterfacePass` uses it;
`mlir/tools/mlir-tblgen/PassGen.cpp` derives `impl::<Pass>Base` from it). A
pass whose `requires` is a stage has `baseClass = "::idr::StagedPass<" #
anchor # ", ::idr::Stage::" # requires # ", ::idr::Stage::" # sets # ">"`
(`include/idr/Transforms/Pipeline.h`, L13), an `OperationPass<anchor>` whose
`runOnOperation()` is `final`: it finds the program (the anchor, its
ancestor, or the module's one program), refuses another stage with
`emitError` and `signalPassFailure()`, runs the pass's `virtual void
runOnProgram()`, and on success sets the program's stage to `sets`. The
check is thus part of the pass in every tool that runs it; there is no
generated C++ check and no instrumentation: `idr::addStageCheck` is
withdrawn, since it would repeat the base class's check (and an
instrumentation cannot set the stage a pass leaves without writing IR). Only
a pass anchored on the program or the module may set a stage: a
function-anchored pass has `sets` equal to `requires`. L06's
`-gen-pass-stages` writes the stage table (`IdrPassStages.txt`, `<requires>
<sets> <argument>` per pass) that the coordinator's spec test reads: each
pass's `requires`, in pipeline order, is the stage the previous pass `sets`
(`tests/spec/**`, from L13's handoff). Deleted: the two hand checks
(`Ownership/Rc.cpp:62`; `Effects/Effects.cpp:31-34`, L11's), the three hand
`setStage` calls (`Defunctionalize/Pass.cpp:140`, `Rc.cpp:81`,
`Conversion/Lower.cpp:227`) and the stage sentences in `Passes.td`'s
descriptions. A pass that keeps `requires = any` keeps `runOnOperation`.
*idr-rc's steps* (mlir-13, mlir-14; §9 B1): idr-rc set `owned` midway, before
its two nested runs (`Rc.cpp:81`, `:87`, `:110`), so it becomes a registered
pass pipeline (`PassPipelineRegistration`: `--idr-rc` still names the whole)
of registered passes, in order: `idr.func(idr-rc-cells)` [first] (S3's
cells made); `idr-rc-stack` [first] (S3's stack cells promoted);
`idr-rc-grades` [first → owned] (the buffer boundaries, here because an
`idr.own.adopt` is owned, `IdrOwnershipOps.td:195`, which the verifier
refuses before the owned stage, `Verify/Program.cpp:230`; Borrows; the
owned grades); `idr.func(idr-rc-place)` [owned]; `idr-rc-exclusive` [owned]
(exclusivity, which reads the dups placement makes, `Rc.cpp:15`, and the
reuse rewrite of `idr.cell.new` into `idr.cell.recycle`); `symbol-dce`.
Consumers: each lane that owns a staged pass renames its `runOnOperation` to
`runOnProgram` (L08, L09, L11, L12, L13, L14); L06 (`-gen-pass-stages`); L09
(escapes at the stack step) and L10 (Reuses, Borrows and Exclusivity at
their steps); L18 installs no stage check.

**S28. Two files several lanes edit are the coordinator's, from handoffs.**
`foreign/idr/include/idr/IR/IdrDialect.h` and
`foreign/idr/include/idr/IR/IdrBytecode.td` are in the coordinator's writes,
because each lane's finding changes a different declaration of one file and
`ownership.json` cannot give a file to five lanes. A lane puts its exact
hunk in its handoff ("hub text") and writes its own files against it; the
coordinator applies the hunks (they touch disjoint declarations) before
`make typecheck`. In `IdrDialect.h`: L01 deletes the `MatchLike` concept; L02
deletes `detail::verifyHoles` and declares `bool fillsCell(CellInitOp)` in
`detail` (S3); L03 changes `consumes` and `ownsParameter` to take a `const
mlir::SymbolTable *` (S6), while S7's and S9's declarations and the effect
table live in L03's own `Func.h`, not here; L04 deletes `Held::Closure`
(S10) and adds the `SameValue` trait class (S11); L05 deletes
`MayCrash<bool>::Impl`, the `GuardOp` concept, `knownNonZero` and
`knownFinite`, `ConsumesOperands`' unread groups and the run-time
`guardedSpeculatability`, and writes S16's `Guard`, `Guarded` and the
`GuardedOp` trait class; L06 includes `IdrGuards.inc` after the op classes
(S16); L08 adds the `NoRuntimeForm` trait class (S43); L17 changes `struct
Ctor` (S19). In
`IdrBytecode.td`: L04 says in its handoff how the bare world is written (a
type no record covers is written as its text, as the world's carrier is now;
a record is `def WorldType : DialectType<(type)>;` appended last to `elems`,
so no code moves); L02 types `DestType`'s parameter
`WithType<"::idr::BoxType", Type>` and deletes its `cBuilder`; L06 writes the
`Idr_FieldCode` enum and the `Body` and `Ctor` records (idris-emit-15); L17
states the `Ctor` role payload in its handoff (S19), and the coordinator
writes it into L06's `Ctor` record.

**S29. ODS spellings that three or more `.td` writers share** (ODS text by
L05 in `IdrBase.td`). (a) `Idr_Guarded<list<string> operands,
I32EnumAttrCase kind, string cause>`, uses written `["indices", "array"]`;
the five `CheckKind` cases are defs named as `Idr_Megamorphic` is,
`Idr_Nonzero`, `Idr_InBounds`, `Idr_Nonempty`, `Idr_Finite`, `Idr_InRange`
(L05 defines them), and L05, L16 (`IdrScalarOps.td`, `IdrStringOps.td`,
`IdrBigOps.td`) and L24 (`IdrArrayOps.td`, `IdrIOOps.td`) rewrite their
uses. (b) The ABI word, with no empty-string sentinel for the count: `class
Idr_AbiCount;` with the record defs `Idr_NoCount`, `Idr_BytesOf` and
`Idr_LengthOf`, and `class Idr_AbiWord<string word, Idr_AbiCount count>`
with fields `abiWord` and `Idr_AbiCount abiCount = count`: `word` is a case
of the generator's `Word` (`World`, `Str`, `Big`, `Buffer`), `count` the
guard count kind the base's `guardOf` gives that word (`Idr_BytesOf` for
`Str`, `Idr_LengthOf` for `Buffer`, `Idr_NoCount` otherwise), so the
generator reads a record, never a string that may be empty. Each constraint
in the base `dialectWord` table mixes it in, spelled the same way, in the
file that defines it: L04 (`IdrTypes.td`: `Idr_WorldType`, `Idr_StrType`,
`Idr_StrValue`, `Idr_BigType`, `Idr_NatType`, `Idr_BigValue`,
`Idr_NatValue`, `Idr_BigOrNatValue`), L03 (`IdrOps.td`: `Idr_StrRead`,
`Idr_BigRead`, `Idr_NatRead`, `Idr_BigOrNatRead`) and L16 (`IdrBigOps.td`:
`Idr_Rank1ArrayValue`, `Idr_ByteBuffer`); L06 reads the fields and deletes
`dialectWord`. (c) The rules (`Idr_Rule`, `Idr_RuleCategory`): L05 adds the
category `def Idr_UserError : I32EnumAttrCase<"UserError", 2, "user
error">` and, with the other rules, `Idr_RuleCase<"Elaboration", 31,
"elaboration", Idr_UserError>` (31: the first value never given to a rule),
the refusal that carries Idris's own message when a program does not
elaborate (S25); the category comment, which names two kinds and calls them
the only two, is rewritten for three (§9 B8). The generated Idris `Rule` and
`RuleCategory` gain the cases at regeneration. Consumers: L03, L04, L06,
L16, L20, L21, L22, L24.

**S30. Reserved symbol names** (L17, `Symbols.h`/`Symbols.cpp`).
`std::string idr::reservedName(llvm::StringRef kind, llvm::StringRef
discriminator)` returns `__idr$<kind>$<discriminator>`, `kind` starting with a
letter, so that no `mangle` output (which writes `$` only before a digit) and
no runtime C name equals one (conversion-15). The reserved names are
`("entry", "body")` (the entry body), `("release", "cafs")` (the release
function) and `("bin", name)` (a symbol two bins read), with the box data's;
the release function's name has one accessor, `std::string
idr::releaseCafsName()`, read wherever it is made or called. Callers: L07
(`StaticNames.cpp`: the box data), L06 (`Runtime.cpp`: the merge names the
release function), L08 (`Entry.cpp`: the entry body and the call of the
release function; `Mangle.h`'s comment), L18 (`Partition.cpp`: the
cross-bin names). The collision checks the reserved names make impossible
go; the check that a runtime declaration's C name is no program symbol
stays (a C identifier is its own mangling, and `SymbolTable::insert` would
rename the declaration silently).

**S31. A primitive's type and a quantity's use, total** (L21,
`Frontend/Resolve.idr`). `primTy : PrimType -> PrimTy`, total and exported
(no `Maybe`); `data Use = Erased | Used Quantity`, with no `Eq` (a reader
matches); `use : RigCount -> Use` (`elimSemi Erased (Used One) (const (Used
Many))`); `multiplicity : Use -> Multiplicity`. `quantityOf`, whose
`quantityOf 0` is `Many`, is deleted; each `RigCount` classifier and Boolean
test (idris-frontend-5, L22's) reads `use`. Consumers: L22.

**S32. A definition's place, resolved once; probes by type** (L22,
`Frontend/Walk.idr`). `export record Placement` (its constructor unexported,
so only `placementOf` makes one) holds the context index and its path,
computed once; `placementOf : Int -> Maybe Placement` (`Nothing` only for a
negative index); `placementIn : Context -> Name -> Maybe Placement`;
`resolve : {auto c : Ref Ctxt Defs} -> Name -> Core (Maybe (Placement,
GlobalDef))`, over the fork's `lookupCtxtExactI`; `addressOf : Placement ->
Address`; `enter : Placement -> (w : Walked) -> Maybe (Subset Walked (\w' =>
Smaller w' w))`, whose `Nothing` means only "entered already"
(idris-frontend-6). A probe is a name no definition has (idris-frontend-11):
`public export data Probe`, one constructor per family (two families that
share a spelling are two constructors); `probeName : Probe -> Name` is the
only place a probe's string is spelled, with `probeOf : Name -> Maybe Probe`,
`probeTerm : Probe -> ClosedTerm` and `probeOfTerm : TT vs -> Maybe Probe`;
every name, Core and key stays byte-identical. Consumers: L21 (`Terms`'
placements, its probe sites).

**S33. A dictionary field carries its key** (L22, `Translate/State.idr`).
`DictField = (Link Form, Nat, Nat)` moves unchanged from `Finite.idr` to
`State.idr` (`Proof/Requests.FieldUniverse` is over it); `DictArg
ClosedTerm` becomes `DictArg DictField ClosedTerm`, the key built in `Types`
where the layout is registered, so no lookup by printed symbol converts one
key to the other (idris-frontend-12). Consumers: L21 (`Cases.dictionariesOf`
reads each `DictArg`'s key).

**S34. The inline verdict, decided once** (L09, `Analysis/Inline.h`).
`struct inlining::Facts { int64_t size = 0; bool inlines = false; }` and
`Facts inlining::factsOf(idr::FuncOp fn, unsigned calls, bool shared)`, one
read of the final body: `size = inlineSize(fn)`; `inlines` is false when
`shared`, when the body calls `fn`, or under `no_inline`, else true for a
leaf (no `idr.call`) of at most `kLeafSize` ops, else `(calls - 1) * (size -
kSmall) <= kProduct` (analysis-16). The cycle input stays the ready set's
`shared`. Consumers: L11 (`Component.cpp`'s `finish` calls it and its own
`factsOf` goes; `Inline.cpp` reads `facts.inlines` and `facts.size`, not
`fn.getNoInline()`; `Optimize.h`).

**S35. Array op shapes as interfaces** (ODS text by L05 in
`IdrInterfaces.td`; implementations by L24; read by L13 and by L24's
yield). `Idr_YieldTargetsOpInterface`, one method `::mlir::ValueRange
getYieldTargets()` (the arrays the leading values of the op's
`idr.array.yield` move into, one each; the yield forwards the values after
them), a base of `Idr_GeneratingOpInterface` and `Idr_UpdateOpInterface`:
`TabulateOp` and `TabulateIOOp` give `getArrays()`, `FoldLastOp` and
`ScanLastOp` `getResults()`, `ArrayUpdateOp` and `ElementUpdateOp`
`getODSOperands(0)`. The yield's parent rule is a `PredOpTrait` that its
parent holds the interface, and both `TypeSwitch`es on the parent's kind go
(ir-ops-2). `Idr_LastAxisFoldOpInterface` on the `Idr_FoldsAnAccumulator`
ops (`idr.fold_last`, `idr.scan_last`): `::mlir::OperandRange getInits()`,
`::mlir::Value getLength()`, `unsigned getFrameRank()`,
`::mlir::Block::BlockArgListType getAccumulators()` (transforms-b-13);
`StructureLoops/Linalg.cpp`'s ternaries, `Nests.cpp`'s second `folded`
instantiation and `StructureLoops.cpp:31`'s cast go, and the scan's write of
each step stays (essential). Consumers: L13.

**S36. Whether a constructor has a cell** (L02, `IR/Ownership.h`). `bool
idr::buildsCell(mlir::Type type, idr::Tag tag)`: a value of `type`, at any
grade, is a box and constructor `tag` is not an atom (`isBoxed(type) &&
!dataTypeOf(type).isAtom(tag)`, defined in `OpsOwnership.cpp`). It is the
one place the two cases meet: a con for which it holds becomes
`idr.cell.new` and `idr.cell.init` in idr-rc's cells step and its take is
`idr.take`; any other con stays `idr.con` and its take is `idr.unpack` (S3,
S4); `!idr.cell`'s verifier requires it. Testing at any grade fixes §7's
linear-box bug (`Stack.cpp:73` tests `isa<BoxType>` alone). Consumers: L07
(`LowerCon` keeps the others), L13 (the cells and stack steps), L15 (the
owned verifier refuses an `idr.con` for which it holds after idr-rc).

**S37. Remaking an op with new operands and types** (L12,
`Support/Remake.h`, header only). `mlir::Operation
*idr::remakeOp(mlir::RewriterBase &rewriter, mlir::Operation *op,
mlir::ValueRange operands, mlir::TypeRange results)`, inline: it clones `op`
with an `IRMapping` of the new operands and
`Operation::CloneOptions::all().cloneRegions(false).withResultTypes(results)`
(properties, attributes and successors come with the clone), inserts it
before `op`, and moves each region in with `rewriter.inlineRegionBefore`;
the caller replaces `op` (transforms-a-15: no hand `OperationState`). The
three copies go: `Columns/Records.cpp:remake`, `RetypePattern`'s inline copy
and `Specialize/Raise.cpp:retyped`. Consumers: L11 (`Raise.cpp`'s push).

**S38. A program's root, by one rule** (L03, `Func.h`; with L07's
`layout::holdsNoComponent`). `enum class idr::RootKind { Status, IO }` and
`std::optional<RootKind> idr::rootKind(mlir::FunctionType, Stage)`: `() ->
i64` is `Status` at every stage; before lowering, `(!idr.world) -> (R...)`
is `IO` when every `R` holds no runtime component (`bool
layout::holdsNoComponent(mlir::Type)`, L07: the world, and a data type held
in place of at most one constructor whose every field holds none, so the
frontend's `IORes` of unit and the e2e `(!Unit, !idr.world)` root); lowered,
`() -> ()` is `IO`; any other type is none, which the program's verifier
refuses at that stage, so the `(!idr.world) -> (!idr.world, i64)`
misreading is refused (its `i64` holds a component). `Program.cpp`'s
`rootType` becomes it; idr-entry reads it and trusts the lowered stage's
verifier (conversion-8). The finding's narrower IO form `(!idr.world) ->
!idr.world` would refuse every program the frontend emits
(`Programs.idr:translateIOProgram`) and every e2e IO fixture. Consumers: L07
(supplies `holdsNoComponent`, the one decision of "no runtime form" in
`layout::components`), L08 (`Entry.cpp`).

**S39. A callee's constants, with a null object** (L09 declares it in
`Analysis/Constants.h`; L11 writes the hook). `using ConstantsOf =
llvm::function_ref<ConstantResults(idr::CallOp call)>`: the final callee's
`returnedConstants`, else, for a callee that is not final,
`ConstantValue::getUnknownConstant()` at every result of `call`. Joining
unknown is upstream's `setToEntryState`, so `visitExternalCall` has no
branch, and no `const ConstantResults *` null pointer travels through the
callee hooks (analysis-7). Consumers: L11 (`Effects/Constants.cpp` builds
the hook from its callee variant).

**S40. A lane op's width** (L12, `Transforms/Narrow.h`). `struct
narrow::LaneWidth { unsigned bits; bool lanes; }` and `LaneWidth
narrow::laneWidth(mlir::Operation *op)`: for an elementwise op that is no
`CastOpInterface` and no `arith::SelectOp`, the widest
`ConstantIntRanges::getStorageBitwidth` of its operand and result types and
whether they are vectors; `{0, false}` otherwise. It replaces `Width` and
`widthOf`: "computes on wide lanes" is defined once (transforms-a-14).
Consumers: L14 (`Expect/NarrowedLanes.cpp` reads `w.lanes ? w.bits : 0`).

**S41. A closure's quantity is its type** (L04; ODS text by L24 in
`IdrClosureOps.td`). `idr.closure` and `idr.suspend` give their result at
quantity one (`!idr.lin<...>` over the closure's or the suspension's type)
exactly when some capture is linear, and plain otherwise: a declared
`PredOpTrait` on each op (S17's standard), not code in
`ClosureOp::verify`/`SuspendOp::verify`. `idr.apply`'s callee and
`idr.force`'s suspension constraints read the carrier (`unrestricted`), so a
linear closure is applied, and a linear suspension forced, with no
`lin.use` first. The linearity verifier (L04, `Verify/Linearity.cpp`) then
counts the one use as for any linear value (ir-verify-7). Deleted:
`holdsLinear` and `takenOnce` (`Grades.h`/`Grades.cpp`, L04), the two
verifier rules (`OpsClosures.cpp`, L24), `LinUseOp::fold`'s guard
(`OpsScalars.cpp`, L16), Feeds' closure exception (`Canon/Feeds.cpp`, L01).
Kept (essential): a world is never captured. Consumers: L01, L12 (the sum a
linear closure becomes is linear), L16, L20 (`Emit/Closures.idr` writes the
closure's type at quantity one when a capture is linear: Idris binds such a
lambda at quantity 1), L24.

**S42. What a literal of a type is** (L04; ODS text by L05 in
`IdrInterfaces.td`). `Idr_LiteralTypeInterface`, a
`TypeInterface<"LiteralTypeInterface">` with `bool
isLiteral(::mlir::Attribute)` and `::mlir::ParseResult
parseLiteral(::mlir::AsmParser &, ::mlir::Attribute &)`. L04 implements it
on `StrType`, `BigType` and `NatType` (`Types.cpp`) and, by external model,
on `IntegerType` (`ValueFacts.cpp`, where the scalar models are attached); a
natural's literal is a non-negative `BigAttr`, said there once.
`idr.match_lit`'s scrutinee is a value whose type implements it (a type
constraint on the interface in `IdrMatchOps.td`, replacing the listed
types), and `MatchLitOp::verify` and `parseKey` (L01) and
`ConstantOp::isBuildableWith` (L17, `Constants.cpp`) dispatch through it
(ir-ops-10). Deleted: the two ladders in the match ops, the literal cases
of `isBuildableWith`, the second natural rule. Consumers: L01, L17.

**S43. Ops with no runtime form are a trait** (L08; ODS text by L05 in
`IdrInterfaces.td`; the C++ class in L08's S28 hunk). `def Idr_NoRuntimeForm
: NativeOpTrait<"NoRuntimeForm"> { let cppNamespace = "::idr"; }`, its class
an empty `mlir::OpTrait::TraitBase` whose comment says the op's result is
its operand at run time (a change of grade, linearity or kind). Carrying the
operand implies it, said once: `Idr_ResultCarriesOperand` becomes a
`TraitList` of its native trait (under a new def name; the C++ class
`ResultCarriesOperand` keeps its name) and `Idr_NoRuntimeForm`, so
`idr.borrow`, `idr.share`, `idr.lin.enter` and `idr.lin.use` have it with no
edit; the others list it themselves: L02 (`idr.own.adopt`, `idr.own.give`),
L24 (`idr.tie_shape`), L16 (`idr.nat.to_big`). idr-lower registers one
upstream `OpTraitConversionPattern<::idr::NoRuntimeForm>`
(`DialectConversion.h`) that replaces the op's result with its first
operand's converted values (`replaceOpWithMultiple`), for every op with the
trait (conversion-13). Deleted: `LowerAsItself` and the four hand lists
(`Cells.cpp:216` and `Memrefs.cpp:144`, L07's; `Counting.cpp:196-197` and
`Bigs.cpp:71`, L08's). Consumers: L02, L05, L07, L16, L24.

**S44. String builders as an interface; rewrites to a value as folds** (L01;
ODS text by L05 in `IdrInterfaces.td`; attached by L16).
`Idr_StrBuilderOpInterface`: `bool nonEmpty()`, `bool writesInPieces()`,
`::mlir::Value writePieces(::mlir::OpBuilder &b, ::mlir::Value world)` (only
when `writesInPieces()`; it gives the world after), `bool knowsFirstChar()`
and `::mlir::Value firstChar(::mlir::OpBuilder &b)` (only when
`knowsFirstChar()`): a predicate beside each builder, so a profit test asks
without building. L16 attaches it in its ODS to `idr.str.append`,
`str.cons`, `str.from_char`, S21's three shows, `str.pack`, `str.concat` and
`idr.big.show`; L01 defines its methods in `Canon/Output.cpp` from the DRR
patterns they replace: `Canonicalize.td`'s thirteen patterns become two C++
patterns over the interface, and Feeds asks it (ir-verify-16). A rewrite to
an existing value is a fold, not a pattern (mlir-19): `PutStrOp::fold`
(`put_str ""`; defined by L01, `hasFolder` on `idr.io.put_str` by L24) and
`StrHeadOp::fold`, which handles the cons case (L16). Consumers: L05
(`knownNonEmpty`), L14 (`Expect/Output.cpp` asks `writesInPieces`), L16,
L24.

## 5. Library first

| Responsibility | Upstream owner | What disappears |
|---|---|---|
| A shared op shape (matches) | ODS `OpInterface` | the `MatchLike` concept, 24 `isa` pairs |
| Result types from operands | `InferTypeOpInterface` | take's three hand result lists |
| A region's predecessors | `RegionBranchOpInterface::getPredecessorValues` | returned-arguments' `scf` ladder (transforms-b-4) |
| Memory effects and operand constraints | ODS `MemoryEffects<[...]>`, `Arg<..., [MemRead]>`, type constraints, `DenseArrayStrictlySorted` | 11 hand `getEffects`, ~20 hand verifier checks |
| An optional-free default | ODS properties (`DefaultValuedProp`, `NamedEnumProp`) | the effects attribute's two storage forms, `Idr_EffectAttr` |
| What a call may do | `MemoryEffectOpInterface` over `idr.call`'s own effects; upstream CSE, dead-op erase and canonicalization | `CalleeEffects` and its readers, `Optimize/PureCalls.cpp`, the table-bound canonicalizer (S6) |
| An op that lowers to its operand | `OpTraitConversionPattern` over a trait | four hand lists of `LowerAsItself` (S43) |
| Dead blocks after inlining | `mlir::eraseUnreachableBlocks` | multi-block function bodies |
| Cached module analyses | `AnalysisManager`, `CallGraph` | five SCC walks |
| A dependency solver | `DataFlowSolver`, `AnalysisState` subscriptions | Borrows' hand queues (analysis-14) |
| Errors that carry their class | `llvm::Error`, `llvm::Expected` | 62 sentinel returns in the driver |
| A location's file and line | `Location::findInstanceOf<FileLineColRange>` | the crash message's hand walk (conversion-11) |
| Type conversion in lowering | `TypeConverter`, the dialect conversion framework | per-pattern width casework |
| Generated tables from ODS | `idris-mlir-tblgen` over records | hand C++ and Idris tables keyed by name |

## 6. Lanes (all start at dispatch)

Every lane starts at dispatch; the contracts each consumes are fixed in §4,
so none waits on another. L25, L26 and L27 were added on 2026-10-18, after
L01 to L22 were dispatched; they and L23 start together at their own
dispatch, against base 1e5a8a8e, and the seams L23 and L25 share (P, Y, T,
B) are fixed in both lanes' bodies. The table is generated from
`ownership.json`.

<!-- lanes-table -->
| Lane | Outcome | Exclusive writes | Findings |
|---|---|---|---|
| L01 | Matches: one interface, declared regions | `foreign/idr/include/idr/IR/IdrMatchOps.td`, `foreign/idr/include/idr/IR/Canon.h`, `foreign/idr/lib/IR/OpsMatch.cpp`, `foreign/idr/lib/IR/OpsMatchSyntax.cpp`, `foreign/idr/lib/IR/Regions.cpp`, `foreign/idr/lib/IR/Canon/**`, `foreign/idr/lib/Transforms/Canonicalize/**`, `foreign/idr/include/idr/Transforms/Canonicalize.h`, `tests/canon-array-moves/**`, `tests/verify-match/verify-match.mlir` | ir-ods-1, ir-verify-2, transforms-a-2, ir-ods-9, ir-ops-14, ir-verify-13, ir-verify-17, ir-verify-16, mlir-2, mlir-9, mlir-19 |
| L02 | Cells: con with its token, take's inferred results, atoms | `foreign/idr/include/idr/IR/IdrOwnershipOps.td`, `foreign/idr/include/idr/IR/Ownership.h`, `foreign/idr/lib/IR/OpsCon.cpp`, `foreign/idr/lib/IR/OpsOwnership.cpp` | transforms-b-2, ir-ops-5, analysis-13, transforms-b-1, ir-ops-6, ir-ops-8, mlir-5 |
| L03 | Functions, effects and stages: one block, one effects property, one stage table | `foreign/idr/include/idr/IR/IdrOps.td`, `foreign/idr/include/idr/IR/Func.h`, `foreign/idr/lib/IR/Func/**`, `foreign/idr/lib/IR/Effects.cpp`, `foreign/idr/lib/IR/Ops.cpp`, `foreign/idr/lib/IR/Dialect.cpp`, `foreign/idr/lib/IR/Verify/Program.cpp`, `tests/effects-alloc/**`, `tests/func-call-effects-contain/**`, `tests/verify-program/verify-program.mlir` | ir-verify-1, transforms-b-3, analysis-9, ir-verify-15, analysis-3, ir-verify-6, ir-verify-5, transforms-a-8, transforms-a-13, ir-verify-9, ir-ops-9, mlir-4, mlir-12 |
| L04 | Types and grades: the world's own type, used once by type, a value's source | `foreign/idr/include/idr/IR/IdrTypes.td`, `foreign/idr/include/idr/IR/Grades.h`, `foreign/idr/include/idr/IR/Ranges.h`, `foreign/idr/lib/IR/Types.cpp`, `foreign/idr/lib/IR/Grades.cpp`, `foreign/idr/lib/IR/Ranges.cpp`, `foreign/idr/lib/IR/ValueFacts.cpp`, `foreign/idr/lib/IR/Asm.cpp`, `foreign/idr/lib/IR/Bytecode.cpp`, `foreign/idr/lib/IR/Verify/Linearity.cpp`, `tests/asm-aliases/**`, `tests/syntax-closures/**`, `tests/world-once/**` | ir-ods-3, ir-verify-3, ir-ops-16, ir-verify-7, ir-verify-8, analysis-4, analysis-8, ir-ops-10 |
| L05 | Declared facts: interfaces, guard marks, crash effects, ODS constraints | `foreign/idr/include/idr/IR/IdrBase.td`, `foreign/idr/include/idr/IR/IdrInterfaces.td`, `foreign/idr/include/idr/IR/IdrCheckOps.td`, `foreign/idr/include/idr/IR/Fold.h`, `foreign/idr/lib/IR/OpsChecks.cpp`, `foreign/idr/lib/IR/Crashes.cpp`, `tests/guards-fold-finite/**` | ir-ods-2, ir-verify-4, ir-ods-4, ir-ods-5, ir-ops-1, ir-ops-13, ir-ods-10 |
| L06 | Generator and runtime ABI: typed tables generated once | `foreign/idr/tools/idris-mlir-tblgen.cpp`, `foreign/idr/include/idr/Conversion/Runtime.h`, `foreign/idr/lib/Conversion/Runtime.cpp`, `foreign/idr/lib/Conversion/RuntimeCalls.cpp`, `foreign/idr/include/idr/IR/IdrRuntime.td` | conversion-1, driver-runtime-T1, conversion-2, driver-runtime-T2, driver-runtime-T3, ir-ods-11, driver-runtime-T4, idris-emit-15 |
| L07 | Layout and cell lowering: one component walk, one header writer | `foreign/idr/include/idr/IR/Layout.h`, `foreign/idr/lib/IR/Layout/**`, `foreign/idr/include/idr/Conversion/Arrays.h`, `foreign/idr/include/idr/Conversion/Elements.h`, `foreign/idr/include/idr/Conversion/Facts.h`, `foreign/idr/include/idr/Conversion/Fields.h`, `foreign/idr/include/idr/Conversion/StaticData.h`, `foreign/idr/include/idr/Conversion/Words.h`, `foreign/idr/lib/Conversion/Arrays.cpp`, `foreign/idr/lib/Conversion/Buffers.cpp`, `foreign/idr/lib/Conversion/Cells.cpp`, `foreign/idr/lib/Conversion/Descriptors.cpp`, `foreign/idr/lib/Conversion/Elements.cpp`, `foreign/idr/lib/Conversion/Facts.cpp`, `foreign/idr/lib/Conversion/Fields.cpp`, `foreign/idr/lib/Conversion/MemoCells.cpp`, `foreign/idr/lib/Conversion/Memrefs.cpp`, `foreign/idr/lib/Conversion/RuntimeCells.cpp`, `foreign/idr/lib/Conversion/StaticData.cpp`, `foreign/idr/lib/Conversion/StaticNames.cpp`, `foreign/idr/lib/Conversion/Words.cpp`, `tests/lower-arrays/**` | ir-ops-3, ir-ods-6, conversion-6, conversion-3, conversion-4, conversion-5, conversion-9, conversion-12, conversion-14, ir-ops-12, mlir-11, mlir-15, mlir-16 |
| L08 | Lowering control: entry, tail calls, matches, literals, symbols | `foreign/idr/include/idr/Conversion/FuncToFunc.h`, `foreign/idr/include/idr/Conversion/Frame.h`, `foreign/idr/include/idr/Conversion/IdrPattern.h`, `foreign/idr/include/idr/Conversion/Mangle.h`, `foreign/idr/include/idr/Conversion/Matches.h`, `foreign/idr/include/idr/Conversion/Passes.h`, `foreign/idr/include/idr/Conversion/Patterns.h`, `foreign/idr/include/idr/Conversion/ReturnRegisters.h`, `foreign/idr/include/idr/Conversion/TailCallPlan.h`, `foreign/idr/include/idr/Conversion/TailPosition.h`, `foreign/idr/lib/Conversion/Bigs.cpp`, `foreign/idr/lib/Conversion/Checks.cpp`, `foreign/idr/lib/Conversion/Counting.cpp`, `foreign/idr/lib/Conversion/Entry.cpp`, `foreign/idr/lib/Conversion/Frame.cpp`, `foreign/idr/lib/Conversion/FuncToFunc.cpp`, `foreign/idr/lib/Conversion/Lower.cpp`, `foreign/idr/lib/Conversion/Mangle.cpp`, `foreign/idr/lib/Conversion/Matches.cpp`, `foreign/idr/lib/Conversion/ReturnRegisters.cpp`, `foreign/idr/lib/Conversion/Scalars.cpp`, `foreign/idr/lib/Conversion/Strings.cpp`, `foreign/idr/lib/Conversion/TailCallPlan.cpp`, `foreign/idr/lib/Conversion/TailCalls.cpp`, `foreign/idr/lib/Conversion/TailPosition.cpp`, `tests/tail-calls-decided-loops/**`, `tests/e2e-crash-callsite/**`, `tests/names-reserved/**`, `foreign/idr/include/idr/Conversion/PassThroughMemory.h`, `foreign/idr/lib/Conversion/PassThroughMemory.cpp` | conversion-7, conversion-8, conversion-10, conversion-11, conversion-13, conversion-15, mlir-10 |
| L09 | Analyses I: call cycles once, binding times as two, escapes, inline verdicts | `foreign/idr/include/idr/Analysis/Constants.h`, `foreign/idr/include/idr/Analysis/Effects.h`, `foreign/idr/include/idr/Analysis/Escapes.h`, `foreign/idr/include/idr/Analysis/EscapesDetail.h`, `foreign/idr/include/idr/Analysis/Inline.h`, `foreign/idr/include/idr/Analysis/Specialize.h`, `foreign/idr/include/idr/Analysis/BindingTimes.h`, `foreign/idr/include/idr/Analysis/CallCycles.h`, `foreign/idr/include/idr/Support/Scc.h`, `foreign/idr/lib/Support/Scc.cpp`, `foreign/idr/lib/Analysis/BindingTimes.cpp`, `foreign/idr/lib/Analysis/CallCycles.cpp`, `foreign/idr/lib/Analysis/Constants.cpp`, `foreign/idr/lib/Analysis/Effects.cpp`, `foreign/idr/lib/Analysis/Escapes.cpp`, `foreign/idr/lib/Analysis/EscapesCycles.cpp`, `foreign/idr/lib/Analysis/Inline.cpp`, `tests/idr/escapes/**` | analysis-1, transforms-a-3, analysis-2, analysis-12, analysis-16, mlir-20 |
| L10 | Analyses II: labels, identities, tail, ownership, ranges | `foreign/idr/include/idr/Analysis/Identities.h`, `foreign/idr/include/idr/Analysis/Labels.h`, `foreign/idr/include/idr/Analysis/Ownership.h`, `foreign/idr/include/idr/Analysis/Ranges.h`, `foreign/idr/include/idr/Analysis/Tail.h`, `foreign/idr/include/idr/Analysis/Ownership/**`, `foreign/idr/lib/Analysis/Identities.cpp`, `foreign/idr/lib/Analysis/IdentitiesRebuilds.cpp`, `foreign/idr/lib/Analysis/IdentitiesRecord.cpp`, `foreign/idr/lib/Analysis/Labels.cpp`, `foreign/idr/lib/Analysis/LabelSites.cpp`, `foreign/idr/lib/Analysis/Ranges.cpp`, `foreign/idr/lib/Analysis/Tail.cpp`, `foreign/idr/lib/Analysis/Ownership/**`, `tests/idr/exclusivity/**` | analysis-5, analysis-6, analysis-10, analysis-11, analysis-14, analysis-15, analysis-18, mlir-21 |
| L11 | Optimizer and specialization: one request, one node lifecycle, keys off the dialect | `foreign/idr/include/idr/Transforms/Effects.h`, `foreign/idr/include/idr/Transforms/Identity.h`, `foreign/idr/include/idr/Transforms/Inline.h`, `foreign/idr/include/idr/Transforms/Optimize.h`, `foreign/idr/include/idr/Transforms/Specialize.h`, `foreign/idr/lib/Transforms/Effects/**`, `foreign/idr/lib/Transforms/Identity/**`, `foreign/idr/lib/Transforms/Inline/**`, `foreign/idr/lib/Transforms/Optimize/**`, `foreign/idr/lib/Transforms/Specialize/**`, `tests/pipeline-one-pipeline/**`, `tests/raise-apply/**`, `tests/optimize-caller-cap/**`, `tests/identity/**`, `tests/contify-never-returns-twice/**` | transforms-a-4, transforms-a-5, transforms-a-6, transforms-a-7, transforms-a-10, transforms-b-14, analysis-7, ir-ods-12 |
| L12 | Defunctionalization, deduplication, demand, narrowing, columns | `foreign/idr/include/idr/Transforms/Columns.h`, `foreign/idr/include/idr/Transforms/Deduplicate.h`, `foreign/idr/include/idr/Transforms/Defunctionalize.h`, `foreign/idr/include/idr/Transforms/Demand.h`, `foreign/idr/include/idr/Transforms/Narrow.h`, `foreign/idr/lib/Transforms/Columns/**`, `foreign/idr/lib/Transforms/Deduplicate/**`, `foreign/idr/lib/Transforms/Defunctionalize/**`, `foreign/idr/lib/Transforms/Demand/**`, `foreign/idr/lib/Transforms/Narrow/**`, `tests/defunc-choice/**`, `tests/dedup-keep-apart/**`, `tests/narrow-descending/**`, `tests/vectorize-rows/**`, `foreign/idr/include/idr/Support/Remake.h` | transforms-a-12, transforms-a-9, transforms-a-14, transforms-a-15, mlir-17 |
| L13 | Ownership, buffers, stack, tail and loops; passes' stages as data | `foreign/idr/include/idr/Transforms/Bufferize.h`, `foreign/idr/include/idr/Transforms/BufferizeModels.h`, `foreign/idr/include/idr/Transforms/Ownership.h`, `foreign/idr/include/idr/Transforms/Pipeline.h`, `foreign/idr/include/idr/Transforms/Stack.h`, `foreign/idr/include/idr/Transforms/StructureLoops.h`, `foreign/idr/include/idr/Transforms/Tail.h`, `foreign/idr/include/idr/Transforms/Passes.td`, `foreign/idr/include/idr/Transforms/InnerPasses.td`, `foreign/idr/lib/Transforms/Bufferize/**`, `foreign/idr/lib/Transforms/Ownership/**`, `foreign/idr/lib/Transforms/Stack/**`, `foreign/idr/lib/Transforms/StructureLoops/**`, `foreign/idr/lib/Transforms/Tail/**`, `foreign/idr/lib/Transforms/Pipeline.cpp`, `tests/rc-arrays/**`, `tests/bufferize-aliasing/**`, `tests/loops-accumulate/**`, `tests/structure-columns/**`, `tests/pipeline-do-block/**`, `tests/actions-accumulate/**`, `tests/stack-expect/**`, `tests/returned-threaded/**` | transforms-b-4, transforms-b-5, transforms-b-6, transforms-b-7, transforms-b-8, transforms-b-9, transforms-b-10, transforms-b-11, transforms-b-12, transforms-b-16, transforms-b-17, mlir-8, mlir-13, mlir-14, mlir-18 |
| L14 | idr-expect and contracts: one typed property table | `foreign/idr/include/idr/Transforms/Contracts.h`, `foreign/idr/include/idr/Transforms/Expect.h`, `foreign/idr/lib/Transforms/Contracts/**`, `foreign/idr/lib/Transforms/Expect/**`, `tests/expect-allocation/**`, `tests/contracts-break-linear/**` | transforms-a-1, mlir-22, mlir-23 |
| L15 | Verifier internals: the owned stage and uses read the flow edges | `foreign/idr/include/idr/IR/Verify.h`, `foreign/idr/lib/IR/Verify/Attributes.cpp`, `foreign/idr/lib/IR/Verify/Knots.cpp`, `foreign/idr/lib/IR/Verify/Owned.cpp`, `foreign/idr/lib/IR/Verify/OwnedOps.cpp`, `foreign/idr/lib/IR/Verify/OwnedRegions.cpp`, `foreign/idr/lib/IR/Verify/Uses.cpp`, `tests/reduce-regions/**`; not `tests/verify-match/verify-match.mlir`, `tests/verify-program/verify-program.mlir` | ir-verify-11, ir-verify-12, ir-verify-18, ir-verify-19 |
| L16 | Value ops: strings, bigs, scalars and their folds | `foreign/idr/include/idr/IR/IdrStringOps.td`, `foreign/idr/include/idr/IR/IdrBigOps.td`, `foreign/idr/include/idr/IR/IdrScalarOps.td`, `foreign/idr/lib/IR/OpsStrings.cpp`, `foreign/idr/lib/IR/OpsBigs.cpp`, `foreign/idr/lib/IR/OpsScalars.cpp`, `foreign/idr/lib/IR/Fold/**`, `tests/fold-add-zero/**` | ir-verify-10, ir-ops-15, transforms-b-15, mlir-1 |
| L17 | Data, attributes and flow: constructor roles carry their payload, one constant form | `foreign/idr/include/idr/IR/IdrAttrs.td`, `foreign/idr/include/idr/IR/IdrFlow.td`, `foreign/idr/include/idr/IR/Flow.h`, `foreign/idr/include/idr/IR/FlowEdges.h`, `foreign/idr/include/idr/IR/Symbols.h`, `foreign/idr/include/idr/IR/TypeGraph.h`, `foreign/idr/lib/IR/Attrs.cpp`, `foreign/idr/lib/IR/ConAttr.cpp`, `foreign/idr/lib/IR/Constants.cpp`, `foreign/idr/lib/IR/ContentNames.cpp`, `foreign/idr/lib/IR/DataBody.cpp`, `foreign/idr/lib/IR/DataRemap.cpp`, `foreign/idr/lib/IR/Flow.cpp`, `foreign/idr/lib/IR/FlowEdges.cpp`, `foreign/idr/lib/IR/FlowOps.cpp`, `foreign/idr/lib/IR/Symbols.cpp`, `foreign/idr/lib/IR/TypeGraph.cpp`, `tests/roles-contify/**` | ir-ods-7, transforms-a-11, idris-emit-9, ir-ods-8, ir-ops-11, ir-ops-4, analysis-17, ir-ops-7, ir-verify-14, mlir-3 |
| L18 | Driver, target, tools and boxes: failures as values, options as a variant | `foreign/idr/include/idr/Driver/**`, `foreign/idr/include/idr/Support/Actions.h`, `foreign/idr/include/idr/Support/Profile.h`, `foreign/idr/include/idr/Support/Stack.h`, `foreign/idr/include/idr/Support/Worklist.h`, `foreign/idr/include/idr/Target/**`, `foreign/idr/lib/Driver/**`, `foreign/idr/lib/Support/Actions.cpp`, `foreign/idr/lib/Support/Profile.cpp`, `foreign/idr/lib/Target/**`, `foreign/idr/tools/idris-mlir-opt.cpp`, `foreign/idr/tools/idris-mlir-reduce.cpp`, `foreign/idr/tools/idris-mlir.cpp`, `foreign/idr/unittests/**`, `tests/obs-debug-counter/**`, `foreign/idr/include/idr/InitIdr.h`; not `foreign/idr/include/idr/Target/CMakeLists.txt`, `foreign/idr/lib/Target/CMakeLists.txt`, `foreign/idr/unittests/CMakeLists.txt` | driver-runtime-D1, driver-runtime-D2, driver-runtime-D3, driver-runtime-D4, driver-runtime-D5, driver-runtime-D6, driver-runtime-S1, driver-runtime-U1, driver-runtime-P1, mlir-6 |
| L19 | Runtime: streams in the handle table, one crash format, platform facts in the platform layer | `runtime/**`, `tests/runtime-api/**`, `tests/runtime-bigs/**`, `tests/runtime-counting/**`, `tests/runtime-doubles/**`, `tests/runtime-start/**`, `tests/runtime-strings/**`, `tests/runtime-text/**`, `tests/runtime-utf8/**`, `tests/io-buffer/**`, `tests/big-cell/**`, `tests/heap-region/**`, `tests/stack-guard-page/**`, `harness/prop/**`; not `runtime/CMakeLists.txt` | driver-runtime-R1, driver-runtime-R2, driver-runtime-R3, driver-runtime-R4, driver-runtime-R5, driver-runtime-R6, driver-runtime-R7 |
| L20 | Idris Core and Emit: Core keeps what the frontend knew | `compiler/src/IdrisMLIR/Emit/**`, `compiler/src/IdrisMLIR/Emit.idr`, `compiler/src/IdrisMLIR/Term.idr`, `compiler/src/IdrisMLIR/Types.idr`, `compiler/src/IdrisMLIR/MLIR/**`, `compiler/src/IdrisMLIR/MLIR.idr`, `compiler/src/IdrisMLIR/Loc.idr`, `compiler/src/IdrisMLIR/Ids.idr`, `compiler/src/IdrisMLIR/Registry/**`, `compiler/src/IdrisMLIR/Registry.idr`, `compiler/src/IdrisMLIR/Facts.idr`, `compiler/src/IdrisMLIR/SyntaxSamples.idr`, `tests/compiler/**` | idris-emit-1, idris-emit-2, idris-emit-3, idris-emit-4, idris-emit-5, idris-emit-6, idris-emit-7, idris-emit-10, idris-emit-11, idris-emit-12, idris-emit-13, idris-emit-14, idris-emit-16, idris-emit-17, idris-emit-18, idris-emit-19, idris-frontend-13, idris-emit-8, idris-frontend-18, lists-1, mlir-7 |
| L21 | Frontend translation: shapes, primitives, refusals and terms by their types | `compiler/src/IdrisMLIR/Frontend/Translate/Cases.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Errors.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Forced.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Given.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Primitives.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Programs.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Shapes.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr`, `compiler/src/IdrisMLIR/Frontend/Resolve.idr`, `compiler/src/IdrisMLIR/Frontend/Translate.idr`, `compiler/idris/src/Idris/Host.idr` | idris-frontend-1, idris-frontend-2, idris-frontend-3, idris-frontend-14, lists-2 |
| L22 | Frontend state and checker: one place per definition, quantities by one view | `compiler/src/IdrisMLIR/Frontend/Growth/**`, `compiler/src/IdrisMLIR/Frontend/Growth.idr`, `compiler/src/IdrisMLIR/Frontend/Finite.idr`, `compiler/src/IdrisMLIR/Frontend/Program.idr`, `compiler/src/IdrisMLIR/Frontend/Profile.idr`, `compiler/src/IdrisMLIR/Frontend/Driver.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Closed.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Instances.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Keys.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Recursion.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/State.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Types.idr`, `compiler/src/IdrisMLIR/Proof/**`, `compiler/src/IdrisMLIR/Frontend/Walk.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Dictionaries.idr` | idris-frontend-5, idris-frontend-6, idris-frontend-12, lists-3, idris-frontend-11, cleanup-1 |
| L23 | Idris libraries and test machinery: typed primitives, identities by name, one source of tests | `harness/Fuzz.idr`, `harness/Gen.idr`, `harness/Lock.idr`, `harness/Main.idr`, `harness/Prims.idr`, `harness/Runner.idr`, `harness/Sem.idr`, `harness/TwoLevels.idr`, `harness/lib/**`, `tests/runner/**`, `libs/**`, `tests/two-levels/**`, `tests/fuzz/**` | idris-frontend-4, idris-frontend-7, idris-frontend-8, idris-frontend-9, idris-frontend-10, idris-frontend-15, idris-frontend-16, idris-frontend-17, lists-4, legacy-7, legacy-8, legacy-9, legacy-10 |
| L24 | Array, closure, IO and platform ops: one yield rule, linear captures, the world's operands | `foreign/idr/include/idr/IR/IdrArrayOps.td`, `foreign/idr/include/idr/IR/IdrClosureOps.td`, `foreign/idr/include/idr/IR/IdrIOOps.td`, `foreign/idr/include/idr/IR/IdrPlatformOps.td`, `foreign/idr/include/idr/IR/Arrays.h`, `foreign/idr/lib/IR/OpsArrays.cpp`, `foreign/idr/lib/IR/OpsClosures.cpp`, `foreign/idr/lib/IR/OpsGenerating.cpp`, `foreign/idr/lib/IR/OpsPlatform.cpp`, `foreign/idr/lib/IR/OpsTabulate.cpp`, `tests/tie-shape-dims-fold/**`, `foreign/idr/lib/IR/OpsFolds.cpp`, `tests/arrays-byte-buffer/**` | ir-ops-2, transforms-b-13 |
| L25 | Legacy tests and benchmarks: one program per benchmark, one fixture per table, tools out of tests/ | `bench/**`, `tests/bench/**`, `tests/programs/**`, `harness/README.md`, `tests/upstream-idris/**`, `tests/compile-times.sh`, `tools/upstream-idris/**`, `tools/compile-times.sh`, `tests/determinism-rbtree/**`, `tests/determinism-threads-rbtree/**` | legacy-1, legacy-2, legacy-3, legacy-4, legacy-5, legacy-6 |
| L26 | The fork's SyntaxInfo knot: a pragma is first-order data the processor interprets | `compiler/idris/src/TTImp/TTImp.idr`, `compiler/idris/src/TTImp/ProcessDecls.idr`, `compiler/idris/src/Idris/Desugar.idr`, `compiler/idris/src/Idris/Syntax.idr`, `compiler/idris/README.md` | selfhost-1 |
| L27 | tools/self.sh: a stage is the frontend, then the pipeline on its kept module | `tools/self.sh` | selfhost-2 |
<!-- /lanes-table -->

The coordinator owns the hubs (CMake, ipkg, `Makefile`, `tools/**` less
L27's `tools/self.sh` and the two tools L25 moves there, `PINS.md`,
`upstream/**`, `tests/spec/**`, `tests/upstream/**`, `tests/ACCEPTANCE.md`),
the generated Idris modules, `proposals/**`, `HANDOFF.md`, `IdrDialect.h`
and `IdrBytecode.td` (S28: each lane's hunk comes in its handoff), and
integration (§8). Since 2026-10-18, `bench/**`, `tests/bench/**` and
`tests/programs/**` are L25's and `tests/fuzz/**` is L23's. Not owned by
any lane, and so the coordinator's if a lane's change reaches them:
`tests/accept/**`, `tests/reject/**`, `tests/toolchain/**` other than
L19's directories above, `tests/determinism/**` other than L25's two.

## 7. Latent bugs (each a lane obligation with a discriminator)

| Bug | Finding | Lane | Discriminator |
|---|---|---|---|
| A nullary boxed `idr.con` that reaches lowering unfolded gets a heap cell its take never frees | ir-ops-6 | L02 (L07 lowers the atom) | a fixture with a nullary boxed constructor taken after idr-rc: no allocation in the lowered module (`--idr-contracts` property or lowered-IR check) |
| The verifier accepts an IO root `(!idr.world) -> (!idr.world, i64)`, which idr-entry treats as an exit status | conversion-8 | L08 (S38: L03's `rootKind`) | a verify fixture refusing that root, and the frontend's `IORes` root and the e2e `(!Unit, !idr.world)` root still verify |
| A memref with a non-identity affine layout gets different field counts from two of four descriptor walks | conversion-3 | L07 | one walk; a lowering fixture with such a memref |
| A nested sum that fails to define passes a null `DataType` to `held()` before the failure is read | transforms-a-12 | L12 | the failure is a value the recursion returns; a defunctionalization fixture with a failing nested sum refuses cleanly |
| The verifier accepts the bare world carrier used twice (`!idr.world_carrier` counts as quantity many; `!idr.world` used twice is already refused, `tests/world-once/world-once.mlir`) | ir-verify-3 | L04 | a fixture with `idr.func @f(%w: !idr.world_carrier) -> (!idr.world_carrier, !idr.world_carrier) { idr.return %w, %w : ... }`, which verifies at the base; after, the spelling does not parse. The existing world-twice fixture does not discriminate and stays |
| Inlining a never-returning callee leaves a dead second block, and two such inlines in one caller leave the second call in the dead block | ir-verify-1 | L03 (L11 erases, S5) | the two-callee inline fixture: a caller that calls two never-returning callees in sequence has, after idr-inline and after idr-contify, one block and verifies; a hand-written two-block `idr.func` is refused |
| A call to a function whose only effect is crash loses the IO write an inline `idr.crash` keeps | ir-verify-6 | L03 | an effects fixture comparing the call and the inline crash |
| DataRemap's content key ignores boxes and leaves below a field's top, so two remaps can name two types alike | ir-ops-7 | L17 | one decision of what a field becomes; a remap fixture with two remaps of one kind |
| A hole at a non-box field is caught only by an `assert` | ir-ops-8 | L02 | a verify fixture refusing it in a release build |
| idr-stack's box test skips linear boxes | transforms-b-1 | L02 (S36; L13's stack step reads it) | a stack fixture placing a linear box on the stack |
| An exclusive token cannot be parsed where a reuse takes it: `tests/lower-exclusive/lower-exclusive.mlir:13` and `tests/expect-tests-nothing/expect-tests-nothing.mlir:18` do not parse at HEAD | found by L02's drafter (S3) | L02 | `idr.cell.recycle` of an `!idr.excl<!idr.token>` round-trips; both fixtures, rewritten to S3's cell ops, parse and pass |
| `onlyAtoms` (`Verify/Uses.cpp:101-108`) accepts an in-place run whose boxed cells hold atom fields | found by L15's drafter (S4, S18) | L15 | a new `verify/only-atoms.mlir`: at `stage(owned)`, a constant in-place `!List` of two cells taken by an `idr.dup` at the excl grade is refused ("takes an exclusive reference to a value that reaches cells other than atoms"); it verifies at the base |
| Following `idr.share` as a structural source would prove a shared cell exclusive and update it in place (the trap S11's `Idr_SameValue` closes) | analysis-4 (S11) | L04 (L10's fixture) | a fixture where a box reaches its use only through an `idr.share`: its cell is never recycled or updated in place, and Exclusivity proves it nothing |
| The frontend refuses `prim__negate` at fixed widths, which Prims and Fuzz generate | idris-frontend-3 | L21 | a program that calls `prim__negate_Int8` (and the `Bits8` and `Int64` ones) directly compiles and negates; `negate x` on an `Int8` is not it, since the prelude writes that `prim__sub_Int8 0 x` and it compiles at the base; `tests/fuzz/seed-*` compile |
| TwoLevels claims every primitive and covers about 297 of 353 | idris-frontend-7 | L23 | TwoLevels enumerates `Prims.prims` itself; the count equals it |

Fixed-width negate is a translation, not a semantic choice: Idris defines
`prim__negate` on a fixed width as two's-complement negation, which is the
dialect's subtraction from zero in that width, as subtraction is emitted
today (L21).

## 8. Acceptance (the conjunction) and integration

`every lane's producer ∧ every consumer adapted ∧ every predecessor deleted
∧ discriminating evidence ∧ bounded scope ∧ integrated qualification`.

1. **Source review** by the coordinator against each dispatch: the selected
   representation built, the named predecessor deleted (grep finds no old
   name), no bridge, no extra.
2. **C++:** after every lane lands, in this order. (a) Apply S28's hunks and
   reconcile every `CMakeLists.txt` source list with the tree: `typecheck`
   compiles only the files a list names, so a new file (`CallCycles.cpp`) is
   unchecked until its line is added, and a deleted one fails configure; the
   lanes' handoffs give the lines. (b) ODS first: build only
   `IdrRuntimeAbiIncGen` and `IdrOpsIncGen` (`cmake --build --preset
   typecheck --target IdrRuntimeAbiIncGen IdrOpsIncGen -- -k 0`), because one
   TableGen error in any of the eight lanes' `.td` files stops every C++
   unit and masks all other errors; errors go to the `.td`'s lane, repeat
   until both build. (c) `tools/dialects.sh generate typecheck`. (d) Then
   `make typecheck` (every part); `errors.log` has one error per line, each
   file belongs to one lane (`ownership.json`), and an error whose
   declaration and definition are in two lanes' files (a §4 seam) goes to
   both lanes with the contract text; repair dispatches repeat until green.
   `make check` passes. The integration is staged so: hubs, then the ODS
   targets alone, then generation, then C++.
3. **Fixture rewrites** (§9 B7): the coordinator runs one script over every
   fixture for the printed forms that change wave-wide: S2's default
   (`default(%d: T)`), S6's effects (`effects = #idr.effects<X>` in an
   attribute dictionary becomes `effects<X>`, before an `idr.func`'s symbol
   and after an `idr.call`'s arguments), S18's constants, S3's cell ops and
   S4's take split; the lanes' handoffs give the rules. Lanes edit those
   lines in their own fixtures and never in another lane's.
4. **Idris on Chez:** the frontend, the libraries and the test machinery
   build on the stock host; over `tests/programs`, `tests/accept` and
   `tests/reject`, the integrated frontend's status, stdout and stderr equal
   the base's, and its Core equals the base's except where a finding changes
   what Core holds (S23, S24) or how a refusal is carried (S25, rulings A1
   and A7, §9 B8: the frontend prints no refusal and writes them into the
   module, so a refused program's stdout and stderr change and
   `tests/reject/*/expected` change with them, written by their owners, the
   coordinator for `tests/reject/**`; the Chez gate compares the output the
   driver would print from the module's refusals), each such difference
   named in the lane's handoff; the self compile's frontend step still exits
   0. The base is a commit that holds the checker
   (`compiler/src/IdrisMLIR/Frontend/Growth.idr`, untracked when this packet
   was compiled): the Idris lanes' `git archive HEAD` must contain it.
5. **Runtime** (ruling A3): during the swarm L19 builds the runtime privately
   with host clang, from `build/typecheck/compile_commands.json` and the
   base's `idris_rt_ops.h` regenerated privately, and runs every property
   program and the `rc` mode (on the base: 52 units, every program exits
   0). At integration the coordinator rebuilds it against the regenerated
   `idris_rt_ops.h`, where a finding that changes the ABI (S15's buffer
   entries and helper declarations) is checked, and reruns them.
6. **Discriminators:** each §7 bug's fixture exists, marked
   `NEEDS-ACCEPTANCE` where this machine cannot run it.
7. **The owner's build:** `make build`, `make test`, `make test-idr`,
   `make test-unit`, `make test-mlir-tools` on both targets, accepting the
   marked files. This packet is not qualified until then.

Evidence kinds stay separate: source review, behaviour on Chez, the
typecheck, and the owner's build; none substitutes for another.

## 9. Decisions

The owner's rulings are settled; nothing else here is. The owner insisted
that no agent's choice be recorded as settled design, so every decision the
coordinator or a drafter made is listed apart, for the owner's review before
dispatch.

**The owner's rulings** (asked and answered, 2026-10-17):

| ID | Date | Ruling | Where |
|---|---|---|---|
| A1 | 2026-10-17 | D1 adopted: refusals are records (idris-frontend-1). It reverses one line of 0002 §4.4 (refusals printed as prose, the report carrying only the verdict) | S25 |
| A2 | 2026-10-17 | Review D-C: the dead block after inlining a never-returning callee is erased at our two call sites (L11), once after the whole inline loop. Upstream's own inliner leaves that block to a cleanup after it, so this is upstream's shape, not a workaround | S5 |
| A3 | 2026-10-17 | Review D-D: the runtime lane builds the runtime privately with host clang (compile commands from `build/typecheck/compile_commands.json`; the base `idris_rt_ops.h` regenerated privately) and runs its property programs; findings that change the ABI are checked against integration's regenerated header | §0, §8.5 |
| A4 | 2026-10-17 | Cells are explicit after counting (the owner's MLIR-native pick, over folding reuse into con, transforms-b-2, and over an interface over two ops, ir-ops-5; the former P1) | S3, S36 |
| A5 | 2026-10-17 | mlir-12 adopted, an extreme hard cutover: `idr.call` carries its own effects, as `llvm.call` carries `memory_effects`. The second effects API is hard-deleted, every reference (the `CalleeEffects` table and its readers, `effectsOf(CallOp, ...)`, the call-effects lookups), with our hand CSE (`Optimize/PureCalls.cpp`) and the canonicalizer wrapper bound to a table; upstream CSE, DCE and canonicalization do that work once calls declare their effects. The effects pass writes each call's effects; S7's `effectsOf(CallOp, const CalleeEffects &)` export is withdrawn | S6, S7 |
| A6 | 2026-10-17 | mlir-5 adopted: `idr.take` splits into one op per meaning over the three operand kinds mlir-5 names, each with its own declared effects | S4 |
| A7 | 2026-10-17 | S25's transport: the frontend writes each refusal as a typed attribute in its module (`#idr.refusal<rule, loc, message>`, L17 declares it); the driver re-emits each through `idr::refuse(loc, rule)`, so the existing `foldDiagnostics` alone decides the verdict and writes the report; no text lines are parsed | S25 |
| A8 | 2026-10-17 | The owner's direction: "hard cutover. don't be afraid to churn massive portions of the codebase to be representation first to map well onto mlir", and "push the heavy lifting to mlir, and push harder on our types" | the whole packet |
| A9 | 2026-10-18 | `tests/spec/time-trace` is deleted; the coordinator deletes it, and `.gitignore:8`, itself | coordinator |
| A10 | 2026-10-18 | The 72 generated `programs/semantics/prim-*` directories fold into one fixture driven by `Sem.idr`'s list | legacy-8, idris-frontend-9, seam P (L23, L25) |
| A11 | 2026-10-18 | `tests/fuzz-two-hosts` becomes seeded programs with committed expected output derived from each program's meaning, never a run-time comparison against Chez | legacy-7 (L23) |
| A12 | 2026-10-18 | The test runner's dependency on `contrib` and `test` (`harness/harness.ipkg`) is an open item after this wave, in no lane | none |

**0002's D13 is reversed.** D13 ("calls hold no effects": a call's effects
kept only on its callee, transforms-b's kept list) was recorded in 0002 as a
decision; it was never the owner's ruling. Ruling A5 replaces it: a call
holds its own effects, verified to contain its callee's.

**Decided by the coordinator on 2026-10-18 for L23 and L25 to L27, not yet
reviewed by the owner** (the defaults the rulings A9 to A12 left, and how
the drafter carried out 0003's decided D3 and D6):

| ID | Decision | Where |
|---|---|---|
| E1 | `bench/ackdyn` is deleted everywhere; the kept record keeps its rows, as measured | legacy-1 |
| E2 | The six benchmark programs copied as fixtures build from `bench/<name>/Main.idr`, one program per benchmark; the three drifted linear ones settle on `Linear.Vec`, the form `bench/README.md` states | legacy-2 |
| E3 | `io/system-info` loses its BSD and Windows arms: two arms over `tools/host.sh`'s host names, its count `ncpu_total` | legacy-3 |
| E4 | The stale documents are cut to the tree (`bench/README.md`, `bench/records/README.md`, `bench/run.sh`'s citation, `bench/lib` copy and `rejected` mark, `harness/README.md`'s layout) | legacy-4, legacy-6 |
| E5 | `tests/upstream-idris/` and `tests/compile-times.sh` move to `tools/` | legacy-5 |
| E6 | `tests/registry-only` and `tests/hot-loop` stay where they are | none |
| E7 | The libm list is one list, `libm_symbols` in `harness/lib/heap.sh`, allowed to every test; the pools' `symbols` files go (their other four names are the runtime's imports) | legacy-10 |
| E8 | A11 is carried out as one fixture whose program prints `Fuzz.twoHosts` (Gen's checks and the generators' output for fixed seeded requests), its `expected-stdout` committed after a review of each section against its definition; the fixture runs no stock host | legacy-7 |
| E9 | D3 is carried out as `Pragma`, first-order data in `TTImp.TTImp`, interpreted by `processPragma`, declared in `TTImp.ProcessDecls` and defined in `Idris.Desugar` (the mechanism `TTImp.Elab.Check.processDecl` already uses); `Pass` moves to `TTImp.TTImp` | selfhost-1 |
| E10 | `tools/self.sh`'s limits: the frontend half 1800 s (about five times the measured 345 s; debt for the native stages), the pipeline half 7200 s (debt: never measured) | selfhost-2 |

**Still the owner's to decide:**

| ID | Choice | Recommendation | Trade-off |
|---|---|---|---|
| D2 | analysis-9: a function's effects become an ODS property (and, under A5, a call's) | adopt | the frontend never writes a solved effect (it writes the default), and the generator leaves a default-valued property that is no attribute out of its builders, so `upstream/25` is not reached: its note is that a property which is no attribute written into a dictionary stays a discardable attribute with the property at its default (the pinned `getInherentAttr`/`setInherentAttr` cover attributes and segment sizes only). `NamedEnumProp` prints and parses itself, so `Idr_EffectAttr` goes (S6); the cost that remains is L03's hand printer and parser for `idr.func`. If `NamedEnumProp` inside `DefaultValuedProp` fails to round-trip on the owner's build, L03 escalates and the property becomes `NamedEnumPropWithAttrForm` over `Idr_EffectAttr` (kept then; L17 deletes nothing) |

**Decided by the coordinator, approved by the owner before dispatch (2026-10-17: "rip it")**
(update 3 §B and §E, the drafters' round-2 corrections, and the packet's
earlier P2 to P5; none is settled design until the owner has reviewed it):

| ID | Decision | Reason |
|---|---|---|
| B1 | Stack placement and idr-rc's steps: idr-rc is a registered pass pipeline of registered passes (mlir-13, mlir-14), in order cells, stack, grades (sets `owned`), place (where reuse rewrites `cell.new` into `cell.recycle`, reading the cached `Reuses`), exclusive, `symbol-dce`; the separate idr-stack pass that ran before idr-rc is deleted (S3, S27). Update 3 §B's first order (exclusivity, borrows and reuse, then counting) is corrected by L13's round 2 | stack cells are promoted where cells exist and before reuse, so Reuses and Exclusivity see stack cells and "stack beats reuse" holds; exclusivity reads the dups placement makes (`Rc.cpp:15`); the buffer boundaries are in the grades step because an `idr.own.adopt` is owned (`IdrOwnershipOps.td:195`), which the verifier refuses before the owned stage (`Program.cpp:230`) |
| B2 | S22: the specializer's keys stay uniqued MLIR attributes; holes lose their index; a raise key holds its consumer by reference to the uniqued form, a uniqued `StringAttr` digest naming its entry in the run's table of forms | C++ values would rebuild the uniquer (the audit); no form is parsed back from printed text |
| B3 | S11: `sourceOf` never looks through `idr.share`, by the trait `Idr_SameValue`, which `idr.share` lacks; a memo part is `Field`, not `Made`; Exclusivity keeps its own edge search | a share carries `ResultCarriesOperand` but forgets exclusivity: following it would prove a shared cell exclusive (§7); a trait states it, so no `isa` tests the op |
| B4 | S2: the default region is first, `MaxSizedRegion<1>`; S1 gains `caseOf` and the builders' signatures; every reader of `getRegionNumber()` as a case index goes through `caseOf`; printed `default(%d: T) { ... }` | ODS allows a variadic region list only last |
| B5 | S3's refinements: holes and destinations leave `idr.con` for `idr.cell.init`; `cell.init` infers its results (the plain box at creation, its type printed only when it differs); `cell.recycle` has exactly `memref.realloc`'s effects; `!idr.cell<box type, tag>` has no grade, is linear by type, is not counted and refuses an atom; the producer writes the header and `cell.init` the fields; the cell ops are legal from the cells step, at stage `first`; `idr::buildsCell` (S36) | the drafters' and both audits' corrections |
| B6 | The root rule (conversion-8): `rootKind(FunctionType, Stage)` (S38) admits the roots real programs have and refuses the `(!idr.world) -> (!idr.world, i64)` misreading; L07 adds `holdsNoComponent` | the finding's narrower IO form would refuse every program the frontend emits and every e2e IO fixture |
| B7 | Fixture rewrites: the printed forms that change wave-wide (S2's default, S6's effects, S18's constants, the cell ops, the take split) are rewritten by the coordinator with one script at integration; lanes do not hand-edit those lines in other lanes' fixtures, and do edit them in their own (§8.3) | one rule per form, applied once, instead of every lane editing the same lines in files it does not own |
| B8 | S25's transport, completed (update 3 §E): L20's `ModuleRefusal` and `Emit.refused` writing the `idr.refusals` module attribute; one channel (the frontend prints no refusal, the driver prints each once); Idris's own errors as refusals of a new rule `Elaboration` in a new user-error category (S29(c)); exit status 3 no longer a verdict | every frontend failure is typed and `foldDiagnostics` decides every verdict. For the owner: the base's `Idr_RuleCategory` has two cases and a comment calling them the only two, and AGENTS.md names the same two kinds of refusal, so `UserError` is a third kind; and `refusalHead` (`Attrs.cpp`) writes `unsupported (<phrase>)` for every rule, so an elaboration failure reads `unsupported (elaboration): ...` unless the head follows the category; a refusal of the user-error category prints Idris's own message under the rule name, never "unsupported (...)", which stays the head of the unsupported category |
| B9 | S27: the stage check comes only from upstream's pass `baseClass` (`StagedPass`); `idr::addStageCheck` (update 3 §C) is withdrawn | it would repeat the base class's check |
| B10 | The typed token (a token type that carries its constructor or its size) was considered and not adopted | reuse admits any constructor of the same size, and the size is the target's layout, so a type would duplicate that and move the check, not remove it |
| B11 | Contracts given to the findings update 3 named as having none: transforms-b-13 is S35, ir-verify-7 is S41, ir-ops-10 is S42, conversion-13 is S43; and the consumer seams of ir-verify-16 and mlir-19 are S44. ir-verify-12 and ir-verify-17 are out of this wave (below) | a cross-lane correction with no contract is written by two lanes against two guesses |
| B12 | mlir-9 is withdrawn: the default region's argument stays a fresh binding that upstream does not forward; S2 states that its predecessor is not declared, and S11 reads it as `Same` by our own rule. Recorded as withdrawn in `mlir-audit.md` | the matches register upstream's region-branch canonicalizations (`OpsMatch.cpp:192,200`); given the edge, `ControlFlowInterfaces.cpp:718-760` would replace the argument by the scrutinee, a second use of a linear value the match consumed, and `:859-990` would erase an unused argument together with the scrutinee operand, against P2 |
| P2 | A match's default region always binds the scrutinee | a linear scrutinee is consumed by the match, so the region must rebind it; one form, no optional binding |
| P3 | Interfaces live in `IdrInterfaces.td` (L05 writes them from §4's text) | one generated interface header; the implementing lane writes the methods |
| P4 | analysis-14 (Borrows on `DataFlowSolver`) is in the wave, last in L10 | the owner's directive covers it; L10 lands its other findings first and keeps Borrows' API, so a stalled analysis-14 blocks nothing |
| P5 | Fixed-width negate is translated, not refused | §7 |

**Decided by the coordinator during the run** (2026-10-18; for the owner's
review, each recorded where the code holds it):

| ID | Decision | Reason |
|---|---|---|
| R1 | A new stage `graded` between `first` and `owned`: idr-rc-grades sets it, idr-rc-place runs at it, idr-rc-exclusive sets `owned`; `StageFacts` gains `grades()` beside `counted()` | between grading and counting the IR is graded but not counted, and the count walk would refuse every owned parameter; the state is real, so it is named, and no nested pipeline returns (mlir-14) |
| R2 | `setEntry` is deleted; `writeEffects` is the one writer of a function's and its calls' effects | raising a function's effects without its calls' leaves calls the verifier refuses |
| R3 | `CallCycles` gives every function a component, one without a body its own, on no cycle | lookups are total; no guard at any reader |
| R4 | `CellType::isCellPointer()` is true; `holdsReferences` and `isCounted` false; `Carriers::of` gives a cell its box's carriers | a cell is one non-null pointer to a cell its producer headed; its flow is its box's |
| R5 | `ofType` gives a type with no integers upstream's width-0 maximum range | an uninitialized range stops inference for every op reading a box or a string |
| R6 | Every staged pass is `runOnProgram(ProgramOp program)`, handed the program `StagedPass` found | no pass looks the program up again |
| R7 | The flow rule admits a part of the op's own result as an edge's `from` | a fold's loop-carried accumulator; escape analysis needs the edge |
| R8 | Effects print bare: `effects<io, crash>` (upstream's unquoted bit enum) | readable IR, no printer of ours |
| R9 | `idr.world.new` and `idr.crash_str` lose the primitive mark | neither is an Idris primitive; the frontend has `NewWorld` and `CrashWith` |
| R10 | The fork's `DLY` cell and the growth check's display are plain data, with the fork's `SyntaxInfo` (selfhost-1) | the pipeline's closure analysis found both on a cycle through a cell; a stored `Core` action is the state the data makes unrepresentable |
| R11 | Forced reads a clause place through the fork's own `argToPat` (`Idris.Host`) | one reading of what a pattern place tests, Idris's |

Open for the owner: a covering literal match with no default is still
refused with `match` (the frontend never builds `LitNoDefault`); and the
fuzz shrinker halves a draw with `divNatNZ`, which never finishes on a
draw near 2^64 (a fast division with an erased proof, or Bits64 draws).

**Out of this wave** (for the owner's review). Each stays in
`ownership.json` with its lane, which keeps the base's form, builds nothing
of the correction and says so in its handoff.

- **ir-verify-12** (L15): the owned stage's crossings into upstream's buffer
  ops become `idr.own.load`, `idr.own.store` and `idr.own.alloc`. Its
  producers are outside L15: the ops are L02's ODS, idr-rc's grades and
  placement steps and bufferization write them (L13), the lowering expands
  them before upstream's memref lowering (L07, L08), and their flow edges
  are L17's. This wave already rebuilds exactly that code (B1's split of
  idr-rc, S3's cells, S43's trait on `own.adopt` and `own.give`), and the
  finding's discriminator ("it cannot be written") checks only the verifier's
  half. Written after B1 lands, the three ops are made once, by the split
  steps.
- **ir-verify-17** (L01): case-of-case's profit rule as an op interface
  (`meets`). Feeds' ladder decides on a pair, the value's producer and its
  consumer (string builders under a guard, a closure and its apply, a call
  result's elimination), with helpers private to `Canon/Feeds.cpp`
  (`eliminationAt`, `reader`, `writtenInPieces`, `closedWith`, `foldsWith`).
  An interface on the consumer alone either exports those helpers to the six
  op owners (L01, L02, L03, L05, L16, L24) or keeps every body in
  `Feeds.cpp`, where the drift the finding names stays. In this wave S6
  changes the call arm, S41 deletes the closure arm and S44 moves the string
  arms onto `StrBuilderOpInterface`; what remains of the ladder is known
  only after. L01 keeps `feeds()`, adapted to S1, S3, S41 and S44.

## 10. Packet files

- `ownership.json`: each lane's title, exclusive writes, exclusions and
  findings (the authority for §3 and §6).
- `parts/representation.md`, `parts/common.md`, `parts/rules.md`, and
  `parts/lanes/<lane>.md`: assembled by `assemble.py` into
  `dispatch/<lane>.md`, with the owned findings and the consumer
  adaptations quoted from [findings/](findings/).
- `validate.py`: checks this packet (§11).
- `orchestrator.md`: the coordinator's run sheet.

## 11. Validation record

<!-- validation -->
<!-- /validation -->
