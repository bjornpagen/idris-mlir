module Main

-- The same program, its LNat with one constructor that holds fields, as
-- the promise needs: accepted.
import Prelude
import Linear.Nat

isZero : LNat -> Bool
isZero Zero = True
isZero _ = False

main : IO ()
main = printLn (isZero (Succ (Succ Zero)))
