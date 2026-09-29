||| The runner of the golden tests, with no threads: every test runs in a
||| process of its own (tests/runner/one.sh), as many at once as asked,
||| through xargs. Test.Golden's runner trades tests and results between
||| Chez threads over channels, and a thread that dies (an exception while
||| it reads one test's output) or misses a wakeup leaves the others waiting
||| for ever, holding the tree's lock. Processes that end cannot do that.
module Runner

import Data.List
import Data.String
import System
import System.File

import Test.Golden

%default covering

||| The non-empty lines of a file, or none when it does not exist.
linesOf : String -> IO (List String)
linesOf path = do
  Right text <- readFile path
    | Left _ => pure []
  pure (filter (/= "") (lines text))

banner : String -> String
banner name =
  let rule = pack (replicate 72 '-') in unlines ["", rule, name, rule]

||| The tests of one pool that the options select, each reported as it
||| ends; the verdicts go to `results`/passed and `results`/failed.
runPool : Options -> String -> TestPool -> IO ()
runPool opts results pool = do
  let tests = filterTests opts (testCases pool)
  let (_ :: _) = tests
    | [] => pure ()
  putStrLn (banner pool.poolName)
  fflush stdout
  Right () <- writeFile (results ++ "/tests") (unlines tests)
    | Left err => die (show err)
  ignore $ system $ "xargs -P " ++ show opts.threads ++ " -n 1 sh runner/one.sh "
                 ++ escapeArg results ++ " " ++ escapeArg (exeUnderTest opts)
                 ++ " < " ++ escapeArg (results ++ "/tests")

||| Every pool in turn, then the number of tests that passed and the list
||| of those that failed; the exit status is 1 when any failed.
export
runPools : Options -> List TestPool -> IO ()
runPools opts pools = do
  pid <- getPID
  let results = "build/results." ++ show pid
  ignore $ system $ "rm -rf " ++ escapeArg results ++ " && mkdir -p " ++ escapeArg results
  traverse_ (runPool opts results) pools
  passed <- linesOf (results ++ "/passed")
  failed <- linesOf (results ++ "/failed")
  ignore $ system $ "rm -rf " ++ escapeArg results
  putStrLn (show (length passed) ++ "/" ++ show (length passed + length failed)
            ++ " tests successful")
  when (not (null failed)) $ do
    putStrLn "Failing tests:"
    putStr (unlines (sort failed))
  if null failed then exitSuccess else exitFailure
