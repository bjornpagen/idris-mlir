<!-- SPDX-License-Identifier: 0BSD -->
<!-- Copyright (c) 2026 Bjorn Pagen -->
## T — The translation of applications total: a structural spine and one head evaluation

Findings: F12

Owner / exclusive writes: `compiler/src/IdrisMLIR/Frontend/Translate/Terms.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Programs.idr`, `compiler/src/IdrisMLIR/Frontend/Translate/Cases.idr`. Nothing else: `tools/policies.txt` is the coordinator's (you name the lines that go); `Frontend/Translate/Closed.idr`, `Frontend/Program.idr` and `Frontend/Driver.idr` are lane I's.

Read first:
- Packet: README §1, §2 (two hosts), §3 F12, §4.6 (as lane I implements it, quoted under Inputs), §6.
- `proposals/0001-total/README.md` §4.1 (head beta, ruling (b)), §4.3 (the `Beta` phase and why applying a part goes to `normaliseHoles`), §5 item 6 (the two changes and the owner's ruling on the refusal).
- `AGENTS.md`: "A closed call runs at run time"; "never miscompile silently"; no count is a reason to refuse.
- `Terms.idr`: `Ctx` 45-50; `compileTime` 137-148; `headType` 152-160; `term` 236-303; `delayed`, `letIn`, `suspend` 305-342; `applyOver` 344-372; `bindHeld` 374-392; `application`'s `Ref` clause 394-1331 (its where-block: `holed` 459-649, `arguments` 652-678, `argValue` 686-691, `finish` 697-712, `resolveMethod` 723-753, `call` 770-778, `identity` 785-800, `exiting` 807-813, `constructor` 906-947, `primitive` 949-979, `hooked` 1311-1330); `application`'s other clause 1337-1351; `headStep` 1353-1376.
- `Closed.idr`: `VarInfo` 54-64 and `under` 74-77; `closeWritten` 182-192; `hasRuntimePart` 205-212; `solved` 224-226; `solution` 235-250; `runtimeDependent` 281-322; `holeMarker` 335-336, 973; `Normaliser` 339-341; `normalisedBy` 477-490 (the guard: `partialIn`, then `normaliseKeeping`, which binds every `MN "idris-mlir-hole" i` as a variable the evaluator does not look into); the `Part` record 557-566 and `partOf` 699-702 (the pattern your `Arg` follows); `implementationOf` 872-884; `stuckText` 908-912; `fillHoles` 1022-1029; `packedType`, `unpacked` 1054-1080.
- `Frontend/Host.idr:49-61` (`host.normaliseHoles`: applies lambdas and fills solved metavariables, unfolds no definition); `Frontend/Walk.idr:37-99` (`Walked`, `start`, `enter`).
- `Cases.idr:449-818` (the seven `covering` definitions; their own recursion is structural on the case tree); `Programs.idr:43-124, 144-174`.
- `tools/policies.txt:38-58` (the `covering` lines).

Permitted outcome:
- Mandatory: every definition of the three files total under `%default total`, with no `covering`, `partial`, `assert_total`, `assert_smaller` or `believe_me`, but for one fixed exception: `translateIOProgram` calls `Finite.translateFrom`, which lane Q makes total (outcome A) or `covering` (outcome B, owner ruling R4), so `translateIOProgram` keeps `covering`, with the comment `-- covering only because translateFrom is: the dictionary passes are not yet proved finite (Finite.idr)`, and the coordinator removes it if Q returns A; the translation unchanged on programs that today translate and that refer only to definitions Idris proves total, except the recorded narrowings named under Fixed decisions; the refusal the owner ruled (an implementation that refers to a definition Idris does not prove total) explicit; the consumer adaptations to §4.6 in your files.
- Optional: nothing.
- Later: a third phase if the recorded narrowings show up in a real program (Escalate, not this lane).

Fixed decisions:
- **Phase** (Terms.idr, `export` the type abstractly and `asWritten`):
  ```idris
  ||| Where a term being translated comes from: written in the definition
  ||| (`Written`), which may still hold redexes, solved metavariables and
  ||| values the environment binds, and which may be settled once into the
  ||| phase it holds; or settled (`Settled`): a normal form of Idris's
  ||| evaluator, closed but for the variables bound around it, which
  ||| nothing evaluates again.
  data Phase = Settled | Written Phase

  asWritten : Phase
  asWritten = Written Settled
  ```
  Going from `Written next` to `next` is a step to a part of the phase, as Closed's phases are, so the checker sees it.
- **The measure**: lexicographically the phase, then the metavariables entered on the path (`Walked`, as `Closed.filledIn` enters them), then the term. Every function of the mutual block but `settle` and `holed` takes `(ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w)` right after its auto arguments (`settle` takes the phase it translates in, `holed` the phase only, as declared below); every recursive call passes them on unchanged, except a metavariable's solution (`rec w' less` after `enter`) and a settled term (`next`, with `start` and `sizeAccessible start`).
- **Arg** (Terms.idr):
  ```idris
  ||| An argument of an application, made where it is a subterm: as written,
  ||| its translation, and what it closes over as an implementation
  ||| (`holed`), each suspended there, so that no use translates a list
  ||| element.
  record Arg (vars : Scope) (nv : Nat) where
    constructor MkArg
    written : TT vars
    translated : Lazy (Core (Term nv))
    held : Lazy (Core (Maybe (ClosedTerm, List1 (ClosedTerm, Core (Term nv)))))
  ```
  with `overBinder : Arg vars nv -> Arg (x :: vars) nv` (`weaken` the written term; the thunks as they are) and `underLet : Arg vars nv -> Arg (x :: vars) (S nv)` (`weaken` the written term; `weakenUnder 1` on the translation and on every value thunk inside `held`).
- **Stand** (Terms.idr): what a marker of a settled term stands for.
  ```idris
  data Stand : Nat -> Type where
    ||| A variable in scope: the marker is bound as it is, with no `let`.
    AsVariable : VarInfo (Fin nv) -> Stand nv
    ||| A runtime value, bound once by a `let` before the term.
    AsValue : Lazy (Core (Term nv)) -> Stand nv
  ```
- **The spine.** `term`'s `App` clause walks the spine itself; each argument becomes an `Arg` where it is a subterm, built by `argOf` (`MkArg a (term ph w acc ctx env a) (holed ph ctx env afc a)`); a list of TT arguments (a metavariable's) becomes `Arg`s through an explicit recursion `argsOf`, never `map`. Every place that today calls `term` or `holed` on a list element reads the thunks instead: `applyOver`, `arguments`, `argValue`, `finish`, `identity`, `primitive`'s `Crash`, `resolveMethod`'s rest, the redex binding.
- **The head evaluation** (0001 §4.1 ruling (b)):
  - A syntactic redex `(\x => body) a`, at any phase, binds `x` in the environment and translates `body`, which is a subterm, with the remaining `Arg`s: an erased binder (`isErased rig`) binds `TypeValue (closeWritten bfc env a.written)`; an argument that is a variable binds a copy of that variable's entry (an alias); a dictionary binder (`dictionaryBinder rig ty`) binds `Static w Nothing` for `w <- solved (closeWritten bfc env a.written)` when `not !(runtimeDependent w)`, and otherwise, from `!(a.held)` = `Just (shape, values)`, a Core `let` of the packed values (`quantityOf top`) and `Static shape (Just (FZ, MkHoles (map fst values) binder))`, the binder made as `Instances.classify` makes it (`Instances.idr:225-229`), and `Nothing` refuses `RuntimeClosure` with today's text `"an implementation chosen at runtime: " ++ !(showTT w)`; any other binder is today's `let` (`Let loc (binderName x) (quantityOf rig) v body`, `v <- a.translated`, entry `Runtime FZ Nothing (Just known)`, `known <- closeNormalise bfc env ty`). The remaining `Arg`s go under the binder by `overBinder` (no Core binder) or `underLet` (a Core `let`).
  - A value from the environment (a variable whose entry is `Static`) applied to its `Arg`s, a projection's field (`resolveMethod`), at phase `Written next`, is **settled**: `settle next ctx env fc value pre args` (below) gives Idris's evaluator the value applied to its arguments, compile-time ones in place and runtime ones as markers, and translates the normal form in phase `next`. In phase `Settled`, a `Static` variable used at runtime refuses `RuntimeClosure` with `"an implementation chosen at runtime: " ++ !(showTT t)` (a recorded narrowing: a settled term binds only runtime variables, so only `holed`'s pieces below can reach it), and `resolveMethod` does not resolve (it returns `Nothing`, and the call requests the projection as any definition: the same value, one call further).
  - The evaluator is `normalisedBy host.normaliseHoles` (exported today). It is Idris's evaluator that applies lambdas and fills solved metavariables and unfolds no definition, so a closed call inside the value still runs at run time (AGENTS.md), and `normalisedBy`'s guard is the owner's ruling: a value that refers to a definition Idris does not prove total is refused, `reject (bestFC ctx fc) ctx.owner StaticArgument ("the implementation " ++ !(showTT value) ++ " refers to " ++ !(stuckText (OnPartial n)))`, which names both. 0001 §5 item 6 names `normaliseAll`; it unfolds and runs every definition the term reaches, which would compute closed calls of a method at compile time, so this lane uses `normaliseHoles` through the same `normalisedBy` (reported to the coordinator).
  - A metavariable, at any phase, is entered once on its path: `enter (gamma defs) (Resolved i) w` gives the smaller walk and its solution (`solution fc n margs`) is translated (as a term, or as the head of the remaining `Arg`s) with `rec w' less`; a solution `Nothing` keeps today's refusal (`EscapeHatch`, "the hole ..."); a metavariable met again on its own path is `internal (bestFC ctx fc) "a metavariable met again on its own path"`.
- **settle** (Terms.idr, in the mutual block):
  ```idris
  settle : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
           (next : Phase) -> Ctx -> List (VarInfo (Fin nv)) -> FC ->
           (value : ClosedTerm) -> (pre : List (Stand nv)) -> List (Arg vars nv) -> Core (Term nv)
  ```
  `value` is closed but for the hole markers `0 .. length pre - 1`, which `pre` says what they stand for. Each `Arg`, in order, gives one argument term: when `compileTime env a.written` or `not (hasRuntimePart w)` for `w <- solved (closeWritten fc env a.written)`, the term `w` itself; otherwise, when `!(a.held)` is `Just (shape, values)`, `shape` with its markers renumbered to the next free numbers (`fillHoles (map holeMarker [k .. k + p - 1]) shape`) and one `AsValue` per value; otherwise, when `a.written` is a variable whose entry is `Runtime` or `Shaped`, the next marker and `AsVariable` of that entry; otherwise the next marker and `AsValue a.translated`. Then `normalisedBy host.normaliseHoles (foldl (App EmptyFC) value terms)`: `Left n` is the refusal above; `Right nf` goes to `bindStands next start (sizeAccessible start) ctx env loc 0 id stands (embedClosed nf)`, which binds marker `i` (`MN "idris-mlir-hole" i`) by `refToLocal` to a new TT binder, `AsVariable e` as the entry `map ren e` with no Core binder, `AsValue v` as `Let loc (shown "held") (quantityOf top) (rename ren !v) ...` with the entry `Runtime FZ Nothing Nothing` (as `bindHeld` binds held values today), and at the end translates the body with `term next ...`. A `Static t (Just (x, hs))` variable is settled as `fillHoles !(unpacked hs.types (holeMarker 0)) t` with `pre = [AsVariable (Runtime x (Just (typeOf hs.binder)) Nothing)]`; a `Static t Nothing` one as `t` with `pre = []`; `resolveMethod`'s field with `pre = []`, or, for `DictParam _ (Just _)`, with one `AsValue` per value of `!(x.held)` (the field's markers are the shape's).
- **holed** (Terms.idr, in the mutual block, out of `application`'s where-block):
  ```idris
  holed : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vars : Scope} ->
          Phase -> Ctx -> List (VarInfo (Fin nv)) -> FC -> TT vars ->
          Core (Maybe (ClosedTerm, List1 (ClosedTerm, Core (Term nv))))
  ```
  It evaluates nothing itself: it closes `x` with each `Runtime`, `Shaped` and `Static _ (Just _)` entry of the environment replaced, in order, by `TypeValue (holeMarker k)` (so `closeWritten` puts the marker where the variable is; those entries are its stands), then `r <- implementationOf !(solved closed)` (Closed's reduction, total: projections, `let`s, applied lambdas, through its own phases), then walks `r` structurally: a marker standing for a `Static t (Just (v, hs))` is today's leaf (`Terms.idr:504-508`); a definition that `gives` (as `:601-616`) applied to arguments is today's `parts` (`:618-649`), each argument of `r` made where it is a subterm with its walk suspended, numbered from 0 and shifted when combined; at a value position, a marker standing for `Runtime v` or `Shaped v` is `(Just v, aty, pure (Var loc v))`, and any other runtime value is a piece translated by `bindStands next ... (map AsVariable stands) (embedClosed piece)` at phase `Written next`, and at phase `Settled` refuses `RuntimeClosure` (`"an implementation chosen at runtime: " ++ !(showTT r)`, the second recorded narrowing); anything else is today's `closedOver` (`:562-592`) over the markers. Today's `reduced` step and the substitutions of `walk` are gone: `implementationOf` does them. The numbering and merging after the walk (`:461-469`) stay as they are.
- **Splitting `application`**: `spine` (walks `App` nodes, collecting `Arg`s), `applyRef` (today's `Ref` clause, its where-block kept, every list element read through its thunks) and `applyHead` (every other head: a variable, a lambda with arguments, a metavariable, an `As` pattern, anything else translated as a term then `applyOver`). `term`'s `Ref` clause calls `applyRef` with no arguments, so that no clause passes a term to a function that passes it back unchanged.
- **Closed.idr's exports**: none added, none removed. This lane uses exactly: `VarInfo(Runtime, Shaped, TypeValue, Static)`, `under`, `mentions`, `mentionsHole`, `constantLit`, `delayedLets`, `embedClosed`, `closeWritten`, `closeNormalise`, `solved`, `solution`, `runtimeDependent`, `hasRuntimePart`, `normaliseClosed`, `normalisedBy`, `holeMarker`, `fillHoles`, `unpacked`, `packedType`, `pairNames`, `projection`, `projected`, `implementationOf`, `whnf`, `Head(Built, Stuck)`, `StuckOn(OnRuntime, OnPartial, OnValue)`, `stuckText`, `erasedArgs`, `shapeHead`, `shaped`, `showTT`, `isTypeLike`, `lookupDef`; and `Host.host`, `Walk.Walked`, `Walk.start`, `Walk.enter`. Lane I keeps each of these with its signature.
- **Two hosts**: no construct idris-mlir refuses; `Lazy` record fields as `Closed.Part` has them; quantity-1 binders where they hold.

Inputs: README §4.6 as lane I implements it; apply these declarations in your private copy to typecheck, and deliver none of them.
- `Term.Con` has `name : String` after `id`; `ConId` is `MkConId (dataId : DataId) {arity : Nat} (index : Fin arity)`; every `ConId` is made by `IdrisMLIR.Frontend.Translate.Types.conIdOf : DataId -> GlobalDef -> Core (Maybe ConId)`.
- `IdrisMLIR.Frontend.Translate.State.definitionAddress : Context -> Name -> Maybe Address`; `TS.loops : SortedMap Address Bool`; `TS.refused : SortedSet Address`.
- `Request` is `MkRequest inst name kinds key site owner link` with `owner : Shown`; `request`'s signature is unchanged (`FC -> String -> Name -> List PKind -> Core FnId`).

Outputs:
- `Terms.term` with the new leading `Phase -> (w : Walked) -> (0 acc : SizeAccessible w)` arguments, and `asWritten`, both exported: `Cases.tree` calls `term asWritten start (sizeAccessible start) ctx env' tm` at a leaf (each leaf starts a path).
- Total `translateInstance`; `translateIOProgram` `covering` for `translateFrom`'s sake alone: if Q returns A, the coordinator removes its `covering` and then `Frontend/Program.idr:140`'s and `Frontend/Driver.idr:276, 302, 325`'s (lane I's files) with their `tools/policies.txt` lines; under B those four stay `covering`, for the same reason.

Implement:
1. Re-read the three files. Add `Phase`, `asWritten`, `Arg`, `overBinder`, `underLet`, `Stand` to `Terms.idr`.
2. Thread `ph w acc` through `term`, `delayed`, `letIn`, `suspend`, `applyOver`, and the new `spine`, `argOf`, `argsOf`, `applyRef`, `applyHead`, `bindStands`, keeping every other argument as it is; `settle` and `holed` take the arguments declared above.
3. `term`: `App` → `spine ph w acc ctx env fc f [argOf ... fc a]`; `Ref` → `applyRef ph w acc ctx env fc fc nt n []`; `Local`: `Runtime`/`Shaped` as today, `TypeValue` and out of scope as today's internal errors, `Static` settled at `Written next` (no arguments) and refused at `Settled`; `Meta` entered on the walk (`acc@(Access rec)`); every other clause as today with `ph w acc` passed.
4. `spine ph w acc ctx env afc (App _ f a) args = spine ... f (argOf ph w acc ctx env afc a :: args)`; a `Ref` head goes to `applyRef`, any other to `applyHead`.
5. `applyHead`: a variable: `Runtime`/`Shaped` → `applyOver` with `Var` and `headType`; `Static` → settled or refused as in step 3, with the `Arg`s; a lambda with an `Arg` → the redex binding, then `spine` on its body with the rest; a lambda with none → `term` (a closure); a metavariable → entered, then `spine` on the solution with the `Arg`s; `As` → `spine` on the pattern; anything else → `term` on the head, then `applyOver`.
6. `applyRef`: today's body with `args : List (Arg vars nv)`; `typeAfter`, `instantiate`, `compileTime`, messages and `getAt i xs` read `.written`; `arguments`'s `ValueParam` reads `.translated`, its `DictParam _ (Just _)` reads `.held` and packs as today; `argValue x` is `MkArgValue (closeNormalise afc env x.written) (solved (closeWritten afc env x.written)) (isImplementation x.written) (map (\(shape, held) => (shape, map fst held)) <$> x.held)`; `resolveMethod` settles at `Written next` and returns `Nothing` at `Settled`; `identity` and `Crash` force the `Arg`'s translation. Lift `pack` out of `arguments` so the redex binding uses it too, and make its pair constructor's id with `conIdOf inst !(lookupDef afc ctx.owner con)` (`Nothing` is today's internal "a pair type without its one constructor").
7. `constructor` (`:923`): `Just cid <- conIdOf inst def | Nothing => internal fc ("the constructor " ++ show (fullname def) ++ " is not registered")`, the lookup in `st.cons` as today.
8. Write `settle`, `bindStands` and `holed` as decided; delete `headStep`, `bindHeld`, `holed`'s `walk`, `reduced`, `closedPrefix` and today's `application`.
9. `Cases.idr`: the leaf calls `term asWritten start (sizeAccessible start) ...`; `instanceOf` takes the constructor's `GlobalDef` and, for a value whose Core type is `DataT d`, looks up `!(conIdOf d def)` in `st.cons` (the check `layout.name == cn` stays); `newtypeCase` and `conAlternatives` make `cid` with `conIdOf inst def` (`Nothing` is today's "is not registered" internal error); remove `covering` from `tree`, `natCase`, `natAlternatives`, `staticCase`, `newtypeCase`, `conAlternatives`, `litAlternatives`. Their recursion is on the case tree's alternatives and needs no other change.
10. `Programs.idr`: `refused` and `loops` are looked up at `definitionAddress (gamma defs) (fullname def)` (no address: not refused, not total); remove `covering` from `translateInstance`; keep it on `translateIOProgram`, with the comment of Permitted outcome, and nothing else in it may need it (its own recursion, if any, is structural).
11. Typecheck (Acceptance); where Idris names a call it cannot see decrease, fix the structure there (a list traversed by `map` becomes an explicit recursion; a term passed back unchanged becomes a call to the function that handles it), never with an escape hatch.

Delete: `headStep`, `bindHeld`, `application` (replaced by `spine`, `applyRef`, `applyHead`), `holed`'s `walk`/`reduced`/`closedPrefix`, every `term`/`holed` call on a list element, 16 of the 17 `covering` markers of the three files (all but `translateIOProgram`'s), and the `MkConId inst (shortName ...)` constructions.

NOT TO DO:
- Do not edit `Closed.idr`, `Instances.idr`, `Types.idr`, `State.idr`, `Program.idr`, `Driver.idr`, `Finite.idr`, `Keys.idr` or `tools/policies.txt`; your handoff names what they need.
- Do not use `normaliseAll`, `again`, or a depth or round counter; do not add a phase beyond the two decided.
- Do not change what `classify` returns, how instances are keyed, or any message text other than the new refusal.
- Do not translate an `Arg`'s written term again anywhere it already has a thunk.
- Do not add tests in `tests/` (lane X2's); name the fixtures under Handoff.

Stop and return: when the three files are total and typecheck, or when an Escalate case holds, with the handoff.

Acceptance:
- `grep -n -w -e partial -e assert_total -e assert_smaller -e believe_me` over the three files finds nothing but comments; `grep -n -w covering` finds exactly `translateIOProgram`'s and its comment.
- Typecheck: in a private copy with the Inputs declarations applied (and, as lane I's dispatch does, the minimal adaptations other modules need), `idris2 --typecheck` of the frontend against `build/idris2-host` checks every module through `Frontend/Driver.idr` with totality enforced, no warnings.
- Discriminators (read): no `term` or `holed` applied to an element of a list; every `Arg` is built by `argOf` or `argsOf`; the only normaliser call in the three files is `normalisedBy host.normaliseHoles` in `settle`; the refusal names the implementation and the definition.
- Two hosts: no construct idris-mlir refuses.
- What only the owner's build shows (mark each in your handoff, for the coordinator to route as `NEEDS-ACCEPTANCE`): `tests/accept/show-dependent-pair`, `tests/accept/higher-order-dictionary` and every accepted program whose implementations close over runtime values translate as before; the Core of `tests/programs` is unchanged but where a settled term now calls a projection's instance.

Tempting partial solution: keeping `getFnArgs` and calling `term` on the list it gives, with a `Nat` depth or an `assert_smaller` to quiet the checker, or settling every head with `normaliseAll`. Acceptance rejects the first (a count or an escape hatch is no measure, and the grep finds it) and the second (it runs closed calls at compile time and unfolds every definition, contrary to AGENTS.md).

Escalate if: Idris's checker rejects a call this design claims decreasing (name the call and the argument it compares); `normalisedBy`'s guard refuses an implementation of `prelude` or `base` (then `terminates`' verdicts, not the program, are at fault); a program of `tests/accept` or `tests/programs` would reach either recorded narrowing (a `Static` used at runtime in a settled term, or a runtime value an implementation closes over computed in a settled term) by your reading; an argument that is no variable and is bound by `settle`'s unrestricted `let` is linear by its type (name the program).

Handoff: per `parts/common.md`. Also: the `tools/policies.txt` lines to delete (the eight `Terms.idr` lines, `translateInstance`'s line and the seven `Cases.idr` lines; `translateIOProgram`'s line stays, its reason becoming `calls translateFrom, covering until the dictionary passes are proved finite`), and, for the coordinator to apply only if Q returns A, `covering` removed from `translateIOProgram`, `Frontend/Program.idr:140` (`program`) and `Frontend/Driver.idr:276, 302, 325` (`perform`, `frontend`, `main`) with their five policies lines; the reject fixture for lane X2: a program whose `Show` implementation's `show` calls a `covering` function, the implementation matched and its method applied (expect `static argument`, message `does not prove ends`); the two recorded narrowings with any program you found that reaches them; every deviation from this dispatch with its reason.
