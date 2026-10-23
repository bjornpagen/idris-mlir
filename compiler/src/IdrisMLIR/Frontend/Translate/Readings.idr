-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The readings an instance is keyed by, and the relations they are built
||| of: the kinds of static argument, the markers a reading reads, how a
||| term is read (`ReadAs`, over a `Mode`), how a reading's form was read
||| off its term (`FormFrom`), its root (`Root`), and an instance's
||| reading of a static argument (`InstanceReading`). They are relations
||| and the pure functions their types name, and run none of the
||| frontend's computation, so they sit below the translation's state,
||| whose readings cache and requests hold an instance's reading beside the
||| key it was read for; the readers (`Growth.Template`) and the closed
||| terms' reductions (`Translate.Closed`) sit above it and read them from
||| here.
module IdrisMLIR.Frontend.Translate.Readings

import Core.Case.CaseTree
import Core.Context
import Core.TT
import Idris.Host
import Libraries.Data.List.SizeOf

import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Frontend.Translate.Contraction
import IdrisMLIR.Frontend.Translate.Definitions
import IdrisMLIR.Frontend.Translate.Literals
import IdrisMLIR.Proof.Forms
import IdrisMLIR.Proof.Reading
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template

import Data.DPair
import Data.List
import Data.List1
import Data.Vect

%default total

-- The evaluator's relation names its forms and steps as this module names
-- a template's nodes and a static argument's kind; here each name is
-- always the frontend's.
%hide Idris.Host.Head
%hide Idris.Host.Applied
%hide Idris.Host.Beta
%hide Idris.Host.Computes
%hide Idris.Host.AType
%hide Idris.Host.delayed

------------------------------------------------------------------------------
-- The kinds of static argument
------------------------------------------------------------------------------

||| How a static argument keys its instance, as classify's PKind: a type
||| (TypeParam), a type family (TypeParam too: a type parameter whose kind
||| is a function into a universe, `tm : Scope -> Type` or a functor's `f`,
||| whose value is a type constructor applied to fewer arguments than it
||| takes, or a lambda), an implementation (DictParam), a form (FormParam),
||| a shape (ValueParam). A family and an implementation are the kinds whose
||| value's head splits the definition it is given to (`Root`).
public export
data Static = AType | AFamily | ADictionary | AForm | AShape

-- The kinds in one order, so that a table can be keyed by kind.
kindOrder : Static -> Nat
kindOrder AType = 0
kindOrder AFamily = 1
kindOrder ADictionary = 2
kindOrder AForm = 3
kindOrder AShape = 4

export
Eq Static where
  x == y = kindOrder x == kindOrder y

export
Ord Static where
  compare x y = compare (kindOrder x) (kindOrder y)

------------------------------------------------------------------------------
-- The markers
------------------------------------------------------------------------------

||| The name of marker `i` (`holeMarker`'s): a probe (`ProbeHole`), which
||| passes through every normaliser, under every binder, as itself.
export
markerName : Nat -> Name
markerName i = probeName (ProbeHole i)

||| The number of the marker a name is, if it is one (`markerName`'s).
export
markerOf : Name -> Maybe Nat
markerOf n = case probeOf n of
  Just (ProbeHole i) => Just i
  _ => Nothing

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

||| The marker `Formal j a` reads back from: argument j of a family's
||| value, which takes a arguments of its own. A lambda's variable is one,
||| and so is each argument a definition given fewer than its parameters
||| lacks, so that what the value computes from its arguments is read where
||| beta puts them. Nothing matches it deeper: a match on it leaves the
||| value as written (`walk`).
formalAt : (j, a : Nat) -> Term vs
formalAt j a = probeTerm (ProbeFormal j a)

------------------------------------------------------------------------------
-- What a term mentions
------------------------------------------------------------------------------

||| Whether a term holds a part a test picks: one somewhere in it, or none.
||| The view a caller that chooses by it matches on.
public export
data Mention = Mentioned | Unmentioned

||| Mentioned where either is, the second looked at only where the first is
||| not.
export
orMention : Mention -> Lazy Mention -> Mention
orMention Mentioned _ = Mentioned
orMention Unmentioned m = m

||| The machine's test at one part, read as the view.
export
asMention : Bool -> Mention
asMention True = Mentioned
asMention False = Unmentioned

||| Whether a subterm the test picks is in a term: the term, its binders'
||| types and values, an application's parts, a pattern's value, what a
||| delay holds, a metavariable's arguments.
export
mentioning : ({0 vs : Scope} -> Term vs -> Mention) -> Term vars -> Mention
mentioning p tm = orMention (p tm) (parts tm)
  where
    anyOf : List (Term vs) -> Mention
    anyOf [] = Unmentioned
    anyOf (t :: ts) = orMention (mentioning p t) (anyOf ts)

    binder : Binder (Term vs) -> Mention
    binder (Lam _ _ _ ty) = mentioning p ty
    binder (Let _ _ v ty) = orMention (mentioning p ty) (mentioning p v)
    binder (Pi _ _ _ ty) = mentioning p ty
    binder (PVar _ _ _ ty) = mentioning p ty
    binder (PLet _ _ v ty) = orMention (mentioning p ty) (mentioning p v)
    binder (PVTy _ _ ty) = mentioning p ty

    parts : Term vs -> Mention
    parts (Bind _ _ b sc) = orMention (binder b) (mentioning p sc)
    parts (App _ f a) = orMention (mentioning p f) (mentioning p a)
    parts (As _ _ _ pat) = mentioning p pat
    parts (TDelayed _ _ t) = mentioning p t
    parts (TDelay _ _ t a) = orMention (mentioning p t) (mentioning p a)
    parts (TForce _ _ t) = mentioning p t
    parts (Meta _ _ _ args) = anyOf args
    parts _ = Unmentioned

||| Does a subterm satisfy the test (`mentioning`)?
export
mentions : ({0 vs : Scope} -> Term vs -> Bool) -> Term vars -> Bool
mentions p tm = mentioned (mentioning (\t => asMention (p t)) tm)
  where
    mentioned : Mention -> Bool
    mentioned Mentioned = True
    mentioned Unmentioned = False

||| Does a term mention a metavariable? Idris can leave a solved one in an
||| elaborated term (the implementation for the inner pair of a triple).
export
hasMeta : TT vars -> Bool
hasMeta = mentions metaTerm
  where
    metaTerm : TT vs -> Bool
    metaTerm (Meta {}) = True
    metaTerm _ = False

||| How a term's unknowns were solved, kept whole: it holds none, and is
||| itself; or it holds one, and is the normal form the normaliser that
||| applies lambdas and fills in solutions gives, with that normaliser's
||| steps and the evidence that it takes none further. The translation's
||| argument as written and a growth reading's term are solved by the one
||| function that gives this (`Closed.solving`), so a proof relating the
||| two holds which case each is in rather than relating two solvers. It
||| sits here, below the readings, so that a reading read off a term as
||| written keeps the solving itself (`FormFrom`), not its steps alone.
public export
data Solved : Frozen -> ClosedTerm -> ClosedTerm -> Type where
  NoUnknown : (0 _ : hasMeta t = False) -> Solved ctx t t
  SolvedBy : (0 _ : hasMeta t = True) -> (0 r : Reduct OfNormaliseHoles ctx t) -> Solved ctx t r.value

||| The steps a solving took: none where the term holds no unknown.
export
0 solvedSteps : Solved ctx t s -> Reduces (evaluationOf OfNormaliseHoles) ctx t s
solvedSteps (NoUnknown {t} _) = reducesToItself t
solvedSteps (SolvedBy _ r) = r.steps

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
public export
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

-- Its own namespace, since the terms read in turn (`AllReadAs`) are a list
-- too, and one module holds one `Nil` per namespace.
namespace Values
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
public export
extend : Values a xs -> Values a ys -> Values a (xs ++ ys)
extend [] ys = ys
extend (x :: xs) ys = x :: extend xs ys

||| The parameters of a definition, the first argument first, and the
||| arguments past them; nothing when it is applied to fewer.
public export
bindParams : (vs : Scope) -> List a -> Maybe (Values a vs, List a)
bindParams [] as = Just ([], as)
bindParams (_ :: vs) (a :: as) = map (\(env, rest) => (a :: env, rest)) (bindParams vs as)
bindParams (_ :: _) [] = Nothing

||| A constructor's arguments bound to what it was applied to; nothing when
||| they are not as many.
public export
bindEach : (ns : List Name) -> List a -> Maybe (Values a ns)
bindEach [] [] = Just []
bindEach (_ :: ns) (x :: xs) = (x ::) <$> bindEach ns xs
bindEach _ _ = Nothing

||| Every argument of an alternative bound to one value.
export
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
closeBy : (a -> ClosedTerm) -> Values a vs -> Term vs -> ClosedTerm
closeBy {vs} f env tm = substs (sizeOfValues env) (substEnv f env) (rewrite appendNilRightNeutral vs in tm)

||| A term with what each of its variables stands for.
export
close : Values ClosedTerm vs -> Term vs -> ClosedTerm
close = closeBy id

placeholders : (vs : Scope) -> Values ClosedTerm vs
placeholders [] = []
placeholders (_ :: vs) = Erased EmptyFC Placeholder :: placeholders vs

||| A term under binders, each binder's variable a placeholder, which no
||| reading looks into: what a part under a binder is when it is
||| substituted into a definition.
export
closedOver : {vs : Scope} -> Term vs -> ClosedTerm
closedOver tm = close (placeholders vs) tm

export
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
||| closes over (`Readings.markerName`), with the evidence either way.
public export
data HoleView : Name -> Type where
  IsHole : (i : Nat) -> (0 _ : Readings.markerOf n = Just i) -> HoleView n
  NotHole : (0 _ : Readings.markerOf n = Nothing) -> HoleView n

export
holeView : (n : Name) -> HoleView n
holeView n with (Readings.markerOf n) proof found
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
public export
data Reference = HoleMarker Nat
               | FormalMarker Nat Nat
               | PartMarker Nat (List Nat)
               | FieldMarker Nat (List1 Nat)
               | RuntimePart
               | DataConstructor (Maybe Address)
               | TypeConstructor (Maybe Address)
               | AtDefinition Address

export
referenceOf : Context -> List StandIn -> NameType -> Name -> Reference
referenceOf ctx stands Bound n = case Readings.markerOf n of
  Just i => HoleMarker i
  Nothing => case probeOf n of
    Just (ProbeFormal j a) => FormalMarker j a
    Just (ProbeFieldPath i path) => FieldMarker i path
    Just q => maybe RuntimePart (uncurry PartMarker) (partOfProbe stands q)
    Nothing => RuntimePart
referenceOf ctx stands (DataCon _ _) n = DataConstructor (definitionAddress ctx n)
referenceOf ctx stands (TyCon _) n = TypeConstructor (definitionAddress ctx n)
referenceOf ctx stands Func n = maybe RuntimePart AtDefinition (definitionAddress ctx n)

------------------------------------------------------------------------------
-- How a term is read
------------------------------------------------------------------------------

||| What a reading keeps of a part: a type's (or a dictionary's) every node,
||| or a value's skeleton, in which every part that is no data constructor
||| is one hole (`skeleton` makes it `Erased`). These are two cases of the
||| problem, and the one distinction an unfolding carries.
public export
data Keeping = EveryNode | Skeleton

mutual
  ||| A term's skeleton, as a shape's key holds it (`Closed.skeleton`): the
  ||| data constructor that heads it, applied to each argument's own
  ||| skeleton, every argument that has none (no data constructor heads it)
  ||| cut to one hole, the runtime probe. A hole stands for the node it cut,
  ||| as a site's reading of a shape reads a part that is no data
  ||| constructor as one hole (`nodeOf Skeleton`). Only a term a data
  ||| constructor heads has a skeleton.
  public export
  data SkeletonOf : ClosedTerm -> ClosedTerm -> Type where
    SkeletonHead : SkeletonOf (Ref fc (DataCon tag arity) n) (Ref fc (DataCon tag arity) n)
    SkeletonApplied : SkeletonOf f f' -> ArgumentCut a a' -> SkeletonOf (App fc f a) (App fc f' a')

  ||| An argument of a skeleton: its own skeleton, or, where it has none, the
  ||| hole that stands for it.
  public export
  data ArgumentCut : ClosedTerm -> ClosedTerm -> Type where
    ArgumentKept : SkeletonOf a a' -> ArgumentCut a a'
    ArgumentCutAt : (0 _ : (s : ClosedTerm) -> Not (SkeletonOf a s)) -> ArgumentCut a (probeTerm ProbeRuntime)

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

||| A constant as the key writes it (`Literals.writeConstant`): a string and a
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

------------------------------------------------------------------------------
-- What a match meets
------------------------------------------------------------------------------

||| A term a constructor heads, as a match meets it: a data constructor of
||| its tag, or a type constructor, applied to its fields, with the host's
||| evidence of the spine (`Idris.Host.Spine`).
public export
data HeadedAs : ConstructorHead -> Name -> List (Term vs) -> Term vs -> Type where
  DataHeaded : Spine s (Ref rfc (DataCon tag arity) c) fields -> HeadedAs (DataHead tag) c fields s
  FamilyHeaded : Spine s (Ref rfc (TyCon arity) c) fields -> HeadedAs FamilyHead c fields s

||| What a match meets, parsed once, with what the host's step meets there
||| where it takes or passes an alternative by it: through the term's dots
||| (`Idris.Host.Shows`), a data or type constructor applied, a literal or
||| a delay. Besides, a part of the writer's parameter (by its parameter
||| and path), an argument of a family's value, a runtime value (a part
||| every reading takes as one node, or a hole marker), or anything else:
||| an application stuck in turn, a projection of what is no constructor,
||| an applied marker, a field of the writer's dictionary.
public export
data Scrutinee : ClosedTerm -> Type where
  Constructed : (h : ConstructorHead) -> (c : Name) -> (sargs : List ClosedTerm) ->
                {0 u : ClosedTerm} -> (0 _ : Shows s u) -> (0 _ : HeadedAs h c sargs u) -> Scrutinee s
  Literal : (k : Constant) -> {0 fc : FC} -> (0 _ : Shows s (PrimVal fc k)) -> Scrutinee s
  Suspended : (dty, da : ClosedTerm) -> {0 fc : FC} -> {0 r : LazyReason} -> (0 _ : Shows s (TDelay fc r dty da)) -> Scrutinee s
  Matched : Nat -> List Nat -> Scrutinee s
  OnFormal : Nat -> Nat -> Scrutinee s
  AtRuntime : Scrutinee s
  StuckInTurn : Scrutinee s

-- What a match meets at a head applied to arguments, the term shown
-- through its dots.
headedScrutinee : Context -> List StandIn -> {0 s, u : ClosedTerm} -> (0 _ : Shows s u) ->
                  (h : ClosedTerm) -> (args : List ClosedTerm) -> (0 _ : Spine u h args) -> Scrutinee s
headedScrutinee ctx stands shown (Ref _ (DataCon tag _) n) args sp = Constructed (DataHead tag) n args shown (DataHeaded sp)
headedScrutinee ctx stands shown (Ref _ (TyCon _) n) args sp = Constructed FamilyHead n args shown (FamilyHeaded sp)
headedScrutinee ctx stands shown (Ref _ nt n) args sp = case (referenceOf ctx stands nt n, args) of
  (PartMarker i path, []) => Matched i path
  (FormalMarker j a, []) => OnFormal j a
  (RuntimePart, _) => AtRuntime
  (HoleMarker _, _) => AtRuntime
  _ => StuckInTurn
headedScrutinee ctx stands shown (PrimVal _ k) [] sp = Literal k (shownAlone shown sp)
headedScrutinee ctx stands shown (TDelay _ _ ty a) [] sp = Suspended ty a (shownAlone shown sp)
headedScrutinee ctx stands shown (Erased _ Placeholder) args sp = AtRuntime
headedScrutinee ctx stands shown (Erased _ Impossible) args sp = AtRuntime
headedScrutinee ctx stands shown (Meta {}) args sp = AtRuntime
headedScrutinee ctx stands shown _ args sp = StuckInTurn

||| What a match meets: the term shown through its dots (`Proof.Reading.shownOf`),
||| read as its head applied to its arguments (`Proof.Reading.spineOf`), each
||| with the host's evidence, which the match's alternatives are taken by.
export
scrutineeOf : Context -> List StandIn -> (s : ClosedTerm) -> Scrutinee s
scrutineeOf ctx stands s =
  let Element u shown = shownOf s
      MkSpineOf h args sp = spineOf u in
  headedScrutinee ctx stands shown h args sp

------------------------------------------------------------------------------
-- Structural recursions
------------------------------------------------------------------------------

||| An alternative of a recursion on a Nat-like argument, one level deep:
||| the successor's leaf, which may recur, or another's (the zero's, the
||| default's), which must be closed.
public export
data Arm = Step ClosedTerm | Base ClosedTerm

||| The other leaves of a structural recursion, and the closed children of
||| its successor's leaf, when it is one. The successor's leaf is a
||| recursive call, or a data or type constructor applied to children each
||| of which is a recursive call or closed; every recursive call takes a
||| predecessor marker at the matched position and every other argument as
||| it came; every other leaf is closed; and at least one call recurs.
||| Closed means: no marker of the walk's, no mention of the definition. A
||| predecessor is a part of the matched parameter one match deeper, told
||| by its parameter and depth (`partDepth`), whichever field it is.
export
recursion : Context -> List StandIn -> (self : Address) -> (predecessor : (Nat, Nat)) -> (args : List ClosedTerm) ->
            (idx : Nat) -> List Arm -> Maybe (List ClosedTerm, List ClosedTerm)
recursion ctx stands self predecessor args idx arms = case go arms of
  Just (bases, kids, S _) => Just (bases, kids)
  _ => Nothing
  where
    refersOut : {0 vs : Scope} -> Term vs -> Bool
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
public export
unfolding : Mode -> Mode
unfolding (MkMode w k KeepsCall ctx) = MkMode w k UnfoldsBeside ctx
unfolding m = m

||| The stand-ins a mode reads, a site's; an instance's term holds none.
public export
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

||| Which eta-redexes a reading's normal forms are contracted at: a site's
||| type, read beside the unfoldings of its calls, keeps a redex around a
||| call (`Contraction.CallsKept`), which it reads as both its forms (`SEta`);
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
  data ReadAs : Mode -> Values Substitute vs -> Term vs -> Template -> Type where
    ||| A closed run of a successor: its height.
    ARun : Run u n -> ReadAs m env u (Leaf (S n))
    ||| Any other term, read by its head.
    ASpine : SpineAs m env u [] t -> ReadAs m env u t

  ||| Terms read, each in turn.
  public export
  data AllReadAs : Mode -> Values Substitute vs -> List (Term vs) -> List Template -> Type where
    Nil : AllReadAs m env [] []
    (::) : ReadAs m env a t -> AllReadAs m env as ts -> AllReadAs m env (a :: as) (t :: ts)

  ||| A term applied to arguments, read by its head: a node of the key holds
  ||| the head's own parts and the arguments the head is applied to.
  public export
  data SpineAs : Mode -> Values Substitute vs -> Term vs -> List (Term vs) -> Template -> Type where
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
    SLambda : PassingAs m env info ps -> ReadAs m env ty t -> ReadAs m (FormalArgument (List.length vs) k :: env) sc s ->
              AllReadAs m env as ts ->
              SpineAs m env (Bind fc x (Lam lfc rig info ty) sc) as (nodeOf m.keeping (Head Nothing ((ps ++ [t, s]) ++ ts)))
    SBinder : BinderAs m env b ps -> ReadAs m (Placeholding :: env) sc s -> AllReadAs m env as ts ->
              SpineAs m env (Bind fc x b sc) as (nodeOf m.keeping (Head Nothing ((ps ++ [s]) ++ ts)))
    ||| A lambda chain a site's type keeps around a call
    ||| (`Contraction.CallsKept`), alone: both its forms (`keptChain`), the call
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
    SHole : (0 _ : Readings.markerOf n = Just i) -> AllReadAs m env as ts ->
            SpineAs m env (Ref fc Bound n) as (partOf m.keeping (Token (S i)) ts)
    ||| Argument j of a family's value, which beta substitutes.
    SFormal : (0 _ : Readings.markerOf n = Nothing) -> (0 _ : probeOf n = Just (ProbeFormal j k)) ->
              AllReadAs m env as ts -> SpineAs m env (Ref fc Bound n) as (partOf m.keeping (Formal j k) ts)
    ||| One of the writer's markers, in a site's term.
    SMarker : (0 _ : walkMarker stands n = Just t) -> AllReadAs (MkMode (OfSite stands) kp cl ctx) env as ts ->
              SpineAs (MkMode (OfSite stands) kp cl ctx) env (Ref fc Bound n) as (markedOf t ts)
    ||| Any other bound name, which is no argument of a family's value: a
    ||| runtime part, one node.
    SPart : (0 _ : Readings.markerOf n = Nothing) -> (0 _ : NotFormal n) -> AllReadAs m env as ts ->
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
              Reducing (MkMode (OfSite stands) kp cl ctx) a n (map (closeBy Readings.substituted env) as) (nodeOf kp (Head (Just a) ts)) t ->
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
              Reducing (MkMode (OfSite stands) kp WalksAlone ctx) a n (map (closeBy Readings.substituted env) as) (nodeOf kp (Head (Just a) ts)) t ->
              SpineAs (MkMode (OfSite stands) kp WalksAlone ctx) env (Ref fc Func n) as t

  ||| What a binder's implicitness holds: a default, which the key writes.
  public export
  data PassingAs : Mode -> Values Substitute vs -> PiInfo (Term vs) -> List Template -> Type where
    PImplicit : PassingAs m env Implicit []
    PExplicit : PassingAs m env Explicit []
    PAuto : PassingAs m env AutoImplicit []
    PDefault : ReadAs m env d r -> PassingAs m env (DefImplicit d) [r]

  ||| A binder's parts, of a binder that is no lambda (`NodeBinder`): its
  ||| default, its type, and a `let`'s value.
  public export
  data BinderAs : Mode -> Values Substitute vs -> Binder (Term vs) -> List Template -> Type where
    BLet : ReadAs m env v tv -> ReadAs m env ty t -> BinderAs m env (Let fc rig v ty) [tv, t]
    BPi : PassingAs m env info ps -> ReadAs m env ty t -> BinderAs m env (Pi fc rig info ty) (ps ++ [t])
    BPVar : PassingAs m env info ps -> ReadAs m env ty t -> BinderAs m env (PVar fc rig info ty) (ps ++ [t])
    BPLet : ReadAs m env v tv -> ReadAs m env ty t -> BinderAs m env (PLet fc rig v ty) [tv, t]
    BPVTy : ReadAs m env ty t -> BinderAs m env (PVTy fc rig ty) [t]

  ||| A lambda chain a site keeps around a call (`Contraction.CallsKept`), read
  ||| down to the call: under each lambda, its implicitness and its type,
  ||| its variable an argument of the value (`Formal`), as a lambda is read;
  ||| at the call, its own arguments, and what an instance that unfolds it
  ||| makes of it (`CallUnfolds`), under the lambdas; nothing where no
  ||| instance unfolds it.
  public export
  data EtaChain : Mode -> Values Substitute vs -> Term vs -> Address -> List Template -> Maybe Template -> Type where
    ChainLambda : PassingAs m env info ps -> ReadAs m env ty t ->
                  EtaChain m (FormalArgument (List.length vs) k :: env) sc a ts r ->
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
  data CallUnfolds : Mode -> Values Substitute vs -> Term vs -> List (Term vs) -> Address -> List Template ->
                     Maybe Template -> Type where
    UnfoldsApplied : CallUnfolds m env f (a :: as) d ts r -> CallUnfolds m env (App fc f a) as d ts r
    CallWalked : (0 _ : AddressedAs m n (Just d)) -> AllReadAs m env own ts -> AllReadAs m env vars fs ->
                 Reducing m d n (map (closeBy Readings.substituted env) (own ++ vars)) (nodeOf m.keeping (Head (Just d) (ts ++ fs))) t ->
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
  public export
  data Reducing : Mode -> Address -> Name -> List ClosedTerm -> (written : Template) -> Template -> Type where
    ||| Its case tree walked over its arguments.
    ByWalk : (0 _ : Defines m.inContext n def) -> (0 _ : definition def = PMDef info pargs body) -> (0 _ : TreeOf body tree) ->
             (0 _ : bindParams pargs terms = Just (env, extras)) -> Unfolds m a written env tree extras (Just t) ->
             Reducing m a n terms written t
    ||| A recursion structural on a Nat-like argument: the argument raised
    ||| by its leaves.
    ByStructure : {0 extras : List ClosedTerm} ->
                  (0 _ : Defines m.inContext n def) -> (0 _ : definition def = PMDef info pargs body) -> (0 _ : TreeOf body tree) ->
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
  public export
  data GivenUnfolds : Mode -> Address -> (written : Template) -> List ClosedTerm -> (pargs : Scope) -> CaseTree pargs ->
                      Template -> Type where
    GivenWalked : (0 _ : bindParams pargs (terms ++ map Readings.substituted lacking) = Just (env, extras)) ->
                  Unfolds m a written env tree extras (Just t) -> GivenUnfolds m a written terms pargs tree t
    GivenAgain : GivenUnfolds m a written terms pargs tree (Opaque a (map Readings.substituteTemplate lacking))

  ||| A recursion structural on a part of the writer's parameter j at
  ||| `path`, which reads as `Var j (length path)`, a Nat-like argument
  ||| every recursive call takes a predecessor of: its other leaves, and the
  ||| marker raised by the tallest of them and of the successor's closed
  ||| children, less one. Its shape is what `recursion` found in its arms,
  ||| which the bound rests on.
  public export
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
  public export
  data Unfolds : Mode -> (self : Address) -> (written : Template) -> Values ClosedTerm vs -> CaseTree vs ->
                 List ClosedTerm -> Maybe Template -> Type where
    ULeaf : (0 r : MaximalReading (contractingFor (unfolding m)) m.inContext (applyTo (close env rhs) extras)) ->
            ReadAs (unfolding m) [] r.reading.readForm t -> Unfolds m self written env (STerm i rhs) extras (Just t)
    UUnmatched : Unfolds m self written env (Unmatched msg) extras (Just written)
    UImpossible : Unfolds m self written env Impossible extras Nothing
    UConstructed : (0 _ : scrutineeOf (gamma (defsOf m.inContext)) (standsOf m) (valueAt env idx p) = Constructed h c sargs shown headed) ->
                   TakenBy m self written env h c sargs alts extras r ->
                   Unfolds m self written env (Case idx p ty alts) extras r
    ULiteral : (0 _ : scrutineeOf (gamma (defsOf m.inContext)) (standsOf m) (valueAt env idx p) = Literal k shown) ->
               TakesLiteral m self written env k alts extras r -> Unfolds m self written env (Case idx p ty alts) extras r
    USuspended : (0 _ : scrutineeOf (gamma (defsOf m.inContext)) (standsOf m) (valueAt env idx p) = Suspended dty da shown) ->
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
  public export
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
  ||| (`Idris.Host.Picks`): the first of a constant equal to it, or of the
  ||| primitive type it is, or a default, past every alternative the host
  ||| misses (another constant, a primitive type the literal is not, an
  ||| alternative that binds fields); the definition as written where the
  ||| host's walk is stuck, at a delay's alternative, or where none is left.
  ||| Constants are compared by the evaluator's own comparison
  ||| (`Idris.Host.ByConstant`, `Idris.Host.OtherConstant`), each type's
  ||| equality, never by their syntax: two doubles equal but spelt apart
  ||| meet, and a NaN meets none.
  public export
  data TakesLiteral : Mode -> (self : Address) -> (written : Template) -> Values ClosedTerm vs -> Constant ->
                      List (CaseAlt vs) -> List ClosedTerm -> Maybe Template -> Type where
    LiteralMeets : (0 _ : (k' == k) = True) -> Unfolds m self written env t extras r ->
                   TakesLiteral m self written env k (ConstCase k' t :: alts) extras r
    LiteralPasses : (0 _ : (k' == k) = False) -> TakesLiteral m self written env k alts extras r ->
                    TakesLiteral m self written env k (ConstCase k' t :: alts) extras r
    LiteralNamesType : (0 _ : (map PrT (isConstantType (dropNS cn)) == Just k) = True) -> Unfolds m self written env t extras r ->
                       TakesLiteral m self written env k (ConCase cn tag [] t :: alts) extras r
    LiteralOtherType : (0 _ : (map PrT (isConstantType (dropNS cn)) == Just k) = False) ->
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
  public export
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
  public export
  data Alternatives : Mode -> (self : Address) -> (written : Template) -> Values ClosedTerm vs -> FieldsOf ->
                      List (CaseAlt vs) -> List ClosedTerm -> List Template -> Type where
    NoAlternatives : Alternatives m self written env f [] extras []
    WithAlternative : AlternativeUnfolds m self written env f alt extras r -> Alternatives m self written env f alts extras ls ->
                  Alternatives m self written env f (alt :: alts) extras (maybe ls (\u => u :: ls) r)

  ||| One alternative walked, argument k it binds bound as the match binds
  ||| it (`fieldOf`): a delay's type its first and its value its second.
  public export
  data AlternativeUnfolds : Mode -> (self : Address) -> (written : Template) -> Values ClosedTerm vs -> FieldsOf ->
                            CaseAlt vs -> List ClosedTerm -> Maybe Template -> Type where
    ConstructorAlternative : Unfolds m self written (extend (boundFields f 0 cargs) env) t extras r ->
                             AlternativeUnfolds m self written env f (ConCase con tag cargs t) extras r
    DelayAlternative : Unfolds m self written (fieldOf f 0 :: fieldOf f 1 :: env) t extras r ->
                       AlternativeUnfolds m self written env f (DelayCase tyn argn t) extras r
    ConstantAlternative : Unfolds m self written env t extras r -> AlternativeUnfolds m self written env f (ConstCase k t) extras r
    DefaultAlternative : Unfolds m self written env t extras r -> AlternativeUnfolds m self written env f (DefaultCase t) extras r

------------------------------------------------------------------------------
-- A static argument read
------------------------------------------------------------------------------

||| The kinds a reading reads off the term as written: a dictionary, keyed
||| as written, and a shape a constructor heads, whose skeleton is. A type,
||| a family and a form are read off the host's normal form alone.
public export
data ReadAsWritten : Static -> Type where
  WrittenDictionary : ReadAsWritten ADictionary
  WrittenShape : ReadAsWritten AShape

||| How a reading's form was read off its term: the host's normal form of
||| it, contracted (a type, a family, a form, a shape no constructor
||| heads), with the evidence that it is normal, which the reading lemma
||| compares an instance's normal form by; or the term as written, its
||| unknowns solved (`Solved`, kept whole, so a proof reads which of no
||| unknown or the holes normaliser's normal form it is), then contracted,
||| of a kind read so (a dictionary, a shape a constructor heads:
||| `ReadAsWritten`). A dictionary, and no other kind, that closes over
||| runtime values is the implementation the frontend's own reduction finds
||| it to be (`Closed.implementationOf`), contracted, which no relation of
||| the host's yet states.
public export
data FormFrom : Static -> Frozen -> ClosedTerm -> ClosedTerm -> Type where
  FromNormalForm : (r : NormalReading OfNormaliseTypes ctx t) -> FormFrom k ctx t r.readForm
  FromWritten : ReadAsWritten k -> Solved ctx t v -> EtaContracts v u -> FormFrom k ctx t u
  FromImplementation : EtaContracts v u -> FormFrom ADictionary ctx t u

------------------------------------------------------------------------------
-- An instance's static argument
------------------------------------------------------------------------------

||| An instance's static argument of a kind read once in a frozen context,
||| as its link writes it: the form its key writes, how that form was read
||| off the term there, the evidence that the contraction it was read by,
||| which contracts every redex, left none (`Contraction.EtaNormal`), so
||| reading it again reads it as it is (`Proof.Covers.etaNormalFixed`), the
||| template it reads as there with what that says of the form, and its
||| root. The context is an index, so a reading's evidence is over the
||| context its reader holds.
public export
record InstanceReading (ctx : Frozen) (k : Static) (t : ClosedTerm) where
  constructor MkInstanceReading
  form : ClosedTerm
  0 formFrom : FormFrom k ctx t form
  0 maximal : EtaNormal EveryRedex form
  template : Template
  0 describes : ReadAs (InstanceMode ctx) [] form template
  root : Root

||| The height of what an instance's reading reads as: what bounds its key
||| (`Template.keyedWithin`), and what the worklist checks against the
||| growth check's bound at the position it is given at.
public export
readingHeight : InstanceReading ctx k t -> Nat
readingHeight r = height r.template

||| The definition a root names that splits the node of a request it is
||| given to: an implementation's, or the type constructor a family's value
||| applies. A request's arguments hold no marker of the growth check, so
||| no root is a `Parameter` here, and no choice the running program
||| makes, which keys nothing, so none is `Chosen`; a function that gives
||| an implementation at each use is given as written and matched where it
||| is used, so it splits nothing.
public export
splitting : Root -> Maybe Address
splitting (Rooted j) = Just j
splitting (Chosen _) = Nothing
splitting (Gives _) = Nothing
splitting (Parameter _ _) = Nothing
splitting Unrooted = Nothing
