-- expect: uniqueness, line 26
-- message: Rebuilds.bump
module Main

import Prelude
import Rebuilds

-- The library's shared passes bump a list it reads again, so the call is
-- refused, and the refusal is the library's: at its line
-- (library/Rebuilds.idr), naming its bump, though this program hands
-- shared a list no one else holds. exclusive/ calls the library's once.

main : IO ()
main = do
  c <- getChar
  printLn (sharedOf (cast (ord c - ord '0')))
