module Main

-- A runtime argument keyed by its shape (the rest of `describe`'s type
-- reduces on it), whose expression calls a function nothing else calls:
-- the argument is passed at run time and computed where it stands, so
-- the call inside it is a call of the program like any other.

import Prelude

Payload : Nat -> Type
Payload Z = Int
Payload (S k) = String

describe : (n : Nat) -> Payload n -> String
describe Z x = show x
describe (S k) s = s

count : List a -> Nat
count [] = Z
count (_ :: xs) = S (count xs)

main : IO ()
main = do
  let xs = the (List Int) [1, 2, 3]
  putStrLn (describe (S (count xs)) "three")
