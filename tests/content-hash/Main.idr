module Main

-- XXH3's 128-bit hash in the frontend, from which every generated name
-- takes its 16 hex digits: the hash of the first n bytes of the published
-- sanity buffer at each n of the reference's own check, and of three
-- texts, each as its low and high halves.

import Prelude
import IdrisMLIR.Ids

-- The first n bytes of the sanity buffer: byte i is the top byte of g_i,
-- where g_0 is 2654435761 and g_(i+1) is g_i * 11400714785074694797,
-- modulo 2^64.
sanity : Nat -> List Bits8
sanity n = go n 2654435761
  where
    go : Nat -> Bits64 -> List Bits8
    go Z _ = []
    go (S k) g = cast (prim__shr_Bits64 g 56) :: go k (g * 11400714785074694797)

line : String -> Hash128 -> String
line what h = what ++ ": " ++ hex16 h.low ++ " " ++ hex16 h.high

main : IO ()
main = do
  for_ [0, 1, 6, 12, 24, 48, 81, 222, 403, 512, 2048, 2240, 2367] $ \n =>
    putStrLn (line (show n) (xxh3_128 (sanity n)))
  for_ ["a", "abc", "Prelude.Types.List[Int]"] $ \key =>
    putStrLn (line key (xxh3_128 (utf8 key)))
