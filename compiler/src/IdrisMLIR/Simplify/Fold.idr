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

||| Neither NaN nor infinite.
finite : Double -> Bool
finite d = d == d && d - d == 0.0

||| The C library's functions, as the compiler's own runtime (Chez Scheme)
||| computes them: the same functions the program calls (SEM-DBL-3).
math : MathFn -> List Double -> Maybe Double
math Exp [x] = Just (exp x)
math Log [x] = Just (log x)
math Pow [x, y] = Just (pow x y)
math Sin [x] = Just (sin x)
math Cos [x] = Just (cos x)
math Tan [x] = Just (tan x)
math ASin [x] = Just (asin x)
math ACos [x] = Just (acos x)
math ATan [x] = Just (atan x)
math Sqrt [x] = Just (sqrt x)
math Floor [x] = Just (floor x)
math Ceiling [x] = Just (ceiling x)
math _ _ = Nothing

doubles : List Lit -> Maybe (List Double)
doubles = traverse (\l => case l of
                             LDouble d => Just d
                             _ => Nothing)

||| An Integer primitive on literals, computed with Idris's own Integer
||| primitives, which are the reference's by construction (SEM-BIG-1).
||| Nothing when it would crash or has no result.
export
foldBig : BigOp -> List Lit -> Maybe Lit
foldBig (BigArith op) [LBig a, LBig b] = LBig <$> case op of
  Add => Just (a + b)
  Sub => Just (a - b)
  Mul => Just (a * b)
  -- The divisor is not zero, so the primitives are total here.
  Div => if b == 0 then Nothing else Just (assert_total (prim__div_Integer a b))
  Mod => if b == 0 then Nothing else Just (assert_total (prim__mod_Integer a b))
  And => Just (prim__and_Integer a b)
  Or => Just (prim__or_Integer a b)
  Xor => Just (prim__xor_Integer a b)
foldBig BigNegate [LBig a] = Just (LBig (negate a))
foldBig (BigCompare op) [LBig a, LBig b] = Just (bool (holds op a b))
foldBig (ToBig (SInt _)) [LInt _ n] = Just (LBig n)
foldBig (ToBig SChar) [LChar c] = Just (LBig c)
foldBig (ToBig SDouble) [LDouble d] =
  if finite d then Just (LBig (prim__cast_DoubleInteger d)) else Nothing
foldBig (FromBig (SInt t)) [LBig n] = Just (LInt t (wrap t n))
foldBig (FromBig SChar) [LBig n] = Just (LChar (if isScalar n then n else 0))
foldBig (FromBig SDouble) [LBig n] = Just (LDouble (prim__cast_IntegerDouble n))
foldBig BigShow [LBig n] = Just (LStr (show n))
foldBig BigRead [LStr s] = Just (LBig (prim__cast_StringInteger s))
foldBig _ _ = Nothing

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
foldPrim (FloatOp op) [LDouble a, LDouble b] = Just (LDouble (case op of
                                                                 FAdd => a + b
                                                                 FSub => a - b
                                                                 FMul => a * b
                                                                 FDiv => a / b))
foldPrim Negate [LDouble a] = Just (LDouble (negate a))
foldPrim (Math f) args = LDouble <$> (doubles args >>= math f)
foldPrim (Compare op SDouble) [LDouble a, LDouble b] = Just (bool (holds op a b))
foldPrim (Compare op _) [x, y] = bool <$> (holds op <$> number x <*> number y)
-- SEM-DBL-4: truncation toward zero, then wrapping; a non-finite Double
-- crashes at runtime.
foldPrim (Cast SDouble (SInt t)) [LDouble d] =
  if finite d then Just (LInt t (wrap t (cast d))) else Nothing
foldPrim (Cast (SInt _) SDouble) [LInt _ n] = Just (LDouble (fromInteger n))
foldPrim (Cast _ (SInt t)) [x] = LInt t . wrap t <$> number x
foldPrim DoubleHead [LDouble d] = case unpack (prim__cast_DoubleString d) of
  (c :: _) => Just (LChar (cast (ord c)))
  [] => Nothing
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
foldStr (ToStr SDouble) [LDouble d] = Just (LStr (prim__cast_DoubleString d))
foldStr (FromStr SDouble) [LStr s] = Just (LDouble (prim__cast_StringDouble s))
foldStr _ _ = Nothing
