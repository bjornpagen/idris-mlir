-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Every probe (`Walk.Probe`) at small arguments through its name and back
||| (`probeOf . probeName`), every axis through its term and back
||| (`probeOfTerm . probeTerm`), and names no probe has. A probe read back is
||| compared with the probe itself, constructor and arguments, so two probes
||| that one name spells cannot pass.
module Main

import Core.Context
import Core.Name
import IdrisMLIR.Frontend.Walk
import Data.List
import Data.List1
import Data.Vect

%default total

||| Two probes are one: the same constructor at the same arguments.
sameProbe : Probe -> Probe -> Bool
sameProbe (ProbeBinder a) (ProbeBinder b) = a == b
sameProbe (ProbeHole a) (ProbeHole b) = a == b
sameProbe (ProbeHoleFound a) (ProbeHoleFound b) = a == b
sameProbe ProbeUnknown ProbeUnknown = True
sameProbe ProbeRuntime ProbeRuntime = True
sameProbe (ProbeRuntimeAt a) (ProbeRuntimeAt b) = a == b
sameProbe (ProbeStandIn a) (ProbeStandIn b) = a == b
sameProbe (ProbePattern a) (ProbePattern b) = a == b
sameProbe ProbeForm ProbeForm = True
sameProbe (ProbeAxis a c) (ProbeAxis b d) = a == b && c == d
sameProbe (ProbeAxisAt a) (ProbeAxisAt b) = a == b
sameProbe (ProbeSize a) (ProbeSize b) = a == b
sameProbe (ProbeVar a c) (ProbeVar b d) = a == b && c == d
sameProbe (ProbeFormal a c) (ProbeFormal b d) = a == b && c == d
sameProbe (ProbeFieldPath a c fs) (ProbeFieldPath b d gs) = a == b && c == d && forget fs == forget gs
sameProbe (ProbeHeld a p) (ProbeHeld b q) = toList a == toList b && p == q
sameProbe _ _ = False

||| The small numbers every numbered family is drawn at, with two of more
||| than one digit.
small : List Nat
small = [0, 1, 2, 3, 10, 12]

||| Field paths: one step and longer ones.
paths : List (List1 Nat)
paths = [0 ::: [], 3 ::: [], 2 ::: [0, 5], 1 ::: [1]]

||| Held addresses: the least, the greatest, and one of every kind of byte.
heldAddresses : List Address
heldAddresses =
  [ [0, 0, 0, 0, 0, 0, 0, 0], [255, 255, 255, 255, 255, 255, 255, 255]
  , [1, 2, 3, 4, 5, 6, 7, 255] ]

||| Every probe that is one name, at the arguments above.
probes : List Probe
probes =
  [ProbeUnknown, ProbeRuntime, ProbeForm]
  ++ concatMap (\i => [ ProbeBinder i, ProbeHole i, ProbeHoleFound i, ProbeRuntimeAt i
                      , ProbeStandIn i, ProbePattern i, ProbeAxisAt i, ProbeSize i ]) small
  ++ concatMap (\i => concatMap (\d => [ProbeVar i d, ProbeFormal i d]) small) small
  ++ concatMap (\i => concatMap (\d => map (ProbeFieldPath i d) paths) small) small
  ++ concatMap (\a => map (ProbeHeld a) small) heldAddresses

||| Names a user program or Idris may hold, which are no probe, their texts
||| interned in one table seeded as a session's is: a text of the known
||| vocabulary is its known identifier, and no two texts share one.
others : List Name
others =
  let (x1, t1) = internIn "x1" seeded
      (pattern, t2) = internIn "idris-mlir-pattern" t1
      (pattern07, t3) = internIn "idris-mlir-pattern-07" t2
      (arg, t4) = internIn "arg" t3
      (axis, t5) = internIn "idris-mlir-axis" t4
      (a, t6) = internIn "A" t5
      (b, t7) = internIn "b" t6
      (x, t8) = internIn "x" t7
      (field, _) = internIn "idris-mlir-field" t8
  in [ UN (Basic x1), UN (Basic pattern), UN (Basic pattern07)
     , MN arg 0, MN axis 0, NS (nsOf [a]) (UN (Basic b))
     , Nested (0, 0) (UN (Basic x)), Nested (1, 2) (UN (Basic field)) ]

roundTrips : Probe -> Bool
roundTrips p = maybe False (sameProbe p) (probeOf (probeName p))

axisRoundTrips : (Nat, Nat) -> Bool
axisRoundTrips (i, j) =
  let p = ProbeAxis i j in maybe False (sameProbe p) (probeOfTerm (the ClosedTerm (probeTerm p)))

report : String -> List String -> IO ()
report what [] = putStrLn (what ++ ": each read back as itself")
report what bad = for_ bad $ \b => putStrLn (what ++ ": WRONG " ++ b)

main : IO ()
main = do
  report "probes" (map (show . probeName) (filter (not . roundTrips) probes))
  report "axes" (map show (filter (not . axisRoundTrips) [(i, j) | i <- small, j <- small]))
  case map show (filter (isJust . probeOf) others) of
    [] => putStrLn "other names: no probe"
    bad => for_ bad $ \b => putStrLn ("other names: WRONG " ++ b)
