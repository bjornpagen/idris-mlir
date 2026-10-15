module Depth

%default total

||| The argument of the call is the parameter with one element fewer, seven
||| constructors deep: smaller by looking under six matching constructors.
deep : List a -> Nat
deep (a :: b :: c :: d :: e :: f :: g :: es) = deep (a :: b :: c :: d :: e :: f :: es)
deep _ = 0

||| Five deep, within the pinned checker's default depth.
shallow : List a -> Nat
shallow (a :: b :: c :: d :: e :: es) = shallow (a :: b :: c :: d :: es)
shallow _ = 0
