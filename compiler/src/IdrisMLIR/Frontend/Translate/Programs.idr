-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Function instances and programs: each instance requested is translated
||| in turn, and the program is assembled from what they registered.
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
import IdrisMLIR.Frontend.Translate.Shapes
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Terms
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Syntax.Idr
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
  tree' <- tree (MkCtx owner fc complete) env (telescope (length args) (type def))
                (emptyKnown (length env)) treeCT
  loc <- toLoc fc
  -- Each array parameter's dimensions that a size variable fixes, stated
  -- equal to the parameter or the runtime size that fixes it first; an
  -- instance with no array parameter has none to state.
  ties <- if any (isJust . (>>= valueDims) . map typeOf . runtimeBinder) kinds
            then do
              (sized, _) <- sizedTelescope (length args) (type def) kinds
              entryWitnesses kinds sized
            else pure []
  let body = tied loc ties tree'
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

    -- The body under one `let` per parameter with a tied dimension, in
    -- parameter order: the parameter as its dimensions are stated, which
    -- the body uses in its place.
    tied : {n : Nat} -> Loc -> List (Nat, List (Maybe Witness)) -> Term n -> Term n
    tied loc [] body = body
    tied loc ((r, ws) :: rest) body = case natToFin r n of
      Nothing => tied loc rest body
      Just p =>
        let params = map (\i => fromMaybe p (natToFin i n)) [0 .. minus n 1]
            dims = map (\w => w >>= witnessTerm loc params) ws
            inner = tied loc rest body
        in Let loc (shown "tied") Many (Tie loc (Var loc p) dims)
               (rename (\x => if x == p then FZ else FS x) inner)

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
    environment n i (FormParam f :: ks) = TypeValue f :: environment n i ks
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

||| The program: its data and function instances in the order they were
||| registered. Whether a value of a data instance is boxed is the
||| dialect's to decide, from the whole type graph, once.
assemble : {auto s : Ref TState TS} -> FnId -> Core Source
assemble root = do
  st <- get TState
  let datas = mapMaybe (\n => lookup n st.datas) (st.dataOrder <>> [])
  let fns = mapMaybe (\n => lookup n st.fns) (st.fnOrder <>> [])
  pure (MkSource datas fns root)

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
  -- The root is code of no module, at the generated location: the world is
  -- its parameter, and main's value its action. A binder is known by its
  -- name over its own span, and this one has none, so it is no Idris
  -- binder's whatever it is called.
  let loc = noLoc
  let body : Term 1
      body = App loc (Call loc inst Nothing []) (Var loc FZ)
  let rootId = MkFnId "$idris-mlir.root"
  src <- assemble rootId
  -- The root is the `ProgramRoot` hook's code, `unsafePerformIO main`: its
  -- facts are the registry's. It has no loop of its own; what main does is
  -- main's, which the passes find through the call.
  let facts = MkFacts True
  let root = MkTFn rootId (MkInstanceKey rootId.name [] Whole) 1 [(shown "world", MkBinder (quantityOf linear) WorldT)]
                   res body loc facts
  pure (Just ({ fns $= (++ [root]) } src))
