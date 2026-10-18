-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2026 Bjorn Pagen
||| What a program written over Idris's compiler asks of it and the
||| program's totality checker cannot follow, stated once, here.
|||
||| The frontend of idris-mlir is such a program, and total: every
||| recursion of its own is structural or well founded, and Idris checks
||| it. It also calls this compiler, which is covering, and the checker
||| follows each call into it: an operation whose own recursion the checker
||| cannot follow (decoding a definition from its TTC, a traversal through
||| a higher-order map, the elaborator) would make every function of the
||| program that reaches it partial. Each such operation is one field of
||| one value, `host`, the one place such a program trusts this compiler:
||| its theorem is that every operation named here returns. The evaluator
||| and the elaborator are here for good, since Idris's theory is not
||| strongly normalizing and the elaborator runs what types compute, and
||| so is the termination check that normalises as it goes; every other
||| field is here until the function it names is total, and then it is
||| deleted and its callers call the function. An operation the checker
||| can follow is called directly and is never here. A field is one
||| operation at one type, so that each goes on its own.
module Idris.Host

import Core.Case.CaseBuilder
import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Env
import Core.Normalise
import Core.Termination
import Core.TT
import Idris.CommandLine
import Idris.ModTree
import Idris.Package
import Idris.REPL.Common
import Idris.REPL.Opts
import Idris.SetOptions
import Idris.Syntax

%default total
%prefix_record_projections off

||| The operations of Idris's compiler whose termination a program over it
||| takes on trust, each named as this compiler names it.
public export
record Host where
  constructor MkHost

  -- The evaluator: Idris's theory is not strongly normalizing, so a
  -- normal form is trusted to exist; every caller first proves that each
  -- definition its term refers to ends, which is what that trust rests on.

  ||| `Core.Normalise.normalise`.
  normalise : {auto c : Ref Ctxt Defs} -> {free : _} ->
              Defs -> Env Term free -> Term free -> Core (Term free)
  ||| `Core.Normalise.normaliseTypes`.
  normaliseTypes : {auto c : Ref Ctxt Defs} -> {free : _} ->
                   Defs -> Env Term free -> Term free -> Core (Term free)
  ||| `Core.Normalise.normaliseHoles`.
  normaliseHoles : {auto c : Ref Ctxt Defs} -> {free : _} ->
                   Defs -> Env Term free -> Term free -> Core (Term free)
  ||| `Core.Normalise.normaliseAll`, every definition unfolded whatever its
  ||| visibility.
  normaliseAll : {auto c : Ref Ctxt Defs} -> {free : _} ->
                 Defs -> Env Term free -> Term free -> Core (Term free)

  -- Termination.

  ||| `Core.Termination.checkTerminating`.
  checkTerminating : {auto c : Ref Ctxt Defs} -> FC -> Name -> Core Terminating

  -- The driver.

  ||| `Idris.ModTree.buildMain`: the elaborator, on a main file and what it
  ||| imports, from a fresh context and fresh elaboration states.
  buildMain : {auto c : Ref Ctxt Defs} -> {auto s : Ref Syn SyntaxInfo} ->
              {auto o : Ref ROpts REPLOpts} -> String -> Core (List Error)
  ||| `Idris.Package.processPackageOpts`: the elaborator, on a package.
  processPackageOpts : {auto c : Ref Ctxt Defs} -> {auto s : Ref Syn SyntaxInfo} ->
                       {auto o : Ref ROpts REPLOpts} -> {auto p : Ref PostS PostSession} ->
                       List CLOpt -> Core ControlFlow

  -- The case builder.

  ||| `Core.Case.CaseBuilder.argToPat`: a place of a clause's left-hand
  ||| side as the case builder reads it, the evaluator again, since it
  ||| computes a literal written through a primitive conversion
  ||| (`normalisePrims`) and reads what that gives.
  argToPat : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core Pat

  -- The error printer.

  ||| `Idris.REPL.Common.emitError`: the evaluator again, since an error is
  ||| printed with the holes of its terms normalised (`normaliseHoles`).
  emitError : {auto c : Ref Ctxt Defs} -> {auto o : Ref ROpts REPLOpts} ->
              {auto s : Ref Syn SyntaxInfo} -> Error -> Core ()

||| Idris's compiler, as a program over it calls it where the checker
||| cannot follow it. The one trust of such a program in this compiler,
||| stated once: each of these returns.
export
host : Host
host = assert_total (MkHost
  { normalise
  , normaliseTypes
  , normaliseHoles
  , normaliseAll
  , checkTerminating
  , buildMain
  , processPackageOpts
  , argToPat
  , emitError
  })
