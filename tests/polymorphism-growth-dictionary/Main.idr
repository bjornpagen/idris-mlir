-- expect: polymorphism, line 15
-- message: growing it by 1 each round, and nothing bounds how far it grows
module Main

import Prelude

-- quote shows its value inside as many pairs of quotes as its count says:
-- each call passes itself the implementation quoted, built over the one it
-- was given, so its instances need Show Int, quoted over it, quoted over
-- that, one more for each count the run's input gives.

[quoted] Show a => Show a where
  show x = "'" ++ show x ++ "'"

quote : (sh : Show a) => Nat -> a -> String
quote Z x = show x
quote (S k) x = quote @{quoted} k x

main : IO ()
main = do
  line <- getLine
  putStrLn (quote (integerToNat (cast line)) (the Int 7))
