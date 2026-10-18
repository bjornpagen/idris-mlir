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
import IdrisMLIR.Syntax.Idr
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
           Nat -> List (Maybe ((Subset Static Requested, ClosedTerm), Written Form)) -> Core (List (Nat, StaticReading))
readings i [] = pure []
readings i (Nothing :: as) = readings (S i) as
readings i (Just ((Element kind _, t), w) :: as) = do
  here <- case lookup (kind, w) (!(get TState)).readings of
    Just r => pure r
    Nothing => do
      (h, root) <- closedHeight kind t
      let r = MkStaticReading h (case root of
                             Rooted j => Just j
                             Unrooted => Nothing
                             Parameter _ _ => Nothing)
      update TState { readings $= insert (kind, w) r }
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
          FC -> (owner : String) -> Name -> List PKind -> Core FnId
request fc owner n kinds = do
  found <- instanceKey fc owner n snd (map staticKindOf kinds)
  let inst = MkFnId found.symbol
  st <- get TState
  unless (contains inst st.seen) $ do
    checkRecursion n
    read <- readings 0 found.arguments
    let node = MkNode found.link.definition (mapMaybe (\(i, r) => (i,) <$> r.head) read)
    update TState { seen $= insert inst
                  , fnOrder $= (:< inst)
                  , requested $= (:< MkRequest inst n kinds found.key fc (shown owner) found.link node
                                               (map (\(i, r) => (i, r.height)) read)) }
  pure inst

||| A compile-time value of an argument, computed on demand: normalised for a
||| type, as written for an implementation. `dictionary` says the argument is
||| an implementation known at compile time, whatever binds it: Idris passes
||| an enclosing function's constraints to its case and with blocks as
||| explicit arguments. `holed` is the argument as an implementation that
||| closes over runtime values (`Terms.holed`): its form with a marker for
||| each value (`holeMarker`), and the values' types, by marker.
public export
record ArgValue where
  constructor MkArgValue
  normalised : Core ClosedTerm
  written : Core ClosedTerm
  dictionary : Bool
  holed : Core (Maybe (ClosedTerm, List1 ClosedTerm))

||| A compile-time argument as the instance's call classified it: the
||| value, and whether it is an implementation.
export
known : ClosedTerm -> Bool -> ArgValue
known t dict = MkArgValue (pure t) (pure t) dict (pure Nothing)

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
    given (TypeParam t) = Just (known t False)
    given (DictParam t Nothing) = Just (known t True)
    given (DictParam t (Just h)) = Just ({ holed := pure (Just (t, h.types)) } (known t True))
    given ErasedParam = Nothing
    given (FormParam f) = Just (known f False)
    given (ValueParam _ shape _) = (\t => known t False) <$> shape

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
             String -> (ClosedTerm -> ClosedTerm) -> Core Bool
needsShape owner rest = outsideIndices mentionsUnknown owner !(normaliseClosed (rest unknownPart))

||| What of a runtime argument's shape the rest of a callee's type needs to
||| reduce as it does at the call: nothing when it does not reduce on it
||| (`needsShape`); otherwise the shape cut at the least depth at which the
||| normalised type mentions what the cut leaves unknown only as an index,
||| or the whole shape when no depth is enough, the type stuck on what the
||| argument does not say.
neededShape : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              String -> (ClosedTerm -> ClosedTerm) -> ClosedTerm -> Core (Maybe ClosedTerm)
neededShape owner rest shape =
  if not !(needsShape owner rest) then pure Nothing else least (drop 1 [0 .. shapeDepth shape])
  where
    -- The depths a cut can have past the empty one, the least first.
    least : List Nat -> Core (Maybe ClosedTerm)
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
                String -> (ClosedTerm -> ClosedTerm) -> ArgValue -> Core (Maybe ClosedTerm)
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
||| its normalised type and the rest of the type) and whether its argument
||| is an implementation: a type, a type family (a type parameter whose
||| kind is a function into a universe), a form, an implementation, an
||| erased value that keys nothing, or a runtime value, by how the rest of
||| the type depends on it. The one place `classify` and `staticsOver`
||| decide it.
data Keying = Typed | Family | Formed | Implemented | Unkeyed | Runtime Dependence

keyingOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           RigCount -> ClosedTerm -> TT [x] -> (dictionary : Bool) -> Core Keying
keyingOf rig a' sc dictionary =
  if isErased rig
     then if isTypeLike a' then pure (case a' of
                                        Bind _ _ (Pi {}) _ => Family
                                        _ => Typed) else do
            -- An erased shape of the array language that a value array's
            -- type needs is its form: a tensor's rank is its type, so it
            -- keys the instance. Any other erased argument keys nothing.
            needed <- if isShapeType (shapeOf !(toFullNames a'))
                        then formNeeded (\x => subst x sc)
                        else pure False
            pure (if needed then Formed else Unkeyed)
     else if !(dictionaryBinder rig a') || dictionary
             then pure Implemented
             else pure (Runtime (if isJust (shrink sc (Drop Refl)) then Runs else Reduces))

||| `classify`'s decisions over arguments given as closed terms (over the
||| growth check's markers, `Growth.Sites`), each with whether it is an
||| implementation, or `Nothing` for a runtime value: each parameter's
||| kind, and the rest of the type. It decides by `keyingOf` and
||| `needsShape`, as `classify` does, but computes no value, reads no Core
||| type, registers nothing and refuses nothing, so it runs over markers.
export
staticsOver : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              (owner : String) -> (arity : Nat) -> (callee : ClosedTerm) ->
              List (Maybe (ClosedTerm, Bool)) -> Core (List (Maybe Static), ClosedTerm)
staticsOver owner Z ty _ = pure ([], ty)
staticsOver owner (S k) ty vals = do
  Bind _ _ (Pi _ rig _ a) sc <- the (Core ClosedTerm) (case ty of
                                    Bind _ _ (Pi {}) _ => pure ty
                                    _ => normaliseClosed ty)
    | _ => internal EmptyFC "more arguments than the type has binders"
  a' <- normaliseClosed a
  let (given, vals') = nextStatic vals
  kind <- case !(keyingOf rig a' sc (maybe False snd given)) of
    Typed => pure (Just AType)
    Family => pure (Just AFamily)
    Formed => pure (Just AForm)
    Implemented => pure (Just ADictionary)
    Unkeyed => pure Nothing
    Runtime Runs => pure Nothing
    Runtime Reduces => pure (if !(needsShape owner (\x => subst x sc)) then Just AShape else Nothing)
  (kinds, res) <- staticsOver owner k !(normaliseClosed (subst (maybe (Erased EmptyFC Placeholder) fst given) sc)) vals'
  pure (kind :: kinds, res)

||| Walks a callee's type over its arguments: which are type parameters or
||| implementations, which are erased, which are runtime (and their types).
export
classify : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           FC -> String -> Nat -> ClosedTerm -> ArgValues ->
           Core (List PKind, ClosedTerm)
classify fc owner Z ty _ = pure ([], ty)
classify fc owner (S k) ty vals = case ty of
  Bind bfc _ (Pi _ rig _ a) sc => parameter bfc rig a sc
  _ => do
    -- A type that shows its binders only once normalised, written with a
    -- name for a function type.
    Bind bfc _ (Pi _ rig _ a) sc <- normaliseClosed ty
      | _ => internal fc "more arguments than the type has binders"
    parameter bfc rig a sc
  where
    -- The parameter a binder binds, and the rest of the type after it.
    parameter : FC -> RigCount -> ClosedTerm -> TT [x] -> Core (List PKind, ClosedTerm)
    parameter bfc rig a sc = do
      a' <- normaliseClosed a
      let (given, vals') = nextStatic vals
      case !(keyingOf rig a' sc (maybe False (.dictionary) given)) of
        Typed => typed given vals'
        -- A family keys its instance as any type does; only the growth
        -- check reads what heads its value.
        Family => typed given vals'
        Formed => do
          let Just v = given
            | Nothing => reject fc owner StaticArgument "a shape that is not known statically"
          shape <- v.normalised
          let Just form = shapeForm shape
            | Nothing => reject fc owner Polymorphism ("a shape whose rank no analysis fixes: " ++ !(showTT shape))
          (rest, res) <- classify fc owner k !(normaliseClosed (subst form sc)) vals'
          pure (FormParam form :: rest, res)
        Unkeyed => do
          (rest, res) <- classify fc owner k (subst (Erased bfc Placeholder) sc) vals'
          pure (ErasedParam :: rest, res)
        Implemented => do
          let Just v = given
            | Nothing => reject fc owner StaticArgument "an implementation that is not known statically"
          written <- v.written
          -- An implementation can be a function of a runtime value
          -- (`{y : a} -> Show (p y)`, applied to the first component of a
          -- dependent pair), which Idris resolved at every value: constant
          -- in it, or using it only where it is erased (`Show (Tag y)`).
          -- What the function returns is then a compile-time value, seen
          -- once the projections and applications that lead to it are
          -- reduced; one that still needs the value is chosen at runtime.
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
          (key, holes) <- the (Core (ClosedTerm, Maybe Holes)) $
            if not dependent then pure (val, Nothing) else do
              -- The message is made in its own `do`: a `!` lifts to its
              -- statement, and would make it whether or not it is needed.
              Just (shape, tys) <- v.holed
                | Nothing => do
                    reject fc owner RuntimeClosure ("an implementation chosen at runtime: " ++ !(showTT val))
              key <- implementationOf shape
              held <- coreType fc owner ValueType !(normaliseClosed !(packedType tys))
              pure (key, Just (MkHoles tys (MkBinder (quantityOf top) held)))
          (rest, res) <- classify fc owner k !(normaliseClosed (subst key sc)) vals'
          pure (DictParam key holes :: rest, res)
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
          (rest, res) <- classify fc owner k !(normaliseClosed (subst value sc)) vals'
          pure (ValueParam b shape a' :: rest, res)
      where
        -- A type, normalised, keys the instance.
        typed : Maybe ArgValue -> ArgValues -> Core (List PKind, ClosedTerm)
        typed given after = do
          let Just v = given
            | Nothing => reject fc owner StaticArgument "a type argument that is not known statically"
          val <- v.normalised
          (rest, res) <- classify fc owner k !(normaliseClosed (subst val sc)) after
          pure (TypeParam val :: rest, res)
