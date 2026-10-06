module Main

-- The top module Prelude defines nothing of its own: it re-exports
-- Builtin, PrimIO and the Prelude.* modules, whose fixtures cover each
-- export where it is defined, so what it gives a program is the
-- re-exports themselves (covers). This program imports Prelude alone and
-- reaches, unqualified, definitions of the modules it re-exports, each
-- line printed so that Chez checks what it computes.

import Prelude

main : IO ()
main = do
  let n = the Int 7
  printLn (fst (n, "Builtin"))
  printLn (not (n > 9))
  printLn (the Double (cast n))
  printLn (compare n 3)
  printLn (map (* 2) [n, 1])
  putStrLn "interpolated \{show n}"
  printLn (abs (negate n))
  printLn (1 + n * 2)
  printLn (length [n, n])
