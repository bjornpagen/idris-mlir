-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Closures and suspensions in symbol form: the body of a lambda or a delay
||| as a function of its own, which takes first the values the body uses
||| from outside it, its captures, which an `idr.closure` or an
||| `idr.suspend` of the function then holds. The function is named from its
||| owner and its content, so that no counter and no place in the owner
||| reaches its name, and two bodies of one owner that are one function are
||| written once.
module IdrisMLIR.Emit.Closures

import IdrisMLIR.Dialect.Idr as Idr
import IdrisMLIR.Emit.Monad
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR

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
-- Names
------------------------------------------------------------------------------

||| The names of a function's values in the order they are defined: its
||| arguments, then each statement's results before what its regions bind,
||| `%0` on. A statement of several results is one name, `#i` its results.
record Numbering where
  constructor MkNumbering
  next : Nat
  names : SortedMap String String

numbered : Numbering -> Occurrence -> Numbering
numbered st (Uses _) = st
numbered st (Binds v) = { next $= S, names $= insert v.name ("%" ++ show st.next) } st
numbered st (Defines name results) =
  let fresh = "%" ++ show st.next
      ofResults = case results of
        [_] => []
        rs => zipWith (\i, old => (old, fresh ++ "#" ++ show i)) [0 .. length rs] rs
  in MkNumbering (S st.next) (foldl (\m, (old, new) => insert old new m) (insert name fresh st.names) ofResults)

renamedBy : SortedMap String String -> String -> String
renamedBy m n = fromMaybe n (lookup n m)

||| A function's one region with its values named in definition order, so
||| that its text is its content, wherever it was written from.
renumbered : Region -> Region
renumbered r = renameRegion (renamedBy (walkRegion numbered (MkNumbering 0 empty) r).names) r

------------------------------------------------------------------------------
-- The function
------------------------------------------------------------------------------

||| The function of a body, private and total: it has no loop of its own,
||| since a recursion goes through a function of the program, which carries
||| its own proof or its absence.
functionOp : String -> MlirType -> Region -> Op
functionOp sym type body = Idr.funcOp {symVisibility = Just "private", total' = True} sym type body

||| The function a lambda's or a delay's body becomes, among its owner's,
||| and its symbol and captures. `params` are the arguments the body binds
||| itself (a lambda's parameter, none for a delay), `body` its statements
||| to its end, `results` its result types, `l` where it is written. Its
||| arguments are its captures, at their types and at `l`, then `params`.
||| Its symbol is the owner's with `kind` and the hash of the function's
||| text without its name and locations; a symbol written already with that
||| text is the same function, and with another text an internal error.
export covering
lift : Loc -> (kind : String) -> List Argument -> List Statement -> List MlirType
    -> E (String, List Value)
lift l kind params body results = do
  let caps = captures (MkRegion params body)
  names <- traverse (const fresh) caps
  let args = zipWith (\c, n => MkArgument (MkValue n c.type) (At l)) caps names ++ params
      outside = renamedBy (fromList (zip (map (.name) caps) names))
      region = renumbered (renameRegion outside (MkRegion args body))
      type = FunctionType (MkSignature (map (.value.type) args) results)
      key = genericForm (functionOp "" type region)
  st <- get
  let sym = contentName st.owner kind key
  case lookup sym st.keys of
    Just known =>
      if known == key then pure (sym, caps)
      else internal ("two functions of " ++ st.owner ++ " are named " ++ sym)
    Nothing => do
      put ({ keys $= insert sym key,
             lifted $= (:< MkStatement Nothing (functionOp sym type region) (Named st.definition l)) } st)
      pure (sym, caps)
