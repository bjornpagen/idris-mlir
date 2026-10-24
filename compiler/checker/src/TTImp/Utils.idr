-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module TTImp.Utils

import Core.Env
import Core.Value
import Core.UnifyState
import TTImp.TTImp

import Data.String

import Idris.Syntax
import Idris.Syntax.Builtin

import Libraries.Data.NameMap
import Libraries.Utils.String

%default total

-- Every list, option and wrapper the syntax holds terms in is walked by a
-- function of its own rather than by `map`, `concatMap` or a list's bind,
-- in the order and as often as those visited it, so that each recursive
-- call is on a part of the term it was given and each walk is total by its
-- structure.

-- What a variable contributes in a position: in argument position, a lower
-- case name not bound locally, bound as itself.
bindableVar : (arg : Bool) -> (env : List Name) -> Name -> List (Name, Name)
bindableVar True env nm@(UN (Basic n))
      -- If the identifier is not bound locally and begins with a lowercase letter..
    = if not (nm `elem` env) && lowerFirst n.text
         then [(nm, nm)]
         else []
bindableVar _ _ _ = []

-- Identify lower case names in argument position, which we can bind later.
-- Don't go under case, let, or local bindings, or IAlternative.
--
-- arg: Is the current expression in argument position? (We don't want to implicitly
--      bind funtions.)
--
-- env: Local names in scope. We only want to bind free variables, so we need this.
--
-- Each name is bound as itself; binding it away from names the term already
-- binds makes new spellings, which findUniqueBindableNames does.
export
findBindableNames : (arg : Bool) -> (env : List Name) ->
                    RawImp -> List (Name, Name)

-- Helper to traverse the inside of a quoted expression, looking for unquotes
findBindableNamesQuot : List Name -> RawImp ->
                        List (Name, Name)

bindableIn : (arg : Bool) -> (env : List Name) -> List RawImp -> List (Name, Name)
bindableIn arg env [] = []
bindableIn arg env (t :: ts) = findBindableNames arg env t ++ bindableIn arg env ts

bindableUpdated : (env : List Name) -> List IFieldUpdate -> List (Name, Name)
bindableUpdated env [] = []
bindableUpdated env (ISetField _ t :: upds)
    = findBindableNames True env t ++ bindableUpdated env upds
bindableUpdated env (ISetFieldApp _ t :: upds)
    = findBindableNames True env t ++ bindableUpdated env upds

-- The terms of quoted declarations and clauses, searched for unquotes in
-- the order the declarations list them. A clause's terms are searched after
-- `before` and a declaration's between `before` and `after`, searched again
-- for each one: the terms its enclosing form gives every clause or
-- declaration it holds, so that a form holding none searches none of them.
quotedClause : List Name -> ImpClause -> List (Name, Name)
quotedClauses : List Name -> (before : List (Name, Name)) ->
                List ImpClause -> List (Name, Name)
quotedDecl : List Name -> ImpDecl -> List (Name, Name)
quotedDecls : List Name -> (before, after : List (Name, Name)) ->
              List ImpDecl -> List (Name, Name)

quotedClauses env before [] = []
quotedClauses env before (cl :: cls)
    = before ++ quotedClause env cl ++ quotedClauses env before cls

quotedClause env (PatClause _ lhs rhs)
    = findBindableNamesQuot env lhs ++ findBindableNamesQuot env rhs
quotedClause env (WithClause _ lhs _ wval _ _ cls)
    = quotedClauses env (findBindableNamesQuot env wval ++ findBindableNamesQuot env lhs) cls
quotedClause env (ImpossibleClause _ lhs) = findBindableNamesQuot env lhs

quotedDecls env before after [] = []
quotedDecls env before after (d :: ds)
    = before ++ quotedDecl env d ++ after ++ quotedDecls env before after ds

quotedMaybe : List Name -> Maybe RawImp -> List (Name, Name)
quotedMaybe env Nothing = []
quotedMaybe env (Just t) = findBindableNamesQuot env t

quotedTys : List Name -> List ImpTy -> List (Name, Name)
quotedTys env [] = []
quotedTys env (MkWithFCTyName _ _ t :: tys) = findBindableNamesQuot env t ++ quotedTys env tys

-- A parameter block searches its parameters' types alone.
quotedParamTy : List Name -> ImpParameter -> List (Name, Name)
quotedParamTy env (MkWithRigName _ _ (MkPiBindData _ ty)) = findBindableNamesQuot env ty

quotedParamTys : List Name -> List ImpParameter -> List (Name, Name)
quotedParamTys env [] = []
quotedParamTys env (p :: ps) = quotedParamTy env p ++ quotedParamTys env ps

-- A record searches a binder's default value, then its type.
quotedBind : List Name -> PiBindData RawImp -> List (Name, Name)
quotedBind env (MkPiBindData (DefImplicit t) ty)
    = findBindableNamesQuot env t ++ findBindableNamesQuot env ty
quotedBind env (MkPiBindData _ ty) = findBindableNamesQuot env ty

-- A record searches each parameter with each of its fields in turn.
quotedFields : List Name -> (before : List (Name, Name)) -> List IField -> List (Name, Name)
quotedFields env before [] = []
quotedFields env before (MkWithFCRigName _ _ _ bind :: fields)
    = before ++ quotedBind env bind ++ quotedFields env before fields

quotedRecord : List Name -> List ImpParameter -> List IField -> List (Name, Name)
quotedRecord env [] fields = []
quotedRecord env (MkWithRigName _ _ bind :: params) fields
    = quotedFields env (quotedBind env bind) fields ++ quotedRecord env params fields

quotedDecl env (IClaim (MkFCVal _ (MkIClaimData _ _ _ (MkWithFCTyName _ _ ty))))
    = findBindableNamesQuot env ty
quotedDecl env (IData _ _ _ (MkImpData _ _ tycon _ datacons))
    = quotedMaybe env tycon ++ quotedTys env datacons
quotedDecl env (IData _ _ _ (MkImpLater _ _ tycon)) = findBindableNamesQuot env tycon
quotedDecl env (IDef _ _ cls) = quotedClauses env [] cls
quotedDecl env (IParameters _ (p ::: ps) ds)
    = quotedDecls env [] (quotedParamTy env p ++ quotedParamTys env ps) ds
quotedDecl env (IRecord _ _ _ _ (MkFCVal _ (MkImpRecord (MkWithName _ params) (MkWithNameOpts _ _ fields))))
    = quotedRecord env params fields
quotedDecl env (IFail _ _ ds) = quotedDecls env [] [] ds
quotedDecl env (INamespace _ _ ds) = quotedDecls env [] [] ds
quotedDecl env (ITransform _ _ lhs rhs)
    = findBindableNamesQuot env lhs ++ findBindableNamesQuot env rhs
quotedDecl env (IPragma _ _ _) = []
quotedDecl env (ILog _) = []
quotedDecl env (IBuiltin {}) = []

quotedUpdates : List Name -> List IFieldUpdate -> List (Name, Name)
quotedUpdates env [] = []
quotedUpdates env (ISetField _ t :: upds) = findBindableNamesQuot env t ++ quotedUpdates env upds
quotedUpdates env (ISetFieldApp _ t :: upds) = findBindableNamesQuot env t ++ quotedUpdates env upds

findBindableNames arg env (IVar fc nm) = bindableVar arg env nm
findBindableNames arg env (IPi fc rig p mn aty retty)
    = let env' = case mn of
                      Nothing => env
                      Just n => n :: env in
          findBindableNames True env aty ++
          findBindableNames True env' retty
findBindableNames arg env (ILam fc rig p mn aty sc)
    = let env' = case mn of
                      Nothing => env
                      Just n => n :: env in
      findBindableNames True env aty ++
      findBindableNames True env' sc
findBindableNames arg env (IApp fc fn av)
    = findBindableNames False env fn ++ findBindableNames True env av
findBindableNames arg env (INamedApp fc fn n av)
    = findBindableNames False env fn ++ findBindableNames True env av
findBindableNames arg env (IAutoApp fc fn av)
    = findBindableNames False env fn ++ findBindableNames True env av
findBindableNames arg env (IWithApp fc fn av)
    = findBindableNames False env fn ++ findBindableNames True env av
findBindableNames arg env (IAs fc _ _ nm@(UN (Basic _)) pat)
    = (nm, nm) :: findBindableNames arg env pat
findBindableNames arg env (IAs fc _ _ n pat)
    = findBindableNames arg env pat
findBindableNames arg env (IMustUnify fc r pat)
    = findBindableNames arg env pat
findBindableNames arg env (IDelayed fc r t)
    = findBindableNames arg env t
findBindableNames arg env (IDelay fc t)
    = findBindableNames arg env t
findBindableNames arg env (IForce fc t)
    = findBindableNames arg env t
findBindableNames arg env (IQuote fc t)
    = findBindableNamesQuot env t
findBindableNames arg env (IQuoteDecl fc ds)
    = quotedDecls env [] [] ds
findBindableNames arg env (IAlternative fc u alts)
    = bindableIn arg env alts
-- A name either reading would bind, each written part searched once, so
-- that a tuple nested to any depth costs one search of each part. What
-- each reading holds is read off the terms typeReading and valueReading
-- build: a pair's type former and constructor are variables in function
-- position and the unit's stand where the syntax does, holes hold no name,
-- and the parts stand in argument position in both readings, which hold
-- the same names of them. The dependent pair's value reading refers to its
-- name, and its type reading binds it over the second part: the names that
-- part gives with the name bound are those it gives without, but for the
-- name itself, which the value reading's reference gives. The names are
-- found in the order the readings give them first.
findBindableNames arg env (ITypeOrValue fc (PairOf l r))
    = findBindableNames True env l ++ findBindableNames True env r
findBindableNames arg env (ITypeOrValue fc UnitOf)
    = bindableVar arg env (knownUN KUnit) ++ bindableVar arg env (knownUN KMkUnit)
findBindableNames arg env (ITypeOrValue fc (DPairOf opFC nameFC n r))
    = findBindableNames True (n :: env) r ++ bindableVar True env n
findBindableNames arg env (IUpdate fc updates tm)
    = findBindableNames True env tm ++ bindableUpdated env updates
-- We've skipped case, let and local - rather than guess where the
-- name should be bound, leave it to the programmer
findBindableNames arg env tm = []

findBindableNamesQuot env (IPi fc x y z argTy retTy)
    = findBindableNamesQuot env argTy ++ findBindableNamesQuot env retTy
findBindableNamesQuot env (ILam fc x y z argTy lamTy)
    = findBindableNamesQuot env argTy ++ findBindableNamesQuot env lamTy
findBindableNamesQuot env (ILet fc lhsfc x y nTy nVal scope)
    = findBindableNamesQuot env nTy ++ findBindableNamesQuot env nVal
      ++ findBindableNamesQuot env scope
findBindableNamesQuot env (ICase fc _ x ty cls)
    = quotedClauses env (findBindableNamesQuot env x ++ findBindableNamesQuot env ty) cls
findBindableNamesQuot env (ILocal fc ds x)
    = quotedDecls env (findBindableNamesQuot env x) [] ds
findBindableNamesQuot env (ICaseLocal fc uname internalName args x)
    = findBindableNamesQuot env x
findBindableNamesQuot env (IApp fc x y)
    = findBindableNamesQuot env x ++ findBindableNamesQuot env y
findBindableNamesQuot env (INamedApp fc x y z)
    = findBindableNamesQuot env x ++ findBindableNamesQuot env z
findBindableNamesQuot env (IAutoApp fc x y)
    = findBindableNamesQuot env x ++ findBindableNamesQuot env y
findBindableNamesQuot env (IWithApp fc x y)
    = findBindableNamesQuot env x ++ findBindableNamesQuot env y
findBindableNamesQuot env (IRewrite fc x y)
    = findBindableNamesQuot env x ++ findBindableNamesQuot env y
findBindableNamesQuot env (ICoerced fc x)
    = findBindableNamesQuot env x
findBindableNamesQuot env (IBindHere fc x y)
    = findBindableNamesQuot env y
findBindableNamesQuot env (IUpdate fc upds x)
    = findBindableNamesQuot env x ++ quotedUpdates env upds
findBindableNamesQuot env (IAs fc nfc x y z)
    = findBindableNamesQuot env z
findBindableNamesQuot env (IDelayed fc x y)
    = findBindableNamesQuot env y
findBindableNamesQuot env (IDelay fc x)
    = findBindableNamesQuot env x
findBindableNamesQuot env (IForce fc x)
    = findBindableNamesQuot env x
findBindableNamesQuot env (IUnquote fc x)
    = findBindableNames True env x
findBindableNamesQuot env (IWithUnambigNames fc xs x)
    = findBindableNamesQuot env x
findBindableNamesQuot env (IVar fc x) = []
findBindableNamesQuot env (ISearch fc) = []
findBindableNamesQuot env (IAlternative fc x xs) = []
findBindableNamesQuot env (ITypeOrValue fc x) = []
findBindableNamesQuot env (IBindVar fc x) = []
findBindableNamesQuot env (IPrimVal fc c) = []
findBindableNamesQuot env (IType fc) = []
findBindableNamesQuot env (IHole fc x) = []
findBindableNamesQuot env (Implicit fc bindIfUnsolved) = []
-- These are the ones I'm not sure about
findBindableNamesQuot env (IMustUnify fc x y)
    = findBindableNamesQuot env y
findBindableNamesQuot env (IUnifyLog fc k x)
    = findBindableNamesQuot env x
-- Should f `(g `(List ~(x))) bind "x" as a parameter to "f"?
-- Depends how (or if) recursive quoting works
findBindableNamesQuot env (IQuote fc x) = []
findBindableNamesQuot env (IQuoteName fc x) = []
findBindableNamesQuot env (IQuoteDecl fc xs) = []

-- What a variable contributes: its name, unless it is bound locally.
freeName : (env : List Name) -> Name -> List Name
freeName env n = if not (n `elem` env) then [n] else []

export
findAllNames : (env : List Name) -> RawImp -> List Name

allNamesIn : (env : List Name) -> List RawImp -> List Name
allNamesIn env [] = []
allNamesIn env (t :: ts) = findAllNames env t ++ allNamesIn env ts

allNamesUpdated : (env : List Name) -> List IFieldUpdate -> List Name
allNamesUpdated env [] = []
allNamesUpdated env (ISetField _ t :: upds) = findAllNames env t ++ allNamesUpdated env upds
allNamesUpdated env (ISetFieldApp _ t :: upds) = findAllNames env t ++ allNamesUpdated env upds

findAllNames env (IVar fc n) = freeName env n
findAllNames env (IPi fc rig p mn aty retty)
    = let env' = case mn of
                      Nothing => env
                      Just n => n :: env in
          findAllNames env aty ++ findAllNames env' retty
findAllNames env (ILam fc rig p mn aty sc)
    = let env' = case mn of
                      Nothing => env
                      Just n => n :: env in
      findAllNames env' aty ++ findAllNames env' sc
findAllNames env (IApp fc fn av)
    = findAllNames env fn ++ findAllNames env av
findAllNames env (INamedApp fc fn n av)
    = findAllNames env fn ++ findAllNames env av
findAllNames env (IAutoApp fc fn av)
    = findAllNames env fn ++ findAllNames env av
findAllNames env (IWithApp fc fn av)
    = findAllNames env fn ++ findAllNames env av
findAllNames env (IAs fc _ _ n pat)
    = n :: findAllNames env pat
findAllNames env (IMustUnify fc r pat)
    = findAllNames env pat
findAllNames env (IDelayed fc r t)
    = findAllNames env t
findAllNames env (IDelay fc t)
    = findAllNames env t
findAllNames env (IForce fc t)
    = findAllNames env t
findAllNames env (IQuote fc t)
    = findAllNames env t
findAllNames env (IUnquote fc t)
    = findAllNames env t
findAllNames env (IAlternative fc u alts)
    = allNamesIn env alts
-- The names of both readings, read off the terms typeReading and
-- valueReading build, each written part searched once: each reading's type
-- former or constructor, and the parts, which both readings hold; the
-- dependent pair's second part under the type reading's binder of its
-- name, which gives every name it gives unbound but that one, which the
-- value reading's reference gives; holes hold no name.
findAllNames env (ITypeOrValue fc (PairOf l r))
    = freeName env pairname ++ freeName env mkpairname
      ++ findAllNames env l ++ findAllNames env r
findAllNames env (ITypeOrValue fc UnitOf)
    = freeName env (knownUN KUnit) ++ freeName env (knownUN KMkUnit)
findAllNames env (ITypeOrValue fc (DPairOf opFC nameFC n r))
    = freeName env dpairname ++ findAllNames (n :: env) r
      ++ freeName env mkdpairname ++ freeName env n
findAllNames env (IUpdate fc updates tm)
    = findAllNames env tm
    ++ allNamesUpdated env updates
    ++ concatMap (map (UN . Basic) . getFieldUpdatePath) updates
-- We've skipped case, let and local - rather than guess where the
-- name should be bound, leave it to the programmer
findAllNames env tm = []

-- Find the names in a type that affect the 'using' declarations (i.e.
-- the ones that mean the declaration will be added).
export
findIBindVars : RawImp -> List Name

iBindVarsIn : List RawImp -> List Name
iBindVarsIn [] = []
iBindVarsIn (t :: ts) = findIBindVars t ++ iBindVarsIn ts

iBindVarsUpdated : List IFieldUpdate -> List Name
iBindVarsUpdated [] = []
iBindVarsUpdated (ISetField _ t :: upds) = findIBindVars t ++ iBindVarsUpdated upds
iBindVarsUpdated (ISetFieldApp _ t :: upds) = findIBindVars t ++ iBindVarsUpdated upds

findIBindVars (IPi fc rig p mn aty retty)
    = findIBindVars aty ++ findIBindVars retty
findIBindVars (ILam fc rig p mn aty sc)
    = findIBindVars aty ++ findIBindVars sc
findIBindVars (IApp fc fn av)
    = findIBindVars fn ++ findIBindVars av
findIBindVars (INamedApp fc fn n av)
    = findIBindVars fn ++ findIBindVars av
findIBindVars (IAutoApp fc fn av)
    = findIBindVars fn ++ findIBindVars av
findIBindVars (IWithApp fc fn av)
    = findIBindVars fn ++ findIBindVars av
findIBindVars (IBindVar fc v)
    = [v]
findIBindVars (IDelayed fc r t)
    = findIBindVars t
findIBindVars (IDelay fc t)
    = findIBindVars t
findIBindVars (IForce fc t)
    = findIBindVars t
findIBindVars (IAlternative fc u alts)
    = iBindVarsIn alts
findIBindVars (ITypeOrValue fc (PairOf l r))
    = findIBindVars l ++ findIBindVars r
findIBindVars (ITypeOrValue fc UnitOf) = []
findIBindVars (ITypeOrValue fc (DPairOf _ _ _ r))
    = findIBindVars r
findIBindVars (IUpdate fc updates tm)
    = findIBindVars tm ++ iBindVarsUpdated updates
-- We've skipped case, let and local - rather than guess where the
-- name should be bound, leave it to the programmer
findIBindVars tm = []

-- What a substitution makes of a name standing where it may be replaced:
-- the term given for it, unless the name is bound there.
substFree : (bound : List Name) -> List (Name, RawImp) -> Name ->
            (written : RawImp) -> RawImp
substFree bound ps n written
    = if not (n `elem` bound)
         then case lookup n ps of
                   Just t => t
                   _ => written
         else written

-- A variable, substituted when explicit variable names are and left alone
-- when bound variable names are.
substVar : (bvar : Bool) -> (bound : List Name) -> List (Name, RawImp) ->
           FC -> Name -> RawImp
substVar False bound ps fc n = substFree bound ps n (IVar fc n)
substVar True bound ps fc n = IVar fc n

mutual
  -- Substitute for either an explicit variable name, or a bound variable name
  -- TODO association list should be map (should the `List Name` be a set as well?)
  substNames' : Bool -> List Name -> List (Name, RawImp) ->
                RawImp -> RawImp
  substNames' bvar bound ps (IVar fc n) = substVar bvar bound ps fc n
  substNames' True bound ps (IBindVar fc n) = substFree bound ps n (IBindVar fc n)
  substNames' bvar bound ps (IPi fc r p mn argTy retTy)
      = let bound' = maybe bound (\n => n :: bound) mn in
            IPi fc r p mn (substNames' bvar bound ps argTy)
                          (substNames' bvar bound' ps retTy)
  substNames' bvar bound ps (ILam fc r p mn argTy scope)
      = let bound' = maybe bound (\n => n :: bound) mn in
            ILam fc r p mn (substNames' bvar bound ps argTy)
                           (substNames' bvar bound' ps scope)
  substNames' bvar bound ps (ILet fc lhsFC r n nTy nVal scope)
      = let bound' = n :: bound in
            ILet fc lhsFC r n (substNames' bvar bound ps nTy)
                              (substNames' bvar bound ps nVal)
                              (substNames' bvar bound' ps scope)
  substNames' bvar bound ps (ICase fc opts y ty xs)
      = ICase fc opts
          (substNames' bvar bound ps y) (substNames' bvar bound ps ty)
          (substNamesClauses bvar bound ps xs)
  substNames' bvar bound ps (ILocal fc xs y)
      = let bound' = definedInBlock emptyNS xs ++ bound in
            ILocal fc (substNamesDecls bvar bound ps xs)
                      (substNames' bvar bound' ps y)
  substNames' bvar bound ps (IApp fc fn arg)
      = IApp fc (substNames' bvar bound ps fn) (substNames' bvar bound ps arg)
  substNames' bvar bound ps (INamedApp fc fn y arg)
      = INamedApp fc (substNames' bvar bound ps fn) y (substNames' bvar bound ps arg)
  substNames' bvar bound ps (IAutoApp fc fn arg)
      = IAutoApp fc (substNames' bvar bound ps fn) (substNames' bvar bound ps arg)
  substNames' bvar bound ps (IWithApp fc fn arg)
      = IWithApp fc (substNames' bvar bound ps fn) (substNames' bvar bound ps arg)
  substNames' bvar bound ps (IAlternative fc y xs)
      = IAlternative fc y (substNamesAll bvar bound ps xs)
  -- The dependent pair's type reading binds its name over its second part
  -- and its value reading refers to it, so where that name is substituted
  -- the two readings are two terms, and the site is the generic
  -- alternative over them. Each reading is built over its pieces
  -- substituted: its variables as variables, its part under the type
  -- reading's binder and outside it; the rest of a reading is holes, which
  -- hold no name.
  substNames' bvar bound ps (ITypeOrValue fc (DPairOf opFC nameFC n r))
      = let under = substNames' bvar (n :: bound) ps r
            same = ITypeOrValue fc (DPairOf opFC nameFC n under) in
            case lookup n ps of
                 Just _ =>
                   if n `elem` bound
                      then same
                      else let var = substVar bvar bound ps
                               value = dpairValueReading var opFC nameFC (getFC r) n
                                         (substNames' bvar bound ps r) in
                               IAlternative fc (UniqueDefault value)
                                 [dpairTypeReading var opFC nameFC n under, value]
                 Nothing => same
  substNames' bvar bound ps (ITypeOrValue fc (PairOf l r))
      = ITypeOrValue fc (PairOf (substNames' bvar bound ps l) (substNames' bvar bound ps r))
  substNames' bvar bound ps (ITypeOrValue fc UnitOf)
      = ITypeOrValue fc UnitOf
  substNames' bvar bound ps (ICoerced fc y)
      = ICoerced fc (substNames' bvar bound ps y)
  substNames' bvar bound ps (IAs fc nameFC s y pattern)
      = IAs fc nameFC s y (substNames' bvar bound ps pattern)
  substNames' bvar bound ps (IMustUnify fc r pattern)
      = IMustUnify fc r (substNames' bvar bound ps pattern)
  substNames' bvar bound ps (IDelayed fc r t)
      = IDelayed fc r (substNames' bvar bound ps t)
  substNames' bvar bound ps (IDelay fc t)
      = IDelay fc (substNames' bvar bound ps t)
  substNames' bvar bound ps (IForce fc t)
      = IForce fc (substNames' bvar bound ps t)
  substNames' bvar bound ps (IUpdate fc updates tm)
      = IUpdate fc (substNamesUpdates bvar bound ps updates)
                   (substNames' bvar bound ps tm)
  substNames' bvar bound ps tm = tm

  substNamesAll : Bool -> List Name -> List (Name, RawImp) ->
                  List RawImp -> List RawImp
  substNamesAll bvar bound ps [] = []
  substNamesAll bvar bound ps (t :: ts)
      = substNames' bvar bound ps t :: substNamesAll bvar bound ps ts

  substNamesMaybe : Bool -> List Name -> List (Name, RawImp) ->
                    Maybe RawImp -> Maybe RawImp
  substNamesMaybe bvar bound ps Nothing = Nothing
  substNamesMaybe bvar bound ps (Just t) = Just (substNames' bvar bound ps t)

  substNamesUpdates : Bool -> List Name -> List (Name, RawImp) ->
                      List IFieldUpdate -> List IFieldUpdate
  substNamesUpdates bvar bound ps [] = []
  substNamesUpdates bvar bound ps (ISetField path t :: upds)
      = ISetField path (substNames' bvar bound ps t) :: substNamesUpdates bvar bound ps upds
  substNamesUpdates bvar bound ps (ISetFieldApp path t :: upds)
      = ISetFieldApp path (substNames' bvar bound ps t) :: substNamesUpdates bvar bound ps upds

  substNamesClause' : Bool -> List Name -> List (Name, RawImp) ->
                      ImpClause -> ImpClause
  substNamesClause' bvar bound ps (PatClause fc lhs rhs)
      = let bound' = map snd (findBindableNames True bound lhs)
                     ++ findIBindVars lhs
                     ++ bound in
            PatClause fc (substNames' bvar [] [] lhs)
                         (substNames' bvar bound' ps rhs)
  substNamesClause' bvar bound ps (WithClause fc lhs rig wval prf flags cs)
      = let bound' = map snd (findBindableNames True bound lhs)
                     ++ findIBindVars lhs
                     ++ bound in
            WithClause fc (substNames' bvar [] [] lhs) rig
                          (substNames' bvar bound' ps wval) prf flags cs
  substNamesClause' bvar bound ps (ImpossibleClause fc lhs)
      = ImpossibleClause fc (substNames' bvar bound [] lhs)

  substNamesClauses : Bool -> List Name -> List (Name, RawImp) ->
                      List ImpClause -> List ImpClause
  substNamesClauses bvar bound ps [] = []
  substNamesClauses bvar bound ps (cl :: cls)
      = substNamesClause' bvar bound ps cl :: substNamesClauses bvar bound ps cls

  substNamesTys : Bool -> List Name -> List (Name, RawImp) ->
                  List ImpTy -> List ImpTy
  substNamesTys bvar bound ps [] = []
  substNamesTys bvar bound ps (MkWithFCTyName fc n t :: tys)
      = MkWithFCTyName fc n (substNames' bvar bound ps t) :: substNamesTys bvar bound ps tys

  substNamesData' : Bool -> List Name -> List (Name, RawImp) ->
                    ImpData -> ImpData
  substNamesData' bvar bound ps (MkImpData fc n con opts dcons)
      = MkImpData fc n (substNamesMaybe bvar bound ps con) opts
                  (substNamesTys bvar bound ps dcons)
  substNamesData' bvar bound ps (MkImpLater fc n con)
      = MkImpLater fc n (substNames' bvar bound ps con)

  substNamesDecl' : Bool -> List Name -> List (Name, RawImp ) ->
                   ImpDecl -> ImpDecl
  substNamesDecl' bvar bound ps (IClaim (MkFCVal fc (MkIClaimData rig vis opts (MkWithFCTyName tfc tn ty))))
      = IClaim (MkFCVal fc (MkIClaimData rig vis opts
                              (MkWithFCTyName tfc tn (substNames' bvar bound ps ty))))
  substNamesDecl' bvar bound ps (IDef fc n cs)
      = IDef fc n (substNamesClauses bvar bound ps cs)
  substNamesDecl' bvar bound ps (IData fc vis mbtot d)
      = IData fc vis mbtot (substNamesData' bvar bound ps d)
  substNamesDecl' bvar bound ps (IFail fc msg ds)
      = IFail fc msg (substNamesDecls bvar bound ps ds)
  substNamesDecl' bvar bound ps (INamespace fc ns ds)
      = INamespace fc ns (substNamesDecls bvar bound ps ds)
  substNamesDecl' bvar bound ps d = d

  substNamesDecls : Bool -> List Name -> List (Name, RawImp) ->
                    List ImpDecl -> List ImpDecl
  substNamesDecls bvar bound ps [] = []
  substNamesDecls bvar bound ps (d :: ds)
      = substNamesDecl' bvar bound ps d :: substNamesDecls bvar bound ps ds

export
substNames : List Name -> List (Name, RawImp) ->
             RawImp -> RawImp
substNames = substNames' False

export
substBindVars : List Name -> List (Name, RawImp) ->
                RawImp -> RawImp
substBindVars = substNames' True

export
substNamesClause : List Name -> List (Name, RawImp) ->
                   ImpClause -> ImpClause
substNamesClause = substNamesClause' False

mutual
  export
  substLoc : FC -> RawImp -> RawImp
  substLoc fc' (IVar fc n) = IVar fc' n
  substLoc fc' (IPi fc r p mn argTy retTy)
      = IPi fc' r p mn (substLoc fc' argTy)
                      (substLoc fc' retTy)
  substLoc fc' (ILam fc r p mn argTy scope)
      = ILam fc' r p mn (substLoc fc' argTy)
                        (substLoc fc' scope)
  substLoc fc' (ILet fc lhsFC r n nTy nVal scope)
      = ILet fc' fc' r n (substLoc fc' nTy)
                     (substLoc fc' nVal)
                     (substLoc fc' scope)
  substLoc fc' (ICase fc opts y ty xs)
      = ICase fc' opts (substLoc fc' y) (substLoc fc' ty)
                  (substLocClauses fc' xs)
  substLoc fc' (ILocal fc xs y)
      = ILocal fc' (substLocDecls fc' xs)
                   (substLoc fc' y)
  substLoc fc' (IApp fc fn arg)
      = IApp fc' (substLoc fc' fn) (substLoc fc' arg)
  substLoc fc' (INamedApp fc fn y arg)
      = INamedApp fc' (substLoc fc' fn) y (substLoc fc' arg)
  substLoc fc' (IAutoApp fc fn arg)
      = IAutoApp fc' (substLoc fc' fn) (substLoc fc' arg)
  substLoc fc' (IWithApp fc fn arg)
      = IWithApp fc' (substLoc fc' fn) (substLoc fc' arg)
  substLoc fc' (IAlternative fc y xs)
      = IAlternative fc' y (substLocAll fc' xs)
  substLoc fc' (ITypeOrValue fc (DPairOf _ _ n r))
      = ITypeOrValue fc' (DPairOf fc' fc' n (substLoc fc' r))
  substLoc fc' (ITypeOrValue fc (PairOf l r))
      = ITypeOrValue fc' (PairOf (substLoc fc' l) (substLoc fc' r))
  substLoc fc' (ITypeOrValue fc UnitOf)
      = ITypeOrValue fc' UnitOf
  substLoc fc' (ICoerced fc y)
      = ICoerced fc' (substLoc fc' y)
  substLoc fc' (IAs fc nameFC s y pattern)
      = IAs fc' fc' s y (substLoc fc' pattern)
  substLoc fc' (IMustUnify fc r pattern)
      = IMustUnify fc' r (substLoc fc' pattern)
  substLoc fc' (IDelayed fc r t)
      = IDelayed fc' r (substLoc fc' t)
  substLoc fc' (IDelay fc t)
      = IDelay fc' (substLoc fc' t)
  substLoc fc' (IForce fc t)
      = IForce fc' (substLoc fc' t)
  substLoc fc' (IUpdate fc updates tm)
      = IUpdate fc' (substLocUpdates fc' updates)
                    (substLoc fc' tm)
  substLoc fc' tm = tm

  substLocAll : FC -> List RawImp -> List RawImp
  substLocAll fc' [] = []
  substLocAll fc' (t :: ts) = substLoc fc' t :: substLocAll fc' ts

  substLocMaybe : FC -> Maybe RawImp -> Maybe RawImp
  substLocMaybe fc' Nothing = Nothing
  substLocMaybe fc' (Just t) = Just (substLoc fc' t)

  substLocUpdates : FC -> List IFieldUpdate -> List IFieldUpdate
  substLocUpdates fc' [] = []
  substLocUpdates fc' (ISetField path t :: upds)
      = ISetField path (substLoc fc' t) :: substLocUpdates fc' upds
  substLocUpdates fc' (ISetFieldApp path t :: upds)
      = ISetFieldApp path (substLoc fc' t) :: substLocUpdates fc' upds

  export
  substLocClause : FC -> ImpClause -> ImpClause
  substLocClause fc' (PatClause fc lhs rhs)
      = PatClause fc' (substLoc fc' lhs)
                      (substLoc fc' rhs)
  substLocClause fc' (WithClause fc lhs rig wval prf flags cs)
      = WithClause fc' (substLoc fc' lhs) rig
                       (substLoc fc' wval)
                       prf
                       flags
                       (substLocClauses fc' cs)
  substLocClause fc' (ImpossibleClause fc lhs)
      = ImpossibleClause fc' (substLoc fc' lhs)

  substLocClauses : FC -> List ImpClause -> List ImpClause
  substLocClauses fc' [] = []
  substLocClauses fc' (cl :: cls) = substLocClause fc' cl :: substLocClauses fc' cls

  substLocTys : FC -> List ImpTy -> List ImpTy
  substLocTys fc' [] = []
  substLocTys fc' (MkWithFCTyName _ n t :: tys)
      = MkWithFCTyName fc' n (substLoc fc' t) :: substLocTys fc' tys

  substLocData : FC -> ImpData -> ImpData
  substLocData fc' (MkImpData fc n con opts dcons)
      = MkImpData fc' n (substLocMaybe fc' con) opts
                        (substLocTys fc' dcons)
  substLocData fc' (MkImpLater fc n con)
      = MkImpLater fc' n (substLoc fc' con)

  substLocDecl : FC -> ImpDecl -> ImpDecl
  substLocDecl fc' (IClaim (MkFCVal _ $ MkIClaimData r vis opts (MkWithFCTyName _ n t)))
      = IClaim (MkFCVal fc' $ MkIClaimData r vis opts (MkWithFCTyName fc' n (substLoc fc' t)))
  substLocDecl fc' (IDef fc n cs)
      = IDef fc' n (substLocClauses fc' cs)
  substLocDecl fc' (IData fc vis mbtot d)
      = IData fc' vis mbtot (substLocData fc' d)
  substLocDecl fc' (IFail fc msg ds)
      = IFail fc' msg (substLocDecls fc' ds)
  substLocDecl fc' (INamespace fc ns ds)
      = INamespace fc' ns (substLocDecls fc' ds)
  substLocDecl fc' d = d

  substLocDecls : FC -> List ImpDecl -> List ImpDecl
  substLocDecls fc' [] = []
  substLocDecls fc' (d :: ds) = substLocDecl fc' d :: substLocDecls fc' ds

export
etaExpandImplicits : {auto c : Ref Ctxt Defs} ->
                     {auto u : Ref UST UState} ->
                     FC -> (ty, lhs, rhs : RawImp) ->
                     Core (RawImp, RawImp)
etaExpandImplicits fc ty lhs rhs
    = do let imps = collectImplicits ty
         namedImps <- for imps $ \nm => (nm,) <$> genVarName (known Karg)
         let lhsArgs = namedImps <&> makeArg True
         let rhsArgs = namedImps <&> makeArg False
         pure (apply lhs lhsArgs, apply rhs rhsArgs)
  where
    collectImplicits : RawImp -> List Name
    collectImplicits (IPi _ _ Explicit _        _ ty) = []
    collectImplicits (IPi _ _ _        (Just n) _ ty) = n :: collectImplicits ty
    collectImplicits _                                = []

    ivar : (bind : Bool) -> Name -> RawImp
    ivar True  = IBindVar fc
    ivar False = IVar fc

    makeArg : (bind : Bool) -> (Name, Name) -> Arg
    makeArg bind (n, bindName) = Named fc n $ ivar bind bindName

-- What follows makes fresh names, spelling candidates until one is free,
-- and names arguments from what the evaluator makes of their types. A
-- search ends, given a candidate to spell, because each candidate is a new
-- spelling and the names in use are finitely many, a fact of spellings no
-- part of its arguments shows; the evaluator need not end at all, since
-- Idris's theory is not strongly normalizing. So these are covering, and
-- every walk above is total.
%default covering

-- Appends the ' character to "x" until it is unique with respect to "xs".
-- Each primed spelling is new text, so the session's table makes it an
-- identifier; one already in "xs" is the identifier met before.
export
genUniqueIdent : {auto c : Ref Ctxt Defs} ->
                 (xs : List Ident) -> (x : Ident) -> Core Ident
genUniqueIdent xs x
    = if x `elem` xs then genUniqueIdent xs !(intern (x.text ++ "'")) else pure x

-- As findBindableNames, with each name bound away from the identifiers in
-- 'used'.
export
findUniqueBindableNames :
  {auto c : Ref Ctxt Defs} ->
  FC -> (arg : Bool) -> (env : List Name) -> (used : List Ident) ->
  RawImp -> Core (List (Name, Name))
findUniqueBindableNames fc arg env used t
  = do assoc <- traverse bindApart (nub (findBindableNames arg env t))
       when (showShadowingWarning !getSession) $
         do defs <- get Ctxt
            let ctxt = gamma defs
            ns <- map catMaybes $ for assoc $ \ (n, _) => do
                    ns <- lookupCtxtName n ctxt
                    let ns = flip List.mapMaybe ns $ \(n, _, d) =>
                               case definition d of
                                -- do not warn about holes: `?a` is not actually
                                -- getting shadowed as it will not become a
                                -- toplevel declaration
                                 Hole {} => Nothing
                                 _ => pure n
                    pure $ MkPair n <$> fromList ns
            whenJust (fromList ns) $ recordWarning . ShadowingGlobalDefs fc
       pure assoc
  where
    -- Only a basic user name can meet an identifier in 'used'; any other
    -- is bound as itself.
    bindApart : (Name, Name) -> Core (Name, Name)
    bindApart (nm, UN (Basic n)) = pure (nm, UN (Basic !(genUniqueIdent used n)))
    bindApart bound = pure bound
