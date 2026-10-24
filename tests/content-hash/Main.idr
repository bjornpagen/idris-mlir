module Main

-- XXH3's 128-bit hash, seed 0 and the default secret, from the mlir-hash
-- library: the hash the frontend takes the low half of when a key's print
-- loses part of an instance's identity. Its oracle is the reference's own
-- values: the hash of the first n bytes of the reference's sanity buffer
-- at each n its own check reads, then of three texts, each written as its
-- low and high halves in hexadecimal, as the reference publishes them.

import Prelude
import Data.Bits
import Data.Fin
import Hash.XXH3

-- The first n bytes of the sanity buffer: byte i is the top byte of g_i,
-- where g_0 is 2654435761 and g_(i+1) is g_i * 11400714785074694797,
-- modulo 2^64.
sanity : Nat -> List Bits8
sanity n = go n 2654435761
  where
    go : Nat -> Bits64 -> List Bits8
    go Z _ = []
    go (S k) g = cast (shiftR g 56) :: go k (g * 11400714785074694797)

-- A text of ASCII characters as its bytes, each character's code.
ascii : String -> List Bits8
ascii key = map (cast . ord) (unpack key)

-- A word as 16 lowercase hexadecimal digits, most significant first.
hex16 : Bits64 -> String
hex16 x = pack (map digit [60, 56, 52, 48, 44, 40, 36, 32, 28, 24, 20, 16, 12, 8, 4, 0])
  where
    digit : Fin 64 -> Char
    digit at =
      let d = shiftR x at .&. 0xF in
      if d < 10 then chr (cast d + ord '0') else chr (cast d - 10 + ord 'a')

line : String -> Hash128 -> String
line what h = what ++ ": " ++ hex16 h.low ++ " " ++ hex16 h.high

main : IO ()
main = do
  for_ [0, 1, 6, 12, 24, 48, 81, 222, 403, 512, 2048, 2240, 2367] $ \n =>
    putStrLn (line (show n) (xxh3_128 (sanity n)))
  for_ ["a", "abc", "Prelude.Types.List[Int]"] $ \key =>
    putStrLn (line key (xxh3_128 (ascii key)))
