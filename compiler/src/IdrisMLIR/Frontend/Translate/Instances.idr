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

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Keys
import IdrisMLIR.Frontend.Translate.Recursion
import IdrisMLIR.Frontend.Translate.Shapes
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Ids
import IdrisMLIR.Registry
import IdrisMLIR.Syntax.Idr
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.List
import Data.SortedMap
import Data.SortedSet
import Data.String

%default covering

||| The name a definition's type gives its parameter at a position.
parameterName : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                FC -> String -> Name -> Nat -> Core String
parameterName fc owner n i = do
  def <- lookupDef fc owner n
  go i (type def)
  where
    go : Nat -> TT vs -> Core String
    go Z (Bind _ x (Pi {}) _) = pure (show x)
    go (S k) (Bind _ _ (Pi {}) sc) = go k sc
    go _ _ = pure ("number " ++ show (S i))

mutual
  ||| The size of a term, by which request chains compare static arguments:
  ||| 1 plus the sizes of its parts, an integer literal 1 plus its magnitude
  ||| and a string literal 1 plus its length, so that finitely many terms
  ||| share a size.
  termSize : TT vs -> Nat
  termSize (App _ f a) = 1 + termSize f + termSize a
  termSize (Bind _ _ b sc) = 1 + binderSize b + termSize sc
  termSize (PrimVal _ c) = 1 + constantSize c
  termSize (Meta _ _ _ args) = 1 + sum (map termSize args)
  termSize (As _ _ a p) = 1 + termSize a + termSize p
  termSize (TDelayed _ _ t) = 1 + termSize t
  termSize (TDelay _ _ t a) = 1 + termSize t + termSize a
  termSize (TForce _ _ t) = 1 + termSize t
  termSize (Erased _ (Dotted t)) = 1 + termSize t
  termSize _ = 1

  binderSize : TTBinder (TT vs) -> Nat
  binderSize (Let _ _ v ty) = termSize v + termSize ty
  binderSize (PLet _ _ v ty) = termSize v + termSize ty
  binderSize b = termSize (binderType b)

  ||| A constant measured on the literal it is (`constantLit`).
  constantSize : Constant -> Nat
  constantSize c = maybe 0 literalSize (constantLit c)

  ||| An integer by its magnitude, a string by its length, any other literal
  ||| by nothing more than itself.
  literalSize : Lit -> Nat
  literalSize (LInt _ n) = integerToNat (abs n)
  literalSize (LBig n) = integerToNat (abs n)
  literalSize (LNat n) = n
  literalSize (LStr s) = length s
  literalSize _ = 0

||| The sizes of an instance's static arguments, one per parameter: 0 where
||| a parameter keys nothing.
staticSizes : List PKind -> List Nat
staticSizes = map (\k => maybe 0 termSize (staticOf k))

||| The first position at which `after` is larger than `before`, when it is
||| smaller at none.
growsAt : List Nat -> List Nat -> Maybe Nat
growsAt before after =
  let pairs = zip before after in
  if all (\(b, a) => a >= b) pairs
     then fst <$> find (\(_, (b, a)) => a > b) (zip [0 .. length pairs] pairs)
     else Nothing

||| Refuses a new instance whose static arguments grow against an instance
||| of the same definition on its request chain (the instance requesting
||| it, the one that requested that, back to `main`): smaller in no
||| position and larger in one. On one chain the instances of one
||| definition have distinct keys, and finitely many keys share a vector
||| of sizes, so an infinite chain would have to grow somewhere (Dickson's
||| lemma) and is refused there; the request tree, finitely branching, is
||| then finite, and the worklist ends on every program. What is refused
||| is the recursion that builds a larger static argument at each call, a
||| construct no compile-time analysis bounds; anything else compiles,
||| however many instances it makes.
chainGrows : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> String -> Name -> String -> InstanceKey -> List PKind -> Core ()
chainGrows fc owner n base key kinds = from (!(get TState)).current
  where
    from : Maybe FnId -> Core ()
    from Nothing = pure ()
    from (Just inst) = do
      st <- get TState
      let Just r = lookup inst st.requesters
        | Nothing => pure ()
      when (r.base == base) $
        case growsAt (staticSizes r.kinds) (staticSizes kinds) of
          Just i => do
            x <- parameterName fc owner n i
            reject fc owner Polymorphism
                   ("polymorphic recursion: " ++ base ++ " requests itself with its argument " ++ x ++
                    " larger, which its recursion builds deeper at each call (" ++ keyText key ++
                    " after " ++ keyText r.key ++ "), so that each instance would need another")
          Nothing => pure ()
      from r.parent

||| Requests a function instance, for parameters classified as the call
||| gives them, and returns its identity. A new instance remembers how it came
||| to be: the chain leads back to the user definition a library instance
||| serves (`Dictionaries.chooser`), and through the instances of its own
||| definition it comes from (`chainGrows`).
export
request : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          FC -> String -> Name -> List PKind -> Core FnId
request fc owner n kinds = do
  (ident, key) <- instanceKey n (map staticOf kinds)
  let inst = MkFnId ident
  base <- nameKey <$> toFullNames n
  st <- get TState
  unless (contains inst st.seen) $ do
    checkRecursion n
    chainGrows fc owner n base key kinds
    update TState { seen $= insert inst
                  , requesters $= insert inst (MkRequest n base st.current kinds key)
                  , queue $= enqueue (MkPending n inst key kinds) }
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
  holed : Core (Maybe (ClosedTerm, List ClosedTerm))

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

nextStatic : ArgValues -> (Maybe ArgValue, ArgValues)
nextStatic (v :: vs) = (v, vs)
nextStatic [] = (Nothing, [])

||| What of a runtime argument's shape the rest of a callee's type needs to
||| reduce as it does at the call: the shape cut at the least depth at
||| which the normalised type mentions what the cut leaves unknown only as
||| an index of an inductive family, which is compile-time information.
||| Nothing when it needs none of it: `(n : Nat) -> Vect n Int -> Int`
||| only indexes a vector by `n`, so one instance serves every argument.
||| The whole shape when no depth is enough, the type stuck on what the
||| argument does not say.
neededShape : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              String -> (ClosedTerm -> ClosedTerm) -> ClosedTerm -> Core (Maybe ClosedTerm)
neededShape owner rest shape = go 0
  where
    go : Nat -> Core (Maybe ClosedTerm)
    go d =
      if d > shapeDepth shape then pure (Just shape) else do
        ty <- normaliseClosed (rest (cutShape unknownPart d shape))
        if !(outsideIndices mentionsUnknown owner ty)
           then go (S d)
           else pure (if d == 0 then Nothing else Just (cutShape (Erased EmptyFC Impossible) d shape))

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

skip : ArgValues -> ArgValues
skip = Data.List.drop 1

||| Walks a callee's type over its arguments: which are type parameters or
||| implementations, which are erased, which are runtime (and their types).
export
classify : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           FC -> String -> Nat -> ClosedTerm -> ArgValues ->
           Core (List PKind, ClosedTerm)
classify fc owner Z ty _ = pure ([], ty)
classify fc owner (S k) (Bind bfc _ (Pi _ rig _ a) sc) vals = do
  a' <- normaliseClosed a
  if isErased rig && isTypeLike a'
     then do
       let (Just v, vals') = nextStatic vals
         | _ => reject fc owner StaticArgument "a type argument that is not known statically"
       val <- v.normalised
       (rest, res) <- classify fc owner k !(normaliseClosed (subst val sc)) vals'
       pure (TypeParam val :: rest, res)
     else if isErased rig
       then do
         -- An erased shape of the array language that a value array's type
         -- needs is its form: a tensor's rank is its type, so it keys the
         -- instance. Any other erased argument keys nothing.
         needed <- if isShapeType (shapeOf !(toFullNames a'))
                     then formNeeded (\x => subst x sc)
                     else pure False
         if needed
            then do
              let (Just v, vals') = nextStatic vals
                | _ => reject fc owner StaticArgument "a shape that is not known statically"
              shape <- v.normalised
              let Just form = shapeForm shape
                | Nothing => reject fc owner Polymorphism ("a shape whose rank no analysis fixes: " ++ !(showTT shape))
              (rest, res) <- classify fc owner k !(normaliseClosed (subst form sc)) vals'
              pure (FormParam form :: rest, res)
            else do
              (rest, res) <- classify fc owner k (subst (Erased bfc Placeholder) sc) (skip vals)
              pure (ErasedParam :: rest, res)
     else if !(dictionaryBinder rig a') || maybe False (.dictionary) (fst (nextStatic vals))
       then do
         let (Just v, vals') = nextStatic vals
           | _ => reject fc owner StaticArgument "an implementation that is not known statically"
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
         hole <- the (Core (Maybe (ClosedTerm, List ClosedTerm))) (if dependent then v.holed else pure Nothing)
         -- The message is made in its own `do`: a `!` lifts to its
         -- statement, and would make it whether or not it is needed.
         when (dependent && isNothing hole) $ do
           reject fc owner RuntimeClosure ("an implementation chosen at runtime: " ++ !(showTT val))
         key <- case hole of
                  Just (shape, _) => implementationOf shape
                  Nothing => pure val
         holes <- case hole of
                    Just (_, tys) => do
                      held <- coreType fc owner ValueType !(normaliseClosed !(packedType tys))
                      pure (Just (MkHoles tys (MkBinder (quantityOf top) held)))
                    Nothing => pure Nothing
         (rest, res) <- classify fc owner k !(normaliseClosed (subst key sc)) vals'
         pure (DictParam key holes :: rest, res)
       else do
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
         let (v, vals') = nextStatic vals
         shape <- case (isNothing (shrink sc (Drop Refl)), v) of
           (True, Just arg) => do
             Just found <- argumentShape owner (\x => subst x sc) arg
               | Nothing => pure Nothing
             neededShape owner (\x => subst x sc) found
           _ => pure Nothing
         let value = fromMaybe (Erased bfc Placeholder) shape
         (rest, res) <- classify fc owner k !(normaliseClosed (subst value sc)) vals'
         pure (ValueParam b shape a' :: rest, res)
classify fc owner (S k) ty vals = do
  ty' <- normaliseClosed ty
  case ty' of
    Bind {} => classify fc owner (S k) ty' vals
    _ => internal fc "more arguments than the type has binders"
