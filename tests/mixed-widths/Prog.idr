module Prog

-- One constructor holding four widths, read back each at its own width:
-- each field keeps its width's value, whatever its neighbours hold. The
-- values are each width's edges: its least, its greatest, and one past the
-- greatest, which the cast from Int wraps to the least (for Bits64, which
-- has no Int past it, Int's least, read as 2^63).

public export
data Packed = MkPacked Bits8 Int16 Bits64 Int32

public export
total' : Packed -> Int
total' (MkPacked a b c d) =
  prim__add_Int (prim__cast_Bits8Int a)
    (prim__add_Int (prim__cast_Int16Int b)
      (prim__add_Int (prim__cast_Bits64Int c) (prim__cast_Int32Int d)))

public export
result : Int
result = total' (MkPacked (prim__cast_IntBits8 200) (prim__cast_IntInt16 (-100)) (prim__cast_IntBits64 3) (prim__cast_IntInt32 7))

public export
least : Packed
least = MkPacked (prim__cast_IntBits8 0) (prim__cast_IntInt16 (-32768)) (prim__cast_IntBits64 0) (prim__cast_IntInt32 (-2147483648))

public export
greatest : Packed
greatest = MkPacked (prim__cast_IntBits8 255) (prim__cast_IntInt16 32767) (prim__cast_IntBits64 (-1)) (prim__cast_IntInt32 2147483647)

public export
past : Packed
past = MkPacked (prim__cast_IntBits8 256) (prim__cast_IntInt16 32768) (prim__cast_IntBits64 (-9223372036854775808)) (prim__cast_IntInt32 2147483648)

public export
byte : Packed -> Bits8
byte (MkPacked a _ _ _) = a

public export
short : Packed -> Int16
short (MkPacked _ b _ _) = b

public export
word : Packed -> Bits64
word (MkPacked _ _ c _) = c

public export
int : Packed -> Int32
int (MkPacked _ _ _ d) = d
