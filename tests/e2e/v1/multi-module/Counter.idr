module Counter

export
count : Int -> Int
count 0 = 0
count n = prim__add_Int 2 (count (prim__sub_Int n 1))
