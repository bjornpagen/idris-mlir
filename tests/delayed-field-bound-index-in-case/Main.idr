module Main

-- A delayed field at an index its constructor binds, forced inside a case
-- block: `Seq` holds an `Inf (R e)` and `Lag` a `Lazy (R e)` at the `e`
-- each binds, and `count` forces the field in the case on the first
-- field's count, where the suspension has the constructor's own index,
-- not one the case block is checked at.

data R : Bool -> Type where
  P : R True
  E : R False
  Seq : R True -> Inf (R e) -> R True
  Lag : R True -> Lazy (R e) -> R True

covering
count : R c -> Maybe Nat
count P = Just 1
count E = Just 0
count (Seq a b) = case count a of
  Nothing => Nothing
  Just n => map (+ n) (count b)
count (Lag a b) = case count a of
  Nothing => Nothing
  Just n => map (+ n) (count b)

covering
main : IO ()
main = do
  printLn (count (Seq P (Seq P E)))
  printLn (count (Lag P (Seq P (Lag P E))))
