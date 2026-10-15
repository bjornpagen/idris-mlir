-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The fork's size-change decision (`loopsTerminate`) on small components,
||| each written as the Idris it stands for. A call's graph has a row for
||| each of the callee's arguments and a column for each of the caller's,
||| as the call graph builds it. A path's graph is the later call's graph
||| times the earlier's, so a decision that composed in the other order
||| would judge a component of three functions on a word that is no path:
||| the two cycles below are each other's mirror for that mistake.
module Main

import Algebra
import Algebra.SizeChange
import Core.Name
import Core.Termination.SizeChange
import Libraries.Data.SparseMatrix

u : SizeChange
u = Unknown

f, g, h : Name
f = UN (Basic "f")
g = UN (Basic "g")
h = UN (Basic "h")

-- f a b = g b 5; g x (S y) = h x y; h c d = f d c
-- diverges: f 4 b -> g b 5 -> h b 4 -> f 4 b
diverging : List (Name, Name, Matrix SizeChange)
diverging
    = [ (f, g, fromListList [[u, Same], [u, u]])         -- g0 = f1
      , (g, h, fromListList [[Same, u], [u, Smaller]])   -- h0 = g0, h1 < g1
      , (h, f, fromListList [[u, Same], [Same, u]]) ]    -- f0 = h1, f1 = h0

-- f a b = g a 0; g (S n) _ = h 0 n; h _ m = f m 0
-- terminates: the first argument goes f0 -> g0 -> h1 (smaller) -> f0
terminating : List (Name, Name, Matrix SizeChange)
terminating
    = [ (f, g, fromListList [[Same, u], [u, u]])         -- g0 = f0
      , (g, h, fromListList [[u, u], [Smaller, u]])      -- h1 < g0
      , (h, f, fromListList [[u, Same], [u, u]]) ]       -- f0 = h1

-- f (S a) b = f b a: swaps, and decreases the first only every other time
-- round; the second time round both are smaller.
swapping : List (Name, Name, Matrix SizeChange)
swapping = [ (f, f, fromListList [[u, Same], [Smaller, u]]) ]   -- f0 = f1, f1 < f0

-- f a b = f b a: swaps for ever.
swappingForEver : List (Name, Name, Matrix SizeChange)
swappingForEver = [ (f, f, fromListList [[u, Same], [Same, u]]) ]

main : IO ()
main = do
  putStrLn ("diverging 3-cycle: " ++ show (loopsTerminate diverging [f, g, h]))
  putStrLn ("terminating 3-cycle: " ++ show (loopsTerminate terminating [f, g, h]))
  putStrLn ("swapping: " ++ show (loopsTerminate swapping [f]))
  putStrLn ("swapping for ever: " ++ show (loopsTerminate swappingForEver [f]))
