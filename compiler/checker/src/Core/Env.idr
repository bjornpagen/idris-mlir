-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.Env

import Core.TT
import Data.List

import Libraries.Data.List.SizeOf

import Libraries.Data.VarSet

import Libraries.Data.SnocList.SizeOf

%default total

-- Environment containing types and values of local variables
public export
data Env : (tm : Scoped) -> Scope -> Type where
     Nil : Env tm Scope.empty
     (::) : Binder (tm vars) -> Env tm vars -> Env tm (x :: vars)

%name Env rho

public export
empty : Env tm Scope.empty
empty = []

export
extend : (x : Name) -> Binder (tm vars) -> Env tm vars -> Env tm (x :: vars)
extend x = (::) {x}

export
(++) : {ns : _} -> Env Term ns -> Env Term vars -> Env Term (ns ++ vars)
(++) (b :: bs) e = extend _ (map embed b) (bs ++ e)
(++) [] e = e

export
length : Env tm xs -> Nat
length [] = 0
length (_ :: xs) = S (length xs)

export
eraseLinear : Env tm vs -> Env tm vs
eraseLinear [] = Env.empty
eraseLinear (b :: bs)
    = if isLinear (multiplicity b)
         then setMultiplicity b erased :: eraseLinear bs
         else b :: eraseLinear bs

export
getErased : {0 vs : _} -> Env tm vs -> List (Var vs)
getErased env = go env [<] where

  go : Env tm vars -> SizeOf seen -> List (Var (seen <>> vars))
  go [] p = []
  go (b :: bs) p
    = if isErased (multiplicity b)
         then mkVarChiply p :: go bs (p :< _)
         else go bs (p :< _)

||| A variable of the scope, with the multiplicity of its binder. Its name
||| is the scope's, found equal as a value to the one looked for.
public export
data IsDefined : Scope -> Type where
  MkIsDefined : {idx : Nat} -> {0 n : Name} -> RigCount -> (0 p : IsVar n idx vars) ->
                IsDefined vars

export
defined : {vars : _} ->
          (n : Name) -> Env Term vars ->
          Maybe (IsDefined vars)
defined n [] = Nothing
defined {vars = x :: xs} n (b :: env)
    = if n == x
         then Just (MkIsDefined (multiplicity b) First)
         else do MkIsDefined rig prf <- defined n env
                 pure (MkIsDefined rig (Later prf))

revOnto : (xs, vs : List a) -> reverseOnto xs vs = reverse vs ++ xs
revOnto xs [] = Refl
revOnto xs (v :: vs)
    = rewrite revOnto (v :: xs) vs in
        rewrite appendAssociative (reverse vs) [v] xs in
          rewrite revOnto [v] vs in Refl


-- Weaken by all the names at once at the end, to save multiple traversals
-- in big environments
-- Also reversing the names at the end saves significant time over concatenating
-- when environments get fairly big.
getBinderUnder : Weaken tm =>
                 {vars : _} -> {idx : Nat} ->
                 (ns : Scope) ->
                 (0 p : IsVar x idx vars) -> Env tm vars ->
                 Binder (tm (reverseOnto vars ns))
getBinderUnder {idx = Z} {vars = v :: vs} ns First (b :: env)
    = rewrite revOnto vs (v :: ns) in map (weakenNs (reverse (mkSizeOf (v :: ns)))) b
getBinderUnder {idx = S k} {vars = v :: vs} ns (Later lp) (b :: env)
    = getBinderUnder (v :: ns) lp env

export
getBinder : Weaken tm =>
            {vars : _} -> {idx : Nat} ->
            (0 p : IsVar x idx vars) -> Env tm vars -> Binder (tm vars)
getBinder el env = getBinderUnder Scope.empty el env

-- For getBinderLoc, we are not reusing getBinder because there is no need to
-- needlessly weaken stuff;
export
getBinderLoc : {vars : _} -> {idx : Nat} -> (0 p : IsVar x idx vars) -> Env tm vars -> FC
getBinderLoc {idx = Z}   First     (b :: _)   = binderLoc b
getBinderLoc {idx = S k} (Later p) (_ :: env) = getBinderLoc p env

-- Make a type which abstracts over an environment
-- Don't include 'let' bindings, since they have a concrete value and
-- shouldn't be generalised
export
abstractEnvType : {vars : _} ->
                  FC -> Env Term vars -> (tm : Term vars) -> ClosedTerm
abstractEnvType fc [] tm = tm
abstractEnvType fc (Let fc' c val ty :: env) tm
    = abstractEnvType fc env (Bind fc _ (Let fc' c val ty) tm)
abstractEnvType fc (Pi fc' c e ty :: env) tm
    = abstractEnvType fc env (Bind fc _ (Pi fc' c e ty) tm)
abstractEnvType fc (b :: env) tm
    = let bnd = Pi (binderLoc b) (multiplicity b) Explicit (binderType b)
       in abstractEnvType fc env (Bind fc _ bnd tm)

-- As above, but abstract over all binders including lets
export
abstractFullEnvType : {vars : _} ->
                      FC -> Env Term vars -> (tm : Term vars) -> ClosedTerm
abstractFullEnvType fc [] tm = tm
abstractFullEnvType fc (Pi fc' c e ty :: env) tm
    = abstractFullEnvType fc env (Bind fc _ (Pi fc' c e ty) tm)
abstractFullEnvType fc (b :: env) tm
    = let bnd = Pi fc (multiplicity b) Explicit (binderType b)
      in abstractFullEnvType fc env (Bind fc _ bnd tm)

export
mkExplicit : Env Term vs -> Env Term vs
mkExplicit [] = Env.empty
mkExplicit (Pi fc c _ ty :: env) = Pi fc c Explicit ty :: mkExplicit env
mkExplicit (b :: env) = b :: mkExplicit env

export
letToLam : Env Term vars -> Env Term vars
letToLam [] = []
letToLam (Let fc c val ty :: env) = Lam fc c Explicit ty :: letToLam env
letToLam (b :: env) = b :: letToLam env

-- The locals a term mentions, the types and values of the binders it holds
-- among them, added to a set. A local is not followed to its binder here:
-- what a binder of the environment mentions is added once, by `closeUsed`.
mutual
  usedInTerms : VarSet vars -> List (Term vars) -> VarSet vars
  usedInTerms used [] = used
  usedInTerms used (t :: ts) = usedInTerms (usedIn used t) ts

  -- A binder's type, and a let's value with it (a default implicit's value
  -- is not read).
  usedInBinder : VarSet vars -> Binder (Term vars) -> VarSet vars
  usedInBinder used (Lam _ _ _ ty) = usedIn used ty
  usedInBinder used (Let _ _ val ty) = usedIn (usedIn used val) ty
  usedInBinder used (Pi _ _ _ ty) = usedIn used ty
  usedInBinder used (PVar _ _ _ ty) = usedIn used ty
  usedInBinder used (PLet _ _ val ty) = usedIn (usedIn used val) ty
  usedInBinder used (PVTy _ _ ty) = usedIn used ty

  usedIn : VarSet vars -> Term vars -> VarSet vars
  usedIn used (Local fc r idx p) = VarSet.insert (MkVar p) used
  usedIn used (Meta _ _ _ args) = usedInTerms used args
  usedIn used (Bind fc x b tm)
      = VarSet.dropFirst (usedIn (weaken {tm = VarSet} (usedInBinder used b)) tm)
  usedIn used (App fc fn arg) = usedIn (usedIn used fn) arg
  usedIn used (As fc s a p) = usedIn (usedIn used a) p
  usedIn used (TDelayed fc r tm) = usedIn used tm
  usedIn used (TDelay fc r ty tm) = usedIn (usedIn used ty) tm
  usedIn used (TForce fc r tm) = usedIn used tm
  usedIn used (Erased fc (Dotted tm)) = usedIn used tm
  usedIn used _ = used

------------------------------------------------------------------------------
-- What a term needs of its scope
------------------------------------------------------------------------------

||| A term over the part of its scope it mentions: that part, as the
||| thinning that keeps it, and the term over it. A term covered so is read
||| in any scope that keeps that part by thinning it there, which cannot
||| fail, where strengthening a term into a smaller scope can.
public export
Covered : Scoped -> Scoped
Covered t vars = (kept : Scope ** (Thin kept vars, t kept))

-- The thinning that keeps only the variable at `idx`, and its name.
onlyAt : (vars : Scope) -> (idx : Nat) -> (0 _ : IsVar n idx vars) ->
         (x : Name ** Thin [x] vars)
onlyAt (x :: xs) Z _ = (x ** Keep none)
onlyAt (_ :: xs) (S k) p = let (x ** th) = onlyAt xs k (dropLater p) in (x ** Drop th)
onlyAt [] _ First impossible
onlyAt [] _ (Later _) impossible

-- A scope's cover, from below its binder: what it keeps beyond the bound
-- variable, and the scope over that and the bound variable.
popped : {vars : Scope} -> Covered Term (x :: vars) ->
         (kept : Scope ** (Thin kept vars, Term (x :: kept)))
popped (_ ** (Refl, sc)) = (vars ** (Refl, sc))
popped (kept ** (Drop th, sc)) = (kept ** (th, thin sc (Drop Refl)))
popped ((_ :: kept) ** (Keep th, sc)) = (kept ** (th, sc))

-- Two parts of one node over what either mentions.
pairUp : {vars : Scope} -> Covered Term vars -> Covered Term vars ->
         (kept : Scope ** (Thin kept vars, Term kept, Term kept))
pairUp (_ ** (tha, a)) (_ ** (thb, b))
    = let (u ** (thu, l, r)) = keepBoth tha thb in (u ** (thu, thin a l, thin b r))

mutual
  coverPi : {vars : Scope} -> PiInfo (Term vars) ->
            (kept : Scope ** (Thin kept vars, PiInfo (Term kept)))
  coverPi Implicit = ([] ** (none, Implicit))
  coverPi Explicit = ([] ** (none, Explicit))
  coverPi AutoImplicit = ([] ** (none, AutoImplicit))
  coverPi (DefImplicit t) = let (k ** (th, t')) = cover t in (k ** (th, DefImplicit t'))

  coverPiTy : {vars : Scope} -> PiInfo (Term vars) -> Term vars ->
              (kept : Scope ** (Thin kept vars, PiInfo (Term kept), Term kept))
  coverPiTy p ty
      = let (_ ** (thp, p')) = coverPi p
            (_ ** (tht, ty')) = cover ty
            (u ** (thu, l, r)) = keepBoth thp tht in
            (u ** (thu, map (\t => thin t l) p', thin ty' r))

  ||| A binder over the part of its scope its terms mention.
  export
  coverBinder : {vars : Scope} -> Binder (Term vars) ->
                (kept : Scope ** (Thin kept vars, Binder (Term kept)))
  coverBinder (Lam fc c p ty)
      = let (k ** (th, p', ty')) = coverPiTy p ty in (k ** (th, Lam fc c p' ty'))
  coverBinder (Let fc c val ty)
      = let (k ** (th, val', ty')) = pairUp (cover val) (cover ty) in (k ** (th, Let fc c val' ty'))
  coverBinder (Pi fc c p ty)
      = let (k ** (th, p', ty')) = coverPiTy p ty in (k ** (th, Pi fc c p' ty'))
  coverBinder (PVar fc c p ty)
      = let (k ** (th, p', ty')) = coverPiTy p ty in (k ** (th, PVar fc c p' ty'))
  coverBinder (PLet fc c val ty)
      = let (k ** (th, val', ty')) = pairUp (cover val) (cover ty) in (k ** (th, PLet fc c val' ty'))
  coverBinder (PVTy fc c ty)
      = let (k ** (th, ty')) = cover ty in (k ** (th, PVTy fc c ty'))

  coverAll : {vars : Scope} -> List (Term vars) ->
             (kept : Scope ** (Thin kept vars, List (Term kept)))
  coverAll [] = ([] ** (none, []))
  coverAll (t :: ts)
      = let (_ ** (tht, t')) = cover t
            (_ ** (thts, ts')) = coverAll ts
            (u ** (thu, l, r)) = keepBoth tht thts in
            (u ** (thu, thin t' l :: map (\x => thin x r) ts'))

  ||| A term over the part of its scope it mentions.
  export
  cover : {vars : Scope} -> Term vars -> Covered Term vars
  cover (Local fc r idx p)
      = let (x ** th) = onlyAt vars idx p in ([x] ** (th, Local fc r Z First))
  cover (Ref fc nt n) = ([] ** (none, Ref fc nt n))
  cover (Meta fc n i args)
      = let (k ** (th, args')) = coverAll args in (k ** (th, Meta fc n i args'))
  cover (Bind fc x b sc)
      = let (_ ** (thb, b')) = coverBinder b
            (_ ** (ths, sc')) = popped (cover sc)
            (u ** (thu, l, r)) = keepBoth thb ths in
            (u ** (thu, Bind fc x (map (\t => thin t l) b') (thin sc' (Keep r))))
  cover (App fc f a)
      = let (k ** (th, f', a')) = pairUp (cover f) (cover a) in (k ** (th, App fc f' a'))
  cover (As fc s a p)
      = let (k ** (th, a', p')) = pairUp (cover a) (cover p) in (k ** (th, As fc s a' p'))
  cover (TDelayed fc r t)
      = let (k ** (th, t')) = cover t in (k ** (th, TDelayed fc r t'))
  cover (TDelay fc r ty t)
      = let (k ** (th, ty', t')) = pairUp (cover ty) (cover t) in (k ** (th, TDelay fc r ty' t'))
  cover (TForce fc r t)
      = let (k ** (th, t')) = cover t in (k ** (th, TForce fc r t'))
  cover (PrimVal fc c) = ([] ** (none, PrimVal fc c))
  cover (Erased fc Placeholder) = ([] ** (none, Erased fc Placeholder))
  cover (Erased fc Impossible) = ([] ** (none, Erased fc Impossible))
  cover (Erased fc (Dotted t))
      = let (k ** (th, t')) = cover t in (k ** (th, Erased fc (Dotted t')))
  cover (TType fc u) = ([] ** (none, TType fc u))

||| A part of an environment's variables, closed under their binders: each
||| variable kept, with its binder over the variables kept before it, which
||| keep what that binder mentions. The environment of the part is built as
||| the part is, never strengthened into it.
export
closed : {vars : Scope} -> Env Term vars -> Thin kept vars ->
         (us : Scope ** (Thin us vars, Thin kept us, Env Term us))
closed env Refl = (vars ** (Refl, Refl, env))
closed (b :: env) (Drop th)
    = let (us ** (u, e, env')) = closed env th in (us ** (Drop u, e, env'))
closed {vars = x :: _} (b :: env) (Keep th)
    = let (_ ** (thb, b')) = coverBinder b
          (_ ** (thm, l, r)) = keepBoth th thb
          (us ** (u, e, env')) = closed env thm in
          (x :: us ** (Keep u, Keep (chain l e), map (\t => thin t (chain r e)) b' :: env'))

export
mkEnvOnto : FC -> (xs : List Name) -> Env Term ys -> Env Term (xs ++ ys)
mkEnvOnto fc [] vs = vs
mkEnvOnto fc (n :: ns) vs
   = PVar fc top Explicit (Erased fc Placeholder)
   :: mkEnvOnto fc ns vs

-- Make a dummy environment, if we genuinely don't care about the values
-- and types of the contents.
-- We use this when building and comparing case trees.
export
mkEnv : FC -> (vs : Scope) -> Env Term vs
mkEnv fc [] = []
mkEnv fc (n :: ns) = PVar fc top Explicit (Erased fc Placeholder) :: mkEnv fc ns

export
allVars : {0 vars : _} -> Env Term vars -> List (Var vars)
allVars env = go env [<] where

  go :  {0 vars : _} -> Env Term vars ->
        {0 seen : SnocList Name} -> SizeOf seen ->
        List (Var (seen <>> vars))
  go [] _ = []
  go (v :: vs) p = mkVarChiply p :: go vs (p :< _)


export
allVarsNoLet : {0 vars : _} -> Env Term vars -> List (Var vars)
allVarsNoLet env = go env [<] where

  go :  {0 vars : _} -> Env Term vars ->
        {0 seen : SnocList Name} -> SizeOf seen ->
        List (Var (seen <>> vars))
  go [] _ = []
  go (Let _ _ _ _ :: vs) p = go vs (p :< _)
  go (v :: vs) p = mkVarChiply p :: go vs (p :< _)

export
close : FC -> Ident -> Env Term vars -> Term vars -> ClosedTerm
close fc nm env tm
  = let (s, env) = mkSubstEnv 0 env in
    substs s env (rewrite appendNilRightNeutral vars in tm)

  where
    mkSubstEnv : Int -> Env Term vs -> (SizeOf vs, SubstEnv vs Scope.empty)
    mkSubstEnv i [] = (zero, Subst.empty)
    mkSubstEnv i (v :: vs)
       = let (s, env) = mkSubstEnv (i + 1) vs in
         (suc s, Ref fc Bound (MN nm i) :: env)
