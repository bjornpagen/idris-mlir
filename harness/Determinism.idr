-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Determinism: the same program compiles to the same bytes whatever the
||| number of threads: one compilation at each of 1, 3, 5 and 13 threads,
||| one at a count drawn for the run, and one more at 13 in a second
||| process, byte for byte; each executable they made gives the same bytes
||| on every input; and one module through the pipeline under one thread
||| and under MLIR's pool.
module Determinism

import Data.List
import Data.Maybe
import Data.String
import System
import System.File

import Files
import Harness
import Serve

%default covering

||| The seed the drawn count comes from: IDRIS_MLIR_DETERMINISM_SEED,
||| which a failure names and which replays it, or the clock's seconds.
determinismSeed : IO Integer
determinismSeed = do
  given <- getEnv "IDRIS_MLIR_DETERMINISM_SEED"
  case given >>= parseInteger of
    Just seed => pure seed
    Nothing => time

||| The count drawn from the seed, from 2 to 31, never one of the counts
||| always tried, so that over many runs every split of the work is tried.
drawnCount : Integer -> Integer
drawnCount seed =
  let drawn = 2 + mod seed 30 in
  if drawn == 3 || drawn == 5 || drawn == 13 then drawn + 1 else drawn

||| The compilations every determinism check makes, by their thread counts:
||| 1 runs serially; 3, 5 and 13 are pairwise coprime, so no two of them
||| split a list of work at the same boundaries, and 13 is more threads
||| than a small program has functions, so some threads get none; then the
||| drawn count; the last, 13 again, is a second process, so nothing a
||| process draws when it starts (where its allocator places things)
||| reaches an artifact.
record Compilation where
  constructor MkCompilation
  number : Nat
  threads : Integer
  what : String

compilations : (drawn : Integer) -> List Compilation
compilations drawn =
  [ MkCompilation 1 1 "1 thread", MkCompilation 2 3 "3 threads", MkCompilation 3 5 "5 threads"
  , MkCompilation 4 13 "13 threads", MkCompilation 5 drawn "a drawn count of threads"
  , MkCompilation 6 13 "13 threads, a second process" ]

||| The same compilations in words, as the transcripts name them, the same
||| whatever count was drawn.
phrase : String
phrase = "1, 3, 5 and 13 threads, a drawn count and in a second process"

drawnLine : Integer -> Integer -> String
drawnLine drawn seed = "  the drawn count: " ++ show drawn ++ " threads (IDRIS_MLIR_DETERMINISM_SEED=" ++ show seed ++ ")"

stripPrefix' : String -> String -> String
stripPrefix' p s = if isPrefixOf p s then pack (drop (length p) (unpack s)) else s

||| `determinism FIXTURE [INPUT...]`: an IO program in Main.idr with the
||| installed packages its `packages` names, compiled by each of the
||| compilations, gives byte-identical artifacts of every kind, the module
||| the frontend emitted among them; and the executable of every
||| compilation, each run in a process of its own, prints the same bytes and
||| exits alike on every input: the stdin of each of the fixture's cases,
||| the empty input, and each INPUT, a line written to stdin. --num-threads
||| comes after the one tools/compile.sh passes, so it is the one that
||| counts. Every compilation runs in the one directory, so nothing differs
||| by where it ran, and its build is moved aside after it.
export
determinism : Env -> (fixture : String) -> (inputs : List String) -> IO ()
determinism e given inputs = do
  let fixture = absolute e given
  seed <- determinismSeed
  let drawn = drawnCount seed
  packages <- packageOptions fixture
  let det = inWork e "det"
  made e det
  _ <- copyFixture e fixture det
  Just built <- compileAll seed drawn packages det (compilations drawn)
    | Nothing => pure ()
  for_ artifactKinds $ \kind => do
    files <- for built $ \n => artifactFiles (inWork e ("det" ++ show n)) (Named "prog") kind
    if any isNil files then tell e (kindName kind ++ ": missing") else do
      let names = zipWith (\n, fs => map (stripPrefix' (inWork e ("det" ++ show n) ++ "/")) fs) built files
      let first = fromMaybe [] (head' names)
      same <- for (zip built names) $ \(n, ns) => do
        bytes <- for first $ \name => sameBytes e (inWork e ("det1/" ++ name)) (inWork e ("det" ++ show n ++ "/" ++ name))
        pure (ns == first && all id bytes)
      if all id same
         then tell e (kindName kind ++ ": identical at " ++ phrase)
         else do
           tell e (kindName kind ++ ": differs at " ++ phrase)
           tell e (drawnLine drawn seed)
  -- The runs: each input, to each compilation's executable.
  let inputDir = inWork e "inputs"
  made e inputDir
  ignore (writeFile (inputDir ++ "/empty") "")
  caseNames <- directoriesIn (fixture ++ "/cases")
  for_ caseNames $ \c => do
    let stdin = fixture ++ "/cases/" ++ c ++ "/stdin"
    when !(exists stdin) $
      ignore (bounded e ["cp", stdin, inputDir ++ "/case-" ++ c] (ToFile "/dev/null") (Apart ToCaller))
  for_ (zip [1 .. length inputs] inputs) $ \(n, input) =>
    ignore (writeFile (inputDir ++ "/given-" ++ show n) (input ++ "\n"))
  differ <- concat <$> (for !(visibleIn inputDir) $ \input => runs built (inputDir ++ "/" ++ input) input)
  case differ of
    [] => tell e "runs: every executable prints the same bytes and exits alike on each input"
    _ => tell e ("runs: the executables differ in what they print or how they exit on:" ++ concat differ)
  where
    compileAll : Integer -> Integer -> List String -> String -> List Compilation -> IO (Maybe (List Nat))
    compileAll _ _ _ _ [] = pure (Just [])
    compileAll seed drawn packages det (c :: rest) = do
      removed e (det ++ "/build")
      compiled <- compileProgram e (packages ++ ["--num-threads=" ++ show c.threads]) (det ++ "/Main.idr") "prog"
      tell e ("compile at " ++ c.what ++ ": exit " ++ show (raw compiled))
      if not (succeeded compiled)
         then do
           when (c.number == 5) $ tell e (drawnLine c.threads seed)
           showIn e [inWork e "compile.out", inWork e "compile.err"]
           pure Nothing
         else do
           let aside = inWork e ("det" ++ show c.number)
           made e aside
           ignore (bounded e ["mv", det ++ "/build", aside ++ "/build"] (ToFile "/dev/null") (Apart ToCaller))
           map (c.number ::) <$> compileAll seed drawn packages det rest

    -- Each compilation's executable on the input, held to the first's.
    runs : List Nat -> String -> String -> IO (List String)
    runs built path input = do
      outcomes <- for built $ \n => do
        exe <- fromMaybe "" <$> artifactFile (inWork e ("det" ++ show n)) (Named "prog") Executable
        status <- runProgram e ("run" ++ show n) exe (FromFile path)
        pure (n, raw status)
      case outcomes of
        [] => pure []
        ((first, firstStatus) :: rest) =>
          concat <$> for rest (\(n, status) => do
            sameOut <- sameBytes e (inWork e ("run" ++ show first ++ ".out")) (inWork e ("run" ++ show n ++ ".out"))
            pure (if sameOut && status == firstStatus then [] else [" " ++ input ++ " (compilation " ++ show n ++ ")"]))

||| The text of a pass report's standard error split where its statistics
||| start, at its first `===` line: the remarks before it, as they are
||| emitted, and the statistics, printed when the pipeline ends.
remarksAndStatistics : String -> (String, String)
remarksAndStatistics text =
  let (remarks, stats) = break (isPrefixOf "===") (lines text) in
  (concatMap (++ "\n") remarks, concatMap (++ "\n") stats)

||| `determinism_threads FIXTURE`: the module the fixture's program hands
||| the driver, through idris-mlir-opt's idr-pipeline under one thread and
||| under MLIR's pool, and under the pool again: the same module, byte for
||| byte with its locations, the same statistics, and the same remarks
||| (through the diagnostic engine, which orders what a pass says of each
||| function by the function, whichever thread ran it). With threading on,
||| MLIR hands a nested pipeline's work to the pool's threads even when the
||| pool has one, so per-thread state shows on any host. The remarks and the
||| statistics stay in the work directory's one.remarks and one.stats, and
||| so on, for the test to read.
export
determinismThreads : Env -> (fixture : String) -> IO ()
determinismThreads e given = do
  let fixture = absolute e given
  let det = inWork e "det"
  made e det
  _ <- copyFixture e fixture det
  packages <- packageOptions fixture
  compiled <- compileProgram e packages (det ++ "/Main.idr") "prog"
  tell e ("compile: exit " ++ show (raw compiled))
  if not (succeeded compiled) then showIn e [inWork e "compile.out", inWork e "compile.err"] else do
    input <- fromMaybe "" <$> artifactFile det (Named "prog") Module
    Held <- pipelines input ["one", "many", "again"]
      | Broken => pure ()
    same "one.mlir" "many.mlir" "module: identical under one thread and under many" "module: differs between one thread and many"
    same "many.mlir" "again.mlir" "module: identical under many, again" "module: differs between two runs under many"
    same "one.stats" "many.stats" "statistics: identical under one thread and under many" "statistics: differ between one thread and many"
    alike <- sameBytes e (inWork e "one.remarks") (inWork e "many.remarks")
    if alike then tell e "remarks: identical under one thread and under many" else do
      tell e "remarks: differ between one thread and many"
      tellAll e !(differences e (inWork e "one.remarks") (inWork e "many.remarks"))
  where
    same : (a, b, yes, no : String) -> IO ()
    same a b yes no = do
      alike <- sameBytes e (inWork e a) (inWork e b)
      tell e (if alike then yes else no)

    pipelines : String -> List String -> IO Holds
    pipelines _ [] = pure Held
    pipelines input (run :: rest) = do
      let threading = if run == "one" then ["--mlir-disable-threading"] else []
      status <- bounded e ([e.tools.idrisMlirOpt] ++ threading
                           ++ ["--mlir-print-debuginfo", "--mlir-pass-statistics", "--mlir-pass-statistics-display=list",
                               "--remarks-filter=.*", "--idr-pipeline", input, "-o", inWork e (run ++ ".mlir")])
                        ToCaller (Apart (ToFile (inWork e (run ++ ".err"))))
      if not (succeeded status)
         then do
           tell e (run ++ ": exit " ++ show (raw status))
           showIn e [inWork e (run ++ ".err")]
           pure Broken
         else do
           let (remarks, stats) = remarksAndStatistics (fromMaybe "" !(readIfThere (inWork e (run ++ ".err"))))
           ignore (writeFile (inWork e (run ++ ".remarks")) remarks)
           ignore (writeFile (inWork e (run ++ ".stats")) stats)
           pipelines input rest
