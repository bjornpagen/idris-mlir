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

||| A file of the compilation's, in its directory, made first with those it
||| is in when it does not exist, as Idris's own -o makes its output's.
||| Not being able to write it is the compiler's failure, as idris-mlir's
||| own outputs are, not the program's.
write : String -> String -> Core ()
write path text = do
  case Libraries.Utils.Path.parent path of
    Just dir => do
      Right () <- coreLift (mkdirAll dir)
        | Left err => throw (InternalError ("cannot write " ++ path ++ ": " ++ show err))
      pure ()
    Nothing => pure ()
  Right () <- coreLift (writeFile path text)
    | Left err => throw (InternalError ("cannot write " ++ path ++ ": " ++ show err))
  pure ()

||| Nanoseconds on the monotonic clock.
now : Core Integer
now = toNano <$> coreLift (clockTime Monotonic)

||| The compilation's phases and their milliseconds, one `phase<TAB>ms` line
||| each, written at the path `--timing` names: what a compilation spends
||| where, measured rather than guessed.
reportTimes : Maybe String -> List (String, Integer) -> Core ()
reportTimes Nothing _ = pure ()
reportTimes (Just path) times =
  write path (concatMap (\(name, ns) => name ++ "\t" ++ show (ns `div` 1000000) ++ "\n") times)

||| The registry's entries against the loaded context, once, before
||| anything uses them; `--break-shape` breaks the one it names.
validated : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            Maybe String -> FC -> Core ()
validated breakShape fc = case !(validate breakShape) of
  Valid => pure ()
  Wrong at owner msg => reject at owner HookShape msg
  NoSuchEntry name => internal fc ("--break-shape=" ++ name ++ " names no entry of the registry")

||| The middle end: Translate's full Core, printed, and `Emit`'s
||| contract text.
middle : FC -> Source -> Core (String, String)
middle fc src = do
  let core = showSource src
  Right mlir <- pure (emit src)
    | Left msg => do
        ignore (coreLift (fPutStrLn stderr core))
        internal fc ("Emit: " ++ msg)
  pure (core, mlir)

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
  (core, mlir) <- middle fc prog
  t4 <- now
  write corePath core
  write mlirPath mlir
  t5 <- now
  reportTimes timing [ ("checks", t1 - t0), ("reachable", t2 - t1), ("translate", t3 - t2)
                     , ("print", t4 - t3), ("write", t5 - t4) ]
  pure []
