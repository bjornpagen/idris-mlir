-- expect: polymorphism, line 16
-- message: (Main.quoted a sh)
module Main

import Prelude

-- quote shows its value inside as many pairs of quotes as its count says:
-- each call passes itself the implementation quoted, built over the one it
-- was given, so its instances need Show Int, quoted over it, quoted over
-- that, one more for each count the run's input gives. near/ quotes once,
-- at main, and passes the implementation it is given on unchanged.

[quoted] Show a => Show a where
  show x = "'" ++ show x ++ "'"

quote : (sh : Show a) => Nat -> a -> String
quote Z x = show x
quote (S k) x = quote @{quoted} k x

main : IO ()
main = do
  line <- getLine
  putStrLn (quote (integerToNat (cast line)) (the Int 7))
