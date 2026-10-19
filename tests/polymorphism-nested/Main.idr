-- expect: polymorphism, line 12
-- message: growing it by 1 each round, and nothing bounds how far it grows
module Main

import Prelude

-- depth calls itself at a pair of what it was given, so the types its
-- instances need are Char, (Char, Char), ((Char, Char), (Char, Char)),
-- ..., one level deeper at each round, as many as its count says. The
-- program is refused, naming that growth.

depth : Int -> a -> Int
depth 0 _ = 0
depth n x = prim__add_Int 1 (depth (prim__sub_Int n 1) (MkPair x x))

main : IO ()
main = putStrLn (prim__cast_IntString (depth 3 'c'))
