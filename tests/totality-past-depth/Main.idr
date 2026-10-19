module Main

-- A recursion whose argument is smaller only under six matching
-- constructors is total, as one under four is: whether a function is
-- total is a fact of the program, not of a count of constructors the
-- checker looks under, and no pragma says how deep to look. Each counts
-- the elements past its depth: none of the empty list, none at the depth
-- itself, one past it.

import Prelude

%default total

deep : List a -> Nat
deep (a :: b :: c :: d :: e :: f :: g :: es) = S (deep (a :: b :: c :: d :: e :: f :: es))
deep _ = 0

shallow : List a -> Nat
shallow (a :: b :: c :: d :: e :: es) = S (shallow (a :: b :: c :: d :: es))
shallow _ = 0

main : IO ()
main = do
  printLn (deep [the Int 1, 2, 3, 4, 5, 6, 7, 8, 9])
  printLn (shallow [the Int 1, 2, 3, 4, 5, 6, 7, 8, 9])
  printLn (deep (the (List Int) []), shallow (the (List Int) []))
  printLn (deep [the Int 1, 2, 3, 4, 5, 6], shallow [the Int 1, 2, 3, 4])
  printLn (deep [the Int 1, 2, 3, 4, 5, 6, 7], shallow [the Int 1, 2, 3, 4, 5])
