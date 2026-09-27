module Prog

-- rule: IDR-DATA-1, IDR-DATA-2, IDR-DATA-3, IDR-CON-1, IDR-TAG-1, IDR-FIELD-1, IDR-MATCH-1
-- rule: LOW-DATA-1, LOW-DATA-2, LOW-DATA-3, LOW-SWITCH-1, LOW-ERASE-1, CORE-ERASE-1, ELIM-ERASE-3
public export
data Shape = Circle Int | Rect Int Int

public export
area : Shape -> Int
area (Circle r) = prim__mul_Int 3 (prim__mul_Int r r)
area (Rect w h) = prim__mul_Int w h

public export
keep : (0 witness : Int) -> Int -> Int
keep witness v = v

-- A loop longer than compile-time evaluation runs (ELIM-G-19), so its
-- result is known only at runtime and the code below is not folded away.
public export
countdown : Int -> Int
countdown 0 = 6
countdown n = countdown (prim__sub_Int n 1)

public export
main : Int
main = keep 99 (area (Rect (countdown 100000) 7))
