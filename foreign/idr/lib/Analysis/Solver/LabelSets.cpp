// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The label solve's sets, each held once (LabelGraph.h): a set is its
// members in label order, interned by them; a union of sets is made once
// per tuple of their ids, and is the largest of them, with no label copied,
// where that one holds the others.
#include "idr/Analysis/Solver/LabelGraph.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/STLForwardCompat.h"

#include <algorithm>

using namespace mlir;

namespace idr::labels {

// The empty set is id 0, and is never looked up by its members.
SetTable::SetTable() { sets.emplace_back(); }

SetId SetTable::intern(ArrayRef<Label> members) {
  if (members.empty())
    return SetId{};
  read += members.size();
  if (auto it = ids.find(members); it != ids.end())
    return it->second;
  ArrayRef<Label> kept = members.copy(storage);
  auto id = SetId(static_cast<std::uint32_t>(sets.size()));
  sets.push_back(kept);
  ids.try_emplace(kept, id);
  return id;
}

ArrayRef<Label> SetTable::members(SetId set) const { return sets[llvm::to_underlying(set)]; }

bool SetTable::within(SetId part, SetId whole) {
  ArrayRef<Label> in = members(whole);
  read += members(part).size();
  return llvm::all_of(members(part), [&](Label label) { return std::binary_search(in.begin(), in.end(), label); });
}

// The union of two or more distinct sets is the largest of them when it
// holds the others, and is made once per tuple of ids.
SetId SetTable::unite(footprint::Vector<SetId> &inputs) {
  llvm::erase(inputs, SetId{});
  llvm::sort(inputs);
  inputs.erase(std::unique(inputs.begin(), inputs.end()), inputs.end());
  if (inputs.empty())
    return SetId{};
  if (inputs.size() == 1)
    return inputs.front();
  if (auto it = unions.find(ArrayRef<SetId>(inputs)); it != unions.end())
    return it->second;
  SetId largest = *llvm::max_element(
      inputs, [&](SetId a, SetId b) { return members(a).size() < members(b).size(); });
  SetId result = largest;
  if (!llvm::all_of(inputs, [&](SetId part) { return part == largest || within(part, largest); })) {
    footprint::Vector<Label> all;
    for (SetId part : inputs)
      llvm::append_range(all, members(part));
    read += all.size();
    llvm::sort(all);
    all.erase(std::unique(all.begin(), all.end()), all.end());
    result = intern(all);
  }
  unions.try_emplace(ArrayRef<SetId>(inputs).copy(storage), result);
  return result;
}

} // namespace idr::labels
