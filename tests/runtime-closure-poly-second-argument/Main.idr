module Main

-- A closure held in a field takes a polymorphic function after its first
-- argument and applies it at two types. The function given where the
-- closure is applied is the member of that parameter type's choice, as one
-- given to a definition is, and each application inside the closure
-- applies it at its own types.

import Prelude

record Pairing where
  constructor MkPairing
  run : Int -> ({0 a : Type} -> a -> List a) -> (List Int, List String)

single : {0 a : Type} -> a -> List a
single x = [x]

main : IO ()
main = do
  line <- getLine
  let p = MkPairing (\n, g => (g n, g line))
  printLn (p.run 3 single)
  printLn (p.run 4 (\x => [x, x]))
