-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module TTImp.Elab.Delayed

import Core.Case.CaseTree
import Core.Context.Log
import Core.Env
import Core.Metadata
import Core.Normalise
import Core.Unify
import Core.Value

import TTImp.Elab.Check

import Libraries.Data.IntMap
import Libraries.Data.NameMap

%default covering

-- We run the elaborator in the given environment, but need to end up with a
-- closed term.
mkClosedElab : {vars : _} ->
               FC -> Env Term vars ->
               (Core (Term vars, Glued vars)) ->
               Core ClosedTerm
mkClosedElab fc [] elab
    = do (tm, _) <- elab
         pure tm
mkClosedElab {vars = x :: vars} fc (b :: env) elab
    = mkClosedElab fc env
          (do (sc', _) <- elab
              let b' = newBinder b
              pure (Bind fc x b' sc', gErased fc))
  where
    -- in 'abstractEnvType' we get a Pi binder (so we'll need a Lambda) for
    -- everything except 'Let', so make the appropriate corresponding binder
    -- here
    newBinder : Binder (Term vars) -> Binder (Term vars)
    newBinder b@(Let {}) = b
    newBinder b = Lam (binderLoc b) (multiplicity b) Explicit (binderType b)

-- Run an elaborator with the holes it must not solve set to the given ones,
-- and the unification state's own restored after. It is a function of its
-- own, not code in the closure delayOnFailure and delayElab store: a record
-- update is a local definition, applied to everything its parent binds,
-- and there that is the cell of delayed elaborators the closure is stored
-- in.
withNoSolve : {auto u : Ref UST UState} ->
              IntMap () -> Core a -> Core a
withNoSolve nos elab
    = do ust <- get UST
         let nos' = noSolve ust
         put UST ({ noSolve := nos } ust)
         res <- elab
         ust <- get UST
         put UST ({ noSolve := nos' } ust)
         pure res

-- Try the given elaborator; if it fails, and the error matches the
-- predicate, make a hole and try it again later when more holes might
-- have been resolved.
-- The elaborator is given the cell of delayed elaborators and the expected
-- type, rather than capturing either (see DelayedElab): the first time the
-- type as the caller has it, and when it is retried the type's term
-- evaluated again, since we might know more by then. A glued type holds
-- the computations that make its term and its normal form, and the closure
-- the retry is stored as holds no computation, only the term.
export
delayOnFailure : {vars : _} ->
                 {auto c : Ref Ctxt Defs} ->
                 {auto m : Ref MD Metadata} ->
                 {auto u : Ref UST UState} ->
                 {auto dl : Ref DLY DelayedElabs} ->
                 {auto e : Ref EST (EState vars)} ->
                 FC -> RigCount -> Env Term vars ->
                 (expected : Glued vars) ->
                 (Error -> Bool) ->
                 (pri : DelayReason) ->
                 (Ref DLY DelayedElabs -> Bool -> Glued vars -> Core (Term vars, Glued vars)) ->
                 Core (Term vars, Glued vars)
delayOnFailure fc rig env expected pred pri elab
    = do ust <- get UST
         let nos = noSolve ust -- remember the holes we shouldn't solve
         handle (elab dl False expected)
          (\err =>
              do est <- get EST
                 if pred err
                    then
                      do nm <- genName (known Kdelayed)
                         ty <- getTerm expected
                         (ci, dtm) <- newDelayed fc linear env nm ty
                         logGlueNF "elab.delay" 5 ("Postponing elaborator " ++ show nm ++
                                      " at " ++ show fc ++
                                      " for") env expected
                         log "elab.delay" 10 ("Due to error " ++ show err)
                         defs <- get Ctxt
                         update DLY
                                 ((pri, ci, localHints defs,
                                   MkDelayedElab $ \dl =>
                                   mkClosedElab fc env
                                      (withNoSolve nos (elab dl True (gnf env ty)))) :: )
                         pure (dtm, expected)
                    else throw err)

-- Make a hole and elaborate it later. The elaborator is given the cell of
-- delayed elaborators and the expected type, if there is one, as
-- delayOnFailure's retry is.
export
delayElab : {vars : _} ->
            {auto c : Ref Ctxt Defs} ->
            {auto m : Ref MD Metadata} ->
            {auto u : Ref UST UState} ->
            {auto dl : Ref DLY DelayedElabs} ->
            {auto e : Ref EST (EState vars)} ->
            FC -> RigCount -> Env Term vars ->
            (expected : Maybe (Glued vars)) ->
            (pri : DelayReason) ->
            (Ref DLY DelayedElabs -> Maybe (Glued vars) -> Core (Term vars, Glued vars)) ->
            Core (Term vars, Glued vars)
delayElab {vars} fc rig env exp pri elab
    = do ust <- get UST
         let nos = noSolve ust -- remember the holes we shouldn't solve
         nm <- genName (known Kdelayed)
         expected <- mkExpected exp
         ty <- getTerm expected
         (ci, dtm) <- newDelayed fc linear env nm ty
         logGlueNF "elab.delay" 5 ("Postponing elaborator " ++ show nm ++
                      " for") env expected
         let given = map (const ty) exp
         defs <- get Ctxt
         update DLY
                 ((pri, ci, localHints defs,
                   MkDelayedElab $ \dl =>
                                 mkClosedElab fc env
                                   (withNoSolve nos (elab dl (map (gnf env) given)))) :: )
         pure (dtm, expected)
  where
    mkExpected : Maybe (Glued vars) -> Core (Glued vars)
    mkExpected (Just ty) = pure ty
    mkExpected Nothing
        = do nm <- genName (known KdelayTy)
             u <- uniVar fc
             ty <- metaVar fc erased env nm (TType fc u)
             pure (gnf env ty)

export
ambiguous : Error -> Bool
ambiguous (AmbiguousElab {}) = True
ambiguous (AmbiguousName {}) = True
ambiguous (InType _ _ err) = ambiguous err
ambiguous (InCon _ err) = ambiguous err
ambiguous (InLHS _ _ err) = ambiguous err
ambiguous (InRHS _ _ err) = ambiguous err
ambiguous (WhenUnifying _ _ _ _ _ err) = ambiguous err
ambiguous _ = False

||| Whether an elaboration failed because a linear binder was used at a
||| multiplicity it does not have, so that checking the term again at
||| multiplicity one may succeed. A name with several candidates fails when
||| all of them do, and checking again at one tries every candidate again,
||| so that failure is such a failure when any candidate's is.
export
misusesLinear : Error -> Bool
misusesLinear (LinearMisuse _ _ r _) = isLinear r
misusesLinear (AllFailed alts) = candidates alts
  where
    candidates : List (Maybe Name, Error) -> Bool
    candidates [] = False
    candidates ((_, err) :: rest) = misusesLinear err || candidates rest
misusesLinear (InType _ _ err) = misusesLinear err
misusesLinear (InCon _ err) = misusesLinear err
misusesLinear (InLHS _ _ err) = misusesLinear err
misusesLinear (InRHS _ _ err) = misusesLinear err
misusesLinear _ = False

mutual
  mismatchNF : {auto c : Ref Ctxt Defs} ->
               {vars : _} ->
               Defs -> NF vars -> NF vars -> Core Bool
  mismatchNF defs (NTCon _ xn _ xargs) (NTCon _ yn _ yargs)
      = if xn /= yn
           then pure True
           else anyM (mismatch defs) (zipWith (curry $ mapHom snd) xargs yargs)
  mismatchNF defs (NDCon _ _ xt _ xargs) (NDCon _ _ yt _ yargs)
      = if xt /= yt
           then pure True
           else anyM (mismatch defs) (zipWith (curry $ mapHom snd) xargs yargs)
  mismatchNF defs (NPrimVal _ xc) (NPrimVal _ yc) = pure (xc /= yc)
  mismatchNF defs (NDelayed _ _ x) (NDelayed _ _ y) = mismatchNF defs x y
  mismatchNF defs (NDelay _ _ _ x) (NDelay _ _ _ y)
      = mismatchNF defs !(evalClosure defs x) !(evalClosure defs y)
  mismatchNF _ _ _ = pure False

  mismatch : {auto c : Ref Ctxt Defs} ->
             {vars : _} ->
             Defs -> (Closure vars, Closure vars) -> Core Bool
  mismatch defs (x, y)
      = mismatchNF defs !(evalClosure defs x) !(evalClosure defs y)

contra : {auto c : Ref Ctxt Defs} ->
         {vars : _} ->
         Defs -> NF vars -> NF vars -> Core Bool
-- Unlike 'impossibleOK', any mismatch indicates an unrecoverable error
contra defs (NTCon _ xn xa xargs) (NTCon _ yn ya yargs)
    = if xn /= yn
         then pure True
         else anyM (mismatch defs) (zipWith (curry $ mapHom snd) xargs yargs)
contra defs (NDCon _ _ xt _ xargs) (NDCon _ _ yt _ yargs)
    = if xt /= yt
         then pure True
         else anyM (mismatch defs) (zipWith (curry $ mapHom snd) xargs yargs)
contra defs (NPrimVal _ x) (NPrimVal _ y) = pure (x /= y)
contra defs (NDCon {}) (NPrimVal {}) = pure True
contra defs (NPrimVal {}) (NDCon {}) = pure True
contra defs x y = pure False

-- Errors that might be recoverable later if we try again. Generally -
-- ambiguity errors, type inference errors
export
recoverable : {auto c : Ref Ctxt Defs} ->
              Error -> Core Bool
recoverable (CantConvert _ gam env l r)
   = do defs <- get Ctxt
        let defs = { gamma := gam } defs
        pure $ not !(contra defs !(nf defs env l) !(nf defs env r))
recoverable (CantSolveEq _ gam env l r)
   = do defs <- get Ctxt
        let defs = { gamma := gam } defs
        pure $ not !(contra defs !(nf defs env l) !(nf defs env r))
recoverable (UndefinedName {}) = pure False
recoverable (LinearMisuse {}) = pure False
recoverable (GrowingSearch {}) = pure False
recoverable (InType _ _ err) = recoverable err
recoverable (InCon _ err) = recoverable err
recoverable (InLHS _ _ err) = recoverable err
recoverable (InRHS _ _ err) = recoverable err
recoverable (WhenUnifying _ _ _ _ _ err) = recoverable err
recoverable _ = pure True

data RetryError
     = RecoverableErrors
     | AllErrors

Show RetryError where
  show RecoverableErrors = "RecoverableErrors"
  show AllErrors = "AllErrors"

-- Try all the delayed elaborators. If there's a failure, we want to
-- show the ambiguity errors first (since that's the likely cause)
-- Return all the ones that need trying again
retryDelayed' : {vars : _} ->
                {auto c : Ref Ctxt Defs} ->
                {auto m : Ref MD Metadata} ->
                {auto u : Ref UST UState} ->
                {auto dl : Ref DLY DelayedElabs} ->
                {auto e : Ref EST (EState vars)} ->
                RetryError ->
                (progress : Bool) ->
                DelayedElabs ->
                DelayedElabs ->
                Core (Bool, DelayedElabs)
retryDelayed' errmode p acc [] = pure (p, reverse acc)
retryDelayed' errmode p acc (d@(_, i, hints, elab) :: ds)
    = do defs <- get Ctxt
         Just Delayed <- lookupDefExact (Resolved i) (gamma defs)
              | _ => retryDelayed' errmode p acc ds
         handle
           (do logC "elab.retry" 5 $ do pure $ "Retrying delayed hole " ++ show !(getFullName (Resolved i))
               -- elab itself might have delays internally, so keep track of them
               put DLY (the DelayedElabs [])
               update Ctxt { localHints := hints }

               tm <- runDelayedElab elab
               nested <- get DLY
               let ds' = reverse nested ++ ds

               updateDef (Resolved i) (const (Just
                    (PMDef (MkPMDefInfo NotHole True False)
                           Scope.empty (LiveBody (STerm 0 tm) [] []))))
               logTerm "elab.update" 5 ("Resolved delayed hole " ++ show i) tm
               logTermNF "elab.update" 5 ("Resolved delayed hole NF " ++ show i) Env.empty tm
               removeHole i
               retryDelayed' errmode True acc ds')
           (\err => do logC "elab" 5 $ do pure $ show errmode ++ ":Error in " ++ show !(getFullName (Resolved i))
                                              ++ "\n" ++ show err
                       case errmode of
                         RecoverableErrors =>
                            if not !(recoverable err)
                               then throw err
                               else retryDelayed' errmode p (d :: acc) ds
                         AllErrors =>
                            -- we've got an error, but see if we get a more
                            -- helpful one with a later elaborator
                            handle (do ignore $ retryDelayed' errmode p [] ds
                                       throw err)
                               (\err' => throw (better err err')))
  where
    better : Error -> Error -> Error
    better e (GenericMsg {}) = e
    better (GenericMsg {}) e = e
    better e _ = e

export
retryDelayed : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               {auto m : Ref MD Metadata} ->
               {auto u : Ref UST UState} ->
               {auto dl : Ref DLY DelayedElabs} ->
               {auto e : Ref EST (EState vars)} ->
               UnifyInfo -> DelayedElabs ->
               Core ()
retryDelayed mode ds
    = do (p, ds) <- retryDelayed' RecoverableErrors False [] ds -- try everything again
         solveConstraints mode Normal -- maybe we can resolve some interfaces now
         if p
            then retryDelayed mode ds -- progress, go around again
            else ignore $ retryDelayed' AllErrors False [] ds -- fail on all errors

-- Run an elaborator, then all the delayed elaborators arising from it
export
runDelays : {vars : _} ->
            {auto c : Ref Ctxt Defs} ->
            {auto m : Ref MD Metadata} ->
            {auto u : Ref UST UState} ->
            {auto dl : Ref DLY DelayedElabs} ->
            {auto e : Ref EST (EState vars)} ->
            (DelayReason -> Bool) -> Core a -> Core a
runDelays pri elab
    = do olddelayed <- get DLY
         put DLY (the DelayedElabs [])
         tm <- elab
         ust <- get UST
         delayed <- get DLY
         log "elab.delay" 2 $ "Rerunning delayed in elaborator"
         handle (do ignore $ retryDelayed' AllErrors False []
                       (reverse (filter hasPri delayed)))
                (\err => do put UST ust
                            put DLY olddelayed
                            throw err)
         update DLY (++ olddelayed)
         pure tm
  where
    hasPri : (DelayReason, d) -> Bool
    hasPri (n, _) = pri n
