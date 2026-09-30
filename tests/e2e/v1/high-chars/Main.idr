module Main

import Prelude

-- The Prelude's putChar is C's putchar: it writes the character's low byte,
-- so 'È' (200) is the one byte c8 and 'λ' (955) the byte bb, as with the
-- reference, while a string is written in UTF-8. The byte on stdin, ca, is
-- read back as the character 202 and written as that byte again, and a
-- character computed at runtime from it is written the same way.
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
