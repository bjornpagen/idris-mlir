module Main

-- fasta-redux: the same three sequences as fasta, but each random nucleotide
-- is the table entry of the generator's residue. fasta searches the
-- cumulative probabilities every time; this lookup is what that program
-- refuses. The table holds every residue, so the sequences are fasta's.

import Prelude
import Data.IOArray
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

im : Int
im = 139968

random : Int -> Int
random seed = (seed * 3877 + 29573) `mod` im

pick : List Sym -> Double -> Char
pick [] _ = 'a'
pick [MkSym c _] _ = c
pick (MkSym c p :: rest) r = if r < p then c else pick rest r

-- One slot per residue. Built once, then each nucleotide is an index.
lookup : List Sym -> IO (IOArray Int)
lookup tbl = do
  arr <- newArray im
  fill arr 0
  pure arr
  where
    fill : IOArray Int -> Int -> IO ()
    fill arr s =
      if s >= im then pure ()
      else do
        ignore (writeArray arr s (cast (ord (pick tbl (cast s / cast im)))))
        fill arr (s + 1)

lineLen : Int
lineLen = 60

repeatFasta : Int -> Int -> IO ()
repeatFasta k n =
  if n <= 0 then pure ()
  else do
    let m = min n lineLen
    putStrLn (pack (take (cast m) (drop (cast k) alu2)))
    repeatFasta ((k + m) `mod` aluLen) (n - m)

gen : IOArray Int -> Int -> Int -> List Char -> IO (Int, List Char)
gen _ s 0 acc = pure (s, reverse acc)
gen arr s k acc = do
  let s' = random s
  Just code <- readArray arr s'
    | Nothing => gen arr s' (k - 1) ('a' :: acc)
  gen arr s' (k - 1) (chr code :: acc)

randomFasta : IOArray Int -> Int -> Int -> IO Int
randomFasta arr seed n =
  if n <= 0 then pure seed
  else do
    let m = min n lineLen
    (seed', line) <- gen arr seed m []
    putStrLn (pack line)
    randomFasta arr seed' (n - m)

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
  iubTable <- lookup iub
  homoTable <- lookup homo
  putStrLn ">ONE Homo sapiens alu"
  repeatFasta 0 (n * 2)
  putStrLn ">TWO IUB ambiguity codes"
  s <- randomFasta iubTable 42 (n * 3)
  putStrLn ">THREE Homo sapiens frequency"
  _ <- randomFasta homoTable s (n * 5)
  pure ()
