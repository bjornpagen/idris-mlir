// idr.inbounds:joins: the values bound from several places, each from one
// value per place: the arguments a region branch forwards and the results
// it gives (scf.while, scf.for, scf.if, idr.match, idr.match_lit, the loops
// over arrays), a private
// function's parameters, a call's results, a select. What each place gives
// is said by the ops' own interfaces and by the module's symbol uses, so a
// new region op is a join the moment it describes its branches.
export module idr.inbounds:joins;

import idr.mlir;
import idr.dialect;
import idr.graph;

using namespace mlir;

namespace idr::inbounds {

// A component of the record it was read from. A match's case argument is
// the scrutinee's field; its default binds the scrutinee, which is not a
// component. Views are not stripped here: the caller does that, so a walk
// that asks which component a value is does not follow a call while it asks.
export struct Component {
  Value record;
  StringAttr ctor;
  uint64_t index;
};

export std::optional<Component> componentOf(Value value) {
  if (auto field = value.getDefiningOp<FieldOp>())
    return Component{field.getValue(), field.getCtorAttr().getAttr(), field.getIndex()};
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
  return Component{match.getScrutinee(), ctor.getAttr(), arg.getArgNumber()};
}

// The array an access reads or writes: a view or a share of an owned
// array is that array, of its length, and so is the array a linear
// position was entered with.
export Value arrayRoot(Value array) {
  while (true) {
    Value next = ::idr::throughLinear(array);
    if (auto borrow = next.getDefiningOp<BorrowOp>())
      next = borrow.getValue();
    else if (auto share = next.getDefiningOp<ShareOp>())
      next = share.getValue();
    if (next == array)
      return array;
    array = next;
  }
}

// The array `dim` measures: an array's one dimension is its length.
export std::optional<Value> dimensionOf(memref::DimOp dim) {
  std::optional<int64_t> index = dim.getConstantIndex();
  if (!index || *index != 0 || !isArray(dim.getSource().getType()))
    return std::nullopt;
  return dim.getSource();
}

// What `value` clamps at 0 from below: `x` when it is `max(x, c)`, either
// way round, for a constant `c` of at most 0, so that its clamp at 0 is
// `x`'s.
export std::optional<Value> clampOf(Value value) {
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

// The array whose length `length` is: its one dimension made i64, which is
// what the guard of an access to it checks the index against. None for any
// other integer.
export std::optional<Value> measured(Value length) {
  auto cast = length.getDefiningOp<arith::IndexCastOp>();
  if (!cast || !cast.getIn().getType().isIndex() || !length.getType().isInteger(64))
    return std::nullopt;
  auto dim = cast.getIn().getDefiningOp<memref::DimOp>();
  return dim ? dimensionOf(dim) : std::nullopt;
}

// The calls of each private function whose every use is a direct call: the
// only places its parameters are bound. A function whose address is taken
// (a closure of it, a constant) or that is public has no such list, so
// nothing is known of its parameters.
export class Calls {
public:
  explicit Calls(ModuleOp module) {
    graph::SymbolUses symbolUses(module);
    for (auto fn : module.getOps<func::FuncOp>()) {
      if (!fn.isPrivate() || fn.isExternal())
        continue;
      std::optional<ArrayRef<SymbolTable::SymbolUse>> uses = symbolUses.of(fn);
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

// Where `value` is among `inputs`.
export std::optional<unsigned> positionIn(ValueRange inputs, Value value) {
  for (auto [i, input] : llvm::enumerate(inputs))
    if (input == value)
      return i;
  return std::nullopt;
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
