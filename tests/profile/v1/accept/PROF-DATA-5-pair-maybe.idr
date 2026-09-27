-- stdout: 7\nx\n
module Main

import Prelude

-- rule: ELIM-MONO-1, ELIM-MONO-2, ELIM-MONO-4, FE-TR-5
data Opt a = None | Some a

orElse : a -> Opt a -> a
orElse d None = d
orElse _ (Some x) = x

main : IO ()
main = do
  let a : Opt Int = Some 7
  let b : Opt Char = None
  let p = MkPair a b
  putStrLn (prim__cast_IntString (orElse 0 (fst p)))
  putChar (orElse 'x' (snd p))
  putStrLn ""
