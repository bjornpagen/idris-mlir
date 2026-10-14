-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| MLIR's textual form, as `Emit` writes it. A type and an attribute are
||| data: the builtin ones the frontend uses are constructors here, and each
||| dialect's are the constructors of the sums generated from the dialect's
||| ODS (IdrisMLIR.Syntax.*), which this module's types and attributes hold;
||| each is written in the syntax ODS declares for it, which the dialect's
||| generated C++ parser reads. An op is written in its dialect's declarative
||| format where the dialect's generated printer has one for it (a
||| `Format`), its regions and location appended here; otherwise in MLIR's
||| generic form, which every op has and which ODS says whole: its name,
||| operands, inherent attributes (its properties), regions, discardable
||| attributes, types and location. The generated builders make the ops
||| (IdrisMLIR.Dialect.*). An op's custom syntax is C++ (custom directives,
||| hand-written parsers), which nothing generated from ODS can know, so
||| such an op is written generic.
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
||| function, so each is a part of the type it is in: a recursion through a
||| function the dialect's syntax is given, which the totality checker does
||| not follow, so this and what prints with it are covering.
export covering
typeText : MlirType -> String
typeText (IntegerType w) = "i" ++ show w
typeText F64Type = "f64"
typeText IndexType = "index"
typeText NoneType = "none"
typeText (MemRefType dynamic e) = "memref<" ++ concat (replicate dynamic "?x") ++ typeText e ++ ">"
typeText (FunctionType s) = signature typeText s
typeText (Idr x) = idrTypeText typeText x

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
export covering
attrText : MlirAttr -> String
attrText UnitAttr = "unit"
attrText (BoolAttr b) = if b then "true" else "false"
attrText (IntegerAttr n t) = show n ++ " : " ++ typeText t
attrText (FloatAttr d t) = floatLiteral d ++ " : " ++ typeText t
attrText (StringAttr s) = utf8 s
attrText (SymbolRefAttr r) = symbolRef r
attrText (TypeAttr t) = typeText t
attrText (ArrayAttr as) = array attrText as
attrText (DenseI32ArrayAttr []) = "array<i32>"
attrText (DenseI32ArrayAttr ns) = "array<i32: " ++ commaSeparated (map show ns) ++ ">"
attrText (Idr x) = idrAttrText typeText attrText x
attrText (Arith x) = arithAttrText typeText attrText x
attrText (UB x) = ubAttrText typeText attrText x

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

||| How an op's dialect writes it: its text in the dialect's declarative
||| format up to its regions, which the format puts last, or Nothing for an
||| op written generic.
public export
Format : Type
Format = Op -> Maybe String

indent : Nat -> String
indent d = replicate (2 * d) ' '

||| An attribute dictionary between `opening` and `closing`, after a space,
||| if it has any entries; a unit attribute is its name alone. The generated
||| printers write an op's `attr-dict` with it.
export covering
dictionary : String -> String -> List NamedAttr -> String
dictionary opening closing [] = ""
dictionary opening closing as = " " ++ opening ++ commaSeparated (map entry as) ++ closing
  where
    entry : NamedAttr -> String
    entry (name, UnitAttr) = name
    entry (name, a) = name ++ " = " ++ attrText a

||| A block argument with its type and location: `%3: i64 loc(...)`, as
||| MLIR's own printer writes a block argument's location.
covering
argumentText : Argument -> String
argumentText a = fastConcat [a.value.name, ": ", typeText a.value.type, " ", location a.at]

||| The name of an op's results, as its statement binds them.
named : Maybe String -> Nat -> String
named (Just r) (S (S k)) = r ++ ":" ++ show (S (S k)) ++ " = "
named (Just r) _ = r ++ " = "
named Nothing _ = ""

||| What an op's text puts around its regions: before the first, between
||| two, and after the last. In the declarative form the head is the
||| dialect's and each region follows after a space; in the generic form
||| `"dialect.op"(operands) <{properties}> (` comes before them and
||| `) {attributes} : type` after.
covering
frame : Format -> Op -> (String, String, String)
frame format o = case format o of
  Just declared => case o.regions of
    [] => (declared, "", "")
    _ => (declared ++ " ", " ", "")
  Nothing =>
    let start = fastConcat [quoted o.name, "(", commaSeparated (map (.name) o.operands), ")",
                            dictionary "<{" "}>" o.properties]
        end = fastConcat [dictionary "{" "}" o.attributes, " : ",
                          signature typeText (MkSignature (map (.type) o.operands) o.results)]
    in case o.regions of
         [] => (start ++ end, "", "")
         _ => (start ++ " (", ", ", ")" ++ end)

||| The opening of a region's one block, indented by `d`. The block is
||| labelled even when it has no arguments: the generic form reads `{}` as
||| a region of no blocks, and a block of no ops is one only by its label.
covering
blockOpening : Nat -> List Argument -> String
blockOpening d [] = fastConcat ["{\n", indent d, "^bb0:\n"]
blockOpening d arguments =
  fastConcat ["{\n", indent d, "^bb0(", commaSeparated (map argumentText arguments), "):\n"]

-- The text is written as pieces, each function's before the `rest` it is
-- given, and joined once per top-level op: appending two strings copies
-- both, so building an op's text from its regions' texts would copy every
-- statement once per region around it and once per statement after it in
-- its block, which grows with the square of the op.
mutual
  ||| An op, its regions indented by `d`.
  covering
  opText : Nat -> Format -> Op -> List String -> List String
  opText d format o rest =
    let (before, between, after) = frame format o
    in before :: regionsText d format between o.regions (after :: rest)

  covering
  regionsText : Nat -> Format -> String -> List Region -> List String -> List String
  regionsText d format between [] rest = rest
  regionsText d format between [r] rest = regionText d format r rest
  regionsText d format between (r :: rs) rest =
    regionText d format r (between :: regionsText d format between rs rest)

  covering
  regionText : Nat -> Format -> Region -> List String -> List String
  regionText d format (MkRegion arguments statements) rest =
    blockOpening d arguments ::
    statementsText (S d) format statements (indent d :: "}" :: rest)

  covering
  statementsText : Nat -> Format -> List Statement -> List String -> List String
  statementsText d format [] rest = rest
  statementsText d format (s :: ss) rest = statementText d format s (statementsText d format ss rest)

  covering
  statementText : Nat -> Format -> Statement -> List String -> List String
  statementText d format (MkStatement result op at) rest =
    indent d :: named result (length op.results) ::
    opText d format op (" " :: location at :: "\n" :: rest)

||| A module written whole: its op, with what it holds, at its location.
||| MLIR reads a location after the top-level op as it reads one after any
||| other, and the module keeps it: a diagnostic about the whole module is
||| reported there.
export covering
showModule : Format -> Location -> Op -> String
showModule format at m = fastConcat (opText 0 format m [" ", location at, "\n"])

||| A module written one top-level op at a time, so that the text of the
||| whole module is never held: the text before the statements of its one
||| region and the text after them, with the module's location. The
||| statements of `m`'s region are not written; the caller writes each
||| between the two by `topLevel`.
export covering
moduleText : Format -> Location -> Op -> (String, String)
moduleText format at m =
  let (before, _, after) = frame format m
  in (before ++ blockOpening 0 [], fastConcat ["}", after, " ", location at, "\n"])

||| A top-level op of a module written by `moduleText`, with its location.
export covering
topLevel : Format -> Statement -> String
topLevel format s = fastConcat (statementText 1 format s [])
