||| What `Emit` writes, and its one printer: MLIR's custom syntax for the
||| contract's dialects. An operation is a line, or a line that opens
||| regions, their contents, and the line that closes them; every operation
||| carries its location.
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

------------------------------------------------------------------------------
-- Types
------------------------------------------------------------------------------

||| The contract's types (IDR-TY-*). Data types hold
||| their mangled symbol.
public export
data MType = I Nat | F64
           | Data String | Boxed String
           | Fn (List MType) (List MType)
           | Str | Big | World | Erased

mutual
  export
  showType : MType -> String
  showType (I w) = "i" ++ show w
  showType F64 = "f64"
  showType (Data s) = "!idr.data<" ++ symbol s ++ ">"
  showType (Boxed s) = "!idr.box<" ++ symbol s ++ ">"
  showType (Fn as rs) = "!idr.fn<(" ++ showTypes as ++ ") -> (" ++ showTypes rs ++ ")>"
  showType Str = "!idr.str"
  showType Big = "!idr.big"
  showType World = "!idr.world"
  showType Erased = "!idr.erased"

  ||| Types separated by commas.
  export
  showTypes : List MType -> String
  showTypes [] = ""
  showTypes [t] = showType t
  showTypes (t :: ts) = showType t ++ ", " ++ showTypes ts

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

||| An operation as text: one line, or a line that opens regions (ending in
||| `{`), the operations inside, and the text that closes them. The region
||| headers of an `idr.match` (`case @C(%x: i64) {`) are nests without a
||| location of their own.
public export
data Op = Line String Location
        | Nest String (List Op) String (Maybe Location)

indent : Nat -> String
indent d = replicate (2 * d) ' '

mutual
  showOp : Nat -> Op -> String
  showOp d (Line text at) = indent d ++ text ++ " " ++ location at ++ "\n"
  showOp d (Nest opening body close at) =
    indent d ++ opening ++ "\n" ++ showOps (S d) body ++
    indent d ++ close ++ maybe "" (\l => " " ++ location l) at ++ "\n"

  showOps : Nat -> List Op -> String
  showOps d [] = ""
  showOps d (o :: os) = showOp d o ++ showOps d os

||| A module with its attributes.
export
showModule : String -> List Op -> String
showModule attrs ops = "module attributes {" ++ attrs ++ "} {\n" ++ showOps 1 ops ++ "}\n"
