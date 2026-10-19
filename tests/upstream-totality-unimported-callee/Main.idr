module Main

import Prelude

-- Neither Loop nor Count is imported: each is reached through a covering
-- function of a module that imports it, so the check that follows the call
-- reads the callee from the modules ViaLoop and ViaCount import.
import ViaLoop
import ViaCount

%default total

-- Loop.loop, which never returns, through ViaLoop.viaLoop.
caller : Nat -> Nat
caller x = viaLoop x

-- Count.count, total, through ViaCount.viaCount.
counted : Nat -> Nat
counted x = viaCount x

main : IO ()
main = printLn (counted 3)
