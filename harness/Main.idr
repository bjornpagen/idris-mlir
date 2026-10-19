-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The golden test runner. It reads its options with Idris's own
||| `Test.Golden`, as third_party/Idris2/tests/Main.idr does, and runs the
||| tests itself (Runner.idr).
|||
||| Every test is a directory of `tests/`, all at that one level, and its
||| kind is what it holds (`kindOf`): a `run` script is a scripted test; a
||| `Main.idr` without one is a compiled program, refused by one rule when
||| its first line is `-- expect: <rule>, line <n>`; one `.mlir` file and
||| nothing to run it is a dialect fixture, whose RUN lines lit runs. The
||| suite a test belongs to follows from its kind (a fixture is `test-idr`,
||| anything else `test`), unless the test names another in a `suite` file,
||| the one way any test declares one. A directory of `tests/` that is no
||| test stops the runner: nothing sits there unread.
|||
||| harness/one.sh runs each test in a process of its own, in the test's
||| directory, and compares its stdout with its `expected`, or with the
||| kind's expectation where the kind fixes it (a fixture's RUN lines all
||| hold). Run from `tests/`, by make (`make check`, `make test`,
||| `make test-idr`, `make test-mlir-tools`):
|||
|||     runtests <idris-mlir> [--suite check|test|test-idr|test-mlir-tools] [--list]
|||              [--threads N] [--only NAMES] [--except NAMES] [--only-file PATH]
|||
||| `--list` prints the names of the tests the options select, and runs
||| none. A new expectation is written by hand: a test with no `expected`
||| fails and prints its whole output, which its author reads and, when it
||| is right, copies to `expected`. Nothing accepts output for a test.
|||
||| A test may run once per parameter: `parameterized` names it, and it
||| runs as `<name>@<parameter>`, its run script given the parameter as `$2`.
|||
||| It also answers the `run` scripts that need Idris:
|||
|||     runtests --sem-program <name>   the program of a semantics test
|||     runtests --sem-expected <name>  the stdout its program must print
|||     runtests --fuzz-program program|threads|tape|replay|shrink|two-hosts ...
|||                                     a program or a case of the fuzzer (Fuzz.idr)
|||     runtests --fuzz-check overran|agree|model|first|modelled <request> [<stdout-file>]
|||                                     what a fuzzer program printed, checked (Fuzz.idr)
|||     runtests --lock                 the check of toolchain.lock.json
module Main

import Data.Either
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

%default covering

isDirectory : String -> IO Bool
isDirectory path = do
  Right d <- openDir path
    | Left _ => pure False
  closeDir d
  pure True

||| The names in a directory, sorted, but the hidden ones (a desktop's
||| `.DS_Store`, an editor's swap file), which no one put there as a test.
entries : String -> IO (List String)
entries dir = do
  Right names <- listDir dir
    | Left _ => pure []
  pure (sort (filter (not . isPrefixOf ".") names))

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
||| where it holds; elsewhere it is reported as not run, never counted as
||| passed.
runsHere : SortedSet String -> String -> IO Bool
runsHere names test = do
  Right text <- readFile (test ++ "/targets")
    | Left _ => pure True
  pure (any (\word => contains word names) (words text))

||| What a test is, read from what its directory holds; harness/one.sh runs
||| each kind its own way.
data Kind = Script | Program | Reject | Fixture

Eq Kind where
  Script == Script = True
  Program == Program = True
  Reject == Reject = True
  Fixture == Fixture = True
  _ == _ = False

||| The kind's name, as harness/one.sh is given it.
kindName : Kind -> String
kindName Script = "script"
kindName Program = "program"
kindName Reject = "reject"
kindName Fixture = "fixture"

||| What the tests of a kind are, for a pool's banner.
kindTitle : Kind -> String
kindTitle Script = "scripts"
kindTitle Program = "compiled programs"
kindTitle Reject = "programs refused by one rule"
kindTitle Fixture = "dialect fixtures"

||| The suite a test of a kind is in when it names none.
defaultSuite : Kind -> String
defaultSuite Fixture = "test-idr"
defaultSuite _ = "test"

||| The kind of the test in DIR, or why DIR is no test. A `run` script
||| decides, since a script may build its program or its module from the
||| files beside it; then a `Main.idr`, refused when its first line is the
||| header that names the rule; then exactly one `.mlir` file.
kindOf : String -> IO (Either String Kind)
kindOf dir = do
  if !(exists (dir ++ "/run")) then pure (Right Script) else do
  if !(exists (dir ++ "/Main.idr"))
     then do
       Right text <- readFile (dir ++ "/Main.idr")
         | Left err => pure (Left (show err))
       let first = fromMaybe "" (head' (lines text))
       let header = isPrefixOf "--" first && isPrefixOf "expect:" (trim (strSubstr 2 (strLength first) first))
       pure (Right (if header then Reject else Program))
     else do
       let modules = filter (isSuffixOf ".mlir") !(entries dir)
       pure (case modules of
               [_] => Right Fixture
               [] => Left "no run script, Main.idr or .mlir file"
               _ => Left "more than one .mlir file and no run script")

||| A test: its name, its kind, the suite it is in, and whether it runs on
||| this host.
record Test where
  constructor MkTest
  name : String
  kind : Kind
  suite : String
  here : Bool

||| The suites, each with what it checks.
suites : List (String, String)
suites =
  [ ("check", "the repository: pins, commands, toolchain, source rules")
  , ("test", "the compiler on programs, and what it builds")
  , ("test-idr", "the idr dialect and its passes")
  , ("test-mlir-tools", "each bug of upstream/ on its reproducer, with the pinned (patched) tools")
  ]

||| The test in DIR, or why it is none.
testOf : SortedSet String -> String -> IO (Either String Test)
testOf names dir = do
  Right kind <- kindOf dir
    | Left why => pure (Left (dir ++ ": " ++ why))
  declared <- readFile (dir ++ "/suite")
  let suite = either (const (defaultSuite kind)) trim declared
  if isNothing (lookup suite suites)
     then pure (Left (dir ++ ": suite names no suite: " ++ suite))
     else pure (Right (MkTest dir kind suite !(runsHere names dir)))

||| Every test of `tests/`, the current directory, or the directories
||| that are none, each with why.
discover : IO (Either (List String) (List Test))
discover = do
  names <- hostNames
  dirs <- entries "."
  found <- for dirs $ \dir =>
    if !(isDirectory dir) then testOf names dir else pure (Left (dir ++ ": not a directory"))
  pure (case partitionEithers found of
          ([], tests) => Right tests
          (bad, _) => Left bad)

||| The tests that run once per parameter, with their parameters: the
||| semantics test once per test of Sem's table.
parameterized : SortedMap String (List String)
parameterized = fromList [("semantics", Sem.names)]

||| A test's runs as `--only` selects them, the runner hands them to
||| harness/one.sh and their verdicts name them: `<name>`, or
||| `<name>@<parameter>`, which one.sh splits at its first `@`.
runsOf : String -> List String
runsOf name = case lookup name parameterized of
  Just values => map (\p => name ++ "@" ++ p) values
  Nothing => [name]

||| The pools of a suite, one per kind, each run with its kind's name, as
||| harness/one.sh takes them; and the runs whose `targets` file names no
||| name of this host.
pools : List Test -> String -> (List Pool, List String)
pools tests suite =
  let inSuite = filter (\t => t.suite == suite) tests
      description = fromMaybe "" (lookup suite suites)
      poolOf = \kind =>
        MkPool (suite ++ ": " ++ kindTitle kind ++ "; " ++ description)
               (filter (\t => t.kind == kind && t.here) inSuite >>= \t => map (\r => (r, kindName t.kind)) (runsOf t.name))
  in (filter (not . null . (.runs)) (map poolOf [Program, Reject, Fixture, Script]),
      filter (\t => not t.here) inSuite >>= \t => runsOf t.name)

||| `--suite NAME` and the other arguments.
takeOwn : List String -> (Maybe String, List String)
takeOwn ("--suite" :: name :: rest) = let (_, others) = takeOwn rest in (Just name, others)
takeOwn (arg :: rest) = let (suite, others) = takeOwn rest in (suite, arg :: others)
takeOwn [] = (Nothing, [])

fuzzCheckUsage : String
fuzzCheckUsage = "runtests --fuzz-check overran|agree|model|first|modelled program <seed> <cases> <part> | replay <tape> <part> [<stdout-file>]"

runnerUsage : String
runnerUsage = unlines
  [ "usage: runtests <idris-mlir> [--suite " ++ joinBy "|" (map fst suites) ++ "] [--list]"
  , "                [--threads N] [--only NAMES] [--except NAMES] [--only-file PATH]"
  , "       runtests --sem-program <name> | --sem-expected <name> | --lock"
  , "       runtests --fuzz-program program|threads|tape|replay|shrink|two-hosts ..."
  , "       " ++ fuzzCheckUsage
  ]

||| The repository root: IDRIS_MLIR_ROOT, or the parent of `tests/`.
root : IO String
root = do
  Nothing <- getEnv "IDRIS_MLIR_ROOT"
    | Just r => pure r
  Just here <- currentDir
    | Nothing => die "the current directory is unknown"
  pure (fromMaybe here (parent here))

runSuites : String -> List String -> IO ()
runSuites prog args = do
  let (suite, rest) = takeOwn args
  let list = elem "--list" rest
  Just opts <- options (prog :: filter (/= "--list") rest)
    | Nothing => die runnerUsage
  -- Test.Golden's parser reads options this runner does not honour; one
  -- given would be ignored, so it is refused instead.
  when (opts.interactive || opts.timing || isJust opts.failureFile || isJust opts.codegen) $
    die ("--interactive, --timing, --failure-file and --cg are not options of this runner\n" ++ runnerUsage)
  case suite of
    Just s => when (isNothing (lookup s suites)) $ die ("unknown suite " ++ s ++ "\n" ++ runnerUsage)
    Nothing => pure ()
  r <- root
  ignore $ setEnv "IDRIS_MLIR_ROOT" r True
  Right tests <- discover
    | Left bad => die ("tests/ holds what is no test:\n" ++ unlines (map ("  " ++) bad))
  -- Run anywhere but tests/, nothing is found; that must not pass.
  when (null tests) $ die "no tests found: run the runner in tests/, through make"
  let chosen = maybe (map fst suites) pure suite
  let found = map (pools tests) chosen
  let selected = concatMap fst found
  if list
     then putStr (unlines (filterTests opts (selected >>= map fst . (.runs))))
     else runPools opts r (concatMap snd found) selected

||| A file's text, or the runner's death naming it.
readOrDie : String -> IO String
readOrDie path = do
  Right text <- readFile path
    | Left err => die (path ++ ": " ++ show err)
  pure text

||| A file's bytes, each the Char of its value: a program's output, which
||| may hold NUL, where a read of the file's text (readFile, through C's
||| lines) loses the rest of its line; or the runner's death naming it.
bytesOrDie : String -> IO String
bytesOrDie path = do
  Right h <- openFile path Read
    | Left err => die (path ++ ": " ++ show err)
  bytes <- go h [<]
  closeFile h
  pure (pack bytes)
  where
    go : File -> SnocList Char -> IO (List Char)
    go h acc = do
      Right c <- fGetChar h
        | Left err => die (path ++ ": " ++ show err)
      True <- fEOF h
        | False => go h (acc :< c)
      pure (acc <>> [])

||| `--fuzz-check overran <request>`, or `--fuzz-check <how> <request>
||| <stdout-file>`, the file read here, byte for byte.
fuzzCheck : List String -> IO ()
fuzzCheck ("overran" :: request) = maybe (die ("usage: " ++ fuzzCheckUsage)) putStr (Fuzz.overranOf request)
fuzzCheck (how :: rest) = case [<] <>< rest of
  request :< file => do
    output <- bytesOrDie file
    maybe (die ("usage: " ++ fuzzCheckUsage)) putStr (Fuzz.checkOf how (request <>> []) output)
  [<] => die ("usage: " ++ fuzzCheckUsage)
fuzzCheck [] = die ("usage: " ++ fuzzCheckUsage)

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
    ["--lock"] => Lock.check !root
    rest => runSuites (fromMaybe "runtests" (head' args)) rest
