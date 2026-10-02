module Prog

-- A crash reports a source location: the function whose operation failed,
-- the module having been loaded from its TTC, which keeps no location
-- inside a term.
partial
f : Int -> Int
f x = prim__div_Int 10 x

export partial
result : Int
result = f 0
