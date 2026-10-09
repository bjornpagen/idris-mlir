-- Each right-hand side applies a primitive to constants, or is a literal
-- whose conversion does. The pinned Idris checks each to the constant its
-- own evaluator computes, running on Chez Scheme, so a backend whose
-- primitive means something else never sees the call.

-- Chez reads "12.7" as 12; a backend may read it as no Int at all.
plain : Int
plain = prim__cast_StringInt "12.7"

-- Chez writes +inf.0; IEEE 754 spells it inf, and Node writes Infinity.
partial
infinity : String
infinity = prim__cast_DoubleString (prim__div_Double 1.0 0.0)

-- The evaluator's cast writes the escape `show` writes, \233, not the
-- character.
eAcute : String
eAcute = prim__cast_CharString '\233'

-- A literal's conversion runs its FromString implementation, primitive
-- and all.
public export
data N = MkN Int

public export
FromString N where
  fromString s = MkN (prim__cast_StringInt s)

viaLiteral : N
viaLiteral = "12.7"

-- A literal of a primitive type is a constant, and stays one.
small : Int
small = 42
