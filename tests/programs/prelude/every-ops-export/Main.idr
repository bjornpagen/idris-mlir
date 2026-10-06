module Main

-- Prelude.Ops declares fixities only, so what it gives a program is how
-- each operator groups (covers): every operator it declares is used
-- unbracketed beside one of a different precedence and beside itself,
-- at values where any other grouping computes something else, and
-- <=>, which the prelude declares but does not define, at a definition
-- of the program's own. Each line is printed so that Chez checks what it
-- computes.

import Prelude

spaced : List String -> String
spaced [] = ""
spaced [s] = s
spaced (s :: ss) = s ++ " " ++ spaced ss

line : String -> List String -> IO ()
line label xs = putStrLn (label ++ ": " ++ spaced xs)

-- Equivalence of Bools, at infix 0: below every comparison.
(<=>) : Bool -> Bool -> Bool
(<=>) a b = a == b

asList : SnocList a -> List a
asList sx = asList' sx []
  where
    asList' : SnocList a -> List a -> List a
    asList' [<] acc = acc
    asList' (sx :< x) acc = asList' sx (x :: acc)

half : Int -> Maybe Int
half n = if mod n 2 == 0 then Just (div n 2) else Nothing

dec : Int -> Maybe Int
dec n = if n > 0 then Just (n - 1) else Nothing

main : IO ()
main = do
  -- infixl 8 + and -, infixl 9 * and /, infix 6 comparisons.
  let x = the Int 10
  line "arith" [show (x - 3 - 2), show (x - 3 + 2), show (2 + 3 * 4), show (2 * 3 + 4), show (x - 2 * 3)]
  line "fraction" [show (the Double 100.0 / 10.0 / 2.0), show (the Double 1.0 + 6.0 / 2.0 * 3.0)]
  line "compare" (map show [1 + 2 == the Int 3, x - 1 /= 9, x * 2 < x + 11, x <= 5 + 5, x > 3 * 3, x >= x + 1])
  -- infixl 9 `div` and `mod`, with * at the same level.
  line "div mod" [show (17 `div` 5 * 2), show (2 * 17 `div` 5), show (17 `mod` 5 `mod` 2), show (x + 7 `mod` 4)]
  -- infixr 5 &&, infixr 4 ||, below the comparisons.
  line "bool" (map show [True || False && False, False && True || True, x > 5 && x < 20 || x == 0, x == 3 || x == 10 && x > 0])
  -- infix 0 <=>, below everything above.
  line "equivalence" (map show [x > 5 <=> x > 3, True || False <=> False, 1 + 1 == the Int 2 <=> 2 * 2 == the Int 5])
  -- infixr 7 :: and ++, infixl 7 :<, above the comparisons.
  line "list" [show (the Int 1 :: [2] ++ [3] ++ [4]), show ("a" ++ "b" ++ "c" == "abc"), show (length ([1, 2] ++ the (List Int) [3]))]
  line "snoc" [show (asList ([<] :< the Int 1 :< 2 :< 3))]
  -- infixl 1 >>=, =<<, >>, >=>, <=<, <&>.
  line "monad" [ show (Just 40 >>= half >>= dec), show (dec =<< Just 8 >>= half)
               , show (Just () >> Just (the Int 6) >>= half), show ((half >=> dec >=> half) 10)
               , show ((dec <=< half) 8), show (Just (the Int 3) <&> (* 2) <&> (+ 1)) ]
  -- infixr 2 <|>, infixl 3 <*>, *>, <*, infixr 4 <$>, $>, <$.
  line "applicative" [ show (Nothing <|> Just (the Int 1) <|> Just 2), show ((+) <$> Just (the Int 1) <*> Just 2)
                     , show (Just 'a' *> Just 'b' <* Just 'c'), show (Just (the Int 1) $> 'x'), show ('y' <$ Just (the Int 1))
                     , show (Nothing <|> (+ 1) <$> Just (the Int 4)), show (subtract <$> Just (the Int 10) <*> Just 3) ]
  -- infixl 8 <+>, with ++ below it.
  line "semigroup" [show ("ab" <+> "cd" <+> "ef"), show ([the Int 1] <+> [2] ++ [3])]
  -- infixr 9 . and .:, infixr 0 $, <| and infixl 0 |>.
  line "compose" [ show ((+ 1) . (* 2) . (+ 3) $ the Int 4), show (((+) .: (*)) (the Int 2) 3 4)
                 , show (negate $ (+ 1) $ the Int 4), show ((* 2) <| (+ 1) <| the Int 4)
                 , show (the Int 4 |> (+ 1) |> (* 2)), show (show <| the Int 3 + 4) ]
