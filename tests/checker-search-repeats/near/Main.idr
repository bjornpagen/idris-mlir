module Main

-- A goal met again on its path fails that step and no more: a Way is
-- sought by `again`, which asks a Way, the goal it was sought for, and by
-- `base`, which asks nothing. The repeat fails `again`'s step, as
-- upstream's cycle check does, so the search goes on to `base`, finds it,
-- and the program prints which way it found. Had the repeat ended the
-- whole search, as a growth does, it would have found nothing.

import Prelude

-- No constructor is a hint, so the hints are the search's only ways.
data Way : Type where
  [noHints]
  Base : Way
  Again : Way -> Way

%hint
again : Way -> Way
again = Again

%hint
base : Way
base = Base

way : Way
way = %search

main : IO ()
main = putStrLn (case way of
                      Base => "base"
                      Again _ => "again")
