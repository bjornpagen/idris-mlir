-- SPDX-License-Identifier: 0BSD
-- Copyright (c) 2026 Bjorn Pagen
||| The matches, from the frontend to the lowering: a region per case,
||| rejoining at the op's results. Each region ends by yielding those
||| results, by jumping to an enclosing join point, which the match lets
||| through (upstream's early exit), or by never ending.
|||
||| A case of `idr.match` binds the scrutinee refined to its constructor,
||| and the default binds it refined to the constructors no case holds, so a
||| field is a total read of the refined value and a read of a constructor
||| the value is not cannot be written. The values whose types mention an
||| index the case refines are forwarded into it beside the scrutinee, the
||| same values at their refined types. That each region binds those
||| refinements is the function's scope walk's to check, which keeps every
||| enclosing case's refinement on its stack, so no op walks its ancestors.
|||
||| `idr.match_lit`'s scrutinee is a string, a big integer or a natural,
||| read in place, so its regions bind nothing; an integer or a condition is
||| matched by upstream's `scf.index_switch` or `scf.if`.
module IdrisMLIR.Spec.Control.Matches

import IdrisMLIR.Spec.Core.Vocabulary
import IdrisMLIR.Spec.Effects.Declaration
import IdrisMLIR.Spec.Families.Dialect

import Data.Fin
import Data.List1
import Data.Vect

%default total

------------------------------------------------------------------------------
-- What the matches' operands are
------------------------------------------------------------------------------

||| A value of a data type, at any grade: what `idr.match` takes apart.
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

------------------------------------------------------------------------------
-- Their shape, shared
------------------------------------------------------------------------------

||| `MatchOpInterface`: a match, its scrutinee, a region per case and a
||| default, read alike for both matches by the passes that take a match
||| apart (placement, the tail passes, frames). The default is region 0, so
||| a case's index is its region's number less one.
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
          "the default region: empty when an idr.match's cases are exhaustive"
      , MkMethod PerObject "unsigned" "caseOf" [param "::mlir::Region &" "region"]
          EveryImplementer "the case `region` is, a case region of this match" ]
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

||| `default(%d: !Refined, ...) {...}`, `default {...}`, or nothing for an
||| exhaustive match's empty default.
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

||| `idr.match`: the scrutinee and the forwarded values enter every region
||| refined, which upstream's interface reads as the region's entry
||| operands, so its dataflow sees each refined value equal to its source
||| and no flow declaration of ours is needed.
export
matchOp : Op 2 1 1 2
matchOp = MkOp
  { home = InIdr
  , mnemonic = "match"
  , ins = [ single "scrutinee" (SatisfiesType matchable)
          , variadic "forwarded" (UpstreamType AnyTypeC) ]
  , outs = [results "results" (UpstreamType AnyTypeC)]
  , attrs = [attr "cases" (UpstreamAttr DenseI32ArrayAttrC)]
  , regions = [MkRegion "default_region" OneRegion (AtMost 1), sizedRegions "case_regions" 1]
  , traits = [SingleBlock, PropagateControlFlowBreak]
  , interfaces =
      [ Declares RegionBranch
          (branchMethods ++ ["getEntrySuccessorOperands", "areTypesCompatible"])
      , Implements matchInterface ["getNumCases", "getCaseRegion", "caseOf"]
      , Implements erasedBinderInterface ["getBoundSorts"] ]
  , effects = Executes [] [ReadsMemo 0] Recursive Untouched
  , speculation = RecursivelySpeculatable
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0)
      , OptionalGroup [Lit "forward", Lit "("] (ValueOf (OperandRef 1))
          [Lit ":", TypeOf (OfGroup (OperandRef 1)), Lit ")"]
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
      , MkMember OnObject "::idr::DataType" "getDataType" [] ]
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "branches on the constructor of a data value, binding it refined in each case"
      """
      The scrutinee is taken at its grade: a linear one is used by the match,
      and each region that runs binds it refined, first, then each forwarded
      value at its refined type. A case's fields are reads of its refined
      value. The default region is empty when the cases are exhaustive.

      `%r = idr.match %v : !T -> (i64) { case @A(%a: !A) {...} default(%d: !D) {...} }`
      """
  }

||| `idr.match_lit`: a literal key per case and a default always, since no
||| set of literals is exhaustive; nothing enters a region.
export
matchLitOp : Op 1 1 1 2
matchLitOp = MkOp
  { home = InIdr
  , mnemonic = "match_lit"
  , ins = [single "scrutinee" (SatisfiesType matchedLiteral)]
  , outs = [results "results" (UpstreamType AnyTypeC)]
  , attrs = [attr "cases" (UpstreamAttr ArrayAttrC)]
  , regions = [sized "default_region" 1, sizedRegions "case_regions" 1]
  , traits = [SingleBlock, PropagateControlFlowBreak]
  , interfaces =
      [ Declares RegionBranch branchMethods
      , Implements matchInterface ["getNumCases", "getCaseRegion", "caseOf"] ]
  , effects = Executes [] [] Recursive Untouched
  , speculation = RecursivelySpeculatable
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0), Lit ":", TypeOf (OfGroup (OperandRef 0)), Lit "->"
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
      and in that case the scrutinee is that literal.
      """
  }

||| `idr.yield`: ends a region of a match or of a join point's op with the
||| op's results. It declares no effect: passing a value out of a region
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
             , HasParent ("match" ::: ["match_lit", "join", "loop"]) ]
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
  , doc = brief "ends a region of a match or a join point's op with the op's results"
  }
