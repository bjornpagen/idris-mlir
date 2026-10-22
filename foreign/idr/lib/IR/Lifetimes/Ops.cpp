// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// `!idr.lifetime`'s kind, the questions every pass asks of a lifetime value
// (its kind, the lifetime a scoped value lives in, where its memory comes
// from), and the hooks of the lifetime's ops: the region that runs once,
// which the openers, the loan and the unpack share, what a loan and an
// unpack bind, the pack that ends a per-level lifetime's region, and the
// cell bumped into a lifetime.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Lifetimes.h"

#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

//===----------------------------------------------------------------------===//
// The kind's spelling, and the directives that write a known type as nothing
//===----------------------------------------------------------------------===//

// A case's keyword from the specification's table; a home's site after it.
ParseResult idr::parseLifetimeKind(AsmParser &parser, FailureOr<LifetimeKind> &kind) {
  for (LifetimeKind candidate :
       {LifetimeKind::view(), LifetimeKind::room(), LifetimeKind::cursor()})
    if (succeeded(parser.parseOptionalKeyword(candidate.spelling()))) {
      kind = candidate;
      return success();
    }
  if (succeeded(parser.parseOptionalKeyword(LifetimeKind::home(0).spelling()))) {
    std::uint32_t site;
    if (parser.parseInteger(site))
      return failure();
    kind = LifetimeKind::home(site);
    return success();
  }
  return parser.emitError(parser.getCurrentLocation(), "expected a lifetime's kind");
}

void idr::printLifetimeKind(AsmPrinter &printer, LifetimeKind kind) {
  printer << kind.spelling();
  kind.fold([] {}, [] {}, [] {}, [&](std::uint32_t site) { printer << ' ' << site; });
}

namespace idr {

// A loan gives its owner back at the owner's own type, written once.
ParseResult parseSameType(OpAsmParser &, Type &returned, Type owner) {
  returned = owner;
  return success();
}
void printSameType(OpAsmPrinter &, Operation *, Type, Type) {}

// The one view lifetime type and the one room lifetime type, written as
// nothing: activation's and forget's results are views, reserve's a room.
ParseResult parseViewLifetime(OpAsmParser &parser, Type &view) {
  view = LifetimeType::get(parser.getContext(), LifetimeKind::view());
  return success();
}
void printViewLifetime(OpAsmPrinter &, Operation *, Type) {}

ParseResult parseRoomLifetime(OpAsmParser &parser, Type &room) {
  room = LifetimeType::get(parser.getContext(), LifetimeKind::room());
  return success();
}
void printRoomLifetime(OpAsmPrinter &, Operation *, Type) {}

} // namespace idr

//===----------------------------------------------------------------------===//
// Lifetime values
//===----------------------------------------------------------------------===//

namespace {

std::optional<LifetimeKind> kindOfType(Type type) {
  if (auto lifetime = dyn_cast<LifetimeType>(type))
    return lifetime.getKind();
  return std::nullopt;
}

template <typename Ask>
bool kindIs(Type type, Ask ask) {
  std::optional<LifetimeKind> kind = kindOfType(type);
  return kind && ask(*kind);
}

} // namespace

bool idr::admitsPuts(Type type) {
  return kindIs(type, [](LifetimeKind k) { return k.admitsPuts(); });
}
bool idr::isCursorLifetime(Type type) {
  return kindIs(type, [](LifetimeKind k) { return k.isCursor(); });
}
bool idr::isRoomLifetime(Type type) {
  return kindIs(type, [](LifetimeKind k) { return k.isRoom(); });
}
bool idr::isViewLifetime(Type type) {
  return kindIs(type, [](LifetimeKind k) { return k.isView(); });
}
bool idr::isLifetimeOfCase(Type type, LifetimeKindCase kase) {
  return kindIs(type, [&](LifetimeKind k) { return k.kindCase() == kase; });
}

LifetimeKind idr::lifetimes::kindOf(Value lifetime) {
  return cast<LifetimeType>(lifetime.getType()).getKind();
}

bool idr::lifetimes::passesAs(Type arg, Type param) {
  std::optional<LifetimeKind> a = kindOfType(arg);
  std::optional<LifetimeKind> p = kindOfType(param);
  return a && p && a->passesAs(*p);
}

bool idr::lifetimes::sameCursors(FunctionType caller, FunctionType callee) {
  return llvm::count_if(caller.getInputs(), isCursorLifetime) ==
         llvm::count_if(callee.getInputs(), isCursorLifetime);
}

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

Value idr::lifetimes::extentOf(Value lifetime) {
  if (auto forget = lifetime.getDefiningOp<LifetimeForgetOp>())
    return forget.getLifetime();
  if (auto reserve = lifetime.getDefiningOp<LifetimeReserveOp>())
    return reserve.getLifetime();
  return lifetime;
}

// Each opener binds its lifetime as its region's first argument, and says
// where its memory comes from (OpensLifetimeOpInterface).
std::optional<Opener> idr::lifetimes::openerOf(Value lifetime) {
  auto arg = dyn_cast<BlockArgument>(extentOf(lifetime));
  if (!arg || arg.getArgNumber() != 0)
    return std::nullopt;
  if (auto opens = dyn_cast<OpensLifetimeOpInterface>(arg.getOwner()->getParentOp()))
    return opens.getOpener();
  return std::nullopt;
}

// A stack lifetime packs its mark and a chained one its chain, whether its
// opener or an unpack bound it; a block, a home and a lifetime without
// memory are never per level.
std::optional<Packed> idr::lifetimes::packedOf(Value lifetime) {
  auto arg = dyn_cast<BlockArgument>(lifetime);
  if (!arg || arg.getArgNumber() != 0)
    return std::nullopt;
  if (auto unpack = dyn_cast<LifetimeUnpackOp>(arg.getOwner()->getParentOp()))
    return cast<LifetimePackageType>(unpack.getPackage().getType()).getPacked();
  std::optional<Opener> opener = openerOf(lifetime);
  if (opener == Opener::OnStack)
    return Packed::FromStack;
  if (opener == Opener::InChain)
    return Packed::FromChain;
  return std::nullopt;
}

// A stack's opener and a stack package's unpack name the cursor below.
Value idr::lifetimes::baseOf(Value lifetime) {
  auto arg = dyn_cast<BlockArgument>(lifetime);
  if (!arg || arg.getArgNumber() != 0)
    return nullptr;
  Operation *binder = arg.getOwner()->getParentOp();
  if (auto stack = dyn_cast<LifetimeStackOp>(binder))
    return stack.getBase();
  if (auto unpack = dyn_cast<LifetimeUnpackOp>(binder))
    return unpack.getBase();
  return nullptr;
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

template <RunsOnceOp Op>
void state(Op op, Value made, Value lifetime, unsigned own) {
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
  void Op::setStatedLifetime(Value made, Value lifetime) { state(*this, made, lifetime, Own); }

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

// A counted value lent: the region binds the loan's lifetime, a view, and
// the view of the owner, scoped to it with what the owner claims of its
// sharing, at many uses.
LogicalResult LendOp::verifyRegions() {
  Type owner = getOwner().getType();
  std::optional<Hold> hold = holdOf(owner);
  if (!hold || hold->release() != Release::Counted)
    return emitOpError("lends ") << owner << ", which is no counted value";
  Block &entry = getBody().front();
  Type view = graded({Uses::Many, Hold::scoped(hold->claim())}, owner);
  if (entry.getNumArguments() != 2 || !isViewLifetime(entry.getArgument(0).getType()) ||
      entry.getArgument(1).getType() != view)
    return emitOpError("binds no loan's view lifetime and view ") << view;
  return success();
}

//===----------------------------------------------------------------------===//
// idr.lifetime.unpack
//===----------------------------------------------------------------------===//

// A stack's mark goes back to the cursor whose stack it is, which the
// unpack names exactly when its package is a stack's; the region binds the
// reopened lifetime, a cursor, and the values the package holds, restated
// in it, in the package's order.
LogicalResult LifetimeUnpackOp::verifyRegions() {
  auto package = cast<LifetimePackageType>(getPackage().getType());
  bool stack = package.getPacked() == Packed::FromStack;
  if (stack != static_cast<bool>(getBase()))
    return emitOpError(stack ? "reopens a stack's package but names no cursor its mark goes back to"
                             : "names a base cursor for a chain's package, which has none");
  Block &entry = getBody().front();
  if (entry.getNumArguments() != package.getHeld().size() + 1 ||
      !isCursorLifetime(entry.getArgument(0).getType()) ||
      !llvm::equal(entry.getArgumentTypes().drop_front(), package.getHeld()))
    return emitOpError("binds no cursor lifetime and the values ") << package << " holds";
  return success();
}

//===----------------------------------------------------------------------===//
// idr.lifetime.reserve
//===----------------------------------------------------------------------===//

// A room reserved in a cursor puts its bytes into the cursor's lifetime.
Value LifetimeReserveOp::getPutLifetime() { return getLifetime(); }

std::uint64_t LifetimeReserveOp::getPutBytes(const Layouts &) {
  return static_cast<std::uint64_t>(getBytes());
}

//===----------------------------------------------------------------------===//
// idr.cell.arena
//===----------------------------------------------------------------------===//

Value CellArenaOp::getPutLifetime() { return getLifetime(); }

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
