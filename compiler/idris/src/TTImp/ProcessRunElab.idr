-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module TTImp.ProcessRunElab

import Core.Env
import Core.Metadata
import Core.Reflect
import Core.UnifyState
import Core.Value

import Idris.REPL.Opts
import Idris.Syntax

import TTImp.Elab
import TTImp.Elab.Check
import TTImp.Elab.RunElab
import TTImp.TTImp

%default covering

export
processRunElab : {vars : _} ->
                 {auto c : Ref Ctxt Defs} ->
                 {auto m : Ref MD Metadata} ->
                 {auto u : Ref UST UState} ->
                 {auto dl : Ref DLY DelayedElabs} ->
                 {auto s : Ref Syn SyntaxInfo} ->
                 {auto o : Ref ROpts REPLOpts} ->
                 List ElabOpt -> NestedNames vars -> Env Term vars -> FC ->
                 RawImp -> Core ()
processRunElab eopts nest env fc tm
    = do defs <- get Ctxt
         unless (isExtension ElabReflection defs) $
             throw (GenericMsg fc "%language ElabReflection not enabled")
         tidx <- resolveName (knownUN KElabScript)
         let n = reflection KElab
         unit <- getCon fc defs (builtin KUnit)
         exp <- appCon fc defs n [unit]

         stm <- checkTerm tidx InExpr eopts nest env tm (gnf env exp)
         nfstm <- nfOpts withAll defs env stm
         ignore $ logTime 2 "Elaboration script" $
           elabScript top fc nest env nfstm Nothing
