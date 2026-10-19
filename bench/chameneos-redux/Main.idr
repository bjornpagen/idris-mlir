-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
module Main

-- chameneos-redux (the Benchmarks Game): creatures go to one meeting place
-- in pairs, each pair takes the complement of its two colours, and the
-- place closes after n meetings. The game specifies one thread per
-- creature; threads are outside this compiler's language, so this is the
-- same workload under a deterministic cooperative scheduler: the creatures
-- that can run wait in a run queue, the one at its head goes to the place,
-- and a pair that has met joins the back of the queue, the creature that
-- was waiting first. The C in main.c is this algorithm too, and its output
-- is byte for byte this one's. With the queue in the order the creatures
-- were made, three creatures meet in rounds of three meetings and ten in
-- rounds of five, each creature twice or once a round, so for an n that is
-- a multiple of 15 every creature meets as often as every other and the
-- output is the game's published one (400 and 120 meetings each for
-- n = 600). The game's size is 6000000.

import Prelude

data Colour = Blue | Red | Yellow

colourName : Colour -> String
colourName Blue = "blue"
colourName Red = "red"
colourName Yellow = "yellow"

complement : Colour -> Colour -> Colour
complement Blue Blue = Blue
complement Blue Red = Yellow
complement Blue Yellow = Red
complement Red Blue = Yellow
complement Red Red = Red
complement Red Yellow = Blue
complement Yellow Blue = Red
complement Yellow Red = Blue
complement Yellow Yellow = Yellow

record Creature where
  constructor MkCreature
  ident : Int
  colour : Colour
  meetings : Int
  selfMeetings : Int

digitName : Char -> String
digitName '0' = "zero"
digitName '1' = "one"
digitName '2' = "two"
digitName '3' = "three"
digitName '4' = "four"
digitName '5' = "five"
digitName '6' = "six"
digitName '7' = "seven"
digitName '8' = "eight"
digitName _ = "nine"

-- The game's spelling of a number: each decimal digit as a word, each
-- after a space.
spell : Int -> String
spell n = go (unpack (show n))
  where
    go : List Char -> String
    go [] = ""
    go (d :: ds) = " " ++ digitName d ++ go ds

colourList : List Colour -> String
colourList [] = ""
colourList (c :: cs) = " " ++ colourName c ++ colourList cs

-- The meeting place with n meetings left, the creature waiting there if
-- any, and the run queue as a front list and a reversed back list. The
-- creature at the head arrives: once the place has closed every creature
-- fades, and the result is all of them; with nobody waiting it waits;
-- otherwise the two meet.
schedule : Int -> Maybe Creature -> List Creature -> List Creature -> List Creature
schedule n waiter [] [] = case waiter of
  Nothing => []
  Just w => [w]
schedule n waiter [] back = schedule n waiter (reverse back) []
schedule n waiter (c :: front) back =
  if n == 0
    then case waiter of
      Nothing => c :: front ++ back
      Just w => w :: c :: front ++ back
    else case waiter of
      Nothing => schedule n (Just c) front back
      Just w =>
        let k = complement (colour c) (colour w)
            same = if ident c == ident w then 1 else 0
            w' = MkCreature (ident w) k (meetings w + 1) (selfMeetings w + same)
            c' = MkCreature (ident c) k (meetings c + 1) (selfMeetings c + same)
        in schedule (n - 1) Nothing front (c' :: w' :: back)

insert : Creature -> List Creature -> List Creature
insert c [] = [c]
insert c (d :: ds) = if ident c <= ident d then c :: d :: ds else d :: insert c ds

byIdent : List Creature -> List Creature
byIdent [] = []
byIdent (c :: cs) = insert c (byIdent cs)

creatures : Int -> List Colour -> List Creature
creatures i [] = []
creatures i (c :: cs) = MkCreature i c 0 0 :: creatures (i + 1) cs

tally : List Creature -> Int -> IO Int
tally [] allMet = pure allMet
tally (c :: cs) allMet = do
  putStrLn (show (meetings c) ++ spell (selfMeetings c))
  tally cs (allMet + meetings c)

game : Int -> List Colour -> IO ()
game n colours = do
  putStrLn (colourList colours)
  allMet <- tally (byIdent (schedule n Nothing (creatures 0 colours) [])) 0
  putStrLn (spell allMet)
  putStrLn ""

complements : List Colour -> List Colour -> IO ()
complements [] _ = pure ()
complements (a :: as) bs = do
  row a bs
  complements as bs
  where
    row : Colour -> List Colour -> IO ()
    row a [] = pure ()
    row a (b :: bs) = do
      putStrLn (colourName a ++ " + " ++ colourName b ++ " -> " ++ colourName (complement a b))
      row a bs

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
  complements [Blue, Red, Yellow] [Blue, Red, Yellow]
  putStrLn ""
  game n [Blue, Red, Yellow]
  game n [Blue, Red, Yellow, Red, Yellow, Blue, Red, Yellow, Red, Blue]
