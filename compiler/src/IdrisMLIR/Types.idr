||| Types, literals and primitives shared by both levels of Core.
|||
||| The split that matters is Kovács's value/computation split (closure-free
||| two-level type theory, ICFP 2024): `VTy` are the value types, which exist
||| at runtime and may be stored in data; `Ty` adds function types, `Lazy` and
||| static data, which exist only at compile time and must be eliminated
||| (PROF-HEAP-*). First-order Core mentions only `VTy`, so a function value
||| cannot survive into it.
module IdrisMLIR.Types

import IdrisMLIR.Ids

import Data.String

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
export Ord IntTy where compare a b = compare (rank a) (rank b)

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
-- Value types and types
------------------------------------------------------------------------------

||| Value types: what exists at runtime (Kovács's `ValTy`).
public export
data VTy = IntT IntTy | CharT | StrT | WorldT | ErasedT | DataT DataId | DoubleT

||| Types: value types, and the compile-time-only types that `Simplify`
||| eliminates (Kovács's computation types, and data holding them).
public export
data Ty = V VTy | FunT Quantity Ty Ty | LazyT Ty | StaticT DataId

vrank : VTy -> Nat
vrank (IntT _) = 0
vrank CharT = 1
vrank StrT = 2
vrank WorldT = 3
vrank ErasedT = 4
vrank (DataT _) = 5
vrank DoubleT = 6

export
Eq VTy where
  IntT a == IntT b = a == b
  DataT a == DataT b = a == b
  a == b = vrank a == vrank b

export
Ord VTy where
  compare (IntT a) (IntT b) = compare a b
  compare (DataT a) (DataT b) = compare a b
  compare a b = compare (vrank a) (vrank b)

export
Eq Ty where
  V a == V b = a == b
  FunT q a r == FunT q' a' r' = q == q' && a == a' && r == r'
  LazyT a == LazyT b = a == b
  StaticT a == StaticT b = a == b
  _ == _ = False

export
Show VTy where
  show (IntT t) = show t
  show CharT = "Char"
  show StrT = "String"
  show WorldT = "%World"
  show ErasedT = "Erased"
  show (DataT d) = show d
  show DoubleT = "Double"

export
Show Ty where
  show (V t) = show t
  show (FunT q a r) = "((" ++ show q ++ " _ : " ++ show a ++ ") -> " ++ show r ++ ")"
  show (LazyT a) = "Lazy (" ++ show a ++ ")"
  show (StaticT d) = show d

||| A type that exists at runtime.
public export
value : Ty -> Maybe VTy
value (V t) = Just t
value _ = Nothing

||| The data instance of a data type, runtime or static.
public export
dataOf : Ty -> Maybe DataId
dataOf (V (DataT d)) = Just d
dataOf (StaticT d) = Just d
dataOf _ = Nothing

||| The quantity a runtime value of this type is passed with.
export
defaultQuantity : VTy -> Quantity
defaultQuantity ErasedT = Q0
defaultQuantity WorldT = Q1
defaultQuantity _ = QW

------------------------------------------------------------------------------
-- Literals
------------------------------------------------------------------------------

public export
data Lit = LInt IntTy Integer | LChar Integer | LStr String | LDouble Double

export
Eq Lit where
  LInt s a == LInt t b = s == t && a == b
  LChar a == LChar b = a == b
  LStr a == LStr b = a == b
  LDouble a == LDouble b = a == b
  _ == _ = False

export
Show Lit where
  show (LInt t n) = show n ++ ":" ++ show t
  show (LChar c) = "chr " ++ show c
  show (LStr s) = show s
  show (LDouble d) = prim__cast_DoubleString d ++ ":Double"

public export
litTy : Lit -> VTy
litTy (LInt t _) = IntT t
litTy (LChar _) = CharT
litTy (LStr _) = StrT
litTy (LDouble _) = DoubleT

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

||| Operand types of comparisons and casts at runtime.
public export
data Scalar = SInt IntTy | SChar | SDouble

||| Primitives that run at runtime, in first-order Core.
public export
data Prim = IntOp ArithOp IntTy | FloatOp FArith | Negate | Math MathFn
          | Compare Cmp Scalar | Cast Scalar Scalar

||| String primitives: evaluated at compile time or fused into output
||| (ELIM-G-6, ELIM-G-7), never run (PROF-HEAP-3, PROF-PRIM-4).
public export
data StrOp = Append | Cons | Length | Head | Tail | Index | Reverse | Substr
           | StrCompare Cmp | ToStr Scalar | FromStr Scalar

||| The primitives of full Core.
public export
data PrimOp = Run Prim | Str StrOp

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

export
Show StrOp where
  show Append = "strAppend"
  show Cons = "strCons"
  show Length = "strLength"
  show Head = "strHead"
  show Tail = "strTail"
  show Index = "strIndex"
  show Reverse = "strReverse"
  show Substr = "strSubstr"
  show (StrCompare op) = show op ++ "_String"
  show (ToStr s) = "cast_" ++ show s ++ "String"
  show (FromStr s) = "cast_String" ++ show s

export
Show PrimOp where
  show (Run p) = show p
  show (Str s) = show s

public export
scalarTy : Scalar -> VTy
scalarTy (SInt t) = IntT t
scalarTy SChar = CharT
scalarTy SDouble = DoubleT

||| The operand types of a runtime primitive.
public export
primArgs : Prim -> List VTy
primArgs (IntOp _ t) = [IntT t, IntT t]
primArgs (FloatOp _) = [DoubleT, DoubleT]
primArgs Negate = [DoubleT]
primArgs (Math Pow) = [DoubleT, DoubleT]
primArgs (Math _) = [DoubleT]
primArgs (Compare _ s) = [scalarTy s, scalarTy s]
primArgs (Cast a _) = [scalarTy a]

public export
primResult : Prim -> VTy
primResult (IntOp _ t) = IntT t
primResult (FloatOp _) = DoubleT
primResult Negate = DoubleT
primResult (Math _) = DoubleT
primResult (Compare _ _) = IntT IdrisInt
primResult (Cast _ b) = scalarTy b

public export
strArgs : StrOp -> List VTy
strArgs Cons = [CharT, StrT]
strArgs Index = [StrT, IntT IdrisInt]
strArgs Substr = [IntT IdrisInt, IntT IdrisInt, StrT]
strArgs (ToStr s) = [scalarTy s]
strArgs Append = [StrT, StrT]
strArgs (StrCompare _) = [StrT, StrT]
strArgs _ = [StrT]

public export
strResult : StrOp -> VTy
strResult Length = IntT IdrisInt
strResult Head = CharT
strResult Index = CharT
strResult (StrCompare _) = IntT IdrisInt
strResult (FromStr s) = scalarTy s
strResult _ = StrT

public export
opArgs : PrimOp -> List VTy
opArgs (Run p) = primArgs p
opArgs (Str s) = strArgs s

------------------------------------------------------------------------------
-- IO
------------------------------------------------------------------------------

public export
data IOOp = PutStr | PutChar | GetChar | Exit | PutInt IntTy | PutDouble

export
Show IOOp where
  show PutStr = "putStr"
  show PutChar = "putChar"
  show GetChar = "getChar"
  show Exit = "exit"
  show (PutInt t) = "putInt_" ++ show t
  show PutDouble = "putDouble"

||| The runtime operands of an IO primitive before the world, and whether its
||| result value is a character (otherwise it is `()`).
public export
ioArgs : IOOp -> List VTy
ioArgs PutStr = [StrT]
ioArgs PutChar = [CharT]
ioArgs (PutInt t) = [IntT t]
ioArgs GetChar = []
ioArgs Exit = [IntT IdrisInt]
ioArgs PutDouble = [DoubleT]

public export
data EntryKind = IntEntry | IOEntry
