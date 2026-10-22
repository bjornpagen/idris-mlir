-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The matches, from the frontend to the lowering: a region per case,
||| rejoining at the op's results. Each region ends by yielding those
||| results, by jumping to an enclosing join point, which the match lets
||| through (upstream's early exit), or by never ending.
|||
||| A case of `idr.data.match` binds the scrutinee refined to its
||| constructor, and the default binds it refined to the constructors no case
||| holds, which the op's own verifier holds each region to, so a field is a
||| total read of the refined value and a case that binds a constructor it
||| does not test cannot be written. The values whose types mention an index
||| the case refines are forwarded into it beside the scrutinee, the same
||| values at their refined types. The equation a case assumes is the op's
||| answer through the binder interface, which the function's scope walk
||| reads as it enters the region and unifies with every enclosing one, so
||| no op walks its ancestors.
|||
||| `idr.lit.match`'s scrutinee is a string, a big integer or a natural,
||| read in place: a case binds nothing, since in it the scrutinee is its
||| literal, and the default binds the scrutinee refined to the complement of
||| the keys, at the scrutinee's type, as a data match's default does; an
||| integer or a condition is matched by upstream's `scf.index_switch` or
||| `scf.if`.
|||
||| A scoped value a match makes (a result, a refined value it binds) lives
||| in the lifetime its `outer` operand states, present exactly when one is
||| scoped: one hop from the value, as every op that makes a scoped value
||| states it.
module IdrisMLIR.Spec.Control.Matches

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Families.Dialect
import IdrisMLIR.Spec.Lifetimes.Declarations

import Data.Fin
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- What the matches' operands are
------------------------------------------------------------------------------

||| A value of a data type, at any grade: what `idr.data.match` takes apart.
export
matchable : Predicate
matchable = MkPredicate "isMatchable" OnType
  (brief "a value of a data type, at any grade")

||| A value of a type with literals that no upstream op matches: a string,
||| a big integer, a natural, at any grade, read in place.
export
matchedLiteral : Predicate
matchedLiteral = MkPredicate "isMatchedLiteral" OnType
  (brief "a value of a type with literals that is no integer, read in place")

||| The lifetime a match states for the scoped values it makes.
lifetime : TypeC
lifetime = OurType (SomeType lifetimeType)

------------------------------------------------------------------------------
-- Their shape, shared
------------------------------------------------------------------------------

||| `MatchOpInterface`: a match, its scrutinee, a region per case and a
||| default, read alike for both matches by the passes that take a match
||| apart (placement, the tail passes, frames) and by the rules that drop
||| cases. The default is region 0, so a case's index is its region's number
||| less one.
export
matchInterface : InterfaceDef
matchInterface = MkInterfaceDef
  { name = "MatchOpInterface"
  , subject = OverOps
  , bases = []
  , methods =
      [ MkMethod PerObject "::mlir::Value" "getScrutinee" [] EveryImplementer
          "the value the match takes apart, or reads"
      , MkMethod PerObject "unsigned" "getNumCases" [] EveryImplementer
          "the number of its cases"
      , MkMethod PerObject "::mlir::Region &" "getCaseRegion" [param "unsigned" "index"]
          EveryImplementer "the region of case `index`"
      , MkMethod PerObject "::mlir::Region &" "getDefaultRegion" [] EveryImplementer
          "the default region: empty when an idr.data.match's cases are exhaustive"
      , MkMethod PerObject "unsigned" "caseOf" [param "::mlir::Region &" "region"]
          EveryImplementer "the case `region` is, a case region of this match"
      , MkMethod PerObject "::mlir::Operation *" "keepCases"
          [ param "::mlir::RewriterBase &" "rewriter", param "::llvm::ArrayRef<unsigned>" "kept"
          , param "::mlir::Region *" "fallback" ]
          EveryImplementer
          "this match replaced by one of the cases `kept` alone, `fallback` its default (none: an exhaustive idr.data.match), a case region that reads none of its arguments binding the default's" ]
  , verifier = Unverified
  , doc = brief "a match: a region per case of its scrutinee, and a default"
  }

------------------------------------------------------------------------------
-- The custom directives
------------------------------------------------------------------------------

||| `(R, ...)`: the results' types, none among them.
export
resultTypes : Directive
resultTypes = MkDirective "ResultTypes" [VariadicTypeArg]
  (brief "the results' types in parentheses, none among them")

||| `case @C(%c: !Refined, %v: !Forwarded, ...) {...}` per case, the
||| constructor written by its label in the scrutinee's family.
export
matchCases : Directive
matchCases = MkDirective "MatchCases"
  [RefTypeArg, AttrArg "::mlir::DenseI32ArrayAttr", VariadicRegionArg]
  (brief "each case: its constructor and the refined values its region binds")

||| `case <literal> {...}` per key, a literal of the scrutinee's type.
export
literalCases : Directive
literalCases = MkDirective "LiteralCases"
  [RefTypeArg, AttrArg "::mlir::ArrayAttr", VariadicRegionArg]
  (brief "each case: its literal and its region")

||| `default(%d: !Refined, ...) {...}`, or nothing for an exhaustive data
||| match's empty default.
export
defaultCase : Directive
defaultCase = MkDirective "DefaultCase" [RegionArg]
  (brief "the default and what it binds, when it runs")

------------------------------------------------------------------------------
-- The ops
------------------------------------------------------------------------------

||| What both matches declare of upstream's control-flow interface: their
||| successors, the regions a known key takes, the regions' bounds, and
||| what enters each region.
branchMethods : List Ident
branchMethods =
  [ "getSuccessorRegions", "getEntrySuccessorRegions", "getRegionInvocationBounds"
  , "getSuccessorInputs" ]

||| `idr.data.match`: the scrutinee and the forwarded values enter every
||| region refined, which upstream's interface reads as the region's entry
||| operands, so its dataflow sees each refined value equal to its source
||| and no flow declaration of ours is needed.
export
matchOp : Op 3 1 1 2
matchOp = MkOp
  { home = InIdr
  , mnemonic = "data.match"
  , ins = [ single "scrutinee" (SatisfiesType matchable)
          , variadic "forwarded" (UpstreamType AnyTypeC)
          , optional "outer" lifetime ]
  , outs = [results "results" (UpstreamType AnyTypeC)]
  , attrs = [attr "cases" (UpstreamAttr DenseI32ArrayAttrC)]
  , regions = [MkRegion "default_region" OneRegion (AtMost 1), sizedRegions "case_regions" 1]
  , traits = [SingleBlock, PropagateControlFlowBreak, AttrSizedOperandSegments]
  , interfaces =
      [ Declares RegionBranch
          (branchMethods ++ ["getEntrySuccessorOperands", "areTypesCompatible"])
      , Implements matchInterface ["getNumCases", "getCaseRegion", "caseOf", "keepCases"]
      , Implements erasedBinderInterface ["getBoundSorts", "getRefinement"]
      , Implements statesLifetime ["getStatedLifetime", "setStatedLifetime"] ]
  , effects = Executes [] [ReadsMemo 0] Recursive Untouched
  , speculation = RecursivelySpeculatable
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0)
      , OptionalGroup [Lit "forward", Lit "("] (ValueOf (OperandRef 1))
          [Lit ":", TypeOf (OfGroup (OperandRef 1)), Lit ")"]
      , OptionalGroup [Lit "in"] (ValueOf (OperandRef 2)) []
      , Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->"
      , Custom resultTypes [TypeOfGroup (ResultRef 0)]
      , AttrDictWithKeyword, Lit "{"
      , Custom matchCases [TypeAgain (OperandRef 0), Group (AttrRef 0), Group (RegionRef 1)]
      , Custom defaultCase [Group (RegionRef 0)]
      , Lit "}" ]
  , builders =
      [ MkBuilder [ param "::mlir::TypeRange" "results", param "::mlir::Value" "scrutinee"
                  , param "::mlir::ValueRange" "forwarded"
                  , param "::llvm::ArrayRef<::idr::Tag>" "tags" ] ]
  , defaultBuilders = DeclaredOnly
  , members =
      [ MkMember OnObject "::mlir::BlockArgument" "getRefined" [param "::mlir::Region &" "region"]
      , MkMember OnObject "::idr::Tag" "getCaseTag" [param "unsigned" "index"]
      , MkMember OnObject "::idr::DataType" "getDataType" []
      , MkMember OnObject "::mlir::OperandRange" "getEntering" []
      , MkMember OnObject "::llvm::SmallVector<::mlir::Type>" "getDefaultTypes" [] ]
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "branches on the constructor of a data value, binding it refined in each case"
      """
      The scrutinee is taken at its grade: a linear one is used by the match,
      and each region that runs binds it refined, first, then each forwarded
      value at its refined type. A case's fields are reads of its refined
      value. The default region is empty when the cases are exhaustive.

      `%r = idr.data.match %v : !T -> (i64) { case @A(%a: !A) {...} default(%d: !D) {...} }`
      """
  }

||| `idr.lit.match`: a literal key per case and a default always, since no
||| set of literals is exhaustive. The scrutinee enters the default, which
||| binds it refined to the complement of the keys at its own type (a natural
||| 0-versus-successor match computes `nat.pred` from it); a case binds
||| nothing.
export
matchLitOp : Op 2 1 1 2
matchLitOp = MkOp
  { home = InIdr
  , mnemonic = "lit.match"
  , ins = [single "scrutinee" (SatisfiesType matchedLiteral), optional "outer" lifetime]
  , outs = [results "results" (UpstreamType AnyTypeC)]
  , attrs = [attr "cases" (UpstreamAttr ArrayAttrC)]
  , regions = [sized "default_region" 1, sizedRegions "case_regions" 1]
  , traits = [SingleBlock, PropagateControlFlowBreak]
  , interfaces =
      [ Declares RegionBranch (branchMethods ++ ["getEntrySuccessorOperands"])
      , Implements matchInterface ["getNumCases", "getCaseRegion", "caseOf", "keepCases"]
      , Implements statesLifetime ["getStatedLifetime", "setStatedLifetime"] ]
  , effects = Executes [] [] Recursive Untouched
  , speculation = RecursivelySpeculatable
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0)
      , OptionalGroup [Lit "in"] (ValueOf (OperandRef 1)) []
      , Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->"
      , Custom resultTypes [TypeOfGroup (ResultRef 0)]
      , AttrDictWithKeyword, Lit "{"
      , Custom literalCases [TypeAgain (OperandRef 0), Group (AttrRef 0), Group (RegionRef 1)]
      , Custom defaultCase [Group (RegionRef 0)]
      , Lit "}" ]
  , builders =
      [ MkBuilder [ param "::mlir::TypeRange" "results", param "::mlir::Value" "scrutinee"
                  , param "::mlir::ArrayAttr" "cases" ] ]
  , defaultBuilders = DeclaredOnly
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "branches on the value of a string, a big integer or a natural"
      """
      The scrutinee is read in place; each case is one literal of its type,
      and in that case the scrutinee is that literal. The default binds the
      scrutinee, which there is none of the keys.

      `%r = idr.lit.match %s : !idr.str -> (i64) { case "" {...} default(%t: !idr.str) {...} }`
      """
  }

||| `idr.yield`: ends a region of an op that rejoins at its results (a
||| match, a join point's op, a region run once, a region in which an erased
||| equality holds, the test of sharing, a trusted library's IO action run
||| for a value) with the op's results; and the region of an answer's slot
||| with nothing, since that op's result is what the region wrote through
||| its destination. It declares no effect: passing a value out of a region
||| hands its ownership on, which is no consumption. A join point's yields
||| stand until the last step of the lowering, after the program is lowered.
export
yieldOp : Op 1 0 0 0
yieldOp = MkOp
  { home = InIdr
  , mnemonic = "yield"
  , ins = [variadic "results" (UpstreamType AnyTypeC)]
  , outs = []
  , attrs = []
  , regions = []
  , traits = [ Terminator, ReturnLike
             , HasParent ("data.match" ::: [ "lit.match", "join", "loop"
                                           , "lifetime", "lifetime.home", "lifetime.block"
                                           , "lifetime.stack", "lifetime.chain", "lifetime.unpack"
                                           , "lend", "index.assume", "count.match_unique"
                                           , "io.unsafe_run", "dest.answer" ]) ]
  , interfaces =
      [Declares RegionBranchTerminator ["getMutableSuccessorOperands", "getSuccessorRegions"]]
  , effects = noEffects
  , speculation = AlwaysSpeculatable
  , stages = Always
  , meaning = NoFold
  , verify = DeclarationOnly
  , format = Declared
      [ AttrDict
      , OptionalGroup [] (ValueOf (OperandRef 0)) [Lit ":", TypeOf (OfGroup (OperandRef 0))] ]
  , builders = []
  , defaultBuilders = WithDefaults
  , members = []
  , guards = []
  , specializations = []
  , laws = []
  , doc = brief "ends a region of an op that rejoins after it, with what the region gives its results"
  }
