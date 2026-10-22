-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The pieces of MLIR's text that every printer shares: names, string and
||| number literals, symbol references, function signatures, lists and
||| locations. A leaf but for the one UTF-8 encoder (the specification's) and the
||| source locations (`Loc`), so that the generated syntax of each dialect
||| (IdrisMLIR.Syntax.*) and the builtin types and attributes
||| (IdrisMLIR.MLIR) write them alike.
module IdrisMLIR.MLIR.Text

import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Spec.Core.Text

import Data.List
import Data.Maybe
import Data.String

%default total

------------------------------------------------------------------------------
-- Names
------------------------------------------------------------------------------

||| A hexadecimal digit, `0` to `F`, of a number below 16.
hexDigit : Int -> Char
hexDigit d = chr (if d < 10 then ord '0' + d else ord 'A' + (d - 10))

||| The escape of a byte, `\XX`, before the characters `rest`.
escape : Int -> List Char -> List Char
escape n rest = '\\' :: hexDigit (n `div` 16) :: hexDigit (n `mod` 16) :: rest

||| A string literal with MLIR's escapes, for text that is ASCII. Its
||| characters are made in one pass and packed once.
export
quoted : String -> String
quoted s = pack ('"' :: foldr esc ['"'] (unpack s))
  where
    esc : Char -> List Char -> List Char
    esc '"' rest = '\\' :: '"' :: rest
    esc '\\' rest = '\\' :: '\\' :: rest
    esc c rest = if ord c < 32 || ord c == 127 then escape (ord c) rest else c :: rest

||| A string as the UTF-8 bytes of a string attribute: each byte of its
||| encoding printable as itself but a quote and a backslash, every other
||| escaped. Its characters are made in one pass and packed once.
export
utf8Literal : String -> String
utf8Literal s = pack ('"' :: foldr byte ['"'] (IdrisMLIR.Spec.Core.Text.utf8 s))
  where
    byte : Bits8 -> List Char -> List Char
    byte b rest = let n = cast {to = Int} b in
                  if n >= 32 && n < 127 && n /= 34 && n /= 92 then chr n :: rest else escape n rest

||| A symbol reference, `@name`: the name itself when it is an MLIR bare
||| identifier (a letter or `_`, then letters, digits, `_`, `$` and `.`),
||| else the string literal of its UTF-8 bytes, as a string attribute writes
||| it, so that `@"…"` in a reference and `sym_name = "…"` in the
||| declaration name the same symbol.
export
symbol : String -> String
symbol name = if bare (unpack name) then "@" ++ name else "@" ++ utf8Literal name
  where
    rest : Char -> Bool
    rest c = isAlphaNum c || c == '_' || c == '$' || c == '.'
    bare : List Char -> Bool
    bare (c :: cs) = (isAlpha c || c == '_') && all rest cs
    bare [] = False

------------------------------------------------------------------------------
-- Lists
------------------------------------------------------------------------------

||| Texts separated by `sep`, joined once (`joinBy` appends each to all
||| before it).
export
separated : String -> List String -> String
separated sep xs = fastConcat (intersperse sep xs)

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

||| A symbol nested in others, by the name of each: `@T::@C` is
||| `MkSymbolRef "T" ["C"]`, and a flat one has no nested names.
public export
record SymbolRef where
  constructor MkSymbolRef
  root : String
  nested : List String

export
symbolRef : SymbolRef -> String
symbolRef r = separated "::" (map symbol (r.root :: r.nested))

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

||| An operation's location: a source span; an Idris name at one, MLIR's
||| `NameLoc`; or a binder of a definition's, its name at its span fused
||| with its identity (`#idr.binder`: the definition's symbol and the
||| binder's number in it), the one key a check of a binder's quantity
||| reads. Names reach MLIR only this way: as debug information, which
||| passes keep and diagnostics print, and never as data a pass could
||| compare.
public export
data Location = At Loc | Named Shown Loc | Binder Shown Loc String Nat

||| A span of a file as MLIR writes a `FileLineColRange`, 1-based at both
||| ends: one point, a range on one line, or a range across lines.
fileSpan : String -> Span -> String
fileSpan file s =
  let sl = s.startLine + 1
      sc = s.startCol + 1
      el = s.endLine + 1
      ec = s.endCol + 1
      start = fastConcat [quoted file, ":", show sl, ":", show sc]
  in if sl == el && sc == ec then start
     else if sl == el then fastConcat [start, " to :", show ec]
     else fastConcat [start, " to ", show el, ":", show ec]

||| Where code is, as MLIR writes it: a span of a file; or, in no file (a
||| module whose source is not installed, generated code), `unknown`, which
||| is what a location names no file by.
placeText : Located -> Maybe String
placeText (InModule _ (Just file) s) = Just (fileSpan file s)
placeText (InPackage file s) = Just (fileSpan file s)
placeText (InModule _ Nothing _) = Nothing
placeText Unlocated = Nothing

||| A location's text inside `loc(...)`. Code from a library whose
||| diagnostics are reported at the user's caller (the registry's *Report
||| at caller* column) is fused with the metadata `"library"`.
wrapped : Loc -> String -> String
wrapped l inner = "loc(" ++ (if inLibrary l then "fused<\"library\">[" ++ inner ++ "]" else inner) ++ ")"

||| A location as an attribute's text, `loc(...)`, as MLIR writes it.
export
location : Location -> String
location (At l) = wrapped l (fromMaybe "unknown" (placeText l.located))
location (Named n l) = wrapped l (quoted (show n) ++ maybe "" (\p => "(" ++ p ++ ")") (placeText l.located))
location (Binder n l _ _) = location (Named n l)
