-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| idris-mlir-front, the Idris side of idris-mlir: a function from files to
||| files. Given a program's main file, Idris builds it and the modules it
||| imports, reading and writing their TTCs, and the frontend writes the
||| program's idr module, its one output, at the path it is given;
||| idris-mlir then compiles the module. Given a package, Idris builds, checks,
||| installs or cleans it, which is how the prefix the frontend reads is
||| made. It runs no other program and reads no environment: the prefix
||| and the package directories are its arguments.
|||
|||     idris-mlir-front --prefix DIR [--package-path DIR]... [-p PACKAGE]...
|||                      [--no-prelude] TASK
|||
||| where TASK is one of
|||
|||     [--timing FILE] -o FILE SOURCE
|||                       the program whose main file is SOURCE
|||     --check SOURCE    SOURCE and what it imports, built and checked
|||     [--timing FILE] --build PACKAGE.ipkg, --install PACKAGE.ipkg,
|||     --typecheck PACKAGE.ipkg, --clean PACKAGE.ipkg
|||                       Idris's package commands
|||     --libdir          the prefix's directory of packages, printed
|||
||| A program the frontend refuses is a module too: it holds each refusal,
||| the first found first, Idris's own errors among them as refusals of the
||| rule `elaboration`, and no program; idris-mlir reads and reports them,
||| and the frontend prints none. Otherwise Idris prints what it reports on
||| stdout: for a program nothing but the compiler's own error, and for the
||| other tasks its progress, its warnings and its errors too. The exit
||| status is idris-mlir's: 0, 1 for the compiler's own error, 2 for a usage
||| error, 3 for a program refused (its module says why, and the status
||| decides nothing) or an error of a task that writes no module. A package
||| that does not build is 1, as Idris's package commands decide.
module IdrisMLIR.Frontend.Driver

import Core.Context
import Core.Core
import Core.Directory
import Core.InitPrimitives
import Core.Metadata
import Core.Options
import Core.UnifyState

import Idris.CommandLine
import Idris.Host
import Idris.ModTree
import Idris.Package
import Idris.Package.Types
import Idris.REPL.Common
import Idris.REPL.Opts
import Idris.SetOptions
import Idris.Syntax

import IdrisMLIR.Emit
import IdrisMLIR.Frontend.Profile
import IdrisMLIR.Frontend.Program
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate
import IdrisMLIR.Loc
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Grades.Grade

import Data.List
import Data.List1
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String
import System
import System.File

%default total

------------------------------------------------------------------------------
-- The command line
------------------------------------------------------------------------------

||| What a run does.
data Task
  = ||| The program whose main file is the source: its module written at
    ||| this path, its phases' times at the first when given.
    Compile (Maybe String) String String
  | ||| A main file and what it imports, built and checked.
    Check String
  | ||| One of Idris's package commands on a package file, its time written
    ||| at the path when given, with Idris's own phases printed as it runs
    ||| them.
    PackageCommand (Maybe String) PkgCommand String
  | ||| The directory of packages under the prefix.
    LibDir

||| The command line as given, every option once but those that repeat.
record Arguments where
  constructor MkArguments
  idrisPrefix : Maybe String
  packagePaths : SnocList String
  packages : SnocList String
  noPrelude : Bool
  timing : Maybe String
  output : Maybe String
  check : Maybe String
  package : Maybe (PkgCommand, String)
  libDir : Bool
  sources : SnocList String

none : Arguments
none = MkArguments Nothing [<] [<] False Nothing Nothing Nothing Nothing False [<]

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
          TASK: [--timing FILE] -o FILE SOURCE
              | --check SOURCE
              | [--timing FILE] --build|--install|--typecheck|--clean PACKAGE.ipkg
              | --libdir
        """

||| The options that take a value.
valued : SortedSet String
valued = SortedSet.fromList [ "--prefix", "--package-path", "-p", "--timing", "-o", "--check"
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
parse a ("--package-path" :: d :: rest) = parse ({ packagePaths $= (:< d) } a) rest
parse a ("-p" :: p :: rest) = parse ({ packages $= (:< p) } a) rest
parse a ("--no-prelude" :: rest) = parse ({ noPrelude := True } a) rest
parse a ("--timing" :: f :: rest) = do
  t <- once "--timing" a.timing f
  parse ({ timing := t } a) rest
parse a ("-o" :: f :: rest) = do
  o <- once "-o" a.output f
  parse ({ output := o } a) rest
parse a ("--check" :: f :: rest) = do
  c <- once "--check" a.check f
  parse ({ check := c } a) rest
parse a ("--libdir" :: rest) = parse ({ libDir := True } a) rest
parse a (flag :: rest) = case packageCommand flag of
    Just cmd => command cmd rest
    Nothing => other rest
  where
    -- Anything but a package command with its file: an option missing its
    -- value, an unknown option, or a source.
    other : List String -> Either String Arguments
    other more =
      if contains flag valued
        then Left (flag ++ " takes a value")
        else if isPrefixOf "-" flag
          then Left ("unknown option " ++ flag)
          else parse ({ sources $= (:< flag) } a) more

    command : PkgCommand -> List String -> Either String Arguments
    command cmd (f :: rest') = do
      p <- once "a package command" a.package (cmd, f)
      parse ({ package := p } a) rest'
    command cmd [] = other []

||| One task, and only what that task reads.
taskOf : Arguments -> Either String Task
taskOf a = case (a.check, a.package, a.libDir) of
  (Nothing, Nothing, False) => compile
  (Just f, Nothing, False) => do onlyFor "--check"; untimed "--check"; Right (Check f)
  (Nothing, Just (cmd, f), False) => do onlyFor "a package command"; Right (PackageCommand a.timing cmd f)
  (Nothing, Nothing, True) => do onlyFor "--libdir"; untimed "--libdir"; Right LibDir
  _ => Left "--check, a package command and --libdir are tasks of their own"
  where
    onlyFor : String -> Either String ()
    onlyFor task =
      if isJust a.output || not (null a.sources)
        then Left (task ++ " takes no source or -o")
        else Right ()
    untimed : String -> Either String ()
    untimed task = if isJust a.timing then Left (task ++ " takes no --timing") else Right ()
    compile : Either String Task
    compile = do
      let Just out = a.output
        | Nothing => Left "no -o"
      case a.sources <>> [] of
        [source] => Right (Compile a.timing out source)
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

||| The status of the errors a build reported (and printed), by the one
||| rule of the verdict: accepted < refused < internal, the worst seen
||| winning. The compiler's own error (1) makes the build the compiler's
||| whatever else it found, and the program's errors alone are its refusal
||| (3); a build that reported none is accepted, and has no errors to give
||| here. The order needs no exception for an error a refusal caused: a
||| refusal ends the translation of what it refuses (`Errors.noting`,
||| `TS.refused`), so no error found after it is its cascade, and an
||| internal error beside one is the compiler's, to be fixed before the
||| refusal can be believed.
statusOfAll : List1 Error -> ExitCode
statusOfAll errs = if any internal errs then ExitFailure 1 else ExitFailure 3
  where
    internal : Error -> Bool
    internal (InternalError _) = True
    internal _ = False

||| The status of one error, by the same rule.
statusOf : Error -> ExitCode
statusOf err = statusOfAll (err ::: [])

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
  traverse_ addPackageSearchPath (r.given.packagePaths <>> [])
  addPackageSearchPath !pkgGlobalDirectory
  for_ defaultPackages $ \p => catch (addPkgDir p anyBounds) (const (pure ()))
  for_ (r.given.packages <>> []) $ \p => addPkgDir p anyBounds

||| Builds the main file and the modules it imports, and loads the main
||| module from its TTC, as Idris recorded it once read (`Reloaded`, its
||| module the one given, which the file's path names, its checked file);
||| or the errors Idris reported, at least one, which it printed or not as
||| the session's verbosity says. A main file that cannot be read is the
||| program's error, as Idris reports it.
built : {auto c : Ref Ctxt Defs} ->
        {auto s : Ref Syn SyntaxInfo} ->
        {auto o : Ref ROpts REPLOpts} ->
        (mainModule : ModuleIdent) -> (source : String) -> Core Built
built mainModule source = do
  Right _ <- readText source
    | Left err => throw (FileErr source err)
  host.buildMain mainModule source

||| Where a rejection is: a refusal's site, or the location of Idris's own
||| error, or the main file's start when it has none.
siteOf : (main : NonEmptyFC) -> Rejection -> NonEmptyFC
siteOf main (Refused r) = r.site
siteOf main (ByIdris e) = fromMaybe main (getErrorLoc e >>= isNonEmptyFC)

||| A rejection as a refusal of a rule at its site (`siteOf`). Idris's own
||| error is a refusal of the rule `Elaboration`, its message Core's print
||| of the error: Idris's renderer (`Idris.Error.perror`) is covering, and
||| the frontend is total.
refusalOf : (main : NonEmptyFC) -> Rejection -> (SomeRule, NonEmptyFC, String)
refusalOf main r@(Refused refusal) = (refusal.rule, siteOf main r, refusal.message)
refusalOf main r@(ByIdris e) = (Refusal Elaboration, siteOf main r, show e)

||| The program refused: its refusals written, in the order given, into the
||| module at `out`, with no Core and nothing printed, since idris-mlir
||| reads and reports them; the status says the program was refused.
refusedAt : (out : String) -> List1 ModuleRefusal -> Core ()
refusedAt out rs = do
  writeRefused out rs
  coreLift (exitWith (ExitFailure 3))

||| The program refused for its rejections, each a refusal at its site
||| (`refusalOf`) in the order found (`refusedAt`). Each refusal's module is
||| the one the modules already read (none, when Idris could not build the
||| program) hold, or what `lacking` says, once the session is done, a
||| module they lack is (`moduleRefusals`).
refusing : {auto c : Ref Ctxt Defs} -> Modules -> (lacking : Core (ModuleIdent -> Lacked)) -> (main : NonEmptyFC) ->
           (out : String) -> List1 Rejection -> Core ()
refusing loaded lacking main out rs = do
  lacked <- lacking
  refusedAt out !(moduleRefusals lacked loaded (map (refusalOf main) rs))

||| What a module a refusal of a session that loaded no program names is,
||| where no table holds it: one Idris found, read at the home it found it
||| in; one it found nowhere is the project's module it failed to build,
||| which it was elaborating when it erred, read as the project's.
building : {auto c : Ref Ctxt Defs} -> Core (ModuleIdent -> Lacked)
building = do
  homes <- map (\(m, home, _) => (m, home)) <$> loadedModules
  pure (\m => FoundAt (fromMaybe Project (lookup m homes)))

||| A compilation rejected before its main module is named, which only
||| Idris's own error does: the session failed, or the main file's path
||| names no module. It is refused at its own location, or, where Idris
||| gives it none, at none (`noLoc`, as the translation places what Idris
||| does not locate): there is no main file's start to put it at. Its rule
||| and message are `refusalOf`'s for Idris's error. Essential: Idris
||| locates the error or it does not.
unnamed : {auto c : Ref Ctxt Defs} -> (out : String) -> Error -> Core ()
unnamed out err = do
  let rule : SomeRule = Refusal Elaboration
      message = show err
  refusals <- case getErrorLoc err >>= isNonEmptyFC of
    Just site => do
      lacked <- building
      moduleRefusals lacked SortedMap.empty ((rule, site, message) ::: [])
    Nothing => pure (MkModuleRefusal rule noLoc message ::: [])
  refusedAt out refusals

||| Idris shows an error's location with the lines of the source it read
||| last, which is the error's own only for an error found while its file
||| was elaborated. The compiler's own error is found later, in any module
||| of the program, so the source shown is the file of the error's module
||| when the project has it, and none otherwise.
showingItsSource : {auto c : Ref Ctxt Defs} -> {auto o : Ref ROpts REPLOpts} ->
                   Error -> Core ()
showingItsSource err = case map fst (getErrorLoc err >>= isNonEmptyFC) of
  Just (PhysicalIdrSrc ident) => do
    path <- catch (moduleSource EmptyFC ident) (const (pure Nothing))
    text <- maybe (pure "") (\p => either (const "") id <$> readText p) path
    setCurrentElabSource text
  _ => setCurrentElabSource ""

perform : {auto c : Ref Ctxt Defs} ->
          {auto s : Ref Syn SyntaxInfo} ->
          {auto o : Ref ROpts REPLOpts} ->
          Task -> Core ()
perform (Compile timing out source) = do
  -- The main module, named once from the file's path: the one built and
  -- reloaded, and the main file's start, where each rejection from here
  -- on that Idris gives no location is. An error before it is named is
  -- `unnamed`'s, in `frontend`.
  mainModule <- ctxtPathToNS source
  let main = mainSite mainModule
  catch (do Reloaded m <- built mainModule source
              | NotBuilt errs => refusing SortedMap.empty building main out (map ByIdris errs)
            -- The program loaded, each module's origin, source and name are
            -- read once, before anything locates a term in it: every module
            -- the session read, the main module among them.
            loaded <- modulesOf SortedMap.empty (map (\(ident, home, _) => (ident, home)) !loadedModules)
            -- The table holds every module the session loaded, so a
            -- refusal's module it lacks is one the session never read.
            [] <- program loaded m.ident m.file timing out
              | (r :: rs) => refusing loaded (pure (const Unloaded)) main out (r ::: rs)
            pure ())
    $ \err => case err of
        -- Essential: the compiler's own error is no refusal of the
        -- program, and `frontend` prints it.
        InternalError _ => throw err
        _ => refusing SortedMap.empty building main out (singleton (ByIdris err))
perform (Check source) = do
  mainModule <- ctxtPathToNS source
  Reloaded _ <- built mainModule source
    | NotBuilt errs => coreLift (exitWith (statusOfAll errs))
  pure ()
perform (PackageCommand timing cmd file) = do
  p <- newRef PostS defaultPost
  -- Timed, Idris prints its own phases as it runs them (`logTime`), and
  -- the command's whole time is the file's.
  when (isJust timing) $ setSession ({ logTimings := Just 1 } !getSession)
  start <- now
  ignore (host.processPackageOpts [Package cmd (Just file)])
  end <- now
  reportTimes timing [(pack (dropWhile (== '-') (unpack (show cmd))), end - start)]
perform LibDir = coreLift (putStrLn !pkgGlobalDirectory)

frontend : Run -> Core ()
frontend r = do
  c <- newRef Ctxt !initDefs
  s <- newRef Syn initSyntax
  -- A compilation prints nothing: the program's errors are refusals its
  -- module holds. Checking and the package commands print Idris's
  -- progress, warnings and errors.
  let (mainFile, verbosity) = case r.task of
        Compile _ _ source => (Just source, NoneLvl)
        Check source => (Just source, InfoLvl)
        _ => (Nothing, InfoLvl)
  o <- newRef ROpts (defaultOpts mainFile verbosity)
  -- What Idris prints is the same on any terminal: no colour, and no
  -- line broken at the terminal's width.
  setColor False
  setConsoleWidth (Just 0)
  addPrimitives
  catch (do session r; perform r.task) $ \err => case (r.task, err) of
    -- The compiler's own error is printed whatever the task. Essential:
    -- the refusal and the compiler's failure are two outcomes (3 and 1).
    (Compile _ _ _, InternalError _) => do
      update ROpts { verbosity := ErrorLvl }
      printed err
    -- Once the main module is named `perform` refuses each error but the
    -- compiler's own, so a compilation's error here came before it was
    -- named, or in refusing another.
    (Compile _ out _, _) => unnamed out err
    _ => printed err
  where
    printed : {auto c : Ref Ctxt Defs} -> {auto s : Ref Syn SyntaxInfo} -> {auto o : Ref ROpts REPLOpts} ->
              Error -> Core ()
    printed err = do
      showingItsSource err
      host.emitError err
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
