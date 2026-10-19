module Prog

import Prelude

-- Shifts of Integer constants, folded by calling the runtime: a right shift
-- is the floor of the quotient, a negative amount shifts the other way, and
-- 0 shifted left by an amount no word holds is 0.

public export
shifted : List Integer
shifted =
  [ prim__shr_Integer (-7) 1, prim__shl_Integer 7 (-1)
  , prim__shl_Integer 0 100000000000000000000, prim__shr_Integer (-1) 100000000000000000000
  , prim__shl_Integer 1 64, prim__shr_Integer (-18446744073709551617) 64 ]
