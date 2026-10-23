module Binds

-- A do block of thirty pattern binds, in plain Idris over IO: no
-- linearity, no constraint. Each bind is a case block nested in the one
-- before, and each statement calls step with f's own arguments. Building
-- f's size-change graph compares each argument of each call with each of
-- f's argument patterns, which a call k binds deep sees wrapped in k as
-- patterns; on the stock Idris each such comparison took time doubling
-- with k.

%default total

step : Nat -> IO Nat -> IO (Nat, Nat)
step k op = do
  x <- op
  pure (x, k)

f : Nat -> IO Nat -> IO Nat
f k op = do
  (a0, b0) <- step k op
  (a1, b1) <- step k op
  (a2, b2) <- step k op
  (a3, b3) <- step k op
  (a4, b4) <- step k op
  (a5, b5) <- step k op
  (a6, b6) <- step k op
  (a7, b7) <- step k op
  (a8, b8) <- step k op
  (a9, b9) <- step k op
  (a10, b10) <- step k op
  (a11, b11) <- step k op
  (a12, b12) <- step k op
  (a13, b13) <- step k op
  (a14, b14) <- step k op
  (a15, b15) <- step k op
  (a16, b16) <- step k op
  (a17, b17) <- step k op
  (a18, b18) <- step k op
  (a19, b19) <- step k op
  (a20, b20) <- step k op
  (a21, b21) <- step k op
  (a22, b22) <- step k op
  (a23, b23) <- step k op
  (a24, b24) <- step k op
  (a25, b25) <- step k op
  (a26, b26) <- step k op
  (a27, b27) <- step k op
  (a28, b28) <- step k op
  (a29, b29) <- step k op
  pure (a0 + b29)
