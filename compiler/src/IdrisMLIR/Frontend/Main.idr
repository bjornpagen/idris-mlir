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

import IdrisMLIR.Emit
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Rule
import IdrisMLIR.Term
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

||| The middle end (CORE-PASS-1): Translate's full Core, printed, and `Emit`'s
||| contract text. `--directive dump-core` writes the full Core as
||| `01-translate.core`.
middle : FC -> Maybe String -> Source -> Core (String, String)
middle fc dir src = do
  let core = showSource src
  dump dir "01-translate" core
  Right mlir <- pure (emit src)
    | Left msg => do
        ignore (coreLift (fPutStrLn stderr core))
        internal fc ("Emit: " ++ msg)
  pure (core, mlir)

------------------------------------------------------------------------------
-- idris-mlir-cc (DRV-CC-2)
------------------------------------------------------------------------------

||| `--directive no-eval`: `idris-mlir-cc --no-eval`, which leaves every
||| closed call to run at runtime (docs/cutover.md, 6.4 and 10). The
||| equivalence suite (tests/equivalence) compiles each program both ways.
noEval : {auto c : Ref Ctxt Defs} -> Core (List String)
noEval = do
  ds <- getDirectives (Other "mlir")
  pure (if elem "no-eval" ds then ["--no-eval"] else [])

||| A location in `idris-mlir-cc`'s text: `file:line:column`, 1-based.
record Place where
  constructor MkPlace
  file : String
  line : Int
  col : Int

||| The first location in a line of text, as MLIR prints one
||| (a file name, quoted or not, then `:line:column`).
place : String -> Maybe Place
place text = head' (mapMaybe parse (words text))
  where
    digits : String -> Maybe Int
    digits d = if d /= "" && all isDigit (unpack d) then Just (cast d) else Nothing
    unquote : String -> String
    unquote f = pack (filter (/= '"') (unpack f))
    parse : String -> Maybe Place
    parse w = case reverse (forget (split (== ':') w)) of
      ("" :: c :: l :: rest@(_ :: _)) => MkPlace (unquote (joinBy ":" (reverse rest))) <$> digits l <*> digits c
      (c :: l :: rest@(_ :: _)) => MkPlace (unquote (joinBy ":" (reverse rest))) <$> digits l <*> digits c
      _ => Nothing

||| A profile rejection as `idris-mlir-cc` reports it: the rule, what it
||| says, and where.
record Rejection where
  constructor MkRejection
  rule : String
  message : String
  at : Maybe Place

||| The first `unsupported (<RULE>): ...` in the text, and its location: on
||| its line, or else anywhere in the text.
rejection : String -> Maybe Rejection
rejection text = do
  l <- find (isInfixOf "unsupported (") (lines text)
  let (_, rest) = breakOn "unsupported (" l
  let body = pack (drop (length (unpack "unsupported (")) (unpack rest))
  let (rule, after) = break (== ')') body
  let message = trim (pack (drop 1 (dropWhile (/= ':') (unpack after))))
  pure (MkRejection rule message (place l <|> head' (mapMaybe place (lines text))))
  where
    breakOn : String -> String -> (String, String)
    breakOn needle hay = go [] (unpack hay)
      where
        go : List Char -> List Char -> (String, String)
        go acc [] = (pack (reverse acc), "")
        go acc cs@(c :: rest) =
          if isPrefixOf (unpack needle) cs then (pack (reverse acc), pack cs) else go (c :: acc) rest

||| A definition of the program: where it is, and its Idris name.
record Definition where
  constructor MkDefinition
  loc : Loc
  name : String

||| DIAG-FMT-1, DIAG-LOC-1: a profile rejection from `idris-mlir-cc`, as an
||| Idris error at the user's code. The location's module is the one a
||| definition of the program names for that file; the definition reported
||| is the last one that starts at or before the location.
reportRejection : {auto s : Ref TState TS} -> FC -> Source -> Rejection -> Core a
reportRejection fc src r = do
  let Just rule = parseRule r.rule
    | Nothing => internal fc ("idris-mlir-cc reported an unknown rule: " ++ r.rule)
  case r.at of
    Nothing => reject fc (show src.root) rule r.message
    Just p => do
      let inFile = filter (\d => d.loc.file == p.file) definitions
      -- Of definitions on one line, the first in program order: the IO root
      -- comes last, at main's location.
      let owner = maybe p.file (.name)
                        (last' (sortBy earlier (reverse (filter (\d => d.loc.startLine < p.line) inFile))))
      let at = case inFile of
                 (d :: _) => fromLoc ({ startLine := p.line - 1, startCol := p.col - 1
                                      , endLine := p.line - 1, endCol := p.col - 1 } d.loc)
                 [] => MkFC (PhysicalPkgSrc p.file) (p.line - 1, p.col - 1) (p.line - 1, p.col - 1)
      reject at owner rule r.message
  where
    definitions : List Definition
    definitions = map (\f => MkDefinition f.loc (show f.idrisName)) src.fns ++
                  map (\d => MkDefinition d.loc (show d.idrisName)) src.datas
    earlier : Definition -> Definition -> Ordering
    earlier a b = compare a.loc.startLine b.loc.startLine

||| Runs `idris-mlir-cc` with its stderr in `errPath`: its exit status and
||| what it wrote there. Nothing it wrote is lost: on success, its text goes
||| on to stderr.
runCc : List String -> String -> Core (Int, String)
runCc args errPath = do
  status <- coreLift (system (escapeCmd (idrisMlirCc :: args) ++ " 2> " ++ escapeArg errPath))
  text <- either (const "") id <$> coreLift (readFile errPath)
  remove errPath
  when (status == 0 && text /= "") $ ignore (coreLift (fPutStr stderr text))
  pure (status, text)

||| DRV-CC-2: what an exit status of `idris-mlir-cc` means. 3 is a profile
||| rejection, a user error; anything else but 0 is an internal error
||| (DIAG-ICE-1). Either way the artifacts are removed (FE-ART-1).
ccVerdict : {auto s : Ref TState TS} -> FC -> Source -> List String -> (Int, String) -> Core ()
ccVerdict fc src artifacts (0, _) = pure ()
ccVerdict fc src artifacts (3, text) = do
  traverse_ remove artifacts
  case rejection text of
    Just r => reportRejection fc src r
    Nothing => internal fc ("idris-mlir-cc rejected the program without naming a rule:\n" ++ text)
ccVerdict fc src artifacts (status, text) = do
  traverse_ remove artifacts
  internal fc ("idris-mlir-cc failed with status " ++ show status ++ ":\n" ++ text)

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
  -- A profile rejection on the optimized module is a user error of
  -- `--check` too, and leaves no artifact (docs/cutover.md, 7.11).
  ccVerdict fc prog [corePath, mlirPath] !(runCc ([mlirPath, "--check"] ++ !noEval) (mlirPath ++ ".stderr"))
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

||| Runs a pinned tool; a failure is an internal error, and leaves no
||| artifact (FE-ART-1).
run : FC -> List String -> List String -> Core ()
run fc artifacts cmd = do
  status <- coreLift (system (escapeCmd cmd))
  unless (status == 0) $ do
    traverse_ remove artifacts
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
  ccVerdict fc prog [corePath, mlirPath, objPath] !(runCc ([mlirPath, "-o", objPath] ++ dumps ++ !noEval) (base ++ ".cc.stderr"))
  -- TC-LINK-2: lld links the program's one object (TC-LINK-1) into a
  -- static-PIE executable on musl, whose libc.a also holds the libm functions
  -- of LOW-EXT-1, with GMP as a native archive. The pinned clang's
  -- configuration file supplies the sysroot, compiler-rt and libunwind.
  run fc [corePath, mlirPath, objPath, base] [pinnedCc, "--target=x86_64-unknown-linux-musl", "-fuse-ld=lld", "-static-pie",
          "-Wl,--gc-sections", "-Wl,--icf=all", objPath, "-o", base, "-lgmp"]
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
