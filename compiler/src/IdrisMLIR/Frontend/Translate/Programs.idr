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
import IdrisMLIR.Frontend.Translate.Boundary
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
import IdrisMLIR.Spec.Control.Joins
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Types

import Control.WellFounded
import Data.Fin
import Data.List
import Data.List.Quantifiers
import Data.Nat
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.Vect
import Decidable.Equality

%default total

-- A scope here is always a term's, the checker's: where a rule is decided
-- is no question this module asks.
%hide IdrisMLIR.Spec.Core.Rules.Scope

||| The name of the next parameter, and the names after it: a parameter
||| past the names a type gives is `x`.
parameterName : List Name -> (Shown, List Name)
parameterName [] = (shown "x", [])
parameterName (x :: xs) = (binderName x, xs)

||| An instance's runtime parameters' names, as the type it is classified
||| over names them, and what each variable of its body's scope stands for,
||| one per parameter, the scope having one variable per kind: a type, an
||| implementation or a parameter of quantity 0 a compile-time value, an
||| index parameter its level (the next one `level`), which its body's
||| types read, and a runtime parameter the next Core parameter. Each kind
||| comes with its parameter's position among the instance's `kc`
||| (`at`), which an implementation's entry keeps (`GivenParameter`).
runtimeParams : {0 sp : Scoping} -> (level : Nat) -> List Name -> (vars : Scope) -> (kinds : List PKind) ->
                (0 _ : length kinds = length vars) -> (at : Vect (length kinds) (Fin kc)) ->
                (Vect (Runtimes kinds) Shown, StandsFor kc sp vars (Fin (Runtimes kinds)))
runtimeParams level xs [] [] _ [] = ([], [])
runtimeParams level xs (_ :: vs) (TypeParam t :: ks) same (_ :: at) =
  let (ps, env) = runtimeParams level (snd (parameterName xs)) vs ks (predecessors same) at in (ps, TypeValue t :: env)
runtimeParams level xs (_ :: vs) (DictParam t Nothing :: ks) same (p :: at) =
  let (ps, env) = runtimeParams level (snd (parameterName xs)) vs ks (predecessors same) at in
  (ps, Static t Nothing (MkGivenParameter p Nothing) :: env)
runtimeParams level xs (_ :: vs) (ErasedParam :: ks) same (_ :: at) =
  let (ps, env) = runtimeParams level (snd (parameterName xs)) vs ks (predecessors same) at in
  (ps, TypeValue (Erased EmptyFC Placeholder) :: env)
runtimeParams level xs (_ :: vs) (IndexParam _ :: ks) same (_ :: at) =
  let (ps, env) = runtimeParams (S level) (snd (parameterName xs)) vs ks (predecessors same) at in
  (ps, TypeValue (marker level) :: env)
runtimeParams level xs (_ :: vs) (FormParam f :: ks) same (_ :: at) =
  let (ps, env) = runtimeParams level (snd (parameterName xs)) vs ks (predecessors same) at in (ps, TypeValue f :: env)
runtimeParams level xs (_ :: vs) (DictParam t (Just h) :: ks) same (p :: at) =
  let (x, xs') = parameterName xs
      (ps, env) = runtimeParams level xs' vs ks (predecessors same) at in
  (x :: ps, Static t (Just (FZ, h)) (MkGivenParameter p (Just (FZ, h))) :: map (map FS) env)
runtimeParams level xs (_ :: vs) (ChoiceParam b known :: ks) same (_ :: at) =
  let (x, xs') = parameterName xs
      (ps, env) = runtimeParams level xs' vs ks (predecessors same) at in
  (x :: ps, Runtime FZ (BothTypes b.type known.type) :: map (map FS) env)
runtimeParams level xs (_ :: vs) (ValueParam b shape known :: ks) same (_ :: at) =
  let (x, xs') = parameterName xs
      (ps, env) = runtimeParams level xs' vs ks (predecessors same) at in
  (x :: ps, maybe (Runtime FZ (BothTypes b.type known)) (shaped FZ b.type known) shape
              :: map (map FS) env)
runtimeParams level xs [] (_ :: _) Refl _ impossible
runtimeParams level xs (_ :: _) [] Refl _ impossible

||| Equal successors have equal predecessors.
predecessors : {0 m, n : Nat} -> S m = S n -> m = n
predecessors Refl = Refl

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
||| values of the case tree's scope, which has one variable per kind of
||| the signature, as the request classified as many parameters as the
||| body it holds has.
translateDefinition : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                      (p : Request) -> Name -> (m : Matched) ->
                      (0 _ : length p.signature.kinds = length m.args) -> Front ()
translateDefinition p n m counted = do
  d <- lookupDef EmptyFC (show n) n
  let def = d.def
  let owner = show (fullname def)
  let address = addressOf d.placement
  -- A definition the checks refused is left out, and so is what only it
  -- reaches.
  before <- getState
  False <- pure (contains address before.refused)
    | True => pure ()
  Nothing <- heldChoice p.signature.kinds
    | Just parts => heldDispatch p parts
  let fc = location def
  let ty = d.type
  -- A missing case crashes.
  let complete = case isCovering (totality def) of
                   MissingCases _ => False
                   _ => True
  let (names, env) = runtimeParams {sp = OfTree} 0 (parameterNames ty) m.args p.signature.kinds counted
                                   (Data.Vect.allFins (length p.signature.kinds))
  tree' <- tree (MkCtx owner fc complete p.signature.result p.signature.callee.result
                       (length (telescopeOf p.signature.kinds)) (givesAfter (length m.args) (memberPlaces d)) p Refl)
                env (clauses m.args m.pats) m.tree
  loc <- toLoc fc
  -- Each array parameter's dimensions that a size variable fixes, stated
  -- equal to the parameter or the runtime size that fixes it first; an
  -- instance with no array parameter has none to state.
  ties <- if any (isJust . valueDims . (.type)) p.signature.callee.params
            then (entryTies . fst) <$> sizedTelescope ty p.signature.kinds
            else pure []
  -- Where the definition stands, read once from its Idris name: a case,
  -- with or nested block is local to the function Idris lifted it out of.
  let standing = case blockOf (fullname def) of
                   Just _ => LocalDefinition
                   Nothing => OwnFunction
  -- A local definition, which a join point may make its region, states
  -- what its signature fixes of its result's dynamic dimensions, over its
  -- parameters, where its body gives its value (`tiedExits`): each call of
  -- it states the same of the value, and one that becomes a jump leaves
  -- the statement to the region.
  exits <- case (standing, valueDims p.signature.callee.result) of
             (LocalDefinition, Just _) => do
               (tel, res) <- sizedTelescope ty p.signature.kinds
               map (\(k, w) => (k, witnessTerm loc (allFins (Runtimes p.signature.kinds)) w)) <$> resultTies tel res p.signature.callee.result
             _ => pure []
  let body = tied loc p.signature.callee.params (allFins (Runtimes p.signature.kinds)) ties
                  (tiedExits loc p.signature.callee.result exits (length (telescopeOf p.signature.kinds)) p.signature.callee.params tree')
  -- What Idris proved of its loops, read with the program (`Recursion`).
  let termination = d.nature.termination
  extents <- signatureExtents p.signature.kinds p.signature.result
  updateState (derive { fns $= insert p.inst (MkTFn p.key standing (telescopeOf p.signature.kinds) (Runtimes p.signature.kinds) p.signature.callee
                                                      extents names body loc termination) })
  where
    -- The body under one `let` per parameter with a tied dimension, in
    -- parameter order: the parameter, of its binder's type, as its
    -- dimensions are stated, which the body uses in its place. The
    -- parameters are the body's variables, parameter `i` being `i`.
    tied : Loc -> Vect r Binder -> Vect r (Fin n) -> List (Fin r, List (Nat, Witness r)) -> Term n -> Term n
    tied loc params vs [] body = body
    tied loc params vs ((x, axes) :: rest) body =
      let p = Data.Vect.index x vs in
      Let loc (shown "tied") (OfValue Many)
          (Tie loc (Data.Vect.index x params).type (Var loc p) (map (\(k, w) => (k, witnessTerm loc vs w)) axes))
          (rename (\y => if y == p then FZ else FS y) (tied loc params vs rest body))

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
translateApplication : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                       (p : Request) -> (uses : Nat) -> (0 _ : length p.signature.kinds = 2 + uses) ->
                       Front ()
translateApplication p uses counted = do
  let owner = show p.owner
  let fc = p.site
  app <- (.application) <$> reading
  let (names, env) = runtimeParams {sp = OfTerm} 0 (appliedScope app uses) (appliedScope app uses) p.signature.kinds
                                   (trans counted (sym (cong (\k => S (S k)) (lengthReplicate uses))))
                                   (Data.Vect.allFins (length p.signature.kinds))
  let (_ :: form :: arguments) = variablesOf (appliedScope app uses)
  -- No definition is translated, so what its result is the instance
  -- decides.
  body <- atType asWritten start (sizeAccessible start) (MkCtx owner fc True p.signature.result p.signature.callee.result (length (telescopeOf p.signature.kinds)) ByInstance p Refl) env p.signature.result
                 (foldl (App fc) form arguments)
  loc <- toLoc fc
  extents <- signatureExtents p.signature.kinds p.signature.result
  updateState (derive { fns $= insert p.inst (MkTFn p.key OwnFunction (telescopeOf p.signature.kinds) (Runtimes p.signature.kinds) p.signature.callee
                                                      extents names body loc Acyclic) })

||| Translates one function instance, of a definition or of a member at a
||| use. An instance given an implementation that holds a choice the
||| running program made is a dispatch on that choice
||| (`Choices.heldDispatch`), each of its arms the instance with the choice
||| fixed, so no tree takes apart a field the program does not fix.
translateInstance : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Request -> Front ()
translateInstance p = translated p.instantiates p.classifiesAll
  where
    translated : (what : Instantiates) -> (0 _ : length p.signature.kinds = appliedArity what) -> Front ()
    translated (OfDefinition n m) counted = translateDefinition p n m counted
    translated (AtUse uses) counted = do
      Nothing <- heldChoice p.signature.kinds
        | Just parts => heldDispatch p parts
      translateApplication p uses counted

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
  let Just m = d.matched
    | Nothing => reject (location d.def) (show (fullname d.def)) DefinitionShape "not a pattern-matching definition"
  -- The root's call gives `main` no argument: each of its parameters is
  -- classified as a call that gives it none classifies it.
  kinds <- classifyKeys fc (show main) (show main) (length m.args) d.type (replicate (length m.args) Nothing)
  request fc (show main) (OfDefinition main m) kinds

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

------------------------------------------------------------------------------
-- The join points of local definitions
------------------------------------------------------------------------------

%prefix_record_projections off

||| A local join taken out of those not reached yet, by its identity, and
||| those left, one fewer.
record Taken (ms : List LocalJoin) where
  constructor MkTaken
  member : LocalJoin
  rest : List LocalJoin
  0 fewer : LT (length rest) (length ms)

%prefix_record_projections on

||| A local join's identity: its definition's.
joinId : LocalJoin -> FnId
joinId m = m.definition.callee.fn

||| The local join of `ms` with the identity `f`, taken out.
taken : FnId -> (ms : List LocalJoin) -> Maybe (Taken ms)
taken f [] = Nothing
taken f (m :: ms) =
  if joinId m == f
     then Just (MkTaken m ms reflexive)
     else (\t => MkTaken t.member (m :: t.rest) (LTESucc t.fewer)) <$> taken f ms

||| The local joins a function reaches, each once, in the order first
||| reached: through its calls and those of each one it reaches, every one
||| a tail call. Each one reached is taken out of those left, so the walk
||| ends.
reached : SortedMap FnId (List FnId) -> (left : List LocalJoin) -> (0 _ : Accessible LT (length left)) ->
          List FnId -> SnocList LocalJoin -> List LocalJoin
reached calls left acc [] found = found <>> []
reached calls left acc@(Access rec) (f :: fs) found = case taken f left of
  Nothing => reached calls left acc fs found
  Just t => reached calls t.rest (rec (length t.rest) t.fewer) (fromMaybe [] (lookup (joinId t.member) calls) ++ fs)
                    (found :< t.member)

||| Where the join op of a group of local joins puts their tokens: in its
||| body alone when none calls one, an `idr.join`; at the head of every
||| region when one does, an `idr.loop`, whose regions jump among
||| themselves.
tokenScope : SortedMap FnId (List FnId) -> List LocalJoin -> TokenScope
tokenScope calls group =
  let ids = the (SortedSet FnId) (fromList (map joinId group))
      callsOne = \m => any (\c => contains c ids) (fromMaybe [] (lookup (joinId m) calls)) in
  if any callsOne group then InEveryRegion else InBody

||| The join points in scope once each of the local joins `ms` has one, in
||| order, each outside those before it.
stacked : List LocalJoin -> List Nat -> List Nat
stacked [] js = js
stacked (m :: ms) js = stacked ms (pointArity m :: js)

0 stackedNonEmpty : (ms : List LocalJoin) -> Data.List.NonEmpty (stacked ms (k :: js))
stackedNonEmpty [] = Data.List.IsNonEmpty
stackedNonEmpty (m :: ms) = stackedNonEmpty ms

||| A term with every call of each local join of `ms` a jump to its join
||| point. Every call of one is a tail call wherever it is written
||| (`joinLocals` found it so), so none fails: one that did would be a
||| local definition that passed the test written as anything but a join
||| point.
throughAll : FC -> (ms : List LocalJoin) -> TermAt js n -> Front (TermAt (stacked ms js) n)
throughAll fc [] t = pure t
throughAll fc (m :: ms) t = case jumpsTo (continuationOf m) t of
  Just t' => throughAll fc ms t'
  Nothing => internal fc ("the local definition " ++ m.definition.callee.symbol ++
                          ", every call of which is a tail call, called where it returns")

||| The local joins' regions, each made of what `bodyOf` makes of its
||| region's body, in the order `stacked` gives their join points, in a
||| function whose telescope is `q` deep.
regionsIn : (q : Nat) -> ((m : LocalJoin) -> Front (TermAt s (pointArity m))) -> (ms : List LocalJoin) ->
            All (Target s r) js -> Front (All (Target s r) (stacked ms js))
regionsIn q bodyOf [] acc = pure acc
regionsIn q bodyOf (m :: ms) acc = do
  b <- bodyOf m
  regionsIn q bodyOf ms (regionAt q m b :: acc)

||| A function with the local joins it reaches as the join points of one op
||| around its body, every call of one a jump to it, and what Idris proved
||| of their loops part of what it proved of the function's.
joined : FC -> SortedMap FnId (List FnId) -> List LocalJoin -> TFn -> Front TFn
joined fc calls members f =
  case reached calls members (wellFounded (length members)) (fromMaybe [] (lookup f.callee.fn calls)) [<] of
    [] => pure f
    group@(m :: ms) => do
      body <- throughAll fc group f.body
      let q = length f.telescope
      withJoins <- the (Front (Term f.arity)) $ case tokenScope calls group of
        InBody => do
          targets <- regionsIn q (\g => pure (regionBody g)) group []
          pure (Join {nonEmpty = stackedNonEmpty {k = pointArity m} {js = []} ms} f.loc InBody targets body)
        InEveryRegion => do
          targets <- regionsIn q (\g => throughAll fc group (regionBody g)) group []
          pure (Join {nonEmpty = stackedNonEmpty {k = pointArity m} {js = []} ms} f.loc InEveryRegion targets body)
      pure (MkTFn f.key f.standing f.telescope f.arity f.callee f.extents f.paramNames withJoins f.loc
                  (withRegions f.termination (map (.definition) group)))

||| The local joins among `ms` whose calls run their actions.
runsOf : List LocalJoin -> List LocalJoin
runsOf [] = []
runsOf (m@(MkLocalJoin _ (ByRun _)) :: ms) = m :: runsOf ms
runsOf (_ :: ms) = runsOf ms

||| The program's functions with the join points its local definitions
||| make: a local definition (a `case`, `with`, `where` or `let` block Idris
||| lifted out of a function) every call of which, in every function, is
||| the head of a saturated application in a tail position (`jumpsTo` finds
||| a join point there) is no function of the program but a join region of
||| each function that reaches it. Its calls are tail calls with its
||| parameters, or, its result an action, tail calls applied to the world
||| (`JumpsBy`). A local definition only inlining would make one is left to
||| the passes that inline.
joinLocals : FC -> TFn -> List TFn -> Front (TFn, List TFn)
joinLocals fc root fns = do
  let calling = map (\f => (f, calleesOf f.body)) (root :: fns)
      calls = the (SortedMap FnId (List FnId)) (fromList (map (\(f, cs) => (f.callee.fn, cs)) calling))
      callers = foldl addCaller empty calling
      found = mapMaybe (jumpedBy callers) fns
      members = filter (fitsRuns (runsOf found)) found
      ids = the (SortedSet FnId) (fromList (map joinId members))
  root' <- joined fc calls members root
  others <- traverse (joined fc calls members) (filter (\f => not (contains f.callee.fn ids)) fns)
  pure (root', others)
  where
    -- A function, once, among the callers of each callee it calls.
    addCaller : SortedMap FnId (List TFn) -> (TFn, List FnId) -> SortedMap FnId (List TFn)
    addCaller m (f, cs) =
      foldl (\acc, c => insert c (f :: fromMaybe [] (lookup c acc)) acc) m
            (SortedSet.toList (the (SortedSet FnId) (fromList cs)))

    -- How a local definition's calls jump to it, each caller read as it
    -- is written: every one a tail call with its parameters; else, its
    -- result an action, every one a tail call applied to the world, its own
    -- calls read in its region, its action run on the world. A caller that
    -- runs another's action is never read as running its own, so no
    -- decision here rests on another's.
    jumpedBy : SortedMap FnId (List TFn) -> TFn -> Maybe LocalJoin
    jumpedBy callers f = case f.standing of
      OwnFunction => Nothing
      LocalDefinition =>
        let hs = fromMaybe [] (lookup f.callee.fn callers) in
        if all (\h => isJust (jumpsTo (Calling f.callee) h.body)) hs
          then Just (MkLocalJoin f ByCall)
          else case actionType f.callee.result of
            Nothing => Nothing
            Just a =>
              let m = MkLocalJoin f (ByRun a) in
              if all (\h => if h.callee.fn == f.callee.fn
                               then isJust (jumpsTo (continuationOf m) (regionBody m))
                               else isJust (jumpsTo (continuationOf m) h.body)) hs
                then Just m
                else Nothing

    -- A local join whose calls are tail calls with its parameters, read
    -- again in the region of each whose calls run its action, which applies
    -- each of its tails to the world: a call of it at such a tail is no
    -- longer a tail call with its parameters alone.
    fitsRuns : List LocalJoin -> LocalJoin -> Bool
    fitsRuns runs m@(MkLocalJoin _ ByCall) = all (\r => isJust (jumpsTo (continuationOf m) (regionBody r))) runs
    fitsRuns runs (MkLocalJoin _ (ByRun _)) = True

||| The program: its families as groups, and its function instances in the
||| order they were requested, as the instance table holds them once every
||| step's derivation is merged into it, with the join points its local
||| definitions make. How a family's values are laid out is the dialect's
||| to decide, from each type, once.
assemble : FC -> Facts -> TFn -> Front Source
assemble fc t root = do
  let fams = mapMaybe (declaredIn t) (t.familyOrder <>> [])
      fns = mapMaybe (\n => lookup n t.fns) (t.fnOrder <>> [])
  (root', others) <- joinLocals fc root fns
  pure (MkSource (groupsOf fams) root' others)

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
  let FunT (MkBinder world WorldT) res@(DataT _ _) = sig.callee.result
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
      body = App loc (MkBinder world WorldT) res (Call loc sig.callee Nothing [] (rewrite noArgument in [])) (Var loc FZ)
  -- The root is the one function of no definition, so no instance is it;
  -- its symbol is its key printed, as every symbol is.
  let rootKey = MkInstanceKey "$idris-mlir.root" NoArguments Whole
  -- The root is the `ProgramRoot` hook's code, `unsafePerformIO main`. It
  -- has no loop of its own; what main does is main's, which the passes find
  -- through the call.
  let root = MkTFn rootKey OwnFunction [] 1 (MkCallee RootFn (keyText rootKey) [MkBinder Once WorldT] res)
                   (MkExtents [[]] []) [shown "world"] body loc Acyclic
  Just <$> assemble fc st.table root
