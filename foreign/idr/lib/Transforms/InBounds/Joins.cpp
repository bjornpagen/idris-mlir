// The values bound from several places, each from one value per place: the
// arguments a region branch forwards and the results it gives (scf.while,
// scf.for, scf.if, idr.match, idr.match_lit, the loops over arrays), a
// private function's parameters, a call's results, a select. What each
// place gives is said by the ops' own interfaces, so a new region op is a
// join the moment it describes its branches. A function's parameters and a
// call's results are bound in other functions: those joins are interfaces,
// whose places only the constructor of Lengths walks.
//
// A record field, a take's field and a match case's argument are the
// component the constructor stored. Following that construction is how a
// length and the array it describes, kept as two fields, come to be
// related: the relation is the operands the constructor paired, not the
// type the record has.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/Transforms/InBounds.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::inbounds {

// A match's case argument is the scrutinee's field; its default binds the
// scrutinee, which is not a component. Views are not stripped here: the
// caller does that, so a walk that asks which component a value is does not
// follow a call while it asks.
std::optional<Component> componentOf(Value value) {
  if (auto field = value.getDefiningOp<FieldOp>())
    return Component{field.getValue(), field.getCtorAttr().getLeafReference(), field.getIndex()};
  if (auto take = value.getDefiningOp<TakeOp>()) {
    ResultRange fields = take.getFields();
    for (auto [i, field] : llvm::enumerate(fields))
      if (field == value)
        return Component{take.getValue(), take.getCtor().getLeafReference(), i};
  }
  auto arg = dyn_cast<BlockArgument>(value);
  if (!arg || !arg.getOwner()->isEntryBlock())
    return std::nullopt;
  auto match = dyn_cast<MatchOp>(arg.getOwner()->getParentOp());
  if (!match)
    return std::nullopt;
  unsigned number = arg.getOwner()->getParent()->getRegionNumber();
  if (number >= match.getCases().size())
    return std::nullopt;
  auto ctor = dyn_cast<FlatSymbolRefAttr>(match.getCases()[number]);
  if (!ctor)
    return std::nullopt;
  return Component{match.getScrutinee(), ctor.getLeafReference(), arg.getArgNumber()};
}

std::optional<Value> dimensionOf(memref::DimOp dim) {
  std::optional<int64_t> index = dim.getConstantIndex();
  if (!index || *index != 0 || !isRank1Array(dim.getSource().getType()))
    return std::nullopt;
  return dim.getSource();
}

// So that `value`'s clamp at 0 is `x`'s.
std::optional<Value> clampOf(Value value) {
  auto max = value.getDefiningOp<arith::MaxSIOp>();
  if (!max)
    return std::nullopt;
  auto floor = [](Value side) {
    APInt k;
    return matchPattern(side, m_ConstantInt(&k)) && !k.isStrictlyPositive();
  };
  if (floor(max.getLhs()))
    return max.getRhs();
  if (floor(max.getRhs()))
    return max.getLhs();
  return std::nullopt;
}

// What the guard of an access to it checks the index against. None for any
// other integer.
std::optional<Value> measured(Value length) {
  auto cast = length.getDefiningOp<arith::IndexCastOp>();
  if (!cast || !cast.getIn().getType().isIndex() || !length.getType().isInteger(64))
    return std::nullopt;
  auto dim = cast.getIn().getDefiningOp<memref::DimOp>();
  return dim ? dimensionOf(dim) : std::nullopt;
}

std::optional<unsigned> positionIn(ValueRange inputs, Value value) {
  for (auto [i, input] : llvm::enumerate(inputs))
    if (input == value)
      return i;
  return std::nullopt;
}

InterfaceKey::Tuple InterfaceKey::tuple() const {
  return {function, static_cast<unsigned>(side), static_cast<unsigned>(shape), first, second, ctor,
          field, other};
}

namespace {

// What every predecessor of `successor` gives the input at `position`, in
// predecessor order. Two values bound at one join line up place by place,
// and that order is the one the interface walks. The inverse successor
// mapping lists the same operands, in the hash order of the operands, which
// would pair a size with another place's array.
SmallVector<Value> forwarded(RegionBranchOpInterface branch, RegionSuccessor successor,
                             unsigned position) {
  SmallVector<Value> values;
  branch.getPredecessorValues(successor, static_cast<int>(position), values);
  return values;
}

// A function's parameters are bound only by its calls when every use of it
// is a direct call; a function whose address is taken, or that is public,
// binds them where nothing is known.
std::optional<Join> argumentJoin(BlockArgument arg, const Lengths::Local &lengths) {
  Block *block = arg.getOwner();
  if (!block->isEntryBlock())
    return std::nullopt;
  Operation *parent = block->getParentOp();
  if (auto fn = dyn_cast<FuncOp>(parent)) {
    if (!lengths.lengths().callsOf(fn))
      return std::nullopt;
    return Join{block, fn, false, {}, fn, InterfaceKey::Side::Parameters, arg.getArgNumber()};
  }
  auto branch = dyn_cast<RegionBranchOpInterface>(parent);
  if (!branch)
    return std::nullopt;
  RegionSuccessor successor(block->getParent());
  std::optional<unsigned> position = positionIn(branch.getSuccessorInputs(successor), arg);
  if (!position)
    return std::nullopt;
  return Join{block->getParent(), parent, true, forwarded(branch, successor, *position)};
}

// Two results of one call are bound by the callee's returns. The callee is
// named, never read: whether it has a body is the interface's to say.
std::optional<Join> resultJoin(OpResult result, const Lengths::Local &lengths) {
  Operation *op = result.getOwner();
  if (auto branch = dyn_cast<RegionBranchOpInterface>(op)) {
    RegionSuccessor successor(op);
    std::optional<unsigned> position = positionIn(branch.getSuccessorInputs(successor), result);
    if (!position)
      return std::nullopt;
    return Join{op, op, true, forwarded(branch, successor, *position)};
  }
  if (auto call = dyn_cast<CallOp>(op)) {
    auto callee = lengths.symbols().lookup<FuncOp>(call.getCallee());
    if (!callee)
      return std::nullopt;
    return Join{op, op, false, {}, callee, InterfaceKey::Side::Results, result.getResultNumber()};
  }
  // Two selects on one condition take the same side.
  if (auto select = dyn_cast<arith::SelectOp>(op); select && select.getCondition().getType().isInteger(1))
    return Join{select.getCondition().getAsOpaquePointer(), op, true,
                {select.getTrueValue(), select.getFalseValue()}};
  return std::nullopt;
}

} // namespace

std::optional<Join> joinOf(Value value, const Lengths::Local &lengths) {
  if (auto arg = dyn_cast<BlockArgument>(value))
    return argumentJoin(arg, lengths);
  return resultJoin(cast<OpResult>(value), lengths);
}

} // namespace idr::inbounds
