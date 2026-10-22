-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Function instances: requesting one, and classifying a callee's
||| parameters as compile-time values (types and implementations, which key
||| the instance), erased ones, and runtime ones, whose argument's shape
||| keys the instance too when the type must reduce on the value.
module IdrisMLIR.Frontend.Translate.Instances

import Core.Context
import Core.Core
import Core.Name.Scoped
import Core.TT
import Libraries.Data.List.Thin

import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Keys
import IdrisMLIR.Frontend.Translate.Recursion
import IdrisMLIR.Frontend.Translate.Shapes
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Ids
import IdrisMLIR.Proof.Forms
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Registry
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.DPair
import Data.List
import Data.List1
import Data.SortedMap
import Data.SortedSet

%default total

-- Each static argument of a request read as the growth check reads a
-- site's (`Template.closedHeight`), by parameter index: its height, and
-- the head that splits the request's node: the implementation at the root
-- of each static implementation the call gives, and the type constructor
-- at the head of each family it gives. A type argument has a type
-- constructor at its root only when it is applied to fewer arguments than
-- it takes, which only a family's value is, so the type arguments that
-- split the node are the families, those the graph splits a callee by
-- (`Sites`). An implementation that is a function (`() -> Eq a`) and a
-- family that is a lambda have no root (`Unrooted`) and split nothing:
-- cases the problem has. A request's arguments hold no marker of the
-- growth check, so no root is a `Parameter` here. An argument is read
-- once, by its kind and as the request's link writes it, its identity
-- (`TS.readings`): the same type or implementation is given to many
-- requests. Each argument comes with how the link writes it
-- (`Keys.Instance`).
readings : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           Nat -> List (Maybe ((Subset Static Requested, ClosedTerm), Written Form)) -> Front (List (Nat, StaticReading))
readings i [] = pure []
readings i (Nothing :: as) = readings (S i) as
readings i (Just ((Element kind _, t), w) :: as) = do
  here <- case lookup (kind, w) (!(getState)).readings of
    Just r => pure r
    Nothing => do
      (h, root) <- closedHeight kind t
      let r = MkStaticReading h (case root of
                             Rooted j => Just j
                             Unrooted => Nothing
                             Parameter _ _ => Nothing)
      updateState { readings $= insert (kind, w) r }
      pure r
  ((i, here) ::) <$> readings (S i) as

||| Requests a function instance, for parameters classified as the call
||| gives them, and returns its identity. A new instance is recorded with
||| what it is an instance of, the site that requested it, the definition
||| whose translation did, and the node at whose positions the worklist
||| checks its static arguments against the growth check's bounds
||| (`Finite`): its definition, split by the heads of the implementations
||| and families it is given, so that a method's projection is checked at
||| the implementation that runs, and a definition over a family at the
||| type constructor it is. The link stays its identity.
export
request : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          FC -> (owner : String) -> Name -> List PKind -> Front FnId
request fc owner n kinds = do
  found <- instanceKey fc owner n snd (map staticKindOf kinds)
  st <- getState
  case lookup found.link st.fnIds of
    Just inst => pure inst
    Nothing => do
      let inst = MkFnId st.nextInstance
      updateState { fnIds $= insert found.link inst, nextInstance $= S }
      core (checkRecursion n)
      read <- readings 0 found.arguments
      let node = MkNode found.link.definition (mapMaybe (\(i, r) => (i,) <$> r.head) read)
      updateState { fnOrder $= (:< inst)
                    , requested $= (:< MkRequest inst n kinds found.key fc (shown owner) found.link node
                                                 (map (\(i, r) => (i, r.height)) read)) }
      pure inst

||| What a call knows of an argument it gives: an implementation known at
||| compile time, whatever binds it (Idris passes an enclosing function's
||| constraints to its case and with blocks as explicit arguments); a
||| choice of one, which a dispatch passes on (`Choices`); or a value,
||| whose parameter's type decides what it is.
public export
data Offer = AnImplementation | AChoice | AValue

||| A compile-time value of an argument, computed on demand: normalised for a
||| type, as written for an implementation, with what the call knows of it
||| (`Offer`). `holed` is the argument as an implementation that closes over
||| runtime values (`Terms.holed`): its form with a marker for each value
||| (`holeMarker`), and the values' types, by marker. These are what the
||| instance is keyed by, so none names a level of the caller's
||| (`unmarked`). `scoped` is the argument normalised in the caller's scope,
||| its levels kept: what an index parameter is given.
public export
record ArgValue where
  constructor MkArgValue
  normalised : Front ClosedTerm
  written : Front ClosedTerm
  offer : Offer
  holed : Front (Maybe (ClosedTerm, List1 ClosedTerm))
  scoped : Front ClosedTerm

||| A compile-time argument as the instance's call classified it: the
||| value, and what the call knows of it.
export
known : ClosedTerm -> Offer -> ArgValue
known t offer = MkArgValue (pure t) (pure t) offer (pure Nothing) (pure t)

||| The arguments of a call by position: `Nothing` for a runtime argument of
||| an instance.
public export
ArgValues : Type
ArgValues = List (Maybe ArgValue)

||| The arguments an instance is translated at, from the kinds its call
||| gave its parameters.
export
givenArgs : List PKind -> ArgValues
givenArgs = map given
  where
    given : PKind -> Maybe ArgValue
    given (TypeParam t) = Just (known t AValue)
    given (DictParam t Nothing) = Just (known t AnImplementation)
    given (DictParam t (Just h)) = Just ({ holed := pure (Just (t, h.types)) } (known t AnImplementation))
    given (ChoiceParam _ t) = Just (known t AChoice)
    given ErasedParam = Nothing
    given (IndexParam _) = Nothing
    given (FormParam f) = Just (known f AValue)
    given (ValueParam _ shape _) = (\t => known t AValue) <$> shape

||| The argument at the next parameter, and those after it: past the
||| arguments given, none.
nextStatic : List (Maybe a) -> (Maybe a, List (Maybe a))
nextStatic (v :: vs) = (v, vs)
nextStatic [] = (Nothing, [])

||| Does the rest of a callee's type reduce on a runtime parameter's value:
||| with what no shape says standing for the value, does the normalised
||| type mention it other than as an index of an inductive family, which is
||| compile-time information? Then the parameter is keyed by its
||| argument's shape. `(n : Nat) -> Vect n Int -> Int` only indexes a
||| vector by `n`, so one instance serves every argument.
needsShape : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             String -> (ClosedTerm -> ClosedTerm) -> Front Bool
needsShape owner rest = outsideIndices mentionsUnknown owner !(normaliseClosed (rest unknownPart))

||| What of a runtime argument's shape the rest of a callee's type needs to
||| reduce as it does at the call: nothing when it does not reduce on it
||| (`needsShape`); otherwise the shape cut at the least depth at which the
||| normalised type mentions what the cut leaves unknown only as an index,
||| or the whole shape when no depth is enough, the type stuck on what the
||| argument does not say.
neededShape : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              String -> (ClosedTerm -> ClosedTerm) -> ClosedTerm -> Front (Maybe ClosedTerm)
neededShape owner rest shape =
  if not !(needsShape owner rest) then pure Nothing else least (drop 1 [0 .. shapeDepth shape])
  where
    -- The depths a cut can have past the empty one, the least first.
    least : List Nat -> Front (Maybe ClosedTerm)
    least [] = pure (Just shape)
    least (d :: ds) = do
      ty <- normaliseClosed (rest (cutShape unknownPart d shape))
      if !(outsideIndices mentionsUnknown owner ty)
         then least ds
         else pure (Just (cutShape (Erased EmptyFC Impossible) d shape))

||| The shape of a runtime argument, as far as it is known at compile time:
||| the constructors written in it (`skeleton`), or, for an argument that
||| mentions no runtime value and without which the rest of the type is
||| stuck, the constructors of what it reduces to. Base's `clockTime` passes
||| its with block `isClockMandatory clockType`, a closed pure call with no
||| constructor written, on which the block's type reduces.
argumentShape : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                String -> (ClosedTerm -> ClosedTerm) -> ArgValue -> Front (Maybe ClosedTerm)
argumentShape owner rest arg = do
  written <- arg.written
  case skeleton written of
    Just shape => pure (Just shape)
    Nothing =>
      if !(runtimeDependent written) then pure Nothing else do
        Just _ <- neededShape owner rest (Erased EmptyFC Impossible)
          | Nothing => pure Nothing
        skeleton <$> arg.normalised

||| How the rest of a callee's type depends on a runtime parameter: it does
||| not mention it (`Runs`), or it does (`Reduces`), and then the argument's
||| shape keys the instance as far as the rest reduces on it (`needsShape`).
data Dependence = Runs | Reduces

||| How a parameter keys an instance, decided from its binder (its quantity,
||| its normalised type and the rest of the type) and what the call knows
||| of its argument (`Offer`): a type, a type family (a type parameter whose
||| kind is a function into a universe), a form, an implementation, at the
||| quantity its binder has, an erased value that keys nothing, or a
||| runtime value, by how the rest of the type depends on it. The one place
||| `classify` and `staticsOver` decide it.
data Keying = Typed | Family | Formed | Implemented Uses | Unkeyed | Runtime Dependence

keyingOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           RigCount -> ClosedTerm -> TT [x] -> Offer -> Front Keying
keyingOf rig a' sc offer = case use rig of
  Erased =>
    if isTypeLike a' then pure (case a' of
                                  Bind _ _ (Pi {}) _ => Family
                                  _ => Typed) else do
      -- An erased shape of the array language that the rest of the type
      -- puts in a form is its form: a tensor's rank is its type, so it
      -- keys the instance, by the rule a data type's parameter is formed
      -- by. Any other erased argument keys nothing.
      pure (if !(formNeeded a' (\x => subst x sc)) then Formed else Unkeyed)
  Used q => case offer of
    AnImplementation => pure (Implemented q)
    AChoice => pure (Implemented q)
    AValue =>
      if !(implementationType a')
         then pure (Implemented q)
         else pure (Runtime (if isJust (shrink sc (Drop Refl)) then Runs else Reduces))

||| `classify`'s decisions over arguments given as closed terms (over the
||| growth check's markers, `Growth.Sites`), each with what the call knows
||| of it (`Offer`), or `Nothing` for a runtime value: each parameter's
||| kind, and the rest of the type. It decides by `keyingOf` and
||| `needsShape`, as `classify` does, but computes no value, reads no Core
||| type, registers nothing and refuses nothing, so it runs over markers.
export
staticsOver : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              (owner : String) -> (arity : Nat) -> (callee : ClosedTerm) ->
              List (Maybe (ClosedTerm, Offer)) -> Front (Vect arity (Maybe Static), ClosedTerm)
staticsOver owner Z ty _ = pure ([], ty)
staticsOver owner (S k) ty vals = do
  Bind _ _ (Pi _ rig _ a) sc <- showingBinder ty
    | _ => internal EmptyFC "more arguments than the type has binders"
  a' <- normaliseClosed a
  let (given, vals') = nextStatic vals
  kind <- case !(keyingOf rig a' sc (maybe AValue snd given)) of
    Typed => pure (Just AType)
    Family => pure (Just AFamily)
    Formed => pure (Just AForm)
    Implemented _ => pure (Just ADictionary)
    Unkeyed => pure Nothing
    Runtime Runs => pure Nothing
    Runtime Reduces => pure (if !(needsShape owner (\x => subst x sc)) then Just AShape else Nothing)
  (kinds, res) <- staticsOver owner k !(normaliseClosed (subst (maybe (Erased EmptyFC Placeholder) fst given) sc)) vals'
  pure (kind :: kinds, res)

||| A callee's parameters, classified over its arguments (`classifyCall`),
||| and the type after them.
public export
Classified : Type
Classified = (List PKind, ClosedTerm)

||| Walks a callee's type over its arguments: which are type parameters or
||| implementations, which are erased, which are index parameters, which
||| are runtime (and their types). Each index parameter stands in the rest
||| of the type as its own level (`marker`), the next one `level`, so the
||| types read in the callee's scope.
classifyAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> String -> (level : Nat) -> Nat -> ClosedTerm -> ArgValues ->
             Front Classified
classifyAt fc owner level Z ty _ = pure ([], ty)
classifyAt fc owner level (S k) ty vals = do
  Bind bfc _ (Pi _ rig _ a) sc <- showingBinder ty
    | _ => internal fc "more arguments than the type has binders"
  parameter bfc rig a sc
  where
    -- The parameter a binder binds, and the rest of the type after it.
    parameter : FC -> RigCount -> ClosedTerm -> TT [x] -> Front Classified
    parameter bfc rig a sc = do
      a' <- normaliseClosed a
      let (given, vals') = nextStatic vals
      case !(keyingOf rig a' sc (maybe AValue (.offer) given)) of
        Typed => typed given vals'
        -- A family keys its instance as any type does; only the growth
        -- check reads what heads its value.
        Family => typed given vals'
        Formed => do
          let Just v = given
            | Nothing => reject fc owner StaticArgument "a shape that is not known statically"
          form <- formOf <$> spineOf fc owner !(v.normalised)
          mapFst (FormParam form ::) <$> classifyAt fc owner level k !(normaliseClosed (subst form sc)) vals'
        -- An erased binder an index of a runtime parameter's type or of
        -- the result reads, and nothing a value is made of, is an index
        -- parameter, its level standing for it in the rest of the type;
        -- any other is absent.
        Unkeyed => do
          rest <- normaliseClosed (subst (marker level) sc)
          case !(occurrenceOf owner level rest) of
            IndexOnly => do
              sort <- sortOfType a'
              mapFst (IndexParam sort ::) <$> classifyAt fc owner (S level) k rest vals'
            _ => mapFst (ErasedParam ::) <$> classifyAt fc owner level k (subst (Erased bfc Placeholder) sc) vals'
        Implemented q => do
          let Just v = given
            | Nothing => reject fc owner StaticArgument "an implementation that is not known statically"
          case v.offer of
            AChoice => chosen q a' vals'
            _ => do
              written <- v.written
              implemented q a' v written vals'
        Runtime dependence => do
          when !(erasedOutsideIndices owner a') $ do
            reject fc owner ValueType ("a parameter type that depends on another argument: " ++ !(showTT a'))
          b <- coreBinder fc owner ValueType rig a'
          -- The rest of the type may have to reduce on the parameter's value
          -- (`treeDelete : (n : Nat) -> ... -> Either (Tree n k v o) (delType n k v o)`
          -- in Data.SortedMap, where `delType` reduces on the constructors of
          -- `n`). Then the argument's shape, the constructors it is built
          -- with as written, everything else erased (`S _`), stands for the
          -- parameter in the type and keys the instance, so that the type
          -- reduces at each one as it does at each call; only as much of it
          -- as the type needs (`neededShape`), so that a recursion that
          -- builds its argument deeper below what the type looks at stays in
          -- one instance. The shape is read off the argument as written; it
          -- is computed only for a closed argument, one that mentions no
          -- runtime value, that the type is stuck without (`argumentShape`),
          -- by normalising it as the type itself is normalised. An argument
          -- that mentions a runtime value is any computation, which the
          -- compiler must not run. An argument with no constructor at its
          -- head, written or reduced to, has no shape, and a parameter the
          -- type does not mention, or mentions only as an index
          -- (`Vect n Int`), keys nothing, so a function on naturals has one
          -- instance.
          shape <- case (dependence, given) of
            (Reduces, Just arg) => do
              Just found <- argumentShape owner (\x => subst x sc) arg
                | Nothing => pure Nothing
              neededShape owner (\x => subst x sc) found
            _ => pure Nothing
          let value = fromMaybe (Erased bfc Placeholder) shape
          mapFst (ValueParam b shape a' ::) <$> classifyAt fc owner level k !(normaliseClosed (subst value sc)) vals'
      where
        -- A type, normalised, keys the instance.
        typed : Maybe ArgValue -> ArgValues -> Front Classified
        typed given after = do
          let Just v = given
            | Nothing => reject fc owner StaticArgument "a type argument that is not known statically"
          val <- v.normalised
          mapFst (TypeParam val ::) <$> classifyAt fc owner level k !(normaliseClosed (subst val sc)) after

        -- An implementation given as written, at a parameter of an
        -- interface's type.
        implemented : Uses -> ClosedTerm -> ArgValue -> ClosedTerm -> ArgValues -> Front Classified
        implemented q a' v written vals' = do
          -- An implementation can be a function of a runtime value
          -- (`{y : a} -> Show (p y)`, applied to the first component of a
          -- dependent pair), which Idris resolved at every value: constant
          -- in it, or using it only where it is erased (`Show (Tag y)`).
          -- What the function returns is then a compile-time value, seen
          -- once the projections and applications that lead to it are
          -- reduced.
          val <- if !(runtimeDependent written) then implementationOf written else pure written
          -- One that a definition gives without matching on a runtime value
          -- it closes over (`{vars : _} -> Show (Term vars)`) is chosen now
          -- all the same, and only the value is passed at runtime. What
          -- written holds only in an erased argument can still be needed
          -- at runtime once the implementation is expanded to its
          -- constructor, whose own blocks take that argument as an
          -- ordinary parameter (a case block of `Show (Term vars)` takes
          -- `vars` so), so dependence is judged on the expanded form too;
          -- an argument expansion keeps only in types (a grammar's
          -- consumption index) is no dependence. A form no compile-time
          -- reduction may expand, through a definition Idris does not prove
          -- ends, is taken as dependent: what it would show is not known.
          dependent <- if !(runtimeDependent val) then pure True
                         else if hasRuntimePart written
                                then maybe (pure True) runtimeDependent !(expandClosed written)
                                else pure False
          if not dependent then staticOrChosen q a' val vals' else do
            -- One that still needs a runtime value to say which it is is
            -- chosen at run time, among those the program fixes.
            Just (shape, tys) <- v.holed
              | Nothing => chosen q a' vals'
            key <- implementationOf shape
            held <- coreType fc owner ValueType !(normaliseClosed !(packedType tys))
            static key (Just (MkHoles tys (MkBinder Many held))) vals'

        -- An implementation that needs no runtime value keys the
        -- instance, unless a definition Idris does not prove ends computes
        -- it: no compile-time reduction runs that, so it is computed at run
        -- time, a choice like any other.
        staticOrChosen : Uses -> ClosedTerm -> ClosedTerm -> ArgValues -> Front Classified
        staticOrChosen q a' val vals' = do
          Stuck (OnPartial _) <- whnf val
            | _ => static val Nothing vals'
          chosen q a' vals'

        -- An implementation known now keys the instance.
        static : ClosedTerm -> Maybe Holes -> ArgValues -> Front Classified
        static key holes vals' =
          mapFst (DictParam key holes ::) <$> classifyAt fc owner level k !(normaliseClosed (subst key sc)) vals'

        -- A choice of an implementation of the parameter's type, a value at
        -- run time. Which implementation it is no type after it can read.
        chosen : Uses -> ClosedTerm -> ArgValues -> Front Classified
        chosen q a' vals' = do
          choice <- choiceFamily fc owner a'
          mapFst (ChoiceParam (MkBinder q (DataT choice.family [])) a' ::)
            <$> classifyAt fc owner level k !(normaliseClosed (subst (Erased bfc Placeholder) sc)) vals'

||| What a call gives each index parameter of its callee, in order: the
||| argument at its position, normalised in the caller's scope with the
||| caller's own levels kept; nothing where the call gives none.
indexForms : {auto c : Ref Ctxt Defs} -> List PKind -> ArgValues -> Front (List (Maybe ClosedTerm))
indexForms [] _ = pure []
indexForms (IndexParam _ :: ks) vals = do
  let (given, vals') = nextStatic vals
  here <- traverse (.scoped) given
  (here ::) <$> indexForms ks vals'
indexForms (_ :: ks) vals = indexForms ks (snd (nextStatic vals))

||| The index terms a call passes its callee, one per index parameter, in
||| the caller's scope: a number, a successor chain, a level of the
||| caller's own, or outside the language where no link exists (an
||| argument no index term reads, or none given).
export
callIndices : {auto c : Ref Ctxt Defs} -> List PKind -> ArgValues -> Front (List ITerm)
callIndices kinds vals = traverse (maybe (pure IOpaque) indexTerm) !(indexForms kinds vals)

||| The terms a construction site gives its constructor's erased binders,
||| in the site's scope: each the term of the argument at the binder's
||| position (a number, a level of the site's own plus a count), outside the
||| language where the site gives no argument there or no term reads it.
export
binderTerms : {auto c : Ref Ctxt Defs} -> List ConBinder -> ArgValues -> Front (List ITerm)
binderTerms bs vals = traverse term bs
  where
    term : ConBinder -> Front ITerm
    term b = case join (getAt b.argument vals) of
      Just v => indexTerm !(v.scoped)
      Nothing => pure IOpaque

||| A callee's classified signature read in the scope of a call: each of
||| its levels given the argument the call passes it, erased where it
||| passes none, in its runtime parameters' types and its result, so that
||| no level of the callee's reads as one of the caller's.
inCaller : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           FC -> String -> ArgValues -> (List PKind, ClosedTerm) -> Front (List PKind, ClosedTerm)
inCaller fc owner vals (kinds, res) = case telescopeOf kinds of
  [] => pure (kinds, res)
  _ => do
    forms <- indexForms kinds vals
    kinds' <- traverse (kindAt forms) kinds
    res' <- normaliseClosed (atLevels forms res)
    pure (kinds', res')
  where
    kindAt : List (Maybe ClosedTerm) -> PKind -> Front PKind
    kindAt forms (ValueParam b shape idrisType) = do
      here <- normaliseClosed (atLevels forms idrisType)
      t <- coreType fc owner ValueType here
      pure (ValueParam ({ type := t } b) shape here)
    kindAt forms k = pure k

||| A callee's parameters classified at a call (`classifyAt`), read in the
||| caller's scope (`inCaller`): what every call of a function and every
||| use of a primitive's or a library function's signature reads.
export
classifyCall : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               FC -> String -> Nat -> ClosedTerm -> ArgValues ->
               Front Classified
classifyCall fc owner arity ty vals = inCaller fc owner vals !(classifyAt fc owner 0 arity ty vals)

||| An instance's own signature, classified on the static arguments it was
||| requested with: its index parameters its own levels, which its body's
||| scope binds first.
export
classifyInstance : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                   FC -> String -> Nat -> ClosedTerm -> ArgValues ->
                   Front Classified
classifyInstance fc owner arity ty vals = classifyAt fc owner 0 arity ty vals
