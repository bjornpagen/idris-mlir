-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Libraries.Utils.Octal

%default total

export
fromOctDigit : Char -> Maybe Int
fromOctDigit '0' = Just 0
fromOctDigit '1' = Just 1
fromOctDigit '2' = Just 2
fromOctDigit '3' = Just 3
fromOctDigit '4' = Just 4
fromOctDigit '5' = Just 5
fromOctDigit '6' = Just 6
fromOctDigit '7' = Just 7
fromOctDigit _ = Nothing

export
fromOctChars : List Char -> Maybe Integer
fromOctChars = fromOctChars' 1
  where
    fromOctChars' : Integer -> List Char -> Maybe Integer
    fromOctChars' _ [] = Just 0
    fromOctChars' m (d :: ds)
      = do digit <- fromOctDigit (toLower d)
           digits <- fromOctChars' (m*8) ds
           pure $ cast digit * m + digits

export
fromOct : String -> Maybe Integer
fromOct = fromOctChars . unpack
