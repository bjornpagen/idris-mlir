module Main

-- Every run-time export of Prelude.Uninhabited, each used (covers):
-- uninhabited at each implementation the module provides (Void,
-- True = False and False = True), absurd and void, in the branches of
-- programs that no value takes, beside the branches that run; the
-- refutations of True = False and False = True kept in the No of a
-- decision; and implementations at a program's own empty types, one
-- declared and one built with MkUninhabited. The interface's constructor
-- is compile-time only. Each line is printed so that Chez checks what it
-- computes.

import Prelude

spaced : List String -> String
spaced [] = ""
spaced [s] = s
spaced (s :: ss) = s ++ " " ++ spaced ss

-- A type with no constructors.
data Never : Type where

Uninhabited Never where
  uninhabited n impossible

-- A record that holds a Void, so has no value either.
record Stuck where
  constructor MkStuck
  stuck : Void

stuckUninhabited : Uninhabited Stuck
stuckUninhabited = MkUninhabited stuck

-- Uninhabited Void through absurd, and void itself.
fromVoid : Either Void Int -> Int
fromVoid (Left v) = absurd v
fromVoid (Right n) = n

viaVoid : Either Void String -> String
viaVoid (Left v) = void v
viaVoid (Right s) = s

viaUninhabited : Either Void Bool -> Bool
viaUninhabited (Left v) = void (uninhabited v)
viaUninhabited (Right b) = b

-- Bool's equality decided: True = False and False = True refuted by
-- their implementations, one through uninhabited, one through absurd.
decBool : (a, b : Bool) -> Dec (a = b)
decBool True True = Yes Refl
decBool False False = Yes Refl
decBool True False = No uninhabited
decBool False True = No absurd

showDec : Dec p -> String
showDec (Yes _) = "Yes"
showDec (No _) = "No"

-- The program's own empty types in the branches no value takes.
counted : List (Either Never Int) -> Int
counted [] = 0
counted (Left n :: _) = absurd n
counted (Right k :: rest) = k + counted rest

unstuck : Maybe Stuck -> String
unstuck Nothing = "nothing stuck"
unstuck (Just s) = absurd @{stuckUninhabited} s

refuted : Maybe Never -> String
refuted Nothing = "never refuted"
refuted (Just n) = void (uninhabited n)

main : IO ()
main = do
  printLn (fromVoid (Right 42))
  putStrLn (viaVoid (Right "void kept out"))
  printLn (viaUninhabited (Right True))
  putStrLn (spaced [showDec (decBool a b) | a <- [False, True], b <- [False, True]])
  printLn (counted [Right 1, Right 2, Right 39])
  putStrLn (unstuck Nothing)
  putStrLn (refuted Nothing)
