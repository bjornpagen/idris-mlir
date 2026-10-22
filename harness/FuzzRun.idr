-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The fuzzers run: generated closed expressions over every builtin
||| (Fuzz.idr), each written four ways in one build, held to each other, to
||| the folders, over the integers to what the builtins mean, and, where a
||| case reaches a guard that fails, to the crash its guard's cause names;
||| and programs of lazy structures (Lazy.idr), held to their models. Every
||| check is a relation the program's own run and modules must satisfy, so
||| none depends on what a seed draws or in what order.
module FuzzRun

import Data.List
import Data.Maybe
import Data.String
import System
import System.File

import Files
import Fuzz
import Harness
import Lazy
import Serve

%default covering

||| The cases of a program: the size the seeds' recorded outputs had, kept.
||| That thirty compile within the test's limits at every thread count a
||| seed draws is for the owner's build to confirm.
fuzzCases : String
fuzzCases = "30"

||| The cases of a lazy program.
lazyCases : String
lazyCases = "8"

||| The two parts of a seed's program: its cases' operands read at run time,
||| or written in it.
parts : List String
parts = ["runtime", "static"]

||| What one part's checks found: the problems of each check, the first
||| failing case and how it fails, the step that stopped the checks before
||| they could run, and why the model's check did not run.
record Found where
  constructor MkFound
  compiled : List String
  agree : List String
  folded : List String
  model : List String
  firstFailing : Maybe (String, String)
  stopped : Maybe String
  unmodelled : Maybe String

nothingFound : Found
nothingFound = MkFound [] [] [] [] Nothing Nothing Nothing

||| A check's line: TEXT, then `ok`, or `failed` and the problems the check
||| found, or, for a check of the program's output or modules after a step
||| before it failed, `not run` and that step.
report : Env -> (text : String) -> (problems : List String) -> (stopped : Maybe String) -> IO ()
report e text problems stopped = case stopped of
  Just step => tell e (text ++ ": not run: " ++ step)
  Nothing => case problems of
    [] => tell e (text ++ ": ok")
    _ => do tell e (text ++ ": failed"); tellAll e (take 40 problems)

||| The first ten lines of a failed compilation's output, indented.
compileLines : Env -> IO (List String)
compileLines e = indented <$> firstLines 10 [inWork e "compile.out", inWork e "compile.err"]

||| What a fuzz check says of a request's cases and their run, a line per
||| problem; a check the runner cannot make is a line saying so.
checked : (seed, how : String) -> List String -> Observed -> List String
checked seed how request run = case Fuzz.checkOf how request run of
  Just text => lines text
  Nothing => [seed ++ ": no " ++ how ++ " check"]

||| How a run of a fuzzer program went, read back byte for byte.
observedRun : Env -> (name : String) -> Status -> IO Observed
observedRun e name status = do
  output <- bytesIfThere (inWork e (name ++ ".out"))
  errors <- bytesIfThere (inWork e (name ++ ".err"))
  pure (Fuzz.observed output (statusWords status) errors)

||| The program of the seed for the part and its stdin generated, compiled
||| at the seed's thread count with the checked runtime, run on its stdin,
||| and checked:
|||   - the build compiles and runs, no case ran out of its tape, and the
|||     run ends as the oracle says: returned with nothing on stderr, or
|||     crashed at the first case whose evaluation reaches a guard that
|||     fails, by one of the causes it may meet first;
|||   - each case's lines (d, j, r, s) that run print one value, each of
|||     them once;
|||   - once the program is graded no op of main computes on constants alone
|||     (folded=@Main.main), so the folders computed every d line;
|||   - each case the model covers prints the value its integers mean.
||| A check whose input was never made, because the program was not
||| generated or compiled, is not run, and the step that stopped it says
||| so, which fails the test: an empty list of problems is no evidence for a
||| check that never looked. So does the model's check when no case the run
||| prints has a model.
fuzzCheck : Env -> (seed, threads, part : String) -> IO Found
fuzzCheck e seed threads part = do
  let dir = inWork e ("fuzz-" ++ part ++ "-" ++ seed)
  made e (dir ++ "/prog")
  let request = ["program", seed, fuzzCases, part]
  case (Fuzz.programOf (request ++ ["main"]), Fuzz.programOf (request ++ ["stdin"])) of
    (Nothing, _) => pure ({ compiled := [seed ++ ": no main"], stopped := Just "no main was generated" } nothingFound)
    (_, Nothing) => pure ({ compiled := [seed ++ ": no stdin"], stopped := Just "no stdin was generated" } nothingFound)
    (Just main, Just stdin) => do
      ignore (writeFile (dir ++ "/main") main)
      ignore (writeFile (dir ++ "/stdin") stdin)
      let overran = maybe [seed ++ ": no overran check"] lines (Fuzz.overranOf request)
      ignore (writeFile (dir ++ "/prog/Main.idr") main)
      compiled <- compileChecked e ["--num-threads=" ++ threads] (dir ++ "/prog/Main.idr") "prog"
      if not (succeeded compiled)
         then do
           shown <- compileLines e
           pure ({ compiled := overran ++ (seed ++ ": compile exit " ++ show (raw compiled)) :: shown
                 , stopped := Just ("the compile exited " ++ show (raw compiled)) } nothingFound)
         else do
           ran <- runProgram e "prog" (dir ++ "/prog/build/exec/prog") (FromFile (dir ++ "/stdin"))
           -- A closed expression is folded by the time the program is
           -- graded: the emitted module through the pipeline's slice up to
           -- that stage, the property checked there.
           emitted <- fromMaybe "" <$> artifactFile (dir ++ "/prog") (Named "prog") Module
           folding <- bounded e [e.tools.idrisMlirOpt, "--mlir-disable-threading", emitted, "--idr-target",
                                 "--idr-pipeline=to=graded", "--idr-expect=holds=folded=@Main.main", "-o", "/dev/null"]
                              (ToFile (inWork e "expect.log")) WithOutput
           folded <- if succeeded folding then pure [] else do
             shown <- firstLines 40 [inWork e "expect.log"]
             pure ((seed ++ ": main computes on constants once graded") :: indented shown)
           run <- observedRun e "prog" ran
           let modelled : Nat = fromMaybe 0 (Fuzz.checkOf "modelled" request run >>= parsePositive . trim)
           pure (MkFound (overran ++ checked seed "ending" request run) (checked seed "agree" request run) folded
                         (if modelled == the Nat 0 then [] else checked seed "model" request run)
                         (Fuzz.checkOf "first" request run >>= failingCase)
                         Nothing
                         (if modelled == the Nat 0 then Just "no case the run prints has a model" else Nothing))
  where
    failingCase : String -> Maybe (String, String)
    failingCase text = case words text of
      [n, how] => Just (n, how)
      _ => Nothing

||| The one-case program of TAPE compiles and runs, and its case fails as
||| HOW says; its source is fuzz-try/Main.idr in the work directory, and its
||| output try.out.
failsAs : Env -> (threads, part, tape, how : String) -> IO Bool
failsAs e threads part tape how = do
  let dir = inWork e "fuzz-try"
  removed e dir
  made e dir
  case (Fuzz.programOf ["replay", tape, part, "main"], Fuzz.programOf ["replay", tape, part, "stdin"]) of
    (Just main, Just stdin) => do
      ignore (writeFile (dir ++ "/main") main)
      ignore (writeFile (dir ++ "/stdin") stdin)
      ignore (writeFile (dir ++ "/Main.idr") main)
      compiled <- compileChecked e ["--num-threads=" ++ threads] (dir ++ "/Main.idr") "prog"
      if not (succeeded compiled) then pure False else do
        ran <- runProgram e "try" (dir ++ "/build/exec/prog") (FromFile (dir ++ "/stdin"))
        run <- observedRun e "try" ran
        pure (map trim (Fuzz.checkOf "first" ["replay", tape, part] run) == Just ("1 " ++ how))
    _ => pure False

||| The case's tape shrunk: each candidate of the current tape is built as a
||| one-case program and run, and the first whose case fails the same way
||| becomes the current tape, a line saying so, and the candidates start
||| again. Every candidate is before its tape in shortlex order, so the loop
||| ends; no count of attempts stops it. Then the smallest failing case's
||| function and lines.
shrink : Env -> (seed, threads, part, failed, how : String) -> IO ()
shrink e seed threads part failed how = do
  case Fuzz.programOf ["tape", seed, failed, part] of
    Nothing => tell e ("  | no tape for case " ++ failed)
    Just text => do
      let tape = trailing text
      if not !(failsAs e threads part tape how)
         then tell e ("  | case " ++ failed ++ " does not fail alone, on its tape " ++ tape)
         else do
           smallest <- kept
           (source, output) <- smaller tape smallest
           tellAll e (indented (filter (/= "") (caseFunction (lines source))))
           tellAll e (indented (filter firstCaseLine (lines (pack (map (\c => if c == chr 0 then chr 255 else c) (unpack output))))))
  where
    kept : IO (String, String)
    kept = [| MkPair (fromMaybe "" <$> readIfThere (inWork e "fuzz-try/Main.idr")) (bytesIfThere (inWork e "try.out")) |]

    firstOf : List String -> IO (Maybe String)
    firstOf [] = pure Nothing
    firstOf (c :: cs) = do
      fails <- failsAs e threads part c how
      if fails then pure (Just c) else firstOf cs

    smaller : String -> (String, String) -> IO (String, String)
    smaller tape smallest = case Fuzz.programOf ["shrink", tape] of
      Nothing => pure smallest
      Just candidates => do
        Just found <- firstOf (lines candidates)
          | Nothing => pure smallest
        tell e ("  | smaller failing tape: " ++ found)
        smaller found !kept

    -- The lines of the first case's function: from `c1 :` to the first
    -- empty line.
    caseFunction : List String -> List String
    caseFunction ls = case dropWhile (not . isPrefixOf "c1 :") ls of
      [] => []
      (start :: rest) => start :: takeWhile (/= "") rest

    firstCaseLine : String -> Bool
    firstCaseLine l = case unpack l of
      (c :: '1' :: ' ' :: _) => elem c (unpack "djrs")
      _ => False

||| `fuzz SEED`: for each part, `runtime` then `static`, the program of SEED
||| checked (fuzzCheck), a line per check. The first case that ends
||| otherwise, disagrees or misses its model is shrunk under its check's
||| line.
export
fuzz : Env -> (seed : String) -> IO ()
fuzz e seed = case Fuzz.programOf ["threads", seed] of
  Nothing => tell e ("fuzz: no thread count for seed " ++ seed)
  Just count => for_ parts $ \part => do
    let threads = trailing count
    found <- fuzzCheck e seed threads part
    let shrunk = \how => case found.firstFailing of
                           Just (n, h) => when (h == how) (shrink e seed threads part n how)
                           Nothing => pure ()
    report e (part ++ ": every build compiles, runs and ends as its cases say") found.compiled Nothing
    shrunk "ending"
    report e (part ++ ": each case prints one value, whoever computes it") found.agree found.stopped
    shrunk "agree"
    report e (part ++ ": every d line is folded") found.folded found.stopped
    report e (part ++ ": each case over integers prints its documented value") found.model
           (found.stopped <|> found.unmodelled)
    shrunk "model"

||| `fuzz_lazy SEED`: the lazy program of SEED and its stdin, compiled with
||| the checked runtime, which ends a program at the first count operation
||| on a cell that died, and a run that returns with a cell still live as
||| its internal error, and run on its stdin; two checks, a line each: the
||| build compiles, runs, exits 0 and writes nothing on stderr; and each
||| case prints the lines its model computes. The second says `not run`,
||| which fails, when the first stopped before the program ran.
export
fuzzLazy : Env -> (seed : String) -> IO ()
fuzzLazy e seed = do
  let dir = inWork e ("lazy-" ++ seed)
  made e (dir ++ "/prog")
  (compiled, model, stopped) <- check dir
  report e "lazy: every build compiles, runs, exits 0 and writes nothing on stderr" compiled Nothing
  report e "lazy: each case prints its model" model stopped
  where
    check : String -> IO (List String, List String, Maybe String)
    check dir = case (Lazy.programOf [seed, lazyCases, "main"], Lazy.programOf [seed, lazyCases, "stdin"]) of
      (Nothing, _) => pure ([seed ++ ": no main"], [], Just "no main was generated")
      (_, Nothing) => pure ([seed ++ ": no stdin"], [], Just "no stdin was generated")
      (Just main, Just stdin) => do
        ignore (writeFile (dir ++ "/main") main)
        ignore (writeFile (dir ++ "/stdin") stdin)
        ignore (writeFile (dir ++ "/prog/Main.idr") main)
        compiled <- compileChecked e [] (dir ++ "/prog/Main.idr") "prog"
        if not (succeeded compiled)
           then do
             shown <- compileLines e
             pure ((seed ++ ": compile exit " ++ show (raw compiled)) :: shown, [], Just ("the compile exited " ++ show (raw compiled)))
           else do
             ran <- runProgram e "prog" (dir ++ "/prog/build/exec/prog") (FromFile (dir ++ "/stdin"))
             wrote <- nonEmpty (inWork e "prog.err")
             ranLines <- if succeeded ran && not wrote then pure [] else do
               shown <- firstLines 5 [inWork e "prog.err"]
               pure ((seed ++ ": prog exited " ++ show (raw ran)) :: indented shown)
             output <- bytesIfThere (inWork e "prog.out")
             let model = maybe [seed ++ ": no model check"] lines (Lazy.checkOf [seed, lazyCases] output)
             pure (ranLines, model, Nothing)
