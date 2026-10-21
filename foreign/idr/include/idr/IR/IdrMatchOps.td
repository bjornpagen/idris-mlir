// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The matches of the idr dialect: on a constructor and on a literal.

#ifndef IDR_MATCH_OPS
#define IDR_MATCH_OPS

include "idr/IR/IdrAttrs.td"
include "idr/IR/IdrInterfaces.td"

//===----------------------------------------------------------------------===//
// Matches
//===----------------------------------------------------------------------===//

// A match's regions are scf.index_switch's: the default first, region 0,
// then a region per key, case `i` in region `i + 1`, since ODS takes a list
// of regions only last. `defaultConstraint` says whether the default may be
// empty. A default that runs binds the scrutinee back at its type, a fresh
// binding the match declares as no successor input: upstream's region
// patterns, which the hooks add, would otherwise put the scrutinee in its
// place, a second use of a linear scrutinee the match used, or erase an
// unused one together with the scrutinee. Control enters one region that
// is not empty, the one a known scrutinee takes or any, and each returns to
// the match.
class Idr_MatchOpBase<string mnemonic, Region defaultConstraint, list<Trait> traits = []>
    : Idr_Op<mnemonic, !listconcat(traits, [RecursiveMemoryEffects,
        RecursivelySpeculatable, SingleBlock, Idr_MatchOpInterface, Idr_Decides,
        DeclareOpInterfaceMethods<RegionBranchOpInterface,
            ["getEntrySuccessorRegions", "getRegionInvocationBounds",
             "getSuccessorInputs"]>])> {
  let results = (outs Variadic<AnyType>:$results);
  let regions = (region defaultConstraint:$defaultRegion,
                        VariadicRegion<SizedRegion<1>>:$caseRegions);
  let skipDefaultBuilders = 1;
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
  let hasCanonicalizer = 1;
  code matchClassDeclaration = [{
    unsigned getNumCases() { return getCaseRegions().size(); }
    ::mlir::Region &getCaseRegion(unsigned index) { return getCaseRegions()[index]; }
    // The case `region` is the region of: the default is region 0.
    unsigned caseOf(::mlir::Region &region) {
      assert(region.getParentOp() == getOperation() && &region != &getDefaultRegion() &&
             "caseOf asks for a case region of this match");
      return region.getRegionNumber() - 1;
    }
    std::optional<::idr::Tag> knownTag(::mlir::Region &region);
    ::mlir::Operation *rebuild(::mlir::RewriterBase &rewriter, ::mlir::TypeRange results,
                               ::llvm::ArrayRef<unsigned> keptCases,
                               ::mlir::Region *defaultRegion);

  private:
    // The region that runs when the scrutinee is the constant `value` (or,
    // for idr.match, when it is built by an idr.con), or what an enclosing
    // match on the same value leaves it; null if unknown. An empty default
    // never runs, and is never the answer.
    ::mlir::Region *getTakenRegion(::mlir::Attribute value);

  public:
  }];
  let extraClassDeclaration = matchClassDeclaration;
  let extraClassDefinition = [{
    void $cppClass::getSuccessorRegions(::mlir::RegionBranchPoint point,
        ::llvm::SmallVectorImpl<::mlir::RegionSuccessor> &successors) {
      if (!point.isParent()) {
        successors.push_back(::mlir::RegionSuccessor(getOperation()));
        return;
      }
      for (::mlir::Region &region : getOperation()->getRegions())
        if (!region.empty())
          successors.emplace_back(&region);
    }

    void $cppClass::getEntrySuccessorRegions(::llvm::ArrayRef<::mlir::Attribute> operands,
        ::llvm::SmallVectorImpl<::mlir::RegionSuccessor> &successors) {
      if (::mlir::Region *taken = getTakenRegion(operands.front()))
        successors.emplace_back(taken);
      else
        getSuccessorRegions(::mlir::RegionBranchPoint::parent(), successors);
    }

    // At most once each region that is not empty, and none but the taken
    // one when it is known.
    void $cppClass::getRegionInvocationBounds(::llvm::ArrayRef<::mlir::Attribute> operands,
        ::llvm::SmallVectorImpl<::mlir::InvocationBounds> &bounds) {
      ::mlir::Region *taken = getTakenRegion(operands.front());
      for (::mlir::Region &region : getOperation()->getRegions())
        bounds.emplace_back(/*lb=*/0,
                            /*ub=*/!region.empty() && (!taken || taken == &region) ? 1 : 0);
    }

    ::mlir::ValueRange $cppClass::getSuccessorInputs(::mlir::RegionSuccessor successor) {
      return successor.isOperation() ? ::mlir::ValueRange(getResults()) : ::mlir::ValueRange();
    }
  }];
}

// A case's arguments are named by the pattern variables' locations, else
// f0, f1, ... by position. A case is a constructor's tag in the
// scrutinee's data type, whose body the verifier reads, written by name.
def Idr_MatchOp : Idr_MatchOpBase<"match", MaxSizedRegion<1>, [
    DeclareOpInterfaceMethods<MemoryEffectsOpInterface>,
    DeclareOpInterfaceMethods<Idr_FlowOpInterface>,
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmBlockArgumentNames"]>]> {
  let summary = "branches on the constructor of a sum or box, taking it apart at its grade";
  let description = [{
    The scrutinee is taken at its grade: a linear one is used by the match,
    and each case binds the constructor's fields at the product of the
    scrutinee's quantity and the field's, as Idris binds pattern variables.
    The default region is empty when the cases are exhaustive; otherwise it
    binds the scrutinee back at its type, the one use of a linear scrutinee
    no case took apart.

    `%r = idr.match %v : !T -> (i64) { case @A(%x: i64) {...} default(%d: !T) {...} }`
  }];
  let arguments = (ins Idr_SumView:$scrutinee, Idr_TagArray:$cases);
  let builders = [
    // A match on `scrutinee` with an empty region per tag of `tags` and an
    // empty default, which a match whose default runs gives its block.
    OpBuilder<(ins "::mlir::TypeRange":$results, "::mlir::Value":$scrutinee,
                   "::llvm::ArrayRef<::idr::Tag>":$tags)>
  ];
  let assemblyFormat = [{
    $scrutinee `:` type($scrutinee) `->` custom<ResultTypes>(type($results))
    attr-dict-with-keyword ` ` `{`
    custom<MatchCases>(ref(type($scrutinee)), $cases, $caseRegions) ``
    custom<DefaultCase>($defaultRegion) `\n` `` `}`
  }];
  let extraClassDeclaration = matchClassDeclaration # [{
    // The data type of the scrutinee, and the tag case `index` takes.
    ::idr::DataType getDataType();
    ::idr::Tag getCaseTag(unsigned index) {
      return ::idr::Tag{static_cast<uint32_t>(getCases()[index])};
    }
  }];
}

// A condition (i1) too: idr-rc makes a select of counted values a match
// on its condition, so that each branch consumes what it yields. The keys
// are literals of the scrutinee's type, which says what one is; no set of
// literals is exhaustive, so the default is required.
def Idr_MatchLitOp : Idr_MatchOpBase<"match_lit", SizedRegion<1>> {
  let summary = "branches on the value of a scalar, string, big or natural";
  let arguments = (ins Idr_Read<"::idr::LiteralTypeInterface",
                                "a value of a type with literals, read in place">:$scrutinee,
                       ArrayAttr:$cases);
  let builders = [
    // A match on `scrutinee` with an empty region per key of `cases` and an
    // empty default, which the caller gives its block.
    OpBuilder<(ins "::mlir::TypeRange":$results, "::mlir::Value":$scrutinee,
                   "::mlir::ArrayAttr":$cases)>
  ];
  let assemblyFormat = [{
    $scrutinee `:` type($scrutinee) `->` custom<ResultTypes>(type($results))
    attr-dict-with-keyword ` ` `{`
    custom<LiteralCases>(ref(type($scrutinee)), $cases, $caseRegions) ``
    custom<DefaultCase>($defaultRegion) `\n` `` `}`
  }];
}

// A match branches into its regions, and the yield goes on to the match's
// results.
def Idr_YieldOp : Idr_Op<"yield", [Idr_ConsumesOnly, ReturnLike, Terminator,
    ParentOneOf<["MatchOp", "MatchLitOp"]>,
    DeclareOpInterfaceMethods<RegionBranchTerminatorOpInterface,
        ["getMutableSuccessorOperands", "getSuccessorRegions"]>]> {
  let summary = "ends a region of a match with its results";
  let arguments = (ins Variadic<AnyType>:$results);
  let assemblyFormat = "attr-dict ($results^ `:` type($results))?";
}

#endif // IDR_MATCH_OPS
