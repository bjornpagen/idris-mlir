module Data.Evil

import Prelude

-- The refused program's module without its %inline.
public export
double : Int -> Int
double x = x + x
