-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Main

-- JSON and arithmetic expressions over linear parser combinators in the
-- manner of typed algebraic parsing: nothing backtracks inside a parse, a
-- parser carries the set of bytes it may start with and whether it
-- accepts nothing, and a choice reads one byte of lookahead, held beside
-- the input. The input is all of stdin, read once into a buffer, frozen in
-- place behind a quantity-1 handle (Linear.Bytes) and parsed line by line
-- with no copy; only a line that is no JSON value is read again, from its
-- start, as an expression. The same lines and summary as json-hand, which
-- parses them by hand, and json-comb, whose combinators backtrack.

import Prelude
import Data.Buffer
import System.File
import Linear.Notation
import Array
import Linear.Bytes

%default covering

------------------------------------------------------------------------------
-- The combinators
------------------------------------------------------------------------------

-- Where a parse is: past the end, or at a byte, which is the lookahead,
-- at its offset; the handle beside it either way.
data St : (0 r : Type) -> (0 n : Nat) -> Type where
  AtEnd : (pos : Nat) -> (1 input : Bytes r n) -> St r n
  At : (c : Bits8) -> (pos : Nat) -> (1 input : Bytes r n) -> St r n

data LRes : (0 r : Type) -> (0 n : Nat) -> Type -> Type where
  LFail : (1 st : St r n) -> LRes r n a
  LOk : a -> (1 st : St r n) -> LRes r n a

data Nullability = Nullable | Consuming

record LP (0 r : Type) (0 n : Nat) (a : Type) where
  constructor MkLP
  firstSet : Bits8 -> Bool
  emptiness : Nullability
  runLP : (1 _ : St r n) -> LRes r n a

atByte : (pos : Nat) -> (1 _ : Peeked r n pos) -> St r n
atByte pos (End input) = AtEnd pos input
atByte pos (Byte input b _) = At b pos input

advance : Nat -> (1 _ : Bytes r n) -> St r n
advance pos input = atByte pos (peek input pos)

release : (1 _ : St r n) -> Bytes r n
release (AtEnd _ input) = input
release (At _ _ input) = input

nullable : Nullability -> Bool
nullable Nullable = True
nullable Consuming = False

both : Nullability -> Nullability -> Nullability
both Nullable Nullable = Nullable
both _ _ = Consuming

oneOf : Nullability -> Nullability -> Nullability
oneOf Consuming Consuming = Consuming
oneOf _ _ = Nullable

satisfyRun : (Bits8 -> Bool) -> (1 _ : St r n) -> LRes r n Bits8
satisfyRun f (AtEnd pos input) = LFail (AtEnd pos input)
satisfyRun f (At c pos input) = if f c then LOk c (advance (S pos) input) else LFail (At c pos input)

satisfy : (Bits8 -> Bool) -> LP r n Bits8
satisfy f = MkLP f Consuming (satisfyRun f)

pureLP : a -> LP r n a
pureLP x = MkLP (const False) Nullable (LOk x)

mapRes : (a -> b) -> (1 _ : LRes r n a) -> LRes r n b
mapRes f (LFail st) = LFail st
mapRes f (LOk x st) = LOk (f x) st

mapLP : (a -> b) -> LP r n a -> LP r n b
mapLP f p = MkLP p.firstSet p.emptiness (\st => mapRes f (p.runLP st))

apRes : LP r n a -> (1 _ : LRes r n (a -> b)) -> LRes r n b
apRes q (LFail st) = LFail st
apRes q (LOk f st) = mapRes f (q.runLP st)

ap : LP r n (a -> b) -> LP r n a -> LP r n b
ap p q = MkLP (\c => p.firstSet c || (nullable p.emptiness && q.firstSet c))
              (both p.emptiness q.emptiness) (\st => apRes q (p.runLP st))

seqL : LP r n a -> LP r n b -> LP r n a
seqL p q = ap (mapLP (\x, _ => x) p) q

seqR : LP r n a -> LP r n b -> LP r n b
seqR p q = ap (mapLP (\_, y => y) p) q

-- The one byte of lookahead chooses: the parser that may start with it,
-- else the one that accepts nothing.
altRun : LP r n a -> LP r n a -> (1 _ : St r n) -> LRes r n a
altRun p q (AtEnd pos input) =
  if nullable p.emptiness then p.runLP (AtEnd pos input) else q.runLP (AtEnd pos input)
altRun p q (At c pos input) =
  if p.firstSet c then p.runLP (At c pos input)
  else if q.firstSet c then q.runLP (At c pos input)
  else if nullable p.emptiness then p.runLP (At c pos input)
  else q.runLP (At c pos input)

alt : LP r n a -> LP r n a -> LP r n a
alt p q = MkLP (\c => p.firstSet c || q.firstSet c) (oneOf p.emptiness q.emptiness) (altRun p q)

mutual
  manyGo : LP r n a -> SnocList a -> (1 _ : St r n) -> LRes r n (List a)
  manyGo p acc (AtEnd pos input) = LOk (acc <>> []) (AtEnd pos input)
  manyGo p acc (At c pos input) =
    if p.firstSet c
      then manyStep p acc (p.runLP (At c pos input))
      else LOk (acc <>> []) (At c pos input)

  manyStep : LP r n a -> SnocList a -> (1 _ : LRes r n a) -> LRes r n (List a)
  manyStep p acc (LFail st) = LFail st
  manyStep p acc (LOk x st) = manyGo p (acc :< x) st

many : LP r n a -> LP r n (List a)
many p = MkLP p.firstSet Nullable (manyGo p [<])

some : LP r n a -> LP r n (List a)
some p = ap (mapLP (::) p) (many p)

sepBy : LP r n a -> LP r n s -> LP r n (List a)
sepBy p sep = alt (ap (mapLP (::) p) (many (seqR sep p))) (pureLP [])

between : LP r n o -> LP r n c -> LP r n a -> LP r n a
between o c p = seqL (seqR o p) c

------------------------------------------------------------------------------
-- JSON and expressions
------------------------------------------------------------------------------

data JSON = JNull | JBool Bool | JNum Integer | JStr | JArr (List JSON) | JObj (List JSON)

-- A line ends at its newline, so a space is any blank but that.
isBlank : Bits8 -> Bool
isBlank b = b == 32 || b == 9 || b == 13

isDigitByte : Bits8 -> Bool
isDigitByte b = b >= 48 && b <= 57

bytesOf : String -> List Bits8
bytesOf s = map (\ch => cast (ord ch)) (unpack s)

spaces : LP r n ()
spaces = mapLP (const ()) (many (satisfy isBlank))

token : LP r n a -> LP r n a
token p = seqL p spaces

symbol : Bits8 -> LP r n Bits8
symbol c = token (satisfy (== c))

word : List Bits8 -> LP r n ()
word [] = pureLP ()
word (c :: cs) = seqR (satisfy (== c)) (word cs)

keyword : String -> a -> LP r n a
keyword w v = token (mapLP (const v) (word (bytesOf w)))

digitsValue : List Bits8 -> Integer
digitsValue = foldl (\acc, d => acc * 10 + cast d - 48) 0

signed : Bool -> Integer -> Integer
signed neg v = if neg then negate v else v

-- A number is read as its value while it is parsed.
number : LP r n Integer
number = token (ap (mapLP signed (alt (mapLP (const True) (satisfy (== 45))) (pureLP False)))
                   (mapLP digitsValue (some (satisfy isDigitByte))))

str : LP r n ()
str = token (mapLP (const ()) (between (satisfy (== 34)) (satisfy (== 34))
                                        (many (satisfy (\b => b /= 34 && b /= 10)))))

valueFirst : Bits8 -> Bool
valueFirst c = c == 110 || c == 116 || c == 102 || c == 34 || c == 91 || c == 123 || c == 45 || isDigitByte c

-- A recursive parser runs its alternatives inside the function its record
-- holds, so building it does not build itself.
mutual
  value : LP r n JSON
  value = MkLP valueFirst Consuming (\st => valueAlternatives.runLP st)

  valueAlternatives : LP r n JSON
  valueAlternatives =
    alt (keyword "null" JNull)
      (alt (keyword "true" (JBool True))
        (alt (keyword "false" (JBool False))
          (alt (mapLP JNum number)
            (alt (mapLP (const JStr) str)
              (alt (mapLP JArr array) (mapLP JObj object))))))

  array : LP r n (List JSON)
  array = between (symbol 91) (symbol 93) (sepBy value (symbol 44))

  member : LP r n JSON
  member = seqR str (seqR (symbol 58) value)

  object : LP r n (List JSON)
  object = between (symbol 123) (symbol 125) (sepBy member (symbol 44))

exprFirst : Bits8 -> Bool
exprFirst c = c == 40 || c == 45 || isDigitByte c

applyAll : Integer -> List (Integer -> Integer -> Integer, Integer) -> Integer
applyAll acc [] = acc
applyAll acc ((f, y) :: rest) = applyAll (f acc y) rest

addop : LP r n (Integer -> Integer -> Integer)
addop = alt (mapLP (const (+)) (symbol 43)) (mapLP (const (-)) (symbol 45))

mulop : LP r n (Integer -> Integer -> Integer)
mulop = alt (mapLP (const (*)) (symbol 42)) (mapLP (const div) (symbol 47))

mutual
  expr : LP r n Integer
  expr = ap (mapLP applyAll term) (many (ap (mapLP MkPair addop) term))

  inner : LP r n Integer
  inner = MkLP exprFirst Consuming (\st => expr.runLP st)

  term : LP r n Integer
  term = ap (mapLP applyAll factor) (many (ap (mapLP MkPair mulop) factor))

  factor : LP r n Integer
  factor = alt number (between (symbol 40) (symbol 41) inner)

size : JSON -> Integer
size (JArr xs) = 1 + sum (map size xs)
size (JObj ms) = 1 + sum (map size ms)
size _ = 1

numbers : JSON -> Integer
numbers (JNum n) = n
numbers (JArr xs) = sum (map numbers xs)
numbers (JObj ms) = sum (map numbers ms)
numbers _ = 0

------------------------------------------------------------------------------
-- The lines
------------------------------------------------------------------------------

-- What the lines so far were.
record Tally where
  constructor MkTally
  jsonLines, nodes, jsonSum, exprLines, exprSum, errorLines : Integer

jsonLine : LP r n JSON
jsonLine = seqR spaces value

exprLine : LP r n Integer
exprLine = seqR spaces expr

-- Every line from `pos` on, into the tally: a JSON value when one spans
-- the line, else an expression when one does, else neither, skipped to
-- its newline. A parse that ends at the newline or the end has spanned
-- its line.
mutual
  linesFrom : Tally -> Nat -> (1 _ : Bytes r n) -> Res Tally (const (Bytes r n))
  linesFrom s pos input = startLine s pos (peek input pos)

  startLine : Tally -> (pos : Nat) -> (1 _ : Peeked r n pos) -> Res Tally (const (Bytes r n))
  startLine s pos (End input) = s # input
  startLine s pos (Byte input _ _) = tryJson s pos (jsonLine.runLP (advance pos input))

  tryJson : Tally -> Nat -> (1 _ : LRes r n JSON) -> Res Tally (const (Bytes r n))
  tryJson s pos (LOk j (At 10 q input)) = linesFrom (json j s) (S q) input
  tryJson s pos (LOk j (AtEnd q input)) = linesFrom (json j s) q input
  tryJson s pos (LOk j st) = tryExpr s pos (exprLine.runLP (advance pos (release st)))
  tryJson s pos (LFail st) = tryExpr s pos (exprLine.runLP (advance pos (release st)))

  tryExpr : Tally -> Nat -> (1 _ : LRes r n Integer) -> Res Tally (const (Bytes r n))
  tryExpr s pos (LOk v (At 10 q input)) = linesFrom ({ exprLines $= (+ 1), exprSum $= (+ v) } s) (S q) input
  tryExpr s pos (LOk v (AtEnd q input)) = linesFrom ({ exprLines $= (+ 1), exprSum $= (+ v) } s) q input
  tryExpr s pos (LOk v st) = skipLine ({ errorLines $= (+ 1) } s) pos (release st)
  tryExpr s pos (LFail st) = skipLine ({ errorLines $= (+ 1) } s) pos (release st)

  skipLine : Tally -> Nat -> (1 _ : Bytes r n) -> Res Tally (const (Bytes r n))
  skipLine s at input = skipAt s at (peek input at)

  skipAt : Tally -> (at : Nat) -> (1 _ : Peeked r n at) -> Res Tally (const (Bytes r n))
  skipAt s at (End input) = s # input
  skipAt s at (Byte input b _) = if b == 10 then linesFrom s (S at) input else skipLine s (S at) input

  json : JSON -> Tally -> Tally
  json j s = { jsonLines $= (+ 1), nodes $= (+ size j), jsonSum $= (+ numbers j) } s

-- The input's bytes, frozen in place for the parse and thawed back after.
summary : (n : Nat) -> Array [<n] Bits8 -> Tally
summary n arr = unrestricted (LArray.thaw arr (\buf => withBytes buf (\input => linesFrom (MkTally 0 0 0 0 0 0) 0 input) done))
  where
    done : Tally -> (1 _ : LArray [<n] Bits8) -> !* Tally
    done s buf = let MkBang _ = LArray.freeze buf in MkBang s

------------------------------------------------------------------------------
-- The input
------------------------------------------------------------------------------

-- A non-negative size is a buffer; nothing here asks for a negative one.
alloc : Int -> IO Buffer
alloc n = do
  Just buf <- newBuffer n
    | Nothing => emptyBuffer
  pure buf

copyBytes : Buffer -> Buffer -> Int -> IO ()
copyBytes src dst n = go 0
  where
    go : Int -> IO ()
    go j =
      if j >= n then pure ()
      else do
        b <- getBits8 src j
        setBits8 dst j b
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
          copyBytes buf bigger len'
          go bigger cap' len'

report : Tally -> IO ()
report s = do
  putStrLn ("json " ++ show s.jsonLines ++ " size " ++ show s.nodes ++ " sum " ++ show s.jsonSum)
  putStrLn ("expr " ++ show s.exprLines ++ " sum " ++ show s.exprSum)
  putStrLn ("error " ++ show s.errorLines)

main : IO ()
main = do
  (buf, len) <- readAll
  let n : Nat = cast len
  arr <- bufferBytes buf n
  report (summary n arr)
