import Data.Vect

cross_product : Vect n a -> Vect m b -> Vect (n * m) (a,b)

foo : (n : Nat) -> (us, vs : List Bool) -> (xs : Vect n Nat) ->
      (ys : Vect (length (us ++ vs)) Nat) ->
      Vect (length (us ++ vs) * b * (length (us ++ vs))) (Nat, Nat, Nat)
foo n us vs xs ys = replace {p = id} ?goal
  (cross_product ys (cross_product xs xs))
