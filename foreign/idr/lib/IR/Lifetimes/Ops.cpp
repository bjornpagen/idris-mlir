// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The questions every pass asks of a lifetime value (the lifetime a scoped
// value lives in, the lifetime whose extent it has, what its package holds
// where it is per level, the cursor a stack lies on, what a use does with
// it), and the hooks of the lifetime's ops: the region that runs once,
// which the openers, the loan and the unpack share, what a loan and an
// unpack bind, the pack that ends a per-level lifetime's region, the cell
// bumped into a lifetime, and how each op that does more than name a
// lifetime uses it. The kind itself is Kind.cpp's.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Lifetimes.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// Lifetime values
//===----------------------------------------------------------------------===//

// The op that made a result states its lifetime; a block argument's is
// stated by the op whose region binds it, a function stating its
// parameters' in its signature. Any other value lives in no lifetime.
Value idr::lifetimes::statedLifetime(Value scoped) {
  if (!freedBy(scoped.getType(), Release::Scoped))
    return nullptr;
  Operation *maker = isa<OpResult>(scoped)
                         ? cast<OpResult>(scoped).getOwner()
                         : cast<BlockArgument>(scoped).getOwner()->getParentOp();
  auto states = dyn_cast_or_null<StatesLifetimeOpInterface>(maker);
  return states ? states.getStatedLifetime(scoped) : nullptr;
}

// The group's generated accessor keeps its segment's size with it.
void idr::lifetimes::restateOuters(StatesOutersOpInterface op, ValueRange outers) {
  op.getOutersMutable().assign(outers);
}

// A lifetime derived from another, a view cast from it or a room reserved
// in it, has its extent, which the op that derived it names
// (DerivesLifetimeOpInterface); any other lifetime is its own extent.
Value idr::lifetimes::extentOf(Value lifetime) {
  auto derived = lifetime.getDefiningOp<DerivesLifetimeOpInterface>();
  return derived ? derived.getDerivedFrom() : lifetime;
}

// A stack lifetime packs its mark and a chained one its chain, whether its
// opener or an unpack bound it, which its binder says (PerLevelOpInterface);
// a block, a home and a lifetime without memory are never per level, and
// their openers bind none.
std::optional<Packed> idr::lifetimes::packedOf(Value lifetime) {
  auto arg = dyn_cast<BlockArgument>(lifetime);
  if (!arg || arg.getArgNumber() != 0)
    return std::nullopt;
  auto binder = dyn_cast<PerLevelOpInterface>(arg.getOwner()->getParentOp());
  return binder ? std::optional<Packed>(binder.getPacked()) : std::nullopt;
}

// A stack's opener and a stack package's unpack name the cursor below
// (CursorBinderOpInterface); a chain's unpack names none.
Value idr::lifetimes::baseOf(Value lifetime) {
  auto arg = dyn_cast<BlockArgument>(lifetime);
  if (!arg || arg.getArgNumber() != 0)
    return nullptr;
  auto binder = dyn_cast<CursorBinderOpInterface>(arg.getOwner()->getParentOp());
  return binder ? binder.getCursorBase() : nullptr;
}

// An op without the interface only names the lifetime.
LifetimeUse idr::lifetimes::useOf(OpOperand &lifetime) {
  auto uses = dyn_cast<LifetimeUseOpInterface>(lifetime.getOwner());
  return uses ? uses.getLifetimeUse(lifetime) : LifetimeUse::Names;
}

// A cell's source takes the lifetime it is memory of as its one lifetime
// operand: a cell its count frees comes from a source that takes none.
Value idr::lifetimes::cellLifetime(Value cell) {
  Operation *source = cell.getDefiningOp();
  if (!source)
    return nullptr;
  auto lifetime = llvm::find_if(source->getOperands(),
                                [](Value operand) { return isa<LifetimeType>(operand.getType()); });
  return lifetime == source->getOperands().end() ? Value() : *lifetime;
}

//===----------------------------------------------------------------------===//
// The region that runs once
//===----------------------------------------------------------------------===//

namespace {

// An op whose one region runs once, entered with no operand forwarded (its
// arguments are its own: the lifetime first, then what a loan or a package
// binds, each living in that lifetime), returning its yields as its
// results after `own` results of its own (a loan's owner); each scoped
// result lives in the lifetime its own entry of `outers` states.
template <typename Op>
concept RunsOnceOp = lifetimes::StatesOuters<Op> && requires(Op op) {
  { op.getBody() } -> std::convertible_to<Region &>;
};

template <RunsOnceOp Op>
void successors(Op op, RegionBranchPoint point, SmallVectorImpl<RegionSuccessor> &regions) {
  if (point.isParent())
    regions.push_back(RegionSuccessor(&op.getBody()));
  else
    regions.push_back(RegionSuccessor(op.getOperation()));
}

template <RunsOnceOp Op>
ValueRange inputs(Op op, RegionSuccessor successor, unsigned own) {
  if (successor.isOperation())
    return ValueRange(op->getResults().drop_front(own));
  return ValueRange();
}

// A result's lifetime is its entry of `outers`; an argument the region binds
// after the lifetime lives in that lifetime.
template <RunsOnceOp Op>
Value stated(Op op, Value made, unsigned own) {
  if (isa<OpResult>(made))
    return lifetimes::statedOuter(op, made, own);
  auto arg = cast<BlockArgument>(made);
  Block &entry = op.getBody().front();
  if (arg.getOwner() == &entry && arg.getArgNumber() > 0)
    return entry.getArgument(0);
  return nullptr;
}

// Named apart from OpState's own `state`, which an op's member finds first.
template <RunsOnceOp Op>
void stateLifetime(Op op, Value made, Value lifetime, unsigned own) {
  lifetimes::stateOuter(op, made, lifetime, own);
}

} // namespace

// Each op of the region run once defines the same five hooks, its own
// results counted out first: one definition, the shared templates above.
#define IDR_RUNS_ONCE(Op, Own)                                                                     \
  void Op::getSuccessorRegions(RegionBranchPoint point,                                           \
                               SmallVectorImpl<RegionSuccessor> &regions) {                       \
    successors(*this, point, regions);                                                             \
  }                                                                                                \
  ValueRange Op::getSuccessorInputs(RegionSuccessor successor) {                                  \
    return inputs(*this, successor, Own);                                                          \
  }                                                                                                \
  void Op::getRegionInvocationBounds(ArrayRef<Attribute>,                                         \
                                     SmallVectorImpl<InvocationBounds> &bounds) {                 \
    bounds.emplace_back(1, 1);                                                                     \
  }                                                                                                \
  Value Op::getStatedLifetime(Value made) { return stated(*this, made, Own); }                    \
  void Op::setStatedLifetime(Value made, Value lifetime) {                                        \
    stateLifetime(*this, made, lifetime, Own);                                                     \
  }

IDR_RUNS_ONCE(LifetimeOp, 0)
IDR_RUNS_ONCE(LifetimeHomeOp, 0)
IDR_RUNS_ONCE(LifetimeBlockOp, 0)
IDR_RUNS_ONCE(LifetimeStackOp, 0)
IDR_RUNS_ONCE(LifetimeChainOp, 0)
IDR_RUNS_ONCE(LifetimeUnpackOp, 0)
IDR_RUNS_ONCE(LendOp, 1)
#undef IDR_RUNS_ONCE

//===----------------------------------------------------------------------===//
// idr.lend
//===----------------------------------------------------------------------===//

Value LendOp::getView() { return getBody().front().getArgument(1); }

Type lifetimes::lentView(Type owner) {
  Unique claim = uncountedClaims[static_cast<unsigned>(Uses::Many)];
  return graded({Uses::Many, Hold::scoped(claim)}, owner);
}

// A counted value lent: the region binds the loan's lifetime, a view, and
// the view of the owner, scoped to it at many uses, so claiming what a
// value used many times may before references are counted (the grade's
// uncountedClaims), which is nothing: a loan is made before counting.
LogicalResult LendOp::verifyRegions() {
  Type owner = getOwner().getType();
  std::optional<Hold> hold = holdOf(owner);
  if (!hold || hold->release() != Release::Counted)
    return emitOpError("lends ") << owner << ", which is no counted value";
  Block &entry = getBody().front();
  Type view = lifetimes::lentView(owner);
  if (entry.getNumArguments() != 2 || !isViewLifetime(entry.getArgument(0).getType()) ||
      entry.getArgument(1).getType() != view)
    return emitOpError("binds no loan's view lifetime and view ") << view;
  return success();
}

//===----------------------------------------------------------------------===//
// idr.lifetime.unpack
//===----------------------------------------------------------------------===//

// The lifetime it reopens is per level as its package's source was.
Packed LifetimeUnpackOp::getPacked() { return getPackage().getType().getPacked(); }

// A stack's mark goes back to the cursor whose stack it is, which the
// unpack names exactly when its package is a stack's; what enters the level
// lies in that cursor above the mark, so a chain's unpack, which names
// none, takes nothing in. The region binds the reopened lifetime, a cursor,
// the values the package holds in the package's order, then those that
// enter in theirs, each restated in it.
LogicalResult LifetimeUnpackOp::verifyRegions() {
  auto package = cast<LifetimePackageType>(getPackage().getType());
  bool stack = package.getPacked() == Packed::FromStack;
  Value base = getBase();
  if (stack != static_cast<bool>(base))
    return emitOpError(stack ? "reopens a stack's package but names no cursor its mark goes back to"
                             : "names a base cursor for a chain's package, which has none");
  for (Value entered : getEntering())
    if (!base || lifetimes::statedLifetime(entered) != base)
      return emitOpError("takes into its level ")
             << entered.getType() << ", which does not live in the cursor its mark goes back to";
  Block &entry = getBody().front();
  ArrayRef<Type> held = package.getHeld();
  TypeRange bound = entry.getArgumentTypes();
  if (bound.size() != 1 + held.size() + getEntering().size() ||
      !isCursorLifetime(entry.getArgument(0).getType()) ||
      !llvm::equal(bound.drop_front().take_front(held.size()), held) ||
      !llvm::equal(bound.take_back(getEntering().size()), getEntering().getTypes()))
    return emitOpError("binds no cursor lifetime, the values ")
           << package << " holds and those that enter its level";
  return success();
}

//===----------------------------------------------------------------------===//
// idr.lifetime.reserve
//===----------------------------------------------------------------------===//

// A room reserved in a cursor puts its bytes into the cursor's lifetime,
// its one lifetime operand.
TypedValue<LifetimeType> LifetimeReserveOp::getPutLifetime() { return getLifetime(); }

LifetimeUse LifetimeReserveOp::getLifetimeUse(OpOperand &) { return LifetimeUse::Puts; }

std::uint64_t LifetimeReserveOp::getPutBytes(const Layouts &) {
  return static_cast<std::uint64_t>(getBytes());
}

//===----------------------------------------------------------------------===//
// idr.cell.arena
//===----------------------------------------------------------------------===//

// The cell is bumped into its one lifetime operand, and is what it puts
// there.
TypedValue<LifetimeType> CellArenaOp::getPutLifetime() { return getLifetime(); }

TypedValue<CellType> CellArenaOp::getPutCell() { return getCell(); }

LifetimeUse CellArenaOp::getLifetimeUse(OpOperand &) { return LifetimeUse::Puts; }

// The cell's allocation size, its constructor's in its family's cells.
std::uint64_t CellArenaOp::getPutBytes(const Layouts &layouts) {
  auto cell = cast<CellType>(getCell().getType());
  return layouts.cells(cell.getData()).cell(cell.getTag()).size;
}

// A cell of a lifetime is the lifetime's, lent to whatever holds it, as a
// slot of the frame is: it is new to no one, so nothing is declared, and
// the box its init makes is not fresh.
void CellArenaOp::getFlowEdges(FlowEdges &) {}

//===----------------------------------------------------------------------===//
// idr.cell.stack
//===----------------------------------------------------------------------===//

// A slot of the frame, stated in its one lifetime operand, which it puts
// nothing into.
LifetimeUse CellStackOp::getLifetimeUse(OpOperand &) { return LifetimeUse::Slot; }

//===----------------------------------------------------------------------===//
// idr.call
//===----------------------------------------------------------------------===//

// A lifetime a call takes is its callee's parameter, which its callee's
// own uses decide.
LifetimeUse idr::CallOp::getLifetimeUse(OpOperand &) { return LifetimeUse::PassesOn; }

//===----------------------------------------------------------------------===//
// idr.lifetime.pack
//===----------------------------------------------------------------------===//

// The end of a per-level lifetime's region: its lifetime is the region's
// own, of a stack or a chain, the package says so and holds the values
// given, and nothing follows it but the terminator that yields it, so
// nothing is put into the lifetime once its memory has moved.
LogicalResult LifetimePackOp::verify() {
  Value lifetime = getLifetime();
  auto arg = dyn_cast<BlockArgument>(lifetime);
  if (!arg || arg.getOwner() != getOperation()->getBlock())
    return emitOpError("packs a lifetime its region does not bind");
  std::optional<Packed> packed = lifetimes::packedOf(lifetime);
  auto package = cast<LifetimePackageType>(getPackage().getType());
  if (!packed || *packed != package.getPacked())
    return emitOpError("packs a lifetime that is no stack or chain lifetime, or into ") << package;
  if (!llvm::equal(getHeld().getTypes(), package.getHeld()))
    return emitOpError("holds values of other types than ") << package << " says";
  Operation *next = getOperation()->getNextNode();
  if (!next || next != getOperation()->getBlock()->getTerminator() ||
      !llvm::is_contained(next->getOperands(), getPackage()))
    return emitOpError("is not followed by the terminator that yields its package");
  return success();
}
