// idr.lower:tailPosition: whether a call on the LLVM dialect is in tail
// position, as idr-tail-calls decides it: by what the path from the call
// to a return decides alone.

export module idr.lower:tailPosition;

import idr.mlir;

using namespace mlir;

namespace idr::lower {

namespace {

// What a value is on the path from a call to a return, as far as the path
// alone decides it: a part of the call's result (`path`, the positions an
// extractvalue takes, empty for the whole result), a constant, poison, a
// struct put together on the path, or unknown.
struct Known {
  enum class Kind : uint8_t { Unknown, Part, Constant, Poison, Struct };
  Kind kind = Kind::Unknown;
  SmallVector<int64_t, 2> path;
  Attribute constant;
  std::vector<Known> fields;

  static Known part(ArrayRef<int64_t> path) {
    Known k;
    k.kind = Kind::Part;
    k.path.assign(path.begin(), path.end());
    return k;
  }
  static Known of(Kind kind) {
    Known k;
    k.kind = kind;
    return k;
  }
};

unsigned fieldCount(Type type) {
  auto structure = dyn_cast<LLVM::LLVMStructType>(type);
  return structure ? static_cast<unsigned>(structure.getBody().size()) : 0;
}

// The part at `position` of a value known as `k`.
Known extract(const Known &k, ArrayRef<int64_t> position) {
  if (position.empty() || k.kind == Known::Kind::Poison)
    return k;
  if (k.kind == Known::Kind::Part) {
    SmallVector<int64_t, 4> path(k.path.begin(), k.path.end());
    llvm::append_range(path, position);
    return Known::part(path);
  }
  auto at = static_cast<size_t>(position.front());
  if (k.kind == Known::Kind::Struct && at < k.fields.size())
    return extract(k.fields[at], position.drop_front());
  return Known();
}

// A value known as `k`, of `type`, with the part at `position` replaced by
// `value`.
Known insert(const Known &k, Type type, ArrayRef<int64_t> position, const Known &value) {
  if (position.empty())
    return value;
  unsigned n = fieldCount(type);
  auto at = static_cast<size_t>(position.front());
  if (at >= n)
    return Known();
  Known out = Known::of(Known::Kind::Struct);
  for (unsigned i = 0; i < n; ++i) {
    SmallVector<int64_t, 1> index{static_cast<int64_t>(i)};
    out.fields.push_back(k.kind == Known::Kind::Struct ? k.fields[i]
                         : k.kind == Known::Kind::Unknown || k.kind == Known::Kind::Constant
                             ? Known()
                             : extract(k, index));
  }
  Type field = cast<LLVM::LLVMStructType>(type).getBody()[at];
  out.fields[at] = insert(out.fields[at], field, position.drop_front(), value);
  return out;
}

// Whether `k`, of `type`, is exactly the part of the call's result at `path`:
// that part, or a struct put together from each of its fields in order.
bool isPart(const Known &k, Type type, SmallVectorImpl<int64_t> &path) {
  if (k.kind == Known::Kind::Part)
    return ArrayRef(k.path) == ArrayRef(path);
  if (k.kind != Known::Kind::Struct || k.fields.size() != fieldCount(type))
    return false;
  auto structure = cast<LLVM::LLVMStructType>(type);
  for (auto [i, field] : llvm::enumerate(k.fields)) {
    path.push_back(static_cast<int64_t>(i));
    bool same = isPart(field, structure.getBody()[i], path);
    path.pop_back();
    if (!same)
      return false;
  }
  return true;
}

} // namespace

// Whether `call`, in `fn`, is in tail position: the path from it, which every
// op on it decides alone, returns the call's result unchanged, or returns
// nothing after a call that returns nothing. Every op on the way only
// computes, so returning right after the call loses nothing.
bool inTailPosition(LLVM::CallOp call, LLVM::LLVMFuncOp fn) {
  Type result = fn.getFunctionType().getReturnType();
  bool nothing = isa<LLVM::LLVMVoidType>(result);
  if (nothing != (call.getNumResults() == 0) ||
      (!nothing && call.getResult().getType() != result))
    return false;
  DenseMap<Value, Known> known;
  if (!nothing)
    known[call.getResult()] = Known::part({});
  auto lookup = [&](Value value) -> Known {
    if (auto it = known.find(value); it != known.end())
      return it->second;
    Operation *def = value.getDefiningOp();
    if (auto constant = dyn_cast_or_null<LLVM::ConstantOp>(def)) {
      Known k = Known::of(Known::Kind::Constant);
      k.constant = constant.getValue();
      return k;
    }
    if (isa_and_nonnull<LLVM::PoisonOp, LLVM::UndefOp>(def))
      return Known::of(Known::Kind::Poison);
    return Known();
  };
  // The path goes through each block once at most: one that comes round
  // again is a loop, and does not return the call's result.
  DenseSet<Block *> entered;
  Block::iterator at = std::next(call->getIterator());
  auto enter = [&](Block *block, ValueRange args) {
    if (!entered.insert(block).second)
      return false;
    SmallVector<Known> values = llvm::map_to_vector(args, lookup);
    for (auto [arg, value] : llvm::zip_equal(block->getArguments(), values))
      known[arg] = value;
    at = block->begin();
    return true;
  };
  // A decided condition: the constant `k` is an integer.
  auto decided = [](const Known &k) -> std::optional<APInt> {
    auto integer = k.kind == Known::Kind::Constant ? dyn_cast<IntegerAttr>(k.constant)
                                                   : IntegerAttr();
    if (!integer)
      return std::nullopt;
    return integer.getValue();
  };
  // Enough for the joins and loop exits of a lowered body, short of a scan
  // of a whole large function from every call in it.
  constexpr unsigned budget = 4096;
  for (unsigned steps = 0; steps < budget; ++steps) {
    Operation *op = &*at;
    if (auto ret = dyn_cast<LLVM::ReturnOp>(op)) {
      if (nothing)
        return true;
      SmallVector<int64_t, 4> path;
      return ret.getNumOperands() == 1 && isPart(lookup(ret.getOperand(0)), result, path);
    }
    if (auto branch = dyn_cast<LLVM::BrOp>(op)) {
      if (!enter(branch.getDest(), branch.getDestOperands()))
        return false;
      continue;
    }
    if (auto branch = dyn_cast<LLVM::CondBrOp>(op)) {
      std::optional<APInt> condition = decided(lookup(branch.getCondition()));
      if (!condition)
        return false;
      bool taken = !condition->isZero();
      if (!enter(taken ? branch.getTrueDest() : branch.getFalseDest(),
                 taken ? branch.getTrueDestOperands() : branch.getFalseDestOperands()))
        return false;
      continue;
    }
    if (auto branch = dyn_cast<LLVM::SwitchOp>(op)) {
      std::optional<APInt> value = decided(lookup(branch.getValue()));
      if (!value)
        return false;
      Block *dest = branch.getDefaultDestination();
      ValueRange operands = branch.getDefaultOperands();
      if (std::optional<DenseIntElementsAttr> cases = branch.getCaseValues())
        for (auto [i, key] : llvm::enumerate(cases->getValues<APInt>()))
          if (key == *value) {
            dest = branch.getCaseDestinations()[i];
            operands = branch.getCaseOperands(static_cast<unsigned>(i));
            break;
          }
      if (!enter(dest, operands))
        return false;
      continue;
    }
    if (op->hasTrait<OpTrait::IsTerminator>())
      return false;
    if (auto extract = dyn_cast<LLVM::ExtractValueOp>(op)) {
      known[extract.getResult()] = lower::extract(lookup(extract.getContainer()), extract.getPosition());
    } else if (auto insert = dyn_cast<LLVM::InsertValueOp>(op)) {
      known[insert.getResult()] = lower::insert(lookup(insert.getContainer()), insert.getType(),
                                           insert.getPosition(), lookup(insert.getValue()));
    } else if (op->getNumRegions() != 0 || !isMemoryEffectFree(op)) {
      return false;
    }
    ++at;
  }
  return false;
}

} // namespace idr::lower
