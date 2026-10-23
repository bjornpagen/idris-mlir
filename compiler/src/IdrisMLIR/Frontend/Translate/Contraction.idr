-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Eta contraction as every reader of a static argument takes it: which
||| redexes a contraction contracts, the contraction itself with its
||| evidence (`Proof.Reading.EtaContracts`), and the evidence that no
||| redex it contracts is left in what it gives (`EtaNormal`), with what a
||| growth reading holds of it (`MaximalReading`). None of it runs the
||| frontend's computation, so it sits below the readings an instance is
||| keyed by, which hold that evidence, and below the state that caches
||| them; the closed terms' reductions read it from here.
module IdrisMLIR.Frontend.Translate.Contraction

import Core.Context
import Core.Env
import Core.TT
import Idris.Host

import IdrisMLIR.Frontend.Translate.Definitions
import IdrisMLIR.Proof.Reading
import IdrisMLIR.Proof.Requests

import Data.DPair
import Data.Nat

%default total

||| Which eta-redexes a contraction contracts: every one, as a key, a
||| compared type argument and an instance's reading take a term; or every
||| one but a redex around a call of a definition the context holds, which
||| a site's type keeps. An instance may unfold such a call under the
||| lambda, and the lambda then stays around the unfolding, one level
||| taller than the contracted call; a site keeps the lambda so that its
||| reading reads both forms (`Readings.SEta`).
public export
data Contracting = EveryRedex | CallsKept Context

||| A call whose redex a site's contraction keeps: one of a definition the
||| context holds, by the spine that applies it.
public export
data KeptCall : Contracting -> Term vs -> Type where
  CallOf : (0 _ : Spine g (Ref fc Func n) args) -> (0 _ : definitionAddress ctx n = Just a) -> KeptCall (CallsKept ctx) g

||| Whether a contraction keeps the redex whose contracted term is given: a
||| site's keeps one around a call of a definition the context holds
||| (`KeptCall`), and contracts every other.
public export
data RedexKept : Contracting -> Term vs -> Type where
  KeptAround : {0 why : KeptCall how g} -> RedexKept how g
  ContractedAway : RedexKept how g

-- A call's redex, kept where the context holds the definition called.
keptCall : (ctx : Context) -> (n : Name) -> (0 _ : Spine g (Ref fc Func n) args) -> RedexKept (CallsKept ctx) g
keptCall ctx n headed with (definitionAddress ctx n) proof found
  _ | Just a = KeptAround {why = CallOf headed found}
  _ | Nothing = ContractedAway

||| Whether a contraction keeps the redex that contracts to a term
||| (`RedexKept`), decided once for the contraction and the reading that reads
||| what it kept.
export
keptAround : (how : Contracting) -> (g : Term vs) -> RedexKept how g
keptAround EveryRedex g = ContractedAway
keptAround (CallsKept ctx) g = case spineOf g of
  MkSpineOf (Ref _ Func n) _ headed => keptCall ctx n headed
  MkSpineOf _ _ _ => ContractedAway

------------------------------------------------------------------------------
-- What a term mentions, and what dropping a variable gives
------------------------------------------------------------------------------

mutual
  ||| Where a term mentions its scope's variable at index i: a local of
  ||| that index, or a part that mentions it, under a binder the index one
  ||| deeper; each part a strengthening reads (`Idris.Host.Strengthened`).
  public export
  data Mentions : Nat -> Term vs -> Type where
    MentionsLocal : {0 p : IsVar x i vs} -> Mentions i (Local fc l i p)
    MentionsMeta : AnyMentions i ts -> Mentions i (Meta fc m k ts)
    MentionsBinder : BinderMentions i b -> Mentions i (Bind fc y b sc)
    MentionsScope : Mentions (S i) sc -> Mentions i (Bind fc y b sc)
    MentionsFunction : Mentions i f -> Mentions i (App fc f a)
    MentionsArgument : Mentions i a -> Mentions i (App fc f a)
    MentionsAsName : Mentions i a -> Mentions i (As fc s a t)
    MentionsAsPattern : Mentions i t -> Mentions i (As fc s a t)
    MentionsDelayed : Mentions i t -> Mentions i (TDelayed fc r t)
    MentionsDelayType : Mentions i ty -> Mentions i (TDelay fc r ty a)
    MentionsDelayValue : Mentions i a -> Mentions i (TDelay fc r ty a)
    MentionsForce : Mentions i t -> Mentions i (TForce fc r t)
    MentionsDotted : Mentions i t -> Mentions i (Erased fc (Dotted t))

  ||| One of some terms mentions the variable at index i.
  public export
  data AnyMentions : Nat -> List (Term vs) -> Type where
    MentionedHere : Mentions i t -> AnyMentions i (t :: ts)
    MentionedLater : AnyMentions i ts -> AnyMentions i (t :: ts)

  ||| A binder's implicitness, type or value mentions the variable at
  ||| index i.
  public export
  data BinderMentions : Nat -> Binder (Term vs) -> Type where
    MentionsLamInfo : PiMentions i p -> BinderMentions i (Lam fc c p ty)
    MentionsLamType : Mentions i ty -> BinderMentions i (Lam fc c p ty)
    MentionsLetValue : Mentions i v -> BinderMentions i (Let fc c v ty)
    MentionsLetType : Mentions i ty -> BinderMentions i (Let fc c v ty)
    MentionsPiInfo : PiMentions i p -> BinderMentions i (Pi fc c p ty)
    MentionsPiType : Mentions i ty -> BinderMentions i (Pi fc c p ty)
    MentionsPVarInfo : PiMentions i p -> BinderMentions i (PVar fc c p ty)
    MentionsPVarType : Mentions i ty -> BinderMentions i (PVar fc c p ty)
    MentionsPLetValue : Mentions i v -> BinderMentions i (PLet fc c v ty)
    MentionsPLetType : Mentions i ty -> BinderMentions i (PLet fc c v ty)
    MentionsPVTyType : Mentions i ty -> BinderMentions i (PVTy fc c ty)

  ||| A default implicit's term mentions the variable at index i.
  public export
  data PiMentions : Nat -> PiInfo (Term vs) -> Type where
    MentionsDefault : Mentions i t -> PiMentions i (DefImplicit t)

||| What dropping a variable from a part gives, with the evidence either
||| way: the part over the scope without it, or where the part mentions it.
public export
data Shrinking : (r : Type) -> (r -> Type) -> Type -> Type where
  Shrinks : (u : r) -> (0 _ : ev u) -> Shrinking r ev mentioned
  Needs : (0 _ : mentioned) -> Shrinking r ev mentioned

mutual
  ||| A term read over its scope without the variable after its first o
  ||| (`Idris.Host.Strengthened`), or where it mentions that variable
  ||| (`Mentions`): Idris's `shrink` at the thinning that drops it, with the
  ||| evidence either way, so that a lambda a contraction keeps because its
  ||| function mentions its variable says so.
  export
  dropOrMention : (o : Nat) -> (0 _ : DropsAt o vs ws) -> (t : Term vs) ->
                  Shrinking (Term ws) (Strengthened o t) (Mentions o t)
  dropOrMention o d (Local fc l idx p) = case dropIndex o idx of
    IsTheDropped same => Needs (rewrite sym same in MentionsLocal)
    Reindexed j dropped => Shrinks (Local fc l j (droppedVar d dropped p)) (MLocal dropped)
  dropOrMention o d (Ref fc nt nm) = Shrinks (Ref fc nt nm) (MRef (keptByNone nt))
  dropOrMention o d (Meta fc m k args) = case dropOrMentionAll o d args of
    Needs mentioned => Needs (MentionsMeta mentioned)
    Shrinks args' s => Shrinks (Meta fc m k args') (MMeta NoneHere s)
  dropOrMention o d (Bind fc y b sc) = case dropOrMentionBinder o d b of
    Needs mentioned => Needs (MentionsBinder mentioned)
    Shrinks b' sb => case dropOrMention (S o) (DropsUnder d) sc of
      Needs mentioned => Needs (MentionsScope mentioned)
      Shrinks sc' ss => Shrinks (Bind fc y b' sc') (MBind sb ss)
  dropOrMention o d (App fc f a) = case dropOrMention o d f of
    Needs mentioned => Needs (MentionsFunction mentioned)
    Shrinks f' sf => case dropOrMention o d a of
      Needs mentioned => Needs (MentionsArgument mentioned)
      Shrinks a' sa => Shrinks (App fc f' a') (MApp sf sa)
  dropOrMention o d (As fc s a t) = case dropOrMention o d a of
    Needs mentioned => Needs (MentionsAsName mentioned)
    Shrinks a' sa => case dropOrMention o d t of
      Needs mentioned => Needs (MentionsAsPattern mentioned)
      Shrinks t' st => Shrinks (As fc s a' t') (MAs sa st)
  dropOrMention o d (TDelayed fc r t) = case dropOrMention o d t of
    Needs mentioned => Needs (MentionsDelayed mentioned)
    Shrinks t' st => Shrinks (TDelayed fc r t') (MDelayed st)
  dropOrMention o d (TDelay fc r ty a) = case dropOrMention o d ty of
    Needs mentioned => Needs (MentionsDelayType mentioned)
    Shrinks ty' sty => case dropOrMention o d a of
      Needs mentioned => Needs (MentionsDelayValue mentioned)
      Shrinks a' sa => Shrinks (TDelay fc r ty' a') (MDelay sty sa)
  dropOrMention o d (TForce fc r t) = case dropOrMention o d t of
    Needs mentioned => Needs (MentionsForce mentioned)
    Shrinks t' st => Shrinks (TForce fc r t') (MForce st)
  dropOrMention o d (PrimVal fc c) = Shrinks (PrimVal fc c) MPrim
  dropOrMention o d (Erased fc Placeholder) = Shrinks (Erased fc Placeholder) MPlaceholder
  dropOrMention o d (Erased fc Impossible) = Shrinks (Erased fc Impossible) MImpossible
  dropOrMention o d (Erased fc (Dotted t)) = case dropOrMention o d t of
    Needs mentioned => Needs (MentionsDotted mentioned)
    Shrinks t' st => Shrinks (Erased fc (Dotted t')) (MDotted st)
  dropOrMention o d (TType fc u) = Shrinks (TType fc u) MType

  dropOrMentionAll : (o : Nat) -> (0 _ : DropsAt o vs ws) -> (ts : List (Term vs)) ->
                     Shrinking (List (Term ws)) (AllMapped DropsOne None (the (SubstEnv [] []) []) o ts) (AnyMentions o ts)
  dropOrMentionAll o d [] = Shrinks [] MNone
  dropOrMentionAll o d (t :: ts) = case dropOrMention o d t of
    Needs mentioned => Needs (MentionedHere mentioned)
    Shrinks u s => case dropOrMentionAll o d ts of
      Needs mentioned => Needs (MentionedLater mentioned)
      Shrinks us ss => Shrinks (u :: us) (MEach s ss)

  dropOrMentionBinder : (o : Nat) -> (0 _ : DropsAt o vs ws) -> (b : Binder (Term vs)) ->
                        Shrinking (Binder (Term ws)) (BinderMapped DropsOne None (the (SubstEnv [] []) []) o b)
                                  (BinderMentions o b)
  dropOrMentionBinder o d (Lam fc c p ty) = case dropOrMentionPi o d p of
    Needs mentioned => Needs (MentionsLamInfo mentioned)
    Shrinks p' sp => case dropOrMention o d ty of
      Needs mentioned => Needs (MentionsLamType mentioned)
      Shrinks ty' sty => Shrinks (Lam fc c p' ty') (MLam sp sty)
  dropOrMentionBinder o d (Let fc c v ty) = case dropOrMention o d v of
    Needs mentioned => Needs (MentionsLetValue mentioned)
    Shrinks v' sv => case dropOrMention o d ty of
      Needs mentioned => Needs (MentionsLetType mentioned)
      Shrinks ty' sty => Shrinks (Let fc c v' ty') (MLet sv sty)
  dropOrMentionBinder o d (Pi fc c p ty) = case dropOrMentionPi o d p of
    Needs mentioned => Needs (MentionsPiInfo mentioned)
    Shrinks p' sp => case dropOrMention o d ty of
      Needs mentioned => Needs (MentionsPiType mentioned)
      Shrinks ty' sty => Shrinks (Pi fc c p' ty') (MPi sp sty)
  dropOrMentionBinder o d (PVar fc c p ty) = case dropOrMentionPi o d p of
    Needs mentioned => Needs (MentionsPVarInfo mentioned)
    Shrinks p' sp => case dropOrMention o d ty of
      Needs mentioned => Needs (MentionsPVarType mentioned)
      Shrinks ty' sty => Shrinks (PVar fc c p' ty') (MPVar sp sty)
  dropOrMentionBinder o d (PLet fc c v ty) = case dropOrMention o d v of
    Needs mentioned => Needs (MentionsPLetValue mentioned)
    Shrinks v' sv => case dropOrMention o d ty of
      Needs mentioned => Needs (MentionsPLetType mentioned)
      Shrinks ty' sty => Shrinks (PLet fc c v' ty') (MPLet sv sty)
  dropOrMentionBinder o d (PVTy fc c ty) = case dropOrMention o d ty of
    Needs mentioned => Needs (MentionsPVTyType mentioned)
    Shrinks ty' sty => Shrinks (PVTy fc c ty') (MPVTy sty)

  dropOrMentionPi : (o : Nat) -> (0 _ : DropsAt o vs ws) -> (p : PiInfo (Term vs)) ->
                    Shrinking (PiInfo (Term ws)) (PiMapped DropsOne None (the (SubstEnv [] []) []) o p) (PiMentions o p)
  dropOrMentionPi o d Implicit = Shrinks Implicit MImplicit
  dropOrMentionPi o d Explicit = Shrinks Explicit MExplicit
  dropOrMentionPi o d AutoImplicit = Shrinks AutoImplicit MAutoImplicit
  dropOrMentionPi o d (DefImplicit t) = case dropOrMention o d t of
    Needs mentioned => Needs (MentionsDefault mentioned)
    Shrinks u s => Shrinks (DefImplicit u) (MDefault s)

------------------------------------------------------------------------------
-- What a contraction leaves
------------------------------------------------------------------------------

||| Whether a term is its scope's innermost variable.
public export
isInnermost : Term vs -> Bool
isInnermost (Local _ _ Z _) = True
isInnermost _ = False

||| Whether a lambda's body applies a term to the lambda's variable: the
||| shape of a redex.
public export
appliesVariable : Term vs -> Bool
appliesVariable (App _ _ a) = isInnermost a
appliesVariable _ = False

-- A lambda's body by the shape of a redex: a term applied to the lambda's
-- variable, or anything else.
data LambdaBody : Term vs -> Type where
  AppliedToVariable : (f : Term vs) -> (0 _ : b = App afc f (Local vfc l Z p)) -> LambdaBody b
  NotApplied : (0 _ : appliesVariable b = False) -> LambdaBody b

lambdaBody : (b : Term vs) -> LambdaBody b
lambdaBody (App afc f (Local vfc l Z p)) = AppliedToVariable f Refl
lambdaBody (App afc f (Local vfc l (S i) p)) = NotApplied Refl
lambdaBody (App afc f (Ref rfc nt n)) = NotApplied Refl
lambdaBody (App afc f (Meta mfc m k ts)) = NotApplied Refl
lambdaBody (App afc f (Bind bfc y b sc)) = NotApplied Refl
lambdaBody (App afc f (App gfc g a)) = NotApplied Refl
lambdaBody (App afc f (As sfc s a t)) = NotApplied Refl
lambdaBody (App afc f (TDelayed dfc r t)) = NotApplied Refl
lambdaBody (App afc f (TDelay dfc r ty a)) = NotApplied Refl
lambdaBody (App afc f (TForce ffc r t)) = NotApplied Refl
lambdaBody (App afc f (PrimVal pfc c)) = NotApplied Refl
lambdaBody (App afc f (Erased efc w)) = NotApplied Refl
lambdaBody (App afc f (TType tfc u)) = NotApplied Refl
lambdaBody (Local fc l i p) = NotApplied Refl
lambdaBody (Ref fc nt n) = NotApplied Refl
lambdaBody (Meta fc m k ts) = NotApplied Refl
lambdaBody (Bind fc y b sc) = NotApplied Refl
lambdaBody (As fc s a t) = NotApplied Refl
lambdaBody (TDelayed fc r t) = NotApplied Refl
lambdaBody (TDelay fc r ty a) = NotApplied Refl
lambdaBody (TForce fc r t) = NotApplied Refl
lambdaBody (PrimVal fc c) = NotApplied Refl
lambdaBody (Erased fc w) = NotApplied Refl
lambdaBody (TType fc u) = NotApplied Refl

||| Why a contraction left a lambda, by its body: the body applies no term
||| to the lambda's variable; or applies one that mentions it, which no
||| contraction drops it from; or applies a call whose redex the
||| contraction keeps (`KeptCall`).
public export
data LambdaLeft : Contracting -> Term vs -> Type where
  NoRedex : (0 _ : appliesVariable body = False) -> LambdaLeft how body
  UsedByFunction : (0 _ : Mentions Z f) -> LambdaLeft how (App afc f (Local vfc l Z p))
  CallKept : (0 _ : KeptCall how f) -> LambdaLeft how (App afc f (Local vfc l Z p))

mutual
  ||| A term that holds no redex a contraction contracts (`Contracting`):
  ||| at every lambda the contraction reads, its reason to stay
  ||| (`LambdaLeft`), and every part the contraction reads so too. A
  ||| metavariable's arguments and what a binder's implicitness holds are
  ||| no part any reading contracts, and are as written.
  public export
  data EtaNormal : Contracting -> Term vs -> Type where
    NormalLambda : EtaNormal how ty -> EtaNormal how sc -> LambdaLeft how sc ->
                   EtaNormal how (Bind fc x (Lam lfc rig info ty) sc)
    NormalBinder : BinderNormal how b -> EtaNormal how sc -> EtaNormal how (Bind fc x b sc)
    NormalApp : EtaNormal how f -> EtaNormal how a -> EtaNormal how (App fc f a)
    NormalAs : EtaNormal how a -> EtaNormal how t -> EtaNormal how (As fc s a t)
    NormalDelayed : EtaNormal how t -> EtaNormal how (TDelayed fc r t)
    NormalDelay : EtaNormal how ty -> EtaNormal how a -> EtaNormal how (TDelay fc r ty a)
    NormalForce : EtaNormal how t -> EtaNormal how (TForce fc r t)
    NormalDotted : EtaNormal how t -> EtaNormal how (Erased fc (Dotted t))
    NormalLocal : EtaNormal how (Local fc l i p)
    NormalRef : EtaNormal how (Ref fc nt n)
    NormalMeta : EtaNormal how (Meta fc m k ts)
    NormalPrim : EtaNormal how (PrimVal fc c)
    NormalPlaceholder : EtaNormal how (Erased fc Placeholder)
    NormalImpossible : EtaNormal how (Erased fc Impossible)
    NormalType : EtaNormal how (TType fc u)

  ||| A binder other than a lambda, which is a node of its own, with its
  ||| type and a `let`'s value so.
  public export
  data BinderNormal : Contracting -> Binder (Term vs) -> Type where
    NormalLet : EtaNormal how v -> EtaNormal how ty -> BinderNormal how (Let fc c v ty)
    NormalPi : EtaNormal how ty -> BinderNormal how (Pi fc c p ty)
    NormalPVar : EtaNormal how ty -> BinderNormal how (PVar fc c p ty)
    NormalPLet : EtaNormal how v -> EtaNormal how ty -> BinderNormal how (PLet fc c v ty)
    NormalPVTy : EtaNormal how ty -> BinderNormal how (PVTy fc c ty)

||| A term contracted as a contraction contracts it (`Contracting`), with
||| the contraction that gives it (`Proof.Reading.EtaContracts`) and the
||| evidence that it is maximal, no redex the contraction contracts left
||| in it (`EtaNormal`), both at quantity 0.
public export
record Contracted {0 vs : Scope} (how : Contracting) (t : Term vs) where
  constructor MkContracted
  etaForm : Term vs
  0 etaSteps : EtaContracts t etaForm
  0 etaNormal : EtaNormal how etaForm

------------------------------------------------------------------------------
-- Strengthening keeps what a contraction leaves
------------------------------------------------------------------------------

mutual
  -- A mention of a variable other than the one a strengthening drops,
  -- strengthened: a mention of that variable at the index the drop gives.
  0 mentionKept : Strengthened o t u -> Mentions i t -> (j : Nat ** (Dropped o i j, Mentions j u))
  mentionKept (MLocal {j} moved) MentionsLocal = (j ** (moved, MentionsLocal))
  mentionKept (MMeta _ ms) (MentionsMeta mentioned) = case anyMentionKept ms mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsMeta kept))
  mentionKept (MBind mb _) (MentionsBinder mentioned) = case binderMentionKept mb mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsBinder kept))
  mentionKept (MBind _ ms) (MentionsScope mentioned) = case mentionKept ms mentioned of
    (_ ** (DropUnder {j} dropped, kept)) => (j ** (dropped, MentionsScope kept))
  mentionKept (MApp mf _) (MentionsFunction mentioned) = case mentionKept mf mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsFunction kept))
  mentionKept (MApp _ ma) (MentionsArgument mentioned) = case mentionKept ma mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsArgument kept))
  mentionKept (MAs ma _) (MentionsAsName mentioned) = case mentionKept ma mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsAsName kept))
  mentionKept (MAs _ mt) (MentionsAsPattern mentioned) = case mentionKept mt mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsAsPattern kept))
  mentionKept (MDelayed mt) (MentionsDelayed mentioned) = case mentionKept mt mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsDelayed kept))
  mentionKept (MDelay mty _) (MentionsDelayType mentioned) = case mentionKept mty mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsDelayType kept))
  mentionKept (MDelay _ ma) (MentionsDelayValue mentioned) = case mentionKept ma mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsDelayValue kept))
  mentionKept (MForce mt) (MentionsForce mentioned) = case mentionKept mt mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsForce kept))
  mentionKept (MDotted mt) (MentionsDotted mentioned) = case mentionKept mt mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsDotted kept))

  0 anyMentionKept : AllMapped DropsOne None (the (SubstEnv [] []) []) o ts us -> AnyMentions i ts ->
                     (j : Nat ** (Dropped o i j, AnyMentions j us))
  anyMentionKept (MEach m _) (MentionedHere mentioned) = case mentionKept m mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionedHere kept))
  anyMentionKept (MEach _ ms) (MentionedLater mentioned) = case anyMentionKept ms mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionedLater kept))

  0 binderMentionKept : BinderMapped DropsOne None (the (SubstEnv [] []) []) o b b' -> BinderMentions i b ->
                        (j : Nat ** (Dropped o i j, BinderMentions j b'))
  binderMentionKept (MLam mp _) (MentionsLamInfo mentioned) = case piMentionKept mp mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsLamInfo kept))
  binderMentionKept (MLam _ mty) (MentionsLamType mentioned) = case mentionKept mty mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsLamType kept))
  binderMentionKept (MLet mv _) (MentionsLetValue mentioned) = case mentionKept mv mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsLetValue kept))
  binderMentionKept (MLet _ mty) (MentionsLetType mentioned) = case mentionKept mty mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsLetType kept))
  binderMentionKept (MPi mp _) (MentionsPiInfo mentioned) = case piMentionKept mp mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsPiInfo kept))
  binderMentionKept (MPi _ mty) (MentionsPiType mentioned) = case mentionKept mty mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsPiType kept))
  binderMentionKept (MPVar mp _) (MentionsPVarInfo mentioned) = case piMentionKept mp mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsPVarInfo kept))
  binderMentionKept (MPVar _ mty) (MentionsPVarType mentioned) = case mentionKept mty mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsPVarType kept))
  binderMentionKept (MPLet mv _) (MentionsPLetValue mentioned) = case mentionKept mv mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsPLetValue kept))
  binderMentionKept (MPLet _ mty) (MentionsPLetType mentioned) = case mentionKept mty mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsPLetType kept))
  binderMentionKept (MPVTy mty) (MentionsPVTyType mentioned) = case mentionKept mty mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsPVTyType kept))

  0 piMentionKept : PiMapped DropsOne None (the (SubstEnv [] []) []) o p p' -> PiMentions i p ->
                    (j : Nat ** (Dropped o i j, PiMentions j p'))
  piMentionKept (MDefault m) (MentionsDefault mentioned) = case mentionKept m mentioned of
    (j ** (dropped, kept)) => (j ** (dropped, MentionsDefault kept))

-- A call's spine, strengthened: the same head over its arguments
-- strengthened.
0 spineKept : {0 t : Term xs} -> {0 u : Term ys} -> Strengthened o t u -> Spine t (Ref fc Func n) args ->
              (args' : List (Term ys) ** Spine u (Ref fc Func n) args')
spineKept (MRef _) Host.Head = ([] ** Host.Head)
spineKept (MApp {a'} mf _) (Host.Applied s) = case spineKept mf s of
  (args' ** s') => (args' ++ [a'] ** Host.Applied s')

-- A call a contraction keeps the redex around, strengthened, is still one.
0 keptKept : Strengthened o f f' -> KeptCall how f -> KeptCall how f'
keptKept s (CallOf headed defined) = case spineKept s headed of
  (_ ** headed') => CallOf headed' defined

-- Strengthening under a lambda keeps what is not its variable.
0 notInnermostKept : Strengthened (S o) a a' -> isInnermost a = False -> isInnermost a' = False
notInnermostKept (MLocal DropBefore) none = absurd none
notInnermostKept (MLocal (DropUnder _)) _ = Refl
notInnermostKept (MMarker first _) _ = void (noneReplaces first)
notInnermostKept (MRef _) _ = Refl
notInnermostKept (MMeta _ _) _ = Refl
notInnermostKept (MBind _ _) _ = Refl
notInnermostKept (MApp _ _) _ = Refl
notInnermostKept (MAs _ _) _ = Refl
notInnermostKept (MDelayed _) _ = Refl
notInnermostKept (MDelay _ _) _ = Refl
notInnermostKept (MForce _) _ = Refl
notInnermostKept MPrim _ = Refl
notInnermostKept MPlaceholder _ = Refl
notInnermostKept MImpossible _ = Refl
notInnermostKept (MDotted _) _ = Refl
notInnermostKept MType _ = Refl

-- A body that applies nothing to its lambda's variable, strengthened under
-- the lambda, applies nothing to it either.
0 notAppliedKept : Strengthened (S o) b b' -> appliesVariable b = False -> appliesVariable b' = False
notAppliedKept (MApp _ ma) none = notInnermostKept ma none
notAppliedKept (MLocal _) _ = Refl
notAppliedKept (MMarker first _) _ = void (noneReplaces first)
notAppliedKept (MRef _) _ = Refl
notAppliedKept (MMeta _ _) _ = Refl
notAppliedKept (MBind _ _) _ = Refl
notAppliedKept (MAs _ _) _ = Refl
notAppliedKept (MDelayed _) _ = Refl
notAppliedKept (MDelay _ _) _ = Refl
notAppliedKept (MForce _) _ = Refl
notAppliedKept MPrim _ = Refl
notAppliedKept MPlaceholder _ = Refl
notAppliedKept MImpossible _ = Refl
notAppliedKept (MDotted _) _ = Refl
notAppliedKept MType _ = Refl

-- Why a lambda stayed, strengthened under it: its variable stays local 0,
-- what mentions it still does, and the call its redex is kept around is
-- still one.
0 leftKept : Strengthened (S o) b b' -> LambdaLeft how b -> LambdaLeft how b'
leftKept s (NoRedex none) = NoRedex (notAppliedKept s none)
leftKept (MApp mf (MLocal DropBefore)) (UsedByFunction mentioned) = case mentionKept mf mentioned of
  (_ ** (DropBefore, kept)) => UsedByFunction kept
leftKept (MApp mf (MLocal DropBefore)) (CallKept why) = CallKept (keptKept mf why)

mutual
  ||| A term that holds no redex a contraction contracts, strengthened,
  ||| holds none: strengthening rebuilds each node from its parts, and
  ||| keeps each lambda's reason to stay (`leftKept`), so what a redex
  ||| contracts to is as maximal as the body it came from.
  export
  0 normalKept : Strengthened o t u -> EtaNormal how t -> EtaNormal how u
  normalKept (MBind (MLam _ mty) ms) (NormalLambda nty nsc left) =
    NormalLambda (normalKept mty nty) (normalKept ms nsc) (leftKept ms left)
  normalKept (MBind mb ms) (NormalBinder nb nsc) = NormalBinder (binderNormalKept mb nb) (normalKept ms nsc)
  normalKept (MApp mf ma) (NormalApp nf na) = NormalApp (normalKept mf nf) (normalKept ma na)
  normalKept (MAs ma mt) (NormalAs na nt) = NormalAs (normalKept ma na) (normalKept mt nt)
  normalKept (MDelayed mt) (NormalDelayed nt) = NormalDelayed (normalKept mt nt)
  normalKept (MDelay mty ma) (NormalDelay nty na) = NormalDelay (normalKept mty nty) (normalKept ma na)
  normalKept (MForce mt) (NormalForce nt) = NormalForce (normalKept mt nt)
  normalKept (MDotted mt) (NormalDotted nt) = NormalDotted (normalKept mt nt)
  normalKept (MLocal _) NormalLocal = NormalLocal
  normalKept (MRef _) NormalRef = NormalRef
  normalKept (MMarker first _) NormalRef = void (noneReplaces first)
  normalKept (MMeta _ _) NormalMeta = NormalMeta
  normalKept MPrim NormalPrim = NormalPrim
  normalKept MPlaceholder NormalPlaceholder = NormalPlaceholder
  normalKept MImpossible NormalImpossible = NormalImpossible
  normalKept MType NormalType = NormalType

  0 binderNormalKept : BinderMapped DropsOne None (the (SubstEnv [] []) []) o b b' -> BinderNormal how b ->
                       BinderNormal how b'
  binderNormalKept (MLet mv mty) (NormalLet nv nty) = NormalLet (normalKept mv nv) (normalKept mty nty)
  binderNormalKept (MPi _ mty) (NormalPi nty) = NormalPi (normalKept mty nty)
  binderNormalKept (MPVar _ mty) (NormalPVar nty) = NormalPVar (normalKept mty nty)
  binderNormalKept (MPLet mv mty) (NormalPLet nv nty) = NormalPLet (normalKept mv nv) (normalKept mty nty)
  binderNormalKept (MPVTy mty) (NormalPVTy nty) = NormalPVTy (normalKept mty nty)

-- The function a term applies, as maximal as the application.
0 appliedNormal : EtaNormal how (App fc f a) -> EtaNormal how f
appliedNormal (NormalApp nf _) = nf

------------------------------------------------------------------------------
-- The contraction
------------------------------------------------------------------------------

-- A lambda the contraction leaves, over its type and body contracted,
-- with its reason to stay.
lambdaLeft : (fc : FC) -> (x : Name) -> (lfc : FC) -> (rig : RigCount) -> (info : PiInfo (Term vs)) ->
             {0 ty : Term vs} -> Contracted how ty -> {0 sc : Term (x :: vs)} -> (body : Term (x :: vs)) ->
             (0 _ : EtaContracts sc body) -> (0 _ : EtaNormal how body) -> (0 _ : LambdaLeft how body) ->
             Contracted how (Bind fc x (Lam lfc rig info ty) sc)
lambdaLeft fc x lfc rig info ty' body steps normal left =
  MkContracted (Bind fc x (Lam lfc rig info ty'.etaForm) body) (EtaBind (EtaLam ty'.etaSteps) steps)
               (NormalLambda ty'.etaNormal normal left)

||| A lambda over its type and body, each contracted: where the body
||| applies a term that does not mention the lambda's variable to that
||| variable, that term, read without the variable (`dropOrMention`),
||| unless the contraction keeps that redex (`keptAround`); otherwise the
||| lambda over them, with why it stays. The term a redex contracts to was
||| part of a contracted body, so it holds no redex either (`normalKept`).
lambdaContracted : (how : Contracting) -> (fc : FC) -> (x : Name) -> (lfc : FC) -> (rig : RigCount) ->
                   (info : PiInfo (Term vs)) -> {0 ty : Term vs} -> Contracted how ty ->
                   {0 sc : Term (x :: vs)} -> (body : Term (x :: vs)) -> (0 _ : EtaContracts sc body) ->
                   (0 _ : EtaNormal how body) -> Contracted how (Bind fc x (Lam lfc rig info ty) sc)
lambdaContracted how fc x lfc rig info ty' body steps normal = case lambdaBody body of
  AppliedToVariable f same => case dropOrMention Z DropsHere f of
    Needs mentioned =>
      lambdaLeft fc x lfc rig info ty' body steps normal
                 (replace {p = LambdaLeft how} (sym same) (UsedByFunction mentioned))
    Shrinks g dropped => case keptAround how f of
      ContractedAway =>
        MkContracted g (EtaRedex (replace {p = EtaContracts sc} same steps) dropped)
                     (normalKept dropped (appliedNormal (replace {p = EtaNormal how} same normal)))
      KeptAround {why} =>
        lambdaLeft fc x lfc rig info ty' body steps normal (replace {p = LambdaLeft how} (sym same) (CallKept why))
  NotApplied none => lambdaLeft fc x lfc rig info ty' body steps normal (NoRedex none)

||| A term with its eta-redexes contracted, the innermost first, as a
||| contraction contracts them (`Contracting`): `\y => f y`, where `f`
||| does not mention `y`, is `f`, and so `\x, y => g x y` is `g`; with
||| the contraction that gives it (`Proof.Reading.EtaContracts`) and the
||| evidence that no redex it contracts is left (`EtaNormal`), at quantity
||| 0. A normal form keeps them: Idris passes a method's argument of a
||| type that binds implicits so (`fork`'s thread, `\{e'}, {c} => thread
||| e' c`), and a family as a lambda that applies it (`\x => g x`: an
||| implementation's superclass over `f . g`, a recursion over `Cells p`,
||| the predicate of `(c ** as ** Positive g c as)`). A binder other than
||| a lambda contracts its type and a `let`'s value; what its implicitness
||| holds is no part any reading takes.
export
contractedBy : (how : Contracting) -> (t : Term vs) -> Contracted how t
contractedBy how (Bind fc x (Lam lfc rig info ty) sc) =
  let body = contractedBy how sc in
  lambdaContracted how fc x lfc rig info (contractedBy how ty) body.etaForm body.etaSteps body.etaNormal
contractedBy how (Bind fc x (Let bfc rig v ty) sc) =
  let v' = contractedBy how v
      ty' = contractedBy how ty
      sc' = contractedBy how sc in
  MkContracted (Bind fc x (Let bfc rig v'.etaForm ty'.etaForm) sc'.etaForm)
               (EtaBind (EtaLet v'.etaSteps ty'.etaSteps) sc'.etaSteps)
               (NormalBinder (NormalLet v'.etaNormal ty'.etaNormal) sc'.etaNormal)
contractedBy how (Bind fc x (Pi bfc rig info ty) sc) =
  let ty' = contractedBy how ty
      sc' = contractedBy how sc in
  MkContracted (Bind fc x (Pi bfc rig info ty'.etaForm) sc'.etaForm) (EtaBind (EtaPi ty'.etaSteps) sc'.etaSteps)
               (NormalBinder (NormalPi ty'.etaNormal) sc'.etaNormal)
contractedBy how (Bind fc x (PVar bfc rig info ty) sc) =
  let ty' = contractedBy how ty
      sc' = contractedBy how sc in
  MkContracted (Bind fc x (PVar bfc rig info ty'.etaForm) sc'.etaForm) (EtaBind (EtaPVar ty'.etaSteps) sc'.etaSteps)
               (NormalBinder (NormalPVar ty'.etaNormal) sc'.etaNormal)
contractedBy how (Bind fc x (PLet bfc rig v ty) sc) =
  let v' = contractedBy how v
      ty' = contractedBy how ty
      sc' = contractedBy how sc in
  MkContracted (Bind fc x (PLet bfc rig v'.etaForm ty'.etaForm) sc'.etaForm)
               (EtaBind (EtaPLet v'.etaSteps ty'.etaSteps) sc'.etaSteps)
               (NormalBinder (NormalPLet v'.etaNormal ty'.etaNormal) sc'.etaNormal)
contractedBy how (Bind fc x (PVTy bfc rig ty) sc) =
  let ty' = contractedBy how ty
      sc' = contractedBy how sc in
  MkContracted (Bind fc x (PVTy bfc rig ty'.etaForm) sc'.etaForm) (EtaBind (EtaPVTy ty'.etaSteps) sc'.etaSteps)
               (NormalBinder (NormalPVTy ty'.etaNormal) sc'.etaNormal)
contractedBy how (App fc f a) =
  let f' = contractedBy how f
      a' = contractedBy how a in
  MkContracted (App fc f'.etaForm a'.etaForm) (EtaApp f'.etaSteps a'.etaSteps) (NormalApp f'.etaNormal a'.etaNormal)
contractedBy how (As fc side a p) =
  let a' = contractedBy how a
      p' = contractedBy how p in
  MkContracted (As fc side a'.etaForm p'.etaForm) (EtaAs a'.etaSteps p'.etaSteps) (NormalAs a'.etaNormal p'.etaNormal)
contractedBy how (TDelayed fc r t) =
  let t' = contractedBy how t in
  MkContracted (TDelayed fc r t'.etaForm) (EtaDelayed t'.etaSteps) (NormalDelayed t'.etaNormal)
contractedBy how (TDelay fc r t a) =
  let t' = contractedBy how t
      a' = contractedBy how a in
  MkContracted (TDelay fc r t'.etaForm a'.etaForm) (EtaDelay t'.etaSteps a'.etaSteps)
               (NormalDelay t'.etaNormal a'.etaNormal)
contractedBy how (TForce fc r t) =
  let t' = contractedBy how t in
  MkContracted (TForce fc r t'.etaForm) (EtaForce t'.etaSteps) (NormalForce t'.etaNormal)
contractedBy how (Erased fc (Dotted t)) =
  let t' = contractedBy how t in
  MkContracted (Erased fc (Dotted t'.etaForm)) (EtaDotted t'.etaSteps) (NormalDotted t'.etaNormal)
contractedBy how t@(Local _ _ _ _) = MkContracted t EtaSame NormalLocal
contractedBy how t@(Ref _ _ _) = MkContracted t EtaSame NormalRef
contractedBy how t@(Meta _ _ _ _) = MkContracted t EtaSame NormalMeta
contractedBy how t@(PrimVal _ _) = MkContracted t EtaSame NormalPrim
contractedBy how t@(Erased _ Placeholder) = MkContracted t EtaSame NormalPlaceholder
contractedBy how t@(Erased _ Impossible) = MkContracted t EtaSame NormalImpossible
contractedBy how t@(TType _ _) = MkContracted t EtaSame NormalType

||| A term with every eta-redex in it contracted (`contractedBy`). A type
||| argument is compared so (`canonicalTypeArg`), and a key and an
||| instance's reading take a term so, so that a family is read as itself
||| whatever stands for it: a marker, or the type constructor at its head.
export
contracted : (t : Term vs) -> Contracted EveryRedex t
contracted = contractedBy EveryRedex

||| A reading of the growth check with the evidence, at quantity 0, that
||| its form is maximal: the contraction it was read by left no redex it
||| contracts (`EtaNormal`), so a form read with every redex contracted, an
||| instance's, is what any contraction of it gives
||| (`Proof.Covers.etaNormalFixed`).
public export
record MaximalReading (how : Contracting) (ctx : Frozen) (t : ClosedTerm) where
  constructor MkMaximalReading
  reading : NormalReading OfNormaliseTypes ctx t
  0 maximal : EtaNormal how reading.readForm

