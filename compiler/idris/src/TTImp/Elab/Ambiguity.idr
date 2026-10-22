-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module TTImp.Elab.Ambiguity

import Core.Env
import Core.Metadata
import Core.Reflect
import Core.Unify
import Core.Value

import Idris.REPL.Opts
import Idris.Syntax
import Idris.Syntax.Builtin

import TTImp.Elab.Check
import TTImp.Elab.Delayed
import TTImp.TTImp

import Data.String
import Data.Vect

import Libraries.Data.UserNameMap
import Libraries.Data.WithDefault

%default covering

export
expandAmbigName : {vars : _} ->
                  {auto c : Ref Ctxt Defs} ->
                  {auto e : Ref EST (EState vars)} ->
                  ElabMode -> NestedNames vars -> Env Term vars -> RawImp ->
                  List (FC, Maybe (Maybe Name), RawImp) ->
                  RawImp -> Maybe (Glued vars) -> Core RawImp
expandAmbigName (InLHS _) nest env orig args (IBindVar fc n) exp
    = do est <- get EST
         if n `elem` lhsPatVars est
            then pure $ IMustUnify fc NonLinearVar orig
            else pure $ orig
expandAmbigName mode nest env orig args (IVar fc x) exp
   = case lookup x (names nest) of
          Just _ => do log "elab.ambiguous" 20 $ "Nested " ++ show x
                       pure orig
          Nothing => do
             defs <- get Ctxt
             case defined x env of
                  Just _ =>
                    if isNil args || notLHS mode
                       then do log "elab.ambiguous" 20 $ "Defined in env " ++ show x
                               pure $ orig
                       else pure $ IMustUnify fc VarApplied orig
                  Nothing =>
                     do est <- get EST
                        primNs <- getPrimNames
                        let prims = primNamesToList primNs
                        let primApp = isPrimName prims x
                        case lookupUN (userNameRoot x) (unambiguousNames est) of
                          Just xr => do
                            log "elab.ambiguous" 50 $ "unambiguous: " ++ show (fst xr)
                            pure $ mkAlt primApp est xr
                          Nothing => do
                            ns <- lookupCtxtName x (gamma defs)
                            ns' <- filterM visible ns
                            case ns' of
                               [] => do log "elab.ambiguous" 50 $ "Failed to find " ++ show orig
                                        pure orig
                               [nalt] =>
                                     do log "elab.ambiguous" 40 $ "Only one " ++ show (fst nalt)
                                        pure $ mkAlt primApp est nalt
                               nalts =>
                                     do log "elab.ambiguous" 10 $
                                          "Ambiguous: " ++ joinBy ", " (map (show . fst) nalts)
                                        pure $ IAlternative fc
                                                      (uniqType x args primNs)
                                                      (map (mkAlt primApp est) nalts)
  where
    lookupUN : Maybe UserName -> UserNameMap a -> Maybe a
    lookupUN Nothing _ = Nothing
    lookupUN (Just n) sm = lookup n sm

    visible : (Name, Int, GlobalDef) -> Core Bool
    visible (n, i, def)
        = do let NS ns x = fullname def
                 | _ => pure True
             if !(isVisible ns)
                then pure $ visibleInAny (!getNS :: !getNestedNS) (NS ns x)
                                         (collapseDefault $ visibility def)
                else pure False

    -- If there's multiple alternatives and all else fails, resort to using
    -- the primitive directly
    -- The order of the arguments have a big effect on case-tree size
    uniqType : Name -> List (FC, Maybe (Maybe Name), RawImp) -> PrimNames -> AltType
    uniqType n [(_, _, IPrimVal fc (BI x))] (MkPrimNs (Just fi) _ _ _ _ _ _)
        = UniqueDefault (IPrimVal fc (BI x))
    uniqType n [(_, _, IPrimVal fc (Str x))] (MkPrimNs _ (Just si) _ _ _ _ _)
        = UniqueDefault (IPrimVal fc (Str x))
    uniqType n [(_, _, IPrimVal fc (Ch x))] (MkPrimNs _ _ (Just ci) _ _ _ _)
        = UniqueDefault (IPrimVal fc (Ch x))
    uniqType n [(_, _, IPrimVal fc (Db x))] (MkPrimNs _ _ _ (Just di) _ _ _)
        = UniqueDefault (IPrimVal fc (Db x))
    uniqType n [(_, _, IQuote fc tm)] (MkPrimNs _ _ _ _ (Just dt) _ _)
        = UniqueDefault (IQuote fc tm)
        {-
    uniqType n [(_, _, IQuoteName fc tm)] (MkPrimNs _ _ _ _ _ (Just dn) _)
        = UniqueDefault (IQuoteName fc tm)
    uniqType n [(_, _, IQuoteDecl fc tm)] (MkPrimNs _ _ _ _ _ _ (Just ddl))
        = UniqueDefault (IQuoteDecl fc tm)
        -}
    uniqType _ _ _ = Unique

    buildAlt : RawImp -> List (FC, Maybe (Maybe Name), RawImp) ->
               RawImp
    buildAlt f [] = f
    buildAlt f ((fc', Nothing, a) :: as)
        = buildAlt (IApp fc' f a) as
    buildAlt f ((fc', Just Nothing, a) :: as)
        = buildAlt (IAutoApp fc' f a) as
    buildAlt f ((fc', Just (Just i), a) :: as)
        = buildAlt (INamedApp fc' f i a) as

    -- If it's not a constructor application, dot it
    wrapDot : Bool -> EState vars ->
              ElabMode -> Name -> List RawImp -> Def -> RawImp -> RawImp
    wrapDot _ _ _ _ _ (DCon {}) tm = tm
    wrapDot _ _ _ _ _ (TCon {}) tm = tm
    -- Leave primitive applications alone, because they'll be inlined
    -- before compiling the case tree
    wrapDot prim est (InLHS _) n' [arg] _ tm
       = if n' == Resolved (defining est) || prim
            then tm
            else IMustUnify fc NotConstructor tm
    wrapDot prim est (InLHS _) n' _ _ tm
       = if n' == Resolved (defining est)
            then tm
            else IMustUnify fc NotConstructor tm
    wrapDot _ _ _ _ _ _ tm = tm

    notLHS : ElabMode -> Bool
    notLHS (InLHS _) = False
    notLHS _ = True

    mkTerm : Bool -> EState vars -> Name -> GlobalDef -> RawImp
    mkTerm prim est n def
        = if (Context.Macro `elem` flags def) && notLHS mode
             then alternativeFirstSuccess $ reverse $
                    allSplits args <&> \(macroArgs, extArgs) =>
                      (IRunElab fc False $ ICoerced fc $ IVar fc n `buildAlt` macroArgs) `buildAlt` extArgs
             else wrapDot prim est mode n (map (snd . snd) args)
                    (definition def) (buildAlt (IVar fc n) args)
      where
        -- All splits of the original list starting from the (empty, full) finishing with (full, empty)
        allSplits : (l : List a) -> Vect (S $ length l) (List a, List a)
        allSplits []           = [([], [])]
        allSplits full@(x::xs) = ([], full) :: (mapFst (x::) <$> allSplits xs)

        alternativeFirstSuccess : forall n. Vect (S n) RawImp -> RawImp
        alternativeFirstSuccess [x] = x
        alternativeFirstSuccess xs  = IAlternative fc FirstSuccess $ toList xs

    mkAlt : Bool -> EState vars -> (Name, Int, GlobalDef) -> RawImp
    mkAlt prim est (fullname, i, gdef)
        = mkTerm prim est (Resolved i) gdef

expandAmbigName mode nest env orig args (IApp fc f a) exp
    = expandAmbigName mode nest env orig
                      ((fc, Nothing, a) :: args) f exp
expandAmbigName mode nest env orig args (INamedApp fc f n a) exp
    = expandAmbigName mode nest env orig
                      ((fc, Just (Just n), a) :: args) f exp
expandAmbigName mode nest env orig args (IAutoApp fc f a) exp
    = expandAmbigName mode nest env orig
                      ((fc, Just Nothing, a) :: args) f exp
expandAmbigName elabmode nest env orig args tm exp
    = do log "elab.ambiguous" 50 $ "No ambiguity " ++ show orig
         pure orig

stripDelay : NF vars -> NF vars
stripDelay (NDelayed fc r t) = stripDelay t
stripDelay tm = tm

data TypeMatch = Concrete | Poly | NoMatch

Show TypeMatch where
  show Concrete = "Concrete"
  show Poly = "Poly"
  show NoMatch = "NoMatch"

mutual
  mightMatchD : {auto c : Ref Ctxt Defs} ->
                {vars : _} ->
                Defs -> NF vars -> ClosedNF -> Core TypeMatch
  mightMatchD defs l r
      = mightMatch defs (stripDelay l) (stripDelay r)

  mightMatchArg : {auto c : Ref Ctxt Defs} ->
                  {vars : _} ->
                  Defs ->
                  Closure vars -> ClosedClosure ->
                  Core Bool
  mightMatchArg defs l r
      = pure $ case !(mightMatchD defs !(evalClosure defs l) !(evalClosure defs r)) of
             NoMatch => False
             _ => True

  mightMatchArgs : {auto c : Ref Ctxt Defs} ->
                   {vars : _} ->
                   Defs ->
                   Scopeable (Closure vars) -> Scopeable ClosedClosure ->
                   Core Bool
  mightMatchArgs defs [] [] = pure True
  mightMatchArgs defs (x :: xs) (y :: ys)
      = do amatch <- mightMatchArg defs x y
           if amatch
              then mightMatchArgs defs xs ys
              else pure False
  mightMatchArgs _ _ _ = pure False

  mightMatch : {auto c : Ref Ctxt Defs} ->
               {vars : _} ->
               Defs -> NF vars -> ClosedNF -> Core TypeMatch
  mightMatch defs target (NBind fc n (Pi {}) sc)
      = mightMatchD defs target !(sc defs (toClosure defaultOpts Env.empty (Erased fc Placeholder)))
  mightMatch defs (NBind {}) (NBind {}) = pure Poly -- lambdas might match
  mightMatch defs (NTCon _ n a args) (NTCon _ n' a' args')
      = if n == n'
           then do amatch <- mightMatchArgs defs (map snd args) (map snd args')
                   if amatch then pure Concrete else pure NoMatch
           else pure NoMatch
  mightMatch defs (NDCon _ n t a args) (NDCon _ n' t' a' args')
      = if t == t'
           then do amatch <- mightMatchArgs defs (map snd args) (map snd args')
                   if amatch then pure Concrete else pure NoMatch
           else pure NoMatch
  mightMatch defs (NPrimVal _ x) (NPrimVal _ y)
      = if x == y then pure Concrete else pure NoMatch
  mightMatch defs (NType {}) (NType {}) = pure Concrete
  mightMatch defs (NApp {}) _ = pure Poly
  mightMatch defs (NErased {}) _ = pure Poly
  mightMatch defs _ (NApp {}) = pure Poly
  mightMatch defs _ (NErased {}) = pure Poly
  mightMatch _ _ _ = pure NoMatch

-- Return true if the given name could return something of the given target type
couldBeName : {auto c : Ref Ctxt Defs} ->
              {vars : _} ->
              Defs -> NF vars -> Name -> Core TypeMatch
couldBeName defs target n
    = case !(lookupTyExact n (gamma defs)) of
           Nothing => pure Poly -- could be a local name, don't rule it out
           Just ty => mightMatchD defs target !(nf defs Env.empty ty)

couldBeFn : {auto c : Ref Ctxt Defs} ->
            {vars : _} ->
            Defs -> NF vars -> RawImp -> Core TypeMatch
couldBeFn defs ty (IVar _ n) = couldBeName defs ty n
couldBeFn defs ty (IAlternative {}) = pure Concrete
couldBeFn defs ty _ = pure Poly

-- Returns Nothing if there's no possibility the expression's type matches
-- the target type
-- Just (True, app) if it's a match on concrete return type
-- Just (False, app) if it might be a match due to being polymorphic
couldBe : {auto c : Ref Ctxt Defs} ->
          {vars : _} ->
          Defs -> NF vars -> RawImp -> Core (Maybe (Bool, RawImp))
couldBe {vars} defs ty@(NTCon _ n _ _) app
   = case !(couldBeFn {vars} defs ty (getFn app)) of
          Concrete => pure $ Just (True, app)
          Poly => pure $ Just (False, app)
          NoMatch => pure Nothing
couldBe {vars} defs ty@(NPrimVal {}) app
   = case !(couldBeFn {vars} defs ty (getFn app)) of
          Concrete => pure $ Just (True, app)
          Poly => pure $ Just (False, app)
          NoMatch => pure Nothing
couldBe {vars} defs ty@(NType {}) app
   = case !(couldBeFn {vars} defs ty (getFn app)) of
          Concrete => pure $ Just (True, app)
          Poly => pure $ Just (False, app)
          NoMatch => pure Nothing
couldBe defs ty app = pure $ Just (False, app)


notOverloadable : Defs -> (Bool, RawImp) -> Core Bool
notOverloadable defs (True, fn) = pure True
notOverloadable defs (concrete, fn) = notOverloadableFn (getFn fn)
  where
    notOverloadableFn : RawImp -> Core Bool
    notOverloadableFn (IVar _ n)
        = do Just gdef <- lookupCtxtExact n (gamma defs)
                  | Nothing => pure True
             pure False -- If the name exists, and doesn't have a concrete type
                        -- but another possibility does, remove it from the set
                        -- no matter what
                        -- (TODO: Consider whether %allow_overloads should exist)
                        -- (not (Overloadable `elem` flags gdef))
    notOverloadableFn _ = pure True

filterCore : (a -> Core Bool) -> List a -> Core (List a)
filterCore f [] = pure []
filterCore f (x :: xs)
    = do p <- f x
         xs' <- filterCore f xs
         if p then pure (x :: xs')
              else pure xs'

pruneByType : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              Env Term vars -> NF vars -> List RawImp ->
              Core (List RawImp)
pruneByType env target alts
    = do defs <- get Ctxt
         matches_in <- traverse (couldBe defs (stripDelay target)) alts
         let matches = mapMaybe id matches_in
         logNF "elab.prune" 10 "Prune by" env target
         log "elab.prune" 10 (show matches)
         res <- if any Builtin.fst matches
                -- if there's any concrete matches, drop the non-concrete
                -- matches marked as '%allow_overloads' from the possible set
                   then do keep <- filterCore (notOverloadable defs) matches
                           log "elab.prune" 10 $ "Keep " ++ show keep
                           pure (map snd keep)
                   else pure (map snd matches)
         if isNil res
            then pure alts -- if none of them work, better to show all the errors
            else pure res

getName : RawImp -> Maybe Name
getName (IVar _ n) = Just n
getName (IApp _ f _) = getName f
getName (INamedApp _ f _ _) = getName f
getName (IAutoApp _ f _) = getName f
getName _ = Nothing

-- The elaborators of an ambiguous application, with a default and without,
-- given the cell of delayed elaborators and the expected type, which a
-- retry evaluates again (see delayOnFailure). Each is a function of its
-- own rather than the body of a lambda in checkAlternative: a local
-- definition is applied to everything its parent binds, so one used in
-- the lambda would capture checkAlternative's cell.
checkDefaultDelayed : {vars : _} ->
                      {auto c : Ref Ctxt Defs} ->
                      {auto m : Ref MD Metadata} ->
                      {auto u : Ref UST UState} ->
                      {auto dl : Ref DLY DelayedElabs} ->
                      {auto e : Ref EST (EState vars)} ->
                      {auto s : Ref Syn SyntaxInfo} ->
                      {auto o : Ref ROpts REPLOpts} ->
                      RigCount -> ElabInfo ->
                      NestedNames vars -> Env Term vars ->
                      FC -> (def : RawImp) -> List RawImp -> UnifyInfo ->
                      (delayed : Bool) -> (expected : Glued vars) ->
                      Core (Term vars, Glued vars)
checkDefaultDelayed rig elabinfo nest env fc def alts solvemode delayed expected
    = do solveConstraints solvemode Normal
         logGlueNF "elab.ambiguous" 5 (fastConcat
           [ "Ambiguous elaboration at ", show fc, ":\n"
           , unlines (map (("  " ++) . show) alts)
           , "With default. Target type "
           ]) env expected
         alts' <- pruneByType env !(getNF expected) alts
         log "elab.prune" 5 $
           "Pruned " ++ show (minus (length alts) (length alts')) ++ " alts."
           ++ " Kept:\n" ++ unlines (map show alts')

         if delayed -- use the default if there's still ambiguity
            then try
                   (exactlyOne' False fc env
                       (map (\t =>
                          (getName t,
                           checkImp rig elabinfo
                                    nest env t
                                    (Just expected))) alts'))
                   (do log "elab.ambiguous" 5 "All failed, running default"
                       checkImp rig elabinfo
                                    nest env def (Just expected))
            else exactlyOne' True fc env
                  (map (\t =>
                    (getName t,
                     checkImp rig elabinfo
                              nest env t (Just expected)))
                     alts')

checkAlternativeDelayed : {vars : _} ->
                          {auto c : Ref Ctxt Defs} ->
                          {auto m : Ref MD Metadata} ->
                          {auto u : Ref UST UState} ->
                          {auto dl : Ref DLY DelayedElabs} ->
                          {auto e : Ref EST (EState vars)} ->
                          {auto s : Ref Syn SyntaxInfo} ->
                          {auto o : Ref ROpts REPLOpts} ->
                          RigCount -> ElabInfo ->
                          NestedNames vars -> Env Term vars ->
                          FC -> AltType -> List RawImp -> UnifyInfo ->
                          (delayed : Bool) -> (expected : Glued vars) ->
                          Core (Term vars, Glued vars)
checkAlternativeDelayed rig elabinfo nest env fc uniq alts solvemode delayed expected
    = do alts' <- pruneByType env !(getNF expected) alts

         logGlueNF "elab.ambiguous" 5 (fastConcat
             [ "Ambiguous elaboration"
             , " (kept ", show (length alts'), " out of "
             , show (length alts), " candidates)"
             , " (", if delayed then "" else "not ", "delayed)"
             , " at ", show fc, ":\n"
             , unlines (map show alts')
             , "Target type "
             ]) env expected
         let tryall = case uniq of
                           FirstSuccess => anyOne fc
                           _ => exactlyOne' (not delayed) fc env
         tryall (map (\t =>
             (getName t,
              do res <- checkImp rig elabinfo
                                 nest env t (Just expected)
                 -- Do it twice for interface resolution;
                 -- first pass gets the determining argument
                 -- (maybe rethink this, there should be a better
                 -- way that allows one pass)
                 solveConstraints solvemode Normal
                 solveConstraints solvemode Normal
                 log "elab.ambiguous" 10 $ show (getName t) ++ " success"
                 logTermNF "elab.ambiguous" 10 "Result" env (fst res)
                 pure res)) alts')

export
checkAlternative : {vars : _} ->
                   {auto c : Ref Ctxt Defs} ->
                   {auto m : Ref MD Metadata} ->
                   {auto u : Ref UST UState} ->
                   {auto dl : Ref DLY DelayedElabs} ->
                   {auto e : Ref EST (EState vars)} ->
                   {auto s : Ref Syn SyntaxInfo} ->
                   {auto o : Ref ROpts REPLOpts} ->
                   RigCount -> ElabInfo ->
                   NestedNames vars -> Env Term vars ->
                   FC -> AltType -> List RawImp -> Maybe (Glued vars) ->
                   Core (Term vars, Glued vars)
checkAlternative rig elabinfo nest env fc (UniqueDefault def) alts mexpected
    = do expected <- maybe (do nm <- genName "altTy"
                               u <- uniVar fc
                               ty <- metaVar fc erased env nm (TType fc u)
                               pure (gnf env ty))
                           pure mexpected
         let solvemode = case elabMode elabinfo of
                              InLHS c => inLHS
                              _ => inTerm
         delayOnFailure fc rig env expected ambiguous Ambiguity $
             \dl, delayed, exp =>
               checkDefaultDelayed {dl} rig elabinfo nest env fc def alts solvemode delayed exp
checkAlternative rig elabinfo nest env fc uniq alts mexpected
    = do alts' <- maybe (Core.pure [])
                        (\exp => pruneByType env !(getNF exp) alts) mexpected
         case alts' of
           [alt] => checkImp rig elabinfo nest env alt mexpected
           _ =>
             do expected <- maybe (do nm <- genName "altTy"
                                      u <- uniVar fc
                                      ty <- metaVar fc erased env nm (TType fc u)
                                      pure (gnf env ty))
                                  pure mexpected
                let solvemode = case elabMode elabinfo of
                                      InLHS c => inLHS
                                      _ => inTerm
                delayOnFailure fc rig env expected ambiguous Ambiguity $
                     \dl, delayed, exp =>
                       checkAlternativeDelayed {dl} rig elabinfo nest env fc uniq alts solvemode delayed exp

------------------------------------------------------------------------------
-- The syntax that writes a type and a value of it alike
------------------------------------------------------------------------------

||| What an expected type says the syntax for a type and its value alike
||| writes: a type, where the expected type is a universe; a value, where it
||| is any other type already known; and neither yet, where it is an unknown
||| applied, a definition stuck on one, or nothing at all, any of which a
||| later solution may make either.
data Sort = Universe | Known | Unknown

headSort : NF vars -> Sort
headSort (NType {}) = Universe
headSort (NApp _ (NMeta {}) _) = Unknown
headSort (NApp _ (NRef Func _) _) = Unknown
headSort (NForce {}) = Unknown
headSort (NErased {}) = Unknown
headSort _ = Known

sortOf : {auto c : Ref Ctxt Defs} -> {vars : _} -> Glued vars -> Core Sort
sortOf expected = pure (headSort (stripDelay !(getNF expected)))

||| A pair's parts, elaborated once against unknowns of their own: what
||| both of its readings are made of, so that settling which one it is
||| elaborates nothing again.
record PairParts (vars : Scope) where
  constructor MkPairParts
  leftType : Term vars
  rightType : Term vars
  left : Term vars
  right : Term vars

-- The parts are arguments, at the multiplicity a constructor's argument
-- has, and the right one is checked first, as an application whose
-- argument types are unknown checks them, so that the left one has more to
-- resolve its names with.
pairParts : {vars : _} ->
            {auto c : Ref Ctxt Defs} ->
            {auto m : Ref MD Metadata} ->
            {auto u : Ref UST UState} ->
            {auto dl : Ref DLY DelayedElabs} ->
            {auto e : Ref EST (EState vars)} ->
            {auto s : Ref Syn SyntaxInfo} ->
            {auto o : Ref ROpts REPLOpts} ->
            RigCount -> ElabInfo -> NestedNames vars -> Env Term vars ->
            FC -> (l, r : RawImp) -> Core (PairParts vars)
pairParts rig elabinfo nest env fc l r
    = do lty <- partType "pairFst"
         rty <- partType "pairSnd"
         let partInfo = { topLevel := False } elabinfo
         (r', _) <- check (rig |*| top) partInfo nest env r (Just (gnf env rty))
         (l', _) <- check (rig |*| top) partInfo nest env l (Just (gnf env lty))
         pure (MkPairParts lty rty l' r')
  where
    partType : String -> Core (Term vars)
    partType root
        = do nm <- genName root
             u <- uniVar fc
             metaVar fc erased env nm (TType fc u)

-- The type reading of elaborated parts: each part a type, and the whole
-- the pair type over them.
pairTypeOf : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST UState} ->
             RigCount -> ElabInfo -> Env Term vars -> FC -> PairParts vars ->
             Glued vars -> Core (Term vars, Glued vars)
pairTypeOf rig elabinfo env fc parts expected
    = do defs <- get Ctxt
         ul <- uniVar fc
         ur <- uniVar fc
         (l, _) <- checkExp (rig |*| top) elabinfo env fc parts.left
                            (gnf env parts.leftType) (Just (gType fc ul))
         (r, _) <- checkExp (rig |*| top) elabinfo env fc parts.right
                            (gnf env parts.rightType) (Just (gType fc ur))
         pairTy <- getCon fc defs pairname
         u <- uniVar fc
         checkExp rig elabinfo env fc (apply fc pairTy [l, r]) (gType fc u) (Just expected)

-- The value reading of elaborated parts: the pair of them, whose type is
-- the pair type over the unknowns they were elaborated against.
pairOf : {vars : _} ->
         {auto c : Ref Ctxt Defs} ->
         {auto u : Ref UST UState} ->
         RigCount -> ElabInfo -> Env Term vars -> FC -> PairParts vars ->
         Glued vars -> Core (Term vars, Glued vars)
pairOf rig elabinfo env fc parts expected
    = do defs <- get Ctxt
         pairTy <- getCon fc defs pairname
         mkPair <- getCon fc defs mkpairname
         checkExp rig elabinfo env fc
                  (apply fc mkPair [parts.leftType, parts.rightType, parts.left, parts.right])
                  (gnf env (apply fc pairTy [parts.leftType, parts.rightType]))
                  (Just expected)

-- Upstream settles the alternative it builds for this syntax when it is
-- first met, if one reading alone fits, and else when it is retried, with
-- the reading that alone fits adding no constraint, or else its default,
-- the value. So is this site settled, by its expected type's sort when
-- that is known, and by upstream's rule between the two readings when it is
-- not. The readings are given as elaborators of the two terms; what they
-- are made of was elaborated before. Constraints are solved before each
-- try, as upstream's are: before the first by `checkTypeOrValue`, which
-- reads the sort then too, and here before each retry.
settle : {vars : _} ->
         {auto c : Ref Ctxt Defs} ->
         {auto m : Ref MD Metadata} ->
         {auto u : Ref UST UState} ->
         {auto dl : Ref DLY DelayedElabs} ->
         {auto e : Ref EST (EState vars)} ->
         FC -> Env Term vars -> UnifyInfo -> (delayed : Bool) -> Glued vars ->
         (asType, asValue : (Maybe Name, Core (Term vars, Glued vars))) ->
         Core (Term vars, Glued vars)
settle fc env solvemode delayed expected asType asValue
    = do when delayed $ solveConstraints solvemode Normal
         case !(sortOf expected) of
              Universe => snd asType
              Known => snd asValue
              Unknown =>
                if delayed
                   then try (exactlyOne' False fc env [asType, asValue]) (snd asValue)
                   else exactlyOne' True fc env [asType, asValue]

-- A pair whose parts are elaborated, settled each time it is tried. A
-- function of its own, not the body of the lambda that delays it, so that
-- the lambda captures no cell of delayed elaborators.
settlePair : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto m : Ref MD Metadata} ->
             {auto u : Ref UST UState} ->
             {auto dl : Ref DLY DelayedElabs} ->
             {auto e : Ref EST (EState vars)} ->
             RigCount -> ElabInfo -> Env Term vars -> FC -> PairParts vars ->
             UnifyInfo -> (delayed : Bool) -> Glued vars ->
             Core (Term vars, Glued vars)
settlePair rig elabinfo env fc parts solvemode delayed expected
    = settle fc env solvemode delayed expected
        (Just pairname, pairTypeOf rig elabinfo env fc parts expected)
        (Just mkpairname, pairOf rig elabinfo env fc parts expected)

-- The syntax as written, settled each time it is tried by elaborating the
-- reading it is found to write.
settleWritten : {vars : _} ->
                {auto c : Ref Ctxt Defs} ->
                {auto m : Ref MD Metadata} ->
                {auto u : Ref UST UState} ->
                {auto dl : Ref DLY DelayedElabs} ->
                {auto e : Ref EST (EState vars)} ->
                {auto s : Ref Syn SyntaxInfo} ->
                {auto o : Ref ROpts REPLOpts} ->
                RigCount -> ElabInfo -> NestedNames vars -> Env Term vars ->
                FC -> Overlaid -> UnifyInfo -> (delayed : Bool) -> Glued vars ->
                Core (Term vars, Glued vars)
settleWritten rig elabinfo nest env fc ovl solvemode delayed expected
    = let asType = typeReading fc ovl
          asValue = valueReading fc ovl in
          settle fc env solvemode delayed expected
            (getName asType, checkImp rig elabinfo nest env asType (Just expected))
            (getName asValue, checkImp rig elabinfo nest env asValue (Just expected))

-- The syntax as written, settled when first met, and else when retried.
checkWritten : {vars : _} ->
               {auto c : Ref Ctxt Defs} ->
               {auto m : Ref MD Metadata} ->
               {auto u : Ref UST UState} ->
               {auto dl : Ref DLY DelayedElabs} ->
               {auto e : Ref EST (EState vars)} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto o : Ref ROpts REPLOpts} ->
               RigCount -> ElabInfo -> NestedNames vars -> Env Term vars ->
               FC -> Overlaid -> UnifyInfo -> Glued vars ->
               Core (Term vars, Glued vars)
checkWritten rig elabinfo nest env fc ovl solvemode expected
    = delayOnFailure fc rig env expected ambiguous Ambiguity $
        \dl, delayed, exp =>
          settleWritten {dl} rig elabinfo nest env fc ovl solvemode delayed exp

||| The syntax that writes a type and a value of it alike: `(l, r)`, `()`,
||| and `(x ** p)` with the type of `x` left out. Its expected type's sort
||| decides which it writes; while that is unknown, a pair's parts are
||| elaborated once, against unknowns of their own, and the site waits for
||| the sort with nothing more to elaborate, so a tuple costs one
||| elaboration per part however deep it nests. A unit has no part, and a
||| dependent pair's readings share none (the type reading binds the name
||| over the second part, the value reading refers to it), so each waits as
||| written. On a left-hand side a pair waits as written too: its parts are
||| patterns, which the reading's application checks as a pattern needs.
export
checkTypeOrValue : {vars : _} ->
                   {auto c : Ref Ctxt Defs} ->
                   {auto m : Ref MD Metadata} ->
                   {auto u : Ref UST UState} ->
                   {auto dl : Ref DLY DelayedElabs} ->
                   {auto e : Ref EST (EState vars)} ->
                   {auto s : Ref Syn SyntaxInfo} ->
                   {auto o : Ref ROpts REPLOpts} ->
                   RigCount -> ElabInfo ->
                   NestedNames vars -> Env Term vars ->
                   FC -> Overlaid -> Maybe (Glued vars) ->
                   Core (Term vars, Glued vars)
checkTypeOrValue rig elabinfo nest env fc ovl mexpected
    = do expected <- maybe (do nm <- genName "altTy"
                               u <- uniVar fc
                               ty <- metaVar fc erased env nm (TType fc u)
                               pure (gnf env ty))
                           pure mexpected
         let solvemode = case elabMode elabinfo of
                              InLHS c => inLHS
                              _ => inTerm
         solveConstraints solvemode Normal
         case (ovl, elabMode elabinfo, !(sortOf expected)) of
              (PairOf l r, InLHS _, _) =>
                  checkWritten rig elabinfo nest env fc ovl solvemode expected
              (PairOf l r, _, Unknown) =>
                  do parts <- pairParts rig elabinfo nest env fc l r
                     delayOnFailure fc rig env expected ambiguous Ambiguity $
                       \dl, delayed, exp =>
                         settlePair {dl} rig elabinfo env fc parts solvemode delayed exp
              _ => checkWritten rig elabinfo nest env fc ovl solvemode expected
