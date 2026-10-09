module Prog

-- 12.886856079101562 and ...563 both read back as this double, and are
-- equally near it: its text is the even one
-- (findings/decision-primitive-semantics.md, "The text of a Double"),
-- though the argument is a literal.

public export
tie : String
tie = prim__cast_DoubleString 12.886856079101562
