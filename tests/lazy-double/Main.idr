module Main

import Prelude

-- Each step forces the previous suspension twice. One cell per step makes
-- that two reads of a stored value; a fresh run of the body at every force
-- is 2^n additions, 2^40 and more for the inputs here. The values cross the
-- largest small natural, 2^62, and a word, 2^64.

nat : Nat -> Lazy Nat
nat Z = 1
nat (S k) = let x = nat k in x + x

main : IO ()
main = do
  line <- getLine
  printLn (nat (cast line))
