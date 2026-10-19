module Main

import Prelude

-- Each step forces the previous suspension twice. One cell per step makes
-- that two reads of a stored value; a fresh run of the body at every force
-- is 2^40 additions.

nat : Nat -> Lazy Nat
nat Z = 1
nat (S k) = let x = nat k in x + x

main : IO ()
main = printLn (nat 40)
