module Prog

import Prelude

-- Shifts of Integer constants, folded by calling the runtime: a right shift
-- is the floor of the quotient, a negative amount shifts the other way, and
-- 0 shifted left by an amount no word holds is 0. The amounts and values
-- cross the runtime's small integers at 2^62 and a word at 2^63 and 2^64,
-- each way and of each sign.

public export
shifted : List Integer
shifted =
  [ prim__shr_Integer (-7) 1, prim__shl_Integer 7 (-1)
  , prim__shl_Integer 0 100000000000000000000, prim__shr_Integer (-1) 100000000000000000000
  , prim__shl_Integer 1 64, prim__shr_Integer (-18446744073709551617) 64
  , prim__shl_Integer 1 61, prim__shl_Integer 1 62, prim__shl_Integer 1 63
  , prim__shl_Integer (-1) 62, prim__shl_Integer (-1) 63
  , prim__shr_Integer 4611686018427387904 62, prim__shr_Integer 4611686018427387903 62
  , prim__shr_Integer (-4611686018427387904) 62, prim__shr_Integer (-4611686018427387905) 62
  , prim__shr_Integer 18446744073709551616 1, prim__shl_Integer 9223372036854775807 1
  , prim__shl_Integer 5 0, prim__shr_Integer (-5) 0, prim__shr_Integer 7 (-62) ]
