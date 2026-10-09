module Prog

-- 10^8 self tail calls run in constant stack (the harness limits the stack
-- to 1 MiB). sum 1..10^8 = 5000000050000000. Compile-time evaluation stops
-- it when it has spent its budget, so the loop runs at runtime.
sumTo : Int -> Int -> Int
sumTo 0 acc = acc
sumTo n acc = sumTo (prim__sub_Int n 1) (prim__add_Int acc n)

export partial
result : Int
result = sumTo 100000000 0
