||| The pieces of MLIR's text that every printer shares: names, string and
||| number literals, symbol references, function signatures and lists. A
||| leaf, so that the generated syntax of each dialect (IdrisMLIR.Syntax.*)
||| and the builtin types and attributes (IdrisMLIR.MLIR) write them alike.
module IdrisMLIR.MLIR.Text

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
-- Lists
------------------------------------------------------------------------------

||| Texts separated by `sep`.
export
separated : String -> List String -> String
separated sep = joinBy sep

||| Texts separated by commas.
export
commaSeparated : List String -> String
commaSeparated = separated ", "

||| A list, `[a, b]`, each element written by `a`.
export
array : (at -> String) -> List at -> String
array a xs = fastConcat ["[", commaSeparated (map a xs), "]"]

------------------------------------------------------------------------------
-- Symbol references and signatures
------------------------------------------------------------------------------

||| A symbol nested in others, by the mangled name of each: `@T::@C` is
||| `MkSymbolRef "T" ["C"]`, and a flat one has no nested names.
public export
record SymbolRef where
  constructor MkSymbolRef
  root : String
  nested : List String

export
symbolRef : SymbolRef -> String
symbolRef r = joinBy "::" (map symbol (r.root :: r.nested))

||| What a function takes and gives: a builtin function type's, or a
||| closure's.
public export
record Signature ty where
  constructor MkSignature
  inputs : List ty
  results : List ty

||| `(A...) -> (R...)`, the inputs and results written by `t`: the results in
||| parentheses always, which MLIR reads for one result as for several.
export
signature : (ty -> String) -> Signature ty -> String
signature t s =
  fastConcat ["(", commaSeparated (map t s.inputs), ") -> (", commaSeparated (map t s.results), ")"]

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
