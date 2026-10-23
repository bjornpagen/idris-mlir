module Tuple

-- A pattern let of a case whose type is found from its clauses. Each
-- clause builds a pair whose first part is a string literal, whose type
-- (a metavariable of the clause, over its pattern variables) is fixed only
-- by the let's body or the literal's default; the case's own type stands
-- over the variables outside the clause, so it cannot be solved to a term
-- that mentions the literal's type until that metavariable is pruned of
-- the clause's variables, which it cannot depend on.
data Edit = Keep String | Delete String | Insert String

render : Edit -> String
render e =
  let (mark, l) = case e of
                    Keep x => (" ", x)
                    Delete x => ("-", x)
                    Insert x => ("+", x)
  in mark ++ l
