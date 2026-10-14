||| Full Core to the contract: one module of the `idr`, `func`, `arith`,
||| `math`, `memref` and `ub` dialects, each op made by its builder, which is
||| generated from the op's ODS (IdrisMLIR.Dialect.*), and written in MLIR's
||| generic form (IdrisMLIR.MLIR).
|||
||| A body is written by one fold over `Term`, a paramorphism: the algebra
||| turns each layer into an emitter, which, given the values of the
||| variables in scope and the type the context expects, appends the layer's
||| operations and returns its value. The alternatives Idris proved
||| impossible are left out, which is why the algebra sees each subterm as it
||| was. Control flow is regions: a match is `idr.match` or `idr.match_lit`,
||| a lambda `idr.lambda` and a `Delay` `idr.delay`, whose bodies use the
||| values of their scope where they are.
|||
||| Types are synthesized as they are written, bidirectionally: every
||| emitter returns its value's type (TTC drops the types of `let`s), and a
||| context that knows the type it expects passes it down, for
||| the one term whose type its parts do not give, a closure whose body never
||| returns.
module IdrisMLIR.Emit

import IdrisMLIR.Dialect.Builtin as Builtin
import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Emit.Declarations
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Ids
import IdrisMLIR.MLIR
import IdrisMLIR.Term

import Control.Monad.State
import Data.List

%default total

||| The contract text of a program, the `idr` module idris-mlir reads, as
||| texts in order: the text before its declarations, each declaration's
||| (its data instances', then its functions'), and the text after them. A
||| declaration is emitted and printed only when its text is forced, and
||| dropped once its text is written, so that neither the module's ops nor
||| its text, which are the size of the program, ever exist whole. A
||| declaration `Emit` cannot write is the error its text is. The module is
||| at the root's location, which is main's, so that whatever the pipeline
||| reports about the whole program is at the user's code.
export covering
emit : Source -> Either String (List (Lazy (Either String String)))
emit src = do
  let Just root = find (\f => f.id == src.root) src.fns
    | Nothing => Left "the root function is missing"
  let ix = index src
  let (before, after) = moduleFrame (At root.loc)
                          ({ attributes := [Idr.programDiscardable] }
                             (Builtin.moduleOp (MkRegion [] [])))
  pure (Right before :: map (dataText ix) src.datas ++ map (fnText ix src.root) src.fns ++
        [Right after])
  where
    -- Each declaration is emitted from the state a module starts in:
    -- a function numbers its own values from 0 and gives back the state it
    -- was given, and a data instance numbers none.
    declaration : E Statement -> Either String String
    declaration act = topLevel <$> evalStateT (MkES 0 [<]) act
    dataText : Index -> Data -> Lazy (Either String String)
    dataText ix d = declaration (dataDecl ix d)
    fnText : Index -> FnId -> TFn -> Lazy (Either String String)
    fnText ix root f = declaration (function ix root f)
