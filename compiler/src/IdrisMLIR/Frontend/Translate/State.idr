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
import IdrisMLIR.Frontend.Translate.Readings
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Proof.Forms
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Registry.Libraries
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Types

import Data.Fin
import Data.List
import Data.List1
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.Vect

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

||| Parameter classification after instantiation (`Instances.classify`). A
||| type parameter and an implementation (a value of an interface's type,
||| such as an interface constraint, or a polymorphic function passed as a
||| value, `Types.polymorphicType`) are compile-time values: they key the
||| instance and are not parameters at runtime. An implementation may close
||| over runtime values (`{vars : _} -> Show (Term vars)` at the scope a term
||| has): which implementation it is stays a compile-time value, the values
||| replaced by markers, and the parameter holds the values (`Holes`). An
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
data PKind = TypeParam ClosedTerm
           | DictParam ClosedTerm (Maybe Holes)
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

||| An instance's telescope: the sorts of its index parameters, in order,
||| the levels `0 .. p-1` of its body's scope.
export
telescopeOf : List PKind -> List Sort
telescopeOf [] = []
telescopeOf (IndexParam s :: ks) = s :: telescopeOf ks
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

||| A value made from its runtime arguments in order, whatever their number.
export
listed : ({0 m : Nat} -> List (IdrisMLIR.Term.Term m) -> IdrisMLIR.Term.Term m) -> Maker r
listed f = MkMaker (\ys => f (toList ys))

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
  {g : Nat}
  {m : Nat}
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
||| the values it closes over and the shape at the quantity it was read
||| with; where nothing keys it, whatever the parameter's binder decides.
||| So the value an instance holds for a parameter its key names is the
||| form the key writes there.
public export
data AtKey : Maybe (KeyedAs, StaticReading) -> PKind -> Type where
  TypeAtKey : {0 r : StaticReading} -> AtKey (Just (AsType, r)) (TypeParam r.form)
  DictionaryAtKey : {0 r : StaticReading} -> {0 holes : Maybe Holes} ->
                    AtKey (Just (AsDictionary holes, r)) (DictParam r.form holes)
  FormAtKey : {0 r : StaticReading} -> AtKey (Just (AsForm, r)) (FormParam r.form)
  ShapeAtKey : {0 r : StaticReading} -> {0 q : Uses} -> {0 t : Ty} -> {0 idrisType : ClosedTerm} ->
               AtKey (Just (AsShape q, r)) (ValueParam (MkBinder q t) (Just r.form) idrisType)
  NoKey : {0 k : PKind} -> AtKey Nothing k

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

||| The constructor of a member of a choice: one with no field, for an
||| implementation that closes over no runtime value, or one whose one
||| field holds the values it captures (`Holes`), as a closure's does.
public export
data MemberCon = Bare (Con 0) | Capturing Holes (Con 1)

||| An implementation the program fixes as a value of its interface type,
||| one constructor of that type's choice (`Choices`): its form, the
||| runtime values it closes over replaced by markers (`Closed.holeMarker`),
||| which keys the instance of every callee a dispatch calls at it, and its
||| constructor.
public export
record ChoiceMember where
  constructor MkChoiceMember
  form : ClosedTerm
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
||| runtime values: its family, the type, and its members in the order the
||| translation found them, each the next constructor. It only grows, and
||| a dispatch on it is built once the translation has found every member
||| (`Choices.dispatchers`).
public export
record Choice where
  constructor MkChoice
  family : FamilyId
  type : ClosedTerm
  members : SnocList ChoiceMember

||| The parameter a dispatch finds its choice in, as its kind holds it: the
||| parameter takes the choice, of this binder and type (`Given`), and the
||| kinds hold `rest` more choices after it, each arm a call of the callee
||| with one fewer (`Choices.calleeAt`); or the parameter takes an
||| implementation the program fixes, of this form, and holds the values
||| it closes over, the one at place `j` among them a choice the running
||| program made (`Held j`): a field of the implementation, whose every
||| member is an instance of the callee with that field fixed
||| (`Choices.heldDispatch`).
public export
data Chosen = Given (rest : Nat) Binder ChoiceType | Held (j : Nat) ClosedTerm Holes

||| The kind of the parameter a dispatch finds its choice in.
export
chosenKind : Chosen -> PKind
chosenKind (Given _ b t) = ChoiceParam b t
chosenKind (Held _ form hs) = DictParam form (Just hs)

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
||| on), its kinds as the call classified them, one per parameter the
||| callee applies, split at the parameter its choice is found in
||| (`Chosen`), so that the parameter and its kind are one, the choice's
||| family, and where and in whose definition it was made. None of it
||| changes once made; its arms, which grow with its choice, are its own
||| table's (`Facts.dispatchArms`).
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
||| instance of it, decided once per position (`Types.tyConFacts`):
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

||| What the translation reads of a type constructor's definition: its
||| parameters, the role of the argument at each position (`Role`), the
||| first first, and what its values are as numbers go.
public export
record TyConFacts where
  constructor MkTyConFacts
  params : List Nat
  roles : List Role
  natness : Natness

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

||| A definition of the frozen context as the translation reads it, each
||| part read once (`Boundary`): its place, the definition, its type as the
||| context's accessor reads it, its body when it matches (`Matched`),
||| whether Idris proved it ends (`Ends`), what the registry makes of it
||| (`Registered`), the hook that lowers its calls, read against its type
||| (`Resolve.Lowered`), where its values are members of a choice
||| (`MemberPlaces`), and what it takes at each binder of its type in
||| normal form (`Closed.argumentAt`), read off the normal form the member
||| table is read off.
public export
record Defined where
  constructor MkDefined
  placement : Placement
  def : GlobalDef
  type : ClosedTerm
  matched : Maybe Matched
  ends : Ends
  registered : Registered
  loweredBy : Maybe (Lowered LibraryFunction)
  places : MemberPlaces
  taken : List ArgumentAt

||| Where a definition's values are members of a choice (`MemberPlaces`),
||| read once at the boundary: the lookup the translation and the growth
||| check read it by, with `givenAt` and `givesAfter`.
export
memberPlaces : Defined -> MemberPlaces
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

||| What the translation reads of the program: the context frozen once the
||| program and everything it imports are loaded and every termination
||| verdict it reaches is in it, which every normaliser reads; every
||| definition the translation can meet from the program's entry, each read
||| once and kept by its entry in the context (`Boundary.readProgram`); the
||| type a member at a use is applied as by, with its binders' names,
||| interned once (`Application`); the type constructors of the
||| interfaces the program loaded, by full name, Idris's own table of them,
||| since nothing the translation does declares one (an implementation is
||| a value of one of these types, or of a pair of or a function to such
||| values, `Boundary.implementationHolding`); and what follows from the
||| definitions alone, found once from them: each type constructor's facts
||| (`TypeConstructors`), the component of the call graph each definition
||| whose loops Idris proved to end is proved in (`Recursion`; one with no
||| proof may diverge, `terminationOf`), and what each case, with and
||| nested block is called, `<parent>.case<k>` (`Boundary`), each by its
||| address. Nothing the translation does changes it.
public export
record Read where
  constructor MkRead
  frozen : Frozen
  definitions : SortedMap Int Defined
  application : Application
  interfaces : SortedSet Name
  tyCons : SortedMap Address TyConFacts
  loops : SortedMap Address ComponentId
  blockNames : SortedMap Address String

||| What Idris proved of a definition's loops: that they end, in the
||| component the proof is of, or, with no proof, that they may diverge, by
||| the definition's own name. Total: a definition with no proof is one
||| that may diverge, whatever left it unproved.
export
terminationOf : Read -> Defined -> Termination
terminationOf r d = case lookup (addressOf d.placement) r.loops of
  Just component => Terminates component
  Nothing => MayDiverge (shown (show (fullname d.def)) ::: [])

||| What was read of a name: the definition at the entry the frozen context
||| resolves it to; no definition, for a name the context defines as
||| nothing (a probe's, a binder's); or an entry the reading missed, which
||| only the compiler's error leaves, since every definition the
||| translation can meet is read.
public export
data ReadOf = ReadAs Defined | NoDefinition | Missed

||| What was read of a name (`ReadOf`).
export
readOf : Read -> Name -> ReadOf
readOf r n = case definitionIn r.frozen n of
  NotDefined _ => NoDefinition
  DefinedAs i _ _ _ => maybe Missed ReadAs (lookup i r.definitions)

||| The definition a name names, as it was read (`readOf`); nothing for a
||| name the context defines as nothing, a probe's among them. Every
||| definition a phase can meet was read from what `main` reaches, so one
||| the context defines and the reading missed is the compiler's error.
export
definedIn : Read -> Name -> Core (Maybe Defined)
definedIn r n = case readOf r n of
  ReadAs d => pure (Just d)
  NoDefinition => pure Nothing
  Missed => throw (InternalError ("the definitions read from what main reaches miss " ++ show (fullNameIn r.frozen n)))

%prefix_record_projections on

||| What the translation derives of the program, each fact by its
||| content: the family instances, each by its link, its identity numbered
||| once (the next number `nextFamily`), each by its identity, and in the
||| order registered; their constructors; the function instances
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
||| for every other.
|||
||| The instance table is these facts as the worklist has merged them
||| (`merged`); a step's derivation is these facts as the step made or
||| changed them, which supersede the table's by key.
public export
record Facts where
  constructor MkFacts
  familyIds : SortedMap (Link Form) FamilyId
  nextFamily : Nat
  families : SortedMap FamilyId Family
  familyOrder : SnocList FamilyId
  cons : SortedMap ConId ConLayout
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

||| No fact.
export
noFacts : Facts
noFacts = MkFacts empty 0 empty [<] empty empty [<] empty empty empty empty empty empty empty empty

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
  MkFacts (over f.familyIds t.familyIds) f.nextFamily (over f.families t.families) (t.familyOrder ++ f.familyOrder)
          (over f.cons t.cons) (over f.instances t.instances)
          (t.fnOrder ++ f.fnOrder) (over f.fns t.fns) (over f.named t.named) (over f.keyLinks t.keyLinks)
          (over f.choiceIds t.choiceIds) (over f.choices t.choices) (over f.dispatchesOn t.dispatchesOn)
          (over f.dispatchArms t.dispatchArms) (over f.readings t.readings)
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

export
initState : Read -> Modules -> NonEmptyFC -> TS
initState r loaded fc = MkTS
  { reads = r
  , table = noFacts, derived = startingFrom noFacts
  , moduleFC = fc, rejected = [<], refused = empty
  , spelled = empty, modules = loaded, bounds = empty
  , sizes = MkBounds (const []) 0 0 0 }

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

||| A family registered, by its identity, as the step being run reads it
||| (`lookupFact`).
export
familyOf : FamilyId -> TS -> Maybe Family
familyOf = lookupFact (.families)

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
