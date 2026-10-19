module Main

-- Generic exponentiation by squaring over a user Ring, with a constrained
-- implementation for 2x2 matrices: Fibonacci numbers from matrix powers.
-- The powers 0 and 1 take each base case; 3^39 and fib 92 are the largest
-- that an Int holds, and fib 93 is past it, wrapped as Int arithmetic is.

import Builtin
import Prelude

interface Ring a where
  zero : a
  one : a
  add : a -> a -> a
  mul : a -> a -> a

Ring Int where
  zero = 0
  one = 1
  add = prim__add_Int
  mul = prim__mul_Int

record M2 a where
  constructor MkM2
  a11 : a
  a12 : a
  a21 : a
  a22 : a

Ring a => Ring (M2 a) where
  zero = MkM2 zero zero zero zero
  one = MkM2 one zero zero one
  add (MkM2 a b c d) (MkM2 e f g h) = MkM2 (add a e) (add b f) (add c g) (add d h)
  mul (MkM2 a b c d) (MkM2 e f g h) =
    MkM2 (add (mul a e) (mul b g)) (add (mul a f) (mul b h))
         (add (mul c e) (mul d g)) (add (mul c f) (mul d h))

partial
power : Ring a => a -> Int -> a
power x 0 = one
power x n = case prim__mod_Int n 2 of
  0 => let h = power x (prim__div_Int n 2) in mul h h
  _ => mul x (power x (prim__sub_Int n 1))

three : Int
three = 3

partial
fib : Int -> Int
fib n = a12 (power (MkM2 1 1 1 0) n)

partial
main : IO ()
main = do
  putStrLn (prim__cast_IntString (power three 13))
  putStrLn (prim__cast_IntString (fib 10))
  putStrLn (prim__cast_IntString (fib 50))
  putStrLn (prim__cast_IntString (fib 90))
  putStrLn (prim__cast_IntString (power three 0))
  putStrLn (prim__cast_IntString (power three 1))
  putStrLn (prim__cast_IntString (power three 39))
  putStrLn (prim__cast_IntString (fib 0))
  putStrLn (prim__cast_IntString (fib 1))
  putStrLn (prim__cast_IntString (fib 2))
  putStrLn (prim__cast_IntString (fib 92))
  putStrLn (prim__cast_IntString (fib 93))
