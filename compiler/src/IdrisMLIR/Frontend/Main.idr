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

import IdrisMLIR.Code
import IdrisMLIR.Code.Check
import IdrisMLIR.Code.Loops
import IdrisMLIR.Emit
import IdrisMLIR.Loc
import IdrisMLIR.Rule
import IdrisMLIR.Simplify
import IdrisMLIR.Term
import IdrisMLIR.Term.Check
import IdrisMLIR.Frontend.Paths
import IdrisMLIR.Frontend.Profile
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate
import IdrisMLIR.Registry
import IdrisMLIR.Registry.Libraries

import Data.List
import Data.List1
import Data.Maybe
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

write : String -> String -> Core ()
write path text = do
  Right () <- coreLift (writeFile path text)
    | Left err => throw (FileErr path err)
  pure ()

remove : String -> Core ()
remove path = ignore (coreLift (removeFile path))

||| HOOK-SHAPE-1: the registry's entries against the loaded context, once,
||| before anything uses them (docs/architecture/17-registry.md).
validated : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> FC -> Core ()
validated fc = case !validate of
  Valid => pure ()
  Wrong at owner msg => reject at owner HookShape1 msg
  NoSuchEntry name => internal fc ("the directive break-shape=" ++ name ++ " names no entry of the registry")

||| FE-ENTRY-4: is a definition the head of the term Idris hands an IO
||| backend?
programRoot : List Hook -> Bool
programRoot [] = False
programRoot (ProgramRoot :: _) = True
programRoot (_ :: hs) = programRoot hs

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
dump : Maybe String -> String -> String -> Core ()
dump Nothing _ _ = pure ()
dump (Just dir) name text = write (dir </> name ++ ".core") text

||| CORE-CHECK-1: a failure is an internal error, with the Core on stderr for
||| the report (DIAG-ICE-1).
checked : FC -> String -> Either (Rule, String) () -> String -> Core ()
checked fc pass (Right ()) _ = pure ()
checked fc pass (Left (rule, msg)) core = do
  ignore (coreLift (fPutStrLn stderr core))
  internal fc ("Core.Check after " ++ pass ++ ": " ++ show rule ++ ": " ++ msg)

||| Simplify and Emit, with the checks between them (CORE-PASS-1); returns
||| the printed first-order Core and the contract text.
middle : {auto s : Ref TState TS} -> FC -> Maybe String -> Source -> Core (String, String)
middle fc dir src = do
  let full = showSource src
  dump dir "01-translate" full
  checked fc "Translate" (checkSource src) full
  Right simple <- pure (simplify src)
    | Left d => fromDiag d
  dump dir "02-simplify" (showTarget simple)
  checked fc "Simplify" (check simple) (showTarget simple)
  let target = relaxTarget (loopify simple)
  let core = showTarget target
  dump dir "03-loops" core
  checked fc "Loops" (check target) core
  Right mlir <- pure (emit target)
    | Left msg => do
        ignore (coreLift (fPutStrLn stderr core))
        internal fc msg
  pure (core, mlir)

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
  validated fc
  checkPragmas ident source
  defs <- get Ctxt
  -- PROF-PROG-1
  case defs.imported of
    [] => pure ()
    ((m, _, _) :: _) => do
      at <- map snd . head' <$> imports ident source
      reject (fromMaybe fc at) (show ident) ProfProg1
             ("a main : Int program imports nothing (it imports " ++ show m ++ ")")
  -- PROF-PROG-2: Idris's entry convention, from the registry.
  let main = toName (intEntry (modulePath ident))
  Just def <- lookupCtxtExact main (gamma defs)
    | Nothing => reject fc (show ident) ProfProg2 "the module does not define main"
  ty <- normalise defs Env.Nil (type def)
  case ty of
    PrimVal _ (PrT IntType) => pure ()
    _ => reject (location def) (show main) ProfProg2 "main must have type Int"
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
    go : Core.TT.Term.Term vs -> List (Core.TT.Term.Term vs) -> (Core.TT.Term.Term vs, List (Core.TT.Term.Term vs))
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
  validated fc
  unless (programRoot (hooksOf !(toFullNames perform))) $
    reject fc "main" FeEntry4 "the root is not unsafePerformIO main"
  -- PROF-PROG-4, PROF-PRAG-1: every module is trusted or a user module with source.
  let mainIdent = case !(toFullNames main) of
                    NS ns _ => nsAsModuleIdent ns
                    _ => moduleIdent mainModule
  let mods = mainIdent :: map (\(_, (m, _, _)) => m) defs.allImported
  let user = filter (\m => not (covers Trusted (originOf m) || null (unsafeUnfoldModuleIdent m))) mods
  sources <- for user $ \m => do
    path <- catch (Just <$> nsToSource fc m) (\_ => pure Nothing)
    pure (m, path)
  let userNames = map (show . fst) (filter (isJust . snd) sources)
  -- An import of a module that is neither a user module nor trusted, at the
  -- import itself (DIAG-LOC-1).
  for_ sources $ \(m, path) => case path of
    Just p => do
      is <- imports m p
      for_ is $ \(target, at) =>
        unless (covers Trusted (moduleOrigin (forget (split (== '.') target))) || elem target userNames) $
          reject at (show m) ProfProg4
                 ("imports " ++ target ++ ", which is neither a user module nor a trusted module")
    Nothing => pure ()
  for_ sources $ \(m, path) => case path of
    Just p => checkPragmas m p
    Nothing => reject fc "main" ProfProg4
                 ("loads " ++ show m ++ ", which is neither a user module nor a trusted module")
  checkReachable fc [main]
  prog <- translateIOProgram fc main
  (dir, dumpMlir) <- dumpDir base
  (core, mlir) <- middle fc dir prog
  write corePath core
  write mlirPath mlir
  -- DRV-FLOW-2: the rest of the chain, with the pinned tools.
  let dumps = if dumpMlir then ["--dump-after=all", "--dump-dir=" ++ base ++ ".dump"] else []
  run fc ([idrisMlirCc, mlirPath, "-o", objPath] ++ dumps)
  -- LOW-EXT-1: libm, for the Double functions the reference backend also takes
  -- from it.
  run fc [pinnedCc, objPath, "-o", base, "-lm"]
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
