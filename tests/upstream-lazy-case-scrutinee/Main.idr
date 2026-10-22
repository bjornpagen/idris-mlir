module Main

-- A case block, and an if, written where a delayed value is expected. The
-- program delays the whole argument, the scrutinee with the rest, so
-- where the value is never forced the scrutinee is never computed. The
-- pinned Idris checks the block at the delayed type and delays each
-- alternative instead, which computes the scrutinee where the argument is
-- built: here a crash.
-- The stock Idris still has the bug (upstream/55-lazy-case-scrutinee);
-- the type checker (compiler/checker) fixes it as its own code, and this
-- test checks that fix.

import Prelude

partial
boom : Int -> Int
boom 0 = 5

pick : Lazy Int -> Int
pick _ = 1

-- Forced, the delayed block computes its scrutinee as before.
later : Lazy Int -> Int
later x = x + 1

partial
main : IO ()
main = do
  printLn (pick (case boom 1 of { 5 => 1; _ => 2 }))
  printLn (ifThenElse True (the Int 1) (if boom 1 == 5 then 2 else 3))
  printLn (later (case boom 0 of { 5 => 10; _ => 20 }))
  printLn (later (if boom 0 == 5 then 30 else 40))
