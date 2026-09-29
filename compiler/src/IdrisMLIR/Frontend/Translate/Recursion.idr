||| Polymorphic recursion, found in the size-change graphs that Idris's
||| termination checker keeps for every definition (`sizeChange`). A call
||| in a recursive component of the call graph that gives a callee's type
||| or implementation argument anything but one of the caller's own
||| arguments, unchanged, would ask for instances at ever larger types.
||| Idris folds a case block's calls into its parent's graph, so the
||| definitions here are the ones Idris checks.
module IdrisMLIR.Frontend.Translate.Recursion

import Core.Context
import Core.Core
import Core.TT
import Libraries.Data.SparseMatrix

import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Rule

import Data.List
import Data.List1
import Data.SortedMap
import Data.SortedSet

%default covering

||| A definition of the graph: its full name, where it is, and its calls,
||| each to a definition, with how each argument of the callee relates to
||| the caller's (row: the callee's argument; column: the caller's).
record Node where
  constructor MkNode
  name : Name
  location : FC
  calls : List SCCall

||| Tarjan's search for the components, from one definition: each
||| definition met gets a number in the order met, and the least number of
||| one still on the stack that it reaches.
record Search where
  constructor MkSearch
  next : Nat
  number : SortedMap String Nat
  low : SortedMap String Nat
  stack : List String
  onStack : SortedSet String
  nodes : SortedMap String Node
  found : List (List String)

||| A definition as a node, with its calls to definitions that exist.
node : {auto c : Ref Ctxt Defs} -> Name -> Core (Maybe Node)
node n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => pure Nothing
  full <- toFullNames (fullname def)
  calls <- traverse (\call => pure ({ fnCall := !(toFullNames call.fnCall) } call)) (sizeChange def)
  pure (Just (MkNode full (location def) calls))

mutual
  ||| Visits a definition not visited yet: its component is found once
  ||| every definition it reaches is.
  visit : {auto c : Ref Ctxt Defs} -> SortedSet String -> Node -> Search -> Core Search
  visit done v s0 = do
    let key = nameKey v.name
    let s1 = { next $= S, number $= insert key s0.next, low $= insert key s0.next
             , stack $= (key ::), onStack $= insert key, nodes $= insert key v } s0
    s2 <- successors done key (map (.fnCall) v.calls) s1
    if lookup key s2.low /= lookup key s2.number then pure s2 else do
      let (members, rest) = break (== key) s2.stack
      pure ({ stack := drop 1 rest
            , onStack $= \on => foldl (flip delete) on (key :: members)
            , found $= ((key :: members) ::) } s2)

  successors : {auto c : Ref Ctxt Defs} -> SortedSet String -> String -> List Name -> Search ->
               Core Search
  successors done key [] s = pure s
  successors done key (w :: ws) s = do
    let wkey = nameKey w
    s' <- if contains wkey done then pure s else
            case lookup wkey s.number of
              Just n => pure (if contains wkey s.onStack then lower key n s else s)
              Nothing => do
                Just wn <- node w
                  | Nothing => pure s
                after <- visit done wn s
                pure (maybe after (\n => lower key n after) (lookup wkey after.low))
    successors done key ws s'
    where
      lower : String -> Nat -> Search -> Search
      lower k n st = { low $= \m => insert k (min n (fromMaybe n (lookup k m))) m } st

||| The positions of a definition's type or implementation arguments, which
||| key its instances.
staticPositions : {auto c : Ref Ctxt Defs} -> Name -> Core (List Nat)
staticPositions n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => pure []
  go 0 (type def)
  where
    go : Nat -> TT vars -> Core (List Nat)
    go i (Bind _ _ (Pi _ rig pinfo a) sc) = do
      -- As `classify` decides: an erased argument is a compile-time value
      -- only when it is a type.
      static <- if isErased rig then pure (isTypeLike a)
                else if isAuto pinfo then pure True else interfaceType a
      rest <- go (S i) sc
      pure (if static then i :: rest else rest)
    go _ _ = pure []

||| Is argument `i` of a call one of the caller's own, unchanged?
same : Nat -> SCCall -> Bool
same i call = case Data.List.lookup i call.fnArgs of
  Just row => any (\(_, change) => change == Same) (forget row)
  Nothing => False

||| Checks one component: a recursive one may pass on a type or an
||| implementation only as the caller got it.
checkComponent : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 SortedMap String Node -> List String -> Core ()
checkComponent nodes members = do
  let inside = the (SortedSet String) (fromList members)
  let recursive = case members of
                    [one] => maybe False (any (\call => nameKey call.fnCall == one) . (.calls)) (lookup one nodes)
                    _ => True
  when recursive $
    for_ (mapMaybe (\m => lookup m nodes) members) $ \caller =>
      for_ (filter (\call => contains (nameKey call.fnCall) inside) caller.calls) $ \call => do
        positions <- staticPositions call.fnCall
        unless (all (\i => same i call) positions) $
          reject caller.location (show caller.name) Polymorphism
                 ("polymorphic recursion: " ++ show caller.name ++ " calls " ++ show call.fnCall ++
                  " with a type or an implementation that is not its own, unchanged")

||| Checks the component of a definition, and of every definition it
||| reaches, once each.
export
checkRecursion : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Name -> Core ()
checkRecursion n = do
  st <- get TState
  full <- toFullNames n
  unless (contains (nameKey full) st.checked) $ do
    Just start <- node full
      | Nothing => pure ()
    result <- visit st.checked start (MkSearch 0 empty empty [] empty empty [])
    for_ result.found (checkComponent result.nodes)
    update TState { checked $= \done => foldl (flip insert) done (keys result.nodes) }
