module Main

-- A tuple of 64 components, pairs nested to the right, 63 deep, as a type,
-- as a value, and as a value whose expected type is unknown: the type is
-- `Pair Char (Pair Char (...))` and the value
-- `MkPair 'A' (MkPair 'B' (...))`, so `chars` gives back the 64 characters
-- written, "A" to "Z", "a" to "z", "0" to "9", "+" and "/", in order. The
-- program is accepted within the compiler's time for one command: each
-- pair's two readings are tried at that pair alone, so the work grows with
-- the components, not with every way of reading them. `chars` matches by
-- the constructor, so the syntax is read only as a type and as a value
-- here; as a pattern it has a test of its own.

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
  (MkPair c0 (MkPair c1 (MkPair c2 (MkPair c3 (MkPair c4 (MkPair c5 (MkPair
  c6 (MkPair c7 (MkPair c8 (MkPair c9 (MkPair c10 (MkPair c11 (MkPair c12
  (MkPair c13 (MkPair c14 (MkPair c15 (MkPair c16 (MkPair c17 (MkPair c18
  (MkPair c19 (MkPair c20 (MkPair c21 (MkPair c22 (MkPair c23 (MkPair c24
  (MkPair c25 (MkPair c26 (MkPair c27 (MkPair c28 (MkPair c29 (MkPair c30
  (MkPair c31 (MkPair c32 (MkPair c33 (MkPair c34 (MkPair c35 (MkPair c36
  (MkPair c37 (MkPair c38 (MkPair c39 (MkPair c40 (MkPair c41 (MkPair c42
  (MkPair c43 (MkPair c44 (MkPair c45 (MkPair c46 (MkPair c47 (MkPair c48
  (MkPair c49 (MkPair c50 (MkPair c51 (MkPair c52 (MkPair c53 (MkPair c54
  (MkPair c55 (MkPair c56 (MkPair c57 (MkPair c58 (MkPair c59 (MkPair c60
  (MkPair c61 (MkPair c62
  c63)))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))))
  = pack
      [c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15,
       c16, c17, c18, c19, c20, c21, c22, c23, c24, c25, c26, c27, c28, c29,
       c30, c31, c32, c33, c34, c35, c36, c37, c38, c39, c40, c41, c42, c43,
       c44, c45, c46, c47, c48, c49, c50, c51, c52, c53, c54, c55, c56, c57,
       c58, c59, c60, c61, c62, c63]

main : IO ()
main = do
  putStrLn (chars wide)
  -- `unknown`'s type is not known while its value is read: at each pair
  -- only the pair fits, a character being no type.
  let unknown =
        ('A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
         'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
         'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
         'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z',
         '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '/')
  putStrLn (chars unknown)
