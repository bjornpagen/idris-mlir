-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Closures and suspensions in symbol form: the body of a lambda or a delay
||| as a function of its own, which takes first the values the body uses
||| from outside it, its captures, which an `idr.fn.closure` or an
||| `idr.lazy.suspend` of the function then holds. Its erased index parameters
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

||| What a walk of a body has seen: the values defined so far, and the
||| values used before any definition, in the order first used. A value's
||| identity is unique within a function, so one set of what is defined
||| serves every region: a value defined in one region is never used in a
||| sibling.
record Seen where
  constructor MkSeen
  defined : SortedSet ValueId
  captured : SortedSet ValueId
  order : SnocList Value

seen : Seen -> Occurrence -> Seen
seen st (Uses v) =
  if contains v.name st.defined || contains v.name st.captured then st
  else { captured $= insert v.name, order $= (:< v) } st
seen st (Binds v) = { defined $= insert v.name } st
seen st (Defines names) = { defined $= \d => foldl (flip insert) d names } st

||| The values a body uses that it does not define, its own arguments
||| among what it defines: an op's operands before what its regions hold,
||| statements in order, each value once, at its first use.
captures : Region -> List Value
captures r = (walkRegion seen (MkSeen empty empty [<]) r).order <>> []

------------------------------------------------------------------------------
-- The function
------------------------------------------------------------------------------

||| An `idr.func`: its symbol, its telescope (the sorts of its erased index
||| parameters), its extents (the entries naming the index term each `?`
||| of its type's tensors is, in order of side, position and axis), its
||| type, its body, and what Idris proved of its loops, `#idr.terminates`
||| exactly when Idris's checker proved that every call of it ends, and
||| absent otherwise. Its row is the derivation's, written later from its
||| ops.
export
functionOp : String -> List (SortOf MlirType MlirAttr) -> List MlirAttr -> MlirType -> Region -> Termination -> Op
functionOp sym telescope extents type body termination =
  Idr.funcOp {binders' = Just (Idr (IndexBindersAttr telescope)), extents' = Just (Idr (ExtentsAttr extents)),
              terminates' = terminates termination}
             (StringAttr sym) (TypeAttr type) body
  where
    terminates : Termination -> Maybe MlirAttr
    terminates Proved = Just (Idr TerminatesAttr)
    terminates Unproved = Nothing

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
||| proved of its loops is its owner's. Its signature is no Idris type's,
||| so it names no extent by a term.
export
lift : Loc -> (kind : Lifted) -> (telescope : List (SortOf MlirType MlirAttr)) -> List Argument
    -> List Statement -> List MlirType -> E (String, List Value)
lift l kind telescope params body results = do
  let caps = captures (MkRegion params body)
  names <- traverse (\_ => (\n => Bound n 0) <$> fresh) caps
  let args = zipWith (\c, n => MkArgument (MkValue n c.type) (At l)) caps names ++ params
      outside = \v => fromMaybe v (lookup v (the (SortedMap ValueId ValueId) (fromList (zip (map (.name) caps) names))))
      region = renameRegion outside (MkRegion args body)
      type = FunctionType (MkSignature (map (.value.type) args) results)
  st <- get
  let sym = st.ownerSymbol ++ "." ++ liftedText kind ++ show st.liftedCount
  put ({ liftedCount $= S,
         lifted $= (:< (sym, MkStatement Nothing (functionOp sym telescope [] type region st.termination)
                                         (Named st.definition l))) } st)
  pure (sym, caps)
