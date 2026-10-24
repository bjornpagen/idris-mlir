-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Parser.Support.Escaping

import Control.WellFounded
import Data.List
import Data.Nat
import Libraries.Data.String.Extra

%default total

export
hex : Char -> Maybe Int
hex '0' = Just 0
hex '1' = Just 1
hex '2' = Just 2
hex '3' = Just 3
hex '4' = Just 4
hex '5' = Just 5
hex '6' = Just 6
hex '7' = Just 7
hex '8' = Just 8
hex '9' = Just 9
hex 'a' = Just 10
hex 'b' = Just 11
hex 'c' = Just 12
hex 'd' = Just 13
hex 'e' = Just 14
hex 'f' = Just 15
hex _ = Nothing

export
oct : Char -> Maybe Int
oct '0' = Just 0
oct '1' = Just 1
oct '2' = Just 2
oct '3' = Just 3
oct '4' = Just 4
oct '5' = Just 5
oct '6' = Just 6
oct '7' = Just 7
oct _ = Nothing

export
getEsc : String -> Maybe Char
getEsc "NUL" = Just '\NUL'
getEsc "SOH" = Just '\SOH'
getEsc "STX" = Just '\STX'
getEsc "ETX" = Just '\ETX'
getEsc "EOT" = Just '\EOT'
getEsc "ENQ" = Just '\ENQ'
getEsc "ACK" = Just '\ACK'
getEsc "BEL" = Just '\BEL'
getEsc "BS" = Just '\BS'
getEsc "HT" = Just '\HT'
getEsc "LF" = Just '\LF'
getEsc "VT" = Just '\VT'
getEsc "FF" = Just '\FF'
getEsc "CR" = Just '\CR'
getEsc "SO" = Just '\SO'
getEsc "SI" = Just '\SI'
getEsc "DLE" = Just '\DLE'
getEsc "DC1" = Just '\DC1'
getEsc "DC2" = Just '\DC2'
getEsc "DC3" = Just '\DC3'
getEsc "DC4" = Just '\DC4'
getEsc "NAK" = Just '\NAK'
getEsc "SYN" = Just '\SYN'
getEsc "ETB" = Just '\ETB'
getEsc "CAN" = Just '\CAN'
getEsc "EM" = Just '\EM'
getEsc "SUB" = Just '\SUB'
getEsc "ESC" = Just '\ESC'
getEsc "FS" = Just '\FS'
getEsc "GS" = Just '\GS'
getEsc "RS" = Just '\RS'
getEsc "US" = Just '\US'
getEsc "SP" = Just '\SP'
getEsc "DEL" = Just '\DEL'
getEsc str = Nothing

-- What is left of a text once a part of it is read: no more characters
-- than the text had, so a loop over the text that reads an escape recurses
-- on less of it.
record Remaining (text : List Char) where
  constructor MkRemaining
  rest : List Char
  0 noLonger : Nat.LTE (length rest) (length text)

-- What is left of a text with one more character in front.
grown : Remaining text -> Remaining (c :: text)
grown (MkRemaining rest le) = MkRemaining rest (lteSuccRight le)

-- What follows a text's first character.
past : (text : List Char) -> Remaining (c :: text)
past text = MkRemaining text (lteSuccRight reflexive)

-- The text after the characters given, if it begins with them.
after : (hashes : List Char) -> (text : List Char) -> Maybe (Remaining text)
after [] text = Just (MkRemaining text reflexive)
after (h :: hs) [] = Nothing
after (h :: hs) (c :: cs) = if h == c then grown <$> after hs cs else Nothing

-- The longest start of the text of characters `p` holds of, and what
-- follows it.
spanning : (Char -> Bool) -> (text : List Char) -> (List Char, Remaining text)
spanning p [] = ([], MkRemaining [] LTEZero)
spanning p (c :: cs)
    = if p c
         then let (ds, more) = spanning p cs in (c :: ds, grown more)
         else ([], MkRemaining (c :: cs) reflexive)

toHex : Int -> List Char -> Maybe Int
toHex _ [] = Just 0
toHex m (d :: ds)
    = pure $ !(hex (toLower d)) * m + !(toHex (m*16) ds)

toOct : Int -> List Char -> Maybe Int
toOct _ [] = Just 0
toOct m (d :: ds)
    = pure $ !(oct (toLower d)) * m + !(toOct (m*8) ds)

-- The characters an escape stands for, given what follows its backslash and
-- hashes, and what follows the escape.
escapeAt : (text : List Char) -> Maybe (List Char, Remaining text)
escapeAt ('\\' :: xs) = Just (['\\'], past xs)
escapeAt ('\n' :: xs) = Just ([], past xs)
escapeAt ('&' :: xs) = Just ([], past xs)
escapeAt ('a' :: xs) = Just (['\a'], past xs)
escapeAt ('b' :: xs) = Just (['\b'], past xs)
escapeAt ('f' :: xs) = Just (['\f'], past xs)
escapeAt ('n' :: xs) = Just (['\n'], past xs)
escapeAt ('r' :: xs) = Just (['\r'], past xs)
escapeAt ('t' :: xs) = Just (['\t'], past xs)
escapeAt ('v' :: xs) = Just (['\v'], past xs)
escapeAt ('\'' :: xs) = Just (['\''], past xs)
escapeAt ('"' :: xs) = Just (['"'], past xs)
escapeAt ('x' :: xs)
    = case spanning isHexDigit xs of
           ([], more) => Just ([], grown more)
           (ds, more) => Just ([cast !(toHex 1 (reverse ds))], grown more)
escapeAt ('o' :: xs)
    = case spanning isOctDigit xs of
           ([], more) => Just ([], grown more)
           (ds, more) => Just ([cast !(toOct 1 (reverse ds))], grown more)
escapeAt xs
    = case spanning isDigit xs of
           ([], MkRemaining (a :: b :: c :: rest) le) =>
             case getEsc (fastPack [a, b, c]) of
                  Just v => Just ([v], MkRemaining rest (lteSuccLeft (lteSuccLeft (lteSuccLeft le))))
                  Nothing => case getEsc (fastPack [a, b]) of
                                  Just v => Just ([v], MkRemaining (c :: rest) (lteSuccLeft (lteSuccLeft le)))
                                  Nothing => Just ([], MkRemaining xs reflexive)
           ([], MkRemaining (a :: b :: []) le) =>
             case getEsc (fastPack [a, b]) of
                  Just v => Just ([v], MkRemaining [] LTEZero)
                  Nothing => Just ([], MkRemaining xs reflexive)
           ([], more) => Just ([], more)
           (ds, more) => Just ([cast (cast {to=Int} (fastPack ds))], more)

-- The text unescaped from where it stands: each escape read leaves less of
-- the text than there was, which `acc` bounds, so the loop ends.
unescapeFrom : (hashes : List Char) -> (text : List Char) ->
               (0 acc : Accessible Nat.LT (length text)) -> Maybe (List Char)
unescapeFrom hashes [] _ = Just []
unescapeFrom hashes (x :: xs) (Access rec)
    = if x == '\\'
         then case after hashes xs of
                   Just (MkRemaining body le) =>
                     case escapeAt body of
                          Just (made, MkRemaining rest le') =>
                            (made ++) <$> unescapeFrom hashes rest
                                            (rec (length rest) (LTESucc (transitive le' le)))
                          Nothing => Nothing
                   Nothing => (x ::) <$> unescapeFrom hashes xs (rec (length xs) reflexive)
         else (x ::) <$> unescapeFrom hashes xs (rec (length xs) reflexive)

export
unescape : Nat -> String -> Maybe String
unescape hashtag x = let text = unpack x in
                       fastPack <$> unescapeFrom (replicate hashtag '#') text (wellFounded (length text))
