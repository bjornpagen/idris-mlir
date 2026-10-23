-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| Join points: a continuation local to its function, jumped to in tail
||| position with typed arguments (grades and reuse tokens among them),
||| never an allocated closure. An op of the family holds its body, region
||| 0, entered once from the op, and one join region per join point, whose
||| parameters are its entry block's arguments after its tokens; it yields
||| its results as a match does. A join region binds the erased index
||| variables its parameters' types name, and a jump instantiates them.
|||
||| A target is upstream's builtin token: only a token producer defines one
||| and only a token consumer uses one, which the core verifier holds for
||| every op of every dialect, so a join point cannot be stored, passed,
||| returned, yielded or captured, and no check of ours looks for an escape.
|||
||| The family's two members differ in where their tokens are, which is what
||| their regions may do: `idr.join` defines them in its body alone, so no
||| join region names its own op's targets and none repeats or diverges;
||| `idr.loop` begins every region with them, so a join region may jump to
||| itself or a sibling, and its regions repeat. A recursive join point is a
||| loop, and an op whose regions cannot repeat is never one. A loop of code
||| Idris did not prove to end may run forever, which its function's row
||| holds from Idris's proof, so no op of the loop marks it.
|||
||| Each scoped value an op of the family makes lives in the lifetime its
||| own entry of `outers` states: its scoped results, in result order, then
||| each scoped parameter of each region, in region and parameter order,
||| since each join region binds values of its own.
module IdrisMLIR.Spec.Control.Joins

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Control.Matches
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Families.Dialect
import IdrisMLIR.Spec.Lifetimes.Declarations

import Data.Fin
import Data.List.Elem
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- The family's constant
------------------------------------------------------------------------------

||| Where a member's tokens are: in its body alone, or at the head of every
||| region.
public export
data TokenScope = InBody | InEveryRegion

export
tokenScopeClosed : Closed TokenScope
tokenScopeClosed = MkClosed
  { name = "TokenScope"
  , shape = OneOf
  , every = InBody ::: [InEveryRegion]
  , complete = \case
      InBody => Here
      InEveryRegion => There Here
  , describe = \case
      InBody => MkCase "InBody" (word "in_body" ::: []) "the body defines the tokens: no join region repeats"
      InEveryRegion => MkCase "InEveryRegion" (word "in_every_region" ::: [])
                         "every region begins with the tokens: join regions repeat"
  , doc = brief "where the tokens of a join point's op are"
  }

tokenScopeEnum : EnumDef
tokenScopeEnum = enumDef tokenScopeClosed

||| The mnemonic of each member.
public export
memberName : TokenScope -> Mnemonic
memberName InBody = "join"
memberName InEveryRegion = "loop"

memberCase : TokenScope -> Ident
memberCase InBody = "InBody"
memberCase InEveryRegion = "InEveryRegion"

------------------------------------------------------------------------------
-- The shape both members share
------------------------------------------------------------------------------

||| `JoinPointsOpInterface`: what a jump and the passes that read jumps
||| ask a join point's op, which lists no op: the join region a token
||| designates, a region's tokens, a join region's parameters.
export
joinPointsInterface : InterfaceDef
joinPointsInterface = MkInterfaceDef
  { name = "JoinPointsOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject "::mlir::Region *" "getTarget" [param "::mlir::BlockArgument" "token"]
          EveryImplementer "the join region `token` designates; null when it is no token of this op"
      , MkMethod PerObject "::mlir::Block::BlockArgListType" "getTokens"
          [param "::mlir::Region &" "region"] EveryImplementer
          "the tokens `region` begins with, one per join region; none in an idr.join's join region"
      , MkMethod PerObject "::mlir::Block::BlockArgListType" "getParameters"
          [param "::mlir::Region &" "region"] EveryImplementer
          "a region's parameters: its arguments after its tokens; the body takes none" ]
  , verifier = Unverified
  , doc = brief "an op of join points: regions entered by jumps through tokens"
  }

||| The carrier of the family's constant, specialized per member.
export
family : TokenScope -> Specialized
family scope = MkSpecialized "JoinPointsFamily"
  [("tokens", EnumConstant (MkCaseRef tokenScopeEnum (memberCase scope)))]

||| What the members declare of upstream's control-flow interface: their
||| successors, what enters each region, how often each runs, what enters
||| a join region read off its token's uses, and an argument typed in the
||| jump's scope standing for a parameter typed in its region's.
branchMethods : List Ident
branchMethods =
  [ "getSuccessorRegions", "getSuccessorInputs", "getRegionInvocationBounds"
  , "getPredecessors", "areTypesCompatible" ]

||| A member of the family. Its regions repeat exactly when its tokens head
||| every region, so only that member is upstream's loop and may not be
||| speculated.
public export
joinPoints : TokenScope -> Op 1 1 1 2
joinPoints scope = MkOp
  { home = InIdr
  , mnemonic = memberName scope
  , ins = [outers]
  , outs = [results "results" (UpstreamType AnyTypeC)]
  , attrs = [attr "binders" (UpstreamAttr ArrayAttrC)]
  , regions = [sized "body" 1, sizedRegions "join_regions" 1]
  , traits = [PropagateControlFlowBreak, TokenProducer, HasNestedTerminator ("jump" ::: [])]
  , interfaces = interfacesOf scope
  , effects = Executes [] [] Recursive Untouched
  , speculation = speculationOf scope
  , stages = Always
  , meaning = NoFold
  , verify = VerifiesRegions
  , format = HandFormat
  , builders = []
  , defaultBuilders = WithDefaults
  , members = bindingMembers
  , guards = []
  , specializations = [family scope]
  , laws = []
  , doc = docOf scope
  }
  where
    common : List InterfaceUse
    common =
      [ Declares RegionBranch branchMethods
      , Declares HasBreakingControlFlow []
      , Implements joinPointsInterface ["getTarget", "getTokens", "getParameters"]
      , Implements erasedBinderInterface ["getBoundSorts"]
      , Implements statesLifetime ["getStatedLifetime", "setStatedLifetime"]
      , Implements statesOuters [] ]

    interfacesOf : TokenScope -> List InterfaceUse
    interfacesOf InBody = common
    interfacesOf InEveryRegion = common ++ [Declares LoopLike ["getLoopRegions"]]

    speculationOf : TokenScope -> Speculation
    speculationOf InBody = RecursivelySpeculatable
    speculationOf InEveryRegion = NotSpeculatable

    docOf : TokenScope -> Doc
    docOf InBody = MkDoc "join points that never repeat: tokens in the body alone"
      """
      `%r = idr.join tokens(%k) in (%l : !L) -> (R) {...} join(%p: A) {...}`,
      `in (%l : !L)` the lifetimes it states, one per scoped value it makes. The
      body's tokens designate the join regions; a join region binds its
      parameters and may jump to an enclosing op's join points, never to its
      own.
      """
    docOf InEveryRegion = MkDoc "a recursive group of join points: tokens at the head of every region"
      """
      `%r = idr.loop tokens(%k) -> (R) {...} join tokens(%s)(%p: A) {...}`.
      Every region begins with the same tokens, so a join region may jump to
      itself or a sibling.
      """

||| The family's members, from the list of its constants.
public export
joinPointOps : List AnyOp
joinPointOps = map (\scope => SomeOp (joinPoints scope)) [InBody, InEveryRegion]

------------------------------------------------------------------------------
-- The jump
------------------------------------------------------------------------------

||| `idr.jump %t <terms> (%a: T, ...)`: control leaves for the join region
||| its token designates, its arguments that region's parameters, its terms
||| that region's erased binders. Every op it crosses lets it through, which
||| its verifier reads off each op's trait. It declares no effect: it only
||| transfers control, and upstream's dead-code rule reads an exit that
||| leaves a region as no dead op. A jump carries no tail fact: tail
||| position is the precondition of forming one.
public export
jumpOp : Op 2 0 1 0
jumpOp = MkOp
  { home = InIdr
  , mnemonic = "jump"
  , ins = [single "target" (UpstreamType TokenC), variadic "args" (UpstreamType AnyTypeC)]
  , outs = []
  , attrs = [MkAttr "terms" indexArgs]
  , regions = []
  , traits = [Terminator, TokenConsumer]
  , interfaces =
      [ Declares RegionBranchTerminator ["getMutableSuccessorOperands"]
      , Declares RegionExitTerminator ["getPotentialTargets"]
      , Implements scopeRuleInterface ["verifyScopeRule"] ]
  , effects = noEffects
  , speculation = NotSpeculatable
  , stages = Always
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0)
      , OptionalGroup [Lit "<"] (ValueOf (AttrRef 0)) [Lit ">"]
      , OptionalGroup [Lit "("] (ValueOf (OperandRef 1))
          [Lit ":", TypeOf (OfGroup (OperandRef 1)), Lit ")"]
      , AttrDict ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "jumps to the join region a token designates, passing its parameters"
  }
