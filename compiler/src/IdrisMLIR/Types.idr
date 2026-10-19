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
import Data.Vect

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

||| What an array a world orders holds: the one cell of an IORef, or a run
||| of elements of one dynamic dimension (base's `ArrayData` and `Buffer`).
public export
data Ordered = Cell | Elements

export
Eq Ordered where
  Cell == Cell = True
  Elements == Elements = True
  _ == _ = False

||| The dimensions of the memref an array a world orders is.
export
orderedDims : Ordered -> List Dim
orderedDims Cell = []
orderedDims Elements = [Dynamic]

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
  ||| world (`Ordered`); its element is never a tensor.
  public export
  data Ty = IntT IntTy | CharT | DoubleT | StrT | BigT | NatT | WorldT
          | DataT DataId
          | FunT Binder Ty
          | LazyT Ty
          | TensorT (List Dim) Ty
          | MemRefT Ordered Ty

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
  sameTy (MemRefT o a) (MemRefT p b) = o == p && sameTy a b
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
  tyText name (MemRefT Cell a) = "Mut (" ++ tyText name a ++ ")"
  tyText name (MemRefT Elements a) = "Array (" ++ tyText name a ++ ")"

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

||| An operation of the array language on tensors (`Term.Tensor`), holding
||| its operands `t`, in the order the dump writes them. An axis is counted
||| from 0, outermost first; the axis of `Take`, `Drop`, `Concat` and `Pad`
||| is the shape's last, before the cell's, and `Transpose`'s the shape's
||| last but one.
public export
data TensorOp t
  = ||| The extent of axis k of the array, a natural.
    Extent Nat t
  | ||| The element of the array at the coordinates (naturals, one per
    ||| leading axis), or the cell there when the result is a tensor.
    Extract t (List t)
  | ||| The array with the element or cell at the coordinates.
    Insert t t (List t)
  | ||| The first k along the axis of the array.
    Take Nat t t
  | ||| All but the first k along the axis of the array.
    Drop Nat t t
  | ||| One array then the other along the axis.
    Concat Nat t t
  | ||| The array with the axis and the one after it swapped.
    Transpose Nat t
  | ||| The array's elements in row-major order at the result's shape, its
    ||| extents given outermost first; the result's dimensions after them are
    ||| the cell's.
    Reshape t (List t)

export
Functor TensorOp where
  map f (Extent k x) = Extent k (f x)
  map f (Extract x cs) = Extract (f x) (map f cs)
  map f (Insert x v cs) = Insert (f x) (f v) (map f cs)
  map f (Take a k x) = Take a (f k) (f x)
  map f (Drop a k x) = Drop a (f k) (f x)
  map f (Concat a x y) = Concat a (f x) (f y)
  map f (Transpose a x) = Transpose a (f x)
  map f (Reshape x es) = Reshape (f x) (map f es)

export
Foldable TensorOp where
  foldr f z (Extent _ x) = f x z
  foldr f z (Extract x cs) = f x (foldr f z cs)
  foldr f z (Insert x v cs) = f x (f v (foldr f z cs))
  foldr f z (Take _ k x) = f k (f x z)
  foldr f z (Drop _ k x) = f k (f x z)
  foldr f z (Concat _ x y) = f x (f y z)
  foldr f z (Transpose _ x) = f x z
  foldr f z (Reshape x es) = f x (foldr f z es)

export
Traversable TensorOp where
  traverse f (Extent k x) = Extent k <$> f x
  traverse f (Extract x cs) = Extract <$> f x <*> traverse f cs
  traverse f (Insert x v cs) = Insert <$> f x <*> f v <*> traverse f cs
  traverse f (Take a k x) = Take a <$> f k <*> f x
  traverse f (Drop a k x) = Drop a <$> f k <*> f x
  traverse f (Concat a x y) = Concat a <$> f x <*> f y
  traverse f (Transpose a x) = Transpose a <$> f x
  traverse f (Reshape x es) = Reshape <$> f x <*> traverse f es

||| An operation's name, as the dump writes it.
export
tensorOpName : TensorOp t -> String
tensorOpName (Extent k _) = "extent" ++ show k
tensorOpName (Extract _ _) = "extract"
tensorOpName (Insert _ _ _) = "insert"
tensorOpName (Take a _ _) = "take" ++ show a
tensorOpName (Drop a _ _) = "drop" ++ show a
tensorOpName (Concat a _ _) = "concat" ++ show a
tensorOpName (Transpose a _) = "transpose" ++ show a
tensorOpName (Reshape _ _) = "reshape"

||| What a tie states of an axis of an array: the extent of another
||| array's axis, exact, or any natural, converted as an extent.
public export
data Stated t = SameAs t | Natural t

export
Functor Stated where
  map f (SameAs x) = SameAs (f x)
  map f (Natural x) = Natural (f x)

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

||| The C library's functions of one double, and the exact ones.
public export
data UnaryMath = Exp | Log | Sin | Cos | Tan | ASin | ACos | ATan | Sqrt | Floor | Ceiling

||| A fixed-width integer or a `Char`, which compares and converts as an
||| unsigned integer of 32 bits.
public export
data IntLike = SInt IntTy | SChar

||| The width of a fixed-width integer or a `Char`.
export
likeWidth : IntLike -> Nat
likeWidth (SInt t) = width t
likeWidth SChar = 32

||| The signedness of a fixed-width integer or a `Char`.
export
likeSigned : IntLike -> Bool
likeSigned (SInt t) = signed t
likeSigned SChar = False

||| The operand types of comparisons and conversions: an integral one, or a
||| double.
public export
data Scalar = SIntegral IntLike | SDouble

||| The conversions between scalars that exist: between integral types,
||| and between a fixed-width integer and a double.
public export
data Conversion = IntToInt IntLike IntLike | IntToDouble IntTy | DoubleToInt IntTy

||| What a string is read as: a fixed-width integer or a double. Idris
||| reads no `Char` from a string.
public export
data Numeric = NInt IntTy | NDouble

||| Idris's primitives as Core has them, indexed by their arity: an op of
||| the dialect that Idris names as a primitive (`Op`), with the Core type
||| of its value, from the primitive's signature; an operation its types
||| choose, by the signedness and width of fixed-width integers,
||| characters and doubles, among `arith`'s, `math`'s and the dialect's ops;
||| a comparison, by its predicate; or the length of an array a world
||| orders.
public export
data Prim : Nat -> Type where
  IntOp : ArithOp -> IntTy -> Prim 2
  IntShift : Shift -> IntTy -> Prim 2
  FloatOp : FArith -> Prim 2
  ||| The negation of a double; a fixed-width integer's is a subtraction.
  Negate : Prim 1
  Math1 : UnaryMath -> Prim 1
  Pow : Prim 2
  Compare : CmpPredicate -> Scalar -> Prim 2
  Cast : Conversion -> Prim 1
  StrCompare : CmpPredicate -> Prim 2
  ||| A scalar shown as a string.
  ToStr : Scalar -> Prim 1
  ||| A string read as a number.
  FromStr : Numeric -> Prim 1
  BigCompare : CmpPredicate -> Prim 2
  ToBig : Scalar -> Prim 1
  FromBig : Scalar -> Prim 1
  NatCompare : CmpPredicate -> Prim 2
  ||| The number of elements of an array a world orders, of this element
  ||| type: the dimension of its memref.
  ArrayLength : Ty -> Prim 1
  ||| The op of a pure primitive of the dialect, on its operands in the op's
  ||| order, each at its own type, giving a value of `result`.
  Op : (p : PurePrim) -> (result : Ty) -> Prim (primArity p)

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
Show IntLike where
  show (SInt t) = show t
  show SChar = "Char"

export
Show Scalar where
  show (SIntegral t) = show t
  show SDouble = "Double"

export
Show Numeric where
  show (NInt t) = show t
  show NDouble = "Double"

export
Show FArith where
  show FAdd = "add"
  show FSub = "sub"
  show FMul = "mul"
  show FDiv = "div"

export
Show UnaryMath where
  show Exp = "exp"
  show Log = "log"
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
Show (Prim k) where
  show (IntOp op t) = show op ++ "_" ++ show t
  show (IntShift s t) = show s ++ "_" ++ show t
  show (FloatOp op) = show op ++ "_Double"
  show Negate = "neg_Double"
  show (Math1 f) = show f ++ "_Double"
  show Pow = "pow_Double"
  show (Compare op s) = show op ++ "_" ++ show s
  show (Cast (IntToInt a b)) = "cast_" ++ show a ++ show b
  show (Cast (IntToDouble t)) = "cast_" ++ show t ++ "Double"
  show (Cast (DoubleToInt t)) = "cast_Double" ++ show t
  show (StrCompare op) = show op ++ "_String"
  show (ToStr s) = "cast_" ++ show s ++ "String"
  show (FromStr n) = "cast_String" ++ show n
  show (BigCompare op) = show op ++ "_Integer"
  show (ToBig s) = "cast_" ++ show s ++ "Integer"
  show (FromBig s) = "cast_Integer" ++ show s
  show (NatCompare op) = show op ++ "_Nat"
  show (ArrayLength e) = "arraySize<" ++ show e ++ ">"
  show (Op p _) = pureName p

||| The Core type of an integral scalar.
public export
likeTy : IntLike -> Ty
likeTy (SInt t) = IntT t
likeTy SChar = CharT

public export
scalarTy : Scalar -> Ty
scalarTy (SIntegral t) = likeTy t
scalarTy SDouble = DoubleT

||| The type each operand of a primitive is checked against, in Idris's
||| argument order; none for an op of the dialect, which takes each operand
||| at its own type.
public export
slots : Prim k -> Vect k (Maybe Ty)
slots (IntOp _ t) = [Just (IntT t), Just (IntT t)]
slots (IntShift _ t) = [Just (IntT t), Just (IntT t)]
slots (FloatOp _) = [Just DoubleT, Just DoubleT]
slots Negate = [Just DoubleT]
slots (Math1 _) = [Just DoubleT]
slots Pow = [Just DoubleT, Just DoubleT]
slots (Compare _ s) = [Just (scalarTy s), Just (scalarTy s)]
slots (Cast (IntToInt a _)) = [Just (likeTy a)]
slots (Cast (IntToDouble t)) = [Just (IntT t)]
slots (Cast (DoubleToInt _)) = [Just DoubleT]
slots (StrCompare _) = [Just StrT, Just StrT]
slots (ToStr s) = [Just (scalarTy s)]
slots (FromStr _) = [Just StrT]
slots (BigCompare _) = [Just BigT, Just BigT]
slots (ToBig s) = [Just (scalarTy s)]
slots (FromBig _) = [Just BigT]
slots (NatCompare _) = [Just NatT, Just NatT]
slots (ArrayLength e) = [Just (MemRefT Elements e)]
slots (Op p _) = replicate (primArity p) Nothing
