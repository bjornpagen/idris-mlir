||| MLIR's textual form, as `Emit` writes it. A type or an attribute is its
||| text: the builtin ones are made here, and each dialect's by the module
||| generated from the dialect's ODS (IdrisMLIR.Dialect.*), which also
||| builds its ops. An op is written in MLIR's generic form, which every op
||| has and which ODS says whole: its name, operands, inherent attributes
||| (its properties), regions, discardable attributes, types and location.
||| An op's custom syntax is C++ (custom directives, hand-written parsers),
||| which nothing generated from ODS can know.
module IdrisMLIR.MLIR

import IdrisMLIR.Ids
import IdrisMLIR.Loc

import Data.List
import Data.Maybe
import Data.String

%default total

------------------------------------------------------------------------------
-- Names
------------------------------------------------------------------------------

||| Injective mangling into MLIR symbol text. Characters outside
||| `[A-Za-z0-9_.]`, `$` included, are written `$<code point>$`.
export
mangle : String -> String
mangle s = concatMap escape (unpack s)
  where
    escape : Char -> String
    escape c = if isAlphaNum c || c == '_' || c == '.'
                  then singleton c
                  else "$" ++ show (ord c) ++ "$"

hex : Int -> String
hex n = let digits = unpack "0123456789ABCDEF" in
        pack [ fromMaybe '0' (getAt (cast (n `div` 16)) digits)
             , fromMaybe '0' (getAt (cast (n `mod` 16)) digits) ]

||| A string literal with MLIR's escapes, for text that is ASCII.
export
quoted : String -> String
quoted s = "\"" ++ concatMap esc (unpack s) ++ "\""
  where
    esc : Char -> String
    esc '"' = "\\\""
    esc '\\' = "\\\\"
    esc c = if ord c < 32 || ord c == 127 then "\\" ++ hex (ord c) else singleton c

||| A string as the UTF-8 bytes of a string attribute.
export
utf8 : String -> String
utf8 s = "\"" ++ concatMap enc (unpack s) ++ "\""
  where
    byte : Int -> String
    byte b = if b >= 32 && b < 127 && b /= 34 && b /= 92 then singleton (chr b) else "\\" ++ hex b
    enc : Char -> String
    enc c =
      let n = ord c in
      if n < 0x80 then byte n
      else if n < 0x800 then byte (0xC0 + n `div` 64) ++ byte (0x80 + n `mod` 64)
      else if n < 0x10000 then byte (0xE0 + n `div` 4096) ++ byte (0x80 + (n `div` 64) `mod` 64)
                               ++ byte (0x80 + n `mod` 64)
      else byte (0xF0 + n `div` 262144) ++ byte (0x80 + (n `div` 4096) `mod` 64)
           ++ byte (0x80 + (n `div` 64) `mod` 64) ++ byte (0x80 + n `mod` 64)

||| A symbol reference, `@name`, for mangled text. A name that is not an
||| MLIR bare identifier (one starting with a digit or `$`) is quoted.
export
symbol : String -> String
symbol m = case unpack m of
  (c :: _) => if isAlpha c || c == '_' then "@" ++ m else "@" ++ quoted m
  [] => "@\"\""

||| Texts separated by commas.
export
commaSeparated : List String -> String
commaSeparated = joinBy ", "

------------------------------------------------------------------------------
-- Literals
------------------------------------------------------------------------------

||| An exact MLIR float literal: the shortest decimal that reads back as the
||| same double (the compiler runs on Chez Scheme, whose `number->string`
||| prints that), with a point as MLIR requires, and hexadecimal bits for
||| NaN and the infinities.
export
floatLiteral : Double -> String
floatLiteral d =
  if d /= d then "0x7FF8000000000000"
  else if d > 1.7976931348623157e308 then "0x7FF0000000000000"
  else if d < -1.7976931348623157e308 then "0xFFF0000000000000"
  else decimal (prim__cast_DoubleString d)
  where
    -- Chez marks subnormals with a precision suffix, `5e-324|1`.
    decimal : String -> String
    decimal s =
      let s' = fst (break (== '|') s)
          (mant, ex) = break (== 'e') s'
          mant' = if any (== '.') (unpack mant) then mant else mant ++ ".0"
      in mant' ++ ex

||| The two's complement bit pattern of `n` in `w` bits, read as signed:
||| how an integer attribute of that width is written.
export
twos : Nat -> Integer -> Integer
twos w n = let m = pow w
               r = n `mod` m
               r' = if r < 0 then r + m else r
           in if r' >= m `div` 2 then r' - m else r'
  where
    pow : Nat -> Integer
    pow Z = 1
    pow (S k) = 2 * pow k

------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------

||| A type, by its text.
public export
record MlirType where
  constructor MkMlirType
  text : String

||| A signless integer type, `i64`: an op that reads an integer says how.
export
integerType : Nat -> MlirType
integerType w = MkMlirType ("i" ++ show w)

export
f64Type : MlirType
f64Type = MkMlirType "f64"

export
indexType : MlirType
indexType = MkMlirType "index"

||| An array of elements of a type: a memref of one dynamic dimension.
export
memRefType : MlirType -> MlirType
memRefType e = MkMlirType ("memref<?x" ++ e.text ++ ">")

||| A function type, `(i64, !idr.str) -> i64`: its results in parentheses,
||| unless it has one that is not itself a function type.
export
functionType : List MlirType -> List MlirType -> MlirType
functionType ins outs =
  MkMlirType ("(" ++ commaSeparated (map (.text) ins) ++ ") -> " ++ results outs)
  where
    results : List MlirType -> String
    results [r] = if isPrefixOf "(" r.text then "(" ++ r.text ++ ")" else r.text
    results rs = "(" ++ commaSeparated (map (.text) rs) ++ ")"

------------------------------------------------------------------------------
-- Attributes
------------------------------------------------------------------------------

||| An attribute, by its text.
public export
record MlirAttr where
  constructor MkMlirAttr
  text : String

||| An attribute of an op's: its name, and itself.
public export
NamedAttr : Type
NamedAttr = (String, MlirAttr)

export
unitAttr : MlirAttr
unitAttr = MkMlirAttr "unit"

export
boolAttr : Bool -> MlirAttr
boolAttr b = MkMlirAttr (if b then "true" else "false")

||| An integer of an integer type, or of `index`.
export
integerAttr : Integer -> MlirType -> MlirAttr
integerAttr n t = MkMlirAttr (show n ++ " : " ++ t.text)

||| A float of a float type.
export
floatAttr : Double -> MlirType -> MlirAttr
floatAttr d t = MkMlirAttr (floatLiteral d ++ " : " ++ t.text)

||| A string, as its UTF-8 bytes.
export
stringAttr : String -> MlirAttr
stringAttr s = MkMlirAttr (utf8 s)

||| A symbol, by its mangled name.
export
flatSymbolRefAttr : String -> MlirAttr
flatSymbolRefAttr m = MkMlirAttr (symbol m)

||| A symbol nested in others, by the mangled name of each: `@T::@C`.
export
symbolRefAttr : List String -> MlirAttr
symbolRefAttr ms = MkMlirAttr (joinBy "::" (map symbol ms))

export
typeAttr : MlirType -> MlirAttr
typeAttr t = MkMlirAttr t.text

export
arrayAttr : List MlirAttr -> MlirAttr
arrayAttr as = MkMlirAttr ("[" ++ commaSeparated (map (.text) as) ++ "]")

export
typeArrayAttr : List MlirType -> MlirAttr
typeArrayAttr ts = arrayAttr (map typeAttr ts)

||| The number of values in each group of an op's operands or results, where
||| more than one group may vary in length.
export
segmentSizes : List Nat -> MlirAttr
segmentSizes [] = MkMlirAttr "array<i32>"
segmentSizes ns = MkMlirAttr ("array<i32: " ++ commaSeparated (map show ns) ++ ">")

||| A unit attribute, there when `set`.
export
unitIf : String -> Bool -> List NamedAttr
unitIf name set = if set then [(name, unitAttr)] else []

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
    entry (name, a) = if a.text == "unit" then name else name ++ " = " ++ a.text

||| A block argument or an operand with its type: `%3: i64`.
typed : Value -> String
typed v = v.name ++ ": " ++ v.type.text

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
                (functionType (map (.type) operands) results).text :: rest
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
