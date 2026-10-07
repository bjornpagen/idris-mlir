// A record field, a take's field and a match case's argument are the
// component the constructor stored. Following that construction is how a
// length and the array it describes, kept as two fields, come to be
// related: the relation is the operands the constructor paired, not the
// type the record has.

module;

#include "mlir/IR/Dominance.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SmallVector.h"

export module idr.inbounds:components;

import idr.dialect;
import idr.mlir;
import :joins;

using namespace mlir;

namespace idr::inbounds {

namespace {

// Past this many values followed while walking one record, the rest fail:
// an answer is then only weaker.
constexpr unsigned walkLimit = 64;

// Erases `value` from `set` when destroyed, so a walk can visit it again
// on another branch.
struct Forget {
  DenseSet<Value> *set = nullptr;
  Value value;
  Forget(DenseSet<Value> &set, Value value) : set(&set), value(value) {}
  Forget(const Forget &) = delete;
  Forget &operator=(const Forget &) = delete;
  ~Forget() {
    if (set)
      set->erase(value);
  }
};

// A component of the record `record`: field `index` of constructor `ctor`.
struct Proj {
  Value record;
  StringAttr ctor;
  uint64_t index;
};

// `value` as a component of the record it was read from, or none when it
// was computed on its own. Views are the array under them, so a borrow of
// a field is that field.
std::optional<Proj> projectionOf(Value value) {
  std::optional<Component> component = componentOf(arrayRoot(value));
  if (!component)
    return std::nullopt;
  return Proj{component->record, component->ctor, component->index};
}

bool sameCtor(ConOp con, StringAttr ctor) { return con.getCtor().getLeafReference() == ctor; }

using Pair = std::pair<Value, Value>;

std::optional<SmallVector<Pair>> onePair(Value size, Value array) {
  SmallVector<Pair> pairs;
  pairs.push_back({size, array});
  return pairs;
}

// The pairs the two components of `record` hold by. `origin` is the
// record the reads came from; meeting it again is those reads.
std::optional<SmallVector<Pair>> pairFields(const Calls &calls, Value record, Value origin,
                                            const Proj &sizeProj, const Proj &arrayProj, Value size,
                                            Value array, DenseSet<Value> &seen) {
  record = arrayRoot(record);
  if (record.getDefiningOp<ub::PoisonOp>())
    return SmallVector<Pair>{};
  if (seen.contains(record))
    return record == origin ? onePair(size, array) : std::nullopt;
  if (auto con = record.getDefiningOp<ConOp>()) {
    OperandRange fields = con.getFields();
    if (!sameCtor(con, arrayProj.ctor) || sizeProj.index >= fields.size() ||
        arrayProj.index >= fields.size())
      return std::nullopt;
    return onePair(arrayRoot(fields[sizeProj.index]), arrayRoot(fields[arrayProj.index]));
  }
  std::optional<Join> join = joinOf(record, calls);
  if (!join || seen.size() >= walkLimit)
    return std::nullopt;
  seen.insert(record);
  Forget forget(seen, record);
  SmallVector<Pair> needs;
  for (Value in : join->incoming) {
    std::optional<SmallVector<Pair>> part =
        pairFields(calls, in, origin, sizeProj, arrayProj, size, array, seen);
    if (!part)
      return std::nullopt;
    needs.append(part->begin(), part->end());
  }
  return needs;
}

// The pairs `(size, array)` holds by, when `array` is the component
// `proj` of a record. Empty when the record is poison. None when some
// construction does not show the component.
std::optional<SmallVector<Pair>> expand(const Calls &calls, DominanceInfo &dominance, Value size,
                                        Value record, Value array, const Proj &proj,
                                        DenseSet<Value> &seen) {
  record = arrayRoot(record);
  Value origin = arrayRoot(proj.record);
  if (record.getDefiningOp<ub::PoisonOp>())
    return SmallVector<Pair>{};
  if (seen.contains(record))
    return record == origin ? onePair(size, array) : std::nullopt;
  // Both reads are of this same record: its two stored components are
  // paired, not the reads themselves.
  if (std::optional<Proj> sizeProj = projectionOf(size);
      sizeProj && sizeProj->ctor == proj.ctor && arrayRoot(sizeProj->record) == record &&
      record == origin) {
    DenseSet<Value> fields;
    return pairFields(calls, record, record, *sizeProj, proj, size, array, fields);
  }
  if (auto con = record.getDefiningOp<ConOp>()) {
    if (!sameCtor(con, proj.ctor) || proj.index >= con.getFields().size())
      return std::nullopt;
    return onePair(size, arrayRoot(con.getFields()[proj.index]));
  }
  std::optional<Join> recordJoin = joinOf(record, calls);
  if (!recordJoin || seen.size() >= walkLimit)
    return std::nullopt;
  seen.insert(record);
  Forget forget(seen, record);
  std::optional<Join> sizeJoin = joinOf(size, calls);
  SmallVector<Pair> needs;
  if (sizeJoin && sizeJoin->key == recordJoin->key &&
      sizeJoin->incoming.size() == recordJoin->incoming.size()) {
    for (auto [n, in] : llvm::zip_equal(sizeJoin->incoming, recordJoin->incoming)) {
      std::optional<SmallVector<Pair>> part = expand(calls, dominance, n, in, array, proj, seen);
      if (!part)
        return std::nullopt;
      needs.append(part->begin(), part->end());
    }
    return needs;
  }
  if (recordJoin->local && dominance.properlyDominates(size, recordJoin->owner)) {
    for (Value in : recordJoin->incoming) {
      std::optional<SmallVector<Pair>> part = expand(calls, dominance, size, in, array, proj, seen);
      if (!part)
        return std::nullopt;
      needs.append(part->begin(), part->end());
    }
    return needs;
  }
  return std::nullopt;
}

} // namespace

// `component` when `array` was read out of a record. `needs` is then the
// pairs that read holds by, empty for a poison record, and absent when a
// construction does not show the component.
export struct ComponentPairs {
  bool component = false;
  std::optional<SmallVector<std::pair<Value, Value>>> needs;
};

export ComponentPairs componentPairs(const Calls &calls, DominanceInfo &dominance, Value size,
                                     Value array) {
  std::optional<Proj> proj = projectionOf(array);
  if (!proj)
    return {};
  DenseSet<Value> seen;
  return {true, expand(calls, dominance, size, proj->record, array, *proj, seen)};
}

} // namespace idr::inbounds
