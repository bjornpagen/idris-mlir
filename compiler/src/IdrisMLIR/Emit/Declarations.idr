||| The module's declarations: data instances and functions, each named by
||| its symbol and stating its key as `#idr.instance`.
module IdrisMLIR.Emit.Declarations

import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Emit.Bodies
import IdrisMLIR.Emit.Index
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Emit.Types
import IdrisMLIR.Facts
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.List
import Data.Vect

%default total

||| What a function or a data instance is an instance of, as text.
instanceAttr : InstanceKey -> MlirAttr
instanceAttr key = Idr (InstanceAttr key.origin (map StringAttr key.arguments))

||| A declaration is located by its Idris name, a constructor by its own.
export
dataDecl : Index -> Data -> E Statement
dataDecl ix d = do
  sym <- dataSymbol ix d.id
  ctors <- traverse ctor d.cons
  let box = case d.repr of
              Sop => False
              Box => True
  pure (MkStatement Nothing
                    (Idr.dataOp {box = box, instance = Just (instanceAttr d.key)} sym (MkRegion [] ctors))
                    (Named (shown d.key.origin) d.loc))
  where
    ctor : Con -> E Statement
    ctor c = do
      ts <- traverse (binderType ix) c.fields
      pure (MkStatement Nothing (Idr.ctorOp c.id.name ts) (Named c.idrisName c.loc))

||| A function, located by its Idris name, each parameter by the name Idris
||| gave it. Only the root is public. What Idris proved of it and where its
||| code is from are its own attributes: `total` when every loop of its
||| body is one Idris proved terminating, `break_last` when its code is
||| from a library a cycle of references breaks at only when the cycle has
||| no function from elsewhere (the registry's *break last*), which
||| `idr-loop-breakers` reads, never the location.
export
function : Index -> FnId -> TFn -> E Statement
function ix root f = do
  sym <- fnSymbol ix f.id
  ((params, res), ops) <- inFunction $ do
    params <- traverse (\(_, b) => (\r => val r (typeOf b) b.quantity) <$> fresh) f.params
    res <- plain' (para alg' f.body (\i => index i params) (Just f.result))
    pure (params, res)
  rt <- mlirType ix f.result
  args <- traverse (\((name, _), p) => (\o => MkArgument o (Named name f.loc)) <$> operand ix p)
                   (toList (zip f.params params))
  body <- epilogue ix f.loc rt res ops
  -- One cell for a lazy constant. Inlining the function that builds it
  -- would build a fresh cell at every use, and each force would run the
  -- body again.
  let shared = f.arity == 0 && lazyResult f.result
  let fn = Idr.funcOp {symVisibility = if f.id == root then Nothing else Just "private",
                       total' = f.facts.terminating,
                       breakLast = covers BreakLast f.loc.origin,
                       noInline = shared,
                       instance = Just (instanceAttr f.key)}
                      sym
                      (FunctionType (MkSignature (map (\a : Argument => a.value.type) args) [rt]))
                      (MkRegion args body)
  pure (MkStatement Nothing fn (Named (shown f.key.origin) f.loc))
  where
    lazyResult : Ty -> Bool
    lazyResult (LazyT _) = True
    lazyResult _ = False
    alg' : {0 nv : Nat} -> TermF (Sub Em) nv -> Em nv
    alg' = alg ix
    plain' : E (Maybe Val) -> E (Maybe Val)
    plain' = plain ix f.loc
