-- expect: hook, line 19
-- message: Linear.Nat.LNat
module Main

-- Linear.Nat is the program's own module here, named as the module of
-- mlir-linear whose LNat the registry promises is rebuilt in place. Only a
-- type with exactly one constructor that holds fields keeps that promise:
-- its cell is the one each rebuild takes. This LNat has two, so the entry
-- does not meet the type, and the program is refused where it first holds
-- one.
import Prelude
import Linear.Nat

isZero : LNat -> Bool
isZero Zero = True
isZero _ = False

main : IO ()
main = printLn (isZero (Succ (Twice Zero)))
