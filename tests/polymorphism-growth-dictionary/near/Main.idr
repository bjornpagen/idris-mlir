module Main

import Prelude

-- The refused program with the implementation passed on as given: main
-- gives quote the quoted implementation over Show Int, once, and every
-- round passes it on, so whatever the count it shows 7 in one pair of
-- quotes.

[quoted] Show a => Show a where
  show x = "'" ++ show x ++ "'"

quote : (sh : Show a) => Nat -> a -> String
quote Z x = show x
quote (S k) x = quote @{sh} k x

main : IO ()
main = do
  line <- getLine
  putStrLn (quote @{quoted} (integerToNat (cast line)) (the Int 7))
