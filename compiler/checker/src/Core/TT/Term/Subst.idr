-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.TT.Term.Subst

import Core.FC
import Core.Name.Scoped

import Core.TT.Binder
import Core.TT.Subst
import Core.TT.Term
import Core.TT.Var

import Libraries.Data.List.SizeOf

import Data.Nat

%default total

public export
SubstEnv : Scope -> Scoped
SubstEnv = Subst Term

-- Each kind of node a term holds terms in is substituted by a function of
-- its own, so that every recursive call is on a part of its argument; and
-- each is public, so that a proof over terms with values put in reads off
-- what substitution makes of every node.
mutual
  public export
  substPi : Substitutable Term (PiInfo . Term)
  substPi outer dropped env Implicit = Implicit
  substPi outer dropped env Explicit = Explicit
  substPi outer dropped env AutoImplicit = AutoImplicit
  substPi outer dropped env (DefImplicit t) = DefImplicit (substTerm outer dropped env t)

  public export
  substBinder : Substitutable Term (Binder . Term)
  substBinder outer dropped env (Lam fc c p ty)
      = Lam fc c (substPi outer dropped env p) (substTerm outer dropped env ty)
  substBinder outer dropped env (Let fc c val ty)
      = Let fc c (substTerm outer dropped env val) (substTerm outer dropped env ty)
  substBinder outer dropped env (Pi fc c p ty)
      = Pi fc c (substPi outer dropped env p) (substTerm outer dropped env ty)
  substBinder outer dropped env (PVar fc c p ty)
      = PVar fc c (substPi outer dropped env p) (substTerm outer dropped env ty)
  substBinder outer dropped env (PLet fc c val ty)
      = PLet fc c (substTerm outer dropped env val) (substTerm outer dropped env ty)
  substBinder outer dropped env (PVTy fc c ty) = PVTy fc c (substTerm outer dropped env ty)

  public export
  substTerms : Substitutable Term (List . Term)
  substTerms outer dropped env [] = []
  substTerms outer dropped env (t :: ts)
      = substTerm outer dropped env t :: substTerms outer dropped env ts

  public export
  substTerm : Substitutable Term Term
  substTerm outer dropped env (Local fc r _ prf)
      = find (localOf fc r) outer dropped (MkVar prf) env
  substTerm outer dropped env (Ref fc x name) = Ref fc x name
  substTerm outer dropped env (Meta fc n i xs)
      = Meta fc n i (substTerms outer dropped env xs)
  substTerm outer dropped env (Bind fc x b scope)
      = Bind fc x (substBinder outer dropped env b)
                  (substTerm (suc outer) dropped env scope)
  substTerm outer dropped env (App fc fn arg)
      = App fc (substTerm outer dropped env fn) (substTerm outer dropped env arg)
  substTerm outer dropped env (As fc s as pat)
      = As fc s (substTerm outer dropped env as) (substTerm outer dropped env pat)
  substTerm outer dropped env (TDelayed fc x y) = TDelayed fc x (substTerm outer dropped env y)
  substTerm outer dropped env (TDelay fc x t y)
      = TDelay fc x (substTerm outer dropped env t) (substTerm outer dropped env y)
  substTerm outer dropped env (TForce fc r x) = TForce fc r (substTerm outer dropped env x)
  substTerm outer dropped env (PrimVal fc c) = PrimVal fc c
  substTerm outer dropped env (Erased fc Impossible) = Erased fc Impossible
  substTerm outer dropped env (Erased fc Placeholder) = Erased fc Placeholder
  substTerm outer dropped env (Erased fc (Dotted t)) = Erased fc (Dotted (substTerm outer dropped env t))
  substTerm outer dropped env (TType fc u) = TType fc u

public export
substs : SizeOf dropped -> SubstEnv dropped vars -> Term (dropped ++ vars) -> Term vars
substs dropped env tm = substTerm zero dropped env tm

public export
subst : Term vars -> Term (Scope.bind vars x) -> Term vars
subst val tm = substs (suc zero) [val] tm

------------------------------------------------------------------------
-- What substitution makes of a local

-- A local `i` past `outer` binders, with values put in for the `dropped`
-- variables after them, is one of three things by where `i` is: below the
-- binders, the same local; among the dropped variables, the value put in,
-- weakened under the binders; past them, the same local, `dropped` lower.

||| No sum is below its first part.
export
0 notBelowPlus : {a : Nat} -> LT (a + b) a -> Void
notBelowPlus {a = Z} lt = absurd lt
notBelowPlus {a = S a} (LTESucc lt) = notBelowPlus lt

0 belowFound : (o : SizeOf outer) -> (s : SizeOf dropped) -> (env : SubstEnv dropped vars) ->
               (0 p : IsVar nm i (outer ++ (dropped ++ vars))) -> LT i (size o) ->
               (e : Either (Var outer) (Var (dropped ++ vars))) -> VarLocated {outer = dropped ++ vars} o (MkVar p) e ->
               LocalAt fc r i (foundAt (localOf fc r) o s env e)
belowFound o s env p lt (Left w) (LocatedIn same _)
    = replace {p = \k => LocalAt fc r k (localOf fc r (embed w))} (trans (embedVarIdx w) same)
              (localOfIdx (embed w))
belowFound o s env p lt (Right w) (LocatedPast same)
    = void (notBelowPlus (replace {p = \k => LT k (size o)} same lt))

||| A local below the binders a substitution is under is kept.
export
0 substBelow : (o : SizeOf outer) -> (s : SizeOf dropped) -> (env : SubstEnv dropped vars) ->
               (0 p : IsVar nm i (outer ++ (dropped ++ vars))) -> LT i (size o) ->
               LocalAt fc r i (substTerm o s env (Local fc r i p))
substBelow o s env p lt = belowFound o s env p lt (locateVar {outer = dropped ++ vars} o (MkVar p)) (locateVarLocated {outer = dropped ++ vars} o (MkVar p))

0 middleDropped : (s : SizeOf dropped) -> (env : SubstEnv dropped vars) ->
                  (w1 : Var (dropped ++ vars)) -> (w : Var dropped) -> varIdx w1 = varIdx w ->
                  (e : Either (Var dropped) (Var vars)) -> VarLocated {outer = vars} s w1 e ->
                  droppedAt (localOf fc r) env e = index env w
middleDropped s env w1 w same (Left w2) (LocatedIn same2 _) = cong (index env) (sameVar w2 w (trans same2 same))
middleDropped s env w1 w same (Right w3) (LocatedPast same3)
    = void (notBelowPlus (replace {p = \k => LT k (size s)} (trans (sym same) same3) (varBelowSize s w)))

0 middleFound : (o : SizeOf outer) -> (s : SizeOf dropped) -> (env : SubstEnv dropped vars) ->
                (0 p : IsVar nm i (outer ++ (dropped ++ vars))) -> (w : Var dropped) -> i = size o + varIdx w ->
                (e : Either (Var outer) (Var (dropped ++ vars))) -> VarLocated {outer = dropped ++ vars} o (MkVar p) e ->
                foundAt (localOf fc r) o s env e = weakenNs o (index env w)
middleFound o s env p w eq (Left w0) (LocatedIn _ lt)
    = void (notBelowPlus (replace {p = \k => LT k (size o)} eq lt))
middleFound o s env p w eq (Right w1) (LocatedPast same)
    = cong (weakenNs o)
           (middleDropped s env w1 w (plusLeftCancel (size o) (varIdx w1) (varIdx w) (trans (sym same) eq))
                          (locateVar {outer = vars} s w1) (locateVarLocated {outer = vars} s w1))

||| A local among the variables a substitution puts values in for is the
||| value, weakened under the binders the substitution is under.
export
0 substMiddle : (o : SizeOf outer) -> (s : SizeOf dropped) -> (env : SubstEnv dropped vars) ->
                (0 p : IsVar nm i (outer ++ (dropped ++ vars))) -> (w : Var dropped) -> i = size o + varIdx w ->
                substTerm o s env (Local fc r i p) = weakenNs o (index env w)
substMiddle o s env p w eq = middleFound o s env p w eq (locateVar {outer = dropped ++ vars} o (MkVar p)) (locateVarLocated {outer = dropped ++ vars} o (MkVar p))

0 pastDropped : (o : SizeOf outer) -> (s : SizeOf dropped) -> (env : SubstEnv dropped vars) ->
                (w1 : Var (dropped ++ vars)) -> (k : Nat) -> varIdx w1 = size s + k ->
                (e : Either (Var dropped) (Var vars)) -> VarLocated {outer = vars} s w1 e ->
                LocalAt fc r (size o + k) (weakenNs o (droppedAt (localOf fc r) env e))
pastDropped o s env w1 k eq (Left w2) (LocatedIn _ lt)
    = void (notBelowPlus (replace {p = \x => LT x (size s)} eq lt))
pastDropped o s env w1 k eq (Right (MkVar {varIdx = j} q)) (LocatedPast same)
    = replace {p = \x => LocalAt fc r (size o + x) (weakenNs o (Local fc r j q))}
              (plusLeftCancel (size s) j k (trans (sym same) eq))
              (weakenLocalAt o q)

0 pastFound : (o : SizeOf outer) -> (s : SizeOf dropped) -> (env : SubstEnv dropped vars) ->
              (0 p : IsVar nm i (outer ++ (dropped ++ vars))) -> (k : Nat) -> i = size o + (size s + k) ->
              (e : Either (Var outer) (Var (dropped ++ vars))) -> VarLocated {outer = dropped ++ vars} o (MkVar p) e ->
              LocalAt fc r (size o + k) (foundAt (localOf fc r) o s env e)
pastFound o s env p k eq (Left w0) (LocatedIn _ lt)
    = void (notBelowPlus (replace {p = \x => LT x (size o)} eq lt))
pastFound o s env p k eq (Right w1) (LocatedPast same)
    = pastDropped o s env w1 k (plusLeftCancel (size o) (varIdx w1) (size s + k) (trans (sym same) eq))
                  (locateVar {outer = vars} s w1) (locateVarLocated {outer = vars} s w1)

||| A local past the variables a substitution puts values in for is kept,
||| as many lower as there were of them.
export
0 substPast : (o : SizeOf outer) -> (s : SizeOf dropped) -> (env : SubstEnv dropped vars) ->
              (0 p : IsVar nm i (outer ++ (dropped ++ vars))) -> (k : Nat) -> i = size o + (size s + k) ->
              LocalAt fc r (size o + k) (substTerm o s env (Local fc r i p))
substPast o s env p k eq = pastFound o s env p k eq (locateVar {outer = dropped ++ vars} o (MkVar p)) (locateVarLocated {outer = dropped ++ vars} o (MkVar p))
