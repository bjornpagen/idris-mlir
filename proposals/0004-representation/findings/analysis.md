<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Representation survey: analysis

Area: `foreign/idr/include/idr/Analysis/` and `foreign/idr/lib/Analysis/` (5,274 lines): BindingTimes (header `Specialize.h`), Constants, Effects, Escapes/EscapesCycles, Identities with Record and Rebuilds, Inline, Labels/LabelSites, Ownership/ (Values, Uses, Borrows, Reuses, Exclusivity, ExclusivityAnalyses), Ranges, Tail. Read whole, with producers and consumers in `lib/IR`, `lib/Transforms/{Optimize,Specialize,Inline,Effects,Ownership,Stack,Tail,Narrow,Defunctionalize}` and `lib/Conversion/TailCallPlan.cpp`.

## The area as it stands

The analyses built on upstream are in good shape:
- Escapes and Exclusivity are sparse analyses on MLIR's solver, over the one flow interface.
- Ranges is upstream's integer range analysis, seeded for naturals.
- Constants is upstream's constant propagation with a summary hook.
- Labels' 0CFA (kept by the representation wave) is a closed union-find with the empty set as its null object.

The defects sit between the analyses:
- **One fact computed in several places that already disagree:** the call graph's components, "on a cycle", the effects a body implies, a callee's effects, "a natural is ≥ 0", and what a value structurally is.
- **Lattice elements nothing reads** since their consumer was deleted (binding times).
- **"Not computed" or "not final" encoded as nothing:** a null pointer, an absent attribute, or a `nullopt`.
- **Results that travel by position** next to the list they came from.

## Findings, ranked (branches removed against risk)

### analysis-1: binding times hold three elements no decision reads, and `Free` is just `Fixed` for a function on no cycle
| Field | Content |
|---|---|
| Evidence | `Analysis/Specialize.h:25-32,37-59` enum `{Free, Fixed, Decreasing, Bounded, Other}`. The only decision is `Transforms/Specialize/Keys.cpp:59-64` `specializesOn`: `time == Free \|\| time == Fixed`. bfdcac70 deleted the unrolling consumer (`unrolls = Decreasing \|\| Bounded`, `kUnrollLimit`) but kept the lattice. In `BindingTimes.cpp`, about 17 branches serve it: `Smaller`, `partOf` (3 arms), `code`'s Smaller arm, `join` over `optional` (3 branches, 86-92), `value_or(Other)` (145-147), 4 part-of eval branches (173-192, whose comment at 185-188 still cites unrolling), `refer`'s 3-arm visitor (210-218), `callsItself` and the `cycle` split (224-246), and `nameOf`'s 5 cases (35-49). Consumers: `Specialize.cpp:256-270` (`seenBy` builds all-`Free`), `:272-285` (pads with `Other` behind `p < theirs.size()`), and `Optimize/Component.cpp:221-247` (`heldTimes++` walks a vector parallel to a filtered sublist). |
| Counterexample | `count`'s counter is `decreasing` and is treated exactly like `other`. `free` and `fixed` are indistinguishable to `specializesOn`. The optional "nothing passed" state is unreachable for an SCC member, yet it is guarded. |
| Root cause | The lattice keeps a distinction a deleted consumer needed. "On no cycle" is a per-function fact copied into each parameter, although vacuous truth already gives `Fixed`. |
| Correction | `enum class BindingTime { Fixed, Varies }` (join is max) in `Analysis/BindingTimes.h`. The abstract value is `variant<Same{param}, Anything>` and `seen` starts at `Fixed`. Per-function API: `bindingTimesOf(FuncOp, ArrayRef<FuncOp> component)`. |
| Deletion | `Free`/`Decreasing`/`Bounded`/`Smaller`, `partOf`, the 4 eval branches, `join`'s cases and the optional bottom, `value_or`, `callsItself` and the `cycle` split, 3 `nameOf` cases, the stale docs, `Free \|\|`, and `takeUp`'s parallel `times`. |
| Consumers | `Analysis/Specialize.h` (renamed), `BindingTimes.cpp`, `Transforms/Specialize/{Keys,Specialize,Report}.cpp`, `Optimize/Component.cpp`, `Transforms/{Specialize,Optimize}.h`, `tests/idr/specialize/binding-times.mlir`. |
| Discriminator | `binding-times.mlir` restated in two names. Property: every `SpecKeyAttr` is unchanged on the e2e suite. |
| Verification here | `make typecheck`, `tools/check-units.py`, `make check`. Fixtures run on the owner's build. |
| Size and risk | About 100 lines and 17 branches go; behaviour is unchanged by construction. Kept: per-function tuple interpretation, and `seenBy`'s inside/outside split. |
| Insight | 4, 11, 16 |

### analysis-2: the call graph's components and "same cycle" are computed five times
| Field | Content |
|---|---|
| Evidence | `Support/Scc.h` claims "the one walk". In practice: `Effects.cpp:78-104` `callGraphComponents` (3 branches); `EscapesCycles.cpp:24-42` calls `llvm::scc_begin` directly into its own map; `Escapes.cpp:82-87` `together` has 3 guards for an always-present node; `Ownership/Borrows.cpp:106-116` calls `scc_begin` into `cycleOf` (`isExternal`, `optional first`, `value_or`; compared at 265). Outside the area: `Optimize/Contify.cpp:69-76` `componentsOf`, `Tail/Returned.cpp:209-215`, `Conversion/TailCallPlan.cpp:134-141`, `Optimize/ReadySet.cpp:50-58`, `Specialize/Report.cpp:31`. |
| Counterexample | Three numberings of one partition, keyed differently. `together` treats a function missing from its map as on no cycle, which the closed world rules out. |
| Root cause | No analysis holds the module's call-graph components. |
| Correction | `idr::CallCycles` (`Analysis/CallCycles.h`), cached by the AnalysisManager and invalidated with CallGraph/SymbolTable. Built through `idr::components`, keyed by the callable `Operation*`. API: `components()` callees first, `componentOf`, `together`, `callsItself`. |
| Deletion | `callGraphComponents`, the EscapesCycles SCC loop and map, `together`'s guards, Borrows' `cycleOf`, Contify's `componentsOf`, and the direct `scc_begin` loops. Escapes keeps only its tail-self-call refinement. |
| Consumers | `lib/Analysis/{Effects,Escapes,EscapesCycles}.cpp`, `Analysis/{Effects,Escapes}.h`, `Ownership/Borrows.cpp`, `Optimize/{Contify,ReadySet}.cpp`, `Specialize/Report.cpp`, `Transforms/Effects/Effects.cpp`, `Tail/Returned.cpp`, `Conversion/TailCallPlan.cpp`, `lib/Analysis/CMakeLists.txt`. |
| Discriminator | A googletest box covering mutual recursion, a self tail call, a self non-tail call and a leaf. Stack, rc, effects and contify fixtures unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | About 70 lines, 4 walks and about 10 branches go. Low risk. Kept: Escapes' tail-self exception, and Inline's `onCycle` (it uses the ready set's components, not the call graph's). |
| Insight | 4, 7, 16 |

### analysis-3: the effects of a body are written twice, and only the verifier knows an indirect run
| Field | Content |
|---|---|
| Evidence | Solver: `Effects.cpp:28-63` (`Body`, `calleeOf`, `bodyOf`, `sumOf`). Verifier: `Verify/Program.cpp:76-95` walks again, with `dyn_cast<CallOp>` and `isa<ApplyOp, ForceOp>` → `anyEffect`. Shared: only `bodyEffect` (`Func.cpp:137-148`). "Runs labels" is listed at `Program.cpp:85`, `Effects.cpp:158` and `Labels.cpp:278-284`. |
| Counterexample | `componentEffects` on a higher-stage program ignores an apply, so `idr-effects` must refuse the stage (`Transforms/Effects/Effects.cpp:30-33`), while the verifier counts the same apply as every effect. |
| Root cause | 0002 §4.3 moved only the own part into `lib/IR`. The callee sum and the indirect-run rule sit in two units. |
| Correction | In `lib/IR/Func`: `bodyEffect` counts an indirect run as `anyEffect`, and `componentEffects` moves beside it. The verifier becomes `bitEnumContainsAll(fn.getEffects(), componentEffects({fn}, symbols))`. Add an op interface `Idr_RunsLabelsOpInterface { Value getLabelCarrier(); }` on apply and force, read by `Labels::runs` and `observableRuns`. |
| Deletion | The verifier walk (2 branches), two apply/force lists, the `Labels::runs` ladder, and Effects.cpp's private body/sum (moved, not copied). |
| Consumers | `IR/{Func.h,IdrInterfaces.td,IdrClosureOps.td}`, `lib/IR/Func/Func.cpp`, `Verify/Program.cpp`, `Analysis/Effects.h`, `lib/Analysis/{Effects,Labels}.cpp`, `Optimize/Component.cpp`, `Defunctionalize/Pass.cpp`. |
| Discriminator | A verify fixture still refuses `effects = none` with an apply. New `--idr-contracts` property: after `idr-effects`, every entry equals the verifier's required set. |
| Verification here | `make typecheck`, `make typecheck-dialects`, `make check`. |
| Size and risk | About 35 lines and 5 branches go. Low risk: no indirect run exists post-defunctionalization. Kept: the stage refusal, and `observableRuns` as a separate reach over label edges. |
| Insight | 7, 16 |

### analysis-4: what a value is made of is re-derived by six ladders that disagree
| Field | Content |
|---|---|
| Evidence | "Same value at another grade" (`ResultCarriesOperand`) is read at: `IdentitiesRecord.cpp:225-226`, `Tail.cpp:89-94`, `Grades.cpp:146-158` (`throughLinear` handles lin ops only), `Verify/Uses.cpp:33-40` (`viewedFrom`), and `Ownership/Exclusivity.cpp:146-167` (`proves`, via flow edges). `BindingTimes.cpp:159-196` does not read it at all. "What a match region's argument is" is re-derived at: `BindingTimes.cpp:171-179`, `IdentitiesRecord.cpp:142-157`, `:59-73` (`remaining`), `:267-287` (`framesAt`), and `Verify/Uses.cpp:56-72` (`readFrom`: any region argument is a field, the default one included). Memo opacity is in Identities only. |
| Counterexample | A recursion passing a parameter through `idr.lin.use` or `idr.lin.enter` is `other` to binding times, so it is never specialized, while Identities sees the same value. `readFrom` calls the scrutinee a field of itself. |
| Root cause | No IR-level view of a value's structural source. A match's region arguments are described only in prose. |
| Correction | `idr::sourceOf(Value) -> variant<Made, Same{Value}, Field{Value, Tag, unsigned}>` in `Grades.h`. `Same` covers a `ResultCarriesOperand` result and a default-region argument; `Field` covers `idr.field` and case-region arguments; a memo part is `Made`. Add `MatchOp::knownTag(Region&) -> optional<Tag>`. Each ladder keeps only its extras. |
| Deletion | BindingTimes' match branch; Identities' `internArg`, `remaining`, `framesAt`'s tag logic and three `internResult` arms; the grade lambdas in `arrayRoot`, `viewedFrom` and `moduloAt`; `proves`' edge search; readFrom's match arm. About 12 branches. |
| Consumers | `IR/{Grades.h,IdrMatchOps.td}`, `lib/IR/{Grades,OpsMatch,Verify/Uses}.cpp`, `lib/Analysis/{BindingTimes,IdentitiesRecord,Tail}.cpp`, `Ownership/Exclusivity.cpp`. |
| Discriminator | A binding-times fixture with a self call on `lin.use %x` reports `fixed`. A `sourceOf` googletest box. Identities, rc and verify fixtures unchanged. |
| Verification here | `make typecheck`, `make typecheck-dialects`. |
| Size and risk | About 60 lines and 12 branches go. Medium risk: Borrows' field walk under readFrom's changed default-region reading. Kept: Identities' `Pred`/`Successor`, and readFrom's buffer cases. |
| Insight | 6, 7, 16 |

### analysis-5: a flow point has three key spaces and two five-arm visitors
| Field | Content |
|---|---|
| Evidence | `Labels.h:138-146` holds three maps. `LabelSites.cpp:44-71` and `:80-103` are the same 5-arm visitor (find versus find-or-create), each resolving a parameter with an assert (`:27-33`). The link rule appears twice: `LabelSites.cpp:127` (by carrier) and `Labels.cpp:194` (by type). |
| Counterexample | A new point kind costs an arm in two visitors and maybe a fourth map. |
| Root cause | A point is not normalized to a key before lookup. |
| Correction | `PointKey = variant<Value, FlowAnchor, ResultKey>`, one `keyOf(FlowPoint)` normalizer and one `DenseMap<PointKey, Node>`. `lookup` is `find`, `nodeOf` is `try_emplace`. `linkOf(Carriers)` is used by both. |
| Deletion | Two maps, one visitor, the duplicate parameter resolution, and one link rule. |
| Consumers | `Analysis/Labels.h`, `lib/Analysis/{Labels,LabelSites}.cpp`. |
| Discriminator | Defunctionalize fixtures unchanged. A googletest box: a parameter point equals its entry argument. |
| Verification here | `make typecheck`. |
| Size and risk | About 40 lines and 6 arms go. Low risk. Kept: the 0CFA, the union-find, and the empty-set null object. |
| Insight | 7, 8, 12 |

### analysis-6: Identities reads a callee's effects three ways, and the accessor D13 named was never exported
| Field | Content |
|---|---|
| Evidence | `Identities.h:42-48` has `Callee{optional givesBack; bool returns}`. `Optimize/Component.cpp:229-233` computes `returns` from `fn && !diverge`. `IdentitiesRecord.cpp:167-170` splits member against outside (2 branches; the only use of `members` in `Walker`). `:325-329` `onlyAllocates` reads the same callee's effects through `CalleeEffects`. D13's `idr::effectsOf` exists only as an anonymous `calleeEffect` (`lib/IR/Effects.cpp:120-131`). |
| Counterexample | `returns` and "only allocates" come from two separate readings of one attribute. |
| Root cause | `returns` is a projection of `effects` carried as its own field, computed per route. |
| Correction | Export `idr::effectsOf(CallOp, const CalleeEffects&)` in `Flow.h`. `Call::returns = !(effectsOf(...) & diverge)`. `Outside` returns `optional<unsigned>`. |
| Deletion | `identities::Callee`, `defineCall`'s branch, `members` in `Record::walk`/`Walker`, and the lambda's test. |
| Consumers | `IR/Flow.h`, `lib/IR/Effects.cpp`, `Analysis/Identities.h`, `lib/Analysis/{Identities,IdentitiesRecord}.cpp`, `Optimize/Component.cpp`. |
| Discriminator | Identity fixtures unchanged. A box: a member calling a diverging outside callee gives back nothing. |
| Verification here | `make typecheck`. |
| Size and risk | About 15 lines and 4 branches go. Low risk. |
| Insight | 6, 16 |

### analysis-7: "callee final or not" travels as a null pointer through every callee hook
| Field | Content |
|---|---|
| Evidence | `Transforms/Optimize.h:112-117` (`summary()` is null). `ReadySet.cpp:98-101` (a second null), `:103-107` (an assert precondition on `of`), `:111-120` (`givesBack` returns `nullopt` for three states). `Constants.h:34-38` (`ConstantsOf` is null). `Constants.cpp:43-46` (a dead `direct ? … : nullptr`: every call past defunctionalization is an `idr.call`). `Effects/Constants.cpp:172-175` and `Inline/Inline.cpp:57-61` re-test. `Specialize.h:61-70` states the precondition only in a comment. |
| Counterexample | Pending, sibling and missing callees are all null. `givesBack` conflates "gives nothing" with "unknown". |
| Root cause | The scheduler's three callee cases are encoded as pointer nullness. |
| Correction | `ReadySet::callee(reader, name) -> variant<Final{const Summary&}, Sibling{const Solved&}, Pending>`. "No node" is not a case. Hooks take the variant; `BindingTimes::of` takes a `Final`. |
| Deletion | The double null, the assert, the three `nullopt`s, the `direct` arm, and three hook null tests. |
| Consumers | `Transforms/Optimize.h`, `Optimize/{ReadySet,Component,Optimize}.cpp`, `Analysis/{Constants,Specialize}.h`, `lib/Analysis/Constants.cpp`, `Transforms/{Effects/Constants,Inline/Inline,Identity/Identity,Specialize/Specialize}.cpp`. |
| Discriminator | Optimize, constants, inline and identity fixtures unchanged. The type check forbids `of` on a non-final node. |
| Verification here | `make typecheck`. |
| Size and risk | About 25 lines and 8 branches go. Low to medium risk (a hub). The three cases are essential; only the null goes. |
| Insight | 5, 8 |

### analysis-8: "a natural is ≥ 0" is applied at four sites, with and without the grade
| Field | Content |
|---|---|
| Evidence | `Ranges.cpp:30-37` seeds `isa<NatType>` on the type as written. `OpsBigs.cpp:21-26` clamps. `OpsScalars.cpp:79-90` `anyValue` looks through the grade (`unrestricted`). `Narrow/Facts.cpp:57-63` clamps again. |
| Counterexample | A `!idr.lin<!idr.nat>` block argument gets no seed, while `lin.use` of it gets one. The reader's clamp hides the gap. |
| Root cause | The range a type proves has no single home. |
| Correction | Export `anyValue` as `idr::ranges::ofType(Type)` (ignores the grade). `NaturalRanges::setToEntryState` joins it, and the op hooks intersect with it. |
| Deletion | The `isa<NatType>` seed, the `OpsBigs` hand clamp, and `Facts::of`'s clamp (2 branches). |
| Consumers | `IR/Ranges.h`, `lib/IR/{OpsBigs,OpsScalars}.cpp`, `lib/Analysis/Ranges.cpp`, `Narrow/Facts.cpp`. |
| Discriminator | A graded-natural case in `unittests/Ranges.cpp`. Narrow fixtures unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | About 15 lines and 4 branches go. Low risk. |
| Insight | 16 |

### analysis-9: the default effects have two storage forms
| Field | Content |
|---|---|
| Evidence | `IdrOps.td:126-145` uses `DefaultValuedOptionalAttr<Idr_EffectAttr, "anyEffect">`. `Func.cpp:116-127` has a verifier rule refusing the explicit default. `Effects.cpp:67-76` `setEntry` special-cases `anyEffect`. `Specialize/Raise.cpp:135` and `Specialization.cpp:35` call `removeEffectsAttr`. `Verify/Program.cpp:79` tests presence. The generated `Dialect/Idr.idr:307-309` has `Maybe MlirAttr`. |
| Counterexample | An explicit every-effect attribute is valid IR that the verifier must refuse so deduplication sees equal functions. |
| Root cause | An optional attribute admits both absence and an explicit default for one value. |
| Correction | `DefaultValuedProp<EnumProp<Idr_Effect>, "::idr::anyEffect">:$effects`. |
| Deletion | The verifier rule, `setEntry`'s branch, two `removeEffectsAttr` calls, and the presence test. |
| Consumers | `IdrOps.td`, `lib/IR/Func/Func.cpp` (parse 89, print 110), `Verify/Program.cpp`, `Analysis/Effects.{h,cpp}`, `Specialize/{Raise,Specialization}.cpp`, `Optimize/Waves.cpp`, `Contracts/Contracts.cpp`, the bytecode path, and the generated Idris dialect. |
| Discriminator | `--verify-roundtrip` on the `effects` fixtures. A dedup fixture: explicit-all and absent are one class. |
| Verification here | `make typecheck`, `make typecheck-dialects`. Round trip and bytecode run on the owner's build. |
| Size and risk | About 20 lines, 4 branches and a verifier rule go. Medium risk: the custom printer, and upstream/25's property bytecode bug nearby. |
| Insight | 4, 5 |

### analysis-10: Exclusivity's tables lose the type of a caller and say "none" twice
| Field | Content |
|---|---|
| Evidence | `Ownership.h:282-291` returns `optional<ArrayRef<Operation*>>` from `callers`/`returns`. `Exclusivity.cpp:108-113` records only live `CallOp`s. `:130-136` gives `returns` no entry. Consumers: `Transforms/Ownership/Specialize.cpp:68-73` does a `dyn_cast` and re-checks `live`, then dereferences `*callers(fn)`, guarded only by call order (`:60-62`). `Signatures.cpp:56-57` tests `returns && !empty`. |
| Counterexample | Calling `calledExclusive` first dereferences `nullopt`. |
| Root cause | The tables are typed as generic op lists, not as what they hold. |
| Correction | `optional<ArrayRef<CallOp>> callers` (`nullopt` only when callers are unknown), `ArrayRef<ReturnOp> returns`, bound once in `specializeOnGrade`. |
| Deletion | The `dyn_cast`, the `live` re-check, the unguarded `*`, and the optional's double test. |
| Consumers | `Analysis/Ownership.h`, `Ownership/Exclusivity.cpp`, `Transforms/Ownership/{Specialize,Signatures}.cpp`. |
| Discriminator | Ownership fixtures unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | About 10 lines and 4 branches go. Low risk. Kept: `Sharing`'s three values (at the end, `Unknown` means dead code). |
| Insight | 5, 6 |

### analysis-11: a take's field has two coordinates in Reuses
| Field | Content |
|---|---|
| Evidence | `Reuses.cpp:53-68` uses `Held = variant<Value, VirtualField{index}>`, `virtualOf` (`:254-259,268-269`). The public form is `TakenField{site, field}` (`Ownership.h:202-218`). `record` converts between them (`:232-238`), and `typeOf`/`usesOf` index by number. |
| Counterexample | Two numberings of one thing. |
| Root cause | The internal interning duplicates the public coordinate. |
| Correction | `Held = variant<Value, TakenField>` with `DenseMap<TakenField, Virtual>`. |
| Deletion | `VirtualField`, `virtualOf`, the numbering, and the conversion. |
| Consumers | `Analysis/Ownership.h`, `Ownership/Reuses.cpp`. |
| Discriminator | Reuse fixtures unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | About 15 lines and 3 branches go. Low risk. |
| Insight | 12 |

### analysis-12: Escapes passes a one-valued `Mode` and reads a missing state as "escapes"
| Field | Content |
|---|---|
| Evidence | `EscapesDetail.h:87-100` defines `Mode` and `part()`. All three calls pass `Shallow` (`Escapes.cpp:228,308`, `EscapesCycles.cpp:101`). `EscapesCycles.cpp:98-100` has `if (!state) return true`. |
| Counterexample | `Mode::Deep` is never passed. A con with no uses counts as escaping. |
| Root cause | A general parameter for one case, and absence read as top. |
| Correction | `own(Value, const Escape&)`, with a missing state read as `Escape{}`. |
| Deletion | `Mode`, the mode test, and the null branch. |
| Consumers | `EscapesDetail.h`, `lib/Analysis/{Escapes,EscapesCycles}.cpp`. |
| Discriminator | Stack fixtures unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | About 6 lines and 3 branches go. Low risk. |
| Insight | 5, 8 |

### analysis-13: `tail::Built = variant<ConOp, ReuseOp>` is an op interface not yet named
| Field | Content |
|---|---|
| Evidence | `Tail.h:40-57` ("what reads one reads either"). `Tail.cpp:19-39,72-74` has a ladder and three visits. Outside: `Tail/Trmc.cpp:85-97,120-129`, `Verify/OwnedOps.cpp:127`, `Expect/Does.cpp:36`. |
| Counterexample | A third cell-building op costs an arm everywhere. |
| Root cause | A shared op shape lives in a C++ variant instead of ODS. |
| Correction | `Idr_BuildsConstructorOpInterface` (`getDataType`, `getTag`, `getField`, `getHoles`, result) on con and reuse. |
| Deletion | `Built`, `opOf`, `fieldOf`, `fieldCount`, the `builtBox` ladder, the `isa` lists, and Trmc's overload pair. |
| Consumers | `IR/{IdrInterfaces,IdrOps,IdrOwnershipOps}.td`, `Analysis/Tail.{h,cpp}`, `Tail/Trmc.cpp`, `Verify/OwnedOps.cpp`, `Expect/Does.cpp`. |
| Discriminator | Trmc fixtures unchanged. |
| Verification here | `make typecheck`, `make typecheck-dialects`. |
| Size and risk | About 30 lines go. Low to medium risk. |
| Insight | 7 |

### analysis-14: Borrows is a hand-built dependency solver where MLIR's solver is the mechanism
| Field | Content |
|---|---|
| Evidence | `Borrows.cpp:73-85` (`Fact`, `Action`, `Own`), `:120-123` (the `became` loop), `:180-238` (`perform`, the `whenOwned`/`whenHolds` queues), `:293-300`. Precedent: Exclusivity's `Runs` state on `DataFlowSolver`. |
| Counterexample | Each new rule hand-adds a Fact, an Action and a waiting edge. |
| Root cause | It reimplements `getOrCreateFor` subscriptions. |
| Correction | One `DataFlowAnalysis` with a monotone "holds its own reference" `AnalysisState` per parameter and per read value, with the dependencies expressed as subscriptions. |
| Deletion | `Fact`, `Action`, `Own`, `waiting`, `became`, `perform`, and the queue arms. |
| Consumers | `Ownership/Borrows.cpp` (API unchanged). |
| Discriminator | Borrow fixtures and the `borrowed` statistic unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | About 60 lines and 6 branches go. Medium-high risk: the rules run both ways along call edges. Do it last. |
| Insight | 13, 14 |

### analysis-15: Borrows' `Holding::Fixed` lumps three reasons
| Field | Content |
|---|---|
| Evidence | `Borrows.cpp:66-71,135-157`: `start` maps root, no-references and quantity-1 parameters all to `Fixed`, and `paramOf` re-tests `holdsReferences`. Output: `Ownership.h:238`, consumed in `Signatures.cpp:25-36`. |
| Counterexample | `Fixed` for a word and for the root's box are one state that `paramOf` must split again. |
| Root cause | The internal lattice drops a case the output needs. |
| Correction | Add `Holding::Untracked`; `paramOf` becomes a pure map. |
| Deletion | The type re-test (1 branch). |
| Consumers | `Ownership/Borrows.cpp`. |
| Discriminator | Fixtures unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | Trivial. Fold into analysis-14's lane. |
| Insight | 4, 6 |

### analysis-16: the inline summary carries the decision's inputs, re-decided at every call
| Field | Content |
|---|---|
| Evidence | `Inline.h:33-51`: `Facts{size, calls, leaf, onCycle}` plus a separate `noInline`. `Inline.cpp:20-26` and `Transforms/Inline/Inline.cpp:64-65` re-decide per call. `Component.cpp:56-71` builds the facts. |
| Counterexample | Flag combinations travel to every call. |
| Root cause | The summary holds the inputs, not the verdict. |
| Correction | `Facts{int64_t size; bool inlines;}`, decided once in `finish`. |
| Deletion | `calls`/`leaf`/`onCycle` and the per-call `noInline` read. |
| Consumers | `Analysis/Inline.{h,cpp}`, `Optimize/{Component,Optimize}.cpp`, `Inline/Inline.cpp`, `Transforms/Optimize.h`. |
| Discriminator | Inline fixtures and the `inlined` statistic unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | About 10 lines go. Trivial. |
| Insight | 6 |

### analysis-17: a constant's field walk is defined in `Analysis/Labels.h`, not on `ConAttr`
| Field | Content |
|---|---|
| Evidence | `Labels.h:58-78` (`cellField`, `eachField`), used in `Labels.cpp:46`, `LabelSites.cpp:210` and `Defunctionalize/Declare.cpp:239`. `isRun()` (a null tail as the tag, `IdrAttrs.td:105`) is re-cased in about 15 IR, Specialize and Conversion sites. `IdentitiesRecord.cpp:258-260` has a `!isRun()` that `fields.empty()` already implies. |
| Counterexample | A reader that wants fields must know the run encoding. |
| Root cause | The attribute's two forms leak to readers that only need its fields. |
| Correction | `ConAttr::walkFields(fn(Attribute, unsigned))` on the attribute. |
| Deletion | The Labels.h helpers, the redundant test, and the run cases at field-only readers (to be counted by the IR lane). |
| Consumers | `IdrAttrs.td`, `ConAttr.cpp`, `Labels.h`, `lib/Analysis/{Labels,LabelSites,IdentitiesRecord}.cpp`, `Declare.cpp`. |
| Discriminator | Defunctionalize and static-data fixtures unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | Small here. The run form itself is essential. |
| Insight | 7, 8 |

### analysis-18: "this block ends a tail position" is written twice
| Field | Content |
|---|---|
| Evidence | `Tail.cpp:48-51` and `:121-123`. |
| Counterexample | Two edits per change. |
| Root cause | A missing predicate. |
| Correction | `bool endsTail(Block&)`. |
| Deletion | One copy (2 branches). |
| Consumers | `Analysis/Tail.{h,cpp}`. |
| Discriminator | Fixtures unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | Trivial. |
| Insight | 16 |

## Judged essential, kept

- **Labels' own 0CFA** (decided in bfdcac70), its union-find, and the empty `ArrayAttr` as the null object.
- **`observableRuns` apart from the effect bits.** It is asked before the conversion, over label edges the call graph lacks, and "observable" is finer than `Effect::io`.
- **Escapes' `Reach` and shallow/deep.** `escapes` crosses calls; `tailCalled` and `loops` are frame-local. Its redundant tops cost solver visits, not branches. `loopsAround`'s `nullopt` covers unknown region shapes.
- **Exclusivity's ordered `Sharing`.** At the end, `Unknown` is dead code, neither exclusive nor shared, and consumers ask both. Also kept: the `Calls` pair and `NoConstants`.
- **Ranges' `optional` result** (unreached proves nothing) and its `FailureOr` solve.
- **Identities' `Build` sum, its greatest fixpoint, and the slot↔argument map.** Neither it nor BindingTimes' tuple interpreter fits MLIR's IR-anchored solver better.
- **The three callee cases of analysis-7**; only their encoding as null goes.
- **Reuses' two `Held` cases, `whereDies`' empty-use case, and `heldIn`'s empty range.**
- **Inline's caller cap** (a policy), and Constants on upstream's lattice.

## Crossing into other areas

- IR: analysis-3, -4, -8, -9, -13, -17
- Optimize, Specialize and Inline: analysis-1, -7, -16
- Ownership transforms: analysis-10
- Tail and Conversion: analysis-2, -13
- Narrow: analysis-8