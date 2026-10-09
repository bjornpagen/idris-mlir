module Prog

-- A primitive applied to literals means what the runtime computes, as it
-- does on values read at run time: the text of 1.0 / 0.0 is IEEE 754's
-- `inf`, not the `+inf.0` of the Scheme that runs Idris's evaluator. The
-- division is not covering, so the constant is partial.

public export partial
infinity : String
infinity = prim__cast_DoubleString (prim__div_Double 1.0 0.0)
