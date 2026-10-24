-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Implementations and polymorphic functions chosen at run time among
||| those the program fixes.
|||
||| An implementation, or a polymorphic function, is a compile-time value
||| wherever the program fixes one: it keys the instance of what it is given
||| to, and is no value at run time (`Instances`). Where a run-time value
||| decides which one it is (`op @{choose k}`, a map built with one of two
||| orderings, a field of a constructor holding whichever implementation or
||| function its construction site gave), the ones it can be are still a set
||| the program fixes: those written where a value of that type is made. So
||| such a value is a value of a closed sum, its type's choice
||| (`Types.choiceFamily`), one constructor per implementation or function,
||| each carrying what it closes over (`Holes`), the choices its own
||| constraints made among them. It is a sum of which one, never a record of
||| methods or a polymorphic closure: a use needs no polymorphic value,
||| since every use fixes its own types.
|||
||| An instance given an implementation the program fixes, one of whose
||| fields the running program chose, holds that field as a value; the
||| instance is a dispatch on it (`heldDispatch`), each arm the instance
||| with the field fixed to the member, so that a tree takes apart only
||| what the program fixes.
|||
||| A value of a polymorphic function's choice applied where it is held is
||| a use of it, a member at a use (`AtUse`): the choice is passed to the
||| application as by `\f, x1 .. xn => f x1 .. xn` at its type, so the
||| use is a call given a choice, whose every arm calls the member at the
||| use's own types.
|||
||| A call given a choice is a dispatch: one function, a match on the
||| choice whose arm for each member calls the callee's instance at that
||| member, the member's field passed where the choice was. A member and a
||| dispatch are joined as soon as both exist, whichever comes first, so
||| every arm is requested as an instance of the program within the
||| translation that found the second; the dispatch is written once the
||| translation has found every member (`dispatchers`). A choice whose set
||| no analysis bounds is no choice: the growth check refuses the
||| recursion that would build it, before the translation.
module IdrisMLIR.Frontend.Translate.Choices

import Core.Context
import Core.Core
import Core.TT

import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Instances
import IdrisMLIR.Frontend.Translate.Keys
import IdrisMLIR.Frontend.Translate.Readings
import IdrisMLIR.Frontend.Translate.Shapes
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Ids
import IdrisMLIR.Loc
import IdrisMLIR.Spec.Core.Rules
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
import Decidable.Equality

%default total

-- Every do block here binds in `Front`, never in `Core`: Core's own bind,
-- beside the interface's, would make each bind an ambiguity, elaborated
-- once per candidate with all of the block after it inside.
%hide Core.Core.(>>=)
%hide Core.Core.(>>)

------------------------------------------------------------------------------
-- Members
------------------------------------------------------------------------------

%prefix_record_projections off

||| The one constructor of a data family, with each of its fields' Idris
||| type at the family's instance, in order (`ArgKind`), which a reader of
||| a value of it reads a field's own family off (`Types.dataFamilyOf`).
public export
record Only (k : Nat) where
  constructor MkOnly
  single : Con k
  fieldTypes : Vect k ClosedTerm

%prefix_record_projections on

||| The Idris types of a constructor's runtime fields at its family's
||| instance, in order, one per field.
fieldTypesOf : (as : List ArgKind) -> Vect (fieldCount as) ClosedTerm
fieldTypesOf [] = []
fieldTypesOf (Param _ :: as) = fieldTypesOf as
fieldTypesOf (ErasedArg :: as) = fieldTypesOf as
fieldTypesOf (Field _ _ t :: as) = t :: fieldTypesOf as

||| The one constructor of a data family (`Res`, `IORes`, a pair, the
||| unit), of `k` fields, read off the family its reader holds, so no
||| family is looked up by its identity. Each is a declaration of Idris's
||| or of a trusted library's, whose shape the declaration states and its
||| family's identity does not carry; a hook, or the frontend's packing, is
||| where the frontend first reads it at that shape, so one of another
||| shape is refused there, by its reader's refusal (`refused`).
export
onlyCon : (k : Nat) -> (refused : String -> Front (Only k)) -> DataFamily -> Front (Only k)
onlyCon k refused df = do
  let [layout] = toList df.layouts
    | _ => refused ("a value of " ++ keyText df.key ++ ", which has not one constructor")
  let Yes same = decEq (fieldCount layout.args) k
    | No _ => refused ("a value of " ++ keyText df.key ++ ", whose constructor has " ++ show (fieldCount layout.args) ++
                       " fields, not " ++ show k)
  pure (MkOnly (replace {p = Con} same layout.con)
               (replace {p = \n => Vect n ClosedTerm} same (fieldTypesOf layout.args)))

||| The pair that holds values of these types as one (`packedType`), the
||| first and the rest.
pairOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         FC -> String -> ClosedTerm -> List1 ClosedTerm -> Front (Con 2)
pairOf fc owner t rest = do
  -- The pair Idris's `%pair` names, applied, is a data type's, whose
  -- family `dataFamilyOf` reads from the type, which says nothing of
  -- `packedType`: the packing is where the frontend first reads it, so a
  -- pair of another shape is refused, as the compiled module it is.
  packed <- packedType (t ::: forget rest)
  Just (df, _) <- dataFamilyOf fc owner packed
    | Nothing => do
        written <- showTT packed
        reject fc owner CompiledModule ("values held as one in a value of type " ++ written ++ ", which is no pair")
  (.single) <$> onlyCon 2 (reject fc owner CompiledModule) df

||| The values an implementation closes over as the one value its parameter
||| holds (`packedType`): the value itself, or a pair of the first and the
||| rest.
export
pack : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {0 nv : Nat} ->
       FC -> String -> Loc -> List1 (ClosedTerm, Term nv) -> Front (Term nv)
pack fc owner loc (first ::: rest) = packed first rest
  where
    packed : (ClosedTerm, Term nv) -> List (ClosedTerm, Term nv) -> Front (Term nv)
    packed (_, v) [] = pure v
    packed (t, v) (p :: ps) = do
      pair <- pairOf fc owner t (map fst (p ::: ps))
      pure (ConApp loc pair [] [v, !(packed p ps)])

||| The values one variable holds as one, the first of type `t` and the
||| rest of the types after it (`takenApart`): each pair taken apart into
||| its first value and the variable holding the rest, which is taken apart
||| by the types left, one fewer.
apartFrom : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {0 n : Nat} ->
            FC -> String -> Loc -> (t : ClosedTerm) -> (ts : List ClosedTerm) -> Fin n ->
            ({0 p : Nat} -> (Fin n -> Fin p) -> Vect (S (length ts)) (Fin p) -> Front (Term p)) -> Front (Term n)
apartFrom fc owner loc t [] x k = k id [x]
apartFrom fc owner loc t (u :: us) x k = do
  pair <- pairOf fc owner t (u ::: us)
  body <- apartFrom fc owner loc u us (Bound {k = 2} (FS FZ))
            (\ren, vs => k (ren . Free {k = 2}) (ren (Bound {k = 2} FZ) :: vs))
  pure (Case loc pair.id.family x (Exhaustive (MkAlt pair [shown "value", shown "rest"] body ::: [])))

||| The values one variable holds as one (`pack`), of these types, taken
||| apart by the pairs that hold them: the body built over each value's
||| variable, one per type, in order, with the renaming of the scope
||| outside.
export
takenApart : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {0 n : Nat} ->
             FC -> String -> Loc -> (types : List1 ClosedTerm) -> Fin n ->
             ({0 p : Nat} -> (Fin n -> Fin p) -> Vect (length (forget types)) (Fin p) -> Front (Term p)) -> Front (Term n)
takenApart fc owner loc (t ::: ts) x k = apartFrom fc owner loc t ts x k

||| A list without its element at a place.
without : Nat -> List a -> List a
without Z (_ :: ys) = ys
without (S i) (y :: ys) = y :: without i ys
without _ [] = []

||| What a callee is given at a member: the implementation it is, fixed as
||| it was registered, and the values it closes over when it closes over
||| any.
memberKind : ChoiceMember -> PKind
memberKind m = case m.con of
  Bare _ => DictParam m.dictionary Nothing
  Capturing h _ => DictParam m.dictionary (Just h)

||| The constructor of the member at position `at` of a choice's family,
||| labelled for a reader by the definition its implementation or function
||| is, and its place, which keeps two members of one definition apart; a
||| lambda is labelled by its place alone.
newCon : {auto s : Ref TState TS} -> FC -> FamilyId -> (at : Nat) -> ClosedTerm -> Vect k Binder -> Front (Con k)
newCon fc fam at form fields = do
  loc <- toLoc fc
  label <- case getFn form of
             Ref _ _ n => (\full => shortName full ++ "." ++ show at) <$> fullName n
             _ => pure ("member." ++ show at)
  pure (MkCon (MkConId fam (last {n = at})) label [] [] fields loc)

||| A dispatch's arms with its arm for the member at position `i`, as the
||| step being run derives them: the arms as the step reads them
||| (`lookupFact`), none before the first, with the arm, superseding the
||| table's.
withArm : FnId -> Nat -> DispatchArm -> TS -> TS
withArm inst i arm st =
  derive { dispatchArms $= insert inst (insert i arm (fromMaybe empty (lookupFact (.dispatchArms) inst st))) } st

||| A choice with one more member, its family's next constructor (its
||| family is declared from its members, `choiceDeclared`), as the step
||| being run derives it: as the step reads it (`lookupFact`), changed,
||| superseding the table's.
withMember : FamilyId -> ChoiceMember -> TS -> TS
withMember fam m st = case lookupFact (.choices) fam st of
  Just ch => derive { choices $= insert fam ({ members $= (:< m) } ch) } st
  Nothing => st

%prefix_record_projections off

||| A signature's kinds split at the parameter a dispatch finds its choice
||| in, what that parameter is (`a`), and its position among those that
||| exist at run time, read off the same kinds, so the position is one the
||| signature has.
public export
record ChoiceAt (ks : List PKind) (a : Type) where
  constructor MkChoiceAt
  kindsSplit : SplitKinds (length ks) a
  runtimePlace : Fin (Runtimes ks)

%prefix_record_projections on

||| A parameter found among the kinds after one more kind.
laterChoice : (k : PKind) -> ChoiceAt ks a -> ChoiceAt (k :: ks) a
laterChoice k at = MkChoiceAt (afterKind k at.kindsSplit) (after (boundAtRuntime k) at.runtimePlace)

||| The first choice a signature's parameter takes: its kinds split at that
||| parameter, which holds its binder and the type it is a choice of, and
||| its position at run time.
givenChoice : (ks : List PKind) -> Maybe (ChoiceAt ks (Binder, ChoiceType))
givenChoice [] = Nothing
givenChoice (ChoiceParam b t :: ks) = Just (MkChoiceAt (MkSplitKinds [] (b, t) (Data.Vect.fromList ks) Refl) FZ)
givenChoice (k :: ks) = laterChoice k <$> givenChoice ks

||| How many choices a call's kinds hold.
export
choicesIn : Vect n PKind -> Nat
choicesIn [] = 0
choicesIn (ChoiceParam _ _ :: ks) = S (choicesIn ks)
choicesIn (_ :: ks) = choicesIn ks

||| The values a member of a choice closes over, by type: none for one that
||| closes over none.
ownValues : ChoiceMember -> List ClosedTerm
ownValues m = case m.con of
  Bare _ => []
  Capturing h _ => forget h.types

||| The values an implementation closes over, by type, for one member of
||| the choice it holds at place `j`: the others in order, then the
||| member's own.
heldTypes : (j : Nat) -> List ClosedTerm -> ChoiceMember -> List ClosedTerm
heldTypes j types m = without j types ++ ownValues m

||| A term of an implementation that holds `count` values for one member of
||| the choice it holds at place `j` (`heldTypes`): the member's form in
||| place of the choice's marker, the markers after it each one lower, and
||| the member's own after all of them. The member's markers pass through
||| the frontend's other family of markers on the way, so that none is
||| renamed twice. Every step puts in names no reduction unfolds, so the
||| implementation's form and the value it was fixed at are placed alike
||| (`mapValue`).
heldPlaced : (j : Nat) -> (count : Nat) -> ChoiceMember -> ClosedTerm -> ClosedTerm
heldPlaced j count m t =
  let own = iterateN (length (ownValues m)) S 0
      left = minus count 1
      moved = fillHoles (map found own) m.dictionary.form
      placed = substName (markerName j) moved t
      lowered = foldl (\u, i => substName (markerName (S i)) (holeMarker i) u) placed (drop j (iterateN left S 0))
  in foldl (\u, q => substName (probeName (ProbeHoleFound q)) (holeMarker (left + q)) u) lowered own
  where
    found : Nat -> ClosedTerm
    found q = probeTerm (ProbeHoleFound q)

||| The parameter an instance takes for one member of the choice the
||| implementation it is given (`holder`) holds at place `j`: the
||| implementation with that field fixed, its form and the value it was
||| fixed at placed alike (`heldPlaced`), so it is fixed by construction and
||| nothing reduces it, holding the values left (`heldTypes`), none when
||| none is left.
heldMember : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> String -> (j : Nat) -> (holder : FixedDictionary) -> Holes -> ChoiceMember -> Front PKind
heldMember fc owner j holder hs m = do
  let placing = heldPlaced j (length (forget hs.types)) m
  fixed <- builtDictionary (placing holder.form) holder.type (mapValue placing holder.reducesTo)
  case heldTypes j (forget hs.types) m of
    [] => pure (DictParam fixed Nothing)
    (t :: ts) => do
      held <- coreType fc owner ValueType !(normaliseClosed !(packedType (t ::: ts)))
      pure (DictParam fixed (Just (MkHoles (t ::: ts) (MkBinder Many held))))

mutual
  ||| The function a call reaches at kinds that hold up to `choices`
  ||| choices, by its signature: the callee's own instance when they hold
  ||| none, requested; else what the instance's own signature makes it, a
  ||| dispatch on its first choice, each of whose arms holds one fewer
  ||| (`dispatchOn`): each arm is given that count (`givenArm`), so it falls
  ||| at every dispatch. The callee is a definition, or a member at a use
  ||| (`AtUse`), the member the choice it dispatches on.
  export
  calleeAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (choices : Nat) -> FC -> String -> (what : Instantiates) -> Vect (appliedArity what) PKind -> Front InstanceSig
  calleeAt Z fc owner what kinds = request fc owner what kinds
  calleeAt (S k) fc owner what kinds = dispatchOn k fc owner what kinds

  ||| The instance a call reaches at kinds that may hold a choice, made
  ||| once, its signature read then, as an instance's is: its identity is
  ||| the callee's link at the call's static arguments, which hold nothing
  ||| where a choice is, as no instance of the callee's does. Whether it is
  ||| a dispatch, and on which parameter, is its own signature's to say,
  ||| which is keyed by the call's static arguments alone and classified
  ||| apart from the call's kinds: on the first choice the signature takes,
  ||| whose position among its parameters at run time the signature fixes
  ||| (`givenChoice`). A dispatch is joined with every member its choice
  ||| has so far; an instance whose signature takes no choice is the
  ||| callee's own, recorded as any request is.
  dispatchOn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               (rest : Nat) -> FC -> String -> (what : Instantiates) -> Vect (appliedArity what) PKind -> Front InstanceSig
  dispatchOn rest fc owner what kinds = do
    found <- instanceFor fc owner what kinds
    let inst = InstanceOf found.link
    Nothing <- pure (requestedBefore inst !getState)
      | Just sig => pure sig
    (sig ** signed) <- instanceSig fc owner what found
    let Just at = givenChoice sig.kinds
      | Nothing => do
          recordRequest fc owner what found sig signed
          pure sig
    let parts = at.kindsSplit
    let (b, ty) = parts.here
    choice <- choiceFamily fc owner ty
    st <- getState
    let d = MkDispatch inst found.key sig what parts.kindsBefore (Given rest b ty) parts.kindsAfter
                       (trans parts.spans signed.classifiesAll) at.runtimePlace choice.family fc owner
    updateState (derive { instances $= insert inst sig, fnOrder $= (:< inst)
                        , dispatchesOn $= insert choice.family
                                            (d :: fromMaybe [] (lookupFact (.dispatchesOn) choice.family st)) })
    armsFor rest d 0 (choice.members <>> [])
    pure sig

  ||| The arms of a dispatch on a choice its parameter takes, for the
  ||| members given, the first at position `i`, each reaching its callee at
  ||| the `rest` choices after the one dispatched on (`givenArm`).
  armsFor : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            (rest : Nat) -> Dispatch -> (i : Nat) -> List ChoiceMember -> Front ()
  armsFor rest d i [] = pure ()
  armsFor rest d i (m :: ms) = do
    arm <- givenArm rest d m
    updateState (withArm d.inst i (MkDispatchArm m arm))
    armsFor rest d (S i) ms

  ||| What the arm of a dispatch on a choice its parameter takes calls for a
  ||| member: the callee at that member, at kinds that hold the `rest`
  ||| choices after the one dispatched on, requested, or dispatched on its
  ||| next choice.
  givenArm : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (rest : Nat) -> Dispatch -> ChoiceMember -> Front InstanceSig
  givenArm rest d m = calleeAt rest d.site d.owner d.callee (givenInstead (memberKind m) d)

||| The arm of a dispatch for its choice's member at position `i`, by the
||| signature of what it calls: for a choice its parameter takes, the
||| callee at that member, at the count of choices the dispatch left
||| (`givenArm`); for one an implementation it is given holds, the callee
||| with that field fixed to the member, requested (`heldMember`).
armAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
        Dispatch -> (i : Nat) -> ChoiceMember -> Front ()
armAt d i m = do
  arm <- case d.chosen of
    Given rest _ _ => givenArm rest d m
    HeldIn holder hs j => do
      kind <- heldMember d.site d.owner (finToNat j) holder hs m
      request d.site d.owner d.callee (givenInstead kind d)
  updateState (withArm d.inst i (MkDispatchArm m arm))

------------------------------------------------------------------------------
-- Choices an implementation holds
------------------------------------------------------------------------------

||| The first value an implementation given at a parameter closes over that
||| is itself a choice (`choiceType`): a field of the implementation the
||| running program chose, which the program fixes the members of: the
||| kinds split at its parameter, which holds the parameter as it holds
||| the choice (`HeldIn`, its place among the values the parameter holds)
||| and the type it is a choice of, as `choiceType` read it, and that
||| parameter's position at run time, read off the same kinds.
export
heldChoice : {auto s : Ref TState TS} -> (ks : List PKind) -> Front (Maybe (ChoiceAt ks (Chosen, ChoiceType)))
heldChoice [] = pure Nothing
heldChoice (DictParam holder (Just hs) :: ks) = do
  Just (j, t) <- among (forget hs.types)
    | Nothing => map (laterChoice (DictParam holder (Just hs))) <$> heldChoice ks
  pure (Just (MkChoiceAt (MkSplitKinds [] (HeldIn holder hs j, t) (Data.Vect.fromList ks) Refl) FZ))
  where
    among : (ts : List ClosedTerm) -> Front (Maybe (Fin (length ts), ChoiceType))
    among [] = pure Nothing
    among (t :: ts) = case !(choiceType t) of
      Just ct => pure (Just (FZ, ct))
      Nothing => map (\(j, ct) => (FS j, ct)) <$> among ts
heldChoice (k :: ks) = map (laterChoice k) <$> heldChoice ks

||| An instance given an implementation that holds a choice the running
||| program made, in the parameter its kinds are split at (`HeldIn`, at its
||| place among the values): a dispatch on that choice, whose arm for each member
||| is the callee's instance with the field fixed to the member
||| (`heldMember`), so that the callee's tree takes the field apart as it
||| takes any implementation the program fixes. The instance is the
||| dispatch: its identity, key and signature are the request's, its kinds
||| the request's split at that parameter (`heldChoice`), and the dispatch
||| is written with every other (`dispatchers`). It is joined with every
||| member its choice has so far.
export
heldDispatch : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               (r : Request) -> ChoiceAt r.signature.kinds (Chosen, ChoiceType) -> Front ()
heldDispatch r at = do
  let owner = show r.owner
  let parts = at.kindsSplit
  let (chosen, ty) = parts.here
  choice <- choiceFamily r.site owner ty
  let d = MkDispatch r.inst r.key r.signature r.instantiates parts.kindsBefore chosen parts.kindsAfter
                     (trans parts.spans r.classifiesAll) at.runtimePlace choice.family r.site owner
  st <- getState
  -- A request is one instance, of one choice, so its dispatch is made at
  -- most once, among that choice's.
  let made = fromMaybe [] (lookupFact (.dispatchesOn) choice.family st)
  let False = any (sameInstance r.inst) made
    | True => pure ()
  updateState (derive { dispatchesOn $= insert choice.family (d :: made) })
  traverse_ (\(i, m) => armAt d i m) (zip (iterateN (length choice.members) S 0) (choice.members <>> []))
  where
    sameInstance : FnId -> Dispatch -> Bool
    sameInstance inst e = e.inst == inst

||| A new member of a choice, joined with every dispatch made on it: each
||| has its arm for it.
added : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Choice -> ChoiceMember -> Front ()
added choice m = do
  let at = length choice.members
  updateState (withMember choice.family m)
  st <- getState
  for_ (fromMaybe [] (lookupFact (.dispatchesOn) choice.family st)) $ \d => armAt d at m

||| An implementation written where a value of a choice's type is made,
||| read as the one classification of a dictionary reads it
||| (`Template.dictionaryReading`): fixed at the choice's type, with its
||| reading and the value it reduces to (`Closed.fixedAt`), or nothing for
||| one the running program chooses. Only a fixed one is registered, so no
||| arm of a dispatch meets a member its tree cannot take apart.
fixedMember : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              ChoiceType -> (form : ClosedTerm) -> Front (Maybe FixedDictionary)
fixedMember ty form = do
  d <- dictionaryReading form
  pure (case fixedAt ty.type d.reduct of
          FixedNow v => Just (MkFixedDictionary form ty.type d.asStatic d.ofDictionary v)
          ChosenAtRunTime _ => Nothing)

||| The member of the choice of a type, as `choiceType` read it, for an
||| implementation that closes over no runtime value (`form`), where the
||| program fixes it (`fixedMember`): found by its form, or added as the
||| choice's next constructor, with no field. Nothing for one the running
||| program chooses, which is no member.
export
memberBare : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> String -> ChoiceType -> (form : ClosedTerm) -> Front (Maybe (Con 0))
memberBare fc owner ty form = do
  Just dictionary <- fixedMember ty form
    | Nothing => pure Nothing
  choice <- choiceFamily fc owner ty
  case found (choice.members <>> []) of
    Just con => pure (Just con)
    Nothing => do
      con <- newCon fc choice.family (length choice.members) form []
      added choice (MkChoiceMember dictionary (Bare con))
      pure (Just con)
  where
    found : List ChoiceMember -> Maybe (Con 0)
    found [] = Nothing
    found (MkChoiceMember d (Bare con) :: ms) = if d.form == form then Just con else found ms
    found (_ :: ms) = found ms

||| The member of the choice of a type, as `choiceType` read it, for an
||| implementation that closes over runtime values of these types, by its
||| form with a marker for each (`form`), where the program fixes it
||| (`fixedMember`): found by that form, or added as the choice's next
||| constructor, whose one field holds the values (`Holes`). Nothing for
||| one the running program chooses, which is no member.
export
memberHolding : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                FC -> String -> ChoiceType -> (form : ClosedTerm) -> List1 ClosedTerm -> Front (Maybe (Con 1))
memberHolding fc owner ty form types = do
  Just dictionary <- fixedMember ty form
    | Nothing => pure Nothing
  packed <- coreType fc owner ValueType !(normaliseClosed !(packedType types))
  let held = MkHoles types (MkBinder Many packed)
  choice <- choiceFamily fc owner ty
  case found (choice.members <>> []) of
    Just con => pure (Just con)
    Nothing => do
      con <- newCon fc choice.family (length choice.members) form [held.binder]
      added choice (MkChoiceMember dictionary (Capturing held con))
      pure (Just con)
  where
    found : List ChoiceMember -> Maybe (Con 1)
    found [] = Nothing
    found (MkChoiceMember d (Capturing _ con) :: ms) = if d.form == form then Just con else found ms
    found (_ :: ms) = found ms

------------------------------------------------------------------------------
-- Dispatches
------------------------------------------------------------------------------

||| The index terms a function passes on to a callee of its own telescope:
||| its own levels, in order.
export
ownLevels : Nat -> List ITerm
ownLevels n = map IVar (take n [0 .. n])

||| The arguments an arm passes its callee: each of the dispatch's
||| parameters as it is, but the choice, where the member's field goes when
||| it has one.
passed : {k : Nat} -> Loc -> (choice : Fin n) -> Maybe (Fin (Under k n)) -> List (Fin n) -> List (Term (Under k n))
passed loc choice field [] = []
passed loc choice field (x :: xs) =
  (if x == choice then maybe [] (\f => [Var loc f]) field else [Var loc (Free {k} x)]) ++ passed loc choice field xs

||| One dispatch as the function it is: a match on its choice, an arm per
||| member in the order the members were found (its arms, by the member's
||| position), each calling the callee's instance at that member with the
||| dispatch's parameters. A choice a parameter takes is that parameter,
||| and the member's field goes where it was. A choice an implementation
||| holds is one of the values its parameter holds, taken apart first, and
||| the member's own values go after the others, held as one again
||| (`heldMember`). A choice with no member is never built, so the
||| dispatch is never called. No definition of Idris's is it, so no proof
||| of Idris's covers a loop through it: what its arms do is theirs.
dispatcher : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Dispatch -> Front ()
dispatcher d = asFunction d.signature d.choice
  where
    matching : {0 p : Nat} -> Loc -> Fin p -> List (Alt p) -> Term p
    matching loc x [] = Unreachable loc NoMember
    matching loc x (a :: as) = Case loc d.family x (Exhaustive (a ::: as))

    -- What an arm calls, given the dispatch's parameters in order, as many
    -- as its signature takes: its index parameters are the dispatch's
    -- levels, so its binders and its result read in the dispatch's scope.
    -- Kept: the arm passes the parameters the dispatch has, and its
    -- callee, the member's instance, takes those its own signature
    -- classifies, two readings of one type that nothing ties to one count,
    -- so a parameter left past every function type its result shows is
    -- the second reading disagreeing with the first.
    calling : {0 q : Nat} -> Loc -> InstanceSig -> List ITerm -> List (Term q) -> Front (Term q)
    calling loc target indices xs =
      case applyMaker loc (MkMaker (\ys => Call loc target.callee Nothing indices ys)) target.callee.params
                      (substTy indices target.callee.result) xs of
        Just t => pure t
        Nothing => internal d.site "a dispatch's arm passing its member's instance more than its type takes"

    arm : Loc -> List ITerm -> Fin n -> List (Fin n) -> (Nat, DispatchArm) -> Front (Alt n)
    arm loc indices choice params (_, a) = do
      let inst = a.target
      case a.member.con of
        Bare con => MkAlt con [] <$> calling loc inst indices (passed {k = 0} loc choice Nothing params)
        Capturing _ con =>
          MkAlt con [shown "held"] <$> calling loc inst indices (passed {k = 1} loc choice (Just (Bound {k = 1} FZ)) params)

    -- The callee's instance at a member, given the dispatch's parameters,
    -- the implementation's parameter the values given, held as one, or
    -- nothing where none is left.
    called : {0 q : Nat} -> Loc -> InstanceSig -> List ITerm -> Fin n -> List (Fin n) -> (Fin n -> Fin q) ->
             List (ClosedTerm, Fin q) -> Front (Term q)
    called loc inst indices held params ren values = do
      packed <- case values of
                  [] => pure []
                  (v :: vs) => (:: []) <$> pack d.site d.owner loc (map (\(ty, y) => (ty, Var loc y)) (v ::: vs))
      calling loc inst indices (concatMap (\y => if y == held then packed else [Var loc (ren y)]) params)

    -- The arm for a member of a choice an implementation holds: the values
    -- left, then the member's own, taken apart from its field.
    heldArm : {0 p : Nat} -> Loc -> List ITerm -> Fin n -> List (Fin n) -> (Fin n -> Fin p) ->
              List (ClosedTerm, Fin p) -> (Nat, DispatchArm) -> Front (Alt p)
    heldArm loc indices held params ren others (_, a) = do
      let inst = a.target
      case a.member.con of
        Bare con => MkAlt con [] <$> called loc inst indices held params ren others
        Capturing h con => do
          body <- takenApart d.site d.owner loc h.types (Bound {k = 1} {n = p} FZ) $ \ren', own =>
                    called loc inst indices held params (ren' . Free {k = 1} . ren)
                           (map (\(ty, y) => (ty, ren' (Free {k = 1} y))) others ++ zip (forget h.types) (toList own))
          pure (MkAlt con [shown "held"] body)

    -- The function at the dispatch's signature, taken apart once, so that
    -- its kinds are those its callee and its choice are typed by: the
    -- callee's parameters, at run time, are the dispatch's.
    asFunction : (sig : InstanceSig) -> Fin (Runtimes sig.kinds) -> Front ()
    asFunction (MkInstanceSig kinds result callee) choice = do
      loc <- toLoc d.site
      st <- getState
      -- Each arm holds its member, written when the later of the two was
      -- made, so the match is read off the arms alone.
      let numbered = maybe [] SortedMap.toList (lookupFact (.dispatchArms) d.inst st)
      let indices = ownLevels (length (telescopeOf kinds))
      let params = List.allFins (Runtimes kinds)
      body <- case d.chosen of
        Given _ _ _ => do
          arms <- traverse (arm loc indices choice params) numbered
          pure (matching loc choice arms)
        HeldIn _ hs j =>
          -- The values are taken apart one per type, and the place is a
          -- position among the types.
          takenApart d.site d.owner loc hs.types choice $ \ren, values => do
            let typed = Data.Zippable.zip (Data.Vect.fromList (forget hs.types)) values
            let chosen = snd (Data.Vect.index j typed)
            arms <- traverse (heldArm loc indices choice params ren (without (finToNat j) (toList typed))) numbered
            pure (matching loc chosen arms)
      extents <- signatureExtents kinds result
      updateState (derive { fns $= insert d.inst (MkTFn d.key OwnFunction (telescopeOf kinds) (Runtimes kinds) callee
                                                        extents (map (const (shown "x")) callee.params) body loc Unproved) })

||| Dispatches in the order of their identities.
byInstance : Dispatch -> Dispatch -> Ordering
byInstance a b = compare a.inst b.inst

||| Every dispatch as the function it is, once the translation has found
||| every member of every choice: every dispatch is in the instance table,
||| on its choice, the worklist having merged every step's; each is
||| written in the order of its identity.
export
dispatchers : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Front ()
dispatchers = do
  st <- getState
  traverse_ dispatcher (sortBy byInstance (concat (values st.table.dispatchesOn)))
