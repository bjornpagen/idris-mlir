-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The operations of the contract that one layer of a term becomes:
||| literals, primitives, constructor applications and effects, each made by
||| its op's builder (IdrisMLIR.Dialect.*). Every op is written after its
||| guards, which its ODS declares (Idr.guardsOf): a partial op is a guard
||| and a total op, the guard checking the operand, and the op taking the
||| guard's result in the operand's place, so it stays below its check.
module IdrisMLIR.Emit.Operations

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
import IdrisMLIR.Syntax.Arith
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.List
import Data.SortedMap

%default total

------------------------------------------------------------------------------
-- Guards
------------------------------------------------------------------------------

||| An op of one result of type `t`, written as it is: a guard's own work,
||| which has no guard of its own.
unguarded : Loc -> MlirType -> (MlirType -> Op) -> E Value
unguarded l t build = do
  r <- fresh
  append (MkStatement (Just r) (build t) (At l))
  pure (MkValue r t)

||| The length of an array a world orders, its memref's dimension, as an
||| `Int`.
memrefLength : Loc -> Value -> E Value
memrefLength l a = do
  zero <- unguarded l IndexType (Arith.constantOp (IntegerAttr 0 IndexType))
  n <- unguarded l IndexType (MemRef.dimOp a zero)
  unguarded l (IntegerType 64) (Arith.indexCastOp n)

||| The bytes of a machine word a buffer stores or loads.
wordSize : Ty -> Maybe Integer
wordSize (IntT t) = Just (cast (width t) `div` 8)
wordSize DoubleT = Just 8
wordSize _ = Nothing

||| `xs` with its element at `i` replaced by `x`.
setAt : Nat -> a -> List a -> List a
setAt Z x (_ :: ys) = x :: ys
setAt (S i) x (y :: ys) = y :: setAt i x ys
setAt _ _ [] = []

||| `o` after its guards: each written here, in order, at `l`, and `o`
||| taking each guard's result in place of the operand it checks. An op
||| without guards is itself. `types` are an effect's type arguments, which
||| give a stored or loaded word its size.
guarded : Loc -> List Ty -> Op -> E Op
guarded l types o = foldlM check o (guardsOf o)
  where
    operandAt : Op -> Nat -> E Value
    operandAt o i = maybe (internal (o.name ++ " without its operand " ++ show i)) pure (getAt i o.operands)

    -- A count of bytes, as an `Int`: an operand's value, a string
    -- operand's bytes, an array operand's length, or the word an effect
    -- stores or loads.
    count : Op -> Count -> E Value
    count o (CountAt i) = operandAt o i
    count o (BytesOf i) = unguarded l (IntegerType 64) (Idr.strBytesLengthOp !(operandAt o i))
    count o (LengthOf i) = memrefLength l !(operandAt o i)
    count o WordSize = case map wordSize types of
      [Just n] => unguarded l (IntegerType 64) (Arith.constantOp (IntegerAttr n (IntegerType 64)))
      _ => internal (o.name ++ " at the types " ++ show types)

    check : Op -> Guard -> E Op
    check o g = do
      x <- operandAt o g.operand
      build <- the (E (MlirType -> Op)) $ case g.check of
        Nonzero => pure (Idr.checkNonzeroOp x g.cause)
        Nonempty => pure (Idr.checkNonemptyOp x g.cause)
        Finite => pure (Idr.checkFiniteOp x g.cause)
        InBounds i => pure (Idr.checkInBoundsOp x !(operandAt o i) g.cause)
        InRange c size => pure (Idr.checkRangeOp x !(count o c) !(count o size) g.cause)
      checked <- unguarded l x.type build
      pure ({ operands $= setAt g.operand checked } o)

------------------------------------------------------------------------------
-- Writing ops
------------------------------------------------------------------------------

||| An op where it stands, after its guards, and the names of its results:
||| one per result type, `name#i` of one name for several.
placed : Loc -> List Ty -> Op -> E (List String)
placed l types o = do
  o' <- guarded l types o
  case o'.results of
    [] => [] <$ append (MkStatement Nothing o' (At l))
    [_] => do
      r <- fresh
      append (MkStatement (Just r) o' (At l))
      pure [r]
    ts => do
      r <- fresh
      append (MkStatement (Just r) o' (At l))
      pure (zipWith (\i, _ => r ++ "#" ++ show i) [0 .. length ts] ts)

||| An op with one result, of an MLIR type that is no Core type's (a
||| condition, an index).
export
mlirValue : Loc -> MlirType -> (MlirType -> Op) -> E Value
mlirValue l t build = do
  o <- guarded l [] (build t)
  r <- fresh
  append (MkStatement (Just r) o (At l))
  pure (MkValue r t)

||| An op with one result, of a Core type, held as itself.
export
value : Index -> Loc -> Ty -> (MlirType -> Op) -> E Val
value ix l t build = do
  r <- mlirValue l (mlirType t) build
  pure (val r.name t Many)

||| An op without results.
export
statement : Loc -> Op -> E ()
statement l o = ignore (placed l [] o)

||| An op, and the names of its results, one per result type.
export
resultNames : Loc -> Op -> E (List String)
resultNames l = placed l []

||| A value where the contract expects it used as `use`. A linear value
||| where a plain one is expected is used (`idr.lin.use`), its one use; a
||| plain value in a linear position enters it (`idr.lin.enter`), as Idris
||| lets any value fill a binder of quantity 1.
export
coerce : Index -> Loc -> Quantity -> Val -> E Val
coerce ix l use v = case (linear v.use v.type, linear use v.type) of
  (True, False) => value ix l v.type (Idr.linUseOp !(operand ix v))
  (False, True) => do
    let entered = { use := One } v
    let t = heldType One v.type
    r <- mlirValue l t (Idr.linEnterOp !(operand ix v))
    pure ({ name := r.name } entered)
  _ => pure v

------------------------------------------------------------------------------
-- Literals
------------------------------------------------------------------------------

||| A literal: integers and doubles are `arith.constant`,
||| strings and bigs `idr.constant`.
export
literal : Index -> Loc -> Lit -> E Val
literal ix l (LInt t n) = value ix l (IntT t)
  (Arith.constantOp (IntegerAttr (twos (width t) n) (IntegerType (width t))))
literal ix l (LChar c) = value ix l CharT (Arith.constantOp (IntegerAttr c (IntegerType 32)))
literal ix l (LDouble d) = value ix l DoubleT (Arith.constantOp (FloatAttr d F64Type))
literal ix l (LStr s) = value ix l StrT (Idr.constantOp (StringAttr s))
literal ix l (LBig n) = value ix l BigT (Idr.constantOp (idr (BigAttr n)))
literal ix l (LNat n) = value ix l NatT (Idr.constantOp (idr (BigAttr (cast n))))

------------------------------------------------------------------------------
-- Primitives
------------------------------------------------------------------------------

||| A comparison's result.
bool : MlirType
bool = IntegerType 1

||| The `arith.cmpi` predicate: `Char`s compare as code points.
cmpi : CmpPredicate -> Bool -> CmpIPredicate
cmpi CmpPredicate.Eq _ = CmpIPredicate.Eq
cmpi CmpPredicate.Lt s = if s then CmpIPredicate.Slt else CmpIPredicate.Ult
cmpi CmpPredicate.Lte s = if s then CmpIPredicate.Sle else CmpIPredicate.Ule
cmpi CmpPredicate.Gt s = if s then CmpIPredicate.Sgt else CmpIPredicate.Ugt
cmpi CmpPredicate.Gte s = if s then CmpIPredicate.Sge else CmpIPredicate.Uge

||| The `arith.cmpf` predicate: ordered, so false on NaN.
cmpf : CmpPredicate -> CmpFPredicate
cmpf CmpPredicate.Eq = CmpFPredicate.OEQ
cmpf CmpPredicate.Lt = CmpFPredicate.OLT
cmpf CmpPredicate.Lte = CmpFPredicate.OLE
cmpf CmpPredicate.Gt = CmpFPredicate.OGT
cmpf CmpPredicate.Gte = CmpFPredicate.OGE

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

||| A pure primitive of the dialect on its operands, giving a value of type
||| `t`.
primValue : Index -> Loc -> IdrPrim -> List Val -> Ty -> E Val
primValue ix l p vs t = do
  args <- traverse (operand ix) vs
  value ix l t (\r => primOp p args [r])

||| What a pure primitive of the dialect gives, at Core's type: a string, an
||| Integer or a natural as itself, a character a `Char`, a length in
||| characters or bytes or a handle's test an `Int`; Integer arithmetic gives
||| what it takes, Integers or naturals. A conversion whose result its types
||| name is a `Cast`, `ToStr`, `FromStr`, `ToBig` or `FromBig`, which gives
||| that type.
resultOf : IdrPrim -> List Val -> E Ty
resultOf BigAdd (a :: _) = pure a.type
resultOf BigMul (a :: _) = pure a.type
resultOf p _ = case p of
  StrAppend => pure StrT
  StrCons => pure StrT
  StrTail => pure StrT
  StrReverse => pure StrT
  StrSubstr => pure StrT
  StrPack => pure StrT
  StrConcat => pure StrT
  StrDropBytes => pure StrT
  BigShow => pure StrT
  HandleString => pure StrT
  StrHead => pure CharT
  StrIndex => pure CharT
  StrScalarAt => pure CharT
  StrLength => pure (IntT IdrisInt)
  StrBytesLength => pure (IntT IdrisInt)
  StrScalarBytes => pure (IntT IdrisInt)
  HandleIsNull => pure (IntT IdrisInt)
  BigSub => pure BigT
  BigAnd => pure BigT
  BigOr => pure BigT
  BigXor => pure BigT
  BigShl => pure BigT
  BigShr => pure BigT
  BigDiv => pure BigT
  BigMod => pure BigT
  BigNeg => pure BigT
  BigFromStr => pure BigT
  NatToBig => pure BigT
  NatFromBig => pure NatT
  _ => internal ("the primitive " ++ show (Op p) ++ ", which gives no value of a type of its own")

||| A primitive, on operands in Idris's order (an op of the dialect's in the
||| op's).
export
prim : Index -> Loc -> Prim -> List Val -> E Val
prim ix l (Op p) vs = primValue ix l p vs !(resultOf p vs)
prim ix l (IntOp op t) [a, b] =
  value ix l (IntT t) (intArith op (signed t) !(operand ix a) !(operand ix b))
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
  (SDouble, SInt t) => primValue ix l ToInt [a] (IntT t)
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
prim ix l (StrCompare c) [a, b] =
  extend ix l !(mlirValue l bool (Idr.strCmpOp c !(operand ix a) !(operand ix b)))
prim ix l (ToStr (SInt t)) [x] = value ix l StrT (Idr.strShowOp {isSigned = signed t} !(operand ix x))
prim ix l (ToStr SChar) [c] = primValue ix l StrFromChar [c] StrT
prim ix l (ToStr SDouble) [x] = value ix l StrT (Idr.strShowOp !(operand ix x))
prim ix l (FromStr (SInt t)) [s] = value ix l (IntT t) (Idr.strToIntOp {isSigned = signed t} !(operand ix s))
prim ix l (FromStr SDouble) [s] = primValue ix l StrToDouble [s] DoubleT
prim ix l (BigCompare c) [a, b] =
  extend ix l !(mlirValue l bool (Idr.bigCmpOp c !(operand ix a) !(operand ix b)))
prim ix l (ToBig (SInt t)) [x] = value ix l BigT (Idr.bigFromIntOp {isSigned = signed t} !(operand ix x))
prim ix l (ToBig SChar) [c] = value ix l BigT (Idr.bigFromIntOp !(operand ix c))
prim ix l (ToBig SDouble) [d] = primValue ix l BigFromDouble [d] BigT
prim ix l (FromBig (SInt t)) [b] = primValue ix l BigToInt [b] (IntT t)
prim ix l (FromBig SDouble) [b] = primValue ix l BigToDouble [b] DoubleT
-- The code point if the integer is one, else 0; `idr.to_char`
-- decides for the integers an `i64` holds, and 0 stands for the rest.
prim ix l (FromBig SChar) [b] = do
  lo <- literal ix l (LBig 0)
  hi <- literal ix l (LBig 0x10FFFF)
  big <- operand ix b
  ge <- mlirValue l bool (Idr.bigCmpOp CmpPredicate.Gte big !(operand ix lo))
  le <- mlirValue l bool (Idr.bigCmpOp CmpPredicate.Lte big !(operand ix hi))
  inRange <- mlirValue l bool (Arith.andiOp ge le)
  n <- mlirValue l (IntegerType 64) (Idr.bigToIntOp big)
  outside <- literal ix l (LInt IdrisInt (-1))
  m <- mlirValue l (IntegerType 64) (Arith.selectOp inRange n !(operand ix outside))
  value ix l CharT (Idr.toCharOp {isSigned = True} m)
prim ix l (NatCompare c) [a, b] =
  extend ix l !(mlirValue l bool (Idr.bigCmpOp c !(operand ix a) !(operand ix b)))
prim ix l (ArrayLength _) [a] = do
  n <- memrefLength l !(operand ix a)
  pure (val n.name (IntT IdrisInt) Many)
prim ix l p vs = internal ("the primitive " ++ show p ++ " with " ++ show (length vs) ++ " operands")

------------------------------------------------------------------------------
-- Constructors
------------------------------------------------------------------------------

||| A constructor application (`idr.con`): the constructor is its tag within
||| its value's type, built with every field (no hole).
export
con : Index -> Loc -> Con -> List Val -> E Val
con ix l c vs0 = do
  vs <- traverse (\(f, v) => coerce ix l f.quantity v) (zip c.fields vs0)
  fields <- traverse (operand ix) vs
  value ix l (DataT c.id.dataId) (\t => Idr.conOp (cast c.tag) fields t [])

mutual
  ||| The value a variable names: itself, or the constructor a match took
  ||| apart, built again from its fields as the region holds them; in the
  ||| owned stage the cell it came from is reused.
  export
  force : Index -> Loc -> Val -> E Val
  force ix l (MkVal n t u (Taken c fs)) = do
    Just k <- pure (lookup c ix.cons)
      | Nothing => internal ("the constructor " ++ show c ++ ", which is not declared")
    con ix l k !(forceAll ix l fs)
  force ix l v = pure v

  forceAll : Index -> Loc -> List Val -> E (List Val)
  forceAll ix l [] = pure []
  forceAll ix l (v :: vs) = (::) <$> force ix l v <*> forceAll ix l vs

||| The one constructor of a data instance.
export
only : Index -> DataId -> E Con
only ix d = case (.cons) <$> lookup d ix.datas of
  Just [c] => pure c
  _ => internal (show d ++ " does not have exactly one constructor")

||| The `IORes` of an IO operation's result and its next world.
export
ioResult : Index -> Loc -> DataId -> Val -> Val -> E Val
ioResult ix l res x w = con ix l !(only ix res) [x, w]

||| The unit of a data instance whose one constructor has no fields.
unitOf : Index -> Ty -> Maybe Con
unitOf ix (DataT d) = case (.cons) <$> lookup d ix.datas of
  Just [c] => if null c.fields then Just c else Nothing
  _ => Nothing
unitOf ix _ = Nothing

------------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------------

||| An effect: the primitive `p`, which performs IO, on its operands, after
||| its guards, and the `IORes` instance `res` of its value and the next
||| world. `types` are the types its call fixes (a buffer word's). The
||| primitive takes the world as its last operand (one without operands
||| makes a world) and gives the next as its last result. A unit value
||| carries nothing, so the op gives no result for it: the unit is built
||| after it. `idr.array.get` always yields the element: its type has a
||| value result even when the element is a unit.
export
effect : Index -> Loc -> IdrPrim -> List Ty -> List Val -> DataId -> E (Maybe Val)
effect ix l p types vs res = do
  unless (primPerformsIO p) $
    internal (show (Op p) ++ ", which performs no IO, as an effect")
  mk <- only ix res
  [x, _] <- pure (map typeOf mk.fields)
    | _ => internal (show res ++ " does not hold a value and a world")
  args <- traverse (operand ix) vs
  let unit = unitOf ix x
  let gives = case (p, unit) of
                (ArrayGet, _) => [mlirType x]
                (_, Just _) => []
                (_, Nothing) => [mlirType x]
  names <- placed l types (primOp p args (gives ++ [mlirType WorldT]))
  v <- case (p, unit, head' names) of
    (ArrayGet, _, Just n) => pure (val n x Many)
    (_, Just u, _) => con ix l u []
    (_, Nothing, Just n) => pure (val n x Many)
    _ => internal (show (Op p) ++ " without its value")
  Just w <- pure (last' names)
    | Nothing => internal (show (Op p) ++ " without the next world")
  Just <$> con ix l mk [v, val w WorldT Many]
