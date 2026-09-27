||| Primitives on literals at compile time (ELIM-G-6), with the semantics of
||| docs/architecture/03-semantics.md. A primitive that would crash is not
||| folded: the crash happens at runtime, where the program puts it.
module IdrisMLIR.Simplify.Fold

import IdrisMLIR.Types

import Data.String

%default total

pow2 : Nat -> Integer
pow2 Z = 1
pow2 (S k) = 2 * pow2 k

||| Two's complement wrapping to a width (SEM-INT-2).
export
wrap : IntTy -> Integer -> Integer
wrap t n =
  let m = pow2 (width t)
      r = n `mod` m
      r' = if r < 0 then r + m else r
  in if signed t && r' >= m `div` 2 then r' - m else r'

||| Euclidean division and remainder (SEM-INT-3), for b /= 0.
euclid : Integer -> Integer -> (Integer, Integer)
euclid a b =
  let q = if (a < 0) == (b < 0) then abs a `div` abs b else negate (abs a `div` abs b)
      r = a - b * q
  in if r < 0 then (if b > 0 then (q - 1, r + b) else (q + 1, r - b)) else (q, r)

||| A Unicode scalar value (SEM-CHAR-3).
isScalar : Integer -> Bool
isScalar c = (c >= 0 && c <= 0xD7FF) || (c >= 0xE000 && c <= 0x10FFFF)

holds : Ord a => Cmp -> a -> a -> Bool
holds CLt a b = a < b
holds CLte a b = a <= b
holds CEq a b = a == b
holds CGte a b = a >= b
holds CGt a b = a > b

bool : Bool -> Lit
bool b = LInt IdrisInt (if b then 1 else 0)

number : Lit -> Maybe Integer
number (LInt _ n) = Just n
number (LChar c) = Just c
number _ = Nothing

||| A runtime primitive on literals, when it cannot crash. Bitwise operations
||| are left to MLIR.
export
foldPrim : Prim -> List Lit -> Maybe Lit
foldPrim (IntOp Add t) [LInt _ a, LInt _ b] = Just (LInt t (wrap t (a + b)))
foldPrim (IntOp Sub t) [LInt _ a, LInt _ b] = Just (LInt t (wrap t (a - b)))
foldPrim (IntOp Mul t) [LInt _ a, LInt _ b] = Just (LInt t (wrap t (a * b)))
foldPrim (IntOp Div t) [LInt _ a, LInt _ b] =
  if b == 0 then Nothing
  else Just (LInt t (if signed t then wrap t (fst (euclid a b)) else a `div` b))
foldPrim (IntOp Mod t) [LInt _ a, LInt _ b] =
  if b == 0 then Nothing
  else Just (LInt t (if signed t then wrap t (snd (euclid a b)) else a `mod` b))
foldPrim (Compare op _) [x, y] = bool <$> (holds op <$> number x <*> number y)
foldPrim (Cast _ (SInt t)) [x] = LInt t . wrap t <$> number x
foldPrim (Cast _ SChar) [x] = (\n => LChar (if isScalar n then n else 0)) <$> number x
foldPrim _ _ = Nothing

||| A string primitive on literals (ELIM-G-6).
export
foldStr : StrOp -> List Lit -> Maybe Lit
foldStr Append [LStr a, LStr b] = Just (LStr (a ++ b))
foldStr Cons [LChar c, LStr s] = Just (LStr (strCons (chr (cast c)) s))
foldStr Length [LStr s] = Just (LInt IdrisInt (cast (length s)))
foldStr Reverse [LStr s] = Just (LStr (reverse s))
foldStr (StrCompare op) [LStr a, LStr b] = Just (bool (holds op a b))
foldStr (ToStr SChar) [LChar c] = Just (LStr (singleton (chr (cast c))))
foldStr (ToStr (SInt _)) [LInt _ n] = Just (LStr (show n))
foldStr _ _ = Nothing
