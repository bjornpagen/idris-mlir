module Main

-- `(a, b)` writes either the pair type `Pair a b` or the pair `MkPair a b`,
-- chosen by the type the site is expected to have:
-- - a universe: the pair type;
-- - any other type already known: the pair;
-- - a type not yet known: the one reading that fits there, and where both
--   fit, the pair, the syntax's default.
-- A tuple of more components is pairs nested to the right.
--
-- `which` tells which reading a site took by the type it was given: an
-- implementation at `Type`, the type of the pair type, and one at
-- `(Type, Type)`, the type of a pair of two types. With both, either
-- reading of `(Nat, Bool)` finds an implementation, so only the rule
-- decides what it prints.

import Prelude

%default total

interface Reading t where
  which : (0 _ : t) -> String

Reading Type where
  which _ = "the pair type"

-- An implementation's head is a type: `(Type, Type)` is `Pair Type Type`.
Reading (Type, Type) where
  which _ = "the pair"

-- A signature is expected to be a type: `(Nat, Bool)` is `Pair Nat Bool`.
-- The definition is expected to have that type, known and no universe:
-- `(S (S Z), False)` is `MkPair (S (S Z)) False`.
two : (Nat, Bool)
two = (S (S Z), False)

-- `Pair Nat (Pair Bool Char)` and `MkPair (S Z) (MkPair False 'c')`: the
-- first component is 1, and the second is the pair of the other two.
three : (Nat, Bool, Char)
three = (S Z, False, 'c')

main : IO ()
main = do
  -- Expected `Type`: the pair type, `Pair Nat Bool`.
  putStrLn (which {t = Type} (Nat, Bool))
  -- Expected `Pair Type Type`: the pair, `MkPair Nat Bool`.
  putStrLn (which {t = (Type, Type)} (Nat, Bool))
  -- Expected type unknown, and both readings fit (`Pair Nat Bool : Type`,
  -- `MkPair Nat Bool : (Type, Type)`): the default, the pair.
  putStrLn (which (Nat, Bool))
  -- Expected type unknown, and only the pair fits, `Z` being no type:
  -- `MkPair Z True`, shown "(0, True)".
  printLn (Z, True)
  printLn two
  printLn (fst three)
  printLn (snd three)
