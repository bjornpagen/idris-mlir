-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Every probe family through its name and back (`Walk.probeOf`), an axis
||| through its term (`probeOfTerm`), and names no probe has.
module Main

import Core.Context
import IdrisMLIR.Frontend.Walk
import Data.List1
import Data.Vect

%default total

-- Every probe family at a few numbers, through its name and back.
probes : List Probe
probes = the (List Probe)
  [ ProbeBinder 0, ProbeBinder 7, ProbeHole 0, ProbeHole 3, ProbeHoleFound 2, ProbeUnknown, ProbeRuntime
  , ProbeRuntimeAt 0, ProbeRuntimeAt 5, ProbeStandIn 1, ProbePattern 0, ProbePattern 12, ProbeForm
  , ProbeAxisAt 4, ProbeSize 3, ProbeVar 1 2, ProbeFormal 0 3, ProbeFieldPath 1 0 (2 ::: [0, 5])
  , ProbeHeld [1, 2, 3, 4, 5, 6, 7, 255] 4 ]

sameProbe : Probe -> Probe -> Bool
sameProbe p q = probeName p == probeName q

main : IO ()
main = do
  for_ probes $ \p => case probeOf (probeName p) of
    Just q => putStrLn (if sameProbe p q then "ok " ++ show (probeName p) else "WRONG " ++ show (probeName p))
    Nothing => putStrLn ("NONE " ++ show (probeName p))
  -- An axis is its term: two references.
  case probeOfTerm (the ClosedTerm (probeTerm (ProbeAxis 2 3))) of
    Just (ProbeAxis 2 3) => putStrLn "ok axis"
    _ => putStrLn "WRONG axis"
  -- Names no probe has.
  for_ (the (List Name) [UN (Basic "x1"), MN "arg" 0, UN (Basic "idris-mlir-pattern-07"), NS (mkNamespace "A") (UN (Basic "b"))]) $ \n =>
    putStrLn (maybe "ok none" (const "WRONG some") (probeOf n))
