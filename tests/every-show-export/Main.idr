module Main

-- Every run-time export of Prelude.Show, each used (covers): show and
-- showPrec at every Show implementation the module provides, at each
-- precedence where it matters (a negative number is bracketed from
-- PrefixMinus on, a constructor application at App, a pair and a list
-- never); the escapes Show Char and Show String write, with the \& that
-- keeps an escape from running into what follows; the constructors of
-- Prec, precCon and Prec's Eq and Ord; showParens, showCon and showArg in
-- implementations of a program's own types, one defining showPrec only
-- (show is the default), one show only (showPrec is the default), one
-- built with MkShow. Show Void is used where a Void cannot arrive. The
-- interface's constructor is compile-time only. Each line is printed so
-- that what it computes is checked.

import Prelude

spaced : List String -> String
spaced [] = ""
spaced [s] = s
spaced (s :: ss) = s ++ " " ++ spaced ss

line : String -> List String -> IO ()
line label xs = putStrLn (label ++ ": " ++ spaced xs)

-- A value shown at Open, Equal, Dollar, Backtick, a user operator's
-- precedence, PrefixMinus and App.
precs : List Prec
precs = [Open, Equal, Dollar, Backtick, User 6, PrefixMinus, App]

atEach : Show a => a -> List String
atEach x = map (\d => showPrec d x) precs

-- A number and its negation, shown with show and at each precedence.
signed : (Show a, Neg a) => a -> List String
signed x = show x :: show (negate x) :: atEach x ++ atEach (negate x)

-- An expression with an infix operator of its own (at User 6, left
-- associative) and a prefix constructor: showPrec only, so show is the
-- default, showPrec Open.
data Expr = Lit Int | Add Expr Expr | Neg Expr

Show Expr where
  showPrec d (Lit n) = showPrec d n
  showPrec d (Add a b) = showParens (d >= User 6) (showPrec (User 6) a ++ " + " ++ showPrec (User 7) b)
  showPrec d (Neg e) = showCon d "Neg" (showArg e)

-- A record shown with show only, so showPrec is the default, show.
record Point where
  constructor MkPoint
  px : Int
  py : Int

Show Point where
  show p = "<" ++ show (px p) ++ "," ++ show (py p) ++ ">"

-- A wrapper whose implementation is MkShow's record of both methods.
data Celsius = MkCelsius Double

celsiusShow : Show Celsius
celsiusShow = MkShow (\(MkCelsius t) => show t ++ "C") (\d, (MkCelsius t) => showCon d "MkCelsius" (showArg t))

-- An index that DPair's Show needs at each value of its first component.
data Tag : Nat -> Type where
  MkTag : (n : Nat) -> Tag n

Show (Tag n) where
  showPrec d (MkTag k) = showCon d "MkTag" (showArg k)

-- Show Void, reached only in a branch no value takes.
noVoid : Either Void Int -> String
noVoid = either show show

main : IO ()
main = do
  line "Int" (signed (the Int 42) ++ [show (the Int 9223372036854775807), show (the Int (-9223372036854775808))])
  line "Integer" (signed (the Integer 123456789012345678901234567890))
  line "Int8" (signed (the Int8 127) ++ [show (the Int8 (-128))])
  line "Int16" (signed (the Int16 32767) ++ [show (the Int16 (-32768))])
  line "Int32" (signed (the Int32 2147483647) ++ [show (the Int32 (-2147483648))])
  line "Int64" (signed (the Int64 9223372036854775807) ++ [show (the Int64 (-9223372036854775808))])
  line "Bits8" (show (the Bits8 255) :: atEach (the Bits8 7))
  line "Bits16" (show (the Bits16 65535) :: atEach (the Bits16 7))
  line "Bits32" (show (the Bits32 4294967295) :: atEach (the Bits32 7))
  line "Bits64" (show (the Bits64 18446744073709551615) :: atEach (the Bits64 7))
  line "Double" (signed (the Double 2.5) ++ [show (the Double 0.1), show (the Double 1.0e100), show (the Double 0.0)])
  line "Nat" (show (the Nat 0) :: atEach (the Nat 12345678901234567890))
  line "Char" (map show ['a', '\'', '"', '\\', '\a', '\b', '\f', '\n', '\r', '\t', '\v', '\SO', '\DEL', '\0', '\ESC', '\US', ' ', '~', '\128', '\233', '\1234'] ++ atEach 'x')
  line "String" [ show "plain", show "quote \" and 'tick'", show "tab\tnewline\nbackslash\\"
                , show (pack ['\SO', 'H']), show (pack ['\SO', 'I']), show (pack ['\233', '1']), show (pack ['\233', 'a'])
                , show (pack ['\0', '1', '\DEL']), show "", showPrec App "s" ]
  line "Bool" (show True :: show False :: atEach True)
  line "Unit" (show () :: atEach ())
  line "Ordering" (map show [LT, EQ, GT] ++ atEach LT)
  line "Void" [noVoid (Right 7)]
  line "Pair" (show (the Int (-1), "a") :: show ((the Int 1, 'b'), (True, the Integer (-2))) :: atEach (the Int (-3), the Int 4))
  line "DPair" [show (the (DPair Nat Tag) (2 ** MkTag 2)), showPrec App (the (DPair Nat Tag) (0 ** MkTag 0))]
  line "List" (show (the (List Int) []) :: show (the (List Int) [-1, 2, -3]) :: show [[the Int 1], [], [-2, 3]] :: atEach [Just (the Int (-1))])
  line "Maybe" (show (the (Maybe Int) Nothing) :: show (Just (Just (the Int (-3)))) :: show (Just (the Int 3, the Int (-4))) :: atEach (Just (the Int (-5))) ++ atEach (the (Maybe Int) Nothing))
  line "Either" (show (the (Either Int String) (Left (-1))) :: show (the (Either Int (Either String Int)) (Right (Right (-2)))) :: atEach (the (Either Int Bool) (Right True)))
  line "Expr" (let e = Add (Add (Lit 1) (Neg (Lit (-2)))) (Add (Lit 3) (Lit 4)) in show e :: atEach e ++ [show (Neg (Neg (Lit 5))), show (Just (Add (Lit 1) (Lit 2)))])
  line "Point" (show (MkPoint 1 (-2)) :: atEach (MkPoint 3 4) ++ [show (Just (MkPoint 5 6))])
  line "Celsius" (show @{celsiusShow} (MkCelsius (-40.0)) :: atEach @{celsiusShow} (MkCelsius 21.5))
  line "precCon" (map (show . precCon) precs ++ [show (precCon (User 100))])
  line "Prec ==" (map show [User 3 == User 3, User 3 == User 4, Open == Open, Open == App, User 3 /= User 4, Dollar /= Dollar, User 0 == Backtick])
  line "Prec compare" (map show [compare (User 2) (User 5), compare (User 5) (User 5), compare App Open, compare Backtick (User 0), compare (User 99) PrefixMinus])
  line "Prec order" (map show [Equal < Dollar, App <= PrefixMinus, User 7 > User 6, Open >= Open] ++ [show (precCon (max Backtick Equal)), show (precCon (min App (User 1)))])
  line "showParens" [showParens True "x", showParens False "x", showParens True ""]
  line "showCon" [showCon Open "C" " 1", showCon Backtick "C" " 1", showCon App "C" " 1", showCon App "C" ""]
  line "showArg" [showArg (the Int 1), showArg (the Int (-1)), showArg (Just 'c'), showArg [the Int (-1)], showArg "s"]
