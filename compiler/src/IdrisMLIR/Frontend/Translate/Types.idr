-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Types and data instances: the Core type of a closed Idris type, and the
||| monomorphic data instances it names, registered as they are met.
module IdrisMLIR.Frontend.Translate.Types

import Core.Context
import Core.Core
import Core.Env
import Core.TT
import Core.TT.Traversals
import Libraries.Data.List.Finite
import Libraries.Data.NatSet

import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Finite
import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Translate.Boundary
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Given
import IdrisMLIR.Frontend.Translate.Keys
import IdrisMLIR.Frontend.Translate.Shapes
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.TypeConstructors
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.MLIR
import IdrisMLIR.Registry
import IdrisMLIR.Spec.Core.Rules
import IdrisMLIR.Spec.Families.Group
import IdrisMLIR.Spec.Grades.Grade
import IdrisMLIR.Term
import IdrisMLIR.Proof.Forms
import IdrisMLIR.Proof.Growth
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Types

import Control.WellFounded
import Data.DPair
import Data.Fin
import Data.List
import Data.List.Elem
import Data.List.Quantifiers
import Decidable.Equality
import Data.SnocList
import Data.SortedMap
import Data.SortedSet
import Data.String

%default total

||| A term read in another scope: each level's stand-in replaced by the
||| closed term given for it there, and erased where none is given, since a
||| level of one scope is never one of another's.
export
atLevels : List (Maybe ClosedTerm) -> {vars : _} -> TT vars -> TT vars
atLevels given = mapTerm at
  where
    at : {vs : _} -> Term vs -> Term vs
    at t = case binderOf t of
      Just j => maybe (Erased EmptyFC Placeholder) embedClosed (join (getAt j given))
      Nothing => t

||| A term with every level's stand-in erased: what a key holds of an
||| argument (a static argument a call gives the instance it keys, a type
||| argument a data instance is keyed by) names no level of the scope it
||| is written in, whose levels are no one else's, so an erased index keys
||| nothing.
export
unmarked : {vars : _} -> TT vars -> TT vars
unmarked = atLevels []

||| Which arguments of a constructor are the data type's parameters, whose
||| values the data instance gives: each binder of its type is replaced by a
||| marker, and the markers found at the parameter positions of the return
||| type name them. An erased binder there is given the instance's argument
||| (an erased one where the key holds none); one the constructor holds at
||| runtime is given it only at a `Keyed` position, a type, and at any
||| other is a field (`MkTag : (n : Nat) -> Tag n`, which Idris finds at
||| the same place in every constructor), whose value a form would not be.
export
paramLayout : (con : GlobalDef) -> List Nat -> List Role -> ClosedTerm -> List (Maybe Nat)
paramLayout con params roles ty =
  let (n ** (ret, taken)) = markAll none 0 ty
      args = snd (getFnArgs ret)
      -- The first parameter a binder's marker is found at.
      found = SortedMap.fromList (reverse (mapMaybe (\p => (,p) <$> (getAt p args >>= binderOf)) params))
  in toList (zipWith (\i, a => lookup (finToNat i) found >>= given a) (allFins n) taken)
  where
    -- What the constructor takes at each binder (`argumentAt`), by
    -- position, and the return type with each binder its marker.
    markAll : Given vs -> Nat -> TT vs -> (n ** (ClosedTerm, Vect n ArgumentAt))
    markAll g i (Bind _ _ (Pi _ rig _ _) sc) =
      let (n ** (ret, taken)) = markAll (give (marker i) g) (S i) sc in (S n ** (ret, argumentAt con i rig :: taken))
    markAll g i t = (0 ** (close g t, []))
    given : ArgumentAt -> Nat -> Maybe Nat
    given (RuntimeValue _) p = if roleAt p roles == Keyed then Just p else Nothing
    given _ p = Just p

||| An extent's dimension: static where its normal form is a literal, a
||| `Nat`-like chain of successors ending at zero (read from Idris's flags,
||| never from names) or a non-negative integer; dynamic otherwise, since
||| an erased extent is the value's own, never a constant it is assumed to
||| be.
extentDim : {auto c : Ref Ctxt Defs} -> ClosedTerm -> Front Dim
extentDim = go 0
  where
    -- The role of the constructor a term is an application of.
    roleOf : ClosedTerm -> Front (Maybe NatRole)
    roleOf tm = case getFn tm of
      Ref _ (DataCon _ _) n => do
        found <- defined n
        pure (found >>= \con => natRole con.def)
      _ => pure Nothing
    -- A successor's predecessor is its last argument.
    go : Nat -> ClosedTerm -> Front Dim
    go k tm@(App _ _ pred) = case !(roleOf tm) of
      Just Zero => pure (Static k)
      Just Succ => go (S k) pred
      Nothing => pure Dynamic
    go k tm@(Ref _ (DataCon _ _) _) = case !(roleOf tm) of
      Just Zero => pure (Static k)
      _ => pure Dynamic
    go k (PrimVal _ c) = case constantLit c of
      Just (LBig i) => pure (if i >= 0 then Static (k + integerToNat i) else Dynamic)
      _ => pure Dynamic
    go k _ = pure Dynamic

||| The dimensions of a value array's shape at an instance, one per axis of
||| its form, outermost first (`spineOf`, which refuses a shape that has
||| none).
shapeDims : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            FC -> String -> ClosedTerm -> Front (List Dim)
shapeDims fc owner shape = traverse extentDim (extents !(spineOf fc owner !(normaliseClosed shape)))

||| Does the rest of a function's type need an erased binder's form: is
||| the binder a shape that the rest, with `formProbe` for it, puts in a
||| form (`TypeConstructors.formRead`), the type constructors' forms as
||| they were read with the program (`Read.tyCons`)?
export
formNeeded : (kind : ClosedTerm) -> (ClosedTerm -> ClosedTerm) -> Front Bool
formNeeded kind rest = do
  r <- reading
  probed <- fullTerm !(normaliseClosed (rest formProbe))
  core (formRead r r.tyCons start (sizeAccessible start) [] kind isFormProbe [probed])

||| What the translation reads of a type constructor's definition
||| (`TyConFacts`), read once with the program (`Read.tyCons`,
||| `TypeConstructors`). Every type constructor read has them, so a
||| definition without them is none, which no caller asks of: each asks of
||| the definition a type constructor's name heads.
export
tyConFacts : Defined -> Front TyConFacts
tyConFacts tc = do
  r <- reading
  -- The facts are a table the type constructors' addresses key, read for
  -- every type constructor read, which the table's type does not say.
  let Just facts = lookup (addressOf tc.placement) r.tyCons
    | Nothing => internal (location tc.def) ("the facts of " ++ show (fullname tc.def) ++ ", which is no type constructor")
  pure facts

||| The positions of a type constructor's arguments the growth check
||| watches (`watched`), read with its other facts (`tyConFacts`).
export
represented : Defined -> Front (List Nat)
represented tc = positionsOf watched . (.roles) <$> tyConFacts tc

||| The roles of a type constructor's arguments; nothing for a name that
||| is no type constructor.
rolesOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          String -> Name -> Front (Maybe (List Role))
rolesOf owner n = do
  tc <- lookupDef EmptyFC owner n
  case definition tc.def of
    TCon {} => pure (Just (!(tyConFacts tc)).roles)
    _ => pure Nothing

||| Does a type mention what the test picks other than as an index of an
||| inductive family? Indices exist at compile time only, so a type that
||| mentions something only there has one representation whatever it is.
export
outsideIndices : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 (ClosedTerm -> Bool) -> String -> ClosedTerm -> Front Bool
outsideIndices picks owner = within none
  where
    mutual
      within : Given vs -> TT vs -> Front Bool
      within g (Bind bfc _ (Pi _ rig _ a) sc) = do
        -- The argument is erased in the result: a dependency on it is one on
        -- an erased value, unless it is only an index. A quantity-0 binder
        -- of kind Type, `{0 s : Type} -> ST s Int` (the argument of base's
        -- runST), is compile-time only: a value of the type is applied to a
        -- type and to nothing at runtime, so it has the representation of
        -- its body with the binder erased (`coreType`), one representation
        -- for whatever type it is applied to. The body may then mention the
        -- binder only where no representation needs it, as an index or a
        -- phantom parameter (`keyedOf`); anywhere else (`{0 s : Type} ->
        -- List s`) the representation would depend on it, and the type is
        -- refused. An argument taken with quantity 0 is not passed: its type
        -- has no representation, whatever it mentions (`(0 _ : IsConClause
        -- p) -> ...`).
        inA <- case use rig of
                 Erased => pure False
                 Used _ => within g a
        inB <- within (give (Erased bfc Placeholder) g) sc
        pure (inA || inB)
      -- A suspension of a type depends on what the type depends on:
      -- `coreType` represents `Lazy t` as a suspension of `t`'s
      -- representation.
      within g (TDelayed _ _ t) = within g t
      -- A type family, at a type parameter (`DPair a (\x => Vect x Int)`,
      -- `SortedDMap k (\_ => v)`): its values have its body's
      -- representation, whatever its argument, so the body is what may
      -- depend on something, as a function type's result is.
      within g (Bind bfc _ (Lam {}) sc) = within (give (Erased bfc Placeholder) g) sc
      -- Only a `Keyed` argument is a type a representation is made of: a
      -- `Formed` one is a shape whose extents are indices, and whose rank
      -- the key holds (`spineOf` refuses one with none).
      within g tm = case getFnArgs tm of
        (Ref _ (TyCon _) n, args) => do
          Just rs <- rolesOf owner n
            | Nothing => pure (picks (close g tm))
          params g rs (length args) tm
        _ => pure (picks (close g tm))

      -- The arguments at the `Keyed` positions of an application of `k`
      -- arguments, the last first, so that each is a subterm.
      params : Given vs -> List Role -> Nat -> TT vs -> Front Bool
      params g rs (S k) (App _ f a) = do
        here <- if roleAt k rs == Keyed then within g a else pure False
        before <- params g rs k f
        pure (here || before)
      params g rs _ _ = pure False

||| Does a type mention an erased value other than as an index of an
||| inductive family? Indices exist at compile time only, so a value of the
||| family stores none.
export
erasedOutsideIndices : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                       String -> ClosedTerm -> Front Bool
erasedOutsideIndices = outsideIndices anyErased

mutual
  ||| A type with the indices of every inductive family in it erased, so
  ||| that `Vect 3 Double` and `Vect n Double` name one instance, and every
  ||| shape a value array's type needs cut to its form, so that `Vector 3
  ||| Int` and `Vector n Int` do too. A type family is a lambda
  ||| (`SortedDMap k (\_ => v)`, `DPair a (\x => p x)`): the indices inside
  ||| its body are erased the same way, so two families that differ only
  ||| there name one instance.
  eraseIndices : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 {vars : _} -> FC -> String -> TT vars -> Front (TT vars)
  eraseIndices fc owner (Bind bfc x b sc) = do
    b' <- binder b
    sc' <- eraseIndices fc owner sc
    pure (Bind bfc x b' sc')
    where
      binder : TTBinder (TT vars) -> Front (TTBinder (TT vars))
      binder (Lam lfc rig info ty) = Lam lfc rig info <$> eraseIndices fc owner ty
      binder (Let lfc rig v ty) = Let lfc rig <$> eraseIndices fc owner v <*> eraseIndices fc owner ty
      binder (Pi lfc rig info ty) = Pi lfc rig info <$> eraseIndices fc owner ty
      binder (PVar lfc rig info ty) = PVar lfc rig info <$> eraseIndices fc owner ty
      binder (PLet lfc rig v ty) = PLet lfc rig <$> eraseIndices fc owner v <*> eraseIndices fc owner ty
      binder (PVTy lfc rig ty) = PVTy lfc rig <$> eraseIndices fc owner ty
  eraseIndices fc owner tm = case getFnArgs tm of
    (Ref _ (TyCon _) n, args) => do
      Just rs <- rolesOf owner n
        | Nothing => pure tm
      erase rs (length args) tm
    _ => pure tm
    where
      -- An application of `k` arguments with each one keyed by its role,
      -- the last first, so that each is a subterm.
      erase : List Role -> Nat -> TT vars -> Front (TT vars)
      erase rs (S k) (App _ f a) = App EmptyFC <$> erase rs k f <*> argumentKey fc owner (roleAt k rs) a
      erase rs _ h = pure h

  ||| What a key holds of an argument at a position of a role: a type with
  ||| its indices erased, a shape's form, or nothing. A shape with no form
  ||| makes no key (`spineOf`).
  argumentKey : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                {vars : _} -> FC -> String -> Role -> TT vars -> Front (TT vars)
  argumentKey fc owner Keyed a = unmarked <$> eraseIndices fc owner a
  argumentKey fc owner Formed a = formOf <$> spineOf fc owner a
  argumentKey fc owner Held _ = pure (Erased EmptyFC Placeholder)
  argumentKey fc owner Index _ = pure (Erased EmptyFC Placeholder)

||| A constructor's name within its data type, the symbol of its `idr.ctor`:
||| a data type's constructors share its namespace, so the name without it
||| is unique there. The full name is its location.
export
shortName : Name -> String
shortName (NS _ n) = shortName n
shortName n = show n

||| A constructor's identity in a family instance: its tag as a position
||| among the constructors of the type its result is. Nothing when the
||| definition is no constructor, its type's constructors are not known,
||| or its tag is past them.
export
conIdOf : {auto c : Ref Ctxt Defs} -> FamilyId -> Defined -> Front (Maybe ConId)
conIdOf inst con = do
  let DCon tag _ _ = definition con.def
    | _ => pure Nothing
  -- The type as written may hide its binders behind a definition (`a -@ b`
  -- is `(1 _ : a) -> b`), so the type constructor is read off its normal
  -- form, as `constructor` reads the layout.
  Just tn <- built <$> normaliseClosed con.type
    | Nothing => pure Nothing
  Just tc <- defined tn
    | Nothing => pure Nothing
  let TCon _ _ _ _ _ (Just cons) _ = definition tc.def
    | _ => pure Nothing
  pure (MkConId inst <$> integerToFin (cast tag) (length cons))
  where
    -- The type constructor a constructor's type ends in, under its binders.
    built : TT vs -> Maybe Name
    built (Bind _ _ (Pi {}) sc) = built sc
    built tm = case getFnArgs tm of
      (Ref _ (TyCon _) tn, _) => Just tn
      _ => Nothing

||| Is a value of a type at an instance a member, by the one rule the member
||| table is read by (`Boundary.choiceHolding` and kin)? At an instance's
||| type the instance has given everything it gives, so what the rule
||| leaves undecided there (a head stuck on a runtime value) is no member.
isMember : Holding -> Bool
isMember AMember = True
isMember _ = False

||| Is a type the type of implementations, whatever binds a value of it
||| (`Boundary.implementationHolding`)?
export
implementationType : TT vars -> Front Bool
implementationType ty = (\r => isMember (implementationHolding r.frozen r.interfaces ty)) <$> reading

||| Is a type the type of a polymorphic function, one that takes a type or
||| an implementation before what it gives
||| (`Boundary.polymorphicHolding`)?
export
polymorphicType : TT vars -> Front Bool
polymorphicType ty = (\r => isMember (polymorphicHolding r.frozen r.interfaces ty)) <$> reading

||| Is a value of this type (normalised), held at run time, a value of the
||| type's choice (`choiceFamily`, `Boundary.choiceHolding`): a
||| polymorphic function, or an implementation?
export
choiceType : TT vars -> Front Bool
choiceType ty = (\r => isMember (choiceHolding r.frozen r.interfaces ty)) <$> reading

||| Is a value at a place a member of its type's choice: as the member
||| table says (`MemberPlaces`), and where the instance decides, as the
||| instance's type there (`ty`, normalised) does.
export
holds : Holding -> (ty : ClosedTerm) -> Front Bool
holds AMember _ = pure True
holds NoMember _ = pure False
holds ByInstance ty = choiceType ty

||| Does a binder of this quantity and (normalised) type bind a value the
||| program fixes at compile time wherever it fixes one: an implementation
||| (`implementationType`), or a polymorphic function (`polymorphicType`)?
||| The same answer classifies a function's parameters (`classify`) and
||| what an applied lambda binds (`Terms.applyHead`), so that what a call
||| passes as a compile-time value, a lambda binds as one.
export
compileTimeBinder : RigCount -> TT vars -> Front Bool
compileTimeBinder rig ty = case use rig of
  Erased => pure False
  Used _ => do
    False <- implementationType ty
      | True => pure True
    polymorphicType ty

||| A choice registered by what it is a choice of, once, with no
||| constructor yet: a choice no value is ever made of is uninhabited.
registeredChoice : {auto s : Ref TState TS} -> ChoiceKey -> InstanceKey -> ClosedTerm -> Loc -> Front Choice
registeredChoice k key ty loc = do
  st <- getState
  case lookupFact (.choiceIds) k st >>= \fam => lookupFact (.choices) fam st of
    Just choice => pure choice
    Nothing => do
      let fam = MkFamilyId st.derived.facts.nextFamily
      let choice = MkChoice fam ty [<]
      updateState (derive { choiceIds $= insert k fam, nextFamily $= S
                          , choices $= insert fam choice
                          , families $= insert fam (MkFamily fam key None [] [] loc)
                          , familyOrder $= (:< fam) })
      pure choice

||| A function type with every binder explicit: which binders Idris fills
||| in at an application is the source's business, and the functions one
||| type holds are applied alike whatever its binders say.
explicitBinders : TT vs -> TT vs
explicitBinders (Bind fc x (Pi pfc rig _ a) sc) = Bind fc x (Pi pfc rig Explicit a) (explicitBinders sc)
explicitBinders tm = tm

||| The choice of a type (`choiceType`): the closed sum of the
||| implementations of an interface type, or of the polymorphic functions
||| of a function type, that the program fixes as runtime values
||| (`Choice`), one constructor each, which the translation adds as it
||| finds them (`Choices.memberBare`). An interface's is keyed as a family
||| of the type constructor at its arguments would be, each argument
||| whole; a function type's by the type itself, its binders explicit. It
||| is not the interface's record: which implementation or function a
||| value is, not its methods, is what a dispatch on it reads.
export
choiceFamily : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               FC -> String -> ClosedTerm -> Front Choice
choiceFamily fc owner ty@(Bind {}) = do
  let canonical = explicitBinders ty
  (written, key) <- functionKey canonical
  registeredChoice (OfFunction written) key canonical !(toLoc fc)
choiceFamily fc owner ty = do
  -- Every type given here is one `choiceType` answered a member's, whose
  -- head is an interface's type constructor, and the answer is a `Bool`.
  let (Ref _ _ n, args) = getFnArgs ty
    | _ => internal fc ("a choice of no implementation type: " ++ !(showTT ty))
  iface <- lookupDef fc owner n
  keyed <- traverse (\a => Just <$> argumentKey fc owner Keyed !(canonicalTypeArg a)) args
  (_, found) <- instanceKey fc owner (fullname iface.def) id keyed
  registeredChoice (OfInterface found.link) found.key ty !(toLoc (location iface.def))

||| A value array of these dimensions of this element: an array of value
||| arrays is one, the element's dimensions after these. An array of
||| records is a tensor of the record, whatever the record holds: the
||| dialect splits it into one tensor per field.
valueArrayOf : List Dim -> Ty -> Ty
valueArrayOf ds (TensorT cs el) = TensorT (ds ++ cs) el
valueArrayOf ds e = TensorT ds e

||| The registrations in progress: the bounds the growth check gave
||| (`TS.sizes`, which nothing changes while the translation runs), and the
||| links of the data instances being registered, each with the identity
||| minted for it before its constructors were read, the innermost first.
record Registering where
  constructor MkRegistering
  sizes : Bounds
  links : List (Link Form, FamilyId)

-- The links of a chain, without the identities minted for them.
linksOf : List (Link Form, FamilyId) -> List (Link Form)
linksOf [] = []
linksOf ((l, _) :: ls) = l :: linksOf ls

||| Why registering ends: each data instance registered extends the chain
||| by its link, new to it and within the bounds, and the universe of links
||| within the bounds is finite (`Requests.Universe`), so each extension
||| leaves less room in it (`Finite.extensionsEnd`). A link is its own key.
0 Descending : Registering -> Type
Descending reg = Accessible (Extends (Universe forms addresses reg.sizes) id) (linksOf reg.links)

-- No link is on the empty chain.
0 offEmpty : Not (Elem l (linksOf []))
offEmpty Here impossible
offEmpty (There _) impossible

-- Whether a link is on the chain: the identity minted for it there, or
-- that it is not on it.
data OnChain : Link Form -> List (Link Form, FamilyId) -> Type where
  Minted : FamilyId -> OnChain l ls
  Fresh : (0 _ : Not (Elem l (linksOf ls))) -> OnChain l ls

onChain : (l : Link Form) -> (ls : List (Link Form, FamilyId)) -> OnChain l ls
onChain l [] = Fresh offEmpty
onChain l ((k, fam) :: ks) = case elemLink l [k] of
  Yes _ => Minted fam
  No notK => case onChain l ks of
    Minted f => Minted f
    Fresh ne => Fresh (neitherHereNorThere (\eq => notK (replace {p = \x => Elem l [x]} eq Here)) ne)

-- A chain of links keyed by themselves is itself.
0 keyedBySelf : (ls : List (Link Form)) -> map Prelude.Basics.id ls = ls
keyedBySelf [] = Refl
keyedBySelf (l :: ls) = cong (l ::) (keyedBySelf ls)

-- The empty chain descends.
0 started : (b : Bounds) -> Descending (MkRegistering b [])
started b = extensionsEnd (Universe forms addresses b) id [] [] [] (wellFounded _)

||| The growth check's bound on each argument a data instance is keyed by,
||| at its type constructor's node (`MkNode t []`), checked where the
||| instance is registered, on the arguments as the key holds them (its
||| `statics`, read as an instance's are, nothing where it holds none). A
||| position given no bound, or an argument above its bound, is a flow the
||| check missed: the compiler's error, never the program's.
boundsHold : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> String -> Address -> (statics : List (Maybe StaticReading)) -> Front ()
boundsHold fc what t statics = do
  st <- getState
  for_ (mapMaybe (\(j, a) => (j,) <$> a) (zip (iterateN (length statics) S 0) statics)) $ \(j, r) =>
    heightWithin fc what st.bounds (MkNode t [], j) r.height

||| What is known of an erased index, from its normal form: a constructor
||| binder's stand-in (`marker`) is that binder's level; a chain of
||| successors of `Nat` (Idris's `ZERO` and `SUCC` flags, never names) over
||| zero or a stand-in is a number or a level plus one per successor; a
||| non-negative integer literal is a number; anything else is outside the
||| language, refining nothing. Read once, where a type is read, and where
||| a call gives an index parameter its argument.
export
indexTerm : ClosedTerm -> Front ITerm
indexTerm = go 0
  where
    roleOf : ClosedTerm -> Front (Maybe NatRole)
    roleOf tm = case getFn tm of
      Ref _ (DataCon _ _) n => do
        found <- defined n
        pure (found >>= \con => natRole con.def)
      _ => pure Nothing
    go : Nat -> ClosedTerm -> Front ITerm
    go k tm = case binderOf tm of
      Just level => pure (succ (IVar level) k)
      Nothing => case tm of
        App _ _ pred => case !(roleOf tm) of
          Just Zero => pure (INat k)
          Just Succ => go (S k) pred
          Nothing => pure IOpaque
        Ref _ (DataCon _ _) _ => case !(roleOf tm) of
          Just Zero => pure (INat k)
          _ => pure IOpaque
        PrimVal _ c => case constantLit c of
          Just (LBig i) => pure (if i >= 0 then INat (k + integerToNat i) else IOpaque)
          _ => pure IOpaque
        _ => pure IOpaque

||| Where an erased binder occurs in the rest of a function's type, given
||| as the binder's stand-in (`marker k`): nowhere a value is passed (in no
||| runtime binder's type, nor in the result), only as an index of an
||| inductive family there, or somewhere a representation would depend on
||| it. Only the second makes the binder an index parameter: one only a
||| proof reads is no binder, and one a representation reads is no index.
public export
data Occurrence = Unpassed | IndexOnly | Represented

export
occurrenceOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               String -> (k : Nat) -> (rest : ClosedTerm) -> Front Occurrence
occurrenceOf owner k rest = do
  represented <- outsideIndices (mentionsMarker k) owner rest
  pure (if represented then Represented else if passed rest then IndexOnly else Unpassed)
  where
    passed : TT vs -> Bool
    passed (Bind _ _ (Pi _ rig _ a) sc) = (case use rig of
                                             Erased => False
                                             Used _ => mentionsMarker k a) || passed sc
    passed t = mentionsMarker k t

||| The sort of an erased binder or index, from its type's normal form: a
||| natural for Idris's `Nat` (a chain), a type for a universe, outside the
||| language for anything else.
export
sortOfType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> ClosedTerm -> Front Sort
sortOfType (TType _ _) = pure SType
sortOfType tm = case getFn tm of
  Ref _ (TyCon _) n => do
    Just tc <- defined n
      | Nothing => pure SOpaque
    case (!(tyConFacts tc)).natness of
      Chain => pure SNat
      _ => pure SOpaque
  _ => pure SOpaque

||| The levels a term or a type names, each once.
mutual
  levelsOfTerm : ITerm -> List Nat
  levelsOfTerm (IVar k) = [k]
  levelsOfTerm (ISucc t _) = levelsOfTerm t
  levelsOfTerm (ICon _ _ as) = levelsOfTerms as
  levelsOfTerm (IType t) = levelsOfTy t
  levelsOfTerm _ = []

  levelsOfTerms : List ITerm -> List Nat
  levelsOfTerms [] = []
  levelsOfTerms (t :: ts) = levelsOfTerm t ++ levelsOfTerms ts

  levelsOfTy : Ty -> List Nat
  levelsOfTy (DataT _ ts) = levelsOfTerms ts
  levelsOfTy (NatT t) = levelsOfTerm t
  levelsOfTy (FunT (MkBinder _ a) r) = levelsOfTy a ++ levelsOfTy r
  levelsOfTy (LazyT a) = levelsOfTy a
  levelsOfTy (TensorT _ a) = levelsOfTy a
  levelsOfTy (MemRefT _ a) = levelsOfTy a
  levelsOfTy _ = []

||| A term or a type with its levels renamed by `f`: a level `f` drops is
||| outside the language there.
mutual
  relevelTerm : (Nat -> Maybe Nat) -> ITerm -> ITerm
  relevelTerm f (IVar k) = maybe IOpaque IVar (f k)
  relevelTerm f (ISucc t k) = succ (relevelTerm f t) k
  relevelTerm f (ICon g c as) = ICon g c (relevelTerms f as)
  relevelTerm f (IType t) = IType (relevelTy f t)
  relevelTerm f t = t

  relevelTerms : (Nat -> Maybe Nat) -> List ITerm -> List ITerm
  relevelTerms f [] = []
  relevelTerms f (t :: ts) = relevelTerm f t :: relevelTerms f ts

  export
  relevelTy : (Nat -> Maybe Nat) -> Ty -> Ty
  relevelTy f (DataT g ts) = DataT g (relevelTerms f ts)
  relevelTy f (NatT t) = NatT (relevelTerm f t)
  relevelTy f (FunT (MkBinder q a) r) = FunT (MkBinder q (relevelTy f a)) (relevelTy f r)
  relevelTy f (LazyT a) = LazyT (relevelTy f a)
  relevelTy f (TensorT ds a) = TensorT ds (relevelTy f a)
  relevelTy f (MemRefT o a) = MemRefT o (relevelTy f a)
  relevelTy f t = t

||| A constructor's argument as its layout holds it: a field's type with the
||| constructor's levels outside the language, since a field read in a body
||| is at the scope's levels, which the match gives it.
unlinked : ArgKind -> ArgKind
unlinked (Param v) = Param v
unlinked ErasedArg = ErasedArg
unlinked (Field i b t) = Field i ({ type $= relevelTy (const Nothing) } b) t

-- The layout's arguments have as many fields as the walk's.
0 unlinkedCount : (as : List ArgKind) -> fieldCount (map unlinked as) = fieldCount as
unlinkedCount [] = Refl
unlinkedCount (Param _ :: as) = unlinkedCount as
unlinkedCount (ErasedArg :: as) = unlinkedCount as
unlinkedCount (Field _ _ _ :: as) = cong S (unlinkedCount as)

||| What the walk of a constructor's type finds: its arguments' kinds, the
||| position and type of each of its quantity-0 arguments in order (its
||| candidate binders, each given its stand-in where it is bound), and the
||| type it returns, under those stand-ins.
record Walked where
  constructor MkWalked
  kinds : List ArgKind
  erasedTypes : List (Nat, ClosedTerm)
  returns : ClosedTerm

mutual
  ||| The Core type of a type, read under binders whose values are given,
  ||| in the registration of the families on `chain`. The type is normalised
  ||| (`coreType` normalises it once), so every part of it is too, and the
  ||| reading is structural. A type that has no runtime representation is
  ||| reported under `rule`: `ValueType`, or `DependentField` for a
  ||| constructor field. An argument of quantity 0 is no argument at
  ||| runtime, so a function type that takes one is the type of its result.
  coreTypeIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               (chain : Registering) -> (0 _ : Descending chain) ->
               {cat : Category} -> Given vars -> FC -> String -> Rule cat -> TT vars -> Front Ty
  coreTypeIn chain acc g fc owner rule (PrimVal _ (PrT t)) = pure (prim (primTy t))
    where
      prim : PrimTy -> Ty
      prim (IntP it) = IntT it
      prim IntegerP = BigT
      prim StringP = StrT
      prim CharP = CharT
      prim DoubleP = DoubleT
      prim WorldP = WorldT
  coreTypeIn chain acc g fc owner rule tm@(Bind bfc x (Pi _ rig _ a) sc) = do
    -- A polymorphic function in a runtime position is a value of its
    -- type's choice: which of the functions the program puts there it is.
    False <- polymorphicType tm
      | True => do
          choice <- choiceFamily fc owner !(normaliseClosed (close g tm))
          pure (DataT choice.family [])
    let g' = give (Erased bfc Placeholder) g
    case use rig of
      Erased => coreTypeIn chain acc g' fc owner rule sc
      Used q => do
        arg <- coreBinderIn chain acc g fc owner rule q a
        when !(erasedOutsideIndices owner (close g' sc)) $
          reject fc owner rule "a function type that depends on its argument"
        rt <- coreTypeIn chain acc g' fc owner rule sc
        -- A closure's type is one for every extent its values are made at.
        pure (FunT ({ type $= dynamicDims } arg) (dynamicDims rt))
  -- `Inf` is a suspension like `Lazy`.
  coreTypeIn chain acc g fc owner rule (TDelayed _ _ t) =
    LazyT . dynamicDims <$> coreTypeIn chain acc g fc owner rule t
  -- An implementation in a runtime position is a value of its type's
  -- choice: which of the implementations the program fixes it is.
  coreTypeIn chain acc g fc owner rule tm = do
    True <- implementationType tm
      | False => dataTypeIn chain acc g fc owner rule tm
    choice <- choiceFamily fc owner !(normaliseClosed (close g tm))
    pure (DataT choice.family [])

  ||| A type that is no implementation's, by its head.
  dataTypeIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               (chain : Registering) -> (0 _ : Descending chain) ->
               {cat : Category} -> Given vars -> FC -> String -> Rule cat -> TT vars -> Front Ty
  dataTypeIn chain acc g fc owner rule tm = case getFnArgs tm of
    (Ref rfc (TyCon _) n, args) => do
      tc <- lookupDef fc owner n
      -- A word type is a machine word whatever its arguments: what a
      -- `Ptr t` points to names what its handle holds, not its
      -- representation.
      let hs = namedHooks tc.registered
      -- Idris's `Nat`, a chain of successors, is a natural. A family of
      -- the same shape whose constructors take an erased index (`Fin`,
      -- `Elem`) is a family: the dialect lays it out as a number.
      case (!(tyConFacts tc)).natness of
       Chain => pure (NatT IOpaque)
       _ => if hs.wordType
         then pure (IntT UInt64)
         else case hs.orderedArray of
           Just (o, Just e) => pure (MemRefT o e)
           Just (o, Nothing) => case tm of
             App _ (Ref _ _ _) a => do
               e <- coreTypeIn chain acc g fc owner rule a
               case e of
                 TensorT _ _ => reject fc owner rule ("an array a world orders holding an array value: " ++ !(showTT (close g tm)))
                 _ => pure (MemRefT o e)
             _ => reject fc owner HookShape ("the registry's ordered array type " ++ show (fullname tc.def) ++ ", without its one element type")
           Nothing =>
             if hs.valueArray
               then case tm of
                 App _ (App _ (Ref _ _ _) shape) a => do
                   ds <- shapeDims fc owner (close g shape)
                   e <- coreTypeIn chain acc g fc owner rule a
                   case e of
                     MemRefT _ _ => reject fc owner rule ("an array value holding an array a world orders: " ++ !(showTT (close g tm)))
                     _ => pure (valueArrayOf ds e)
                 _ => reject fc owner HookShape ("the registry's value array type " ++ show (fullname tc.def) ++ ", without its shape and element")
               else snd <$> familyIn chain acc fc owner n !(traverse (normaliseClosed . close g) args)
    (TType _ _, _) => reject fc owner rule "Type in a runtime position"
    (Erased _ _, _) => reject fc owner rule "a type that depends on a runtime or erased value"
    -- A binder of the type read so far stands for a value of quantity 0 or
    -- a runtime one, as an erased part does.
    (Local {}, _) => reject fc owner rule "a type that depends on a runtime or erased value"
    _ => do reject fc owner rule ("unsupported runtime type " ++ !(showTT (close g tm)))

  ||| Registers a family instance, once, and gives the type of a value of
  ||| it at the index terms its arguments give. A family is the type
  ||| constructor at the arguments its key holds; its indices are the
  ||| positions the key does not hold, each read into an index term
  ||| (`indexTerm`). Its identity is minted before its constructors are
  ||| read, so a field of the family itself finds it: a recursive family
  ||| names itself. Registering descends on the room the chain leaves among
  ||| the links within the growth check's bounds (`Descending`): a new
  ||| instance is checked against those bounds and pushed. A data type
  ||| whose fields need ever larger instances of itself (`data T a = L a |
  ||| N (T (a, a))`) is refused before translation, by the growth phase.
  familyIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (chain : Registering) -> (0 _ : Descending chain) ->
             FC -> String -> Name -> List ClosedTerm -> Front (FamilyId, Ty)
  familyIn chain (Access rec) fc owner tcon args0 = do
    tc <- lookupDef fc owner tcon
    let def = tc.def
    let tname = show (fullname def)
    facts <- tyConFacts tc
    let params = facts.params
    let roles = facts.roles
    let positions = [0 .. length args0]
    args <- traverse (\(i, a) => let r = roleAt i roles in
                                 if inKey r then argumentKey fc owner r !(canonicalTypeArg a)
                                            else pure (Erased EmptyFC Placeholder))
                     (zip positions args0)
    -- Each argument the key holds is read once, as an instance's static
    -- argument is (`Template.staticReading`), and the link writes its
    -- reading's form: the form the growth check's sites read.
    statics <- traverse (\(i, a) => if inKey (roleAt i roles) then Just <$> staticReading AType a else pure Nothing)
                        (zip positions args)
    indices <- traverse indexTerm (map snd (filter (\(i, _) => not (inKey (roleAt i roles))) (zip positions args0)))
    (address, found) <- instanceKey fc owner (fullname def) (.form) statics
    st <- getState
    case lookupFact (.familyIds) found.link st of
      Just fam => pure (fam, DataT fam indices)
      Nothing => case onChain found.link chain.links of
        -- A link on the chain had its identity minted before its
        -- constructors were read, which the chain keeps with it.
        Minted fam => pure (fam, DataT fam indices)
        Fresh fresh => do
          let fam = MkFamilyId st.derived.facts.nextFamily
          updateState (derive { familyIds $= insert found.link fam, nextFamily $= S })
          let what = keyText found.key ++ ", registered,"
          boundsHold fc what address statics
          inside <- sizedWithin fc what chain.sizes found.link
          TCon arity _ _ _ _ datacons _ <- pure (definition def)
            | _ => reject fc owner ValueType (tname ++ " is not a data type")
          let Just datacons = datacons
            | Nothing => reject fc owner DataType (tname ++ " has no known constructors")
          loc <- toLoc (location def)
          sorts <- indexSorts tc (filter (\i => not (inKey (roleAt i roles))) (take arity [0 .. arity]))
          conList <- traverse (constructor (MkRegistering chain.sizes ((found.link, fam) :: chain.links))
                                           (rec (found.link :: linksOf chain.links)
                                                (Extend (\e => fresh (replace {p = Elem found.link} (keyedBySelf (linksOf chain.links)) e))
                                                        inside.member))
                                           fc owner fam found.link args params roles)
                              datacons
          let sorted = sortBy (\(a, _), (b, _) => compare (snd a).tag (snd b).tag) conList
          let cons = map fst sorted
          promise <- promised tname (namedHooks tc.registered).sumShape cons
          updateState (derive { families $= insert fam (MkFamily fam found.key promise sorts cons loc)
                              , familyOrder $= (:< fam) })
          pure (fam, DataT fam indices)
    where
      -- What the registry promises of the family's values, where its entry
      -- meets the family's constructors: a promise to rebuild them in
      -- place is kept only by a family with exactly one constructor that
      -- holds fields, the one whose cell each rebuild takes; any other
      -- family the entry names is the entry's mismatch, refused here, so
      -- no family holds a promise it cannot keep.
      promised : String -> Maybe SumHook -> List (k ** Con k) -> Front Promise
      promised tname (Just IsInPlace) cons = case filter (\(k ** _) => k > 0) cons of
        [_] => pure InPlace
        cells => reject fc owner HookShape
                   (tname ++ ": the registry's entry promises that its values are rebuilt in place, which only " ++
                    "a type with exactly one constructor that holds fields keeps, and it has " ++ show (length cells))
      promised _ _ _ = pure None

      -- The sorts of a type constructor's index positions, from its type.
      indexSorts : Defined -> List Nat -> Front (List Sort)
      indexSorts d ps = go none 0 !(normaliseClosed d.type)
        where
          go : Given vs -> Nat -> TT vs -> Front (List Sort)
          go g i (Bind bfc _ (Pi _ _ _ a) sc) = do
            rest <- go (give (Erased bfc Placeholder) g) (S i) sc
            if elem i ps then (:: rest) <$> sortOfType !(normaliseClosed (close g a)) else pure rest
          go g i _ = pure []

  ||| A constructor of a family being registered, with its arguments'
  ||| kinds, registered too: its erased binders (the quantity-0 arguments an
  ||| index of its result or a field's type names, renumbered as levels of
  ||| its own scope in order), its equation (the index terms its result
  ||| type gives) and its fields. The translation holds a field's type with
  ||| the constructor's levels outside the language, since a field read in
  ||| a body is at the scope's levels, which the match gives it.
  constructor : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                (chain : Registering) -> (0 _ : Descending chain) ->
                FC -> String -> FamilyId -> Link Form -> List ClosedTerm -> List Nat -> List Role -> Name ->
                Front ((k ** Con k), List ArgKind)
  constructor chain acc fc owner fam link targs ps roles dcon = do
    dc <- lookupDef fc owner dcon
    let def = dc.def
    let cname = show (fullname def)
    DCon _ arity _ <- pure (definition def)
      | _ => reject fc owner CompiledModule (cname ++ " is not a constructor")
    Just cid <- conIdOf fam dc
      | Nothing => reject fc owner CompiledModule (cname ++ " is not a constructor")
    loc <- toLoc (location def)
    -- The type as written may hide its binders behind a definition
    -- (`a -@ b` is `(1 _ : a) -> b`); its normal form shows each one,
    -- with the quantity that makes a field linear.
    ty <- normaliseClosed dc.type
    let layout = paramLayout def ps roles ty
    -- Every match binds `arity` arguments: a layout of another length
    -- would misplace every field after the first difference. Idris gives
    -- a constructor the arity its type binds, in the module the compiler
    -- reads when it runs.
    when (length layout /= arity) $
      reject (location def) owner CompiledModule (cname ++ " has " ++ show arity ++ " arguments, but its type binds " ++
                                                   show (length layout))
    walked <- walk chain acc def cname (location def) targs 0 0 0 layout none ty
    -- The result's index terms, at the family's index positions.
    let resultArgs = snd (getFnArgs walked.returns)
    equation0 <- traverse indexTerm
                   (map snd (filter (\(i, _) => not (inKey (roleAt i roles))) (zip [0 .. length resultArgs] resultArgs)))
    let fields0 = fieldsOf walked.kinds
    -- A binder no index and no field names is an erased proof: it does
    -- not exist.
    let used = nub (levelsOfTerms equation0 ++ concatMap (levelsOfTy . (.type)) (toList fields0))
        kept = filter (\k => elem k used) (take (length walked.erasedTypes) [0 .. length walked.erasedTypes])
        renumber = \k => findIndex' k kept
    binders <- traverse (\(at, t) => (\sort => MkConBinder sort at) <$> sortOfType !(normaliseClosed t))
                        (map snd (filter (\(k, _) => elem k kept) (zip [0 .. length walked.erasedTypes] walked.erasedTypes)))
    let fields = map (\b => { type $= relevelTy renumber } b) fields0
        equation = relevelTerms renumber equation0
        unlinkedKinds = map unlinked walked.kinds
        con = MkCon cid (shortName (fullname def)) binders equation
                    (replace {p = \n => Vect n Binder} (sym (unlinkedCount walked.kinds)) fields) loc
    updateState (derive { cons $= insert cid (MkConLayout unlinkedKinds (fullname def) con) })
    pure ((fieldCount unlinkedKinds ** con), unlinkedKinds)
    where
      findIndex' : Nat -> List Nat -> Maybe Nat
      findIndex' k ks = finToNat <$> findIndex (== k) ks

  ||| The constructor's arguments, read under the binders passed, each
  ||| given its value: a parameter is the instance's, one of quantity 0 is
  ||| no field and is given its stand-in, the next level of the
  ||| constructor's own scope, anything else is the next field, an
  ||| implementation among them a choice (`choiceFamily`).
  walk : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         (chain : Registering) -> (0 _ : Descending chain) -> (con : GlobalDef) ->
         String -> FC -> List ClosedTerm -> (at, i, e : Nat) -> List (Maybe Nat) ->
         Given vs -> TT vs -> Front Walked
  walk chain acc con cname dfc targs at i e (Just p :: ls) g (Bind bfc _ (Pi {}) sc) = do
    let v = fromMaybe (Erased bfc Placeholder) (getAt p targs)
    w <- walk chain acc con cname dfc targs (S at) i e ls (give v g) sc
    pure ({ kinds $= (Param v ::) } w)
  walk chain acc con cname dfc targs at i e (Nothing :: ls) g (Bind bfc _ (Pi _ rig _ a) sc) =
    case argumentAt con at rig of
      RuntimeValue q => do
        let g' = give (Erased bfc Placeholder) g
        a' <- normaliseClosed (close g a)
        when !(erasedOutsideIndices cname a') $ do
          reject dfc cname DependentField ("a field type that depends on another field: " ++ !(showTT a'))
        b <- coreBinderIn chain acc none dfc cname DependentField q a'
        w <- walk chain acc con cname dfc targs (S at) (S i) e ls g' sc
        pure ({ kinds $= (Field i b a' ::) } w)
      _ => do
        w <- walk chain acc con cname dfc targs (S at) i (S e) ls (give (marker e) g) sc
        pure ({ kinds $= (ErasedArg ::), erasedTypes $= ((at, close g a) ::) } w)
  walk _ _ _ _ _ _ _ _ _ _ g t = pure (MkWalked [] [] (close g t))

  ||| The family a type names, when it is a data type and not a natural, a
  ||| machine word or an array of either kind: the family, and the type of
  ||| its values at the type's index terms.
  dataOfIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (chain : Registering) -> (0 _ : Descending chain) ->
             Given vars -> FC -> String -> TT vars -> Front (Maybe (FamilyId, Ty))
  dataOfIn chain acc g fc owner tm = case getFnArgs tm of
    (Ref _ (TyCon _) n, args) => do
      tc <- lookupDef fc owner n
      let hs = namedHooks tc.registered
      case (!(tyConFacts tc)).natness of
        Chain => pure Nothing
        _ => if hs.wordType || isJust hs.orderedArray || hs.valueArray then pure Nothing else do
               args' <- traverse (normaliseClosed . close g) args
               Just <$> familyIn chain acc fc owner n args'
    _ => pure Nothing

  ||| The binder of a position of this type at this quantity: the Core type
  ||| at the quantity Idris gave the position.
  coreBinderIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                 (chain : Registering) -> (0 _ : Descending chain) ->
                 {cat : Category} -> Given vars -> FC -> String -> Rule cat -> Uses -> TT vars -> Front Binder
  coreBinderIn chain acc g fc owner rule q tm = MkBinder q <$> coreTypeIn chain acc g fc owner rule tm

||| Reads a type from the start of a registration: its normal form, under
||| no binder, with no family being registered.
outermost : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            ((chain : Registering) -> (0 _ : Descending chain) ->
             Given Scope.empty -> ClosedTerm -> Front a) -> ClosedTerm -> Front a
outermost read tm = do
  b <- (.sizes) <$> getState
  read (MkRegistering b []) (started b) none !(normaliseClosed tm)

||| The Core type of a closed type. A type that has no runtime
||| representation is reported under `rule`: `ValueType`, or
||| `DependentField` for a constructor field.
export
coreType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           {cat : Category} -> FC -> String -> Rule cat -> ClosedTerm -> Front Ty
coreType fc owner rule = outermost (\chain, acc, g => coreTypeIn chain acc g fc owner rule)

||| The family a closed type names, when it is a data type and not a
||| natural, a machine word or an array of either kind (`dataOfIn`).
export
dataOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         FC -> String -> ClosedTerm -> Front (Maybe (FamilyId, Ty))
dataOf fc owner = outermost (\chain, acc, g => dataOfIn chain acc g fc owner)

||| The binder of a position of a closed type at the quantity its value is
||| used at (`coreBinderIn`). A position of quantity 0 binds no runtime
||| value, and has no use to give.
export
coreBinder : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             {cat : Category} -> FC -> String -> Rule cat -> Uses -> ClosedTerm -> Front Binder
coreBinder fc owner rule q tm = outermost (\chain, acc, g => coreBinderIn chain acc g fc owner rule q) tm
