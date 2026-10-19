module Main

import Prelude

-- getBinderUnder's shape: a scope that grows on every round, under a family
-- whose value's index is erased. At the family's head, the scope keys
-- nothing and the recursion stays one instance.
data Tm : List () -> Type where
  V : Tm vs

data Env : (List () -> Type) -> List () -> Type where
  Nil : Env tm []
  (::) : tm vs -> Env tm vs -> Env tm (() :: vs)

interface Weaken (0 tm : List () -> Type) where
  weakenNs : (ns : List ()) -> tm vs -> tm (ns ++ vs)

Weaken Tm where
  weakenNs _ V = V

under : Weaken tm => {vars : List ()} -> (ns : List ()) -> Env tm vars -> Nat -> Maybe (tm (reverseOnto vars ns))
under ns [] _ = Nothing
under {vars = () :: vs} ns (b :: env) Z = Nothing
under {vars = () :: vs} ns (b :: env) (S k) = under (() :: ns) env k

main : IO ()
main = printLn (maybe 0 (const 1) (under {tm = Tm} [] [V, V, V] 2))
