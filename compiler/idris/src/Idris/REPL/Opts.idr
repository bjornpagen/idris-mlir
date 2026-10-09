module Idris.REPL.Opts

import Idris.Syntax

import Data.String

%default total

namespace VerbosityLvl
  public export
  data VerbosityLvl =
   ||| Suppress all message output to `stdout`.
   NoneLvl |
   ||| Keep only errors.
   ErrorLvl |
   ||| Keep everything.
   InfoLvl

-- What the elaborator and the build keep of upstream's REPL options: the
-- state that decides how messages are printed. The REPL and the IDE mode
-- are not part of this compiler, so neither is their state.
public export
record REPLOpts where
  constructor MkREPLOpts
  mainfile : Maybe String
  verbosity : VerbosityLvl
  currentElabSource : String
  consoleWidth : Maybe Nat -- Nothing is auto
  color : Bool

export
defaultOpts : Maybe String -> VerbosityLvl -> REPLOpts
defaultOpts fname verbosity
    = MkREPLOpts
        { mainfile = fname
        , verbosity = verbosity
        , currentElabSource = ""
        , consoleWidth = Nothing
        , color = True
        }

export
data ROpts : Type where

export
withROpts : {auto o : Ref ROpts REPLOpts} -> Core a -> Core a
withROpts = wrapRef ROpts (\_ => pure ())

export
setVerbosity : {auto o : Ref ROpts REPLOpts} ->
               VerbosityLvl -> Core ()
setVerbosity v = update ROpts { verbosity := v }

export
getVerbosity : {auto o : Ref ROpts REPLOpts} -> Core VerbosityLvl
getVerbosity = verbosity <$> get ROpts

export
setMainFile : {auto o : Ref ROpts REPLOpts} ->
              Maybe String -> Core ()
setMainFile src = update ROpts { mainfile := src }

export
setCurrentElabSource : {auto o : Ref ROpts REPLOpts} ->
                       String -> Core ()
setCurrentElabSource src = update ROpts { currentElabSource := src }

export
getCurrentElabSource : {auto o : Ref ROpts REPLOpts} ->
                       Core String
getCurrentElabSource = currentElabSource <$> get ROpts

export
getConsoleWidth : {auto o : Ref ROpts REPLOpts} -> Core (Maybe Nat)
getConsoleWidth = consoleWidth <$> get ROpts

export
setConsoleWidth : {auto o : Ref ROpts REPLOpts} -> Maybe Nat -> Core ()
setConsoleWidth n = update ROpts { consoleWidth := n }

export
getColor : {auto o : Ref ROpts REPLOpts} -> Core Bool
getColor = color <$> get ROpts

export
setColor : {auto o : Ref ROpts REPLOpts} -> Bool -> Core ()
setColor b = update ROpts { color := b }
