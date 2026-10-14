||| The components of the call graph, found in the size-change graphs that
||| Idris's termination checker keeps for every definition (`sizeChange`),
||| and what each says of its recursion. A call in a recursive component
||| that gives a callee's type or implementation argument anything but one
||| of the caller's own arguments, unchanged, would ask for instances at
||| ever larger types: polymorphic recursion. And every loop through a
||| definition terminates when the graphs of the calls in its component
||| decrease some argument each time round, which is what the definition's
||| `terminating` fact says (`Facts`): a loop never leaves its component.
||| Idris folds a case block's calls into its parent's graph, so the
||| definitions here are the ones Idris checks.
module IdrisMLIR.Frontend.Translate.Recursion

import Core.Context
import Core.Core
import Core.TT
import Core.Termination.SizeChange
import Libraries.Data.SparseMatrix

import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Prof
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Graph
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

||| A definition as a node, with its calls to definitions that exist.
node : {auto c : Ref Ctxt Defs} -> Name -> Core (Maybe Node)
node n = do
  count "recursion.node"
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => pure Nothing
  full <- toFullNames (fullname def)
  calls <- traverse (\call => pure ({ fnCall := !(toFullNames call.fnCall) } call)) (sizeChange def)
  pure (Just (MkNode full (location def) calls))

||| The call graph as Idris's termination checker keeps it: a definition is
||| a node, known by `nameKey`, and each of its calls an edge, but for one
||| to a definition whose component was checked before (`done`). A
||| definition is looked up only when the search first meets it, and a name
||| with none is no node.
callGraph : {auto c : Ref Ctxt Defs} -> SortedMap String Bool -> Graph Core String Node
callGraph done = MkGraph (nameKey . (.name)) edges
  where
    edges : Node -> List (String, Core (Maybe Node))
    edges v = filter (\(callee, _) => not (isJust (lookup callee done)))
                     (map (\call => (nameKey call.fnCall, node call.fnCall)) v.calls)

||| The positions of a definition's type or implementation arguments, which
||| key its instances.
staticPositions : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Name -> Core (List Nat)
staticPositions n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => pure []
  go 0 (type def)
  where
    go : Nat -> TT vars -> Core (List Nat)
    go i (Bind _ _ (Pi _ rig _ a) sc) = do
      -- As `classify` decides: an erased argument is a compile-time value
      -- only when it is a type, any other only when it is an
      -- implementation.
      static <- if isErased rig then pure (isTypeLike a) else dictionaryBinder rig a
      rest <- go (S i) sc
      pure (if static then i :: rest else rest)
    go _ _ = pure []

||| Is argument `i` of a call one of the caller's own, unchanged?
same : Nat -> SCCall -> Bool
same i call = case Data.List.lookup i call.fnArgs of
  Just row => any (\(_, change) => change == Same) (forget row)
  Nothing => False

||| Checks one component: whether every loop through each of its
||| definitions terminates, and, for a recursive one, that it passes on a
||| type or an implementation only as the caller got it. Each call that
||| does not is rejected, and the whole component is refused: its
||| instances would never end, so the translation leaves them out.
checkComponent : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> List (String, Node) -> Core ()
checkComponent members = do
  let inside = the (SortedSet String) (fromList (map fst members))
  let callers = map snd members
  let calls = [ (caller.name, call.fnCall, call.fnArgs)
              | caller <- callers, call <- caller.calls, contains (nameKey call.fnCall) inside ]
  let verdicts = loopsTerminate calls (map (.name) callers)
  update TState { loops $= \m => foldl (\m', (n, v) => insert (nameKey n) v m') m verdicts }
  let recursive = case members of
                    [(one, caller)] => any (\call => nameKey call.fnCall == one) caller.calls
                    _ => True
  when recursive $ do
    wrong <- for callers $ \caller =>
      for (filter (\call => contains (nameKey call.fnCall) inside) caller.calls) $ \call => do
        positions <- staticPositions call.fnCall
        if all (\i => same i call) positions then pure False else do
          noted $ reject caller.location (show caller.name) Polymorphism
                    ("polymorphic recursion: " ++ show caller.name ++ " calls " ++ show call.fnCall ++
                     " with a type or an implementation that is not its own, unchanged")
          pure True
    when (any (any id) wrong) $
      update TState { refused $= \r => foldl (\r', caller => insert (nameKey caller.name) r') r callers }

||| Checks the component of a definition, and of every definition it
||| reaches, once each.
export
checkRecursion : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Name -> Core ()
checkRecursion n = do
  st <- get TState
  full <- toFullNames n
  unless (isJust (lookup (nameKey full) st.loops)) $ do
    Just start <- node full
      | Nothing => pure ()
    found <- components @{CORE} (callGraph st.loops) [start]
    for_ found checkComponent
