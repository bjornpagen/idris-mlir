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
||| (`Contraction.contractedBy`) gives its result with that evidence and with
||| the evidence that no redex it contracts is left. What contraction gives
||| is never taller than what it was given (`contractionHeight`), so
||| whatever bounds the normal form bounds what the readers read; and it
||| makes no step a node's shape decides (a type by its name, a head that
||| drops its arguments or a lambda, applied, a `let` or an as pattern the
||| evaluation runs: `ShapeRedex`) that the normal form lacks
||| (`contractedShape`), so what a reader reads off a normal form takes
||| none (`readNoShapeStep`).
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
-- Steps a node's shape decides
------------------------------------------------------------------------------

||| A type constructor of no arguments that names a type the evaluator
||| rewrites it to, wherever it is: the universe (`TypeName`) or a
||| primitive type (`ConstantTypeName`).
public export
data NamedType : Name -> Type where
  NamesUniverse : (0 _ : knownRoot n = Just KType) -> NamedType n
  NamesPrimitive : (0 _ : isConstantType n = Just pt) -> NamedType n

||| A head the evaluator rewrites the application of, whatever it is
||| applied to: one that drops what it is applied to (`DropApplied`), or a
||| lambda (`Beta`).
public export
data AppliedHead : Term vs -> Type where
  DropsApplied : DropsArguments f -> AppliedHead f
  LambdaApplied : AppliedHead (Bind bfc x (Lam lfc c p ty) sc)

mutual
  ||| A step of an evaluation that a node's shape decides, with what the
  ||| evaluation runs and keeps, in any context, somewhere in a term: at a
  ||| type constructor that names a type (`NamedType`), at an application
  ||| of a head the evaluator rewrites (`AppliedHead`), at a `let` where the
  ||| evaluation runs everything (`Zeta`), at an as pattern where it removes
  ||| them (`RemoveAs`), or under a node `Idris.Host.Redex` steps under,
  ||| under a delay as the delayed evaluation.
  public export
  data ShapeRedex : Evaluation -> Term vs -> Type where
    ShapeAtName : NamedType n -> ShapeRedex ev (Ref fc (TyCon Z) n)
    ShapeAtApplied : AppliedHead f -> ShapeRedex ev (App fc f a)
    ShapeAtLet : (0 _ : ev.running = RunsAll) -> ShapeRedex ev (Bind fc x (Let lfc c val ty) sc)
    ShapeAtAs : (0 _ : ev.asPatterns = RemovesAs) -> ShapeRedex ev (As fc s n t)
    ShapeInMeta : SomeShapeRedex ev scope -> ShapeRedex ev (Meta fc m i scope)
    ShapeInBinder : BinderShapeRedex ev b -> ShapeRedex ev (Bind fc x b sc)
    ShapeInBody : ShapeRedex ev sc -> ShapeRedex ev (Bind fc x b sc)
    ShapeInFunction : ShapeRedex ev f -> ShapeRedex ev (App fc f a)
    ShapeInArgument : ShapeRedex ev a -> ShapeRedex ev (App fc f a)
    ShapeInAsName : ShapeRedex ev n -> ShapeRedex ev (As fc s n t)
    ShapeInAsPattern : ShapeRedex ev t -> ShapeRedex ev (As fc s n t)
    ShapeInDelayed : ShapeRedex ev t -> ShapeRedex ev (TDelayed fc r t)
    ShapeInDelayType : ShapeRedex (delayed ev) ty -> ShapeRedex ev (TDelay fc d ty a)
    ShapeInDelayValue : ShapeRedex (delayed ev) a -> ShapeRedex ev (TDelay fc d ty a)
    ShapeInForce : ShapeRedex ev t -> ShapeRedex ev (TForce fc r t)
    ShapeInDot : ShapeRedex ev t -> ShapeRedex ev (Erased fc (Dotted t))

  public export
  data SomeShapeRedex : Evaluation -> List (Term vs) -> Type where
    ShapeInFirst : ShapeRedex ev t -> SomeShapeRedex ev (t :: ts)
    ShapeInRest : SomeShapeRedex ev ts -> SomeShapeRedex ev (t :: ts)

  public export
  data BinderShapeRedex : Evaluation -> Binder (Term vs) -> Type where
    ShapeInLamImplicit : PiShapeRedex ev p -> BinderShapeRedex ev (Lam fc c p ty)
    ShapeInLamType : ShapeRedex ev ty -> BinderShapeRedex ev (Lam fc c p ty)
    ShapeInLetValue : ShapeRedex ev val -> BinderShapeRedex ev (Let fc c val ty)
    ShapeInLetType : ShapeRedex ev ty -> BinderShapeRedex ev (Let fc c val ty)
    ShapeInPiImplicit : PiShapeRedex ev p -> BinderShapeRedex ev (Pi fc c p ty)
    ShapeInPiType : ShapeRedex ev ty -> BinderShapeRedex ev (Pi fc c p ty)
    ShapeInPVarImplicit : PiShapeRedex ev p -> BinderShapeRedex ev (PVar fc c p ty)
    ShapeInPVarType : ShapeRedex ev ty -> BinderShapeRedex ev (PVar fc c p ty)
    ShapeInPLetValue : ShapeRedex ev val -> BinderShapeRedex ev (PLet fc c val ty)
    ShapeInPLetType : ShapeRedex ev ty -> BinderShapeRedex ev (PLet fc c val ty)
    ShapeInPVTyType : ShapeRedex ev ty -> BinderShapeRedex ev (PVTy fc c ty)

  public export
  data PiShapeRedex : Evaluation -> PiInfo (Term vs) -> Type where
    ShapeInDefault : ShapeRedex ev t -> PiShapeRedex ev (DefImplicit t)

-- The step a head the evaluator rewrites the application of takes there.
0 appliedHeadStep : {0 ev : Evaluation} -> {0 ctx : Frozen} -> AppliedHead f -> Redex ev ctx (App fc f a)
appliedHeadStep (DropsApplied dropped) = AtRoot (DropApplied dropped)
appliedHeadStep LambdaApplied = AtRoot Beta

-- The step a type constructor that names a type takes.
0 namedStep : {0 ev : Evaluation} -> {0 ctx : Frozen} -> NamedType n -> Redex ev ctx (Ref fc (TyCon Z) n)
namedStep (NamesUniverse root) = AtRoot (TypeName root)
namedStep (NamesPrimitive named) = AtRoot (ConstantTypeName named)

mutual
  ||| A step a node's shape decides is a step of the evaluation in every
  ||| context, where it is.
  export
  0 shapeRedex : {0 ev : Evaluation} -> {0 ctx : Frozen} -> ShapeRedex ev t -> Redex ev ctx t
  shapeRedex (ShapeAtName named) = namedStep named
  shapeRedex (ShapeAtApplied h) = appliedHeadStep h
  shapeRedex (ShapeAtLet runs) = AtRoot (Zeta runs)
  shapeRedex (ShapeAtAs removes) = AtRoot (RemoveAs removes)
  shapeRedex (ShapeInMeta r) = InMeta (someShapeRedex r)
  shapeRedex (ShapeInBinder r) = InBinder (binderShapeRedex r)
  shapeRedex (ShapeInBody r) = InBody (shapeRedex r)
  shapeRedex (ShapeInFunction r) = InFunction (shapeRedex r)
  shapeRedex (ShapeInArgument r) = InArgument (shapeRedex r)
  shapeRedex (ShapeInAsName r) = InAsName (shapeRedex r)
  shapeRedex (ShapeInAsPattern r) = InAsPattern (shapeRedex r)
  shapeRedex (ShapeInDelayed r) = InDelayed (shapeRedex r)
  shapeRedex (ShapeInDelayType r) = InDelayType (shapeRedex r)
  shapeRedex (ShapeInDelayValue r) = InDelayValue (shapeRedex r)
  shapeRedex (ShapeInForce r) = InForce (shapeRedex r)
  shapeRedex (ShapeInDot r) = InDot (shapeRedex r)

  0 someShapeRedex : {0 ev : Evaluation} -> {0 ctx : Frozen} -> SomeShapeRedex ev ts -> SomeRedex ev ctx ts
  someShapeRedex (ShapeInFirst r) = InFirst (shapeRedex r)
  someShapeRedex (ShapeInRest r) = InRest (someShapeRedex r)

  0 binderShapeRedex : {0 ev : Evaluation} -> {0 ctx : Frozen} -> BinderShapeRedex ev b -> BinderRedex ev ctx b
  binderShapeRedex (ShapeInLamImplicit r) = InLamImplicit (piShapeRedex r)
  binderShapeRedex (ShapeInLamType r) = InLamType (shapeRedex r)
  binderShapeRedex (ShapeInLetValue r) = InLetValue (shapeRedex r)
  binderShapeRedex (ShapeInLetType r) = InLetType (shapeRedex r)
  binderShapeRedex (ShapeInPiImplicit r) = InPiImplicit (piShapeRedex r)
  binderShapeRedex (ShapeInPiType r) = InPiType (shapeRedex r)
  binderShapeRedex (ShapeInPVarImplicit r) = InPVarImplicit (piShapeRedex r)
  binderShapeRedex (ShapeInPVarType r) = InPVarType (shapeRedex r)
  binderShapeRedex (ShapeInPLetValue r) = InPLetValue (shapeRedex r)
  binderShapeRedex (ShapeInPLetType r) = InPLetType (shapeRedex r)
  binderShapeRedex (ShapeInPVTyType r) = InPVTyType (shapeRedex r)

  0 piShapeRedex : {0 ev : Evaluation} -> {0 ctx : Frozen} -> PiShapeRedex ev p -> PiRedex ev ctx p
  piShapeRedex (ShapeInDefault r) = InDefault (shapeRedex r)

-- A head a strengthening gives that drops what it is applied to was one:
-- a strengthening rebuilds each such node as it was.
0 strengthenedDrops : DropsArguments g -> Strengthened o f g -> DropsArguments f
strengthenedDrops _ (MMarker first _) = void (noneReplaces first)
strengthenedDrops DropsAtPlaceholder MPlaceholder = DropsAtPlaceholder
strengthenedDrops DropsAtImpossible MImpossible = DropsAtImpossible
strengthenedDrops DropsAtConstant MPrim = DropsAtConstant
strengthenedDrops DropsAtUniverse MType = DropsAtUniverse
strengthenedDrops DropsAtDelay (MDelay _ _) = DropsAtDelay

-- A head a strengthening gives whose application the evaluator rewrites
-- was one.
0 strengthenedHead : AppliedHead g -> Strengthened o f g -> AppliedHead f
strengthenedHead (DropsApplied dropped) m = DropsApplied (strengthenedDrops dropped m)
strengthenedHead LambdaApplied (MMarker first _) = void (noneReplaces first)
strengthenedHead LambdaApplied (MBind (MLam _ _) _) = LambdaApplied

mutual
  ||| A strengthening makes no step a node's shape decides: it rebuilds
  ||| every node it is given from its parts, and puts no value in for a
  ||| name (`Idris.Host.Strengthened`), so each such step of what it gives
  ||| was one of what it was given, at the same node.
  export
  0 strengthenedShape : ShapeRedex ev g -> Strengthened o f g -> ShapeRedex ev f
  strengthenedShape _ (MMarker first _) = void (noneReplaces first)
  strengthenedShape (ShapeAtName named) (MRef _) = ShapeAtName named
  strengthenedShape (ShapeAtApplied h) (MApp mf _) = ShapeAtApplied (strengthenedHead h mf)
  strengthenedShape (ShapeAtLet runs) (MBind (MLet _ _) _) = ShapeAtLet runs
  strengthenedShape (ShapeAtAs removes) (MAs _ _) = ShapeAtAs removes
  strengthenedShape (ShapeInMeta r) (MMeta _ ms) = ShapeInMeta (someStrengthenedShape r ms)
  strengthenedShape (ShapeInBinder r) (MBind mb _) = ShapeInBinder (binderStrengthenedShape r mb)
  strengthenedShape (ShapeInBody r) (MBind _ msc) = ShapeInBody (strengthenedShape r msc)
  strengthenedShape (ShapeInFunction r) (MApp mf _) = ShapeInFunction (strengthenedShape r mf)
  strengthenedShape (ShapeInArgument r) (MApp _ ma) = ShapeInArgument (strengthenedShape r ma)
  strengthenedShape (ShapeInAsName r) (MAs ma _) = ShapeInAsName (strengthenedShape r ma)
  strengthenedShape (ShapeInAsPattern r) (MAs _ mt) = ShapeInAsPattern (strengthenedShape r mt)
  strengthenedShape (ShapeInDelayed r) (MDelayed mt) = ShapeInDelayed (strengthenedShape r mt)
  strengthenedShape (ShapeInDelayType r) (MDelay mty _) = ShapeInDelayType (strengthenedShape r mty)
  strengthenedShape (ShapeInDelayValue r) (MDelay _ ma) = ShapeInDelayValue (strengthenedShape r ma)
  strengthenedShape (ShapeInForce r) (MForce mt) = ShapeInForce (strengthenedShape r mt)
  strengthenedShape (ShapeInDot r) (MDotted mt) = ShapeInDot (strengthenedShape r mt)

  0 someStrengthenedShape : SomeShapeRedex ev us -> AllMapped DropsOne None (the (SubstEnv [] []) []) o ts us ->
                            SomeShapeRedex ev ts
  someStrengthenedShape (ShapeInFirst r) (MEach m _) = ShapeInFirst (strengthenedShape r m)
  someStrengthenedShape (ShapeInRest r) (MEach _ ms) = ShapeInRest (someStrengthenedShape r ms)

  0 binderStrengthenedShape : BinderShapeRedex ev b' -> BinderMapped DropsOne None (the (SubstEnv [] []) []) o b b' ->
                              BinderShapeRedex ev b
  binderStrengthenedShape (ShapeInLamImplicit r) (MLam mp _) = ShapeInLamImplicit (piStrengthenedShape r mp)
  binderStrengthenedShape (ShapeInLamType r) (MLam _ mty) = ShapeInLamType (strengthenedShape r mty)
  binderStrengthenedShape (ShapeInLetValue r) (MLet mv _) = ShapeInLetValue (strengthenedShape r mv)
  binderStrengthenedShape (ShapeInLetType r) (MLet _ mty) = ShapeInLetType (strengthenedShape r mty)
  binderStrengthenedShape (ShapeInPiImplicit r) (MPi mp _) = ShapeInPiImplicit (piStrengthenedShape r mp)
  binderStrengthenedShape (ShapeInPiType r) (MPi _ mty) = ShapeInPiType (strengthenedShape r mty)
  binderStrengthenedShape (ShapeInPVarImplicit r) (MPVar mp _) = ShapeInPVarImplicit (piStrengthenedShape r mp)
  binderStrengthenedShape (ShapeInPVarType r) (MPVar _ mty) = ShapeInPVarType (strengthenedShape r mty)
  binderStrengthenedShape (ShapeInPLetValue r) (MPLet mv _) = ShapeInPLetValue (strengthenedShape r mv)
  binderStrengthenedShape (ShapeInPLetType r) (MPLet _ mty) = ShapeInPLetType (strengthenedShape r mty)
  binderStrengthenedShape (ShapeInPVTyType r) (MPVTy mty) = ShapeInPVTyType (strengthenedShape r mty)

  0 piStrengthenedShape : PiShapeRedex ev p' -> PiMapped DropsOne None (the (SubstEnv [] []) []) o p p' -> PiShapeRedex ev p
  piStrengthenedShape (ShapeInDefault r) (MDefault m) = ShapeInDefault (strengthenedShape r m)

-- What a head contracted to one that drops what it is applied to was: that
-- head, or a delay contracted, which drops it too; or a lambda, an
-- eta-redex, whose application beta reduces.
0 droppedFrom : DropsArguments f' -> EtaContracts f f' -> AppliedHead f
droppedFrom dropped EtaSame = DropsApplied dropped
droppedFrom _ (EtaRedex _ _) = LambdaApplied
droppedFrom DropsAtDelay (EtaDelay _ _) = DropsApplied DropsAtDelay
droppedFrom DropsAtPlaceholder (EtaDotted _) impossible
droppedFrom DropsAtImpossible (EtaDotted _) impossible

-- What a head contracted to a lambda was: a lambda.
0 lambdaFrom : EtaContracts f (Bind bfc x (Lam lfc c p ty) sc) -> AppliedHead f
lambdaFrom EtaSame = LambdaApplied
lambdaFrom (EtaRedex _ _) = LambdaApplied
lambdaFrom (EtaBind (EtaLam _) _) = LambdaApplied

-- What a head contracted to one whose application the evaluator rewrites
-- was: one too.
0 appliedFrom : AppliedHead f' -> EtaContracts f f' -> AppliedHead f
appliedFrom (DropsApplied dropped) cf = droppedFrom dropped cf
appliedFrom LambdaApplied cf = lambdaFrom cf

mutual
  ||| Contraction makes no step a node's shape decides that the term it
  ||| contracts lacks: a node it keeps is rebuilt from its parts
  ||| contracted, a redex it contracts is a part of the lambda's body
  ||| strengthened (`strengthenedShape`), and a head it contracts to one
  ||| whose application the evaluator rewrites was one (`appliedFrom`).
  export
  0 contractedShape : ShapeRedex ev v -> EtaContracts w v -> ShapeRedex ev w
  contractedShape r EtaSame = r
  contractedShape r (EtaRedex body dropped) = ShapeInBody (contractedShape (ShapeInFunction (strengthenedShape r dropped)) body)
  contractedShape (ShapeAtApplied h) (EtaApp cf _) = ShapeAtApplied (appliedFrom h cf)
  contractedShape (ShapeAtLet runs) (EtaBind (EtaLet _ _) _) = ShapeAtLet runs
  contractedShape (ShapeAtAs removes) (EtaAs _ _) = ShapeAtAs removes
  contractedShape (ShapeInBinder r) (EtaBind cb _) = ShapeInBinder (binderContractedShape r cb)
  contractedShape (ShapeInBody r) (EtaBind _ csc) = ShapeInBody (contractedShape r csc)
  contractedShape (ShapeInFunction r) (EtaApp cf _) = ShapeInFunction (contractedShape r cf)
  contractedShape (ShapeInArgument r) (EtaApp _ ca) = ShapeInArgument (contractedShape r ca)
  contractedShape (ShapeInAsName r) (EtaAs ca _) = ShapeInAsName (contractedShape r ca)
  contractedShape (ShapeInAsPattern r) (EtaAs _ ct) = ShapeInAsPattern (contractedShape r ct)
  contractedShape (ShapeInDelayed r) (EtaDelayed ct) = ShapeInDelayed (contractedShape r ct)
  contractedShape (ShapeInDelayType r) (EtaDelay cty _) = ShapeInDelayType (contractedShape r cty)
  contractedShape (ShapeInDelayValue r) (EtaDelay _ ca) = ShapeInDelayValue (contractedShape r ca)
  contractedShape (ShapeInForce r) (EtaForce ct) = ShapeInForce (contractedShape r ct)
  contractedShape (ShapeInDot r) (EtaDotted ct) = ShapeInDot (contractedShape r ct)

  0 binderContractedShape : BinderShapeRedex ev b' -> BinderContracts b b' -> BinderShapeRedex ev b
  binderContractedShape (ShapeInLamImplicit r) (EtaLam _) = ShapeInLamImplicit r
  binderContractedShape (ShapeInLamType r) (EtaLam cty) = ShapeInLamType (contractedShape r cty)
  binderContractedShape (ShapeInLetValue r) (EtaLet cv _) = ShapeInLetValue (contractedShape r cv)
  binderContractedShape (ShapeInLetType r) (EtaLet _ cty) = ShapeInLetType (contractedShape r cty)
  binderContractedShape (ShapeInPiImplicit r) (EtaPi _) = ShapeInPiImplicit r
  binderContractedShape (ShapeInPiType r) (EtaPi cty) = ShapeInPiType (contractedShape r cty)
  binderContractedShape (ShapeInPVarImplicit r) (EtaPVar _) = ShapeInPVarImplicit r
  binderContractedShape (ShapeInPVarType r) (EtaPVar cty) = ShapeInPVarType (contractedShape r cty)
  binderContractedShape (ShapeInPLetValue r) (EtaPLet cv _) = ShapeInPLetValue (contractedShape r cv)
  binderContractedShape (ShapeInPLetType r) (EtaPLet _ cty) = ShapeInPLetType (contractedShape r cty)
  binderContractedShape (ShapeInPVTyType r) (EtaPVTy cty) = ShapeInPVTyType (contractedShape r cty)

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

||| What the readers read off the host's normal form takes no step a node's
||| shape decides anywhere in it: contraction makes none the normal form
||| lacks (`contractedShape`), and the normal form takes no step at all.
export
0 readNoShapeStep : (r : NormalReading form ctx t) -> ShapeRedex (evaluationOf form) r.readForm -> Void
readNoShapeStep r shape = r.reduct.normal (shapeRedex (contractedShape shape r.contraction))
