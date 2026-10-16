<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
## I — Every table of the frontend keyed by a typed identity, the verdict rule held once, and the trust in Idris's compiler moved into the fork

Findings: F11

Owner / exclusive writes: `compiler/src/IdrisMLIR/**` (as `ownership.json` writes it), excluding `compiler/src/IdrisMLIR/Registry/**`, `compiler/src/IdrisMLIR/Emit/Operations.idr`, `compiler/src/IdrisMLIR/Proof/**`, `compiler/src/IdrisMLIR/Frontend/Finite.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Keys.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Programs.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Cases.idr`, `compiler/src/IdrisMLIR/Dialect/**`, `compiler/src/IdrisMLIR/Syntax/**`; and in the fork, `compiler/idris/src/Idris/Host.idr` (new) and `compiler/idris/README.md`. The files this lane edits: `Ids.idr`, `Term.idr`, `Frontend/Translate/State.idr`, `Frontend/Translate/Recursion.idr`, `Frontend/Translate/Instances.idr`, `Frontend/Translate/Dictionaries.idr`, `Frontend/Translate/Types.idr`, `Frontend/Translate/Errors.idr`, `Frontend/Profile.idr`, `Frontend/Driver.idr`, `Emit.idr`, `Emit/Monad.idr`, `Emit/Closures.idr`, `Emit/Index.idr`, `Emit/Bodies.idr`, `Frontend/Host.idr` (deleted), `Frontend/Resolve.idr` and `Frontend/Translate/Closed.idr` (their import of it), and the two fork files. Nothing else: both `.ipkg` files and `tools/policies.txt` are the coordinator's (you give the text).

Read first:
- Packet: README §1 (I5), §3 F11 (with its note that `TS.symbols` stays), §4.4, §4.6, §6; `review.md` §1a (the declarations §4.6 lacked, fixed below) and D1, D2.
- `proposals/0002-total/README.md` §5 item 8 (the list this finding comes from).
- `Ids.idr:16-34` (`FnId`, `DataId`, `ConId`), `:68-78` (their `Eq`, `Ord`, `Show`), `:414-418` (`contentName`).
- `Frontend/Translate/State.idr:77-87` (`nameKey`), `:89-105` (`Request`), `:169-177` (`Dictionary`), `:192-269` (`TS`: `loops` 218, `named` 221, `symbols` 225, `blockNames` 230, `dicts` 234, `assumed` 239, `refused` 259, `spelled` 262, `places` 266, `tyCons` 269), `:271-290` (`initState`, `nextPass`).
- `Frontend/Translate/Recursion.idr:35-138` (the Tarjan search keyed by `nameKey`).
- `Frontend/Translate/Instances.idr:40-52` (`request` builds `Request`).
- `Frontend/Translate/Dictionaries.idr:61-73` (`chooser`), `:141-158` (`recordDictionary`, the message at 152-156).
- `Frontend/Translate/Types.idr:308-318` (`tyConFacts`), `:426-428` (`shortName`), `:593-652` (`dataInstanceIn`; `datacons` at 632-638), `:656-679` (`constructor`, `MkCon` at 676).
- `Frontend/Profile.idr:146-148` (`found`), `:260-263` (`moduleOf`), `:359-395` (`level`: `reported`, `refuse`, `reach`).
- `Frontend/Translate/Errors.idr:74-85` (`moduleLoc`, `places`).
- `Term.idr:368-379` (`Con`), `:445-459` (`Names`, `sourceNames`), `:486-503` (`printer`: `show c` at 494 and 503), `:557-561` (`dataDecl`: `show c.id`).
- `Emit/Index.idr:108-116` (`spellCtors`: `c.id.name`), `:136-140` (`names`); `Emit/Bodies.idr:326-328, 375-377` (internal messages that `show` a `ConId`), `:456, :484` (`lift` callers); `Emit/Monad.idr:19-40` (`ES`, `initial`); `Emit/Closures.idr:58-123` (`Numbering`, `lift`); `Emit.idr:73`.
- `MLIR/Bytecode.idr:150-176, 235-237` (`Numbered`, `Scope`).
- `Frontend/Driver.idr:215-227` (`statusOf`, `statusOfAll`).
- `Frontend/Host.idr` whole (the `Host` record, `host = assert_total (MkHost ...)` at 84, its importers `Resolve.idr:21`, `Driver.idr:53`, `Translate/Dictionaries.idr:40`, `Translate/Closed.idr:16`); `Registry/Libraries.idr:84-101` (`moduleOrigin`: `IdrisMLIR.*` is `User`, the package `idris-compiler` is `Library Compiler`), `:60-71` (`Compiler` is trusted); `Frontend/Profile.idr:345-348` (a trusted library's own `assert_total` and `assert_smaller` are filtered from its references, so they are admitted); `compiler/idris/README.md:225-230` (the evaluator and the elaborator are not total, and which frontend calls reach them); `tools/policies.txt:33` (the trust point's line).
- `Frontend/Walk.idr:93-99` (`enter`: a name with no place is never entered); `Proof/Requests.idr:250-254` (`Address`), `:307-314` (`Link`); `Frontend/Translate/Keys.idr:405-412` (`addressOf`, which moves to you), `:806-810` (the `symbols` check).
- Consumers in other lanes' files, which those lanes adapt against §4.6 (you do not edit them): `Frontend/Finite.idr:126-128, 157, 235-236` (Q), `Frontend/Translate/Keys.idr:196-226, 251-285, 405-412, 484, 795` (Q), `Frontend/Translate/Programs.idr:50, 79` (T), `Frontend/Translate/Cases.idr:496, 729, 764` (T), `Frontend/Translate/Terms.idr:670, 923` (T), `Emit/Operations.idr:381, 391` (P: reads `c.id.dataId`, `c.tag` and `show c`; all keep working unchanged).

Permitted outcome:
- Mandatory: the declarations under Fixed decisions, exactly; every consumer in your files adapted; every printed text a user or a test reads (the module, the Core dump, every refusal) byte-identical; the frontend's verdict rule held once; the `Host` record and `host` moved into the fork as `Idris.Host`, so that no `IdrisMLIR.*` module holds an escape hatch of its own (owner ruling R4).
- Optional: nothing.
- Later (not this wave, named in your handoff): typed SSA value names in `IdrisMLIR.MLIR` (they would carry Emit's `Numbering.names` and Bytecode's `Scope`), which changes the syntax model and P's `Emit/Operations.idr:115`.

Fixed decisions: this is README §4.6 as the coordinator folds it in; T and Q write against the same text.
- **A definition's identity is its address in the context**, `IdrisMLIR.Proof.Requests.Address` (the context index's eight bytes, what `Link.definition` already holds), not `Fin n`: the context size is a runtime value and the links already use `Address`. In `Frontend/Translate/State.idr`, exported:
  ```idris
  ||| A name of the context by its index, as the index's eight bytes, the low
  ||| byte first: what a definition is, which the request links compare.
  export
  addressOf : Int -> Address

  ||| A definition's identity: its address in the context; nothing for a
  ||| name the context does not hold, which no table keeps.
  export
  definitionAddress : Context -> Name -> Maybe Address
  definitionAddress ctx n = addressOf <$> getNameID n ctx
  ```
  `addressOf`'s body is `Keys.idr:407-412` moved verbatim (`bytes 8 (cast i)`); Q deletes the private copy in Keys and uses yours. A name with no address has no identity: every table below skips it, as `Walk.enter` does.
- **`Request`** (State.idr) becomes exactly:
  ```idris
  public export
  record Request where
    constructor MkRequest
    inst : FnId
    name : Name
    kinds : List PKind
    key : InstanceKey
    site : FC
    owner : Shown
    link : Link Form
  ```
  `base` is deleted: its identity is `link.definition`, and the two messages that print it (Finite, Q's) print `nameKey !(toFullNames r.name)`, the same text. `owner` is `Shown`, the requesting definition as the refusal prints it: it is never compared, only printed, and an `FnId` prints the instance's symbol (`Main.f[Int]`), not the definition (`Main.f`), so §4.6's "the requesting `FnId`" would change the text. `request`'s signature is unchanged (`(owner : String)`); it stores `shown owner`.
- **`Dictionary.chooser : Shown`**, for the same reason: it is printed once (`Dictionaries.idr:155`) and never compared; `recordDictionary` stores `shown by` and prints `show d.chooser`.
- **`ConId`** (Ids.idr) becomes:
  ```idris
  ||| A constructor of a data instance: the instance, and the constructor's
  ||| position among its type's constructors, which is Idris's tag for it.
  ||| Its name is printed from the context that declares it (`Con.name`).
  public export
  record ConId where
    constructor MkConId
    dataId : DataId
    {arity : Nat}
    index : Fin arity
  ```
  `arity` is the number of constructors of the instance's type constructor (its `TCon`'s constructor list). `Eq` and `Ord` compare `(dataId, finToNat index)`. `Show ConId` stays, printing the identity, `show c.dataId ++ "#" ++ show (finToNat c.index)`, for internal-error messages only (P's `Emit/Operations.idr:391` uses it); nothing a user or a test reads prints it.
- **`Term.Con`** gains `name : String` after `id` (the constructor's name as the module and the dump print it, `shortName (fullname def)`): `MkCon id name idrisName tag fields loc role`. Its `tag` is generated from the identity, `finToNat id.index`, at the one construction site. **`Term.Names`** gains `conName : ConId -> String` as its third field.
- **`conIdOf`**, exported from `Frontend/Translate/Types.idr`, the one way any site makes a `ConId`:
  ```idris
  ||| A constructor's identity in a data instance: its tag as a position
  ||| among the constructors of the type its result is. Nothing when the
  ||| definition is no constructor, its type's constructors are not known,
  ||| or its tag is past them.
  export
  conIdOf : {auto c : Ref Ctxt Defs} -> DataId -> GlobalDef -> Core (Maybe ConId)
  ```
- **`TS` fields**: `loops : SortedMap Address Bool`, `refused : SortedSet Address`, `tyCons : SortedMap Address TyConFacts`, `blockNames : SortedMap Address String`, `places : SortedMap ModuleIdent (Origin, String)`, `spelled : SortedSet (ModuleIdent, String)`. `symbols : SortedMap String (Link Form)` stays as it is: it is the check that no two identities print one symbol (F11's note, review D2), the reason `FnId` and `DataId`, which are symbols, are faithful identities. `cons`, `dicts` and `assumed` keep their types, over the new `ConId`.
- **`nameKey`** stays exported, as a print only: the polymorphic-recursion refusal prints a definition by it. No table is keyed by it after this lane; its doc comment says so.
- **Recursion**: `Node` gains `address : Address` (`MkNode name address location calls`); `Search`'s `number`, `low` are `SortedMap Address Nat`, `stack : List Address`, `onStack : SortedSet Address`, `nodes : SortedMap Address Node`, `found : List (List Address)`; `visit`, `successors` take `SortedMap Address Bool` for `done`.
- **Emit**: `ES.owner : FnId` and `initial : FnId -> Shown -> ES`. `lift`'s kind becomes `data Lifted = LiftedLambda | LiftedDelay` (in `Emit/Closures.idr`, exported), printed `"lam"` and `"delay"` where the symbol is made. `ES.keys` stays keyed by the lifted function's symbol: like `TS.symbols`, it is the check that two contents never share one printed name (`Closures.idr:116-119`).
- **Not changed, by decision**: Emit's `Numbering.names` and Bytecode's `Scope` are keyed by SSA names, the only identity of a value in `IdrisMLIR.MLIR` (`Value.name : String`), which P's `Emit/Operations.idr:115` and `SyntaxSamples.idr` spell as text; Bytecode's `Numbered` tables key by the very text the file holds (strings, dialect and op names, attribute and type text), which is "its own table of the values it writes". Each gets a one-line comment saying why it is keyed by text.
- **The verdict (§4.4, frontend half; owner ruling R1)**: the rule is `statusOfAll` (internal over refused); `statusOf err = statusOfAll [err]`, and its doc comment names the order `accepted < refused < internal`, the worst seen winning, and why that needs no exception: the frontend's refusals end its build, so no error after a refusal is its cascade.
- **The trust in Idris's compiler lives in the fork (owner ruling R4).** The claim that each `Host` operation returns is a claim about Idris's compiler, and the fork is Idris's compiler, a trusted library (`Library Compiler`) whose own assertions `make self` admits; in `IdrisMLIR.*` the same `assert_total` is the user's and is refused. So: a new fork module `compiler/idris/src/Idris/Host.idr`, `module Idris.Host`, holds the `Host` record and `host` exactly as `Frontend/Host.idr` has them (same fields, same types, same `assert_total (MkHost {...})`, the same imports, `%default total`, `%prefix_record_projections off`), its module doc the current one restated from the fork's side: what a program written over Idris's compiler (the frontend) asks of it and its checker cannot follow, each field one operation at one type, stated once here; the evaluator, the elaborator and the termination check are here for good, every other field until its fork function is total. `Frontend/Host.idr` is deleted, and its four importers import `Idris.Host` instead (only `IdrisMLIR.Frontend.*` imports the fork, which this keeps; the fork imports nothing of `IdrisMLIR.*`). `compiler/idris/README.md` gains, after the paragraph on the evaluator and the elaborator (`:225-230`), one paragraph: `Idris.Host` is the fork's own module (no upstream file), the one record of these operations, whose `assert_total` is the fork's statement that each returns; the frontend calls them only through it. No field, type or behaviour changes.
- **Two hosts.** Everything here must build with the stock Idris on Chez and with idris-mlir (`make self`): implicit record fields (as the fork's `Core.Primitives.Prim` has), `Fin`, `Vect 8 (Fin 256)` keys, `ModuleIdent`'s own `Ord`; no escape hatch, no `%foreign`, no new `partial` or `covering`. A quantity-1 binder is welcome where it holds.

Inputs: README §4.6 as above; nothing from a sibling's body. Your private copy needs the other lanes' consumer adaptations to typecheck: apply in it the minimal adaptations this dispatch names for `Finite.idr`, `Keys.idr`, `Terms.idr`, `Cases.idr` and `Programs.idr` (each listed under Outputs), and deliver none of them.

Outputs: the declarations, and who consumes them.
- `State.addressOf`, `State.definitionAddress`: used by you (Recursion, Profile, Types), by Q (`Keys.idr`: `write`'s `Ref` case becomes `Node (Shaped Reference) (definitionAddress ctx n) 0`; `instanceKey` uses `addressOf d`; `blockNames` lookups) and by T (`Programs.idr:50, 79`: `refused` and `loops` by `definitionAddress (gamma defs) (fullname def)`).
- `Request` without `base`, `owner : Shown`: Q (`Finite.idr:126-128` prints `show r.owner` and `nameKey !(toFullNames r.name)`; `:157` the same name).
- `ConId`, `conIdOf`, `Con.name`, `Names.conName`: T (`Cases.idr:496, 729, 764`; `Terms.idr:670, 923` make every `ConId` with `conIdOf`), Q (`Finite.idr:250, 284`: no textual change), P (`Emit/Operations.idr:381, 391`: no change).
- `TS.blockNames : SortedMap Address String`: Q (`Keys.idr:196-206, 217-226, 256-277`). `TS.loops`, `TS.refused`: T (`Programs.idr`) and Q (`Finite.idr:235-236` copies fields; no textual change).

Implement:
1. `Ids.idr`: replace `ConId` as decided; `Eq`/`Ord` over `(dataId, finToNat index)`; `Show` prints the identity. Leave `FnId`, `DataId`, `InstanceKey`, `contentName` as they are.
2. `Term.idr`: add `Con.name`; add `Names.conName`; `sourceNames` builds it from `p.datas` (`fromList (concatMap (\d => map (\c => (c.id, c.name)) d.cons) p.datas)`, falling back to `show c` for an id the program does not declare, as `fnName` falls back to `show f`); `printer` prints `names.conName c` where it printed `show c` (both sites); `showSource`'s `dataDecl` prints `c.name` where it printed `show c.id`.
3. `Frontend/Translate/Types.idr`: write `conIdOf` (the definition's `DCon tag _ _`; the head `TyCon` of its type's result under its `Pi` binders, read as `Cases.idr:133-137`'s `built` reads it, a few lines of your own; that type constructor's `TCon _ _ _ _ _ (Just cons) _`; `MkConId inst <$> natToFin (cast tag) (length cons)`). In `constructor` (`:656-679`), make the id with `conIdOf inst def` (its `Nothing` is the existing `reject fc owner CompiledModule (cname ++ " is not a constructor")`), build `MkCon cid (shortName (fullname def)) (shown cname) (finToNat cid.index) ...`. `tyConFacts` keys by `definitionAddress (gamma defs) (fullname def)` and, for a name with no address, computes without caching.
4. `Frontend/Translate/State.idr`: add `addressOf`, `definitionAddress` (import what `getNameID` needs, `Core.Context` is already imported); `Request` and `Dictionary` and the `TS` field types as decided; rewrite the doc comments of the changed fields and of `nameKey` so they state the new keys (no comment cites a document).
5. `Frontend/Translate/Instances.idr` (`request`): drop the `base` computation; build `MkRequest inst n kinds found.key fc (shown owner) found.link`.
6. `Frontend/Translate/Dictionaries.idr`: `by : Shown` (`maybe (shown owner) (shown . show . fst) chosen`), stored in `MkDictionary`; the message prints `show d.chooser` and `show by`; the constructor's name in the message stays `maybe (show cid) (\l => show l.name) (lookup cid st.cons)` (the fallback now prints the identity, on a path `Terms.constructor` has already made unreachable by its own lookup).
7. `Frontend/Translate/Recursion.idr`: key everything by `Address` as decided. In `node`, compute `definitionAddress (gamma defs) full`; `Nothing` gives `pure Nothing`. In `successors`, `let Just xkey = definitionAddress (gamma defs) x | Nothing => successors done key w0 acc w p xs s` before the `done` lookup. In `checkComponent`, `inside : SortedSet Address` from the members; a call is inside when its callee's address is in it; each verdict `(n, v)` is inserted at `definitionAddress (gamma defs) n` and skipped when it has none. `checkRecursion` looks `loops` up by the address of `full`, and does nothing for a name with none.
8. `Frontend/Profile.idr`: `reported : SortedSet (Address, Maybe Address)`; `key` is `definitionAddress (gamma defs) full` (with none, the definition is skipped, the same branch `enter` failing takes); `refuse` inserts the addresses of `full`, of `owner` and of the path's head, each when it has one; `found` inserts `(ident, n)`; `moduleOf : FC -> Maybe ModuleIdent`, and the `spelled` test is `maybe False (\m => contains (m, nameRoot full) st.spelled) (moduleOf (userFC here))`.
9. `Frontend/Translate/Errors.idr` (`moduleLoc`): key `places` by `ident`; the `Loc` still prints `shown (show ident)`.
10. `Emit/Monad.idr`, `Emit/Closures.idr`, `Emit.idr`, `Emit/Bodies.idr`: `ES.owner : FnId`, `initial`; `lift` takes a `Lifted`, makes `contentName st.owner.name (liftedText kind) key` and reports `show st.owner`; `Emit.idr:73` passes `f.id`; `Bodies.idr:456, 484` pass `LiftedLambda`, `LiftedDelay`. Add the one-line why-comments on `Numbering.names` and on Bytecode's `Numbered` and `Scope`.
11. `Emit/Index.idr`: `spellCtors` uses `c.name`; `names` adds `\c => maybe (show c) (.name) (lookup c ix.cons)`. In `Emit/Bodies.idr`, the two internal messages that have the `Con` in hand print its name (`:328` `k.name`, `:377` `ctor.name`); `:327` and `:376` keep `show c` (they have none).
12. `Frontend/Driver.idr`: `statusOf err = statusOfAll [err]`, with the order in `statusOfAll`'s doc comment.
13. Typecheck as Acceptance says; fix what fails in your files only.

Delete: `Request.base`; `ConId.name` (the name moves to `Con.name`, read from the context); every lookup of `loops`, `refused`, `tyCons`, `blockNames`, Recursion's tables and Profile's `reported` by `nameKey` (in your files); `places` and `spelled` by `show ident`; `ES.owner : String`; `lift`'s string kind; `statusOf`'s second copy of the rule.

NOT TO DO:
- Do not edit T's, Q's or P's files, or `Dialect/**`, `Syntax/**` (the coordinator's, generated).
- Do not rekey `TS.symbols` or `ES.keys`; do not type SSA names; do not touch Bytecode's tables beyond the comment.
- Do not change `VarInfo` or any export of `Frontend/Translate/Closed.idr`: T writes against its current export list.
- Do not remove the `covering` markers of `Frontend/Program.idr:140` and `Frontend/Driver.idr:276, 302, 325`: they go when T's translation is total, applied by the coordinator at integration with `tools/policies.txt`.
- Do not change `FnId`, `DataId`, `InstanceKey`, `keyText`, or any printed text a user or test reads.
- Do not change a field, a type, an import's meaning or the `assert_total`'s scope in the move: `host` in the fork is the same value. Do not move any other trust into the fork (the dictionary passes' termination is the frontend's claim: lane Q states it as `covering`).
- Do not edit `compiler/idris/MODULES` (it lists kept upstream files; `Idris.Host` is none) or either `.ipkg`.

Stop and return: when every Implement step is done and the typecheck below passes on your private copy, or when an Escalate case holds; return the handoff.

Acceptance:
- Typecheck: in a private copy with the minimal consumer adaptations of Inputs applied, `idris2 --typecheck` of the frontend against `build/idris2-host` checks every module through `Frontend/Driver.idr`, totality enforced, no warnings.
- Discriminators (read in your files): no `nameKey` call outside `State.idr`'s definition; no `SortedMap String` or `SortedSet String` in `State.idr` and `Recursion.idr` but `symbols`; every `MkConId` takes an index and every `ConId` a site makes comes from `conIdOf`; `Term.printer`, `dataDecl` and `spellCtors` print constructor names from `Con.name`/`conName`, never `show` of a `ConId`; `MkRequest` has seven fields.
- The move (here): `Idris/Host.idr` typechecks with the pinned `idris2` against the installed fork (`IDRIS2_PACKAGE_PATH=build/idris2-host/idris2-0.8.0`, `-p idris-compiler`), and your private frontend copy, with that file beside its sources as `Idris/Host.idr`, typechecks with no `IdrisMLIR.Frontend.Host` left; `grep -rn -w -e assert_total -e assert_smaller -e believe_me compiler/src/IdrisMLIR` in your copy finds only `Frontend/Finite.idr:295` (lane Q's, which Q deletes) and comments.
- Two hosts: no construct idris-mlir refuses added (no escape hatch, no `%foreign`, no recursion it would call megamorphic).
- What only the owner's build shows: byte-identical Core dumps and modules (`tools/self.sh`'s stage compare, the program suites), and refusal texts unchanged.

Tempting partial solution: wrapping the strings in newtypes (`record DefKey where name : String`) and keeping `nameKey` as what they hold, or keeping `ConId.name` beside the new index. Acceptance rejects both: the first keeps the printed name as the identity (I5), the second holds one fact twice. Rekeying `TS.symbols` by `FnId` is rejected too: it deletes the guard F11's note keeps.

Escalate if: a constructor's Idris tag is not its position in its `TCon`'s constructor list for some definition you find (then `conIdOf`'s premise is false); `ModuleIdent`'s `Ord` is missing on a host; a consumer needs `Request.owner` as an identity (compared, not printed); keeping `Show ConId` conflicts with a site you cannot fix. Also escalate if `Profile.idr`'s filter of a trusted library's assertions would not admit `Idris.Host`'s `assert_total` by your reading (then the move does not achieve R4: name the line).

Handoff: per `parts/common.md`. Also: the §4.6 declarations as you implemented them (exact signatures of `addressOf`, `definitionAddress`, `conIdOf`, `ConId`, `Con`, `Names`, `Request`, `Dictionary`, the `TS` fields, `Lifted`), any deviation from this dispatch with its reason, and the consumer adaptations T and Q must match. Hub requests: `compiler/idris/idris-compiler.ipkg` gains `Idris.Host` in `modules` (in its sorted place); `compiler/idris-mlir.ipkg` loses `IdrisMLIR.Frontend.Host` if it lists it. `tools/policies.txt`: the line `compiler/src/IdrisMLIR/Frontend/Host.idr: host = assert_total -- ...` becomes `compiler/idris/src/Idris/Host.idr: host = assert_total -- ...` with its reason unchanged, and the section comment "The frontend's two trust points" becomes "The trust points: what the frontend relies on and Idris's totality checker cannot see".
