<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# transforms-a: representation survey

Area: `foreign/idr/lib/Transforms/{Specialize,Defunctionalize,Inline,Deduplicate,Identity,Canonicalize,Contracts,Expect,Columns,Narrow,Demand}` and their headers. Read whole, with the callers and types each value passes through (Optimize's ready set, Analysis/BindingTimes, IR's DataType/Ctor, the match ops, DataBody, ContentNames, the inliner interface). Evidence is source observation at HEAD 73d6dcf3 plus the working tree; nothing was run.

## The area as it stands

Most of the core representations here are sound. Defunctionalization keys each sum by (carrier, the solve's uniqued, name-sorted label `ArrayAttr`), so equal label sets are one key by attribute identity, and it makes every sum before any function converts. Specialization keys are uniqued dialect attributes named by canonical hash. Deduplication compares bodies through one rename map that it shares with raising.

The defects fall into four groups:
- **idr-expect.** It is a language of about 80 properties. Each property re-parses its own argument string, and each property's name is written three times. Because the arguments are strings, the contracts round-trip the module through a temporary file and skip every function whose name another function answers to.
- **Specialization's key machinery.** A C++ `Pattern` mirrors the key attribute only so that it can renumber hole indices, and those indices always equal the hole's pre-order position. A request holds its node kind twice and its owner three times. It compares keys across owners and kinds in flat lists. A raise key stores its consumer as printed text and parses it back. A made function's lifecycle is spread over a null field, a claimed set, a symbol lookup and a second node.
- **Facts other areas own that this area's code has to re-test.**
  - Two match ops with no shared interface: 25 `isa<MatchOp, MatchLitOp>` sites.
  - A five-case binding time whose one consumer reads one bit.
  - What a program stage implies, decided in several places.
  - A constructor role whose payload sits in separate fields beside it.
- **Small duplicates.** Columns lists the ops it converts twice. There are three copies of the op-remake helper and two definitions of "a wide lane". The inline legality rule lives outside the inliner interface.

## Findings, ranked (branches removed against risk)

### transforms-a-1: idr-expect's properties take their argument as text, and each property parses it itself

| Field | Content |
|---|---|
| Evidence | **The interface:** `include/idr/Transforms/Expect.h:52-53` defines `Check = LogicalResult(*)(ModuleOp, AnalysisManager&, StringRef argument)`.<br>**Each property parses its own argument:**<ul><li>14 `splitAt` calls (`Expect/Arguments.cpp:12-20`).</li><li>Two more hand-written parsers of `@f:@g`: `callerAndCallee` (`Does.cpp:75-83`) and `callsOfPair` (`Calls.cpp:81-93`).</li><li>43 `named(module, …)` calls, each followed by `if (functions.empty()) return failure();` (43 branches).</li><li>19 `function.empty()` failure branches, 6 `getAsInteger` error branches, 4 `symbolList`, 12 `rootsOf`.</li><li>A bracket- and quote-aware splitter written for one property: `itemsOf` and `unwrapped` (`Returns.cpp:34-78`).</li><li>A position written as two flags plus an index (`Closures.cpp:53-60`: `(!result && !parameter) \|\| … \|\| (parameter && position.empty())`).</li><li>Effects re-spelled by replacing characters (`SolvedEffects.cpp:25-34`).</li></ul>**Each property's name is written three times:** in `Lookup.cpp:12-96` (83 `.Case`), in 60 `constexpr StringRef property = "…"` constants plus 9 literals in `Does.cpp:106-133`, and in `Expect.h`'s comment list.<br>**Contracts are forced through the text:**<ul><li>Before every checked pass, `Contracts.cpp` prints the whole module to a temporary file so that `quantitiesKept` can read a path: `writeModule` (89-105), `Snapshot::printed`/`path` (`Contracts.h:43-48`), the write-failure branch (278-285), and the parse branches in `Quantities.cpp:96-100`.</li><li>It builds `"@" + symbol + ":0"` for crash-sites, and so it must skip any function whose symbol contains `:` or whose name another function also answers to (188-190, two guards).</li><li>The relation its own test breaks is a string, compared twice with a fallthrough error (246-259).</li></ul> |
| Counterexample | crash-sites-not-added is never checked for a function that has a specialization, a raise node, a deduplicated twin, or a lambda of its own definition. `names` (`Named.cpp:63-65`) answers for every function whose location names the symbol, and `Expect.h:17-24` says that Emit names every lambda's location after its definition and that every copy keeps its original's location. So `count_if(functions, madeFrom) != 1` holds and the contract is skipped. Separately, a malformed argument such as `crash-sites=@f:x` is caught only when that property runs, by that property's own parser and wording. |
| Root cause | A property's argument has a grammar, but no type. The shapes are: none, `@f`, optional `@f`, `@f:@g`, `@f:n`, `@f:[list]`, a file, `@f:values`, `@f:position:[list]` and `@f:effects`. The property itself is identified by a string. |
| Correction | **One table of property records** in `Lookup.cpp`, each `{name, Grammar, check}`:<ul><li>`Grammar` is a closed enum of the shapes above.</li><li>`check` takes a parsed `Argument`, a variant of: `Functions` (a non-empty list of `FunctionOpInterface`, already resolved by `names`), `Pair`, `Count`, `List`, `Module` (an `OwningOpRef<ModuleOp>`), `Values`, `Position{Result\|Arg, n}` and `Effects`.</li><li>`Expect::runOnOperation` parses `name=argument` once, by the record's grammar, and reports a malformed argument there.</li></ul>**Contracts call the typed cores directly:** `quantitiesKept(ModuleOp now, ModuleOp before)` against a `module->clone()` snapshot, and the crash-site count of the one `FuncOp` that was kept. `BreakContract::relation` becomes an enum `cl::opt` with `cl::values`. |
| Deletion | <ul><li>The error branches: 43 `functions.empty()`, 19 `function.empty()`, 6 count-parse and 14 `splitAt`.</li><li>`splitAt`, `callerAndCallee`, `callsOfPair`, `symbolList`, `itemsOf` and `unwrapped` as per-property code; one parser per grammar remains.</li><li>The 60 `property` constants and Does.cpp's literals.</li><li>In Contracts: `writeModule`, `Snapshot::printed`/`path`, the write-failure branch, the two crash-site guards and the `"@…:0"` string.</li><li>BreakContract's string compare and fallthrough error.</li></ul> |
| Consumers | `include/idr/Transforms/Expect.h`, all 52 `lib/Transforms/Expect/*.cpp`, `include/idr/Transforms/Contracts.h`, `lib/Transforms/Contracts/Contracts.cpp`. The syntax of the 246 test files' `--idr-expect=holds=` lines and `mlir.expect` files does not change. |
| Discriminator | A contracts test where `test-idr-break-contract` adds an `idr.crash` to a function that has a lambda or a specialization: `--idr-contracts` is silent today, and reports `contract crash-sites-not-added broken by …` after. `crash-sites=@f:x` fails at the request, with the grammar named, the same way for every property. The existing expect tests pass unchanged. |
| Verification here | `make typecheck` (C++ compiles). No property runs, because `idris-mlir-opt` links MLIR. |
| Size and risk | **Removed:** about 150 lines of parsing and more than 100 branches, plus a module print per pass under `--idr-contracts`.<br>**Risk:** low. The test syntax does not change; only the wording of malformed-argument errors does.<br>**Stays (essential):** each property's check, the `@f` = every-copy meaning, and one parser per shape. |
| Insight | 6 (parse once, at the boundary); 7 (one table dispatches); 14 (the argument language as data, not 80 ad hoc parsers). |

### transforms-a-2: The two match ops share no interface, so 25 sites ask `isa<MatchOp, MatchLitOp>` (crosses into IR)

| Field | Content |
|---|---|
| Evidence | `include/idr/IR/IdrMatchOps.td:16-38`: both ops share an ODS base whose `getCaseRegion`, `getDefaultRegion` and `getTakenRegion` are per-class C++ methods, not an interface. Generic code dispatches by hand:<ul><li>25 `isa<MatchOp, MatchLitOp>` pairs in 15 files. In this area: `Specialize/Raise.cpp:81`, `Columns/Columns.cpp:45`, `Expect/Placement.cpp` (4), `Quantities.cpp` (2), `Does.cpp:30`, `Returns.cpp`. Elsewhere: `lib/IR/Canon` (12), `Analysis/IdentitiesRecord.cpp` (2), `Tail.cpp`, `OpsClosures.cpp`.</li><li>Two hand-written dispatchers, `scrutineeOf` and `casesOf` with its `Case = variant<Attribute, Tag>` (`Placement.cpp:28-51`).</li><li>16 further single-kind `dyn_cast`s.</li><li>One pattern instantiated twice: `MatchColumns<MatchOp>` and `MatchColumns<MatchLitOp>` (`Columns/Calls.cpp:117-118`).</li></ul> |
| Counterexample | A site that lists only one of the two ops silently skips the other. `Quantities.cpp:68-73` must list both to find bound fields, and nothing catches a new site that forgets one. |
| Root cause | "A match" is one concept: a scrutinee, a region per case, an optional default, and the region a known value takes. It is held as two op classes with no common interface. |
| Correction | An `Idr_MatchOpInterface` in `IdrInterfaces.td`, declared by `Idr_MatchOpBase`, with `getScrutinee`, `getCaseRegion(i)`, `getDefaultRegion`, `getTakenRegion(Attribute)`, and `getCaseKey(i)`, which returns the case as an `Attribute` (a tag as an `IntegerAttr`, a literal as itself). |
| Deletion | The 25 pairs become `isa<MatchOpInterface>`. `scrutineeOf`, `casesOf` and its variant go, as do one `MatchColumns` instantiation and the per-class copies of the shared methods. |
| Consumers | IR (`IdrInterfaces.td`, `IdrMatchOps.td`, the match ops' `.cpp`) and the 15 files above. |
| Discriminator | Canon and expect tests pass unchanged, and a grep spec ("no `isa<MatchOp, MatchLitOp>`") holds. |
| Verification here | `make typecheck`. |
| Size and risk | **Removed:** about 25 conditions and two helpers.<br>**Risk:** low; this is pure dispatch.<br>**Stays (essential):** a constructor match binds fields and has a data type, and a literal match does neither. That difference stays in the two ops and in `getCaseKey`. |
| Insight | 7 |

### transforms-a-3: A binding time has five cases, and specialization reads one bit (crosses into analysis)

| Field | Content |
|---|---|
| Evidence | `include/idr/Analysis/Specialize.h:24-31` defines `BindingTime {Free, Fixed, Decreasing, Bounded, Other}`. Its one consumer, `specializesOn` (`Specialize/Keys.cpp:61-64`), reads only `Free \|\| Fixed`.<br>**Decreasing and Bounded are computed but no pass reads them** (`Analysis/BindingTimes.cpp`):<ul><li>the `Smaller` abstract value, `partOf` and the second case of `code` (61-81);</li><li>`join`'s Bounded rule (86-92);</li><li>four descent rules (field, `idr.big.pred`, positive `arith.subi`, match region) (173-193).</li></ul>They are only printed (`nameOf`, 35-49), and the header's prose for them ("the keys shrink along the chain…") describes the policy that 0007's D4/R08 replaced.<br>**Free is a fact about the function (on no cycle) written per parameter:** `bindingTimesOf` special-cases an acyclic component (239-246), `seenBy` builds a Free vector for a call that enters a component (`Specialize.cpp:260-270`), and `inherited` fills in Other (275-286). |
| Counterexample | Free and Fixed are different values that every reader treats the same; so are Decreasing, Bounded and Other. `tests/specialize-binding-times/specialize-binding-times.mlir` pins the spelling of distinctions no pass makes. |
| Root cause | The lattice of an earlier specialization policy outlived the policy. |
| Correction | `enum class BindingTime { Fixed, Varies }`. A parameter is fixed when every call within the component passes it unchanged in its own position, which on no cycle is vacuously true; so a parameter no call passes is Fixed. The abstract domain becomes `Same{param} \| Anything`. |
| Deletion | Free, Decreasing and Bounded; `Smaller`, `partOf` and the four descent rules; `join`'s lattice; the acyclic special case in `bindingTimesOf`; `seenBy`'s separate Free vector; `specializesOn`'s disjunction. |
| Consumers | `include/idr/Analysis/Specialize.h`, `lib/Analysis/BindingTimes.cpp`, `lib/Transforms/Specialize/{Keys,Specialize,Report}.cpp`, the description in `Passes.td`, and `tests/specialize-binding-times/specialize-binding-times.mlir` (rewritten to fixed/varies). |
| Discriminator | Every specialization result is unchanged, because the consumer's predicate selects the same set. `binding-times.mlir` states fixed and varies. |
| Verification here | `make typecheck`. |
| Size and risk | **Removed:** about 50 lines and 10 branches.<br>**Risk:** low; `specializesOn`'s truth table is preserved.<br>**Stays (essential):** the distinction between fixed and varies. |
| Insight | 12 (Free is Fixed, vacuously), 4, 16 |

### transforms-a-4: A key hole stores its index, which is always its pre-order position, and a C++ `Pattern` mirrors the key to renumber it

| Field | Content |
|---|---|
| Evidence | **The index:** `#idr.key_hole<index>` (`IdrAttrs.td:235-239`). Three sites keep the index equal to the hole's pre-order ordinal: `renumber` (`Patterns.cpp:90-98`), `append`'s `next` counter (`Keys.cpp:66-76`) and `liftPart`'s `sources.size()-1` (`Keys.cpp:166-170`). `oneShape` compares indices (`Keys.cpp:132-135`) and `rebuild` indexes `holes[i]` (`Patterns.cpp:154-155`).<br>**The mirror:** `Specialize.h:172-203` declares `Pattern` with the cases Hole, Constant, Con and Linear; Linear holds "exactly one" pattern in a `std::vector`. A `Pattern` exists to be renumbered and then converted into the attribute (`keyOf`, `Keys.cpp:199-212`; `leafOf`, `Patterns.cpp:60`). It duplicates the attribute's own predicate: `hasStructure` on the `Pattern` (`Patterns.cpp:103-109`) and `structured` on the key (`Specialize.cpp:152-161`) are the same test.<br>**Dead fields:** `Composed::held` and `Argument::time` (`Specialize.h:207-222`) are written and never read. |
| Counterexample | `#idr.spec_key<"f", [#idr.key_hole<1>, #idr.key_hole<0>]>`, and `[<0>, <0>]`, are representable and are distinct attributes from `[<0>, <1>]`. Only the order of construction rules them out, so a key built any other way would name a second node for one shape. |
| Root cause | A hole's identity is held as a number, when its position is the coordinate. |
| Correction | `#idr.key_hole` takes no parameter: the i-th hole of a key, in pre-order, is the node's parameter i. `shapeOf` builds the key attribute directly and appends leaves in pre-order. `fill`, `rebuild`, `liftPart` and `oneShape` walk holes with a cursor. |
| Deletion | `Pattern`, `Hole`, `Constant`, `Con`, `Linear`, `renumber`, `keyOf(Pattern)`, `leafOf` and `hasStructure(Pattern)`; `Composed::args` and `held`, and the `Argument` struct; `append`'s counter; `oneShape`'s index comparison. |
| Consumers | `IdrAttrs.td`; generated `compiler/src/IdrisMLIR/Syntax/Idr.idr`; `compiler/src/IdrisMLIR/SyntaxSamples.idr:130-142`; `tests/dialect-syntax/expected`; `Specialize.h`; `Keys.cpp`; `Patterns.cpp`; `Specialization.cpp`; `Redirect.cpp`; `Specialize.cpp`. |
| Discriminator | The illegal keys above no longer parse. Specialization outputs keep their behaviour; node names change with the key's spelling, and no test pins them. `one-clone` and `specialized-once` hold as before. |
| Verification here | `make typecheck`, `make typecheck-dialects`, and `SyntaxSamples` built on Chez. |
| Size and risk | **Removed:** about 90 lines.<br>**Risk:** low to moderate. Composition must number holes in the old order, which pre-order traversal does by construction.<br>**Stays (essential):** the three pattern cases: hole, constructor and constant. |
| Insight | 11 (position as the coordinate); one fact, one place |

### transforms-a-5: A raise key holds its consumer as printed text, which the build parses back

| Field | Content |
|---|---|
| Evidence | `KeyRaiseAttr(callee, consumer: StringAttr)`, "by the match's printed form" (`IdrAttrs.td:257-264`). `Forms::formOf` (`Consumer.cpp:111-134`) already holds each consumer as a detached `idr.func` (`Specialize.h:243-253`), compares consumers by `sameFunction`, and prints each one.<br>`buildRaise` (`Raise.cpp:117-129`) parses that text back with the verifier off. It raises an internal error when the text does not read back as one function, or when the callee is not a single block that returns. `decide` already excluded that second case (`Consumer.cpp:147-148`) on the same final function.<br>When `canonicalHash` names the node, the text is printed a second time inside the key (`Specialize.cpp:233`). |
| Counterexample | The key can hold any string. The internal error "does not read back as a consumer of its one block" can only fire if printing and parsing disagree, which is a state the representation admits. |
| Root cause | The consumer's identity (its content) and its code are one string, so the code has to be recovered by parsing. |
| Correction | `Forms` becomes the run's table of consumer forms: each is a detached `idr.func`, interned by `sameFunction`, with the canonical digest of its text. `KeyRaiseAttr(callee, form)` holds that digest. `buildRaise` clones the consumer from the table by key; `Nodes::build` passes the table in. |
| Deletion | The parse (`parseSourceString` and `ParserConfig`), both internal-error conditions, and the second printing. |
| Consumers | `IdrAttrs.td`, `Specialize.h`, `Consumer.cpp`, `Raise.cpp`, `Specialize.cpp`, `SyntaxSamples.idr`. |
| Discriminator | The raise tests (`tests/pipeline-one-pipeline`, `tests/optimize-caller-cap`) behave unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | **Removed:** about 25 lines and 2 internal-error branches.<br>**Risk:** low. |
| Insight | A string that names a thing is a missing type; 6 |

### transforms-a-6: A request holds its kind twice and its owner three times

| Field | Content |
|---|---|
| Evidence | `Want{Key key; owner; operands; optional<Consumer> consumer}` (`Specialize.h:230-238`): `consumer` is set exactly when `key` is a `KeyRaiseAttr` (`Consumer.cpp:154-160` against `171-175`). Readers branch on one or the other:<ul><li>`want->consumer ? RaiseAction : SpecializeCloneAction` (`Specialize.cpp:386-387`);</li><li>`want.consumer ? dispatch : call` and `if (consumer)` (`Redirect.cpp:62-63`, `70-76`);</li><li>the kind string (`Specialize.cpp:231`);</li><li>visits on the key in `Nodes::build` (329-332), `inherited` (278) and `operandsOf` (`Redirect.cpp:30-44`).</li></ul>`owner` is a copy of the key's own field: `= key.getOrigin()` for a specialization (`Consumer.cpp:173`) and `= key.getCallee()` for a raise (156). `Node::owner` copies it a third time (`Specialize.cpp:241`). The word "origin" names two things: `SpecKeyAttr::origin` is the owner, while `Node::origin` is the program function behind it. |
| Counterexample | A `Want` with a raise key and no consumer is representable. `redirect` would then build a call of the raise node with the call's own result types, which are not the node's. |
| Root cause | The node kind is a variant over keys, but the data that belongs to each kind sits beside it as optional fields. |
| Correction | `Want = std::variant<SpecWant{SpecKeyAttr; SmallVector<Value> leaves}, RaiseWant{KeyRaiseAttr; Consumer; SmallVector<Value> operands}>`. `ownerOf(Key)` is the one projection to the owner. The per-kind behaviour (action, name kind, build, binding times, operand types, the op replaced) is one visit. Rename `SpecKeyAttr::origin` to `owner`. |
| Deletion | `Want::consumer`, `Want::owner` and `Node::owner`; the three `consumer ?` branches; the kind string. |
| Consumers | `Specialize.h`, `Specialize.cpp`, `Consumer.cpp`, `Redirect.cpp`, `Keys.cpp`, `IdrAttrs.td` (the rename), `SyntaxSamples.idr`. |
| Discriminator | The wrong pairing does not compile. |
| Verification here | `make typecheck`. |
| Size and risk | **Removed:** about 5 branches and 3 fields.<br>**Risk:** low.<br>**Stays (essential):** specialization and raise are two kinds of node that build differently. |
| Insight | 4 |

### transforms-a-7: A requester's earlier keys are one flat list across owners and kinds, so every comparison re-tests both

| Field | Content |
|---|---|
| Evidence | `Requester::given` (`Specialize.cpp:78-95`) and `chainOf` (123-136) are `SmallVector<Key>` lists across all owners and both kinds. `judge` (196-208) compares the new key against each, and every comparison re-tests the pairing:<ul><li>`Order::grows` (`Keys.cpp:275-282`): two `get_if` and an origin test;</li><li>`differsInShape` (`Specialize.cpp:145-150`): two `get_if`;</li><li>`sameShape`'s origin test (`Keys.cpp:366-369`).</li></ul> |
| Counterexample | A new `map` key is compared against every `foldr` key the requester holds, and is false by the origin guard. A raise key is compared against every spec key, and is false by the kind guard. |
| Root cause | Keys that can only be compared within one owner are not indexed by owner. |
| Correction | `Requester` holds `DenseMap<StringAttr owner, SmallVector<SpecKeyAttr>>`. The raise keys it was given go in a set of their own, since they grow nothing and are never lifted (`Keys.cpp:271-274`). `chainOf` returns only the chain's spec keys of the new key's owner. `Order::grows` and `sameShape` then take two `SpecKeyAttr`s of one owner by construction. |
| Deletion | Four `get_if`s, two origin tests, and `differsInShape`. |
| Consumers | `Specialize.h` (the `Order` signature), `Specialize.cpp`, `Keys.cpp`. |
| Discriminator | Specialization tests unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | **Removed:** about 8 branches.<br>**Risk:** low.<br>**Stays (essential):** the embedding and the lift. |
| Insight | 11 (index by the coordinate that decides whether two keys compare) |

### transforms-a-8: What a program stage implies is decided in five places, in three forms (crosses into IR, analysis and Effects)

| Field | Content |
|---|---|
| Evidence | <ul><li>`Narrow/Facts.cpp:31-49`: a `counted(Stage)` switch with `llvm_unreachable`, in which Lowered is counted.</li><li>`IR/Verify/Program.cpp:187-212`: `StageFacts{closures, counted}`, in which Lowered is `nullopt`.</li><li>`Analysis/Identities.cpp:25`: `getStage() >= Stage::Owned`, meaning counted, by enum order.</li><li>`IR/Flow.cpp:288` (`!= Higher`) and `Transforms/Effects/Effects.cpp:31` (`== Higher`), both meaning closures.</li></ul> |
| Counterexample | A new stage between First and Owned changes Identities' answer silently, while it breaks the build of Narrow's switch and the verifier's switch. That is three different failures for one new case. Today Lowered is "counted" in one place and "has no facts" in another. |
| Root cause | A stage's facts are not data of the stage. |
| Correction | One total `constexpr StageFacts factsOf(Stage)` beside `ProgramOp`, holding `{closures, counted, holdsIdrFuncs}`. Each reader reads the field it means. |
| Deletion | Narrow's switch and its unreachable; the verifier's optional; the ordering comparison; the two equality tests against Higher. |
| Consumers | `Narrow/Facts.cpp`; IR (the ProgramOp header, `Verify/Program.cpp`, `Flow.cpp`); `Analysis/Identities.cpp`; `Transforms/Effects/Effects.cpp`. |
| Discriminator | Adding a stage fails to compile in exactly one place. |
| Verification here | `make typecheck`. |
| Size and risk | **Removed:** about 20 lines.<br>**Risk:** low.<br>**Kept:** Rc.cpp's `!= First` is a precondition on the pass, not a fact of the stage. |
| Insight | 7, 14 |

### transforms-a-9: idr-columns states which ops it converts twice

| Field | Content |
|---|---|
| Evidence | **Patterns** are registered per op in three files: `Calls.cpp:116-119` (6), `ArrayOps.cpp:111-115` (6), and `Tensors.cpp:233-243` (7, plus 7 registered by name).<br>**Legality** is listed again in `Columns.cpp:42-63`: 26 ops across five `addDynamicallyLegalOp` lists, with every other op legal by default (line 40).<br>**One body twice:** `MatchColumns` and `TabulateColumns` (`Calls.cpp:96-112`, `ArrayOps.cpp:40-56`). |
| Counterexample | An op that has a pattern but is not in a legality list is legal by line 40, so it is never converted and is silently gathered at its boundary. An op in a legality list with no pattern fails with "internal error: idr-columns". |
| Root cause | "idr-columns converts op X" is held as two facts: a pattern and a legality entry. |
| Correction | One registration helper per op that adds the pattern and its legality together, as upstream's `populate…AndLegality` helpers do. The default legality is `converter.isLegal(op)`; the special legalities travel with their patterns. One `ResultColumns<Op>` template replaces the two identical ones. |
| Deletion | The five lists in `Columns.cpp` and one of the two templates. |
| Consumers | `Columns.h`, `Columns.cpp`, `Calls.cpp`, `ArrayOps.cpp`, `Tensors.cpp`. |
| Discriminator | Columns tests unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | **Removed:** about 40 lines.<br>**Risk:** low.<br>**Stays (essential):** the special legalities: FuncOp's signature, the fold or scan region, a select with a shaped condition, and a yield under an update. |
| Insight | One fact, one place; 14 |

### transforms-a-10: A made function's lifecycle is spread over a null field, a claimed set, a symbol lookup and a second node (crosses into Optimize)

| Field | Content |
|---|---|
| Evidence | <ul><li>`specialize::Node::fn` is "null until build", and `times` is "written by build" (`Specialize.h:75-80`).</li><li>Whether the node is claimed is `State::claimed` (`Specialize.cpp:109`, `316-319`).</li><li>Whether it is in the program is asked of the schedule by name (`inProgram`, 188-191; the double condition at 229).</li><li>`node.fn == requester` compares a possibly null `fn` (252).</li><li>Once placed, it becomes `optimize::Node` with `Made{times}`, the times moved out of the first node (`Optimize.h:104-110`, `Waves.cpp:198`), and is found again through `ReadySet::byMade` (`Optimize.h:227`; `Component.cpp:160-161`; `Waves.cpp:247-250`).</li></ul> |
| Counterexample | All of these are representable: a node in `claimed` whose `fn` is null after a failed build; a node whose `times` were moved out but which `find` still returns; a missing `byMade` entry (the `!target` test in `parks`). |
| Root cause | The phases Requested → Built → Placed are not a state of the node. |
| Correction | `specialize::Node::state : variant<Requested, Claimed, Built{FuncOp, times}, Placed{optimize::Node*}>`, with transitions made under the table's lock. `optimize::Node::Made` holds the `specialize::Node*` it came from. |
| Deletion | `State::claimed`; `fn` and `times` as free fields; `inProgram` and the double condition; `ReadySet::byMade`; `parks`' `!target` test. |
| Consumers | `Specialize.h`, `Specialize.cpp`, and in Optimize: `Optimize.h`, `Waves.cpp`, `Component.cpp`, `ReadySet.cpp`. |
| Discriminator | Determinism across thread counts is unchanged. |
| Verification here | `make typecheck`. |
| Size and risk | **Removed:** about 10 branches.<br>**Risk:** moderate, because this touches scheduler concurrency and wave ordering.<br>**Stays (essential):** the phases themselves. |
| Insight | 4 |

### transforms-a-11: A constructor's role and its payload are independent fields (crosses into IR)

| Field | Content |
|---|---|
| Evidence | `Ctor{name, fields, bool byName, CtorRole role, fn}` (`IdrDialect.h:262-277`). The verifier guards the invalid combinations (`DataBody.cpp:74-81`). Consumers in this area:<ul><li>`Defunctionalize/Forces.cpp:62-90`: a switch on role with `llvm_unreachable` for Plain, ListNil and ListCons in a memo sum;</li><li>`Declare.cpp:164-172`: builds constructors positionally, `{…, false, CtorRole::Running, FlatSymbolRefAttr()}`;</li><li>`Columns/Records.cpp:29-33`: re-tests `ctor.role != Plain` after it has already tested the kind is Plain;</li><li>`Expect/Closures.cpp:76-78`: filters `role == Label` inside a closure or memo sum.</li></ul> |
| Counterexample | `{role = Plain, fn = @f, byName = true}` is a value of the struct. Only the body verifier rejects it, and every switch on role inside a memo sum must say what Plain would mean there. |
| Root cause | Data that belongs to one role is not carried by that role. |
| Correction | **The role becomes a sum with payload:** `variant<Plain, ListNil, ListCons, Label{fn, byName}, Running, Forced>`. The generated `CtorRole` enum stays as its discriminator, and D1 ("role, never position") is kept.<br>**A typed view of a memo sum:** `DataType::memo()` returns `{labels, running, forced}`, so the dispatch function iterates the labels and the two states with no switch. |
| Deletion | The verifier's two field-combination rules; Forces' switch and its unreachable arm (3 cases); Records' redundant test; the positional construction. |
| Consumers | IR (`IdrDialect.h`, `Types.cpp`, `DataBody.cpp`, the role generator); `Forces.cpp`; `Declare.cpp`; `Records.cpp`; `Expect/Closures.cpp`; every reader of `ctor.fn` or `ctor.byName` (32 `CtorRole::` sites in lib). |
| Discriminator | A plain constructor that names a function no longer compiles. |
| Verification here | `make typecheck`. |
| Size and risk | **Removed:** about 10 branches.<br>**Risk:** moderate, because `Ctor` is read everywhere.<br>**Stays (essential):** the roles. |
| Insight | 4, 5 |

### transforms-a-12: The defunctionalization decision is half-built between phases, and a nested sum's failure is a flag the recursion cannot see

| Field | Content |
|---|---|
| Evidence | <ul><li>`Sum::type` is null until `define` (`Defunctionalize.h:159-162`), and `typeOf` asserts it (`Declare.cpp:51-53`).</li><li>`Signature::converted` is empty until `declare` (`Defunctionalize.h:89-93`, `Declare.cpp:77-85`).</li><li>`defineForces` is a separate later step (`Pass.cpp:114-117`).</li><li>`bool broken` (`Defunctionalize.h:202`) is set by `define` when `DataType::define` fails (`Declare.cpp:129-131`). But a nested `define`, reached through `slotType`, returns a null `DataType`, and `held` wraps it at once (`Declare.cpp:39-42`, `137-141`), before `declare` reads the flag (75-76).</li></ul> |
| Counterexample | If the body verifier refuses a capture type two levels down a closure sum, the code reaches `BoxType::get(DataType())`, or a body with a null field, instead of the internal error the flag was meant to report. |
| Root cause | The decision is one object mutated through phases rather than a value returned when complete, and a failure inside a callback that cannot return failure is recorded in a side flag. |
| Correction | `declare` returns `FailureOr<Decision>`: the sums with their types, the converted signatures, the dispatch functions already defined, and the constants. Nested definition returns `FailureOr<Type>` through `slotType` and `body`, and `DataType::define`'s callback returns `FailureOr<Body>`. |
| Deletion | `broken`; the null-type state and its assert; `converted` as a field filled in later; `defineForces` as a separate step. |
| Consumers | `Defunctionalize.h`, `Declare.cpp`, `Forces.cpp`, `Pass.cpp`, `Patterns*.cpp`, `Converter.cpp`; IR's `DataType::define`. |
| Discriminator | A unit test that defines a sum over an unsupported field type gets an internal error, not a crash. |
| Verification here | `make typecheck`. |
| Size and risk | **Removed:** about 20 lines.<br>**Risk:** low to moderate. |
| Insight | 5, 6 |

### transforms-a-13: The inline legality rule lives outside the inliner interface (crosses into IR)

| Field | Content |
|---|---|
| Evidence | `fitsRegion` (`Inline.h:27-31`, `Inline.cpp:35-43`) decides whether a multi-block body may go into the call's region. It does so by comparing `parent->getName() == callee->getName()`, a name standing for "the parent is an idr.func". Both inline sites must remember to call it (`Inline.cpp:65`, `Optimize/Contify.cpp:100`), while `IdrInlinerInterface::isLegalToInline(Region*, Region*, …)` returns true unconditionally (`lib/IR/Func/Inliner.cpp:26-28`). |
| Counterexample | Any inline site that does not call `fitsRegion` (an upstream inliner pass, say) puts a multi-block body into an `idr.match` region, which is SingleBlock. |
| Root cause | A legality rule of the dialect is held by a helper of one pass. |
| Correction | `IdrInlinerInterface::isLegalToInline(dest, src, …)` returns false when `src` needs blocks of its own and `dest`'s op is SingleBlock. `inlineCall` then fails, with nothing changed; both sites already handle that failure. |
| Deletion | `fitsRegion`, its declaration, the two call-site conditions, and the name comparison. |
| Consumers | `Inline.h`, `Inline.cpp`, `Optimize/Contify.cpp`, `lib/IR/Func/Inliner.cpp`. |
| Discriminator | Inline and contify tests unchanged. The `capped` statistic may count a call that does not fit; test the cap after legality, or accept that. |
| Verification here | `make typecheck`. |
| Size and risk | **Removed:** about 15 lines and 3 conditions.<br>**Risk:** low. |
| Insight | 7 (an MLIR mechanism not used yet) |

### transforms-a-14: "Computes on wide lanes" is defined twice

| Field | Content |
|---|---|
| Evidence | `Narrow/Widths.cpp:73-88` `widthOf`: elementwise and not a cast. `Expect/NarrowedLanes.cpp:26-42` `laneBits`: elementwise, not a cast, and not an `arith.select`. The same property calls the pass's own `accumulations` and `runsAtMostOnce` (47, 86). |
| Counterexample | A vectorized loop whose only 64-bit lane op is a select: idr-narrow-lanes versions it, and narrowed-lanes asks for no version. |
| Root cause | One predicate is held in the pass and copied, differently, into its test. |
| Correction | One `narrow::laneWidth(Operation*)` that decides about select once, called by both, as `accumulations` already is. |
| Deletion | `laneBits`. |
| Consumers | `Narrow.h`, `Widths.cpp`, `Expect/NarrowedLanes.cpp`. |
| Discriminator | A loop whose only wide op is a select. |
| Verification here | `make typecheck`. |
| Size and risk | **Removed:** about 15 lines.<br>**Risk:** low. |
| Insight | One fact, one place |

### transforms-a-15: Three copies of "make the op again with new operands and types, moving its regions"

| Field | Content |
|---|---|
| Evidence | `Specialize/Raise.cpp:37-50` (`retyped`), `Columns/Records.cpp:251-264` (`remake`), and `Defunctionalize/Patterns.cpp:247-262` (inside `RetypePattern`, which also handles successors). Upstream has `convertOpResultTypes` (`DialectConversion.h:804-807`) for the case without regions. |
| Counterexample | A fix to one copy (successors, say, which only defunctionalization's copy handles) misses the other two. |
| Root cause | A helper written three times. |
| Correction | One `idr::remakeOp(RewriterBase&, Operation*, ValueRange, TypeRange)` in Support, which keeps properties, discardable attributes and successors and moves the regions. |
| Deletion | Two copies. |
| Consumers | The three files, plus `Support`. |
| Discriminator | `make typecheck`. |
| Verification here | `make typecheck`. |
| Size and risk | **Removed:** about 25 lines.<br>**Risk:** low. |
| Insight | One fact, one place |

## Judged essential, and kept

- **Deduplicate's own equivalence** (`Equivalence.cpp`) over upstream's `OperationEquivalence`. Upstream compares raw attributes; it cannot read a symbol reference through the renames of classes found below, or read a self-reference as the other function's name. The hash and equality pair is the one definition, and raising's `Forms` shares it.
- **Deduplicate's reference graph built from symbol uses** rather than `CallGraph`. It runs before defunctionalization, where a closure's label is a symbol use that no call graph sees.
- **Defunctionalization's key `(carrier, labels)`.** Equal sets are equal attributes, and a key's constructors in label-name order make `labelTag` a binary search with no table. `rebuildIn` returning null is the conversion framework's protocol for a failed materialization.
- **The pattern language's three cases** in `shapeOf`, `rebuild` and `holeTypes`: hole, constructor and constant.
- **`liftPart`** taking a non-run constant constructor apart while lifting a run whole: runs never unroll, by 0007's M7.
- **`Order`'s two measures**, structural embedding for key constructors and size for constant constructors: the termination argument's choice.
- **Specialization and raise as two node kinds** (Brooks): they build differently.
- **Narrow's `wordOf` `if constexpr` ladder** over the generated `BigToWord` table: identity, comparison, truncation, max-with-constant and binary op are genuinely different shapes of word op.
- **Narrow's `descends`** over `scf.while`. It is a different question from descent over calls, because it follows the continue-decision on each path, and after transforms-a-3 nothing else asks about descent.
- **`Facts::madeBounds`.** The program's solver is read by functions in parallel and is never written, so each function keeps its own bounds for the values it makes.
- **Demand re-deriving the rebuilt parameters** from reuse → take → parameter. The uniqueness refusal is a user refusal that must be raised by a pass; a signature type would turn it into a verifier error.
- **Contracts' `linear-kept`** comparing results by position and skipping a function whose arity changed: a result has no identity but its position.
- **quantities-kept** identifying a binder by its location key and dropping ambiguous keys: the location is the only identity that survives every pass's copying.
- **Identity's node lookup by name, with an assert.** MLIR gives an inner pass no per-run argument besides its op.
- **Inline skipping a callee whose summary is null.** A callee in the caller's own component is genuinely not final.
- **Canonicalize.** Upstream's canonicalizer with a bound table. The nullable `CalleeEffects*` is IR's: absence means two different things in `lib/IR/Effects.cpp`, the operand's grade in one function and every effect in the other. It is not counted here.
- **The `@f` = every-copy meaning of `names`** in idr-expect: tests name source definitions, deliberately.
