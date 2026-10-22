-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| JSON, read: what the lock (toolchain.lock.json) and a compilation's time
||| trace are written in. The runner builds under both hosts, and contrib,
||| which holds Idris's own reader, is a package idris-mlir does not ship,
||| so the harness reads JSON itself.
|||
||| A number is kept as the text it was written as: the lock's schema is an
||| integer and a trace's durations are integers of microseconds, and a
||| reader that read every number as a Double would give each host's
||| printing of it back, which differs between the hosts.
module Json

import Data.List
import Data.String

%default total

public export
data JSON
  = JNull
  | JBool Bool
  | JNumber String
  | JString String
  | JArray (List JSON)
  | JObject (List (String, JSON))

||| What the text is made of, between its values.
data Token
  = LBrace | RBrace | LBracket | RBracket | Colon | Comma
  | TString String | TNumber String | TWord String

numberChar : Char -> Bool
numberChar c = isDigit c || c == '-' || c == '+' || c == '.' || c == 'e' || c == 'E'

||| The character an escape after a backslash stands for; a `\u` escape
||| reads its four hex digits apart (`unicode`).
escaped : Char -> Maybe Char
escaped '"' = Just '"'
escaped '\\' = Just '\\'
escaped '/' = Just '/'
escaped 'b' = Just '\b'
escaped 'f' = Just '\f'
escaped 'n' = Just '\n'
escaped 'r' = Just '\r'
escaped 't' = Just '\t'
escaped _ = Nothing

hexValue : Char -> Maybe Int
hexValue c =
  if isDigit c then Just (ord c - ord '0')
  else if c >= 'a' && c <= 'f' then Just (ord c - ord 'a' + 10)
  else if c >= 'A' && c <= 'F' then Just (ord c - ord 'A' + 10)
  else Nothing

unicode : Char -> Char -> Char -> Char -> Maybe Char
unicode a b c d = do
  [w, x, y, z] <- traverse hexValue [a, b, c, d]
    | _ => Nothing
  pure (chr (((w * 16 + x) * 16 + y) * 16 + z))

mutual
  ||| The tokens of the text: each step takes at least the character it
  ||| reads, so the lexer ends on every text.
  lexOut : SnocList Token -> List Char -> Either String (List Token)
  lexOut acc [] = Right (acc <>> [])
  lexOut acc (c :: cs) = lexChar acc c cs

  ||| The token a character outside a string or a number starts.
  lexChar : SnocList Token -> Char -> List Char -> Either String (List Token)
  lexChar acc '{' cs = lexOut (acc :< LBrace) cs
  lexChar acc '}' cs = lexOut (acc :< RBrace) cs
  lexChar acc '[' cs = lexOut (acc :< LBracket) cs
  lexChar acc ']' cs = lexOut (acc :< RBracket) cs
  lexChar acc ':' cs = lexOut (acc :< Colon) cs
  lexChar acc ',' cs = lexOut (acc :< Comma) cs
  lexChar acc '"' cs = lexString acc [<] cs
  lexChar acc c cs =
    if isSpace c then lexOut acc cs
    else if numberChar c then lexNumber acc [<c] cs
    else if isAlpha c then lexWord acc [<c] cs
    else Left ("unexpected " ++ show c)

  lexString : SnocList Token -> SnocList Char -> List Char -> Either String (List Token)
  lexString _ _ [] = Left "a string that does not end"
  lexString acc s ('"' :: cs) = lexOut (acc :< TString (pack (s <>> []))) cs
  lexString acc s ('\\' :: 'u' :: a :: b :: c :: d :: cs) =
    case unicode a b c d of
      Just u => lexString acc (s :< u) cs
      Nothing => Left "a \\u escape without four hex digits"
  lexString acc s ('\\' :: e :: cs) =
    case escaped e of
      Just c => lexString acc (s :< c) cs
      Nothing => Left ("the escape \\" ++ singleton e)
  lexString acc s (c :: cs) = lexString acc (s :< c) cs

  lexNumber : SnocList Token -> SnocList Char -> List Char -> Either String (List Token)
  lexNumber acc n [] = Right ((acc :< TNumber (pack (n <>> []))) <>> [])
  lexNumber acc n (c :: cs) =
    if numberChar c then lexNumber acc (n :< c) cs
    else lexChar (acc :< TNumber (pack (n <>> []))) c cs

  lexWord : SnocList Token -> SnocList Char -> List Char -> Either String (List Token)
  lexWord acc w [] = Right ((acc :< TWord (pack (w <>> []))) <>> [])
  lexWord acc w (c :: cs) =
    if isAlpha c then lexWord acc (w :< c) cs
    else lexChar (acc :< TWord (pack (w <>> []))) c cs

||| What the parser is inside of: an array of the values read so far, or an
||| object of its fields read so far and the key of the field being read.
data Frame
  = InArray (SnocList JSON)
  | InObject (SnocList (String, JSON)) String

||| Where the parser stands: before a value (`Value`); after one, with the
||| frames it is inside (`After`); before an object's key (`Key`); after an
||| object's key, before its colon (`Colon`).
data Expecting = Value | After JSON | KeyNext | ColonAfter String

||| The value of the tokens, by one pass over them with an explicit stack
||| of frames, each step taking a token, so the parser ends on every text
||| and its depth is the heap's, never the stack's.
parseTokens : Expecting -> List Frame -> List Token -> Either String JSON
-- a value
parseTokens Value fs (TString s :: ts) = parseTokens (After (JString s)) fs ts
parseTokens Value fs (TNumber n :: ts) = parseTokens (After (JNumber n)) fs ts
parseTokens Value fs (TWord "true" :: ts) = parseTokens (After (JBool True)) fs ts
parseTokens Value fs (TWord "false" :: ts) = parseTokens (After (JBool False)) fs ts
parseTokens Value fs (TWord "null" :: ts) = parseTokens (After JNull) fs ts
parseTokens Value fs (LBracket :: RBracket :: ts) = parseTokens (After (JArray [])) fs ts
parseTokens Value fs (LBracket :: ts) = parseTokens Value (InArray [<] :: fs) ts
parseTokens Value fs (LBrace :: RBrace :: ts) = parseTokens (After (JObject [])) fs ts
parseTokens Value fs (LBrace :: ts) = parseTokens KeyNext (InObject [<] "" :: fs) ts
parseTokens Value _ _ = Left "expected a value"
-- an object's key and its colon
parseTokens KeyNext fs (TString k :: ts) = parseTokens (ColonAfter k) fs ts
parseTokens KeyNext _ _ = Left "expected an object's key"
parseTokens (ColonAfter k) (InObject fields _ :: fs) (Colon :: ts) =
  parseTokens Value (InObject fields k :: fs) ts
parseTokens (ColonAfter _) _ _ = Left "expected a colon after a key"
-- after a value: the end, or the frame it belongs to goes on or ends
parseTokens (After v) [] [] = Right v
parseTokens (After _) [] _ = Left "text after the value"
parseTokens (After v) (InArray vs :: fs) (Comma :: ts) = parseTokens Value (InArray (vs :< v) :: fs) ts
parseTokens (After v) (InArray vs :: fs) (RBracket :: ts) = parseTokens (After (JArray (vs <>> [v]))) fs ts
parseTokens (After v) (InObject fields k :: fs) (Comma :: ts) =
  parseTokens KeyNext (InObject (fields :< (k, v)) "" :: fs) ts
parseTokens (After v) (InObject fields k :: fs) (RBrace :: ts) =
  parseTokens (After (JObject (fields <>> [(k, v)]))) fs ts
parseTokens (After _) _ _ = Left "expected a comma or the end of an array or object"

||| The JSON value the text holds, or what is wrong with it.
export
parse : String -> Either String JSON
parse text = lexOut [<] (unpack text) >>= parseTokens Value []

||| A field of an object, by its key.
export
field : String -> JSON -> Maybe JSON
field key (JObject fields) = lookup key fields
field _ _ = Nothing

||| A number written as an integer.
export
integer : JSON -> Maybe Integer
integer (JNumber n) = parseInteger n
integer _ = Nothing
