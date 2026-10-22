-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module TTImp.Elab

import Core.Env
import Core.LinearCheck
import Core.Metadata
import Core.Unify

import Idris.REPL.Opts
import Idris.Syntax

import TTImp.Elab.Check
import TTImp.Elab.Delayed
import TTImp.Elab.Term
import TTImp.TTImp

import Libraries.Data.IntMap
import Libraries.Data.NameMap

%default covering

findPLetRenames : {vars : _} ->
                  (marks : List Name) -> Term vars -> List (Name, (RigCount, Name))
findPLetRenames marks (Bind fc n (PLet _ c (Local _ _ idx p) ty) sc)
    = case nameAt p of
           x@(MN {}) => if n `elem` marks
                           then findPLetRenames marks sc
                           else (x, (c, n)) :: findPLetRenames marks sc
           _ => findPLetRenames marks sc
findPLetRenames marks (Bind fc n _ sc) = findPLetRenames marks sc
findPLetRenames marks tm = []

-- A mark over a variable gives way to it: the variable is the clause's own
-- for that argument, which the case tree never splits, and nothing names
-- the mark.
markDrops : (marks : List Name) -> Term vars -> List Name
markDrops marks (Bind fc n (PLet _ _ (Local {}) _) sc)
    = if n `elem` marks then n :: markDrops marks sc else markDrops marks sc
markDrops marks (Bind fc n _ sc) = markDrops marks sc
markDrops marks tm = []

doPLetRenames : {vars : _} ->
                List (Name, (RigCount, Name)) ->
                List Name -> Term vars -> Term vars
doPLetRenames ns drops (Bind fc n b@(PLet {}) sc)
    = if n `elem` drops
         then subst (Erased fc Placeholder) (doPLetRenames ns drops sc)
         else Bind fc n b (doPLetRenames ns drops sc)
doPLetRenames ns drops (Bind fc n b sc)
    = case lookup n ns of
           Just (c, n') =>
             Bind fc n' (setMultiplicity b (c `lub` (multiplicity b)))
                     (doPLetRenames ns (n' :: drops) (compat sc))
           Nothing => Bind fc n b (doPLetRenames ns drops sc)
doPLetRenames ns drops sc = sc

getRigNeeded : ElabMode -> RigCount
getRigNeeded InType = erased -- unrestricted usage in types
getRigNeeded (InLHS r) = if isErased r then erased
                                     else linear
getRigNeeded _ = linear

-- Make sure the types of holes have the references to solved holes normalised
-- away (since solved holes don't get written to .tti)
export
normaliseHoleTypes : {auto c : Ref Ctxt Defs} ->
                     {auto u : Ref UST UState} ->
                     Core ()
normaliseHoleTypes
    = do ust <- get UST
         let hs = keys (holes ust)
         defs <- get Ctxt
         traverse_ (normaliseH defs) hs
  where
    updateType : Defs -> Int -> GlobalDef -> Core ()
    updateType defs i def
        = do ty' <- case !(tryNormaliseSizeLimit defs 10 Env.empty (type def)) of
                         Quoted ty' => pure ty'
                         TooDeep => normaliseHoles defs Env.empty (type def)
             ignore $ addDef (Resolved i) ({ type := ty' } def)

    normaliseH : Defs -> Int -> Core ()
    normaliseH defs i
        = whenJust !(lookupCtxtExact (Resolved i) (gamma defs)) $ \ gdef =>
            case definition gdef of
              Hole {} => updateType defs i gdef
              _ => pure ()

export
addHoleToSave : {auto c : Ref Ctxt Defs} ->
                Name -> Core ()
addHoleToSave n
    = do defs <- get Ctxt
         Just ty <- lookupTyExact n (gamma defs)
              | Nothing => pure ()
         let ms = keys (getMetas ty)
         addToSave n
         traverse_ addToSave ms

-- Elaborate a term, returning with it and its type the as-patterns it
-- binds for implicit arguments its patterns leave out (`marks`).
export
elabTermSubMarked : {inner, vars : _} ->
                     {auto c : Ref Ctxt Defs} ->
                     {auto m : Ref MD Metadata} ->
                     {auto u : Ref UST UState} ->
                     {auto dl : Ref DLY DelayedElabs} ->
                     {auto s : Ref Syn SyntaxInfo} ->
                     {auto o : Ref ROpts REPLOpts} ->
                     Int -> ElabMode -> List ElabOpt ->
                     NestedNames vars -> Env Term vars ->
                     Env Term inner -> Thin inner vars ->
                     RawImp -> Maybe (Glued vars) ->
                     Core (Term vars, Glued vars, List Name)
elabTermSubMarked {vars} defining mode opts nest env env' sub tm ty
    = do let incase = elem InCase opts
         let inTrans = elem InTrans opts

         -- Record the current hole state; we only check the list of current
         -- holes is completely solved so this needs to be accurate.
         oldhs <- if not incase
                     then saveHoles
                     else pure empty
         olddelayed <- get DLY
         put DLY (the DelayedElabs [])
         constart <- getNextEntry

         defs <- get Ctxt
         e <- newRef EST (initEStateSub defining env' sub)
         let rigc = getRigNeeded mode

         (chktm, chkty) <- check {e} rigc (initElabInfo mode) nest env tm ty
         -- Final retry of constraints and delayed elaborations
         -- - Solve any constraints, then retry any delayed elaborations
         -- - Finally, last attempts at solving constraints, but this
         --   is most likely just to be able to display helpful errors
         let solvemode = case mode of
                              InLHS _ => inLHS
                              _ => inTerm
         solveConstraints solvemode Normal
         logTerm "elab" 5 "Looking for delayed in " chktm
         delayed <- get DLY
         catch (retryDelayed solvemode
                             (sortBy (\x, y => compare (fst x) (fst y))
                                       delayed))
                 (\err =>
                    do put DLY olddelayed
                       throw err)
         put DLY olddelayed
         solveConstraintsAfter constart solvemode MatchArgs

         -- As long as we're not in the RHS of a case block,
         -- finish off constraint solving
         -- On the LHS the constraint solving is used to handle overloading
         when (not incase || isJust (isLHS mode)) $
           -- resolve any default hints
           do log "elab" 5 "Resolving default hints"
              solveConstraintsAfter constart solvemode Defaults
              -- perhaps resolving defaults helps...
              -- otherwise, this last go is most likely just to give us more
              -- helpful errors.
              solveConstraintsAfter constart solvemode LastChance

         dumpConstraints "elab" 4 False
         defs <- get Ctxt
         chktm <- normaliseArgHoles defs env chktm

         -- Linearity and hole checking.
         -- on the LHS, all holes need to have been solved
         chktm <- case mode of
              InLHS _ => do when (not incase) $ checkUserHolesAfter constart True
                            pure chktm
              InTransform => do when (not incase) $ checkUserHolesAfter constart True
                                pure chktm
              -- elsewhere, all unification problems must be
              -- solved, though we defer that if it's a case block since we
              -- might learn a bit more later.
              _ => if (not incase)
                      then do checkUserHolesAfter constart inTrans
                              linearCheck (getFC tm) rigc False env chktm
                          -- Linearity checking looks in case blocks, so no
                          -- need to check here.
                      else pure chktm
         normaliseHoleTypes
         -- Put the current hole state back to what it was (minus anything
         -- which has been solved in the meantime)
         when (not incase) $
           do hs <- getHoles
              restoreHoles (addHoles empty hs (toList oldhs))

         -- Make a note to save all the user holes and the things they
         -- reference
         est <- get EST
         traverse_ addHoleToSave (keys (saveHoles est))

         -- On the LHS, finish by tidying up the plets (changing things that
         -- were of the form x@_, where the _ is inferred to be a variable,
         -- to just x)
         case mode of
              InLHS _ =>
                 do let vs = findPLetRenames (marks est) chktm
                    let drops = markDrops (marks est) chktm
                    let ret = doPLetRenames vs drops chktm
                    pure (ret, gnf env (doPLetRenames vs drops !(getTerm chkty)),
                          marks est)
              _ => do dumpConstraints "elab" 2 False
                      pure (chktm, chkty, marks est)
  where
    addHoles : (acc : IntMap (FC, Name)) ->
               (allHoles : IntMap (FC, Name)) ->
               List (Int, (FC, Name)) ->
               IntMap (FC, Name)
    addHoles acc allhs [] = acc
    addHoles acc allhs ((n, x) :: hs)
        = case lookup n allhs of
               Nothing => addHoles acc allhs hs
               Just _ => addHoles (insert n x acc) allhs hs

export
elabTermSub : {inner, vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto m : Ref MD Metadata} ->
              {auto u : Ref UST UState} ->
              {auto dl : Ref DLY DelayedElabs} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto o : Ref ROpts REPLOpts} ->
              Int -> ElabMode -> List ElabOpt ->
              NestedNames vars -> Env Term vars ->
              Env Term inner -> Thin inner vars ->
              RawImp -> Maybe (Glued vars) ->
              Core (Term vars, Glued vars)
elabTermSub defining mode opts nest env env' sub tm ty
    = do (tm', ty', _) <- elabTermSubMarked defining mode opts nest env env' sub tm ty
         pure (tm', ty')

export
elabTerm : {vars : _} ->
           {auto c : Ref Ctxt Defs} ->
           {auto m : Ref MD Metadata} ->
           {auto u : Ref UST UState} ->
           {auto dl : Ref DLY DelayedElabs} ->
           {auto s : Ref Syn SyntaxInfo} ->
           {auto o : Ref ROpts REPLOpts} ->
           Int -> ElabMode -> List ElabOpt ->
           NestedNames vars -> Env Term vars ->
           RawImp -> Maybe (Glued vars) ->
           Core (Term vars, Glued vars)
elabTerm defining mode opts nest env tm ty
    = elabTermSub defining mode opts nest env env Refl tm ty

export
checkTermSub : {inner, vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               {auto m : Ref MD Metadata} ->
               {auto u : Ref UST UState} ->
               {auto dl : Ref DLY DelayedElabs} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto o : Ref ROpts REPLOpts} ->
               Int -> ElabMode -> List ElabOpt ->
               NestedNames vars -> Env Term vars ->
               Env Term inner -> Thin inner vars ->
               RawImp -> Glued vars ->
               Core (Term vars)
checkTermSub defining mode opts nest env env' sub tm ty
    = do defs <- case mode of
                      InType => branch -- might need to backtrack if there's
                                       -- a case in the type
                      _ => get Ctxt
         ust <- get UST
         dls <- get DLY
         mv <- get MD
         res <-
            catch {t = Error}
                  (elabTermSub defining mode opts nest
                               env env' sub tm (Just ty))
                  $ \case
                    TryWithImplicits loc benv ns
                      => do put Ctxt defs
                            put UST ust
                            put DLY dls
                            put MD mv
                            tm' <- bindImps loc benv ns tm
                            elabTermSub defining mode opts nest
                                        env env' sub
                                        tm' (Just ty)
                    err => throw err
         case mode of
              InType => commit -- bracket the 'branch' above
              _ => pure ()

         pure (fst res)
  where
    bindImps' : FC -> Env Term vs -> List (Name, Term vs) -> RawImp ->
                Core RawImp
    bindImps' loc env [] ty = pure ty
    bindImps' loc env ((n, ty) :: ntys) sc
        = pure $ IPi loc erased Implicit (Just n)
                     (Implicit loc True) !(bindImps' loc env ntys sc)

    bindImps : FC -> Env Term vs -> List (Name, Term vs) -> RawImp ->
               Core RawImp
    bindImps loc env ns (IBindHere fc m ty)
        = pure $ IBindHere fc m !(bindImps' loc env ns ty)
    bindImps loc env ns ty = bindImps' loc env ns ty

export
checkTerm : {vars : _} ->
            {auto c : Ref Ctxt Defs} ->
            {auto m : Ref MD Metadata} ->
            {auto u : Ref UST UState} ->
            {auto dl : Ref DLY DelayedElabs} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto o : Ref ROpts REPLOpts} ->
            Int -> ElabMode -> List ElabOpt ->
            NestedNames vars -> Env Term vars ->
            RawImp -> Glued vars ->
            Core (Term vars)
checkTerm defining mode opts nest env tm ty
    = checkTermSub defining mode opts nest env env Refl tm ty
