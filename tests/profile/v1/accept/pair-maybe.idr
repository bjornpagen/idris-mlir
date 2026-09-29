-- stdout: 7\nx\n
module Main

import Prelude

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
