// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What each key's sum is: a box where a closure key is on a cycle of "a
// capture holds a value of that key", which only a cell can end, and a memo
// sum always, since two references share one cell; and its name, made from
// the key's content. Every key becomes a sum: none is refused.

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Labels.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Scc.h"
#include "idr/Transforms/Defunctionalize.h"

#include "mlir/IR/BuiltinOps.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/Support/raw_ostream.h"

#include <algorithm>
#include <string>

using namespace mlir;

namespace idr::defunctionalize {

namespace {

// The bytes a key's name is made from: its carrier as MLIR prints it, then
// each label, in name order, after a NUL.
std::string keyText(const Key &key) {
  std::string text;
  llvm::raw_string_ostream os(text);
  key.first.print(os);
  for (auto label : key.second.getAsRange<FlatSymbolRefAttr>())
    os << '\0' << label.getValue();
  return text;
}

} // namespace

// The keys a value of `type`, in a slot of `key`, holds without a cell in
// between: its own when it is a closure, and those of the fields of a data
// type it holds in place, transitively. A box, a suspension and an array
// are cells.
void Slots::holds(Type type, const Key &key, SmallVectorImpl<Key> &out,
                  llvm::DenseSet<DataType> &seen) const {
  if (isClosureType(type)) {
    out.push_back(key);
    return;
  }
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (!data || !data.hasBody() || !seen.insert(data).second)
    return;
  for (auto [tag, ctor] : llvm::enumerate(data.getCtors()))
    for (auto [i, field] : llvm::enumerate(ctor.fields))
      holds(field,
            isKeyed(field)
                ? fieldKey(data, static_cast<unsigned>(tag), static_cast<unsigned>(i))
                : Key(),
            out, seen);
}

// A closure key is boxed when it is on a cycle of its captures.
void Slots::decide() {
  llvm::DenseMap<Key, SmallVector<Key>> edges;
  SmallVector<Key> candidates;
  for (auto &[key, sum] : sums) {
    if (isLazy(key) || isEmpty(key))
      continue;
    candidates.push_back(key);
    for (auto label : key.second.getAsRange<FlatSymbolRefAttr>()) {
      const Signature &sig = signature(label.getAttr());
      for (unsigned i = 0, n = captures(label.getAttr(), key.first); i < n; ++i) {
        llvm::DenseSet<DataType> seen;
        holds(sig.type.getInput(i), sig.arguments[i], edges[key], seen);
      }
    }
  }
  for (const SmallVector<Key> &component :
       stronglyConnected<Key>(candidates, [&](Key key) { return edges.lookup(key); }))
    if (component.size() > 1 ||
        llvm::is_contained(edges.lookup(component.front()), component.front()))
      cyclic.insert(component.begin(), component.end());
}

// Each key's sum, made by name and without a body. A closure key's is
// named under `fn$`, a lazy key's under `lazy$`, which no Idris name holds;
// two keys on one name are the compiler's error, raised where the name is
// interned.
LogicalResult Slots::name() {
  ContentNames names;
  for (auto &[key, sum] : sums) {
    FailureOr<StringAttr> name =
        names.intern(module.getLoc(), isLazy(key) ? "lazy$" : "fn$", "sum", keyText(key));
    if (failed(name))
      return failure();
    sum = DataType::get(ctx, name->getValue());
  }
  return success();
}

unsigned Slots::numConstructors() const {
  unsigned count = 0;
  for (const auto &entry : sums)
    count += static_cast<unsigned>(entry.first.second.size());
  return count;
}

unsigned Slots::largestBoxedSum() const {
  unsigned largest = 0;
  for (const Key &key : cyclic)
    largest = std::max(largest, static_cast<unsigned>(key.second.size()));
  return largest;
}

} // namespace idr::defunctionalize
