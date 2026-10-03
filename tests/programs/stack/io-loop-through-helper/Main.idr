module Main

-- An IO loop through the mutually recursive process and body, which call a
-- helper, push, whose body is an `if` over two actions, with an argument
-- that is itself a case (comp c). Each character goes round through push's
-- action and the continuation of its bind, which calls body: in tail
-- position all the way, through the closures of the binds. Chez runs it in
-- constant stack, as Scheme's proper tail calls do, and so must this
-- compiler, on an input long enough that a frame kept per character would
-- exhaust the 1 MiB stack the harness gives the program.

import Prelude
import Data.IOArray.Prims

comp : Char -> Char
comp c = case toUpper c of
  'A' => 'T'
  'C' => 'G'
  'G' => 'C'
  'T' => 'A'
  u => u

Chars : Type
Chars = ArrayData Char

copyChars : Chars -> Chars -> Int -> Int -> IO ()
copyChars from to i n =
  if i >= n then pure ()
  else do
    c <- primIO (prim__arrayGet from i)
    primIO (prim__arraySet to i c)
    copyChars from to (i + 1) n

-- c stored at len, the buffer grown first when it is full: the buffer and
-- its capacity.
push : Chars -> Int -> Int -> Char -> IO (Chars, Int)
push buf cap len c =
  if len < cap
     then do
       primIO (prim__arraySet buf len c)
       pure (buf, cap)
     else do
       big <- primIO (prim__newArray (cap * 2) ' ')
       copyChars buf big 0 len
       primIO (prim__arraySet big len c)
       pure (big, cap * 2)

readAll : Chars -> Int -> Int -> IO (Chars, Int)
readAll buf cap len = do
  c <- getChar
  if ord c == 255
     then pure (buf, len)
     else do
       (buf', cap') <- push buf cap len c
       readAll buf' cap' (len + 1)

-- After each '>', the characters up to the next one pushed into a buffer
-- of their own, and their number written.
mutual
  process : Chars -> Int -> Int -> IO ()
  process inp n i =
    if i >= n then pure ()
    else do
      c <- primIO (prim__arrayGet inp i)
      if c == '>'
         then do
           acc <- primIO (prim__newArray 16 ' ')
           body inp n (i + 1) acc 16 0
         else process inp n (i + 1)

  body : Chars -> Int -> Int -> Chars -> Int -> Int -> IO ()
  body inp n i acc cap len =
    if i >= n then printLn len
    else do
      c <- primIO (prim__arrayGet inp i)
      if c == '>'
         then do
           printLn len
           process inp n i
         else if c == '\n'
                 then body inp n (i + 1) acc cap len
                 else do
                   (acc', cap') <- push acc cap len (comp c)
                   body inp n (i + 1) acc' cap' (len + 1)

main : IO ()
main = do
  buf <- primIO (prim__newArray 16 ' ')
  (inp, n) <- readAll buf 16 0
  process inp n 0
