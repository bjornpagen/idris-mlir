-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What the translation reads of each type constructor's definition, read
||| once where the program is read (`Boundary.readProgram`): its parameters,
||| the role of the argument at each position, and what its values are as
||| numbers go (`TyConFacts`). These follow from the definitions alone,
||| which nothing the translation does changes, so each is found once,
||| before any phase reads it, from the definitions read from what `main`
||| reaches and the frozen context, and kept in the type constructor's own
||| definition as the phases read it (`State.Nature`), with what else the
||| whole program's definitions say of each one (`readWhole`).
module IdrisMLIR.Frontend.Translate.TypeConstructors

import Core.Context
import Core.Core
import Core.TT
import Idris.Host

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Given
import IdrisMLIR.Frontend.Translate.Readings
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Registry

import IdrisMLIR.Ids

import Control.WellFounded
import Data.DPair
import Data.List
import Data.Maybe
import Data.Nat
import Data.SortedMap

%default total

-- A term is closed here over what a given scope holds (`Given.close`),
-- never over a reading's values.
%hide IdrisMLIR.Frontend.Translate.Readings.close

------------------------------------------------------------------------------
-- Stand-ins
------------------------------------------------------------------------------

||| A stand-in for level `i` of a scope's telescope of erased binders: the
||| `i`th binder of a constructor's type, or a function's `i`th index
||| parameter (`Instances.classifyCall`).
export
marker : Nat -> ClosedTerm
marker i = probeTerm (ProbeBinder i)

||| The binder a name stands in for (`marker`), by its number.
markerNumber : Name -> Maybe Nat
markerNumber n = case probeOf n of
  Just (ProbeBinder k) => Just k
  _ => Nothing

||| The binder a term stands in for, if it is a stand-in (`marker`).
export
binderOf : TT vs -> Maybe Nat
binderOf (Ref _ _ n) = markerNumber n
binderOf _ = Nothing

||| Does a term mention the stand-in for the `k`th binder of a constructor's
||| type?
export
mentionsMarker : Nat -> TT vs -> Bool
mentionsMarker k = mentions (\t => binderOf t == Just k)

------------------------------------------------------------------------------
-- Reading the definitions
------------------------------------------------------------------------------

||| A closed term's normal form in the frozen context, its definitions
||| unfolded as `Closed.normaliseClosed` unfolds them.
normal : Reading facts -> ClosedTerm -> Core ClosedTerm
normal r tm = (.value) <$> host.normaliseTypes r.frozen tm

||| A constructor as the translation reads it, once: its definition, its
||| type normalised with every name full (a type may hide its binders
||| behind a definition, `a -@ b` is `(1 _ : a) -> b`, and a record's
||| parameter kinds may be solved metavariables), and that type read under
||| its binders, each given its stand-in (`marker`): what the constructor
||| takes at each binder, as Idris decided it (`argumentAt`), with the
||| binder's type, and the type it returns.
record Constructor where
  constructor MkConstructor
  global : GlobalDef
  normalForm : ClosedTerm
  taking : List (ArgumentAt, ClosedTerm)
  result : ClosedTerm

||| A constructor's type read under its binders, each given its stand-in
||| (`marker`): what the constructor takes at each binder, with the
||| binder's type, and the type it returns.
conBinders : GlobalDef -> Given vs -> Nat -> TT vs -> (List (ArgumentAt, ClosedTerm), ClosedTerm)
conBinders con g i (Bind _ _ (Pi _ rig _ a) sc) =
  let (bs, ret) = conBinders con (give (marker i) g) (S i) sc in ((argumentAt con i rig, close g a) :: bs, ret)
conBinders con g i t = ([], close g t)

||| The constructors of a type constructor, each read once
||| (`Constructor`). Nothing when Idris does not know the constructors (a
||| type declared without them) or one names no definition. What the
||| translation reads of a type constructor is read from these
||| (`factsOf`).
constructorsOf : {0 facts : Type} -> Reading facts -> DefinitionRead facts -> Core (Maybe (List Constructor))
constructorsOf r tc = case definition tc.def of
  TCon _ _ _ _ _ (Just cons) _ => do
    found <- traverse (definedIn r) cons
    case the (Maybe (List (DefinitionRead facts))) (sequence found) of
      Just cs => Just <$> traverse read cs
      Nothing => pure Nothing
  _ => pure Nothing
  where
    read : DefinitionRead facts -> Core Constructor
    read con = do
      ty <- fullNamesIn r.frozen <$> normal r con.type
      let (bs, ret) = conBinders con.def none 0 ty
      pure (MkConstructor con.def ty bs ret)

||| The parameters of a type constructor: Idris's, and those its own
||| reading of the constructors' types misses because a type hides its
||| binders behind a definition (`a -@ LList a -@ LList a`, where Idris sees
||| only an application of `-@`). On the normalised types, as Idris does: a
||| position is a parameter when every occurrence of the type, as a field's
||| result and as the constructor's, has there the same binder of the
||| constructor, and no earlier position has it too. Such an argument is
||| never refined by a match, so reading it as a parameter changes nothing
||| Idris proved. Given the constructors' types (`constructorsOf`).
dataParams : GlobalDef -> Maybe (List Constructor) -> List Nat
dataParams def conTys = case definition def of
  TCon arity params _ _ _ _ _ =>
    let positions : List Nat = iterateN arity S 0
        idris = List.filter (\i => elem i params) positions in
    if length idris == arity then idris else
      let found : List Nat = case conTys of
                    Just ts@(_ :: _) => let sets = map (uniform . (.normalForm)) ts in
                                        List.filter (\i => all (elem i) sets) positions
                    _ => [] in
      List.filter (\i => elem i idris || elem i found) positions
  _ => []
  where
    -- The arguments of an occurrence of the type, as binders; only a
    -- binder's first position counts.
    binders : List ClosedTerm -> List (Maybe Nat)
    binders = go []
      where
        go : List Nat -> List ClosedTerm -> List (Maybe Nat)
        go seen [] = []
        go seen (a :: as) = case binderOf a of
          Just k => if elem k seen then Nothing :: go seen as else Just k :: go (k :: seen) as
          Nothing => Nothing :: go seen as
    -- The occurrence of the type that a type returns, under its binders.
    occurrence : Given vs -> TT vs -> Maybe (List ClosedTerm)
    occurrence g (Bind bfc _ (Pi {}) sc) = occurrence (give (Erased bfc Placeholder) g) sc
    occurrence g tm = case getFnArgs tm of
      (Ref _ _ n, args) => if n == fullname def then Just (map (close g) args) else Nothing
      _ => Nothing
    merge : List (Maybe Nat) -> List (Maybe Nat) -> List (Maybe Nat)
    merge = zipWith (\a, b => if a == b then a else Nothing)
    -- The parameter positions one constructor allows.
    uniform : ClosedTerm -> List Nat
    uniform ty = go none 0 Nothing ty
      where
        positions : List (Maybe Nat) -> List Nat
        positions ms = mapMaybe (\(i, m) => map (const i) m) (zip [0 .. length ms] ms)
        add : Maybe (List (Maybe Nat)) -> ClosedTerm -> Maybe (List (Maybe Nat))
        add acc t = case occurrence none t of
          Just args => Just (maybe (binders args) (\ms => merge ms (binders args)) acc)
          Nothing => acc
        go : Given vs -> Nat -> Maybe (List (Maybe Nat)) -> TT vs -> List Nat
        go g i acc (Bind _ _ (Pi _ _ _ a) sc) = go (give (marker i) g) (S i) (add acc (close g a)) sc
        go g i acc ret = maybe [] positions (add acc (close g ret))

-- A constructor's binder held at runtime.
heldBinder : (ArgumentAt, ClosedTerm) -> Bool
heldBinder (RuntimeValue _, _) = True
heldBinder _ = False

-- Is binder `k` of a constructor's held at runtime, or none of its?
binderHeld : Nat -> List (ArgumentAt, ClosedTerm) -> Bool
binderHeld k bs = maybe True heldBinder (getAt k bs)

-- Does a binder held at runtime have a type that names binder `k`?
namedBy : Nat -> (ArgumentAt, ClosedTerm) -> Bool
namedBy k (RuntimeValue _, a) = mentionsMarker k a
namedBy k _ = False

||| Is a kind certainly the type of values, not a universe: a variable
||| (`x : a`) or a data type (`n : Nat`)?
valueKind : TT vs -> Bool
valueKind (Local {}) = True
valueKind tm = case getFnArgs tm of
  (Ref _ (TyCon _) _, _) => True
  (PrimVal _ _, _) => True
  _ => False

||| Whether each argument of a type constructor's kind is certainly a value
||| (`valueKind`), in order.
kinds : TT vs -> List Bool
kinds (Bind _ _ (Pi _ _ _ a) sc) = valueKind a :: kinds sc
kinds _ = []

------------------------------------------------------------------------------
-- Roles
------------------------------------------------------------------------------

||| The `Keyed` positions of a type constructor's arguments: the types a
||| value of it represents, its parameters whose kind is a universe, and
||| which some constructor holds at runtime or names in the type of an
||| argument it holds at runtime. With the `Formed` shapes, they tell
||| instances apart; every other argument (an index, or a value parameter
||| such as `Equal`'s `x`) is compile-time information. A parameter no
||| constructor names is a phantom (the state thread `s` of base's `ST s a`
||| and `STRef s a`): every type it is given has values of one
||| representation, so one instance serves them all, and a type
||| abstraction over it, `{0 s : Type} -> ST s Int`, is a value of that one
||| instance once applied to whatever type. Given its parameters and its
||| constructors' types (`constructorsOf`).
keyedOf : Reading facts -> DefinitionRead facts -> List Nat -> Maybe (List Constructor) -> Core (List Nat)
keyedOf r tc params conTys = case definition tc.def of
  TCon arity _ _ _ _ _ _ => do
    -- A record's parameter kinds may be solved metavariables, and a type
    -- may be declared through a definition of its kind (`data CaseTree :
    -- Scoped`, where `Scoped = Scope -> Type`): its binders are those of
    -- the normal form.
    ty <- normal r tc.type
    let values = kinds ty
    let types = filter (\i => elem i params && not (fromMaybe False (getAt i values))) (iterateN arity S 0)
    -- Without its constructors, every type parameter counts.
    pure (case conTys of
            Just ts@(_ :: _) => filter (\i => any (represents i) ts) types
            _ => types)
  _ => pure []
  where
    -- Does a constructor represent the parameter at position `p` of the
    -- type it returns: does it hold the binder there at runtime, or name it
    -- in the type of an argument it holds at runtime? An erased argument
    -- has no representation, whatever its type names (`Subset`'s
    -- predicate, the type of its erased proof). Anything but a binder
    -- there counts.
    represents : Nat -> Constructor -> Bool
    represents p con = case getAt p (snd (getFnArgs con.result)) >>= binderOf of
      Just k => binderHeld k con.taking || any (namedBy k) con.taking
      Nothing => True

-- A split of candidates that holds one or more leaves fewer out.
0 shorter : (a, b : Nat) -> a + S b = n -> LT a n
shorter a b Refl = rewrite sym (plusSuccRightSucc a b) in LTESucc (lteAddRight a)

||| The `Held` positions of a type constructor's arguments: every argument
||| but a parameter whose kind is a universe and that its values hold. A
||| value holds such an argument when a constructor that has its own binder
||| there holds a runtime argument whose type reaches that binder, through
||| a function type's argument or result, a suspension, or a represented
||| position of a type constructor (this one's, or another's `Keyed`
||| ones). It is the least such set: `L : a -> T a` makes `T`'s `a` a
||| position, and `PCons : P (a, a) -> P a`, whose index no value holds,
||| does not. Such an index is checked by the growth phase, never a key.
||| Given the type constructor's parameters, its `Keyed` positions and its
||| constructors' types (`constructorsOf`).
heldOf : Reading facts -> DefinitionRead facts -> (params, keys : List Nat) -> List Constructor -> Core (List Nat)
heldOf r tc ps keys conTys = case definition tc.def of
  TCon arity _ _ _ _ _ _ => do
    ty <- normal r tc.type
    let values = kinds ty
    -- Every argument position: `[0 .. minus arity 1]` would be `[0]` at
    -- arity 0.
    let candidates@(_ :: _) = filter (\i => not (elem i ps) && not (fromMaybe False (getAt i values)))
                                     (iterateN arity S 0)
      | [] => pure []
    least keys conTys [] candidates (wellFounded _)
  _ => pure []
  where
    -- The `Keyed` positions of another type constructor.
    keysOf : Name -> Core (List Nat)
    keysOf d = do
      Just other <- definedIn r d
        | Nothing => pure []
      conTys <- constructorsOf r other
      keyedOf r other (dataParams other.def conTys) conTys

    mutual
      -- Does a type reach the stand-in for binder `k`, at the positions
      -- `own` of this type constructor?
      reaches : List Nat -> Nat -> TT vs -> Core Bool
      reaches own k (Ref _ _ n) = pure (markerNumber n == Just k)
      reaches own k (Bind _ _ (Pi _ rig _ a) sc) = do
        inA <- case use rig of
                 Erased => pure False
                 Used _ => reaches own k a
        if inA then pure True else reaches own k sc
      reaches own k (TDelayed _ _ t) = reaches own k t
      reaches own k tm = case getFnArgs tm of
        (Ref _ (TyCon _) d, args) => do
          ks <- if d == fullname tc.def then pure own else keysOf d
          spine ks own k (length args) tm
        _ => pure False

      -- The arguments at positions `ks` of an application of `j`
      -- arguments, the last first, so that each is a subterm.
      spine : List Nat -> List Nat -> Nat -> Nat -> TT vs -> Core Bool
      spine ks own k (S j) (App _ f a) = do
        here <- if elem j ks then reaches own k a else pure False
        if here then pure True else spine ks own k j f
      spine _ _ _ _ _ = pure False

    -- Does a binder held at runtime have a type that reaches binder `k`?
    reachedBy : List Nat -> Nat -> (ArgumentAt, ClosedTerm) -> Core Bool
    reachedBy own k (RuntimeValue _, a) = reaches own k a
    reachedBy own k _ = pure False

    -- Does a constructor whose return type has its own binder at `p` hold
    -- a runtime argument whose type reaches it?
    holds : List Nat -> Nat -> Constructor -> Core Bool
    holds own p con = case getAt p (snd (getFnArgs con.result)) >>= binderOf of
      Just k => any id <$> traverse (reachedBy own k) con.taking
      Nothing => pure False

    -- The candidates of `out` the set `held` makes held, and the rest, as
    -- many between them as `out` has.
    among : List Nat -> List Constructor -> List Nat -> (out : List Nat) ->
            Core (Subset (List Nat, List Nat) (\s => length (snd s) + length (fst s) = length out))
    among keys conTys held [] = pure (Element ([], []) Refl)
    among keys conTys held (p :: ps) = do
      Element (ins, outs) n <- among keys conTys held ps
      True <- any id <$> traverse (holds (keys ++ held) p) conTys
        | False => pure (Element (ins, p :: outs) (cong S n))
      pure (Element (p :: ins, outs) (trans (sym (plusSuccRightSucc _ _)) (cong S n)))

    -- The least set, from none: each round holds what the set so far makes
    -- held among the candidates still out, and the set is whole at a round
    -- that holds none. A round that holds one or more leaves fewer out, so
    -- the rounds descend on the candidates still out.
    least : List Nat -> List Constructor -> List Nat -> (out : List Nat) ->
            (0 _ : Accessible LT (length out)) -> Core (List Nat)
    least keys conTys held out (Access fewer) = do
      Element (p :: ps, outs) n <- among keys conTys held out
        | Element ([], _) _ => pure held
      least keys conTys (held ++ p :: ps) outs (fewer _ (shorter _ _ n))

||| What a type constructor's values are as numbers, from its constructors
||| (`constructorsOf`): `Nat`-like when they carry Idris's `ZERO` and
||| `SUCC` flags, read from Idris's metadata, never from names; a `Chain`
||| when each also takes every argument at runtime, none at quantity 0. A
||| key keeps what a constructor takes at quantity 0 (`FS`'s index), so a
||| chain's values' keys are only their successors: `Nat`, but neither
||| `Fin` nor `Elem`, which are `Numeral`s.
natnessOf : Maybe (List Constructor) -> Natness
natnessOf (Just cons@(_ :: _)) =
  if not (all (isJust . natRole . (.global)) cons) then NotNat
    else if all (\con => all heldBinder con.taking) cons then Chain
    else Numeral
natnessOf _ = NotNat

||| The roles of a value array's arguments, its shape and its element, as
||| `Shapes.arrayParts` reads them: the shape is its form, and the element
||| a type. The registry's hook says a type constructor is one; it has no
||| constructors to read anything else off.
valueArrayRoles : List Role
valueArrayRoles = [Formed, Keyed]

------------------------------------------------------------------------------
-- Forms
------------------------------------------------------------------------------

mutual
  -- Each application of a type constructor in a term, with whether each of
  -- its arguments, the first first, mentions what the test picks.
  picked : ({0 vs : Scope} -> TT vs -> Bool) -> TT vars -> List (Name, List Bool)
  picked p tm = applied p tm []

  -- A term applied to arguments, the first first.
  applied : ({0 vs : Scope} -> TT vs -> Bool) -> TT vars -> List (TT vars) -> List (Name, List Bool)
  applied p (App _ f a) args = picked p a ++ applied p f (a :: args)
  applied p (Ref _ (TyCon _) n) args = [(n, map (mentions p) args)]
  applied p (Bind _ _ b sc) _ = pickedIn p b ++ picked p sc
  applied p (TDelayed _ _ t) _ = picked p t
  applied p (TDelay _ _ t a) _ = picked p t ++ picked p a
  applied p (TForce _ _ t) _ = picked p t
  applied p (As _ _ _ pat) _ = picked p pat
  applied p _ _ = []

  -- A binder's type, and a `let`'s value.
  pickedIn : ({0 vs : Scope} -> TT vs -> Bool) -> TTBinder (TT vars) -> List (Name, List Bool)
  pickedIn p (Lam _ _ _ ty) = picked p ty
  pickedIn p (Let _ _ v ty) = picked p v ++ picked p ty
  pickedIn p (Pi _ _ _ ty) = picked p ty
  pickedIn p (PVar _ _ _ ty) = picked p ty
  pickedIn p (PLet _ _ v ty) = picked p v ++ picked p ty
  pickedIn p (PVTy _ _ ty) = picked p ty

||| What the `Formed` positions of type constructors are assumed to be
||| while they are found: those of each type constructor whose own are
||| being found on the walk, by its name, as far as they are found so far.
public export
Assumed : Type
Assumed = List (Name, List Nat)

||| The facts of the type constructors found already, by the definition:
||| while the definitions are read, those of the type constructors found
||| before this one (`typeConstructorsOf`); once they are all read, every
||| type constructor's, which its nature holds (`natureFacts`). None for a
||| type constructor not found yet, whose facts the walk finds
||| (`formedAt`), and for a definition that is no type constructor.
public export
FactsFound : Type -> Type
FactsFound facts = DefinitionRead facts -> Maybe TyConFacts

||| The facts of every type constructor, once the program is read: each
||| one's nature holds them.
export
natureFacts : FactsFound Nature
natureFacts d = case d.nature.asTypeConstructor of
  ATypeConstructor facts => Just facts
  NoTypeConstructor => Nothing

mutual
  ||| Does a binder of this kind stand where terms put it in a form: is its
  ||| kind the shape type, and is it, as the test picks it out, in an
  ||| argument at a `Formed` position of a type constructor applied in one
  ||| of the terms (a value array's shape, or a shape a data type's array
  ||| reads)? A tensor's rank is its type, so such a binder keys what its
  ||| type is. The one rule for a function's erased binder
  ||| (`Types.formNeeded`) and a data type's parameter (`formedIn`). The
  ||| facts of the type constructors found already are `known`.
  export
  formRead : Reading facts -> (known : FactsFound facts) ->
             (w : Walked) -> (0 _ : SizeAccessible w) -> Assumed ->
             (kind : ClosedTerm) -> ({0 vs : Scope} -> TT vs -> Bool) -> List ClosedTerm -> Core Bool
  formRead r known w acc assumed kind p ts =
    if isShapeType (shapeOf (fullNamesIn r.frozen kind))
       then inForm r known w acc assumed (ts >>= picked p)
       else pure False

  -- Is one of the arguments picked at a `Formed` position of the type
  -- constructor applied to it?
  inForm : Reading facts -> FactsFound facts ->
           (w : Walked) -> (0 _ : SizeAccessible w) -> Assumed -> List (Name, List Bool) -> Core Bool
  inForm r known w acc assumed [] = pure False
  inForm r known w acc assumed ((n, ms) :: rest) = do
    fs <- formedAt r known w acc assumed n
    if any (\j => fromMaybe False (getAt j ms)) fs then pure True else inForm r known w acc assumed rest

  -- The `Formed` positions of a type constructor, by its name: as assumed
  -- while its own are being found, as found already (`known`), or else
  -- found here, the walk entering it. Every type constructor the walk has
  -- entered is assumed, so one it cannot enter is none the context holds
  -- a place for.
  formedAt : Reading facts -> FactsFound facts ->
             (w : Walked) -> (0 _ : SizeAccessible w) -> Assumed -> Name -> Core (List Nat)
  formedAt r known w (Access rec) assumed n = case lookup n assumed of
    Just fs => pure fs
    Nothing => do
      Just tc <- definedIn r n
        | Nothing => pure []
      case known tc of
        Just found => pure (positionsOf (== Formed) found.roles)
        Nothing => case enter tc.placement w of
          Just (Element w' less) => formedIn r known w' (rec w' less) assumed tc
          Nothing => pure []

  ||| The `Formed` positions of a type constructor: a value array's shape
  ||| (`valueArrayRoles`), and the least set of its parameters of which a
  ||| constructor's runtime field puts the binder at the parameter in a
  ||| form (`formRead`), this type constructor's own positions read as the
  ||| set found so far, and those of every type constructor its fields
  ||| apply found the same way, inside, with this one's assumed. Each round
  ||| adds what the set so far makes formed among the parameters still out,
  ||| and the set is whole at a round that adds none, so the rounds descend
  ||| on the parameters still out, as the walk does on the type
  ||| constructors it has entered. `Grid : Shape -> Type` with `MkGrid :
  ||| Array s Int -> Grid s` has its shape formed, and so does a type whose
  ||| constructor holds a `Grid s`; a phantom shape, which no field puts in
  ||| an array, has not.
  formedIn : Reading facts -> FactsFound facts ->
             (w : Walked) -> (0 _ : SizeAccessible w) -> Assumed -> DefinitionRead facts -> Core (List Nat)
  formedIn r known w acc assumed tc =
    if (namedHooks tc.registered).valueArray then pure (positionsOf (== Formed) valueArrayRoles) else do
      Just cons <- constructorsOf r tc
        | Nothing => pure []
      rounds r known w acc assumed (fullname tc.def) cons [] (dataParams tc.def (Just cons)) (wellFounded _)

  rounds : Reading facts -> FactsFound facts ->
           (w : Walked) -> (0 _ : SizeAccessible w) -> Assumed -> Name -> List Constructor ->
           (formed, out : List Nat) -> (0 _ : Accessible LT (length out)) -> Core (List Nat)
  rounds r known w acc assumed self conTys formed out (Access fewer) = do
    Element (p :: ps, outs) n <- formedAmong r known w acc ((self, formed) :: assumed) conTys out
      | Element ([], _) _ => pure (sort formed)
    rounds r known w acc assumed self conTys (formed ++ p :: ps) outs (fewer _ (shorter _ _ n))

  -- The parameters of `out` some constructor puts in a form, and the rest,
  -- as many between them as `out` has.
  formedAmong : Reading facts -> FactsFound facts ->
                (w : Walked) -> (0 _ : SizeAccessible w) -> Assumed -> List Constructor -> (out : List Nat) ->
                Core (Subset (List Nat, List Nat) (\s => length (snd s) + length (fst s) = length out))
  formedAmong r known w acc assumed conTys [] = pure (Element ([], []) Refl)
  formedAmong r known w acc assumed conTys (p :: ps) = do
    Element (ins, outs) n <- formedAmong r known w acc assumed conTys ps
    True <- formedBy r known w acc assumed p conTys
      | False => pure (Element (ins, p :: outs) (cong S n))
    pure (Element (p :: ins, outs) (trans (sym (plusSuccRightSucc _ _)) (cong S n)))

  -- Does a constructor whose return type has its own binder at parameter
  -- `p` put that binder in a form with a runtime field?
  formedBy : Reading facts -> FactsFound facts ->
             (w : Walked) -> (0 _ : SizeAccessible w) -> Assumed -> Nat -> List Constructor -> Core Bool
  formedBy r known w acc assumed p [] = pure False
  formedBy r known w acc assumed p (con :: cs) = do
    let bs = con.taking
    here <- case getAt p (snd (getFnArgs con.result)) >>= binderOf of
      Just k => case getAt k bs of
        Just (_, kind) => formRead r known w acc assumed kind (\t => binderOf t == Just k) (map snd (filter heldBinder bs))
        Nothing => pure False
      Nothing => pure False
    if here then pure True else formedBy r known w acc assumed p cs

------------------------------------------------------------------------------
-- The facts
------------------------------------------------------------------------------

||| What the translation reads of a type constructor's definition, from its
||| constructors read once (`constructorsOf`): its parameters
||| (`dataParams`), the role of each argument (`keyedOf`, `formedIn`,
||| `heldOf`; a value array's are `valueArrayRoles`), and how it is
||| `Nat`-like (`natnessOf`). Those of the type constructors found before
||| it are `known`.
factsOf : Reading facts -> (known : FactsFound facts) -> DefinitionRead facts -> Core TyConFacts
factsOf r known tc = do
  conTys <- constructorsOf r tc
  let ps = dataParams tc.def conTys
  roles <- if (namedHooks tc.registered).valueArray then pure valueArrayRoles else do
             let TCon arity _ _ _ _ _ _ = definition tc.def
               | _ => pure []
             keys <- keyedOf r tc ps conTys
             -- The walk starts at this type constructor, entered.
             let w = startAt tc.placement
             forms <- formedIn r known w (sizeAccessible w) [] tc
             held <- heldOf r tc ps keys (fromMaybe [] conTys)
             pure (map (roleOf keys forms held) (iterateN arity S 0))
  pure (MkTyConFacts ps roles (natnessOf conTys))
  where
    roleOf : (keys, forms, held : List Nat) -> Nat -> Role
    roleOf keys forms held j =
      if elem j forms then Formed
        else if elem j keys then Keyed
        else if elem j held then Held
        else Index

||| What the translation reads of every type constructor read from what
||| `main` reaches (`factsOf`), by address, each found once, in the order
||| the table holds them: each reads the facts of those found before it,
||| and walks to the rest (`formedAt`). The table holds a type
||| constructor's facts and nothing else.
typeConstructorsOf : Reading () -> Core (SortedMap Address TyConFacts)
typeConstructorsOf r = foldlM add empty (values r.definitions)
  where
    add : SortedMap Address TyConFacts -> DefinitionRead () -> Core (SortedMap Address TyConFacts)
    add known d = case definition d.def of
      TCon {} => (\facts => insert (addressOf d.placement) facts known) <$>
                   factsOf r (\other => lookup (addressOf other.placement) known) d
      _ => pure known

||| What every phase after the boundary reads of the program, once every
||| definition it can meet is read (`Reading ()`): each definition with
||| what follows of it from all of them (`Nature`), found once: its facts
||| as a type constructor, found here (`typeConstructorsOf`), whose table
||| holds a type constructor's and no other's; what the walk that names
||| blocks calls it (`called`, by address, `Boundary.blockNamesOf`); and the
||| component Idris proved its loops end in (`proved`, by address,
||| `Recursion.loopsOf`), a definition with no proof one that may diverge.
export
readWhole : (proved : SortedMap Address ComponentId) -> (called : SortedMap Address String) ->
            Reading () -> Core Read
readWhole proved called r = do
  facts <- typeConstructorsOf r
  pure (natured (natureFrom facts called proved) r)
