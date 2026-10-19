module Main

-- `Show (DPair a p)` takes `{y : a} -> Show (p y)`: a function from the
-- pair's first component, a runtime value, to an implementation. Idris
-- fixes the implementation at every index, so the function is constant in
-- its argument (`\_ => String`) or uses it only where it is erased (the
-- index of `Tag n` and of `Vect n Int`), and `show` specializes as for any
-- other implementation.

import Prelude
import Data.Vect

data Tag : Nat -> Type where
  Zero : Tag Z
  Next : Tag n -> Tag (S n)

Show (Tag n) where
  showPrec _ Zero = "Zero"
  showPrec d (Next t) = showCon d "Next" (showArg t)

tag : (n : Nat) -> Tag n
tag Z = Zero
tag (S k) = Next (tag k)

-- A field that is also the index: Idris finds `n` at the same place in
-- every constructor, as it finds a parameter, but the constructor holds it
-- at runtime, and the match's tree names the erased index for it.
data Tagged : Nat -> Type where
  MkTagged : (n : Nat) -> Tagged n

Show (Tagged n) where
  showPrec d (MkTagged k) = showCon d "MkTagged" (showArg k)

-- The same, a match deeper: the type of the held value comes from Hold's.
data Holder : Type where
  Hold : {0 m : Nat} -> Tagged m -> Holder

held : Holder -> Nat
held (Hold (MkTagged k)) = k

main : IO ()
main = do
  line <- getLine
  let k = cast {to = Int} line
  let n = cast {to = Nat} k
  printLn (the (DPair Int (\_ => String)) (k ** "x"))
  printLn (the (List (DPair Int (\_ => Bool))) [(k ** True), (k + 1 ** False)])
  printLn (the (DPair Nat Tag) (n ** tag n))
  printLn (the (DPair Nat (\m => Vect m Int)) (n ** replicate n k))
  printLn (the (DPair Int (\_ => DPair Nat Tag)) (k ** (S n ** tag (S n))))
  printLn (the (DPair Nat Tagged) (n ** MkTagged n))
  printLn (held (Hold (MkTagged (n + 5))))
