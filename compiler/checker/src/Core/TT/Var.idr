-- SPDX-License-Identifier: BSD-3-Clause
-- Copyright (c) 2020 Edwin Brady
module Core.TT.Var

import Data.Fin
import Data.List
import Data.Nat
import Data.So
import Data.SnocList

import Core.Name.Scoped

import Libraries.Data.SnocList.HasLength
import Libraries.Data.SnocList.SizeOf

import Data.List.HasLength
import Data.DPair

import Libraries.Data.List.SizeOf

import Libraries.Data.Erased

%default total

------------------------------------------------------------------------
-- IsVar Predicate

-- TODO need a copy of `IsVar` for both

||| IsVar n k ns is a proof that
||| the name n
||| is a position k
||| in the snoclist ns
public export
data IsVar : a -> Nat -> List a -> Type where
     First : IsVar n Z (n :: ns)
     Later : IsVar n i ns -> IsVar n (S i) (m :: ns)

%name IsVar idx

-- `vs` is available in the erased fragment, and the case builder
-- pattern-matches on it. To simplify the case tree and help the
-- coverage checker, we use an explicit dot pattern here.
-- TODO: remove `{vs = .(_)}` once the compiler generates more optimal case trees.
export
0 Last : HasLength (S n) vs -> Exists (\ nm => IsVar nm n vs)
Last {vs = .(_)} (S Z) = Evidence _ First
Last {vs = .(_)} (S (S p)) = bimap id Later (Last (S p))

export
finIdx : {idx : _} -> (0 prf : IsVar x idx vars) ->
         Fin (length vars)
finIdx First = FZ
finIdx (Later l) = FS (finIdx l)

||| Inversion principle for Later
export
dropLater : IsVar nm (S idx) (n :: ns) -> IsVar nm idx ns
dropLater (Later p) = p

||| Recover the value pointed at by an IsVar proof.
||| O(n) in the size of the index. The walk matches the list and the index,
||| which are values; the proof is erased, so it is only carried down, and
||| it is what makes the empty list impossible.
export
nameAt : {vars : List a} -> {idx : Nat} -> (0 p : IsVar n idx vars) -> a
nameAt {vars = x :: _} {idx = Z} _ = x
nameAt {vars = _ :: xs} {idx = S k} p = nameAt {vars = xs} {idx = k} (dropLater p)
nameAt {vars = []} First impossible
nameAt {vars = []} (Later _) impossible

export
0 mkIsVar : HasLength m inner -> IsVar nm m (inner ++ nm :: outer)
mkIsVar Z = First
mkIsVar (S x) = Later (mkIsVar x)

export
0 mkIsVarChiply : HasLength m inner -> IsVar nm m (inner <>> nm :: outer)
mkIsVarChiply hl
  = rewrite chipsAsListAppend inner (nm :: outer) in
    rewrite sym $ plusZeroRightNeutral m in
    mkIsVar (hlChips hl Z)

||| Compute the remaining scope once the target variable has been removed
public export
dropIsVar :
  (ns : List a) ->
  {idx : Nat} -> (0 p : IsVar name idx ns) ->
  List a
dropIsVar (_ :: xs) First = xs
dropIsVar (n :: xs) (Later p) = n :: dropIsVar xs p

||| Throw in extra variables on the outer side of the context
||| This is essentially the identity function
||| This is slow so we ensure it's only used in a runtime irrelevant manner
export
0 embedIsVar : IsVar x idx xs -> IsVar x idx (xs ++ outer)
embedIsVar First = First
embedIsVar (Later p) = Later (embedIsVar p)

||| Throw in extra variables on the local end of the context.
||| This is slow so we ensure it's only used in a runtime irrelevant manner
export
0 weakenIsVar : (s : SizeOf ns) -> IsVar x idx xs -> IsVar x (size s + idx) (ns ++ xs)
weakenIsVar (MkSizeOf Z Z) p =  p
weakenIsVar (MkSizeOf (S k) (S l)) p =  Later (weakenIsVar (MkSizeOf k l) p)

0 locateIsVarLT :
  (s : SizeOf local) ->
  So (idx < size s) ->
  IsVar x idx (local ++ outer) ->
  IsVar x idx local
locateIsVarLT (MkSizeOf Z Z) so v = case v of
  First impossible
  Later v impossible
locateIsVarLT (MkSizeOf (S k) (S l)) so v = case v of
  First => First
  Later v => Later (locateIsVarLT (MkSizeOf k l) so v)

0 locateIsVarGE :
  (s : SizeOf local) ->
  So (idx >= size s) ->
  IsVar x idx (local ++ outer) ->
  IsVar x (idx `minus` size s) outer
locateIsVarGE (MkSizeOf Z Z) so v = rewrite minusZeroRight idx in v
locateIsVarGE (MkSizeOf (S k) (S l)) so v = case v of
  Later v => locateIsVarGE (MkSizeOf k l) so v

-- Which side of `local` index `idx` is on, as `choose` decides it: a
-- function of its own, so that a proof follows the decision.
locatedBy : {idx : Nat} -> (s : SizeOf local) ->
  (0 p : IsVar x idx (local ++ outer)) ->
  Either (So (idx < size s)) (So (not (idx < size s))) ->
  Either (Erased (IsVar x idx local))
         (Erased (IsVar x (idx `minus` size s) outer))
locatedBy s p (Left so) = Left (MkErased (locateIsVarLT s so p))
locatedBy s p (Right so) = Right (MkErased (locateIsVarGE s so p))

export
locateIsVar : {idx : Nat} -> (s : SizeOf local) ->
  (0 p : IsVar x idx (local ++ outer)) ->
  Either (Erased (IsVar x idx local))
         (Erased (IsVar x (idx `minus` size s) outer))
locateIsVar s p = locatedBy s p (choose (idx < size s))

------------------------------------------------------------------------
-- Variable in scope

||| A variable in a scope is a name, a De Bruijn index,
||| and a proof that the name is at that position in the scope.
||| Everything but the De Bruijn index is erased.
public export
record Var {0 a : Type} (vars : List a) where
  constructor MkVar
  {varIdx : Nat}
  {0 varNm : a}
  0 varPrf : IsVar varNm varIdx vars

namespace Var

  export
  first : Var (n :: ns)
  first = MkVar First

  export
  later : Var ns -> Var (n :: ns)
  later (MkVar p) = MkVar (Later p)

  export
  isLater : Var (n :: vs) -> Maybe (Var vs)
  isLater (MkVar First) = Nothing
  isLater (MkVar (Later p)) = Just (MkVar p)

  export
  last : SizeOf vs -> Maybe (Var vs)
  last (MkSizeOf Z p) = Nothing
  last (MkSizeOf (S n) p) = Just (MkVar (snd $ Last p))

export
mkVar : SizeOf inner -> Var (inner ++ nm :: outer)
mkVar (MkSizeOf s p) = MkVar (mkIsVar p)

export
mkVarChiply : SizeOf inner -> Var (inner <>> nm :: outer)
mkVarChiply (MkSizeOf s p) = MkVar (mkIsVarChiply p)

||| Generate all variables
export
allVars : (vars : Scope) -> List (Var vars)
allVars = go [<] where

  go : SizeOf local -> (vs : Scope) -> List (Var (local <>> vs))
  go s [] = []
  go s (v :: vs) = mkVarChiply s :: go (s :< v) vs

export
Eq (Var xs) where
  v == w = varIdx v == varIdx w

export
Show (Var ns) where
  show v = show (varIdx v)

------------------------------------------------------------------------
-- Named variable in scope

public export
record NVar {0 a : Type} (nm : a) (vars : List a) where
  constructor MkNVar
  {nvarIdx : Nat}
  0 nvarPrf : IsVar nm nvarIdx vars

namespace NVar

  export
  first : NVar n (n :: ns)
  first = MkNVar First

  export
  later : NVar nm ns -> NVar nm (n :: ns)
  later (MkNVar p) = MkNVar (Later p)

  export
  isLater : NVar nm (n :: ns) -> Maybe (NVar nm ns)
  isLater (MkNVar First) = Nothing
  isLater (MkNVar (Later p)) = Just (MkNVar p)

export
forgetName : NVar nm vars -> Var vars
forgetName (MkNVar p) = MkVar p

export
recoverName : (v : Var vars) -> NVar (varNm v) vars
recoverName (MkVar p) = MkNVar p

export
mkNVar : SizeOf inner -> NVar nm (inner ++ nm :: outer)
mkNVar (MkSizeOf s p) = MkNVar (mkIsVar p)

export
mkNVarChiply : SizeOf inner -> NVar nm (inner <>> nm :: outer)
mkNVarChiply (MkSizeOf s p) = MkNVar (mkIsVarChiply p)

-- A named variable on the side its index was found on.
nvarAt : {idx, k : Nat} ->
         Either (Erased (IsVar nm idx local)) (Erased (IsVar nm (idx `minus` k) outer)) ->
         Either (NVar nm local) (NVar nm outer)
nvarAt (Left p) = Left (MkNVar (runErased p))
nvarAt (Right p) = Right (MkNVar (runErased p))

export
locateNVar : SizeOf local -> NVar nm (local ++ outer) ->
             Either (NVar nm local) (NVar nm outer)
locateNVar s (MkNVar p) = nvarAt {k = size s} (locateIsVar s p)

public export
dropNVar : {ns : List a} -> NVar nm ns -> List a
dropNVar (MkNVar p) = dropIsVar ns p

------------------------------------------------------------------------
-- Scope checking

export
isDeBruijn : Nat -> (vars : List Name) -> Maybe (Var vars)
isDeBruijn Z (_ :: _) = pure first
isDeBruijn (S k) (_ :: vs) = later <$> isDeBruijn k vs
isDeBruijn _ _ = Nothing

||| The innermost variable of the scope that has the name. The names are
||| compared as values; the variable's proof names the scope's own, which
||| is the same name.
export
isVar : (n : Name) -> (ns : List Name) -> Maybe (Var ns)
isVar n [] = Nothing
isVar n (m :: ms)
    = if n == m then pure first else later <$> isVar n ms

export
locateVar : SizeOf local -> Var (local ++ outer) ->
            Either (Var local) (Var outer)
locateVar s v  = bimap forgetName forgetName
  $ locateNVar s (recoverName v)

------------------------------------------------------------------------
-- Weakening

export
weakenNVar : SizeOf ns -> NVar name outer -> NVar name (ns ++ outer)
weakenNVar s (MkNVar {nvarIdx} p)
  = MkNVar {nvarIdx = plus (size s) nvarIdx} (weakenIsVar s p)

export
embedNVar : NVar name ns -> NVar name (ns ++ outer)
embedNVar (MkNVar p) = MkNVar (embedIsVar p)

export
insertNVar : SizeOf local ->
             NVar nm (local ++ outer) ->
             NVar nm (local ++ n :: outer)
insertNVar p v = case locateNVar p v of
  Left v => embedNVar v
  Right v => weakenNVar p (later v)

export
insertNVarChiply : SizeOf local ->
  NVar nm (local <>> outer) ->
  NVar nm (local <>> n :: outer)
insertNVarChiply p v
  = rewrite chipsAsListAppend local (n :: outer) in
    insertNVar (p <>> zero)
  $ replace {p = NVar nm} (chipsAsListAppend local outer) v

-- A variable of `local` kept, or one past it moved past `ns` too: its
-- index stated outright, so that a proof reads it off, the scopes' order
-- changed only in the erased proof.
insertedAt : {0 local, ns, outer : Scope} -> SizeOf local -> SizeOf ns ->
             Either (NVar name local) (NVar name outer) ->
             NVar name (local ++ (ns ++ outer))
insertedAt p q (Left v) = embedNVar v
insertedAt p q (Right (MkNVar {nvarIdx} v))
    = MkNVar {nvarIdx = plus (size (p + q)) nvarIdx}
             (rewrite appendAssociative local ns outer in weakenIsVar (p + q) v)

export
insertNVarNames : GenWeakenable (NVar name)
insertNVarNames p q v = insertedAt p q (locateNVar p v)

||| The (partial) inverse to insertNVar
export
removeNVar : SizeOf local ->
         NVar nm (local ++ n :: outer) ->
  Maybe (NVar nm (local ++      outer))
removeNVar s var = case locateNVar s var of
  Left v => pure (embedNVar v)
  Right v => weakenNVar s <$> isLater v

export
insertVar : SizeOf local ->
  Var (local ++ outer) ->
  Var (local ++ n :: outer)
insertVar p v = forgetName $ insertNVar p (recoverName v)

weakenVar : SizeOf ns -> Var outer -> Var (ns ++ outer)
weakenVar p v = forgetName $ weakenNVar p (recoverName v)

insertVarNames : GenWeakenable Var
insertVarNames p q v = forgetName $ insertNVarNames p q (recoverName v)

||| The (partial) inverse to insertVar
export
removeVar : SizeOf local ->
         Var (local ++ n :: outer) ->
  Maybe (Var (local ++      outer))
removeVar s var = forgetName <$> removeNVar s (recoverName var)

------------------------------------------------------------------------
-- Strengthening

export
strengthenIsVar : {n : Nat} -> (s : SizeOf inner) ->
  (0 p : IsVar x n (inner ++ vars)) ->
  Maybe (Erased (IsVar x (n `minus` size s) vars))
strengthenIsVar s p = case locateIsVar s p of
  Left _ => Nothing
  Right p => pure p

strengthenVar : SizeOf inner ->
  Var (inner ++ vars) -> Maybe (Var vars)
strengthenVar s (MkVar p)
  = do MkErased p <- strengthenIsVar s p
       pure (MkVar p)

strengthenNVar : SizeOf inner ->
  NVar x (inner ++ vars) -> Maybe (NVar x vars)
strengthenNVar s (MkNVar p)
  = do MkErased p <- strengthenIsVar s p
       pure (MkNVar p)

------------------------------------------------------------------------
-- Reindexing

0 lookup :
  CompatibleVars xs ys ->
  {idx : Nat} ->
  (0 p : IsVar {a} name idx xs) ->
  a
lookup Pre p = name
lookup (Ext {m} x) First = m
lookup (Ext x) (Later p) = lookup x p

0 compatIsVar :
  (ns : CompatibleVars xs ys) ->
  {idx : Nat} -> (0 p : IsVar name idx xs) ->
  IsVar (lookup ns p) idx ys
compatIsVar Pre p = p
compatIsVar (Ext {n} x) First = First
compatIsVar (Ext {n} x) (Later p) = Later (compatIsVar x p)

||| The variable an index names once the scope's names are renamed: the
||| same index, under the new name at that position.
export
0 renamedIsVar :
  CompatibleVars xs ys ->
  {idx : Nat} -> (0 p : IsVar name idx xs) ->
  Exists (\ n => IsVar n idx ys)
renamedIsVar ns p = Evidence _ (compatIsVar ns p)


compatVar : CompatibleVars xs ys -> Var xs -> Var ys
compatVar prf (MkVar p) = MkVar (compatIsVar prf p)

------------------------------------------------------------------------
-- Thinning

export
thinIsVar : {idx : Nat} -> (0 p : IsVar name idx xs) ->
  Thin xs ys -> Var ys
thinIsVar p Refl = MkVar p
thinIsVar p (Drop th) = later (thinIsVar p th)
thinIsVar First (Keep th) = first
thinIsVar (Later p) (Keep th) = later (thinIsVar p th)

export
shrinkIsVar : {idx : Nat} -> (0 p : IsVar name idx xs) ->
  Thin ys xs -> Maybe (Var ys)
shrinkIsVar prf Refl = Just (MkVar prf)
shrinkIsVar First (Drop p) = Nothing
shrinkIsVar (Later x) (Drop p) = shrinkIsVar x p
shrinkIsVar First (Keep p) = Just first
shrinkIsVar (Later x) (Keep p) = later <$> shrinkIsVar x p

------------------------------------------------------------------------
-- Putting it all together

export
%hint
0 FreelyEmbeddableIsVar : FreelyEmbeddable (IsVar x k)
FreelyEmbeddableIsVar = MkFreelyEmbeddable embedIsVar

export
GenWeaken (Var {a = Name}) where
  genWeakenNs = insertVarNames

%hint
export
WeakenVar : Weaken (Var {a = Name})
WeakenVar = GenWeakenWeakens

export
Strengthen (Var {a = Name}) where
  strengthenNs = strengthenVar

export
FreelyEmbeddable (Var {a = Name}) where
  embed (MkVar p) = MkVar (embedIsVar p)

export
IsScoped (Var {a = Name}) where
  compatNs = compatVar

  thin (MkVar p) = thinIsVar p
  shrink (MkVar p) = shrinkIsVar p

export
GenWeaken (NVar {a = Name} nm) where
  genWeakenNs = insertNVarNames

%hint
export
WeakenNVar : Weaken (NVar {a = Name} nm)
WeakenNVar = GenWeakenWeakens

export
Strengthen (NVar {a = Name} nm) where
  strengthenNs = strengthenNVar

export
FreelyEmbeddable (NVar {a = Name} nm) where
  embed (MkNVar p) = MkNVar (embedIsVar p)

------------------------------------------------------------------------
-- Corollaries

||| Moving the zeroth variable under a set number of variables
export
shiftUnderNs : SizeOf {a = Name} inner ->
               {idx : _} ->
               (0 p : IsVar n idx (x :: inner ++ outer)) ->
               NVar n (inner ++ x :: outer)
shiftUnderNs s First = weakenNs s (MkNVar First)
shiftUnderNs s (Later p) = insertNVar s (MkNVar p)

------------------------------------------------------------------------
-- What each operation does to a variable's index

-- A variable is its index: the name and the proof beside it are erased,
-- and two proofs that a name is at an index of a scope are one proof. So a
-- proof over terms reads off each operation on variables what it does to
-- the index, and nothing else.

||| Two proofs that a name is at an index of a scope name one name.
export
0 isVarName : IsVar n i vs -> IsVar m i vs -> n = m
isVarName First First = Refl
isVarName (Later p) (Later q) = isVarName p q

||| A name is at an index of a scope in one way.
export
0 isVarUnique : (p, q : IsVar n i vs) -> p = q
isVarUnique First First = Refl
isVarUnique (Later p) (Later q) = cong Later (isVarUnique p q)

0 varAtSame : (0 p : IsVar n i vs) -> (0 q : IsVar m i vs) -> n = m -> MkVar p = MkVar q
varAtSame p q Refl = cong (\x => MkVar x) (isVarUnique p q)

||| Two variables of a scope at one index are one variable.
export
0 sameVar : (v, w : Var vs) -> varIdx v = varIdx w -> v = w
sameVar (MkVar p) (MkVar q) Refl = varAtSame p q (isVarName p q)

||| A variable's index is below the size of its scope.
export
0 varBelowSize : (s : SizeOf vs) -> (v : Var vs) -> LT (varIdx v) (size s)
varBelowSize (MkSizeOf n hl) (MkVar p) = below hl p
  where
    below : HasLength k xs -> IsVar x i xs -> LT i k
    below Z First impossible
    below Z (Later _) impossible
    below (S _) First = LTESucc LTEZero
    below (S h) (Later q) = LTESucc (below h q)

||| The variable at each index below the size of a scope.
export
0 varAt : (s : SizeOf vs) -> (j : Nat) -> LT j (size s) -> (w : Var vs ** varIdx w = j)
varAt (MkSizeOf n hl) j lt = at hl j lt
  where
    at : HasLength k xs -> (j : Nat) -> LT j k -> (w : Var xs ** varIdx w = j)
    at Z j lt = absurd lt
    at (S h) Z _ = (MkVar First ** Refl)
    at (S h) (S j) (LTESucc lt) = case at h j lt of
      (MkVar q ** same) => (MkVar (Later q) ** cong S same)

||| An index against a scope of `a` variables, then `b` more: among the
||| first `a`, among the `b` after them, or past both.
public export
data Range : (a, b, i : Nat) -> Type where
  InFirst : (0 _ : LT i a) -> Range a b i
  InSecond : (j : Nat) -> (0 _ : i = a + j) -> (0 _ : LT j b) -> Range a b i
  PastBoth : (k : Nat) -> (0 _ : i = a + (b + k)) -> Range a b i

||| Where an index is against two parts of a scope.
export
0 range : (a, b, i : Nat) -> Range a b i
range Z Z i = PastBoth i Refl
range Z (S b) Z = InSecond Z Refl (LTESucc LTEZero)
range Z (S b) (S i) = case range Z b i of
  InFirst lt => absurd lt
  InSecond j same lt => InSecond (S j) (cong S same) (LTESucc lt)
  PastBoth k same => PastBoth k (cong S same)
range (S a) b Z = InFirst (LTESucc LTEZero)
range (S a) b (S i) = case range a b i of
  InFirst lt => InFirst (LTESucc lt)
  InSecond j same lt => InSecond j (cong S same) lt
  PastBoth k same => PastBoth k (cong S same)

-- An index below a size, or at or past it, as a found side says.
data Side : (bound, idx : Nat) -> Either a b -> Type where
  Below : (0 _ : LT idx bound) -> Side bound idx (Left l)
  Past : (0 _ : LTE bound idx) -> Side bound idx (Right r)

0 notLessIsAtLeast : (m, n : Nat) -> So (not (m < n)) -> LTE n m
notLessIsAtLeast m Z _ = LTEZero
notLessIsAtLeast Z (S k) so = absurd so
notLessIsAtLeast (S j) (S k) so = LTESucc (notLessIsAtLeast j k so)

0 pastMinus : (n, m : Nat) -> LTE n m -> n + (m `minus` n) = m
pastMinus Z m _ = minusZeroRight m
pastMinus (S n) Z lte = absurd lte
pastMinus (S n) (S m) (LTESucc lte) = cong S (pastMinus n m lte)

0 locatedBySide : {idx : Nat} -> (s : SizeOf local) -> (0 p : IsVar x idx (local ++ outer)) ->
                  (c : Either (So (idx < size s)) (So (not (idx < size s)))) ->
                  Side (size s) idx (locatedBy {outer} s p c)
locatedBySide s p (Left so) = Below (ltOpReflectsLT idx (size s) so)
locatedBySide s p (Right so) = Past (notLessIsAtLeast idx (size s) so)

0 locateIsVarSide : {idx : Nat} -> (s : SizeOf local) -> (0 p : IsVar x idx (local ++ outer)) ->
                    Side (size s) idx (locateIsVar {outer} s p)
locateIsVarSide s p = locatedBySide s p (choose (idx < size s))

-- Where `locateNVar` puts a named variable, by its index.
data NLocated : SizeOf local -> NVar nm (local ++ outer) -> Either (NVar nm local) (NVar nm outer) -> Type where
  NIn : (0 _ : nvarIdx w = nvarIdx v) -> (0 _ : LT (nvarIdx v) (size s)) -> NLocated s v (Left w)
  NPast : (0 _ : nvarIdx v = size s + nvarIdx w) -> NLocated s v (Right w)

0 nvarAtLocated : {idx : Nat} -> (s : SizeOf local) -> (0 p : IsVar nm idx (local ++ outer)) ->
                  (e : Either (Erased (IsVar nm idx local)) (Erased (IsVar nm (idx `minus` size s) outer))) ->
                  Side (size s) idx e ->
                  NLocated {outer} s (MkNVar p) (nvarAt {local} {outer} {k = size s} e)
nvarAtLocated s p (Left q) (Below lt) = NIn Refl lt
nvarAtLocated s p (Right q) (Past atLeast) = NPast (sym (pastMinus (size s) idx atLeast))

0 locateNVarLocated : (s : SizeOf local) -> (v : NVar nm (local ++ outer)) -> NLocated {outer} s v (locateNVar {outer} s v)
locateNVarLocated s (MkNVar p) = nvarAtLocated s p (locateIsVar s p) (locateIsVarSide s p)

||| Where `locateVar` puts a variable, by its index: below the local
||| part's size, at the same index there; at or past it, at the index past
||| it.
public export
data VarLocated : SizeOf local -> Var (local ++ outer) -> Either (Var local) (Var outer) -> Type where
  LocatedIn : (0 _ : varIdx w = varIdx v) -> (0 _ : LT (varIdx v) (size s)) -> VarLocated s v (Left w)
  LocatedPast : (0 _ : varIdx v = size s + varIdx w) -> VarLocated s v (Right w)

0 forgetLocated : NLocated {outer} s (MkNVar p) e ->
                  VarLocated {outer} s (MkVar p) (bimap TT.Var.forgetName TT.Var.forgetName e)
forgetLocated (NIn {w = MkNVar q} same lt) = LocatedIn same lt
forgetLocated (NPast {w = MkNVar q} same) = LocatedPast same

||| What `locateVar` does to a variable's index.
export
0 locateVarLocated : (s : SizeOf local) -> (v : Var (local ++ outer)) -> VarLocated {outer} s v (locateVar {outer} s v)
locateVarLocated s (MkVar p) = forgetLocated (locateNVarLocated s (MkNVar p))

||| b + (a + c) is a + (b + c).
export
0 swapPlus : (a, b, c : Nat) -> b + (a + c) = a + (b + c)
swapPlus a Z c = Refl
swapPlus a (S b) c = trans (cong S (swapPlus a b c)) (plusSuccRightSucc a (b + c))

-- The scopes are stated here and below: this module sizes lists and
-- snoc-lists both, and a scope that appears only under `SizeOf` leaves
-- nothing else to say which `size` is meant.
0 insertedAtIdx : {0 local, ns, outer : Scope} ->
                  (p : SizeOf local) -> (q : SizeOf ns) -> (v : NVar name (local ++ outer)) ->
                  (e : Either (NVar name local) (NVar name outer)) -> NLocated {outer} p v e ->
                  Either (LT (nvarIdx v) (size p), nvarIdx (insertedAt {outer} p q e) = nvarIdx v)
                         (LTE (size p) (nvarIdx v),
                          nvarIdx (insertedAt {outer} p q e) = size q + nvarIdx v)
insertedAtIdx p q v (Left (MkNVar w)) (NIn same lt) = Left (lt, same)
insertedAtIdx p q v (Right (MkNVar {nvarIdx = j} w)) (NPast same)
    = Right (replace {p = LTE (size p)} (sym same) (lteAddRight (size p)),
             trans (cong (\x => x + j) (sizeAppend p q))
               (trans (sym (plusAssociative (size p) (size q) j))
                 (trans (swapPlus (size q) (size p) j) (cong (\x => size q + x) (sym same)))))

||| What `insertNVarNames` does to a variable's index: one of `local` keeps
||| it, one past `local` moves past `ns` too.
export
0 insertNVarNamesIdx : {0 local, ns, outer : Scope} ->
                       (p : SizeOf local) -> (q : SizeOf ns) -> (v : NVar name (local ++ outer)) ->
                       Either (LT (nvarIdx v) (size p), nvarIdx (insertNVarNames {outer} p q v) = nvarIdx v)
                              (LTE (size p) (nvarIdx v),
                               nvarIdx (insertNVarNames {outer} p q v) = size q + nvarIdx v)
insertNVarNamesIdx {outer} p q v = insertedAtIdx {outer} p q v (locateNVar {outer} p v) (locateNVarLocated p v)

0 forgetIdx : (w : NVar n vs) -> varIdx (forgetName w) = nvarIdx w
forgetIdx (MkNVar p) = Refl

||| Weakening a variable past `ns` adds their count to its index.
export
0 weakenVarIdx : {0 ns, vars : Scope} -> (s : SizeOf ns) -> (v : Var vars) -> varIdx (weakenNs s v) = size s + varIdx v
weakenVarIdx s (MkVar p) = case insertNVarNamesIdx {outer = vars} zero s (MkNVar p) of
  Left (lt, _) => absurd lt
  Right (_, same) => trans (forgetIdx (insertNVarNames {outer = vars} zero s (MkNVar p))) same

||| Embedding a variable in a larger scope keeps its index.
export
0 embedVarIdx : (v : Var vars) -> varIdx (embed {outer} v) = varIdx v
embedVarIdx (MkVar p) = Refl

||| The variable after `inner`'s is at its size.
export
0 mkVarChiplyIdx : {0 inner : SnocList Name} -> (s : SnocList.SizeOf.SizeOf inner) ->
                   varIdx (mkVarChiply {nm} {outer} s) = size s
mkVarChiplyIdx (MkSizeOf _ _) = Refl
