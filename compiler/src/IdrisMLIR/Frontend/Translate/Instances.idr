||| Function instances: requesting one, and classifying a callee's
||| parameters as compile-time values (types and implementations, which key
||| the instance), erased ones, and runtime ones.
module IdrisMLIR.Frontend.Translate.Instances

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
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

||| Requests a function instance and returns its name. Polymorphic recursion
||| would request ever larger instances of one definition.
export
request : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          FC -> String -> Name -> List (Maybe ClosedTerm) -> Core FnId
request fc owner n statics = do
  inst <- MkFnId <$> instanceName n statics
  base <- nameKey <$> toFullNames n
  st <- get TState
  unless (contains inst st.seen) $ do
    -- Growth is a homeomorphic embedding of the static arguments (here, of
    -- their text): the new instance's contain the old one's and are larger.
    -- Another implementation of the same method is not growth.
    let args = snd (break (== '[') inst.name)
    let strip = \s => pack (filter (\c => c /= '[' && c /= ']') (unpack s))
    when (any (\(b, old) => b == base && length old < length args && isInfixOf (strip old) args) st.current) $
      reject fc owner Polymorphism
             ("polymorphic recursion: " ++ base ++ " calls itself at a larger type (" ++ inst.name ++ ")")
    let count = fromMaybe 0 (lookup base st.perName)
    when (count >= 64) $
      reject fc owner Polymorphism ("more than 64 instances of " ++ base)
    put TState ({ seen $= insert inst
                , perName $= insert base (S count)
                , queue $= (++ [MkPending n inst statics ((base, args) :: st.current)]) } st)
  pure inst

||| Parameter classification after instantiation. A type parameter and an
||| implementation (an auto-implicit argument, such as an interface
||| constraint) are compile-time values: they key the instance
||| and are erased at runtime.
public export
data PKind = TypeParam ClosedTerm | DictParam ClosedTerm | ErasedParam | RuntimeParam Ty

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

export
known : ClosedTerm -> ArgValue
known t = MkArgValue (pure t) (pure t) True

||| The arguments of a call by position: `Nothing` for a runtime argument of
||| an instance.
public export
ArgValues : Type
ArgValues = List (Maybe ArgValue)

nextStatic : ArgValues -> (Maybe ArgValue, ArgValues)
nextStatic (v :: vs) = (v, vs)
nextStatic [] = (Nothing, [])

skip : ArgValues -> ArgValues
skip = Data.List.drop 1

export
isAuto : PiInfo t -> Bool
isAuto AutoImplicit = True
isAuto _ = False

||| Is a type an interface, whatever binds a value of it? Idris declares an
||| interface's record with unique search (`uniqueAuto`), and passes a
||| function's constraints to its `where` functions and its case and with
||| blocks as explicit arguments.
interfaceType : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core Bool
interfaceType ty = case spine ty [] of
  (Ref _ (TyCon _) n, _) => do
    defs <- get Ctxt
    Just def <- lookupCtxtExact n (gamma defs)
      | Nothing => pure False
    case definition def of
      TCon _ _ _ flags _ _ _ => pure flags.uniqueAuto
      _ => pure False
  _ => pure False

||| Walks a callee's type over its arguments: which are type parameters or
||| implementations, which are erased, which are runtime (and their types).
export
classify : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           FC -> String -> Nat -> ClosedTerm -> ArgValues ->
           Core (List (Quantity, PKind), ClosedTerm)
classify fc owner Z ty _ = pure ([], ty)
classify fc owner (S k) (Bind bfc _ (Pi _ rig pinfo a) sc) vals = do
  a' <- normaliseClosed a
  if isErased rig && isTypeLike a'
     then do
       let (Just v, vals') = nextStatic vals
         | _ => reject fc owner StaticArgument "a type argument that is not known statically"
       val <- v.normalised
       (rest, res) <- classify fc owner k !(normaliseClosed (subst val sc)) vals'
       pure ((Q0, TypeParam val) :: rest, res)
     else if isErased rig
       then do
         (rest, res) <- classify fc owner k (subst (Erased bfc Placeholder) sc) (skip vals)
         pure ((Q0, ErasedParam) :: rest, res)
     else if isAuto pinfo || maybe False (.dictionary) (fst (nextStatic vals)) || !(interfaceType a')
       then do
         let (Just v, vals') = nextStatic vals
           | _ => reject fc owner StaticArgument "an implementation that is not known statically"
         val <- v.written
         when (runtimeDependent val) $
           reject fc owner RuntimeClosure ("an implementation chosen at runtime: " ++ showTT val)
         (rest, res) <- classify fc owner k !(normaliseClosed (subst val sc)) vals'
         pure ((Q0, DictParam val) :: rest, res)
       else do
         when !(erasedOutsideIndices owner a') $
           reject fc owner ValueType "a parameter type that depends on another argument"
         t <- coreType fc owner ValueType a'
         (rest, res) <- classify fc owner k (subst (Erased bfc Placeholder) sc) (skip vals)
         pure ((quantity rig, RuntimeParam t) :: rest, res)
classify fc owner (S k) ty vals = do
  ty' <- normaliseClosed ty
  case ty' of
    Bind {} => classify fc owner (S k) ty' vals
    _ => internal fc "more arguments than the type has binders"
