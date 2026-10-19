module Main

-- A Fin literal checked before its bound is known: the lambda is checked
-- first, at `Vect ?n Int`, so `2 : Fin ?n` is elaborated while ?n is a
-- hole, and only the vector after it fixes n = 3. Folding the literal's
-- conversion there stops halfway, inside base's Fin `fromInteger`, and the
-- erased proof of its where block, a believe_me, lands in main, which the
-- compiler refuses as an escape hatch; the literal must stay a call.

import Prelude
import Data.Vect

applyTo : (Vect n Int -> Int) -> Vect n Int -> Int
applyTo f xs = f xs

main : IO ()
main = printLn (applyTo (\v => index 2 v) [10, 20, 30])
