-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the frontend asks of Idris's compiler and cannot prove returns.
|||
||| The frontend is total: every recursion of its own is structural or well
||| founded, and Idris checks it. It also calls Idris's compiler, which is
||| covering, and Idris's totality checker follows each call into it: an
||| operation whose own recursion the checker cannot follow (decoding a
||| definition from its TTC, a traversal through a higher-order map, the
||| elaborator) would make every frontend function that reaches it partial.
||| Each such operation is one field of one value, `host`, the one place the
||| frontend trusts: its theorem is that every operation of Idris's
||| compiler named here returns. The evaluator and the elaborator are here
||| for good, since Idris's theory is not strongly normalizing and the
||| elaborator runs what types compute, and so is the termination check
||| that normalises as it goes; every other field is here until the fork's
||| function it names is total, and then it is deleted and its callers call
||| the function. An operation the checker can
||| follow is called directly and is never here. A field is one fork
||| operation at one type, so that each goes on its own.
module IdrisMLIR.Frontend.Host

import Core.Context
import Core.Core
import Core.Env
import Core.Normalise
import Core.Termination
import Core.TT
import Idris.CommandLine
import Idris.ModTree
import Idris.Package
import Idris.REPL.Opts
import Idris.SetOptions
import Idris.Syntax

%default total
%prefix_record_projections off

||| The operations of Idris's compiler whose termination the frontend takes
||| on trust, each named as the fork names it.
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

||| Idris's compiler, as the frontend calls it where the checker cannot
||| follow it. The one trust of the frontend in Idris's compiler, stated
||| once: each of these returns.
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
  })
