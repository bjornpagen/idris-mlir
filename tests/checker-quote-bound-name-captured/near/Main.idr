module Main

-- The refused program's equation made true: the left side's inner
-- function returns the outer `x` too, so the right side is the left one
-- eta-reduced. The eta step quotes `k (\y => x)` and keeps the
-- conversion's own name for `x` as itself under `y`.

import Prelude

%default total

0 etaReduced : (k : (Nat -> Nat) -> Nat -> Nat) ->
               (\x : Nat => \z : Nat => k (\y : Nat => x) z) = (\x : Nat => k (\y : Nat => x))
etaReduced k = Refl

main : IO ()
main = putStrLn "checked"
