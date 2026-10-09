||| Types, literals and primitives of Core.
|||
||| There is one type language: every type of full Core exists at runtime,
||| and MLIR removes abstraction. A data
||| instance records its representation where it is declared (`Term.Data`),
||| so `DataT` names the instance and nothing more. Types Idris flags
||| `ZERO`/`SUCC` are not data at all: they are `NatT`.
module IdrisMLIR.Types

import IdrisMLIR.Dialect.Idr
import IdrisMLIR.Ids
import IdrisMLIR.MLIR

%default total

------------------------------------------------------------------------------
-- Uses and integer types
------------------------------------------------------------------------------

||| Idris's multiplicities as a type writes them, which the registry's
||| shapes of library types compare.
public export
data Quantity = Q0 | Q1 | QW

export
Eq Quantity where
  Q0 == Q0 = True
  Q1 == Q1 = True
  QW == QW = True
  _ == _ = False

export
Show Quantity where
  show Q0 = "0"
  show Q1 = "1"
  show QW = "w"

||| How often a runtime value is used, as Idris proved: exactly once
||| (multiplicity 1) or any number of times (ω). Multiplicity 0 binds no
||| runtime value at all (`Binder`'s `Gone`).
public export
data Use = Once | Many

export
Eq Use where
  Once == Once = True
  Many == Many = True
  _ == _ = False

export
Show Use where
  show Once = "1"
  show Many = "w"

public export
data IntTy = IdrisInt | SInt8 | SInt16 | SInt32 | SInt64 | UInt8 | UInt16 | UInt32 | UInt64

rank : IntTy -> Nat
rank IdrisInt = 0
rank SInt8 = 1
rank SInt16 = 2
rank SInt32 = 3
rank SInt64 = 4
rank UInt8 = 5
rank UInt16 = 6
rank UInt32 = 7
rank UInt64 = 8

export Eq IntTy where a == b = rank a == rank b

export
Show IntTy where
  show IdrisInt = "Int"
  show SInt8 = "Int8"
  show SInt16 = "Int16"
  show SInt32 = "Int32"
  show SInt64 = "Int64"
  show UInt8 = "Bits8"
  show UInt16 = "Bits16"
  show UInt32 = "Bits32"
  show UInt64 = "Bits64"

export
width : IntTy -> Nat
width SInt8 = 8
width UInt8 = 8
width SInt16 = 16
width UInt16 = 16
width SInt32 = 32
width UInt32 = 32
width _ = 64

export
signed : IntTy -> Bool
signed UInt8 = False
signed UInt16 = False
signed UInt32 = False
signed UInt64 = False
signed _ = True

------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------

mutual
  ||| The types of Core. `BigT` is `Integer`; `NatT` is `Nat` and every
  ||| `Nat`-like type, an integer that is never negative, the same
  ||| big at runtime; `FunT` is a closure, binding its argument as a lambda
  ||| does; `LazyT` is a suspension, one cell whose value is shared by every
  ||| force; `DataT` is a data instance, whose declaration says
  ||| whether it is an unboxed sum or a box; `ArrayT` is a mutable array of
  ||| its element type, `Data.IOArray.Prims.ArrayData`, read and written
  ||| through the world.
  public export
  data Ty = IntT IntTy | CharT | DoubleT | StrT | BigT | NatT | WorldT | ErasedT
          | DataT DataId
          | FunT Binder Ty
          | LazyT Ty
          | ArrayT Ty

  ||| What a parameter, a lambda, an arrow or a constructor field binds:
  ||| nothing at runtime (multiplicity 0), or a value of a type, used as
  ||| Idris proved.
  public export
  data Binder = Gone | Held Use Ty

||| The type of what a binder binds: an erased value when it binds nothing.
public export
typeOf : Binder -> Ty
typeOf Gone = ErasedT
typeOf (Held _ t) = t

mutual
  sameTy : Ty -> Ty -> Bool
  sameTy (IntT a) (IntT b) = a == b
  sameTy CharT CharT = True
  sameTy DoubleT DoubleT = True
  sameTy StrT StrT = True
  sameTy BigT BigT = True
  sameTy NatT NatT = True
  sameTy WorldT WorldT = True
  sameTy ErasedT ErasedT = True
  sameTy (DataT a) (DataT b) = a == b
  sameTy (FunT a r) (FunT a' r') = sameBinder a a' && sameTy r r'
  sameTy (LazyT a) (LazyT b) = sameTy a b
  sameTy (ArrayT a) (ArrayT b) = sameTy a b
  sameTy _ _ = False

  sameBinder : Binder -> Binder -> Bool
  sameBinder Gone Gone = True
  sameBinder (Held u t) (Held u' t') = u == u' && sameTy t t'
  sameBinder _ _ = False

export
Eq Ty where
  (==) = sameTy

export
Eq Binder where
  (==) = sameBinder

mutual
  showTy : Ty -> String
  showTy (IntT t) = show t
  showTy CharT = "Char"
  showTy DoubleT = "Double"
  showTy StrT = "String"
  showTy BigT = "Integer"
  showTy NatT = "Nat"
  showTy WorldT = "%World"
  showTy ErasedT = "Erased"
  showTy (DataT d) = show d
  showTy (FunT a r) = "((" ++ showBinder a ++ ") -> " ++ showTy r ++ ")"
  showTy (LazyT a) = "Lazy (" ++ showTy a ++ ")"
  showTy (ArrayT a) = "Array (" ++ showTy a ++ ")"

  ||| `0 Erased`, `1 T` or `w T`, as the Core dump writes a binder.
  showBinder : Binder -> String
  showBinder Gone = "0 Erased"
  showBinder (Held u t) = show u ++ " " ++ showTy t

export
Show Ty where
  show = showTy

export
Show Binder where
  show = showBinder

------------------------------------------------------------------------------
-- Literals
------------------------------------------------------------------------------

||| `LNat` is a natural, never negative: a `Nat`-like value.
public export
data Lit = LInt IntTy Integer | LChar Integer | LStr String | LDouble Double | LBig Integer
         | LNat Nat

export
Eq Lit where
  LInt s a == LInt t b = s == t && a == b
  LChar a == LChar b = a == b
  LStr a == LStr b = a == b
  LDouble a == LDouble b = a == b
  LBig a == LBig b = a == b
  LNat a == LNat b = a == b
  _ == _ = False

export
Show Lit where
  show (LInt t n) = show n ++ ":" ++ show t
  show (LChar c) = "chr " ++ show c
  show (LStr s) = show s
  show (LDouble d) = prim__cast_DoubleString d ++ ":Double"
  show (LBig n) = show n ++ ":Integer"
  show (LNat n) = show n ++ ":Nat"

------------------------------------------------------------------------------
-- Primitives
------------------------------------------------------------------------------

public export
data ArithOp = Add | Sub | Mul | Div | Mod | And | Or | Xor

||| The direction of a shift of a fixed-width integer (idr.shl, idr.shr).
public export
data Shift = ShiftLeft | ShiftRight

public export
data Cmp = CLt | CLte | CEq | CGte | CGt

||| Double arithmetic.
public export
data FArith = FAdd | FSub | FMul | FDiv

||| The C library's functions on doubles, and the exact ones.
public export
data MathFn = Exp | Log | Pow | Sin | Cos | Tan | ASin | ACos | ATan | Sqrt | Floor | Ceiling

||| The fixed-width operand types of comparisons and casts.
public export
data Scalar = SInt IntTy | SChar | SDouble

||| Idris's primitives as Core has them: an op of the dialect that Idris
||| names as a primitive (`Op`), which has no attribute; an operation its
||| types choose, by the signedness and width of fixed-width integers,
||| characters and doubles, among `arith`'s, `math`'s and the dialect's ops
||| with an attribute; a comparison, by its predicate; or an array's length,
||| or an index checked against a bound.
public export
data Prim
  = IntOp ArithOp IntTy | IntShift Shift IntTy | FloatOp FArith | Negate | Math MathFn
  | Compare Cmp Scalar | Cast Scalar Scalar
  | StrCompare Cmp
  | ||| A scalar shown as a string.
    ToStr Scalar
  | ||| A string read as a number.
    FromStr Scalar
  | BigCompare Cmp
  | ToBig Scalar | FromBig Scalar
  | NatCompare Cmp
  | ||| The number of elements of an array of this element type: the
    ||| dimension of its memref.
    ArrayLength Ty
  | ||| An index, once it is at least 0 and below the bound: the guard of an
    ||| index against an integer (`idr.check.in_bounds`), which crashes as
    ||| an access outside an array does. The bound is a size, never negative
    ||| (the one caller, Linear.Array, keeps it so), since the guard checks
    ||| it as it checks a length.
    IndexBelow
  | ||| The op of a primitive of the dialect, on its operands in the op's
    ||| order, each at its own type.
    Op IdrPrim

export
Show ArithOp where
  show Add = "add"
  show Sub = "sub"
  show Mul = "mul"
  show Div = "div"
  show Mod = "mod"
  show And = "and"
  show Or = "or"
  show Xor = "xor"

export
Show Cmp where
  show CLt = "lt"
  show CLte = "lte"
  show CEq = "eq"
  show CGte = "gte"
  show CGt = "gt"

export
Show Scalar where
  show (SInt t) = show t
  show SChar = "Char"
  show SDouble = "Double"

export
Show FArith where
  show FAdd = "add"
  show FSub = "sub"
  show FMul = "mul"
  show FDiv = "div"

export
Show MathFn where
  show Exp = "exp"
  show Log = "log"
  show Pow = "pow"
  show Sin = "sin"
  show Cos = "cos"
  show Tan = "tan"
  show ASin = "asin"
  show ACos = "acos"
  show ATan = "atan"
  show Sqrt = "sqrt"
  show Floor = "floor"
  show Ceiling = "ceiling"

export
Show Shift where
  show ShiftLeft = "shl"
  show ShiftRight = "shr"

export
Show Prim where
  show (IntOp op t) = show op ++ "_" ++ show t
  show (IntShift s t) = show s ++ "_" ++ show t
  show (FloatOp op) = show op ++ "_Double"
  show Negate = "neg_Double"
  show (Math f) = show f ++ "_Double"
  show (Compare op s) = show op ++ "_" ++ show s
  show (Cast a b) = "cast_" ++ show a ++ show b
  show (StrCompare op) = show op ++ "_String"
  show (ToStr s) = "cast_" ++ show s ++ "String"
  show (FromStr s) = "cast_String" ++ show s
  show (BigCompare op) = show op ++ "_Integer"
  show (ToBig s) = "cast_" ++ show s ++ "Integer"
  show (FromBig s) = "cast_Integer" ++ show s
  show (NatCompare op) = show op ++ "_Nat"
  show (ArrayLength e) = "arraySize<" ++ show e ++ ">"
  show IndexBelow = "indexBelow"
  show (Op p) = (primOp p [] []).name

public export
scalarTy : Scalar -> Ty
scalarTy (SInt t) = IntT t
scalarTy SChar = CharT
scalarTy SDouble = DoubleT

||| The operand types of a primitive chosen by its types, in Idris's
||| argument order. The op of the dialect takes its operands at their own
||| types, so it lists none.
public export
primArgs : Prim -> List Ty
primArgs (IntOp _ t) = [IntT t, IntT t]
primArgs (IntShift _ t) = [IntT t, IntT t]
primArgs (FloatOp _) = [DoubleT, DoubleT]
primArgs Negate = [DoubleT]
primArgs (Math Pow) = [DoubleT, DoubleT]
primArgs (Math _) = [DoubleT]
primArgs (Compare _ s) = [scalarTy s, scalarTy s]
primArgs (Cast a _) = [scalarTy a]
primArgs (StrCompare _) = [StrT, StrT]
primArgs (ToStr s) = [scalarTy s]
primArgs (FromStr _) = [StrT]
primArgs (BigCompare _) = [BigT, BigT]
primArgs (ToBig s) = [scalarTy s]
primArgs (FromBig _) = [BigT]
primArgs (NatCompare _) = [NatT, NatT]
primArgs (ArrayLength e) = [ArrayT e]
primArgs IndexBelow = [IntT IdrisInt, IntT IdrisInt]
primArgs (Op _) = []
