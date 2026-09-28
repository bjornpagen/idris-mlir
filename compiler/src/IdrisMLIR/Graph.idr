||| Strongly connected components of a finite graph, in a deterministic order
||| (FE-DET-1). Two users: which data instances are recursive (a box,
||| `Term.Repr`) and the loop breakers of the call graph (OPT-PIPE-3).
module IdrisMLIR.Graph

import Data.List
import Data.SortedMap
import Data.SortedSet

%default total

||| The nodes reachable from `n` in one or more steps, within `set`.
reach : Ord k => Nat -> (k -> List k) -> SortedSet k -> k -> SortedSet k
reach fuel next set n = walk fuel empty (step n)
  where
    step : k -> List k
    step m = filter (`contains` set) (next m)
    walk : Nat -> SortedSet k -> List k -> SortedSet k
    walk Z seen _ = seen
    walk _ seen [] = seen
    walk (S f) seen (m :: ms) =
      if contains m seen then walk (S f) seen ms else walk f (insert m seen) (step m ++ ms)

||| The strongly connected components of the graph on `nodes` whose edges
||| are `next` (edges to other nodes are ignored). Each component lists its
||| nodes in the order of `nodes`, and the components come in the order of
||| their first node.
export
components : Ord k => (k -> List k) -> List k -> List (List k)
components next nodes =
  let set = SortedSet.fromList nodes
      fuel = length nodes
      reaches = the (SortedMap k (SortedSet k)) (fromList [(n, reach fuel next set n) | n <- nodes])
      linked = \a, b => maybe False (contains b) (lookup a reaches)
  in split linked fuel nodes
  where
    split : (k -> k -> Bool) -> Nat -> List k -> List (List k)
    split r Z _ = []
    split r _ [] = []
    split r (S f) (n :: rest) =
      let (same, other) = partition (\m => r n m && r m n) rest
      in (n :: same) :: split r f other

||| The nodes on a cycle: in a component of two or more nodes, or with an
||| edge to themselves.
export
cyclic : Ord k => (k -> List k) -> List k -> SortedSet k
cyclic next nodes = SortedSet.fromList (concatMap onCycle (components next nodes))
  where
    onCycle : List k -> List k
    onCycle [n] = if elem n (next n) then [n] else []
    onCycle c = c
