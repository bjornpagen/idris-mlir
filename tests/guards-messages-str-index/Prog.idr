module Prog

-- An index past the end of a string: the index's guard fails, and the
-- crash names the cause and the definition whose read failed, loaded from
-- its TTC, which keeps no location inside a term.
partial
charAt : Int -> Char
charAt i = prim__strIndex "abc" i

export partial
result : Char
result = charAt 5
