module Main

-- Every run-time export of Prelude.Types, each used (covers): Nat and its
-- arithmetic, Maybe, Either, the equivalences and the decisions built
-- from them, the List and SnocList functions with their tail-recursive
-- twins and the helpers those are built from, Stream (an infinite value
-- under Inf, Delay and Force, of which only a finite prefix is taken),
-- the String and Char functions, the Double functions, and the ranges at
-- each type the module implements Range for. Beside them, the module's
-- implementations at its own types: Num, Eq and Ord of Nat; Eq, Ord,
-- Semigroup, Monoid, Functor, Applicative, Alternative, Monad, Foldable
-- and Traversable of Maybe, Either and List as each has them; Eq and Ord
-- of SnocList; Functor of Stream; Semigroup and Monoid of String; and the
-- Pair implementations. The types, Range's constructor and the
-- equivalence type former are compile-time only. Each line is printed so
-- that what it computes is checked.

import Prelude

spaced : List String -> String
spaced [] = ""
spaced [s] = s
spaced (s :: ss) = s ++ " " ++ spaced ss

line : String -> List String -> IO ()
line label xs = putStrLn (label ++ ": " ++ spaced xs)

-- Nat ---------------------------------------------------------------------

three : Nat
three = S (S (S Z))

-- Maybe -------------------------------------------------------------------

halve : Nat -> Maybe Nat
halve n = if mod (natToInteger n) 2 == 0 then Just (integerToNat (div (natToInteger n) 2)) else Nothing

positive : Int -> Maybe Int
positive x = if x > 0 then Just x else Nothing

even : Int -> Bool
even x = mod x 2 == 0

odd : Int -> Bool
odd x = not (even x)

-- Either ------------------------------------------------------------------

parseDigit : Char -> Either String Int
parseDigit c = if isDigit c then Right (ord c - ord '0') else Left (pack [c])

-- Equivalences and decisions ----------------------------------------------

natInteger : Nat <=> Integer
natInteger = MkEquivalence natToInteger integerToNat

-- A decision whose evidence is a value, carried to another type by an
-- equivalence.
someNat : Dec Nat
someNat = Yes three

-- A decision whose evidence is a proof: whether a Maybe is Nothing, refuted
-- in the Just case by Maybe's Uninhabited implementation.
isNothing' : (m : Maybe Nat) -> Dec (m = Nothing)
isNothing' Nothing = Yes Refl
isNothing' (Just x) = No (\eq => uninhabited eq)

succInjective : S m = S n -> m = n
succInjective Refl = Refl

succEquiv : (m = n) <=> (S m = S n)
succEquiv = MkEquivalence (\eq => cong S eq) succInjective

Uninhabited (Z = S n) where
  uninhabited Refl impossible

Uninhabited (S n = Z) where
  uninhabited Refl impossible

decEqNat : (m, n : Nat) -> Dec (m = n)
decEqNat Z Z = Yes Refl
decEqNat (S j) (S k) = viaEquivalence succEquiv (decEqNat j k)
decEqNat Z (S k) = No (\eq => uninhabited eq)
decEqNat (S j) Z = No (\eq => absurd eq)

showDec : Dec p -> String
showDec (Yes _) = "Yes"
showDec (No _) = "No"

showDecNat : Dec Nat -> String
showDecNat (Yes n) = "Yes " ++ show n
showDecNat (No _) = "No"

showDecInteger : Dec Integer -> String
showDecInteger (Yes n) = "Yes " ++ show n
showDecInteger (No _) = "No"

showSnoc : Show a => SnocList a -> String
showSnoc sx = "[<" ++ go sx ++ "]"
  where
    go : SnocList a -> String
    go [<] = ""
    go [< x] = show x
    go (sx :< x) = go sx ++ ", " ++ show x

-- Streams -----------------------------------------------------------------

-- Each element twice the one before, the rest of the stream delayed.
powers : Stream Integer
powers = 1 :: Delay (map (* 2) powers)

-- The rest of a stream, forced by hand.
rest : Stream a -> Stream a
rest (_ :: xs) = Force xs

-- Pair's Applicative and Monad, at a Monoid of logs.
logged : Int -> (String, Int)
logged n = (show n ++ ";", n * 10)

main : IO ()
main = do
  -- Nat
  line "nat" [show Z, show three, show (plus three 4), show (minus 10 three), show (minus three 10), show (mult three 5)]
  line "nat num" [show (the Nat 3 + 4 * 2), show (the Nat 7 * 0 + 1), show (fromInteger {ty = Nat} 12)]
  line "nat eq" [show (equalNat 3 3), show (equalNat 3 4), show (the Nat 5 == 5), show (the Nat 5 /= 6)]
  line "nat ord" [show (compareNat 2 5), show (compareNat 5 5), show (compareNat 6 5), show (compare (the Nat 1) 0), show (the Nat 3 < 4), show (max (the Nat 3) 9)]
  line "nat integer" [show (natToInteger 42), show (integerToNat 17), show (integerToNat (-5)), show (integerToNat 0)]
  line "count" [show (count isDigit (unpack "a1b22c333")), show (count (> 2) (Just (the Int 3))), show (count (> 2) [the Int 1, 5, 7])]
  -- Maybe
  line "maybe" [show (maybe "none" show (halve 10)), show (maybe "none" show (halve 7))]
  whenJust (halve 8) (\n => line "whenJust" [show n])
  whenJust (halve 9) (\n => line "whenJust" [show n])
  line "maybe eq" [show (Just (the Int 1) == Just 1), show (Just (the Int 1) == Nothing), show (the (Maybe Int) Nothing == Nothing)]
  line "maybe ord" [show (compare Nothing (Just (the Int 1))), show (compare (Just (the Int 2)) (Just 1)), show (Just (the Int 0) > Nothing)]
  line "maybe monoid" [show (Nothing <+> Just (the Int 4)), show (Just (the Int 1) <+> Just 2), show (the (Maybe Int) neutral)]
  line "maybe functor" [show (map (+ 1) (Just (the Int 1))), show (map (+ 1) (the (Maybe Int) Nothing))]
  line "maybe applicative" [show (pure (+) <*> Just (the Int 2) <*> Just 3), show (Just (the (Int -> Int) (+ 1)) <*> Nothing)]
  line "maybe alternative" [show (Nothing <|> Just (the Int 5)), show (Just (the Int 6) <|> Just 7), show (the (Maybe Int) empty)]
  line "maybe monad" [show (halve 12 >>= halve), show (halve 6 >>= halve), show (halve 5 >>= halve)]
  line "maybe foldable" [show (foldr (+) 10 (Just (the Int 5))), show (sum (the (Maybe Int) Nothing)), show (null (Just 'x')), show (null (the (Maybe Int) Nothing))]
  line "maybe traversable" [show (traverse positive (Just 3)), show (traverse positive (Just (-3))), show (traverse positive Nothing)]
  -- Either
  line "either" [show (either (const (the Int (-1))) id (parseDigit '7')), show (either (const (the Int (-1))) id (parseDigit 'x'))]
  line "either eq" [show (parseDigit '3' == Right 3), show (parseDigit 'a' == Left "a"), show (parseDigit 'a' == Right 0)]
  line "either ord" [show (compare (parseDigit 'a') (parseDigit '1')), show (compare (parseDigit '2') (parseDigit '1')), show (compare (parseDigit 'a') (parseDigit 'b'))]
  line "either functor" [show (map (* 2) (parseDigit '4')), show (map (* 2) (parseDigit 'z'))]
  line "either bifunctor" [show (bimap String.length (* 2) (parseDigit 'q')), show (bimap String.length (* 2) (parseDigit '4'))]
  line "either bifoldable" [show (bifoldr (\s, acc => String.length s + acc) (\n, acc => cast n + acc) 100 (parseDigit 'q')), show (bifoldl (\acc, s => acc + String.length s) (\acc, n => acc + cast n) 100 (parseDigit '9')), show (binull (parseDigit '1'))]
  line "either bitraversable" [show (bitraverse (\s => Just (s ++ "!")) positive (parseDigit 'x')), show (bitraverse (\s => Just (s ++ "!")) positive (parseDigit '0'))]
  line "either applicative" [show (pure (+) <*> parseDigit '1' <*> parseDigit '2'), show (pure (+) <*> parseDigit 'a' <*> parseDigit '2'), show ([| parseDigit '1' + parseDigit 'b' |])]
  line "either monad" [show (parseDigit '5' >>= (\n => parseDigit (chr (ord '0' + n - 1)))), show (parseDigit 'e' >>= (\n => Right (n + 1)))]
  line "either foldable" [show (foldr (+) 1 (parseDigit '8')), show (foldr (+) 1 (parseDigit 'y')), show (null (parseDigit 'y')), show (null (parseDigit '0'))]
  line "either traversable" [show (traverse positive (parseDigit '3')), show (traverse positive (parseDigit '0')), show (traverse positive (parseDigit 'n'))]
  -- Equivalences and decisions
  line "equivalence" [show (natInteger.leftToRight 9), show (natInteger.rightToLeft 11), show (leftToRight natInteger 2), show (rightToLeft natInteger (-1))]
  line "via value" [showDecInteger (viaEquivalence natInteger someNat), showDecNat someNat]
  line "dec proof" [showDec (isNothing' Nothing), showDec (isNothing' (Just 1))]
  line "via proof" [showDec (decEqNat 4 4), showDec (decEqNat 4 2), showDec (decEqNat 0 3), showDec (decEqNat 3 0)]
  -- Lists
  let xs = the (List Int) [1, 2, 3, 4, 5, 6]
  line "list append" [show (xs ++ [7]), show (tailRecAppend [the Int 0] xs), show ([the Int 1] <+> [2]), show (the (List Int) neutral)]
  line "list length" [show (List.length xs), show (lengthTR xs), show (lengthPlus 10 xs)]
  line "list filter" [show (filter (> 3) xs), show (filterTR (< 3) xs), show (filterAppend [< 100] even xs)]
  line "list mapMaybe" [show (List.mapMaybe positive [1, -1, 2]), show (mapMaybeTR positive [-2, 3]), show (mapMaybeAppend [< 0] positive [4, -4])]
  line "list reverse" [show (reverse xs), show (reverseOnto [0] [1, 2, the Int 3])]
  line "list map" [show (mapImpl (* 10) xs), show (mapTR (+ 1) xs), show (mapAppend [< 'a'] toUpper ['b', 'c']), show (map negate xs)]
  line "list bind" [show (listBind [1, 2, the Int 3] (\x => [x, x * 10])), show (listBindOnto (\x => [x, x]) [0] [the Int 7, 8]), show (xs >>= (\x => if even x then [x] else []))]
  line "list eq" [show (xs == xs), show (xs == reverse xs), show (the (List Int) [] == [])]
  line "list ord" [show (compare [the Int 1, 2] [1, 3]), show (compare [the Int 1, 2] [1]), show (compare (the (List Int) []) []), show ([the Int 2] > [1, 9])]
  line "list foldable" [show (foldr (::) [] xs), show (foldl (flip (::)) [] xs), show (null xs), show (null (the (List Int) [])), show (toList xs), show (foldMap show xs), show (sum xs), show (product xs)]
  line "list applicative" [show (the (List Int) (pure 5)), show ([(+ 1), (* 2)] <*> [10, the Int 20]), show ([| MkPair (the (List Int) [1, 2]) ['a', 'b'] |])]
  line "list alternative" [show ([the Int 1, 2] <|> [3]), show (the (List Int) empty)]
  line "list traversable" [show (traverse positive xs), show (traverse positive [1, 0, 2]), show (sequence [Just 'a', Just 'b'])]
  line "list search" [show (elem 3 xs), show (elem 9 xs), show (elemBy (\a, b => a == b * 2) 6 xs), show (elem 'c' (Just 'c')), show (getAt 2 xs), show (getAt 9 xs)]
  -- Snoc-lists
  let sx = the (SnocList Int) [< 1, 2, 3, 4]
  line "snoc fish" [showSnoc (sx <>< [5, 6]), show (sx <>> [5, 6])]
  line "snoc append" [showSnoc (sx ++ [< 9]), showSnoc (tailRecAppend sx [< 7, 8])]
  line "snoc length" [show (SnocList.length sx), show (lengthTR sx), show (lengthPlus 5 sx)]
  line "snoc filter" [showSnoc (filter even sx), showSnoc (filterTR odd sx), showSnoc (filterAppend [10] (> 2) sx)]
  line "snoc mapMaybe" [showSnoc (SnocList.mapMaybe positive [< 1, -2, 3]), showSnoc (mapMaybeTR positive [< -1, 4]), showSnoc (mapMaybeAppend [9] positive [< 5, -5])]
  line "snoc reverse" [showSnoc (reverse sx), showSnoc (reverseOnto [< 0] sx)]
  line "snoc eq" [show (sx == sx), show (sx == [< 1, 2]), show ([< 'a'] == [< 'a'])]
  line "snoc ord" [show (compare sx [< 1, 2, 3, 5]), show (compare [< 2] sx), show (compare (the (SnocList Int) [<]) [<])]
  -- Streams
  let nats = countFrom (the Nat 0) S
  line "stream" [show (take 5 nats), show (head powers), show (take 6 powers), show (take 3 (tail powers)), show (take 3 (rest (rest powers)))]
  line "stream cons" [show (take 4 (the Int 7 :: Delay (countFrom 8 (+ 2))))]
  line "stream map" [show (take 4 (map (* 3) nats))]
  line "stream until" [show (takeUntil (> 4) nats), show (takeBefore (> 4) nats), show (takeUntil (> 100) powers)]
  -- Ranges
  line "range nat" [show (the (List (List Nat)) [[1 .. 5], [5 .. 2], [1, 3 .. 10], [9, 6 .. 1], take 3 [4 ..], take 4 [10, 8 ..]])]
  line "range int" [show (the (List (List Int)) [[-2 .. 2], [3 .. 0], [1, 4 .. 12], [10, 7 .. -3], take 3 [-1 ..], take 3 [0, -5 ..]])]
  line "range integer" [show (the (List (List Integer)) [rangeFromTo 1 3, rangeFromThenTo 0 10 30, take 2 (rangeFrom 99), take 3 (rangeFromThen 1 2)])]
  line "range char" [show (the (List (List Char)) [['a' .. 'e'], ['a', 'c' .. 'i'], take 3 ['x' ..], take 3 ['z', 'x' ..]])]
  -- Strings
  let s = "Hello, World"
  line "string" [show (String.length s), show [s ++ "!", reverse s, substr 7 5 s, substr 20 2 s, strCons '>' s]]
  line "string uncons" [show (strUncons "abc"), show (strUncons "")]
  line "string pack" [show (pack ['i', 'd', 'r']), show (fastPack ['m', 'l', 'i', 'r']), show (unpack "abc"), show (fastUnpack "xyz")]
  line "string concat" [show [fastConcat (the (List String) ["ab", "cd", "ef"]), "x" <+> "y", the String neutral, concat (the (List String) ["p", "q"])]]
  -- Characters
  let cs = unpack "aZ5 \t\nx#f\DEL\159G7"
  line "upper lower" [show (map isUpper cs), show (map isLower cs)]
  line "alpha digit" [show (map isAlpha cs), show (map isDigit cs), show (map isAlphaNum cs)]
  line "space nl" [show (map isSpace cs), show (map isNL cs), show (isSpace '\xa0'), show (isNL '\r')]
  line "hex oct control" [show (map isHexDigit cs), show (map isOctDigit cs), show (map isControl cs)]
  line "case" [show (map toUpper cs), show (map toLower cs)]
  line "chr ord" [show (chr 65), show (ord 'z'), show (chr (ord 'a' + 1))]
  -- Doubles
  line "constants" [show [pi, euler]]
  line "exp log pow" [show [exp 1, log 10, pow 2 10, pow 2 0.5, sqrt 2]]
  line "trig" [show [sin 0.5, cos 0.5, tan 0.5, asin 0.5, acos 0.5, atan 1]]
  line "hyperbolic" [show [sinh 1, cosh 1, tanh 0.5]]
  line "rounding" [show [floor 2.5, floor (-2.5), ceiling 2.5, ceiling (-2.5)]]
  -- Pairs
  line "pair bifunctor" [show (bimap (+ 1) String.length (the Int 1, "abc"))]
  line "pair bifoldable" [show (bifoldr (+) (\s, acc => acc + cast (String.length s)) (the Int 0) (1, "ab")), show (bifoldl (+) (\acc, s => acc + cast (String.length s)) (the Int 10) (1, "abc")), show (binull ('a', 'b'))]
  line "pair bitraversable" [show (bitraverse positive (\c => Just (toUpper c)) (1, 'a')), show (bitraverse positive (\c => Just c) (0, 'a'))]
  line "pair functor" [show (map (+ 1) ('k', the Int 1))]
  line "pair foldable" [show (foldr (+) 1 ('k', the Int 2)), show (foldl (+) 1 ('k', the Int 3)), show (null ('k', 'v'))]
  line "pair traversable" [show (traverse positive ('a', 4)), show (traverse positive ('a', 0))]
  line "pair applicative" [show (the (String, Int) (pure 3)), show (("f;", (+ 1)) <*> logged 4)]
  line "pair monad" [show (logged 1 >>= (\n => logged (n + 1)))]
