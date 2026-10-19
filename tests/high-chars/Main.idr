module Main

import Prelude

-- A Char is a Unicode scalar value, and putChar writes its UTF-8 encoding,
-- as putStr writes a string's: 'È' (200) is c3 88 and 'λ' (955) is ce bb,
-- where upstream's backends write the low byte. The first line holds each
-- length's first and last character (127, 128, 2047, 2048, 65535, 65536 and
-- the last, 1114111). getChar reads one byte as the character of that
-- number, and 255 at the end of input, so the input's byte comes back as a
-- character and characters computed at runtime from it are written the
-- same way.
main : IO ()
main = do
  putChar (chr 128)
  putChar (chr 200)
  putChar (chr 255)
  putChar (chr 955)
  putChar (chr 127)
  putChar (chr 2047)
  putChar (chr 2048)
  putChar (chr 65535)
  putChar (chr 65536)
  putChar (chr 1114111)
  putChar '\n'
  putStr (pack [chr 201, chr 955])
  putChar '\n'
  c <- getChar
  putChar c
  putChar (chr (ord c + 53))
  putChar (chr (ord c + 256))
  putChar '\n'
