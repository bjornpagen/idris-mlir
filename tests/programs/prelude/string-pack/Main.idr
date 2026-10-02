module Main

-- Strings built from lists once: the Prelude's pack, fastPack and
-- fastConcat (which base's fastUnlines uses), and fastUnpack, with
-- characters beyond ASCII, empty lists and a long one.

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
