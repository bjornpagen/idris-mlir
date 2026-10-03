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
import Core.Env
import Core.Normalise
import Core.TT
import Libraries.Data.WithDefault

import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Rule

import Data.List
import Data.SortedMap
import Data.SortedSet
import Data.String

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

||| The definitions a type mentions.
definitionsIn : TT vars -> List Name
definitionsIn (Ref _ Func n) = [n]
definitionsIn (Bind _ _ b sc) = definitionsIn (binderType b) ++ definitionsIn sc
definitionsIn (App _ f a) = definitionsIn f ++ definitionsIn a
definitionsIn (TDelayed _ _ t) = definitionsIn t
definitionsIn _ = []

||| Why an implementation may be one of two for one type: the type it is
||| declared for mentions a definition Idris keeps opaque where the
||| program is (`Meters`, which its module exports without its body,
||| `Meters = Int`), so the types it builds are types of their own there.
||| The compiler unfolds every definition (`normaliseAll`), and so makes
||| one data instance of two such types and gives it one implementation.
||| Data keyed by the type Idris sees would not be sound: inside the
||| defining module the two types are one, and a value of one can leave it
||| as the other, holding the first one's implementation.
opaqueFor : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Core (Maybe String)
opaqueFor impl = case spine impl [] of
  (Ref _ _ n, _) => do
    defs <- get Ctxt
    Just def <- lookupCtxtExact n (gamma defs)
      | Nothing => pure Nothing
    -- What Idris itself does not reduce here, a definition public to the
    -- program aside, which is only stuck.
    seen <- toFullNames !(normalise defs Env.Nil (type def))
    opaque <- hidden (nub (definitionsIn seen))
    case opaque of
      [] => pure Nothing
      _ => pure (Just (show !(toFullNames n) ++ " implements " ++ !(showTT seen) ++ ", where " ++
                       joinBy ", " (map show opaque) ++ " is opaque to the program (exported without " ++
                       "its definition) and unfolded by this compiler: two types to Idris are one " ++
                       "type here, whose data holds one implementation"))
  _ => pure Nothing
  where
    hidden : List Name -> Core (List Name)
    hidden [] = pure []
    hidden (x :: xs) = do
      defs <- get Ctxt
      rest <- hidden xs
      Just def <- lookupCtxtExact x (gamma defs)
        | Nothing => pure rest
      pure (if collapseDefault (visibility def) == Public then rest else x :: rest)

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
      why <- catMaybes <$> traverse opaqueFor [d.impl, impl']
      reject site owner DictionaryField
             (show cid.dataId ++ "::" ++ show cid ++ " holds two implementations of " ++ !(showTT ty) ++
              ": " ++ !(showTT d.impl) ++ ", chosen in " ++ d.chooser ++ ", and " ++ !(showTT impl') ++
              ", chosen in " ++ by ++ concatMap ("; " ++) why)
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
