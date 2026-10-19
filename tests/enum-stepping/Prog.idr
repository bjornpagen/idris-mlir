module Prog

public export
data Day = Mon | Tue | Wed | Thu | Fri | Sat | Sun

public export
next : Day -> Day
next Mon = Tue
next Tue = Wed
next Wed = Thu
next Thu = Fri
next Fri = Sat
next Sat = Sun
next Sun = Mon

public export
index : Day -> Int
index Mon = 0
index Tue = 1
index Wed = 2
index Thu = 3
index Fri = 4
index Sat = 5
index Sun = 6

public export
stepN : Int -> Day -> Day
stepN 0 d = d
stepN n d = stepN (prim__sub_Int n 1) (next d)

public export
result : Int
result = index (stepN 10 Mon)
