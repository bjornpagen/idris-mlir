module Main

-- Union-find with path compression and union by rank over an array of
-- records: Lean's `unionfind.lean` (Counting Immutable Beans), which
-- threads the array through a state monad and updates it in place while
-- unshared. Here the array is a growable linear vector (Linear.Vec) of
-- records, threaded at quantity 1 through every find and union: pure code,
-- each update a store of a freshly built record, as in Lean. Prints "ok"
-- and the number of nodes that are not roots. A node is compared with the
-- size where it is read or written; one past the end, which the checks
-- before it keep out, reads the error entry and writes nothing.

import Prelude
import Data.So
import Linear.Notation
import Array
import Linear.Vec

record NodeData where
  constructor MkNodeData
  find : Int
  rank : Int

Arr : Nat -> Type
Arr k = Vec k NodeData

-- The entry of node `i`; the error entry past the end.
readAt : {k : Nat} -> (1 _ : Arr k) -> Nat -> Res NodeData (const (Arr k))
readAt s i = case choose (i < k) of
  Left inside => Vec.read s (natToFinLt i @{inside})
  Right _ => MkNodeData (-2) 0 # s

-- The vector with `e` at node `i`; as it was past the end.
writeAt : {k : Nat} -> (1 _ : Arr k) -> Nat -> NodeData -> Arr k
writeAt s i e = case choose (i < k) of
  Left inside => Vec.write s (natToFinLt i @{inside}) e
  Right _ => s

-- The entry of n's root, found with at most fuel steps; every entry on the
-- path is replaced by the root's. A node out of range, or a chain longer
-- than the fuel, is an error, as in Lean.
findEntryAux : {k : Nat} -> (1 _ : Arr k) -> Int -> Int -> Int -> Res NodeData (const (Arr k))
findEntryAux s cap fuel n =
  if fuel == 0 then MkNodeData (-1) 0 # s
  else if n < 0 || n >= cap then MkNodeData (-2) 0 # s
  else
    let e # s1 = readAt s (cast n) in
    if e.find == n then e # s1
    else let e1 # s2 = findEntryAux s1 cap (fuel - 1) e.find
         in e1 # writeAt s2 (cast n) e1

findEntry : {k : Nat} -> (1 _ : Arr k) -> Int -> Int -> Res NodeData (const (Arr k))
findEntry s cap n = findEntryAux s cap cap n

union : {k : Nat} -> (1 _ : Arr k) -> Int -> Int -> Int -> Arr k
union s cap n1 n2 =
  let r1 # s1 = findEntry s cap n1
      r2 # s2 = findEntry s1 cap n2
  in if r1.find == r2.find then s2
     else if r1.rank < r2.rank then writeAt s2 (cast r1.find) (MkNodeData r2.find 0)
     else if r1.rank == r2.rank
       then writeAt (writeAt s2 (cast r1.find) (MkNodeData r2.find 0)) (cast r2.find) (MkNodeData r2.find (r2.rank + 1))
       else writeAt s2 (cast r2.find) (MkNodeData r1.find 0)

mkNodes : {k : Nat} -> (1 _ : Arr k) -> Int -> Int -> Arr k
mkNodes s cap n = if n < cap then mkNodes (writeAt s (cast n) (MkNodeData n 1)) cap (n + 1) else s

mergePackAux : {k : Nat} -> (1 _ : Arr k) -> Int -> Int -> Int -> Int -> Arr k
mergePackAux s cap fuel n d =
  if fuel == 0 then s
  else if n + d < cap then mergePackAux (union s cap n (n + d)) cap (fuel - 1) (n + 1) d
  else s

mergePack : {k : Nat} -> (1 _ : Arr k) -> Int -> Int -> Arr k
mergePack s cap d = mergePackAux s cap cap 0 d

numEqsAux : {k : Nat} -> (1 _ : Arr k) -> Int -> Int -> Int -> Int -> Res Int (const (Arr k))
numEqsAux s cap fuel n r =
  if fuel == 0 then r # s
  else if n < cap then
    let e # s1 = findEntry s cap n
    in numEqsAux s1 cap (fuel - 1) (n + 1) (if n == e.find then r else r + 1)
  else r # s

discard : (1 _ : Arr k) -> ()
discard a = let MkBang _ = Vec.freeze a in ()

test : Int -> Int
test n = unrestricted $ withVec (cast n) (MkNodeData 0 0) (\s =>
  let 1 s1 = mergePack (mergePack (mergePack (mergePack (mkNodes s n 0) n 50000) n 10000) n 5000) n 1000
      v # s2 = numEqsAux s1 n n 0 0
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
     else putStrLn ("ok " ++ show (test n))
