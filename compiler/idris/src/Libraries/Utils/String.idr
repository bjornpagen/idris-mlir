module Libraries.Utils.String

import Data.String

%default total

-- Base's trims and number parsers see a string through its `strM` view,
-- whose proof is coerced with `believe_me`, which this compiler refuses
-- wherever a program reaches it. These see its characters, with base's
-- results.

||| The string without the whitespace it starts with (base's `ltrim`).
export
trimStart : String -> String
trimStart = pack . dropWhile isSpace . unpack

trimmedChars : String -> List Char
trimmedChars = reverse . dropWhile isSpace . reverse . dropWhile isSpace . unpack

||| The string without the whitespace it starts or ends with (base's
||| `trim`).
export
trimSpace : String -> String
trimSpace = pack . trimmedChars

||| Decimal digits after an optional `+`, whitespace around them trimmed
||| (base's `parsePositive`).
export
parseNatural : Num a => String -> Maybe a
parseNatural s = case trimmedChars s of
  [] => Nothing
  '+' :: cs => fromInteger <$> parseNumWithoutSign cs 0
  cs => fromInteger <$> parseNumWithoutSign cs 0

||| Decimal digits after an optional sign, whitespace around them trimmed
||| (base's `parseInteger`).
export
parseSigned : Num a => Neg a => String -> Maybe a
parseSigned s = case trimmedChars s of
  [] => Nothing
  '-' :: cs => negate . fromInteger <$> parseNumWithoutSign cs 0
  '+' :: cs => fromInteger <$> parseNumWithoutSign cs 0
  cs => fromInteger <$> parseNumWithoutSign cs 0

export
stripSurrounds : (lead : Nat) -> (tail : Nat) -> String -> String
stripSurrounds lead tail str = substr lead (length str `minus` (lead + tail)) str

export
stripQuotes : String -> String
stripQuotes = stripSurrounds 1 1

export
lowerFirst : String -> Bool
lowerFirst "" = False
lowerFirst str = isLower $ assert_total $ prim__strHead str
