module Libraries.Text.Distance.Levenshtein

import Data.String

%default total

||| Self-evidently correct but O(3 ^ (min mn)) complexity
spec : String -> String -> Nat
spec a b = loop (fastUnpack a) (fastUnpack b) where

  loop : List Char -> List Char -> Nat
  loop [] ys = length ys -- deletions
  loop xs [] = length xs -- insertions
  loop (x :: xs) (y :: ys)
    = if x == y then loop xs ys -- match
      else 1 + minimum
           [ loop (x :: xs) ys -- insert y
           , loop xs (y :: ys) -- delete x
           , loop xs ys        -- substitute y for x
           ]

-- here we change Levenshtein slightly so that we may only substitute
-- alpha / numerical characters for similar ones. This avoids suggesting
-- "#" as a replacement for an out of scope "n".
cost : Char -> Char -> Nat
cost c d
    = if c == d then 0 else
      if isAlpha c && isAlpha d then 1 else
      if isDigit c && isDigit d then 1 else 2

||| Dynamic programming, one row of the table at a time. Row j holds, for
||| each i from 0 to |a|, the distance between the first i characters of a
||| and the first j of b. Row 0 is 0, 1, ..., |a| (insertions), and each row
||| starts with j (deletions).
distance : List Char -> List Char -> Nat
distance as bs = lastOf (rows 1 bs [0 .. length as])
  where
    -- the cells of row j after the first, from row j-1 and the j-th
    -- character d of b, with the formula of the specification's `loop`
    cells : Char -> (left : Nat) -> List Char -> List Nat -> List Nat
    cells d left (c :: cs) (diag :: up :: ups)
        = let here = minimum [ 1 + up             -- insert y
                             , 1 + left           -- delete x
                             , cost c d + diag    -- equal or substitute y for x
                             ] in
              here :: cells d here cs (up :: ups)
    cells _ _ _ _ = []

    rows : (j : Nat) -> List Char -> List Nat -> List Nat
    rows j [] row = row
    rows j (d :: ds) row = rows (S j) ds (j :: cells d j as row)

    -- the last cell of the last row; a row is never empty, and the first
    -- cell of the last row is |b|
    lastOf : List Nat -> Nat
    lastOf = foldl (\ _, x => x) (length bs)

export
compute : HasIO io => String -> String -> io Nat
compute a b = pure (distance (unpack a) (unpack b))
