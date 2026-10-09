module Prog

-- The head of the empty string: the string's guard fails, and the crash
-- names the cause and the definition whose read failed, loaded from its
-- TTC, which keeps no location inside a term.
partial
first : String -> Char
first s = prim__strHead s

export partial
result : Char
result = first ""
