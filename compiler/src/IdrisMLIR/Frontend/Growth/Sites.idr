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
||| parameters past those it has (`Parameters`).
|||
||| A leaf knows what its matches made of the parameters: a match on a shape
||| is substituted where it happens, so that `count (S m) = count (S (S m))`
||| writes `S (S m)` with `m` a part one level down, and a default clause,
||| expanded into the constructors it stands for, writes the constructor it
||| matched. Each part a match binds has a stand-in of its own
||| (`Template.StandIn`), kept as its own marker up to the reading, so that
||| a site's term is an instance's argument with a value put in for each
||| marker. A dictionary keeps its marker through every match, since its
||| root is the writer's head, which the flow reads.
module IdrisMLIR.Frontend.Growth.Sites

import Core.Case.CaseTree
import Core.Context
import Core.Core
import Core.TT
import Libraries.Data.List.SizeOf
import Libraries.Data.NameMap

import IdrisMLIR.Frontend.Growth.Template
import IdrisMLIR.Frontend.Profile
import IdrisMLIR.Frontend.Resolve
import IdrisMLIR.Frontend.Translate.Boundary
import IdrisMLIR.Frontend.Translate.Cases
import IdrisMLIR.Frontend.Translate.Closed
import IdrisMLIR.Frontend.Translate.Errors
import IdrisMLIR.Frontend.Translate.Instances
import IdrisMLIR.Frontend.Translate.State
import IdrisMLIR.Frontend.Translate.Types
import IdrisMLIR.Frontend.Walk
import IdrisMLIR.Proof.Requests
import IdrisMLIR.Proof.Template
import IdrisMLIR.Registry

import Control.WellFounded
import Data.DPair
import Data.List
import Data.List1
import Data.SortedSet
import Data.String

%default total

||| What a site reaches: a definition it calls (a function, an
||| implementation, a projection, a constructor holding dictionaries), a type
||| constructor it builds, method `k` of a dictionary, which the template
||| is, with that dictionary's root, the application of a compile-time
||| form at a use, which no definition is (`Translate.State.AtUse`), at the
||| form's type (0), the form (1) and the use's static arguments (2 on), or
||| the choice of a head, a member of which it makes, its one argument.
public export
data Reach = Calls Address | Builds Address | Dispatches Template Root Nat | Applies | Makes ChoiceHead

||| Where a site's writer reads its parameters: all its own; or, in the
||| walk of a member's application at a use, its own below `from` and from
||| there on the positions of the application the use gives, parameter
||| `from + j` its position j (`Translate.State.AtUse`). The two ranges are
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

||| What a message shows an argument by (below).
export
data ArgumentText : Type

||| One argument a site writes, whole: the target's parameter it is at (of
||| a dispatched method, its own, in the order its field's lambdas take
||| them), its kind, the template written there and its root, as its
||| kind's one reading gives them (`rooted`) and as the target is given it
||| (`asGiven`), the closed term it was read off, over the writer's markers
||| and the site's stand-ins (none for a part of a type already read),
||| those stand-ins, which a reading of the term again reads it with, the
||| choice a dictionary the running program chooses there is a member of
||| (its binder's type's), which a reading again reads it with too, and
||| what a message shows it by. Only a refusal prints that, and most
||| arguments are in none, so it is read where a message is made
||| (`showArgument`).
public export
record Argument where
  constructor MkArgument
  position : Nat
  kind : Static
  template : Template
  root : Root
  term : Maybe ClosedTerm
  stands : List StandIn
  memberOf : Maybe ChoiceHead
  shown : ArgumentText

||| One site: who wrote it (whose parameters the templates' `Var`s are, as
||| `params` reads them), the definition whose text holds it, what it
||| reaches, the argument written at each static position of the target,
||| and where it is.
public export
record Site where
  constructor MkSite
  writer : Address
  params : Parameters
  within : Address
  reach : Reach
  arguments : List Argument
  fc : FC

------------------------------------------------------------------------------
-- What each variable stands for
------------------------------------------------------------------------------

||| A dictionary a variable holds: the writer's dictionary parameter `i` at
||| match depth `d`, and the fields matched out of it, the first first; or
||| one known as a term, the dictionary a constructor holds, matched out of
||| a value, or one written where a lambda's dictionary binder takes it.
data Dict = Own Nat Nat (List Nat) | Known ClosedTerm

||| What a variable of the walk stands for: a compile-time value that is
||| never code (a parameter's type, family or form at the node, a type a
||| match reads off the scrutinee's type, an erased argument a lambda is
||| applied to); a dictionary; a runtime value whose shape keys the
||| instance, not matched yet (a stand-in), or matched (a constructor of
||| stand-ins); a value of quantity 0; or any other runtime value. A shape
||| not matched yet carries its stand-in, so that a match knows what it
||| rebinds and how deep without looking it up.
data Stand = Fixed ClosedTerm
           | Holds Dict
           | Pattern StandIn
           | Shape ClosedTerm
           | Erased
           | Runtime

||| What a stand is in a closed term: a runtime value as `closeWritten` has
||| it, a quantity-0 value as a placeholder. The writer's own dictionary is
||| the field its path reads, which with no field matched out is its marker.
termOf : Stand -> ClosedTerm
termOf (Fixed t) = t
termOf (Holds (Own i d path)) = fieldAt i d path
termOf (Holds (Known t)) = t
termOf (Pattern p) = standInAt p
termOf (Shape t) = t
termOf Erased = Erased EmptyFC Placeholder
termOf Runtime = Erased EmptyFC Impossible

||| A variable as the walk knows it: what it stands for, the name a message
||| shows it by, and its type where that is known.
Standing : Type
Standing = (Stand, Name, Maybe ClosedTerm)

||| What each variable of a scope stands for, the innermost first, so that a
||| variable out of scope has nothing to stand for.
data Env : Scope -> Type where
  Nil : Env []
  (::) : Standing -> Env vs -> Env (v :: vs)

standings : Env vs -> List Standing
standings [] = []
standings (e :: es) = e :: standings es

append : Env as -> Env vs -> Env (as ++ vs)
append [] env = env
append (e :: es) env = e :: append es env

||| The entry of a variable, which its scope says is there.
entryAt : Env vs -> (idx : Nat) -> (0 _ : IsVar n idx vs) -> Standing
entryAt (e :: _) Z _ = e
entryAt (_ :: es) (S i) p = entryAt es i (dropLater p)
entryAt [] _ First impossible
entryAt [] _ (Later _) impossible

||| A term in scope, closed with what each variable stands for.
close : {vs : Scope} -> Env vs -> TT vs -> ClosedTerm
close env t = closeWritten EmptyFC (map (\(s, _, _) => the (VarInfo ()) (TypeValue (termOf s))) (standings env)) t

||| What a call knows of a term it gives: a variable that holds a dictionary
||| is an implementation. The translation passes a caller's dictionaries to
||| its blocks as explicit arguments, so the callee's binder alone does not
||| say.
offerOf : Env vs -> TT vs -> Offer
offerOf env (Local _ _ idx p) = case entryAt env idx p of
  (Holds _, _, _) => AnImplementation
  _ => AValue
offerOf _ _ = AValue

------------------------------------------------------------------------------
-- Pattern stand-ins
------------------------------------------------------------------------------

||| The stand-ins made on the walk's path so far, and the next one's number.
public export
record Pats where
  constructor MkPats
  next : Nat
  made : List StandIn

||| A fresh stand-in at parameter `i`, depth `d`.
fresh : (i, d : Nat) -> Pats -> (Stand, Pats)
fresh i d ps = let p = MkStandIn ps.next i d in (Pattern p, MkPats (S ps.next) (p :: ps.made))

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

||| A term closed as a dictionary's key holds it: every runtime value and
||| shape it mentions a hole marker, numbered by first occurrence, as the
||| translation marks what an implementation closes over; with the place in
||| the scope of the value each marker stands for, by marker.
holedAt : {vs : Scope} -> Env vs -> TT vs -> (ClosedTerm, List Nat)
holedAt env t =
  let valued = zipWith value [0 .. length (standings env)] (standings env)
      c = closeWritten EmptyFC (map (\(v, _) => the (VarInfo ()) (TypeValue v)) valued) t
      order = fst (occurring (SortedSet.fromList (mapMaybe snd valued)) c ([<], empty)) <>> []
  in (replacing (zipWith (\r, n => (n, holeMarker r)) [0 .. length order] order) c, mapMaybe placeOf order)
  where
    -- The place a runtime value's name was made for (`runtimeAt`).
    placeOf : Name -> Maybe Nat
    placeOf n = case probeOf n of
      Just (ProbeRuntimeAt p) => Just p
      _ => Nothing

    -- A runtime value or a shape as a name of its own, by its place in
    -- the scope, which is renumbered once the term is closed.
    runtimeAt : Nat -> (ClosedTerm, Maybe Name)
    runtimeAt p = (probeTerm (ProbeRuntimeAt p), Just (probeName (ProbeRuntimeAt p)))

    value : Nat -> Standing -> (ClosedTerm, Maybe Name)
    value p (Runtime, _, _) = runtimeAt p
    value p (Pattern _, _, _) = runtimeAt p
    value p (Shape _, _, _) = runtimeAt p
    value p (s, _, _) = (termOf s, Nothing)

||| A term closed as a dictionary's key holds it (`holedAt`).
holed : {vs : Scope} -> Env vs -> TT vs -> ClosedTerm
holed env t = fst (holedAt env t)

||| The types of the runtime values a term closed as a dictionary's key
||| mentions, by marker (`holedAt`), where the walk knows each: what a lambda
||| closes over, which the member it is holds as one value
||| (`Closed.packedType`). Nothing when the walk knows one's type not.
closedOverTypes : {vs : Scope} -> Env vs -> (places : List Nat) -> Maybe (List ClosedTerm)
closedOverTypes env = traverse (\p => getAt p (standings env) >>= \(_, _, ty) => ty)

||| What a definition's leaves give at a node: a member of its result
||| type's choice, which a lambda there is, of that type; or a value.
data Giving = MemberLeaves ClosedTerm | ValueLeaves

||| What the walk knows of the writer: its address, how many parameters it
||| takes, and how its sites read them; the definition whose text holds
||| what it reads (for a field type, the field's constructor); its name for
||| the normalisers' messages, its location, which a site with no location
||| of its own takes, its definition, whose type names its parameters, by
||| which a message shows their markers, and what its leaves give.
record At where
  constructor MkAt
  writer : Address
  arity : Nat
  params : Parameters
  within : Address
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
||| which is no machine name, so that the solving's quotation keeps it.
display : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> (names : List Name) -> Pats -> Env vs -> TT vs -> Front String
display names ps env t = do
  shown <- traverse shownAs (standings env)
  showTT (named names ps.made !(solved (closeWritten EmptyFC shown t)))
  where
    -- The text a name prints as becomes an identifier here, where the
    -- message is made.
    shownAs : Standing -> Front (VarInfo ())
    shownAs (_, x, _) = (\i => TypeValue (Ref EmptyFC Bound (UN (Basic i)))) <$> core (intern (show x))

||| A site of the writer's, at its own location when it has none.
siteAt : At -> FC -> Reach -> List Argument -> Site
siteAt at fc reach args = MkSite at.writer at.params at.within reach args (if isEmptyFC fc then at.loc else fc)

||| The name of what an address holds, for a message.
nameText : {auto c : Ref Ctxt Defs} -> Address -> Front String
nameText a = do
  defs <- getDefs
  maybe (pure "_") (\n => show <$> fullNames n) (nameAt (gamma defs) a)

||| The name the writer's type gives its parameter i, as a message shows it.
parameterName : (names : List Name) -> Nat -> String
parameterName names i = maybe "_" show (getAt i names)

mutual
  ||| A template as a message shows it, each marker by the writer's name for
  ||| its parameter.
  render : {auto c : Ref Ctxt Defs} -> (names : List Name) -> Template -> Front String
  render names (Var i _) = pure (parameterName names i)
  render names (Head (Just a) []) = nameText a
  render names (Head (Just a) cs) = (\h, as => "(" ++ unwords (h :: as) ++ ")") <$> nameText a <*> renderAll names cs
  render names (Head Nothing cs) = (\as => "(" ++ joinBy " -> " as ++ ")") <$> renderAll names cs
  render names (Leaf _) = pure "_"
  render names (Token _) = pure "_"
  render names (Formal _ _) = pure "_"
  render names (Choice _ ls) = (\as => "{" ++ joinBy " | " as ++ "}") <$> renderAll names ls
  render names (Opaque a cs) = (\h, as => "(" ++ unwords (h :: as) ++ ")") <$> nameText a <*> renderAll names cs
  render names (Applied i _ cs) = (\as => "(" ++ unwords (parameterName names i :: as) ++ ")") <$> renderAll names cs
  render names (Computing i _ cs) = (\as => "(" ++ unwords (parameterName names i :: as) ++ ")") <$> renderAll names cs
  render names (Field k t) = (\s => s ++ "." ++ show k) <$> render names t
  render names (Member (InterfaceHead a)) = (\s => "{" ++ s ++ " the running program chooses}") <$> nameText a
  render names (Member ArrowHead) = pure "{a polymorphic function the running program chooses}"
  render names (Member UnshownHead) = pure "{a member the running program chooses}"

  renderAll : {auto c : Ref Ctxt Defs} -> (names : List Name) -> List Template -> Front (List String)
  renderAll names [] = pure []
  renderAll names (t :: ts) = (::) <$> render names t <*> renderAll names ts

||| What a message shows an argument by, read where a message is made
||| (`showArgument`): a template, each marker by the writer's name for its
||| parameter; a closed term; a term as written, in its scope; or one of
||| the writer's parameters. It holds the definition the names come from,
||| never a computation: the sites are kept, and a computation kept with
||| them is one the pipeline's closure analysis cannot tell from any other
||| of its type, those that read the translation's state among them.
data ArgumentText : Type where
  TemplateText : (writer : GlobalDef) -> Template -> ArgumentText
  TermText : ClosedTerm -> ArgumentText
  WrittenText : {vs : Scope} -> (writer : GlobalDef) -> Pats -> Env vs -> TT vs -> ArgumentText
  ParameterText : (writer : GlobalDef) -> Nat -> ArgumentText

------------------------------------------------------------------------------
-- What a type builds
------------------------------------------------------------------------------

||| The type constructor the boundary read at an address, if one is there.
typeConstructorAt : Address -> Front (Maybe Defined)
typeConstructorAt a = do
  Just d <- definitionRead a
    | Nothing => pure Nothing
  pure (case definition d.def of
          TCon {} => Just d
          _ => Nothing)

mutual
  ||| A template with every child at a type constructor's position read by
  ||| its role (`Role`), at every head, the written ones and those
  ||| unfolding made alike: an `Index` as a closed part, a `Formed` shape as
  ||| its form (`formedTemplate`), and any other as itself. The data key
  ||| holds no more than this of each argument (`Types.argumentKey`), so a
  ||| height read here bounds the key's.
  eraseIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Template -> Front Template
  eraseIn (Head (Just a) cs) = do
    Just tc <- typeConstructorAt a
      | Nothing => Head (Just a) <$> eraseAll cs
    Head (Just a) <$> erasedAt (!(tyConFacts tc)).roles 0 cs
  eraseIn (Head Nothing cs) = Head Nothing <$> eraseAll cs
  eraseIn (Choice t ls) = Choice <$> eraseIn t <*> eraseAll ls
  eraseIn (Opaque a cs) = Opaque a <$> eraseAll cs
  eraseIn (Applied i d cs) = Applied i d <$> eraseAll cs
  eraseIn (Computing i d cs) = Computing i d <$> eraseAll cs
  eraseIn (Field k t) = Field k <$> eraseIn t
  eraseIn t@(Var _ _) = pure t
  eraseIn t@(Leaf _) = pure t
  eraseIn t@(Token _) = pure t
  eraseIn t@(Formal _ _) = pure t
  eraseIn t@(Member _) = pure t

  eraseAll : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> List Template -> Front (List Template)
  eraseAll [] = pure []
  eraseAll (t :: ts) = (::) <$> eraseIn t <*> eraseAll ts

  erasedAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> List Role -> Nat -> List Template -> Front (List Template)
  erasedAt rs j [] = pure []
  erasedAt rs j (t :: ts) = (::) <$> asRole (roleAt j rs) t <*> erasedAt rs (S j) ts

  asRole : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Role -> Template -> Front Template
  asRole Keyed t = eraseIn t
  asRole Formed t = formedTemplate t
  asRole Held t = eraseIn t
  asRole Index _ = pure (Leaf 1)

||| The site a type constructor's head writes: `Builds` at the arguments a
||| value of it represents, each already read without what no value
||| represents; none for a head that is no type constructor.
built : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> At -> FC -> Address -> List Template -> Front (List Site)
built at fc a cs = do
  Just tc <- typeConstructorAt a
    | Nothing => pure []
  let args = map argument (mapMaybe (\j => (j,) <$> getAt j cs) !(represented tc))
  pure [siteAt at fc (Builds a) args]
  where
    -- A part of a type already read, with no term of its own to root.
    argument : (Nat, Template) -> Argument
    argument (j, t) = MkArgument j AType t Unrooted Nothing [] Nothing (TemplateText at.writerDef t)

mutual
  ||| The sites at every type constructor of a template, at any depth: in a
  ||| stuck definition's leaves, in an unfolded synonym, under a binder.
  buildsIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> At -> FC -> Template -> Front (List Site)
  buildsIn at fc (Head (Just a) cs) = (++) <$> built at fc a cs <*> buildsAll at fc cs
  buildsIn at fc (Head Nothing cs) = buildsAll at fc cs
  buildsIn at fc (Choice t ls) = (++) <$> buildsIn at fc t <*> buildsAll at fc ls
  buildsIn at fc (Opaque _ cs) = buildsAll at fc cs
  buildsIn at fc (Applied _ _ cs) = buildsAll at fc cs
  buildsIn at fc (Computing _ _ cs) = buildsAll at fc cs
  buildsIn at fc (Field _ t) = buildsIn at fc t
  buildsIn at fc (Var _ _) = pure []
  buildsIn at fc (Leaf _) = pure []
  buildsIn at fc (Token _) = pure []
  buildsIn at fc (Formal _ _) = pure []
  buildsIn at fc (Member _) = pure []

  buildsAll : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> At -> FC -> List Template -> Front (List Site)
  buildsAll at fc [] = pure []
  buildsAll at fc (t :: ts) = (++) <$> buildsIn at fc t <*> buildsAll at fc ts

||| What a closed type, a term of a site whose stand-ins are `stands`,
||| builds: its canonical form as data instances compare type arguments,
||| its template, and that without what no value of each type constructor
||| in it represents, so that a head inside an index builds nothing.
builds : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> At -> List StandIn -> FC -> ClosedTerm -> Front (List Site)
builds at stands fc t = buildsIn at fc !(eraseIn !(templateOf stands AType !(canonicalTypeArg t)))

------------------------------------------------------------------------------
-- Sites of calls
------------------------------------------------------------------------------

||| An argument of an application, made where it is a subterm: as written,
||| and its walks as code, as a static value, and as a member applied at a
||| use of a type (`useOf`), each suspended there.
record Arg (vs : Scope) where
  constructor MkArg
  written : TT vs
  asCode : Lazy (Front (List Site))
  asStatic : Lazy (Front (List Site))
  asUse : ClosedTerm -> Front (List Site)

||| An argument under a binder the walk binds.
overBinder : Arg vs -> Arg (x :: vs)
overBinder a = MkArg (weaken a.written) a.asCode a.asStatic a.asUse

||| A closed value as an argument, a compile-time value or a marker, whose
||| walks write nothing: it holds no application of the program's.
closedArg : ClosedTerm -> Arg vs
closedArg t = MkArg (embedClosed t) (pure []) (pure []) (\_ => pure [])

||| Arguments each walked as a static value.
statics : List (Arg vs) -> Front (List Site)
statics xs = (>>= id) <$> traverse (\x => Force x.asStatic) xs

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
  pure (decided 0 os (toList kinds) positions binders, rest)
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

mutual
  ||| The types of the runtime values a dictionary closes over, in the order
  ||| the translation finds them (`Terms.holed`): each argument a definition
  ||| that gives a dictionary takes at a runtime parameter that is no
  ||| dictionary, where the argument mentions a runtime value (a hole
  ||| marker), at that parameter's type; a compile-time value there (an
  ||| implementation, a polymorphic function: `compileTimeBinder`) is
  ||| looked into.
  ||| A value two parameters share is listed at each: the translation holds
  ||| it once, so the packing below is never shorter than its.
  heldIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> ClosedTerm -> Front (List ClosedTerm)
  heldIn t = heldSpine t []

  heldSpine : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
              ClosedTerm -> List (ClosedTerm, Lazy (Front (List ClosedTerm))) -> Front (List ClosedTerm)
  heldSpine (App _ f a) args = heldSpine f ((a, heldIn a) :: args)
  heldSpine (Ref _ _ n) args = do
    Just (_, d) <- definitionOf n
      | Nothing => pure []
    case definition d.def of
      -- A definition of one right-hand side.
      PMDef {} => if oneLeaf d then heldOver d.def 0 d.type args else pure []
      DCon {} => heldOver d.def 0 d.type args
      _ => pure []
  heldSpine _ _ = pure []

  -- The arguments from position `j` of the definition on, its type there
  -- `ty`, what it takes at each read as the definition's (`argumentAt`).
  heldOver : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
             GlobalDef -> (j : Nat) -> ClosedTerm -> List (ClosedTerm, Lazy (Front (List ClosedTerm))) ->
             Front (List ClosedTerm)
  heldOver def j ty [] = pure []
  heldOver def j ty ((a, inner) :: rest) = do
    Bind _ _ (Pi _ rig _ aty) sc <- normaliseClosed ty
      | _ => pure []
    here <- case argumentAt def j rig of
              RuntimeValue _ => if not (mentionsHole a) then pure [] else do
                aty' <- normaliseClosed aty
                if !(compileTimeBinder rig aty') then Force inner else pure [aty']
              _ => pure []
    (here ++) <$> heldOver def (S j) (subst a sc) rest

||| A static argument at a position, read off the closed term its key holds
||| at its kind (`rooted`), a term of a site whose stand-ins are `stands`,
||| as its target is given it, a member of the choice `memberOf` where the
||| running program chooses it (`asGiven`), with how a message shows it.
export
readArgument : {auto c : Ref Ctxt Defs} -> List StandIn -> Nat -> Static -> (memberOf : Maybe ChoiceHead) -> ClosedTerm ->
               ArgumentText -> Front Argument
readArgument stands j k memberOf t shown =
  (\(tm, root) => MkArgument j k (asGiven memberOf (tm, root)) root (Just t) stands memberOf shown) <$> rooted stands k t

||| What the callee of a dictionary that closes over runtime values does
||| with them: it holds them as one value, the first and a pair of the rest
||| (`Closed.packedType`), and takes them apart with the pair's projections
||| (`Closed.unpacked`). So each split is a `Calls` of each projection at
||| the first's type and the rest's, and a build of that pair.
packing : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> At -> List StandIn -> FC -> List ClosedTerm -> Front (List Site)
packing at stands fc [] = pure []
packing at stands fc [_] = pure []
packing at stands fc (t :: ts@(u :: us)) = do
  rest <- packedType (u ::: us)
  (pair, first, second) <- pairNames
  halves <- sequence [readArgument stands 0 AType Nothing t (TermText t), readArgument stands 1 AType Nothing rest (TermText rest)]
  here <- traverse (split halves) [first, second]
  p <- refTo EmptyFC pair
  built <- builds at stands fc (App EmptyFC (App EmptyFC p t) rest)
  later <- packing at stands fc ts
  pure (catMaybes here ++ built ++ later)
  where
    split : List Argument -> Name -> Front (Maybe Site)
    split halves n = do
      Just (a, _) <- definitionOf n
        | Nothing => pure Nothing
      pure (Just (siteAt at fc (Calls a) halves))

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

||| One static argument, closed as its key holds it at its kind, and read
||| (`rooted`): a type, family, form or shape as written over the markers
||| and the site's stand-ins (a type's template reads it in full normal
||| form); a dictionary with what it closes over as hole markers, so that
||| its template and its root read one closed term, and as the callee is
||| given it (`asGiven`): one the running program chooses is a member of
||| the choice of the binder's type, which the translation dispatches on.
||| With the sites of the types a type or a family builds, and of the
||| packing of the values a dictionary closes over.
argument : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> Given vs -> Static -> Front (Argument, List Site)
argument at ps env fc g k = do
  (v, beside) <- the (Front (ClosedTerm, Front (List Site))) $ case k of
    AType => pure (g.offer.value, builds at ps.made fc g.offer.value)
    AFamily => pure (g.offer.value, builds at ps.made fc g.offer.value)
    AForm => pure (g.offer.value, pure [])
    AShape => pure (g.offer.value, pure [])
    ADictionary => do
      d <- solved (holed env g.offer.arg.written)
      pure (d, heldIn d >>= packing at ps.made fc)
  memberOf <- case k of
    ADictionary => Just <$> choiceAt g.binder
    _ => pure Nothing
  x <- readArgument ps.made g.position k memberOf v (WrittenText at.writerDef ps env g.offer.arg.written)
  pure (x, !beside)

||| A site reaching a target at the static arguments of those given, with
||| the sites of the types its type arguments build.
callSite : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> Reach -> List (Given vs) -> Front (List Site)
callSite at ps env fc reach gs = do
  ws <- traverse (\(g, k) => argument at ps env fc g k) (mapMaybe static gs)
  pure (siteAt at fc reach (map fst ws) :: (ws >>= snd))
  where
    static : Given vs -> Maybe (Given vs, Static)
    static g = case g.taking of
      AsStatic k => Just (g, k)
      AsCode => Nothing
      Nowhere => Nothing

||| A member of the choice of head `k` that the place makes, `written`
||| closed as a dictionary's key holds it (`d`, its runtime values hole
||| markers), and the types of the values it holds as one: the member
||| writes its form at its choice's position, which every dispatch on the
||| choice reads (`Translate.Choices`), with the packing of the values it
||| holds, as a dictionary argument does (`argument`). What its body
||| requests at a use is its use's walk (`useOf`).
memberAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> ChoiceHead -> (d : ClosedTerm) -> (holding : List ClosedTerm) -> TT vs ->
           Front (List Site)
memberAt at ps env fc k d holding written = do
  x <- readArgument ps.made 0 ADictionary Nothing d (WrittenText at.writerDef ps env written)
  packed <- packing at ps.made fc holding
  pure (siteAt at fc (Makes k) [x] :: packed)

||| A lambda where the member table says a member stands: the member of its
||| type's choice (`Translate.Terms.member`), of a polymorphic function
||| type, whose head is the arrow, written at its choice's position
||| (`memberAt`), holding the runtime values of the scope it mentions. A
||| lambda is a value, so the program fixes it.
lambdaAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> TT vs -> Front (List Site)
lambdaAt at ps env fc lam = do
  let (form, places) = holedAt env lam
  d <- solved form
  -- A value the walk binds with no type (a case's field past the binders
  -- its constructor's type shows) is packed with nothing it knows of the
  -- pair's halves, so the packing is left out with it.
  memberAt at ps env fc ArrowHead d (maybe [] id (closedOverTypes env places)) lam

||| What a value of a type in normal form, over the writer's markers, is:
||| a member of its type's choice, no member, or what only an instance
||| decides (`Boundary.choiceHolding`, the decision the translation makes at
||| each instance, where an undecided head is no member). Over markers an
||| undecided head is a value an instance puts in, so the walk takes the
||| value both ways.
holdingOf : ClosedTerm -> Front Holding
holdingOf normal = (\r => choiceHolding r.frozen r.interfaces normal) <$> reading

||| What a value of a type the instance decides is (`holdingOf`), the type
||| the site's arguments give, delayed or not, normalised.
holdingAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> ClosedTerm -> Front Holding
holdingAt ty = holdingOf !(normaliseClosed (undelayed ty))

||| The arguments a use gives a member of type `ty`: one at each binder the
||| type shows, each the position of the application the use gives it
||| (`Parameters`), a marker past the writer's own parameters, position 2
||| the first, past the type and the form.
useArguments : {auto c : Ref Ctxt Defs} -> {vs : Scope} -> At -> ClosedTerm -> Front (List (Arg vs))
useArguments at ty = do
  normal <- normaliseClosed ty
  arguments (shown normal) 2 normal
  where
    -- The binders a normal form shows.
    shown : TT ws -> Nat
    shown (Bind _ _ (Pi {}) sc) = S (shown sc)
    shown _ = Z

    arguments : Nat -> (position : Nat) -> ClosedTerm -> Front (List (Arg vs))
    arguments Z _ _ = pure []
    arguments (S n) j t = do
      Bind _ _ (Pi {}) sc <- showingBinder t
        | _ => pure []
      let x = markerAt (at.arity + j) 0
      (closedArg x ::) <$> arguments n (S j) (subst x sc)

||| The member an argument at a binder of type `ty` that takes one makes: a
||| lambda there, or one delayed, is that member; anything else makes its
||| member as code, where a definition applied gives its own
||| (`definitionMember`). A member of a polymorphic function's choice is
||| applied at each use of the choice, so its use's walk is made here,
||| once (`Arg.asUse`).
memberMade : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
             At -> Pats -> Env vs -> FC -> (ty : ClosedTerm) -> Arg vs -> Front (List Site)
memberMade at ps env fc ty a = do
  made <- case a.written of
    lam@(Bind lfc _ (Lam {}) _) => lambdaAt at ps env lfc lam
    TDelay _ _ _ lam@(Bind lfc _ (Lam {}) _) => lambdaAt at ps env lfc lam
    _ => pure []
  used <- case !(choiceAt ty) of
    ArrowHead => a.asUse (undelayed ty)
    _ => pure []
  pure (made ++ used)

||| An argument at a binder of type `ty` that takes a member: the member it
||| makes (`memberMade`), and its walk as code.
atMember : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> (ty : ClosedTerm) -> Arg vs -> Front (List Site)
atMember at ps env fc ty a = (++) <$> memberMade at ps env fc ty a <*> Force a.asCode

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
||| of its type's choice (`Translate.Terms.applyRef`'s `memberHere`),
||| written at its choice's position (`memberAt`), the unshown head's
||| where the type shows none. Essential: a value no compile-time
||| reduction fixes is a choice, no member.
definitionMember : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                   At -> Pats -> Env vs -> FC -> Defined -> (after : Front ClosedTerm) -> List (Arg vs) ->
                   Front (List Site)
definitionMember at ps env fc d after args = case givesAfter (length args) (memberPlaces d) of
    NoMember => pure []
    AMember => made !after
    ByInstance => do
      ty <- after
      case !(holdingOf ty) of
        NoMember => pure []
        _ => made ty
  where
    made : ClosedTerm -> Front (List Site)
    made ty = do
      k <- choiceHeadOf ty
      let written = foldl (App fc) (Ref fc Func (fullname d.def)) (map (.written) args)
      form <- solved (holed env written)
      FixedNow <- fixing ty form
        | ChosenAtRunTime _ => pure []
      memberAt at ps env fc k form !(heldIn form) written

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

||| Arguments as a callee's type takes them: a static one is walked as a
||| static value, a runtime one as code, and an erased one not at all, since
||| the translation passes it nowhere.
walked : List (Given vs) -> Front (List Site)
walked [] = pure []
walked (g :: gs) = (++) <$> one g.taking <*> walked gs
  where
    one : Taking -> Front (List Site)
    one (AsStatic _) = Force g.offer.arg.asStatic
    one AsCode = Force g.offer.arg.asCode
    one Nowhere = pure []

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
walkedAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> Taker -> (given : Nat -> Holding) -> List (Given vs) -> Front (List Site)
walkedAt at ps env fc taker given [] = pure []
walkedAt at ps env fc taker given (g :: gs) =
  (++) <$> one taker g.taking (given g.position) <*> walkedAt at ps env fc taker given gs
  where
    decided : Holding -> Front (List Site)
    decided AMember = atMember at ps env fc g.binder g.offer.arg
    decided NoMember = walked [g]
    decided ByInstance = (++) <$> memberMade at ps env fc g.binder g.offer.arg <*> walked [g]

    one : Taker -> Taking -> Holding -> Front (List Site)
    one AFunction (AsStatic _) _ = do
      used <- case !(choiceAt g.binder) of
        ArrowHead => g.offer.arg.asUse (undelayed g.binder)
        _ => pure []
      (used ++) <$> walked [g]
    one _ _ AMember = atMember at ps env fc g.binder g.offer.arg
    one _ _ NoMember = walked [g]
    one _ _ ByInstance = decided !(holdingAt g.binder)

||| The member at a use's types of a compile-time form of type `t`
||| (`Translate.State.AtUse`), which applies the form as by `\f, x1 .. xn
||| => f x1 .. xn` at `t` (`Instances.applicationType`): the type at the
||| application's position 0, the form at 1, as `form` reads it, and each
||| of the use's static arguments at its own from 2 on, as the type takes
||| them. With the walk of the use's arguments as the type takes them: a
||| static one by its kind, and any other as code, or nowhere at an erased
||| binder.
useAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
        At -> Pats -> Env vs -> FC -> (t : ClosedTerm) -> (form : Argument) -> List (Arg vs) -> Front (List Site)
useAt at ps env fc t form args = do
  os <- traverse (offered ps env) args
  ty <- applicationType
  (kinds, _) <- staticsOver at.owner (2 + length args) ty (Just (t, AValue) :: Nothing :: map (\o => Just (o.value, o.offer)) os)
  let (k :: _ :: ks) = toList kinds
    | _ => pure []
  -- The form's type is the application's first argument, a type, whose
  -- binder is a universe.
  let typed = MkGiven (MkOffered (closedArg t) t AValue) 0 (maybe Nowhere AsStatic k) (TType EmptyFC (UN Underscore))
  gs <- along 2 t ks os
  ws <- traverse (\(g, k) => argument at ps env fc g k) (mapMaybe static (typed :: gs))
  now <- walkedAt at ps env fc AFunction (const ByInstance) gs
  pure (siteAt at fc Applies (form :: map fst ws) :: (ws >>= snd) ++ now)
  where
    static : Given vs -> Maybe (Given vs, Static)
    static g = case g.taking of
      AsStatic k => Just (g, k)
      AsCode => Nothing
      Nowhere => Nothing

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
                  At -> Pats -> Env vs -> FC -> (t : ClosedTerm) -> List (Arg vs) -> Front (List Site)
heldApplication at ps env fc t args =
  useAt at ps env fc t (MkArgument 1 ADictionary (Member ArrowHead) Chosen Nothing [] (Just ArrowHead)
                                    (TemplateText at.writerDef (Member ArrowHead)))
        args

||| Arguments applied to a value of a known type, or of none: one at an
||| erased binder is passed nowhere, and any other is code. A polymorphic
||| function held at run time, applied, is a use of it
||| (`heldApplication`). Past the binders the type shows, an argument is a
||| runtime value.
overType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> Maybe ClosedTerm -> List (Arg vs) -> Front (List Site)
overType at ps env fc _ [] = pure []
overType at ps env fc known (a :: as) = do
  ty <- traverse showingBinder known
  case ty of
    Just t@(Bind _ _ (Pi _ rig _ b) sc) => do
      False <- polymorphicType t
        | True => heldApplication at ps env fc t (a :: as)
      -- No definition's member table speaks for a type a value has: the
      -- binder's type decides, as the instance does, and where only an
      -- instance can, the value is taken both ways.
      here <- case use rig of
                Erased => pure []
                Used _ => case !(holdingAt b) of
                  NoMember => Force a.asCode
                  _ => atMember at ps env fc b a
      (here ++) <$> overType at ps env fc (Just (subst (close env a.written) sc)) as
    _ => do
      here <- Force a.asCode
      (here ++) <$> overType at ps env fc Nothing as

||| The names a type gives its binders.
piNames : TT vs -> List Name
piNames (Bind _ x (Pi {}) sc) = x :: piNames sc
piNames _ = []

||| How many parameters a definition takes: its case tree's scope, or the
||| arity Idris records, or the binders its type shows.
arityOf : Defined -> Nat
arityOf d = case definition d.def of
  PMDef _ args _ => length args
  DCon _ arity _ => arity
  TCon arity _ _ _ _ _ _ => arity
  Builtin {arity} _ => arity
  ForeignDef arity _ => arity
  ExternDef arity => arity
  _ => length (piNames d.type)

||| A data constructor applied, what it takes at each binder `positions`:
||| `Calls` of it at its dictionary arguments, so that the flow sees what a
||| match on them reads, when it has any; and the sites of its result type
||| after its arguments. With the arguments given, for their walk, and that
||| type.
constructed : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
              At -> Pats -> Env vs -> FC -> Address -> Defined -> (positions : List ArgumentAt) -> List (Arg vs) ->
              Front (List Site, List (Given vs), ClosedTerm)
constructed at ps env fc a d positions args = do
  (gs, rest) <- taken at ps env d.type positions args
  calls <- case filter holdsDictionary gs of
    [] => pure []
    dictionaries => callSite at ps env fc (Calls a) dictionaries
  result <- builds at ps.made fc rest
  pure (calls ++ result, gs, rest)
  where
    holdsDictionary : Given vs -> Bool
    holdsDictionary g = case g.taking of
      AsStatic ADictionary => True
      _ => False

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
||| method's own static arguments, those past the projection's, numbered
||| from the method's first in the order its field's lambdas take them.
||| With the walk of those arguments over the rest of the projection's
||| type.
dispatch : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> Projected -> Given vs -> ClosedTerm -> List (Arg vs) -> Front (List Site)
dispatch at ps env fc p dict rest extras = do
  read <- rooted ps.made ADictionary !(solved (holed env dict.offer.arg.written))
  tm <- (\head => asGiven (Just head) read) <$> choiceAt dict.binder
  -- The method's own arguments are those its type shows binders for; any
  -- past them applies its result.
  positions <- argumentsIn rest
  let n = min (length extras) (length positions)
  (gs, after) <- taken at ps env rest positions (take n extras)
  site <- callSite at ps env fc (Dispatches tm (snd read) p.field) gs
  now <- walkedAt at ps env fc AFunction (const ByInstance) gs
  later <- overType at ps env fc (Just after) (drop n extras)
  pure (site ++ now ++ later)

||| The definitions a hook calls in place of the one written: the library
||| function of a natural's operation, with no arguments, or the function a
||| foreign definition stands for, at the same arguments, the first that
||| applies as the translation's `hooked` takes them. Each library function
||| is the one the boundary interned with the definition (`Registered`).
hookCalls : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
            At -> Pats -> Env vs -> FC -> Hooks LibraryFunction -> List (Arg vs) -> Front (List Site)
hookCalls at ps env fc hs args = case hs.natOperation of
  Just (Tested _ lib) => library lib
  Just (OnIntegers lib) => library lib
  Just _ => pure []
  Nothing => maybe (pure []) aliased hs.alias
  where
    library : LibraryFunction -> Front (List Site)
    library lib = do
      Just (a, _) <- definitionOf lib.name
        | Nothing => pure []
      pure [siteAt at fc (Calls a) []]

    aliased : LibraryFunction -> Front (List Site)
    aliased lib = do
      Just (a, d) <- definitionOf lib.name
        | Nothing => pure []
      (gs, _) <- taken at ps env d.type d.taken (take (arityOf d) args)
      callSite at ps env fc (Calls a) gs

||| A definition applied as code: the member of its value's choice where
||| the member table says it gives one after its arguments
||| (`definitionMember`), however many it is given; `Calls` of it at the
||| static arguments its type makes, and a method call's `Dispatches`
||| beside it; the definitions its hooks call instead; and the walk of its
||| arguments, a member where the table says its binder takes one.
call : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
       At -> Pats -> Env vs -> FC -> Address -> Defined -> List (Arg vs) -> Front (List Site)
call at ps env fc a d args = do
  let arity = arityOf d
  (gs, rest) <- taken at ps env d.type d.taken (take arity args)
  member <- definitionMember at ps env fc d (typeAfter rest (map (\x => close env x.written) (drop arity args))) args
  own <- callSite at ps env fc (Calls a) gs
  -- A `%foreign` the registry gives no hooks is refused where it is
  -- called (`Translate.Terms.applyRef`), so it calls nothing in place.
  instead <- case callHooks d.registered of
    Right hs => hookCalls at ps env fc hs args
    Left _ => pure []
  now <- walkedAt at ps env fc AFunction (\j => givenAt j (memberPlaces d)) gs
  later <- case methodRecord d gs of
    Just (p, dict) => dispatch at ps env fc p dict rest (drop arity args)
    Nothing => overType at ps env fc (Just rest) (drop arity args)
  pure (member ++ own ++ instead ++ now ++ later)

||| A definition applied as code.
applyRef : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> Name -> List (Arg vs) -> Front (List Site)
applyRef at ps env fc n args = do
  Just (a, d) <- definitionOf n
    -- A name the context defines as nothing: a marker of a settled term.
    | Nothing => overType at ps env fc Nothing args
  case definition d.def of
    -- A constructor's field that holds an implementation or a polymorphic
    -- function holds the member its site fixes (`Translate.Terms.constructor`),
    -- as the member table says of its binder.
    DCon _ arity _ => do
      (sites, gs, rest) <- constructed at ps env fc a d d.taken (take arity args)
      now <- walkedAt at ps env fc AConstructor (\j => givenAt j (memberPlaces d)) gs
      later <- overType at ps env fc (Just rest) (drop arity args)
      pure (sites ++ now ++ later)
    PMDef {} => call at ps env fc a d args
    Builtin {} => call at ps env fc a d args
    ForeignDef {} => call at ps env fc a d args
    ExternDef {} => call at ps env fc a d args
    -- A type where code is, or a hole: the translation refuses both.
    _ => pure []

||| A definition applied in a type or a static argument: a constructor as
||| anywhere, an implementation as `Calls` of its function; any other
||| definition there is unfolded by the template, and never requested. A
||| dictionary built with its interface's constructor holds its methods as
||| its own lambdas, which the translation runs in place of a dispatch on
||| it (`Terms.resolveMethod` takes the field and settles it), so they are
||| code wherever the dictionary is written; its other arguments are
||| static.
staticRef : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
            At -> Pats -> Env vs -> FC -> Name -> List (Arg vs) -> Front (List Site)
staticRef at ps env fc n args = do
  Just (a, d) <- definitionOf n
    | Nothing => statics args
  case definition d.def of
    DCon _ arity _ => do
      (sites, gs, _) <- constructed at ps env fc a d d.taken (take arity args)
      fields <- if !(implementationType d.type) then walked gs else statics (take arity args)
      (\later => sites ++ fields ++ later) <$> statics (drop arity args)
    _ => do
      own <- if not !(implementationType d.type) then pure [] else do
        (gs, _) <- taken at ps env d.type d.taken (take (arityOf d) args)
        callSite at ps env fc (Calls a) gs
      (own ++) <$> statics args

------------------------------------------------------------------------------
-- Terms
------------------------------------------------------------------------------

||| Where a term the walk reads comes from: written in the definition, which
||| may settle once into the phase it holds; or settled, a normal form that
||| nothing settles again.
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
         At -> Pats -> Env vs -> TT vs -> Front (List Site)
  term ph w acc at ps env (Local fc _ idx p) = applyVariable ph w acc at ps env fc idx p []
  term ph w acc at ps env (Ref fc _ n) = applyRef at ps env fc n []
  -- A closed run of a Nat-like successor is a literal, which calls and
  -- builds nothing: read whole, as a template reads it (`closedRun`), it is
  -- one step, where a walk through its constructors would close the rest
  -- of the run at each.
  term ph w acc at ps env tm@(App _ f a) = do
    Nothing <- closedRun tm
      | Just _ => pure []
    spine ph w acc at ps env f [argOf ph w acc at ps env a]
  -- A lambda: its binders and body as code. Where it is a member, the
  -- place it stands says so (`atMember`, `resultMember`).
  term ph w acc at ps env (Bind fc x (Lam _ rig _ ty) sc) = lambdaBinder ph w acc at ps env x rig ty sc
  -- An erased `let` binds a compile-time value, and its value is no code.
  -- One that binds an implementation or a polymorphic function
  -- (`compileTimeBinder`) binds the value as written, as the translation
  -- binds it, settled where it is applied; a polymorphic function so bound
  -- may be applied at a use (`implementationAt`), so its use's walk is
  -- made here, where it is a subterm (`useOf`).
  term ph w acc at ps env (Bind _ x (Let _ rig val ty) sc) = case use rig of
    Erased => term ph w acc at ps ((Erased, x, Nothing) :: env) sc
    Used _ => do
      let typed = close env ty
      vty <- normaliseClosed typed
      if !(compileTimeBinder rig vty)
        then do
          known <- solved (close env val)
          here <- static ph w acc at ps env val
          used <- case !(choiceHeadOf vty) of
            ArrowHead => useOf ph w acc at ps env vty val
            _ => pure []
          body <- term ph w acc at ps ((Holds (Known known), x, Just typed) :: env) sc
          pure (here ++ used ++ body)
        else do
          value <- term ph w acc at ps env val
          here <- readType ph w acc at ps env ty
          body <- term ph w acc at ps ((Runtime, x, Just typed) :: env) sc
          pure (value ++ here ++ body)
  term ph w acc at ps env (Meta fc n i margs) = entered ph w acc at ps env fc n i margs []
  term ph w acc at ps env (As _ _ _ pat) = term ph w acc at ps env pat
  term ph w acc at ps env (TDelay _ _ _ arg) = term ph w acc at ps env arg
  term ph w acc at ps env (TForce _ _ arg) = term ph w acc at ps env arg
  -- A type, a constant or an erased value is no call.
  term ph w acc at ps env (Bind _ _ _ _) = pure []
  term ph w acc at ps env (TDelayed _ _ _) = pure []
  term ph w acc at ps env (PrimVal _ _) = pure []
  term ph w acc at ps env (Erased _ _) = pure []
  term ph w acc at ps env (TType _ _) = pure []

  ||| A lambda's binder and its scope. A binder of quantity 0 binds nothing
  ||| at runtime, so its type is no type a value has.
  lambdaBinder : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                 (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                 At -> Pats -> Env vs -> (x : Name) -> RigCount -> TT vs -> TT (x :: vs) -> Front (List Site)
  lambdaBinder ph w acc at ps env x rig ty sc = case use rig of
    Erased => lambdaScope ph w acc at ps ((Erased, x, Nothing) :: env) sc
    Used _ => do
      here <- readType ph w acc at ps env ty
      (here ++) <$> lambdaScope ph w acc at ps ((Runtime, x, Just (close env ty)) :: env) sc

  ||| A lambda's scope. A lambda directly under another is one value with
  ||| it, a member only as the whole is one, so its binder is walked as the
  ||| outer one's; any other term is code.
  lambdaScope : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                At -> Pats -> Env vs -> TT vs -> Front (List Site)
  lambdaScope ph w acc at ps env (Bind _ x (Lam _ rig _ ty) sc) = lambdaBinder ph w acc at ps env x rig ty sc
  lambdaScope ph w acc at ps env tm = term ph w acc at ps env tm

  ||| A type or a static argument: an implementation applied in it is a
  ||| call, and so is a constructor holding dictionaries; its types are read
  ||| off its template, by whoever reads it as a type.
  static : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
           At -> Pats -> Env vs -> TT vs -> Front (List Site)
  static ph w acc at ps env (Ref fc _ n) = staticRef at ps env fc n []
  static ph w acc at ps env tm@(App _ f a) = do
    Nothing <- closedRun tm
      | Just _ => pure []
    staticSpine ph w acc at ps env f [argOf ph w acc at ps env a]
  static ph w acc at ps env (Bind _ x (Lam _ rig _ ty) sc) = do
    here <- static ph w acc at ps env ty
    (here ++) <$> static ph w acc at ps ((byQuantity (use rig), x, Just (close env ty)) :: env) sc
  static ph w acc at ps env (Bind _ x (Pi _ rig _ ty) sc) = do
    here <- static ph w acc at ps env ty
    (here ++) <$> static ph w acc at ps ((byQuantity (use rig), x, Just (close env ty)) :: env) sc
  static ph w acc at ps env (Bind _ x (Let _ rig val ty) sc) = do
    value <- static ph w acc at ps env val
    here <- static ph w acc at ps env ty
    body <- static ph w acc at ps ((byQuantity (use rig), x, Just (close env ty)) :: env) sc
    pure (value ++ here ++ body)
  static ph w acc at ps env (Meta fc n i margs) = staticEntered ph w acc at ps env fc n i margs []
  static ph w acc at ps env (As _ _ _ pat) = static ph w acc at ps env pat
  static ph w acc at ps env (TDelayed _ _ t) = static ph w acc at ps env t
  static ph w acc at ps env (TDelay _ _ t a) = (++) <$> static ph w acc at ps env t <*> static ph w acc at ps env a
  static ph w acc at ps env (TForce _ _ a) = static ph w acc at ps env a
  -- A variable, a pattern's binder, a constant or an erased value writes
  -- nothing.
  static ph w acc at ps env (Local _ _ _ _) = pure []
  static ph w acc at ps env (Bind _ _ _ _) = pure []
  static ph w acc at ps env (PrimVal _ _) = pure []
  static ph w acc at ps env (Erased _ _) = pure []
  static ph w acc at ps env (TType _ _) = pure []

  ||| A binder's or a `let`'s type: what it writes, and the types it builds.
  readType : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
             (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
             At -> Pats -> Env vs -> TT vs -> Front (List Site)
  readType ph w acc at ps env ty = do
    here <- static ph w acc at ps env ty
    (here ++) <$> builds at ps.made (getLoc ty) (close env ty)

  ||| An argument where it is a subterm of the application.
  argOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
          (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          At -> Pats -> Env vs -> TT vs -> Arg vs
  argOf ph w acc at ps env a =
    MkArg a (term ph w acc at ps env a) (static ph w acc at ps env a) (\ty => useOf ph w acc at ps env ty a)

  ||| A member of a polymorphic function's choice applied at a use of type
  ||| `ty` (`Translate.State.AtUse`), walked once, at the place that makes
  ||| it, in the phase of the walk that meets it: applied to an argument at
  ||| each binder its type shows, each the position of the application the
  ||| use gives it (`useArguments`), so that what its body requests at a
  ||| use's types reads those positions. A delayed member is the member it
  ||| delays, and one under `let`s is their body, each binder standing as
  ||| the walk of a term binds it.
  useOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
          (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          At -> Pats -> Env vs -> (ty : ClosedTerm) -> TT vs -> Front (List Site)
  useOf ph w acc at ps env ty (TDelay _ _ _ t) = useOf ph w acc at ps env ty t
  useOf ph w acc at ps env ty (Bind _ x (Let _ rig _ vty) sc) = case use rig of
    Erased => useOf ph w acc at ps ((Erased, x, Nothing) :: env) ty sc
    Used _ => useOf ph w acc at ps ((Runtime, x, Just (close env vty)) :: env) ty sc
  useOf ph w acc at ps env ty t = do
    args <- useArguments at ty
    spine ph w acc ({ params := UseFrom at.arity } at) ps env t args

  ||| An application's spine as code, its arguments collected where each is
  ||| a subterm, down to its head.
  spine : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
          (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
          At -> Pats -> Env vs -> TT vs -> List (Arg vs) -> Front (List Site)
  spine ph w acc at ps env (App _ f a) args = spine ph w acc at ps env f (argOf ph w acc at ps env a :: args)
  spine ph w acc at ps env (Ref fc _ n) args = applyRef at ps env fc n args
  spine ph w acc at ps env tm args = applyHead ph w acc at ps env tm args

  ||| An application's spine in a type or a static argument.
  staticSpine : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                At -> Pats -> Env vs -> TT vs -> List (Arg vs) -> Front (List Site)
  staticSpine ph w acc at ps env (App _ f a) args = staticSpine ph w acc at ps env f (argOf ph w acc at ps env a :: args)
  staticSpine ph w acc at ps env (Ref fc _ n) args = staticRef at ps env fc n args
  staticSpine ph w acc at ps env (Meta fc n i margs) args = staticEntered ph w acc at ps env fc n i margs args
  staticSpine ph w acc at ps env tm args = do
    here <- static ph w acc at ps env tm
    (here ++) <$> statics args

  ||| A head that is no definition, applied as code: a variable; a lambda,
  ||| whose variable stands for its argument, so that its body sees it; a
  ||| solved metavariable, as its solution; anything else, walked with its
  ||| arguments applied to a value of unknown type.
  applyHead : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
              (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
              At -> Pats -> Env vs -> TT vs -> List (Arg vs) -> Front (List Site)
  applyHead ph w acc at ps env (Local fc _ idx p) args = applyVariable ph w acc at ps env fc idx p args
  -- The argument stands as what it is: a compile-time value at an erased
  -- binder; the variable it is; at a binder of an implementation or a
  -- polymorphic function (`compileTimeBinder`), its form as written, a
  -- static value; anything else, a runtime value, which is code.
  -- A polymorphic function bound so may be applied at a use
  -- (`implementationAt`), so its use's walk is made here (`Arg.asUse`).
  applyHead ph w acc at ps env (Bind _ x (Lam _ rig _ ty) sc) (a :: rest) = do
    (entry, own) <- the (Front (Standing, List Site)) $
      case use rig of
        Erased => pure ((Fixed (close env a.written), x, Nothing), [])
        Used _ => case a.written of
          Local _ _ idx p => pure (let (s, _, t) = entryAt env idx p in ((s, x, t), []))
          _ => do
            bty <- normaliseClosed (close env ty)
            if !(compileTimeBinder rig bty)
              then do
                used <- case !(choiceHeadOf bty) of
                  ArrowHead => a.asUse bty
                  _ => pure []
                pure ((Holds (Known !(solved (close env a.written))), x, Just (close env ty)), !(Force a.asStatic) ++ used)
              else do
                value <- Force a.asCode
                here <- readType ph w acc at ps env ty
                pure ((Runtime, x, Just (close env ty)), value ++ here)
    (own ++) <$> spine ph w acc at ps (entry :: env) sc (map overBinder rest)
  applyHead ph w acc at ps env (Meta fc n i margs) args = entered ph w acc at ps env fc n i margs args
  applyHead ph w acc at ps env (As _ _ _ pat) args = spine ph w acc at ps env pat args
  applyHead ph w acc at ps env tm args = do
    here <- term ph w acc at ps env tm
    (here ++) <$> overType at ps env fc Nothing args

  ||| A variable applied as code: a runtime value's arguments over its type;
  ||| a dictionary, settled once with them.
  applyVariable : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                  (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                  At -> Pats -> Env vs -> FC -> (idx : Nat) -> (0 p : IsVar n idx vs) -> List (Arg vs) ->
                  Front (List Site)
  applyVariable ph w acc at ps env fc idx p args = case entryAt env idx p of
    (Runtime, _, ty) => overType at ps env fc ty args
    (Pattern _, _, ty) => overType at ps env fc ty args
    (Shape _, _, ty) => overType at ps env fc ty args
    (s@(Holds _), _, ty) => implementationAt ph at ps env fc ty (termOf s) args
    -- Idris's quantity check keeps a compile-time variable out of every
    -- position that exists at runtime.
    (Fixed _, _, _) => pure []
    (Erased, _, _) => pure []

  ||| A dictionary or a polymorphic function applied as code: written, it is
  ||| settled once, its lambdas applied to the arguments, and walked in the
  ||| phase it held. Applied in a settled term, which settles nothing again,
  ||| it is the member at this use's types (`Translate.Terms.implementationAt`):
  ||| a use of the form, fixed at the application's position 1
  ||| (`useAt`), whose walk at a use was made where it was bound. One
  ||| whose type the walk does not know is applied to arguments that are
  ||| code.
  implementationAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                     Phase -> At -> Pats -> Env vs -> FC -> Maybe ClosedTerm -> ClosedTerm -> List (Arg vs) ->
                     Front (List Site)
  implementationAt Settled at ps env fc Nothing t args = overType at ps env fc Nothing args
  implementationAt Settled at ps env fc (Just ty) t args = do
    form <- readArgument ps.made 1 ADictionary Nothing t (TermText t)
    useAt at ps env fc !(normaliseClosed ty) form args
  -- A polymorphic function settled where it is applied is also a use of
  -- it (`useAt`): what the program gave for it was walked at its uses
  -- where it was given (`walkedAt`), which reads these positions, so a
  -- parameter's own application, whose form only an instance holds, is
  -- bounded through them.
  implementationAt (Written next) at ps env fc (Just ty) t args = do
    nty <- normaliseClosed ty
    used <- case !(choiceHeadOf nty) of
      ArrowHead => do
        form <- readArgument ps.made 1 ADictionary Nothing t (TermText t)
        useAt at ps env fc nty form args
      _ => pure []
    settled <- lambdasApplied (foldl (App fc) t (map (\a => close env a.written) args))
    (used ++) <$> term next start (sizeAccessible start) at ps [] settled
  implementationAt (Written next) at ps env fc Nothing t args = do
    settled <- lambdasApplied (foldl (App fc) t (map (\a => close env a.written) args))
    term next start (sizeAccessible start) at ps [] settled

  ||| A metavariable applied as code, as the solution the type checker gave
  ||| it, entered once on the path: met again, its solution is being walked.
  entered : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
            (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
            At -> Pats -> Env vs -> FC -> Name -> Int -> List (TT vs) -> List (Arg vs) -> Front (List Site)
  entered ph w acc@(Access rec) at ps env fc n i margs args = do
    -- A negative index is no place, which Idris's bare `Int` allows.
    let Just placement = placementOf i
      | Nothing => pure []
    let Just (Element w' less) = enter placement w
      | Nothing => pure []
    Just tm <- solution fc n margs
      | Nothing => pure []
    spine ph w' (rec w' less) at ps env tm args

  ||| A metavariable applied in a type or a static argument, likewise.
  staticEntered : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                  (ph : Phase) -> (w : Walked) -> (0 acc : SizeAccessible w) ->
                  At -> Pats -> Env vs -> FC -> Name -> Int -> List (TT vs) -> List (Arg vs) -> Front (List Site)
  staticEntered ph w acc@(Access rec) at ps env fc n i margs args = do
    -- A negative index is no place, which Idris's bare `Int` allows.
    let Just placement = placementOf i
      | Nothing => pure []
    let Just (Element w' less) = enter placement w
      | Nothing => pure []
    Just tm <- solution fc n margs
      | Nothing => pure []
    staticSpine ph w' (rec w' less) at ps env tm args

||| A leaf at the writer's result: where its leaves give a member of a
||| type, a lambda there, under its `let`s, is that member
||| (`Translate.Terms.atType`); and a member of a polymorphic function's
||| choice, a lambda or a definition applied, is applied at each use of the
||| choice, so its use's walk is made here (`useOf`).
resultMember : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
               At -> Pats -> Env vs -> TT vs -> Front (List Site)
resultMember at ps env tm = case at.giving of
  ValueLeaves => pure []
  MemberLeaves ty => do
    used <- case !(choiceAt ty) of
      ArrowHead => useOf asWritten start (sizeAccessible start) at ps env ty tm
      _ => pure []
    (used ++) <$> under env tm
  where
    under : {ws : Scope} -> Env ws -> TT ws -> Front (List Site)
    under env' lam@(Bind fc _ (Lam {}) _) = lambdaAt at ps env' fc lam
    under env' (Bind _ x (Let _ rig _ ty) sc) = case use rig of
      Erased => under ((Erased, x, Nothing) :: env') sc
      Used _ => under ((Runtime, x, Just (close env' ty)) :: env') sc
    under _ _ = pure []

||| A closed type: what it writes, and the types it builds.
readClosed : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> At -> Pats -> ClosedTerm -> Front (List Site)
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
rebound p con ((s, x, ty) :: es) = (restand s, x, map (substName (standInName p.number) con) ty) :: rebound p con es
  where
    restand : Stand -> Stand
    restand (Pattern q) = if q.number == p.number then Shape con else Pattern q
    restand (Fixed t) = Fixed (substName (standInName p.number) con t)
    restand (Holds (Known t)) = Holds (Known (substName (standInName p.number) con t))
    restand (Shape t) = Shape (substName (standInName p.number) con t)
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
  pure (env, foldl (App EmptyFC) con (map (\(s, _, _) => termOf s) (standings env)), ps')
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
      facts <- tyConFacts tc
      pure (paramLayout cd.def facts.params facts.roles ty)

    -- A runtime field: of a shape not matched yet, a shape one match
    -- deeper; of anything else, a runtime value.
    field : Pats -> (Stand, Pats)
    field ps = case v of
      Pattern p => fresh p.param (S p.depth) ps
      _ => (Runtime, ps)

    -- The scrutinee's type need not show the parameter when it is no type
    -- constructor applied (a type-level function stuck on a marker): the
    -- argument is then not known.
    stand : Pats -> Maybe Nat -> Nat -> RigCount -> ClosedTerm -> Front (Stand, Pats)
    stand ps (Just p) b _ _ = pure (maybe Erased Fixed (getAt p r), ps)
    stand ps Nothing b rig a = case v of
      Holds (Own i d path) => pure (Holds (Own i d (path ++ [b])), ps)
      _ => case argumentAt cd.def b rig of
        RuntimeValue _ =>
          if !(compileTimeBinder rig !(normaliseClosed a)) then pure (Runtime, ps) else pure (field ps)
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

mutual
  ||| A case tree: each leaf's term as code, from a path of its own, with
  ||| what the matches above it made of the scope.
  tree : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
         At -> Pats -> Env vs -> CaseTree vs -> Front (List Site)
  tree at ps env (STerm _ tm) = (++) <$> resultMember at ps env tm <*> term asWritten start (sizeAccessible start) at ps env tm
  tree at ps env (Unmatched _) = pure []
  tree at ps env Impossible = pure []
  -- The scrutinee's type is its variable's: a case tree loaded from a TTC
  -- holds none of its own.
  tree at ps env (Case idx p _ alts) = do
    let v = entryAt env idx p
    r <- the (Front (List ClosedTerm)) $ case v of
      (_, _, Just ty) => typeArgs <$> normaliseClosed ty
      (_, _, Nothing) => pure []
    every <- coversAll alts
    alternatives at ps env v r every alts alts
    where
      -- The arguments of the type constructor a type is.
      typeArgs : ClosedTerm -> List ClosedTerm
      typeArgs ty = case getFnArgs ty of
        (Ref _ (TyCon _) _, as) => as
        _ => []

  alternatives : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                 At -> Pats -> Env vs -> Standing -> List ClosedTerm -> Bool -> List (CaseAlt vs) ->
                 List (CaseAlt vs) -> Front (List Site)
  alternatives at ps env v r every alts [] = pure []
  alternatives at ps env v r every alts (ConCase cn tag args rhs :: rest) = do
    here <- the (Front (List Site)) $ case !(definitionOf cn) of
      Just (_, cd) => do
        (bound, con, ps') <- conStands ps (fst v) r cd (Ref EmptyFC (DataCon tag (length args)) cn) args
        tree at ps' (append bound (matchedAs (fst v) con env)) rhs
      -- Idris's tree names only constructors the context holds.
      Nothing => pure []
    (here ++) <$> alternatives at ps env v r every alts rest
    where
      -- A shape not matched yet is the constructor from now on; a dictionary
      -- keeps its marker, so that its root stays the writer's head.
      matchedAs : Stand -> ClosedTerm -> Env vs -> Env vs
      matchedAs (Pattern p) con env = rebound p con env
      matchedAs _ _ env = env
  -- A default after a complete split stands for no value.
  alternatives at ps env v r every alts (DefaultCase rhs :: rest) = do
    here <- if every then pure [] else defaulted at ps env v r alts rhs
    (here ++) <$> alternatives at ps env v r every alts rest
  alternatives at ps env v r every alts (ConstCase _ rhs :: rest) =
    (++) <$> tree at ps env rhs <*> alternatives at ps env v r every alts rest
  -- A suspension has one form: its alternative binds the value's type,
  -- erased, and the value forced, which stands as the scrutinee does, at
  -- the type the suspension's is of.
  alternatives at ps env v r every alts (DelayCase ty arg rhs :: rest) =
    (++) <$> tree at ps ((Erased, ty, Nothing) :: (fst v, arg, forced (snd (snd v))) :: env) rhs
         <*> alternatives at ps env v r every alts rest
    where
      forced : Maybe ClosedTerm -> Maybe ClosedTerm
      forced (Just (TDelayed _ _ t)) = Just t
      forced _ = Nothing

  ||| A default alternative. On a shape not matched yet it stands for each
  ||| constructor the alternatives leave out, which it is walked once for, as
  ||| that constructor; on anything else it is walked once.
  defaulted : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
              At -> Pats -> Env vs -> Standing -> List ClosedTerm -> List (CaseAlt vs) -> CaseTree vs ->
              Front (List Site)
  defaulted at ps env (Pattern p, _, _) r alts rhs = do
    named <- traverse fullNames (mapMaybe conName alts)
    every <- traverse fullNames !(siblings alts)
    case filter (\cn => not (elem cn named)) every of
      -- Matched on no constructor (literals), the default is one clause.
      [] => tree at ps env rhs
      others => expand at ps env p r others rhs
  defaulted at ps env _ r alts rhs = tree at ps env rhs

  ||| A default walked once per constructor it stands for, with the shape
  ||| matched to it.
  expand : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> StandIn -> List ClosedTerm -> List Name -> CaseTree vs ->
           Front (List Site)
  expand at ps env p r [] rhs = pure []
  expand at ps env p r (cn :: cns) rhs = do
    here <- the (Front (List Site)) $ case !(definitionOf cn) of
      Just (_, cd) => case definition cd.def of
        DCon tag arity _ => do
          (_, con, ps') <- conStands ps (Pattern p) r cd (Ref EmptyFC (DataCon tag arity) cn) (piNames cd.type)
          tree at ps' (rebound p con env) rhs
        _ => pure []
      -- A type's constructors are constructors the context holds.
      Nothing => pure []
    (here ++) <$> expand at ps env p r cns rhs

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

||| The writer a definition is, at its address, within another, with what
||| its leaves give.
atDefinition : (writer, within : Address) -> Defined -> Giving -> At
atDefinition writer within d giving =
  MkAt writer (arityOf d) OwnOnly within (show (fullname d.def)) (location d.def) d.def giving

||| An argument as a message shows it.
export
showArgument : {auto c : Ref Ctxt Defs} -> ArgumentText -> Front String
showArgument (TemplateText def t) = render !(parameterNames def) t
showArgument (TermText t) = showTT t
showArgument (WrittenText def ps env t) = display !(parameterNames def) ps env t
showArgument (ParameterText def i) = (\names => parameterName names i) <$> parameterNames def

||| The writer of a type, by address: what a type writes has no leaves.
writerAt : (writer, within : Address) -> Front (Maybe At)
writerAt writer within = do
  Just d <- definitionRead writer
    | Nothing => pure Nothing
  pure (Just (atDefinition writer within d ValueLeaves))

||| What a parameter of the definition stands for, by its kind and its value
||| at the node: a type, a family or a form is that value, its marker
||| unless the node has a head for it; a dictionary the dictionary at its
||| marker; a shape a fresh stand-in at depth 0; and anything else erased
||| or a runtime value, by its quantity.
standFor : Maybe Static -> RigCount -> Nat -> ClosedTerm -> Pats -> (Stand, Pats)
standFor (Just AType) _ i v ps = (Fixed v, ps)
standFor (Just AFamily) _ i v ps = (Fixed v, ps)
standFor (Just AForm) _ i v ps = (Fixed v, ps)
standFor (Just ADictionary) _ i v ps = (Holds (Own i 0 []), ps)
standFor (Just AShape) _ i v ps = fresh i 0 ps
standFor Nothing rig _ v ps = (byQuantity (use rig), ps)

||| The definition's parameters, off its type, each standing as its kind
||| and its value at the node say, with the sites its runtime binders'
||| types and its result type write: the types the translation reads off a
||| callee's signature.
signature : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            At -> List (Maybe Static, ClosedTerm) -> (i : Nat) -> ClosedTerm -> Pats -> Front (List Site, Pats, List Standing)
signature at [] i ty ps = (, ps, []) <$> readClosed at ps ty
signature at ((k, v) :: ks) i ty ps = do
  Bind _ x (Pi _ rig _ a) sc <- showingBinder ty
    | ty' => (, ps, []) <$> readClosed at ps ty'
  parameter x rig a sc
  where
    runtime : Stand -> Bool
    runtime Runtime = True
    runtime (Pattern _) = True
    runtime _ = False

    parameter : Name -> RigCount -> ClosedTerm -> TT [x] -> Front (List Site, Pats, List Standing)
    parameter x rig a sc = do
      let (st, ps') = standFor k rig i v ps
      here <- if runtime st then readClosed at ps a else pure []
      (rest, ps'', params) <- signature at ks (S i) (subst (termOf st) sc) ps'
      pure (here ++ rest, ps'', (st, x, Just a) :: params)

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
||| the method's own.
projectionSite : {auto c : Ref Ctxt Defs} -> At -> Pats -> List (Maybe Static, Standing) -> Projected -> Front Site
projectionSite at ps params p = do
  (tm, root) <- rooted [] ADictionary (markerAt p.matched 0)
  args <- traverse own (mapMaybe static (zip [0 .. length p.params] p.params))
  pure (siteAt at at.loc (Dispatches tm root p.field) args)
  where
    static : (Nat, Maybe Nat) -> Maybe (Nat, Nat, Static, ClosedTerm)
    static (q, Just j) = case getAt j params of
      Just (Just k, (st, _, _)) => Just (q, j, k, termOf st)
      _ => Nothing
    static (_, Nothing) = Nothing

    own : (Nat, Nat, Static, ClosedTerm) -> Front Argument
    own (q, j, k, t) = readArgument ps.made q k Nothing t (ParameterText at.writerDef j)

||| What each parameter stands for at a node: a family the node has a head
||| for is that type constructor applied to parts of the family's value,
||| one level down, each a stand-in of its own, as many as the constructor
||| takes beyond the family's own arrows, which is what a match of the
||| family's value against the constructor would bind; any other parameter
||| is its marker. With the stand-ins made, after those of `ps`. A head is
||| the address of a type constructor (`rooted`), which the context holds:
||| an address it does not is the graph's broken invariant.
nodeValues : {auto c : Ref Ctxt Defs} -> (n : Nat) -> List (Nat, Address) -> (i : Nat) -> ClosedTerm -> Pats ->
             Front (List ClosedTerm, Pats)
nodeValues Z heads i ty ps = pure ([], ps)
nodeValues (S n) heads i ty ps = do
  Bind _ _ (Pi _ _ _ kind) sc <- showingBinder ty
    | _ => pure ([], ps)
  (v, ps') <- maybe (pure (markerAt i 0, ps)) (headed kind) (lookup i heads)
  (vs, ps'') <- nodeValues n heads (S i) (subst v sc) ps'
  pure (v :: vs, ps'')
  where
    arrows : TT vs -> Nat
    arrows (Bind _ _ (Pi {}) sc) = S (arrows sc)
    arrows _ = Z

    -- One stand-in for each part, a level down.
    parts : Nat -> Pats -> (List ClosedTerm, Pats)
    parts Z qs = ([], qs)
    parts (S m) qs = let (st, qs') = fresh i 1 qs
                         (rest, qs'') = parts m qs' in
                     (termOf st :: rest, qs'')

    headed : ClosedTerm -> Address -> Front (ClosedTerm, Pats)
    headed kind tc = do
      Just tcd <- definitionRead tc
        | Nothing => internal EmptyFC "a family's head the context does not hold"
      let TCon arity _ _ _ _ _ _ = definition tcd.def
        | _ => internal EmptyFC ("a family's head that is no type constructor: " ++ show (fullname tcd.def))
      k <- arrows <$> normaliseClosed kind
      let (ts, ps') = parts (minus arity k) ps
      pure (foldl (App EmptyFC) (Ref EmptyFC (TyCon arity) (fullname tcd.def)) ts, ps')

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
            (writer, within : Address) -> Defined -> (List ClosedTerm, Pats) -> Front (List (Maybe Static), List Site)
nodeSites writer within d (values, made) = do
  (kinds', result) <- staticsOver (show (fullname d.def)) (arityOf d) d.type (map (\v => Just (v, AValue)) values)
  let kinds = toList kinds'
  at <- atDefinition writer within d <$> givingOf (givesAfter (arityOf d) (memberPlaces d)) result
  (sig, ps, params) <- signature at (zip kinds values) 0 d.type made
  body <- the (Front (List Site)) $ case d.matched of
    Just m => do
      st <- getState
      if contains at.writer st.refused || answersFor d.registered then pure [] else
        case dictionaryProjection kinds m.tree of
          Just p => (\site => [site]) <$> projectionSite at ps (zip kinds params) p
          Nothing => tree at ps (envOf m.args params) m.tree
    Nothing => pure []
  pure (kinds, sig ++ body)
  where
    -- What the registry made of the definition's calls, read with it: a
    -- hook that answers for its every call leaves no body translated, and
    -- a `%foreign` with no hooks has none to translate.
    answersFor : Registered -> Bool
    answersFor r = case callHooks r of
      Right hs => answersForCalls hs
      Left _ => False

||| A definition as its node with no heads reads it, every parameter its
||| marker: the sites it writes there, and its families by parameter index,
||| the type parameters whose kind is a function into a universe. Both come
||| from the one decision of its parameters' kinds. A node of it with heads
||| is split by the type constructor at the head of each family's value
||| (`Heads`), and read at those heads (`sitesOf`).
public export
record Reading where
  constructor MkReading
  sites : List Site
  families : List Nat

||| A definition read at a node: each of its families the node has a head
||| for stands for that type constructor (`nodeValues`), and every other
||| parameter for its marker. Nothing at an address the context holds no
||| definition at.
atNode : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
         Address -> (heads : List (Nat, Address)) -> Front (List (Maybe Static), List Site)
atNode a heads = do
  Just d <- definitionRead a
    | Nothing => pure ([], [])
  nodeSites a a d !(nodeValues (arityOf d) heads 0 d.type (MkPats 0 []))

||| A definition as its node with no heads reads it, from the definition
||| the walk holds.
export
readingOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Address -> Defined -> Front Reading
readingOf a d = do
  (kinds, ss) <- nodeSites a a d !(nodeValues (arityOf d) [] 0 d.type (MkPats 0 []))
  pure (MkReading ss (mapMaybe family (zip [0 .. length kinds] kinds)))
  where
    family : (Nat, Maybe Static) -> Maybe Nat
    family (i, Just AFamily) = Just i
    family _ = Nothing

||| Every site a definition writes at a node with heads.
export
sitesOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Address -> (heads : List (Nat, Address)) -> Front (List Site)
sitesOf a heads = snd <$> atNode a heads

||| The sites a closed term over the writer's markers and the stand-ins
||| `stands`, numbered from 0, writes, as a type `within` holds: a data
||| constructor's field type, its markers the data type's parameters and
||| its stand-ins the parts of them its constructor's type binds.
export
sitesIn : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
          (writer, within : Address) -> (stands : List StandIn) -> ClosedTerm -> Front (List Site)
sitesIn writer within stands tm = do
  Just at <- writerAt writer within
    | Nothing => pure []
  readClosed at (MkPats (length stands) stands) tm
