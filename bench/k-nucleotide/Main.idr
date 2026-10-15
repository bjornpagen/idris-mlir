-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Main

-- k-nucleotide (the Benchmarks Game): the frequencies of nucleotides and
-- pairs in the third sequence of a FASTA input, then the counts of five
-- longer fragments. The sequence is a byte per nucleotide. Each fragment
-- is a key packed two bits a nucleotide and rolled along it, counted in
-- one open-addressing table: a slot is the key beside its count, an empty
-- slot is a zero key, and the same hash as the C (`key ^ (key >> 15)`).
-- The table holds twice as many slots as there are fragments to count, or
-- twice the 4^k possible keys when that is fewer: a 1-mer has four keys.
-- The table is a linear array (Array's LArray) threaded through the counting
-- loop at quantity 1 and frozen for the lookups; the sequence is an array
-- copied once out of the input buffer. A slot or a position the program
-- computes is checked against its array where it is used; the program keeps
-- every one inside it.

import Prelude
import Data.Bits
import Data.Buffer
import Data.List
import Linear.Notation
import Array
import System.File

record Slot where
  constructor MkSlot
  k : Int
  n : Int

-- A nucleotide's code, the same for either case: A 0, C 1, T 2, G 3.
codeOf : Bits8 -> Bits8
codeOf b =
  let v : Int = cast b
  in cast ((v `shiftR` 1) .&. 3)

nl : Bits8
nl = cast (ord '\n')

gt : Bits8
gt = cast (ord '>')

-- A non-negative size is a buffer; a negative one is empty, and nothing here
-- asks for a negative size.
alloc : Int -> IO Buffer
alloc n = do
  Just buf <- newBuffer n
    | Nothing => emptyBuffer
  pure buf

copy : Buffer -> Int -> Buffer -> Int -> Int -> IO ()
copy src si dst di n = go 0
  where
    go : Int -> IO ()
    go j =
      if j >= n then pure ()
      else do
        b <- getBits8 src (si + j)
        setBits8 dst (di + j) b
        go (j + 1)

-- The whole input. A short read is the end; a full buffer is doubled.
readAll : IO (Buffer, Int)
readAll = do
  buf <- alloc 1048576
  go buf 1048576 0
  where
    go : Buffer -> Int -> Int -> IO (Buffer, Int)
    go buf cap len = do
      Right got <- readBufferData stdin buf len (cap - len)
        | Left _ => pure (buf, len)
      let len' = len + got
      if got == 0 || len' < cap then pure (buf, len')
        else do
          let cap' = cap * 2
          bigger <- alloc cap'
          copy buf 0 bigger 0 len'
          go bigger cap' len'

-- True when buf[start..end) begins with ">THREE".
startsThree : Buffer -> Int -> Int -> IO Bool
startsThree buf start end = go 0
  where
    pat : Int -> Bits8
    pat 0 = gt
    pat 1 = cast (ord 'T')
    pat 2 = cast (ord 'H')
    pat 3 = cast (ord 'R')
    pat 4 = cast (ord 'E')
    pat _ = cast (ord 'E')
    go : Int -> IO Bool
    go j =
      if j >= 6 then pure True
      else if start + j >= end then pure False
      else do
        b <- getBits8 buf (start + j)
        if b == pat j then go (j + 1) else pure False

-- The index just after the ">THREE" line, or `len` when there is none.
findThree : Buffer -> Int -> IO Int
findThree buf len = line 0 0
  where
    line : Int -> Int -> IO Int
    line i start =
      if i >= len then pure len
      else do
        b <- getBits8 buf i
        if b /= nl then line (i + 1) start
          else do
            yes <- startsThree buf start i
            if yes then pure (i + 1) else line (i + 1) (i + 1)

-- The third sequence as codes, newlines dropped, up to the next header.
codesOf : Buffer -> Int -> Int -> IO (Buffer, Int)
codesOf input len from = do
  out <- alloc (len - from)
  n <- take input from out 0
  pure (out, n)
  where
    take : Buffer -> Int -> Buffer -> Int -> IO Int
    take input i out used =
      if i >= len then pure used
      else do
        b <- getBits8 input i
        if b == gt then pure used
          else if b == nl then take input (i + 1) out used
          else do
            setBits8 out used (codeOf b)
            take input (i + 1) out (used + 1)

-- 4^k, the number of fragments of k nucleotides.
fragments : Int -> Int
fragments k = if k <= 0 then 1 else 4 * fragments (k - 1)

-- Twice the fragments, or twice the possible keys when fewer of those exist.
capacity : Int -> Int -> Int
capacity nfrag k =
  let need = max 1 (min nfrag (fragments k))
  in grow 1 need
  where
    grow : Int -> Int -> Int
    grow c need = if c < 2 * need then grow (c * 2) need else c

slotOf : Int -> Int -> Int
slotOf key mask = (key `xor` (key `shiftR` 15)) .&. mask

-- Position i of an array of cap, when it is one.
position : (cap : Nat) -> Int -> Maybe (Fin cap)
position cap i = if i < 0 then Nothing else checkIndex cap (cast i)

Slots : Nat -> Type
Slots cap = LArray [<cap] Slot

-- The slot at i, with the table given back (an empty slot past the end).
slotAt : {cap : Nat} -> (1 _ : Slots cap) -> Int -> Res Slot (const (Slots cap))
slotAt t i = case position cap i of
  Just j => read t [<j]
  Nothing => MkSlot 0 0 # t

-- The table with s at i (unchanged past the end).
store : {cap : Nat} -> (1 _ : Slots cap) -> Int -> Slot -> Slots cap
store t i s = case position cap i of
  Just j => write t [<j] s
  Nothing => t

-- `frag` is stored as frag + 1, so a zero key is the empty slot.
bump : {cap : Nat} -> (1 _ : Slots cap) -> Int -> Int -> Int -> Slots cap
bump a mask frag i =
  let s # a1 = slotAt a i in
  if s.k == 0 then store a1 i (MkSlot (frag + 1) 1)
    else if s.k == frag + 1 then store a1 i (MkSlot (frag + 1) (s.n + 1))
    else bump a1 mask frag ((i + 1) .&. mask)

-- The counts of one fragment length: the frozen table, its size and its
-- mask.
record Counts where
  constructor MkCounts
  size : Nat
  slots : Vector size Slot
  mask : Int

-- The counting loop over the sequence: its own test of the position
-- against the sequence's length gives the position it reads.
roll : {n, cap : Nat} -> Vector n Bits8 -> Int -> (1 _ : Slots cap) -> Int -> Int -> Int -> Nat -> Slots cap
roll codes k table mask keyMask key i =
  case checkIndex n i of
    Nothing => table
    Just j =>
      let c : Int = cast (codes !! [<j])
          key' = ((key `shiftL` 2) .|. c) .&. keyMask
          table' = if cast i >= k - 1
                      then bump table mask key' (slotOf key' mask)
                      else table
      in roll codes k table' mask keyMask key' (S i)

-- The counts of the fragments of length k: a fresh table threaded through
-- the counting loop, then frozen. The sequence is a value, so the loop is
-- pure, and the buffer it came from is not carried through it, where it
-- would be retained and released on every nucleotide.
tally : {n : Nat} -> Vector n Bits8 -> Int -> Counts
tally codes k =
  let len = cast {to = Int} n
      nfrag = if len >= k then len - k + 1 else 0
      cap = capacity nfrag k
      mask = cap - 1
      keyMask = fragments k - 1
      size = cast {to = Nat} cap
      frozen = unrestricted (withArray [<size] (MkSlot 0 0) (\t => freeze (roll codes k t mask keyMask 0 0)))
  in MkCounts size frozen mask

found : Counts -> Int -> Int
found (MkCounts size t mask) frag = go (slotOf frag mask)
  where
    go : Int -> Int
    go i = case position size i of
      Nothing => 0
      Just j =>
        let s = t !! [<j] in
        if s.k == 0 then 0
          else if s.k == frag + 1 then s.n
          else go ((i + 1) .&. mask)

letter : Int -> Char
letter 0 = 'A'
letter 1 = 'C'
letter 2 = 'T'
letter _ = 'G'

name : Int -> Int -> String
name k key = pack (go k key [])
  where
    go : Int -> Int -> List Char -> List Char
    go 0 _ acc = acc
    go j rest acc = go (j - 1) (rest `shiftR` 2) (letter (rest .&. 3) :: acc)

packed : String -> Int
packed s = foldl (\key, c => key * 4 + code c) 0 (unpack s)
  where
    code : Char -> Int
    code c = (ord c `shiftR` 1) .&. 3

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

frequencies : {n : Nat} -> Vector n Bits8 -> Int -> IO ()
frequencies seq k = do
  let t = tally seq k
  let counts = map (\key => (name k key, found t key)) [0 .. fragments k - 1]
  let denom = cast (cast n - k + 1)
  traverse_ (\(key, c) => putStrLn (key ++ " " ++ fixed 3 (100.0 * cast c / denom)))
    (sortBy byFrequency counts)
  putStrLn ""

fragment : {n : Nat} -> Vector n Bits8 -> String -> IO ()
fragment seq frag = do
  let k = cast (length frag)
      t = tally seq k
  putStrLn (show (found t (packed frag)) ++ "\t" ++ frag)

main : IO ()
main = do
  (input, len) <- readAll
  from <- findThree input len
  (seq, n) <- codesOf input len from
  -- One copy out of the IO buffer, then the counts are pure loops over it.
  codes <- tabulateIO [<cast n] (\[<i] => getBits8 seq (cast (finToNat i)))
  frequencies codes 1
  frequencies codes 2
  traverse_ (fragment codes) ["GGT", "GGTA", "GGTATT", "GGTATTTTAATT", "GGTATTTTAATTTATAGT"]
