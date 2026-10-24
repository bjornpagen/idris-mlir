-- expect: elaboration, line 24
-- message: Can't find an implementation for Way
module Main

-- A goal met again on its path: a Way is sought by `again`, which asks a
-- Way, the goal it was sought for. The repeat fails that step, as
-- upstream's cycle check does, and with no other way to a Way the search
-- finds nothing for the goal it sought, which the refusal names. near/
-- adds another way, which the search finds past the repeat.

import Prelude

-- No constructor is a hint, so `again` is the search's only way.
data Way : Type where
  [noHints]
  Base : Way
  Again : Way -> Way

%hint
again : Way -> Way
again = Again

way : Way
way = %search

main : IO ()
main = printLn (the Int 1)
