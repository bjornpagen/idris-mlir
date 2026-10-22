module Main

-- A method whose let-bound helper is polymorphic, its constraint the
-- method's own interface, and calls the same method at another type: the
-- Nat implementation describes a Bool through the Bool implementation.

import Prelude

interface Describe a where
  describe : a -> String

Describe Bool where
  describe True = "yes"
  describe False = "no"

Describe Nat where
  describe n =
    let tag : {0 b : Type} -> Describe b => b -> String
        tag x = "<" ++ describe x ++ ">"
    in tag (n == 0) ++ show n

main : IO ()
main = do
  line <- getLine
  putStrLn (describe (the Nat (cast line)))
