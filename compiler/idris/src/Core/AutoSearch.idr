-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.AutoSearch

import Core.Context.Log
import Core.Env
import Core.Normalise
import Core.Unify
import Core.Value

import Data.Either
import Data.Maybe

import Libraries.Data.NatSet
import Libraries.Data.List.SizeOf
import Libraries.Data.WithDefault

%default covering

tryUnifyUnambig' : {auto c : Ref Ctxt Defs} ->
                   {auto u : Ref UST UState} ->
                   {default False preferLeftError : Bool} ->
                   Core a -> (Error -> Core a) -> Core a
tryUnifyUnambig' left right = handleUnify left $ \case
  e@(AmbiguousSearch {}) => throw e
  e@(SearchGrows {})     => throw e
  e                      => if preferLeftError
                              then tryUnify (right e) (throw e)
                              else right e

tryUnifyUnambig : {auto c : Ref Ctxt Defs} ->
                  {auto u : Ref UST UState} ->
                  {default False preferLeftError : Bool} ->
                  Core a -> Core a -> Core a
tryUnifyUnambig left right = tryUnifyUnambig' {preferLeftError} left $ const right

tryNoDefaultsFirst : {auto c : Ref Ctxt Defs} ->
                     {auto u : Ref UST UState} ->
                     (Bool -> Core a) -> Core a
tryNoDefaultsFirst f = tryUnifyUnambig {preferLeftError=True} (f False) (f True)

SearchEnv : Scoped
SearchEnv vars = List (NF vars, Closure vars)

-- The path rule. A search that never ends meets, on one of its paths, a
-- goal into which an earlier goal of the same type constructor embeds
-- (Kruskal's tree theorem, over finitely many labels), so the search stops
-- at the first such pair, by construction and with no count: the later goal
-- repeats the earlier (convertible: that step fails, as upstream's cycle
-- check does), or grows from it through unknowns a later round may fix (the
-- search waits), or grows with everything known (the program is refused).
-- What the stock Idris answers with a large enough depth is answered the
-- same, but where its answer was its depth running out.

-- A goal's argument as the rule compares it. The labels are finitely many:
-- unknowns are one symbol, and so are the locals the search binds itself
-- (its Π goals add them without bound) and the goal's own binders' locals,
-- and a universe, whose level is a fresh name each time, is one symbol too.
-- A constant keeps its value, under an order with no infinite descent and no
-- infinite antichain: an integer by its magnitude, a string as a
-- subsequence, any other constant (of a finite type) by equality. A numeral
-- of a unary type is its constructors' tree already.
data Label
  = Named Name
  | RootLocal Nat
  | SearchLocal
  | Unsolved
  | Universe
  | Literal Constant
  | Binds Nat
  | LazyType
  | LazyValue
  | Forced
  | ErasedPart

-- Whether the earlier label is below the later one.
labelBelow : Label -> Label -> Bool
labelBelow (Named m) (Named n) = m == n
labelBelow (RootLocal i) (RootLocal j) = i == j
labelBelow SearchLocal SearchLocal = True
labelBelow Unsolved Unsolved = True
labelBelow Universe Universe = True
labelBelow (Literal c) (Literal d) = constantBelow c d
  where
    subsequence : List Char -> List Char -> Bool
    subsequence [] _ = True
    subsequence (_ :: _) [] = False
    subsequence (x :: xs) (y :: ys)
        = if x == y then subsequence xs ys else subsequence (x :: xs) ys

    constantBelow : Constant -> Constant -> Bool
    constantBelow (BI x) (BI y) = abs x <= abs y
    constantBelow (Str x) (Str y) = subsequence (unpack x) (unpack y)
    constantBelow x y = x == y
labelBelow (Binds i) (Binds j) = i == j
labelBelow LazyType LazyType = True
labelBelow LazyValue LazyValue = True
labelBelow Forced Forced = True
labelBelow ErasedPart ErasedPart = True
labelBelow _ _ = False

data Shape = Shaped Label (List Shape)

bindingKind : Binder (Term vs) -> Nat
bindingKind (Lam {}) = 0
bindingKind (Let {}) = 1
bindingKind (Pi {}) = 2
bindingKind (PVar {}) = 3
bindingKind (PLet {}) = 4
bindingKind (PVTy {}) = 5

mutual
  -- A goal's argument's shape, given how many of the innermost locals of
  -- its environment the search bound itself (`k`) and how many binders of
  -- the term itself are around it (`inner`).
  shapeIn : (k, inner : Nat) -> Term vs -> Shape
  shapeIn k inner (Local _ _ idx _)
      = if idx < inner + k
           then Shaped SearchLocal []
           else Shaped (RootLocal (minus idx (inner + k))) []
  shapeIn k inner (Ref _ _ n) = Shaped (Named n) []
  shapeIn k inner (Meta {}) = Shaped Unsolved []
  shapeIn k inner (Bind _ _ b sc)
      = Shaped (Binds (bindingKind b)) [shapeIn k inner (binderType b), shapeIn k (S inner) sc]
  shapeIn k inner (App _ f a) = applied k inner f [shapeIn k inner a]
  shapeIn k inner (As _ _ _ p) = shapeIn k inner p
  shapeIn k inner (TDelayed _ _ t) = Shaped LazyType [shapeIn k inner t]
  shapeIn k inner (TDelay _ _ t a) = Shaped LazyValue [shapeIn k inner t, shapeIn k inner a]
  shapeIn k inner (TForce _ _ t) = Shaped Forced [shapeIn k inner t]
  shapeIn k inner (PrimVal _ c) = Shaped (Literal c) []
  shapeIn k inner (Erased {}) = Shaped ErasedPart []
  shapeIn k inner (TType {}) = Shaped Universe []

  -- An application's head takes its arguments as children; an unknown
  -- applied is an unknown.
  applied : (k, inner : Nat) -> Term vs -> List Shape -> Shape
  applied k inner (App _ f a) args = applied k inner f (shapeIn k inner a :: args)
  applied k inner (Meta {}) args = Shaped Unsolved []
  applied k inner f args
      = case shapeIn k inner f of
             Shaped l cs => Shaped l (cs ++ args)

mutual
  -- Homeomorphic embedding: the earlier shape is in a child of the later
  -- one, or the roots agree and the children embed, in order, into a
  -- subsequence of the later's (the leftmost match never loses one).
  embeds : Shape -> Shape -> Bool
  embeds s t@(Shaped _ ts) = couples s t || embedsChild s ts

  embedsChild : Shape -> List Shape -> Bool
  embedsChild s [] = False
  embedsChild s (t :: ts) = embeds s t || embedsChild s ts

  couples : Shape -> Shape -> Bool
  couples (Shaped l ss) (Shaped l' ts) = labelBelow l l' && embedsAll ss ts

  embedsAll : List Shape -> List Shape -> Bool
  embedsAll [] _ = True
  embedsAll (_ :: _) [] = False
  embedsAll (s :: ss) (t :: ts)
      = if embeds s t then embedsAll ss ts else embedsAll (s :: ss) ts

hasUnknown : Shape -> Bool
hasUnknown (Shaped Unsolved _) = True
hasUnknown (Shaped _ cs) = anyUnknown cs
  where
    anyUnknown : List Shape -> Bool
    anyUnknown [] = False
    anyUnknown (c :: cs) = hasUnknown c || anyUnknown cs

-- Two argument lists of one type constructor, compared argument by
-- argument: tuples of a fixed arity, whose order is again a
-- well-quasi-order.
pointwise : List Shape -> List Shape -> Bool
pointwise [] [] = True
pointwise (s :: ss) (t :: ts) = embeds s t && pointwise ss ts
pointwise _ _ = False

-- How the search came to a goal.
data Via = AtTop | ByHint Name | ByLocal

viaHints : Via -> List Name
viaHints (ByHint n) = [n]
viaHints _ = []

-- A goal the search took up, as the path rule reads it.
record Visited where
  constructor MkVisited
  family : Name
  arguments : List Shape
  goal : ClosedTerm
  reachedBy : Via

-- What the search knows of the path that led to the goal it is given: how
-- many of the innermost locals it bound itself, how it came to the goal, and
-- the goals before it, the latest first. Upstream's path (`trying`) starts
-- again under a Π goal; this one is kept whole.
record Track where
  constructor MkTrack
  bound : Nat
  via : Via
  visited : List Visited

-- The earliest goal of the path, scanning back, that embeds in a goal of
-- the given type constructor and arguments, with the hints between them.
grownFrom : Name -> List Shape -> Track -> Maybe (Visited, List Name)
grownFrom fam shapes track = scan (viaHints track.via) track.visited
  where
    scan : List Name -> List Visited -> Maybe (Visited, List Name)
    scan hints [] = Nothing
    scan hints (v :: vs)
        = if v.family == fam && pointwise v.arguments shapes
             then Just (v, hints)
             else scan (viaHints v.reachedBy ++ hints) vs

-- A growth is the search's answer, never a failed branch: every combinator
-- that tries alternatives passes it up rather than trying the next.
isGrowth : Error -> Bool
isGrowth (SearchGrows {}) = True
isGrowth _ = False

searchType : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             FC -> RigCount ->
             (defaults : Bool) -> (trying : List (Term vars)) ->
             (track : Track) ->
             (defining : Name) ->
             (checkDets : Bool) -> (topTy : ClosedTerm) ->
             Env Term vars -> (target : Term vars) -> Core (Term vars)

public export
record ArgInfo (vars : Scope) where
  constructor MkArgInfo
  holeID : Int
  argRig : RigCount
  plicit : PiInfo (Closure vars)
  metaApp : Term vars
  argType : Term vars

export
mkArgs : {vars : _} ->
         {auto c : Ref Ctxt Defs} ->
         {auto u : Ref UST UState} ->
         FC -> RigCount ->
         Env Term vars -> NF vars ->
         Core (List (ArgInfo vars), NF vars)
mkArgs fc rigc env (NBind nfc x (Pi fc' c p ty) sc)
    = do defs <- get Ctxt
         empty <- clearDefs defs
         nm <- genName "sa"
         argTy <- quote empty env ty
         let argRig = rigMult rigc c
         (idx, arg) <- newMeta fc' argRig env nm argTy
                               (Hole (length env) (holeInit False)) False
         setInvertible fc (Resolved idx)
         (rest, restTy) <- mkArgs fc rigc env
                              !(sc defs (toClosure defaultOpts env arg))
         pure (MkArgInfo idx argRig p arg argTy :: rest, restTy)
mkArgs fc rigc env ty = pure ([], ty)

export
impLast : List (ArgInfo vars) -> List (ArgInfo vars)
impLast xs = filter (not . impl) xs ++ filter impl xs
  where
      impl : ArgInfo vs -> Bool
      impl inf
          = case plicit inf of
                 Explicit => False
                 _ => True

searchIfHole : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST UState} ->
               FC ->
               (defaults : Bool) -> List (Term vars) ->
               (ispair : Bool) -> (track : Track) ->
               (defining : Name) -> (topTy : ClosedTerm) -> Env Term vars ->
               (arg : ArgInfo vars) ->
               Core ()
searchIfHole fc defaults trying ispair track def top env arg
    = do let hole = holeID arg
         let rig = argRig arg

         defs <- get Ctxt
         Just gdef <- lookupCtxtExact (Resolved hole) (gamma defs)
              | Nothing => throw (CantSolveGoal fc (gamma !(get Ctxt)) Env.empty top Nothing)
         let Hole _ _ = definition gdef
              | _ => pure () -- already solved
         top' <- if ispair
                    then normaliseScope defs Env.empty (type gdef)
                    else pure top

         argdef <- searchType fc rig defaults trying track def False top' env
                              !(normaliseScope defs env (argType arg))
         logTermNF "auto" 5 "Solved arg" env argdef
         logTermNF "auto" 5 "Arg meta" env (metaApp arg)
         ok <- solveIfUndefined env (metaApp arg) argdef
         if ok
            then pure ()
            else do vs <- unify inTerm fc env (metaApp arg) argdef
                    let [] = constraints vs
                        | _ => throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
                    pure ()

successful : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             List (Core (Term vars)) ->
             Core (List (Either Error (Term vars, Defs, UState)))
successful [] = pure []
successful (elab :: elabs)
    = do ust <- get UST
         defs <- branch
         catch (do -- Run the elaborator
                   res <- elab
                   -- Record post-elaborator state
                   ust' <- get UST
                   defs' <- get Ctxt
                   -- Reset to previous state and try the rest
                   put UST ust
                   put Ctxt defs
                   elabs' <- successful elabs
                   -- Record success, and the state we ended at
                   pure (Right (res, defs', ust') :: elabs'))
               (\err => do put UST ust
                           put Ctxt defs
                           when (isGrowth err) $ throw err
                           elabs' <- successful elabs
                           pure (Left err :: elabs'))

anyOne : {auto c : Ref Ctxt Defs} ->
         {auto u : Ref UST UState} ->
         FC -> Env Term vars -> (topTy : ClosedTerm) ->
         List (Core (Term vars)) ->
         Core (Term vars)
anyOne fc env top [] = throw (CantSolveGoal fc (gamma !(get Ctxt)) Env.empty top Nothing)
anyOne fc env top [elab]
    = catch elab $
         \case
           err@(CantSolveGoal {})   => throw err
           err@(AmbiguousSearch {}) => throw err
           err@(SearchGrows {})     => throw err
           _ => throw $ CantSolveGoal fc (gamma !(get Ctxt)) Env.empty top Nothing
anyOne fc env top (elab :: elabs)
    = handleUnify elab $ \err =>
        if isGrowth err then throw err else anyOne fc env top elabs

exactlyOne : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             FC -> Env Term vars -> (topTy : ClosedTerm) -> (target : NF vars) ->
             List (Core (Term vars)) ->
             Core (Term vars)
exactlyOne fc env top target [elab]
    = catch elab $
         \case
           err@(CantSolveGoal {}) => throw err
           err@(SearchGrows {})   => throw err
           _ => throw $ CantSolveGoal fc (gamma !(get Ctxt)) Env.empty top Nothing
exactlyOne {vars} fc env top target all
    = do elabs <- successful all
         case nubBy ((==) `on` fst) $ rights elabs of
              [(res, defs, ust)] =>
                    do put UST ust
                       put Ctxt defs
                       commit
                       pure res
              [] => throw (CantSolveGoal fc (gamma !(get Ctxt)) Env.empty top Nothing)
              rs => throw (AmbiguousSearch fc env !(quote !(get Ctxt) env target)
                             !(traverse normRes rs))
  where
    normRes : (Term vars, Defs, UState) -> Core (Term vars)
    normRes (tm, defs, _) = normaliseHoles defs env tm

-- We can only resolve things which are at unrestricted multiplicity. Expression
-- search happens before linearity checking and we can't guarantee that just
-- because something is apparently available now, it will be available by the
-- time we get to linearity checking.
-- It's also fine to use anything if we're working at multiplicity 0
getUsableEnv : FC -> RigCount ->
               SizeOf done ->
               Env Term vars ->
               -- TODO this will be `vars <>< done` after refactoring
               List (Term (done ++ vars), Term (done ++ vars))
getUsableEnv fc rigc p [] = []
getUsableEnv {vars = v :: vs} {done} fc rigc p (b :: env)
   = let rest = getUsableEnv fc rigc (sucR p) env in
         if (multiplicity b == top || isErased rigc)
            then let 0 var = mkIsVar (hasLength p) in
                     (Local (binderLoc b) Nothing _ var,
                       rewrite appendAssociative done (Scope.single v) vs in
                          weakenNs (sucR p) (binderType b)) ::
                               rewrite appendAssociative done (Scope.single v) vs in rest
            else rewrite appendAssociative done (Scope.single v) vs in rest

-- A local is usable if it contains no holes in a determining argument position
usableLocal : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              FC -> (defaults : Bool) ->
              Env Term vars -> (locTy : NF vars) -> Core Bool
-- pattern variables count as concrete things!
usableLocal loc defaults env (NApp fc (NMeta (PV {}) _ _) args)
    = pure True
usableLocal loc defaults env (NApp fc (NMeta {}) args)
    = pure False
usableLocal {vars} loc defaults env (NTCon _ n _ args)
    = do sd <- getSearchData loc (not defaults) n
         usableLocalArg 0 (detArgs sd) (map snd args)
  -- usable if none of the determining arguments of the local's type are
  -- holes
  where
    usableLocalArg : Nat -> NatSet -> List (Closure vars) -> Core Bool
    usableLocalArg i dets [] = pure True
    usableLocalArg i dets (c :: cs)
        = if i `elem` dets
             then do defs <- get Ctxt
                     u <- usableLocal loc defaults env !(evalClosure defs c)
                     if u
                        then usableLocalArg (1 + i) dets cs
                        else pure False
             else usableLocalArg (1 + i) dets cs
usableLocal loc defaults env (NDCon _ n _ _ args)
    = do defs <- get Ctxt
         us <- traverse (usableLocal loc defaults env)
                        !(traverse (evalClosure defs) $ map snd args)
         pure (all id us)
usableLocal loc defaults env (NApp _ (NLocal {}) args)
    = do defs <- get Ctxt
         us <- traverse (usableLocal loc defaults env)
                        !(traverse (evalClosure defs) $ map snd args)
         pure (all id us)
usableLocal loc defaults env (NBind fc x (Pi {}) sc)
    = do defs <- get Ctxt
         usableLocal loc defaults env
                !(sc defs (toClosure defaultOpts env (Erased fc Placeholder)))
usableLocal loc defaults env (NErased {}) = pure False
usableLocal loc _ _ _ = pure True

searchLocalWith : {vars : _} ->
                  {auto c : Ref Ctxt Defs} ->
                  {auto u : Ref UST UState} ->
                  FC -> RigCount ->
                  (defaults : Bool) -> List (Term vars) ->
                  (track : Track) ->
                  (defining : Name) -> (topTy : ClosedTerm) ->
                  Env Term vars -> (Term vars, Term vars) ->
                  (target : NF vars) -> Core (Term vars)
searchLocalWith {vars} fc rigc defaults trying track def top env (prf, ty) target
    = do defs <- get Ctxt
         nty <- nf defs env ty
         findPos defs pure nty target
  where
    clearEnvType : {idx : Nat} -> (0 p : IsVar nm idx vs) ->
                   FC -> Env Term vs -> Env Term vs
    clearEnvType First fc (b :: env)
        = Lam (binderLoc b) (multiplicity b) Explicit (Erased fc Placeholder) :: env
    clearEnvType (Later p) fc (b :: env) = b :: clearEnvType p fc env

    clearEnv : Term vars -> Env Term vars -> Env Term vars
    clearEnv (Local fc _ idx p) env
        = clearEnvType p fc env
    clearEnv _ env = env

    findDirect : Defs ->
                 (Term vars -> Core (Term vars)) ->
                 NF vars ->  -- local's type
                 (target : NF vars) ->
                 Core (Term vars)
    findDirect defs f ty target
        = do (args, appTy) <- mkArgs fc rigc env ty
             fprf <- f prf
             logTermNF "auto" 10 "Trying" env fprf
             logNF "auto" 10 "Type" env ty
             logNF "auto" 10 "For target" env target
             ures <- unify inTerm fc env target appTy
             let [] = constraints ures
                 | _ => throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
             -- We can only use the local if its type is not an unsolved hole
             if !(usableLocal fc defaults env ty)
                then do
                   let candidate = apply fc fprf (map metaApp args)
                   logTermNF "auto" 10 "Local var candidate " env candidate
                   -- Clear the local from the environment to avoid getting
                   -- into a loop repeatedly applying it
                   let env' = clearEnv prf env
                   -- Work right to left, because later arguments may solve
                   -- earlier ones by unification
                   traverse_ (searchIfHole fc defaults trying False
                                  ({ via := ByLocal } track) def top env')
                            (impLast args)
                   pure candidate
                else do logNF "auto" 10 "Can't use " env ty
                        throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)

    findPos : Defs ->
              (Term vars -> Core (Term vars)) ->
              NF vars ->  -- local's type
              (target : NF vars) ->
              Core (Term vars)
    findPos defs f nty@(NTCon pfc pn _ [(_, xty), (_, yty)]) target
        = tryUnifyUnambig (findDirect defs f nty target) $
             do fname <- maybe (throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing))
                               pure
                               !fstName
                sname <- maybe (throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing))
                               pure
                               !sndName
                if !(isPairType pn)
                   then do empty <- clearDefs defs
                           xtytm <- quote empty env xty
                           ytytm <- quote empty env yty
                           exactlyOne fc env top target
                            [(do xtynf <- evalClosure defs xty
                                 findPos defs
                                     (\arg => normalise defs env $ apply fc (Ref fc Func fname)
                                                        [xtytm,
                                                         ytytm,
                                                         !(f arg)])
                                     xtynf target),
                             (do ytynf <- evalClosure defs yty
                                 findPos defs
                                     (\arg => normalise defs env $ apply fc (Ref fc Func sname)
                                                        [xtytm,
                                                         ytytm,
                                                         !(f arg)])
                                     ytynf target)]
                   else throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
    findPos defs f nty target
        = findDirect defs f nty target

searchLocalVars : {vars : _} ->
                  {auto c : Ref Ctxt Defs} ->
                  {auto u : Ref UST UState} ->
                  FC -> RigCount ->
                  (defaults : Bool) -> List (Term vars) ->
                  (track : Track) ->
                  (defining : Name) -> (topTy : ClosedTerm) ->
                  Env Term vars ->
                  (target : NF vars) -> Core (Term vars)
searchLocalVars fc rig defaults trying track def top env target
    = do let elabs = map (\t => searchLocalWith fc rig defaults trying track def
                                              top env t target)
                         (getUsableEnv fc rig zero env)
         exactlyOne fc env top target elabs

isPairNF : {auto c : Ref Ctxt Defs} ->
           Env Term vars -> NF vars -> Defs -> Core Bool
isPairNF env (NTCon _ n _ _) defs
    = isPairType n
isPairNF env (NBind fc b (Pi {}) sc) defs
    = isPairNF env !(sc defs (toClosure defaultOpts env (Erased fc Placeholder))) defs
isPairNF _ _ _ = pure False

searchName : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             FC -> RigCount ->
             (defaults : Bool) -> List (Term vars) ->
             (track : Track) ->
             (defining : Name) -> (topTy : ClosedTerm) ->
             Env Term vars -> (target : NF vars) ->
             (Name, GlobalDef) ->
             Core (Term vars)
searchName fc rigc defaults trying track def top env target (n, ndef)
    = do defs <- get Ctxt
         when (not (visibleInAny (!getNS :: !getNestedNS)
                                 (fullname ndef) (collapseDefault $ visibility ndef))) $
            throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
         when (BlockedHint `elem` flags ndef) $
            throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)

         let ty = type ndef
         when (isErased ty) $
            throw (CantSolveGoal fc (gamma defs) [] top Nothing)

         nty <- nf defs env (embed ty)
         logNF "auto" 10 ("Searching Name " ++ show n) env nty
         (args, appTy) <- mkArgs fc rigc env nty
         ures <- unify inTerm fc env target appTy
         let [] = constraints ures
             | _ => throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
         ispair <- isPairNF env nty defs
         let candidate = apply fc (Ref fc (getDefNameType ndef) n) (map metaApp args)
         logTermNF "auto" 10 "Candidate " env candidate
         -- Work right to left, because later arguments may solve earlier
         -- dependencies by unification
         traverse_ (searchIfHole fc defaults trying ispair
                                 ({ via := ByHint n } track) def top env)
                  (impLast args)
         pure candidate

searchNames : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST UState} ->
              FC -> RigCount ->
              (defaults : Bool) -> List (Term vars) ->
              (track : Track) ->
              (defining : Name) -> (topTy : ClosedTerm) ->
              Env Term vars -> Bool -> List Name ->
              (target : NF vars) -> Core (Term vars)
searchNames fc rigc defaults trying track defining topty env ambig [] target
    = throw (CantSolveGoal fc (gamma !(get Ctxt)) Env.empty topty Nothing)
searchNames fc rigc defaults trying track defining topty env ambig (n :: ns) target
    = do defs <- get Ctxt
         visnsm <- traverse (visible (gamma defs) (currentNS defs :: nestedNS defs)) (n :: ns)
         let visns = mapMaybe id visnsm
         let elabs = map (searchName fc rigc defaults trying track defining topty env target) visns
         if ambig
            then anyOne fc env topty elabs
            else exactlyOne fc env topty target elabs
  where
    visible : Context ->
              List Namespace -> Name -> Core (Maybe (Name, GlobalDef))
    visible gam nspace n
        = do Just def <- lookupCtxtExact n gam
                  | Nothing => pure Nothing
             if visibleInAny nspace n (collapseDefault $ visibility def)
                then pure $ Just (n, def)
                else pure $ Nothing

concreteDets : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               FC -> Bool ->
               Env Term vars -> (top : ClosedTerm) ->
               (pos : Nat) -> (dets : NatSet) ->
               (args : List (Closure vars)) ->
               Core ()
concreteDets fc defaults env top pos dets [] = pure ()
concreteDets {vars} fc defaults env top pos dets (arg :: args)
    = do when (pos `elem` dets) $ do
           defs <- get Ctxt
           argnf <- evalClosure defs arg
           logNF "auto.determining" 10
             "Checking that the following argument is concrete"
             env argnf
           concrete defs argnf True
         concreteDets fc defaults env top (1 + pos) dets args
  where
    concrete : Defs -> NF vars -> (atTop : Bool) -> Core ()
    concrete defs (NBind nfc x b sc) atTop
        = do scnf <- sc defs (toClosure defaultOpts env (Erased nfc Placeholder))
             concrete defs scnf False
    concrete defs (NTCon nfc n a args) atTop
        = do sd <- getSearchData nfc False n
             let args' = NatSet.take (detArgs sd) args
             traverse_ (\ parg => do argnf <- evalClosure defs parg
                                     concrete defs argnf False) (map snd args')
    concrete defs (NDCon nfc n t a args) atTop
        = do traverse_ (\ parg => do argnf <- evalClosure defs parg
                                     concrete defs argnf False) (map snd args)
    concrete defs (NApp _ (NMeta n i _) _) True
        = do Just (Hole _ b) <- lookupDefExact n (gamma defs)
                  | _ => throw (DeterminingArg fc n i Env.empty top)
             unless (implbind b) $
                  throw (DeterminingArg fc n i Env.empty top)
    concrete defs (NApp _ (NMeta n i _) _) False
        = do Just (Hole _ b) <- lookupDefExact n (gamma defs)
                  | def => throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
             unless (implbind b) $
                  throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
    concrete defs tm atTop = pure ()

checkConcreteDets : {vars : _} ->
                    {auto c : Ref Ctxt Defs} ->
                    FC -> Bool ->
                    Env Term vars -> (top : ClosedTerm) ->
                    NF vars ->
                    Core ()
checkConcreteDets fc defaults env top (NTCon tfc tyn a args)
    = do defs <- get Ctxt
         if !(isPairType tyn)
            then case args of
                      [(_, aty), (_, bty)] =>
                          do anf <- evalClosure defs aty
                             bnf <- evalClosure defs bty
                             checkConcreteDets fc defaults env top anf
                             checkConcreteDets fc defaults env top bnf
                      _ => do sd <- getSearchData fc defaults tyn
                              concreteDets fc defaults env top 0 (detArgs sd) (map snd args)
            else
              do sd <- getSearchData fc defaults tyn
                 log "auto.determining" 10 $
                   "Determining arguments for " ++ show !(toFullNames tyn)
                   ++ " " ++ show (detArgs sd)
                 concreteDets fc defaults env top 0 (detArgs sd) (map snd args)
checkConcreteDets fc defaults env top _
    = pure ()

-- A goal convertible with one before it on its path repeats it: that step
-- fails, as an ordinary failure, and the search tries what else it has.
abandonIfCycle : {vars : _} ->
                 {auto c : Ref Ctxt Defs} ->
                 FC -> ClosedTerm ->
                 Env Term vars -> Term vars -> List (Term vars) ->
                 Core ()
abandonIfCycle fc top env tm [] = pure ()
abandonIfCycle fc top env tm (ty :: tys)
    = do defs <- get Ctxt
         if !(convert defs env tm ty)
            then throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
            else abandonIfCycle fc top env tm tys

-- Declared at the top
searchType fc rigc defaults trying track def checkdets top env (Bind nfc x b@(Pi fc' c p ty) sc)
    = pure (Bind nfc x (Lam fc' c p ty)
             !(searchType fc rigc defaults [] ({ bound $= S } track) def checkdets top
                          (b :: env) sc))
searchType fc rigc defaults trying track def checkdets top env (Bind nfc x b@(Let fc' c val ty) sc)
    = pure (Bind nfc x b
             !(searchType fc rigc defaults [] ({ bound $= S } track) def checkdets top
                          (b :: env) sc))
searchType {vars} fc rigc defaults trying track def checkdets top env target
    = do defs <- get Ctxt
         abandonIfCycle fc top env target trying
         let trying' = target :: trying
         nty <- nf defs env target
         case nty of
              NTCon tfc tyn a args =>
                  if a == length args
                     then do logNF "auto" 10 "Next target" env nty
                             track' <- visit tyn (map snd args)
                             sd <- getSearchData fc defaults tyn
                             -- Check determining arguments are okay for 'args'
                             when checkdets $
                                 checkConcreteDets fc defaults env top
                                                   (NTCon tfc tyn a args)
                             if defaults && checkdets
                                then tryGroups track' Nothing nty (hintGroups sd)
                                else tryUnifyUnambig
                                       (searchLocalVars fc rigc defaults trying' track' def top env nty)
                                       (tryGroups track' Nothing nty (hintGroups sd))
                     else throw (CantSolveGoal fc (gamma defs) Env.empty top Nothing)
              _ => do logNF "auto" 10 "Next target: " env nty
                      searchLocalVars fc rigc defaults trying' track def top env nty
  where
    -- The path rule, before the goal is taken up: an earlier goal of the
    -- same type constructor that embeds in this one stops the search (the
    -- convertible ones were caught above); else the goal joins the path.
    visit : Name -> List (Closure vars) -> Core Track
    visit tyn args
        = do defs <- get Ctxt
             tms <- traverse (quote defs env) args
             let shapes = map (shapeIn track.bound 0) tms
             let goal = abstractEnvType fc env target
             case grownFrom tyn shapes track of
                  Nothing => pure ({ visited $= (MkVisited tyn shapes goal track.via ::) } track)
                  Just (earlier, hints) =>
                     let growth = if any hasUnknown earlier.arguments || any hasUnknown shapes
                                     then ThroughUnknowns
                                     else Settled in
                         throw (SearchGrows fc (gamma defs) growth earlier.goal goal hints)

    -- Take the earliest error message (that's when we look inside pairs,
    -- typically, and it's best to be more precise)
    tryGroups : Track -> Maybe Error ->
                NF vars -> List (Bool, List Name) -> Core (Term vars)
    tryGroups track' (Just err) nty [] = throw err
    tryGroups track' Nothing nty [] = throw (CantSolveGoal fc (gamma !(get Ctxt)) Env.empty top Nothing)
    tryGroups track' merr nty ((ambigok, g) :: gs)
        = tryUnifyUnambig'
             (do logC "auto" 5
                        (do gn <- traverse getFullName g
                            pure ("Search: Trying " ++ show (length gn) ++
                                           " names " ++ show gn))
                 logNF "auto" 5 "For target" env nty
                 tryNoDefaultsFirst $ \d =>
                   searchNames fc rigc d (target :: trying) track' def top env ambigok g nty)
             (\err => tryGroups track' (Just $ fromMaybe err merr) nty gs)

-- Declared in Core.Unify as:
-- search : {vars : _} ->
--          {auto c : Ref Ctxt Defs} ->
--          {auto u : Ref UST UState} ->
--          FC -> RigCount ->
--          (defaults : Bool) ->
--          (defining : Name) -> (topTy : Term vars) -> Env Term vars ->
--          Core (Term vars)
Core.Unify.search fc rigc defaults def top env
    = do logTermNF "auto" 3 "Initial target: " env top
         log "auto" 3 $ "Running search with defaults " ++ show defaults
         tm <- searchType fc rigc defaults [] (MkTrack 0 AtTop []) def
                          True (abstractEnvType fc env top) env
                          top
         logTermNF "auto" 3 "Result" env tm
         pure tm
