||| The golden test runner, on Idris's
||| own `Test.Golden`, as third_party/Idris2/tests/Main.idr.
|||
||| A test is a directory with a POSIX-sh `run` script and an `expected`
||| file. The runner (Runner.idr, each test in a process of its own) calls
||| `./run` in that directory with the idris-mlir
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
||| With `--list`, it prints each pool's tests instead of running them. A
||| pool's directories are found with `testsInDir`; one that does not exist,
||| or holds no test yet, adds none.
|||
||| It also answers the `run` scripts that need Idris:
|||
|||     runtests --sem-program <name>   the program of a semantics test
|||     runtests --sem-expected <name>  the stdout its program must print
|||     runtests --sem-list             the names of the semantics tests
|||     runtests --fuzz-program <seed> <cases> runtime|static
|||                                     a program of the fuzzer (Fuzz.idr)
|||     runtests --two-levels-program primitives|prelude terms|main
|||                                     a module of the two levels (TwoLevels.idr)
|||     runtests --lock                 the check of toolchain.lock.json
module Main

import Data.List
import Data.Maybe
import Data.String
import System
import System.Directory
import System.File
import System.Info
import System.Path

import Test.Golden

import Fuzz
import Lock
import Runner
import Sem
import TwoLevels

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

||| The operating system a test's `targets` file names, from the compiler
||| that built this runner (darwin, linux, ...); `macos` for darwin.
hostOs : String
hostOs = case System.Info.os of
  "darwin" => "macos"
  other => other

||| The architecture a `targets` file names, from IDRIS_MLIR_HOST_ARCH
||| (the Makefile exports uname -m; a run script invoked directly gets the
||| same fallback from tests/testutils.sh).
hostArch : String -> String
hostArch raw = case raw of
  "x86_64" => "x86-64"
  "amd64" => "x86-64"
  "arm64" => "aarch64"
  "aarch64" => "aarch64"
  other => other

||| The names this host answers to in a `targets` file: its architecture
||| and its operating system. A host whose architecture cannot be read
||| (IDRIS_MLIR_HOST_ARCH unset) answers to its operating system alone.
hostNames : IO (List String)
hostNames = do
  Just raw <- getEnv "IDRIS_MLIR_HOST_ARCH"
    | Nothing => pure [hostOs]
  pure (hostArch raw :: [hostOs])

||| Whether TEST runs here. A test with no `targets` file holds everywhere;
||| one with a `targets` file holds only where it names one of this host's
||| names, which is how an x86-only, arm64-only or Linux-only test runs
||| where it holds and is not counted elsewhere.
runsHere : List String -> String -> IO Bool
runsHere names test = do
  Right text <- readFile (test ++ "/targets")
    | Left _ => pure True
  pure (any (\word => word `elem` names) (words text))

||| The tests of TESTS that run here.
applicableTests : List String -> List String -> IO (List String)
applicableTests names tests = do
  flags <- traverse (runsHere names) tests
  pure (map fst (filter snd (zip tests flags)))

||| The tests of the directories that hold any, found by `testsInDir`, as
||| one pool. A directory that does not exist yet has no tests.
pool : String -> List String -> IO TestPool
pool name dirs = do
  names <- hostNames
  found <- for dirs $ \dir =>
    if !(holdsTests dir)
       then applicableTests names !(map testCases (testsInDir dir name))
       else pure []
  pure (MkTestPool name [] Test.Golden.Nothing (sort (concat found)))

||| One pool per subdirectory of a tree, each named after its directory.
subpools : String -> String -> IO (List TestPool)
subpools tree description = do
  dirs <- subdirs tree
  for dirs $ \dir => pool (dir ++ ": " ++ description) [dir]

||| The make target that runs each pool. The program topics under
||| `programs/` are listed with a line each, as upstream Idris's tests are.
suites : List (String, IO (List TestPool))
suites =
  [ ("check", sequence
      [ pool "spec: the repository: pins, commands, toolchain, source rules" ["spec"]
      ])
  , ("test", sequence
      [ pool "compiler: Idris-side units and artifact rules" ["compiler"]
      , pool "accept: programs the profile accepts" ["accept"]
      , pool "reject: programs rejected with a named rule" ["reject"]
      , pool "programs/semantics: the meaning of primitives, matches and crashes" ["programs/semantics"]
      , pool "programs/basic: language features" ["programs/basic"]
      , pool "programs/io: input and output through the Prelude, System.File, System.Info and Buffer" ["programs/io"]
      , pool "programs/prelude: the Prelude and base over strings, lists and doubles" ["programs/prelude"]
      , pool "programs/interfaces: interfaces resolved at compile time" ["programs/interfaces"]
      , pool "programs/eval: compile-time evaluation and specialization" ["programs/eval"]
      , pool "programs/partial: partial functions, crashes and the stack" ["programs/partial"]
      , pool "programs/stack: loops through calls in tail position in constant stack on long inputs, and recursions a million calls deep" ["programs/stack"]
      , pool "programs/nat: natural numbers" ["programs/nat"]
      , pool "programs/data: data and records at runtime" ["programs/data"]
      , pool "programs/linear: linear values and the linear library's lists" ["programs/linear"]
      , pool "programs/arrays: linear arrays, IOArray and Buffer" ["programs/arrays"]
      , pool "determinism: byte-identical artifacts" ["determinism"]
      , pool "registry: privileged knowledge of library definitions" ["registry"]
      , pool "toolchain: the pinned toolchain and what it builds" ["toolchain"]
      , pool "fuzz: closed expressions over every primitive, each written three ways, against their recorded values" ["fuzz"]
      , pool "two levels: closed terms over every primitive and the Prelude, compiled, against their recorded values" ["two-levels"]
      , pool "bench: every benchmark builds and prints its recorded output" ["bench"]
      ])
  , ("test-idr", subpools "idr" "the idr dialect and its passes")
  , ("test-mlir-tools", sequence
      [ pool "upstream: each bug of upstream/ on its reproducer, with the pinned (patched) tools" ["upstream"] ])
  ]

||| The repository root: IDRIS_MLIR_ROOT, or the parent of `tests/`.
root : IO String
root = do
  Nothing <- getEnv "IDRIS_MLIR_ROOT"
    | Just r => pure r
  Just here <- currentDir
    | Nothing => die "the current directory is unknown"
  pure (fromMaybe here (parent here))

||| `--suite NAME`, `--list` and the other arguments.
takeOwn : List String -> (Maybe String, Bool, List String)
takeOwn ("--suite" :: name :: rest) = let (_, list, others) = takeOwn rest in (Just name, list, others)
takeOwn ("--list" :: rest) = let (suite, _, others) = takeOwn rest in (suite, True, others)
takeOwn (arg :: rest) = let (suite, list, others) = takeOwn rest in (suite, list, arg :: others)
takeOwn [] = (Nothing, False, [])

runnerUsage : String
runnerUsage = unlines
  [ "usage: runtests <idris-mlir> [--suite " ++ joinBy "|" (map fst suites) ++ "] [--list] [Test.Golden options]"
  , "       runtests --sem-program <name> | --sem-expected <name> | --sem-list | --lock"
  , "       runtests --fuzz-program <seed> <cases> runtime|static"
  , "       runtests --two-levels-program primitives|prelude terms|main"
  , Test.Golden.usage
  ]

||| The pools of a suite, or of all of them.
suitePools : Maybe String -> IO (List TestPool)
suitePools Nothing = concat <$> sequence (map snd suites)
suitePools (Just s) =
  maybe (die ("unknown suite " ++ s ++ "\n" ++ runnerUsage)) id (lookup s suites)

||| The tests each pool would run, without running them.
listPools : Options -> List TestPool -> IO ()
listPools opts pools = for_ pools $ \p => do
  let tests = filterTests opts (testCases p)
  putStrLn (poolName p ++ ": " ++ show (length tests))
  traverse_ (putStrLn . ("  " ++)) tests

runSuites : String -> List String -> IO ()
runSuites prog args = do
  let (suite, listing, rest) = takeOwn args
  Just opts <- options (prog :: rest)
    | Nothing => die runnerUsage
  r <- root
  ignore $ setEnv "IDRIS_MLIR_ROOT" r True
  pools <- suitePools suite
  -- Run anywhere but tests/, the pools are empty; that must not pass.
  when (all (null . testCases) pools) $
    die "no tests found: run the runner in tests/, through make"
  -- Accepting new output asks at each failure, one test at a time, which
  -- only Test.Golden's runner does.
  if listing then listPools opts pools
    else if opts.interactive then runnerWith opts pools
    else runPools opts pools

main : IO ()
main = do
  args <- getArgs
  case drop 1 args of
    ["--sem-program", name] =>
      maybe (die ("no semantics test " ++ name)) putStr (programOf name)
    ["--sem-expected", name] =>
      maybe (die ("no semantics test " ++ name)) putStr (expectedOf name)
    ["--sem-list"] => traverse_ putStrLn names
    ("--fuzz-program" :: fuzz) =>
      maybe (die "usage: runtests --fuzz-program <seed> <cases> runtime|static") putStr
            (Fuzz.programOf fuzz)
    ("--two-levels-program" :: which) =>
      maybe (die "usage: runtests --two-levels-program primitives|prelude terms|main") putStr
            (TwoLevels.programOf which)
    ["--lock"] => Lock.check !root
    rest => runSuites (fromMaybe "runtests" (head' args)) rest
