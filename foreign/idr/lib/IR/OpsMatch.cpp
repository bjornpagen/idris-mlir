// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.data.match and idr.lit.match: their rules, their builders, the region
// each takes for a known key, the edges upstream's control-flow interfaces
// read off them, the equation each case assumes, and the lifetime they
// state for the scoped values they make.
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
//
// idr.lit.match's scrutinee is a string, a big integer or a natural, read in
// place and never taken apart: a case binds nothing, since in it the
// scrutinee is its literal, and the default binds the scrutinee, none of
// the keys, at its own type. An integer or a condition is matched by
// scf.index_switch or scf.if.
//
// A region ends by yielding the match's results, by jumping to an enclosing
// join point, which the match lets through, or by never ending. That is
// each terminator's own rule: a yield names its parents, a jump checks what
// it crosses, and a terminator that never ends has no successor.

#include "idr/IR/Control/Stated.h"
#include "idr/IR/Families/Scope.h"
#include "idr/IR/Grades.h"
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
// for, which nothing reaches. A key is a tag of idr.data.match or a literal
// of idr.lit.match, two different things, so this is written over the op.
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
// the two lists are held to one length here. And the lifetime the match
// states is present exactly when what it makes is scoped.
template <MatchFamily Match>
LogicalResult verifyKeys(Match op) {
  if (op.getCases().size() != op.getCaseRegions().size())
    return op.emitOpError("expects one key per case region");
  llvm::SmallDenseSet<std::decay_t<decltype(*op.getCases().begin())>> seen;
  for (auto key : op.getCases())
    if (!seen.insert(key).second)
      return op.emitOpError("has two cases for one key");
  return control::verifyStated(op);
}

// A match like `op` holding the cases `kept` alone, made by `make` from
// their keys, with `fallback` as its default: the regions moved in, the
// lifetime it states kept, `op` replaced.
template <MatchFamily Match, typename Make>
Match keepCasesOf(Match op, RewriterBase &rewriter, ArrayRef<unsigned> kept, Region *fallback,
                  Make &&make) {
  rewriter.setInsertionPoint(op);
  Match fresh = make();
  if (Value outer = op.getOuter())
    rewriter.modifyOpInPlace(fresh, [&] { fresh.getOuterMutable().assign(outer); });
  for (auto [index, into] : llvm::zip_equal(kept, fresh.getCaseRegions()))
    rewriter.inlineRegionBefore(op.getCaseRegions()[index], into, into.end());
  if (fallback) {
    Region &into = fresh.getDefaultRegion();
    rewriter.inlineRegionBefore(*fallback, into, into.end());
  }
  rewriter.replaceOp(op, fresh->getResults());
  return fresh;
}

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

// A region gives the match's results at their own types: what a case
// learned of a value leaves it only through a cast its scope checks.
LogicalResult verifyYields(Operation *op) {
  for (Region &region : op->getRegions())
    if (!region.empty())
      if (auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
          yield && TypeRange(yield.getResults()) != op->getResultTypes())
        return op->emitOpError("region #")
               << region.getRegionNumber() << " yields " << yield.getResults().getTypes()
               << " for results of types " << op->getResultTypes();
  return success();
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

// The scrutinee and the forwarded values, which enter every region; the
// lifetime the match states, its last operand, enters none.
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

Value DataMatchOp::getStatedLifetime(Value made) { return control::statedFor(*this, made); }

void DataMatchOp::setStatedLifetime(Value made, Value lifetime) {
  control::stateFor(*this, made, lifetime);
}

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

//===----------------------------------------------------------------------===//
// idr.lit.match
//===----------------------------------------------------------------------===//

// Keys are literals of the scrutinee's type, as the type says. A case binds
// nothing, since in it the scrutinee is its literal; the default binds the
// scrutinee, none of the keys, at its own type.
LogicalResult LitMatchOp::verify() {
  if (failed(verifyKeys(*this)))
    return failure();
  auto literals = cast<LiteralTypeInterface>(unrestricted(getScrutinee().getType()));
  for (Attribute key : getCases())
    if (!literals.isLiteral(key))
      return emitOpError("has a key ") << key << " that is not a literal of " << literals;
  for (Region &region : getCaseRegions())
    if (region.getNumArguments())
      return emitOpError("region #") << region.getRegionNumber()
                                     << " binds an argument, and a literal case binds none";
  Region &fallback = getDefaultRegion();
  if (TypeRange(fallback.getArgumentTypes()) != TypeRange(getScrutinee().getType()))
    return emitOpError("expects a default that binds its scrutinee, of type ")
           << getScrutinee().getType();
  return verifyYields(*this);
}

void LitMatchOp::build(OpBuilder &, OperationState &state, TypeRange results, Value scrutinee,
                       ArrayAttr cases) {
  state.addOperands(scrutinee);
  state.addTypes(results);
  state.getOrAddProperties<Properties>().cases = cases;
  addRegions(state, cases.size());
}

unsigned LitMatchOp::getNumCases() { return static_cast<unsigned>(getCaseRegions().size()); }

Region &LitMatchOp::getCaseRegion(unsigned index) { return getCaseRegions()[index]; }

unsigned LitMatchOp::caseOf(Region &region) { return region.getRegionNumber() - 1; }

// The cases kept by their keys, and the default, which a literal match
// always has: the scrutinee it binds is none of fewer keys still.
Operation *LitMatchOp::keepCases(RewriterBase &rewriter, ArrayRef<unsigned> kept,
                                 Region *fallback) {
  return keepCasesOf(*this, rewriter, kept, fallback, [&] {
    SmallVector<Attribute> keys =
        llvm::map_to_vector(kept, [&](unsigned index) { return getCases()[index]; });
    return LitMatchOp::create(rewriter, getLoc(), getResultTypes(), getScrutinee(),
                              rewriter.getArrayAttr(keys));
  });
}

Value LitMatchOp::getStatedLifetime(Value made) { return control::statedFor(*this, made); }

void LitMatchOp::setStatedLifetime(Value made, Value lifetime) {
  control::stateFor(*this, made, lifetime);
}

void LitMatchOp::getSuccessorRegions(RegionBranchPoint point,
                                     SmallVectorImpl<RegionSuccessor> &successors) {
  successorsOf(*this, point, successors);
}

// The scrutinee enters the default alone.
OperandRange LitMatchOp::getEntrySuccessorOperands(RegionSuccessor successor) {
  return getOperation()->getOperands().take_front(
      successor.getSuccessor() == &getDefaultRegion() ? 1 : 0);
}

ValueRange LitMatchOp::getSuccessorInputs(RegionSuccessor successor) {
  if (successor.isOperation())
    return getResults();
  return successor.getSuccessor()->getArguments();
}

// The literal itself, when the scrutinee is a constant.
void LitMatchOp::getEntrySuccessorRegions(ArrayRef<Attribute> operands,
                                          SmallVectorImpl<RegionSuccessor> &successors) {
  Attribute value = operands.front();
  entrySuccessorsOf(*this, value ? takenRegion(*this, value) : nullptr, successors);
}

void LitMatchOp::getRegionInvocationBounds(ArrayRef<Attribute> operands,
                                           SmallVectorImpl<InvocationBounds> &bounds) {
  Attribute value = operands.front();
  boundsOf(*this, value ? takenRegion(*this, value) : nullptr, bounds);
}
