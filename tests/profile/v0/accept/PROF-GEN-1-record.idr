-- exit: 20
module Main

-- rule: PROF-GEN-3, PROF-TERM-1, SEM-DATA-1
record Point where
  constructor MkPoint
  x : Int
  y : Int

area : Point -> Int
area p = prim__mul_Int p.x p.y

main : Int
main = area (MkPoint 4 5)
