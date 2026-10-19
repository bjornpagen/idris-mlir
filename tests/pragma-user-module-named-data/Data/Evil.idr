module Data.Evil

import Prelude

-- A pragma the profile accepts only in a trusted library.
%inline
public export
double : Int -> Int
double x = x + x
