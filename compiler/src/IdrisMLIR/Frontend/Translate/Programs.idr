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
import IdrisMLIR.Frontend.Translate.TypeConstructors
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
import Decidable.Equality

%default total

||| The name of the next parameter, and the names after it: a parameter
||| past the names a type gives is `x`.
parameterName : List Name -> (Shown, List Name)
parameterName [] = (shown "x", [])
parameterName (x :: xs) = (binderName x, xs)

||| An instance's runtime parameters' names, as the type it is classified
||| over names them, and what each variable of its body's scope stands for,
||| one per parameter: a type, an implementation or a parameter of
||| quantity 0 a compile-time value, an index parameter its level (the next
||| one `level`), which its body's types read, and a runtime parameter the
||| next Core parameter.
runtimeParams : (level : Nat) -> List Name -> (kinds : List PKind) ->
                (Vect (Runtimes kinds) Shown, List (VarInfo (Fin (Runtimes kinds))))
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
  (x :: ps, Static t (Just (FZ, h)) :: map (map FS) env)
runtimeParams level xs (ChoiceParam b known :: ks) =
  let (x, xs') = parameterName xs
      (ps, env) = runtimeParams level xs' ks in
  (x :: ps, Runtime FZ (BothTypes b.type known) :: map (map FS) env)
runtimeParams level xs (ValueParam b shape known :: ks) =
  let (x, xs') = parameterName xs
      (ps, env) = runtimeParams level xs' ks in
  (x :: ps, maybe (Runtime FZ (BothTypes b.type known)) (shaped FZ b.type known) shape
              :: map (map FS) env)

||| The names a type gives its parameters.
parameterNames : TT vs -> List Name
parameterNames (Bind _ x (Pi {}) sc) = x :: parameterNames sc
parameterNames _ = []

||| Every variable of a scope, the first first, as a term of it: one per
||| name the scope has.
variablesOf : (vs : Scope) -> Vect (length vs) (TT vs)
variablesOf [] = []
variablesOf (v :: vs) = Local EmptyFC Nothing 0 First :: map weaken (variablesOf vs)

||| Translates an instance of a definition at its signature, which its
||| request read once (`InstanceSig`) and every call of it holds. Its
||| runtime parameters are its Core parameters, numbered in order; a type,
||| an implementation and a parameter of quantity 0 are compile-time
||| values of the case tree's scope, which has one variable per parameter
||| of the definition's type.
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
  let sig = p.signature
  Nothing <- heldChoice sig.kinds
    | Just (before, chosen, after, ty) => heldDispatch p before chosen after ty
  let fc = location def
  Just m <- pure d.matched
    | Nothing => reject fc owner DefinitionShape "not a pattern-matching definition"
  let ty = d.type
  -- A missing case crashes.
  let complete = case isCovering (totality def) of
                   MissingCases _ => False
                   _ => True
  let (names, env) = runtimeParams 0 (parameterNames ty) sig.kinds
  tree' <- tree (MkCtx owner fc complete sig.result (givesAfter (length m.args) (memberPlaces d)) p) env (clauses m.args m.pats) m.tree
  loc <- toLoc fc
  -- Each array parameter's dimensions that a size variable fixes, stated
  -- equal to the parameter or the runtime size that fixes it first; an
  -- instance with no array parameter has none to state.
  ties <- if any (isJust . valueDims . (.type)) sig.callee.params
            then (entryTies . fst) <$> sizedTelescope ty sig.kinds
            else pure []
  let body = tied loc (allFins (Runtimes sig.kinds)) ties tree'
  -- What Idris proved of its loops, read with the program for every
  -- definition read (`Recursion`), in a table its addresses key, whose
  -- type does not say every definition read has an entry.
  let Just termination = lookup address (!reading).loops
    | Nothing => internal fc (owner ++ " has no component of Idris's call graph read")
  updateState (derive { fns $= insert p.inst (MkTFn p.key (telescopeOf sig.kinds) (Runtimes sig.kinds) sig.callee names
                                                      body loc termination) })
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

||| The scope a member at a use's body is in: its parameters' names, the
||| form's type's and the form's, as the type it is applied as by binds
||| them (`Application`), then `x` for each of the use's arguments.
appliedScope : Application -> Nat -> Scope
appliedScope app uses = app.formType :: app.form :: replicate uses (UN (Basic (known Kx)))

||| Translates a member at a use's types (`AtUse uses`): its body is its
||| form, its second parameter, applied to the use's arguments, its
||| parameters after it, as the form is applied wherever a scope binds it
||| (`Terms.implementationAt`), on a path of its own, at the type the use
||| gives. Its signature, read once where it was requested, is
||| `Instances.applicationType` classified, the form's type keying it
||| first, in the scope `appliedScope` names. It has no loop of its own:
||| what its form calls is the callee's.
translateApplication : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Request -> Nat -> Front ()
translateApplication p uses = do
  let owner = show p.owner
  let fc = p.site
  let sig = p.signature
  app <- (.application) <$> reading
  let (names, env) = runtimeParams 0 (appliedScope app uses) sig.kinds
  let (_ :: form :: arguments) = variablesOf (appliedScope app uses)
  -- No definition is translated, so what its result is the instance
  -- decides.
  body <- atType asWritten start (sizeAccessible start) (MkCtx owner fc True sig.result ByInstance p) env sig.result
                 (foldl (App fc) form arguments)
  loc <- toLoc fc
  updateState (derive { fns $= insert p.inst (MkTFn p.key (telescopeOf sig.kinds) (Runtimes sig.kinds) sig.callee names
                                                      body loc Acyclic) })

||| Translates one function instance, of a definition or of a member at a
||| use. An instance given an implementation that holds a choice the
||| running program made is a dispatch on that choice
||| (`Choices.heldDispatch`), each of its arms the instance with the choice
||| fixed, so no tree takes apart a field the program does not fix.
translateInstance : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Request -> Front ()
translateInstance p = case p.instantiates of
  OfDefinition n _ => translateDefinition p n
  AtUse uses => do
    Nothing <- heldChoice p.signature.kinds
      | Just (before, chosen, after, ty) => heldDispatch p before chosen after ty
    translateApplication p uses

||| One step of the translation's worklist: the instance of a request, the
||| item's own, translated as a function of what it reads (the program as
||| read, which every computation of the frontend's is given; and the
||| instance table and what the phases before it found, as the state
||| `found` holds them) and of the request, which the translation reads
||| where it takes apart what the request gives (`Ctx.request`). It runs on
||| a state of its own, whose derivation starts empty (`startingFrom`), and
||| gives back what it derived (`Derived`): it changes no other state, so a
||| step that refuses leaves nothing to undo.
export
step : {auto c : Ref Ctxt Defs} -> (found : TS) -> Request -> Front Derived
step found r = do
  s <- core (newRef TState ({ derived := startingFrom found.table } found))
  translateInstance r
  (.derived) <$> getState

||| The instance of `main` the root calls, requested: what it instantiates,
||| `main` at the arity its definition has, and its signature.
mainInstance : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> FC -> Name -> Front InstanceSig
mainInstance fc main = do
  d <- lookupDef fc (show main) main
  let PMDef _ params _ = definition d.def
    | _ => reject (location d.def) (show (fullname d.def)) DefinitionShape "not a pattern-matching definition"
  request fc (show main) (OfDefinition main (length params)) []

||| The root's request, as a step derives it (`step`): the instance of
||| `main` the root calls, requested, and what requesting it derived.
export
mainRequest : {auto c : Ref Ctxt Defs} -> FC -> Name -> (found : TS) -> Front (FnId, Derived)
mainRequest fc main found = do
  s <- core (newRef TState ({ derived := startingFrom found.table } found))
  sig <- mainInstance fc main
  pure (sig.callee.fn, (!getState).derived)

||| Every dispatch written as the function it is (`dispatchers`), as a step
||| derives it (`step`).
dispatched : {auto c : Ref Ctxt Defs} -> (found : TS) -> Front Derived
dispatched found = do
  s <- core (newRef TState ({ derived := startingFrom found.table } found))
  dispatchers
  (.derived) <$> getState

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
||| order they were requested, as the instance table holds them once every
||| step's derivation is merged into it. How a family's values are laid out
||| is the dialect's to decide, from each type, once.
assemble : Facts -> TFn -> Source
assemble t root =
  let fams = mapMaybe (\f => lookup f t.families) (t.familyOrder <>> [])
      fns = mapMaybe (\n => lookup n t.fns) (t.fnOrder <>> []) in
  MkSource (groupsOf fams) root fns

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
  Just _ <- core (translateFrom (mainRequest fc main) step)
    | Nothing => pure Nothing
  let [<] = (!(getState)).rejected
    | _ => pure Nothing
  -- Every member of every choice is known once the translation has ended:
  -- each dispatch on one is written now, and what writing them derived is
  -- merged into the instance table with what every step derived.
  written <- dispatched !getState
  updateState { table $= \t => merged t written }
  let owner = show main
  let notIO = reject fc owner ProgramShape "main must have type IO ()"
  -- Main was requested first, so requesting it again reads the signature
  -- every call of it holds.
  sig <- mainInstance fc main
  let FunT (MkBinder _ WorldT) res@(DataT _ _) = sig.callee.result
    | _ => notIO
  -- An action takes no argument but the world, which its value is applied
  -- to; a `main` that takes one is no `IO ()`.
  let Yes noArgument = decEq (Runtimes sig.kinds) 0
    | No _ => notIO
  st <- getState
  -- The root is code of no module, at the generated location: the world is
  -- its parameter, and main's value its action. A binder is known by its
  -- name over its own span, and this one has none, so it is no Idris
  -- binder's whatever it is called.
  let loc = noLoc
  let body : Term 1
      body = App loc (Call loc sig.callee Nothing [] (rewrite noArgument in [])) (Var loc FZ)
  -- The root is the one function of no definition, so no instance is it;
  -- its symbol is its key printed, as every symbol is.
  let rootKey = MkInstanceKey "$idris-mlir.root" NoArguments Whole
  -- The root is the `ProgramRoot` hook's code, `unsafePerformIO main`. It
  -- has no loop of its own; what main does is main's, which the passes find
  -- through the call.
  let root = MkTFn rootKey [] 1 (MkCallee RootFn (keyText rootKey) [MkBinder Once WorldT] res) [shown "world"]
                   body loc Acyclic
  pure (Just (assemble st.table root))
