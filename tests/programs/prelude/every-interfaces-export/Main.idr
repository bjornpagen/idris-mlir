module Main

-- Every run-time export of Prelude.Interfaces, each used (covers):
-- Semigroup and Monoid with their named implementations, Functor,
-- Applicative, Alternative and Monad with their operators, Foldable with
-- every method and the folds derived from it, Traversable, Bifunctor,
-- Bifoldable and Bitraversable, and the Compose implementations of each.
-- They are taken at List, Maybe, Either, pairs, IO and at user types whose
-- implementations leave the defaults to the interface: Tree gives Foldable
-- only foldr, These gives Bifunctor only bimap and Bifoldable only
-- bifoldr, Tagged gives Bifunctor only mapFst and mapSnd, State gives
-- Monad only (>>=) and Box only join. The interfaces' constructors are
-- compile-time only. Each line is printed so that Chez checks what it
-- computes.

import Prelude

data Tree a = Leaf | Node (Tree a) a (Tree a)

Show a => Show (Tree a) where
  showPrec _ Leaf = "."
  showPrec d (Node l x r) = "(" ++ show l ++ " " ++ show x ++ " " ++ show r ++ ")"

Functor Tree where
  map f Leaf = Leaf
  map f (Node l x r) = Node (map f l) (f x) (map f r)

Foldable Tree where
  foldr f z Leaf = z
  foldr f z (Node l x r) = foldr f (f x (foldr f z r)) l

Traversable Tree where
  traverse f Leaf = pure Leaf
  traverse f (Node l x r) = [| Node (traverse f l) (f x) (traverse f r) |]

tree : Tree Int
tree = Node (Node Leaf 1 Leaf) 2 (Node (Node Leaf 3 Leaf) 4 Leaf)

data These a b = This a | That b | Both a b

(Show a, Show b) => Show (These a b) where
  showPrec d (This x) = showCon d "This" (showArg x)
  showPrec d (That y) = showCon d "That" (showArg y)
  showPrec d (Both x y) = showCon d "Both" (showArg x ++ showArg y)

Bifunctor These where
  bimap f g (This x) = This (f x)
  bimap f g (That y) = That (g y)
  bimap f g (Both x y) = Both (f x) (g y)

Bifoldable These where
  bifoldr f g z (This x) = f x z
  bifoldr f g z (That y) = g y z
  bifoldr f g z (Both x y) = f x (g y z)

Bitraversable These where
  bitraverse f g (This x) = This <$> f x
  bitraverse f g (That y) = That <$> g y
  bitraverse f g (Both x y) = [| Both (f x) (g y) |]

data Tagged a b = Tag a b

(Show a, Show b) => Show (Tagged a b) where
  showPrec d (Tag x y) = showCon d "Tag" (showArg x ++ showArg y)

Bifunctor Tagged where
  mapFst f (Tag x y) = Tag (f x) y
  mapSnd g (Tag x y) = Tag x (g y)

-- A counter threaded through a computation; its Monad gives only (>>=).
data State s a = MkState (s -> (a, s))

runState : State s a -> s -> (a, s)
runState (MkState f) = f

Functor (State s) where
  map f (MkState g) = MkState (\s => let (x, s') = g s in (f x, s'))

Applicative (State s) where
  pure x = MkState (\s => (x, s))
  MkState f <*> MkState g = MkState (\s => let (h, s') = f s; (x, s'') = g s' in (h x, s''))

Monad (State s) where
  MkState g >>= k = MkState (\s => let (x, s') = g s in runState (k x) s')

tick : Int -> State Int Int
tick x = MkState (\s => (x + s, s + 1))

-- One value; its Monad gives only join.
data Box a = MkBox a

Show a => Show (Box a) where
  showPrec d (MkBox x) = showCon d "MkBox" (showArg x)

Functor Box where
  map f (MkBox x) = MkBox (f x)

Applicative Box where
  pure = MkBox
  MkBox f <*> MkBox x = MkBox (f x)

Monad Box where
  join (MkBox b) = b

-- The largest Int seen, a Monoid of its own.
record MaxInt where
  constructor MkMax
  value : Int

Semigroup MaxInt where
  MkMax x <+> MkMax y = MkMax (max x y)

Monoid MaxInt where
  neutral = MkMax (-1000)

half : Int -> Maybe Int
half x = if mod x 2 == 0 then Just (div x 2) else Nothing

small : Int -> Maybe Int
small x = if x < 5 then Just x else Nothing

positive : Int -> Either String Int
positive x = if x > 0 then Right x else Left ("not positive: " ++ show x)

even : Int -> Bool
even x = mod x 2 == 0

ints : List Int -> List Int
ints = id

row : List String -> IO ()
row [] = putStrLn ""
row [s] = putStrLn s
row (s :: ss) = do putStr (s ++ " | "); row ss

monoids : IO ()
monoids = do
  putStrLn "-- Semigroup and Monoid"
  row [show (() <+> ()), show (the () neutral)]
  row [show (("ab", ints [1]) <+> ("cd", ints [2])), show (the (String, List Int) neutral)]
  row [show (LT <+> GT), show (EQ <+> GT), show (GT <+> LT), show (EQ <+> neutral), show (the Ordering neutral)]
  row [(show <+> (\x => show (x * 2))) (the Int 21), the (Int -> String) neutral 3]
  row [show (value (MkMax 3 <+> MkMax 9 <+> MkMax 4)), show (value neutral)]
  row [show ((<+>) @{Additive} (the Int 3) 4), show (the Int (neutral @{Additive}))]
  row [show ((<+>) @{Multiplicative} (the Int 3) 4), show (the Int (neutral @{Multiplicative}))]
  row [show ((<+>) @{Bool.Semigroup.Any} False True), show (neutral @{Bool.Monoid.Any})]
  row [show ((<+>) @{Bool.Semigroup.All} False True), show (neutral @{Bool.Monoid.All})]
  row [show (force ((<+>) @{Bool.Lazy.Semigroup.Any} (delay False) (delay True))), show (force (neutral @{Bool.Lazy.Monoid.Any}))]
  row [show (force ((<+>) @{Bool.Lazy.Semigroup.All} (delay True) (delay False))), show (force (neutral @{Bool.Lazy.Monoid.All}))]
  row [show ((<+>) @{SemigroupApplicative} (Just "x") (Just "y")), show (the (Maybe String) (neutral @{MonoidApplicative}))]
  row [show ((<+>) @{SemigroupAlternative} Nothing (Just (the Int 1))), show (the (Maybe Int) (neutral @{MonoidAlternative}))]
  row [ show (force ((<+>) @{Lazy.SemigroupAlternative} (delay (Just (the Int 2))) (delay (Just 3))))
      , show (force (the (Lazy (List Int)) (neutral @{Lazy.MonoidAlternative}))) ]

functors : IO ()
functors = do
  putStrLn "-- Functor"
  row [show (map (+ 1) (ints [1, 2, 3])), show ((* 2) <$> Just (the Int 5)), show (ints [1, 2] <&> show)]
  row [show (map (* 10) (the (Either String Int) (Right 4))), show (map (* 10) (the (Either String Int) (Left "no")))]
  row [show (map String.length (the Int 1, "second")), show ('z' <$ ints [1, 2, 3]), show (Just 'a' $> "kept")]
  row [show (ignore (Just 'x')), show (ignore (ints [1, 2]))]
  row [show (map (+ 1) tree)]
  row [show (map @{Functor.Compose} (+ 1) [Just (the Int 1), Nothing, Just 3])]
  ignore (pure {f = IO} "ignored")

bifunctors : IO ()
bifunctors = do
  putStrLn "-- Bifunctor"
  row [show (bimap (+ 1) show (the (Int, Int) (1, 2))), show (mapFst negate (the Int 3, "s")), show (mapSnd String.length (the Int 4, "four"))]
  row [show (bimap (+ 1) show (the (Either Int Int) (Left 1))), show (mapSnd (* 2) (the (Either Int Int) (Right 5)))]
  row [show (mapHom (* 3) (the (Int, Int) (1, 2))), show (mapHom String.length (the (Either String String) (Left "abc")))]
  row [show (mapFst (+ 1) (the (These Int String) (Both 1 "b"))), show (mapSnd String.length (the (These Int String) (That "that")))]
  row [show (bimap (+ 1) String.length (Tag (the Int 1) "tag")), show (mapFst show (Tag (the Int 2) 'c')), show (mapSnd not (Tag 'x' True))]
  row [show (bimap @{Bifunctor.Compose} (+ 1) show (the (List (Int, Int)) [(1, 2), (3, 4)]))]
  row [ show (mapFst @{Bifunctor.Compose} (+ 1) (Just (the Int 5, 'a')))
      , show (mapSnd @{Bifunctor.Compose} (+ 1) (Just ('b', the Int 6))) ]

applicatives : IO ()
applicatives = do
  putStrLn "-- Applicative"
  row [show (pure {f = Maybe} 'p'), show ([(+ 1), (* 10)] <*> ints [1, 2]), show (Just (+ 3) <*> Just (the Int 4))]
  row [show (Just 'l' <* Just 'a'), show (Just 'r' *> Just 'a'), show (ints [1, 2] <* ['a', 'b']), show (Nothing {ty = Int} *> Just 'a')]
  row [show (the (Either String Int) (Right (+ 1) <*> Right 2)), show (the (Either String Int) (Left {b = Int -> Int} "f" <*> Left "x"))]
  row [show (the (List (Maybe Int)) (pure @{Applicative.Compose} 7))]
  row [show ((<*>) @{Applicative.Compose} [Just (+ 1), Nothing] [Just (the Int 10), Just 20])]
  putStr "a" *> putStrLn "b" <* putStrLn "c"
  putStrLn "-- Alternative"
  row [show (Nothing <|> Just (the Int 1)), show (Just (the Int 2) <|> Just 3), show (ints [1, 2] <|> [3])]
  row [show (empty {f = Maybe} {a = Int}), show (empty {f = List} {a = Int})]
  row [show (the (Maybe ()) (guard True)), show (the (List ()) (guard False))]
  row [show (the (List Int) (do x <- [1 .. 10]; guard (mod x 3 == 0); pure x))]

monads : IO ()
monads = do
  putStrLn "-- Monad"
  row [show (Just 8 >>= half), show (Just 6 >>= half >>= half), show (ints [1, 2] >>= \x => [x, x * 10])]
  row [show (join [ints [1], [2, 3]]), show (join (Just (Just 'j'))), show (half =<< Just 12)]
  row [show ((half >=> half) 12), show ((half <=< half) 6), show ((positive >=> (positive . negate)) 3)]
  row [show (Just () >> Just 'n'), show (Right 1 >>= positive), show (positive 0 >>= positive)]
  row [show (runState (tick 10 >>= tick >>= tick) 1), show (runState (join (MkState (\s => (tick s, s * 2)))) 3)]
  row [show (MkBox (the Int 4) >>= (\x => MkBox (x * 2))), show (join (MkBox (MkBox 'b')))]
  row [ show ((>>=) @{Monad.Compose} (Just (ints [1, 2])) (\x => Just [x, x * 10]))
      , show ((>>=) @{Monad.Compose} (Just (ints [1, 3])) (\x => if x > 2 then Nothing else Just [x])) ]
  putStrLn "first" >> putStrLn "second"
  when True (putStrLn "when True")
  when False (putStrLn "when False")
  unless False (putStrLn "unless False")
  unless True (putStrLn "unless True")
  row [show (the (Maybe ()) (when False Nothing)), show (the (Maybe ()) (unless False Nothing))]

foldables : IO ()
foldables = do
  putStrLn "-- Foldable"
  row [show (foldr (::) [] tree), show (foldl (flip (::)) [] tree), show (foldr (-) 0 (ints [10, 4, 1])), show (foldl (-) 0 (ints [10, 4, 1]))]
  row [show (null tree), show (null (the (Tree Int) Leaf)), show (null (ints [])), show (null (Just 'n'))]
  row [show (toList tree), show (toList (Just 'm'))]
  row [foldMap show tree, show (foldMap (\x => [x, x]) (ints [1, 2])), foldMap show (the (Either String Int) (Right 9))]
  row [ show (foldlM (\acc, x => if x > 0 then Just (acc + x) else Nothing) 0 tree)
      , show (foldlM (\acc, x => half (acc + x)) 0 (ints [2, 2])) ]
  row [concat ["con", "cat"], show (concat (Just (ints [1, 2]))), concatMap show (ints [1, 2, 3]), show (concatMap (\x => [x, x]) tree)]
  row [show (and [True, True]), show (and [True, False]), show (or [False, False]), show (or (Just True)), show (and (the (List (Lazy Bool)) []))]
  row [show (and [False, 1 `div` 0 == the Int 1]), show (or [True, 1 `div` 0 == the Int 1])]
  row [show (any (> 3) tree), show (all (> 0) tree), show (any (> 9) (ints [1, 2])), show (all even [2, 4])]
  row [show (sum tree), show (product tree), show (sum' (the (List Double) [1.5, 2.5])), show (product' (ints [2, 3, 7]))]
  row [show (sum (the (List Integer) [])), show (product (Just (the Int 6)))]
  row [show (choice [Nothing, Just (the Int 1), Just 2]), show (choice (the (List (Lazy (Maybe Int))) []))]
  row [show (choiceMap half [3, 5, 8, 4]), show (choiceMap (\x => [x, x]) (Just 'c'))]
  traverse_ printLn tree
  for_ (ints [1, 2]) (\x => putStrLn ("for_ " ++ show x))
  sequence_ [putStrLn "sequence_ 1", putStrLn "sequence_ 2"]
  row [show (traverse_ half [2, 4]), show (traverse_ half [2, 3]), show (sequence_ [Just 'a', Just 'b']), show (for_ (Just 3) half)]
  ignore (foldlM (\acc, x => do putStrLn ("foldlM " ++ show acc ++ " " ++ show x); pure (acc + x)) 0 (ints [1, 2, 3]))
  row [ show (foldr @{Foldable.Compose} (::) [] [Just (the Int 1), Nothing, Just 3])
      , show (foldl @{Foldable.Compose} (+) 0 [ints [1, 2], [3]]) ]
  row [ show (null @{Foldable.Compose} [Nothing {ty = Int}]), show (null @{Foldable.Compose} [Just 'j'])
      , foldMap @{Foldable.Compose} show [Just (the Int 4), Just 5] ]
  row [show (toList @{Foldable.Compose} [ints [1, 2], [], [3]])]

bifoldables : IO ()
bifoldables = do
  putStrLn "-- Bifoldable"
  row [show (bifoldr (::) (::) [] (the (Int, Int) (1, 2))), show (bifoldl (flip (::)) (flip (::)) [] (the (Int, Int) (1, 2))), show (binull ('a', 'b'))]
  row [show (bifoldr (+) (*) 1 (the (Either Int Int) (Left 4))), show (binull (the (Either Int Int) (Right 1)))]
  row [ show (bifoldr (::) (::) [] (the (These Int Int) (Both 1 2)))
      , show (bifoldl (flip (::)) (flip (::)) [] (the (These Int Int) (Both 1 2))) ]
  row [show (binull (the (These Int Int) (This 1))), bifoldMap show id (the (These Int String) (Both 3 "x")), bifoldMapFst show (the (These Int String) (Both 3 "x"))]
  row [bifoldMap show show (the Int 5, 'q'), bifoldMapFst show (the (Either Int Char) (Right 'r'))]
  row [ show (bifoldr @{Bifoldable.Compose} (::) (::) [] (the (List (Either Int Int)) [Left 1, Right 2]))
      , show (bifoldl @{Bifoldable.Compose} (flip (::)) (flip (::)) [] (the (List (Either Int Int)) [Left 1, Right 2])) ]
  row [ show (binull @{Bifoldable.Compose} (the (List (Either Int Int)) [Left 1]))
      , show (binull @{Bifoldable.Compose} (the (List (Either Int Int)) [])) ]

traversables : IO ()
traversables = do
  putStrLn "-- Traversable"
  row [show (traverse half [2, 4, 6]), show (traverse half [2, 3])]
  row [show (traverse positive (Just 5)), show (traverse half tree)]
  row [show (sequence [Just (the Int 1), Just 2]), show (sequence [Just (the Int 1), Nothing])]
  row [show (sequence (map Just tree)), show (for (ints [1, 2]) positive)]
  row [show (for tree (\x => if x > 0 then Right (x * 2) else Left x)), show (traverse (\x => ints [x, x + 10]) (Just 1))]
  row [ show (traverse @{Traversable.Compose} half [Just 2, Nothing, Just 8])
      , show (traverse @{Traversable.Compose} half [Just 3]) ]
  ys <- traverse (\x => do printLn x; pure (x * 2)) tree
  printLn ys
  putStrLn "-- Bitraversable"
  row [show (bitraverse half small (the (Int, Int) (4, 3))), show (bitraverse half small (the (Either Int Int) (Left 6)))]
  row [show (bisequence (Just (the Int 1), Just 'b')), show (bisequence (the (Either (Maybe Int) (Maybe Int)) (Right Nothing)))]
  row [show (bifor (the (These Int Int) (Both 2 4)) half half), show (bitraverse half half (the (These Int Int) (That 3)))]
  row [ show (bitraverse @{Bitraversable.Compose} half small [Left 2, Right 1])
      , show (bitraverse @{Bitraversable.Compose} half small [Right 0]) ]

main : IO ()
main = do
  monoids
  functors
  bifunctors
  applicatives
  monads
  foldables
  bifoldables
  traversables

