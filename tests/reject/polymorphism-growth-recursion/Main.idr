-- expect: polymorphism, line 19
-- message: passes n through the type-level recursion
module Main

import Prelude

-- Two n is a tuple of about n / 2 + 1 Ints, by a recursion that steps two
-- constructors at a time. From an n it does not know, what it computes
-- is no bounded shape of n, so the type of wrap's second argument is
-- stuck on wrap's first. wrap is called once, at a constant, and its one
-- instance is finite; the program is refused all the same, since nothing
-- in the program bounds what the recursion computes.

Two : Nat -> Type
Two Z = Int
Two (S Z) = Int
Two (S (S k)) = (Int, Two k)

wrap : (n : Nat) -> Two n -> Int -> Int
wrap n x k = k + cast n

main : IO ()
main = do
  line <- getLine
  printLn (wrap (S (S Z)) (1, 2) (cast line))
