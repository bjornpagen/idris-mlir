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

// Region i < cases.size() is the case cases[i]; one more region is the default.
class Idr_MatchOpBase<string mnemonic, list<Trait> traits = []>
    : Idr_Op<mnemonic, !listconcat(traits, [RecursiveMemoryEffects,
        RecursivelySpeculatable, SingleBlock,
        DeclareOpInterfaceMethods<RegionBranchOpInterface,
            ["getEntrySuccessorRegions", "getRegionInvocationBounds",
             "getSuccessorInputs"]>])> {
  let results = (outs Variadic<AnyType>:$results);
  let regions = (region VariadicRegion<SizedRegion<1>>:$regions);
  let hasCustomAssemblyFormat = 1;
  let hasVerifier = 1;
  let hasRegionVerifier = 1;
  let hasCanonicalizer = 1;
  code matchClassDeclaration = [{
    // The region of case `index`, and the default region, if any.
    ::mlir::Region &getCaseRegion(unsigned index) { return getRegions()[index]; }
    ::mlir::Region *getDefaultRegion() {
      return getRegions().size() > getCases().size() ? &getRegions().back() : nullptr;
    }
    // The region that runs when the scrutinee is the constant `value` (or,
    // for idr.match, when it is built by an idr.con), or null if unknown.
    ::mlir::Region *getTakenRegion(::mlir::Attribute value);
  }];
  let extraClassDeclaration = matchClassDeclaration;
}

// A case's arguments are named by the pattern variables' locations, else
// f0, f1, ... by position. A case names a constructor within the
// scrutinee's data type, whose body the verifier reads.
def Idr_MatchOp : Idr_MatchOpBase<"match", [
    DeclareOpInterfaceMethods<OpAsmOpInterface, ["getAsmBlockArgumentNames"]>]> {
  let summary = "branches on the constructor of a sum or box, taking it apart at its grade";
  let description = [{
    The scrutinee is taken at its grade: a linear one is used by the match,
    and each case binds the constructor's fields at the product of the
    scrutinee's quantity and the field's, as Idris binds pattern variables.
    The default region binds nothing, or takes a scrutinee no case took
    apart back at its type.
  }];
  let arguments = (ins Idr_SumView:$scrutinee, ArrayAttr:$cases);
  let extraClassDeclaration = matchClassDeclaration # [{
    // The data type of the scrutinee, and the tag of the constructor case
    // `index` names.
    ::idr::DataType getDataType();
    unsigned getCaseTag(unsigned index);
  }];
}

// A condition (i1) too: idr-rc makes a select of counted values a match
// on its condition, so that each branch consumes what it yields.
def Idr_MatchLitOp : Idr_MatchOpBase<"match_lit"> {
  let summary = "branches on the value of a condition, integer, string, big or natural";
  let arguments = (ins AnyTypeOf<[I1, Idr_Int, Idr_StrType, Idr_BigType,
                                  Idr_NatType]>:$scrutinee,
                       ArrayAttr:$cases);
}

// A match branches into its regions, and the yield goes on to the match's
// results.
def Idr_YieldOp : Idr_Op<"yield", [Idr_ConsumesOnly<"0">, ReturnLike, Terminator,
    ParentOneOf<["MatchOp", "MatchLitOp"]>,
    DeclareOpInterfaceMethods<RegionBranchTerminatorOpInterface,
        ["getMutableSuccessorOperands", "getSuccessorRegions"]>]> {
  let summary = "ends a region of a match with its results";
  let arguments = (ins Variadic<AnyType>:$results);
  let assemblyFormat = "attr-dict ($results^ `:` type($results))?";
}

#endif // IDR_MATCH_OPS
