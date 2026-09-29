-- expect: runtime data, line 10
module Main

-- The Prelude's lists are recursive: a list whose length is known only at
-- runtime would need the heap. The program uses nothing but the Prelude,
-- its IO included.

import Prelude

build : Int -> List Int
build 0 = []
build n = n :: build (n - 1)

len : List Int -> Int
len [] = 0
len (_ :: xs) = 1 + len xs

main : IO ()
main = do
  c <- getChar
  putStrLn (show (len (build (cast (ord c)))))
