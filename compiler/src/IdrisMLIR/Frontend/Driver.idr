||| idris-mlir-front, the Idris side of idris-mlir: a function from files to
||| files. Given a program's main file, Idris builds it and the modules it
||| imports, reading and writing their TTCs, and the frontend writes the
||| program's Core and its idr module at the paths it is given; idris-mlir
||| then compiles the module. Given a package, Idris builds, checks,
||| installs or cleans it, which is how the prefix the frontend reads is
||| made. It runs no other program and reads no environment: the prefix
||| and the package directories are its arguments.
|||
|||     idris-mlir-front --prefix DIR [--package-path DIR]... [-p PACKAGE]...
|||                      [--no-prelude] TASK
|||
||| where TASK is one of
|||
|||     [--break-shape KEY] --core FILE -o FILE SOURCE
|||                       the program whose main file is SOURCE
|||     --check SOURCE    SOURCE and what it imports, built and checked
|||     --build PACKAGE.ipkg, --install PACKAGE.ipkg, --typecheck
|||     PACKAGE.ipkg, --clean PACKAGE.ipkg
|||                       Idris's package commands
|||     --libdir          the prefix's directory of packages, printed
|||
||| Idris prints what it reports on stdout: for a program only its errors,
||| as Idris's own compilation to an executable does, otherwise its progress
||| and its warnings too. The frontend's rejections are Idris errors,
||| printed the same way where they are found. The exit status is
||| idris-mlir's: 0, 1 for the compiler's own error, 2 for a usage error, 3
||| for any error of the program's, Idris's included. A package that does
||| not build is 1, as Idris's package commands decide.
module IdrisMLIR.Frontend.Driver

import Core.Context
import Core.Core
import Core.Directory
import Core.InitPrimitives
import Core.Metadata
import Core.Options
import Core.UnifyState

import Idris.CommandLine
import Idris.ModTree
import Idris.Package
import Idris.Package.Types
import Idris.REPL.Common
import Idris.REPL.Opts
import Idris.SetOptions
import Idris.Syntax

import IdrisMLIR.Frontend.Program
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Registry.Libraries

import Data.List
import Data.String
import System
import System.File

%default covering

------------------------------------------------------------------------------
-- The command line
------------------------------------------------------------------------------

||| What a run does.
data Task
  = ||| The program whose main file is the source: its Core and its module
    ||| written at these paths, the registry's entry the key names broken.
    Compile (Maybe String) String String String
  | ||| A main file and what it imports, built and checked.
    Check String
  | ||| One of Idris's package commands on a package file.
    PackageCommand PkgCommand String
  | ||| The directory of packages under the prefix.
    LibDir

||| The command line as given, every option once but those that repeat.
record Arguments where
  constructor MkArguments
  idrisPrefix : Maybe String
  packagePaths : List String
  packages : List String
  noPrelude : Bool
  breakShape : Maybe String
  corePath : Maybe String
  output : Maybe String
  check : Maybe String
  package : Maybe (PkgCommand, String)
  libDir : Bool
  sources : List String

none : Arguments
none = MkArguments Nothing [] [] False Nothing Nothing Nothing Nothing Nothing False []

||| What a run is given: the prefix, the rest of its session's arguments,
||| and its task.
record Run where
  constructor MkRun
  prefixDir : String
  given : Arguments
  task : Task

synopsis : String
synopsis = """
        usage: idris-mlir-front --prefix DIR [--package-path DIR]... [-p PACKAGE]... [--no-prelude] TASK
          TASK: [--break-shape KEY] --core FILE -o FILE SOURCE
              | --check SOURCE
              | --build|--install|--typecheck|--clean PACKAGE.ipkg
              | --libdir
        """

||| The options that take a value.
valued : List String
valued = [ "--prefix", "--package-path", "-p", "--break-shape", "--core", "-o", "--check"
         , "--build", "--install", "--typecheck", "--clean" ]

once : String -> Maybe a -> a -> Either String (Maybe a)
once _ Nothing x = Right (Just x)
once flag (Just _) _ = Left (flag ++ " is given twice")

packageCommand : String -> Maybe PkgCommand
packageCommand "--build" = Just Build
packageCommand "--install" = Just Install
packageCommand "--typecheck" = Just Typecheck
packageCommand "--clean" = Just Clean
packageCommand _ = Nothing

parse : Arguments -> List String -> Either String Arguments
parse a [] = Right a
parse a ("--prefix" :: d :: rest) = do
  p <- once "--prefix" a.idrisPrefix d
  parse ({ idrisPrefix := p } a) rest
parse a ("--package-path" :: d :: rest) = parse ({ packagePaths $= (++ [d]) } a) rest
parse a ("-p" :: p :: rest) = parse ({ packages $= (++ [p]) } a) rest
parse a ("--no-prelude" :: rest) = parse ({ noPrelude := True } a) rest
parse a ("--break-shape" :: k :: rest) = do
  b <- once "--break-shape" a.breakShape k
  parse ({ breakShape := b } a) rest
parse a ("--core" :: f :: rest) = do
  c <- once "--core" a.corePath f
  parse ({ corePath := c } a) rest
parse a ("-o" :: f :: rest) = do
  o <- once "-o" a.output f
  parse ({ output := o } a) rest
parse a ("--check" :: f :: rest) = do
  c <- once "--check" a.check f
  parse ({ check := c } a) rest
parse a ("--libdir" :: rest) = parse ({ libDir := True } a) rest
parse a (flag :: rest) =
  case (packageCommand flag, rest) of
    (Just cmd, f :: rest') => do
      p <- once "a package command" a.package (cmd, f)
      parse ({ package := p } a) rest'
    _ => if elem flag valued
           then Left (flag ++ " takes a value")
           else if isPrefixOf "-" flag
             then Left ("unknown option " ++ flag)
             else parse ({ sources $= (++ [flag]) } a) rest

||| One task, and only what that task reads.
taskOf : Arguments -> Either String Task
taskOf a = case (a.check, a.package, a.libDir) of
  (Nothing, Nothing, False) => compile
  (Just f, Nothing, False) => do onlyFor "--check"; Right (Check f)
  (Nothing, Just (cmd, f), False) => do onlyFor "a package command"; Right (PackageCommand cmd f)
  (Nothing, Nothing, True) => do onlyFor "--libdir"; Right LibDir
  _ => Left "--check, a package command and --libdir are tasks of their own"
  where
    onlyFor : String -> Either String ()
    onlyFor task =
      if isJust a.corePath || isJust a.output || isJust a.breakShape || not (null a.sources)
        then Left (task ++ " takes no source, --core, -o or --break-shape")
        else Right ()
    compile : Either String Task
    compile = do
      let Just core = a.corePath
        | Nothing => Left "no --core"
      let Just out = a.output
        | Nothing => Left "no -o"
      case a.sources of
        [source] => Right (Compile a.breakShape core out source)
        [] => Left "no source file"
        _ => Left "more than one source file"

arguments : List String -> Either String Run
arguments args = do
  a <- parse none args
  let Just dir = a.idrisPrefix
    | Nothing => Left "no --prefix"
  t <- taskOf a
  Right (MkRun dir a t)

------------------------------------------------------------------------------
-- Exit statuses
------------------------------------------------------------------------------

||| The compiler's own error is 1; every other error is the program's: 3.
statusOf : Error -> ExitCode
statusOf (InternalError _) = ExitFailure 1
statusOf _ = ExitFailure 3

||| The errors a build reported (and printed): the program's, unless one is
||| the compiler's.
statusOfAll : List Error -> ExitCode
statusOfAll errs = if any internal errs then ExitFailure 1 else ExitFailure 3
  where
    internal : Error -> Bool
    internal (InternalError _) = True
    internal _ = False

------------------------------------------------------------------------------
-- A run
------------------------------------------------------------------------------

||| The session: the prefix and the package directories given, prelude and
||| base, which every program sees (when they are installed: not yet when
||| they are the packages being built), and the packages asked for.
session : {auto c : Ref Ctxt Defs} -> Run -> Core ()
session r = do
  setPrefix r.prefixDir
  setWorkingDir "."
  when r.given.noPrelude $ setSession ({ noprelude := True } !getSession)
  traverse_ addPackageSearchPath r.given.packagePaths
  addPackageSearchPath !pkgGlobalDirectory
  for_ defaultPackages $ \p => catch (addPkgDir p anyBounds) (const (pure ()))
  for_ r.given.packages $ \p => addPkgDir p anyBounds

||| Builds the main file and the modules it imports, and loads the main
||| module from its TTC, or ends the run with the status of the errors
||| Idris reported. A main file that cannot be read is the program's error,
||| as Idris reports it.
built : {auto c : Ref Ctxt Defs} ->
        {auto s : Ref Syn SyntaxInfo} ->
        {auto o : Ref ROpts REPLOpts} ->
        String -> Core ModuleIdent
built source = do
  Right _ <- coreLift (readFile source)
    | Left err => throw (FileErr source err)
  mainModule <- ctxtPathToNS source
  u <- newRef UST initUState
  m <- newRef MD (initMetadata (PhysicalIdrSrc mainModule))
  resetContext (PhysicalIdrSrc mainModule)
  [] <- buildDeps source
    | errs => coreLift (exitWith (statusOfAll errs))
  pure mainModule

||| Idris shows an error's location with the lines of the source it read
||| last, which is the error's own only for an error found while its file
||| was elaborated. A rejection is found later, in any module of the
||| program, so the source shown is the file of the error's module when
||| the project has it, and none otherwise.
showingItsSource : {auto c : Ref Ctxt Defs} -> {auto o : Ref ROpts REPLOpts} ->
                   Error -> Core ()
showingItsSource err = case map fst (getErrorLoc err >>= isNonEmptyFC) of
  Just (PhysicalIdrSrc ident) => do
    path <- catch (moduleSource EmptyFC ident) (const (pure Nothing))
    text <- maybe (pure "") (\p => either (const "") id <$> coreLift (readFile p)) path
    setCurrentElabSource text
  _ => setCurrentElabSource ""

perform : {auto c : Ref Ctxt Defs} ->
          {auto s : Ref Syn SyntaxInfo} ->
          {auto o : Ref ROpts REPLOpts} ->
          Task -> Core ()
perform (Compile breakShape core out source) = do
  mainModule <- built source
  program mainModule breakShape core out
perform (Check source) = ignore (built source)
perform (PackageCommand cmd file) = do
  p <- newRef PostS defaultPost
  ignore (processPackageOpts [Package cmd (Just file)])
perform LibDir = coreLift (putStrLn !pkgGlobalDirectory)

frontend : Run -> Core ()
frontend r = do
  c <- newRef Ctxt !initDefs
  s <- newRef Syn initSyntax
  -- A compilation prints only errors, as Idris's own compilation to an
  -- executable does; checking and the package commands print Idris's
  -- progress and warnings too.
  let (mainFile, verbosity) = case r.task of
        Compile _ _ _ source => (Just source, ErrorLvl)
        Check source => (Just source, InfoLvl)
        _ => (Nothing, InfoLvl)
  o <- newRef ROpts (defaultOpts mainFile verbosity)
  -- What Idris prints is the same on any terminal: no colour, and no
  -- line broken at the terminal's width.
  setColor False
  setConsoleWidth (Just 0)
  addPrimitives
  catch (do session r; perform r.task) $ \err => do
    showingItsSource err
    emitError err
    coreLift (exitWith (statusOf err))

main : IO ()
main = do
  args <- getArgs
  case arguments (drop 1 args) of
    Left msg => do
      ignore (fPutStrLn stderr ("idris-mlir-front: " ++ msg ++ "\n" ++ synopsis))
      exitWith (ExitFailure 2)
    Right r => coreRun (frontend r)
                 (\err => do ignore (fPutStrLn stderr ("idris-mlir-front: " ++ show err))
                             exitWith (statusOf err))
                 pure
