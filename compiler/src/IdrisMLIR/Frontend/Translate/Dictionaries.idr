||| Dictionaries held in constructor fields.
|||
||| An implementation is a compile-time value: a function's interface
||| argument keys its instances and is erased at runtime (`Instances`). A
||| constructor can hold one too (`Empty : Ord k => SortedDMap k v`, where
||| `Data.SortedMap` keeps the ordering of its keys), and its type does not
||| say which: `SortedDMap String v` is the type of maps built with any
||| `Ord String`. Were the field a runtime value, every method called on it
||| would be a call of a closure chosen at runtime, which the match on the
||| map could not specialize. So a dictionary field is a compile-time value
||| of the data instance, as a type argument is: it is erased from the
||| representation, and the implementation it holds is the one every
||| construction site of that constructor, in the whole program, gives it.
||| A match binds the field to that implementation, and the methods called
||| on it specialize as they do for an interface argument of a function. A
||| program whose construction sites give one constructor two
||| implementations is rejected, naming both; the field would have to hold
||| one of two at runtime.
|||
||| The translation is demand-driven, so a match on a constructor can come
||| before any construction site of it. The match then takes the field as
||| never built and its alternative as unreachable, and a construction site
||| met later in the same pass voids the pass: the translation starts over,
||| knowing the implementation. A pass that ends without such a site has
||| seen every construction site the program can reach: the first value of a
||| constructor is built on a path through no match on that constructor, and
||| that path was translated. Each restart fixes one more field, so the
||| passes are as few as the dictionary fields built after they were matched.
module IdrisMLIR.Frontend.Translate.Dictionaries

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Rule

import Data.SortedMap
import Data.SortedSet

%default covering

||| The user definition the instance being translated serves: itself, or
||| the nearest one up the chain of requests through the library's
||| instances. A construction site is usually a library's
||| (`Data.SortedMap.empty`), and the terms Idris keeps carry no locations,
||| so this is where the program's choice of an implementation is reported.
chooser : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Core (Maybe (Name, FC))
chooser = do
  st <- get TState
  go st.current
  where
    go : Maybe FnId -> Core (Maybe (Name, FC))
    go Nothing = pure Nothing
    go (Just inst) = do
      st <- get TState
      let Just r = lookup inst st.requesters
        | Nothing => pure Nothing
      defs <- get Ctxt
      Just def <- lookupCtxtExact r.name (gamma defs)
        | Nothing => go r.parent
      loc <- toLoc (location def)
      case loc.origin of
        User => pure (Just (fullname def, location def))
        _ => go r.parent

||| A construction site gives field `i` of a constructor the implementation
||| `impl`: the one the field holds, if no site gave another. Two sites of
||| one constructor agree when their implementations are one, by what each
||| reduces to (`implementationOf`), not as written: Data.SortedMap's
||| `Monoid` takes the map's `Ord k` as the first of a pair of constraints,
||| where `fromList`'s caller names it directly.
export
recordDictionary : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                   FC -> String -> ConId -> ClosedTerm -> Nat -> ClosedTerm -> Core ()
recordDictionary fc owner cid ty i impl = do
  impl' <- toFullNames !(implementationOf 64 impl)
  chosen <- chooser
  let site = maybe fc snd chosen
  let by = maybe owner (show . fst) chosen
  st <- get TState
  case lookup (cid, i) st.dicts of
    Just d => unless (d.impl == impl') $ do
      ty' <- toFullNames ty
      reject site owner DictionaryField
             (show cid.dataId ++ "::" ++ show cid ++ " holds two implementations of " ++ showTT ty' ++
              ": " ++ showTT d.impl ++ ", chosen in " ++ d.chooser ++ ", and " ++ showTT impl' ++
              ", chosen in " ++ by)
    Nothing =>
      update TState { dicts $= insert (cid, i) (MkDictionary impl' by site)
                    , restart $= (|| contains (cid, i) st.assumed) }

||| The implementation field `i` of a constructor holds, where a match
||| binds it; `Nothing` when no construction site has given one, which the
||| match takes as never built.
export
dictionaryOf : {auto s : Ref TState TS} -> ConId -> Nat -> Core (Maybe ClosedTerm)
dictionaryOf cid i = do
  st <- get TState
  case lookup (cid, i) st.dicts of
    Just d => pure (Just d.impl)
    Nothing => do
      update TState { assumed $= insert (cid, i) }
      pure Nothing
