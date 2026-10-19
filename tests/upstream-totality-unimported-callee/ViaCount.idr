module ViaCount

import Prelude
import Count

%default total

export covering
viaCount : Nat -> Nat
viaCount x = count x
