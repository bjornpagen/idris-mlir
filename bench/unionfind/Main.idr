-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Main

-- Union-find with path compression and union by rank over an array of
-- records: Lean's `unionfind.lean` (Counting Immutable Beans), which
-- threads the array through a state monad and updates it in place while
-- unshared. Here the array is a linear array (Array's LArray) of records,
-- threaded at quantity 1 through every find and union: pure code, each
-- update a store of a freshly built record, as in Lean. Prints "ok" and the
-- number of nodes that are not roots.

import Prelude
import Linear.Notation
import Array

record NodeData where
  constructor MkNodeData
  find : Int
  rank : Int

Arr : Nat -> Type
Arr n = LArray [<n] NodeData

-- Node n's position in the array, when it is one.
node : (cap : Nat) -> Int -> Maybe (Fin cap)
node cap n = if n < 0 then Nothing else checkIndex cap (cast n)

-- The array with e at node n (unchanged for a node out of range).
set : {cap : Nat} -> (1 _ : Arr cap) -> Int -> NodeData -> Arr cap
set s n e = case node cap n of
  Just j => write s [<j] e
  Nothing => s

-- The entry of n's root, found with at most fuel steps; every entry on the
-- path is replaced by the root's. A node out of range, or a chain longer
-- than the fuel, is an error, as in Lean.
findEntryAux : {cap : Nat} -> (1 _ : Arr cap) -> Nat -> Int -> Res NodeData (const (Arr cap))
findEntryAux s Z n = MkNodeData (-1) 0 # s
findEntryAux s (S fuel) n = case node cap n of
  Nothing => MkNodeData (-2) 0 # s
  Just j =>
    let e # s1 = read s [<j] in
    if e.find == n then e # s1
    else let e1 # s2 = findEntryAux s1 fuel e.find
         in e1 # write s2 [<j] e1

findEntry : {cap : Nat} -> (1 _ : Arr cap) -> Int -> Res NodeData (const (Arr cap))
findEntry s n = findEntryAux s cap n

union : {cap : Nat} -> (1 _ : Arr cap) -> Int -> Int -> Arr cap
union s n1 n2 =
  let r1 # s1 = findEntry s n1
      r2 # s2 = findEntry s1 n2
  in if r1.find == r2.find then s2
     else if r1.rank < r2.rank then set s2 r1.find (MkNodeData r2.find 0)
     else if r1.rank == r2.rank
       then set (set s2 r1.find (MkNodeData r2.find 0)) r2.find (MkNodeData r2.find (r2.rank + 1))
       else set s2 r2.find (MkNodeData r1.find 0)

mkNodes : {cap : Nat} -> (1 _ : Arr cap) -> Int -> Arr cap
mkNodes s n = if n < cast cap then mkNodes (set s n (MkNodeData n 1)) (n + 1) else s

mergePackAux : {cap : Nat} -> (1 _ : Arr cap) -> Nat -> Int -> Int -> Arr cap
mergePackAux s Z n d = s
mergePackAux s (S fuel) n d =
  if n + d < cast cap then mergePackAux (union s n (n + d)) fuel (n + 1) d
  else s

mergePack : {cap : Nat} -> (1 _ : Arr cap) -> Int -> Arr cap
mergePack s d = mergePackAux s cap 0 d

numEqsAux : {cap : Nat} -> (1 _ : Arr cap) -> Nat -> Int -> Int -> Res Int (const (Arr cap))
numEqsAux s Z n r = r # s
numEqsAux s (S fuel) n r =
  if n < cast cap then
    let e # s1 = findEntry s n
    in numEqsAux s1 fuel (n + 1) (if n == e.find then r else r + 1)
  else r # s

discard : (1 _ : Arr cap) -> ()
discard a = let MkBang _ = freeze a in ()

test : Nat -> Int
test n =
  unrestricted $ withArray [<n] (MkNodeData 0 0) (\s =>
    let 1 s1 = mergePack (mergePack (mergePack (mergePack (mkNodes s 0) 50000) 10000) 5000) 1000
        v # s2 = numEqsAux s1 n 0 0
        () = discard s2
    in MkBang v)

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  if n < 2
     then putStrLn "Error : input must be greater than 1"
     else putStrLn ("ok " ++ show (test (cast n)))
