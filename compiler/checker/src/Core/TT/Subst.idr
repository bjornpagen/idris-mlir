-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.TT.Subst

import Core.Name.Scoped
import Core.TT.Var

import Libraries.Data.List.SizeOf

%default total

-- TODO replace by pointwise lifting: `Subst tm ds vars = All (\_. tm vars) ds`
public export
data Subst : Scoped -> Scope -> Scoped where
  Nil : Subst tm Scope.empty vars
  (::) : tm vars -> Subst tm ds vars -> Subst tm (d :: ds) vars

public export
empty : Subst tm Scope.empty vars
empty = []


namespace Var

  public export
  index : Subst tm ds vars -> Var ds -> tm vars
  index [] (MkVar p) impossible
  index (t :: _) (MkVar First) = t
  index (_ :: ts) (MkVar (Later p)) = index ts (MkVar p)

-- What a variable becomes once values are put in for the variables of
-- `dropped`, each step a function of the side `locateVar` finds it on, and
-- each public, so that a proof over a term with values put in reads off
-- what a variable becomes.

||| A variable of `dropped`: its value; one past them: itself.
public export
droppedAt : (Var vars -> tm vars) -> Subst tm dropped vars ->
            Either (Var dropped) (Var vars) -> tm vars
droppedAt k sub (Left var) = index sub var
droppedAt k sub (Right var) = k var

-- TODO revisit order of `dropped` and `Subst`
public export
findDrop :
  (Var vars -> tm vars) ->
  SizeOf dropped ->
  Var (dropped ++ vars) ->
  Subst tm dropped vars ->
  tm vars
findDrop k s var sub = droppedAt k sub (locateVar s var)

||| A variable bound under `outer`: itself; one past them: what it becomes
||| past `dropped`, weakened under `outer`.
public export
foundAt : Weaken tm =>
          (forall vars. Var vars -> tm vars) ->
          SizeOf outer -> SizeOf dropped -> Subst tm dropped vars ->
          Either (Var outer) (Var (dropped ++ vars)) ->
          tm (outer ++ vars)
foundAt k outer dropped sub (Left var) = k (embed var)
foundAt k outer dropped sub (Right var) = weakenNs outer (findDrop k dropped var sub)

public export
find : Weaken tm =>
       (forall vars. Var vars -> tm vars) ->
       SizeOf outer -> SizeOf dropped ->
       Var (outer ++ (dropped ++ vars)) ->
       Subst tm dropped vars ->
       tm (outer ++ vars)
find k outer dropped var sub = foundAt k outer dropped sub (locateVar outer var)

-- TODO rename `outer`
public export
0 Substitutable : Scoped -> Scoped -> Type
Substitutable val tm
  = {0 outer, dropped, vars : Scope} ->
    SizeOf outer ->
    SizeOf dropped ->
    Subst val dropped vars ->
    tm (outer ++ (dropped ++ vars)) ->
    tm (outer ++ vars)
