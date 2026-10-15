// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Whether a call on the LLVM dialect is in tail position.

#include "idr/Conversion/TailPosition.h"
#include "idr/Support/Worklist.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/Hashing.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Sequence.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>
#include <utility>
#include <variant>
#include <vector>

using namespace mlir;

namespace idr::conversion {

namespace {

struct Known;

// What a value is on the path from a call to a return, as far as the path
// alone decides it. Nothing the path decides.
struct Unknown {
  bool operator==(const Unknown &) const = default;
};
// A part of the call's result: the positions an extractvalue takes to it,
// none for the whole result.
struct Part {
  SmallVector<int64_t, 2> path;
  bool operator==(const Part &) const = default;
};
// An llvm.mlir.constant.
struct Constant {
  Attribute value;
  bool operator==(const Constant &) const = default;
};
// Poison or undef, every part of which is too.
struct Poison {
  bool operator==(const Poison &) const = default;
};
// A struct put together on the path: what each of its fields is, in order.
struct Struct {
  std::vector<Known> fields;
  bool operator==(const Struct &) const = default;
};

struct Known {
  std::variant<Unknown, Part, Constant, Poison, Struct> is;
  bool operator==(const Known &) const = default;
};

llvm::hash_code hashOf(const Known &k) {
  llvm::hash_code payload = std::visit(
      llvm::makeVisitor(
          [](const Part &part) { return llvm::hash_combine_range(part.path); },
          [](const Constant &constant) { return hash_value(constant.value); },
          [](const Struct &built) {
            llvm::hash_code fields = llvm::hash_value(built.fields.size());
            for (const Known &field : built.fields)
              fields = llvm::hash_combine(fields, hashOf(field));
            return fields;
          },
          [](const Unknown &) { return llvm::hash_code(0); },
          [](const Poison &) { return llvm::hash_code(0); }),
      k.is);
  return llvm::hash_combine(k.is.index(), payload);
}

// An entry of the path into a block: the block, and what the path knows
// there of each of its arguments and of each value live into it, which is
// everything the walk from there reads that it does not compute.
struct Entry {
  Block *block;
  SmallVector<Known, 2> arguments;
  SmallVector<Known, 4> liveIn;
  bool operator==(const Entry &) const = default;
};

// The part at `position` of a value known as `k`. A constant's parts are
// not taken apart.
Known extract(const Known &k, ArrayRef<int64_t> position) {
  if (position.empty())
    return k;
  return std::visit(
      llvm::makeVisitor(
          [&](const Part &part) -> Known {
            Part deeper = part;
            llvm::append_range(deeper.path, position);
            return {std::move(deeper)};
          },
          [&](const Struct &built) -> Known {
            auto at = static_cast<size_t>(position.front());
            if (at >= built.fields.size())
              return {Unknown{}};
            return extract(built.fields[at], position.drop_front());
          },
          [&](const Poison &) -> Known { return k; },
          [](const Unknown &) -> Known { return {Unknown{}}; },
          [](const Constant &) -> Known { return {Unknown{}}; }),
      k.is);
}

// A value known as `k`, of `type`, with the part at `position` replaced by
// `value`: a struct of what each field of `k` is, and `value` in its place.
Known insert(const Known &k, Type type, ArrayRef<int64_t> position, const Known &value) {
  if (position.empty())
    return value;
  auto structure = dyn_cast<LLVM::LLVMStructType>(type);
  auto at = static_cast<size_t>(position.front());
  if (!structure || at >= structure.getBody().size())
    return {Unknown{}};
  Struct built;
  for (int64_t field : llvm::seq<int64_t>(0, static_cast<int64_t>(structure.getBody().size())))
    built.fields.push_back(extract(k, ArrayRef<int64_t>(field)));
  built.fields[at] = insert(built.fields[at], structure.getBody()[at], position.drop_front(), value);
  return {std::move(built)};
}

// Whether `k`, of `type`, is exactly the part of the call's result at `path`:
// that part, or a struct put together from each of its fields in order.
bool isPart(const Known &k, Type type, SmallVectorImpl<int64_t> &path) {
  if (const auto *part = std::get_if<Part>(&k.is))
    return ArrayRef(part->path) == ArrayRef(path);
  const auto *built = std::get_if<Struct>(&k.is);
  auto structure = dyn_cast<LLVM::LLVMStructType>(type);
  if (!built || !structure || built->fields.size() != structure.getBody().size())
    return false;
  for (auto [i, field] : llvm::enumerate(built->fields)) {
    path.push_back(static_cast<int64_t>(i));
    bool same = isPart(field, structure.getBody()[i], path);
    path.pop_back();
    if (!same)
      return false;
  }
  return true;
}

// The integer a condition is when the path decides it.
std::optional<APInt> decided(const Known &k) {
  const auto *constant = std::get_if<Constant>(&k.is);
  auto integer = constant ? dyn_cast<IntegerAttr>(constant->value) : IntegerAttr();
  if (!integer)
    return std::nullopt;
  return integer.getValue();
}

// Where a branch the path decides goes, and what it passes there.
struct Edge {
  Block *dest;
  ValueRange operands;
};

// What a terminator decides: whether the call is in tail position, or where
// the path goes on.
using Step = std::variant<bool, Edge>;

// What the path from a call has learned of the values on it.
class Walk {
public:
  // `result` is the function's result type, void when the call returns
  // nothing.
  Walk(LLVM::CallOp call, Type result) : call(call), result(result) {
    if (call.getNumResults() != 0)
      known[call.getResult()] = {Part{}};
  }

  Known lookup(Value value) const {
    if (auto it = known.find(value); it != known.end())
      return it->second;
    Operation *def = value.getDefiningOp();
    if (auto constant = dyn_cast_or_null<LLVM::ConstantOp>(def))
      return {Constant{constant.getValue()}};
    if (isa_and_nonnull<LLVM::PoisonOp, LLVM::UndefOp>(def))
      return {Poison{}};
    return {Unknown{}};
  }

  // Learns what `op`, which is no terminator, computes; whether the path may
  // go past it. An op that has an effect or a region ends it: what follows
  // the call would then do more than return. So does the call itself, met
  // again: its result would then be a new one, not the one the path holds.
  bool compute(Operation &op) {
    if (&op == call.getOperation())
      return false;
    if (auto extracted = dyn_cast<LLVM::ExtractValueOp>(op)) {
      known[extracted.getResult()] =
          extract(lookup(extracted.getContainer()), extracted.getPosition());
      return true;
    }
    if (auto inserted = dyn_cast<LLVM::InsertValueOp>(op)) {
      known[inserted.getResult()] = insert(lookup(inserted.getContainer()), inserted.getType(),
                                           inserted.getPosition(), lookup(inserted.getValue()));
      return true;
    }
    return op.getNumRegions() == 0 && isMemoryEffectFree(&op);
  }

  // What `terminator` decides. A branch the path does not decide, or a
  // terminator that neither branches nor returns, is no tail position.
  Step follow(Operation &terminator) const {
    if (auto ret = dyn_cast<LLVM::ReturnOp>(terminator)) {
      if (isa<LLVM::LLVMVoidType>(result))
        return true;
      SmallVector<int64_t, 4> path;
      return ret.getNumOperands() == 1 && isPart(lookup(ret.getOperand(0)), result, path);
    }
    if (auto branch = dyn_cast<LLVM::BrOp>(terminator))
      return Edge{branch.getDest(), branch.getDestOperands()};
    if (auto branch = dyn_cast<LLVM::CondBrOp>(terminator)) {
      std::optional<APInt> condition = decided(lookup(branch.getCondition()));
      if (!condition)
        return false;
      if (condition->isZero())
        return Edge{branch.getFalseDest(), branch.getFalseDestOperands()};
      return Edge{branch.getTrueDest(), branch.getTrueDestOperands()};
    }
    if (auto branch = dyn_cast<LLVM::SwitchOp>(terminator)) {
      std::optional<APInt> value = decided(lookup(branch.getValue()));
      if (!value)
        return false;
      if (std::optional<DenseIntElementsAttr> cases = branch.getCaseValues())
        for (auto [i, key] : llvm::enumerate(cases->getValues<APInt>()))
          if (key == *value)
            return Edge{branch.getCaseDestinations()[i],
                        branch.getCaseOperands(static_cast<unsigned>(i))};
      return Edge{branch.getDefaultDestination(), branch.getDefaultOperands()};
    }
    return false;
  }

  // The entry `edge` makes: its block, what the branch passes each of the
  // block's arguments, all read before any is given, and what the path
  // knows of each value live into the block, in the order of `liveIn`.
  Entry enter(const Edge &edge, const Liveness::ValueSetT &liveIn) const {
    auto read = [&](Value value) { return lookup(value); };
    return {edge.dest, llvm::map_to_vector<2>(edge.operands, read),
            llvm::map_to_vector<4>(liveIn, read)};
  }

  // Gives the arguments of `entry`'s block what the entry knows of them.
  void bind(const Entry &entry) {
    for (auto [arg, value] : llvm::zip_equal(entry.block->getArguments(), entry.arguments))
      known[arg] = value;
  }

private:
  LLVM::CallOp call;
  Type result;
  DenseMap<Value, Known> known;
};

} // namespace

} // namespace idr::conversion

// An entry is a key of the path's set of entries.
template <>
struct llvm::DenseMapInfo<idr::conversion::Entry> {
  static unsigned getHashValue(const idr::conversion::Entry &entry) {
    llvm::hash_code values = llvm::hash_value(entry.arguments.size());
    for (const idr::conversion::Known &argument : entry.arguments)
      values = llvm::hash_combine(values, idr::conversion::hashOf(argument));
    for (const idr::conversion::Known &value : entry.liveIn)
      values = llvm::hash_combine(values, idr::conversion::hashOf(value));
    return static_cast<unsigned>(llvm::hash_combine(entry.block, values));
  }
  static bool isEqual(const idr::conversion::Entry &a, const idr::conversion::Entry &b) {
    return a == b;
  }
};

namespace idr::conversion {

bool TailPaths::inTailPosition(LLVM::CallOp call) const {
  bool nothing = isa<LLVM::LLVMVoidType>(result);
  if (nothing != (call.getNumResults() == 0) ||
      (!nothing && call.getResult().getType() != result))
    return false;
  Walk walk(call, result);
  // What the ops from `from` to the end of their block decide: whether the
  // call is in tail position, or the edge the path takes on.
  auto walkFrom = [&](Block::iterator from, Block *block) -> Step {
    for (Operation &op : llvm::make_range(from, block->end())) {
      if (op.hasTrait<OpTrait::IsTerminator>())
        return walk.follow(op);
      if (!walk.compute(op))
        return false;
    }
    // A block without a terminator, which a verified function has none of.
    return false;
  };
  // The path enters a block knowing the same of its arguments and of the
  // values live into it once at most. The walk from a block reads nothing
  // else it does not compute, so coming to a block again knowing what it
  // knew before means the path from there is the one it took before, a
  // loop, which never returns the call's result: the call is not in tail
  // position. Knowing something else, it may decide another branch. What
  // is known of a value is one of the function's own constants, poison, a
  // part of the call's result or a struct of these along the value's type,
  // finitely many, so the walk ends however long the path.
  OnceWorklist<Entry> path;
  // What a step decides, or none when it entered a block not entered with
  // its values before.
  auto take = [&](const Step &step) -> std::optional<bool> {
    if (const bool *tail = std::get_if<bool>(&step))
      return *tail;
    const Edge &edge = std::get<Edge>(step);
    Entry entry = walk.enter(edge, liveness.getLiveIn(edge.dest));
    if (!path.push(entry))
      return false;
    walk.bind(entry);
    return std::nullopt;
  };
  if (std::optional<bool> tail = take(walkFrom(std::next(call->getIterator()), call->getBlock())))
    return *tail;
  while (std::optional<Entry> entry = path.pop())
    if (std::optional<bool> tail = take(walkFrom(entry->block->begin(), entry->block)))
      return *tail;
  // Each step decides or enters a block, so the walk returns above.
  return false;
}

} // namespace idr::conversion
