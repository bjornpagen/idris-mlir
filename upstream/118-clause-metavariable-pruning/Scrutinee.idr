module Scrutinee

-- The same on a case of an expression, which splits no variable of the
-- environment.
data Edit = Keep String | Delete String

render : Edit -> String
render e =
  let (mark, l) = case id e of
                    Keep x => (" ", x)
                    Delete x => ("-", x)
  in mark ++ l
