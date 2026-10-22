-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module TTImp.Elab.Lazy

import Core.Env
import Core.Metadata
import Core.Unify
import Core.Value

import Idris.REPL.Opts
import Idris.Syntax

import TTImp.Elab.Check
import TTImp.Elab.Delayed
import TTImp.TTImp

%default covering

export
checkDelayed : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               {auto m : Ref MD Metadata} ->
               {auto u : Ref UST UState} ->
               {auto dl : Ref DLY DelayedElabs} ->
               {auto e : Ref EST (EState vars)} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto o : Ref ROpts REPLOpts} ->
               RigCount -> ElabInfo ->
               NestedNames vars -> Env Term vars ->
               FC -> LazyReason -> RawImp -> Maybe (Glued vars) ->
               Core (Term vars, Glued vars)
checkDelayed rig elabinfo nest env fc r tm exp
    = do u <- uniVar fc
         (tm', gty) <- check rig elabinfo nest env tm (Just (gType fc u))
         pure (TDelayed fc r tm', gty)

-- `tm` checked at the type under a delay, and delayed: the one place a
-- delay is elaborated, for an explicit `Delay`, which the source wrote,
-- and for a case block written where a delayed value is expected
-- (checkCase), around which the elaborator inserts it.
export
checkDelayAt : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               {auto m : Ref MD Metadata} ->
               {auto u : Ref UST UState} ->
               {auto dl : Ref DLY DelayedElabs} ->
               {auto e : Ref EST (EState vars)} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto o : Ref ROpts REPLOpts} ->
               RigCount -> ElabInfo ->
               NestedNames vars -> Env Term vars ->
               FC -> Delaying -> RawImp -> (under : NF vars) ->
               Core (Term vars, Glued vars)
checkDelayAt rig elabinfo nest env fc d tm under
    = do defs <- get Ctxt
         (tm', gty) <- check rig elabinfo nest env tm (Just (glueBack defs env under))
         tynf <- getNF gty
         ty <- getTerm gty
         pure (TDelay fc d ty tm', glueBack defs env (NDelayed fc d.reason tynf))

-- The elaborator of a delay, given the cell of delayed elaborators and the
-- expected type, which a retry evaluates again (see delayOnFailure). It is
-- a function of its own rather than the body of a lambda in checkDelay: a
-- local definition is applied to everything its parent binds, so one used
-- in the lambda would capture checkDelay's cell.
checkDelayDelayed : {vars : _} ->
                    {auto c : Ref Ctxt Defs} ->
                    {auto m : Ref MD Metadata} ->
                    {auto u : Ref UST UState} ->
                    {auto dl : Ref DLY DelayedElabs} ->
                    {auto e : Ref EST (EState vars)} ->
                    {auto s : Ref Syn SyntaxInfo} ->
                    {auto o : Ref ROpts REPLOpts} ->
                    RigCount -> ElabInfo ->
                    NestedNames vars -> Env Term vars ->
                    FC -> RawImp -> (expected : Glued vars) ->
                    Core (Term vars, Glued vars)
checkDelayDelayed rig elabinfo nest env fc tm expected
    = case !(getNF expected) of
           NDelayed _ r expnf => checkDelayAt rig elabinfo nest env fc (MkDelaying r InSource) tm expnf
           ty => do logNF "elab.delay" 5 "Expected delay type" env ty
                    throw (GenericMsg fc ("Can't infer delay type"))

export
checkDelay : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto m : Ref MD Metadata} ->
             {auto u : Ref UST UState} ->
             {auto dl : Ref DLY DelayedElabs} ->
             {auto e : Ref EST (EState vars)} ->
             {auto s : Ref Syn SyntaxInfo} ->
             {auto o : Ref ROpts REPLOpts} ->
             RigCount -> ElabInfo ->
             NestedNames vars -> Env Term vars ->
             FC -> RawImp -> Maybe (Glued vars) ->
             Core (Term vars, Glued vars)
checkDelay rig elabinfo nest env fc tm mexpected
    = do expected <- maybe (do nm <- genName (known KdelayTy)
                               u <- uniVar fc
                               ty <- metaVar fc erased env nm (TType fc u)
                               pure (gnf env ty))
                           pure mexpected
         let solvemode = case elabMode elabinfo of
                              InLHS c => inLHS
                              _ => inTerm
         solveConstraints solvemode Normal
         -- Can only check if we know the expected type already because we
         -- need to infer the delay reason
         delayOnFailure fc rig env expected delayError LazyDelay
            (\dl, delayed, exp => checkDelayDelayed {dl} rig elabinfo nest env fc tm exp)
  where
    delayError : Error -> Bool
    delayError (GenericMsg {}) = True
    delayError _ = False

export
checkForce : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto m : Ref MD Metadata} ->
             {auto u : Ref UST UState} ->
             {auto dl : Ref DLY DelayedElabs} ->
             {auto e : Ref EST (EState vars)} ->
             {auto s : Ref Syn SyntaxInfo} ->
             {auto o : Ref ROpts REPLOpts} ->
             RigCount -> ElabInfo ->
             NestedNames vars -> Env Term vars ->
             FC -> RawImp -> Maybe (Glued vars) ->
             Core (Term vars, Glued vars)
checkForce rig elabinfo nest env fc tm exp
    = do defs <- get Ctxt
         expf <- maybe (pure Nothing)
                       (\gty => do tynf <- getNF gty
                                   pure (Just (glueBack defs env
                                         (NDelayed fc LUnknown tynf))))
                       exp
         (tm', gty) <- check rig elabinfo nest env tm expf
         tynf <- getNF gty
         case tynf of
              NDelayed _ r expnf =>
                 pure (TForce fc r tm', glueBack defs env expnf)
              _ => throw (GenericMsg fc "Forcing a non-delayed type")
