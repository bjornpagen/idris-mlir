// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a value's type says of its data, a constructor written by its label,
// the elimination of a value at one of its uses, and the names the lowering
// reserves.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/Regions.h"

#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Twine.h"

#include <algorithm>
#include <concepts>
#include <iterator>

using namespace mlir;
using namespace idr;

DataType idr::dataTypeOf(Type type) { return dyn_cast<DataType>(unrestricted(type)); }

namespace {

// Whether what `set` holds may write a memo cell's state: a force's write,
// a call whose row carries memo_state, anything an op that declares
// nothing may do. Which cell a write names is not read: a call's row names
// none, and a force reaches the cell under whatever value holds it (a
// widening, a match's refined binding, a field of what holds it).
bool mayForce(const effects::EffectSet &set) {
  return set.mayAct(effects::Kind::Write, effects::ResourceId::MemoState);
}

// Whether an op from `first` up to `last` in one block, with everything in
// it, may write a memo cell's state.
bool anyForces(Block::iterator first, Block::iterator last) {
  return std::any_of(first, last, [](Operation &op) { return mayForce(effects::whole(&op)); });
}

// Whether something of `holder`, beside what precedes an op in its block,
// may write a memo cell's state before that op runs in `region`: every op
// of `holder` where the region may run again, the op's own earlier runs
// among them (any region no interface bounds); every op of its other
// regions where one of them may enter it (a join point's region, entered
// by a jump from its body); nothing where only `holder` enters it.
bool forcedAround(Operation *holder, Region &region) {
  if (regionRuns(holder, region.getRegionNumber()) == Runs::Repeatedly)
    return mayForce(effects::whole(holder));
  SmallVector<RegionBranchPoint> entries;
  cast<RegionBranchOpInterface>(holder).getPredecessors(RegionSuccessor(&region), entries);
  if (llvm::all_of(entries, [](RegionBranchPoint entry) { return entry.isParent(); }))
    return false;
  return llvm::any_of(holder->getRegions(), [&](Region &other) {
    return &other != &region &&
           llvm::any_of(other, [](Block &block) { return anyForces(block.begin(), block.end()); });
  });
}

} // namespace

// A cast into or out of a linear position is the cell it was given, built
// as that was: the value is read through each such cast (throughLinear),
// as every reader of what a value is reads it. Whether the cell may have
// been forced since it was built is its memo state, and every op that may
// change that state declares a write of it, a call through its row; so the
// question is asked, through the effect system's one query, of each op
// that may run between the idr.data.con and `reader`: those after the con
// in its block up to the one that holds `reader`, and, in each region on
// the way down to `reader`, what the region's op does itself (a force's
// exchange writes before its region runs), what comes before the way down
// in its block, and what else of the op may run first. What `reader`'s own
// regions do runs after it reads. A reader the con does not come before in
// the con's block is not one the con's cell reaches as built.
bool idr::builtStateHolds(Value value, Operation *reader) {
  DataType data = dataTypeOf(value.getType());
  if (!data || !data.memo())
    return true;
  auto con = throughLinear(value).getDefiningOp<DataConOp>();
  if (!con)
    return false;
  Operation *outermost = con->getBlock()->findAncestorOpInBlock(*reader);
  if (!outermost || !con->isBeforeInBlock(outermost))
    return false;
  for (Operation *at = reader; at != outermost; at = at->getParentOp()) {
    Region *region = at->getParentRegion();
    Operation *holder = region->getParentOp();
    // Essential: a region of several blocks, which only the lowering makes,
    // runs its blocks in an order no op states, so nothing is known.
    if (!region->hasOneBlock() || mayForce(effects::own(holder)) ||
        anyForces(region->front().begin(), at->getIterator()) || forcedAround(holder, *region))
      return false;
  }
  return !anyForces(std::next(con->getIterator()), outermost->getIterator());
}

ParseResult idr::parseCtorRef(AsmParser &parser, Type type, IntegerAttr &tag) {
  SMLoc at = parser.getCurrentLocation();
  StringAttr label;
  if (parser.parseSymbolName(label))
    return failure();
  DataType data = dataTypeOf(type);
  if (!data)
    return parser.emitError(at, "names a constructor of ") << type << ", which is no data type";
  std::optional<Tag> found = data.getGroup().tagOf(data.getMember(), label.getValue());
  if (!found)
    return parser.emitError(at, "expects a constructor of ")
           << type << ", got @" << label.getValue();
  tag = parser.getBuilder().getI32IntegerAttr(static_cast<int32_t>(*found));
  return success();
}

void idr::printCtorRef(OpAsmPrinter &printer, Operation *, Type type, IntegerAttr tag) {
  printer.printSymbolName(dataTypeOf(type).ctor(Tag{static_cast<uint32_t>(tag.getInt())}).label);
}

namespace {

// `user` read as the one class of op the chain allows at a step, where it
// is one that `fits` the step; none where it is another op, or none.
template <typename Op, typename Fits>
  requires std::predicate<Fits &, Op>
Op stepAs(Operation *user, Fits &&fits) {
  auto op = dyn_cast_if_present<Op>(user);
  return op && fits(op) ? op : Op();
}

} // namespace

// The chain is its steps in their order, each read as its own class: a
// linear position entered and left at once, a field of a value of a family
// that is no closure sum (one is dispatched on itself, below), a linear
// position left, then the dispatch.
std::optional<idr::Elimination> idr::eliminationAt(OpOperand &use) {
  // The only user of `v`, if it has one.
  auto next = [](Value v) { return v.hasOneUse() ? *v.user_begin() : nullptr; };
  auto entering = [](LinCastOp cast) { return cast.getDirection() == QuantityChange::Enter; };
  auto leaving = [](LinCastOp cast) { return cast.getDirection() == QuantityChange::Leave; };
  auto ofNoClosureSum = [](DataFieldOp field) {
    DataType data = dataTypeOf(field.getValue().getType());
    return !data || !data.closures();
  };
  Elimination e;
  Value value = use.get();
  Operation *user = use.getOwner();
  if (LinCastOp enter = stepAs<LinCastOp>(user, entering)) {
    LinCastOp exit = stepAs<LinCastOp>(next(enter.getResult()), leaving);
    if (!exit)
      return std::nullopt;
    e.passed = {enter, exit};
    user = next(value = exit.getResult());
  }
  if (DataFieldOp field = stepAs<DataFieldOp>(user, ofNoClosureSum)) {
    e.field = field;
    user = next(value = field.getResult());
  }
  if (LinCastOp leave = stepAs<LinCastOp>(user, leaving)) {
    e.use = leave;
    user = next(value = leave.getResult());
  }
  // The dispatch takes the value apart and does nothing else with it, which
  // its op declares (EliminatesOperand: a match, a field read, a string's
  // output), so no op is named here. What raising dispatches on is what a
  // tail builds, a closure sum or a string; a match or a field read is
  // declared over every family, and a value of any other family is never
  // dispatched on (a field of one is a step, read above).
  DataType data = dataTypeOf(value.getType());
  if (!user || !user->hasTrait<EliminatesOperand>() || user->getOperand(0) != value ||
      (data && !data.closures()))
    return std::nullopt;
  e.dispatch = user;
  return e;
}

SmallVector<Operation *> idr::Elimination::steps() const {
  SmallVector<Operation *> out;
  if (passed)
    out.append({passed->first, passed->second});
  if (field)
    out.push_back(*field);
  if (use)
    out.push_back(*use);
  return out;
}

std::string idr::reservedName(StringRef kind, StringRef discriminator) {
  return ("__idr$" + kind + "$" + discriminator).str();
}
