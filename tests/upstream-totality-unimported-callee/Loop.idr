module Loop

import Prelude

%default total

export covering
loop : Nat -> Nat
loop x = loop (S x)
