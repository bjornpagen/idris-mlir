module Prog

public export
data Shape = Circle Int | Rect Int Int

public export
area : Shape -> Int
area (Circle r) = prim__mul_Int 3 (prim__mul_Int r r)
area (Rect w h) = prim__mul_Int w h

public export
keep : (0 witness : Int) -> Int -> Int
keep witness v = v

-- A loop on an Int, which Idris does not prove terminating: a closed call,
-- which runs at run time.
public export
countdown : Int -> Int
countdown 0 = 6
countdown n = countdown (prim__sub_Int n 1)

-- Both shapes' areas, the circle's in the thousands, so that each is read
-- off the one number printed.
public export
result : Int
result = prim__add_Int (keep 99 (area (Rect (countdown 100000) 7))) (prim__mul_Int 1000 (area (Circle 2)))
