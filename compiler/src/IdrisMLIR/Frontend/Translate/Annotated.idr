-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The growth model's walk of a definition, as a tree: a node per step the
||| walk takes into the definition's text (a term walked as code, as a
||| static value, at a use, a case tree), each holding the term or the case
||| tree it stands at, and each request the walk decided there a field of
||| the node whose role it is (the call a reference makes, the types a
||| binder's type builds, the member a lambda makes, the dispatch a method
||| call makes). An argument is held where it is taken, as its taker took
||| it: walked as code, as a static value, both, as the member its binder
||| takes, or, where only an instance decides, every way the model walked
||| it. So the text annotated with what the model decided is one value,
||| which a reader walks in place of the term.
|||
||| What a request is depends on how far the model has got: a site as the
||| walk made it, the entry its number made it, and so on. The tree is
||| generic in it (`req`, indexed by the request's role), and a traversal
||| visits every request in the order the walk made them (`traverseReading`),
||| which numbering and every reader of the requests in order read.
module IdrisMLIR.Frontend.Translate.Annotated

import Core.Case.CaseTree
import Core.Name.Scoped
import Core.TT
import Libraries.Data.List.Thin

import Data.Vect

%default total

||| The role a request has at the node that holds it, the request's reach
||| as an index: a call (a definition it calls), a build (a type
||| constructor a type builds), a dispatch (a method of a dictionary), an
||| application at a use (of a compile-time form no definition applies), a
||| member a choice is made of, a dictionary rebuilt where its field is
||| taken apart, and the values a dictionary bound in the text keeps.
public export
data ReachKind = CallReach | BuildReach | DispatchReach | ApplyReach | MakeReach | RepackReach | KeepReach

------------------------------------------------------------------------------
-- What requests sit beside
------------------------------------------------------------------------------

||| The pair and its projections that holding two values or more as one
||| reaches, where the list is made.
public export
record PairSites (req : ReachKind -> Type) where
  constructor MkPairSites
  pair : req BuildReach
  first : req CallReach
  second : req CallReach

||| What a list of values held as one writes where it is made: the types
||| each runtime value's type builds, in the list's order, and, for two
||| values or more where the program declares a pair, the pair and its
||| projections.
public export
record HeldSites (req : ReachKind -> Type) where
  constructor MkHeldSites
  types : List (req BuildReach)
  pair : Maybe (PairSites req)

||| What a request's static argument writes beside the request, by its
||| kind: a type's or a family's, the types its value builds; a form's or
||| a shape's, nothing; a dictionary's, the lists of values it holds as
||| one, each with what it writes (none, for one given as a variable that
||| holds a dictionary bound in the text, whose place keeps its list).
public export
data Beside : (ReachKind -> Type) -> Type where
  BuildsBeside : List (req BuildReach) -> Beside req
  NothingBeside : Beside req
  HeldBeside : List (HeldSites req) -> Beside req

||| A request, with what each of its static arguments writes beside it.
public export
record Requested (req : ReachKind -> Type) (r : ReachKind) where
  constructor MkRequested
  request : req r
  beside : List (Beside req)

||| A member of a choice made where the walk is, with the lists of values
||| it holds as one, each with what it writes.
public export
record MemberAt (req : ReachKind -> Type) where
  constructor MkMemberAt
  makes : req MakeReach
  held : List (HeldSites req)

||| What a dictionary bound in the text keeps where it is bound: nothing,
||| where it closes over no value whose type the walk knows (or is the
||| writer's own); or the one list it holds as one, at its place, with
||| what that list writes.
public export
data KeptAt : (ReachKind -> Type) -> Type where
  KeepsNothing : KeptAt req
  KeepsList : req KeepReach -> HeldSites req -> KeptAt req

||| A field of the writer's dictionary parameter taken apart by a match:
||| the writer rebuilt with the field a value it holds, and the pair that
||| holds the field after the values the writer was given.
public export
record Repacked (req : ReachKind -> Type) where
  constructor MkRepacked
  repacks : req RepackReach
  pair : Maybe (PairSites req)

------------------------------------------------------------------------------
-- The walk's nodes
------------------------------------------------------------------------------

mutual
  ||| A term walked as code: the term, and the step the walk took there.
  public export
  record CodeNode (req : ReachKind -> Type) (vs : Scope) where
    constructor MkCodeNode
    term : Term vs
    step : CodeStep req vs

  ||| What the walk of a term as code did at it: nothing (a type, a
  ||| constant, an erased value, a closed run of a successor, which is a
  ||| literal); applied a head to its arguments (a variable, a reference,
  ||| an application's spine, a metavariable); walked a lambda; a `let`,
  ||| by what it binds (a type, whatever its quantity; an erased value; an
  ||| implementation or a polymorphic function, its value as a static one,
  ||| its use where its choice is applied at one, and what it keeps; a
  ||| runtime value, as code, with its type read); or went into an as
  ||| pattern, a suspension or a force.
  public export
  data CodeStep : (ReachKind -> Type) -> Scope -> Type where
    CodeInert : CodeStep req vs
    CodeApplied : HeadNode req vs -> CodeStep req vs
    CodeLambda : LambdaNode req vs -> CodeStep req vs
    CodeLetType : {x : Name} -> CodeNode req (x :: vs) -> CodeStep req vs
    CodeLetErased : {x : Name} -> CodeNode req (x :: vs) -> CodeStep req vs
    CodeLetForm : {x : Name} -> (value : StaticNode req vs) -> (use : Maybe (UseNode req vs)) -> KeptAt req ->
                  CodeNode req (x :: vs) -> CodeStep req vs
    CodeLetValue : {x : Name} -> (value : CodeNode req vs) -> TypeRead req vs -> CodeNode req (x :: vs) -> CodeStep req vs
    CodeAs : CodeNode req vs -> CodeStep req vs
    CodeDelay : CodeNode req vs -> CodeStep req vs
    CodeForce : CodeNode req vs -> CodeStep req vs

  ||| A lambda's binder, by its quantity: erased, which binds nothing at
  ||| run time; or used, its type read. Then its scope.
  public export
  data LambdaNode : (ReachKind -> Type) -> Scope -> Type where
    ErasedBinder : {x : Name} -> LambdaBodyNode req (x :: vs) -> LambdaNode req vs
    UsedBinder : {x : Name} -> TypeRead req vs -> LambdaBodyNode req (x :: vs) -> LambdaNode req vs

  ||| A lambda's scope: a lambda directly under it, one value with it, or
  ||| any other term, as code.
  public export
  data LambdaBodyNode : (ReachKind -> Type) -> Scope -> Type where
    InnerLambda : LambdaNode req vs -> LambdaBodyNode req vs
    LambdaCode : CodeNode req vs -> LambdaBodyNode req vs

  ||| A type read: its walk as a static value, and the types it builds.
  public export
  record TypeRead (req : ReachKind -> Type) (vs : Scope) where
    constructor MkTypeRead
    static : StaticNode req vs
    builds : List (req BuildReach)

  ||| A term walked as a static value or a type: the term, and the step.
  public export
  record StaticNode (req : ReachKind -> Type) (vs : Scope) where
    constructor MkStaticNode
    term : Term vs
    step : StaticStep req vs

  ||| What the walk of a static term did at it: nothing; applied a head (a
  ||| reference, a spine, a metavariable); went under a binder (a lambda or
  ||| a function type: its type, then its scope); a `let` (value, type,
  ||| scope); or into an as pattern, a lazy type, a suspension (its type,
  ||| then its value) or a force.
  public export
  data StaticStep : (ReachKind -> Type) -> Scope -> Type where
    StaticInert : StaticStep req vs
    StaticApplied : StaticHead req vs -> StaticStep req vs
    StaticBinder : {x : Name} -> StaticNode req vs -> StaticNode req (x :: vs) -> StaticStep req vs
    StaticLet : {x : Name} -> (value : StaticNode req vs) -> (type : StaticNode req vs) -> StaticNode req (x :: vs) ->
                StaticStep req vs
    StaticAs : StaticNode req vs -> StaticStep req vs
    StaticLazy : StaticNode req vs -> StaticStep req vs
    StaticDelay : (type : StaticNode req vs) -> (value : StaticNode req vs) -> StaticStep req vs
    StaticForce : StaticNode req vs -> StaticStep req vs

  ||| A member of a polymorphic function's choice applied at a use, walked
  ||| where it is made: the member's term, and the step.
  public export
  record UseNode (req : ReachKind -> Type) (vs : Scope) where
    constructor MkUseNode
    term : Term vs
    step : UseStep req vs

  ||| What the walk of a member at a use did: nothing (a closed value, which
  ||| holds no application of the program's); went into a suspension or
  ||| under a `let`; or applied the member to the use's arguments.
  public export
  data UseStep : (ReachKind -> Type) -> Scope -> Type where
    UseInert : UseStep req vs
    UseDelayed : UseNode req vs -> UseStep req vs
    UseUnderLet : {x : Name} -> UseNode req (x :: vs) -> UseStep req vs
    UseApplied : HeadNode req vs -> UseStep req vs

  ||| A head applied as code to the arguments of its spine: a reference, by
  ||| what it is; a variable, by what it stands for; a lambda, its argument
  ||| bound as its binder takes it and its body applied to the rest; a
  ||| metavariable, as its solution; an as pattern, as its pattern; any
  ||| other term, as code, applied to its arguments over no known type.
  public export
  data HeadNode : (ReachKind -> Type) -> Scope -> Type where
    HeadReference : RefNode req vs -> HeadNode req vs
    HeadVariable : VariableNode req vs -> HeadNode req vs
    HeadLambda : {x : Name} -> BoundArg req vs -> HeadNode req (x :: vs) -> HeadNode req vs
    HeadSolution : SolutionNode req vs -> HeadNode req vs
    HeadPattern : HeadNode req vs -> HeadNode req vs
    HeadOther : CodeNode req vs -> OverNode req vs -> HeadNode req vs

  ||| A metavariable applied: its solution's spine, entered once on the
  ||| path; or nothing, unsolved or met again on its own path.
  public export
  data SolutionNode : (ReachKind -> Type) -> Scope -> Type where
    Solved : HeadNode req vs -> SolutionNode req vs
    NotEntered : SolutionNode req vs

  ||| A variable applied as code: a runtime value, its arguments over its
  ||| type; a dictionary or a polymorphic function, settled; a compile-time
  ||| value, which no runtime position holds.
  public export
  data VariableNode : (ReachKind -> Type) -> Scope -> Type where
    RuntimeVariable : OverNode req vs -> VariableNode req vs
    SettledVariable : SettlingNode req vs -> VariableNode req vs
    CompileTimeVariable : VariableNode req vs

  ||| A reference applied as code, by what the context defines it as: a
  ||| name it defines nothing at (a marker of a settled term), its
  ||| arguments over no known type; a data constructor; a function, a
  ||| builtin, a foreign or an extern definition, called; a type or a hole,
  ||| which the translation refuses.
  public export
  data RefNode : (ReachKind -> Type) -> Scope -> Type where
    MarkerReference : OverNode req vs -> RefNode req vs
    ConstructorReference : ConstructNode req vs -> RefNode req vs
    CalledReference : CallNode req vs -> RefNode req vs
    RefusedReference : RefNode req vs

  ||| What a constructor applied as code builds and holds: the sites its
  ||| application writes (its call where it holds or builds a dictionary,
  ||| its result type's builds).
  public export
  record ConstructedSites (req : ReachKind -> Type) where
    constructor MkConstructedSites
    calls : Maybe (Requested req CallReach)
    result : List (req BuildReach)

  ||| A data constructor applied as code: the member its value is where the
  ||| member table says it gives one, what its application writes, its
  ||| arguments up to its arity as it takes each, and those past it.
  public export
  record ConstructNode (req : ReachKind -> Type) (vs : Scope) where
    constructor MkConstructNode
    member : Maybe (MemberAt req)
    constructed : ConstructedSites req
    now : List (ArgNode req vs)
    later : OverNode req vs

  ||| A definition called: the member its value is where the member table
  ||| says it gives one, its call, the call a hook makes in its place, its
  ||| arguments up to its arity as it takes each, and those past it.
  public export
  record CallNode (req : ReachKind -> Type) (vs : Scope) where
    constructor MkCallNode
    member : Maybe (MemberAt req)
    own : Requested req CallReach
    instead : Maybe (Requested req CallReach)
    now : List (ArgNode req vs)
    later : PastArity req vs

  ||| The arguments a definition is given past its arity: a method call's,
  ||| which its dictionary's dispatch takes; any other's, over the type it
  ||| gives.
  public export
  data PastArity : (ReachKind -> Type) -> Scope -> Type where
    MethodCall : DispatchNode req vs -> PastArity req vs
    PastOver : OverNode req vs -> PastArity req vs

  ||| A method dispatched on its record: the dispatch, the method's own
  ||| arguments past the projection's as it takes each, and those past them.
  public export
  record DispatchNode (req : ReachKind -> Type) (vs : Scope) where
    constructor MkDispatchNode
    dispatches : Requested req DispatchReach
    now : List (ArgNode req vs)
    later : OverNode req vs

  ||| Arguments applied over a type: none left; one at a binder the type
  ||| shows, as it takes it, then the rest; or a polymorphic function held
  ||| at run time, applied: a use of it.
  public export
  data OverNode : (ReachKind -> Type) -> Scope -> Type where
    OverDone : OverNode req vs
    OverArgument : ArgNode req vs -> OverNode req vs -> OverNode req vs
    OverUse : UseAtNode req vs -> OverNode req vs

  ||| A use of a compile-time form no definition applies: the application,
  ||| with what each static argument it reads writes beside it; the
  ||| arguments the form's type takes, as it takes each; and those past the
  ||| binders it shows, each read at every kind an instance can read it at.
  public export
  record UseAtNode (req : ReachKind -> Type) (vs : Scope) where
    constructor MkUseAtNode
    applies : Requested req ApplyReach
    now : List (ArgNode req vs)
    past : List (PastArg req vs)

  ||| An argument past the binders a form's type shows: what each of its
  ||| readings writes beside the application, and the argument, walked both
  ||| as a static value and as code.
  public export
  record PastArg (req : ReachKind -> Type) (vs : Scope) where
    constructor MkPastArg
    beside : List (Beside req)
    argument : ArgNode req vs

  ||| A dictionary or a polymorphic function applied as code, by the phase
  ||| of the term it is in: in a settled term, applied over no known type,
  ||| or a use of its form; written, settled at its arguments, beside the use
  ||| of its form where its choice is applied at one.
  public export
  data SettlingNode : (ReachKind -> Type) -> Scope -> Type where
    SettledOver : OverNode req vs -> SettlingNode req vs
    SettledUse : UseAtNode req vs -> SettlingNode req vs
    Settling : (use : Maybe (UseAtNode req vs)) -> FormNode req vs -> SettlingNode req vs

  ||| A form settled at its arguments: walked as written; or, where it
  ||| closes over values, under the one variable that holds them.
  public export
  data FormNode : (ReachKind -> Type) -> Scope -> Type where
    FormWalked : HeadNode req vs -> FormNode req vs
    FormHolding : {x : Name} -> HeadNode req (x :: vs) -> FormNode req vs

  ||| The argument a lambda applied binds, as its binder takes it.
  public export
  record BoundArg (req : ReachKind -> Type) (us : Scope) where
    constructor MkBoundArg
    {origin : Scope}
    thinned : Thin origin us
    written : Term origin
    bound : BoundAs req origin us

  ||| How a lambda applied binds its argument: as a compile-time value (at
  ||| an erased binder, or of a type or a type family); as another name for
  ||| a variable; as a form (an implementation or a polymorphic function),
  ||| walked as a static value, at its use where its choice is applied at
  ||| one, with what it keeps; or as a runtime value, walked as code, the
  ||| binder's type read.
  public export
  data BoundAs : (ReachKind -> Type) -> Scope -> Scope -> Type where
    BoundCompileTime : BoundAs req vs us
    BoundAlias : BoundAs req vs us
    BoundForm : StaticNode req vs -> Maybe (UseNode req vs) -> KeptAt req -> BoundAs req vs us
    BoundValue : CodeNode req vs -> TypeRead req us -> BoundAs req vs us

  ||| An argument where it is taken: in the scope it is written in, its
  ||| place in the taker's, its term, and how its taker took it.
  public export
  record ArgNode (req : ReachKind -> Type) (us : Scope) where
    constructor MkArgNode
    {origin : Scope}
    thinned : Thin origin us
    written : Term origin
    taken : TakenAs req origin

  ||| How a taker took an argument: walked as its binder's kind says; a
  ||| function's static argument, also at its use where its choice is
  ||| applied at one; the member its binder takes, and code; where only an
  ||| instance decides, both the member and its walk; or a dictionary a
  ||| constructor holds in a static value, also as the computation a match
  ||| that finds it stuck computes.
  public export
  data TakenAs : (ReachKind -> Type) -> Scope -> Type where
    TakenWalked : ArgWalk req vs -> TakenAs req vs
    TakenUsed : Maybe (UseNode req vs) -> ArgWalk req vs -> TakenAs req vs
    TakenMember : MemberNode req vs -> CodeNode req vs -> TakenAs req vs
    TakenEither : MemberNode req vs -> ArgWalk req vs -> TakenAs req vs
    TakenComputed : ArgWalk req vs -> ComputedNode req vs -> TakenAs req vs

  ||| An argument walked as its binder's kind says: passed nowhere (erased);
  ||| as code (at run time); as a static value; or both (a value whose shape
  ||| keys the instance, which is passed at run time too, and an argument
  ||| past the binders a type shows).
  public export
  data ArgWalk : (ReachKind -> Type) -> Scope -> Type where
    WalkedNowhere : ArgWalk req vs
    WalkedCode : CodeNode req vs -> ArgWalk req vs
    WalkedStatic : StaticNode req vs -> ArgWalk req vs
    WalkedBoth : StaticNode req vs -> CodeNode req vs -> ArgWalk req vs

  ||| The member an argument makes where its binder takes one: the member
  ||| made where it stands (a lambda, the writer's own dictionary, or none
  ||| here), and its use's walk where its choice is applied at a use.
  public export
  record MemberNode (req : ReachKind -> Type) (vs : Scope) where
    constructor MkMemberNode
    made : Maybe (MemberAt req)
    used : Maybe (UseNode req vs)

  ||| A dictionary's field as a match that finds it stuck computes it: in a
  ||| settled term, as code; written, settled once as the term it is, with
  ||| what it keeps.
  public export
  data ComputedNode : (ReachKind -> Type) -> Scope -> Type where
    ComputedCode : CodeNode req vs -> ComputedNode req vs
    ComputedSettled : KeptAt req -> SettlingNode req vs -> ComputedNode req vs

  ||| A static term's head applied to its spine's arguments: a reference,
  ||| by what it is; a metavariable's solution, or nothing where it is not
  ||| entered; any other term, walked, with its arguments.
  public export
  data StaticHead : (ReachKind -> Type) -> Scope -> Type where
    StaticReference : StaticRefNode req vs -> StaticHead req vs
    StaticSolved : StaticHead req vs -> StaticHead req vs
    StaticNotEntered : StaticHead req vs
    StaticOther : StaticNode req vs -> List (ArgNode req vs) -> StaticHead req vs

  ||| A reference applied in a static value: a name the context defines
  ||| nothing at, its arguments as static values; a data constructor, what
  ||| it writes, its fields as it takes each (a dictionary's as its binders
  ||| take them, also computed where a match finds one stuck; data's as
  ||| static values), and its arguments past them; any other definition,
  ||| its call where it is an implementation, and its arguments.
  public export
  data StaticRefNode : (ReachKind -> Type) -> Scope -> Type where
    StaticMarker : List (ArgNode req vs) -> StaticRefNode req vs
    StaticConstructor : ConstructedSites req -> (fields : List (ArgNode req vs)) -> (later : List (ArgNode req vs)) ->
                        StaticRefNode req vs
    StaticDefinition : Maybe (Requested req CallReach) -> List (ArgNode req vs) -> StaticRefNode req vs

------------------------------------------------------------------------------
-- Case trees and readings
------------------------------------------------------------------------------

mutual
  ||| A case tree walked: the tree, and the step.
  public export
  record TreeNode (req : ReachKind -> Type) (vs : Scope) where
    constructor MkTreeNode
    tree : CaseTree vs
    step : TreeStep req vs

  ||| What the walk of a case tree did: a leaf, as the member the
  ||| definition's result is at a use, and as code; nothing at an unmatched
  ||| or an impossible one; a match, the dictionary it rebuilds where it
  ||| takes a field of the writer's apart, and each alternative.
  public export
  data TreeStep : (ReachKind -> Type) -> Scope -> Type where
    TreeLeaf : LeafMember req vs -> CodeNode req vs -> TreeStep req vs
    TreeUnmatched : TreeStep req vs
    TreeImpossible : TreeStep req vs
    TreeMatch : Maybe (Repacked req) -> List (AltNode req vs) -> TreeStep req vs

  ||| An alternative of a match: a constructor's, under what it binds (none
  ||| where the context holds no such constructor); a default, after a
  ||| complete split none, on a shape not matched yet once per constructor
  ||| it stands for, and otherwise once; a constant's; a suspension's,
  ||| under its type and its value.
  public export
  data AltNode : (ReachKind -> Type) -> Scope -> Type where
    ConstructorAlt : {args : List Name} -> TreeNode req (Scope.addInner vs args) -> AltNode req vs
    UnknownConstructorAlt : AltNode req vs
    DefaultNone : AltNode req vs
    DefaultOnce : TreeNode req vs -> AltNode req vs
    DefaultExpanded : List (ExpansionNode req vs) -> AltNode req vs
    ConstantAlt : TreeNode req vs -> AltNode req vs
    DelayAlt : {ty, arg : Name} -> TreeNode req (Scope.addInner vs [ty, arg]) -> AltNode req vs

  ||| A default walked as one constructor it stands for: the tree, with the
  ||| shape matched to it; nothing for a name that is no data constructor.
  public export
  data ExpansionNode : (ReachKind -> Type) -> Scope -> Type where
    Expanded : Name -> TreeNode req vs -> ExpansionNode req vs
    NotExpanded : Name -> ExpansionNode req vs

  ||| A leaf at the writer's result: a value; or a member of its result
  ||| type's choice, its use's walk where the choice is applied at a use,
  ||| and the member a lambda there makes.
  public export
  data LeafMember : (ReachKind -> Type) -> Scope -> Type where
    ValueLeaf : LeafMember req vs
    MemberLeaf : Maybe (UseNode req vs) -> Maybe (MemberAt req) -> LeafMember req vs

||| A definition's signature read: each parameter's binder type, read where
||| the parameter is a runtime value, and its result type.
public export
record SignatureNode (req : ReachKind -> Type) where
  constructor MkSignatureNode
  binders : List (Maybe (TypeRead req []))
  result : TypeRead req []

||| A definition's body as the walk read it: none (no case tree); not
||| translated (refused, or answered for by a hook); a projection of a
||| dictionary, its one dispatch; or its case tree, in its parameters'
||| scope.
public export
data BodyNode : (ReachKind -> Type) -> Type where
  NoBody : BodyNode req
  Untranslated : BodyNode req
  ProjectionBody : req DispatchReach -> BodyNode req
  CaseBody : {args : Scope} -> TreeNode req args -> BodyNode req

||| A definition read at a node: what a type constructor's fields write,
||| in its constructors' order (none for any other definition), its
||| signature and its body.
public export
record ReadingTree (req : ReachKind -> Type) where
  constructor MkReadingTree
  fields : List (r : ReachKind ** req r)
  signature : SignatureNode req
  body : BodyNode req

------------------------------------------------------------------------------
-- Visiting the requests
------------------------------------------------------------------------------

||| What a visit does at each request: something of the request's role.
public export
0 Visitor : (Type -> Type) -> (ReachKind -> Type) -> (ReachKind -> Type) -> Type
Visitor m req req' = {0 r : ReachKind} -> req r -> m (req' r)

visitPair : Applicative m => Visitor m req req' -> PairSites req -> m (PairSites req')
visitPair v (MkPairSites p a b) = [| MkPairSites (v p) (v a) (v b) |]

visitHeld : Applicative m => Visitor m req req' -> HeldSites req -> m (HeldSites req')
visitHeld v (MkHeldSites ts p) = [| MkHeldSites (traverse v ts) (traverse (visitPair v) p) |]

visitBeside : Applicative m => Visitor m req req' -> Beside req -> m (Beside req')
visitBeside v (BuildsBeside bs) = BuildsBeside <$> traverse v bs
visitBeside v NothingBeside = pure NothingBeside
visitBeside v (HeldBeside hs) = HeldBeside <$> traverse (visitHeld v) hs

visitRequested : Applicative m => Visitor m req req' -> Requested req r -> m (Requested req' r)
visitRequested v (MkRequested x bs) = [| MkRequested (v x) (traverse (visitBeside v) bs) |]

visitMemberAt : Applicative m => Visitor m req req' -> MemberAt req -> m (MemberAt req')
visitMemberAt v (MkMemberAt x hs) = [| MkMemberAt (v x) (traverse (visitHeld v) hs) |]

visitKept : Applicative m => Visitor m req req' -> KeptAt req -> m (KeptAt req')
visitKept v KeepsNothing = pure KeepsNothing
visitKept v (KeepsList x h) = [| KeepsList (v x) (visitHeld v h) |]

visitRepacked : Applicative m => Visitor m req req' -> Repacked req -> m (Repacked req')
visitRepacked v (MkRepacked x p) = [| MkRepacked (v x) (traverse (visitPair v) p) |]

visitConstructed : Applicative m => Visitor m req req' -> ConstructedSites req -> m (ConstructedSites req')
visitConstructed v (MkConstructedSites c r) = [| MkConstructedSites (traverse (visitRequested v) c) (traverse v r) |]

mutual
  -- Each visit goes through a node's fields in the order the walk made
  -- what they hold, so the requests are visited in the order they were
  -- made.
  visitCode : Applicative m => Visitor m req req' -> CodeNode req vs -> m (CodeNode req' vs)
  visitCode v (MkCodeNode t s) = MkCodeNode t <$> visitCodeStep v s

  visitCodeStep : Applicative m => Visitor m req req' -> CodeStep req vs -> m (CodeStep req' vs)
  visitCodeStep v CodeInert = pure CodeInert
  visitCodeStep v (CodeApplied h) = CodeApplied <$> visitHead v h
  visitCodeStep v (CodeLambda l) = CodeLambda <$> visitLambda v l
  visitCodeStep v (CodeLetType b) = CodeLetType <$> visitCode v b
  visitCodeStep v (CodeLetErased b) = CodeLetErased <$> visitCode v b
  visitCodeStep v (CodeLetForm s u k b) = [| CodeLetForm (visitStatic v s) (visitMaybeUse v u) (visitKept v k) (visitCode v b) |]
  visitCodeStep v (CodeLetValue c t b) = [| CodeLetValue (visitCode v c) (visitTypeRead v t) (visitCode v b) |]
  visitCodeStep v (CodeAs c) = CodeAs <$> visitCode v c
  visitCodeStep v (CodeDelay c) = CodeDelay <$> visitCode v c
  visitCodeStep v (CodeForce c) = CodeForce <$> visitCode v c

  visitLambda : Applicative m => Visitor m req req' -> LambdaNode req vs -> m (LambdaNode req' vs)
  visitLambda v (ErasedBinder b) = ErasedBinder <$> visitLambdaBody v b
  visitLambda v (UsedBinder t b) = [| UsedBinder (visitTypeRead v t) (visitLambdaBody v b) |]

  visitLambdaBody : Applicative m => Visitor m req req' -> LambdaBodyNode req vs -> m (LambdaBodyNode req' vs)
  visitLambdaBody v (InnerLambda l) = InnerLambda <$> visitLambda v l
  visitLambdaBody v (LambdaCode c) = LambdaCode <$> visitCode v c

  visitTypeRead : Applicative m => Visitor m req req' -> TypeRead req vs -> m (TypeRead req' vs)
  visitTypeRead v (MkTypeRead s bs) = [| MkTypeRead (visitStatic v s) (traverse v bs) |]

  visitStatic : Applicative m => Visitor m req req' -> StaticNode req vs -> m (StaticNode req' vs)
  visitStatic v (MkStaticNode t s) = MkStaticNode t <$> visitStaticStep v s

  visitStaticStep : Applicative m => Visitor m req req' -> StaticStep req vs -> m (StaticStep req' vs)
  visitStaticStep v StaticInert = pure StaticInert
  visitStaticStep v (StaticApplied h) = StaticApplied <$> visitStaticHead v h
  visitStaticStep v (StaticBinder t s) = [| StaticBinder (visitStatic v t) (visitStatic v s) |]
  visitStaticStep v (StaticLet x t s) = [| StaticLet (visitStatic v x) (visitStatic v t) (visitStatic v s) |]
  visitStaticStep v (StaticAs s) = StaticAs <$> visitStatic v s
  visitStaticStep v (StaticLazy s) = StaticLazy <$> visitStatic v s
  visitStaticStep v (StaticDelay t s) = [| StaticDelay (visitStatic v t) (visitStatic v s) |]
  visitStaticStep v (StaticForce s) = StaticForce <$> visitStatic v s

  visitUse : Applicative m => Visitor m req req' -> UseNode req vs -> m (UseNode req' vs)
  visitUse v (MkUseNode t s) = MkUseNode t <$> visitUseStep v s

  visitMaybeUse : Applicative m => Visitor m req req' -> Maybe (UseNode req vs) -> m (Maybe (UseNode req' vs))
  visitMaybeUse v Nothing = pure Nothing
  visitMaybeUse v (Just u) = Just <$> visitUse v u

  visitUseStep : Applicative m => Visitor m req req' -> UseStep req vs -> m (UseStep req' vs)
  visitUseStep v UseInert = pure UseInert
  visitUseStep v (UseDelayed u) = UseDelayed <$> visitUse v u
  visitUseStep v (UseUnderLet u) = UseUnderLet <$> visitUse v u
  visitUseStep v (UseApplied h) = UseApplied <$> visitHead v h

  visitHead : Applicative m => Visitor m req req' -> HeadNode req vs -> m (HeadNode req' vs)
  visitHead v (HeadReference r) = HeadReference <$> visitRef v r
  visitHead v (HeadVariable x) = HeadVariable <$> visitVariable v x
  visitHead v (HeadLambda a b) = [| HeadLambda (visitBound v a) (visitHead v b) |]
  visitHead v (HeadSolution s) = HeadSolution <$> visitSolution v s
  visitHead v (HeadPattern h) = HeadPattern <$> visitHead v h
  visitHead v (HeadOther c o) = [| HeadOther (visitCode v c) (visitOver v o) |]

  visitSolution : Applicative m => Visitor m req req' -> SolutionNode req vs -> m (SolutionNode req' vs)
  visitSolution v (Solved h) = Solved <$> visitHead v h
  visitSolution v NotEntered = pure NotEntered

  visitVariable : Applicative m => Visitor m req req' -> VariableNode req vs -> m (VariableNode req' vs)
  visitVariable v (RuntimeVariable o) = RuntimeVariable <$> visitOver v o
  visitVariable v (SettledVariable s) = SettledVariable <$> visitSettling v s
  visitVariable v CompileTimeVariable = pure CompileTimeVariable

  visitRef : Applicative m => Visitor m req req' -> RefNode req vs -> m (RefNode req' vs)
  visitRef v (MarkerReference o) = MarkerReference <$> visitOver v o
  visitRef v (ConstructorReference c) = ConstructorReference <$> visitConstruct v c
  visitRef v (CalledReference c) = CalledReference <$> visitCall v c
  visitRef v RefusedReference = pure RefusedReference

  visitConstruct : Applicative m => Visitor m req req' -> ConstructNode req vs -> m (ConstructNode req' vs)
  visitConstruct v (MkConstructNode mem c now later) =
    [| MkConstructNode (traverse (visitMemberAt v) mem) (visitConstructed v c) (visitArgs v now) (visitOver v later) |]

  visitCall : Applicative m => Visitor m req req' -> CallNode req vs -> m (CallNode req' vs)
  visitCall v (MkCallNode mem own instead now later) =
    [| MkCallNode (traverse (visitMemberAt v) mem) (visitRequested v own) (traverse (visitRequested v) instead)
                  (visitArgs v now) (visitPastArity v later) |]

  visitPastArity : Applicative m => Visitor m req req' -> PastArity req vs -> m (PastArity req' vs)
  visitPastArity v (MethodCall d) = MethodCall <$> visitDispatch v d
  visitPastArity v (PastOver o) = PastOver <$> visitOver v o

  visitDispatch : Applicative m => Visitor m req req' -> DispatchNode req vs -> m (DispatchNode req' vs)
  visitDispatch v (MkDispatchNode d now later) = [| MkDispatchNode (visitRequested v d) (visitArgs v now) (visitOver v later) |]

  visitOver : Applicative m => Visitor m req req' -> OverNode req vs -> m (OverNode req' vs)
  visitOver v OverDone = pure OverDone
  visitOver v (OverArgument a rest) = [| OverArgument (visitArg v a) (visitOver v rest) |]
  visitOver v (OverUse u) = OverUse <$> visitUseAt v u

  visitUseAt : Applicative m => Visitor m req req' -> UseAtNode req vs -> m (UseAtNode req' vs)
  visitUseAt v (MkUseAtNode a now past) = [| MkUseAtNode (visitRequested v a) (visitArgs v now) (visitPasts v past) |]

  visitPasts : Applicative m => Visitor m req req' -> List (PastArg req vs) -> m (List (PastArg req' vs))
  visitPasts v [] = pure []
  visitPasts v (MkPastArg bs a :: rest) =
    [| (::) [| MkPastArg (traverse (visitBeside v) bs) (visitArg v a) |] (visitPasts v rest) |]

  visitSettling : Applicative m => Visitor m req req' -> SettlingNode req vs -> m (SettlingNode req' vs)
  visitSettling v (SettledOver o) = SettledOver <$> visitOver v o
  visitSettling v (SettledUse u) = SettledUse <$> visitUseAt v u
  visitSettling v (Settling Nothing f) = Settling Nothing <$> visitForm v f
  visitSettling v (Settling (Just u) f) = [| Settling (Just <$> visitUseAt v u) (visitForm v f) |]

  visitForm : Applicative m => Visitor m req req' -> FormNode req vs -> m (FormNode req' vs)
  visitForm v (FormWalked h) = FormWalked <$> visitHead v h
  visitForm v (FormHolding h) = FormHolding <$> visitHead v h

  visitBound : Applicative m => Visitor m req req' -> BoundArg req vs -> m (BoundArg req' vs)
  visitBound v (MkBoundArg th w b) = MkBoundArg th w <$> visitBoundAs v b

  visitBoundAs : Applicative m => Visitor m req req' -> BoundAs req vs us -> m (BoundAs req' vs us)
  visitBoundAs v BoundCompileTime = pure BoundCompileTime
  visitBoundAs v BoundAlias = pure BoundAlias
  visitBoundAs v (BoundForm s u k) = [| BoundForm (visitStatic v s) (visitMaybeUse v u) (visitKept v k) |]
  visitBoundAs v (BoundValue c t) = [| BoundValue (visitCode v c) (visitTypeRead v t) |]

  visitArgs : Applicative m => Visitor m req req' -> List (ArgNode req vs) -> m (List (ArgNode req' vs))
  visitArgs v [] = pure []
  visitArgs v (a :: as) = [| visitArg v a :: visitArgs v as |]

  visitArg : Applicative m => Visitor m req req' -> ArgNode req vs -> m (ArgNode req' vs)
  visitArg v (MkArgNode th w t) = MkArgNode th w <$> visitTaken v t

  visitTaken : Applicative m => Visitor m req req' -> TakenAs req vs -> m (TakenAs req' vs)
  visitTaken v (TakenWalked w) = TakenWalked <$> visitWalk v w
  visitTaken v (TakenUsed u w) = [| TakenUsed (visitMaybeUse v u) (visitWalk v w) |]
  visitTaken v (TakenMember mem c) = [| TakenMember (visitMember v mem) (visitCode v c) |]
  visitTaken v (TakenEither mem w) = [| TakenEither (visitMember v mem) (visitWalk v w) |]
  visitTaken v (TakenComputed w c) = [| TakenComputed (visitWalk v w) (visitComputed v c) |]

  visitWalk : Applicative m => Visitor m req req' -> ArgWalk req vs -> m (ArgWalk req' vs)
  visitWalk v WalkedNowhere = pure WalkedNowhere
  visitWalk v (WalkedCode c) = WalkedCode <$> visitCode v c
  visitWalk v (WalkedStatic s) = WalkedStatic <$> visitStatic v s
  visitWalk v (WalkedBoth s c) = [| WalkedBoth (visitStatic v s) (visitCode v c) |]

  visitMember : Applicative m => Visitor m req req' -> MemberNode req vs -> m (MemberNode req' vs)
  visitMember v (MkMemberNode made used) = [| MkMemberNode (traverse (visitMemberAt v) made) (visitMaybeUse v used) |]

  visitComputed : Applicative m => Visitor m req req' -> ComputedNode req vs -> m (ComputedNode req' vs)
  visitComputed v (ComputedCode c) = ComputedCode <$> visitCode v c
  visitComputed v (ComputedSettled k s) = [| ComputedSettled (visitKept v k) (visitSettling v s) |]

  visitStaticHead : Applicative m => Visitor m req req' -> StaticHead req vs -> m (StaticHead req' vs)
  visitStaticHead v (StaticReference r) = StaticReference <$> visitStaticRef v r
  visitStaticHead v (StaticSolved h) = StaticSolved <$> visitStaticHead v h
  visitStaticHead v StaticNotEntered = pure StaticNotEntered
  visitStaticHead v (StaticOther s as) = [| StaticOther (visitStatic v s) (visitArgs v as) |]

  visitStaticRef : Applicative m => Visitor m req req' -> StaticRefNode req vs -> m (StaticRefNode req' vs)
  visitStaticRef v (StaticMarker as) = StaticMarker <$> visitArgs v as
  visitStaticRef v (StaticConstructor c fs later) = [| StaticConstructor (visitConstructed v c) (visitArgs v fs) (visitArgs v later) |]
  visitStaticRef v (StaticDefinition own as) = [| StaticDefinition (traverse (visitRequested v) own) (visitArgs v as) |]

mutual
  visitTree : Applicative m => Visitor m req req' -> TreeNode req vs -> m (TreeNode req' vs)
  visitTree v (MkTreeNode t s) = MkTreeNode t <$> visitTreeStep v s

  visitTreeStep : Applicative m => Visitor m req req' -> TreeStep req vs -> m (TreeStep req' vs)
  visitTreeStep v (TreeLeaf mem c) = [| TreeLeaf (visitLeafMember v mem) (visitCode v c) |]
  visitTreeStep v TreeUnmatched = pure TreeUnmatched
  visitTreeStep v TreeImpossible = pure TreeImpossible
  visitTreeStep v (TreeMatch r alts) = [| TreeMatch (traverse (visitRepacked v) r) (visitAlts v alts) |]

  visitAlts : Applicative m => Visitor m req req' -> List (AltNode req vs) -> m (List (AltNode req' vs))
  visitAlts v [] = pure []
  visitAlts v (a :: as) = [| visitAlt v a :: visitAlts v as |]

  visitAlt : Applicative m => Visitor m req req' -> AltNode req vs -> m (AltNode req' vs)
  visitAlt v (ConstructorAlt t) = ConstructorAlt <$> visitTree v t
  visitAlt v UnknownConstructorAlt = pure UnknownConstructorAlt
  visitAlt v DefaultNone = pure DefaultNone
  visitAlt v (DefaultOnce t) = DefaultOnce <$> visitTree v t
  visitAlt v (DefaultExpanded es) = DefaultExpanded <$> visitExpansions v es
  visitAlt v (ConstantAlt t) = ConstantAlt <$> visitTree v t
  visitAlt v (DelayAlt t) = DelayAlt <$> visitTree v t

  visitExpansions : Applicative m => Visitor m req req' -> List (ExpansionNode req vs) -> m (List (ExpansionNode req' vs))
  visitExpansions v [] = pure []
  visitExpansions v (Expanded n t :: es) = [| (::) (Expanded n <$> visitTree v t) (visitExpansions v es) |]
  visitExpansions v (NotExpanded n :: es) = (NotExpanded n ::) <$> visitExpansions v es

  visitLeafMember : Applicative m => Visitor m req req' -> LeafMember req vs -> m (LeafMember req' vs)
  visitLeafMember v ValueLeaf = pure ValueLeaf
  visitLeafMember v (MemberLeaf u mem) = [| MemberLeaf (visitMaybeUse v u) (traverse (visitMemberAt v) mem) |]

visitSignature : Applicative m => Visitor m req req' -> SignatureNode req -> m (SignatureNode req')
visitSignature v (MkSignatureNode bs r) = [| MkSignatureNode (traverse (traverse (visitTypeRead v)) bs) (visitTypeRead v r) |]

visitBody : Applicative m => Visitor m req req' -> BodyNode req -> m (BodyNode req')
visitBody v NoBody = pure NoBody
visitBody v Untranslated = pure Untranslated
visitBody v (ProjectionBody d) = ProjectionBody <$> v d
visitBody v (CaseBody t) = CaseBody <$> visitTree v t

||| Every request a reading holds visited once, in the order the walk made
||| them: its fields', its signature's, then its body's.
export
traverseReading : Applicative m => Visitor m req req' -> ReadingTree req -> m (ReadingTree req')
traverseReading v (MkReadingTree fs sig b) =
  [| MkReadingTree (traverse (\(r ** x) => (\y => (r ** y)) <$> v x) fs) (visitSignature v sig) (visitBody v b) |]

||| Every request a type read holds visited once, in the order the walk made
||| them.
export
traverseTypeRead : Applicative m => Visitor m req req' -> TypeRead req vs -> m (TypeRead req' vs)
traverseTypeRead = visitTypeRead

------------------------------------------------------------------------------
-- Labelling the requests
------------------------------------------------------------------------------

||| What labelling does at each request: makes one of the request's role of
||| the request and its label.
public export
0 Labeller : (ReachKind -> Type) -> (ReachKind -> Type) -> Type -> Type
Labeller req req' b = {0 r : ReachKind} -> req r -> b -> req' r

-- How many requests a list holds, each counted by `c`.
sizeList : (a -> Nat) -> List a -> Nat
sizeList c [] = 0
sizeList c (x :: xs) = c x + sizeList c xs

-- A list labelled, each element taking as many labels as it counts.
labelList : (c : a -> Nat) -> ((x : a) -> Vect (c x) b -> a') -> (xs : List a) -> Vect (sizeList c xs) b -> List a'
labelList c l [] [] = []
labelList c l (x :: xs) v = let (h, t) = splitAt (c x) v in l x h :: labelList c l xs t

sizeMaybe : (a -> Nat) -> Maybe a -> Nat
sizeMaybe c Nothing = 0
sizeMaybe c (Just x) = c x

labelMaybe : (c : a -> Nat) -> ((x : a) -> Vect (c x) b -> a') -> (m : Maybe a) -> Vect (sizeMaybe c m) b -> Maybe a'
labelMaybe c l Nothing [] = Nothing
labelMaybe c l (Just x) v = Just (l x v)

-- Requests of one role, one label each.
zipLabels : (a -> b -> c) -> (xs : List a) -> Vect (length xs) b -> List c
zipLabels k [] [] = []
zipLabels k (x :: xs) (y :: ys) = k x y :: zipLabels k xs ys

sizePair : PairSites req -> Nat
sizePair _ = 3

labelPair : Labeller req req' b -> (x : PairSites req) -> Vect (sizePair x) b -> PairSites req'
labelPair k (MkPairSites p a b) [x, y, z] = MkPairSites (k p x) (k a y) (k b z)

sizeHeld : HeldSites req -> Nat
sizeHeld (MkHeldSites ts p) = length ts + sizeMaybe sizePair p

labelHeld : Labeller req req' b -> (x : HeldSites req) -> Vect (sizeHeld x) b -> HeldSites req'
labelHeld k (MkHeldSites ts p) v =
  let (a, c) = splitAt (length ts) v in MkHeldSites (zipLabels (k {r = BuildReach}) ts a) (labelMaybe sizePair (labelPair k) p c)

sizeBeside : Beside req -> Nat
sizeBeside (BuildsBeside bs) = length bs
sizeBeside NothingBeside = 0
sizeBeside (HeldBeside hs) = sizeList sizeHeld hs

labelBeside : Labeller req req' b -> (x : Beside req) -> Vect (sizeBeside x) b -> Beside req'
labelBeside k (BuildsBeside bs) v = BuildsBeside (zipLabels (k {r = BuildReach}) bs v)
labelBeside k NothingBeside [] = NothingBeside
labelBeside k (HeldBeside hs) v = HeldBeside (labelList sizeHeld (labelHeld k) hs v)

sizeRequested : Requested req r -> Nat
sizeRequested (MkRequested _ bs) = 1 + sizeList sizeBeside bs

labelRequested : Labeller req req' b -> (x : Requested req r) -> Vect (sizeRequested x) b -> Requested req' r
labelRequested k (MkRequested x bs) (y :: v) = MkRequested (k x y) (labelList sizeBeside (labelBeside k) bs v)

sizeMemberAt : MemberAt req -> Nat
sizeMemberAt (MkMemberAt _ hs) = 1 + sizeList sizeHeld hs

labelMemberAt : Labeller req req' b -> (x : MemberAt req) -> Vect (sizeMemberAt x) b -> MemberAt req'
labelMemberAt k (MkMemberAt x hs) (y :: v) = MkMemberAt (k x y) (labelList sizeHeld (labelHeld k) hs v)

sizeKept : KeptAt req -> Nat
sizeKept KeepsNothing = 0
sizeKept (KeepsList _ h) = 1 + sizeHeld h

labelKept : Labeller req req' b -> (x : KeptAt req) -> Vect (sizeKept x) b -> KeptAt req'
labelKept k KeepsNothing [] = KeepsNothing
labelKept k (KeepsList x h) (y :: v) = KeepsList (k x y) (labelHeld k h v)

sizeRepacked : Repacked req -> Nat
sizeRepacked (MkRepacked _ p) = 1 + sizeMaybe sizePair p

labelRepacked : Labeller req req' b -> (x : Repacked req) -> Vect (sizeRepacked x) b -> Repacked req'
labelRepacked k (MkRepacked x p) (y :: v) = MkRepacked (k x y) (labelMaybe sizePair (labelPair k) p v)

sizeConstructed : ConstructedSites req -> Nat
sizeConstructed (MkConstructedSites c r) = sizeMaybe sizeRequested c + length r

labelConstructed : Labeller req req' b -> (x : ConstructedSites req) -> Vect (sizeConstructed x) b -> ConstructedSites req'
labelConstructed k (MkConstructedSites c r) v =
  let (a, d) = splitAt (sizeMaybe sizeRequested c) v in
  MkConstructedSites (labelMaybe sizeRequested (labelRequested k) c a) (zipLabels (k {r = BuildReach}) r d)

mutual
  -- Each size counts a node's fields in the order its visit goes through
  -- them, and each labelling splits its labels in that order, so the
  -- labels go to the requests in the order they were made.
  sizeCode : CodeNode req vs -> Nat
  sizeCode (MkCodeNode _ s) = sizeCodeStep s

  sizeCodeStep : CodeStep req vs -> Nat
  sizeCodeStep CodeInert = 0
  sizeCodeStep (CodeApplied h) = sizeHead h
  sizeCodeStep (CodeLambda l) = sizeLambda l
  sizeCodeStep (CodeLetType b) = sizeCode b
  sizeCodeStep (CodeLetErased b) = sizeCode b
  sizeCodeStep (CodeLetForm s u k b) = sizeStatic s + (sizeMaybeUse u + (sizeKept k + sizeCode b))
  sizeCodeStep (CodeLetValue c t b) = sizeCode c + (sizeTypeRead t + sizeCode b)
  sizeCodeStep (CodeAs c) = sizeCode c
  sizeCodeStep (CodeDelay c) = sizeCode c
  sizeCodeStep (CodeForce c) = sizeCode c

  sizeLambda : LambdaNode req vs -> Nat
  sizeLambda (ErasedBinder b) = sizeLambdaBody b
  sizeLambda (UsedBinder t b) = sizeTypeRead t + sizeLambdaBody b

  sizeLambdaBody : LambdaBodyNode req vs -> Nat
  sizeLambdaBody (InnerLambda l) = sizeLambda l
  sizeLambdaBody (LambdaCode c) = sizeCode c

  sizeTypeRead : TypeRead req vs -> Nat
  sizeTypeRead (MkTypeRead s bs) = sizeStatic s + length bs

  sizeStatic : StaticNode req vs -> Nat
  sizeStatic (MkStaticNode _ s) = sizeStaticStep s

  sizeStaticStep : StaticStep req vs -> Nat
  sizeStaticStep StaticInert = 0
  sizeStaticStep (StaticApplied h) = sizeStaticHead h
  sizeStaticStep (StaticBinder t s) = sizeStatic t + sizeStatic s
  sizeStaticStep (StaticLet x t s) = sizeStatic x + (sizeStatic t + sizeStatic s)
  sizeStaticStep (StaticAs s) = sizeStatic s
  sizeStaticStep (StaticLazy s) = sizeStatic s
  sizeStaticStep (StaticDelay t s) = sizeStatic t + sizeStatic s
  sizeStaticStep (StaticForce s) = sizeStatic s

  sizeUse : UseNode req vs -> Nat
  sizeUse (MkUseNode _ s) = sizeUseStep s

  sizeMaybeUse : Maybe (UseNode req vs) -> Nat
  sizeMaybeUse Nothing = 0
  sizeMaybeUse (Just u) = sizeUse u

  sizeUseStep : UseStep req vs -> Nat
  sizeUseStep UseInert = 0
  sizeUseStep (UseDelayed u) = sizeUse u
  sizeUseStep (UseUnderLet u) = sizeUse u
  sizeUseStep (UseApplied h) = sizeHead h

  sizeHead : HeadNode req vs -> Nat
  sizeHead (HeadReference r) = sizeRef r
  sizeHead (HeadVariable x) = sizeVariable x
  sizeHead (HeadLambda a b) = sizeBound a + sizeHead b
  sizeHead (HeadSolution s) = sizeSolution s
  sizeHead (HeadPattern h) = sizeHead h
  sizeHead (HeadOther c o) = sizeCode c + sizeOver o

  sizeSolution : SolutionNode req vs -> Nat
  sizeSolution (Solved h) = sizeHead h
  sizeSolution NotEntered = 0

  sizeVariable : VariableNode req vs -> Nat
  sizeVariable (RuntimeVariable o) = sizeOver o
  sizeVariable (SettledVariable s) = sizeSettling s
  sizeVariable CompileTimeVariable = 0

  sizeRef : RefNode req vs -> Nat
  sizeRef (MarkerReference o) = sizeOver o
  sizeRef (ConstructorReference c) = sizeConstruct c
  sizeRef (CalledReference c) = sizeCall c
  sizeRef RefusedReference = 0

  sizeConstruct : ConstructNode req vs -> Nat
  sizeConstruct (MkConstructNode mem c now later) =
    sizeMaybe sizeMemberAt mem + (sizeConstructed c + (sizeArgs now + sizeOver later))

  sizeCall : CallNode req vs -> Nat
  sizeCall (MkCallNode mem own instead now later) =
    sizeMaybe sizeMemberAt mem + (sizeRequested own + (sizeMaybe sizeRequested instead + (sizeArgs now + sizePastArity later)))

  sizePastArity : PastArity req vs -> Nat
  sizePastArity (MethodCall d) = sizeDispatch d
  sizePastArity (PastOver o) = sizeOver o

  sizeDispatch : DispatchNode req vs -> Nat
  sizeDispatch (MkDispatchNode d now later) = sizeRequested d + (sizeArgs now + sizeOver later)

  sizeOver : OverNode req vs -> Nat
  sizeOver OverDone = 0
  sizeOver (OverArgument a rest) = sizeArg a + sizeOver rest
  sizeOver (OverUse u) = sizeUseAt u

  sizeUseAt : UseAtNode req vs -> Nat
  sizeUseAt (MkUseAtNode a now past) = sizeRequested a + (sizeArgs now + sizePasts past)

  sizePasts : List (PastArg req vs) -> Nat
  sizePasts [] = 0
  sizePasts (MkPastArg bs a :: rest) = (sizeList sizeBeside bs + sizeArg a) + sizePasts rest

  sizeSettling : SettlingNode req vs -> Nat
  sizeSettling (SettledOver o) = sizeOver o
  sizeSettling (SettledUse u) = sizeUseAt u
  sizeSettling (Settling Nothing f) = sizeForm f
  sizeSettling (Settling (Just u) f) = sizeUseAt u + sizeForm f

  sizeForm : FormNode req vs -> Nat
  sizeForm (FormWalked h) = sizeHead h
  sizeForm (FormHolding h) = sizeHead h

  sizeBound : BoundArg req vs -> Nat
  sizeBound (MkBoundArg _ _ b) = sizeBoundAs b

  sizeBoundAs : BoundAs req vs us -> Nat
  sizeBoundAs BoundCompileTime = 0
  sizeBoundAs BoundAlias = 0
  sizeBoundAs (BoundForm s u k) = sizeStatic s + (sizeMaybeUse u + sizeKept k)
  sizeBoundAs (BoundValue c t) = sizeCode c + sizeTypeRead t

  sizeArgs : List (ArgNode req vs) -> Nat
  sizeArgs [] = 0
  sizeArgs (a :: as) = sizeArg a + sizeArgs as

  sizeArg : ArgNode req vs -> Nat
  sizeArg (MkArgNode _ _ t) = sizeTaken t

  sizeTaken : TakenAs req vs -> Nat
  sizeTaken (TakenWalked w) = sizeWalk w
  sizeTaken (TakenUsed u w) = sizeMaybeUse u + sizeWalk w
  sizeTaken (TakenMember mem c) = sizeMember mem + sizeCode c
  sizeTaken (TakenEither mem w) = sizeMember mem + sizeWalk w
  sizeTaken (TakenComputed w c) = sizeWalk w + sizeComputed c

  sizeWalk : ArgWalk req vs -> Nat
  sizeWalk WalkedNowhere = 0
  sizeWalk (WalkedCode c) = sizeCode c
  sizeWalk (WalkedStatic s) = sizeStatic s
  sizeWalk (WalkedBoth s c) = sizeStatic s + sizeCode c

  sizeMember : MemberNode req vs -> Nat
  sizeMember (MkMemberNode made used) = sizeMaybe sizeMemberAt made + sizeMaybeUse used

  sizeComputed : ComputedNode req vs -> Nat
  sizeComputed (ComputedCode c) = sizeCode c
  sizeComputed (ComputedSettled k s) = sizeKept k + sizeSettling s

  sizeStaticHead : StaticHead req vs -> Nat
  sizeStaticHead (StaticReference r) = sizeStaticRef r
  sizeStaticHead (StaticSolved h) = sizeStaticHead h
  sizeStaticHead StaticNotEntered = 0
  sizeStaticHead (StaticOther s as) = sizeStatic s + sizeArgs as

  sizeStaticRef : StaticRefNode req vs -> Nat
  sizeStaticRef (StaticMarker as) = sizeArgs as
  sizeStaticRef (StaticConstructor c fs later) = sizeConstructed c + (sizeArgs fs + sizeArgs later)
  sizeStaticRef (StaticDefinition own as) = sizeMaybe sizeRequested own + sizeArgs as

mutual
  labelCode : Labeller req req' b -> (x : CodeNode req vs) -> Vect (sizeCode x) b -> CodeNode req' vs
  labelCode k (MkCodeNode t s) v = MkCodeNode t (labelCodeStep k s v)

  labelCodeStep : Labeller req req' b -> (x : CodeStep req vs) -> Vect (sizeCodeStep x) b -> CodeStep req' vs
  labelCodeStep k CodeInert [] = CodeInert
  labelCodeStep k (CodeApplied h) v = CodeApplied (labelHead k h v)
  labelCodeStep k (CodeLambda l) v = CodeLambda (labelLambda k l v)
  labelCodeStep k (CodeLetType b) v = CodeLetType (labelCode k b v)
  labelCodeStep k (CodeLetErased b) v = CodeLetErased (labelCode k b v)
  labelCodeStep k (CodeLetForm s u kept b) v =
    let (vs, r1) = splitAt (sizeStatic s) v
        (vu, r2) = splitAt (sizeMaybeUse u) r1
        (vk, vb) = splitAt (sizeKept kept) r2 in
    CodeLetForm (labelStatic k s vs) (labelMaybeUse k u vu) (labelKept k kept vk) (labelCode k b vb)
  labelCodeStep k (CodeLetValue c t b) v =
    let (vc, r1) = splitAt (sizeCode c) v
        (vt, vb) = splitAt (sizeTypeRead t) r1 in
    CodeLetValue (labelCode k c vc) (labelTypeRead k t vt) (labelCode k b vb)
  labelCodeStep k (CodeAs c) v = CodeAs (labelCode k c v)
  labelCodeStep k (CodeDelay c) v = CodeDelay (labelCode k c v)
  labelCodeStep k (CodeForce c) v = CodeForce (labelCode k c v)

  labelLambda : Labeller req req' b -> (x : LambdaNode req vs) -> Vect (sizeLambda x) b -> LambdaNode req' vs
  labelLambda k (ErasedBinder b) v = ErasedBinder (labelLambdaBody k b v)
  labelLambda k (UsedBinder t b) v = let (vt, vb) = splitAt (sizeTypeRead t) v in UsedBinder (labelTypeRead k t vt) (labelLambdaBody k b vb)

  labelLambdaBody : Labeller req req' b -> (x : LambdaBodyNode req vs) -> Vect (sizeLambdaBody x) b -> LambdaBodyNode req' vs
  labelLambdaBody k (InnerLambda l) v = InnerLambda (labelLambda k l v)
  labelLambdaBody k (LambdaCode c) v = LambdaCode (labelCode k c v)

  labelTypeRead : Labeller req req' b -> (x : TypeRead req vs) -> Vect (sizeTypeRead x) b -> TypeRead req' vs
  labelTypeRead k (MkTypeRead s bs) v =
    let (vs, vb) = splitAt (sizeStatic s) v in MkTypeRead (labelStatic k s vs) (zipLabels (k {r = BuildReach}) bs vb)

  labelStatic : Labeller req req' b -> (x : StaticNode req vs) -> Vect (sizeStatic x) b -> StaticNode req' vs
  labelStatic k (MkStaticNode t s) v = MkStaticNode t (labelStaticStep k s v)

  labelStaticStep : Labeller req req' b -> (x : StaticStep req vs) -> Vect (sizeStaticStep x) b -> StaticStep req' vs
  labelStaticStep k StaticInert [] = StaticInert
  labelStaticStep k (StaticApplied h) v = StaticApplied (labelStaticHead k h v)
  labelStaticStep k (StaticBinder t s) v = let (vt, vs) = splitAt (sizeStatic t) v in StaticBinder (labelStatic k t vt) (labelStatic k s vs)
  labelStaticStep k (StaticLet x t s) v =
    let (vx, r1) = splitAt (sizeStatic x) v
        (vt, vs) = splitAt (sizeStatic t) r1 in
    StaticLet (labelStatic k x vx) (labelStatic k t vt) (labelStatic k s vs)
  labelStaticStep k (StaticAs s) v = StaticAs (labelStatic k s v)
  labelStaticStep k (StaticLazy s) v = StaticLazy (labelStatic k s v)
  labelStaticStep k (StaticDelay t s) v = let (vt, vs) = splitAt (sizeStatic t) v in StaticDelay (labelStatic k t vt) (labelStatic k s vs)
  labelStaticStep k (StaticForce s) v = StaticForce (labelStatic k s v)

  labelUse : Labeller req req' b -> (x : UseNode req vs) -> Vect (sizeUse x) b -> UseNode req' vs
  labelUse k (MkUseNode t s) v = MkUseNode t (labelUseStep k s v)

  labelMaybeUse : Labeller req req' b -> (x : Maybe (UseNode req vs)) -> Vect (sizeMaybeUse x) b -> Maybe (UseNode req' vs)
  labelMaybeUse k Nothing [] = Nothing
  labelMaybeUse k (Just u) v = Just (labelUse k u v)

  labelUseStep : Labeller req req' b -> (x : UseStep req vs) -> Vect (sizeUseStep x) b -> UseStep req' vs
  labelUseStep k UseInert [] = UseInert
  labelUseStep k (UseDelayed u) v = UseDelayed (labelUse k u v)
  labelUseStep k (UseUnderLet u) v = UseUnderLet (labelUse k u v)
  labelUseStep k (UseApplied h) v = UseApplied (labelHead k h v)

  labelHead : Labeller req req' b -> (x : HeadNode req vs) -> Vect (sizeHead x) b -> HeadNode req' vs
  labelHead k (HeadReference r) v = HeadReference (labelRef k r v)
  labelHead k (HeadVariable x) v = HeadVariable (labelVariable k x v)
  labelHead k (HeadLambda a b) v = let (va, vb) = splitAt (sizeBound a) v in HeadLambda (labelBound k a va) (labelHead k b vb)
  labelHead k (HeadSolution s) v = HeadSolution (labelSolution k s v)
  labelHead k (HeadPattern h) v = HeadPattern (labelHead k h v)
  labelHead k (HeadOther c o) v = let (vc, vo) = splitAt (sizeCode c) v in HeadOther (labelCode k c vc) (labelOver k o vo)

  labelSolution : Labeller req req' b -> (x : SolutionNode req vs) -> Vect (sizeSolution x) b -> SolutionNode req' vs
  labelSolution k (Solved h) v = Solved (labelHead k h v)
  labelSolution k NotEntered [] = NotEntered

  labelVariable : Labeller req req' b -> (x : VariableNode req vs) -> Vect (sizeVariable x) b -> VariableNode req' vs
  labelVariable k (RuntimeVariable o) v = RuntimeVariable (labelOver k o v)
  labelVariable k (SettledVariable s) v = SettledVariable (labelSettling k s v)
  labelVariable k CompileTimeVariable [] = CompileTimeVariable

  labelRef : Labeller req req' b -> (x : RefNode req vs) -> Vect (sizeRef x) b -> RefNode req' vs
  labelRef k (MarkerReference o) v = MarkerReference (labelOver k o v)
  labelRef k (ConstructorReference c) v = ConstructorReference (labelConstruct k c v)
  labelRef k (CalledReference c) v = CalledReference (labelCall k c v)
  labelRef k RefusedReference [] = RefusedReference

  labelConstruct : Labeller req req' b -> (x : ConstructNode req vs) -> Vect (sizeConstruct x) b -> ConstructNode req' vs
  labelConstruct k (MkConstructNode mem c now later) v =
    let (vm, r1) = splitAt (sizeMaybe sizeMemberAt mem) v
        (vc, r2) = splitAt (sizeConstructed c) r1
        (vn, vl) = splitAt (sizeArgs now) r2 in
    MkConstructNode (labelMaybe sizeMemberAt (labelMemberAt k) mem vm) (labelConstructed k c vc) (labelArgs k now vn) (labelOver k later vl)

  labelCall : Labeller req req' b -> (x : CallNode req vs) -> Vect (sizeCall x) b -> CallNode req' vs
  labelCall k (MkCallNode mem own instead now later) v =
    let (vm, r1) = splitAt (sizeMaybe sizeMemberAt mem) v
        (vo, r2) = splitAt (sizeRequested own) r1
        (vi, r3) = splitAt (sizeMaybe sizeRequested instead) r2
        (vn, vl) = splitAt (sizeArgs now) r3 in
    MkCallNode (labelMaybe sizeMemberAt (labelMemberAt k) mem vm) (labelRequested k own vo)
               (labelMaybe sizeRequested (labelRequested k) instead vi) (labelArgs k now vn) (labelPastArity k later vl)

  labelPastArity : Labeller req req' b -> (x : PastArity req vs) -> Vect (sizePastArity x) b -> PastArity req' vs
  labelPastArity k (MethodCall d) v = MethodCall (labelDispatch k d v)
  labelPastArity k (PastOver o) v = PastOver (labelOver k o v)

  labelDispatch : Labeller req req' b -> (x : DispatchNode req vs) -> Vect (sizeDispatch x) b -> DispatchNode req' vs
  labelDispatch k (MkDispatchNode d now later) v =
    let (vd, r1) = splitAt (sizeRequested d) v
        (vn, vl) = splitAt (sizeArgs now) r1 in
    MkDispatchNode (labelRequested k d vd) (labelArgs k now vn) (labelOver k later vl)

  labelOver : Labeller req req' b -> (x : OverNode req vs) -> Vect (sizeOver x) b -> OverNode req' vs
  labelOver k OverDone [] = OverDone
  labelOver k (OverArgument a rest) v = let (va, vr) = splitAt (sizeArg a) v in OverArgument (labelArg k a va) (labelOver k rest vr)
  labelOver k (OverUse u) v = OverUse (labelUseAt k u v)

  labelUseAt : Labeller req req' b -> (x : UseAtNode req vs) -> Vect (sizeUseAt x) b -> UseAtNode req' vs
  labelUseAt k (MkUseAtNode a now past) v =
    let (va, r1) = splitAt (sizeRequested a) v
        (vn, vp) = splitAt (sizeArgs now) r1 in
    MkUseAtNode (labelRequested k a va) (labelArgs k now vn) (labelPasts k past vp)

  labelPasts : Labeller req req' b -> (x : List (PastArg req vs)) -> Vect (sizePasts x) b -> List (PastArg req' vs)
  labelPasts k [] [] = []
  labelPasts k (MkPastArg bs a :: rest) v =
    let (vh, vr) = splitAt (sizeList sizeBeside bs + sizeArg a) v
        (vb, va) = splitAt (sizeList sizeBeside bs) vh in
    MkPastArg (labelList sizeBeside (labelBeside k) bs vb) (labelArg k a va) :: labelPasts k rest vr

  labelSettling : Labeller req req' b -> (x : SettlingNode req vs) -> Vect (sizeSettling x) b -> SettlingNode req' vs
  labelSettling k (SettledOver o) v = SettledOver (labelOver k o v)
  labelSettling k (SettledUse u) v = SettledUse (labelUseAt k u v)
  labelSettling k (Settling Nothing f) v = Settling Nothing (labelForm k f v)
  labelSettling k (Settling (Just u) f) v = let (vu, vf) = splitAt (sizeUseAt u) v in Settling (Just (labelUseAt k u vu)) (labelForm k f vf)

  labelForm : Labeller req req' b -> (x : FormNode req vs) -> Vect (sizeForm x) b -> FormNode req' vs
  labelForm k (FormWalked h) v = FormWalked (labelHead k h v)
  labelForm k (FormHolding h) v = FormHolding (labelHead k h v)

  labelBound : Labeller req req' b -> (x : BoundArg req vs) -> Vect (sizeBound x) b -> BoundArg req' vs
  labelBound k (MkBoundArg th w b) v = MkBoundArg th w (labelBoundAs k b v)

  labelBoundAs : Labeller req req' b -> (x : BoundAs req vs us) -> Vect (sizeBoundAs x) b -> BoundAs req' vs us
  labelBoundAs k BoundCompileTime [] = BoundCompileTime
  labelBoundAs k BoundAlias [] = BoundAlias
  labelBoundAs k (BoundForm s u kept) v =
    let (vs, r1) = splitAt (sizeStatic s) v
        (vu, vk) = splitAt (sizeMaybeUse u) r1 in
    BoundForm (labelStatic k s vs) (labelMaybeUse k u vu) (labelKept k kept vk)
  labelBoundAs k (BoundValue c t) v = let (vc, vt) = splitAt (sizeCode c) v in BoundValue (labelCode k c vc) (labelTypeRead k t vt)

  labelArgs : Labeller req req' b -> (x : List (ArgNode req vs)) -> Vect (sizeArgs x) b -> List (ArgNode req' vs)
  labelArgs k [] [] = []
  labelArgs k (a :: as) v = let (va, vs) = splitAt (sizeArg a) v in labelArg k a va :: labelArgs k as vs

  labelArg : Labeller req req' b -> (x : ArgNode req vs) -> Vect (sizeArg x) b -> ArgNode req' vs
  labelArg k (MkArgNode th w t) v = MkArgNode th w (labelTaken k t v)

  labelTaken : Labeller req req' b -> (x : TakenAs req vs) -> Vect (sizeTaken x) b -> TakenAs req' vs
  labelTaken k (TakenWalked w) v = TakenWalked (labelWalk k w v)
  labelTaken k (TakenUsed u w) v = let (vu, vw) = splitAt (sizeMaybeUse u) v in TakenUsed (labelMaybeUse k u vu) (labelWalk k w vw)
  labelTaken k (TakenMember mem c) v = let (vm, vc) = splitAt (sizeMember mem) v in TakenMember (labelMember k mem vm) (labelCode k c vc)
  labelTaken k (TakenEither mem w) v = let (vm, vw) = splitAt (sizeMember mem) v in TakenEither (labelMember k mem vm) (labelWalk k w vw)
  labelTaken k (TakenComputed w c) v = let (vw, vc) = splitAt (sizeWalk w) v in TakenComputed (labelWalk k w vw) (labelComputed k c vc)

  labelWalk : Labeller req req' b -> (x : ArgWalk req vs) -> Vect (sizeWalk x) b -> ArgWalk req' vs
  labelWalk k WalkedNowhere [] = WalkedNowhere
  labelWalk k (WalkedCode c) v = WalkedCode (labelCode k c v)
  labelWalk k (WalkedStatic s) v = WalkedStatic (labelStatic k s v)
  labelWalk k (WalkedBoth s c) v = let (vs, vc) = splitAt (sizeStatic s) v in WalkedBoth (labelStatic k s vs) (labelCode k c vc)

  labelMember : Labeller req req' b -> (x : MemberNode req vs) -> Vect (sizeMember x) b -> MemberNode req' vs
  labelMember k (MkMemberNode made used) v =
    let (vm, vu) = splitAt (sizeMaybe sizeMemberAt made) v in
    MkMemberNode (labelMaybe sizeMemberAt (labelMemberAt k) made vm) (labelMaybeUse k used vu)

  labelComputed : Labeller req req' b -> (x : ComputedNode req vs) -> Vect (sizeComputed x) b -> ComputedNode req' vs
  labelComputed k (ComputedCode c) v = ComputedCode (labelCode k c v)
  labelComputed k (ComputedSettled kept s) v = let (vk, vs) = splitAt (sizeKept kept) v in ComputedSettled (labelKept k kept vk) (labelSettling k s vs)

  labelStaticHead : Labeller req req' b -> (x : StaticHead req vs) -> Vect (sizeStaticHead x) b -> StaticHead req' vs
  labelStaticHead k (StaticReference r) v = StaticReference (labelStaticRef k r v)
  labelStaticHead k (StaticSolved h) v = StaticSolved (labelStaticHead k h v)
  labelStaticHead k StaticNotEntered [] = StaticNotEntered
  labelStaticHead k (StaticOther s as) v = let (vs, va) = splitAt (sizeStatic s) v in StaticOther (labelStatic k s vs) (labelArgs k as va)

  labelStaticRef : Labeller req req' b -> (x : StaticRefNode req vs) -> Vect (sizeStaticRef x) b -> StaticRefNode req' vs
  labelStaticRef k (StaticMarker as) v = StaticMarker (labelArgs k as v)
  labelStaticRef k (StaticConstructor c fs later) v =
    let (vc, r1) = splitAt (sizeConstructed c) v
        (vf, vl) = splitAt (sizeArgs fs) r1 in
    StaticConstructor (labelConstructed k c vc) (labelArgs k fs vf) (labelArgs k later vl)
  labelStaticRef k (StaticDefinition own as) v =
    let (vo, va) = splitAt (sizeMaybe sizeRequested own) v in
    StaticDefinition (labelMaybe sizeRequested (labelRequested k) own vo) (labelArgs k as va)

mutual
  sizeTree : TreeNode req vs -> Nat
  sizeTree (MkTreeNode _ s) = sizeTreeStep s

  sizeTreeStep : TreeStep req vs -> Nat
  sizeTreeStep (TreeLeaf mem c) = sizeLeafMember mem + sizeCode c
  sizeTreeStep TreeUnmatched = 0
  sizeTreeStep TreeImpossible = 0
  sizeTreeStep (TreeMatch r alts) = sizeMaybe sizeRepacked r + sizeAlts alts

  sizeAlts : List (AltNode req vs) -> Nat
  sizeAlts [] = 0
  sizeAlts (a :: as) = sizeAlt a + sizeAlts as

  sizeAlt : AltNode req vs -> Nat
  sizeAlt (ConstructorAlt t) = sizeTree t
  sizeAlt UnknownConstructorAlt = 0
  sizeAlt DefaultNone = 0
  sizeAlt (DefaultOnce t) = sizeTree t
  sizeAlt (DefaultExpanded es) = sizeExpansions es
  sizeAlt (ConstantAlt t) = sizeTree t
  sizeAlt (DelayAlt t) = sizeTree t

  sizeExpansions : List (ExpansionNode req vs) -> Nat
  sizeExpansions [] = 0
  sizeExpansions (Expanded _ t :: es) = sizeTree t + sizeExpansions es
  sizeExpansions (NotExpanded _ :: es) = sizeExpansions es

  sizeLeafMember : LeafMember req vs -> Nat
  sizeLeafMember ValueLeaf = 0
  sizeLeafMember (MemberLeaf u mem) = sizeMaybeUse u + sizeMaybe sizeMemberAt mem

mutual
  labelTree : Labeller req req' b -> (x : TreeNode req vs) -> Vect (sizeTree x) b -> TreeNode req' vs
  labelTree k (MkTreeNode t s) v = MkTreeNode t (labelTreeStep k s v)

  labelTreeStep : Labeller req req' b -> (x : TreeStep req vs) -> Vect (sizeTreeStep x) b -> TreeStep req' vs
  labelTreeStep k (TreeLeaf mem c) v = let (vm, vc) = splitAt (sizeLeafMember mem) v in TreeLeaf (labelLeafMember k mem vm) (labelCode k c vc)
  labelTreeStep k TreeUnmatched [] = TreeUnmatched
  labelTreeStep k TreeImpossible [] = TreeImpossible
  labelTreeStep k (TreeMatch r alts) v =
    let (vr, va) = splitAt (sizeMaybe sizeRepacked r) v in TreeMatch (labelMaybe sizeRepacked (labelRepacked k) r vr) (labelAlts k alts va)

  labelAlts : Labeller req req' b -> (x : List (AltNode req vs)) -> Vect (sizeAlts x) b -> List (AltNode req' vs)
  labelAlts k [] [] = []
  labelAlts k (a :: as) v = let (va, vs) = splitAt (sizeAlt a) v in labelAlt k a va :: labelAlts k as vs

  labelAlt : Labeller req req' b -> (x : AltNode req vs) -> Vect (sizeAlt x) b -> AltNode req' vs
  labelAlt k (ConstructorAlt t) v = ConstructorAlt (labelTree k t v)
  labelAlt k UnknownConstructorAlt [] = UnknownConstructorAlt
  labelAlt k DefaultNone [] = DefaultNone
  labelAlt k (DefaultOnce t) v = DefaultOnce (labelTree k t v)
  labelAlt k (DefaultExpanded es) v = DefaultExpanded (labelExpansions k es v)
  labelAlt k (ConstantAlt t) v = ConstantAlt (labelTree k t v)
  labelAlt k (DelayAlt t) v = DelayAlt (labelTree k t v)

  labelExpansions : Labeller req req' b -> (x : List (ExpansionNode req vs)) -> Vect (sizeExpansions x) b -> List (ExpansionNode req' vs)
  labelExpansions k [] [] = []
  labelExpansions k (Expanded n t :: es) v = let (vt, ve) = splitAt (sizeTree t) v in Expanded n (labelTree k t vt) :: labelExpansions k es ve
  labelExpansions k (NotExpanded n :: es) v = NotExpanded n :: labelExpansions k es v

  labelLeafMember : Labeller req req' b -> (x : LeafMember req vs) -> Vect (sizeLeafMember x) b -> LeafMember req' vs
  labelLeafMember k ValueLeaf [] = ValueLeaf
  labelLeafMember k (MemberLeaf u mem) v =
    let (vu, vm) = splitAt (sizeMaybeUse u) v in MemberLeaf (labelMaybeUse k u vu) (labelMaybe sizeMemberAt (labelMemberAt k) mem vm)

sizeSignature : SignatureNode req -> Nat
sizeSignature (MkSignatureNode bs r) = sizeList (sizeMaybe sizeTypeRead) bs + sizeTypeRead r

labelSignature : Labeller req req' b -> (x : SignatureNode req) -> Vect (sizeSignature x) b -> SignatureNode req'
labelSignature k (MkSignatureNode bs r) v =
  let (vb, vr) = splitAt (sizeList (sizeMaybe sizeTypeRead) bs) v in
  MkSignatureNode (labelList (sizeMaybe sizeTypeRead) (labelMaybe sizeTypeRead (labelTypeRead k)) bs vb) (labelTypeRead k r vr)

sizeBody : BodyNode req -> Nat
sizeBody NoBody = 0
sizeBody Untranslated = 0
sizeBody (ProjectionBody _) = 1
sizeBody (CaseBody t) = sizeTree t

labelBody : Labeller req req' b -> (x : BodyNode req) -> Vect (sizeBody x) b -> BodyNode req'
labelBody k NoBody [] = NoBody
labelBody k Untranslated [] = Untranslated
labelBody k (ProjectionBody d) [y] = ProjectionBody (k d y)
labelBody k (CaseBody t) v = CaseBody (labelTree k t v)

sizeField : {0 req : ReachKind -> Type} -> (r : ReachKind ** req r) -> Nat
sizeField _ = 1

labelField : Labeller req req' b -> (x : (r : ReachKind ** req r)) -> Vect (sizeField x) b -> (r : ReachKind ** req' r)
labelField k (r ** x) [y] = (r ** k x y)

||| How many requests a reading holds.
export
readingSize : ReadingTree req -> Nat
readingSize (MkReadingTree fs sig b) = sizeList sizeField fs + (sizeSignature sig + sizeBody b)

||| A reading with each request labelled, as many labels as it holds, in
||| the order the walk made the requests: the order `traverseReading` visits
||| them in.
export
labelReading : Labeller req req' b -> (x : ReadingTree req) -> Vect (readingSize x) b -> ReadingTree req'
labelReading k (MkReadingTree fs sig b) v =
  let (vf, r1) = splitAt (sizeList sizeField fs) v
      (vs, vb) = splitAt (sizeSignature sig) r1 in
  MkReadingTree (labelList sizeField (labelField k) fs vf) (labelSignature k sig vs) (labelBody k b vb)
