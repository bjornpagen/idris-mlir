-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the translation reads of the program, read once, at the boundary:
||| when the program and everything it imports are loaded and its entry is
||| found, every definition the translation can meet from the entry is read
||| through the context's accessors, each part of it once, and kept by its
||| entry (`Defined`). Idris's termination check writes its verdicts into
||| the context, so every function among them whose verdict the checked
||| module leaves unchecked is checked as it is read, and the context is
||| frozen only then: nothing writes it after, and every normaliser reads
||| it as frozen. Where a definition's values are members of a choice, and
||| what it takes at each binder, are read off its type in normal form, once
||| the context is frozen; and what follows from the definitions alone is
||| found from them once: each type constructor's facts
||| (`TypeConstructors`), each definition's loops (`Recursion`), and what
||| each block is called (`blockNamesOf`). The translation reads these and
||| nothing else of the context (`Errors.defined`).
|||
||| A definition is met through a name some term the translation holds
||| refers to: a definition's type or body, or a normal form of terms made
||| from those, whose names are again the names of the bodies unfolded. So
||| the definitions it can meet are those the entry refers to, and those
||| they refer to in turn, through their types, their case trees, their
||| clauses' patterns and their one clause, the unknowns in them, a type
||| constructor's constructors, the definition a block belongs to, the calls
||| Idris's size-change graphs keep, and the library functions the
||| registry's hooks of a definition name; and the pair Idris's `%pair`
||| names, which the translation builds itself. Once the context is
||| frozen, each unknown met is read again by the entry its term gives it,
||| as the solution the checker gave it or a hole (`Solution`), and the
||| pair as its three definitions (`PairRead`), so no phase after looks
||| either up by name.
module IdrisMLIR.Frontend.Translate.Boundary

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Env
import Core.Options
import Core.TT
import Idris.Host

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Definitions
import IdrisMLIR.Frontend.Translate.Recursion
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.TypeConstructors
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Ids
import IdrisMLIR.Registry
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Types

import Control.WellFounded
import Data.DPair
import Data.List
import Data.List1
import Data.Maybe
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Decidable.Equality

%default total

-- A scope here is always a term's, the checker's: where a rule is decided
-- is no question this module asks.
%hide IdrisMLIR.Spec.Core.Rules.Scope

------------------------------------------------------------------------------
-- What a definition refers to
------------------------------------------------------------------------------

||| A name a definition refers to, as a walk over what the program reaches
||| follows it: a definition, or a metavariable, by the entry its term
||| gives it, which is the name Host's `Solve` unfolds, with the name the
||| term shows it by, for a message. A walk that names blocks reads a
||| metavariable's solution under the definition that refers to it
||| (`nameUnder`), and the reading reads each one's solution by that entry
||| once the context is frozen (`solutionAt`).
public export
data Referent = ARef Name | AMeta Name Int

||| The name a reference is to: a metavariable's, its entry.
export
referentName : Referent -> Name
referentName (ARef n) = n
referentName (AMeta _ i) = Resolved i

mutual
  ||| The references of a term, left to right: a function before its
  ||| argument, a binder's type and value before its scope.
  termRefs : SnocList Referent -> Term vs -> SnocList Referent
  termRefs acc (Ref _ _ n) = acc :< ARef n
  termRefs acc (Meta _ n i args) = termsRefs (acc :< AMeta n i) args
  termRefs acc (Bind _ _ b sc) = termRefs (binderRefs acc b) sc
  termRefs acc (App _ f a) = termRefs (termRefs acc f) a
  termRefs acc (As _ _ a p) = termRefs (termRefs acc a) p
  termRefs acc (TDelayed _ _ t) = termRefs acc t
  termRefs acc (TDelay _ _ t a) = termRefs (termRefs acc t) a
  termRefs acc (TForce _ _ t) = termRefs acc t
  termRefs acc (Erased _ (Dotted t)) = termRefs acc t
  termRefs acc _ = acc

  termsRefs : SnocList Referent -> List (Term vs) -> SnocList Referent
  termsRefs acc [] = acc
  termsRefs acc (t :: ts) = termsRefs (termRefs acc t) ts

  piRefs : SnocList Referent -> PiInfo (Term vs) -> SnocList Referent
  piRefs acc (DefImplicit t) = termRefs acc t
  piRefs acc _ = acc

  binderRefs : SnocList Referent -> Binder (Term vs) -> SnocList Referent
  binderRefs acc (Lam _ _ p ty) = termRefs (piRefs acc p) ty
  binderRefs acc (Let _ _ v ty) = termRefs (termRefs acc ty) v
  binderRefs acc (Pi _ _ p ty) = termRefs (piRefs acc p) ty
  binderRefs acc (PVar _ _ p ty) = termRefs (piRefs acc p) ty
  binderRefs acc (PLet _ _ v ty) = termRefs (termRefs acc ty) v
  binderRefs acc (PVTy _ _ ty) = termRefs acc ty

mutual
  ||| The references of a case tree: each case's scrutinee type and each
  ||| alternative's constructor, and each leaf's term, in order.
  treeRefs : SnocList Referent -> CaseTree vs -> SnocList Referent
  treeRefs acc (Case _ _ ty alts) = altsRefs (termRefs acc ty) alts
  treeRefs acc (STerm _ t) = termRefs acc t
  treeRefs acc _ = acc

  altsRefs : SnocList Referent -> List (CaseAlt vs) -> SnocList Referent
  altsRefs acc [] = acc
  altsRefs acc (a :: as) = altsRefs (altRefs acc a) as

  altRefs : SnocList Referent -> CaseAlt vs -> SnocList Referent
  altRefs acc (ConCase n _ _ sc) = treeRefs (acc :< ARef n) sc
  altRefs acc (DelayCase _ _ sc) = treeRefs acc sc
  altRefs acc (ConstCase _ sc) = treeRefs acc sc
  altRefs acc (DefaultCase sc) = treeRefs acc sc

mutual
  ||| The references of a clause's pattern: its constructors and type
  ||| constructors, and the terms of what it cannot match.
  patRefs : SnocList Referent -> Pat -> SnocList Referent
  patRefs acc (PAs _ _ p) = patRefs acc p
  patRefs acc (PCon _ n _ _ ps) = patsRefs (acc :< ARef n) ps
  patRefs acc (PTyCon _ n _ ps) = patsRefs (acc :< ARef n) ps
  patRefs acc (PConst _ _) = acc
  patRefs acc (PArrow _ _ s t) = patRefs (patRefs acc s) t
  patRefs acc (PDelay _ _ s t) = patRefs (patRefs acc s) t
  patRefs acc (PLoc _ _) = acc
  patRefs acc (PUnmatchable _ t) = termRefs acc t

  patsRefs : SnocList Referent -> List Pat -> SnocList Referent
  patsRefs acc [] = acc
  patsRefs acc (p :: ps) = patsRefs (patRefs acc p) ps

||| What a definition's body and type refer to, in the order a walk meets
||| them: its case tree, its clauses' patterns and its one clause, the parts
||| of its body the translation reads, then its type, after the body so that
||| a walk meets first what the body refers to. A block no body calls may
||| still be named by a type (a local datatype of a block, named in the
||| types that mention it).
export
references : Maybe Matched -> ClosedTerm -> List Referent
references m ty = termRefs (maybe [<] body m) ty <>> []
  where
    body : Matched -> SnocList Referent
    body mt =
      let afterPats = patsRefs (treeRefs [<] mt.tree) (concat mt.pats) in
      case mt.onlyClause of
        Just (_ ** rhs) => termRefs afterPats rhs
        Nothing => afterPats

||| The definition a case, with or nested block belongs to: a case or with
||| block's parent is its full name, which Idris keeps; a nested function's
||| is its place in the context (`Closed.rootOf`, which climbs them).
parentOf : Name -> Maybe Name
parentOf (NS _ n) = parentOf n
parentOf (CaseBlock outer _) = Just outer
parentOf (WithBlock outer _) = Just outer
parentOf (Nested (outer, _) _) = Just (Resolved outer)
parentOf _ = Nothing

||| The names of the library functions the registry's hooks of a
||| definition name: its name's, and a `%foreign` definition's specs'.
librariesOf : Registered -> List Name
librariesOf (ByName hs) = map (.name) (libraries hs)
librariesOf (BySpecs hs called) = map (.name) (libraries hs ++ either (const []) libraries called)

------------------------------------------------------------------------------
-- Reading a definition
------------------------------------------------------------------------------

%prefix_record_projections off

||| A definition as the reading has it before the context is frozen: every
||| part `Defined` keeps but where its values are members of a choice, which
||| is read off its type in normal form once the context is frozen.
record Unfrozen where
  constructor MkUnfrozen
  placement : Placement
  def : GlobalDef
  type : ClosedTerm
  matched : Maybe Matched
  ends : Ends
  registered : Registered

%prefix_record_projections on

||| Every name the translation may meet through a definition it meets.
referred : Unfrozen -> List Referent
referred d =
  references d.matched d.type
  ++ map ARef (constructors (definition d.def)
               ++ maybe [] (:: []) (parentOf (fullname d.def))
               ++ map (.fnCall) (sizeChange d.def)
               ++ librariesOf d.registered)
  where
    constructors : Def -> List Name
    constructors (TCon _ _ _ _ _ cons _) = fromMaybe [] cons
    constructors _ = []

||| How many clauses a body has, which a stored body says without decoding
||| one.
clauseCount : Body args -> Nat
clauseCount (LiveBody _ _ cs) = length cs
clauseCount (StoredBody _ _ cs) = length cs

||| The right-hand side of a body's clause, in its scope, when it has
||| exactly one; of a body of more, no clause is decoded.
onlyClauseOf : Body args -> Core (Maybe (vs : Scope ** Term vs))
onlyClauseOf body = case clauseCount body of
  1 => do
    [(vs ** (_, _, rhs))] <- clausesOf body
      | _ => pure Nothing
    pure (Just (vs ** rhs))
  _ => pure Nothing

||| Whether Idris proved that the definition at entry `i` ends (`Ends`),
||| with the definition as that leaves it: the verdict its checked module
||| holds, or, for a function that leaves it unchecked, the verdict of
||| Idris's termination check, run here, once, since the check writes its
||| verdicts into the context and the context is frozen only after every
||| definition is read. The definition read before the check is given the
||| verdict the check wrote. A constructor ends: applying one runs nothing,
||| and its own verdict is its type's positivity, which no reduction asks.
verdictOf : {auto c : Ref Ctxt Defs} -> Int -> GlobalDef -> Core (GlobalDef, Ends)
verdictOf i def = case definition def of
  DCon {} => pure (def, ProvedToEnd)
  TCon {} => pure (def, ProvedToEnd)
  _ => case isTerminating (totality def) of
    Unchecked => do
      verdict <- host.checkTerminating EmptyFC (Resolved i)
      pure ({ totality->isTerminating := verdict } def, endsBy verdict)
    verdict => pure (def, endsBy verdict)
  where
    endsBy : Terminating -> Ends
    endsBy IsTerminating = ProvedToEnd
    endsBy _ = NotProvedToEnd

||| What the registry makes of a definition (`Registered`): the hooks of
||| its name, and a foreign definition's by its specs, each library
||| function they name interned once, where it enters the compiler.
registeredOf : {auto c : Ref Ctxt Defs} -> GlobalDef -> Core Registered
registeredOf def = do
  own <- interned (hooksOf (fullname def))
  case definition def of
    ForeignDef _ specs => BySpecs own <$> Interfaces.traverse @{%search} @{Applicative.CORE} interned
                                                            (foreignHooks (fullname def) specs)
    _ => pure (ByName own)
  where
    interned : Hooks QName -> Core (Hooks LibraryFunction)
    interned = readLibraries @{Applicative.CORE} (\q => MkLibraryFunction q <$> toName q)

||| A definition as the translation reads it, each part through the
||| context's accessors once, before the context is frozen: its type; of
||| one that matches, its case tree, its clauses' patterns and its one
||| clause; whether it ends (`verdictOf`); and what the registry makes of it.
readDefinition : {auto c : Ref Ctxt Defs} -> Int -> Placement -> GlobalDef -> Core Unfrozen
readDefinition i p def0 = do
  (def, ends) <- verdictOf i def0
  ty <- (.fst) <$> readTypeOf def
  m <- case definition def of
         PMDef _ args body => Just <$> matched args body
         _ => pure Nothing
  pure (MkUnfrozen p def ty m ends !(registeredOf def))
  where
    matched : (args : Scope) -> Body args -> Core Matched
    matched args body = do
      tree <- (.fst) <$> readTreeOf body
      pats <- clausePatsOf body
      only <- onlyClauseOf body
      pure (MkMatched args tree pats only)

------------------------------------------------------------------------------
-- What a type says of a value of it held at run time
------------------------------------------------------------------------------

||| A member where either says so; none where both say none; else what
||| the instance decides.
eitherHolds : Holding -> Holding -> Holding
eitherHolds AMember _ = AMember
eitherHolds _ AMember = AMember
eitherHolds NoMember NoMember = NoMember
eitherHolds _ _ = ByInstance

||| A member where both say so; none where either says none; else what the
||| instance decides.
bothHold : Holding -> Holding -> Holding
bothHold NoMember _ = NoMember
bothHold _ NoMember = NoMember
bothHold AMember AMember = AMember
bothHold _ _ = ByInstance

||| The head of a type: a type constructor, which the type applies whatever
||| an instance substitutes; what the instance decides, a variable, an
||| unknown, a definition its arguments leave stuck, or a marker of the
||| growth walk's, which is the writer's variable; or anything else, which
||| no value of a choice has (a constant, a universe, a constructor, a
||| runtime value a probe stands for).
data Headed = ByTypeConstructor Name | Undecided | Neither

headed : Term vs -> Headed
headed ty = case getFn ty of
  Ref _ (TyCon _) n => ByTypeConstructor n
  Ref _ Func _ => Undecided
  Ref _ Bound n => maybe Neither probed (probeOf n)
  Local {} => Undecided
  Meta {} => Undecided
  _ => Neither
  where
    -- A bound name no binder binds is a probe. The growth walk's markers
    -- (the writer's parameter, a part of one a site matched, a field of
    -- its dictionary, an argument of a family's value) stand for what each
    -- instance puts in, so only an instance decides a type one heads, as
    -- the member table leaves a type its variable heads to the instance.
    -- Any other probe stands for a runtime value or a binder of a
    -- constructor's type, which no instance puts in.
    probed : Probe -> Headed
    probed (ProbePart _ _) = Undecided
    probed (ProbePattern _) = Undecided
    probed (ProbeFieldPath _ _) = Undecided
    probed (ProbeFormal _ _) = Undecided
    probed _ = Neither

||| Is a value of a type an implementation, whatever binds it? Idris passes
||| a function's constraints to its `where` functions and its case and with
||| blocks as explicit arguments, so the binder does not say. An
||| implementation is a value of an interface, which is what Idris declared
||| as one, in its table of interfaces (`Read.interfaces`); of a pair of
||| implementations, which is how Idris gives a tuple of constraints
||| (`(Show a, Show b) => Show (a, b)`), each one found by search: its pair
||| type (`%pair`) is the one Idris's search takes apart; or of a function
||| to an implementation, a constraint over the values of its arguments
||| (`{y : a} -> Show (p y)`, which `Show (DPair a p)` takes). A type whose
||| values Idris finds by search is not an interface for that: an
||| auto-implicit argument of any other type (`{auto c : Ref Ctxt Defs}`, a
||| proof Idris searches for) is an ordinary argument, and any data type may
||| ask for the unique search an interface's record has (`[uniqueSearch]`).
export
implementationHolding : Frozen -> (interfaces : SortedSet Name) -> Term vs -> Holding
implementationHolding fz ifs (Bind _ _ (Pi {}) sc) = implementationHolding fz ifs sc
implementationHolding fz ifs ty = case headed ty of
  Undecided => ByInstance
  Neither => NoMember
  ByTypeConstructor n =>
    let full = fullNameIn fz n in
    if contains full ifs then AMember else case ty of
      App _ (App _ (Ref _ _ _) a) b =>
        if paired full then bothHold (implementationHolding fz ifs a) (implementationHolding fz ifs b) else NoMember
      _ => NoMember
  where
    paired : Name -> Bool
    paired full = case pairnames (options (defsOf fz)) of
      Just ns => full == fullNameIn fz (pairType ns)
      Nothing => False

||| Does a binder of quantity `rig` and type `a` take a type or an
||| implementation, as a polymorphic function's first does?
takesStatic : Frozen -> SortedSet Name -> RigCount -> Term vs -> Holding
takesStatic fz ifs rig a = eitherHolds typeLike (case use rig of
                                                   Erased => NoMember
                                                   Used _ => implementationHolding fz ifs a)
  where
    typeLike : Holding
    typeLike = if isTypeLike a then AMember else case headed a of
      Undecided => ByInstance
      _ => NoMember

||| Is a type the type of a polymorphic function: one that takes a type, or
||| an implementation, before what it gives (`{0 a : Type} -> a -> List a`,
||| `Show a => a -> String` under a binder of `a`)? Such a value passed as
||| an argument is a compile-time value, as an implementation is: which
||| function it is keys the instance of what it is given to, each use
||| applies it at the use's own types, and the runtime values it closes
||| over are what its parameter holds. One held at run time (in a field, as
||| a result, chosen by a runtime value) is a value of its type's choice
||| (`Types.choiceFamily`), which function it is, so no polymorphic value
||| exists at run time either. A function on values whose result is an
||| implementation (`{y : Nat} -> Show (Tag y)`) takes neither: its type is
||| an implementation's already (`implementationHolding`).
export
polymorphicHolding : Frozen -> (interfaces : SortedSet Name) -> Term vs -> Holding
polymorphicHolding fz ifs (Bind _ _ (Pi _ rig _ a) sc) = eitherHolds (takesStatic fz ifs rig a) (polymorphicHolding fz ifs sc)
polymorphicHolding fz ifs ty = case headed ty of
  Undecided => ByInstance
  _ => NoMember

||| Is a value of this type (normalised), held at run time, a value of the
||| type's choice (`Types.choiceFamily`): a polymorphic function, or an
||| implementation? A function on values whose result is an implementation
||| (`{y : Nat} -> Show (Tag y)`) is a closure that gives a choice, no
||| choice itself.
export
choiceHolding : Frozen -> (interfaces : SortedSet Name) -> Term vs -> Holding
choiceHolding fz ifs ty@(Bind _ _ (Pi {}) _) = polymorphicHolding fz ifs ty
choiceHolding fz ifs ty = implementationHolding fz ifs ty

||| Where a definition's values are members of a choice, read off its type
||| in normal form (`MemberPlaces`): a value given at a binder is one by
||| the binder's type, under the delay where the binder is delayed (a
||| delayed polymorphic function, a branch of `if`); the definition applied
||| to as many arguments as binders before a type gives one by that type.
placesOf : Frozen -> SortedSet Name -> ClosedTerm -> MemberPlaces
placesOf fz ifs normal = fst (go normal)
  where
    taken : Term vs -> Holding
    taken (TDelayed _ _ inner) = choiceHolding fz ifs inner
    taken a = choiceHolding fz ifs a

    -- The places of a type, with what the type is as a polymorphic
    -- function's, which the type one binder out is when it is one.
    go : Term vs -> (MemberPlaces, Holding)
    go (Bind _ _ (Pi _ rig _ a) sc) =
      let (rest, after) = go sc
          here = eitherHolds (takesStatic fz ifs rig a) after in
      (MkMemberPlaces (taken a :: rest.given) (here ::: forget rest.gives), here)
    go t = (MkMemberPlaces [] (implementationHolding fz ifs t ::: []), polymorphicHolding fz ifs t)

------------------------------------------------------------------------------
-- What each block is called
------------------------------------------------------------------------------

||| Idris's full name, except that a `DN`, which is how Idris names an
||| implementation's method, is its inner name: the display name
||| (`Prelude.Types.map`) is every implementation's in the module, the inner
||| one (`Prelude.Types.map_Functor_Maybe`) is this one's.
export
plainName : Name -> Name
plainName (NS ns (DN _ m)) = NS ns m
plainName (DN _ m) = m
plainName m = m

||| A name as a key prints it (`plainName`).
export
plainOrigin : Name -> String
plainOrigin n = show (plainName n)

||| The kind of block Idris made of a definition: a case block and a with
||| block, which Idris numbers with one counter for the whole build, and a
||| nested (`where`) function by its own name, as a key prints it
||| (`plainName`), which Idris numbers with its parent's place in the
||| context. None of those numbers says where the block is, and a name says
||| it only up to the blocks of one kind under one parent: each clause's
||| `where` may define the same name again.
export
data BlockKind = OfCase | OfWith | OfNested Name

Eq BlockKind where
  OfCase == OfCase = True
  OfWith == OfWith = True
  OfNested a == OfNested b = a == b
  _ == _ = False

Ord BlockKind where
  compare OfCase OfCase = EQ
  compare OfCase _ = LT
  compare OfWith OfCase = GT
  compare OfWith OfWith = EQ
  compare OfWith (OfNested _) = LT
  compare (OfNested a) (OfNested b) = compare a b
  compare (OfNested _) _ = GT

||| A block's kind as its printed name spells it under its parent.
kindText : BlockKind -> String
kindText OfCase = "case"
kindText OfWith = "with"
kindText (OfNested inner) = show inner

||| The kind of block a definition is, by its name; nothing for a
||| definition that is no block.
export
blockOf : Name -> Maybe BlockKind
blockOf (NS _ n) = blockOf n
blockOf (CaseBlock _ _) = Just OfCase
blockOf (WithBlock _ _) = Just OfWith
blockOf (Nested _ inner) = Just (OfNested (plainName inner))
blockOf _ = Nothing

||| What a definition read refers to, in the order the walk meets it
||| (`references`): its body as the translation reads it, then its type.
||| For a solved metavariable these are its solution's.
referentsOf : DefinitionRead () -> List Referent
referentsOf d = references d.matched d.type

||| Where a walk that names blocks has got to: what each definition it has
||| walked is called, by address, a block by its place under the definition
||| that refers to it first and any other by its own name; how many blocks
||| of each kind are named so far under the definition being walked (none
||| of a kind the map does not hold); and what the walk has entered, no
||| more than where it was.
record Reached (w : Walked) where
  constructor MkReached
  names : SortedMap Address String
  counters : SortedMap BlockKind Nat
  after : Walked
  0 noMore : NoMore after w

mutual
  ||| Names the blocks a definition refers to, depth first: each block not
  ||| yet named gets the next number of its kind under the definition that
  ||| refers to it first (`.case0`, `.with0`, `.go0`, `.go1`), and its own
  ||| references are walked at once under its new name. The numbers count
  ||| from 0 in each parent, so a block's name changes only with its
  ||| parent's definition, never with how many blocks the rest of the build
  ||| made. An ordinary reference is walked too: a block is not always
  ||| referred to by the definition Idris named it for (a case block of an
  ||| interface's default method is referred to by the implementation
  ||| methods the default was elaborated into, under the method's name), so
  ||| the walk follows references until it reaches a definition that does
  ||| refer to the block. A solved metavariable is walked through its
  ||| solution, under the same parent and counters. Each definition and each
  ||| metavariable is entered once (`Walk`), which is why the walk ends:
  ||| `w0` is where this level of it began, and every definition it enters
  ||| leaves fewer than `w0` to enter.
  nameUnder : Reading () -> String -> SortedMap Address String -> SortedMap BlockKind Nat ->
              (w0 : Walked) -> (0 _ : SizeAccessible w0) ->
              (w : Walked) -> (0 _ : NoMore w w0) -> List Referent -> Core (Reached w)
  nameUnder r origin names ks w0 acc w p [] = pure (MkReached names ks w (noMore w))
  nameUnder r origin names ks w0 acc@(Access rec) w p (AMeta _ i :: rest) = do
    Just d <- definedIn r (Resolved i)
      | Nothing => nameUnder r origin names ks w0 acc w p rest
    case enter d.placement w of
      Nothing => nameUnder r origin names ks w0 acc w p rest
      Just (Element w1 q) => do
        MkReached names' ks' w2 q2 <- nameUnder r origin names ks w1 (rec w1 (fewerThen q p)) w1 (noMore w1)
                                                (referentsOf d)
        MkReached names'' ks'' w3 q3 <- nameUnder r origin names' ks' w0 acc w2 (thenNoMore q2 (thenNoMore (fewer q) p)) rest
        pure (MkReached names'' ks'' w3 (thenNoMore q3 (thenNoMore q2 (fewer q))))
  nameUnder r origin names ks w0 acc@(Access rec) w p (ARef ref :: rest) = do
    let full = fullNameIn r.frozen ref
    let Just kind = blockOf full
      | Nothing => do
          (names', Element w1 q1) <- blocksFrom r names full w0 acc w p
          MkReached names'' ks' w2 q2 <- nameUnder r origin names' ks w0 acc w1 (thenNoMore q1 p) rest
          pure (MkReached names'' ks' w2 (thenNoMore q2 q1))
    -- A name no definition has is no block to name.
    Just d <- definedIn r full
      | Nothing => nameUnder r origin names ks w0 acc w p rest
    let key = addressOf d.placement
    let Nothing = lookup key names
      | Just _ => nameUnder r origin names ks w0 acc w p rest
    let Just (Element w1 q) = enter d.placement w
      | Nothing => nameUnder r origin names ks w0 acc w p rest
    let k = fromMaybe 0 (lookup kind ks)
    let name = origin ++ "." ++ kindText kind ++ show k
    MkReached names' _ w2 q2 <- nameUnder r name (insert key name names) empty w1 (rec w1 (fewerThen q p)) w1 (noMore w1)
                                          (referentsOf d)
    MkReached names'' ks'' w3 q3 <- nameUnder r origin names' (insert kind (S k) ks) w0 acc w2
                                              (thenNoMore q2 (thenNoMore (fewer q) p)) rest
    pure (MkReached names'' ks'' w3 (thenNoMore q3 (thenNoMore q2 (fewer q))))

  ||| Names the blocks of a definition that is no block, once, by its full
  ||| name.
  blocksFrom : Reading () -> SortedMap Address String -> Name -> (w0 : Walked) -> (0 _ : SizeAccessible w0) ->
               (w : Walked) -> (0 _ : NoMore w w0) -> Core (SortedMap Address String, Subset Walked (\w' => NoMore w' w))
  blocksFrom r names full w0 acc@(Access rec) w p = do
    let Nothing = blockOf full
      | Just _ => pure (names, Element w (noMore w))
    -- Nor is a name no definition has a definition to walk.
    Just d <- definedIn r full
      | Nothing => pure (names, Element w (noMore w))
    let key = addressOf d.placement
    let Nothing = lookup key names
      | Just _ => pure (names, Element w (noMore w))
    let Just (Element w1 q) = enter d.placement w
      | Nothing => pure (names, Element w (noMore w))
    let origin = plainOrigin full
    MkReached names' _ w2 q2 <- nameUnder r origin (insert key origin names) empty w1 (rec w1 (fewerThen q p)) w1 (noMore w1)
                                          (referentsOf d)
    pure (names', Element w2 (thenNoMore q2 (fewer q)))

||| Names the blocks of a definition that is no block, once, on a walk of
||| its own.
nameBlocksOf : Reading () -> SortedMap Address String -> Name -> Core (SortedMap Address String)
nameBlocksOf r names n = fst <$> blocksFrom r names (fullNameIn r.frozen n) start (sizeAccessible start) start (noMore start)

||| What each case, with and nested block the translation can meet is
||| called (`nameUnder`), by its address: named first from the program's
||| entry, then from every definition read, since a block need not be
||| referred to from what the entry refers to (a default method's case
||| block is referred to by the implementation methods the default was
||| elaborated into, and a nested block's parent index is its place in the
||| context that elaborated it, which loading does not keep). Each name
||| depends on the definitions alone, and on the one order they are walked
||| in.
blockNamesOf : Reading () -> (entry : Name) -> Core (SortedMap Address String)
blockNamesOf r entry = do
  fromEntry <- nameBlocksOf r empty entry
  foldlC (\names, d => nameBlocksOf r names (fullname d.def)) fromEntry (values r.definitions)

------------------------------------------------------------------------------
-- Reading the program
------------------------------------------------------------------------------

%prefix_record_projections off

||| What the reading before the freeze met: every definition, by its entry
||| (`readFrom`), and every metavariable a term of one names, by the entry
||| the term gives it, with the name it shows it by, whose solution is read
||| by that entry once the context is frozen (`solutionsOf`).
record Met where
  constructor MkMet
  found : SortedMap Int Unfrozen
  metavariables : SortedMap Int Name

%prefix_record_projections on

||| Every definition met from the references, after those read so far,
||| each read once and kept by its entry, then what it refers to read in
||| turn. A definition is entered into a walk when it is read (`Walk`), and
||| every one read leaves fewer to enter, which is why the reading ends; a
||| name the context defines as nothing, a probe's or a binder's, is no
||| definition to read. A type constructor's constructor the context holds
||| nothing for is passed over here too, and refused once the reading is
||| frozen, where the type's constructors are read (`constructorsRead`);
||| and so is a metavariable at no entry, which is noted, as every
||| metavariable is, wherever a term names it, read or not, and refused
||| once the context is frozen, where its solution is read (`solutionAt`).
readFrom : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 _ : SizeAccessible w) ->
           Met -> List Referent -> Core Met
readFrom w acc met [] = pure met
readFrom w acc@(Access rec) met (r :: rs) = do
  let met' = noted r
  defs <- get Ctxt
  Just (i, def) <- lookupCtxtExactI (referentName r) (gamma defs)
    | Nothing => readFrom w acc met' rs
  -- A negative entry is no place, which Idris's bare `Int` allows.
  let Just p = placementOf i
    | Nothing => readFrom w acc met' rs
  case enter p w of
    -- Read already.
    Nothing => readFrom w acc met' rs
    Just (Element w' less) => do
      d <- readDefinition i p def
      readFrom w' (rec w' less) ({ found $= insert i d } met') (referred d ++ rs)
  where
    noted : Referent -> Met
    noted (AMeta shownAs j) = { metavariables $= insert j shownAs } met
    noted (ARef _) = met

||| The type a member at a use is applied as by (`AtUse`, `Application`),
||| its binders' names interned once.
applicationOf : {auto c : Ref Ctxt Defs} -> Core Application
applicationOf = do
  t <- intern "t"
  f <- intern "f"
  u <- intern "u"
  pure (applicationOver (UN (Basic t)) (UN (Basic f)) (UN (Basic u)))

||| The number of binders a type shows as written.
shownBinders : TT vars -> Nat
shownBinders (Bind _ _ (Pi {}) sc) = S (shownBinders sc)
shownBinders _ = Z

||| What a definition read before the freeze has its calls lowered to,
||| read off its type in normal form (`Resolve.rowOf`): the hook of its
||| calls checked against the arity its calls are translated at, a case
||| tree's parameters or a bodiless declaration's; nothing where no hook
||| lowers its calls, or where its calls are no function's (a constructor's,
||| a type's, a builtin's), which no hook lowers. A `%foreign` definition
||| the registry gives no hooks is refused where it is called.
loweredOf : Unfrozen -> ClosedTerm -> Either String (Maybe (Lowered (const LibraryFunction)))
loweredOf u normal = case callHooks u.registered of
  Left _ => Right Nothing
  Right hs => case (u.matched, definition u.def) of
    (Just m, _) => rowOf (length m.args) (shownBinders u.type) normal hs
    (Nothing, ForeignDef arity _) => rowOf arity (shownBinders u.type) normal hs
    (Nothing, ExternDef arity) => rowOf arity (shownBinders u.type) normal hs
    _ => Right Nothing

||| A definition read before the freeze, by its name, as `found` holds it:
||| nothing for a name no read definition has.
foundAs : {auto c : Ref Ctxt Defs} -> SortedMap Int Unfrozen -> Name -> Core (Maybe Unfrozen)
foundAs found n = do
  defs <- get Ctxt
  pure ((\(i, _) => lookup i found) =<< !(lookupCtxtExactI n (gamma defs)))

||| A library function a row names (a natural's test, its operation on
||| integers), read against its definition: the parameters its calls are
||| translated at, its case tree's, and the values among them at run time,
||| as its type in normal form shows, `count` of them, as many as the row's
||| lowering gives it (`CheckedLibrary`); else why it is not the function
||| the row's hook calls.
checkedLibrary : {auto c : Ref Ctxt Defs} -> Frozen -> SortedMap Int Unfrozen -> (count : Nat) -> LibraryFunction ->
                 Core (Either String (CheckedLibrary count))
checkedLibrary fz found count lib = do
  Just u <- foundAs found lib.name
    | Nothing => pure (Left notDefinition)
  let Just m = u.matched
    | Nothing => pure (Left notDefinition)
  normal <- (.value) <$> host.normaliseTypes fz u.type
  pure (checkedAt (length m.args) normal)
  where
    notDefinition : String
    notDefinition = "the registry names the library function " ++ show lib.named ++ ", which is not a definition"

    checkedAt : (params : Nat) -> ClosedTerm -> Either String (CheckedLibrary count)
    checkedAt params normal = case operandsUpTo params normal of
      Nothing => Left ("the registry names the library function " ++ show lib.named ++
                       ", whose calls take arguments its type does not show")
      Just (k ** ops) => case decEq k count of
        Yes Refl => Right (MkCheckedLibrary lib ops)
        No _ => Left ("the registry names the library function " ++ show lib.named ++ ", of " ++ show k ++
                      " values at run time, where its hook gives it " ++ show count)

||| A row read against its definition's type (`rowOf`), each library
||| function it calls read against that function's definition
||| (`checkedLibrary`), so the row carries what each takes.
checkedRow : {auto c : Ref Ctxt Defs} -> Frozen -> SortedMap Int Unfrozen -> Lowered (const LibraryFunction) ->
             Core (Either String (Lowered CheckedLibrary))
checkedRow fz found (MkLowered {count} ops low) = map (MkLowered ops) <$> lowering {k = count} low
  where
    lowering : {k : Nat} -> Lowering (const LibraryFunction) k -> Core (Either String (Lowering CheckedLibrary k))
    lowering (NatPrimitive p) = pure (Right (NatPrimitive p))
    lowering (NatClamped p) = pure (Right (NatClamped p))
    lowering (NatTested p lib) = map (NatTested p) <$> checkedLibrary fz found 1 lib
    lowering {k} (NatOnIntegers lib) = map NatOnIntegers <$> checkedLibrary fz found k lib
    lowering (Builder p fits) = pure (Right (Builder p fits))
    lowering (ArrayOperation g) = pure (Right (ArrayOperation g))
    lowering IdentityOnLast = pure (Right IdentityOnLast)
    lowering (PureOperation p lits fits) = pure (Right (PureOperation p lits fits))
    lowering (IOOperation lits a) = pure (Right (IOOperation lits a))
    lowering (AccessOperation access rank) = pure (Right (AccessOperation access rank))
    lowering (PrimOperation lits p) = pure (Right (PrimOperation lits p))

mutual
  ||| The right-hand sides a case tree reaches, each in its own scope.
  leavesOf : {vs : Scope} -> CaseTree vs -> List (ws : Scope ** Term ws)
  leavesOf (Case _ _ _ alts) = altLeaves alts
  leavesOf {vs} (STerm _ tm) = [(vs ** tm)]
  leavesOf (Unmatched _) = []
  leavesOf Impossible = []

  altLeaves : {vs : Scope} -> List (CaseAlt vs) -> List (ws : Scope ** Term ws)
  altLeaves [] = []
  altLeaves (ConCase _ _ args sc :: rest) = leavesOf sc ++ altLeaves rest
  altLeaves (DelayCase _ _ sc :: rest) = leavesOf sc ++ altLeaves rest
  altLeaves (ConstCase _ sc :: rest) = leavesOf sc ++ altLeaves rest
  altLeaves (DefaultCase sc :: rest) = leavesOf sc ++ altLeaves rest

mutual
  ||| Every application in a term whose head is a definition given two
  ||| arguments or more: the head and its first two arguments, in the scope
  ||| the application is written in, the outermost first.
  headedApps : {vs : Scope} -> Term vs -> List (ws : Scope ** (Name, Term ws, Term ws))
  headedApps {vs} tm@(App _ f a) =
    (case getFnArgs tm of
       (Ref _ _ n, (x :: y :: _)) => [(vs ** (n, x, y))]
       _ => []) ++ spineArgs f ++ headedApps a
  headedApps (Bind _ _ (Let _ _ val _) sc) = headedApps val ++ headedApps sc
  headedApps (Bind _ _ _ sc) = headedApps sc
  headedApps (TDelay _ _ _ arg) = headedApps arg
  headedApps (TForce _ _ arg) = headedApps arg
  headedApps (As _ _ _ p) = headedApps p
  headedApps _ = []

  -- The arguments down an application's spine, whose head the application
  -- itself is recorded at.
  spineArgs : {vs : Scope} -> Term vs -> List (ws : Scope ** (Name, Term ws, Term ws))
  spineArgs (App _ f a) = spineArgs f ++ headedApps a
  spineArgs _ = []

||| Every variable of a scope a placeholder, as a term closed over the scope
||| reads a value it does not need.
placeholdersOf : (vs : Scope) -> ByVar vs ClosedTerm
placeholdersOf [] = []
placeholdersOf (_ :: vs) = Erased EmptyFC Placeholder :: placeholdersOf vs

||| A type in normal form that is an action on the world: the quantity it
||| takes the world at, and what it gives, its world a placeholder.
worldAction : ClosedTerm -> Maybe (Uses, ClosedTerm)
worldAction (Bind _ _ (Pi _ rig _ (PrimVal _ (PrT WorldType))) sc) = case use rig of
  Used q => Just (q, subst (Erased EmptyFC Placeholder) sc)
  Erased => Nothing
worldAction _ = Nothing

||| Is a definition `believe_me`: the `BelieveMe` primitive, or a
||| definition whose one right-hand side applies it, as the translation
||| reads a call of either inside an exit (`Terms.exitCast`)?
believeMeIn : {auto c : Ref Ctxt Defs} -> SortedMap Int Unfrozen -> Name -> Core Bool
believeMeIn found n = do
  Just u <- foundAs found n
    | Nothing => pure False
  if primitive u then pure True else case u.matched of
    Just m => case getFn <$> leafOf m of
      Just (Ref _ _ p) => maybe False primitive <$> foundAs found p
      _ => pure False
    Nothing => pure False
  where
    primitive : Unfrozen -> Bool
    primitive u = case definition u.def of
      Builtin BelieveMe => True
      _ => False

||| What Idris's types say of the `believe_me`s an exit gives its action any
||| result by (`Hook.Exits`): each takes an action on the world and gives
||| one, its type arguments read with the definition's variables as
||| placeholders (`ExitTypes`, read off the first); nothing for a
||| definition that is no exit, or an exit with no `believe_me`. An exit
||| whose `believe_me` takes or gives anything else is not the definition
||| the registry's hook names, and is refused here, once.
exitTypesOf : {auto c : Ref Ctxt Defs} -> Frozen -> SortedMap Int Unfrozen -> Unfrozen -> Core (Either String (Maybe ExitTypes))
exitTypesOf fz found u = case ((namedHooks u.registered).exits, u.matched) of
  (True, Just m) => do
    found' <- casts (concatMap appsIn (leavesOf m.tree))
    read found'
  _ => pure (Right Nothing)
  where
    appsIn : (ws : Scope ** Term ws) -> List (ws : Scope ** (Name, Term ws, Term ws))
    appsIn (ws ** tm) = headedApps tm

    -- The applications whose head is `believe_me`.
    casts : List (ws : Scope ** (Name, Term ws, Term ws)) -> Core (List (ws : Scope ** (Name, Term ws, Term ws)))
    casts [] = pure []
    casts (app@(_ ** (n, _, _)) :: rest) = do
      later <- casts rest
      pure (if !(believeMeIn found n) then app :: later else later)

    actionOf : (ws : Scope) -> Term ws -> Core (Maybe (Uses, ClosedTerm))
    actionOf ws t = worldAction . (.value) <$> host.normaliseTypes fz (closeOver EmptyFC (placeholdersOf ws) t)

    noAction : String
    noAction = "the registry names an exit whose believe_me does not give an action on the world any result"

    read : List (ws : Scope ** (Name, Term ws, Term ws)) -> Core (Either String (Maybe ExitTypes))
    read [] = pure (Right Nothing)
    read ((ws ** (_, a, b)) :: rest) = do
      Just (aw, ag) <- actionOf ws a
        | Nothing => pure (Left noAction)
      Just (vw, _) <- actionOf ws b
        | Nothing => pure (Left noAction)
      Right _ <- read rest
        | Left msg => pure (Left msg)
      pure (Right (Just (MkExitTypes aw ag vw)))

||| A type constructor's constructors (`Constructors`): none declared, for
||| a type declared without them; or each as it was read
||| (`ConstructorAt`), in the order its declaration lists them, none for
||| any other definition, which has no constructors to read. A name the
||| type lists that the frozen context defines as nothing, or as no
||| constructor, or a constructor whose tag is not its place in the list,
||| is the compiled module's error, refused here, once, at the type
||| constructor or else at `fallback`, as the translation refuses a missing
||| definition, so no reader after meets a type with a constructor it
||| cannot read, or one it reads at another tag than Idris gave it.
constructorsRead : NonEmptyFC -> Reading () -> DefinitionRead () -> Core (Either Refusal Constructors)
constructorsRead fallback r tc = case definition tc.def of
  TCon _ _ _ _ _ (Just cons) _ => map DeclaredAs <$> listed 0 cons
  TCon _ _ _ _ _ Nothing _ => pure (Right NoneDeclared)
  _ => pure (Right (DeclaredAs []))
  where
    refused : String -> Refusal
    refused what = MkRefusal (Refusal CompiledModule) (fromMaybe fallback (isNonEmptyFC (location tc.def)))
                             (show (fullname tc.def) ++ ": " ++ what)

    -- Idris tags a type's constructors in the order its declaration lists
    -- them, from 0, and every reader reads a constructor at its tag.
    listed : (place : Nat) -> List Name -> Core (Either Refusal (List ConstructorAt))
    listed place [] = pure (Right [])
    listed place (cn :: rest) = do
      ReadAs _ _ _ con <- readOf r cn
        | NoDefinition _ => pure (Left (refused ("missing definition " ++ show cn ++ ", which its type lists as a constructor")))
      let DCon tag arity _ = definition con.def
        | _ => pure (Left (refused (show (fullname con.def) ++ " is not a constructor")))
      let True = tag == cast place
        | False => pure (Left (refused (show (fullname con.def) ++ " has the tag " ++ show tag ++
                                        ", but its type lists it at " ++ show place)))
      Right later <- listed (S place) rest
        | Left refusal => pure (Left refusal)
      pure (Right (MkConstructorAt con place arity :: later))

||| The reading with every definition given its constructors
||| (`constructorsRead`), the entry and the pair's as every other; the
||| first refusal stops it.
constructed : NonEmptyFC -> Reading () -> Core (Either Refusal (Reading Constructors))
constructed fallback r = do
  Right entry <- given r.entry
    | Left refusal => pure (Left refusal)
  Right pair <- pairGiven r.pair
    | Left refusal => pure (Left refusal)
  Right ds <- each empty (SortedMap.toList r.definitions)
    | Left refusal => pure (Left refusal)
  pure (Right (MkReading r.frozen entry ds r.application r.interfaces r.solutions pair))
  where
    given : DefinitionRead () -> Core (Either Refusal (DefinitionRead Constructors))
    given d = map (\cons => withNature cons d) <$> constructorsRead fallback r d

    pairGiven : Maybe (PairRead ()) -> Core (Either Refusal (Maybe (PairRead Constructors)))
    pairGiven Nothing = pure (Right Nothing)
    pairGiven (Just pg) = do
      Right p <- given pg.pairDefined
        | Left refusal => pure (Left refusal)
      Right f <- given pg.firstDefined
        | Left refusal => pure (Left refusal)
      Right s <- given pg.secondDefined
        | Left refusal => pure (Left refusal)
      pure (Right (Just (MkPairRead pg.pairAddress p pg.firstAddress f pg.secondAddress s)))

    each : SortedMap Int (DefinitionRead Constructors) -> List (Int, DefinitionRead ()) ->
           Core (Either Refusal (SortedMap Int (DefinitionRead Constructors)))
    each done [] = pure (Right done)
    each done ((i, d) :: rest) = do
      Right d' <- given d
        | Left refusal => pure (Left refusal)
      each (insert i d' done) rest

||| The solution of the metavariable at entry `i` (`Solution`), read once
||| from the frozen context by that entry, which its term gives it and
||| Host's `Solve` unfolds: the definition there, of no arguments and one
||| leaf, at the entry's placement, or a hole. A metavariable at no entry,
||| or at one of any other definition, is the compiled module's error,
||| refused here at `fallback` by the name its term shows it by, as the
||| boundary refuses other checked input it cannot read; the checker writes
||| a solution in no other shape, so no program reaches it.
solutionAt : (fz : Frozen) -> NonEmptyFC -> (i : Int) -> (shownAs : Name) -> Core (Either Refusal (Solution fz i))
solutionAt fz fallback i shownAs = case definitionIn fz (Resolved i) of
  NotDefined _ => pure (Left (refused "a metavariable at no entry"))
  DefinedAs _ _ d defines => shaped d defines
  where
    refused : String -> Refusal
    refused what = MkRefusal (Refusal CompiledModule) fallback (show shownAs ++ ": " ++ what)

    shaped : (d : GlobalDef) -> (0 _ : Defines fz (Resolved i) d) -> Core (Either Refusal (Solution fz i))
    shaped d defines with (definition d) proof held
      shaped d defines | PMDef info [] body = do
        Element (STerm leaf tm) treeOf <- readTreeOf body
          | Element _ _ => pure (Left (refused "a metavariable whose solution matches"))
        pure (Right (SolvedAs tm (placementAt i (resolvedPlaced resolvedItself defines)) defines held treeOf Refl))
      shaped d defines | Hole locals flags = pure (Right (Unsolved defines held))
      shaped d defines | _ = pure (Left (refused "a metavariable whose definition is neither a solution nor a hole"))

||| The solution of every metavariable a term read names, by its entry
||| (`solutionAt`): the table every walk that meets a metavariable reads
||| (`State.solutionIn`). The first refusal stops it.
solutionsOf : (fz : Frozen) -> NonEmptyFC -> List (Int, Name) -> Core (Either Refusal (Solutions fz))
solutionsOf fz fallback = go noSolutions
  where
    go : Solutions fz -> List (Int, Name) -> Core (Either Refusal (Solutions fz))
    go done [] = pure (Right done)
    go done ((i, shownAs) :: rest) = do
      Right s <- solutionAt fz fallback i shownAs
        | Left refusal => pure (Left refusal)
      go (withSolution i s done) rest

||| The pair Idris's `%pair` names (`PairRead`), each of its three names
||| read as the reading has it (`readIn`), by its entry's address
||| (`definedAddress`); nothing for a program that declares no `%pair`. A
||| declared one that names what the frozen context defines as nothing is
||| the compiled module's error, refused here at `fallback`; the checker
||| takes the pragma only of names it resolves, so no program reaches it.
pairingIn : (fz : Frozen) -> SortedMap Int (DefinitionRead ()) -> NonEmptyFC -> Core (Either Refusal (Maybe (PairRead ())))
pairingIn fz ds fallback = case pairnames (options (defsOf fz)) of
  Nothing => pure (Right Nothing)
  Just ns => do
    Right (pa, pd) <- part (pairType ns)
      | Left refusal => pure (Left refusal)
    Right (fa, fd) <- part (fstName ns)
      | Left refusal => pure (Left refusal)
    Right (sa, sd) <- part (sndName ns)
      | Left refusal => pure (Left refusal)
    pure (Right (Just (MkPairRead pa pd fa fd sa sd)))
  where
    part : Name -> Core (Either Refusal (Address, DefinitionRead ()))
    part n = do
      ReadAs i resolved defines d <- readIn fz ds n
        | NoDefinition _ => pure (Left (MkRefusal (Refusal CompiledModule) fallback
                                                  (show n ++ ": named by %pair, and defined as nothing")))
      pure (Right (definedAddress i resolved defines, d))

||| What the translation reads of a program whose entry is the definition
||| named `entry`, and whose loaded interfaces are `interfaces`: every
||| definition it can meet from the entry and from the pair `%pair` names,
||| read from the loaded context, every verdict the reading writes in it
||| and every registry name the validation resolves interned before it is
||| frozen; then the context frozen, the registry's entries validated
||| against it, and each definition's values that are members of a choice,
||| its binders with what it takes at each and their types, and the hook
||| that lowers its calls read off its type in normal form; the entry, as
||| it was read, found once by its name; the solution of every
||| metavariable a term read names, by its entry, and the pair `%pair`
||| names, each read once; each type constructor's constructors read; and
||| what follows from the definitions alone found once: each type
||| constructor's facts, each definition's loops, and each block's name. A
||| registry entry or row the loaded definitions contradict, a type
||| constructor whose constructors the context does not hold, and a
||| metavariable or a `%pair` the context does not define as one, are
||| refused here, once, at their definition or else at `fallback`, and
||| nothing after reads the registry's rows but as this read them.
export
readProgram : {auto c : Ref Ctxt Defs} -> (interfaces : SortedSet Name) -> (entry : Name) ->
              (fallback : NonEmptyFC) -> Core (Either Refusal Read)
readProgram ifs entry fallback = do
  defs <- get Ctxt
  let pair = maybe [] (\ns => map ARef [pairType ns, fstName ns, sndName ns]) (pairnames (options defs))
  met <- readFrom start (sizeAccessible start) (MkMet empty empty) (ARef entry :: pair)
  -- The registry's entries the validation resolves, each definition's name
  -- interned while the context may still be written.
  sites <- registrySites
  -- The context changes no more: frozen here, every normaliser reads it as
  -- frozen.
  fz <- host.freezeContext
  Nothing <- validate fz sites fallback
    | Just refusal => pure (Left refusal)
  Right definitions <- frozenAll fz met.found empty (SortedMap.toList met.found)
    | Left refusal => pure (Left refusal)
  -- The entry was read first, from its name: the definition the frozen
  -- context gives that name, found once here and held by the reading, so
  -- no phase after looks it up again. The program found it by that name
  -- in the context before the reading, so a context that defines it as
  -- nothing is a program with no main, refused as one.
  ReadAs _ _ _ entryRead <- readIn fz definitions entry
    | NoDefinition _ => pure (Left (MkRefusal (Refusal ProgramShape) fallback (programEntry ++ ": the program defines no main")))
  -- Each metavariable met, and the pair, read once from the frozen
  -- context by their entries, so no phase after looks either up by name:
  -- the solutions with the evidence the evaluator's own step states, the
  -- pair with its definitions as the reading has them.
  Right solutions <- solutionsOf fz fallback (SortedMap.toList met.metavariables)
    | Left refusal => pure (Left refusal)
  Right pairing <- pairingIn fz definitions fallback
    | Left refusal => pure (Left refusal)
  application <- applicationOf
  -- What follows from the definitions alone is found from them, before
  -- any definition holds it: none of the three readings reads what the
  -- others find, and each definition is given all three at once. The type
  -- constructors' facts read their constructors, read first.
  let fromDefinitions = MkReading fz entryRead definitions application ifs solutions pairing
  Right withConstructors <- constructed fallback fromDefinitions
    | Left refusal => pure (Left refusal)
  proved <- loopsOf fromDefinitions
  blocks <- blockNamesOf fromDefinitions entry
  Right <$> readWhole proved blocks withConstructors
  where
    -- A definition read before the freeze, with what is read off its type
    -- in normal form once the context is frozen: where its values are
    -- members of a choice, each binder with what it takes there and the
    -- binder's type, the hook that
    -- lowers its calls, its library functions read against their
    -- definitions (`checkedRow`), and, for an exit, what Idris's types say
    -- of its `believe_me` (`exitTypesOf`); or the refusal of the registry's
    -- row the definitions contradict.
    frozenAs : Frozen -> SortedMap Int Unfrozen -> Unfrozen -> Core (Either Refusal (DefinitionRead ()))
    frozenAs fz found u = do
      normal <- (.value) <$> host.normaliseTypes fz u.type
      let refused = \msg => MkRefusal (Refusal HookShape) (fromMaybe fallback (isNonEmptyFC (location u.def)))
                                     (show (fullname u.def) ++ ": " ++ msg)
      let Right lowered = loweredOf u normal
        | Left msg => pure (Left (refused msg))
      Right checked <- the (Core (Either String (Maybe (Lowered CheckedLibrary)))) $ case lowered of
                         Nothing => pure (Right Nothing)
                         Just row => map Just <$> checkedRow fz found row
        | Left msg => pure (Left (refused msg))
      Right exit <- exitTypesOf fz found u
        | Left msg => pure (Left (refused msg))
      pure (Right (MkDefined u.placement u.def u.type u.matched u.ends u.registered checked exit
                             (placesOf fz ifs normal) (bindersWith (argumentAt u.def) normal) ()))

    -- Every definition read, frozen in order, by its entry; the first
    -- refusal stops the reading.
    frozenAll : Frozen -> SortedMap Int Unfrozen -> SortedMap Int (DefinitionRead ()) -> List (Int, Unfrozen) ->
                Core (Either Refusal (SortedMap Int (DefinitionRead ())))
    frozenAll fz found done [] = pure (Right done)
    frozenAll fz found done ((i, u) :: rest) = do
      Right d <- frozenAs fz found u
        | Left refusal => pure (Left refusal)
      frozenAll fz found (insert i d done) rest
