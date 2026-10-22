# Recheck 3 fixes: the lanes' handoffs



=== 
L07 has three findings in recheck 3. I fixed two; the third needs no work because the first fix deletes the line it names. Nothing was built or run (D56).

1. **The `Counts` enum restated `Release`** (`include/idr/Transforms/Counting/Facts.h`): **fixed.**
   - I deleted `Counts` and `countsOf`. The eight `countsOf(x) == Counts::Counted` checks now call `freedBy(x, Release::Counted)` from Grades.h: `Expand.cpp`, `Placement.cpp` (two), `PlacementRewrite.cpp`, `PlacementWalk.cpp` (two) and `ReuseAssign.cpp`.
   - The `switch` in `Placement::classify` now reads the hold itself: no hold or `Static` places nothing, `Scoped` makes the value Scoped, `Counted` makes it Owned. Its comment now carries what the deleted enum's comment said.
   - Who frees a value is now held only in the grade's hold. The duplicate enum and the mapping from one enum to the other are gone. I also dropped the header's unused `ErrorHandling.h` include; no file that includes it uses that header.
   - In the same spirit, `isCountedValue` (`lib/IR/Counting/Ops.cpp`) loses its `holdsReferences(value) &&` test. GradedType's verifier already ensures a hold exists exactly when the carrier holds references, so that test re-checked a verifier rule. It is now `freedBy(value, Release::Counted)`.
   - The audit counted 17 references; the tree had 9, and none is left anywhere outside `audits/` and `proposals/`.

2. **D112, the `llvm_unreachable` at `Facts.h:61`**: **not done as a separate change.** It only asked to delete an `llvm_unreachable`, which D114 now allows, and the line went with `countsOf` in finding 1. INT's D91 note on the same line is gone for the same reason.

3. **C192, `own.adopt` was legal from the frontend's stage** (`compiler/spec/IdrisMLIR/Spec/Counting/Declarations.idr`): **fixed.**
   - Its legal window is now `between First Owned`. First is the stage bufferization runs at (`Pipeline.idr`), and bufferization is the op's only writer.
   - So a program at the frontend's stage can no longer hold one. The Idris builder generator (`written = legalAt op.stages Higher`) stops writing a builder for it. The op's doc comment now says why.
   - No test, harness file or unit test writes `own.adopt`.
   - **Seam (L16, or the specgen run):** `compiler/src/IdrisMLIR/Dialect/Idr.idr:1006-1010`, the `ownAdoptOp` builder, must go. That file is a hand copy of the generator's output, and the generator no longer writes it. Emit never calls it.
   - **Seam (INT):** the generated `Generated/` TableGen picks up the new window when the generator is run.

**Files for INT:** none added, moved or deleted.

**HEAD:** f5d46b5e at start, ee142e85 at finish. The four commits in between touch none of my files.


=== 
Five of my six findings are dealt with: four fixed and one already settled by the coordinator. The sixth, C101, is left because it needs changes in three other lanes first. Nothing was built, typechecked or run.

HEAD at start: f5d46b5e. HEAD at finish: 2501ca2f. The four commits in between were the coordinator's or other lanes', and none touched my files.

**Stale op name, `include/idr/IR/Numeric/Domain.h:16`: fixed.** The comment now says `idr.int.div_s`.

**C111, the nonempty and finite conditions written twice: fixed.** Each is now one function in the numeric template, used by the folder, the interval decision and the lowering.
- `Numeric/Inline.h` gains `nonempty(d, length)`, which is `nonzero` of the runtime's character count, and `finite(d, bits)`, which tests that the Double's exponent field is not all set. Each has a function object, `Nonempty` and `Finite`.
- `OpsChecks.cpp` gets the length through `lengthOf` and the bits through `bitcastToAPInt`, then calls the template.
- `Conversion/Checks.cpp` calls the same template over arith. `math.isfinite` is replaced by `arith.bitcast` plus the template. This loses nothing: LLVM's InstCombine turns exactly this bit test back into `llvm.is.fpclass` (`InstCombineCompares.cpp:1920-1944`).
- In the spec, `GuardCondition` gains `LengthNonzero` and `BitsFinite`, and the two guard ops now name the template condition instead of their own code. The holds-string guard keeps its own code, since only the run knows what a handle holds.
- `Numeric/Checks.h` gains static_asserts for each case, including the infinity bits checked against C++'s own double.
- The two new conditions now join the list of meanings the interval unittest checks (`unittests/Intervals.cpp`, L15's); that file needs no change.

**C120, `known(bool holds)`: fixed.** It is gone.
- `bigNonzero` now reads `numeric::nonzero` over the Integer constant taken as a one-value interval at its own width, which gives `Known` directly.
- `nonempty` and `finite` convert the template's word truth with `knownOf(numeric::Bit)`, so no plain C++ bool test feeds a `Known` any more.

**C113/C158, `spec/Ops/Values.idr:7`: fixed.** The module doc now says `idr.platform.os`.

**C110: no change.** The coordinator corrected C110 in recheck 3: the header stays in `include/idr/IR/Numeric/`, which the runtime includes.

**C101, `spec/Ops/IO.idr:161`: left, waiting on three seams.** The spec's ABI kinds have no 8-bit kind, so the exit row cannot say `idris_rt_exit(uint8_t)` yet.
- L03: `Spec/Core/Ods.idr` `OperandKind` needs an unsigned 8-bit kind that the generator spells `uint8_t` and passes zero-extended, as `TakesBool` is.
- L21: `Conversion/RuntimeCalls.cpp` `LowerExit` must truncate the status to i8 after its 0-to-255 test.
- L11: `runtime/End/End.cpp:323` must take `uint8_t` and drop its cast.
- Then I change the exit row from `[TakesInt64]` to that new kind.

**Outside my findings:** the D103 skeleton-rule finding cites my `spec/Ops/Rewrites.idr`, but it belongs to L14 and L12 (`Memory.idr`).

**Files for INT:** none added, moved or deleted. The generated `InlineMeanings.h.inc` gains `Nonempty` and `Finite` when regenerated.

Changed files:
- `foreign/idr/include/idr/IR/Numeric/{Domain,Inline,Checks}.h`
- `foreign/idr/lib/IR/OpsChecks.cpp`
- `foreign/idr/lib/Conversion/Checks.cpp`
- `compiler/spec/IdrisMLIR/Spec/Ops/{Numeric,Checks,Values}.idr`


=== 
L08, recheck 3. HEAD was f5d46b5e at start and 696f6752 at finish. Recheck 3 gave L08 three findings: two are fixed, one is left. Nothing was built or run.

**C202: idr-rc-exclusive could change the type of an upstream op's result. Fixed.**
- The bug was real. `exclusivity::followed` (`include/idr/Analysis/Ownership/Walks.h`) only skipped values that an upstream op reads. It did not skip an element that `tensor.extract` or `memref.load` produces, and `writeVersion` could then retype it.
- There is now one shared check, `ownership::upstreamElement` in `Facts.h`. `followed` uses it, and so does the in-place rule (`Chains.cpp`), in place of its own inline copy.
- `ub.poison` is still followed: it reads nothing, so C202 lets us choose its type.
- To keep this sound I also changed `ExclusivityGraph.cpp` `readInto`. When a counted value is read out of a part, the value it came from is now marked shared based on the read value's type. Before, this only happened if exclusivity followed the read value.
  - Without this, an element no longer followed would stop marking its array shared.
  - Side effect: it also fixes an older gap from 17e1e026. A counted field read that an upstream op then reads used to leave its holder unshared, so the holder could be proved exclusive while a second reference existed. It is now marked shared. This only makes the analysis more conservative.
- For upstream elements the solve's answers do not change. They were already marked shared, so the gap was only that the representation allowed the wrong state.
- State made unrepresentable: the type writer can no longer reach an upstream element.

**C178 / §5.2: pointer-keyed maps in `Unique.cpp:218` and `UniqueResults.cpp:207`. Fixed.**
- Both private `DenseMap<Value, Local>` maps are gone. Both files now use the solver's one shared numbering (`solver::Numbering`, through the new `unique::Locals` in `Unique.h`), which the footprint counts and which is freed with each body.
- Branch deleted: `Body::values` is gone. Forwards now carry their numbers, and node layout reads the numbering's finished result.
- I deleted `ownership::forEachValue`. `forEachFollowed` and `forEachJoinParameter` now use `solver::inWalkOrder`, so every numbering of a body uses one walk order instead of two that each called itself "the one walk".
  - L07's `Counting/Borrows.cpp` uses `forEachJoinParameter` on the same terms as the analysis, so its numbers change together with it. No edit is needed there.

**C32 (shared with L14): Borrows to be measured on patched upstream storage (patch 77) first. Left.**
- It needs a stage-1 measurement (bytes per anchor, all four targets), which needs a build.
- Borrows already runs on the solver layer's marking (`Borrows.cpp:41-43`), so whether that order still holds may need the coordinator or owner to decide.

**For INT:** no files added, moved or deleted. Modified:
- `foreign/idr/include/idr/Analysis/Ownership.h`
- `foreign/idr/include/idr/Analysis/Ownership/Facts.h`
- `foreign/idr/include/idr/Analysis/Ownership/Walks.h` (now includes `Analysis/Solver/Extraction.h`)
- `foreign/idr/include/idr/Transforms/InPlace/Unique.h`
- `foreign/idr/lib/Analysis/Ownership/ExclusivityGraph.cpp`
- `foreign/idr/lib/Transforms/InPlace/Chains.cpp`
- `foreign/idr/lib/Transforms/InPlace/Unique.cpp`
- `foreign/idr/lib/Transforms/InPlace/UniqueResults.cpp`
- `foreign/idr/lib/Transforms/Ownership/Exclusive.cpp`

**Seams:** none.


=== 
Lane L06, recheck 3. HEAD at start f5d46b5e, at finish 9c6beaa7 (other lanes committed in between). Nothing was built or run, and I made no git write in the repository.

**Findings**
- **D55, tuple has no diff:** fixed. I added `upstream/fork-tuple-node/` with a README and `pull-request.diff`: e5b39cb2's tuple hunks, laid against the Idris pin (89ba32eb). The pin's commit is not in our checkout, so I downloaded its 16 files from GitHub; each matched the base version the other fork diffs record. I merged the hunks three ways and rewrote the conflicts against upstream's text (`Functor.idr`, `Ambiguity.idr`, which had to use upstream's `delayOnFailure`, and `TTImp.idr`). `git apply --check` passes on those files. PINS tuple-node, upstream/README.md (now eighteen fork entries, plus a table row) and fork-ambiguity-depth's README now point to it.
- **D49/D67, generated modules carry stamps (settled by C229):** fixed in `tools/dialects.sh`. `generate` writes no stamp, and `check` regenerates each module with the built `idris-mlir-tblgen` and compares it with the committed file. The fingerprint code and `mlir-tblgen` go.
- **D15, `tools/check-units.py`:** deleted. Nothing called it, and `make typecheck-cxx` already compiles every unit (ninja `<unit>.cpp^` builds one).
- **PINS stale entries:** all fixed.
  - :163 now names `Lower/Functions.cpp` and `TailCalls.cpp` instead of `TailCallPlan.cpp`.
  - :142 and :1031 drop Borrows, which runs on no MLIR solver.
  - :1084 gives TypeGraph's real path, and :275 drops the deleted `TwoLevels.idr`.
  - :487 (inline-unreachable) now says the e-graph's match rules leave `ub.unreachable`, names the real `inlineCall` site and idr-inline, and has a status line.
  - :711 names the passes that really run pipelines: idr-optimize, idr-narrow, idr-inline.
- **Patch READMEs naming deleted passes or paths:** fixed in 19, 04 and 81. The same staleness also turned up in 30, 77 and 18, fixed too.
- **`tools/licenses.sh`, unused fixture names:** fixed. `live-cells`, `default-stack` and `constant-stack` go; no file has those names and nothing reads one. `targets` stays because `harness/Main.idr:154` reads it.
- **C99, upstream recursion patches:** left. They wait on the stack painting, which needs a stage-1 build.
- **fork-parser-bounds README:** fixed. It now says the fork's parser is upstream's deep embedding again. No other patch plan reasoned from the shallow parser.
- **Not in the findings, fixed:** `tools/compile-times.sh` read rows for idr-rc, Canonicalizer and CSE, none of which exist any more. Those dead rows are gone, and it now reports idr-simplify's rows.
- **Not in the findings, for the coordinator:** `tools/host.sh` (`peak_memory`) and `tools/bootstrap.sh` (the lock) each still embed a Python one-liner. Under C229's rule that is Python of ours; I left both for a ruling.

**Seams**
- **L16:** the 13 committed modules under `compiler/src/IdrisMLIR/{Syntax,Dialect}/` and `Encoding/Builtin.idr` each still end with a `-- fingerprint:` line, which must go. INT's first `tools/dialects.sh generate` rewrites them without it, or L16 strips the line.
- **L19 (or INT's Makefile):** C229 wants a test-mlir-tools check that runs `tools/dialects.sh check`, for example `tests/dialects-current/run`.

**Files for INT:** deleted `tools/check-units.py`; added `upstream/fork-tuple-node/README.md` and `upstream/fork-tuple-node/pull-request.diff`. No Makefile or CMake file calls anything I removed.


=== 
All five L09 findings are handled: three are fixed outright and two need one change each in another lane's file. HEAD was f5d46b5e at start and is 9c6beaa7 at finish; none of the commits in between touch my files. Nothing was built or run.

1. **cxx-rules: phase 3 of the lowering (`Matches.cpp:386-396`) rebuilt its patterns and target per function — fixed on my side, needs L21.** The patterns and target now live in a new `conversion::ControlFlowLowering` struct in `Matches.h`, built once. `lowerControlFlow` takes it as a second argument, and `populateJoinLoweringPatterns` is gone (its only caller was inside that function). Until L21 makes this change, `Lower.cpp` will not compile:
   - **L21, `foreign/idr/lib/Conversion/Lower.cpp`:** `struct Lowering` gains a `ControlFlowLowering controlFlow;` member, initialised with `*program.getContext()`.
   - `lowerFunction` then returns `lowerControlFlow(fn, lowering.controlFlow)`.

2. **C178 and §5.2: the value map in `IdenticalRegions.cpp:43` — partly fixed, partly left.**
   - **Fixed:** a new `Body` class numbers a region once, however many regions it is compared with (before, it was renumbered for every pair). Its map and table now use `footprint::DenseMap` and `footprint::Vector`, so the pass's footprint counts them.
   - **Left:** the map is still keyed by `Value`. Comparing two bodies needs a link from each value in one to its partner in the other, and MLIR gives values no dense number; upstream's own region comparison keeps the same map.
   - **To finish it,** either L14's `solver::Numbering` (`Analysis/Solver/Extraction.h`) gains a constructor over one region's body with a lookup that can miss for values defined outside it, or the coordinator rules the map essential.

3. **C144: `holdsUndecided` in `YieldedFields.cpp` — fixed on my side, needs L03.** What the rule really needs is that nothing it touches lives in a lifetime. It now checks that directly: the split result and every constructor field must not be `scoped`. Under that condition the lifetimes the match states keep their positions, so the rule is sound at every stage and no longer reads the stage table at all.
   - Gating on `countingAt` instead, as the audit suggested for L12's reader, would have been wrong: the Graded stage has lifetimes but no counting yet.
   - **L03, `Spec/Pipeline/Stage.idr`:** `StageHolds`, `holdsClosed`, `holdsAt` and the `holdsAt` column of `stageFacts` now have no C++ reader (L12's moved to `countingAt`), so they can be deleted.

4. **C109: stale "world" vocabulary — fixed.** Reworded the comments at `FlowEdges.h:266-268` and the header of `FlowEdges.cpp`.

5. **C120: `rewriteIf(bool holds)` — fixed.**
   - Each rule's `decide` now returns the positions it found in its `Rewrite`: unused results, unreached join regions, regions with an unread parameter, the single jump's target, the cases that read their key.
   - Each `rewrite` acts on those positions and skips any that no longer hold on the root as it then is.
   - The three rules with nothing to choose (`LoopToJoin`, `DeadDefault`, `AllExits`) return an empty `Rewrite` from their own branch.
   - Removed: `rewriteIf`, `someResultUnused`, `someRegionUnreached`, `someParameterUnread` and `unused`.
   - Added: `choose`, `unusedResults`, `dropUnused`, `reachedTargets`, `unreachedTargets`, `unreadTargets` and `targetPosition`.

**Not in my section, noted:**
- The D75 conjecture marked "With L09" is filed under L18 (`Contify.cpp`); I left it.
- `lib/IR/Ops/Rules.cpp:56` (L13) has its own copy of `eraseAfter`, which `idr::control::eraseAfter` already provides.

**For INT:** no files were added, moved or deleted. The edited files are:
- `foreign/idr/include/idr/Conversion/Matches.h`
- `foreign/idr/lib/Conversion/Matches.cpp`
- `foreign/idr/include/idr/Transforms/Joins/Rules.h`
- `foreign/idr/lib/Transforms/Joins/{Rules,JoinRules,MatchRules,IdenticalRegions,YieldedFields}.cpp`
- `foreign/idr/include/idr/IR/FlowEdges.h`
- `foreign/idr/lib/IR/FlowEdges.cpp`


=== 
L20, recheck 3. HEAD was ee142e85 at start and fa62f1e4 at finish; the coordinator committed in between. Nothing was built or typechecked (D56).

L20 has one finding in recheck 3, the D104 entry in `rulings-D56-D111.md`. No other recheck 3 file has a finding for `libs/`.

**D104: `thawBack` said it copies nothing, but it did copy.** Fixed. The finding was still true on the live tree. `thawBack` called `LArray.thaw`, whose body is `k (Writing (copied x))`. That copies every element on the stock host, and the frontend's translation of it copies under idris-mlir. D104 says the buffer is thawed back in place, so I changed the code to match the comment rather than delete the comment.
- `libs/mlir-array/Array/Core.idr`: adds a handle type, `Frozen.Frozen r s a`, whose constructor `Held` is visible only inside this module. Two operations go with it:
  - `Frozen.read`, which reads one element and gives the handle back.
  - `LArray.withFrozen`, which freezes a linear array behind a handle for a fresh region `r`, runs the continuation, and turns the returned handle back into the linear array. It rewraps the same slots and copies nothing on either host.
- `libs/mlir-array/Linear/Bytes.idr`: `Bytes r n` now holds the byte count and that handle (`Lent n bytes`). `withBytes` goes through `withFrozen`, and `peek`, `copy` and `matches` read through `Frozen.read`, passing the handle along. `freezeIn`, `frozenAs` and `thawBack` are deleted. The exported API is unchanged, so `Linear.Parser` and the benchmarks need no edits.
- **What is now unrepresentable:** thawing in place while something else still reaches the bytes.
  - The only way to the frozen array is the use-once handle, and the continuation must give it back.
  - The continuation's result cannot name the fresh region.
  - The only thing a read hands out is an element.
  - So when `withFrozen` rebuilds the linear array, nothing else holds its slots, and `withFrozen` is the only place that rebuild happens.
- Both new functions compile from their bodies (`!!` already has its registry entry), so no registry row is needed.
- I added this API to `Array.Core` under D101 and D104, which leave the library's shape to this lane. It is listed here for the coordinator to review.

**Not mine, for reference:**
- L16, `compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr` (`AThaw`, `fresh`): `LArray.thaw` is still translated as a fresh tabulate even when its argument is dead. This is L16's own recheck 3 finding (the D104 entry under L16), and the benchmarks' first thaw of an unrestricted array still goes through it. Proposal 0009 says thaw "copies unless its argument is dead". The fix there is to emit `Writing x` and let bufferization decide whether a copy is needed.
- The array `withFrozen` puts back is never proved unique, because `Held` holds it unrestricted. So under idris-mlir, whether a write after the thaw happens in place is bufferization's decision. `foreign/idr/lib/Transforms/Bufferize/Linear.cpp:19-21` already says it decides that way. It is safe either way and stays in place when nothing reads the bytes later. Proving it would take a stage-1 measurement.
- The D44 entry in `rulings-D1-D55.md`, that `mlir-relational` has no reader, is filed under L16 because the frontend has to consume it. Nothing changes in `libs/`.

**Files for INT:** none added, moved or deleted. Edited: `libs/mlir-array/Array/Core.idr` and `libs/mlir-array/Linear/Bytes.idr`.


=== 
HEAD at start: f5d46b5e. HEAD at finish: 9d8e76c7 (the new commits were other lanes'). Nothing was built, typechecked or run.

**Fixed**
- **Dead tblgen helpers:** `traitsOfClass`, `markOf`, `operandNamed`, `resultNamed` deleted.
- **tblgen reading C++ spellings (D51):** op attributes are now told apart by upstream's records. The `attrRows` table names each def or class once, resolved once per run, and matched by identity or `isSubClassOf`. `UnitAttr`, `Index` and `AttrSized*Segments` are compared as defs. A bit enum is read through its base attribute class. A parameter given as a string is only its C++ spelling, so those spellings are one table, each written once. The `::…Type` guess (for the deleted box) is gone; such a parameter is now listed as not generated.
- **C229:** the generator writes no stamp. Module headers now say `make test-mlir-tools` regenerates and compares them.
- **ResultUsesMax:** `idr::ResultUsesMax<Result, From...>::Impl` added in `IR/Traits.h`; it checks the uses rule.
- **C78:** the specification's fingerprint is now its printed value (every output, in order), not its source files.
- **C144:** `StageHolds`, `holdsAt` and their column deleted. Both C++ readers had already stopped reading it.
- **C116:** new `RunDeciding` pipeline node (decide step with `kind = Decide`, plus its apply group). `narrow` decides, `narrowWords` is its group, and specgen prints `idr::pipeline::applyGroupOfIdrNarrow`.
- **Adaptor form chosen by string compare (`Ods.idr:319`):** new `InfersTypes InferredOnly | AlsoCompatible`; `InferType` removed from `UpInterface`.
- **Dialect namespace compared as text (`Cpp.idr:184`):** a header block is now `DialectNamespace | Nested (List1 Ident)`.
- **Dead `inIdr`, `builtUpType`:** deleted. `odsDialect` is not deleted; it is now used to print the dialect records `Ods.idr` spelled by hand six times.

**Seams (path: what it must become)**
- L06 `tools/dialects.sh`: stop appending and reading `-- fingerprint:`.
- L16: 13 committed Syntax, Dialect and Encoding modules still end in a fingerprint line, removed when INT regenerates them. `MLIR.idr:60-81` `HandType`/`HandAttr` and the hand bytecode path should use the generated constructors; the hand `DataOf` is missing `binders`.
- L12 `Narrow.cpp:226-228`: call `applyGroupOfIdrNarrow(nested)` from the new `ApplyGroups.h.inc`.
- `Declares InferType [...]` must become `InfersTypes`:
  - L07 `Counting/Declarations.idr`: `InferredOnly` at :216 and :237, `AlsoCompatible` at :327 and :427.
  - L18 `Closures/Memo.idr:132` and L04 `Families/Ops.idr:150`: `InferredOnly`.
- `("idr" ::: [], …)` must become `(DialectNamespace, …)`:
  - L05 `Grades/Declarations.idr:306`, `Lifetimes/Declarations.idr:716`
  - L04 `Families/Dialect.idr:131`
  - L01 `Effects/Declarations.idr:38`
- `("idr" ::: [x], …)` must become `(Nested (x ::: []), …)`:
  - L13 `Ops/Numeric.idr:209`, `Ops/Platform.idr:211`
  - L11 `Runtime/Endings.idr:332`, `Layout.idr:26`, `Clocks.idr:69`

**Left**
- **C156 `nodesPerOp`:** needs the stage-1 measurement.
- **C42:** needs L21 to make the lowering a function pass (plus a program step that sets `Lowered`), or a coordinator amendment of C42.
- **D108:** the admission is L14's.

**Nothing to do**
- **C7:** the coordinator corrected it.

**Wrong**
- **"No Idris printer for the six family declarations":** `encodersModule` (`Generator/Idris.idr:705-729`) prints every type and attribute, these six included (`Families/Declarations.idr:20-23`), into `IdrType`/`IdrAttr`. The duplicate is L16's hand mirror.

**For INT:** one new generated output, `foreign/idr/include/idr/IR/Generated/ApplyGroups.h.inc`, needs wiring and a manifest entry. `StageFacts.h.inc` changes when regenerated. No files moved or deleted.
