// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.data.match, and what both matches take: its rules, its builder, the
// region it takes for a known constructor, the edges upstream's
// control-flow interfaces read off it, what each region knows of its
// scrutinee, the equation each case assumes, and the lifetimes it states
// for the scoped values it makes. What it shares with idr.lit.match is
// idr/IR/Control/MatchFamily.h; idr.lit.match is Control/LiteralMatch.cpp.
//
// A match is a region per case, from the frontend to the lowering. Each
// region of idr.data.match binds the scrutinee refined: a case to its
// constructor, the default to the constructors no case holds, which the
// op's verifier holds each region to, so a field is a total read of that
// refined value and a case that binds a constructor it does not test cannot
// be written. The values whose types mention an index the case refines
// enter it refined too, forwarded beside the scrutinee. The equation a case
// assumes is the op's answer through the binder interface; the function's
// scope walk reads it as it enters the region, with every enclosing one on
// its stack, and holds each refined value to it.

#include "idr/IR/Control/MatchFamily.h"
#include "idr/IR/Control/Stated.h"
#include "idr/IR/Families/Scope.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/RegionKindInterface.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/SmallVectorExtras.h"

using namespace mlir;
using namespace idr;
using namespace idr::control;

namespace {

// The region a known scrutinee takes: a constant constructor; the
// constructor of the idr.data.con that built it, where its state still
// holds at the match (a memo cell's changes); or the one constructor its
// type leaves possible. Else none is known.
Region *takenRegionOf(DataMatchOp op, Attribute value) {
  Value scrutinee = op.getScrutinee();
  const auto &possible = dataTypeOf(scrutinee.getType()).possibleTags();
  if (possible.size() == 1)
    return takenRegion(op, static_cast<int32_t>(possible.front()));
  if (auto con = dyn_cast_or_null<ConAttr>(value))
    return takenRegion(op, static_cast<int32_t>(con.getTag()));
  if (!builtStateHolds(scrutinee, op.getOperation()))
    return nullptr;
  if (auto built = scrutinee.getDefiningOp<DataConOp>())
    return takenRegion(op, static_cast<int32_t>(built.getTag()));
  return nullptr;
}

// Each region's refined scrutinee is refined to at least the constructors
// that reach the region and at most those its key admits: a case's own, the
// default's every one no case holds. So a case that binds a constructor it
// does not test cannot be written, and a region no constructor reaches (its
// constructor one the scrutinee's type excludes) claims nothing false.
LogicalResult verifyRefined(DataMatchOp op) {
  const families::TagSet &possible = op.getDataType().possibleTags();
  auto check = [&](Region &region, auto admits) -> LogicalResult {
    Type bound = region.getArgument(0).getType();
    if (!isMatchable(bound))
      return op.emitOpError("region #")
             << region.getRegionNumber() << " binds " << bound << " for its scrutinee";
    const families::TagSet &claimed = dataTypeOf(bound).possibleTags();
    if (llvm::all_of(claimed, admits) && llvm::all_of(possible, [&](Tag tag) {
          return !admits(tag) || claimed.contains(tag);
        }))
      return success();
    return op.emitOpError("region #")
           << region.getRegionNumber() << " binds its scrutinee as " << bound
           << ", refined to other constructors than those that reach it";
  };
  // The default admits every constructor no case holds; a case, its own.
  Region &fallback = op.getDefaultRegion();
  if (!fallback.empty() && failed(check(fallback, [&](Tag tag) {
        return !llvm::is_contained(op.getCases(), static_cast<int32_t>(tag));
      })))
    return failure();
  for (unsigned i = 0, n = op.getNumCases(); i < n; ++i)
    if (Region &region = op.getCaseRegion(i); !region.empty())
      if (failed(check(region, [key = op.getCaseTag(i)](Tag tag) { return tag == key; })))
        return failure();
  return success();
}

} // namespace

//===----------------------------------------------------------------------===//
// What the matches take
//===----------------------------------------------------------------------===//

// A data value, at any grade: its carrier is a family application.
bool idr::isMatchable(Type type) { return isa<DataType>(unrestricted(type)); }

// A value of a type with literals: a word of any width, a char, a double, a
// string, a big integer or a natural. A condition is chosen on by scf.if,
// never matched.
bool idr::isMatchedLiteral(Type type) {
  Type carrier = unrestricted(type);
  return isa<LiteralTypeInterface>(carrier) && !carrier.isInteger(1);
}

//===----------------------------------------------------------------------===//
// idr.data.match
//===----------------------------------------------------------------------===//

// Each key is a constructor of the scrutinee's family, and every region
// that runs binds the refined scrutinee and each forwarded value, in that
// order, the scrutinee refined to the constructors that reach it, and
// gives the results at their own types.
LogicalResult DataMatchOp::verify() {
  if (failed(verifyKeys(*this)))
    return failure();
  uint32_t declared = getDataType().declaredCount();
  for (int32_t tag : getCases())
    if (tag < 0 || static_cast<uint32_t>(tag) >= declared)
      return emitOpError("has a case for constructor #")
             << tag << ", which its scrutinee's family does not declare";
  size_t bound = 1 + getForwarded().size();
  for (Region &region : getOperation()->getRegions())
    if (!region.empty() && region.getNumArguments() != bound)
      return emitOpError("region #")
             << region.getRegionNumber() << " must bind the refined scrutinee and the "
             << getForwarded().size() << " values the match forwards";
  return failure(failed(verifyRefined(*this)) || failed(verifyYields(*this)));
}

// Built stating no lifetime: what it makes is stated where it is scoped.
void DataMatchOp::build(OpBuilder &builder, OperationState &state, TypeRange results,
                        Value scrutinee, ValueRange forwarded, ArrayRef<Tag> tags) {
  state.addOperands(scrutinee);
  state.addOperands(forwarded);
  state.addTypes(results);
  Properties &properties = state.getOrAddProperties<Properties>();
  properties.cases = builder.getDenseI32ArrayAttr(
      llvm::map_to_vector(tags, [](Tag tag) { return static_cast<int32_t>(tag); }));
  properties.operandSegmentSizes = {1, static_cast<int32_t>(forwarded.size()), 0};
  addRegions(state, tags.size());
}

unsigned DataMatchOp::getNumCases() { return static_cast<unsigned>(getCaseRegions().size()); }

Region &DataMatchOp::getCaseRegion(unsigned index) { return getCaseRegions()[index]; }

// The case `region` is: the default, region 0, is none of them.
unsigned DataMatchOp::caseOf(Region &region) { return region.getRegionNumber() - 1; }

// Case `index`'s constructor, the key the match holds for it.
Tag DataMatchOp::getCaseTag(unsigned index) {
  return Tag{static_cast<uint32_t>(getCases()[index])};
}

// The scrutinee's family application, which its type is.
DataType DataMatchOp::getDataType() { return dataTypeOf(getScrutinee().getType()); }

// The refined scrutinee a region that runs binds first.
BlockArgument DataMatchOp::getRefined(Region &region) { return region.getArgument(0); }

// Every region binds the scrutinee refined, its type the constructors that
// reach the region: a case's, or the default's every one no case holds.
CaseScrutinee DataMatchOp::getRegionScrutinee(Region &region) {
  return case_scrutinee::Bound{getRefined(region)};
}

// The scrutinee and the forwarded values, which enter every region; the
// lifetimes the match states, its last operands, enter none.
OperandRange DataMatchOp::getEntering() {
  return getOperation()->getOperands().take_front(1 + getForwarded().size());
}

// What the default binds: the scrutinee, at its grade, refined to the
// constructors no case holds, and each forwarded value as it is.
SmallVector<Type> DataMatchOp::getDefaultTypes() {
  Type scrutinee = getScrutinee().getType();
  DataType data = getDataType();
  SmallVector<Tag> left;
  for (Tag tag : data.possibleTags())
    if (!llvm::is_contained(getCases(), static_cast<int32_t>(tag)))
      left.push_back(tag);
  SmallVector<Type> types{graded(gradeOf(scrutinee), data.refined(left))};
  llvm::append_range(types, getForwarded().getTypes());
  return types;
}

// The constructor's binders bind in its case; the default binds none.
ArrayRef<families::Sort> DataMatchOp::getBoundSorts(Region &region) {
  if (&region == &getDefaultRegion())
    return {};
  return getDataType().binderSorts(getCaseTag(caseOf(region)));
}

// A case assumes its scrutinee's indices equal to its constructor's
// equation over the binders it binds; the default, and a case of a family
// with no indices, assume nothing.
std::optional<families::RegionRefinement> DataMatchOp::getRefinement(Region &region) {
  if (&region == &getDefaultRegion())
    return std::nullopt;
  families::RegionRefinement refinement =
      families::caseRefinement(getDataType(), getCaseTag(caseOf(region)));
  if (refinement.count == 0)
    return std::nullopt;
  return refinement;
}

// The cases kept by their keys, and the default, which then binds what a
// default of those cases binds: the scrutinee refined to every constructor
// they leave. Where that changes a type (a case region taking the default's
// place, a default left more constructors), the region reads none of its
// arguments.
Operation *DataMatchOp::keepCases(RewriterBase &rewriter, ArrayRef<unsigned> kept,
                                  Region *fallback) {
  DataMatchOp fresh = keepCasesOf(*this, rewriter, kept, fallback, [&] {
    SmallVector<Tag> tags =
        llvm::map_to_vector(kept, [&](unsigned index) { return getCaseTag(index); });
    return DataMatchOp::create(rewriter, getLoc(), getResultTypes(), getScrutinee(),
                               getForwarded(), tags);
  });
  if (fallback)
    for (auto [arg, type] :
         llvm::zip_equal(fresh.getDefaultRegion().getArguments(), fresh.getDefaultTypes()))
      arg.setType(type);
  return fresh;
}

Value DataMatchOp::getStatedLifetime(Value made) { return lifetimes::statedOuter(*this, made, 0); }

void DataMatchOp::setStatedLifetime(Value made, Value lifetime) {
  lifetimes::stateOuter(*this, made, lifetime, 0);
}

unsigned DataMatchOp::getScopedBindings() { return scopedBindings(*this); }

std::optional<unsigned> DataMatchOp::getBindingEntry(Value made) { return bindingEntry(*this, made); }

void DataMatchOp::getSuccessorRegions(RegionBranchPoint point,
                                      SmallVectorImpl<RegionSuccessor> &successors) {
  successorsOf(*this, point, successors);
}

// The scrutinee and the forwarded values enter every region, refined.
OperandRange DataMatchOp::getEntrySuccessorOperands(RegionSuccessor) { return getEntering(); }

ValueRange DataMatchOp::getSuccessorInputs(RegionSuccessor successor) {
  if (successor.isOperation())
    return getResults();
  return successor.getSuccessor()->getArguments();
}

// A value enters a region refined: as itself, or at its family with fewer
// constructors possible or at an index the case's equation fixes. A yield
// gives the match's results at their own types, which the op's verifier
// holds it to.
bool DataMatchOp::areTypesCompatible(Type lhs, Type rhs) {
  return lhs == rhs || families::refines(rhs, lhs);
}

void DataMatchOp::getEntrySuccessorRegions(ArrayRef<Attribute> operands,
                                           SmallVectorImpl<RegionSuccessor> &successors) {
  entrySuccessorsOf(*this, takenRegionOf(*this, operands.front()), successors);
}

void DataMatchOp::getRegionInvocationBounds(ArrayRef<Attribute> operands,
                                            SmallVectorImpl<InvocationBounds> &bounds) {
  boundsOf(*this, takenRegionOf(*this, operands.front()), bounds);
}
