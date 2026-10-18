-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The operations of the contract that one layer of a term becomes:
||| literals, primitives, constructor applications and effects, each made by
||| its op's builder (IdrisMLIR.Dialect.*). The builder of a partial op
||| gives the op with its guards, which its ODS declares (`Guarded`), and
||| the op is written after them: each guard an op checking the operand,
||| the op taking the guard's result in the operand's place, so it stays
||| below its check. A total op's builder gives the op alone.
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
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Guards
------------------------------------------------------------------------------

||| An op of one result of type `t`, written as it is at `at`: a guard's
||| own work, which has no guard of its own.
unguarded : Location -> MlirType -> (MlirType -> Op) -> E Value
unguarded at t build = do
  r <- fresh
  append (MkStatement (Just r) (build t) at)
  pure (MkValue r t)

||| The length of an array a world orders, its memref's dimension, as an
||| `Int`, the variable `binder` bound to it.
memrefLength : {default Nothing binder : Maybe Binding} -> Loc -> Value -> E Value
memrefLength l a = do
  zero <- unguarded (At l) IndexType (Arith.constantOp (IntegerAttr 0 IndexType))
  n <- unguarded (At l) IndexType (MemRef.dimOp a zero)
  unguarded (madeAt binder l (IntT IdrisInt) Many) (IntegerType 64) (Arith.indexCastOp n)

||| The op of a guarded builder after its guards: each guard's check op
||| written at `l`, in order, the op taking each guard's result in place of
||| the operand it checks. A guard names its operand by its position among
||| the op's, which its builder knows; one past them is the generator's
||| error.
checked : Loc -> Guarded -> E Op
checked l g = foldlM check g.op g.guards
  where
    -- A count of bytes, as an `Int`: a value of the op's, the bytes of the
    -- word it loads or stores, a string's bytes, or an array's length.
    count : Count -> E Value
    count (CountOf v) = pure v
    count (WordOf (IntegerType w)) =
      unguarded (At l) (IntegerType 64) (Arith.constantOp (IntegerAttr (cast w `div` 8) (IntegerType 64)))
    count (WordOf F64Type) = unguarded (At l) (IntegerType 64) (Arith.constantOp (IntegerAttr 8 (IntegerType 64)))
    count (WordOf t) = internal ("a buffer word of type " ++ typeText t)
    count (BytesOf v) = unguarded (At l) (IntegerType 64) (Idr.strBytesLengthOp v)
    count (LengthOf v) = memrefLength l v

    check : Op -> Guard -> E Op
    check o g = case splitAt g.operand o.operands of
      (before, x :: after) => do
        build <- the (E (MlirType -> Op)) $ case g.check of
          Nonzero => pure (Idr.checkNonzeroOp x g.cause)
          Nonempty => pure (Idr.checkNonemptyOp x g.cause)
          Finite => pure (Idr.checkFiniteOp x g.cause)
          InBounds i => pure (Idr.checkInBoundsOp x i g.cause)
          InRange c size => pure (Idr.checkRangeOp x !(count c) !(count size) g.cause)
        checkedValue <- unguarded (At l) x.type build
        pure ({ operands := before ++ checkedValue :: after } o)
      (_, []) => internal (o.name ++ " has no operand " ++ show g.operand ++ " for its guard")

------------------------------------------------------------------------------
-- Writing ops
------------------------------------------------------------------------------

||| A total op where it stands, at `at`, and the name of its statement,
||| which binds its results (`resultAt`); an op of no results binds none.
export
placed : Location -> Op -> E (Maybe String)
placed at o = case o.results of
  [] => Nothing <$ append (MkStatement Nothing o at)
  _ :: _ => do
    r <- fresh
    append (MkStatement (Just r) o at)
    pure (Just r)

||| The op of a guarded builder where it stands, after its guards, and the
||| name of its statement.
export
place : Loc -> Guarded -> E (Maybe String)
place l g = placed (At l) !(checked l g)

||| A total op with one result, of type `t`, at `at`.
export
mlirValueAt : Location -> MlirType -> (MlirType -> Op) -> E Value
mlirValueAt at t build = do
  r <- fresh
  append (MkStatement (Just r) (build t) at)
  pure (MkValue r t)

||| A total op with one result, of an MLIR type that is no Core type's (a
||| condition, an index).
export
mlirValue : Loc -> MlirType -> (MlirType -> Op) -> E Value
mlirValue l = mlirValueAt (At l)

||| A total op with one result, of a Core type, held as itself, the
||| variable `binder` bound to it.
export
value : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Ty -> (MlirType -> Op) -> E Val
value ix l t build = do
  r <- mlirValueAt (madeAt binder l t Many) (mlirType t) build
  pure (MkVal r.name t Many)

||| A partial op with one result, of a Core type, after its guards, held as
||| itself, the variable `binder` bound to it.
export
guardedValue : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Ty -> (MlirType -> Guarded) -> E Val
guardedValue ix l t build = do
  o <- checked l (build (mlirType t))
  r <- fresh
  append (MkStatement (Just r) o (madeAt binder l t Many))
  pure (MkVal r t Many)

||| A total op without results.
export
statement : Loc -> Op -> E ()
statement l o = ignore (placed (At l) o)

||| A value where the contract expects it used as `use`, the variable
||| `binder` bound to it. A linear value where a plain one is expected is
||| used (`idr.lin.use`), its one use; a plain value in a linear position
||| enters it (`idr.lin.enter`), as Idris lets any value fill a binder of
||| quantity 1.
export
coerce : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Quantity -> Val -> E Val
coerce ix l use v = case (linear v.use v.type, linear use v.type) of
  (True, False) => value {binder} ix l v.type (Idr.linUseOp (operand v))
  (False, True) => do
    r <- mlirValueAt (madeAt binder l v.type One) (heldType One v.type) (Idr.linEnterOp (operand v))
    pure (MkVal r.name v.type One)
  _ => pure v

------------------------------------------------------------------------------
-- Literals
------------------------------------------------------------------------------

||| A literal, the variable `binder` bound to it: integers and doubles are
||| `arith.constant`, strings and bigs `idr.constant`.
export
literal : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Lit -> E Val
literal ix l (LInt t n) = value {binder} ix l (IntT t)
  (Arith.constantOp (IntegerAttr (twos (width t) n) (IntegerType (width t))))
literal ix l (LChar c) = value {binder} ix l CharT (Arith.constantOp (IntegerAttr c (IntegerType 32)))
literal ix l (LDouble d) = value {binder} ix l DoubleT (Arith.constantOp (FloatAttr d F64Type))
literal ix l (LStr s) = value {binder} ix l StrT (Idr.constantOp (StringAttr s))
literal ix l (LBig n) = value {binder} ix l BigT (Idr.constantOp (idr (BigAttr n)))
literal ix l (LNat n) = value {binder} ix l NatT (Idr.constantOp (idr (BigAttr (cast n))))

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

||| The `math` op of a C library function of one double, or an exact one.
math1 : UnaryMath -> Value -> MlirType -> Op
math1 Exp = Math.expOp
math1 Log = Math.logOp
math1 Sin = Math.sinOp
math1 Cos = Math.cosOp
math1 Tan = Math.tanOp
math1 ASin = Math.asinOp
math1 ACos = Math.acosOp
math1 ATan = Math.atanOp
math1 Sqrt = Math.sqrtOp
math1 Floor = Math.floorOp
math1 Ceiling = Math.ceilOp

||| Fixed-width arithmetic, the variable `binder` bound to it. The bitwise
||| and wrapping ops are `arith`, whose integers are signless; division and
||| remainder are Euclidean, each an op per signedness, partial.
intArith : Maybe Binding -> Index -> Loc -> ArithOp -> IntTy -> Val -> Val -> E Val
intArith binder ix l Add t x y = value {binder} ix l (IntT t) (Arith.addiOp (operand x) (operand y))
intArith binder ix l Sub t x y = value {binder} ix l (IntT t) (Arith.subiOp (operand x) (operand y))
intArith binder ix l Mul t x y = value {binder} ix l (IntT t) (Arith.muliOp (operand x) (operand y))
intArith binder ix l And t x y = value {binder} ix l (IntT t) (Arith.andiOp (operand x) (operand y))
intArith binder ix l Or t x y = value {binder} ix l (IntT t) (Arith.oriOp (operand x) (operand y))
intArith binder ix l Xor t x y = value {binder} ix l (IntT t) (Arith.xoriOp (operand x) (operand y))
intArith binder ix l Div t x y =
  guardedValue {binder} ix l (IntT t) ((if signed t then Idr.divsOp else Idr.divuOp) (operand x) (operand y))
intArith binder ix l Mod t x y =
  guardedValue {binder} ix l (IntT t) ((if signed t then Idr.modsOp else Idr.moduOp) (operand x) (operand y))

||| A shift of a fixed-width integer, an op per direction and signedness.
shiftOp : Shift -> IntTy -> Value -> Value -> MlirType -> Op
shiftOp ShiftLeft t = if signed t then Idr.shlsOp else Idr.shluOp
shiftOp ShiftRight t = if signed t then Idr.shrsOp else Idr.shruOp

||| Double arithmetic, `arith`'s.
floatArith : FArith -> Value -> Value -> MlirType -> Op
floatArith FAdd x y = Arith.addfOp x y
floatArith FSub x y = Arith.subfOp x y
floatArith FMul x y = Arith.mulfOp x y
floatArith FDiv x y = Arith.divfOp x y

||| A comparison's `i1` as an `Int`, the variable `binder` bound to it.
extend : Maybe Binding -> Index -> Loc -> Value -> E Val
extend binder ix l c = value {binder} ix l (IntT IdrisInt) (Arith.extuiOp c)

||| A primitive on its operands, in Idris's order (an op of the dialect's in
||| the op's), the variable `binder` bound to its value.
export
prim : Maybe Binding -> Index -> Loc -> Prim k -> Vect k Val -> E Val
prim binder ix l (Op p r) vs = guardedValue {binder} ix l r (\t => pureOp p (map operand vs) [t])
prim binder ix l (IntOp op t) [a, b] = intArith binder ix l op t a b
prim binder ix l (IntShift s t) [a, b] = value {binder} ix l (IntT t) (shiftOp s t (operand a) (operand b))
prim binder ix l (FloatOp op) [a, b] = value {binder} ix l DoubleT (floatArith op (operand a) (operand b))
prim binder ix l Negate [a] = value {binder} ix l DoubleT (Arith.negfOp (operand a))
prim binder ix l (Math1 f) [a] = value {binder} ix l DoubleT (math1 f (operand a))
prim binder ix l Pow [a, b] = value {binder} ix l DoubleT (Math.powfOp (operand a) (operand b))
prim binder ix l (Compare c (SIntegral t)) [a, b] =
  extend binder ix l !(mlirValue l bool (Arith.cmpiOp (cmpi c (likeSigned t)) (operand a) (operand b)))
prim binder ix l (Compare c SDouble) [a, b] =
  extend binder ix l !(mlirValue l bool (Arith.cmpfOp (cmpf c) (operand a) (operand b)))
prim binder ix l (Cast (IntToInt (SInt f) SChar)) [a] =
  value {binder} ix l CharT ((if signed f then Idr.toCharSOp else Idr.toCharUOp) (operand a))
-- An integral type of the width of another is the other retyped; a wider
-- one is truncated, a narrower one extended by the source's sign.
prim binder ix l (Cast (IntToInt from to)) [a] =
  if likeWidth from == likeWidth to then pure ({ type := likeTy to } a)
  else if likeWidth from > likeWidth to then value {binder} ix l (likeTy to) (Arith.trunciOp (operand a))
  else value {binder} ix l (likeTy to) ((if likeSigned from then Arith.extsiOp else Arith.extuiOp) (operand a))
prim binder ix l (Cast (IntToDouble f)) [a] =
  value {binder} ix l DoubleT ((if signed f then Arith.sitofpOp else Arith.uitofpOp) (operand a))
prim binder ix l (Cast (DoubleToInt t)) [a] = guardedValue {binder} ix l (IntT t) (Idr.toIntOp (operand a))
prim binder ix l (StrCompare c) [a, b] =
  extend binder ix l !(mlirValue l bool (Idr.strCmpOp c (operand a) (operand b)))
prim binder ix l (ToStr (SIntegral (SInt t))) [x] =
  value {binder} ix l StrT ((if signed t then Idr.strShowSintOp else Idr.strShowUintOp) (operand x))
prim binder ix l (ToStr (SIntegral SChar)) [c] = value {binder} ix l StrT (Idr.strFromCharOp (operand c))
prim binder ix l (ToStr SDouble) [x] = value {binder} ix l StrT (Idr.strShowDoubleOp (operand x))
prim binder ix l (FromStr (NInt t)) [s] = value {binder} ix l (IntT t) (Idr.strToIntOp (operand s))
prim binder ix l (FromStr NDouble) [s] = value {binder} ix l DoubleT (Idr.strToDoubleOp (operand s))
prim binder ix l (BigCompare c) [a, b] =
  extend binder ix l !(mlirValue l bool (Idr.bigCmpOp c (operand a) (operand b)))
prim binder ix l (ToBig (SIntegral (SInt t))) [x] =
  value {binder} ix l BigT ((if signed t then Idr.bigFromSintOp else Idr.bigFromUintOp) (operand x))
prim binder ix l (ToBig (SIntegral SChar)) [c] = value {binder} ix l BigT (Idr.bigFromUintOp (operand c))
prim binder ix l (ToBig SDouble) [d] = guardedValue {binder} ix l BigT (Idr.bigFromDoubleOp (operand d))
prim binder ix l (FromBig (SIntegral (SInt t))) [b] = value {binder} ix l (IntT t) (Idr.bigToIntOp (operand b))
-- The code point if the integer is one, else 0; `idr.to_char_s` decides
-- for the integers an `i64` holds, and 0 stands for the rest.
prim binder ix l (FromBig (SIntegral SChar)) [b] = do
  lo <- literal ix l (LBig 0)
  hi <- literal ix l (LBig 0x10FFFF)
  ge <- mlirValue l bool (Idr.bigCmpOp CmpPredicate.Gte (operand b) (operand lo))
  le <- mlirValue l bool (Idr.bigCmpOp CmpPredicate.Lte (operand b) (operand hi))
  inRange <- mlirValue l bool (Arith.andiOp ge le)
  n <- mlirValue l (IntegerType 64) (Idr.bigToIntOp (operand b))
  outside <- literal ix l (LInt IdrisInt (-1))
  m <- mlirValue l (IntegerType 64) (Arith.selectOp inRange n (operand outside))
  value {binder} ix l CharT (Idr.toCharSOp m)
prim binder ix l (FromBig SDouble) [b] = value {binder} ix l DoubleT (Idr.bigToDoubleOp (operand b))
prim binder ix l (NatCompare c) [a, b] =
  extend binder ix l !(mlirValue l bool (Idr.bigCmpOp c (operand a) (operand b)))
prim binder ix l (ArrayLength _) [a] = do
  n <- memrefLength {binder} l (operand a)
  pure (MkVal n.name (IntT IdrisInt) Many)

------------------------------------------------------------------------------
-- Constructors
------------------------------------------------------------------------------

||| A constructor application (`idr.con`): the constructor is its tag within
||| its value's type, built with every field, the variable `binder` bound
||| to it.
export
con : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Con k -> Vect k Val -> E Val
con ix l c vs0 = do
  vs <- traverse (\(f, v) => coerce ix l f.quantity v) (zip c.fields vs0)
  value {binder} ix l (DataT c.id.dataId) (Idr.conOp (cast c.tag) (toList (map operand vs)))

mutual
  ||| The value a variable stands for: itself, or the constructor a match
  ||| took apart, built again from its fields as the region holds them,
  ||| the variable `binder` bound to it; in the owned stage the cell it
  ||| came from is reused.
  export
  force : {default Nothing binder : Maybe Binding} -> Index -> Loc -> InScope -> E Val
  force ix l (Whole v) = pure v
  force ix l (Taken c fs _) = con {binder} ix l c !(forceAll ix l fs)

  forceAll : Index -> Loc -> Vect k InScope -> E (Vect k Val)
  forceAll ix l [] = pure []
  forceAll ix l (v :: vs) = (::) <$> force ix l v <*> forceAll ix l vs

------------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------------

||| An effect: the IO primitive `p` on its operands, which end with the
||| world, after its guards, and the `IORes` `res` of what it gives and the
||| next world, the variable `binder` bound to it. The op gives the next
||| world as its last result, after the value when it gives one; when it
||| gives none, the value is the unit `gives` names, built after it.
export
effect : Maybe Binding -> Index -> Loc -> (p : IOPrim) -> IOGives (ioResult p) -> List Val -> Con 2 -> E (Maybe Val)
effect binder ix l p gives vs res = Just <$> given gives
  where
    world : MlirType
    world = mlirType WorldT
    given : {0 r : IOResult} -> IOGives r -> E Val
    given (GivesUnit u) = do
      Just n <- place l (ioOp p (map operand vs) [world])
        | Nothing => internal (ioName p ++ " gives no next world")
      v <- con ix l u []
      con {binder} ix l res [v, MkVal (resultAt n 1 0) WorldT Many]
    given GivesValue = do
      let x = typeOf (head res.fields)
      Just n <- place l (ioOp p (map operand vs) [mlirType x, world])
        | Nothing => internal (ioName p ++ " gives no value")
      con {binder} ix l res [MkVal (resultAt n 2 0) x Many, MkVal (resultAt n 2 1) WorldT Many]
