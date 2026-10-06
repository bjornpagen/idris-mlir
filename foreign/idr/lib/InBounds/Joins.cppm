// idr.inbounds:joins: the values bound from several places, each from one
// value per place: the arguments a region branch forwards and the results
// it gives (scf.while, scf.for, scf.if, idr.match, idr.match_lit), a private
// function's parameters, a call's results, a select. What each place gives
// is said by the ops' own interfaces and by the module's symbol uses, so a
// new region op is a join the moment it describes its branches.
export module idr.inbounds:joins;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::inbounds {

// The array an access reads or writes: a view or a share of an owned
// array is that array, of its length.
export Value arrayRoot(Value array) {
  while (true) {
    if (auto borrow = array.getDefiningOp<BorrowOp>())
      array = borrow.getValue();
    else if (auto share = array.getDefiningOp<ShareOp>())
      array = share.getValue();
    else
      return array;
  }
}

// The calls of each private function whose every use is a direct call: the
// only places its parameters are bound. A function whose address is taken
// (a closure of it, a constant) or that is public has no such list, so
// nothing is known of its parameters.
export class Calls {
public:
  explicit Calls(ModuleOp module) {
    for (auto fn : module.getOps<func::FuncOp>()) {
      if (!fn.isPrivate() || fn.isExternal())
        continue;
      std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(fn, module);
      if (!uses)
        continue;
      SmallVector<func::CallOp> calls;
      bool direct = true;
      for (const SymbolTable::SymbolUse &use : *uses) {
        auto call = dyn_cast<func::CallOp>(use.getUser());
        if (!call || call.getCallee() != fn.getSymName()) {
          direct = false;
          break;
        }
        calls.push_back(call);
      }
      if (direct)
        sites.try_emplace(fn, std::move(calls));
    }
  }

  // Every call of `fn`, when those are all its uses; else null.
  const SmallVector<func::CallOp> *of(func::FuncOp fn) const {
    auto it = sites.find(fn);
    return it == sites.end() ? nullptr : &it->second;
  }

private:
  DenseMap<Operation *, SmallVector<func::CallOp>> sites;
};

// A value bound from several places: the value each place gives it, in an
// order every value of the same join (`key`) shares, so that two of them
// pair place by place. `owner` is the op whose run binds it; when `local`,
// every place is inside the owner or the owner itself, where a value
// defined before the owner is in scope and keeps one value throughout.
export struct Join {
  const void *key;
  Operation *owner;
  bool local;
  SmallVector<Value> incoming;
};

namespace {

// What every predecessor of `successor` gives the input at `position`.
SmallVector<Value> forwarded(RegionBranchOpInterface branch, RegionSuccessor successor,
                             unsigned position) {
  SmallVector<RegionBranchPoint> points;
  branch.getPredecessors(successor, points);
  SmallVector<Value> values;
  for (RegionBranchPoint point : points)
    values.push_back(branch.getSuccessorOperands(point, successor)[position]);
  return values;
}

std::optional<unsigned> positionIn(ValueRange inputs, Value value) {
  for (auto [i, input] : llvm::enumerate(inputs))
    if (input == value)
      return i;
  return std::nullopt;
}

std::optional<Join> argumentJoin(BlockArgument arg, const Calls &calls) {
  Block *block = arg.getOwner();
  if (!block->isEntryBlock())
    return std::nullopt;
  Operation *parent = block->getParentOp();
  if (auto fn = dyn_cast<func::FuncOp>(parent)) {
    const SmallVector<func::CallOp> *sites = calls.of(fn);
    if (!sites)
      return std::nullopt;
    Join join{block, fn, false, {}};
    for (func::CallOp call : *sites)
      join.incoming.push_back(call.getArgOperands()[arg.getArgNumber()]);
    return join;
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

std::optional<Join> resultJoin(OpResult result) {
  Operation *op = result.getOwner();
  if (auto branch = dyn_cast<RegionBranchOpInterface>(op)) {
    RegionSuccessor successor(op);
    std::optional<unsigned> position = positionIn(branch.getSuccessorInputs(successor), result);
    if (!position)
      return std::nullopt;
    return Join{op, op, true, forwarded(branch, successor, *position)};
  }
  if (auto call = dyn_cast<func::CallOp>(op)) {
    auto callee = SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(call, call.getCalleeAttr());
    if (!callee || callee.isExternal())
      return std::nullopt;
    Join join{op, op, false, {}};
    callee.walk([&](func::ReturnOp ret) {
      join.incoming.push_back(ret.getOperand(result.getResultNumber()));
    });
    return join;
  }
  // Two selects on one condition take the same side.
  if (auto select = dyn_cast<arith::SelectOp>(op); select && select.getCondition().getType().isInteger(1))
    return Join{select.getCondition().getAsOpaquePointer(), op, true,
                {select.getTrueValue(), select.getFalseValue()}};
  return std::nullopt;
}

} // namespace

// The join `value` is bound at, or none when it is computed by one op or
// bound where not every place is known.
export std::optional<Join> joinOf(Value value, const Calls &calls) {
  if (auto arg = dyn_cast<BlockArgument>(value))
    return argumentJoin(arg, calls);
  return resultJoin(cast<OpResult>(value));
}

} // namespace idr::inbounds
