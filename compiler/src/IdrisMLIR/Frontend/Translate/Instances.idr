||| Function instances: requesting one, and classifying a callee's
||| parameters as compile-time values (types and implementations, which key
||| the instance), erased ones, and runtime ones, whose argument's shape
||| keys the instance too when the type depends on the value.
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
||| (`checkRecursion`), so only a call Idris does not record (under
||| `assert_total`, or through a local function) can reach it.
instanceBudget : Nat
instanceBudget = 4096

||| Requests a function instance, for parameters classified as the call
||| gives them, and returns its name. A new instance remembers the instance
||| that requested it, which leads back to the user definition a library
||| instance serves (`Dictionaries.chooser`).
export
request : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          FC -> String -> Name -> List PKind -> Core FnId
request fc owner n kinds = do
  inst <- MkFnId <$> instanceName n (map staticOf kinds)
  base <- nameKey <$> toFullNames n
  st <- get TState
  unless (contains inst st.seen) $ do
    checkRecursion n
    let count = fromMaybe 0 (lookup base st.perName)
    when (count >= instanceBudget) $
      reject fc owner CompileBudget ("more than " ++ show instanceBudget ++ " instances of " ++ base)
    update TState { seen $= insert inst
                  , perName $= insert base (S count)
                  , requesters $= insert inst (n, st.current)
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
           reject fc owner RuntimeClosure ("an implementation chosen at runtime: " ++ showTT val)
         (rest, res) <- classify fc owner k !(normaliseClosed (subst val sc)) vals'
         pure (DictParam val :: rest, res)
       else do
         when !(erasedOutsideIndices owner a') $
           reject fc owner ValueType ("a parameter type that depends on another argument: " ++ showTT !(toFullNames a'))
         t <- coreType fc owner ValueType a'
         -- The rest of the type may depend on the parameter's value
         -- (`treeDelete : (n : Nat) -> ... -> Either (Tree n k v o) (delType n k v o)`
         -- in Data.SortedMap, where `delType` reduces on the constructors of
         -- `n`). Then the argument's shape, the constructors it is built
         -- with as written, everything else erased (`S _`), stands for the
         -- parameter in the type and keys the instance, so that the type
         -- reduces at each one as it does at each call. The shape is read
         -- off the argument, never computed: a runtime argument is any
         -- computation, which the compiler must not run. An argument with
         -- no constructor at its head has no shape, and a parameter the
         -- type does not mention keys nothing, so a function on naturals has
         -- one instance.
         let (v, vals') = nextStatic vals
         shape <- if isNothing (shrink sc (Drop Refl))
                     then maybe (pure Nothing) (\arg => skeleton <$> arg.written) v
                     else pure Nothing
         let value = fromMaybe (Erased bfc Placeholder) shape
         (rest, res) <- classify fc owner k !(normaliseClosed (subst value sc)) vals'
         pure (ValueParam (Held (useOf rig) t) shape :: rest, res)
classify fc owner (S k) ty vals = do
  ty' <- normaliseClosed ty
  case ty' of
    Bind {} => classify fc owner (S k) ty' vals
    _ => internal fc "more arguments than the type has binders"
