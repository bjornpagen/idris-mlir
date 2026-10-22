-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The runner's two halves around the runs, which harness/runs.sh makes:
||| the plan, which writes the pools of runs the options select, and the
||| tally, which reads their verdicts back. Every test runs in a process of
||| its own (harness/one.sh), as many at once as asked, through xargs: the
||| runner itself creates no process, so it builds and runs under both
||| hosts, idris-mlir among them, which refuses process creation.
|||
||| The plan's directory holds `threads`, `selected` (every run the options
||| select, one per line), `elsewhere` (those whose targets file names no
||| name of this host), and per pool `pool.<n>.banner` and `pool.<n>.runs`
||| (`<kind> <run>` per line), n from 1 in the order the pools run. Each
||| run's verdict (Verdict.idr) appends its name to `passed` or `failed`
||| there.
module Runner

import Data.List
import Data.Maybe
import Data.SortedSet
import Data.String
import System
import System.File

import Files

%default covering

||| A pool: its banner, and its runs, each with the name of its test's
||| kind, which harness/one.sh runs it by.
public export
record Pool where
  constructor MkPool
  name : String
  runs : List (String, String)

writeOrDie : String -> String -> IO ()
writeOrDie path text = do
  Right () <- writeFile path text
    | Left err => die (path ++ ": " ++ show err)
  pure ()

banner : String -> String
banner name =
  let rule = pack (replicate 72 '-') in unlines ["", rule, name, rule]

||| Writes the plan of the selected runs in `results`: the pools, those with
||| no run left out, the runs not run here, and the threads to run them on.
export
writePlan : (results : String) -> (threads : Nat) -> (elsewhere : List String) -> List Pool -> IO ()
writePlan results threads elsewhere pools = do
  let chosen = filter (not . null . (.runs)) pools
  writeOrDie (results ++ "/threads") (show threads ++ "\n")
  writeOrDie (results ++ "/selected") (unlines (chosen >>= map fst . (.runs)))
  writeOrDie (results ++ "/elsewhere") (unlines elsewhere)
  for_ (zip [1 .. length chosen] chosen) $ \(n, pool) => do
    writeOrDie (results ++ "/pool." ++ show n ++ ".banner") (banner pool.name)
    writeOrDie (results ++ "/pool." ++ show n ++ ".runs")
               (unlines (map (\(run, kind) => kind ++ " " ++ run) pool.runs))

||| The non-empty lines of a file, or none when it does not exist.
linesOf : String -> IO (List String)
linesOf path = do
  text <- readIfThere path
  pure (filter (/= "") (lines (fromMaybe "" text)))

||| The number of the runs selected that passed, the runs not run on this
||| host (`elsewhere`: their targets file names another), and the runs that
||| failed or gave no verdict at all (a run of harness/one.sh that died
||| before it wrote one). The exit status is 1 when any failed or gave none,
||| or when the options selected no run at all.
export
tally : (results : String) -> IO ()
tally results = do
  selected <- linesOf (results ++ "/selected")
  passed <- linesOf (results ++ "/passed")
  failed <- linesOf (results ++ "/failed")
  notHere <- linesOf (results ++ "/elsewhere")
  let reported = SortedSet.fromList (passed ++ failed)
  let silent = filter (\t => not (contains t reported)) selected
  -- A selection that names no test, a misspelt `only` among them, ran
  -- nothing, which is no pass.
  when (null selected && null notHere) $ do
    putStrLn "no test matches the selection"
    exitFailure
  putStrLn (show (length passed) ++ "/" ++ show (length selected) ++ " tests successful")
  when (not (null notHere)) $ do
    putStrLn (show (length notHere) ++ " not run on this host, whose names their targets file does not list:")
    putStr (unlines notHere)
  when (not (null failed)) $ do
    putStrLn "Failing tests:"
    putStr (unlines (sort failed))
  when (not (null silent)) $ do
    putStrLn "Tests that gave no verdict:"
    putStr (unlines (sort silent))
  if null failed && null silent then exitSuccess else exitFailure
