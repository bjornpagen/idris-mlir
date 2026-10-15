module Main

-- A linear handle's size, read through an unqualified `size` on the right
-- of a linear pattern `let` and of a plain `let`. The name has two
-- candidates, and only the linear one fits the linear handle, so Idris
-- settles on it. Before the fork's fix the elaborator retried the value at
-- quantity one only on a bare linearity error, and the ambiguity (every
-- candidate failing at the context's quantity) refused the program.

import Prelude

%default total

data Handle : Type where
  MkHandle : Nat -> Handle

namespace Plain
  export
  size : List a -> Nat
  size = length

namespace Linear
  export
  size : (1 _ : Handle) -> Res Nat (const Handle)
  size (MkHandle n) = n # MkHandle n

twice : (1 _ : Handle) -> Res Nat (const Handle)
twice h = let n # h = size h in
          let m # h = size h in
          (n + m) # h

once : (1 _ : Handle) -> Res Nat (const Handle)
once h = let r = size h in r

close : (1 _ : Handle) -> ()
close (MkHandle _) = ()

-- What `f` gives of a fresh handle of size `k`, the handle closed.
measured : ((1 _ : Handle) -> Res Nat (const Handle)) -> Nat -> Nat
measured f k = let n # h = f (MkHandle k) in let () = close h in n

main : IO ()
main = do
  printLn (measured twice 3)
  printLn (measured once 3)
