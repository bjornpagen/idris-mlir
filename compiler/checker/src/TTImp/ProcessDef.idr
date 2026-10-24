-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module TTImp.ProcessDef

import Core.Case.CaseBuilder
import Core.Case.CaseTree
import Core.Case.CaseTree.Pretty
import Core.Coverage
import Core.Env
import Core.Hash
import Core.LinearCheck
import Core.Metadata
import Core.Termination
import Core.Termination.CallGraph
import Core.Value
import Core.UnifyState

import Idris.REPL.Opts
import Idris.Syntax
import Idris.Pretty.Annotations

import TTImp.BindImplicits
import TTImp.Elab
import TTImp.Elab.Binders
import TTImp.Elab.Check
import TTImp.Elab.Utils
import TTImp.Impossible
import TTImp.TTImp
import TTImp.TTImp.Functor
import TTImp.ProcessType
import TTImp.Unelab
import TTImp.WithClause

import Data.Either
import Data.List
import Data.String
import Data.Maybe
import Libraries.Data.NameMap
import Libraries.Data.WithDefault
import Libraries.Text.PrettyPrint.Prettyprinter
import Libraries.Data.List.SizeOf
import Libraries.Data.VarSet

%default covering

mutual
  mismatchNF : {auto c : Ref Ctxt Defs} ->
               {vars : _} ->
               Defs -> NF vars -> NF vars -> Core Bool
  mismatchNF defs (NTCon _ xn _ xargs) (NTCon _ yn _ yargs)
      = if xn /= yn
           then pure True
           else anyM (mismatch defs) (zipWith (curry $ mapHom snd) xargs yargs)
  mismatchNF defs (NDCon _ _ xt _ xargs) (NDCon _ _ yt _ yargs)
      = if xt /= yt
           then pure True
           else anyM (mismatch defs) (zipWith (curry $ mapHom snd) xargs yargs)
  mismatchNF defs (NPrimVal _ xc) (NPrimVal _ yc) = pure (xc /= yc)
  mismatchNF defs (NDelayed _ _ x) (NDelayed _ _ y) = mismatchNF defs x y
  mismatchNF defs (NDelay _ _ _ x) (NDelay _ _ _ y)
      = mismatchNF defs !(evalClosure defs x) !(evalClosure defs y)

  -- NPrimVal is apart from NDCon, NTCon, NBind, and NType
  mismatchNF defs (NPrimVal {}) (NDCon {}) = pure True
  mismatchNF defs (NDCon {}) (NPrimVal {}) = pure True
  mismatchNF defs (NPrimVal {}) (NBind {}) = pure True
  mismatchNF defs (NBind {}) (NPrimVal {}) = pure True
  mismatchNF defs (NPrimVal {}) (NTCon {}) = pure True
  mismatchNF defs (NTCon {}) (NPrimVal {}) = pure True
  mismatchNF defs (NPrimVal {}) (NType {}) = pure True
  mismatchNF defs (NType {}) (NPrimVal {}) = pure True

-- NTCon is apart from NBind, and NType
  mismatchNF defs (NTCon {}) (NBind {}) = pure True
  mismatchNF defs (NBind {}) (NTCon {}) = pure True
  mismatchNF defs (NTCon {}) (NType {}) = pure True
  mismatchNF defs (NType {}) (NTCon {}) = pure True

-- NBind is apart from NType
  mismatchNF defs (NBind {}) (NType {}) = pure True
  mismatchNF defs (NType {}) (NBind {}) = pure True

  mismatchNF _ _ _ = pure False

  mismatch : {auto c : Ref Ctxt Defs} ->
             {vars : _} ->
             Defs -> (Closure vars, Closure vars) -> Core Bool
  mismatch defs (x, y)
      = mismatchNF defs !(evalClosure defs x) !(evalClosure defs y)

-- If the terms have the same type constructor at the head, and one of
-- the argument positions has different constructors at its head, then this
-- is an impossible case, so return True
export
impossibleOK : {auto c : Ref Ctxt Defs} ->
               {vars : _} ->
               Defs -> NF vars -> NF vars -> Core Bool
impossibleOK defs (NTCon _ xn xa xargs) (NTCon _ yn ya yargs)
    = if xn /= yn
         then pure True
         else anyM (mismatch defs) (zipWith (curry $ mapHom snd) xargs yargs)
-- If it's a data constructor, any mismatch will do
impossibleOK defs (NDCon _ _ xt _ xargs) (NDCon _ _ yt _ yargs)
    = if xt /= yt
         then pure True
         else anyM (mismatch defs) (zipWith (curry $ mapHom snd) xargs yargs)
impossibleOK defs (NPrimVal _ x) (NPrimVal _ y) = pure (x /= y)

-- NPrimVal is apart from NDCon, NTCon, NBind, and NType
impossibleOK defs (NPrimVal {}) (NDCon {}) = pure True
impossibleOK defs (NDCon {}) (NPrimVal {}) = pure True
impossibleOK defs (NPrimVal {}) (NBind {}) = pure True
impossibleOK defs (NBind {}) (NPrimVal {}) = pure True
impossibleOK defs (NPrimVal {}) (NTCon {}) = pure True
impossibleOK defs (NTCon {}) (NPrimVal {}) = pure True
impossibleOK defs (NPrimVal {}) (NType {}) = pure True
impossibleOK defs (NType {}) (NPrimVal {}) = pure True

-- NTCon is apart from NBind, and NType
impossibleOK defs (NTCon {}) (NBind {}) = pure True
impossibleOK defs (NBind {}) (NTCon {}) = pure True
impossibleOK defs (NTCon {}) (NType {}) = pure True
impossibleOK defs (NType {}) (NTCon {}) = pure True

-- NBind is apart from NType
impossibleOK defs (NBind {}) (NType {}) = pure True
impossibleOK defs (NType {}) (NBind {}) = pure True

impossibleOK defs x y = pure False

export
impossibleErrOK : {auto c : Ref Ctxt Defs} ->
                  Defs -> Error -> Core Bool
impossibleErrOK defs (CantConvert fc gam env l r)
    = do let defs = { gamma := gam } defs
         impossibleOK defs !(nf defs env l)
                           !(nf defs env r)
impossibleErrOK defs (CantSolveEq fc gam env l r)
    = do let defs = { gamma := gam } defs
         impossibleOK defs !(nf defs env l)
                           !(nf defs env r)
impossibleErrOK defs (CyclicMeta {}) = pure True
impossibleErrOK defs (AllFailed errs)
    = allM (impossibleErrOK defs) (map snd errs)
impossibleErrOK defs (WhenUnifying _ _ _ _ _ err)
    = impossibleErrOK defs err
impossibleErrOK defs ImpossibleCase = pure True
impossibleErrOK defs _ = pure False

-- Given a type checked LHS and its type, return the environment in which we
-- should check the RHS, the LHS and its type in that environment,
-- and a function which turns a checked RHS into a
-- pattern clause
-- The 'Thin' proof contains a proof that refers to the *inner* environment,
-- so all the outer things are marked as 'Drop'
extendEnv : {vars : _} ->
            Env Term vars -> Thin inner vars ->
            NestedNames vars ->
            Term vars -> Term vars ->
            Core (vars' **
                    (Thin inner vars',
                     Env Term vars', NestedNames vars',
                     Term vars', Term vars'))
-- A variable is its position in the scope, and its name only a label: the
-- type's scope is read in the pattern's, its top variable labelled with the
-- pattern's name (`compat`), whatever label the type's binder gave it.
extendEnv env p nest (Bind _ n (PVar fc c pi tmty) sc) (Bind _ _ (PVTy {}) tysc)
    = extendEnv (PVar fc c pi tmty :: env) (Drop p) (weaken (dropName n nest)) sc (compat tysc)
-- PLet on the left becomes Let on the right, to give it computational force
extendEnv env p nest (Bind _ n (PLet fc c tmval tmty) sc) (Bind _ _ (PLet {}) tysc)
    = extendEnv (Let fc c tmval tmty :: env) (Drop p) (weaken (dropName n nest)) sc (compat tysc)
extendEnv env p nest tm ty
      = pure (_ ** (p, env, nest, tm, ty))

-- Find names which are applied to a function in a Rig1/Rig0 position,
-- so that we know how they should be bound on the right hand side of the
-- pattern.
-- 'bound' counts the number of variables locally bound; these are the
-- only ones we're checking linearity of (we may be shadowing names if this
-- is a local definition, so we need to leave the earlier ones alone)
findLinear : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             Bool -> Nat -> RigCount -> Term vars ->
             Core (List (Name, RigCount))
findLinear top bound rig (Bind fc n b sc)
    = findLinear top (S bound) rig sc
findLinear top bound rig (As fc _ _ p)
    = findLinear top bound rig p
findLinear top bound rig tm
    = case getFnArgs tm of
           (Ref _ _ n, []) => pure []
           (Ref _ nt n, args)
              => do defs <- get Ctxt
                    Just nty <- lookupTyExact n (gamma defs)
                         | Nothing => pure []
                    findLinArg (accessible nt rig) !(nf defs Env.empty nty) args
           _ => pure []
    where
      accessible : NameType -> RigCount -> RigCount
      accessible Func r = if top then r else erased
      accessible _ r = r

      findLinArg : {vars : _} ->
                   RigCount -> ClosedNF -> List (Term vars) ->
                   Core (List (Name, RigCount))
      findLinArg rig ty@(NBind _ _ (Pi _ c _ _) _) (As fc u a p :: as)
          = if isLinear c
               then case u of
                         UseLeft => findLinArg rig ty (p :: as)
                         UseRight => findLinArg rig ty (a :: as)
               else pure $ !(findLinArg rig ty [a]) ++ !(findLinArg rig ty (p :: as))
      findLinArg rig (NBind _ x (Pi _ c _ _) sc) (Local {name=a} fc _ idx prf :: as)
          = do defs <- get Ctxt
               let a = nameAt prf
               if idx < bound
                 then do sc' <- sc defs (toClosure defaultOpts Env.empty (Ref fc Bound x))
                         pure $ (a, rigMult c rig) ::
                                    !(findLinArg rig sc' as)
                 else do sc' <- sc defs (toClosure defaultOpts Env.empty (Ref fc Bound x))
                         findLinArg rig sc' as
      findLinArg rig (NBind fc x (Pi _ c _ _) sc) (a :: as)
          = do defs <- get Ctxt
               pure $ !(findLinear False bound (c |*| rig) a) ++
                      !(findLinArg rig !(sc defs (toClosure defaultOpts Env.empty (Ref fc Bound x))) as)
      findLinArg rig ty (a :: as)
          = pure $ !(findLinear False bound rig a) ++ !(findLinArg rig ty as)
      findLinArg _ _ [] = pure []

setLinear : List (Name, RigCount) -> Term vars -> Term vars
setLinear vs tm@(Bind fc x b sc)
    = if isPatternBinder b
         then let b' = maybe b (setMultiplicity b) (lookup x vs)
               in Bind fc x b' (setLinear vs sc)
         else tm
  where
    isPatternBinder : Binder a -> Bool
    isPatternBinder (PVar {}) = True
    isPatternBinder (PVTy {}) = True
    isPatternBinder (PLet {}) = True
    isPatternBinder _ = False
setLinear vs tm = tm

-- Combining multiplicities on LHS:
-- Rig1 + Rig1/W not valid, since it means we have repeated use of name
-- Rig0 + RigW = RigW
-- Rig0 + Rig1 = Rig1
combineLinear : FC -> List (Name, RigCount) ->
                Core (List (Name, RigCount))
combineLinear loc [] = pure []
combineLinear loc ((n, count) :: cs)
    = case lookupAll n cs of
           [] => pure $ (n, count) :: !(combineLinear loc cs)
           counts => do count' <- combineAll count counts
                        pure $ (n, count') ::
                               !(combineLinear loc (filter notN cs))
  where
    notN : (Name, RigCount) -> Bool
    notN (n', _) = n /= n'

    lookupAll : Name -> List (Name, RigCount) -> List RigCount
    lookupAll n [] = []
    lookupAll n ((n', c) :: cs)
       = if n == n' then c :: lookupAll n cs else lookupAll n cs

    -- Those combine rules are obtuse enough that they are worth investigating
    combine : RigCount -> RigCount -> Core RigCount
    combine l r = if l |+| r == top && not (isErased $ l `glb` r) && (l `glb` r) /= top
                     then throw (LinearUsed loc 2 n)
                     -- if everything is fine, return the linearity that has the
                     -- highest bound
                     else pure (l `lub` r)

    combineAll : RigCount -> List RigCount -> Core RigCount
    combineAll c [] = pure c
    combineAll c (c' :: cs)
        = do newc <- combine c c'
             combineAll newc cs

-- The variables of a checked left-hand side's scope that name an argument
-- the clause leaves to unification. The elaborator writes each such argument
-- as an as-pattern on its own side over `_` (an implicit the clause leaves
-- out, `implicitsAs`; a case block's environment; a with block's argument)
-- and binds the as-name in the scope. A case alternative's pattern on the
-- variable it splits goes into that variable's as-pattern too, but it is
-- the clause's own: only the `_` marks an argument left to unification.
-- So does each as-pattern the elaborator binds for an implicit argument it
-- inserts into a pattern (`marks`).
unifiedArgs : {vars : _} -> (marks : List Name) -> RawImp -> VarSet vars
unifiedArgs marks lhs = foldr bind VarSet.empty (marks ++ leftOut lhs)
  where
    leftOut : RawImp -> List Name
    leftOut (IAs _ _ UseLeft n (Implicit {})) = [n]
    leftOut (IApp _ f a) = leftOut f ++ leftOut a
    leftOut (INamedApp _ f _ a) = leftOut f ++ leftOut a
    leftOut (IAutoApp _ f a) = leftOut f ++ leftOut a
    leftOut _ = []

    bind : Name -> VarSet vars -> VarSet vars
    bind n set = maybe set (\v => VarSet.insert v set) (isVar n vars)

export -- also used by Transforms
checkLHS : {vars : _} ->
           {auto c : Ref Ctxt Defs} ->
           {auto m : Ref MD Metadata} ->
           {auto u : Ref UST UState} ->
           {auto dl : Ref DLY DelayedElabs} ->
           {auto s : Ref Syn SyntaxInfo} ->
           {auto o : Ref ROpts REPLOpts} ->
           Bool -> -- in transform
           (mult : RigCount) ->
           Int -> List ElabOpt -> NestedNames vars -> Env Term vars ->
           FC -> RawImp ->
           Core (RawImp, -- checked LHS with implicits added
                 (vars' ** (Thin vars vars',
                           Env Term vars', NestedNames vars',
                           Term vars', Term vars',
                           -- the arguments it leaves to unification
                           VarSet vars')))
checkLHS {vars} trans mult n opts nest env fc lhs_in
    = do defs <- get Ctxt
         logRaw "declare.def.lhs" 30 "Raw LHS: " lhs_in
         lhs_raw <- if trans
                       then pure lhs_in
                       else lhsInCurrentNS nest lhs_in
         logRaw "declare.def.lhs" 30 "Raw LHS in current NS: " lhs_raw

         autoimp <- isUnboundImplicits
         setUnboundImplicits True
         (_, lhs_bound) <- bindNames False lhs_raw
         setUnboundImplicits autoimp
         logRaw "declare.def.lhs" 30 "Raw LHS with implicits bound" lhs_bound

         lhs <- if trans
                   then pure lhs_bound
                   else implicitsAs n defs vars lhs_bound

         logC "declare.def.lhs" 5 $ do pure $ "Checking LHS of " ++ show !(getFullName (Resolved n))
-- todo: add Pretty RawImp instance
--         logC "declare.def.lhs" 5 $ do pure $ show $ indent {ann = ()} 2 $ pretty lhs
         log "declare.def.lhs" 10 $ show lhs
         logEnv "declare.def.lhs" 5 "In env" env
         let lhsMode = if trans
                          then InTransform
                          else InLHS mult
         (lhstm, lhstyg, marks) <-
             wrapErrorC opts (InLHS fc !(getFullName (Resolved n))) $
                     elabTermSubMarked n lhsMode opts nest env env Refl
                                (IBindHere fc PATTERN lhs) Nothing
         logTerm "declare.def.lhs" 5 "Checked LHS term" lhstm
         lhsty <- getTerm lhstyg

         defs <- get Ctxt
         let lhsenv = letToLam env
         -- we used to fully normalise the LHS, to make sure fromInteger
         -- patterns were allowed, but now they're fully normalised anyway
         -- so we only need to do the holes. If there's a lot of type level
         -- computation, this is a huge saving!
         lhstm <- normaliseHoles defs lhsenv lhstm
         lhsty <- normaliseHoles defs env lhsty
         linvars_in <- findLinear True 0 linear lhstm
         logTerm "declare.def.lhs" 10 "Checked LHS term after normalise" lhstm
         log "declare.def.lhs" 5 $ "Linearity of names in " ++ show n ++ ": " ++
                 show linvars_in

         linvars <- combineLinear fc linvars_in
         let lhstm_lin = setLinear linvars lhstm
         let lhsty_lin = setLinear linvars lhsty

         logTerm "declare.def.lhs" 3 "LHS term" lhstm_lin
         logTerm "declare.def.lhs" 5 "LHS type" lhsty_lin
         setHoleLHS (bindEnv fc env lhstm_lin)

         (vars' ** (sub', env', nest', lhstm', lhsty')) <-
             extendEnv env Refl nest lhstm_lin lhsty_lin
         pure (lhs, (vars' ** (sub', env', nest', lhstm', lhsty', unifiedArgs marks lhs)))

-- Return whether any of the pattern variables are in an empty type, where
-- empty means that no constructor of the family can build a value of it:
--  * No constructors
--  * Every constructor of the family has a return type which conflicts with
--    the given constructor's type, or an argument of a type which is empty
--    in the same way, as it is or under what the other arguments' types
--    hold of it (Core.Coverage.isEmpty)
hasEmptyPat : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              Defs -> Env Term vars -> Term vars -> Core Bool
hasEmptyPat defs env (Bind fc x b sc)
   = pure $ !(isEmpty defs env !(nf defs env (binderType b)))
            || !(hasEmptyPat defs (b :: env) sc)
hasEmptyPat defs env _ = pure False

-- For checking with blocks as nested names
applyEnv : {vars : _} ->
           {auto c : Ref Ctxt Defs} ->
           Env Term vars -> Name ->
           Core (Name, (Maybe Name, List (Var vars), FC -> NameType -> Term vars))
applyEnv env withname
    = do n' <- resolveName withname
         pure (withname, (Just withname, reverse (allVarsNoLet env),
                  \fc, nt => applyTo fc
                         (Ref fc nt (Resolved n')) env))

-- Check a pattern clause, returning the component of the 'Case' expression it
-- represents, or Nothing if it's an impossible clause
export
checkClause : {vars : _} ->
              {auto c : Ref Ctxt Defs} ->
              {auto m : Ref MD Metadata} ->
              {auto u : Ref UST UState} ->
              {auto dl : Ref DLY DelayedElabs} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto o : Ref ROpts REPLOpts} ->
              (mult : RigCount) -> (vis : Visibility) ->
              (totreq : TotalReq) -> (hashit : Bool) ->
              Int -> List ElabOpt -> NestedNames vars -> Env Term vars ->
              ImpClause -> Core (Either RawImp Clause)
checkClause mult vis totreq hashit n opts nest env (ImpossibleClause fc lhs)
    = do lhs_raw <- lhsInCurrentNS nest lhs
         handleUnifyElab
           (do autoimp <- isUnboundImplicits
               setUnboundImplicits True
               (_, lhs) <- bindNames False lhs_raw
               setUnboundImplicits autoimp

               log "declare.def.clause.impossible" 5 $ "Checking " ++ show lhs
               logEnv "declare.def.clause.impossible" 5 "In env" env
               (lhstm, lhstyg) <-
                           elabTerm n (InLHS mult) opts nest env
                                      (IBindHere fc COVERAGE lhs) Nothing
               defs <- get Ctxt
               lhs <- normaliseHoles defs env lhstm
               if !(hasEmptyPat defs env lhs)
                  then pure (Left lhs_raw)
                  else throw (ValidCase fc env (Left lhs)))
           (\err =>
              case err of
                   ValidCase {} => throw err
                   _ => do defs <- get Ctxt
                           if !(impossibleErrOK defs err)
                              then pure (Left lhs_raw)
                              else throw (ValidCase fc env (Right err)))
checkClause {vars} mult vis totreq hashit n opts nest env (PatClause fc lhs_in rhs)
    = do (_, (vars'  ** (sub', env', nest', lhstm', lhsty', unified))) <-
             checkLHS False mult n opts nest env fc lhs_in
         let rhsMode = if isErased mult then InType else InExpr
         log "declare.def.clause" 5 $ "Checking RHS " ++ show rhs
         logEnv "declare.def.clause" 5 "In env" env'

         rhstm <- logTime 3 ("Check RHS " ++ show fc) $
                    wrapErrorC opts (InRHS fc !(getFullName (Resolved n))) $
                       checkTermSub n rhsMode opts nest' env' env sub' rhs (gnf env' lhsty')
         clearHoleLHS

         logTerm "declare.def.clause" 3 "RHS term" rhstm
         when hashit $
           do addHashWithNames lhstm'
              addHashWithNames rhstm
              log "module.hash" 15 "Adding hash for def."

         -- If the rhs is a hole, record the lhs in the metadata because we
         -- might want to split it interactively
         case rhstm of
              Meta {} =>
                 addLHS (getFC lhs_in) (length env) env' lhstm'
              _ => pure ()

         pure (Right (MkClause env' lhstm' rhstm unified))
-- TODO: (to decide) With is complicated. Move this into its own module?
checkClause {vars} mult vis totreq hashit n opts nest env
    (WithClause ifc lhs_in rig wval_raw mprf flags cs)
    = do (lhs, (vars'  ** (sub', env', nest', lhspat, reqty, unified))) <-
             checkLHS False mult n opts nest env ifc lhs_in
         let wmode
               = if isErased mult || isErased rig then InType else InExpr

         (wval, gwvalTy) <- wrapErrorC opts (InRHS ifc !(getFullName (Resolved n))) $
                elabTermSub n wmode opts nest' env' env sub' wval_raw Nothing
         clearHoleLHS

         logTerm "declare.def.clause.with" 5 "With value (at quantity \{show rig})" wval
         logTerm "declare.def.clause.with" 3 "Required type" reqty
         wvalTy <- getTerm gwvalTy
         defs <- get Ctxt
         wval <- normaliseHoles defs env' wval
         wvalTy <- normaliseHoles defs env' wvalTy

         -- The with function is over the part of the environment the value,
         -- its type and the outer environment mention, closed under the
         -- binders of what they mention (`closed`). The value and its type
         -- are each covered and thinned into that part, and its binders
         -- built over it as it is made, so nothing is strengthened into it.
         let (_ ** (valIn, wvalOver)) = cover wval
         let (_ ** (tyIn, wvalTyOver)) = cover wvalTy
         let (_ ** (bothIn, valInBoth, tyInBoth)) = keepBoth valIn tyIn
         let (_ ** (needIn, bothInNeed, _)) = keepBoth bothIn sub'
         let (wevars ** (withSub, needInWith, wvalEnv)) = closed env' needIn
         let inWith = chain bothInNeed needInWith
         let wval = thin wvalOver (chain valInBoth inWith)
         let wvalTy = thin wvalTyOver (chain tyInBoth inWith)
         logTerm "declare.def.clause.with" 5 "With value type" wvalTy
         log "declare.def.clause.with" 5 $ "Using vars " ++ show wevars

         -- Abstracting over 'wval' in the scope of bNotReq in order
         -- to get the 'magic with' behaviour
         (wargs ** (scenv, var, binder)) <- bindWithArgs rig wvalTy ((,wval) <$> mprf) wvalEnv

         let bnr = bindNotReq vfc 0 env' withSub [] reqty
         let notreqns = fst bnr
         let notreqty = snd bnr

         rdefs <- if Syntactic `elem` flags
                     then clearDefs defs
                     else pure defs
         wtyScope <- replace rdefs scenv !(nf rdefs scenv (weakenNs (mkSizeOf wargs) wval))
                            var
                            !(nf rdefs scenv
                                 (weakenNs (mkSizeOf wargs) notreqty))
         let bNotReq = binder wtyScope

         -- The environment has some implicit and some explcit args, potentially,
         -- which is inconvenient since we have to know which is which when
         -- elaborating the application of the rhs function. So it's easier
         -- if we just make them all explicit - this type isn't visible to
         -- users anyway!
         let env' = mkExplicit env'

         let (reqns, envns, wtype) = bindReq vfc (mkExplicit wvalEnv) withSub [] bNotReq

         -- list of argument names - 'Just' means we need to match the name
         -- in the with clauses to find out what the pattern should be.
         -- 'Nothing' means it's the with pattern (so wargn)
         let wargNames
                 = map Just reqns ++
                   Nothing :: map Just notreqns

         logTerm "declare.def.clause.with" 3 "With function type" wtype
         log "declare.def.clause.with" 5 $ "Argument names " ++ show wargNames

         wname <- genWithName !(toFullNames (Resolved n))
         widx <- addDef wname ({flags $= (SetTotal totreq ::)}
                                    (newDef vfc wname (if isErased mult then erased else top)
                                      vars wtype (specified vis) None))

         let toWarg : Maybe (PiInfo RawImp, Name) -> List (Maybe Name, RawImp)
               := flip maybe (\pn => [(Nothing, IVar vfc (snd pn))]) $
                    (Nothing, wval_raw) ::
                    case mprf of
                      Nothing => []
                      Just _  =>
                       let fc = emptyFC in
                       let refl = IVar fc (NS builtinNS (knownUN KRefl)) in
                       [(map snd mprf, INamedApp fc refl (knownUN Kx) wval_raw)]

         let rhs_in = gapply (IVar vfc wname)
                    $ map (\ nm => (Nothing, IVar vfc nm)) envns
                   ++ concatMap toWarg wargNames

         log "declare.def.clause.with" 3 $ "Applying to with argument " ++ show rhs_in
         rhs <- wrapErrorC opts (InRHS ifc !(getFullName (Resolved n))) $
             checkTermSub n wmode opts nest' env' env sub' rhs_in
                          (gnf env' reqty)

         -- Generate new clauses by rewriting the matched arguments
         cs' <- traverse (mkClauseWith 1 wname wargNames lhs) cs
         log "declare.def.clause.with" 3 $ "With clauses: " ++ show cs'

         -- Elaborate the new definition here
         nestname <- applyEnv env wname
         let nest'' = { names $= (nestname ::) } nest

         let wdef = IDef ifc wname cs'
         processDecl [] nest'' env wdef

         pure (Right (MkClause env' lhspat rhs unified))
  where
    vfc : FC
    vfc = virtualiseFC ifc

    bindWithArgs :
       (rig : RigCount) -> (wvalTy : Term xs) -> Maybe ((RigCount, Name), Term xs) ->
       (wvalEnv : Env Term xs) ->
       Core (ext : Scope
         ** ( Env Term (ext ++ xs)
            , Term (ext ++ xs)
            , (Term (ext ++ xs) -> Term xs)
            ))
    bindWithArgs {xs} rig wvalTy Nothing wvalEnv =
      let wargn : Name
          wargn = MN (known Kwarg) 0
          wargs : Scope
          wargs = [wargn]

          scenv : Env Term (wargs ++ xs)
                := Pi vfc top Explicit wvalTy :: wvalEnv

          var : Term (wargs ++ xs)
              := Local vfc (Just False) Z First

          binder : Term (wargs ++ xs) -> Term xs
                 := Bind vfc wargn (Pi vfc rig Explicit wvalTy)

      in pure (wargs ** (scenv, var, binder))

    bindWithArgs {xs} rig wvalTy (Just ((rigPrf, name), wval)) wvalEnv = do
      defs <- get Ctxt

      -- The proof a `with` clause names is of `Builtin.Equal`, which the
      -- prelude defines: a program that has no such type is refused.
      let eqName = NS builtinNS (knownUN KEqual)
      Just (TCon ar _ _ _ _ _ _) <- lookupDefExact eqName (gamma defs)
        | _ => throw (GenericMsg vfc "The proof a `with` clause names is of Builtin.Equal, which is not a type here")
      let eqTyCon = Ref vfc (TyCon ar) !(toResolvedNames eqName)

      let wargn : Name
          wargn = MN (known Kwarg) 0
          wargs : Scope
          wargs = [name, wargn]

          wvalTy' := weaken wvalTy
          eqTy : Term (MN (known Kwarg) 0 :: xs)
               := apply vfc eqTyCon
                           [ wvalTy'
                           , wvalTy'
                           , weaken wval
                           , Local vfc (Just False) Z First
                           ]

          scenv : Env Term (wargs ++ xs)
                := Pi vfc top Implicit eqTy
                :: Pi vfc top Explicit wvalTy
                :: wvalEnv

          var : Term (wargs ++ xs)
              := Local vfc (Just False) (S Z) (Later First)

          binder : Term (wargs ++ xs) -> Term xs
                 := \ t => Bind vfc wargn (Pi vfc rig Explicit wvalTy)
                         $ Bind vfc name  (Pi vfc rigPrf Implicit eqTy) t

      pure (wargs ** (scenv, var, binder))

    -- Rewrite the clauses in the block to use an updated LHS.
    -- 'drop' is the number of additional with arguments we expect
    -- (i.e. the things to drop from the end before matching LHSs)
    mkClauseWith : (drop : Nat) -> Name ->
                   List (Maybe (PiInfo RawImp, Name)) ->
                   RawImp -> ImpClause ->
                   Core ImpClause
    mkClauseWith drop wname wargnames lhs (PatClause ploc patlhs rhs)
        = do log "declare.def.clause.with" 20 "PatClause"
             newlhs <- getNewLHS ploc drop nest wname wargnames lhs patlhs
             newrhs <- withRHS ploc drop wname wargnames rhs lhs
             pure (PatClause ploc newlhs newrhs)
    mkClauseWith drop wname wargnames lhs (WithClause ploc patlhs rig wval prf flags ws)
        = do log "declare.def.clause.with" 20 "WithClause"
             newlhs <- getNewLHS ploc drop nest wname wargnames lhs patlhs
             newwval <- withRHS ploc drop wname wargnames wval lhs
             ws' <- traverse (mkClauseWith (S drop) wname wargnames lhs) ws
             pure (WithClause ploc newlhs rig newwval prf flags ws')
    mkClauseWith drop wname wargnames lhs (ImpossibleClause ploc patlhs)
        = do log "declare.def.clause.with" 20 "ImpossibleClause"
             newlhs <- getNewLHS ploc drop nest wname wargnames lhs patlhs
             pure (ImpossibleClause ploc newlhs)

-- Calculate references for the given name, and recursively if they haven't
-- been calculated already: what its compile-time tree, the program the
-- frontend translates, refers to. The references are asked for first, so
-- that a definition whose references are known has its tree left as it is
-- held: every reference in the tree is read, so a stored tree is decoded.
calcRefs : {auto c : Ref Ctxt Defs} ->
           (aTotal : Name) -> (fn : Name) -> Core ()
calcRefs at fn
    = do defs <- get Ctxt
         Just gdef <- lookupCtxtExact fn (gamma defs)
              | _ => pure ()
         let Nothing = refersToM gdef
              | Just _ => pure () -- already done
         let PMDef r cargs body = definition gdef
              | _ => pure () -- not a function definition
         tree_ct <- treeOf body
         let metas = CaseTree.getMetas tree_ct
         traverse_ addToSave (keys metas)
         let refs = addRefs at metas tree_ct
         ignore $ addDef fn ({ refersToM := Just refs } gdef)
         traverse_ (calcRefs at) (keys refs)

toPats : Clause -> (vs ** (Env Term vs, Term vs, Term vs))
toPats (MkClause {vars} env lhs rhs _)
    = (_ ** (env, lhs, rhs))

-- A clause as the tree its definition keeps reads it. Only the coverage
-- check needs an argument a clause leaves to unification split after the
-- patterns that fix it, and it builds a tree of its own. Above quantity 0
-- the tree a definition keeps is the program that runs (this compiler's
-- frontend translates it, testing in the order the tree splits), and it
-- takes an erased argument as a variable where later patterns bind the names
-- in it; moved after them, that argument is split, and a type the definition
-- computes stops reducing while it is unsolved (the length in `Data.Fun`'s
-- `Fun` and `chain`, which base's `Data.Nat.Order.lte` leaves unsolved, so
-- that `lte` no longer checks). So that tree is built from the clauses
-- without the mark, and splits in the arguments' order, as upstream's run
-- time tree did (its clauses carried none). At quantity 0 nothing runs
-- and every argument a clause matches is split, and the tree splits such an
-- argument last, as the coverage check's does.
saved : RigCount -> Clause -> Clause
saved mult cl@(MkClause env lhs rhs _)
    = if isErased mult then cl else MkClause env lhs rhs VarSet.empty

warnUnreachable : {auto c : Ref Ctxt Defs} ->
                  Clause -> Core ()
warnUnreachable (MkClause env lhs rhs _)
    = recordWarning (UnreachableClause (getLoc lhs) env lhs)

isAlias : RawImp -> Maybe ((FC, Name)              -- head symbol
                          , List (FC, (FC, Name))) -- pattern variables
isAlias lhs
  = do let (hd, apps) = getFnArgs lhs []
       hd <- isIVar hd
       args <- traverse (isExplicit >=> bitraverse pure isIBindVar) apps
       pure (hd, args)

lookupOrAddAlias : {vars : _} ->
                   {auto m : Ref MD Metadata} ->
                   {auto c : Ref Ctxt Defs} ->
                   {auto u : Ref UST UState} ->
                   {auto dl : Ref DLY DelayedElabs} ->
                   {auto s : Ref Syn SyntaxInfo} ->
                   {auto o : Ref ROpts REPLOpts} ->
                   List ElabOpt -> NestedNames vars -> Env Term vars -> FC ->
                   Name -> List ImpClause -> Core (Maybe GlobalDef)
lookupOrAddAlias eopts nest env fc n [cl@(PatClause _ lhs _)]
  = do defs <- get Ctxt
       log "declare.def.alias" 20 $ "Looking at \{show cl}"
       Nothing <- lookupCtxtExact n (gamma defs)
         | Just gdef => pure (Just gdef)
       -- No prior declaration:
       --   1) check whether it has the shape of an alias
       let Just (hd, args) = isAlias lhs
         | Nothing => pure Nothing
       --   2) check whether it could be a misspelling
       log "declare.def" 5 $
         "Missing type declaration for the alias "
         ++ show n
         ++ ". Checking first whether it is a misspelling."
       [] <- do -- get the candidates
                Just (str, kept) <- getSimilarNames n
                   | Nothing => pure []
                -- only keep the ones that haven't been defined yet
                decls <- for kept $ \ (cand, vis, weight) => do
                    Just gdef <- lookupCtxtExact cand (gamma defs)
                      | Nothing => pure Nothing -- should be impossible
                    let None = definition gdef
                      | _ => pure Nothing
                    pure (Just (cand, vis, weight))
                pure $ showSimilarNames (currentNS defs) n str $ catMaybes decls
          | (x :: xs) => throw (MaybeMisspelling (NoDeclaration fc n) (x ::: xs))
       --   3) declare an alias
       log "declare.def" 5 "Not a misspelling: go ahead and declare it!"
       processType eopts nest env fc top Public []
          -- See #3409
          $ MkWithFCTyName fc (MkFCVal fc n) $ holeyType (map snd args)
       defs <- get Ctxt
       lookupCtxtExact n (gamma defs)

  where
    holeyType : List (FC, Name) -> RawImp
    holeyType [] = Implicit fc False
    holeyType ((xfc, x) :: xs)
      = let xfc = virtualiseFC xfc in
        IPi xfc top Explicit (Just x) (Implicit xfc False)
      $ holeyType xs

lookupOrAddAlias _ _ _ fc n _
  = do defs <- get Ctxt
       lookupCtxtExact n (gamma defs)

export
processDef : {vars : _} ->
             {auto c : Ref Ctxt Defs} ->
             {auto m : Ref MD Metadata} ->
             {auto u : Ref UST UState} ->
             {auto dl : Ref DLY DelayedElabs} ->
             {auto s : Ref Syn SyntaxInfo} ->
             {auto o : Ref ROpts REPLOpts} ->
             List ElabOpt -> NestedNames vars -> Env Term vars -> FC ->
             Name -> List ImpClause -> Core ()
processDef opts nest env fc n_in cs_in
  = do n <- inCurrentNS n_in
       withDefStacked n $ do
         defs <- get Ctxt
         Just gdef <- lookupOrAddAlias opts nest env fc n cs_in
           | Nothing => noDeclaration fc n
         let None = definition gdef
              | _ => throw (AlreadyDefined fc n)
         ty <- typeOf gdef
         -- a module's interface hash (what determines when the module has changed)
         -- should include the definition (RHS) of anything that is public (available
         -- at compile time for elaboration) _or_ inlined (dropped into destination definitions
         -- during compilation).
         let hashit = (collapseDefault $ visibility gdef) == Public || (Inline `elem` gdef.flags)
         let mult = if isErased (multiplicity gdef)
                       then erased
                       else linear
         nidx <- resolveName n

         -- Dynamically rebind default totality requirement to this function's totality requirement
         -- and use this requirement when processing `with` blocks
         log "declare.def" 5 $ "Traversing clauses of " ++ show n ++ " with mult " ++ show mult
         let treq = fromMaybe !getDefaultTotalityOption (findSetTotal (flags gdef))
         cs <- withTotality treq $
               traverse (checkClause mult (collapseDefault $ visibility gdef) treq
                                     hashit nidx opts nest env) cs_in

         let pats = map toPats (rights cs)

         (cargs ** (tree_ct, clausePats, unreachable)) <-
             logTime 3 ("Building compile time case tree for " ++ show n) $
                getPMDef fc (CompileTime mult Evaluating) n ty (map (saved mult) (rights cs))

         traverse_ warnUnreachable unreachable

         logC "declare.def" 2 $
                 do t <- toFullNames tree_ct
                    pure ("Case tree for " ++ show n ++ ": " ++ show t)

         -- check whether the name was declared in a different source file
         defs <- get Ctxt
         let pi = case lookup n (userHoles defs) of
                        Nothing => defaultPI
                        Just e => { externalDecl := e } defaultPI
         ignore $ addDef (Resolved nidx)
                  ({ definition := PMDef pi cargs (LiveBody tree_ct clausePats pats)
                   } gdef)
         -- The erased positions found where the type was declared may be
         -- too few: a type that reaches its binders through a definition
         -- declared before and defined after is stuck there. Its clauses
         -- were checked against the whole spine, so it is complete now.
         updateErasable (Resolved nidx)

         when (collapseDefault (visibility gdef) == Public) $
             do let rmetas = getMetas tree_ct
                log "declare.def" 10 $ "Saving from " ++ show n ++ ": " ++ show (keys rmetas)
                traverse_ addToSave (keys rmetas)
         when (isUserName n && collapseDefault (visibility gdef) /= Private) $
             do let tymetas = getMetas ty
                traverse_ addToSave (keys tymetas)
         addToSave n

         atotal <- toResolvedNames (NS builtinNS (knownUN Kassert_total))
         logTime 3 ("Building size change graphs " ++ show n) $
           when (not (InCase `elem` opts)) $
             do calcRefs atotal (Resolved nidx)
                sc <- calculateSizeChange fc n
                setSizeChange fc n sc
                checkIfGuarded fc n

         md <- get MD -- don't need the metadata collected on the coverage check

         cov <- logTime 3 ("Checking Coverage " ++ show n) $ checkCoverage nidx ty mult cs
         setCovering fc n cov
         put MD md
  where
    -- Move `withTotality` to Core.Context if we need it elsewhere
    ||| Temporarily rebind the default totality requirement (%default total/partial/covering).
    withTotality : TotalReq -> Lazy (Core a) -> Core a
    withTotality tot c = do
         defaultTotality <- getDefaultTotalityOption
         setDefaultTotalityOption tot
         x <- catch c (\error => do setDefaultTotalityOption defaultTotality
                                    throw error)
         setDefaultTotalityOption defaultTotality
         pure x


    simplePat : forall vars . Term vars -> Bool
    simplePat (Local {}) = True
    simplePat (Erased {}) = True
    simplePat (As _ _ _ p) = simplePat p
    simplePat _ = False

    -- Is the clause returned from 'checkClause' a catch all clause, i.e.
    -- one where all the arguments are variables? If so, no need to do the
    -- (potentially expensive) coverage check
    catchAll : Clause -> Bool
    catchAll (MkClause env lhs _ _)
       = all simplePat (getArgs lhs)

    -- Return 'Nothing' if the clause is impossible, otherwise return the
    -- checked clause (with implicits filled in, so that we can see if they
    -- match any of the given clauses)
    checkImpossible : Int -> RigCount -> ClosedTerm ->
                      Core (Maybe ClosedTerm)
    checkImpossible n mult tm
        = do itm <- unelabNoPatvars Env.empty tm
             let itm = map rawName itm
             handleUnifyElab
               (do ctxt <- get Ctxt
                   log "declare.def.impossible" 3 $ "Checking for impossibility: " ++ show itm
                   autoimp <- isUnboundImplicits
                   setUnboundImplicits True
                   (_, lhstm) <- bindNames False itm
                   setUnboundImplicits autoimp
                   (lhstm, _) <- elabTerm n (InLHS mult) [] (MkNested []) Env.empty
                                    (IBindHere fc COVERAGE lhstm) Nothing
                   defs <- get Ctxt
                   lhs <- normaliseHoles defs Env.empty lhstm
                   if !(hasEmptyPat defs Env.empty lhs)
                      then do log "declare.def.impossible" 5 "Some empty pat"
                              put Ctxt ctxt
                              pure Nothing
                      else do log "declare.def.impossible" 5 "No empty pat"
                              empty <- clearDefs ctxt
                              rtm <- closeEnv empty !(nf empty Env.empty lhs)
                              put Ctxt ctxt
                              pure (Just rtm))
               (\err => do defs <- get Ctxt
                           if !(impossibleErrOK defs err)
                              then do
                                log "declare.def.impossible" 5 "impossible because \{show err}"
                                pure Nothing
                              else pure (Just tm))
      where
        closeEnv : Defs -> ClosedNF -> Core ClosedTerm
        closeEnv defs (NBind _ x (PVar {}) sc)
            = closeEnv defs !(sc defs (toClosure defaultOpts Env.empty (Ref fc Bound x)))
        closeEnv defs nf = quote defs Env.empty nf

    getClause : Either RawImp Clause -> Core (Maybe Clause)
    getClause (Left rawlhs)
        = catch (do lhsp <- getImpossibleTerm env nest rawlhs
                    log "declare.def.impossible" 3 $ "Generated impossible LHS: " ++ show lhsp
                    pure $ Just $ MkClause Env.empty lhsp (Erased (getFC rawlhs) Impossible) VarSet.empty)
                (\e => do log "declare.def" 5 $ "Error in getClause " ++ show e
                          recordWarning $ GenericWarn (fromMaybe (getFC rawlhs) $ getErrorLoc e) (show e)
                          pure Nothing)
    getClause (Right c) = pure (Just c)

    checkCoverage : Int -> ClosedTerm -> RigCount ->
                    List (Either RawImp Clause) ->
                    Core Covering
    checkCoverage n ty mult cs
        = do covcs' <- traverse getClause cs -- Make stand in LHS for impossible clauses
             log "declare.def" 5 $ unlines
               $ "Using clauses :"
               :: map (("  " ++) . show) !(traverse toFullNames covcs')
             let covcs = mapMaybe id covcs'
             (_ ** (ctree, _, _)) <-
                 getPMDef fc (CompileTime mult CheckingCoverage) (Resolved n) ty covcs
             logC "declare.def" 3 $ do pure $ "Working from " ++ show !(toFullNames ctree)
             missCase <- if any catchAll covcs
                            then do logC "declare.def" 3 $ do pure "Catch all case in \{show !(getFullName (Resolved n))}"
                                    pure []
                            else getMissing fc (Resolved n) ty ctree
             logC "declare.def" 3 $
                     do mc <- traverse toFullNames missCase
                        pure ("Initially missing in " ++
                                 show !(getFullName (Resolved n)) ++ ":\n" ++
                                showSep "\n" (map show mc))
             -- Filter out the ones which are impossible
             missImp <- traverse (checkImpossible n mult) missCase
             -- Filter out the ones which are actually matched (perhaps having
             -- come up due to some overlapping patterns)
             missMatch <- traverse (checkMatched (not $ isErased mult) covcs) (mapMaybe id missImp)
                                              -- ^ Do not check coverage for erased arguments
                                              -- only in non-erased functions (Issues #1998, #3357)
             let miss = catMaybes missMatch
             if isNil miss
                then do [] <- getNonCoveringRefs fc (Resolved n)
                           | ns => toFullNames (NonCoveringCall ns)
                        pure IsCovering
                else pure (MissingCases miss)
