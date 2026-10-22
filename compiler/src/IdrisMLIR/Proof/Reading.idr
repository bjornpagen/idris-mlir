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
||| itself whatever stands for it, and one family is one key; a site's type
||| keeps a redex around a call, which an instance may unfold under the
||| lambda, and reads it as both its forms. The host's
||| relation has no eta step and gains none: its trusted claim that every
||| reduct of a term goes on to the normaliser's result
||| (`Idris.Host.reachesNormalForm`) would then be false, since a
||| contracted term does not reduce back to the uncontracted form the
||| normaliser can return. So contraction is the frontend's own relation
||| (`EtaContracts`), what a reader reads is the host's normal form
||| followed by it (`ReadOff`), and the frontend's contraction
||| (`Closed.contractedBy`) gives its result with that evidence and with
||| the evidence that no redex it contracts is left. What contraction gives
||| is never taller than what it was given (`contractionHeight`), so
||| whatever bounds the normal form bounds what the readers read.
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

||| Where index i of a scope goes once the variable after its first o is
||| dropped: it is that variable, or it has an index without it
||| (`Idris.Host.Dropped`).
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
  ||| Strengthening keeps a term's height: every node is rebuilt from the
  ||| same parts, and no bounds put a value in for a name.
  export
  0 strengthenedHeight : Strengthened o t u -> termHeight u = termHeight t
  strengthenedHeight (MLocal _) = Refl
  strengthenedHeight (MMarker first _) = void (noneReplaces first)
  strengthenedHeight (MRef _) = Refl
  strengthenedHeight (MMeta _ ts) = cong S (allStrengthenedHeight ts)
  strengthenedHeight (MBind b sc) = cong S (cong2 maximum (binderStrengthenedHeight b) (strengthenedHeight sc))
  strengthenedHeight (MApp f a) = cong S (cong2 maximum (strengthenedHeight f) (strengthenedHeight a))
  strengthenedHeight (MAs a t) = cong S (cong2 maximum (strengthenedHeight a) (strengthenedHeight t))
  strengthenedHeight (MDelayed t) = cong S (strengthenedHeight t)
  strengthenedHeight (MDelay ty a) = cong S (cong2 maximum (strengthenedHeight ty) (strengthenedHeight a))
  strengthenedHeight (MForce t) = cong S (strengthenedHeight t)
  strengthenedHeight MPrim = Refl
  strengthenedHeight MPlaceholder = Refl
  strengthenedHeight MImpossible = Refl
  strengthenedHeight (MDotted t) = cong S (strengthenedHeight t)
  strengthenedHeight MType = Refl

  0 allStrengthenedHeight : AllMapped DropsOne None (the (SubstEnv [] []) []) o ts us -> termsHeight us = termsHeight ts
  allStrengthenedHeight MNone = Refl
  allStrengthenedHeight (MEach t ts) = cong2 maximum (strengthenedHeight t) (allStrengthenedHeight ts)

  0 binderStrengthenedHeight : BinderMapped DropsOne None (the (SubstEnv [] []) []) o b b' -> binderHeight b' = binderHeight b
  binderStrengthenedHeight (MLam p ty) = cong2 maximum (piStrengthenedHeight p) (strengthenedHeight ty)
  binderStrengthenedHeight (MLet v ty) = cong2 maximum (strengthenedHeight v) (strengthenedHeight ty)
  binderStrengthenedHeight (MPi p ty) = cong2 maximum (piStrengthenedHeight p) (strengthenedHeight ty)
  binderStrengthenedHeight (MPVar p ty) = cong2 maximum (piStrengthenedHeight p) (strengthenedHeight ty)
  binderStrengthenedHeight (MPLet v ty) = cong2 maximum (strengthenedHeight v) (strengthenedHeight ty)
  binderStrengthenedHeight (MPVTy ty) = strengthenedHeight ty

  0 piStrengthenedHeight : PiMapped DropsOne None (the (SubstEnv [] []) []) o p p' -> piHeight p' = piHeight p
  piStrengthenedHeight MImplicit = Refl
  piStrengthenedHeight MExplicit = Refl
  piStrengthenedHeight MAutoImplicit = Refl
  piStrengthenedHeight (MDefault t) = strengthenedHeight t

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

------------------------------------------------------------------------------
-- Readings
------------------------------------------------------------------------------

||| What a reader reads off a term: the host's reduction of it by a
||| normaliser's steps, then eta contraction of what that reaches.
public export
data ReadOff : NormalForm -> Frozen -> ClosedTerm -> ClosedTerm -> Type where
  ReducedThenContracted : Reduces (evaluationOf form) ctx t v -> EtaContracts v u -> ReadOff form ctx t u

||| A closed term as the growth check's readings take it in the frozen
||| context they read: the host's normal form of it there, eta-contracted,
||| with the normal form it was read in and the contraction that read it,
||| none of which is paid for. The context is an index, so every reading
||| of a site, and every reading of the instances of one, states its
||| normal forms over the one context the whole reading reads.
public export
record NormalReading (form : NormalForm) (ctx : Frozen) (t : ClosedTerm) where
  constructor MkNormalReading
  readForm : ClosedTerm
  0 reduct : Reduct form ctx t
  0 contraction : EtaContracts reduct.value readForm

||| What the readers read is no taller than the host's normal form they
||| read it off.
export
0 readNoTaller : (r : NormalReading form ctx t) -> LTE (termHeight r.readForm) (termHeight r.reduct.value)
readNoTaller r = contractionHeight r.contraction
