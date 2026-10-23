module Machine

-- The shape the e-graph prototype met:
-- a loop over a linear state, its continuation a pattern-matching lambda
-- over the state and the loop's values whose body is a do block of pattern
-- binds, nested nine deep. Every bind, and every pattern of a lambda, is a
-- case block, so the innermost call is twenty-nine case blocks deep, and it
-- passes on the function's own implicit arguments (the machine's v, b and
-- m, and its instance). Linearity, the ambiguous (#), (::) and list
-- literals are not what costs: each can be taken away and the time stays.

%default total

export infixr 1 :&

public export
data Got : Type -> Type -> Type where
  (:&) : (1 r : res) -> (x : a) -> Got res a

public export
data Vals : (Type -> Type) -> List Type -> Type where
  Nil  : Vals v []
  (::) : v t -> Vals v ts -> Vals v (t :: ts)

public export
interface Machine (0 v : Type -> Type) (0 b : Type -> Type) (0 m : Type -> Type) | m where
  bind1 : (1 _ : m a) -> (1 _ : (1 _ : a) -> m c) -> m c
  pure1 : (1 _ : a) -> m a
  swap2 : (1 _ : LPair (b e) (b e)) -> m (Got (LPair (b e) (b e)) (v e))
  forUp : {0 s : Type} -> {ts : List Type} -> v Nat -> (1 st : s) -> Vals v ts ->
          (v Nat -> (1 _ : s) -> Vals v ts -> m (Got s (Vals v ts))) -> m (Got s (Vals v ts))

namespace L
  export
  (>>=) : Machine v b m => (1 _ : m a) -> (1 _ : (1 _ : a) -> m c) -> m c
  (>>=) = bind1

f : Machine v b m => v Nat -> (1 s1 : b Nat) -> (1 s2 : b Nat) -> Vals v [Nat, Nat] ->
    m (Got (LPair (b Nat) (b Nat)) (Vals v [Nat, Nat]))
f n s1 s2 [p, q] = L.do
  ((s1 # s2) :& z0) <- swap2 (s1 # s2)
  ((s1 # s2) :& [p, q]) <- forUp n (s1 # s2) [p, q]
    (\i0, (s1 # s2), [p, q] => L.do
        ((s1 # s2) :& z1) <- swap2 (s1 # s2)
        ((s1 # s2) :& [p, q]) <- forUp n (s1 # s2) [p, q]
          (\i1, (s1 # s2), [p, q] => L.do
              ((s1 # s2) :& z2) <- swap2 (s1 # s2)
              ((s1 # s2) :& [p, q]) <- forUp n (s1 # s2) [p, q]
                (\i2, (s1 # s2), [p, q] => L.do
                    ((s1 # s2) :& z3) <- swap2 (s1 # s2)
                    ((s1 # s2) :& [p, q]) <- forUp n (s1 # s2) [p, q]
                      (\i3, (s1 # s2), [p, q] => L.do
                          ((s1 # s2) :& z4) <- swap2 (s1 # s2)
                          ((s1 # s2) :& [p, q]) <- forUp n (s1 # s2) [p, q]
                            (\i4, (s1 # s2), [p, q] => L.do
                                ((s1 # s2) :& z5) <- swap2 (s1 # s2)
                                ((s1 # s2) :& [p, q]) <- forUp n (s1 # s2) [p, q]
                                  (\i5, (s1 # s2), [p, q] => L.do
                                      ((s1 # s2) :& z6) <- swap2 (s1 # s2)
                                      ((s1 # s2) :& [p, q]) <- forUp n (s1 # s2) [p, q]
                                        (\i6, (s1 # s2), [p, q] => L.do
                                            ((s1 # s2) :& z7) <- swap2 (s1 # s2)
                                            ((s1 # s2) :& [p, q]) <- forUp n (s1 # s2) [p, q]
                                              (\i7, (s1 # s2), [p, q] => L.do
                                                  ((s1 # s2) :& z8) <- swap2 (s1 # s2)
                                                  ((s1 # s2) :& [p, q]) <- forUp n (s1 # s2) [p, q]
                                                    (\i8, (s1 # s2), [p, q] => L.do
                                                        ((s1 # s2) :& y) <- swap2 (s1 # s2)
                                                        pure1 ((s1 # s2) :& [y, q]))
                                                  pure1 ((s1 # s2) :& [p, q]))
                                            pure1 ((s1 # s2) :& [p, q]))
                                      pure1 ((s1 # s2) :& [p, q]))
                                pure1 ((s1 # s2) :& [p, q]))
                          pure1 ((s1 # s2) :& [p, q]))
                    pure1 ((s1 # s2) :& [p, q]))
              pure1 ((s1 # s2) :& [p, q]))
        pure1 ((s1 # s2) :& [p, q]))
  pure1 ((s1 # s2) :& [p, q])
