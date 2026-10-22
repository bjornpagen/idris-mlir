-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The golden test runner. It builds and runs under both hosts, the pinned
||| Idris on Chez and idris-mlir itself, so it depends on base and the
||| dialect's specification alone, and it creates no process: the runs are
||| harness/runs.sh's, between the plan this writes and the tally it reads,
||| and a check that needs a tool asks the glue to start it (Serve.idr).
|||
||| Every test is a directory of `tests/`, all at that one level, and its
||| kind is what it holds (`kindOf`): a `run` script is a scripted test; a
||| `Main.idr` without one is a compiled program, refused by one rule when
||| its first line is `-- expect: <rule>, line <n>`; one `.mlir` file and
||| nothing to run it is a dialect fixture, whose RUN lines Lit.idr runs.
||| The suite a test belongs to follows from its kind (a fixture is
||| `test-idr`, anything else `test`), unless the test names another in a
||| `suite` file, the one way any test declares one. A directory of
||| `tests/` that is no test stops the runner: nothing sits there unread.
|||
||| harness/one.sh runs each test in a process of its own, in the test's
||| directory, and compares its stdout with its `expected`, or with the
||| kind's expectation where the kind fixes it (a fixture's RUN lines all
||| hold). Run from `tests/`, by make, through harness/runs.sh:
|||
|||     runtests --plan <results> <idris-mlir> [--suite check|test|test-idr|test-mlir-tools]
|||              [--list] [--threads N] [--only NAMES] [--except NAMES] [--only-file PATH]
|||     runtests --tally <results>
|||
||| `--list` prints the names of the runs the options select, and plans
||| none. `--only` and `--except` take words, each a part of a test's name;
||| a run is selected when its name holds one of `--only`'s (or there are
||| none) and none of `--except`'s. A new expectation is written by hand: a
||| test with no `expected` fails and prints its whole output, which its
||| author reads and, when it is right, copies to `expected`. Nothing
||| accepts output for a test.
|||
||| A test may run once per parameter: `parameterized` names it, and it
||| runs as `<name>@<parameter>`, its run script given the parameter as `$2`.
|||
||| It also computes every check the run scripts share, under the names
||| harness/lib/harness.sh gives them. Those that start a tool run as a
||| session with the glue:
|||
|||     runtests --serve <dir> <check> <argument>...
|||       compile-program|compile-checked [OPTION]... SOURCE OUTPUT
|||       link-program ARG... | mlir-check WHAT SOURCE ARG... | copy-fixture FIXTURE DEST
|||       e2e-io FIXTURE | sem-case NAME | near-neighbour FIXTURE   (Programs.idr)
|||       profile-reject FIXTURE | registry-shadowed KEY CASE SOURCE MODULE NAME EDIT MAIN [OPTION]...
|||       determinism FIXTURE [INPUT]... | determinism-threads FIXTURE   (Determinism.idr)
|||       fuzz SEED | fuzz-lazy SEED   (FuzzRun.idr)
|||       lit FILE | lit-fixture | lit-differential FILE BEFORE AFTER   (Lit.idr)
|||
||| and those that read files alone run by themselves:
|||
|||     runtests --show FILE... | --empty NAME FILE | --first-word FILE | --package-options DIR
|||     runtests --artifact-files|--artifact-file DIR NAME KIND | --artifacts DIR NAME | --no-artifacts DIR
|||     runtests --stage-options FIXTURE | --timing-rows REPORT | --idris-lex code|strings FILE
|||     runtests --artifact-kinds | --runtime-fact <dev-prefix> NAME
|||     runtests --lit-fails any|N STATUS STDERR CMD...
|||                                     how a RUN line's command that is to fail failed
|||     runtests --reject <test> <report> <output>
|||                                     a refused program held to its header (Reject.idr)
|||     runtests --rules | --rule-phrases [CATEGORY] | --rule-category PHRASE
|||                                     every rule's phrase and its category's (Facts.idr)
|||     runtests --linear-program <seed> <case> linear|twin|stdin|verdict | checks
|||                                     a generated linear program, its
|||                                     de-linearized twin, its input, the
|||                                     verdict the rule predicts (Linear.idr)
|||     runtests --linear-check <seed> <case> <status> <report>
|||                                     a compilation held to that verdict
|||     runtests --fuzz-program <request> | --lazy-program <request>
|||                                     a program of the fuzzers, or their
|||                                     checkers' own checks (Fuzz.idr, Lazy.idr)
|||     runtests --expect-table         idr-expect's table of properties, printed
|||                                     from their records (Properties.idr)
|||     runtests --scale-print <fixture> 1|2
|||                                     a scale fixture at its size or twice it
|||     runtests --scale-check <report> <trace> <report> <trace>
|||                                     the two compilations held to the
|||                                     scaling relation (Scale.idr)
|||     runtests --runtime-effects <module>
|||                                     each op's declared effects held to its
|||                                     runtime function (RuntimeEffects.idr)
|||     runtests --trace-totals <trace> | --trace-units <trace>...
|||                                     time traces summed (Trace.idr)
|||     runtests --lock                 the check of toolchain.lock.json
module Main

import Data.Either
import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet
import Data.So
import Data.String
import System
import System.Directory
import System.File

import Covers
import Determinism
import Facts
import Files
import Fuzz
import FuzzRun
import Harness
import Lazy
import Lex
import Linear
import Lit
import Lock
import Programs
import Properties
import Reject
import Runner
import RuntimeEffects
import Scale
import Sem
import Serve
import Trace
import Universal

%default covering

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

||| Whether a test runs on this host.
data Placement = Here | Elsewhere

isHere : Placement -> Bool
isHere Here = True
isHere Elsewhere = False

||| Where TEST runs. A test with no `targets` file holds everywhere; one
||| with a `targets` file holds only where it names one of this host's
||| names, which is how an x86-only, arm64-only or Linux-only test runs
||| where it holds; elsewhere it is reported as not run, never counted as
||| passed.
placementOf : SortedSet String -> String -> IO Placement
placementOf names test = do
  Right text <- readFile (test ++ "/targets")
    | Left _ => pure Here
  pure (if any (\word => contains word names) (words text) then Here else Elsewhere)

||| What a test is, read from what its directory holds; harness/one.sh runs
||| each kind its own way.
data Kind = Script | Program | Reject | Fixture

Eq Kind where
  Script == Script = True
  Program == Program = True
  Reject == Reject = True
  Fixture == Fixture = True
  _ == _ = False

||| What the runner knows of a kind: its name, as harness/one.sh is given
||| it; what its tests are, for a pool's banner; and the suite a test of it
||| is in when it names none.
record KindFacts where
  constructor MkKindFacts
  name : String
  title : String
  suite : String

facts : Kind -> KindFacts
facts Script = MkKindFacts "script" "scripts" "test"
facts Program = MkKindFacts "program" "compiled programs" "test"
facts Reject = MkKindFacts "reject" "programs refused by one rule" "test"
facts Fixture = MkKindFacts "fixture" "dialect fixtures" "test-idr"

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
       let header = isPrefixOf "--" first && isPrefixOf "expect:" (trim (pack (drop 2 (unpack first))))
       pure (Right (if header then Reject else Program))
     else do
       let modules = filter (isSuffixOf ".mlir") !(entries dir)
       pure (case modules of
               [_] => Right Fixture
               [] => Left "no run script, Main.idr or .mlir file"
               _ => Left "more than one .mlir file and no run script")

||| A test: its name, its kind, the suite it is in, and where it runs.
record Test where
  constructor MkTest
  name : String
  kind : Kind
  suite : String
  placement : Placement

||| The suites, each with what it checks.
suites : List (String, String)
suites =
  [ ("check", "the repository: pins, commands, toolchain, source rules")
  , ("test", "the compiler on programs, and what it builds")
  , ("test-idr", "the idr dialect and its passes")
  , ("test-mlir-tools", "each bug of upstream/ on its reproducer, with the pinned (patched) tools; the upstream dialects' Idris modules, written again by the built generator")
  ]

||| The test in DIR, or why it is none.
testOf : SortedSet String -> String -> IO (Either String Test)
testOf names dir = do
  Right kind <- kindOf dir
    | Left why => pure (Left (dir ++ ": " ++ why))
  declared <- readFile (dir ++ "/suite")
  let suite = either (const (facts kind).suite) trim declared
  if isNothing (lookup suite suites)
     then pure (Left (dir ++ ": suite names no suite: " ++ suite))
     else pure (Right (MkTest dir kind suite !(placementOf names dir)))

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

------------------------------------------------------------------------------
-- The options of a plan
------------------------------------------------------------------------------

||| What a plan is asked for: the suite (every suite when none), whether
||| only to list the runs, the threads to run them on, and the words that
||| select them by name.
record Options where
  constructor MkOptions
  suite : Maybe String
  listing : Bool
  threads : Nat
  only : List String
  except : List String
  onlyFile : Maybe String

defaults : Options
defaults = MkOptions Nothing False 1 [] [] Nothing

||| The options, or the argument that is none. An empty `--only` or
||| `--except` (make passes both, often empty) selects by nothing.
optionsOf : List String -> Either String Options
optionsOf = go defaults
  where
    go : Options -> List String -> Either String Options
    go o [] = Right o
    go o ("--suite" :: s :: rest) =
      if isJust (lookup s suites) then go ({ suite := Just s } o) rest else Left ("unknown suite " ++ s)
    go o ("--list" :: rest) = go ({ listing := True } o) rest
    go o ("--threads" :: n :: rest) =
      maybe (Left ("--threads takes a positive number, not " ++ n)) (\k => go ({ threads := k } o) rest) (parsePositive {a = Nat} n)
    go o ("--only" :: ws :: rest) = go ({ only $= (words ws ++) } o) rest
    go o ("--except" :: ws :: rest) = go ({ except $= (words ws ++) } o) rest
    go o ("--only-file" :: p :: rest) = go ({ onlyFile := Just p } o) rest
    go o (arg :: _) = Left ("not an option of the runner: " ++ arg)

||| Whether the options select the run `name`.
selects : (only : List String) -> (except : List String) -> String -> Bool
selects only except name =
  (null only || any (`isInfixOf` name) only) && all (not . (`isInfixOf` name)) except

||| The pools of a suite, one per kind, each run with its kind's name, as
||| harness/one.sh takes them; and the runs whose `targets` file names no
||| name of this host.
pools : List Test -> String -> (List Pool, List String)
pools tests suite =
  let inSuite = filter (\t => t.suite == suite) tests
      description = fromMaybe "" (lookup suite suites)
      poolOf = \kind =>
        MkPool (suite ++ ": " ++ (facts kind).title ++ "; " ++ description)
               (filter (\t => t.kind == kind && isHere t.placement) inSuite
                 >>= \t => map (\r => (r, (facts t.kind).name)) (runsOf t.name))
  in (map poolOf [Program, Reject, Fixture, Script],
      filter (not . isHere . (.placement)) inSuite >>= \t => runsOf t.name)

||| The repository root, IDRIS_MLIR_ROOT, which the Makefile exports to
||| every test command, as it does the host's names; without it the runner
||| refuses to start.
repositoryRoot : IO String
repositoryRoot = do
  Just r <- getEnv "IDRIS_MLIR_ROOT"
    | Nothing => do
        putStrLn "tests: IDRIS_MLIR_ROOT is unset; run the tests through make"
        exitWith (ExitFailure 2)
  pure r

usage : String
usage = unlines
  [ "usage: runtests --plan <results> <idris-mlir> [--suite " ++ joinBy "|" (map fst suites) ++ "] [--list]"
  , "                [--threads N] [--only NAMES] [--except NAMES] [--only-file PATH]"
  , "       runtests --tally <results>"
  , "       runtests --serve <dir> compile-program|compile-checked [OPTION]... SOURCE OUTPUT"
  , "       runtests --serve <dir> link-program ARG... | mlir-check WHAT SOURCE ARG... | copy-fixture FIXTURE DEST"
  , "       runtests --serve <dir> e2e-io FIXTURE | sem-case NAME | near-neighbour FIXTURE"
  , "       runtests --serve <dir> profile-reject FIXTURE | registry-shadowed KEY CASE SOURCE MODULE NAME shape|gone MAIN [OPTION]..."
  , "       runtests --serve <dir> determinism FIXTURE [INPUT]... | determinism-threads FIXTURE"
  , "       runtests --serve <dir> fuzz SEED | fuzz-lazy SEED"
  , "       runtests --serve <dir> lit FILE | lit-fixture | lit-differential FILE BEFORE AFTER"
  , "       runtests --show FILE... | --empty NAME FILE | --first-word FILE | --package-options DIR"
  , "       runtests --artifact-files|--artifact-file DIR NAME module|objects|executable"
  , "       runtests --artifacts DIR NAME | --no-artifacts DIR | --stage-options FIXTURE | --timing-rows REPORT"
  , "       runtests --idris-lex code|strings FILE | --lit-fails any|N STATUS STDERR CMD..."
  , "       runtests --artifact-kinds | --runtime-fact <dev-prefix> NAME"
  , "       runtests --reject <test> <report> <output>"
  , "       runtests --rules | --rule-phrases [CATEGORY] | --rule-category PHRASE"
  , "       runtests --trace-totals <trace> | --trace-units <trace>... | --lock"
  , "       runtests --linear-program <seed> <case> linear|twin|stdin|verdict | --linear-program checks"
  , "       runtests --linear-check <seed> <case> <status> <report>"
  , "       runtests --expect-table | --scale-print <fixture> 1|2 | --scale-check <report> <trace> <report> <trace>"
  , "       runtests --runtime-effects <module>"
  , "       runtests --fuzz-program program|threads|tape|replay|shrink|two-hosts ..."
  , "       runtests --lazy-program <seed> <cases> main|stdin | --lazy-program checks"
  ]

||| `--plan <results> <idris-mlir> <options>`: the runs the options select,
||| listed, or written as pools for harness/runs.sh. The compiler under test
||| is harness/runs.sh's to hand to one.sh; the plan only checks it is named.
plan : (results : String) -> List String -> IO ()
plan results args = do
  let Right opts = optionsOf args
    | Left why => die (why ++ "\n" ++ usage)
  Right tests <- discover
    | Left bad => die ("tests/ holds what is no test:\n" ++ unlines (map ("  " ++) bad))
  -- Run anywhere but tests/, nothing is found; that must not pass.
  when (null tests) $ die "no tests found: run the runner in tests/, through make"
  extra <- maybe (pure []) (\p => words <$> readOrDie p) opts.onlyFile
  let only = extra ++ opts.only
  let chosen = maybe (map fst suites) pure opts.suite
  let found = map (pools tests) chosen
  let keep : Pool -> Pool
      keep pool = { runs $= filter (selects only opts.except . fst) } pool
  let selected = map keep (concatMap fst found)
  let notHere = filter (selects only opts.except) (concatMap snd found)
  if opts.listing
     then putStr (unlines (selected >>= map fst . (.runs)))
     else writePlan results opts.threads notHere selected

||| The exit status of a check that answers with one.
exitAs : Nat -> IO ()
exitAs n =
  let code = cast {to = Int} n in
  case choose (not (code == 0)) of
    Left nonZero => exitWith (ExitFailure code @{nonZero})
    Right _ => exitSuccess

||| A status a check reports as its own, the shell's number.
exitWith' : Status -> IO ()
exitWith' = exitAs . raw

||| The last two words of a compilation's, its source and its output, and
||| the options before them.
compilation : List String -> Maybe (List String, String, String)
compilation args = case [<] <>< args of
  options :< source :< output => Just (options <>> [], source, output)
  _ => Nothing

||| `--serve <dir> <check> <argument>...`: the checks that start tools.
serve : Env -> List String -> IO ()
serve e ("compile-program" :: args) = case compilation args of
  Just (options, source, output) => compileProgram e options source output >>= exitWith'
  Nothing => die usage
serve e ("compile-checked" :: args) = case compilation args of
  Just (options, source, output) => compileChecked e options source output >>= exitWith'
  Nothing => die usage
serve e ("link-program" :: args) = linkProgram e args ToCaller (Apart ToCaller) >>= exitWith'
serve e ("mlir-check" :: what :: source :: args) = mlirCheck e what source args
serve e ["copy-fixture", fixture, dest] = copyFixture e fixture dest >>= exitWith'
serve e ["e2e-io", fixture] = e2eIo e fixture
serve e ["sem-case", name] = semCase e name
serve e ["near-neighbour", fixture] = nearNeighbour e fixture
serve e ["profile-reject", fixture] = profileReject e fixture
serve e ("registry-shadowed" :: args) = fromMaybe (die usage) (registryShadowedOf e args)
serve e ("determinism" :: fixture :: inputs) = determinism e fixture inputs
serve e ["determinism-threads", fixture] = determinismThreads e fixture
serve e ["fuzz", seed] = fuzz e seed
serve e ["fuzz-lazy", seed] = fuzzLazy e seed
serve e ["lit", file] = litLines e file >>= traverse_ (tell e)
serve e ["lit-fixture"] = litFixture e
serve e ("lit-differential" :: file :: modules) = litDifferential e file modules >>= exitAs
serve _ _ = die usage

||| `--lit-fails <want> <status> <stderr> <command>...`: the line of how the
||| command did not fail as stated, if it did not, and status 1 then.
litFailsCheck : (want, status, stderr : String) -> List String -> IO ()
litFailsCheck want status stderr command = do
  errors <- bytesIfThere stderr
  case litFails want (fromMaybe 0 (parsePositive status)) errors command of
    Nothing => exitSuccess
    Just line => do putStrLn line; exitFailure

main : IO ()
main = do
  args <- getArgs
  case drop 1 args of
    ("--plan" :: results :: _ :: rest) => plan results rest
    ["--tally", results] => tally results
    ("--serve" :: dir :: check) => withSession dir $ \s => do
      tools <- toolsOf
      serve (MkEnv tools s "") check
    ("--show" :: files) => showFiles files
    ["--empty", name, file] => emptiness name file
    ["--first-word", file] => firstWord file >>= traverse_ putStrLn
    ["--package-options", dir] => packageOptions dir >>= putStrLn . unwords
    ["--artifact-files", dir, name, kind] =>
      maybe (die usage) (\k => artifactFiles dir (buildNamed name) k >>= putStr . unlines) (kindNamed kind)
    ["--artifact-file", dir, name, kind] =>
      maybe (die usage) (\k => artifactFile dir (buildNamed name) k >>= traverse_ putStrLn) (kindNamed kind)
    ["--artifacts", dir, name] => artifactLines dir name >>= putStr . unlines
    ["--no-artifacts", dir] => noArtifactsLine dir >>= putStrLn
    ["--stage-options", fixture] => stageOptions fixture >>= putStr . unlines
    ["--artifact-kinds"] => putStrLn (unwords (map kindName artifactKinds))
    ["--runtime-fact", devPrefix, name] =>
      runtimeFact devPrefix name >>= either (\line => do putStrLn line; exitFailure) putStrLn
    ["--timing-rows", report] => readOrDie report >>= putStr . unlines . timingRows
    ["--idris-lex", mode, file] =>
      maybe (die usage) (\m => readOrDie file >>= putStr . unlines . lexed m) (lexedNamed mode)
    ("--lit-fails" :: want :: status :: stderr :: command) => litFailsCheck want status stderr command
    ["--reject", test, report, output] => reject test report output
    ["--trace-totals", trace] => traceTotals trace
    ("--trace-units" :: traces@(_ :: _)) => traceUnits traces
    ("--fuzz-program" :: fuzz) => maybe (die usage) putStr (Fuzz.programOf fuzz)
    ("--linear-program" :: request) => maybe (die usage) putStr (Linear.programOf request)
    ["--linear-check", seed, n, status, report] => Linear.check seed n status report
    ("--lazy-program" :: request) => maybe (die usage) putStr (Lazy.programOf request)
    ["--expect-table"] => putStr Properties.table
    ("--scale-print" :: request) => maybe (die usage) putStr (Scale.printOf request)
    ("--scale-check" :: files) => scaleCheck files
    ["--runtime-effects", module'] => readOrDie module' >>= putStr . unlines . heldLines
    ["--lock"] => repositoryRoot >>= Lock.check
    ["--rules"] => putStr (unlines ruleLines)
    ["--rule-phrases"] => putStr (unlines (rulePhrases Nothing))
    ["--rule-phrases", category] => putStr (unlines (rulePhrases (Just category)))
    ["--rule-category", phrase] => maybe exitFailure putStrLn (categoryOfPhrase phrase)
    _ => die usage
