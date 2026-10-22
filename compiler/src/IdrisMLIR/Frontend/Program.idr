-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| A program, once Idris has built its main file: the user's `main` checked
||| against the profile, translated to Core and emitted as MLIR, the module,
||| the compilation's one output, written to the path idris-mlir names. Before the translation,
||| the growth check bounds every static position, or refuses the types that
||| grow without bound. Nothing runs a tool: the pipeline and the link are
||| idris-mlir's.
module IdrisMLIR.Frontend.Program

import Core.Context
import Core.Core
import Core.Directory
import Core.TT
import Idris.Host
import Idris.Syntax

import IdrisMLIR.Emit
import IdrisMLIR.Ids
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Term
import IdrisMLIR.Frontend.Growth
import IdrisMLIR.Frontend.Profile
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate
import IdrisMLIR.Frontend.Translate.Boundary
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Registry.Primitives

import Data.List
import Data.List1
import Data.Maybe
import Data.SortedMap
import Data.SortedSet
import Data.String
import System.Clock
import System.File

import Libraries.Data.ANameMap
import Libraries.Data.WithDefault
import Libraries.Utils.Path

%default total

||| The directory a file of the compilation's is in, made first with those
||| it is in when it does not exist, as Idris's own -o makes its output's.
||| Not being able to write a file is the compiler's failure, as
||| idris-mlir's own outputs are, not the program's.
makeParent : String -> Core ()
makeParent path = case Libraries.Utils.Path.parent path of
  Just dir => do
    Right () <- coreLift (mkdirAll dir)
      | Left err => throw (InternalError ("cannot write " ++ path ++ ": " ++ show err))
    pure ()
  Nothing => pure ()

||| A file of the compilation's.
write : String -> String -> Core ()
write path text = do
  makeParent path
  Right () <- coreLift (writeFile path text)
    | Left err => throw (InternalError ("cannot write " ++ path ++ ": " ++ show err))
  pure ()

||| The module, written as Emit makes it, top-level op by top-level op, so
||| that no text of the whole module is held. It streams to its path, and a
||| module Emit gives up on is removed, so a failed emit leaves no partial
||| module there: its message is the compiler's failure. There is no write beside the path and rename onto
||| it: base has no rename, and `%foreign` is outside the language this
||| compiler compiles, which the frontend is written in.
covering
writeModule : FC -> String -> Source -> Core ()
writeModule fc path src = do
  makeParent path
  Right h <- coreLift (openFile path WriteTruncate)
    | Left err => throw (InternalError ("cannot write " ++ path ++ ": " ++ show err))
  emitted <- coreLift (emit h src)
  coreLift (closeFile h)
  case emitted of
    Right () => pure ()
    Left msg => do
      ignore (coreLift (removeFile path))
      internal fc ("Emit: " ++ msg)

||| A program refused, written where its module would be: a module that
||| holds each refusal (`Emit.refused`) and no program, which the driver
||| reads and reports. Not being able to write it is the compiler's failure.
export covering
writeRefused : String -> List1 ModuleRefusal -> Core ()
writeRefused path refusals = do
  makeParent path
  Right h <- coreLift (openFile path WriteTruncate)
    | Left err => throw (InternalError ("cannot write " ++ path ++ ": " ++ show err))
  written <- coreLift (refused h refusals)
  coreLift (closeFile h)
  case written of
    Right () => pure ()
    Left msg => do
      ignore (coreLift (removeFile path))
      throw (InternalError ("cannot write " ++ path ++ ": " ++ msg))

||| Nanoseconds on the monotonic clock.
export
now : Core Integer
now = toNano <$> coreLift (clockTime Monotonic)

||| A run's phases and their milliseconds, one `phase<TAB>ms` line each,
||| written at the path `--timing` names: what a compilation or a package
||| command spends where, measured rather than guessed.
export
reportTimes : Maybe String -> List (String, Integer) -> Core ()
reportTimes Nothing _ = pure ()
reportTimes (Just path) times =
  write path (concatMap (\(name, ns) => name ++ "\t" ++ show (ns `div` 1000000) ++ "\n") times)

||| The registry's entries against the loaded context, once, before
||| anything uses them; a broken entry is a refusal, at the module when the
||| entry has no location.
validated : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Front ()
validated = case !(core (validate !frozenContext (!getState).moduleFC)) of
  Nothing => pure ()
  Just r => rejectWith r

isUser : Origin -> Bool
isUser User = True
isUser _ = False

||| The function the program runs: `main` as Idris resolves it in the main
||| file, the one definition of that name visible there. That is the main
||| module's own `main` or one it imports; another module's private `main`
||| is not seen, and two visible ones are ambiguous, as Idris finds them.
entryPoint : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Front GlobalDef
entryPoint = do
  defs <- getDefs
  entry <- core (internUserName programEntry)
  found <- core (lookupCtxtName (UN entry) (gamma defs))
  here <- core ((::) <$> getNS <*> getNestedNS)
  visible <- keepIf (visibleFrom here) (map (\(_, _, def) => def) found)
  case visible of
    [def] => pure def
    [] => reject EmptyFC programEntry ProgramShape "the program defines no main"
    ms => reject EmptyFC programEntry ProgramShape
            ("main is ambiguous: " ++ joinBy ", " (map (show . fullname) ms))
  where
    visibleFrom : List Namespace -> GlobalDef -> Front Bool
    visibleFrom here def = case fullname def of
      n@(NS ns _) =>
        if !(core (isVisible ns))
          then pure (visibleInAny here n (collapseDefault (visibility def)))
          else pure False
      _ => pure False

||| Compiles the program Idris has built from its main file, whose path
||| names the module `mainFile`, into the module at `mlirPath`, or gives the
||| program's rejections, the first found first, and writes nothing. What
||| each module the session loaded is (`loaded`) was read once, before
||| it. The checks of the source and of what the
||| program reaches report every rejection they find, the growth check
||| every cause of a type grown without bound, and the translation of a
||| program the growth check admits every rejected instance of what the
||| checks did not refuse. A refusal that stops the compilation (no main, a
||| broken registry entry) is one of them; only the compiler's own error is
||| thrown.
export covering
program : {auto c : Ref Ctxt Defs} -> {auto syn : Ref Syn SyntaxInfo} ->
          (loaded : Modules) -> (mainFile : ModuleIdent) -> (timing : Maybe String) ->
          (mlirPath : String) -> Core (List Rejection)
program loaded mainFile timing mlirPath = do
  t0 <- now
  -- The interfaces of every module Idris loaded for the program, which
  -- Idris keeps with their syntax rather than with their definitions.
  interfaces <- SortedSet.fromList . map fst . ANameMap.toList . (.ifaces) <$> get Syn
  -- Until main is found, a refusal is at the main file's start.
  let fileSite : NonEmptyFC = (PhysicalIdrSrc mainFile, (0, 0), (0, 0))
  -- Idris has loaded the program and everything it imports: the context
  -- changes no more, and every normaliser reads it as frozen here.
  frozen <- host.freezeContext
  application <- applicationOf
  s <- newRef TState (initState (MkRead frozen SortedMap.empty application) loaded interfaces fileSite)
  Just mainDef <- noting (entered fileSite)
    | Nothing => rejections
  -- Once the entry is found, every definition the phases after it can meet
  -- from it is read, once, and they read nothing else of the context.
  r <- readProgram (!(get TState)).reads (fullname mainDef)
  update TState { reads := r }
  noted (compiled t0 mainDef)
  rejections
  where
   -- The project's modules among the checked ones, each once, in the order
   -- given, with its checked file and its source when the project has it,
   -- read from the table, which was read over the same modules.
   userModules : SortedSet ModuleIdent -> List (ModuleIdent, String) -> List (ModuleIdent, String, Maybe String)
   userModules seen [] = []
   userModules seen ((m, checked) :: rest) =
     if contains m seen then userModules seen rest else
       let after = userModules (insert m seen) rest in
       case lookup m loaded of
         Just l => if isUser l.origin then (m, checked, l.source) :: after else after
         Nothing => after

   -- The program's entry, where a refusal is located from then on, once
   -- the registry's entries are found good against the loaded context.
   entered : {auto s : Ref TState TS} -> NonEmptyFC -> Front GlobalDef
   entered fileSite = do
    mainDef <- entryPoint
    updateState { moduleFC := fromMaybe fileSite (isNonEmptyFC (location mainDef)) }
    validated
    pure mainDef

   covering
   compiled : {auto s : Ref TState TS} -> Integer -> GlobalDef -> Front ()
   compiled t0 mainDef = do
    let main = fullname mainDef
    let fc = location mainDef
    -- Every module of the project's is one with a checked module and a
    -- source: the main file's, named as its path names it, which is where
    -- its terms are located, and every one the session loaded, among them
    -- the module `main` is in. Library modules outside the table may be
    -- loaded, but not reached (checkReachable).
    session <- core loadedModules
    Just mainChecked <- core elaboratedChecked
      | Nothing => internal fc "the main file's checked module is not loaded"
    let users = userModules SortedSet.empty ((mainFile, mainChecked) :: map (\(m, _, checked) => (m, checked)) session)
    -- The user's own imports are of user modules or trusted ones, and its
    -- pragmas those the elaborator discharges, each read from its checked
    -- module and rejected where the source writes it.
    for_ users $ \(m, checked, _) => core (checkModule m checked)
    for_ users $ \(m, _, path) => core $ noted $ case path of
      Just p => checkSpelled m p
      Nothing => reject fc programEntry ProgramShape
                   ("loads " ++ show m ++ ", a module of the project whose source is missing")
    t1 <- core now
    core (checkReachable fc [main])
    t2 <- core now
    admitted <- core (checkGrowth fc main)
    t3 <- core now
    let checked = [("checks", t1 - t0), ("reachable", t2 - t1), ("growth", t3 - t2)]
    -- A program whose growth is refused is not translated: no potential, no
    -- bound for the translation to stay within. Every refusal found so far
    -- is reported.
    True <- pure admitted
      | False => core (reportTimes timing checked)
    Just prog <- translateIOProgram fc main
      | Nothing => do
          t4 <- core now
          core (reportTimes timing (checked ++ [("translate", t4 - t3)]))
    t4 <- core now
    core (writeModule fc mlirPath prog)
    t5 <- core now
    core (reportTimes timing (checked ++ [("translate", t4 - t3), ("emit", t5 - t4)]))
