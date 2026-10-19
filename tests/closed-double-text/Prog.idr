module Prog

import Prelude

-- A primitive applied to literals means what the runtime computes, as it
-- does on values read at run time. The text of 1.0 / 0.0 is IEEE 754's
-- `inf`, of -1.0 / 0.0 `-inf`, of 0.0 / 0.0 `nan`, and a product past the
-- largest double is `inf` too; the divisions are not covering, so those
-- constants are partial. A finite double's text is its fewest digits that
-- read back, at each end of the subnormals and of the range: the smallest
-- subnormal, `5e-324`, and its negation, the largest subnormal, the
-- smallest normal and the largest double.

public export partial
specials : List String
specials =
  [ prim__cast_DoubleString (prim__div_Double 1.0 0.0)
  , prim__cast_DoubleString (prim__div_Double (prim__negate_Double 1.0) 0.0)
  , prim__cast_DoubleString (prim__div_Double 0.0 0.0)
  , prim__cast_DoubleString (prim__mul_Double 1.0e308 10.0) ]

public export
ends : List String
ends =
  [ prim__cast_DoubleString 4.9e-324
  , prim__cast_DoubleString (prim__negate_Double 4.9e-324)
  , prim__cast_DoubleString 1.0e-323
  , prim__cast_DoubleString 2.225073858507201e-308
  , prim__cast_DoubleString 2.2250738585072014e-308
  , prim__cast_DoubleString 1.7976931348623157e308 ]
