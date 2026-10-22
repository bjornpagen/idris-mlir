-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
||| Lexers: recognisers of tokens, and tokenizers that make tokens of what
||| they read.
|||
||| The API, for a lexer written over it:
|||
||| - `Recognise c` reads characters, at least one when `c` is `True`;
|||   `Lexer` is `Recognise True`.
||| - Sequence: `<+>`, which consumes if either part does; `andThen`, a
|||   lexer followed by a recogniser made only once the lexer has matched,
|||   which may therefore be the recogniser being defined. A recogniser
|||   that names itself does so after `andThen`.
||| - Choice: `<|>`, `opt`, `choice`, `choiceMap`; lookahead: `expect`,
|||   `reject`; and `fail`, `empty`, `eof`.
||| - Characters and runs of them: `pred`, `any`, `is`, `isNot`, `non`,
|||   `exact`, `some`, `many`, `someUntil`, `manyUntil`, `digits`,
|||   `alphaNum`, `space`, `newline`, `symbol`, `surround`, `escape`, and
|||   the literals.
||| - Tokenizers: `match`, `compose` with the `Group` its begin's text
|||   opens, `<|>`, `tokenRules`, `tokenKinds`; run by `lex` and `lexTo`,
|||   which give the tokens and why and where tokenizing stopped.
module Libraries.Text.Lexer

import Data.Bool
import Data.List

import public Libraries.Text.Lexer.Core
import public Libraries.Text.Lexer.Tokenizer
import public Libraries.Text.Token

%default total

||| Any character.
||| /./
export
any : Lexer
any = pred (const True)

||| The lexer, or else no input.
||| /`l`?/
export
opt : (l : Lexer) -> Recognise False
opt l = l <|> empty

||| Any character, where the lexer would not match.
||| /(?!`l`)./
export
non : (l : Lexer) -> Lexer
non l = reject l <+> any

||| The recogniser a function makes of each element, the first that
||| matches. Consumes if each does. Fails if there are none.
export
choiceMap : {0 c : Bool} -> Foldable t => (a -> Recognise c) -> t a -> Recognise c
choiceMap f xs = foldr (\x, acc => rewrite sym (andSameNeutral c) in f x <|> acc) fail xs

||| The first recogniser that matches. Consumes if each does. Fails if there
||| are none.
export
choice : {0 c : Bool} -> Foldable t => t (Recognise c) -> Recognise c
choice = choiceMap id

||| The character given.
||| /[`x`]/
export
is : (x : Char) -> Lexer
is x = pred (== x)

||| Any character but the one given.
||| /[\^`x`]/
export
isNot : (x : Char) -> Lexer
isNot x = pred (/= x)

-- The character given, either case.
like : (x : Char) -> Lexer
like x = pred (\y => toUpper x == toUpper y)

-- A lexer of the first character, then each of the rest.
spell : (Char -> Lexer) -> Lexer -> List Char -> Lexer
spell one first [] = first
spell one first (x :: xs) = spell one (first <+> one x) xs

||| The string given. Fails if the string is empty.
||| /`str`/
export
exact : (str : String) -> Lexer
exact str = case unpack str of
                 [] => fail
                 (x :: xs) => spell is (is x) xs

-- The string given, either case. Fails if the string is empty.
approx : (str : String) -> Lexer
approx str = case unpack str of
                  [] => fail
                  (x :: xs) => spell like (like x) xs

mutual
  ||| The lexer, once or more.
  ||| /`l`+/
  export
  some : Lexer -> Lexer
  some l = l `andThen` many l

  ||| The lexer, none or more times.
  ||| /`l`\*/
  export
  many : Lexer -> Recognise False
  many l = opt (some l)

||| The lexer once or more, each where `stopBefore` would not match, which
||| is not read.
||| /((?!`stopBefore`)`l`)\+/
export
someUntil : (stopBefore : Lexer) -> (l : Lexer) -> Lexer
someUntil stopBefore l = some (reject stopBefore <+> l)

||| The lexer none or more times, each where `stopBefore` would not match,
||| which is not read.
||| /((?!`stopBefore`)`l`)\*/
export
manyUntil : (stopBefore : Lexer) -> (l : Lexer) -> Recognise False
manyUntil stopBefore l = many (reject stopBefore <+> l)

-- The lexer none or more times until `stopAfter` matches, which is read.
manyThen : (stopAfter : Lexer) -> (l : Lexer) -> Lexer
manyThen stopAfter l = manyUntil stopAfter l <+> stopAfter

-- One decimal digit.
digit : Lexer
digit = pred isDigit

||| One or more decimal digits.
||| /[0-9]+/
export
digits : Lexer
digits = some digit

-- One or more binary digits.
binDigits : Lexer
binDigits = some (pred (\c => c == '0' || c == '1'))

-- One or more hexadecimal digits.
hexDigits : Lexer
hexDigits = some (pred isHexDigit)

-- One or more octal digits.
octDigits : Lexer
octDigits = some (pred isOctDigit)

||| One letter or digit.
||| /[A-Za-z0-9]/
export
alphaNum : Lexer
alphaNum = pred isAlphaNum

||| One whitespace character.
||| /\\s/
export
space : Lexer
space = pred isSpace

||| One newline: CRLF, CR or LF.
||| /\\r\\n|[\\r\\n]/
export
newline : Lexer
newline = exact "\r\n" <|> is '\r' <|> is '\n'

||| One character neither whitespace, a letter nor a digit.
||| /[\^\\sA-Za-z0-9]/
export
symbol : Lexer
symbol = pred (\x => not (isSpace x || isAlphaNum x))

||| `start`, then the lexer none or more times until `end`, which is read.
||| /`start`(`l`)\*?`end`/
export
surround : (start : Lexer) -> (end : Lexer) -> (l : Lexer) -> Lexer
surround start end l = start <+> manyThen end l

-- The lexer between two of the same quote.
quote : (q : Lexer) -> (l : Lexer) -> Lexer
quote q l = surround q q l

||| An escape lexer, then the lexer it escapes.
||| /[`esc`]`l`/
export
escape : (esc : Lexer) -> Lexer -> Lexer
escape esc l = esc <+> l

||| A string literal, its escaped characters with it.
||| /"(\\\\.|.)\*?"/
export
stringLit : Lexer
stringLit = quote (is '"') (escape (is '\\') any <|> any)

||| A character literal, its escaped character with it.
||| /'(\\\\.|[\^'])'/
export
charLit : Lexer
charLit = let q = '\'' in
              is q <+> (escape (is '\\') (control <|> any) <|> isNot q) <+> is q
  where
    lexStr : List String -> Lexer
    lexStr [] = fail
    lexStr (t :: ts) = exact t <|> lexStr ts

    control : Lexer
    control = lexStr ["NUL", "SOH", "STX", "ETX", "EOT", "ENQ", "ACK", "BEL",
                      "BS",  "HT",  "LF",  "VT",  "FF",  "CR",  "SO",  "SI",
                      "DLE", "DC1", "DC2", "DC3", "DC4", "NAK", "SYN", "ETB",
                      "CAN", "EM",  "SUB", "ESC", "FS",  "GS",  "RS",  "US",
                      "SP",  "DEL"]
                <|> (is 'x' <+> hexDigits)
                <|> (is 'o' <+> octDigits)
                <|> digits

||| An integer literal, perhaps negative.
||| /-?[0-9]+/
export
intLit : Lexer
intLit = opt (is '-') <+> digits

-- A binary literal, after "0b".
binLit : Lexer
binLit = exact "0b" <+> binDigits

-- A hexadecimal literal, after "0x" or "0X".
hexLit : Lexer
hexLit = approx "0x" <+> hexDigits

-- An octal literal, after "0o".
octLit : Lexer
octLit = exact "0o" <+> octDigits

||| Decimal digits, runs of them joined by underscores.
export
digitsUnderscoredLit : Lexer
digitsUnderscoredLit = digits <+> many (is '_' <+> digits)

||| A binary literal, runs of its digits joined by underscores.
export
binUnderscoredLit : Lexer
binUnderscoredLit = binLit <+> many (is '_' <+> binDigits)

||| A hexadecimal literal, runs of its digits joined by underscores.
export
hexUnderscoredLit : Lexer
hexUnderscoredLit = hexLit <+> many (is '_' <+> hexDigits)

||| An octal literal, runs of its digits joined by underscores.
export
octUnderscoredLit : Lexer
octUnderscoredLit = octLit <+> many (is '_' <+> octDigits)
