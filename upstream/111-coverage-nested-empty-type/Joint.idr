module Joint

%default total

data AllR : List Nat -> List Nat -> Type where
  Nil : AllR [] []
  (::) : (t : Nat) -> AllR xs ts -> AllR (x :: xs) (t :: ts)

data Head = MkHead (Maybe Nat) (List Nat)

-- A case block over a pair whose equation refines `r`, which the block
-- takes from its scope: the Refl refines it to `MkHead Nothing []`, so
-- the coverage check splits it and proposes `MkHead Nothing (_ :: _)`
-- with the scrutinee unsplit. Neither part of the scrutinee's type is
-- empty alone; together they are: the equation holds `ts = _ :: _`, and
-- then `AllR [] (_ :: _)` has no value.
atHead : (r : Head) -> (ts : List Nat ** (r = MkHead Nothing ts, AllR [] ts)) -> Nat
atHead r p = case p of
  ([] ** (Refl, [])) => Z

-- The frontend's Proof.Covers.atNamedType: a head read with its address
-- over the readings of no arguments, the equation inside a triple.
0 atNamed : (r : Head) -> (a : Maybe Nat ** ts : List Nat ** (r = MkHead a ts, a = a, AllR [] ts)) -> Nat
atNamed r p = case p of
  (a' ** [] ** (Refl, _, [])) => Z

-- The same as clauses: the case the clause misses, `MkHead Nothing (_ ::
-- _)`, is refuted as the impossible clause that names it is.
clauses : (r : Head) -> (ts : List Nat ** (r = MkHead Nothing ts, AllR [] ts)) -> Nat
clauses (MkHead Nothing []) ([] ** (Refl, [])) = Z

written : (r : Head) -> (ts : List Nat ** (r = MkHead Nothing ts, AllR [] ts)) -> Nat
written (MkHead Nothing []) ([] ** (Refl, [])) = Z
written (MkHead Nothing (_ :: _)) (_ ** (Refl, _)) impossible
