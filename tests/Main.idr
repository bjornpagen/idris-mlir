||| The golden test runner (docs/plan.md section 9; TEST-CMD-1), on Idris's
||| own `Test.Golden`, as third_party/Idris2/tests/Main.idr.
|||
||| A test is a directory with a POSIX-sh `run` script and an `expected`
||| file. The runner calls `./run` in that directory with the idris-mlir
||| under test as `$1` and IDRIS_MLIR_ROOT set to the repository root, and
||| compares its stdout with `expected`. `run` prints the exit status of what
||| it runs and the artifacts that must exist, so every test checks both by
||| construction. `tests/testutils.sh` holds what the scripts share.
|||
||| Run from `tests/`, by make (`make check`, `make test`, `make test-idr`,
||| `make test-mlir-tools`):
|||
|||     runtests <idris-mlir> [--suite check|test|test-idr|test-mlir-tools]
|||              [--threads N] [--only NAMES] [--except NAMES] [--interactive]
|||
||| It also answers the `run` scripts that need Idris:
|||
|||     runtests --sem-program <name>   the program of a TEST-SEM-1 test
|||     runtests --sem-list             the names of the TEST-SEM-1 tests
|||     runtests --spec <check>         a TEST-SPEC-1 check (Spec.idr)
|||     runtests --lock                 the check of toolchain.lock.json
module Main

import Data.List
import Data.Maybe
import Data.String
import System
import System.Directory
import System.File
import System.Path

import Test.Golden

import Lock
import Sem
import Spec

%default covering

isDirectory : String -> IO Bool
isDirectory path = do
  Right d <- openDir path
    | Left _ => pure False
  closeDir d
  pure True

||| The subdirectories of a directory, sorted.
subdirs : String -> IO (List String)
subdirs dir = do
  Right names <- listDir dir
    | Left _ => pure []
  found <- for (sort names) $ \n => do
    let path = dir ++ "/" ++ n
    pure (if !(isDirectory path) then [path] else [])
  pure (concat found)

||| Whether a directory holds a test: a subdirectory with a `run` script.
holdsTests : String -> IO Bool
holdsTests dir = do
  found <- for !(subdirs dir) $ \d => exists (d ++ "/run")
  pure (any id found)

||| The tests of the directories that hold any, found by `testsInDir`, as
||| one pool. A directory that does not exist yet has no tests.
pool : String -> List String -> IO TestPool
pool name dirs = do
  found <- for dirs $ \dir =>
    if !(holdsTests dir)
       then map testCases (testsInDir dir name)
       else pure []
  pure (MkTestPool name [] Test.Golden.Nothing (sort (concat found)))

||| A pool over every version directory of a tree: `e2e/v0`, `e2e/v1`, ...
versioned : String -> String -> (String -> String) -> IO TestPool
versioned name tree inside = pool name . map inside =<< subdirs tree

||| The make target that runs each pool.
suites : List (String, List (IO TestPool))
suites =
  [ ("check",
      [ pool "spec: rule identifiers against the tests (TEST-SPEC-1)" ["spec"]
      , pool "toolchain: pins, commands and repository rules" ["toolchain"]
      ])
  , ("test",
      [ pool "compiler: Idris-side units and artifact rules" ["compiler"]
      , versioned "accept: profile fixtures that compile (TEST-ACC-1)" "profile" (++ "/accept")
      , versioned "reject: profile fixtures that are rejected (TEST-REJ-1)" "profile" (++ "/reject")
      , versioned "e2e: programs against their oracles and Chez" "e2e" id
      , pool "determinism: byte-identical artifacts (TEST-DET-1)" ["determinism"]
      , pool "registry: privileged knowledge of library definitions" ["registry"]
      ])
  , ("test-idr",
      [ versioned "dialect: the idr dialect and its passes (TEST-IDR-1)" "idr" id ])
  , ("test-mlir-tools",
      [ pool "pipeline: the pinned upstream MLIR tools" ["mlir"] ])
  ]

||| The repository root: IDRIS_MLIR_ROOT, or the parent of `tests/`.
root : IO String
root = do
  Nothing <- getEnv "IDRIS_MLIR_ROOT"
    | Just r => pure r
  Just here <- currentDir
    | Nothing => die "the current directory is unknown"
  pure (fromMaybe here (parent here))

||| `--suite NAME` and the other arguments.
takeSuite : List String -> (Maybe String, List String)
takeSuite ("--suite" :: name :: rest) = let (_, others) = takeSuite rest in (Just name, others)
takeSuite (arg :: rest) = let (suite, others) = takeSuite rest in (suite, arg :: others)
takeSuite [] = (Nothing, [])

runnerUsage : String
runnerUsage = unlines
  [ "usage: runtests <idris-mlir> [--suite " ++ joinBy "|" (map fst suites) ++ "] [Test.Golden options]"
  , "       runtests --sem-program <name> | --sem-list | --spec <check> | --lock"
  , Test.Golden.usage
  ]

runSuites : String -> List String -> IO ()
runSuites prog args = do
  let (suite, rest) = takeSuite args
  Just opts <- options (prog :: rest)
    | Nothing => die runnerUsage
  r <- root
  ignore $ setEnv "IDRIS_MLIR_ROOT" r True
  chosen <- case suite of
    Nothing => pure (concatMap snd suites)
    Just s => maybe (die ("unknown suite " ++ s ++ "\n" ++ runnerUsage)) pure (lookup s suites)
  pools <- sequence chosen
  -- Run anywhere but tests/, the pools are empty; that must not pass.
  when (all (null . testCases) pools) $
    die "no tests found: run the runner in tests/, through make"
  runnerWith opts pools

main : IO ()
main = do
  args <- getArgs
  case drop 1 args of
    ["--sem-program", name] =>
      maybe (die ("no TEST-SEM-1 test " ++ name)) putStr (programOf name)
    ["--sem-list"] => traverse_ putStrLn names
    ["--spec", name] => Spec.check !root name
    ["--lock"] => Lock.check !root
    rest => runSuites (fromMaybe "runtests" (head' args)) rest
