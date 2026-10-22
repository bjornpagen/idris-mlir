-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the growth check's readers read of a term: the host's reduction
||| followed by eta contraction, a relation of the frontend's proof beside
||| the host's (`Idris.Host.Reduces`), and the measure contraction never
||| raises.
|||
||| A normal form keeps an eta-redex (`\x => f x`, where `f` does not
||| mention `x`): Idris passes a family as a lambda that applies it, and a
||| method's argument of a type that binds implicits so. Every reading of
||| the growth check takes its term contracted, so that a family is read as
||| itself whatever stands for it, and one family is one key. The host's
||| relation has no eta step and gains none: its trusted claim that every
||| reduct of a term goes on to the normaliser's result
||| (`Idris.Host.reachesNormalForm`) would then be false, since a
||| contracted term does not reduce back to the uncontracted form the
||| normaliser can return. So contraction is the frontend's own relation
||| (`EtaContracts`), what a reader reads is the host's normal form
||| followed by it (`ReadOff`), and the contraction gives its result with
||| that evidence (`Contraction`). What contraction gives is never taller
||| than what it was given (`contractionHeight`), so whatever bounds the
||| normal form bounds what the readers read.
module IdrisMLIR.Proof.Reading

import Core.TT
import Idris.Host

import Control.Relation
import Data.Nat

%default total

------------------------------------------------------------------------------
-- Heights
------------------------------------------------------------------------------

mutual
  ||| How tall a term is: a variable, a name, a constant, a placeholder and
  ||| a universe 1, and any other node one above its tallest part.
  public export
  termHeight : Term vs -> Nat
  termHeight (Local _ _ _ _) = 1
  termHeight (Ref _ _ _) = 1
  termHeight (Meta _ _ _ args) = S (termsHeight args)
  termHeight (Bind _ _ b sc) = S (maximum (binderHeight b) (termHeight sc))
  termHeight (App _ f a) = S (maximum (termHeight f) (termHeight a))
  termHeight (As _ _ a p) = S (maximum (termHeight a) (termHeight p))
  termHeight (TDelayed _ _ t) = S (termHeight t)
  termHeight (TDelay _ _ ty a) = S (maximum (termHeight ty) (termHeight a))
  termHeight (TForce _ _ t) = S (termHeight t)
  termHeight (PrimVal _ _) = 1
  termHeight (Erased _ Placeholder) = 1
  termHeight (Erased _ Impossible) = 1
  termHeight (Erased _ (Dotted t)) = S (termHeight t)
  termHeight (TType _ _) = 1

  ||| The tallest of some terms; 0 for none.
  public export
  termsHeight : List (Term vs) -> Nat
  termsHeight [] = 0
  termsHeight (t :: ts) = maximum (termHeight t) (termsHeight ts)

  ||| The tallest part of a binder: its type, a `let`'s value, a default.
  public export
  binderHeight : Binder (Term vs) -> Nat
  binderHeight (Lam _ _ p ty) = maximum (piHeight p) (termHeight ty)
  binderHeight (Let _ _ v ty) = maximum (termHeight v) (termHeight ty)
  binderHeight (Pi _ _ p ty) = maximum (piHeight p) (termHeight ty)
  binderHeight (PVar _ _ p ty) = maximum (piHeight p) (termHeight ty)
  binderHeight (PLet _ _ v ty) = maximum (termHeight v) (termHeight ty)
  binderHeight (PVTy _ _ ty) = termHeight ty

  ||| A default's height; 0 for any other implicitness, which holds no term.
  public export
  piHeight : PiInfo (Term vs) -> Nat
  piHeight Implicit = 0
  piHeight Explicit = 0
  piHeight AutoImplicit = 0
  piHeight (DefImplicit t) = termHeight t

-- Base states only that `maximum` is above both arguments; the bounds below
-- need that it is the least such.
0 maxLub : {a, c : Nat} -> LTE a b -> LTE c b -> LTE (maximum a c) b
maxLub {a = Z} _ lc = lc
maxLub {a = S _} {c = Z} la _ = la
maxLub {a = S a} {c = S c} (LTESucc la) (LTESucc lc) = LTESucc (maxLub la lc)

0 maxMono : {a, a', c, c' : Nat} -> LTE a a' -> LTE c c' -> LTE (maximum a c) (maximum a' c')
maxMono la lc = maxLub (transitive la (maximumLeftUpperBound _ _)) (transitive lc (maximumRightUpperBound _ _))

------------------------------------------------------------------------------
-- Dropping a variable
------------------------------------------------------------------------------

||| Index i of a scope, once the variable after its first o is dropped, is
||| index j: past the dropped one, one less; below it, the same. The
||| dropped one itself has no index there.
public export
data Dropped : (o, i, j : Nat) -> Type where
  DropPast : Dropped Z (S i) i
  DropBefore : Dropped (S o) Z Z
  DropUnder : Dropped o i j -> Dropped (S o) (S i) (S j)

||| Where index i of a scope goes once the variable after its first o is
||| dropped: it is that variable, or it has an index without it.
public export
data AfterDrop : (o, i : Nat) -> Type where
  IsTheDropped : (0 _ : i = o) -> AfterDrop o i
  Reindexed : (j : Nat) -> (0 _ : Dropped o i j) -> AfterDrop o i

||| Where index i goes, decided on the two numbers.
export
dropIndex : (o, i : Nat) -> AfterDrop o i
dropIndex Z Z = IsTheDropped Refl
dropIndex Z (S i) = Reindexed i DropPast
dropIndex (S o) Z = Reindexed Z DropBefore
dropIndex (S o) (S i) = case dropIndex o i of
  IsTheDropped same => IsTheDropped (cong S same)
  Reindexed j dropped => Reindexed (S j) (DropUnder dropped)

||| A scope `vs` and the scope `ws` it is with its variable after the first
||| o dropped.
public export
data DropsAt : (o : Nat) -> (vs, ws : Scope) -> Type where
  DropsHere : DropsAt Z (x :: vs) vs
  DropsUnder : DropsAt o vs ws -> DropsAt (S o) (y :: vs) (y :: ws)

||| A variable of `vs` other than the dropped one is a variable of `ws`, at
||| the index its drop gives it.
export
0 droppedVar : DropsAt o vs ws -> Dropped o i j -> IsVar n i vs -> IsVar n j ws
droppedVar DropsHere DropPast (Later p) = p
droppedVar (DropsUnder _) DropBefore First = First
droppedVar (DropsUnder d) (DropUnder dropped) (Later p) = Later (droppedVar d dropped p)

mutual
  ||| A term over a scope read over that scope with its variable after the
  ||| first o dropped: the same term, each index past the dropped variable
  ||| one less, where the term does not mention that variable.
  public export
  data Strengthened : Nat -> Term vs -> Term ws -> Type where
    StrLocal : {0 p : IsVar n i vs} -> {0 q : IsVar n j ws} -> Dropped o i j ->
               Strengthened o (Local fc l i p) (Local fc l j q)
    StrRef : Strengthened o (Ref fc nt nm) (Ref fc nt nm)
    StrMeta : AllStrengthened o ts us -> Strengthened o (Meta fc m k ts) (Meta fc m k us)
    StrBind : BinderStrengthened o b b' -> Strengthened (S o) sc sc' ->
              Strengthened o (Bind fc y b sc) (Bind fc y b' sc')
    StrApp : Strengthened o f f' -> Strengthened o a a' -> Strengthened o (App fc f a) (App fc f' a')
    StrAs : Strengthened o a a' -> Strengthened o t t' -> Strengthened o (As fc s a t) (As fc s a' t')
    StrDelayed : Strengthened o t t' -> Strengthened o (TDelayed fc r t) (TDelayed fc r t')
    StrDelay : Strengthened o ty ty' -> Strengthened o a a' ->
               Strengthened o (TDelay fc d ty a) (TDelay fc d ty' a')
    StrForce : Strengthened o t t' -> Strengthened o (TForce fc r t) (TForce fc r t')
    StrPrim : Strengthened o (PrimVal fc c) (PrimVal fc c)
    StrPlaceholder : Strengthened o (Erased fc Placeholder) (Erased fc Placeholder)
    StrImpossible : Strengthened o (Erased fc Impossible) (Erased fc Impossible)
    StrDotted : Strengthened o t t' -> Strengthened o (Erased fc (Dotted t)) (Erased fc (Dotted t'))
    StrType : Strengthened o (TType fc u) (TType fc u)

  ||| Terms strengthened, each in turn.
  public export
  data AllStrengthened : Nat -> List (Term vs) -> List (Term ws) -> Type where
    StrNil : AllStrengthened o [] []
    StrCons : Strengthened o t u -> AllStrengthened o ts us -> AllStrengthened o (t :: ts) (u :: us)

  ||| A binder strengthened: each of its parts.
  public export
  data BinderStrengthened : Nat -> Binder (Term vs) -> Binder (Term ws) -> Type where
    StrLam : PiStrengthened o p p' -> Strengthened o ty ty' -> BinderStrengthened o (Lam fc c p ty) (Lam fc c p' ty')
    StrLet : Strengthened o v v' -> Strengthened o ty ty' -> BinderStrengthened o (Let fc c v ty) (Let fc c v' ty')
    StrPi : PiStrengthened o p p' -> Strengthened o ty ty' -> BinderStrengthened o (Pi fc c p ty) (Pi fc c p' ty')
    StrPVar : PiStrengthened o p p' -> Strengthened o ty ty' ->
              BinderStrengthened o (PVar fc c p ty) (PVar fc c p' ty')
    StrPLet : Strengthened o v v' -> Strengthened o ty ty' ->
              BinderStrengthened o (PLet fc c v ty) (PLet fc c v' ty')
    StrPVTy : Strengthened o ty ty' -> BinderStrengthened o (PVTy fc c ty) (PVTy fc c ty')

  ||| An implicitness strengthened: a default's term.
  public export
  data PiStrengthened : Nat -> PiInfo (Term vs) -> PiInfo (Term ws) -> Type where
    StrImplicit : PiStrengthened o Implicit Implicit
    StrExplicit : PiStrengthened o Explicit Explicit
    StrAutoImplicit : PiStrengthened o AutoImplicit AutoImplicit
    StrDefault : Strengthened o t u -> PiStrengthened o (DefImplicit t) (DefImplicit u)

mutual
  ||| Strengthening keeps a term's height: every node is rebuilt from the
  ||| same parts.
  export
  0 strengthenedHeight : Strengthened o t u -> termHeight u = termHeight t
  strengthenedHeight (StrLocal _) = Refl
  strengthenedHeight StrRef = Refl
  strengthenedHeight (StrMeta ts) = cong S (allStrengthenedHeight ts)
  strengthenedHeight (StrBind b sc) = cong S (cong2 maximum (binderStrengthenedHeight b) (strengthenedHeight sc))
  strengthenedHeight (StrApp f a) = cong S (cong2 maximum (strengthenedHeight f) (strengthenedHeight a))
  strengthenedHeight (StrAs a t) = cong S (cong2 maximum (strengthenedHeight a) (strengthenedHeight t))
  strengthenedHeight (StrDelayed t) = cong S (strengthenedHeight t)
  strengthenedHeight (StrDelay ty a) = cong S (cong2 maximum (strengthenedHeight ty) (strengthenedHeight a))
  strengthenedHeight (StrForce t) = cong S (strengthenedHeight t)
  strengthenedHeight StrPrim = Refl
  strengthenedHeight StrPlaceholder = Refl
  strengthenedHeight StrImpossible = Refl
  strengthenedHeight (StrDotted t) = cong S (strengthenedHeight t)
  strengthenedHeight StrType = Refl

  0 allStrengthenedHeight : AllStrengthened o ts us -> termsHeight us = termsHeight ts
  allStrengthenedHeight StrNil = Refl
  allStrengthenedHeight (StrCons t ts) = cong2 maximum (strengthenedHeight t) (allStrengthenedHeight ts)

  0 binderStrengthenedHeight : BinderStrengthened o b b' -> binderHeight b' = binderHeight b
  binderStrengthenedHeight (StrLam p ty) = cong2 maximum (piStrengthenedHeight p) (strengthenedHeight ty)
  binderStrengthenedHeight (StrLet v ty) = cong2 maximum (strengthenedHeight v) (strengthenedHeight ty)
  binderStrengthenedHeight (StrPi p ty) = cong2 maximum (piStrengthenedHeight p) (strengthenedHeight ty)
  binderStrengthenedHeight (StrPVar p ty) = cong2 maximum (piStrengthenedHeight p) (strengthenedHeight ty)
  binderStrengthenedHeight (StrPLet v ty) = cong2 maximum (strengthenedHeight v) (strengthenedHeight ty)
  binderStrengthenedHeight (StrPVTy ty) = strengthenedHeight ty

  0 piStrengthenedHeight : PiStrengthened o p p' -> piHeight p' = piHeight p
  piStrengthenedHeight StrImplicit = Refl
  piStrengthenedHeight StrExplicit = Refl
  piStrengthenedHeight StrAutoImplicit = Refl
  piStrengthenedHeight (StrDefault t) = strengthenedHeight t

||| What dropping a variable from a part gives: the part over the scope
||| without it, with the evidence; or nothing, where the part mentions it.
public export
data Strengthening : (r : Type) -> (r -> Type) -> Type where
  Strengthens : (u : r) -> (0 _ : ev u) -> Strengthening r ev
  MentionsDropped : Strengthening r ev

mutual
  ||| A term read over its scope with the variable after the first o
  ||| dropped (`Strengthened`), or nothing where it mentions that
  ||| variable: Idris's `shrink` at the thinning that drops it, with the
  ||| evidence, which a contraction needs.
  export
  dropVariable : (o : Nat) -> (0 _ : DropsAt o vs ws) -> (t : Term vs) ->
                 Strengthening (Term ws) (Strengthened o t)
  dropVariable o d (Local fc l idx p) = case dropIndex o idx of
    IsTheDropped _ => MentionsDropped
    Reindexed j dropped => Strengthens (Local fc l j (droppedVar d dropped p)) (StrLocal dropped)
  dropVariable o d (Ref fc nt nm) = Strengthens (Ref fc nt nm) StrRef
  dropVariable o d (Meta fc m k args) = case dropVariableAll o d args of
    MentionsDropped => MentionsDropped
    Strengthens args' s => Strengthens (Meta fc m k args') (StrMeta s)
  dropVariable o d (Bind fc y b sc) = case dropVariableBinder o d b of
    MentionsDropped => MentionsDropped
    Strengthens b' sb => case dropVariable (S o) (DropsUnder d) sc of
      MentionsDropped => MentionsDropped
      Strengthens sc' ss => Strengthens (Bind fc y b' sc') (StrBind sb ss)
  dropVariable o d (App fc f a) = case dropVariable o d f of
    MentionsDropped => MentionsDropped
    Strengthens f' sf => case dropVariable o d a of
      MentionsDropped => MentionsDropped
      Strengthens a' sa => Strengthens (App fc f' a') (StrApp sf sa)
  dropVariable o d (As fc s a t) = case dropVariable o d a of
    MentionsDropped => MentionsDropped
    Strengthens a' sa => case dropVariable o d t of
      MentionsDropped => MentionsDropped
      Strengthens t' st => Strengthens (As fc s a' t') (StrAs sa st)
  dropVariable o d (TDelayed fc r t) = case dropVariable o d t of
    MentionsDropped => MentionsDropped
    Strengthens t' st => Strengthens (TDelayed fc r t') (StrDelayed st)
  dropVariable o d (TDelay fc r ty a) = case dropVariable o d ty of
    MentionsDropped => MentionsDropped
    Strengthens ty' sty => case dropVariable o d a of
      MentionsDropped => MentionsDropped
      Strengthens a' sa => Strengthens (TDelay fc r ty' a') (StrDelay sty sa)
  dropVariable o d (TForce fc r t) = case dropVariable o d t of
    MentionsDropped => MentionsDropped
    Strengthens t' st => Strengthens (TForce fc r t') (StrForce st)
  dropVariable o d (PrimVal fc c) = Strengthens (PrimVal fc c) StrPrim
  dropVariable o d (Erased fc Placeholder) = Strengthens (Erased fc Placeholder) StrPlaceholder
  dropVariable o d (Erased fc Impossible) = Strengthens (Erased fc Impossible) StrImpossible
  dropVariable o d (Erased fc (Dotted t)) = case dropVariable o d t of
    MentionsDropped => MentionsDropped
    Strengthens t' st => Strengthens (Erased fc (Dotted t')) (StrDotted st)
  dropVariable o d (TType fc u) = Strengthens (TType fc u) StrType

  dropVariableAll : (o : Nat) -> (0 _ : DropsAt o vs ws) -> (ts : List (Term vs)) ->
                    Strengthening (List (Term ws)) (AllStrengthened o ts)
  dropVariableAll o d [] = Strengthens [] StrNil
  dropVariableAll o d (t :: ts) = case dropVariable o d t of
    MentionsDropped => MentionsDropped
    Strengthens u s => case dropVariableAll o d ts of
      MentionsDropped => MentionsDropped
      Strengthens us ss => Strengthens (u :: us) (StrCons s ss)

  dropVariableBinder : (o : Nat) -> (0 _ : DropsAt o vs ws) -> (b : Binder (Term vs)) ->
                       Strengthening (Binder (Term ws)) (BinderStrengthened o b)
  dropVariableBinder o d (Lam fc c p ty) = case dropVariablePi o d p of
    MentionsDropped => MentionsDropped
    Strengthens p' sp => case dropVariable o d ty of
      MentionsDropped => MentionsDropped
      Strengthens ty' sty => Strengthens (Lam fc c p' ty') (StrLam sp sty)
  dropVariableBinder o d (Let fc c v ty) = case dropVariable o d v of
    MentionsDropped => MentionsDropped
    Strengthens v' sv => case dropVariable o d ty of
      MentionsDropped => MentionsDropped
      Strengthens ty' sty => Strengthens (Let fc c v' ty') (StrLet sv sty)
  dropVariableBinder o d (Pi fc c p ty) = case dropVariablePi o d p of
    MentionsDropped => MentionsDropped
    Strengthens p' sp => case dropVariable o d ty of
      MentionsDropped => MentionsDropped
      Strengthens ty' sty => Strengthens (Pi fc c p' ty') (StrPi sp sty)
  dropVariableBinder o d (PVar fc c p ty) = case dropVariablePi o d p of
    MentionsDropped => MentionsDropped
    Strengthens p' sp => case dropVariable o d ty of
      MentionsDropped => MentionsDropped
      Strengthens ty' sty => Strengthens (PVar fc c p' ty') (StrPVar sp sty)
  dropVariableBinder o d (PLet fc c v ty) = case dropVariable o d v of
    MentionsDropped => MentionsDropped
    Strengthens v' sv => case dropVariable o d ty of
      MentionsDropped => MentionsDropped
      Strengthens ty' sty => Strengthens (PLet fc c v' ty') (StrPLet sv sty)
  dropVariableBinder o d (PVTy fc c ty) = case dropVariable o d ty of
    MentionsDropped => MentionsDropped
    Strengthens ty' sty => Strengthens (PVTy fc c ty') (StrPVTy sty)

  dropVariablePi : (o : Nat) -> (0 _ : DropsAt o vs ws) -> (p : PiInfo (Term vs)) ->
                   Strengthening (PiInfo (Term ws)) (PiStrengthened o p)
  dropVariablePi o d Implicit = Strengthens Implicit StrImplicit
  dropVariablePi o d Explicit = Strengthens Explicit StrExplicit
  dropVariablePi o d AutoImplicit = Strengthens AutoImplicit StrAutoImplicit
  dropVariablePi o d (DefImplicit t) = case dropVariable o d t of
    MentionsDropped => MentionsDropped
    Strengthens u s => Strengthens (DefImplicit u) (StrDefault s)

------------------------------------------------------------------------------
-- Eta contraction
------------------------------------------------------------------------------

mutual
  ||| A term with eta-redexes contracted anywhere in it: a lambda whose body,
  ||| contracted, applies a term that does not mention the lambda's
  ||| variable to that variable is that term, read without the variable;
  ||| any other node is itself, its parts contracted; and any term is
  ||| itself. Locations, and what a binder's implicitness holds, are kept.
  public export
  data EtaContracts : Term vs -> Term vs -> Type where
    EtaSame : EtaContracts t t
    EtaRedex : {0 p : IsVar n Z (y :: vs)} ->
               EtaContracts sc (App afc f (Local lfc l Z p)) -> Strengthened Z f g ->
               EtaContracts (Bind fc y (Lam bfc c info ty) sc) g
    EtaBind : BinderContracts b b' -> EtaContracts sc sc' -> EtaContracts (Bind fc y b sc) (Bind fc y b' sc')
    EtaApp : EtaContracts f f' -> EtaContracts a a' -> EtaContracts (App fc f a) (App fc f' a')
    EtaAs : EtaContracts a a' -> EtaContracts t t' -> EtaContracts (As fc s a t) (As fc s a' t')
    EtaDelayed : EtaContracts t t' -> EtaContracts (TDelayed fc r t) (TDelayed fc r t')
    EtaDelay : EtaContracts ty ty' -> EtaContracts a a' -> EtaContracts (TDelay fc d ty a) (TDelay fc d ty' a')
    EtaForce : EtaContracts t t' -> EtaContracts (TForce fc r t) (TForce fc r t')
    EtaDotted : EtaContracts t t' -> EtaContracts (Erased fc (Dotted t)) (Erased fc (Dotted t'))

  ||| A binder with its type, and a `let`'s value, contracted.
  public export
  data BinderContracts : Binder (Term vs) -> Binder (Term vs) -> Type where
    EtaLam : EtaContracts ty ty' -> BinderContracts (Lam fc c p ty) (Lam fc c p ty')
    EtaLet : EtaContracts v v' -> EtaContracts ty ty' -> BinderContracts (Let fc c v ty) (Let fc c v' ty')
    EtaPi : EtaContracts ty ty' -> BinderContracts (Pi fc c p ty) (Pi fc c p ty')
    EtaPVar : EtaContracts ty ty' -> BinderContracts (PVar fc c p ty) (PVar fc c p ty')
    EtaPLet : EtaContracts v v' -> EtaContracts ty ty' -> BinderContracts (PLet fc c v ty) (PLet fc c v' ty')
    EtaPVTy : EtaContracts ty ty' -> BinderContracts (PVTy fc c ty) (PVTy fc c ty')

mutual
  ||| Contraction never makes a term taller: a redex's term is a part of the
  ||| lambda's body, read without the variable, which keeps its height
  ||| (`strengthenedHeight`).
  export
  0 contractionHeight : EtaContracts t u -> LTE (termHeight u) (termHeight t)
  contractionHeight EtaSame = reflexive
  contractionHeight (EtaRedex {f} body s) =
    rewrite strengthenedHeight s in
      transitive (maximumLeftUpperBound (termHeight f) 1)
        (transitive (lteSuccRight reflexive)
          (transitive (contractionHeight body)
            (transitive (maximumRightUpperBound _ _) (lteSuccRight reflexive))))
  contractionHeight (EtaBind b sc) = LTESucc (maxMono (binderContractionHeight b) (contractionHeight sc))
  contractionHeight (EtaApp f a) = LTESucc (maxMono (contractionHeight f) (contractionHeight a))
  contractionHeight (EtaAs a t) = LTESucc (maxMono (contractionHeight a) (contractionHeight t))
  contractionHeight (EtaDelayed t) = LTESucc (contractionHeight t)
  contractionHeight (EtaDelay ty a) = LTESucc (maxMono (contractionHeight ty) (contractionHeight a))
  contractionHeight (EtaForce t) = LTESucc (contractionHeight t)
  contractionHeight (EtaDotted t) = LTESucc (contractionHeight t)

  0 binderContractionHeight : BinderContracts b b' -> LTE (binderHeight b') (binderHeight b)
  binderContractionHeight (EtaLam ty) = maxMono reflexive (contractionHeight ty)
  binderContractionHeight (EtaLet v ty) = maxMono (contractionHeight v) (contractionHeight ty)
  binderContractionHeight (EtaPi ty) = maxMono reflexive (contractionHeight ty)
  binderContractionHeight (EtaPVar ty) = maxMono reflexive (contractionHeight ty)
  binderContractionHeight (EtaPLet v ty) = maxMono (contractionHeight v) (contractionHeight ty)
  binderContractionHeight (EtaPVTy ty) = contractionHeight ty

||| A value contracted by a relation, with the contraction that gives it:
||| what the frontend's contraction returns, the evidence at quantity 0.
public export
record Contraction {0 a : Type} (rel : a -> a -> Type) (x : a) where
  constructor MkContraction
  etaForm : a
  0 etaSteps : rel x etaForm

------------------------------------------------------------------------------
-- No step
------------------------------------------------------------------------------

mutual
  ||| Every term reduces to itself, under every evaluation: each node
  ||| rebuilt from its parts by the congruence that steps under it, each
  ||| part reduced to itself. A reading that takes a term as written (a
  ||| dictionary, a shape a constructor heads) reads it off by no step.
  export
  0 reducesRefl : {0 ev : Evaluation} -> {0 ctx : Frozen} -> (t : Term vs) -> Reduces ev ctx t t
  reducesRefl (Local fc l idx p) = ALocal
  reducesRefl (Ref fc nt n) = ARef
  reducesRefl (Meta fc m i args) = AMeta (allReduceRefl args)
  reducesRefl (Bind fc x b sc) = ABind (binderReducesRefl b) (reducesRefl sc)
  reducesRefl (App fc f a) = AnApp (reducesRefl f) (reducesRefl a)
  reducesRefl (As fc s n t) = AnAs (reducesRefl n) (reducesRefl t)
  reducesRefl (TDelayed fc r t) = ADelayed (reducesRefl t)
  reducesRefl (TDelay fc r ty a) = ADelay (reducesRefl ty) (reducesRefl a)
  reducesRefl (TForce fc r t) = AForce (reducesRefl t)
  reducesRefl (PrimVal fc c) = APrimVal
  reducesRefl (Erased fc Placeholder) = AnErased APlaceholder
  reducesRefl (Erased fc Impossible) = AnErased AnImpossible
  reducesRefl (Erased fc (Dotted t)) = AnErased (ADotted (reducesRefl t))
  reducesRefl (TType fc u) = AType

  0 allReduceRefl : {0 ev : Evaluation} -> {0 ctx : Frozen} -> (ts : List (Term vs)) -> AllReduce ev ctx ts ts
  allReduceRefl [] = NoneLeft
  allReduceRefl (t :: ts) = Each (reducesRefl t) (allReduceRefl ts)

  0 binderReducesRefl : {0 ev : Evaluation} -> {0 ctx : Frozen} -> (b : Binder (Term vs)) -> BinderReduces ev ctx b b
  binderReducesRefl (Lam fc c p ty) = ALam (piReducesRefl p) (reducesRefl ty)
  binderReducesRefl (Let fc c v ty) = ALet (reducesRefl v) (reducesRefl ty)
  binderReducesRefl (Pi fc c p ty) = APi (piReducesRefl p) (reducesRefl ty)
  binderReducesRefl (PVar fc c p ty) = APVar (piReducesRefl p) (reducesRefl ty)
  binderReducesRefl (PLet fc c v ty) = APLet (reducesRefl v) (reducesRefl ty)
  binderReducesRefl (PVTy fc c ty) = APVTy (reducesRefl ty)

  0 piReducesRefl : {0 ev : Evaluation} -> {0 ctx : Frozen} -> (p : PiInfo (Term vs)) -> PiReduces ev ctx p p
  piReducesRefl Implicit = AnImplicit
  piReducesRefl Explicit = AnExplicit
  piReducesRefl AutoImplicit = AnAutoImplicit
  piReducesRefl (DefImplicit t) = ADefImplicit (reducesRefl t)

------------------------------------------------------------------------------
-- Readings
------------------------------------------------------------------------------

||| What a reader reads off a term: the host's reduction of it by a
||| normaliser's steps, then eta contraction of what that reaches.
public export
data ReadOff : NormalForm -> Frozen -> ClosedTerm -> ClosedTerm -> Type where
  ReducedThenContracted : Reduces (evaluationOf form) ctx t v -> EtaContracts v u -> ReadOff form ctx t u

||| A closed term as the growth check's readings take it: the host's normal
||| form of it, eta-contracted, with the context and the normal form it was
||| read in and the contraction that read it, none of which is paid for.
public export
record NormalReading (form : NormalForm) (t : ClosedTerm) where
  constructor MkNormalReading
  readForm : ClosedTerm
  0 readIn : Frozen
  0 reduct : Reduct form readIn t
  0 contraction : EtaContracts reduct.value readForm

||| What a normal reading gives is read off the term.
export
0 readingReadOff : (r : NormalReading form t) -> ReadOff form r.readIn t r.readForm
readingReadOff r = ReducedThenContracted r.reduct.steps r.contraction

||| What the readers read is no taller than the host's normal form they
||| read it off.
export
0 readNoTaller : (r : NormalReading form t) -> LTE (termHeight r.readForm) (termHeight r.reduct.value)
readNoTaller r = contractionHeight r.contraction
