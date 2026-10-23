-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Templates (`Proof.Template`), read off checked terms: what a definition
||| writes at a static argument, read as the key of the request it makes
||| holds it.
|||
||| A static argument (a type, a family, a dictionary, a form, a shape) is a
||| closed term over markers for the writer's own static parameters. Its
||| template is a tree of heads (constructors, implementations, binders)
||| whose leaves are the markers (`Var`), the closed parts (`Leaf`,
||| `Token`), a field of a dictionary that is no constructor yet (`Field`),
||| a member of a choice the running program makes (`Member`, which a
||| reader of a site puts in where its root says so: `asGiven`), and what a
||| type computes from a marker: a definition's case
||| tree unfolded behind what it matched on (`Choice`), a recursion nothing
||| bounds (`Opaque`), or a family the writer was given, applied, which
||| every instance beta-reduces (`Applied`; `Computing` once the graph
||| finds a value that computes lands there). A family's value is read as
||| its meaning, what beta computes from its arguments (`Formal`), beside
||| the form its key holds, so that what lands at a family bounds what
||| every application of it writes. The growth check's arcs read one height
||| and one weight off it.
|||
||| There is one reader, and one form per kind, the key's
||| (`Instances.classify`): a type, a family or a form normalised and
||| contracted, a dictionary as written or as the implementation it stands
||| for, a shape as its skeleton. The kind is an argument, so no reading
||| guesses what a term is. Every reading comes with what it says of the
||| form it reads (`ReadAs`, at quantity 0): the template has a node for
||| every node the key writes. A site's term is read for every instance
||| (`siteReading`): a call it leaves applied is the call as written beside
||| its unfolding, since an instance may leave it stuck, and the unfolding
||| comes with the trace of the definition's case tree it read
||| (`Reducing`, `Unfolds`), what the reading's soundness against the
||| host's steps is stated over. A lambda chain around such a call, which a
||| key contracts to the call, a site's type keeps and reads as both forms
||| (`SEta`): the call as written, and its unfolding under the lambdas,
||| which an instance that unfolds the call keeps around what it unfolds
||| to. `believe_me` is read beside the value it gives back
||| (`SBelieved`). A request's
||| argument is an instance's term, read by the same reader with every call
||| as written (`readInstance`), and its link writes the form that reading
||| reads, so its key is never larger than its reading (`keyedWithin`).
|||
||| A marker is a bound name of the walk's own, a nested name around a user
||| name no Idris identifier spells. Idris's quotation rebinds a bound
||| machine name to the binder whose number it carries, so a marker is never
||| one: it passes through every normaliser, under every binder, as itself.
|||
||| Every definition a reading looks up is read from the context frozen
||| once the program was loaded, by a pure function of it (`inFrozen`), with
||| the evidence that the context defines the name so: the definition the
||| evaluator's step that unfolds the name unfolds. A reading reads that
||| context once, where it starts, and carries it in its mode
||| (`Mode.inContext`), so that every definition, address, full name and
||| normal form its relation states is over one context, a site's reading
||| and its instances' alike.
|||
||| Unfolding puts a definition on the walk's stack (`Walk.enter`), the
||| measure every reading here recurses on, so the readings end however the
||| definitions refer to one another. A definition met again on its own
||| unfolding is a recursion: one that takes its Nat-like argument's
||| predecessor, under at most one head a level, is bounded by its proof
||| (`structural`), and any other is `Opaque`. A weight of `Stuck` means
||| "met again", or a sum of two heights (an applied family whose argument
||| holds a marker), or a family whose value computes from its arguments
||| (`Beta`), never "did not reduce".
module IdrisMLIR.Frontend.Growth.Template

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.TT
import Idris.Host
import Libraries.Data.List.SizeOf

import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Contraction
import IdrisMLIR.Frontend.Translate.Definitions
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Keys
import IdrisMLIR.Frontend.Translate.Literals
import IdrisMLIR.Frontend.Translate.Readings
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Proof.Bound
import IdrisMLIR.Proof.Derivation
import IdrisMLIR.Proof.Forms
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Inversion
import IdrisMLIR.Proof.Markers
import IdrisMLIR.Proof.Reading
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Sizes
import IdrisMLIR.Proof.Template

import Control.Relation
import Control.WellFounded
import Data.DPair
import Data.Fin
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.List1
import Data.Nat
import Data.SortedMap
import Data.Vect
import Decidable.Equality

%default total

-- The evaluator's relation names its forms and steps as this module names
-- a template's nodes and a static argument's kind, and the growth
-- theorem's rules and the host's inert heads name theirs as this module
-- names a root, a family's beta and a run; here each name is always the
-- frontend's.
%hide Idris.Host.Head
%hide Idris.Host.Applied
%hide Idris.Host.Beta
%hide Idris.Host.Computes
%hide Idris.Host.AType
%hide Idris.Host.delayed
%hide IdrisMLIR.Proof.Bound.Writing.Chosen
%hide IdrisMLIR.Proof.Bound.Writing.Beta
%hide IdrisMLIR.Proof.Bound.RunZero
%hide IdrisMLIR.Proof.Inversion.Inert
-- The checker's thinnings name their identity `Refl`, which its terms'
-- module exports with them; here `Refl` is always equality's, and a pair
-- of a value and its evidence (`Element x Refl`) leaves nothing else to
-- tell the two apart.
%hide Libraries.Data.List.Thin.Refl

------------------------------------------------------------------------------
-- The frozen context
------------------------------------------------------------------------------

||| A definition of the frozen context, read purely: its place, which a walk
||| enters, the definition, and the evidence that the context defines the
||| name so, the one an evaluator's step that unfolds the name unfolds
||| (`Idris.Host.definedOnce`).
record InFrozen (ctx : Frozen) (n : Name) where
  constructor MkInFrozen
  placement : Placement
  def : GlobalDef
  0 defines : Defines ctx n def

0 justAlike : Just x = Just y -> x = y
justAlike Refl = Refl

0 noneIsJust : Nothing = Just x -> Void
noneIsJust Refl impossible

-- A name the context defines resolves to an entry at a non-negative index
-- (`Idris.Host.definedPlaced`).
0 entryNonNegative : Resolves ctx n i -> Defines ctx n d -> (i < 0) = False
entryNonNegative r defines = case definedPlaced defines of
  (j ** (found, nonNegative)) => replace {p = \k => (k < 0) = False} (justAlike (trans (sym found) (resolvesAs r))) nonNegative

-- An entry at a non-negative index has a place (`Walk.placedWhereResolved`),
-- read off the name the entry resolves itself as.
0 unplacedEntry : {0 ctx : Frozen} -> placementIn (gamma (defsOf ctx)) (Resolved i) = Nothing -> (i < 0) = False -> Void
unplacedEntry none nonNegative = case placedWhereResolved {ctx = gamma (defsOf ctx)} {n = Resolved i} Refl nonNegative of
  (p ** placed) => noneIsJust (trans (sym none) placed)

-- The place of the entry a name the context defines resolves to, read off
-- the entry's resolved name, which names it with no lookup: every entry of
-- a defined name has one, so no definition the context gives is left
-- without a place.
placeOf : (ctx : Frozen) -> (i : Int) -> (0 _ : Resolves ctx n i) -> (0 _ : Defines ctx n d) -> Placement
placeOf ctx i r defines with (placementIn (gamma (defsOf ctx)) (Resolved i)) proof placed
  _ | Just p = p
  _ | Nothing = void (unplacedEntry placed (entryNonNegative r defines))

||| The definition the frozen context gives a name, at its place: nothing
||| for a name it defines as nothing, the one case the context has.
inFrozen : (ctx : Frozen) -> (n : Name) -> Maybe (InFrozen ctx n)
inFrozen ctx n = case definitionIn ctx n of
  NotDefined _ => Nothing
  DefinedAs i r d defines => Just (MkInFrozen (placeOf ctx i r defines) d defines)

||| The definition at an address of the frozen context: nothing at bytes no
||| entry has.
atAddress : (ctx : Frozen) -> Address -> Maybe GlobalDef
atAddress ctx a = nameAt (gamma (defsOf ctx)) a >>= (\n => (.def) <$> inFrozen ctx n)

||| The definition the boundary read at an address (`Errors.defined`), by
||| the name the frozen context gives the entry there: nothing at bytes no
||| entry has, or for an entry the context defines as nothing.
export
definitionRead : Address -> Front (Maybe State.Defined)
definitionRead a = do
  ctx <- frozenContext
  case nameAt (gamma (defsOf ctx)) a of
    Just n => defined n
    Nothing => pure Nothing

------------------------------------------------------------------------------
-- The markers
------------------------------------------------------------------------------

-- The walk's markers are made below the state that caches readings
-- (`Readings.markerAt`); a reader reads them back here.

||| The parameter and path of `markerAt`'s name, and of no other.
export
markerOf : Name -> Maybe (Nat, List Nat)
markerOf n = case probeOf n of
  Just (ProbePart i path) => Just (i, path)
  _ => Nothing

||| What a site binds a match on a field of the writer's dictionary
||| parameter i to, by its path: the dictionary's field first, then a field
||| of that field. A dictionary with no path is the marker itself, one name
||| per value. A dictionary keeps its marker through every match, never a
||| part of anything, so it has no depth: its fields read below `Var i 0`.
export
fieldAt : (i : Nat) -> (path : List Nat) -> ClosedTerm
fieldAt i [] = markerAt i []
fieldAt i (k :: ks) = probeTerm (ProbeFieldPath i (k ::: ks))

------------------------------------------------------------------------------
-- Nat-like constructors, as a reading meets them
------------------------------------------------------------------------------

||| The role a constructor has in a Nat-like type, if any.
roleOf : Frozen -> Name -> Maybe NatRole
roleOf ctx n = natRole . (.def) =<< inFrozen ctx n

||| A closed run, as `Keys.successorRun` reads one: n >= 1 applications of
||| one successor, the same definition at each step, ending in a zero. Its
||| count n, with the run; the run's template is `Leaf (S n)`, the model's
||| height of `S^n Z`, so that a template's explicit successors over a
||| marker are never shorter than the run they close to. A run that ends in
||| anything else is read node by node.
export
closedRun : {auto c : Ref Ctxt Defs} -> (t : TT vs) -> Front (Maybe (SuccessorRun t))
closedRun t@(App _ (Ref _ (DataCon _ _) _) _) = do
  w <- writerOf (heads t)
  pure (successorRun w t)
  where
    -- The constructors down a run's spine: the only names its reading asks
    -- the roles of.
    heads : TT vs -> List (TT vs)
    heads (App _ f@(Ref _ (DataCon _ _) _) a) = f :: heads a
    heads z@(Ref _ (DataCon _ _) _) = [z]
    heads _ = []
closedRun _ = pure Nothing

------------------------------------------------------------------------------
-- An alternative at another entry
------------------------------------------------------------------------------

||| How an alternative at another entry meets a constructor: missed, or,
||| for a data constructor of the alternative's tag, neither taken nor
||| missed, where the host's walk is stuck.
data AnotherEntry : ConstructorHead -> Int -> Type where
  Passed : (0 _ : Missed h tag) -> AnotherEntry h tag
  Blocked : (0 _ : t = tag) -> AnotherEntry (DataHead t) tag

anotherEntry : (h : ConstructorHead) -> (tag : Int) -> AnotherEntry h tag
anotherEntry FamilyHead tag = Passed EntryDiffers
anotherEntry (DataHead t) tag = case decEq t tag of
  Yes same => Blocked same
  No other => Passed (TagDiffers other)

------------------------------------------------------------------------------
-- Structural recursions
------------------------------------------------------------------------------

||| The alternatives of a match one level deep on a Nat-like argument, the
||| part of the writer's parameter j at `path`, each leaf with the
||| parameters substituted and each argument the match binds the part at
||| its own field below (`PartsOf`); nothing for any other match.
natArms : Frozen -> (j : Nat) -> (path : List Nat) -> Values ClosedTerm vs -> List (CaseAlt vs) -> Maybe (List Arm)
natArms ctx j path env [] = Just []
natArms ctx j path env (ConCase con _ cargs (STerm _ rhs) :: alts) = do
  let body = close (extend (boundFields (PartsOf j path) 0 cargs) env) rhs
  role <- roleOf ctx con
  let arm = case role of
              Succ => Step body
              Zero => Base body
  (arm ::) <$> natArms ctx j path env alts
natArms ctx j path env (DefaultCase (STerm _ rhs) :: alts) = (Base (close env rhs) ::) <$> natArms ctx j path env alts
natArms ctx j path env (_ :: _) = Nothing

------------------------------------------------------------------------------
-- What a reader reads as one node, and a form as its key holds it
------------------------------------------------------------------------------

||| A binder a reading reads as one node over its parts and its scope:
||| every binder but a lambda, which is a family's value (`SLambda`) or a
||| chain a site keeps around a call (`SEta`), so that one term has one
||| reading at every node.
public export
data NodeBinder : Binder t -> Type where
  NodeLet : NodeBinder (Let fc rig v ty)
  NodePi : NodeBinder (Pi fc rig info ty)
  NodePVar : NodeBinder (PVar fc rig info ty)
  NodePLet : NodeBinder (PLet fc rig v ty)
  NodePVTy : NodeBinder (PVTy fc rig ty)

0 lambdaNoNode : NodeBinder (Lam fc rig info ty) -> Void
lambdaNoNode NodeLet impossible
lambdaNoNode NodePi impossible
lambdaNoNode NodePVar impossible
lambdaNoNode NodePLet impossible
lambdaNoNode NodePVTy impossible

mutual
  ||| A template a shape's form rewrites as its key holds it: each `:<` of its
  ||| spine with its extent the leaf an erased extent is, each leaf of a
  ||| choice so, anything else as read.
  public export
  data KeyForm : Template -> Template -> Type where
    AsRead : KeyForm t t
    ExtentErased : KeyForm rest rest' -> KeyForm (Head (Just a) [e, rest, x]) (Head (Just a) [e, rest', Leaf 1])
    LeavesFormed : AllKeyForm ls ls' -> KeyForm (Choice s ls) (Choice s ls')

  public export
  data AllKeyForm : List Template -> List Template -> Type where
    NoneFormed : AllKeyForm [] []
    EachFormed : KeyForm t t' -> AllKeyForm ts ts' -> AllKeyForm (t :: ts) (t' :: ts')

------------------------------------------------------------------------------
-- The readings
------------------------------------------------------------------------------

||| An argument met on a spine: the term, as a closed term for what
||| substitutes it, and its reading; each computed when it is needed.
record Arg {0 vs : Scope} (m : Mode) (stand : Values Substitute vs) where
  constructor MkArg
  term : TT vs
  value : Lazy ClosedTerm
  0 closedAs : Force value = closeBy Readings.substituted stand term
  reading : Lazy (Front (Subset Template (ReadAs m stand term)))

||| The terms of some arguments.
termsOf : {0 vs : Scope} -> {0 m : Mode} -> {0 stand : Values Substitute vs} -> List (Arg m stand) -> List (TT vs)
termsOf [] = []
termsOf (a :: as) = a.term :: termsOf as

-- The closed terms a call's unfolding walks are its arguments as written,
-- each variable by its substitute.
0 closedTerms : {0 vs : Scope} -> {0 m : Mode} -> {0 stand : Values Substitute vs} ->
                (args : List (Arg m stand)) -> map (\x => Force x.value) args = map (closeBy Readings.substituted stand) (termsOf args)
closedTerms [] = Refl
closedTerms (a :: as) = cong2 (::) a.closedAs (closedTerms as)

||| The arguments' readings, in order.
readings : {0 vs : Scope} -> {0 m : Mode} -> {0 stand : Values Substitute vs} ->
           (args : List (Arg m stand)) -> Front (Subset (List Template) (AllReadAs m stand (termsOf args)))
readings [] = pure (Element [] [])
readings (a :: as) = do
  r <- Force a.reading
  rs <- readings as
  pure (Element (r.fst :: rs.fst) (r.snd :: rs.snd))

||| Whether a term mentions one of the walk's markers, each of which an
||| instance puts a value in for: the writer's parameter, a part of one a
||| site matched, a field of its dictionary, an argument of a family's
||| value. Any other probe stands for a runtime value, which no instance
||| puts in.
markersIn : TT vs -> Mention
markersIn = mentioning marker
  where
    marker : {0 ws : Scope} -> TT ws -> Mention
    marker (Ref _ Bound n) = case probeOf n of
      Just (ProbePart _ _) => Mentioned
      Just (ProbePattern _) => Mentioned
      Just (ProbeFieldPath _ _) => Mentioned
      Just (ProbeFormal _ _) => Mentioned
      _ => Unmentioned
    marker _ = Unmentioned

||| Whether one of a call's arguments mentions one of the walk's markers.
mentionedAmong : List ClosedTerm -> Mention
mentionedAmong [] = Unmentioned
mentionedAmong (t :: ts) = case markersIn t of
  Mentioned => Mentioned
  Unmentioned => mentionedAmong ts

||| A projection applied to its parameters whose record is no data
||| constructor application: its field, the record, and the arguments past
||| the projection's own. A normal form has projected every constructor
||| record, and a dictionary's key writes a projection of one as the
||| application it is.
projectedRecord : {auto c : Ref Ctxt Defs} -> Name -> List (Arg m stand) ->
                  Front (Maybe (Nat, Arg m stand, List (Arg m stand)))
projectedRecord n args = do
  Just pr <- projection n
    | Nothing => pure Nothing
  pure $ do
    (env, extras) <- bindParams pr.params args
    let projected = valueAt env pr.matched pr.isParam
    case getFnArgs (Force projected.value) of
      (Ref _ (DataCon _ _) _, _) => Nothing
      _ => Just (pr.field, projected, extras)

||| How many arguments a value of a type takes: its Pi binders, read off
||| its normal form when the type as written is no Pi down to a universe or
||| a type constructor applied, the forms no normaliser adds a binder to.
arityOf : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> TT vs -> Front Nat
arityOf ty = case written ty of
    Just k => pure k
    Nothing => pure (pis !(normaliseClosed (closedOver ty)))
  where
    pis : TT ws -> Nat
    pis (Bind _ _ (Pi {}) sc) = S (pis sc)
    pis _ = 0

    written : TT ws -> Maybe Nat
    written (Bind _ _ (Pi {}) sc) = S <$> written sc
    written (TType {}) = Just 0
    written t = case getFn t of
      Ref _ (TyCon _) _ => Just 0
      PrimVal {} => Just 0
      _ => Nothing

||| How many arguments each parameter of a type takes, in order.
binderArities : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> TT vs -> Front (List Nat)
binderArities (Bind _ _ (Pi _ _ _ ty) sc) = (::) <$> arityOf ty <*> binderArities sc
binderArities _ = pure []

||| Arguments j, j + 1, ... of a family's value, as many as asked, each
||| taking as many arguments as its type does (none past the list).
formalsFrom : Nat -> List Nat -> Nat -> List Substitute
formalsFrom j ks Z = []
formalsFrom j [] (S n) = FormalArgument j 0 :: formalsFrom (S j) [] n
formalsFrom j (k :: ks) (S n) = FormalArgument j k :: formalsFrom (S j) ks n

||| A bound name that is neither a hole marker nor an argument of a
||| family's value: in a site's term, one of the writer's markers, or a
||| runtime part; in an instance's, which holds no marker, a runtime part.
siteBound : {0 vs : Scope} -> {0 stand : Values Substitute vs} -> {0 as : List (TT vs)} ->
            (m : Mode) -> (fc : FC) -> (n : Name) -> (0 _ : Readings.markerOf n = Nothing) -> (0 _ : NotFormal n) ->
            (ts : List Template) -> (0 _ : AllReadAs m stand as ts) ->
            Subset Template (SpineAs m stand (Ref fc Bound n) as)
siteBound (MkMode (OfSite stands) kp cl ctx) fc n none plain ts rs with (walkMarker stands n) proof found
  _ | Just t = Element (markedOf t ts) (SMarker found rs)
  _ | Nothing = Element (partOf kp (Leaf 1) ts) (SPart none plain rs)
siteBound (MkMode OfInstance kp cl ctx) fc n none plain ts rs = Element (partOf kp (Leaf 1) ts) (SPart none plain rs)

||| A bound name that is no hole marker, read: an argument of a family's
||| value its own; any other as `siteBound` reads it.
boundName : {0 vs : Scope} -> {0 stand : Values Substitute vs} -> {0 as : List (TT vs)} ->
            (m : Mode) -> (fc : FC) -> (n : Name) -> (0 _ : Readings.markerOf n = Nothing) ->
            (ts : List Template) -> (0 _ : AllReadAs m stand as ts) ->
            Subset Template (SpineAs m stand (Ref fc Bound n) as)
boundName m fc n none ts rs = case formalView n of
  IsFormal j k formal => Element (partOf m.keeping (Formal j k) ts) (SFormal none formal rs)
  NotFormalName plain => siteBound m fc n none plain ts rs

||| A site's call beside its unfolding: as written, which every instance
||| that leaves it stuck writes, and what the unfolding gives the others;
||| read for where a type matches, the unfolding alone.
besides : {0 vs : Scope} -> {0 stand : Values Substitute vs} -> {0 as : List (TT vs)} -> {0 fc : FC} -> {0 n : Name} ->
          {0 ctx : Frozen} -> (stands : List StandIn) -> (kp : Keeping) -> (cl : Calling) -> (a : Address) ->
          (0 _ : AddressedAs (MkMode (OfSite stands) kp cl ctx) n (Just a)) -> (ts : List Template) ->
          (0 _ : AllReadAs (MkMode (OfSite stands) kp cl ctx) stand as ts) -> (unfolded : Template) ->
          (0 _ : Reducing (MkMode (OfSite stands) kp cl ctx) a n (map (closeBy Readings.substituted stand) as)
                          (nodeOf kp (Head (Just a) ts)) unfolded) ->
          Subset Template (SpineAs (MkMode (OfSite stands) kp cl ctx) stand (Ref fc Func n) as)
besides stands kp WalksAlone a at ts rs t r = Element t (SWalked at rs r)
besides stands kp cl a at ts rs t r = Element (Choice (Leaf 1) [nodeOf kp (Head (Just a) ts), t]) (SBeside at rs r)

||| What a site's reading makes of a definition left applied, at its
||| arguments as closed terms: the call as written, which every instance
||| writes; a recursion met again on its own unfolding; or the call as
||| written beside what an instance that reduces it makes of it.
data CallRead : Mode -> Address -> Name -> List ClosedTerm -> Template -> Type where
  AsWritten : CallRead m a n terms written
  Recurs : CallRead m a n terms written
  Unfolded : (t : Template) -> (0 _ : Reducing m a n terms written t) -> CallRead m a n terms written

||| A kept lambda chain read (`EtaChain`): its call's address, the
||| templates of the call's own arguments, and what an instance that
||| unfolds the call makes of it under the lambdas.
record ChainRead {0 vs : Scope} (m : Mode) (stand : Values Substitute vs) (t : TT vs) where
  constructor MkChainRead
  address : Address
  own : List Template
  unfolded : Maybe Template
  0 chain : EtaChain m stand t address own unfolded

||| The call at the bottom of a kept lambda chain read (`CallUnfolds`), at
||| the arguments its spine has met.
record UnfoldsRead {0 vs : Scope} (m : Mode) (stand : Values Substitute vs) (t : TT vs) (as : List (TT vs)) where
  constructor MkUnfoldsRead
  address : Address
  own : List Template
  unfolded : Maybe Template
  0 call : CallUnfolds m stand t as address own unfolded

||| A list cut before its last elements, the parts making it up.
record Parted {0 a : Type} (xs : List a) where
  constructor MkParted
  front : List a
  back : List a
  0 joined : front ++ back = xs

||| A list cut before its last `k` elements: the arguments a call has of
||| its own and the variables of the lambdas a chain keeps around it.
partedBefore : (k : Nat) -> (xs : List a) -> Parted xs
partedBefore k xs = cutAt (minus (length xs) k) xs
  where
    cutAt : Nat -> (ys : List a) -> Parted ys
    cutAt Z ys = MkParted [] ys Refl
    cutAt (S j) [] = MkParted [] [] Refl
    cutAt (S j) (y :: ys) = let MkParted f b p = cutAt j ys in MkParted (y :: f) b (cong (y ::) p)

0 termsJoined : {0 vs : Scope} -> {0 m : Mode} -> {0 stand : Values Substitute vs} ->
                (xs, ys : List (Arg m stand)) -> termsOf (xs ++ ys) = termsOf xs ++ termsOf ys
termsJoined [] ys = Refl
termsJoined (x :: xs) ys = cong (x.term ::) (termsJoined xs ys)

-- The terms of a cut list are the terms of its parts.
0 partedTerms : {0 vs : Scope} -> {0 m : Mode} -> {0 stand : Values Substitute vs} -> {0 args : List (Arg m stand)} ->
                (p : Parted args) -> termsOf args = termsOf p.front ++ termsOf p.back
partedTerms (MkParted f b joined) = rewrite sym joined in termsJoined f b

||| `believe_me` applied to its two types and a value in a site's type, its
||| arguments read, where they mention the walk's markers: the value beside
||| the call as written (`SBelieved`), since the evaluator gives the value
||| back unchanged at an instance whose value is one it can give another
||| type (`Idris.Host.Coercible`). Any other call, and a `believe_me` given
||| more or fewer arguments, is no reading of this one's.
believed : {0 vs : Scope} -> (m : Mode) -> {0 stand : Values Substitute vs} -> (fc : FC) -> (n : Name) -> (a : Address) ->
           (0 _ : AddressedAs m n (Just a)) -> (def : GlobalDef) -> (0 _ : Defines m.inContext n def) ->
           (args : List (Arg m stand)) -> Subset (List Template) (AllReadAs m stand (termsOf args)) ->
           Maybe (Subset Template (SpineAs m stand (Ref fc Func n) (termsOf args)))
believed (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) fc n a at def defines [x1, x2, x3] (Element [ra, rb, rv] read) =
  case (Element (definition def) Refl, mentionedAmong [Force x1.value, Force x2.value, Force x3.value]) of
    (Element (Builtin BelieveMe) belief, Mentioned) =>
      Just (Element (Choice (Leaf 1) [Head (Just a) [ra, rb, rv], rv]) (SBelieved at defines belief read))
    _ => Nothing
believed _ _ _ _ _ _ _ _ _ = Nothing

mutual
  ||| A term read as its key writes it, each variable by its substitute (a
  ||| placeholder, or a lambda's argument), with what the reading says of it.
  ||| A closed run of a Nat-like type is its run's height (`closedRun`).
  read : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
         (stand : Values Substitute vs) -> (t : TT vs) -> Front (Subset Template (ReadAs m stand t))
  read m w acc stand t = do
    Just run <- closedRun t
      | Nothing => (\r => Element r.fst (ASpine r.snd)) <$> spine m w acc stand t []
    pure (Element (Leaf (S run.count)) (ARun run.run))

  ||| Terms read, each in turn.
  readAll : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            (stand : Values Substitute vs) -> (ts : List (TT vs)) -> Front (Subset (List Template) (AllReadAs m stand ts))
  readAll m w acc stand [] = pure (Element [] [])
  readAll m w acc stand (t :: ts) = do
    r <- read m w acc stand t
    rs <- readAll m w acc stand ts
    pure (Element (r.fst :: rs.fst) (r.snd :: rs.snd))

  ||| A term applied to arguments, read by its head. A dot is a node of the
  ||| key, and so of the template. A runtime part is one key node, in every
  ||| reading. An `Erased` part is an unbound binder's placeholder, or a
  ||| part cut or holed at runtime; a binder's variable is its substitute; a
  ||| metavariable left after `solved` and every normaliser has no solution,
  ||| and its scope is written by the key. A node that is no head of its own
  ||| (a binder, a delay, a dot, an as pattern) applied holds its own parts
  ||| and its arguments in one node, as the key writes it.
  spine : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          (stand : Values Substitute vs) -> (t : TT vs) -> (args : List (Arg m stand)) ->
          Front (Subset Template (SpineAs m stand t (termsOf args)))
  spine m w acc stand (App _ f a) args =
    (\r => Element r.fst (SApp r.snd))
      <$> spine m w acc stand f (MkArg a (closeBy substituted stand a) Refl (read m w acc stand a) :: args)
  spine m w acc stand (Erased _ (Dotted u)) args = do
    r <- read m w acc stand u
    rs <- readings args
    pure (Element (nodeOf m.keeping (Head Nothing (r.fst :: rs.fst))) (SDot r.snd rs.snd))
  spine m w acc stand (Erased _ Placeholder) args = do
    rs <- readings args
    pure (Element (partOf m.keeping (Leaf 1) rs.fst) (SPlaceholder rs.snd))
  spine m w acc stand (Erased _ Impossible) args = do
    rs <- readings args
    pure (Element (partOf m.keeping (Leaf 1) rs.fst) (SImpossible rs.snd))
  spine m w acc stand (Local _ _ idx p) args = do
    rs <- readings args
    pure (Element (partOf m.keeping (substituteTemplate (valueAt stand idx p)) rs.fst) (SLocal rs.snd))
  spine m w acc stand (Meta _ _ _ margs) args = do
    ms <- readAll m w acc stand margs
    rs <- readings args
    pure (Element (nodeOf m.keeping (Head Nothing (ms.fst ++ rs.fst))) (SMeta ms.snd rs.snd))
  spine m w acc stand (Ref fc nt n) args = reference m w acc stand fc nt n args
  spine m w acc stand (TType _ _) args = do
    rs <- readings args
    pure (Element (partOf m.keeping (Leaf 1) rs.fst) (SUniverse rs.snd))
  spine m w acc stand (PrimVal _ k) args = do
    rs <- readings args
    pure (Element (nodeOf m.keeping (appliedConstant k rs.fst)) (SConstant rs.snd))
  spine m w acc stand (Bind fc x (Lam lfc rig info ty) sc) args = lambdaSpine m w acc stand fc x lfc rig info ty sc args
  spine m w acc stand (Bind fc x b@(Let _ _ _ _) sc) args = nodeBinder m w acc stand fc x b NodeLet sc args
  spine m w acc stand (Bind fc x b@(Pi _ _ _ _) sc) args = nodeBinder m w acc stand fc x b NodePi sc args
  spine m w acc stand (Bind fc x b@(PVar _ _ _ _) sc) args = nodeBinder m w acc stand fc x b NodePVar sc args
  spine m w acc stand (Bind fc x b@(PLet _ _ _ _) sc) args = nodeBinder m w acc stand fc x b NodePLet sc args
  spine m w acc stand (Bind fc x b@(PVTy _ _ _) sc) args = nodeBinder m w acc stand fc x b NodePVTy sc args
  spine m w acc stand (TDelayed _ _ u) args = do
    t <- read m w acc stand u
    rs <- readings args
    pure (Element (nodeOf m.keeping (Head Nothing (t.fst :: rs.fst))) (SDelayed t.snd rs.snd))
  spine m w acc stand (TDelay _ _ ty a) args = do
    t <- read m w acc stand ty
    v <- read m w acc stand a
    rs <- readings args
    pure (Element (nodeOf m.keeping (Head Nothing (t.fst :: v.fst :: rs.fst))) (SDelay t.snd v.snd rs.snd))
  spine m w acc stand (TForce _ _ u) args = do
    t <- read m w acc stand u
    rs <- readings args
    pure (Element (nodeOf m.keeping (Head Nothing (t.fst :: rs.fst))) (SForce t.snd rs.snd))
  spine m w acc stand (As _ _ a p) args = do
    t <- read m w acc stand a
    v <- read m w acc stand p
    rs <- readings args
    pure (Element (nodeOf m.keeping (Head Nothing (t.fst :: v.fst :: rs.fst))) (SAs t.snd v.snd rs.snd))

  ||| A lambda applied to arguments. A lambda chain a site's type keeps
  ||| around a call (`Contraction.CallsKept`), alone, is read as both its forms
  ||| (`SEta`): the call as written, which an instance that leaves the call
  ||| stuck contracts to, and the call's unfolding under the lambdas, which
  ||| an instance that unfolds it keeps. Any other lambda is a family's
  ||| value (or a function's), whose variable is what beta substitutes: an
  ||| argument (`Formal`), so that a definition stuck on it is read for what
  ||| it computes from each argument as well as as written. Every other
  ||| reading takes its term contracted, so no lambda there only applies
  ||| something to its own variables.
  lambdaSpine : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                (stand : Values Substitute vs) -> (fc : FC) -> (x : Name) -> (lfc : FC) -> (rig : RigCount) ->
                (info : PiInfo (TT vs)) -> (ty : TT vs) -> (sc : TT (x :: vs)) -> (args : List (Arg m stand)) ->
                Front (Subset Template (SpineAs m stand (Bind fc x (Lam lfc rig info ty) sc) (termsOf args)))
  -- The site's mode is written out where it is used: the alternatives
  -- below are case blocks, which see a name bound by an as pattern as a
  -- variable apart from the mode it matched.
  lambdaSpine (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) w acc stand fc x lfc rig info ty sc [] =
    case contracted (Bind fc x (Lam lfc rig info ty) sc) of
      MkContracted g steps _ => case keptAround (contractingFor (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx)) g of
        ContractedAway => plainLambda (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) w acc stand fc x lfc rig info ty sc []
        KeptAround => do
          Just r <- chainLambda (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) w acc stand 0 fc x lfc rig info ty sc
            | Nothing => plainLambda (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) w acc stand fc x lfc rig info ty sc []
          pure (Element (keptChain r.address r.own r.unfolded) (SEta steps r.chain))
  lambdaSpine m w acc stand fc x lfc rig info ty sc args = plainLambda m w acc stand fc x lfc rig info ty sc args

  ||| A lambda applied to arguments, read as a lambda: a head above its
  ||| implicitness, its type, its scope and the arguments.
  plainLambda : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                (stand : Values Substitute vs) -> (fc : FC) -> (x : Name) -> (lfc : FC) -> (rig : RigCount) ->
                (info : PiInfo (TT vs)) -> (ty : TT vs) -> (sc : TT (x :: vs)) -> (args : List (Arg m stand)) ->
                Front (Subset Template (SpineAs m stand (Bind fc x (Lam lfc rig info ty) sc) (termsOf args)))
  plainLambda {vs} m w acc stand fc x lfc rig info ty sc args = do
    ps <- passing m w acc stand info
    t <- read m w acc stand ty
    k <- arityOf (closeBy substituted stand ty)
    s <- read m w acc (FormalArgument (length vs) k :: stand) sc
    rs <- readings args
    pure (Element (nodeOf m.keeping (Head Nothing ((ps.fst ++ [t.fst, s.fst]) ++ rs.fst)))
                  (SLambda ps.snd t.snd s.snd rs.snd))

  ||| A lambda of a chain a site keeps around a call, `peeled` lambdas
  ||| below the chain's outermost: its implicitness and its type, then
  ||| below it (`chainBelow`), its variable an argument of the value.
  chainLambda : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                (stand : Values Substitute vs) -> (peeled : Nat) -> (fc : FC) -> (x : Name) -> (lfc : FC) -> (rig : RigCount) ->
                (info : PiInfo (TT vs)) -> (ty : TT vs) -> (sc : TT (x :: vs)) ->
                Front (Maybe (ChainRead m stand (Bind fc x (Lam lfc rig info ty) sc)))
  chainLambda {vs} m w acc stand peeled fc x lfc rig info ty sc = do
    ps <- passing m w acc stand info
    t <- read m w acc stand ty
    k <- arityOf (closeBy substituted stand ty)
    Just r <- chainBelow m w acc (FormalArgument (length vs) k :: stand) (S peeled) sc
      | Nothing => pure Nothing
    pure (Just (MkChainRead r.address r.own (map (\s => nodeOf m.keeping (Head Nothing (ps.fst ++ [t.fst, s]))) r.unfolded)
                            (ChainLambda ps.snd t.snd r.chain)))

  ||| Below a lambda of a kept chain: a further lambda of it, or the call at
  ||| its bottom, the last `peeled` of whose arguments are the chain's
  ||| variables; nothing where the bottom is no call of a definition the
  ||| context holds.
  chainBelow : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
               (stand : Values Substitute vs) -> (peeled : Nat) -> (t : TT vs) -> Front (Maybe (ChainRead m stand t))
  chainBelow m w acc stand peeled (Bind fc x (Lam lfc rig info ty) sc) = chainLambda m w acc stand peeled fc x lfc rig info ty sc
  chainBelow m w acc stand peeled t =
    map (\r => MkChainRead r.address r.own r.unfolded (ChainCall r.call)) <$> callUnfolds m w acc stand peeled t []

  ||| The call at the bottom of a kept chain, read down its spine with the
  ||| arguments met so far (`CallUnfolds`).
  callUnfolds : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                (stand : Values Substitute vs) -> (peeled : Nat) -> (t : TT vs) -> (args : List (Arg m stand)) ->
                Front (Maybe (UnfoldsRead m stand t (termsOf args)))
  callUnfolds m w acc stand peeled (App _ f a) args =
    map (\r => MkUnfoldsRead r.address r.own r.unfolded (UnfoldsApplied r.call))
      <$> callUnfolds m w acc stand peeled f (MkArg a (closeBy substituted stand a) Refl (read m w acc stand a) :: args)
  callUnfolds m w acc stand peeled (Ref fc Func n) args with (definitionAddress (gamma (defsOf m.inContext)) n) proof found
    _ | Just d = Just <$> calledWith m w acc stand peeled fc n d found args
    _ | Nothing = pure Nothing
  callUnfolds m w acc stand peeled t args = pure Nothing

  ||| A call at the bottom of a kept chain: its own arguments and the
  ||| chain's variables, read, and what an instance that unfolds it makes
  ||| of it, as a site's call beside its unfolding is read (`callRead`).
  calledWith : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
               (stand : Values Substitute vs) -> (peeled : Nat) -> (fc : FC) -> (n : Name) -> (d : Address) ->
               (0 _ : AddressedAs m n (Just d)) -> (args : List (Arg m stand)) ->
               Front (UnfoldsRead m stand (Ref fc Func n) (termsOf args))
  calledWith m w acc stand peeled fc n d at args = do
    let parts = partedBefore peeled args
    rs <- readings parts.front
    fs <- readings parts.back
    let stays = MkUnfoldsRead d rs.fst Nothing
                  (replace {p = \zs => CallUnfolds m stand (Ref fc Func n) zs d rs.fst Nothing} (sym (partedTerms parts))
                           (CallStays {vars = termsOf parts.back} at rs.snd))
    let Just (MkInFrozen placement def defines) = inFrozen m.inContext n
      | Nothing => pure stays
    let written := nodeOf m.keeping (Head (Just d) (rs.fst ++ fs.fst))
    outcome <- callRead m w acc d n placement def defines (map (\x => Force x.value) args) written
    pure (case outcome of
            AsWritten => stays
            Recurs =>
              MkUnfoldsRead d rs.fst (Just (Opaque d (rs.fst ++ fs.fst)))
                (replace {p = \zs => CallUnfolds m stand (Ref fc Func n) zs d rs.fst (Just (Opaque d (rs.fst ++ fs.fst)))}
                         (sym (partedTerms parts)) (CallAgain at rs.snd fs.snd))
            Unfolded t r =>
              MkUnfoldsRead d rs.fst (Just t)
                (replace {p = \zs => CallUnfolds m stand (Ref fc Func n) zs d rs.fst (Just t)} (sym (partedTerms parts))
                         (CallWalked at rs.snd fs.snd
                            (replace {p = \ts => Reducing m d n ts written t}
                                     (trans (closedTerms args) (cong (map (closeBy substituted stand)) (partedTerms parts))) r))))

  ||| What a binder's implicitness holds: a default, which the key writes.
  passing : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            (stand : Values Substitute vs) -> (info : PiInfo (TT vs)) -> Front (Subset (List Template) (PassingAs m stand info))
  passing m w acc stand Implicit = pure (Element [] PImplicit)
  passing m w acc stand Explicit = pure (Element [] PExplicit)
  passing m w acc stand AutoImplicit = pure (Element [] PAuto)
  passing m w acc stand (DefImplicit d) = (\r => Element [r.fst] (PDefault r.snd)) <$> read m w acc stand d

  ||| A binder that is no lambda, applied: a head above its parts, its scope,
  ||| in which its variable is a placeholder, and the arguments.
  nodeBinder : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
               (stand : Values Substitute vs) -> (fc : FC) -> (x : Name) -> (b : TTBinder (TT vs)) -> (0 _ : NodeBinder b) ->
               (sc : TT (x :: vs)) -> (args : List (Arg m stand)) ->
               Front (Subset Template (SpineAs m stand (Bind fc x b sc) (termsOf args)))
  nodeBinder m w acc stand fc x b node sc args = do
    ps <- binder m w acc stand b node
    s <- read m w acc (Placeholding :: stand) sc
    rs <- readings args
    pure (Element (nodeOf m.keeping (Head Nothing ((ps.fst ++ [s.fst]) ++ rs.fst))) (SBinder ps.snd s.snd rs.snd))

  ||| A binder's parts, of a binder that is no lambda: its default, its type,
  ||| and a `let`'s value before it.
  binder : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           (stand : Values Substitute vs) -> (b : TTBinder (TT vs)) -> (0 _ : NodeBinder b) ->
           Front (Subset (List Template) (BinderAs m stand b))
  binder m w acc stand (Lam _ _ _ _) node = void (lambdaNoNode node)
  binder m w acc stand (Let _ _ v ty) _ = do
    tv <- read m w acc stand v
    t <- read m w acc stand ty
    pure (Element [tv.fst, t.fst] (BLet tv.snd t.snd))
  binder m w acc stand (Pi _ _ info ty) _ = do
    ps <- passing m w acc stand info
    t <- read m w acc stand ty
    pure (Element (ps.fst ++ [t.fst]) (BPi ps.snd t.snd))
  binder m w acc stand (PVar _ _ info ty) _ = do
    ps <- passing m w acc stand info
    t <- read m w acc stand ty
    pure (Element (ps.fst ++ [t.fst]) (BPVar ps.snd t.snd))
  binder m w acc stand (PLet _ _ v ty) _ = do
    tv <- read m w acc stand v
    t <- read m w acc stand ty
    pure (Element [tv.fst, t.fst] (BPLet tv.snd t.snd))
  binder m w acc stand (PVTy _ _ ty) _ = do
    t <- read m w acc stand ty
    pure (Element [t.fst] (BPVTy t.snd))

  ||| A reference applied, in every reading: a hole marker its token, an
  ||| argument of a family's value its own, a site's marker its family's
  ||| reading (applied, a head above it and its arguments), a runtime part
  ||| one node. A data constructor is a head in every reading, a type
  ||| constructor in a type's.
  reference : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
              (stand : Values Substitute vs) -> (fc : FC) -> (nt : NameType) -> (n : Name) -> (args : List (Arg m stand)) ->
              Front (Subset Template (SpineAs m stand (Ref fc nt n) (termsOf args)))
  reference m w acc stand fc Bound n args = do
    rs <- readings args
    pure (case holeView n of
            IsHole i hole => Element (partOf m.keeping (Token (S i)) rs.fst) (SHole hole rs.snd)
            NotHole none => boundName m fc n none rs.fst rs.snd)
  reference m w acc stand fc (DataCon tag arity) n args = do
    rs <- readings args
    pure (Element (Head (definitionAddress (gamma (defsOf m.inContext)) n) rs.fst) (SData Refl rs.snd))
  reference m w acc stand fc (TyCon arity) n args = do
    rs <- readings args
    pure (Element (nodeOf m.keeping (Head (definitionAddress (gamma (defsOf m.inContext)) n) rs.fst)) (STypeCon Refl rs.snd))
  reference m w acc stand fc Func n args with (definitionAddress (gamma (defsOf m.inContext)) n) proof found
    _ | Just a = ofDefinition m w acc stand fc n a found args
    _ | Nothing = do
      rs <- readings args
      pure (Element (partOf m.keeping (Leaf 1) rs.fst) (SNoDefinition found rs.snd))

  ||| A definition with a place, applied. In a site's type, a projection of a
  ||| record that is no constructor is, at an instance, one of two things:
  ||| the application as written, which a dictionary's key keeps (`classify`
  ||| takes a dictionary as written), and a normal form keeps while the
  ||| record stays no constructor; or the record's field (`Field`), once the
  ||| record is one. So it is the choice of both, behind the record it
  ||| matches. In a skeleton, a projection of a value is a match on it like
  ||| any other; in an instance's term it is as written, as its key is.
  ofDefinition : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                 (stand : Values Substitute vs) -> (fc : FC) -> (n : Name) -> (a : Address) ->
                 (0 _ : AddressedAs m n (Just a)) -> (args : List (Arg m stand)) ->
                 Front (Subset Template (SpineAs m stand (Ref fc Func n) (termsOf args)))
  ofDefinition (MkMode (OfSite stands) EveryNode cl ctx) w acc stand fc n a at args = do
    -- The mode written out, not named by an as pattern: the alternative
    -- below is a case block, which would see that name apart from it.
    Just (k, projected, extras) <- projectedRecord n args
      | Nothing => call (MkMode (OfSite stands) EveryNode cl ctx) w acc stand fc n a at args
    matched <- Force projected.reading
    rs <- readings args
    es <- readings extras
    pure (Element (Choice matched.fst [Head (Just a) rs.fst, partOf EveryNode (Template.Field k matched.fst) es.fst])
                  (SProjected at matched.snd rs.snd es.snd))
  ofDefinition m w acc stand fc n a at args = call m w acc stand fc n a at args

  call : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
         (stand : Values Substitute vs) -> (fc : FC) -> (n : Name) -> (a : Address) ->
         (0 _ : AddressedAs m n (Just a)) -> (args : List (Arg m stand)) ->
         Front (Subset Template (SpineAs m stand (Ref fc Func n) (termsOf args)))
  call (MkMode wh kp KeepsCall ctx) w acc stand fc n a at args = do
    rs <- readings args
    pure (Element (nodeOf kp (Head (Just a) rs.fst)) (SKept at rs.snd))
  call m w acc stand fc n a at args = applied m w acc stand fc n a at args

  ||| A definition left applied in a site's normal form or shape. The
  ||| normaliser leaves applied, whatever its arguments, one that does not
  ||| match (its visibility, an implementation under `normaliseTypes`, a
  ||| builtin) and one applied to fewer arguments than its parameters, so it
  ||| is applied at every instance too: it stays as written. One already
  ||| being unfolded on this path is a recursion (`Opaque`), unless the
  ||| first unfolding found it structural. Any other is unfolded, its case
  ||| tree walked over its arguments, beside the call as written: an
  ||| instance whose values leave its match stuck writes the call. A builtin
  ||| given as many arguments as it takes, the writer's markers among them,
  ||| computes, at an instance whose values are constants, a constant
  ||| (`Idris.Host.Primitive`), which is no higher than a leaf two high
  ||| (`Proof.Bound.AtComputed`). An instance's term is never unfolded: it
  ||| is its key.
  applied : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            (stand : Values Substitute vs) -> (fc : FC) -> (n : Name) -> (a : Address) ->
            (0 _ : AddressedAs m n (Just a)) -> (args : List (Arg m stand)) ->
            Front (Subset Template (SpineAs m stand (Ref fc Func n) (termsOf args)))
  applied (MkMode OfInstance kp cl ctx) w acc stand fc n a at args = do
    rs <- readings args
    pure (Element (nodeOf kp (Head (Just a) rs.fst)) (SKept at rs.snd))
  applied (MkMode (OfSite stands) kp cl ctx) w acc stand fc n a at args = do
    rs <- readings args
    -- Bound transparently: the evidence below is indexed by the template
    -- itself, so its name must stand for it in types.
    let written := nodeOf kp (Head (Just a) rs.fst)
    let folded = the (Subset Template (SpineAs (MkMode (OfSite stands) kp cl ctx) stand (Ref fc Func n) (termsOf args)))
                     (Element written (SKept at rs.snd))
    let Just (MkInFrozen placement def defines) = inFrozen ctx n
      | Nothing => pure folded
    let Nothing = believed (MkMode (OfSite stands) kp cl ctx) fc n a at def defines args rs
      | Just belief => pure belief
    outcome <- callRead (MkMode (OfSite stands) kp cl ctx) w acc a n placement def defines (map (\x => Force x.value) args) written
    pure (case outcome of
            AsWritten => folded
            Recurs => Element (Opaque a rs.fst) (SRecurs at rs.snd)
            Unfolded t r =>
              besides stands kp cl a at rs.fst rs.snd t
                      (replace {p = \ts => Reducing (MkMode (OfSite stands) kp cl ctx) a n ts written t} (closedTerms args) r))

  ||| A site's call of a definition the frozen context gives, at its
  ||| arguments as closed terms (`applied`): a definition given fewer
  ||| arguments than its parameters (`given`), one whose tree is one leaf,
  ||| which the normaliser would have unfolded had it matched nothing and
  ||| so stays as written, one met again on this path, one structural on a
  ||| Nat-like argument (`structural`), any other walked (`walk`); and a
  ||| builtin that computes a constant, given as many arguments as it takes
  ||| with the writer's markers among them, where every node is read and
  ||| calls are unfolded beside. `believe_me`
  ||| computes no constant: it gives back the value it is given, which
  ||| `applied` reads beside it where it is given its three arguments
  ||| (`believed`), and given any other count it is as written.
  callRead : {auto c : Ref Ctxt Defs} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
             (a : Address) -> (n : Name) -> Placement -> (def : GlobalDef) -> (0 _ : Defines m.inContext n def) ->
             (terms : List ClosedTerm) -> (written : Template) -> Front (CallRead m a n terms written)
  callRead m w acc@(Access rec) a n placement def defines terms written = case Element (definition def) Refl of
    Element (PMDef _ pargs body) isDef => do
      tree <- caseTreeOf body
      case Element (bindParams pargs terms) Refl of
        Element Nothing short => do
          Just t <- given m w acc placement a terms !(typeOfDefinition def) pargs tree.fst written
            | Nothing => pure AsWritten
          pure (Unfolded t.fst (ByGiven defines isDef tree.snd short t.snd))
        Element (Just (env, extras)) bound => case tree of
          Element (STerm _ _) _ => pure AsWritten
          Element tr inTree => case enter placement w of
            Nothing => pure Recurs
            Just (Element w' less) => do
              Nothing <- structural m w' (rec w' less) a terms env tr extras
                | Just t => pure (Unfolded t.fst (ByStructure defines isDef inTree bound t.snd))
              Element (Just t) walked <- walk m w' (rec w' less) a written env tr extras
                | Element Nothing _ => pure AsWritten
              pure (Unfolded t (ByWalk defines isDef inTree bound walked))
    Element (Builtin BelieveMe) _ => pure AsWritten
    Element (Builtin {arity} op) isBuiltin => case (m, mentionedAmong terms) of
      (MkMode _ EveryNode UnfoldsBeside _, Mentioned) => case decEq (length terms) arity of
        Yes saturated => pure (Unfolded (Leaf 2) (ByBuiltin defines isBuiltin saturated))
        -- Essential: the host computes a primitive applied to as many
        -- arguments as it takes, and no other (`Idris.Host.Primitive`); a
        -- builtin applied to more is `believe_me` or `crash`, neither of
        -- which computes a constant.
        No _ => pure AsWritten
      _ => pure AsWritten
    _ => pure AsWritten

  ||| A definition given fewer arguments than its parameters: a family's
  ||| value (or a function's). Its key holds it as written, and beta gives
  ||| it the rest, so in a type's form it is the choice of both (`applied`
  ||| puts the call as written beside): its case tree walked over an
  ||| argument (`Formal`) for each parameter it lacks, or, met again on its
  ||| own unfolding, a recursion through the arguments it lacks, which
  ||| nothing bounds. A skeleton keeps it as written: no value's skeleton is
  ||| applied.
  given : {auto c : Ref Ctxt Defs} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          Placement -> (a : Address) -> (terms : List ClosedTerm) -> (type : ClosedTerm) -> (pargs : Scope) ->
          (tree : CaseTree pargs) -> (written : Template) ->
          Front (Maybe (Subset Template (GivenUnfolds m a written terms pargs tree)))
  given (MkMode _ Skeleton _ _) w acc placement a terms ty pargs tree written = pure Nothing
  -- The mode written out where the walk is given it, inside case blocks,
  -- which would see a name bound by an as pattern apart from it.
  given (MkMode wh EveryNode cl ctx) w acc@(Access rec) placement a terms ty pargs tree written = do
    arities <- binderArities ty
    let lacking := formalsFrom 0 (drop (length terms) arities) (minus (length pargs) (length terms))
    case Element (bindParams pargs (terms ++ map substituted lacking)) Refl of
      Element Nothing _ => pure Nothing
      Element (Just (env, extras)) bound => case enter placement w of
        Nothing => pure (Just (Element (Opaque a (map substituteTemplate lacking)) GivenAgain))
        Just (Element w' less) => do
          Element (Just t) walked <- walk (MkMode wh EveryNode cl ctx) w' (rec w' less) a written env tree extras
            | Element Nothing _ => pure Nothing
          pure (Just (Element t (GivenWalked bound walked)))

  ||| A recursion structural on one Nat-like argument, read as the
  ||| argument raised by its leaves' height: `Choice (Var j e)` of the other
  ||| leaves and of `Var j e` under c heads, with c = max B S' - 1, B the
  ||| tallest other leaf and S' the tallest closed child of the successor's.
  |||
  ||| Proof, by induction on the argument v, with h(v) = k + 1 for k
  ||| successors: h(n Z) <= B <= 1 + c; h(n (S k)) <= 1 + max(S', h(n k))
  ||| <= 1 + h(k) + c = h(S k) + c, since h(k) >= 1 and c >= S' - 1. So
  ||| h(n v) <= h(v) + c, which is the reading's weight from `Var j e`. A
  ||| default's leaf is a base like the zero's. A leaf that holds another
  ||| marker grows by a sum of heights (`F a Z = a`), which no template
  ||| states, so it is no structural recursion; nor is a deeper step, a
  ||| recursion on a non-Nat value, a nested case tree, or two heads a
  ||| level.
  structural : {auto c : Ref Ctxt Defs} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
               (self : Address) -> (args : List ClosedTerm) -> (env : Values ClosedTerm vs) -> (tree : CaseTree vs) ->
               List ClosedTerm -> Front (Maybe (Subset Template (Structural m self args env tree)))
  structural m w acc self args env (Case idx p ty alts) extras =
    case Element (bareMarker (standsOf m) (valueAt env idx p)) Refl of
      Element Nothing _ => pure Nothing
      Element (Just (j, path)) marked => do
        let Just arms = natArms m.inContext j path env alts
          | Nothing => pure Nothing
        arms' <- traverse normalisedArm arms
        case Element (recursion (gamma (defsOf m.inContext)) (standsOf m) self (j, S (length path)) args idx arms') Refl of
          Element Nothing _ => pure Nothing
          Element (Just (bases, kids)) shaped => do
            leaves <- readAll (unfolding m) w acc [] bases
            children <- readAll (unfolding m) w acc [] kids
            pure (Just (Element _ (Raised marked shaped leaves.snd children.snd)))
    where
      normalisedArm : Arm -> Front Arm
      normalisedArm (Step t) = Step . (.readForm) . (.reading) <$> readNormal EveryRedex m.inContext (applyTo t extras)
      normalisedArm (Base t) = Base . (.readForm) . (.reading) <$> readNormal EveryRedex m.inContext (applyTo t extras)
  structural _ _ _ _ _ _ _ _ = pure Nothing

  ||| A case tree walked over what its variables stand for, the leaves it
  ||| can reach read under the walk that entered it; nothing for an absurd
  ||| tree. A match on a constructor, a literal or a delay takes its
  ||| alternative, as the normaliser would at every instance; one on a
  ||| runtime value is stuck at every instance, so the definition stays as
  ||| written; one on a marker, or on what is stuck in turn, is a `Choice`
  ||| of every alternative's leaves behind what it matched on; one on an
  ||| argument of a family's value is the choice of the definition as
  ||| written and of a recursion of `self` stuck on that argument, since
  ||| what it computes depends on what beta substitutes there. What it read
  ||| comes with how (`Unfolds`).
  walk : {auto c : Ref Ctxt Defs} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
         (self : Address) -> (written : Template) -> (env : Values ClosedTerm vs) -> (tree : CaseTree vs) ->
         (extras : List ClosedTerm) -> Front (Subset (Maybe Template) (Unfolds m self written env tree extras))
  walk m w acc self written env (STerm _ rhs) extras = do
    r <- readNormal (contractingFor (unfolding m)) m.inContext (applyTo (close env rhs) extras)
    t <- read (unfolding m) w acc [] r.reading.readForm
    pure (Element (Just t.fst) (ULeaf r t.snd))
  -- A partial definition stops where it does not match, at every instance.
  walk m w acc self written env (Unmatched _) extras = pure (Element (Just written) UUnmatched)
  walk m w acc self written env Impossible extras = pure (Element Nothing UImpossible)
  walk m w acc self written env (Case idx p ty alts) extras =
    case Element (scrutineeOf (gamma (defsOf m.inContext)) (standsOf m) (valueAt env idx p)) Refl of
      Element (Constructed h c sargs _ _) found =>
        (\r => Element r.fst (UConstructed found r.snd)) <$> chosen m w acc self written env h c sargs alts extras
      Element (Literal k _) found => (\r => Element r.fst (ULiteral found r.snd)) <$> literal m w acc self written env k alts extras
      Element (Suspended dty da _) found =>
        (\r => Element r.fst (USuspended found r.snd)) <$> delayed m w acc self written env dty da alts extras
      -- A constructor's argument is a part of the matched value, one level
      -- deeper, at its own field.
      Element (Matched i path) found =>
        (\r => Element (Just (Choice (Var i (length path)) r.fst)) (UMatched found r.snd))
          <$> everyAlt m w acc self written env (PartsOf i path) alts extras
      -- An argument of a family's value: as written, which every key of
      -- the value holds and an argument at run time leaves stuck; or, once
      -- beta substitutes the argument, what the match computes from it,
      -- which nothing bounds (`beta` says the value computes).
      Element (OnFormal j k) found => pure (Element (Just (Choice (Formal j k) [written, Opaque self [Formal j k]])) (UOnFormal found))
      Element AtRuntime found => pure (Element (Just written) (UAtRuntime found))
      -- A constructor's argument is a part of the value, so the value
      -- bounds it.
      Element StuckInTurn found => do
        t <- read (unfolding m) w acc [] (valueAt env idx p)
        r <- everyAlt m w acc self written env (AllOf (valueAt env idx p)) alts extras
        pure (Element (Just (Choice t.fst r.fst)) (UStuck found t.snd r.snd))

  ||| The alternative a constructor takes, by the entry its name resolves
  ||| to, as the host's step takes it: the context's comparison of entries
  ||| (`Idris.Host.compareEntries`) gives the step's own evidence, and an
  ||| alternative at another entry is passed only where the host misses it.
  chosen : {auto c : Ref Ctxt Defs} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           (self : Address) -> (written : Template) -> (env : Values ClosedTerm vs) -> (h : ConstructorHead) ->
           (name : Name) -> (sargs : List ClosedTerm) -> (alts : List (CaseAlt vs)) -> (extras : List ClosedTerm) ->
           Front (Subset (Maybe Template) (TakenBy m self written env h name sargs alts extras))
  chosen m w acc self written env h c sargs (ConCase con tag cargs sc :: alts) extras =
    case compareEntries m.inContext c con of
      BothAt same => case Element (bindEach cargs sargs) Refl of
        Element (Just bound) binds =>
          (\r => Element r.fst (TakesThis same binds r.snd)) <$> walk m w acc self written (extend bound env) sc extras
        -- Essential: the evaluator's walk of the tree is stuck where a
        -- constructor meets an alternative at its entry binding other than
        -- its arguments, so every instance leaves the definition there.
        Element Nothing differs => pure (Element (Just written) (ArityDiffers same differs))
      Apart apart => case anotherEntry h tag of
        Passed missed =>
          (\r => Element r.fst (PassesThis apart missed r.snd)) <$> chosen m w acc self written env h c sargs alts extras
        -- Essential: the host's walk is stuck where a data constructor
        -- meets an alternative of its tag at another entry.
        Blocked shared => pure (Element (Just written) (TagShared apart shared))
  chosen m w acc self written env h c sargs (DefaultCase sc :: _) extras =
    (\r => Element r.fst (TakesDefault r.snd)) <$> walk m w acc self written env sc extras
  -- Essential: a constructor neither matches nor misses an alternative of
  -- a delay or a constant, and the host's walk is stuck there.
  chosen m w acc self written env h c sargs (DelayCase _ _ _ :: _) extras = pure (Element (Just written) MeetsDelay)
  chosen m w acc self written env h c sargs (ConstCase _ _ :: _) extras = pure (Element (Just written) MeetsConstant)
  chosen m w acc self written env h c sargs [] extras = pure (Element (Just written) NoneTaken)

  literal : {auto c : Ref Ctxt Defs} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            (self : Address) -> (written : Template) -> (env : Values ClosedTerm vs) -> (k : Constant) ->
            (alts : List (CaseAlt vs)) -> (extras : List ClosedTerm) ->
            Front (Subset (Maybe Template) (TakesLiteral m self written env k alts extras))
  -- A constant alternative and a primitive type's are compared with the
  -- literal by the evaluator's own comparison, the one its step decides
  -- by, so the walk takes the alternative every instance's evaluation
  -- takes.
  literal m w acc self written env k (ConstCase k' t :: alts) extras with (k' == k) proof compared
    _ | True = (\r => Element r.fst (LiteralMeets compared r.snd)) <$> walk m w acc self written env t extras
    _ | False = (\r => Element r.fst (LiteralPasses compared r.snd)) <$> literal m w acc self written env k alts extras
  literal m w acc self written env k (ConCase cn tag [] t :: alts) extras with (map PrT (isConstantType (dropNS cn)) == Just k) proof named
    _ | True = (\r => Element r.fst (LiteralNamesType named r.snd)) <$> walk m w acc self written env t extras
    _ | False = (\r => Element r.fst (LiteralOtherType named r.snd)) <$> literal m w acc self written env k alts extras
  literal m w acc self written env k (ConCase cn tag (_ :: _) t :: alts) extras =
    (\r => Element r.fst (LiteralFields r.snd)) <$> literal m w acc self written env k alts extras
  literal m w acc self written env k (DefaultCase t :: _) extras =
    (\r => Element r.fst (LiteralDefault r.snd)) <$> walk m w acc self written env t extras
  -- Essential: a literal neither matches nor misses a delay's
  -- alternative, and the host's walk is stuck there.
  literal m w acc self written env k (DelayCase _ _ _ :: _) extras = pure (Element (Just written) LiteralMeetsDelay)
  literal m w acc self written env k [] extras = pure (Element (Just written) NoLiteral)

  delayed : {auto c : Ref Ctxt Defs} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            (self : Address) -> (written : Template) -> (env : Values ClosedTerm vs) -> (dty, da : ClosedTerm) ->
            (alts : List (CaseAlt vs)) -> (extras : List ClosedTerm) ->
            Front (Subset (Maybe Template) (TakesDelay m self written env dty da alts extras))
  delayed m w acc self written env dty da (DelayCase _ _ t :: _) extras =
    (\r => Element r.fst (DelayThis r.snd)) <$> walk m w acc self written (dty :: da :: env) t extras
  delayed m w acc self written env dty da (DefaultCase t :: _) extras =
    (\r => Element r.fst (DelayDefault r.snd)) <$> walk m w acc self written env t extras
  -- Essential: a delay neither matches nor misses an alternative of a
  -- constructor or a constant, and the host's walk is stuck there.
  delayed m w acc self written env dty da (ConCase _ _ _ _ :: _) extras = pure (Element (Just written) DelayMeetsConstructor)
  delayed m w acc self written env dty da (ConstCase _ _ :: _) extras = pure (Element (Just written) DelayMeetsConstant)
  delayed m w acc self written env dty da [] extras = pure (Element (Just written) NoDelay)

  ||| Every alternative's leaves, each argument a constructor or a delay
  ||| binds as the match binds it (`FieldsOf`); an absurd one gives none.
  everyAlt : {auto c : Ref Ctxt Defs} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
             (self : Address) -> (written : Template) -> (env : Values ClosedTerm vs) -> (f : FieldsOf) ->
             (alts : List (CaseAlt vs)) -> (extras : List ClosedTerm) ->
             Front (Subset (List Template) (Alternatives m self written env f alts extras))
  everyAlt m w acc self written env f [] extras = pure (Element [] NoAlternatives)
  everyAlt m w acc self written env f (alt :: alts) extras = do
    here <- alternative m w acc self written env f alt extras
    rest <- everyAlt m w acc self written env f alts extras
    pure (Element (maybe rest.fst (\u => u :: rest.fst) here.fst) (WithAlternative here.snd rest.snd))

  alternative : {auto c : Ref Ctxt Defs} -> (m : Mode) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                (self : Address) -> (written : Template) -> (env : Values ClosedTerm vs) -> (f : FieldsOf) ->
                (alt : CaseAlt vs) -> (extras : List ClosedTerm) ->
                Front (Subset (Maybe Template) (AlternativeUnfolds m self written env f alt extras))
  alternative m w acc self written env f (ConCase _ _ cargs t) extras =
    (\r => Element r.fst (ConstructorAlternative r.snd)) <$> walk m w acc self written (extend (boundFields f 0 cargs) env) t extras
  alternative m w acc self written env f (DelayCase _ _ t) extras =
    (\r => Element r.fst (DelayAlternative r.snd)) <$> walk m w acc self written (fieldOf f 0 :: fieldOf f 1 :: env) t extras
  alternative m w acc self written env f (ConstCase _ t) extras =
    (\r => Element r.fst (ConstantAlternative r.snd)) <$> walk m w acc self written env t extras
  alternative m w acc self written env f (DefaultCase t) extras =
    (\r => Element r.fst (DefaultAlternative r.snd)) <$> walk m w acc self written env t extras

||| A closed term read on a walk that has entered nothing yet.
readFromStart : {auto c : Ref Ctxt Defs} -> (m : Mode) -> (t : ClosedTerm) -> Front (Subset Template (ReadAs m [] t))
readFromStart m t = read m start (sizeAccessible start) [] t

mutual
  ||| A shape's template as a key holds its form (`Shapes.formOf`): each
  ||| `:<` of its spine, the constructor of tag 1 as `Shapes.shapeView`
  ||| reads it, with its extent the leaf an erased extent is; any other
  ||| part (`Lin`, the writer's marker, a computation) as it is, and each
  ||| leaf of a choice so. A form's height is then the key's, whatever
  ||| extents are written, so that a key and the bound on it are read alike.
  formedReading : {auto c : Ref Ctxt Defs} -> (t : Template) -> Front (Subset Template (KeyForm t))
  -- The template written out where it is read as itself: the alternatives
  -- are case blocks, which would see a name bound by an as pattern apart
  -- from the template it matched.
  formedReading (Head (Just a) [e, rest, x]) = do
    ctx <- frozenContext
    let Just def = atAddress ctx a
      | Nothing => pure (Element (Head (Just a) [e, rest, x]) AsRead)
    case definition def of
      DCon 1 _ _ => (\r => Element (Head (Just a) [e, r.fst, Leaf 1]) (ExtentErased r.snd)) <$> formedReading rest
      _ => pure (Element (Head (Just a) [e, rest, x]) AsRead)
  formedReading (Choice s ls) = (\r => Element (Choice s r.fst) (LeavesFormed r.snd)) <$> formedReadings ls
  formedReading t = pure (Element t AsRead)

  formedReadings : {auto c : Ref Ctxt Defs} -> (ts : List Template) -> Front (Subset (List Template) (AllKeyForm ts))
  formedReadings [] = pure (Element [] NoneFormed)
  formedReadings (t :: ts) = do
    r <- formedReading t
    rs <- formedReadings ts
    pure (Element (r.fst :: rs.fst) (EachFormed r.snd rs.snd))

||| A shape's template as a key holds its form (`formedReading`).
export
formedTemplate : {auto c : Ref Ctxt Defs} -> Template -> Front Template
formedTemplate t = (.fst) <$> formedReading t

------------------------------------------------------------------------------
-- A static argument read
------------------------------------------------------------------------------

||| A dictionary's form, as `classify` keys it, how it was read off the
||| term, and the evidence its contraction gives that no redex is left in
||| it (`Contraction.EtaNormal`): every reading of a dictionary contracts every
||| redex.
record DictionaryForm (ctx : Frozen) (t : ClosedTerm) where
  constructor MkDictionaryForm
  form : ClosedTerm
  0 formFrom : FormFrom ADictionary ctx t form
  0 maximal : EtaNormal EveryRedex form

||| A dictionary's form, as `classify` keys it: as written, or the
||| implementation it stands for where it depends on a runtime value.
dictionaryForm : {auto c : Ref Ctxt Defs} -> (ctx : Frozen) -> (t : ClosedTerm) -> Front (DictionaryForm ctx t)
dictionaryForm ctx t = do
  s <- solving ctx t
  if !(runtimeDependent s.fst)
     then do
       impl <- implementationOf s.fst
       let c = contracted impl
       pure (MkDictionaryForm c.etaForm (FromImplementation c.etaSteps) c.etaNormal)
     else
       let c = contracted s.fst in
       pure (MkDictionaryForm c.etaForm (FromWritten WrittenDictionary s.snd c.etaSteps) c.etaNormal)

||| A site's static argument read: the mode it is read in, the context of
||| which is the one every normal form and definition of the reading is
||| over, the form its reading reads, how it was read off the term in that
||| context and the evidence that the contraction it was read by left no
||| redex it contracts (`contractingFor`), the template it reads as with
||| what that says of the form, and what the site writes there, the
||| template with a form's extents as its key holds them.
public export
record SiteReading (k : Readings.Static) (t : ClosedTerm) where
  constructor MkSiteReading
  0 mode : Mode
  form : ClosedTerm
  0 formFrom : FormFrom k mode.inContext t form
  0 maximal : EtaNormal (contractingFor mode) form
  read : Template
  0 describes : ReadAs mode [] form read
  template : Template
  0 formed : KeyForm read template

||| A term of a site's read off its normal form, in the mode's context.
normalSite : {auto c : Ref Ctxt Defs} -> {0 k : Readings.Static} -> (m : Mode) -> (t : ClosedTerm) -> Front (SiteReading k t)
normalSite m t = do
  n <- readNormal (contractingFor m) m.inContext t
  r <- readFromStart m n.reading.readForm
  pure (MkSiteReading m n.reading.readForm (FromNormalForm n.reading) n.maximal r.fst r.snd r.fst AsRead)

||| What a site, a field or a cap writes at a static argument of kind k, a
||| term whose stand-ins are `stands`, read as its key writes it there
||| (`Instances.classify`) at every instance. It is normalised with each
||| stand-in its own marker, and only the reading reads it as the part it
||| stands for. A type, a family and a form are normalised as classify
||| normalises them, stuck definitions unfolded beside the calls as
||| written, and a form is read as its key holds it (`formedReading`). A
||| dictionary is the form classify keys: as written, or the
||| implementation it stands for when it depends on a runtime value,
||| nothing normalised or unfolded. A shape is a skeleton: of the argument
||| as written when a data constructor heads it, else of its normal form
||| (`Instances.argumentShape`). The frozen context is read once, here,
||| and the whole reading is over it.
export
siteReading : {auto c : Ref Ctxt Defs} -> (stands : List StandIn) -> (k : Readings.Static) -> (t : ClosedTerm) ->
              Front (SiteReading k t)
siteReading stands AType t = do
  ctx <- frozenContext
  normalSite (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) t
siteReading stands AFamily t = do
  ctx <- frozenContext
  normalSite (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) t
siteReading stands AForm t = do
  ctx <- frozenContext
  n <- readNormal (contractingFor (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx)) ctx t
  r <- readFromStart (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) n.reading.readForm
  f <- formedReading r.fst
  pure (MkSiteReading (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) n.reading.readForm (FromNormalForm n.reading)
                      n.maximal r.fst r.snd f.fst f.snd)
siteReading stands ADictionary t = do
  ctx <- frozenContext
  d <- dictionaryForm ctx t
  r <- readFromStart (MkMode (OfSite stands) EveryNode KeepsCall ctx) d.form
  pure (MkSiteReading (MkMode (OfSite stands) EveryNode KeepsCall ctx) d.form d.formFrom d.maximal r.fst r.snd r.fst AsRead)
siteReading stands AShape t = do
  ctx <- frozenContext
  s <- solving ctx t
  case getFnArgs s.fst of
    (Ref _ (DataCon _ _) _, _) => do
      let c = contracted s.fst
      r <- readFromStart (MkMode (OfSite stands) Skeleton KeepsCall ctx) c.etaForm
      pure (MkSiteReading (MkMode (OfSite stands) Skeleton KeepsCall ctx) c.etaForm
                          (FromWritten WrittenShape s.snd c.etaSteps) c.etaNormal r.fst r.snd r.fst AsRead)
    _ => normalSite (MkMode (OfSite stands) Skeleton UnfoldsBeside ctx) t

||| What a site writes at a static argument (`siteReading`).
export
templateOf : {auto c : Ref Ctxt Defs} -> List StandIn -> Readings.Static -> ClosedTerm -> Front Template
templateOf stands k t = (.template) <$> siteReading stands k t

||| Where a type matches on its writer's parameters: its normal form read
||| with every stuck definition's case tree walked, and nothing beside it.
||| A cap is the deepest such match (`Caps.capFrom`): the call as written,
||| which a key reading puts beside each walk (`applied`), reduces at the
||| depth a cap cuts at, so it is no part of what the type matches on.
export
capTemplate : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Front Template
capTemplate t = do
  ctx <- frozenContext
  (.template) <$> normalSite {k = AType} (MkMode (OfSite []) EveryNode WalksAlone ctx) t

------------------------------------------------------------------------------
-- The measures
------------------------------------------------------------------------------

||| What beta makes of the family values a template holds, each read as
||| its meaning (lambdas' variables and the parameters a definition lacks
||| as arguments, `Formal`): no higher than the value above the tallest
||| argument (`Inert`), or what nothing bounds (`Computes`). A value
||| computes when its meaning holds a definition stuck on one of its
||| arguments (`Opaque`: beta lets its match go on), or applies an argument
||| to what holds another argument, or to other than as many arguments as
||| it takes: a sum of two heights. Each of these is a case of the problem:
||| an argument that beta substitutes into a computation, rather than
||| places.
public export
data Beta = Inert | Computes

both : Beta -> Beta -> Beta
both Inert b = b
both Computes _ = Computes

mutual
  -- Does any of these templates hold an argument of a family's value?
  holdsFormal : List Template -> Bool
  holdsFormal [] = False
  holdsFormal (t :: ts) = formalIn t || holdsFormal ts

  formalIn : Template -> Bool
  formalIn (Formal _ _) = True
  formalIn (Head _ ts) = holdsFormal ts
  formalIn (Opaque _ ts) = holdsFormal ts
  formalIn (Applied _ _ ts) = holdsFormal ts
  formalIn (Computing _ _ ts) = holdsFormal ts
  formalIn (Choice s ts) = formalIn s || holdsFormal ts
  formalIn (Field _ t) = formalIn t
  formalIn _ = False

mutual
  ||| What beta makes of the family values a template holds (`Beta`). An
  ||| argument that takes arguments of its own reads as a head above them
  ||| when it is applied (`marked`); one that takes none at the head of a
  ||| node is a binder's type, which is no application.
  export
  beta : Template -> Beta
  beta (Opaque _ ts) = if holdsFormal ts then Computes else betaAll ts
  beta (Head Nothing (Formal _ k@(S _) :: args)) =
    if length args /= k || holdsFormal args then Computes else betaAll args
  beta (Formal _ (S _)) = Computes
  beta (Head _ ts) = betaAll ts
  beta (Choice _ ts) = betaAll ts
  beta (Applied _ _ ts) = betaAll ts
  beta (Computing _ _ _) = Computes
  beta (Field _ t) = beta t
  beta (Var _ _) = Inert
  beta (Leaf _) = Inert
  beta (Token _) = Inert
  beta (Member _) = Inert
  beta (Formal _ Z) = Inert

  betaAll : List Template -> Beta
  betaAll [] = Inert
  betaAll (t :: ts) = both (beta t) (betaAll ts)

||| What lands at the position of a family the writer was given, over the
||| growth graph's walk: only closed values no higher than k, each inert; or
||| inert values not all closed, whose height an arc carries; or a value
||| that computes, carried there from where one lands or written there not
||| closed; or closed values only, some computing, which are these terms:
||| a family applied there is evaluated at each (`Graph.evaluated`).
public export
data Landing = Closed Nat | Open | Computed | Evaluable (List ClosedTerm)

mutual
  -- The writer's families a template carries on as families: the whole
  -- template when it is one of them (a family passed on), and every one
  -- applied in it (inside a family's value, what beta makes of the value
  -- is what the family makes). Anywhere else a marker is a type's part,
  -- which beta never applies.
  export
  familiesIn : Template -> List Nat
  familiesIn (Var i _) = [i]
  familiesIn t = appliedIn t

  appliedIn : Template -> List Nat
  appliedIn (Applied i _ ts) = i :: appliedAll ts
  appliedIn (Computing i _ ts) = i :: appliedAll ts
  appliedIn (Head _ ts) = appliedAll ts
  appliedIn (Opaque _ ts) = appliedAll ts
  appliedIn (Choice s ts) = appliedIn s ++ appliedAll ts
  appliedIn (Field _ t) = appliedIn t
  appliedIn _ = []

  appliedAll : List Template -> List Nat
  appliedAll [] = []
  appliedAll (t :: ts) = appliedIn t ++ appliedAll ts

mutual
  -- The writer's families whose landing an applied family in a template
  -- reads: each family applied, and each one its arguments carry on
  -- (`withClosedFamilies`).
  export
  applyingIn : Template -> List Nat
  applyingIn (Applied i _ ts) = i :: (ts >>= familiesIn) ++ applyingAll ts
  applyingIn (Computing i _ ts) = i :: (ts >>= familiesIn) ++ applyingAll ts
  applyingIn (Head _ ts) = applyingAll ts
  applyingIn (Opaque _ ts) = applyingAll ts
  applyingIn (Choice s ts) = applyingIn s ++ applyingAll ts
  applyingIn (Field _ t) = applyingIn t
  applyingIn _ = []

  applyingAll : List Template -> List Nat
  applyingAll [] = []
  applyingAll (t :: ts) = applyingIn t ++ applyingAll ts

-- Whether arguments applied to a family give beta what computes: one of
-- them computes, or carries on a family where a computing value lands. A
-- family's value may apply an argument it is given, and what that
-- argument computes from its own arguments is then in the result.
export
argumentsBeta : (Nat -> Landing) -> List Template -> Beta
argumentsBeta c ts = both (betaAll ts) (if any computing (ts >>= familiesIn) then Computes else Inert)
  where
    computing : Nat -> Bool
    computing i = case c i of
      Computed => True
      Evaluable _ => True
      _ => False

||| A template read at a node (`withClosedFamilies`), with the writer's
||| families the reading landed closed: each applied where only closed
||| values land, its arguments inert, which the reading writes as heads
||| above its arguments (`landedAs`), so the template no longer names it.
||| The writer still reads each at a position, where those values land,
||| and what an instance writes there rests on them: the graph lists each
||| among the site's writers, carried from where the reading drops it.
public export
record LandedReading where
  constructor MkLandedReading
  template : Template
  landed : List Nat

||| Templates read at a node, in order, with the families their readings
||| landed closed.
public export
record LandedReadings where
  constructor MkLandedReadings
  templates : List Template
  allLanded : List Nat

||| A family of the writer's, applied, read at a node: by what lands at its
||| position and what beta makes of its arguments (`withClosedFamilies`);
||| landed closed where only closed values land and its arguments are
||| inert, the one case that drops the family.
public export
landedAs : Landing -> Beta -> (i, d : Nat) -> List Template -> LandedReading
landedAs Computed _ i d ts = MkLandedReading (Computing i d ts) []
landedAs (Evaluable _) _ i d ts = MkLandedReading (Computing i d ts) []
landedAs (Closed _) Computes i d ts = MkLandedReading (Computing i d ts) []
landedAs Open Computes i d ts = MkLandedReading (Computing i d ts) []
landedAs (Closed k) Inert i d ts = MkLandedReading (raise k (Head Nothing ts)) [i]
landedAs Open Inert i d ts = MkLandedReading (Applied i d ts) []

-- What follows is public, as `readLanded` is, so that a proof over a
-- template read at a node reads off what each node becomes.

||| A node over its children read, landing what they landed.
public export
nodeLanded : (List Template -> Template) -> LandedReadings -> LandedReading
nodeLanded node rs = MkLandedReading (node rs.templates) rs.allLanded

||| A reading of one node, landing what it lands and then what its
||| children landed.
public export
landedOver : LandedReading -> List Nat -> LandedReading
landedOver here rest = MkLandedReading here.template (here.landed ++ rest)

||| A family applied to its arguments read, read as its landing says,
||| landing what it lands and what they landed.
public export
landedApplied : (Nat -> Landing) -> (i, d : Nat) -> LandedReadings -> LandedReading
landedApplied c i d rs = landedOver (landedAs (c i) (argumentsBeta c rs.templates) i d rs.templates) rs.allLanded

||| A choice over its scrutinee and leaves read.
public export
choiceLanded : LandedReading -> LandedReadings -> LandedReading
choiceLanded x rs = MkLandedReading (Choice x.template rs.templates) (x.landed ++ rs.allLanded)

||| A field of its record read.
public export
fieldLanded : Nat -> LandedReading -> LandedReading
fieldLanded k x = MkLandedReading (Field k x.template) x.landed

||| A template read before the rest.
public export
consLanded : LandedReading -> LandedReadings -> LandedReadings
consLanded x rs = MkLandedReadings (x.template :: rs.templates) (x.landed ++ rs.allLanded)

mutual
  ||| A template read at a node, each applied family of the writer's by what
  ||| lands at its position (`Graph`), with the families it landed closed.
  ||| Beta of an inert family no higher than k, applied to arguments no
  ||| higher than h, is no higher than k + h (`Proof.Bound.instHeight`): the
  ||| value's meaning is a part of the value, no higher than it. So where
  ||| only closed values no higher than k land, an applied family reads as
  ||| k heads above its arguments; where values not all closed land, it
  ||| stays applied, the family's own height carried by an arc when its
  ||| arguments are closed (`appliedWeight`), and a sum of two heights
  ||| otherwise; and where a value may compute, or an argument does, it
  ||| reads as computing (`Computing`), a value nothing bounds.
  public export
  readLanded : (landing : Nat -> Landing) -> Template -> LandedReading
  readLanded c (Applied i d ts) = landedApplied c i d (readAllLanded c ts)
  readLanded c (Computing i d ts) = nodeLanded (Computing i d) (readAllLanded c ts)
  readLanded c (Head a ts) = nodeLanded (Head a) (readAllLanded c ts)
  readLanded c (Opaque a ts) = nodeLanded (Opaque a) (readAllLanded c ts)
  readLanded c (Choice t ts) = choiceLanded (readLanded c t) (readAllLanded c ts)
  readLanded c (Field k t) = fieldLanded k (readLanded c t)
  readLanded c t@(Var _ _) = MkLandedReading t []
  readLanded c t@(Leaf _) = MkLandedReading t []
  readLanded c t@(Token _) = MkLandedReading t []
  readLanded c t@(Member _) = MkLandedReading t []
  readLanded c t@(Formal _ _) = MkLandedReading t []

  public export
  readAllLanded : (landing : Nat -> Landing) -> List Template -> LandedReadings
  readAllLanded c [] = MkLandedReadings [] []
  readAllLanded c (t :: ts) = consLanded (readLanded c t) (readAllLanded c ts)

||| A template read at a node (`readLanded`), as the graph draws it.
public export
withClosedFamilies : (landing : Nat -> Landing) -> Template -> Template
withClosedFamilies c t = (readLanded c t).template

||| Templates read at a node, in order.
public export
allWithClosed : (landing : Nat -> Landing) -> List Template -> List Template
allWithClosed c ts = (readAllLanded c ts).templates

------------------------------------------------------------------------------
-- Roots and requests
------------------------------------------------------------------------------

||| A part of a dictionary met on the way to its root: as written, the
||| constructor it is built with and that constructor's arguments, and the
||| implementation at its root, each found when needed, on the walk where
||| the part was met.
record Piece where
  constructor MkPiece
  written : Lazy ClosedTerm
  built : Lazy (Front (Maybe (Name, List Piece)))
  root : Lazy (Front Root)

||| The implementations a definition's leaves give, as its root: none roots
||| nothing.
givesOf : List Address -> Root
givesOf [] = Unrooted
givesOf (m :: ms) = Gives (m ::: ms)

||| The implementations an instance that fixes a dictionary can make it.
fixedAddresses : FixedRoot -> List Address
fixedAddresses (BuiltBy a) = [a]
fixedAddresses (GivenBy js) = js

||| The implementations a root can be: none for the writer's own parameter,
||| whose head is the node's; for one the running program chooses, whose
||| members its choice holds, only those an instance that fixes it after
||| all makes it; and none for what roots nothing.
addresses : Root -> List Address
addresses (Rooted j) = [j]
addresses (Chosen AtRunTimeAlways) = []
addresses (Chosen (FixedAt f)) = fixedAddresses f
addresses (Gives ms) = forget ms
addresses (Parameter _ _) = []
addresses Unrooted = []

||| The type of a definition applied to arguments, normalised as a type is
||| read: each argument put in for the binder that takes it, and past the
||| binders the type shows, what it shows.
appliedType : {auto c : Ref Ctxt Defs} -> ClosedTerm -> List ClosedTerm -> Front ClosedTerm
appliedType ty [] = normaliseClosed ty
appliedType ty (a :: as) = do
  Bind _ _ (Pi {}) sc <- showingBinder ty
    | shown => normaliseClosed shown
  appliedType (subst a sc) as

-- A dictionary is taken apart the way the growth graph reads one
-- (`Implementations.fieldsOf`, `Heads`) and the translation projects one
-- (`Closed`'s projections take the field this way first): a projection
-- takes its field from the constructor its record is built with, and a
-- record is built with one as written, or once a definition with one
-- right-hand side (an implementation) is unfolded over its arguments. A
-- projection whose record is built with none (a marker, a runtime part)
-- has no root of its own: the template's field says what it is. Nothing
-- goes to Idris's normaliser, whose normal form of a record unfolds the
-- implementations inside the field too.
mutual
  ||| A part met as an argument of a spine.
  pieceOf : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) -> ClosedTerm -> Piece
  pieceOf w acc t = MkPiece t (builtOf w acc t []) (rootOf w acc t [])

  ||| The constructor a dictionary is built with, and its arguments; nothing
  ||| for a marker, a runtime part, a definition that matches, or one met
  ||| again on its own unfolding.
  builtOf : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            ClosedTerm -> List Piece -> Front (Maybe (Name, List Piece))
  builtOf w acc (App _ f a) args = builtOf w acc f (pieceOf w acc a :: args)
  builtOf w acc (Ref _ (DataCon _ _) n) args = pure (Just (n, args))
  builtOf w acc (Ref _ Func n) args = do
    Just pr <- projection n
      | Nothing => unfoldedBuilt w acc n args
    Just (field, extras) <- projectedPiece pr args
      | Nothing => pure Nothing
    map (\(con, fields) => (con, fields ++ extras)) <$> Force field.built
  builtOf w acc _ _ = pure Nothing

  ||| A definition with one right-hand side, applied to its parameters,
  ||| unfolded: the constructor its body is built with.
  unfoldedBuilt : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                  Name -> List Piece -> Front (Maybe (Name, List Piece))
  unfoldedBuilt w acc@(Access rec) n args = do
    ctx <- frozenContext
    let Just (MkInFrozen placement def _) = inFrozen ctx n
      | Nothing => pure Nothing
    case definition def of
      PMDef _ pargs pbody => do
        -- A definition of one right-hand side; of one that matches, nothing
        -- is decoded.
        Just body <- leafOfBody pbody
          | Nothing => pure Nothing
        case bindParams pargs args of
          Nothing => pure Nothing
          -- Entered already: met again on its own unfolding.
          Just (env, extras) => case enter placement w of
            Nothing => pure Nothing
            Just (Element w' less) =>
              let written : Piece -> ClosedTerm
                  written p = Force p.written in
              builtOf w' (rec w' less) (applyTo (closeBy written env body) (map written extras)) []
      _ => pure Nothing

  ||| A projection applied to its parameters: the field it takes from the
  ||| constructor its record is built with, and the arguments past the
  ||| projection's own.
  projectedPiece : {auto c : Ref Ctxt Defs} -> Projection -> List Piece -> Front (Maybe (Piece, List Piece))
  projectedPiece pr args = do
    let Just (env, extras) = bindParams pr.params args
      | Nothing => pure Nothing
    Just (con, fields) <- Force (valueAt env pr.matched pr.isParam).built
      | Nothing => pure Nothing
    ctx <- frozenContext
    if fullNameIn ctx con /= fullNameIn ctx pr.con
       then pure Nothing
       else pure ((, extras) <$> getAt pr.field fields)

  ||| The implementation, or the constructor, at a dictionary's root: one of
  ||| the walk's markers is the writer's own dictionary; a constructor
  ||| applied, or a definition applied that is no projection (an
  ||| implementation), is itself; a projection is its field's root when its
  ||| record is built with a constructor, and has none when it is not (its
  ||| record a marker, a runtime part, a definition that matches): what it
  ||| is then, the template's field says (`Heads`). A runtime value (a hole,
  ||| a runtime part, a value closed as unknown) is one the running program
  ||| chooses. A field applied to further arguments is a function, and roots
  ||| nothing.
  rootOf : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           ClosedTerm -> List Piece -> Front Root
  rootOf w acc (App _ f a) args = rootOf w acc f (pieceOf w acc a :: args)
  rootOf w acc (Ref _ nt n) args = do
    ctx <- frozenContext
    -- A stand-in is a part of a runtime value, never a dictionary: read as
    -- a runtime part, it names no implementation, as its marker matched
    -- deeper would name none of its own, so a root reads no site's
    -- stand-ins.
    case referenceOf (gamma (defsOf ctx)) [] nt n of
      PartMarker i path => pure (Parameter i (length path))
      DataConstructor a => pure (maybe Unrooted Rooted a)
      AtDefinition a => do
        Just pr <- projection n
          | Nothing => definitionRoot w acc (Ref EmptyFC nt n) n a (map (\p => Force p.written) args)
        Just (field, []) <- projectedPiece pr args
          | _ => pure Unrooted
        Force field.root
      -- A field of a dictionary, which the template's field says, and
      -- what is no dictionary.
      FieldMarker _ _ => pure Unrooted
      HoleMarker _ => pure (Chosen AtRunTimeAlways)
      FormalMarker _ _ => pure Unrooted
      RuntimePart => pure (Chosen AtRunTimeAlways)
      TypeConstructor _ => pure Unrooted
  -- A dictionary delayed, or forced, is that dictionary: a choice's leaves
  -- hold their alternatives lazily.
  rootOf w acc (TDelay _ _ _ t) args = rootOf w acc t args
  rootOf w acc (TForce _ _ t) args = rootOf w acc t args
  -- A function that computes an implementation from what it is given (a
  -- rank-2 dictionary, `\{y} => if y == 0 then loud else quiet`), a value
  -- the program fixes (`Closed.fixing`), given to its callee as written:
  -- where its body applies a definition to its variable, each use gives
  -- one of the implementations that definition's leaves give, the members
  -- of the closed sum the use matches on; where it does not use its
  -- variable, each use gives the one dictionary its body is
  -- (`\_ => __Impl_Eq_Int`). A body applied at its head to anything else
  -- (a projection, the writer's own parameter) gives nothing it names.
  rootOf w acc (Bind _ _ (Lam {}) sc) [] = case getFnArgs (subst unknownPart sc) of
    (Ref _ Func n, as) =>
      if any mentionsUnknown as then givesOf <$> leafRoots w acc n as else do
        ctx <- frozenContext
        let Just a = definitionAddress (gamma (defsOf ctx)) n
          | Nothing => pure Unrooted
        Nothing <- projection n
          | Just _ => pure Unrooted
        givesOf . addresses <$> definitionRoot w acc (Ref EmptyFC Func n) n a as
    _ => pure Unrooted
  rootOf w acc (Erased _ Impossible) _ = pure (Chosen AtRunTimeAlways)
  rootOf w acc _ _ = pure Unrooted

  ||| A definition applied that is no projection, at its root, as the
  ||| translation decides what it is. Of a function type, it gives at each
  ||| use one of the implementations its leaves give, whether the program
  ||| fixes it or the running program chooses it, a closure: its callee is
  ||| given it as it is, and every use matches on it, so it splits nothing;
  ||| a definition given fewer arguments than it takes is walked over
  ||| unknown values for the rest. Of an interface's type, where the program
  ||| fixes it now (`Closed.fixing`), it is itself where its one right-hand
  ||| side builds it, an implementation, whose fields a match reads; one
  ||| that computes it, by matching or by applying another, is one of the
  ||| implementations its leaves give, which a match reads through each.
  ||| Otherwise the running program chooses it, a member of its type's
  ||| choice, which every dispatch on it reads whole; and where what its
  ||| reduction is stuck on mentions the walk's markers, an instance's
  ||| values may fix it after all, and it is there what a fixed one is.
  definitionRoot : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                   (head : ClosedTerm) -> Name -> Address -> List ClosedTerm -> Front Root
  definitionRoot w acc head n a args = do
    ctx <- frozenContext
    let Just (MkInFrozen _ def _) = inFrozen ctx n
      | Nothing => pure (Rooted a)
    ty <- appliedType !(typeOfDefinition def) args
    case ty of
      -- Essential: a value of a function type gives an implementation at
      -- each use; a value of an interface's type is one.
      Bind _ _ (Pi {}) _ => givesOf <$> leafRoots w acc n (args ++ replicate (lacking def) unknownPart)
      _ => case !(fixing ty (applyTo head args)) of
        ChosenAtRunTime on => Chosen <$> settling on def
        FixedNow _ => asRoot <$> fixedAs def
    where
      lacking : GlobalDef -> Nat
      lacking def = case definition def of
        PMDef _ pargs _ => minus (length pargs) (length args)
        _ => 0

      -- What the definition applied is where the program fixes it.
      fixedAs : GlobalDef -> Front FixedRoot
      fixedAs def = case definition def of
        PMDef _ pargs body => do
          Just rhs <- leafOfBody {args = pargs} body
            | Nothing => GivenBy <$> leafRoots w acc n args
          case getFn rhs of
            Ref _ (DataCon _ _) _ => pure (BuiltBy a)
            _ => GivenBy <$> leafRoots w acc n args
        _ => pure (BuiltBy a)

      asRoot : FixedRoot -> Root
      asRoot (BuiltBy j) = Rooted j
      asRoot (GivenBy js) = givesOf js

      -- Essential: a reduction stuck on a value that mentions the walk's
      -- markers is one an instance puts values in for, and one stuck on
      -- anything else, a definition Idris does not prove ends above all,
      -- stays stuck at every instance.
      settledBy : Mention -> GlobalDef -> Front Settling
      settledBy Mentioned def = FixedAt <$> fixedAs def
      settledBy Unmentioned def = pure AtRunTimeAlways

      settling : StuckOn -> GlobalDef -> Front Settling
      settling (OnPartial _) def = pure AtRunTimeAlways
      settling (OnRuntime t) def = settledBy (markersIn t) def
      settling (OnValue t) def = settledBy (markersIn t) def

  ||| The implementations a definition applied gives at the leaves of its
  ||| case tree: every alternative's, since what it matches on is known
  ||| only at run time, each leaf read by its root, a leaf that is a choice
  ||| in turn giving its members. A definition met again on its own
  ||| unfolding gives nothing more.
  leafRoots : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) ->
              Name -> List ClosedTerm -> Front (List Address)
  leafRoots w acc@(Access rec) n args = do
    ctx <- frozenContext
    let Just (MkInFrozen placement def _) = inFrozen ctx n
      | Nothing => pure []
    let PMDef _ pargs body = definition def
      | _ => pure []
    case (bindParams pargs args, enter placement w) of
      (Just (env, extras), Just (Element w' less)) => leaves w' (rec w' less) env !((.fst) <$> caseTreeOf body) extras
      _ => pure []

  ||| The implementations a case tree gives at its leaves, its variables
  ||| standing for what `env` says; a pattern's variables stand for the
  ||| value matched, as a walk of every alternative reads them.
  leaves : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           Values ClosedTerm vs -> CaseTree vs -> List ClosedTerm -> Front (List Address)
  leaves w acc env (STerm _ rhs) extras = do
    addresses <$> rootOf w acc (applyTo (close env rhs) extras) []
  leaves w acc env (Case idx p _ alts) extras = leavesOfAlts w acc env (valueAt env idx p) alts extras
  leaves w acc env (Unmatched _) extras = pure []
  leaves w acc env Impossible extras = pure []

  leavesOfAlts : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                 Values ClosedTerm vs -> ClosedTerm -> List (CaseAlt vs) -> List ClosedTerm -> Front (List Address)
  leavesOfAlts w acc env x [] extras = pure []
  leavesOfAlts w acc env x (ConCase _ _ cargs t :: alts) extras =
    (++) <$> leaves w acc (extend (bindAll cargs x) env) t extras <*> leavesOfAlts w acc env x alts extras
  leavesOfAlts w acc env x (DelayCase _ _ t :: alts) extras =
    (++) <$> leaves w acc (x :: x :: env) t extras <*> leavesOfAlts w acc env x alts extras
  leavesOfAlts w acc env x (ConstCase _ t :: alts) extras =
    (++) <$> leaves w acc env t extras <*> leavesOfAlts w acc env x alts extras
  leavesOfAlts w acc env x (DefaultCase t :: alts) extras =
    (++) <$> leaves w acc env t extras <*> leavesOfAlts w acc env x alts extras

||| What a dictionary is at its root (`rootOf`), never its written head:
||| `snd (MkPair x d)` is d's root. A lambda applied at its head is applied
||| first. The one root function of a dictionary: a request's, a site's and
||| a field's roots are its result.
export
dictionaryRoot : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Front Root
dictionaryRoot t = do
  written <- solved t
  form <- case getFn written of
            Bind {} => lambdasApplied written
            _ => pure written
  rootOf start (sizeAccessible start) form []

||| What a type is at its root, as its normal form (`readNormal`) shows it:
||| the type constructor at its head when it takes more arguments than it
||| is applied to, which is a family's value (`Term`, `Either e`), and only
||| a family's, since a type of kind `Type` is a type constructor applied
||| in full; the writer's family there, applied or not, a marker that no
||| head was given for; or nothing (a lambda, a type, a stuck computation).
formRoot : Context -> ClosedTerm -> Root
formRoot ctx form = case getFnArgs form of
  (Ref _ (TyCon arity) n, args) =>
    if length args < arity then maybe Unrooted Rooted (definitionAddress ctx n) else Unrooted
  (Ref _ Bound n, _) => maybe Unrooted (uncurry Parameter . partDepth) (Template.markerOf n)
  _ => Unrooted

-- A site's type or family read once: its reading (`siteReading`), and
-- its root, off the form that reading read.
typeReading : {auto c : Ref Ctxt Defs} -> List StandIn -> (k : Readings.Static) -> (t : ClosedTerm) -> Front (SiteReading k t, Root)
typeReading stands k t = do
  ctx <- frozenContext
  r <- siteReading stands k t
  pure (r, formRoot (gamma (defsOf ctx)) r.form)

||| A static argument read once at its kind: its reading (`siteReading`),
||| whose template is what a site writes there, and its root, the
||| definition that splits the node it is given to. A dictionary's is the
||| implementation that runs (`dictionaryRoot`). A type's is the type
||| constructor at its head, which only a family's value has (`formRoot`),
||| off the normal form its template reads; a request's type parameter is a
||| type or a family alike, so every type is read for one. A form and a
||| shape split nothing. The one reading of a site's argument and of a
||| request's, so the graph and the requests split a definition by the same
||| heads; the reading itself comes back with the root, so that what a site
||| writes is known to be its template (`Sites.WrittenAs`).
export
rooted : {auto c : Ref Ctxt Defs} -> List StandIn -> (k : Readings.Static) -> (t : ClosedTerm) -> Front (SiteReading k t, Root)
rooted stands AType t = typeReading stands AType t
rooted stands AFamily t = typeReading stands AFamily t
rooted stands AForm t = (, Unrooted) <$> siteReading stands AForm t
rooted stands AShape t = (, Unrooted) <$> siteReading stands AShape t
rooted stands ADictionary t = (,) <$> siteReading stands ADictionary t <*> dictionaryRoot t

||| The head of a choice's type (`ChoiceHead`), its normal form: the arrow
||| of a function type, the type constructor any other applies; for a type
||| headed by neither, a variable or a stuck definition, the head only an
||| instance shows.
export
choiceHeadOf : TT vs -> Front ChoiceHead
choiceHeadOf (Bind _ _ (Pi {}) _) = pure ArrowHead
choiceHeadOf ty = case getFn ty of
  Ref _ (TyCon _) n => do
    ctx <- frozenContext
    pure (maybe UnshownHead InterfaceHead (definitionAddress (gamma (defsOf ctx)) n))
  _ => pure UnshownHead

||| A dictionary read as a callee is given it (`rooted`), where its
||| binder's type is a choice's, of head `k`: where its root says the
||| running program chooses it, a member of that choice, which every
||| dispatch the translation makes on it reads whole, or, where an instance
||| fixes it after all, what is written; any other as it is written, and
||| so is every argument that is no dictionary.
public export
asGiven : Maybe ChoiceHead -> (Template, Root) -> Template
asGiven (Just k) (t, Chosen _) = Choice (Leaf 1) [t, Member k]
asGiven _ (t, _) = t


------------------------------------------------------------------------------
-- An instance's static argument
------------------------------------------------------------------------------

-- What a type is at its root, off its form (`formRoot`).
typeRoot : Frozen -> ClosedTerm -> Front Root
typeRoot ctx form = pure (formRoot (gamma (defsOf ctx)) form)

-- An instance's term read off its normal form, its root read off the form.
normalInstance : {auto c : Ref Ctxt Defs} -> {0 k : Readings.Static} -> (ctx : Frozen) -> (ClosedTerm -> Front Root) ->
                 (t : ClosedTerm) -> Front (InstanceReading ctx k t)
normalInstance ctx rootOfForm t = do
  n <- readNormal EveryRedex ctx t
  r <- readFromStart (InstanceMode ctx) n.reading.readForm
  root <- rootOfForm n.reading.readForm
  pure (MkInstanceReading n.reading.readForm (FromNormalForm n.reading) n.maximal r.fst r.snd root)

-- A form and a shape split nothing.
noRoot : ClosedTerm -> Front Root
noRoot _ = pure Unrooted

||| An instance's static argument at its kind, read once: the form its key
||| writes, which is the form a site's reading of the same kind reads
||| (`siteReading`), so that one family is one key whatever stands for it
||| (itself, or a lambda that applies it); the template it reads as, every
||| node and every call as written, which is its key; and its root, the
||| definition that splits the node it is given to (`rooted`).
export
readInstance : {auto c : Ref Ctxt Defs} -> (ctx : Frozen) -> (k : Readings.Static) -> (t : ClosedTerm) ->
               Front (InstanceReading ctx k t)
readInstance ctx AType t = normalInstance ctx (typeRoot ctx) t
readInstance ctx AFamily t = normalInstance ctx (typeRoot ctx) t
readInstance ctx AForm t = normalInstance ctx noRoot t
readInstance ctx ADictionary t = do
  d <- dictionaryForm ctx t
  r <- readFromStart (InstanceMode ctx) d.form
  root <- dictionaryRoot t
  pure (MkInstanceReading d.form d.formFrom d.maximal r.fst r.snd root)
readInstance ctx AShape t = do
  s <- solving ctx t
  case getFnArgs s.fst of
    (Ref _ (DataCon _ _) _, _) => do
      let c = contracted s.fst
      r <- readFromStart (InstanceMode ctx) c.etaForm
      pure (MkInstanceReading c.etaForm (FromWritten WrittenShape s.snd c.etaSteps) c.etaNormal r.fst r.snd Unrooted)
    _ => normalInstance ctx noRoot t

-- What the translation keeps of an instance's reading: the reading itself,
-- at quantity 0, and what it reads of it, each the reading's by type.
keptReading : InstanceReading ctx k t -> StaticReading
keptReading r = MkStaticReading r r.form Refl (readingHeight r) Refl (splitting r.root) Refl

||| A dictionary given as a request's static argument, as the translation
||| keeps it (`State.DictionaryReading`): its reading (`readInstance`), and
||| what the reading's form reduces to at its head (`Closed.reducedOf`),
||| reduced once here, so that whether the program fixes it is decided off
||| that at each parameter it is given at (`Closed.fixedAt`) and the form
||| is reduced nowhere else. Read once, by its written key, as every static
||| argument is (`staticReading`).
export
dictionaryReading : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> ClosedTerm -> Front DictionaryReading
dictionaryReading t = do
  writer <- writerOf [t]
  let written = writtenOf writer t
  case lookupFact (.dictionaries) written !(getState) of
    Just d => pure d
    Nothing => do
      ctx <- frozenContext
      r <- readInstance ctx ADictionary t
      reduct <- reducedOf r.form
      let here = MkDictionaryReading (keptReading r) Refl reduct
      updateState (derive { dictionaries $= insert written here })
      pure here

||| An implementation built around one the program fixes, as a kind holds it
||| (`State.FixedDictionary`): its reading, read once by its written key as
||| every static argument is, and the value it reduces to at its head, which
||| its builder built beside it (`Choices.heldMember`, `Cases.heldHere`), so
||| nothing reduces it. A form read before keeps the reading it had; one read
||| first here is kept with that value as what it reduces to.
export
builtDictionary : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> ClosedTerm -> FixedValue -> Front FixedDictionary
builtDictionary t v = do
  writer <- writerOf [t]
  let written = writtenOf writer t
  case lookupFact (.dictionaries) written !(getState) of
    Just d => pure (MkFixedDictionary t d.asStatic d.ofDictionary v)
    Nothing => do
      ctx <- frozenContext
      r <- readInstance ctx ADictionary t
      let here = MkDictionaryReading (keptReading r) Refl (ReducesTo v)
      updateState (derive { dictionaries $= insert written here })
      pure (MkFixedDictionary t here.asStatic here.ofDictionary v)

||| A request's static argument at its kind, as the translation keeps it:
||| the reading itself (`readInstance`), kept at quantity 0 beside what the
||| translation reads of it, the form its link writes, its height and the
||| head that splits its node, each the reading's by type
||| (`State.StaticReading`); a dictionary's with what its form reduces to
||| (`dictionaryReading`). The same argument is given to many requests,
||| so it is read once, by its kind and its written key, and a step's
||| readings are merged into the instance table with the rest of what it
||| derived; a later request given it holds the reading read the first
||| time, never another.
export
staticReading : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Readings.Static -> ClosedTerm -> Front StaticReading
staticReading ADictionary t = do
  d <- dictionaryReading t
  pure d.asStatic
staticReading kind t = do
  writer <- writerOf [t]
  let written = writtenOf writer t
  case lookupFact (.readings) (kind, written) !(getState) of
    Just r => pure r
    Nothing => do
      ctx <- frozenContext
      r <- readInstance ctx kind t
      let here = keptReading r
      updateState (derive { readings $= insert (kind, written) here })
      pure here

------------------------------------------------------------------------------
-- A key is never larger than its instance's reading
------------------------------------------------------------------------------

-- An instance's reading describes its term as its key writes it
-- (`InstanceMode`), so the key, read as a tree of its heads
-- (`Keys.keyTree`), is no taller, no wider and no heavier than the
-- template: each node of the tree is within a node of the template, which
-- holds each of its children within a child of its own. So the key weighs
-- no more than the universe lets a key of the template's measures weigh
-- (`keyedWithin`), the bound each request's argument carries.

-- Base states only that `maximum` is above both arguments; the bounds below
-- need that it is the least such.
0 maxLub : {a, c : Nat} -> LTE a b -> LTE c b -> LTE (maximum a c) b
maxLub {a = Z} _ lc = lc
maxLub {a = S _} {c = Z} la _ = la
maxLub {a = S a} {c = S c} (LTESucc la) (LTESucc lc) = LTESucc (maxLub la lc)

0 maxMono : {a, a', c, c' : Nat} -> LTE a a' -> LTE c c' -> LTE (maximum a c) (maximum a' c')
maxMono la lc = maxLub (transitive la (maximumLeftUpperBound _ _)) (transitive lc (maximumRightUpperBound _ _))

0 lteOfEq : a = b -> LTE b c -> LTE a c
lteOfEq Refl le = le

0 lteToEq : b = c -> LTE a b -> LTE a c
lteToEq Refl le = le

0 underOne : (n : Nat) -> LTE (n + 0) (S n)
underOne n = lteSuccRight (lteOfEq (plusZeroRightNeutral n) reflexive)

0 elemLeft : Elem x xs -> Elem x (xs ++ ys)
elemLeft Here = Here
elemLeft (There e) = There (elemLeft e)

0 elemRight : (xs : List a) -> Elem x ys -> Elem x (xs ++ ys)
elemRight [] e = e
elemRight (_ :: xs) e = There (elemRight xs e)

0 lengthJoin : (xs, ys : List a) -> length (xs ++ ys) = length xs + length ys
lengthJoin [] ys = Refl
lengthJoin (_ :: xs) ys = cong S (lengthJoin xs ys)

||| A key tree applied to more arguments, each one more child of its node,
||| as the key writes an application.
public export
0 appliedTo : KeyTree -> List KeyTree -> KeyTree
appliedTo t [] = t
appliedTo t (k :: ks) = appliedTo (addChild t k) ks

-- Children added one at a time, the last first.
0 onto : List KeyTree -> List KeyTree -> List KeyTree
onto cs [] = cs
onto cs (k :: ks) = onto (k :: cs) ks

0 appliedNode : (x : Nat) -> (cs, ks : List KeyTree) -> appliedTo (KeyNode x cs) ks = KeyNode x (onto cs ks)
appliedNode x cs [] = Refl
appliedNode x cs (k :: ks) = appliedNode x (k :: cs) ks

0 allOnto : {0 p : KeyTree -> Type} -> All p cs -> All p ks -> All p (onto cs ks)
allOnto pcs [] = pcs
allOnto pcs (pk :: pks) = allOnto (pk :: pcs) pks

0 lengthOnto : (cs, ks : List KeyTree) -> length (onto cs ks) = length ks + length cs
lengthOnto cs [] = Refl
lengthOnto cs (k :: ks) = trans (lengthOnto (k :: cs) ks) (sym (plusSuccRightSucc (length ks) (length cs)))

||| A key tree no taller, no wider and no heavier than a template, as
||| `sizeWithin` measures both: a widest node or a heaviest symbol of one
||| counts as none, as the universe counts them.
public export
record Enclosed (k : KeyTree) (t : Template) where
  constructor MkEnclosed
  0 high : LTE (keyHeight k) (height t)
  0 wide : LTE (keyArity k) (maximum 1 (arity t))
  0 heavy : LTE (keyHeaviest k) (maximum 1 (heaviest t))

-- A key tree within one of some templates.
0 InSome : List Template -> KeyTree -> Type
InSome ts k = (t : Template ** (Elem t ts, Enclosed k t))

0 tallestAt : Elem t ts -> LTE (height t) (tallest ts)
tallestAt Here = maximumLeftUpperBound _ _
tallestAt (There el) = transitive (tallestAt el) (maximumRightUpperBound _ _)

0 widestAt : Elem t ts -> LTE (arity t) (widest ts)
widestAt Here = maximumLeftUpperBound _ _
widestAt (There el) = transitive (widestAt el) (maximumRightUpperBound _ _)

0 heaviestAt : Elem t ts -> LTE (heaviest t) (heaviestOf ts)
heaviestAt Here = maximumLeftUpperBound _ _
heaviestAt (There el) = transitive (heaviestAt el) (maximumRightUpperBound _ _)

0 allTall : All (InSome ts) cs -> LTE (keyTallest cs) (tallest ts)
allTall [] = LTEZero
allTall ((t ** (el, wi)) :: rest) = maxLub (transitive wi.high (tallestAt el)) (allTall rest)

0 allWide : All (InSome ts) cs -> LTE (keyWidest cs) (maximum 1 (widest ts))
allWide [] = LTEZero
allWide ((t ** (el, wi)) :: rest) = maxLub (transitive wi.wide (maxMono reflexive (widestAt el))) (allWide rest)

0 allHeavy : All (InSome ts) cs -> LTE (keyHeaviestOf cs) (maximum 1 (heaviestOf ts))
allHeavy [] = LTEZero
allHeavy ((t ** (el, wi)) :: rest) = maxLub (transitive wi.heavy (maxMono reflexive (heaviestAt el))) (allHeavy rest)

-- A node of the key within a head of the template: each child within one
-- of the head's children, no more children, its own symbol no heavier.
0 nodeWithin : {x : Nat} -> {cs : List KeyTree} -> {ts : List Template} -> {a : Maybe Address} ->
               All (InSome ts) cs -> LTE (length cs) (length ts) -> LTE x (maximum 1 (heaviestOf ts)) ->
               Enclosed (KeyNode x cs) (Head a ts)
nodeWithin inside many heavy =
  MkEnclosed (LTESucc (allTall inside))
           (maxLub (transitive many (transitive (maximumLeftUpperBound _ _) (maximumRightUpperBound 1 _)))
                   (transitive (allWide inside) (maxMono reflexive (maximumRightUpperBound _ _))))
           (maxLub heavy (allHeavy inside))

-- Key trees each within its template, in order.
data Pairwise : List KeyTree -> List Template -> Type where
  NoPairs : Pairwise [] []
  Paired : Enclosed k t -> Pairwise ks ts -> Pairwise (k :: ks) (t :: ts)

0 pairwiseLength : Pairwise ks ts -> length ks = length ts
pairwiseLength NoPairs = Refl
pairwiseLength (Paired _ ps) = cong S (pairwiseLength ps)

0 pairwiseIn : Pairwise ks ts -> ((t : Template) -> Elem t ts -> Elem t big) -> All (InSome big) ks
pairwiseIn NoPairs inc = []
pairwiseIn (Paired {t} w ps) inc = (t ** (inc t Here, w)) :: pairwiseIn ps (\u, el => inc u (There el))

0 widen : All (InSome ts) cs -> ((t : Template) -> Elem t ts -> Elem t big) -> All (InSome big) cs
widen [] inc = []
widen ((t ** (el, w)) :: rest) inc = (t ** (inc t el, w)) :: widen rest inc

0 ontoLength : (cs : List KeyTree) -> {ks : List KeyTree} -> Pairwise ks ts -> length (onto cs ks) = length ts + length cs
ontoLength cs ps = trans (lengthOnto cs ks) (cong (+ length cs) (pairwiseLength ps))

-- A one-node key within a template one high.
0 oneNode : (t : Template) -> LTE 1 (height t) -> Enclosed (KeyNode 1 []) t
oneNode t high = MkEnclosed high LTEZero (maximumLeftUpperBound 1 (heaviest t))

0 substituteOwn : (s : Substitute) -> Enclosed (KeyNode 1 []) (substituteTemplate s)
substituteOwn (FormalArgument j k) = oneNode (Formal j k) reflexive
substituteOwn Placeholding = oneNode (Leaf 1) reflexive

0 tokenOwn : (n : Nat) -> Enclosed (KeyNode n []) (Token n)
tokenOwn n = MkEnclosed reflexive LTEZero (maxLub (maximumRightUpperBound 1 n) LTEZero)

0 holeOwn : (i : Nat) -> Enclosed (KeyNode (S i + 0) []) (Token (S i))
holeOwn i = MkEnclosed reflexive LTEZero (LTESucc (lteOfEq (plusZeroRightNeutral i) reflexive))

-- A key's node read with another head, the same node.
0 headChanged : {k, k' : KeyTree} -> k = k' -> Enclosed (appliedTo k' ks) t -> Enclosed (appliedTo k ks) t
headChanged Refl wi = wi

-- A part that is no head of its own, applied: alone, its own node; applied,
-- a head above it and its arguments, which holds the key's node.
0 partWithin : {x : Nat} -> {own : Template} -> {ks : List KeyTree} -> {ts : List Template} ->
               Enclosed (KeyNode x []) own -> Pairwise ks ts ->
               Enclosed (appliedTo (KeyNode x []) ks) (partOf EveryNode own ts)
partWithin w NoPairs = w
partWithin {x} {own} {ks = k :: ks'} {ts = u :: us} w (Paired first rest) =
  replace {p = \kt => Enclosed kt (Head Nothing (own :: u :: us))} (sym (appliedNode x [] (k :: ks'))) $
    nodeWithin (allOnto [] (pairwiseIn (Paired first rest) (\_, el => There el)))
               (lteOfEq (ontoLength [] (Paired first rest)) (LTESucc (underOne (length us))))
               (transitive (maximumLeftUpperBound x 0) (transitive w.heavy (maxMono reflexive (maximumLeftUpperBound _ _))))

-- A node with parts of its own, applied: one head over its parts and its
-- arguments, as the key writes it.
0 splicedWithin : {x : Nat} -> {own : List KeyTree} -> {ownT : List Template} -> {ks : List KeyTree} ->
                  {ts : List Template} -> {a : Maybe Address} ->
                  All (InSome ownT) own -> LTE (length own) (length ownT) -> LTE x 1 -> Pairwise ks ts ->
                  Enclosed (appliedTo (KeyNode x own) ks) (Head a (ownT ++ ts))
splicedWithin {x} {own} {ownT} {ks} {ts} {a} inOwn many one ps =
  replace {p = \kt => Enclosed kt (Head a (ownT ++ ts))} (sym (appliedNode x own ks)) $
    nodeWithin (allOnto (widen inOwn (\_, el => elemLeft {ys = ts} el)) (pairwiseIn ps (\_, el => elemRight {ys = ts} ownT el)))
               (lteOfEq (ontoLength own ps)
                  (lteOfEq (plusCommutative (length ts) (length own))
                     (lteToEq (sym (lengthJoin ownT ts)) (plusLteMonotoneRight (length ts) (length own) (length ownT) many))))
               (transitive one (maximumLeftUpperBound 1 _))

0 glyphsIn : (cs : List Char) -> ((t : Template) -> Elem t (spelt cs) -> Elem t big) -> All (InSome big) (glyphTrees cs)
glyphsIn [] inc = []
glyphsIn (_ :: cs) inc = (Leaf 1 ** (inc (Leaf 1) Here, oneNode (Leaf 1) reflexive)) :: glyphsIn cs (\t, el => inc t (There el))

0 glyphsLength : (cs : List Char) -> length (glyphTrees cs) = length (spelt cs)
glyphsLength [] = Refl
glyphsLength (_ :: cs) = cong S (glyphsLength cs)

0 spellWithin : (cs : List Char) -> {ks : List KeyTree} -> {ts : List Template} -> Pairwise ks ts ->
                Enclosed (appliedTo (KeyNode 1 (glyphTrees cs)) ks) (Head Nothing (spelt cs ++ ts))
spellWithin cs ps = splicedWithin {ownT = spelt cs} (glyphsIn cs (\_, el => el)) (lteOfEq (glyphsLength cs) reflexive) reflexive ps

0 constantWithin : (c : Constant) -> {ks : List KeyTree} -> {ts : List Template} -> Pairwise ks ts ->
                   Enclosed (appliedTo (constantTree c) ks) (appliedConstant c ts)
constantWithin (Str x) ps = spellWithin (unpack x) ps
constantWithin (Db x) ps = spellWithin (unpack (show x)) ps
constantWithin (Ch x) ps = partWithin (oneNode (Leaf 1) reflexive) ps
constantWithin (PrT x) ps = partWithin (oneNode (Leaf 1) reflexive) ps
constantWithin WorldVal ps = partWithin (oneNode (Leaf 1) reflexive) ps
constantWithin (I x) ps = partWithin (tokenOwn _) ps
constantWithin (I8 x) ps = partWithin (tokenOwn _) ps
constantWithin (I16 x) ps = partWithin (tokenOwn _) ps
constantWithin (I32 x) ps = partWithin (tokenOwn _) ps
constantWithin (I64 x) ps = partWithin (tokenOwn _) ps
constantWithin (BI x) ps = partWithin (tokenOwn _) ps
constantWithin (B8 x) ps = partWithin (tokenOwn _) ps
constantWithin (B16 x) ps = partWithin (tokenOwn _) ps
constantWithin (B32 x) ps = partWithin (tokenOwn _) ps
constantWithin (B64 x) ps = partWithin (tokenOwn _) ps

-- A run of n successors is n + 1 high, every node of it with one child
-- at most, every symbol of it weighing one.
0 runWithin : (w : Writer) -> Run u n -> Enclosed (keyTree w u) (Leaf (S n))
runWithin w RunZero = MkEnclosed reflexive LTEZero reflexive
runWithin w (RunSucc r) =
  let rec = runWithin w r in
  MkEnclosed (LTESucc (maxLub rec.high LTEZero))
           (maxLub reflexive (maxLub rec.wide LTEZero))
           (maxLub reflexive (maxLub rec.heavy LTEZero))

-- A node's own children, each within one of its own templates, no more of
-- them.
record Own (cs : List KeyTree) (ts : List Template) where
  constructor MkOwn
  0 inside : All (InSome ts) cs
  0 many : LTE (length cs) (length ts)

mutual
  ||| An instance's key, read as a tree of its heads, is within the
  ||| template its reading reads it as.
  export
  0 readWithin : (w : Writer) -> ReadAs (InstanceMode ctx) env u t -> Enclosed (keyTree w u) t
  readWithin w (ARun r) = runWithin w r
  readWithin w (ASpine s) = spineWithin w s

  0 allWithin : (w : Writer) -> AllReadAs (InstanceMode ctx) env as ts -> Pairwise (keyTrees w as) ts
  allWithin w [] = NoPairs
  allWithin w (r :: rs) = Paired (readWithin w r) (allWithin w rs)

  0 spineWithin : (w : Writer) -> SpineAs (InstanceMode ctx) env f as t -> Enclosed (appliedTo (keyTree w f) (keyTrees w as)) t
  spineWithin w (SApp s) = spineWithin w s
  spineWithin w (SDot {r} ru rs) = splicedWithin {ownT = [r]} [(r ** (Here, readWithin w ru))] reflexive reflexive (allWithin w rs)
  spineWithin w (SPlaceholder rs) = partWithin (oneNode (Leaf 1) reflexive) (allWithin w rs)
  spineWithin w (SImpossible rs) = partWithin (oneNode (Leaf 1) reflexive) (allWithin w rs)
  spineWithin {env} w (SLocal {idx} {p} rs) = partWithin (substituteOwn (valueAt env idx p)) (allWithin w rs)
  spineWithin w (SMeta {ms = own} dms rs) =
    let pms = allWithin w dms in
    splicedWithin {ownT = own} (pairwiseIn pms (\_, el => el)) (lteOfEq (pairwiseLength pms) reflexive) reflexive (allWithin w rs)
  spineWithin w (SUniverse rs) = partWithin (oneNode (Leaf 1) reflexive) (allWithin w rs)
  spineWithin w (SConstant {c} rs) = constantWithin c (allWithin w rs)
  spineWithin w (SLambda {ps} {t} {s} pa rt rsc rs) =
    let o = passingWithin w pa in
    splicedWithin {ownT = ps ++ [t, s]}
                  ((s ** (elemRight {ys = [t, s]} ps (There Here), readWithin w rsc)) ::
                   widen o.inside (\_, el => elemLeft {ys = [t, s]} el))
                  (lteToEq (sym (lengthJoin ps [t, s]))
                     (lteToEq (plusCommutative 2 (length ps)) (lteSuccRight (LTESucc o.many))))
                  reflexive (allWithin w rs)
  spineWithin w (SBinder {ps} {s} ba rsc rs) =
    let o = binderWithin w ba in
    splicedWithin {ownT = ps ++ [s]}
                  ((s ** (elemRight {ys = [s]} ps Here, readWithin w rsc)) :: widen o.inside (\_, el => elemLeft {ys = [s]} el))
                  (lteToEq (sym (lengthJoin ps [s])) (lteToEq (plusCommutative 1 (length ps)) (LTESucc o.many)))
                  reflexive (allWithin w rs)
  spineWithin w (SDelayed {t} ru rs) = splicedWithin {ownT = [t]} [(t ** (Here, readWithin w ru))] reflexive reflexive (allWithin w rs)
  spineWithin w (SDelay {t} {v} rty ra rs) =
    splicedWithin {ownT = [t, v]} [(t ** (Here, readWithin w rty)), (v ** (There Here, readWithin w ra))] reflexive reflexive (allWithin w rs)
  spineWithin w (SForce {t} ru rs) = splicedWithin {ownT = [t]} [(t ** (Here, readWithin w ru))] reflexive reflexive (allWithin w rs)
  spineWithin w (SAs {t} {v} ra rp rs) =
    splicedWithin {ownT = [t, v]} [(t ** (Here, readWithin w ra)), (v ** (There Here, readWithin w rp))] reflexive reflexive (allWithin w rs)
  spineWithin w (SHole {fc} {n} {i} found rs) =
    headChanged (markerNode w fc n found) (partWithin (holeOwn i) (allWithin w rs))
  spineWithin w (SFormal {fc} {n} {j} {k} none _ rs) =
    headChanged (unmarkedNode w fc n none) (partWithin (oneNode (Formal j k) reflexive) (allWithin w rs))
  spineWithin w (SPart {fc} {n} none _ rs) =
    headChanged (unmarkedNode w fc n none) (partWithin (oneNode (Leaf 1) reflexive) (allWithin w rs))
  spineWithin w (SNoDefinition _ rs) = partWithin (oneNode (Leaf 1) reflexive) (allWithin w rs)
  spineWithin w (SData _ rs) = splicedWithin {ownT = []} [] LTEZero reflexive (allWithin w rs)
  spineWithin w (STypeCon _ rs) = splicedWithin {ownT = []} [] LTEZero reflexive (allWithin w rs)
  spineWithin w (SKept _ rs) = splicedWithin {ownT = []} [] LTEZero reflexive (allWithin w rs)
  -- A site's markers and unfoldings: no instance's term holds them.
  spineWithin w (SMarker _ _) impossible
  spineWithin w (SBeside _ _ _) impossible
  spineWithin w (SProjected _ _ _ _) impossible
  spineWithin w (SRecurs _ _) impossible
  spineWithin w (SWalked _ _ _) impossible
  spineWithin w (SEta _ _) impossible
  spineWithin w (SBelieved _ _ _ _) impossible

  0 passingWithin : (w : Writer) -> PassingAs (InstanceMode ctx) env info ps -> Own (passingTrees w info) ps
  passingWithin w PImplicit = MkOwn [] LTEZero
  passingWithin w PExplicit = MkOwn [] LTEZero
  passingWithin w PAuto = MkOwn [] LTEZero
  passingWithin w (PDefault {r} rd) = MkOwn [(r ** (Here, readWithin w rd))] reflexive

  0 binderWithin : (w : Writer) -> BinderAs (InstanceMode ctx) env b ps -> Own (binderTrees w b) ps
  binderWithin w (BLet {tv} {t} rv rt) =
    MkOwn [(tv ** (Here, readWithin w rv)), (t ** (There Here, readWithin w rt))] reflexive
  binderWithin w (BPi {ps} {t} pa rt) =
    let o = passingWithin w pa in
    MkOwn ((t ** (elemRight {ys = [t]} ps Here, readWithin w rt)) :: widen o.inside (\_, el => elemLeft {ys = [t]} el))
          (lteToEq (sym (lengthJoin ps [t])) (lteToEq (plusCommutative 1 (length ps)) (LTESucc o.many)))
  binderWithin w (BPVar {ps} {t} pa rt) =
    let o = passingWithin w pa in
    MkOwn ((t ** (elemRight {ys = [t]} ps Here, readWithin w rt)) :: widen o.inside (\_, el => elemLeft {ys = [t]} el))
          (lteToEq (sym (lengthJoin ps [t])) (lteToEq (plusCommutative 1 (length ps)) (LTESucc o.many)))
  binderWithin w (BPLet {tv} {t} rv rt) =
    MkOwn [(tv ** (Here, readWithin w rv)), (t ** (There Here, readWithin w rt))] reflexive
  binderWithin w (BPVTy {t} rt) = MkOwn [(t ** (Here, readWithin w rt))] reflexive

0 maxOnePred : (a : Nat) -> pred (maximum 1 a) = pred a
maxOnePred Z = Refl
maxOnePred (S k) = Refl

-- The universe counts a widest node of one as none.
0 sizeWithinOne : (a, h, e : Nat) -> sizeWithin (maximum 1 a) h e = sizeWithin a h e
sizeWithinOne a h e = cong (\q => (2 * h + e) * nodesWithin (S q) h) (maxOnePred a)

||| An instance's key weighs no more than the universe lets a key weigh at
||| any measures at least its reading's: its template's widest node, height
||| and heaviest token. What a request carries for an argument
||| (`Proof.Derivation.ArgumentDerivation`'s `keyed`) is this, at the
||| universe's arity and heaviest token and the argument's reading.
export
0 keyedWithin : (w : Writer) -> (r : InstanceReading ctx k t) -> {a, h, e : Nat} ->
                LTE (arity r.template) a -> LTE (height r.template) h -> LTE (heaviest r.template) e ->
                LTE (writtenOf w r.form).size (sizeWithin a h e)
keyedWithin w r wide high heavy =
  let wi = readWithin w r.describes in
  transitive (lteToEq (sizeWithinOne (arity r.template) (height r.template) (heaviest r.template))
                      (writtenWithin w r.form {a = maximum 1 (arity r.template)} {h = height r.template}
                                     {e = heaviest r.template} wi.high wi.wide wi.heavy))
             (sizeWithinMono wide high heavy)

------------------------------------------------------------------------------
-- A capped argument's reading
------------------------------------------------------------------------------

||| A chain's shape as a capped parameter's key holds it in a frozen
||| context, h high: a constructor applied to nothing, or to the shape of
||| its predecessor, or a part the shape does not say (a cut, an erased
||| part, a runtime part, or what is not known of a runtime value, a name
||| the context defines as nothing), which is never a value an
||| implementation closes over. A chain's constructors take no erased
||| argument (`Natness.Chain`), so a key cut from a chain's skeleton
||| (`Closed.skeleton`, `Closed.cutShape`) is one.
public export
data ChainShape : Frozen -> TT vs -> Nat -> Type where
  ChainEnd : ChainShape ctx (Ref fc (DataCon tag arity) n) 1
  ChainStep : ChainShape ctx a h -> ChainShape ctx (App fc (Ref rfc (DataCon tag arity) n) a) (S h)
  ChainCut : ChainShape ctx (Erased fc Impossible) 1
  ChainErased : ChainShape ctx (Erased fc Placeholder) 1
  ChainUnsaid : (0 _ : Readings.markerOf n = Nothing) -> ChainShape ctx (Ref fc Bound n) 1
  ChainUnknown : (0 _ : (d : GlobalDef) -> Not (Defines ctx n d)) -> ChainShape ctx (Ref fc Func n) 1

||| What a capped position holds of a value (`Proof.Bound.Capped`), at a
||| shape h high: no node with more than one child, no token, and no higher
||| than the shape.
public export
record CapRead (t : Template) (h : Nat) where
  constructor MkCapRead
  0 high : LTE (height t) h
  0 narrow : LTE (arity t) 1
  0 light : LTE (heaviest t) 0

0 nothingNotJust : Nothing = Just x -> Void
nothingNotJust Refl impossible

-- A closed run is a chain one longer than its successors.
0 runShaped : Run u n -> ChainShape ctx u h -> h = S n
runShaped RunZero ChainEnd = Refl
runShaped (RunSucc r) (ChainStep c) = cong S (runShaped r c)

mutual
  ||| A chain's shape, read as an instance's term, is what a capped
  ||| position holds of a value as high as the shape: so a capped request's
  ||| reading meets every premise of `Capped` but its height against the
  ||| cap, which is the cap's argument (`Caps.capFrom`).
  export
  0 chainReads : ChainShape cx u h -> ReadAs (InstanceMode ctx) env u t -> CapRead t h
  chainReads c (ARun {n} r) = replace {p = CapRead (Leaf (S n))} (sym (runShaped r c)) (MkCapRead reflexive LTEZero LTEZero)
  chainReads c (ASpine s) = chainSpine c s

  0 chainSpine : ChainShape cx u h -> SpineAs (InstanceMode ctx) env u [] t -> CapRead t h
  chainSpine ChainEnd (SData _ []) = MkCapRead reflexive LTEZero LTEZero
  chainSpine (ChainStep c) (SApp (SData _ (r :: []))) =
    let inner = chainReads c r in
    MkCapRead (LTESucc (maxLub inner.high LTEZero))
              (maxLub reflexive (maxLub inner.narrow LTEZero))
              (maxLub inner.light LTEZero)
  chainSpine ChainCut (SImpossible []) = MkCapRead reflexive LTEZero LTEZero
  chainSpine ChainErased (SPlaceholder []) = MkCapRead reflexive LTEZero LTEZero
  chainSpine (ChainUnsaid none) (SHole found _) = void (nothingNotJust (trans (sym none) found))
  chainSpine (ChainUnsaid none) (SFormal _ _ []) = MkCapRead reflexive LTEZero LTEZero
  chainSpine (ChainUnsaid none) (SPart _ _ []) = MkCapRead reflexive LTEZero LTEZero
  chainSpine (ChainUnknown _) (SNoDefinition _ []) = MkCapRead reflexive LTEZero LTEZero
  chainSpine (ChainUnknown _) (SKept _ []) = MkCapRead reflexive LTEZero LTEZero

||| A chain's shape reduces only to a chain's shape as high: a constructor
||| and a bound name are inert (`Proof.Inversion.inertAlone`,
||| `Proof.Inversion.inertOne`), an erased part no dot holds and a name the
||| context defines as nothing take no step (`Proof.Inversion`), so each
||| reduces to itself over what its predecessor reduces to.
export
0 chainReduces : {0 ev : Evaluation} -> ChainShape ctx u h -> Reduces ev ctx u v -> ChainShape ctx v h
chainReduces ChainEnd r = case inertAlone InertData r of
  (_ ** same) => rewrite same in ChainEnd
chainReduces (ChainStep c) r = case inertOne InertData r of
  (_ ** _ ** _ ** (same, ra)) => rewrite same in ChainStep (chainReduces c ra)
chainReduces ChainCut r = case erasedReduces IsImpossible r of
  (_ ** same) => rewrite same in ChainCut
chainReduces ChainErased r = case erasedReduces IsPlaceholder r of
  (_ ** same) => rewrite same in ChainErased
chainReduces (ChainUnsaid none) r = case inertAlone InertBound r of
  (_ ** same) => rewrite same in ChainUnsaid none
chainReduces (ChainUnknown nowhere) r = case inertAlone (InertUndefined nowhere) r of
  (_ ** same) => rewrite same in ChainUnknown nowhere

-- Contraction rewrites no reference.
0 referenceKept : EtaContracts (Ref fc nt n) v -> v = Ref fc nt n
referenceKept EtaSame = Refl

||| Contraction keeps a chain's shape: it holds no lambda.
export
0 chainContracted : ChainShape ctx u h -> EtaContracts u v -> v = u
chainContracted _ EtaSame = Refl
chainContracted (ChainStep c) (EtaApp cf ca) = rewrite referenceKept cf in rewrite chainContracted c ca in Refl

||| What a reader reads off a chain's shape is a chain's shape as high:
||| the host's steps reach only one (`chainReduces`), contraction keeps it
||| (`chainContracted`), and a shape is never read off an implementation.
export
0 shapeForm : ChainShape ctx t h -> FormFrom AShape ctx t u -> ChainShape ctx u h
shapeForm c (FromNormalForm r) =
  rewrite chainContracted (chainReduces c r.reduct.steps) r.contraction in chainReduces c r.reduct.steps
shapeForm c (FromWritten _ solving k) =
  rewrite chainContracted (chainReduces c (solvedSteps solving)) k in chainReduces c (solvedSteps solving)

||| What the cut of a capped parameter's argument gives the request that
||| keys by it (`Instances.neededShape`, `Closed.cutShape`): the shape it
||| keeps, a chain's shape in the frozen context, as high as `keptHeight`,
||| no taller than the cap of the position the argument lands at. A cap
||| applies where `Caps.capOf` gives one: a parameter keyed by its
||| argument's shape, of a chain's type (`Natness.Chain`), whose callee's
||| type inspects it to a depth one below the cap (`Caps.capFrom`); the cut
||| keeps the shape to the least depth at which the type stops needing it,
||| or whole where the type is stuck on a hole, which a chain's shape has
||| only at its end.
public export
record CutWithin (ctx : Frozen) (cap : Nat) (t : ClosedTerm) where
  constructor MkCutWithin
  0 keptHeight : Nat
  0 chain : ChainShape ctx t keptHeight
  0 short : LTE keptHeight cap

||| A capped request's argument, the shape its cut kept, derived: its
||| instance's reading reads a chain's shape (`shapeForm`, `chainReads`), so
||| it is a value the capped position holds (`Proof.Bound.Capped`), no
||| taller than the cap, and its key weighs no more than its reading lets
||| a key weigh (`keyedWithin`).
public export
0 cappedDerivation : {g : Graph} -> {m : Model g} -> (b : Bounds) -> (w : Writer) -> (p : Fin g.size) ->
                     index p g.caps = Just c -> CutWithin ctx c t -> (r : InstanceReading ctx AShape t) ->
                     ArgumentDerivation m b (writtenOf w r.form).size
cappedDerivation b w p cap cut r =
  let held = chainReads (shapeForm cut.chain r.formFrom) r.describes in
  MkArgumentDerivation p r.template (Capped cap (transitive held.high cut.short) held.narrow held.light)
    (keyedWithin w r reflexive reflexive reflexive)

||| A capped request's argument placed in the universe at its parameter's
||| height h, where its position's bound is within h, which every
||| parameter's position is (`Growth.positionWithin`).
export
0 cappedPlaced : {g : Graph} -> {m : Model g} -> {pot : Vect g.size Nat} -> (b : Bounds) -> (w : Writer) -> (p : Fin g.size) ->
                 index p g.caps = Just c -> CutWithin ctx c t -> (r : InstanceReading ctx AShape t) ->
                 LTE (bound g pot p) h -> ArgumentWithin m pot b (Just (writtenOf w r.form)) h
cappedPlaced b w p cap cut r under = Keyed (cappedDerivation b w p cap cut r) under

||| A capped request's argument is no taller than its cap: its reading,
||| whose key is never taller (`readWithin`), is a chain's shape as high as
||| the cut kept.
export
0 cappedKeyHeight : (w : Writer) -> CutWithin ctx c t -> (r : InstanceReading ctx AShape t) ->
                    LTE (keyHeight (keyTree w r.form)) c
cappedKeyHeight w cut r =
  transitive (readWithin w r.describes).high
             (transitive (chainReads (shapeForm cut.chain r.formFrom) r.describes).high cut.short)

------------------------------------------------------------------------------
-- The reading lemma's statement
------------------------------------------------------------------------------

||| What an instance puts in for a site's markers, as the reading lemma
||| takes it: for the marker each variable of the markers' scope stands for,
||| read as the writer's `Var i d`, the value put in, read as an instance's
||| term, is another reading (`Proof.Bound.Reread`) of a part d deep of a
||| value of V at a position the site's writer reads parameter i at.
public export
0 MarkersHold : {g : Graph} -> Model g -> Bound.Site g.size -> Frozen -> List StandIn -> Bounds ns -> SubstEnv ns [] -> Type
MarkersHold {g} m s ctx stands bs vs =
  (x : Var ns) -> (i, d : Nat) -> walkMarker stands (replacedAt bs x) = Just (Template.Var i d) ->
  (u : Template) -> ReadAs (InstanceMode ctx) [] (Var.index vs x) u ->
  (p : Fin g.size ** v : Template ** u' : Template ** (Elem (i, p) s.writers, InV m p v, Sub d v u', Reread u' u))

||| The reading lemma, as the growth proof states it: at markers fresh for
||| the frozen context and apart (`Proof.Markers.Markers`), put in by values
||| the site's writer holds (`MarkersHold`), every reading of what a request
||| holds of the site's term with those values put in (`HeldAs`), as an
||| instance's key reads it, is what the site's reading writes
||| (`Proof.Bound.Writes`), and so what the graph's site, that reading read
||| where its writer's families land, writes
||| (`Proof.Covers.siteWritesRead`). It is proved by induction on the
||| site's reading, the host's reduction inverted at each head it keeps
||| (`Proof.Inversion`), carried through putting the values in
||| (`Idris.Host.Mapped`, `Idris.Host.mappedReduces`) and through
||| contraction (`Proof.Reading`). At a shape the instance reads the
||| skeleton the request holds, never the whole term: where the site's
||| skeleton cuts a node to a hole, the request's skeleton cuts it too.
public export
0 ReadingCovers : {g : Graph} -> (m : Model g) -> Bound.Site g.size -> List StandIn -> (k : Readings.Static) -> (t : ClosedTerm) ->
                  SiteReading k t -> Type
ReadingCovers m s stands k t r =
  {0 ns : Scope} -> (mk : Markers r.mode.inContext ns) -> (vs : SubstEnv ns []) ->
  MarkersHold m s r.mode.inContext stands mk.bounds vs ->
  {0 held : ClosedTerm} -> HeldAs r.mode.inContext k (putIn SizeOf.zero (mkSizeOf ns) mk.bounds vs t) held ->
  (inst : InstanceReading r.mode.inContext k held) ->
  Writes m s r.template inst.template
