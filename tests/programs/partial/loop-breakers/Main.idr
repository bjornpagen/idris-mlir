module Main

-- Two functions that call each other form one strongly connected
-- component: the first is its loop breaker, which the inliner leaves alone,
-- so the other is inlined into it and it becomes self recursive.

import Prelude

mutual
  even : Int -> Int
  even 0 = 1
  even n = odd (prim__sub_Int n 1)

  odd : Int -> Int
  odd 0 = 0
  odd n = even (prim__sub_Int n 1)

partial
main : IO ()
main = do
  c <- getChar
  putStrLn (prim__cast_IntString (even (prim__sub_Int (prim__cast_CharInt c) 48)))
