-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
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

export
defaultOpts : Maybe String -> VerbosityLvl -> REPLOpts
defaultOpts fname verbosity
    = MkREPLOpts
        { mainfile = fname
        , verbosity = verbosity
        , currentElabSource = ""
        }

export
data ROpts : Type where

export
withROpts : {auto o : Ref ROpts REPLOpts} -> Core a -> Core a
withROpts = wrapRef ROpts (\_ => pure ())

export
setCurrentElabSource : {auto o : Ref ROpts REPLOpts} ->
                       String -> Core ()
setCurrentElabSource src = update ROpts { currentElabSource := src }

export
getCurrentElabSource : {auto o : Ref ROpts REPLOpts} ->
                       Core String
getCurrentElabSource = currentElabSource <$> get ROpts
