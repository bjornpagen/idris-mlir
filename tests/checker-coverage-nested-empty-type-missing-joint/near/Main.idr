module Main

-- The refused program with its missing case written.

import Prelude
import Data.Nat

%default total

data Head = MkHead (Maybe Nat) (List Nat)

upToOne : (r : Head) -> (ts : List Nat ** (r = MkHead Nothing ts, LTE (length ts) 1)) -> Bool
upToOne (MkHead Nothing []) ([] ** (Refl, _)) = True
upToOne (MkHead Nothing (_ :: _)) _ = False

partial
main : IO ()
main = do
  printLn (upToOne (MkHead Nothing []) ([] ** (Refl, LTEZero)))
  printLn (upToOne (MkHead Nothing [7]) ([7] ** (Refl, LTESucc LTEZero)))
