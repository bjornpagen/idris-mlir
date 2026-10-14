module Core.Termination.SizeChange

import Core.Context.Log

import Core.Termination.References

import Libraries.Data.NameMap

import Libraries.Data.SparseMatrix

import Data.List
import Data.List1

%default covering

-- Based on:
-- The Size-Change Principle for Termination
-- by Chin Soon Lee, Neil D. Jones, Amir M. Ben-Amram
-- https://doi.org/10.1145/360204.360210

------------------------------------------------------------------------
-- Basic types

||| Refer to an argument by its position
-- This seems to assume that a function has a set number of arguments
-- (a constraint we currently enforce: all clauses' LHS need to have
-- the same number of arguments)
Arg : Type
Arg = Nat

||| A change in (g y₀ ⋯ yₙ) with respect to (f x₀ ⋯ xₙ) is
||| for argument yᵢ in g and xⱼ in f:
|||   Smaller        if yᵢ < xⱼ
|||   Equal          if yᵢ <= xⱼ
|||   Unknown        if yᵢ is not related to xⱼ
Change : {- f g -} Type
Change = Matrix SizeChange

||| A sequence in the call graph lists the source location of the successive
||| calls and the name of each of the functions being called
||| TODO: also record the arguments so that we can print e.g.
|||   flip x y -> flop y x -> flip x y
||| instead of the less useful
|||   flip -> flop -> flip
public export
CallSeq : {- f g -} Type
CallSeq = List (FC, Name)

||| A call a search reached: its caller, its callee, how each argument of
||| the callee relates to the caller's, and where it is.
Call : Type
Call = (Name, Name, Change, FC)

------------------------------------------------------------------------
-- Actual size-change computations

||| Diagrammatic composition:
||| Given a (Change f g) and a (Change g h), compute a (Change f h)
composeChange : Change {- f g -} -> Change {- g h -} -> Change {- f h -}
composeChange
    -- We use the SizeChange monoid: Unknown is a 0, Same is a neutral
    = mult

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
    = do setTerminating l f (NotTerminating (BadPath p g))
         setPrefixTerminating p g

addFunctions : {auto c : Ref Ctxt Defs} ->
              Defs ->
              List GlobalDef -> -- functions we're adding
              NameMap (FC, Name) -> -- functions we've already seen (and their predecessor)
              List Call ->
              Core (Either Terminating (List Call, NameMap (FC, Name)))
addFunctions defs [] pred work
    = pure $ Right (work, pred)
addFunctions defs (d1 :: ds) pred work
    = do calls <- foldlC resolveCall [] d1.sizeChange
         let Nothing = find isNonTerminating calls
            | Just (d2, l, _) =>
              do let g = d2.fullname
                 let init = prefixCallSeq pred d1.fullname ++ [(l, g)]
                 setPrefixTerminating init g
                 pure $ Left (NotTerminating (BadPath init g))
         let (ds, pred, work) = foldl addCall (ds, pred, work) (filter isUnchecked calls)
         addFunctions defs ds pred work
  where
    resolveCall : List (GlobalDef, FC, Call) ->
                  SCCall ->
                  Core (List (GlobalDef, FC, Call))
    resolveCall calls (MkSCCall g ch l)
        = do Just d2 <- lookupCtxtExact g (gamma defs)
                | Nothing => do logC "totality.termination.calc" 7 $ do pure "Not found: \{show g}"
                                pure calls
             pure ((d2, l, (d1.fullname, d2.fullname, ch, l)) :: calls)

    addCall : (List GlobalDef, NameMap (FC, Name), List Call) ->
                  (GlobalDef, FC, Call) ->
                  (List GlobalDef, NameMap (FC, Name), List Call)
    addCall (ds, pred, work_in) (d2, l, c)
        = let work = c :: work_in in
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
           Defs ->
           GlobalDef -> -- entry
           Core (Either Terminating (List Call, NameMap (FC, Name)))
initWork defs def = addFunctions defs [def] (insert def.fullname (def.location, def.fullname) empty) []

||| The strongly connected components of the graph of the calls in a work
||| list, as each function's component (Tarjan's algorithm). A path from a
||| function back to itself never leaves its component, so every loop is
||| among the calls inside components; a call between two components is on
||| no loop, and closing over it only makes paths that no loop is on.
record Components where
  constructor MkComponents
  next : Nat
  index : NameMap Nat
  low : NameMap Nat
  stack : List Name
  onStack : NameMap ()
  component : NameMap Nat
  count : Nat

lowOf : Components -> Name -> Nat
lowOf st v = fromMaybe 0 (lookup v st.low)

||| Pops the component whose first visited function is `v`.
popComponent : Name -> Components -> Components
popComponent v st = go st.stack st
  where
    go : List Name -> Components -> Components
    go [] st = { stack := [] } st
    go (w :: ws) st
        = let st' = { onStack $= delete w, component $= insert w st.count } st in
          if w == v then { stack := ws, count $= S } st' else go ws st'

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

||| The calls inside components, by caller, each caller's in the order of
||| their callees and graphs. Every loop is among them: a call that leaves
||| a component is on no path back to it.
insideComponents : List Call -> NameMap (List (Name, Change, FC))
insideComponents work
    = let calls = foldl (\m, (f, g, _, _) => insert f (g :: fromMaybe [] (lookup f m)) m)
                        (the (NameMap (List Name)) empty) work
          st = foldlNames (\st, v, _ => if isJust (lookup v st.index) then st else connect calls st v)
                          (MkComponents 0 empty empty [] empty empty 0) calls
          same = \f, g => lookup f st.component == lookup g st.component in
      foldr (\(f, g, x, l), m => if same f g then insert f ((g, x, l) :: fromMaybe [] (lookup f m)) m else m)
            (the (NameMap (List (Name, Change, FC))) empty)
            (sortBy (comparing (\(f, g, x, _) => (f, g, x))) work)

||| `weaker g h`: `h` says at least what `g` says of every argument: each
||| arc of `g` is one of `h`'s, as strong or stronger (a missing entry is no
||| arc, the weakest).
weaker : Change -> Change -> Bool
weaker g h = all row g
  where
    row : (Nat, Vector1 SizeChange) -> Bool
    row (i, xs) = case Vector.lookupOrd i h of
      Nothing => False
      Just ys => all (\(j, x) => maybe False (x <=) (Vector1.lookupOrd j ys)) (forget xs)

||| Does going round a loop with this graph, from a function to itself,
||| fail to decrease? Going round any number of times is a power of the
||| graph, and some power is idempotent, unchanged by composing with
||| itself: the loop decreases each time round exactly when that power
||| takes some argument to a strictly smaller one of itself. A power that
||| is not found within the fuel counts as failing, so that the answer is
||| never a decrease that was not shown.
nonDescending : Change -> Bool
nonDescending g = go 1024 g
  where
    go : Nat -> Change -> Bool
    go Z _ = True
    go (S k) p = if composeChange p p == p
                    then not (any (\(i, xs) => Vector1.lookupOrd i xs == Just Smaller) p)
                    else go k (composeChange p g)

||| A loop through `f` that fails to decrease some argument each time
||| round, if there is one, as its calls. The walks from `f` are extended
||| one call at a time, breadth first, and each function they reach keeps
||| only the weakest graphs of the walks to it, those no other walk's graph
||| is weaker than: composition keeps the order, so a walk whose graph is no
||| weaker than one kept extends only to walks no weaker than that one's,
||| and a loop that fails to decrease still fails with a weaker graph, since
||| the powers of a weaker graph are weaker and a strict arc of a weaker
||| graph is one of the stronger's. So a loop without decrease exists
||| exactly when one of the graphs kept at `f` has none, and the first walk
||| back to `f` that has none, one of the fewest calls, is the loop. A
||| function's own loops are walks from it: the paths between every other
||| pair of its component are no part of the answer.
loopFrom : NameMap (List (Name, Change, FC)) -> Name -> Maybe CallSeq
loopFrom out f = go (map (\(h, x, l) => (h, x, [(l, h)])) (callsOf f)) [] empty
  where
    callsOf : Name -> List (Name, Change, FC)
    callsOf g = fromMaybe [] (lookup g out)

    -- Each walk: where it is, its graph, and its calls, the last first.
    go : List (Name, Change, CallSeq) -> List (Name, Change, CallSeq) -> NameMap (List Change) ->
         Maybe CallSeq
    go [] [] kept = Nothing
    go [] next kept = go (reverse next) [] kept
    go ((h, x, p) :: rest) next kept
        = let old = fromMaybe [] (lookup h kept) in
          if any (\y => weaker y x) old then go rest next kept
          else if h == f && nonDescending x then Just (reverse p)
          else go rest (foldl (\acc, (k, z, l) => (k, composeChange x z, (l, k) :: p) :: acc) next (callsOf h))
                  (insert h (x :: filter (not . weaker x) old) kept)

||| For each function of a strongly connected component of the call graph,
||| given the calls between its functions (caller, callee, and how each
||| argument of the callee relates to the caller's), whether every loop
||| through it decreases some argument each time round. A loop never
||| leaves its component, so a call out of it is no part of the answer.
export
loopsTerminate : List (Name, Name, Matrix SizeChange) -> List Name -> List (Name, Bool)
loopsTerminate calls members
    = let out = foldl (\m, (f, h, x) => insert f ((h, x, EmptyFC) :: fromMaybe [] (lookup f m)) m)
                      (the (NameMap (List (Name, Change, FC))) empty) (reverse calls) in
      map (\f => (f, isNothing (loopFrom out f))) members

||| The names a definition refers to, with those of its case blocks, which
||| are checked as part of it.
addCases : {auto c : Ref Ctxt Defs} -> Defs -> List Name -> Core (List Name)
addCases defs ns = go empty ns
  where
    go : NameMap () -> List Name -> Core (List Name)
    go all [] = pure (keys all)
    go all (n :: ns)
        = case lookup n all of
             Just _ => go all ns
             Nothing =>
               if caseFn !(getFullName n)
                  then case !(lookupCtxtExact n (gamma defs)) of
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
settle : {auto c : Ref Ctxt Defs} -> Defs -> List Name -> Core ()
settle defs visited
    = do let seen = Libraries.Data.NameMap.fromList (map (\n => (n, ())) visited)
         deps <- explore seen visited empty
         let users = foldlNames (\m, n, ds => foldl (\m, d => insert d (n :: fromMaybe [] (lookup d m)) m) m
                                                    (fromMaybe [] ds))
                                (the (NameMap (List Name)) empty) deps
         let unsettled = spread users empty (keys (filterBy (\n => maybe False isNothing (lookup n deps)) deps))
         traverse_ (\n => when (isNothing (lookup n unsettled)) $
                             setTerminating EmptyFC n IsTerminating)
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
        = do Just def <- lookupCtxtExact n (gamma defs)
               | Nothing => pure Nothing
             let PMDef {} = definition def
               | d => pure (if primitive d then Just [] else Nothing)
             refs <- addCases defs (keys (refersTo def) ++ map (\(MkSCCall g _ _) => g) def.sizeChange)
             go refs []
      where
        go : List Name -> List Name -> Core (Maybe (List Name))
        go [] acc = pure (Just acc)
        go (r :: rs) acc
            = do Just d <- lookupCtxtExact r (gamma defs)
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

||| The last of the functions given, in name order, with a loop that fails
||| to decrease, and the loop: the one a failed search records.
lastLoop : NameMap (List (Name, Change, FC)) -> List Name -> Maybe (Name, CallSeq)
lastLoop out [] = Nothing
lastLoop out (g :: gs) = case loopFrom out g of
  Just loop => Just (g, loop)
  Nothing => lastLoop out gs

export
calcTerminating : {auto c : Ref Ctxt Defs} ->
                  FC -> Name -> Core Terminating
calcTerminating loc n
    = do defs <- get Ctxt
         logC "totality.termination.calc" 7 $ do pure $ "Calculating termination: " ++ show !(toFullNames n)
         Just def <- lookupCtxtExact n (gamma defs)
           | Nothing => undefinedName loc n
         IsTerminating <- totRefs defs (nub !(addCases defs (keys (refersTo def))))
           | bad => pure bad
         Right (work, pred) <- initWork defs def
           | Left bad => pure bad
         let inside = insideComponents work
         let Nothing = lastLoop inside (reverse (keys inside))
           | Just (g, loop) =>
               ifThenElse (def.fullname == g)
                 (pure $ NotTerminating (RecPath loop))
                 (do setTerminating EmptyFC g (NotTerminating (RecPath loop))
                     let init = prefixCallSeq pred g
                     setPrefixTerminating init g
                     pure $ NotTerminating (BadPath init g))
         settle defs (keys pred)
         pure IsTerminating
