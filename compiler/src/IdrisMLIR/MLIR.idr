||| MLIR's textual form, as `Emit` writes it. A type and an attribute are
||| data: the builtin ones the frontend uses are constructors here, and each
||| dialect's are the constructors of the sums generated from the dialect's
||| ODS (IdrisMLIR.Syntax.*), which this module's types and attributes hold;
||| each is written in the syntax ODS declares for it, which the dialect's
||| generated C++ parser reads. An op is written in MLIR's generic form,
||| which every op has and which ODS says whole: its name, operands,
||| inherent attributes (its properties), regions, discardable attributes,
||| types and location; the generated builders make them
||| (IdrisMLIR.Dialect.*). An op's custom syntax is C++ (custom directives,
||| hand-written parsers), which nothing generated from ODS can know.
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
  ||| A type: a builtin one, or a dialect's, which holds types of its own.
  ||| A signless integer type, `i64`, is read as an op that reads it says;
  ||| an array of elements of a type is a memref of as many dimensions as
  ||| it has, each dynamic: of none, the memref of one element.
  public export
  data MlirType
    = IntegerType Nat
    | F64Type
    | IndexType
    | NoneType
    | MemRefType Nat MlirType
    | FunctionType (Signature MlirType)
    | Idr (IdrType MlirType)

||| A type's text. A dialect's type writes the types it holds by this
||| function, so each is a part of the type it is in.
export
typeText : MlirType -> String
typeText (IntegerType w) = "i" ++ show w
typeText F64Type = "f64"
typeText IndexType = "index"
typeText NoneType = "none"
typeText (MemRefType dynamic e) = "memref<" ++ concat (replicate dynamic "?x") ++ typeText e ++ ">"
typeText (FunctionType s) = signature (\v => typeText (assert_smaller s v)) s
typeText (Idr x) = idrTypeText (\v => typeText (assert_smaller x v)) x

------------------------------------------------------------------------------
-- Attributes
------------------------------------------------------------------------------

namespace MlirAttr
  ||| An attribute: a builtin one, or a dialect's, which holds types and
  ||| attributes of its own. An integer is of an integer type or of `index`,
  ||| a float of a float type; a string is written as its UTF-8 bytes; the
  ||| dense array of `i32` is the number of values in each group of an op's
  ||| operands or results, where more than one group may vary in length.
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
    | Idr (IdrAttr MlirType MlirAttr)
    | Arith (ArithAttr MlirType MlirAttr)
    | UB (UBAttr MlirType MlirAttr)

||| An attribute's text, each attribute it holds written by this function.
export
attrText : MlirAttr -> String
attrText UnitAttr = "unit"
attrText (BoolAttr b) = if b then "true" else "false"
attrText (IntegerAttr n t) = show n ++ " : " ++ typeText t
attrText (FloatAttr d t) = floatLiteral d ++ " : " ++ typeText t
attrText (StringAttr s) = utf8 s
attrText (SymbolRefAttr r) = symbolRef r
attrText (TypeAttr t) = typeText t
attrText (ArrayAttr as) = array (\v => attrText (assert_smaller as v)) as
attrText (DenseI32ArrayAttr []) = "array<i32>"
attrText (DenseI32ArrayAttr ns) = "array<i32: " ++ commaSeparated (map show ns) ++ ">"
attrText (Idr x) = idrAttrText typeText (\v => attrText (assert_smaller x v)) x
attrText (Arith x) = arithAttrText typeText (\v => attrText (assert_smaller x v)) x
attrText (UB x) = ubAttrText typeText (\v => attrText (assert_smaller x v)) x

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
-- Locations
------------------------------------------------------------------------------

||| An operation's location: a source span, or an Idris name at one, MLIR's
||| `NameLoc`. Names reach MLIR only this way: as
||| debug information, which passes keep and diagnostics print, and never
||| as data a pass could compare.
public export
data Location = At Loc | Named Shown Loc

||| The file and the 1-based line and column of the start.
span : Loc -> String
span l = if l.file == "" then "unknown"
         else quoted l.file ++ ":" ++ show (l.startLine + 1) ++ ":" ++ show (l.startCol + 1)

||| The location's text inside `loc(...)`. Code from a library whose
||| diagnostics are reported at the user's caller (the registry's *Report at
||| caller* column) is wrapped as `fused<"library">[...]`.
wrapped : Loc -> String -> String
wrapped l inner = "loc(" ++ (if inLibrary l then "fused<\"library\">[" ++ inner ++ "]" else inner) ++ ")"

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
    arguments : List Value
    statements : List Statement

  ||| An op where it stands: the name of its results, if it has any, and
  ||| its location.
  public export
  record Statement where
    constructor MkStatement
    result : Maybe String
    op : Op
    at : Location

indent : Nat -> String
indent d = replicate (2 * d) ' '

||| An attribute dictionary between `opening` and `closing`, if it has any
||| entries; a unit attribute is its name alone.
dictionary : String -> String -> List NamedAttr -> String
dictionary opening closing [] = ""
dictionary opening closing as = " " ++ opening ++ commaSeparated (map entry as) ++ closing
  where
    entry : NamedAttr -> String
    entry (name, UnitAttr) = name
    entry (name, a) = name ++ " = " ++ attrText a

||| A block argument or an operand with its type: `%3: i64`.
typed : Value -> String
typed v = v.name ++ ": " ++ typeText v.type

||| The name of an op's results, as its statement binds them.
named : Maybe String -> Nat -> String
named (Just r) (S (S k)) = r ++ ":" ++ show (S (S k)) ++ " = "
named (Just r) _ = r ++ " = "
named Nothing _ = ""

-- The text is written as pieces, each function's before the `rest` it is
-- given, and joined once (showModule): appending two strings copies both,
-- so building an op's text from its regions' texts would copy every
-- statement once per region around it and once per statement after it in
-- its block, which grows with the square of the module.
mutual
  ||| `"dialect.op"(operands) <{properties}> (regions) {attributes} : type`,
  ||| its regions indented by `d`.
  opText : Nat -> Op -> List String -> List String
  opText d (MkOp name operands properties regions attributes results) rest =
    let after = dictionary "{" "}" attributes :: " : " ::
                signature typeText (MkSignature (map (.type) operands) results) :: rest
    in quoted name :: "(" :: commaSeparated (map (.name) operands) :: ")" ::
       dictionary "<{" "}>" properties ::
       (case regions of
          [] => after
          _ => " (" :: regionsText d regions (")" :: after))

  regionsText : Nat -> List Region -> List String -> List String
  regionsText d [] rest = rest
  regionsText d [r] rest = regionText d r rest
  regionsText d (r :: rs) rest = regionText d r (", " :: regionsText d rs rest)

  ||| The block is labelled even when it has no arguments: the generic form
  ||| reads `{}` as a region of no blocks, and a block of no ops is one
  ||| only by its label.
  regionText : Nat -> Region -> List String -> List String
  regionText d (MkRegion arguments statements) rest =
    "{\n" :: indent d :: "^bb0" ::
    (case arguments of
       [] => ""
       _ => "(" ++ commaSeparated (map typed arguments) ++ ")") :: ":\n" ::
    statementsText (S d) statements (indent d :: "}" :: rest)

  statementsText : Nat -> List Statement -> List String -> List String
  statementsText d [] rest = rest
  statementsText d (s :: ss) rest = statementText d s (statementsText d ss rest)

  statementText : Nat -> Statement -> List String -> List String
  statementText d (MkStatement result op at) rest =
    indent d :: named result (length op.results) ::
    opText d op (" " :: location at :: "\n" :: rest)

||| A module: its op, in the generic form too, with what it holds.
export
showModule : Op -> String
showModule m = fastConcat (opText 0 m ["\n"])
