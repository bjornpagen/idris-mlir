-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The benchmarks of bench/ as a smoke test: each builds with this compiler
||| and, on a small input, prints the output recorded for it. Nothing is
||| timed; bench/run.sh times them, on inputs too large for a test.
module Bench

import Data.Maybe
import Data.String
import System.File

import Harness
import Serve

%default covering

||| `bench_smoke DIR`: every benchmark, bench/<name>/Main.idr as bench/run.sh
||| builds it, run on DIR/<name>.in, prints DIR/<name>.out, exits 0 and
||| writes nothing on stderr.
export
benchSmoke : Env -> (dir : String) -> IO ()
benchSmoke e given = do
  let dir = absolute e given
  let bench = e.tools.root ++ "/bench"
  names <- visibleIn bench
  for_ names $ \name => do
    let main = bench ++ "/" ++ name ++ "/Main.idr"
    when !(exists main) $ do
      let input = dir ++ "/" ++ name ++ ".in"
      let recorded = dir ++ "/" ++ name ++ ".out"
      inputThere <- exists input
      recordedThere <- exists recorded
      if not (inputThere && recordedThere)
         then tell e (name ++ ": no recorded input and output in " ++ baseName dir)
         else do
           let copy = inWork e name
           made e copy
           ignore (bounded e ["cp", main, copy ++ "/"] ToCaller (Apart ToCaller))
           packages <- packageOptions (bench ++ "/" ++ name)
           compiled <- compileChecked e packages (copy ++ "/Main.idr") "prog"
           if not (succeeded compiled)
              then do
                tell e (name ++ ": compile exit " ++ show (raw compiled))
                showIn e [inWork e "compile.out", inWork e "compile.err"]
              else do
                ran <- runProgram e name (copy ++ "/build/exec/prog") (FromFile input)
                wrote <- nonEmpty (inWork e (name ++ ".err"))
                if not (succeeded ran) || wrote
                   then do
                     tell e (name ++ ": exit " ++ show (raw ran))
                     showIn e [inWork e (name ++ ".err")]
                   else do
                     same <- sameBytes e recorded (inWork e (name ++ ".out"))
                     if same
                        then tell e (name ++ ": prints the recorded output")
                        else do
                          tell e (name ++ ": prints another output (< recorded, > printed)")
                          tellAll e !(differences e recorded (inWork e (name ++ ".out")))
