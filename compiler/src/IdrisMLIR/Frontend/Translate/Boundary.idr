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
||| it as frozen. Where a definition's values are members of a choice is
||| read off its type in normal form, once the context is frozen. The
||| translation reads these and nothing else of the context
||| (`Errors.defined`).
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
||| names, which the translation builds itself.
module IdrisMLIR.Frontend.Translate.Boundary

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.Options
import Core.TT
import Idris.Host

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Registry

import Control.WellFounded
import Data.DPair
import Data.List
import Data.List1
import Data.Maybe
import Data.SnocList
import Data.SortedMap
import Data.SortedSet

%default total

------------------------------------------------------------------------------
-- What a definition refers to
------------------------------------------------------------------------------

||| A name a definition refers to, as a walk over what the program reaches
||| follows it: a definition, or a metavariable, whose solution a walk that
||| names blocks reads under the definition that refers to it (`Keys`).
public export
data Referent = ARef Name | AMeta Name

||| The name a reference is to.
export
referentName : Referent -> Name
referentName (ARef n) = n
referentName (AMeta n) = n

mutual
  ||| The references of a term, left to right: a function before its
  ||| argument, a binder's type and value before its scope.
  termRefs : SnocList Referent -> Term vs -> SnocList Referent
  termRefs acc (Ref _ _ n) = acc :< ARef n
  termRefs acc (Meta _ n _ args) = termsRefs (acc :< AMeta n) args
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
||| definition name.
librariesOf : Registered -> List Name
librariesOf (Hooked hs) = map (.name) (libraries hs)
librariesOf (Unhooked _) = []

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
referred : Unfrozen -> List Name
referred d =
  map referentName (references d.matched d.type)
  ++ constructors (definition d.def)
  ++ maybe [] (:: []) (parentOf (fullname d.def))
  ++ map (.fnCall) (sizeChange d.def)
  ++ librariesOf d.registered
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

||| What the registry makes of a definition (`Registered`): a foreign
||| definition's hooks by its specs, any other's by its name, each library
||| function they name interned once, where it enters the compiler.
registeredOf : {auto c : Ref Ctxt Defs} -> GlobalDef -> Core Registered
registeredOf def = case definition def of
  ForeignDef _ specs => case foreignHooks (fullname def) specs of
    Right hs => Hooked <$> interned hs
    Left miss => pure (Unhooked miss)
  _ => Hooked <$> interned (hooksOf (fullname def))
  where
    interned : Hooks QName -> Core (Hooks LibraryFunction)
    interned = readLibraries (\q => MkLibraryFunction q <$> toName q)

||| A definition as the translation reads it, each part through the
||| context's accessors once, before the context is frozen: its type; of
||| one that matches, its case tree, its clauses' patterns and its one
||| clause; whether it ends (`verdictOf`); and what the registry makes of it.
readDefinition : {auto c : Ref Ctxt Defs} -> Int -> Placement -> GlobalDef -> Core Unfrozen
readDefinition i p def0 = do
  (def, ends) <- verdictOf i def0
  ty <- (.fst) <$> host.typeOf def
  m <- case definition def of
         PMDef _ args body => Just <$> matched args body
         _ => pure Nothing
  pure (MkUnfrozen p def ty m ends !(registeredOf def))
  where
    matched : (args : Scope) -> Body args -> Core Matched
    matched args body = do
      tree <- (.fst) <$> host.treeOf body
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
||| unknown, or a definition its arguments leave stuck; or anything else,
||| which no value of a choice has (a constant, a universe, a constructor).
data Headed = ByTypeConstructor Name | Undecided | Neither

headed : Term vs -> Headed
headed ty = case getFn ty of
  Ref _ (TyCon _) n => ByTypeConstructor n
  Ref _ Func _ => Undecided
  Local {} => Undecided
  Meta {} => Undecided
  _ => Neither

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
-- Reading the program
------------------------------------------------------------------------------

||| Every definition met from the names, after those read so far, each read
||| once and kept by its entry, then what it refers to read in turn. A
||| definition is entered into a walk when it is read (`Walk`), and every
||| one read leaves fewer to enter, which is why the reading ends; a name
||| the context defines as nothing, a probe's or a binder's, is no
||| definition to read.
readFrom : {auto c : Ref Ctxt Defs} -> (w : Walked) -> (0 _ : SizeAccessible w) ->
           SortedMap Int Unfrozen -> List Name -> Core (SortedMap Int Unfrozen)
readFrom w acc found [] = pure found
readFrom w acc@(Access rec) found (n :: ns) = do
  defs <- get Ctxt
  Just (i, def) <- lookupCtxtExactI n (gamma defs)
    | Nothing => readFrom w acc found ns
  -- A negative entry is no place, which Idris's bare `Int` allows.
  let Just p = placementOf i
    | Nothing => readFrom w acc found ns
  case enter p w of
    -- Read already.
    Nothing => readFrom w acc found ns
    Just (Element w' less) => do
      d <- readDefinition i p def
      readFrom w' (rec w' less) (insert i d found) (referred d ++ ns)

||| The type a member at a use is applied as by (`AtUse`): `{0 t : Type} ->
||| (f : t) -> t`, the form's type, then the form, giving a value of the
||| form's type, its binders' names interned once.
applicationOf : {auto c : Ref Ctxt Defs} -> Core ClosedTerm
applicationOf = do
  t <- intern "t"
  f <- intern "f"
  u <- intern "u"
  pure (Bind EmptyFC (UN (Basic t)) (Pi EmptyFC erased Implicit (TType EmptyFC (UN (Basic u))))
          (Bind EmptyFC (UN (Basic f)) (Pi EmptyFC top Explicit (Local EmptyFC Nothing 0 First))
                (Local EmptyFC Nothing 1 (Later First))))

||| What the translation reads of a program whose entry is the definition
||| named `entry`, and whose loaded interfaces are `interfaces`: every
||| definition it can meet from the entry and from the pair `%pair` names,
||| read from the loaded context, every verdict the reading writes in it
||| before it is frozen; then the context frozen, and where each
||| definition's values are members of a choice read off its type in
||| normal form.
export
readProgram : {auto c : Ref Ctxt Defs} -> (interfaces : SortedSet Name) -> (entry : Name) -> Core Read
readProgram ifs entry = do
  defs <- get Ctxt
  let pair = maybe [] (\ns => [pairType ns, fstName ns, sndName ns]) (pairnames (options defs))
  found <- readFrom start (sizeAccessible start) empty (entry :: pair)
  -- The context changes no more: frozen here, every normaliser reads it as
  -- frozen.
  fz <- host.freezeContext
  definitions <- traverse (definedIn fz) found
  application <- applicationOf
  pure (MkRead fz definitions application ifs)
  where
    definedIn : Frozen -> Unfrozen -> Core Defined
    definedIn fz u = do
      normal <- (.value) <$> host.normaliseTypes fz u.type
      pure (MkDefined u.placement u.def u.type u.matched u.ends u.registered (placesOf fz ifs normal))
