-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module TTImp.Elab.As

import Core.Env
import Core.Unify

import Idris.REPL.Opts
import Idris.Syntax

import TTImp.Elab.Check
import TTImp.Elab.ImplicitBind
import TTImp.TTImp

%default covering

-- Only one side can be usable if it's linear! Normally we'd assume this
-- to be the new variable (UseRight), but in generated case blocks it's
-- better if it's the pattern (UseLeft)
rigPat : UseSide -> RigCount -> RigCount
rigPat UseLeft rig = if isLinear rig then linear else rig
rigPat UseRight rig = if isLinear rig then erased else rig

rigAs : UseSide -> RigCount -> RigCount
rigAs UseLeft rig = if isLinear rig then erased else rig
rigAs UseRight rig = if isLinear rig then linear else rig

-- Name the checked pattern `pat`, at multiplicity `rig`, as `n_in`: the
-- as-pattern `n_in@pat`, whose name the left-hand side binds. The caller has
-- noted `n_in` as a pattern variable (`noteLHSPatVar`, `notePatVar`).
export
bindAs : {vars : _} ->
         {auto c : Ref Ctxt Defs} ->
         {auto u : Ref UST UState} ->
         {auto e : Ref EST (EState vars)} ->
         RigCount -> ElabInfo -> Env Term vars ->
         FC -> (nameFC : FC) -> UseSide -> Name ->
         (pat : (Term vars, Glued vars)) -> Maybe (Glued vars) ->
         Core (Term vars, Glued vars)
bindAs rig elabinfo env fc nameFC side n_in (pattm, patty) topexp
    = do est <- get EST
         let n = PV n_in (defining est)
         (tm, exp, bty) <- mkPatternHole nameFC rig n env
                                 (implicitMode elabinfo)
                                 topexp
         log "elab.as" 5 $ "Added as pattern name " ++ show (n, (rigAs side rig, tm, exp, bty))
         update EST { boundNames $= ((n, AsBinding (rigAs side rig) Explicit tm exp pattm) :: ),
                      toBind $= ((n, AsBinding (rigAs side rig) Explicit tm bty pattm) ::) }
         (ntm, nty) <- checkExp rig elabinfo env nameFC tm (gnf env exp)
                                (Just patty)

         pure (As fc side ntm pattm, patty)

export
checkAs : {vars : _} ->
          {auto c : Ref Ctxt Defs} ->
          {auto u : Ref UST UState} ->
          {auto dl : Ref DLY DelayedElabs} ->
          {auto e : Ref EST (EState vars)} ->
          {auto s : Ref Syn SyntaxInfo} ->
          {auto o : Ref ROpts REPLOpts} ->
          RigCount -> ElabInfo ->
          NestedNames vars -> Env Term vars ->
          FC -> (nameFC : FC) -> UseSide -> Name -> RawImp -> Maybe (Glued vars) ->
          Core (Term vars, Glued vars)
checkAs rig elabinfo nest env fc nameFC side n_in pat topexp
    = do let elabmode = elabMode elabinfo
         let InLHS _ = elabmode
             | _ => do log "elab.as" 2 $ "Bad @-pattern " ++ show pat
                       throw (GenericMsg fc "@-patterns only allowed in pattern clauses")
         est <- get EST
         let n = PV n_in (defining est)
         noteLHSPatVar elabmode n_in
         notePatVar n
         case lookup n (boundNames est) of
              Nothing =>
                 do pat' <- check (rigPat side rig) elabinfo nest env pat topexp
                    bindAs rig elabinfo env fc nameFC side n_in pat' topexp
              Just bty => throw (NonLinearPattern fc n_in)
