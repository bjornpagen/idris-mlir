module Core.InitPrimitives

import Core.Context
import Core.Primitives

%default covering

addPrim : {auto c : Ref Ctxt Defs} ->
          Prim -> Core ()
addPrim p
    = addBuiltin (opName (fn p)) (type p) (totality p) (fn p)

export
addPrimitives : {auto c : Ref Ctxt Defs} -> Core ()
addPrimitives
    = traverse_ addPrim allPrimitives
