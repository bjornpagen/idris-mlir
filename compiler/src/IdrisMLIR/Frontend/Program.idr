||| A program, once Idris has built its main file: the user's `main` checked
||| against the profile, translated to Core and emitted as MLIR, the Core and
||| the module written to the paths idris-mlir names. Nothing runs a tool:
||| the pipeline and the link are idris-mlir's.
module IdrisMLIR.Frontend.Program

import Core.Context
import Core.Core
import Core.Directory
import Core.TT

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
import Data.String
import System.File

import Libraries.Data.WithDefault

%default covering

||| A file of the compilation's. Not being able to write it is the
||| compiler's failure, as idris-mlir's own outputs are, not the program's.
write : String -> String -> Core ()
write path text = do
  Right () <- coreLift (writeFile path text)
    | Left err => throw (InternalError ("cannot write " ++ path ++ ": " ++ show err))
  pure ()

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
||| at `mlirPath`.
export
program : {auto c : Ref Ctxt Defs} ->
          (mainFile : ModuleIdent) -> (breakShape : Maybe String) ->
          (corePath, mlirPath : String) -> Core ()
program mainFile breakShape corePath mlirPath = do
  -- Until main is found, an error is at the main file.
  s <- newRef TState (initState (MkFC (PhysicalIdrSrc mainFile) (0, 0) (0, 0)))
  (main, mainIdent) <- entryPoint
  defs <- get Ctxt
  Just mainDef <- lookupCtxtExact main (gamma defs)
    | Nothing => internal EmptyFC "main has no definition"
  let fc = location mainDef
  put TState (initState fc)
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
        unless (trusted || elem target userNames) $
          reject at (show m) ProgramShape
                 ("imports " ++ target ++ ", which is neither a user module nor a trusted module")
    Nothing => pure ()
  for_ sources $ \(m, path) => case path of
    Just p => checkPragmas m p
    Nothing => reject fc programEntry ProgramShape
                 ("loads " ++ show m ++ ", a module of the project whose source is missing")
  checkReachable fc [main]
  prog <- translateIOProgram fc main
  (core, mlir) <- middle fc prog
  write corePath core
  write mlirPath mlir
