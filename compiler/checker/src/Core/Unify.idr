-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Unify

import Core.Case.CaseTree
import Core.Context.Log
import Core.Env
import Core.GetType
import Core.Normalise
import Core.Options
import public Core.UnifyState
import Core.Value

import Data.Maybe

import Libraries.Data.List.SizeOf

import Libraries.Data.VarSet

import Libraries.Data.IntMap
import Libraries.Data.NameMap

%default covering

public export
data UnifyMode = InLHS
               | InTerm
               | InMatch
               | InSearch

-- Need to record if we're at the top level or not, because top level things
-- can have Force and Delay inserted, and may have been postponed.
public export
record UnifyInfo where
  constructor MkUnifyInfo
  atTop : Bool
  umode : UnifyMode

export
inTerm : UnifyInfo
inTerm = MkUnifyInfo True InTerm

export
inLHS : UnifyInfo
inLHS = MkUnifyInfo True InLHS

export
inMatch : UnifyInfo
inMatch = MkUnifyInfo True InMatch

lower : UnifyInfo -> UnifyInfo
lower = { atTop := False }

Eq UnifyMode where
   InLHS == InLHS = True
   InTerm == InTerm = True
   InMatch == InMatch = True
   InSearch == InSearch = True
   _ == _ = False

Eq UnifyInfo where
  x == y = atTop x == atTop y && umode x == umode y

Show UnifyMode where
  show InLHS = "InLHS"
  show InTerm = "InTerm"
  show InMatch = "InMatch"
  show InSearch = "InSearch"

-- If we're unifying a Lazy type with a non-lazy type, we need to add an
-- explicit force or delay to the first argument to unification. This says
-- which to add, if any. Can only added at the very top level.
public export
data AddLazy = NoLazy | AddForce LazyReason | AddDelay LazyReason

export
Show AddLazy where
  show NoLazy = "NoLazy"
  show (AddForce _) = "AddForce"
  show (AddDelay _) = "AddDelay"

public export
record UnifyResult where
  constructor MkUnifyResult
  constraints : List Int
  holesSolved : Bool -- did we solve any holes
  namesSolved : List Int -- which ones did we solve (as name indices)
  addLazy : AddLazy

union : UnifyResult -> UnifyResult -> UnifyResult
union u1 u2 = MkUnifyResult (union (constraints u1) (constraints u2))
                            (holesSolved u1 || holesSolved u2)
                            (namesSolved u1 ++ namesSolved u2)
                            NoLazy -- only top level, so assume no annotation

unionAll : List UnifyResult -> UnifyResult
unionAll [] = MkUnifyResult [] False [] NoLazy
unionAll [c] = c
unionAll (c :: cs) = union c (unionAll cs)

constrain : Int -> UnifyResult
constrain c = MkUnifyResult [c] False [] NoLazy

success : UnifyResult
success = MkUnifyResult [] False [] NoLazy

solvedHole : Int -> UnifyResult
solvedHole n = MkUnifyResult [] True [n] NoLazy

public export
interface Unify tm where
  -- Unify returns a list of ids referring to newly added constraints
  unifyD : {vars : Scope} ->
           Ref Ctxt Defs ->
           Ref UST UState ->
           UnifyInfo ->
           FC -> Env Term vars ->
           tm vars -> tm vars ->
           Core UnifyResult
  -- As unify but at the top level can allow lazy/non-lazy to be mixed in
  -- order to infer annotations
  unifyWithLazyD : {vars : _} ->
                   Ref Ctxt Defs ->
                   Ref UST UState ->
                   UnifyInfo ->
                   FC -> Env Term vars ->
                   tm vars -> tm vars ->
                   Core UnifyResult
  unifyWithLazyD = unifyD

-- Workaround for auto implicits not working in interfaces
-- In calls to unification, the first argument is the given type, and the second
-- argument is the expected type.
export
unify : Unify tm =>
        {vars : _} ->
        {auto c : Ref Ctxt Defs} ->
        {auto u : Ref UST UState} ->
        UnifyInfo ->
        FC -> Env Term vars ->
        tm vars -> tm vars ->
        Core UnifyResult
unify {c} {u} = unifyD c u

export
unifyWithLazy : Unify tm =>
                {vars : _} ->
                {auto c : Ref Ctxt Defs} ->
                {auto u : Ref UST UState} ->
                UnifyInfo ->
                FC -> Env Term vars ->
                tm vars -> tm vars ->
                Core UnifyResult
unifyWithLazy {c} {u} = unifyWithLazyD c u

||| How an automatic search's goals grow along one of its paths: through
||| unknowns a later round of elaboration may fix, or with every part of both
||| goals known, when no later round can change the search.
public export
data Growth = ThroughUnknowns | Settled

||| A search that grew: a later goal of one of its paths into which an
||| earlier goal of the same type constructor embeds. The goals are closed
||| over their environments and read in the context the search had when it
||| met them, which holds the unknowns its own steps made; the names are the
||| hints the search applied between them, in order.
public export
record Grown where
  constructor MkGrown
  growth : Growth
  context : Context
  earlier : ClosedTerm
  later : ClosedTerm
  hints : List Name

||| A search that met a goal again: a later goal of one of its paths
||| convertible with an earlier one. The search finds nothing there for the
||| goal it sought, which is closed and read in the context the search had
||| when it met the repeat.
public export
record Repeat where
  constructor MkRepeat
  context : Context
  sought : ClosedTerm

||| What a step of the automatic search gives when it throws no error: what
||| it found, a goal it repeated, or the growth that stopped it. A repeat
||| fails the step, as upstream's cycle check does, and as an error does:
||| each of the search's choices undoes it and tries what else it has. A
||| growth fails nothing, so no choice can let a sibling answer instead:
||| each passes it up, and the whole search ends with it. All three are
||| values, so every combinator passes each up by its type.
public export
data Searched : Type -> Type where
  Found : a -> Searched a
  Repeated : Repeat -> Searched a
  Grows : Grown -> Searched a

export
Functor Searched where
  map f (Found a) = Found (f a)
  map f (Repeated r) = Repeated r
  map f (Grows g) = Grows g

-- Defined in Core.AutoSearch. A search that finds nothing, by a repeat or a
-- growth, leaves nothing of itself behind: the unknowns and solutions its
-- steps made are undone, so the search is retried, or refused, whole.
export
search : {vars : _} ->
         {auto c : Ref Ctxt Defs} ->
         {auto u : Ref UST UState} ->
         FC -> RigCount ->
         (defaults : Bool) ->
         (defining : Name) -> (topTy : Term vars) -> Env Term vars ->
         Core (Searched (Term vars))

ufail : FC -> String -> Core a
ufail loc msg = throw (GenericMsg loc msg)

convertError : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               FC -> Env Term vars -> NF vars -> NF vars -> Core a
convertError loc env x y
    = do defs <- get Ctxt
         empty <- clearDefs defs
         throw (CantConvert loc (gamma defs)
                                env !(quote empty env x)
                                    !(quote empty env y))

convertErrorS : {vars : _} ->
                {auto c : Ref Ctxt Defs} ->
                Bool -> FC -> Env Term vars -> NF vars -> NF vars -> Core a
convertErrorS s loc env x y
    = if s then convertError loc env y x
           else convertError loc env x y

-- Find all the metavariables required by each of the given names.
-- We'll assume all meta solutions are of the form STerm exp.
chaseMetas : {auto c : Ref Ctxt Defs} ->
             List Name -> NameMap () -> Core (List Name)
chaseMetas [] all = pure (keys all)
chaseMetas (n :: ns) all
    = case lookup n all of
           Just _ => chaseMetas ns all
           _ => do defs <- get Ctxt
                   Just (PMDef _ args body) <- lookupDefExact n (gamma defs)
                        | _ => chaseMetas ns (insert n () all)
                   -- Only a tree that is one leaf holds a solution, and only
                   -- that leaf is decoded.
                   sns <- walkTree body (\leaf, tree => case tree of
                            STerm _ x => do soln <- leafTerm leaf {outer = []} x
                                            pure (keys (getMetas soln))
                            _ => pure [])
                   chaseMetas (sns ++ ns) (insert n () all)

-- Get all the metavariable names used by the term (recursively, so we
-- can do the occurs check)
getMetaNames : {auto c : Ref Ctxt Defs} ->
               Term vars -> Core (List Name)
getMetaNames tm
    = let metas = getMetas tm in
          chaseMetas (keys metas) empty

postpone : {vars : _} ->
           {auto c : Ref Ctxt Defs} ->
           {auto u : Ref UST UState} ->
           FC -> UnifyInfo -> String ->
           Env Term vars -> NF vars -> NF vars -> Core UnifyResult
postpone loc mode logstr env x y
    = do defs <- get Ctxt
         empty <- clearDefs defs
         logC "unify.postpone" 10 $
              do xq <- quote defs env x
                 yq <- quote defs env y
                 pure (logstr ++ ": " ++ show !(toFullNames xq) ++
                                    " =?= " ++ show !(toFullNames yq))

         -- If we're blocked because a name is undefined, give up
         checkDefined defs x
         checkDefined defs y

         c <- addConstraint (MkConstraint loc (atTop mode) env x y)
         log "unify.postpone" 10 $
                 show c ++ " NEW CONSTRAINT " ++ show loc
         logNF "unify.postpone" 10 "X" env x
         logNF "unify.postpone" 10 "Y" env y
         pure (constrain c)
  where
    checkDefined : Defs -> NF vars -> Core ()
    checkDefined defs (NApp _ (NRef _ n) _)
        = do Just _ <- lookupCtxtExact n (gamma defs)
                  | _ => undefinedName loc n
             pure ()
    checkDefined _ _ = pure ()

    undefinedN : Name -> Core Bool
    undefinedN n
        = do defs <- get Ctxt
             pure $ case !(lookupDefExact n (gamma defs)) of
                  Just (Hole {}) => True
                  Just (BySearch {}) => True
                  Just (Guess {}) => True
                  _ => False

postponeS : {vars : _} ->
            {auto c : Ref Ctxt Defs} ->
            {auto u : Ref UST UState} ->
            Bool -> FC -> UnifyInfo -> String -> Env Term vars ->
            NF vars -> NF vars ->
            Core UnifyResult
postponeS s loc mode logstr env x y
    = if s then postpone loc (lower mode) logstr env y x
           else postpone loc mode logstr env x y

unifyArgs : (Unify tm, Quote tm) =>
            {vars : _} ->
            {auto c : Ref Ctxt Defs} ->
            {auto u : Ref UST UState} ->
            UnifyInfo -> FC -> Env Term vars ->
            List (tm vars) -> List (tm vars) ->
            Core UnifyResult
unifyArgs mode loc env [] [] = pure success
unifyArgs mode loc env (cx :: cxs) (cy :: cys)
    = do -- Do later arguments first, since they may depend on earlier
         -- arguments and use their solutions.
         cs <- unifyArgs mode loc env cxs cys
         res <- unify (lower mode) loc env cx cy
         pure (union res cs)
unifyArgs mode loc env _ _ = ufail loc ""

-- Get the variables in an application argument list; fail if any arguments
-- are not variables, fail if there's any repetition of variables
-- We use this to check that the pattern unification rule is applicable
-- when solving a metavariable applied to arguments
-- We return a list (because the order matters) and a set (for easy
-- querying)
getVars : List (NF vars) -> Maybe (List (Var vars), VarSet vars)
getVars = go [<] VarSet.empty where

  go : SnocList (Var vars) -> VarSet vars ->
       List (NF vars) -> Maybe (List (Var vars), VarSet vars)
  go acc got [] = Just (acc <>> [], got)
  go acc got (NErased fc (Dotted t) :: xs) = go acc got (t :: xs)
  go acc got (NApp fc (NLocal r idx p) [] :: xs)
    = let v := MkVar p in
      if v `VarSet.elem` got then Nothing
         else go (acc :< v) (VarSet.insert v got) xs
  go acc got (NAs _ _ _ p :: xs) = go acc got (p :: xs)
  go acc _ (_ :: xs) = Nothing

-- Update the variable list to point into the sub environment
-- (All of these will succeed because the Thin we have comes from
-- the list of variable uses! It's not stated in the type, though.)
updateVars : List (Var {a = Name} vars) -> Thin newvars vars -> List (Var newvars)
updateVars vs th = mapMaybe (\ v => shrink v th) vs

{- Applying the pattern unification rule is okay if:
   * Arguments are all distinct local variables
   * The metavariable name doesn't appear in the unifying term
   * The local variables which appear in the term are all arguments to
     the metavariable application (not checked here, checked with the
     result of `patternEnv`)

   Return the subset of the environment used in the arguments
   to which the metavariable is applied. If this environment is enough
   to check the term we're unifying with, and that term doesn't use the
   metavariable name, we can safely apply the rule.

   Also, return the list of arguments the metavariable was applied to, to
   make sure we use them in the right order when we build the solution.
-}
patternEnv : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             {vars : _} ->
             Env Term vars -> List (Closure vars) ->
             Core (Maybe (newvars ** (List (Var newvars),
                                     Thin newvars vars)))
patternEnv {vars} env args
    = do defs <- get Ctxt
         empty <- clearDefs defs
         args' <- traverse (evalArg empty) args
         pure $
           case getVars args' of
             Nothing => Nothing
             Just (vslist, vsset) =>
               let (newvars ** svs) = fromVarSet _ vsset in
                 Just (newvars ** (updateVars vslist svs, svs))

getVarsTm : List (Term vars) -> Maybe (List (Var vars), VarSet vars)
getVarsTm = go [<] VarSet.empty where

  go : SnocList (Var vars) -> VarSet vars ->
       List (Term vars) -> Maybe (List (Var vars), VarSet vars)
  go acc got [] = Just (acc <>> [], got)
  go acc got (Local fc r idx p :: xs)
    = let v := MkVar p in
      if v `VarSet.elem` got then Nothing
         else go (acc :< v) (VarSet.insert v got) xs
  go acc _ (_ :: xs) = Nothing

export
patternEnvTm : {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               {vars : _} ->
               Env Term vars -> List (Term vars) ->
               Core (Maybe (newvars ** (List (Var newvars),
                                       Thin newvars vars)))
patternEnvTm {vars} env args
    = do defs <- get Ctxt
         empty <- clearDefs defs
         pure $ case getVarsTm args of
           Nothing => Nothing
           Just (vslist, vsset) =>
             let (newvars ** svs) = fromVarSet _ vsset in
                 Just (newvars ** (updateVars vslist svs, svs))

-- Check that the metavariable name doesn't occur in the solution.
-- If it does, normalising might help. If it still does, that's an error.
occursCheck : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              FC -> Env Term vars -> UnifyInfo ->
              Name -> Term vars -> Core (Maybe (Term vars))
occursCheck fc env mode mname tm
    = do solmetas <- getMetaNames tm
         let False = mname `elem` solmetas
             | _ => do defs <- get Ctxt
                       tmnf <- normalise defs env tm
                       solmetas <- getMetaNames tmnf
                       if mname `elem` solmetas
                          then do failOnStrongRigid False
                                     (throw (CyclicMeta fc env mname tmnf))
                                     tmnf
                                  pure Nothing
                          else pure $ Just tmnf
         pure $ Just tm
  where
    -- Throw an occurs check failure if the name appears 'strong rigid',
    -- that is, under a constructor form rather than a function, in the
    -- term
    failOnStrongRigid : Bool -> Core () -> Term vars -> Core ()
    failOnStrongRigid bad err (Meta _ n _ _)
        = if bad && n == mname
             then err
             else pure ()
    failOnStrongRigid bad err tm
        = case getFnArgs tm of
               (f, []) => pure ()
               (Ref _ Func _, _) => pure () -- might reduce away, just block
               (Ref _ _ _, args) => traverse_ (failOnStrongRigid True err) args
               (f, args) => traverse_ (failOnStrongRigid bad err) args

-- How the variables in a metavariable definition map to the variables in
-- the solution term (the Var newvars)
--
-- TODO factor out as a renaming
-- TODO use `All` "quantifier"
data IVars : Scope -> Scoped where
     INil : IVars Scope.empty newvars
     ICons : Maybe (Var newvars) -> IVars vs newvars ->
             IVars (v :: vs) newvars

Weaken (IVars vs) where
  weakenNs s INil = INil
  weakenNs s (ICons t ts) = ICons (weakenNs @{MaybeWeaken} s t) (weakenNs s ts)

getIVars : IVars vs ns -> List (Maybe (Var ns))
getIVars INil = []
getIVars (ICons v vs) = v :: getIVars vs

-- Instantiate a metavariable by binding the variables in 'newvars'
-- and returning the term
-- If the type of the metavariable doesn't have enough arguments, fail, because
-- this wasn't valid for pattern unification
tryInstantiate : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              {vars, newvars : _} ->
              FC -> UnifyInfo -> Env Term vars ->
              (metavar : Name) -> (mref : Int) -> (numargs : Nat) ->
              (mdef : GlobalDef) ->
              List (Var newvars) -> -- Variable each argument maps to
              Term vars -> -- original, just for error message
              Term newvars -> -- shrunk environment
              Core Bool -- postpone if the type is yet unknown
tryInstantiate {newvars} loc mode env mname mref num mdef locs otm tm
    = do logTerm "unify.instantiate" 5 ("Instantiating in " ++ show newvars) tm
--          let Hole _ _ = definition mdef
--              | def => ufail {a=()} loc (show mname ++ " already resolved as " ++ show def)
         case fullname mdef of
              PV pv pi => throw (PatternVariableUnifies loc (getLoc otm) env (PV pv pi) otm)
              _ => pure ()
         defs <- get Ctxt
         mty <- typeOf mdef
         ty <- normalisePis defs Env.empty mty
                     -- make sure we have all the pi binders we need in the
                     -- type to make the metavariable definition
         logTerm "unify.instantiate" 5 ("Type: " ++ show mname) mty
         logTerm "unify.instantiate" 5 ("Type: " ++ show mname) ty
         log "unify.instantiate" 5 ("With locs: " ++ show locs)
         log "unify.instantiate" 5 ("From vars: " ++ show newvars)

         defs <- get Ctxt
         -- Try to instantiate the hole
         Just rhs <- mkDef locs INil tm ty
           | _ => do
               log "unify.instantiate" 5 "Postponed"
               pure False

         logTerm "unify.instantiate" 5 "Definition" rhs
         let simpleDef = MkPMDefInfo (SolvedHole num)
                                     (not (isUserName mname) && isSimple rhs)
         let newdef = { definition :=
                          PMDef simpleDef Scope.empty (LiveBody (STerm 0 rhs) [] [])
                      } mdef
         ignore $ addDef (Resolved mref) newdef
         -- Meta-to-meta unification: an unknown solved as another's
         -- application is one class with it, its value the other's.
         case tm of
              Meta _ _ other _ => mergeUnknowns mref other
              _ => pure ()
         removeHole mref
         pure True
  where
    precise : Bool
    precise
        = case definition mdef of
               Hole _ p => precisetype p
               _ => False

    -- A solution is deemed simple enough to inline if either:
    --   * It is smaller than some threshold and has no metavariables in it
    --   * It's just a metavariable itself
    -- The thresholds (6 and 3 below) decide only whether the solved hole is
    -- unfolded where it is used, so the form of the checked term the TTC
    -- stores, never whether the program is accepted.
    noMeta : Term vs -> Nat -> Bool
    noMeta (App _ f a) (S k) = noMeta f k && noMeta a k
    noMeta (Bind _ _ b sc) (S k) = noMeta (binderType b) k && noMeta sc k
    noMeta (Meta {}) d = False
    noMeta (TDelayed _ _ t) d = noMeta t d
    noMeta (TDelay _ _ t a) d = noMeta t d && noMeta a d
    noMeta (TForce _ _ t) d = noMeta t d
    noMeta (As _ _ a p) d = noMeta a d && noMeta p d
    noMeta (Local {}) _ = True
    noMeta (Ref {}) _ = True
    noMeta (PrimVal {}) _ = True
    noMeta (TType {}) _ = True
    noMeta _ _ = False

    isSimple : Term vs -> Bool
    isSimple (Meta {}) = True
    isSimple (Bind _ _ (Lam {}) sc) = isSimple sc
    isSimple (App _ f a) = noMeta f 6 && noMeta a 3
    isSimple tm = noMeta tm 0

    updateIVar : forall vs, newvars . IVars vs newvars -> Var newvars ->
                 Maybe (Var vs)
    updateIVar (ICons Nothing rest) new
        = later <$> updateIVar rest new
    updateIVar (ICons (Just old) rest) new
        = if new == old
             then Just first
             else later <$> updateIVar rest new
    updateIVar _ _ = Nothing

    updateIVars : {vs, newvars : _} ->
                  IVars vs newvars -> Term newvars -> Maybe (Term vs)
    updateIVars ivs (Local fc r idx p)
        = do MkVar p' <- updateIVar ivs (MkVar p)
             Just (Local fc r _ p')
    updateIVars ivs (Ref fc nt n) = pure $ Ref fc nt n
    updateIVars ivs (Meta fc n i args)
        = pure $ Meta fc n i !(traverse (updateIVars ivs) args)
    updateIVars {vs} ivs (Bind fc x b sc)
        = do b' <- updateIVarsB ivs b
             sc' <- updateIVars (ICons (Just first) (weaken ivs)) sc
             Just (Bind fc x b' sc')
      where
        updateIVarsPi : {vs, newvars : _} ->
                        IVars vs newvars -> PiInfo (Term newvars) -> Maybe (PiInfo (Term vs))
        updateIVarsPi ivs Explicit = Just Explicit
        updateIVarsPi ivs Implicit = Just Implicit
        updateIVarsPi ivs AutoImplicit = Just AutoImplicit
        updateIVarsPi ivs (DefImplicit t)
            = do t' <- updateIVars ivs t
                 Just (DefImplicit t')

        updateIVarsB : {vs, newvars : _} ->
                       IVars vs newvars -> Binder (Term newvars) -> Maybe (Binder (Term vs))
        updateIVarsB ivs (Lam fc c p t)
            = do p' <- updateIVarsPi ivs p
                 Just (Lam fc c p' !(updateIVars ivs t))
        updateIVarsB ivs (Let fc c v t) = Just (Let fc c !(updateIVars ivs v) !(updateIVars ivs t))
        -- Make 'pi' binders have multiplicity W when we infer a Rig1 metavariable,
        -- since this is the most general thing to do if it's unknown.
        updateIVarsB ivs (Pi fc rig p t)
            = do p' <- updateIVarsPi ivs p
                 Just (Pi fc rig p' !(updateIVars ivs t))
        updateIVarsB ivs (PVar fc c p t)
            = do p' <- updateIVarsPi ivs p
                 Just (PVar fc c p' !(updateIVars ivs t))
        updateIVarsB ivs (PLet fc c v t) = Just (PLet fc c !(updateIVars ivs v) !(updateIVars ivs t))
        updateIVarsB ivs (PVTy fc c t) = Just (PVTy fc c !(updateIVars ivs t))
    updateIVars ivs (App fc f a)
        = Just (App fc !(updateIVars ivs f) !(updateIVars ivs a))
    updateIVars ivs (As fc u a p)
        = Just (As fc u !(updateIVars ivs a) !(updateIVars ivs p))
    updateIVars ivs (TDelayed fc r arg)
        = Just (TDelayed fc r !(updateIVars ivs arg))
    updateIVars ivs (TDelay fc r ty arg)
        = Just (TDelay fc r !(updateIVars ivs ty) !(updateIVars ivs arg))
    updateIVars ivs (TForce fc r arg)
        = Just (TForce fc r !(updateIVars ivs arg))
    updateIVars ivs (PrimVal fc c) = Just (PrimVal fc c)
    updateIVars ivs (Erased fc Impossible) = Just (Erased fc Impossible)
    updateIVars ivs (Erased fc Placeholder) = Just (Erased fc Placeholder)
    updateIVars ivs (Erased fc (Dotted t)) = Erased fc . Dotted <$> updateIVars ivs t
    updateIVars ivs (TType fc u) = Just (TType fc u)

    mkDef : {vs, newvars : _} ->
            List (Var newvars) ->
            IVars vs newvars -> Term newvars -> Term vs ->
            Core (Maybe (Term vs))
    mkDef (v :: vs) vars soln (Bind bfc x (Pi fc c info ty) sc)
       = do sc' <- mkDef vs (ICons (Just v) vars) soln sc
            pure $ (Bind bfc x (Lam fc c info (Erased bfc Placeholder)) <$> sc')
    mkDef vs vars soln (Bind bfc x b@(Let _ c val ty) sc)
       = do mbsc' <- mkDef vs (ICons Nothing vars) soln sc
            flip traverseOpt mbsc' $ \sc' =>
              case shrink sc' (Drop Refl) of
                Just scs => pure scs
                Nothing => pure $ Bind bfc x b sc'
    mkDef [] vars soln _
       = do let Just soln' = updateIVars vars soln
                | Nothing => ufail loc ("Can't make solution for " ++ show mname
                                           ++ " " ++ show (getIVars vars, soln))
            pure (Just soln')
    mkDef _ _ _ _ = pure Nothing

-- update a solution that the machine found with the thing the programmer
-- actually wrote! We assume that we've already checked that they unify.
export
updateSolution : {vars : _} ->
                 {auto c : Ref Ctxt Defs} ->
                 {auto u : Ref UST UState} ->
                 Env Term vars -> Term vars -> Term vars -> Core Bool
updateSolution env (Meta fc mname idx args) soln
    = do defs <- get Ctxt
         case !(patternEnvTm env args) of
              Nothing => pure False
              Just (newvars ** (locs, submv)) =>
                  case shrink soln submv of
                       Nothing => pure False
                       Just stm =>
                          do Just hdef <- lookupCtxtExact (Resolved idx) (gamma defs)
                                  | Nothing => throw (InternalError "Can't happen: no definition")
                             tryInstantiate fc inTerm env mname idx (length args) hdef (toList locs) soln stm
updateSolution env metavar soln
    = pure False

export
solveIfUndefined : {vars : _} ->
                   {auto c : Ref Ctxt Defs} ->
                   {auto u : Ref UST UState} ->
                   Env Term vars -> Term vars -> Term vars -> Core Bool
solveIfUndefined env metavar@(Meta fc mname idx args) soln
    = do defs <- get Ctxt
         Just (Hole {}) <- lookupDefExact (Resolved idx) (gamma defs)
              | _ => pure False
         updateSolution env metavar soln
solveIfUndefined env (Erased _ (Dotted metavar)) soln
  = solveIfUndefined env metavar soln
solveIfUndefined env metavar soln
    = pure False

isDefInvertible : {auto c : Ref Ctxt Defs} ->
                  FC -> Int -> Core Bool
isDefInvertible fc i
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact (Resolved i) (gamma defs)
              | Nothing => throw (UndefinedName fc (Resolved i))
         pure (invertible gdef)

mutual
  unifyIfEq : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              {vars : _} ->
              (postpone : Bool) ->
              FC -> UnifyInfo -> Env Term vars -> NF vars -> NF vars ->
              Core UnifyResult
  unifyIfEq post loc mode env x y
        = do defs <- get Ctxt
             if !(convertInf defs env x y)
                then pure success
                else if post
                        then postpone loc mode ("Postponing unifyIfEq " ++
                                                 show (atTop mode)) env x y
                        else convertError loc env x y

  getArgTypes : {vars : _} ->
                {auto c : Ref Ctxt Defs} ->
                Defs -> (fnType : NF vars) -> List (Closure vars) ->
                Core (Maybe (List (NF vars)))
  getArgTypes defs (NBind _ n (Pi _ _ _ ty) sc) (a :: as)
     = do Just scTys <- getArgTypes defs !(sc defs a) as
               | Nothing => pure Nothing
          pure (Just (!(evalClosure defs ty) :: scTys))
  getArgTypes _ _ [] = pure (Just [])
  getArgTypes _ _ _ = pure Nothing

  headsConvert : {vars : _} ->
                 {auto c : Ref Ctxt Defs} ->
                 {auto u : Ref UST UState} ->
                 UnifyInfo ->
                 FC -> Env Term vars ->
                 Maybe (List (NF vars)) -> Maybe (List (NF vars)) ->
                 Core Bool
  headsConvert mode fc env (Just vs) (Just ns)
      = case (reverse vs, reverse ns) of
             (v :: _, n :: _) =>
                do logNF "unify.head" 10 "Unifying head" env v
                   logNF "unify.head" 10 ".........with" env n
                   res <- unify mode fc env v n
                   -- If there's constraints, we postpone the whole equation
                   -- so no need to record them
                   pure (isNil (constraints res ))
             _ => pure False
  headsConvert mode fc env _ _
      = do log "unify.head" 10 "Nothing to convert"
           pure True

  unifyInvertible : {auto c : Ref Ctxt Defs} ->
                    {auto u : Ref UST UState} ->
                    {vars : _} ->
                    (swaporder : Bool) ->
                    UnifyInfo -> FC -> Env Term vars ->
                    (metaname : Name) -> (metaref : Int) ->
                    (margs : List (Closure vars)) ->
                    (margs' : List (Closure vars)) ->
                    Maybe ClosedTerm ->
                    (List (FC, Closure vars) -> NF vars) ->
                    List (FC, Closure vars) ->
                    Core UnifyResult
  unifyInvertible swap mode fc env mname mref margs margs' nty con args'
      = do defs <- get Ctxt
           -- Get the types of the arguments to ensure that the rightmost
           -- argument types match up
           Just vty <- lookupTyExact (Resolved mref) (gamma defs)
                | Nothing => ufail fc ("No such metavariable " ++ show mname)
           vargTys <- getArgTypes defs !(nf defs env (embed vty)) (margs ++ margs')
           nargTys <- maybe (pure Nothing)
                            (\ty => getArgTypes defs !(nf defs env (embed ty)) $ map snd args')
                            nty
           -- If the rightmost arguments have the same type, or we don't
           -- know the types of the arguments, we'll get on with it.
           if !(headsConvert mode fc env vargTys nargTys)
              then
                -- Unify the rightmost arguments, with the goal of turning the
                -- hole application into a pattern form
                case (reverse margs', reverse args') of
                     (h :: hargs, f :: fargs) =>
                        tryUnify
                          (if not swap then
                              do log "unify.invertible" 10 "Unifying invertible"
                                 ures <- unify mode fc env h (snd f)
                                 log "unify.invertible" 10 $ "Constraints " ++ show (constraints ures)
                                 uargs <- unify mode fc env
                                       (NApp fc (NMeta mname mref margs) (reverse $ map (EmptyFC,) hargs))
                                       (con (reverse fargs))
                                 pure (union ures uargs)
                             else
                              do log "unify.invertible" 10 "Unifying invertible"
                                 ures <- unify mode fc env (snd f) h
                                 log "unify.invertible" 10 $ "Constraints " ++ show (constraints ures)
                                 uargs <- unify mode fc env
                                       (con (reverse fargs))
                                       (NApp fc (NMeta mname mref margs) (reverse $ map (EmptyFC,) hargs))
                                 pure (union ures uargs))
                          (postponeS swap fc mode "Postponing hole application [1]" env
                                (NApp fc (NMeta mname mref margs) $ map (EmptyFC,) margs')
                                (con args'))
                     _ => postponeS swap fc mode "Postponing hole application [2]" env
                                (NApp fc (NMeta mname mref margs) (map (EmptyFC,) margs'))
                                (con args')
              else -- TODO: Cancellable function applications
                   postpone fc mode "Postponing hole application [3]" env
                            (NApp fc (NMeta mname mref margs) (map (EmptyFC,) margs')) (con args')

  -- Unify a hole application - we have already checked that the hole is
  -- invertible (i.e. it's a determining argument to a proof search where
  -- it is a constructor or something else invertible in each case)
  unifyHoleApp : {auto c : Ref Ctxt Defs} ->
                 {auto u : Ref UST UState} ->
                 {vars : _} ->
                 (swaporder : Bool) ->
                 UnifyInfo -> FC -> Env Term vars ->
                 (metaname : Name) -> (metaref : Int) ->
                 (margs : List (Closure vars)) ->
                 (margs' : List (Closure vars)) ->
                 NF vars ->
                 Core UnifyResult
  unifyHoleApp swap mode loc env mname mref margs margs' (NTCon nfc n a args')
      = do defs <- get Ctxt
           mty <- lookupTyExact n (gamma defs)
           unifyInvertible swap (lower mode) loc env mname mref margs margs' mty (NTCon nfc n a) args'
  unifyHoleApp swap mode loc env mname mref margs margs' (NDCon nfc n t a args')
      = do defs <- get Ctxt
           mty <- lookupTyExact n (gamma defs)
           unifyInvertible swap (lower mode) loc env mname mref margs margs' mty (NDCon nfc n t a) args'
  unifyHoleApp swap mode loc env mname mref margs margs' (NApp nfc (NLocal r idx p) args')
      = unifyInvertible swap (lower mode) loc env mname mref margs margs' Nothing
                        (NApp nfc (NLocal r idx p)) args'
  unifyHoleApp swap mode loc env mname mref margs margs' tm@(NApp nfc (NMeta n i margs2) args2')
      = do defs <- get Ctxt
           Just mdef <- lookupCtxtExact (Resolved i) (gamma defs)
                | Nothing => undefinedName nfc mname
           let inv = isPatName n || invertible mdef
           if inv
              then unifyInvertible swap (lower mode) loc env mname mref margs margs' Nothing
                                   (NApp nfc (NMeta n i margs2)) args2'
              else postponeS swap loc mode "Postponing hole application" env
                             (NApp loc (NMeta mname mref margs) $ map (EmptyFC,) margs') tm
    where
      isPatName : Name -> Bool
      isPatName (PV {}) = True
      isPatName _ = False

  unifyHoleApp swap mode loc env mname mref margs margs' tm
      = postponeS swap loc mode "Postponing hole application" env
                 (NApp loc (NMeta mname mref margs) $ map (EmptyFC,) margs') tm

  postponePatVar : {auto c : Ref Ctxt Defs} ->
                   {auto u : Ref UST UState} ->
                   {vars : _} ->
                   (swaporder : Bool) ->
                   UnifyInfo -> FC -> Env Term vars ->
                   (metaname : Name) -> (metaref : Int) ->
                   (margs : List (Closure vars)) ->
                   (margs' : List (Closure vars)) ->
                   (soln : NF vars) ->
                   Core UnifyResult
  postponePatVar swap mode loc env mname mref margs margs' tm
      = do let x = NApp loc (NMeta mname mref margs) (map (EmptyFC,) margs')
           defs <- get Ctxt
           if !(convert defs env x tm)
              then pure success
              else postponeS swap loc mode "Not in pattern fragment" env
                             x tm

  solveHole : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              {newvars, vars : _} ->
              FC -> UnifyInfo -> Env Term vars ->
              (metaname : Name) -> (metaref : Int) ->
              -- The hole's definition, as the caller found it
              (hdef : GlobalDef) ->
              (margs : List (Closure vars)) ->
              (margs' : List (Closure vars)) ->
              List (Var newvars) ->
              Thin newvars vars ->
              (solfull : Term vars) -> -- Original solution
              (soln : Term newvars) -> -- Solution with shrunk environment
              (solnf : NF vars) ->
              Core (Maybe UnifyResult)
  solveHole loc mode env mname mref hdef margs margs' locs submv solfull stm solnf
      = do ust <- get UST
           -- if the terms are the same, this isn't a solution
           -- but they are already unifying, so just return
           if solutionHeadSame solnf || inNoSolve mref (noSolve ust)
              then pure $ Just success
              else -- Rather than doing the occurs check here immediately,
                   -- we'll wait until all metavariables are resolved, and in
                   -- the meantime look out for cycles when normalising (which
                   -- is cheap enough because we only need to look out for
                   -- metavariables)
                   do progress <- tryInstantiate loc mode env mname mref (length margs) hdef (toList locs) solfull stm
                      pure $ toMaybe progress (solvedHole mref)
    where
      inNoSolve : Int -> IntMap () -> Bool
      inNoSolve i ns
          = case lookup i ns of
                 Nothing => False
                 Just _ => True

      -- Only need to check the head metavar is the same, we've already
      -- checked the rest if they are the same (and we couldn't instantiate it
      -- anyway...)
      solutionHeadSame : NF vars -> Bool
      solutionHeadSame (NApp _ (NMeta _ shead _) _) = shead == mref
      solutionHeadSame _ = False

  unifyHole : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              {vars : _} ->
              (swaporder : Bool) ->
              UnifyInfo -> FC -> Env Term vars ->
              FC -> (metaname : Name) -> (metaref : Int) ->
              (args : List (Closure vars)) ->
              (args' : List (Closure vars)) ->
              (soln : NF vars) ->
              Core UnifyResult
  unifyHole swap mode loc env fc mname mref margs margs' tmnf
      = do defs <- get Ctxt
           empty <- clearDefs defs
           let args = if isNil margs' then margs else margs ++ margs'
           logC "unify.hole" 10
                   (do args' <- traverse (evalArg empty) args
                       qargs <- traverse (quote empty env) args'
                       qtm <- quote empty env tmnf
                       pure $ "Unifying: " ++ show mname ++ " " ++ show qargs ++
                              " with " ++ show qtm) -- first attempt, try 'empty', only try 'defs' when on 'retry'?
           case !(patternEnv env args) of
                Nothing =>
                  do Just hdef <- lookupCtxtExact (Resolved mref) (gamma defs)
                        | _ => postponePatVar swap mode loc env mname mref margs margs' tmnf
                     let Hole _ _ = definition hdef
                        | _ => postponePatVar swap mode loc env mname mref margs margs' tmnf
                     if invertible hdef
                        then unifyHoleApp swap mode loc env mname mref margs margs' tmnf
                        else postponePatVar swap mode loc env mname mref margs margs' tmnf
                Just (newvars ** (locs, submv)) =>
                  do Just hdef <- lookupCtxtExact (Resolved mref) (gamma defs)
                         | _ => postponePatVar swap mode loc env mname mref margs margs' tmnf
                     let Hole _ _ = definition hdef
                         | _ => postponeS swap loc mode "Delayed hole" env
                                          (NApp loc (NMeta mname mref margs) $ map (EmptyFC,) margs')
                                          tmnf
                     tm <- case !(quoteWithin defs.options.elabDirectives.nfThreshold
                                              empty env tmnf) of
                                WithinDepth tm => pure tm
                                TooDeep => quote defs env tmnf
                     Just tm <- occursCheck loc env mode mname tm
                         | _ => postponeS swap loc mode "Occurs check failed" env
                                          (NApp loc (NMeta mname mref margs) $ map (EmptyFC,) margs')
                                          tmnf

                     let solveOrElsePostpone : Term newvars -> Core UnifyResult
                         solveOrElsePostpone stm = do
                           mbResult <- solveHole fc mode env mname mref hdef
                                                 margs margs' locs submv
                                                 tm stm tmnf
                           flip fromMaybe (pure <$> mbResult) $
                             postponeS swap loc mode "Can't instantiate" env
                                       (NApp loc (NMeta mname mref margs) $ map (EmptyFC,) margs') tmnf

                     let cantShrink : Core UnifyResult
                         cantShrink = postponeS swap loc mode "Can't shrink" env
                                                (NApp loc (NMeta mname mref margs) $ map (EmptyFC,) margs')
                                                tmnf

                     case shrink tm submv of
                          Just stm => solveOrElsePostpone stm
                          Nothing =>
                            do tm' <- quote defs env tmnf
                               case shrink tm' submv of
                                    Just stm => solveOrElsePostpone stm
                                    Nothing =>
                                      do True <- pruneOutside mode env submv tm'
                                             | False => cantShrink
                                         defs <- get Ctxt
                                         case shrink !(normalise defs env tm') submv of
                                              Nothing => cantShrink
                                              Just stm => solveOrElsePostpone stm

  -- Pruning. A solution of a metavariable applied to the variables `th`
  -- keeps can mention no other variable, so an unsolved metavariable that
  -- stands in it applied to another (its arguments distinct variables, and
  -- not itself in the arguments of another metavariable or of a function,
  -- which might discard it) has no solution that depends on that one. Each
  -- such metavariable whose type does not need the variables it drops is
  -- solved as a fresh one over the variables it keeps, after which the
  -- solution may shrink. Returns whether any was. Only in a term, and only
  -- of a clause's pattern variables, which no metavariable made outside the
  -- clause can depend on: a pattern's metavariables stand for its
  -- variables, and a type's may yet be bound as its implicits, which is
  -- decided by their names and the order their constraints leave them in.
  pruneOutside : {vars, newvars : _} ->
                 {auto c : Ref Ctxt Defs} ->
                 {auto u : Ref UST UState} ->
                 UnifyInfo -> Env Term vars -> Thin newvars vars ->
                 Term vars -> Core Bool
  pruneOutside mode env th tm
      = case umode mode of
             InTerm => prune env th tm
             _ => pure False
    where
      isPatternVar : {vs : _} -> Env Term vs -> Term vs -> Bool
      isPatternVar env (Local _ _ _ p)
          = case getBinder p env of
                 PVar {} => True
                 _ => False
      isPatternVar _ _ = False

      -- The fresh metavariable is over the variables kept and those their
      -- binders mention (`closed`), so it is pruned only where that leaves
      -- out every variable dropped.
      pruneMeta : {vs, nvs : _} ->
                  Env Term vs -> Thin nvs vs ->
                  FC -> Name -> Int -> List (Term vs) -> Core Bool
      pruneMeta env th fc n i args
          = do defs <- get Ctxt
               Just gdef <- lookupCtxtExact (Resolved i) (gamma defs)
                    | Nothing => pure False
               -- the elaborator's own, not a hole the programmer named or
               -- one that stands for a name bound implicitly
               let Hole _ flags = definition gdef
                    | _ => pure False
               let MN _ _ = dropNS n
                    | _ => pure False
               let False = implbind flags
                    | True => pure False
               let kept = filter (\a => isJust (shrink a th)) args
               let dropped = filter (\a => isNothing (shrink a th)) args
               let (_ :: _) = dropped
                    | [] => pure False
               let True = all (isPatternVar env) dropped
                    | False => pure False
               Just _ <- patternEnvTm env args
                    | Nothing => pure False
               Just (kvs ** (_, kth)) <- patternEnvTm env kept
                    | Nothing => pure False
               let (us ** (uth, _, kenv)) = closed env kth
               let True = all (\a => isNothing (shrink a uth)) dropped
                    | False => pure False
               ty <- normalise defs env !(getTerm !(getType env (Meta fc n i args)))
               let Just kty = shrink ty uth
                    | Nothing => pure False
               n' <- genMVName (dropNS n)
               (_, ptm) <- newMeta fc (multiplicity gdef) kenv n' kty
                                   (Hole (length kenv) flags) True
               logTerm "unify.hole" 10 ("Pruning " ++ show n ++ " to") (thin ptm uth)
               res <- unify (lower mode) fc env (Meta fc n i args) (thin ptm uth)
               pure (isNil (constraints res))

      prune : {vs, nvs : _} -> Env Term vs -> Thin nvs vs -> Term vs -> Core Bool

      pruneAll : {vs, nvs : _} -> Env Term vs -> Thin nvs vs -> List (Term vs) -> Core Bool
      pruneAll env th ts = any id <$> traverse (prune env th) ts

      prune env th (Meta fc n i args) = pruneMeta env th fc n i args
      prune env th (Bind _ _ b sc)
          = do pb <- pruneAll env th (case b of
                                           Let _ _ val ty => [val, ty]
                                           PLet _ _ val ty => [val, ty]
                                           _ => [binderType b])
               psc <- prune (b :: env) (Keep th) sc
               pure (pb || psc)
      prune env th tm@(App {})
          = case getFnArgs tm of
                 (Meta {}, _) => pure False
                 (Ref _ Func _, _) => pure False
                 (f, args) => pruneAll env th (f :: args)
      prune env th (TDelayed _ _ t) = prune env th t
      prune env th (TDelay _ _ ty t) = pruneAll env th [ty, t]
      prune env th (TForce _ _ t) = prune env th t
      prune env th _ = pure False

  -- Unify an application with something else
  unifyApp : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             {vars : _} ->
             (swaporder : Bool) -> -- swap the order when postponing
                                   -- (this is to preserve second arg being expected type)
             UnifyInfo -> FC -> Env Term vars -> FC ->
             NHead vars -> List (FC, Closure vars) -> NF vars ->
             Core UnifyResult
  unifyApp swap mode loc env fc (NMeta n i margs) args tm
      = unifyHole swap mode loc env fc n i margs (map snd args) tm
  unifyApp swap mode loc env fc hd args (NApp mfc (NMeta n i margs) margs')
      = unifyHole swap mode loc env mfc n i margs (map snd margs') (NApp fc hd args)
  unifyApp swap mode loc env fc hd args (NErased _ (Dotted t))
      = unifyApp swap mode loc env fc hd args t
  -- Postpone if a name application against an application, unless they are
  -- convertible
  unifyApp swap mode loc env fc (NRef nt n) args tm
      = do log "unify.application" 10 $ "Name against app, unifyIfEq"
           if not swap
              then unifyIfEq True loc mode env (NApp fc (NRef nt n) args) tm
              else unifyIfEq True loc mode env tm (NApp fc (NRef nt n) args)
  unifyApp swap mode loc env xfc (NLocal rx x xp) [] (NApp yfc (NLocal ry y yp) [])
      = do gam <- get Ctxt
           if x == y then pure success
             else postponeS swap loc mode "Postponing var"
                            env (NApp xfc (NLocal rx x xp) [])
                                (NApp yfc (NLocal ry y yp) [])
  -- A local against something canonical (binder or constructor) is bad
  unifyApp swap mode loc env xfc (NLocal rx x xp) args y@(NBind {})
      = convertErrorS swap loc env (NApp xfc (NLocal rx x xp) args) y
  unifyApp swap mode loc env xfc (NLocal rx x xp) args y@(NDCon {})
      = convertErrorS swap loc env (NApp xfc (NLocal rx x xp) args) y
  unifyApp swap mode loc env xfc (NLocal rx x xp) args y@(NTCon {})
      = convertErrorS swap loc env (NApp xfc (NLocal rx x xp) args) y
  unifyApp swap mode loc env xfc (NLocal rx x xp) args y@(NPrimVal {})
      = convertErrorS swap loc env (NApp xfc (NLocal rx x xp) args) y
  unifyApp swap mode loc env xfc (NLocal rx x xp) args y@(NType {})
      = convertErrorS swap loc env (NApp xfc (NLocal rx x xp) args) y
  -- If they're already convertible without metavariables, we're done,
  -- otherwise postpone
  unifyApp False mode loc env fc hd args tm
      = do gam <- get Ctxt
           if !(convert gam env (NApp fc hd args) tm)
              then pure success
              else postponeS False loc mode "Postponing constraint"
                             env (NApp fc hd args) tm
  unifyApp True mode loc env fc hd args tm
      = do gam <- get Ctxt
           if !(convert gam env tm (NApp fc hd args))
              then pure success
              else postponeS True loc mode "Postponing constraint"
                             env (NApp fc hd args) tm

  unifyBothApps : {auto c : Ref Ctxt Defs} ->
                  {auto u : Ref UST UState} ->
                  {vars : _} ->
                  UnifyInfo -> FC -> Env Term vars ->
                  FC -> NHead vars -> List (FC, Closure vars) ->
                  FC -> NHead vars -> List (FC, Closure vars) ->
                  Core UnifyResult
  unifyBothApps mode loc env xfc (NLocal xr x xp) [] yfc (NLocal yr y yp) []
      = if x == y
           then pure success
           else convertError loc env (NApp xfc (NLocal xr x xp) [])
                                     (NApp yfc (NLocal yr y yp) [])
  -- Locally bound things, in a term (not LHS). Since we have to unify
  -- for *all* possible values, we can safely unify the arguments.
  unifyBothApps mode@(MkUnifyInfo p InTerm) loc env xfc (NLocal xr x xp) xargs yfc (NLocal yr y yp) yargs
      = if x == y
           then unifyArgs mode loc env (map snd xargs) (map snd yargs)
           else postpone loc mode "Postponing local app"
                         env (NApp xfc (NLocal xr x xp) xargs)
                             (NApp yfc (NLocal yr y yp) yargs)
  unifyBothApps mode loc env xfc (NLocal xr x xp) xargs yfc (NLocal yr y yp) yargs
      = do log "unify.application" 10 $ "Both local apps, unifyIfEq"
           unifyIfEq True loc mode env (NApp xfc (NLocal xr x xp) xargs)
                                       (NApp yfc (NLocal yr y yp) yargs)
  -- If they're both holes, solve the one with the bigger context
  unifyBothApps mode loc env xfc (NMeta xn xi xargs) xargs' yfc (NMeta yn yi yargs) yargs'
      = do invx <- isDefInvertible loc xi
           if xi == yi && (invx || umode mode == InSearch)
                               -- Invertible, (from auto implicit search)
                               -- so we can also unify the arguments.
              then unifyArgs mode loc env (xargs ++ map snd xargs')
                                          (yargs ++ map snd yargs')
              else do xlocs <- localsIn xargs
                      ylocs <- localsIn yargs
                      -- Solve the one with the bigger context, and if they're
                      -- equal, the one that's applied to fewest things (because
                      -- then they arguments get substituted in)
                      let xbigger = xlocs > ylocs
                                      || (xlocs == ylocs &&
                                           length xargs' <= length yargs')
                      if (xbigger || umode mode == InMatch) && not (pv xn)
                        then unifyApp False mode loc env xfc (NMeta xn xi xargs) xargs'
                                            (NApp yfc (NMeta yn yi yargs) yargs')
                        else unifyApp True mode loc env yfc (NMeta yn yi yargs) yargs'
                                           (NApp xfc (NMeta xn xi xargs) xargs')
    where
      pv : Name -> Bool
      pv (PV {}) = True
      pv _ = False

      localsIn : List (Closure vars) -> Core Nat
      localsIn [] = pure 0
      localsIn (c :: cs)
          = do defs <- get Ctxt
               case !(evalClosure defs c) of
                 NApp _ (NLocal {}) _ => pure $ S !(localsIn cs)
                 _ => localsIn cs

  unifyBothApps mode loc env xfc (NMeta xn xi xargs) xargs' yfc fy yargs'
      = unifyApp False mode loc env xfc (NMeta xn xi xargs) xargs'
                                        (NApp yfc fy yargs')
  unifyBothApps mode loc env xfc fx xargs' yfc (NMeta yn yi yargs) yargs'
      = if umode mode /= InMatch
           then unifyApp True mode loc env xfc (NMeta yn yi yargs) yargs'
                                               (NApp xfc fx xargs')
           else unifyApp False mode loc env xfc fx xargs'
                                        (NApp yfc (NMeta yn yi yargs) yargs')
  unifyBothApps mode@(MkUnifyInfo p InSearch) loc env xfc fx@(NRef xt hdx) xargs yfc fy@(NRef yt hdy) yargs
      = if hdx == hdy
           then unifyArgs mode loc env (map snd xargs) (map snd yargs)
           else unifyApp False mode loc env xfc fx xargs (NApp yfc fy yargs)
  unifyBothApps mode@(MkUnifyInfo p InMatch) loc env xfc fx@(NRef xt hdx) xargs yfc fy@(NRef yt hdy) yargs
      = if hdx == hdy
           then do logC "unify.application" 5
                          (do defs <- get Ctxt
                              xs <- traverse (quote defs env) (map snd xargs)
                              ys <- traverse (quote defs env) (map snd yargs)
                              pure ("Matching args " ++ show xs ++ " " ++ show ys))
                   unifyArgs mode loc env (map snd xargs) (map snd yargs)
           else unifyApp False mode loc env xfc fx xargs (NApp yfc fy yargs)
  unifyBothApps mode loc env xfc fx ax yfc fy ay
      = unifyApp False mode loc env xfc fx ax (NApp yfc fy ay)

  unifyPiInfo : {auto c : Ref Ctxt Defs} ->
                {auto u : Ref UST UState} ->
                {vars : _} ->
                UnifyInfo -> FC -> Env Term vars ->
                PiInfo (Closure vars) -> PiInfo (Closure vars) ->
                Core (Maybe UnifyResult)
  unifyPiInfo mode loc env Explicit Explicit = pure $ Just success
  unifyPiInfo mode loc env Implicit Implicit = pure $ Just success
  unifyPiInfo mode loc env AutoImplicit AutoImplicit = pure $ Just success
  unifyPiInfo mode loc env (DefImplicit x) (DefImplicit y) = Just <$> unify mode loc env x y
  unifyPiInfo mode loc env _ _ = pure Nothing

  unifyBothBinders: {auto c : Ref Ctxt Defs} ->
                    {auto u : Ref UST UState} ->
                    {vars : _} ->
                    UnifyInfo -> FC -> Env Term vars ->
                    FC -> Name -> Binder (Closure vars) ->
                    (Defs -> Closure vars -> Core (NF vars)) ->
                    FC -> Name -> Binder (Closure vars) ->
                    (Defs -> Closure vars -> Core (NF vars)) ->
                    Core UnifyResult
  unifyBothBinders mode loc env xfc x (Pi fcx cx ix tx) scx yfc y (Pi fcy cy iy ty) scy
      = do defs <- get Ctxt
           let err = convertError loc env
                       (NBind xfc x (Pi fcx cx ix tx) scx)
                       (NBind yfc y (Pi fcy cy iy ty) scy)
           if cx /= cy
             then err
             else do Just ci <- unifyPiInfo (lower mode) loc env ix iy
                       | Nothing => err
                     empty <- clearDefs defs
                     tx' <- quote empty env tx
                     logC "unify.binder" 10 $
                               (do ty' <- quote empty env ty
                                   pure ("Unifying arg types " ++ show tx' ++ " and " ++ show ty'))
                     ct <- unify (lower mode) loc env tx ty
                     xn <- genVarName (known Kx)
                     let env' : Env Term (x :: _)
                              = Pi fcy cy Explicit tx' :: env
                     case constraints ct of
                         [] => -- No constraints, check the scope
                            do tscx <- scx defs (toClosure defaultOpts env (Ref loc Bound xn))
                               tscy <- scy defs (toClosure defaultOpts env (Ref loc Bound xn))
                               tmx <- quote empty env tscx
                               tmy <- quote empty env tscy
                               cs <- unify (lower mode) loc env'
                                       (refsToLocals (Add x xn None) tmx)
                                       (refsToLocals (Add x xn None) tmy)
                               pure (union ci cs)
                         cs => -- Constraints, make new guarded constant
                            do txtm <- quote empty env tx
                               tytm <- quote empty env ty
                               c <- newConstant loc erased env
                                      (Bind xfc x (Lam fcy cy Explicit txtm) (Local xfc Nothing _ First))
                                      (Bind xfc x (Pi fcy cy Explicit txtm)
                                          (weaken tytm)) cs
                               tscx <- scx defs (toClosure defaultOpts env (Ref loc Bound xn))
                               tscy <- scy defs (toClosure defaultOpts env (App loc c (Ref loc Bound xn)))
                               tmx <- quote empty env tscx
                               tmy <- quote empty env tscy
                               cs' <- unify (lower mode) loc env'
                                        (refsToLocals (Add x xn None) tmx)
                                        (refsToLocals (Add x xn None) tmy)
                               pure (union ci (union ct cs'))
  unifyBothBinders mode loc env xfc x (Lam fcx cx ix tx) scx yfc y (Lam fcy cy iy ty) scy
      = do defs <- get Ctxt
           let err = convertError loc env
                       (NBind xfc x (Lam fcx cx ix tx) scx)
                       (NBind yfc y (Lam fcy cy iy ty) scy)
           if cx /= cy
             then err
             else do empty <- clearDefs defs
                     Just ci <- unifyPiInfo (lower mode) loc env ix iy
                       | Nothing => err
                     ct <- unify (lower mode) loc env tx ty
                     xn <- genVarName (known Kx)
                     txtm <- quote empty env tx
                     let env' : Env Term (x :: _)
                              = Lam fcx cx Explicit txtm :: env

                     tscx <- scx defs (toClosure defaultOpts env (Ref loc Bound xn))
                     tscy <- scy defs (toClosure defaultOpts env (Ref loc Bound xn))
                     tmx <- quote empty env tscx
                     tmy <- quote empty env tscy
                     cs' <- unify (lower mode) loc env' (refsToLocals (Add x xn None) tmx)
                                                              (refsToLocals (Add x xn None) tmy)
                     pure (union ci (union ct cs'))

  unifyBothBinders mode loc env xfc x bx scx yfc y by scy
      = convertError loc env
                  (NBind xfc x bx scx)
                  (NBind yfc y by scy)

  dumpArg : {vars : _} ->
            {auto c : Ref Ctxt Defs} ->
            Env Term vars -> Closure vars -> Core ()
  dumpArg env (MkClosure opts loc lenv tm)
      = do defs <- get Ctxt
           empty <- clearDefs defs
           logTerm "unify" 20 "Term: " tm
           nf <- evalClosure empty (MkClosure opts loc lenv tm)
           logNF "unify" 20 "  " env nf
  dumpArg env cl
      = do defs <- get Ctxt
           empty <- clearDefs defs
           nf <- evalClosure empty cl
           logNF "unify" 20 "  " env nf

  export
  unifyNoEta : {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               {vars : _} ->
               UnifyInfo -> FC -> Env Term vars ->
               NF vars -> NF vars ->
               Core UnifyResult
  unifyNoEta mode loc env (NDCon xfc x tagx ax xs) (NDCon yfc y tagy ay ys)
      = do gam <- get Ctxt
           if tagx == tagy
             then
                  do -- Constantly checking the log setting appears to have
                     -- a bit of overhead, but I'm keeping this here because it
                     -- may prove useful again...
                     {-
                     ust <- get UST
                     when (logging ust) $
                        do logC "unify" 20 $ do pure $ "Constructor " ++ show !(toFullNames x) ++ " " ++ show loc
                           log "unify" 20 "ARGUMENTS:"
                           traverse_ (dumpArg env) xs
                           log "unify" 20 "WITH:"
                           traverse_ (dumpArg env) ys
                     -}
                     unifyArgs mode loc env (map snd xs) (map snd ys)
             else convertError loc env
                       (NDCon xfc x tagx ax xs)
                       (NDCon yfc y tagy ay ys)
  unifyNoEta mode loc env (NTCon xfc x ax xs) (NTCon yfc y ay ys)
   = do logC "unify" 20 $ do
          x <- toFullNames x
          y <- toFullNames y
          pure $ "Comparing type constructors " ++ show x ++ " and " ++ show y
        if x == y
           then do let xs = map snd xs
                   let ys = map snd ys

                   logC "unify" 20 $
                     pure $ "Constructor " ++ show x
                   logC "unify" 20 $ map (const "") $ traverse_ (dumpArg env) xs
                   logC "unify" 20 $ map (const "") $ traverse_ (dumpArg env) ys
                   unifyArgs mode loc env xs ys
             -- TODO: Type constructors are not necessarily injective.
             -- If we don't know it's injective, need to postpone the
             -- constraint. But before then, we need some way to decide
             -- what's injective...
             -- gallais: really? We don't mind being anticlassical do we?
--                then postpone True loc mode env (quote empty env (NTCon x ax xs))
--                                           (quote empty env (NTCon y ay ys))
           else convertError loc env
                     (NTCon xfc x ax xs)
                     (NTCon yfc y ay ys)
  unifyNoEta mode loc env (NDelayed xfc _ x) (NDelayed yfc _ y)
      = unify (lower mode) loc env x y
  unifyNoEta mode loc env (NDelay xfc _ xty x) (NDelay yfc _ yty y)
      = unifyArgs mode loc env [xty, x] [yty, y]
  unifyNoEta mode loc env (NForce xfc _ x axs) (NForce yfc _ y ays)
      = do cs <- unify (lower mode) loc env x y
           cs' <- unifyArgs mode loc env (map snd axs) (map snd ays)
           pure (union cs cs')
  unifyNoEta mode loc env x@(NApp xfc fx@(NMeta {}) axs)
                          y@(NApp yfc fy@(NMeta {}) ays)
      = do defs <- get Ctxt
           if !(convert defs env x y)
               then pure success
               else unifyBothApps (lower mode) loc env xfc fx axs yfc fy ays
  unifyNoEta mode loc env (NApp xfc fx axs) (NApp yfc fy ays)
      = unifyBothApps (lower mode) loc env xfc fx axs yfc fy ays
  unifyNoEta mode loc env x (NErased _ (Dotted y)) = unifyNoEta mode loc env x y
  unifyNoEta mode loc env (NErased _ (Dotted x)) y = unifyNoEta mode loc env x y
  unifyNoEta mode loc env (NApp xfc hd args) y
      = unifyApp False (lower mode) loc env xfc hd args y
  unifyNoEta mode loc env y (NApp yfc hd args)
      = if umode mode /= InMatch
           then unifyApp True mode loc env yfc hd args y
           else do log "unify.noeta" 10 $ "Unify if Eq due to something with app"
                   unifyIfEq True loc mode env y (NApp yfc hd args)
  -- Only try stripping as patterns as a last resort
  unifyNoEta mode loc env x (NAs _ _ _ y) = unifyNoEta mode loc env x y
  unifyNoEta mode loc env (NAs _ _ _ x) y = unifyNoEta mode loc env x y
  unifyNoEta mode loc env x y
      = do defs <- get Ctxt
           empty <- clearDefs defs
           log "unify.noeta" 10 $ "Nothing else worked, unifyIfEq"
           unifyIfEq (isDelay x || isDelay y) loc mode env x y
    where
      -- If one of them is a delay, and they're not equal, we'd better
      -- postpone and come back to it so we can insert the implicit
      -- Force/Delay later
      isDelay : NF vars -> Bool
      isDelay (NDelayed {}) = True
      isDelay _ = False

  isHoleApp : NF vars -> Bool
  isHoleApp (NApp _ (NMeta {}) _) = True
  isHoleApp _ = False

  export
  Unify NF where
    unifyD _ _ mode loc env (NBind xfc x bx scx) (NBind yfc y by scy)
        = unifyBothBinders mode loc env xfc x bx scx yfc y by scy
    unifyD _ _ mode loc env tmx@(NBind xfc x (Lam fcx cx ix tx) scx) tmy
        = do defs <- get Ctxt
             logNF "unify" 10 "EtaR" env tmx
             logNF "unify" 10 "...with" env tmy
             if isHoleApp tmy
                then if not !(convert defs env tmx tmy)
                        then unifyNoEta (lower mode) loc env tmx tmy
                        else pure success
                else do empty <- clearDefs defs
                        domty <- quote empty env tx
                        etay <- nf defs env
                                  $ Bind xfc x (Lam fcx cx Explicit domty)
                                  $ App xfc (weaken !(quote empty env tmy))
                                            (Local xfc Nothing 0 First)
                        logNF "unify" 10 "Expand" env etay
                        unify (lower mode) loc env tmx etay
    unifyD _ _ mode loc env tmx tmy@(NBind yfc y (Lam fcy cy iy ty) scy)
        = do defs <- get Ctxt
             logNF "unify" 10 "EtaL" env tmx
             logNF "unify" 10 "...with" env tmy
             if isHoleApp tmx
                then if not !(convert defs env tmx tmy)
                        then unifyNoEta (lower mode) loc env tmx tmy
                        else pure success
                else do empty <- clearDefs defs
                        domty <- quote empty env ty
                        etax <- nf defs env
                                 $ Bind yfc y (Lam fcy cy Explicit domty)
                                 $ App yfc (weaken !(quote empty env tmx))
                                           (Local yfc Nothing 0 First)
                        logNF "unify" 10 "Expand" env etax
                        unify (lower mode) loc env etax tmy
    unifyD _ _ mode loc env tmx tmy = unifyNoEta mode loc env tmx tmy

    unifyWithLazyD _ _ mode loc env (NDelayed _ _ tmx) (NDelayed _ _ tmy)
       = unify (lower mode) loc env tmx tmy
    unifyWithLazyD _ _ mode loc env x@(NDelayed _ r tmx) tmy
       = if isHoleApp tmy && not (umode mode == InMatch)
            -- given type delayed, expected unknown, so let's wait and see
            -- what the expected type turns out to be
            then postpone loc mode "Postponing in lazy" env x tmy
            else do vs <- unify (lower mode) loc env tmx tmy
                    pure ({ addLazy := AddForce r } vs)
    unifyWithLazyD _ _ mode loc env tmx (NDelayed _ r tmy)
       = do vs <- unify (lower mode) loc env tmx tmy
            pure ({ addLazy := AddDelay r } vs)
    unifyWithLazyD _ _ mode loc env tmx tmy
       = unify mode loc env tmx tmy

  export
  Unify Term where
    unifyD _ _ mode loc env x y
          = do defs <- get Ctxt
               empty <- clearDefs defs
               if x == y
                  then do log "unify.equal" 10 $
                                 "Skipped unification (equal already): "
                                 ++ show x ++ " and " ++ show y
                          pure success
                  else do xnf <- nf defs env x
                          ynf <- nf defs env y
                          unify mode loc env xnf ynf
    unifyWithLazyD _ _ mode loc env x y
          = do defs <- get Ctxt
               empty <- clearDefs defs
               if x == y
                  then do log "unify.equal" 10 $
                                 "Skipped unification (equal already): "
                                 ++ show x ++ " and " ++ show y
                          pure success
                  else do xnf <- nf defs env x
                          ynf <- nf defs env y
                          unifyWithLazy mode loc env xnf ynf

  export
  Unify Closure where
    unifyD _ _ mode loc env x y
        = do defs <- get Ctxt
             empty <- clearDefs defs
             if !(convert empty env x y)
                then pure success
                else
                  do xnf <- evalClosure defs x
                     ynf <- evalClosure defs y
                     -- If one's a meta and the other isn't, don't reduce at
                     -- all
                     case (xnf, ynf) of
                         -- They might be equal, don't want to make a cycle
                         (NApp _ (NMeta {}) _, NApp _ (NMeta {}) _)
                               => unify mode loc env xnf ynf
                         (NApp _ (NMeta _ i _) _, _) =>
                            do ynf' <- evalClosure empty y
                               xtm <- quote empty env xnf
                               ytm <- quote empty env ynf'
                               cs <- unify mode loc env !(nf empty env xtm)
                                                        !(nf empty env ytm)
                               case constraints cs of
                                    [] => pure cs
                                    _ => do ynf <- evalClosure defs y
                                            unify mode loc env xnf ynf
                         (_, NApp _ (NMeta _ i _ ) _) =>
                            do xnf' <- evalClosure empty x
                               xtm <- quote empty env xnf'
                               ytm <- quote empty env ynf
                               cs <- unify mode loc env !(nf empty env ytm)
                                                        !(nf empty env xtm)
                               case constraints cs of
                                    [] => pure cs
                                    _ => unify mode loc env xnf ynf
                         _ => unify mode loc env xnf ynf

-- An unknown made invertible unifies differently, so the searches waiting
-- on it wake.
export
setInvertible : {auto c : Ref Ctxt Defs} ->
                {auto u : Ref UST UState} ->
                FC -> Name -> Core ()
setInvertible fc n
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact n (gamma defs)
              | Nothing => undefinedName fc n
         i <- addDef n ({ invertible := True } gdef)
         wake i

public export
data SolveMode = Normal -- during elaboration: unifies and searches
               | Defaults -- unifies and searches for default hints only
               | MatchArgs -- match rather than unify
               | LastChance -- as normal, but any failure throws rather than delays

Eq SolveMode where
  Normal == Normal = True
  Defaults == Defaults = True
  LastChance == LastChance = True
  _ == _ = False

retry : {auto c : Ref Ctxt Defs} ->
        {auto u : Ref UST UState} ->
        UnifyInfo -> Int -> Core UnifyResult
retry mode c
    = do ust <- get UST
         case lookup c (constraints ust) of
              Nothing => pure success
              Just Resolved => pure success
              Just (MkConstraint loc withLazy env xold yold)
               => do defs <- get Ctxt
                     x <- continueNF defs env xold
                     y <- continueNF defs env yold
                     catch
                       (do logNF "unify.retry" 5 ("Retrying " ++ show c ++ " " ++ show (umode mode)) env x
                           logNF "unify.retry" 5 "....with" env y
                           log "unify.retry" 5 $ if withLazy
                                      then "(lazy allowed)"
                                      else "(no lazy)"
                           cs <- ifThenElse withLazy
                                    (unifyWithLazy mode loc env x y)
                                    (unify (lower mode) loc env x y)
                           case constraints cs of
                             [] => do log "unify.retry" 5 $ "Success " ++ show (addLazy cs)
                                      deleteConstraint c
                                      pure cs
                             _ => do log "unify.retry" 5 $ "Constraints " ++ show (addLazy cs)
                                     pure cs)
                      (\err => do defs <- get Ctxt
                                  empty <- clearDefs defs
                                  throw (WhenUnifying loc (gamma defs) env !(quote empty env x) !(quote empty env y) err))

delayMeta : {vars : _} ->
            LazyReason -> Nat -> Term vars -> Term vars -> Term vars
delayMeta r (S k) ty (Bind fc n b sc)
    = Bind fc n b (delayMeta r k (weaken ty) sc)
-- The delay unification asks for, inserted around a solution checked
-- against a delayed type.
delayMeta r envb ty tm = TDelay (getLoc tm) (MkDelaying r ByElaborator) ty tm

forceMeta : LazyReason -> Nat -> Term vars -> Term vars
forceMeta r (S k) (Bind fc n b sc)
    = Bind fc n b (forceMeta r k sc)
forceMeta r envb tm = TForce (getLoc tm) r tm

-- The unknowns a term reaches, through the solutions of those solved: what a
-- search on it waits for.
unknownsOf : {auto c : Ref Ctxt Defs} -> Term vars -> Core (List Int)
unknownsOf tm = reach (keys (addMetas True empty tm)) empty
  where
    reach : List Name -> IntMap () -> Core (List Int)
    reach [] seen = pure (keys seen)
    reach (Resolved i :: ns) seen
        = case lookup i seen of
               Just () => reach ns seen
               Nothing =>
                 do defs <- get Ctxt
                    case !(lookupDefExact (Resolved i) (gamma defs)) of
                         Just (PMDef _ args body) =>
                           do sns <- walkTree body (\leaf, tree => case tree of
                                       STerm _ x => do soln <- leafTerm leaf {outer = []} x
                                                       pure (keys (addMetas True empty soln))
                                       _ => pure [])
                              reach (sns ++ ns) (insert i () seen)
                         _ => reach ns (insert i () seen)
    -- `addMetas True` names every unknown by its index; no other name
    -- comes.
    reach (_ :: ns) seen = reach ns seen

-- Check whether it's worth trying a search again, based on what went wrong
recoverable : Error -> Bool
recoverable (UndefinedName {}) = False
recoverable (InType _ _ err) = recoverable err
recoverable (InCon _ err) = recoverable err
recoverable (InLHS _ _ err) = recoverable err
recoverable (InRHS _ _ err) = recoverable err
recoverable (WhenUnifying _ _ _ _ _ err) = recoverable err
recoverable (MaybeMisspelling err _) = recoverable err
recoverable _ = True

-- Retry the given constraint, return True if progress was made
retryGuess : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             UnifyInfo -> (smode : SolveMode) -> (hole : (Int, (FC, Name))) ->
             Core Bool
retryGuess mode smode (hid, (loc, hname))
    = do defs <- get Ctxt
         case !(lookupCtxtExact (Resolved hid) (gamma defs)) of
           Nothing => pure False
           Just def =>
             case definition def of
               BySearch rig defining =>
                  do ty <- typeOf def
                     Right searched <- tryErrorUnify
                                         (search loc rig (smode == Defaults) defining
                                                 ty Env.empty)
                          | Left err => failed rig def err
                     case searched of
                          Found tm =>
                            do let gdef = { definition := PMDef defaultPI Scope.empty (LiveBody (STerm 0 tm) [] []) } def
                               logTermNF "unify.retry" 5 ("Solved " ++ show hname) Env.empty tm
                               ignore $ addDef (Resolved hid) gdef
                               removeGuess hid
                               pure True
                          -- Here, where the search is retried or refused, a
                          -- repeat is the failure it stands for.
                          Repeated r => failed rig def
                                          (CantSolveGoal loc r.context Env.empty r.sought Nothing)
                          Grows g => grown def g
               Guess tm envb [constr] =>
                 do let umode = case smode of
                                     MatchArgs => inMatch
                                     _ => mode
                    cs <- retry umode constr
                    case constraints cs of
                         [] => do tm' <- case addLazy cs of
                                           NoLazy => pure tm
                                           AddForce r => pure $ forceMeta r envb tm
                                           AddDelay r =>
                                              do ty <- getType Env.empty tm
                                                 logTerm "unify.retry" 5 "Retry Delay" tm
                                                 pure $ delayMeta r envb !(getTerm ty) tm
                                  let gdef = { definition := PMDef (MkPMDefInfo NotHole True)
                                                                   Scope.empty (LiveBody (STerm 0 tm') [] []) } def
                                  logTerm "unify.retry" 5 ("Resolved " ++ show hname) tm'
                                  ignore $ addDef (Resolved hid) gdef
                                  removeGuess hid
                                  pure (holesSolved cs)
                         newcs => do tm' <- case addLazy cs of
                                           NoLazy => pure tm
                                           AddForce r => pure $ forceMeta r envb tm
                                           AddDelay r =>
                                              do ty <- getType Env.empty tm
                                                 logTerm "unify.retry" 5 "Retry Delay (constrained)" tm
                                                 pure $ delayMeta r envb !(getTerm ty) tm
                                     let gdef = { definition := Guess tm' envb newcs } def
                                     ignore $ addDef (Resolved hid) gdef
                                     pure False
               Guess tm envb constrs =>
                 do let umode = case smode of
                                     MatchArgs => inMatch
                                     _ => mode
                    cs' <- traverse (retry umode) constrs
                    let csAll = unionAll cs'
                    case constraints csAll of
                         -- All constraints resolved, so turn into a
                         -- proper definition and remove it from the
                         -- hole list
                         [] => do let gdef = { definition := PMDef (MkPMDefInfo NotHole True)
                                                                   Scope.empty (LiveBody (STerm 0 tm) [] []) } def
                                  logTerm "unify.retry" 5 ("Resolved " ++ show hname) tm
                                  ignore $ addDef (Resolved hid) gdef
                                  removeGuess hid
                                  pure (holesSolved csAll)
                         newcs => do let gdef = { definition := Guess tm envb newcs } def
                                     ignore $ addDef (Resolved hid) gdef
                                     pure False
               _ => pure False
  where
    refuse : Grown -> Core Bool
    refuse g = throw (GrowingSearch loc g.context g.earlier g.later g.hints)

    -- A search that failed and changed nothing waits for an unknown its
    -- goal reaches to change, since until then a retry fails the same way.
    -- One that failed in the round that tries default hints is tried
    -- without them in the next, and does not wait.
    stillWaits : GlobalDef -> Core Bool
    stillWaits def
        = do case smode of
                  Defaults => pure ()
                  _ => do unknowns <- unknownsOf !(typeOf def)
                          waitOn hid unknowns
             pure False

    -- A search that grows through unknowns may end once a later round
    -- fixes them, so it waits as a determining argument's does; at the last
    -- chance, the end of the declaration's elaboration, nothing more will be
    -- fixed, and the program is refused. With every part known, no later
    -- round changes it, and the program is refused at once.
    grown : GlobalDef -> Grown -> Core Bool
    grown def g = case g.growth of
                       ThroughUnknowns => case smode of
                                               LastChance => refuse g
                                               _ => stillWaits def
                       Settled => refuse g

    failed : RigCount -> GlobalDef -> Error -> Core Bool
    failed rig def (DeterminingArg _ n i _ _)
        = do logTerm "unify.retry" 5
                     ("Failed (det " ++ show hname ++ " " ++ show n ++ ")")
                     !(typeOf def)
             setInvertible loc (Resolved i)
             pure False -- progress not made yet!
    failed rig def err
        = do ty <- typeOf def
             logTermNF "unify.retry" 5
                       ("Search failed at " ++ show rig ++ " for " ++ show hname)
                       Env.empty ty
             case smode of
                  LastChance => throw err
                  _ => if recoverable err
                          then stillWaits def -- Postpone again
                          else do defs <- get Ctxt
                                  throw (CantSolveGoal loc (gamma defs)
                                           Env.empty ty (Just err))

-- A round: each guess retried in turn, but a search that waits is passed,
-- since a retry would fail as its last did. Whether it waits is read when
-- its turn comes, after what the round solved before it.
retryRound : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             UnifyInfo -> SolveMode -> List (Int, (FC, Name)) -> Core (List Bool)
retryRound umode smode [] = pure []
retryRound umode smode (g :: gs)
    = do ust <- get UST
         progress <- case lookup (fst g) (waiting ust) of
                          Just () => pure False
                          Nothing => retryGuess umode smode g
         (progress ::) <$> retryRound umode smode gs

-- The first round retries every guess, since what changed since the last
-- call is not only unknowns; each later round, semi-naively, only what
-- changed unknowns woke and the guesses that are not searches.
export
solveConstraints : {auto c : Ref Ctxt Defs} ->
                   {auto u : Ref UST UState} ->
                   UnifyInfo -> (smode : SolveMode) -> Core ()
solveConstraints umode smode
    = do retryAll
         rounds smode
  where
    rounds : SolveMode -> Core ()
    rounds mode
        = do ust <- get UST
             progress <- retryRound umode mode (toList (guesses ust))
             when (any id progress) $ rounds Normal

export
solveConstraintsAfter : {auto c : Ref Ctxt Defs} ->
                        {auto u : Ref UST UState} ->
                        Int -> UnifyInfo -> (smode : SolveMode) -> Core ()
solveConstraintsAfter start umode smode
    = do retryAll
         rounds smode
  where
    afterStart : (Int, a) -> Bool
    afterStart (x, _) = x >= start

    rounds : SolveMode -> Core ()
    rounds mode
        = do ust <- get UST
             progress <- retryRound umode mode (filter afterStart (toList (guesses ust)))
             when (any id progress) $ rounds Normal

-- Replace any 'BySearch' with 'Hole', so that we don't keep searching
-- fruitlessly while elaborating the rest of a source file
export
giveUpConstraints : {auto c : Ref Ctxt Defs} ->
                    {auto u : Ref UST UState} ->
                    Core ()
giveUpConstraints
    = do ust <- get UST
         traverse_ constraintToHole (toList (guesses ust))
  where
    constraintToHole : (Int, (FC, Name)) -> Core ()
    constraintToHole (hid, (_, _))
        = do defs <- get Ctxt
             case !(lookupDefExact (Resolved hid) (gamma defs)) of
                  Just (BySearch {}) =>
                         updateDef (Resolved hid) (const (Just (Hole 0 (holeInit False))))
                  Just (Guess {}) =>
                         updateDef (Resolved hid) (const (Just (Hole 0 (holeInit False))))
                  _ => pure ()

-- Check whether any of the given hole references have the same solution
-- (up to conversion)
export
checkArgsSame : {auto u : Ref UST UState} ->
                {auto c : Ref Ctxt Defs} ->
                List Int -> Core Bool
checkArgsSame [] = pure False
checkArgsSame (x :: xs)
    = do defs <- get Ctxt
         Just (PMDef _ [] body) <- lookupDefExact (Resolved x) (gamma defs)
              | _ => checkArgsSame xs
         STerm 0 def <- treeOf body
              | _ => checkArgsSame xs
         s <- anySame def xs
         if s
            then pure True
            else checkArgsSame xs
  where
    anySame : ClosedTerm -> List Int -> Core Bool
    anySame tm [] = pure False
    anySame tm (t :: ts)
        = do defs <- get Ctxt
             Just (PMDef _ [] body) <- lookupDefExact (Resolved t) (gamma defs)
                 | _ => anySame tm ts
             STerm 0 def <- treeOf body
                 | _ => anySame tm ts
             if !(convert defs Env.empty tm def)
                then pure True
                else anySame tm ts

export
checkDots : {auto u : Ref UST UState} ->
            {auto c : Ref Ctxt Defs} ->
            Core ()
checkDots
    = do ust <- get UST
         hs <- getCurrentHoles
         traverse_ checkConstraint (reverse (dotConstraints ust))
         hs <- getCurrentHoles
         update UST { dotConstraints := [] }
  where
    getHoleName : ClosedTerm -> Core (Maybe Name)
    getHoleName tm
        = do defs <- get Ctxt
             NApp _ (NMeta n' i args) _ <- nf defs Env.empty tm
                 | _ => pure Nothing
             pure (Just n')

    checkConstraint : (Name, DotReason, Constraint) -> Core ()
    checkConstraint (n, reason, MkConstraint fc wl env xold yold)
        = do defs <- get Ctxt
             x <- continueNF defs env xold
             y <- continueNF defs env yold
             logNF "unify.constraint" 10 "Dot" env y
             logNF "unify.constraint" 10 "  =" env x
             -- A dot is okay if the constraint is solvable *without solving
             -- any additional holes*
             ust <- get UST
             handleUnify
               (do defs <- get Ctxt
                   -- get the hole name that 'n' is currently resolved to,
                   -- if indeed it is still a hole
                   (i, _) <- getPosition n (gamma defs)
                   oldholen <- getHoleName (Meta fc n i [])

                   -- Check that what was given (x) matches what was
                   -- solved by unification (y).
                   -- In 'InMatch' mode, only metavariables in 'x' can
                   -- be solved, so everything in the dotted metavariable
                   -- must be complete.
                   cs <- unify inMatch fc env x y
                   defs <- get Ctxt

                   -- If the name standing for the dot wasn't solved
                   -- earlier, but is now (even with another metavariable)
                   -- this is bad (it most likely means there's a non-linear
                   -- variable)
                   dotSolved <-
                      maybe (pure False)
                            (\n => do Just ndef <- lookupDefExact n (gamma defs)
                                           | Nothing => undefinedName fc n
                                      pure $ case ndef of
                                           Hole {} => False
                                           _ => True)
                            oldholen

                   -- If any of the things we solved have the same definition,
                   -- we've sneaked a non-linear pattern variable in
                   argsSame <- checkArgsSame (namesSolved cs)
                   when (not (isNil (constraints cs))
                            || dotSolved || argsSame) $
                      throw (InternalError "Dot pattern match fail"))
               (\err =>
                    case err of
                         InternalError _ =>
                           do defs <- get Ctxt
                              Just dty <- lookupTyExact n (gamma defs)
                                   | Nothing => undefinedName fc n
                              logTermNF "unify.constraint" 5 "Dot type" Env.empty dty
                              -- Clear constraints so we don't report again
                              -- later
                              put UST ({ dotConstraints := [] } ust)
                              empty <- clearDefs defs
                              throw (BadDotPattern fc env reason
                                      !(quote empty env x)
                                      !(quote empty env y))
                         _ => do put UST ({ dotConstraints := [] } ust)
                                 throw err)
    checkConstraint _ = pure ()
