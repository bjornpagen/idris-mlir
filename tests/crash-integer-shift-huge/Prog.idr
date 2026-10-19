module Prog

import Prelude

-- 1 shifted left by 2^64 places needs 2^61 bytes: memory is exhausted at
-- run time, after the output before it, which a shift by 2^6 places, past
-- a word, gives. The amounts are a recursion's results, which the
-- elaborator's own constant folding does not reach: given the literal, it
-- would compute the shift while checking the program, before this
-- compiler sees it.

pow2 : Nat -> Integer
pow2 Z = 1
pow2 (S k) = 2 * pow2 k

export
small : Integer
small = prim__shl_Integer 1 (pow2 6)

export
result : Integer
result = prim__shl_Integer 1 (pow2 64)
