-- expect: elaboration, line 17
module Main

-- A search whose goals grow without repeating: a G 0 is sought by Up1,
-- which asks a G 1, or by Up2, which asks a G 2, and every goal asks
-- larger ones, with no constructor that ends. Each goal holds an earlier
-- one, G 0 inside G 1, so the search is refused where the program asks
-- it, naming the goals, and ends by construction, with no count.

import Prelude

data G : Nat -> Type where
  Up1 : G (S n) -> G n
  Up2 : G (S (S n)) -> G n

x : G 0
x = %search

main : IO ()
main = printLn (the Int 1)
