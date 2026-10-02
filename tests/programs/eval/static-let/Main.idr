module Main

import Prelude

main : IO ()
main = do
  let f = \x => prim__add_Int x 100
  putStrLn (prim__cast_IntString (f (f 1)))
