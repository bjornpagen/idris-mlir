||| Full Core to the contract: one module in the custom syntax of the `idr`,
||| `func`, `arith`, `math` and `ub` dialects.
|||
||| A body is written by one fold over `Term`, a paramorphism: the algebra
||| turns each layer into an emitter, which, given the values of the
||| variables in scope and the type the context expects, appends the layer's
||| operations and returns its value. The alternatives Idris proved
||| impossible are left out, which is why the algebra sees each subterm as it
||| was. Control flow is regions: a match is `idr.match` or `idr.match_lit`,
||| and a lambda or `Delay` is a lifted function whose leading parameters are
||| its captures.
|||
||| Types are synthesized as they are written, bidirectionally: every
||| emitter returns its value's type (TTC drops the types of `let`s), and a
||| context that knows the type it expects passes it down, for
||| the one term whose type its parts do not give, a closure whose body never
||| returns.
module IdrisMLIR.Emit

import IdrisMLIR.Emit.Declarations
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Ids
import IdrisMLIR.MLIR
import IdrisMLIR.Term

import Control.Monad.State

%default total

||| The contract text of a program: the `idr` module `idris-mlir-cc` reads.
export
emit : Source -> Either String String
emit src = do
  let ix = index src
  let start = MkES 0 [<] [<] (MkOwner "" (shown "") False)
  (_, ops) <- runStateT start $ do
    datas <- traverse (dataDecl ix) src.datas
    fns <- traverse (function ix src.root) src.fns
    pure (datas ++ concat fns)
  pure (showModule "idr.program" ops)
