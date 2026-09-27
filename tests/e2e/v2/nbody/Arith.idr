module Arith

-- A small numeric prelude: arithmetic as a user
-- interface (FE-TR-6), with implementations for Double and Int. IO comes from
-- PrimIO, and putStr and `do` from the Prelude's own IO and Interfaces
-- modules; the rest of the Prelude is not imported, since its names would
-- clash with these.

import public Builtin
import public PrimIO
import public Prelude.IO
import public Prelude.Interfaces

%default partial

export infixl 8 +, -
export infixl 9 *, /
export infix 6 <, <=, >, >=, ==
export infixr 5 &&

public export
data Bool = False | True

public export
ifThenElse : Bool -> Lazy a -> Lazy a -> a
ifThenElse True t e = t
ifThenElse False t e = e

public export
not : Bool -> Bool
not True = False
not False = True

public export
(&&) : Bool -> Lazy Bool -> Bool
True && b = b
False && _ = False

||| Integer literals. Prelude.Num, which Prelude.Interfaces loads, turns on
||| `%integerLit fromInteger` for every module after it, so the literals of
||| these modules need a `fromInteger` in scope: this one, not the Prelude's
||| `Num`, whose operators would clash with `Arith`'s.
public export
interface FromInteger a where
  fromInteger : Integer -> a

public export
FromInteger Int where
  fromInteger = prim__cast_IntegerInt

public export
FromInteger Double where
  fromInteger = prim__cast_IntegerDouble

public export
truth : Int -> Bool
truth 0 = False
truth _ = True

public export
interface Arith a where
  (+) : a -> a -> a
  (-) : a -> a -> a
  (*) : a -> a -> a
  negate : a -> a
  fromInt : Int -> a

public export
interface Arith a => Ordered a where
  (<) : a -> a -> Bool
  (<=) : a -> a -> Bool
  (==) : a -> a -> Bool

public export
(>) : Ordered a => a -> a -> Bool
x > y = y < x

public export
(>=) : Ordered a => a -> a -> Bool
x >= y = y <= x

public export
Arith Double where
  (+) = prim__add_Double
  (-) = prim__sub_Double
  (*) = prim__mul_Double
  negate = prim__negate_Double
  fromInt = prim__cast_IntDouble

public export
Ordered Double where
  x < y = truth (prim__lt_Double x y)
  x <= y = truth (prim__lte_Double x y)
  x == y = truth (prim__eq_Double x y)

public export
Arith Int where
  (+) = prim__add_Int
  (-) = prim__sub_Int
  (*) = prim__mul_Int
  negate x = prim__sub_Int 0 x
  fromInt x = x

public export
Ordered Int where
  x < y = truth (prim__lt_Int x y)
  x <= y = truth (prim__lte_Int x y)
  x == y = truth (prim__eq_Int x y)

public export
(/) : Double -> Double -> Double
(/) = prim__div_Double

public export
div : Int -> Int -> Int
div = prim__div_Int

public export
mod : Int -> Int -> Int
mod = prim__mod_Int

public export
abs : Ordered a => a -> a
abs x = if x < fromInt 0 then negate x else x

public export
toDouble : Int -> Double
toDouble = prim__cast_IntDouble

public export
truncate : Double -> Int
truncate = prim__cast_DoubleInt

public export
exp : Double -> Double
exp = prim__doubleExp

public export
log : Double -> Double
log = prim__doubleLog

public export
sin : Double -> Double
sin = prim__doubleSin

public export
cos : Double -> Double
cos = prim__doubleCos

public export
atan : Double -> Double
atan = prim__doubleATan

public export
pow : Double -> Double -> Double
pow = prim__doublePow

public export
floor : Double -> Double
floor = prim__doubleFloor

public export
sqrt : Double -> Double
sqrt = prim__doubleSqrt

public export
show : Double -> String
show = prim__cast_DoubleString

public export
showInt : Int -> String
showInt = prim__cast_IntString

public export
printDouble : Double -> IO ()
printDouble x = putStrLn (show x)

public export
printInt : Int -> IO ()
printInt n = putStrLn (showInt n)

public export
label : String -> Double -> IO ()
label s x = do
  putStr s
  putStr ": "
  printDouble x

||| A non-negative decimal number from stdin, up to the first other character.
public export
readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      let d = prim__sub_Int (prim__cast_CharInt c) 48
      if d >= 0 && d <= 9 then go (acc * 10 + d) else pure acc
