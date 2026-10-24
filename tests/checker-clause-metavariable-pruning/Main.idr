module Main

-- Pattern lets of case blocks whose type is found from their clauses.
-- Each clause builds a pair whose first part is a string literal, whose
-- type is an unknown of the clause, standing over the clause's pattern
-- variables, which only the let's body or the literal's default fixes;
-- the case's own type stands over the variables outside the clause, so it
-- could not be solved to a term holding the literal's type, and the case
-- was refused: "Can't infer type for case scrutinee". The literal's type
-- cannot depend on the clause's variables in any solution, so it is now
-- pruned of them, and the case's type is the pair type over it. `render`
-- splits the variable it cases on; `renderOf` cases on an expression,
-- which splits none.
-- The stock Idris is patched for it (upstream/118-clause-metavariable-
-- pruning); the type checker has the change as its own code, and this
-- test checks it.

import Prelude

data Edit = Keep String | Delete String | Insert String

render : Edit -> String
render e =
  let (mark, l) = case e of
                    Keep x => (" ", x)
                    Delete x => ("-", x)
                    Insert x => ("+", x)
  in mark ++ l

renderOf : Edit -> String
renderOf e =
  let (mark, l) = case id e of
                    Keep x => (" ", x)
                    Delete x => ("-", x)
                    Insert x => ("+", x)
  in mark ++ l

main : IO ()
main = do
  putStrLn (render (Keep "kept"))
  putStrLn (render (Delete "gone"))
  putStrLn (render (Insert "new"))
  putStrLn (renderOf (Keep "kept"))
  putStrLn (renderOf (Insert "new"))
