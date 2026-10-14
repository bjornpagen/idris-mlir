||| The nodes on a cycle of a finite graph: which data instances are
||| recursive, and so boxes (`Term.Repr`). The program's call graph is
||| MLIR's (`idr-loop-breakers`, `idr-effects`).
module IdrisMLIR.Graph

import Control.Monad.Identity
import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet

%default total

||| Tarjan's search for the strongly connected components: each node met
||| gets a number in the order met, and the least number of one still on
||| the stack that it reaches. Each node and edge is visited once, so the
||| search grows with the graph, where comparing every node with every
||| other would grow with its square, and the program has thousands of data
||| instances.
record Search k where
  constructor MkSearch
  next : Nat
  number : SortedMap k Nat
  low : SortedMap k Nat
  stack : List k
  onStack : SortedSet k
  found : List (List k)

mutual
  ||| Visits a node not visited yet: its component is found once every node
  ||| it reaches is.
  covering
  visit : Ord k => (k -> List k) -> SortedSet k -> k -> Search k -> Search k
  visit next nodes v s0 =
    let s1 = { next $= S, number $= insert v s0.next, low $= insert v s0.next
             , stack $= (v ::), onStack $= insert v } s0
        s2 = successors next nodes v (filter (`contains` nodes) (next v)) s1
    in if lookup v s2.low /= lookup v s2.number then s2 else
         let (members, rest) = break (== v) s2.stack
         in { stack := drop 1 rest
            , onStack $= \on => foldl (flip delete) on (v :: members)
            , found $= ((v :: members) ::) } s2

  covering
  successors : Ord k => (k -> List k) -> SortedSet k -> k -> List k -> Search k -> Search k
  successors next nodes v [] s = s
  successors next nodes v (w :: ws) s =
    let s' = case lookup w s.number of
               Just n => if contains w s.onStack then lower n s else s
               Nothing => let after = visit next nodes w s in
                          maybe after (\n => lower n after) (lookup w after.low)
    in successors next nodes v ws s'
    where
      lower : Nat -> Search k -> Search k
      lower n st = { low $= \m => insert v (min n (fromMaybe n (lookup v m))) m } st

||| The nodes on a cycle of the graph on `nodes` whose edges are `next`
||| (edges to other nodes are ignored): those in a component of two or more
||| nodes, or with an edge to themselves.
export covering
cyclic : Ord k => (k -> List k) -> List k -> SortedSet k
cyclic next nodes =
  let set = SortedSet.fromList nodes
      start = MkSearch 0 empty empty [] empty []
      searched = foldl (\s, n => if isJust (lookup n s.number) then s else visit next set n s) start nodes
  in foldl (\acc, c => foldl (flip insert) acc (onCycle c)) empty searched.found
  where
    onCycle : List k -> List k
    onCycle [n] = if elem n (next n) then [n] else []
    onCycle c = c
