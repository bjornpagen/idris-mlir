-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The scale fixtures (Scale.idr) compiled at a size and at twice it, and
||| held to the relation between the two. The larger fixture's compilation
||| is the longest step any test takes, so a scale test gives each step two
||| minutes; every step is still bounded.
module ScaleRun

import Data.Fin
import Data.Maybe
import Data.String
import System.File

import Harness
import Scale
import Serve

%default covering

||| `scale_compile FIXTURE FACTOR [OPTION]...`: the fixture printed at its
||| size times FACTOR and compiled whole with the OPTIONs, its report and
||| time trace beside it in the work directory's FIXTURE.FACTOR.report and
||| .trace; the compilation's status, or 1 when the fixture is not printed.
export
scaleCompile : Env -> (fixture, factor : String) -> (options : List String) -> IO Status
scaleCompile e fixture factor options =
  case (sourceFileOf fixture, printOf [fixture, factor]) of
    (Just source, Just text) => do
      let dir = inWork e (fixture ++ "." ++ factor)
      made e dir
      ignore (writeFile (dir ++ "/" ++ source) text)
      let base = inWork e (fixture ++ "." ++ factor)
      compileProgram e (["--report=" ++ base ++ ".report", "--time-trace=" ++ base ++ ".trace"] ++ options)
                     (dir ++ "/" ++ source) "scale"
    _ => do
      tell e (fixture ++ " at factor " ++ factor ++ ": the fixture is not printed")
      tell e ("  | no scale fixture " ++ fixture ++ " at factor " ++ factor)
      pure (Code 1)

||| `scale_relation FIXTURE`: compiled at its size and at twice it, both
||| accepted, every statistic and zone count at twice the size within the
||| relation of its count at the size, each solve's work and each pass's
||| footprint read among them (Scale.idr, scaleCheck).
export
scaleRelation : Env -> (fixture : String) -> IO ()
scaleRelation e fixture = go ["1", "2"]
  where
    go : List String -> IO ()
    go [] = scaleCheck (concatMap (\k => let base = inWork e (fixture ++ "." ++ k) in [base ++ ".report", base ++ ".trace"]) ["1", "2"])
    go (factor :: rest) = do
      compiled <- scaleCompile e fixture factor []
      if succeeded compiled then go rest else do
        tell e (fixture ++ " at factor " ++ factor ++ ": compile exit " ++ show (raw compiled))
        showIn e [inWork e "compile.out", inWork e "compile.err"]
