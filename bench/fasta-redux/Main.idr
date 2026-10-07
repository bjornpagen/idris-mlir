module Main

-- fasta-redux: the same three sequences as fasta, but each random nucleotide
-- is the table entry of the generator's residue. fasta searches the
-- cumulative probabilities every time; this lookup is what that program
-- refuses. The table holds every residue, so the sequences are fasta's.

import Prelude
import Data.Buffer
import Data.List
import System.File

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

-- A non-negative size is a buffer; a negative one is empty, and nothing here
-- asks for a negative size.
alloc : Int -> IO Buffer
alloc n = do
  Just buf <- newBuffer n
    | Nothing => emptyBuffer
  pure buf

-- One byte per residue. Built once, then each nucleotide is an index.
lookup : List Sym -> IO Buffer
lookup tbl = do
  arr <- alloc im
  fill arr 0
  pure arr
  where
    fill : Buffer -> Int -> IO ()
    fill arr s =
      if s >= im then pure ()
      else do
        setBits8 arr s (cast (ord (pick tbl (cast s / cast im))))
        fill arr (s + 1)

lineLen : Int
lineLen = 60

-- alu ++ alu, so a line that starts before the end of alu copies straight
-- through, the same slice `take` of `drop` took.
aluBuffer : IO Buffer
aluBuffer = do
  let cs = alu ++ alu
  let n = cast (length cs)
  buf <- alloc n
  fill buf cs 0
  pure buf
  where
    fill : Buffer -> List Char -> Int -> IO ()
    fill _ [] _ = pure ()
    fill buf (c :: cs) i = do
      setBits8 buf i (cast (ord c))
      fill buf cs (i + 1)

copySlice : Buffer -> Int -> Buffer -> Int -> IO ()
copySlice src start dst n = go 0
  where
    go : Int -> IO ()
    go i =
      if i >= n then pure ()
      else do
        b <- getBits8 src (start + i)
        setBits8 dst i b
        go (i + 1)

putLine : Buffer -> Int -> IO ()
putLine line m = do
  ignore (writeBufferData stdout line 0 m)
  putChar '\n'

repeatFasta : Buffer -> Buffer -> Int -> Int -> IO ()
repeatFasta alu line k n =
  if n <= 0 then pure ()
  else do
    let m = min n lineLen
    copySlice alu k line m
    putLine line m
    repeatFasta alu line ((k + m) `mod` aluLen) (n - m)

gen : Buffer -> Buffer -> Int -> Int -> Int -> IO Int
gen table line s k i =
  if k <= 0 then pure s
  else do
    let s' = random s
    c <- getBits8 table s'
    setBits8 line i c
    gen table line s' (k - 1) (i + 1)

randomFasta : Buffer -> Buffer -> Int -> Int -> IO Int
randomFasta table line seed n =
  if n <= 0 then pure seed
  else do
    let m = min n lineLen
    seed' <- gen table line seed m 0
    putLine line m
    randomFasta table line seed' (n - m)

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
  alu <- aluBuffer
  iubTable <- lookup iub
  homoTable <- lookup homo
  line <- alloc lineLen
  putStrLn ">ONE Homo sapiens alu"
  repeatFasta alu line 0 (n * 2)
  putStrLn ">TWO IUB ambiguity codes"
  s <- randomFasta iubTable line 42 (n * 3)
  putStrLn ">THREE Homo sapiens frequency"
  _ <- randomFasta homoTable line s (n * 5)
  pure ()
