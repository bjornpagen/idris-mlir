module Main

-- Symbolic differentiation: the n-th derivative of x^x, simplified as it is
-- built, printing the size of each derivative. Perceus's `deriv.kk` and
-- Lean's `deriv.lean` (Counting Immutable Beans). Subterms are shared, so
-- counts are really needed.

import Prelude

data Expr = Val Int | Var String | Add Expr Expr | Mul Expr Expr | Pow Expr Expr | Ln Expr

pown : Int -> Int -> Int
pown a 0 = 1
pown a 1 = a
pown a n =
  let b = pown a (n `div` 2) in
  b * b * (if n `mod` 2 == 0 then 1 else a)

add : Expr -> Expr -> Expr
add (Val n) (Val m) = Val (n + m)
add (Val 0) f = f
add f (Val 0) = f
add f (Val n) = add (Val n) f
add (Val n) (Add (Val m) f) = add (Val (n + m)) f
add f (Add (Val n) g) = add (Val n) (add f g)
add (Add f g) h = add f (add g h)
add f g = Add f g

mul : Expr -> Expr -> Expr
mul (Val n) (Val m) = Val (n * m)
mul (Val 0) _ = Val 0
mul _ (Val 0) = Val 0
mul (Val 1) f = f
mul f (Val 1) = f
mul f (Val n) = mul (Val n) f
mul (Val n) (Mul (Val m) f) = mul (Val (n * m)) f
mul f (Mul (Val n) g) = mul (Val n) (mul f g)
mul (Mul f g) h = mul f (mul g h)
mul f g = Mul f g

powr : Expr -> Expr -> Expr
powr (Val m) (Val n) = Val (pown m n)
powr _ (Val 0) = Val 1
powr f (Val 1) = f
powr (Val 0) _ = Val 0
powr f g = Pow f g

ln : Expr -> Expr
ln (Val 1) = Val 0
ln f = Ln f

d : String -> Expr -> Expr
d x (Val _) = Val 0
d x (Var y) = if x == y then Val 1 else Val 0
d x (Add f g) = add (d x f) (d x g)
d x (Mul f g) = add (mul f (d x g)) (mul g (d x f))
d x (Pow f g) =
  mul (powr f g) (add (mul (mul g (d x f)) (powr f (Val (-1)))) (mul (ln f) (d x g)))
d x (Ln f) = mul (d x f) (powr f (Val (-1)))

count : Expr -> Int
count (Val _) = 1
count (Var _) = 1
count (Add f g) = count f + count g
count (Mul f g) = count f + count g
count (Pow f g) = count f + count g
count (Ln f) = count f

deriv : Int -> Expr -> IO Expr
deriv i f = do
  let f' = d "x" f
  putStrLn (show (i + 1) ++ " count: " ++ show (count f'))
  pure f'

nestAux : Int -> Int -> Expr -> IO Expr
nestAux s n x =
  if n == 0 then pure x
  else do
    y <- deriv (s - n) x
    nestAux s (n - 1) y

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  let x = Var "x"
  _ <- nestAux n n (powr x x)
  pure ()
