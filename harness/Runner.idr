-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The runner of the golden tests, with no threads: every test runs in a
||| process of its own (harness/one.sh), as many at once as asked,
||| through xargs. Test.Golden's runner trades tests and results between
||| Chez threads over channels, and a thread that dies (an exception while
||| it reads one test's output) or misses a wakeup leaves the others waiting
||| for ever, holding the tree's lock. Processes that end cannot do that.
module Runner

import Data.List
import Data.SortedSet
import Data.String
import System
import System.File

import Test.Golden

%default covering

||| A pool: its banner, and its runs, each with the name of its test's
||| kind, which harness/one.sh runs it by.
public export
record Pool where
  constructor MkPool
  name : String
  runs : List (String, String)

||| The non-empty lines of a file, or none when it does not exist.
linesOf : String -> IO (List String)
linesOf path = do
  Right text <- readFile path
    | Left _ => pure []
  pure (filter (/= "") (lines text))

banner : String -> String
banner name =
  let rule = pack (replicate 72 '-') in unlines ["", rule, name, rule]

||| The runs of one pool that the options select, each reported as it
||| ends; the verdicts go to `results`/passed and `results`/failed. The
||| runs selected are returned, so that the count is of what was asked,
||| not of what reported.
runPool : Options -> String -> String -> Pool -> IO (List String)
runPool opts root results pool = do
  let runs = filter (\(run, _) => elem run (filterTests opts [run])) pool.runs
  let (_ :: _) = runs
    | [] => pure []
  putStrLn (banner pool.name)
  fflush stdout
  Right () <- writeFile (results ++ "/tests") (unlines (map (\(run, kind) => kind ++ " " ++ run) runs))
    | Left err => die (show err)
  ignore $ system $ "xargs -P " ++ show opts.threads ++ " -n 2 sh " ++ escapeArg (root ++ "/harness/one.sh") ++ " "
                 ++ escapeArg results ++ " " ++ escapeArg (exeUnderTest opts)
                 ++ " < " ++ escapeArg (results ++ "/tests")
  pure (map fst runs)

||| Every pool in turn, then the number of tests that passed of those
||| selected, the tests the options select that do not run on this host
||| (`elsewhere`: their targets file names another), and the tests that
||| failed or gave no verdict at all (a run of harness/one.sh that
||| died before it wrote one). The exit status is 1 when any failed or gave
||| none, or when the options select no test at all.
export
runPools : Options -> (root : String) -> (elsewhere : List String) -> List Pool -> IO ()
runPools opts root elsewhere pools = do
  pid <- getPID
  let results = root ++ "/harness/build/results." ++ show pid
  ignore $ system $ "rm -rf " ++ escapeArg results ++ " && mkdir -p " ++ escapeArg results
  selected <- concat <$> traverse (runPool opts root results) pools
  passed <- linesOf (results ++ "/passed")
  failed <- linesOf (results ++ "/failed")
  ignore $ system $ "rm -rf " ++ escapeArg results
  let reported = SortedSet.fromList (passed ++ failed)
  let silent = filter (\t => not (contains t reported)) selected
  let notHere = filterTests opts elsewhere
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
