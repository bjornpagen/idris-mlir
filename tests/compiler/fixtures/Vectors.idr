module Vectors

%default total

public export
data Count = Zero | Next Count

public export
plus : Count -> Count -> Count
plus Zero right = right
plus (Next left) right = Next (plus left right)

public export
data Vector : Count -> Type -> Type where
  Empty : Vector Zero a
  Cons : a -> Vector n a -> Vector (Next n) a

public export
append : Vector n a -> Vector m a -> Vector (plus n m) a
append Empty right = right
append (Cons item rest) right = Cons item (append rest right)

public export
keep : (0 witness : Count) -> (value : Count) -> Count
keep witness value = value

public export
runtimeLength : (n : Count) -> Vector n a -> Count
runtimeLength n values = n
