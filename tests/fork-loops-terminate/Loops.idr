-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The fork's size-change decision (`loopsTerminate`) on small components,
||| each written as the Idris it stands for. A call's graph has a row for
||| each of the callee's arguments and a column for each of the caller's,
||| as the call graph builds it. A path's graph is the later call's graph
||| times the earlier's, so a decision that composed in the other order
||| would judge a component of three functions on a word that is no path:
||| the two cycles below are each other's mirror for that mistake. A loop
||| the decision says goes round for ever is one the component's calls
||| make, from the function back to it, or the verdict says it is not.
module Main

import Algebra
import Algebra.SizeChange
import Core.Context
import Core.Termination.SizeChange
import Data.String
import Libraries.Data.SparseMatrix

u : SizeChange
u = Unknown

||| The three functions' names, their texts interned in one table seeded as
||| a session's is, so no two share an identifier.
names : (Name, Name, Name)
names =
  let (fi, t1) = internIn "f" seeded
      (gi, t2) = internIn "g" t1
      (hi, _) = internIn "h" t2
  in (UN (Basic fi), UN (Basic gi), UN (Basic hi))

f, g, h : Name
f = fst names
g = fst (snd names)
h = snd (snd names)

||| The call `caller` makes to `callee`, with its graph, made at no place
||| of a source.
call : Name -> Name -> List (List SizeChange) -> (Name, SCCall)
call caller callee graph = (caller, MkSCCall callee (fromListList graph) EmptyFC)

-- f a b = g b 5; g x (S y) = h x y; h c d = f d c
-- diverges: f 4 b -> g b 5 -> h b 4 -> f 4 b
diverging : List (Name, SCCall)
diverging
    = [ call f g [[u, Same], [u, u]]         -- g0 = f1
      , call g h [[Same, u], [u, Smaller]]   -- h0 = g0, h1 < g1
      , call h f [[u, Same], [Same, u]] ]    -- f0 = h1, f1 = h0

-- f a b = g a 0; g (S n) _ = h 0 n; h _ m = f m 0
-- terminates: the first argument goes f0 -> g0 -> h1 (smaller) -> f0
terminating : List (Name, SCCall)
terminating
    = [ call f g [[Same, u], [u, u]]         -- g0 = f0
      , call g h [[u, u], [Smaller, u]]      -- h1 < g0
      , call h f [[u, Same], [u, u]] ]       -- f0 = h1

-- f (S a) b = f b a: swaps, and decreases the first only every other time
-- round; the second time round both are smaller.
swapping : List (Name, SCCall)
swapping = [ call f f [[u, Same], [Smaller, u]] ]   -- f0 = f1, f1 < f0

-- f a b = f b a: swaps for ever.
swappingForEver : List (Name, SCCall)
swappingForEver = [ call f f [[u, Same], [Same, u]] ]

||| Do these calls, in order, go from `start` back to it by calls the
||| component makes: the first made by `start`, each later one by the
||| function the one before it called, and the last calling `start`?
closesAt : List (Name, SCCall) -> (start : Name) -> List (FC, Name) -> Bool
closesAt calls start [] = False
closesAt calls start loop = from start loop
  where
    from : Name -> List (FC, Name) -> Bool
    from at [] = at == start
    from at ((_, callee) :: rest)
        = any (\(caller, c) => caller == at && fnCall c == callee) calls && from callee rest

verdict : List (Name, SCCall) -> (Name, Loops) -> String
verdict calls (fn, Decreasing) = show fn ++ " decreases"
verdict calls (fn, Endless loop)
    = show fn ++ (if closesAt calls fn (callSeq loop)
                     then " goes round for ever"
                     else " goes round for ever by calls its component does not make")

judged : List (Name, SCCall) -> List Name -> String
judged calls members = joinBy ", " (map (verdict calls) (loopsTerminate calls members))

main : IO ()
main = do
  putStrLn ("diverging 3-cycle: " ++ judged diverging [f, g, h])
  putStrLn ("terminating 3-cycle: " ++ judged terminating [f, g, h])
  putStrLn ("swapping: " ++ judged swapping [f])
  putStrLn ("swapping for ever: " ++ judged swappingForEver [f])
