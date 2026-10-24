<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Recheck 3: the second seam batch's handoffs


=== 
L01 had nothing left to close. I made no edits, and no files were added, moved or deleted.

**(1) Seams addressed to L01:**
- **`Effects/Declarations.idr:38`** (L03's seam in fixes-b.md: `("idr" ::: [], …)` becomes `(DialectNamespace, …)`): already done by a8ec2839. Line 38 reads `( DialectNamespace`, and it fits the live `Namespace` and `Header` types in `Spec/Core/Cpp.idr:39-48`.
- seams-a.md addresses nothing to L01.

**(2) Items my own handoff left:**
- **No recheck-3 handoff:** L01 has none in fixes-a.md or fixes-b.md, and no recheck-3 finding. cxx-rules.md:98 lists L01 among the lanes with no finding.
- **Earlier handoffs (`handoffs/L01*.md`):** their queued items are done. `effects::acquires` and `effects::mayAcquire` are both in the tree, and nothing in `compiler/spec/` was left waiting on a seam.
- **`std::unreachable()` at `IR/Effects/Vocabulary.h:190`:** left. It sits after a switch over every case. cxx-rules.md lists it only as "noted, not counted", and D114/D115 let our C++ assert.

**Re-checked against the live tree (reading and grep only, nothing built or typechecked):**
- **Removed or renamed names:** L01's files no longer use any name that another lane removed or renamed in recheck 3. Among them are `InferType`, `"idr" :::`, `holdsAt`/`StageHolds`, `licensesDropOrMove`, `symbolUse`, `callsItself`, `SymbolTable`, `ruleTable`/`ruleClosed` and `Query.h`.
- **Records:** `MkInterfaceDef`, `MkMethod … DelegatesByClass`, `MkHeader`, the `Declarations` update and `MkResourceDef` all match L03's current record shapes.
- **D112:** there is no `internal`, `assert_total`, `assert_smaller`, `believe_me`, `partial` or `covering` in `Spec/Effects/`.
- **Stock-host rules:** no lambda has a typed binder (`\(x : T) =>`) and none has a `::` pattern. Globals in types were already made qualified (3689b354, f5d46b5e), and no L01 file has changed since a8ec2839.
- **Comments:** none cites a rule or section number, names a pass that no longer exists, or uses the "world" vocabulary.

**HEAD:** ea7ce403 at start and at finish.


=== 
HEAD was ea7ce403 at start and is ea7ce403 at finish. Nothing was built, typechecked or run, and I made no git write. The recheck-3 batches hold no L05 handoff, so I took L05's open recheck-3 findings as my own leftovers, as L02 did. All three were still in the live tree.

**Seam addressed to L05**
- **Namespaces at `Grades/Declarations.idr:306` and `Lifetimes/Declarations.idr:716`:** already done by a8ec2839. Both now read `DialectNamespace`, and no `"idr" :::` is left in my spec files.

**L05's findings with no handoff**
- **`idr::ownership::readThrough` had no caller (cxx-rules):** closed. I deleted the declaration and its comment in `foreign/idr/include/idr/IR/Ownership.h`, and the definition and its comment in `foreign/idr/lib/IR/Verify/Uses.cpp`. `bufferOf`, `readFrom` and `viewRoot` keep their other callers. The function is deleted outright.
- **`LifetimeKind::isHome` had no caller (cxx-rules):** closed. I deleted it from `foreign/idr/include/idr/IR/Lifetimes.h`. A home is still read through `fold`, `kindCase` and `passesAs`. `isView`, `isRoom` and `isCursor` keep their callers.
- **`fieldGrade` had no use (idris-and-tests, in `compiler/spec`):** closed. I deleted it from `compiler/spec/IdrisMLIR/Spec/Grades/Grade.idr`, along with the Grade accessor `uses`, whose only caller it was. Nothing in `compiler/src` or the harness calls that `uses`; the `uses` the frontend and Emit read is a record field or a local name. The C++ composes a field's grade from the generated `usesTimes` and `holdReadsOnce`/`holdReadsMany` tables, so the law is still stated once.
- After these deletions, a grep of the whole tree finds no `readThrough`, `isHome` or `fieldGrade`.

**For the coordinator:** `Grade` and `bare` in `Grade.idr` have no reader in any code, only the doc comment in `Grades/Declarations.idr`. The audit did not flag them, so I left them.

**Files for INT:** none added, moved or deleted. Edited:
- `foreign/idr/include/idr/IR/Ownership.h`
- `foreign/idr/include/idr/IR/Lifetimes.h`
- `foreign/idr/lib/IR/Verify/Uses.cpp`
- `compiler/spec/IdrisMLIR/Spec/Grades/Grade.idr`

No seams are open for other lanes.


=== 
HEAD was ea7ce403 at start and at finish. Nothing was built, typechecked or run, and I made no git write. I closed one item; four were left, waiting on L03 or a design decision, and one was already done.

**L09's `eraseAfter` seam (`lib/IR/Ops/Rules.cpp:56`): closed, though not the way L09 proposed.**
- I could not call `idr::control::eraseAfter`. It lives in IdrJoins, and IdrJoins links IdrIR, so calling it from IdrIR would make the two libraries depend on each other.
- Instead, the one copy is now mine in IdrIR: `idr::eraseAfter`, declared in `idr/IR/Ops/Rules.h` next to `neverEmpty`, which the Joins rules already read from there.
- `MatchRules.cpp` already includes that header, so its call now finds `idr::eraseAfter` first. It compiles either way, and with no ambiguity.
- **Seam for L09:** delete `idr::control::eraseAfter` from `Transforms/Joins/Rules.h:41` and `Rules.cpp:89-96`, and have `JoinRules.cpp` include `idr/IR/Ops/Rules.h`. Their copy's `dropAllUses()` isn't needed: a region has one block until the lowering, and the rewriter checks that no erased op still has a user.

**Left:**
- **C101, the exit row at `Spec/Ops/IO.idr:162`:** still `[TakesInt64]`. `Core/Ods.idr:106` still has no 8-bit operand kind (L03), and changing the row first would not match the runtime's generated prototype.
- **`EliminatesOperand` on `io.put_str`:** L03 has not declared the trait in `Spec/Core/Interfaces.idr` or `IR/Traits.h`. Naming it now would break the spec.
- **The interface for the op ladder in `IdentitiesRecord.cpp` (`nat.pred`, `big.add`):** no interface is declared yet. What it returns, and whether `data.con` (L04) shares it with the natural successor and predecessor, is a choice of an API's shape, so it goes to the coordinator or owner first.

**Already done:**
- **Dialect namespace:** `Ops/Numeric.idr:209` and `Ops/Platform.idr:212` already read `Nested (… ::: [])`.
- **D103:** L12 has already added the skeleton rules in `Spec/Arrays/Memory.idr`.

**Files:** none added, moved or deleted. I edited `foreign/idr/include/idr/IR/Ops/Rules.h` and `foreign/idr/lib/IR/Ops/Rules.cpp`.


=== 
L15, closing the recheck-3 seams. HEAD was ea7ce403 at start and at finish. I built, typechecked and ran nothing, so none of the edits below has been compiled.

**Closed**
- **L14: `depthFirst`'s stack is now counted** (`foreign/idr/include/idr/Support/Nest.h`).
  - The stack is now a `footprint::Vector<std::pair<Node, Way>>` instead of `llvm::SmallVector<…, 32>`, so its heap shows up in the footprint of the run doing the walk. `pop_back_val` is replaced by a move from `back()` followed by `pop_back()`. The header now includes `idr/Support/Footprint.h` instead of `SmallVector.h`.
  - State made unrepresentable: a walk's stack, which grows with the input, can no longer take heap outside the footprint.
  - Cost: the 32 inline slots are gone, so each walk now makes at least one heap allocation. Nobody has measured this.
  - `Footprint.h`'s comment now lists the walk's stack among what it counts. The test in `Footprint.cpp` already covers `footprint::Vector`, so I left the tests alone.
- **L14: `Memory.h`'s comment no longer says the optimizer reads it.** The only reader left is idr-simplify's `HostArenas` (`Simplify.cpp:70`), and the comment now says each function's e-graph is admitted against this memory by its arena, whichever pass builds it.

**Already done**
- **L13's note that `unittests/Intervals.cpp` needs no change: confirmed.** The test checks every meaning in the generated `numeric::Meanings`. `nonempty` and `finite` only use operations that its test domain (`Guarded`) already has (`constant`, `bitAnd`, `equal`, `negation`), so no edit is needed.
- No file I own uses any symbol another lane deleted in recheck 3. `graph.callsItself`, which `Calls.cpp` calls, still exists in `ProgramGraph.h:122`.

**Left**
- **L04's `foldDialect` (whether `Support/Match.h` gets an overload that folds an `mlir::Type`):** this still needs the coordinator to pick between that overload and a type interface in the spec. Nothing in `proposals/` or `audits/` records a decision. The recheck-3 audit (`cxx-rules.md:34`) leans towards the interface and L04 recommends the overload. Once it is decided, `Match.h` is mine.
- **§5.2 library layering** (`IdrSupport` links MLIR; `Actions.h`, `Profile.h` and `Remake.h` include MLIR): this is routed to INT with L15, and L14 also left it for the coordinator and INT. It stays open until they decide.
- My recheck-3 batch has no L15 handoff, and I own nothing under `compiler/spec/`, so there was nothing of my own to carry over.

**Files:** none added, moved or deleted. Edited:
- `foreign/idr/include/idr/Support/Nest.h`
- `foreign/idr/include/idr/Support/Memory.h`
- `foreign/idr/include/idr/Support/Footprint.h`


=== 
L03, recheck 3 seams. HEAD was ea7ce403 at start and at finish. Nothing was built, typechecked or run, and I made no git write.

**Closed**
- **`EliminatesOperand` trait (L04's seam, raised in fixes-a and again in seams-a):** I declared `eliminatesOperand : TraitDef` in `Spec/Core/Interfaces.idr` and added it to `core.traits` in `Spec.idr`. The empty class `idr::EliminatesOperand` is now in `IR/Traits.h`, whose header comment I updated. No op carries the trait yet, so no C++ reads it until the next three steps land:
  - L09 puts it on `data.match`, L13 on `io.put_str`, L04 on `data.field`.
  - L04 then turns the lambda at `Symbols.cpp:76-84` into a single `hasTrait` test.
- **C101, an 8-bit ABI kind (asked by L11, L13 and L21):** `OperandKind` in `Spec/Core/Ods.idr` gains `TakesUInt8`. In `Generator/Cpp.idr`, `takesC` prints it as `uint8_t`, `takesName` as `UInt8`, and the printed `OperandKind` enum now includes it. Seams that are still open:
  - L13: the exit row at `Ops/IO.idr:162` should use `[TakesUInt8]`.
  - L21: `Runtime.cpp` `llvmType` needs a `UInt8` case giving i8, or its switch stops compiling. `runtimeDeclaration` must set zext on `UInt8` as it does on `Bool`. `LowerExit` truncates the status to i8.
  - L11: `End.cpp:323` should take `uint8_t` and drop its cast.
  - L13: `Fold.h` `constantKinds` should exclude `UInt8`. Otherwise an op that folds and takes `UInt8` would read its constant through `doubleOf`.

**Already done**
- C116 (`RunDeciding`, plus L12's `applyGroupOfIdrNarrow` call).
- ResultUsesMax.
- C144: `StageHolds` is gone from the spec. It still appears in the generated `StageFacts.h.inc` until INT regenerates.
- The namespace and `InfersTypes` seams: none is left in the spec.
- D108, closed by L14 and L18.

**Left**
- **The op ladder in `IdentitiesRecord.cpp`:** the interface's method would have to return the analysis's `build::` values, which the IR layer cannot name. Choosing its shape is a call for the coordinator.
- **`count.take_into` claiming `unique self` after idr-rc-expand:** this needs a new stage or stage fact in `Pipeline/Stage.idr`, which is a call for the coordinator.
- **C42:** waits on the coordinator's amendment.
- **C156:** waits on a measurement.

**Files for INT:** none added, moved or deleted. Regenerating changes `RuntimeAbi.h.inc` and the runtime's ops header, and adds the trait's ODS def.


=== 
**L09, recheck 3 seams.** HEAD was ea7ce403 at start and at finish. Nothing was built, typechecked or run, and I made no git write.

1. **L14's seam, the value map in `IdenticalRegions.cpp`: closed.**
   - `Body` now uses `solver::Numbering<BodyValueTag, solver::Scope::Nested>` over its region. The tag is a new local `BodyValueTag` whose `Minter` is that numbering.
   - The comparison is `n ? partner[*n] == rv : lv == rv`.
   - The private `footprint::DenseMap<Value, unsigned>`, the hand walk that filled it, and the per-comparison `std::fill` are deleted.
   - `partner` is now an `IndexVector<BodyValue, Value>` local to each comparison. A match left over from an earlier comparison can no longer be read, so no reset is needed, and `sameAs` is now `const`.
   - The `#include`s of `Footprint.h` and `<algorithm>` are gone. `Extraction.h`, `Id.h` and `<optional>` are added.

2. **L04's seam, the `EliminatesOperand` trait on `data.match`: closed.**
   - L03's declaration (`Interfaces.idr:92`, `Traits.h:45`, `Spec.idr:233`) is in the working tree but not yet committed.
   - `matchOp` in `Spec/Control/Matches.idr` now lists `OurTrait eliminatesOperand`, with a short comment saying why.
   - My edit depends on L03's change landing.
   - Still open: L13 needs to add the trait to `io.put_str` (`Spec/Ops/IO.idr:68`, which still has no traits). L04 needs to add it to `data.field` (`Families/Ops.idr:148`, which still has `traits = []`) and then switch the `eliminates` lambda in `Symbols.cpp:76-84` to a `hasTrait` check.

3. **Phase 3 of the lowering built per function: already done** by L21. `Lower.cpp:103,116,227` holds one `ControlFlowLowering` and passes it in.

4. **L03 deleting `StageHolds`, `holdsAt` and `holdsClosed`: already done** in the spec. They survive only in the generated `StageFacts.h.inc`, which INT's regeneration removes. The `YieldedFields.cpp` fix (checking for scoped values instead of reading the stage table) still holds.

5. **D75, a missed promised join point: left.** It needs the owner or coordinator to choose which op holds the promise.

**Files for INT:** nothing added, moved or deleted. Edited `foreign/idr/lib/Transforms/Joins/IdenticalRegions.cpp` (it now includes `idr/Analysis/Solver/Extraction.h`) and `compiler/spec/IdrisMLIR/Spec/Control/Matches.idr`.


=== 
No seam in fixes-a.md, fixes-b.md or seams-a.md names L10, and L10 has no recheck-3 handoff in either fixes batch. Recheck 3 gave L10 one finding, and I left it, so I made no changes.

**C206 (decisions-C161-C224.md:75), the tail decider testing for a free reindex: left.**
- **Still open in the live tree.** `foreign/idr/lib/IR/Tail.cpp:27-31` still reads `dyn_cast<DataReindexOp>` → `isFree()`, and otherwise `hasTrait<ResultCarriesOperand>()`.
- **It can't move onto the existing trait.** C206 says a reindex is not `ResultCarriesOperand`, because that trait's readers mean a change of grade alone. So the decider really does have two cases: a change of grade, and a reindex whose types make it free. The fix is one interface that answers "gives its operand on with no run-time work", so no op is named. Choosing where that fact lives is an API-shape call for the coordinator.
- **Why it can't be done in my files alone.** If I declared the interface in my spec and switched the decider before `data.reindex` implements it, calls through a free reindex would silently stop being tail calls. That breaks the tail-call promise.
- **Proposed seam:**
  - Declare an op interface, e.g. `CarriesOnOpInterface` with one method `carriesOn()`. It could go in my `Spec/Tail/Declarations.idr` or in L03's `Core/Interfaces.idr`.
  - L04 implements it on `data.reindex` (`Families/Ops.idr:217`, defined by `isFree` in `Refinement.cpp:87`).
  - L03's `ResultCarriesOperand` class in `IR/Traits.h` derives from the interface's Trait. MLIR registers an interface from any base that has `getInterfaceID` and a model (`InterfaceSupport.h:148-152, 231-232`), so the fact is still declared once.
  - Then `carriesOn` becomes a single `dyn_cast` on the interface, used by Tail.cpp, `Tail/Context.cpp`, `TrmcRewrite.cpp` and `AccumulatorPlan.cpp`.

**Rechecked, nothing to do:**
- None of the symbols deleted in recheck 3 is still referenced in my files. The `callsItself` in `AccumulatorPlan.cpp:72` is a local helper, not the program graph's.
- `Spec/Tail/Declarations.idr` names nothing the spec changes removed (`InferType`, `":::"` namespaces, `holdsAt`).

**Files:** none added, moved or deleted. Nothing was built or run.

**HEAD:** ea7ce403 at start, 78272c93 at finish. The one commit in between is L03's change to `Generator/Ods.idr` and touches no L10 file.


=== 
L11 closed one item, did its part of a second, and left two; one more needed no change. Nothing was built, typechecked or run, and I made no git writes.

**C24, the null handle held twice: closed.**
- The new `Spec/Runtime/Handles.idr` holds the null handle once, as "every bit set" over `handleBits`. It gives it as `nullWord`, the unsigned word a program reads, and `nullHandle = -1`, the signed form the runtime uses.
- I also moved the standard streams there, as a closed set `StandardStream`, with `standardHandle` giving a stream's handle from its place in the set. Same defect in the same file: the frontend writes the literals 0, 1 and 2 and the runtime gets them from its seed order. C24 didn't ask for this.
- `Spec/Runtime/Declarations.idr` now prints `handlesHeader`, which becomes `Handles.h.inc`.
- On the runtime side, the hand constant `rt::io::nullHandle` is deleted (no alias). Every use now reads `idr::handles::nullHandle`. `environmentHandle` is now the slot after the standard streams instead of a literal 3. A `static_assert` checks that each stream sits in the seed at its handle. The handle prose in `idris_rt.h`, `Files.cpp` and `Handles.cpp` no longer restates the numbers.

**C101, `idris_rt_exit(uint8_t)`: my part done, the chain still open.** L03's `TakesUInt8` is now in the working tree (uncommitted). `End.cpp:323` now takes `uint8_t` and the cast is gone. This won't compile until L13 changes the exit row at `Spec/Ops/IO.idr:162` to `[TakesUInt8]` and L21 makes `LowerExit` in `RuntimeCalls.cpp` truncate the status to i8.

**L08's `Nested` namespace seam (Endings, Layout, Clocks): already done** in a8ec2839.

**D112's `llvm_unreachable` calls: no change needed.** D114 allows assertions in our C++.

**C201/C98 stack sizes per target: left.** They need the stage-1 measurement with INT.

**Seams:**
- **L16:** `Registry/Primitives.idr:242-244` should use `standardHandle StandardInput/StandardOutput/StandardError`, and lines 374 and 377 should use `LInt UInt64 nullWord`. Both need `import IdrisMLIR.Spec.Runtime.Handles`.
- **L03:** add the new module to `spec.ipkg` and to `Spec.idr`'s list of root imports.
- **L13 (optional):** the prose at `Ops/Platform.idr:11` and `Ops/IO.idr:109,116` still spells the handles as numbers.

**Files:**
- Added `compiler/spec/IdrisMLIR/Spec/Runtime/Handles.idr`.
- For INT: a new generated output, `foreign/idr/include/idr/IR/Generated/Handles.h.inc`, needs a manifest entry.
- Nothing moved or deleted. Edited: `Spec/Runtime/Declarations.idr`, `runtime/End/End.cpp`, `runtime/idris_rt.h`, and `runtime/Io/{Io.h, Handles.cpp, Files.cpp, Directories.cpp, Lines.cpp, Process.cpp}`.

**HEAD:** ea7ce403 at start, 78272c93 at finish.
