module Main

-- Union-find with path compression and union by rank over an array of
-- records: Lean's `unionfind.lean` (Counting Immutable Beans), which
-- threads the array through a state monad and updates it in place while
-- unshared. Here the array is a linear array (Linear.Array) of records,
-- threaded at quantity 1 through every find and union: pure code, each
-- update a store of a freshly built record, as in Lean. Prints "ok" and the
-- number of nodes that are not roots.

import Prelude
import Linear.Notation
import Linear.Array

record NodeData where
  constructor MkNodeData
  find : Int
  rank : Int

Arr : Type
Arr = Array NodeData

-- The entry of n's root, found with at most fuel steps; every entry on the
-- path is replaced by the root's. A node out of range, or a chain longer
-- than the fuel, is an error, as in Lean.
findEntryAux : (1 _ : Arr) -> Int -> Int -> Int -> Res NodeData (const Arr)
findEntryAux s cap fuel n =
  if fuel == 0 then MkNodeData (-1) 0 # s
  else if n < 0 || n >= cap then MkNodeData (-2) 0 # s
  else
    let e # s1 = read s n in
    if e.find == n then e # s1
    else let e1 # s2 = findEntryAux s1 cap (fuel - 1) e.find
         in e1 # write s2 n e1

findEntry : (1 _ : Arr) -> Int -> Int -> Res NodeData (const Arr)
findEntry s cap n = findEntryAux s cap cap n

union : (1 _ : Arr) -> Int -> Int -> Int -> Arr
union s cap n1 n2 =
  let r1 # s1 = findEntry s cap n1
      r2 # s2 = findEntry s1 cap n2
  in if r1.find == r2.find then s2
     else if r1.rank < r2.rank then write s2 r1.find (MkNodeData r2.find 0)
     else if r1.rank == r2.rank
       then write (write s2 r1.find (MkNodeData r2.find 0)) r2.find (MkNodeData r2.find (r2.rank + 1))
       else write s2 r2.find (MkNodeData r1.find 0)

mkNodes : (1 _ : Arr) -> Int -> Int -> Arr
mkNodes s cap n = if n < cap then mkNodes (write s n (MkNodeData n 1)) cap (n + 1) else s

mergePackAux : (1 _ : Arr) -> Int -> Int -> Int -> Int -> Arr
mergePackAux s cap fuel n d =
  if fuel == 0 then s
  else if n + d < cap then mergePackAux (union s cap n (n + d)) cap (fuel - 1) (n + 1) d
  else s

mergePack : (1 _ : Arr) -> Int -> Int -> Arr
mergePack s cap d = mergePackAux s cap cap 0 d

numEqsAux : (1 _ : Arr) -> Int -> Int -> Int -> Int -> Res Int (const Arr)
numEqsAux s cap fuel n r =
  if fuel == 0 then r # s
  else if n < cap then
    let e # s1 = findEntry s cap n
    in numEqsAux s1 cap (fuel - 1) (n + 1) (if n == e.find then r else r + 1)
  else r # s

discard : (1 _ : Arr) -> ()
discard a = freeze a (\_ => ())

test : Int -> Int
test n =
  let 1 s = mkArray n (MkNodeData 0 0)
      1 s1 = mergePack (mergePack (mergePack (mergePack (mkNodes s n 0) n 50000) n 10000) n 5000) n 1000
      v # s2 = numEqsAux s1 n n 0 0
      () = discard s2
  in v

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
     else putStrLn ("ok " ++ show (test n))
