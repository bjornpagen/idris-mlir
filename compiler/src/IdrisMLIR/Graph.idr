||| The strongly connected components of a finite graph, and the nodes on a
||| cycle: which data instances are recursive, and so boxes (`Term.Repr`),
||| and which definitions' loops are checked together (`Recursion`). The
||| program's call graph is MLIR's (`idr-loop-breakers`, `idr-effects`).
module IdrisMLIR.Graph

import Control.Monad.Identity
import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet

%default total

||| A graph as a search meets it, in `m`: each node is known by its key,
||| and each of its edges is the key of the node at its end with how to
||| find that node, which is done only when the search first meets it: the
||| definitions of a call graph are looked up one by one. An edge whose
||| node is not found (`Nothing`) is ignored.
public export
record Graph (m : Type -> Type) k a where
  constructor MkGraph
  key : a -> k
  edges : a -> List (k, m (Maybe a))

||| Tarjan's search: each node met gets a number in the order met, and the
||| least number of one still on the stack that it reaches. Each node and
||| edge is visited once, so the search grows with the graph, where
||| comparing every node with every other would grow with its square, and a
||| program has thousands of data instances and definitions.
record Search k a where
  constructor MkSearch
  next : Nat
  number : SortedMap k Nat
  low : SortedMap k Nat
  stack : List (k, a)
  onStack : SortedSet k
  found : List (List (k, a))

mutual
  ||| Visits a node not visited yet: its component is found once every node
  ||| it reaches is.
  covering
  visit : Monad m => Ord k => Graph m k a -> a -> Search k a -> m (Search k a)
  visit g v s0 = do
    let kv = g.key v
    let s1 = { next $= S, number $= insert kv s0.next, low $= insert kv s0.next
             , stack $= ((kv, v) ::), onStack $= insert kv } s0
    s2 <- successors g kv (g.edges v) s1
    if lookup kv s2.low /= lookup kv s2.number then pure s2 else do
      let (members, rest) = break ((== kv) . fst) s2.stack
      let component = (kv, v) :: members
      pure ({ stack := drop 1 rest
            , onStack $= \on => foldl (\on', member => delete (fst member) on') on component
            , found $= (component ::) } s2)

  covering
  successors : Monad m => Ord k => Graph m k a -> k -> List (k, m (Maybe a)) -> Search k a ->
               m (Search k a)
  successors g kv [] s = pure s
  successors g kv ((kw, find) :: ws) s = do
    s' <- case lookup kw s.number of
      Just n => pure (if contains kw s.onStack then lower n s else s)
      Nothing => do
        Just w <- find
          | Nothing => pure s
        after <- visit g w s
        pure (maybe after (\n => lower n after) (lookup kw after.low))
    successors g kv ws s'
    where
      lower : Nat -> Search k a -> Search k a
      lower n st = { low $= \lows => insert kv (min n (fromMaybe n (lookup kv lows))) lows } st

||| The strongly connected components of `g` that the nodes `roots` reach,
||| the last found first, each found once every component it reaches is.
||| A component lists its nodes, each with its key, from the one the search
||| met first.
export covering
components : Monad m => Ord k => Graph m k a -> List a -> m (List (List (k, a)))
components g roots = (.found) <$> foldlM from (MkSearch 0 empty empty [] empty []) roots
  where
    from : Search k a -> a -> m (Search k a)
    from s r = if isJust (lookup (g.key r) s.number) then pure s else visit g r s

||| The nodes on a cycle of the graph on `nodes` whose edges are `next`
||| (edges to other nodes are ignored): those in a component of two or more
||| nodes, or with an edge to themselves.
export covering
cyclic : Ord k => (k -> List k) -> List k -> SortedSet k
cyclic next nodes =
  let set = SortedSet.fromList nodes
      graph = MkGraph id (\n => map (\m => (m, Id (Just m))) (filter (`contains` set) (next n)))
  in foldl (\acc, c => foldl (flip insert) acc (onCycle (map fst c))) empty
           (runIdentity (components graph nodes))
  where
    onCycle : List k -> List k
    onCycle [n] = if elem n (next n) then [n] else []
    onCycle c = c
