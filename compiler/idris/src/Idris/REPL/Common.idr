module Idris.REPL.Common

import Core.Env
import Core.InitPrimitives
import Core.Metadata
import Core.Unify

import Idris.Error
import Idris.Pretty
import public Idris.REPL.Opts
import Idris.Syntax

import Data.String
import System.File

%default covering

||| Output informational messages, unless suppressed by a flag.
||| This function should only be called with informational
||| messages, an unhandled error is an example of what should
||| *not* end up here.
export
iputStrLn : {auto c : Ref Ctxt Defs} ->
            {auto o : Ref ROpts REPLOpts} ->
            Doc IdrisAnn -> Core ()
iputStrLn msg
    = do opts <- get ROpts
         case verbosity opts of
              InfoLvl  => coreLift $ putStrLn !(render msg)
              -- output silenced
              _ => pure ()

||| Sampled against `VerbosityLvl`.
public export
data MsgStatus = MsgStatusNone | MsgStatusError | MsgStatusInfo

doPrint : MsgStatus -> VerbosityLvl -> Bool
doPrint MsgStatusNone  InfoLvl  = True
doPrint MsgStatusNone  ErrorLvl = True
doPrint MsgStatusNone  NoneLvl  = True
doPrint MsgStatusError InfoLvl  = True
doPrint MsgStatusError ErrorLvl = True
doPrint MsgStatusError NoneLvl  = False
doPrint MsgStatusInfo  InfoLvl  = True
doPrint MsgStatusInfo  ErrorLvl = False
doPrint MsgStatusInfo  NoneLvl  = False

printWithStatus : {auto o : Ref ROpts REPLOpts} ->
                  (Doc ann -> Core String) ->
                  (Doc ann -> MsgStatus -> Core ())
printWithStatus render msg status
  = do opts <- get ROpts
       when (doPrint status (verbosity opts)) $
         coreLift $ putStrLn !(render msg)

export
printError : {auto o : Ref ROpts REPLOpts} ->
             Doc IdrisAnn -> Core ()
printError msg = printWithStatus render msg MsgStatusError

-- Display an error message from checking a source file
export
emitError : {auto c : Ref Ctxt Defs} ->
            {auto o : Ref ROpts REPLOpts} ->
            {auto s : Ref Syn SyntaxInfo} ->
            Error -> Core ()
emitError e = printWithStatus render !(display e) MsgStatusError

export
emitWarning : {auto c : Ref Ctxt Defs} ->
              {auto o : Ref ROpts REPLOpts} ->
              {auto s : Ref Syn SyntaxInfo} ->
              Warning -> Core ()
emitWarning w = printWithStatus render !(displayWarning w) MsgStatusInfo

export
emitWarnings : {auto c : Ref Ctxt Defs} ->
               {auto o : Ref ROpts REPLOpts} ->
               {auto s : Ref Syn SyntaxInfo} ->
               Core (List Error)
emitWarnings
    = do defs <- get Ctxt
         let ws = reverse (warnings defs)
         session <- getSession
         if (session.warningsAsErrors)
           then let errs = WarningAsError <$> ws in
                errs <$ traverse_ emitError errs
           else [] <$ traverse_ emitWarning ws

export
emitWarningsAndErrors : {auto c : Ref Ctxt Defs} ->
                        {auto o : Ref ROpts REPLOpts} ->
                        {auto s : Ref Syn SyntaxInfo} ->
                        List Error -> Core (List Error)
emitWarningsAndErrors errs = do
  ws <- emitWarnings
  traverse_ emitError errs
  pure ws

export
resetContext : {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto m : Ref MD Metadata} ->
               (origin : OriginDesc) ->
               Core ()
resetContext origin
    = do defs <- get Ctxt
         put Ctxt ({ options := clearNames (options defs) } !initDefs)
         addPrimitives
         put UST initUState
         put Syn initSyntax
         put MD (initMetadata origin)
