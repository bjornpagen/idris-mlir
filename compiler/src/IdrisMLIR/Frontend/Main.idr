||| The `mlir` backend, registered with the stock Idris driver (FE-ENTRY-*).
module IdrisMLIR.Frontend.Main

import Compiler.Common
import Core.Context
import Core.Core
import Core.Directory
import Core.Normalise
import Core.TT
import Core.Env
import Idris.Driver
import Idris.Syntax
import Libraries.Utils.Path

import IdrisMLIR.Core
import IdrisMLIR.Emit
import IdrisMLIR.HeapCheck
import IdrisMLIR.Simplify
import IdrisMLIR.Frontend.Paths
import IdrisMLIR.Frontend.Profile
import IdrisMLIR.Frontend.Translate

import Data.List
import Data.String
import System
import System.Directory
import System.File

------------------------------------------------------------------------------
-- Diagnostics
------------------------------------------------------------------------------

||| DIAG-FMT-1 for errors found after translation.
fromDiag : {auto s : Ref TState TS} -> Diag -> Core a
fromDiag d = reject (fromLoc d.loc) (if d.loc.file == "" then d.owner else d.loc.file) d.rule d.message

||| DIAG-ICE-1
internal : FC -> String -> Core a
internal fc msg = throw (GenericMsg fc ("mlir backend: internal error: " ++ msg))

write : String -> String -> Core ()
write path text = do
  Right () <- coreLift (writeFile path text)
    | Left err => throw (FileErr path err)
  pure ()

remove : String -> Core ()
remove path = ignore (coreLift (removeFile path))

------------------------------------------------------------------------------
-- The middle end (CORE-PASS-1)
------------------------------------------------------------------------------

||| Simplify, HeapCheck and Emit; returns the printed Core and the contract text.
middle : {auto s : Ref TState TS} -> FC -> Program -> Core (String, String)
middle fc prog = do
  Right simple <- pure (simplify prog)
    | Left d => fromDiag d
  Right checked <- pure (heapCheck simple)
    | Left d => fromDiag d
  Right mlir <- pure (emit checked)
    | Left msg => do
        -- DIAG-ICE-1: an internal error; the Core goes to stderr for the report.
        ignore (coreLift (fPutStrLn stderr (showProgram checked)))
        internal fc msg
  pure (showProgram checked, mlir)

------------------------------------------------------------------------------
-- main : Int programs (FE-ENTRY-2)
------------------------------------------------------------------------------

compileModule : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
                String -> Core (Maybe (String, List String))
compileModule c _ source = do
  ident <- ctxtPathToNS source
  -- DIAG-LOC-1: a location that --check reports.
  let fc = MkFC (PhysicalIdrSrc ident) (0, 0) (0, 0)
  corePath <- getTTCFileName source "core"
  mlirPath <- getTTCFileName source "mlir"
  -- FE-ART-1: no stale artifacts survive a failure.
  remove corePath
  remove mlirPath
  s <- newRef TState (initState fc)
  checkPragmas ident source
  defs <- get Ctxt
  -- PROF-PROG-1
  case defs.imported of
    [] => pure ()
    ((m, _, _) :: _) => reject fc (show ident) "PROF-PROG-1"
                          ("a main : Int program imports nothing (it imports " ++ show m ++ ")")
  -- PROF-PROG-2
  let main = NS (miAsNamespace ident) (UN (Basic "main"))
  Just def <- lookupCtxtExact main (gamma defs)
    | Nothing => reject fc (show ident) "PROF-PROG-2" "the module does not define main"
  ty <- normalise defs Env.Nil (type def)
  case ty of
    PrimVal _ (PrT IntType) => pure ()
    _ => reject (location def) (show main) "PROF-PROG-2" "main must have type Int"
  checkReachable fc [main]
  prog <- translateIntProgram main
  (core, mlir) <- middle fc prog
  write corePath core
  write mlirPath mlir
  pure (Just (!(getObjFileName source "mlir"), []))

------------------------------------------------------------------------------
-- IO programs (FE-ENTRY-4, DRV-FLOW-2)
------------------------------------------------------------------------------

rootName : ClosedTerm -> Maybe (Name, Name)
rootName tm = case go tm [] of
    (Ref _ _ f, args) => case reverse args of
      (Ref _ _ m :: _) => Just (f, m)
      _ => Nothing
    _ => Nothing
  where
    go : Term vs -> List (Term vs) -> (Term vs, List (Term vs))
    go (App _ f a) acc = go f (a :: acc)
    go f acc = (f, acc)

run : FC -> List String -> Core ()
run fc cmd = do
  status <- coreLift (system (escapeCmd cmd))
  unless (status == 0) $
    internal fc (fastConcat (intersperse " " cmd) ++ " failed with status " ++ show status)

compileIO : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
            String -> String -> ClosedTerm -> String -> Core (Maybe String)
compileIO c _ tmpDir outputDir tm outfile = do
  let base = outputDir </> outfile
  let corePath = base ++ ".core"
  let mlirPath = base ++ ".mlir"
  let objPath = base ++ ".o"
  traverse_ remove [corePath, mlirPath, objPath, base]
  defs <- get Ctxt
  Just (perform, main) <- pure (rootName tm)
    | Nothing => throw (GenericMsg EmptyFC "mlir backend: unsupported (FE-ENTRY-4): an unexpected root term")
  Just mainDef <- lookupCtxtExact main (gamma defs)
    | Nothing => throw (GenericMsg EmptyFC "mlir backend: unsupported (FE-ENTRY-4): main is missing")
  let fc = location mainDef
  main <- toFullNames main
  s <- newRef TState (initState fc)
  unless (show !(toFullNames perform) == "PrimIO.unsafePerformIO") $
    reject fc "main" "FE-ENTRY-4" "the root is not unsafePerformIO main"
  -- PROF-PROG-4, PROF-PRAG-1: every module is trusted or a user module with source.
  let mainIdent = case !(toFullNames main) of
                    NS ns _ => nsAsModuleIdent ns
                    _ => nsAsModuleIdent (mkNamespace "Main")
  let mods = mainIdent :: map (\(_, (m, _, _)) => m) defs.allImported
  for_ mods $ \m =>
    unless (trustedModule (unsafeUnfoldModuleIdent m) || null (unsafeUnfoldModuleIdent m)) $ do
      Right path <- catch (Right <$> nsToSource fc m) (\_ => pure (Left ()))
        | Left () => reject fc "main" "PROF-PROG-4"
                       ("imports " ++ show m ++ ", which is neither a user module nor a trusted module")
      checkPragmas m path
  checkReachable fc [main]
  prog <- translateIOProgram fc main
  (core, mlir) <- middle fc prog
  write corePath core
  write mlirPath mlir
  -- DRV-FLOW-2: the rest of the chain, with the pinned tools.
  run fc [idrisMlirCc, mlirPath, "-o", objPath]
  run fc [pinnedCc, objPath, "-o", base]
  pure (Just base)

||| The stock driver does not fail `-o` on a backend error, so the backend
||| reports the error and exits with status 1 itself (DIAG-EXIT-1).
compileProgram : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
                 String -> String -> ClosedTerm -> String -> Core (Maybe String)
compileProgram c s tmpDir outputDir tm outfile =
  catch (compileIO c s tmpDir outputDir tm outfile) $ \err => do
    coreLift (putStrLn ("Error: " ++ show err))
    coreLift (exitWith (ExitFailure 1))

executeProgram : Ref Ctxt Defs -> Ref Syn SyntaxInfo ->
                 String -> ClosedTerm -> Core ()
executeProgram _ _ _ _ =
  throw (GenericMsg EmptyFC "mlir backend: unsupported (FE-ENTRY-5): --exec is not supported")

backend : Codegen
backend = MkCG compileProgram executeProgram (Just compileModule) (Just "mlir")

main : IO ()
main = mainWithCodegens [("mlir", backend)]
