||| Types, literals and primitives of Core (docs/architecture/05-middle-ir.md).
|||
||| There is one type language: every type of full Core exists at runtime,
||| and MLIR removes abstraction (docs/architecture/09-optimization.md). A data
||| instance records its representation where it is declared (`Term.Data`),
||| so `DataT` names the instance and nothing more. Types Idris flags
||| `ZERO`/`SUCC` are not data at all: they are `BigT`.
module IdrisMLIR.Types

import IdrisMLIR.Ids

%default total

------------------------------------------------------------------------------
-- Quantities and integer types
------------------------------------------------------------------------------

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

||| The types of Core. `BigT` is `Integer` and every `Nat`-like type;
||| `FunT` and `LazyT` are closures; `DataT` is a data instance, whose
||| declaration says whether it is an unboxed sum or a box.
public export
data Ty = IntT IntTy | CharT | DoubleT | StrT | BigT | WorldT | ErasedT
        | DataT DataId
        | FunT Quantity Ty Ty
        | LazyT Ty

export
Eq Ty where
  IntT a == IntT b = a == b
  CharT == CharT = True
  DoubleT == DoubleT = True
  StrT == StrT = True
  BigT == BigT = True
  WorldT == WorldT = True
  ErasedT == ErasedT = True
  DataT a == DataT b = a == b
  FunT q a r == FunT q' a' r' = q == q' && a == a' && r == r'
  LazyT a == LazyT b = a == b
  _ == _ = False

export
Show Ty where
  show (IntT t) = show t
  show CharT = "Char"
  show DoubleT = "Double"
  show StrT = "String"
  show BigT = "Integer"
  show WorldT = "%World"
  show ErasedT = "Erased"
  show (DataT d) = show d
  show (FunT q a r) = "((" ++ show q ++ " _ : " ++ show a ++ ") -> " ++ show r ++ ")"
  show (LazyT a) = "Lazy (" ++ show a ++ ")"

------------------------------------------------------------------------------
-- Literals
------------------------------------------------------------------------------

public export
data Lit = LInt IntTy Integer | LChar Integer | LStr String | LDouble Double | LBig Integer

export
Eq Lit where
  LInt s a == LInt t b = s == t && a == b
  LChar a == LChar b = a == b
  LStr a == LStr b = a == b
  LDouble a == LDouble b = a == b
  LBig a == LBig b = a == b
  _ == _ = False

export
Show Lit where
  show (LInt t n) = show n ++ ":" ++ show t
  show (LChar c) = "chr " ++ show c
  show (LStr s) = show s
  show (LDouble d) = prim__cast_DoubleString d ++ ":Double"
  show (LBig n) = show n ++ ":Integer"

------------------------------------------------------------------------------
-- Primitives
------------------------------------------------------------------------------

public export
data ArithOp = Add | Sub | Mul | Div | Mod | And | Or | Xor

public export
data Cmp = CLt | CLte | CEq | CGte | CGt

||| Double arithmetic (SEM-DBL-2).
public export
data FArith = FAdd | FSub | FMul | FDiv

||| The C library's functions on doubles, and the exact ones (SEM-DBL-3).
public export
data MathFn = Exp | Log | Pow | Sin | Cos | Tan | ASin | ACos | ATan | Sqrt | Floor | Ceiling

||| The fixed-width operand types of comparisons and casts.
public export
data Scalar = SInt IntTy | SChar | SDouble

||| Idris's primitives as Core has them (IDR-IN-3): on fixed-width
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

------------------------------------------------------------------------------
-- IO
------------------------------------------------------------------------------

||| The IO primitives the registry lists (`IOCall`, PROF-IO-4).
public export
data IOOp = PutStr | PutChar
          | GetByte   -- one byte of input (SEM-IO-7)

export
Show IOOp where
  show PutStr = "putStr"
  show PutChar = "putChar"
  show GetByte = "getByte"

||| The operand types of an IO primitive, before the world.
public export
ioArgs : IOOp -> List Ty
ioArgs PutStr = [StrT]
ioArgs PutChar = [CharT]
ioArgs GetByte = []
