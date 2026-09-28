module Main

-- Numerical methods written against a user numeric interface, on a value
-- read at run time, diffed against the stock Chez backend.

import Arith
import Complex

%default partial

-- Exponentiation by squaring, for any Arith: Int, Double, Complex.
power : Arith a => a -> Int -> a
power x 0 = fromInt 1
power x n = if mod n 2 == 0 then let h = power x (div n 2) in h * h
            else x * power x (n - 1)

-- Newton's method for the k-th root.
root : Int -> Double -> Double
root k a = go a 60
  where
    go : Double -> Int -> Double
    go x 0 = x
    go x n = go ((toDouble (k - 1) * x + a / power x (k - 1)) / toDouble k) (n - 1)

-- Simpson's rule for sin on [a, b] with n (even) intervals.
simpson : Double -> Double -> Int -> Double
simpson a b n = (h / 3.0) * (sin a + sin b + go 1 0.0)
  where
    h : Double
    h = (b - a) / toDouble n
    go : Int -> Double -> Double
    go i acc = if i >= n then acc
               else go (i + 1) (acc + (if mod i 2 == 0 then 2.0 else 4.0) * sin (a + toDouble i * h))

-- Runge-Kutta 4 for y' = y on [0, 1], starting at 1: approximately e.
rk4 : Int -> Double
rk4 n = go 0 1.0
  where
    h : Double
    h = 1.0 / toDouble n
    go : Int -> Double -> Double
    go i y = if i >= n then y
             else let k1 = y
                      k2 = y + h / 2.0 * k1
                      k3 = y + h / 2.0 * k2
                      k4 = y + h * k3
                  in go (i + 1) (y + h / 6.0 * (k1 + 2.0 * k2 + 2.0 * k3 + k4))

-- The sum of n copies of x, naively and with Kahan's compensation.
naive : Double -> Int -> Double
naive x n = go n 0.0
  where
    go : Int -> Double -> Double
    go 0 s = s
    go i s = go (i - 1) (s + x)

kahan : Double -> Int -> Double
kahan x n = go n 0.0 0.0
  where
    go : Int -> Double -> Double -> Double
    go 0 s c = s
    go i s c = let y = x - c
                   t = s + y
               in go (i - 1) t ((t - s) - y)

-- Machin's formula, and the Leibniz series with n terms.
machin : Double
machin = 16.0 * atan (1.0 / 5.0) - 4.0 * atan (1.0 / 239.0)

leibniz : Int -> Double
leibniz n = 4.0 * go 0 0.0
  where
    go : Int -> Double -> Double
    go i acc = if i >= n then acc
               else go (i + 1) (acc + (if mod i 2 == 0 then 1.0 else -1.0) / toDouble (2 * i + 1))

-- The golden ratio as a continued fraction of depth n.
golden : Int -> Double
golden 0 = 1.0
golden n = 1.0 + 1.0 / golden (n - 1)

-- The length of the Collatz sequence from n.
collatz : Int -> Int -> Int
collatz 1 steps = steps
collatz n steps = collatz (if mod n 2 == 0 then div n 2 else 3 * n + 1) (steps + 1)

gcd : Int -> Int -> Int
gcd a 0 = a
gcd a b = gcd b (mod a b)

-- Mandelbrot iterations of c, up to limit.
escape : Complex -> Int -> Int
escape c limit = go (fromInt 0) 0
  where
    go : Complex -> Int -> Int
    go z i = if i >= limit then i
             else if magnitude2 z > 4.0 then i
             else go (z * z + c) (i + 1)

mandelRow : Double -> Int -> IO ()
mandelRow y x = if x >= 60 then putChar '\n'
  else do
    let c = MkComplex (-2.2 + toDouble x * 0.05) y
    let n = escape c 50
    putChar (if n >= 50 then '#' else if n > 8 then '+' else if n > 3 then '.' else ' ')
    mandelRow y (x + 1)

mandel : Int -> IO ()
mandel row = if row >= 24 then pure ()
  else do
    mandelRow (-1.2 + toDouble row * 0.1) 0
    mandel (row + 1)

main : IO ()
main = do
  c <- getChar
  let k = prim__sub_Int (prim__cast_CharInt c) 48
  let x = toDouble k
  label "sqrt" (root 2 x)
  label "cbrt" (root 3 (x * x * x))
  label "libm sqrt" (sqrt x)
  label "simpson" (simpson 0.0 (4.0 * atan 1.0) (k * 40))
  label "rk4" (rk4 (k * 20))
  label "e" (exp 1.0)
  label "naive" (naive 0.1 (k * 200000))
  label "kahan" (kahan 0.1 (k * 200000))
  label "machin" (machin + x - x)
  label "leibniz" (leibniz (k * 10000))
  label "golden" (golden (k * 8))
  label "power" (power 1.0001 (k * 2000))
  let z = power (MkComplex 0.6 (x / 10.0)) (k * 3)
  label "complex re" (re z)
  label "complex im" (im z)
  printInt (power 3 (k * 7))
  printInt (collatz (k * 5467) 0)
  printInt (gcd (k * 1071) (k * 462))
  printInt (truncate (x * 1234.5678))
  mandel 0
