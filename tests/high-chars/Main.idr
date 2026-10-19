module Main

import Prelude

-- A Char is a Unicode scalar value, and putChar writes its UTF-8 encoding,
-- as putStr writes a string's: 'È' (200) is c3 88 and 'λ' (955) is ce bb,
-- where upstream's backends write the low byte. The byte ca on stdin is
-- read back as the character 202, and characters computed at runtime from
-- it are written the same way.
main : IO ()
main = do
  putChar (chr 128)
  putChar (chr 200)
  putChar (chr 255)
  putChar (chr 955)
  putChar '\n'
  putStr (pack [chr 201, chr 955])
  putChar '\n'
  c <- getChar
  putChar c
  putChar (chr (ord c + 53))
  putChar (chr (ord c + 256))
  putChar '\n'
