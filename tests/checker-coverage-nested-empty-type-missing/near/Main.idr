module Main

-- The refused program with its missing case written.

import Prelude
import Data.Nat

%default total

below : (c : Nat) -> (Nat, LTE c 1) -> Bool
below _ (_, LTEZero) = True
below (S _) _ = False

partial
main : IO ()
main = do
  printLn (below 0 (5, LTEZero))
  printLn (below 1 (5, LTESucc LTEZero))
