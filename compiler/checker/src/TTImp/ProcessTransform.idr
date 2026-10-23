-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module TTImp.ProcessTransform

import Core.Env
import Core.Metadata
import Core.UnifyState

import Idris.REPL.Opts
import Idris.Syntax

import TTImp.Elab
import TTImp.Elab.Check
import TTImp.ProcessDef -- for checking LHS
import TTImp.TTImp

import Libraries.Data.VarSet

%default covering

||| A `%transform` rule, which only a trusted library writes (a user
||| module's is refused by the frontend): elaborated as upstream elaborates
||| one, its right side checked against its left's type and its left a
||| function's application, and kept nowhere. A rule states an equality an
||| optimizer may use, which changes no program, and this compiler's
||| optimizer is its own.
export
processTransform : {vars : _} ->
                   {auto c : Ref Ctxt Defs} ->
                   {auto m : Ref MD Metadata} ->
                   {auto u : Ref UST UState} ->
                   {auto dl : Ref DLY DelayedElabs} ->
                   {auto s : Ref Syn SyntaxInfo} ->
                   {auto o : Ref ROpts REPLOpts} ->
                   List ElabOpt -> NestedNames vars -> Env Term vars -> FC ->
                   Name -> RawImp -> RawImp -> Core ()
processTransform eopts nest env fc tn_in lhs rhs
    = do tn <- inCurrentNS tn_in
         tidx <- resolveName tn
         (_, (vars'  ** (sub', env', nest', lhstm, lhsty, _))) <-
             checkLHS True top tidx eopts nest env fc lhs
         logTerm "transform.lhs" 3 "Transform LHS" lhstm
         rhstm <- wrapError (InRHS fc tn_in) $
                       checkTermSub tidx InExpr (InTrans :: eopts) nest' env' env sub' rhs (gnf env' lhsty)
         clearHoleLHS
         logTerm "transform.rhs" 3 "Transform RHS" rhstm
         case getFn lhstm of
              Ref {} => pure ()
              _ => throw (GenericMsg fc "LHS of a transformation must be a function application")
