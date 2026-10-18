-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
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
||| A pool's directories are found with `testsInDir`; one that does not
||| exist, or holds no test yet, adds none.
|||
||| A test is a directory, or a directory and one parameter: a directory
||| `parameterized` names runs once per parameter, as `<dir>@<parameter>`,
||| its run script given the parameter as `$2` (tests/runner/one.sh).
|||
||| It also answers the `run` scripts that need Idris:
|||
|||     runtests --sem-program <name>   the program of a semantics test
|||     runtests --sem-expected <name>  the stdout its program must print
|||     runtests --fuzz-program program|threads|tape|replay|shrink|two-hosts ...
|||                                     a program or a case of the fuzzer (Fuzz.idr)
|||     runtests --fuzz-check overran|agree|model|first <request> [<stdout-file>]
|||                                     what a fuzzer program printed, checked (Fuzz.idr)
|||     runtests --two-levels-program primitives|prelude terms|main
|||                                     a module of the two levels (TwoLevels.idr)
|||     runtests --two-levels-check primitives|prelude <stdout-file> <expected-file>
|||                                     what a two-levels program printed, checked
|||     runtests --lock                 the check of toolchain.lock.json
module Main

import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet
import Data.String
import System
import System.Directory
import System.File
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
  pure (join found)

||| Whether a directory holds a test: a subdirectory with a `run` script.
holdsTests : String -> IO Bool
holdsTests dir = do
  found <- for !(subdirs dir) $ \d => exists (d ++ "/run")
  pure (any id found)

||| The names this host answers to in a `targets` file: its architecture
||| and its operating system, as tools/host.sh names them and the Makefile
||| exports them (IDRIS_MLIR_HOST_NAMES). Without them a test with a
||| `targets` file could run nowhere unnoticed, so the runner refuses to
||| start.
hostNames : IO (SortedSet String)
hostNames = do
  Just names <- getEnv "IDRIS_MLIR_HOST_NAMES"
    | Nothing => do
        putStrLn "tests: IDRIS_MLIR_HOST_NAMES is unset; run the tests through make"
        exitWith (ExitFailure 2)
  pure (fromList (words names))

||| Whether TEST runs here. A test with no `targets` file holds everywhere;
||| one with a `targets` file holds only where it names one of this host's
||| names, which is how an x86-only, arm64-only or Linux-only test runs
||| where it holds and is not counted elsewhere.
runsHere : SortedSet String -> String -> IO Bool
runsHere names test = do
  Right text <- readFile (test ++ "/targets")
    | Left _ => pure True
  pure (any (\word => contains word names) (words text))

||| The tests of TESTS that run here.
applicableTests : SortedSet String -> List String -> IO (List String)
applicableTests names tests = do
  flags <- traverse (runsHere names) tests
  pure (map fst (filter snd (zip tests flags)))

||| A test: a directory, or a directory and the one parameter its run
||| script is given.
data Entry = Plain String | Instance String String

||| A test's name, as `--only` selects it, as the runner hands it to
||| tests/runner/one.sh and as its verdict names it: `<dir>`, or
||| `<dir>@<parameter>`, which one.sh splits at its first `@`.
entryName : Entry -> String
entryName (Plain dir) = dir
entryName (Instance dir parameter) = dir ++ "@" ++ parameter

||| The directories that run once per parameter, with their parameters:
||| the semantics fixture once per test of Sem's table.
parameterized : SortedMap String (List String)
parameterized = fromList [("programs/semantics/prim", Sem.names)]

||| A directory's tests: one per parameter, or the directory itself.
entriesOf : String -> List Entry
entriesOf dir = case lookup dir parameterized of
  Just values => map (Instance dir) values
  Nothing => [Plain dir]

||| A pool: its name and its tests.
record Pool where
  constructor MkPool
  name : String
  entries : List Entry

||| A pool as Test.Golden's options select from it and the runner runs it.
golden : Pool -> TestPool
golden p = MkTestPool p.name [] Test.Golden.Nothing (map entryName p.entries)

||| The tests of the directories that hold any, found by `testsInDir`, as
||| one pool. A directory that does not exist yet has no tests.
pool : String -> List String -> IO Pool
pool name dirs = do
  names <- hostNames
  found <- for dirs $ \dir =>
    if !(holdsTests dir)
       then applicableTests names !(map testCases (testsInDir dir name))
       else pure []
  pure (MkPool name (sortBy (comparing entryName) (join found >>= entriesOf)))

||| One pool per subdirectory of a tree, each named after its directory.
subpools : String -> String -> IO (List Pool)
subpools tree description = do
  dirs <- subdirs tree
  for dirs $ \dir => pool (dir ++ ": " ++ description) [dir]

||| The make target that runs each pool. The program topics under
||| `programs/` are listed with a line each, as upstream Idris's tests are.
suites : List (String, IO (List Pool))
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
      , pool "programs/io: input and output through the Prelude, System, System.File, System.Directory, System.Clock, System.Info and Buffer" ["programs/io"]
      , pool "programs/prelude: the Prelude and base over strings, lists and doubles" ["programs/prelude"]
      , pool "programs/interfaces: interfaces resolved at compile time" ["programs/interfaces"]
      , pool "programs/eval: closed calls, specialization and arity raising" ["programs/eval"]
      , pool "programs/partial: partial functions, crashes and the stack" ["programs/partial"]
      , pool "programs/stack: loops through calls in tail position in constant stack on long inputs, and recursions a million calls deep" ["programs/stack"]
      , pool "programs/nat: natural numbers" ["programs/nat"]
      , pool "programs/data: data and records at runtime" ["programs/data"]
      , pool "programs/linear: linear values, the linear library's lists and its string iterator" ["programs/linear"]
      , pool "programs/arrays: typed arrays and growable linear vectors (libs/mlir-array), IOArray, IORef, ST and Buffer" ["programs/arrays"]
      , pool "determinism: byte-identical artifacts" ["determinism"]
      , pool "registry: privileged knowledge of library definitions" ["registry"]
      , pool "toolchain: the pinned toolchain and what it builds" ["toolchain"]
      , pool "fuzz: closed expressions over every primitive, each written four ways, held to each other and to the integers' documented meaning; Gen and its users on both hosts" ["fuzz"]
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

||| `--suite NAME` and the other arguments.
takeOwn : List String -> (Maybe String, List String)
takeOwn ("--suite" :: name :: rest) = let (_, others) = takeOwn rest in (Just name, others)
takeOwn (arg :: rest) = let (suite, others) = takeOwn rest in (suite, arg :: others)
takeOwn [] = (Nothing, [])

fuzzCheckUsage : String
fuzzCheckUsage = "runtests --fuzz-check overran|agree|model|first program <seed> <cases> <part> | replay <tape> <part> [<stdout-file>]"

twoLevelsCheckUsage : String
twoLevelsCheckUsage = "runtests --two-levels-check primitives|prelude <stdout-file> <expected-file>"

runnerUsage : String
runnerUsage = unlines
  [ "usage: runtests <idris-mlir> [--suite " ++ joinBy "|" (map fst suites) ++ "] [Test.Golden options]"
  , "       runtests --sem-program <name> | --sem-expected <name> | --lock"
  , "       runtests --fuzz-program program|threads|tape|replay|shrink|two-hosts ..."
  , "       " ++ fuzzCheckUsage
  , "       runtests --two-levels-program primitives|prelude terms|main"
  , "       " ++ twoLevelsCheckUsage
  , Test.Golden.usage
  ]

||| The pools of a suite, or of all of them.
suitePools : Maybe String -> IO (List Pool)
suitePools Nothing = join <$> sequence (map snd suites)
suitePools (Just s) =
  maybe (die ("unknown suite " ++ s ++ "\n" ++ runnerUsage)) id (lookup s suites)

runSuites : String -> List String -> IO ()
runSuites prog args = do
  let (suite, rest) = takeOwn args
  Just opts <- options (prog :: rest)
    | Nothing => die runnerUsage
  r <- root
  ignore $ setEnv "IDRIS_MLIR_ROOT" r True
  pools <- suitePools suite
  -- Run anywhere but tests/, the pools are empty; that must not pass.
  when (all (null . (.entries)) pools) $
    die "no tests found: run the runner in tests/, through make"
  -- Accepting new output asks at each failure, one test at a time, which
  -- only Test.Golden's runner does; it runs a directory's script with no
  -- parameter, so a test of a parameterized directory is not one it can
  -- run: essential.
  if opts.interactive
     then case instanceIn (filter (selected opts) (pools >>= (.entries))) of
       Just name => die (name ++ " runs with a parameter, which --interactive cannot give; run it without --interactive")
       Nothing => runnerWith opts (map golden pools)
     else runPools opts (map golden pools)
  where
    selected : Options -> Entry -> Bool
    selected opts e = not (null (filterTests opts [entryName e]))
    instanceIn : List Entry -> Maybe String
    instanceIn [] = Nothing
    instanceIn (Plain _ :: es) = instanceIn es
    instanceIn (e@(Instance _ _) :: _) = Just (entryName e)

||| A file's text, or the runner's death naming it.
readOrDie : String -> IO String
readOrDie path = do
  Right text <- readFile path
    | Left err => die (path ++ ": " ++ show err)
  pure text

||| `--fuzz-check overran <request>`, or `--fuzz-check <how> <request>
||| <stdout-file>`, the file read here.
fuzzCheck : List String -> IO ()
fuzzCheck ("overran" :: request) = maybe (die ("usage: " ++ fuzzCheckUsage)) putStr (Fuzz.overranOf request)
fuzzCheck (how :: rest) = case [<] <>< rest of
  request :< file => do
    output <- readOrDie file
    maybe (die ("usage: " ++ fuzzCheckUsage)) putStr (Fuzz.checkOf how (request <>> []) output)
  [<] => die ("usage: " ++ fuzzCheckUsage)
fuzzCheck [] = die ("usage: " ++ fuzzCheckUsage)

||| `--two-levels-check <corpus> <stdout-file> <expected-file>`, the files
||| read here; an expected file that cannot be read is a finding of the
||| check's, not the runner's death.
twoLevelsCheck : String -> String -> String -> IO ()
twoLevelsCheck corpus printedFile expectedFile = do
  printed <- readOrDie printedFile
  expected <- either (const Nothing) Just <$> readFile expectedFile
  maybe (die ("usage: " ++ twoLevelsCheckUsage)) (putStr . unlines) (TwoLevels.checkOf corpus printed expected)

main : IO ()
main = do
  args <- getArgs
  case drop 1 args of
    ["--sem-program", name] =>
      maybe (die ("no semantics test " ++ name)) putStr (Sem.programOf name)
    ["--sem-expected", name] =>
      maybe (die ("no semantics test " ++ name)) putStr (expectedOf name)
    ("--fuzz-program" :: fuzz) =>
      maybe (die "usage: runtests --fuzz-program program|threads|tape|replay|shrink|two-hosts ...") putStr
            (Fuzz.programOf fuzz)
    ("--fuzz-check" :: check) => fuzzCheck check
    ("--two-levels-program" :: which) =>
      maybe (die "usage: runtests --two-levels-program primitives|prelude terms|main") putStr
            (TwoLevels.programOf which)
    ["--two-levels-check", corpus, printed, expected] => twoLevelsCheck corpus printed expected
    ["--lock"] => Lock.check !root
    rest => runSuites (fromMaybe "runtests" (head' args)) rest
