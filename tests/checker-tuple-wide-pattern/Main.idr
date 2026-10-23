module Main

-- A tuple of 64 components as a pattern: `Wide`'s value matched against
-- the 64 names, each pair of the pattern the pair `MkPair`, as the matched
-- value's type, `Wide`, says. `chars` gives back the 64 characters
-- written, "A" to "Z", "a" to "z", "0" to "9", "+" and "/", in order. The
-- program is accepted within the compiler's time for one command: each
-- pair of the pattern is read at that pair alone, so the work grows with
-- the components, not with every way of reading them.

import Prelude

%default total

-- Expected a type: each pair is the pair type.
0 Wide : Type
Wide =
  (Char, Char, Char, Char, Char, Char, Char, Char, Char, Char, Char, Char,
   Char, Char, Char, Char, Char, Char, Char, Char, Char, Char, Char, Char,
   Char, Char, Char, Char, Char, Char, Char, Char, Char, Char, Char, Char,
   Char, Char, Char, Char, Char, Char, Char, Char, Char, Char, Char, Char,
   Char, Char, Char, Char, Char, Char, Char, Char, Char, Char, Char, Char,
   Char, Char, Char, Char)

-- Expected `Wide`, known and no universe: each pair is the pair.
wide : Wide
wide =
  ('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N',
   'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b',
   'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p',
   'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '0', '1', '2', '3',
   '4', '5', '6', '7', '8', '9', '+', '/')

chars : Wide -> String
chars
  (c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15,
   c16, c17, c18, c19, c20, c21, c22, c23, c24, c25, c26, c27, c28, c29,
   c30, c31, c32, c33, c34, c35, c36, c37, c38, c39, c40, c41, c42, c43,
   c44, c45, c46, c47, c48, c49, c50, c51, c52, c53, c54, c55, c56, c57,
   c58, c59, c60, c61, c62, c63)
  = pack
      [c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15,
       c16, c17, c18, c19, c20, c21, c22, c23, c24, c25, c26, c27, c28, c29,
       c30, c31, c32, c33, c34, c35, c36, c37, c38, c39, c40, c41, c42, c43,
       c44, c45, c46, c47, c48, c49, c50, c51, c52, c53, c54, c55, c56, c57,
       c58, c59, c60, c61, c62, c63]

main : IO ()
main = putStrLn (chars wide)
