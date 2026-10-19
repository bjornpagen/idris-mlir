module Prog

-- An index past the end of a string: the index's guard fails, and the
-- crash names the cause and the definition whose read failed, loaded from
-- its TTC, which keeps no location inside a term.
export partial
charAt : String -> Int -> Char
charAt s i = prim__strIndex s i
