-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The translation's state: the data and function instances registered so
||| far, and the function instances waiting to be translated.
module IdrisMLIR.Frontend.Translate.State

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.TT
import Idris.Host

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Annotated
import IdrisMLIR.Frontend.Translate.Contraction
import IdrisMLIR.Frontend.Translate.Definitions
import IdrisMLIR.Frontend.Translate.Place
import IdrisMLIR.Frontend.Translate.Readings
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Proof.Bound
import IdrisMLIR.Proof.Forms
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Held
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Spec.Families.Group
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Fin
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Data.List1
import Data.Nat
import Data.SnocList
import Data.SortedMap
import Data.SortedMap.Dependent
import Data.SortedSet
import Data.Vect
import Decidable.Equality

%default total

||| The runtime values an implementation closes over (`DictParam`,
||| `Closed.Static`): their types, in the order of the markers that stand
||| for them in its compile-time form (`Closed.holeMarker`), and the one
||| parameter that holds them: the value itself, or, for more than one, a
||| pair of the first and the rest (`Closed.packedType`).
public export
record Holes where
  constructor MkHoles
  types : List1 ClosedTerm
  binder : Binder

||| What keys the choice of a type (`Types.choiceFamily`): a polymorphic
||| function's type keys it itself; an interface's type, or a pair of
||| them, by the type constructor at its head at that constructor's
||| arguments, as a family of it would be keyed.
public export
data KeyedBy = ByItself | ByHead Name (List ClosedTerm)

%prefix_record_projections off

||| A type whose values, held at run time, are its choice's (`Choices`),
||| read once where a value of it is found to be one (`Types.choiceType`),
||| with what keys its choice, so that registering the choice reads
||| nothing of the type again.
public export
record ChoiceType where
  constructor MkChoiceType
  type : ClosedTerm
  keying : KeyedBy

%prefix_record_projections on

||| A request's static argument as an instance's reading reads it
||| (`Template.staticReading`), kept by its kind and its written key, and
||| given to every request that argument keys: the reading itself, at
||| quantity 0, in the frozen context it was read in and at the kind and
||| the term it was read at, so that what a request puts in for a parameter
||| its key names is a reading's form by construction; and what the
||| translation reads of it at run time, each the reading's by type: the
||| form its link writes, its height (`Readings.readingHeight`), and the
||| definition at its root that splits the node of a request it is given
||| to, the implementation of a dictionary or the type constructor at the
||| head of a family, if it has one (`Readings.splitting`).
public export
record StaticReading where
  constructor MkStaticReading
  {0 readIn : Frozen}
  {0 readKind : Static}
  {0 readTerm : ClosedTerm}
  0 reading : InstanceReading readIn readKind readTerm
  form : ClosedTerm
  0 isForm : form = reading.form
  height : Nat
  0 isHeight : height = readingHeight reading
  head : Maybe Address
  0 isHead : head = splitting reading.root

||| What a reduction to a head is stuck on.
public export
data StuckOn
  = ||| A runtime value: one an implementation closes over, a part of one
    ||| its shape does not say, or a runtime variable.
    OnRuntime ClosedTerm
  | ||| A definition Idris does not prove ends, which Idris's normaliser
    ||| would run.
    OnPartial Name
  | ||| A value that is no constructor application: a literal, a type, a
    ||| function, a definition applied to fewer arguments than it takes.
    OnValue ClosedTerm

||| What an implementation the program fixes now reduces to at its head: an
||| interface's constructor applied to its fields, which a tree that matches
||| on the implementation takes apart at compile time; or a value of a
||| function type, a lambda or a definition applied to fewer arguments than
||| it takes, which each use applies in place.
public export
data FixedValue = FixedConstructor Name (List ClosedTerm) | FixedFunction ClosedTerm

||| A fixed value with each of its terms changed alike: the constructor's
||| arguments, or the function. Putting in names no reduction unfolds (the
||| markers of the values an implementation closes over) commutes with
||| reducing to a head, so a form with such names put in reduces to its
||| value with them put in, and nothing reduces it again.
export
mapValue : (ClosedTerm -> ClosedTerm) -> FixedValue -> FixedValue
mapValue f (FixedConstructor n args) = FixedConstructor n (map f args)
mapValue f (FixedFunction v) = FixedFunction (f v)

||| What an implementation's form reduces to at its head, whatever type it
||| is given at (`Closed.reducedOf`): a value the program fixes, or what the
||| reduction is stuck on. Whether a function value is fixed is its type's
||| to say, read where it is given (`Closed.fixedAt`).
public export
data HeadReduct = ReducesTo FixedValue | StuckAt StuckOn

||| A dictionary's static argument as an instance's reading reads it
||| (`StaticReading`), with what the reading's form reduces to at its head
||| (`HeadReduct`), found once where it was read: reduced there, or, for a
||| form built around one already reduced, built beside it
||| (`Template.builtDictionary`). Whether the program fixes the dictionary
||| is decided from it at each parameter it is given at (`Closed.fixedAt`),
||| and nothing reduces the form again.
public export
record DictionaryReading where
  constructor MkDictionaryReading
  asStatic : StaticReading
  0 ofDictionary : asStatic.readKind = ADictionary
  reduct : HeadReduct

||| An implementation the program fixes now, as the kind of a parameter
||| given it holds it (`DictParam`): its form as given (what a call writes,
||| where the call classifies it; its reading's form, where an instance is
||| keyed by it, `atReading`); the type it is fixed at, the parameter's or
||| the choice's, which a use of it as a form applies it at
||| (`Terms.implementationAt`); its reading (`StaticReading`); and the value
||| its form reduces to at its head (`FixedValue`), found once: where the
||| one classification of a dictionary read it, the reduct its reading kept
||| (`Template.dictionaryReading`), fixed at the type it is given at
||| (`Closed.fixedAt`); or, for a form built around one already reduced,
||| built beside it (`Choices.heldMember`, `Cases.heldHere`). A kind that
||| holds it is fixed by type, so a tree that matches on its parameter takes
||| that value apart, and nothing reduces the form again.
public export
record FixedDictionary where
  constructor MkFixedDictionary
  form : ClosedTerm
  type : ClosedTerm
  asStatic : StaticReading
  0 ofDictionary : asStatic.readKind = ADictionary
  reducesTo : FixedValue

||| A fixed implementation as an instance keyed by it holds it: at the form
||| its reading reads, which its key writes there.
public export
atReading : FixedDictionary -> FixedDictionary
atReading d = MkFixedDictionary d.asStatic.form d.type d.asStatic d.ofDictionary d.reducesTo

||| An index of an inductive family that a type argument's form leaves
||| erased (`_` at an `Index` position of a type constructor's
||| application: an instance's key erases one that names a level of its
||| caller's, `Types.unmarked`, and a family's key every one), as an index
||| parameter of the instance the form keys, or as an index of the family
||| whose key holds the type (`Types.heldPlaces`), which each of its
||| constructors binds: the path to it from the form's root, the outermost
||| step first, and its sort. Each call passes its term there
||| (`Instances.indexForms`), and each construction site gives it the term
||| there (`Instances.binderTerms`), so a closure's type and a family's
||| keep the index the program names.
public export
record ErasedIndex where
  constructor MkErasedIndex
  path : List FormStep
  sort : Sort

||| Parameter classification after instantiation (`Instances.classify`). A
||| type parameter and an implementation (a value of an interface's type,
||| such as an interface constraint, or a polymorphic function passed as a
||| value, `Types.polymorphicType`) are compile-time values: they key the
||| instance and are not parameters at runtime. A type parameter's form
||| holds each index of an inductive family its key erased as an index
||| parameter of the instance (`ErasedIndex`), at the levels after those of
||| the index parameters before it, which its value in the instance's
||| scope names there (`TypeConstructors.filledIndices`); a call's own
||| reading of its type argument holds none. An implementation is one the
||| program fixes now, with its reading and the value it reduces to
||| (`FixedDictionary`). It may close over runtime values (`{vars : _} ->
||| Show (Term vars)` at the scope a term has): which implementation it is
||| stays a compile-time value, the values replaced by markers, and the
||| parameter holds the values (`Holes`). An
||| implementation the call chooses at run time among those the program
||| fixes is a choice (`ChoiceParam`): a runtime value of the closed sum of
||| the implementations of its interface type (`Choices`), with its binder
||| and that type as the classification read it (`ChoiceType`); a call
||| given one is a dispatch on it, never an instance at it. A parameter of
||| quantity 0 is no parameter at runtime and keys nothing: absent, or,
||| when it occurs as an index of an inductive family in a runtime
||| parameter's type or the result and nowhere a representation depends on
||| it, an index parameter of the instance, of
||| its sort, whose level is the number of index parameters before it, so
||| that the instance's types name it (`!idr.data<#Vect[v0]>`). Any other
||| binds as its binder says, with its closed Idris type, which tells a
||| function-typed value's erased arguments from its runtime ones; when the
||| rest of the type depends on its value, the shape of its argument keys
||| the instance too. An erased shape of the array language that a value
||| array's type needs is its form, the spine with every extent erased: it
||| keys the instance, since a tensor's rank is its type. The kinds stay
||| positional, one per parameter of the definition's type, as the case
||| tree's scope has one variable per parameter.
public export
data PKind = TypeParam ClosedTerm (List ErasedIndex)
           | DictParam FixedDictionary (Maybe Holes)
           | ChoiceParam Binder ChoiceType
           | ErasedParam
           | IndexParam Sort
           | FormParam ClosedTerm
           | ValueParam Binder (Maybe ClosedTerm) ClosedTerm

||| A request's static argument as the kind of parameter it keys, its term
||| left out: what the instance puts in there once the term is the form
||| its reading reads (`Template.staticReading`). A type, read as a type:
||| a family keys its instance as any type does (`TypeParam`), and its
||| value reads as a type, whose root is the type constructor it applies
||| when it has one, so no request is read as a family. An implementation,
||| with the values it closes over, which its form leaves as markers. A
||| form. A runtime value's shape, with the quantity of the parameter it
||| is the value of.
public export
data KeyedAs = AsType | AsDictionary (Maybe Holes) | AsForm | AsShape Uses

||| The kinds no static argument keys: a runtime value whose shape keys
||| nothing, a choice the running program makes (which implementation runs
||| is the value's), an erased value, and an index parameter. A request
||| writes nothing of its argument at one of these into its link, and puts
||| nothing in for it: its instance's binder decides what it is.
public export
data KeysNothing : PKind -> Type where
  UnshapedValue : KeysNothing (ValueParam b Nothing t)
  ChoiceKeysNothing : KeysNothing (ChoiceParam b c)
  ErasedKeysNothing : KeysNothing ErasedParam
  IndexKeysNothing : KeysNothing (IndexParam s)

||| An instance's telescope: the sorts of its index parameters, in order,
||| the levels `0 .. p-1` of its body's scope, each erased index of a type
||| parameter's form one of them.
export
telescopeOf : List PKind -> List Sort
telescopeOf [] = []
telescopeOf (IndexParam s :: ks) = s :: telescopeOf ks
telescopeOf (TypeParam _ is :: ks) = map (.sort) is ++ telescopeOf ks
telescopeOf (_ :: ks) = telescopeOf ks

||| What a parameter binds at run time, if it is a parameter at run time:
||| a value, the values an implementation closes over, held as one, or a
||| choice of an implementation.
public export
boundAtRuntime : PKind -> Maybe Binder
boundAtRuntime (ValueParam b _ _) = Just b
boundAtRuntime (DictParam _ (Just h)) = Just h.binder
boundAtRuntime (ChoiceParam b _) = Just b
boundAtRuntime _ = Nothing

||| One more for what exists at run time.
public export
counted : Maybe a -> Nat -> Nat
counted (Just _) n = S n
counted Nothing n = n

||| How many of a call's parameters exist at run time.
public export
Runtimes : List PKind -> Nat
Runtimes [] = Z
Runtimes (k :: ks) = counted (boundAtRuntime k) (Runtimes ks)

||| A position among the parameters after one that exists at run time or
||| not: one further, or the same.
export
after : (m : Maybe a) -> Fin n -> Fin (counted m n)
after (Just _) i = FS i
after Nothing i = i

||| The binders of a call's parameters that exist at run time, in order.
export
runtimeBinders : (kinds : List PKind) -> Vect (Runtimes kinds) Binder
runtimeBinders [] = []
runtimeBinders (k :: ks) = before (boundAtRuntime k) (runtimeBinders ks)
  where
    before : (m : Maybe Binder) -> Vect n Binder -> Vect (counted m n) Binder
    before (Just b) bs = b :: bs
    before Nothing bs = bs

||| The parameters at run time of a call's first `m` kinds and of the rest
||| are all of its parameters at run time: what a call gives and what its
||| closures take are as many as its callee has.
export
runtimesSplit : (m : Nat) -> (ks : List PKind) -> Runtimes (take m ks) + Runtimes (drop m ks) = Runtimes ks
runtimesSplit Z [] = Refl
runtimesSplit Z (k :: ks) = Refl
runtimesSplit (S m) [] = Refl
runtimesSplit (S m) (k :: ks) =
  step {a = Runtimes (take m ks)} {c = Runtimes (drop m ks)} {d = Runtimes ks} (boundAtRuntime k) (runtimesSplit m ks)
  where
    step : {0 a, c, d : Nat} -> (b : Maybe Binder) -> a + c = d -> counted b a + c = counted b d
    step (Just _) prf = cong S prf
    step Nothing prf = prf

||| What a parameter is given put before what the parameters after it are:
||| the term `x` makes where the parameter exists at run time, nothing
||| where it does not, so `x` runs only for a parameter at run time.
export
consAt : Applicative m => (b : Maybe Binder) -> m t -> m (Vect n t) -> m (Vect (counted b n) t)
consAt (Just _) x rest = (::) <$> x <*> rest
consAt Nothing x rest = rest

||| One term per parameter that exists at run time, in order, each made
||| from the parameter's position and kind; the count is the kinds', by
||| type.
export
eachRuntime : Monad m => (Nat -> PKind -> m t) -> (ks : List PKind) -> m (Vect (Runtimes ks) t)
eachRuntime f = go 0
  where
    go : Nat -> (ks : List PKind) -> m (Vect (Runtimes ks) t)
    go i [] = pure []
    go i (k :: ks) = consAt (boundAtRuntime k) (f i k) (go (S i) ks)

||| The binder of a closure's parameter: one closure type serves every
||| extent its values are made at, so every tensor dimension in it is
||| dynamic, as the closure's own type has it (`coreType`).
export
closureBinder : Binder -> Binder
closureBinder b = { type $= dynamicDims } b

||| A call's value made from its runtime arguments, as many as it has
||| parameters that exist at runtime.
public export
record Maker (r : Nat) where
  constructor MkMaker
  make : {0 m : Nat} -> Vect r (IdrisMLIR.Term.Term m) -> IdrisMLIR.Term.Term m

||| A maker over a count shown equal to its own.
export
recount : (0 _ : a = b) -> Maker b -> Maker a
recount Refl mk = mk

||| Eta-expands a known head applied to too few arguments over its missing
||| runtime parameters, one closure each, as the curried type of the
||| result requires: `\x => .. => head(args ++ xs)`, the head's value of
||| type `valueTy`, so each closure gives a closure over the parameters after
||| its own, or that value (`closureType`).
export
etaExpand : {0 nv : Nat} -> {0 g : Nat} -> Loc -> Vect k Binder -> (valueTy : Ty) -> Maker (g + k) ->
            Vect g (IdrisMLIR.Term.Term nv) -> IdrisMLIR.Term.Term nv
etaExpand loc [] valueTy mk given = (recount (sym (plusZeroRightNeutral g)) mk).make given
etaExpand loc {k = S k'} (b :: rest) valueTy mk given =
  IdrisMLIR.Term.Lam loc (shown "x") (closureBinder b) (closureType rest valueTy)
      (etaExpand loc rest valueTy (recount (plusSuccRightSucc g k') mk)
                 (snoc (map (weakenUnder 1) given) (IdrisMLIR.Term.Var loc FZ)))

%prefix_record_projections off

||| What a call gives a function of `k` runtime parameters, by position:
||| the values of the first `g` of them, and the binders of the `m` it
||| leaves to the closures that complete it (`etaExpand`), together as
||| many as the function takes.
public export
record Supplied (k : Nat) (nv : Nat) where
  constructor MkSupplied
  {0 g : Nat}
  {0 m : Nat}
  values : Vect g (IdrisMLIR.Term.Term nv)
  missing : Vect m Binder
  0 together : g + m = k

%prefix_record_projections on

||| A call's arguments against an arity: as many as it or more, the first
||| that many and the rest; or fewer.
public export
data Saturation : Nat -> Type -> Type where
  Saturated : Vect n a -> List a -> Saturation n a
  Short : Saturation n a

||| A call's arguments against an arity (`Saturation`).
export
saturation : (n : Nat) -> List a -> Saturation n a
saturation Z xs = Saturated [] xs
saturation (S n) [] = Short
saturation (S n) (x :: xs) = case saturation n xs of
  Saturated now rest => Saturated (x :: now) rest
  Short => Short

||| A call's value made from the runtime arguments given, in order, by
||| what the function applied is, its value of type `valueTy`: as many as its
||| maker takes saturate it, and each one after applies its value at the
||| function type `valueTy` shows for it; with fewer, one closure per missing
||| parameter completes it (`etaExpand`), as a call below its arity is.
||| The binders are its parameters', in the scope the value is made in.
||| Nothing where an argument is left past every function type `valueTy`
||| shows, which a value of that type does not take.
export
applyMaker : {0 nv : Nat} -> Loc -> Maker r -> Vect r Binder -> (valueTy : Ty) -> List (IdrisMLIR.Term.Term nv) ->
             Maybe (IdrisMLIR.Term.Term nv)
applyMaker loc mk bs valueTy ns = go [] bs mk ns
  where
    applying : IdrisMLIR.Term.Term nv -> Ty -> List (IdrisMLIR.Term.Term nv) -> Maybe (IdrisMLIR.Term.Term nv)
    applying f t [] = Just f
    applying f (FunT a r) (x :: xs) = applying (IdrisMLIR.Term.App loc a r f x) r xs
    applying f _ (_ :: _) = Nothing

    go : {0 g : Nat} -> Vect g (IdrisMLIR.Term.Term nv) -> Vect k Binder -> Maker (g + k) -> List (IdrisMLIR.Term.Term nv) ->
         Maybe (IdrisMLIR.Term.Term nv)
    go given [] mk' rest = applying ((recount (sym (plusZeroRightNeutral g)) mk').make given) valueTy rest
    go given bs'@(_ :: _) mk' [] = Just (etaExpand loc bs' valueTy mk' given)
    go given {k = S k'} (_ :: bs') mk' (n :: rest) = go (snoc given n) bs' (recount (plusSuccRightSucc g k') mk') rest

||| An instance's signature, read once where the instance is first
||| requested (`Instances.request`), which the instance's own step and
||| every call of it read: each parameter of its definition's type as the
||| instance classifies it over the static arguments it is requested with,
||| its index parameters its own levels; the Idris type of its result,
||| normalised, in that scope; and what a call holds of it (`Callee`), one
||| binder per parameter that exists at run time, by type.
public export
record InstanceSig where
  constructor MkInstanceSig
  kinds : List PKind
  result : ClosedTerm
  callee : Callee (Runtimes kinds)

||| A full name, printed so that different names print differently: Idris's
||| `show` prints only the display part of a `DN` and leaves out the index of
||| a case or with block. It is a print, for a message that names a
||| definition; no table is keyed by it, since a definition is its address
||| (`definitionAddress`), and it is no part of what the program is called,
||| which `Keys` prints.
export
nameKey : Name -> String
nameKey (NS ns n) = let k = nameKey n in if any isOpChar (unpack k) then show ns ++ ".(" ++ k ++ ")" else show ns ++ "." ++ k
nameKey (DN str n) = str.text ++ "{" ++ nameKey n ++ "}"
nameKey (CaseBlock outer i) = "case block " ++ show i ++ " in " ++ nameKey outer
nameKey (WithBlock outer i) = "with block " ++ show i ++ " in " ++ nameKey outer
nameKey n = show n

||| A definition as the growth check splits it (`Growth`): its address,
||| the implementation (or interface constructor) at the root of each
||| implementation it is given that has one, and the type constructor at
||| the head of each type family it is given that one heads (`tm : Scope ->
||| Type` at `Term`), by the parameter's index, ascending. A method is
||| requested as its projection at the dictionary, so two calls of it at
||| implementations of different heads are two nodes: it is keyed by the
||| implementation that runs. A definition whose kinds depend on what its
||| family is (an index of `Term` keys nothing that a marker would key) is
||| two nodes at two type constructors, each with its own positions.
public export
record Node where
  constructor MkNode
  definition : Address
  heads : List (Nat, Address)

export
Eq Node where
  x == y = x.definition == y.definition && x.heads == y.heads

export
Ord Node where
  compare x y = compare (x.definition, x.heads) (y.definition, y.heads)

||| A static position of the checked graph: a node and one of its
||| definition's parameters, by position.
public export
Position : Type
Position = (Node, Nat)

%prefix_record_projections off
||| What a pattern-matching definition's body is to the translation, read
||| once through the context's accessors (`Boundary`): its case tree, each
||| clause's patterns as the case builder read them, and the right-hand
||| side of its clause, in that clause's scope, when it has exactly one,
||| which is all of its clauses the translation reads.
public export
record Matched where
  constructor MkMatched
  args : Scope
  tree : CaseTree args
  pats : List (List Pat)
  onlyClause : Maybe (vs : Scope ** Core.TT.Term.Term vs)

||| The right-hand side of a body whose case tree is one leaf; nothing for
||| one that matches.
export
leafOf : (m : Matched) -> Maybe (Core.TT.Term.Term m.args)
leafOf m = case m.tree of
  STerm _ rhs => Just rhs
  _ => Nothing

%prefix_record_projections on

||| What a function instance is an instance of: a definition of the
||| program, with its body as the boundary read it, whose case tree's
||| parameters are the arity every call of it and its own translation
||| read, one reading; or a
||| member of a choice at a use's types (`AtUse uses`), which
||| no definition of the program is. A member at a use is a compile-time
||| form (a polymorphic function, an implementation) applied to the `uses`
||| arguments a use gives it, where no definition applies it: a value of a
||| choice applied where it is held, each member at that use's own types,
||| or a form a settled term would settle inside its own settled form. It
||| is applied as by `\f, x1 .. xn => f x1 .. xn` at the form's type
||| (`Instances.applicationType`): the type, a compile-time value, keys
||| it, then the form, then the use's arguments, as many as the use gives
||| and the type, as Idris checked the use, takes, so no instance takes
||| more than its type does.
public export
data Instantiates = OfDefinition Name Matched | AtUse Nat

||| How many parameters an instance applies: a definition's case tree's,
||| or the type, the form and the use's arguments of a member at a use.
public export
appliedArity : Instantiates -> Nat
appliedArity (OfDefinition _ m) = length m.args
appliedArity (AtUse uses) = 2 + uses

||| What an instance's parameter is put in at, as its request keys it
||| there: where a static argument keys it, that argument's reading's
||| form, at the kind it was read as (`KeyedAs`), the implementation with
||| the values it closes over and the value it was fixed at, and the shape
||| at the quantity it was read with; where nothing keys it, whatever the
||| parameter's binder decides, a kind that keys nothing (`KeysNothing`). So
||| the value an instance holds for a parameter its key names is the form
||| the key writes there (a type's with its erased indices the instance's
||| index parameters), and at every other parameter it holds no static
||| value.
public export
data AtKey : Maybe (KeyedAs, StaticReading) -> PKind -> Type where
  TypeAtKey : {0 r : StaticReading} -> {0 is : List ErasedIndex} -> AtKey (Just (AsType, r)) (TypeParam r.form is)
  DictionaryAtKey : {0 d : FixedDictionary} -> {0 holes : Maybe Holes} ->
                    AtKey (Just (AsDictionary holes, d.asStatic)) (DictParam (atReading d) holes)
  FormAtKey : {0 r : StaticReading} -> AtKey (Just (AsForm, r)) (FormParam r.form)
  ShapeAtKey : {0 r : StaticReading} -> {0 q : Uses} -> {0 t : Ty} -> {0 idrisType : ClosedTerm} ->
               AtKey (Just (AsShape q, r)) (ValueParam (MkBinder q t) (Just r.form) idrisType)
  NoKey : {0 k : PKind} -> (0 _ : KeysNothing k) -> AtKey Nothing k

||| What a request keys its instance's next parameter by, and what it keys
||| those after it by: past the arguments the request gives, nothing.
public export
nextKey : List (Maybe (KeyedAs, StaticReading)) -> (Maybe (KeyedAs, StaticReading), List (Maybe (KeyedAs, StaticReading)))
nextKey (k :: ks) = (k, ks)
nextKey [] = (Nothing, [])

||| Each of an instance's parameters put in as its request keys it
||| (`AtKey`), position by position.
public export
data AllAtKey : List (Maybe (KeyedAs, StaticReading)) -> List PKind -> Type where
  Nil : {0 keys : List (Maybe (KeyedAs, StaticReading))} -> AllAtKey keys []
  (::) : {0 keys : List (Maybe (KeyedAs, StaticReading))} -> {0 k : PKind} -> {0 ks : List PKind} ->
         AtKey (fst (nextKey keys)) k -> AllAtKey (snd (nextKey keys)) ks -> AllAtKey keys (k :: ks)

||| An instance's signature as its request reads it, at what the request
||| keys it by: one kind per parameter the instance applies, each put in as
||| the request keys it (`AllAtKey`).
public export
record SignedAt (what : Instantiates) (keys : List (Maybe (KeyedAs, StaticReading))) (sig : InstanceSig) where
  constructor MkSignedAt
  0 classifiesAll : length sig.kinds = appliedArity what
  0 atKey : AllAtKey keys sig.kinds

||| A function instance requested: what it is an instance of, its
||| signature, read once where it was first requested (`InstanceSig`), so
||| that it is translated at what every call of it holds, with what the
||| request keyed each parameter by and that each is put in at it, at
||| quantity 0, so that the value an instance holds for a static argument is
||| the form its key writes there, and each static argument's reading
||| (`StaticReading`) holds the instance's reading of it whose form that is;
||| its key, the call that requested it,
||| where and in whose definition, for a message to print, its link, which
||| is its identity, and the height of each static argument at the position
||| of the growth check's graph it is bounded at, which the worklist checks
||| against the growth check's bounds (`Finite`). A definition's positions
||| are its node's (its definition, split by the heads of what it is
||| given) at its parameters' indices; a member at a use is no definition,
||| so no node of the graph is it, and the growth check bounds its link
||| alone (`Proof.Requests.Bounds`). The node's heads and the heights are
||| the arguments' readings, found when the instance is requested
||| (`Instances.request`). Its signature classifies as many parameters as
||| it applies, so its translation binds one per variable of its scope.
public export
record Request where
  constructor MkRequest
  instantiates : Instantiates
  signature : InstanceSig
  0 classifiesAll : length signature.kinds = appliedArity instantiates
  0 keys : List (Maybe (KeyedAs, StaticReading))
  0 atKey : AllAtKey keys signature.kinds
  key : InstanceKey
  site : FC
  owner : Shown
  link : Link Form
  positions : List (Position, Nat)

||| A request's identity: the instance its link is.
public export
(.inst) : Request -> FnId
(.inst) r = InstanceOf r.link

||| A request's signature's kinds, one per parameter its instance applies,
||| as many as its signature classifies (`classifiesAll`).
export
kindsOf : (r : Request) -> Vect (appliedArity r.instantiates) PKind
kindsOf r = replace {p = \n => Vect n PKind} r.classifiesAll (Data.Vect.fromList r.signature.kinds)

||| One argument of a constructor, as a data instance has it. Idris does not
||| put the data type's parameters first (`(::) : {0 len} -> {0 elem} ->
||| ...`), so every argument says what it is: a parameter, whose value the
||| instance gives; an argument of quantity 0, which is no field; or
||| runtime field `i`, counting the runtime fields from 0, with its binder
||| and its Idris type at the instance. An implementation the constructor
||| holds (`Empty : Ord k => ...`) is a field like any other, its value a
||| choice (`Choices`): each construction site gives the one it fixes.
public export
data ArgKind = Param ClosedTerm
             | ErasedArg
             | Field Nat Binder ClosedTerm

||| How many of a constructor's arguments are runtime fields.
public export
fieldCount : List ArgKind -> Nat
fieldCount [] = 0
fieldCount (Param _ :: as) = fieldCount as
fieldCount (ErasedArg :: as) = fieldCount as
fieldCount (Field _ _ _ :: as) = S (fieldCount as)

||| The binders of a constructor's runtime fields, in order, one per field.
public export
fieldsOf : (as : List ArgKind) -> Vect (fieldCount as) Binder
fieldsOf [] = []
fieldsOf (Param _ :: as) = fieldsOf as
fieldsOf (ErasedArg :: as) = fieldsOf as
fieldsOf (Field _ b _ :: as) = b :: fieldsOf as

||| What a constructor instance needs for case trees: its arguments, its
||| full name, and the constructor as Core has it, indexed by its runtime
||| fields, as many as its arguments say.
public export
record ConLayout where
  constructor MkConLayout
  args : List ArgKind
  name : Name
  con : Con (fieldCount args)

||| A constructor as Emit's term holds it, with its count of fields.
export
layoutCon : ConLayout -> (k ** Con k)
layoutCon l = (fieldCount l.args ** l.con)

%prefix_record_projections off

||| A data family as the translation registered it: what Emit declares of
||| it (its identity, its key, what its library promises of its values,
||| the sorts of its erased indices, its location), and each constructor's
||| layout, in tag order, so that a constructor's tag is its position
||| among them (`ConId tags`) and its layout is read there. The record is
||| made once its last constructor is read: a family its own fields name
||| has an identity before it has a record (`Types.familyIn`). What crosses
||| into Emit's term is its declaration (`dataDeclared`), which holds no TT.
public export
record DataFamily where
  constructor MkDataFamily
  id : FamilyId
  key : InstanceKey
  promise : Promise
  indices : List Sort
  {0 tags : Nat}
  layouts : Vect tags ConLayout
  loc : Loc

%prefix_record_projections on

||| A data family as Emit declares it: its constructors are its layouts'.
export
dataDeclared : DataFamily -> Family
dataDeclared df = MkFamily df.id df.key df.promise df.indices (toList (map layoutCon df.layouts)) df.loc

||| The constructor of a member of a choice: one with no field, for an
||| implementation that closes over no runtime value, or one whose one
||| field holds the values it captures (`Holes`), as a closure's does.
public export
data MemberCon = Bare (Con 0) | Capturing Holes (Con 1)

||| A member's constructor, whatever its field.
export
memberCon : MemberCon -> (k ** Con k)
memberCon (Bare c) = (0 ** c)
memberCon (Capturing _ c) = (1 ** c)

||| An implementation the program fixes as a value of its interface type,
||| one constructor of that type's choice (`Choices`): the implementation
||| fixed (`FixedDictionary`), its form the runtime values it closes over
||| replaced by markers (`Closed.holeMarker`), registered with the reading
||| and the value the one classification of a dictionary found, which key
||| the instance of every callee a dispatch calls at it and which that
||| callee's tree takes apart; and its constructor. A member is registered
||| only where the program fixes it now (`Choices.memberBare`), so no arm of
||| a dispatch is given one its tree cannot take apart.
public export
record ChoiceMember where
  constructor MkChoiceMember
  dictionary : FixedDictionary
  con : MemberCon

||| What a choice is a choice of, its identity: an interface type, by its
||| link (the interface at the arguments a family of it would be keyed
||| by); or a polymorphic function type, written out whole, since no
||| definition is the type of a function.
public export
data ChoiceKey = OfInterface (Link Form) | OfFunction (Written Form)

export
Eq ChoiceKey where
  OfInterface a == OfInterface b = a == b
  OfFunction a == OfFunction b = a == b
  _ == _ = False

export
Ord ChoiceKey where
  compare (OfInterface a) (OfInterface b) = compare a b
  compare (OfInterface _) (OfFunction _) = LT
  compare (OfFunction _) (OfInterface _) = GT
  compare (OfFunction a) (OfFunction b) = compare a b

||| The closed sum of the implementations of one interface type, or of the
||| polymorphic functions of one function type, that the program fixes as
||| runtime values: its family, numbered with the data families, and the
||| key and location Emit declares it with, the type, and its members in
||| the order the translation found them, each the next constructor. It
||| only grows, and a dispatch on it is built once the translation has
||| found every member (`Choices.dispatchers`). Its members are its only
||| constructors: no layout is read of a choice, since no Idris
||| constructor builds or matches one.
public export
record Choice where
  constructor MkChoice
  family : FamilyId
  key : InstanceKey
  type : ClosedTerm
  loc : Loc
  members : SnocList ChoiceMember

||| A choice as Emit declares it: a family that promises nothing and has no
||| index, its constructors its members' so far.
export
choiceDeclared : Choice -> Family
choiceDeclared ch = MkFamily ch.family ch.key None [] (map (\m => memberCon m.con) (ch.members <>> [])) ch.loc

||| The parameter a dispatch finds its choice in, as its kind holds it: the
||| parameter takes the choice, of this binder and type (`Given`), and the
||| kinds hold `rest` more choices after it, each arm a call of the callee
||| with one fewer (`Choices.calleeAt`); or the parameter takes an
||| implementation the program fixes (`FixedDictionary`), and holds the
||| values it closes over, the one at a place among them a choice the
||| running program made (`HeldIn`, the place a position among the values'
||| types): a field of the implementation, whose every member is an
||| instance of the callee with that field fixed (`Choices.heldDispatch`).
public export
data Chosen : Type where
  Given : (rest : Nat) -> Binder -> ChoiceType -> Chosen
  HeldIn : FixedDictionary -> (hs : Holes) -> Fin (length (forget hs.types)) -> Chosen

||| The kind of the parameter a dispatch finds its choice in.
export
chosenKind : Chosen -> PKind
chosenKind (Given _ b t) = ChoiceParam b t
chosenKind (HeldIn holder hs _) = DictParam holder (Just hs)

%prefix_record_projections off

||| A call's kinds split at one of its parameters, `n` in all: the kinds
||| before it, what the parameter is (`here`), and the kinds after it. Its
||| projections, as a dispatch's, are postfix only: a prefix `after` would
||| be `State.after` too.
public export
record SplitKinds (n : Nat) (a : Type) where
  constructor MkSplitKinds
  {0 before : Nat}
  {0 after : Nat}
  kindsBefore : Vect before PKind
  here : a
  kindsAfter : Vect after PKind
  0 spans : before + S after = n

||| The split of a call's kinds after one more kind before them.
export
afterKind : PKind -> SplitKinds n a -> SplitKinds (S n) a
afterKind k parts = MkSplitKinds (k :: parts.kindsBefore) parts.here parts.kindsAfter (cong S parts.spans)

||| A call given a choice (`ChoiceParam`), or an instance given an
||| implementation that holds one, as one function: its identity and key,
||| its signature, read once where it was made (`InstanceSig`), the callee
||| (a definition, or a member at a use, whose choice the use dispatches
||| on), its signature's kinds, one per parameter the callee applies,
||| split at the parameter its choice is found in (`Chosen`), so that the
||| parameter and its kind are one, and that parameter's position among
||| its signature's parameters at run time, read off the same kinds
||| (`Choices.ChoiceAt`), the choice's family, and where and in whose
||| definition it was made.
||| None of it changes once made; its arms, which grow with its choice,
||| are its own table's (`Facts.dispatchArms`).
public export
record Dispatch where
  constructor MkDispatch
  inst : FnId
  key : InstanceKey
  signature : InstanceSig
  callee : Instantiates
  {0 before : Nat}
  {0 after : Nat}
  kindsBefore : Vect before PKind
  chosen : Chosen
  kindsAfter : Vect after PKind
  0 spans : before + S after = appliedArity callee
  choice : Fin (Runtimes signature.kinds)
  family : FamilyId
  site : FC
  owner : String

||| A dispatch's arm for one member of its choice, made when the later of
||| the two is: the member, and the signature of the callee's instance at
||| it, which the arm calls. The arm holds the member it is for, so no arm
||| is written for a member it cannot name.
public export
record DispatchArm where
  constructor MkDispatchArm
  member : ChoiceMember
  target : InstanceSig

%prefix_record_projections on

||| A dispatch's kinds with the parameter its choice is found in given
||| another kind: what an arm's callee is given, one kind per parameter the
||| callee applies.
export
givenInstead : PKind -> (d : Dispatch) -> Vect (appliedArity d.callee) PKind
givenInstead k d = replace {p = \n => Vect n PKind} d.spans (d.kindsBefore ++ k :: d.kindsAfter)

export
data TState : Type where

||| What a type constructor's values are, as numbers go.
public export
data Natness = NotNat     -- not Nat-like
             | Numeral    -- Nat-like (Idris's ZERO/SUCC), but a constructor takes an erased argument (Fin's FS)
             | Chain      -- Nat-like, every constructor argument at run time: a shape is a chain of S

||| What the argument at a position of a type constructor is to a data
||| instance of it, decided once per position (`TypeConstructors`):
|||
||| - `Keyed`: a type parameter a value represents, which keys the instance
|||   whole, its own indices erased;
||| - `Formed`: a parameter of the shape type that a value array's shape
|||   reads, which keys the instance by its form, the rank kept and the
|||   extents erased, since a tensor's rank is its type;
||| - `Held`: an index whose kind is a universe and that the values hold,
|||   which keys nothing but the growth check watches;
||| - `Index`: compile-time information alone.
|||
||| The key keeps the `Keyed` and `Formed` arguments, and the growth check
||| watches every position but an `Index`, reading a `Formed` one as the
||| key's form, so that what the key holds and what the check bounds are
||| read off one role.
public export
data Role = Keyed | Formed | Held | Index

public export
Eq Role where
  Keyed == Keyed = True
  Formed == Formed = True
  Held == Held = True
  Index == Index = True
  _ == _ = False

||| What a definition takes at an argument position: no value at run time
||| (quantity 0), or a value, at Idris's quantity. Whether an erased
||| position is an index the IR keeps is a fact of each instance, read
||| where its type constructors' roles are known (`IndexParam`), not of
||| the definition.
public export
data ArgumentAt = NoValue | RuntimeValue Uses

||| The binders a type in normal form shows, in order, each with what is
||| read of it (`a`) and its type in the scope of the binders before it,
||| then what the type gives after them. A reader that has the arguments
||| before a binder closes the binder's type over them, so no reader walks
||| the type again, where it could find fewer binders than were read.
public export
data Binders : Type -> Scope -> Type where
  ShowsNoMore : Core.TT.Term.Term vs -> Binders a vs
  ShowsBinder : {0 x : Name} -> a -> Core.TT.Term.Term vs -> Binders a (x :: vs) -> Binders a vs

||| The binders a type in normal form shows (`Binders`), binder `j` of
||| quantity `rig` read as `at` reads it.
export
bindersWith : (at : Nat -> RigCount -> a) -> Core.TT.Term.Term vs -> Binders a vs
bindersWith at = go 0
  where
    go : Nat -> Core.TT.Term.Term ws -> Binders a ws
    go j (Bind _ _ (Pi _ rig _ ty) sc) = ShowsBinder (at j rig) ty (go (S j) sc)
    go _ t = ShowsNoMore t

||| What is read of each binder, in order.
public export
readOfEach : Binders a vs -> List a
readOfEach (ShowsNoMore _) = []
readOfEach (ShowsBinder r _ rest) = r :: readOfEach rest

namespace ByVar
  ||| One entry per variable of a scope, the innermost first, so that every
  ||| variable the scope holds has its entry and no other has one.
  public export
  data ByVar : Scope -> Type -> Type where
    Nil : ByVar [] a
    (::) : a -> ByVar vs a -> ByVar (v :: vs) a

export
Functor (ByVar vs) where
  map f [] = []
  map f (x :: xs) = f x :: map f xs

||| The entries, the innermost first.
export
innermostFirst : ByVar vs a -> List a
innermostFirst [] = []
innermostFirst (x :: xs) = x :: innermostFirst xs

||| The entry of a variable, which its scope says is there.
export
lookupVar : (idx : Nat) -> (0 _ : IsVar n idx vs) -> ByVar vs a -> a
lookupVar Z _ (x :: _) = x
lookupVar (S i) p (_ :: xs) = lookupVar i (dropLater p) xs
lookupVar _ First [] impossible
lookupVar _ (Later _) [] impossible

||| Each entry made by an effect, in scope order.
export
traverseByVar : Applicative f => (a -> f b) -> ByVar vs a -> f (ByVar vs b)
traverseByVar g [] = pure []
traverseByVar g (x :: xs) = (::) <$> g x <*> traverseByVar g xs

||| Two entries of each variable, made one.
export
zipByVar : (a -> b -> c) -> ByVar vs a -> ByVar vs b -> ByVar vs c
zipByVar f [] [] = []
zipByVar f (x :: xs) (y :: ys) = f x y :: zipByVar f xs ys

||| The entries of inner variables put in front of a scope's.
export
prepend : ByVar as a -> ByVar vs a -> ByVar (as ++ vs) a
prepend [] xs = xs
prepend (y :: ys) xs = y :: prepend ys xs

||| One entry per name, each made from the element of a list as long.
export
byVarFrom : (vs : Scope) -> (f : a -> b) -> (xs : List a) -> (0 _ : length xs = length vs) -> ByVar vs b
byVarFrom [] f [] _ = []
byVarFrom (_ :: vs) f (x :: xs) same = f x :: byVarFrom vs f xs (injective {f = S} same)
byVarFrom [] f (_ :: _) Refl impossible
byVarFrom (_ :: _) f [] Refl impossible

||| The same entry for every name.
export
everyVar : (vs : Scope) -> a -> ByVar vs a
everyVar [] x = []
everyVar (_ :: vs) x = x :: everyVar vs x

||| The role of the argument at a position: past the type constructor's
||| arguments, none is there to key anything.
public export
roleAt : Nat -> List Role -> Role
roleAt j rs = fromMaybe Index (getAt j rs)

||| The positions whose role the test picks, in order.
public export
positionsOf : (Role -> Bool) -> List Role -> List Nat
positionsOf p rs = map fst (filter (p . snd) (zip [0 .. length rs] rs))

||| Does the key hold the argument at a position of this role?
public export
inKey : Role -> Bool
inKey Keyed = True
inKey Formed = True
inKey Held = False
inKey Index = False

||| Does the growth check watch the argument at a position of this role?
public export
watched : Role -> Bool
watched Index = False
watched _ = True

||| What a module the session loaded is to the program: where its code
||| comes from, as the registry classifies it by the package Idris loaded
||| it from; its source file, when the project has one; and its name as a
||| location prints it. Facts of the module, which nothing the program
||| does changes.
public export
record LoadedModule where
  constructor MkLoadedModule
  origin : Origin
  source : Maybe String
  printed : Shown

||| The modules the session loaded, each with what it is to the program,
||| read once when the session has loaded the program (`Errors.modulesOf`).
public export
Modules : Type
Modules = SortedMap ModuleIdent LoadedModule

-- The records of what is read once are read by their fields as `.tree`,
-- `.type` and kin: a field named as a function of the translation's own
-- (`Cases.tree`) or as one of Idris's (`GlobalDef`'s type) is no prefix
-- function beside it.
%prefix_record_projections off

||| Whether Idris proved that every call of a definition ends: its
||| termination check's verdict, which follows everything the definition
||| calls, read once (`Boundary`). A constructor ends: applying one runs
||| nothing.
public export
data Ends = ProvedToEnd | NotProvedToEnd

||| What a value of a type, held at run time, is to the choices
||| (`Choices`): a member of its type's choice whatever an instance
||| substitutes (an implementation's type, a polymorphic function's); never
||| one (a type constructor no interface is, a constant, a function on
||| values); or what the instance decides, where the type's head is a
||| variable or a definition its arguments leave stuck, which an instance's
||| arguments may make either.
public export
data Holding = AMember | NoMember | ByInstance

||| Where a definition's values are members of a choice, read once off its
||| type in normal form (`Boundary`): what a value given at each binder the
||| type shows is (a constructor's field, a delayed argument, at the type
||| under the delay), and what the definition applied to each count of
||| arguments gives, from none to as many as the type shows binders, so one
||| more than those. The translation tests a type only where the instance
||| decides (`ByInstance`), and so does the growth check.
public export
record MemberPlaces where
  constructor MkMemberPlaces
  given : List Holding
  gives : List1 Holding

||| A binder or a count of arguments past those a definition's type shows:
||| an instance's type may show more only where what the type gives after
||| all of them is the instance's to decide.
beyond : MemberPlaces -> Holding
beyond ps = case last ps.gives of
  ByInstance => ByInstance
  _ => NoMember

||| What a value given at binder `j` of a definition is (`MemberPlaces`).
export
givenAt : Nat -> MemberPlaces -> Holding
givenAt j ps = fromMaybe (beyond ps) (getAt j ps.given)

||| What a definition applied to `k` arguments gives (`MemberPlaces`).
export
givesAfter : Nat -> MemberPlaces -> Holding
givesAfter k ps = fromMaybe (beyond ps) (getAt k (forget ps.gives))

||| What Idris's types say of the `believe_me` an exit's body gives its
||| action any result by (`Hook.Exits`), read once at the boundary, with
||| the definition's variables as placeholders: the value it gives is an
||| action on the world, taking it at `valueWorld`. The action it is given
||| is one too, which the boundary checks; what that action gives is read
||| at each instance, off the argument the instance passes
||| (`Terms.exitAction`), since a placeholder stands for a type only the
||| instance fixes.
public export
record ExitTypes where
  constructor MkExitTypes
  valueWorld : Uses

||| A definition of the frozen context as the translation reads it, each
||| part read once (`Boundary`): its place, the definition, its type as the
||| context's accessor reads it, its body when it matches (`Matched`),
||| whether Idris proved it ends (`Ends`), what the registry makes of it
||| (`Registered`), the hook that lowers its calls, read against its type
||| and its library functions' definitions (`Resolve.Lowered`), for an
||| exit (`Hook.Exits`) what Idris's types say of the `believe_me` it ends
||| with (`ExitTypes`), where its values are members of a choice
||| (`MemberPlaces`), and the binders of its type in normal form, the
||| normal form the member table is read off, each with what the
||| definition takes there (`Closed.argumentAt`) and its type (`Binders`);
||| and what the whole program's definitions say of it (`facts`), which
||| only all of them read can give: nothing while they are being read
||| (`()`), its constructors once they are (`ConstructorAt`), and its
||| `Nature` once those are.
public export
record DefinitionRead (facts : Type) where
  constructor MkDefined
  placement : Placement
  def : GlobalDef
  type : ClosedTerm
  matched : Maybe Matched
  ends : Ends
  registered : Registered
  loweredBy : Maybe (Lowered CheckedLibrary)
  exitTypes : Maybe ExitTypes
  places : MemberPlaces
  binders : Binders ArgumentAt []
  nature : facts

||| A constructor of a type constructor, as the boundary read it once every
||| definition was read (`Boundary.readProgram`): the definition its type
||| constructor lists, read from what `main` reaches, which Idris made a
||| constructor, its tag, and the arguments Idris gives it, which every
||| match on it binds. Idris tags a type's constructors in the order its
||| declaration lists them, from 0, and a match or an application reads a
||| constructor at its tag. A type constructor that lists a name the
||| context defines as nothing, or as no constructor, or a constructor at
||| another place than its tag, is refused there, as the compiled module it
||| is, so no reader of a type constructor's constructors meets one, and a
||| constructor's tag is its place in its type's list.
public export
record ConstructorAt where
  constructor MkConstructorAt
  read : DefinitionRead ()
  tag : Nat
  arity : Nat

||| A type constructor's constructors, as its declaration gives them: none
||| declared (`data T : Type`, never given any), so that what its values
||| are no reader knows; or declared, each as the boundary read it, in the
||| order the declaration lists them (`ConstructorAt`), none for an empty
||| type, which has no values. The two are the problem's: Idris records
||| the first as no list at all, the second as a list.
public export
data Constructors = NoneDeclared | DeclaredAs (List ConstructorAt)

||| What the translation reads of a type constructor's definition: its
||| parameters, the role of the argument at each position (`Role`), the
||| first first, what its values are as numbers go, and its constructors as
||| the boundary read them (`Constructors`), which every reader of a value
||| of the type reads.
public export
record TyConFacts where
  constructor MkTyConFacts
  params : List Nat
  roles : List Role
  natness : Natness
  constructors : Constructors

||| What the translation reads of a definition as a type constructor: a
||| type constructor's facts (`TyConFacts`), found once from every
||| definition read (`TypeConstructors`), or none, for any other
||| definition. A reader of a type constructor matches here, so no reader
||| holds a type constructor without its facts.
public export
data AsTypeConstructor = ATypeConstructor TyConFacts | NoTypeConstructor

||| What the walk that names blocks over what `main` reaches calls a
||| definition (`Boundary.blockNamesOf`): a nested block by its place under
||| the definition that refers to it first, which an unrelated edit does
||| not move, and any other definition it entered by its own name; or
||| nothing, for a definition no walk entered. A nested block no walk
||| reaches is no part of the compiled program: a local definition is a
||| function, and eager evaluation runs nothing of one no call reaches.
public export
data WalkedName = NamedByWalk String | NotWalked

||| What follows of a definition from the whole program's definitions,
||| found once from all of them, before any phase reads one
||| (`TypeConstructors.readWhole`): its facts as a type constructor, what
||| the walk that names blocks calls it, and what Idris proved of its
||| loops, the component it is proved to end in or, with no proof, that it
||| may diverge.
public export
record Nature where
  constructor MkNature
  asTypeConstructor : AsTypeConstructor
  called : WalkedName
  termination : Termination

||| A definition as every phase after the boundary reads it: with what the
||| whole program's definitions say of it (`Nature`).
public export
Defined : Type
Defined = DefinitionRead Nature

||| A definition given what the whole program's definitions say of it.
export
withNature : facts' -> DefinitionRead facts -> DefinitionRead facts'
withNature n d =
  MkDefined d.placement d.def d.type d.matched d.ends d.registered d.loweredBy d.exitTypes d.places d.binders n

||| The pair Idris's `%pair` names, which holds a value and the rest of a
||| list as one, and its two projections, which take it apart: each by its
||| definition's address and as the boundary read it, with what the whole
||| program's definitions say of it (`facts`), as every definition read is.
||| Read once, after the freeze (`Boundary.readProgram`), so no phase looks
||| the pair's names up again.
public export
record PairRead (facts : Type) where
  constructor MkPairRead
  pairAddress : Address
  pairDefined : DefinitionRead facts
  firstAddress : Address
  firstDefined : DefinitionRead facts
  secondAddress : Address
  secondDefined : DefinitionRead facts

||| The pair as every phase after the boundary reads it (`PairRead`).
public export
Pairing : Type
Pairing = PairRead Nature

||| The pair with each of its definitions given what `f` says of it.
export
pairWith : (DefinitionRead facts -> DefinitionRead facts') -> PairRead facts -> PairRead facts'
pairWith f pg =
  MkPairRead pg.pairAddress (f pg.pairDefined) pg.firstAddress (f pg.firstDefined) pg.secondAddress (f pg.secondDefined)

||| Is a name the definition at an address the boundary read (the pair type
||| `%pair` names, base's `plus` on `Nat`; nothing for a program that
||| defines none)? The name is the definition the frozen context gives it,
||| compared by its address, so no two names are compared; a name it
||| defines as nothing names no definition.
export
namedAt : Frozen -> Maybe Address -> Name -> Bool
namedAt fz Nothing n = False
namedAt fz (Just a) n = case definitionIn fz n of
  DefinedAs i resolved _ defines => sameAddress (definedAddress i resolved defines) a
  NotDefined _ => False

||| What a definition takes at each binder of its type in normal form, in
||| order (`binders`).
public export
(.taken) : DefinitionRead facts -> List ArgumentAt
(.taken) d = readOfEach d.binders

||| Where a definition's values are members of a choice (`MemberPlaces`),
||| read once at the boundary: the lookup the translation and the growth
||| check read it by, with `givenAt` and `givesAfter`.
export
memberPlaces : DefinitionRead facts -> MemberPlaces
memberPlaces d = d.places

||| The type a member at a use is applied as by, `{0 t : Type} -> (f : t)
||| -> t` (the form's type, then the form, giving a value of the form's
||| type), with the names of its two binders, which an instance of a
||| member at a use names its first two parameters by. Made once
||| (`applicationOver`), so the names are the type's binders' and no others.
public export
record Application where
  constructor MkApplication
  formType : Name
  form : Name
  type : ClosedTerm

||| The type a member at a use is applied as by, its binders the names
||| given and its universe `u`'s.
export
applicationOver : (formType, form, u : Name) -> Application
applicationOver t f u =
  MkApplication t f
    (Bind EmptyFC t (Pi EmptyFC erased Implicit (TType EmptyFC u))
          (Bind EmptyFC f (Pi EmptyFC top Explicit (Local EmptyFC Nothing 0 First))
                (Local EmptyFC Nothing 1 (Later First))))

||| What the checker made of a metavariable a term the boundary read names,
||| at the entry `i` the term gives it, the name Host's `Solve` unfolds:
||| read once, before the freeze, with the definitions, and held of the
||| frozen context `fz`, which is made of what was read (`Host.frozenFrom`,
||| `Host.heldAt`, `Boundary.readProgram`): a solution, the definition at
||| that entry, of no arguments and one leaf, which is the solution, held
||| with the entry's placement, which a walk enters before it walks the
||| solution, and with the premises `Solve` states of such a definition, at
||| quantity 0; or a
||| hole the source left, which the checker left unsolved. Essential: the
||| problem has both, and a hole is no term. The checker writes a solution
||| in no other shape, so the boundary refuses a metavariable at no entry,
||| or at one of any other definition, as the compiled module it is, and
||| no reader meets either.
public export
data Solution : Frozen -> Int -> Type where
  SolvedAs : {0 fz : Frozen} -> {0 i : Int} -> {0 d : GlobalDef} -> {0 info : PMDefInfo} -> {0 body : Body []} ->
             {0 leaf : Int} -> (solution : ClosedTerm) -> (placement : Placement) ->
             (0 defines : Defines fz (Resolved i) d) -> (0 _ : definition d = PMDef info [] body) ->
             (0 _ : TreeOf body (STerm leaf solution)) ->
             (0 _ : placement = placementAt i (resolvedPlaced Host.resolvedItself defines)) -> Solution fz i
  Unsolved : {0 fz : Frozen} -> {0 i : Int} -> {0 d : GlobalDef} -> {0 locals : Nat} -> {0 flags : HoleFlags} ->
             (0 _ : Defines fz (Resolved i) d) -> (0 _ : definition d = Hole locals flags) -> Solution fz i

||| The place of the entry a metavariable was read at (`Solution`): a
||| solution's, which it holds; a hole's, placed off the evidence it was
||| read with, as the solution's was, so no reader tests the entry again.
export
solutionPlacement : {i : Int} -> Solution fz i -> Placement
solutionPlacement (SolvedAs _ placement _ _ _ _) = placement
solutionPlacement (Unsolved defines _) = placementAt i (resolvedPlaced Host.resolvedItself defines)

||| The solution of each metavariable a term the boundary read names, by
||| its entry in the frozen context, each read at that entry (`Solution`).
||| An entry is a key, not an index: Idris's terms carry a metavariable's
||| entry as a bare `Int`, which says nothing of the table.
public export
Solutions : Frozen -> Type
Solutions fz = SortedDMap Int (Solution fz)

||| No solution read yet.
export
noSolutions : Solutions fz
noSolutions = Data.SortedMap.Dependent.empty

||| The table with the solution at an entry added.
export
withSolution : (i : Int) -> Solution fz i -> Solutions fz -> Solutions fz
withSolution i s table = Data.SortedMap.Dependent.insert i s table

||| What the translation reads of the program: the context frozen once the
||| program is read, of the definitions the reading met, every termination
||| verdict it reaches written, which every normaliser reads; the
||| program's entry, `main`, as it was read, which every phase that starts
||| from it starts from; every definition the translation can meet from the
||| entry, the entry's among them, each read once and kept by its entry in
||| the context (`Boundary.readProgram`); the type a member at a use is
||| applied as by, with its binders' names, interned once (`Application`);
||| the type constructors of the interfaces the program loaded, by full
||| name, Idris's own table of them, since nothing the translation does
||| declares one (an implementation is a value of one of these types, or of
||| a pair of or a function to such values,
||| `Boundary.implementationHolding`); the solution of every metavariable a
||| term read names, by its entry (`Solutions`), which every walk that
||| meets one reads; the pair Idris's `%pair` names (`PairRead`), which
||| holds values as one, none for a program that declares no `%pair`; the
||| address of `IO`'s type constructor (`ioType`), the type of what
||| `unsafePerformIO` runs, which the program's root runs `main` as, read
||| once after the freeze, so `IO` is known by that identity and never by
||| its name again, nor by its shape (`Terms.ioOf`); and the address of
||| base's `plus` on `Nat` (`natPlus`), which an index term reads as a sum
||| (`Types.indexTerm`), read once with `IO`'s and known by that identity
||| alone, none for a program whose reading meets no `plus`. Each definition holds
||| what the whole program's definitions say of it (`facts`): nothing while
||| they are being read, its constructors once they are, and its `Nature`
||| once those are (`Read`); the pair's, as every other's. Nothing the
||| translation does changes it.
public export
record Reading (facts : Type) where
  constructor MkReading
  frozen : Frozen
  entry : DefinitionRead facts
  definitions : SortedMap Int (DefinitionRead facts)
  application : Application
  interfaces : SortedSet Name
  solutions : Solutions frozen
  pair : Maybe (PairRead facts)
  ioType : Address
  natPlus : Maybe Address

||| What every phase after the boundary reads of the program: each
||| definition with its `Nature`.
public export
Read : Type
Read = Reading Nature

||| The address of the pair type `%pair` names, as the reading holds the
||| pair (`PairRead`); nothing for a program that declares no `%pair`.
export
pairTypeIn : Reading facts -> Maybe Address
pairTypeIn r = (.pairAddress) <$> r.pair

||| What follows of a definition from the whole program's definitions,
||| read off what was found from all of them, each by address: the type
||| constructors' facts, a table that holds a type constructor's and no
||| other's (`TypeConstructors`); what the walk that names blocks calls each
||| definition it entered (`Boundary.blockNamesOf`); and the component each
||| definition whose loops Idris proved to end is proved in (`Recursion`),
||| one with no proof one that may diverge, whatever left it unproved.
export
natureFrom : (tyCons : SortedMap Address TyConFacts) -> (called : SortedMap Address String) ->
             (proved : SortedMap Address ComponentId) -> DefinitionRead facts -> Nature
natureFrom tyCons called proved d =
  let a = addressOf d.placement in
  MkNature (maybe NoTypeConstructor ATypeConstructor (lookup a tyCons))
           (maybe NotWalked NamedByWalk (lookup a called))
           (maybe Unproved (\c => InComponent c.index) (lookup a proved))

||| The reading with every definition given what the whole program's
||| definitions say of it (`nature`), the entry as every other.
export
natured : (DefinitionRead facts -> Nature) -> Reading facts -> Read
natured nature r =
  MkReading r.frozen (withNature (nature r.entry) r.entry) (map (\d => withNature (nature d) d) r.definitions)
            r.application r.interfaces r.solutions (map (pairWith (\d => withNature (nature d) d)) r.pair) r.ioType
            r.natPlus

||| What was read of a name: the definition at the entry the frozen context
||| resolves it to, with the entry and the evidence that the name resolves
||| there and that the context defines it, so that a reader that also needs
||| the entry's address resolves the name once (`Definitions.definedAddress`);
||| or no definition, for a name the context defines as nothing (a probe's,
||| a binder's).
public export
data ReadOf : Frozen -> Name -> Type -> Type where
  ReadAs : {0 ctx : Frozen} -> {0 n : Name} -> {0 facts : Type} -> {0 g : GlobalDef} -> (i : Int) ->
           (0 _ : Resolves ctx n i) -> (0 _ : Defines ctx n g) -> DefinitionRead facts -> ReadOf ctx n facts
  NoDefinition : {0 ctx : Frozen} -> {0 n : Name} -> {0 facts : Type} ->
                 (0 _ : (g : GlobalDef) -> Not (Defines ctx n g)) -> ReadOf ctx n facts

-- The one miss of the reading, a definition's (`readEntry`) or a
-- solution's (`solutionIn`): every definition a phase can meet, a
-- metavariable among them, was read from what `main` reaches, so an entry
-- the context defines and the reading missed is the compiler's error,
-- which no program decides.
missedEntry : Frozen -> Name -> Core a
missedEntry fz n = throw (InternalError ("the definitions read from what main reaches miss " ++ show (fullNameIn fz n)))

||| What was read of the definition at the entry a name resolves to, by
||| that entry, for a reader that resolved the name once already: the one
||| read of an entry, which `readIn` reads a name by. Every definition a
||| phase can meet was read from what `main` reaches, so an entry the
||| context defines and the reading missed is the compiler's error
||| (`missedEntry`).
export
readEntry : (fz : Frozen) -> SortedMap Int (DefinitionRead facts) -> (n : Name) -> (i : Int) ->
            (0 _ : Resolves fz n i) -> Core (DefinitionRead facts)
readEntry fz ds n i _ = case lookup i ds of
  Just d => pure d
  Nothing => missedEntry fz n

||| What was read of a name among the definitions read from what `main`
||| reaches, each by its entry in the frozen context (`ReadOf`): the one
||| reading of a name, which the boundary also finds the entry by before
||| the reading is whole, the entry read as every entry is (`readEntry`).
export
readIn : (fz : Frozen) -> SortedMap Int (DefinitionRead facts) -> (n : Name) -> Core (ReadOf fz n facts)
readIn fz ds n = case definitionIn fz n of
  NotDefined none => pure (NoDefinition none)
  DefinedAs i resolved _ defines => ReadAs i resolved defines <$> readEntry fz ds n i resolved

||| The solution the boundary read of the metavariable at entry `i`
||| (`Solution`), from the reading's table, by the entry the walk's term
||| gives it. Every term a phase walks is one the boundary read from what
||| `main` reaches, or Idris's normal form of such terms, which names no
||| metavariable they do not, and the boundary read the solution of every
||| metavariable those name, so one the table misses is the reading's
||| miss, as a definition's is (`missedEntry`).
export
solutionIn : (r : Reading facts) -> (i : Int) -> Core (Solution r.frozen i)
solutionIn r i = case lookupPrecise i r.solutions of
  Just s => pure s
  Nothing => missedEntry r.frozen (Resolved i)

||| What was read of a name (`readIn`) in the reading.
export
readOf : (r : Reading facts) -> (n : Name) -> Core (ReadOf r.frozen n facts)
readOf r n = readIn r.frozen r.definitions n

||| The definition a name names, as it was read (`readOf`); nothing for a
||| name the context defines as nothing, a probe's among them.
export
definedIn : Reading facts -> Name -> Core (Maybe (DefinitionRead facts))
definedIn r n = do
  ReadAs _ _ _ d <- readOf r n
    | NoDefinition _ => pure Nothing
  pure (Just d)

%prefix_record_projections on

------------------------------------------------------------------------------
-- The growth model's sites
------------------------------------------------------------------------------

-- The site table's records are read by their fields as `.site`, `.fc` and
-- kin, a field named as a variable every walk binds (`fc`, `site`) is no
-- prefix function beside it.
%prefix_record_projections off

||| A head at an entry the frozen context defines: what the boundary read of
||| the definition the context gives the name the head is called by
||| (`Errors.defined`), which every reader of the head reads, a type
||| constructor's facts and a constructor's tag among it, at the address the
||| context gives that name. One read, which whatever holds the head holds
||| once.
public export
record HeadDefinedAt (a : Address) where
  constructor MkHeadDefinedAt
  0 frozenIn : Frozen
  0 calledBy : Name
  defined : Defined
  0 addressed : definitionAddress (gamma (defsOf frozenIn)) calledBy = Just a

||| The definition a site's reading met a head at, by the head's address,
||| the one the reading's frozen context gives the name the head is called
||| by (`HeadDefinedAt`); or, at an entry the context defines nothing at,
||| that entry, which a message shows the head by. Two cases the host's
||| context has: an entry made with a definition, and one made without.
public export
data HeadDef : Address -> Type where
  HeadDefined : {0 a : Address} -> HeadDefinedAt a -> HeadDef a
  HeadUndefined : {0 a : Address} -> (0 frozenIn : Frozen) -> (0 calledBy : Name) -> (entry : Int) ->
                  (0 resolved : getNameID calledBy (gamma (defsOf frozenIn)) = Just entry) ->
                  (0 none : (d : GlobalDef) -> Not (Defines frozenIn calledBy d)) ->
                  (0 addressed : definitionAddress (gamma (defsOf frozenIn)) calledBy = Just a) -> HeadDef a

||| A template with the definition of each recursion it holds and of each
||| head it names, as its reading met them: what a site writes at a static
||| argument, and every part of it the growth graph draws from.
public export
record TemplateRead where
  constructor MkTemplateRead
  template : Template
  recursionsRead : All RecursionDef (recursions template)
  headsRead : All HeadDef (namedHeads template)

||| The templates of some read, in order.
public export
templatesOf : List TemplateRead -> List Template
templatesOf [] = []
templatesOf (r :: rs) = r.template :: templatesOf rs

||| Templates read hold each one's recursions, in order.
public export
allRead : (rs : List TemplateRead) -> All RecursionDef (recursionsIn (templatesOf rs))
allRead [] = []
allRead (r :: rs) = allJoined r.recursionsRead (allRead rs)

||| Templates read name each one's heads, in order.
public export
allHeads : (rs : List TemplateRead) -> All HeadDef (namedHeadsIn (templatesOf rs))
allHeads [] = []
allHeads (r :: rs) = allJoined r.headsRead (allHeads rs)

||| Each of some templates with the definitions of the recursions it holds
||| and the heads it names, read off those of the list.
public export
eachRead : (ts : List Template) -> All RecursionDef (recursionsIn ts) -> All HeadDef (namedHeadsIn ts) -> List TemplateRead
eachRead [] _ _ = []
eachRead (t :: ts) held heads =
  MkTemplateRead t (allBefore (recursions t) held) (allBefore (namedHeads t) heads)
    :: eachRead ts (allAfter (recursions t) held) (allAfter (namedHeads t) heads)

||| A site's static argument read: the mode it is read in, the context of
||| which is the one every normal form and definition of the reading is
||| over, the form its reading reads, how it was read off the term in that
||| context and the evidence that the contraction it was read by left no
||| redex it contracts (`contractingFor`), the template it reads as with
||| what that says of the form, and what the site writes there, the
||| template with a form's extents as its key holds them, with the
||| definition of each recursion that holds and of each head it names, read
||| where the reading met it.
public export
record SiteReading (k : Readings.Static) (t : ClosedTerm) where
  constructor MkSiteReading
  0 mode : Readings.Mode
  form : ClosedTerm
  0 formFrom : FormFrom k mode.inContext t form
  0 maximal : EtaNormal (contractingFor mode) form
  read : Template
  0 describes : ReadAs mode [] form read
  template : Template
  0 formed : KeyForm read template
  recursionsRead : All RecursionDef (recursions template)
  headsRead : All HeadDef (namedHeads template)

||| Where a site's writer reads its parameters: all its own; or, in the
||| walk of a member's application at a use, its own below `from` and from
||| there on the positions of the application the use gives, parameter
||| `from + j` its position j (`AtUse`). The two ranges are
||| the coordinates of one scope, the writer's parameters first.
public export
data Parameters = OwnOnly | UseFrom Nat

||| What a parameter of a writer is, read as a site's `Parameters` say.
public export
data ParameterOf = WritersOwn Nat | UsesPosition Nat

export
parameterOf : Parameters -> Nat -> ParameterOf
parameterOf OwnOnly i = WritersOwn i
parameterOf (UseFrom from) i = if i < from then WritersOwn i else UsesPosition (minus i from)

||| A dictionary of the writer's that holds values as one: its dictionary
||| parameter i, or one its text binds (`BoundPlace`). What it holds is
||| bounded at its place's held positions.
public export
data OwnHolder = OwnParameter Nat | OwnBinding BoundPlace

export
Eq OwnHolder where
  OwnParameter i == OwnParameter j = i == j
  OwnBinding a == OwnBinding b = a == b
  _ == _ = False

||| What a message shows an argument by (below).
public export
data ArgumentText : Type

||| One value of a list of values a dictionary holds as one, the list its
||| receiver is given (`Closed.packedType`).
public export
data HeldItem : Type

||| How an argument's template was written: off a term, at its kind, as its
||| target is given it (`asGiven`) over that term's one reading (`Template.rooted`),
||| so what the site writes is that reading's template wherever the target
||| is given it as written; or off no term, a part of a type already read,
||| or a choice's member the walk names itself.
public export
data WrittenAs : Static -> Maybe ClosedTerm -> Maybe ChoiceHead -> Template -> Root -> Type where
  OffTerm : (r : SiteReading k t) -> WrittenAs k (Just t) given (asGiven given (r.template, root)) root
  NoTerm : WrittenAs k Nothing given w root

||| What a site wrote off a term is that term's reading's template, as its
||| target is given it, the equation the reading lemma at the site is
||| carried through (`Proof.Covers.siteWritesRead`).
export
0 writtenReading : WrittenAs k (Just t) given w root -> (r : SiteReading k t ** w = asGiven given (r.template, root))
writtenReading (OffTerm r) = (r ** Refl)

||| One argument a site writes, whole: the target's parameter it is at (of
||| a dispatched method, its own, in the order its field's lambdas take
||| them), its kind, the template written there, with the definition of
||| each recursion it holds as the reading met it, and its root, with what
||| its kind's reader read at each address the root names, where the
||| reading met the name (`HeadsRead`: of a family's, the type constructor,
||| which the flow carries beside each heading it is given; of any other
||| kind's, nothing), as its kind's one reading gives them (`Template.rooted`) and as
||| the target is given it (`asGiven`), the closed term it was read off,
||| over the writer's markers and the site's stand-ins (none for a part of
||| a type already read),
||| those stand-ins, which a reading of the term again reads it with, the
||| choice a dictionary the running program chooses there is a member of
||| (its binder's type's), which a reading again reads it with too, the
||| lists of values a dictionary there holds as one, each a list an
||| instance may give the target with it (none where it holds none, and
||| for every other kind), and what a message shows it by. Only a refusal
||| prints that, and most arguments are in none, so it is read where a
||| message is made (`Sites.showArgument`). How the template was written is kept
||| beside it (`WrittenAs`).
public export
record Argument where
  constructor MkArgument
  position : Nat
  kind : Static
  template : Template
  recursionsRead : All RecursionDef (recursions template)
  root : Root
  rootHeads : HeadsRead kind (rootAddresses root)
  term : Maybe ClosedTerm
  stands : List StandIn
  memberOf : Maybe ChoiceHead
  0 writtenAs : WrittenAs kind term memberOf template root
  holds : List (List1 HeldItem)
  shown : ArgumentText

||| One value of a list a dictionary holds as one, as the place that gives
||| the list writes it: a value of a type the walk knows, read as a type
||| argument is, each reading of it an evaluation gives (`Graph.evaluated`);
||| the one value a dictionary of the writer's holds (its parameter, or one
||| its text binds), its values packed into one, as the translation holds a
||| variable that holds values (`Terms.holed`); each value the writer's
||| dictionary parameter holds, as itself, which a request that keeps the
||| parameter as it was given passes on (`Cases.heldHere`); or each value a
||| member of a choice holds, which a dispatch on a value of the choice puts
||| in that value's place (`Choices.heldMember`). A value is no list: no
||| list is held inside another but as the one value its type packs.
data HeldItem : Type where
  OfType : List1 Argument -> HeldItem
  PackedBy : OwnHolder -> HeldItem
  EachOf : Nat -> HeldItem
  MembersOf : ChoiceHead -> HeldItem

||| What a site reaches: a definition it calls (a function, an
||| implementation, a projection, a constructor holding dictionaries) or a
||| type constructor it builds, each at its address with what the boundary
||| read of it, which the walk that enters it reads, so that nothing finds
||| it again by address; method `k` of a dictionary, which the template
||| is, with that dictionary's root, the application of a compile-time form
||| at a use, which no definition is (`AtUse`), at the
||| form's type (0), the form (1) and the use's static arguments (2 on), or
||| the choice of a head, a member of which it makes, its one argument,
||| with what a message reads of the head (`HeadRead`). Or
||| the writer itself again, where its tree takes apart a field of its
||| dictionary parameter at a path of fields, which the running program may
||| have chosen (`Translate.Cases.heldHere`): the dictionary rebuilt with
||| that field a value it holds, and each member the field's choice has
||| there in turn (`Translate.Choices.heldDispatch`). The parameter's own
||| argument is held apart, since the node it is read at rebuilds it
||| (`Heads.reaches`); the site's arguments are the writer's other static
||| ones, each as it is, a dictionary with the values it was given. The
||| values a dictionary argument holds as one are the argument's own
||| (`Argument.holds`), written where the argument lands. Or the place a
||| `let` or a lambda's argument binds a dictionary that closes over values
||| at, which keeps the list of them it holds as one (`Terms.letIn`): no
||| callee is given it, and every use of the dictionary reads its values
||| there (`PackedBy`).
public export
data SiteReach : Type where
  Calls : Address -> Defined -> SiteReach
  Builds : Address -> Defined -> SiteReach
  Dispatches : Template -> Root -> Nat -> SiteReach
  Applies : SiteReach
  Makes : (k : ChoiceHead) -> HeadRead k -> SiteReach
  Repacks : Argument -> List1 Nat -> SiteReach
  Keeps : BoundPlace -> List1 HeldItem -> SiteReach

||| The role a site's reach gives it at the node of the model's walk that
||| holds it (`Annotated.ReachKind`).
public export
ReachOf : SiteReach -> ReachKind
ReachOf (Calls _ _) = CallReach
ReachOf (Builds _ _) = BuildReach
ReachOf (Dispatches _ _ _) = DispatchReach
ReachOf Applies = ApplyReach
ReachOf (Makes _ _) = MakeReach
ReachOf (Repacks _ _) = RepackReach
ReachOf (Keeps _ _) = KeepReach

||| One site: who wrote it, by address and as it was read (whose parameters
||| the templates' `Var`s are, as `params` reads them, and whose type names
||| them), the definition whose text holds it, as it was read, what it
||| reaches, the argument written at each static position of the target,
||| and where it is.
public export
record Site where
  constructor MkSite
  writer : Address
  writerDef : GlobalDef
  params : Parameters
  within : GlobalDef
  reach : SiteReach
  arguments : List Argument
  fc : FC

||| A site as the walk makes it: where in its writer's text it was made,
||| and the site. A reading's sites are taken in the order of their places
||| in the text (`Place.grownFrom`), which is the order every reader of a
||| reading's sites in turn reads them in.
public export
record Made where
  constructor MkMade
  place : Place
  site : Site

||| A site the walk made, held at a node of the model's walk
||| (`Annotated`) in the field of its role, which its reach gives.
public export
record AtRole (r : ReachKind) where
  constructor MkAtRole
  made : Made
  0 role : ReachOf made.site.reach = r

||| What a message shows an argument by, read where a message is made
||| (`Sites.showArgument`): a template, each marker by the writer's name for its
||| parameter, with the definition of each recursion it holds and each head
||| it names, which name the rest; a closed term; a term as written, in its
||| scope, with the stand-ins the walk had made and the name each variable
||| of the scope was bound with; or one of the writer's parameters. It holds the definitions the
||| names come from, never a computation: the sites are kept, and a
||| computation kept with them is one the pipeline's closure analysis cannot
||| tell from any other of its type, those that read the translation's
||| state among them.
data ArgumentText : Type where
  TemplateText : (writer : GlobalDef) -> (t : Template) -> All RecursionDef (recursions t) -> All HeadDef (namedHeads t) ->
                 ArgumentText
  TermText : ClosedTerm -> ArgumentText
  WrittenText : {vs : Scope} -> (writer : GlobalDef) -> (stands : List StandIn) -> (names : ByVar vs Name) ->
                Core.TT.Term.Term vs -> ArgumentText
  ParameterText : (writer : GlobalDef) -> Nat -> ArgumentText

||| How the values a dictionary's place holds are written on: as they are,
||| or as one of the chains of pairs a list of two up to `upTo + 1` values
||| packs to (`Proof.Held.pairChainsUpTo`), with the evidence it is one of
||| them. A writing of held values on writes the chain its packing names
||| and nothing else (`packingTemplate`).
public export
data Packing : Type where
  AsTheyAre : Packing
  Chained : (pairAt : Address) -> (upTo : Nat) -> (chain : Template) ->
            (0 listed : Elem chain (pairChainsUpTo pairAt upTo)) -> Packing

||| The template a packing writes.
public export
packingTemplate : Packing -> Template
packingTemplate AsTheyAre = Template.Var 0 0
packingTemplate (Chained _ _ chain _) = chain

||| A site of a node's reading, numbered once among every reading's sites
||| (`Graph.numberedReadings`): its number, which names it wherever what it wrote
||| is read, and the site.
public export
record Entry (k : Nat) where
  constructor MkEntry
  number : Fin k
  site : Site

||| A numbered site held at a node of the model's walk (`Annotated`) in the
||| field of its role, which its reach gives.
public export
record NumberedAt (k : Nat) (r : ReachKind) where
  constructor MkNumberedAt
  entry : Entry k
  0 role : ReachOf entry.site.reach = r

||| What made an arc: the entry whose site wrote it and the argument whose
||| template gave it, a value of a list a dictionary argument holds among
||| them; an
||| implementation's method field, which placed the implementation's
||| parameter, the arc's source, among the method function's (a leading
||| arc); field k of the definition that gives a dictionary, as it was
||| read, whose template it is, with the definitions of the recursions it
||| holds; or the values
||| a dictionary's place holds, the arc's source, written on as their
||| packing says: into the pairs that hold a list of several, at most the
||| held count of them (`Graph.heldPackings`), or into the list another place is
||| given, as they are or as the one value a list of several packs to
||| (`Graph.heldWritings`).
public export
data Wrote : (entries : Nat) -> Type where
  FromArgument : Entry k -> Argument -> Wrote k
  ThroughMethod : Wrote k
  InField : GlobalDef -> Nat -> TemplateRead -> Wrote k
  PacksHeld : Packing -> Wrote k

||| What the growth graph drew, all of it erased but how many sites there
||| are: the graph and the growth theorem's model it was drawn from, whose
||| sites are every place the program writes a static argument at; how many
||| sites every node's reading holds, numbered once; and the model's sites,
||| each with what wrote it, so that an entry's membership among the
||| model's sites is read off them (`membersOf`).
public export
record SiteDrawing where
  constructor MkSiteDrawing
  0 graph : Graph
  0 model : Model graph
  entries : Nat
  0 kept : List (Bound.Site graph.size, Wrote entries)
  0 keptSites : model.sites = map Builtin.fst kept

||| A node's reading as the model's walk annotated it (`Annotated`): the
||| node, the definition it is read at, and the definition's text with what
||| the walk decided at each place, each request the entry its number made
||| it.
public export
record DrawnReading (k : Nat) where
  constructor MkDrawnReading
  node : Node
  defined : Defined
  tree : ReadingTree (NumberedAt k)

||| The growth model's site table, written once by the growth check
||| (`Growth.checkGrowth`) before the translation: before it, nothing drawn;
||| then what the graph drew, and every node's reading, numbered once, main's
||| among them (the root), so that a reading is named by its number and none
||| is looked up by its node.
public export
data SiteTable : Type where
  Undrawn : SiteTable
  DrawnTable : (drawing : SiteDrawing) -> {readings : Nat} -> Vect readings (DrawnReading drawing.entries) ->
               (root : Fin readings) -> SiteTable

||| A site of the model an argument of a numbered entry wrote: the site, the
||| entry and the argument, how the graph kept it, the entry's number, and
||| the site's membership among the model's sites, which every lemma the
||| graph keeps of a site reads.
public export
record DrawnFrom (d : SiteDrawing) (e : Fin d.entries) where
  constructor MkDrawnFrom
  site : Bound.Site d.graph.size
  entry : Entry d.entries
  argument : Argument
  0 written : Elem (site, FromArgument entry argument) d.kept
  0 numbered : entry.number = e
  0 member : Elem site d.model.sites

-- A kept site is one of the model's.
0 keptMember : (d : SiteDrawing) -> {x : (Bound.Site d.graph.size, Wrote d.entries)} -> Elem x d.kept ->
               Elem (Builtin.fst x) d.model.sites
keptMember d el = replace {p = Elem (Builtin.fst x)} (sym d.keptSites) (elemMap Builtin.fst el)

||| What a numbered entry's arguments are in the model: every site of it an
||| argument of the entry wrote, in the order the graph kept them, each
||| with its membership. A capped position keeps none, and neither does a
||| reading no visit reached.
export
0 membersOf : (d : SiteDrawing) -> (e : Fin d.entries) -> List (DrawnFrom d e)
membersOf d e = among d.kept (keptMember d) id
  where
    among : (ks : List (Bound.Site d.graph.size, Wrote d.entries)) ->
            (inSites : {x : (Bound.Site d.graph.size, Wrote d.entries)} -> Elem x ks -> Elem (Builtin.fst x) d.model.sites) ->
            (inKept : {x : (Bound.Site d.graph.size, Wrote d.entries)} -> Elem x ks -> Elem x d.kept) -> List (DrawnFrom d e)
    among [] _ _ = []
    among ((s, FromArgument en x) :: ks) inSites inKept =
      let rest = among ks (\el => inSites (There el)) (\el => inKept (There el)) in
      case decEq en.number e of
        Yes same => MkDrawnFrom s en x (inKept Here) same (inSites Here) :: rest
        No _ => rest
    among (_ :: ks) inSites inKept = among ks (\el => inSites (There el)) (\el => inKept (There el))

%prefix_record_projections on

||| What the translation derives of the program, each fact by its
||| content: the data family instances (`DataFamily`, which holds its
||| constructors' layouts), each by its link and by its identity, numbered
||| once (the next number `nextFamily`) with the choices', and every
||| family in the order registered; the function instances
||| requested, each by its identity, which is its content (requesting one
||| derives it, and nothing mints it), with its signature, read once where
||| it was first requested, in the order first requested, and the
||| functions made of them; the keys made, each identity's symbol and
||| key, and each key's identity, so that two identities on one key are
||| found (a print that drops what it claims to keep, or a collision of the
||| hash bits a lossy key carries); the choices, each by what it is a
||| choice of (`ChoiceKey`), its family numbered with the families, and
||| each by its family; the dispatches on each choice, by its family, which
||| a new member is joined with, and each dispatch's arms, by its identity
||| and its member's position, which orders its match; and each
||| static argument a request has given, read (`StaticReading`), by its
||| kind and as a link writes it (`Keys.write`), which tells two arguments
||| apart as Idris's `==` does, so an argument read for one request is read
||| for every other: a dictionary with what its form reduces to
||| (`DictionaryReading`), every other kind by itself.
|||
||| The instance table is these facts as the worklist has merged them
||| (`merged`); a step's derivation is these facts as the step made or
||| changed them, which supersede the table's by key.
public export
record Facts where
  constructor MkFacts
  familiesAt : SortedMap (Link Form) DataFamily
  nextFamily : Nat
  dataFamilies : SortedMap FamilyId DataFamily
  familyOrder : SnocList FamilyId
  instances : SortedMap FnId InstanceSig
  fnOrder : SnocList FnId
  fns : SortedMap FnId TFn
  named : SortedMap (Link Form) (String, InstanceKey)
  keyLinks : SortedMap InstanceKey (Link Form)
  choiceIds : SortedMap ChoiceKey FamilyId
  choices : SortedMap FamilyId Choice
  dispatchesOn : SortedMap FamilyId (List Dispatch)
  dispatchArms : SortedMap FnId (SortedMap Nat DispatchArm)
  readings : SortedMap (Static, Written Form) StaticReading
  dictionaries : SortedMap (Written Form) DictionaryReading

||| No fact.
export
noFacts : Facts
noFacts = MkFacts empty 0 empty [<] empty [<] empty empty empty empty empty empty empty empty empty

||| What one step of the translation derived (`Programs.step`): the facts it
||| made or changed, among them its instance's function, by its identity,
||| its families numbered after the table's; and the instances it requested
||| that the table lacked, in the order requested, which the worklist judges
||| against the step's chain and takes in a later generation.
public export
record Derived where
  constructor MkDerived
  facts : Facts
  requested : SnocList Request

||| What a step has derived before it derives anything: no fact, the next
||| family numbered after the table's (`table`), and no request.
export
startingFrom : (table : Facts) -> Derived
startingFrom table = MkDerived ({ nextFamily := table.nextFamily } noFacts) [<]

||| The instance table with a step's derivation merged into it: every fact
||| the step made or changed supersedes the table's by its key, and the
||| families and instances it made come after the table's, in order. The
||| step numbered its families after the table's, so the next family is
||| the step's. Only the step's own facts are walked.
export
merged : Facts -> Derived -> Facts
merged t d =
  let f = d.facts in
  MkFacts (over f.familiesAt t.familiesAt) f.nextFamily (over f.dataFamilies t.dataFamilies) (t.familyOrder ++ f.familyOrder)
          (over f.instances t.instances)
          (t.fnOrder ++ f.fnOrder) (over f.fns t.fns) (over f.named t.named) (over f.keyLinks t.keyLinks)
          (over f.choiceIds t.choiceIds) (over f.choices t.choices) (over f.dispatchesOn t.dispatchesOn)
          (over f.dispatchArms t.dispatchArms) (over f.readings t.readings) (over f.dictionaries t.dictionaries)
  where
    -- The step's entries over the table's, the step's kept where both
    -- hold a key.
    over : SortedMap k v -> SortedMap k v -> SortedMap k v
    over step table = insertFrom (SortedMap.toList step) table

public export
record TS where
  constructor MkTS
  ||| What the translation reads of the program (`Read`), its definitions
  ||| read once the entry is found, before every phase that reads them;
  ||| each computation of the frontend's reads it (`Errors.reading`).
  reads : Read
  ||| The instance table (`Facts`), as the worklist has merged each step's
  ||| derivation into it; a step reads it and writes nothing to it.
  table : Facts
  ||| What the step being run has derived so far (`Derived`), which every
  ||| fact it reads supersedes the table's with (`lookupFact`), and the
  ||| only part of the state a step writes (`derive`).
  derived : Derived
  ||| Where a refusal at no location of its own is: the main module, at
  ||| main once it is found (`Errors.siteAt`).
  moduleFC : NonEmptyFC
  ||| The program's rejections so far, in the order they were found: a
  ||| check or an instance that is rejected does not stop the others
  ||| (`Errors.noting`), so that one run reports every independent one.
  rejected : SnocList Rejection
  ||| The definitions the checks of what the program reaches rejected, and
  ||| the user definitions that refer to them, by address: the translation
  ||| leaves them out, since what it would find there is the same
  ||| rejection again, or something the checks exist to keep from it.
  refused : SortedSet Address
  ||| The escape hatches and holes the source of a user module spells, each
  ||| rejected where it is written: by the module and the name Idris gives
  ||| what the source spells, the name a definition the program reaches
  ||| through them has, so a reach is compared with a spelling as names, not
  ||| as text.
  spelled : SortedSet (ModuleIdent, Name)
  ||| Every module the session loaded, with what it is to the program
  ||| (`LoadedModule`), read once before the checks and never changed:
  ||| every location a term of the program has is in one of them
  ||| (`Errors.toLoc`).
  modules : Modules
  ||| Each static position's height bound, written by the growth check
  ||| (`Growth.checkGrowth`) once, before the translation: a request whose
  ||| static argument is higher, or whose position has none, is the
  ||| check's unsoundness, which the worklist reports (`Finite`).
  bounds : SortedMap Position Nat
  ||| The same bounds as sizes of written arguments, per definition: the
  ||| universe the worklist descends in (`Proof.Requests.Bounds`).
  ||| Nothing is within it until the growth check writes it.
  sizes : Bounds
  ||| The growth model's site table (`SiteTable`), written by the growth
  ||| check once, before the translation, beside the bounds it derives from
  ||| its graph: what the proof that the worklist ends states each request's
  ||| argument against. Until then nothing drawn (`Undrawn`), so no request
  ||| can name a site in it.
  growth : SiteTable

export
initState : Read -> Modules -> NonEmptyFC -> TS
initState r loaded fc = MkTS
  { reads = r
  , table = noFacts, derived = startingFrom noFacts
  , moduleFC = fc, rejected = [<], refused = empty
  , spelled = empty, modules = loaded, bounds = empty
  , sizes = MkBounds (const []) 0 0 0
  , growth = Undrawn }

||| A fact of the instance table as the step being run reads it: what the
||| step derived, which supersedes the table's, else what the table holds.
export
lookupFact : (Facts -> SortedMap k v) -> k -> TS -> Maybe v
lookupFact field key st = lookup key (field st.derived.facts) <|> lookup key (field st.table)

||| The signature of an instance requested by the step being run or before
||| it (`lookupFact`); nothing for one not yet requested.
export
requestedBefore : FnId -> TS -> Maybe InstanceSig
requestedBefore = lookupFact (.instances)

||| A family registered, by its identity, as Emit declares it: a data
||| family's (`dataDeclared`), or a choice's with the members found so far
||| (`choiceDeclared`).
export
declaredIn : Facts -> FamilyId -> Maybe Family
declaredIn t fam = (dataDeclared <$> lookup fam t.dataFamilies) <|> (choiceDeclared <$> lookup fam t.choices)

||| The state with what the step being run has derived changed by `f`: the
||| one write of the instance table's facts a step makes.
export
derive : (Facts -> Facts) -> TS -> TS
derive f = { derived->facts $= f }

||| The state the translation starts from: no fact derived, and the rest of
||| what the phases before it found, the growth check's bounds among them.
export
translating : TS -> TS
translating = { table := noFacts, derived := startingFrom noFacts }
