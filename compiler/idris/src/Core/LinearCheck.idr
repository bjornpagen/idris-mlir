-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.LinearCheck

import Core.Case.CaseTree
import Core.Context.Log
import Core.Env
import Core.Normalise
import Core.Options
import Core.UnifyState
import Core.Value

import Libraries.Data.List.SizeOf
import Libraries.Data.SnocList.SizeOf

import Array

%default covering

-- The uses of the binders in scope, one for each use in a linear context,
-- each naming the binder it uses. A binder's quantity is the sum of its
-- uses in 0/1/ω, which is all a check of it reads.
Usage : Scoped
Usage vars = List (Var vars)

||| The quantity each binder of a scope is used at, by its position.
Uses : Scoped
Uses vars = Array [<length vars] RigCount

||| Closes a binder's scope: the sum of the binder's uses in 0/1/ω, and the
||| uses of the binders outside it, in the scope outside.
closeScope : Usage (n :: vars) -> (RigCount, Usage vars)
closeScope [] = (erased, [])
closeScope (MkVar First :: us) = let (q, outer) = closeScope us in (linear |+| q, outer)
closeScope (MkVar (Later p) :: us) = let (q, outer) = closeScope us in (q, MkVar p :: outer)

||| The binder a use names, as a place in its scope.
binderOf : Var vars -> Index [<length vars]
binderOf (MkVar p) = [<finIdx p]

||| The quantity each binder of a scope is used at: the uses grouped by the
||| binder each names, and each group summed in 0/1/ω, every use one, in
||| one pass over the uses.
usesOf : {vars : _} -> Usage vars -> Uses vars
usesOf us = sumUses (map binderOf us)
  where
    sumUses : List (Index [<length vars]) -> Uses vars
    sumUses owners = accumulate (|+|) (fill [<length vars] erased) (Array.fromList owners)
                                (fill [<length owners] linear)

||| The number of uses a message about a binder names. A quantity keeps no
||| count past one, so the uses of a binder used many times are counted for
||| the message, once, as it is thrown.
usesNamed : RigCount -> Var vars -> Usage vars -> Nat
usesNamed Rig0 _ _ = 0
usesNamed Rig1 _ _ = 1
usesNamed RigW v us = length (filter (== v) us)

mutual
  updateHoleUsageArgs : {0 vars : _} ->
                        {auto c : Ref Ctxt Defs} ->
                        {auto u : Ref UST UState} ->
                        (useInHole : Bool) ->
                        Var vars -> List (Var vars) ->
                        List (Term vars) -> Core Bool
  updateHoleUsageArgs useInHole var zs [] = pure False
  updateHoleUsageArgs useInHole var zs (a :: as)
      = do h <- updateHoleUsage useInHole var zs a
           h' <- updateHoleUsageArgs useInHole var zs as
           pure (h || h')

  -- The assumption here is that hole types are abstracted over the entire
  -- environment, so that they have the appropriate number of function
  -- arguments and there are no lets
  updateHoleType : {0 vars : _} ->
                   {auto c : Ref Ctxt Defs} ->
                   {auto u : Ref UST UState} ->
                   (useInHole : Bool) ->
                   Var vars -> List (Var vars) ->
                   Term vs -> List (Term vars) ->
                   Core (Term vs)
  updateHoleType useInHole var zs (Bind bfc nm (Pi fc' c e ty) sc) (Local _ r v _ :: as)
      -- if the argument to the hole type is the variable of interest,
      -- and the variable should be used in the hole, set it to Rig1,
      -- otherwise set it to Rig0
      = if varIdx var == v
           then do scty <- updateHoleType False var zs sc as
                   let c' = if useInHole then c else erased
                   pure (Bind bfc nm (Pi fc' c' e ty) scty)
           else if elem v (map varIdx zs)
                then do scty <- updateHoleType useInHole var zs sc as
                        pure (Bind bfc nm (Pi fc' erased e ty) scty)
                else do scty <- updateHoleType useInHole var zs sc as
                        pure (Bind bfc nm (Pi fc' c e ty) scty)
  updateHoleType useInHole var zs (Bind bfc nm (Pi fc' c e ty) sc) (a :: as)
      = do ignore $ updateHoleUsage False var zs a
           scty <- updateHoleType useInHole var zs sc as
           pure (Bind bfc nm (Pi fc' c e ty) scty)
  updateHoleType useInHole var zs ty as
      = do ignore $ updateHoleUsageArgs False var zs as
           pure ty

  updateHoleUsagePats : {auto c : Ref Ctxt Defs} ->
                        {auto u : Ref UST UState} ->
                        (useInHole : Bool) ->
                        Var vars -> List (Term vars) ->
                        (vs ** (Env Term vs, Term vs, Term vs)) ->
                        Core Bool
  updateHoleUsagePats {vars} useInHole var args (vs ** (env, lhs, rhs))
      = do -- Find the argument which corresponds to var
           let argpos = findArg Z args
           log "quantity.hole" 10 $ "At positions " ++ show argpos
           -- Find what it's position is in env by looking at the lhs args
           let vars = mapMaybe (findLocal (getArgs lhs)) argpos
           hs <- traverse (\vsel => updateHoleUsage useInHole vsel [] rhs)
                          vars
           pure (elem True hs)
    where
      findArg : Nat -> List (Term vars) -> List Nat
      findArg i [] = []
      findArg i (Local _ _ idx vel :: els)
          = if idx == varIdx var
               then i :: findArg (1 + i) els
               else findArg (1 + i) els
      findArg i (_ :: els) = findArg (1 + i) els

      findLocal : List (Term vs) -> Nat -> Maybe (Var vs)
      findLocal (Local _ _ _ p :: _) Z = Just (MkVar p)
      findLocal (As _ _ (Local _ _ _ p) _ :: _) Z = Just (MkVar p)
      findLocal (As _ _ _ (Local _ _ _ p) :: _) Z = Just (MkVar p)
      findLocal (_ :: els) (S k) = findLocal els k
      findLocal _ _ = Nothing

  updateHoleUsage : {0 vars : _} ->
                    {auto c : Ref Ctxt Defs} ->
                    {auto u : Ref UST UState} ->
                    (useInHole : Bool) ->
                    Var vars -> List (Var vars) ->
                    Term vars -> Core Bool
  updateHoleUsage useInHole (MkVar var) zs (Bind _ _ (Let _ _ val _) sc)
      = do h <- updateHoleUsage useInHole (MkVar var) zs val
           h' <- updateHoleUsage useInHole (MkVar (Later var)) (map weaken zs) sc
           pure (h || h')
  updateHoleUsage useInHole (MkVar var) zs (Bind _ n b sc)
      = updateHoleUsage useInHole (MkVar (Later var)) (map weaken zs) sc
  updateHoleUsage useInHole var zs (Meta fc n i args)
      = do defs <- get Ctxt
           Just gdef <- lookupCtxtExact (Resolved i) (gamma defs)
                | Nothing => updateHoleUsageArgs useInHole var zs args
           -- only update for holes with no definition yet
           case definition gdef of
                Hole {} =>
                   do ty <- typeOf gdef
                      ty' <- updateHoleType useInHole var zs ty args
                      updateTy i ty'
                      logTerm "quantity.hole.update" 5 ("New type of " ++
                                 show (fullname gdef)) ty'
                      logTerm "quantity.hole.update" 5 ("Updated from " ++
                                 show (fullname gdef)) ty
                      pure True
                _ => updateHoleUsageArgs useInHole var zs args
  updateHoleUsage useInHole var zs (As _ _ a p)
      = do h <- updateHoleUsage useInHole var zs a
           h' <- updateHoleUsage useInHole var zs a
           pure (h || h')
  updateHoleUsage useInHole var zs (TDelayed _ _ t)
      = updateHoleUsage useInHole var zs t
  updateHoleUsage useInHole var zs (TDelay _ _ _ t)
      = updateHoleUsage useInHole var zs t
  updateHoleUsage useInHole var zs (TForce _ _ t)
      = updateHoleUsage useInHole var zs t
  updateHoleUsage useInHole var zs tm
      = case getFnArgs tm of
             (Ref _ _ fn, args) =>
                  -- no need to look inside 'fn' for holes since we did that
                  -- when working through lcheckDef recursively
                  updateHoleUsageArgs useInHole var zs args
             (f, []) => pure False
             (f, args) => updateHoleUsageArgs useInHole var zs (f :: args)

-- Linearity checking of an already checked term. This serves two purposes:
--  + Checking correct usage of linear bindings
--  + updating hole types to reflect usage counts correctly
-- Returns term, normalised type, and a list of used variables
mutual
  lcheck : {vars : _} ->
           {auto c : Ref Ctxt Defs} ->
           {auto u : Ref UST UState } ->
           RigCount -> (erase : Bool) -> Env Term vars -> Term vars ->
           Core (Term vars, Glued vars, Usage vars)
  lcheck {vars} rig erase env (Local {name} fc x idx prf)
      = let b = getBinder prf env
            rigb = multiplicity b
            ty = binderType b in
            do log "quantity" 15 "lcheck Local"
               when (not erase) $ rigSafe rigb rig
               pure (Local fc x idx prf, gnf env ty, used rig)
    where
      rigSafe : RigCount -> RigCount -> Core ()
      rigSafe l r = when (l < r)
                         (throw (LinearMisuse fc (nameAt prf) l r))

      -- count the usage if we're in a linear context. If not, the usage doesn't
      -- matter
      used : RigCount -> Usage vars
      used r = if isLinear r then [MkVar prf] else []

  lcheck rig erase env (Ref fc nt fn)
      = do logC "quantity" 15 $ do pure "lcheck Ref \{show (nt)} \{show !(toFullNames fn)}"
           ty <- lcheckDef fc rig erase env fn
           pure (Ref fc nt fn, gnf env (embed ty), [])

  -- If the meta has a definition, and we're not in Rig0, expand it first
  -- and check the result.
  -- Otherwise, don't count variable usage in holes, so as far as linearity
  -- checking is concerned, update the type so that the binders
  -- are in Rig0
  lcheck {vars} rig erase env (Meta fc n idx args)
      = do log "quantity" 15 "lcheck Meta"
           defs <- get Ctxt
           Just gdef <- lookupCtxtExact (Resolved idx) (gamma defs)
                | _ => undefinedName fc n
           -- The type is read only where the answer depends on it.
           expand <- branchZero
                       (do ty <- typeOf gdef
                           pure (case ty of
                                      Erased {} => True -- defined elsewhere, need to expand
                                      _ => False))
                       (pure (case definition gdef of
                                   PMDef {} => True
                                   _ => False))
                       rig
           logC "quantity" 10 $ do
             def <- case definition gdef of
                         PMDef _ margs body =>
                              walkTree body (\leaf, tree => case tree of
                                STerm _ x => do tm <- leafTerm leaf {outer = []} x
                                                tm' <- toFullNames tm
                                                pure (show tm')
                                _ => pure "")
                         _ => pure ""
             pure (show rig ++ ": " ++ show n ++ " " ++ show fc ++ "\n"
                     ++ show def)
           if expand
              then expandMeta rig erase env n idx (definition gdef) args
              else do gty <- typeOf gdef
                      let ty : ClosedTerm
                             = case definition gdef of
                                    Hole {} => unusedHoleArgs args gty
                                    _ => gty
                      nty <- nf defs env (embed ty)
                      lcheckMeta rig erase env fc n idx args [] nty
    where
      unusedHoleArgs : List a -> Term vs -> Term vs
      unusedHoleArgs (_ :: args) (Bind bfc n (Pi fc _ e ty) sc)
          = Bind bfc n (Pi fc erased e ty) (unusedHoleArgs args sc)
      unusedHoleArgs args (Bind bfc n (Let fc c e ty) sc)
          = Bind bfc n (Let fc c e ty) (unusedHoleArgs args sc)
      unusedHoleArgs _ ty = ty

  lcheck rig_in erase env (Bind fc nm b sc)
      = do log "quantity" 15 "lcheck Bind"
           (b', bt, usedb) <- handleUnify (lcheckBinder rig erase env b)
                                 (\err =>
                                     case err of
                                          LinearMisuse _ _ r _ =>
                                             lcheckBinder rig erase env
                                                (setMultiplicity b linear)
                                          _ => throw err)
           -- Anything linear can't be used in the scope of a lambda, if we're
           -- checking in general context
           let env' = if rig_in == top
                         then case b of
                              Lam {} => eraseLinear env
                              _ => env
                         else env
           (sc', sct, usedsc) <- lcheck rig erase (b' :: env') sc

           let (used_in, usedOutside) = closeScope usedsc
           holeFound <- if not erase && isLinear (multiplicity b)
                           then updateHoleUsage (isErased used_in)
                                         first
                                         (map weaken (getErased env'))
                                         sc'
                           else pure False

           -- if there's a hole, assume it will contain the missing usage
           -- if there is none already
           let used = if isLinear ((multiplicity b) |*| rig) &&
                         holeFound && isErased used_in
                         then linear
                         else used_in

           when (not erase) $
               checkUsageOK used (usesNamed used first usedsc) ((multiplicity b) |*| rig)
           defs <- get Ctxt
           discharge defs env fc nm b' bt sc' sct (usedb ++ usedOutside)
    where
      rig : RigCount
      rig = case b of
                 Pi {} =>
                      if isErased rig_in
                         then erased
                         else top -- checking as if an inspectable run-time type
                 Let {} => rig_in
                 _ => if isErased rig_in
                         then erased
                         else linear

      checkUsageOK : RigCount -> Lazy Nat -> RigCount -> Core ()
      checkUsageOK used named r = when (isLinear r && not (isLinear used))
                                       (throw (LinearUsed fc named nm))

  lcheck rig erase env (App fc f a)
      = do logC "quantity" 15 $ do pure "lcheck App \{show !(toFullNames f)} \{show !(toFullNames a)}"
           (f', gfty, fused) <- lcheck rig erase env f
           defs <- get Ctxt
           fty <- getNF gfty
           case undot fty of
                NBind _ _ (Pi _ rigf _ ty) scdone =>
                     -- if the argument is borrowed, it's okay to use it in
                     -- unrestricted context, because we'll be out of the
                     -- application without spending it
                   do let checkRig = rigf |*| rig
                      (a', gaty, aused) <- lcheck checkRig erase env a
                      sc' <- scdone defs (toClosure defaultOpts env a')
                      let aerased = if erase && isErased rigf then Erased fc Placeholder else a'
                      pure (App fc f' aerased,
                            glueBack defs env sc',
                            fused ++ aused)
                NApp _ (NRef _ n) _ =>
                      do Just _ <- lookupCtxtExact n (gamma defs)
                              | _ => undefinedName fc n
                         tfty <- getTerm gfty
                         needFunctionType f' gfty
                NErased _ Placeholder =>
                  do when (not erase) $ needFunctionType f' gfty
                     -- we don't do any linearity checking when `erase` is set
                     -- so returning an empty usage is fine
                     pure (App fc f a, gErased fc, [])
                _ =>
                  needFunctionType f' gfty
    where
      needFunctionType : Term vars -> Glued vars -> Core _
      needFunctionType f gfty =
        do tfty <- getTerm gfty
           throw (GenericMsg fc ("Linearity checking failed on " ++ show !(toFullNames f) ++
                 " (" ++ show !(toFullNames tfty) ++ " not a function type)"))

      undot : NF vars -> NF vars
      undot (NErased _ (Dotted tm)) = tm
      undot tm = tm

  lcheck rig erase env (As fc s as pat)
      = do log "quantity" 15 "lcheck As"
           (as', _, _) <- lcheck rig erase env as
           (pat', pty, u) <- lcheck rig erase env pat
           pure (As fc s as' pat', pty, u)
  lcheck rig erase env (TDelayed fc r ty)
      = do log "quantity" 15 "lcheck Delayed"
           (ty', _, u) <- lcheck rig erase env ty
           pure (TDelayed fc r ty', gType fc (MN (known Ktop) 0), u)
  lcheck rig erase env (TDelay fc d ty val)
      = do (ty', _, _) <- lcheck erased erase env ty
           (val', gty, u) <- lcheck rig erase env val
           ty <- getTerm gty
           pure (TDelay fc d ty' val', gnf env (TDelayed fc d.reason ty), u)
  lcheck rig erase env (TForce fc r val)
      = do log "quantity" 15 "lcheck Force"
           (val', gty, u) <- lcheck rig erase env val
           tynf <- getNF gty
           case tynf of
                NDelayed _ r narg
                    => do defs <- get Ctxt
                          pure (TForce fc r val', glueBack defs env narg, u)
                _ => throw (GenericMsg fc "Not a delayed type")
  lcheck rig erase env (PrimVal fc c)
      = do log "quantity" 15 "lcheck PrimVal"
           pure (PrimVal fc c, gErased fc, [])
  lcheck rig erase env (Erased fc i)
      = do log "quantity" 15 "lcheck Erased"
           pure (Erased fc i, gErased fc, [])
  lcheck rig erase env (TType fc u)
      -- Not universe checking here, just use the top of the hierarchy
      = do log "quantity" 15 "lcheck TType"
           pure (TType fc u, gType fc (MN (known Ktop) 0), [])

  lcheckBinder : {vars : _} ->
                 {auto c : Ref Ctxt Defs} ->
                 {auto u : Ref UST UState} ->
                 RigCount -> (erase : Bool) -> Env Term vars ->
                 Binder (Term vars) ->
                 Core (Binder (Term vars), Glued vars, Usage vars)
  lcheckBinder rig erase env (Lam fc c x ty)
      = do (tyv, tyt, _) <- lcheck erased erase env ty
           pure (Lam fc c x tyv, tyt, [])
  lcheckBinder rig erase env (Let fc rigc val ty)
      = do (tyv, tyt, _) <- lcheck erased erase env ty
           (valv, valt, vs) <- lcheck (rig |*| rigc) erase env val
           pure (Let fc rigc valv tyv, tyt, vs)
  lcheckBinder rig erase env (Pi fc c x ty)
      = do (tyv, tyt, _) <- lcheck (rig |*| c) erase env ty
           pure (Pi fc c x tyv, tyt, [])
  lcheckBinder rig erase env (PVar fc c p ty)
      = do (tyv, tyt, _) <- lcheck erased erase env ty
           pure (PVar fc c p tyv, tyt, [])
  lcheckBinder rig erase env (PLet fc rigc val ty)
      = do (tyv, tyt, _) <- lcheck erased erase env ty
           (valv, valt, vs) <- lcheck (rig |*| rigc) erase env val
           pure (PLet fc rigc valv tyv, tyt, vs)
  lcheckBinder rig erase env (PVTy fc c ty)
      = do (tyv, tyt, _) <- lcheck erased erase env ty
           pure (PVTy fc c tyv, tyt, [])

  discharge : {vars : _} ->
              Defs -> Env Term vars ->
              FC -> (nm : Name) -> Binder (Term vars) -> Glued vars ->
              Term (nm :: vars) -> Glued (nm :: vars) -> Usage vars ->
              Core (Term vars, Glued vars, Usage vars)
  discharge defs env fc nm (Lam fc' c x ty) gbindty scope gscopety used
       = do scty <- getTerm gscopety
            pure (Bind fc nm (Lam fc' c x ty) scope,
                  gnf env (Bind fc nm (Pi fc' c x ty) scty), used)
  discharge defs env fc nm (Let fc' c val ty) gbindty scope gscopety used
       = do scty <- getTerm gscopety
            pure (Bind fc nm (Let fc' c val ty) scope,
                  gnf env (Bind fc nm (Let fc' c val ty) scty), used)
  discharge defs env fc nm (Pi fc' c x ty) gbindty scope gscopety used
       = pure (Bind fc nm (Pi fc' c x ty) scope, gbindty, used)
  discharge defs env fc nm (PVar fc' c p ty) gbindty scope gscopety used
       = do scty <- getTerm gscopety
            pure (Bind fc nm (PVar fc' c p ty) scope,
                  gnf env (Bind fc nm (PVTy fc' c ty) scty), used)
  discharge defs env fc nm (PLet fc' c val ty) gbindty scope gscopety used
       = do scty <- getTerm gscopety
            pure (Bind fc nm (PLet fc' c val ty) scope,
                  gnf env (Bind fc nm (PLet fc' c val ty) scty), used)
  discharge defs env fc nm (PVTy fc' c ty) gbindty scope gscopety used
       = pure (Bind fc nm (PVTy fc' c ty) scope, gbindty, used)

  data ArgUsage
       = UseAny -- RigW so we don't care
       | Use0 -- argument position not used
       | Use1 -- argument position used exactly once
       | UseKeep -- keep as is
       | UseUnknown -- hole, so can't tell

  Show ArgUsage where
    show UseAny = "any"
    show Use0 = "0"
    show Use1 = "1"
    show UseKeep = "keep"
    show UseUnknown = "unknown"

  -- Check argument usage in case blocks. Returns a list of how each argument
  -- in the case block is used, to build the appropriate type for the outer
  -- block.
  getArgUsage : {auto c : Ref Ctxt Defs} ->
                {auto e : Ref UST UState} ->
                FC -> RigCount -> ClosedTerm ->
                List (vs ** (Env Term vs, Term vs, Term vs)) ->
                Core (List ArgUsage)
  getArgUsage topfc rig ty pats
      = do us <- traverse (getPUsage ty) pats
           pure (map snd !(combine us))
    where
      getCaseUsage : Term ns -> Env Term vs -> List (Term vs) ->
                     Uses vs -> Term vs ->
                     Core (List (Name, ArgUsage))
      getCaseUsage ty env (As _ _ _ p :: args) uses rhs
          = getCaseUsage ty env (p :: args) uses rhs
      getCaseUsage (Bind _ n (Pi _ rig _ ty) sc) env (arg :: args) uses rhs
          = if isLinear rig
               then case arg of
                         (Local _ _ idx p) =>
                           do rest <- getCaseUsage sc env args uses rhs
                              let used_in = uses !! binderOf (MkVar p)
                              holeFound <- updateHoleUsage (isErased used_in) (MkVar p) [] rhs
                              let ause = case used_in of
                                              Rig0 => if holeFound then UseUnknown else Use0
                                              _ => Use1
                              pure ((n, ause) :: rest)
                         _ => do elseCase
               else elseCase
          where
            elseCase : Core (List (Name, ArgUsage))
            elseCase = do rest <- getCaseUsage sc env args uses rhs
                          pure $ if isErased rig
                             then ((n, Use0) :: rest)
                             else ((n, UseKeep) :: rest)
      getCaseUsage tm env args uses rhs = pure []

      checkUsageOK : FC -> RigCount -> Lazy Nat -> Name -> Bool -> RigCount -> Core ()
      checkUsageOK fc used named nm isloc rig
          = when (isLinear rig && ((isloc && used == RigW) || (not isloc && not (isLinear used))))
                 (throw (LinearUsed fc named nm))

      -- Is the variable one of the lhs arguments; i.e. do we treat it as
      -- affine rather than linear
      isLocArg : Var vars -> List (Term vars) -> Bool
      isLocArg p [] = False
      isLocArg p (Local _ _ idx _ :: args)
          = idx == varIdx p || isLocArg p args
      isLocArg p (As _ _ tm pat :: args)
          = isLocArg p (tm :: pat :: args)
      isLocArg p (_ :: args) = isLocArg p args

      -- As checkEnvUsage in general, but it's okay for local variables to
      -- remain unused (since in that case, they must be used outside the
      -- case block)
      checkEnvUsage : {vars : _} ->
                      SizeOf done ->
                      RigCount ->
                      Env Term vars -> Usage (done <>> vars) -> Uses (done <>> vars) ->
                      List (Term (done <>> vars)) ->
                      Term (done <>> vars) -> Core ()
      checkEnvUsage s rig [] usage uses args tm = pure ()
      checkEnvUsage s rig {done} {vars = nm :: xs} (b :: env) usage uses args tm
          = do let pos = mkVarChiply s
               let used_in = uses !! binderOf pos

               holeFound <- if isLinear (multiplicity b)
                               then updateHoleUsage (isErased used_in) pos [] tm
                               else pure False
               let used = if isLinear ((multiplicity b) |*| rig) &&
                             holeFound && isErased used_in
                             then linear
                             else used_in
               checkUsageOK (getLoc (binderType b))
                            used (usesNamed used pos usage) nm (isLocArg pos args)
                                    ((multiplicity b) |*| rig)
               checkEnvUsage (s :< nm) rig env usage uses args tm

      getPUsage : ClosedTerm -> (vs ** (Env Term vs, Term vs, Term vs)) ->
                  Core (List (Name, ArgUsage))
      getPUsage ty (_ ** (penv, lhs, rhs))
          = do logEnv "quantity" 10 "Env" penv
               logTerm "quantity" 10 "LHS" lhs
               logTerm "quantity" 5 "Linear check in case RHS" rhs
               (rhs', _, used) <- lcheck rig False penv rhs
               log "quantity" 10 $ "Used: " ++ show used
               let args = getArgs lhs
               let uses = usesOf used
               checkEnvUsage [<] rig penv used uses args rhs'
               ause <- getCaseUsage ty penv args uses rhs
               log "quantity" 10 $ "Arg usage: " ++ show ause
               pure ause

      combineUsage : (Name, ArgUsage) -> (Name, ArgUsage) ->
                     Core (Name, ArgUsage)
      combineUsage (n, Use0) (_, Use1)
          = throw (GenericMsg topfc ("Inconsistent usage of " ++ show n ++ " in case branches"))
      combineUsage (n, Use1) (_, Use0)
          = throw (GenericMsg topfc ("Inconsistent usage of " ++ show n ++ " in case branches"))
      combineUsage (n, UseAny) _ = pure (n, UseAny)
      combineUsage _ (n, UseAny) = pure (n, UseAny)
      combineUsage (n, UseKeep) _ = pure (n, UseKeep)
      combineUsage _ (n, UseKeep) = pure (n, UseKeep)
      combineUsage (n, UseUnknown) _ = pure (n, UseUnknown)
      combineUsage _ (n, UseUnknown) = pure (n, UseUnknown)
      combineUsage x y = pure x

      combineUsages : List (Name, ArgUsage) -> List (Name, ArgUsage) ->
                      Core (List (Name, ArgUsage))
      combineUsages [] [] = pure []
      combineUsages (u :: us) (v :: vs)
          = do u' <- combineUsage u v
               us' <- combineUsages us vs
               pure (u' :: us')
      combineUsages _ _ = throw (InternalError "Argument usage lists inconsistent")

      combine : List (List (Name, ArgUsage)) ->
                Core (List (Name, ArgUsage))
      combine [] = pure []
      combine [x] = pure x
      combine (x :: xs)
          = do xs' <- combine xs
               combineUsages x xs'

  lcheckDef : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              FC -> RigCount -> (erase : Bool) -> Env Term vars -> Name ->
              Core ClosedTerm
  lcheckDef fc rig True env n
      = do defs <- get Ctxt
           Just def <- lookupCtxtExact n (gamma defs)
                | Nothing => undefinedName fc n
           typeOf def
  lcheckDef fc rig False env n
      = do defs <- get Ctxt
           let Just idx = getNameID n (gamma defs)
                | Nothing => undefinedName fc n
           Just def <- lookupCtxtExact (Resolved idx) (gamma defs)
                | Nothing => undefinedName fc n
           rigSafe (multiplicity def) rig
           if linearChecked def
              then typeOf def
              else case definition def of
                        PMDef _ _ body =>
                            do ty <- typeOf def
                               pats <- clausesOf body
                               u <- getArgUsage (getLoc ty) rig ty pats
                               log "quantity" 5 $ "Overall arg usage " ++ show u
                               let ty' = updateUsage u ty
                               updateTy idx ty'
                               setLinearCheck idx True
                               logTerm "quantity" 5 ("New type of " ++
                                          show (fullname def)) ty'
                               logTerm "quantity" 5 ("Updated from " ++
                                          show (fullname def)) ty
                               pure ty'
                        _ => typeOf def
    where
      updateUsage : List ArgUsage -> Term ns -> Term ns
      updateUsage (u :: us) (Bind bfc n (Pi fc c e ty) sc)
          = let sc' = updateUsage us sc
                c' = case u of
                          Use0 => erased
                          Use1 => linear -- ignore usage elsewhere, we checked here
                          UseUnknown => c -- don't know, assumed unchanged and update hole types
                          UseKeep => c -- matched here, so count usage elsewhere
                          UseAny => c in -- no constraint, so leave alone
                Bind bfc n (Pi fc c' e ty) sc'
      updateUsage _ ty = ty

      rigSafe : RigCount -> RigCount -> Core ()
      rigSafe a b = when (a < b)
                         (throw (LinearMisuse fc !(getFullName n) a b))

  expandMeta : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               RigCount -> (erase : Bool) -> Env Term vars ->
               Name -> Int -> Def -> List (Term vars) ->
               Core (Term vars, Glued vars, Usage vars)
  expandMeta rig erase env n idx (PMDef _ [] body) args
      = do STerm _ fn <- treeOf body
               | ct => throw (InternalError ("Badly formed metavar solution " ++ show n ++ " " ++ show ct))
           tm <- substMeta fn (embed fn) args zero Subst.empty
           lcheck rig erase env tm
    where
      -- The solution is given whole too, for the message.
      substMeta : {drop, vs : _} ->
                  ClosedTerm -> Term (drop ++ vs) -> List (Term vs) ->
                  SizeOf drop -> SubstEnv drop vs ->
                  Core (Term vs)
      substMeta fn (Bind bfc n (Lam _ c e ty) sc) (a :: as) drop env
          = substMeta fn sc as (suc drop) (a :: env)
      substMeta fn (Bind bfc n (Let _ c val ty) sc) as drop env
          = substMeta fn (subst val sc) as drop env
      substMeta fn rhs [] drop env = pure (substs drop env rhs)
      substMeta fn rhs _ _ _ = throw (InternalError ("Badly formed metavar solution " ++ show n ++ " " ++ show fn))
  expandMeta rig erase env n idx def _
      = throw (InternalError ("Badly formed metavar solution " ++ show n ++ " " ++ show def))

  lcheckMeta : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               RigCount -> Bool -> Env Term vars ->
               FC -> Name -> Int ->
               (args : List (Term vars)) ->
               (checked : List (Term vars)) ->
               NF vars -> Core (Term vars, Glued vars, Usage vars)
  lcheckMeta rig erase env fc n idx
             (arg :: args) chk (NBind _ _ (Pi _ rigf _ ty) sc)
      = do let checkRig = rigf |*| rig
           (arg', gargTy, aused) <- lcheck checkRig erase env arg
           defs <- get Ctxt
           sc' <- sc defs (toClosure defaultOpts env arg')
           let aerased = if erase && isErased rigf
                            then Erased fc Placeholder
                            else arg'
           (tm, gty, u) <- lcheckMeta rig erase env fc n idx args
                                      (aerased :: chk) sc'
           pure (tm, gty, aused ++ u)
  lcheckMeta rig erase env fc n idx (arg :: args) chk nty
      = do defs <- get Ctxt
           empty <- clearDefs defs
           ty <- quote empty env nty
           throw (GenericMsg fc ("Linearity checking failed on metavar "
                      ++ show !(toFullNames n) ++ " (" ++ show !(toFullNames ty)
                      ++ " not a function type)"))
  lcheckMeta rig erase env fc n idx [] chk nty
      = do defs <- get Ctxt
           pure (Meta fc n idx (reverse chk), glueBack defs env nty, [])


checkEnvUsage : {vars : _} ->
                {auto c : Ref Ctxt Defs} ->
                {auto u : Ref UST UState} ->
                FC -> SizeOf done -> RigCount ->
                Env Term vars -> Usage (done <>> vars) -> Uses (done <>> vars) ->
                Term (done <>> vars) ->
                Core ()
checkEnvUsage fc s rig [] usage uses tm = pure ()
checkEnvUsage fc s rig {vars = nm :: xs} (b :: env) usage uses tm
    = do let pos = mkVarChiply s
         let used_in = uses !! binderOf pos

         holeFound <- if isLinear (multiplicity b)
                         then updateHoleUsage (isErased used_in) pos [] tm
                         else pure False
         let used = if isLinear ((multiplicity b) |*| rig) &&
                       holeFound && isErased used_in
                       then linear
                       else used_in
         checkUsageOK used (usesNamed used pos usage) ((multiplicity b) |*| rig)
         checkEnvUsage fc (s :< nm) rig env usage uses tm
  where
    checkUsageOK : RigCount -> Lazy Nat -> RigCount -> Core ()
    checkUsageOK used named r = when (isLinear r && not (isLinear used))
                                     (throw (LinearUsed fc named nm))

-- Linearity check an elaborated term. If 'erase' is set, erase anything that's in
-- a Rig0 argument position (we can't do this until typechecking is complete, though,
-- since it might be used for unification/reasoning elsewhere, so we only do this for
-- definitions ready for compilation).
export
linearCheck : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              FC -> RigCount -> (erase : Bool) ->
              Env Term vars -> Term vars ->
              Core (Term vars)
linearCheck fc rig erase env tm
    = do logTerm "quantity" 5 "Linearity check on " tm
         logEnv "quantity" 5 "In env" env
         (tm', _, used) <- lcheck rig erase env tm
         log "quantity" 5 $ "Used: " ++ show used
         when (not erase) $ checkEnvUsage fc [<] rig env used (usesOf used) tm'
         pure tm'
