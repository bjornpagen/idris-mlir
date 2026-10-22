-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The components of the call graph, found in the size-change graphs that
||| Idris's termination checker keeps for every definition (`sizeChange`),
||| and what each says of its loops. Every loop through a definition
||| terminates when the graphs of the calls in its component decrease some
||| argument each time round: its termination names the component, so that
||| a cycle a later pass makes through two components (a stored function, a
||| method's projection) is never read as one Idris proved.
||| Idris folds a case block's calls into its parent's graph, so the
||| definitions here are the ones Idris checks.
module IdrisMLIR.Frontend.Translate.Recursion

import Core.Context
import Core.Core
import Core.TT
import Core.Termination.SizeChange
import Idris.Host
import Libraries.Data.SparseMatrix

import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Ids
import IdrisMLIR.Term

import Data.List1

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

||| A definition read as a node (`Defined`), with its calls, every name
||| full as the frozen context names it.
memberOf : Frozen -> Defined -> Member
memberOf fz d =
  MkMember (fullNameIn fz (fullname d.def)) (addressOf d.placement)
           (map (\call => { fnCall := fullNameIn fz call.fnCall } call) (sizeChange d.def))

mutual
  ||| Visits a definition the walk has just entered: its component is found
  ||| once every definition it reaches is. `w0` is where the walk was once
  ||| it entered the definition, and every definition it enters below
  ||| leaves fewer than `w0` to enter (`Walk`), which is why the search
  ||| ends.
  visit : Read -> SortedMap Address Termination -> Member ->
          (w0 : Walked) -> (0 _ : SizeAccessible w0) -> Search -> Core (Search, Subset Walked (\w' => NoMore w' w0))
  visit r done v w0 acc s0 = do
    let key = v.address
    let s1 = { next $= S, number $= insert key s0.next, low $= insert key s0.next
             , stack $= (v ::), onStack $= insert key } s0
    (s2, reached) <- successors r done key w0 acc w0 (noMore w0) (map (.fnCall) v.calls) s1
    if lookup key s2.low /= lookup key s2.number then pure (s2, reached) else do
      let (members, rest) = break (\m => m.address == key) s2.stack
      pure ({ stack := drop 1 rest
            , onStack $= \on => foldl (flip delete) on (key :: map (.address) members)
            , found $= ((v :: members) ::) } s2, reached)

  ||| The calls of the definition at `key`, in order: a callee the walk has
  ||| not entered is visited, and one on the stack lowers the definition's
  ||| link. A callee is read as the translation reads it (`definedIn`); a
  ||| name no definition has is no callee.
  successors : Read -> SortedMap Address Termination -> Address ->
               (w0 : Walked) -> (0 _ : SizeAccessible w0) -> (w : Walked) -> (0 _ : NoMore w w0) ->
               List Name -> Search -> Core (Search, Subset Walked (\w' => NoMore w' w))
  successors r done key w0 acc w p [] s = pure (s, Element w (noMore w))
  successors r done key w0 acc@(Access rec) w p (x :: xs) s = do
    Just d <- definedIn r x
      | Nothing => successors r done key w0 acc w p xs s
    let xkey = addressOf d.placement
    let False = isJust (lookup xkey done)
      | True => successors r done key w0 acc w p xs s
    -- Entered already: met before in this search.
    let Just (Element w1 q) = enter d.placement w
      | Nothing => successors r done key w0 acc w p xs (maybe s (\n => if contains xkey s.onStack then lower key n s else s)
                                                           (lookup xkey s.number))
    (after, Element w2 q2) <- visit r done (memberOf r.frozen d) w1 (rec w1 (fewerThen q p)) s
    let s' = maybe after (\n => lower key n after) (lookup xkey after.low)
    (s'', Element w3 q3) <- successors r done key w0 acc w2 (thenNoMore q2 (thenNoMore (fewer q) p)) xs s'
    pure (s'', Element w3 (thenNoMore q3 (thenNoMore q2 (fewer q))))
    where
      lower : Address -> Nat -> Search -> Search
      lower k n st = { low $= \m => insert k (min n (fromMaybe n (lookup k m))) m } st

||| The components checked so far: the next one's number, and what Idris
||| proved of each definition's loops, by address.
record Checked where
  constructor MkChecked
  nextComponent : Nat
  proved : SortedMap Address Termination

||| Checks one component, numbered as it is found: each definition whose
||| loops Idris's graphs prove to end terminates in it; any other may
||| diverge, by its own name. Whether its recursion asks for ever more
||| instances is the growth check's to say (`Growth`), on the program's
||| static positions.
checkComponent : Read -> Checked -> List Member -> Checked
checkComponent r checked members =
  let names = gamma (defsOf r.frozen)
      inside = the (SortedSet Address) (fromList (map (.address) members))
      within = \n => maybe False (\a => contains a inside) (definitionAddress names n)
      calls = [ (caller.name, call) | caller <- members, call <- caller.calls, within call.fnCall ]
      verdicts = loopsTerminate calls (map (.name) members)
      component = MkComponentId checked.nextComponent
      termination : Name -> Loops -> Termination
      termination n Decreasing = Terminates component
      termination n (Endless _) = MayDiverge (shown (show n) ::: [])
  in MkChecked (S checked.nextComponent)
               (foldl (\m, (n, v) => maybe m (\a => insert a (termination n v) m) (definitionAddress names n))
                      checked.proved verdicts)

||| What Idris proved of the loops of every definition read from what
||| `main` reaches, by address: the component of each, found from each in
||| the order the table holds them, once, and numbered as found. What a
||| definition's loops are follows from the definitions alone, so every
||| one is found where the program is read, before any instance is
||| requested.
export
loopsOf : Read -> Core (SortedMap Address Termination)
loopsOf r = (.proved) <$> foldlM from (MkChecked 0 empty) (values r.definitions)
  where
    from : Checked -> Defined -> Core Checked
    from checked d =
      if isJust (lookup (addressOf d.placement) checked.proved) then pure checked else do
        let w = startAt d.placement
        (result, _) <- visit r checked.proved (memberOf r.frozen d) w (sizeAccessible w) (MkSearch 0 empty empty [] empty [])
        pure (foldl (checkComponent r) checked result.found)
