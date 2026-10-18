-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The components of the call graph, found in the size-change graphs that
||| Idris's termination checker keeps for every definition (`sizeChange`),
||| and what each says of its loops. Every loop through a definition
||| terminates when the graphs of the calls in its component decrease some
||| argument each time round, which is what the definition's
||| `terminating` fact says (`Facts`): a loop never leaves its component.
||| Idris folds a case block's calls into its parent's graph, so the
||| definitions here are the ones Idris checks.
module IdrisMLIR.Frontend.Translate.Recursion

import Core.Context
import Core.Core
import Core.TT
import Core.Termination.SizeChange
import Libraries.Data.SparseMatrix

import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Proof.Requests

import Control.WellFounded
import Data.DPair
import Data.List
import Data.Nat
import Data.SortedMap
import Data.SortedSet

%default total

||| A definition of the graph: its full name, its address, which the
||| search keys it by, and its calls, each to a definition, with how each
||| argument of the callee relates to the caller's (row: the callee's
||| argument; column: the caller's).
record Member where
  constructor MkMember
  name : Name
  address : Address
  calls : List SCCall

||| Tarjan's search for the components, from one definition: each
||| definition met gets a number in the order met, and the least number of
||| one still on the stack that it reaches, each definition by its address.
||| The stack and the components found hold the definitions themselves.
record Search where
  constructor MkSearch
  next : Nat
  number : SortedMap Address Nat
  low : SortedMap Address Nat
  stack : List Member
  onStack : SortedSet Address
  found : List (List Member)

||| A definition as a node, with its calls to definitions that exist.
memberOf : {auto c : Ref Ctxt Defs} -> Name -> Core (Maybe Member)
memberOf n = do
  defs <- get Ctxt
  Just def <- lookupCtxtExact n (gamma defs)
    | Nothing => pure Nothing
  full <- toFullNames (fullname def)
  let Just address = definitionAddress (gamma defs) full
    | Nothing => pure Nothing
  calls <- traverse (\call => pure ({ fnCall := !(toFullNames call.fnCall) } call)) (sizeChange def)
  pure (Just (MkMember full address calls))

mutual
  ||| Visits a definition the walk has just entered: its component is found
  ||| once every definition it reaches is. `w0` is where the walk was once
  ||| it entered the definition, and every definition it enters below
  ||| leaves fewer than `w0` to enter (`Walk`), which is why the search
  ||| ends.
  visit : {auto c : Ref Ctxt Defs} -> SortedMap Address Bool -> Member ->
          (w0 : Walked) -> (0 _ : SizeAccessible w0) -> Search -> Core (Search, Subset Walked (\w' => NoMore w' w0))
  visit done v w0 acc s0 = do
    let key = v.address
    let s1 = { next $= S, number $= insert key s0.next, low $= insert key s0.next
             , stack $= (v ::), onStack $= insert key } s0
    (s2, reached) <- successors done key w0 acc w0 (noMore w0) (map (.fnCall) v.calls) s1
    if lookup key s2.low /= lookup key s2.number then pure (s2, reached) else do
      let (members, rest) = break (\m => m.address == key) s2.stack
      pure ({ stack := drop 1 rest
            , onStack $= \on => foldl (flip delete) on (key :: map (.address) members)
            , found $= ((v :: members) ::) } s2, reached)

  ||| The calls of the definition at `key`, in order: a callee the walk has
  ||| not entered is visited, and one on the stack lowers the definition's
  ||| link.
  successors : {auto c : Ref Ctxt Defs} -> SortedMap Address Bool -> Address ->
               (w0 : Walked) -> (0 _ : SizeAccessible w0) -> (w : Walked) -> (0 _ : NoMore w w0) ->
               List Name -> Search -> Core (Search, Subset Walked (\w' => NoMore w' w))
  successors done key w0 acc w p [] s = pure (s, Element w (noMore w))
  successors done key w0 acc@(Access rec) w p (x :: xs) s = do
    defs <- get Ctxt
    let Just xkey = definitionAddress (gamma defs) x
      | Nothing => successors done key w0 acc w p xs s
    let False = isJust (lookup xkey done)
      | True => successors done key w0 acc w p xs s
    let Just (Element w1 q) = enter (gamma defs) x w
      | Nothing => successors done key w0 acc w p xs (maybe s (\n => if contains xkey s.onStack then lower key n s else s)
                                                           (lookup xkey s.number))
    Just xn <- memberOf x
      | Nothing => do
          (s', Element w2 q2) <- successors done key w0 acc w1 (thenNoMore (fewer q) p) xs s
          pure (s', Element w2 (thenNoMore q2 (fewer q)))
    (after, Element w2 q2) <- visit done xn w1 (rec w1 (fewerThen q p)) s
    let s' = maybe after (\n => lower key n after) (lookup xkey after.low)
    (s'', Element w3 q3) <- successors done key w0 acc w2 (thenNoMore q2 (thenNoMore (fewer q) p)) xs s'
    pure (s'', Element w3 (thenNoMore q3 (thenNoMore q2 (fewer q))))
    where
      lower : Address -> Nat -> Search -> Search
      lower k n st = { low $= \m => insert k (min n (fromMaybe n (lookup k m))) m } st

||| Checks one component: whether every loop through each of its
||| definitions terminates, which its definitions' `terminating` fact says.
||| Whether its recursion asks for ever more instances is the growth
||| check's to say (`Growth`), on the program's static positions.
checkComponent : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> List Member -> Core ()
checkComponent members = do
  defs <- get Ctxt
  let inside = the (SortedSet Address) (fromList (map (.address) members))
  let within = \n => maybe False (\a => contains a inside) (definitionAddress (gamma defs) n)
  let calls = [ (caller.name, call.fnCall, call.fnArgs)
              | caller <- members, call <- caller.calls, within call.fnCall ]
  let verdicts = loopsTerminate calls (map (.name) members)
  update TState { loops $= \m => foldl (\m', (n, v) => maybe m' (\a => insert a v m') (definitionAddress (gamma defs) n))
                                        m verdicts }

||| Checks the component of a definition, and of every definition it
||| reaches, once each.
export
checkRecursion : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Name -> Core ()
checkRecursion n = do
  st <- get TState
  full <- toFullNames n
  defs <- get Ctxt
  let Just key = definitionAddress (gamma defs) full
    | Nothing => pure ()
  unless (isJust (lookup key st.loops)) $ do
    let Just (Element w _) = enter (gamma defs) full start
      | Nothing => pure ()
    Just member <- memberOf full
      | Nothing => pure ()
    (result, _) <- visit st.loops member w (sizeAccessible w) (MkSearch 0 empty empty [] empty [])
    for_ result.found checkComponent
