-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Main

-- JSON and arithmetic expressions over the library's linear parser
-- (Linear.Parser): all of stdin read once into a buffer, frozen in place
-- behind a quantity-1 handle to immutable bytes, and parsed line by line
-- with no copy. Each parser gives the handle back whether it succeeds or
-- fails, so a choice runs its second parser on the same handle from the
-- same offset, and a line that is no JSON value is read again from its
-- start as an expression; a string is a view of the bytes, two offsets.
-- The same lines and summary as json-hand, which parses them by hand, and
-- json-comb and json-linear, the other combinator libraries.

import Prelude
import Data.Buffer
import System.File
import Linear.Notation
import Array
import Linear.Parser

%default covering

data JSON = JNull | JBool Bool | JNum Integer | JStr | JArr (List JSON) | JObj (List JSON)

-- A line ends at its newline, so a space is any blank but that.
isBlank : Bits8 -> Bool
isBlank b = b == 32 || b == 9 || b == 13

isDigitByte : Bits8 -> Bool
isDigitByte b = b >= 48 && b <= 57

bytesOf : String -> List Bits8
bytesOf s = map (\ch => cast (ord ch)) (unpack s)

digitsValue : List Bits8 -> Integer
digitsValue = foldl (\acc, d => acc * 10 + cast d - 48) 0

signed : Bool -> Integer -> Integer
signed neg v = if neg then negate v else v

spaces : Parser r n ()
spaces = spanWhile isBlank >>= \_ => pure ()

token : Parser r n a -> Parser r n a
token p = p >>= \x => spaces >>= \_ => pure x

symbol : Bits8 -> Parser r n Bits8
symbol c = token (byte c)

keyword : String -> a -> Parser r n a
keyword w v = token (literal (bytesOf w) >>= \_ => pure v)

sign : Parser r n Bool
sign = (byte 45 >>= \_ => pure True) <|> pure False

-- A number is read as its value while it is parsed.
number : Parser r n Integer
number = token (sign >>= \neg => some (satisfy isDigitByte) >>= \ds => pure (signed neg (digitsValue ds)))

-- A string is a view of the bytes between its quotes, kept nowhere.
str : Parser r n ()
str = token (byte 34 >>= \_ => spanWhile (\b => b /= 34 && b /= 10) >>= \_ => byte 34 >>= \_ => pure ())

sepBy : Parser r n a -> Parser r n s -> Parser r n (List a)
sepBy p sep = (p >>= \x => many (sep >>= \_ => p) >>= \xs => pure (x :: xs)) <|> pure []

between : Parser r n o -> Parser r n c -> Parser r n a -> Parser r n a
between o c p = o >>= \_ => p >>= \x => c >>= \_ => pure x

-- A recursive parser takes its arguments before it runs its alternatives,
-- so building it does not build itself.
mutual
  value : Parser r n JSON
  value input from within far = valueAlternatives input from within far

  valueAlternatives : Parser r n JSON
  valueAlternatives =
    keyword "null" JNull
      <|> keyword "true" (JBool True)
      <|> keyword "false" (JBool False)
      <|> map JNum number
      <|> map (const JStr) str
      <|> map JArr array
      <|> map JObj object

  array : Parser r n (List JSON)
  array = between (symbol 91) (symbol 93) (sepBy value (symbol 44))

  member : Parser r n JSON
  member = str >> (symbol 58 >>= \_ => value)

  object : Parser r n (List JSON)
  object = between (symbol 123) (symbol 125) (sepBy member (symbol 44))

-- Expressions: + - * / and parentheses, left associative; an operator
-- whose operand does not follow is left unread.
mutual
  expr : Parser r n Integer
  expr input from within far = (term >>= exprRest) input from within far

  exprRest : Integer -> Parser r n Integer
  exprRest acc =
    (symbol 43 >>= \_ => term >>= \v => exprRest (acc + v))
      <|> (symbol 45 >>= \_ => term >>= \v => exprRest (acc - v))
      <|> pure acc

  term : Parser r n Integer
  term = factor >>= termRest

  termRest : Integer -> Parser r n Integer
  termRest acc =
    (symbol 42 >>= \_ => factor >>= \v => termRest (acc * v))
      <|> (symbol 47 >>= \_ => factor >>= \v => termRest (div acc v))
      <|> pure acc

  factor : Parser r n Integer
  factor = number <|> (symbol 40 >>= \_ => expr >>= \v => symbol 41 >>= \_ => pure v)

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

lineEnd : Parser r n ()
lineEnd = (byte 10 >>= \_ => pure ()) <|> eof

jsonLine : Parser r n JSON
jsonLine = spaces >> (value >>= \j => lineEnd >> pure j)

exprLine : Parser r n Integer
exprLine = spaces >> (expr >>= \v => lineEnd >> pure v)

-- What is left of a line, and its newline or the end: never fails.
skipLine : Parser r n ()
skipLine = spanWhile (/= 10) >>= \_ => lineEnd

-- Every line from `from` on, into the tally: a JSON value when one spans
-- the line, else an expression when one does, else neither, skipped to
-- its newline. Each parse gives the handle back, so the next one runs on
-- it from where the line starts.
mutual
  linesFrom : Tally -> (1 _ : Bytes r n) -> (from : Nat) -> (0 _ : LTE from n) -> Res Tally (const (Bytes r n))
  linesFrom s input from within = startLine s from within (peek input from)

  startLine : Tally -> (from : Nat) -> (0 _ : LTE from n) -> (1 _ : Peeked r n from) -> Res Tally (const (Bytes r n))
  startLine s from within (End input) = s # input
  startLine s from within (Byte input _ _) = tryJson s from within (jsonLine input from within from)

  tryJson : Tally -> (from : Nat) -> (0 _ : LTE from n) -> (1 _ : Result r n JSON) -> Res Tally (const (Bytes r n))
  tryJson s from within (Ok input to fits _ j) =
    linesFrom ({ jsonLines $= (+ 1), nodes $= (+ size j), jsonSum $= (+ numbers j) } s) input to fits
  tryJson s from within (Fail input _) = tryExpr s from within (exprLine input from within from)

  tryExpr : Tally -> (from : Nat) -> (0 _ : LTE from n) -> (1 _ : Result r n Integer) -> Res Tally (const (Bytes r n))
  tryExpr s from within (Ok input to fits _ v) = linesFrom ({ exprLines $= (+ 1), exprSum $= (+ v) } s) input to fits
  tryExpr s from within (Fail input _) = skipped ({ errorLines $= (+ 1) } s) (skipLine input from within from)

  skipped : Tally -> (1 _ : Result r n ()) -> Res Tally (const (Bytes r n))
  skipped s (Ok input to fits _ _) = linesFrom s input to fits
  skipped s (Fail input _) = s # input

-- The input's bytes, frozen in place for the parse and thawed back after.
summary : (n : Nat) -> Array [<n] Bits8 -> Tally
summary n arr = unrestricted (LArray.thaw arr (\buf => withBytes buf (\input => linesFrom (MkTally 0 0 0 0 0 0) input 0 LTEZero) done))
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
