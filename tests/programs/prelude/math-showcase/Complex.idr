module Complex

import Arith

%default partial

public export
record Complex where
  constructor MkComplex
  re : Double
  im : Double

public export
Arith Complex where
  MkComplex a b + MkComplex c d = MkComplex (a + c) (b + d)
  MkComplex a b - MkComplex c d = MkComplex (a - c) (b - d)
  MkComplex a b * MkComplex c d = MkComplex (a * c - b * d) (a * d + b * c)
  negate (MkComplex a b) = MkComplex (negate a) (negate b)
  fromInt n = MkComplex (toDouble n) 0.0

public export
magnitude2 : Complex -> Double
magnitude2 (MkComplex a b) = a * a + b * b
