-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module TTImp.ProcessDecls

import Core.Directory
import Core.Env
import Core.Termination
import Core.UnifyState

import Idris.Error
import Idris.Pretty
import Idris.REPL.Opts
import Idris.Syntax
import Parser.Source

import TTImp.BindImplicits
import TTImp.Elab.Check
import TTImp.ProcessBuiltin
import TTImp.ProcessData
import TTImp.ProcessDef
import TTImp.ProcessParams
import TTImp.ProcessRecord
import TTImp.ProcessTransform
import TTImp.ProcessType
import TTImp.TTImp

import TTImp.ProcessDecls.Totality

import Libraries.Text.PrettyPrint.Prettyprinter.Doc

%default covering

processFailing :
  {vars : _} ->
  {auto c : Ref Ctxt Defs} ->
  {auto u : Ref UST UState} ->
  {auto dl : Ref DLY DelayedElabs} ->
  {auto s : Ref Syn SyntaxInfo} ->
  {auto o : Ref ROpts REPLOpts} ->
  List ElabOpt ->
  NestedNames vars -> Env Term vars ->
  FC -> Maybe String ->  List ImpDecl -> Core ()
processFailing eopts nest env fc mmsg decls
    = do -- save the state: the content of a failing block should be discarded
         ust <- get UST
         dls <- get DLY
         syn <- get Syn

         -- We expect the block to fail and so the definitions introduced
         -- in it should be discarded once we leave the block.
         defs <- branch

         -- We're going to run the elaboration, and then return:
         -- * Nothing     if the block correctly failed
         -- * Just err    if it either did not fail or failed with an invalid error message
         result <- catch
               (do -- Run the elaborator
                   before <- getTotalityErrors
                   traverse_ (processDecl eopts nest env) decls
                   after <- getTotalityErrors
                   let errs = after \\ before
                   let (e :: es) = errs
                     | [] => do -- We better have unsolved holes
                                -- checkUserHoles True -- do we need this one too?

                                 -- should we only look at the ones introduced in the block?
                                Nothing <- checkDelayedHoles
                                  | Just err => throw err

                                -- Or we have (unfortunately) succeeded
                                pure (Just $ FailingDidNotFail fc)
                   let Just msg = mmsg
                     | _ => pure Nothing
                   logC "elab.failing" 10 $
                     do texts <- traverse errorText errs
                        pure "Failing block based on \{show msg} failed with \{show texts}"
                   test <- anyM (checkError msg) errs
                   pure $ do -- Unless the error is the expected one
                             guard (not test)
                             -- We should complain we had the wrong one
                             pure (FailingWrongError fc msg (e ::: es)))
               (\err => do let Just msg = mmsg
                                 | _ => pure Nothing
                           logC "elab.failing" 10 $
                             do text <- errorText err
                                pure "Failing block based on \{show msg} failed with \{text}"
                           test <- checkError msg err
                           pure $ do -- Unless the error is the expected one
                                     guard (not test)
                                     -- We should complain we had the wrong one
                                     pure (FailingWrongError fc msg (err ::: [])))
         -- Reset the state
         put UST ust
         put DLY dls
         put Syn syn
         put Ctxt defs
         -- And fail if the block was successfully accepted
         whenJust result throw

-- Implemented in Idris.Desugar, which makes every pragma and sees the
-- interface and implementation elaborators, above this module
export
processPragma : {vars : _} ->
                {auto c : Ref Ctxt Defs} ->
                {auto u : Ref UST UState} ->
                {auto dl : Ref DLY DelayedElabs} ->
                {auto s : Ref Syn SyntaxInfo} ->
                {auto o : Ref ROpts REPLOpts} ->
                FC -> NestedNames vars -> Env Term vars -> Pragma -> Core ()

-- Implements processDecl, declared in TTImp.Elab.Check
process : {vars : _} ->
          {auto c : Ref Ctxt Defs} ->
          {auto u : Ref UST UState} ->
          {auto dl : Ref DLY DelayedElabs} ->
          {auto s : Ref Syn SyntaxInfo} ->
          {auto o : Ref ROpts REPLOpts} ->
          List ElabOpt ->
          NestedNames vars -> Env Term vars -> ImpDecl -> Core ()
process eopts nest env (IClaim dat@(MkFCVal fc (MkIClaimData rig vis opts ty)))
    = processType eopts nest env dat.fc rig vis opts ty
process eopts nest env (IData fc vis mbtot ddef)
    = processData eopts nest env fc vis mbtot ddef
process eopts nest env (IDef fc fname def)
    = processDef eopts nest env fc fname def
process eopts nest env (IParameters fc ps decls)
    = processParams nest env fc (forget ps) decls
process eopts nest env (IRecord fc ns vis mbtot rec)
    = processRecord eopts nest env ns vis mbtot rec
process eopts nest env (IFail fc msg decls)
    = processFailing eopts nest env fc msg decls
process eopts nest env (INamespace fc ns decls)
    = withExtendedNS ns $
         traverse_ (processDecl eopts nest env) decls
process eopts nest env (ITransform fc n lhs rhs)
    = processTransform eopts nest env fc n lhs rhs
process eopts nest env (IPragma fc _ p)
    = processPragma fc nest env p
process eopts nest env (ILog lvl)
    = addLogLevel (uncurry unsafeMkLogLevel <$> lvl)
process eopts nest env (IBuiltin fc type name)
    = processBuiltin nest env fc type name

TTImp.Elab.Check.processDecl = process

export
processDecls : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               {auto dl : Ref DLY DelayedElabs} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto o : Ref ROpts REPLOpts} ->
               NestedNames vars -> Env Term vars -> List ImpDecl -> Core ()
processDecls nest env decls = traverse_ (processDecl [] nest env) decls
