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

import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Instances
import IdrisMLIR.Frontend.Translate.Keys
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

------------------------------------------------------------------------------
-- Members
------------------------------------------------------------------------------

||| The one constructor of a data type (`Res`, `IORes`, a pair, the unit),
||| of `k` fields. Each is a declaration of Idris's or of a trusted
||| library's, read with the program when the compiler runs, whose shape
||| the declaration states and its family's identity does not carry.
export
onlyCon : {auto s : Ref TState TS} -> FC -> (k : Nat) -> Ty -> Front (Con k)
onlyCon fc k (DataT inst _) = do
  st <- getState
  -- A family's identity is minted by its registration, which writes it
  -- in the table this reads, whose type does not say so.
  let Just decl = familyOf inst st
    | Nothing => internal fc ("a value of an undeclared type " ++ show inst)
  let [(k' ** con)] = decl.cons
    | _ => internal fc ("a value of " ++ show inst ++ ", which has not one constructor")
  let Yes Refl = decEq k' k
    | No _ => internal fc ("a value of " ++ show inst ++ ", whose constructor has " ++ show k' ++ " fields, not " ++ show k)
  pure con
onlyCon fc k t = internal fc ("a value of type " ++ show t)

||| The pair that holds values of these types as one (`packedType`), the
||| first and the rest.
pairOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         FC -> String -> ClosedTerm -> List1 ClosedTerm -> Front (Con 2)
pairOf fc owner t rest = do
  -- The pair Idris's `%pair` names, applied, is a data type's, whose Core
  -- type `coreType` reads from the type, which says nothing of `packedType`.
  DataT inst _ <- coreType fc owner ValueType !(normaliseClosed !(packedType (t ::: forget rest)))
    | _ => internal fc "values held as one, in no pair"
  onlyCon fc 2 (DataT inst [])

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

||| The values one variable holds as one (`pack`), of these types, taken
||| apart by the pairs that hold them: the body built over each value's
||| variable, in order, with the renaming of the scope outside.
export
takenApart : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {0 n : Nat} ->
             FC -> String -> Loc -> ClosedTerm -> List ClosedTerm -> Fin n ->
             ({0 p : Nat} -> (Fin n -> Fin p) -> List (Fin p) -> Front (Term p)) -> Front (Term n)
takenApart fc owner loc t [] x k = k id [x]
takenApart fc owner loc t (u :: us) x k = do
  pair <- pairOf fc owner t (u ::: us)
  body <- takenApart fc owner loc u us (Bound {k = 2} (FS FZ))
            (\ren, vs => k (ren . Free {k = 2}) (ren (Bound {k = 2} FZ) :: vs))
  pure (Case loc pair.id.family x (Exhaustive (MkAlt pair [shown "value", shown "rest"] body ::: [])))

||| A list without its element at a place.
without : Nat -> List a -> List a
without Z (_ :: ys) = ys
without (S i) (y :: ys) = y :: without i ys
without _ [] = []

||| A member's constructor, whatever its field.
conOf : MemberCon -> (k ** Con k)
conOf (Bare c) = (0 ** c)
conOf (Capturing _ c) = (1 ** c)

||| What a callee is given at a member: the implementation it is, and the
||| values it closes over when it closes over any.
memberKind : ChoiceMember -> PKind
memberKind m = case m.con of
  Bare _ => DictParam m.form Nothing
  Capturing h _ => DictParam m.form (Just h)

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

||| A dispatch with its arm for the member at position `i`, the signature
||| of the instance it calls, as the step being run derives it: the
||| dispatch as the step reads it (`lookupFact`), with the arm, superseding
||| the table's.
withArm : FnId -> Nat -> InstanceSig -> TS -> TS
withArm inst i arm st = case lookupFact (.dispatches) inst st of
  Just d => derive { dispatches $= insert inst ({ arms $= insert i arm } d) } st
  Nothing => st

||| A choice with one more member, and its family with the member's
||| constructor after the others, as the step being run derives them: each
||| as the step reads it (`lookupFact`), changed, superseding the table's.
withMember : FamilyId -> ChoiceMember -> TS -> TS
withMember fam m st =
  let st' = case lookupFact (.choices) fam st of
              Just ch => derive { choices $= insert fam ({ members $= (:< m) } ch) } st
              Nothing => st in
  case familyOf fam st' of
    Just f => derive { families $= insert fam ({ cons $= (++ [conOf m.con]) } f) } st'
    Nothing => st'

||| The first choice among a call's kinds: the kinds before it, its
||| parameter's binder and the type it is a choice of, and the kinds after
||| it.
firstChoice : List PKind -> Maybe (List PKind, Binder, ClosedTerm, List PKind)
firstChoice [] = Nothing
firstChoice (ChoiceParam b t :: ks) = Just ([], b, t, ks)
firstChoice (k :: ks) = (\(before, b, t, after) => (k :: before, b, t, after)) <$> firstChoice ks

||| How many choices a call's kinds hold.
export
choicesIn : List PKind -> Nat
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

||| An implementation's form for one member of the choice it holds at
||| place `j` (`heldTypes`): the member's form in place of the choice's
||| marker, the markers after it each one lower, and the member's own after
||| all of them. The member's markers pass through the frontend's other
||| family of markers on the way, so that none is renamed twice.
heldForm : (j : Nat) -> (count : Nat) -> ClosedTerm -> ChoiceMember -> ClosedTerm
heldForm j count form m =
  let own = iterateN (length (ownValues m)) S 0
      left = minus count 1
      moved = fillHoles (map found own) m.form
      placed = substName (markerName j) moved form
      lowered = foldl (\t, i => substName (markerName (S i)) (holeMarker i) t) placed (drop j (iterateN left S 0))
  in foldl (\t, q => substName (probeName (ProbeHoleFound q)) (holeMarker (left + q)) t) lowered own
  where
    found : Nat -> ClosedTerm
    found q = probeTerm (ProbeHoleFound q)

||| The parameter an instance takes for one member of the choice the
||| implementation it is given holds at place `j`: the implementation with
||| that field fixed (`heldForm`), holding the values left (`heldTypes`),
||| none when none is left.
heldMember : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             FC -> String -> (j : Nat) -> ClosedTerm -> Holes -> ChoiceMember -> Front PKind
heldMember fc owner j form hs m = do
  let form' = heldForm j (length (forget hs.types)) form m
  case heldTypes j (forget hs.types) m of
    [] => pure (DictParam form' Nothing)
    (t :: ts) => do
      held <- coreType fc owner ValueType !(normaliseClosed !(packedType (t ::: ts)))
      pure (DictParam form' (Just (MkHoles (t ::: ts) (MkBinder Many held))))

mutual
  ||| The function a call reaches at kinds that hold `choices` choices, by
  ||| its signature: the callee's own instance when they hold none,
  ||| requested; else a dispatch on the first, each of whose arms holds one
  ||| fewer. The callee is a definition, or a member at a use (`AtUse`), the
  ||| member the choice it dispatches on.
  export
  calleeAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             (choices : Nat) -> FC -> String -> Instantiates -> List PKind -> Front InstanceSig
  calleeAt Z fc owner what kinds = request fc owner what kinds
  calleeAt (S k) fc owner what kinds = case firstChoice kinds of
    Nothing => request fc owner what kinds
    Just (before, b, ty, after) => dispatchOn k fc owner what before b ty after

  ||| The dispatch of a call on the choice in the parameter after `before`,
  ||| made once, its signature read then, as an instance's is: its identity
  ||| is the callee's link at the call's static arguments, which hold
  ||| nothing where the choice is, as no instance of the callee's does. It
  ||| is joined with every member its choice has so far.
  dispatchOn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               (rest : Nat) -> FC -> String -> Instantiates -> (before : List PKind) -> Binder -> ClosedTerm ->
               (after : List PKind) -> Front InstanceSig
  dispatchOn rest fc owner what before b ty after = do
    choice <- choiceFamily fc owner ty
    let kinds = before ++ ChoiceParam b ty :: after
    found <- instanceFor fc owner what kinds
    let inst = InstanceOf found.link
    Nothing <- pure (requestedBefore inst !getState)
      | Just sig => pure sig
    sig <- instanceSig fc owner what kinds inst found.symbol
    st <- getState
    let d = MkDispatch inst found.key sig what before (Given rest b ty) after choice.family fc owner empty
    updateState (derive { instances $= insert inst sig, fnOrder $= (:< inst)
                        , dispatches $= insert inst d
                        , dispatchesOn $= insert choice.family
                                            (inst :: fromMaybe [] (lookupFact (.dispatchesOn) choice.family st)) })
    armsFor d 0 (choice.members <>> [])
    pure sig

  ||| The arms of a dispatch for the members given, the first at position
  ||| `i`.
  armsFor : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            Dispatch -> (i : Nat) -> List ChoiceMember -> Front ()
  armsFor d i [] = pure ()
  armsFor d i (m :: ms) = do
    armAt d i m
    armsFor d (S i) ms

  ||| The arm of a dispatch for its choice's member at position `i`, by the
  ||| signature of what it calls: for a choice its parameter takes, the
  ||| callee at that member, requested, or dispatched on its next choice;
  ||| for one an implementation it is given holds, the callee with that
  ||| field fixed to the member, requested (`heldMember`).
  armAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          Dispatch -> (i : Nat) -> ChoiceMember -> Front ()
  armAt d i m = do
    arm <- case d.chosen of
      Given rest _ _ => calleeAt rest d.site d.owner d.callee (givenInstead (memberKind m) d)
      Held j form hs => do
        kind <- heldMember d.site d.owner j form hs m
        request d.site d.owner d.callee (givenInstead kind d)
    updateState (withArm d.inst i arm)

------------------------------------------------------------------------------
-- Choices an implementation holds
------------------------------------------------------------------------------

||| The first value an implementation given at a parameter closes over that
||| is itself a choice (`choiceType`): a field of the implementation the
||| running program chose, which the program fixes the members of. The
||| kinds before its parameter, the parameter as it holds the choice
||| (`Held`, its place among the values the parameter holds), the kinds
||| after it, and the type it is a choice of.
export
heldChoice : {auto s : Ref TState TS} ->
             List PKind -> Front (Maybe (List PKind, Chosen, List PKind, ClosedTerm))
heldChoice = go [<]
  where
    among : Nat -> List ClosedTerm -> Front (Maybe (Nat, ClosedTerm))
    among j [] = pure Nothing
    among j (t :: ts) = if !(choiceType t) then pure (Just (j, t)) else among (S j) ts

    go : SnocList PKind -> List PKind -> Front (Maybe (List PKind, Chosen, List PKind, ClosedTerm))
    go before [] = pure Nothing
    go before (DictParam form (Just hs) :: ks) = do
      Just (j, t) <- among 0 (forget hs.types)
        | Nothing => go (before :< DictParam form (Just hs)) ks
      pure (Just (before <>> [], Held j form hs, ks, t))
    go before (k :: ks) = go (before :< k) ks

||| An instance given an implementation that holds a choice the running
||| program made, in the parameter after `before` (`Held`, at its place
||| among the values): a dispatch on that choice, whose arm for each member
||| is the callee's instance with the field fixed to the member
||| (`heldMember`), so that the callee's tree takes the field apart as it
||| takes any implementation the program fixes. The instance is the
||| dispatch: its identity, key and signature are the request's, its kinds
||| the request's split at that parameter (`heldChoice`), and the dispatch
||| is written with every other (`dispatchers`). It is joined with every
||| member its choice has so far.
export
heldDispatch : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
               Request -> (before : List PKind) -> Chosen -> (after : List PKind) -> ClosedTerm -> Front ()
heldDispatch r before chosen after ty = do
  let owner = show r.owner
  choice <- choiceFamily r.site owner ty
  let d = MkDispatch r.inst r.key r.signature r.instantiates before chosen after choice.family r.site owner empty
  st <- getState
  let Nothing = lookupFact (.dispatches) r.inst st
    | Just _ => pure ()
  updateState (derive { dispatches $= insert r.inst d
                      , dispatchesOn $= insert choice.family
                                          (r.inst :: fromMaybe [] (lookupFact (.dispatchesOn) choice.family st)) })
  traverse_ (\(i, m) => armAt d i m) (zip (iterateN (length choice.members) S 0) (choice.members <>> []))

||| A new member of a choice, joined with every dispatch made on it: each
||| has its arm for it.
added : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Choice -> ChoiceMember -> Front ()
added choice m = do
  let at = length choice.members
  updateState (withMember choice.family m)
  st <- getState
  for_ (fromMaybe [] (lookupFact (.dispatchesOn) choice.family st)) $ \inst => do
    -- Each dispatch is listed on its choice where it is made, by the
    -- identity its table keys it by: two tables, which nothing ties.
    let Just d = lookupFact (.dispatches) inst st
      | Nothing => internal EmptyFC "a dispatch listed on its choice and never made"
    armAt d at m

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
      added choice (MkChoiceMember form (Capturing held con))
      pure con
  where
    found : List ChoiceMember -> Maybe (Con 1)
    found [] = Nothing
    found (MkChoiceMember f (Capturing _ con) :: ms) = if f == form then Just con else found ms
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
||| member in the order the members were found, each calling the callee's
||| instance at that member with the dispatch's parameters. A choice a
||| parameter takes is that parameter, and the member's field goes where it
||| was. A choice an implementation holds is one of the values its
||| parameter holds, taken apart first, and the member's own values go
||| after the others, held as one again (`heldMember`). A choice with no
||| member is never built, so the dispatch is never called. It has no loop
||| of its own: what its arms do is theirs.
dispatcher : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Dispatch -> Front ()
dispatcher d = do
  let kinds = d.signature.kinds
  loc <- toLoc d.site
  st <- getState
  let members = maybe [] (\ch => ch.members <>> []) (lookupFact (.choices) d.family st)
  -- The choice's parameter is one at run time in the dispatch's kinds;
  -- its signature is those kinds classified over their static arguments,
  -- a second reading that nothing ties to the first.
  let Just choice = natToFin (Runtimes (take (length d.kindsBefore) kinds)) (Runtimes kinds)
    | Nothing => internal d.site "a dispatch whose choice is no parameter at run time"
  let indices = ownLevels (length (telescopeOf kinds))
  let params = List.allFins (Runtimes kinds)
  let numbered = zip (iterateN (length members) S 0) members
  body <- case d.chosen of
    Given _ _ _ => do
      arms <- traverse (arm loc indices choice params) numbered
      pure (matching loc choice arms)
    Held j _ hs => do
      let (t ::: ts) = hs.types
      takenApart d.site d.owner loc t ts choice $ \ren, values => do
        let typed = zip (forget hs.types) values
        -- The place was found among the values' types (`heldChoice`), and
        -- the values are taken apart one per type, as lists whose lengths
        -- nothing ties.
        let Just (_, chosen) = getAt j typed
          | Nothing => internal d.site "a choice held past the values an implementation holds"
        arms <- traverse (heldArm loc indices choice params ren (without j typed)) numbered
        pure (matching loc chosen arms)
  updateState (derive { fns $= insert d.inst (MkTFn d.key (telescopeOf kinds) (Runtimes kinds) d.signature.callee
                                                    (map (const (shown "x")) d.signature.callee.params) body loc Acyclic) })
  where
    matching : {0 p : Nat} -> Loc -> Fin p -> List (Alt p) -> Term p
    matching loc x [] = Unreachable loc
    matching loc x (a :: as) = Case loc d.family x (Exhaustive (a ::: as))

    -- Each member is joined with the dispatch when the later of the two
    -- is made, its arm written by its place in a map the members do not
    -- index.
    armOf : Nat -> Front InstanceSig
    armOf i = case lookup i d.arms of
      Just target => pure target
      Nothing => internal d.site "a member joined with a dispatch and given no arm"

    -- What an arm calls, given the dispatch's parameters in order, as many
    -- as its signature takes: its index parameters are the dispatch's
    -- levels, so its binders read in the dispatch's scope.
    calling : {0 q : Nat} -> Loc -> InstanceSig -> List ITerm -> List (Term q) -> Term q
    calling loc target indices = applyMaker loc (MkMaker (\ys => Call loc target.callee Nothing indices ys)) target.callee.params

    arm : Loc -> List ITerm -> Fin n -> List (Fin n) -> (Nat, ChoiceMember) -> Front (Alt n)
    arm loc indices choice params (i, m) = do
      inst <- armOf i
      case m.con of
        Bare con => pure (MkAlt con [] (calling loc inst indices (passed {k = 0} loc choice Nothing params)))
        Capturing _ con =>
          pure (MkAlt con [shown "held"] (calling loc inst indices (passed {k = 1} loc choice (Just (Bound FZ)) params)))

    -- The callee's instance at a member, given the dispatch's parameters,
    -- the implementation's parameter the values given, held as one, or
    -- nothing where none is left.
    called : {0 q : Nat} -> Loc -> InstanceSig -> List ITerm -> Fin n -> List (Fin n) -> (Fin n -> Fin q) ->
             List (ClosedTerm, Fin q) -> Front (Term q)
    called loc inst indices held params ren values = do
      packed <- case values of
                  [] => pure []
                  (v :: vs) => (:: []) <$> pack d.site d.owner loc (map (\(ty, y) => (ty, Var loc y)) (v ::: vs))
      pure (calling loc inst indices (concatMap (\y => if y == held then packed else [Var loc (ren y)]) params))

    -- The arm for a member of a choice an implementation holds: the values
    -- left, then the member's own, taken apart from its field.
    heldArm : {0 p : Nat} -> Loc -> List ITerm -> Fin n -> List (Fin n) -> (Fin n -> Fin p) ->
              List (ClosedTerm, Fin p) -> (Nat, ChoiceMember) -> Front (Alt p)
    heldArm loc indices held params ren others (i, m) = do
      inst <- armOf i
      case m.con of
        Bare con => MkAlt con [] <$> called loc inst indices held params ren others
        Capturing h con => do
          let (t ::: ts) = h.types
          body <- takenApart d.site d.owner loc t ts (Bound {k = 1} {n = p} FZ) $ \ren', own =>
                    called loc inst indices held params (ren' . Free {k = 1} . ren)
                           (map (\(ty, y) => (ty, ren' (Free {k = 1} y))) others ++ zip (forget h.types) own)
          pure (MkAlt con [shown "held"] body)

||| Every dispatch as the function it is, once the translation has found
||| every member of every choice: every dispatch is in the instance table,
||| the worklist having merged every step's.
export
dispatchers : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Front ()
dispatchers = traverse_ dispatcher (values (!(getState)).table.dispatches)
