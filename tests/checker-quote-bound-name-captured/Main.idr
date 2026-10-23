-- expect: elaboration, line 24
module Main

-- A false equation: the left side's inner function returns its own
-- argument, the right side's the outer `x`. The conversion check names
-- each binder it goes under, `x` first, and its eta step quotes the right
-- side's body, `k (\y => x)`, naming the quotation's binder `y` afresh,
-- first too: both count from zero. The quotation took a bound name for
-- its binder of the same number, so `x` became `y`, the two sides one
-- term, and the equation was accepted. A bound name is now a quotation's
-- binder only when it is that binder's whole name, as every other reader
-- of a bound name takes it, and the equation is refused where it is
-- proved. The compiler's frontend met the same capture with its own bound
-- names (a field type `Vect n a` under its `{0 a : Type}` came back `Vect
-- a a`); this is the type checker's own case of it. The stock Idris
-- accepts this.

import Prelude

%default total

0 wrong : (k : (Nat -> Nat) -> Nat -> Nat) ->
          (\x : Nat => \z : Nat => k (\y : Nat => y) z) = (\x : Nat => k (\y : Nat => x))
wrong k = Refl

main : IO ()
main = putStrLn "unreached"
