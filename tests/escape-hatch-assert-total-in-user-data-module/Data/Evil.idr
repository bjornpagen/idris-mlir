module Data.Evil

import Prelude

public export
count : Int -> Int
count n = if n <= 0 then 0 else 1 + assert_total (count (n - 1))
