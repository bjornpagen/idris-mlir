module Main

-- Strings built from lists once: the Prelude's pack, fastPack and
-- fastConcat (which base's fastUnlines uses), and fastUnpack, with
-- characters of every UTF-8 length (U+00E9, U+2603, U+1F600 and the last
-- scalar value, U+10FFFF), empty lists and a long one.

import Prelude
import Data.String

main : IO ()
main = do
  putStrLn (pack ['h', 'é', 'l', 'l', 'o', ' ', 'w', 'ö', 'r', 'l', 'd'])
  putStrLn (fastPack (unpack "fast ☃ pack"))
  putStrLn (pack [])
  putStrLn (fastConcat ["ab", "", "çd", "e☃f"])
  putStrLn (fastConcat [])
  printLn (fastUnpack "héllo")
  printLn (length (pack (replicate 1000 'x')))
  putStr (fastUnlines ["one", "two", "thrée"])
  putStrLn (pack ['a', '\x1F600', '\x10FFFF', 'z'])
  printLn (fastUnpack "a\x1F600\x10FFFF")
  printLn (fastUnpack "")
  printLn (length (fastConcat ["", ""]), length (fastPack []))
