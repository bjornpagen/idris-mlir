module Main

-- A function held in a variable takes some arguments with quantity 0:
-- those are passed erased, never computed. Base's `uncurry` for `Subset`
-- applies its function to the subset's proof (`f s.fst s.snd`), which has
-- no runtime value.

import Prelude
import Data.DPair

describe : (x : Nat) -> (0 _ : x = x) -> String
describe x _ = show x

main : IO ()
main = do
  line <- getLine
  putStrLn (uncurry describe (Element (length line) Refl))
