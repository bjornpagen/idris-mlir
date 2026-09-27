module Main

-- Union-find with path compression and union by rank over an array of
-- records. Lean's `unionfind.lean` (Counting Immutable Beans), which threads
-- the array through a state monad and updates it in place while unshared;
-- here the array is base's array primitive, updated in IO. Every update
-- stores a freshly built record, as in Lean. Prints "ok" and the number of
-- nodes that are not roots.

import Prelude
import Data.IOArray.Prims
import System

record NodeData where
  constructor MkNodeData
  find : Int
  rank : Int

Arr : Type
Arr = ArrayData NodeData

get : Arr -> Int -> IO NodeData
get a i = primIO (prim__arrayGet a i)

set : Arr -> Int -> NodeData -> IO ()
set a i x = primIO (prim__arraySet a i x)

failWith : String -> IO a
failWith e = do
  putStrLn ("Error : " ++ e)
  exitWith (ExitFailure 1)

-- The entry of n's root, found with at most fuel steps; every entry on the
-- path is replaced by the root's.
findEntryAux : Arr -> Int -> Int -> Int -> IO NodeData
findEntryAux s cap fuel n =
  if fuel == 0 then failWith "out of fuel"
  else if n < 0 || n >= cap then failWith "invalid Node"
  else do
    e <- get s n
    if e.find == n
      then pure e
      else do
        e1 <- findEntryAux s cap (fuel - 1) e.find
        set s n e1
        pure e1

findEntry : Arr -> Int -> Int -> IO NodeData
findEntry s cap n = findEntryAux s cap cap n

union : Arr -> Int -> Int -> Int -> IO ()
union s cap n1 n2 = do
  r1 <- findEntry s cap n1
  r2 <- findEntry s cap n2
  if r1.find == r2.find
    then pure ()
    else if r1.rank < r2.rank
      then set s r1.find (MkNodeData r2.find 0)
      else if r1.rank == r2.rank
        then do
          set s r1.find (MkNodeData r2.find 0)
          set s r2.find (MkNodeData r2.find (r2.rank + 1))
        else set s r2.find (MkNodeData r1.find 0)

mkNodes : Arr -> Int -> Int -> IO ()
mkNodes s cap n = if n < cap then do set s n (MkNodeData n 1); mkNodes s cap (n + 1) else pure ()

mergePackAux : Arr -> Int -> Int -> Int -> Int -> IO ()
mergePackAux s cap fuel n d =
  if fuel == 0 then pure ()
  else if n + d < cap then do
    union s cap n (n + d)
    mergePackAux s cap (fuel - 1) (n + 1) d
  else pure ()

mergePack : Arr -> Int -> Int -> IO ()
mergePack s cap d = mergePackAux s cap cap 0 d

numEqsAux : Arr -> Int -> Int -> Int -> Int -> IO Int
numEqsAux s cap fuel n r =
  if fuel == 0 then pure r
  else if n < cap then do
    e <- findEntry s cap n
    numEqsAux s cap (fuel - 1) (n + 1) (if n == e.find then r else r + 1)
  else pure r

test : Int -> IO Int
test n =
  if n < 2 then failWith "input must be greater than 1"
  else do
    s <- primIO (prim__newArray n (MkNodeData 0 0))
    mkNodes s n 0
    mergePack s n 50000
    mergePack s n 10000
    mergePack s n 5000
    mergePack s n 1000
    numEqsAux s n n 0 0

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
  v <- test n
  putStrLn ("ok " ++ show v)
