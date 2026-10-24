<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# Rederivation audit: identities and names

Family: every place a thing (a function, an op, a property, a data type, a
block, a runtime function, a package, a primitive, a registry entry, a static
datum) is identified or compared by its printed name, a string, a hash of
text or a lookup by name, in the frontend, the specification's generator, the
TableGen backend, the C++ and the harness; for each, the typed identity that
should carry it.

- HEAD at start: `eedaf5d40a36a5423c2516364871ea901c2aaec7`.
- HEAD at finish: `d73863f5e4377ce21574b94896868b12f9403fe9` (three commits
  landed meanwhile: L18aa's two and D133's design. 8b2cd180 touched
  `Specialize.h` and `Specialize/Open.cpp`, cited in 5 and in the kept list;
  their cited lines were re-read at d73863f5 and stand. The others touch only
  the spec's regrade ops, the queue, a handoff and the proposal).
- Read-only. Nothing was built or run but greps over the checkout and the
  pinned MLIR tree (`.toolchain/llvm-project/mlir`); no C++ tool is built on
  this machine, so no cost below is measured. One number is quoted from
  another lane's measurement and says so.
- Grounds: **read** (seen in the code at the lines given), **conjecture**
  (magnitude or a carrier's detail not checked). Owners by
  `audits/p0/verify/ownership.json`. "Modified" means `git status` showed the
  file modified at the time of this audit, so the fix waits on the lane that
  holds it.

Ranked by how much rederiving the fix deletes: lines of code whose only job
is to recover the fact, then the work per compile it stops.

---

## 1. Which definitions a program uses: printed back out of the module and the source (harness `covers`)

**Fact.** Which Idris definitions the compiled program uses at run time, and
for each its registry fate (called; lowered by a hook to an op or a value;
ruled out by a rule).

**First known.** The frontend's reading:
`compiler/src/IdrisMLIR/Frontend/Translate/Boundary.idr:1122-1192`
(`readProgram`): every definition read, by entry (`met.found`,
`definitions : SortedMap Int (DefinitionRead ())`), each with what the
registry makes of it (`registeredOf`, Boundary.idr:296-305; its lowering read
against its type, `checkedRow`, 781-796). The registry's ruled-out names are
`Registry/Recognized.idr:216-222, 273`.

**Dropped.** Emit carries the set into the module only as printed text:
function symbols (`keyText`, `Term.idr:2065`), `NameLoc` text of `show n`
(`MLIR/Bytecode.idr:449-455`), family labels (`Emit/Index.idr:373-375`,
`keyText f.key`). A definition a hook lowers to a value leaves nothing.

**Re-derived.** `harness/Covers.idr`:
- 521-528 `moduleNames`: runs `idris-mlir-opt --mlir-print-debuginfo` to
  print the whole module as text;
- 343-509: a character scanner over that text (`Scan`, `scanLine`: string
  kinds, family aliases, bracket depth) collecting symbols, location names
  and `label::ctor` refinements;
- 533-578 `typeOfSpace`, 580-624 `moduleUses`: each prelude export's full
  name matched against the printed names by prefix, `[`key, `;hash`, an
  `_Instance` suffix (`Prelude.Num.fromInteger_Num_Int`) or a `::ctor` after
  a family label;
- 681-735 `sourceCalls`: the fixture's source text scanned for the bare or
  qualified spelling of a name;
- 757-760 `registryValue` and 743-748 `decidedExclusion`: hand copies of
  the registry's entries, because "the registry's hooks are the compiler's
  Idris source, which this check cannot ask" (754-756).

Cost: per `covers` test, a print of the whole module and a scan of it and of
the sources; heuristics that can attribute a printed name to the wrong
export; two copies of compiler knowledge kept in step by hand.

**Carrier.** The frontend's own typed table of what it read (`Read`'s
definitions by entry, each with its `Registered` hooks, and the refusal rule
of a ruled-out one, a `SomeRule` of the specification), written once per
compilation as an artifact beside the report and the timing the frontend
already writes, each definition by the checker's full name (the printer
`:browse` uses) and its fate from a closed set. The harness reads closed sets
through `Facts` as it reads verdicts; nothing is matched by spelling.

**Deletes.** `harness/Covers.idr` 343-624 (about 280 lines: `Kind`,
`Waiting`, `Scan`, `startScan`, `emit`, `symbol`, `unescaped`,
`symbolChar`, `aliasChar`, `scanLine`, `moduleNames`, `typeOfSpace`,
`moduleUses`), 676-760 (about 85: `sourceCalls`, `decidedExclusion`,
`registryValue`), the module print in `coversPrelude` (880), and the doc
lines 5-16 that describe the scan. About 365 lines.

**Owner.** L19 (harness/), waits on L16 (the frontend writes the table).
`harness/Covers.idr` clean; `Boundary.idr` modified (L16). Ground: read.

---

## 2. A `where` block's parent: lost by the checker, re-walked by the frontend

**Fact.** The definition a nested (`where`) block belongs to, and its
ordinal under it, which the block's printed name (`Parent.name<k>`) and so
its symbol is made from.

**First known.** The checker, at elaboration:
`compiler/checker/src/TTImp/Elab/Local.idr:89`
`Nested (outer, nextName ust) inner`: the parent is `outer`, its index in
the elaborating context, beside a session-wide counter
(`Core/Name.idr:43`, `Nested : (Int, Int) -> Name -> Name`).

**Dropped.** The TTC writes the pair as two integers; loading renumbers every
`Resolved` index, so after loading `outer` names nothing
(`Frontend/Translate/Boundary.idr:647-648` says so). Case and with blocks no
longer lose it: the checker now mints `CaseBlock (parent : Name) (ordinal :
Nat)` and `WithBlock` likewise with a per-parent count
(`Core/UnifyState.idr:203-227`, `Core/Name.idr:49-50`), and the frontend
reads them directly (`Translate/Keys.idr:73-77`, `typedBlock`).

**Re-derived.** `Boundary.idr:503-654`: a walk of every definition's body
and type references, from `main` and then from every definition read
(`blockNamesOf`, called at 1191), naming each block after the definition that
refers to it first, `origin.kindN` with per-parent counters, kept as
`SortedMap Address String`; carried on as `State.idr:1198` `WalkedName`,
`State.idr:1210` `Nature.called`, `State.idr:1408-1413` `natureFrom`,
`TypeConstructors.idr:605-609` `readWhole`'s `called`, and
`Keys.idr:89-96` `keyOrigin`'s walk branch. The walk names case and with
blocks too, which `typedBlock` then overrides; its doc (Boundary.idr:503-509)
still says case and with blocks are numbered "with one counter for the whole
build", stale since the per-parent ordinal. Cost: one walk of the whole
program's definitions per compile, a string per block.

**Carrier.** `Nested (parent : Name) (ordinal : Nat) inner` in the checker,
minted by the same `nextBlockOrdinal` (UnifyState.idr:206-213) and written by
the TTC as a `Name`, which loading resolves like any other; `typedBlock`
reads a nested block's name as it reads a case block's. The checker is ours
(D118, C233) and the case and with blocks already took exactly this form.

**Deletes.** `Boundary.idr:503-654` (about 150 lines: `BlockKind` and its
instances, `kindText`, `referentsOf`, `Reached`, `nameUnder`,
`blocksFrom`, `nameBlocksOf`, `blockNamesOf`) and the call at 1191;
`WalkedName`, `Nature.called`, `natureFrom`'s and `readWhole`'s `called`;
`keyOrigin` becomes `typedBlock` or `plainOrigin`. `blockOf` stays only as
the name's own predicate (Programs.idr:164, Keys.idr:1005). About 180 lines,
and the per-compile walk.

**Owner.** L17 (checker: `Core/Name.idr`, `TTImp/Elab/Local.idr`,
`Core/TTC.idr`, `Core/Reflect.idr`), then L16. Waits on both:
`Core/TTC.idr` modified (L17); `Boundary.idr`, `State.idr`,
`TypeConstructors.idr` modified (L16). Ground: read.

---

## 3. Op properties by name across the Idris-to-MLIR boundary

**Fact.** Which inherent attribute (property) of which op a value fills, and
which op an op is.

**First known.** The specification: an op is indexed by its attribute count,
so every reference is a position (`compiler/spec/IdrisMLIR/Spec/Core/Op.idr`
header and 101-114, `Attr`); each generated builder knows each property
statically.

**Dropped.**
- `compiler/spec/IdrisMLIR/Spec/Generator/Idris.idr:167` emits each property
  as its name string (`attrIf "callee" …`, `[("rule", …)]`), 213 each op as
  `MkOpName Dialect.X "mnemonic"`; idris-mlir-tblgen's `-gen-idris-dialect`
  does the same for the upstream ops. About 110 property-name literals in
  `compiler/src/IdrisMLIR/Dialect/*.idr`.
- `compiler/src/IdrisMLIR/MLIR.idr:229-230` (`attrIf`), 274-287: an `Op`
  holds `properties : List NamedAttr`, keyed by `String`, and its name as
  `OpName` text.
- `MLIR/Bytecode.idr:796-805`: properties and discardable attributes written
  as one `DictionaryAttr`, each name a string entry (`numberEntries`,
  704-712); the properties section written empty (993; header 13-20).

**Re-derived.** On load (pinned MLIR): the reader sorts each op's dictionary
by name; `Operation::create` calls `setAttrs(DictionaryAttr)`
(`lib/IR/Operation.cpp:145, 301-318`), which asks `getInherentAttr(name)`
and `setInherentAttr(name, value)` for every entry, ODS-generated ladders of
one `if (name == "…")` per property (`tools/mlir-tblgen/OpDefinitionsGen.cpp:
1498-1507`), then makes a new dictionary of the rest; `populateDefaultAttrs`
by name per op. On the Idris side each name is looked up per op in the
string table (`stringNumber`) and the dictionary's bytes in the attribute
table, and each op's name in `opNameTable` keyed by `(Nat, String)`
(Bytecode.idr:326, 345-348). Per op, per property, every compile.

**Carrier.** MLIR's native property encoding: each op's ODS-generated
`writeProperties`/`readProperties` (OpDefinitionsGen.cpp:1621-1716), the op
mask's `kHasProperties` and the properties section
(`include/mlir/Bytecode/Encoding.h:94, 117`). The specification generates,
per op, a positional property writer from the op's attribute list, the list
ODS generates `readProperties` from, and builders take typed properties.
The op's name number comes from the specification's op index (the generated
`OpIndex.h.inc` already lists every op of ours and every admitted upstream
op; see 14).

**Deletes.** The property-name literals of the generated builders and their
emission (Generator/Idris.idr:167; tblgen's builder emission); `attrIf`'s
name parameter; `Op.properties` as a name-keyed list; the properties half of
Bytecode.idr:796-805 and `numberEntries`' use for them; the text key of
`opNameTable`. No C++ of ours goes; MLIR's per-op string ladders and the
dictionary sort stop running.

**Owner.** L03 (specification generator, idris-mlir-tblgen) and L16
(`MLIR.idr`, `Bytecode.idr`, the generated builders under compiler/src).
`compiler/spec/IdrisMLIR/Spec/Pipeline/Pipeline.idr` modified (L03); the
files named here are clean. Ground: read (the cost per op is conjecture).

---

## 4. A data type's family group: re-encoded at every type occurrence

**Fact.** A family group's identity in the module (its `#idr.family`
attribute entry).

**First known.** `compiler/src/IdrisMLIR/Emit/Index.idr:399-410`
(`declare`): each group's attribute built once, in declaration order, keyed
by its typed `FamilyId` (`Ids.idr:31-38`: "this number only finds it in the
table").

**Dropped.** `Emit/Index.idr:150-156` (`typeIn a (DataT f ts)`): every type
occurrence holds the group's whole attribute value (`e.group`) and the
`FamilyId` is dropped at the `MlirType` boundary. A group's attribute names
earlier groups' members by their whole attributes (Index.idr:396-398), so a
group value holds every group it reaches.

**Re-derived.** `MLIR/Bytecode.idr:585-586` (`numberIdrType … DataType`) →
697 `attrNumber w (Idr a)` → 724 `numberIdrAttr … FamilyAttr` →
`numberMembers` → every constructor's field types → every earlier group they
name, as a tree (Idris values are not shared by the walk), then the encoded
bytes are looked up in the attribute table (`number`, 253-264; the key
compared byte by byte, `compareBytes` 276-282). No memo: each type
occurrence (every op result, block argument and signature type) re-walks the
transitive closure of its family's declaration. The header (Bytecode.idr:
11-12) says "a family is written once however many types apply it": written
once, found again every time. Context, measured by INT-24 (a0d5c9c3,
`/tmp/int24/self/knowngen/out/timing`): `emit` 1638 ms of 19.6 s for
knowngen; the walk's share of it is not measured.

**Carrier.** The `FamilyId`: the writer numbers each group once, in the
Index's declaration order, and a data type in `MlirType` refers to its group
by that typed identity (an `MlirAttr` case resolved through the table the
writer fills first), so a type occurrence costs its own index terms and one
lookup by a number.

**Deletes.** The per-occurrence walk (the numbering functions stay, called
once per group); the whole-attribute payload in each `DataType` occurrence.
Few lines; the work per type occurrence goes from the size of the reachable
family tree to constant.

**Owner.** L16. `Emit/Bodies.idr`, `Emit/Monad.idr`, `Emit/Operations.idr`
modified (L16); `Emit/Index.idr` and `MLIR/Bytecode.idr` clean. Ground: read
(magnitude conjecture).

---

## 5. A content digest recomputed on every call, though its comment says it is kept

**Fact.** The process-independent content digest of an attribute or a type
(`stableDigest`), which names specialized copies, raise copies, closure
families and static data.

**First known.** When the uniqued attribute or type is made; its content
never changes after.

**Dropped.** `foreign/idr/lib/IR/ContentNames.cpp:171-193`: `digestOf`
starts from an empty `Digests done` scratch map on every call (comment
36-40: "one digest's scratch, gone when the digest returns"), so nothing is
kept. `foreign/idr/include/idr/Transforms/Specialize.h:132-134` claims the
opposite ("by the digest of its content computed once when it was made").

**Re-derived.** Every call re-encodes the whole value, a data type through
its whole family group:
- `Transforms/Deduplicate/Deduplicate.cpp:188-228` (`structuralDigest`):
  per function, a digest of every op result type, block argument type and
  attribute dictionary, and every op's name written as text (209-211);
  called from `Transforms/Specialize/Consumer.cpp:51-52` for every consumer
  a request builds (a consumer function is cloned and digested per call
  site that may raise, 389-392), only to bucket it;
- `Specialize.h:135-136` (`Bytes::attribute`, `Bytes::type`) per key named;
- `Transforms/Defunctionalize/Declare.cpp:69` per closure family key;
- `Conversion/StaticNames.cpp:57, 64, 71-72` per static reference (see 6).

**Carrier.** The digest held in the storage of our attributes and types,
computed in the storage constructor from the parameters' own digests (a
Merkle digest), so `stableDigest` is the parameters' digests combined, not a
walk; builtin leaves (integers, strings) are digested directly. For the
in-process bucket of `Forms::intern`, the uniqued values' identities, as
upstream's `OperationEquivalence` hash uses them; the digest only where a
name is made.

**Deletes.** The per-call walk and scratch map in ContentNames.cpp:171-193;
the stale comment Specialize.h:132-134; Consumer.cpp's digest per request.

**Owner.** L04 (`ContentNames.cpp`, `Symbols.h`); callers L18
(Specialize, Deduplicate, Defunctionalize), L21 (StaticNames).
`Families.h` modified (L04), `Specialize/Open.cpp` modified (L18); the
files named here are clean. Ground: read.

---

## 6. A static datum's global: named by a digest of its content, found again by recomputing it

**Fact.** Which global holds a static datum (a constant cell run, a string,
a big, a crash site's text, the homes array).

**First known.** `foreign/idr/lib/Conversion/Lower/Statics.cpp:84-120`
(`idr-lower-statics`): each datum's global made once, "under the name of its
content (StaticNames), which the lowering's reference to it reads"
(Statics.cpp:3-11).

**Dropped.** At the pass boundary: the constant op keeps only its attribute;
the global is reachable only by recomputing its name.

**Re-derived.**
- `Conversion/StaticData.cpp:179` `symbols.lookup(StaticNames::cell(con, 0))`
  and `include/idr/Conversion/StaticData.h:142` `symbols.lookup(name)`: "made
  already?" asked by digesting and looking the name up;
- `StaticData.cpp:238, 245`: in a run of N cells, two digests per cell, each
  of the whole `con`, which holds every cell: O(N²) per run;
- `StaticData.cpp:106, 125, 128` (`constantComponents`, run by
  `Cells.cpp:205`, `Lower/Values.cpp:62, 83`, `Lower/Repack.cpp:215`), and
  `StaticBytes.cpp:137` (`bigConstant`): a digest per reference in every
  function;
- `Conversion/Runtime.cpp:179-180`: two text digests per crash site;
  `Lower/Accounts.cpp:107`, `Lower/Lifetimes.cpp:107`, `StaticBytes.cpp:174`
  likewise.

**Carrier.** MLIR's global-and-reference model (as `memref.global` and
`memref.get_global` are): idr-lower-statics, which makes each global, rewrites
each use of a static datum into the op that names its global
(`llvm.mlir.addressof @g`), and a crash site's lowering reads the globals
statics made for it; inside the pass, the uniqued attribute is the datum's
in-process identity (one table by attribute, not a name lookup). The name is
computed once per new global.

**Deletes.** The `symbols.lookup(name)` existence tests, the digests per
reference and per cell, `StaticNames` calls outside the pass that makes the
globals.

**Owner.** L21 (`Conversion/StaticData.cpp`, `StaticNames.cpp`,
`StaticBytes.cpp`, `Runtime.cpp`, `Lower/*`, `include/idr/Conversion/*`).
`Conversion/Lower.cpp` modified (L21); the files named here are clean.
Ground: read (the O(N²) is read off the loop; its seconds are conjecture).

---

## 7. Escape hatches found by re-lexing the source and comparing spellings

**Fact.** That a user module refers to an escape hatch (`believe_me`,
`prim__believe_me`, `prim__crash`, `idris_crash`) or writes a hole, and where.

**First known.** The checker's elaborator, when it resolves the identifier to
a definition, before evaluation can reduce `prim__believe_me` applied to a
constructor away (`Registry/Recognized.idr:24-27`); an unsolved hole is a
`Hole` definition of the context.

**Dropped.** The TTC keeps no record of the resolved reference once it is
reduced ("the checked module keeps no trace of them",
`Frontend/Profile.idr:238-241`).

**Re-derived.** `Frontend/Profile.idr:231-280`: every user source re-read
(`readText`) and re-lexed with Idris's lexer; each identifier's text looked
up in `spellings : SortedMap String` (`Registry.idr:41-58`), keyed by the
unqualified spelling (`DotSepIdent _ n` drops the namespace). A user's own
definition spelled `believe_me` is refused though it is no escape hatch;
the reach check then matches by unqualified name too
(`Profile.idr:634`, `contains (m, dropNS full) st.spelled`). Per compile, one
extra read and lex of every user module.

**Carrier.** The checker records, in the module's TTC, each reference its
elaborator resolved (the resolved `Name` and its location) before
evaluation, or keeps the reference in the elaborated term; the frontend asks
the registry by the entry the name resolves to, as it does for every other
hook. Holes from the context's `Hole` definitions. (Which of the two the
checker takes is conjecture; that the checker can is not: it is ours.)

**Deletes.** `checkSpelled`, `readText` (Profile.idr:231-280); `spellings`
and `spellingHooks` (Registry.idr:41-58); the `Spelling` key and `Written`
expectation (`Registry/Entry.idr:62-78, 556, 604`); `spelling` and its four
entries (Recognized.idr:24-29, 289-292); `TS.spelled` and its unqualified
match (Profile.idr:634). About 80 lines.

**Owner.** L17 (checker), then L16. `Core/TTC.idr` modified (L17);
`Profile.idr` modified (L16). Ground: read (carrier conjecture).

---

## 8. The registry's `%foreign` entries: validated, thrown away, searched again by spec text

**Fact.** Which registry entry gives a `%foreign` definition its hooks.

**First known.** `Frontend/Resolve.idr:291-310` (`readRegistry`) resolves
every entry's site once, Foreign entries included (`Registry/Entry.idr:
602-603`, a Foreign entry names its declaring definition), and `validate`
(Resolve.idr:343-394) checks at 367 that the definition there declares the
entry's spec.

**Dropped.** `gathered` (Resolve.idr:305-308) indexes only `Def` entries in
`byEntry`; `validate` returns `Maybe Refusal`, the checked site discarded (a
validator).

**Re-derived.** `foreignHooksAt` (Resolve.idr:319-328), per `%foreign`
definition read (Boundary.idr:296-305): a linear `find` over every entry,
calling `declares` (`Registry.idr:62-63`) first, which re-parses all of the
definition's spec strings (`parseSpec`, Entry.idr) for every entry it
passes, then compares convention and function text; once more for
`DeclaredElsewhere`.

**Carrier.** `RegistryRead` holding the validated Foreign entries at their
resolved sites (as `byEntry` holds `Def` entries) and a table by `Spec` for
the "declared elsewhere" message, both built once where the registry is
read; `validate` returns the `RegistryRead` it checked.

**Deletes.** `foreignHooksAt`'s search and its per-entry spec parsing; the
second `declares` at Resolve.idr:367 folds into the build.

**Owner.** L16. `Resolve.idr`, `Registry.idr`, `Registry/Entry.idr` clean.
Ground: read.

---

## 9. A run's ending compared as printed text (harness)

**Fact.** How a compiled program's run ended (an exit code or a signal).

**First known.** The process status the runner gets (`boundedOn`'s result,
`raw status`) and the expected ending parsed into `Ending`
(`harness/Facts.idr:readEnding`).

**Dropped.** Both are printed: `statusWords status` (Serve) and
`statusLine expected` (`Facts.idr:103-106`); `harness/FuzzRun.idr:83` stores
the status in `Observed` as text.

**Re-derived.** `harness/Programs.idr:204-205` and `harness/Fuzz.idr:750,
757` compare the two printed strings.

**Carrier.** The typed status (`Code (Fin 256)` or `Raised Signal`, the
specification's `status e`) on both sides, compared by value; printed only in
the message.

**Deletes.** The text comparisons and `Observed.status : String`.

**Owner.** L19. Files clean. Ground: read.

---

## 10. Trust decided by a package's name text

**Fact.** Which library a module comes from (`Origin`), which decides trust
and admission.

**First known.** Where the build installs the prelude, base and our packages
under the compiler's own prefix (the driver's `--prefix`).

**Dropped.** `Frontend/Resolve.idr:75-78` keeps only the found package's name
text (`Installed p.name`).

**Re-derived.** `Registry/Libraries.idr:94-106` (`moduleOrigin`) matches
`Installed "prelude"`, `"base"`, `"mlir-linear"`, … by string, and the
namespace's first segment (`"Builtin"`, `"PrimIO"`) by text, once per module
(`Translate/Errors.idr:291-295`). The comment at Libraries.idr:29-30 says
"trust never follows from a name", but here it follows from the package's
name: a package named `base` on the package path is trusted. The working
tree is adding one more string arm (`"idris-mlir-spec"`, modified now).

**Carrier.** The package's identity as the build installed it, read once at
the boundary into a typed `Lib` (by the installed package's location under
the compiler's prefix, which the driver gives the frontend), so a new
shipped package is a case of a closed type, not a string.

**Deletes.** The string arms of `moduleOrigin`; `Home`'s `Installed String`.

**Owner.** L16. `Libraries.idr` modified (L16). Ground: read (carrier
conjecture; a design question for the coordinator).

---

## 11. Instance symbols: a collision guard over printed keys

**Fact.** That two function instances are one (their `Link`).

**First known.** `Translate/Keys.idr:1103-1152` (`instanceAt`): the link,
structural, keys the instance table (`named`).

**Dropped.** The symbol is the key printed (`keyText`), which is not
injective by construction.

**Re-derived.** `keyLinks : SortedMap InstanceKey (Link Form)`
(`State.idr:1926`, merged at 1967) and the internal error at
Keys.idr:1141-1151: every new instance's printed key looked up by its text
parts to catch two links that print alike.

**Carrier.** A symbol whose discriminator is a function of the link alone
(the link's text hash always carried, or a print proved injective), so no
collision is representable and the table goes.

**Deletes.** `keyLinks`, its merge and the guard. About 15 lines.

**Owner.** L16. `State.idr` modified (L16). Ground: read.

---

## 12. The driver's handoff check: an op's dialect by its namespace string

**Fact.** Which dialects the frontend writes (a static set, generated:
`include/idr/IR/Generated/WrittenDialects.txt`).

**Re-derived.** `foreign/idr/lib/Driver/Run.cpp:98-108, 284-286`: per
compile a `DialectRegistry` is built, then per op of the module
`getDialectAllocator(op->getName().getDialectNamespace())`, a string-keyed
map lookup.

**Carrier.** The generated list as C++ dialect classes, compared by the op's
`Dialect` type identity (or the module's dialect set checked once per
dialect, not per op).

**Owner.** L11 (`lib/Driver/`). Clean. Ground: read.

---

## 13. Runtime functions told from program functions by name after linking

**Fact.** Which functions of the linked module came from the runtime.

**First known.** Before linking: the program module is the program's
functions, every one under the program's prefix (`Conversion/Entry.cpp:
47-48`, `Mangle.cpp:41-43`).

**Re-derived.** `foreign/idr/lib/Driver/LinkRuntime.cpp:76-103`: a
`StringSet` of the runtime's function names built per compile, then every
program function and every call's callee looked up by name.

**Carrier.** The program's functions taken before the link (the list the
program module already is), so the loop walks those and asks of a callee
only whether it is one of them; no name set.

**Owner.** L11. Clean. Ground: read.

---

## 14. Dead: an unused name comparison and an unused generated op table

- `Frontend/Resolve.idr:51-52` `sameName`: no caller.
- `foreign/idr/include/idr/IR/Generated/OpIndex.h.inc`: "the key of every
  per-op table", included by nothing (only `generated.manifest` names it).
  Either the carrier of 3's op number and 5's op identity in digests, or
  deleted with its generator.

**Owner.** L16 (`sameName`); L03 (OpIndex's generator) and INT (the
generated file). Ground: read.

---

## 15. The vectorization schedule: a static library parsed from text per context

`foreign/idr/lib/Target/Schedules.cpp:88-113, 255-269`: the transform
library is assembled from string fragments and parsed with
`parseSourceString` once per context; the entry point is named by string
(`Transforms/Pipeline.cpp:36`) and `transform.structured.match
ops{["linalg.generic"]}` matches op names by string per op walked. The
interpreter, its named sequences and `structured.match` are upstream's
mechanism, so the names are upstream's to keep; what is ours is parsing a
library known when the compiler is built on every run. Building it with the
transform dialect's builders, or loading it once as bytecode, keeps the
upstream interpreter. Owner L21. Clean. Ground: read.

---

## Checked and kept: essential, or upstream's

- Function identity is MLIR's symbol: `ProgramGraph`'s one name table
  (`Analysis/Solver/ProgramGraph.cpp:73, 109-113`), `SymbolTable` callee
  lookups in passes (`Exclusive.cpp:185`, `InPlace/Writer.cpp:130`,
  `Tail/Frames.cpp:209, 219`, `Columns.cpp:82`), and self-call tests by
  `StringAttr` equality (`Tail/Context.cpp:171`, `Func/Fold.cpp:51`,
  `Optimize/Demand.cpp:131`, `Contify.cpp:245`, `Tail/TrmcRewrite.cpp:221`,
  `TailLoops.cpp:131`, `AccumulatorPlan.cpp:68`, `Accumulate.cpp:234`,
  `Specialize/Open.cpp:663, 682, 851`) are hash lookups or pointer compares
  on uniqued strings, which MLIR's referring by name forces. Two small
  leftovers: `Tail/Jumps.cpp:81` and `Defunctionalize/Forces.cpp:105` use
  `lookupSymbol` without a table (a linear scan of the program), each for
  calls the pass itself made or once per memo label.
- Runtime functions are a generated typed table (`idr::runtime::Function`,
  `Conversion/Runtime.cpp:113-170`); no runtime function is named by a
  literal.
- The registry's `Def` entries are resolved once to context entries
  (`Resolve.idr:291-313`) and read by entry; the frontend's `Shown` has no
  `Eq`; `IO` and `plus` are known by address (Boundary.idr:1150-1170).
- The test API names functions by what the test writer writes
  (`Transforms/Expect/Named.cpp:91-124`) and binders by a typed
  `BinderAttr` in their location (`Expect/Quantities.cpp`): text for a human
  at the test boundary.
- `idris-mlir-tblgen.cpp:992-1014` reads a parameter's kind from its C++
  spelling: upstream's `ArrayRefParameter` holds its element only as that
  text, and the backend runs only when the compiler is built (audit 14 T06).
- Text at real boundaries: CLI flags (`Frontend/Driver.idr:129-180`), asm
  parsers (`IR/Grades.cpp:44-77`), LLVM's printed IR read by
  `harness/RuntimeEffects.idr`, frame sizes from LLVM diagnostics by function
  name (`Driver/StackBound.cpp:57, 182, 234`), the prepared runtime's identity
  flags (`Driver/ReadRuntime.cpp:304-331`), MLIR resource names
  (`EffectTree.h.inc:327-336`), DLTI module attributes (`Target/Target.cpp:
  102-134`), the source text the profile lexes for pragmas the TTC keeps
  (`Profile.idr:checkModule`).

---

## Table

| # | Fact | Drop site | Re-derive sites | Carrier | Lines deleted | Owner | Waits on |
|---|------|-----------|-----------------|---------|---------------|-------|----------|
| 1 | Definitions a program uses, and each one's registry fate | Emit writes them only as symbols and NameLoc text (`Bytecode.idr:449-455`, `Term.idr:2065`) | `harness/Covers.idr:343-624` (print module, scan text, match by suffix), 681-735 (scan source), 743-760 (hand copies of the registry) | The frontend's typed `Read` table written once per compile, names by the checker's printer, fates from closed sets | ~365 | L19 | L16 |
| 2 | A `where` block's parent and ordinal | `Nested (outer, idx)`: context index lost by the TTC (`TTImp/Elab/Local.idr:89`, `Core/Name.idr:43`) | `Boundary.idr:503-654` whole-program walk, `State.idr:1198-1210, 1408-1413`, `TypeConstructors.idr:605-609`, `Keys.idr:89-96` | `Nested (parent : Name) (ordinal : Nat)`, as CaseBlock and WithBlock already are | ~180, and a walk per compile | L17, L16 | L17 (`TTC.idr`), L16 (`Boundary.idr`, `State.idr`, `TypeConstructors.idr`) |
| 3 | Which property of which op | Property names as strings in builders (`Generator/Idris.idr:167, 213`; `MLIR.idr:229, 287`), one dictionary (`Bytecode.idr:796-805`), empty properties section (993) | MLIR's dictionary sort, `setAttrs` string ladders per op per property (`Operation.cpp:301-318`, `OpDefinitionsGen.cpp:1498-1507`); Idris string tables per op (`Bytecode.idr:326, 345, 704-712`) | ODS native `writeProperties`/`readProperties`, `kHasProperties`, properties section; op number from the spec's op index | ~110 literals plus the property paths; per-op work on both sides | L03, L16 | L03 (`Spec/Pipeline`), L16 |
| 4 | A family group's entry | `typeIn` puts the whole group attribute in every type (`Emit/Index.idr:150-156`) | `Bytecode.idr:585, 697, 724` walk per type occurrence, bytes looked up (253-282) | `FamilyId`, numbered once by the writer in declaration order | few; per type occurrence O(reachable family tree) to O(1) | L16 | L16 (`Emit/*` modified) |
| 5 | Content digest of an attribute or type | `ContentNames.cpp:171-193` keeps nothing (comment at `Specialize.h:132-134` says it does) | `Deduplicate.cpp:188-228` via `Consumer.cpp:51-52` per request; `Specialize.h:135-136`; `Declare.cpp:69`; `StaticNames.cpp:57-72` | Merkle digest in our attributes' and types' storage; uniqued identity for in-process buckets | ~25 and per-call walks | L04 | L04 (`Families.h`), L18 (`Open.cpp`) |
| 6 | The global of a static datum | Pass boundary after `idr-lower-statics` (`Lower/Statics.cpp:84-120`) | `StaticData.cpp:106, 125, 128, 179, 238, 245`; `StaticData.h:142`; `StaticBytes.cpp:137, 174`; `Runtime.cpp:179-180`; `Accounts.cpp:107`; `Lifetimes.cpp:107` | `llvm.mlir.addressof @g` made by the pass that makes the global; uniqued attribute as identity inside it | ~20; O(N²) per run, a digest per reference | L21 | L21 (`Lower.cpp`) |
| 7 | An escape hatch referenced, a hole written | The TTC keeps no resolved reference (`Profile.idr:238-241`) | `Profile.idr:231-280` re-read and re-lex every source, `Registry.idr:41-58` spelling map, `Profile.idr:634` unqualified match | The checker's resolved references (Name, location) in the TTC; holes from `Hole` definitions | ~80; a lex per module per compile | L17, L16 | L17 (`TTC.idr`), L16 (`Profile.idr`) |
| 8 | The entry that hooks a `%foreign` definition | `gathered` skips Foreign entries; `validate` returns `Maybe Refusal` (`Resolve.idr:305-308, 343`) | `foreignHooksAt` (`Resolve.idr:319-328`) linear search, `declares` re-parses specs per entry (`Registry.idr:62-63`) | `RegistryRead` holding validated Foreign entries by site and by `Spec` | ~12 | L16 | none |
| 9 | How a run ended | `statusWords`, `statusLine` (`Facts.idr:103-106`), `FuzzRun.idr:83` | `Programs.idr:204-205`, `Fuzz.idr:750, 757` | Typed status compared by value | ~10 | L19 | none |
| 10 | A module's library (trust) | `Installed p.name` (`Resolve.idr:75-78`) | `Libraries.idr:94-106` string arms, once per module | Typed `Lib` from the installed package's place under the compiler's prefix | ~12 | L16 | L16 (`Libraries.idr`) |
| 11 | Two instances are one | Symbol is the printed key | `keyLinks` and its guard (`State.idr:1926, 1967`; `Keys.idr:1141-1151`) | Symbol discriminator a function of the link | ~15 | L16 | L16 (`State.idr`) |
| 12 | Dialects the frontend writes | Static list (`WrittenDialects.txt`) | `Run.cpp:98-108, 284-286`: per op a namespace string lookup | Generated dialect classes, compared by type identity | ~10 | L11 | none |
| 13 | Runtime vs program functions | Program functions known before the link | `LinkRuntime.cpp:76-103` StringSet, lookups by name | The pre-link program function list | ~8 | L11 | none |
| 14 | (dead) | — | `Resolve.idr:51-52` `sameName`; `OpIndex.h.inc` unused | delete, or use OpIndex as 3's and 5's op identity | ~870 generated, 2 | L16, L03, INT | none |
| 15 | The vectorization schedule library | A build-time constant held as text | `Schedules.cpp:255-269` parse per context | Built with the transform dialect's builders, or bytecode loaded once | ~30 | L21 | none |

## The three whose fix deletes the most

1. **Covers (1).** The frontend knows every definition it resolved, by entry
   and by registry fate, and writes none of it; the harness prints the whole
   module, scans it character by character, matches names by suffix, scans
   the sources for spellings and keeps two hand copies of the registry.
   About 365 lines, all of them rederivation.
2. **The nested-block walk (2).** The checker had the parent and loses it in
   the TTC as a context index; the frontend walks the whole program every
   compile to invent a parent and an ordinal, for every block though only
   nested ones need it, while case and with blocks already carry theirs.
   About 180 lines and a whole-program walk per compile, once `Nested`
   carries `(parent : Name) (ordinal : Nat)`.
3. **Properties by name (3).** Every generated builder knows each property
   statically, writes its name as a string, and MLIR string-compares it back
   into a property slot for every op of every compile, after sorting the
   op's dictionary; MLIR's native positional encoding, which ODS already
   generates for every op, carries it with no name.
