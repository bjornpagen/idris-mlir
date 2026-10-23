module Main

-- Pairs in a type whose parts are bound implicitly, as base's
-- Decidable.Equality states `pairInjective`: `(a, b) = (c, d)`. Each pair's
-- expected type is unknown, so its parts are elaborated against unknown
-- types of their own, and the pair settles as a value, `MkPair a b`; a part
-- bound implicitly takes that unknown as its type. Where nothing solves the
-- unknown (one pair's, here, once the other's are solved by them), it is
-- bound as an argument of the type, as an application binds its unsolved
-- implicit arguments. The type checker left both unknowns
-- unsolved and refused each definition: "Unsolved holes: pairFst,
-- pairSnd". A tuple nests pairs, its inner pair a part of the outer one
-- (`tripleInjective`).

import Prelude

%default total

pairInjective : (a, b) = (c, d) -> (a = c, b = d)
pairInjective Refl = (Refl, Refl)

0 firsts : (a, b) = (c, d) -> a = c
firsts eq = fst (pairInjective eq)

0 tripleInjective : (a, b, c) = (d, e, f) -> (a = d, (b, c) = (e, f))
tripleInjective Refl = (Refl, Refl)

main : IO ()
main = case pairInjective {a = Z} {b = True} {c = Z} {d = True} Refl of
  (Refl, Refl) => putStrLn "injective"
