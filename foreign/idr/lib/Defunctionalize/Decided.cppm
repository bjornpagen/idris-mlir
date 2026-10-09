// idr.defunctionalize:decided: which keys become sums: those whose labels
// are known, not empty and fit the type, unless a value can reach the key
// only as a closure; boxed when the key is on a cycle of captures. Every
// lazy key whose labels are known, fit, and return into one key becomes a
// memo sum, a box. A lazy key left a suspension, or a closure key left a
// closure that a value may reach, is one the analysis could not convert.
export module idr.defunctionalize:decided;

import idr.mlir;
import idr.dialect;
import idr.graph;

import :closures;
import :moves;
import :slots;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::defunctionalize {

// A key the analysis could not convert: a suspension's (`lazy`) or a
// closure's, and the op where the analysis lost its value.
export struct UnknownKey {
  Operation *at;
  bool lazy;
};

// Which keys become sums, and which of those are boxed.
struct Decided : Moves {
  using Moves::Moves;

  llvm::DenseSet<Key> converted;
  llvm::DenseSet<Key> cyclic;

  bool isConverted(const Key &key) { return converted.contains(key); }

  // Whether a value of `from` can be rebuilt as one of `to`. Into a slot no
  // label reaches, the move never runs.
  bool canCoerce(const Key &from, const Key &to) {
    return from == to || !isConverted(to) || isEmpty(from) || isEmpty(to) ||
           (isConverted(from) && within(from, to));
  }

  // Whether `key` can become a sum: its labels are known and fit its type.
  // A closure's are not empty. A cell's labels return into its one `forced`
  // field, so they return one key; a cell no label reaches is still a memo
  // sum, so that no lazy type is left.
  bool convertible(const Key &key) {
    if (!key.second || !llvm::all_of(key.second.getAsRange<StringAttr>(),
                                     [&](StringAttr label) { return fits(label, key.first); }))
      return false;
    if (!isLazy(key))
      return !key.second.empty();
    return llvm::all_of(key.second.getAsRange<StringAttr>(), [&](StringAttr label) {
      return result(module.function(label), 0) == forced(key);
    });
  }

  // The keys a value of `type`, in a slot of `key`, holds without a box in
  // between.
  void holds(Type type, const Key &key, SmallVectorImpl<Key> &out,
             llvm::DenseSet<StringAttr> &seen) {
    if (isClosureType(type)) {
      out.push_back(key);
      return;
    }
    auto data = dyn_cast<idr::DataType>(idr::unrestricted(type));
    if (!data || !seen.insert(data.getName().getAttr()).second)
      return;
    auto decl = module.symbols.lookup<idr::DataOp>(data.getName().getAttr());
    if (!decl)
      return;
    for (idr::CtorOp ctor : decl.getCtors())
      for (auto [i, field] : llvm::enumerate(ctor.getFieldTypes().getAsValueRange<TypeAttr>()))
        holds(field, fields.lookup({data.getName().getAttr(), ctor.getSymNameAttr(), unsigned(i)}),
              out, seen);
  }

  // A key is converted if it is convertible, and a closure's if it is on no
  // cycle of "a capture holds"; a memo sum is a box, which ends any cycle.
  // Then, to a fixpoint, a key stays a closure where a value can only come
  // to it as a closure, and the labels of a closure keep its type's
  // signature.
  void decide() {
    llvm::DenseMap<Key, SmallVector<Key>> edges;
    SmallVector<Key> candidates;
    for (auto &[key, sum] : keys) {
      if (!convertible(key))
        continue;
      candidates.push_back(key);
      if (isLazy(key))
        continue;
      for (StringAttr label : key.second.getAsRange<StringAttr>()) {
        func::FuncOp fn = module.function(label);
        for (unsigned i = 0; i < captures(label, key.first); ++i) {
          llvm::DenseSet<StringAttr> seen;
          holds(fn.getArgumentTypes()[i], argument(fn, i), edges[key], seen);
        }
      }
    }
    for (const SmallVector<Key> &component : graph::stronglyConnected<Key>(
             candidates, [&](Key key) { return edges.lookup(key); }))
      if (component.size() > 1 || llvm::is_contained(edges.lookup(component.front()),
                                                      component.front()))
        cyclic.insert(component.begin(), component.end());
    converted.insert(candidates.begin(), candidates.end());

    bool changed = true;
    auto keep = [&](const Key &key) {
      if (key.first && converted.erase(key))
        changed = true;
    };
    // A closure of `label` of `type` calls it with the type's arguments.
    auto seal = [&](StringAttr label, Type type) {
      func::FuncOp fn = module.function(label);
      if (!type || !fn || fn.isExternal() || fn.getNumArguments() < arity(type))
        return;
      for (size_t i = fn.getNumArguments() - arity(type); i < fn.getNumArguments(); ++i)
        keep(argument(fn, static_cast<unsigned>(i)));
      llvm::for_each(results.lookup(fn.getOperation()), keep);
    };
    auto sealAll = [&](const Key &key) {
      if (key.second)
        for (StringAttr label : key.second.getAsRange<StringAttr>())
          seal(label, key.first);
    };
    // Functions that others may call keep their signatures.
    for (func::FuncOp fn : module.op.getOps<func::FuncOp>())
      if (!fn.isExternal() && (fn.isPublic() || module.escaping.contains(fn.getSymNameAttr()))) {
        for (unsigned i = 0; i < fn.getNumArguments(); ++i)
          keep(argument(fn, i));
        llvm::for_each(results.lookup(fn.getOperation()), keep);
      }
    while (changed) {
      changed = false;
      for (const Flow &flow : flows) {
        if (isConverted(flow.to) && !canCoerce(flow.from, flow.to))
          keep(flow.to);
        if (!isConverted(flow.to) && !isEmpty(flow.to) && isConverted(flow.from))
          sealAll(flow.from);
      }
      for (auto &[label, slot] : sources) {
        if (isConverted(slot) && !llvm::is_contained(slot.second, label))
          keep(slot);
        if (!isConverted(slot))
          seal(label, slot.first);
      }
      for (auto &[key, sum] : keys)
        if (!isConverted(key))
          sealAll(key);
      // An apply of a closure passes closures and returns closures.
      for (idr::ApplyOp apply : module.applies) {
        if (isConverted(values.lookup(apply.getCallee())))
          continue;
        for (Value arg : apply.getArgs())
          if (isClosureType(arg.getType()) && isConverted(values.lookup(arg)))
            sealAll(values.lookup(arg));
        for (Value value : apply.getResults())
          if (isClosureType(value.getType()))
            keep(values.lookup(value));
      }
    }

    // Closure sums and memo sums are numbered apart, each by first
    // appearance.
    unsigned closureSums = 0, memoSums = 0;
    for (auto &[key, sum] : keys) {
      if (!isConverted(key))
        continue;
      if (isLazy(key)) {
        sum = idr::BoxType::get(ctx, FlatSymbolRefAttr::get(ctx, ("lazy$" + Twine(memoSums++)).str()));
        continue;
      }
      auto name = FlatSymbolRefAttr::get(ctx, ("fn$" + Twine(closureSums++)).str());
      sum = cyclic.contains(key) ? Type(idr::BoxType::get(ctx, name))
                                 : Type(idr::DataType::get(ctx, name));
    }
  }

  // The lazy keys left suspensions and the closure keys left closures that a
  // value may reach, each once with the op where the analysis lost its
  // value, or else where it first appears.
  SmallVector<UnknownKey> unknownKeys() {
    SmallVector<UnknownKey> out;
    // By op, once for suspensions and once for closures.
    llvm::DenseSet<Operation *> reported[2];
    for (auto &[key, sum] : keys) {
      bool lazy = isLazy(key);
      if (!key.first || isConverted(key) || (!lazy && isEmpty(key)))
        continue;
      Operation *at = lost.lookup(key);
      if (!at)
        at = firstSeen.lookup(key);
      if (!at)
        at = module.op;
      if (reported[lazy].insert(at).second)
        out.push_back({at, lazy});
    }
    return out;
  }
};

} // namespace idr::defunctionalize
