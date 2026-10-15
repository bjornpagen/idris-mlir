# U14 — Frontend translation: request chains, content names, arrays recognized

## Permitted outcome

Each item is observable in the source and, on the owner's machine, in the
emitted Core and module. All are Mandatory unless marked.

1. **Mandatory. The request-chain rule decides polymorphic recursion.**
   `Translate/Instances.idr`'s `request` refuses a new instance of a
   definition exactly when, against an instance of the same definition
   on its request chain, its static arguments are smaller in no
   position and larger in one, by the size of their normal forms (0012
   D4, 0004 D40). The refusal is `unsupported (polymorphism)` at the
   requesting call, with the message C20 fixes. No count, budget or
   blanket refusal decides acceptance in the frontend any more.
2. **Mandatory. The frontend's half of names from content (C21).**
   `IdrisMLIR.Ids` holds XXH3's 128-bit hash in plain Idris over
   `Bits64`, the UTF-8 bytes of a string, 16-digit hex, and
   `contentName`, exactly as C21 declares them.
3. **Mandatory. Instance symbols by the key alone (0009 §4.10, 0007 §4.5).**
   The key printer reports whether its print dropped part of the
   instance's identity; `InstanceKey` carries that report with the low
   64 bits of the identity hash; `Term.keyText` is the symbol (the
   print, or the print, `;` and 16 hex digits). `FnId` and `DataId` are
   that symbol, interned once; two identities on one symbol are an
   internal error. The bucket-and-position identity goes.
4. **Mandatory. Every hook applied below its arity is eta-expanded.**
   The identity hook (`replace`, `rewrite__impl`, the pointer casts,
   `nest`, `merge`, `freeze`, `natToFinLT`), the identity on its last
   runtime argument, below its full arity is a closure over its missing
   runtime parameters whose body is the saturated identity, through the
   same `finish` every other hook uses (0002 D18). The profile's
   `answersForBody` then holds at every arity.
5. **Mandatory. Binder identity.** The program root and the exit's
   world lambda are generated code: their location is the generated
   location (`Loc` of origin `Generated`, no file), and their world
   binder is named `world`. Holes an implementation closes over are
   normalised as bound variables of an Idris `Env`, never renamed to a
   function reference around the normaliser.
6. **Mandatory. Data facts from the registry (D19, D29).** The list's two
   constructors carry their role (`Con.role`) from registry entries on
   `Prelude.Basics.Nil` and `(::)`; instances of `Linear.List.LList`
   and `Linear.Nat.LNat` carry the in-place promise (`Data.promise`)
   from registry entries on those types. Emission writes both into the
   identified type's body (C01, C22).
7. **Mandatory. The `BreakLast` purpose and its table column are gone**
   from `Registry/Libraries.idr`.
8. **Mandatory. Refusals name their rule by the generated enum (C04).**
   Every importer of the hand-written rule module imports
   `IdrisMLIR.Syntax.Idr`, where C04 generates `Rule`; `show rule` is its
   phrase; the ipkg no longer lists the hand-written module.
9. **Mandatory. Arrays recognized as MLIR's types (0003 §2, §4.1, D13, D14).**
   `Array s a` and `LArray s a` are `TensorT` with one dimension per
   axis of the shape's form, static where the shape's normal form at the
   instance is a literal and dynamic otherwise; `ArrayData a`,
   `Mut a` and `Buffer` are `MemRefT`. A tensor inside a closure's or a
   suspension's type has every dimension dynamic. An erased shape
   argument that a value array's shape needs keys the instance by its
   form (the spine, extents erased). The generating set and `LArray`'s
   operations are recognized by name through registry entries and
   translated to C20's `Tensor`, `Tabulate`, `TabulateIO`, `Reduce` and
   `Tie` terms;
   a function's entry ties every array argument's dynamic dimensions
   that share a size variable, and a call's result is tied where its
   type's extents come from the call's arguments.
9a. **Mandatory. Arrays of records are one array per field (0003 D44,
    the coordinator's assignment).** An array of either kind whose
    element is a record (one constructor of two fields or more, not
    containing itself, every field holdable by that kind of array) is
    C20's `ColumnsT kind dims record`, decided once in `coreType`; every
    term on it is written as on any array, and emission writes it one
    array per field, reads gathering and writes scattering (C20 §10).
    Linear and world-ordered arrays of records follow the same split.
9b. **Mandatory. A tabulation's cells have extents its type fixes.** A
    `Tabulate`, `TabulateIO` or `withArray` fill whose cells (or a record
    element's array fields) have a dynamic dimension is refused,
    `unsupported (type)`, "an array of cells whose extents no type fixes"
    (C20 §2): nothing holds those extents before the first cell is made,
    nor when the array is empty.
10. **Mandatory. The old array recognition is gone:** `Rank`, `ArrayT`,
    `IndexBelow`, the `ArraySize` and `ArrayLoop` hooks, the region
    term, the two Scheme-spec registry entries of the in-house linear
    array library and the index-space entries.
11. **Mandatory. The deleted modules and options are gone** (`## Delete`).
12. **Mandatory. `compiler/idris-mlir.ipkg` lists every module of the
    package as it is at integration:** the deletions here (the profiling
    module and the hand-written rule module, whose `Rule` C04 generates
    into `IdrisMLIR.Syntax.Idr`), `Translate.Shapes`, and every module C22
    names.
13. **Consumer adaptations (Mandatory):** `Frontend/Program.idr` calls
    emission through C22's entry point; `Frontend/Driver.idr` loses the
    deleted option; `Graph.idr`'s module comment stops naming a deleted
    pass.

## Owner / exclusive writes

ownership.json's U14 entry, every path:
- `SRC/Frontend` (`compiler/src/IdrisMLIR/Frontend`): `Driver.idr`,
  `Program.idr`, `Resolve.idr`, `Profile.idr`, `Translate.idr`,
  `Translate/*.idr`. Deleted: one module, named under `## Delete`. New:
  `Translate/Shapes.idr` (shape forms, extents, ties).
- `SRC/Registry` (`compiler/src/IdrisMLIR/Registry`): `Entry.idr`,
  `Libraries.idr`, `Name.idr`, `Primitives.idr`, `Recognized.idr`.
- `SRC/Registry.idr` (`compiler/src/IdrisMLIR/Registry.idr`).
- `SRC/Facts.idr` (`compiler/src/IdrisMLIR/Facts.idr`).
- `SRC/Graph.idr` (`compiler/src/IdrisMLIR/Graph.idr`).
- `SRC/Term.idr` (`compiler/src/IdrisMLIR/Term.idr`).
- `SRC/Types.idr` (`compiler/src/IdrisMLIR/Types.idr`).
- `SRC/Ids.idr` (`compiler/src/IdrisMLIR/Ids.idr`).
- `SRC/Loc.idr` (`compiler/src/IdrisMLIR/Loc.idr`).
- `compiler/idris-mlir.ipkg`.

**Excluded:**
- `compiler/src/IdrisMLIR/Emit.idr`, `Emit/`, `MLIR.idr`, `MLIR/`,
  `SyntaxSamples.idr`, `compiler/syntax-samples.ipkg`: U15. Emission of
  `Tensor`, `Tabulate`, `Reduce` and `Tie`, the `tensor.cast` at slots,
  symbol-form closures, lambda names, the bytecode writer and the
  identified type bodies are U15's, written against C20 and C21.
- `compiler/src/IdrisMLIR/Rule.idr`, `Dialect/`, `Syntax/`,
  `foreign/idr/tools/idris-mlir-tblgen.cpp`: U01 (C04 generates the rule
  module that replaces `Rule.idr`).
- `libs/`, `compiler/idris/src/Libraries/Data/Table.idr`: U13 (C19).
- `tests/`: U17 and U18. The XXH3 test-vector test, the request-chain
  fixtures and the registry tests are theirs, against C20 and C21.
- `tools/dialects.sh`, the Makefile and every CMake list: the
  coordinator.
- `foreign/idr/`: the C++ lanes.

## Read first

- `contracts.md`: C20 and C21 (yours), and C01, C04, C11, C19, C22.
- 0004 `README.md`: §2.5 (what is still refused), §4 stage 1 (every
  bullet, `README.md:675-778`), the §6 rows at `README.md:1245` (the
  frontend's owner clause), `1256`, `1262-1263`, `1265`, `1267`,
  `1270-1271`; D18, D19, D29, D36, D40, D42, D43.
- 0012 (`proposals/0012-self-host-features.md`): "What stays refused",
  feature 2 (the rule, why it is total, what it deletes), D4.
- 0009 §4.10 (`proposals/0009-data-oriented-frontend.md:434-560`): the
  instance-symbol rule and what the print drops.
- 0007 §4.4, §4.5, D16 (`proposals/0007-sharded-whole-program-compiler.md:434-470, 990-1000`).
- 0003 (`proposals/0003-typed-apl/README.md`): §2 (the correspondence),
  §3.1, §3.2, §3.5, §3.8, §4.1, §4.3, §13, §15's frontend row, §17
  stage 1, D2, D4, D13, D14, D19, D25, D37, D39.
- 0002 (`proposals/0002-get-back-on-track.md:297-311`): the castPtr seam.
- The live code, whole files: `Frontend/Translate/Instances.idr`
  (`request` 99-117, `growing` 62-92, `classify` 206-303),
  `Translate/Recursion.idr` (`checkComponent` 125-152),
  `Translate/Keys.idr` (`render` 264-306, `instanceKey` 319-343),
  `Translate/Closed.idr` (`normaliseKeeping` 499-506, the markers
  464-516), `Translate/Terms.idr` (`application` 340-400, `finish`
  658-676, `arrayLoop` 1007-1033, `exitAction` 761-772),
  `Translate/Types.idr` (`coreType` 390-437, `dataInstance` 446-536,
  `dataOf` 538-553), `Translate/Programs.idr` (`translateIOProgram`
  159-196), `Translate/State.idr`, `Profile.idr` (`answersForBody`
  65-70), `Program.idr`, `Driver.idr`, `Resolve.idr` (`validate`
  209-250), `Registry/*.idr`, `Types.idr`, `Term.idr`, `Ids.idr`.
- Their consumers, to keep what C20 promises: `Emit/Index.idr`,
  `Emit/Declarations.idr`, `Emit/Types.idr`, `Emit/Bodies.idr`,
  `Emit/Operations.idr`.
- XXH3: `.toolchain/build/llvm-project/llvm/lib/Support/xxhash.cpp:60-140,
  395-470, 480-956` and the published values in
  `llvm/unittests/Support/xxhashTest.cpp:15-31, 78-130`.
- Idris's normaliser under an environment: `compiler/idris/src/Core/Normalise.idr`
  (`normalise`), `Core/Env.idr`, `Core/TT/Subst.idr`.

## Fixed decisions

- **The rule (0012 D4).** A request of a new instance of definition `d`
  (its `nameKey`), with static vector `v` (one entry per parameter of
  `d`'s type: the value `staticOf` gives, a form for a form parameter,
  and none elsewhere), walks the chain of requesters from the instance
  being translated (`TS.current`, then each `Request.parent`) to the
  root. For every instance `a` of `d` met, with vector `u`, it refuses
  when `size v_i >= size u_i` at every position and `>` at one. `size`
  is C20's: 0 for no value; for a term, 1 plus the sizes of its parts,
  an integer literal counting 1 plus its magnitude and a string literal
  1 plus its length. The refusal names `d`, the parameter at the first
  growing position and both instance keys, at the requesting call's
  location. `checkComponent` keeps computing the loop verdicts and
  refuses nothing.
- **Hash and name format (C21).** XXH3-128, seed 0, default secret, over
  the UTF-8 bytes of the key text; a name carries `low` as 16 lowercase
  hex digits. A generated name is `<owner>.<kind>.<hex16>`.
- **Instance symbols.** The printer is C20's `renderKey`: it returns the
  print and whether it dropped part of the identity. Loss is reported
  for: an `Erased` of reason `Impossible` or `Dotted`, a `Meta` with
  arguments, a `DN` (its display name is dropped), a case or with block
  name (its number is dropped), a lambda or let (binder type and
  quantity dropped), a binder printed through (`PVar`, `PLet`,
  `PVTy`), a default implicit printed as implicit, an integer constant
  (its width is dropped), a `TDelay` (its type is dropped) and an
  as-pattern (its name is dropped). The identity text is C20's
  `identityText`, a structural encoding with no location and no binder
  name; its XXH3-128 low half is the suffix.
- **Ids are symbols.** `FnId.name` and `DataId.name` are the symbol;
  `TS.named` keeps the lookup by arguments and gains the intern table
  `TS.symbols : SortedMap String (List (Maybe ClosedTerm))` per symbol.
- **Binder identity.** A generated binder (the root's world, the exit's
  world) is at `noLoc`; the root `TFn`'s `loc` is `noLoc`. Holes:
  `normaliseKeeping` turns each marker into a local of a scope of the
  hole names (`refsToLocals`), normalises under an `Env` that binds each
  as a pattern variable, and substitutes the markers back
  (`substs`); `heldMarker` is deleted.
- **Registry facts.** `Hook` gains `Plays Role` (a constructor's role,
  Faster) and `Promises Promise` (a type's promise, Stricter); `Role`
  and `Promise` are declared in `Types.idr` (C20). The frontend asks
  `Registry.isShapeType`; the registry compares.
- **Columns.** `Ty` gains `ColumnsT ArrayKind (List Dim) DataId`;
  `Translate/Types.idr`'s `columnar` and `arrayOf` decide it from the
  registered declaration (`TS.datas`, `TS.building`, `TS.reentered`), so
  a record that contains itself, or is still being registered, is never
  split, and one Idris type has one Core type.
- **Arrays.** `Dim` is C22's (`IdrisMLIR.MLIR`); `Ty` gains `TensorT
  (List Dim) Ty` and `MemRefT (List Dim) Ty`. A form parameter is
  `PKind`'s `FormParam ClosedTerm`. The rank of a shape a generating
  call takes apart is read from its operands' and result's `Ty`, never
  from the order of the implicits (C20). Extents and coordinates are
  taken apart by tag (0 the empty one, 1 the snoc), which C19 fixes.
  Coordinates and extents stay naturals in Core; their conversion to
  `index` is emission's. A world-ordered access keeps its guard.
- **No option.** The frontend keeps `--timing` (observation) and reads
  no environment.

## Inputs

- C01: the identified data type's body holds a constructor's role and
  the type's promise (emission writes them from C20's `Con.role` and
  `Data.promise`; U14 only fills the Core).
- C04: the generated Idris rule module, its constructor names and its
  phrase function; `CompileBudget` absent.
- C11: `idr.tie_shape`, which U15 writes for C20's `Tie`.
- C19: the module `Array.Core`, its names, signatures, implicit counts
  and constructor order (`Array`, `LArray`, `Extents`, `Index`, `Cell`,
  the generating set, `withArray`, `read`, `write`, `freeze`, `thaw`,
  `lshape`, `grow`, `tabulateIO`), the package name `mlir-array`, and
  its reliance on `Data.Fin.natToFinLT` being the identity.
- C22: `IdrisMLIR.MLIR.Dim`, emission's entry point called by
  `Frontend/Program.idr`, and the list of modules emission adds.

## Outputs

- C20: the frontend's recognition and request chains: `Types.idr`'s
  `Ty`, `TensorOp`, `Reduction`, `Role`, `Promise`; `Term.idr`'s new
  terms, `Con.role`, `Data.promise`, `keyText`; `Ids.idr`'s
  `InstanceKey` with `KeyPrint`; the registry entries for arrays and
  data facts; the refusal message of the rule; the module list of the
  ipkg; the list of acceptance changes. Consumers: U15 (all of it),
  U18 (messages, acceptance changes, registry tests), U13 (the shapes
  the registry expects of its library), U08 (the promise, which
  emission writes into the type).
- C21, the Idris half and the shared test vectors: `xxh3_128`, `utf8`,
  `hex16`, `contentName` in `IdrisMLIR.Ids`. Consumers: U15 (lambda and
  delay names), U18 (the test-vector test), U01 (the same vectors for
  the C++ helper).

## Implement

- **`Ids.idr`.** Add `Hash128`, `xxh3_128`, `utf8`, `hex16`,
  `contentName` (C21), a straight port of
  `L/lib/Support/xxhash.cpp:480-956` with its helpers (the 192-byte
  secret, `mult64to128` by 32-bit halves, the four length classes and
  the long hash). Add `KeyPrint` and `InstanceKey.print`. Keep the
  `Shown` discipline.
- **`Translate/Keys.idr`.** `render` becomes `renderKey`, returning
  `(String, Bool)` by the loss list above; `argumentText` returns both.
  Add `identityText` (C20). `instanceKey` computes the key, its print
  and loss, the symbol (`keyText`), interns it in `TS.symbols` with the
  arguments (an existing symbol with other arguments is
  `internal`), and returns the symbol as the identity.
- **`Translate/State.idr`.** `PKind` gains `FormParam ClosedTerm`;
  `staticOf`, `runtimeBinder` cover it. Delete `perName`. Add
  `symbols`. `Decl` gains `promise`; `nextPass` keeps `symbols` and
  `named` as it keeps `blockNames` (both are functions of the
  definitions). `TyConFacts` unchanged.
- **`Translate/Instances.idr`.** `request` calls `checkRecursion` for
  the loop verdicts, then `chainGrows`, the rule, with C20's `size` and
  message; `growing` and the budget go. `classify` gains the form case:
  an erased, non-type-like parameter whose type is the shape type
  (`Recognized.shapeType`, by `conforms`) and which the rest of the type
  needs at a value array's shape position (`Shapes.formNeeded`) is a
  `FormParam` of the argument's form (`Shapes.shapeForm` of its normal
  form); no known form is `unsupported (polymorphism)`, "a shape whose
  rank no analysis fixes". `givenArgs` covers it.
- **`Translate/Recursion.idr`.** `checkComponent` records verdicts only;
  delete `staticPositions`, `same` and the refusal.
- **`Translate/Shapes.idr` (new).** `shapeSpine`, `extentDim`,
  `shapeForm`, `formNeeded`, `shapeDims`, and the ties:
  `entryTies`, `resultTies` (C20).
- **`Translate/Types.idr`.** `coreType`: an `OrderedArrayType` is a
  `MemRefT`; an `ArrayValueType` is a `TensorT` of `shapeDims` of its
  shape followed by its element's dimensions when the element is a
  tensor (an ordered array of tensors and a tensor of memrefs are
  `ValueType` refusals); a `FunT`'s binder and result and a `LazyT`'s
  value go through `dynamicDims`. `dataOf` excludes both array kinds.
  `outsideIndices` and `eraseIndices` treat a value array's shape as an
  index. `dataInstance` fills `Decl.promise` from `Promises`; the
  constructor walk fills `Con.role` from `Plays`. A value array's
  constructor matched or applied is a `HookShape` refusal naming it
  opaque (Cases and Terms).
- **`Translate/Terms.idr`.** `application`: the identity hook goes
  through `finish` at every arity; `Generating` hooks dispatch to
  `generating`, which builds C20's terms by the table in C20, each
  runtime argument `Let`-bound once in order; delete `loopTerm`,
  `arrayLoop`, `arraySize`, the `ArraySize` branch; `arrayElement`
  reads `MemRefT`. `call` ties the result (`resultTies`). The exit's
  world lambda is at `noLoc`, named `world`.
- **`Translate/Programs.idr`.** The root is at `noLoc` with its binder
  named `world`; entry ties wrap the body (`entryTies`), one `Let`
  named `tied` per tied parameter, in parameter order; `assemble`
  carries `promise` into `Data`.
- **`Translate/Closed.idr`.** `normaliseKeeping` under an `Env`;
  delete `heldMarker`.
- **`Translate/Hooks.idr`.** Delete `arrayElementOf`, `arrayLoopOf`; add
  `orderedArrayOf`, `isValueArray`, `generatingOf`, `roleOf`,
  `promiseOf`.
- **`Types.idr`.** As C20: `Ty`, `TensorOp`, `Reduction`, `Role`,
  `Promise`, `dynamicDims`, `tensorDims`; delete `Rank`, `dimensions`,
  `IndexBelow`; `ArrayLength`'s operand is `MemRefT [Dynamic] e`.
- **`Term.idr`.** As C20: `Tensor`, `Tabulate`, `TabulateIO`, `Reduce`, `Tie` in
  `Term`, `TermF`, `rename`, `hmap`, `para`, the printer; `Con.role`,
  `Data.promise`; `keyText` the symbol; the module comment says
  emission writes closures in symbol form.
- **`Registry/Entry.idr`.** `Hook`: `OrderedArrayType (List Dim) (Maybe
  Ty)`, `ArrayValueType`, `Generating ArrayPrim`, `Plays Role`,
  `Promises Promise`; delete `ArrayType`, `ArraySize`, `ArrayLoop`;
  `kind` covers each. `ArrayPrim` as C20.
- **`Registry/Primitives.idr`.** `ArrayData` and `Buffer` entries are
  `OrderedArrayType [Dynamic]`, `Mut` is `OrderedArrayType []`; delete
  the two Scheme-spec entries.
- **`Registry/Recognized.idr`.** Delete the index-space entries; add
  C20's array-language and data-fact entries and `shapeType`.
- **`Registry/Libraries.idr`.** Delete the `BreakLast` purpose, its
  column, its row cells and its doc; `moduleOrigin (Installed
  "mlir-array")` is `Library InHouse`.
- **`Registry.idr`.** Delete the test hook; export `shapeType`.
- **`Frontend/Resolve.idr`, `Program.idr`, `Driver.idr`.** Validation
  without a broken entry; `program` without the option; emission
  through C22.
- **`Frontend/Profile.idr`.** `answersForBody` also covers `Generating`.
- **`Errors.idr`.** `reject` renders the rule's phrase from C04's
  module.
- **The ipkg.** As C20's module list.

Failure paths: a registry entry whose definition does not have C20's
shape stops the compilation with the validation message, as today; a
symbol interned twice for two identities, a tensor of memrefs reaching
emission, a generating call whose operand is not of the expected `Ty`
are `internal` errors; a shape with no known spine and a rule refusal
are `unsupported (polymorphism)`.

## Delete

- `Instances.idr`: `instanceBudget`, its `compile-time budget`
  refusal and the `CompileBudget` use, `perName`, `growing` as a check
  of its own.
- `Recursion.idr`: `checkComponent`'s blanket refusal, `staticPositions`,
  `same`.
- `Frontend/Translate/Prof.idr` and its ipkg line.
- The `$world` binder name (`Programs.idr:183-194`, `Terms.idr:769`)
  and the hole sentinel's rename (`heldMarker`, `Closed.idr:473-476,
  499-506`).
- The frontend's half of `--break-shape`: `Driver.idr`'s option,
  `breakShape` field and synopsis; `Program.idr`'s parameter and
  `NoSuchEntry` message; `Resolve.idr`'s `NoSuchEntry` and its
  argument; `Registry.idr`'s `breaking`.
- `Libraries.idr`: the `BreakLast` purpose and column.
- `Types.idr`: `Rank`, `dimensions`, `ArrayT`, `IndexBelow`.
- `Term.idr`: `Region`, `RegionF`, `regionName`.
- `Registry/Entry.idr`: `ArrayType`, `ArraySize`, `ArrayLoop`.
- `Registry/Primitives.idr`: the `prim__arraySize` and `prim__index`
  entries keyed by the Scheme specs of the in-house `Linear.Array`.
- `Registry/Recognized.idr`: `indexSpace`, `indexSpaces`.
- `Translate/Hooks.idr`: `arrayElementOf`, `arrayLoopOf`.
- `Translate/Terms.idr`: `loopTerm`, `arrayLoop`, `arraySize`.
- `Emit/Index.idr`'s repeat counter is U15's to delete; this lane
  removes the need for it.

## NOT TO DO

- No edit to `Emit.idr`, `Emit/`, `MLIR.idr`, `MLIR/` (U15),
  `Rule.idr`, `Dialect/`, `Syntax/` (U01), `libs/` (U13), `tests/`
  (U17, U18) or any C++ file. A line you need there is a seam you
  report.
- No count, budget, fuel or depth limit that refuses a program; the
  `64` fuel of `whnf`, `implementationOf` and `cutRuntime` bounds
  reduction, refuses nothing and stays.
- No `linalg`, `bufferization` or `affine` term, no loop op of ours, no
  `scf.parallel` (a finite semiring's fold is 0003's stage 4), no
  constant tensor (stage 2's constants), no `idr.scan` or
  `idr.scatter` (the structuring's).
- No guard on a typed access, and no guard removed from a world-ordered
  one.
- No new option, environment variable or behaviour toggle; no fallback
  to the old array path; no compile-time comparison against Chez.
- No `idr-isolate`-shaped regions: closures stay `Lam` and `Suspend`
  in Core; their symbol form is U15's.
- Do not touch the fork (`compiler/idris`) or `third_party/Idris2`.

## Tempting partial solutions

- **Keeping `instanceBudget` as a "safety net" beside the rule.**
  Rejected: a count would still decide acceptance (D40). Acceptance
  case: no `CompileBudget` or budget constant remains in `Frontend/`.
- **Keeping `checkComponent`'s refusal and adding the rule after it.**
  Rejected: bounded polymorphic recursion stays refused. Acceptance
  case: a `Functor`-style method recursing at a finite set of types
  compiles (U18's fixture).
- **A hash over every key whose print repeats another, or a widened
  name on collision.** Rejected by 0009 §4.10 and 0007 §4.5: one key's
  symbol would depend on another key. Acceptance case: the symbol is a
  function of the key alone; editing one definition changes no other
  symbol (U18's name-stability fixture).
- **Suffixing every symbol with its hash.** Rejected: unreadable, and
  0009 decides the suffix only where the print loses identity.
  Acceptance case: a key with no loss prints bare.
- **Renaming `$world` to another reserved name.** Rejected: a name chosen
  to dodge a collision is the sentinel again. Acceptance case: the
  generated binder is named `world` and located at the generated
  location.
- **Guessing the list's cons or a shape's snoc by field count.**
  Rejected: `listElement`'s defect. Acceptance case: the roles come from
  registry entries and the snoc from C19's tag order.
- **Making every erased `SnocList Nat` argument a form parameter.**
  Rejected: a recursion over an erased snoc-list index that no array
  needs would become a refusal. Acceptance case: a form parameter is
  made only where a value array's shape needs it.
- **Reading a generating call's ranks from the order of its implicits.**
  Rejected: Idris's auto-binding order is not C19's contract. Acceptance
  case: ranks come from the operands' and result's `Ty`.
- **Emitting `tensor.cast` from the frontend.** Rejected: the cast is a
  fact of two types at a slot, which emission sees (C20 assigns it to
  U15). Acceptance case: no cast term exists in `Term`.

## Acceptance

- A search of the lane's files for every name `## Delete` lists finds
  none, and the deleted module neither exists nor is named by the ipkg.
- The private-build-dir typecheck of `compiler/idris-mlir.ipkg` passes
  for every module this lane owns; a failure inside U15's or U01's
  modules against an unwritten contract is reported as a seam with the
  file and the missing declaration.
- On the owner's machine (listed for the handoff, not run here):
  `tests/reject/polymorphism-growing-shape` still refused with its
  message; `polymorphism-nested` refused at its recursive call; U18's
  XXH3 test passes C21's vectors; every array program of
  `tests/programs/arrays` keeps its expected output; the corpus emits.
- Every number written cites its authority (C20's size measure is
  0012 D4's; the 16 hex digits and 64 bits are D18's).

## Stop and return

Done when every Mandatory item is in the source, the deletions are
complete, and the private typecheck of the lane's modules passes or
fails only on a seam. Return the common obligations' handoff, with
every seam named by file, missing declaration and contract (C04's
module name, C19's signatures, C22's `Dim` and entry point and module
list are the likely ones), then stop. A shape in C19 that differs from
C20's registry entry is reported, and the entry is written to C19.
