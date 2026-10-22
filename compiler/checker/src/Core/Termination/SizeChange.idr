-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Termination.SizeChange

import Core.Context.Log

import Core.Termination.References

import Libraries.Data.NameMap

import Libraries.Data.SparseMatrix

import Array

import Control.WellFounded

import Data.Fin
import Data.List
import Data.List.Elem
import Data.List1
import Data.SortedMap
import Data.Vect

import Decidable.Equality

import Libraries.Data.List.Finite

%default covering

-- Based on:
-- The Size-Change Principle for Termination
-- by Chin Soon Lee, Neil D. Jones, Amir M. Ben-Amram
-- https://doi.org/10.1145/360204.360210

------------------------------------------------------------------------
-- Basic types

||| A change in (g y₀ ⋯ yₙ) with respect to (f x₀ ⋯ xₙ) is
||| for argument yᵢ in g and xⱼ in f:
|||   Smaller        if yᵢ < xⱼ
|||   Equal          if yᵢ <= xⱼ
|||   Unknown        if yᵢ is not related to xⱼ
Change : {- f g -} Type
Change = Libraries.Data.SparseMatrix.Matrix SizeChange

||| A sequence in the call graph lists the source location of the successive
||| calls and the name of each of the functions being called
||| TODO: also record the arguments so that we can print e.g.
|||   flip x y -> flop y x -> flip x y
||| instead of the less useful
|||   flip -> flop -> flip
public export
CallSeq : {- f g -} Type
CallSeq = List (FC, Name)

||| How the path of a walk was made: one call, or the paths of two walks
||| joined, the first's calls then the second's. Joining two walks makes one
||| step of a path, which shares the two it is made of; listing the calls
||| copies them, and a search joins paths of paths, whose calls can double
||| at each step. Only the loop a failed check reports has its calls listed.
export
data CallPath {- f g -} = Call FC Name | Then CallPath CallPath

||| The calls of a path, in order.
export
callSeq : CallPath {- f g -} -> CallSeq {- f g -}
callSeq p = go p []
  where
    go : CallPath -> CallSeq -> CallSeq
    go (Call l g) seq = (l, g) :: seq
    go (Then p1 p2) seq = go p1 (go p2 seq)

||| What a search finds of the loops through a function: each decreases
||| some argument every time round, or this one, by the calls it makes from
||| the function, goes round for ever without decreasing any.
public export
data Loops = Decreasing | Endless CallPath

||| The calls a check has found, each from a caller to a callee with its
||| graph, once, with the place it is made.
Work : Type
Work = SortedMap (Name, Name, Change) FC

------------------------------------------------------------------------
-- The calls a check reaches

-- find (potential) chain of calls to given function (inclusive)
prefixCallSeq : NameMap (FC, Name) -> (g : Name) -> {- Exists \ f => -} CallSeq {- f g -}
prefixCallSeq pred g = go g []
  where
    go : Name -> CallSeq -> CallSeq
    go g seq
        = let Just (l, f) = lookup g pred
             | Nothing => seq in
          if f == g then -- we've reached the entry point!
            seq
          else
            go f ((l, g) :: seq)

||| Steps in a call sequence leading to a loop are also problematic
setPrefixTerminating : {auto c : Ref Ctxt Defs} ->
                       CallSeq -> Name -> Core ()
setPrefixTerminating [] g = pure ()
setPrefixTerminating (_ :: []) g = pure ()
setPrefixTerminating ((l, f) :: p) g
    = do setReachedTerminating l f (NotTerminating (BadPath p g))
         setPrefixTerminating p g

addFunctions : {auto c : Ref Ctxt Defs} ->
              List GlobalDef -> -- functions we're adding
              NameMap (FC, Name) -> -- functions we've already seen (and their predecessor)
              Work ->
              Core (Either Terminating (Work, NameMap (FC, Name)))
addFunctions [] pred work
    = pure $ Right (work, pred)
addFunctions (d1 :: ds) pred work
    = do calls <- foldlC resolveCall [] d1.sizeChange
         let Nothing = find isNonTerminating calls
            | Just (d2, l, _) =>
              do let g = d2.fullname
                 let init = prefixCallSeq pred d1.fullname ++ [(l, g)]
                 setPrefixTerminating init g
                 pure $ Left (NotTerminating (BadPath init g))
         let (ds, pred, work) = foldl addCall (ds, pred, work) (filter isUnchecked calls)
         addFunctions ds pred work
  where
    -- A call is to a definition, a function, a constructor or a case block,
    -- and the context and the modules its imports reach hold every one a
    -- loaded definition calls: a call to a name neither holds is a context
    -- out of step with its TTCs, and is refused.
    resolveCall : List (GlobalDef, FC, Change) ->
                  SCCall ->
                  Core (List (GlobalDef, FC, Change))
    resolveCall calls (MkSCCall g ch l)
        = do Just d2 <- lookupReached g
                | Nothing => undefinedName l g
             pure ((d2, l, ch) :: calls)

    addCall : (List GlobalDef, NameMap (FC, Name), Work) ->
              (GlobalDef, FC, Change) ->
              (List GlobalDef, NameMap (FC, Name), Work)
    addCall (ds, pred, work_in) (d2, l, ch)
        = let work = insert (d1.fullname, d2.fullname, ch) l work_in in
          case lookup d2.fullname pred of
               Just _ =>
                 (ds, pred, work)
               Nothing =>
                 (d2 :: ds, insert d2.fullname (l, d1.fullname) pred, work)

    isNonTerminating : (GlobalDef, _, _) -> Bool
    isNonTerminating (d2, _, _)
        = case d2.totality.isTerminating of
               NotTerminating _ => True
               _ => False

    isUnchecked : (GlobalDef, _, _) -> Bool
    isUnchecked (d2, _, _)
        = case d2.totality.isTerminating of
               Unchecked => True
               _ => False

initWork : {auto c : Ref Ctxt Defs} ->
           GlobalDef -> -- entry
           Core (Either Terminating (Work, NameMap (FC, Name)))
initWork def = addFunctions [def] (insert def.fullname (def.location, def.fullname) empty) empty

------------------------------------------------------------------------
-- Components

||| Tarjan's search for the strongly connected components of the graph of
||| the calls in a work list: each function met gets a number in the order
||| met, and the least number of one still on the stack that it reaches.
record Components where
  constructor MkComponents
  next : Nat
  index : NameMap Nat
  low : NameMap Nat
  stack : List Name
  onStack : NameMap ()
  found : List (List Name)

lowOf : Components -> Name -> Nat
lowOf st v = fromMaybe 0 (lookup v st.low)

||| Pops the component whose first visited function is `v`.
popComponent : Name -> Components -> Components
popComponent v st = go st.stack [] st
  where
    go : List Name -> List Name -> Components -> Components
    go [] members st = { stack := [], found $= (members ::) } st
    go (w :: ws) members st
        = let st' = { onStack $= delete w } st in
          if w == v then { stack := ws, found $= ((w :: members) ::) } st'
                    else go ws (w :: members) st'

mutual
  connect : NameMap (List Name) -> Components -> Name -> Components
  connect calls st v
      = let i = st.next
            st1 = { next $= S, index $= insert v i, low $= insert v i,
                    stack $= (v ::), onStack $= insert v () } st
            st2 = foldl (connectCall calls v) st1 (fromMaybe [] (lookup v calls)) in
        if lowOf st2 v == i then popComponent v st2 else st2

  connectCall : NameMap (List Name) -> Name -> Components -> Name -> Components
  connectCall calls v st w
      = case lookup w st.index of
             Nothing => let st' = connect calls st w in
                        { low $= insert v (min (lowOf st' v) (lowOf st' w)) } st'
             Just j => if isJust (lookup w st.onStack)
                          then { low $= insert v (min (lowOf st v) j) } st
                          else st

||| A strongly connected component of the call graph: its functions, and
||| the calls each makes, in the work list's order.
record Component where
  constructor MkComponent
  members : List Name
  calls : List (Name, SCCall)

||| The components of the graph of a work list's calls. A path from a
||| function back to itself never leaves its component, so the loops of
||| each are searched on its own; a call out of a component is on no loop,
||| and the search drops it.
components : Work -> List Component
components work
    = let out = foldr (\((f, g, ch), l), m => insert f (MkSCCall g ch l :: fromMaybe [] (lookup f m)) m)
                      (the (NameMap (List SCCall)) empty) (SortedMap.toList work)
          callees = map (map fnCall) out
          st = foldlNames (\st, v, _ => if isJust (lookup v st.index) then st else connect callees st v)
                          (MkComponents 0 empty empty [] empty []) callees in
      map (\fs => MkComponent fs (concatMap (\f => map (f,) (fromMaybe [] (lookup f out))) fs)) st.found

------------------------------------------------------------------------
-- The loops of a component

||| A size-change graph over `n` arguments, dense: at `[<i, j]`, how
||| argument `i` at the end relates to argument `j` at the start
||| (`Unknown`, nothing known).
Graph : Nat -> Type
Graph n = Array [<n, n] SizeChange

||| A walk of calls from the function `from` to the function `to`, over `n`
||| arguments: its graph, and the calls it makes. The ends are in the type,
||| so that walks join only end to start (`andThen`). The graphs over `n`
||| arguments are finitely many (`Finite`), which is why the searches below
||| end: each keeps every graph it meets once (by its rows, `rows`), so it
||| has room for fewer graphs at each step.
data Walk : (n : Nat) -> (from, to : Fin m) -> Type where
  MkWalk : (graph : Graph n) -> (path : CallPath) -> Walk n from to

pathOf : Walk n from to -> CallPath
pathOf (MkWalk _ p) = p

parts : Walk n from to -> (Graph n, CallPath)
parts (MkWalk g p) = (g, p)

Finite SizeChange where
  values = [Smaller, Same, Unknown]
  complete Smaller = Here
  complete Same = There Here
  complete Unknown = There (There Here)

||| The arguments of a graph over `n`, each by its place, in order, listed
||| once for every graph of a component's search: base's `allFins` makes
||| the list anew at each call, at a cost quadratic in `n`, and every key
||| and every comparison of a graph reads it.
record Places (n : Nat) where
  constructor MkPlaces
  each : Vect n (Fin n)

||| The walk's graph, row by row: the finite form a search keeps.
rows : Places n -> Walk n from to -> Vect n (Vect n SizeChange)
rows ps (MkWalk g _) = map (\i => map (\j => g !! [<i, j]) ps.each) ps.each

||| Does `p` hold at every place of a graph over `n` arguments?
everywhere : Places n -> (Index [<n, n] -> Bool) -> Bool
everywhere ps p = all (\i => all (\j => p [<i, j]) ps.each) ps.each

||| A walk from `a` to `b`, then one from `b` to `c`: the walk from `a` to
||| `c`. How an argument of `c` relates to one of `a` is the strongest way
||| through an argument of `b`: the matrix product of the later graph by
||| the earlier in the size-change semiring, whose sum's zero is `Unknown`,
||| since a graph's rows are the arguments at its end.
andThen : Walk n a b -> Walk n b c -> Walk n a c
andThen (MkWalk ab p) (MkWalk bc q) = MkWalk (contract (|+|) plusNeutral (|*|) bc ab) (Then p q)

||| `weaker x y`: `y` says at least what `x` says of every argument: each
||| arc of `x` is one of `y`'s, as strong or stronger (`Unknown`, no arc, is
||| the weakest).
weaker : Places n -> Walk n a b -> Walk n a b -> Bool
weaker ps (MkWalk x _) (MkWalk y _) = everywhere ps (\ix => x !! ix <= y !! ix)

||| Do two walks between the same functions have one graph?
sameGraph : Places n -> Walk n a b -> Walk n a b -> Bool
sameGraph ps (MkWalk x _) (MkWalk y _) = everywhere ps (\ix => x !! ix == y !! ix)

||| Does a loop's walk take some argument to a strictly smaller one of
||| itself?
decreases : Places n -> Walk n f f -> Bool
decreases ps (MkWalk g _) = any (\i => g !! [<i, i] == Smaller) ps.each

||| Does going round a loop with this walk twice go round as once does,
||| without decreasing any argument? Then it goes round for ever.
endless : Places n -> Walk n f f -> Bool
endless ps e = sameGraph ps (andThen e e) e && not (decreases ps e)

||| What going round a loop with the walk `g` does, judged by its powers
||| from `p` on, each as it is met. Going round any number of times is a
||| power of `g`, and some power goes round twice as it goes round once:
||| the powers are associative products in a finite set, so they cycle, and
||| the cycle holds one. The loop decreases each time round exactly when
||| that power takes some argument to a strictly smaller one of itself;
||| when it does not, that power's walk is the loop that goes round for
||| ever. Once a power repeats, every power has been met. Each is a graph
||| over the same arguments, met once, so the room for more goes down at
||| each.
total
powers : {n : Nat} -> Places n -> (g : Walk n f f) ->
         (seen : List (Vect n (Vect n SizeChange))) -> (0 nd : NoDup seen) ->
         (0 room : Nat) ->
         (0 fits : length seen + room = length (values {a = Vect n (Vect n SizeChange)})) ->
         (0 acc : Accessible LT room) -> (p : Walk n f f) -> Loops
powers ps g seen nd room fits (Access rec) p
    = let key = rows ps p in
      case isElem key seen of
           Yes _ => Decreasing
           No notIn =>
             if endless ps p then Endless (pathOf p)
             else let 0 next = roomAfter nd notIn room fits in
                  powers ps g (key :: seen) (notIn :: nd) (fst next) (snd (snd next))
                         (rec (fst next) (rewrite fst (snd next) in reflexive))
                         (andThen p g)

||| What going round a loop with this walk, from a function to itself,
||| does.
total
roundTrip : {n : Nat} -> Places n -> Walk n f f -> Loops
roundTrip ps g = powers ps g [] [] (length (values {a = Vect n (Vect n SizeChange)})) Refl (wellFounded _) g

||| What the loop a walk from `f` to `h` closes does: a walk closes one when
||| it comes back to `f`, and one that ends elsewhere closes none, so none
||| of its loops fails.
total
closes : {m, n : Nat} -> Places n -> (f, h : Fin m) -> Walk n f h -> Loops
closes ps f h x = case decEq h f of
                    Yes back => roundTrip ps (replace {p = Walk n f} back x)
                    No _ => Decreasing

||| The calls of a component, each from the function it is listed under, to
||| the function it names, with its graph and the call itself. Only
||| `callsFrom` reads it, so a call's walk is typed by its ends.
record Calls (m, n : Nat) where
  constructor MkCalls
  table : Vect m (List (Fin m, Graph n, CallPath))

callsFrom : (h : Fin m) -> Calls m n -> List (k : Fin m ** Walk n h k)
callsFrom h cs = map (\(k, g, p) => (k ** MkWalk g p)) (index h (table cs))

||| The weakest walks from `f` found so far, by the function each ends at.
||| Only `keptAt` and `keep` touch it, so a walk kept at `h` is one to `h`.
record Kept (m, n : Nat) (f : Fin m) where
  constructor MkKept
  table : Vect m (List (Graph n, CallPath))

keptAt : (h : Fin m) -> Kept m n f -> List (Walk n f h)
keptAt h k = map (\(g, p) => MkWalk g p) (index h (table k))

||| `x` kept at `h`, and the walks there it is weaker than dropped.
keep : Places n -> (h : Fin m) -> Walk n f h -> Kept m n f -> Kept m n f
keep ps h x k = MkKept (replaceAt h (parts x :: map parts (filter (not . weaker ps x) (keptAt h k)))
                                  (table k))

||| What the loops through `f` do, given the calls of its component. The
||| walks from `f` are extended one call at a time, and each function they
||| reach keeps only the weakest walks to it, those no other walk's graph is
||| weaker than: composition keeps the order (weaker parts make a weaker
||| walk), so a walk no weaker than one kept extends only to walks no
||| weaker than that one's, and what each function keeps in the end are the
||| weakest walks of every walk to it, whatever the order of the search. A
||| loop that fails to decrease still fails when its graph says less, since
||| the powers of a weaker graph are weaker and a strict arc of a weaker
||| graph is one of the stronger's; so a walk dropped for a weaker one kept
||| loses no loop that fails. Each walk back to `f` is judged as it is
||| found, and the first that goes round for ever is the answer; a search
||| that runs out of walks has judged every weakest loop through `f`, and
||| each decreases. The loops through `f` are walks from it: the paths
||| between the other pairs of its component are no part of its answer.
|||
||| The search ends: a walk's graph is kept at a function at most once
||| (once kept, it or a weaker one stays kept, so it is never kept again),
||| every pair of a function and a graph's rows it keeps is in `seen`, which
||| holds each once, and there are finitely many such pairs. Each walk taken
||| from `todo` is either dropped, leaving `todo` shorter, or kept, leaving
||| less room.
total
search : {m, n : Nat} -> Places n -> (f : Fin m) -> (out : Calls m n) ->
         (seen : List (Fin m, Vect n (Vect n SizeChange))) -> (0 nd : NoDup seen) ->
         (kept : Kept m n f) ->
         (0 room : Nat) ->
         (0 fits : length seen + room = length (values {a = (Fin m, Vect n (Vect n SizeChange))})) ->
         (0 acc : Accessible LT room) ->
         (todo : List (h : Fin m ** Walk n f h)) -> Loops
search ps f out seen nd kept room fits acc [] = Decreasing
search ps f out seen nd kept room fits (Access rec) ((h ** x) :: todo)
    = if any (\y => weaker ps y x) (keptAt h kept)
         then search ps f out seen nd kept room fits (Access rec) todo
      else case closes ps f h x of
             Endless loop => Endless loop
             Decreasing =>
               let key = (h, rows ps x) in
               case isElem key seen of
                 Yes _ => search ps f out seen nd kept room fits (Access rec) todo
                 No notIn =>
                   let 0 next = roomAfter nd notIn room fits in
                   search ps f out (key :: seen) (notIn :: nd) (keep ps h x kept)
                          (fst next) (snd (snd next))
                          (rec (fst next) (rewrite fst (snd next) in reflexive))
                          (map (\(k ** z) => (k ** andThen x z)) (callsFrom h out) ++ todo)

||| The arguments the graphs of a component's calls speak of: one past the
||| largest position any of them names.
argCount : List (Name, SCCall) -> Nat
argCount calls = foldr (\(_, call), acc => max acc (width (fnArgs call))) 0 calls
  where
    width : Change -> Nat
    width x = foldr (\(i, row), acc => max acc (max (S i) (S (Vector1.maxIndex row)))) 0 x

||| A call's graph (a row for each of the callee's arguments, a column for
||| each of the caller's), dense over `n` arguments: where the call's
||| sparse graph has no entry, nothing is known.
dense : {n : Nat} -> Change -> Graph n
dense x = Array.Core.tabulate [<n, n] entry
  where
    entry : Index [<n, n] -> SizeChange
    entry [<i, j] = fromMaybe Unknown (Vector.lookupOrd (finToNat i) x >>= Vector1.lookupOrd (finToNat j))

||| For each function of a strongly connected component of the call graph,
||| given the calls its functions make (the caller, and the call: the
||| callee, how each argument of the callee relates to the caller's, and
||| where it is made), what the loops through it do. A loop never leaves
||| its component, so a call out of it is no part of the answer.
export total
loopsTerminate : List (Name, SCCall) -> List Name -> List (Name, Loops)
loopsTerminate calls members
    = let n = argCount calls
          ps = MkPlaces (Vect.allFins n)
          out = MkCalls (foldr (add {n}) (replicate (length members) []) calls) in
      zip members (map (\f => search ps f out [] [] (MkKept (replicate (length members) [])) _ Refl
                                         (wellFounded _) (callsFrom f out))
                       (toList (Vect.allFins (length members))))
  where
    add : {n : Nat} -> (Name, SCCall) ->
          Vect (length members) (List (Fin (length members), Graph n, CallPath)) ->
          Vect (length members) (List (Fin (length members), Graph n, CallPath))
    add (f, call) out
        = case (findIndex (== f) members, findIndex (== fnCall call) members) of
               (Just i, Just j) => updateAt i ((j, dense (fnArgs call), Call (fnLoc call) (fnCall call)) ::) out
               _ => out

||| What the search finds of the loops through each function of a
||| component.
componentLoops : Component -> List (Name, Loops)
componentLoops comp = loopsTerminate comp.calls comp.members

||| The function a failed check reports, and its loop that goes round for
||| ever: of every function with such a loop, the greatest by name, so that
||| the report does not depend on the order the components are searched in.
reported : List (Name, Loops) -> Maybe (Name, CallPath)
reported = foldl pick Nothing
  where
    pick : Maybe (Name, CallPath) -> (Name, Loops) -> Maybe (Name, CallPath)
    pick found (_, Decreasing) = found
    pick Nothing (g, Endless loop) = Just (g, loop)
    pick (Just (h, other)) (g, Endless loop) = if g > h then Just (g, loop) else Just (h, other)

------------------------------------------------------------------------
-- The check

||| The names a definition refers to, with those of its case blocks, which
||| are checked as part of it.
addCases : {auto c : Ref Ctxt Defs} -> List Name -> Core (List Name)
addCases ns = go empty ns
  where
    go : NameMap () -> List Name -> Core (List Name)
    go all [] = pure (keys all)
    go all (n :: ns)
        = case lookup n all of
             Just _ => go all ns
             Nothing =>
               if caseFn !(getFullName n)
                  then case !(lookupReached n) of
                            Just def => go (insert n () all) (keys (refersTo def) ++ ns)
                            Nothing => go (insert n () all) ns
                  else go (insert n () all) ns

||| Records as terminating the functions a successful search visited whose
||| verdict no later check could change, so that no later check searches
||| them again. A visited function's own check would search a part of this
||| search's graph, which has no loop, and would find each name it refers
||| to as it is then. That is the same verdict when every such name is
||| settled: terminating already, a primitive, which has no calls, or
||| settled here. Settled here are the visited functions and their case
||| blocks (a case block is checked inline, as part of the function that
||| matches, so no call reaches one and none is on a loop) whose names are
||| all settled. A function that is not defined yet, a constructor whose
||| type's positivity is not checked yet, or a reference to an unchecked
||| function outside the search (under `assert_total`, or a guarded `Delay`)
||| may still become non-terminating, and so does everything that refers to
||| one.
settle : {auto c : Ref Ctxt Defs} -> List Name -> Core ()
settle visited
    = do let seen = Libraries.Data.NameMap.fromList (map (\n => (n, ())) visited)
         deps <- explore seen visited empty
         let users = foldlNames (\m, n, ds => foldl (\m, d => insert d (n :: fromMaybe [] (lookup d m)) m) m
                                                    (fromMaybe [] ds))
                                (the (NameMap (List Name)) empty) deps
         let unsettled = spread users empty (keys (filterBy (\n => maybe False isNothing (lookup n deps)) deps))
         traverse_ (\n => when (isNothing (lookup n unsettled)) $
                             setReachedTerminating EmptyFC n IsTerminating)
                   (keys deps)
  where
    primitive : Def -> Bool
    primitive (Builtin _) = True
    primitive (ExternDef _) = True
    primitive _ = False

    -- The functions and case blocks a function's verdict depends on, or
    -- Nothing when it depends on a name that is not settled.
    dependencies : NameMap () -> Name -> Core (Maybe (List Name))
    dependencies seen n
        = do Just def <- lookupReached n
               | Nothing => pure Nothing
             let PMDef {} = definition def
               | d => pure (if primitive d then Just [] else Nothing)
             refs <- addCases (keys (refersTo def) ++ map (\(MkSCCall g _ _) => g) def.sizeChange)
             go refs []
      where
        go : List Name -> List Name -> Core (Maybe (List Name))
        go [] acc = pure (Just acc)
        go (r :: rs) acc
            = do -- A name that is no definition, a variable, waits on
                 -- nothing.
                 Just d <- lookupReached r
                   | Nothing => go rs acc
                 case isTerminating (totality d) of
                      IsTerminating => go rs acc
                      NotTerminating _ => pure Nothing
                      Unchecked =>
                        if isJust (lookup d.fullname seen) || caseFn d.fullname
                           then go rs (d.fullname :: acc)
                           else if primitive (definition d)
                                   then go rs acc
                                   else pure Nothing

    -- Every function and case block reached, with what it depends on.
    explore : NameMap () -> List Name -> NameMap (Maybe (List Name)) ->
              Core (NameMap (Maybe (List Name)))
    explore seen [] acc = pure acc
    explore seen (n :: ns) acc
        = case lookup n acc of
               Just _ => explore seen ns acc
               Nothing => do
                 ds <- dependencies seen n
                 explore seen (fromMaybe [] ds ++ ns) (insert n ds acc)

    spread : NameMap (List Name) -> NameMap () -> List Name -> NameMap ()
    spread users acc [] = acc
    spread users acc (n :: ns)
        = case lookup n acc of
               Just _ => spread users acc ns
               Nothing => spread users (insert n () acc) (fromMaybe [] (lookup n users) ++ ns)

||| Whether a function terminates: every function it reaches that is not
||| checked yet is searched, each component on its own, for a loop that
||| goes round for ever. One through the function itself is its own; one
||| elsewhere is that function's, and the function is not terminating for
||| reaching it.
export
calcTerminating : {auto c : Ref Ctxt Defs} ->
                  FC -> Name -> Core Terminating
calcTerminating loc n
    = do defs <- get Ctxt
         logC "totality.termination.calc" 7 $ do pure $ "Calculating termination: " ++ show !(toFullNames n)
         Just def <- lookupCtxtExact n (gamma defs)
           | Nothing => undefinedName loc n
         IsTerminating <- totRefs (nub !(addCases (keys (refersTo def))))
           | bad => pure bad
         Right (work, pred) <- initWork def
           | Left bad => pure bad
         let Nothing = reported (concatMap componentLoops (components work))
           | Just (g, loop) =>
               let loopSeq = callSeq loop in
               ifThenElse (def.fullname == g)
                 (pure $ NotTerminating (RecPath loopSeq))
                 (do setReachedTerminating EmptyFC g (NotTerminating (RecPath loopSeq))
                     let init = prefixCallSeq pred g
                     setPrefixTerminating init g
                     pure $ NotTerminating (BadPath init g))
         settle (keys pred)
         pure IsTerminating
