<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Traceability: the owner's rulings D1 to D111 against the tree

Done criterion: "every ruling in the proposal is implemented in the tree,
or recorded there as needing no code". Read from the code on `main` at
39a31f8b with the working tree as it stood on 2026-10-22 (lanes still
writing; uncommitted changes named as such). Nothing was built. Paths are
under `foreign/idr/` unless they start with another top-level directory;
`spec/` is `compiler/spec/IdrisMLIR/Spec/`.

Cross-cutting, not repeated per row: INT's CMake hubs are not yet wired.
`lib/CMakeLists.txt:42-43` (TailCallPlan, TailPosition),
`lib/Analysis/CMakeLists.txt:7,22` (CallCycles, Recursion),
`lib/IR/CMakeLists.txt:30,45` (DataBody, DataRemap),
`lib/Transforms/CMakeLists.txt:97,341` (Demand, Nests) still list deleted
sources, and `include/idr/IR/Generated/` and `generated.manifest` do not
exist yet.

| ruling | verdict | where, or what is missing | owner |
| --- | --- | --- | --- |
| D1 | Needs no code | Queue order. | coordinator |
| D2 | Implemented | The solver layer, `include/idr/Analysis/Solver/` (`ProgramGraph.h`, `Graph.h`, `IdentityRecords.h`). | L14 |
| D3 | Needs no code | Research waves, done. | coordinator |
| D4 | Needs no code | Process gate. | coordinator |
| D5 | Needs no code | The lens, `.claude/skills/representation-first/`. | coordinator |
| D6 | Needs no code | Delegation rule. | coordinator |
| D7 | Partial | 43 concepts, no `std::function`. Still `llvm::TypeSwitch` at `lib/Transforms/Narrow/Ops.cpp:148` (banned with the ladders, C52), and an op-list `isa<BigSmallOp, BigFromSIntOp, BigFromUIntOp>` at `Narrow/Narrow.cpp:113`. | L12 |
| D8 | Needs no code | Scope. | coordinator |
| D9 | Implemented | `spec/Effects/{Resource,Atom,Declaration,Declarations,LLVM}.idr`; `include/idr/IR/Effects/`; one op per semantics in `spec/Ops/`. | L01, L13 |
| D10 | Partial | The rule is in AGENTS.md. Facts proved or true by construction are still re-tested on every compilation: `compiler/src/IdrisMLIR/Frontend/Finite.idr:180-216` (`heightWithin`, `sizedWithin`, "the growth check is unsound"), `Frontend/Translate/Types.idr:902-908` (`boundsHold`), and `IdrisMLIR/Laws.idr`, which `Emit.idr:71-76` runs "on every compilation" for laws the translation guarantees. | L16 |
| D11 | Needs no code | Process. | coordinator |
| D12 | Needs no code | The language's meaning; refusals are `unsupported`. | coordinator |
| D13 | Implemented | `spec/Functions/Termination.idr` (per Idris component). Divergence withholds `MustProgress` (`spec/Effects/LLVM.idr:84-102`, `lib/Conversion/Lower/Attributes.cpp:52`). A certain crash is a plain crash (`lib/IR/OpsChecks.cpp:133-180`). | L02, L13 |
| D14 | Implemented | `io.exit`: a `NeverReturns` terminator writing `Exit` (`spec/Ops/IO.idr:144-173`). `WillReturn` is withheld (`include/idr/IR/Effects/Vocabulary.h:191-196`). | L01 |
| D15 | Implemented | `compiler/spec` (Idris) and its generator `spec/Generator/Main.idr`. | L03 |
| D16 | Partial | No hand `.td` is tracked under `foreign/idr`, and the generator exists (`spec/Generator/{Ods,Cpp,Outputs}.idr`). Its outputs are neither generated nor committed. | INT |
| D17 | Needs no code | Lifts the fence. `Idr_Decides` has 0 hits; `Positions` is kept on its merits. | coordinator |
| D18 | Needs no code | Principle, carried by D19. | coordinator |
| D19 | Implemented | `data.match`/`lit.match` have a region per case (`spec/Control/Matches.idr`); `idr.join`/`idr.loop` in `spec/Control/Joins.idr`; `SCFToControlFlow` runs only at the lowering (`spec/Pipeline/Pipeline.idr:605`). | L09 |
| D20 | Implemented | The world is dropped at Emit (`compiler/src/IdrisMLIR/Emit/Declarations.idr:31-33`, `Emit/Index.idr:111`). No world type or op remains; `tabulate_io` and `element.update` have 0 hits. | L16, L01 |
| D21 | Implemented | `Crash` sits under `IO`, with `Heap` as a sibling (`spec/Effects/Resource.idr`). A guard returns its operand refined (`CheckNonzeroOp`). | L01 |
| D22 | Implemented | One derivation and one writer: `lib/Transforms/Effects/`, `lib/Analysis/Effects.cpp`, `WriteRows` in `lib/Transforms/Pipeline.cpp`. `bodyEffect`, `solveEffects` and `componentEffects` have 0 hits. | L02 |
| D23 | Implemented | `Alloc` reports only (`spec/Effects/Atom.idr`); there is an acquires rule; out of memory ends with status 111 (`spec/Runtime/Endings.idr:225`). | L01, L11 |
| D24 | Implemented | `lib/Transforms/InPlace/` (idr-in-place), the `InPlaceType` hook (`compiler/src/IdrisMLIR/Registry/Entry.idr:310`), `tests/uniqueness-shared-rebuild/{,near/}`. `Demand/` is gone. | L08 |
| D25 | Implemented | `upstream/65-early-exits` to `71-*` with `tests/upstream-early-exit*` and `PINS.md:715`; `PropagateControlFlowBreak` and `HasBreakingControlFlowOpInterface` (`spec/Core/Upstream.idr`); dependencies fast-forwarded (b9c0b2bb). | L06, L09 |
| D26 | Implemented | `lib/Transforms/Counting/Bound.cpp` (loan share, cb367eed) and `Placement.cpp`. | L07 |
| D27 | Implemented | The tree in `spec/Effects/Resource.idr`. | L01 |
| D28 | Implemented | The names in `Resource.idr:87-145` and `ResourceId`; every `*Resource` class has 0 hits. | L01 |
| D29 | Implemented | Eleven atoms (`spec/Effects/Atom.idr:32-75`); the old spellings have 0 hits in tests. | L01 |
| D30 | Implemented | `TailKind` (`spec/Functions/Tail.idr:24`); one definition (`include/idr/IR/Tail.h`); `musttail`/`tailcc` (`lib/Conversion/TailCalls.cpp`). The deciders are deleted, and `numFrameBound` has 0 hits. | L10, L21 |
| D31 | Implemented | `lib/Transforms/Tail/{Frames,FramesFamily,Continuations,Split}.cpp`, with frames typed by a family per component, indexed by the row a frame awaits; at run time, `runtime/Alloc/Frames.cpp`. | L10, L11 |
| D32 | Implemented | `lib/Driver/StackBound.cpp`, `runtime/Start/Runner.cpp`; no 64 GiB anywhere. | L10, L11 |
| D33 | Implemented | `upstream/10-recursive-attribute-parser/llvm.patch` and the iterative patches 80-93, 97 (58f54f31, 789a8600, 63a04a64). | L06, L15 |
| D34 | Implemented | `lib/Transforms/Tail/{Trmc,TrmcRewrite}.cpp`, `!idr.dest` (`spec/Tail/Declarations.idr`), `ModuloContext`. | L10 |
| D35 | Implemented | `runtime/Platform/Posix/Memory.cpp`, `tests/runtime-commit-limit`. | L11 |
| D36 | Implemented | `memory.max` in `runtime/Platform/Posix/Cgroups.cpp`; `StatsRange` in `runtime/Alloc/Cells.cpp`. | L11 |
| D37 | Implemented | The ending table in `spec/Runtime/Endings.idr` (codes 111/126, `Abort`); `mainReturned` has 0 hits. | L11 |
| D38 | Implemented | `idris_rt_crash_at` (`runtime/End/End.cpp:299`). | L11, L21 |
| D39 | Needs no code | Amended by D63, D88 and D90. Its deletions are gone: `!idr.q` and `Locality` have 0 hits, and `isStatic` is now type-based (`lib/Transforms/Specialize/Consumer.cpp:150`). | L05 |
| D40 | Needs no code | Superseded by D90. The `heap`/`frame` constants are gone. | L05 |
| D41 | Implemented | `include/idr/IR/Numeric/{Inline,Domain,Intervals}.h`, included by `runtime/Big/Arithmetic.cpp:7`. | L13 |
| D42 | Implemented | Registry `generating` rows name spec ops (`Registry/Recognized.idr`); AGENTS.md is amended. | L12, L16 |
| D43 | Implemented | `DestinationStyleOpInterface` and `TilingInterface` (`include/idr/IR/Arrays.h`); `lowerToLoopsUsingSCFForOp` (`lib/IR/OpsTabulate.cpp`); `upstream/27`, `upstream/64`. `Nests.cpp`, `GeneratingOpInterface`, `StoreModel` and `HeapReadModel` are gone. 0009 is amended. | L12 |
| D44 | Partial | Present: the relational core (`libs/mlir-relational`, 57016413) and the semi-naive instance worklist (`Frontend/Finite.idr:23`). Owed: 0010 A0 on the fork (interned names, the term arena as columns), 0011 O1 and O5 ("Owed (L17c)", handoffs/L17b.md). A0 is uncommitted and in progress: `compiler/idris/src/Core/Name/{Ident,Known}.idr` and `Core/TT/Stored.idr` are untracked. | L17, L16 |
| D45 | Implemented | Through D53 to D55, which amend it. | L17 |
| D46 | Partial | `compiler/src/IdrisMLIR/Proof/Bound.idr` still states Theorem 1 "over a model of what the frontend's sites write", not over `Frontend/Growth/Template.idr:75`'s `Template`. The run-time re-check and its internal error remain (`Finite.idr:180-216`, `Translate/Types.idr:902-908`). | L16 |
| D47 | Implemented | `.claude/skills/representation-first/SKILL.md:105`. | coordinator |
| D48 | Partial | Families are in: `spec/Families/*`, `FamilyAttr` (`include/idr/IR/Families/`), `!idr.data<#F[ts]>`; `Idr_DataTableAttr`, `MutableType`, `DataRemap.cpp` and `!idr.box` are gone from the code. Stale old forms remain. `upstream/28-liveness-non-forwarded-terminator/tabulate-across-call.mlir`, used by `tests/upstream-liveness-non-forwarded-terminator`, and `upstream/24-*/idr-{call,cycle}.mlir` are in the old `#idr.types` syntax, which no longer parses. `tests/emit-dialects/{witness,near-miss}` fixtures hold `!idr.box`. | L06, L19 |
| D49 | Partial | Amended by D67. The committed generated files do not exist yet. | INT |
| D50 | Partial | The frontend imports `Spec.Core.Rules`, `Runtime.Endings`, `Runtime.Clocks`, `Grades.Grade` and `Pipeline.Stage`, and the tblgen list backends are gone. But `include/idr/IR/CMakeLists.txt:23,27-28` still generates `IdrRules.txt`, `IdrPassRoles.txt` and `IdrPassStages.txt` through those removed backends. Stale mentions: `lib/Driver/Outcome.cpp:67` (L11), `tests/rules-covered/run:23` and `without-fixture:3` (L19). | INT, L11, L19 |
| D51 | Implemented | `tools/idris-mlir-tblgen.cpp` has four backends (`gen-idris-syntax`, `-dialect`, `-bytecode`, `-admitted-classes`); `IdrAdmitted` records come from `spec/Generator/Outputs.idr:135-144`. | L03 |
| D52 | Implemented | `spec/Generator/Render.idr` (no `Double`, no sort), `tests/spec-self`, `tests/spec-current`. | L03, L19 |
| D53 | Implemented | Homeomorphic embedding in `compiler/idris/src/Core/AutoSearch.idr:143-147`; `GrowingSearch` (`Core/Core.idr`); a386fe4d, e5b39cb2; `upstream/fork-search-depth`. | L17 |
| D54 | Implemented | A growth through unknowns waits for a later round (`Searched`/`Grows`, e5b39cb2; `upstream/fork-search-depth/README.md`). | L17 |
| D55 | Implemented | `%ambiguity_depth` is deleted (a386fe4d, `upstream/fork-ambiguity-depth`); the tuple is one node settled by sort (e5b39cb2). | L17 |
| D56 | Needs no code | Process. | coordinator |
| D57 | Partial | The pass exists (`lib/Transforms/EGraph/`), but a fired rule replaces the node and never unions (`EGraph/Nodes.cpp:202-240`), so extraction chooses nothing. This is §4's next owner question. | L14 (owner) |
| D58 | Implemented | `SignatureKey`'s layout class (`include/idr/Transforms/Specialize.h:11,178-190`), `IndexArgsAttr`, `data.reindex`. | L18, L04 |
| D59 | Implemented | `!idr.nat` takes an index-term parameter (`spec/Ops/Values.idr:89-103`); `Frontend/Translate/Terms.idr:1244`. | L13, L16 |
| D60 | Implemented | `tie_shape` (`lib/IR/OpsArrayShapes.cpp`); the index-term key; 0009 is amended (`README.md:5-8`). | L12 |
| D61 | Implemented | The write part in `spec/Functions/Parameters.idr`; `ArgMem` (`spec/Effects/LLVM.idr`). | L02 |
| D62 | Implemented | The algebra in `spec/Grades/Grade.idr` (`Claims`, `Fits`), as amended by D88. | L05 |
| D63 | Implemented | `idr.lifetime` (`spec/Lifetimes/Declarations.idr:177`); lifetime operands (`include/idr/IR/Lifetimes.h`, `lib/IR/Func/Inliner.cpp`). | L05 |
| D64 | Implemented | `Unreportable` in `spec/Runtime/Endings.idr:199`. | L11 |
| D65 | Implemented | `memory.swap.max` in `runtime/Platform/Posix/Cgroups.cpp`. | L11 |
| D66 | Implemented | `runtime/Start/Runner.cpp:67-75`. | L11 |
| D67 | Partial | The manifest's generator exists (`spec/Generator/Manifest.idr`), but `foreign/idr/generated.manifest` is absent. | INT |
| D68 | Implemented | `Reduces` in `compiler/idris/src/Idris/Host.idr:17-190`. Removing the witness is tied to D46. | L17 |
| D69 | Partial | O7's union-find is in: `compiler/idris/src/Libraries/Data/UnionFind.idr`, `Core/UnifyState.idr:106-112,263` (e5b39cb2). O6, the multiplicity check as a semiring fold, is uncommitted and in progress (diffs to `Core/LinearCheck.idr` and `Core/Termination/SizeChange.idr`). | L17 |
| D70 | Implemented | `Unique = None \| Self \| Deep` (`spec/Grades/Hold.idr:30`); `tests/in-place-shared-elements`. | L05, L08 |
| D71 | Partial | `Linear.Vec` is an `InPlaceType` entry. The working tree deletes `LArray`'s entry (an uncommitted diff to `compiler/src/IdrisMLIR/Registry/Recognized.idr:132-145`, "a linear array is no family"), against the ruling's "two more `InPlaceType` entries", with no dated ruling. The claim level (C185's `unique deep` or (A)) is open in §4. | L16 |
| D72 | Implemented | `FieldReach = InPlaceFamily` (`spec/Grades/Grade.idr:198`); `tests/in-place-list-in-linear-record-shared`. | L05, L08 |
| D73 | Implemented | `lib/Transforms/Counting/Borrows.cpp`. | L07 |
| D74 | Implemented | `Counting/Placement.cpp:35`, `Bound.cpp:119`. | L07 |
| D75 | Implemented | `lib/Transforms/Optimize/Contify.cpp`, `Expect/Continuations.cpp`, `include/idr/Transforms/Joins.h`. | L09, L18 |
| D76 | Implemented | Builtin token targets (`spec/Control/Joins.idr:11-16`); `!idr.cont` has 0 hits. | L09 |
| D77 | Implemented | `lib/Driver/LinkRuntime.cpp:84` strips `probe-stack` from the inlined runtime; the runtime takes stack-clash protection (`runtime/CMakeLists.txt`, `upstream/86`). | L11, L06 |
| D78 | Implemented | No stack bit in any runtime header (0 hits); lexical cells are `Scoped` and uncounted. | L05, L11 |
| D79 | Implemented | `borrowedBefore` (`lib/Transforms/InPlace/Chains.cpp:125-160`); `tests/in-place-borrowed-read-ends`. | L08 |
| D80 | Implemented | The `function` parameter of `idris_rt_crash_at` (`runtime/End/End.cpp:299`); `Naming = WithFunction` (`Endings.idr:49`). | L11 |
| D81 | Implemented | `runtime/Platform/Posix/{Process,Files}.cpp` (`EPIPE`); `BrokenPipe` (`Endings.idr:254`). | L11 |
| D82 | Needs no code | Conditional on upstream merging. | coordinator |
| D83 | Implemented | AGENTS.md's wording; the seven tests are now programs (03557455). | L19 |
| D84 | Needs no code | Reversed by D85 and D107. | coordinator |
| D85 | Needs no code | Reversed by D107. | coordinator |
| D86 | Needs no code | Reversed by D107: no Idris engine, nothing linked as bitcode. | coordinator |
| D87 | Needs no code | Out of P0 by D107: no sparse library in `libs/`. | coordinator |
| D88 | Implemented | `Hold = Counted Unique \| Scoped Unique \| Static` (`spec/Grades/Hold.idr:37`); `Grade` on references only (`Grade.idr:293-295`). | L05 |
| D89 | Implemented | The hold key (`Specialize.h:178-190`, `Specialize/Consumer.cpp:150-167`); the static marker is count 0 (`runtime/Rc/Rc.h:78`). | L18, L11 |
| D90 | Implemented | `!idr.graded`, `idr.activation`, `idr.lend`, `idr.lifetime.forget`, `Release::Static`. `!idr.q` and `idr.borrow` have 0 hits; `!idr.lin` survives only in the `upstream/27`, `upstream/64` READMEs. | L05 |
| D91 | Implemented | `-DLLVM_ENABLE_ASSERTIONS=OFF` at `tools/bootstrap.sh:946,1051,1175`; 0 `assert(` in `foreign/idr` and `runtime`. | L06, L15 |
| D92 | Needs no code | 0020 is amended (cites D92). | coordinator |
| D93 | Implemented | `LifetimeKind = View \| Room \| Cursor \| Home` (`spec/Lifetimes/Kind.idr:25`); one opener per source (`Declarations.idr:443-448`); `lib/IR/Lifetimes/Kind.cpp`. | L05 |
| D94 | Implemented | `Amount = Finite \| Unbounded` and `#idr.put_bounds` (`spec/Functions/Parameters.idr:60-120`). | L02, L05 |
| D95 | Implemented | `Packed = FromStack \| FromChain` (`Kind.idr:149-168`), `idr.lifetime.package`, `Tail/Split.cpp` (6905a004). | L05, L10 |
| D96 | Implemented | 6905a004 and cc6d1894 (a tail call's cursors are checked by position). | L10 |
| D97 | Needs no code | Narrowed and reversed by D107. | coordinator |
| D98 | Implemented | No greedy-driver call and no canonicalization pattern (0 hits). `simplify` stands at every point that holds our ops and in the inliner (`spec/Pipeline/Pipeline.idr:260,271,549`). | L14, L03 |
| D99 | Implemented | Upstream passes are run as they are (`RunUpstream`, `Pipeline.idr:94`). | L03 |
| D100 | Implemented | No canonicalize or CSE in `Pipeline.idr`. | L03 |
| D101 | Implemented | The fork's `WithBounds` is a sum (`compiler/idris/src/Libraries/Text/Bounded.idr`; `upstream/fork-parser-bounds`; `PINS.md:1805`). | L17 |
| D102 | Implemented | `CallOp::getSpeculatability` reads the row (`lib/IR/Func/Call.cpp:84`); `include/idr/IR/Effects/Set.h:73`. | L02 |
| D103 | Implemented | The skeleton in `EGraph/{Build,Elaborate,Simplify}.cpp`. | L14 |
| D104 | Implemented | `libs/mlir-array/Linear/Bytes.idr` and the parser over it (57016413). | L20 |
| D105 | Implemented | A numeral is one literal (`Frontend/Translate/Terms.idr:1294-1309`); a case binds its scrutinee refined (`spec/Control/Matches.idr:8-21`). | L16, L09 |
| D106 | Implemented | Narrow, directionless local rules (50237819, ff8ea61d, d09e1090); `spec/Core/Rewrite.idr`. | L14, L13 |
| D107 | Implemented | The C++ engine (`lib/Transforms/EGraph/`); rules from the spec (`spec/Core/Rewrite.idr`, C191 770cf8ce); the elaborator's own union-find. | L14, L17 |
| D108 | Implemented | Budget = `nodesPerOp` × ops (`EGraph/Build.cpp:78`); arena admission (`Optimize/Component.cpp:67-70`, `Inline/InlinePass.cpp:47`). | L14, L18 |
| D109 | Implemented | No optimization on the Idris side; rules are spec data generated into C++. | L03, L14 |
| D110 | Implemented | `InPlaceFamily` reach (`spec/Grades/Grade.idr:198`); the buffer extension is §4's open question. | L05 |
| D111 | Needs no code | Process. | coordinator |
