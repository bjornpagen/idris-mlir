module Prog

-- rule: LOW-TAIL-5, SEM-RES-2, LOW-TAIL-4
-- 10^8 self tail calls run in constant stack (the harness limits the stack
-- to 1 MiB). sum 1..10^8 = 5000000050000000, and 5000000050000000 mod 256
-- = 128. Idris cannot evaluate this at type-checking time (TEST-ORACLE-2).
sumTo : Int -> Int -> Int
sumTo 0 acc = acc
sumTo n acc = sumTo (prim__sub_Int n 1) (prim__add_Int acc n)

partial
main : Int
main = prim__mod_Int (sumTo 100000000 0) 256
