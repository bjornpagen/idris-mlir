module Main

-- fasta (the Benchmarks Game): a repeated sequence and two random ones
-- drawn from cumulative tables by a linear congruential generator, written
-- 60 characters to a line.

import Prelude
import Data.List

alu : List Char
alu = unpack ("GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGG"
           ++ "GAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTCGAGA"
           ++ "CCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAAT"
           ++ "ACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTGTAATCCCA"
           ++ "GCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACCCGGG"
           ++ "AGGCGGAGGTTGCAGTGAGCCGAGATCGCGCCACTGCACTCC"
           ++ "AGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAA")

aluLen : Int
aluLen = cast (length alu)

alu2 : List Char
alu2 = alu ++ alu

record Sym where
  constructor MkSym
  symbol : Char
  cum : Double

-- Cumulative probabilities, summed in order, as the C version sums them.
table : List (Char, Double) -> List Sym
table = go 0.0
  where
    go : Double -> List (Char, Double) -> List Sym
    go _ [] = []
    go acc ((c, p) :: rest) = let acc' = acc + p in MkSym c acc' :: go acc' rest

iub : List Sym
iub = table [ ('a', 0.27), ('c', 0.12), ('g', 0.12), ('t', 0.27)
            , ('B', 0.02), ('D', 0.02), ('H', 0.02), ('K', 0.02), ('M', 0.02), ('N', 0.02)
            , ('R', 0.02), ('S', 0.02), ('V', 0.02), ('W', 0.02), ('Y', 0.02) ]

homo : List Sym
homo = table [ ('a', 0.3029549426680), ('c', 0.1979883004921)
             , ('g', 0.1975473066391), ('t', 0.3015094502008) ]

random : Int -> Int
random seed = (seed * 3877 + 29573) `mod` 139968

pick : List Sym -> Double -> Char
pick [] _ = 'a'
pick [MkSym c _] _ = c
pick (MkSym c p :: rest) r = if r < p then c else pick rest r

lineLen : Int
lineLen = 60

repeatFasta : Int -> Int -> IO ()
repeatFasta k n =
  if n <= 0 then pure ()
  else do
    let m = min n lineLen
    putStrLn (pack (take (cast m) (drop (cast k) alu2)))
    repeatFasta ((k + m) `mod` aluLen) (n - m)

gen : List Sym -> Int -> Int -> List Char -> (Int, List Char)
gen tbl s 0 acc = (s, reverse acc)
gen tbl s k acc =
  let s' = random s
      c = pick tbl (cast s' / 139968.0)
  in gen tbl s' (k - 1) (c :: acc)

randomFasta : List Sym -> Int -> Int -> IO Int
randomFasta tbl seed n =
  if n <= 0 then pure seed
  else do
    let m = min n lineLen
    let (seed', line) = gen tbl seed m []
    putStrLn (pack line)
    randomFasta tbl seed' (n - m)

readInt : IO Int
readInt = go 0
  where
    go : Int -> IO Int
    go acc = do
      c <- getChar
      if isDigit c then go (acc * 10 + cast (ord c - 48)) else pure acc

main : IO ()
main = do
  n <- readInt
  putStrLn ">ONE Homo sapiens alu"
  repeatFasta 0 (n * 2)
  putStrLn ">TWO IUB ambiguity codes"
  s <- randomFasta iub 42 (n * 3)
  putStrLn ">THREE Homo sapiens frequency"
  _ <- randomFasta homo s (n * 5)
  pure ()
