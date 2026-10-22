-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Types, literals and primitives of Core.
|||
||| There is one type language: every type of full Core exists at runtime,
||| and MLIR removes abstraction. A data type is the inductive family Idris
||| checked, applied to index terms (`DataT`): the family is declared once
||| (`Term.Family`), its identity a dense number of the program's family
||| table, and the application states what is known of each erased index,
||| as the scope it is written in knows it. Types Idris flags `ZERO`/`SUCC`
||| are not data at all: they are `NatT`, a natural as a number.
module IdrisMLIR.Types

import IdrisMLIR.Ids
import IdrisMLIR.MLIR
import IdrisMLIR.Spec.Core.Op as Spec
import IdrisMLIR.Spec.Ops.Values
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Spec.Runtime.Clocks
import IdrisMLIR.Spec.Ops.Platform

import Data.String
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Integer types
------------------------------------------------------------------------------

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

||| How an Idris integer type reads its bits: which of an op's two
||| members (`divs` or `divu`, `extsi` or `extui`) computes on it. A choice
||| between two ops, never a `Bool`.
public export
data Signedness = Signed | Unsigned

export
signedness : IntTy -> Signedness
signedness UInt8 = Unsigned
signedness UInt16 = Unsigned
signedness UInt32 = Unsigned
signedness UInt64 = Unsigned
signedness _ = Signed

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
  ||| What is known of an erased index, in the scope it is written in: a
  ||| natural as a number; a level of the scope's telescope of erased
  ||| binders (a function's index parameters, then each enclosing case's
  ||| constructor binders, outermost first); a term plus a constant; a
  ||| literal of a scalar sort, or a type; a constructor of a family member
  ||| applied to its binders and then its fields, in declaration order; or
  ||| nothing, an index outside the language, which refines nothing. Only
  ||| normal forms are built (`succ`, `iCon`): no successor of a number or
  ||| of a successor, and a numeral family's constructors read as numbers.
  public export
  data ITerm
    = INat Nat
    | IVar Nat
    | ISucc ITerm Nat
    | ILit Lit
    | IType Ty
    | ICon FamilyId Nat (List ITerm)
    | IOpaque

  ||| The sort of an erased binder or of a family's index: a natural, a
  ||| type, an index outside the language, a scalar of the type given, or a
  ||| value of a family.
  public export
  data Sort = SNat | SType | SOpaque | SScalar Ty | SFamily FamilyId

  ||| The types of Core. `BigT` is `Integer`; `NatT` is `Nat`, an integer
  ||| that is never negative, a number at runtime, linked to the index term
  ||| it is: a literal's number, the level of a binder that is both a value
  ||| and an index, or `IOpaque` where no term is known; `FunT` is a closure,
  ||| binding its argument as a lambda does; `LazyT` is a suspension, one
  ||| cell whose value is shared by every force; `DataT` is a family
  ||| applied to one term per index, whatever its values hold: how they are
  ||| laid out, inline or in a cell, is the dialect's to decide from the
  ||| type. `TensorT` is a value of the array language (`Array s a`, which
  ||| a linear array's cell holds): a ranked tensor of its element, one
  ||| dimension per axis of the form of `s`, outermost first, static where
  ||| the shape's normal form at the instance is a literal; an array of
  ||| arrays is one tensor, the element's dimensions after the shape's, so
  ||| its element is never a tensor or a memref. `MemRefT` is an array a
  ||| world orders (`Ordered`); its element is never a tensor. `WorldT` is
  ||| Idris's world, which Core keeps so that the translation reads IO as
  ||| Idris wrote it; Emit writes no value of it, since after the frontend
  ||| IO is ordered by effects.
  public export
  data Ty = IntT IntTy | CharT | DoubleT | StrT | BigT | NatT ITerm | WorldT
          | DataT FamilyId (List ITerm)
          | FunT Binder Ty
          | LazyT Ty
          | TensorT (List Dim) Ty
          | MemRefT Ordered Ty

  ||| What a parameter, a lambda, an arrow, a `let` or a constructor field
  ||| binds: a value of a type, used as Idris proved, once or many times.
  ||| A binder of quantity zero binds no runtime value, so it is not a
  ||| binder: the position is absent, or an erased binder of the scope's
  ||| telescope (`Sort`) when an index refers to it.
  public export
  record Binder where
    constructor MkBinder
    quantity : Uses
    type : Ty

  ||| A literal. `LNat` is a natural, never negative: one constant of
  ||| `NatT`, however large, never a chain of successors.
  public export
  data Lit = LInt IntTy Integer | LChar Integer | LStr String | LDouble Double | LBig Integer
           | LNat Integer

||| The type of what a binder binds.
public export
typeOf : Binder -> Ty
typeOf = (.type)

||| `t + k` in normal form: a successor of a number is a number, and of a
||| successor one successor of the sum.
export
succ : ITerm -> Nat -> ITerm
succ t Z = t
succ (INat a) k = INat (a + k)
succ (ISucc t a) k = ISucc t (a + k)
succ t k = ISucc t k

||| Whether two uses are one: the quantities a binder can hold.
export
sameUses : Uses -> Uses -> Bool
sameUses Once Once = True
sameUses Many Many = True
sameUses _ _ = False

mutual
  sameTerm : ITerm -> ITerm -> Bool
  sameTerm (INat a) (INat b) = a == b
  sameTerm (IVar a) (IVar b) = a == b
  sameTerm (ISucc t a) (ISucc u b) = a == b && sameTerm t u
  sameTerm (ILit a) (ILit b) = sameLit a b
  sameTerm (IType a) (IType b) = sameTy a b
  sameTerm (ICon f c as) (ICon g d bs) = f == g && c == d && sameTerms as bs
  sameTerm IOpaque IOpaque = True
  sameTerm _ _ = False

  sameTerms : List ITerm -> List ITerm -> Bool
  sameTerms [] [] = True
  sameTerms (a :: as) (b :: bs) = sameTerm a b && sameTerms as bs
  sameTerms _ _ = False

  sameLit : Lit -> Lit -> Bool
  sameLit (LInt s a) (LInt t b) = s == t && a == b
  sameLit (LChar a) (LChar b) = a == b
  sameLit (LStr a) (LStr b) = a == b
  sameLit (LDouble a) (LDouble b) = a == b
  sameLit (LBig a) (LBig b) = a == b
  sameLit (LNat a) (LNat b) = a == b
  sameLit _ _ = False

  sameTy : Ty -> Ty -> Bool
  sameTy (IntT a) (IntT b) = a == b
  sameTy CharT CharT = True
  sameTy DoubleT DoubleT = True
  sameTy StrT StrT = True
  sameTy BigT BigT = True
  sameTy (NatT a) (NatT b) = sameTerm a b
  sameTy WorldT WorldT = True
  sameTy (DataT f ts) (DataT g us) = f == g && sameTerms ts us
  sameTy (FunT a r) (FunT a' r') = sameBinder a a' && sameTy r r'
  sameTy (LazyT a) (LazyT b) = sameTy a b
  sameTy (TensorT ds a) (TensorT es b) = ds == es && sameTy a b
  sameTy (MemRefT o a) (MemRefT p b) = o == p && sameTy a b
  sameTy _ _ = False

  sameBinder : Binder -> Binder -> Bool
  sameBinder (MkBinder q t) (MkBinder q' t') = sameUses q q' && sameTy t t'

export
Eq ITerm where
  (==) = sameTerm

export
Eq Ty where
  (==) = sameTy

export
Eq Binder where
  (==) = sameBinder

export
Eq Lit where
  (==) = sameLit

mutual
  ||| A type as a message names it: text for a human, never compared.
  export
  tyText : Ty -> String
  tyText (IntT t) = show t
  tyText CharT = "Char"
  tyText DoubleT = "Double"
  tyText StrT = "String"
  tyText BigT = "Integer"
  tyText (NatT t) = "Nat[" ++ termText t ++ "]"
  tyText WorldT = "%World"
  tyText (DataT f ts) = "data " ++ show f ++ "[" ++ joinBy ", " (termsText ts) ++ "]"
  tyText (FunT a r) = "((" ++ binderText a ++ ") -> " ++ tyText r ++ ")"
  tyText (LazyT a) = "Lazy (" ++ tyText a ++ ")"
  tyText (TensorT ds a) = "Tensor [<" ++ joinBy ", " (map dimText ds) ++ "] (" ++ tyText a ++ ")"
    where
      dimText : Dim -> String
      dimText (Static n) = show n
      dimText Dynamic = "?"
  tyText (MemRefT Cell a) = "Mut (" ++ tyText a ++ ")"
  tyText (MemRefT Elements a) = "Array (" ++ tyText a ++ ")"

  binderText : Binder -> String
  binderText (MkBinder Once t) = "1 " ++ tyText t
  binderText (MkBinder Many t) = "w " ++ tyText t

  termText : ITerm -> String
  termText (INat n) = show n
  termText (IVar k) = "v" ++ show k
  termText (ISucc t k) = termText t ++ " + " ++ show k
  termText (ILit l) = "lit"
  termText (IType t) = "type " ++ tyText t
  termText (ICon f c as) = show f ++ "@" ++ show c ++ "(" ++ joinBy ", " (termsText as) ++ ")"
  termText IOpaque = "_"

  termsText : List ITerm -> List String
  termsText [] = []
  termsText (t :: ts) = termText t :: termsText ts

export
Show Ty where
  show = tyText

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

%prefix_record_projections off

||| Which index term each `?` of a function's signature is: for each
||| parameter at run time, in order, and for the result, the axes of its
||| tensor type that a term over the function's index parameters names,
||| each with that term, by axis. A tensor type has no symbolic dimension,
||| so the link from an array's extent to its index rides here, beside the
||| signature, into the function's `extents`, where specialization
||| substitutes a call's terms into it. An
||| axis a number fixes is static in the type and is not here, nor is one
||| no term names; a parameter's place is its position in the vector, so
||| no entry names a parameter the function lacks.
public export
record Extents (arity : Nat) where
  constructor MkExtents
  params : Vect arity (List (Nat, ITerm))
  result : List (Nat, ITerm)

%prefix_record_projections on

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

||| The signedness of a fixed-width integer or a `Char`, which reads as
||| unsigned.
export
likeSignedness : IntLike -> Signedness
likeSignedness (SInt t) = signedness t
likeSignedness SChar = Unsigned

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
  Compare : Comparison -> Scalar -> Prim 2
  Cast : Conversion -> Prim 1
  StrCompare : Comparison -> Prim 2
  ||| A scalar shown as a string.
  ToStr : Scalar -> Prim 1
  ||| A string read as a number.
  FromStr : Numeric -> Prim 1
  BigCompare : Comparison -> Prim 2
  ToBig : Scalar -> Prim 1
  FromBig : Scalar -> Prim 1
  NatCompare : Comparison -> Prim 2
  ||| The number of elements of an array a world orders, of this element
  ||| type: the dimension of its memref.
  ArrayLength : Ty -> Prim 1
  ||| The op of a pure primitive of the dialect, on its operands in the op's
  ||| order, each at its own type, giving a value of `result` at the hold its
  ||| declaration gives it, where that type holds references (`made`, or
  ||| static for text the target names).
  Op : {i : Nat} -> (op : Spec.Op i 1 0 0) -> (result : Ty) -> (hold : Hold) -> Prim i

||| The hold of a value an op makes: counted, claiming nothing of its
||| sharing.
public export
made : Hold
made = Hold.Counted None

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
  show (Op op _ _) = opName op

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
slots (NatCompare _) = [Just (NatT IOpaque), Just (NatT IOpaque)]
slots (ArrayLength e) = [Just (MemRefT Elements e)]
slots (Op {i} _ _ _) = replicate i Nothing

------------------------------------------------------------------------------
-- IO primitives
------------------------------------------------------------------------------

||| An access to an array a world orders (`ArrayData`, an IORef's cell, a
||| buffer's bytes), by what it does: a new array, each element the fill;
||| an element read; an element written. Each is its op of the dialect at
||| the rank the array's type has, one size or index per dimension, none
||| for a cell, and a size or index reaches the op as an `index`.
public export
data ArrayAccess = NewArray | GetElement | SetElement

||| How many values an access gives.
public export
accessResults : ArrayAccess -> Nat
accessResults NewArray = 1
accessResults GetElement = 1
accessResults SetElement = 0

||| How many operands an access takes besides the world, at an array of
||| `rank` dimensions: a new array its sizes and its fill; a read the array
||| and its indices; a write those and the value.
public export
accessOperands : ArrayAccess -> (rank : Nat) -> Nat
accessOperands NewArray rank = S rank
accessOperands GetElement rank = S rank
accessOperands SetElement rank = S (S rank)

||| The rank of the array an access is on, from how many operands it takes
||| besides the world, with the evidence that it takes that many at that
||| rank; none for a count no rank gives.
public export
accessRank : (a : ArrayAccess) -> (operands : Nat) -> Maybe (rank : Nat ** accessOperands a rank = operands)
accessRank NewArray (S rank) = Just (rank ** Refl)
accessRank GetElement (S rank) = Just (rank ** Refl)
accessRank SetElement (S (S rank)) = Just (rank ** Refl)
accessRank _ _ = Nothing

||| A machine word a buffer holds: a fixed-width integer of its type, or a
||| double. Its registry row names it, so its width is the row's.
public export
data BufferWord = WordInt IntTy | WordDouble

||| The bytes a word takes in a buffer.
export
wordBytes : BufferWord -> Nat
wordBytes (WordInt t) = width t `div` 8
wordBytes WordDouble = 8

||| A move of a buffer's bytes, within the buffer or between it and a
||| handle, each behind the check that its span lies in the buffer: a word
||| loaded or stored at an offset; bytes copied from one buffer into
||| another; a string's bytes written, or a run read as a string; bytes
||| written to a handle, or read from one.
public export
data BufferMove = LoadWord BufferWord | StoreWord BufferWord | CopyBytes | SetString | GetString | WriteBytes | ReadBytes

||| How many values a move gives.
public export
moveResults : BufferMove -> Nat
moveResults (LoadWord _) = 1
moveResults (StoreWord _) = 0
moveResults CopyBytes = 0
moveResults SetString = 0
moveResults GetString = 1
moveResults WriteBytes = 1
moveResults ReadBytes = 1

||| How many operands a move takes besides the world: the buffer and the
||| offset of a word, and the word stored; a source, its offset, a length,
||| a destination and its offset; a buffer, an offset and a string or a
||| length; a handle, a buffer, an offset and a count.
public export
moveOperands : BufferMove -> Nat
moveOperands (LoadWord _) = 2
moveOperands (StoreWord _) = 3
moveOperands CopyBytes = 5
moveOperands SetString = 3
moveOperands GetString = 3
moveOperands WriteBytes = 4
moveOperands ReadBytes = 4

||| What a clock's reading tells, as arithmetic on the reading's encoding:
||| whether the clock was read, its seconds, its nanoseconds.
public export
data ClockQuery = Valid | Seconds | Nanoseconds

||| How many values an IO action gives, as a call's `IORes` holds them:
||| none, or one.
public export
data Gives : Nat -> Type where
  GivesNone : Gives 0
  GivesOne : Gives 1

||| What an IO primitive does, indexed by how many operands it takes besides
||| the world and how many values it gives: an op of the dialect with no
||| attribute, whose every operand group is one operand, on the call's
||| operands, giving what an `IORes` holds; a reading of a clock of a
||| kind; a reading of a clock no program has (the collector's), which is
||| the mark of an unread clock; a query of a reading; a reading of one
||| field of a file-time handle (`io.file_time`'s); an access to an array a
||| world orders, at its rank; a move of a buffer's bytes; the end of the
||| process, at its status; or nothing, where the platform has nothing to
||| do (setting up a terminal, which only another system needs).
public export
data IOAction : (operands, results : Nat) -> Type where
  Runs : {i, o : Nat} -> {auto gives : Gives o} -> Spec.Op i o 0 0 -> IOAction i o
  ReadsClock : ClockKind -> IOAction 0 1
  NeverRead : IOAction 0 1
  Queries : ClockQuery -> IOAction 1 1
  ReadsFileTime : FileTimeField -> IOAction 1 1
  Accesses : (a : ArrayAccess) -> (rank : Nat) -> IOAction (accessOperands a rank) (accessResults a)
  Moves : (m : BufferMove) -> IOAction (moveOperands m) (moveResults m)
  Exits : IOAction 1 0
  DoesNothing : IOAction 0 0

||| How many values an action gives.
public export
actionGives : IOAction i o -> Gives o
actionGives (Runs {gives} _) = gives
actionGives (ReadsClock _) = GivesOne
actionGives NeverRead = GivesOne
actionGives (Queries _) = GivesOne
actionGives (ReadsFileTime _) = GivesOne
actionGives (Accesses NewArray _) = GivesOne
actionGives (Accesses GetElement _) = GivesOne
actionGives (Accesses SetElement _) = GivesNone
actionGives (Moves (LoadWord _)) = GivesOne
actionGives (Moves (StoreWord _)) = GivesNone
actionGives (Moves CopyBytes) = GivesNone
actionGives (Moves SetString) = GivesNone
actionGives (Moves GetString) = GivesOne
actionGives (Moves WriteBytes) = GivesOne
actionGives (Moves ReadBytes) = GivesOne
actionGives Exits = GivesNone
actionGives DoesNothing = GivesNone

||| An IO primitive with how many operands it takes and values it gives, as
||| a registry row names one.
public export
record SomeAction where
  constructor MkSomeAction
  {operands : Nat}
  {results : Nat}
  action : IOAction operands results
