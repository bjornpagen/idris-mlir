-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| MLIR's ops, types and attributes, as `Emit` makes them. A type and an
||| attribute are data: the builtin ones the frontend uses are constructors
||| here, and each dialect's are the constructors of the sums generated from
||| the dialect's ODS (IdrisMLIR.Syntax.*), which this module's types and
||| attributes hold; each is written in the syntax ODS declares for it,
||| which the dialect's generated C++ parser reads. The handoff is MLIR
||| bytecode (IdrisMLIR.MLIR.Bytecode), which keeps every attribute and type
||| as that text, the bytecode's own encoding of one a dialect gives no
||| other, and every op as its parts: name, operands, inherent attributes
||| (its properties), regions, discardable attributes, result types and
||| location. The generated builders make the ops (IdrisMLIR.Dialect.*). An
||| op's text, in MLIR's generic form, is only what a content key hashes.
module IdrisMLIR.MLIR

import public IdrisMLIR.MLIR.Text
import public IdrisMLIR.Syntax.Idr
import IdrisMLIR.Syntax.Arith
import IdrisMLIR.Syntax.UB
import IdrisMLIR.Ids
import IdrisMLIR.Loc

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

namespace MlirAttr
  ||| An attribute, defined below: a memref's memory space is one, so the
  ||| types hold attributes as the attributes hold types.
  public export
  data MlirAttr : Type

namespace MlirType
  ||| A type: a builtin one, or a dialect's, which holds types of its own.
  ||| A signless integer type, `i64`, is read as an op that reads it says.
  ||| A ranked tensor's and a memref's dimensions are outermost first; a
  ||| tensor has no encoding, and a memref the identity layout and the
  ||| memory space given, the default one when none is.
  public export
  data MlirType
    = IntegerType Nat
    | F64Type
    | IndexType
    | NoneType
    | RankedTensorType (List Dim) MlirType
    | MemRefType (List Dim) MlirType (Maybe MlirAttr)
    | FunctionType (Signature MlirType)
    | Idr (IdrType MlirType)

------------------------------------------------------------------------------
-- Attributes
------------------------------------------------------------------------------

namespace MlirAttr
  ||| An attribute: a builtin one, or a dialect's, which holds types and
  ||| attributes of its own. An integer is of an integer type or of `index`,
  ||| a float of a float type; a string is written as its UTF-8 bytes; the
  ||| dense array of `i32` is the number of values in each group of an op's
  ||| operands or results, where more than one group may vary in length, and
  ||| that of `i64` the static entries of an op's mixed index lists; a
  ||| dictionary is an op's attributes of one kind, by name.
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
    | Idr (IdrAttr MlirType MlirAttr)
    | Arith (ArithAttr MlirType MlirAttr)
    | UB (UBAttr MlirType MlirAttr)

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
  ||| A type's text. A dialect's type writes the types it holds by this
  ||| function, so each is a part of the type it is in: a recursion through
  ||| a function the dialect's syntax is given, which the totality checker
  ||| does not follow, so this and what prints with it are covering.
  export covering
  typeText : MlirType -> String
  typeText (IntegerType w) = "i" ++ show w
  typeText F64Type = "f64"
  typeText IndexType = "index"
  typeText NoneType = "none"
  typeText (RankedTensorType ds e) = fastConcat ("tensor<" :: map dimText ds ++ [typeText e, ">"])
  typeText (MemRefType ds e space) =
    fastConcat ("memref<" :: map dimText ds ++ [typeText e, maybe "" (\a => ", " ++ attrText a) space, ">"])
  typeText (FunctionType s) = signature typeText s
  typeText (Idr x) = idrTypeText typeText x

  ||| An attribute's text, each attribute it holds written by this function.
  export covering
  attrText : MlirAttr -> String
  attrText UnitAttr = "unit"
  attrText (BoolAttr b) = if b then "true" else "false"
  attrText (IntegerAttr n t) = show n ++ " : " ++ typeText t
  attrText (FloatAttr d t) = floatLiteral d ++ " : " ++ typeText t
  attrText (StringAttr s) = Text.utf8 s
  attrText (SymbolRefAttr r) = symbolRef r
  attrText (TypeAttr t) = typeText t
  attrText (ArrayAttr as) = array attrText as
  attrText (DenseI32ArrayAttr []) = "array<i32>"
  attrText (DenseI32ArrayAttr ns) = "array<i32: " ++ commaSeparated (map show ns) ++ ">"
  attrText (DenseI64ArrayAttr []) = "array<i64>"
  attrText (DenseI64ArrayAttr ns) = "array<i64: " ++ commaSeparated (map show ns) ++ ">"
  attrText (DictionaryAttr as) = "{" ++ commaSeparated (map entryText as) ++ "}"
  attrText (Idr x) = idrAttrText typeText attrText x
  attrText (Arith x) = arithAttrText typeText attrText x
  attrText (UB x) = ubAttrText typeText attrText x

  ||| An entry of a dictionary: a unit attribute is its name alone.
  covering
  entryText : (String, MlirAttr) -> String
  entryText (name, UnitAttr) = name
  entryText (name, a) = name ++ " = " ++ attrText a

||| The dialect a type is of, by its constructor.
export
typeDialect : MlirType -> String
typeDialect (Idr _) = "idr"
typeDialect _ = "builtin"

||| The dialect an attribute is of, by its constructor.
export
attrDialect : MlirAttr -> String
attrDialect (Idr _) = "idr"
attrDialect (Arith _) = "arith"
attrDialect (UB _) = "ub"
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

||| An attribute dictionary between `opening` and `closing`, after a space,
||| if it has any entries. The generated printers write an op's `attr-dict`
||| with it.
export covering
dictionary : String -> String -> List NamedAttr -> String
dictionary opening closing [] = ""
dictionary opening closing as = " " ++ opening ++ commaSeparated (map entryText as) ++ closing

------------------------------------------------------------------------------
-- Locations
------------------------------------------------------------------------------

||| An operation's location: a source span, or an Idris name at one, MLIR's
||| `NameLoc`. Names reach MLIR only this way: as
||| debug information, which passes keep and diagnostics print, and never
||| as data a pass could compare.
public export
data Location = At Loc | Named Shown Loc

||| The span as MLIR writes a `FileLineColRange`, 1-based at both ends: one
||| point, a range on one line, or a range across lines. Code with no source
||| is `unknown`.
span : Loc -> String
span l =
  if l.file == "" then "unknown"
  else let sl = l.startLine + 1
           sc = l.startCol + 1
           el = l.endLine + 1
           ec = l.endCol + 1
           start = fastConcat [quoted l.file, ":", show sl, ":", show sc]
       in if sl == el && sc == ec then start
          else if sl == el then fastConcat [start, " to :", show ec]
          else fastConcat [start, " to ", show el, ":", show ec]

||| The location's text inside `loc(...)`. Code from a library whose
||| diagnostics are reported at the user's caller (the registry's *Report at
||| caller* column) is wrapped as `fused<"library">[...]`.
wrapped : Loc -> String -> String
wrapped l inner = "loc(" ++ (if inLibrary l then "fused<\"library\">[" ++ inner ++ "]" else inner) ++ ")"

||| A location as an attribute's text, `loc(...)`.
export
location : Location -> String
location (At l) = wrapped l (span l)
location (Named n l) = wrapped l (quoted (show n) ++ (if l.file == "" then "" else "(" ++ span l ++ ")"))

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

  ||| A region of one block: the block's arguments, and its ops.
  public export
  record Region where
    constructor MkRegion
    arguments : List Argument
    statements : List Statement

  ||| An op where it stands: the name of its results, if it has any, and
  ||| its location.
  public export
  record Statement where
    constructor MkStatement
    result : Maybe String
    op : Op
    at : Location

||| The names a statement binds its results to: its name for one result,
||| `name#i` for each of several, as an op's operands name them.
export
boundNames : Statement -> List String
boundNames s = case (s.result, s.op.results) of
  (Just r, [_]) => [r]
  (Just r, ts) => zipWith (\i, _ => r ++ "#" ++ show i) [0 .. length ts] ts
  (Nothing, _) => []

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

------------------------------------------------------------------------------
-- The generic form
------------------------------------------------------------------------------

indent : Nat -> String
indent d = replicate (2 * d) ' '

||| The name of an op's results, as its statement binds them.
named : Maybe String -> Nat -> String
named (Just r) (S (S k)) = r ++ ":" ++ show (S (S k)) ++ " = "
named (Just r) _ = r ++ " = "
named Nothing _ = ""

-- The text is written as pieces, each function's before the `rest` it is
-- given, and joined once: appending two strings copies both, so building
-- an op's text from its regions' texts would copy every statement once
-- per region around it, which grows with the square of the op.
mutual
  ||| An op in the generic form, its regions indented by `d`:
  ||| `"dialect.op"(operands) <{properties}> ({regions}) {attributes} : type`.
  covering
  opText : Nat -> Op -> List String -> List String
  opText d o rest =
    let start = fastConcat [quoted o.name, "(", commaSeparated (map (.name) o.operands), ")",
                            dictionary "<{" "}>" o.properties]
        end = fastConcat [dictionary "{" "}" o.attributes, " : ",
                          signature typeText (MkSignature (map (.type) o.operands) o.results)]
    in case o.regions of
         [] => start :: end :: rest
         rs => start :: " (" :: regionsText d rs (")" :: end :: rest)

  covering
  regionsText : Nat -> List Region -> List String -> List String
  regionsText d [] rest = rest
  regionsText d [r] rest = regionText d r rest
  regionsText d (r :: rs) rest = regionText d r (", " :: regionsText d rs rest)

  ||| A region's one block, labelled even when it has no arguments: the
  ||| generic form reads `{}` as a region of no blocks.
  covering
  regionText : Nat -> Region -> List String -> List String
  regionText d (MkRegion arguments statements) rest =
    fastConcat ["{\n", indent d, "^bb0", argumentsText arguments, ":\n"] ::
    statementsText (S d) statements (indent d :: "}" :: rest)

  covering
  argumentsText : List Argument -> String
  argumentsText [] = ""
  argumentsText as =
    "(" ++ commaSeparated (map (\a => a.value.name ++ ": " ++ typeText a.value.type) as) ++ ")"

  covering
  statementsText : Nat -> List Statement -> List String -> List String
  statementsText d [] rest = rest
  statementsText d (MkStatement result op _ :: ss) rest =
    indent d :: named result (length op.results) :: opText d op ("\n" :: statementsText d ss rest)

||| An op in MLIR's generic form without the locations of what it holds:
||| what the op is, wherever it stands. A content key hashes it.
export covering
genericForm : Op -> String
genericForm o = fastConcat (opText 0 o [])
