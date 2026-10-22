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
||| handoff; a double crosses as its 64 bits. Only `arith`'s and `ub`'s
||| attributes, and an identity layout, are their text, in the syntax their
||| dialects declare, which upstream's parsers read. Every op is its parts:
||| name, operands, attributes (its inherent ones, which become its
||| properties when it is made, with its discardable ones), regions, result
||| types and location. The generated builders make the ops
||| (IdrisMLIR.Dialect.*).
module IdrisMLIR.MLIR

import public IdrisMLIR.MLIR.Text
import public IdrisMLIR.Encoding.Idr
import public IdrisMLIR.Encoding.Hand
import IdrisMLIR.Syntax.Arith
import IdrisMLIR.Syntax.UB

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

||| The text a dialect's syntax gives one of its attributes, for the
||| dialects whose attributes cross as text (`arith`, `ub`). It is made with
||| the value it spells, by the value's one constructor (`arith`, `ub`), so
||| it is always that value's.
export
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
    | ||| An attribute of the `arith` dialect, made by `arith`.
      Arith (ArithAttr MlirType MlirAttr) Spelling
    | ||| An attribute of the `ub` dialect, made by `ub`.
      UB (UBAttr MlirType MlirAttr) Spelling

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

  ||| The text of an attribute that crosses as text: `arith`'s and `ub`'s,
  ||| spelled when made, and an identity layout. Every other attribute is
  ||| its entry (`MLIR.Bytecode`); a builtin attribute that `arith`'s or
  ||| `ub`'s text holds is written by this function.
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
  attrText (Arith _ (MkSpelling s)) = s
  attrText (UB _ (MkSpelling s)) = s

  attrsText : List MlirAttr -> List String
  attrsText [] = []
  attrsText (a :: as) = attrText a :: attrsText as

  ||| The entries of a dictionary: a unit attribute is its name alone.
  entriesText : List (String, MlirAttr) -> List String
  entriesText [] = []
  entriesText ((name, UnitAttr) :: es) = name :: entriesText es
  entriesText ((name, a) :: es) = (name ++ " = " ++ attrText a) :: entriesText es

namespace MlirAttr
  ||| An attribute of the `arith` dialect, spelled as its syntax writes it.
  export
  arith : ArithAttr MlirType MlirAttr -> MlirAttr
  arith x = Arith x (MkSpelling (arithAttrText typeText attrText x))

  ||| An attribute of the `ub` dialect, spelled as its syntax writes it.
  export
  ub : UBAttr MlirType MlirAttr -> MlirAttr
  ub x = UB x (MkSpelling (ubAttrText typeText attrText x))

||| The dialect a type is of, by its constructor.
export
typeDialect : MlirType -> String
typeDialect (Idr _) = "idr"
typeDialect (IdrHand _) = "idr"
typeDialect _ = "builtin"

||| The dialect an attribute is of, by its constructor.
export
attrDialect : MlirAttr -> String
attrDialect (Idr _) = "idr"
attrDialect (IdrHand _) = "idr"
attrDialect (Arith _ _) = "arith"
attrDialect (UB _ _) = "ub"
attrDialect _ = "builtin"

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

||| A value an op uses or a region binds: its SSA name and its type.
public export
record Value where
  constructor MkValue
  name : String
  type : MlirType

||| A block argument: the value it binds, at the binder's location.
public export
record Argument where
  constructor MkArgument
  value : Value
  at : Location

mutual
  ||| An op, as the generated builders make it (IdrisMLIR.Dialect.*).
  public export
  record Op where
    constructor MkOp
    name : String
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

  ||| An op where it stands: the name of its results, if it has any, and
  ||| its location.
  public export
  record Statement where
    constructor MkStatement
    result : Maybe String
    op : Op
    at : Location

||| The name of result `i` of the `n` an op gives, its statement's name
||| `r`: `r` itself for one result, `r#i` of several, as an op's operands
||| name them.
export
resultAt : (r : String) -> (n : Nat) -> (i : Nat) -> String
resultAt r (S Z) _ = r
resultAt r _ i = r ++ "#" ++ show i

||| The names a statement binds its results to, in order.
export
boundNames : Statement -> List String
boundNames (MkStatement (Just r) o _) = let n = length o.results in map (resultAt r n) (take n [0 .. n])
boundNames (MkStatement Nothing _ _) = []

------------------------------------------------------------------------------
-- Values
------------------------------------------------------------------------------

||| What a walk of a region meets of its values, in order: each block's
||| arguments, then, for each statement, the values its op uses, then the
||| statement's name and the names its results are bound to (`boundNames`),
||| then what the op's regions hold.
public export
data Occurrence = Uses Value | Binds Value | Defines String (List String)

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
          Just name => f used (Defines name (boundNames (MkStatement r (MkOp n operands props regions attrs results) at)))
          Nothing => used
    in walkStatements f (walkRegions f named regions) ss

  walkRegions : (a -> Occurrence -> a) -> a -> List Region -> a
  walkRegions f acc [] = acc
  walkRegions f acc (r :: rs) = walkRegions f (walkRegion f acc r) rs

mutual
  ||| A region with every value renamed by `f`, where it is defined and
  ||| where it is used: block arguments, statements' names, operands. A
  ||| use of one of several results is renamed as itself, `name#i`.
  export
  renameRegion : (String -> String) -> Region -> Region
  renameRegion f NoBlocks = NoBlocks
  renameRegion f (MkRegion args ss) =
    MkRegion (map (\a => { value.name $= f } a) args) (renameStatements f ss)

  renameStatements : (String -> String) -> List Statement -> List Statement
  renameStatements f [] = []
  renameStatements f (MkStatement r (MkOp n operands props regions attrs results) at :: ss) =
    MkStatement (map f r)
                (MkOp n (map (\v => { name $= f } v) operands) props (renameRegions f regions) attrs results) at
      :: renameStatements f ss

  renameRegions : (String -> String) -> List Region -> List Region
  renameRegions f [] = []
  renameRegions f (r :: rs) = renameRegion f r :: renameRegions f rs
