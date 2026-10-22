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
||| `idr.lit.match`'s scrutinee is a word (an integer of any width, a char),
||| a double, a string, a big integer or a natural, read in place, its keys
||| literals of its type: a case binds nothing, since in it the scrutinee
||| equals its literal (a double's zero key is taken by either zero), and the
||| default binds the scrutinee refined to the complement of the keys, at the
||| scrutinee's type, as a data match's default does. It stays a literal
||| match until the lowering, since no upstream op keeps that refinement or
||| the lifetimes the match states; a condition is chosen on by upstream's
||| `scf.if`.
|||
||| Each scoped value a match makes lives in the lifetime its own entry of
||| `outers` states, one hop from the value, as every op that makes a scoped
||| value states it: its scoped results, in result order, then each scoped
||| position its regions bind, one entry for every region that binds it,
||| since each binds a position at the same hold. Two values of two
||| lifetimes keep each its own span.
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

||| A value of a type with literals, at any grade, read in place: a word, a
||| double, a string, a big integer or a natural; never a condition.
export
matchedLiteral : Predicate
matchedLiteral = MkPredicate "isMatchedLiteral" OnType
  (brief "a value of a type with literals that is no condition, read in place")

||| The lifetimes a control op states, one per scoped value it makes: its
||| scoped results, in result order, then the scoped values its regions
||| bind, in the order its kind says.
-- Public, as other modules' ops check its name at compile time.
public export
outers : Operand
outers = variadic "outers" (OurType (SomeType lifetimeType))

||| What the scoped values a control op's regions bind take of its
||| `outers`, after its scoped results' entries: how many entries, and the
||| entry of one such value counted from the first, whether or not the value
||| is scoped yet; none for a value no region of the op binds. A match's
||| entries are its regions' argument positions, a position scoped where
||| some region's argument at it is; a join point's op's are every
||| argument of every region, in region and argument order.
export
bindingMembers : List Member
bindingMembers =
  [ MkMember OnObject "unsigned" "getScopedBindings" []
  , MkMember OnObject "std::optional<unsigned>" "getBindingEntry" [param "::mlir::Value" "made"] ]

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
||| and no flow declaration of ours is needed. Taking the scrutinee apart
||| is all it does with it, so a chain of single uses ends at it.
public export
matchOp : Op 3 1 1 2
matchOp = MkOp
  { home = InIdr
  , mnemonic = "data.match"
  , ins = [ single "scrutinee" (SatisfiesType matchable)
          , variadic "forwarded" (UpstreamType AnyTypeC)
          , outers ]
  , outs = [results "results" (UpstreamType AnyTypeC)]
  , attrs = [attr "cases" (UpstreamAttr DenseI32ArrayAttrC)]
  , regions = [MkRegion "default_region" OneRegion (AtMost 1), sizedRegions "case_regions" 1]
  , traits = [SingleBlock, PropagateControlFlowBreak, OurTrait eliminatesOperand]
  , interfaces =
      [ Declares RegionBranch
          (branchMethods ++ ["getEntrySuccessorOperands", "areTypesCompatible"])
      , Implements matchInterface ["getNumCases", "getCaseRegion", "caseOf", "keepCases"]
      , Implements erasedBinderInterface ["getBoundSorts", "getRefinement"]
      , Implements statesLifetime ["getStatedLifetime", "setStatedLifetime"]
      , Implements statesOuters [] ]
  , effects = Executes [] [ReadsMemo 0] Recursive Untouched
  , speculation = RecursivelySpeculatable
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0)
      , OptionalGroup [Lit "forward", Lit "("] (ValueOf (OperandRef 1))
          [Lit ":", TypeOf (OfGroup (OperandRef 1)), Lit ")"]
      , OptionalGroup [Lit "in", Lit "("] (ValueOf (OperandRef 2))
          [Lit ":", TypeOf (OfGroup (OperandRef 2)), Lit ")"]
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
      ++ bindingMembers
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "branches on the constructor of a data value, binding it refined in each case"
      """
      The scrutinee is taken at its grade: a linear one is used by the match,
      and each region that runs binds it refined, first, then each forwarded
      value at its refined type. A case's fields are reads of its refined
      value. The default region is empty when the cases are exhaustive.

      `%r = idr.data.match %v : !T -> (i64) { case @A(%a: !A) {...} default(%d: !D) {...} }`,
      with `in (%l : !L)` before the colon the lifetimes it states, one per
      scoped value it makes.
      """
  }

||| `idr.lit.match`: a literal key per case and a default always, since no
||| set of literals is exhaustive. The scrutinee enters the default, which
||| binds it refined to the complement of the keys at its own type (a natural
||| 0-versus-successor match computes `nat.pred` from it); the range
||| analysis gives that binding the scrutinee's range with the keys cut from
||| its ends. A case binds nothing.
public export
matchLitOp : Op 2 1 1 2
matchLitOp = MkOp
  { home = InIdr
  , mnemonic = "lit.match"
  , ins = [single "scrutinee" (SatisfiesType matchedLiteral), outers]
  , outs = [results "results" (UpstreamType AnyTypeC)]
  , attrs = [attr "cases" (UpstreamAttr ArrayAttrC)]
  , regions = [sized "default_region" 1, sizedRegions "case_regions" 1]
  , traits = [SingleBlock, PropagateControlFlowBreak]
  , interfaces =
      [ Declares RegionBranch (branchMethods ++ ["getEntrySuccessorOperands"])
      , Implements matchInterface ["getNumCases", "getCaseRegion", "caseOf", "keepCases"]
      , Implements statesLifetime ["getStatedLifetime", "setStatedLifetime"]
      , Implements statesOuters [] ]
  , effects = Executes [] [] Recursive Untouched
  , speculation = RecursivelySpeculatable
  , stages = between Higher Owned
  , meaning = NoFold
  , verify = VerifiesOp
  , format = Declared
      [ ValueOf (OperandRef 0)
      , OptionalGroup [Lit "in", Lit "("] (ValueOf (OperandRef 1))
          [Lit ":", TypeOf (OfGroup (OperandRef 1)), Lit ")"]
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
  , members = bindingMembers
  , guards = []
  , specializations = []
  , laws = []
  , doc = MkDoc "branches on the value of a word, a double, a string, a big integer or a natural"
      """
      The scrutinee is read in place; each case is one literal of its type,
      and in that case the scrutinee equals that literal (a double's zero is
      taken by either zero). The default binds the scrutinee, which there is
      none of the keys.

      `%r = idr.lit.match %s : !idr.str -> (i64) { case "" {...} default(%t: !idr.str) {...} }`
      `%r = idr.lit.match %c : i32 -> (i64) { case 97 {...} default(%d: i32) {...} }`
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
public export
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

------------------------------------------------------------------------------
-- The upstream ops a condition is chosen with, and the lowering's switch
------------------------------------------------------------------------------

-- Upstream's records hold these ops' meanings and effects, which the
-- specification never restates. Each stands from the frontend's program to
-- the lowering, whose one conversion makes their regions blocks with
-- upstream's scf patterns, so none is left in a lowered function.

||| `scf.if`: a region per arm of a condition, rejoining at its results, as
||| a match's cases do. The frontend writes it where the choice is a
||| condition and no Idris value is matched (an array joined of two whose
||| elements hold references reads one or the other at each coordinate),
||| and passes write it for choices of their own. Its effects are its
||| regions' ops' (`RecursiveMemoryEffects`), as a match's are, which the
||| effect system reads through upstream's interface as it reads every op
||| it does not declare; what it forwards from a yield to its results, a
||| reference among it, the flow readers read from its region branch
||| interface.
export
scfIf : Admitted
scfIf = MkAdmitted SCF "IfOp" "SCF_IfOp" (between Higher Owned) FrontendWrites [] [] Nothing UpstreamFold

||| `scf.index_switch`: a region per case of an index, and a default region,
||| rejoining at its results. Only the lowering writes it, from a data
||| match's tag and from a literal match on a word, in the step that makes
||| every region blocks: it keeps neither the refined scrutinee a match's
||| default binds nor the lifetimes a match states, so nothing before the
||| lowering may hold it. Like `scf.if`, its effects are its regions' ops',
||| its forwarding is its region branch interface's, and a case may jump to
||| an enclosing join point or never end, which upstream's early exit lets
||| through.
export
scfIndexSwitch : Admitted
scfIndexSwitch =
  MkAdmitted SCF "IndexSwitchOp" "SCF_IndexSwitchOp" (between Owned Owned) PassesOnly
    [] [] Nothing UpstreamFold

||| `scf.yield`: ends a region of `scf.if` or `scf.index_switch`, and of the
||| scf loops passes write, with what it gives the op's results. Upstream
||| declares it pure, as `idr.yield` declares no effect: passing a value out
||| of a region hands its ownership on, which is no consumption.
export
scfYield : Admitted
scfYield = MkAdmitted SCF "YieldOp" "SCF_YieldOp" (between Higher Owned) FrontendWrites [] [] Nothing UpstreamFold

||| Every upstream op control flow admits, once: those the frontend writes,
||| and the switch only the lowering writes.
export
controlAdmitted : List Admitted
controlAdmitted = [scfIf, scfIndexSwitch, scfYield]
