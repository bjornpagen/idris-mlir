module Main

-- A quoted search, `(%search)`, as base's Language.Reflection quotes one
-- in `search` and Deriving.Common in `isProvable` and `hasImplementation`.
-- A quote is the term its syntax writes in the language: base's `ISearch`,
-- holding the depth the language gives `%search`. This type checker's
-- search has no depth, and it refused the quote: "A search has no depth to
-- give a script". The quote is now that term, its depth `%search`'s, which
-- reading the term back for a script drops. Checking the types is the
-- test; the program only runs.

import Prelude
import Language.Reflection

%default total

0 searched : TTImp
searched = `(%search)

0 depthOf : TTImp -> Nat
depthOf (ISearch _ depth) = depth
depthOf _ = 0

0 written : depthOf Main.searched = 50
written = Refl

main : IO ()
main = putStrLn "checked"
