module Main

-- reverse-complement (the Benchmarks Game): each FASTA record's sequence
-- reversed and complemented, written 60 characters to a line. The input is
-- read to its end; a sequence accumulates reversed as it is read.

import Prelude
import Data.List

comp : Char -> Char
comp c = case toUpper c of
  'A' => 'T'
  'C' => 'G'
  'G' => 'C'
  'T' => 'A'
  'U' => 'A'
  'M' => 'K'
  'R' => 'Y'
  'Y' => 'R'
  'K' => 'M'
  'V' => 'B'
  'H' => 'D'
  'D' => 'H'
  'B' => 'V'
  u => u

readAll : List Char -> IO (List Char)
readAll acc = do
  c <- getChar
  if ord c == 255 then pure (reverse acc) else readAll (c :: acc)

putChunks : List Char -> IO ()
putChunks [] = pure ()
putChunks cs = let (l, rest) = splitAt 60 cs in do putStrLn (pack l); putChunks rest

mutual
  process : List Char -> IO ()
  process [] = pure ()
  process ('>' :: cs) = do
    let (hdr, rest) = break (== '\n') cs
    putStrLn (pack ('>' :: hdr))
    body (drop 1 rest) []
  process (_ :: cs) = process cs

  body : List Char -> List Char -> IO ()
  body [] acc = putChunks acc
  body ('>' :: cs) acc = do putChunks acc; process ('>' :: cs)
  body ('\n' :: cs) acc = body cs acc
  body (c :: cs) acc = body cs (comp c :: acc)

main : IO ()
main = do
  input <- readAll []
  process input
