||| The module's declarations: data instances and functions, each with the
||| functions lifted from it.
module IdrisMLIR.Emit.Declarations

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
import Data.String
import Data.Vect

%default total

||| A declaration is located by its Idris name.
export
dataDecl : Index -> Data -> E Op
dataDecl ix d = do
  ctors <- traverse ctor d.cons
  pure (Nest ("idr.data " ++ symbol (mangle d.id.name) ++ (case d.repr of
                                                              Sop => ""
                                                              Box => " box") ++ " {")
             ctors "}" (Just (Named d.idrisName d.loc)))
  where
    ctor : Con -> E Op
    ctor c = do
      ts <- traverse (typeText ix . (.type)) c.fields
      qs <- traverse (\f => quantityOf f.type f.quantity) c.fields
      pure (Line ("idr.ctor " ++ symbol (mangle c.id.name) ++ " tag " ++ show c.tag ++
                  " (" ++ joinBy ", " ts ++ ") {quantities = [" ++ joinBy ", " (map (quoted . show) qs) ++ "]}")
                 (Named c.idrisName c.loc))

||| A function, and the functions lifted from it. Only the root is public.
export
function : Index -> FnId -> TFn -> E (List Op)
function ix root f = do
  let sym = mangle f.id.name
  modify { owner := MkOwner sym f.idrisName f.facts.terminating.holds, lifted := [<] }
  ((params, res), ops) <- inFunction $ do
    params <- traverse (\b => (\n => MkVal n b.type b.quantity) <$> fresh) f.params
    res <- para alg' f.body (\i => index i params) (Just f.result)
    pure (params, res)
  rt <- typeText ix f.result
  header <- traverse (param ix) (toList params)
  let visibility = if f.id == root then "" else "private "
  let fn = Nest ("func.func " ++ visibility ++ symbol sym ++ "(" ++ joinBy ", " header ++ ") -> " ++ rt ++
                 attributes f.facts.terminating.holds (contains (FnNode f.id) ix.breakers) ++ " {")
                (epilogue f.loc rt res ops) "}" (Just (Named f.idrisName f.loc))
  inner <- gets (.lifted)
  pure (fn :: (inner <>> []))
  where
    alg' : {0 b : Type} -> TermF (Sub Em) b -> Em b
    alg' = alg ix
