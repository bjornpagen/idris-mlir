-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What each definition writes at the static positions of what it calls and
||| builds, of the application where a use applies a polymorphic function
||| the running program chooses, and of each choice it makes a member of,
||| read off its signature and its case tree, with every parameter a
||| marker: the growth check's sites. They are the definition's, never an
||| instance's, so that a coincidence between two instances' arguments is no
||| arc, and a site of a clause no instance reaches is still one. A member
||| of a polymorphic function's choice is applied at each use of the choice
||| as no definition is, so the definition that makes it also writes what
||| its body requests at a use, reading the use's positions as its own
||| parameters past those it has (`Parameters`). A definition's reading is
||| its text annotated with the walk (`Translate.Annotated`): a node per step
||| the walk takes, each site in the field of the node whose role it is,
||| each made at the place the walk was at (`Translate.Place`), which orders
||| a reading's sites for every reader that takes them in turn, and which
||| the growth graph numbers once (`Graph.numberedReadings`).
|||
||| A leaf knows what its matches made of the parameters: a match on a shape
||| is substituted where it happens, so that `count (S m) = count (S (S m))`
||| writes `S (S m)` with `m` a part one level down, and a default clause,
||| expanded into the constructors it stands for, writes the constructor it
||| matched. Each part a match binds has a stand-in of its own
||| (`Readings.StandIn`), kept as its own marker up to the reading, so that
||| a site's term is an instance's argument with a value put in for each
||| marker. A dictionary keeps its marker through every match, since its
||| root is the writer's head, which the flow reads.
module IdrisMLIR.Frontend.Growth.Sites

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.TT
import Libraries.Data.List.SizeOf
import Libraries.Data.List.Thin
import Libraries.Data.NameMap

import IdrisMLIR.Frontend.Growth.Implementations
import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Profile
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Annotated
import IdrisMLIR.Frontend.Translate.Boundary
import IdrisMLIR.Frontend.Translate.Cases
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Instances
import IdrisMLIR.Frontend.Translate.Keys
import IdrisMLIR.Frontend.Translate.Place
import IdrisMLIR.Frontend.Translate.Readings
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template
import IdrisMLIR.Registry

import Control.Applicative.Const
import Control.Monad.Identity
import Control.WellFounded
import Data.DPair
import Data.List
import Data.List.Quantifiers
import Data.List1
import Data.SnocList
import Data.SortedSet
import Data.String
import Data.Vect

%default total

-- A site closes a term over its environment (`close`) and names what a
-- constructor's application gives (`Constructed`), neither of them a
-- reading's.
%hide IdrisMLIR.Frontend.Translate.Readings.close
%hide IdrisMLIR.Frontend.Translate.Readings.Constructed

||| The sites a walk's nodes hold, in the order the walk made them.
madeIn : (visit : Visitor (Const (SnocList Made)) AtRole AtRole -> a -> Const (SnocList Made) a) -> a -> List Made
madeIn visit x = runConst (visit (\y => MkConst [< y.made]) x) <>> []

||| A reading's sites in the order of their places in the writer's text, at
||| each place in the order the walk made them there: the order every
||| reader of a reading's sites in turn takes them in (`Graph`).
export
inTextOrder : ReadingTree AtRole -> List Site
inTextOrder t = entriesOf (grownFrom (map (\m => (m.place, m.site)) (madeIn traverseReading t)))

------------------------------------------------------------------------------
-- What each variable stands for
------------------------------------------------------------------------------

||| What a hole marker of a dictionary known as a term stands for, where
||| the walk knows its type: a runtime value, of that type; or a dictionary
||| another place binds, the one value that place holds, of the type the
||| values the walk knows of it pack to, which a key's projections of it
||| are built over.
data Closing = ValueOf ClosedTerm | HolderOf BoundPlace ClosedTerm

||| The type a key's projections of a marker are built over.
closingType : Closing -> ClosedTerm
closingType (ValueOf ty) = ty
closingType (HolderOf _ packed) = packed

||| What a dictionary known as a term closes over, where the walk knows the
||| type of each value its key's markers stand for: the place that binds
||| it, which holds what it closes over as one; its form with a hole
||| marker for each value (`holedAt`); what each marker stands for, in the
||| markers' order; and the writer's dictionary parameters it mentions,
||| each the one value it holds, which the translation holds among the
||| dictionary's own values (`Terms.holed`).
record ClosedOver where
  constructor MkClosedOver
  binding : BoundPlace
  holedForm : ClosedTerm
  closings : List1 Closing
  owners : List Nat

||| The types its key's projections and its settled form are built over,
||| one for each of its markers (`Closed.unpacked`, `Closed.packedType`).
valueTypes : ClosedOver -> List1 ClosedTerm
valueTypes co = map closingType co.closings

||| A dictionary a variable holds: the writer's dictionary parameter `i`,
||| and the fields matched out of it, the first first, which a match on it
||| takes apart without making it a part of anything, so it keeps its
||| marker; or one known as a term, the dictionary a constructor holds,
||| matched out of a value, or one written where a lambda's dictionary
||| binder takes it, closed as every term is (`close`), with what it closes
||| over where it closes over values whose types the walk knows
||| (`knownAt`).
data Dict = Own Nat (List Nat) | Known ClosedTerm (Maybe ClosedOver)

||| What a variable of the walk stands for: a compile-time value that is
||| never code (a parameter's type, family or form at the node, a type a
||| match reads off the scrutinee's type, an erased argument a lambda is
||| applied to); a dictionary; a runtime value whose shape keys the
||| instance, not matched yet (a stand-in), or matched (a constructor of
||| stand-ins); a value of quantity 0; the one value the place a dictionary
||| is bound at holds, its values packed into one, which the dictionary is
||| settled over (`settledWalk`); or any other runtime value. A shape not
||| matched yet carries its stand-in, so that a match knows what it rebinds
||| and the path to each part it binds without looking it up.
data Stand = Fixed ClosedTerm
           | Holds Dict
           | Pattern StandIn
           | Shape ClosedTerm
           | Erased
           | Packs BoundPlace
           | Runtime

||| What a stand is in a closed term: a runtime value as `closeWritten` has
||| it, a quantity-0 value as a placeholder. The writer's own dictionary is
||| the field its path reads, which with no field matched out is its marker.
termOf : Stand -> ClosedTerm
termOf (Fixed t) = t
termOf (Holds (Own i path)) = fieldAt i path
termOf (Holds (Known t _)) = t
termOf (Pattern p) = standInAt p
termOf (Shape t) = t
termOf Erased = Erased EmptyFC Placeholder
termOf (Packs _) = Erased EmptyFC Impossible
termOf Runtime = Erased EmptyFC Impossible

||| A variable as the walk knows it: what it stands for, the name a message
||| shows it by, and its type where that is known.
Standing : Type
Standing = (Stand, Name, Maybe ClosedTerm)

||| What each variable of a scope stands for, the innermost first, so that a
||| variable out of scope has nothing to stand for.
Env : Scope -> Type
Env vs = ByVar vs Standing

||| A term in scope, closed with what each variable stands for.
close : {vs : Scope} -> Env vs -> TT vs -> ClosedTerm
close env t = closeOver EmptyFC (map (\(s, _, _) => termOf s) env) t

||| What a call knows of a term it gives: a variable that holds a dictionary
||| is an implementation. The translation passes a caller's dictionaries to
||| its blocks as explicit arguments, so the callee's binder alone does not
||| say.
offerOf : Env vs -> TT vs -> Offer
offerOf env (Local _ _ idx p) = case lookupVar idx p env of
  (Holds _, _, _) => AnImplementation
  _ => AValue
offerOf _ _ = AValue

------------------------------------------------------------------------------
-- Pattern stand-ins
------------------------------------------------------------------------------

||| The stand-ins made on the walk's path so far, the next one's number, and
||| where the walk is in the writer's text (`Place`): the step it took at
||| each node from the writer's root, each walk of one term (as code, as a
||| static value, at a use, as a computed field) a step with its own mode,
||| so that no two binders the walk meets are at one place (`BoundPlace`).
public export
record Pats where
  constructor MkPats
  next : Nat
  made : List StandIn
  place : Place

||| The walk gone one step down from where it is, with the stand-ins it
||| has made.
entering : PlaceStep -> Pats -> Pats
entering s ps = { place $= into s } ps

||| A fresh stand-in for the part of parameter `i` that matches reached
||| along `path`, the parameter's field first.
fresh : (i : Nat) -> (path : List Nat) -> Pats -> (Stand, Pats)
fresh i path ps = let p = MkStandIn ps.next i path in (Pattern p, { next := S ps.next, made $= (p ::) } ps)

||| A term with each of the names given replaced by its term, all at once.
replacing : List (Name, ClosedTerm) -> ClosedTerm -> ClosedTerm
replacing rs t = let (ns ** (bs, vs)) = bindings rs in substs (mkSizeOf ns) vs (refsToLocals bs t)
  where
    bindings : List (Name, ClosedTerm) -> (ns : List Name ** (Bounds ns, SubstEnv ns Scope.empty))
    bindings [] = ([] ** (None, []))
    bindings ((n, v) :: more) = let (ns ** (bs, vs)) = bindings more in (n :: ns ** (Add n n bs, v :: vs))

------------------------------------------------------------------------------
-- How an argument is closed and shown
------------------------------------------------------------------------------

mutual
  ||| Those of the names that a term refers to, each once, after those met
  ||| already, in the order a reading from the left first meets them, with
  ||| the set of them.
  occurring : SortedSet Name -> TT vs -> (SnocList Name, SortedSet Name) -> (SnocList Name, SortedSet Name)
  occurring wanted (Ref _ _ n) met@(order, seen) =
    if contains n wanted && not (contains n seen) then (order :< n, insert n seen) else met
  occurring wanted (App _ f a) met = occurring wanted a (occurring wanted f met)
  occurring wanted (Bind _ _ (Let _ _ v ty) sc) met = occurring wanted sc (occurring wanted ty (occurring wanted v met))
  occurring wanted (Bind _ _ (PLet _ _ v ty) sc) met = occurring wanted sc (occurring wanted ty (occurring wanted v met))
  occurring wanted (Bind _ _ (Lam _ _ _ ty) sc) met = occurring wanted sc (occurring wanted ty met)
  occurring wanted (Bind _ _ (Pi _ _ _ ty) sc) met = occurring wanted sc (occurring wanted ty met)
  occurring wanted (Bind _ _ (PVar _ _ _ ty) sc) met = occurring wanted sc (occurring wanted ty met)
  occurring wanted (Bind _ _ (PVTy _ _ ty) sc) met = occurring wanted sc (occurring wanted ty met)
  occurring wanted (Meta _ _ _ args) met = occurringAll wanted args met
  occurring wanted (As _ _ _ p) met = occurring wanted p met
  occurring wanted (TDelayed _ _ t) met = occurring wanted t met
  occurring wanted (TDelay _ _ t a) met = occurring wanted a (occurring wanted t met)
  occurring wanted (TForce _ _ t) met = occurring wanted t met
  occurring wanted (Erased _ (Dotted t)) met = occurring wanted t met
  occurring _ _ met = met

  occurringAll : SortedSet Name -> List (TT vs) -> (SnocList Name, SortedSet Name) -> (SnocList Name, SortedSet Name)
  occurringAll wanted [] met = met
  occurringAll wanted (t :: ts) met = occurringAll wanted ts (occurring wanted t met)

||| What a hole marker of a dictionary's key stands for (`holedAt`): a
||| runtime value or a shape of the scope, of the type the walk knows,
||| where it knows one; or the one value the place a dictionary is bound at
||| holds, as the translation holds a variable that holds values
||| (`Terms.headed`): a dictionary known as a term that closes over values,
||| or what such a dictionary is settled over, of the type the values the
||| walk knows of it pack to, where it knows one.
data Marked = ARuntime (Maybe ClosedTerm) | AHolder BoundPlace (Maybe ClosedTerm)

||| A term closed as a dictionary's key holds it, its markers numbered by
||| first occurrence (`holedAt`): the key, each runtime value a hole marker
||| and each dictionary known as a term that closes over values its form,
||| whose values are the projections of its marker, as the translation's
||| key has it (`Terms.headed`); the same term with each such dictionary
||| its bare marker, which a reading of what the key holds reads as the one
||| value it holds (`heldIn`); and what each marker stands for.
record Holed where
  constructor MkHoled
  key : ClosedTerm
  marked : ClosedTerm
  markers : List Marked

||| A term closed as a dictionary's key holds it: every runtime value and
||| shape it mentions a hole marker, numbered by first occurrence, and every
||| dictionary known as a term that closes over values one marker too, as
||| the translation marks what an implementation closes over (`Holed`).
holedAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} -> Env vs -> TT vs -> Front Holed
holedAt env t = do
  let valued = positioned 0 env
      c = closeOver EmptyFC (map fst valued) t
      order = fst (occurring (SortedSet.fromList (mapMaybe snd (innermostFirst valued))) c ([<], empty)) <>> []
      numbered = zip [0 .. length order] order
  marks <- traverse (markedAt . snd) numbered
  -- A holder's form is put in first, over its own name, so that its
  -- values' projections take the holder's marker with every other name's.
  let filled = replacing (mapMaybe snd marks) c
  let renumbered = map (\(r, n) => (n, holeMarker r)) numbered
  pure (MkHoled (replacing renumbered filled) (replacing renumbered c) (map fst marks))
  where
    -- A runtime value, a shape, or a dictionary known as a term that
    -- closes over values, as a name of its own, by its place in the
    -- scope, which is renumbered once the term is closed.
    runtimeAt : Nat -> (ClosedTerm, Maybe Name)
    runtimeAt p = (probeTerm (ProbeRuntimeAt p), Just (probeName (ProbeRuntimeAt p)))

    value : Nat -> Standing -> (ClosedTerm, Maybe Name)
    value p (Runtime, _, _) = runtimeAt p
    value p (Pattern _, _, _) = runtimeAt p
    value p (Shape _, _, _) = runtimeAt p
    value p (Packs _, _, _) = runtimeAt p
    value p (Holds (Known _ (Just _)), _, _) = runtimeAt p
    value p (s, _, _) = (termOf s, Nothing)

    -- Each variable's value, by its place in the scope, the innermost 0.
    positioned : Nat -> ByVar ws Standing -> ByVar ws (ClosedTerm, Maybe Name)
    positioned p [] = []
    positioned p (x :: xs) = value p x :: positioned (S p) xs

    -- What stands at the place a name was made for: a runtime value as
    -- itself, of its type where the walk knows it; a dictionary known as
    -- a term as its form, its values the projections of the one value at
    -- its marker, which the place that binds it holds; what a dictionary
    -- is settled over, as itself, the one value its place holds.
    markedAt : Name -> Front (Marked, Maybe (Name, ClosedTerm))
    markedAt n = case probeOf n of
      Just pr@(ProbeRuntimeAt p) => case getAt p (innermostFirst env) of
        Just (Holds (Known _ (Just co)), _, _) => do
          values <- unpacked (valueTypes co) (probeTerm pr)
          packed <- packedType (valueTypes co)
          pure (AHolder co.binding (Just packed), Just (n, fillHoles values co.holedForm))
        Just (Packs b, _, ty) => pure (AHolder b ty, Nothing)
        Just (_, _, ty) => pure (ARuntime ty, Nothing)
        Nothing => pure (ARuntime Nothing, Nothing)
      _ => pure (ARuntime Nothing, Nothing)

||| A term closed as a dictionary's key holds it (`holedAt`).
holed : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} -> Env vs -> TT vs -> Front ClosedTerm
holed env t = do
  h <- holedAt env t
  pure h.key

||| What a key's markers stand for (`holedAt`), where the walk knows each
||| one's type: what a lambda or a dictionary known as a term closes over,
||| which the member or the variable it is holds as one value
||| (`Closed.packedType`). Nothing when the walk knows one's type not.
closingsOf : List Marked -> Maybe (List Closing)
closingsOf = traverse closing
  where
    closing : Marked -> Maybe Closing
    closing (ARuntime ty) = ValueOf <$> ty
    closing (AHolder b ty) = HolderOf b <$> ty

||| What a definition's leaves give at a node: a member of its result
||| type's choice, which a lambda there is, of that type; or a value.
data Giving = MemberLeaves ClosedTerm | ValueLeaves

||| What the walk knows of the writer: its address, how many parameters it
||| takes, and how its sites read them; the kind of each of its parameters
||| at the node, a static one's or none, which its own requests of itself
||| pass on; the definition whose text holds what it reads (for a field
||| type, the field's constructor), as it was read; its name for the
||| normalisers' messages, its location, which a site with no location of
||| its own takes, its definition, whose type names its parameters, by
||| which a message shows their markers, and what its leaves give.
record At where
  constructor MkAt
  writer : Address
  arity : Nat
  params : Parameters
  statics : List (Maybe Static)
  within : GlobalDef
  owner : String
  loc : FC
  writerDef : GlobalDef
  giving : Giving

||| A closed term as a message shows it: each marker of the writer's, and
||| each stand-in of the site's (`stands`), by the name the writer's type
||| gives the parameter it is a part of.
named : List Name -> List StandIn -> ClosedTerm -> ClosedTerm
named names stands t = replacing (mapMaybe nameFor (keys (getRefs (UN Underscore) t))) t
  where
    nameFor : Name -> Maybe (Name, ClosedTerm)
    nameFor n = do
      (i, _) <- standingOf stands n
      x <- getAt i names
      pure (n, Ref EmptyFC Bound x)

||| A written argument as a message shows it: each variable by the name it
||| was bound with, whatever a match made of it since, and each solved
||| metavariable as its solution. A name stands as the text it prints as,
||| which is no machine name, so that the solving's quotation keeps it. The
||| stand-ins are those the walk had made where it wrote the term.
display : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (names : List Name) -> List StandIn -> ByVar vs Name -> TT vs ->
          Front String
display names stands bound t = do
  shown <- traverseByVar shownAs bound
  showTT (named names stands !(solved (closeOver EmptyFC shown t)))
  where
    -- The text a name prints as becomes an identifier here, where the
    -- message is made.
    shownAs : Name -> Front ClosedTerm
    shownAs x = (\i => Ref EmptyFC Bound (UN (Basic i))) <$> core (intern (show x))

||| A site of the writer's, at its own location when it has none, made at
||| a place of its text, held in the field of its reach's role.
siteAt : At -> Place -> FC -> (reach : SiteReach) -> List Argument -> AtRole (ReachOf reach)
siteAt at place fc reach args =
  MkAtRole (MkMade place (MkSite at.writer at.writerDef at.params at.within reach args (if isEmptyFC fc then at.loc else fc))) Refl

||| The name a head is shown by: its definition's, as the boundary read
||| it; at an entry the context defines nothing at, the entry's.
headText : {auto c : Ref Ctxt Defs} -> HeadDef a -> Front String
headText (HeadDefined hd) = pure (show (fullname hd.defined.def))
headText (HeadUndefined _ _ entry _ _ _) = show <$> fullNames (Resolved entry)

||| The name the writer's type gives its parameter i, as a message shows it.
parameterName : (names : List Name) -> Nat -> String
parameterName names i = maybe "_" show (getAt i names)

mutual
  ||| A template as a message shows it, each marker by the writer's name for
  ||| its parameter, each head and each recursion by its definition's, as
  ||| the reading met it.
  render : {auto c : Ref Ctxt Defs} -> (names : List Name) -> (t : Template) -> All RecursionDef (recursions t) ->
           All HeadDef (namedHeads t) -> Front String
  render names (Var i _) _ _ = pure (parameterName names i)
  render names (PartField k i _) _ _ = pure (parameterName names i ++ "." ++ show k)
  render names (Head (Just a) []) _ [h] = headText h
  render names (Head (Just a) cs) held (h :: heads) =
    (\x, as => "(" ++ unwords (x :: as) ++ ")") <$> headText h <*> renderAll names cs held heads
  render names (Head Nothing cs) held heads = (\as => "(" ++ joinBy " -> " as ++ ")") <$> renderAll names cs held heads
  render names (Leaf _) _ _ = pure "_"
  render names (Token _) _ _ = pure "_"
  render names (Formal _ _) _ _ = pure "_"
  render names (Choice s ls) held heads =
    (\as => "{" ++ joinBy " | " as ++ "}") <$> renderAll names ls (allAfter (recursions s) held) (allAfter (namedHeads s) heads)
  render names (Opaque a cs) (r :: held) heads =
    (\as => "(" ++ unwords (show (fullname r.def) :: as) ++ ")") <$> renderAll names cs held heads
  render names (Applied i _ cs) held heads = (\as => "(" ++ unwords (parameterName names i :: as) ++ ")") <$> renderAll names cs held heads
  render names (Computing i _ cs) held heads = (\as => "(" ++ unwords (parameterName names i :: as) ++ ")") <$> renderAll names cs held heads
  render names (Field k t) held heads = (\s => s ++ "." ++ show k) <$> render names t held heads
  render names (Member (InterfaceHead a)) _ [h] = (\s => "{" ++ s ++ " the running program chooses}") <$> headText h
  render names (Member ArrowHead) _ _ = pure "{a polymorphic function the running program chooses}"
  render names (Member UnshownHead) _ _ = pure "{a member the running program chooses}"

  renderAll : {auto c : Ref Ctxt Defs} -> (names : List Name) -> (ts : List Template) -> All RecursionDef (recursionsIn ts) ->
              All HeadDef (namedHeadsIn ts) -> Front (List String)
  renderAll names [] _ _ = pure []
  renderAll names (t :: ts) held heads =
    (::) <$> render names t (allBefore (recursions t) held) (allBefore (namedHeads t) heads)
         <*> renderAll names ts (allAfter (recursions t) held) (allAfter (namedHeads t) heads)

------------------------------------------------------------------------------
-- What a type builds
------------------------------------------------------------------------------

mutual
  ||| A template with every child at a type constructor's position read by
  ||| its role (`Role`), at every head, the written ones and those
  ||| unfolding made alike: an `Index` as a closed part, a `Formed` shape as
  ||| its form (`formedTemplate`), and any other as itself. The data key
  ||| holds no more than this of each argument (`Types.argumentKey`), so a
  ||| height read here bounds the key's. A part read as a closed part takes
  ||| its recursions and its heads with it; every other part keeps its own.
  ||| A head is a type constructor by what the boundary read of it, which
  ||| the reading carries.
  eraseIn : (t : Template) -> All RecursionDef (recursions t) -> All HeadDef (namedHeads t) -> TemplateRead
  eraseIn (Head (Just a) cs) held (h :: heads) =
    let rs = case h of
               HeadDefined hd => case hd.defined.nature.asTypeConstructor of
                 ATypeConstructor facts => erasedAt facts.roles 0 cs held heads
                 NoTypeConstructor => eraseAll cs held heads
               -- Essential: an entry the context defines nothing at is no
               -- type constructor.
               HeadUndefined {} => eraseAll cs held heads in
    MkTemplateRead (Head (Just a) (templatesOf rs)) (allRead rs) (h :: allHeads rs)
  eraseIn (Head Nothing cs) held heads =
    let rs = eraseAll cs held heads in MkTemplateRead (Head Nothing (templatesOf rs)) (allRead rs) (allHeads rs)
  eraseIn (Choice t ls) held heads =
    let x = eraseIn t (allBefore (recursions t) held) (allBefore (namedHeads t) heads)
        rs = eraseAll ls (allAfter (recursions t) held) (allAfter (namedHeads t) heads) in
    MkTemplateRead (Choice x.template (templatesOf rs)) (allJoined x.recursionsRead (allRead rs)) (allJoined x.headsRead (allHeads rs))
  eraseIn (Opaque a cs) (def :: held) heads =
    let rs = eraseAll cs held heads in MkTemplateRead (Opaque a (templatesOf rs)) (def :: allRead rs) (allHeads rs)
  eraseIn (Applied i d cs) held heads =
    let rs = eraseAll cs held heads in MkTemplateRead (Applied i d (templatesOf rs)) (allRead rs) (allHeads rs)
  eraseIn (Computing i d cs) held heads =
    let rs = eraseAll cs held heads in MkTemplateRead (Computing i d (templatesOf rs)) (allRead rs) (allHeads rs)
  eraseIn (Field k t) held heads = let x = eraseIn t held heads in MkTemplateRead (Field k x.template) x.recursionsRead x.headsRead
  eraseIn (Var i d) held heads = MkTemplateRead (Var i d) held heads
  eraseIn (PartField k i d) held heads = MkTemplateRead (PartField k i d) held heads
  eraseIn (Leaf h) held heads = MkTemplateRead (Leaf h) held heads
  eraseIn (Token k) held heads = MkTemplateRead (Token k) held heads
  eraseIn (Formal j k) held heads = MkTemplateRead (Formal j k) held heads
  eraseIn (Member k) held heads = MkTemplateRead (Member k) held heads

  eraseAll : (ts : List Template) -> All RecursionDef (recursionsIn ts) -> All HeadDef (namedHeadsIn ts) -> List TemplateRead
  eraseAll [] _ _ = []
  eraseAll (t :: ts) held heads =
    eraseIn t (allBefore (recursions t) held) (allBefore (namedHeads t) heads)
      :: eraseAll ts (allAfter (recursions t) held) (allAfter (namedHeads t) heads)

  erasedAt : List Role -> Nat -> (ts : List Template) -> All RecursionDef (recursionsIn ts) -> All HeadDef (namedHeadsIn ts) ->
             List TemplateRead
  erasedAt rs j [] _ _ = []
  erasedAt rs j (t :: ts) held heads =
    asRole (roleAt j rs) t (allBefore (recursions t) held) (allBefore (namedHeads t) heads)
      :: erasedAt rs (S j) ts (allAfter (recursions t) held) (allAfter (namedHeads t) heads)

  -- The part at a position read by its role, recursing on the part itself,
  -- so that each step down is to a part of what was given.
  asRole : Role -> (t : Template) -> All RecursionDef (recursions t) -> All HeadDef (namedHeads t) -> TemplateRead
  asRole Keyed t held heads = eraseIn t held heads
  asRole Formed t held heads = formedTemplate t held heads
  asRole Held t held heads = eraseIn t held heads
  asRole Index _ _ _ = MkTemplateRead (Leaf 1) [] []

||| The site a type constructor's head writes: `Builds` of it, as the
||| boundary read it, at the arguments a value of it represents, each
||| already read without what no value represents, with the definitions of
||| the recursions it holds and the heads it names; none for a head that is
||| no type constructor.
built : At -> Place -> FC -> (a : Address) -> HeadDef a -> List TemplateRead -> List (AtRole BuildReach)
built at place fc a h cs = case h of
    HeadDefined hd => case hd.defined.nature.asTypeConstructor of
      ATypeConstructor facts => [siteAt at place fc (Builds a hd.defined) (map argument (mapMaybe (\j => (j,) <$> getAt j cs) (represented facts)))]
      NoTypeConstructor => []
    -- Essential: an entry the context defines nothing at builds nothing.
    HeadUndefined {} => []
  where
    -- A part of a type already read, with no term of its own to root.
    argument : (Nat, TemplateRead) -> Argument
    argument (j, t) =
      MkArgument j AType t.template t.recursionsRead Unrooted TypeHeads Nothing [] Nothing NoTerm []
                 (TemplateText at.writerDef t.template t.recursionsRead t.headsRead)

mutual
  ||| The sites at every type constructor of a template, at any depth: in a
  ||| stuck definition's leaves, in an unfolded synonym, under a binder.
  buildsIn : At -> Place -> FC -> (t : Template) -> All RecursionDef (recursions t) -> All HeadDef (namedHeads t) ->
             List (AtRole BuildReach)
  buildsIn at place fc (Head (Just a) cs) held (h :: heads) = built at place fc a h (eachRead cs held heads) ++ buildsAll at place fc cs held heads
  buildsIn at place fc (Head Nothing cs) held heads = buildsAll at place fc cs held heads
  buildsIn at place fc (Choice t ls) held heads =
    buildsIn at place fc t (allBefore (recursions t) held) (allBefore (namedHeads t) heads)
      ++ buildsAll at place fc ls (allAfter (recursions t) held) (allAfter (namedHeads t) heads)
  buildsIn at place fc (Opaque _ cs) (_ :: held) heads = buildsAll at place fc cs held heads
  buildsIn at place fc (Applied _ _ cs) held heads = buildsAll at place fc cs held heads
  buildsIn at place fc (Computing _ _ cs) held heads = buildsAll at place fc cs held heads
  buildsIn at place fc (Field _ t) held heads = buildsIn at place fc t held heads
  buildsIn at place fc (Var _ _) _ _ = []
  buildsIn at place fc (PartField _ _ _) _ _ = []
  buildsIn at place fc (Leaf _) _ _ = []
  buildsIn at place fc (Token _) _ _ = []
  buildsIn at place fc (Formal _ _) _ _ = []
  buildsIn at place fc (Member _) _ _ = []

  buildsAll : At -> Place -> FC -> (ts : List Template) -> All RecursionDef (recursionsIn ts) -> All HeadDef (namedHeadsIn ts) ->
              List (AtRole BuildReach)
  buildsAll at place fc [] _ _ = []
  buildsAll at place fc (t :: ts) held heads =
    buildsIn at place fc t (allBefore (recursions t) held) (allBefore (namedHeads t) heads)
      ++ buildsAll at place fc ts (allAfter (recursions t) held) (allAfter (namedHeads t) heads)

||| What a closed type, a term of a site whose stand-ins are those the walk
||| has made, builds where the walk is: its canonical form as data
||| instances compare type arguments, its template, and that without what
||| no value of each type constructor in it represents, so that a head
||| inside an index builds nothing.
builds : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> At -> Pats -> FC -> ClosedTerm -> Front (List (AtRole BuildReach))
builds at ps fc t = do
  written <- templateOf ps.made AType !(canonicalTypeArg t)
  let erased = eraseIn written.template written.recursionsRead written.headsRead
  pure (buildsIn at ps.place fc erased.template erased.recursionsRead erased.headsRead)

------------------------------------------------------------------------------
-- Sites of calls
------------------------------------------------------------------------------

||| An argument of an application, made where it is a subterm (`origin`,
||| its scope there): as written there, and where its taker is (`written`,
||| the binders between taken in by `thinned`), and its walks as code, as a
||| static value, as a member applied at a use of a type (`useOf`), and as
||| the computation a match that finds it stuck computes
||| (`computedField`), each suspended where it is a subterm, so each walk
||| is in the scope it is written in.
record Arg (vs : Scope) where
  constructor MkArg
  {origin : Scope}
  thinned : Thin origin vs
  original : TT origin
  written : TT vs
  asCode : Lazy (Front (CodeNode AtRole origin))
  asStatic : Lazy (Front (StaticNode AtRole origin))
  asUse : ClosedTerm -> Front (UseNode AtRole origin)
  asComputed : Lazy (Front (ComputedNode AtRole origin))

||| An argument under a binder the walk binds.
overBinder : Arg vs -> Arg (x :: vs)
overBinder a = MkArg (Drop a.thinned) a.original (weaken a.written) a.asCode a.asStatic a.asUse a.asComputed

||| An argument where its taker holds it, as the taker took it.
argNode : (a : Arg vs) -> TakenAs AtRole a.origin -> ArgNode AtRole vs
argNode a t = MkArgNode a.thinned a.original t

||| A closed value as an argument, a compile-time value or a marker, whose
||| walks write nothing: it holds no application of the program's.
closedArg : {vs : Scope} -> ClosedTerm -> Arg vs
closedArg t =
  let tm = embedClosed t in
  MkArg Refl tm tm (pure (MkCodeNode tm CodeInert)) (pure (MkStaticNode tm StaticInert)) (\_ => pure (MkUseNode tm UseInert))
        (pure (ComputedCode (MkCodeNode tm CodeInert)))

||| Arguments each walked as a static value.
statics : List (Arg vs) -> Front (List (ArgNode AtRole vs))
statics xs = traverse (\x => argNode x . TakenWalked . WalkedStatic <$> Force x.asStatic) xs

||| An argument as a callee's kinds are decided on: closed with what each
||| variable stands for, each a marker or a stand-in of its own, and what
||| the call knows of it: a variable that holds a dictionary is an
||| implementation.
record Offered (vs : Scope) where
  constructor MkOffered
  arg : Arg vs
  value : ClosedTerm
  offer : Offer

offered : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> Pats -> Env vs -> Arg vs -> Front (Offered vs)
offered ps env a = (\v => MkOffered a v (offerOf env a.written)) <$> solved (close env a.written)

||| How a callee's type takes an argument: as a static value of a kind,
||| walked as one; at runtime, walked as code; or erased, passed nowhere
||| by the translation.
data Taking = AsStatic Static | AsCode | Nowhere

||| One argument of a call, whole, as the callee's type takes it: offered,
||| at its position among the callee's parameters, how it is taken, and the
||| type of the binder that takes it, the site's earlier arguments put in.
record Given (vs : Scope) where
  constructor MkGiven
  offer : Offered vs
  position : Nat
  taking : Taking
  binder : ClosedTerm

||| The type of each binder a type shows, each argument given put in for
||| the binder that takes it.
bindersAlong : {auto c : Ref Ctxt Defs} -> ClosedTerm -> List ClosedTerm -> Front (List ClosedTerm)
bindersAlong ty [] = pure []
bindersAlong ty (v :: vs) = do
  Bind _ _ (Pi _ _ _ a) sc <- showingBinder ty
    | _ => pure []
  (a ::) <$> bindersAlong (subst v sc) vs

||| The arguments a callee's type takes, each decided once, by its kind
||| (`staticsOver`) and, for one of none, by what the callee takes there
||| (`positions`: its definition's, or a computed type's); and the rest of
||| the type. An argument past every position the type shows is given
||| nowhere: no binder of the callee takes it.
taken : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
        At -> Pats -> Env vs -> ClosedTerm -> (positions : List ArgumentAt) -> List (Arg vs) ->
        Front (List (Given vs), ClosedTerm)
taken at ps env ty positions args = do
  os <- traverse (offered ps env) args
  (kinds, rest) <- staticsOver at.owner (length args) ty (map (\o => Just (o.value, o.offer)) os)
  binders <- bindersAlong ty (map (.value) os)
  pure (decided 0 os (toList (map staticOf kinds)) positions binders, rest)
  where
    taking : Maybe Static -> ArgumentAt -> Taking
    taking (Just k) _ = AsStatic k
    taking Nothing (RuntimeValue _) = AsCode
    taking Nothing _ = Nowhere

    decided : Nat -> List (Offered vs) -> List (Maybe Static) -> List ArgumentAt -> List ClosedTerm -> List (Given vs)
    decided j (o :: os) (k :: ks) (p :: rs) (b :: bs) = MkGiven o j (taking k p) b :: decided (S j) os ks rs bs
    decided _ _ _ _ _ = []

||| A definition by name, as the boundary read it (`Errors.defined`): its
||| address and what was read of it.
definitionOf : Name -> Front (Maybe (Address, Defined))
definitionOf n = map (\d => (addressOf d.placement, d)) <$> defined n

||| Whether a definition's body, as the boundary read it, is one leaf.
oneLeaf : Defined -> Bool
oneLeaf d = case d.matched of
  Just m => case leafOf m of
    Just _ => True
    Nothing => False
  Nothing => False

||| One value a dictionary's spine holds, as the packing finds it: a
||| runtime value, by its type; or the one value a dictionary of the
||| writer's holds (`OwnHolder`), its values packed into one. Two closings
||| of one spine are compared by these (`packings`).
data InSpine = ValueOfType ClosedTerm | ValuesOf OwnHolder

Eq InSpine where
  ValueOfType a == ValueOfType b = a == b
  ValuesOf a == ValuesOf b = a == b
  _ == _ = False

||| One argument of a dictionary's spine, as the packing reads it: as its
||| key holds it, each runtime value a hole marker, which says whether it
||| is held; as a later binder's type has it put in (`heldIn`); and the
||| values it holds itself, where it is a compile-time value.
record HeldPart where
  constructor MkHeldPart
  keyed : ClosedTerm
  putIn : ClosedTerm
  inner : Lazy (Front (List InSpine))

||| The writer's dictionary parameter a reference stands for, whose values
||| it holds: its marker, or a field matched out of it, which the
||| translation gives the parameter's values (`Cases.staticCase`). A
||| parameter of another kind holds none; a position past the writer's
||| own is a use's, whose kind only the use decides.
dictionaryParameter : (statics : List (Maybe Static)) -> Name -> Maybe Nat
dictionaryParameter statics n = probeOf n >>= parameter
  where
    holding : Nat -> Maybe Nat
    holding i = case getAt i statics of
      Just (Just ADictionary) => Just i
      Just _ => Nothing
      Nothing => Just i

    parameter : Probe -> Maybe Nat
    parameter (ProbePart i _) = holding i
    parameter (ProbeFieldPath i _) = holding i
    parameter _ = Nothing

||| What an argument of a spine mentions that a dictionary holds: a runtime
||| value or a dictionary known as a term that closes over values (a hole
||| marker), or a dictionary parameter of the writer that may hold values,
||| each of which the translation holds where the argument is computed
||| from them (`Terms.holed`); or nothing held.
data Mentioning = MentionsHeld | MentionsNothing

mentioningIn : List (Maybe Static) -> ClosedTerm -> Mentioning
mentioningIn statics t =
  if mentionsHole t || any (\n => isJust (dictionaryParameter statics n)) (keys (getRefs (UN Underscore) t))
    then MentionsHeld else MentionsNothing

||| What a reference given alone holds as one value: a dictionary parameter
||| of the writer, or a field matched out of one, its values packed into
||| one; a dictionary known as a term that closes over values, by the
||| marker the key gives it (`Holed.marked`), the one value the place that
||| binds it holds (`Terms.headed`). A runtime value's marker is a value of
||| its binder's type, which the spine reads there.
heldAs : List (Maybe Static) -> (holders : List Marked) -> Name -> Maybe InSpine
heldAs statics holders n = case dictionaryParameter statics n of
  Just i => Just (ValuesOf (OwnParameter i))
  Nothing => Readings.markerOf n >>= \r => getAt r holders >>= holder
  where
    holder : Marked -> Maybe InSpine
    holder (AHolder b _) = Just (ValuesOf (OwnBinding b))
    holder (ARuntime _) = Nothing

||| The dictionary parameters of the writer a term closed as a key holds it
||| mentions (`Holed.marked`), or fields matched out of one, each once:
||| written as they are, or in a dictionary known as a term that closes
||| over no value whose type the walk knows, which the key holds as it is
||| written. Each is the one value it holds, which the translation holds
||| among what the term closes over (`Terms.holed`). A dictionary that
||| closes over values is a marker of the key, and holds its own.
ownersIn : List (Maybe Static) -> ClosedTerm -> List Nat
ownersIn statics t = nub (mapMaybe (dictionaryParameter statics) (keys (getRefs (UN Underscore) t)))

mutual
  ||| What a dictionary closes over, in the order the translation finds it
  ||| (`Terms.holed`): each argument a definition that gives a dictionary
  ||| takes at a runtime parameter that is no dictionary, where the argument
  ||| as its key holds it (`keyed`, `Holed.marked`) mentions a runtime value
  ||| or a dictionary parameter of the writer's, a value of that parameter's
  ||| type, each earlier argument put in as `putIn` has it; a compile-time
  ||| value there (an implementation, a polymorphic function:
  ||| `compileTimeBinder`) is looked into; and a dictionary parameter of the
  ||| writer's, or a dictionary known as a term that closes over values, as
  ||| it is, the one value it holds (`heldAs`, by the key's markers
  ||| `holders`). The two terms are one term closed two ways, so their
  ||| spines are one.
  ||| A value two parameters share is listed at each: the translation holds
  ||| it once, so the packing below is never shorter than its.
  heldIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           List (Maybe Static) -> (holders : List Marked) -> (keyed, putIn : ClosedTerm) -> Front (List InSpine)
  heldIn statics holders keyed putIn = heldSpine statics holders keyed putIn []

  heldSpine : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              List (Maybe Static) -> (holders : List Marked) -> (keyed, putIn : ClosedTerm) -> List HeldPart ->
              Front (List InSpine)
  heldSpine statics holders (App _ f a) (App _ f' a') args =
    heldSpine statics holders f f' (MkHeldPart a a' (heldIn statics holders a a') :: args)
  heldSpine statics holders (Ref _ _ n) _ args = case (heldAs statics holders n, args) of
    (Just v, []) => pure [v]
    _ => do
      Just (_, d) <- definitionOf n
        | Nothing => pure []
      case definition d.def of
        -- A definition of one right-hand side.
        PMDef {} => if oneLeaf d then heldOver statics holders d.def 0 d.type args else pure []
        DCon {} => heldOver statics holders d.def 0 d.type args
        _ => pure []
  heldSpine statics holders _ _ _ = pure []

  -- The arguments from position `j` of the definition on, its type there
  -- `ty`, what it takes at each read as the definition's (`argumentAt`).
  heldOver : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             List (Maybe Static) -> (holders : List Marked) -> GlobalDef -> (j : Nat) -> ClosedTerm -> List HeldPart ->
             Front (List InSpine)
  heldOver statics holders def j ty [] = pure []
  heldOver statics holders def j ty (x :: rest) = do
    Bind _ _ (Pi _ rig _ aty) sc <- normaliseClosed ty
      | _ => pure []
    here <- case argumentAt def j rig of
              RuntimeValue _ => case mentioningIn statics x.keyed of
                MentionsNothing => pure []
                MentionsHeld => do
                  aty' <- normaliseClosed aty
                  if !(compileTimeBinder rig aty') then Force x.inner else pure [ValueOfType aty']
              _ => pure []
    (here ++) <$> heldOver statics holders def (S j) (subst x.putIn sc) rest

||| A static argument at a position, read off the closed term its key holds
||| at its kind (`rooted`), a term of a site whose stand-ins are `stands`,
||| as its target is given it, a member of the choice `memberOf` where the
||| running program chooses it (`asGiven`), with how a message shows it.
export
readArgument : {auto c : Ref Ctxt Defs} -> List StandIn -> Nat -> Static -> (memberOf : Maybe ChoiceHead) -> ClosedTerm ->
               ArgumentText -> Front Argument
readArgument stands j k memberOf t shown = argumentOf <$> rooted stands k t
  where
    argumentOf : (SiteReading k t, ArgumentRoot k) -> Argument
    argumentOf (r, (root ** heads)) =
      MkArgument j k (asGiven memberOf (r.template, root)) (givenRecursions memberOf r.template root r.recursionsRead) root heads
                 (Just t) stands memberOf (OffTerm r) [] shown

||| The pair Idris's `%pair` names and its two projections, as the boundary
||| read them once (`State.Pairing`); nothing for a program that declares
||| no `%pair`.
export
pairingOf : Front (Maybe Pairing)
pairingOf = (.pair) <$> reading

||| What holding values as one reaches: the pair that holds the first and
||| the rest, and its projections, which the holder takes them apart with
||| (`Closed.unpacked`). What each is given is a list of the values a
||| dictionary holds, which no writer's site knows (a match that finds a
||| field stuck holds it after the values its writer was given, and a
||| dispatch on it puts a member's values in its place), so it is written
||| from each dictionary's held position (`Graph.heldPackings`), and these
||| sites write nothing.
pairReached : At -> Place -> FC -> Front (Maybe (PairSites AtRole))
pairReached at place fc = map reached <$> pairingOf
  where
    reached : Pairing -> PairSites AtRole
    reached pg = MkPairSites (siteAt at place fc (Builds pg.pairAddress pg.pairDefined) [])
                             (siteAt at place fc (Calls pg.firstAddress pg.firstDefined) [])
                             (siteAt at place fc (Calls pg.secondAddress pg.secondDefined) [])

||| One list of values a place holds as one (`Closed.packedType`), as the
||| list's receiver is given it: each value as it holds it (`HeldItem`),
||| with the sites of the types each runtime value's type builds and, for
||| two or more, the pair and its projections, reached (`pairReached`),
||| where the walk is.
heldOne : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          At -> Pats -> FC -> List1 InSpine -> Front (List1 HeldItem, HeldSites AtRole)
heldOne at ps fc (v ::: vs) = do
  list <- items 0 v vs
  inner <- traverse built (v :: vs)
  paired <- case vs of
              [] => pure Nothing
              _ :: _ => pairReached at ps.place fc
  pure (list, MkHeldSites (inner >>= id) paired)
  where
    item : Nat -> InSpine -> Front HeldItem
    item j (ValueOfType u) = (\x => OfType (x ::: [])) <$> readArgument ps.made j AType Nothing u (TermText u)
    item j (ValuesOf h) = pure (PackedBy h)

    items : Nat -> InSpine -> List InSpine -> Front (List1 HeldItem)
    items j u [] = (::: []) <$> item j u
    items j u (w :: ws) = (\x, rest => x ::: forget rest) <$> item j u <*> items (S j) w ws

    built : InSpine -> Front (List (AtRole BuildReach))
    built (ValueOfType u) = builds at ps fc u
    built (ValuesOf _) = pure []

||| The lists of values a place holds as one: no value is no list.
held : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
       At -> Pats -> FC -> List InSpine -> Front (List (List1 HeldItem), List (HeldSites AtRole))
held at ps fc [] = pure ([], [])
held at ps fc (v :: vs) = (\(l, h) => ([l], [h])) <$> heldOne at ps fc (v ::: vs)

||| The lists of values a dictionary or a member closes over (`held`), one
||| written term closed two ways: each earlier argument a later binder's
||| type depends on put in as its key holds it (`keyed`), a hole marker
||| where it is a runtime value or a dictionary known as a term that closes
||| over values; or as the site knows it (`shaped`), a shape it matched as
||| that shape. An instance that holds such an argument's whole shape puts
||| the shape in, a compile-time value, so a value's type there can be
||| taller than any part of the one with holes, which the shape's
||| stand-ins bound; one that does not puts a hole in, whose token the
||| keyed list weighs. Where both read alike, there is one list.
packings : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
           At -> Pats -> FC -> (keyed : Holed) -> (shaped : ClosedTerm) -> Front (List (List1 HeldItem), List (HeldSites AtRole))
packings at ps fc h shaped = do
  keyed <- solved h.marked
  holes <- heldIn at.statics h.markers keyed keyed
  shapes <- heldIn at.statics h.markers keyed shaped
  if shapes == holes then held at ps fc holes else do
    (hs, hsites) <- held at ps fc holes
    (ss, ssites) <- held at ps fc shapes
    pure (hs ++ ss, hsites ++ ssites)

||| A dictionary known as a term, as the walk binds it (`Known`): closed as
||| every term is, and, where it closes over values whose types the walk
||| knows (runtime values, and dictionaries other places bind, each the one
||| value it holds), its place in the writer's text, which holds what it
||| closes over as one, its form with a hole marker for each value, what
||| each marker stands for, and the writer's dictionary parameters it
||| mentions; a settling of it holds them as one variable, as the
||| translation's does (`Terms.standingFor`).
knownAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} -> At -> Pats -> Env vs -> TT vs -> Front Dict
knownAt at ps env t = do
  closed <- solved (close env t)
  h <- holedAt env t
  case closingsOf h.markers of
    Just (m :: ms) =>
      (\f => Known closed (Just (MkClosedOver (MkBoundPlace ps.place) f (m ::: ms) (ownersIn at.statics h.marked))))
        <$> solved h.key
    _ => pure (Known closed Nothing)

||| One value a dictionary known as a term closes over, as its list holds
||| it: a runtime value by its type, or the one value a dictionary another
||| place binds holds.
closedItem : Closing -> InSpine
closedItem (ValueOf ty) = ValueOfType ty
closedItem (HolderOf b _) = ValuesOf (OwnBinding b)

||| The list a dictionary known as a term holds as one, which the place
||| that binds it keeps: what its markers stand for, and each dictionary
||| parameter of the writer it mentions, the one value it holds.
heldValues : ClosedOver -> List1 InSpine
heldValues co = appendl (map closedItem co.closings) (map (ValuesOf . OwnParameter) co.owners)

||| The one value a dictionary known as a term holds, where it is given as
||| it is: what it closes over, held as one at the place that binds it, as
||| the translation holds a variable that holds values (`Terms.holed`).
knownHeld : ClosedOver -> List (List1 HeldItem)
knownHeld co = [PackedBy (OwnBinding co.binding) ::: []]

||| A dictionary given as a variable that holds one known as a term that
||| closes over values, with what it closes over.
knownGiven : Env vs -> TT vs -> Maybe ClosedOver
knownGiven env (Local _ _ idx p) = case lookupVar idx p env of
  (Holds (Known _ (Just co)), _, _) => Just co
  _ => Nothing
knownGiven _ _ = Nothing

||| What a dictionary known as a term holds as one value where it is bound
||| (`Terms.letIn`): its list, which its place keeps, with the types each
||| runtime value's type builds and, for two values or more, the pair and
||| its projections reached (`held`), whose arguments the place's held
||| positions write (`Graph.heldPackings`). The writer's own dictionary is
||| packed where its writer was given it, and one that closes over no value
||| whose type the walk knows has no place of its own: where it is given,
||| what it mentions is read as it is written.
heldBy : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> At -> Pats -> FC -> Dict -> Front (KeptAt AtRole)
heldBy at ps fc (Known _ (Just co)) = do
  (list, sites) <- heldOne at ps fc (heldValues co)
  pure (KeepsList (siteAt at ps.place fc (Keeps co.binding list) []) sites)
heldBy at ps fc (Known _ Nothing) = pure KeepsNothing
heldBy at ps fc (Own _ _) = pure KeepsNothing

||| The type a suspension holds, of a suspension's type; any other as it is:
||| a lambda given delayed where a delayed one is held is the member of the
||| type held.
undelayed : ClosedTerm -> ClosedTerm
undelayed (TDelayed _ _ t) = t
undelayed t = t

||| The head of the choice a value at a binder of this type is a member of,
||| delayed or not, normalised (`choiceHeadOf`).
choiceAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> ClosedTerm -> Front ChoiceHead
choiceAt ty = choiceHeadOf !(normaliseClosed (undelayed ty))

||| Whether a value of a choice of a head is applied at a use: a
||| polymorphic function's member is, at each use of its choice, and so
||| may one be whose head only an instance shows, which an instance may
||| show to be the arrow; an implementation never is.
data UseApplies = AppliedAtUse | NeverApplied

applicationOf : ChoiceHead -> UseApplies
applicationOf ArrowHead = AppliedAtUse
applicationOf UnshownHead = AppliedAtUse
applicationOf (InterfaceHead _) = NeverApplied

||| What a use applies, of a member of the choice of a head: the walk `use`
||| makes, where its members are applied at a use (`applicationOf`).
whereApplied : ChoiceHead -> Lazy (Front a) -> Front (Maybe a)
whereApplied k use = case applicationOf k of
  AppliedAtUse => Just <$> use
  NeverApplied => pure Nothing

||| One static argument, closed as its key holds it at its kind, and read
||| (`rooted`): a type, family, form or shape as written over the markers
||| and the site's stand-ins (a type's template reads it in full normal
||| form); a dictionary with what it closes over as hole markers, so that
||| its template and its root read one closed term, and as the callee is
||| given it (`asGiven`): one the running program chooses is a member of
||| the choice of the binder's type, which the translation dispatches on.
||| A dictionary holds the lists of values it closes over (`packings`), or,
||| given as a variable that holds a dictionary known as a term, the one
||| value that variable holds (`knownHeld`). With the sites of the types a
||| type or a family builds, and of those its held values' types build.
argument : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> Given vs -> Static -> Front (Argument, Beside AtRole)
argument at ps env fc g k = do
  (v, beside) <- the (Front (ClosedTerm, Front (List (List1 HeldItem), Beside AtRole))) $ case k of
    AType => pure (g.offer.value, (\ss => ([], BuildsBeside ss)) <$> builds at ps fc g.offer.value)
    AFamily => pure (g.offer.value, (\ss => ([], BuildsBeside ss)) <$> builds at ps fc g.offer.value)
    AForm => pure (g.offer.value, pure ([], NothingBeside))
    AShape => pure (g.offer.value, pure ([], NothingBeside))
    ADictionary => do
      h <- holedAt env g.offer.arg.written
      d <- solved h.key
      shaped <- solved (close env g.offer.arg.written)
      pure (d, case knownGiven env g.offer.arg.written of
                 Just co => pure (knownHeld co, HeldBeside [])
                 Nothing => (\(ls, hs) => (ls, HeldBeside hs)) <$> packings at ps fc h shaped)
  memberOf <- case k of
    ADictionary => Just <$> choiceAt g.binder
    _ => pure Nothing
  x <- readArgument ps.made g.position k memberOf v (WrittenText at.writerDef ps.made (map (\(_, x, _) => x) env) g.offer.arg.written)
  (lists, sites) <- beside
  pure ({ holds := lists } x, sites)

||| A site reaching a target at the static arguments of those given, with
||| the sites of the types its type arguments build.
callSite : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> (reach : SiteReach) -> List (Given vs) -> Front (Requested AtRole (ReachOf reach))
callSite at ps env fc reach gs = do
  ws <- traverse (\(g, k) => argument at ps env fc g k) (mapMaybe static gs)
  pure (MkRequested (siteAt at ps.place fc reach (map fst ws)) (map snd ws))
  where
    static : Given vs -> Maybe (Given vs, Static)
    static g = case g.taking of
      AsStatic k => Just (g, k)
      AsCode => Nothing
      Nowhere => Nothing

||| A member of the choice of head `k` that the place makes, `written`
||| closed as a dictionary's key holds it (`d`, its runtime values hole
||| markers), with the lists of values it holds as one and their sites:
||| the member writes its form at its choice's position, which every
||| dispatch on the choice reads (`Translate.Choices`), and holds the lists
||| as a dictionary argument does (`argument`). What its body requests at a
||| use is its use's walk (`useOf`).
memberAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> (k : ChoiceHead) -> HeadRead k -> (d : ClosedTerm) ->
           (packed : (List (List1 HeldItem), List (HeldSites AtRole))) -> TT vs -> Front (MemberAt AtRole)
memberAt at ps env fc k named d (lists, packed) written = do
  x <- readArgument ps.made 0 ADictionary Nothing d (WrittenText at.writerDef ps.made (map (\(_, x, _) => x) env) written)
  pure (MkMemberAt (siteAt at ps.place fc (Makes k named) [{ holds := lists } x]) packed)

||| A lambda where the member table says a member stands: the member of its
||| type's choice (`Translate.Terms.member`), of a polymorphic function
||| type, whose head is the arrow, written at its choice's position
||| (`memberAt`), holding the runtime values of the scope it mentions and
||| each dictionary holding values it mentions: one known as a term at its
||| key's marker (`holedAt`), the one value its place holds, and the
||| writer's own (`ownersIn`). A lambda is a value, so the program fixes
||| it.
lambdaAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> TT vs -> Front (MemberAt AtRole)
lambdaAt at ps env fc lam = do
  h <- holedAt env lam
  d <- solved h.key
  -- A value the walk binds with no type (a case's field past the binders
  -- its constructor's type shows) is held with nothing it knows of the
  -- pair's halves, so the list is left out with it.
  packed <- case closingsOf h.markers of
    Just closings => held at ps fc (map closedItem closings ++ map (ValuesOf . OwnParameter) (ownersIn at.statics h.marked))
    Nothing => pure ([], [])
  memberAt at ps env fc ArrowHead ArrowRead d packed lam

||| What a value of a type the instance decides is, the type the site's
||| arguments give, delayed or not, normalised: a member of its type's
||| choice, no member, or what only an instance decides, by the one rule the
||| translation reads (`Types.typeHolding`). Over markers an undecided head
||| is a value an instance puts in, so the walk takes the value both ways.
holdingAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> ClosedTerm -> Front Holding
holdingAt ty = typeHolding !(normaliseClosed (undelayed ty))

||| The arguments a use gives a member of type `ty`, the term `member`: one
||| at each binder the type shows, and at each lambda the member takes its
||| arguments with past them, which an instance's type shows binders for
||| where this one shows none (a type the writer's variable heads, or a
||| definition its markers leave stuck); each the position of the
||| application the use gives it (`Parameters`), a marker past the
||| writer's own parameters, position 2 the first, past the type and the
||| form.
useArguments : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> {0 ws : Scope} -> At -> ClosedTerm -> (member : TT ws) -> Front (List (Arg vs))
useArguments at ty member = do
  normal <- normaliseClosed ty
  arguments (max (shown normal) (lambdas member)) 2 (Just normal)
  where
    -- The binders a normal form shows.
    shown : TT us -> Nat
    shown (Bind _ _ (Pi {}) sc) = S (shown sc)
    shown _ = Z

    -- The lambdas a term takes its arguments with.
    lambdas : TT us -> Nat
    lambdas (Bind _ _ (Lam {}) sc) = S (lambdas sc)
    lambdas _ = Z

    -- Past the binders the type shows, an argument has no binder's type
    -- to be put in for.
    arguments : Nat -> (position : Nat) -> Maybe ClosedTerm -> Front (List (Arg vs))
    arguments Z _ _ = pure []
    arguments (S n) j t = do
      let x = markerAt (at.arity + j) []
      rest <- the (Front (Maybe ClosedTerm)) $ case t of
        Just t' => do
          Bind _ _ (Pi {}) sc <- showingBinder t'
            | _ => pure Nothing
          pure (Just (subst x sc))
        Nothing => pure Nothing
      (closedArg x ::) <$> arguments n (S j) rest

||| The member a variable that holds the writer's own dictionary (its
||| parameter, or a field matched out of it) makes where a binder takes
||| one: each instance fixes that dictionary, and settles it where it is
||| written as the implementation it is there, a member of its type's
||| choice (`Translate.Terms.implementationAt`, `Choices.memberBare`). It
||| is written at its choice's position as the writer's argument there,
||| over the writer's markers, holding the values the writer was given it
||| with, as a dictionary argument holds them (`argument`). Any other
||| variable makes none here: a dictionary the running program chose is a
||| member of its choice already, and one known as a term is settled and
||| walked as code, where a definition applied gives its own
||| (`definitionMember`).
ownMember : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
            At -> Pats -> Env vs -> FC -> (ty : ClosedTerm) -> TT vs -> Front (Maybe (MemberAt AtRole))
ownMember at ps env fc ty written@(Local _ _ idx p) = case lookupVar idx p env of
  (Holds (Own _ _), _, _) => do
    (k ** named) <- choiceReadOf !(normaliseClosed (undelayed ty))
    h <- holedAt env written
    d <- solved h.key
    shaped <- solved (close env written)
    Just <$> memberAt at ps env fc k named d !(packings at ps fc h shaped) written
  _ => pure Nothing
ownMember at ps env fc ty _ = pure Nothing

||| The member an argument at a binder of type `ty` that takes one makes: a
||| lambda there, or one delayed, is that member; a variable that holds the
||| writer's own dictionary makes the one each instance fixes it to
||| (`ownMember`); anything else makes its member as code, where a
||| definition applied gives its own (`definitionMember`). A member of a
||| polymorphic function's choice is applied at each use of the choice, so
||| its use's walk is made here, once (`Arg.asUse`).
memberMade : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
             At -> Pats -> Env vs -> FC -> (ty : ClosedTerm) -> (a : Arg vs) -> Front (MemberNode AtRole a.origin)
memberMade at ps env fc ty a = do
  made <- case a.written of
    lam@(Bind lfc _ (Lam {}) _) => Just <$> lambdaAt at ps env lfc lam
    TDelay _ _ _ lam@(Bind lfc _ (Lam {}) _) => Just <$> lambdaAt at ps env lfc lam
    other => ownMember at ps env fc ty other
  used <- whereApplied !(choiceAt ty) (a.asUse (undelayed ty))
  pure (MkMemberNode made used)

||| An argument at a binder of type `ty` that takes a member: the member it
||| makes (`memberMade`), and its walk as code.
atMember : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> (ty : ClosedTerm) -> (a : Arg vs) -> Front (TakenAs AtRole a.origin)
atMember at ps env fc ty a = TakenMember <$> memberMade at ps env fc ty a <*> Force a.asCode

||| The type of a definition after its arguments, each put in for the binder
||| that takes it, normalised.
typeAfter : {auto c : Ref Ctxt Defs} -> ClosedTerm -> List ClosedTerm -> Front ClosedTerm
typeAfter ty [] = normaliseClosed ty
typeAfter ty (v :: vs) = do
  Bind _ _ (Pi {}) sc <- showingBinder ty
    | shown => normaliseClosed shown
  typeAfter (subst v sc) vs

||| A definition applied as code where what it gives after its arguments is
||| a member (`givesAfter`; where the instance decides, the type `after`
||| them says, and where only an instance can, it may be one): the member
||| of its type's choice (`Translate.Terms.applyDefined`'s `memberHere`,
||| which reads every definition applied so, whatever its kind: an
||| interface's constructor applied builds an implementation as a function
||| that gives one does), written at its choice's position (`memberAt`),
||| the unshown head's where the type shows none. The application is
||| written as Idris writes it, its head the reference `reference` names
||| (a constructor's by its tag and arity), which is how the reading of a
||| dictionary tells a constructor from a function. Essential: a value no
||| compile-time reduction fixes is a choice, no member.
definitionMember : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                   At -> Pats -> Env vs -> FC -> Defined -> (reference : NameType) -> (after : Front ClosedTerm) ->
                   List (Arg vs) -> Front (Maybe (MemberAt AtRole))
definitionMember at ps env fc d reference after args = case givesAfter (length args) (memberPlaces d) of
    NoMember => pure Nothing
    AMember => made !after
    ByInstance => do
      ty <- after
      case !(typeHolding ty) of
        NoMember => pure Nothing
        _ => made ty
  where
    made : ClosedTerm -> Front (Maybe (MemberAt AtRole))
    made ty = do
      (k ** named) <- choiceReadOf ty
      let written = foldl (App fc) (Ref fc reference (fullname d.def)) (map (.written) args)
      h <- holedAt env written
      form <- solved h.key
      FixedNow _ <- fixing ty form
        | ChosenAtRunTime _ => pure Nothing
      shaped <- solved (close env written)
      Just <$> memberAt at ps env fc k named form !(packings at ps fc h shaped) written

||| What a definition's leaves give at its node, from what the member table
||| says it gives after its parameters; where the instance decides, the
||| result type at the node says.
givingOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Holding -> (result : ClosedTerm) -> Front Giving
givingOf AMember result = pure (MemberLeaves result)
givingOf NoMember _ = pure ValueLeaves
givingOf ByInstance result = giving <$> holdingAt result
  where
    -- Where only an instance decides, the leaves may give a member.
    giving : Holding -> Giving
    giving NoMember = ValueLeaves
    giving _ = MemberLeaves result

||| An argument as a callee's type takes it: a static one is walked as a
||| static value, a runtime one as code, and an erased one not at all, since
||| the translation passes it nowhere. A runtime value whose shape keys the
||| instance is both, as the problem has it: its shape a static value, and
||| the value passed at run time, which the translation computes where it
||| stands (`Translate.Instances.ValueParam`), so a call in it is a call.
walked : Taking -> (a : Arg vs) -> Front (ArgWalk AtRole a.origin)
walked (AsStatic AShape) a = WalkedBoth <$> Force a.asStatic <*> Force a.asCode
walked (AsStatic _) a = WalkedStatic <$> Force a.asStatic
walked AsCode a = WalkedCode <$> Force a.asCode
walked Nowhere a = pure WalkedNowhere

||| What takes a call's arguments: a function, which takes a static one as
||| the compile-time value it is, so no member is made there; or a
||| constructor, which holds every one as a value at run time, an
||| implementation or a polymorphic function among them a member of its
||| type's choice (`Translate.Terms.constructor`).
data Taker = AFunction | AConstructor

||| Arguments where `given` says which binders take a member (the member
||| table's `givenAt` for a definition's; for a type no definition has,
||| every binder as the instance decides): an argument at one is a member
||| where it stands (`atMember`), and where the instance decides, where the
||| binder's type the site's arguments give says (`holdingAt`), but a
||| function's static argument, which is no value at run time; any other is
||| walked as its kind says (`walked`). Where only an instance decides, the
||| argument is both: the member it makes, and walked as its kind says. A
||| function given a polymorphic function as a static value applies it
||| where its own text uses it, as a use does (`implementationAt`), so the
||| argument's use's walk is made here (`Arg.asUse`).
takenAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
          At -> Pats -> Env vs -> FC -> Taker -> Holding -> (g : Given vs) -> Front (ArgNode AtRole vs)
takenAt at ps env fc taker holding g = argNode g.offer.arg <$> one taker g.taking holding
  where
    decided : Holding -> Front (TakenAs AtRole g.offer.arg.origin)
    decided AMember = atMember at ps env fc g.binder g.offer.arg
    decided NoMember = TakenWalked <$> walked g.taking g.offer.arg
    decided ByInstance = TakenEither <$> memberMade at ps env fc g.binder g.offer.arg <*> walked g.taking g.offer.arg

    one : Taker -> Taking -> Holding -> Front (TakenAs AtRole g.offer.arg.origin)
    one AFunction (AsStatic _) _ = do
      used <- whereApplied !(choiceAt g.binder) (g.offer.arg.asUse (undelayed g.binder))
      TakenUsed used <$> walked g.taking g.offer.arg
    one _ _ AMember = atMember at ps env fc g.binder g.offer.arg
    one _ _ NoMember = TakenWalked <$> walked g.taking g.offer.arg
    one _ _ ByInstance = decided !(holdingAt g.binder)

||| Arguments as `takenAt` takes each, where `given` says which binders take
||| a member.
walkedAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> Taker -> (given : Nat -> Holding) -> List (Given vs) -> Front (List (ArgNode AtRole vs))
walkedAt at ps env fc taker given gs = traverse (\g => takenAt at ps env fc taker (given g.position) g) gs

||| The member at a use's types of a compile-time form of type `t`
||| (`Translate.State.AtUse`), which applies the form as by `\f, x1 .. xn
||| => f x1 .. xn` at `t` (`Instances.applicationType`): the type at the
||| application's position 0, the form at 1, as `form` reads it, and each
||| of the use's static arguments at its own from 2 on, as the type takes
||| them. With the walk of the use's arguments as the type takes them: a
||| static one by its kind, and any other as code, or nowhere at an erased
||| binder. Past the binders the type shows (a type the writer's variable
||| heads, or a definition its markers leave stuck), an argument is taken
||| as an instance's type takes it, by a kind only the instance decides:
||| written at its position at every kind a request is read at, a type
||| parameter read as a family, whose type constructor splits where the
||| instance's value is a family's, and walked both as a static value and
||| as code.
useAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
        At -> Pats -> Env vs -> FC -> (t : ClosedTerm) -> (form : Argument) -> List (Arg vs) -> Front (UseAtNode AtRole vs)
useAt at ps env fc t form args = do
  os <- traverse (offered ps env) args
  ty <- applicationType
  n <- takes t os
  (kinds, _) <- staticsOver at.owner (S (S n)) ty (Just (t, AValue) :: Nothing :: map (\o => Just (o.value, o.offer)) (take n os))
  let k :: _ :: ks = map staticOf kinds
  -- The form's type is the application's first argument, a type, whose
  -- binder is a universe.
  let typed = MkGiven (MkOffered (closedArg t) t AValue) 0 (maybe Nowhere AsStatic k) (TType EmptyFC (UN Underscore))
  gs <- along 2 t (toList ks) (take n os)
  ws <- traverse (\(g, k) => argument at ps env fc g k) (mapMaybe static (typed :: gs))
  now <- walkedAt at ps env fc AFunction (const ByInstance) gs
  later <- traverse (\(j, o) => past j o) (zip (iterateN (length (drop n os)) S (2 + n)) (drop n os))
  pure (MkUseAtNode (MkRequested (siteAt at ps.place fc Applies (form :: map fst ws ++ (later >>= fst))) (map snd ws))
                    now (map snd later))
  where
    static : Given vs -> Maybe (Given vs, Static)
    static g = case g.taking of
      AsStatic k => Just (g, k)
      AsCode => Nothing
      Nowhere => Nothing

    -- How many of the arguments the type takes, as the binders it shows,
    -- each earlier argument put in, say.
    takes : ClosedTerm -> List (Offered vs) -> Front Nat
    takes ty [] = pure 0
    takes ty (o :: os) = do
      Bind _ _ (Pi {}) sc <- showingBinder ty
        | _ => pure 0
      S <$> takes (subst o.value sc) os

    -- An argument past the binders the type shows, at position `j`, of no
    -- binder's type here: one whose head only an instance shows. A type
    -- and a family are read alike, so a type parameter is written once,
    -- as a family, whose root a member that reads the position as a
    -- family is given; a dictionary's root is the dictionary's alone.
    past : Nat -> Offered vs -> Front (List Argument, PastArg AtRole vs)
    past j o = do
      ws <- traverse (\k => argument at ps env fc (MkGiven o j (AsStatic k) (Erased EmptyFC Placeholder)) k)
                     [AFamily, ADictionary, AForm, AShape]
      walks <- WalkedBoth <$> Force o.arg.asStatic <*> Force o.arg.asCode
      pure (map fst ws, MkPastArg (map snd ws) (argNode o.arg (TakenWalked walks)))

    along : Nat -> ClosedTerm -> List (Maybe Static) -> List (Offered vs) -> Front (List (Given vs))
    along j ty (k :: ks) (o :: os) = do
      Bind _ _ (Pi _ rig _ a) sc <- showingBinder ty
        | _ => pure []
      let taking = case (k, use rig) of
                     (Just st, _) => AsStatic st
                     (Nothing, Erased) => Nowhere
                     (Nothing, Used _) => AsCode
      (MkGiven o j taking a ::) <$> along (S j) (subst o.value sc) ks os
    along _ _ _ _ = pure []

||| A polymorphic function held at run time, of type `t`, applied where it
||| is held: a use of it (`useAt`), whose form at position 1 is the running
||| program's choice, a member of the choice of polymorphic functions,
||| which every place that makes one writes (`memberAt`), and which keys
||| the dispatching instance at nothing, each arm of it a member.
heldApplication : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                  At -> Pats -> Env vs -> FC -> (t : ClosedTerm) -> List (Arg vs) -> Front (UseAtNode AtRole vs)
heldApplication at ps env fc t args =
  useAt at ps env fc t (MkArgument 1 ADictionary (Member ArrowHead) [] (Chosen AtRunTimeAlways) DictionaryHeads Nothing [] (Just ArrowHead) NoTerm []
                                    (TemplateText at.writerDef (Member ArrowHead) [] []))
        args

||| Arguments applied to a value of a known type, or of none: one at an
||| erased binder is passed nowhere, and any other is code. A polymorphic
||| function held at run time, applied, is a use of it
||| (`heldApplication`), and so may a value be whose type shows no binder,
||| its head one only an instance shows, which an instance may show to be
||| a polymorphic function's. Past the binders the type shows, an argument
||| is a runtime value.
overType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> Maybe ClosedTerm -> List (Arg vs) -> Front (OverNode AtRole vs)
overType at ps env fc _ [] = pure OverDone
overType at ps env fc known (a :: as) = do
  ty <- traverse showingBinder known
  case ty of
    Just t@(Bind _ _ (Pi _ rig _ b) sc) => do
      False <- polymorphicType t
        | True => OverUse <$> heldApplication at ps env fc t (a :: as)
      -- No definition's member table speaks for a type a value has: the
      -- binder's type decides, as the instance does, and where only an
      -- instance can, the value is taken both ways.
      here <- the (Front (TakenAs AtRole a.origin)) $ case use rig of
                Erased => pure (TakenWalked WalkedNowhere)
                Used _ => case !(holdingAt b) of
                  NoMember => TakenWalked . WalkedCode <$> Force a.asCode
                  _ => atMember at ps env fc b a
      OverArgument (argNode a here) <$> overType at ps env fc (Just (subst (close env a.written) sc)) as
    -- The use walks every argument, as a static value and as code.
    Just t => do
      k <- choiceHeadOf t
      case applicationOf k of
        AppliedAtUse => OverUse <$> heldApplication at ps env fc t (a :: as)
        NeverApplied => codeThen a (overType at ps env fc Nothing as)
    Nothing => codeThen a (overType at ps env fc Nothing as)
  where
    -- An argument of no binder's type: code, before the rest.
    codeThen : (x : Arg vs) -> Front (OverNode AtRole vs) -> Front (OverNode AtRole vs)
    codeThen x rest = (\c, r => OverArgument (argNode x (TakenWalked (WalkedCode c))) r) <$> Force x.asCode <*> rest

||| The names a type gives its binders.
piNames : TT vs -> List Name
piNames (Bind _ x (Pi {}) sc) = x :: piNames sc
piNames _ = []

||| How many parameters a definition takes: its case tree's scope, as the
||| boundary read its body and the translation calls it, or the arity
||| Idris records, or the binders its type shows.
arityOf : Defined -> Nat
arityOf d = case d.matched of
  Just m => length m.args
  Nothing => case definition d.def of
    DCon _ arity _ => arity
    TCon arity _ _ _ _ _ _ => arity
    Builtin {arity} _ => arity
    ForeignDef arity _ => arity
    ExternDef arity => arity
    _ => length (piNames d.type)

||| What a constructor's application builds: a dictionary, with an
||| interface's constructor, whose fields a dispatch on it settles in place;
||| or a value of a data type, whose fields are values at run time.
data Building = BuildsDictionary | BuildsData

||| A data constructor applied, as the walk reads it: `Calls` of it at
||| every static argument, where it holds a dictionary or builds one, so
||| that the flow sees what a match on its dictionaries reads, and every
||| field a match on what it builds reads, its type arguments among them
||| (`Heads.rebuilt`, `Heads.overPart`), has a writer; and the sites of its
||| result type after its arguments; what it builds; the arguments given,
||| for their walk, each dictionary among them with what the call read of
||| it; and that result type.
record Constructed (vs : Scope) where
  constructor MkConstructed
  sites : ConstructedSites AtRole
  building : Building
  given : List (Given vs, Maybe Argument)
  result : ClosedTerm

||| A data constructor applied, what it takes at each binder `positions`
||| (`Constructed`).
constructed : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
              At -> Pats -> Env vs -> FC -> Address -> Defined -> (positions : List ArgumentAt) -> List (Arg vs) ->
              Front (Constructed vs)
constructed at ps env fc a d positions args = do
  (gs, rest) <- taken at ps env d.type positions args
  read <- traverse dictionary gs
  let dictionaries = mapMaybe snd read
  building <- (\dict => if dict then BuildsDictionary else BuildsData) <$> implementationType d.type
  calls <- case (dictionaries, building) of
    -- Essential: a constructor that holds no dictionary and builds none
    -- has no field a match on a dictionary reads.
    ([], BuildsData) => pure Nothing
    _ => do
      others <- traverse (\(g, k) => readArgument ps.made g.position k Nothing g.offer.value
                                       (WrittenText at.writerDef ps.made (map (\(_, x, _) => x) env) g.offer.arg.written))
                         (mapMaybe other gs)
      pure (Just (MkRequested (siteAt at ps.place fc (Calls a d) (map fst dictionaries ++ others))
                              (map snd dictionaries ++ map (const NothingBeside) others)))
  result <- builds at ps fc rest
  pure (MkConstructed (MkConstructedSites calls result) building (map (\(g, x) => (g, map fst x)) read) rest)
  where
    -- A dictionary, read as the call holds it, with what it writes beside
    -- the call; any other argument, nothing here.
    dictionary : Given vs -> Front (Given vs, Maybe (Argument, Beside AtRole))
    dictionary g = case g.taking of
      AsStatic ADictionary => (\x => (g, Just x)) <$> argument at ps env fc g ADictionary
      _ => pure (g, Nothing)

    -- A static argument of any other kind, read as its key holds it; the
    -- types it builds are its result type's.
    other : Given vs -> Maybe (Given vs, Static)
    other g = case g.taking of
      AsStatic ADictionary => Nothing
      AsStatic k => Just (g, k)
      AsCode => Nothing
      Nowhere => Nothing

||| A projection-shaped definition's case tree: one match on one parameter
||| against one constructor, returning one of its fields, applied or not.
||| The parameter, the field, and for each argument the field is applied to
||| the parameter it is, if it is one.
record Projected where
  constructor MkProjected
  matched : Nat
  field : Nat
  params : List (Maybe Nat)

||| Read off the root of the tree the boundary read.
projectionShape : {0 args : Scope} -> CaseTree args -> Maybe Projected
projectionShape (Case idx _ _ [ConCase _ _ cargs (STerm _ rhs)]) = case getFnArgs rhs of
    (Local _ _ k _, fargs) =>
      if k < length cargs then Just (MkProjected idx k (map (parameter (length cargs)) fargs)) else Nothing
    _ => Nothing
  where
    -- Below the alternative's own variables, a variable is a parameter.
    parameter : Nat -> TT ws -> Maybe Nat
    parameter n (Local _ _ m _) = if m >= n then Just (minus m n) else Nothing
    parameter _ _ = Nothing
projectionShape _ = Nothing

||| The record a call of a projection-shaped definition matches, when the
||| call gives every parameter and the record is a dictionary: a method call.
methodRecord : Defined -> List (Given vs) -> Maybe (Projected, Given vs)
methodRecord d gs = do
  m <- d.matched
  p <- projectionShape m.tree
  Yes _ <- pure (isLTE (length m.args) (length gs))
    | No _ => Nothing
  g <- getAt p.matched gs
  AsStatic ADictionary <- pure g.taking
    | _ => Nothing
  pure (p, g)

||| The method a call dispatches on its dictionary: the record's template
||| and root, read as the projection is given it (`asGiven`), at the
||| method's own static arguments, numbered from the method's first in the
||| order its field's lambdas take them, as the projection's own site
||| numbers them (`projectionSite`). Idris's clause for a projection binds
||| the method's leading implicit arguments, its own type variables (a
||| `Monad m` it quantifies over among them), and applies the field to
||| them: those are the call's arguments at the parameters the field is
||| applied to (`given`, the call's arguments to the projection). Any the
||| method takes past the projection's come after them, walked over the
||| rest of the projection's type; the call walked the others.
dispatch : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> Projected -> Given vs -> (given : List (Given vs)) -> ClosedTerm ->
           List (Arg vs) -> Front (DispatchNode AtRole vs)
dispatch at ps env fc p dict given rest extras = do
  -- The record as its key holds it, bound before it is read: the reading's
  -- type names the term it reads.
  written <- solved !(holed env dict.offer.arg.written)
  (r, root) <- dictionaryRooted ps.made written
  tm <- (\head => asGiven (Just head) (r.template, root)) <$> choiceAt dict.binder
  -- The method's own arguments past the projection's are those its type
  -- shows binders for; any past them applies its result.
  positions <- argumentsIn rest
  let n = min (length extras) (length positions)
  (gs, after) <- taken at ps env rest positions (take n extras)
  let past = map (\g => { position $= (+ length p.params) } g) gs
  site <- callSite at ps env fc (Dispatches tm root p.field) (mapMaybe applied (zip [0 .. length p.params] p.params) ++ past)
  now <- walkedAt at ps env fc AFunction (const ByInstance) past
  later <- overType at ps env fc (Just after) (drop n extras)
  pure (MkDispatchNode site now later)
  where
    -- The field's argument q, where it is the projection's parameter j:
    -- the call's argument there, at the method's own position q. One the
    -- projection does not take from its parameters is no argument of the
    -- call, as at the projection's own site.
    applied : (Nat, Maybe Nat) -> Maybe (Given vs)
    applied (q, Just j) = (\g => { position := q } g) <$> getAt j given
    applied (_, Nothing) = Nothing

||| The definitions a hook calls in place of the one written: the library
||| function of a natural's operation, with no arguments, or the function a
||| foreign definition stands for, at the same arguments, the first that
||| applies as the translation's `hooked` takes them. Each library function
||| is the one the boundary interned with the definition (`Registered`).
hookCalls : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
            At -> Pats -> Env vs -> FC -> Hooks LibraryFunction -> List (Arg vs) -> Front (Maybe (Requested AtRole CallReach))
hookCalls at ps env fc hs args = case hs.natOperation of
  Just (Tested _ lib) => library lib
  Just (OnIntegers lib) => library lib
  Just _ => pure Nothing
  Nothing => maybe (pure Nothing) aliased hs.alias
  where
    library : LibraryFunction -> Front (Maybe (Requested AtRole CallReach))
    library lib = do
      Just (a, d) <- definitionOf lib.name
        | Nothing => pure Nothing
      pure (Just (MkRequested (siteAt at ps.place fc (Calls a d) []) []))

    aliased : LibraryFunction -> Front (Maybe (Requested AtRole CallReach))
    aliased lib = do
      Just (a, d) <- definitionOf lib.name
        | Nothing => pure Nothing
      (gs, _) <- taken at ps env d.type d.taken (take (arityOf d) args)
      Just <$> callSite at ps env fc (Calls a d) gs

||| The arguments of a dictionary built in code with its interface's
||| constructor, each as the member table says, but a method's field Idris
||| wrote at a binder that takes a member: one that applies a function, the
||| method's own, to the field's own arguments
||| (`Implementations.fieldWriting`). The translation settles such a field
||| at each dispatch on the dictionary (`Terms.resolveMethod`), calling that
||| function at the dispatch's own arguments, where the dispatch reaches it
||| (`Dispatches`, `Heads.runs`). Nothing applies the field at a use, so it
||| makes no member of the polymorphic functions' choice: as one, its use's
||| walk would request the function at the positions every use of that
||| choice shares, where the function's own type variables (a `Monad m` it
||| quantifies over) meet whatever any use writes there. It is code where
||| it is written, which is where the walk enters the function. A parent
||| its search found applies a function too, and makes no member either way:
||| it is no lambda, and nothing applies an implementation at a use.
dictionaryArguments : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                      At -> Pats -> Env vs -> FC -> Defined -> List (Given vs) -> Front (List (ArgNode AtRole vs))
dictionaryArguments at ps env fc d gs = traverse one gs
  where
    one : Given vs -> Front (ArgNode AtRole vs)
    one g = asWritten (givenAt g.position (memberPlaces d)) (fieldWriting (close env g.offer.arg.written))
      where
        asTable : Holding -> Front (ArgNode AtRole vs)
        asTable h = takenAt at ps env fc AConstructor h g

        asWritten : Holding -> FieldWriting -> Front (ArgNode AtRole vs)
        asWritten AMember (WrapsFunction _) = argNode g.offer.arg . TakenWalked . WalkedCode <$> Force g.offer.arg.asCode
        asWritten AMember HandWritten = asTable AMember
        asWritten NoMember _ = asTable NoMember
        asWritten ByInstance _ = asTable ByInstance

||| A definition applied as code: the member of its value's choice where
||| the member table says it gives one after its arguments
||| (`definitionMember`), however many it is given; `Calls` of it at the
||| static arguments its type makes, and a method call's `Dispatches`
||| beside it; the definitions its hooks call instead; and the walk of its
||| arguments, a member where the table says its binder takes one.
call : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
       At -> Pats -> Env vs -> FC -> Address -> Defined -> List (Arg vs) -> Front (CallNode AtRole vs)
call at ps env fc a d args = do
  let arity = arityOf d
  (gs, rest) <- taken at ps env d.type d.taken (take arity args)
  member <- definitionMember at ps env fc d Func (typeAfter rest (map (\x => close env x.written) (drop arity args))) args
  own <- callSite at ps env fc (Calls a d) gs
  -- A `%foreign` the registry gives no hooks is refused where it is
  -- called (`Translate.Terms.applyRef`), so it calls nothing in place.
  instead <- case callHooks d.registered of
    Right hs => hookCalls at ps env fc hs args
    Left _ => pure Nothing
  now <- walkedAt at ps env fc AFunction (\j => givenAt j (memberPlaces d)) gs
  later <- case methodRecord d gs of
    Just (p, dict) => MethodCall <$> dispatch at ps env fc p dict gs rest (drop arity args)
    Nothing => PastOver <$> overType at ps env fc (Just rest) (drop arity args)
  pure (MkCallNode member own instead now later)

||| A definition applied as code.
applyRef : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> Name -> List (Arg vs) -> Front (RefNode AtRole vs)
applyRef at ps env fc n args = do
  Just (a, d) <- definitionOf n
    -- A name the context defines as nothing: a marker of a settled term.
    | Nothing => MarkerReference <$> overType at ps env fc Nothing args
  case definition d.def of
    -- A constructor's field that holds an implementation or a polymorphic
    -- function holds the member its site fixes (`Translate.Terms.constructor`),
    -- as the member table says of its binder, but for a method's field,
    -- which a dispatch settles (`dictionaryArguments`). What it builds is
    -- itself a member where the table says it gives one after its
    -- arguments (`definitionMember`), as any definition applied is.
    DCon tag arity _ => do
      dcon <- constructed at ps env fc a d d.taken (take arity args)
      member <- definitionMember at ps env fc d (DataCon tag arity)
                                 (typeAfter dcon.result (map (\x => close env x.written) (drop arity args))) args
      now <- case dcon.building of
        BuildsDictionary => dictionaryArguments at ps env fc d (map fst dcon.given)
        BuildsData => walkedAt at ps env fc AConstructor (\j => givenAt j (memberPlaces d)) (map fst dcon.given)
      later <- overType at ps env fc (Just dcon.result) (drop arity args)
      pure (ConstructorReference (MkConstructNode member dcon.sites now later))
    PMDef {} => CalledReference <$> call at ps env fc a d args
    Builtin {} => CalledReference <$> call at ps env fc a d args
    ForeignDef {} => CalledReference <$> call at ps env fc a d args
    ExternDef {} => CalledReference <$> call at ps env fc a d args
    -- A type where code is, or a hole: the translation refuses both.
    _ => pure RefusedReference

||| The fields of a dictionary built with its constructor, each walked as
||| its binder takes it; then each dictionary among them that the running
||| program may choose (its root, as this writer reads it, is `Chosen`) also
||| as the computation a match that takes the dictionary apart there
||| computes where it reaches it (`Translate.Cases.heldHere`,
||| `computedField`): the key holds the field as written here, with this
||| writer's values, so the requests its computation makes are this
||| writer's sites. A field the program fixes is never stuck, and is never
||| computed so. Every field is walked before any is computed.
dictionaryFields : List (Given vs, Maybe Argument) -> Front (List (ArgNode AtRole vs))
dictionaryFields gs = traverse computing !(traverse walking gs)
  where
    0 Walking : Type
    Walking = (gx : (Given vs, Maybe Argument) ** ArgWalk AtRole (fst gx).offer.arg.origin)

    walking : (Given vs, Maybe Argument) -> Front Walking
    walking (g, x) = (\w => ((g, x) ** w)) <$> walked g.taking g.offer.arg

    computing : Walking -> Front (ArgNode AtRole vs)
    computing ((g, x) ** w) = argNode g.offer.arg <$> case map (.root) x of
      Just (Chosen _) => TakenComputed w <$> Force g.offer.arg.asComputed
      _ => pure (TakenWalked w)

||| A definition applied in a type or a static argument: a constructor as
||| anywhere, an implementation as `Calls` of its function; any other
||| definition there is unfolded by the template, and never requested. A
||| dictionary built with its interface's constructor holds its methods as
||| its own lambdas, which the translation runs in place of a dispatch on
||| it (`Terms.resolveMethod` takes the field and settles it), so they are
||| code wherever the dictionary is written; its other arguments are
||| static, and each dictionary among them is also what a match that finds
||| it stuck computes (`dictionaryFields`).
staticRef : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
            At -> Pats -> Env vs -> FC -> Name -> List (Arg vs) -> Front (StaticRefNode AtRole vs)
staticRef at ps env fc n args = do
  Just (a, d) <- definitionOf n
    | Nothing => StaticMarker <$> statics args
  case definition d.def of
    DCon _ arity _ => do
      dcon <- constructed at ps env fc a d d.taken (take arity args)
      fields <- case dcon.building of
        BuildsDictionary => dictionaryFields dcon.given
        BuildsData => statics (take arity args)
      StaticConstructor dcon.sites fields <$> statics (drop arity args)
    _ => do
      own <- if not !(implementationType d.type) then pure Nothing else do
        (gs, _) <- taken at ps env d.type d.taken (take (arityOf d) args)
        Just <$> callSite at ps env fc (Calls a d) gs
      StaticDefinition own <$> statics args

------------------------------------------------------------------------------
-- Settled terms
------------------------------------------------------------------------------

||| A dictionary or a polymorphic function as its settling walks it, as the
||| translation's does (`Terms.standingFor`): its form, a known one's values
||| the projections of one variable that holds them, the one value the
||| place that binds it holds (`Packs`), which stands for that variable;
||| any other's alone.
formStanding : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Dict -> Front (ClosedTerm, Maybe Standing)
formStanding (Known _ (Just co)) = do
  values <- unpacked (valueTypes co) (probeTerm (ProbeRuntimeAt 0))
  packed <- packedType (valueTypes co)
  pure (fillHoles values co.holedForm, Just (Packs co.binding, UN Underscore, Just packed))
formStanding other = pure (termOf (Holds other), Nothing)

------------------------------------------------------------------------------
-- Terms
------------------------------------------------------------------------------

||| Where a term the walk reads comes from: written in the definition, which
||| may settle once into the phase it holds; or settled, the written form of
||| a dictionary or a polymorphic function walked where it is applied, which
||| settles nothing again.
data Phase = Settled | Written Phase

asWritten : Phase
asWritten = Written Settled

||| A binder's variable, applied to nothing: erased, or a runtime value.
byQuantity : Use -> Stand
byQuantity Erased = Erased
byQuantity (Used _) = Runtime

-- The walk ends, lexicographically in the phase, the metavariables entered
-- on the path, and the term. Every step goes to a part of the term but two:
-- a metavariable's solution, entered once on its path (`Walk`), and a
-- dictionary variable applied, settled once into the phase the written one
-- held. An argument's walks, its use's among them, are made where it is a
-- subterm (`argOf`), in the walk's own phase.
mutual
  ||| A term as code: every application in it, at any depth, is a site.
  term : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
         (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
         At -> Pats -> Env vs -> TT vs -> Front (CodeNode AtRole vs)
  term ph w acc at ps env tm@(Local fc _ idx p) = MkCodeNode tm . CodeApplied . HeadVariable <$> applyVariable ph w acc at ps env fc idx p []
  term ph w acc at ps env tm@(Ref fc _ n) = MkCodeNode tm . CodeApplied . HeadReference <$> applyRef at ps env fc n []
  -- A closed run of a Nat-like successor is a literal, which calls and
  -- builds nothing: read whole, as a template reads it (`closedRun`), it is
  -- one step, where a walk through its constructors would close the rest
  -- of the run at each.
  term ph w acc at ps env tm@(App _ f a) = do
    Nothing <- closedRun tm
      | Just _ => pure (MkCodeNode tm CodeInert)
    MkCodeNode tm . CodeApplied <$> spine ph w acc at (entering AppFunction ps) env f [argOf ph w acc at ps env a]
  -- A lambda: its binders and body as code. Where it is a member, the
  -- place it stands says so (`atMember`, `resultMember`).
  term ph w acc at ps env tm@(Bind fc x (Lam _ rig _ ty) sc) = MkCodeNode tm . CodeLambda <$> lambdaBinder ph w acc at ps env x rig ty sc
  -- A `let` of a type or a type family binds a type parameter whatever its
  -- quantity, its value as written, as the translation binds it
  -- (`Translate.Terms.letIn`), and that value is no code. Any other erased
  -- `let` binds a compile-time value, and its value is no code. One that
  -- binds an implementation or a polymorphic function
  -- (`compileTimeBinder`) binds the value as written, as the translation
  -- binds it, settled where it is applied, what it closes over held as one
  -- at the place it is bound at (`heldBy`); a polymorphic function so
  -- bound may be applied at a use (`implementationAt`), so its use's walk
  -- is made here, where it is a subterm (`useOf`).
  term ph w acc at ps env tm@(Bind _ x (Let _ rig val ty) sc) = MkCodeNode tm <$> do
    let typed = close env ty
    vty <- normaliseClosed typed
    if isTypeLike vty then CodeLetType <$> term ph w acc at (entering BinderScope ps) ((Fixed (close env val), x, Nothing) :: env) sc else
      case use rig of
        Erased => CodeLetErased <$> term ph w acc at (entering BinderScope ps) ((Erased, x, Nothing) :: env) sc
        Used _ =>
          if !(compileTimeBinder rig vty)
            then do
              known <- knownAt at ps env val
              here <- static ph w acc at (entering (BinderValue StaticWalk) ps) env val
              used <- whereApplied !(choiceHeadOf vty) (useOf ph w acc at (entering (BinderValue UseWalk) ps) env vty val)
              held <- heldBy at ps (getLoc val) known
              body <- term ph w acc at (entering BinderScope ps) ((Holds known, x, Just typed) :: env) sc
              pure (CodeLetForm here used held body)
            else do
              value <- term ph w acc at (entering (BinderValue CodeWalk) ps) env val
              here <- readType ph w acc at (entering BinderType ps) env ty
              body <- term ph w acc at (entering BinderScope ps) ((Runtime, x, Just typed) :: env) sc
              pure (CodeLetValue value here body)
  term ph w acc at ps env tm@(Meta fc _ i margs) = MkCodeNode tm . CodeApplied . HeadSolution <$> entered ph w acc at ps env fc i margs []
  term ph w acc at ps env tm@(As _ _ _ pat) = MkCodeNode tm . CodeAs <$> term ph w acc at (entering PatternOfAs ps) env pat
  term ph w acc at ps env tm@(TDelay _ _ _ arg) = MkCodeNode tm . CodeDelay <$> term ph w acc at (entering DelayValue ps) env arg
  term ph w acc at ps env tm@(TForce _ _ arg) = MkCodeNode tm . CodeForce <$> term ph w acc at (entering ForcedValue ps) env arg
  -- A type, a constant or an erased value is no call.
  term ph w acc at ps env tm@(Bind _ _ _ _) = pure (MkCodeNode tm CodeInert)
  term ph w acc at ps env tm@(TDelayed _ _ _) = pure (MkCodeNode tm CodeInert)
  term ph w acc at ps env tm@(PrimVal _ _) = pure (MkCodeNode tm CodeInert)
  term ph w acc at ps env tm@(Erased _ _) = pure (MkCodeNode tm CodeInert)
  term ph w acc at ps env tm@(TType _ _) = pure (MkCodeNode tm CodeInert)

  ||| A lambda's binder and its scope. A binder of quantity 0 binds nothing
  ||| at runtime, so its type is no type a value has.
  lambdaBinder : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                 (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                 At -> Pats -> Env vs -> (x : Name) -> RigCount -> TT vs -> TT (x :: vs) -> Front (LambdaNode AtRole vs)
  lambdaBinder ph w acc at ps env x rig ty sc = case use rig of
    Erased => ErasedBinder <$> lambdaScope ph w acc at (entering BinderScope ps) ((Erased, x, Nothing) :: env) sc
    Used _ => do
      here <- readType ph w acc at (entering BinderType ps) env ty
      UsedBinder here <$> lambdaScope ph w acc at (entering BinderScope ps) ((Runtime, x, Just (close env ty)) :: env) sc

  ||| A lambda's scope. A lambda directly under another is one value with
  ||| it, a member only as the whole is one, so its binder is walked as the
  ||| outer one's; any other term is code.
  lambdaScope : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                At -> Pats -> Env vs -> TT vs -> Front (LambdaBodyNode AtRole vs)
  lambdaScope ph w acc at ps env (Bind _ x (Lam _ rig _ ty) sc) = InnerLambda <$> lambdaBinder ph w acc at ps env x rig ty sc
  lambdaScope ph w acc at ps env tm = LambdaCode <$> term ph w acc at ps env tm

  ||| A type or a static argument: an implementation applied in it is a
  ||| call, and so is a constructor holding dictionaries; its types are read
  ||| off its template, by whoever reads it as a type.
  static : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           At -> Pats -> Env vs -> TT vs -> Front (StaticNode AtRole vs)
  static ph w acc at ps env tm@(Ref fc _ n) = MkStaticNode tm . StaticApplied . StaticReference <$> staticRef at ps env fc n []
  static ph w acc at ps env tm@(App _ f a) = do
    Nothing <- closedRun tm
      | Just _ => pure (MkStaticNode tm StaticInert)
    MkStaticNode tm . StaticApplied <$> staticSpine ph w acc at (entering AppFunction ps) env f [argOf ph w acc at ps env a]
  static ph w acc at ps env tm@(Bind _ x (Lam _ rig _ ty) sc) = do
    here <- static ph w acc at (entering BinderType ps) env ty
    MkStaticNode tm . StaticBinder here <$> static ph w acc at (entering BinderScope ps) ((byQuantity (use rig), x, Just (close env ty)) :: env) sc
  static ph w acc at ps env tm@(Bind _ x (Pi _ rig _ ty) sc) = do
    here <- static ph w acc at (entering BinderType ps) env ty
    MkStaticNode tm . StaticBinder here <$> static ph w acc at (entering BinderScope ps) ((byQuantity (use rig), x, Just (close env ty)) :: env) sc
  static ph w acc at ps env tm@(Bind _ x (Let _ rig val ty) sc) = do
    value <- static ph w acc at (entering (BinderValue StaticWalk) ps) env val
    here <- static ph w acc at (entering BinderType ps) env ty
    body <- static ph w acc at (entering BinderScope ps) ((byQuantity (use rig), x, Just (close env ty)) :: env) sc
    pure (MkStaticNode tm (StaticLet value here body))
  static ph w acc at ps env tm@(Meta fc _ i margs) = MkStaticNode tm . StaticApplied <$> staticEntered ph w acc at ps env fc i margs []
  static ph w acc at ps env tm@(As _ _ _ pat) = MkStaticNode tm . StaticAs <$> static ph w acc at (entering PatternOfAs ps) env pat
  static ph w acc at ps env tm@(TDelayed _ _ t) = MkStaticNode tm . StaticLazy <$> static ph w acc at (entering LazyOf ps) env t
  static ph w acc at ps env tm@(TDelay _ _ t a) =
    (\x, y => MkStaticNode tm (StaticDelay x y)) <$> static ph w acc at (entering DelayType ps) env t
                                                <*> static ph w acc at (entering DelayValue ps) env a
  static ph w acc at ps env tm@(TForce _ _ a) = MkStaticNode tm . StaticForce <$> static ph w acc at (entering ForcedValue ps) env a
  -- A variable, a pattern's binder, a constant or an erased value writes
  -- nothing.
  static ph w acc at ps env tm@(Local _ _ _ _) = pure (MkStaticNode tm StaticInert)
  static ph w acc at ps env tm@(Bind _ _ _ _) = pure (MkStaticNode tm StaticInert)
  static ph w acc at ps env tm@(PrimVal _ _) = pure (MkStaticNode tm StaticInert)
  static ph w acc at ps env tm@(Erased _ _) = pure (MkStaticNode tm StaticInert)
  static ph w acc at ps env tm@(TType _ _) = pure (MkStaticNode tm StaticInert)

  ||| A binder's or a `let`'s type: what it writes, and the types it builds.
  readType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
             (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
             At -> Pats -> Env vs -> TT vs -> Front (TypeRead AtRole vs)
  readType ph w acc at ps env ty = do
    here <- static ph w acc at ps env ty
    MkTypeRead here <$> builds at ps (getLoc ty) (close env ty)

  ||| The argument of the application the walk is at, where it is a
  ||| subterm of it: each of its walks a step into it in its own mode.
  argOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
          (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          At -> Pats -> Env vs -> TT vs -> Arg vs
  argOf ph w acc at ps env a =
    MkArg Refl a a
          (term ph w acc at (entering (AppArgument CodeWalk) ps) env a)
          (static ph w acc at (entering (AppArgument StaticWalk) ps) env a)
          (\ty => useOf ph w acc at (entering (AppArgument UseWalk) ps) env ty a)
          (computedField ph w acc at (entering (AppArgument ComputedWalk) ps) env a)

  ||| A dictionary's field as a match that finds it stuck computes it where
  ||| the match reaches it (`Translate.Terms.computedAt`): written, settled
  ||| once as the term it is written as, walked as code, every runtime value
  ||| it closes over a variable of the settled term (`implementationAt`),
  ||| the values a dictionary known as a term closes over held as one at its
  ||| place, as a bound one's are (`heldBy`); in a settled term, which
  ||| settles nothing again, the term it is, as code.
  computedField : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                  (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                  At -> Pats -> Env vs -> TT vs -> Front (ComputedNode AtRole vs)
  computedField Settled w acc at ps env a = ComputedCode <$> term Settled w acc at ps env a
  computedField ph@(Written _) w acc at ps env a = do
    known <- knownAt at ps env a
    held <- heldBy at ps (getLoc a) known
    ComputedSettled held <$> implementationAt ph at ps env (getLoc a) Nothing known []

  ||| A member of a polymorphic function's choice applied at a use of type
  ||| `ty` (`Translate.State.AtUse`), walked once, at the place that makes
  ||| it, in the phase of the walk that meets it: applied to an argument at
  ||| each binder its type shows and each lambda it takes past them, each
  ||| the position of the application the use gives it (`useArguments`), so
  ||| that what its body requests at a use's types reads those positions.
  ||| A delayed member is the member it delays, and one under `let`s is
  ||| their body, each binder standing as the walk of a term binds it.
  useOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
          (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          At -> Pats -> Env vs -> (ty : ClosedTerm) -> TT vs -> Front (UseNode AtRole vs)
  useOf ph w acc at ps env ty tm@(TDelay _ _ _ t) = MkUseNode tm . UseDelayed <$> useOf ph w acc at (entering DelayValue ps) env ty t
  useOf ph w acc at ps env ty tm@(Bind _ x (Let _ rig val vty) sc) = do
    typeLike <- isTypeLike <$> normaliseClosed (close env vty)
    let stand : Standing = if typeLike then (Fixed (close env val), x, Nothing) else case use rig of
                  Erased => (Erased, x, Nothing)
                  Used _ => (Runtime, x, Just (close env vty))
    MkUseNode tm . UseUnderLet <$> useOf ph w acc at (entering BinderScope ps) (stand :: env) ty sc
  useOf ph w acc at ps env ty t = do
    args <- useArguments at ty t
    MkUseNode t . UseApplied <$> spine ph w acc ({ params := UseFrom at.arity } at) ps env t args

  ||| An application's spine as code, its arguments collected where each is
  ||| a subterm, down to its head; the walk is at the node it reads, each
  ||| function of an application a step below it.
  spine : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
          (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          At -> Pats -> Env vs -> TT vs -> List (Arg vs) -> Front (HeadNode AtRole vs)
  spine ph w acc at ps env (App _ f a) args =
    spine ph w acc at (entering AppFunction ps) env f (argOf ph w acc at ps env a :: args)
  spine ph w acc at ps env (Ref fc _ n) args = HeadReference <$> applyRef at ps env fc n args
  spine ph w acc at ps env tm args = applyHead ph w acc at ps env tm args

  ||| An application's spine in a type or a static argument.
  staticSpine : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                At -> Pats -> Env vs -> TT vs -> List (Arg vs) -> Front (StaticHead AtRole vs)
  staticSpine ph w acc at ps env (App _ f a) args =
    staticSpine ph w acc at (entering AppFunction ps) env f (argOf ph w acc at ps env a :: args)
  staticSpine ph w acc at ps env (Ref fc _ n) args = StaticReference <$> staticRef at ps env fc n args
  staticSpine ph w acc at ps env (Meta fc _ i margs) args = staticEntered ph w acc at ps env fc i margs args
  staticSpine ph w acc at ps env tm args = do
    here <- static ph w acc at ps env tm
    StaticOther here <$> statics args

  ||| A head that is no definition, applied as code: a variable; a lambda,
  ||| whose variable stands for its argument, so that its body sees it; a
  ||| solved metavariable, as its solution; anything else, walked with its
  ||| arguments applied to a value of unknown type.
  applyHead : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
              (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
              At -> Pats -> Env vs -> TT vs -> List (Arg vs) -> Front (HeadNode AtRole vs)
  applyHead ph w acc at ps env (Local fc _ idx p) args = HeadVariable <$> applyVariable ph w acc at ps env fc idx p args
  -- The argument stands as what it is: a compile-time value at an erased
  -- binder, and at a binder of a type or a type family whatever its
  -- quantity, as the translation binds it (`Terms.applyHead`); the variable
  -- it is; at a binder of an implementation or a polymorphic function
  -- (`compileTimeBinder`), its form as written, a static value; anything
  -- else, a runtime value, which is code. A polymorphic function bound so
  -- may be applied at a use (`implementationAt`), so its use's walk is
  -- made here (`Arg.asUse`).
  applyHead ph w acc at ps env (Bind _ x (Lam _ rig _ ty) sc) (a :: rest) = do
    (entry, bound) <- the (Front (Standing, BoundAs AtRole a.origin vs)) $
      case use rig of
        Erased => pure ((Fixed (close env a.written), x, Nothing), BoundCompileTime)
        Used _ => case a.written of
          Local _ _ idx p => pure (let (s, _, t) = lookupVar idx p env in ((s, x, t), BoundAlias))
          _ => do
            bty <- normaliseClosed (close env ty)
            if isTypeLike bty then pure ((Fixed (close env a.written), x, Nothing), BoundCompileTime) else
              if !(compileTimeBinder rig bty)
                then do
                  known <- knownAt at ps env a.written
                  used <- whereApplied !(choiceHeadOf bty) (a.asUse bty)
                  held <- heldBy at ps (getLoc a.written) known
                  pure ((Holds known, x, Just (close env ty)), BoundForm !(Force a.asStatic) used held)
                else do
                  value <- Force a.asCode
                  here <- readType ph w acc at (entering BinderType ps) env ty
                  pure ((Runtime, x, Just (close env ty)), BoundValue value here)
    HeadLambda (MkBoundArg a.thinned a.original bound) <$>
      spine ph w acc at (entering BinderScope ps) (entry :: env) sc (map overBinder rest)
  applyHead ph w acc at ps env (Meta fc _ i margs) args = HeadSolution <$> entered ph w acc at ps env fc i margs args
  applyHead ph w acc at ps env (As _ _ _ pat) args = HeadPattern <$> spine ph w acc at (entering PatternOfAs ps) env pat args
  applyHead ph w acc at ps env tm args = do
    here <- term ph w acc at ps env tm
    HeadOther here <$> overType at ps env (getLoc tm) Nothing args

  ||| A variable applied as code: a runtime value's arguments over its type;
  ||| a dictionary, settled once with them.
  applyVariable : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                  (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                  At -> Pats -> Env vs -> FC -> (idx : Nat) -> (0 p : IsVar n idx vs) -> List (Arg vs) ->
                  Front (VariableNode AtRole vs)
  applyVariable ph w acc at ps env fc idx p args = case lookupVar idx p env of
    (Runtime, _, ty) => RuntimeVariable <$> overType at ps env fc ty args
    (Pattern _, _, ty) => RuntimeVariable <$> overType at ps env fc ty args
    (Shape _, _, ty) => RuntimeVariable <$> overType at ps env fc ty args
    (Packs _, _, ty) => RuntimeVariable <$> overType at ps env fc ty args
    (Holds d, _, ty) => SettledVariable <$> implementationAt ph at ps env fc ty d args
    -- Idris's quantity check keeps a compile-time variable out of every
    -- position that exists at runtime.
    (Fixed _, _, _) => pure CompileTimeVariable
    (Erased, _, _) => pure CompileTimeVariable

  ||| A dictionary or a polymorphic function applied as code: written, it is
  ||| settled once at its arguments as the translation settles it, its form
  ||| walked as written with each argument bound once (`settledWalk`), in the
  ||| phase it held, so that a member made inside it holds the values bound.
  ||| Applied in a settled term, which settles nothing again, it is
  ||| the member at this use's types (`Translate.Terms.implementationAt`):
  ||| a use of the form, fixed at the application's position 1 (`useAt`),
  ||| whose walk at a use was made where it was bound. One whose type the
  ||| walk does not know is applied to arguments that are code.
  implementationAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                     Phase -> At -> Pats -> Env vs -> FC -> Maybe ClosedTerm -> Dict -> List (Arg vs) ->
                     Front (SettlingNode AtRole vs)
  implementationAt Settled at ps env fc Nothing d args = SettledOver <$> overType at ps env fc Nothing args
  implementationAt Settled at ps env fc (Just ty) d args = do
    let t = termOf (Holds d)
    form <- readArgument ps.made 1 ADictionary Nothing t (TermText t)
    SettledUse <$> useAt at ps env fc !(normaliseClosed ty) form args
  -- A polymorphic function settled where it is applied is also a use of
  -- it (`useAt`): what the program gave for it was walked at its uses
  -- where it was given (`walkedAt`), which reads these positions, so a
  -- parameter's own application, whose form only an instance holds, is
  -- bounded through them.
  implementationAt (Written next) at ps env fc (Just ty) d args = do
    let t = termOf (Holds d)
    nty <- normaliseClosed ty
    used <- whereApplied !(choiceHeadOf nty)
              (do form <- readArgument ps.made 1 ADictionary Nothing t (TermText t)
                  useAt at ps env fc nty form args)
    Settling used <$> settledWalk next at (entering SettledForm ps) env d args
  implementationAt (Written next) at ps env fc Nothing d args = Settling Nothing <$> settledWalk next at (entering SettledForm ps) env d args

  ||| A dictionary or a polymorphic function applied as code, written:
  ||| walked as it is written, in the phase it held, its arguments bound
  ||| once where its lambdas bind them (`applyHead`), as the translation
  ||| walks it (`Terms.settle`), the one variable a known one's values are
  ||| projections of bound around it (`formStanding`), so that a member
  ||| made inside it holds them.
  settledWalk : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                (next : Phase) -> At -> Pats -> Env vs -> Dict -> List (Arg vs) -> Front (FormNode AtRole vs)
  settledWalk next at ps env d args = do
    (value, own) <- formStanding d
    case own of
      Nothing => FormWalked <$> spine next start (sizeAccessible start) at ps env (embedClosed value) args
      Just e =>
        let n = probeName (ProbeRuntimeAt 0) in
        FormHolding <$> spine next start (sizeAccessible start) at ps (e :: env) (refToLocal n n (embedClosed value)) (map overBinder args)

  ||| A metavariable applied as code, as the solution the type checker gave
  ||| it, read once at the boundary by the entry its term gives it
  ||| (`State.solutionIn`), and entered once on the path, at that entry's
  ||| place: met again, its solution is being walked. A hole writes nothing
  ||| the growth check bounds: the translation refuses it where it meets it.
  entered : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
            (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            At -> Pats -> Env vs -> FC -> Int -> List (TT vs) -> List (Arg vs) -> Front (SolutionNode AtRole vs)
  entered ph w acc@(Access rec) at ps env fc i margs args = do
    r <- reading
    SolvedAs tm placement _ _ _ _ <- core (solutionIn r i)
      | Unsolved _ _ => pure NotEntered
    let Just (Element w' less) = enter placement w
      | Nothing => pure NotEntered
    Solved <$> spine ph w' (rec w' less) at (entering MetaSolution ps) env (solvedApplied fc tm margs) args

  ||| A metavariable applied in a type or a static argument, likewise.
  staticEntered : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                  (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                  At -> Pats -> Env vs -> FC -> Int -> List (TT vs) -> List (Arg vs) -> Front (StaticHead AtRole vs)
  staticEntered ph w acc@(Access rec) at ps env fc i margs args = do
    r <- reading
    SolvedAs tm placement _ _ _ _ <- core (solutionIn r i)
      | Unsolved _ _ => pure StaticNotEntered
    let Just (Element w' less) = enter placement w
      | Nothing => pure StaticNotEntered
    StaticSolved <$> staticSpine ph w' (rec w' less) at (entering MetaSolution ps) env (solvedApplied fc tm margs) args

||| A leaf at the writer's result: where its leaves give a member of a
||| type, a lambda there, under its `let`s, is that member
||| (`Translate.Terms.atType`); and a member of a polymorphic function's
||| choice, a lambda or a definition applied, is applied at each use of the
||| choice, so its use's walk is made here (`useOf`).
resultMember : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
               At -> Pats -> Env vs -> TT vs -> Front (LeafMember AtRole vs)
resultMember at ps env tm = case at.giving of
  ValueLeaves => pure ValueLeaf
  MemberLeaves ty => do
    used <- whereApplied !(choiceAt ty) (useOf asWritten start (sizeAccessible start) at ps env ty tm)
    MemberLeaf used <$> under env tm
  where
    under : {ws : Scope} -> Env ws -> TT ws -> Front (Maybe (MemberAt AtRole))
    under env' lam@(Bind fc _ (Lam {}) _) = Just <$> lambdaAt at ps env' fc lam
    under env' (Bind _ x (Let _ rig val ty) sc) = do
      typeLike <- isTypeLike <$> normaliseClosed (close env' ty)
      let stand : Standing = if typeLike then (Fixed (close env' val), x, Nothing) else case use rig of
                    Erased => (Erased, x, Nothing)
                    Used _ => (Runtime, x, Just (close env' ty))
      under (stand :: env') sc
    under _ _ = pure Nothing

||| A closed type: what it writes, and the types it builds.
readClosed : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> At -> Pats -> ClosedTerm -> Front (TypeRead AtRole [])
readClosed at ps ty = readType asWritten start (sizeAccessible start) at ps [] ty

------------------------------------------------------------------------------
-- Case trees
------------------------------------------------------------------------------

||| The scope with a matched stand-in replaced by the constructor it matched,
||| in every stand and type, so that every later reference to the scrutinee
||| sees the match: a variable that is the stand-in (the scrutinee, or
||| another name for it) is now that constructor's shape.
rebound : StandIn -> ClosedTerm -> Env vs -> Env vs
rebound p con [] = []
rebound p con ((s, x, ty) :: es) = (restand s, x, map onto ty) :: rebound p con es
  where
    onto : ClosedTerm -> ClosedTerm
    onto = substName (standInName p.number) con

    closing : Closing -> Closing
    closing (ValueOf t) = ValueOf (onto t)
    closing (HolderOf b t) = HolderOf b (onto t)

    restand : Stand -> Stand
    restand (Pattern q) = if q.number == p.number then Shape con else Pattern q
    restand (Fixed t) = Fixed (onto t)
    restand (Holds (Known t co)) =
      Holds (Known (onto t) (map (\c => { holedForm := onto c.holedForm, closings := map closing c.closings } c) co))
    restand (Shape t) = Shape (onto t)
    restand s = s

||| The variables a constructor binds, in argument order, read off its
||| normalised type with its binders laid out as the data instance lays them
||| out (`paramLayout`), and the constructor applied to them. `r` is the
||| scrutinee's type's arguments. An argument at a parameter is that
||| argument, a type; of a dictionary, a field of it, which keeps its path;
||| any other erased one nothing; a runtime field of a shape a shape one
||| constructor deeper, and any other a runtime value: a field that holds
||| an implementation or a polymorphic function among them, a member of the
||| choice of its type, which the running program made where it built the
||| value, as the translation binds it.
conStands : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            Pats -> Stand -> List ClosedTerm -> Defined -> ClosedTerm -> (args : List Name) ->
            Front (Env args, ClosedTerm, Pats)
conStands ps v r cd con args = do
  ty <- normaliseClosed cd.type
  layout <- layoutOf ty
  (env, ps') <- bind ps layout 0 ty args
  pure (env, foldl (App EmptyFC) con (map (\(s, _, _) => termOf s) (innermostFirst env)), ps')
  where
    built : TT ws -> Maybe Name
    built (Bind _ _ (Pi {}) sc) = built sc
    built tm = case getFnArgs tm of
      (Ref _ (TyCon _) tn, _) => Just tn
      _ => Nothing

    layoutOf : ClosedTerm -> Front (List (Maybe Nat))
    layoutOf ty = do
      let Just tn = built ty
        | Nothing => pure []
      Just tc <- defined tn
        | Nothing => pure []
      -- A head the context defines as no type constructor lays out no
      -- parameter, as one it defines as nothing does.
      pure (case tc.nature.asTypeConstructor of
              ATypeConstructor facts => paramLayout cd.def facts.params facts.roles ty
              NoTypeConstructor => [])

    -- Runtime field b: of a shape not matched yet, the part at that
    -- field, one match deeper; of anything else, a runtime value.
    field : Nat -> Pats -> (Stand, Pats)
    field b ps = case v of
      Pattern p => fresh p.param (p.path ++ [b]) ps
      _ => (Runtime, ps)

    -- The scrutinee's type need not show the parameter when it is no type
    -- constructor applied (a type-level function stuck on a marker): the
    -- argument is then not known.
    stand : Pats -> Maybe Nat -> Nat -> RigCount -> ClosedTerm -> Front (Stand, Pats)
    stand ps (Just p) b _ _ = pure (maybe Erased Fixed (getAt p r), ps)
    stand ps Nothing b rig a = case v of
      Holds (Own i path) => pure (Holds (Own i (path ++ [b])), ps)
      _ => case argumentAt cd.def b rig of
        RuntimeValue _ =>
          if !(compileTimeBinder rig !(normaliseClosed a)) then pure (Runtime, ps) else pure (field b ps)
        _ => pure (Erased, ps)

    -- The layout has one entry per binder of the type it was read off,
    -- which is this one, so they are taken in step.
    bind : Pats -> List (Maybe Nat) -> Nat -> ClosedTerm -> (as : List Name) -> Front (Env as, Pats)
    bind ps _ b ty [] = pure ([], ps)
    bind ps (l :: ls) b (Bind _ _ (Pi _ rig _ a) sc) (x :: xs) = do
      (st, ps') <- stand ps l b rig a
      (rest, ps'') <- bind ps' ls (S b) (subst (termOf st) sc) xs
      pure ((st, x, Just a) :: rest, ps'')
    -- A normalised constructor type shows every binder its alternatives
    -- bind, so this is only a type that shows fewer.
    bind ps _ b ty (x :: xs) = do
      (rest, ps') <- bind ps [] (S b) ty xs
      pure ((Runtime, x, Nothing) :: rest, ps')

conName : CaseAlt vs -> Maybe Name
conName (ConCase cn _ _ _) = Just cn
conName _ = Nothing

||| The constructors a match on data constructors is among: those the type
||| constructor its first constructor builds declares, in tag order, as the
||| boundary read them (`Cases.matchedConstructors`). A match on no
||| constructor (literals, a suspension's form) is among none, and so is
||| one whose constructor the context does not hold, which Idris's tree
||| never names.
matchedAmong : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> At -> List (CaseAlt vs) -> Front (List ConstructorAt)
matchedAmong at alts = case mapMaybe conName alts of
  [] => pure []
  (cn :: _) => do
    Just (_, d) <- definitionOf cn
      | Nothing => pure []
    case definition d.def of
      DCon {} => do
        -- The type as written may hide binders behind a definition (`a -@
        -- b`); its normal form shows each one, and what it builds. One that
        -- builds anything but a type constructor's value is the compiled
        -- module's, refused there as its whole type.
        ty <- normaliseClosed d.type
        matchedConstructors at.loc at.owner (fromMaybe ty (builtBy ty))
      -- Essential: a match on a type (a type case) names type
      -- constructors, which no declaration lists together, so its default
      -- stands for every type the alternatives leave out.
      _ => pure []
  where
    -- What a constructor's type builds, after its binders, where a
    -- reference heads it: closed, since a reference needs no scope.
    builtBy : TT ws -> Maybe ClosedTerm
    builtBy (Bind _ _ (Pi {}) sc) = builtBy sc
    builtBy t = case getFn t of
      Ref rfc nt n => Just (Ref rfc nt n)
      _ => Nothing

||| Where a tree takes apart a field of the writer's own dictionary
||| parameter, one field deep or more, the running program may have chosen
||| that field (`Translate.Cases.heldHere`): the writer is requested again,
||| at each of its static parameters as it is, the dictionary rebuilt at
||| the node it is read at (`Heads.reaches`), which knows what the field
||| can be. A match on the dictionary itself is never stuck, since the
||| program fixes it, and one on anything else is no field of it. The
||| rebuilt dictionary holds the field after the values its writer was
||| given, as one, so the pair that holds them is reached (`pairReached`).
||| Every other dictionary parameter is passed on with the values it was
||| given, each as itself (`Cases.passedOn`). The site is made at the
||| match, `place`.
repacked : {auto c : Ref Ctxt Defs} -> At -> Place -> Stand -> Front (Maybe (Repacked AtRole))
repacked at place (Holds (Own i (k :: ks))) = do
  dictionary <- own (i, ADictionary)
  others <- traverse own (mapMaybe static (zip [0 .. length at.statics] at.statics))
  paired <- pairReached at place at.loc
  pure (Just (MkRepacked (siteAt at place at.loc (Repacks dictionary (k ::: ks)) others) paired))
  where
    -- Each static parameter but the dictionary's.
    static : (Nat, Maybe Static) -> Maybe (Nat, Static)
    static (j, Just kind) = if j == i then Nothing else Just (j, kind)
    static (_, Nothing) = Nothing

    own : (Nat, Static) -> Front Argument
    own (j, kind) = do
      x <- readArgument [] j kind Nothing (markerAt j []) (ParameterText at.writerDef j)
      pure (case kind of
              ADictionary => { holds := [EachOf j ::: []] } x
              _ => x)
repacked at place _ = pure Nothing

mutual
  ||| A case tree: each leaf's term, as code and as the member the
  ||| definition's result is at a use, each a walk of its own, with what the
  ||| matches above it made of the scope.
  tree : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
         At -> Pats -> Env vs -> CaseTree vs -> Front (TreeNode AtRole vs)
  tree at ps env t@(STerm _ tm) =
    (\m, c => MkTreeNode t (TreeLeaf m c)) <$> resultMember at (entering (LeafTerm UseWalk) ps) env tm
                                           <*> term asWritten start (sizeAccessible start) at (entering (LeafTerm CodeWalk) ps) env tm
  tree at ps env t@(Unmatched _) = pure (MkTreeNode t TreeUnmatched)
  tree at ps env t@Impossible = pure (MkTreeNode t TreeImpossible)
  -- The scrutinee's type is its variable's: a case tree loaded from a TTC
  -- holds none of its own.
  tree at ps env t@(Case idx p _ alts) = do
    let v = lookupVar idx p env
    r <- the (Front (List ClosedTerm)) $ case v of
      (_, _, Just ty) => typeArgs <$> normaliseClosed ty
      (_, _, Nothing) => pure []
    -- A match on constructors that names each of its type's, by tag, has
    -- a default that stands for no value (`Cases.namesEvery`).
    every <- the (Front Bool) $ case !(matchedAmong at alts) of
      [] => pure False
      cons => pure (namesEvery (map (.tag) cons) alts)
    here <- repacked at ps.place (fst v)
    MkTreeNode t . TreeMatch here <$> alternatives at ps env v r every alts 0 alts
    where
      -- The arguments of the type constructor a type is.
      typeArgs : ClosedTerm -> List ClosedTerm
      typeArgs ty = case getFnArgs ty of
        (Ref _ (TyCon _) _, as) => as
        _ => []

  ||| A match's alternatives from the one at position `k` on, each walked a
  ||| step below the match, by its position.
  alternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                 At -> Pats -> Env vs -> Standing -> List ClosedTerm -> Bool -> List (CaseAlt vs) ->
                 (k : Nat) -> List (CaseAlt vs) -> Front (List (AltNode AtRole vs))
  alternatives at ps env v r every alts k [] = pure []
  alternatives at ps env v r every alts k (ConCase cn tag args rhs :: rest) = do
    here <- the (Front (AltNode AtRole vs)) $ case !(definitionOf cn) of
      Just (_, cd) => do
        (bound, con, ps') <- conStands (entering (CaseAlternative k) ps) (fst v) r cd (Ref EmptyFC (DataCon tag (length args)) cn) args
        ConstructorAlt {args} <$> tree at ps' (prepend bound (matchedAs (fst v) con env)) rhs
      -- Idris's tree names only constructors the context holds.
      Nothing => pure UnknownConstructorAlt
    (here ::) <$> alternatives at ps env v r every alts (S k) rest
    where
      -- A shape not matched yet is the constructor from now on; a dictionary
      -- keeps its marker, so that its root stays the writer's head.
      matchedAs : Stand -> ClosedTerm -> Env vs -> Env vs
      matchedAs (Pattern p) con env = rebound p con env
      matchedAs _ _ env = env
  -- A default after a complete split stands for no value.
  alternatives at ps env v r every alts k (DefaultCase rhs :: rest) = do
    here <- if every then pure DefaultNone else defaulted at (entering (CaseAlternative k) ps) env v r alts rhs
    (here ::) <$> alternatives at ps env v r every alts (S k) rest
  alternatives at ps env v r every alts k (ConstCase _ rhs :: rest) =
    (\t, more => ConstantAlt t :: more) <$> tree at (entering (CaseAlternative k) ps) env rhs
                                       <*> alternatives at ps env v r every alts (S k) rest
  -- A suspension has one form: its alternative binds the value's type,
  -- erased, and the value forced, which stands as the scrutinee does, at
  -- the type the suspension's is of.
  alternatives at ps env v r every alts k (DelayCase ty arg rhs :: rest) =
    (\t, more => DelayAlt {ty} {arg} t :: more)
      <$> tree at (entering (CaseAlternative k) ps) ((Erased, ty, Nothing) :: (fst v, arg, forced (snd (snd v))) :: env) rhs
      <*> alternatives at ps env v r every alts (S k) rest
    where
      forced : Maybe ClosedTerm -> Maybe ClosedTerm
      forced (Just (TDelayed _ _ t)) = Just t
      forced _ = Nothing

  ||| A default alternative. On a shape not matched yet it stands for each
  ||| constructor the alternatives leave out, which it is walked once for, as
  ||| that constructor; on anything else it is walked once.
  defaulted : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
              At -> Pats -> Env vs -> Standing -> List ClosedTerm -> List (CaseAlt vs) -> CaseTree vs ->
              Front (AltNode AtRole vs)
  defaulted at ps env (Pattern p, _, _) r alts rhs = do
    let named = mapMaybe tagOf alts
    every <- matchedAmong at alts
    case map (\c => fullname c.read.def) (filter (\c => not (elem (cast c.tag) named)) every) of
      -- Matched on no constructor (literals), the default is one clause.
      [] => DefaultOnce <$> tree at ps env rhs
      others => DefaultExpanded <$> expand at ps env p r others rhs
  defaulted at ps env _ r alts rhs = DefaultOnce <$> tree at ps env rhs

  -- The tag an alternative names its constructor by.
  tagOf : CaseAlt ws -> Maybe Int
  tagOf (ConCase _ t _ _) = Just t
  tagOf _ = Nothing

  ||| A default walked once per constructor it stands for, with the shape
  ||| matched to it, each a step below the default named by that
  ||| constructor.
  expand : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> StandIn -> List ClosedTerm -> List Name -> CaseTree vs ->
           Front (List (ExpansionNode AtRole vs))
  expand at ps env p r [] rhs = pure []
  expand at ps env p r (cn :: cns) rhs = do
    here <- the (Front (ExpansionNode AtRole vs)) $ case !(definitionOf cn) of
      Just (_, cd) => case definition cd.def of
        DCon tag arity _ => do
          (_, con, ps') <- conStands (entering (Expansion cn) ps) (Pattern p) r cd (Ref EmptyFC (DataCon tag arity) cn) (piNames cd.type)
          Expanded cn <$> tree at ps' (rebound p con env) rhs
        _ => pure (NotExpanded cn)
      -- A type's constructors are constructors the context holds.
      Nothing => pure (NotExpanded cn)
    (here ::) <$> expand at ps env p r cns rhs

------------------------------------------------------------------------------
-- A definition's sites
------------------------------------------------------------------------------

||| The names a definition's parameters go by in its source: its type's
||| binders. A type constructor declared without a type (`data T a = ...`)
||| has machine names there; each of its parameters goes by the name its
||| first constructor binds at that position of the type it returns.
export
parameterNames : {auto c : Ref Ctxt Defs} -> GlobalDef -> Front (List Name)
parameterNames def = do
  own <- piNames <$> typeOfDefinition def
  case definition def of
    TCon _ _ _ _ _ (Just (con :: _)) _ => do
      defs <- getDefs
      Just cdef <- lookupExact con (gamma defs)
        | Nothing => pure own
      pure (zipWith named own (returned [] !(typeOfDefinition cdef) ++ replicate (length own) Nothing))
    _ => pure own
  where
    named : Name -> Maybe Name -> Name
    named n@(MN _ _) (Just x) = x
    named n _ = n

    -- The names a constructor's type binds, the innermost first, and at
    -- each argument of the type it returns, the name of the binder it is.
    returned : List Name -> TT vs -> List (Maybe Name)
    returned bound (Bind _ x (Pi {}) sc) = returned (x :: bound) sc
    returned bound tm = map binderOf (snd (getFnArgs tm))
      where
        binderOf : TT vs -> Maybe Name
        binderOf (Local _ _ i _) = getAt i bound
        binderOf _ = Nothing

||| The writer a definition is, at its address, within another as it was
||| read, with its parameters' kinds and what its leaves give.
atDefinition : (writer : Address) -> (within : GlobalDef) -> Defined -> List (Maybe Static) -> Giving -> At
atDefinition writer within d kinds giving =
  MkAt writer (arityOf d) OwnOnly kinds within (show (fullname d.def)) (location d.def) d.def giving

||| An argument as a message shows it.
export
showArgument : {auto c : Ref Ctxt Defs} -> ArgumentText -> Front String
showArgument (TemplateText def t held heads) = render !(parameterNames def) t held heads
showArgument (TermText t) = showTT t
showArgument (WrittenText def stands names t) = display !(parameterNames def) stands names t
showArgument (ParameterText def i) = (\names => parameterName names i) <$> parameterNames def

||| What a parameter of the definition stands for, by its kind and its value
||| at the node: a type, a family or a form is that value, its marker
||| unless the node has a head for it; a dictionary the dictionary at its
||| marker; a shape a fresh stand-in for the whole parameter, at the empty
||| path; and anything else erased or a runtime value, by its quantity.
standFor : Maybe Static -> RigCount -> Nat -> ClosedTerm -> Pats -> (Stand, Pats)
standFor (Just AType) _ i v ps = (Fixed v, ps)
standFor (Just AFamily) _ i v ps = (Fixed v, ps)
standFor (Just AForm) _ i v ps = (Fixed v, ps)
standFor (Just ADictionary) _ i v ps = (Holds (Own i []), ps)
standFor (Just AShape) _ i v ps = fresh i [] ps
standFor Nothing rig _ v ps = (byQuantity (use rig), ps)

||| The definition's parameters, off its type, each standing as its kind
||| and its value at the node say, with the sites its runtime binders'
||| types and its result type write: the types the translation reads off a
||| callee's signature. The walk is at the binder `here` of the type as it
||| shows it, each binder's type a step into the binder and the binders
||| after it a step into its scope, as the type's own constructors are.
signature : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            At -> List (Maybe Static, ClosedTerm) -> (i : Nat) -> (here : Place) -> ClosedTerm -> Pats ->
            Front (SignatureNode AtRole, Pats, List Standing)
signature at [] i here ty ps = (\r => (MkSignatureNode [] r, ps, [])) <$> readClosed at ({ place := here } ps) ty
signature at ((k, v) :: ks) i here ty ps = do
  Bind _ x (Pi _ rig _ a) sc <- showingBinder ty
    | ty' => (\r => (MkSignatureNode [] r, ps, [])) <$> readClosed at ({ place := here } ps) ty'
  parameter x rig a sc
  where
    runtime : Stand -> Bool
    runtime Runtime = True
    runtime (Pattern _) = True
    runtime _ = False

    parameter : Name -> RigCount -> ClosedTerm -> TT [x] -> Front (SignatureNode AtRole, Pats, List Standing)
    parameter x rig a sc = do
      let (st, ps') = standFor k rig i v ps
      own <- if runtime st then Just <$> readClosed at ({ place := into BinderType here } ps) a else pure Nothing
      (rest, ps'', params) <- signature at ks (S i) (into BinderScope here) (subst (termOf st) sc) ps'
      pure ({ binders $= (own ::) } rest, ps'', (st, x, Just a) :: params)

||| The case tree's scope, one variable per parameter, the first first, each
||| standing as the signature made it. The scope has one variable per binder
||| of the type, so the last clause is only for a type that shows fewer
||| binders even normalised.
envOf : (args : Scope) -> List Standing -> Env args
envOf [] _ = []
envOf (x :: xs) (e :: es) = e :: envOf xs es
envOf (x :: xs) [] = (Runtime, x, Nothing) :: envOf xs []

||| A projection of a dictionary parameter, by its tree and its own
||| parameters' kinds.
dictionaryProjection : {0 args : Scope} -> List (Maybe Static) -> CaseTree args -> Maybe Projected
dictionaryProjection kinds t = do
  p <- projectionShape t
  case getAt p.matched kinds of
    Just (Just ADictionary) => Just p
    _ => Nothing

||| The one site of a projection of a dictionary parameter: its record's
||| method, dispatched on the record, at the field's arguments that are the
||| projection's static parameters, as they stand at the node, numbered as
||| the method's own. A dictionary parameter passed so is passed as it is,
||| the one value it holds (`Terms.holed`). It is made where the
||| projection's case tree is, which it stands for.
projectionSite : {auto c : Ref Ctxt Defs} -> At -> Pats -> List (Maybe Static, Standing) -> Projected -> Front (AtRole DispatchReach)
projectionSite at ps params p = do
  (r, root) <- dictionaryRooted [] (markerAt p.matched [])
  args <- traverse own (mapMaybe static (zip [0 .. length p.params] p.params))
  pure (siteAt at (into DefinitionTree ps.place) at.loc (Dispatches r.template root p.field) args)
  where
    static : (Nat, Maybe Nat) -> Maybe (Nat, Nat, Static, ClosedTerm)
    static (q, Just j) = case getAt j params of
      Just (Just k, (st, _, _)) => Just (q, j, k, termOf st)
      _ => Nothing
    static (_, Nothing) = Nothing

    own : (Nat, Nat, Static, ClosedTerm) -> Front Argument
    own (q, j, k, t) = do
      x <- readArgument ps.made q k Nothing t (ParameterText at.writerDef j)
      pure (case k of
              ADictionary => { holds := [PackedBy (OwnParameter j) ::: []] } x
              _ => x)

||| What each parameter stands for at a node: a family the node has a head
||| for is that type constructor applied to parts of the family's value,
||| one level down, each a stand-in of its own, as many as the constructor
||| takes beyond the family's own arrows, which is what a match of the
||| family's value against the constructor would bind; any other parameter
||| is its marker. With the stand-ins made, after those of `ps`. Each head
||| comes with what the flow carried beside it, read where it entered the
||| flow (`Heads.reaching`): the type constructor's name and arity, as the
||| type's form applies it (`Template.formRoot`), since a family's set holds
||| only what heads a family.
nodeValues : {auto c : Ref Ctxt Defs} -> (n : Nat) -> List (Nat, (a : Address ** TypeConstructorAt a)) -> (i : Nat) -> ClosedTerm ->
             Pats -> Front (List ClosedTerm, Pats)
nodeValues Z heads i ty ps = pure ([], ps)
nodeValues (S n) heads i ty ps = do
  Bind _ _ (Pi _ _ _ kind) sc <- showingBinder ty
    | _ => pure ([], ps)
  (v, ps') <- maybe (pure (markerAt i [], ps)) (headed kind) (lookup i heads)
  (vs, ps'') <- nodeValues n heads (S i) (subst v sc) ps'
  pure (v :: vs, ps'')
  where
    arrows : TT vs -> Nat
    arrows (Bind _ _ (Pi {}) sc) = S (arrows sc)
    arrows _ = Z

    -- One stand-in for each part, a level down: the type constructor's
    -- arguments from k on, each at its own field.
    parts : (k : Nat) -> Nat -> Pats -> (List ClosedTerm, Pats)
    parts k Z qs = ([], qs)
    parts k (S m) qs = let (st, qs') = fresh i [k] qs
                           (rest, qs'') = parts (S k) m qs' in
                       (termOf st :: rest, qs'')

    headed : ClosedTerm -> (a : Address ** TypeConstructorAt a) -> Front (ClosedTerm, Pats)
    headed kind (_ ** NamedTypeConstructor name arity) = do
      k <- arrows <$> normaliseClosed kind
      let (ts, ps') = parts 0 (minus arity k) ps
      pure (foldl (App EmptyFC) (Ref EmptyFC (TyCon arity) name) ts, ps')

||| Every site a definition writes at a node, with each parameter standing
||| for its value there (`nodeValues`): its signature's, for every
||| definition; and its case tree's, for one the translation translates
||| (not refused, and with no hook that answers for its every call; the
||| exit's body is translated). A projection of a dictionary has the one
||| site that dispatches on it. With the kinds of the parameters at those
||| values, which the sites are read by.
|||
||| This is where the kinds of the node's own parameters and of every
||| callee's are decided, by `staticsOver` over what each parameter stands
||| for at the node: the decision `classify` makes for a request, made with
||| the node's heads where the request has its values. A request's node is
||| split by the type constructor at the head of each family's value it is
||| given (`Instances.request`, by `rooted`), so the request is translated
||| at a node whose heads its values have, and
||| `staticsOver` over the heads keys no fewer positions than `classify`
||| over the values, which differ only in what the heads leave as markers.
||| So a request's keyed positions are its node's, and the worklist's bound
||| check (`Finite`) finds a bound at each.
nodeSites : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            (writer : Address) -> Defined -> (List ClosedTerm, Pats) -> Front (List (Maybe Static), SignatureNode AtRole, BodyNode AtRole)
nodeSites writer d (values, made) = do
  (kinds', result) <- staticsOver (show (fullname d.def)) (arityOf d) d.type (map (\v => Just (v, AValue)) values)
  let kinds = toList (map staticOf kinds')
  at <- atDefinition writer d.def d kinds <$> givingOf (givesAfter (arityOf d) (memberPlaces d)) result
  (sig, ps, params) <- signature at (zip kinds values) 0 (into DefinitionType made.place) d.type made
  body <- the (Front (BodyNode AtRole)) $ case d.matched of
    Just m => do
      st <- getState
      if contains at.writer st.refused || answersFor d.registered then pure Untranslated else
        case dictionaryProjection kinds m.tree of
          Just p => ProjectionBody <$> projectionSite at ps (zip kinds params) p
          Nothing => CaseBody <$> tree at (entering DefinitionTree ps) (envOf m.args params) m.tree
    Nothing => pure NoBody
  pure (kinds, sig, body)
  where
    -- What the registry made of the definition's calls, read with it: a
    -- hook that answers for its every call leaves no body translated, and
    -- a `%foreign` with no hooks has none to translate.
    answersFor : Registered -> Bool
    answersFor r = case callHooks r of
      Right hs => answersForCalls hs
      Left _ => False

||| A definition as its node with no heads reads it, every parameter its
||| marker: its text annotated with the walk there (`ReadingTree`), and its
||| families by parameter index, the type parameters whose kind is a
||| function into a universe. Both come from the one decision of its
||| parameters' kinds. A node of it with heads is split by the type
||| constructor at the head of each family's value (`Heads`), and read at
||| those heads (`sitesOf`).
public export
record NodeReading where
  constructor MkNodeReading
  tree : ReadingTree AtRole
  families : List Nat

||| A definition read at a node, at its address and as the walk holds it:
||| each of its families the node has a head for stands for that type
||| constructor (`nodeValues`), and every other parameter for its marker.
atNode : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         Address -> Defined -> (heads : List (Nat, (a : Address ** TypeConstructorAt a))) ->
         Front (List (Maybe Static), SignatureNode AtRole, BodyNode AtRole)
atNode a d heads = do
  values <- nodeValues (arityOf d) heads 0 d.type (MkPats 0 [] [<])
  nodeSites a d values

||| A definition as its node with no heads reads it, from the definition
||| the walk holds, with its fields' types read there too (a type
||| constructor's constructors' fields, `Fields.fieldSites`; none for any
||| other definition).
export
readingOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Address -> Defined -> (fields : List (TypeRead AtRole [])) ->
            Front NodeReading
readingOf a d fields = do
  (kinds, sig, body) <- nodeSites a d !(nodeValues (arityOf d) [] 0 d.type (MkPats 0 [] [<]))
  pure (MkNodeReading (MkReadingTree fields sig body) (mapMaybe family (zip [0 .. length kinds] kinds)))
  where
    family : (Nat, Maybe Static) -> Maybe Nat
    family (i, Just AFamily) = Just i
    family _ = Nothing

||| A definition read at a node with heads, the definition as the walk
||| holds it, each head the type constructor the flow carried.
export
sitesOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Address -> Defined ->
          (heads : List (Nat, (a : Address ** TypeConstructorAt a))) -> Front (ReadingTree AtRole)
sitesOf a d heads = (\(_, sig, body) => MkReadingTree [] sig body) <$> atNode a d heads

||| A closed term over the writer's markers and the stand-ins `stands`,
||| numbered from 0, read as a type `within` holds, at `place` in the
||| writer's text: a data constructor's field type, its markers the data
||| type's parameters and its stand-ins the parts of them its
||| constructor's type binds, every site it writes at `fc`. The writer is a
||| type, at its address and as it was read: what a type writes has no
||| leaves, and no case tree that requests the type again.
export
sitesIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          (writer : Address) -> Defined -> (within : GlobalDef) -> (stands : List StandIn) -> (place : Place) -> FC -> ClosedTerm ->
          Front (TypeRead AtRole [])
sitesIn writer d within stands place fc tm =
  located <$> readClosed (atDefinition writer within d [] ValueLeaves) (MkPats (length stands) stands place) tm
  where
    -- A site at `fc`, its reach, which its role is, as it was.
    at : Site -> Site
    at s = MkSite s.writer s.writerDef s.params s.within s.reach s.arguments fc

    located : TypeRead AtRole [] -> TypeRead AtRole []
    located = runIdentity . traverseTypeRead (\x => Id (MkAtRole (MkMade x.made.place (at x.made.site)) x.role))
