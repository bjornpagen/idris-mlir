module Main

-- rule: SEM-REC-2, ELIM-G-5, PROF-IO-4
-- The Prelude's Applicative combinators over IO: `(*>)` is
-- `map (const id) a <*> b`, so running `a` yields an IORes holding a
-- function. IORes has one constructor, so matching it is not a choice: its
-- fields are read where the match is, and the function stays a
-- compile-time value. for_, traverse_ and sequence_ are built from `(*>)`.

import Prelude

main : IO ()
main = do
  c <- getChar
  let n = the Int (cast (ord c) - 48)
  putStr "a" *> putStrLn "b"
  for_ [1, 2, 3] (\i => printLn (i * n))
  traverse_ printLn [n, n + 1]
  for_ [1 .. 4] (\i => printLn (the Double (cast (i * n)) / 3.0))
  sequence_ [putStrLn "x", printLn n]
  when (n > 3) (putStrLn "big")
  unless (n > 3) (putStrLn "small")
