-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The operations of the module that one layer of a term becomes:
||| literals, primitives, constructor applications and effects, each made by
||| its op's builder (IdrisMLIR.Dialect.*) or from the specification's op
||| value. The builder of a partial op gives the op with its guards, which
||| the specification declares (`Guarded`), and the op is written after
||| them: each guard an op checking the operand, at its site, the op taking
||| the guard's result in the operand's place, so it stays below its check.
||| A total op's builder gives the op alone.
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
import IdrisMLIR.Spec.Core.Dialect
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Op as Spec
import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Ops.IO
import IdrisMLIR.Spec.Ops.Numeric
import IdrisMLIR.Spec.Ops.Platform
import IdrisMLIR.Spec.Ops.Values
import IdrisMLIR.Spec.Runtime.Clocks
import IdrisMLIR.Spec.Runtime.Endings
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
||| its span, and the definition the code is in, as Idris names it, which a
||| cause that names a function prints. Code at no place of a file reports
||| at the place the program's location gives, the main module's, which
||| every refusal-free program has.
export
siteOf : Loc -> E MlirAttr
siteOf l = do
  st <- get
  let function = show st.definition
  pure $ case (locFile l, locSpan l) of
    (Just file, Just s) => Idr (SiteAttr file (cast (s.startLine + 1)) (cast (s.startCol + 1)) function)
    _ => Idr (SiteAttr "" 0 0 function)

------------------------------------------------------------------------------
-- Guards
------------------------------------------------------------------------------

||| An op of one result of type `t`, written as it is at `at`: a guard's
||| own work, which has no guard of its own.
unguarded : Location -> MlirType -> (MlirType -> Op) -> E Value
unguarded at t build = do
  r <- fresh
  append (MkStatement (Just r) (build t) at)
  pure (MkValue (Bound r 0) t)

||| The length of an array a world orders, its memref's dimension, as an
||| `Int`, the variable `binder` bound to it.
memrefLength : {default Nothing binder : Maybe Binding} -> {default Nothing stands : Maybe Shown} -> Loc -> Value -> E Value
memrefLength l a = do
  zero <- unguarded (At l) IndexType (Arith.constantOp (IntegerAttr 0 OfIndex))
  n <- unguarded (At l) IndexType (MemRef.dimOp a zero)
  unguarded (madeAtPlace binder (placeOf stands l) Many) (IntegerType 64) (Arith.indexCastOp n)

||| The op of a guarded builder after its guards: each guard's check op, as
||| its builder makes it, written at `l`, its site the op's, in order, on
||| the operand it checks, its result, of that operand's type, what
||| follows takes in place of the operand checked.
checked : Loc -> Guarded -> E Op
checked l (Unguarded o) = pure o
checked l (Checking check x next) = do
  site <- siteOf l
  c <- unguarded (At l) x.type (const (check site x))
  checked l (next c)

||| The name of the specification's op value: of the dialect its home is.
specName : Spec.Op i o a r -> OpName
specName op = case op.home of
  InIdr => MkOpName Dialect.Idr (mnemonicText op.mnemonic)
  InTransform _ => MkOpName Transform (mnemonicText op.mnemonic)

||| The guards the specification declares for an op, on its operands, one
||| per group, before the op `made` of their results: each its kind's check
||| op (`checkOf`) on the operand at its first position and those at the
||| others, with its cause, and the op takes its result in that operand's
||| place. A position is a `Fin` of the op's own groups, so it names an
||| operand the op has.
specGuarded : List (Guard (Fin i)) -> Vect i Value -> (Vect i Value -> Op) -> Guarded
specGuarded [] vs made = Unguarded (made vs)
specGuarded (g :: gs) vs made =
  let at = Vect.head g.given in
  Checking (Idr.checkOf g.check g.cause (map (\k => index k vs) (Vect.tail g.given))) (index at vs)
           (\c => specGuarded gs (replaceAt at c vs) made)

||| A fixed result type, as the specification names it.
builtType : Buildable -> MlirType
builtType BuiltI1 = IntegerType 1
builtType BuiltI8 = IntegerType 8
builtType BuiltI16 = IntegerType 16
builtType BuiltI32 = IntegerType 32
builtType BuiltI64 = IntegerType 64
builtType BuiltIndex = IndexType
builtType BuiltF64 = F64Type
builtType BuiltNone = NoneType

||| An op of the dialect, by the specification's op value, on its operands,
||| one per group, with the guards the specification declares for it, so no
||| partial op is written without them. Its results are of the types `ts`
||| where it states them; where it infers them, each is its rule's, from
||| the operands it is written on, and `ts` is not read; where it fixes
||| their grades, `ts` are their carriers, each put at its grade; so no
||| type or grade the op fixes is stated.
specOp : Spec.Op i o 0 0 -> Vect i Value -> List MlirType -> Guarded
specOp op vs ts = specGuarded op.guards vs (\ws => MkOp (specName op) (toList ws) [] [] [] (typed ws op.typing))
  where
    -- A result's type by its rule, from the operands.
    ruled : Vect k Value -> TypeRule k -> MlirType
    ruled ws (OperandType g) = (index g ws).type
    ruled ws (ElementTypeOf g) = elementTypeOrSelf (index g ws).type
    ruled ws (FixedType b) = builtType b

    -- A carrier at the grade the op fixes, never its bare one.
    carried : FixedGrade -> MlirType -> MlirType
    carried g t = Idr (GradedType g.uses (Just g.hold) t)

    typed : Vect k Value -> ResultTyping k n -> List MlirType
    typed ws StatedTypes = ts
    typed ws (InferredTypes rules) = toList (map (ruled ws) rules)
    typed ws (CarriersAt grades) = zipWith carried (toList grades) ts

------------------------------------------------------------------------------
-- Writing ops
------------------------------------------------------------------------------

||| A total op that gives no values, where it stands, at `at`: it binds
||| none.
export
placed : Location -> Op -> E ()
placed at o = append (MkStatement Nothing o at)

||| A total op that gives values, where it stands, at `at`, and its
||| statement's number, which its results are bound at (`Bound`). Whether
||| an op gives values is its builder's, from the specification, so the
||| caller that names the op chooses this or `placed` and nothing asks.
export
numbered : Location -> Op -> E Nat
numbered at o = do
  r <- fresh
  append (MkStatement (Just r) o at)
  pure r

||| The op of a guarded builder that gives no values, where it stands,
||| after its guards.
export
place : Loc -> Guarded -> E ()
place l g = placed (At l) !(checked l g)

||| A total op with one result, of type `t`, at `at`.
export
mlirValueAt : Location -> MlirType -> (MlirType -> Op) -> E Value
mlirValueAt at t build = do
  r <- fresh
  append (MkStatement (Just r) (build t) at)
  pure (MkValue (Bound r 0) t)

||| A total op with one result, of an MLIR type that is no Core type's (a
||| condition, an index).
export
mlirValue : Loc -> MlirType -> (MlirType -> Op) -> E Value
mlirValue l = mlirValueAt (At l)

||| A total op with one result, of a Core type, used as `u` says and freed
||| by its count, the variable `binder` bound to it, at the library
||| definition `stands` where the registry lowered one to it: a match's
||| value at the uses its context takes it at, a call's result once, as
||| its callee returns it.
export
valueAt : {default Nothing binder : Maybe Binding} -> {default Nothing stands : Maybe Shown} -> Index -> Loc -> Uses -> Ty -> (MlirType -> Op) -> E Val
valueAt ix l u t build = do
  r <- mlirValueAt (madeAtPlace binder (placeOf stands l) u) (gradedType ix u made t) build
  pure (val r.name t u made)

||| A total op with one result, of a Core type, used many times and freed
||| by its count (`valueAt`).
export
value : {default Nothing binder : Maybe Binding} -> {default Nothing stands : Maybe Shown} -> Index -> Loc -> Ty -> (MlirType -> Op) -> E Val
value ix l t build = valueAt {binder} {stands} ix l Many t build

||| A total op with one result, of a Core type, held as `h` gives: a
||| literal's constant is static data.
export
heldValue : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Hold -> Ty -> (MlirType -> Op) -> E Val
heldValue ix l h t build = do
  r <- mlirValueAt (madeAt binder l Many) (gradedType ix Many h t) build
  pure (val r.name t Many h)

||| A total op with one result, of a Core type, built from the type's
||| carrier, at the grade `g` the op fixes, which its builder puts around
||| the carrier, the variable `binder` bound to it: a small.
export
carriedValue : {default Nothing binder : Maybe Binding} -> Index -> Loc -> FixedGrade -> Ty -> (MlirType -> Op) -> E Val
carriedValue ix l g t build = do
  r <- numbered (madeAt binder l g.uses) (build (mlirType ix t))
  pure (val (Bound r 0) t g.uses g.hold)

||| A partial op with one result, of a Core type, after its guards, used
||| many times and held as `held` says, the variable `binder` bound to it,
||| at the library definition `stands` where the registry lowered one to
||| it.
export
guardedValue : {default Nothing binder : Maybe Binding} -> {default Nothing stands : Maybe Shown}
            -> {default made held : Hold} -> Index -> Loc -> Ty -> (MlirType -> Guarded) -> E Val
guardedValue ix l t build = do
  o <- checked l (build (gradedType ix Many held t))
  r <- fresh
  append (MkStatement (Just r) o (madeAtPlace binder (placeOf stands l) Many))
  pure (val (Bound r 0) t Many held)

||| A total op without results.
export
statement : Loc -> Op -> E ()
statement l o = placed (At l) o

||| A value where the module expects it used as `use`, the variable
||| `binder` bound to it: a value used once where one used many times is
||| expected is cast to it, its one use, and a value used many times fills
||| a binder of quantity 1, as Idris lets any value do (`idr.lin.cast`).
||| The cast holds what a value at its uses may before references are
||| counted (`uncountedHold`): out of a linear position, a value used many
||| times claims nothing. Static data stands where a value its count frees
||| is asked with no op between, as the grade's order says. Nothing is
||| counted: the uses are the binders'.
export
coerce : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Uses -> Val -> E Val
coerce ix l use v = case (v.uses, use) of
  (Once, Many) => cast Many
  (Many, Once) => cast Once
  _ => pure v
  where
    cast : Uses -> E Val
    cast u = do
      let v' = { uses := u, hold := uncountedHold u v.hold } v
      r <- mlirValueAt (madeAt binder l u) (valueType ix v') (Idr.linCastOp (operand ix v) [])
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
  (Arith.constantOp (IntegerAttr (twos (width t) n) (OfWidth (width t))))
literal ix l (LChar c) = value {binder} ix l CharT (Arith.constantOp (IntegerAttr c (OfWidth 32)))
literal ix l (LDouble d) = value {binder} ix l DoubleT (Arith.constantOp (FloatAttr d F64Type))
literal ix l (LStr s) = heldValue {binder} ix l Hold.Static StrT (Idr.constantOp (StringAttr s))
literal ix l (LBig n) = heldValue {binder} ix l Hold.Static BigT (Idr.constantOp (Idr (BigAttr n)))
literal ix l (LNat n) = heldValue {binder} ix l Hold.Static (NatT (INat (integerToNat n))) (Idr.constantOp (Idr (BigAttr n)))

------------------------------------------------------------------------------
-- Primitives
------------------------------------------------------------------------------

||| A comparison's result.
bool : MlirType
bool = IntegerType 1

||| The `arith.cmpi` predicate: `Char`s compare as code points.
cmpi : Comparison -> Signedness -> CmpIPredicate
cmpi Values.Eq _ = CmpIPredicate.Eq
cmpi Values.Lt Signed = CmpIPredicate.Slt
cmpi Values.Lt Unsigned = CmpIPredicate.Ult
cmpi Values.Lte Signed = CmpIPredicate.Sle
cmpi Values.Lte Unsigned = CmpIPredicate.Ule
cmpi Values.Gt Signed = CmpIPredicate.Sgt
cmpi Values.Gt Unsigned = CmpIPredicate.Ugt
cmpi Values.Gte Signed = CmpIPredicate.Sge
cmpi Values.Gte Unsigned = CmpIPredicate.Uge

||| The `arith.cmpf` predicate: ordered, so false on NaN.
cmpf : Comparison -> CmpFPredicate
cmpf Values.Eq = CmpFPredicate.OEQ
cmpf Values.Lt = CmpFPredicate.OLT
cmpf Values.Lte = CmpFPredicate.OLE
cmpf Values.Gt = CmpFPredicate.OGT
cmpf Values.Gte = CmpFPredicate.OGE

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
||| of an unsigned one they are `arith`'s, whose builders give the guard
||| that the divisor is not zero, as the specification admits them.
intArith : Maybe Binding -> Maybe Shown -> Index -> Loc -> ArithOp -> IntTy -> Val -> Val -> E Val
intArith binder stands ix l Add t x y = value {binder} {stands} ix l (IntT t) (Arith.addiOp (operand ix x) (operand ix y))
intArith binder stands ix l Sub t x y = value {binder} {stands} ix l (IntT t) (Arith.subiOp (operand ix x) (operand ix y))
intArith binder stands ix l Mul t x y = value {binder} {stands} ix l (IntT t) (Arith.muliOp (operand ix x) (operand ix y))
intArith binder stands ix l And t x y = value {binder} {stands} ix l (IntT t) (Arith.andiOp (operand ix x) (operand ix y))
intArith binder stands ix l Or t x y = value {binder} {stands} ix l (IntT t) (Arith.oriOp (operand ix x) (operand ix y))
intArith binder stands ix l Xor t x y = value {binder} {stands} ix l (IntT t) (Arith.xoriOp (operand ix x) (operand ix y))
intArith binder stands ix l Div t x y = case signedness t of
  Signed => guardedValue {binder} {stands} ix l (IntT t) (Idr.intDivSOp (operand ix x) (operand ix y))
  Unsigned => guardedValue {binder} {stands} ix l (IntT t) (Arith.divuiOp (operand ix x) (operand ix y))
intArith binder stands ix l Mod t x y = case signedness t of
  Signed => guardedValue {binder} {stands} ix l (IntT t) (Idr.intModSOp (operand ix x) (operand ix y))
  Unsigned => guardedValue {binder} {stands} ix l (IntT t) (Arith.remuiOp (operand ix x) (operand ix y))

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
extend : Maybe Binding -> Maybe Shown -> Index -> Loc -> Value -> E Val
extend binder stands ix l c = value {binder} {stands} ix l (IntT IdrisInt) (Arith.extuiOp c)

||| A primitive on its operands, in Idris's order (an op of the dialect's in
||| the op's), the variable `binder` bound to its value.
export
prim : Maybe Binding -> Maybe Shown -> Index -> Loc -> Prim k -> Vect k Val -> E Val
-- An op's result is held as its declaration says where its type holds
-- references.
prim binder stands ix l (Op op r h) vs = guardedValue {binder} {stands} {held = h} ix l r (\t => specOp op (map (operand ix) vs) [t])
prim binder stands ix l (IntOp op t) [a, b] = intArith binder stands ix l op t a b
prim binder stands ix l (IntShift s t) [a, b] = value {binder} {stands} ix l (IntT t) (shiftOp s (signedness t) (operand ix a) (operand ix b))
prim binder stands ix l (FloatOp op) [a, b] = value {binder} {stands} ix l DoubleT (floatArith op (operand ix a) (operand ix b))
prim binder stands ix l Negate [a] = value {binder} {stands} ix l DoubleT (Arith.negfOp (operand ix a))
prim binder stands ix l (Math1 f) [a] = value {binder} {stands} ix l DoubleT (math1 f (operand ix a))
prim binder stands ix l Pow [a, b] = value {binder} {stands} ix l DoubleT (Math.powfOp (operand ix a) (operand ix b))
prim binder stands ix l (Compare c (SIntegral t)) [a, b] =
  extend binder stands ix l !(mlirValue l bool (Arith.cmpiOp (cmpi c (likeSignedness t)) (operand ix a) (operand ix b)))
prim binder stands ix l (Compare c SDouble) [a, b] =
  extend binder stands ix l !(mlirValue l bool (Arith.cmpfOp (cmpf c) (operand ix a) (operand ix b)))
prim binder stands ix l (Cast (IntToInt (SInt f) SChar)) [a] = case signedness f of
  Signed => value {binder} {stands} ix l CharT (const (Idr.intToCharSOp (operand ix a)))
  Unsigned => value {binder} {stands} ix l CharT (const (Idr.intToCharUOp (operand ix a)))
-- An integral type of the width of another is the other retyped; a wider
-- one is truncated, a narrower one extended by the source's sign.
prim binder stands ix l (Cast (IntToInt from to)) [a] =
  if likeWidth from == likeWidth to then pure ({ type := likeTy to } a)
  else if likeWidth from > likeWidth to then value {binder} {stands} ix l (likeTy to) (Arith.trunciOp (operand ix a))
  else case likeSignedness from of
    Signed => value {binder} {stands} ix l (likeTy to) (Arith.extsiOp (operand ix a))
    Unsigned => value {binder} {stands} ix l (likeTy to) (Arith.extuiOp (operand ix a))
prim binder stands ix l (Cast (IntToDouble f)) [a] = case signedness f of
  Signed => value {binder} {stands} ix l DoubleT (Arith.sitofpOp (operand ix a))
  Unsigned => value {binder} {stands} ix l DoubleT (Arith.uitofpOp (operand ix a))
prim binder stands ix l (Cast (DoubleToInt t)) [a] = guardedValue {binder} {stands} ix l (IntT t) (Idr.f64ToIntOp (operand ix a))
prim binder stands ix l (StrCompare c) [a, b] =
  extend binder stands ix l !(mlirValue l bool (const (Idr.strCmpOp c (operand ix a) (operand ix b))))
prim binder stands ix l (ToStr (SIntegral (SInt t))) [x] = case signedness t of
  Signed => value {binder} {stands} ix l StrT (Idr.strShowSintOp (operand ix x))
  Unsigned => value {binder} {stands} ix l StrT (Idr.strShowUintOp (operand ix x))
prim binder stands ix l (ToStr (SIntegral SChar)) [c] = value {binder} {stands} ix l StrT (Idr.strFromCharOp (operand ix c))
prim binder stands ix l (ToStr SDouble) [x] = value {binder} {stands} ix l StrT (Idr.strShowDoubleOp (operand ix x))
prim binder stands ix l (FromStr (NInt t)) [s] = value {binder} {stands} ix l (IntT t) (Idr.strToIntOp (operand ix s))
prim binder stands ix l (FromStr NDouble) [s] = value {binder} {stands} ix l DoubleT (const (Idr.strToDoubleOp (operand ix s)))
prim binder stands ix l (BigCompare c) [a, b] =
  extend binder stands ix l !(mlirValue l bool (const (Idr.bigCmpOp c (operand ix a) (operand ix b))))
prim binder stands ix l (ToBig (SIntegral (SInt t))) [x] = case signedness t of
  Signed => value {binder} {stands} ix l BigT (Idr.bigFromSintOp (operand ix x))
  Unsigned => value {binder} {stands} ix l BigT (Idr.bigFromUintOp (operand ix x))
prim binder stands ix l (ToBig (SIntegral SChar)) [c] = value {binder} {stands} ix l BigT (Idr.bigFromUintOp (operand ix c))
prim binder stands ix l (ToBig SDouble) [d] = guardedValue {binder} {stands} ix l BigT (Idr.bigFromDoubleOp (operand ix d))
prim binder stands ix l (FromBig (SIntegral (SInt t))) [b] = value {binder} {stands} ix l (IntT t) (Idr.bigToIntOp (operand ix b))
-- The code point if the integer is one, else 0; `idr.int.to_char_s` decides
-- for the integers an `i64` holds, and 0 stands for the rest.
prim binder stands ix l (FromBig (SIntegral SChar)) [b] = do
  lo <- literal ix l (LBig 0)
  hi <- literal ix l (LBig 0x10FFFF)
  ge <- mlirValue l bool (const (Idr.bigCmpOp Values.Gte (operand ix b) (operand ix !(coerce ix l Many lo))))
  le <- mlirValue l bool (const (Idr.bigCmpOp Values.Lte (operand ix b) (operand ix !(coerce ix l Many hi))))
  inRange <- mlirValue l bool (Arith.andiOp ge le)
  n <- mlirValue l (IntegerType 64) (Idr.bigToIntOp (operand ix b))
  outside <- literal ix l (LInt IdrisInt (-1))
  m <- mlirValue l (IntegerType 64) (Arith.selectOp inRange n (operand ix outside))
  value {binder} {stands} ix l CharT (const (Idr.intToCharSOp m))
prim binder stands ix l (FromBig SDouble) [b] = value {binder} {stands} ix l DoubleT (const (Idr.bigToDoubleOp (operand ix b)))
prim binder stands ix l (NatCompare c) [a, b] =
  extend binder stands ix l !(mlirValue l bool (const (Idr.bigCmpOp c (operand ix a) (operand ix b))))
prim binder stands ix l (ArrayLength _) [a] = do
  n <- memrefLength {binder} {stands} l (operand ix a)
  pure (val n.name (IntT IdrisInt) Many made)

------------------------------------------------------------------------------
-- Constructors
------------------------------------------------------------------------------

||| The values a constructor's fields take: each at its field's quantity,
||| an array as its buffer (`bufferization.to_buffer`), since a cell holds
||| no tensor; none for the world, which is no value of the module.
fieldOperands : Index -> Loc -> Vect k Binder -> Vect k Val -> E (List Value)
fieldOperands ix l [] [] = pure []
fieldOperands ix l (MkBinder _ WorldT :: fs) (_ :: vs) = fieldOperands ix l fs vs
fieldOperands ix l (f :: fs) (v :: vs) = (::) <$> held f <*> fieldOperands ix l fs vs
  where
    held : Binder -> E Value
    -- An array's buffer, at the bare grade upstream's op gives it, fills
    -- its field at any quantity, as any value fills a binder of quantity
    -- 1. Nothing takes it over here: the buffer behind the tensor may be
    -- a slice, a parameter's or one read out of a cell, and only
    -- bufferization knows which buffer is an allocation, where it enters
    -- the grades.
    held (MkBinder _ (TensorT ds e)) = do
      t <- operand ix <$> coerce ix l Many v
      mlirValue l (fieldType ix (TensorT ds e)) (Bufferization.toBufferOp t)
    held b = operand ix <$> coerce ix l b.quantity v

||| A constructor application (`idr.data.con`), built with every field: its value
||| is of the family at the index terms its equation gives with its binders
||| substituted, refined to its constructor, which is how the op knows its
||| tag, made at the uses its one consumer takes it at, `once` where it fills
||| a quantity-1 position, so no cast drops what Idris proved. It claims
||| nothing: what a pass proves of it is the pass's to write. The variable
||| `binder` is bound to it.
export
con : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Uses -> Con k -> List ITerm -> Vect k Val -> E Val
con ix l u c bs vs = do
  os <- fieldOperands ix l c.fields vs
  let t = conType c bs
      refined = OneOf (c.tag ::: [])
  r <- mlirValueAt (madeAt binder l u) (valueTypeOf ix t u made refined) (Idr.dataConOp os [])
  pure (MkVal r.name t u made refined)

------------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------------

||| What an action wrote: nothing, or the one value it gives.
data Acted : Nat -> Type where
  ActedNone : Acted 0
  ActedOne : ValueId -> Acted 1

||| An effect: the IO action on its operands, after its checks, with no
||| world (its order is the effects its ops declare), and the `IORes` `res`
||| of what it gives, the variable `binder` bound to it. An action that
||| ends the process is a terminator: nothing follows it, so it gives
||| nothing.
export
effect : Maybe Binding -> Index -> Loc -> IOAction i o -> IOGives o -> Vect i Val -> Con 2 -> E (Maybe Val)
effect binder ix l a gives vs res = do
  Just done <- acted a vs
    | Nothing => pure Nothing
  Just <$> answer gives done
  where
    -- What a value-giving action gives, the type of its `IORes`'s field.
    given : Ty
    given = typeOf (head res.fields)

    givenType : MlirType
    givenType = gradedType ix Many made given

    -- The `IORes` of what the action gave.
    answer : IOGives n -> Acted n -> E Val
    answer (GivesUnit u) ActedNone = do
      v <- con ix l Many u [] []
      con {binder} ix l Many res [] [v, worldVal]
    answer GivesValue (ActedOne r) = con {binder} ix l Many res [] [val r given Many made, worldVal]

    int64 : Integer -> E Value
    int64 n = mlirValue l (IntegerType 64) (Arith.constantOp (IntegerAttr n (OfWidth 64)))

    -- An op written where it stands, after its guards, giving as many
    -- values as its action does.
    written : Gives n -> (List MlirType -> Guarded) -> E (Maybe (Acted n))
    written GivesNone build = Just ActedNone <$ place l (build [])
    written GivesOne build = do
      r <- numbered (At l) !(checked l (build [givenType]))
      pure (Just (ActedOne (Bound r 0)))

    -- A value an action gives, made by a total op.
    gave : E Value -> E (Maybe (Acted 1))
    gave made = Just . ActedOne . (.name) <$> made

    -- The offset of a span of `count` bytes in a buffer, checked to lie in
    -- the buffer's length: the span is the primitive's own, so its check
    -- is the frontend's to give.
    within : Value -> Value -> Value -> E Value
    within buf offset count = do
      size <- memrefLength l buf
      mlirValue l (IntegerType 64)
        (const (Idr.checkRangeOp ByteRangeOutsideBuffer !(siteOf l) offset count size))

    -- The bytes of the machine word a load or a store names.
    wordSize : BufferWord -> E Value
    wordSize w = int64 (natToInteger (wordBytes w))

    -- A size or an index of an array a world orders, an `Int`, as the
    -- `index` its op takes.
    asIndex : Value -> E Value
    asIndex v = mlirValue l IndexType (Arith.indexCastOp v)

    -- The value of an operand, at its own type.
    arg : Val -> Value
    arg = operand ix

    -- Two to a power, as a mask's bound.
    pow2 : Nat -> Integer
    pow2 Z = 1
    pow2 (S k) = 2 * pow2 k

    -- What the action wrote, on as many operands as it takes; nothing for
    -- an action that ends the process, which is a terminator.
    acted : IOAction k n -> Vect k Val -> E (Maybe (Acted n))
    -- The op's operands are one per group.
    acted (Runs {gives = g} op) xs = written g (specOp op (map arg xs))
    acted (ReadsClock k) [] =
      gave (mlirValue l givenType (const (Idr.ioClockOp k)))
    acted NeverRead [] = gave (int64 unreadable)
    acted (ReadsFileTime f) [times] =
      gave (mlirValue l givenType
              (const (Idr.handleFileTimeOp f (arg times))))
    acted (Queries q) [reading] = gave (query q (arg reading))
      where
        query : ClockQuery -> Value -> E Value
        query Valid r = do
          mark <- int64 unreadable
          isRead <- mlirValue l (IntegerType 1) (Arith.cmpiOp CmpIPredicate.Ne r mark)
          mlirValue l givenType (Arith.extuiOp isRead)
        query Seconds r = do
          bits <- int64 (natToInteger nanosecondBits)
          mlirValue l givenType (Arith.shruiOp r bits)
        query Nanoseconds r = do
          mask <- int64 (pow2 nanosecondBits - 1)
          mlirValue l givenType (Arith.andiOp r mask)
    -- A negative size makes an empty array: each size is clamped at zero
    -- before it reaches the allocation.
    acted (Accesses NewArray rank) xs = do
      zero <- int64 0
      ns <- traverse (\size => asIndex !(mlirValue l (IntegerType 64) (Arith.maxsiOp (arg size) zero))) (init xs)
      gave (mlirValue l givenType (Idr.arrayNewOp (toList ns) (arg (last xs))))
    -- An access takes each index as the `index` it casts to, which its
    -- builder's guard checks against the array.
    acted (Accesses GetElement rank) (arr :: indices) = do
      is <- traverse (asIndex . arg) indices
      written GivesOne (\_ => Idr.arrayGetOp (arg arr) (toList is) givenType)
    acted (Accesses SetElement rank) (arr :: rest) = do
      is <- traverse (asIndex . arg) (init rest)
      written GivesNone (\_ => Idr.arraySetOp (arg arr) (toList is) (arg (last rest)))
    acted (Moves (LoadWord w)) [buf, off] = do
      off' <- within (arg buf) (arg off) !(wordSize w)
      written GivesOne (specOp bufferLoad [arg buf, off'])
    acted (Moves (StoreWord w)) [buf, off, v] = do
      off' <- within (arg buf) (arg off) !(wordSize w)
      written GivesNone (specOp bufferStore [arg buf, off', arg v])
    acted (Moves CopyBytes) [src, srcOff, len, dst, dstOff] = do
      srcOff' <- within (arg src) (arg srcOff) (arg len)
      dstOff' <- within (arg dst) (arg dstOff) (arg len)
      written GivesNone (specOp bufferCopy [arg src, srcOff', arg len, arg dst, dstOff'])
    acted (Moves SetString) [buf, off, str] = do
      bytes <- mlirValue l (IntegerType 64) (const (Idr.strBytesLengthOp (arg str)))
      off' <- within (arg buf) (arg off) bytes
      written GivesNone (specOp bufferSetString [arg buf, off', arg str])
    acted (Moves GetString) [buf, off, len] = do
      off' <- within (arg buf) (arg off) (arg len)
      written GivesOne (specOp bufferGetString [arg buf, off', arg len])
    acted (Moves WriteBytes) [h, buf, off, count] = do
      off' <- within (arg buf) (arg off) (arg count)
      written GivesOne (specOp writeBytesOp [arg h, arg buf, off', arg count])
    acted (Moves ReadBytes) [h, buf, off, count] = do
      off' <- within (arg buf) (arg off) (arg count)
      written GivesOne (specOp readBytesOp [arg h, arg buf, off', arg count])
    acted Exits [status] = do
      place l (Idr.ioExitOp (arg status))
      pure Nothing
    acted DoesNothing [] = pure (Just ActedNone)
