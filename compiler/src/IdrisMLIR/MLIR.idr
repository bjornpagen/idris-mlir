-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| MLIR's ops, types and attributes, as `Emit` makes them. A type and an
||| attribute are data: the builtin ones the frontend uses are constructors
||| here, and the `idr` dialect's are the values of the sums printed from
||| the dialect's specification beside their bytecode encoders
||| (IdrisMLIR.Encoding.Idr), which this module's types and attributes
||| hold. The handoff is MLIR bytecode (IdrisMLIR.MLIR.Bytecode): every
||| `idr` type and attribute is an entry of the dialect's bytecode encoding,
||| which refers to what it holds by entry, so no `idr` text crosses the
||| handoff; a double crosses as its 64 bits. Only the attributes of the
||| upstream dialects whose attributes cross as text (`arith`'s, `ub`'s,
||| `linalg`'s), and an identity layout, are their text, in the syntax their
||| dialects declare, which upstream's parsers read. Every op is its parts:
||| name, operands, attributes (its inherent ones, which become its
||| properties when it is made, with its discardable ones), regions, result
||| types and location. The generated builders make the ops
||| (IdrisMLIR.Dialect.*). A dialect is the specification's
||| (IdrisMLIR.Spec.Core.Dialect): an op's name and a text attribute hold
||| theirs, so none is told by its text.
module IdrisMLIR.MLIR

import public IdrisMLIR.MLIR.Text
import public IdrisMLIR.Encoding.Idr
import public IdrisMLIR.Encoding.Wire
import IdrisMLIR.Spec.Core.Dialect
import IdrisMLIR.Spec.Runtime.Endings

import Data.List
import Data.Maybe
import Data.String

%default total

------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------

namespace MlirType
  ||| A dimension of a shaped type: an extent the type fixes, or one the
  ||| value carries, written `?`.
  public export
  data Dim = Static Nat | Dynamic

export
Eq Dim where
  Static a == Static b = a == b
  Dynamic == Dynamic = True
  _ == _ = False

------------------------------------------------------------------------------
-- What the families' C++ reads whole
------------------------------------------------------------------------------

-- The values the families' types and attributes hold are the wire's
-- (IdrisMLIR.Encoding.Wire), printed from the specification for both
-- readers. These types and attributes take them laid out, so the frontend
-- holds them typed here until the writer has numbered what they hold.

||| The hand-coded `idr` types: `!idr.data`, a member of a family's group
||| applied to one term per index, the nodes of every term in order, refined
||| to the tags a dense array of `i32` holds (none unrefined, empty
||| uninhabited); and `!idr.self`, a member of the group being declared, in
||| a field of that group.
public export
data HandType : (ty, at : Type) -> Type where
  DataOf : (group : at) -> (member : Nat) -> (indices : List (TermNode ty at)) -> (refinement : Maybe at) -> HandType ty at
  SelfOf : (member : Nat) -> (indices : List (TermNode ty at)) -> HandType ty at

||| The hand-coded `idr` attributes: `#idr.family`, a group's data members,
||| the only members the frontend declares; `#idr.index_binders`, the sorts
||| of a function's index parameters or a region's binders;
||| `#idr.index_args`, the terms a call or a lifted function's maker gives
||| them, each its nodes, so their count is the list's; and
||| `#idr.equation`, an erased equality's two terms.
public export
data HandAttr : (ty, at : Type) -> Type where
  FamilyOf : List (DataMember ty at) -> HandAttr ty at
  BindersOf : List (SortOf ty at) -> HandAttr ty at
  ArgsOf : List (List (TermNode ty at)) -> HandAttr ty at
  EquationOf : (lhs, rhs : List (TermNode ty at)) -> HandAttr ty at

||| The text a dialect's syntax gives one of its attributes, for the
||| dialects whose attributes cross as text. It is made with the value it
||| spells, by the smart constructor printed with the value's dialect
||| (IdrisMLIR.Dialect.*), so it is that value's, under that dialect.
public export
data Spelling = MkSpelling (Lazy String)

namespace MlirAttr
  ||| An attribute, defined below: a memref's memory space is one, so the
  ||| types hold attributes as the attributes hold types.
  public export
  data MlirAttr : Type

namespace MlirType
  ||| A type: a builtin one, or one of the `idr` dialect, which holds types
  ||| and attributes of its own. A signless integer type, `i64`, is read as
  ||| an op that reads it says. A ranked tensor's and a memref's dimensions
  ||| are outermost first; a tensor has no encoding, and a memref the
  ||| identity layout and the memory space given, the default one when none
  ||| is.
  public export
  data MlirType
    = IntegerType Nat
    | F64Type
    | IndexType
    | NoneType
    | RankedTensorType (List Dim) MlirType
    | MemRefType (List Dim) MlirType (Maybe MlirAttr)
    | FunctionType (Signature MlirType)
    | ||| A type of the `idr` dialect.
      Idr (IdrType MlirType MlirAttr)
    | ||| A type of the `idr` dialect whose parameters its C++ codes by
      ||| hand, held typed until the writer lays them out.
      IdrHand (HandType MlirType MlirAttr)

------------------------------------------------------------------------------
-- Attributes
------------------------------------------------------------------------------

namespace MlirAttr
  ||| An attribute: a builtin one, or a dialect's, which holds types and
  ||| attributes of its own. An integer is of an integer type or of `index`,
  ||| a float of a float type (its value crosses as its bits); a string is
  ||| written as its UTF-8 bytes; the dense array of `i32` is the number of
  ||| values in each group of an op's operands or results, where more than
  ||| one group may vary in length, and that of `i64` the static entries of
  ||| an op's mixed index lists; a dictionary is an op's attributes of one
  ||| kind, by name; the identity map of a rank is the layout a memref of
  ||| that rank has, which its entry names.
  public export
  data MlirAttr
    = UnitAttr
    | BoolAttr Bool
    | IntegerAttr Integer MlirType
    | FloatAttr Double MlirType
    | StringAttr String
    | SymbolRefAttr SymbolRef
    | TypeAttr MlirType
    | ArrayAttr (List MlirAttr)
    | DenseI32ArrayAttr (List Nat)
    | DenseI64ArrayAttr (List Integer)
    | DictionaryAttr (List (String, MlirAttr))
    | IdentityMap Nat
    | ||| A location, as an attribute holds one (a family's declaration).
      LocAttr Location
    | ||| An attribute of the `idr` dialect.
      Idr (IdrAttr MlirType MlirAttr)
    | ||| An attribute of the `idr` dialect whose parameters its C++ codes
      ||| by hand, held typed until the writer lays them out.
      IdrHand (HandAttr MlirType MlirAttr)
    | ||| An attribute of an upstream dialect whose attributes cross as
      ||| text: the dialect, and the attribute spelled in its syntax, made
      ||| by the smart constructor printed with the dialect.
      Spelled Dialect Spelling

||| The entry of a static index list that an operand gives: MLIR's
||| `ShapedType::kDynamic`, the least 64-bit integer.
export
dynamicExtent : Integer
dynamicExtent = -9223372036854775808

||| A dimension as a shaped type writes it, with the `x` after it.
dimText : Dim -> String
dimText (Static n) = show n ++ "x"
dimText Dynamic = "?x"

mutual
  ||| A builtin type's text, as an attribute that crosses as text holds it:
  ||| `arith`'s and `ub`'s attributes hold builtin types only. An `idr` type
  ||| never crosses as text; it is its entry (`MLIR.Bytecode`).
  export
  typeText : MlirType -> String
  typeText (IntegerType w) = "i" ++ show w
  typeText F64Type = "f64"
  typeText IndexType = "index"
  typeText NoneType = "none"
  typeText (RankedTensorType ds e) = fastConcat ("tensor<" :: map dimText ds ++ [typeText e, ">"])
  typeText (MemRefType ds e Nothing) = fastConcat ("memref<" :: map dimText ds ++ [typeText e, ">"])
  typeText (MemRefType ds e (Just a)) = fastConcat ("memref<" :: map dimText ds ++ [typeText e, ", " ++ attrText a, ">"])
  typeText (FunctionType (MkSignature ins outs)) = signature id (MkSignature (typesText ins) (typesText outs))
  -- No text attribute holds one, so this is never read.
  typeText (Idr _) = "none"
  typeText (IdrHand _) = "none"

  typesText : List MlirType -> List String
  typesText [] = []
  typesText (t :: ts) = typeText t :: typesText ts

  ||| The text of an attribute that crosses as text: an upstream dialect's
  ||| spelled when made, and an identity layout. Every other attribute is
  ||| its entry (`MLIR.Bytecode`); a builtin attribute that a spelled
  ||| attribute's text holds is written by this function.
  export
  attrText : MlirAttr -> String
  attrText UnitAttr = "unit"
  attrText (BoolAttr b) = if b then "true" else "false"
  attrText (IntegerAttr n t) = show n ++ " : " ++ typeText t
  -- A float never crosses as text: its entry holds its bits.
  attrText (FloatAttr _ t) = "0 : " ++ typeText t
  attrText (StringAttr s) = utf8Literal s
  attrText (SymbolRefAttr r) = symbolRef r
  attrText (TypeAttr t) = typeText t
  attrText (ArrayAttr as) = array id (attrsText as)
  attrText (DenseI32ArrayAttr []) = "array<i32>"
  attrText (DenseI32ArrayAttr ns) = "array<i32: " ++ commaSeparated (map show ns) ++ ">"
  attrText (DenseI64ArrayAttr []) = "array<i64>"
  attrText (DenseI64ArrayAttr ns) = "array<i64: " ++ commaSeparated (map show ns) ++ ">"
  attrText (DictionaryAttr as) = "{" ++ commaSeparated (entriesText as) ++ "}"
  attrText (IdentityMap n) =
    let dims = commaSeparated (map (\i => "d" ++ show i) (take n [0 .. n])) in
    fastConcat ["affine_map<(", dims, ") -> (", dims, ")>"]
  -- No text attribute holds one of these, so this is never read.
  attrText (LocAttr _) = "unit"
  attrText (Idr _) = "unit"
  attrText (IdrHand _) = "unit"
  attrText (Spelled _ (MkSpelling s)) = s

  attrsText : List MlirAttr -> List String
  attrsText [] = []
  attrsText (a :: as) = attrText a :: attrsText as

  ||| The entries of a dictionary: a unit attribute is its name alone.
  entriesText : List (String, MlirAttr) -> List String
  entriesText [] = []
  entriesText ((name, UnitAttr) :: es) = name :: entriesText es
  entriesText ((name, a) :: es) = (name ++ " = " ++ attrText a) :: entriesText es

||| The dialect of an attribute that crosses as text: a spelled one's own,
||| and builtin's for an identity layout and the builtin attributes the
||| writer writes as text.
export
attrDialect : MlirAttr -> Dialect
attrDialect (Spelled d _) = d
attrDialect (Idr _) = Dialect.Idr
attrDialect (IdrHand _) = Dialect.Idr
attrDialect _ = Builtin

||| A tensor's or a memref's element type, any other type itself, as
||| upstream's `getElementTypeOrSelf` gives it: what the builder of an op
||| whose result is an array's element computes that result's type with,
||| as the op's C++ inference does.
export
elementTypeOrSelf : MlirType -> MlirType
elementTypeOrSelf (RankedTensorType _ e) = e
elementTypeOrSelf (MemRefType _ e _) = e
elementTypeOrSelf t = t

||| An attribute of an op's: its name, and itself.
public export
NamedAttr : Type
NamedAttr = (String, MlirAttr)

||| A unit attribute, there when `set`.
export
unitIf : String -> Bool -> List NamedAttr
unitIf name set = if set then [(name, UnitAttr)] else []

||| An attribute ODS lets an op leave out, there when given.
export
attrIf : String -> (a -> MlirAttr) -> Maybe a -> List NamedAttr
attrIf name make = maybe [] (\x => [(name, make x)])

------------------------------------------------------------------------------
-- Operations
------------------------------------------------------------------------------

||| A value's identity in its function: result `i` of what binds it, by
||| that binder's number among the function's (a block's argument binds
||| one, its result 0); or none, for what is no value of the module
||| (Idris's world), which no op may take. Values are looked up and told
||| apart by it, never by text.
public export
data ValueId = Bound Nat Nat | Unbound

export
Eq ValueId where
  Bound b i == Bound c j = b == c && i == j
  Unbound == Unbound = True
  _ == _ = False

export
Ord ValueId where
  compare (Bound b i) (Bound c j) = compare (b, i) (c, j)
  compare (Bound _ _) Unbound = LT
  compare Unbound (Bound _ _) = GT
  compare Unbound Unbound = EQ

||| A value an op uses or a region binds: its identity and its type.
public export
record Value where
  constructor MkValue
  name : ValueId
  type : MlirType

||| A block argument: the value it binds, at the binder's location.
public export
record Argument where
  constructor MkArgument
  value : Value
  at : Location

||| An op's name: its dialect and its name there (`addi` of `arith.addi`),
||| as bytecode records it.
public export
record OpName where
  constructor MkOpName
  dialect : Dialect
  name : String

mutual
  ||| An op, as the generated builders make it (IdrisMLIR.Dialect.*).
  public export
  record Op where
    constructor MkOp
    name : OpName
    operands : List Value
    ||| Its inherent attributes, which ODS declares.
    properties : List NamedAttr
    regions : List Region
    ||| Its discardable attributes.
    attributes : List NamedAttr
    results : List MlirType

  ||| A region: of no blocks, which an op whose region may be empty holds
  ||| (a match's default when its cases are exhaustive); or of one block,
  ||| its arguments and its ops.
  public export
  data Region = NoBlocks | MkRegion (List Argument) (List Statement)

  ||| An op where it stands: its number among its function's binders, if
  ||| it has results, which they are bound at, and its location.
  public export
  record Statement where
    constructor MkStatement
    result : Maybe Nat
    op : Op
    at : Location

||| An op as the builder of a partial op gives it: the op, or a guard to
||| write before it and what follows given the guard's result. A guard is
||| its check op, the cause its crash names, the operand it
||| checks and the others it is given; the op takes the guard's result in
||| place of the operand it checks. A builder names each of its operands by
||| its own binder, so no guard names an operand by its position, and none
||| can name one the op lacks.
public export
data Guarded : Type where
  Unguarded : Op -> Guarded
  Checking : (check : OpName) -> (cause : Cause) -> (checked : Value) -> (others : List Value)
          -> (Value -> Guarded) -> Guarded

||| Each of `xs` checked in turn by `check` against the same `others`, and
||| what follows given their results, in order: how a builder guards a
||| group of operands that holds any number.
export
checkingEach : (check : OpName) -> (cause : Cause) -> (xs, others : List Value) -> (List Value -> Guarded) -> Guarded
checkingEach check cause [] others next = next []
checkingEach check cause (x :: xs) others next =
  Checking check cause x others (\x' => checkingEach check cause xs others (\xs' => next (x' :: xs')))

||| The values a statement binds, its results in order.
export
boundNames : Statement -> List ValueId
boundNames (MkStatement (Just r) o _) = let n = length o.results in map (Bound r) (take n [0 .. n])
boundNames (MkStatement Nothing _ _) = []

------------------------------------------------------------------------------
-- Values
------------------------------------------------------------------------------

||| What a walk of a region meets of its values, in order: each block's
||| arguments, then, for each statement, the values its op uses, then the
||| values its results are bound to (`boundNames`), then what the op's
||| regions hold.
public export
data Occurrence = Uses Value | Binds Value | Defines (List ValueId)

mutual
  ||| A fold over a region's values, in the order `Occurrence` says.
  export
  walkRegion : (a -> Occurrence -> a) -> a -> Region -> a
  walkRegion f acc NoBlocks = acc
  walkRegion f acc (MkRegion args ss) = walkStatements f (foldl (\x, g => f x (Binds g.value)) acc args) ss

  walkStatements : (a -> Occurrence -> a) -> a -> List Statement -> a
  walkStatements f acc [] = acc
  walkStatements f acc (MkStatement r (MkOp n operands props regions attrs results) at :: ss) =
    let used = foldl (\x, v => f x (Uses v)) acc operands
        named = case r of
          Just _ => f used (Defines (boundNames (MkStatement r (MkOp n operands props regions attrs results) at)))
          Nothing => used
    in walkStatements f (walkRegions f named regions) ss

  walkRegions : (a -> Occurrence -> a) -> a -> List Region -> a
  walkRegions f acc [] = acc
  walkRegions f acc (r :: rs) = walkRegions f (walkRegion f acc r) rs

mutual
  ||| A region with every value it binds as a block's argument, and every
  ||| value its ops use, renamed by `f`: what a lifted function's body
  ||| uses of its captures becomes its own arguments.
  export
  renameRegion : (ValueId -> ValueId) -> Region -> Region
  renameRegion f NoBlocks = NoBlocks
  renameRegion f (MkRegion args ss) =
    MkRegion (map (\a => { value.name $= f } a) args) (renameStatements f ss)

  renameStatements : (ValueId -> ValueId) -> List Statement -> List Statement
  renameStatements f [] = []
  renameStatements f (MkStatement r (MkOp n operands props regions attrs results) at :: ss) =
    MkStatement r (MkOp n (map (\v => { name $= f } v) operands) props (renameRegions f regions) attrs results) at
      :: renameStatements f ss

  renameRegions : (ValueId -> ValueId) -> List Region -> List Region
  renameRegions f [] = []
  renameRegions f (r :: rs) = renameRegion f r :: renameRegions f rs
