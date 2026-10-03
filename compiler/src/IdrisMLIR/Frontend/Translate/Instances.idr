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
import IdrisMLIR.Frontend.Translate.Recursion
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Ids
import IdrisMLIR.Rule
import IdrisMLIR.Types

import Data.List
import Data.SortedMap
import Data.SortedSet
import Data.String

%default covering

||| How many instances of one definition the translation makes before it
||| gives up. Idris's size-change graphs rule out polymorphic recursion
||| (`checkRecursion`), and `growing` a recursion that deepens a shape, so
||| only a call Idris does not record (under `assert_total`, or through a
||| local function) can reach it.
instanceBudget : Nat
instanceBudget = 4096

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

||| The shapes of the runtime arguments, by position: a hole where there is
||| none.
shapes : List PKind -> List ClosedTerm
shapes = map shapeOf
  where
    shapeOf : PKind -> ClosedTerm
    shapeOf (ValueParam _ (Just s)) = s
    shapeOf _ = Erased EmptyFC Placeholder

||| Refuses an instance whose argument at a runtime parameter has a deeper
||| shape than at an instance of the same definition it comes from,
||| directly or through other definitions. The definition's type needs that
||| much of the value, so each instance would request one deeper again;
||| only translating the instances would show whether a match ends it, so
||| the first deeper one is refused.
growing : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          FC -> String -> Name -> String -> List PKind -> Core ()
growing fc owner n base kinds = do
  st <- get TState
  from st.current
  where
    deeper : (Nat, ClosedTerm, ClosedTerm) -> Bool
    deeper (_, before, after) = shapeDepth after > shapeDepth before

    from : Maybe FnId -> Core ()
    from Nothing = pure ()
    from (Just inst) = do
      st <- get TState
      let Just r = lookup inst st.requesters
        | Nothing => pure ()
      when (r.base == base) $
        case find deeper (zip [0 .. length kinds] (zip (shapes r.kinds) (shapes kinds))) of
          Just (i, before, after) => do
            x <- parameterName fc owner n i
            reject fc owner Polymorphism
                   ("polymorphic recursion: the type of " ++ base ++ " depends on its argument " ++ x ++
                    ", which its recursion builds deeper at each call (" ++ !(showTT after) ++
                    " after " ++ !(showTT before) ++ "), so that each instance would need another")
          Nothing => pure ()
      from r.parent

||| Requests a function instance, for parameters classified as the call
||| gives them, and returns its name. A new instance remembers how it came
||| to be: the chain leads back to the user definition a library instance
||| serves (`Dictionaries.chooser`), and through the instances of its own
||| definition it comes from (`growing`).
export
request : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          FC -> String -> Name -> List PKind -> Core FnId
request fc owner n kinds = do
  inst <- MkFnId <$> instanceName n (map staticOf kinds)
  base <- nameKey <$> toFullNames n
  st <- get TState
  unless (contains inst st.seen) $ do
    checkRecursion n
    growing fc owner n base kinds
    let count = fromMaybe 0 (lookup base st.perName)
    when (count >= instanceBudget) $
      reject fc owner CompileBudget ("more than " ++ show instanceBudget ++ " instances of " ++ base)
    update TState { seen $= insert inst
                  , perName $= insert base (S count)
                  , requesters $= insert inst (MkRequest n base st.current kinds)
                  , queue $= (++ [MkPending n inst kinds]) }
  pure inst

||| A compile-time value of an argument, computed on demand: normalised for a
||| type, as written for an implementation. `dictionary` says the argument is
||| an implementation known at compile time, whatever binds it: Idris passes
||| an enclosing function's constraints to its case and with blocks as
||| explicit arguments.
public export
record ArgValue where
  constructor MkArgValue
  normalised : Core ClosedTerm
  written : Core ClosedTerm
  dictionary : Bool

||| A compile-time argument as the instance's call classified it: the
||| value, and whether it is an implementation.
export
known : ClosedTerm -> Bool -> ArgValue
known t dict = MkArgValue (pure t) (pure t) dict

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
    given (DictParam t) = Just (known t True)
    given (ValueParam _ shape) = (\t => known t False) <$> shape

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

skip : ArgValues -> ArgValues
skip = Data.List.drop 1

||| Walks a callee's type over its arguments: which are type parameters or
||| implementations, which are erased, which are runtime (and their types).
export
classify : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           FC -> String -> Nat -> ClosedTerm -> ArgValues ->
           Core (List PKind, ClosedTerm)
classify fc owner Z ty _ = pure ([], ty)
classify fc owner (S k) (Bind bfc _ (Pi _ rig pinfo a) sc) vals = do
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
         (rest, res) <- classify fc owner k (subst (Erased bfc Placeholder) sc) (skip vals)
         pure (ValueParam Gone Nothing :: rest, res)
     else if !(dictionaryBinder rig pinfo a') || maybe False (.dictionary) (fst (nextStatic vals))
       then do
         let (Just v, vals') = nextStatic vals
           | _ => reject fc owner StaticArgument "an implementation that is not known statically"
         val <- v.written
         when !(runtimeDependent val) $
           reject fc owner RuntimeClosure ("an implementation chosen at runtime: " ++ !(showTT val))
         (rest, res) <- classify fc owner k !(normaliseClosed (subst val sc)) vals'
         pure (DictParam val :: rest, res)
       else do
         when !(erasedOutsideIndices owner a') $
           reject fc owner ValueType ("a parameter type that depends on another argument: " ++ !(showTT a'))
         t <- coreType fc owner ValueType a'
         -- The rest of the type may have to reduce on the parameter's value
         -- (`treeDelete : (n : Nat) -> ... -> Either (Tree n k v o) (delType n k v o)`
         -- in Data.SortedMap, where `delType` reduces on the constructors of
         -- `n`). Then the argument's shape, the constructors it is built
         -- with as written, everything else erased (`S _`), stands for the
         -- parameter in the type and keys the instance, so that the type
         -- reduces at each one as it does at each call; only as much of it
         -- as the type needs (`neededShape`), so that a recursion that
         -- builds its argument deeper below what the type looks at stays in
         -- one instance. The shape is read off the argument, never
         -- computed: a runtime argument is any computation, which the
         -- compiler must not run. An argument with no constructor at its
         -- head has no shape, and a parameter the type does not mention, or
         -- mentions only as an index (`Vect n Int`), keys nothing, so a
         -- function on naturals has one instance.
         let (v, vals') = nextStatic vals
         shape <- case (isNothing (shrink sc (Drop Refl)), v) of
           (True, Just arg) => do
             Just written <- skeleton <$> arg.written
               | Nothing => pure Nothing
             neededShape owner (\x => subst x sc) written
           _ => pure Nothing
         let value = fromMaybe (Erased bfc Placeholder) shape
         (rest, res) <- classify fc owner k !(normaliseClosed (subst value sc)) vals'
         pure (ValueParam (Held (useOf rig) t) shape :: rest, res)
classify fc owner (S k) ty vals = do
  ty' <- normaliseClosed ty
  case ty' of
    Bind {} => classify fc owner (S k) ty' vals
    _ => internal fc "more arguments than the type has binders"
