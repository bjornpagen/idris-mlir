||| The operations of the contract that one layer of a term becomes:
||| literals, primitives, constructor applications and effects, each made by
||| its op's builder (IdrisMLIR.Dialect.*). A partial primitive is a guard
||| and a total op: the guard checks the operand, and the op takes the
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
  (Arith.constantOp (IntegerAttr (twos (width t) n) (IntegerType (width t))))
literal ix l (LChar c) = value ix l CharT (Arith.constantOp (IntegerAttr c (IntegerType 32)))
literal ix l (LDouble d) = value ix l DoubleT (Arith.constantOp (FloatAttr d F64Type))
literal ix l (LStr s) = value ix l StrT (Idr.constantOp (StringAttr s))
literal ix l (LBig n) = value ix l BigT (Idr.constantOp (Idr (BigAttr (show n))))
literal ix l (LNat n) = value ix l NatT (Idr.constantOp (Idr (BigAttr (show n))))

||| The erased value.
export
erasedValue : Index -> Loc -> E Val
erasedValue ix l = value ix l ErasedT (Idr.constantOp (Idr ErasedAttr))

||| A comparison's result.
bool : MlirType
bool = IntegerType 1

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

------------------------------------------------------------------------------
-- Guards
------------------------------------------------------------------------------

||| The length of an array: its memref's dimension, an index, as an `Int`.
arrayLength : Index -> Loc -> Val -> E Val
arrayLength ix l a = do
  zero <- mlirValue l IndexType (Arith.constantOp (IntegerAttr 0 IndexType))
  n <- mlirValue l IndexType (MemRef.dimOp !(operand ix a) zero)
  value ix l (IntT IdrisInt) (Arith.indexCastOp n)

||| How many bytes from an offset a buffer operation touches: the operand at
||| an index, the size of the word an effect stores or loads (its type
||| argument), or the bytes of the string at an index.
data Count = CountAt Nat | WordSize | BytesOf Nat

||| What a guard (`idr.check.*`) checks of the operand it guards, with the
||| other operands it reads by their index among the primitive's: an index
||| below the length of the string or array at an index, or an offset whose
||| bytes lie in the buffer at an index.
data Guard = Nonzero | Nonempty | Byte | Finite | IndexIn Nat | RangeIn Count Nat

divisionByZero, nonFinite, outOfBounds, outsideBuffer : String
divisionByZero = "division by zero"
nonFinite = "cast of a non-finite Double"
outOfBounds = "array index out of bounds"
outsideBuffer = "a byte range outside the buffer"

||| An array access's guard: its index below the length of the array before
||| it, for an array of rank 1. An IORef's one element has no index.
indexGuards : List Val -> List (Guard, Nat, String)
indexGuards (a :: _) = case a.type of
  ArrayT Rank1 _ => [(IndexIn 0, 1, outOfBounds)]
  _ => []
indexGuards [] = []

||| The guards of a partial primitive on its operands, each with the index of
||| the operand it guards and the cause its crash reports; none for a total
||| one.
guardOf : Prim -> List Val -> List (Guard, Nat, String)
guardOf (IntOp Div _) _ = [(Nonzero, 1, divisionByZero)]
guardOf (IntOp Mod _) _ = [(Nonzero, 1, divisionByZero)]
guardOf (Op BigDiv) _ = [(Nonzero, 1, divisionByZero)]
guardOf (Op BigMod) _ = [(Nonzero, 1, divisionByZero)]
guardOf (Op ToByte) _ = [(Byte, 0, "a byte outside 0 to 255")]
guardOf (Op ToInt) _ = [(Finite, 0, nonFinite)]
guardOf (Op BigFromDouble) _ = [(Finite, 0, nonFinite)]
guardOf (Op StrIndex) _ = [(IndexIn 0, 1, "string index out of range")]
guardOf (Op StrHead) _ = [(Nonempty, 0, "head of an empty string")]
guardOf (Op StrTail) _ = [(Nonempty, 0, "tail of an empty string")]
guardOf (Op ArrayGet) vs = indexGuards vs
guardOf (Op ArraySet) vs = indexGuards vs
guardOf (Op WriteBytes) _ = [(RangeIn (CountAt 3) 1, 2, outsideBuffer)]
guardOf (Op ReadBytes) _ = [(RangeIn (CountAt 3) 1, 2, outsideBuffer)]
guardOf (Op BufferGetString) _ = [(RangeIn (CountAt 2) 0, 1, outsideBuffer)]
guardOf (Op BufferLoad) _ = [(RangeIn WordSize 0, 1, outsideBuffer)]
guardOf (Op BufferStore) _ = [(RangeIn WordSize 0, 1, outsideBuffer)]
guardOf (Op BufferSetString) _ = [(RangeIn (BytesOf 2) 0, 1, outsideBuffer)]
guardOf (Op BufferCopy) _ =
  [(RangeIn (CountAt 2) 0, 1, outsideBuffer), (RangeIn (CountAt 2) 3, 4, outsideBuffer)]
guardOf _ _ = []

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

||| The guards of the primitive `p` on its operands, written here, right
||| before the primitive and at its location: the operands, each guard's
||| result in place of the operand it guards. `types` are an effect's type
||| arguments, which give a stored or loaded word its size.
guarded : Index -> Loc -> Prim -> List Ty -> List Val -> E (List Val)
guarded ix l p types vs = foldlM checkOne vs (guardOf p vs)
  where
    operandAt : List Val -> Nat -> E Val
    operandAt ws i =
      maybe (internal (show p ++ " without its operand " ++ show i)) pure (getAt i ws)

    lengthOf : Val -> E Val
    lengthOf s = case s.type of
      StrT => value ix l (IntT IdrisInt) (Idr.strLengthOp !(operand ix s))
      ArrayT _ _ => arrayLength ix l s
      t => internal ("the length of a value of type " ++ show t)

    countOf : List Val -> Count -> E Val
    countOf ws (CountAt i) = operandAt ws i
    countOf ws (BytesOf i) =
      value ix l (IntT IdrisInt) (Idr.strBytesLengthOp !(operand ix !(operandAt ws i)))
    countOf ws WordSize = case map wordSize types of
      [Just n] => value ix l (IntT IdrisInt) (Arith.constantOp (IntegerAttr n (IntegerType 64)))
      _ => internal (show p ++ " at the types " ++ show types)

    checkOne : List Val -> (Guard, Nat, String) -> E (List Val)
    checkOne ws (g, i, cause) = do
      v <- operandAt ws i
      x <- operand ix v
      build <- the (E (MlirType -> Op)) $ case g of
        Nonzero => pure (Idr.checkNonzeroOp x cause)
        Nonempty => pure (Idr.checkNonemptyOp x cause)
        Byte => pure (Idr.checkByteOp x cause)
        Finite => pure (Idr.checkFiniteOp x cause)
        IndexIn s => do
          n <- lengthOf !(operandAt ws s)
          pure (Idr.checkInBoundsOp x !(operand ix n) cause)
        RangeIn c b => do
          n <- countOf ws c
          size <- arrayLength ix l !(operandAt ws b)
          pure (Idr.checkRangeOp x !(operand ix n) !(operand ix size) cause)
      checked <- mlirValue l x.type build
      pure (setAt i (val checked.name v.type v.use) ws)

------------------------------------------------------------------------------
-- Primitives
------------------------------------------------------------------------------

||| A pure primitive of the dialect on its operands, after its guards,
||| giving a value of type `t`.
pureOp : Index -> Loc -> IdrPrim -> List Val -> Ty -> E Val
pureOp ix l p vs t = do
  args <- traverse (operand ix) !(guarded ix l (Op p) [] vs)
  value ix l t (\r => primOp p args [r])

||| What a pure primitive of the dialect gives, at Core's type: a string, an
||| Integer or a natural as itself, a character a `Char`, a length, a byte
||| offset or a handle's test an `Int`; Integer arithmetic gives what it takes,
||| Integers or naturals. A conversion whose result its types name is a
||| `Cast`, `ToStr`, `FromStr`, `ToBig` or `FromBig`, which gives that type.
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
  StrScalarEnd => pure (IntT IdrisInt)
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
||| op's), after its guards.
export
prim : Index -> Loc -> Prim -> List Val -> E Val
prim ix l (Op p) vs = pureOp ix l p vs !(resultOf p vs)
prim ix l (IntOp op t) [a, b] = do
  [x, y] <- traverse (operand ix) !(guarded ix l (IntOp op t) [] [a, b])
    | _ => internal ("the guards of " ++ show (IntOp op t) ++ " changed its operands")
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
  (SDouble, SInt t) => pureOp ix l ToInt [a] (IntT t)
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
  extend ix l !(mlirValue l bool (Idr.strCmpOp (predicate c) !(operand ix a) !(operand ix b)))
prim ix l (ToStr (SInt t)) [x] = value ix l StrT (Idr.strShowOp {isSigned = signed t} !(operand ix x))
prim ix l (ToStr SChar) [c] = pureOp ix l StrFromChar [c] StrT
prim ix l (ToStr SDouble) [x] = value ix l StrT (Idr.strShowOp !(operand ix x))
prim ix l (FromStr (SInt t)) [s] = value ix l (IntT t) (Idr.strToIntOp {isSigned = signed t} !(operand ix s))
prim ix l (FromStr SDouble) [s] = pureOp ix l StrToDouble [s] DoubleT
prim ix l (BigCompare c) [a, b] =
  extend ix l !(mlirValue l bool (Idr.bigCmpOp (predicate c) !(operand ix a) !(operand ix b)))
prim ix l (ToBig (SInt t)) [x] = value ix l BigT (Idr.bigFromIntOp {isSigned = signed t} !(operand ix x))
prim ix l (ToBig SChar) [c] = value ix l BigT (Idr.bigFromIntOp !(operand ix c))
prim ix l (ToBig SDouble) [d] = pureOp ix l BigFromDouble [d] BigT
prim ix l (FromBig (SInt t)) [b] = pureOp ix l BigToInt [b] (IntT t)
prim ix l (FromBig SDouble) [b] = pureOp ix l BigToDouble [b] DoubleT
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
  extend ix l !(mlirValue l bool (Idr.bigCmpOp (predicate c) !(operand ix a) !(operand ix b)))
prim ix l (ArrayLength _) [a] = arrayLength ix l a
prim ix l p vs = internal ("the primitive " ++ show p ++ " with " ++ show (length vs) ++ " operands")

||| A constructor application (`idr.con`); a box's allocates.
export
con : Index -> Loc -> Con -> List Val -> E Val
con ix l c vs0 = do
  vs <- traverse (\(f, v) => coerce ix l (binderUse f) v) (zip c.fields vs0)
  value ix l (DataT c.id.dataId)
        (Idr.conOp (MkSymbolRef (mangle c.id.dataId.name) [mangle c.id.name])
                   !(traverse (operand ix) vs))

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

||| An op, and the names of its results, one per result type.
resultNames : Loc -> Op -> E (List String)
resultNames l o = case o.results of
  [] => [] <$ statement l o
  [_] => do
    r <- fresh
    append (MkStatement (Just r) o (At l))
    pure [r]
  ts => do
    r <- fresh
    append (MkStatement (Just r) o (At l))
    pure (zipWith (\i, _ => r ++ "#" ++ show i) [0 .. length ts] ts)

||| An effect: the primitive `p`, which performs IO, on its operands, after
||| its guards, and the `IORes` instance `res` of its value and the next
||| world. `types` are the types its call fixes (a buffer word's). The
||| primitive takes the world as its last operand (one without operands
||| makes a world) and gives the next as its last result. A unit value
||| carries nothing, so the op gives no result for it: the unit is built
||| after it.
export
effect : Index -> Loc -> IdrPrim -> List Ty -> List Val -> DataId -> E (Maybe Val)
effect ix l p types vs res = do
  unless (primPerformsIO p) $
    internal (show (Op p) ++ ", which performs no IO, as an effect")
  mk <- only ix res
  [x, _] <- pure (map typeOf mk.fields)
    | _ => internal (show res ++ " does not hold a value and a world")
  args <- traverse (operand ix) !(guarded ix l (Op p) types vs)
  let unit = unitOf ix x
  gives <- case unit of
    Just _ => pure []
    Nothing => (\t => [t]) <$> mlirType ix x
  names <- resultNames l (primOp p args (gives ++ [!(mlirType ix WorldT)]))
  v <- case (unit, head' names) of
    (Just u, _) => con ix l u []
    (Nothing, Just n) => pure (val n x Many)
    (Nothing, Nothing) => internal (show (Op p) ++ " without its value")
  Just w <- pure (last' names)
    | Nothing => internal (show (Op p) ++ " without the next world")
  Just <$> con ix l mk [v, val w WorldT Many]
