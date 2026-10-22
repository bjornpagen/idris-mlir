-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The operations of the module that one layer of a term becomes:
||| literals, primitives, constructor applications and effects, each made by
||| its op's builder (IdrisMLIR.Dialect.*). The builder of a partial op
||| gives the op with its guards, which the specification declares
||| (`Guarded`), and the op is written after them: each guard an op checking
||| the operand, at its site, the op taking the guard's result in the
||| operand's place, so it stays below its check. A total op's builder gives
||| the op alone.
module IdrisMLIR.Emit.Operations

import IdrisMLIR.Dialect.Arith as Arith
import IdrisMLIR.Dialect.Bufferization as Bufferization
import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Dialect.Math as Math
import IdrisMLIR.Dialect.MemRef as MemRef
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Emit.Types
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Spec.Ops.Comparisons
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Syntax.Arith
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.List
import Data.List1
import Data.Maybe
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Sites
------------------------------------------------------------------------------

||| Where a crash or a guard reports it failed, as data the op holds
||| (`#idr.site`): the file and the 1-based line and column of the start of
||| its span. Code at no place of a file reports at the place the program's
||| location gives, the main module's, which every refusal-free program has.
export
siteOf : Loc -> MlirAttr
siteOf l = case (locFile l, locSpan l) of
  (Just file, Just s) => Idr (SiteAttr file (cast (s.startLine + 1)) (cast (s.startCol + 1)))
  _ => Idr (SiteAttr "" 0 0)

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
  unguarded (madeAt binder l Many) (IntegerType 64) (Arith.indexCastOp n)

||| The op of a guarded builder after its guards: each guard's check op
||| written at `l`, its site the op's, in order, the op taking each guard's
||| result in place of the operand it checks. A guard names its operand by
||| its position among the op's, which its builder knows; one past them is
||| the generator's error.
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
          Nonzero => pure (Idr.checkNonzeroOp x g.cause (siteOf l))
          Nonempty => pure (Idr.checkNonemptyOp x g.cause (siteOf l))
          Finite => pure (Idr.checkFiniteOp x g.cause (siteOf l))
          InBounds i => pure (Idr.checkInBoundsOp x i g.cause (siteOf l))
          InRange c size => pure (Idr.checkRangeOp x !(count c) !(count size) g.cause (siteOf l))
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

||| A total op with one result, of a Core type, used many times and freed
||| by its count, the variable `binder` bound to it.
export
value : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Ty -> (MlirType -> Op) -> E Val
value ix l t build = do
  r <- mlirValueAt (madeAt binder l Many) (gradedType ix Many Held.Counted t) build
  pure (val r.name t Many Held.Counted)

||| A total op with one result, of a Core type, held as `h` gives: a
||| literal's constant is static data.
export
heldValue : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Held -> Ty -> (MlirType -> Op) -> E Val
heldValue ix l h t build = do
  r <- mlirValueAt (madeAt binder l Many) (gradedType ix Many h t) build
  pure (val r.name t Many h)

||| A partial op with one result, of a Core type, after its guards, used
||| many times, the variable `binder` bound to it.
export
guardedValue : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Ty -> (MlirType -> Guarded) -> E Val
guardedValue ix l t build = do
  o <- checked l (build (gradedType ix Many Held.Counted t))
  r <- fresh
  append (MkStatement (Just r) o (madeAt binder l Many))
  pure (val r t Many Held.Counted)

||| A total op without results.
export
statement : Loc -> Op -> E ()
statement l o = ignore (placed (At l) o)

||| A value where the module expects it used as `use`, the variable
||| `binder` bound to it: a value used once where one used many times is
||| expected is cast to it, its one use, and a value used many times fills
||| a binder of quantity 1, as Idris lets any value do (`idr.lin.cast`).
||| Static data stands where a value its count frees is asked with no op
||| between, as the grade's order says. Nothing is counted: the uses are
||| the binders'.
export
coerce : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Uses -> Val -> E Val
coerce ix l use v = case (v.uses, use) of
  (Once, Many) => cast Many
  (Many, Once) => cast Once
  _ => pure v
  where
    cast : Uses -> E Val
    cast u = do
      let v' = { uses := u } v
      r <- mlirValueAt (madeAt binder l u) (valueType ix v') (Idr.linCastOp (operand ix v))
      pure ({ name := r.name } v')

------------------------------------------------------------------------------
-- Literals
------------------------------------------------------------------------------

||| A literal, the variable `binder` bound to it: integers and doubles are
||| `arith.constant`, strings, bigs and naturals `idr.constant`, static
||| data the run holds, never freed. A natural of any size is one constant,
||| read once at the boundary.
export
literal : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Lit -> E Val
literal ix l (LInt t n) = value {binder} ix l (IntT t)
  (Arith.constantOp (IntegerAttr (twos (width t) n) (IntegerType (width t))))
literal ix l (LChar c) = value {binder} ix l CharT (Arith.constantOp (IntegerAttr c (IntegerType 32)))
literal ix l (LDouble d) = value {binder} ix l DoubleT (Arith.constantOp (FloatAttr d F64Type))
literal ix l (LStr s) = heldValue {binder} ix l Held.Static StrT (Idr.constantOp (StringAttr s))
literal ix l (LBig n) = heldValue {binder} ix l Held.Static BigT (Idr.constantOp (Idr (BigAttr n)))
literal ix l (LNat n) = heldValue {binder} ix l Held.Static NatT (Idr.constantOp (Idr (BigAttr n)))

------------------------------------------------------------------------------
-- Primitives
------------------------------------------------------------------------------

||| A comparison's result.
bool : MlirType
bool = IntegerType 1

||| The `arith.cmpi` predicate: `Char`s compare as code points.
cmpi : CmpPredicate -> Signedness -> CmpIPredicate
cmpi CmpPredicate.Eq _ = CmpIPredicate.Eq
cmpi CmpPredicate.Lt Signed = CmpIPredicate.Slt
cmpi CmpPredicate.Lt Unsigned = CmpIPredicate.Ult
cmpi CmpPredicate.Lte Signed = CmpIPredicate.Sle
cmpi CmpPredicate.Lte Unsigned = CmpIPredicate.Ule
cmpi CmpPredicate.Gt Signed = CmpIPredicate.Sgt
cmpi CmpPredicate.Gt Unsigned = CmpIPredicate.Ugt
cmpi CmpPredicate.Gte Signed = CmpIPredicate.Sge
cmpi CmpPredicate.Gte Unsigned = CmpIPredicate.Uge

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
||| and wrapping ops are `arith`, whose integers are signless. Division and
||| remainder of a signed integer are Euclidean, the dialect's partial ops;
||| of an unsigned one they are `arith`'s, after the guard that its divisor
||| is not zero.
intArith : Maybe Binding -> Index -> Loc -> ArithOp -> IntTy -> Val -> Val -> E Val
intArith binder ix l Add t x y = value {binder} ix l (IntT t) (Arith.addiOp (operand ix x) (operand ix y))
intArith binder ix l Sub t x y = value {binder} ix l (IntT t) (Arith.subiOp (operand ix x) (operand ix y))
intArith binder ix l Mul t x y = value {binder} ix l (IntT t) (Arith.muliOp (operand ix x) (operand ix y))
intArith binder ix l And t x y = value {binder} ix l (IntT t) (Arith.andiOp (operand ix x) (operand ix y))
intArith binder ix l Or t x y = value {binder} ix l (IntT t) (Arith.oriOp (operand ix x) (operand ix y))
intArith binder ix l Xor t x y = value {binder} ix l (IntT t) (Arith.xoriOp (operand ix x) (operand ix y))
intArith binder ix l Div t x y = case signedness t of
  Signed => guardedValue {binder} ix l (IntT t) (Idr.intDivSOp (operand ix x) (operand ix y))
  Unsigned => do
    d <- mlirValue l (IntegerType (width t)) (Idr.checkNonzeroOp (operand ix y) DivisionByZero (siteOf l))
    value {binder} ix l (IntT t) (Arith.divuiOp (operand ix x) d)
intArith binder ix l Mod t x y = case signedness t of
  Signed => guardedValue {binder} ix l (IntT t) (Idr.intModSOp (operand ix x) (operand ix y))
  Unsigned => do
    d <- mlirValue l (IntegerType (width t)) (Idr.checkNonzeroOp (operand ix y) DivisionByZero (siteOf l))
    value {binder} ix l (IntT t) (Arith.remuiOp (operand ix x) d)

||| A shift of a fixed-width integer, an op per direction and signedness,
||| since a shift amount's signedness is part of the computation.
shiftOp : Shift -> Signedness -> Value -> Value -> MlirType -> Op
shiftOp ShiftLeft Signed = Idr.intShlSOp
shiftOp ShiftLeft Unsigned = Idr.intShlUOp
shiftOp ShiftRight Signed = Idr.intShrSOp
shiftOp ShiftRight Unsigned = Idr.intShrUOp

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
prim binder ix l (Op p r) vs = guardedValue {binder} ix l r (\t => pureOp p (map (operand ix) vs) [t])
prim binder ix l (IntOp op t) [a, b] = intArith binder ix l op t a b
prim binder ix l (IntShift s t) [a, b] = value {binder} ix l (IntT t) (shiftOp s (signedness t) (operand ix a) (operand ix b))
prim binder ix l (FloatOp op) [a, b] = value {binder} ix l DoubleT (floatArith op (operand ix a) (operand ix b))
prim binder ix l Negate [a] = value {binder} ix l DoubleT (Arith.negfOp (operand ix a))
prim binder ix l (Math1 f) [a] = value {binder} ix l DoubleT (math1 f (operand ix a))
prim binder ix l Pow [a, b] = value {binder} ix l DoubleT (Math.powfOp (operand ix a) (operand ix b))
prim binder ix l (Compare c (SIntegral t)) [a, b] =
  extend binder ix l !(mlirValue l bool (Arith.cmpiOp (cmpi c (likeSignedness t)) (operand ix a) (operand ix b)))
prim binder ix l (Compare c SDouble) [a, b] =
  extend binder ix l !(mlirValue l bool (Arith.cmpfOp (cmpf c) (operand ix a) (operand ix b)))
prim binder ix l (Cast (IntToInt (SInt f) SChar)) [a] = case signedness f of
  Signed => value {binder} ix l CharT (Idr.intToCharSOp (operand ix a))
  Unsigned => value {binder} ix l CharT (Idr.intToCharUOp (operand ix a))
-- An integral type of the width of another is the other retyped; a wider
-- one is truncated, a narrower one extended by the source's sign.
prim binder ix l (Cast (IntToInt from to)) [a] =
  if likeWidth from == likeWidth to then pure ({ type := likeTy to } a)
  else if likeWidth from > likeWidth to then value {binder} ix l (likeTy to) (Arith.trunciOp (operand ix a))
  else case likeSignedness from of
    Signed => value {binder} ix l (likeTy to) (Arith.extsiOp (operand ix a))
    Unsigned => value {binder} ix l (likeTy to) (Arith.extuiOp (operand ix a))
prim binder ix l (Cast (IntToDouble f)) [a] = case signedness f of
  Signed => value {binder} ix l DoubleT (Arith.sitofpOp (operand ix a))
  Unsigned => value {binder} ix l DoubleT (Arith.uitofpOp (operand ix a))
prim binder ix l (Cast (DoubleToInt t)) [a] = guardedValue {binder} ix l (IntT t) (Idr.doubleToIntOp (operand ix a))
prim binder ix l (StrCompare c) [a, b] =
  extend binder ix l !(mlirValue l bool (Idr.strCmpOp c (operand ix a) (operand ix b)))
prim binder ix l (ToStr (SIntegral (SInt t))) [x] = case signedness t of
  Signed => value {binder} ix l StrT (Idr.strShowSintOp (operand ix x))
  Unsigned => value {binder} ix l StrT (Idr.strShowUintOp (operand ix x))
prim binder ix l (ToStr (SIntegral SChar)) [c] = value {binder} ix l StrT (Idr.strFromCharOp (operand ix c))
prim binder ix l (ToStr SDouble) [x] = value {binder} ix l StrT (Idr.strShowDoubleOp (operand ix x))
prim binder ix l (FromStr (NInt t)) [s] = value {binder} ix l (IntT t) (Idr.strToIntOp (operand ix s))
prim binder ix l (FromStr NDouble) [s] = value {binder} ix l DoubleT (Idr.strToDoubleOp (operand ix s))
prim binder ix l (BigCompare c) [a, b] =
  extend binder ix l !(mlirValue l bool (Idr.bigCmpOp c (operand ix a) (operand ix b)))
prim binder ix l (ToBig (SIntegral (SInt t))) [x] = case signedness t of
  Signed => value {binder} ix l BigT (Idr.bigFromSintOp (operand ix x))
  Unsigned => value {binder} ix l BigT (Idr.bigFromUintOp (operand ix x))
prim binder ix l (ToBig (SIntegral SChar)) [c] = value {binder} ix l BigT (Idr.bigFromUintOp (operand ix c))
prim binder ix l (ToBig SDouble) [d] = guardedValue {binder} ix l BigT (Idr.bigFromDoubleOp (operand ix d))
prim binder ix l (FromBig (SIntegral (SInt t))) [b] = value {binder} ix l (IntT t) (Idr.bigToIntOp (operand ix b))
-- The code point if the integer is one, else 0; `idr.to_char_s` decides
-- for the integers an `i64` holds, and 0 stands for the rest.
prim binder ix l (FromBig (SIntegral SChar)) [b] = do
  lo <- literal ix l (LBig 0)
  hi <- literal ix l (LBig 0x10FFFF)
  ge <- mlirValue l bool (Idr.bigCmpOp CmpPredicate.Gte (operand ix b) (operand ix !(coerce ix l Many lo)))
  le <- mlirValue l bool (Idr.bigCmpOp CmpPredicate.Lte (operand ix b) (operand ix !(coerce ix l Many hi)))
  inRange <- mlirValue l bool (Arith.andiOp ge le)
  n <- mlirValue l (IntegerType 64) (Idr.bigToIntOp (operand ix b))
  outside <- literal ix l (LInt IdrisInt (-1))
  m <- mlirValue l (IntegerType 64) (Arith.selectOp inRange n (operand ix outside))
  value {binder} ix l CharT (Idr.intToCharSOp m)
prim binder ix l (FromBig SDouble) [b] = value {binder} ix l DoubleT (Idr.bigToDoubleOp (operand ix b))
prim binder ix l (NatCompare c) [a, b] =
  extend binder ix l !(mlirValue l bool (Idr.bigCmpOp c (operand ix a) (operand ix b)))
prim binder ix l (ArrayLength _) [a] = do
  n <- memrefLength {binder} l (operand ix a)
  pure (val n.name (IntT IdrisInt) Many Held.Counted)

------------------------------------------------------------------------------
-- Constructors
------------------------------------------------------------------------------

mutual
  ||| An index term with the terms `bs` substituted for the levels `0 ..`
  ||| of the scope it is written in: a constructor's equation or field in
  ||| the scope its value is made or read in, a callee's signature at a
  ||| call.
  export
  substitute : List ITerm -> ITerm -> ITerm
  substitute bs (IVar k) = fromMaybe IOpaque (getAt k bs)
  substitute bs (ISucc t k) = succ (substitute bs t) k
  substitute bs (ICon f c as) = ICon f c (substituteAll bs as)
  substitute bs (IType t) = IType (substTy bs t)
  substitute bs t = t

  substituteAll : List ITerm -> List ITerm -> List ITerm
  substituteAll bs [] = []
  substituteAll bs (t :: ts) = substitute bs t :: substituteAll bs ts

  ||| A type with the terms `bs` substituted for the levels of its scope.
  export
  substTy : List ITerm -> Ty -> Ty
  substTy bs (DataT f ts) = DataT f (substituteAll bs ts)
  substTy bs (FunT (MkBinder q a) r) = FunT (MkBinder q (substTy bs a)) (substTy bs r)
  substTy bs (LazyT a) = LazyT (substTy bs a)
  substTy bs (TensorT ds a) = TensorT ds (substTy bs a)
  substTy bs (MemRefT o a) = MemRefT o (substTy bs a)
  substTy bs t = t

||| The type of a constructor's value, its binders given: its family at its
||| equation, the binders substituted.
export
conType : Con k -> List ITerm -> Ty
conType c bs = DataT c.id.family (substituteAll bs c.equation)

||| The values a constructor's fields take: each at its field's quantity,
||| an array as its buffer (`bufferization.to_buffer`), since a cell holds
||| no tensor; none for the world, which is no value of the module.
fieldOperands : Index -> Loc -> Vect k Binder -> Vect k Val -> E (List Value)
fieldOperands ix l [] [] = pure []
fieldOperands ix l (MkBinder _ WorldT :: fs) (_ :: vs) = fieldOperands ix l fs vs
fieldOperands ix l (f :: fs) (v :: vs) = (::) <$> held f <*> fieldOperands ix l fs vs
  where
    held : Binder -> E Value
    held (MkBinder q (TensorT ds e)) = do
      t <- operand ix <$> coerce ix l Many v
      b <- mlirValue l (fieldType ix (TensorT ds e)) (Bufferization.toBufferOp t)
      case q of
        Many => pure b
        Once => mlirValue l (Idr (GradedType Once Nothing b.type)) (Idr.linCastOp b)
    held b = operand ix <$> coerce ix l b.quantity v

||| A constructor application (`idr.con`), built with every field: its value
||| is of the family at the index terms its equation gives with its binders
||| substituted, refined to its constructor, which is how the op knows its
||| tag. The variable `binder` is bound to it.
export
con : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Con k -> List ITerm -> Vect k Val -> E Val
con ix l c bs vs = do
  os <- fieldOperands ix l c.fields vs
  let v = MkVal "" (conType c bs) Many Held.Counted (OneOf (c.tag ::: []))
  r <- mlirValueAt (madeAt binder l Many) (valueType ix v) (Idr.dataConOp os)
  pure ({ name := r.name } v)

------------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------------

||| An effect: the IO primitive `p` on its operands, after its guards, with
||| no world (its order is the effects its op declares), and the `IORes`
||| `res` of what it gives, the variable `binder` bound to it. An action
||| that ends the process (`exit`) is a terminator: nothing follows it, so
||| it gives nothing.
export
effect : Maybe Binding -> Index -> Loc -> (p : IOPrim) -> IOGives (ioResult p) -> List Val -> Con 2 -> E (Maybe Val)
effect binder ix l Exit _ vs res = do
  ignore (place l (ioOp Exit (map (operand ix) vs) []))
  pure Nothing
effect binder ix l p gives vs0 res = do
  vs <- clamped p vs0
  Just <$> given gives vs
  where
    -- A negative size makes an empty array: the size of a new array is
    -- clamped at zero before it reaches the allocation.
    clamped : IOPrim -> List Val -> E (List Val)
    clamped ArrayNew (size :: rest) = do
      zero <- literal ix l (LInt IdrisInt 0)
      n <- mlirValue l (IntegerType 64) (Arith.maxsiOp (operand ix size) (operand ix zero))
      pure (val n.name (IntT IdrisInt) Many Held.Counted :: rest)
    clamped _ vs' = pure vs'

    world : Val
    world = val "" WorldT Once Held.Counted
    given : {0 r : IOResult} -> IOGives r -> List Val -> E Val
    given (GivesUnit u) vs = do
      ignore (place l (ioOp p (map (operand ix) vs) []))
      v <- con ix l u [] []
      con {binder} ix l res [] [v, world]
    given GivesValue vs = do
      let x = typeOf (head res.fields)
      Just n <- place l (ioOp p (map (operand ix) vs) [gradedType ix Many Held.Counted x])
        | Nothing => internal (ioName p ++ " gives no value")
      con {binder} ix l res [] [val n x Many Held.Counted, world]
