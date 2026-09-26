module Prog

-- rule: IDR-MATCH-3, FE-TR-3, FE-TR-4, IDR-IN-1, IDR-IN-2
public export
classify : Int -> Int
classify 0 = 10
classify 1 = 20
classify 250 = 30
classify _ = 40

public export
main : Int
main = prim__add_Int (classify 250) (prim__add_Int (classify 1) (classify 7))
