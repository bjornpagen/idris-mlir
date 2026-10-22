// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.match and idr.match_lit: their rules, their builders, the region
// each takes for a known key, and the edges upstream's control-flow
// interfaces read off them.
//
// A match is a region per case, from the frontend to the lowering. Each
// region of idr.match binds the scrutinee refined: a case to its
// constructor, the default to the constructors no case holds, so a field is
// a total read of that refined value and a nested match on it has no region
// for a constructor the type excludes. The values whose types mention an
// index the case refines enter it refined too, forwarded beside the
// scrutinee. That a region's arguments are those refinements is the
// function's scope walk's to check, which keeps every enclosing case's
// refinement as it walks; this file checks what the op alone says.
//
// idr.match_lit's scrutinee is a string, a big integer or a natural, read in
// place and never taken apart, so its regions bind nothing. An integer or a
// condition is matched by scf.index_switch or scf.if.
//
// A region ends by yielding the match's results, by jumping to an enclosing
// join point, which the match lets through, or by never ending. That is
// each terminator's own rule: a yield names its parents, a jump checks what
// it crosses, and a terminator that never ends has no successor.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/Matchers.h"
#include "mlir/IR/RegionKindInterface.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallVectorExtras.h"

using namespace mlir;
using namespace idr;

namespace {

// The two members of the match family, each with its key.
template <typename Match>
concept MatchFamily = requires(Match op) {
  op.getCases();
  op.getDefaultRegion();
  op.getCaseRegions();
};

// An empty default region and one per case, the default first.
void addRegions(OperationState &state, size_t cases) {
  for (size_t region = 0; region <= cases; ++region)
    state.addRegion();
}

// The region of `op` its key `key` takes: its case, else the default. An
// empty default never runs: the key is then one the match has no region
// for, which nothing reaches. A key is a tag of idr.match or a literal of
// idr.match_lit, two different things, so this is written over the op.
template <MatchFamily Match, typename Key>
Region *takenRegion(Match op, Key key) {
  auto cases = op.getCases();
  const auto *it = llvm::find(cases, key);
  if (it != cases.end())
    return &op.getCaseRegions()[static_cast<unsigned>(it - cases.begin())];
  Region &fallback = op.getDefaultRegion();
  return fallback.empty() ? nullptr : &fallback;
}

// Every region that runs, entered from the match; the match's results,
// from a yield; from a jump to an enclosing join point, what that point's
// op says, since the match lets the jump through.
template <MatchFamily Match>
void successorsOf(Match op, RegionBranchPoint point, SmallVectorImpl<RegionSuccessor> &successors) {
  if (point.isParent()) {
    for (Region &region : op->getRegions())
      if (!region.empty())
        successors.emplace_back(&region);
    return;
  }
  RegionBranchTerminatorOpInterface terminator = point.getTerminatorPredecessorOrNull();
  if (terminatorPropagatesThrough(terminator, op)) {
    appendPropagatedTerminatorSuccessors(terminator, op, successors);
    return;
  }
  successors.push_back(RegionSuccessor(op.getOperation()));
}

// The region taken when it is known, else every region that runs.
template <MatchFamily Match>
void entrySuccessorsOf(Match op, Region *taken, SmallVectorImpl<RegionSuccessor> &successors) {
  if (taken)
    successors.emplace_back(taken);
  else
    successorsOf(op, RegionBranchPoint::parent(), successors);
}

// At most once each region that runs, and none but the taken one when it
// is known.
template <MatchFamily Match>
void boundsOf(Match op, Region *taken, SmallVectorImpl<InvocationBounds> &bounds) {
  for (Region &region : op->getRegions())
    bounds.emplace_back(/*lb=*/0,
                        /*ub=*/!region.empty() && (!taken || taken == &region) ? 1 : 0);
}

// One key per case region, each once. ODS ties no key to a case region, so
// the two lists are held to one length here.
template <MatchFamily Match>
LogicalResult verifyKeys(Match op) {
  if (op.getCases().size() != op.getCaseRegions().size())
    return op.emitOpError("expects one key per case region");
  llvm::SmallDenseSet<std::decay_t<decltype(*op.getCases().begin())>> seen;
  for (auto key : op.getCases())
    if (!seen.insert(key).second)
      return op.emitOpError("has two cases for one key");
  return success();
}

// The region a known scrutinee takes: a constant constructor; the
// constructor of the idr.con that built it, where its state still holds at
// the match (a memo cell's changes); or the one constructor its type leaves
// possible. Else none is known.
Region *takenRegionOf(MatchOp op, Attribute value) {
  Value scrutinee = op.getScrutinee();
  const auto &possible = dataTypeOf(scrutinee.getType()).possibleTags();
  if (possible.size() == 1)
    return takenRegion(op, static_cast<int32_t>(possible.front()));
  if (auto con = dyn_cast_or_null<ConAttr>(value))
    return takenRegion(op, static_cast<int32_t>(con.getTag()));
  if (!builtStateHolds(scrutinee, op.getOperation()))
    return nullptr;
  if (auto built = scrutinee.getDefiningOp<ConOp>())
    return takenRegion(op, static_cast<int32_t>(built.getTag()));
  return nullptr;
}

} // namespace

//===----------------------------------------------------------------------===//
// What the matches take
//===----------------------------------------------------------------------===//

// A data value, at any grade: its carrier is a family application.
bool idr::isMatchable(Type type) { return isa<DataType>(unrestricted(type)); }

// A value of a type with literals that no upstream op matches: an integer
// or a condition is scf.index_switch's or scf.if's.
bool idr::isMatchedLiteral(Type type) {
  Type carrier = unrestricted(type);
  return isa<LiteralTypeInterface>(carrier) && !isa<IntegerType>(carrier);
}

//===----------------------------------------------------------------------===//
// idr.match
//===----------------------------------------------------------------------===//

// Each key is a constructor of the scrutinee's family, and every region
// that runs binds the refined scrutinee and each forwarded value, in that
// order.
LogicalResult MatchOp::verify() {
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
  return success();
}

void MatchOp::build(OpBuilder &builder, OperationState &state, TypeRange results,
                    Value scrutinee, ValueRange forwarded, ArrayRef<Tag> tags) {
  state.addOperands(scrutinee);
  state.addOperands(forwarded);
  state.addTypes(results);
  state.getOrAddProperties<Properties>().cases = builder.getDenseI32ArrayAttr(
      llvm::map_to_vector(tags, [](Tag tag) { return static_cast<int32_t>(tag); }));
  addRegions(state, tags.size());
}

unsigned MatchOp::getNumCases() { return static_cast<unsigned>(getCaseRegions().size()); }

Region &MatchOp::getCaseRegion(unsigned index) { return getCaseRegions()[index]; }

// The case `region` is: the default, region 0, is none of them.
unsigned MatchOp::caseOf(Region &region) { return region.getRegionNumber() - 1; }

// Case `index`'s constructor, the key the match holds for it.
Tag MatchOp::getCaseTag(unsigned index) {
  return Tag{static_cast<uint32_t>(getCases()[index])};
}

// The scrutinee's family application, which its type is.
DataType MatchOp::getDataType() { return dataTypeOf(getScrutinee().getType()); }

// The refined scrutinee a region that runs binds first.
BlockArgument MatchOp::getRefined(Region &region) { return region.getArgument(0); }

// The constructor's binders bind in its case; the default binds none.
ArrayRef<families::Sort> MatchOp::getBoundSorts(Region &region) {
  if (&region == &getDefaultRegion())
    return {};
  return getDataType().binderSorts(getCaseTag(caseOf(region)));
}

void MatchOp::getSuccessorRegions(RegionBranchPoint point,
                                  SmallVectorImpl<RegionSuccessor> &successors) {
  successorsOf(*this, point, successors);
}

// The scrutinee and the forwarded values enter every region, refined.
OperandRange MatchOp::getEntrySuccessorOperands(RegionSuccessor) { return getOperands(); }

ValueRange MatchOp::getSuccessorInputs(RegionSuccessor successor) {
  if (successor.isOperation())
    return getResults();
  return successor.getSuccessor()->getArguments();
}

// A value enters a region refined: as itself, or at its family with fewer
// constructors possible or at an index the case's equation fixes. A yield
// gives the match's results at their own types.
bool MatchOp::areTypesCompatible(Type lhs, Type rhs) {
  return lhs == rhs || families::refines(rhs, lhs);
}

void MatchOp::getEntrySuccessorRegions(ArrayRef<Attribute> operands,
                                       SmallVectorImpl<RegionSuccessor> &successors) {
  entrySuccessorsOf(*this, takenRegionOf(*this, operands.front()), successors);
}

void MatchOp::getRegionInvocationBounds(ArrayRef<Attribute> operands,
                                        SmallVectorImpl<InvocationBounds> &bounds) {
  boundsOf(*this, takenRegionOf(*this, operands.front()), bounds);
}

//===----------------------------------------------------------------------===//
// idr.match_lit
//===----------------------------------------------------------------------===//

// Keys are literals of the scrutinee's type, as the type says; no region
// binds anything, since the scrutinee is read in place.
LogicalResult MatchLitOp::verify() {
  if (failed(verifyKeys(*this)))
    return failure();
  auto literals = cast<LiteralTypeInterface>(unrestricted(getScrutinee().getType()));
  for (Attribute key : getCases())
    if (!literals.isLiteral(key))
      return emitOpError("has a key ") << key << " that is not a literal of " << literals;
  for (Region &region : getOperation()->getRegions())
    if (!region.empty() && region.getNumArguments())
      return emitOpError("region #") << region.getRegionNumber()
                                     << " binds an argument, and a literal match binds none";
  return success();
}

void MatchLitOp::build(OpBuilder &, OperationState &state, TypeRange results, Value scrutinee,
                       ArrayAttr cases) {
  state.addOperands(scrutinee);
  state.addTypes(results);
  state.getOrAddProperties<Properties>().cases = cases;
  addRegions(state, cases.size());
}

unsigned MatchLitOp::getNumCases() { return static_cast<unsigned>(getCaseRegions().size()); }

Region &MatchLitOp::getCaseRegion(unsigned index) { return getCaseRegions()[index]; }

unsigned MatchLitOp::caseOf(Region &region) { return region.getRegionNumber() - 1; }

void MatchLitOp::getSuccessorRegions(RegionBranchPoint point,
                                     SmallVectorImpl<RegionSuccessor> &successors) {
  successorsOf(*this, point, successors);
}

ValueRange MatchLitOp::getSuccessorInputs(RegionSuccessor successor) {
  return successor.isOperation() ? ValueRange(getResults()) : ValueRange();
}

// The literal itself, when the scrutinee is a constant.
void MatchLitOp::getEntrySuccessorRegions(ArrayRef<Attribute> operands,
                                          SmallVectorImpl<RegionSuccessor> &successors) {
  Attribute value = operands.front();
  entrySuccessorsOf(*this, value ? takenRegion(*this, value) : nullptr, successors);
}

void MatchLitOp::getRegionInvocationBounds(ArrayRef<Attribute> operands,
                                           SmallVectorImpl<InvocationBounds> &bounds) {
  Attribute value = operands.front();
  boundsOf(*this, value ? takenRegion(*this, value) : nullptr, bounds);
}
