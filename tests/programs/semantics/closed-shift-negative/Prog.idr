module Prog

import Prelude

-- A right shift by a negative amount shifts left: -128 shifted left by one
-- is -256, which wraps to 0 as an Int8, so the comparison holds, though
-- every operand is a constant.

public export
shiftedOut : Int
shiftedOut = prim__eq_Int8 (prim__shr_Int8 (cast (-128)) (cast (-1))) (cast 0)
