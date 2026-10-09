module Prog

-- "12.7" is no literal of an Int, so the cast is 0
-- (findings/decision-primitive-semantics.md, "Casts from String"), not the
-- 12 a Scheme reading of the string truncates to, though the argument is a
-- literal.

public export
plain : Int
plain = prim__cast_StringInt "12.7"
