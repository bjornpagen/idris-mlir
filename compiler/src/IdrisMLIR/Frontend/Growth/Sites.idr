-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| What each definition writes at the static positions of what it calls and
||| builds, read off its signature and its case tree, with every parameter a
||| marker: the growth check's sites. They are the definition's, never an
||| instance's, so that a coincidence between two instances' arguments is no
||| arc, and a site of a clause no instance reaches is still one.
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
||| is, with that dictionary's root, or the application of a compile-time
||| form at a use, which no definition is (`Translate.State.AtUse`), at the
||| form's type (0), the form (1) and the use's static arguments (2 on).
public export
data Reach = Calls Address | Builds Address | Dispatches Template Root Nat | Applies

||| What a message shows an argument by (below).
export
data ArgumentText : Type

||| One argument a site writes, whole: the target's parameter it is at (of
||| a dispatched method, its own, in the order its field's lambdas take
||| them), its kind, the template written there and its root, as its
||| kind's one reading gives them (`rooted`), the closed term it was read
||| off, over the writer's markers and the site's stand-ins (none for a
||| part of a type already read), those stand-ins, which a reading of the
||| term again reads it with, and what a message shows it by. Only a
||| refusal prints that, and most arguments are in none, so it is read
||| where a message is made (`showArgument`).
public export
record Argument where
  constructor MkArgument
  position : Nat
  kind : Static
  template : Template
  root : Root
  term : Maybe ClosedTerm
  stands : List StandIn
  shown : ArgumentText

||| One site: who wrote it (whose parameters the templates' `Var`s are), the
||| definition whose text holds it, what it reaches, the argument written at
||| each static position of the target, and where it is.
public export
record Site where
  constructor MkSite
  writer : Address
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
||| translation marks what an implementation closes over.
holed : {vs : Scope} -> Env vs -> TT vs -> ClosedTerm
holed env t =
  let valued = zipWith value [0 .. length (standings env)] (standings env)
      c = closeWritten EmptyFC (map (\(v, _) => the (VarInfo ()) (TypeValue v)) valued) t
      order = fst (occurring (SortedSet.fromList (mapMaybe snd valued)) c ([<], empty)) <>> []
  in replacing (zipWith (\r, n => (n, holeMarker r)) [0 .. length order] order) c
  where
    -- A runtime value or a shape as a name of its own, by its place in
    -- the scope, which is renumbered once the term is closed.
    runtimeAt : Nat -> (ClosedTerm, Maybe Name)
    runtimeAt p = (probeTerm (ProbeRuntimeAt p), Just (probeName (ProbeRuntimeAt p)))

    value : Nat -> Standing -> (ClosedTerm, Maybe Name)
    value p (Runtime, _, _) = runtimeAt p
    value p (Pattern _, _, _) = runtimeAt p
    value p (Shape _, _, _) = runtimeAt p
    value p (s, _, _) = (termOf s, Nothing)

||| What the walk knows of the writer: its address, the definition whose
||| text holds what it reads (for a field type, the field's constructor),
||| its name for the normalisers' messages, its location, which a site with
||| no location of its own takes, and its definition, whose type names its
||| parameters, by which a message shows their markers.
record At where
  constructor MkAt
  writer : Address
  within : Address
  owner : String
  loc : FC
  writerDef : GlobalDef

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
siteAt at fc reach args = MkSite at.writer at.within reach args (if isEmptyFC fc then at.loc else fc)

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
  render names (Held a p) = (\s => s ++ "." ++ show p) <$> nameText a

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

||| The type constructor an address holds, if it holds one.
typeConstructorAt : {auto c : Ref Ctxt Defs} -> Address -> Front (Maybe GlobalDef)
typeConstructorAt a = do
  Just def <- core (definitionAt a)
    | Nothing => pure Nothing
  pure (case definition def of
          TCon {} => Just def
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
    Just def <- typeConstructorAt a
      | Nothing => Head (Just a) <$> eraseAll cs
    Head (Just a) <$> erasedAt (!(tyConFacts def)).roles 0 cs
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
  eraseIn t@(Held _ _) = pure t

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
  Just def <- typeConstructorAt a
    | Nothing => pure []
  let args = map argument (mapMaybe (\j => (j,) <$> getAt j cs) !(represented def))
  pure [siteAt at fc (Builds a) args]
  where
    -- A part of a type already read, with no term of its own to root.
    argument : (Nat, Template) -> Argument
    argument (j, t) = MkArgument j AType t Unrooted Nothing [] (TemplateText at.writerDef t)

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
  buildsIn at fc (Held _ _) = pure []

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
||| and its walks as code and as a static value, each suspended there.
record Arg (vs : Scope) where
  constructor MkArg
  written : TT vs
  asCode : Lazy (Front (List Site))
  asStatic : Lazy (Front (List Site))

||| An argument under a binder the walk binds.
overBinder : Arg vs -> Arg (x :: vs)
overBinder a = MkArg (weaken a.written) a.asCode a.asStatic

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
||| at its position among the callee's parameters, and how it is taken.
record Given (vs : Scope) where
  constructor MkGiven
  offer : Offered vs
  position : Nat
  taking : Taking

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
  pure (decided 0 os (toList kinds) positions, rest)
  where
    taking : Maybe Static -> ArgumentAt -> Taking
    taking (Just k) _ = AsStatic k
    taking Nothing (RuntimeValue _) = AsCode
    taking Nothing _ = Nowhere

    decided : Nat -> List (Offered vs) -> List (Maybe Static) -> List ArgumentAt -> List (Given vs)
    decided j (o :: os) (k :: ks) (p :: rs) = MkGiven o j (taking k p) :: decided (S j) os ks rs
    decided _ _ _ _ = []

||| A definition by name: its address and what the context holds of it.
definitionOf : {auto c : Ref Ctxt Defs} -> Name -> Front (Maybe (Address, GlobalDef))
definitionOf n = map (\(placement, def) => (addressOf placement, def)) <$> core (resolve n)

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
    Just (_, def) <- definitionOf n
      | Nothing => pure []
    case definition def of
      -- A definition of one right-hand side; of one that matches, nothing
      -- is decoded.
      PMDef _ pargs body => case !(leafOfBody {args = pargs} body) of
        Just _ => heldOver def 0 !(typeOfDefinition def) args
        Nothing => pure []
      DCon {} => heldOver def 0 !(typeOfDefinition def) args
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
||| with how a message shows it.
export
readArgument : {auto c : Ref Ctxt Defs} -> List StandIn -> Nat -> Static -> ClosedTerm -> ArgumentText -> Front Argument
readArgument stands j k t shown = (\(tm, root) => MkArgument j k tm root (Just t) stands shown) <$> rooted stands k t

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
  halves <- sequence [readArgument stands 0 AType t (TermText t), readArgument stands 1 AType rest (TermText rest)]
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

||| One static argument, closed as its key holds it at its kind, and read
||| (`rooted`): a type, family, form or shape as written over the markers
||| and the site's stand-ins (a type's template reads it in full normal
||| form); a dictionary with what it closes over as hole markers, so that
||| its template and its root read one closed term. With the sites of the
||| types a type or a family builds, and of the packing of the values a
||| dictionary closes over.
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
  x <- readArgument ps.made g.position k v (WrittenText at.writerDef ps env g.offer.arg.written)
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

||| A polymorphic function held at run time, of type `t`, applied where it
||| is held: a use of it, the member at the use's types
||| (`Translate.State.AtUse`), which applies the form as by `\f, x1 .. xn
||| => f x1 .. xn` at `t` (`Instances.applicationType`). The type keys it
||| at the application's position 0 and each of the use's static arguments
||| at its own from 2 on, as the type takes them; the form at 1 is the
||| running program's choice, which keys its dispatching instance at
||| nothing. With the walk of the use's arguments as the type takes them: a
||| static one by its kind, and any other as code, or nowhere at an erased
||| binder.
heldApplication : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                  At -> Pats -> Env vs -> FC -> (t : ClosedTerm) -> List (Arg vs) -> Front (List Site)
heldApplication at ps env fc t args = do
  os <- traverse (offered ps env) args
  ty <- applicationType
  (kinds, _) <- staticsOver at.owner (2 + length args) ty (Just (t, AValue) :: Nothing :: map (\o => Just (o.value, o.offer)) os)
  let (k :: _ :: ks) = toList kinds
    | _ => pure []
  let typed = MkGiven (MkOffered (MkArg (embedClosed t) (pure []) (pure [])) t AValue) 0 (maybe Nowhere AsStatic k)
  gs <- along 2 t ks os
  site <- callSite at ps env fc Applies (typed :: gs)
  now <- walked gs
  pure (site ++ now)
  where
    along : Nat -> ClosedTerm -> List (Maybe Static) -> List (Offered vs) -> Front (List (Given vs))
    along j ty (k :: ks) (o :: os) = do
      Bind _ _ (Pi _ rig _ _) sc <- showingBinder ty
        | _ => pure []
      let taking = case (k, use rig) of
                     (Just st, _) => AsStatic st
                     (Nothing, Erased) => Nowhere
                     (Nothing, Used _) => AsCode
      (MkGiven o j taking ::) <$> along (S j) (subst o.value sc) ks os
    along _ _ _ _ = pure []

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
    Just t@(Bind _ _ (Pi _ rig _ _) sc) => do
      False <- polymorphicType t
        | True => heldApplication at ps env fc t (a :: as)
      here <- case use rig of
                Erased => pure []
                Used _ => Force a.asCode
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
arityOf : {auto c : Ref Ctxt Defs} -> GlobalDef -> Front Nat
arityOf def = case definition def of
  PMDef _ args _ => pure (length args)
  DCon _ arity _ => pure arity
  TCon arity _ _ _ _ _ _ => pure arity
  Builtin {arity} _ => pure arity
  ForeignDef arity _ => pure arity
  ExternDef arity => pure arity
  _ => length . piNames <$> typeOfDefinition def

||| A data constructor applied: `Calls` of it at its dictionary arguments,
||| so that the flow sees what a match on them reads, when it has any; and
||| the sites of its result type after its arguments. With the arguments
||| given, for their walk, and that type.
constructed : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
              At -> Pats -> Env vs -> FC -> Address -> GlobalDef -> List (Arg vs) ->
              Front (List Site, List (Given vs), ClosedTerm)
constructed at ps env fc a def args = do
  (gs, rest) <- taken at ps env !(typeOfDefinition def) !(argumentsOf def) args
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

||| Read off the tree's root as the context holds it, so that of a stored
||| definition only the one leaf of a projection is decoded, and of any
||| other nothing.
projectionShape : {args : Scope} -> Body args -> Front (Maybe Projected)
projectionShape body = core (walkTree body shape)
  where
    -- Below the alternative's own variables, a variable is a parameter.
    parameter : Nat -> TT ws -> Maybe Nat
    parameter n (Local _ _ m _) = if m >= n then Just (minus m n) else Nothing
    parameter _ _ = Nothing

    shape : {0 t : Scoped} -> Leaves t -> CaseTree' t args -> Core (Maybe Projected)
    shape leaves (Case idx _ _ [ConCase _ _ cargs (STerm _ r)]) = do
      rhs <- leaves.leafTerm {outer = []} r
      pure $ case getFnArgs rhs of
        (Local _ _ k _, fargs) =>
          if k < length cargs then Just (MkProjected idx k (map (parameter (length cargs)) fargs)) else Nothing
        _ => Nothing
    shape _ _ = pure Nothing

||| The record a call of a projection-shaped definition matches, when the
||| call gives every parameter and the record is a dictionary: a method call.
methodRecord : GlobalDef -> List (Given vs) -> Front (Maybe (Projected, Given vs))
methodRecord def gs = case definition def of
  PMDef _ params body => do
    Just p <- projectionShape body
      | Nothing => pure Nothing
    pure $ do
      Yes _ <- pure (isLTE (length params) (length gs))
        | No _ => Nothing
      g <- getAt p.matched gs
      AsStatic ADictionary <- pure g.taking
        | _ => Nothing
      pure (p, g)
  _ => pure Nothing

||| The method a call dispatches on its dictionary: the record's template
||| and root, at the method's own static arguments, those past the
||| projection's, numbered from the method's first in the order its field's
||| lambdas take them. With the walk of those arguments over the rest of the
||| projection's type.
dispatch : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> Projected -> Given vs -> ClosedTerm -> List (Arg vs) -> Front (List Site)
dispatch at ps env fc p dict rest extras = do
  (tm, root) <- rooted ps.made ADictionary !(solved (holed env dict.offer.arg.written))
  -- The method's own arguments are those its type shows binders for; any
  -- past them applies its result.
  positions <- argumentsIn rest
  let n = min (length extras) (length positions)
  (gs, after) <- taken at ps env rest positions (take n extras)
  site <- callSite at ps env fc (Dispatches tm root p.field) gs
  now <- walked gs
  later <- overType at ps env fc (Just after) (drop n extras)
  pure (site ++ now ++ later)

||| The definitions a hook calls in place of the one written: the library
||| function of a natural's operation, with no arguments, or the function a
||| foreign definition stands for, at the same arguments, the first that
||| applies as the translation's `hooked` takes them.
hookCalls : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
            At -> Pats -> Env vs -> FC -> Hooks -> List (Arg vs) -> Front (List Site)
hookCalls at ps env fc hs args = case hs.natOperation of
  Just (Tested _ q) => library q
  Just (OnIntegers q) => library q
  Just _ => pure []
  Nothing => maybe (pure []) aliased hs.alias
  where
    library : QName -> Front (List Site)
    library q = do
      Just (a, _) <- definitionOf !(core (toName q))
        | Nothing => pure []
      pure [siteAt at fc (Calls a) []]

    aliased : QName -> Front (List Site)
    aliased q = do
      Just (a, def) <- definitionOf !(core (toName q))
        | Nothing => pure []
      (gs, _) <- taken at ps env !(typeOfDefinition def) !(argumentsOf def) (take !(arityOf def) args)
      callSite at ps env fc (Calls a) gs

||| The registry's hooks of a definition, as the translation finds them: a
||| foreign definition's by its specs, a primitive's none, any other's by
||| its name.
hooksFor : GlobalDef -> Hooks
hooksFor def = case definition def of
  -- The reach check refuses a `%foreign` the registry gives no hooks or
  -- the wrong ones; here such a declaration calls nothing instead.
  ForeignDef _ specs => case foreignHook (qname (fullname def)) specs of
    Just (Right hs) => hs
    _ => noHooks
  Builtin _ => noHooks
  _ => hooksOf (fullname def)

||| A definition applied as code: `Calls` of it at the static arguments its
||| type makes, and a method call's `Dispatches` beside it; the definitions
||| its hooks call instead; and the walk of its arguments.
call : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
       At -> Pats -> Env vs -> FC -> Address -> GlobalDef -> List (Arg vs) -> Front (List Site)
call at ps env fc a def args = do
  arity <- arityOf def
  (gs, rest) <- taken at ps env !(typeOfDefinition def) !(argumentsOf def) (take arity args)
  own <- callSite at ps env fc (Calls a) gs
  instead <- hookCalls at ps env fc (hooksFor def) args
  now <- walked gs
  later <- case !(methodRecord def gs) of
    Just (p, dict) => dispatch at ps env fc p dict rest (drop arity args)
    Nothing => overType at ps env fc (Just rest) (drop arity args)
  pure (own ++ instead ++ now ++ later)

||| A definition applied as code.
applyRef : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
           At -> Pats -> Env vs -> FC -> Name -> List (Arg vs) -> Front (List Site)
applyRef at ps env fc n args = do
  Just (a, def) <- definitionOf n
    -- A name the context does not hold: a marker of a settled term.
    | Nothing => overType at ps env fc Nothing args
  case definition def of
    DCon _ arity _ => do
      (sites, gs, rest) <- constructed at ps env fc a def (take arity args)
      now <- walked gs
      later <- overType at ps env fc (Just rest) (drop arity args)
      pure (sites ++ now ++ later)
    PMDef {} => call at ps env fc a def args
    Builtin {} => call at ps env fc a def args
    ForeignDef {} => call at ps env fc a def args
    ExternDef {} => call at ps env fc a def args
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
  Just (a, def) <- definitionOf n
    | Nothing => statics args
  case definition def of
    DCon _ arity _ => do
      (sites, gs, _) <- constructed at ps env fc a def (take arity args)
      fields <- if !(implementationType !(typeOfDefinition def)) then walked gs else statics (take arity args)
      (\later => sites ++ fields ++ later) <$> statics (drop arity args)
    _ => do
      ty <- typeOfDefinition def
      own <- if not !(implementationType ty) then pure [] else do
        (gs, _) <- taken at ps env ty !(argumentsOf def) (take !(arityOf def) args)
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
-- held. An argument's walks are made where it is a subterm (`argOf`).
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
  -- A lambda's binder of quantity 0 binds nothing at runtime, so its type
  -- is no type a value has.
  term ph w acc at ps env (Bind _ x (Lam _ rig _ ty) sc) = case use rig of
    Erased => term ph w acc at ps ((Erased, x, Nothing) :: env) sc
    Used _ => do
      here <- readType ph w acc at ps env ty
      (here ++) <$> term ph w acc at ps ((Runtime, x, Just (close env ty)) :: env) sc
  -- An erased `let` binds a compile-time value, and its value is no code.
  term ph w acc at ps env (Bind _ x (Let _ rig val ty) sc) = case use rig of
    Erased => term ph w acc at ps ((Erased, x, Nothing) :: env) sc
    Used _ => do
      value <- term ph w acc at ps env val
      here <- readType ph w acc at ps env ty
      body <- term ph w acc at ps ((Runtime, x, Just (close env ty)) :: env) sc
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
  argOf ph w acc at ps env a = MkArg a (term ph w acc at ps env a) (static ph w acc at ps env a)

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
  applyHead ph w acc at ps env (Bind _ x (Lam _ rig _ ty) sc) (a :: rest) = do
    (entry, own) <- the (Front (Standing, List Site)) $
      case use rig of
        Erased => pure ((Fixed (close env a.written), x, Nothing), [])
        Used _ => case a.written of
          Local _ _ idx p => pure (let (s, _, t) = entryAt env idx p in ((s, x, t), []))
          _ =>
            if !(compileTimeBinder rig !(normaliseClosed (close env ty)))
              then pure ((Holds (Known !(solved (close env a.written))), x, Nothing), !(Force a.asStatic))
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
    (s@(Holds _), _, _) => implementationAt ph at ps env fc (termOf s) args
    -- Idris's quantity check keeps a compile-time variable out of every
    -- position that exists at runtime.
    (Fixed _, _, _) => pure []
    (Erased, _, _) => pure []

  ||| A dictionary applied as code: written, it is settled once, its lambdas
  ||| applied to the arguments, and walked in the phase it held. A settled
  ||| term is closed with its lambdas applied, so no variable of it holds a
  ||| dictionary, and its arguments are code.
  implementationAt : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> {vs : Scope} ->
                     Phase -> At -> Pats -> Env vs -> FC -> ClosedTerm -> List (Arg vs) -> Front (List Site)
  implementationAt Settled at ps env fc t args = overType at ps env fc Nothing args
  implementationAt (Written next) at ps env fc t args = do
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
||| any other erased one nothing; a field of an implementation or a
||| polymorphic function (`compileTimeBinder`) what the constructor holds
||| there; a runtime field of a shape a shape one constructor deeper,
||| and any other a runtime value.
conStands : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} ->
            Pats -> Stand -> List ClosedTerm -> Address -> GlobalDef -> ClosedTerm -> (args : List Name) ->
            Front (Env args, ClosedTerm, Pats)
conStands ps v r ca cdef con args = do
  ty <- normaliseClosed !(typeOfDefinition cdef)
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
      defs <- getDefs
      let Just tn = built ty
        | Nothing => pure []
      Just tdef <- lookupExact tn (gamma defs)
        | Nothing => pure []
      facts <- tyConFacts tdef
      pure (paramLayout cdef facts.params facts.roles ty)

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
      _ => case argumentAt cdef b rig of
        RuntimeValue _ =>
          if !(compileTimeBinder rig !(normaliseClosed a)) then pure (Holds (Known (heldAt ca b)), ps) else
            pure (field ps)
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
  tree at ps env (STerm _ tm) = term asWritten start (sizeAccessible start) at ps env tm
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
      Just (ca, cdef) => do
        (bound, con, ps') <- conStands ps (fst v) r ca cdef (Ref EmptyFC (DataCon tag (length args)) cn) args
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
      Just (ca, cdef@(MkGlobalDef {definition = DCon tag arity _, _})) => do
        (_, con, ps') <- conStands ps (Pattern p) r ca cdef (Ref EmptyFC (DataCon tag arity) cn) (piNames !(typeOfDefinition cdef))
        tree at ps' (rebound p con env) rhs
      -- A type's constructors are constructors the context holds.
      _ => pure []
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

||| The writer a definition is, at its address, within another.
atDefinition : (writer, within : Address) -> GlobalDef -> At
atDefinition writer within def = MkAt writer within (show (fullname def)) (location def) def

||| An argument as a message shows it.
export
showArgument : {auto c : Ref Ctxt Defs} -> ArgumentText -> Front String
showArgument (TemplateText def t) = render !(parameterNames def) t
showArgument (TermText t) = showTT t
showArgument (WrittenText def ps env t) = display !(parameterNames def) ps env t
showArgument (ParameterText def i) = (\names => parameterName names i) <$> parameterNames def

||| The writer, by address, and the definition it is.
writerAt : {auto c : Ref Ctxt Defs} -> (writer, within : Address) -> Front (Maybe (At, GlobalDef))
writerAt writer within = do
  Just def <- core (definitionAt writer)
    | Nothing => pure Nothing
  pure (Just (atDefinition writer within def, def))

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

||| A projection of a dictionary parameter, by its body and its own
||| parameters' kinds.
dictionaryProjection : {args : Scope} -> List (Maybe Static) -> Body args -> Front (Maybe Projected)
dictionaryProjection kinds body = do
  Just p <- projectionShape body
    | Nothing => pure Nothing
  pure (case getAt p.matched kinds of
          Just (Just ADictionary) => Just p
          _ => Nothing)

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
    own (q, j, k, t) = readArgument ps.made q k t (ParameterText at.writerDef j)

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
      Just def <- core (definitionAt tc)
        | Nothing => internal EmptyFC "a family's head the context does not hold"
      let TCon arity _ _ _ _ _ _ = definition def
        | _ => internal EmptyFC ("a family's head that is no type constructor: " ++ show (fullname def))
      k <- arrows <$> normaliseClosed kind
      let (ts, ps') = parts (minus arity k) ps
      pure (foldl (App EmptyFC) (Ref EmptyFC (TyCon arity) (fullname def)) ts, ps')

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
            At -> GlobalDef -> (List ClosedTerm, Pats) -> Front (List (Maybe Static), List Site)
nodeSites at def (values, made) = do
  arity <- arityOf def
  ty <- typeOfDefinition def
  (kinds', _) <- staticsOver at.owner arity ty (map (\v => Just (v, AValue)) values)
  let kinds = toList kinds'
  (sig, ps, params) <- signature at (zip kinds values) 0 ty made
  body <- the (Front (List Site)) $ case definition def of
    PMDef _ args pbody => do
      st <- getState
      if contains at.writer st.refused || answersForCalls (hooksOf (fullname def)) then pure [] else
        case !(dictionaryProjection kinds pbody) of
          Just p => (\site => [site]) <$> projectionSite at ps (zip kinds params) p
          Nothing => tree at ps (envOf args params) !(treeOfBody pbody)
    _ => pure []
  pure (kinds, sig ++ body)

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
  Just (at, def) <- writerAt a a
    | Nothing => pure ([], [])
  nodeSites at def !(nodeValues !(arityOf def) heads 0 !(typeOfDefinition def) (MkPats 0 []))

||| A definition as its node with no heads reads it, from the definition
||| the walk holds.
export
readingOf : {auto c : Ref Ctxt Defs} -> {auto s : Ref TState TS} -> Address -> GlobalDef -> Front Reading
readingOf a def = do
  (kinds, ss) <- nodeSites (atDefinition a a def) def !(nodeValues !(arityOf def) [] 0 !(typeOfDefinition def) (MkPats 0 []))
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
  Just (at, _) <- writerAt writer within
    | Nothing => pure []
  readClosed at (MkPats (length stands) stands) tm
