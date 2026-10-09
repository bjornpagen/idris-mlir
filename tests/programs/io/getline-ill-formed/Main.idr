module Main

-- getLine decodes input that is not well-formed UTF-8 as the Unicode
-- Standard recommends: each maximal subpart, the longest prefix of a
-- well-formed sequence or else one byte, is one U+FFFD (65533). The lines
-- of stdin: a truncated three-byte and four-byte sequence (one each), an
-- overlong C0 80 (two), an encoded surrogate ED A0 80 (three), a lone lead
-- byte (one), then well-formed text of two-, three- and four-byte
-- sequences, read whole.

import Prelude

readLines : IO ()
readLines = do
  l <- getLine
  if l == ""
     then pure ()
     else do
       putStrLn (show (length l) ++ " " ++ show (map ord (unpack l)))
       readLines

main : IO ()
main = readLines
