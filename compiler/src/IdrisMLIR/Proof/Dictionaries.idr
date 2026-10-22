-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What a dictionary rooted at an implementation reduces to, by the host's
||| steps (`Idris.Host.Reduces`), and what a projection of it takes.
|||
||| A dictionary the growth check roots at an implementation J
||| (`Frontend.Growth.Template.Rooted`) is J applied to as many arguments as
||| its one right-hand side binds. The growth check reads J's fields over
||| J's own parameters (`Frontend.Growth.Implementations.fieldsOf`): the
||| right-hand side with the walk's marker in for each parameter, reduced
||| to the constructor it builds (`Fields.builtBy`) applied to its fields
||| (`Fields.inOrder`). At an instance the evaluator unfolds J, and the
||| right-hand side it reaches is the marked one with the instance's values
||| put in for the markers (`Idris.Host.substitutesMarkers`), so it reduces
||| to the constructor applied to the fields with those values put in
||| (`rootedReduces`); the markers are fresh for the context, which is what
||| the host's substitution lemma asks (`Proof.Markers`). A projection of
||| that takes the field its one alternative's leaf names
||| (`projectedField`). What a field's position receives is so what the
||| field's template, over J's parameters, writes at the instance's values,
||| which is the field read the growth theorem states
||| (`Proof.Bound.AtField`).
|||
||| Every proof is erased and total, and nothing here runs.
module IdrisMLIR.Proof.Dictionaries

import Core.Case.CaseTree
import Core.Context
import Core.TT
import Idris.Host
import Libraries.Data.List.SizeOf

import IdrisMLIR.Proof.Markers

%default total

||| A dictionary rooted at an implementation J, J applied to as many
||| arguments as its one right-hand side binds, where the evaluation
||| unfolds J: it reduces to that right-hand side with the arguments put in
||| for J's parameters. Where the right-hand side with the walk's markers
||| in for the parameters reduces to J's constructor applied to its fields
||| (`built`), the dictionary reduces to the constructor applied to the
||| fields with the arguments put in for the markers. The markers are fresh
||| for the context, so the right-hand side names none of them
||| (`leafFresh`): putting the arguments in for the markers is putting them
||| in for the parameters (`Idris.Host.substitutesMarkers`), and the marked
||| term names no unknown by them (`closedNoUnknown`), which the host's
||| substitution lemma asks of the steps it carries the arguments through.
export
0 rootedReduces : {0 ev : Evaluation} -> {0 ctx : Frozen} -> {0 t, built : ClosedTerm} ->
                  {0 args : List ClosedTerm} -> {ns : Scope} ->
                  (mk : Markers ctx ns) ->
                  Spine t (Ref rfc Func j) args -> Defines ctx j d -> Admits ctx ev.unfolding d ->
                  definition d = PMDef info ns body -> Evaluates ev.running info ByName ->
                  TreeOf body (STerm i rhs) -> (same : length args = length ns) ->
                  Reduces ev ctx (substs (mkSizeOf ns) (markersOf fc mk.bounds) (embed rhs)) built ->
                  Reduces ev ctx t (substs (mkSizeOf ns) (bindArguments args ns same) (refsToLocals mk.bounds built))
rootedReduces mk spine defines admits isDef evaluates tree same steps =
  let none = leafFresh mk.fresh defines isDef tree in
  Then (Contract (Unfold spine defines admits isDef evaluates tree same ToLeaf))
       (replace {p = \x => Reduces ev ctx x (substs (mkSizeOf ns) (bindArguments args ns same) (refsToLocals mk.bounds built))}
                (substitutesMarkers {fc} mk.bounds (bindArguments args ns same) rhs mk.apart none)
                (substitutes mk.bounds (bindArguments args ns same) mk.fresh (closedNoUnknown {fc} mk.bounds rhs none) steps))

||| A projection whose case tree matches its record, at the variable its
||| parameters bind the record to, by one alternative whose leaf is a field:
||| where the record is a constructor applied, at the entry the
||| alternative names, the leaf the tree chooses is that field with the
||| constructor's arguments bound to the alternative's names. The
||| projection's tree is the checker's (`Frontend.Translate.Closed.projectionOf`
||| reads it so), and the entry is the one the record's constructor and the
||| alternative's name resolve to.
export
0 projectedField : {0 ev : Evaluation} -> {0 ctx : Frozen} -> {pns : Scope} -> {0 env : SubstEnv pns []} ->
                   {0 p : IsVar nm idx pns} ->
                   Spine (Var.index env (MkVar p)) (Ref cfc (DataCon tag arity) h) fields ->
                   SameEntry ctx h cn -> (fsame : length fields = length cargs) ->
                   Chooses ev ctx env (Case idx p ty [ConCase cn ctag cargs (STerm i leaf)])
                     (substs (mkSizeOf (Scope.addInner pns cargs)) (bindFields fields cargs fsame env) (embed leaf))
projectedField spine entry fsame = ByCase (AsItIs Itself) (Takes (ByConstructor spine entry fsame ToLeaf))
