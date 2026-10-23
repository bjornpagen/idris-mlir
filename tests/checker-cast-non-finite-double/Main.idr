module Main

-- A Double cast to an integer means what the runtime says: a finite one is
-- truncated toward zero, and an infinity or NaN crashes the program that
-- casts it. The type checker's evaluator cast every Double by the host's
-- primitive, which on Chez truncates it exactly and raises on an infinity
-- or NaN, so a type that reached such a cast crashed the compiler. It now
-- leaves that cast applied, as it leaves any primitive it cannot fold.
-- Each type below reaches the casts on both its sides. The infinities are
-- written two ways, so the sides are one term only once both are
-- evaluated, each to the cast of one infinity, left applied; NaN is
-- written alike on both sides, since its division stays applied and no
-- NaN constant exists to compare. Checking
-- the types is the test. The run casts NaN, and crashes by the runtime's
-- cause after the line before it.

import Prelude

%default total

0 toInt : cast {to = Int} 1.0e309 = cast {to = Int} (1.0 / 0.0)
toInt = Refl

0 toInteger : cast {to = Integer} (-1.0e309) = cast {to = Integer} (-1.0 / 0.0)
toInteger = Refl

0 notANumber : cast {to = Int} (0.0 / 0.0) = cast {to = Int} (0.0 / 0.0)
notANumber = Refl

main : IO ()
main = do
  putStrLn "checked"
  printLn (prim__cast_DoubleInt (0.0 / 0.0))
