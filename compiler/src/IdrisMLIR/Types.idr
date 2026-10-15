-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Types, literals and primitives of Core.
|||
||| There is one type language: every type of full Core exists at runtime,
||| and MLIR removes abstraction. A data instance is declared once
||| (`Term.Data`), so `DataT` names the instance and nothing more. Types
||| Idris flags `ZERO`/`SUCC` are not data at all: they are `NatT`.
module IdrisMLIR.Types

import IdrisMLIR.Dialect.Idr
import IdrisMLIR.Ids
import IdrisMLIR.MLIR

import Data.String

%default total

------------------------------------------------------------------------------
-- Quantities and integer types
------------------------------------------------------------------------------

||| A quantity as the Core dump writes it: `1` for a value used exactly
||| once, `w` for one used any number of times. A binder Idris erased binds
||| no runtime value, so it is not represented.
export
quantityText : Quantity -> String
quantityText One = "1"
quantityText Many = "w"

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
  ||| force; `DataT` is a data instance, whatever it holds: how its values
  ||| are laid out, boxed or not, is the dialect's to decide. `TensorT` is a
  ||| value of the array language (`Array s a`, `LArray s a`): a ranked
  ||| tensor of its element, one dimension per axis of the form of `s`,
  ||| outermost first, static where the shape's normal form at the instance
  ||| is a literal; an array of arrays is one tensor, the element's
  ||| dimensions after the shape's, so its element is never a tensor or a
  ||| memref. An array of records is a tensor of the record's data
  ||| instance, which the dialect splits into one tensor per field.
  ||| `MemRefT` is an array a world orders, read and written through the
  ||| world: base's `ArrayData` and `Buffer`, of one dynamic dimension, and
  ||| the one cell of an IORef, of none; its element is never a tensor.
  public export
  data Ty = IntT IntTy | CharT | DoubleT | StrT | BigT | NatT | WorldT
          | DataT DataId
          | FunT Binder Ty
          | LazyT Ty
          | TensorT (List Dim) Ty
          | MemRefT (List Dim) Ty

  ||| What a parameter, a lambda, an arrow or a constructor field binds: a
  ||| value of a type, used as Idris proved. A binder of quantity zero binds
  ||| no runtime value, so it is not a binder: the position is absent.
  public export
  record Binder where
    constructor MkBinder
    quantity : Quantity
    type : Ty

||| The type of what a binder binds.
public export
typeOf : Binder -> Ty
typeOf = (.type)

mutual
  sameTy : Ty -> Ty -> Bool
  sameTy (IntT a) (IntT b) = a == b
  sameTy CharT CharT = True
  sameTy DoubleT DoubleT = True
  sameTy StrT StrT = True
  sameTy BigT BigT = True
  sameTy NatT NatT = True
  sameTy WorldT WorldT = True
  sameTy (DataT a) (DataT b) = a == b
  sameTy (FunT a r) (FunT a' r') = sameBinder a a' && sameTy r r'
  sameTy (LazyT a) (LazyT b) = sameTy a b
  sameTy (TensorT ds a) (TensorT es b) = ds == es && sameTy a b
  sameTy (MemRefT ds a) (MemRefT es b) = ds == es && sameTy a b
  sameTy _ _ = False

  sameBinder : Binder -> Binder -> Bool
  sameBinder (MkBinder q t) (MkBinder q' t') = q == q' && sameTy t t'

export
Eq Ty where
  (==) = sameTy

export
Eq Binder where
  (==) = sameBinder

mutual
  ||| A type as the Core dump writes it, each data instance named by `name`:
  ||| the one type printer, so that the dump can name an instance by its
  ||| key, as the module does.
  export
  tyText : (name : DataId -> String) -> Ty -> String
  tyText name (IntT t) = show t
  tyText name CharT = "Char"
  tyText name DoubleT = "Double"
  tyText name StrT = "String"
  tyText name BigT = "Integer"
  tyText name NatT = "Nat"
  tyText name WorldT = "%World"
  tyText name (DataT d) = name d
  tyText name (FunT a r) = "((" ++ binderText name a ++ ") -> " ++ tyText name r ++ ")"
  tyText name (LazyT a) = "Lazy (" ++ tyText name a ++ ")"
  tyText name (TensorT ds a) = "Tensor [<" ++ joinBy ", " (map dimText ds) ++ "] (" ++ tyText name a ++ ")"
    where
      dimText : Dim -> String
      dimText (Static n) = show n
      dimText Dynamic = "?"
  tyText name (MemRefT [] a) = "Mut (" ++ tyText name a ++ ")"
  tyText name (MemRefT _ a) = "Array (" ++ tyText name a ++ ")"

  ||| `1 T` or `w T`, as the Core dump writes a binder.
  export
  binderText : (name : DataId -> String) -> Binder -> String
  binderText name (MkBinder q t) = quantityText q ++ " " ++ tyText name t

export
Show Ty where
  show = tyText show

export
Show Binder where
  show = binderText show

||| The dimensions a type contributes to a tensor that holds it: a tensor's
||| own, none for anything else.
public export
tensorDims : Ty -> List Dim
tensorDims (TensorT ds _) = ds
tensorDims _ = []

||| A type as a closure's binder or result, or a suspension's value, holds
||| it: every tensor dimension in it dynamic, so that one closure type
||| serves every extent its values are made at.
export
dynamicDims : Ty -> Ty
dynamicDims (TensorT ds e) = TensorT (map (const Dynamic) ds) e
dynamicDims (FunT (MkBinder q a) r) = FunT (MkBinder q (dynamicDims a)) (dynamicDims r)
dynamicDims (LazyT a) = LazyT (dynamicDims a)
dynamicDims t = t

------------------------------------------------------------------------------
-- The array language
------------------------------------------------------------------------------

||| An operation of the array language on tensors (`Term.Tensor`). An axis
||| is counted from 0, outermost first; the axis of `Take`, `Drop`, `Concat`
||| and `Pad` is the shape's last, before the cell's, and `Transpose`'s the
||| shape's last but one.
public export
data TensorOp
  = ||| [x]: the extent of axis k of x, a natural.
    Extent Nat
  | ||| (x :: coords): the element of x at the coordinates (naturals, one
    ||| per leading axis), or the cell there when the result is a tensor.
    Extract
  | ||| (x :: v :: coords): x with v, an element or a cell, at the
    ||| coordinates.
    Insert
  | ||| [k, x]: the first k along the axis.
    Take Nat
  | ||| [k, x]: all but the first k along the axis.
    Drop Nat
  | ||| [x, y]: x then y along the axis.
    Concat Nat
  | ||| [x]: x with the axis and the one after it swapped.
    Transpose Nat
  | ||| (x :: extents): x's elements in row-major order at the result's
    ||| shape, its extents given outermost first; the result's dimensions
    ||| after them are the cell's.
    Reshape
  | ||| [lo, hi, v, x]: x along the axis with lo copies of the cell v before
    ||| and hi after.
    Pad Nat

export
Eq TensorOp where
  Extent a == Extent b = a == b
  Extract == Extract = True
  Insert == Insert = True
  Take a == Take b = a == b
  Drop a == Drop b = a == b
  Concat a == Concat b = a == b
  Transpose a == Transpose b = a == b
  Reshape == Reshape = True
  Pad a == Pad b = a == b
  _ == _ = False

export
Show TensorOp where
  show (Extent k) = "extent" ++ show k
  show Extract = "extract"
  show Insert = "insert"
  show (Take a) = "take" ++ show a
  show (Drop a) = "drop" ++ show a
  show (Concat a) = "concat" ++ show a
  show (Transpose a) = "transpose" ++ show a
  show Reshape = "reshape"
  show (Pad a) = "pad" ++ show a

||| How a reduction along an axis keeps its accumulators (`Term.Reduce`):
||| the last ones, or every one along the axis.
public export
data Reduction = FoldLast | ScanLast

export
Eq Reduction where
  FoldLast == FoldLast = True
  ScanLast == ScanLast = True
  _ == _ = False

export
Show Reduction where
  show FoldLast = "fold_last"
  show ScanLast = "scan_last"

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
||| with an attribute; a comparison, by its predicate; or the length of an
||| array a world orders.
public export
data Prim
  = IntOp ArithOp IntTy | IntShift Shift IntTy | FloatOp FArith | Negate | Math MathFn
  | Compare CmpPredicate Scalar | Cast Scalar Scalar
  | StrCompare CmpPredicate
  | ||| A scalar shown as a string.
    ToStr Scalar
  | ||| A string read as a number.
    FromStr Scalar
  | BigCompare CmpPredicate
  | ToBig Scalar | FromBig Scalar
  | NatCompare CmpPredicate
  | ||| The number of elements of an array a world orders, of this element
    ||| type: the dimension of its memref.
    ArrayLength Ty
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
primArgs (ArrayLength e) = [MemRefT [Dynamic] e]
primArgs (Op _) = []
