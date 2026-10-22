-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Idris source, lexed well enough to tell code from comments, strings and
||| characters, for the source rules the tests check:
|||
|||     runtests --idris-lex code|strings <file>
|||
||| `code` prints each line of code, numbered as `<n>:<text>`, with comments
||| removed (`--` to the end of the line, `|||` documentation, nested
||| `{- -}` blocks), every string literal replaced by "" and every character
||| literal by 'c'. `strings` prints each string literal as
||| `<n>:<contents>`, escapes as written.
module Lex

import Data.List
import Data.String

%default covering

||| What is printed of a file.
public export
data Lexed = CodeLines | StringLiterals

export
lexedNamed : String -> Maybe Lexed
lexedNamed "code" = Just CodeLines
lexedNamed "strings" = Just StringLiterals
lexedNamed _ = Nothing

||| A character of an operator, which a `--` after it continues.
symbolic : Char -> Bool
symbolic c = elem c (unpack "!#$%&*+./<=>?@\\^|~:-")

||| A character of an operator, which continues a `--` before it into one.
continues : Char -> Bool
continues c = elem c (unpack "!#$%&*+./<=>?@\\^|~:")

identifier : Char -> Bool
identifier c = isAlphaNum c || c == '_'

||| One line read: its code with literals replaced, the strings it holds,
||| and the depth of nested block comments open at its end.
record Line where
  constructor MkLine
  code : List Char
  strings : List String
  depth : Nat

||| A string literal's contents after its opening quote, escapes as
||| written, and what follows its closing quote; an unclosed string runs to
||| the line's end.
stringBody : List Char -> (List Char, List Char)
stringBody [] = ([], [])
stringBody ('\\' :: c :: rest) = let (s, after) = stringBody rest in ('\\' :: c :: s, after)
stringBody ['\\'] = (['\\'], [])
stringBody ('"' :: rest) = ([], rest)
stringBody (c :: rest) = let (s, after) = stringBody rest in (c :: s, after)

||| What follows a character literal that starts here, after its opening
||| quote, when one does: `'\...'` up to the next quote, or `'x'`.
charAfter : List Char -> Maybe (List Char)
charAfter ('\\' :: rest) = case break (== '\'') rest of
  (_, '\'' :: after) => Just after
  _ => Nothing
charAfter (_ :: '\'' :: after) = Just after
charAfter _ = Nothing

||| A line lexed from the depth of block comments open before it. Literals
||| are read past by looking ahead, so the walk is covering: each step
||| consumes at least one character.
lexLine : (depth : Nat) -> List Char -> Line
lexLine depth cs = go depth Nothing cs [<] [<]
  where
    go : Nat -> Maybe Char -> List Char -> SnocList Char -> SnocList String -> Line
    go d _ [] out ss = MkLine (out <>> []) (ss <>> []) d
    go (S d) before ('{' :: '-' :: rest) out ss = go (S (S d)) (Just '-') rest out ss
    go (S d) before ('-' :: '}' :: rest) out ss = go d (Just '}') rest out ss
    go (S d) before (c :: rest) out ss = go (S d) (Just c) rest out ss
    go Z before ('{' :: '-' :: rest) out ss = go 1 (Just '-') rest out ss
    go Z before ('-' :: next@('-' :: rest)) out ss =
      if maybe True (not . symbolic) before && maybe True (not . continues) (head' rest)
         then MkLine (out <>> []) (ss <>> []) Z
         else go Z (Just '-') next (out :< '-') ss
    go Z before ('|' :: '|' :: '|' :: _) out ss = MkLine (out <>> []) (ss <>> []) Z
    go Z before ('"' :: rest) out ss =
      let (s, after) = stringBody rest in
      go Z (Just '"') after (out :< '"' :< '"') (ss :< pack s)
    go Z before ('\'' :: rest) out ss =
      case (maybe True (not . identifier) before, charAfter rest) of
        (True, Just after) => go Z (Just '\'') after (out :< '\'' :< 'c' :< '\'') ss
        _ => go Z (Just '\'') rest (out :< '\'') ss
    go Z before (c :: rest) out ss = go Z (Just c) rest (out :< c) ss

||| The file's text, lexed: the lines `runtests --idris-lex` prints.
export
lexed : Lexed -> String -> List String
lexed mode text = go Z 1 (lines text)
  where
    go : Nat -> Nat -> List String -> List String
    go _ _ [] = []
    go depth n (l :: ls) =
      let line = lexLine depth (unpack l)
          shown = case mode of
            CodeLines => if any (\c => c /= ' ' && c /= '\t') line.code then [show n ++ ":" ++ pack line.code] else []
            StringLiterals => map (\s => show n ++ ":" ++ s) line.strings
      in shown ++ go line.depth (S n) ls
