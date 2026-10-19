module Prog

public export
record Point where
  constructor MkPoint
  x : Int
  y : Int

public export
data Shape = Circle Point Int | Rect Point Point

public export
add : Point -> Point -> Point
add p q = MkPoint (prim__add_Int p.x q.x) (prim__add_Int p.y q.y)

public export
width : Shape -> Int
width (Circle _ r) = prim__mul_Int 2 r
width (Rect a b) = prim__sub_Int b.x a.x

public export
result : Int
result = prim__add_Int (width (Rect (MkPoint 1 2) (add (MkPoint 10 20) (MkPoint 5 5)))) (width (Circle (MkPoint 0 0) 3))
