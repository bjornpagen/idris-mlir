module Main

-- Showing a dependent pair: its Show takes the constraint
-- `{y : a} -> Show (p y)`, which reaches the instance as a function field
-- of the dictionary, and a projection applies that field past its own
-- arity. The instance is one the whole program fixes, so the program is
-- accepted and prints the pair, at each length it is used at: the empty
-- vector, one negative element (shown without parentheses, as a list's
-- elements are), and two.

import Prelude
import Data.Vect

main : IO ()
main = do
  printLn (the (n ** Vect n Int) (2 ** [1, 2]))
  printLn (the (n ** Vect n Int) (0 ** []))
  printLn (the (n ** Vect n Int) (1 ** [-1]))
