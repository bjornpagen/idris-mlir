-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Function instances and programs: each instance requested is translated
||| in turn, and the program is assembled from what they registered.
module IdrisMLIR.Frontend.Translate.Programs

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Facts
import IdrisMLIR.Frontend.Finite
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
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Syntax.Idr
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Fin
import Data.List
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.Vect

%default total

||| Translates one function instance. Its runtime parameters are its Core
||| parameters, numbered in order; a type, an implementation and a parameter
||| of quantity 0 are compile-time values of the case tree's scope, which has
||| one variable per parameter of the definition's type.
translateInstance : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Request -> Core ()
translateInstance p = do
  def <- lookupDef EmptyFC (show p.name) p.name
  let owner = show (fullname def)
  -- A definition is its address, which a name the context does not hold
  -- has not: no check refused it, and no loop through it is known.
  let address = definitionAddress (gamma !(get Ctxt)) (fullname def)
  -- A definition the checks refused is left out, and so is what only it
  -- reaches.
  before <- get TState
  False <- pure (maybe False (\a => contains a before.refused) address)
    | True => pure ()
  let fc = location def
  PMDef _ args treeCT _ pats <- pure (definition def)
    | _ => reject fc owner DefinitionShape "not a pattern-matching definition"
  -- A missing case crashes.
  let complete = case isCovering (totality def) of
                   MissingCases _ => False
                   _ => True
  (kinds, resTy) <- classify fc owner (length args) (type def) (givenArgs p.kinds)
  result <- coreType fc owner ValueType !(normaliseClosed resTy)
  (params, env) <- pure (runtimeParams (parameterNames (type def)) kinds)
  tree' <- tree (MkCtx owner fc complete) env !(clauses args (type def) pats) treeCT
  loc <- toLoc fc
  -- Each array parameter's dimensions that a size variable fixes, stated
  -- equal to the parameter or the runtime size that fixes it first; an
  -- instance with no array parameter has none to state.
  ties <- if any (isJust . valueDims . typeOf) (runtimeBinders kinds)
            then (entryTies . fst) <$> sizedTelescope (length args) (type def) kinds
            else pure []
  let body = tied loc (allFins (Runtimes kinds)) ties tree'
  -- Every loop through the definition terminates: its component was
  -- checked when the instance was requested (`Recursion`).
  after <- get TState
  let tot = fromMaybe False (address >>= \a => lookup a after.loops)
  let facts = MkFacts tot
  update TState { fns $= insert p.inst (MkTFn p.inst p.key (Runtimes kinds) params result body loc facts) }
  where
    -- The names the definition's type gives its parameters.
    parameterNames : TT vs -> List Name
    parameterNames (Bind _ x (Pi {}) sc) = x :: parameterNames sc
    parameterNames _ = []

    -- The body under one `let` per parameter with a tied dimension, in
    -- parameter order: the parameter as its dimensions are stated, which
    -- the body uses in its place. The parameters are the body's
    -- variables, parameter `i` being `i`.
    tied : Loc -> Vect r (Fin n) -> List (Fin r, List (Nat, Witness r)) -> Term n -> Term n
    tied loc vs [] body = body
    tied loc vs ((x, axes) :: rest) body =
      let p = Data.Vect.index x vs in
      Let loc (shown "tied") Many (Tie loc (Var loc p) (map (\(k, w) => (k, witnessTerm loc vs w)) axes))
          (rename (\y => if y == p then FZ else FS y) (tied loc vs rest body))

    -- A parameter past the names the definition's type gives is `x`.
    named : List Name -> (Shown, List Name)
    named [] = (shown "x", [])
    named (x :: xs) = (binderName x, xs)

    -- The instance's runtime parameters, named as the definition's type
    -- names them, and what each variable of the case tree's scope stands
    -- for, one per parameter: a type, an implementation or a parameter of
    -- quantity 0 a compile-time value, and a runtime parameter the next
    -- Core parameter.
    runtimeParams : List Name -> (kinds : List PKind) ->
                    (Vect (Runtimes kinds) (Shown, Binder), List (VarInfo (Fin (Runtimes kinds))))
    runtimeParams xs [] = ([], [])
    runtimeParams xs (TypeParam t :: ks) = let (ps, env) = runtimeParams (snd (named xs)) ks in (ps, TypeValue t :: env)
    runtimeParams xs (DictParam t Nothing :: ks) = let (ps, env) = runtimeParams (snd (named xs)) ks in (ps, Static t Nothing :: env)
    runtimeParams xs (ErasedParam :: ks) =
      let (ps, env) = runtimeParams (snd (named xs)) ks in (ps, TypeValue (Erased EmptyFC Placeholder) :: env)
    runtimeParams xs (FormParam f :: ks) = let (ps, env) = runtimeParams (snd (named xs)) ks in (ps, TypeValue f :: env)
    runtimeParams xs (DictParam t (Just h) :: ks) =
      let (x, xs') = named xs
          (ps, env) = runtimeParams xs' ks in
      ((x, h.binder) :: ps, Static t (Just (FZ, h)) :: map (map FS) env)
    runtimeParams xs (ValueParam b shape known :: ks) =
      let (x, xs') = named xs
          (ps, env) = runtimeParams xs' ks in
      ((x, b) :: ps, maybe (Runtime FZ (Just (typeOf b)) (Just known)) (shaped FZ (typeOf b) known) shape
                       :: map (map FS) env)

||| The program: its data and function instances in the order they were
||| registered. Whether a value of a data instance is boxed is the
||| dialect's to decide, from the whole type graph, once.
assemble : {auto s : Ref TState TS} -> TFn -> Core Source
assemble root = do
  st <- get TState
  let datas = mapMaybe (\n => declared n st) (st.dataOrder <>> [])
  let fns = mapMaybe (\n => lookup n st.fns) (st.fnOrder <>> [])
  pure (MkSource datas root fns)

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
  Just inst <- translateFrom (noting (request fc (show main) main [])) translateInstance
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
  -- The root is the `ProgramRoot` hook's code, `unsafePerformIO main`: its
  -- facts are the registry's. It has no loop of its own; what main does is
  -- main's, which the passes find through the call.
  let facts = MkFacts True
  let root = MkTFn rootId (MkInstanceKey rootId.name NoArguments Whole) 1 [(shown "world", MkBinder One WorldT)]
                   res body loc facts
  Just <$> assemble root
