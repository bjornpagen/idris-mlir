module Prog

-- A main : Int program exits with its value mod 256. That is the status
-- Chez gives the same value through exitWith, since libc's exit keeps the
-- low 8 bits: exitWith (ExitFailure 257) exits 1, and exitWith
-- (ExitFailure 256) exits 0. So 257 exits 1, not 0 and not 257.
main : Int
main = 257
