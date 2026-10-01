module Main

-- Constant folding: build a sum of 2^n leaves, reassociate it into a long
-- right-nested chain, fold the constants, and evaluate before and after.
-- Perceus's `cfold.kk` (from Lean's `const_fold`, Counting Immutable
-- Beans). The chains are 2^(n-1) deep, so non-tail recursion is deep.

import Prelude

data Expr = Var Int | Val Int | Add Expr Expr | Mul Expr Expr

mkExpr : Int -> Int -> Expr
mkExpr n v =
  if n == 0 then (if v == 0 then Var 1 else Val v)
  else Add (mkExpr (n - 1) (v + 1)) (mkExpr (n - 1) (max (v - 1) 0))

appendAdd : Expr -> Expr -> Expr
appendAdd (Add e1 e2) e3 = Add e1 (appendAdd e2 e3)
appendAdd e0 e3 = Add e0 e3

appendMul : Expr -> Expr -> Expr
appendMul (Mul e1 e2) e3 = Mul e1 (appendMul e2 e3)
appendMul e0 e3 = Mul e0 e3

reassoc : Expr -> Expr
reassoc (Add e1 e2) = appendAdd (reassoc e1) (reassoc e2)
reassoc (Mul e1 e2) = appendMul (reassoc e1) (reassoc e2)
reassoc e = e

cfold : Expr -> Expr
cfold (Add e1 e2) =
  let e1' = cfold e1
      e2' = cfold e2 in
  case e1' of
    Val a => case e2' of
               Val b => Val (a + b)
               Add f (Val b) => Add (Val (a + b)) f
               Add (Val b) f => Add (Val (a + b)) f
               _ => Add e1' e2'
    _ => Add e1' e2'
cfold (Mul e1 e2) =
  let e1' = cfold e1
      e2' = cfold e2 in
  case e1' of
    Val a => case e2' of
               Val b => Val (a * b)
               Mul f (Val b) => Mul (Val (a * b)) f
               Mul (Val b) f => Mul (Val (a * b)) f
               _ => Mul e1' e2'
    _ => Mul e1' e2'
cfold e = e

eval : Expr -> Int
eval (Var _) = 0
eval (Val v) = v
eval (Add l r) = eval l + eval r
eval (Mul l r) = eval l * eval r

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
  let e = mkExpr n 1
  let v1 = eval e
  let v2 = eval (cfold (reassoc e))
  putStrLn (show v1 ++ " " ++ show v2)
