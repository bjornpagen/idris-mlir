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
import IdrisMLIR.Core.Check
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

||| The directory for `--directive dump-core` and `dump-mlir` (DRV-DUMP-1).
dumpDir : {auto c : Ref Ctxt Defs} -> String -> Core (Maybe String, Bool)
dumpDir base = do
  ds <- getDirectives (Other "mlir")
  let dir = base ++ ".dump"
  let core = elem "dump-core" ds
  let mlir = elem "dump-mlir" ds
  when (core || mlir) $ do
    Right () <- coreLift (createDirs dir)
      | Left err => throw (FileErr dir err)
    pure ()
  pure (if core then Just dir else Nothing, mlir)
  where
    createDirs : String -> IO (Either FileError ())
    createDirs d = do
      ok <- exists d
      if ok then pure (Right ()) else createDir d

||| Writes the Core after a pass when dumping.
dump : Maybe String -> String -> Program -> Core ()
dump Nothing _ _ = pure ()
dump (Just dir) name prog = write (dir </> name ++ ".core") (showProgram prog)

||| Core.Check (CORE-CHECK-1): a failure is an internal error, with the Core
||| on stderr for the report (DIAG-ICE-1).
checked : FC -> String -> (Program -> Either String ()) -> Program -> Core ()
checked fc pass check prog = case check prog of
  Right () => pure ()
  Left msg => do
    ignore (coreLift (fPutStrLn stderr (showProgram prog)))
    internal fc ("Core.Check after " ++ pass ++ ": " ++ msg)

||| Simplify, HeapCheck and Emit (CORE-PASS-1); returns the printed Core and
||| the contract text.
middle : {auto s : Ref TState TS} -> FC -> Maybe String -> Program -> Core (String, String)
middle fc dir prog = do
  dump dir "01-translate" prog
  checked fc "Translate" checkFull prog
  Right simple <- pure (simplify prog)
    | Left d => fromDiag d
  dump dir "02-simplify" simple
  Right heapFree <- pure (heapCheck simple)
    | Left d => fromDiag d
  dump dir "03-heapcheck" heapFree
  checked fc "HeapCheck" checkFirstOrder heapFree
  Right mlir <- pure (emit heapFree)
    | Left msg => do
        ignore (coreLift (fPutStrLn stderr (showProgram heapFree)))
        internal fc msg
  pure (showProgram heapFree, mlir)

------------------------------------------------------------------------------
-- main : Int programs (FE-ENTRY-2)
------------------------------------------------------------------------------

dropExt : String -> String -> String
dropExt path ext = if isSuffixOf ext path then substr 0 (length path `minus` length ext) path else path

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
  (dir, _) <- dumpDir (corePath `dropExt` ".core")
  (core, mlir) <- middle fc dir prog
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
  (dir, dumpMlir) <- dumpDir base
  (core, mlir) <- middle fc dir prog
  write corePath core
  write mlirPath mlir
  -- DRV-FLOW-2: the rest of the chain, with the pinned tools.
  let dumps = if dumpMlir then ["--dump-after=all", "--dump-dir=" ++ base ++ ".dump"] else []
  run fc ([idrisMlirCc, mlirPath, "-o", objPath] ++ dumps)
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
