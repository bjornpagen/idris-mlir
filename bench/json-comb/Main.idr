-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Main

-- JSON and arithmetic expressions over a parser-combinator library in the
-- classic style: a parser is a function from the input and a position to
-- a failure or a value and the position after it, wrapped in a record so
-- that it is a Functor, an Applicative, a Monad and an Alternative, as
-- Parsec-like libraries are; alternatives backtrack. The same lines and
-- the same summary as json-hand, which parses them by hand: the distance
-- between the two is what composing parsers as closures costs, which only
-- specializing the combinators on the parsers they are given removes.
-- Partial where base's strIndex is.

import Prelude
import Data.String

%default partial

------------------------------------------------------------------------------
-- The combinators
------------------------------------------------------------------------------

record Input where
  constructor MkInput
  text : String
  len : Int

data Res a = Fail | Ok a Int

record Parser a where
  constructor MkP
  run : Input -> Int -> Res a

Functor Parser where
  map f (MkP p) = MkP (\s, i => case p s i of
                                  Fail => Fail
                                  Ok x j => Ok (f x) j)

Applicative Parser where
  pure x = MkP (\_, i => Ok x i)
  MkP pf <*> MkP px = MkP (\s, i => case pf s i of
      Fail => Fail
      Ok f j => case px s j of
        Fail => Fail
        Ok x k => Ok (f x) k)

Monad Parser where
  MkP p >>= k = MkP (\s, i => case p s i of
      Fail => Fail
      Ok x j => run (k x) s j)

Alternative Parser where
  empty = MkP (\_, _ => Fail)
  MkP p <|> q = MkP (\s, i => case p s i of
      Fail => run q s i
      Ok x j => Ok x j)

satisfy : (Char -> Bool) -> Parser Char
satisfy f = MkP (\s, i =>
  if i < s.len
    then let c = strIndex s.text i in if f c then Ok c (i + 1) else Fail
    else Fail)

char : Char -> Parser Char
char c = satisfy (== c)

string : String -> Parser String
string w = map pack (traverse char (unpack w))

many : Parser a -> Parser (List a)
many p = MkP (\s, i => case run p s i of
  Fail => Ok [] i
  Ok x j => case run (many p) s j of
    Ok xs k => Ok (x :: xs) k
    Fail => Ok [x] j)

some : Parser a -> Parser (List a)
some p = [| p :: many p |]

sepBy1 : Parser a -> Parser s -> Parser (List a)
sepBy1 p sep = [| p :: many (sep *> p) |]

sepBy : Parser a -> Parser s -> Parser (List a)
sepBy p sep = sepBy1 p sep <|> pure []

between : Parser o -> Parser c -> Parser a -> Parser a
between o c p = o *> p <* c

chainl1 : Parser a -> Parser (a -> a -> a) -> Parser a
chainl1 p op = p >>= rest
  where
    rest : a -> Parser a
    rest x = (do f <- op; y <- p; rest (f x y)) <|> pure x

optional : Parser a -> Parser (Maybe a)
optional p = map Just p <|> pure Nothing

eof : Parser ()
eof = MkP (\s, i => if i >= s.len then Ok () i else Fail)

parse : Parser a -> String -> Maybe a
parse p t = case run p (MkInput t (strLength t)) 0 of
  Ok x _ => Just x
  Fail => Nothing

------------------------------------------------------------------------------
-- JSON and expressions
------------------------------------------------------------------------------

data JSON = JNull | JBool Bool | JNum Integer | JStr String
          | JArr (List JSON) | JObj (List (String, JSON))

spaces : Parser ()
spaces = ignore (many (satisfy isSpace))

token : Parser a -> Parser a
token p = p <* spaces

symbol : Char -> Parser Char
symbol c = token (char c)

digits : Parser Integer
digits = map (foldl (\acc, d => acc * 10 + cast (ord d - 48)) 0) (some (satisfy isDigit))

number : Parser Integer
number = token (do
  neg <- optional (char '-')
  n <- digits
  pure (maybe n (const (negate n)) neg))

str : Parser String
str = token (char '"' *> map pack (many (satisfy (/= '"'))) <* char '"')

keyword : String -> a -> Parser a
keyword w v = token (string w) $> v

-- A recursive parser runs its alternatives inside the function its record
-- holds, so building it does not build itself.
mutual
  value : Parser JSON
  value = MkP (\s, i => run alternatives s i)
    where
      alternatives : Parser JSON
      alternatives = keyword "null" JNull
                 <|> keyword "true" (JBool True)
                 <|> keyword "false" (JBool False)
                 <|> map JNum number
                 <|> map JStr str
                 <|> map JArr array
                 <|> map JObj object

  array : Parser (List JSON)
  array = between (symbol '[') (symbol ']') (sepBy value (symbol ','))

  member : Parser (String, JSON)
  member = [| MkPair str (symbol ':' *> value) |]

  object : Parser (List (String, JSON))
  object = between (symbol '{') (symbol '}') (sepBy member (symbol ','))

mutual
  expr : Parser Integer
  expr = MkP (\s, i => run (chainl1 term addop) s i)

  term : Parser Integer
  term = chainl1 factor mulop

  factor : Parser Integer
  factor = number <|> between (symbol '(') (symbol ')') expr

  addop : Parser (Integer -> Integer -> Integer)
  addop = (symbol '+' $> (+)) <|> (symbol '-' $> (-))

  mulop : Parser (Integer -> Integer -> Integer)
  mulop = (symbol '*' $> (*)) <|> (symbol '/' $> div)

size : JSON -> Integer
size (JArr xs) = 1 + sum (map size xs)
size (JObj ms) = 1 + sum (map (size . snd) ms)
size _ = 1

numbers : JSON -> Integer
numbers (JNum n) = n
numbers (JArr xs) = sum (map numbers xs)
numbers (JObj ms) = sum (map (numbers . snd) ms)
numbers _ = 0

-- What the lines so far were.
record Tally where
  constructor MkTally
  jsonLines, nodes, jsonSum, exprLines, exprSum, errorLines : Integer

-- A line: a JSON value when one spans it, else an expression when one
-- does, else neither.
tally : Tally -> String -> Tally
tally s t = case parse (spaces *> value <* eof) t of
  Just j => { jsonLines $= (+ 1), nodes $= (+ size j), jsonSum $= (+ numbers j) } s
  Nothing => case parse (spaces *> expr <* eof) t of
    Just v => { exprLines $= (+ 1), exprSum $= (+ v) } s
    Nothing => { errorLines $= (+ 1) } s

loop : Tally -> IO Tally
loop s = do
  t <- getLine
  if t == "" then pure s else loop (tally s t)

report : Tally -> IO ()
report s = do
  putStrLn ("json " ++ show s.jsonLines ++ " size " ++ show s.nodes ++ " sum " ++ show s.jsonSum)
  putStrLn ("expr " ++ show s.exprLines ++ " sum " ++ show s.exprSum)
  putStrLn ("error " ++ show s.errorLines)

main : IO ()
main = loop (MkTally 0 0 0 0 0 0) >>= report
