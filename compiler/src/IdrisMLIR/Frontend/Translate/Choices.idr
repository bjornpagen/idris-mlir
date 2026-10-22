-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Implementations chosen at run time among those the program fixes.
|||
||| An implementation is a compile-time value wherever the program fixes
||| one: it keys the instance of what it is given to, and is no value at
||| run time (`Instances`). Where a run-time value decides which one it is
||| (`op @{choose k}`, a map built with one of two orderings, a field of a
||| constructor holding whichever implementation its construction site
||| gave), the implementations it can be are still a set the program fixes:
||| those written where an implementation of that type is made a value. So
||| such a value is a value of a closed sum, its type's choice
||| (`Types.choiceFamily`), one constructor per implementation, each
||| carrying what its implementation closes over (`Holes`), the choices its
||| own constraints made among them. It is a sum of which implementation,
||| never a record of methods: a use of a method needs no polymorphic
||| value, since every use fixes its own types.
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

import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Instances
import IdrisMLIR.Frontend.Translate.Keys
import IdrisMLIR.Frontend.Translate.Shapes
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Types
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
import Data.Vect

%default total

------------------------------------------------------------------------------
-- Members
------------------------------------------------------------------------------

||| A member's constructor, whatever its field.
conOf : MemberCon -> (k ** Con k)
conOf (Bare c) = (0 ** c)
conOf (Holding _ c) = (1 ** c)

||| What a callee is given at a member: the implementation it is, and the
||| values it closes over when it closes over any.
memberKind : ChoiceMember -> PKind
memberKind m = case m.con of
  Bare _ => DictParam m.form Nothing
  Holding h _ => DictParam m.form (Just h)

||| The constructor of the member at position `at` of a choice's family,
||| labelled for a reader by the definition its implementation is, and its
||| place, which keeps two members of one definition apart.
newCon : {auto c : Ref Ctxt Defs} -> FC -> FamilyId -> (at : Nat) -> ClosedTerm -> Vect k Binder -> Front (Con k)
newCon fc fam at form fields = do
  loc <- toLoc fc
  label <- case getFn form of
             Ref _ _ n => (\full => shortName full ++ "." ++ show at) <$> fullNames n
             _ => pure ("implementation." ++ show at)
  pure (MkCon (MkConId fam (last {n = at})) label [] [] fields loc)

replaceAt : Nat -> a -> List a -> List a
replaceAt Z v (_ :: ys) = v :: ys
replaceAt (S i) v (y :: ys) = y :: replaceAt i v ys
replaceAt _ _ [] = []

||| The first choice among a call's kinds: its position, and the type it is
||| a choice of.
firstChoice : List PKind -> Maybe (Nat, ClosedTerm)
firstChoice = go 0
  where
    go : Nat -> List PKind -> Maybe (Nat, ClosedTerm)
    go i [] = Nothing
    go i (ChoiceParam _ t :: _) = Just (i, t)
    go i (_ :: ks) = go (S i) ks

||| How many choices a call's kinds hold.
export
choicesIn : List PKind -> Nat
choicesIn [] = 0
choicesIn (ChoiceParam _ _ :: ks) = S (choicesIn ks)
choicesIn (_ :: ks) = choicesIn ks

mutual
  ||| The instance a call reaches at kinds that hold `choices` choices: the
  ||| callee's own when they hold none, requested; else a dispatch on the
  ||| first, each of whose arms holds one fewer.
  export
  calleeAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (choices : Nat) -> FC -> String -> Name -> List PKind -> Front FnId
  calleeAt Z fc owner n kinds = request fc owner n kinds
  calleeAt (S k) fc owner n kinds = case firstChoice kinds of
    Nothing => request fc owner n kinds
    Just (at, ty) => dispatchOn k fc owner n kinds at ty

  ||| The dispatch of a call on the choice at position `at`, made once: its
  ||| identity is the callee's link at the call's static arguments, which
  ||| hold nothing where the choice is, as no instance of the callee's does.
  ||| It is joined with every member its choice has so far.
  dispatchOn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               (rest : Nat) -> FC -> String -> Name -> List PKind -> (at : Nat) -> ClosedTerm -> Front FnId
  dispatchOn rest fc owner n kinds at ty = do
    choice <- choiceFamily fc owner ty
    found <- instanceKey fc owner n snd (map staticKindOf kinds)
    st <- getState
    case lookup found.link st.fnIds of
      Just inst => pure inst
      Nothing => do
        let inst = MkFnId st.nextInstance
        let d = MkDispatch inst found.symbol found.key n kinds choice.family at rest fc owner empty
        updateState { fnIds $= insert found.link inst, nextInstance $= S, fnOrder $= (:< inst)
                    , dispatches $= insert inst d
                    , dispatchesOn $= insert choice.family (inst :: fromMaybe [] (lookup choice.family st.dispatchesOn)) }
        armsFor rest d 0 (choice.members <>> [])
        pure inst

  ||| The arms of a dispatch for the members given, the first at position
  ||| `i`.
  armsFor : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            (rest : Nat) -> Dispatch -> (i : Nat) -> List ChoiceMember -> Front ()
  armsFor rest d i [] = pure ()
  armsFor rest d i (m :: ms) = do
    armAt rest d i m
    armsFor rest d (S i) ms

  ||| The arm of a dispatch for its choice's member at position `i`: the
  ||| callee at that member, requested, or dispatched on its next choice.
  armAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          (rest : Nat) -> Dispatch -> (i : Nat) -> ChoiceMember -> Front ()
  armAt rest d i m = do
    arm <- calleeAt rest d.site d.owner d.callee (replaceAt d.at (memberKind m) d.kinds)
    updateState { dispatches $= updateExisting ({ arms $= insert i arm }) d.inst }

||| A new member of a choice, joined with every dispatch made on it: each
||| has its arm for it.
added : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Choice -> ChoiceMember -> Front ()
added choice m = do
  let at = length choice.members
  updateState { choices $= updateExisting ({ members $= (:< m) }) choice.family
              , families $= updateExisting ({ cons $= (++ [conOf m.con]) }) choice.family }
  st <- getState
  for_ (fromMaybe [] (lookup choice.family st.dispatchesOn)) $ \inst => do
    let Just d = lookup inst st.dispatches
      | Nothing => internal EmptyFC "a dispatch listed on its choice and never made"
    armAt d.rest d at m

||| The member of the choice of `type` for an implementation that closes over
||| no runtime value (`form`): found by its form, or added as the choice's
||| next constructor, with no field.
export
memberBare : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> String -> (type, form : ClosedTerm) -> Front (Con 0)
memberBare fc owner ty form = do
  choice <- choiceFamily fc owner ty
  case found (choice.members <>> []) of
    Just con => pure con
    Nothing => do
      con <- newCon fc choice.family (length choice.members) form []
      added choice (MkChoiceMember form (Bare con))
      pure con
  where
    found : List ChoiceMember -> Maybe (Con 0)
    found [] = Nothing
    found (MkChoiceMember f (Bare con) :: ms) = if f == form then Just con else found ms
    found (_ :: ms) = found ms

||| The member of the choice of `type` for an implementation that closes over
||| runtime values, by its form with a marker for each (`form`): found by
||| that form, or added as the choice's next constructor, whose one field
||| holds the values (`Holes`).
export
memberHolding : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
                FC -> String -> (type, form : ClosedTerm) -> Holes -> Front (Con 1)
memberHolding fc owner ty form held = do
  choice <- choiceFamily fc owner ty
  case found (choice.members <>> []) of
    Just con => pure con
    Nothing => do
      con <- newCon fc choice.family (length choice.members) form [held.binder]
      added choice (MkChoiceMember form (Holding held con))
      pure con
  where
    found : List ChoiceMember -> Maybe (Con 1)
    found [] = Nothing
    found (MkChoiceMember f (Holding _ con) :: ms) = if f == form then Just con else found ms
    found (_ :: ms) = found ms

------------------------------------------------------------------------------
-- Dispatches
------------------------------------------------------------------------------

||| The index terms a function passes on to a callee of its own telescope:
||| its own levels, in order.
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
||| member in the order the members were found, each calling the callee's
||| instance at that member with the dispatch's parameters, the member's
||| field where the choice was. A choice with no member is never built, so
||| the dispatch is never called. It has no loop of its own: what its arms
||| do is theirs.
dispatcher : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Dispatch -> Front ()
dispatcher d = do
  def <- lookupDef d.site d.owner d.callee
  let PMDef _ params _ _ _ = definition def
    | _ => internal d.site ("a dispatch on " ++ show (fullname def) ++ ", which is no function")
  (kinds, resTy) <- classifyInstance d.site d.owner (length params) (type def) (givenArgs d.kinds)
  result <- coreType d.site d.owner ValueType !(normaliseClosed resTy)
  loc <- toLoc d.site
  st <- getState
  let members = maybe [] (\ch => ch.members <>> []) (lookup d.family st.choices)
  let Just choice = natToFin (Runtimes (take d.at kinds)) (Runtimes kinds)
    | Nothing => internal d.site "a dispatch whose choice is no parameter at run time"
  let indices = ownLevels (length (telescopeOf kinds))
  let params = List.allFins (Runtimes kinds)
  arms <- traverse (arm loc indices choice params) (zip [0 .. length members] members)
  let body = case arms of
               [] => Unreachable loc
               (a :: as) => Case loc choice (Exhaustive (a ::: as))
  updateState { fns $= insert d.inst (MkTFn d.inst d.symbol d.key (telescopeOf kinds) (Runtimes kinds)
                                            (map (\b => (shown "x", b)) (runtimeBinders kinds))
                                            result body loc Acyclic) }
  where
    arm : Loc -> List ITerm -> Fin n -> List (Fin n) -> (Nat, ChoiceMember) -> Front (Alt n)
    arm loc indices choice params (i, m) = do
      let Just inst = lookup i d.arms
        | Nothing => internal d.site "a member joined with a dispatch and given no arm"
      case m.con of
        Bare con => pure (MkAlt con [] (Call loc inst Nothing indices (passed {k = 0} loc choice Nothing params)))
        Holding _ con =>
          pure (MkAlt con [shown "held"] (Call loc inst Nothing indices (passed {k = 1} loc choice (Just (Bound FZ)) params)))

||| Every dispatch as the function it is, once the translation has found
||| every member of every choice.
export
dispatchers : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Front ()
dispatchers = traverse_ dispatcher (values (!(getState)).dispatches)
