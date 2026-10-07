module Main

-- reverse-complement (the Benchmarks Game): each FASTA record's sequence
-- reversed and complemented, written 60 characters to a line. The input is
-- one byte buffer, the complement a 256-byte table, and each sequence a
-- byte buffer: the same bytes the single-threaded C entry writes, without
-- a cons cell per character.

import Prelude
import Data.Buffer
import System.File

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

byte : Char -> Bits8
byte c = cast (ord c)

nl : Bits8
nl = byte '\n'

gt : Bits8
gt = byte '>'

-- A non-negative size is a buffer; a negative one is empty, and nothing here
-- asks for a negative size.
alloc : Int -> IO Buffer
alloc n = do
  Just buf <- newBuffer n
    | Nothing => emptyBuffer
  pure buf

-- Identity, then the complement of every byte: the case split above, once.
complement : IO Buffer
complement = do
  t <- alloc 256
  fill t 0
  pure t
  where
    fill : Buffer -> Int -> IO ()
    fill t i =
      if i >= 256 then pure ()
      else do
        setBits8 t i (byte (comp (chr i)))
        fill t (i + 1)

copy : Buffer -> Int -> Buffer -> Int -> Int -> IO ()
copy src si dst di n = go 0
  where
    go : Int -> IO ()
    go k =
      if k >= n then pure ()
      else do
        b <- getBits8 src (si + k)
        setBits8 dst (di + k) b
        go (k + 1)

-- The whole input. A short read is the end (the runtime reads until the
-- buffer is full or the input ends); a full buffer is doubled.
readAll : IO (Buffer, Int)
readAll = do
  let cap = 1048576
  buf <- alloc cap
  go buf cap 0
  where
    go : Buffer -> Int -> Int -> IO (Buffer, Int)
    go buf cap len = do
      Right n <- readBufferData stdin buf len (cap - len)
        | Left _ => pure (buf, len)
      let len' = len + n
      if n == 0 || len' < cap then pure (buf, len')
        else do
          let cap' = cap * 2
          bigger <- alloc cap'
          copy buf 0 bigger 0 len'
          go bigger cap' len'

rev : Buffer -> Int -> Int -> IO ()
rev buf i j =
  if i >= j then pure ()
  else do
    a <- getBits8 buf i
    b <- getBits8 buf j
    setBits8 buf i b
    setBits8 buf j a
    rev buf (i + 1) (j - 1)

-- Reversed sequence, 60 bytes to a line, one write of the lines.
putSequence : Buffer -> Int -> IO ()
putSequence seq slen =
  if slen <= 0 then pure ()
  else do
    rev seq 0 (slen - 1)
    let lines = (slen + 59) `div` 60
    let outLen = slen + lines
    out <- alloc outLen
    pack seq out 0 0
    ignore (writeBufferData stdout out 0 outLen)
  where
    pack : Buffer -> Buffer -> Int -> Int -> IO ()
    pack seq out si oi =
      if si >= slen then pure ()
      else do
        let m = if slen - si < 60 then slen - si else 60
        copy seq si out oi m
        setBits8 out (oi + m) nl
        pack seq out (si + m) (oi + m + 1)

-- The next newline, or `len` when the header runs to the end.
findNl : Buffer -> Int -> Int -> IO Int
findNl buf len i =
  if i >= len then pure len
  else do
    b <- getBits8 buf i
    if b == nl then pure i else findNl buf len (i + 1)

-- As the C entry: a header is written and the sequence that follows is
-- accumulated complemented; a newline is not part of the sequence; the
-- sequence is written when the next header, or the end, arrives.
process : Buffer -> Int -> Buffer -> Buffer -> IO ()
process input len table seq = go 0 0
  where
    mutual
      go : Int -> Int -> IO ()
      go i slen =
        if i >= len then putSequence seq slen
        else do
          b <- getBits8 input i
          step b i slen

      step : Bits8 -> Int -> Int -> IO ()
      step b i slen =
        if b == gt then do
          putSequence seq slen
          j <- findNl input len i
          ignore (writeBufferData stdout input i (j - i))
          putChar '\n'
          go (j + 1) 0
        else if b == nl then go (i + 1) slen
        else do
          c <- getBits8 table (cast b)
          setBits8 seq slen c
          go (i + 1) (slen + 1)

main : IO ()
main = do
  (input, len) <- readAll
  table <- complement
  seq <- alloc len
  process input len table seq
