module Main

-- k-nucleotide (the Benchmarks Game): the frequencies of nucleotides and
-- pairs in the third sequence of a FASTA input, then the counts of five
-- longer fragments. As the C version does it: the sequence is an array of
-- two-bit codes, each fragment a key packed two bits a nucleotide and
-- rolled along the sequence, counted in an open-addressing hash table of
-- base's IOArrays, whose empty slots (Nothing) mark the unused ones.

import Prelude
import Data.Bits
import Data.IOArray
import Data.List

get : IOArray Int -> Int -> IO Int
get arr i = do
  Just v <- readArray arr i
    | Nothing => pure 0
  pure v

set : IOArray Int -> Int -> Int -> IO ()
set arr i v = ignore (writeArray arr i v)

-- A nucleotide's code, the same for either case: A 0, C 1, T 2, G 3.
code : Char -> Int
code c = (cast (ord c) `shiftR` 1) .&. 3

eof : Char -> Bool
eof c = ord c == 255

-- Skips the lines up to and including the header that starts with ">THREE".
skipToThree : IO ()
skipToThree = line []
  where
    line : List Char -> IO ()
    line acc = do
      c <- getChar
      if eof c
         then pure ()
         else if c == '\n'
                 then if isPrefixOf (unpack ">THREE") (reverse acc) then pure () else line []
                 else line (c :: acc)

-- The growable array of codes, and how many it holds.
record Codes where
  constructor MkCodes
  codes : IOArray Int
  size : Int
  used : Int

push : Codes -> Int -> IO Codes
push (MkCodes arr size used) v =
  if used < size
     then do set arr used v
             pure (MkCodes arr size (used + 1))
     else do bigger <- newArray (2 * size)
             copy arr bigger 0
             set bigger used v
             pure (MkCodes bigger (2 * size) (used + 1))
  where
    copy : IOArray Int -> IOArray Int -> Int -> IO ()
    copy from to i =
      if i >= used then pure () else do v' <- get from i; set to i v'; copy from to (i + 1)

-- The sequence after the header, as codes, up to the next header or the end.
readSequence : Codes -> IO Codes
readSequence acc = do
  c <- getChar
  if eof c || c == '>'
     then pure acc
     else if c == '\n'
             then readSequence acc
             else do acc' <- push acc (code c)
                     readSequence acc'

record Table where
  constructor MkTable
  keys : IOArray Int
  counts : IOArray Int
  mask : Int

newTable : Int -> IO Table
newTable n = do
  let cap = grow 1
  keys <- newArray cap
  counts <- newArray cap
  pure (MkTable keys counts (cap - 1))
  where
    grow : Int -> Int
    grow c = if c < 2 * n then grow (2 * c) else c

-- The slot of `key`, claimed for it if it has none.
slot : Table -> Int -> IO Int
slot t key = probe ((key `xor` (key `shiftR` 15)) .&. mask t)
  where
    probe : Int -> IO Int
    probe i = do
      k <- readArray (keys t) i
      case k of
        Nothing => do set (keys t) i key; set (counts t) i 0; pure i
        Just k' => if k' == key then pure i else probe ((i + 1) .&. mask t)

bump : Table -> Int -> IO ()
bump t key = do
  i <- slot t key
  c <- get (counts t) i
  set (counts t) i (c + 1)

countOf : Table -> Int -> IO Int
countOf t key = do i <- slot t key; get (counts t) i

-- 4^k, the number of fragments of k nucleotides.
fragments : Int -> Int
fragments k = if k <= 0 then 1 else 4 * fragments (k - 1)

-- Every fragment of k codes in seq[0..len), counted.
count : IOArray Int -> Int -> Int -> IO Table
count seq len k = do
  let n = len - k + 1
  t <- newTable (if n < 4096 then 4096 else n)
  roll t (fragments k - 1) 0 0
  pure t
  where
    roll : Table -> Int -> Int -> Int -> IO ()
    roll t mask key i =
      if i >= len
         then pure ()
         else do c <- get seq i
                 let key' = ((key `shiftL` 2) .|. c) .&. mask
                 when (i >= k - 1) (bump t key')
                 roll t mask key' (i + 1)

letter : Int -> Char
letter 0 = 'A'
letter 1 = 'C'
letter 2 = 'T'
letter _ = 'G'

-- The k letters of a key, first letter in the highest bits.
name : Int -> Int -> String
name k key = pack (go k key [])
  where
    go : Int -> Int -> List Char -> List Char
    go 0 _ acc = acc
    go j rest acc = go (j - 1) (rest `shiftR` 2) (letter (rest .&. 3) :: acc)

packed : String -> Int
packed s = foldl (\key, c => key * 4 + code c) 0 (unpack s)

fixed : Nat -> Double -> String
fixed d x =
  let scale = cast {to = Int} (pow 10.0 (cast d))
      s = cast {to = Int} (x * cast scale + 0.5)
      frac = show (s `mod` scale)
  in show (s `div` scale) ++ "." ++ pack (replicate (minus d (length frac)) '0') ++ frac

byFrequency : (String, Int) -> (String, Int) -> Ordering
byFrequency (k1, c1) (k2, c2) = case compare c2 c1 of
  EQ => compare k1 k2
  o => o

frequencies : IOArray Int -> Int -> Int -> IO ()
frequencies seq len k = do
  t <- count seq len k
  counts <- traverse (\key => do c <- countOf t key; pure (name k key, c))
              [0 .. fragments k - 1]
  let denom = cast (len - k + 1)
  traverse_ (\(key, c) => putStrLn (key ++ " " ++ fixed 3 (100.0 * cast c / denom)))
    (sortBy byFrequency counts)
  putStrLn ""

fragment : IOArray Int -> Int -> String -> IO ()
fragment seq len frag = do
  let k = cast (length frag)
  t <- count seq len k
  n <- countOf t (packed frag)
  putStrLn (show n ++ "\t" ++ frag)

main : IO ()
main = do
  skipToThree
  start <- newArray (1 `shiftL` 20)
  MkCodes seq _ len <- readSequence (MkCodes start (1 `shiftL` 20) 0)
  frequencies seq len 1
  frequencies seq len 2
  traverse_ (fragment seq len) ["GGT", "GGTA", "GGTATT", "GGTATTTTAATT", "GGTATTTTAATTTATAGT"]
