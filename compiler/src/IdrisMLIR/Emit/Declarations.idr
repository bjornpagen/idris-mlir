||| The module's declarations: data instances and functions, each with the
||| functions lifted from it.
module IdrisMLIR.Emit.Declarations

import IdrisMLIR.Dialect.Func as Func
import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Emit.Attributes
import IdrisMLIR.Emit.Bodies
import IdrisMLIR.Emit.Breakers
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Emit.Types
import IdrisMLIR.Facts
import IdrisMLIR.Ids
import IdrisMLIR.MLIR
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.List
import Data.SnocList
import Data.SortedSet
import Data.Vect

%default total

||| A declaration is located by its Idris name.
export
dataDecl : Index -> Data -> E Statement
dataDecl ix d = do
  ctors <- traverse ctor d.cons
  let box = case d.repr of
              Sop => False
              Box => True
  pure (MkStatement Nothing (Idr.dataOp {box = box} (mangle d.id.name) (MkRegion [] ctors))
                    (Named d.idrisName d.loc))
  where
    ctor : Con -> E Statement
    ctor c = do
      ts <- traverse (binderType ix) c.fields
      pure (MkStatement Nothing (Idr.ctorOp (mangle c.id.name) ts) (Named c.idrisName c.loc))

||| A function, and the functions lifted from it. Only the root is public.
export
function : Index -> FnId -> TFn -> E (List Statement)
function ix root f = do
  let sym = mangle f.id.name
  modify { lifted := [<] }
  ((params, res), ops) <- inFunction $ do
    params <- traverse (\b => (\n => val n (typeOf b) (binderUse b)) <$> fresh) f.params
    res <- plain' (para alg' f.body (\i => index i params) (Just f.result))
    pure (params, res)
  rt <- mlirType ix f.result
  args <- traverse (operand ix) (toList params)
  body <- epilogue ix f.loc rt res ops
  -- A loop breaker: inlining it could unroll a cycle.
  let fn = Func.funcOp {symVisibility = if f.id == root then Nothing else Just "private"}
                       {noInline = contains (FnNode f.id) ix.breakers} sym
                       (functionType (map (\a : Value => a.type) args) [rt])
                       (MkRegion args body)
  inner <- gets (.lifted)
  pure (MkStatement Nothing ({ attributes := attributes (own f) } fn) (Named f.idrisName f.loc)
        :: (inner <>> []))
  where
    alg' : {0 b : Type} -> TermF (Sub Em) b -> Em b
    alg' = alg ix (MkOwner (mangle f.id.name) f.idrisName (inherited f))
    plain' : E (Maybe Val) -> E (Maybe Val)
    plain' = plain ix f.loc
