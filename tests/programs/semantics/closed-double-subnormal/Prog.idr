module Prog

-- The smallest subnormal's text is its fewest digits that read back,
-- `5e-324` (findings/decision-primitive-semantics.md, "The text of a
-- Double"), without the mantissa width R6RS's printer adds, `5e-324|1`,
-- though the argument is a literal.

public export
subnormal : String
subnormal = prim__cast_DoubleString 4.9e-324
