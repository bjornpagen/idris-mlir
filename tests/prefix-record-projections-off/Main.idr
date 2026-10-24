module Main

import Prelude

-- `%prefix_record_projections off` has the checker define a record's
-- projections only in postfix form, as upstream does: `Box` defines no
-- function `Box.size`, so the one below is the only `size`, and `b.size`
-- is the projection. With the pragma left out, `size` in `main` would be
-- ambiguous between the two. The pragma's whole meaning is the checker's
-- elaboration, so a user module may write it.

%prefix_record_projections off

record Box where
  constructor MkBox
  size : Int
  weight : Int

size : Box -> Int
size b = b.size * 10 + b.weight

main : IO ()
main = printLn (size (MkBox 4 2))
