// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Which keys become sums: those whose labels are known, not empty and fit
// the type, unless a value can reach the key only as a closure; boxed when
// the key is on a cycle of captures. Every lazy key whose labels are known,
// fit, and return into one key becomes a memo sum, a box. A lazy key left a
// suspension, or a closure key left a closure that a value may reach, is
// one the analysis could not convert.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Scc.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/IR/BuiltinOps.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/Twine.h"

using namespace mlir;

namespace idr::defunctionalize {

// Whether a value of `from` can be rebuilt as one of `to`. Into a slot no
// label reaches, and out of one no value is ever in, the move never runs.
bool Slots::canCoerce(const Key &from, const Key &to) const {
  return from == to || !isConverted(to) || unreached(from) || isEmpty(to) ||
         (isConverted(from) && within(from, to));
}

// Whether `key` can become a sum: its labels are known and fit its type. A
// closure's are not empty. A cell's labels return into its one `forced`
// field, so they return one key; a cell no label reaches is still a memo
// sum, so that no lazy type is left.
bool Slots::convertible(const Key &key) const {
  if (!key.second || !llvm::all_of(key.second.getAsRange<StringAttr>(),
                                   [&](StringAttr label) { return fits(label, key.first); }))
    return false;
  if (!isLazy(key))
    return !key.second.empty();
  return llvm::all_of(key.second.getAsRange<StringAttr>(), [&](StringAttr label) {
    return resultKey(label, 0) == forced(key);
  });
}

// The keys a value of `type`, in a slot of `key`, holds without a box in
// between.
void Slots::holds(Type type, const Key &key, SmallVectorImpl<Key> &out,
                  llvm::DenseSet<StringAttr> &seen) const {
  if (isClosureType(type)) {
    out.push_back(key);
    return;
  }
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (!data || !seen.insert(data.getName().getAttr()).second)
    return;
  DataOp decl = lookupData(table, data);
  if (!decl)
    return;
  for (CtorOp ctor : decl.getCtors())
    for (auto [i, field] : llvm::enumerate(ctor.getFieldTypes().getAsValueRange<TypeAttr>()))
      holds(field, fieldKey(data.getName().getAttr(), ctor.getSymNameAttr(), unsigned(i)), out,
            seen);
}

// A key is converted if it is convertible, and a closure's if it is on no
// cycle of "a capture holds"; a memo sum is a box, which ends any cycle.
// Then, to a fixpoint, a key stays a closure where a value can only come to
// it as a closure, and the labels of a closure keep its type's signature.
void Slots::decide() {
  llvm::DenseMap<Key, SmallVector<Key>> edges;
  SmallVector<Key> candidates;
  for (auto &[key, sum] : sums) {
    if (!convertible(key))
      continue;
    candidates.push_back(key);
    if (isLazy(key))
      continue;
    for (StringAttr label : key.second.getAsRange<StringAttr>()) {
      const Signature *sig = signature(label);
      for (unsigned i = 0, n = captures(label, key.first); i < n; ++i) {
        llvm::DenseSet<StringAttr> seen;
        holds(sig->type.getInput(i), sig->arguments[i], edges[key], seen);
      }
    }
  }
  for (const SmallVector<Key> &component :
       stronglyConnected<Key>(candidates, [&](Key key) { return edges.lookup(key); }))
    if (component.size() > 1 ||
        llvm::is_contained(edges.lookup(component.front()), component.front()))
      cyclic.insert(component.begin(), component.end());
  converted.insert(candidates.begin(), candidates.end());

  // A key leaves the converted set at most once, and leaving it only
  // changes the rules that mention it. Rescanning every flow for each key
  // walks the module once per key.
  llvm::SetVector<Key> dropped;
  auto keep = [&](const Key &key) {
    if (key.first && converted.erase(key))
      dropped.insert(key);
  };
  // A closure of `label` of `type` calls it with the type's arguments.
  auto seal = [&](StringAttr label, Type type) {
    const Signature *sig = signature(label);
    if (!type || !sig || sig->external || sig->arguments.size() < arity(type))
      return;
    for (size_t i = sig->arguments.size() - arity(type); i < sig->arguments.size(); ++i)
      keep(sig->arguments[i]);
    llvm::for_each(sig->results, keep);
  };
  auto sealAll = [&](const Key &key) {
    if (key.second)
      for (StringAttr label : key.second.getAsRange<StringAttr>())
        seal(label, key.first);
  };
  llvm::DenseMap<Key, SmallVector<unsigned>> flowsFrom, flowsTo, sourcesOf;
  for (auto [index, flow] : llvm::enumerate(flows)) {
    flowsFrom[flow.from].push_back(static_cast<unsigned>(index));
    flowsTo[flow.to].push_back(static_cast<unsigned>(index));
  }
  for (auto [index, source] : llvm::enumerate(sources))
    sourcesOf[source.second].push_back(static_cast<unsigned>(index));
  llvm::DenseMap<Key, SmallVector<ApplyOp>> appliesOf;
  for (ApplyOp apply : analysis.applies())
    appliesOf[values.lookup(apply.getCallee())].push_back(apply);
  // An apply of a closure passes closures and returns closures.
  auto sealApply = [&](ApplyOp apply) {
    for (Value arg : apply.getArgs())
      if (isClosureType(arg.getType()) && isConverted(values.lookup(arg)))
        sealAll(values.lookup(arg));
    for (Value value : apply.getResults())
      if (isClosureType(value.getType()))
        keep(values.lookup(value));
  };
  auto consequences = [&](const Key &key) {
    sealAll(key);
    if (auto at = sourcesOf.find(key); at != sourcesOf.end())
      for (unsigned index : at->second)
        seal(sources[index].first, sources[index].second.first);
    if (auto at = flowsTo.find(key); at != flowsTo.end())
      for (unsigned index : at->second) {
        const Flow &flow = flows[index];
        if (!isEmpty(flow.to) && isConverted(flow.from))
          sealAll(flow.from);
      }
    if (auto at = flowsFrom.find(key); at != flowsFrom.end())
      for (unsigned index : at->second) {
        const Flow &flow = flows[index];
        if (isConverted(flow.to) && !canCoerce(flow.from, flow.to))
          keep(flow.to);
      }
    if (auto at = appliesOf.find(key); at != appliesOf.end())
      llvm::for_each(at->second, sealApply);
  };
  // Functions that others may call keep their signatures.
  for (FuncOp fn : module.getOps<FuncOp>())
    if (!fn.isExternal() && analysis.escapes(fn))
      if (const Signature *sig = signature(fn.getSymNameAttr())) {
        llvm::for_each(sig->arguments, keep);
        llvm::for_each(sig->results, keep);
      }
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
  for (auto &[key, sum] : sums)
    if (!isConverted(key))
      sealAll(key);
  for (ApplyOp apply : analysis.applies())
    if (!isConverted(values.lookup(apply.getCallee())))
      sealApply(apply);
  for (size_t next = 0; next < dropped.size(); ++next)
    consequences(dropped[next]);

  // Closure sums and memo sums are numbered apart, each by first
  // appearance.
  unsigned closureSums = 0, memoSums = 0;
  for (auto &[key, sum] : sums) {
    if (!isConverted(key))
      continue;
    if (isLazy(key)) {
      sum = BoxType::get(ctx, FlatSymbolRefAttr::get(ctx, ("lazy$" + Twine(memoSums++)).str()));
      continue;
    }
    auto name = FlatSymbolRefAttr::get(ctx, ("fn$" + Twine(closureSums++)).str());
    sum = cyclic.contains(key) ? Type(BoxType::get(ctx, name)) : Type(DataType::get(ctx, name));
  }
}

// The lazy keys left suspensions and the closure keys left closures that a
// value may reach, each once with the op where the analysis lost its value,
// or else where it first appears, which every key has.
SmallVector<UnknownKey> Slots::unknownKeys() const {
  SmallVector<UnknownKey> out;
  // By op, once for suspensions and once for closures.
  llvm::DenseSet<Operation *> reported[2];
  for (auto &[key, sum] : sums) {
    bool lazy = isLazy(key);
    if (!key.first || isConverted(key) || (!lazy && isEmpty(key)))
      continue;
    Operation *at = lost.lookup(key);
    if (!at)
      at = firstSeen.lookup(key);
    if (reported[lazy].insert(at).second)
      out.push_back({at, lazy});
  }
  return out;
}

// The keys of closure type that stay closures: those no value reaches.
unsigned Slots::numClosures() const {
  return static_cast<unsigned>(llvm::count_if(sums, [&](const auto &entry) {
    return isClosureType(entry.first.first) && !isConverted(entry.first);
  }));
}

} // namespace idr::defunctionalize
