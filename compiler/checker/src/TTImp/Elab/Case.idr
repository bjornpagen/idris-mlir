-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module TTImp.Elab.Case

import Core.Env
import Core.Metadata
import Core.Unify
import Core.Value

import Idris.Syntax
import Idris.REPL.Opts

import TTImp.Elab.Check
import TTImp.Elab.Delayed
import TTImp.Elab.ImplicitBind
import TTImp.Elab.Lazy
import TTImp.Elab.Utils
import TTImp.ProcessFnOpt
import TTImp.TTImp
import TTImp.Utils

import Data.Maybe
import Data.String
import Libraries.Data.NameMap
import Libraries.Data.NatSet
import Libraries.Data.VarSet
import Libraries.Data.WithDefault

%default covering

-- Each kind of node a term holds terms in is walked by a function of its
-- own rather than by `map`, so that every recursive call is on a part of
-- the term it was given.
mutual
  changeVarPi : (old : Var vs) -> (new : Var vs) -> PiInfo (Term vs) -> PiInfo (Term vs)
  changeVarPi old new Implicit = Implicit
  changeVarPi old new Explicit = Explicit
  changeVarPi old new AutoImplicit = AutoImplicit
  changeVarPi old new (DefImplicit t) = DefImplicit (changeVar old new t)

  changeVarBinder : (old : Var vs) -> (new : Var vs) -> Binder (Term vs) -> Binder (Term vs)
  changeVarBinder old new (Lam fc c p ty)
      = Lam fc c (changeVarPi old new p) (changeVar old new ty)
  changeVarBinder old new (Let fc c val ty)
      = Let fc c (changeVar old new val) (changeVar old new ty)
  changeVarBinder old new (Pi fc c p ty)
      = Pi fc c (changeVarPi old new p) (changeVar old new ty)
  changeVarBinder old new (PVar fc c p ty)
      = PVar fc c (changeVarPi old new p) (changeVar old new ty)
  changeVarBinder old new (PLet fc c val ty)
      = PLet fc c (changeVar old new val) (changeVar old new ty)
  changeVarBinder old new (PVTy fc c ty) = PVTy fc c (changeVar old new ty)

  changeVars : (old : Var vs) -> (new : Var vs) -> List (Term vs) -> List (Term vs)
  changeVars old new [] = []
  changeVars old new (t :: ts) = changeVar old new t :: changeVars old new ts

  export
  changeVar : (old : Var vs) -> (new : Var vs) -> Term vs -> Term vs
  changeVar old (MkVar new) (Local fc r idx p)
      = if old == MkVar p
           then Local fc r _ new
           else Local fc r _ p
  changeVar old new (Meta fc nm i args)
      = Meta fc nm i (changeVars old new args)
  changeVar (MkVar old) (MkVar new) (Bind fc x b sc)
      = Bind fc x (changeVarBinder (MkVar old) (MkVar new) b)
             (changeVar (MkVar (Later old)) (MkVar (Later new)) sc)
  changeVar old new (App fc fn arg)
      = App fc (changeVar old new fn) (changeVar old new arg)
  changeVar old new (As fc s nm p)
      = As fc s (changeVar old new nm) (changeVar old new p)
  changeVar old new (TDelayed fc r p)
      = TDelayed fc r (changeVar old new p)
  changeVar old new (TDelay fc r t p)
      = TDelay fc r (changeVar old new t) (changeVar old new p)
  changeVar old new (TForce fc r p)
      = TForce fc r (changeVar old new p)
  changeVar old new tm = tm

toRig1 : {idx : Nat} -> (0 p : IsVar nm idx vs) -> Env Term vs -> Env Term vs
toRig1 First (b :: bs)
    = if isErased (multiplicity b)
         then setMultiplicity b linear :: bs
         else b :: bs
toRig1 (Later p) (b :: bs) = b :: toRig1 p bs

allow : Maybe (Var vs) -> Env Term vs -> Env Term vs
allow Nothing env = env
allow (Just (MkVar p)) env = toRig1 p env

-- If the name is used elsewhere, update its multiplicity so it's
-- not required to be used in the case block
updateMults : VarSet vs -> Env Term vs -> Env Term vs
updateMults vars env
  = -- shortcircuiting the call if the set of vars to erase is now empty
    if VarSet.isEmpty vars then env else go vars env
  where

  go : {0 vs : Scope} -> VarSet vs -> Env Term vs -> Env Term vs
  go vars [] = []
  go vars (b :: env)
    = (if first `VarSet.elem` vars
        then setMultiplicity b erased
        else b)
    :: updateMults (VarSet.dropFirst vars) env

findImpsIn : {vars : _} ->
             FC -> Env Term vars -> List (Name, Term vars) -> Term vars ->
             Core ()
findImpsIn fc env ns (Bind _ n b@(Pi _ _ Implicit ty) sc)
    = findImpsIn fc (b :: env)
                 ((n, weaken ty) :: map (\x => (fst x, weaken (snd x))) ns)
                 sc
findImpsIn fc env ns (Bind _ n b sc)
    = findImpsIn fc (b :: env)
                 (map (\x => (fst x, weaken (snd x))) ns)
                 sc
findImpsIn fc env ns ty
    = when (not (isNil ns)) $
           throw (TryWithImplicits fc env (reverse ns))

-- Extend the list of variables we need in the environment so far, removing
-- duplicates
extendNeeded : {vs : _} ->
               Binder (Term vs) ->
               Env Term vs -> VarSet vs -> VarSet vs
extendNeeded (Let _ _ ty val) env needed
    = VarSet.union (findUsedLocs env ty) (VarSet.union (findUsedLocs env val) needed)
extendNeeded (PLet _ _ ty val) env needed
    = VarSet.union (findUsedLocs env ty) (VarSet.union (findUsedLocs env val) needed)
extendNeeded b env needed
    = VarSet.union (findUsedLocs env (binderType b)) needed

findScrutinee : {vs : _} ->
                Env Term vs -> RawImp -> Maybe (Var vs)
findScrutinee {vs = n' :: _} (b :: bs) (IVar loc' n)
    = if n' == n && not (isLet b)
         then Just first
         else do MkVar p <- findScrutinee bs (IVar loc' n)
                 Just (MkVar (Later p))
findScrutinee _ _ = Nothing

getNestData : (Name, (Maybe Name, List (Var vars), a)) ->
              (Name, Maybe Name, List (Var vars))
getNestData (n, (mn, enames, _)) = (n, mn, enames)

bindCaseLocals : FC -> List (Name, Maybe Name, List (Var vars)) ->
                 List (Name, Name)-> RawImp -> RawImp
bindCaseLocals fc [] args rhs = rhs
bindCaseLocals fc ((n, mn, envns) :: rest) argns rhs
    = -- trace ("Case local " ++ show (n,mn,envns) ++ " from " ++ show argns) $
        ICaseLocal fc n (fromMaybe n mn)
                 (map getNameFrom envns)
                 (bindCaseLocals fc rest argns rhs)
  where
    getArg : List (Name, Name) -> Nat -> Maybe Name
    getArg [] _ = Nothing
    getArg ((_, x) :: xs) Z = Just x
    getArg (x :: xs) (S k) = getArg xs k

    getNameFrom : Var vars -> Name
    getNameFrom (MkVar {varIdx = i} _)
        = case getArg argns i of
               Nothing => n
               Just n' => n'

-- Whether a variable occurs in a term. Each kind of node a term holds terms
-- in is walked by a function of its own, so that every recursive call is on
-- a part of the term it was given.
mutual
  total
  occursPi : Var vs -> PiInfo (Term vs) -> Bool
  occursPi v (DefImplicit t) = occurs v t
  occursPi v _ = False

  total
  occursBinder : Var vs -> Binder (Term vs) -> Bool
  occursBinder v (Lam _ _ p ty) = occursPi v p || occurs v ty
  occursBinder v (Let _ _ val ty) = occurs v val || occurs v ty
  occursBinder v (Pi _ _ p ty) = occursPi v p || occurs v ty
  occursBinder v (PVar _ _ p ty) = occursPi v p || occurs v ty
  occursBinder v (PLet _ _ val ty) = occurs v val || occurs v ty
  occursBinder v (PVTy _ _ ty) = occurs v ty

  total
  occursIn : Var vs -> List (Term vs) -> Bool
  occursIn v [] = False
  occursIn v (t :: ts) = occurs v t || occursIn v ts

  total
  occurs : Var vs -> Term vs -> Bool
  occurs v (Local _ _ idx p) = v == MkVar p
  occurs v (Meta _ _ _ args) = occursIn v args
  occurs (MkVar v) (Bind _ _ b sc)
      = occursBinder (MkVar v) b || occurs (MkVar (Later v)) sc
  occurs v (App _ f a) = occurs v f || occurs v a
  occurs v (As _ _ n p) = occurs v n || occurs v p
  occurs v (TDelayed _ _ t) = occurs v t
  occurs v (TDelay _ _ t a) = occurs v t || occurs v a
  occurs v (TForce _ _ t) = occurs v t
  occurs v (Erased _ (Dotted t)) = occurs v t
  occurs v _ = False

-- Whether a metavariable is unsolved: its definition is still a hole.
stillHole : {auto c : Ref Ctxt Defs} -> Int -> Core Bool
stillHole i
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact (Resolved i) (gamma defs)
              | Nothing => pure False
         pure $ case definition gdef of
                     Hole {} => True
                     _ => False

-- Whether an unsolved metavariable is applied to a variable: the variable
-- occurs in its arguments, anywhere in the term.
mutual
  heldPi : {auto c : Ref Ctxt Defs} -> Var vs -> PiInfo (Term vs) -> Core Bool
  heldPi v (DefImplicit t) = inHoleArgs v t
  heldPi v _ = pure False

  heldBinder : {auto c : Ref Ctxt Defs} -> Var vs -> Binder (Term vs) -> Core Bool
  heldBinder v (Lam _ _ p ty) = pure (!(heldPi v p) || !(inHoleArgs v ty))
  heldBinder v (Let _ _ val ty) = pure (!(inHoleArgs v val) || !(inHoleArgs v ty))
  heldBinder v (Pi _ _ p ty) = pure (!(heldPi v p) || !(inHoleArgs v ty))
  heldBinder v (PVar _ _ p ty) = pure (!(heldPi v p) || !(inHoleArgs v ty))
  heldBinder v (PLet _ _ val ty) = pure (!(inHoleArgs v val) || !(inHoleArgs v ty))
  heldBinder v (PVTy _ _ ty) = inHoleArgs v ty

  heldIn : {auto c : Ref Ctxt Defs} -> Var vs -> List (Term vs) -> Core Bool
  heldIn v [] = pure False
  heldIn v (t :: ts) = pure (!(inHoleArgs v t) || !(heldIn v ts))

  inHoleArgs : {auto c : Ref Ctxt Defs} -> Var vs -> Term vs -> Core Bool
  inHoleArgs v (Meta _ _ i args)
      = if !(stillHole i)
           then pure (occursIn v args)
           else heldIn v args
  inHoleArgs (MkVar v) (Bind _ _ b sc)
      = pure (!(heldBinder (MkVar v) b) || !(inHoleArgs (MkVar (Later v)) sc))
  inHoleArgs v (App _ f a) = pure (!(inHoleArgs v f) || !(inHoleArgs v a))
  inHoleArgs v (As _ _ n p) = pure (!(inHoleArgs v n) || !(inHoleArgs v p))
  inHoleArgs v (TDelayed _ _ t) = inHoleArgs v t
  inHoleArgs v (TDelay _ _ t a) = pure (!(inHoleArgs v t) || !(inHoleArgs v a))
  inHoleArgs v (TForce _ _ t) = inHoleArgs v t
  inHoleArgs v _ = pure False

-- A variable replaced by another in the arguments of every unsolved
-- metavariable, and nowhere else: the same places `inHoleArgs` looks in.
mutual
  changeInHolesPi : {auto c : Ref Ctxt Defs} ->
                    (old : Var vs) -> (new : Var vs) -> PiInfo (Term vs) ->
                    Core (PiInfo (Term vs))
  changeInHolesPi old new Implicit = pure Implicit
  changeInHolesPi old new Explicit = pure Explicit
  changeInHolesPi old new AutoImplicit = pure AutoImplicit
  changeInHolesPi old new (DefImplicit t) = DefImplicit <$> changeInHoles old new t

  changeInHolesBinder : {auto c : Ref Ctxt Defs} ->
                        (old : Var vs) -> (new : Var vs) -> Binder (Term vs) ->
                        Core (Binder (Term vs))
  changeInHolesBinder old new (Lam fc r p ty)
      = Lam fc r <$> changeInHolesPi old new p <*> changeInHoles old new ty
  changeInHolesBinder old new (Let fc r val ty)
      = Let fc r <$> changeInHoles old new val <*> changeInHoles old new ty
  changeInHolesBinder old new (Pi fc r p ty)
      = Pi fc r <$> changeInHolesPi old new p <*> changeInHoles old new ty
  changeInHolesBinder old new (PVar fc r p ty)
      = PVar fc r <$> changeInHolesPi old new p <*> changeInHoles old new ty
  changeInHolesBinder old new (PLet fc r val ty)
      = PLet fc r <$> changeInHoles old new val <*> changeInHoles old new ty
  changeInHolesBinder old new (PVTy fc r ty) = PVTy fc r <$> changeInHoles old new ty

  changeInHolesOf : {auto c : Ref Ctxt Defs} ->
                    (old : Var vs) -> (new : Var vs) -> List (Term vs) ->
                    Core (List (Term vs))
  changeInHolesOf old new [] = pure []
  changeInHolesOf old new (t :: ts)
      = (::) <$> changeInHoles old new t <*> changeInHolesOf old new ts

  changeInHoles : {auto c : Ref Ctxt Defs} ->
                  (old : Var vs) -> (new : Var vs) -> Term vs -> Core (Term vs)
  changeInHoles old new (Meta fc nm i args)
      = if !(stillHole i)
           then pure (Meta fc nm i (changeVars old new args))
           else Meta fc nm i <$> changeInHolesOf old new args
  changeInHoles (MkVar old) (MkVar new) (Bind fc x b sc)
      = Bind fc x <$> changeInHolesBinder (MkVar old) (MkVar new) b
                  <*> changeInHoles (MkVar (Later old)) (MkVar (Later new)) sc
  changeInHoles old new (App fc f a)
      = App fc <$> changeInHoles old new f <*> changeInHoles old new a
  changeInHoles old new (As fc s n p)
      = As fc s <$> changeInHoles old new n <*> changeInHoles old new p
  changeInHoles old new (TDelayed fc r t) = TDelayed fc r <$> changeInHoles old new t
  changeInHoles old new (TDelay fc r t a)
      = TDelay fc r <$> changeInHoles old new t <*> changeInHoles old new a
  changeInHoles old new (TForce fc r t) = TForce fc r <$> changeInHoles old new t
  changeInHoles old new tm = pure tm

-- A case that splits a variable puts each clause's pattern in its place
-- throughout the case function's type. A metavariable made outside the
-- case, applied to that variable, would then stand applied to a
-- constructor in every clause, where no constraint on it can be solved (it
-- is outside the pattern fragment): the type the case must have, or an
-- argument's type that only the case's clauses determine, is never found.
-- So where an unsolved metavariable after it is applied to the variable,
-- the case function takes the variable twice: split, and again, at
-- quantity 0, just inside it and unsplit, which those metavariables are
-- applied to instead. The second is the same value at every call, so the
-- function's type, applied, is the one it had; inside a clause the
-- metavariables see a variable, so the clause can solve them. This is the
-- type with the variable at the given depth of its telescope taken twice,
-- and the second's name, where it is.
splitTwice : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             {0 vs : Scope} ->
             Nat -> Term vs -> Core (Maybe (Term vs, Name))
splitTwice (S k) (Bind fc x b sc)
    = do Just (sc', copy) <- splitTwice k sc
              | Nothing => pure Nothing
         pure (Just (Bind fc x b sc', copy))
splitTwice Z (Bind fc x b@(Pi pfc _ _ ty) sc)
    = if !(inHoleArgs (MkVar First) sc)
         then do copy <- genVarName (known Kscr)
                 sc' <- changeInHoles (MkVar (Later First)) (MkVar First)
                                      (the (Term (copy :: x :: vs)) (weaken sc))
                 pure (Just (Bind fc x b
                               (Bind fc copy (Pi pfc erased Explicit (weaken ty)) sc'),
                             copy))
         else pure Nothing
splitTwice _ _ = pure Nothing

-- How a case function takes its scrutinee: as an argument after the
-- environment's, the scrutinee being no variable of it; as the variable of
-- the environment it is, split in place; or as that variable taken twice,
-- split, and just inside it unsplit, under the name given (`splitTwice`).
data Taking : Scope -> Type where
     AfterEnv : Taking vs
     InPlace : Var vs -> Taking vs
     Twice : Var vs -> (copy : Name) -> Taking vs

export
caseBlock : {vars : _} ->
            {auto c : Ref Ctxt Defs} ->
            {auto m : Ref MD Metadata} ->
            {auto u : Ref UST UState} ->
            {auto dl : Ref DLY DelayedElabs} ->
            {auto e : Ref EST (EState vars)} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto o : Ref ROpts REPLOpts} ->
            RigCount ->
            ElabInfo -> FC ->
            NestedNames vars ->
            Env Term vars ->
            List FnOpt ->
            RawImp -> -- original scrutinee
            Term vars -> -- checked scrutinee
            Term vars -> -- its type
            RigCount -> -- its multiplicity
            List ImpClause -> Glued vars ->
            Core (Term vars, Glued vars)
caseBlock {vars} rigc elabinfo fc nest env opts scr scrtm scrty caseRig alts expected
    = do -- TODO (or to decide): Blodwen allowed ambiguities in the scrutinee
         -- to be delayed, but now I think it's better to have simpler
         -- resolution rules, and not delay

         est <- get EST
         fullImps <- getToBind fc (elabMode elabinfo)
                               (implicitMode elabinfo) env []
         log "elab.case" 5 $ "Doing a case under unbound implicits " ++ show fullImps

         scrn <- genVarName (known Kscr)
         casen <- genCaseName !(toFullNames (Resolved (defining est)))

         -- Update environment so that linear bindings which were used
         -- (esp. in the scrutinee!) are set to 0 in the case type
         let env = updateMults (linearUsed est) env
         defs <- get Ctxt
         parentDef <- lookupCtxtExact (Resolved (defining est)) (gamma defs)
         let vis = specified $ case parentDef of
                        Just gdef =>
                             if collapseDefault (visibility gdef) == Public
                                then Public
                                else Private
                        Nothing => Public

         -- if the scrutinee is ones of the arguments in 'env' we should
         -- split on that, rather than adding it as a new argument
         let splitOn = findScrutinee env scr

         caseretty_in <- getTerm expected

         u <- uniVar fc
         (caseretty, _) <- bindImplicits fc (implicitMode elabinfo) defs env
                                         fullImps caseretty_in (TType fc u)
         let casefnty
               = abstractFullEnvType fc (allow splitOn (mkExplicit env))
                            (maybe (Bind fc scrn (Pi fc caseRig Explicit scrty)
                                       (weaken caseretty))
                                   (const caseretty) splitOn)
         -- If we can normalise the type without the result being excessively
         -- big do it. It's the depth of stuck applications - 10 is already
         -- pretty much unreadable!
         casefnty <- normaliseSizeLimit defs 10 Env.empty casefnty
         (casefnty, taking) <- takenAs splitOn casefnty
         (erasedargs, _) <- findErased casefnty

         logEnv "elab.case" 10 "Case env" env
         logTermNF "elab.case" 2 ("Case function type: " ++ show casen) Env.empty casefnty
         traverse_ addToSave (keys (getMetas casefnty))

         -- If we've had to add implicits to the case type (because there
         -- were unbound implicits) then we're in a bit of a mess. Easiest
         -- way out is to throw an error and try again with the implicits
         -- actually bound! This is rather hacky, but a lot less fiddly than
         -- the alternative of fixing up the environment
         when (not (isNil fullImps)) $ findImpsIn fc Env.empty [] casefnty
         cidx <- addDef casen ({ eraseArgs := erasedargs }
                                (newDef fc casen (if isErased rigc then erased else top)
                                      Scope.empty casefnty vis None))

         traverse_ (processFnOpt fc False casen) opts

         -- set the totality of the case block to be the same as that
         -- of the parent function
         let tot = fromMaybe PartialOK $ do findSetTotal (flags !parentDef)
         log "elab.case" 5 $
           unwords [ "Setting totality requirement for", show casen
                   , "to", show tot]
         setFlag fc (Resolved cidx) (SetTotal tot)
         let caseRef : Term vars = Ref fc Func (Resolved cidx)

         let applyEnv = applyToFull fc caseRef env
         let appTm : Term vars = applyCase taking applyEnv scrtm

         let alts' = map (updateClause casen taking nest env) alts
         log "elab.case" 2 $ "Nested: " ++ show (map getNestData (names nest))
         log "elab.case" 2 $ "Generated alts: " ++ show alts'
         logTermNF "elab.case" 2 "Case application" env appTm

         -- Start with empty nested names, since we've extended the rhs with
         -- ICaseLocal so they'll get rebuilt with the right environment
         let nest' = MkNested []
         -- We don't want to keep rechecking delayed elaborators in the
         -- case block, because they're not going to make progress until
         -- we come out again, so save them
         olddelayed <- get DLY
         put DLY (the DelayedElabs [])
         processDecl [InCase] nest' Env.empty (IDef fc casen alts')

         -- If there's no duplication of the scrutinee in the block,
         -- flag it as inlinable.
         -- This will be the case either if the scrutinee is a variable, in
         -- which case the duplication won't hurt, or if there's no variable
         -- duplicated in the body (what ghc calls W-safe)
         -- We'll check that second condition later, after generating the
         -- runtime (erased) case trees
         let inlineOK = maybe False (const True) splitOn
         when inlineOK $ setFlag fc casen Inline

         put DLY olddelayed

         pure (appTm, gnf env caseretty)
  where
    -- Whether a pattern is a variable, which matches without splitting.
    varPattern : RawImp -> Bool
    varPattern (Implicit _ _) = True
    varPattern (IBindVar _ _) = True
    varPattern (IAs _ _ _ _ p) = varPattern p
    varPattern _ = False

    -- Whether a clause leaves the variable the case is on as it is.
    keepsVar : ImpClause -> Bool
    keepsVar (PatClause _ lhs _) = varPattern lhs
    keepsVar (WithClause _ lhs _ _ _ _ _) = varPattern lhs
    keepsVar (ImpossibleClause _ lhs) = varPattern lhs

    -- The case function's type, and how it takes its scrutinee. A variable
    -- it splits is taken twice where an unsolved metavariable is applied to
    -- it (`splitTwice`) and every clause splits it. A clause whose pattern
    -- there is a variable leaves it as it is, so it solves those
    -- metavariables without the second, and with it could not, since what
    -- it solves them to may mention its own metavariables, which depend on
    -- its variable, not on the second.
    takenAs : Maybe (Var vars) -> ClosedTerm -> Core (ClosedTerm, Taking vars)
    takenAs Nothing ty = pure (ty, AfterEnv)
    takenAs (Just v@(MkVar {varIdx = i} _)) ty
        = if any keepsVar alts
             then pure (ty, InPlace v)
             else do Just (ty', copy) <- splitTwice (minus (length vars) (S i)) ty
                          | Nothing => pure (ty, InPlace v)
                     pure (ty', Twice v copy)

    -- The case function applied to the environment, and to the scrutinee
    -- as it takes it: after the environment; in place of its variable; or
    -- in place of its variable twice.
    applyCase : Taking vars -> Term vars -> Term vars -> Term vars
    applyCase AfterEnv applyEnv scrtm = App fc applyEnv scrtm
    applyCase (InPlace _) applyEnv scrtm = applyEnv
    applyCase (Twice (MkVar {varIdx = i} _) _) applyEnv scrtm
        = let (f, args) = getFnArgs applyEnv
              pos = minus (length vars) (S i) in
              apply fc f (take (S pos) args ++ drop pos args)

    mkLocalEnv : Env Term vs -> Env Term vs
    mkLocalEnv [] = Env.empty
    mkLocalEnv (b :: bs)
        = let b' = if isLinear (multiplicity b)
                      then setMultiplicity b erased
                      else b in
              b' :: mkLocalEnv bs

    -- Return the original name in the environment, and what it needs to be
    -- called in the case block. We need to mapping to build the ICaseLocal
    -- so that it applies to the right original variable
    getBindName : Int -> Name -> List Name -> (Name, Name)
    getBindName idx n@(UN un) vs
       = if n `elem` vs then (n, MN (stem un) idx) else (n, n)
      where
        -- The user name's own identifier, so the case block's name for the
        -- variable displays as the variable does.
        stem : UserName -> Ident
        stem (Basic i) = i
        stem (Field i) = i
        stem Underscore = known K_
    getBindName idx n vs
       = if n `elem` vs then (n, MN (known K_cn) idx) else (n, n)

    -- Returns a list of names that nestednames should be applied to, mapped
    -- to what the name has become in the case block, and a list of terms for
    -- the LHS of the case to be applied to.
    addEnv : {vs : _} ->
             Int -> Env Term vs -> List Name -> (List (Name, Name), List RawImp)
    addEnv idx [] used = ([], [])
    addEnv idx {vs = v :: vs} (b :: bs) used
        = let n = getBindName idx v used
              (ns, rest) = addEnv (idx + 1) bs (snd n :: used)
              ns' = n :: ns in
              (ns', IAs fc EmptyFC UseLeft (snd n) (Implicit fc True) :: rest)

    -- Replace a variable in the argument list; if the reference is to
    -- a variable kept in the outer environment (therefore not an argument
    -- in the list) don't consume it
    replace : (idx : Nat) -> RawImp -> List RawImp -> List RawImp
    replace Z lhs (old :: xs)
       = let lhs' = case old of
                         IAs loc' nameLoc' side n _ => IAs loc' nameLoc' side n lhs
                         _ => lhs in
             lhs' :: xs
    replace (S k) lhs (x :: xs)
        = x :: replace k lhs xs
    replace _ _ xs = xs

    mkSplit : Taking vs ->
              RawImp -> List RawImp ->
              List RawImp
    mkSplit AfterEnv lhs args = reverse (lhs :: args)
    mkSplit (InPlace (MkVar {varIdx = i} prf)) lhs args
        = reverse (replace i lhs args)
    mkSplit (Twice (MkVar {varIdx = i} prf) copy) lhs args
        -- the second, unsplit, is a pattern variable just inside the split
        -- one, bound as the environment's variables are
        = let args' = replace i lhs args in
              reverse (take i args' ++
                       IAs fc EmptyFC UseLeft copy (Implicit fc True) :: drop i args')

    -- Names used in the pattern we're matching on, so don't bind them
    -- in the generated case block
    usedIn : RawImp -> List Name
    usedIn (IBindVar _ n) = [n]
    usedIn (IApp _ f a) = usedIn f ++ usedIn a
    usedIn (IAs _ _ _ n a) = n :: usedIn a
    usedIn (IAlternative _ _ alts) = concatMap usedIn alts
    usedIn (ITypeOrValue _ ovl) = concatMap usedIn (overlaidParts ovl)
    usedIn _ = []

    -- Get a name update for the LHS (so that if there's a nested data declaration
    -- the constructors are applied to the environment in the case block)
    nestLHS : FC -> (Name, (Maybe Name, List (Var vars), a)) -> (Name, RawImp)
    nestLHS fc (n, (mn, ns, t))
        = (n, apply (IVar fc (fromMaybe n mn))
                    (map (const (Implicit fc False)) ns))

    applyNested : NestedNames vars -> RawImp -> RawImp
    applyNested nest lhs
        = let fc = getFC lhs in
              substNames [] (map (nestLHS fc) (names nest)) lhs

    updateClause : Name -> Taking vars ->
                   NestedNames vars ->
                   Env Term vars -> ImpClause -> ImpClause
    updateClause casen taking nest env (PatClause loc' lhs rhs)
        = let (ns, args) = addEnv 0 env (usedIn lhs)
              args' = mkSplit taking lhs args
              lhs' = apply (IVar loc' casen) args' in
              PatClause loc' (applyNested nest lhs')
                        (bindCaseLocals loc' (map getNestData (names nest))
                                        ns rhs)
    -- With isn't allowed in a case block but include for completeness
    updateClause casen taking nest env (WithClause loc' lhs rig wval prf flags cs)
        = let (_, args) = addEnv 0 env (usedIn lhs)
              args' = mkSplit taking lhs args
              lhs' = apply (IVar loc' casen) args' in
              WithClause loc' (applyNested nest lhs') rig wval prf flags cs
    updateClause casen taking nest env (ImpossibleClause loc' lhs)
        = let (_, args) = addEnv 0 env (usedIn lhs)
              args' = mkSplit taking lhs args
              lhs' = apply (IVar loc' casen) args' in
              ImpossibleClause loc' (applyNested nest lhs')


-- The delayed elaborator of a case block. It is a function of its own,
-- given the cell of delayed elaborators and the expected type, rather than
-- the body of a lambda in checkCase: a local definition is applied to
-- everything its parent binds, so one used in the lambda would capture
-- checkCase's cell, and the lambda holds no glued type (see delayElab).
checkCaseDelayed : {vars : _} ->
                   {auto c : Ref Ctxt Defs} ->
                   {auto m : Ref MD Metadata} ->
                   {auto u : Ref UST UState} ->
                   {auto dl : Ref DLY DelayedElabs} ->
                   {auto e : Ref EST (EState vars)} ->
                   {auto s : Ref Syn SyntaxInfo} ->
                   {auto o : Ref ROpts REPLOpts} ->
                   RigCount -> ElabInfo ->
                   NestedNames vars -> Env Term vars ->
                   FC -> List FnOpt -> (scr : RawImp) -> (ty : RawImp) -> List ImpClause ->
                   Glued vars ->
                   Core (Term vars, Glued vars)
checkCaseDelayed rig elabinfo nest env fc opts scr scrty_in alts exp
      = do scrty_exp <- case scrty_in of
                             Implicit {} => guessScrType alts
                             _ => pure scrty_in
           u <- uniVar fc
           (scrtyv, scrtyt) <- check erased elabinfo nest env scrty_exp
                                     (Just (gType fc u))
           logTerm "elab.case" 10 "Expected scrutinee type" scrtyv
           -- Try checking at the given multiplicity; if that doesn't work,
           -- try checking at Rig1 (meaning that we're using a linear variable
           -- so the scrutinee should be linear)
           let chrig = if isErased rig then erased else top
           log "elab.case" 5 $ "Checking " ++ show scr ++ " at " ++ show chrig

           (scrtm_in, gscrty, caseRig) <- handle
              (do c <- runDelays (const True) $ check chrig elabinfo nest env scr (Just (gnf env scrtyv))
                  pure (fst c, snd c, chrig))
            $ \e => if misusesLinear e
                       then do c <- runDelays (const True) $ check linear elabinfo nest env scr
                                        (Just (gnf env scrtyv))
                               pure (fst c, snd c, linear)
                       else throw e

           scrty <- getTerm gscrty
           logTermNF "elab.case" 5 "Scrutinee type" env scrty
           defs <- get Ctxt
           checkConcrete !(nf defs env scrty)
           caseBlock rig elabinfo fc nest env opts scr scrtm_in scrty caseRig alts exp
  where
    -- For the moment, throw an error if we haven't been able to work out
    -- the type of the case scrutinee, because we'll need it to build the
    -- type of the case block. But (TODO) consider delaying on failure?
    checkConcrete : NF vs -> Core ()
    checkConcrete (NApp _ (NMeta n i _) _)
        = throw (GenericMsg fc "Can't infer type for case scrutinee")
    checkConcrete _ = pure ()

    applyTo : Defs -> RawImp -> ClosedNF -> Core RawImp
    applyTo defs ty (NBind fc _ (Pi _ _ Explicit _) sc)
        = applyTo defs (IApp fc ty (Implicit fc False))
               !(sc defs (toClosure defaultOpts Env.empty (Erased fc Placeholder)))
    applyTo defs ty (NBind _ x (Pi {}) sc)
        = applyTo defs (INamedApp fc ty x (Implicit fc False))
               !(sc defs (toClosure defaultOpts Env.empty (Erased fc Placeholder)))
    applyTo defs ty _ = pure ty

    -- Get the name and type of the family the scrutinee is in
    getRetTy : Defs -> ClosedNF -> Core (Maybe (Name, ClosedNF))
    getRetTy defs (NBind fc _ (Pi {}) sc)
        = getRetTy defs !(sc defs (toClosure defaultOpts Env.empty (Erased fc Placeholder)))
    getRetTy defs (NTCon _ n arity _)
        = do Just ty <- lookupTyExact n (gamma defs)
                  | Nothing => pure Nothing
             pure (Just (n, !(nf defs Env.empty ty)))
    getRetTy _ _ = pure Nothing

    -- Guess a scrutinee type by looking at the alternatives, so that we
    -- have a hint for building the case type
    guessScrType : List ImpClause -> Core RawImp
    guessScrType [] = pure $ Implicit fc False
    guessScrType (PatClause _ x _ :: xs)
        = case getFn x of
               IVar _ n =>
                  do defs <- get Ctxt
                     [(_, (_, ty))] <- lookupTyName (mapNestedName nest n) (gamma defs)
                         | _ => guessScrType xs
                     Just (tyn, tyty) <- getRetTy defs !(nf defs Env.empty ty)
                         | _ => guessScrType xs
                     applyTo defs (IVar fc tyn) tyty
               _ => guessScrType xs
    guessScrType (_ :: xs) = guessScrType xs

-- A case block written where a delayed value is expected, Lazy t or Inf
-- t, is the delayed value: it is elaborated as a delay of the block (which
-- checks the block at t). Checked at the delayed type, each alternative
-- would be delayed instead, so the block, and its scrutinee, would be
-- computed where the value is built: `ifThenElse True 1 (if boom 1 then 2
-- else 3)` would compute `boom 1`, which the program delays with the rest
-- of the argument.
checkCaseExpected : {vars : _} ->
                    {auto c : Ref Ctxt Defs} ->
                    {auto m : Ref MD Metadata} ->
                    {auto u : Ref UST UState} ->
                    {auto dl : Ref DLY DelayedElabs} ->
                    {auto e : Ref EST (EState vars)} ->
                    {auto s : Ref Syn SyntaxInfo} ->
                    {auto o : Ref ROpts REPLOpts} ->
                    RigCount -> ElabInfo ->
                    NestedNames vars -> Env Term vars ->
                    FC -> List FnOpt -> (scr : RawImp) -> (ty : RawImp) -> List ImpClause ->
                    Glued vars ->
                    Core (Term vars, Glued vars)
checkCaseExpected rig elabinfo nest env fc opts scr scrty_in alts expected
    = case !(getNF expected) of
           NDelayed _ r under =>
              checkDelayAt rig elabinfo nest env fc (MkDelaying r ByElaborator)
                           (ICase fc opts scr scrty_in alts) under
           _ => checkCaseDelayed rig elabinfo nest env fc opts scr scrty_in alts expected

export
checkCase : {vars : _} ->
            {auto c : Ref Ctxt Defs} ->
            {auto m : Ref MD Metadata} ->
            {auto u : Ref UST UState} ->
            {auto dl : Ref DLY DelayedElabs} ->
            {auto e : Ref EST (EState vars)} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto o : Ref ROpts REPLOpts} ->
            RigCount -> ElabInfo ->
            NestedNames vars -> Env Term vars ->
            FC -> List FnOpt -> (scr : RawImp) -> (ty : RawImp) -> List ImpClause ->
            Maybe (Glued vars) ->
            Core (Term vars, Glued vars)
checkCase rig elabinfo nest env fc opts scr scrty_in alts exp
    = delayElab fc rig env exp CaseBlock $ \dl, exp' =>
        checkCaseExpected {dl} rig elabinfo nest env fc opts scr scrty_in alts exp'
