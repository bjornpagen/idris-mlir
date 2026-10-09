||| The command line, on the fork of Idris's compiler (compiler/idris): the
||| session, a package's build, install or clean, and a program's: its main
||| file built, then the closed term `unsafePerformIO main` elaborated and
||| handed to the `mlir` code generator (IdrisMLIR.Frontend.Backend). It
||| reads the command line Idris 2's driver read, and says what that driver
||| said, in the same words, on the same stream, with the same exit status,
||| but for what this compiler has not: an interactive session, which a run
||| with nothing to do after loading would have started, and an expression
||| to execute, which is refused.
module IdrisMLIR.Frontend.Driver

import Core.Binary
import Core.Context
import Core.Context.Log
import Core.Core
import Core.Directory
import Core.Env
import Core.InitPrimitives
import Core.LinearCheck
import Core.Metadata
import Core.Options
import Core.Options.Log
import Core.TT
import Core.UnifyState

import Idris.CommandLine
import Idris.Desugar
import Idris.Env
import Idris.Error
import Idris.ModTree
import Idris.Package
import Idris.Pretty
import Idris.ProcessIdr
import Idris.REPL.Common
import Idris.SetOptions
import Idris.Syntax
import Idris.Syntax.Pragmas
import Idris.Version

import TTImp.Elab
import TTImp.Elab.Check
import TTImp.TTImp

import Libraries.Utils.Path

import IdrisMLIR.Frontend.Backend
import IdrisMLIR.Registry.Primitives

import Data.List1
import Data.String
import System
import System.Directory
import System.File
import System.Term

%default covering

------------------------------------------------------------------------------
-- The command line
------------------------------------------------------------------------------

||| The options that print something and end the run before any session.
quitOpts : List CLOpt -> IO ControlFlow
quitOpts [] = pure Continue
quitOpts (Version :: _) = putStrLn versionMsg $> Abort
quitOpts (TTCVersion :: _) = printLn ttcVersion $> Abort
quitOpts (Help Nothing :: _) = putStrLn usage $> Abort
quitOpts (Help (Just HelpLogging) :: _) = putStrLn helpTopics $> Abort
quitOpts (Help (Just HelpPragma) :: _) = putStrLn pragmaTopics $> Abort
quitOpts (_ :: opts) = quitOpts opts

findInputs : List CLOpt -> Maybe (List1 String)
findInputs [] = Nothing
findInputs (InputFile f :: fs) = Just (f ::: maybe [] toList (findInputs fs))
findInputs (_ :: fs) = findInputs fs

ignoreMissingIpkg : List CLOpt -> Bool
ignoreMissingIpkg = any (\case IgnoreMissingIPKG => True; _ => False)

verbose : List CLOpt -> Bool
verbose = any (\case Verbose => True; _ => False)

||| The expressions to execute, in the order given.
execExprs : List CLOpt -> List String
execExprs = mapMaybe (\case ExecFn e => Just e; _ => Nothing)

------------------------------------------------------------------------------
-- The session
------------------------------------------------------------------------------

splitPaths : String -> List1 String
splitPaths = map trim . split (== pathSeparator)

||| The session's directories, from the environment. IDRIS2_PREFIX is the
||| prefix whose packages this compiler built, in its TTC format; the
||| fork knows no installation of its own to fall back on. prelude and base
||| are found there when they are installed, and not yet when they are the
||| packages being built.
updateEnv : {auto c : Ref Ctxt Defs} ->
            {auto o : Ref ROpts REPLOpts} ->
            Core ()
updateEnv = do
  noColor <- coreLift [ isJust noc || not tty | noc <- idrisGetEnv "NO_COLOR", tty <- isTTY stdout ]
  when noColor $ setColor False
  Just pfx <- coreLift $ idrisGetEnv "IDRIS2_PREFIX"
    | Nothing => throw (UserError ("IDRIS2_PREFIX is not set: it names the prefix "
                                   ++ "of the packages this compiler built"))
  setPrefix pfx
  bpath <- coreLift $ idrisGetEnv "IDRIS2_PATH"
  whenJust bpath $ traverseList1_ addExtraDir . splitPaths
  bdata <- coreLift $ idrisGetEnv "IDRIS2_DATA"
  whenJust bdata $ traverseList1_ addDataDir . splitPaths
  blibs <- coreLift $ idrisGetEnv "IDRIS2_LIBS"
  whenJust blibs $ traverseList1_ addLibDir . splitPaths
  pdirs <- coreLift $ idrisGetEnv "IDRIS2_PACKAGE_PATH"
  whenJust pdirs $ traverseList1_ addPackageSearchPath . splitPaths
  -- The package search path the environment gives comes first, so that it
  -- overrides the prefix's packages.
  addPackageSearchPath !pkgGlobalDirectory
  catch (addPkgDir "prelude" anyBounds) (const (pure ()))
  catch (addPkgDir "base" anyBounds) (const (pure ()))
  defs <- get Ctxt
  let versioned = prefix_dir (dirs (options defs)) </> ("idris2-" ++ showVersion False version)
  addDataDir (versioned </> "support")
  addLibDir (versioned </> "lib")
  Just cwd <- coreLift currentDir
    | Nothing => throw (InternalError "Can't get current directory")
  addLibDir cwd

||| An error that ends the run before or around the build: on stderr, with
||| status 1.
quitWithError : {auto c : Ref Ctxt Defs} ->
                {auto s : Ref Syn SyntaxInfo} ->
                {auto o : Ref ROpts REPLOpts} ->
                Error -> Core a
quitWithError err = do
  doc <- display err
  msg <- render doc
  coreLift (die msg)

------------------------------------------------------------------------------
-- The main file
------------------------------------------------------------------------------

||| What loading came to: the main file unreadable, or a build and the
||| errors it reported, none when every module built (with no main file,
||| the prelude, which is read, not built, and reports none).
data Loaded = Unreadable String FileError | Built (List Error)

||| The source line of the build's first error. A run that loaded a file
||| ends with status 1 when there is one, and with 0 otherwise, an error
||| with no location included: Idris's driver decided the status by it.
errorLine : Loaded -> Maybe Int
errorLine (Built (err :: _)) = map startLine (getErrorLoc err >>= isNonEmptyFC)
errorLine _ = Nothing

||| Builds the main file and the modules it imports, and loads the main
||| module from its TTC, as the module of no name, when every module built.
loadMainFile : {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               {auto dl : Ref DLY DelayedElabs} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto m : Ref MD Metadata} ->
               {auto o : Ref ROpts REPLOpts} ->
               String -> Core Loaded
loadMainFile f = do
  modIdent <- ctxtPathToNS f
  resetContext (PhysicalIdrSrc modIdent)
  Right _ <- coreLift (readFile f)
    | Left err => pure (Unreadable f err)
  errs <- logTime 1 "Build deps" $ buildDeps f
  pure (Built errs)

||| A run with no main file has the prelude, unless the session has none,
||| for `-o` or an expression to execute to be elaborated in.
loadPrelude : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              {auto s : Ref Syn SyntaxInfo} ->
              Core Loaded
loadPrelude = do
  session <- getSession
  when (not (noprelude session)) $ readPrelude True
  pure (Built [])

fileLoadingError : String -> FileError -> Maybe (Doc IdrisAnn) -> Doc IdrisAnn
fileLoadingError fname err suggestion =
  let suggestion = maybe "" (hardline <+>) suggestion
  in hardline <+>
     (indent 2 $
       error ((reflow "Error loading file") <++> (dquotes $ pretty0 fname) <+> colon) <++>
         pretty0 (show err) <+>
       suggestion) <+>
     hardline

displayStartupErrors : {auto o : Ref ROpts REPLOpts} -> Loaded -> Core ()
displayStartupErrors (Unreadable f err) = printError (fileLoadingError f err (nearMatchOptSuggestion f))
displayStartupErrors _ = pure ()

------------------------------------------------------------------------------
-- The program
------------------------------------------------------------------------------

||| The closed term that runs an expression of type `IO a`: the expression
||| under `unsafePerformIO`, elaborated in the loaded context and checked
||| for linearity, with its erased arguments erased. Nothing is compiled to
||| Idris's own intermediate forms: the code generator reads checked TT.
prepareExp : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             {auto dl : Ref DLY DelayedElabs} ->
             {auto s : Ref Syn SyntaxInfo} ->
             {auto m : Ref MD Metadata} ->
             {auto o : Ref ROpts REPLOpts} ->
             PTerm -> Core ClosedTerm
prepareExp ctm = do
  ttimp <- desugar AnyExpr [] (PApp replFC (PRef replFC (UN $ Basic "unsafePerformIO")) ctm)
  -- The local block an interactive session binds its last result `it` in,
  -- with nothing bound: the term elaborates as Idris's driver elaborated it.
  let ttimpWithIt = ILocal replFC [] ttimp
  inidx <- resolveName (UN $ Basic "[input]")
  (tm, _) <- elabTerm inidx InExpr [] (MkNested []) Env.empty ttimpWithIt Nothing
  linearCheck replFC linear True Env.empty tm

||| `-o`: `main` compiled into the output directory, which is made, with the
||| build's directory of executables, first.
compileMain : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              {auto dl : Ref DLY DelayedElabs} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto m : Ref MD Metadata} ->
              {auto o : Ref ROpts REPLOpts} ->
              String -> Core ()
compileMain outfile = do
  tm <- prepareExp (PRef EmptyFC (UN $ Basic "main"))
  d <- getDirs
  ensureDirectoryExists (execBuildDir d)
  let outputDir = outputDirWithDefault d
  ensureDirectoryExists outputDir
  logTime 1 "Code generation overall" $ compileProgram outputDir tm outfile

||| What the main file's options ask once it is loaded: `-o` even after a
||| build that failed (the code generator decides what that leaves), then
||| each expression to execute, which this compiler refuses. A file that
||| could not be read is not compiled.
postOptions : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              {auto dl : Ref DLY DelayedElabs} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto m : Ref MD Metadata} ->
              {auto o : Ref ROpts REPLOpts} ->
              Loaded -> PostSession -> List String -> Core ()
postOptions (Unreadable _ _) (MkPostSession _ (Just _)) _ = pure ()
postOptions _ post execs = do
  whenJust post.outputFile compileMain
  for_ execs $ \_ =>
    throw (GenericMsg EmptyFC "mlir backend: unsupported (program): --exec is not supported")

------------------------------------------------------------------------------
-- A run
------------------------------------------------------------------------------

||| A run: the session, the package commands, if any, and otherwise the
||| main file, or the prelude when there is none. There is no interactive
||| session: loading a file with nothing to do with it checks it.
run : List CLOpt -> Core ()
run opts = do
  defs <- initDefs
  c <- newRef Ctxt ({ options $= addCG (codegenName, Other codegenName) } defs)
  s <- newRef Syn initSyntax
  addPrimitives
  setWorkingDir "."
  when (ignoreMissingIpkg opts) $
    setSession ({ ignoreMissingPkg := True } !getSession)
  o <- newRef ROpts (defaultOpts Nothing InfoLvl)
  updateEnv
  fname <- case findInputs opts of
    Just (fname ::: Nil) => pure (Just fname)
    Nothing => pure Nothing
    Just (fname1 ::: fnames) => do
      let suggestion = nearMatchOptSuggestion fname1
      renderedSuggestion <- maybe (pure "") render suggestion
      quitWithError $
        UserError """
                  Expected at most one input file but was given: \{joinBy ", " (fname1 :: fnames)}
                  \{renderedSuggestion}
                  """
  setMainFile fname
  p <- newRef PostS defaultPost
  Continue <- preOptions opts
    | Abort => pure ()
  Continue <- catch (processPackageOpts opts) quitWithError
    | Abort => pure ()
  flip catch quitWithError $ do
    when (verbose opts) $ setVerbosity InfoLvl
    u <- newRef UST initUState
    dl <- newRef DLY (the DelayedElabs [])
    origin <- maybe (pure (Virtual Interactive))
                    (\f => PhysicalIdrSrc <$> ctxtPathToNS f) fname
    m <- newRef MD (initMetadata origin)
    session <- getSession
    fname <- if findipkg session then findIpkg fname else pure fname
    setMainFile fname
    loaded <- case fname of
      Nothing => logTime 1 "Loading prelude" loadPrelude
      Just f => logTime 1 "Loading main file" $ loadMainFile f
    displayStartupErrors loaded
    post <- get PostS
    catch (postOptions loaded post (execExprs opts)) emitError
    showTimeRecord
    whenJust (errorLine loaded) $ \_ =>
      coreLift $ exitWith (ExitFailure 1)

||| idris-mlir's command line.
export
driver : IO ()
driver = do
  Right opts <- getCmdOpts
    | Left err => do ignore $ fPutStrLn stderr $ "Error: " ++ err
                     exitWith (ExitFailure 1)
  Continue <- quitOpts opts
    | Abort => pure ()
  setupTerm
  coreRun (run opts)
    (\err : Error => do ignore $ fPutStrLn stderr $ "Uncaught error: " ++ show err
                        exitWith (ExitFailure 1))
    (\_ => pure ())
