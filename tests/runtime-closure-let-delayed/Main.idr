module Main

-- A polymorphic function applied twice (`apply2`), given a lambda whose
-- body binds, by a `let`, a second polymorphic function whose body is a
-- `Delay`. The program fixes every function: the lambda and `k` are each
-- one closure, the same at every use, and `k` is applied at each use's
-- types at the type its `let` gives it.

import Prelude

apply2 : ({0 a : Type} -> a -> a) -> Nat -> Nat
apply2 f n = f (f n)

main : IO ()
main = printLn (apply2 (\x => let k : ({0 b : Type} -> b -> Lazy b) = (\z => Delay z) in Force (k x)) 3)
