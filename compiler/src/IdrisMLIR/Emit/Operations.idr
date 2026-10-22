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
import IdrisMLIR.Spec.Core.Enums
import IdrisMLIR.Spec.Core.Op as Spec
import IdrisMLIR.Spec.Core.Text
import IdrisMLIR.Spec.Ops.IO
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
  pure (MkValue r t)

||| The length of an array a world orders, its memref's dimension, as an
||| `Int`, the variable `binder` bound to it.
memrefLength : {default Nothing binder : Maybe Binding} -> Loc -> Value -> E Value
memrefLength l a = do
  zero <- unguarded (At l) IndexType (Arith.constantOp (IntegerAttr 0 IndexType))
  n <- unguarded (At l) IndexType (MemRef.dimOp a zero)
  unguarded (madeAt binder l Many) (IntegerType 64) (Arith.indexCastOp n)

||| A crash cause as an op's property: its number among the causes, as the
||| specification orders them.
export
causeAttr : Cause -> MlirAttr
causeAttr c = IntegerAttr (natToInteger (position causeClosed c)) (IntegerType 32)

||| The op of a guarded builder after its guards: each guard's check op
||| written at `l`, its site the op's, in order, on the op's operands at the
||| positions the guard is given, the first the one it checks, with the
||| cause its crash reports; the op takes each guard's result in place of
||| the operand it checks. The positions are the specification's, of the
||| op's own operands.
checked : Loc -> Guarded -> E Op
checked l g = foldlM check g.op g.guards
  where
    operandAt : Op -> Nat -> E Value
    operandAt o k = case getAt k o.operands of
      Just v => pure v
      Nothing => internal (o.name ++ " has no operand " ++ show k ++ " for its guard")

    check : Op -> Guard -> E Op
    check o gd = case gd.given of
      [] => internal (o.name ++ " has a guard given no operand")
      (at :: rest) => case splitAt at o.operands of
        (before, x :: after) => do
          others <- traverse (operandAt o) rest
          site <- siteOf l
          checkedValue <- unguarded (At l) x.type
                            (\ty => MkOp gd.check (x :: others)
                                         [ ("cause", IntegerAttr (natToInteger gd.cause) (IntegerType 32))
                                         , ("site", site) ] [] [] [ty])
          pure ({ operands := before ++ checkedValue :: after } o)
        (_, []) => internal (o.name ++ " has no operand " ++ show at ++ " for its guard")

||| A case's number among its enum's cases, as the dialect's C++ numbers
||| them: the position of the case the reference names.
caseNumber : CaseRef -> Nat
caseNumber c = go 0 (forget c.enum.cases)
  where
    go : Nat -> List Case -> Nat
    go n [] = n
    go n (x :: xs) = if x.name == c.name then n else go (S n) xs

||| The guards the specification declares for an op, as the printed
||| builders give them.
opGuards : Spec.Op i o a r -> List Guard
opGuards op =
  map (\g => MkGuard ("idr." ++ mnemonicText g.check) (map finToNat (forget g.given)) (caseNumber g.cause))
      op.guards

||| A pure op of the dialect, by the specification's op value, on its
||| operands, of the result type given, with the guards the specification
||| declares for it, so no partial op is written without them.
specOp : {i : Nat} -> Spec.Op i 1 0 0 -> Vect i Value -> MlirType -> Guarded
specOp op vs t = MkGuarded (MkOp (opName op) (toList vs) [] [] [] [t]) (opGuards op)

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
literal ix l (LNat n) = heldValue {binder} ix l Held.Static (NatT (INat (integerToNat n))) (Idr.constantOp (Idr (BigAttr n)))

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
    d <- mlirValue l (IntegerType (width t)) (Idr.checkNonzeroOp (causeAttr DivisionByZero) !(siteOf l) (operand ix y))
    value {binder} ix l (IntT t) (Arith.divuiOp (operand ix x) d)
intArith binder ix l Mod t x y = case signedness t of
  Signed => guardedValue {binder} ix l (IntT t) (Idr.intModSOp (operand ix x) (operand ix y))
  Unsigned => do
    d <- mlirValue l (IntegerType (width t)) (Idr.checkNonzeroOp (causeAttr DivisionByZero) !(siteOf l) (operand ix y))
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
prim binder ix l (Op op r) vs = guardedValue {binder} ix l r (specOp op (map (operand ix) vs))
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
prim binder ix l (Cast (DoubleToInt t)) [a] = guardedValue {binder} ix l (IntT t) (Idr.f64ToIntOp (operand ix a))
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
  ge <- mlirValue l bool (Idr.bigCmpOp Values.Gte (operand ix b) (operand ix !(coerce ix l Many lo)))
  le <- mlirValue l bool (Idr.bigCmpOp Values.Lte (operand ix b) (operand ix !(coerce ix l Many hi)))
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
  substTy bs (NatT t) = NatT (substitute bs t)
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
        Once => mlirValue l (IdrHand (GradedOf Once Nothing b.type)) (Idr.linCastOp b)
    held b = operand ix <$> coerce ix l b.quantity v

||| A constructor application (`idr.con`), built with every field: its value
||| is of the family at the index terms its equation gives with its binders
||| substituted, refined to its constructor, which is how the op knows its
||| tag. The variable `binder` is bound to it.
export
con : {default Nothing binder : Maybe Binding} -> Index -> Loc -> Con k -> List ITerm -> Vect k Val -> E Val
con ix l c bs vs = do
  os <- fieldOperands ix l c.fields vs
  let v = MkVal "" (conType c bs) Many Held.Exclusive (OneOf (c.tag ::: []))
  r <- mlirValueAt (madeAt binder l Many) (valueType ix v) (Idr.dataConOp os)
  pure ({ name := r.name } v)

------------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------------

||| What an action wrote: nothing, or the name of the one value it gives.
data Acted : Nat -> Type where
  ActedNone : Acted 0
  ActedOne : String -> Acted 1

||| An effect: the IO action on its operands, after its checks, with no
||| world (its order is the effects its ops declare), and the `IORes` `res`
||| of what it gives, the variable `binder` bound to it. An action that
||| ends the process is a terminator: nothing follows it, so it gives
||| nothing.
export
effect : Maybe Binding -> Index -> Loc -> IOAction o -> IOGives o -> List Val -> Con 2 -> E (Maybe Val)
effect binder ix l Exits _ vs res = do
  let [status] = vs
    | _ => internal "the exit given other than its status"
  statement l (Idr.ioExitOp !(siteOf l) (operand ix status))
  pure Nothing
effect binder ix l a gives vs res = Just <$> answer gives !(acted a vs)
  where
    world : Val
    world = val "" WorldT Once Held.Counted

    -- What a value-giving action gives, the type of its `IORes`'s field.
    given : Ty
    given = typeOf (head res.fields)

    givenType : MlirType
    givenType = gradedType ix Many Held.Counted given

    -- The `IORes` of what the action gave.
    answer : IOGives n -> Acted n -> E Val
    answer (GivesUnit u) ActedNone = do
      v <- con ix l u [] []
      con {binder} ix l res [] [v, world]
    answer GivesValue (ActedOne r) = con {binder} ix l res [] [val r given Many Held.Counted, world]

    int64 : Integer -> E Value
    int64 n = mlirValue l (IntegerType 64) (Arith.constantOp (IntegerAttr n (IntegerType 64)))

    -- An op written where it stands, after its guards, giving as many
    -- values as its action does.
    written : Gives n -> (List MlirType -> Guarded) -> E (Acted n)
    written GivesNone build = ActedNone <$ place l (build [])
    written GivesOne build = do
      Just r <- place l (build [givenType])
        | Nothing => internal "an IO op that gives a value wrote none"
      pure (ActedOne r)

    -- The offset of a span of `count` bytes in a buffer, checked to lie in
    -- the buffer's length: the span is the primitive's own, so its check
    -- is the frontend's to give.
    within : Value -> Value -> Value -> E Value
    within buf offset count = do
      size <- memrefLength l buf
      mlirValue l (IntegerType 64)
        (Idr.checkRangeOp (causeAttr ByteRangeOutsideBuffer) !(siteOf l) offset count size)

    -- The bytes of a machine word a buffer holds, by its type.
    wordBytes : Ty -> E Value
    wordBytes (IntT t) = int64 (natToInteger (width t `div` 8))
    wordBytes DoubleT = int64 8
    wordBytes t = internal ("a buffer word of type " ++ show t)

    -- A size or an index of an array a world orders, an `Int`, as the
    -- `index` its op takes.
    asIndex : Value -> E Value
    asIndex v = mlirValue l IndexType (Arith.indexCastOp v)

    -- An index checked to lie in the array it indexes, as the `index` the
    -- access takes: the check reads the `Int`, so it is written here,
    -- before the cast, and not by the access's own builder.
    checkedIndex : Value -> Value -> E Value
    checkedIndex arr i = do
      c <- mlirValue l (IntegerType 64) (Idr.checkInBoundsOp (causeAttr IndexOutOfBounds) !(siteOf l) i arr)
      asIndex c

    -- The values of the operands, at their own types.
    args : List Value
    args = map (operand ix) vs

    -- The operands but the last, and the last.
    lastApart : List Value -> Maybe (List Value, Value)
    lastApart [] = Nothing
    lastApart [x] = Just ([], x)
    lastApart (x :: xs) = (\(ys, y) => (x :: ys, y)) <$> lastApart xs

    -- Two to a power, as a mask's bound.
    pow2 : Nat -> Integer
    pow2 Z = 1
    pow2 (S k) = 2 * pow2 k

    acted : IOAction n -> List Val -> E (Acted n)
    acted (Runs {gives = g} op) _ =
      written g (\ts => MkGuarded (MkOp (opName op) args [] [] [] ts) (opGuards op))
    acted (ReadsClock k) _ =
      ActedOne . (.name) <$> mlirValue l givenType
        (Idr.ioClockOp (IntegerAttr (natToInteger (position clockKindClosed k)) (IntegerType 32)))
    acted NeverRead _ = ActedOne . (.name) <$> int64 unreadable
    acted (ReadsFileTime f) _ = case args of
      [times] => ActedOne . (.name) <$> mlirValue l givenType
                   (Idr.handleFileTimeOp (IntegerAttr (natToInteger (position fileTimeFieldClosed f)) (IntegerType 32)) times)
      _ => internal "a file time's field read given other than its file-time handle"
    acted (Queries q) _ = case args of
      [reading] => ActedOne . (.name) <$> query q reading
      _ => internal "a clock's query given other than its reading"
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
    acted (Accesses NewArray) _ = case lastApart args of
      Just (sizes, fill) => do
        zero <- int64 0
        ns <- traverse (\size => asIndex !(mlirValue l (IntegerType 64) (Arith.maxsiOp size zero))) sizes
        ActedOne . (.name) <$> mlirValue l givenType (Idr.arrayNewOp ns fill)
      Nothing => internal "a new array given no fill"
    acted (Accesses GetElement) _ = case args of
      arr :: indices => do
        is <- traverse (checkedIndex arr) indices
        ActedOne . (.name) <$> mlirValue l givenType (\t => (Idr.arrayGetOp arr is t).op)
      [] => internal "an element read given no array"
    acted (Accesses SetElement) _ = case args of
      arr :: rest => case lastApart rest of
        Just (indices, v) => do
          is <- traverse (checkedIndex arr) indices
          ActedNone <$ statement l (Idr.arraySetOp arr is v).op
        Nothing => internal "an element write given no value"
      [] => internal "an element write given no array"
    acted (Moves m) vals = moved m args (map (.type) vals)
      where
        moved : (m : BufferMove) -> List Value -> List Ty -> E (Acted (moveResults m))
        moved LoadWord [buf, off] _ = do
          off' <- within buf off !(wordBytes given)
          written GivesOne (\ts => MkGuarded (MkOp (opName bufferLoad) [buf, off'] [] [] [] ts) [])
        moved StoreWord [buf, off, v] [_, _, vt] = do
          off' <- within buf off !(wordBytes vt)
          written GivesNone (\ts => MkGuarded (MkOp (opName bufferStore) [buf, off', v] [] [] [] ts) [])
        moved CopyBytes [src, srcOff, len, dst, dstOff] _ = do
          srcOff' <- within src srcOff len
          dstOff' <- within dst dstOff len
          written GivesNone (\ts => MkGuarded (MkOp (opName bufferCopy) [src, srcOff', len, dst, dstOff'] [] [] [] ts) [])
        moved SetString [buf, off, str] _ = do
          bytes <- mlirValue l (IntegerType 64) (Idr.strBytesLengthOp str)
          off' <- within buf off bytes
          written GivesNone (\ts => MkGuarded (MkOp (opName bufferSetString) [buf, off', str] [] [] [] ts) [])
        moved GetString [buf, off, len] _ = do
          off' <- within buf off len
          written GivesOne (\ts => MkGuarded (MkOp (opName bufferGetString) [buf, off', len] [] [] [] ts) [])
        moved WriteBytes [h, buf, off, count] _ = do
          off' <- within buf off count
          written GivesOne (\ts => MkGuarded (MkOp (opName writeBytesOp) [h, buf, off', count] [] [] [] ts) [])
        moved ReadBytes [h, buf, off, count] _ = do
          off' <- within buf off count
          written GivesOne (\ts => MkGuarded (MkOp (opName readBytesOp) [h, buf, off', count] [] [] [] ts) [])
        moved m _ _ = internal "a buffer's move given other operands than it takes"
    acted Exits _ = internal "the exit written as an action that returns"
    acted DoesNothing _ = pure ActedNone
