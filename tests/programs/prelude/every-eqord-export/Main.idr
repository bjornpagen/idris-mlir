module Main

-- Every run-time export of Prelude.EqOrd, each used (covers): Eq's and
-- Ord's methods at the prelude's types and at Suit, whose implementations
-- are built with MkEq and MkOrd; the constructors of Ordering, contra,
-- comparing, compareInteger and the Reverse implementation. Each line is
-- printed so that Chez checks what it computes.

import Prelude

data Suit = Clubs | Diamonds | Hearts | Spades

rank : Suit -> Int
rank Clubs = 0
rank Diamonds = 1
rank Hearts = 2
rank Spades = 3

showSuit : Suit -> String
showSuit Clubs = "clubs"
showSuit Diamonds = "diamonds"
showSuit Hearts = "hearts"
showSuit Spades = "spades"

showSuits : List Suit -> String
showSuits [] = ""
showSuits [s] = showSuit s
showSuits (s :: ss) = showSuit s ++ " " ++ showSuits ss

-- Suit's Eq and Ord are the records of their methods, each method
-- given, through rank, and passed where they are used. MkEq and MkOrd
-- still never reach Core: an implementation is a compile-time value
-- there, each method call specialized to the one it is given
-- ((==)[Main.Suit, Main.suitEq]) and the record itself never built, and
-- an implementation chosen at run time is rejected (runtime closure).
suitEq : Eq Suit
suitEq = MkEq (\x, y => rank x == rank y) (\x, y => rank x /= rank y)

suitOrd : Ord Suit
suitOrd = MkOrd @{suitEq}
  (\x, y => compare (rank x) (rank y))
  (\x, y => rank x < rank y)
  (\x, y => rank x > rank y)
  (\x, y => rank x <= rank y)
  (\x, y => rank x >= rank y)
  (\x, y => if rank x >= rank y then x else y)
  (\x, y => if rank x <= rank y then x else y)

insert : Ord a => a -> List a -> List a
insert x [] = [x]
insert x (y :: ys) = if x <= y then x :: y :: ys else y :: insert x ys

sort : Ord a => List a -> List a
sort [] = []
sort (x :: xs) = insert x (sort xs)

main : IO ()
main = do
  printLn (the Int 3 == 3, the Int 3 /= 3)
  printLn (the Integer 12345678901234567890 == 12345678901234567890)
  printLn ('a' /= 'b', "idris" == "idris", "idris" == "mlir")
  printLn (the Double 0.5 == 0.5, the Bits8 255 /= 255)
  printLn (() == (), True /= False, (the Int 1, 'x') == (1, 'y'))
  printLn (compare (the Int 1) 2, compare "b" "a", compare 'c' 'c')
  printLn (the Integer 2 < 3, the Double 2.5 > 3.0)
  printLn (the Int64 (-1) <= -1, the Bits8 7 >= 8)
  printLn (max (the Int 4) 9, min "pear" "apple")
  printLn (compare (the Int 1, "b") (1, "a"), compare False True)
  printLn (compareInteger 10 (-10), compareInteger 7 7)
  printLn (map contra [LT, EQ, GT])
  printLn (LT == contra GT, EQ /= EQ)
  printLn (comparing rank Spades Clubs, comparing snd (the Int 1, 'z') (2, 'a'))
  printLn (compare @{Reverse} (the Int 1) 2, the Int 1 < 2)
  printLn (max @{Reverse} (the Int 4) 9, min @{Reverse} 'a' 'z')
  printLn (sort @{Reverse} (the (List Int) [3, 1, 4, 1, 5]))
  printLn ((==) @{suitEq} Hearts Hearts, (/=) @{suitEq} Clubs Spades,
           (==) @{suitEq} Clubs Spades)
  printLn (compare @{suitOrd} Diamonds Hearts, compare @{suitOrd} Spades Spades,
           compare @{suitOrd} Spades Clubs)
  printLn ((<) @{suitOrd} Spades Clubs, (>) @{suitOrd} Spades Clubs,
           (<=) @{suitOrd} Hearts Hearts, (>=) @{suitOrd} Clubs Diamonds)
  putStrLn (showSuit (max @{suitOrd} Clubs Hearts) ++ " "
            ++ showSuit (min @{suitOrd} Spades Diamonds))
  putStrLn (showSuits (sort @{suitOrd} [Spades, Clubs, Hearts, Diamonds]))
  putStrLn (showSuits (sort @{Reverse @{suitOrd}} [Spades, Clubs, Hearts, Diamonds]))
