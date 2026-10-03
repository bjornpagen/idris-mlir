// idr.defunctionalize:decided: which keys become sums: those whose labels
// are known, not empty and fit the type, unless a value can reach the key
// only as a closure; boxed when the key is on a cycle of captures.
export module idr.defunctionalize:decided;

import idr.mlir;
import idr.dialect;
import idr.graph;

import :closures;
import :slots;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::defunctionalize {

// Which keys become sums, and which of those are boxed.
struct Decided : Slots {
  using Slots::Slots;

  bool isConverted(const Key &key) { return converted.contains(key); }

  // Whether a value of `from` can be rebuilt as one of `to`.
  bool canCoerce(const Key &from, const Key &to) {
    return from == to || !isConverted(to) || isEmpty(from) ||
           (isConverted(from) && within(from, to));
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

  // A key is converted if its labels are known, not empty and fit its
  // type, and it is on no cycle of "a capture holds". Then, to a fixpoint,
  // a key stays a closure where a value can only come to it as a closure,
  // and the labels of a closure keep its type's signature.
  void decide() {
    llvm::DenseMap<Key, SmallVector<Key>> edges;
    SmallVector<Key> candidates;
    for (auto &[key, sum] : keys) {
      if (!key.second || key.second.empty() ||
          !llvm::all_of(key.second.getAsRange<StringAttr>(),
                        [&](StringAttr label) { return fits(label, key.first); }))
        continue;
      candidates.push_back(key);
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
    auto seal = [&](StringAttr label, idr::FnType type) {
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
        if (!isConverted(flow.to) && isConverted(flow.from))
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

    unsigned n = 0;
    for (auto &[key, sum] : keys)
      if (isConverted(key)) {
        auto name = FlatSymbolRefAttr::get(ctx, ("fn$" + Twine(n++)).str());
        sum = cyclic.contains(key) ? Type(idr::BoxType::get(ctx, name))
                                   : Type(idr::DataType::get(ctx, name));
      }
  }
};

} // namespace idr::defunctionalize
