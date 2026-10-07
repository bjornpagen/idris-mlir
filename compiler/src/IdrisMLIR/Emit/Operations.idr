||| The operations of the contract that one layer of a term becomes:
||| literals, primitives, constructor applications and IO primitives, each
||| made by its op's builder (IdrisMLIR.Dialect.*).
module IdrisMLIR.Emit.Operations

import IdrisMLIR.CustomSyntax as Idr
import IdrisMLIR.Dialect.Arith as Arith
import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Dialect.Math as Math
import IdrisMLIR.Dialect.MemRef as MemRef
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Emit.Types
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.List
import Data.SortedMap

%default total

||| An op with one result, of an MLIR type that is no Core type's (a
||| condition, an index).
export
mlirValue : Loc -> MlirType -> (MlirType -> Op) -> E Value
mlirValue l t build = do
  r <- fresh
  append (MkStatement (Just r) (build t) (At l))
  pure (MkValue r t)

||| An op with one result, of a Core type, held as itself.
export
value : Index -> Loc -> Ty -> (MlirType -> Op) -> E Val
value ix l t build = do
  r <- mlirValue l !(mlirType ix t) build
  pure (val r.name t Many)

||| An op without results.
export
statement : Loc -> Op -> E ()
statement l o = append (MkStatement Nothing o (At l))

||| A value where the contract expects it used as `use`. A linear value
||| where a plain one is expected is used (`idr.lin.use`), its one use; a
||| plain value in a linear position enters it (`idr.lin.enter`), as Idris
||| lets any value fill a binder of quantity 1.
export
coerce : Index -> Loc -> Use -> Val -> E Val
coerce ix l use v = case (linear v.use v.type, linear use v.type) of
  (True, False) => value ix l v.type (Idr.linUseOp !(operand ix v))
  (False, True) => do
    let entered = { use := Once } v
    t <- heldType ix Once v.type
    r <- mlirValue l t (Idr.linEnterOp !(operand ix v))
    pure ({ name := r.name } entered)
  _ => pure v

||| A literal: integers and doubles are `arith.constant`,
||| strings and bigs `idr.constant`.
export
literal : Index -> Loc -> Lit -> E Val
literal ix l (LInt t n) = value ix l (IntT t)
  (Arith.constantOp (integerAttr (twos (width t) n) (integerType (width t))))
literal ix l (LChar c) = value ix l CharT (Arith.constantOp (integerAttr c (integerType 32)))
literal ix l (LDouble d) = value ix l DoubleT (Arith.constantOp (floatAttr d f64Type))
literal ix l (LStr s) = value ix l StrT (Idr.constantOp (stringAttr s))
literal ix l (LBig n) = value ix l BigT (Idr.constantOp (Idr.bigAttr (show n)))
literal ix l (LNat n) = value ix l NatT (Idr.constantOp (Idr.bigAttr (show n)))

||| The erased value.
export
erasedValue : Index -> Loc -> E Val
erasedValue ix l = value ix l ErasedT (Idr.constantOp Idr.erasedAttr)

||| A comparison's result.
bool : MlirType
bool = integerType 1

||| The `arith.cmpi` predicate: `Char`s compare as code points.
cmpi : Cmp -> Bool -> CmpIPredicate
cmpi CEq _ = CmpIPredicate.Eq
cmpi CLt s = if s then CmpIPredicate.Slt else CmpIPredicate.Ult
cmpi CLte s = if s then CmpIPredicate.Sle else CmpIPredicate.Ule
cmpi CGt s = if s then CmpIPredicate.Sgt else CmpIPredicate.Ugt
cmpi CGte s = if s then CmpIPredicate.Sge else CmpIPredicate.Uge

||| The `arith.cmpf` predicate: ordered, so false on NaN.
cmpf : Cmp -> CmpFPredicate
cmpf CEq = CmpFPredicate.OEQ
cmpf CLt = CmpFPredicate.OLT
cmpf CLte = CmpFPredicate.OLE
cmpf CGt = CmpFPredicate.OGT
cmpf CGte = CmpFPredicate.OGE

||| The predicate of a comparison of strings, bigs or naturals.
predicate : Cmp -> CmpPredicate
predicate CEq = CmpPredicate.Eq
predicate CLt = CmpPredicate.Lt
predicate CLte = CmpPredicate.Lte
predicate CGt = CmpPredicate.Gt
predicate CGte = CmpPredicate.Gte

||| The `math` op of a C library function or exact operation, on its
||| operands.
mathOp : MathFn -> List Value -> Maybe (MlirType -> Op)
mathOp Pow [a, b] = Just (Math.powfOp a b)
mathOp Exp [a] = Just (Math.expOp a)
mathOp Log [a] = Just (Math.logOp a)
mathOp Sin [a] = Just (Math.sinOp a)
mathOp Cos [a] = Just (Math.cosOp a)
mathOp Tan [a] = Just (Math.tanOp a)
mathOp ASin [a] = Just (Math.asinOp a)
mathOp ACos [a] = Just (Math.acosOp a)
mathOp ATan [a] = Just (Math.atanOp a)
mathOp Sqrt [a] = Just (Math.sqrtOp a)
mathOp Floor [a] = Just (Math.floorOp a)
mathOp Ceiling [a] = Just (Math.ceilOp a)
mathOp _ _ = Nothing

||| The op of an Integer's arithmetic.
bigOp : ArithOp -> Value -> Value -> MlirType -> Op
bigOp Add = Idr.bigAddOp
bigOp Sub = Idr.bigSubOp
bigOp Mul = Idr.bigMulOp
bigOp Div = Idr.bigDivOp
bigOp Mod = Idr.bigModOp
bigOp And = Idr.bigAndOp
bigOp Or = Idr.bigOrOp
bigOp Xor = Idr.bigXorOp

||| Fixed-width arithmetic. The bitwise and wrapping ops are `arith`, whose
||| integers are signless; division and remainder are Euclidean, so they
||| read the signedness Idris's type has.
intArith : ArithOp -> Bool -> Value -> Value -> MlirType -> Op
intArith Add _ x y = Arith.addiOp x y
intArith Sub _ x y = Arith.subiOp x y
intArith Mul _ x y = Arith.muliOp x y
intArith And _ x y = Arith.andiOp x y
intArith Or _ x y = Arith.oriOp x y
intArith Xor _ x y = Arith.xoriOp x y
intArith Div s x y = Idr.divOp {isSigned = s} x y
intArith Mod s x y = Idr.modOp {isSigned = s} x y

||| Double arithmetic, `arith`'s.
floatArith : FArith -> Value -> Value -> MlirType -> Op
floatArith FAdd x y = Arith.addfOp x y
floatArith FSub x y = Arith.subfOp x y
floatArith FMul x y = Arith.mulfOp x y
floatArith FDiv x y = Arith.divfOp x y

||| A comparison's `i1` as an `Int`.
extend : Index -> Loc -> Value -> E Val
extend ix l c = value ix l (IntT IdrisInt) (Arith.extuiOp c)

||| The width and signedness of a fixed-width integer or `Char`.
intLike : Scalar -> Maybe (Nat, Bool)
intLike (SInt t) = Just (width t, signed t)
intLike SChar = Just (32, False)
intLike SDouble = Nothing

||| A primitive, on operands in Idris's order.
export
prim : Index -> Loc -> Prim -> List Val -> E Val
prim ix l (IntOp op t) [a, b] = do
  x <- operand ix a
  y <- operand ix b
  value ix l (IntT t) (intArith op (signed t) x y)
prim ix l (IntShift s t) [a, b] = do
  x <- operand ix a
  y <- operand ix b
  value ix l (IntT t) (case s of
    ShiftLeft => Idr.shlOp {isSigned = signed t} x y
    ShiftRight => Idr.shrOp {isSigned = signed t} x y)
prim ix l (FloatOp op) [a, b] = do
  x <- operand ix a
  y <- operand ix b
  value ix l DoubleT (floatArith op x y)
prim ix l Negate [a] = value ix l DoubleT (Arith.negfOp !(operand ix a))
prim ix l (Math f) as = case mathOp f !(traverse (operand ix) as) of
  Just build => value ix l DoubleT build
  Nothing => internal ("the primitive " ++ show f ++ " with " ++ show (length as) ++ " operands")
prim ix l (Compare c SDouble) [a, b] =
  extend ix l !(mlirValue l bool (Arith.cmpfOp (cmpf c) !(operand ix a) !(operand ix b)))
prim ix l (Compare c s) [a, b] = case intLike s of
  Just (_, sgn) =>
    extend ix l !(mlirValue l bool (Arith.cmpiOp (cmpi c sgn) !(operand ix a) !(operand ix b)))
  Nothing => internal ("a comparison of " ++ show s)
prim ix l (Cast from to) [a] = case (from, to) of
  (SInt f, SChar) => value ix l CharT (Idr.toCharOp {isSigned = signed f} !(operand ix a))
  (SInt f, SDouble) => do
    x <- operand ix a
    value ix l DoubleT (if signed f then Arith.sitofpOp x else Arith.uitofpOp x)
  (SDouble, SInt t) => value ix l (IntT t) (Idr.toIntOp !(operand ix a))
  (SDouble, SDouble) => pure a
  (SChar, SChar) => pure a
  (f, t) => case (intLike f, intLike t) of
    (Just (fw, fs), Just (tw, _)) =>
      if fw == tw then pure ({ type := scalarTy t } a)
      else if fw > tw then value ix l (scalarTy t) (Arith.trunciOp !(operand ix a))
      else do
        x <- operand ix a
        value ix l (scalarTy t) (if fs then Arith.extsiOp x else Arith.extuiOp x)
    _ => internal ("a cast from " ++ show f ++ " to " ++ show t)
prim ix l StrAppend [a, b] = value ix l StrT (Idr.strAppendOp !(operand ix a) !(operand ix b))
prim ix l StrCons [c, s] = value ix l StrT (Idr.strConsOp !(operand ix c) !(operand ix s))
prim ix l StrLength [s] = value ix l (IntT IdrisInt) (Idr.strLengthOp !(operand ix s))
prim ix l StrHead [s] = value ix l CharT (Idr.strHeadOp !(operand ix s))
prim ix l StrTail [s] = value ix l StrT (Idr.strTailOp !(operand ix s))
prim ix l StrIndex [s, i] = value ix l CharT (Idr.strIndexOp !(operand ix s) !(operand ix i))
prim ix l StrReverse [s] = value ix l StrT (Idr.strReverseOp !(operand ix s))
-- Idris takes the start, the length, then the string.
prim ix l StrSubstr [start, len, s] =
  value ix l StrT (Idr.strSubstrOp !(operand ix s) !(operand ix start) !(operand ix len))
prim ix l (StrCompare c) [a, b] =
  extend ix l !(mlirValue l bool (Idr.strCmpOp (predicate c) !(operand ix a) !(operand ix b)))
prim ix l (ToStr (SInt t)) [x] = value ix l StrT (Idr.strShowOp {isSigned = signed t} !(operand ix x))
prim ix l (ToStr SChar) [c] = value ix l StrT (Idr.strFromCharOp !(operand ix c))
prim ix l (ToStr SDouble) [x] = value ix l StrT (Idr.strShowOp !(operand ix x))
prim ix l (FromStr (SInt t)) [s] = value ix l (IntT t) (Idr.strToIntOp {isSigned = signed t} !(operand ix s))
prim ix l (FromStr SDouble) [s] = value ix l DoubleT (Idr.strToDoubleOp !(operand ix s))
prim ix l (BigArith op) [a, b] = value ix l BigT (bigOp op !(operand ix a) !(operand ix b))
prim ix l BigNegate [a] = value ix l BigT (Idr.bigNegOp !(operand ix a))
prim ix l (BigCompare c) [a, b] =
  extend ix l !(mlirValue l bool (Idr.bigCmpOp (predicate c) !(operand ix a) !(operand ix b)))
prim ix l (ToBig (SInt t)) [x] = value ix l BigT (Idr.bigFromIntOp {isSigned = signed t} !(operand ix x))
prim ix l (ToBig SChar) [c] = value ix l BigT (Idr.bigFromIntOp !(operand ix c))
prim ix l (ToBig SDouble) [d] = value ix l BigT (Idr.bigFromDoubleOp !(operand ix d))
prim ix l (FromBig (SInt t)) [b] = value ix l (IntT t) (Idr.bigToIntOp !(operand ix b))
prim ix l (FromBig SDouble) [b] = value ix l DoubleT (Idr.bigToDoubleOp !(operand ix b))
-- The code point if the integer is one, else 0; `idr.to_char`
-- decides for the integers an `i64` holds, and 0 stands for the rest.
prim ix l (FromBig SChar) [b] = do
  lo <- literal ix l (LBig 0)
  hi <- literal ix l (LBig 0x10FFFF)
  big <- operand ix b
  ge <- mlirValue l bool (Idr.bigCmpOp CmpPredicate.Gte big !(operand ix lo))
  le <- mlirValue l bool (Idr.bigCmpOp CmpPredicate.Lte big !(operand ix hi))
  inRange <- mlirValue l bool (Arith.andiOp ge le)
  n <- mlirValue l (integerType 64) (Idr.bigToIntOp big)
  outside <- literal ix l (LInt IdrisInt (-1))
  m <- mlirValue l (integerType 64) (Arith.selectOp inRange n !(operand ix outside))
  value ix l CharT (Idr.toCharOp {isSigned = True} m)
prim ix l BigShow [b] = value ix l StrT (Idr.bigShowOp !(operand ix b))
prim ix l BigRead [s] = value ix l BigT (Idr.bigFromStrOp !(operand ix s))
prim ix l NatAdd [a, b] = value ix l NatT (Idr.bigAddOp !(operand ix a) !(operand ix b))
prim ix l NatMul [a, b] = value ix l NatT (Idr.bigMulOp !(operand ix a) !(operand ix b))
prim ix l (NatCompare c) [a, b] =
  extend ix l !(mlirValue l bool (Idr.bigCmpOp (predicate c) !(operand ix a) !(operand ix b)))
prim ix l NatToBig [n] = value ix l BigT (Idr.natToBigOp !(operand ix n))
prim ix l NatFromBig [b] = value ix l NatT (Idr.natFromBigOp !(operand ix b))
prim ix l (StrBuild Pack _) [xs] = value ix l StrT (Idr.strPackOp !(operand ix xs))
prim ix l (StrBuild Concat _) [xs] = value ix l StrT (Idr.strConcatOp !(operand ix xs))
-- The length of an array is its memref's dimension, an index, as an `Int`.
prim ix l (ArrayLength e) [a] = do
  zero <- mlirValue l indexType (Arith.constantOp (integerAttr 0 indexType))
  n <- mlirValue l indexType (MemRef.dimOp !(operand ix a) zero)
  value ix l (IntT IdrisInt) (Arith.indexCastOp n)
prim ix l p vs = internal ("the primitive " ++ show p ++ " with " ++ show (length vs) ++ " operands")

||| A constructor application (`idr.con`); a box's allocates.
export
con : Index -> Loc -> Con -> List Val -> E Val
con ix l c vs0 = do
  vs <- traverse (\(f, v) => coerce ix l (binderUse f) v) (zip c.fields vs0)
  value ix l (DataT c.id.dataId)
        (Idr.conOp [mangle c.id.dataId.name, mangle c.id.name] !(traverse (operand ix) vs))

mutual
  ||| The value a variable names: itself, or the constructor a match took
  ||| apart, built again from its fields as the region holds them
  ||| (`Val.rebuild`); in the owned stage the cell it came from is reused.
  export
  force : Index -> Loc -> Val -> E Val
  force ix l (MkVal n t u Nothing) = pure (MkVal n t u Nothing)
  force ix l (MkVal n t u (Just (c, fs))) = do
    Just k <- pure (lookup c ix.cons)
      | Nothing => internal ("the constructor " ++ show c ++ ", which is not declared")
    con ix l k !(forceAll ix l fs)

  forceAll : Index -> Loc -> List Val -> E (List Val)
  forceAll ix l [] = pure []
  forceAll ix l (v :: vs) = (::) <$> force ix l v <*> forceAll ix l vs

||| The one constructor of a data instance.
only : Index -> DataId -> E Con
only ix d = case (.cons) <$> lookup d ix.datas of
  Just [c] => pure c
  _ => internal (show d ++ " does not have exactly one constructor")

||| A buffer's element.
byte : Ty
byte = IntT UInt8

||| The `IORes` of an IO operation's result and its next world.
export
ioResult : Index -> Loc -> DataId -> Val -> Val -> E Val
ioResult ix l res x w = con ix l !(only ix res) [x, w]

||| An IO primitive, and the `IORes` of its result and next
||| world.
export
io : Index -> Loc -> IOOp -> List Val -> DataId -> E Val
io ix l op vs res = do
  mk <- only ix res
  (x, w) <- case (op, vs) of
    (PutStr, [s, w0]) => withUnit mk !(nextWorld (Idr.ioPutStrOp !(operand ix s) !(operand ix w0)))
    (PutChar, [c, w0]) => withUnit mk !(nextWorld (Idr.ioPutCharOp !(operand ix c) !(operand ix w0)))
    (GetByte, [w0]) => twoResults CharT (Idr.ioGetByteOp !(operand ix w0))
    (GetLine, [w0]) => twoResults StrT (Idr.ioGetLineOp !(operand ix w0))
    (Array NewArray e, [n, x, w0]) =>
      twoResults (ArrayT e) (Idr.arrayNewOp !(operand ix n) !(operand ix x) !(operand ix w0))
    (Array GetArray e, [a, i, w0]) =>
      twoResults e (Idr.arrayGetOp !(operand ix a) !(operand ix i) !(operand ix w0))
    (Array SetArray e, [a, i, x, w0]) =>
      withUnit mk !(nextWorld (Idr.arraySetOp !(operand ix a) !(operand ix i) !(operand ix x) !(operand ix w0)))
    -- A buffer is an array of bytes: a new one is zero bytes, a byte read
    -- as an Int is widened, an Int written as a byte must be one.
    (BufferNew, [n, w0]) => do
      z <- value ix l byte (Arith.constantOp (integerAttr 0 (integerType 8)))
      twoResults (ArrayT byte) (Idr.arrayNewOp !(operand ix n) !(operand ix z) !(operand ix w0))
    (BufferGet, [a, i, w0]) => do
      (b, w) <- twoResults byte (Idr.arrayGetOp !(operand ix a) !(operand ix i) !(operand ix w0))
      x <- value ix l (IntT IdrisInt) (Arith.extuiOp !(operand ix b))
      pure (x, w)
    (BufferSet, [a, i, x, w0]) => do
      b <- value ix l byte (Idr.toByteOp !(operand ix x))
      withUnit mk !(nextWorld (Idr.arraySetOp !(operand ix a) !(operand ix i) !(operand ix b) !(operand ix w0)))
    -- Bytes between a buffer and a standard stream's handle.
    (WriteBytes, [h, a, o, n, w0]) =>
      twoResults (IntT IdrisInt) (Idr.ioWriteBytesOp !(operand ix h) !(operand ix a) !(operand ix o)
                                               !(operand ix n) !(operand ix w0))
    (ReadBytes, [h, a, o, n, w0]) =>
      twoResults (IntT IdrisInt) (Idr.ioReadBytesOp !(operand ix h) !(operand ix a) !(operand ix o)
                                              !(operand ix n) !(operand ix w0))
    (Eof, [h, w0]) => twoResults (IntT IdrisInt) (Idr.ioEofOp !(operand ix h) !(operand ix w0))
    _ => internal ("the IO primitive " ++ show op ++ " with the wrong operands")
  con ix l mk [x, w]
  where
    ||| An op whose one result is the next world.
    nextWorld : (MlirType -> Op) -> E Val
    nextWorld = value ix l WorldT

    ||| An op whose results are a value of type `t` and the next world.
    twoResults : Ty -> (MlirType -> MlirType -> Op) -> E (Val, Val)
    twoResults t build = do
      r <- fresh
      append (MkStatement (Just r) (build !(mlirType ix t) !(mlirType ix WorldT)) (At l))
      pure (val (r ++ "#0") t Many, val (r ++ "#1") WorldT Many)

    ||| The unit value of an IO result, built after the operation.
    withUnit : Con -> Val -> E (Val, Val)
    withUnit mk w = case map typeOf mk.fields of
      [DataT u, _] => pure (!(con ix l !(only ix u) []), w)
      _ => internal (show res ++ " does not hold a unit value")
