module Main

-- char-list-pipeline's text program, but each generated line is kept in an
-- accumulator and reversed only when all are printed, so no specialization
-- ever sees a line's shape. A line is still built of fresh cells, each a
-- choice of a character consed onto the line before, never static data
-- that every holder shares: reverse turns each line around in place.

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
gen s 0 acc = (s, acc)
gen s k acc = let s' = (s * 3877 + 29573) `mod` 139968
              in gen s' (k - 1) (pick table (s' `mod` 8) :: acc)

printAll : List (List Char) -> IO ()
printAll [] = pure ()
printAll (l :: ls) = do putStrLn (pack (reverse l)); printAll ls

lines : Int -> Int -> List (List Char) -> IO ()
lines s 0 acc = printAll acc
lines s n acc =
  let (s', line) = gen s 12 []
  in lines s' (n - 1) (line :: acc)

main : IO ()
main = do
  input <- readAll []
  process input
  lines 42 3 []
