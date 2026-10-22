<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
# L03: the one source, the Idris specification and its generator

*Lane L03 of the P0 verification swarm. Rulings D7, D15, D16, D47, D49,
D50, D51, D52; coordinator decisions C6, C7. HEAD `e96bb991` at the start
(2026-10-21T21:30Z) and at the finish (recorded at the end). Nothing was
built, type-checked or run; every count names its command. Grounds:
*read* (path:line at HEAD), *measured* (command), *recalled*,
*conjecture*, *decision* (a D or C number). "14 T22" is lane 14's item,
"OS §6.1" is `design/one-source.md` §6.1, "CTC" is
`design/compile-time-cpp.md`, "EV" is `design/effect-vocabulary.md`.
Paths without a root are under `foreign/idr/include/idr/` for `.td`
files and `compiler/src/IdrisMLIR/` for `.idr` files.*

The concatenation every `.td` count below is taken over:
`find foreign/idr -name '*.td' -print0 | xargs -0 cat > /tmp/l03-all.td`
(21 files, 5,900 lines, *measured*), then `grep -c PATTERN`.

## 1. Verification

### 1.1 D16: our TableGen is 100% generated from the Idris specification

**Holds, with four corrections.**

- *Claim: "21 `.td` files, 5,862 lines" (OS §1 F1, §8.3).* **Corrected**
  (*measured*, `find foreign/idr -name '*.td' | xargs wc -l`): 21 files,
  **5,900** lines. 5,862 is the sum without `Target/ScheduleOps.td` (38
  lines), which OS §6.2 itself lists as an output. Structural
  incompleteness in a count only.
- *Claim: "every `.td` file under `foreign/idr` becomes its output" (D16)
  and the output table's first row, `IR/*.td` (OS §6.2).* **Corrected:**
  `IR/IdrRuntime.td` has no reader but `idris-mlir-tblgen`
  (`IR/CMakeLists.txt:18-20` feeds it to `-gen-runtime-abi-decls/defs`
  alone; `mlir_tablegen` never reads it, `:40-63`). By OS §6.1's own rule
  ("a fact only our C++ reads is printed straight into a header, never
  routed through `.td`"), its facts go to `idris_rt_ops.h` and the ABI
  header and **no `IdrRuntime.td` is printed**. The same rule strips every
  field only our generator reads from the printed `.td`: `Idr_Runtime`'s
  `symbol` (`IdrBase.td:272-275`), `Idr_Guarded`'s three fields
  (`:304-309`, a `GenInternalOpTrait` mlir-tblgen ignores),
  `Idr_AbiWord`/`Idr_AbiCount` (`:314-328`), `Idr_RuleCase`'s `category`
  (`:174-177`), `Idr_WordOp` (`IdrBigOps.td:21`), `bit idris`
  (`IdrAttrs.td:223`), `bit holdsBodies` (`:324`), the `bodyKinds` and
  `ctorRoles` fields of `Idr_DataType` (`IdrTypes.td:53-54`), and
  Passes.td's role and stage records (`Transforms/Passes.td:33-58`). The
  printed set is 20 files plus the admitted files of D51. Integration
  mismatch inside OS.
- *Claim: OS §8.2's table is "what today's `.td` holds that the spec must
  say first".* **Corrected, structural incompleteness:** the table misses
  constructs the code uses; the full inventory, each with its constructor
  or hand owner, is §2.4 below. Missing from OS §8.2 (*read*, *measured*):
  TableGen-language computation (`!listconcat` `IdrTypes.td:18`; `!foreach`
  and `SubstLeaves` `IdrBase.td:339-342`; `!if`, `!or`, `!ne`, `!eq` and
  `assert` `Passes.td:61-71`; `defvar` holding a C++ lambda
  `IdrClosureOps.td:15-16`); parameter classes with C++ parse and print
  bodies (`IdrAttrs.td:25-35, 150-160, 273-290`); an attribute constraint
  with storage conversions (`Idr_TagAttr`, `:18-22`); dense-array
  constraints (`IdrBase.td:351-357`); a bit enum with `separator` and
  `printBitEnumQuoted` (`IdrAttrs.td:200-209`); an enum
  `parameterPrinter` (`IdrBase.td:237`); properties
  (`DefaultValuedProp<NamedEnumProp<...>>`, `IR/IdrOps.td:162, 219`); the
  dialect's own settings and a data member in its
  `extraClassDeclaration` (`IdrBase.td:34-70`, `std::atomic<int64_t>
  foldLeak` at `:52`); interface `verify` with `verifyWithRegions`
  (`IdrFlow.td:49-52`) and `baseInterfaces` (`IdrInterfaces.td:204-205,
  233`); `oilist` (`IdrClosureOps.td:142`), `VariadicRegion`
  (`IdrMatchOps.td:33`), `DefaultValuedAttr` (`IdrOwnershipOps.td:259`),
  `TypeAttrOf` and `UnitAttr` (`IR/IdrOps.td:158-161`),
  `hasCanonicalizeMethod` (`:341`), `hasRegionVerifier` (7); an op of
  *another* dialect, a transform extension (`Target/ScheduleOps.td:17-34`:
  `Op<Transform_Dialect, ...>`, `TransformOpInterface`,
  `ReportTrackingListenerFailuresOpTrait`); the inner passes' `constructor`
  strings (`Transforms/InnerPasses.td:45, 58, 70`); 48 `Statistic`s, one
  `ListOption` (`Passes.td:910`), pass `dependentDialects`, a computed
  `baseClass` (`Passes.td:68-70`).
- *Claim: DRR is a construct to model (dispatch).* **Read:** today's `.td`
  has **no** DRR (`grep -c 'Pat<' /tmp/l03-all.td` = 0; no
  `-gen-rewriters` in any CMake file). The target uses it (§5.3
  "DRR where a pattern is local"; synthesis A §5.11: about 16 `Pat`s).
  So DRR is a constructor of cutover B, not A: the spec models what the
  dialect uses (OS §10), and DRR enters with the first pattern that uses
  it. Structural incompleteness of the plan's sequencing, not a defect.

What the claim rests on and holds (*read*): mlir-tblgen interprets ODS
and is kept (OS §6.3); every `mlir_tablegen` line reads a `.td` the spec
prints (`IR/CMakeLists.txt:40-63`, `Target/CMakeLists.txt:7-8`,
`Transforms/CMakeLists.txt:7, 11`); upstream's `.td` stay upstream's.

**A finding for cutover A's gate** (OS §8.1: "mlir-tblgen's outputs are
byte-identical to today's"), unverified behaviour made exact by reading
upstream at the pin:
- mlir-tblgen emits op classes in **def-name order**
  (`OpGenHelpers.cpp:55` iterates `records.getDefs()`, a
  `std::map<std::string, ...>`, `llvm/include/llvm/TableGen/Record.h:2012`),
  but type, attribute and interface definitions in **definition order**
  (sorted by record ID, `AttrOrTypeDefGen.cpp:845`,
  `OpInterfacesGen.cpp:680`). So the spec must keep today's def names for
  ops and today's relative order for types, attributes and interfaces, or
  gate A fails on order alone.
- Summaries are copied into the generated headers as doc comments (`///
  a closed program: ...` in `IdrOps.h.inc:893` of the typecheck build,
  *read*), so `Doc` must carry today's text exactly.
- Three enums have values that are not their positions: `Quantity` is 1
  and 2 (`IdrBase.td:83-84`), `Rule` skips 3, 12, 24, 27 (`:187-234`),
  `CheckKind` skips 3 (`:250-256`). OS §4.3's "an enum's position is its
  number" cannot hold at gate A; the spec carries these values until B
  renumbers (bytecode writes enum values, `IdrBytecode.td:22-26`).
- The gate as written omits `idris-mlir-tblgen`'s own outputs
  (`IdrRuntimeAbi.inc`, `idris_rt_ops.h`, `IdrGuards.inc`,
  `IdrBigToWord.inc`, `IdrRuleCategories.inc`, the three `.txt`): specgen
  prints their successors, so they belong in the byte identity, or a
  regression in A is not provably a printer bug.

### 1.2 D15: any higher-level specification of ours is Idris

**Holds, with one correction to the argument that the build always
starts.**
- *Read:* no Python, YAML or DSL source of the `idr` dialect exists;
  `tools/check-units.py` is a syntax checker, not a generator
  (`tools/check-units.py:4-8`). The one non-Idris generator left is
  D51's C++ backend, by ruling.
- *Claim: "bootstrap unchanged; chez needs the host's C compiler only,
  idris needs chez: neither needs LLVM" (OS §7.1, citing
  `tools/bootstrap.sh:1424-1459`).* **Refuted for the recipe as
  written** (*read*): `make bootstrap` runs `all`, which orders `stage2 gmp
  chez idris` (`tools/bootstrap.sh:232`); GMP is built by the pinned clang
  (`:1403`); Idris's build passes `CPPFLAGS=-I$sysroot/usr/include`
  (`:1490-1496`), because upstream's `support` target builds
  `support/refc` (`third_party/Idris2/support/Makefile:5, 10-11`), whose
  headers include `gmp.h`. Chez alone needs only the host's C compiler
  (`:1426-1440`). `make typecheck` builds `chez idris` without stage 2
  (`Makefile:350`). So the spec's generator *can* be built with no LLVM in
  principle, and D49's committed outputs are what actually keep the C++
  build from waiting on Idris. Unverified behaviour in OS, harmless to the
  ruling.

### 1.3 D7 (this lane's part): every static fact is a compile-time constant generated from the one source

**Holds in substance, with three corrections.**
- *"generated from the one source ... through the TableGen it
  generates".* **Corrected:** a fact only our C++ reads reaches C++ as a
  specgen-printed header, never through `.td` (OS §6.1; e.g. the ABI
  table, the guards, `OpIndex`, the effect tables). The `.td` route is
  only for what mlir-tblgen reads.
- *"checked by `static_assert`/`consteval`".* **Corrected:** a fact the
  spec proves is not checked again in C++ (OS §4.3, CTC R4). What stays
  `static_assert`ed is agreement between a hand C++ definition and a
  printed table, never a law the spec already proved (§4 I-9).
- *"Pending: the owner's approval of the skill's new wording" (proposal
  D7, lines 186-188).* **Stale:** D47 approved it.
- **Integration mismatch:** CTC still describes T0 as TableGen and
  `idris-mlir-tblgen` "rebuilt as a typed model" that generates the Idris
  mirror, every cross-record table, the runtime ABI, the pipeline and the
  tests' tables (CTC §1.1 row T0, §2.1, §2.2, and §2.3's TableGen
  sketches); `grep -n 'D16\|specgen' design/compile-time-cpp.md` finds
  nothing (*measured*). Proposal §5.6's bullet "the generator reading the
  records once through the `mlir::tblgen` wrappers" (line 1231) and
  synthesis D §2.6's first bullet say the same. All three contradict D51.
  OS §11.2 lists the changes; none was made.

### 1.4 D47: shared shape over ops is an interface, never a ladder, never a concept that lists ops

**Holds** (*read*: `.claude/skills/representation-first/SKILL.md:102-105`;
`AGENTS.md:405-407`). This lane's part: specgen prints C++, so the ban
must hold for generated code too. Today's generator prints specializations
(`Guarded<Op>`, `BigToWord<Op>`, `Abi<Op>`), never a concept body over op
classes (*read*, `idris-mlir-tblgen.cpp:3002-3106`). OS does not say what
stops specgen from printing a `TypeSwitch` or a concept enumerating ops;
§4 I-6 makes it unprintable.

### 1.5 D49: the generated files are committed, stamped, regenerated by `make check`

**Holds, with three corrections.**
- *"Each is stamped with the fingerprint of the specification and of its
  own text".* **Defect in the mechanism, confirmed in the code's shape.**
  A spec-wide fingerprint written into every output changes every output
  on every spec edit. The `.td` outputs are harmless (mlir-tblgen ignores
  comments and writes `.inc` only when changed). The specgen-printed C++
  headers are not: `IdrGuards.inc`'s successor is included by
  `IR/IdrDialect.h:253`, which **260** files include directly, and
  `idris_rt_ops.h` by `runtime/idris_rt.h:253`, which **56** runtime files
  include (*measured*: `grep -rl '#include "idr/IR/IdrDialect.h"'
  foreign/idr runtime | wc -l`; `grep -rl idris_rt.h runtime | wc -l`).
  A doc edit would recompile all of them, against OS §6.4 ("ninja rebuilds
  only what a change reaches") and §7.4. Today's churn is the evidence:
  lane 14 measured 16 of 29 commits to `Syntax/Idr.idr` changing only the
  stamp (14 T50); origin/main's 101edbc5 adds one C++-only trait and its
  whole diff to both idr modules is the stamp line (*measured*: `git diff
  e96bb991 origin/main -- compiler/src/IdrisMLIR/{Dialect,Syntax}/Idr.idr`).
  A fingerprint of the spec's *source* needs a path read, which D52 forbids
  specgen; a fingerprint of the spec's *values* is a function of the
  outputs and adds nothing. Correction: §4 I-1 (owner question Q2).
- *"`make check` regenerates into a temporary tree and fails on any
  difference".* **Holds, with a cost unmeasured:** it compiles the spec and
  specgen under the pinned Idris inside a test whose commands time out at
  60 s unless the run script sets more (`Makefile:48-50`). Measurement to
  take: cold compile time of the spec and specgen under the pinned Idris on
  each of the four targets; the test's bound is set from it.
- **Structural incompleteness:** the D51 backend's outputs (the upstream
  dialects' Idris modules) are committed too and need a staleness check.
  `make check` cannot run that backend without the C++ build, so it keeps
  today's mechanism for them (records and generator source fingerprinted,
  `tools/dialects.sh:98-108`), which OS does not say.

### 1.6 D50: the frontend imports the specification's closed sets; the three `.txt` files go; builders stay printed

**Holds, with four corrections.**
- *"`IdrRules.txt`, `IdrPassRoles.txt`, `IdrPassStages.txt` go".*
  **Corrected, integration mismatch:** their readers are shell, which
  cannot import an Idris module: `harness/lib/rules.sh:17-18`,
  `harness/lib/profile.sh:56`, `harness/lib/differential.sh:16`,
  `tests/rules-covered/run:23` (*read*; `Driver/Outcome.cpp:67` names the
  file in a comment). Deleting the files needs those checks moved into the
  harness, which is Idris and imports `Spec.Rules` and `Spec.Pipeline`.
  The harness builds on the pinned prefix with `depends = contrib, test`
  (`harness/harness.ipkg:7`; `Makefile:279-287` sets
  `IDRIS2_PREFIX='$(IDRIS_PREFIX)'` only), so `runner` needs the spec
  package on its package path (`HOST_PREFIX`, as `frontend` has,
  `Makefile:204-207`). Seam with L19.
- *"the refusal categories, the ending table, the clock kinds, the grade's
  parts and the pipeline's stages".* **Incomplete list:** today's
  generated copies are nine namespaces of `Syntax/Idr.idr` (*read*,
  `:18-419`, with `ruleCategory`): `CmpPredicate`, `CtorRole`, `Lifetime`, `Permission`,
  `Quantity`, `Rule`, `RuleCategory`, `Stage`, `SumKind`. By D50's
  principle every one is imported; `CtorRole` and `SumKind` go with D48's
  families instead. 22 modules import `IdrisMLIR.Syntax.Idr` today
  (*measured*, `grep -rln 'import IdrisMLIR.Syntax.Idr' compiler/src
  harness | wc -l`). The spec keeps each set in a namespace of its name
  (`Rule.Match`), so the consumers change imports, not names.
- *"each a plain function typed by its op's operand count (`Vect n
  Value`)".* **Corrected:** ops have operand *groups*; 32 are `Variadic`
  (*measured*, `grep -c 'Variadic<' /tmp/l03-all.td`). A builder takes one
  argument per group: a `Value`, a `List Value` or a `Maybe Value`, as
  today's do (`Dialect/Idr.idr:65-66`, `applyOp`). `Vect n` indexes the
  groups and, with TD3, the results (`Op k`).
- *"a generic builder's type would depend on a run-time value of varying
  representation".* **Holds for ops with attributes; refuted for
  primitives.** A primitive has no inherent attribute by construction
  (14 T28, `idris-mlir-tblgen.cpp:1393-1400`), all its operands are
  `Value`, and a generic builder over it already compiles under both hosts:
  `pureOp : (p : PurePrim) -> Vect (primArity p) Value -> List MlirType ->
  Guarded` (`Dialect/Idr.idr:1355`), compiled by `make self` (stage 2
  equals stage 3). So D50's own reason does not require printing primitive
  builders. Owner question Q1.

### 1.7 D51: upstream's records are read by one slim C++ backend

**Holds, with three corrections.**
- *Reads (shape):* today's tool is already a set of `GenRegistration`s on
  `MlirTblgenMain` (`idris-mlir-tblgen.cpp:3221-3255`, 11 registrations).
  D51's backend is a cut: keep the upstream halves of `-gen-idris-syntax`,
  `-gen-idris-dialect`, `-gen-idris-bytecode`; delete the eight
  registrations that read our records (`-gen-runtime-abi-decls`, `-defs`,
  `-gen-guards`, `-gen-big-to-word`, `-gen-rule-list`,
  `-gen-rule-categories`, `-gen-pass-roles`, `-gen-pass-stages`) and the
  idr-only regions (`:984-1189` guards, `:1393-1678` primitives,
  `:2099-2200` identified types and the table, `:2749-3219` ABI, guards,
  word ops, rules, passes: about 1,060 of 3,255 lines by derivation from those
  ranges, about a third, not OS §6.5's "about half"). The format parser
  (`:1822-2002`) stays: arith's and ub's attributes are still printed as
  text (14 TD2). The wrapper bypasses on the upstream half stay to fix in
  the cut (14 T05, T32, T33, T41, T43).
- *"a generated `IdrAdmitted.td`, one record per op naming upstream's
  def".* **Corrected, structural incompleteness:** the backend also
  prints upstream *enums and attributes* the admitted ops take
  (`Syntax/Arith.idr`, 275 lines, *measured* by lane 14) and builtin's
  *bytecode encoders* the writer uses (12 of 51 used, 14 G01). Admitted
  types, attributes and bytecode records need records too, or the backend
  derives the closure itself from the admitted ops (it can for enums an
  op's attribute names, through `Operator`; it cannot for the writer's
  choice of builtin records). One admitted file per upstream dialect keeps
  each module's fingerprint local, as today (`tools/dialects.sh:83-93`).
- **Gap: the C++ side of the admitted set has no generator.** Stage
  legality and `OpIndex` external models need upstream ops by C++ class
  (F19; CTC §2.3(a): "the generator gets the C++ class from the record, so
  that list contains no strings"), and `BigToWord` names upstream classes
  as strings today (`IdrBigOps.td:21, 67, 140, 156, 191, 246`). Under D51's
  letter either the spec restates `::mlir::arith::AddIOp` beside
  `Arith_AddIOp` (two compiler-checked spellings that can name different
  valid ops) or the backend emits one C++ table. Owner question Q3.

### 1.8 D52: under idris-mlir the generator reproduces the committed files byte for byte

**Holds.** Every source of nondeterminism in today's generators, read:
- `idris-mlir-tblgen` iterates only name-ordered `std::map`s for output
  (`:319` enums by name; `:2064`, `:2317`, `:3026`, `:3090` by name or
  class); its pointer-keyed maps are lookups, never iterated for output
  (`:330` `EnumsOfCases`, `:998` `byKind`, `:2302` `guards`). No
  `DenseMap`, hash, time or environment read (*measured*: `grep -n
  'DenseMap\|StringMap\|unordered_\|getenv\|time(\|random'` finds none).
- mlir-tblgen: name order for ops, record-ID order for types, attributes
  and interfaces (§1.1); header banners name the input file without a
  path.
- `tools/dialects.sh`: the fingerprint is POSIX `cksum` of mlir-tblgen's
  record dump and the generator's source (`:100-108`), the same on all
  four targets and in the typecheck build (`tests/dialects-current/run`
  relies on it).

So today nothing nondeterministic reaches an output; D52's risk is new,
from specgen running on two hosts. Its sources and the representation that
removes each are §2.7. **One correction:** "no time, environment or path
read" conflicts with writing only changed files (OS §6.4); specgen writes a
fresh tree and the wrapper compares and moves, as `tools/dialects.sh:137-148`
already does with `cmp -s`, so specgen reads no file at all.

### 1.9 C6: an op's specification names the base primitive it implements; the registry's rows are generated

**Holds in part; three corrections and one challenge.**
- *"the mapping is held once".* **True, and already true today:** every
  category-1 row names its op by a printed constructor (`cCall spec space
  name shape p = cPrimitive ... (IOCall p [])`,
  `Registry/Primitives.idr:160-161`). What C6 actually adds is that
  "is a primitive" and "has a row" become one fact: today the `Primitive`
  trait marks 114 ops (14 §2.6), 9 of whose constructors no Idris code
  names (14 §2.6), and the C++ trait has no C++ reader
  (`IR/Traits.h:72-79`; *measured*: no use outside the generator).
- **Many-to-one with literals:** one op may implement several base
  primitives, and a row may add literal operands (`IOCall ArrayNew [LInt
  UInt8 0]`, `Registry/Primitives.idr:446`; `IOCall : IOPrim -> List Lit
  -> Hook`, `Registry/Entry.idr:232`). The op's field is a list of
  bindings, each a key, a qualified name, a shape and literals.
- **Not every row is an op:** type rows (`WordType`), constant handles
  (`Handle (LInt UInt64 0)`, four rows), the entry (`programRoot`) and
  category 2 stay hand rows (*read*, `Registry/Primitives.idr:64-65,
  232-234, 346, 365-366, 372`).
- **Cost under C7:** the spec depends on base alone, so the registry's
  vocabulary (`Key`, `PrimTy`, `IntTy`, `Multiplicity`, `Shape`, `Lit`,
  `QName`) must move into the spec (`Registry/Entry.idr:8-11` imports
  `Dialect.Idr`, `Syntax.Idr`, `Types`), and the rule that the compiler
  names Idris definitions only in its registry (`tests/registry-only/run:3-11`,
  which does not scan `compiler/spec/`) needs a second home or silently
  stops covering the new names.
- **Challenge:** C6's reason, "both are Idris now, so the old objection no
  longer holds", misreads 14 TD10's objection (coupling the dialect's
  source to base's spelling), which is about coupling, not language. If
  primitives are built by one generic builder over the spec's op value
  (§1.6), the spec need not say which ops Idris names at all, and the
  registry's rows can name the spec op they mean. Owner question Q1.

### 1.10 C7: `compiler/spec/`, package `idris-mlir-spec`, modules `IdrisMLIR.Spec.*`, base alone; generator in `compiler/specgen/`

**Holds, with build-graph corrections.**
- The fork never imports `IdrisMLIR.*` and only `IdrisMLIR.Frontend.*`
  imports the fork (`AGENTS.md`, "The Idris side"): the spec touches
  neither. Everything the sketches use is in base (`Data.Vect`,
  `Data.Fin`, `Data.So`, `Data.List.Elem`, `Data.List1`,
  `Decidable.Equality`); none needs contrib.
- **Unstated consumers and prefixes** (*read*, `Makefile`): the spec is
  built by the pinned Idris into `HOST_PREFIX` (for `frontend`, `runner`,
  `specgen`, `syntax-samples`; the pattern of `fork`, `Makefile:192-197`), and by
  the frontend into `CHECKOUT_PREFIX` (for `make self`, the D52 check, as
  `self-fork` does, `:254-261`). The harness and `syntax-samples.ipkg`
  gain `depends = idris-mlir-spec`.
- **Module layout:** OS §4.1's list misses `Format` (the assembly-format
  AST), `Admitted` (D51's set and the contract's dialect list), `Families`
  (D48's types the frontend builds), `Bytecode` (layouts), `Constraints`,
  `Interfaces`, `Traits`, and the transform extension op. The full layout
  and its import DAG are §2.2.

### 1.11 What the six rulings leave unsaid, and the two-host subset

- *OS §4.4: "every form in §4.2 is of that kind (conjecture until gate
  A)".* **Unverified behaviour with one concrete risk.** The frontend
  refuses a field whose type mentions another field "outside indices"
  (`Frontend/Translate/Types.idr:1060-1061`, `outsideIndices`
  `:604-610`): an earlier field's value inside a type constructor's
  *parameter* is refused, inside an *index* is allowed. EV §6's
  `data Effects : List Group -> Type` keeps `gs` the same variable in every
  constructor's result, which makes it a parameter candidate; a record
  field `effects : Effects (groupsOf ins outs)` could then be `unsupported
  (dependent field)` under idris-mlir while stock Idris accepts it.
  Measurement to take: a fixture beside `tests/dependent-field-type-field`
  with exactly that shape, compiled by idris-mlir.
- **Auto search differs between the hosts.** D45 makes the fork refuse
  `%auto_implicit_depth` and end search by a size rule; stock Idris keeps
  depth 50 (proposal D45). An `auto` proof deeper than 50 (an `Elem` down a
  long list, an `LT` between ranks built as a chain) type-checks under one
  host only. OS's encoding rule leans on `auto` (`Names`, `RuleGroups`,
  `GuardOperands`, `Parent`'s `LT`). §4 I-2 removes the search.
- **A family function discharges its members' proofs where the constants
  are variables.** In OS's `division part sign`, a proof elaborated inside
  the body is stuck if a referenced name is computed by matching on `part`
  or `sign`. The rule the spec needs: a family takes its members' proofs as
  `auto` parameters discharged at each member, or references operands by
  position (§4 I-2), never by a name computed by a case.

## 2. Boundaries

### 2.1 The end state, in one paragraph

One Idris package, `idris-mlir-spec`, holds every static fact of the `idr`
dialect as data whose types make the bad states unwritable. One Idris
program, `specgen`, prints from it a fixed list of files: the `.td`
mlir-tblgen reads, C++ headers only our C++ reads, the runtime's
declarations, the printed Idris builders, value sums and encoders, and the
admitted upstream records. Everything else the Idris side and the harness
need of the spec they import. One C++ backend reads upstream's records for
the ops, attributes and bytecode records the spec admits. A manifest holds
the fingerprints (§4 I-1). Stock Idris builds and runs specgen in every
build and every `make check`; idris-mlir reproduces the same bytes in
`make self`. No output depends on the host, the target, a path or a time.

### 2.2 The specification: modules and their imports

Every module `%default total`, in the subset both hosts compile, base
alone. `A <- B` means B imports A. Names in this table are proposals.

| module | holds | imports |
| --- | --- | --- |
| `Spec.Core` | `Ident` (an ASCII identifier, §2.7), `CppName`, `Doc` (summary, description, exact text), `Dialect` (`Idr \| Builtin \| Arith \| Math \| MemRef \| Tensor \| UB \| Transform`), the closed vocabulary of upstream ODS names (traits, interfaces, builtin types) | base |
| `Spec.Hooks` | every hand C++ hook the spec names: `Pred`, `Directive` (13 cases), `VerifyHook`, `FoldHook`, `CanonHook`, `Member`, `Storage`, `ParamCodec`; each a C++ signature and name, no body | Core |
| `Spec.Format` | the assembly-format AST over positions (§4 I-2) | Core, Hooks |
| `Spec.Constraints` | type and attribute constraints as data, a `Pred` hook where data cannot say it | Core, Hooks |
| `Spec.Enums` | the dialect's enums with their facts (spelling, value until B) | Core |
| `Spec.Rules` | `Rule`, `RuleCategory`, `scope`, `phrase`; namespaced as today | Core |
| `Spec.Endings`, `Spec.Clocks` | D37's ending sum and statuses; clock kinds | Core |
| `Spec.Grades` | `Quantity` (`One \| Many`, no zero), `Permission`, the lifetime constants; the algebra and its proofs | Core |
| `Spec.Effects` | L01/L02's content (resources, kinds, atoms, declarations, laws) | Core |
| `Spec.Interfaces`, `Spec.Traits` | op, type and attribute interfaces (C++ signatures, default bodies as hooks); our native traits; predicate traits | Core, Hooks |
| `Spec.Types` | `TypeDef`, `AttrDef`, parameters, facts per type (§3), storage | Core, Hooks, Constraints, Interfaces, Grades |
| `Spec.Families` | D48's index terms (`Fin s`), constructors, fields with quantity: the types the frontend builds families with | Core, Grades |
| `Spec.Bytecode` | layouts, derived from parameters (§4 I-3) | Types |
| `Spec.Runtime` | `AbiKind`, `CType`, the runtime's helper functions, symbols | Core |
| `Spec.Admitted` | the upstream defs admitted per dialect and stage | Core |
| `Spec.Ops.<Family>` | family functions and their member lists | all above but Pipeline |
| `Spec.Dialect` | the dialect's settings, `allOps`, the global decisions, the output list | Ops.* |
| `Spec.Pipeline` | `Stage`, `Anchor`, `Role`, `PassKind`, `Pass`, the indexed `Pipeline`, inner passes, statistics, check options | Core, Enums |
| `Spec.Expect` | idr-expect's properties | Core |

The frontend imports `Rules`, `Endings`, `Clocks`, `Grades`, `Families`,
`Pipeline` (for `Stage`), `Core` (for `Dialect`), and never `Ops.*` or
`Dialect`, so an op edit rebuilds the frontend only through the printed
modules it already imports (*conjecture* on Idris's rebuild granularity,
as OS §7.4). The harness imports `Rules`, `Endings`, `Pipeline`.

### 2.3 What specgen writes, and who reads it

specgen's `Main` takes one argument, the root of a fresh output tree, and
writes the files `Spec.Dialect.outputs` lists, in that order. Printers are
pure modules with no `System` import; only `Main` does IO.

| output (committed) | read by | replaces |
| --- | --- | --- |
| `foreign/idr/include/idr/IR/{IdrBase,IdrTypes,IdrAttrs,IdrInterfaces,IdrFlow,IdrOps,IdrBytecode,Idr*Ops}.td` (20 with the two below) | mlir-tblgen, CMake lines unchanged (`IR/CMakeLists.txt:40-63`) | the hand files |
| `Target/ScheduleOps.td`, `Transforms/{Passes,InnerPasses}.td` | mlir-tblgen | the hand files |
| `IR/IdrAdmitted{Builtin,Arith,Math,MemRef,Tensor,UB}.td` | the D51 backend | `tools/dialects.sh:83-93`'s hand list |
| `IR/Generated/{OpIndex,Families,EffectTree,EffectFacts,RuntimeAbi,Guards,BigToWord,Endings,Clocks,StageFacts,RuleCategories,ExpectProperties,Hooks,Pipeline}.h.inc` | our C++ | `IdrRuntimeAbi.inc`, `IdrGuards.inc`, `IdrBigToWord.inc`, `IdrRuleCategories.inc`; `Pipeline.cpp:61-197`'s statements; `Expect.h:146-230` |
| `runtime/Generated/{idris_rt_ops.h,Instances.cpp}` | the runtime (`runtime/idris_rt.h:253`) | `-gen-runtime-abi-decls`; `IdrRuntime.td` |
| `compiler/src/IdrisMLIR/Dialect/Idr.idr` | Emit | `-gen-idris-dialect` for idr |
| `compiler/src/IdrisMLIR/Encoding/Idr.idr` | `MLIR/Bytecode.idr` | `-gen-idris-bytecode` for idr; the idr value sums of `Syntax/Idr.idr` |
| nothing: closed sets | imported | `Syntax/Idr.idr`'s nine enum namespaces; the three `.txt` |

`Syntax/Idr.idr` disappears: its enums are imported (D50), its text
printers go with 14 TD2, its value sums move beside their encoders. During
cutover A only, specgen also prints the three `.txt` files and
`Syntax/Idr.idr` byte-identically, deleted in the D50 unit (§5 U2).
Generated `.h` and `.cpp` files fall under `tests/file-size` (`.cpp`/`.h`
scanned, `tests/file-size/run:31`), `tests/zones` and
`tests/registry-only`: their rules name the generated directories.

### 2.4 Every construct of today's `.td`, and what generates it

Counts are `grep -c` over `/tmp/l03-all.td` (*measured*). "Hook" means
essential hand C++ the spec names (OS §9): its declaration is printed into
`Hooks.h.inc`, its definition is hand C++, a missing one is a link error.
"Goes in B" names the ruling or lane that deletes the construct; until
then cutover A must print it.

| construct (count; example) | spec constructor | hand C++ | goes in B |
| --- | --- | --- | --- |
| dialect def (1; `IdrBase.td:28-71`): name, namespace, summary, `useDefaultTypePrinterParser = 0`, `useDefaultAttributePrinterParser`, `hasConstantMaterializer`, `hasCanonicalizer`, `hasOperationAttrVerify`, `hasRegionArgAttrVerify`, `dependentDialects`, `discardableAttrs` | `Spec.Dialect.idr : DialectDef`, one field per setting; `dependentDialects : List Dialect` | the type parser and printer, the materializer, the dialect's canonicalization patterns, the two attribute verifiers (essential: passes can add attributes, the op set is open) | `discardableAttrs` with 14 T38 (the report becomes inherent); the `foldLeak` member (`:48-52`) is state, a `Member` hook until its owner moves it |
| enums: 10 `I32EnumAttr`, 1 `I64EnumAttr`, 1 `I32BitEnumAttr` (`IdrBase.td:83-259`, `IdrAttrs.td:177-209`, `IR/IdrOps.td:52`, `Iteration`) | `data` per enum in `Spec.Enums`/`Rules`/`Grades`/`Pipeline`; `spelling`, `value` total functions; `BitEnum` for a set with `separator`, `quoted` fields | none | `CtorRole`, `SumKind` with D48; `Effect`'s three bits with D29's eleven atoms |
| enum options: `genSpecializedAttr = 0` (10), `parameterPrinter` (`IdrBase.td:237`), `EnumAttr` wrapper (`IdrAttrs.td:366`) | fields of the enum record; `EnumAttr` an `AttrDef` kind | `parameterPrinter`'s expression is upstream's API: printed text, no hook | — |
| types (12 `TypeDef`s via `Idr_Type`, `IdrTypes.td:16-20`; `Token`, `Cell` in `IdrOwnershipOps.td:33, 158`) | `TypeDef` with `params : Vect p Param`, `format`, `traits`, `interfaces`, `facts`, `builders`, `verify`, `storage`, `bytecode`, `doc` | as below | `Box` and the mutable `Data` with D48; `World` with D20 |
| mutable type with hand storage (`Idr_DataType`: `MutableType`, `storageClass`, `genStorageClass = 0`, `skipDefaultBuilders`, `IdrTypes.td:48-57`) | `storage = HandStorage hook`, `mutable` (cutover A only) | the storage class, `seal`, `solveHeld`, `verifyBody` (`:136-151`) | all of it with D48 (a family is an immutable attribute) |
| type and attribute parameters: `EnumParameter` (4), `StringRefParameter`, `ArrayRefParameter`, `DefaultValuedParameter`, `APIntParameter`, C++-typed (`"::idr::DataType"`) | `Param` sum: `EnumP`, `StringP`, `ArrayP`, `DefaultP`, `TypeP CppName`, `AttrP CppName`, `CodecP hook` | none for the generated kinds | — |
| parameters with hand parse/print bodies (3: `Idr_TagParameter` `IdrAttrs.td:25-35`, `Idr_IntegerParameter` `:150-160`, `Idr_SquareListParameter` `:273-290`) | `CodecP (ParamCodec parser printer)` | the three parse/print bodies | `SquareListParameter` with 0003 B7's typed instance identity |
| a parameter default (`Idr_LifetimeParam`, `IdrTypes.td:278-281`) | `DefaultP value`, also printed to the Idris encoder (deletes 14 B06) | none | D40 changes the lifetime parameter |
| attributes (11 `AttrDef`s + 1 `EnumAttr`; `IdrAttrs.td:44-378`, `IdrArrayOps.td:236`) | `AttrDef` as `TypeDef` | `ConAttr`'s builder and checked get (`:91-130`), the table's (`:325-357`) | the table with D48; `WorldSpace` with D20; the keys stay passes-only (no builder printed) |
| attribute constraint with storage conversion (`Idr_TagAttr`, `IdrAttrs.td:18-22`: `convertFromStorage`, `constBuilderCall`) | `AttrC.Typed cppType convert build`: two expressions of upstream's API, printed text | none (upstream's substitution language) | — |
| `ConfinedAttr` with dense-array constraints (2, `IdrBase.td:351-357`) | `AttrC.Confined base [UpConstraint]` from the upstream vocabulary | none | — |
| type constraints: `AnyTypeOf` (12), builtin `I1..I64`, `F64`, `Index`, memref/tensor (12) | `TypeC` data over `Spec.Core`'s upstream vocabulary | none | — |
| type constraints with C++ predicates: 36 `CPred` (`IdrTypes.td:308-309, 323-324`, `IR/IdrOps.td:23-26`, `IdrBase.td:339-348`) | `TypeC.Graded q p carrier` for the grade predicates (`quantityOf`, `isOwned`, `unrestricted`: data, §3); `TypeC.Pred hook` for the rest | the predicates data cannot say (`isFieldType`, `dataTypeOf(...).getKind()`) | — |
| TableGen computation (`!listconcat`, `!foreach`, `SubstLeaves`, `!interleave`, `!if`, `!or`, `!ne`, `!eq`, `#`, `assert`, `defvar`) | none: Idris functions compute; specgen prints the result | none | — (gone at A) |
| interfaces: 10 op (`IdrInterfaces.td:105-274`, `IdrFlow.td:15`), 2 type (`:24, 74`), 40 `InterfaceMethod`s, 2 `baseInterfaces`, 1 `verify` + `verifyWithRegions` | `Interface` record: kind, methods (C++ signature, doc, `body : NoBody \| Default hook`), bases, `verify : Maybe (hook, WithRegions)` | method signatures (the one untyped island, OS §8.2), default bodies, `verifyFlowEdges` | `MayCrash`, `RunsLabels`'s classifier role, `Generating` with D43, per L01/L13 |
| upstream interfaces declared on ops: 114 `DeclareOpInterfaceMethods`, 12 `DeclareTypeInterfaceMethods` | `IfaceUse.Declare iface [method]` | each declared method's body | per L13 |
| native op traits (12 `NativeOpTrait`, `IdrBase.td:272-293`, `IdrInterfaces.td:141, 295-330`) | `OurTrait` closed enum, each with `verifyTrait : Maybe hook` | the traits' C++ classes | `CallsRuntime`, `PerformsIO`, `ObservableIO`, `TakesReference`, `BuildsValue`, `Primitive`, `NoRuntimeForm`, `SameValue`, `ResultCarriesOperand` with D9/D28 (02 T6, T7) and Q1 |
| `PredOpTrait` (9, e.g. `IdrClosureOps.td:22-26`) | `PredTrait doc rule`: a typed rule where data says it (the closure's quantity, §3), else `PredTrait doc hook` | the remaining predicates, templated over the op class (D7) | — |
| `TraitList` (3, `IdrInterfaces.td:116, 315, 337`) | an Idris list-valued function; printed flattened | none | with 02 |
| `GenInternalOpTrait<"Guarded">` marks (12, `IdrBase.td:304-309`) | `Op.guards : List (Guard i)` (§4 I-2) | none | reshaped by L13's guard design |
| effects: `MemRead` 13, `MemWrite` 19, `MemAlloc` 26, `MemFree` 3, `MemoryEffects<>` 8, `Pure` 24, `NoMemoryEffect` 4, `RecursiveMemoryEffects` 7, 6 `Resource`s (`IdrInterfaces.td:87-92`) | `Spec.Effects` (L01/L02) printed into `IdrEffects.td`'s resources and each op's decorators | the resources' C++ classes become generated (CTC §2.3(d)); the typed-rule trait | the six resources with D28 |
| speculation: `ConditionallySpeculatable` 6, `AlwaysSpeculatable` 2, `RecursivelySpeculatable` 2, `AlwaysSpeculatableImplTrait` 1 | `Speculation` sum on the op | `getSpeculatability` where conditional | — |
| structural traits (`IsolatedFromAbove`, `SingleBlock`, `NoTerminator`, `HasParent`, `ParentOneOf`, `Terminator`, `ReturnLike`, `SymbolTable`, `Symbol`, `AffineScope`, `AutomaticAllocationScope`, `ConstantLike`) | `UpTrait` vocabulary; `HasParent` takes an op reference | none | — |
| type relations (`TypesMatchWith` 10, `AllTypesMatch` 3, `SameOperandsAndResultType` 4, `InferTypeOpInterface` 4) | `Relation` data over positions; a transformer is data where it is identity, carrier or element, else a hook (`IdrClosureOps.td:15-16`'s lambda) | the remaining transformers | — |
| operands, results, regions: `Variadic` 32, `Arg<>` 19, `Res<>` 24, `OptionalAttr` 7, `DefaultValuedAttr` 1, `UnitAttr` 1, `TypeAttrOf` 1, `SymbolNameAttr` 2, `FlatSymbolRefAttr` 6, `SizedRegion` 9, `VariadicRegion` 1 | `Operand` (name, `Arity = Single \| Optional \| Variadic`, constraint, decorators), `Result`, `Region` (name, `Sized n \| VariadicSized n`), `Attr` (name, constraint, `Inherent \| Optional \| Default v`) | none | `UnitAttr` flags split per L13 |
| properties (`DefaultValuedProp<NamedEnumProp<Idr_Effect>>`, `IR/IdrOps.td:162, 219`) | `Attr.Property kind default` | none | the row's property becomes D29's atom set, one C++ type (§2.6 seam) |
| assembly formats (149 `assemblyFormat`; directives `type` 145, `attr-dict` 137, `attr-dict-with-keyword` 3, `functional-type` 4, `qualified` 9, `ref` 12, optional groups 10, `oilist` 1) | `Spec.Format`'s AST, references by position | none | — |
| custom directives (90 uses of 13: `Read` 42, `ResultAtGrade` 29, `CtorRef` 5, `ResultTypes` 3, `Fields` 2, `DefaultCase` 2, `Shared`, `OwnedResult`, `NaturalResult`, `MatchCases`, `LiteralCases`, `CellResult`, `CellDests`) | `Format.Custom Directive [position]`, `Directive` a 13-case enum | each directive's parse and print | per L13's ops |
| hand assembly format (5 `hasCustomAssemblyFormat`) | `format = CustomFormat hook` | the parser and printer | `Data`'s and the table's with D48 |
| builders (16 `let builders`, 11 `OpBuilder`, 7 type/attr builders, 9 `skipDefaultBuilders`, 4 `CArg`) | `Builders = Default \| Extra [BuilderHook] \| Only [BuilderHook]`; a builder with an inline body is a hook | the builder bodies | — |
| verifiers: 18 `hasVerifier`, 7 `hasRegionVerifier`, 5 `genVerifyDecl` | `Verify = None \| OnOp hook \| OnRegions hook \| Both`; `TypeDef.verify : Maybe hook` | the bodies (essential set per OS §9, L13 narrows) | — |
| folders (48 `hasFolder`), canonicalizers (9 `hasCanonicalizer`, 1 `hasCanonicalizeMethod`) | `Meaning = Runtime Symbol \| HandFolder hook \| NoFold`; `Canon = None \| Method hook \| Patterns [hook] \| DRR [Pat]` | the hand folders and patterns | the 37 ABI-restating folders with 04 T1; `DRR` enters with B |
| `extraClassDeclaration` (37) / `extraClassDefinition` (6, `$cppClass` at `IdrAttrs.td:133-139`) | `Member` hooks for what MLIR detects by name on the class (`getWalkImmediateSubElementsFn`, `getReplaceImmediateSubElementsFn`: `IdrTypes.td:107-118`, `IdrAttrs.td:343-354`) and data members; a free function or trait for the rest | the member bodies | OS §8.2's "none kept as text" is too strong: protocol members must be class members |
| bytecode records (`IdrBytecode.td`: 5 `DialectType`, 1 `DialectAttribute`, 2 `CompositeBytecode`, `DialectTypes`, `DialectAttributes`, `Idr_Enum`, `Idr_OptionalAttr`, `String`, `record`; 4 `cBuilder`) | `Bytecode = Derived \| Custom hook`, derived from the parameters (§4 I-3) | `QType`'s checked builder (`:38-40`); the table's `fromRows` | the table with D48; every idr type and attribute gets a record (14 TD2) |
| passes (27 `IdrPass`, 3 inner `Pass`; 48 `Statistic`, 1 `ListOption`, `dependentDialects`, `constructor` strings, computed `baseClass`) | `Pass` (name, anchor, `role`, `kind`, `stages = Any \| From s t`, options `= Holds`, statistics, dependent dialects, `constructor = Generated \| Named hook`, doc); `Pipeline`'s indices | the inner passes' constructor functions; the passes | role and stage records disappear from `.td` (only `baseClass` printed) |
| our record classes read only by our generator (`Idr_Runtime` `symbol`, `Idr_Guarded`, `Idr_AbiWord`, `Idr_AbiCount`, `Idr_CType` with `{0}` patterns `IdrRuntime.td:25-48`, `Idr_RuntimeFunction` 15, `Idr_RuleCase`, `Idr_WordOp` 8, `IdrPassRole`, `IdrStage`, `bit idris`, `bit holdsBodies`) | fields of `Op`, `Rule`, `Pass`, `TypeDef`; `Spec.Runtime`'s `CType` a typed declarator, not a pattern | none | not printed into `.td` at all (§1.1) |
| an op of another dialect (`Target/ScheduleOps.td:17-34`) | `Op.dialect = Transform`, the transform interfaces in the upstream vocabulary | `TransformOpInterface`'s `apply` | — |
| docs (201 `summary`, 55 `description`) | `Doc`, exact text | none | — |

Acceptance holds when every row has a constructor or a hook: none is left
to hand `.td`.

### 2.5 Constructor provenance

| fact | constructed by, alone | read by | today's constructor, deleted |
| --- | --- | --- | --- |
| each `.td` file's text | specgen, from `Spec.*` | mlir-tblgen | hand |
| `.inc` from ODS | mlir-tblgen, from those `.td` | our C++ | unchanged |
| our C++ tables (§2.3 row 4) | specgen | our C++ | `idris-mlir-tblgen` (5 files); hand C++ (`Pipeline.cpp:61-197`, `Expect.h:146-230`) |
| the runtime's declarations | specgen | runtime, lowering | `-gen-runtime-abi-decls` over `IdrRuntime.td` |
| idr Idris builders, value sums, encoders | specgen | Emit, the writer | `idris-mlir-tblgen` |
| closed sets on the Idris side | `Spec.*`, imported | frontend, harness, specgen | `Syntax/Idr.idr`; the three `.txt` |
| upstream Idris builders, enums, encoders | the D51 backend, from `IdrAdmitted*.td` and upstream ODS | Emit, the writer | `idris-mlir-tblgen` per dialect |
| the admitted upstream set and the contract's dialect list | `Spec.Admitted`, `Spec.Core.Dialect` | specgen (prints the admitted files), frontend (imports `Dialect`) | `tools/dialects.sh:83-93`; `MLIR.idr:47-54, 182-216` (14 M03, M04) |
| the pipeline and each pass's stages and role | `Spec.Pipeline`, an indexed type | specgen (`baseClass`, the pipeline's body), harness (imports) | `Passes.td`'s records and `Pipeline.cpp` twice (13 DP-01); `IdrPassRoles.txt`, `IdrPassStages.txt` |
| a refusal's category and scope | `Spec.Rules` | specgen (C++ table), frontend, harness | `-gen-rule-categories`, `IdrRules.txt`, `Profile.outsideLanguage` (16 G5) |
| hook declarations | specgen, from `Spec.Hooks` | the hand definitions (a missing one is a link error) | none: today the C++ is named by text in ODS |
| the fingerprints | `tools/spec.sh` (and the D51 wrapper) into the manifest | `tools/spec.sh check`, `tests/spec-current` | `tools/dialects.sh`'s stamp lines |
| category-1 registry rows | Q1: the registry naming spec ops (recommended) or the frontend from `implements` (C6) | the frontend | hand rows naming printed constructors |
| D48's family structure | `Spec.Families` (types), `Spec.Types` (the attribute defs) | frontend (imports the types), specgen (prints defs and encoders) | `#idr.types`, the mutable data type |
| D29's atom set | `Spec.Effects.Atom` | specgen (the row property, the C++ tables) | `Idr_Effect`'s bits |

Who may write an output: specgen alone, through `tools/spec.sh`; `make
check` fails on any other edit. Error paths: a local invariant fails at its
Idris line; a global decision fails as an unsolved `So` whose decision
returns the offending record (OS §10); an upstream name the spec gets wrong
fails in mlir-tblgen or the D51 backend at a generated line whose comment
names the op's family and constants (§2.7: there is no reflection to name a
spec definition). Cleanup: specgen writes a temporary tree; the wrapper
removes it on exit (as `tools/dialects.sh:95-96`), so a failure leaves the
committed outputs untouched.

### 2.6 The build graph

| step | runs when | reads | writes |
| --- | --- | --- | --- |
| `make bootstrap` | unchanged (`tools/bootstrap.sh:232`) | pins | `.toolchain/` |
| `make spec` (new; `fork`'s pattern) | before `build`, `check`, `runner`, `typecheck`, `self`; again when a spec or specgen source changes | `compiler/spec/**`, `compiler/specgen/**` | `idris-mlir-spec` in `HOST_PREFIX`; `compiler/specgen/build/exec/specgen` |
| `tools/spec.sh generate` | first in `make build` | specgen's temporary tree; committed outputs | each output whose bytes differ; the manifest |
| CMake build | after it | generated `.td`; `IdrAdmitted*.td` and upstream ODS (the D51 backend) | `.inc` (write-if-changed); C++; the runtime |
| `tools/dialects.sh generate`, upstream only | after the C++ build (needs the backend) | `IdrAdmitted*.td`, upstream ODS | the six upstream modules that changed; their manifest rows |
| `frontend`, `libs` | as today | the spec package; printed modules | unchanged |
| `make check`: `tests/spec-current` | always | spec and specgen sources | a temporary build and tree; it fails on any byte of difference from the committed outputs or the manifest, and runs one planted module per global decision, each of which must fail to type-check |
| `make check`: upstream half of `tests/dialects-current` | always | mlir-tblgen's record dump, the backend's source | none |
| `make typecheck` | parts: configure, spec, tblgen, cxx, dialects, libs, fork, frontend | as above, with the typecheck TableGen | as above |
| `make self` | adds `self-spec`: the frontend installs the spec in `CHECKOUT_PREFIX` and builds specgen | the same sources | a temporary tree compared byte for byte with the committed outputs (D52) |

Seams fixed here: CMake drops `tablegen(IDR ...)` and the target
`IdrRuntimeAbiIncGen` (`IR/CMakeLists.txt:15-29`) with its dependents
(`runtime/CMakeLists.txt:210, 238, 255`; `foreign/idr/CMakeLists.txt:259`).

### 2.7 Determinism under both hosts, by representation

| source of divergence | what makes it unwritable |
| --- | --- |
| a host primitive's text (`show` of a number; X01's float) | the spec has no `Double` anywhere; specgen prints integers with one printer over `Nat` (division by ten), never `show`; strings are concatenated, never `show`n (its escaper is specgen's own, over ASCII ranges) |
| case mapping or character classes beyond ASCII | every identifier is an `Ident`, built only from `[a-z0-9_.]` with an erased proof per character; docs are printed verbatim (one UTF-8 encoding per scalar sequence) |
| order | outputs are a `List (Path, Text)` in declaration order; specgen sorts nothing and has no map |
| environment, time, paths | printers import no `System`; `Main` reads one argument and writes paths relative to it; the wrapper, not specgen, compares and moves files |
| the target | the spec holds no target fact (`AGENTS.md`: the target is CMake's entry); outputs are identical on the four targets |
| line structure | one renderer ends every line with `\n` |

### 2.8 What goes

- The 21 hand `.td` files as sources (5,900 lines, *measured*); `IdrRuntime.td`
  entirely.
- `idris-mlir-tblgen`'s eight registrations that read our records and the
  idr regions of the three kept (§1.7); `tests/file-size/allowed`'s line
  for the tool if the cut brings it under 400 lines (*conjecture*).
- `IR/CMakeLists.txt:15-29`; `tools/dialects.sh`'s idr row and its hand
  dialect list.
- `Syntax/Idr.idr`'s nine enum namespaces, then the file (§2.3); the three
  `.txt` files and their shell readers (§1.6).
- `tests/facts-in-types` and its planted `.td` (after 14 T38); the `.td`
  halves of `tests/no-behaviour-options`, `tests/registry-only`
  (`witness/.../Length.td`), `tests/zones` and `tests/file-size` (their
  planted `.td`), each a rule over generated text whose state the spec's
  types refuse; `tests/dialects-current`'s idr half becomes
  `tests/spec-current`.
- The fingerprint lines in generated files, for the manifest (Q2).

### 2.9 Seams with other lanes

- **L01, L02 (effects):** the content of `Spec.Effects` is theirs; the
  constructors that print it (resources into `IdrEffects.td`, decorators,
  `EffectTree.h.inc`, `EffectFacts.h.inc`) are mine. **Unfixed:** the atom
  set's one C++ type. Recommended: the dense `Atom` enum and
  `EnumSet<Atom>` that specgen prints, with the row property declared over
  that storage type (its parser and printer printed from the spelling
  table), so no second C++ type (mlir-tblgen's bit enum) exists beside it.
- **L04 (families):** the family attribute's defs need constructors
  today's `.td` never uses: an attribute interface (0 `AttrInterface`
  today) for index terms and recursive attribute parameters; the frontend
  builds families with `Spec.Families`' types, imported, and writes them
  with printed encoders.
- **L13 (ops):** the op table is theirs; `Meaning`, `Canon`, `Verify`,
  `Speculation`, `Builders` and the `Directive` enum are mine.
- **L15 (C++):** the printed headers' shapes are CTC §2.3's, restated as
  Idris printers.
- **L16 (frontend):** imports of the spec; builders per group returning
  `Op k` (14 TD3); the registry (Q1).
- **L19 (tests):** `tests/spec-current`, planted modules, the harness
  importing the spec, the rule-coverage check moved from shell.

## 3. QTT

**Where quantities enter this area.** The spec is ordinary Idris: its
quantity-0 proofs and indices are checked by both hosts' elaborators and
erased by both back ends (Chez drops erased arguments; idris-mlir emits no
parameter for them, `AGENTS.md`), so specgen pays nothing at run time for
any law. Quantity 1 has no use inside the spec. What the spec *says* about
quantities is the dialect's grade vocabulary, and that is where facts are
held twice today:

| QTT fact | where it is held today | where it goes |
| --- | --- | --- |
| quantity 0 has no value | `Quantity` has no zero case (`IdrBase.td:81-84`) | `data Quantity = One \| Many`: no constructor, so no grade, field or operand can say zero (D48's "a field's quantity a type with no erased case") |
| a read operand is at ω and not owned | three `CPred` strings per read class (`IR/IdrOps.td:23-26`) | `TypeC.Graded Many NotOwned carrier`, printed to the C++ predicate and to the builder's operand type |
| a closure is at quantity one exactly when a capture is | the C++ predicate (`IdrClosureOps.td:22-26`) **and** Emit's `any linearType captures` (`Emit/Bodies.idr:331-344`, which calls itself essential) | one typed result-quantity rule on the op, printed to the C++ predicate and to the printed builder, which computes the result grade (§4 I-7) |
| a type is linear by itself (world, destination, cell) | the interface method `isLinearByType` per type (`IdrInterfaces.td:43-47`) **and** `linear One WorldT = False` in Emit (14 E01) | a fact on each `TypeDef`, printed to the interface's answer and imported by Emit |
| a grade pair the verifier refuses | the generated `QType` is the full product (14 G03) | the grade constructors the frontend may write, imported from `Spec.Grades` (the frontend writes one grade, 14 §2.6) |
| the runtime arity of a base primitive | the registry's shape (`Pi Mw ... (Pi M1 world ...)`, `Registry/Primitives.idr:53-55`) and the op's operands, never related; a wrong count is MLIR's reader error (`ioOp : IOPrim -> List Value`, `Dialect/Idr.idr:1661`; 14 T29) | a decision that each binding's shape has exactly as many arguments at a non-zero quantity, the world aside, as its op has operand groups (§4 I-4) |

**The laws L1 to L11 (EV §6) as erased proofs**, sorted by how each is
held, with its two-host risk:
- *A field's erased argument, found at the definition:* L1 (`Parent`'s
  `earlier`), L2 (`Fits`), L3 (`Admits`, `addr`), L6 (`notAcquire`), L7
  (`Stops` with its erased proof). L1's `LT (rank p) (rank r)` built by
  `auto` is a chain as deep as the rank; held instead as a position, a
  parent of `r` is a `Fin (rank r)` into the resources declared before it,
  so a cycle or a later parent has no value and no search runs.
- *By representation, no proof:* L9 (`Admits RuntimeState Read` alone),
  L10 (`Admits Heap` has no `Write`), L11 (the row is the atom set).
- *A quantity-0 theorem by case split:* L4 (`Refl` per atom).
- *A decision over `allOps` beside its lemma:* L5's coverage part, L8.
  Evaluated by both elaborators; cost unmeasured (OS §10).
- *A quantity-0 theorem over a model:* L5's `sound`. The heaviest proof in
  the spec; its elaboration time under both hosts is to measure.

**What a type there makes unwritable that a check catches today:**
- a discardable attribute (`tests/facts-in-types`): no field, once 14 T38
  makes the report inherent;
- a pass option that selects behaviour (`tests/no-behaviour-options`'s
  `.td` half): `PassOption` has one constructor, a check's property list;
- a pass that runs at any stage but sets one (TableGen `assert`,
  `Passes.td:66-67`): `stages = Any | From s t`;
- two guard ops for one check kind, or a kind no guard op checks
  (`idris-mlir-tblgen.cpp:1005-1013`, at the C++ build): the guard op is a
  total function of the kind;
- a guard naming a missing operand (`Guard.operand : Nat`,
  `Dialect/Idr.idr:44-47`; Emit's internal errors at
  `Emit/Operations.idr:67, 82`, met while compiling a user's program): a
  `Fin i` position;
- a misspelt ABI kind (`kindSpelled`, `idris-mlir-tblgen.cpp:787-797`):
  `AbiKind` an enum;
- a builder for an op the frontend's stage forbids (no check today, 14
  T22): builders printed for `Higher` ops alone;
- an IO primitive of the wrong arity (14 T29): the binding decision.

**Using quantities harder.** The three facts held twice in Idris and C++
(the closure's quantity, linearity by type, read operands) become one
typed rule each. The builders then refuse at Emit's compile time what the
C++ verifier refuses today only after the module is read: a closure
written at the wrong quantity, a linear-by-type value given a grade. With
14 TD3's numbered values carrying their grade, a builder's linear operand
can demand a value whose grade is linear, closing 17 FB-28's class (Emit
demoting a quantity-1 binder) at the boundary; that last step is L16's
(*conjecture*).

## 4. Improvements

**I-1. One manifest holds the fingerprints; no generated file carries a
stamp.** *Owner* (amends D49's wording, keeps its intent). Q2.
- *Evidence:* §1.5: 260 direct includers of `IdrDialect.h`, which includes
  the guards header; 56 runtime includers of `idris_rt.h`; origin/main's
  stamp-only diff; 14 T50's 16 of 29 commits.
- *Counterexample:* edit the summary of `idr.str.length`. With a spec
  fingerprint in every output, the guards header, the ABI header and
  `idris_rt_ops.h` change, and 316 files recompile for a doc comment.
- *Root cause:* a fact (the spec changed) stamped on files it does not
  reach.
- *Correction:* `compiler/spec/Generated.manifest`, committed: the
  `cksum` of the spec's and specgen's sources, and per output its path and
  the `cksum` of its text; the D51 wrapper's rows (records and generator
  fingerprint, as today) in the same file. `tools/spec.sh check` needs no
  Idris (stale or edited); `make check` regenerates and compares bytes, the
  real check.
- *Deletes:* every stamp line and the `sed` that strips it
  (`tools/dialects.sh:144, 150-151`).
- *Discriminator:* `tests/spec-current`: a spec comment changes only the
  manifest's first line; a doc change changes only the files printing it;
  a hand edit of an output is flagged.

**I-2. Every reference inside an op is a position, `Fin n`, never a
name.** *Coordinator* (the skill: a lookup that can miss is a missing
index; D48 already writes the spec's index terms this way).
- *Evidence:* OS's `Op` holds `ins : List Operand` and three erased
  searches (`named`, `ruled`, `guarded`); guards today are names checked by
  the C++ generator and positions as `Nat` in Idris
  (`Dialect/Idr.idr:44-47`); `auto` depth differs between hosts (§1.11).
- *Counterexample:* `Idr_Guarded<["rsh"], Idr_Nonzero, ...>` on `divs`
  fails only when the C++ generator runs; a printed guard at position 5 on
  a two-operand op compiles and fails as Emit's internal error.
- *Root cause:* the operand's identity is a string.
- *Correction:* `Op` indexed by its group counts (`Vect i Operand`,
  `Vect o Result`, `Vect a Attr`, `Vect r Region`); `Format i o a r`,
  `Guard i`, effect rules and type relations reference positions; names
  live only in the operand records, printed by a total `index`; members
  sit in `allOps` behind erased counts. Distinct names within an op stay a
  decision.
- *Deletes:* the three erased searches, `Guard.operand : Nat`, two Emit
  internal errors (14 T20, E10), the generator's guard-name check.
- *Discriminator:* a planted op with a format naming operand 2 of 2 has no
  value; the fixture of §1.11 confirms idris-mlir accepts `Op` stored with
  erased counts (if it refuses, the counts stay in erased proofs over
  lists, decided by `So`, not searched).

**I-3. A type's bytecode layout is derived from its parameters.**
*Coordinator* (one fact, one place).
- *Evidence:* `IdrBytecode.td:38-46` restates each type's parameters
  (`QType`'s `quantity`, `permission`, `value`, `lifetime`;
  `IdrTypes.td:286-288`) member for member; mlir-tblgen's reader keeps them
  in step by failing to compile.
- *Counterexample:* add a parameter to `!idr.fn` and forget its record:
  the writer and reader disagree until a C++ compile fails; in the spec it
  cannot be forgotten.
- *Correction:* `Bytecode = Derived | Custom hook`; `Derived` maps each
  parameter kind to a member (enum to `VarInt`, type to `Type`, attribute
  to `Attribute`, string to `String`, array to `Array`), printed to the
  `DialectType` record and to the Idris encoder; `Custom` only for a
  checked builder (`QType`'s, `:38-40`).
- *Deletes:* the restated member lists; with 14 TD2, every idr type and
  attribute gets a record, and the writer's text path for idr goes.
- *Discriminator:* the round trip of `tests/dialect-syntax` shrinks to the
  custom hooks; every derived layout agrees by construction.

**I-4. A primitive's binding is checked against its op's arity through
quantities.** *Coordinator.*
- *Evidence:* §3's last row.
- *Correction:* a decision: for each binding, the arguments of its shape
  at `M1` or `Mw`, the world aside, number exactly the op's operand groups,
  and its literals fill the rest in order. Where the binding lives is Q1.
- *Deletes:* 14 T29's refutable clause, its comment and the path where
  MLIR's reader reports the miscount.
- *Discriminator:* a planted binding of `prim__open` (two strings) to a
  one-operand op fails to type-check.

**I-5. The dialect list and the admitted upstream set are one spec
fact.** *Coordinator* (deletes a hand list in shell; 14 M03, M04, B02-B04).
- *Correction:* `Spec.Core.Dialect` and `Spec.Admitted`; specgen prints
  one `IdrAdmitted<D>.td` per upstream dialect; the frontend imports
  `Dialect` for `MLIR.idr`'s dialect constructors and the writer's dialect
  numbering.
- *Deletes:* `tools/dialects.sh:83-93`; `MLIR.idr`'s per-dialect smart
  constructors and string dialect names (14 M03, M04); the writer's
  text-before-the-dot dialect (14 B02); the unused upstream builders (14
  T22, G01).
- *Discriminator:* a dialect the spec drops leaves no module (today's
  check at `tools/dialects.sh:167-180`, now over the spec's list).

**I-6. specgen's C++ AST has no branch over ops.** *Coordinator* (D47 in
generated code).
- *Correction:* the C++ printer's tree admits enums, `constexpr` arrays
  indexed by a generated enum, class-template specializations with
  `constexpr` members, and declarations of hooks; no `if`, `switch`,
  `isa` or concept body. A table or a specialization is the only way to
  say a per-op fact.
- *Discriminator:* the printer has no constructor for a ladder; no test
  needed.

**I-7. Grade rules are typed data, printed to C++ and to the builders.**
*Coordinator* (one fact held in Idris and C++, §3).
- *Correction:* `TypeC.Graded`, `ResultQuantity = MaxOfOperands
  [position]`, `TypeDef.facts.linearByType`; printed to the C++ predicates
  and interface answers, and to the builders (result grade computed) and
  imported by Emit.
- *Deletes:* `Emit/Bodies.idr:331-344`'s rule, `linear One WorldT = False`
  (14 E01), three `CPred` strings per read class.
- *Discriminator:* a test compiling a closure over a linear capture checks
  the result grade by exit status and verifier, before and after.

**I-8. Cutover A's gate made complete.** *Coordinator.*
- *Correction:* the byte identity covers `idris-mlir-tblgen`'s outputs and
  the three `.txt`; specgen keeps today's op def names, the definition
  order of types, attributes and interfaces, and explicit enum values for
  `Quantity`, `Rule` and `CheckKind` until B renumbers (§1.1). Cutover A
  prints the constructs B deletes (§2.4's last column: the mutable type,
  the table, `World`, the six resources, the marker traits, the guard
  marks, `bit idris`, `bit holdsBodies`, `Effect`'s bits); each B change
  deletes its constructor and printer branch with it, so no constructor
  outlives its construct.

**I-9. A law proven in the spec reaches C++ as its table, not as a
re-proof.** *Coordinator* (D10, CTC R4).
- *Evidence:* CTC §2.3(c) checks the grade algebra's laws by
  `static_assert` over hand `constexpr` code while OS §4.2 proves them by
  case split: the same laws twice.
- *Correction:* specgen prints the algebra's tables (or the Idris proof
  that `fitsIn` is the declaration order licenses `<=` on the printed enum);
  no `static_assert` restates a law; C++ asserts only that a hand function
  equals a printed table.
- *Deletes:* CTC's `semilattice()`-style checks.

**I-10. The canonical contract amended for D16 and D51.** *Coordinator*
(a contradiction in the contract).
- CTC §1.1 (T0), §2.1, §2.2, §2.3's sketches, §4.8; proposal §5.6's
  generator bullet; synthesis D §2.6; `AGENTS.md:185` ("carries its
  category in ODS") and `:580` ("generated to both from ODS"): each now
  says the specification.

## 5. Work units (draft)

**U1. Cutover A: the source moves.** Parts U1a to U1e land in one commit.
- *U1a* writes `compiler/spec/idris-mlir-spec.ipkg`,
  `compiler/spec/IdrisMLIR/Spec/{Core,Hooks,Format,Constraints}.idr`,
  `compiler/specgen/**`, `tools/spec.sh`, `compiler/spec/Generated.manifest`.
- *U1b* writes `Spec/{Enums,Grades,Rules,Interfaces,Traits,Types,Bytecode}.idr`.
- *U1c* writes `Spec/Ops/*.idr`, `Spec/Dialect.idr`, `Spec/Effects.idr`
  (today's six resources, unchanged).
- *U1d* writes `Spec/{Runtime,Pipeline,Admitted,Expect}.idr`,
  `Spec/Ops/Schedule.idr`.
- *U1e* writes the outputs, `foreign/idr/include/idr/IR/CMakeLists.txt`,
  `foreign/idr/CMakeLists.txt`, `runtime/CMakeLists.txt`,
  `foreign/idr/tools/idris-mlir-tblgen.cpp`, `tools/dialects.sh`,
  `Makefile`, `tests/spec-current/**`, the deletions of §2.8.
- *Outcome:* every hand `.td` deleted; mlir-tblgen's and the old
  generator's outputs byte-identical (§4 I-8); the frontend's modules
  identical.
- *Must not:* change any op, type, attribute, effect or name; keep a hand
  `.td` or a verbatim fragment; keep the old generator for any idr fact.
- *Acceptance:* the five suites and `make check` on the four targets;
  outputs compared byte for byte before and after; `tests/spec-current`'s
  cases (§4 I-1).

**U2. D50: the Idris side imports.** Writes the 22 importing modules,
`compiler/syntax-samples.ipkg`, `harness/**`, `harness/lib/{rules,profile,differential}.sh`,
`tests/rules-covered/run`, `Makefile` (`runner`). Deletes `Syntax/Idr.idr`'s
enums and the three `.txt`. Must not keep a printed copy. Acceptance: the
harness reports the same rules and stages as before; the suites unchanged.

**U3. D51: the slim backend.** Writes `foreign/idr/tools/idris-mlir-tblgen.cpp`,
`Spec/Admitted.idr`, `tools/dialects.sh`, `MLIR.idr`, `MLIR/Bytecode.idr`.
Deletes §4 I-5's list. Must not read a record of ours. Acceptance: the
frontend's modules for the six upstream dialects hold only admitted
builders and used encoders; the suites unchanged.

**U4. Positions, not names.** Writes `Spec/Format.idr`, `Spec/Ops/**`,
specgen's Idris printer; Emit call sites with L16. Deletes §4 I-2's list.
Acceptance: §4 I-2's discriminator; suites unchanged.

**U5. Primitives** (after Q1). Writes `Spec/Ops/**`, `Registry/**`,
`Dialect/Idr.idr`'s output, Emit's primitive calls. Deletes the printed
primitive sums or keeps them per Q1; the `Primitive` trait; 14 T29.
Acceptance: §4 I-4's discriminator; every program of `tests/` compiles to
the same artifacts.

**U6. D52: the second host.** Writes specgen's renderer (§2.7),
`Makefile` (`self-spec`), `tools/self.sh`. Acceptance: specgen built by
idris-mlir writes the committed tree byte for byte on the four targets.

**U7. Derived layouts and native idr bytecode.** Writes `Spec/Bytecode.idr`,
`Spec/Types.idr`, `MLIR/Bytecode.idr` with L16. Deletes the writer's text
path for idr types and attributes. Acceptance: the writer has no text
constructor for an idr type or attribute; suites unchanged.

## 6. Owner questions

**Q1. How the Idris side names a primitive (D50's letter, C6).**
- *(A) As decided:* each spec op lists the base primitives it implements;
  specgen prints the primitive sums and the registry's rows. Costs: the
  registry's vocabulary moves into the spec; the spec carries base's
  spelling; the rule that only the registry names Idris definitions gets a
  second home. Buys: adding a primitive is one edit.
- *(B) D50's own reason applied:* a primitive has no attribute, so one
  generic builder over the spec's op value is in the subset (`pureOp`
  already is, `Dialect/Idr.idr:1355`); the registry's rows name the spec op
  they mean; base names stay in the registry; C6 is withdrawn. Costs:
  adding a primitive is two edits. Buys: no printed primitive sums, no
  moved vocabulary, no coupling, the same one-fact property.
- *Recommendation:* (B).

**Q2. D49's stamps.** (A) a manifest holding the spec's fingerprint and
each output's text fingerprint (recommended, §4 I-1); (B) one stamp per
file, its text's only; (C) D49's letter, a spec fingerprint in every file,
which recompiles every includer of a generated header on any spec edit.

**Q3. Who names upstream ops in C++.** The admitted set feeds C++ stage
legality and `BigToWord`, which need upstream C++ classes. (A) The D51
backend gains one emitter, the C++ table of admitted ops, read from the
same records (recommended: the class comes from the def, so the two cannot
name different ops); (B) the spec restates each class name beside its def
name, each checked by its own compiler, free to disagree.

*HEAD at finish: `e96bb991` (2026-10-21T22:05Z), unmoved; no anchor
needed re-checking.*
