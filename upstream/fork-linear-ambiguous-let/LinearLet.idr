module LinearLet

%default total

||| A resource that is used once.
export
data Handle : Type where
  MkHandle : Nat -> Handle

namespace Plain
  ||| A size of an unrestricted value: the candidate that does not fit.
  export
  size : List a -> Nat
  size = length

namespace Linear
  ||| A handle's size, and the handle given back.
  export
  size : (1 _ : Handle) -> Res Nat (const Handle)
  size (MkHandle n) = n # MkHandle n

||| The handle's size, read twice through an unqualified `size` on the
||| right of a linear pattern `let`. The name has two candidates, and only
||| the linear one fits the linear handle.
twice : (1 _ : Handle) -> Res Nat (const Handle)
twice h = let n # h = size h in
          let m # h = size h in
          (n + m) # h

||| The same through a plain `let`, which binds the pair linearly.
once : (1 _ : Handle) -> Res Nat (const Handle)
once h = let r = size h in r
