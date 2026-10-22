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
import Libraries.Data.List.Thin

import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Keys
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
%hide IdrisMLIR.Proof.Bound.Chosen
%hide IdrisMLIR.Proof.Bound.Beta
%hide IdrisMLIR.Proof.Bound.RunZero
%hide IdrisMLIR.Proof.Inversion.Inert

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

||| The definition the frozen context gives a name, at its place: nothing
||| for a name it defines as nothing, or for one at a negative entry, which
||| no place is.
inFrozen : (ctx : Frozen) -> (n : Name) -> Maybe (InFrozen ctx n)
inFrozen ctx n = case definitionIn ctx n of
  NotDefined _ => Nothing
  DefinedAs i _ d defines => (\p => MkInFrozen p d defines) <$> placementOf i

||| The definition at an address of the frozen context: nothing at bytes no
||| entry has.
atAddress : (ctx : Frozen) -> Address -> Maybe GlobalDef
atAddress ctx a = (.def) <$> (nameAt (gamma (defsOf ctx)) a >>= inFrozen ctx)

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
-- Roots
------------------------------------------------------------------------------

||| What a dictionary is at an instance whose values fix it: the definition
||| there, whose one right-hand side builds it, an implementation, which
||| splits its callee; or the implementations its leaves give, where it
||| computes one by matching or by applying another, which split nothing.
public export
data FixedRoot = BuiltBy Address | GivenBy (List Address)

||| What an instance makes of a dictionary its site leaves to the running
||| program. Stuck on a runtime value, or on a definition Idris does not
||| prove ends, it is the running program's at every instance. Stuck on
||| the writer's markers, each of which an instance puts a value in for,
||| an instance may fix it after all (`Closed.fixing`), and there it is
||| what a fixed one is (`FixedRoot`).
public export
data Settling = AtRunTimeAlways | FixedAt FixedRoot

||| What a dictionary or a family is at its root: the definition there (an
||| implementation or an interface constructor a dictionary is, the type
||| constructor a family's value applies); a dictionary the running program
||| chooses (`Closed.fixing`): a runtime value, or a definition no
||| compile-time reduction fixes, a member of its type's choice, which the
||| translation dispatches on wherever it is given, so a reader of it puts
||| in the choice (`asGiven`), with what an instance that fixes it after
||| all makes of it (`Settling`); the implementations a definition's leaves
||| give, where the program fixes the dictionary but no site names which: a
||| function that gives one at each use (a rank-2 dictionary, `\{y} => if
||| y == 0 then loud else quiet`), or a definition that computes one by
||| matching, applied, which the callee is given as written, so they split
||| nothing; the writer's own parameter there (a marker `Var i d`); or
||| neither (a family that is a lambda; a projection of what no constructor
||| builds, which the template's field says).
public export
data Root = Rooted Address
          | Chosen Settling
          | Gives (List1 Address)
          | Parameter Nat Nat
          | Unrooted

------------------------------------------------------------------------------
-- The markers
------------------------------------------------------------------------------

-- The walk's own markers are probes (`Walk`): bound names that no binder
-- binds and no context holds, each passing through every normaliser as
-- itself (a bound reference stays applied, Eval.idr). None is a hole
-- marker, since a request's key holds those for runtime values.

||| The marker of the part of the writer's parameter i that matches reached
||| along `path`, the parameter's field first: one value an instance gives,
||| which reads back as `Var i (length path)`. Field k of a match on it is
||| `markerAt i (path ++ [k])`, a marker of its own.
export
markerAt : (i : Nat) -> (path : List Nat) -> ClosedTerm
markerAt i path = probeTerm (ProbePart i path)

||| The parameter and path of `markerAt`'s name, and of no other.
export
markerOf : Name -> Maybe (Nat, List Nat)
markerOf n = case probeOf n of
  Just (ProbePart i path) => Just (i, path)
  _ => Nothing

||| The marker `Formal j a` reads back from: argument j of a family's
||| value, which takes a arguments of its own. A lambda's variable is one,
||| and so is each argument a definition given fewer than its parameters
||| lacks, so that what the value computes from its arguments is read where
||| beta puts them. Nothing matches it deeper: a match on it leaves the
||| value as written (`walk`).
formalAt : (j, a : Nat) -> TT vs
formalAt j a = probeTerm (ProbeFormal j a)

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
-- A site's stand-ins
------------------------------------------------------------------------------

||| A stand-in of a site's for a part of a shape no match has taken apart
||| yet: its number, the writer's parameter `param` it is a part of, and
||| the path matches took to it, the parameter's field first. Each has a
||| marker of its own (`standInAt`), so that two parts of one parameter,
||| which an instance gives two values, are two markers, and a site's term
||| is what an instance's argument is with a value put in for each of its
||| markers. Only a reading reads a stand-in as the part it stands for,
||| `Var param (length path)` (`walkMarker`), from the stand-ins of the
||| site it reads, which it is given.
public export
record StandIn where
  constructor MkStandIn
  number : Nat
  param : Nat
  path : List Nat

||| A stand-in's name: a bound name that is no machine name, since Idris's
||| quotation rebinds bound machine names by their number, and the
||| normalisers a reading asks quote.
export
standInName : Nat -> Name
standInName k = probeName (ProbePattern k)

||| A stand-in's marker, as a site's term holds it.
export
standInAt : StandIn -> ClosedTerm
standInAt p = probeTerm (ProbePattern p.number)

||| The stand-in of a site's that a stand-in's number names.
public export
standInNumbered : List StandIn -> Nat -> Maybe StandIn
standInNumbered stands k = find (\p => p.number == k) stands

||| The parameter and path of the part a probe stands for in a site: the
||| writer's marker of a part, or one of the site's stand-ins. The one
||| place a part is read off a probe.
public export
partOfProbe : List StandIn -> Probe -> Maybe (Nat, List Nat)
partOfProbe stands (ProbePart i path) = Just (i, path)
partOfProbe stands (ProbePattern k) = (\p => (p.param, p.path)) <$> standInNumbered stands k
partOfProbe _ _ = Nothing

||| The parameter and path of the part a site's marker stands for.
export
standingOf : List StandIn -> Name -> Maybe (Nat, List Nat)
standingOf stands n = probeOf n >>= partOfProbe stands

||| The marker a term is, the writer's or a stand-in of the site's, when it
||| is one, unapplied.
bareMarker : List StandIn -> ClosedTerm -> Maybe (Nat, List Nat)
bareMarker stands (Ref _ Bound n) = standingOf stands n
bareMarker _ _ = Nothing

||| A part by its parameter and how many matches deep it is, which is what
||| a template's marker records of it (`Var`).
public export
partDepth : (Nat, List Nat) -> (Nat, Nat)
partDepth (i, path) = (i, length path)

------------------------------------------------------------------------------
-- Scopes
------------------------------------------------------------------------------

||| What each variable of a scope stands for, the first first: a
||| definition's parameters and the arguments its matches bind.
public export
data Values : Type -> Scope -> Type where
  Nil : Values a []
  (::) : a -> Values a vs -> Values a (v :: vs)

||| What a variable stands for, which its scope says is there.
public export
valueAt : Values a vs -> (idx : Nat) -> (0 _ : IsVar n idx vs) -> a
valueAt (x :: _) Z _ = x
valueAt (_ :: xs) (S i) v = valueAt xs i (dropLater v)
valueAt [] _ First impossible
valueAt [] _ (Later _) impossible

||| An alternative's arguments, which come first, before the scope it
||| extends.
extend : Values a xs -> Values a ys -> Values a (xs ++ ys)
extend [] ys = ys
extend (x :: xs) ys = x :: extend xs ys

||| The parameters of a definition, the first argument first, and the
||| arguments past them; nothing when it is applied to fewer.
bindParams : (vs : Scope) -> List a -> Maybe (Values a vs, List a)
bindParams [] as = Just ([], as)
bindParams (_ :: vs) (a :: as) = map (\(env, rest) => (a :: env, rest)) (bindParams vs as)
bindParams (_ :: _) [] = Nothing

||| A constructor's arguments bound to what it was applied to; nothing when
||| they are not as many.
bindEach : (ns : List Name) -> List a -> Maybe (Values a ns)
bindEach [] [] = Just []
bindEach (_ :: ns) (x :: xs) = (x ::) <$> bindEach ns xs
bindEach _ _ = Nothing

||| Every argument of an alternative bound to one value.
bindAll : (ns : List Name) -> a -> Values a ns
bindAll [] _ = []
bindAll (_ :: ns) x = x :: bindAll ns x

||| What a match read behind what it matched on binds each argument of an
||| alternative to: on a part of the writer's parameter, the part at that
||| argument's own field below it, one value an instance gives, each its
||| own marker; on what is stuck in turn, which no marker stands for, the
||| stuck term, of which every argument is a part. These are the problem's
||| two cases: a part's fields are parts an instance gives values for, a
||| stuck term's are not.
public export
data FieldsOf = PartsOf Nat (List Nat) | AllOf ClosedTerm

||| What a match binds argument k of an alternative to (`FieldsOf`).
public export
fieldOf : FieldsOf -> Nat -> ClosedTerm
fieldOf (PartsOf j path) k = markerAt j (path ++ [k])
fieldOf (AllOf x) _ = x

||| An alternative's arguments from argument k on, each bound as the match
||| binds it (`fieldOf`).
public export
boundFields : FieldsOf -> (k : Nat) -> (ns : List Name) -> Values ClosedTerm ns
boundFields f k [] = []
boundFields f k (_ :: ns) = fieldOf f k :: boundFields f (S k) ns

sizeOfValues : Values a vs -> SizeOf vs
sizeOfValues [] = zero
sizeOfValues (_ :: xs) = suc (sizeOfValues xs)

substEnv : (a -> ClosedTerm) -> Values a vs -> SubstEnv vs []
substEnv f [] = []
substEnv f (x :: xs) = f x :: substEnv f xs

||| A term with each of its variables replaced by the term `f` makes of
||| what stands for it.
export
closeBy : (a -> ClosedTerm) -> Values a vs -> TT vs -> ClosedTerm
closeBy {vs} f env tm = substs (sizeOfValues env) (substEnv f env) (rewrite appendNilRightNeutral vs in tm)

||| A term with what each of its variables stands for.
close : Values ClosedTerm vs -> TT vs -> ClosedTerm
close = closeBy id

placeholders : (vs : Scope) -> Values ClosedTerm vs
placeholders [] = []
placeholders (_ :: vs) = Erased EmptyFC Placeholder :: placeholders vs

||| A term under binders, each binder's variable a placeholder, which no
||| reading looks into: what a part under a binder is when it is
||| substituted into a definition.
closedOver : {vs : Scope} -> TT vs -> ClosedTerm
closedOver tm = close (placeholders vs) tm

applyTo : ClosedTerm -> List ClosedTerm -> ClosedTerm
applyTo = foldl (App EmptyFC)

------------------------------------------------------------------------------
-- What every reading and every match sees
------------------------------------------------------------------------------

||| The writer's marker a bound name is, as a site reads it: a part of the
||| writer's parameter, `Var i` as many matches deep as its path is long; a
||| field of its dictionary along a path, below the dictionary's marker,
||| which no match makes a part; or one of the site's stand-ins, as the
||| part of the parameter it stands for. A stand-in the site being read did
||| not make is no part of its writer's, as any other bound name is none.
public export
walkMarker : List StandIn -> Name -> Maybe Template
walkMarker stands n = case probeOf n of
  Just (ProbeFieldPath i path) => Just (foldl (\t, k => Field k t) (Var i 0) path)
  Just q => uncurry Template.Var . partDepth <$> partOfProbe stands q
  Nothing => Nothing

||| Whether a bound name is a marker of a runtime value an implementation
||| closes over (`Closed.markerName`), with the evidence either way.
public export
data HoleView : Name -> Type where
  IsHole : (i : Nat) -> (0 _ : Closed.markerOf n = Just i) -> HoleView n
  NotHole : (0 _ : Closed.markerOf n = Nothing) -> HoleView n

export
holeView : (n : Name) -> HoleView n
holeView n with (Closed.markerOf n) proof found
  _ | Just i = IsHole i found
  _ | Nothing = NotHole found

||| A bound name that is no argument of a family's value.
public export
0 NotFormal : Name -> Type
NotFormal n = (j, k : Nat) -> Not (probeOf n = Just (ProbeFormal j k))

||| Whether a bound name is an argument of a family's value
||| (`Walk.ProbeFormal`), with the evidence either way.
public export
data FormalView : Name -> Type where
  IsFormal : (j, k : Nat) -> (0 _ : probeOf n = Just (ProbeFormal j k)) -> FormalView n
  NotFormalName : (0 _ : NotFormal n) -> FormalView n

-- A name that is another probe, or none, is no argument of a family's value.
0 otherThan : probeOf n = q -> ((j, k : Nat) -> Not (q = Just (ProbeFormal j k))) -> NotFormal n
otherThan found apart j k same = apart j k (trans (sym found) same)

export
formalView : (n : Name) -> FormalView n
formalView n with (probeOf n) proof found
  _ | Just (ProbeFormal j k) = IsFormal j k found
  _ | Nothing = NotFormalName (otherThan found (\_, _ => \case Refl impossible))
  _ | Just (ProbeBinder _) = NotFormalName (otherThan found (\_, _ => \case Refl impossible))
  _ | Just (ProbeHole _) = NotFormalName (otherThan found (\_, _ => \case Refl impossible))
  _ | Just (ProbeHoleFound _) = NotFormalName (otherThan found (\_, _ => \case Refl impossible))
  _ | Just ProbeUnknown = NotFormalName (otherThan found (\_, _ => \case Refl impossible))
  _ | Just ProbeRuntime = NotFormalName (otherThan found (\_, _ => \case Refl impossible))
  _ | Just (ProbeRuntimeAt _) = NotFormalName (otherThan found (\_, _ => \case Refl impossible))
  _ | Just (ProbeStandIn _) = NotFormalName (otherThan found (\_, _ => \case Refl impossible))
  _ | Just (ProbePattern _) = NotFormalName (otherThan found (\_, _ => \case Refl impossible))
  _ | Just ProbeForm = NotFormalName (otherThan found (\_, _ => \case Refl impossible))
  _ | Just (ProbeAxis _ _) = NotFormalName (otherThan found (\_, _ => \case Refl impossible))
  _ | Just (ProbeAxisAt _) = NotFormalName (otherThan found (\_, _ => \case Refl impossible))
  _ | Just (ProbeSize _) = NotFormalName (otherThan found (\_, _ => \case Refl impossible))
  _ | Just (ProbePart _ _) = NotFormalName (otherThan found (\_, _ => \case Refl impossible))
  _ | Just (ProbeFieldPath _ _) = NotFormalName (otherThan found (\_, _ => \case Refl impossible))

||| A reference as every reading and every match takes it. In order: a hole
||| marker (a runtime value an implementation closes over, which the key
||| writes as its number), an argument of a family's value, one of the
||| walk's markers (a part of the writer's parameter, by its parameter and
||| path, the writer's own marker or a stand-in of the site's; or a field
||| of the writer's dictionary, by its path), a bound name that is none of
||| these (a runtime part), a data or type constructor, a definition with a
||| place, and a definition with none, which stands for what is not known
||| of a runtime value (`unknownPart`, as `Closed.normalHead` reads it).
||| Every marker is a bound name (`Walk.probeTerm`), so a reference to a
||| constructor or a definition is what its reference says, whatever its
||| name, as the key writes it (`Keys.holeAt`).
data Reference = HoleMarker Nat
               | FormalMarker Nat Nat
               | PartMarker Nat (List Nat)
               | FieldMarker Nat (List1 Nat)
               | RuntimePart
               | DataConstructor (Maybe Address)
               | TypeConstructor (Maybe Address)
               | AtDefinition Address

referenceOf : Context -> List StandIn -> NameType -> Name -> Reference
referenceOf ctx stands Bound n = case Closed.markerOf n of
  Just i => HoleMarker i
  Nothing => case probeOf n of
    Just (ProbeFormal j a) => FormalMarker j a
    Just (ProbeFieldPath i path) => FieldMarker i path
    Just q => maybe RuntimePart (uncurry PartMarker) (partOfProbe stands q)
    Nothing => RuntimePart
referenceOf ctx stands (DataCon _ _) n = DataConstructor (definitionAddress ctx n)
referenceOf ctx stands (TyCon _) n = TypeConstructor (definitionAddress ctx n)
referenceOf ctx stands Func n = maybe RuntimePart AtDefinition (definitionAddress ctx n)

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
-- How a term is read
------------------------------------------------------------------------------

||| What a reading keeps of a part: a type's (or a dictionary's) every node,
||| or a value's skeleton, in which every part that is no data constructor
||| is one hole (`skeleton` makes it `Erased`). These are two cases of the
||| problem, and the one distinction an unfolding carries.
public export
data Keeping = EveryNode | Skeleton

||| What a reading does with a definition left applied: keep it as
||| written, as a written key holds it and as an instance's term is the
||| key; unfold its case tree beside the call as written, as a site's term
||| is read for every instance, some of which leave the call stuck and some
||| reduce it; or unfold it alone, which says where a type matches on a
||| value, and describes no key.
public export
data Calling = KeepsCall | UnfoldsBeside | WalksAlone

||| Whose term a reading reads: a site's, over its writer's markers and the
||| stand-ins it is given, each read as the part of the writer's parameter
||| it stands for, which stands for the term at every instance; or an
||| instance's, which holds no marker, and is what its key writes.
public export
data Whose = OfSite (List StandIn) | OfInstance

||| How a term is read, and against what: the frozen context every
||| definition, address and normal form of the reading is the one of. It
||| is read once, where the reading starts, so that what the reading says
||| of a name (`Idris.Host.Defines`) is what every step that unfolds the
||| name unfolds (`Idris.Host.definedOnce`), and a site's reading and its
||| instances' readings speak of one context.
public export
record Mode where
  constructor MkMode
  whose : Whose
  keeping : Keeping
  calls : Calling
  inContext : Frozen

||| How an instance's term is read: every node, its calls as written, as
||| its key writes it.
public export
InstanceMode : Frozen -> Mode
InstanceMode ctx = MkMode OfInstance EveryNode KeepsCall ctx

||| A part that is no head of its own: a node of a type's form, a hole of
||| a value's skeleton.
public export
nodeOf : Keeping -> Template -> Template
nodeOf EveryNode t = t
nodeOf Skeleton _ = Leaf 1

||| A template applied: a head above it and its arguments.
public export
aboveOf : Template -> List Template -> Template
aboveOf t ts = Head Nothing (t :: ts)

||| A part that is no head of its own, applied: a node above it and its
||| arguments in a type's form, a hole in a skeleton; alone, itself.
public export
partOf : Keeping -> Template -> List Template -> Template
partOf k t [] = t
partOf k t (u :: us) = nodeOf k (aboveOf t (u :: us))

||| One of the walk's markers applied: its reading, then its arguments'. A
||| family the writer was given, applied, is whatever every instance's
||| beta-reduction makes of its value's body around the arguments, which is
||| no head above them (`Applied`); a dictionary's field applied is a head
||| above it and them.
public export
markedOf : Template -> List Template -> Template
markedOf t [] = t
markedOf (Var i d) (u :: us) = Applied i d (u :: us)
markedOf t (u :: us) = aboveOf t (u :: us)

||| A leaf per character of a spelt constant.
public export
spelt : List Char -> List Template
spelt [] = []
spelt (_ :: cs) = Leaf 1 :: spelt cs

||| A constant as the key writes it (`Keys.writeConstant`): a string and a
||| double a node with a leaf per character after their shape's, an
||| integer one token carrying its magnitude's weight, anything else one
||| node. A literal's height is its node's, never its magnitude.
public export
constant : Constant -> Template
constant (Str x) = Head Nothing (spelt (unpack x))
constant (Db x) = Head Nothing (spelt (unpack (show x)))
constant (Ch _) = Leaf 1
constant (PrT _) = Leaf 1
constant WorldVal = Leaf 1
constant c = Token (weighs (writeConstant c))

||| A constant applied, as the key writes it: one node over the constant's
||| own parts and the arguments. No term Idris checks applies a constant;
||| the key writes one all the same.
public export
appliedConstant : Constant -> List Template -> Template
appliedConstant (Str x) ts = Head Nothing (spelt (unpack x) ++ ts)
appliedConstant (Db x) ts = Head Nothing (spelt (unpack (show x)) ++ ts)
appliedConstant c ts = partOf EveryNode (constant c) ts

||| The head of a constructor a match meets, as the host's step reads it: a
||| data constructor by its tag, which an alternative of another tag misses
||| (`Idris.Host.OtherTag`), or a type constructor, which an alternative at
||| another entry misses (`Idris.Host.OtherFamily`).
public export
data ConstructorHead = DataHead Int | FamilyHead

||| An alternative at another entry than the constructor a match meets,
||| missed as the host misses it: by its tag, for a data constructor; by
||| its entry, for a type constructor.
public export
data Missed : ConstructorHead -> Int -> Type where
  TagDiffers : (0 _ : Not (t = tag)) -> Missed (DataHead t) tag
  EntryDiffers : Missed FamilyHead tag

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
-- Literals, compared as the host compares them
------------------------------------------------------------------------------

-- A decision of base's, its evidence erased.
decided : DecEq a => (x, y : a) -> Decided (x = y)
decided x y = case decEq x y of
  Yes same => Yes same
  No other => No other

0 leftAlike : the (Either a b) (Left x) = Left y -> x = y
leftAlike Refl = Refl

0 rightAlike : the (Either a b) (Right x) = Right y -> x = y
rightAlike Refl = Refl

0 justAlike : Just x = Just y -> x = y
justAlike Refl = Refl

0 justNotNothing : Just x = Nothing -> Void
justNotNothing Refl impossible

0 noneIsJust : Nothing = Just x -> Void
noneIsJust Refl impossible

-- A sum decided by each side's decision.
sameEither : ((x, y : a) -> Decided (x = y)) -> ((x, y : b) -> Decided (x = y)) -> (e, e' : Either a b) -> Decided (e = e')
sameEither l r (Left x) (Left y) = case l x y of
  Yes same => Yes (cong Left same)
  No other => No (\eq => other (leftAlike eq))
sameEither l r (Right x) (Right y) = case r x y of
  Yes same => Yes (cong Right same)
  No other => No (\eq => other (rightAlike eq))
sameEither l r (Left _) (Right _) = No (\case Refl impossible)
sameEither l r (Right _) (Left _) = No (\case Refl impossible)

sameUnit : (x, y : ()) -> Decided (x = y)
sameUnit () () = Yes Refl

-- A primitive type by its number, which tells two apart.
primTypeCode : PrimType -> Nat
primTypeCode IntType = 0
primTypeCode Int8Type = 1
primTypeCode Int16Type = 2
primTypeCode Int32Type = 3
primTypeCode Int64Type = 4
primTypeCode IntegerType = 5
primTypeCode Bits8Type = 6
primTypeCode Bits16Type = 7
primTypeCode Bits32Type = 8
primTypeCode Bits64Type = 9
primTypeCode StringType = 10
primTypeCode CharType = 11
primTypeCode DoubleType = 12
primTypeCode WorldType = 13

primTypeAt : Nat -> Maybe PrimType
primTypeAt 0 = Just IntType
primTypeAt 1 = Just Int8Type
primTypeAt 2 = Just Int16Type
primTypeAt 3 = Just Int32Type
primTypeAt 4 = Just Int64Type
primTypeAt 5 = Just IntegerType
primTypeAt 6 = Just Bits8Type
primTypeAt 7 = Just Bits16Type
primTypeAt 8 = Just Bits32Type
primTypeAt 9 = Just Bits64Type
primTypeAt 10 = Just StringType
primTypeAt 11 = Just CharType
primTypeAt 12 = Just DoubleType
primTypeAt 13 = Just WorldType
primTypeAt _ = Nothing

0 primTypeDecoded : (t : PrimType) -> primTypeAt (primTypeCode t) = Just t
primTypeDecoded IntType = Refl
primTypeDecoded Int8Type = Refl
primTypeDecoded Int16Type = Refl
primTypeDecoded Int32Type = Refl
primTypeDecoded Int64Type = Refl
primTypeDecoded IntegerType = Refl
primTypeDecoded Bits8Type = Refl
primTypeDecoded Bits16Type = Refl
primTypeDecoded Bits32Type = Refl
primTypeDecoded Bits64Type = Refl
primTypeDecoded StringType = Refl
primTypeDecoded CharType = Refl
primTypeDecoded DoubleType = Refl
primTypeDecoded WorldType = Refl

-- Two primitive types, decided by their numbers.
samePrimType : (a, b : PrimType) -> Decided (a = b)
samePrimType a b = case sameNat (primTypeCode a) (primTypeCode b) of
  Yes same => Yes (justAlike (trans (sym (primTypeDecoded a)) (trans (cong primTypeAt same) (primTypeDecoded b))))
  No other => No (\eq => other (cong primTypeCode eq))

-- A literal other than a double as the sum it is, of types whose
-- equality base decides: an integer of each width, a string, a
-- character, a primitive type, the world.
LiteralSum : Type
LiteralSum = Either Int (Either Int8 (Either Int16 (Either Int32 (Either Int64 (Either Integer (Either Bits8 (Either Bits16 (Either Bits32 (Either Bits64 (Either String (Either Char (Either PrimType ()))))))))))))

fromLiteralSum : LiteralSum -> Constant
fromLiteralSum (Left x) = I x
fromLiteralSum (Right (Left x)) = I8 x
fromLiteralSum (Right (Right (Left x))) = I16 x
fromLiteralSum (Right (Right (Right (Left x)))) = I32 x
fromLiteralSum (Right (Right (Right (Right (Left x))))) = I64 x
fromLiteralSum (Right (Right (Right (Right (Right (Left x)))))) = BI x
fromLiteralSum (Right (Right (Right (Right (Right (Right (Left x))))))) = B8 x
fromLiteralSum (Right (Right (Right (Right (Right (Right (Right (Left x)))))))) = B16 x
fromLiteralSum (Right (Right (Right (Right (Right (Right (Right (Right (Left x))))))))) = B32 x
fromLiteralSum (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left x)))))))))) = B64 x
fromLiteralSum (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left x))))))))))) = Str x
fromLiteralSum (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left x)))))))))))) = Ch x
fromLiteralSum (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left t))))))))))))) = PrT t
fromLiteralSum (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right ()))))))))))))) = WorldVal

toLiteralSum : Constant -> Maybe LiteralSum
toLiteralSum (I x) = Just (Left x)
toLiteralSum (I8 x) = Just (Right (Left x))
toLiteralSum (I16 x) = Just (Right (Right (Left x)))
toLiteralSum (I32 x) = Just (Right (Right (Right (Left x))))
toLiteralSum (I64 x) = Just (Right (Right (Right (Right (Left x)))))
toLiteralSum (BI x) = Just (Right (Right (Right (Right (Right (Left x))))))
toLiteralSum (B8 x) = Just (Right (Right (Right (Right (Right (Right (Left x)))))))
toLiteralSum (B16 x) = Just (Right (Right (Right (Right (Right (Right (Right (Left x))))))))
toLiteralSum (B32 x) = Just (Right (Right (Right (Right (Right (Right (Right (Right (Left x)))))))))
toLiteralSum (B64 x) = Just (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left x))))))))))
toLiteralSum (Str x) = Just (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left x)))))))))))
toLiteralSum (Ch x) = Just (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left x))))))))))))
toLiteralSum (PrT x) = Just (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left x)))))))))))))
toLiteralSum WorldVal = Just (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right ())))))))))))))
toLiteralSum (Db _) = Nothing

0 sumReadBack : (s : LiteralSum) -> toLiteralSum (fromLiteralSum s) = Just s
sumReadBack (Left _) = Refl
sumReadBack (Right (Left _)) = Refl
sumReadBack (Right (Right (Left _))) = Refl
sumReadBack (Right (Right (Right (Left _)))) = Refl
sumReadBack (Right (Right (Right (Right (Left _))))) = Refl
sumReadBack (Right (Right (Right (Right (Right (Left _)))))) = Refl
sumReadBack (Right (Right (Right (Right (Right (Right (Left _))))))) = Refl
sumReadBack (Right (Right (Right (Right (Right (Right (Right (Left _)))))))) = Refl
sumReadBack (Right (Right (Right (Right (Right (Right (Right (Right (Left _))))))))) = Refl
sumReadBack (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left _)))))))))) = Refl
sumReadBack (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left _))))))))))) = Refl
sumReadBack (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left _)))))))))))) = Refl
sumReadBack (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left _))))))))))))) = Refl
sumReadBack (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right ()))))))))))))) = Refl

0 sumInjective : (s, s' : LiteralSum) -> fromLiteralSum s = fromLiteralSum s' -> s = s'
sumInjective s s' same = justAlike (trans (sym (sumReadBack s)) (trans (cong toLiteralSum same) (sumReadBack s')))

0 notDouble : (s : LiteralSum) -> Not (fromLiteralSum s = Db x)
notDouble s same = justNotNothing (trans (sym (sumReadBack s)) (cong toLiteralSum same))

sameLiteralSum : (s, s' : LiteralSum) -> Decided (s = s')
sameLiteralSum =
  sameEither decided (sameEither decided (sameEither decided (sameEither decided (sameEither decided
    (sameEither decided (sameEither decided (sameEither decided (sameEither decided (sameEither decided
    (sameEither decided (sameEither decided (sameEither samePrimType sameUnit))))))))))))

-- A literal is a double, or one of the sum's, read back.
data LiteralKind : Constant -> Type where
  ADouble : (x : Double) -> LiteralKind (Db x)
  InSum : (s : LiteralSum) -> LiteralKind (fromLiteralSum s)

literalKind : (k : Constant) -> LiteralKind k
literalKind (I x) = InSum (Left x)
literalKind (I8 x) = InSum (Right (Left x))
literalKind (I16 x) = InSum (Right (Right (Left x)))
literalKind (I32 x) = InSum (Right (Right (Right (Left x))))
literalKind (I64 x) = InSum (Right (Right (Right (Right (Left x)))))
literalKind (BI x) = InSum (Right (Right (Right (Right (Right (Left x))))))
literalKind (B8 x) = InSum (Right (Right (Right (Right (Right (Right (Left x)))))))
literalKind (B16 x) = InSum (Right (Right (Right (Right (Right (Right (Right (Left x))))))))
literalKind (B32 x) = InSum (Right (Right (Right (Right (Right (Right (Right (Right (Left x)))))))))
literalKind (B64 x) = InSum (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left x))))))))))
literalKind (Str x) = InSum (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left x)))))))))))
literalKind (Ch x) = InSum (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left x))))))))))))
literalKind (PrT x) = InSum (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Left x)))))))))))))
literalKind WorldVal = InSum (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right (Right ())))))))))))))
literalKind (Db x) = ADouble x

||| How the host's step compares a constant alternative with the literal a
||| match meets (`Idris.Host.ByConstant`, `Idris.Host.OtherConstant`): one
||| constant, or two apart, decided on their parts; or two doubles, which
||| the evaluator compares as doubles (`==`, so `0.0` meets `-0.0` and a
||| NaN meets nothing), where no equality of the constants is decided.
public export
data LiteralsCompared : Constant -> Constant -> Type where
  SameLiteral : (0 _ : k' = k) -> LiteralsCompared k' k
  OtherLiteral : (0 _ : Not (k' = k)) -> LiteralsCompared k' k
  TwoDoubles : (meets : Bool) -> (0 _ : (x' == x) = meets) -> LiteralsCompared (Db x') (Db x)

compareLiterals : (k', k : Constant) -> LiteralsCompared k' k
compareLiterals k' k with (literalKind k')
  compareLiterals _ k | ADouble x' with (literalKind k)
    compareLiterals _ _ | ADouble x' | ADouble x = TwoDoubles (x' == x) Refl
    compareLiterals _ _ | ADouble x' | InSum s = OtherLiteral (\same => notDouble s (sym same))
  compareLiterals _ k | InSum s' with (literalKind k)
    compareLiterals _ _ | InSum s' | ADouble x = OtherLiteral (notDouble s')
    compareLiterals _ _ | InSum s' | InSum s = case sameLiteralSum s' s of
      Yes same => SameLiteral (cong fromLiteralSum same)
      No other => OtherLiteral (\same => other (sumInjective s' s same))

||| Whether an alternative of a primitive type that binds nothing names the
||| literal a match meets, as the host's step decides it
||| (`Idris.Host.ByPrimitiveType`, `Idris.Host.OtherPrimitiveType`): the
||| type its name names, as a literal, is the literal.
namesLiteral : (cn : Name) -> (k : Constant) -> Decided (map PrT (isConstantType (dropNS cn)) = Just k)
namesLiteral cn k with (isConstantType (dropNS cn))
  _ | Nothing = No noneIsJust
  _ | Just t = case compareLiterals (PrT t) k of
    SameLiteral same => Yes (cong Just same)
    OtherLiteral other => No (\named => other (justAlike named))

||| What a match meets, parsed once: a data or type constructor applied, a
||| literal, a delay, a part of the writer's parameter (by its parameter
||| and path), an argument of a family's value, a runtime value (a part
||| every reading takes as one node, or a hole marker), or anything else:
||| an application stuck in turn, a projection of what is no constructor,
||| an applied marker, a field of the writer's dictionary.
data Scrutinee = Constructed ConstructorHead Name (List ClosedTerm)
               | Literal Constant
               | Suspended ClosedTerm ClosedTerm
               | Matched Nat (List Nat)
               | OnFormal Nat Nat
               | AtRuntime
               | StuckInTurn

undotted : TT vs -> TT vs
undotted (Erased _ (Dotted u)) = undotted u
undotted t = t

scrutineeOf : Context -> List StandIn -> ClosedTerm -> Scrutinee
scrutineeOf ctx stands s = case getFnArgs (undotted s) of
  (Ref _ (DataCon tag _) n, args) => Constructed (DataHead tag) n args
  (Ref _ (TyCon _) n, args) => Constructed FamilyHead n args
  (Ref _ nt n, args) => case (referenceOf ctx stands nt n, args) of
    (PartMarker i path, []) => Matched i path
    (FormalMarker j a, []) => OnFormal j a
    (RuntimePart, _) => AtRuntime
    (HoleMarker _, _) => AtRuntime
    _ => StuckInTurn
  (PrimVal _ k, []) => Literal k
  (TDelay _ _ ty a, []) => Suspended ty a
  (Erased _ Placeholder, _) => AtRuntime
  (Erased _ Impossible, _) => AtRuntime
  (Meta {}, _) => AtRuntime
  _ => StuckInTurn

------------------------------------------------------------------------------
-- Structural recursions
------------------------------------------------------------------------------

||| An alternative of a recursion on a Nat-like argument, one level deep:
||| the successor's leaf, which may recur, or another's (the zero's, the
||| default's), which must be closed.
data Arm = Step ClosedTerm | Base ClosedTerm

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

||| The other leaves of a structural recursion, and the closed children of
||| its successor's leaf, when it is one. The successor's leaf is a
||| recursive call, or a data or type constructor applied to children each
||| of which is a recursive call or closed; every recursive call takes a
||| predecessor marker at the matched position and every other argument as
||| it came; every other leaf is closed; and at least one call recurs.
||| Closed means: no marker of the walk's, no mention of the definition. A
||| predecessor is a part of the matched parameter one match deeper, told
||| by its parameter and depth (`partDepth`), whichever field it is.
recursion : Context -> List StandIn -> (self : Address) -> (predecessor : (Nat, Nat)) -> (args : List ClosedTerm) ->
            (idx : Nat) -> List Arm -> Maybe (List ClosedTerm, List ClosedTerm)
recursion ctx stands self predecessor args idx arms = case go arms of
  Just (bases, kids, S _) => Just (bases, kids)
  _ => Nothing
  where
    refersOut : {0 vs : Scope} -> TT vs -> Bool
    refersOut (Ref _ nt n) = case referenceOf ctx stands nt n of
      PartMarker _ _ => True
      FieldMarker _ _ => True
      FormalMarker _ _ => True
      AtDefinition a => a == self
      HoleMarker _ => False
      RuntimePart => False
      DataConstructor _ => False
      TypeConstructor _ => False
    refersOut _ = False

    isClosed : ClosedTerm -> Bool
    isClosed t = not (mentions refersOut t)

    -- The predecessor at the matched position, the arguments as they came
    -- at every other.
    stepped : Nat -> List ClosedTerm -> List ClosedTerm -> Bool
    stepped _ [] [] = True
    stepped Z (x :: xs) (_ :: ys) = map partDepth (bareMarker stands x) == Just predecessor && xs == ys
    stepped (S k) (x :: xs) (y :: ys) = x == y && stepped k xs ys
    stepped _ _ _ = False

    isCall : ClosedTerm -> Bool
    isCall t = case getFnArgs t of
      (Ref _ Func f, as) => definitionAddress ctx f == Just self && stepped idx as args
      _ => False

    -- The closed children and the number of recursive calls among them.
    children : List ClosedTerm -> Maybe (List ClosedTerm, Nat)
    children [] = Just ([], 0)
    children (k :: ks) = do
      (closed, calls) <- children ks
      if isCall k then Just (closed, S calls)
        else if isClosed k then Just (k :: closed, calls)
        else Nothing

    step : ClosedTerm -> Maybe (List ClosedTerm, Nat)
    step leaf = if isCall leaf then Just ([], 1) else case getFnArgs leaf of
      (Ref _ (DataCon _ _) _, ks) => children ks
      (Ref _ (TyCon _) _, ks) => children ks
      _ => Nothing

    go : List Arm -> Maybe (List ClosedTerm, List ClosedTerm, Nat)
    go [] = Just ([], [], 0)
    go (Step leaf :: rest) = do
      (closed, calls) <- step leaf
      (bases, kids, more) <- go rest
      Just (bases, closed ++ kids, calls + more)
    go (Base leaf :: rest) =
      if isClosed leaf
         then do (bases, kids, calls) <- go rest
                 Just (leaf :: bases, kids, calls)
         else Nothing

------------------------------------------------------------------------------
-- What a reading says of its term
------------------------------------------------------------------------------

||| What a variable bound inside the term being read is substituted by: a
||| lambda's, an argument of a family's value, which beta substitutes (its
||| position, and how many arguments it takes); any other binder's, a
||| placeholder no reading looks into.
public export
data Substitute = FormalArgument Nat Nat | Placeholding

||| A substitute as a closed term, which a part is closed with.
export
substituted : Substitute -> ClosedTerm
substituted (FormalArgument j k) = formalAt j k
substituted Placeholding = Erased EmptyFC Placeholder

||| A mode that unfolds what it meets left applied, as a site's leaves are
||| read; one that walks keeps walking.
unfolding : Mode -> Mode
unfolding (MkMode w k KeepsCall ctx) = MkMode w k UnfoldsBeside ctx
unfolding m = m

||| The stand-ins a mode reads, a site's; an instance's term holds none.
standsOf : Mode -> List StandIn
standsOf (MkMode (OfSite stands) _ _ _) = stands
standsOf (MkMode OfInstance _ _ _) = []

||| A substitute as read: an argument of a family's value, or a leaf of the
||| placeholder's height, so that every part it is substituted into stays
||| closed.
public export
substituteTemplate : Substitute -> Template
substituteTemplate (FormalArgument j k) = Formal j k
substituteTemplate Placeholding = Leaf 1

||| The address a reading's context gives a name: what a reading heads a
||| constructor, a type constructor or a call of it by, so that two
||| readings over one context head one name by one address.
public export
0 AddressedAs : Mode -> Name -> Maybe Address -> Type
AddressedAs m n a = definitionAddress (gamma (defsOf m.inContext)) n = a

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

||| Which eta-redexes a reading's normal forms are contracted at: a site's
||| type, read beside the unfoldings of its calls, keeps a redex around a
||| call (`Closed.CallsKept`), which it reads as both its forms (`SEta`);
||| every other reading takes them all contracted, as a key does.
public export
contractingFor : Mode -> Contracting
contractingFor (MkMode (OfSite _) EveryNode UnfoldsBeside ctx) = CallsKept (gamma (defsOf ctx))
contractingFor _ = EveryRedex

||| A lambda chain a site keeps around a call, as its reading reads it
||| (`SEta`): the call it contracts to, as written, which every instance
||| that leaves the call stuck contracts to, since nothing the instance puts
||| in mentions the lambdas' variables; and beside it, where an instance
||| unfolds the call, the unfolding under one lambda per argument the call
||| lacks, which such an instance keeps around what the call unfolds to.
public export
keptChain : Address -> List Template -> Maybe Template -> Template
keptChain a ts Nothing = Head (Just a) ts
keptChain a ts (Just t) = Choice (Leaf 1) [Head (Just a) ts, t]

mutual
  ||| What a reading says of a term over a scope, each variable by its
  ||| substitute: the template describes the term as its key writes it, one
  ||| node for each node the key writes, and a skeleton's hole for each part
  ||| a skeleton cuts. A site's term is read for every instance: a call it
  ||| leaves applied is the call as written beside what the instances that
  ||| reduce it make of it (`SBeside`, which carries how: `Reducing`), a
  ||| projection of what no constructor builds yet is the projection beside
  ||| the record's field (`SProjected`), a recursion met again is stuck
  ||| (`SRecurs`), and a marker is the part of the writer's parameter it
  ||| stands for (`SMarker`). An instance's term, which never unfolds, is
  ||| what this relation states whole.
  public export
  data ReadAs : Mode -> Values Substitute vs -> TT vs -> Template -> Type where
    ||| A closed run of a successor: its height.
    ARun : Run u n -> ReadAs m env u (Leaf (S n))
    ||| Any other term, read by its head.
    ASpine : SpineAs m env u [] t -> ReadAs m env u t

  ||| Terms read, each in turn.
  public export
  data AllReadAs : Mode -> Values Substitute vs -> List (TT vs) -> List Template -> Type where
    Nil : AllReadAs m env [] []
    (::) : ReadAs m env a t -> AllReadAs m env as ts -> AllReadAs m env (a :: as) (t :: ts)

  ||| A term applied to arguments, read by its head: a node of the key holds
  ||| the head's own parts and the arguments the head is applied to.
  public export
  data SpineAs : Mode -> Values Substitute vs -> TT vs -> List (TT vs) -> Template -> Type where
    SApp : SpineAs m env f (a :: as) t -> SpineAs m env (App fc f a) as t
    SDot : ReadAs m env u r -> AllReadAs m env as ts ->
           SpineAs m env (Erased fc (Dotted u)) as (nodeOf m.keeping (Head Nothing (r :: ts)))
    SPlaceholder : AllReadAs m env as ts -> SpineAs m env (Erased fc Placeholder) as (partOf m.keeping (Leaf 1) ts)
    SImpossible : AllReadAs m env as ts -> SpineAs m env (Erased fc Impossible) as (partOf m.keeping (Leaf 1) ts)
    SLocal : {0 p : IsVar x idx vs} -> AllReadAs m env as ts ->
             SpineAs m env (Local fc l idx p) as (partOf m.keeping (substituteTemplate (valueAt env idx p)) ts)
    SMeta : AllReadAs m env margs ms -> AllReadAs m env as ts ->
            SpineAs m env (Meta fc x i margs) as (nodeOf m.keeping (Head Nothing (ms ++ ts)))
    SUniverse : AllReadAs m env as ts -> SpineAs m env (TType fc u) as (partOf m.keeping (Leaf 1) ts)
    SConstant : AllReadAs m env as ts -> SpineAs m env (PrimVal fc c) as (nodeOf m.keeping (appliedConstant c ts))
    SLambda : {0 vs : Scope} -> {0 env : Values Substitute vs} ->
              PassingAs m env info ps -> ReadAs m env ty t -> ReadAs m (FormalArgument (length vs) k :: env) sc s ->
              AllReadAs m env as ts ->
              SpineAs m env (Bind fc x (Lam lfc rig info ty) sc) as (nodeOf m.keeping (Head Nothing ((ps ++ [t, s]) ++ ts)))
    SBinder : BinderAs m env b ps -> ReadAs m (Placeholding :: env) sc s -> AllReadAs m env as ts ->
              SpineAs m env (Bind fc x b sc) as (nodeOf m.keeping (Head Nothing ((ps ++ [s]) ++ ts)))
    ||| A lambda chain a site's type keeps around a call
    ||| (`Closed.CallsKept`), alone: both its forms (`keptChain`), the call
    ||| it contracts to and, where an instance unfolds the call, the
    ||| unfolding under one lambda per argument the call lacks.
    SEta : (0 _ : EtaContracts (Bind fc x (Lam lfc rig info ty) sc) g) ->
           EtaChain (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) env (Bind fc x (Lam lfc rig info ty) sc) a ts r ->
           SpineAs (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) env (Bind fc x (Lam lfc rig info ty) sc) []
                   (keptChain a ts r)
    SDelayed : ReadAs m env u t -> AllReadAs m env as ts ->
               SpineAs m env (TDelayed fc r u) as (nodeOf m.keeping (Head Nothing (t :: ts)))
    SDelay : ReadAs m env ty t -> ReadAs m env a v -> AllReadAs m env as ts ->
             SpineAs m env (TDelay fc r ty a) as (nodeOf m.keeping (Head Nothing (t :: v :: ts)))
    SForce : ReadAs m env u t -> AllReadAs m env as ts ->
             SpineAs m env (TForce fc r u) as (nodeOf m.keeping (Head Nothing (t :: ts)))
    SAs : ReadAs m env a t -> ReadAs m env p v -> AllReadAs m env as ts ->
          SpineAs m env (As fc side a p) as (nodeOf m.keeping (Head Nothing (t :: v :: ts)))
    ||| A marker of a runtime value an implementation closes over: its
    ||| number's token.
    SHole : (0 _ : Closed.markerOf n = Just i) -> AllReadAs m env as ts ->
            SpineAs m env (Ref fc Bound n) as (partOf m.keeping (Token (S i)) ts)
    ||| Argument j of a family's value, which beta substitutes.
    SFormal : (0 _ : Closed.markerOf n = Nothing) -> (0 _ : probeOf n = Just (ProbeFormal j k)) ->
              AllReadAs m env as ts -> SpineAs m env (Ref fc Bound n) as (partOf m.keeping (Formal j k) ts)
    ||| One of the writer's markers, in a site's term.
    SMarker : (0 _ : walkMarker stands n = Just t) -> AllReadAs (MkMode (OfSite stands) kp cl ctx) env as ts ->
              SpineAs (MkMode (OfSite stands) kp cl ctx) env (Ref fc Bound n) as (markedOf t ts)
    ||| Any other bound name, which is no argument of a family's value: a
    ||| runtime part, one node.
    SPart : (0 _ : Closed.markerOf n = Nothing) -> (0 _ : NotFormal n) -> AllReadAs m env as ts ->
            SpineAs m env (Ref fc Bound n) as (partOf m.keeping (Leaf 1) ts)
    ||| A definition with no place: what is not known of a runtime value.
    SNoDefinition : (0 _ : AddressedAs m n Nothing) -> AllReadAs m env as ts ->
                    SpineAs m env (Ref fc Func n) as (partOf m.keeping (Leaf 1) ts)
    ||| A data constructor applied, headed by the address the context gives
    ||| it.
    SData : (0 _ : AddressedAs m n a) -> AllReadAs m env as ts -> SpineAs m env (Ref fc (DataCon tag arity) n) as (Head a ts)
    STypeCon : (0 _ : AddressedAs m n a) -> AllReadAs m env as ts ->
               SpineAs m env (Ref fc (TyCon arity) n) as (nodeOf m.keeping (Head a ts))
    ||| A definition as written.
    SKept : (0 _ : AddressedAs m n (Just a)) -> AllReadAs m env as ts ->
            SpineAs m env (Ref fc Func n) as (nodeOf m.keeping (Head (Just a) ts))
    ||| A call in a site's term: as written, which every instance that
    ||| leaves it stuck writes, beside what the others make of it, read off
    ||| the definition at the call's arguments as written (`Reducing`).
    SBeside : (0 _ : AddressedAs (MkMode (OfSite stands) kp cl ctx) n (Just a)) ->
              AllReadAs (MkMode (OfSite stands) kp cl ctx) env as ts ->
              Reducing (MkMode (OfSite stands) kp cl ctx) a n (map (closeBy Template.substituted env) as) (nodeOf kp (Head (Just a) ts)) t ->
              SpineAs (MkMode (OfSite stands) kp cl ctx) env (Ref fc Func n) as (Choice (Leaf 1) [nodeOf kp (Head (Just a) ts), t])
    ||| `believe_me` applied to its two types and a value, in a site's type:
    ||| as written, which an instance leaves where the value it is given is
    ||| none the evaluator gives back unchanged, beside that value, which it
    ||| gives back unchanged everywhere else (`Idris.Host.BelievedMe`).
    SBelieved : (0 _ : AddressedAs (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) n (Just a)) ->
                (0 _ : Defines ctx n def) -> (0 _ : definition def = Builtin BelieveMe) ->
                AllReadAs (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) env [ta, tb, tv] [ra, rb, rv] ->
                SpineAs (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) env (Ref fc Func n) [ta, tb, tv]
                        (Choice (Leaf 1) [Head (Just a) [ra, rb, rv], rv])
    ||| A projection, in a site's type, of a record no constructor builds
    ||| yet: as written, which a dictionary's key keeps while the record
    ||| stays no constructor, or the record's field once it is one, applied
    ||| to the arguments past the projection's own; behind the record.
    SProjected : (0 _ : AddressedAs (MkMode (OfSite stands) EveryNode cl ctx) n (Just a)) ->
                 ReadAs (MkMode (OfSite stands) EveryNode cl ctx) env r rt ->
                 AllReadAs (MkMode (OfSite stands) EveryNode cl ctx) env as ts ->
                 AllReadAs (MkMode (OfSite stands) EveryNode cl ctx) env xs es ->
                 SpineAs (MkMode (OfSite stands) EveryNode cl ctx) env (Ref fc Func n) as
                         (Choice rt [Head (Just a) ts, partOf EveryNode (Template.Field k rt) es])
    ||| A recursion met again on its own unfolding, in a site's term.
    SRecurs : (0 _ : AddressedAs (MkMode (OfSite stands) kp cl ctx) n (Just a)) ->
              AllReadAs (MkMode (OfSite stands) kp cl ctx) env as ts ->
              SpineAs (MkMode (OfSite stands) kp cl ctx) env (Ref fc Func n) as (Opaque a ts)
    ||| A call's unfolding alone, read for where a type matches.
    SWalked : (0 _ : AddressedAs (MkMode (OfSite stands) kp WalksAlone ctx) n (Just a)) ->
              AllReadAs (MkMode (OfSite stands) kp WalksAlone ctx) env as ts ->
              Reducing (MkMode (OfSite stands) kp WalksAlone ctx) a n (map (closeBy Template.substituted env) as) (nodeOf kp (Head (Just a) ts)) t ->
              SpineAs (MkMode (OfSite stands) kp WalksAlone ctx) env (Ref fc Func n) as t

  ||| What a binder's implicitness holds: a default, which the key writes.
  public export
  data PassingAs : Mode -> Values Substitute vs -> PiInfo (TT vs) -> List Template -> Type where
    PImplicit : PassingAs m env Implicit []
    PExplicit : PassingAs m env Explicit []
    PAuto : PassingAs m env AutoImplicit []
    PDefault : ReadAs m env d r -> PassingAs m env (DefImplicit d) [r]

  ||| A binder's parts, of a binder that is no lambda (`NodeBinder`): its
  ||| default, its type, and a `let`'s value.
  public export
  data BinderAs : Mode -> Values Substitute vs -> TTBinder (TT vs) -> List Template -> Type where
    BLet : ReadAs m env v tv -> ReadAs m env ty t -> BinderAs m env (Let fc rig v ty) [tv, t]
    BPi : PassingAs m env info ps -> ReadAs m env ty t -> BinderAs m env (Pi fc rig info ty) (ps ++ [t])
    BPVar : PassingAs m env info ps -> ReadAs m env ty t -> BinderAs m env (PVar fc rig info ty) (ps ++ [t])
    BPLet : ReadAs m env v tv -> ReadAs m env ty t -> BinderAs m env (PLet fc rig v ty) [tv, t]
    BPVTy : ReadAs m env ty t -> BinderAs m env (PVTy fc rig ty) [t]

  ||| A lambda chain a site keeps around a call (`Closed.CallsKept`), read
  ||| down to the call: under each lambda, its implicitness and its type,
  ||| its variable an argument of the value (`Formal`), as a lambda is read;
  ||| at the call, its own arguments, and what an instance that unfolds it
  ||| makes of it (`CallUnfolds`), under the lambdas; nothing where no
  ||| instance unfolds it.
  public export
  data EtaChain : Mode -> Values Substitute vs -> TT vs -> Address -> List Template -> Maybe Template -> Type where
    ChainLambda : {0 vs : Scope} -> {0 env : Values Substitute vs} ->
                  PassingAs m env info ps -> ReadAs m env ty t ->
                  EtaChain m (FormalArgument (length vs) k :: env) sc a ts r ->
                  EtaChain m env (Bind fc x (Lam lfc rig info ty) sc) a ts
                           (map (\s => nodeOf m.keeping (Head Nothing (ps ++ [t, s]))) r)
    ChainCall : CallUnfolds m env u [] a ts r -> EtaChain m env u a ts r

  ||| The call at the bottom of a kept lambda chain, read down its spine:
  ||| its own arguments, then the chain's variables it is applied to; and
  ||| what an instance that unfolds it makes of it, read as a site's call
  ||| beside its unfolding is (`Reducing`); a recursion met again on its own
  ||| unfolding, which nothing bounds; or nothing, where no instance
  ||| unfolds it.
  public export
  data CallUnfolds : Mode -> Values Substitute vs -> TT vs -> List (TT vs) -> Address -> List Template ->
                     Maybe Template -> Type where
    UnfoldsApplied : CallUnfolds m env f (a :: as) d ts r -> CallUnfolds m env (App fc f a) as d ts r
    CallWalked : (0 _ : AddressedAs m n (Just d)) -> AllReadAs m env own ts -> AllReadAs m env vars fs ->
                 Reducing m d n (map (closeBy Template.substituted env) (own ++ vars)) (nodeOf m.keeping (Head (Just d) (ts ++ fs))) t ->
                 CallUnfolds m env (Ref fc Func n) (own ++ vars) d ts (Just t)
    CallAgain : (0 _ : AddressedAs m n (Just d)) -> AllReadAs m env own ts -> AllReadAs m env vars fs ->
                CallUnfolds m env (Ref fc Func n) (own ++ vars) d ts (Just (Opaque d (ts ++ fs)))
    CallStays : (0 _ : AddressedAs m n (Just d)) -> AllReadAs m env own ts ->
                CallUnfolds m env (Ref fc Func n) (own ++ vars) d ts Nothing

  ||| What an instance that reduces a call of a site's makes of it, as the
  ||| reading reads it beside the call as written (`written`), off the
  ||| definition the frozen context gives the call's name, at the call's
  ||| arguments as closed terms. This is the trace the reading's soundness
  ||| against the host's steps (`Idris.Host.Unfold`, `Idris.Host.Chooses`)
  ||| is stated over: every leaf an instance's evaluation reaches is one
  ||| the trace read.
  export
  data Reducing : Mode -> Address -> Name -> List ClosedTerm -> (written : Template) -> Template -> Type where
    ||| Its case tree walked over its arguments.
    ByWalk : (0 _ : Defines m.inContext n def) -> (0 _ : definition def = PMDef info pargs body) -> (0 _ : TreeOf body tree) ->
             (0 _ : bindParams pargs terms = Just (env, extras)) -> Unfolds m a written env tree extras (Just t) ->
             Reducing m a n terms written t
    ||| A recursion structural on a Nat-like argument: the argument raised
    ||| by its leaves.
    ByStructure : (0 _ : Defines m.inContext n def) -> (0 _ : definition def = PMDef info pargs body) -> (0 _ : TreeOf body tree) ->
                  (0 _ : bindParams pargs terms = Just (env, extras)) -> Structural m a terms env tree t ->
                  Reducing m a n terms written t
    ||| Given fewer arguments than its parameters: a family's value, its
    ||| tree walked over an argument of the value for each it lacks.
    ByGiven : (0 _ : Defines m.inContext n def) -> (0 _ : definition def = PMDef info pargs body) -> (0 _ : TreeOf body tree) ->
              (0 _ : bindParams pargs terms = Nothing) -> GivenUnfolds m a written terms pargs tree t ->
              Reducing m a n terms written t
    ||| A builtin given as many arguments as it takes, the writer's markers
    ||| among them: the constant it computes where they are constants
    ||| (`Idris.Host.Primitive`), no higher than a leaf two high.
    ByBuiltin : (0 _ : Defines m.inContext n def) -> (0 _ : definition def = Builtin {arity} op) ->
                (0 _ : length terms = arity) -> Reducing m a n terms written (Leaf 2)

  ||| A family's value walked over an argument of the value for each
  ||| parameter it lacks; or, met again on its own unfolding, a recursion
  ||| through the arguments it lacks, which nothing bounds.
  export
  data GivenUnfolds : Mode -> Address -> (written : Template) -> List ClosedTerm -> (pargs : Scope) -> CaseTree pargs ->
                      Template -> Type where
    GivenWalked : (0 _ : bindParams pargs (terms ++ map Template.substituted lacking) = Just (env, extras)) ->
                  Unfolds m a written env tree extras (Just t) -> GivenUnfolds m a written terms pargs tree t
    GivenAgain : GivenUnfolds m a written terms pargs tree (Opaque a (map Template.substituteTemplate lacking))

  ||| A recursion structural on a part of the writer's parameter j at
  ||| `path`, which reads as `Var j (length path)`, a Nat-like argument
  ||| every recursive call takes a predecessor of: its other leaves, and the
  ||| marker raised by the tallest of them and of the successor's closed
  ||| children, less one. Its shape is what `recursion` found in its arms,
  ||| which the bound rests on.
  export
  data Structural : Mode -> (self : Address) -> (args : List ClosedTerm) -> Values ClosedTerm vs -> CaseTree vs ->
                    Template -> Type where
    Raised : (0 _ : bareMarker (standsOf m) (valueAt env idx p) = Just (j, path)) ->
             (0 _ : recursion (gamma (defsOf m.inContext)) (standsOf m) self (j, S (length path)) args idx arms =
                    Just (bases, kids)) ->
             AllReadAs (unfolding m) [] bases leaves -> AllReadAs (unfolding m) [] kids children ->
             Structural m self args env (Case idx p ty alts)
                        (Choice (Var j (length path))
                                (leaves ++ [raise (minus (max (tallest leaves) (tallest children)) 1) (Var j (length path))]))

  ||| What the walk of a case tree read over what its variables stand for
  ||| and the arguments past its parameters: each leaf it reached, read off
  ||| the host's normal form of the right-hand side; at a match on a closed
  ||| constructor, literal or delay, the alternative it takes; at a match
  ||| on the writer's marker, or on what is stuck in turn, every
  ||| alternative behind what was matched; at a match on a runtime value,
  ||| the definition as written; nothing for an absurd tree.
  export
  data Unfolds : Mode -> (self : Address) -> (written : Template) -> Values ClosedTerm vs -> CaseTree vs ->
                 List ClosedTerm -> Maybe Template -> Type where
    ULeaf : (0 r : NormalReading OfNormaliseTypes m.inContext (applyTo (close env rhs) extras)) ->
            ReadAs (unfolding m) [] r.readForm t -> Unfolds m self written env (STerm i rhs) extras (Just t)
    UUnmatched : Unfolds m self written env (Unmatched msg) extras (Just written)
    UImpossible : Unfolds m self written env Impossible extras Nothing
    UConstructed : (0 _ : scrutineeOf (gamma (defsOf m.inContext)) (standsOf m) (valueAt env idx p) = Constructed h c sargs) ->
                   TakenBy m self written env h c sargs alts extras r ->
                   Unfolds m self written env (Case idx p ty alts) extras r
    ULiteral : (0 _ : scrutineeOf (gamma (defsOf m.inContext)) (standsOf m) (valueAt env idx p) = Literal k) ->
               TakesLiteral m self written env k alts extras r -> Unfolds m self written env (Case idx p ty alts) extras r
    USuspended : (0 _ : scrutineeOf (gamma (defsOf m.inContext)) (standsOf m) (valueAt env idx p) = Suspended dty da) ->
                 TakesDelay m self written env dty da alts extras r -> Unfolds m self written env (Case idx p ty alts) extras r
    UMatched : (0 _ : scrutineeOf (gamma (defsOf m.inContext)) (standsOf m) (valueAt env idx p) = Matched j path) ->
               Alternatives m self written env (PartsOf j path) alts extras ls ->
               Unfolds m self written env (Case idx p ty alts) extras (Just (Choice (Var j (length path)) ls))
    UOnFormal : (0 _ : scrutineeOf (gamma (defsOf m.inContext)) (standsOf m) (valueAt env idx p) = OnFormal j k) ->
                Unfolds m self written env (Case idx p ty alts) extras
                        (Just (Choice (Formal j k) [written, Opaque self [Formal j k]]))
    UAtRuntime : (0 _ : scrutineeOf (gamma (defsOf m.inContext)) (standsOf m) (valueAt env idx p) = AtRuntime) ->
                 Unfolds m self written env (Case idx p ty alts) extras (Just written)
    UStuck : (0 _ : scrutineeOf (gamma (defsOf m.inContext)) (standsOf m) (valueAt env idx p) = StuckInTurn) ->
             ReadAs (unfolding m) [] (valueAt env idx p) t ->
             Alternatives m self written env (AllOf (valueAt env idx p)) alts extras ls ->
             Unfolds m self written env (Case idx p ty alts) extras (Just (Choice t ls))

  ||| The alternative a constructor takes, by the entry its name resolves
  ||| to, as the host's step takes it (`Idris.Host.Picks`): the first at
  ||| its entry, or a default, its arguments bound to the constructor's,
  ||| past every alternative the host misses; the definition as written
  ||| where none is, or where the host's walk of the tree is stuck.
  export
  data TakenBy : Mode -> (self : Address) -> (written : Template) -> Values ClosedTerm vs -> ConstructorHead -> Name ->
                 List ClosedTerm -> List (CaseAlt vs) -> List ClosedTerm -> Maybe Template -> Type where
    TakesThis : (0 _ : SameEntry m.inContext c con) -> (0 _ : bindEach cargs sargs = Just bound) ->
                Unfolds m self written (extend bound env) t extras r ->
                TakenBy m self written env h c sargs (ConCase con tag cargs t :: alts) extras r
    PassesThis : (0 _ : Not (SameEntry m.inContext c con)) -> (0 _ : Missed h tag) ->
                 TakenBy m self written env h c sargs alts extras r ->
                 TakenBy m self written env h c sargs (ConCase con tag cargs t :: alts) extras r
    ||| The constructor at the alternative's entry applied to other than as
    ||| many arguments as the alternative binds: the evaluator neither
    ||| matches the alternative nor misses it (`Idris.Host.Picks`), so its
    ||| walk of the tree is stuck there and every instance leaves the
    ||| definition as written.
    ArityDiffers : (0 _ : SameEntry m.inContext c con) -> (0 _ : bindEach cargs sargs = Nothing) ->
                   TakenBy m self written env h c sargs (ConCase con tag cargs t :: alts) extras (Just written)
    ||| A data constructor at another entry than the alternative's, of its
    ||| tag: the evaluator neither matches nor misses it, and every instance
    ||| leaves the definition as written.
    TagShared : (0 _ : Not (SameEntry m.inContext c con)) -> (0 _ : t = tag) ->
                TakenBy m self written env (DataHead t) c sargs (ConCase con tag cargs u :: alts) extras (Just written)
    TakesDefault : Unfolds m self written env t extras r -> TakenBy m self written env h c sargs (DefaultCase t :: alts) extras r
    ||| An alternative of a delay or of a constant, which a constructor
    ||| neither matches nor misses: the host's walk is stuck there.
    MeetsDelay : TakenBy m self written env h c sargs (DelayCase tyn argn t :: alts) extras (Just written)
    MeetsConstant : TakenBy m self written env h c sargs (ConstCase k t :: alts) extras (Just written)
    NoneTaken : TakenBy m self written env h c sargs [] extras (Just written)

  ||| The alternative a literal takes, as the host's step takes it
  ||| (`Idris.Host.Picks`): the first of that constant, or of the primitive
  ||| type the literal is, or a default, past every alternative the host
  ||| misses (another constant, a primitive type the literal is not, an
  ||| alternative that binds fields); the definition as written where the
  ||| host's walk is stuck, at a delay's alternative, or where none is left.
  ||| Two doubles compare as the evaluator compares them.
  export
  data TakesLiteral : Mode -> (self : Address) -> (written : Template) -> Values ClosedTerm vs -> Constant ->
                      List (CaseAlt vs) -> List ClosedTerm -> Maybe Template -> Type where
    LiteralThis : (0 _ : k' = k) -> Unfolds m self written env t extras r ->
                  TakesLiteral m self written env k (ConstCase k' t :: alts) extras r
    LiteralPasses : (0 _ : Not (k' = k)) -> TakesLiteral m self written env k alts extras r ->
                    TakesLiteral m self written env k (ConstCase k' t :: alts) extras r
    DoubleMeets : (0 _ : (x' == x) = True) -> Unfolds m self written env t extras r ->
                  TakesLiteral m self written env (Db x) (ConstCase (Db x') t :: alts) extras r
    DoublePasses : (0 _ : (x' == x) = False) -> TakesLiteral m self written env (Db x) alts extras r ->
                   TakesLiteral m self written env (Db x) (ConstCase (Db x') t :: alts) extras r
    LiteralNamesType : (0 _ : map PrT (isConstantType (dropNS cn)) = Just k) -> Unfolds m self written env t extras r ->
                       TakesLiteral m self written env k (ConCase cn tag [] t :: alts) extras r
    LiteralOtherType : (0 _ : Not (map PrT (isConstantType (dropNS cn)) = Just k)) ->
                       TakesLiteral m self written env k alts extras r ->
                       TakesLiteral m self written env k (ConCase cn tag [] t :: alts) extras r
    LiteralFields : TakesLiteral m self written env k alts extras r ->
                    TakesLiteral m self written env k (ConCase cn tag (f :: fs) t :: alts) extras r
    LiteralDefault : Unfolds m self written env t extras r -> TakesLiteral m self written env k (DefaultCase t :: alts) extras r
    LiteralMeetsDelay : TakesLiteral m self written env k (DelayCase tyn argn t :: alts) extras (Just written)
    NoLiteral : TakesLiteral m self written env k [] extras (Just written)

  ||| The alternative a delay takes, as the host's step takes it: the first
  ||| delay's, its type and value bound, or a default; the definition as
  ||| written where the host's walk is stuck, at an alternative of a
  ||| constructor or a constant, which a delay neither matches nor misses,
  ||| or where none is left.
  export
  data TakesDelay : Mode -> (self : Address) -> (written : Template) -> Values ClosedTerm vs -> ClosedTerm -> ClosedTerm ->
                    List (CaseAlt vs) -> List ClosedTerm -> Maybe Template -> Type where
    DelayThis : Unfolds m self written (dty :: da :: env) t extras r ->
                TakesDelay m self written env dty da (DelayCase tyn argn t :: alts) extras r
    DelayDefault : Unfolds m self written env t extras r -> TakesDelay m self written env dty da (DefaultCase t :: alts) extras r
    DelayMeetsConstructor : TakesDelay m self written env dty da (ConCase con tag cargs t :: alts) extras (Just written)
    DelayMeetsConstant : TakesDelay m self written env dty da (ConstCase k t :: alts) extras (Just written)
    NoDelay : TakesDelay m self written env dty da [] extras (Just written)

  ||| Every alternative's leaves, each argument a constructor or a delay
  ||| binds as the match binds it (`FieldsOf`); an absurd one gives none.
  export
  data Alternatives : Mode -> (self : Address) -> (written : Template) -> Values ClosedTerm vs -> FieldsOf ->
                      List (CaseAlt vs) -> List ClosedTerm -> List Template -> Type where
    NoAlternatives : Alternatives m self written env f [] extras []
    WithAlternative : AlternativeUnfolds m self written env f alt extras r -> Alternatives m self written env f alts extras ls ->
                  Alternatives m self written env f (alt :: alts) extras (maybe ls (\u => u :: ls) r)

  ||| One alternative walked, argument k it binds bound as the match binds
  ||| it (`fieldOf`): a delay's type its first and its value its second.
  export
  data AlternativeUnfolds : Mode -> (self : Address) -> (written : Template) -> Values ClosedTerm vs -> FieldsOf ->
                            CaseAlt vs -> List ClosedTerm -> Maybe Template -> Type where
    ConstructorAlternative : Unfolds m self written (extend (boundFields f 0 cargs) env) t extras r ->
                             AlternativeUnfolds m self written env f (ConCase con tag cargs t) extras r
    DelayAlternative : Unfolds m self written (fieldOf f 0 :: fieldOf f 1 :: env) t extras r ->
                       AlternativeUnfolds m self written env f (DelayCase tyn argn t) extras r
    ConstantAlternative : Unfolds m self written env t extras r -> AlternativeUnfolds m self written env f (ConstCase k t) extras r
    DefaultAlternative : Unfolds m self written env t extras r -> AlternativeUnfolds m self written env f (DefaultCase t) extras r

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
  0 closedAs : Force value = closeBy Template.substituted stand term
  reading : Lazy (Front (Subset Template (ReadAs m stand term)))

||| The terms of some arguments.
termsOf : List (Arg m stand) -> List (TT vs)
termsOf [] = []
termsOf (a :: as) = a.term :: termsOf as

-- The closed terms a call's unfolding walks are its arguments as written,
-- each variable by its substitute.
0 closedTerms : (args : List (Arg m stand)) -> map (\x => Force x.value) args = map (closeBy Template.substituted stand) (termsOf args)
closedTerms [] = Refl
closedTerms (a :: as) = cong2 (::) a.closedAs (closedTerms as)

||| The arguments' readings, in order.
readings : (args : List (Arg m stand)) -> Front (Subset (List Template) (AllReadAs m stand (termsOf args)))
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
            (m : Mode) -> (fc : FC) -> (n : Name) -> (0 _ : Closed.markerOf n = Nothing) -> (0 _ : NotFormal n) ->
            (ts : List Template) -> (0 _ : AllReadAs m stand as ts) ->
            Subset Template (SpineAs m stand (Ref fc Bound n) as)
siteBound (MkMode (OfSite stands) kp cl ctx) fc n none plain ts rs with (walkMarker stands n) proof found
  _ | Just t = Element (markedOf t ts) (SMarker found rs)
  _ | Nothing = Element (partOf kp (Leaf 1) ts) (SPart none plain rs)
siteBound (MkMode OfInstance kp cl ctx) fc n none plain ts rs = Element (partOf kp (Leaf 1) ts) (SPart none plain rs)

||| A bound name that is no hole marker, read: an argument of a family's
||| value its own; any other as `siteBound` reads it.
boundName : {0 vs : Scope} -> {0 stand : Values Substitute vs} -> {0 as : List (TT vs)} ->
            (m : Mode) -> (fc : FC) -> (n : Name) -> (0 _ : Closed.markerOf n = Nothing) ->
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
          (0 _ : Reducing (MkMode (OfSite stands) kp cl ctx) a n (map (closeBy Template.substituted stand) as)
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

0 termsJoined : (xs, ys : List (Arg m stand)) -> termsOf (xs ++ ys) = termsOf xs ++ termsOf ys
termsJoined [] ys = Refl
termsJoined (x :: xs) ys = cong (x.term ::) (termsJoined xs ys)

-- The terms of a cut list are the terms of its parts.
0 partedTerms : (p : Parted args) -> termsOf args = termsOf p.front ++ termsOf p.back
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
  ||| around a call (`Closed.CallsKept`), alone, is read as both its forms
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
  lambdaSpine m@(MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) w acc stand fc x lfc rig info ty sc [] =
    case contracted (Bind fc x (Lam lfc rig info ty) sc) of
      MkContracted g steps _ => case keptAround (contractingFor m) g of
        ContractedAway => plainLambda m w acc stand fc x lfc rig info ty sc []
        KeptAround => do
          Just r <- chainLambda m w acc stand 0 fc x lfc rig info ty sc
            | Nothing => plainLambda m w acc stand fc x lfc rig info ty sc []
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
    let written = nodeOf m.keeping (Head (Just d) (rs.fst ++ fs.fst))
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
  ofDefinition m@(MkMode (OfSite stands) EveryNode cl ctx) w acc stand fc n a at args = do
    Just (k, projected, extras) <- projectedRecord n args
      | Nothing => call m w acc stand fc n a at args
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
    let written = nodeOf kp (Head (Just a) rs.fst)
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
  given m@(MkMode _ EveryNode _ _) w acc@(Access rec) placement a terms ty pargs tree written = do
    arities <- binderArities ty
    let lacking = formalsFrom 0 (drop (length terms) arities) (minus (length pargs) (length terms))
    case Element (bindParams pargs (terms ++ map substituted lacking)) Refl of
      Element Nothing _ => pure Nothing
      Element (Just (env, extras)) bound => case enter placement w of
        Nothing => pure (Just (Element (Opaque a (map substituteTemplate lacking)) GivenAgain))
        Just (Element w' less) => do
          Element (Just t) walked <- walk m w' (rec w' less) a written env tree extras
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
      normalisedArm (Step t) = Step . (.readForm) <$> readNormal EveryRedex m.inContext (applyTo t extras)
      normalisedArm (Base t) = Base . (.readForm) <$> readNormal EveryRedex m.inContext (applyTo t extras)
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
    t <- read (unfolding m) w acc [] r.readForm
    pure (Element (Just t.fst) (ULeaf r t.snd))
  -- A partial definition stops where it does not match, at every instance.
  walk m w acc self written env (Unmatched _) extras = pure (Element (Just written) UUnmatched)
  walk m w acc self written env Impossible extras = pure (Element Nothing UImpossible)
  walk m w acc self written env (Case idx p ty alts) extras =
    case Element (scrutineeOf (gamma (defsOf m.inContext)) (standsOf m) (valueAt env idx p)) Refl of
      Element (Constructed h c sargs) found =>
        (\r => Element r.fst (UConstructed found r.snd)) <$> chosen m w acc self written env h c sargs alts extras
      Element (Literal k) found => (\r => Element r.fst (ULiteral found r.snd)) <$> literal m w acc self written env k alts extras
      Element (Suspended dty da) found =>
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
  literal m w acc self written env k (ConstCase k' t :: alts) extras with (compareLiterals k' k)
    literal m w acc self written env k (ConstCase k' t :: alts) extras | SameLiteral same =
      (\r => Element r.fst (LiteralThis same r.snd)) <$> walk m w acc self written env t extras
    literal m w acc self written env k (ConstCase k' t :: alts) extras | OtherLiteral other =
      (\r => Element r.fst (LiteralPasses other r.snd)) <$> literal m w acc self written env k alts extras
    literal m w acc self written env (Db x) (ConstCase (Db x') t :: alts) extras | TwoDoubles True meets =
      (\r => Element r.fst (DoubleMeets meets r.snd)) <$> walk m w acc self written env t extras
    literal m w acc self written env (Db x) (ConstCase (Db x') t :: alts) extras | TwoDoubles False misses =
      (\r => Element r.fst (DoublePasses misses r.snd)) <$> literal m w acc self written env (Db x) alts extras
  literal m w acc self written env k (ConCase cn tag [] t :: alts) extras = case namesLiteral cn k of
    Yes named => (\r => Element r.fst (LiteralNamesType named r.snd)) <$> walk m w acc self written env t extras
    No other => (\r => Element r.fst (LiteralOtherType other r.snd)) <$> literal m w acc self written env k alts extras
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
  formedReading t@(Head (Just a) [e, rest, x]) = do
    ctx <- frozenContext
    let Just def = atAddress ctx a
      | Nothing => pure (Element t AsRead)
    case definition def of
      DCon 1 _ _ => (\r => Element (Head (Just a) [e, r.fst, Leaf 1]) (ExtentErased r.snd)) <$> formedReading rest
      _ => pure (Element t AsRead)
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

||| How a reading's form was read off its term: the host's normal form of
||| it, contracted (a type, a family, a form, a shape no constructor
||| heads), with the evidence that it is normal, which the reading lemma
||| compares an instance's normal form by; or the term as written, its
||| unknowns' solutions put in, then contracted (a dictionary, a shape a
||| constructor heads), each what a reader reads off the term
||| (`Proof.Reading.ReadOff`). A dictionary, and no other kind, that closes
||| over runtime values is the implementation the frontend's own reduction
||| finds it to be (`Closed.implementationOf`), contracted, which no
||| relation of the host's yet states.
public export
data FormFrom : State.Static -> Frozen -> ClosedTerm -> ClosedTerm -> Type where
  FromNormalForm : (r : NormalReading OfNormaliseTypes ctx t) -> FormFrom k ctx t r.readForm
  FromWritten : ReadOff OfNormaliseHoles ctx t u -> FormFrom k ctx t u
  FromImplementation : EtaContracts v u -> FormFrom ADictionary ctx t u

||| A term with its unknowns' solutions put in, as `Closed.solved` gives it,
||| with the host's steps that reach it: none where it has no unknown.
solvedIn : (ctx : Frozen) -> (t : ClosedTerm) -> Front (Subset ClosedTerm (Reduces (evaluationOf OfNormaliseHoles) ctx t))
solvedIn ctx t =
  if hasMeta t
     then (\r => Element r.value r.steps) <$> core (host.normaliseHoles ctx t)
     else pure (Element t (reducesToItself t))

||| A dictionary's form, as `classify` keys it: as written, or the
||| implementation it stands for where it depends on a runtime value.
dictionaryForm : {auto c : Ref Ctxt Defs} -> (ctx : Frozen) -> (t : ClosedTerm) -> Front (Subset ClosedTerm (FormFrom ADictionary ctx t))
dictionaryForm ctx t = do
  s <- solvedIn ctx t
  if !(runtimeDependent s.fst)
     then do
       impl <- implementationOf s.fst
       let c = contracted impl
       pure (Element c.etaForm (FromImplementation c.etaSteps))
     else
       let c = contracted s.fst in
       pure (Element c.etaForm (FromWritten (ReducedThenContracted s.snd c.etaSteps)))

||| A site's static argument read: the mode it is read in, the context of
||| which is the one every normal form and definition of the reading is
||| over, the form its reading reads and how it was read off the term in
||| that context, the template it reads as with what that says of the
||| form, and what the site writes there, the template with a form's
||| extents as its key holds them.
public export
record SiteReading (k : State.Static) (t : ClosedTerm) where
  constructor MkSiteReading
  0 mode : Mode
  form : ClosedTerm
  0 formFrom : FormFrom k mode.inContext t form
  read : Template
  0 describes : ReadAs mode [] form read
  template : Template
  0 formed : KeyForm read template

||| A term of a site's read off its normal form, in the mode's context.
normalSite : {auto c : Ref Ctxt Defs} -> {0 k : State.Static} -> (m : Mode) -> (t : ClosedTerm) -> Front (SiteReading k t)
normalSite m t = do
  n <- readNormal (contractingFor m) m.inContext t
  r <- readFromStart m n.readForm
  pure (MkSiteReading m n.readForm (FromNormalForm n) r.fst r.snd r.fst AsRead)

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
siteReading : {auto c : Ref Ctxt Defs} -> (stands : List StandIn) -> (k : State.Static) -> (t : ClosedTerm) ->
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
  r <- readFromStart (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) n.readForm
  f <- formedReading r.fst
  pure (MkSiteReading (MkMode (OfSite stands) EveryNode UnfoldsBeside ctx) n.readForm (FromNormalForm n)
                      r.fst r.snd f.fst f.snd)
siteReading stands ADictionary t = do
  ctx <- frozenContext
  d <- dictionaryForm ctx t
  r <- readFromStart (MkMode (OfSite stands) EveryNode KeepsCall ctx) d.fst
  pure (MkSiteReading (MkMode (OfSite stands) EveryNode KeepsCall ctx) d.fst d.snd r.fst r.snd r.fst AsRead)
siteReading stands AShape t = do
  ctx <- frozenContext
  s <- solvedIn ctx t
  case getFnArgs s.fst of
    (Ref _ (DataCon _ _) _, _) => do
      let c = contracted s.fst
      r <- readFromStart (MkMode (OfSite stands) Skeleton KeepsCall ctx) c.etaForm
      pure (MkSiteReading (MkMode (OfSite stands) Skeleton KeepsCall ctx) c.etaForm
                          (FromWritten (ReducedThenContracted s.snd c.etaSteps)) r.fst r.snd r.fst AsRead)
    _ => normalSite (MkMode (OfSite stands) Skeleton UnfoldsBeside ctx) t

||| What a site writes at a static argument (`siteReading`).
export
templateOf : {auto c : Ref Ctxt Defs} -> List StandIn -> State.Static -> ClosedTerm -> Front Template
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

||| A family of the writer's, applied, read at a node: by what lands at its
||| position and what beta makes of its arguments (`withClosedFamilies`).
public export
landedAs : Landing -> Beta -> (i, d : Nat) -> List Template -> Template
landedAs Computed _ i d ts = Computing i d ts
landedAs (Evaluable _) _ i d ts = Computing i d ts
landedAs (Closed _) Computes i d ts = Computing i d ts
landedAs Open Computes i d ts = Computing i d ts
landedAs (Closed k) Inert i d ts = raise k (Head Nothing ts)
landedAs Open Inert i d ts = Applied i d ts

mutual
  ||| A template read at a node, each applied family of the writer's by what
  ||| lands at its position (`Graph`). Beta of an inert family no higher
  ||| than k, applied to arguments no higher than h, is no higher than k + h
  ||| (`Proof.Bound.instHeight`): the value's meaning is a part of the
  ||| value, no higher than it. So where only closed values no higher than k land, an
  ||| applied family reads as k heads above its arguments; where values not
  ||| all closed land, it stays applied, the family's own height carried by
  ||| an arc when its arguments are closed (`appliedWeight`), and a sum of
  ||| two heights otherwise; and where a value may compute, or an argument
  ||| does, it reads as computing (`Computing`), a value nothing bounds.
  public export
  withClosedFamilies : (landing : Nat -> Landing) -> Template -> Template
  withClosedFamilies c (Applied i d ts) =
    let ts' = allWithClosed c ts in landedAs (c i) (argumentsBeta c ts') i d ts'
  withClosedFamilies c (Computing i d ts) = Computing i d (allWithClosed c ts)
  withClosedFamilies c (Head a ts) = Head a (allWithClosed c ts)
  withClosedFamilies c (Opaque a ts) = Opaque a (allWithClosed c ts)
  withClosedFamilies c (Choice t ts) = Choice (withClosedFamilies c t) (allWithClosed c ts)
  withClosedFamilies c (Field k t) = Field k (withClosedFamilies c t)
  withClosedFamilies c t@(Var _ _) = t
  withClosedFamilies c t@(Leaf _) = t
  withClosedFamilies c t@(Token _) = t
  withClosedFamilies c t@(Member _) = t
  withClosedFamilies c t@(Formal _ _) = t

  public export
  allWithClosed : (landing : Nat -> Landing) -> List Template -> List Template
  allWithClosed c [] = []
  allWithClosed c (t :: ts) = withClosedFamilies c t :: allWithClosed c ts

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
        FixedNow => asRoot <$> fixedAs def
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

-- A site's type read once: its template, as `siteReading` reads it, and
-- its root, off the same form.
typeReading : {auto c : Ref Ctxt Defs} -> List StandIn -> ClosedTerm -> Front (Template, Root)
typeReading stands t = do
  ctx <- frozenContext
  r <- siteReading stands AType t
  pure (r.template, formRoot (gamma (defsOf ctx)) r.form)

||| A static argument read once at its kind: its template (`templateOf`),
||| and its root, the definition that splits the node it is given to. A
||| dictionary's is the implementation that runs (`dictionaryRoot`). A
||| type's is the type constructor at its head, which only a family's value
||| has (`formRoot`), off the normal form its template reads; a request's
||| type parameter is a type or a family alike, so every type is read for
||| one. A form and a shape split nothing. The one reading of a site's
||| argument and of a request's, so the graph and the requests split a
||| definition by the same heads.
export
rooted : {auto c : Ref Ctxt Defs} -> List StandIn -> State.Static -> ClosedTerm -> Front (Template, Root)
rooted stands AType t = typeReading stands t
rooted stands AFamily t = typeReading stands t
rooted stands AForm t = (, Unrooted) <$> templateOf stands AForm t
rooted stands AShape t = (, Unrooted) <$> templateOf stands AShape t
rooted stands ADictionary t = (,) <$> templateOf stands ADictionary t <*> dictionaryRoot t

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

||| An instance's static argument of a kind read once in a frozen context,
||| as its link writes it: the form its key writes, how that form was read
||| off the term there, the template it reads as there with what that says
||| of the form, and its root. The context is an index, so a reading's
||| evidence is over the context its reader holds.
public export
record InstanceReading (ctx : Frozen) (k : State.Static) (t : ClosedTerm) where
  constructor MkInstanceReading
  form : ClosedTerm
  0 formFrom : FormFrom k ctx t form
  template : Template
  0 describes : ReadAs (InstanceMode ctx) [] form template
  root : Root

-- What a type is at its root, off its form (`formRoot`).
typeRoot : Frozen -> ClosedTerm -> Front Root
typeRoot ctx form = pure (formRoot (gamma (defsOf ctx)) form)

-- An instance's term read off its normal form, its root read off the form.
normalInstance : {auto c : Ref Ctxt Defs} -> {0 k : State.Static} -> (ctx : Frozen) -> (ClosedTerm -> Front Root) ->
                 (t : ClosedTerm) -> Front (InstanceReading ctx k t)
normalInstance ctx rootOfForm t = do
  n <- readNormal EveryRedex ctx t
  r <- readFromStart (InstanceMode ctx) n.readForm
  root <- rootOfForm n.readForm
  pure (MkInstanceReading n.readForm (FromNormalForm n) r.fst r.snd root)

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
readInstance : {auto c : Ref Ctxt Defs} -> (ctx : Frozen) -> (k : State.Static) -> (t : ClosedTerm) ->
               Front (InstanceReading ctx k t)
readInstance ctx AType t = normalInstance ctx (typeRoot ctx) t
readInstance ctx AFamily t = normalInstance ctx (typeRoot ctx) t
readInstance ctx AForm t = normalInstance ctx noRoot t
readInstance ctx ADictionary t = do
  d <- dictionaryForm ctx t
  r <- readFromStart (InstanceMode ctx) d.fst
  root <- dictionaryRoot t
  pure (MkInstanceReading d.fst d.snd r.fst r.snd root)
readInstance ctx AShape t = do
  s <- solvedIn ctx t
  case getFnArgs s.fst of
    (Ref _ (DataCon _ _) _, _) => do
      let c = contracted s.fst
      r <- readFromStart (InstanceMode ctx) c.etaForm
      pure (MkInstanceReading c.etaForm (FromWritten (ReducedThenContracted s.snd c.etaSteps)) r.fst r.snd Unrooted)
    _ => normalInstance ctx noRoot t

||| The definition a root names that splits the node of a request it is
||| given to: an implementation's, or the type constructor a family's value
||| applies. A request's arguments hold no marker of the growth check, so
||| no root is a `Parameter` here, and no choice the running program
||| makes, which keys nothing, so none is `Chosen`; a function that gives
||| an implementation at each use is given as written and matched where it
||| is used, so it splits nothing.
splitting : Root -> Maybe Address
splitting (Rooted j) = Just j
splitting (Chosen _) = Nothing
splitting (Gives _) = Nothing
splitting (Parameter _ _) = Nothing
splitting Unrooted = Nothing

||| A request's static argument at its kind, as the translation keeps it:
||| the form its link writes, its reading's height, and the head that
||| splits its node (`readInstance`). The same argument is given to many
||| requests, so it is read once, by its kind and its written key, and a
||| step's readings are merged into the instance table with the rest of
||| what it derived.
export
staticReading : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> State.Static -> ClosedTerm -> Front StaticReading
staticReading kind t = do
  writer <- writerOf [t]
  let written = writtenOf writer t
  case lookupFact (.readings) (kind, written) !(getState) of
    Just r => pure r
    Nothing => do
      ctx <- frozenContext
      r <- readInstance ctx kind t
      let here = MkStaticReading r.form (height r.template) (splitting r.root)
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
underOne n = lteSuccRight (lteOfEq (plusZeroRightNeutral n) lteRefl)

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
allWide ((t ** (el, wi)) :: rest) = maxLub (transitive wi.wide (maxMono lteRefl (widestAt el))) (allWide rest)

0 allHeavy : All (InSome ts) cs -> LTE (keyHeaviestOf cs) (maximum 1 (heaviestOf ts))
allHeavy [] = LTEZero
allHeavy ((t ** (el, wi)) :: rest) = maxLub (transitive wi.heavy (maxMono lteRefl (heaviestAt el))) (allHeavy rest)

-- A node of the key within a head of the template: each child within one
-- of the head's children, no more children, its own symbol no heavier.
0 nodeWithin : {x : Nat} -> {cs : List KeyTree} -> {ts : List Template} -> {a : Maybe Address} ->
               All (InSome ts) cs -> LTE (length cs) (length ts) -> LTE x (maximum 1 (heaviestOf ts)) ->
               Enclosed (KeyNode x cs) (Head a ts)
nodeWithin inside many heavy =
  MkEnclosed (LTESucc (allTall inside))
           (maxLub (transitive many (transitive (maximumLeftUpperBound _ _) (maximumRightUpperBound 1 _)))
                   (transitive (allWide inside) (maxMono lteRefl (maximumRightUpperBound _ _))))
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
substituteOwn (FormalArgument j k) = oneNode (Formal j k) lteRefl
substituteOwn Placeholding = oneNode (Leaf 1) lteRefl

0 tokenOwn : (n : Nat) -> Enclosed (KeyNode n []) (Token n)
tokenOwn n = MkEnclosed lteRefl LTEZero (maxLub (maximumRightUpperBound 1 n) LTEZero)

0 holeOwn : (i : Nat) -> Enclosed (KeyNode (S i + 0) []) (Token (S i))
holeOwn i = MkEnclosed lteRefl LTEZero (LTESucc (lteOfEq (plusZeroRightNeutral i) lteRefl))

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
               (transitive (maximumLeftUpperBound x 0) (transitive w.heavy (maxMono lteRefl (maximumLeftUpperBound _ _))))

-- A node with parts of its own, applied: one head over its parts and its
-- arguments, as the key writes it.
0 splicedWithin : {x : Nat} -> {own : List KeyTree} -> {ownT : List Template} -> {ks : List KeyTree} ->
                  {ts : List Template} -> {a : Maybe Address} ->
                  All (InSome ownT) own -> LTE (length own) (length ownT) -> LTE x 1 -> Pairwise ks ts ->
                  Enclosed (appliedTo (KeyNode x own) ks) (Head a (ownT ++ ts))
splicedWithin {x} {own} {ownT} {ks} {ts} {a} inOwn many one ps =
  replace {p = \kt => Enclosed kt (Head a (ownT ++ ts))} (sym (appliedNode x own ks)) $
    nodeWithin (allOnto (widen inOwn (\_, el => elemLeft el)) (pairwiseIn ps (\_, el => elemRight ownT el)))
               (lteOfEq (ontoLength own ps)
                  (lteOfEq (plusCommutative (length ts) (length own))
                     (lteToEq (sym (lengthJoin ownT ts)) (plusLteMonotoneRight (length ts) (length own) (length ownT) many))))
               (transitive one (maximumLeftUpperBound 1 _))

0 glyphsIn : (cs : List Char) -> ((t : Template) -> Elem t (spelt cs) -> Elem t big) -> All (InSome big) (glyphTrees cs)
glyphsIn [] inc = []
glyphsIn (_ :: cs) inc = (Leaf 1 ** (inc (Leaf 1) Here, oneNode (Leaf 1) lteRefl)) :: glyphsIn cs (\t, el => inc t (There el))

0 glyphsLength : (cs : List Char) -> length (glyphTrees cs) = length (spelt cs)
glyphsLength [] = Refl
glyphsLength (_ :: cs) = cong S (glyphsLength cs)

0 spellWithin : (cs : List Char) -> {ks : List KeyTree} -> {ts : List Template} -> Pairwise ks ts ->
                Enclosed (appliedTo (KeyNode 1 (glyphTrees cs)) ks) (Head Nothing (spelt cs ++ ts))
spellWithin cs ps = splicedWithin (glyphsIn cs (\_, el => el)) (lteOfEq (glyphsLength cs) lteRefl) lteRefl ps

0 constantWithin : (c : Constant) -> {ks : List KeyTree} -> {ts : List Template} -> Pairwise ks ts ->
                   Enclosed (appliedTo (constantTree c) ks) (appliedConstant c ts)
constantWithin (Str x) ps = spellWithin (unpack x) ps
constantWithin (Db x) ps = spellWithin (unpack (show x)) ps
constantWithin (Ch x) ps = partWithin (oneNode (Leaf 1) lteRefl) ps
constantWithin (PrT x) ps = partWithin (oneNode (Leaf 1) lteRefl) ps
constantWithin WorldVal ps = partWithin (oneNode (Leaf 1) lteRefl) ps
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
runWithin w RunZero = MkEnclosed lteRefl LTEZero lteRefl
runWithin w (RunSucc r) =
  let rec = runWithin w r in
  MkEnclosed (LTESucc (maxLub rec.high LTEZero))
           (maxLub lteRefl (maxLub rec.wide LTEZero))
           (maxLub lteRefl (maxLub rec.heavy LTEZero))

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
  spineWithin w (SDot {r} ru rs) = splicedWithin [(r ** (Here, readWithin w ru))] lteRefl lteRefl (allWithin w rs)
  spineWithin w (SPlaceholder rs) = partWithin (oneNode (Leaf 1) lteRefl) (allWithin w rs)
  spineWithin w (SImpossible rs) = partWithin (oneNode (Leaf 1) lteRefl) (allWithin w rs)
  spineWithin {env} w (SLocal {idx} {p} rs) = partWithin (substituteOwn (valueAt env idx p)) (allWithin w rs)
  spineWithin w (SMeta ms rs) =
    let pms = allWithin w ms in
    splicedWithin (pairwiseIn pms (\_, el => el)) (lteOfEq (pairwiseLength pms) lteRefl) lteRefl (allWithin w rs)
  spineWithin w (SUniverse rs) = partWithin (oneNode (Leaf 1) lteRefl) (allWithin w rs)
  spineWithin w (SConstant {c} rs) = constantWithin c (allWithin w rs)
  spineWithin w (SLambda {ps} {t} {s} pa rt rsc rs) =
    let o = passingWithin w pa in
    splicedWithin ((s ** (elemRight ps (There Here), readWithin w rsc)) :: widen o.inside (\_, el => elemLeft el))
                  (lteToEq (sym (lengthJoin ps [t, s]))
                     (lteToEq (plusCommutative 2 (length ps)) (lteSuccRight (LTESucc o.many))))
                  lteRefl (allWithin w rs)
  spineWithin w (SBinder {ps} {s} ba rsc rs) =
    let o = binderWithin w ba in
    splicedWithin ((s ** (elemRight ps Here, readWithin w rsc)) :: widen o.inside (\_, el => elemLeft el))
                  (lteToEq (sym (lengthJoin ps [s])) (lteToEq (plusCommutative 1 (length ps)) (LTESucc o.many)))
                  lteRefl (allWithin w rs)
  spineWithin w (SDelayed {t} ru rs) = splicedWithin [(t ** (Here, readWithin w ru))] lteRefl lteRefl (allWithin w rs)
  spineWithin w (SDelay {t} {v} rty ra rs) =
    splicedWithin [(t ** (Here, readWithin w rty)), (v ** (There Here, readWithin w ra))] lteRefl lteRefl (allWithin w rs)
  spineWithin w (SForce {t} ru rs) = splicedWithin [(t ** (Here, readWithin w ru))] lteRefl lteRefl (allWithin w rs)
  spineWithin w (SAs {t} {v} ra rp rs) =
    splicedWithin [(t ** (Here, readWithin w ra)), (v ** (There Here, readWithin w rp))] lteRefl lteRefl (allWithin w rs)
  spineWithin w (SHole {fc} {n} {i} found rs) =
    headChanged (markerNode w fc n found) (partWithin (holeOwn i) (allWithin w rs))
  spineWithin w (SFormal {fc} {n} {j} {k} none _ rs) =
    headChanged (unmarkedNode w fc n none) (partWithin (oneNode (Formal j k) lteRefl) (allWithin w rs))
  spineWithin w (SPart {fc} {n} none _ rs) =
    headChanged (unmarkedNode w fc n none) (partWithin (oneNode (Leaf 1) lteRefl) (allWithin w rs))
  spineWithin w (SNoDefinition _ rs) = partWithin (oneNode (Leaf 1) lteRefl) (allWithin w rs)
  spineWithin w (SData _ rs) = splicedWithin [] LTEZero lteRefl (allWithin w rs)
  spineWithin w (STypeCon _ rs) = splicedWithin [] LTEZero lteRefl (allWithin w rs)
  spineWithin w (SKept _ rs) = splicedWithin [] LTEZero lteRefl (allWithin w rs)
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
  passingWithin w (PDefault {r} rd) = MkOwn [(r ** (Here, readWithin w rd))] lteRefl

  0 binderWithin : (w : Writer) -> BinderAs (InstanceMode ctx) env b ps -> Own (binderTrees w b) ps
  binderWithin w (BLet {tv} {t} rv rt) =
    MkOwn [(tv ** (Here, readWithin w rv)), (t ** (There Here, readWithin w rt))] lteRefl
  binderWithin w (BPi {ps} {t} pa rt) =
    let o = passingWithin w pa in
    MkOwn ((t ** (elemRight ps Here, readWithin w rt)) :: widen o.inside (\_, el => elemLeft el))
          (lteToEq (sym (lengthJoin ps [t])) (lteToEq (plusCommutative 1 (length ps)) (LTESucc o.many)))
  binderWithin w (BPVar {ps} {t} pa rt) =
    let o = passingWithin w pa in
    MkOwn ((t ** (elemRight ps Here, readWithin w rt)) :: widen o.inside (\_, el => elemLeft el))
          (lteToEq (sym (lengthJoin ps [t])) (lteToEq (plusCommutative 1 (length ps)) (LTESucc o.many)))
  binderWithin w (BPLet {tv} {t} rv rt) =
    MkOwn [(tv ** (Here, readWithin w rv)), (t ** (There Here, readWithin w rt))] lteRefl
  binderWithin w (BPVTy {t} rt) = MkOwn [(t ** (Here, readWithin w rt))] lteRefl

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
  ChainUnsaid : (0 _ : Closed.markerOf n = Nothing) -> ChainShape ctx (Ref fc Bound n) 1
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
  chainReads c (ARun {n} r) = replace {p = CapRead (Leaf (S n))} (sym (runShaped r c)) (MkCapRead lteRefl LTEZero LTEZero)
  chainReads c (ASpine s) = chainSpine c s

  0 chainSpine : ChainShape cx u h -> SpineAs (InstanceMode ctx) env u [] t -> CapRead t h
  chainSpine ChainEnd (SData _ []) = MkCapRead lteRefl LTEZero LTEZero
  chainSpine (ChainStep c) (SApp (SData _ (r :: []))) =
    let inner = chainReads c r in
    MkCapRead (LTESucc (maxLub inner.high LTEZero))
              (maxLub lteRefl (maxLub inner.narrow LTEZero))
              (maxLub inner.light LTEZero)
  chainSpine ChainCut (SImpossible []) = MkCapRead lteRefl LTEZero LTEZero
  chainSpine ChainErased (SPlaceholder []) = MkCapRead lteRefl LTEZero LTEZero
  chainSpine (ChainUnsaid none) (SHole found _) = void (nothingNotJust (trans (sym none) found))
  chainSpine (ChainUnsaid none) (SFormal _ _ []) = MkCapRead lteRefl LTEZero LTEZero
  chainSpine (ChainUnsaid none) (SPart _ _ []) = MkCapRead lteRefl LTEZero LTEZero
  chainSpine (ChainUnknown _) (SNoDefinition _ []) = MkCapRead lteRefl LTEZero LTEZero
  chainSpine (ChainUnknown _) (SKept _ []) = MkCapRead lteRefl LTEZero LTEZero

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
chainReduces (ChainUnknown nowhere) r = case undefinedReduces nowhere r of
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
shapeForm c (FromWritten (ReducedThenContracted r k)) = rewrite chainContracted (chainReduces c r) k in chainReduces c r

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
    (keyedWithin w r lteRefl lteRefl lteRefl)

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
||| the site's writer holds (`MarkersHold`), every reading of the site's
||| term with those values put in, as an instance's key reads it, is what
||| the site's template writes (`Proof.Bound.Writes`). It is proved by
||| induction on the site's reading, the host's reduction inverted at each
||| head it keeps (`Proof.Inversion`), carried through putting the values
||| in (`Idris.Host.Mapped`, `Idris.Host.mappedReduces`) and through
||| contraction (`Proof.Reading`).
public export
0 ReadingCovers : {g : Graph} -> (m : Model g) -> Bound.Site g.size -> List StandIn -> (k : State.Static) -> (t : ClosedTerm) ->
                  SiteReading k t -> Type
ReadingCovers m s stands k t r =
  {0 ns : Scope} -> (mk : Markers r.mode.inContext ns) -> (vs : SubstEnv ns []) ->
  MarkersHold m s r.mode.inContext stands mk.bounds vs ->
  (inst : InstanceReading r.mode.inContext k (putIn SizeOf.zero (mkSizeOf ns) mk.bounds vs t)) ->
  Writes m s r.template inst.template

||| What a site of the model writes at a request's argument, of any kind,
||| from the reading lemma at the site the request read: the site's
||| template is its reading's, and the lemma gives what it writes at the
||| instance's reading of the argument.
export
0 siteWritesFrom : {g : Graph} -> {m : Model g} -> {p : Fin g.size} -> (s : SiteOf m p) -> (r : SiteReading k t) ->
                   s.site.template = r.template -> ReadingCovers m s.site stands k t r ->
                   (mk : Markers r.mode.inContext ns) -> (vs : SubstEnv ns []) ->
                   MarkersHold m s.site r.mode.inContext stands mk.bounds vs ->
                   (inst : InstanceReading r.mode.inContext k (putIn SizeOf.zero (mkSizeOf ns) mk.bounds vs t)) ->
                   SiteWrites m p inst.template
siteWritesFrom s r same covers mk vs held inst = siteWritten s (rewrite same in covers mk vs held inst)
