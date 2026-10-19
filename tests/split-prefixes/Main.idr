module Main

-- span, break and splitAt end their input with a pair of empty lists: the
-- same static pair on every call, holding no cell but the empty list's
-- atom. Joined with the pairs they build around a list nothing else holds,
-- it shares nothing, so what they return is held by nothing else either,
-- and so is a list consed onto a prefix they split off ('>' :: hdr, as
-- reverse-complement writes its headers): every cell taken apart is taken
-- without testing its count.

import Prelude
import Data.List

readAll : List Char -> IO (List Char)
readAll acc = do
  c <- getChar
  if ord c == 255 then pure (reverse acc) else readAll (c :: acc)

putChunks : List Char -> IO ()
putChunks [] = pure ()
putChunks cs = let (l, rest) = splitAt 4 cs in do putStrLn (pack l); putChunks rest

entry : List Char -> IO ()
entry cs = do
  let (hdr, rest) = break (== '\n') cs
  putStrLn (pack ('>' :: hdr))
  let (digits, others) = span isDigit (drop 1 rest)
  putStrLn (pack ('#' :: digits))
  putChunks others

main : IO ()
main = do
  input <- readAll []
  entry input
