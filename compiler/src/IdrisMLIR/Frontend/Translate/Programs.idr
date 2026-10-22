-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Function instances and programs: each instance requested is translated
||| in turn, and the program is assembled from what they registered.
module IdrisMLIR.Frontend.Translate.Programs

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Finite
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Cases
import IdrisMLIR.Frontend.Translate.Choices
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Instances
import IdrisMLIR.Frontend.Translate.Shapes
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Terms
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Fin
import Data.List
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.Vect

%default total

||| The name of the next parameter, and the names after it: a parameter
||| past the names a type gives is `x`.
parameterName : List Name -> (Shown, List Name)
parameterName [] = (shown "x", [])
parameterName (x :: xs) = (binderName x, xs)

||| An instance's runtime parameters, named as the type it is classified
||| over names them, and what each variable of its body's scope stands for,
||| one per parameter: a type, an implementation or a parameter of
||| quantity 0 a compile-time value, an index parameter its level (the next
||| one `level`), which its body's types read, and a runtime parameter the
||| next Core parameter.
runtimeParams : (level : Nat) -> List Name -> (kinds : List PKind) ->
                (Vect (Runtimes kinds) (Shown, Binder), List (VarInfo (Fin (Runtimes kinds))))
runtimeParams level xs [] = ([], [])
runtimeParams level xs (TypeParam t :: ks) =
  let (ps, env) = runtimeParams level (snd (parameterName xs)) ks in (ps, TypeValue t :: env)
runtimeParams level xs (DictParam t Nothing :: ks) =
  let (ps, env) = runtimeParams level (snd (parameterName xs)) ks in (ps, Static t Nothing :: env)
runtimeParams level xs (ErasedParam :: ks) =
  let (ps, env) = runtimeParams level (snd (parameterName xs)) ks in (ps, TypeValue (Erased EmptyFC Placeholder) :: env)
runtimeParams level xs (IndexParam _ :: ks) =
  let (ps, env) = runtimeParams (S level) (snd (parameterName xs)) ks in (ps, TypeValue (marker level) :: env)
runtimeParams level xs (FormParam f :: ks) =
  let (ps, env) = runtimeParams level (snd (parameterName xs)) ks in (ps, TypeValue f :: env)
runtimeParams level xs (DictParam t (Just h) :: ks) =
  let (x, xs') = parameterName xs
      (ps, env) = runtimeParams level xs' ks in
  ((x, h.binder) :: ps, Static t (Just (FZ, h)) :: map (map FS) env)
runtimeParams level xs (ChoiceParam b known :: ks) =
  let (x, xs') = parameterName xs
      (ps, env) = runtimeParams level xs' ks in
  ((x, b) :: ps, Runtime FZ (Just b.type) (Just known) :: map (map FS) env)
runtimeParams level xs (ValueParam b shape known :: ks) =
  let (x, xs') = parameterName xs
      (ps, env) = runtimeParams level xs' ks in
  ((x, b) :: ps, maybe (Runtime FZ (Just b.type) (Just known)) (shaped FZ b.type known) shape
                   :: map (map FS) env)

||| The names a type gives its parameters.
parameterNames : TT vs -> List Name
parameterNames (Bind _ x (Pi {}) sc) = x :: parameterNames sc
parameterNames _ = []

||| Every variable of a scope, the first first, as a term of it.
variablesOf : (vs : Scope) -> List (TT vs)
variablesOf [] = []
variablesOf (v :: vs) = Local EmptyFC Nothing 0 First :: map weaken (variablesOf vs)

||| Translates an instance of a definition. Its runtime parameters are its
||| Core parameters, numbered in order; a type, an implementation and a
||| parameter of quantity 0 are compile-time values of the case tree's
||| scope, which has one variable per parameter of the definition's type.
translateDefinition : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Request -> Name -> Front ()
translateDefinition p n = do
  d <- lookupDef EmptyFC (show n) n
  let def = d.def
  let owner = show (fullname def)
  let address = addressOf d.placement
  -- A definition the checks refused is left out, and so is what only it
  -- reaches.
  before <- getState
  False <- pure (contains address before.refused)
    | True => pure ()
  Nothing <- heldChoice p.kinds
    | Just (at, j, ty) => heldDispatch p at j ty
  let fc = location def
  Just m <- pure d.matched
    | Nothing => reject fc owner DefinitionShape "not a pattern-matching definition"
  let ty = d.type
  -- A missing case crashes.
  let complete = case isCovering (totality def) of
                   MissingCases _ => False
                   _ => True
  (kinds, resTy) <- classifyInstance fc owner (length m.args) ty (givenArgs p.kinds)
  resTy' <- normaliseClosed resTy
  result <- coreType fc owner ValueType resTy'
  (params, env) <- pure (runtimeParams 0 (parameterNames ty) kinds)
  tree' <- tree (MkCtx owner fc complete resTy') env (clauses m.args m.pats) m.tree
  loc <- toLoc fc
  -- Each array parameter's dimensions that a size variable fixes, stated
  -- equal to the parameter or the runtime size that fixes it first; an
  -- instance with no array parameter has none to state.
  ties <- if any (isJust . valueDims . (.type)) (runtimeBinders kinds)
            then (entryTies . fst) <$> sizedTelescope (length m.args) ty kinds
            else pure []
  let body = tied loc (allFins (Runtimes kinds)) ties tree'
  -- What Idris proved of its loops: its component was checked when the
  -- instance was requested (`Recursion`).
  after <- getState
  let Just termination = lookup address after.loops
    | Nothing => internal fc (owner ++ " was requested before its component was checked")
  updateState { fns $= insert p.inst (MkTFn p.inst (keyText p.key) p.key (telescopeOf kinds) (Runtimes kinds) params
                                              result body loc termination) }
  where
    -- The body under one `let` per parameter with a tied dimension, in
    -- parameter order: the parameter as its dimensions are stated, which
    -- the body uses in its place. The parameters are the body's
    -- variables, parameter `i` being `i`.
    tied : Loc -> Vect r (Fin n) -> List (Fin r, List (Nat, Witness r)) -> Term n -> Term n
    tied loc vs [] body = body
    tied loc vs ((x, axes) :: rest) body =
      let p = Data.Vect.index x vs in
      Let loc (shown "tied") (OfValue Many) (Tie loc (Var loc p) (map (\(k, w) => (k, witnessTerm loc vs w)) axes))
          (rename (\y => if y == p then FZ else FS y) (tied loc vs rest body))

||| Translates a member at a use's types (`AtUse uses`): its body is its
||| form, its second parameter, applied to the use's arguments, its
||| parameters after it, as the form is applied wherever a scope binds it
||| (`Terms.implementationAt`), on a path of its own, at the type the use
||| gives. Its parameters are classified over `Instances.applicationType`,
||| the form's type keying it first. It has no loop of its own: what its
||| form calls is the callee's.
translateApplication : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Request -> Nat -> Front ()
translateApplication p uses = do
  let owner = show p.owner
  let fc = p.site
  ty <- applicationType
  (kinds, resTy) <- classifyInstance fc owner (2 + uses) ty (givenArgs p.kinds)
  resTy' <- normaliseClosed resTy
  result <- coreType fc owner ValueType resTy'
  let names = parameterNames ty ++ replicate uses (UN (Basic (known Kx)))
  (params, env) <- pure (runtimeParams 0 names kinds)
  let (_ :: form :: arguments) = variablesOf names
    | _ => internal fc "a member at a use with no form to apply"
  body <- atType asWritten start (sizeAccessible start) (MkCtx owner fc True resTy') env resTy'
                 (foldl (App fc) form arguments)
  loc <- toLoc fc
  updateState { fns $= insert p.inst (MkTFn p.inst (keyText p.key) p.key (telescopeOf kinds) (Runtimes kinds) params
                                              result body loc Acyclic) }

||| Translates one function instance, of a definition or of a member at a
||| use. An instance given an implementation that holds a choice the
||| running program made is a dispatch on that choice
||| (`Choices.heldDispatch`), each of its arms the instance with the choice
||| fixed, so no tree takes apart a field the program does not fix.
translateInstance : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Request -> Front ()
translateInstance p = case p.instantiates of
  OfDefinition n => translateDefinition p n
  AtUse uses => do
    Nothing <- heldChoice p.kinds
      | Just (at, j, ty) => heldDispatch p at j ty
    translateApplication p uses

||| The families a family's fields name.
named : Family -> List FamilyId
named f = concatMap (\(_ ** c) => concatMap (families . (.type)) (toList c.fields)) f.cons
  where
    families : Ty -> List FamilyId
    families (DataT g _) = [g]
    families (FunT (MkBinder _ a) r) = families a ++ families r
    families (LazyT a) = families a
    families (TensorT _ a) = families a
    families (MemRefT _ a) = families a
    families _ = []

||| The families of a program as groups, each a strongly connected
||| component of the graph of families whose fields name each other, in an
||| order where a group names only itself and earlier ones. What each
||| family reaches is found by extending, once per family, what it reaches
||| by the families its fields name: a path of more steps than there are
||| families repeats one, so that many rounds reach everything. Two
||| families are of one group when each reaches the other; a group that
||| reaches another reaches more than it, so groups ordered by how many
||| families they reach, then by when they were registered, name only
||| earlier ones.
groupsOf : List Family -> List FamilyGroup
groupsOf fs =
  let edges = the (SortedMap FamilyId (List FamilyId)) (fromList (map (\f => (f.id, named f)) fs))
      start = the (SortedMap FamilyId (SortedSet FamilyId))
                  (fromList (map (\f => (f.id, fromList (fromMaybe [] (lookup f.id edges)))) fs))
      reach = rounds (length fs) edges start
      reaches = \a, b => maybe False (contains b) (lookup a reach)
      together = \a, b => a == b || (reaches a b && reaches b a)
      grouped = foldl (\gs, f => if any (\g => together (head g).id f.id) gs then gs else gs ++ [f ::: []]) [] fs
      filled = map (\g => case filter (\f => together (head g).id f.id) fs of
                             (x :: xs) => x ::: xs
                             [] => g) grouped
      size = \g => maybe 0 (length . SortedSet.toList) (lookup (head g).id reach)
  in sortBy (\a, b => compare (size a) (size b)) filled
  where
    step : SortedMap FamilyId (List FamilyId) -> SortedMap FamilyId (SortedSet FamilyId)
        -> SortedMap FamilyId (SortedSet FamilyId)
    step edges r = map (\set => foldl (\acc, g => union acc (fromMaybe empty (lookup g r))) set (SortedSet.toList set)) r
    rounds : Nat -> SortedMap FamilyId (List FamilyId) -> SortedMap FamilyId (SortedSet FamilyId)
          -> SortedMap FamilyId (SortedSet FamilyId)
    rounds Z edges r = r
    rounds (S k) edges r = rounds k edges (step edges r)

||| The program: its families as groups, and its function instances in the
||| order they were requested. How a family's values are laid out is the
||| dialect's to decide, from each type, once.
assemble : {auto s : Ref TState TS} -> TFn -> Front Source
assemble root = do
  st <- getState
  let fams = mapMaybe (\f => familyOf f st) (st.familyOrder <>> [])
  let fns = mapMaybe (\n => lookup n st.fns) (st.fnOrder <>> [])
  pure (MkSource (groupsOf fams) root fns)

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
                     FC -> Name -> Front (Maybe Source)
translateIOProgram fc main = do
  Just inst <- core (translateFrom (noting (request fc (show main) (OfDefinition main) [])) translateInstance)
    | Nothing => pure Nothing
  let [<] = (!(getState)).rejected
    | _ => pure Nothing
  -- Every member of every choice is known once the translation has ended:
  -- each dispatch on one is written now.
  dispatchers
  st <- getState
  let owner = show main
  let notIO = reject fc owner ProgramShape "main must have type IO ()"
  let Just mainFn = lookup inst st.fns
    | Nothing => internal fc "main was not translated"
  let FunT (MkBinder _ WorldT) res@(DataT _ _) = mainFn.result
    | _ => notIO
  -- The root is code of no module, at the generated location: the world is
  -- its parameter, and main's value its action. A binder is known by its
  -- name over its own span, and this one has none, so it is no Idris
  -- binder's whatever it is called.
  let loc = noLoc
  let body : Term 1
      body = App loc (Call loc inst Nothing [] []) (Var loc FZ)
  -- The root is the one function of no definition, so no instance is it;
  -- its symbol is its key printed, as every symbol is.
  let rootId = RootFn
  let rootKey = MkInstanceKey "$idris-mlir.root" NoArguments Whole
  -- The root is the `ProgramRoot` hook's code, `unsafePerformIO main`. It
  -- has no loop of its own; what main does is main's, which the passes find
  -- through the call.
  let root = MkTFn rootId (keyText rootKey) rootKey [] 1 [(shown "world", MkBinder Once WorldT)]
                   res body loc Acyclic
  Just <$> assemble root
