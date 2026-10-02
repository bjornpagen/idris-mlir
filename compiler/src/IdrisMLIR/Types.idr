||| Types, literals and primitives of Core.
|||
||| There is one type language: every type of full Core exists at runtime,
||| and MLIR removes abstraction. A data
||| instance records its representation where it is declared (`Term.Data`),
||| so `DataT` names the instance and nothing more. Types Idris flags
||| `ZERO`/`SUCC` are not data at all: they are `NatT`.
module IdrisMLIR.Types

import IdrisMLIR.Ids

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
  ||| big at runtime; `FunT` and `LazyT` are closures, `FunT` binding its argument as a
  ||| lambda does; `DataT` is a data instance, whose declaration says
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

||| Idris's primitives as Core has them: on fixed-width
||| integers, characters and doubles; on strings; on `Integer`.
public export
data Prim
  = IntOp ArithOp IntTy | FloatOp FArith | Negate | Math MathFn
  | Compare Cmp Scalar | Cast Scalar Scalar
  | StrAppend | StrCons | StrLength | StrHead | StrTail | StrIndex | StrReverse | StrSubstr
  | StrCompare Cmp
  | ||| A scalar shown as a string.
    ToStr Scalar
  | ||| A string read as a number.
    FromStr Scalar
  | BigArith ArithOp | BigNegate | BigCompare Cmp
  | ToBig Scalar | FromBig Scalar | BigShow | BigRead
  | ||| The arithmetic of naturals that stays natural: the sum and the
    ||| product.
    NatAdd | NatMul
  | NatCompare Cmp
  | ||| A natural as the Integer it is.
    NatToBig
  | ||| An Integer as a natural, 0 if it is negative.
    NatFromBig
  | ||| The number of elements of an array of this element type: the
    ||| dimension of its memref.
    ArrayLength Ty

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
Show Prim where
  show (IntOp op t) = show op ++ "_" ++ show t
  show (FloatOp op) = show op ++ "_Double"
  show Negate = "neg_Double"
  show (Math f) = show f ++ "_Double"
  show (Compare op s) = show op ++ "_" ++ show s
  show (Cast a b) = "cast_" ++ show a ++ show b
  show StrAppend = "strAppend"
  show StrCons = "strCons"
  show StrLength = "strLength"
  show StrHead = "strHead"
  show StrTail = "strTail"
  show StrIndex = "strIndex"
  show StrReverse = "strReverse"
  show StrSubstr = "strSubstr"
  show (StrCompare op) = show op ++ "_String"
  show (ToStr s) = "cast_" ++ show s ++ "String"
  show (FromStr s) = "cast_String" ++ show s
  show (BigArith op) = show op ++ "_Integer"
  show BigNegate = "negate_Integer"
  show (BigCompare op) = show op ++ "_Integer"
  show (ToBig s) = "cast_" ++ show s ++ "Integer"
  show (FromBig s) = "cast_Integer" ++ show s
  show BigShow = "cast_IntegerString"
  show BigRead = "cast_StringInteger"
  show NatAdd = "add_Nat"
  show NatMul = "mul_Nat"
  show (NatCompare op) = show op ++ "_Nat"
  show NatToBig = "cast_NatInteger"
  show NatFromBig = "cast_IntegerNat"
  show (ArrayLength e) = "arraySize<" ++ show e ++ ">"

public export
scalarTy : Scalar -> Ty
scalarTy (SInt t) = IntT t
scalarTy SChar = CharT
scalarTy SDouble = DoubleT

||| The operand types of a primitive, in Idris's argument order.
public export
primArgs : Prim -> List Ty
primArgs (IntOp _ t) = [IntT t, IntT t]
primArgs (FloatOp _) = [DoubleT, DoubleT]
primArgs Negate = [DoubleT]
primArgs (Math Pow) = [DoubleT, DoubleT]
primArgs (Math _) = [DoubleT]
primArgs (Compare _ s) = [scalarTy s, scalarTy s]
primArgs (Cast a _) = [scalarTy a]
primArgs StrAppend = [StrT, StrT]
primArgs StrCons = [CharT, StrT]
primArgs StrIndex = [StrT, IntT IdrisInt]
primArgs StrSubstr = [IntT IdrisInt, IntT IdrisInt, StrT]
primArgs (StrCompare _) = [StrT, StrT]
primArgs (ToStr s) = [scalarTy s]
primArgs StrLength = [StrT]
primArgs StrHead = [StrT]
primArgs StrTail = [StrT]
primArgs StrReverse = [StrT]
primArgs (FromStr _) = [StrT]
primArgs (BigArith _) = [BigT, BigT]
primArgs BigNegate = [BigT]
primArgs (BigCompare _) = [BigT, BigT]
primArgs (ToBig s) = [scalarTy s]
primArgs (FromBig _) = [BigT]
primArgs BigShow = [BigT]
primArgs BigRead = [StrT]
primArgs NatAdd = [NatT, NatT]
primArgs NatMul = [NatT, NatT]
primArgs (NatCompare _) = [NatT, NatT]
primArgs NatToBig = [NatT]
primArgs NatFromBig = [BigT]
primArgs (ArrayLength e) = [ArrayT e]

------------------------------------------------------------------------------
-- IO
------------------------------------------------------------------------------

||| The operations on a mutable array (`Data.IOArray.Prims`): a new array
||| of a size and a fill, the element at an index, an element written at an
||| index. An index out of bounds crashes, where Idris's primitives leave
||| the behaviour undefined.
public export
data ArrayOp = NewArray | GetArray | SetArray

export
Show ArrayOp where
  show NewArray = "newArray"
  show GetArray = "arrayGet"
  show SetArray = "arraySet"

||| The IO primitives the registry lists (`IOCall`, `ArrayCall`); an array
||| operation carries its element type, which its call fixes.
public export
data IOOp = PutStr | PutChar
          | GetByte   -- one byte of input
          | GetLine   -- a line of input, without its end
          | Array ArrayOp Ty
          | BufferNew -- a buffer of zero bytes
          | BufferGet -- a byte of a buffer, as an Int
          | BufferSet -- an Int written as a byte, which it must be

export
Show IOOp where
  show PutStr = "putStr"
  show PutChar = "putChar"
  show GetByte = "getByte"
  show GetLine = "getLine"
  show (Array op e) = show op ++ "<" ++ show e ++ ">"
  show BufferNew = "bufferNew"
  show BufferGet = "bufferGet"
  show BufferSet = "bufferSet"

||| The operand types of an IO primitive, before the world.
public export
ioArgs : IOOp -> List Ty
ioArgs PutStr = [StrT]
ioArgs PutChar = [CharT]
ioArgs GetByte = []
ioArgs GetLine = []
ioArgs (Array NewArray e) = [IntT IdrisInt, e]
ioArgs (Array GetArray e) = [ArrayT e, IntT IdrisInt]
ioArgs (Array SetArray e) = [ArrayT e, IntT IdrisInt, e]
ioArgs BufferNew = [IntT IdrisInt]
ioArgs BufferGet = [ArrayT (IntT UInt8), IntT IdrisInt]
ioArgs BufferSet = [ArrayT (IntT UInt8), IntT IdrisInt, IntT IdrisInt]
