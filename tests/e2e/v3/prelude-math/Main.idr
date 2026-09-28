module Main

-- rule: PROF-PROG-4, FE-TR-6, SEM-DBL-2, ELIM-SPEC-1, ELIM-EVAL-1, SEM-IO-7
-- Complex numbers as an ordinary user type with the Prelude's own Num, Neg,
-- Fractional and Show interfaces, generic code over Num and Integral, the
-- Mandelbrot set, and the basins of Newton's method for z^3 = 1, on a value
-- read at runtime with the Prelude's getChar. Written the way an Idris
-- programmer would, and diffed against the stock Chez backend.
-- `euclid (the Integer 48) 18` is gone since the cutover (docs/cutover.md
-- 4.3, decision 7.2, a PROF-GEN-4 exception): `euclid` is partial, so it is
-- not evaluated, and its Integer would exist at runtime
-- (profile/v3/reject/PROF-TYPE-4-partial-integer). The line that printed
-- the pair `(21, 6)` prints `21`.

import Prelude

%default partial

record Complex where
  constructor MkC
  re : Double
  im : Double

Num Complex where
  MkC a b + MkC c d = MkC (a + c) (b + d)
  MkC a b * MkC c d = MkC (a * c - b * d) (a * d + b * c)
  fromInteger n = MkC (fromInteger n) 0.0

Neg Complex where
  negate (MkC a b) = MkC (negate a) (negate b)
  MkC a b - MkC c d = MkC (a - c) (b - d)

Show Complex where
  show (MkC a b) = show a ++ " + " ++ show b ++ "i"

Fractional Complex where
  MkC a b / MkC c d = let m = c * c + d * d in MkC ((a * c + b * d) / m) ((b * c - a * d) / m)

magnitude2 : Complex -> Double
magnitude2 (MkC a b) = a * a + b * b

power : Num a => a -> Nat -> a
power x Z = 1
power x (S k) = x * power x k

escape : Complex -> Int -> Int
escape c limit = go 0 0
  where
    go : Complex -> Int -> Int
    go z i = if i >= limit || magnitude2 z > 4.0 then i else go (z * z + c) (i + 1)

row : Double -> Int -> Int -> IO ()
row y w x = if x >= w then putChar '\n' else do
  let k = escape (MkC (-2.0 + 2.5 * cast x / cast w) y) 50
  putChar (if k >= 50 then '#' else if k > 8 then '+' else '.')
  row y w (x + 1)

picture : Int -> Int -> IO ()
picture h y = if y >= h then pure () else do
  row (-1.2 + 2.4 * cast y / cast h) (2 * h) 0
  picture h (y + 1)

-- Newton's method for z^3 = 1: which root does z converge to?
basin : Complex -> Int -> Char
basin z 0 = '?'
basin z k =
  let z' = z - (z * z * z - 1) / (3 * z * z) in
  if magnitude2 (z' - 1) < 1.0e-6 then 'a'
  else if magnitude2 (z' - MkC (-0.5) (sqrt 3.0 / 2.0)) < 1.0e-6 then 'b'
  else if magnitude2 (z' - MkC (-0.5) (negate (sqrt 3.0 / 2.0))) < 1.0e-6 then 'c'
  else basin z' (k - 1)

basins : Int -> Int -> Int -> IO ()
basins h y x =
  if y >= h then pure ()
  else if x >= 2 * h then do putChar '\n'; basins h (y + 1) 0
  else do
    putChar (basin (MkC (-1.5 + 3.0 * cast x / cast (2 * h)) (-1.5 + 3.0 * cast y / cast h)) 40)
    basins h y (x + 1)

euclid : Integral a => Eq a => a -> a -> a
euclid a b = if b == 0 then a else euclid b (a `mod` b)

sumTo : Num a => Int -> (Int -> a) -> a
sumTo 0 f = 0
sumTo n f = f n + sumTo (n - 1) f

main : IO ()
main = do
  c <- getChar
  let n = the Int (cast (ord c) - 48)
  let z = MkC (cast n / 10.0) 0.5
  printLn z
  printLn (power z 3)
  printLn (power (the Double (cast n)) 4)
  printLn (power n 5)
  printLn (z - negate z * 2)
  printLn (magnitude2 (power z 8))
  printLn (sumTo (n * 100) (\i => 1.0 / (the Double (cast i) * cast i)))
  printLn (sumTo n (\i => MkC (cast i) 1.0))
  printLn (sqrt 2.0 * exp 1.0, sin (cast n))
  picture (n * 2) 0
  printLn (z / MkC 1.0 2.0)
  printLn (recip z * z)
  printLn (euclid (n * 462) 1071)
  printLn (abs (negate n), abs (the Double (cast n) - 9.0))
  basins (n * 2) 0 0
