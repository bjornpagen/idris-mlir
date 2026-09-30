||| The emitted module's call graph, and what is read off it: the loop
||| breakers (the functions marked `no_inline`, so that inlining never
||| unrolls a cycle) and the lifted functions that terminate.
module IdrisMLIR.Emit.Breakers

import IdrisMLIR.Facts
import IdrisMLIR.Graph
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Fin
import Data.List
import Data.Maybe
import Data.SortedMap
import Data.SortedSet

%default total

||| A function of the emitted module: an instance, or a function lifted
||| from a lambda or `Delay`, by its label.
public export
data Node = FnNode FnId | LamNode Label

export
Eq Node where
  FnNode a == FnNode b = a == b
  LamNode a == LamNode b = a == b
  _ == _ = False

export
Ord Node where
  compare (FnNode a) (FnNode b) = compare a b
  compare (FnNode _) (LamNode _) = LT
  compare (LamNode _) (FnNode _) = GT
  compare (LamNode a) (LamNode b) = compare a b

||| What a term refers to: the functions it calls or closes over at its own
||| level, and the functions lifted from it, each with its own references.
Refs : Type -> Type
Refs _ = (List Node, List (Node, List Node))

||| The references of several subterms.
mergeRefs : List (List Node, List (Node, List Node)) -> (List Node, List (Node, List Node))
mergeRefs rs = (concatMap fst rs, concatMap snd rs)

refs : {0 b : Type} -> TermF Refs b -> Refs b
refs (CallF _ fn as) = let (here, below) = mergeRefs as in (FnNode fn :: here, below)
refs (LamF _ lbl _ _ (here, below)) = ([LamNode lbl], (LamNode lbl, here) :: below)
refs (SuspendF _ lbl _ (here, below)) = ([LamNode lbl], (LamNode lbl, here) :: below)
refs (VarF _ _) = ([], [])
refs (LiteralF _ _) = ([], [])
refs (ErasedF _) = ([], [])
refs (PrimAppF _ _ as) = mergeRefs as
refs (EffectF _ _ as _) = mergeRefs as
refs (ConAppF _ _ as) = mergeRefs as
refs (LetF _ _ v b) = mergeRefs [v, b]
refs (CaseF _ _ alts d) = mergeRefs (map (\(MkAltF _ _ b) => b) alts ++ toList d)
refs (CaseLitF _ _ alts d) = mergeRefs (map snd alts ++ [d])
refs (CaseNatF _ _ z s) = mergeRefs [z, s]
refs (AppF _ f x) = mergeRefs [f, x]
refs (ResumeF _ e) = e
refs (UnreachableF _) = ([], [])
refs (CrashF _ _) = ([], [])

||| The call graph of the emitted module, where a function refers to what
||| it calls and to the closures it builds. Program order is each instance,
||| then the functions lifted from it by label.
public export
record CallGraph where
  constructor MkCallGraph
  edges : SortedMap Node (List Node)
  order : List Node
  ||| The nodes from a library the registry breaks last (*Break last*).
  library : SortedSet Node
  ||| The instances Idris reports terminating.
  proved : SortedSet Node

export
callGraph : List TFn -> CallGraph
callGraph fns =
  let perFn = map (\f => (f, cata refs f.body)) fns
      nodes = concatMap (\(f, (here, below)) => (FnNode f.id, here) :: sortBy (\a, b => compare (fst a) (fst b)) below) perFn
  in MkCallGraph (fromList nodes) (map fst nodes)
       (fromList (concatMap (\(f, (_, below)) =>
                    if covers BreakLast f.loc.origin then FnNode f.id :: map fst below else [])
                  perFn))
       (fromList [FnNode f.id | f <- fns, f.facts.terminating.holds])

||| The references of a node.
next : CallGraph -> Node -> List Node
next g n = fromMaybe [] (lookup n g.edges)

||| The loop breakers, as in GHC ("Secrets of the Glasgow
||| Haskell Compiler inliner", Peyton Jones and Marlow), on full Core's call
||| graph: enough functions that every cycle through two or more contains
||| one. In each cycle the breaker is the first function in program order
||| that is not from a library the registry breaks last, or the first
||| function if all are; then the rest of the cycle is cut the same way.
export
breakers : CallGraph -> SortedSet Node
breakers g = SortedSet.fromList (within (next g) g.library (length g.order) g.order)
  where
    within : (Node -> List Node) -> SortedSet Node -> Nat -> List Node -> List Node
    within next library Z _ = []
    within next library (S k) ns = concatMap cut (components next ns)
      where
        cut : List Node -> List Node
        cut [_] = []
        cut c = case find (not . (`contains` library)) c <|> head' c of
          Just b => b :: within next library k (delete b c)
          Nothing => []

||| The lifted functions that terminate. Idris reports termination per
||| definition, and counts a lambda's calls as its definition's; so a lambda
||| terminates when every instance it reaches, through the lambdas on the
||| way, is reported terminating, its own definition included when it
||| reaches that. A lambda that reaches none only computes. What a lambda
||| would copy from its definition instead is weaker: one partial call
||| elsewhere in the definition would make every lambda of it partial.
export
terminating : CallGraph -> SortedSet Node
terminating g =
  SortedSet.fromList [n | n <- g.order, isLambda n, holds (reach (length g.order) through (SortedSet.fromList g.order) n)]
  where
    isLambda : Node -> Bool
    isLambda (LamNode _) = True
    isLambda (FnNode _) = False
    through : Node -> List Node
    through n@(LamNode _) = next g n
    through (FnNode _) = []
    holds : SortedSet Node -> Bool
    holds reached = all (\n => isLambda n || contains n g.proved) (SortedSet.toList reached)
