# U19 — Translate: saturated method calls, arity, newtypes, alpha-normalized keys, case blocks by position

Mandatory findings: F-hand-3 F-hand-6 F-hand-7

## Permitted outcome

1. **Every instance carries its key.** `request` and `dataInstance`
   build an `InstanceKey` (C1.6) for each function and data instance:
   the definition's name with case, with and nested blocks named by
   position, and its compile-time arguments as alpha-normal text. The
   key fills `key` on the function and data records of `CS/Term.idr`.
   `FnId` and `DataId` become opaque identities; nothing prints them.
   Mandatory.
2. **No newtype.** A data instance with one constructor and exactly one
   runtime field is not registered as a declaration: `coreType` gives
   the field's type, its constructor translates to its argument, and a
   match on it binds the field to the scrutinee. Decided in
   `dataInstance`, per instance. Mandatory.
3. **Saturated method calls.** A call of a projection (an interface
   method, a parent) whose projected argument is a compile-time
   implementation is translated as the implementation's field applied to
   the call's remaining arguments, in place: the method function is
   called at its syntactic arity and no instance of the projection is
   requested. A visible beta redex becomes a `let`. Mandatory.
4. **No quantity zero in Core.** Translate builds no erased binder, no
   erased argument and no erased term: an erased parameter, field,
   lambda binder or `let` is a compile-time value of the environment,
   an argument at an erased position is not translated, and a type or
   an erased value met where a runtime value is expected is rejected
   with `unsupported (type)` naming the term and its head. Mandatory.
5. **Arity.** A call with as many arguments as the definition's
   syntactic arity is one `Call`; fewer eta-expand over the missing
   runtime parameters at the call site; more apply the result, skipping
   the erased binders of the result's type. Mandatory.
6. **Consumer adaptations.** `Resolve.binderOf` loses its erased case;
   `Profile.enclosing` reads the root of a block from the one place
   that computes it (`Keys.rootOf`). Mandatory.

The `Delay` item of F-hand-6 is confirmed at its site and reported, not
changed: see Fixed decisions and Escalate if.

## Owner / exclusive writes

- `CS/Frontend/Translate` (every module under it), new file
  `CS/Frontend/Translate/Keys.idr`.
- `CS/Frontend/Translate.idr` (unchanged unless `Keys` is re-exported;
  it need not be).
- `CS/Frontend/Resolve.idr` (`binderOf`).
- `CS/Frontend/Profile.idr` (`enclosing`).
- `CS/Frontend/Program.idr`, `CS/Frontend/Driver.idr`: owned, unchanged.
- `CS/Registry`, `CS/Registry.idr`: owned, unchanged. No hook changes.

**Excluded:**

- `CS/Ids.idr` (`InstanceKey`, `InstanceArg`, `FnId`, `DataId`) and
  `CS/Rule.idr`: the coordinator's (C1.6). Consume `MkInstanceKey`,
  `TypeArg`, `ImplArg`, `ShapeArg` by name.
- `CS/Term.idr`, `CS/Types.idr`, `CS/Loc.idr`, `CS/Emit*`, `CS/MLIR*`:
  U18's. U18 removes the erased type, the erased binder, the erased
  term and the erased value from them and adds `key`; this lane
  consumes those removals and fills `key`.
- `compiler/idris-mlir.ipkg`: the coordinator's. The one line this lane
  needs is under Outputs.
- `compiler/idris` (the fork): not touched. What it prints for a name
  (`Core/Name.idr:249-252`) and how it names case blocks
  (`Core/UnifyState.idr:192-198`) is read, not changed.
- `T/*`: U22's. The five `translate.check` fixtures and the `covers`
  checks read the Core dump; the seam is reported, not fixed here.
- `INC/IR/IdrOps.td` (`Idr_InstanceAttr`): the coordinator's.

## Read first

- `contracts.md` C0, C1.2 (`Idr_InstanceAttr`, `Idr_CtorOp`'s
  `field_names`), C1.6, C2.3, C6.1 to C6.6, C7.2, C10, C11.
- `findings.md` F-hand-1, F-hand-3, F-hand-6; F-hand-2 and F-hand-5
  for what U10 and U18 do with the names and locations this lane hands
  them.
- `bugs/idris-mlir-handoff-investigation.md` §3.2 (newtypes, :127-135),
  §3.3 (method shims, :137-153), §3.4 (currying, :155-161), §3.6
  (binder names in keys, :178-187), §3.7 (delays, :189-202), §3.8
  (:204-211), §5 (the target shape, :297-362). Observed in a dump; the
  Translate site of each is named below.
- `HANDOFF.md` "Self-hosting" (:20-52): the stage-0 dump is 58,305
  functions and 7,664 data types; the 702-program corpus is the
  behaviour oracle.
- `proposals/0004-self-host-features.md` (the middle way: every
  construct whose set the whole program bounds is compiled away; a
  runtime choice is refused, never boxed).
- The lane's files, all of them, with these ranges first:
  - `CS/Frontend/Translate/Types.idr`: `nameKey` :46-55,
    `instanceName` :57-90 (the hash bucket `named`, the collision
    suffix `owners`), `paramLayout` :104-122, `typeParams` :206-254,
    `tyConFacts` :289-299, `coreType` :451-494 (the Pi case :467-473
    builds a binder for an erased argument; :476-491 the type
    constructor case; :492-494 the rejections), `dataInstance`
    :496-529 (`building` :516, the registration :521-528), `walk`
    :533-549 (an erased or dictionary field is a `Gone` binder),
    `constructor` :551-572 (`MkConLayout`).
  - `CS/Frontend/Translate/Instances.idr`: `request` :96-113,
    `classify` :201-288 (type :208-214, erased :215-218, implementation
    :219-250, runtime :251-283), `shapes` :52-57, `growing` :65-89.
  - `CS/Frontend/Translate/State.idr`: `PKind` :41-42, `runtimeBinder`
    :45-49, `staticOf` :52-56, `Request` :61-67, `Pending` :96-103,
    `ConLayout` :105-118, `Decl` :136-142, `TS` :154-219 (`owners`
    :173-175, `named` :176-178), `nextPass` :231-235.
  - `CS/Frontend/Translate/Terms.idr`: `etaExpand` :68-77, `term`
    :125-181 (a compile-time variable :133, a primitive type :151, a
    type :153-155, an erased `let` :163-164, a lambda :166-170, a
    `Lazy` type :173), `suspend` :183-188, `application` :190-247 (the
    hooks :206-223, a type constructor :225), `arguments` :448-471
    (an erased argument :471), `finish` :486-499, `call` :501-506,
    `constructor` :606-635, the fallback :821-868 (`headType`,
    `applyTyped` :839-843, `headStep` :854-864).
  - `CS/Frontend/Translate/Cases.idr`: `fieldInfos` :33-34, `bindEquated`
    :283-325 (the erased-variable predicates :287-294), `forcedEnv`
    :334-366 (:341), `tree` :372-453 (the dispatch on the scrutinee's
    Core type :390-417), `staticCase` :519-545, `conAlternatives`
    :551-592 (the field environment :573-582).
  - `CS/Frontend/Translate/Closed.idr`: `VarInfo` :43-53, `closeWritten`
    :145-159 (:158), `projection` :271-284, `whnf` :295-328,
    `projected` :330-347, `implementationOf` :356-366, `shaped`
    :411-413, `closeNormalise` :732-746 (:745).
  - `CS/Frontend/Translate/Programs.idr`: `translateInstance` :36-71,
    `assemble` :115-128, `translateIOProgram` :138-170.
  - `CS/Frontend/Translate/Dictionaries.idr` :126-163;
    `CS/Frontend/Resolve.idr` :165-168; `CS/Frontend/Profile.idr`
    :79-87.
- U18's records this lane fills: `CS/Term.idr` :77-131 (`Term`, `Alt`),
  :309-357 (`Con`, `Data`, `TFn`, `Source`); `CS/Types.idr` :116-132
  (`Ty`, `Binder`, `typeOf`); `CS/Ids.idr` :7-24.
- The fork, read only: `compiler/idris/src/Core/TT/Term.idr` :505-525
  (`eqTerm` ignores binder names) and :573-611 (`show` prints them);
  `Core/Hash.idr` :140-170 (binder names are not hashed);
  `Core/Name.idr` :43-44, :249-252 (`CaseBlock`, `WithBlock`, `Nested`
  print a counter or a resolved index); `Core/UnifyState.idr` :192-198
  (`genCaseName`: a global counter); `TTImp/Elab/Case.idr` :169 and
  `TTImp/ProcessDef.idr` :512 (the root string is `prettyName` of the
  defining function); `Core/Context.idr` :1522-1534 (`prettyName`);
  `Core/TTC.idr` :361, :370 (a `let`'s type is not kept);
  `Idris/Elab/Implementation.idr` :362-370 (a record's method field is
  an eta-expansion over every argument of the method, erased ones
  included) and :374-380 (`methName` is a `DN`).
- The dialect's lazy producers, read only: `INC/IR/IdrOps.td`
  `Idr_SuspendOp` :816-829 and `Idr_DelayOp` :846-855 both build a
  cell; `Idr_LazyValue` :256; `Idr_FnType` :141-160 (`(A...) -> R`).
- Where the Core dump is read by tests: `T/lib/e2e.sh` :164-172
  (`translate.check` on the `.core`), `T/lib/prelude.sh` :1-14
  (`covers` reads full names from the `.core`), and the five
  `translate.check` files (`find tests -name translate.check`).

## Fixed decisions

### What each site of F-hand-6 is, in the code

- **Newtypes (§3.2).** Confirmed. `dataInstance` registers every data
  type with constructors (Types.idr:516-528); nothing counts runtime
  fields. `Core`, `IO` (`MkIO`'s one field `1 fn`), `ST`, `Namespace`
  and `SizeOf` (one runtime field, one erased) are therefore declared
  and matched.
- **Method shims (§3.3).** Confirmed, and the mechanism is three sites.
  `call` (Terms.idr:501-506) requests an instance of the method
  projection with the implementation as a `DictParam`. That instance's
  body is `staticCase` (Cases.idr:519-545) selecting the record's
  field, then `term` on the field (Terms.idr:134, then :166-170), which
  is the eta-expansion Idris writes for a method field
  (`Implementation.idr:362-370`): one `Lam` per binder, erased ones as
  `Gone`. The caller applies the extra arguments one by one
  (Terms.idr:491, :249-251). The dump's "shim returning a curried
  lambda" is exactly this.
- **Currying (§3.4).** Confirmed. `finish` applies extra arguments with
  `applyAll` (:491) and eta-expands with nested unary `Lam`s (:68-77).
  "A lambda applied to its own argument right away" is the fallback of
  `application` (:821-826) on a `Bind Lam` head with a runtime argument:
  `headStep` (:861-863) substitutes only erased, static or dictionary
  arguments, so the lambda is translated and applied.
- **Binder names in keys (§3.6).** Refuted as a duplication, confirmed
  as a printing bug. `instanceName` finds an existing instance by
  `eqTerm` on the arguments after bucketing by `hash` (Types.idr:69-78);
  neither compares nor hashes a binder's name (`Core/TT/Term.idr:510-
  511`, `Core/Hash.idr:166`), so two alpha-equivalent argument lists are
  one instance. Only the printed name (`showTT`, :80-81) carries
  `{arg:NNNN}`, because Idris's `show` prints every Pi binder
  (`Core/TT/Term.idr:589-591`). The fix is the key's text, not the
  identity.
- **Delays (§3.7).** Confirmed at `suspend` (Terms.idr:183-188): every
  `TDelay` becomes a `Suspend`, a variable or literal body included. Not
  changed by this lane: the dialect's only lazy producers, `idr.delay`
  and `idr.suspend`, both build a cell (IdrOps.td:816-855), and a
  `Lazy`-typed parameter of a shared callee must receive one. Dropping
  the `Suspend` changes the argument's type. Reported under Escalate
  if; `suspend` stays as it is.
- **Case blocks named by a counter (§3.11).** Confirmed. `nameKey`
  (Types.idr:53-54) prints `case block <i> in <outer>`; `i` is
  `genCaseName`'s global counter (`UnifyState.idr:192-198`). `Nested`
  names print two resolved indices (`Name.idr:249-250`) and `WithBlock`
  the same counter: the same mechanism names all three.

### The key (C1.6, C6.3)

- **One builder.** `Keys.instanceKey : Name -> List (Maybe Keyed) ->
  Core (String, InstanceKey)` in the new `CS/Frontend/Translate/Keys.idr`
  returns the opaque identity and the key. `Keyed` is in `State.idr`:

  ```idris
  ||| A compile-time argument as the key records it: a type, an
  ||| implementation, or the shape of a runtime argument.
  public export
  data Keyed = KeyType ClosedTerm | KeyImpl ClosedTerm | KeyShape ClosedTerm
  ```

  `staticOf : PKind -> Maybe Keyed` (State.idr:52-56) gives `KeyType`
  for a `TypeParam`, `KeyImpl` for a `DictParam`'s key, `KeyShape` for
  a `ValueParam`'s shape. `instanceKey` maps them to `TypeArg`,
  `ImplArg`, `ShapeArg` with the text below. `request` calls it with
  `map staticOf kinds`; `dataInstance` with `Just (KeyType t)` for each
  kept type parameter and `Nothing` elsewhere.
- **Identity.** `FnId.name` and `DataId.name` are
  `nameKey origin ++ "#" ++ show (hash args) ++ "#" ++ show k`, `k` the
  index of the argument list in its bucket (`TS.named`, which stays as
  it is). The bucket's equality is `eqTerm`, alpha-equivalence. Nothing
  prints an identity: Emit derives the symbol from `key`, with the
  `'n` suffix for two keys that print alike (C6.3). `TS.owners` and
  `suffixed` go.
- **Origin.** `Keys.originOf : Name -> Core String`, on the full name:
  Idris's `show`, except that a `DN` prints its inner name
  (`Prelude.Types.map_Functor_Maybe`, not `Prelude.Types.map`, which
  every implementation in a module would share), and a `CaseBlock`,
  `WithBlock` or `Nested` prints as its parent's origin, a dot, and
  `case<k>`, `with<k>` or the nested name, `k` counting that kind in
  the parent from 0 in the order the parent's definition first refers
  to it.
- **Positions.** `Keys.blockNames` walks a root definition's `treeCT`
  once, depth first: alternatives in order, a leaf's term left to
  right (function before argument, a binder's type and value before its
  scope), a solved metavariable through its solution. Each reference to
  a `CaseBlock`, `WithBlock` or `Nested` name not yet named gets the next
  number of its kind under the referencing definition, then its own
  tree is walked under its new name. The result is kept in
  `TS.blockNames : SortedMap String String` by `nameKey`. `originOf`
  of a block looks it up; when absent, it walks the block's root
  (`Keys.rootOf`, today's `Profile.enclosing` strip of the
  `outer` string, Profile.idr:79-87, moved here and exported) and looks
  again; still absent is `internal`. Two compilations of one program
  give one name, and the name does not change when a library is
  rebuilt with another counter.
- **Text.** `Keys.keyText : ClosedTerm -> Core String` prints a term
  after `toFullNames`, alpha-normally: a `Local` prints the canonical
  name of its binder, `x<d>` where `d` is the binder's depth from the
  outside; a Pi whose binder the scope does not mention prints
  `a -> b`, with Idris's quantity prefix (`0 `, `1 `) and brace or
  double-brace for an implicit or auto binder; one it mentions prints
  `(x<d> : a) -> b` the same way; a lambda prints `\x<d> => b`;
  `Erased` prints `_`; `TType` prints `Type`; an application prints
  the head and its arguments separated by spaces, an applied argument
  in parentheses; `TDelayed` prints `Lazy t`; a primitive value prints
  as Idris prints it; a metavariable prints `?` and its name. No
  binder's name and no counter reaches the text. `showTT` stays for
  messages.
- **A data key** has the type constructor's origin and one `TypeArg`
  per kept type parameter (`tyConFacts.typeParams`), in order, after
  `canonicalTypeArg` and `eraseIndices` as today (Types.idr:508-511).
- **The root** (`$idris-mlir.root`, Programs.idr:164) has the key
  `MkInstanceKey rootId.name []`.
- `TypeArg`'s field is the text. C1.6 declares it `Ty`; see Escalate if.

### Newtypes (C6.2)

- **The decision is `dataInstance`'s**, per instance, after it has
  walked the constructors: one constructor, and its arguments hold
  exactly one `Field` (below), and the instance was not re-entered
  while it was being built. Re-entry is recorded: when `dataInstance`
  meets an instance in `building` (Types.idr:516) it adds it to
  `TS.reentered : SortedSet DataId` and gives `DataT inst`. A
  re-entered instance is declared, whatever its shape, so a type that
  contains itself through its one field (`data Rose = MkRose (List
  Rose)`) stays a box as today.
- **`dataInstance` returns `(DataId, Ty)`:** the id, and the type a
  value has, `DataT inst` for a declaration, the field's type for a
  newtype. The newtype's type is kept in `TS.newtypes : SortedMap
  DataId Ty`, so a second request answers from it; no `Decl` enters
  `datas` or `dataOrder` for it. `coreType` uses the `Ty`
  (Types.idr:491). The constructor's `ConLayout` is registered as for
  any constructor, so matches and constructions find it.
- **Construction** (Terms.idr:606-635): for a newtype,
  `recordDictionary` runs for its dictionary fields as today, then the
  term is the one runtime argument (`finish` with `mk = \[v] => v`; any
  other arity is `internal`).
- **A match** (Cases.idr:384-417): the dispatch no longer reads the
  scrutinee's Core type to find its data instance, since a newtype
  value has its field's type. It reads the alternatives: a `ConCase`
  names a constructor, whose type constructor at the scrutinee's Idris
  type (`VarInfo`, below) names the instance through `dataInstance`;
  then `natLike` goes to `natCase`, a newtype to `newtypeCase`, a
  declaration to `conAlternatives` with that instance, as today; no
  `ConCase` goes to `literals`; the world and the erased cases stay
  first. `newtypeCase` is `staticCase`'s shape (Cases.idr:534-545):
  one `ConCase` whose argument environment is the constructor's
  `args` with the one `Field` bound to the scrutinee's own variable
  (`Runtime i`, or `shaped` with the shape's argument), parameters and
  erased arguments `TypeValue`, dictionary fields `Static` from
  `dictionaryOf`; the alternative's tree is translated in that
  environment with `alternativeTypes` and `underKnown` as today; a
  `DefaultCase` is translated when no `ConCase` is present; nothing is
  built. No `Case` term exists for a newtype.
- **The field's quantity** is the holder's: once the constructor is the
  identity, a value held at ω is used at ω. `IO`'s `1 fn` is the one
  case in base; its uses remain linear where the holder is.
- **`translateIOProgram`** (Programs.idr:138-170): `main`'s Core result
  is `FunT (Held _ WorldT) res@(DataT _)` (the newtype gone); anything
  else is `notIO`. The root body is
  `App loc (Call loc inst Nothing []) (Var loc FZ)`; the `Let` and the
  `Case` on `MkIO` go.

### No quantity zero (C6.1)

- **`PKind`** (State.idr:42):

  ```idris
  data PKind = TypeParam ClosedTerm
             | DictParam ClosedTerm (Maybe Holes)
             | ErasedParam
             | ValueParam Binder (Maybe ClosedTerm) ClosedTerm
  ```

  `ErasedParam` replaces `ValueParam Gone Nothing`
  (Instances.idr:215-218). `ValueParam`'s last field is the parameter's
  closed normalised Idris type (`classify`'s `a'`, :207). Kinds stay
  positional, one per parameter of the definition's type, since the
  case tree's scope has one variable per parameter. `runtimeBinder :
  PKind -> Maybe Binder` (State.idr:45-49): `Just` for a `ValueParam`
  and a holed `DictParam`, `Nothing` otherwise. `shapes`
  (Instances.idr:52-57) gives a hole for `ErasedParam`.
- **`VarInfo`** (Closed.idr:43-53):

  ```idris
  data VarInfo : Type -> Type where
    Runtime : a -> Maybe Ty -> Maybe ClosedTerm -> VarInfo a
    Shaped : a -> Ty -> ClosedTerm -> ClosedTerm -> VarInfo a
    TypeValue : ClosedTerm -> VarInfo a
    Static : ClosedTerm -> Maybe (a, Holes) -> VarInfo a
  ```

  A runtime variable carries its closed Idris type where it is known: a
  parameter's from `ValueParam`, a lambda binder's from
  `closeNormalise` (Terms.idr:168, computed already), a constructor
  field's from `ConLayout.args`, a `Nat` predecessor's from the
  scrutinee, the held values' from `Holes.types`. A `let` carries
  `valueType` of its value (TTC keeps no `let` type): the Pi telescope
  of a lambda chain's binders ending in `Erased`, or the callee's type
  after the applied arguments when the value's head is a `Ref` (the
  type arguments substituted as written, a runtime argument as
  `Erased`), or a `Local`'s own type, or `Nothing`. `Shaped` carries
  the Idris type before the shape. An erased binder of any kind is
  `TypeValue (Erased fc Placeholder)`, which is the value
  `closeWritten` gave the erased type today (Closed.idr:158, :745).
- **Every translation site that produced an erased value changes:**
  - a lambda with an erased binder (Terms.idr:166-170) translates its
    body with the binder `TypeValue (Erased fc Placeholder)`, no `Lam`;
  - an erased `let` (:163-164) translates its body with the binder
    `TypeValue (Erased fc Placeholder)`, no `Let`;
  - `arguments` (:448-471) gives one term per runtime kind, nothing for
    a compile-time or erased kind;
  - `etaExpand` (:68-77) takes the missing runtime binders only;
  - `coreType`'s Pi case (Types.idr:467-473) skips an erased binder:
    `coreType (Pi 0 a sc)` is `coreType` of `sc` with `Erased`
    substituted, and `Resolve.binderOf` is called only for a runtime
    binder (its erased case goes);
  - `walk` (Types.idr:533-549) gives `ArgKind`s, below, and `Con.fields`
    holds the runtime fields only;
  - `translateInstance` (Programs.idr:36-71) numbers the runtime
    parameters: the environment maps each `ValueParam` and holed
    `DictParam` to the next `Fin`, every other kind to `TypeValue` or
    `Static` with no variable; `arity` is their count and `params` their
    binders;
  - `fieldInfos` (Cases.idr:33-34) and `arrange` (Types.idr:368-375)
    become one `argInfos : List ArgKind -> ... -> List (VarInfo (Fin
    (Under k nv)))`, `k` the runtime fields;
  - `applyTyped` (Terms.idr:839-843) walks the head's Idris type
    (`headType`: the `VarInfo`'s, through `TForce` and `TDelayed`): an
    argument at an erased binder is not translated and not passed; at
    any other binder, and past the binders the type shows, it is
    translated with `term`;
  - the extra arguments of a call (`finish`, :491) are applied the same
    way over the callee's result type, which `classify` already returns
    (:204) and every caller of `finish` now passes.
- **What `term` does with a type or an erased term** (Terms.idr:133,
  :151, :153-155, :173, :225): `reject fc owner ValueType` with the
  message `<term> in a runtime position: an argument of <head>, whose
  type is not known here` where a head is known, else `<term> in a
  runtime position`. `ValueType` is the rule `coreType` already uses
  for `Type in a runtime position` (Types.idr:492); no rule is added to
  `CS/Rule.idr`. A compile-time variable met there (`TypeValue`,
  :133) is `internal`: Idris's quantity check keeps one out of a runtime
  position, so reaching one is this compiler's bug.
- **`ArgKind`** (State.idr, replacing `ConLayout.layout`, `params`,
  `dicts`):

  ```idris
  ||| One argument of a constructor, as the instance has it.
  data ArgKind = Param ClosedTerm        -- the data type's parameter: its value
               | ErasedArg               -- quantity 0: no field
               | DictArg ClosedTerm      -- an implementation: a compile-time field
               | Field Nat Ty ClosedTerm -- runtime field i, its Core and Idris types
  record ConLayout where
    args : List ArgKind
    con : Con
  ```

  `Field`'s index counts the runtime fields from 0 and is the
  alternative's `Bound i`. `recordDictionary` and `dictionaryOf` keep
  their `(ConId, Nat)` key with `i` the position among all arguments.

### Methods and arity (C6.4)

- **`resolveMethod`** in `Terms.idr`, inside `call` after `classify`
  and before `request`: when `projection name` (Closed.idr:276-284)
  gives `(arity, idx, _, _)`, the call has at least `arity` arguments,
  and `kinds` at `idx` is `DictParam t holes`:
  - `holes = Nothing`: `projected 64 name` on the first `arity`
    arguments as compile-time terms (`staticOf` where there is one,
    `Erased` for an erased parameter) gives the record's field; the
    call is `application ctx env afc (embedClosed field) (drop arity
    xs)`. `Nothing` from `projected` falls through to `request`, so a
    projection that does not reduce keeps today's instance and
    `staticCase`'s rejection.
  - `holes = Just _`: `holed` on the argument at `idx` gives the
    implementation's shape with markers, the values' types and their
    translations; `projected` on the shape gives the field; each value
    is bound by a `Let` in Core and by a fresh `MN "idris-mlir-held" i`
    in the TT scope, bound to that `Let`'s variable (as the one held
    value is bound today, Terms.idr:138-141), the markers replaced by
    those names (`fillHoles`), and the field applied to the remaining
    arguments is translated under them.
  - The field is Idris's eta-expansion over the method's binders
    (`Implementation.idr:362-370`): `headStep` substitutes the erased
    and dictionary binders, and the runtime binders meet their arguments
    as below. The method function is then called through `call` at its
    own syntactic arity: one `Call`, no instance of the projection.
    `fst` on a runtime pair, and any projection whose projected
    argument is a `ValueParam`, keep today's path.
- **A visible beta redex.** `headStep` (Terms.idr:854-864) also
  substitutes a lambda's argument when the argument is a `Local`, and
  replaces a metavariable head by its solution applied (as `walk`
  does, :333-336). For any other argument of a `Bind Lam` head,
  `application` rewrites `App (\x => b) e` to Idris's `Bind fc x (Let
  fc rig e ty) b` applied to the rest, and `term`'s `Let` case
  translates it (:156-165). No `App` of a `Lam` is built.
- **Arity.** `call` keeps `length params` of the `PMDef` as the arity
  (Terms.idr:223): the syntactic arity. `finish` takes the number of
  arguments the call gave: `missing = drop given kinds`; a missing
  `TypeParam` or `DictParam` is rejected as today (:493-494); the
  missing runtime binders are eta-expanded at the call site, one `Lam`
  each, since `Lam` is unary (Term.idr:105); the extra arguments are
  applied over the result type. The dialect's `!idr.fn` is n-ary
  (IdrOps.td:141-160) and Emit writes one input per `FunT`
  (Emit/Types.idr:38): a partial application missing two parameters is
  two closures until `Lam` binds more than one; see Stop and return.
- **Delays.** `suspend` is unchanged. `delayedLets` (Closed.idr:126-139)
  stays.

### Names in messages

Every rejection keeps `showTT` and Idris's `show`: messages are not
keys. `tests/reject/*` expectations do not change.

## Inputs

- `CS/Ids.idr`: `InstanceKey`, `MkInstanceKey`, `InstanceArg`
  (`TypeArg`, `ImplArg`, `ShapeArg`), `FnId`, `DataId`, `ConId`,
  `Shown` (C1.6).
- `CS/Term.idr` and `CS/Types.idr` as U18 leaves them: a `Term` with no
  erased constructor, a `Binder` that always binds a runtime value, a
  `Ty` with no erased case, `Con.fields` the runtime fields, the
  function and data records with `key : InstanceKey`.
- `CS/Rule.idr`: `ValueType`, `StaticArgument`, `RuntimeClosure`,
  `Match`, `DataType`, `DependentField`, `CompiledModule`, as today.
- The fork's `eqTerm`, `hash`, `toFullNames`, `normaliseTypes`,
  `treeCT`, `sizeChange`, as today.

## Outputs

- Every `TFn` (or `Fn`) and `Data` with its `key`; no `Gone` binder, no
  erased term, no erased type produced anywhere under `CS/Frontend`.
- `Keys.keyText`, `Keys.originOf`, `Keys.instanceKey`, `Keys.rootOf`
  (exported; `Profile` reads `rootOf`).
- **Hub text** for `compiler/idris-mlir.ipkg`: the line
  `, IdrisMLIR.Frontend.Translate.Keys` between
  `IdrisMLIR.Frontend.Translate.Closed` and
  `IdrisMLIR.Frontend.Translate.Dictionaries`.
- **Consumers to name in the handoff:**
  - U18: the symbol and the `#idr.instance` of a function and a data
    declaration come from `key` alone; `FnId.name` and `DataId.name`
    are opaque. The Core dump (`showSource`, Term.idr:438-451) must
    print the readable form of `key` where it prints an id today,
    since `T/lib/prelude.sh` reads full names from it.
  - U22: `tests/registry/identity-hook/translate.check` and
    `tests/programs/data/sortedmap/translate.check` match `(0 Erased)`
    binders and fields that no longer exist; the `covers` checks read
    instance names from the dump; the expected `no-eval` lines are
    U22's own change.
  - The coordinator: the stage-0 function count (58,305 at
    `HANDOFF.md:25`) falls by the projection instances; record the new
    count (README Qualification).

## Implement

- **`Translate/Keys.idr` (new).** `keyText`, `originOf`, `rootOf`,
  `blockNames` and `instanceKey` as Fixed decisions say. `instanceKey`
  owns the bucket (`TS.named`): it finds an existing identity by
  `eqTerm` on the argument list, or makes the next one, and builds the
  key from the `Keyed`s with `keyText`. Imports `State`, `Closed`,
  `Errors` and the fork; nothing imports it but `Types`, `Instances`,
  `Programs` and `Profile`.
- **`State.idr`.** `Keyed`; `PKind` with `ErasedParam` and the typed
  `ValueParam`; `runtimeBinder` to `Maybe Binder`; `staticOf` to `Maybe
  Keyed`; `ArgKind` and the two-field `ConLayout`; `Pending` and
  `Request` gain `key : InstanceKey`; `Decl` gains `key`; `TS` gains
  `newtypes`, `reentered`, `blockNames` and loses `owners`;
  `initState` and `nextPass` follow (`blockNames` survives a pass, as
  `tyCons` does; `newtypes` and `reentered` do not, as `datas` does
  not).
- **`Closed.idr`.** `VarInfo` as above, `Functor`, `shaped` with the
  Idris type, `closeWritten` and `closeNormalise` with the erased-type
  case gone (`TypeValue` covers it). `projection` and `projected` are
  exported already; nothing else moves.
- **`Types.idr`.** `instanceName` goes; `dataInstance` returns
  `(DataId, Ty)`, records `reentered`, decides the newtype from the
  `ArgKind`s, and calls `Keys.instanceKey`; `walk` builds `ArgKind`s
  with each runtime field's Core and Idris types; `coreType`'s Pi case
  skips erased binders and its data case uses the returned `Ty`;
  `fieldsOnly` and `arrange` go, replaced by `argInfos` in `Cases`
  (and a `runtimeArgs : List ArgKind -> List a -> List a` for
  `constructor`'s given arguments); `nameKey` stays for the internal
  maps.
- **`Instances.idr`.** `classify` emits `ErasedParam` and the typed
  `ValueParam`; `request` calls `instanceKey`, stores the key in the
  `Pending` and the `Request`; `shapes` and `growing` read the new
  kinds.
- **`Terms.idr`.** `term`'s cases for a type, a primitive type, a
  `Lazy` type, an erased term, a type constructor and a compile-time
  variable reject or are `internal` as Fixed decisions say; the erased
  lambda and `let` bind `TypeValue`; `etaExpand`, `arguments`,
  `finish` (with the result type and the number of arguments given),
  `applyTyped` over the Idris type, `headType` through `TForce`,
  `headStep` with the `Local` and metavariable cases, the `Let`
  rewrite of a redex, `resolveMethod` in `call`, `constructor` for a
  newtype, `natConstructor` over the runtime arguments, `arrayOperands`
  without `runtimeOnly`, every caller of `finish` passing the result
  type. `valueType` for a `let`'s value.
- **`Cases.idr`.** `argInfos`; `tree`'s dispatch by alternative;
  `newtypeCase`; `conAlternatives` over `ArgKind`s; `natAlternatives`
  with the predecessor's Idris type; `bindEquated` and `forcedEnv`
  testing `TypeValue (Erased _ _)` instead of a runtime variable of the
  erased type.
- **`Programs.idr`.** `translateInstance` numbers runtime parameters,
  fills `key` from the `Pending`; `assemble` passes `Decl.key`;
  `translateIOProgram` on the newtype `IO`.
- **`Resolve.idr`.** `binderOf : RigCount -> Lazy (Core Ty) -> Core
  Binder` builds `Held (useOf rig)` only; its callers test `isErased`
  first.
- **`Profile.idr`.** `enclosing` becomes `Keys.rootOf`.
- **Unchanged:** `Dictionaries`, `Errors`, `Forced`, `Hooks`,
  `Primitives`, `Recursion`, `Translate.idr`, `Program.idr`,
  `Driver.idr`, `Registry.idr`, `Registry/*`.
- **Failure paths:** a `DictParam` missing at a partial application is
  `StaticArgument` as today; a projection that does not reduce keeps
  `RuntimeClosure`; a type where a value is expected is `ValueType`; a
  block its root does not reference, a newtype constructor given other
  than one runtime argument, a scrutinee with no Idris type whose
  alternatives name a constructor, are `internal`.

## Delete

- `instanceName`, `suffixed` and `TS.owners` (Types.idr:57-90,
  State.idr:173-175): printing moves to Emit, the bucket stays.
- `ValueParam Gone Nothing` (Instances.idr:218) and `runtimeBinder _ =
  Gone` (State.idr:49).
- `fieldsOnly`, `arrange` (Types.idr:357-375), `ConLayout.layout`,
  `ConLayout.params`, `ConLayout.dicts`, `fieldInfos` (Cases.idr:33-34),
  `runtimeOnly` (Terms.idr:755-757).
- Every construction of an erased term in `Terms.idr`: :133, :151,
  :153-155, :164, :173, :217, :225, :471, and `etaExpand`'s `argument
  Gone` (:76); `applyTyped`'s `FunT Gone` case (:841).
- The `Runtime _ (Just ErasedT)` predicates: `closeWritten`
  (Closed.idr:158), `closeNormalise` (:745), `bindEquated`
  (Cases.idr:287, :293), `forcedEnv` (:341), `tree` (:397).
- `Resolve.binderOf`'s erased case (Resolve.idr:168).
- `Profile.enclosing` (Profile.idr:79-87), moved to `Keys.rootOf`.
- The `Let` and `Case` on `MkIO` in `translateIOProgram`
  (Programs.idr:158-163).

## NOT TO DO

- Do not edit `CS/Ids.idr`, `CS/Rule.idr`, `CS/Term.idr`,
  `CS/Types.idr`, `CS/Loc.idr`, `CS/Emit*`, `CS/MLIR*`, the generated
  `CS/Dialect` and `CS/Syntax`, or `compiler/idris-mlir.ipkg`.
- Do not print a symbol, a `'n` suffix or an `#idr.instance`: Emit
  (U18) derives them from `key`.
- Do not key an instance by representation (§3.5): the key stays Idris
  types, implementations and shapes (C10). Do not merge instances.
- Do not inline `ifThenElse`, `&&` or `||`, and do not fold a match on
  a known constructor (§3.7, §3.8): not in C6.
- Do not drop a `Suspend` or change `suspend`.
- Do not change `classify`'s rejections, `Dictionaries`' restart, the
  instance budget, the shape machinery or `Recursion`.
- Do not add a `NameLoc` or a span to `Loc` (U18, C6.5). `Lam` and
  `Let` carry no binder name in `Term`; if U18 adds one, fill it from
  the Idris binder and say so in the handoff.
- Do not write a test; describe the evidence in the handoff for U22.
- Do not touch `compiler/idris` or `third_party/Idris2`.

## Stop and return

You are done when every item of Permitted outcome is in place, the
Delete list has no survivor
(`grep -rn 'Gone\|instanceName\|owners\|fieldsOnly\|runtimeOnly' compiler/src/IdrisMLIR/Frontend`
finds nothing), and every rejection message a `tests/reject`
expectation reads is unchanged.

Report, as seams, without stopping:

- the arity of `Lam` (unary): a partial application missing more than
  one parameter is a nest of closures; if U18 makes `Lam` bind several,
  `etaExpand` builds one;
- the delay of an evaluated value (Escalate if);
- the shape of `Binder` after `Gone` leaves `CS/Types.idr`; this lane
  writes `Held u t` everywhere;
- any `translate.check` or `covers` fixture whose text your change
  invalidates, by path.

Return the changed paths, the hub line, the consumer list above,
`Verification: NotRun (swarm policy)`, and the seams.

## Acceptance

- The 702-program corpus: every program prints, exits and crashes as
  before (`make test`, run by the coordinator); `tests/programs/
  interfaces/*` and `tests/programs/prelude/*` keep their
  `expected-stdout` byte for byte.
- `tests/reject/*`: every expectation unchanged; no new rule.
- `T/compiler/handoff-readable` (U22, C9.2): no symbol in the emitted
  module contains `{arg:` or `case block`; every `idr.func` has an
  `instance`. Two alpha-equivalent types in one program (`f : ((x :
  Nat) -> Nat) -> Nat` and `g : (Nat -> Nat) -> Nat`, each at `Maybe`)
  name one data instance, as today, and its key prints `Nat -> Nat`.
- For `data N = MkN Int` and `f (MkN x) = x`, the emitted module declares
  no `idr.data` for `N`, `f` takes an `i64`, and no `idr.match` is
  written for it. For `main : IO ()`, no `idr.data` for `IO` and no
  match on `MkIO` in the root.
- For `show (the Int 3)` through the Prelude, the emitted module calls
  the implementation's method function with `idr.call` and three
  arguments at most once per call site, and defines no
  `Prelude.Show.show[...]` instance; the same for `map` on `Maybe`.
- The stage-0 dump: fewer than 58,305 `idr.func`s, with no instance
  whose origin is a method projection at an implementation; the count
  recorded before and after (README Qualification 3).
- `grep -rn 'Erased loc\|Gone' compiler/src/IdrisMLIR/Frontend` finds
  nothing but the fork's `Erased` constructor in compile-time terms.
- **Tempting partial:** translating the method projection's instance
  with its erased lambdas dropped. Rejected: the method function's
  type arguments are then unknown in the instance and known only at
  the call, so the call is where the projection is resolved.

## Escalate if

- **C1.6 `TypeArg Ty`.** `CS/Ids.idr` cannot import `CS/Types.idr`
  (`Types.idr:11` imports `Ids`), and a type argument need not have a
  `Ty`: a type family (`\x => Vect x Int`), a phantom's type, a type
  that mentions an erased value. This lane produces the alpha-normal
  text for every argument; report that `TypeArg` must hold a `String`
  (or the constructor the coordinator names for text).
- **C1.2 `Idr_InstanceAttr`'s arguments** (a `TypeAttr`, a
  `FlatSymbolRefAttr`, a `#idr.con`): an implementation applied to
  implementations (`Show (List Int)`) is no one symbol, a shape has
  holes, and a type family has no MLIR type. Report that the arguments
  Emit can write from this lane's key are strings.
- **C6.4's `Delay`** of a variable, literal or constructor: the dialect
  has no lazy value that is already evaluated (`Idr_SuspendOp` and
  `Idr_DelayOp` both build a cell, IdrOps.td:816-855; `Idr_ConstantOp`
  holds no lazy, :605-613). Report with these lines; propose a dialect
  form (a lazy constant, or a canonicalization of `idr.delay` whose
  body yields a value defined above) owned by the coordinator and U01,
  and keep `suspend`.
- **C6.1's last sentence** says U18 reports a position that cannot be
  dropped. With no erased term in `Term`, Translate meets it first and
  rejects it (`ValueType`); nothing reaches Emit. Report the overlap.
- **C1.6 names the records `Fn` and `Data`**; at 25890d32 the function
  record is `TFn` (Term.idr:338). Fill `key` on whichever name U18
  leaves and report it.
- A definition the program reaches whose erased argument is applied to
  a head of unknown type in a corpus program (a `let`-bound value that
  is neither a lambda nor an application of a known head): the
  rejection fires on a program that compiled at 25890d32. Report the
  program and the term.
