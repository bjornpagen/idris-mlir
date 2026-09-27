-- expect: PROF-DATA-3 line 11
module Main

-- rule: SEM-REC-1
-- The Prelude's lists are recursive: a list whose length is known only at
-- runtime would need the heap.

import Prelude
import IdrisMLIR.IO

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
