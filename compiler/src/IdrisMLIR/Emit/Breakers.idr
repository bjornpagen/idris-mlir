||| The loop breakers of the emitted module's call graph: the functions
||| marked `no_inline`, so that inlining never unrolls a cycle.
module IdrisMLIR.Emit.Breakers

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
refs (AppF _ f x) = mergeRefs [f, x]
refs (ResumeF _ e) = e
refs (UnreachableF _) = ([], [])
refs (CrashF _ _) = ([], [])

||| The loop breakers, as in GHC ("Secrets of the Glasgow
||| Haskell Compiler inliner", Peyton Jones and Marlow), on full Core's call
||| graph, where a function refers to what it calls and to the closures it
||| builds: enough functions that every cycle through two or more contains
||| one. In each cycle the breaker is the first function in program order
||| that is not from a library the registry breaks last (*Break last*), or
||| the first function if all are; then the rest of the cycle is cut the
||| same way. Program order is each instance, then the functions lifted from
||| it by label.
export
breakers : List TFn -> SortedSet Node
breakers fns =
  let perFn = map (\f => (f, cata refs f.body)) fns
      nodes = concatMap (\(f, (here, below)) => (FnNode f.id, here) :: sortBy (\a, b => compare (fst a) (fst b)) below) perFn
      edges = the (SortedMap Node (List Node)) (fromList nodes)
      library = the (SortedSet Node)
                  (fromList (concatMap (\(f, (_, below)) =>
                               if covers BreakLast f.loc.origin then FnNode f.id :: map fst below else [])
                             perFn))
      order = map fst nodes
  in SortedSet.fromList (within (\n => fromMaybe [] (lookup n edges)) library (length order) order)
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
