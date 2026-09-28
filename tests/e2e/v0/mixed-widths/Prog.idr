module Prog

public export
data Packed = MkPacked Bits8 Int16 Bits64 Int32

public export
total' : Packed -> Int
total' (MkPacked a b c d) =
  prim__add_Int (prim__cast_Bits8Int a)
    (prim__add_Int (prim__cast_Int16Int b)
      (prim__add_Int (prim__cast_Bits64Int c) (prim__cast_Int32Int d)))

public export
main : Int
main = total' (MkPacked (prim__cast_IntBits8 200) (prim__cast_IntInt16 (-100)) (prim__cast_IntBits64 3) (prim__cast_IntInt32 7))
