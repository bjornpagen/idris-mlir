-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Function instances and programs: each instance requested is translated
||| in turn, and the program is assembled with each data instance's
||| representation.
module IdrisMLIR.Frontend.Translate.Programs

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Facts
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Cases
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Forced
import IdrisMLIR.Frontend.Translate.Instances
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Terms
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Graph
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Rule
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Fin
import Data.List
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.Vect

%default covering

||| Translates one function instance. Its runtime parameters are its Core
||| parameters, numbered in order; a type, an implementation and a parameter
||| of quantity 0 are compile-time values of the case tree's scope, which has
||| one variable per parameter of the definition's type.
translateInstance : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Pending -> Core ()
translateInstance p = do
  update TState { current := Just p.inst }
  def <- lookupDef EmptyFC (show p.name) p.name
  let owner = show (fullname def)
  -- A definition the checks refused is left out, and so is what only it
  -- reaches.
  False <- pure (contains (nameKey (fullname def)) (!(get TState)).refused)
    | True => pure ()
  let fc = location def
  PMDef _ args treeCT _ _ <- pure (definition def)
    | _ => reject fc owner DefinitionShape "not a pattern-matching definition"
  -- A missing case crashes.
  let complete = case isCovering (totality def) of
                   MissingCases _ => False
                   _ => True
  (kinds, resTy) <- classify fc owner (length args) (type def) (givenArgs p.kinds)
  result <- coreType fc owner ValueType !(normaliseClosed resTy)
  let params = runtimeParams (parameterNames (type def)) kinds
  let env = environment (length params) 0 kinds
  when (length env /= length kinds) $
    internal fc "the runtime parameters of an instance numbered out of order"
  body <- tree (MkCtx owner fc complete) env (telescope (length args) (type def))
               (emptyKnown (length env)) treeCT
  loc <- toLoc fc
  -- Every loop through the definition terminates: its component was
  -- checked when the instance was requested (`Recursion`).
  let tot = fromMaybe False (lookup (nameKey (fullname def)) (!(get TState)).loops)
  let facts = MkFacts tot
  update TState { fns $= insert p.inst (MkTFn p.inst p.key (length params) (fromList params) result body loc facts)
                , fnOrder $= (:< p.inst) }
  where
    -- The names the definition's type gives its parameters.
    parameterNames : TT vs -> List Name
    parameterNames (Bind _ x (Pi {}) sc) = x :: parameterNames sc
    parameterNames _ = []

    runtimeParams : List Name -> List PKind -> List (Shown, Binder)
    runtimeParams (x :: xs) (k :: ks) = case runtimeBinder k of
      Just b => (binderName x, b) :: runtimeParams xs ks
      Nothing => runtimeParams xs ks
    runtimeParams [] ks = map (\b => (shown "x", b)) (mapMaybe runtimeBinder ks)
    runtimeParams _ [] = []

    -- What each variable of the case tree's scope stands for: a runtime
    -- parameter is the next Core parameter.
    environment : (n : Nat) -> Nat -> List PKind -> List (VarInfo (Fin n))
    environment n i [] = []
    environment n i (TypeParam t :: ks) = TypeValue t :: environment n i ks
    environment n i (DictParam t Nothing :: ks) = Static t Nothing :: environment n i ks
    environment n i (ErasedParam :: ks) = TypeValue (Erased EmptyFC Placeholder) :: environment n i ks
    environment n i (DictParam t (Just h) :: ks) = case natToFin i n of
      Just x => Static t (Just (x, h)) :: environment n (S i) ks
      Nothing => []
    environment n i (ValueParam b shape known :: ks) = case natToFin i n of
      Just x => maybe (Runtime x (Just (typeOf b)) (Just known)) (shaped x (typeOf b) known) shape
                  :: environment n (S i) ks
      Nothing => []

||| Translates every instance requested, until none is left. A rejected
||| instance is recorded and leaves the state as it was before it, the
||| instances it requested included, but for the rejections and what they
||| refused, and what it found of definitions: what it would have reached
||| is reported once it is fixed, and every rejection the translation
||| reports is independent. A pass that a construction site voids
||| (`Dictionaries`) still goes on to the end: an assumption it made only
||| left alternatives out, so all it translates is in the program, and
||| every construction site it finds is one the next pass starts from, not
||| only the first.
drain : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Core ()
drain = do
  st <- get TState
  case dequeue st.queue of
    Nothing => pure ()
    Just (p, rest) => do
      let before = { queue := rest } st
      put TState before
      Nothing <- noting (translateInstance p)
        | Just () => drain
      after <- get TState
      put TState ({ rejected := after.rejected, refused := after.refused, places := after.places
                  , tyCons := after.tyCons, loops := after.loops, blockNames := after.blockNames } before)
      drain

||| The program's instances from its root, in as many passes as the
||| dictionary fields matched before they were built need: each pass starts
||| from the dictionaries the last one found.
translateFrom : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> FC -> Name -> Core (Maybe FnId)
translateFrom fc main = do
  update TState nextPass
  Just inst <- noting (request fc (show main) main [])
    | Nothing => pure Nothing
  drain
  st <- get TState
  if st.restart then translateFrom fc main else pure (Just inst)

||| The program, with each data instance's representation: a box when it
||| contains itself, through the fields of any data (not through closures,
||| which are values of their own), and an unboxed sum otherwise. A record
||| decided Sop here may still become a box in idr-defunctionalize, when a
||| cell holding its values would count more references than a header can:
||| that measure is idr.layout's, not one held here too.
assemble : {auto s : Ref TState TS} -> FnId -> Core Source
assemble root = do
  st <- get TState
  let decls = the (List Decl) (mapMaybe (\n => lookup n st.datas) (st.dataOrder <>> []))
  let contained = \d => maybe [] (\decl => concatMap (mapMaybe dataField . (.fields)) decl.cons)
                                 (lookup d st.datas)
  let boxes = cyclic contained (map (.id) decls)
  let datas = map (\d : Decl => MkData d.id d.key d.cons d.loc (if contains d.id boxes then Box else Sop)) decls
  let fns = mapMaybe (\n => lookup n st.fns) (st.fnOrder <>> [])
  pure (MkSource datas fns root)
  where
    dataField : Binder -> Maybe DataId
    dataField (MkBinder _ (DataT d)) = Just d
    dataField _ = Nothing

||| An IO program. The root is `unsafePerformIO main` written
||| directly as world-passing code, which is what `unsafePerformIO`,
||| `unsafeCreateWorld` and `unsafeDestroyWorld` mean:
|||   root w = main w
||| since an `IO` is its one field, the action on the world. It returns the
||| `IORes` of `main`'s result and the last world, so the world is used
||| exactly once. `%MkWorld` never appears. Nothing when an instance was
||| rejected (`rejections`).
export
translateIOProgram : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                     FC -> Name -> Core (Maybe Source)
translateIOProgram fc main = do
  Just inst <- translateFrom fc main
    | Nothing => pure Nothing
  st <- get TState
  let [<] = st.rejected
    | _ => pure Nothing
  let owner = show main
  let notIO = reject fc owner ProgramShape "main must have type IO ()"
  let Just mainFn = lookup inst st.fns
    | Nothing => internal fc "main was not translated"
  let FunT (MkBinder _ WorldT) res@(DataT _) = mainFn.result
    | _ => notIO
  loc <- toLoc (location !(lookupDef fc owner main))
  -- $world is the parameter; main's value is its action. The name is no
  -- Idris binder's: a binder is known by its name over its definition's
  -- span, and this synthetic one shares main's.
  let body : Term 1
      body = App loc (Call loc inst Nothing []) (Var loc FZ)
  let rootId = MkFnId "$idris-mlir.root"
  src <- assemble rootId
  -- The root is the `ProgramRoot` hook's code, `unsafePerformIO main`: its
  -- facts are the registry's. It has no loop of its own; what main does is
  -- main's, which the passes find through the call.
  let facts = MkFacts True
  let root = MkTFn rootId (MkInstanceKey rootId.name []) 1 [(shown "$world", MkBinder (quantityOf linear) WorldT)]
                   res body loc facts
  pure (Just ({ fns $= (++ [root]) } src))
