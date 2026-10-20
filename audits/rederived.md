<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Facts thrown away and derived again

The owner, 2026-10-19: "no throwing away source locations. check the code
base for any inappropriate rederiving of values that we already knew at
some point." Five read-only sweeps over 374e0e77's parent covered the
fork, the frontend and Emit, the dialect's IR and analyses, the passes,
lowering and driver, and the runtime, harness and tools. Each finding
below gives where the fact is known, where it is lost, where it is derived
again, and the fix that keeps it. The sweeps read code; nothing was run, so
the lane that takes a finding confirms it first, and deletes it here
(or marks it not a finding, with the reason) when it lands.

Every lost location changes what a user sees, not only a dump:
`Conversion/Runtime.cpp` (`crashMessage`) prints `at file:line:col` only
from a `FileLineColRange`, and the report's `file:line` field
(`Driver/Outcome.cpp`) the same way.

Paths under `compiler/` are the Idris side, under `lib/` and `include/`
are `foreign/idr/`.

## The fork's TTC and the frontend (arrays lane)

The root cause of most of the frontend's guessing: the fork's TTC is
lossy, and every definition the frontend reads, main's included
(`ModTree.idr` `buildDeps`: `clearCtxt`, then `readAsMain`), comes back
through it. The fork is ours; each loss is fixed in its encoder, with
`ttcVersion` bumped, and the frontend's reconstruction deleted.

How far the fork's TTC stops matching upstream's, and the care each kept
fact takes, is `compiler/idris/README.md`, "What a TTC keeps".

- **Term locations. Done, 374e0e77.** Each node's FC is written and read
  back. Still owed from it: the frontend's own rebuilt terms take the FC
  of what they rebuild instead of `EmptyFC` (`Translate/Closed.idr`
  betaAll, applyAll, pack/unpack; `Terms.idr` `settle`; `Shapes.idr`;
  `Growth/Sites.idr`; `Growth/Template.idr`), then `bestFC` and
  `Sites.siteAt`'s copy of the same fallback go, and reach refusals
  (`Profile.userFC`) are placed at the reference, not the referring
  definition.
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
  every field again. Make it `!idr.token<!idr.box<T>, @C>`, inferred by
  `TakeOp`, as `CellType` is; delete the four walks and all of `Fields`'
  pairing (the reuse pairing `reuseAt` decided is then in the type).
- **Static in the grade and in `madeStatic`.** idr-rc writes
  `Lifetime::Static`; `madeStatic` asks the defining op again and the
  verifier, Narrow, Placement and Classes trust it over the grade. Grade
  a value made from nothing static where it is made; keep `madeStatic`
  only for ungraded upstream buffers. (This is the WIP on main now.)
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
  rules; `TagOp::fold` never asks. One `knownConstructor(Value, at)` in
  `Canon.h`.
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
- **Data types carry no location.** `DataType::define` errors at
  `UnknownLoc`, and the knot refusal guesses one (first array, first
  located con, else the program). The body holds the declaration's
  location, written by the frontend and carried by DataRemap; `define`
  takes the caller's.

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
- **No stack probes against the 1 MiB guard:** set
  `"probe-stack"="inline-asm"` on program functions.
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
