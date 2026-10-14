||| A program, once Idris has built its main file: the user's `main` checked
||| against the profile, translated to Core and emitted as MLIR, the Core and
||| the module written to the paths idris-mlir names. Nothing runs a tool:
||| the pipeline and the link are idris-mlir's.
module IdrisMLIR.Frontend.Program

import Core.Context
import Core.Core
import Core.Directory
import Core.TT
import Idris.Syntax

import IdrisMLIR.Emit
import IdrisMLIR.Ids
import IdrisMLIR.Rule
import IdrisMLIR.Term
import IdrisMLIR.Frontend.Profile
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Registry.Primitives

import Data.List
import Data.List1
import Data.Maybe
import Data.SortedSet
import Data.String
import System.Clock
import System.File

import Libraries.Data.ANameMap
import Libraries.Data.WithDefault
import Libraries.Utils.Path

%default covering

||| Not being able to write a file of the compilation's is the compiler's
||| failure, as idris-mlir's own outputs are, not the program's.
cannotWrite : String -> FileError -> Core a
cannotWrite path err = throw (InternalError ("cannot write " ++ path ++ ": " ++ show err))

||| A file of the compilation's, in its directory, made first with those it
||| is in when it does not exist, as Idris's own -o makes its output's,
||| written text by text: each text is made as it is written, so that a
||| file the size of the program is never one string. A text that is an
||| error ends the writing, and the file is removed: a compilation that
||| fails writes nothing.
writeTexts : String -> List (Lazy (Either String String)) -> Core (Either String ())
writeTexts path texts = do
  case Libraries.Utils.Path.parent path of
    Just dir => do
      Right () <- coreLift (mkdirAll dir)
        | Left err => cannotWrite path err
      pure ()
    Nothing => pure ()
  Right h <- coreLift (openFile path WriteTruncate)
    | Left err => cannotWrite path err
  written <- each h texts
  coreLift (closeFile h)
  case written of
    Left _ => ignore (coreLift (removeFile path))
    Right () => pure ()
  pure written
  where
    -- Each text is made only once the one before it is written, and is
    -- garbage once written.
    each : File -> List (Lazy (Either String String)) -> Core (Either String ())
    each h [] = pure (Right ())
    each h (t :: ts) = case Force t of
      Left msg => pure (Left msg)
      Right text => do
        Right () <- coreLift (fPutStr h text)
          | Left err => do coreLift (closeFile h); cannotWrite path err
        each h ts

||| A file every text of which is one.
writeAll : String -> List (Lazy String) -> Core ()
writeAll path texts = ignore (writeTexts path (map right texts))
  where
    right : Lazy String -> Lazy (Either String String)
    right t = Right (Force t)

||| Nanoseconds on the monotonic clock.
now : Core Integer
now = toNano <$> coreLift (clockTime Monotonic)

||| The compilation's phases and their milliseconds, one `phase<TAB>ms` line
||| each, written at the path `--timing` names: what a compilation spends
||| where, measured rather than guessed.
reportTimes : Maybe String -> List (String, Integer) -> Core ()
reportTimes Nothing _ = pure ()
reportTimes (Just path) times =
  writeAll path (map line times)
  where
    line : (String, Integer) -> Lazy String
    line (name, ns) = name ++ "\t" ++ show (ns `div` 1000000) ++ "\n"

||| The registry's entries against the loaded context, once, before
||| anything uses them; `--break-shape` breaks the one it names.
validated : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            Maybe String -> FC -> Core ()
validated breakShape fc = case !(validate breakShape) of
  Valid => pure ()
  Wrong at owner msg => reject at owner HookShape msg
  NoSuchEntry name => internal fc ("--break-shape=" ++ name ++ " names no entry of the registry")

||| The middle end: `Emit`'s contract text written at `mlirPath`, then
||| Translate's full Core, printed, at `corePath`. What `Emit` cannot write
||| is the compiler's error, reported after the Core, on stderr, and then
||| neither is written.
middle : FC -> Source -> (corePath, mlirPath : String) -> Core ()
middle fc src corePath mlirPath = do
  Right () <- either (pure . Left) (writeTexts mlirPath) (emit src)
    | Left msg => do
        for_ (sourceTexts src) $ \t => ignore (coreLift (fPutStr stderr (Force t)))
        ignore (coreLift (fPutStrLn stderr ""))
        internal fc ("Emit: " ++ msg)
  writeAll corePath (sourceTexts src)

isUser : Origin -> Bool
isUser User = True
isUser _ = False

||| The function the program runs: `main` as Idris resolves it in the main
||| file, the one definition of that name visible there, with its module.
||| That is the main module's own `main` or one it imports; another
||| module's private `main` is not seen, and two visible ones are ambiguous,
||| as Idris finds them.
entryPoint : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Core (Name, ModuleIdent)
entryPoint = do
  defs <- get Ctxt
  found <- lookupCtxtName (UN (Basic programEntry)) (gamma defs)
  here <- (::) <$> getNS <*> getNestedNS
  visible <- filterM (visibleFrom here) (map (\(_, _, def) => def) found)
  case visible of
    [def] => case fullname def of
      n@(NS ns _) => pure (n, nsAsModuleIdent ns)
      n => internal EmptyFC ("main has no module: " ++ show n)
    [] => reject EmptyFC programEntry ProgramShape "the program defines no main"
    ms => reject EmptyFC programEntry ProgramShape
            ("main is ambiguous: " ++ joinBy ", " (map (show . fullname) ms))
  where
    visibleFrom : List Namespace -> GlobalDef -> Core Bool
    visibleFrom here def = case fullname def of
      n@(NS ns _) =>
        if !(isVisible ns)
          then pure (visibleInAny here n (collapseDefault (visibility def)))
          else pure False
      _ => pure False

||| Compiles the program Idris has built from its main file, whose path
||| names the module `mainFile`, into the Core at `corePath` and the module
||| at `mlirPath`, or gives the program's rejections, the first found
||| first, and writes nothing. The checks of the source and of what the
||| program reaches report every rejection they find, and the translation
||| every rejected instance of what they did not refuse. An error that is
||| not a rejection (no main, a broken registry entry, the compiler's own)
||| is thrown.
export
program : {auto c : Ref Ctxt Defs} -> {auto syn : Ref Syn SyntaxInfo} ->
          (mainFile : ModuleIdent) -> (breakShape : Maybe String) ->
          (timing : Maybe String) -> (corePath, mlirPath : String) -> Core (List Error)
program mainFile breakShape timing corePath mlirPath = do
  t0 <- now
  -- The interfaces of every module Idris loaded for the program, which
  -- Idris keeps with their syntax rather than with their definitions.
  interfaces <- SortedSet.fromList . map fst . ANameMap.toList . (.ifaces) <$> get Syn
  -- Until main is found, an error is at the main file.
  s <- newRef TState (initState interfaces (MkFC (PhysicalIdrSrc mainFile) (0, 0) (0, 0)))
  (main, mainIdent) <- entryPoint
  defs <- get Ctxt
  Just mainDef <- lookupCtxtExact main (gamma defs)
    | Nothing => internal EmptyFC "main has no definition"
  let fc = location mainDef
  put TState (initState interfaces fc)
  validated breakShape fc
  -- Every module of the project's is one with source, whose pragmas are
  -- checked. The main file's module is loaded from its TTC as the module of
  -- no name, and Idris is in its namespace. Library modules outside the
  -- table may be loaded, but not reached (checkReachable).
  fileIdent <- nsAsModuleIdent <$> getNS
  let mods = fileIdent :: mainIdent :: filter (\m => not (null (unsafeUnfoldModuleIdent m))) (map (\(_, (m, _, _)) => m) defs.allImported)
  user <- filterM (\m => isUser <$> originOf m) (nub mods)
  sources <- for user $ \m => do
    path <- moduleSource fc m
    pure (m, path)
  let userNames = map (show . fst) (filter (isJust . snd) sources)
  -- The user's own imports are of user modules or trusted ones, rejected
  -- at the import itself.
  for_ sources $ \(m, path) => case path of
    Just p => do
      is <- imports m p
      for_ is $ \(target, at) => do
        trusted <- covers Trusted <$> originOf (moduleIdent (forget (split (== '.') target)))
        unless (trusted || elem target userNames) $ noted $
          reject at (show m) ProgramShape
                 ("imports " ++ target ++ ", which is neither a user module nor a trusted module")
    Nothing => pure ()
  for_ sources $ \(m, path) => noted $ case path of
    Just p => checkPragmas m p
    Nothing => reject fc programEntry ProgramShape
                 ("loads " ++ show m ++ ", a module of the project whose source is missing")
  t1 <- now
  checkReachable fc [main]
  t2 <- now
  Just prog <- translateIOProgram fc main
    | Nothing => do
        t3 <- now
        reportTimes timing [("checks", t1 - t0), ("reachable", t2 - t1), ("translate", t3 - t2)]
        rejections
  t3 <- now
  middle fc prog corePath mlirPath
  t4 <- now
  reportTimes timing [ ("checks", t1 - t0), ("reachable", t2 - t1), ("translate", t3 - t2)
                     , ("emit", t4 - t3) ]
  pure []
