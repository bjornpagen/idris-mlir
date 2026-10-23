module Main

-- A polymorphic function held in a field whose type names the field
-- before it only as an index. Its choice is keyed by its type with the
-- indices erased, as a data value's family is, so the functions put there
-- at different lengths are one closed sum; each is chosen at run time and
-- applied at two types where it is held.

import Prelude
import Data.Vect

data Picker : Type where
  MkPicker : (n : Nat) -> ({0 a : Type} -> Vect n a -> Maybe a) -> Picker

firstOf : {0 a : Type} -> Vect n a -> Maybe a
firstOf [] = Nothing
firstOf (x :: _) = Just x

lastOf : {0 a : Type} -> Vect n a -> Maybe a
lastOf [] = Nothing
lastOf [x] = Just x
lastOf (_ :: x :: xs) = lastOf (x :: xs)

countdown : (n : Nat) -> Vect n Int
countdown Z = []
countdown (S k) = cast (S k) :: countdown k

use : Picker -> (Maybe Int, Maybe String)
use (MkPicker n f) = (f (countdown n), f (map show (countdown n)))

main : IO ()
main = do
  line <- getLine
  let p = if line == "first" then MkPicker 3 firstOf
            else if line == "last" then MkPicker 2 lastOf
            else MkPicker 0 firstOf
  printLn (use p)
