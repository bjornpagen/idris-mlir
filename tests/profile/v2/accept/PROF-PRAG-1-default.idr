-- exit: 0
-- stdout: 0.5\n
module Main

-- rule: PROF-PRAG-1
-- %default only changes which totality Idris requires.

import Prelude

%default partial

half : Double -> Double
half x = prim__div_Double x 2.0

main : IO ()
main = putStrLn (prim__cast_DoubleString (half 1.0))
