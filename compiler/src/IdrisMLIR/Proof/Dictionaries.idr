-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What a dictionary rooted at an implementation reduces to, by the host's
||| steps (`Idris.Host.Reduces`), and what a projection of it takes.
|||
||| A dictionary the growth check roots at an implementation J
||| (`Frontend.Growth.Template.Rooted`) is J applied to as many arguments as
||| its one right-hand side binds. The growth check reads J's fields over
||| J's own parameters (`Frontend.Growth.Implementations.fieldsOf`): the
||| right-hand side with a marker standing for each parameter, reduced to
||| the constructor it builds (`Fields.builtBy`) applied to its fields
||| (`Fields.inOrder`). At an instance the evaluator unfolds J, and the
||| right-hand side it reaches is the marked one with the instance's values
||| put in for the markers, so it reduces to the constructor applied to the
||| fields with those values put in (`rootedReduces`); a projection of that
||| takes the field its one alternative's leaf names (`projectedField`).
||| What a field's position receives is so what the field's template, over
||| J's parameters, writes at the instance's values, which is the field
||| read the growth theorem states (`Proof.Bound.AtField`).
|||
||| Every proof is erased and total, and nothing here runs.
module IdrisMLIR.Proof.Dictionaries

import Core.Case.CaseTree
import Core.Context
import Core.TT
import Idris.Host
import Libraries.Data.List.SizeOf

%default total

||| A dictionary rooted at an implementation J, J applied to as many
||| arguments as its one right-hand side binds, where the evaluation
||| unfolds J: it reduces to that right-hand side with the arguments put in;
||| and where the right-hand side over J's parameters' markers (`marked`)
||| reduces to J's constructor applied to its fields (`built`), and putting
||| the instance's values in for the markers gives the right-hand side with
||| the arguments put in, the dictionary reduces to the constructor applied
||| to the fields with the values put in. The last premise is the
||| substitution's: the fork's `substs` and `refsToLocals`, whose
||| definitions no proof of a program over the fork reaches.
export
0 rootedReduces : {0 ev : Evaluation} -> {0 ctx : Frozen} -> {0 t, marked, built : ClosedTerm} ->
                  {0 args : List ClosedTerm} -> {ns, ms : Scope} ->
                  Spine t (Ref rfc Func j) args -> Defines ctx j d -> Admits ctx ev.unfolding d ->
                  definition d = PMDef info ns body -> Evaluates ev.running info ByName ->
                  TreeOf body (STerm i rhs) -> (same : length args = length ns) ->
                  (bs : Bounds ms) -> (vs : SubstEnv ms []) ->
                  Reduces ev ctx marked built ->
                  substs (mkSizeOf ms) vs (refsToLocals bs marked) =
                    substs (mkSizeOf ns) (bindArguments args ns same) (embed rhs) ->
                  Reduces ev ctx t (substs (mkSizeOf ms) vs (refsToLocals bs built))
rootedReduces spine defines admits isDef evaluates tree same bs vs steps putIn =
  Then (Contract (Unfold spine defines admits isDef evaluates tree same ToLeaf))
       (replace {p = \x => Reduces ev ctx x (substs (mkSizeOf ms) vs (refsToLocals bs built))} putIn
                (substitutes bs vs steps))

||| A projection whose case tree matches its record, at the variable its
||| parameters bind the record to, by one alternative whose leaf is a field:
||| where the record is a constructor applied, at the entry the
||| alternative names, the leaf the tree chooses is that field with the
||| constructor's arguments bound to the alternative's names. The
||| projection's tree is the fork's (`Frontend.Translate.Closed.projectionOf`
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
