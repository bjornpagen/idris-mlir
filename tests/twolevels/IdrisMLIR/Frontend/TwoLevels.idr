||| The upper level of the two-level test (tests/TwoLevels.idr, SEM-REF-1):
||| the pinned Idris's own evaluator on the terms `Terms.t1`, `Terms.t2`, ...
||| of the program it is given, as a backend of the stock driver, as the
||| compiler's frontend is:
|||
|||     twolevels --no-prelude --cg twolevels -o unused Main.idr
|||
||| prints `t<n> <value>` for each, as the compiled program prints it. The
||| evaluation is the REPL's `normalise_all`: every definition, private ones
||| included, is unfolded, arguments first. A term whose normal form is not a
||| value is printed as `stuck <term>`.
|||
||| It uses the Idris API, which only modules named IdrisMLIR.Frontend.* may
||| import (FE-IN-3); it is a test, built by its test (tests/two-levels), and
||| not part of the compiler.
|||
||| rule: SEM-REF-1, FE-IN-3
module IdrisMLIR.Frontend.TwoLevels

import Compiler.Common
import Core.Context
import Core.Core
import Core.Env
import Core.Normalise
import Core.TT
import Core.Value
import Idris.Driver
import Idris.Syntax

import Data.String

||| A value as the compiled program prints it.
value : ClosedTerm -> String
value (PrimVal _ c) = case c of
  I x => show x
  I8 x => show x
  I16 x => show x
  I32 x => show x
  I64 x => show x
  B8 x => show x
  B16 x => show x
  B32 x => show x
  B64 x => show x
  BI x => show x
  Str x => x
  Ch x => show (ord x)
  Db x => show x
  _ => "stuck " ++ show c
value tm = "stuck " ++ show tm

||| The terms t1, t2, ... of the module Terms, until one is missing.
normaliseTerms : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
                 String -> String -> ClosedTerm -> String -> Core (Maybe String)
normaliseTerms c s tmp out tm outfile = do
  defs <- get Ctxt
  go defs 1
  pure Nothing
  where
    go : Defs -> Nat -> Core ()
    go defs i = do
      let n = NS (mkNamespace "Terms") (UN (Basic ("t" ++ show i)))
      Just _ <- lookupCtxtExact n (gamma defs)
        | Nothing => pure ()
      nf <- normaliseOpts ({ strategy := CBV } withAll) defs Env.Nil (Ref EmptyFC Func n)
      coreLift (putStrLn ("t" ++ show i ++ " " ++ value nf))
      go defs (S i)

noExecute : Ref Ctxt Defs -> Ref Syn SyntaxInfo -> String -> ClosedTerm -> Core ()
noExecute _ _ _ _ = pure ()

main : IO ()
main = mainWithCodegens [("twolevels", MkCG normaliseTerms noExecute Nothing Nothing)]
