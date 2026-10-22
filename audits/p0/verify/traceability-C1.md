<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Traceability: C1 to C95 against the tree

Done criterion: every decision in the proposal is implemented in the tree,
or recorded there as needing no code. Read from the code at HEAD
`2a60f4c6`. The working tree is dirty, and other lanes are editing it as
this is written. Read only: nothing was built. Paths are under
`foreign/idr/` unless a path says otherwise. Owners are from
`ownership.json`. Not counted against any decision: about 60 sources that
the CMake lists name are deleted files (INT, D111), and specgen has not
been run yet (see C78).

| Decision | Verdict | Where, or what is missing | Owner |
|---|---|---|---|
| C1 | Partial | Done: the backward marking (lib/Analysis/Ownership/Borrows.cpp), the forward reuse walk with rejoins (lib/Transforms/Counting/ReuseAssign.cpp) and `token.rebuild` (compiler/spec/.../Counting/Declarations.idr). `Uses.cpp` and the framework are gone. Still there: the cycle restriction that C1 deletes. `framed()` refuses a loan around a call on the caller's own cycle (Analysis/Ownership/Borrows.cpp:194-199, 359), and Ownership.h:127-129 and Counting/Borrows.cpp:23-27 state it. This also goes against D95 | L08, L07 |
| C2 | Needs no code (P0) | R1 to R5 govern 0007/0020 (kernel buffers, rings, foreign calls), and none of those is in P0. The typed rule `ReleasesForeign` exists (include/idr/IR/Effects/Vocabulary.h, Spec/Effects/Declaration.idr) | L01 |
| C3 | Implemented | `SuspendOp::fold` is gone (lib/IR/OpsClosures.cpp:14), as is `Idr_BuildsValue`. no-heap-allocation reads the declared heap `Allocate` (Expect/Allocation.cpp) | L01, L18, L19 |
| C4 | Partial | idr-accumulate works over the spec's laws (Tail/AccumulatorPlan.cpp, `laws::identityOf`). But `big.mul`, `big.and/or/xor` (Spec/Ops/Bigs.idr:145, 156-164) and `str.append` (Strings.idr:62) carry no `Associative`/`Identity`, so Integer `*`, bitwise Integer ops and string concatenation never accumulate. `&&`/`||` with their short circuit are not recognized | L13, L10 |
| C5 | Implemented | `[guard \| stack \| guard \| signal stack]` (runtime/Start/Runner.cpp:67-71). The host's signal minimum (runtime/Platform/{Linux,Darwin}/Host.cpp). The span aligned to 4 GiB and the bounded page map (runtime/Alloc/Cells.cpp:57-219). GMP built with malloc-reentrant and stack-clash protection (tools/bootstrap.sh:1055, 1090) | L11, L06 |
| C6 | Implemented | Registry rows import the spec's ops (compiler/src/IdrisMLIR/Registry/Primitives.idr). `Primitive` is gone from IR/Traits.h | L16, L03 |
| C7 | Implemented | compiler/spec, package idris-mlir-spec on base, with specgen as its executable (spec.ipkg:88-89). The frontend, harness and syntax-samples depend on it. The "second home" clause is moot under C6's replacement | L03 |
| C8 | Implemented | `PlatformOsOp::fold` reads the module's target (lib/IR/OpsPlatform.cpp:34-43). No greedy driver. The PAL error ends as an internal error (runtime/Alloc/Cells.cpp:50-55). Paths are POSIX in the fork (Libraries/Utils/Path.idr). audits/bugs.md records none of these yet, which waits for qualification | L13, L11, L17 |
| C9 | Needs no code | A policy on which C++ features to use. Its first half is superseded by D57 | — |
| C10 | Implemented | Partition refinement over `OperationEquivalence` (lib/Transforms/Deduplicate/Deduplicate.cpp) with upstream/79. Runs once, after knots (Spec/Pipeline/Pipeline.idr) | L18 |
| C11 | Implemented | Mnemonics carry their family prefix per C158. No unprefixed op class (`ConOp`, `DupOp`, `MatchOp` ...) remains | L03 |
| C12 | Implemented | No `!idr.box<` or `#idr.types<` fixture is left. The .mlir tests left are idr-expect and contract properties | L19 |
| C13 | Needs no code | sources/INDEX.md, with licences | coordinator |
| C14 | Implemented | `madeAt` over `Binding` and `Uses`, and `data Held` (compiler/src/IdrisMLIR/Emit/Monad.idr:90, 171). `mostUses` and `holdFor` are gone | L16 |
| C15 | Implemented | `kNoLimit` is gone. The refusal passes carry no budget (Transforms/InPlace/Rule.cpp:5). One OOM handler (include/idr/Driver/Tool.h:93) | L14, L11 |
| C16 | Implemented | tests/scale-threads, tests/determinism-threads-*, and unittests Calls, Rows and Refusals | L19 |
| C17 | Implemented | `Kind = Contract \| Faster \| Stricter` (Registry/Entry.idr:246), and tests/faster-rows | L16, L19 |
| C18 | Implemented | `#idr.given_back` on idr.func (lib/IR/Func/GivenBack.cpp). Transforms/Identity and the Returned solve are gone | L02, L14 |
| C19 | Implemented | Refinement per case (lib/IR/Families/Refinement.cpp, Unify.cpp). `DataFieldOp::getTag` reads the refined type (lib/IR/OpsConReads.cpp:49) | L04, L09 |
| C20 | Implemented | `TailKind` lowers to musttail under tailcc (lib/Conversion/Lower/Functions.cpp:164-216). TailPosition, TailCallPlan, Recursion and CallCycles are gone. One decider is kept, per C139 (lib/IR/Tail.cpp) | L10, L02 |
| C21 | Implemented | Grade parameters on `!idr.graded` (C162). The algebra is proved in Spec/Grades/Grade.idr, and `LifetimeKind` is in Spec/Lifetimes/Kind.idr. `holdsOwn` and `Lifetime = Heap \| Frame` are gone | L05 |
| C22 | Partial | Fit.cpp and the box emission are gone. The frontend never writes `idr.numeral.to_nat`/`of_nat`. `finToNat` and `natToFinLT` are still `IdentityOnLastArgument` rows (Registry/Faster.idr:98-99), translated as an identity from a `Fin` family to `!idr.nat` (Frontend/Translate/Terms.idr:1169-1180) | L16 |
| C23 | Implemented | Four shifts (Spec/Ops/Scalars.idr) and the `Signedness` enum (include/idr/IR/Numeric/Domain.h). `signed : IntTy -> Bool` is gone | L13 |
| C24 | Partial | Done: `io.clock <kind>` over one template (runtime/Io/Clock.cpp:21-47). `handle.is_null` and `clock_valid` are gone. Still there: `io.file_time` returns a handle, which `handle.file_time <kind>` reads field by field and `io.handle_free` frees (Spec/Ops/Platform.idr:206-252). The decision asks for one op with seven results | L13, L11 |
| C25 | Partial | `put_str (str.pack l)` is lowered without allocating (lib/Conversion/Strings.cpp:117-131). There is no allocation-free lowering of `io.put_str (str.show_*)`: no pattern in lib/Conversion names a show op | L13 |
| C26 | Implemented | `lin.cast` with `QuantityChange` (Spec/Grades/Declarations.idr:147, lib/IR/Lifetimes/Cast.cpp). `UseModel` and `isLink` are gone. The sharers are computed once (Bufferize/Releases.cpp:144) | L05, L12 |
| C27 | Implemented | `TransposeOp` is gone. The frontend writes `linalg.transpose` (Emit/Tensors.idr:418) | L16, L12 |
| C28 | Implemented | Each op family declares its `stages`. The pipeline is one typed list (Spec/Pipeline/Pipeline.idr). The hand .td files are gone | L03 |
| C29 | Implemented | Closure sums are families the pass declares (Defunctionalize/Declare.cpp), with `Mode = Memoized \| ByName`. `SlotTypeConverter`, `RetypePattern` and PatternsCalls.cpp are gone | L18 |
| C30 | Implemented | The label solve runs over a union-find of classes (lib/Analysis/Labels.cpp) | L14 |
| C31 | Implemented | Analysis/Effects.cpp's solve is gone. Rows are derived in defunctionalization's decision (include/idr/Analysis/Effects.h, Transforms/Effects/Writer.cpp) | L02, L18 |
| C32 | Partial | Patch 77 is carried, and Ranges and Constants stay on the framework. Borrows is already on the marking, but the number on the patched framework, which was to gate that move, is not taken (upstream/77-dataflow-state-storage/README.md:32-35: the qualification measures) | L14, L08 |
| C33 | Implemented | ProgramGraph over the one `mlir::CallGraph` (include/idr/Analysis/Solver/ProgramGraph.h), with patches 73 and 93. CallCycles, Recursion, Scc.cpp and ReadySet are gone | L14 |
| C34 | Partial | Done: `Id`, `IndexVector`, `Csr`/`GatedCsr`, the marking, `summarize` behind `extern template`, and `ReadsAnalyses` (Solver/Decision.h:54-59). Still there: `Exclusivity` and `Borrows` hand-write their `isInvalidated` (include/idr/Analysis/Ownership.h:85-87, 134-136) | L08 |
| C35 | Implemented | 06, 28 and 63 are submissions only (pull-request.diff, no .patch). Dead parameters and results are in Optimize/Demand.cpp and Results.cpp, and capture narrowing in CaptureDrops.cpp | L06, L18 |
| C36 | Implemented | Grade copies through the one clone-and-key template (include/idr/Analysis/Ownership/GradeCopies.h). `givesExclusive` is gone | L08 |
| C37 | Implemented | lib/Transforms/Counting/Placement*.cpp | L07 |
| C38 | Implemented | Emit writes `ModuloContext` (Emit/Bodies.idr:391). `!idr.dest` follows C167. The second `contextAt` is gone | L10, L16 |
| C39 | Implemented | `count.match_unique` is built only where the grade proves nothing (Counting/Expand.cpp), and the token ops are in Spec/Counting. `LowerTake` lowers `unique self` values only | L07, L21 |
| C40 | Implemented | No atomic count, and one kind per word (runtime/Rc/Rc.h:57). The encoding follows C168 | L11 |
| C41 | Implemented | Owned*.cpp and `effectsCovered` are gone. tests/verifier-every-pass, and patch 74 | L05, L02, L19 |
| C42 | Implemented | lower-runtime, then lower-statics, then idr-lower over each function in parallel, with no merge (lib/Conversion/Lower.cpp:1-21) | L21 |
| C43 | Partial | Patch 75 adds `StackSizeInBytes`, but the pool sets only `ThreadsRequested` (lib/Driver/Compile.cpp:166-168), so the workers keep OS-default stacks. No target entry defines `IDRIS_MLIR_TOOL_STACK_BYTES`, which include/idr/Driver/Tool.h:40-41 requires | L11, INT |
| C44 | Implemented | The prepared runtime's bitcode sits beside the object (lib/Driver/Prepare.cpp:65, ReadRuntime.cpp:255). `BitcodeHome` is gone | L11 |
| C45 | Implemented | optimize, then inline once on upstream's Inliner (Inline/InlinePass.cpp), then contify again (Pipeline.idr). `inlineStep` and `betaReduces` are gone | L18 |
| C46 | Partial | Keys are interned in an arena (Specialize/Arena.cpp), and the key attributes are gone. A node-table mutex remains (`Nodes::State::mutex`, include/idr/Transforms/SpecializeState.h:184), though C46 deletes it | L18 |
| C47 | Superseded | by D98 | — |
| C48 | Superseded | by D98 and D100 | — |
| C49 | Withdrawn | The pipeline runs no canonicalization before defunctionalization anyway | — |
| C50 | Partial | idr types and attributes are native in bytecode, and Syntax/Idr.idr is gone. But the families' encoding is hand C++ (lib/IR/Families/Bytecode.cpp, MemberBytecode.cpp), mirrored by a hand Idris writer (compiler/src/IdrisMLIR/MLIR/HandEncoding.idr). C50 has D48's family attributes derived and printed from the spec | L04, L16, L03 |
| C51 | Implemented | Primed binders, and one argument type per operand group (Spec/Generator/Idris.idr:30-61) | L03 |
| C52 | Partial | `idr::match` (include/idr/Support/Match.h) and the ban in .clang-tidy:21-24 are in place. Still in the code: 51 `get_if`, 17 `holds_alternative`, 47 `std::visit` and 1 `TypeSwitch`. Among them: lib/IR/Flow.cpp, include/idr/IR/FlowEdges.h, lib/Driver/Artifacts.cpp, lib/Analysis/LabelSites.cpp, Identities*.cpp, lib/Transforms/EGraph/*, lib/IR/Lifetimes/Proof.cpp, lib/IR/Verify/Uses.cpp, Counting/*, Narrow/Ops.cpp:148 and tools/idris-mlir-tblgen.cpp | L15, with each file's lane |
| C53 | Missing | No precompiled header: no `target_precompile_headers` or `-fno-pch-timestamp` in any CMakeLists | INT, L15 |
| C54 | Implemented | `_LIBCPP_HARDENING_MODE_EXTENSIVE` (CMakeLists.txt:326), with its handler (runtime/End/End.cpp:337) | INT, L11 |
| C55 | Implemented | The run-time tree, PartialEval.idr and the elaboration-time Transform.idr are gone from the fork (upstream/fork-no-runtime-tree) | L17 |
| C56 | Needs no code yet | Waits on stage 1. The derivation covers breadth (compiler/src/IdrisMLIR/Proof/Requests.idr) | L16 |
| C57 | Partial | The frontend writes no Core dump. But the harness still lists `core` as an artifact kind (harness/lib/compile.sh:110, 116), the prelude coverage reads prog.core (harness/lib/prelude.sh:7-14), and 321 expected files list `artifacts: core ...` | L19 |
| C58 | Implemented | `idr.refusals` is gone. Refusals are ops carrying a `Rule c` (Spec/Core/Rules.idr), read by lib/Driver/Run.cpp | L16, L03 |
| C59 | Implemented | Compiled code takes no probes. Runtime bodies drop theirs when joined (lib/Driver/LinkRuntime.cpp:84-85). The guard is checked when the program is built (lib/Driver/StackBound.cpp) | L11 |
| C60 | Implemented | The count symbols and environment reads are gone. The checked runtime has its own ending (runtime/End/End.h:107) | L11, L19 |
| C61 | Implemented | snmalloc is a patch project (tools/patches.sh:27), with patches 94 and 95. The seed-range hook is C100's span range (runtime/Alloc/Cells.cpp:57-90) | L11, L06 |
| C62 | Implemented | `programPrefix = "idr."` (include/idr/Conversion/Mangle.h) | L21 |
| C63 | Implemented | Frame chunks are given back with one spare kept (runtime/Alloc/Frames.cpp:38-48) | L11 |
| C64 | Implemented | widen-rows and write-rows run around nests (Spec/Pipeline/Pipeline.idr:503-523) | L02 |
| C65 | Implemented | `idr.join` and `idr.loop` are one family, the loop `LoopLike` (Spec/Control/Joins.idr:126-163), with the LoopToJoin rule (Control/Rules.idr:53). `may_loop` is not built: divergence is in the row | L09 |
| C66 | Implemented | The path rule by embedding (compiler/idris/src/Core/AutoSearch.idr:44-160) | L17 |
| C67 | Implemented | Megamorphic refusals are for growth only. The comment at harness/lib/prelude.sh:26 still says an implementation chosen at run time is refused | L16, L19 |
| C68 | Implemented | defunctionalize, knots, in-place and deduplicate run before any optimization (Pipeline.idr) | L18 |
| C69 | Implemented | The spec's declarations (`io.exit` writes `crash`, Spec/Ops/IO.idr:154-156) and tests/runtime-effects. `io.term_setup` is gone | L01, L13 |
| C70 | Implemented | The typed rules are in include/idr/IR/Effects/Vocabulary.h. `AcquiresCell` and `Cache::of` are gone | L01 |
| C71 | Needs no code | No pass of ours adopts `LocalAliasAnalysis` | — |
| C72 | Implemented | `llvm.func` and `llvm.call` are built directly (lib/Conversion/Lower/Functions.cpp). `invariant.group` and launder (lib/Conversion/RuntimeCells.cpp). The call's speculatability comes from its row (lib/IR/Func/Call.cpp:84-85) | L21, L02 |
| C73 | Needs no code | The LICM patch comes only if a measurement asks for it (D103, C151) | — |
| C74 | Implemented | `Terminates` and `MayDiverge` (Spec/Functions/Termination.idr, Frontend/Translate/Recursion.idr). `FuncOp::absorb` is gone | L16, L02 |
| C75 | Partial | Ops are indexed by their group counts, with `Fin` guards and `ResultUsesMaxOf` (Spec/Core/Op.idr). But Emit forgets the guard positions to `Nat` (compiler/src/IdrisMLIR/Emit/Operations.idr:131) and looks them up with internal errors on a miss (:98-116) | L16 |
| C76 | Implemented | Hooks are printed (Spec/Core/Hooks.idr), and laws reach the C++ as tables | L03 |
| C77 | Partial | Spec.Core.Dialect and Admitted exist, and the rule readers go through the runner (harness/lib/rules.sh). But compiler/src/IdrisMLIR/MLIR.idr:207-221 keeps per-dialect constructors and string dialect names (`typeDialect`, `attrDialect`). The build still generates IdrRules.txt, IdrPassRoles and IdrPassStages (include/idr/IR/CMakeLists.txt:23) | L16, INT |
| C78 | Partial | `generate` is pure (Spec/Generator/Outputs.idr:205), and the manifest printer exists. No output is committed: foreign/idr/include/idr/IR/Generated/ and foreign/idr/generated.manifest are absent, though lib/Transforms/Optimize/Contify.cpp includes idr/IR/Generated/Actions.h.inc | INT (D111) |
| C79 | Implemented | `ErasedBinderOpInterface` and one substitution (lib/IR/Families/Substitute.cpp), which the inliner uses (Transforms/Inline/Inline.cpp) | L04 |
| C80 | Implemented | Groups are components (Defunctionalize/Declare.cpp:227), with `Promise`. `SumKind`, `CtorRole` and DataRemap are gone | L04, L18 |
| C81 | Partial | Layouts come from types, and `!idr.box` and Fit are gone. Still there: `firstOrderFamilies` builds a `TypeGraph` in the program verifier (lib/IR/Verify/Program.cpp:103-112). The deleted `layout::holdsNoComponent` is still called (lib/IR/Func/Program.cpp:68), and nothing defines it | L04, L02 |
| C82 | Partial | `idr.index.assume` and `data.reindex` exist (Spec/Families/Dialect.idr:767-776, lib/IR/Families/Refinement.cpp). But the frontend writes no `index.assume`, and the registry's identity hooks for `replace` and `rewrite__impl` remain (Registry/Faster.idr:116-118, 135) | L16 |
| C83 | Implemented | `idr.lend` (lib/IR/Lifetimes/Ops.cpp). `Viewing` and `ownersAcross` are gone | L05 |
| C84 | Implemented | Count and spine proofs (lib/IR/Lifetimes/Proof.cpp, Spine.cpp). Stack.cpp is gone, and the cycle clause follows D95 | L05 |
| C85 | Partial | `isCountedElement` and Classes.cpp are gone. No element is a view by its scope's row: every element read out of memory takes a reference (include/idr/Transforms/Counting/Facts.h:89-104, Counting/Placement.cpp `classify`) | L07 |
| C86 | Implemented | `madeStatic`, `persistHeld` and the `Phantom` class are gone | L05, L07 |
| C87 | Implemented | `count.dup` and `count.drop` take counted operands (Spec/Counting/Declarations.idr:161-178) | L07 |
| C88 | Implemented | The bound B(f) (Counting/Bound.cpp). The checked runtime discriminates it at run time (tests/runtime-frame-bound, C138) | L07, L19 |
| C89 | Missing | Nothing checks that an `in_place` family has exactly one constructor with a cell: not the registry (Registry/Recognized.idr:137-144, Entry.idr:423), not the frontend's family (Frontend/Translate/Types.idr:1178-1180), not the family verifier | L16 |
| C90 | Implemented | idr-in-place runs right after knots (Pipeline.idr, Transforms/InPlace/). Demand is gone | L08 |
| C91 | Implemented | lib/Analysis/Ownership/ExclusivityGraph.cpp:17, 67. `unknownFrom` is gone | L08 |
| C92 | Implemented | The local rule and result claims (Transforms/InPlace/Unique.cpp, UniqueResults.cpp) | L08 |
| C93 | Implemented | upstream/65-71, with tests/upstream-early-exit-* and PINS.md entries. The jump declares no effects | L09, L06 |
| C94 | Implemented | `populateSCFToControlFlowConversionPatterns` (lib/Conversion/Matches.cpp:328) | L09 |
| C95 | Implemented | Contification over a dominator tree (Optimize/Contify.cpp). Case-of-case builds join regions (Joins/CaseOfCase.cpp) | L18, L09 |
