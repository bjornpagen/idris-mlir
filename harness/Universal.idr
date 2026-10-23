-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What holds of every compilation, checked on each program test's own
||| compilation (Programs.idr): the fixture is compiled once, and nothing
||| compiles it a second time, since a compile is seconds and there are
||| hundreds of fixtures. What holds of each pass, that it keeps the
||| quantities Idris proved and the rest of its contracts, and the promises
||| every compiled program keeps (its tail calls jumps, its cycles on frame
||| stacks, its in-place rebuilds made, its frames limited), the
||| compilation checks as the pass runs (--idr-contracts), and its verifier
||| after every pass; what is checked here is what it left.
|||
||| Acceptance is a property of the program, never of the optimizer: a
||| transform an optimization makes is an action of MLIR's action framework
||| that only makes the code faster or smaller, and skipped it leaves valid
||| IR whose behaviour is the same but for the stack and the heap it needs.
||| So every program, compiled again from the module the frontend emitted
||| with a drawn set of those actions skipped, is accepted again and holds
||| every case its test names, and every refused program is refused again
||| by the same rule at the same line. A promise's obligation (an in-place
||| rebuild, a tail call's jump, a destination) is no action: it is the
||| pipeline's, never skippable, so a verdict that rested on an optimization
||| shows here as a verdict that changes.
module Universal

import Data.List
import Data.Maybe
import Data.SortedSet
import Data.String
import System
import System.File

import Files
import Harness
import Reject
import Serve

%default covering

------------------------------------------------------------------------------
-- What an object imports
------------------------------------------------------------------------------

||| A fact of the target entry that the build writes beside the runtime
||| (runtime/CMakeLists.txt) and the harness reads: codegen-symbols, the
||| calls LLVM makes by itself for the target (copies, fills, and what else
||| its code generation emits), one per line; symbol-prefix, the prefix the
||| object format puts before a C name ("_" on Mach-O, empty on ELF, which
||| is a fact like any other); baseline-cpu-flags and baseline-cpu-features,
||| the pinned C compiler's flags for the baseline CPU the runtime is
||| compiled for and the features the build derived from them, one per
||| line. Without the file, the line naming it: the harness has no fact to
||| check against, and no check runs on a guessed one.
export
runtimeFact : (devPrefix : String) -> String -> IO (Either String String)
runtimeFact devPrefix name = do
  let path = devPrefix ++ "/runtime/" ++ name
  Just text <- readIfThere path
    | Nothing => pure (Left ("object: no " ++ path ++ ", which the build writes"))
  pure (Right (trailing text))

||| A symbol in C names: the object format's prefix taken off. A tool that
||| prints a symbol prints it with the prefix, and no allowed list spells
||| one, so every comparison here is in C names.
cName : (symbolPrefix : String) -> String -> String
cName symbolPrefix s = if isPrefixOf symbolPrefix s then pack (drop (length symbolPrefix) (unpack s)) else s

||| The symbols llvm-nm printed for several files, in C names, sorted, each
||| once: with several files it heads each one's symbols with its name, a
||| line ending in a colon, and parts them with blank lines.
symbolsOf : (symbolPrefix : String) -> String -> List String
symbolsOf symbolPrefix text = sort (nub (map (cName symbolPrefix) (filter kept (lines text))))
  where
    kept : String -> Bool
    kept l = l /= "" && not (isSuffixOf ":" l)

||| The calls code generation makes for Doubles: libm's functions, and those
||| LLVM substitutes for `pow` (exp2, ldexp). Any program may hold a Double,
||| so every program is allowed them. The runtime's own imports need no
||| list: they are read off the runtime object.
libmSymbols : List String
libmSymbols = ["exp", "log", "pow", "sin", "cos", "tan", "asin", "acos", "atan", "sqrt", "floor", "ceil", "exp2", "ldexp"]

||| What the runtime object every program links defines and imports (its
||| native half: the bitcode in it names the same symbols), in C names.
runtimeSymbols : Env -> (symbolPrefix : String) -> IO (List String)
runtimeSymbols e symbolPrefix = do
  (_, runtime) <- captured e [e.tools.idrisMlir, "--print-runtime"] (Apart ToCaller)
  (_, text) <- captured e [e.tools.llvmBin ++ "/llvm-nm", "--no-llvm-bc", "--format=just-symbols", trailing runtime]
                        (Apart (ToFile "/dev/null"))
  pure (map (cName symbolPrefix) (lines text))

||| The undefined symbols of the objects a build wrote, one per bin, are
||| among those allowed to a program: the calls code generation makes by
||| itself, the runtime's (the bodies the program did not inline, which
||| resolve there, and what the runtime itself imports), and libm's. A
||| symbol one object defines and another uses is the program's own, so
||| what the objects import is what any of them leaves undefined, less what
||| any of them defines.
objectImports : Env -> (objects : List String) -> IO (Holds, List String)
objectImports e [] = pure (Broken, ["object: none written"])
objectImports e objects = do
  Right codegen <- runtimeFact e.tools.devPrefix "codegen-symbols"
    | Left line => pure (Broken, [line])
  Right symbolPrefix <- runtimeFact e.tools.devPrefix "symbol-prefix"
    | Left line => pure (Broken, [line])
  let nm = e.tools.llvmBin ++ "/llvm-nm"
  undefinedRead <- bounded e ([nm, "--undefined-only", "--format=just-symbols"] ++ objects)
                            (ToFile (inWork e "nm.raw")) (Apart (ToFile (inWork e "nm.err")))
  definedRead <- if succeeded undefinedRead
                    then bounded e ([nm, "--defined-only", "--extern-only", "--format=just-symbols"] ++ objects)
                                 (ToFile (inWork e "nm.defined")) (Apart (ToFile (inWork e "nm.defined.err")))
                    else pure undefinedRead
  if not (succeeded definedRead)
     then do
       shown <- firstLines 40 [inWork e "nm.err", inWork e "nm.defined.err"]
       pure (Broken, "object: llvm-nm failed" :: indented shown)
     else do
       own <- SortedSet.fromList . symbolsOf symbolPrefix . fromMaybe "" <$> readIfThere (inWork e "nm.defined")
       imported <- filter (\s => not (contains s own)) . symbolsOf symbolPrefix . fromMaybe "" <$> readIfThere (inWork e "nm.raw")
       runtime <- runtimeSymbols e symbolPrefix
       let allowed = SortedSet.fromList (lines codegen ++ runtime ++ libmSymbols)
       pure $ case filter (\s => not (contains s allowed)) imported of
         [] => (Held, ["object: no undefined symbol outside the allowed set"])
         extra => (Broken, ["object: undefined symbols outside the allowed set:" ++ concatMap (" " ++) extra])

------------------------------------------------------------------------------
-- The optimizations' actions skipped
------------------------------------------------------------------------------

||| The seed the skipped set is drawn from: IDRIS_MLIR_ACTIONS_SEED, which
||| a failure names and which replays it, or the clock's seconds.
export
actionsSeed : IO Integer
actionsSeed = do
  given <- getEnv "IDRIS_MLIR_ACTIONS_SEED"
  case given >>= parseInteger of
    Just seed => pure seed
    Nothing => time

seedNamed : Integer -> String
seedNamed seed = "skipped actions (IDRIS_MLIR_ACTIONS_SEED=" ++ show seed ++ ")"

||| idris-mlir-opt's debug counter of the set drawn from the seed, as one
||| option, or none when the draw skips nothing; nothing at all when
||| idris-mlir-opt names no action tags. Each action tag (every action the
||| passes take, as idris-mlir-opt names them, `--idr-action-tags`) is
||| left whole, skipped whole, or cut after its first few actions. The
||| skipped pipeline runs in idris-mlir-opt, which keeps upstream's debug
||| counter (idris-mlir registers none), on one thread, so the counter
||| meets the actions in one order and a seed replays.
drawnSkips : Env -> (seed : Integer) -> IO (Maybe (List String))
drawnSkips e seed = do
  (status, tags) <- captured e [e.tools.idrisMlirOpt, "--idr-action-tags"] (Apart ToCaller)
  pure (if succeeded status then Just (counter (draw seed (words tags))) else Nothing)
  where
    draw : Integer -> List String -> List String
    draw _ [] = []
    draw x (tag :: rest) =
      let next = mod (x * 1103515245 + 12345) 2147483648 in
      case mod next 3 of
        1 => (tag ++ "-count=0") :: draw next rest
        2 => (tag ++ "-skip=0") :: (tag ++ "-count=" ++ show (mod (div next 3) 8)) :: draw next rest
        _ => draw next rest

    counter : List String -> List String
    counter [] = []
    counter skips = ["--mlir-debug-counter=" ++ joinBy "," skips]

||| The program of FIXTURE, whose emitted module is MODULE, lowered again
||| from it with the drawn skips and the OPTIONs (its contracts and stage
||| properties, which idris-mlir-opt checks as idris-mlir does), then
||| compiled by idris-mlir and linked with the checked runtime as the
||| program compiled with none skipped was, is accepted, and on every case
||| of FIXTURE ends as that program ended (the same status, stdout and
||| stderr, which its run kept in the work directory's case-runs): the
||| cases' own expectations are the program test's to hold, so a wrong case
||| is named once.
skipsHold : Env -> (seed : Integer) -> (fixture, emitted : String) -> (options : List String) -> IO (Holds, List String)
skipsHold e seed fixture emitted options = do
  Just counter <- drawnSkips e seed
    | Nothing => pure (Broken, ["skipped actions: idris-mlir-opt names no action tags"])
  removed e (inWork e "skipped")
  made e (inWork e "skipped")
  let out = ToFile (inWork e "skipped.out")
  let err = Apart (ToFile (inWork e "skipped.err"))
  lowered <- bounded e ([e.tools.idrisMlirOpt, "--mlir-disable-threading", emitted, "--idr-target", "--idr-pipeline"]
                        ++ counter ++ options ++ ["-o", inWork e "skipped/lowered.mlir"]) out err
  accepted <- if not (succeeded lowered) then pure lowered else
    bounded e [e.tools.idrisMlir, inWork e "skipped/lowered.mlir", "--runtime=" ++ e.tools.checkedPrepared,
               "-o", inWork e "skipped/prog"] out err
  if not (succeeded accepted)
     then do
       shown <- firstLines 40 [inWork e "skipped.out", inWork e "skipped.err"]
       pure (Broken, (seedNamed seed ++ ": not accepted again") :: indented shown)
     else do
       names <- directoriesIn (fixture ++ "/cases")
       differ <- concat <$> for names (endsOtherwise e fixture)
       pure $ case differ of
         [] => (Held, [])
         _ => (Broken, [seedNamed seed ++ ": cases end otherwise:" ++ concatMap (" " ++) differ])
  where
    -- A case whose ending could not be read never ran, and is named already.
    endsOtherwise : Env -> String -> String -> IO (List String)
    endsOtherwise e fixture name = do
      let kept = inWork e ("case-runs/" ++ name)
      Just status <- readIfThere (kept ++ ".status")
        | Nothing => pure []
      let stdin = fixture ++ "/cases/" ++ name ++ "/stdin"
      input <- (\there => if there then FromFile stdin else NoInput) <$> exists stdin
      ran <- runProgram e "skipped-run" (inWork e "skipped/prog") input
      sameOut <- sameBytes e (inWork e "skipped-run.out") (kept ++ ".out")
      sameErr <- sameBytes e (inWork e "skipped-run.err") (kept ++ ".err")
      pure (if show (raw ran) == trailing status && sameOut && sameErr then [] else [name])

||| The refused program of FIXTURE, whose emitted module is MODULE (written
||| whatever the verdict, --emitted), lowered again from it with the drawn
||| skips, is refused again as its header says (Reject.idr), read off the
||| report idris-mlir-opt writes as idris-mlir does (--report): a refusal's
||| rule is the diagnostic's data, which only the report holds, and a
||| program the skips let through is reported accepted. Nothing when it
||| is; otherwise the lines of the comparison, under one naming the seed.
export
skipsRefuse : Env -> (fixture, emitted : String) -> IO ()
skipsRefuse e fixture emitted = do
  seed <- actionsSeed
  Just counter <- drawnSkips e seed
    | Nothing => tell e "skipped actions: idris-mlir-opt names no action tags"
  _ <- bounded e ([e.tools.idrisMlirOpt, "--mlir-disable-threading", emitted, "--idr-target", "--idr-pipeline"]
                  ++ counter ++ ["--report=" ++ inWork e "skipped.report", "-o", inWork e "skipped.mlir"])
                 (ToFile (inWork e "skipped.out")) (Apart (ToFile (inWork e "skipped.err")))
  output <- (++) <$> bytesIfThere (inWork e "skipped.out") <*> bytesIfThere (inWork e "skipped.err")
  (shown, holds) <- judged fixture (inWork e "skipped.report") output
  when (not holds) $ do
    tell e (seedNamed seed ++ ": not refused alike")
    tellAll e (indented shown)

------------------------------------------------------------------------------
-- Every compilation
------------------------------------------------------------------------------

||| What holds of every compilation, as one line: every function of the
||| emitted module MODULE is reached from its root by the symbols the
||| functions reached before it name, so the frontend writes no function
||| the program never calls (idr-expect's `reached`); the objects import
||| nothing a program may not; and the program, compiled again from MODULE
||| with a drawn set of the optimizations' actions skipped and OPTIONS, is
||| accepted and holds its cases again. One line, `universal: holds`, when
||| all hold; otherwise the lines of the checks. A check added to every
||| compilation is added here, and no transcript changes.
export
universal : Env -> (fixture, emitted : String) -> (options, objects : List String) -> IO Holds
universal e fixture emitted options objects = do
  let log = inWork e "universal.log"
  reached <- bounded e [e.tools.idrisMlirOpt, "--mlir-disable-threading", emitted, "--idr-expect=holds=reached", "-o", "/dev/null"]
                     (ToFile log) WithOutput
  reachedLines <- lines . fromMaybe "" <$> readIfThere log
  (imports, importLines) <- objectImports e objects
  seed <- actionsSeed
  (skips, skipLines) <- skipsHold e seed fixture emitted options
  case allHold [if succeeded reached then Held else Broken, imports, skips] of
    Held => do tell e "universal: holds"; pure Held
    Broken => do tellAll e (reachedLines ++ importLines ++ skipLines); pure Broken
