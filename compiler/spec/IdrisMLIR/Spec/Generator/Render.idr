-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| How the generator writes text: lines in order, each ended by one newline,
||| integers by one printer over their digits and strings escaped by one
||| escaper over ASCII, so both hosts write the same bytes. No host printer
||| (`show`) and no `Double` is ever used, and nothing is sorted: the order
||| of every output is the specification's declaration order.
module IdrisMLIR.Spec.Generator.Render

import IdrisMLIR.Spec.Core.Text

import Data.List
import Data.List1
import Data.Nat
import Data.Nat.Views

%default total

||| A file's text, line by line: every printer joins and indents lines as
||| lists, so the synonym unfolds wherever it is named.
public export
Lines : Type
Lines = List String

||| The text of `ls`, each line ended by a newline.
export
render : Lines -> String
render ls = concat (map (++ "\n") ls)

||| `ls`, each line indented by `n` spaces; an empty line stays empty.
export
indent : Nat -> Lines -> Lines
indent n = map pad
  where
    pad : String -> String
    pad "" = ""
    pad l = pack (replicate n ' ') ++ l

||| Binders after a name, each after a space; none, nothing.
export
spaced : List String -> String
spaced [] = ""
spaced bs = " " ++ concat (intersperse " " bs)

||| A C parameter list: `void` when there is none.
export
cParams : List String -> String
cParams [] = "void"
cParams ps = concat (intersperse ", " ps)

||| Pieces joined by a separator.
export
joinWith : String -> List String -> String
joinWith sep xs = concat (intersperse sep xs)

||| A digit's character.
export
digitChar : Nat -> Char
digitChar 0 = '0'
digitChar 1 = '1'
digitChar 2 = '2'
digitChar 3 = '3'
digitChar 4 = '4'
digitChar 5 = '5'
digitChar 6 = '6'
digitChar 7 = '7'
digitChar 8 = '8'
digitChar _ = '9'

||| Little-endian decimal digits doubled, with a carry in.
export
doubleDigits : Nat -> List Nat -> List Nat
doubleDigits c [] = if c == 0 then [] else [c]
doubleDigits c (d :: ds) =
  let x = d + d + c
  in if x >= 10 then minus x 10 :: doubleDigits 1 ds else x :: doubleDigits 0 ds

||| Little-endian decimal digits plus one.
export
incrementDigits : List Nat -> List Nat
incrementDigits [] = [1]
incrementDigits (d :: ds) = if d == 9 then 0 :: incrementDigits ds else S d :: ds

||| A natural's decimal digits, least significant first, by its binary
||| view: halving is the recursion, so it is structural and costs the
||| number's bits, never its value.
export
decimalDigits : (n : Nat) -> List Nat
decimalDigits n with (halfRec n)
  decimalDigits 0 | HalfRecZ = []
  decimalDigits (k + k) | HalfRecEven k rec = doubleDigits 0 (decimalDigits k | rec)
  decimalDigits (S (k + k)) | HalfRecOdd k rec = incrementDigits (doubleDigits 0 (decimalDigits k | rec))

||| A natural's decimal text.
export
decimal : Nat -> String
decimal n = case reverse (decimalDigits n) of
  [] => "0"
  ds => pack (map digitChar ds)

||| An integer's decimal text, its sign first.
export
integer : Integer -> String
integer i = if i < 0 then "-" ++ decimal (fromInteger (negate i)) else decimal (fromInteger i)

||| A hexadecimal digit's character.
export
hexChar : Nat -> Char
hexChar n = case n of
  10 => 'a'
  11 => 'b'
  12 => 'c'
  13 => 'd'
  14 => 'e'
  15 => 'f'
  _ => digitChar n

||| A natural below 2^64 as sixteen hexadecimal digits.
export
hex64 : Nat -> String
hex64 n = pack (go (the Nat 16) n [])
  where
    go : Nat -> Nat -> List Char -> List Char
    go Z _ acc = acc
    go (S k) m acc = go k (divNatNZ m 16 SIsNonZero) (hexChar (modNatNZ m 16 SIsNonZero) :: acc)

||| A string as a double-quoted literal in C++, TableGen and Idris alike:
||| the specification's text is printable ASCII, so a quote and a backslash
||| are the only characters escaped, and a newline is written as `\n`.
export
quoted : String -> String
quoted s = "\"" ++ pack (concatMap esc (unpack s)) ++ "\""
  where
    esc : Char -> List Char
    esc '"' = ['\\', '"']
    esc '\\' = ['\\', '\\']
    esc '\n' = ['\\', 'n']
    esc c = [c]

||| A comment block in C++ and TableGen, `// ` before each line of a
||| paragraph.
export
slashComment : List String -> Lines
slashComment = map (\l => if l == "" then "//" else "// " ++ l)

||| A comment block in a file the shell reads, `# ` before each line.
export
hashComment : List String -> Lines
hashComment = map (\l => if l == "" then "#" else "# " ++ l)

||| A doc comment in Idris, `||| ` before each line.
export
barComment : List String -> Lines
barComment = map (\l => if l == "" then "|||" else "||| " ++ l)

||| The lines of a description.
export
proseLines : Prose -> List String
proseLines p = case proseText p of
  "" => []
  t => forget (split (== '\n') t)
  where
    split : (Char -> Bool) -> String -> List1 String
    split f s = map pack (splitOn' f (unpack s))
      where
        splitOn' : (Char -> Bool) -> List Char -> List1 (List Char)
        splitOn' _ [] = [] ::: []
        splitOn' g (c :: cs) =
          let (first ::: rest) = splitOn' g cs
          in if g c then [] ::: (first :: rest) else (c :: first) ::: rest

||| The banner every generated file opens with, in the comment syntax of
||| its language: its licence, and that it is the specification's output.
export
banner : (comment : List String -> Lines) -> Lines
banner comment =
  comment
    [ "SPDX-License-Identifier: 0BSD"
    , "Copyright (c) 2026 Bjorn Pagen"
    , "Generated by specgen from the dialect's Idris specification"
    , "(compiler/spec/); `make check` regenerates it and fails on any"
    , "difference. Do not edit." ]
