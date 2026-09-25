||| Deliberate runtime erasure: drop quantity-0 parameters and the matching
||| call arguments, then check that nothing compile-time-only reaches runtime.
module IdrisMLIR.Erase

import IdrisMLIR.IR

import Data.List
import Data.SortedMap

%default covering

Masks : Type
Masks = SortedMap String (List Bool)

runtimeMask : Fn -> List Bool
runtimeMask fn = map (\p => p.quantity /= Q0) fn.params

eraseExpr : Masks -> (erased : List Nat) -> Expr -> Either String Expr
eraseExpr _ erased (Var v) =
  if v `elem` erased
     then Left ("erased variable %" ++ show v ++ " is used at runtime")
     else Right (Var v)
eraseExpr _ _ (Lit t n) = Right (Lit t n)
eraseExpr masks erased (Prim op t a b) =
  Prim op t <$> eraseExpr masks erased a <*> eraseExpr masks erased b
eraseExpr masks erased (Cast from to e) = Cast from to <$> eraseExpr masks erased e
eraseExpr masks erased (Call fn args) = do
  let Just mask = lookup fn masks
    | Nothing => Left ("call to unknown function " ++ fn)
  let True = length mask == length args
    | False => Left ("call to " ++ fn ++ " is not saturated")
  Call fn <$> traverse (eraseExpr masks erased) (map fst (filter snd (zip args mask)))
eraseExpr masks erased (Let v Irrelevant _ body) = eraseExpr masks (v :: erased) body
eraseExpr masks erased (Let v t e body) =
  Let v t <$> eraseExpr masks erased e <*> eraseExpr masks erased body
eraseExpr masks erased (Switch t e alts def) =
  Switch t <$> eraseExpr masks erased e
           <*> traverse (\(n, rhs) => (n,) <$> eraseExpr masks erased rhs) alts
           <*> eraseExpr masks erased def
eraseExpr _ _ CompileTime = Left "a compile-time-only value is used at runtime"

eraseFn : Masks -> Fn -> Either String Fn
eraseFn masks fn = do
  let (erased, kept) = partition (\p => p.quantity == Q0) fn.params
  for_ kept $ \p => case p.type of
    Irrelevant => Left (fn.name ++ ": runtime parameter %" ++ show p.var ++ " has no runtime type")
    IntT _ => Right ()
  body <- eraseExpr masks (map (.var) erased) fn.body
  pure ({ params := kept, body := body } fn)

export
erase : Program -> Either String Program
erase prog = do
  let masks = fromList [(fn.name, runtimeMask fn) | fn <- prog.functions]
  fns <- traverse (eraseFn masks) prog.functions
  pure ({ functions := fns } prog)
