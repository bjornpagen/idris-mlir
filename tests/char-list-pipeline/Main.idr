module Main

-- The list shapes of the text programs of the Benchmarks Game: the input
-- read a character at a time into a reversed list and reversed; each
-- record's sequence complemented into a new list as the input is consumed,
-- then split into fixed chunks, each packed and written; and lines drawn
-- from a table by a generator into a list, reversed and packed. The
-- generator's count is a constant, so compilation unrolls it: twelve
-- choices of a character, each consed onto the list the one before built,
-- which must stay twelve choices, not a copy of the rest of the line in
-- every branch of each.

import Prelude
import Data.List

comp : Char -> Char
comp c = case toUpper c of
  'A' => 'T'
  'C' => 'G'
  'G' => 'C'
  'T' => 'A'
  u => u

readAll : List Char -> IO (List Char)
readAll acc = do
  c <- getChar
  if ord c == 255 then pure (reverse acc) else readAll (c :: acc)

putChunks : List Char -> IO ()
putChunks [] = pure ()
putChunks cs = let (l, rest) = splitAt 8 cs in do putStrLn (pack l); putChunks rest

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

table : List (Char, Int)
table = [('a', 3), ('c', 5), ('g', 6), ('t', 8)]

pick : List (Char, Int) -> Int -> Char
pick [] _ = 'n'
pick [(c, _)] _ = c
pick ((c, p) :: rest) r = if r < p then c else pick rest r

gen : Int -> Int -> List Char -> (Int, List Char)
gen s 0 acc = (s, reverse acc)
gen s k acc = let s' = (s * 3877 + 29573) `mod` 139968
              in gen s' (k - 1) (pick table (s' `mod` 8) :: acc)

lines : Int -> Int -> IO ()
lines s 0 = pure ()
lines s n = do
  let (s', line) = gen s 12 []
  putStrLn (pack line)
  lines s' (n - 1)

main : IO ()
main = do
  input <- readAll []
  process input
  lines 42 3
