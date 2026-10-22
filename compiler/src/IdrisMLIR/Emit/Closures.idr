-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Closures and suspensions in symbol form: the body of a lambda or a delay
||| as a function of its own, which takes first the values the body uses
||| from outside it, its captures, which an `idr.closure` or an
||| `idr.suspend` of the function then holds. Its erased index parameters
||| are its owner's scope where it is written, so the index terms of its
||| captures' types keep their levels, and the closure passes that scope's
||| levels. It is named from its owner and its place among the owner's
||| lifted functions, in the order their bodies are finished, which the
||| fold fixes.
module IdrisMLIR.Emit.Closures

import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Spec.Functions.Termination
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.Monad.State
import Data.List
import Data.Maybe
import Data.SnocList
import Data.SortedMap
import Data.SortedSet

%default total

------------------------------------------------------------------------------
-- Captures
------------------------------------------------------------------------------

||| What a walk of a body has seen: the names defined so far, and the
||| values used before any definition, in the order first used. SSA names
||| are unique within a function, so one set of what is defined serves every
||| region: a name defined in one region is never used in a sibling.
record Seen where
  constructor MkSeen
  defined : SortedSet String
  captured : SortedSet String
  order : SnocList Value

seen : Seen -> Occurrence -> Seen
seen st (Uses v) =
  if contains v.name st.defined || contains v.name st.captured then st
  else { captured $= insert v.name, order $= (:< v) } st
seen st (Binds v) = { defined $= insert v.name } st
seen st (Defines _ names) = { defined $= \d => foldl (flip insert) d names } st

||| The values a body uses that it does not define, its own arguments
||| among what it defines: an op's operands before what its regions hold,
||| statements in order, each value once, at its first use.
captures : Region -> List Value
captures r = (walkRegion seen (MkSeen empty empty [<]) r).order <>> []

------------------------------------------------------------------------------
-- The function
------------------------------------------------------------------------------

||| An `idr.func`: its symbol, its telescope (the sorts of its erased index
||| parameters), its type, its body, and what Idris proved of its loops,
||| written as the Idris component every loop through it stays in exactly
||| when Idris's checker proved that component's calls decrease, and absent
||| otherwise. Its row is the derivation's, written later from its ops.
export
functionOp : String -> List (SortOf MlirType MlirAttr) -> MlirType -> Region -> Term.Termination -> Op
functionOp sym telescope type body termination =
  Idr.funcOp {binders = Just (IdrHand (BindersOf telescope)), terminates = proof termination} sym type body
  where
    proof : Term.Termination -> Maybe MlirAttr
    proof (Terminates c) = Just (IdrHand (TerminatesOf (ProvedIn c.index)))
    proof Acyclic = Just (IdrHand (TerminatesOf MadeAcyclic))
    proof (MayDiverge _) = Nothing

||| What a lifted function's body was in its owner, which its symbol says.
public export
data Lifted = LiftedLambda | LiftedDelay

||| A lifted kind as its symbol spells it.
liftedText : Lifted -> String
liftedText LiftedLambda = "lam"
liftedText LiftedDelay = "delay"

||| The function a lambda's or a delay's body becomes, among its owner's,
||| and its symbol and captures. `telescope` is the sorts of the scope's
||| erased binders where the body is written, which become the function's
||| index parameters; `params` are the arguments the body binds itself (a
||| lambda's parameter, none for a delay), `body` its statements to its
||| end, `results` its result types, `l` where it is written. Its arguments
||| are its captures, at their types and at `l`, then `params`. What Idris
||| proved of its loops is its owner's.
export
lift : Loc -> (kind : Lifted) -> (telescope : List (SortOf MlirType MlirAttr)) -> List Argument
    -> List Statement -> List MlirType -> E (String, List Value)
lift l kind telescope params body results = do
  let caps = captures (MkRegion params body)
  names <- traverse (const fresh) caps
  let args = zipWith (\c, n => MkArgument (MkValue n c.type) (At l)) caps names ++ params
      outside = \n => fromMaybe n (lookup n (the (SortedMap String String) (fromList (zip (map (.name) caps) names))))
      region = renameRegion outside (MkRegion args body)
      type = FunctionType (MkSignature (map (.value.type) args) results)
  st <- get
  let sym = st.ownerSymbol ++ "." ++ liftedText kind ++ show st.liftedCount
  put ({ liftedCount $= S,
         lifted $= (:< (sym, MkStatement Nothing (functionOp sym telescope type region st.termination)
                                         (Named st.definition l))) } st)
  pure (sym, caps)
